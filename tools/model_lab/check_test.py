#!/usr/bin/env python3
"""Tests of tools/model_lab/check.py (work item 0214): small labs written
into temporary directories, and the check's limits pinned to the game's
constants.

Usage: python3 tools/model_lab/check_test.py
"""

import math
import pathlib
import re
import sys
import tempfile
import unittest

LAB_TOOLS = pathlib.Path(__file__).resolve().parent
REPOSITORY_ROOT = LAB_TOOLS.parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))
sys.path.insert(0, str(LAB_TOOLS))

import check  # noqa: E402
from models import collision, records  # noqa: E402

CHEST = 'id = "test", model = "test", kind = "chest", footprint = {width = 2, depth = 2, height = 2}'
PUMP = 'motion = {kind = "pump", axis = "y", amplitude = -0.25, period_seconds = 0.6}'
# A cube's corners (1 based) for the faces of a box, as quads.
BOX_FACES = ((1, 2, 3, 4), (5, 8, 7, 6), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 8, 4), (5, 1, 4, 8))


def box_vertices(minimum, maximum):
    (x0, y0, z0), (x1, y1, z1) = minimum, maximum
    return [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]


def triangle_faces(quads, offset):
    """The quads split into triangles, the corners shifted by offset."""
    faces = []
    for a, b, c, d in quads:
        faces += [(a + offset, b + offset, c + offset), (a + offset, c + offset, d + offset)]
    return faces


class Obj:
    """An OBJ text built object by object."""

    def __init__(self):
        self.lines, self.count = [], 0

    def add(self, name, vertices, faces, material="stone"):
        self.lines.append(f"o {name}")
        self.lines += [f"v {x} {y} {z}" for x, y, z in vertices]
        self.lines.append(f"usemtl {material}")
        self.lines += ["f " + " ".join(str(corner) for corner in face) for face in faces]
        self.count += len(vertices)
        return self

    def box(self, name, minimum, maximum, material="stone"):
        return self.add(name, box_vertices(minimum, maximum), triangle_faces(BOX_FACES, self.count), material)

    def polygon(self, name, corners, material="stone"):
        """One face of corners vertices on a circle in the footprint."""
        vertices = [(0.5 * math.cos(2 * math.pi * index / corners), 1.0, 0.5 * math.sin(2 * math.pi * index / corners)) for index in range(corners)]
        face = tuple(self.count + index + 1 for index in range(corners))
        return self.add(name, vertices, [face], material)

    def text(self):
        return "\n".join(self.lines) + "\n"


def mtl_text(names):
    return "".join(f"newmtl {name}\nKd 0.5 0.5 0.5\n" for name in names)


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.lab = pathlib.Path(self.directory.name)
        (self.lab / "data" / "models").mkdir(parents=True)
        (self.lab / "lab.sjson").write_text('models = ["test"]\nmode = "model"\nbuilt_from = "test"\n')

    def tearDown(self):
        self.directory.cleanup()

    def write(self, record, obj, materials=("stone",)):
        (self.lab / "data" / "machines.sjson").write_text("machines = [\n\t{" + record + "}\n]\n")
        (self.lab / "data" / "models" / "test.obj").write_text(obj.text())
        (self.lab / "data" / "models" / "test.mtl").write_text(mtl_text(materials))
        return check.check_model(self.lab, "test")

    def test_a_box_in_its_footprint_passes(self):
        lines, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1, 2, 1)))
        self.assertEqual(problems, [])
        self.assertIn("body 12 triangles (cap 9600)", lines[0])

    def test_a_vertex_past_the_side_is_a_problem(self):
        _, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1.03, 2, 1)))
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith("x spans"), problems)
        _, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1.01, 2, 1)))
        self.assertEqual(problems, [])

    def test_below_the_ground_is_a_problem_and_above_the_top_is_not(self):
        _, problems = self.write(CHEST, Obj().box("body", (-1, -0.03, -1), (1, 2, 1)))
        self.assertEqual(len(problems), 1)
        _, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1, 5, 1)))
        self.assertEqual(problems, [])

    def test_object_names(self):
        _, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1, 2, 1)).box("lid", (-1, 1, -1), (1, 2, 1)))
        self.assertTrue(any("'lid'" in problem for problem in problems), problems)
        _, problems = self.write(CHEST, Obj().box("shell", (-1, 0, -1), (1, 2, 1)))
        self.assertTrue(any("no object named body" in problem for problem in problems), problems)

    def test_the_part_follows_the_motion(self):
        pump = CHEST + ", " + PUMP
        _, problems = self.write(pump, Obj().box("body", (-1, 0, -1), (1, 2, 1)))
        self.assertTrue(any("moves a part" in problem for problem in problems), problems)
        _, problems = self.write(pump, Obj().box("body", (-1, 0, -1), (1, 2, 1)).add("part", [(0, 2, 0), (0.1, 2, 0), (0, 2, 0.1)], [(9, 10, 11)]))
        self.assertEqual(problems, [])
        _, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1, 2, 1)).add("part", [(0, 2, 0), (0.1, 2, 0), (0, 2, 0.1)], [(9, 10, 11)]))
        self.assertTrue(any("no moving part" in problem for problem in problems), problems)

    def test_the_caps(self):
        _, problems = self.write(CHEST, Obj().polygon("body", 9603))
        self.assertTrue(any("body has 9601 triangles, over the sanity cap 9600" in problem for problem in problems), problems)
        _, problems = self.write(CHEST.replace('kind = "chest"', 'kind = "pod"'), Obj().polygon("body", 9603))
        self.assertEqual(problems, [])
        _, problems = self.write(CHEST + ", " + PUMP, Obj().box("body", (-1, 0, -1), (1, 2, 1)).polygon("part", 603))
        self.assertTrue(any("part has 601 triangles" in problem for problem in problems), problems)

    def test_the_materials(self):
        names = [f"material_{index}" for index in range(9)]
        obj = Obj()
        for name in names:
            obj.box("body", (-1, 0, -1), (1, 2, 1), name)
        _, problems = self.write(CHEST, obj, names)
        self.assertTrue(any("9 materials" in problem for problem in problems), problems)
        _, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1, 2, 1), "glass"))
        self.assertTrue(any("material glass is not in the .mtl" in problem for problem in problems), problems)

    def test_an_iris_out_of_bounds_is_a_problem(self):
        record = 'id = "test", model = "test", kind = "hatch", footprint = {width = 1, depth = 2, height = 2}, motion = {kind = "iris", axis = "x", blades = 20, pivot = [0.5, 1, 1], hinge = [0.5, 1.85, 1], amplitude = 0.15, period_seconds = 0.15}'
        obj = Obj().box("body", (-0.5, 0, -1), (0.5, 0.1, 1)).box("part", (-0.05, 1.8, -0.05), (0.05, 1.9, 0.05))
        lines, problems = self.write(record, obj)
        self.assertTrue(any("blades 20" in problem for problem in problems), problems)
        self.assertTrue(any(line.startswith("iris: 20 blades") for line in lines), lines)

    def test_collision_volumes(self):
        machine = records.read_machine({"id": "test", "model": "test", "kind": "chest", "footprint": {"width": 2, "depth": 2, "height": 2}})
        path = self.lab / "data" / "models" / f"test{collision.FILE_SUFFIX}"
        inside = collision.Collision(machine)
        inside.box((-0.5, -0.5, 0.0), (0.5, 0.5, 1.0))
        collision.write(inside, path)
        lines, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1, 2, 1)))
        self.assertIn("collision: 1 volumes (limit 64)", lines)
        self.assertEqual(problems, [])
        outside = collision.Collision(machine)
        outside.box((-0.5, -0.5, 0.0), (1.5, 0.5, 1.0))
        collision.write(outside, path)
        _, problems = self.write(CHEST, Obj().box("body", (-1, 0, -1), (1, 2, 1)))
        self.assertIn("volume 0 leaves the footprint plus 0.02", problems)

    def test_the_limits_are_the_games(self):
        sources = "".join((REPOSITORY_ROOT / "src" / name).read_text() for name in ("model_check.odin", "machine.odin", "model_motion.odin"))

        def game(name):
            match = re.search(rf"^{name} :: ([0-9.]+)", sources, re.MULTILINE)
            self.assertIsNotNone(match, name)
            return float(match.group(1))

        self.assertEqual(check.BODY_TRIANGLES_CAP, game("MODEL_BODY_TRIANGLES_CAP"))
        self.assertEqual(check.POD_BODY_TRIANGLES_CAP, game("MODEL_POD_BODY_TRIANGLES_CAP"))
        self.assertEqual(check.PART_TRIANGLES_CAP, game("MODEL_PART_TRIANGLES_CAP"))
        self.assertEqual(check.MATERIAL_LIMIT, game("MODEL_MATERIAL_LIMIT"))
        self.assertEqual(check.TOLERANCE, game("MODEL_FOOTPRINT_TOLERANCE_CELLS"))
        self.assertEqual(check.IRIS_BLADES, (game("MINIMUM_IRIS_BLADES"), game("MAXIMUM_IRIS_BLADES")))
        self.assertEqual(check.IRIS_AMPLITUDE_MAXIMUM, game("MAXIMUM_IRIS_AMPLITUDE"))


if __name__ == "__main__":
    unittest.main()
