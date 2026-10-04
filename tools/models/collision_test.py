#!/usr/bin/env python3
"""Tests of tools/models/collision.py (work item 0230): the Blender frame
to the file's, the file's text read back, and the lab's helpers.

Usage: python3 tools/models/collision_test.py
"""

import pathlib
import sys
import types
import unittest

TOOLS_DIRECTORY = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS_DIRECTORY))

import sjson  # noqa: E402
from models import collision  # noqa: E402

MACHINE = types.SimpleNamespace(model="test")


class CollisionTest(unittest.TestCase):
    def assert_angles(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for value, wanted in zip(actual, expected):
            self.assertAlmostEqual(value % 360, wanted % 360, places=6)

    def test_file_point(self):
        self.assertEqual(collision.file_point((1.0, 2.0, 3.0)), (1.0, 3.0, -2.0))

    def test_file_sector(self):
        # The door, Blender +X, is the file's +x: 90 degrees about y.
        self.assert_angles(collision.file_sector("Z", (12.6, 347.4)), (102.6, 77.4))
        # About X, Blender +Y (the start) is the file's -z, 270 about x.
        self.assert_angles(collision.file_sector("X", (0, 90)), (270, 0))
        # About Y the file's axis is turned over: the pair swaps.
        self.assert_angles(collision.file_sector("Y", (0, 90)), (0, 90))

    def test_file_volume_of_a_y_cone_swaps_its_ends(self):
        b = collision.Collision(MACHINE)
        b.cone((1, 2), -1, 3, 0.5, 0.25, axis="Y")
        entry = collision.file_volume(b.volumes[0])
        self.assertEqual(entry["axis"], "z")
        self.assertEqual(entry["from"], (1.0, 2.0, -3.0))
        self.assertEqual(entry["to"], (1.0, 2.0, 1.0))
        self.assertEqual((entry["radius_from"], entry["radius_to"]), (0.25, 0.5))

    def test_file_volume_of_a_box_sorts_its_corners(self):
        b = collision.Collision(MACHINE)
        b.box((0, -2, 0), (1, -1, 2))
        entry = collision.file_volume(b.volumes[0])
        self.assertEqual(entry, {"kind": "box", "from": (0.0, 0.0, 1.0), "to": (1.0, 2.0, 2.0)})

    def test_file_text_reads_back(self):
        b = collision.Collision(MACHINE)
        b.cylinder((0, 0), 0, 2.2, 5, shell=0.4, sector=(12.6, 347.4))
        b.box((-1, -1, 0), (1, 1, 2), shell=0.1)
        text = collision.file_text(b)
        self.assertEqual(text, collision.file_text(b))
        volumes = sjson.loads(text)["volumes"]
        self.assertEqual(len(volumes), 2)
        self.assertEqual(volumes[0]["kind"], "round")
        self.assertEqual(volumes[0]["axis"], "y")
        self.assertEqual(volumes[0]["from"], [0, 0, 0])
        self.assertEqual(volumes[0]["to"], [0, 2.2, 0])
        self.assertEqual((volumes[0]["radius_from"], volumes[0]["radius_to"], volumes[0]["shell"]), (5, 5, 0.4))
        self.assertEqual(volumes[0]["sector"], [102.6, 77.4])
        self.assertEqual(volumes[1], {"kind": "box", "axis": "y", "from": [-1, 0, -1], "to": [1, 2, 1], "shell": 0.1})

    def test_contains_a_cone_shell_over_its_sector(self):
        b = collision.Collision(MACHINE)
        b.cone((0, 0), 0, 2, 2, 1, shell=0.5, sector=(30, 330))
        entry = collision.file_volume(b.volumes[0])
        # The sector 30 to 330 leaves the gap round Blender +X, the file's
        # +x: the wall's radius there (1.5 at height 0.5) is open.
        self.assertFalse(collision.contains(entry, (1.5, 0.5, 0)))
        # Blender -X, in the wall at height 0.5 (outer radius 1.75).
        self.assertTrue(collision.contains(entry, (-1.5, 0.5, 0)))
        # In the hollow and outside the outer surface.
        self.assertFalse(collision.contains(entry, (-0.5, 0.5, 0)))
        self.assertFalse(collision.contains(entry, (-1.9, 0.5, 0)))
        minimum, maximum = collision.bounds(entry)
        self.assertEqual((minimum, maximum), ((-2.0, 0.0, -2.0), (2.0, 2.0, 2.0)))

    def test_wire_line_counts(self):
        b = collision.Collision(MACHINE)
        b.box((0, 0, 0), (1, 1, 1))
        b.cylinder((0, 0), 0, 1, 1)
        b.cylinder((0, 0), 0, 1, 1, shell=0.2)
        b.cylinder((0, 0), 0, 1, 1, shell=0.2, sector=(0, 180))
        counts = [len(collision.wire_lines(collision.file_volume(volume))) for volume in b.volumes]
        self.assertEqual(counts, [12, 52, 100, 56])

    def test_refusals(self):
        b = collision.Collision(MACHINE)
        with self.assertRaises(SystemExit):
            b.cylinder((0, 0), 0, 1, 1, shell=0.2, sector=(10, 10))
        for _ in range(collision.VOLUME_LIMIT):
            b.box((0, 0, 0), (1, 1, 1))
        with self.assertRaises(SystemExit):
            b.box((0, 0, 0), (1, 1, 1))
        self.assertEqual(b.count(), collision.VOLUME_LIMIT)


if __name__ == "__main__":
    unittest.main()
