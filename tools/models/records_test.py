#!/usr/bin/env python3
"""Tests of tools/sjson.py and tools/models/records.py (work item 0207):
golden values read by hand off data/machines.sjson as the game's
resolve_machine resolves them.

Usage: python3 tools/models/records_test.py
"""

import pathlib
import sys
import unittest

TOOLS_DIRECTORY = pathlib.Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = TOOLS_DIRECTORY.parent
sys.path.insert(0, str(TOOLS_DIRECTORY))

import sjson  # noqa: E402
from models import records  # noqa: E402

MACHINES = records.load_machines(REPOSITORY_ROOT / "data" / "machines.sjson")

EVERY_FORM = """// a line comment
bare = 1
"quoted key": 2.5
/* a block
   comment */ nested = {inner = [1, [2 3], {deep = true}] other: null}
text = "a\\"b\\\\c\\/d\\n\\t\\u0041"
negative = -3e2, last = false
"""


class SjsonTest(unittest.TestCase):
    def test_every_form(self):
        self.assertEqual(
            sjson.loads(EVERY_FORM),
            {
                "bare": 1,
                "quoted key": 2.5,
                "nested": {"inner": [1, [2, 3], {"deep": True}], "other": None},
                "text": 'a"b\\c/d\n\tA',
                "negative": -300.0,
                "last": False,
            },
        )
        self.assertIsInstance(sjson.loads("a = 7")["a"], int)
        self.assertEqual(sjson.loads("{a = 1}"), {"a": 1})

    def test_errors_name_the_line(self):
        with self.assertRaisesRegex(sjson.SjsonError, "line 2, column 1: duplicate key 'a'"):
            sjson.loads("a = 1\na = 2")
        with self.assertRaisesRegex(sjson.SjsonError, "line 3, column 1: unclosed array"):
            sjson.loads("a = [1\n2\n")


class RecordsTest(unittest.TestCase):
    def test_the_boiler_ports(self):
        boiler = MACHINES["boiler"]
        self.assertEqual([port.name for port in boiler.ports], ["input_water", "output_steam"])
        water, steam = boiler.ports
        self.assertEqual((water.cell, water.face), ((1, 0, 0), "negative_z"))
        self.assertEqual((steam.cell, steam.face), ((1, 0, 1), "positive_z"))
        self.assertEqual(records.port_face(boiler, records.port(boiler, "input_water")), ((0.0, 1.0, 0.5), (0.0, 1.0, 0.0)))
        with self.assertRaises(SystemExit):
            records.port(boiler, "output_water")

    def test_the_steam_engine_ports_take_a_number(self):
        self.assertEqual([port.name for port in MACHINES["steam_engine"].ports], ["input_steam", "input_steam_2"])

    def test_the_pod_open_cells(self):
        pod = MACHINES["pod"]
        boxes = [(box.first, box.last) for box in pod.open_cells]
        self.assertEqual(boxes, [((3, 0, 4), (6, 3, 5)), ((5, 0, 6), (6, 3, 7)), ((8, 0, 5), (9, 1, 6)), ((11, 0, 5), (11, 1, 6))])
        self.assertEqual(records.open_cell_box(pod, 0), ((-3.0, 0.0, 0), (1.0, 2.0, 4)))

    def test_the_pod_fixture_boxes(self):
        pod = MACHINES["pod"]
        self.assertEqual([fixture.machine for fixture in pod.fixtures], ["pod_hatch", "pod_hatch", "pod_locker", "crafting_bench", "oxygen_generator"])
        self.assertEqual(pod.fixtures[2].size, (2, 4, 1))
        self.assertEqual(records.fixture_box(pod, 0), ((4.0, -1.0, 0), (5.0, 1.0, 2)))
        self.assertEqual(records.fixture_box(pod, 2), ((-1.0, -3.0, 0), (1.0, -2.0, 4)))

    def test_motions_pivots_and_footprints(self):
        drill = MACHINES["burner_mining_drill"]
        motion = drill.motion
        self.assertEqual((motion.kind, motion.axis, motion.amplitude, motion.period_seconds), ("pump", "y", -0.25, 0.8))
        self.assertEqual(records.pivot(MACHINES["bore_drill"]), (0.0, 0.0, 0.0))
        furnace = MACHINES["stone_furnace"]
        self.assertEqual(furnace.footprint, records.Footprint(10, 10, 12))
        self.assertEqual(furnace.ports, ())
        self.assertEqual(records.machine_for_model(MACHINES, "arm").id, "burner_inserter")
        self.assertEqual(records.footprint_box(furnace), ((-5.0, -5.0, 0.0), (5.0, 5.0, 12.0)))

    def test_a_record_with_lights_reads(self):
        record = {"id": "room", "kind": "pod", "model": "room", "footprint": {"width": 3, "depth": 4, "height": 2}}
        lit = dict(record, lights=[{"position": [1.0, 2.0, 0.0], "color": [255, 180, 90], "radius_cells": 3, "clip": False}])
        self.assertEqual(records.read_machine(lit), records.read_machine(record))


if __name__ == "__main__":
    unittest.main()
