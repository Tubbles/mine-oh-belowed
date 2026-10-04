#!/usr/bin/env python3
"""Tests of tools/model_lab/model_lab.py (work item 0214): its pure
procedures against the shipped data/machines.sjson read as text and
small strings. Files go into temporary directories only.

Usage: python3 tools/model_lab/model_lab_test.py
"""

import pathlib
import re
import sys
import tempfile
import unittest

LAB_TOOLS = pathlib.Path(__file__).resolve().parent
REPOSITORY_ROOT = LAB_TOOLS.parent.parent
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))
sys.path.insert(0, str(LAB_TOOLS))

import model_lab  # noqa: E402
from models import records  # noqa: E402

MACHINES_TEXT = (REPOSITORY_ROOT / "data" / "machines.sjson").read_text()
MACHINES = records.load_machines(REPOSITORY_ROOT / "data" / "machines.sjson")

HAND_WRITTEN_BLOCK = """\t{
\t\tid = "thing"
\t\t// the cells it leaves
\t\topen_cells = [
\t\t\t{from = {x = 0, y = 0, z = 0}, to = {x = 1, y = 1, z = 1}}
\t\t]
\t\tmodel = "thing"
\t\t// a light
\t\t// over two lines
\t\tinterior_light_share = 0.25
\t\tfootprint = {width = 1, depth = 1, height = 1}
\t\t// an object
\t\tlights = {
\t\t\tposition = [0, 0, 0]
\t\t}
\t\tkind = "chest"
\t}
"""


def machine_with_motion(motion):
    return records.read_machine({"id": "thing", "model": "thing", "kind": "chest", "footprint": {"width": 2, "depth": 2, "height": 2}, "motion": motion})


def lab_machines_of(text):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "machines.sjson"
        path.write_text(text)
        return records.load_machines(path)


class ModelLabTest(unittest.TestCase):
    def test_parse_models(self):
        self.assertEqual(model_lab.parse_models("pod,pod_hatch"), ["pod", "pod_hatch"])
        for argument in ("", "pod,pod", "Pod"):
            with self.assertRaises(SystemExit):
                model_lab.parse_models(argument)

    def test_record_blocks(self):
        blocks = model_lab.record_blocks(MACHINES_TEXT, "model", "stone_furnace")
        self.assertEqual(len(blocks), 1)
        self.assertTrue(blocks[0].startswith("\t{\n"))
        self.assertTrue(blocks[0].endswith("\t}\n"))
        self.assertIn('id = "stone_furnace"', blocks[0])
        self.assertEqual(len(model_lab.record_blocks(MACHINES_TEXT, "model", "arm")), 5)
        self.assertEqual(model_lab.record_blocks(MACHINES_TEXT, "model", "no_such_model"), [])

    def test_stripped_block(self):
        stripped = model_lab.stripped_block(HAND_WRITTEN_BLOCK, model_lab.MODEL_ROUND_STRIPPED_KEYS)
        self.assertEqual(
            stripped,
            '\t{\n\t\tid = "thing"\n\t\tmodel = "thing"\n\t\tfootprint = {width = 1, depth = 1, height = 1}\n\t\tkind = "chest"\n\t}\n',
        )

    def test_lab_records_of_the_furnace(self):
        text = model_lab.lab_records_text(MACHINES_TEXT, ["stone_furnace"], model_lab.MODEL_ROUND_STRIPPED_KEYS, False)
        machines = lab_machines_of(text)
        self.assertEqual(len(machines), 1)
        self.assertEqual(machines["stone_furnace"].footprint, records.Footprint(10, 10, 12))
        self.assertNotIn("// Machine prototypes (work item 0011)", text)

    def test_lab_records_of_the_pod(self):
        text = model_lab.lab_records_text(MACHINES_TEXT, ["pod", "pod_hatch"], model_lab.MODEL_ROUND_STRIPPED_KEYS, False)
        machines = lab_machines_of(text)
        self.assertEqual(len(machines), 2)
        self.assertEqual((machines["pod"].open_cells, machines["pod"].fixtures), ((), ()))
        self.assertNotIn("lights = ", text)
        self.assertNotIn("interior_light_share = ", text)
        text = model_lab.lab_records_text(MACHINES_TEXT, ["pod", "pod_hatch"], model_lab.REWORK_ROUND_STRIPPED_KEYS, True)
        machines = lab_machines_of(text)
        pod = machines["pod"]
        self.assertEqual(len(pod.open_cells), 4)
        self.assertEqual(len(pod.fixtures), 5)
        self.assertEqual(pod.fixtures[2].size, (2, 4, 1))
        for identifier in ("pod_locker", "crafting_bench", "oxygen_generator"):
            self.assertIn(identifier, machines)
        self.assertNotIn("lights = ", text)

    def test_a_model_without_a_record_is_refused(self):
        with self.assertRaises(SystemExit):
            model_lab.lab_records_text(MACHINES_TEXT, ["no_such_model"], model_lab.MODEL_ROUND_STRIPPED_KEYS, False)

    def test_helper_modules(self):
        machines = REPOSITORY_ROOT / "tools" / "models" / "machines"
        self.assertEqual(model_lab.helper_modules((machines / "pod.py").read_text()), ["pod_geometry"])
        self.assertEqual(model_lab.helper_modules((machines / "stone_furnace.py").read_text()), [])
        self.assertEqual(model_lab.helper_modules("from . import a, b as c\nfrom .d import X\nfrom .. import kit\n"), ["a", "b", "d"])

    def test_stub_script(self):
        furnace = model_lab.stub_script(MACHINES["stone_furnace"])
        self.assertIn("kit.expect_footprint(machine, 10, 10, 12)", furnace)
        self.assertNotIn("join_part", furnace)
        drill = model_lab.stub_script(MACHINES["electric_mining_drill"])
        self.assertIn("kit.join_part(", drill)
        self.assertIn("machine)\n", drill)
        self.assertNotIn("records.pivot", drill)
        spin = model_lab.stub_script(machine_with_motion({"kind": "spin", "axis": "y", "amplitude": 1, "period_seconds": 2, "pivot": [1, 0, 1]}))
        self.assertIn("records.pivot(machine))", spin)
        iris = model_lab.stub_script(machine_with_motion({"kind": "iris", "axis": "x", "blades": 8, "pivot": [1, 1, 1], "hinge": [1, 1.8, 1], "amplitude": 0.15, "period_seconds": 0.15}))
        self.assertIn("records.hinge(machine)", iris)
        for text in (furnace, drill, spin, iris):
            compile(text, "stub", "exec")

    def test_registry_text(self):
        text = model_lab.registry_text(["pod", "pod_hatch"])
        compile(text, "registry", "exec")
        self.assertIn('"pod": pod.build', text)
        self.assertIn("COLLISIONS = {name: module.collision", text)
        compile(model_lab.registry_text(["pod"]), "registry", "exec")

    def test_fill_brief(self):
        with self.assertRaises(SystemExit):
            model_lab.fill_brief("a [[x]] b", {})
        with self.assertRaises(SystemExit):
            model_lab.fill_brief("a {{unknown}} b", {"models": "m"})
        self.assertEqual(model_lab.fill_brief("of {{models}}.", {"models": "`pod`"}), "of `pod`.")
        self.assertEqual(model_lab.fill_brief("no slots here", {"models": "m"}), "no slots here")

    def test_brief_slots(self):
        drill = {"electric_mining_drill": MACHINES["electric_mining_drill"]}
        slots = model_lab.brief_slots(drill, ["electric_mining_drill"], {})
        self.assertIn("3 by 3 by 3 cells", slots["size_and_frame"])
        self.assertIn("x from -1.5 to 1.5", slots["size_and_frame"])
        self.assertIn("at most 3200 triangles", slots["parts"])
        self.assertIn("at most 200 triangles", slots["parts"])
        self.assertIn("join_part(volumes, machine)", slots["parts"])
        self.assertIn("electric_mining_drill_front_left.png", slots["commands"])
        pod = {"pod": MACHINES["pod"]}
        self.assertIn("25600", model_lab.brief_slots(pod, ["pod"], {})["parts"])
        views = {"pod": [{"name": "inside_chair", "position": [0, 0, 1.2], "target": [2.5, 0, 0.9], "field_of_view_degrees": 80}]}
        self.assertIn("pod_inside_chair.png", model_lab.brief_slots(pod, ["pod"], views)["commands"])

    def test_the_template_fills(self):
        template = re.sub(r"\[\[[^\]]*\]\]", "word", (LAB_TOOLS / "brief_template.md").read_text())
        drill = {"electric_mining_drill": MACHINES["electric_mining_drill"]}
        brief = model_lab.fill_brief(template, model_lab.brief_slots(drill, ["electric_mining_drill"], {}))
        self.assertNotIn("{{", brief)
        self.assertNotIn("[[", brief)

    def test_lab_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            self.check_lab_directory(pathlib.Path(directory).resolve())

    def check_lab_directory(self, main):
        self.assertEqual(model_lab.lab_directory(None, "pod", main), main / "tmp" / "model_lab" / "pod")
        for argument in ("/tmp/x", str(main / "tmp"), str(main / "src"), str(main / ".claude" / "worktrees" / "0214")):
            with self.assertRaises(SystemExit):
                model_lab.lab_directory(argument, "pod", main)
        inside = main / ".claude" / "worktrees" / "0214" / "tmp" / "model_lab" / "pod"
        self.assertEqual(model_lab.lab_directory(str(inside), "pod", main), inside)

    def test_a_first_round_carries_no_record_comments(self):
        first = model_lab.lab_records_text(MACHINES_TEXT, ["pod", "pod_hatch"], model_lab.MODEL_ROUND_STRIPPED_KEYS, False)
        body = first.split("machines = [", 1)[1]
        self.assertNotIn("//", body)
        self.assertNotIn("(0221)", body)
        self.assertNotIn("slides 2 cells straight up", body)
        rework = model_lab.lab_records_text(MACHINES_TEXT, ["pod", "pod_hatch"], model_lab.REWORK_ROUND_STRIPPED_KEYS, True)
        self.assertIn("slides 2 cells straight up", rework)

    def test_tmp_and_the_labs_directory_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            main = pathlib.Path(directory).resolve()
            worktree_tmp = main / ".claude" / "worktrees" / "0214" / "tmp"
            for lab in (main / "tmp" / "model_lab", worktree_tmp, worktree_tmp / "model_lab", main / "tmp" / "labs" / "tmp"):
                with self.assertRaises(SystemExit, msg=str(lab)):
                    model_lab.lab_directory(str(lab), "pod", main)
            self.assertEqual(model_lab.lab_directory(str(main / "tmp" / "pod_lab"), "pod", main), main / "tmp" / "pod_lab")

    def test_replace_needs_the_lab_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            lab = pathlib.Path(directory)
            with self.assertRaises(SystemExit):
                model_lab.refuse_unbuilt_lab(lab)
            (lab / "lab.sjson").write_text("not = [sjson")
            with self.assertRaises(SystemExit):
                model_lab.refuse_unbuilt_lab(lab)
            (lab / "lab.sjson").write_text('models = ["pod"]\n')
            with self.assertRaises(SystemExit):
                model_lab.refuse_unbuilt_lab(lab)
            (lab / "lab.sjson").write_text(model_lab.lab_file_text(["pod"], "model", "0" * 40))
            model_lab.refuse_unbuilt_lab(lab)

    def test_unmentioned_images(self):
        self.assertEqual(model_lab.unmentioned_images("look at front.png", ["front.png", "back.png"]), ["back.png"])


if __name__ == "__main__":
    unittest.main()
