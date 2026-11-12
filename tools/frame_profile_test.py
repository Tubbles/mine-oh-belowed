#!/usr/bin/env python3
"""Tests of tools/frame_profile.py (work item 0379): the runs of a view
that names a water model, the game's command for a model and when a run
starts a fresh game; the large factory's runs, copies and note (0347).
No game runs.

Usage: python3 tools/frame_profile_test.py
"""

import argparse
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import frame_profile  # noqa: E402

SPRING = {"name": "spring", "stand": [79.159, 150.561], "target": [79, 151], "target_height": 1}
SPRING_BODIES = dict(SPRING, name="spring_bodies", water_model="bodies")


def views_file():
    return {"frames": 600, "distances": [512], "viewports": [1, 2], "views": [SPRING, SPRING_BODIES], "factory": {}}


class FrameProfileTest(unittest.TestCase):
    def test_runs_of_another_water_model_come_last(self):
        views = views_file()
        arguments = argparse.Namespace(check=False, frames=None)
        plan = frame_profile.planned_runs(views, views["views"], True, [512], arguments)
        runs = plan["views_one"] + plan["views_two"] + plan["factory_two"] + plan["factory_one"] + plan["models"]
        self.assertEqual([(run["view"], run["viewports"]) for run in runs], [
            ("spring", 1),
            ("spring", 2),
            ("factory", 2),
            ("factory", 1),
            ("spring_bodies", 1),
            ("spring_bodies", 2),
        ])
        self.assertEqual([run["water_model"] for run in runs], [None, None, None, None, "bodies", "bodies"])

    def test_the_large_factory_runs_after_the_factory_in_one_viewport(self):
        views = views_file()
        arguments = argparse.Namespace(check=False, frames=None)
        plan = frame_profile.planned_runs(views, [], True, [512, 1024], arguments, factory_large=True)
        self.assertEqual([(run["view"], run["viewports"], run["distance"]) for run in plan["factory_large"]], [
            ("factory_large", 1, 512),
            ("factory_large", 1, 1024),
        ])
        self.assertEqual(frame_profile.planned_runs(views, [], True, [512], arguments)["factory_large"], [])

    def test_the_copies_are_range_checked(self):
        self.assertEqual(frame_profile.factory_copies_problem([11, 7]), "")
        self.assertEqual(frame_profile.factory_copies_problem([1, 32]), "")
        for copies in ([0, 7], [11, 33], [-1, 7], [11], [11, 7, 1], [11.5, 7], [True, 7], 11):
            self.assertNotEqual(frame_profile.factory_copies_problem(copies), "", copies)

    def test_the_shipped_copies_and_their_lines(self):
        shipped = frame_profile.sjson.load(frame_profile.repository_root() / "tools" / "frame_profile_views.sjson")
        factory, large = shipped["factory"], shipped["factory_large"]
        self.assertEqual(frame_profile.factory_copies_problem(large["copies"]), "")
        corner = (-34, 3, 36)
        corners = frame_profile.factory_copy_corners(corner, factory, large["copies"])
        self.assertEqual(len(corners), 76)
        self.assertNotIn(corner, corners)
        self.assertIn((-34 - 28, 3, 36), corners)
        self.assertIn((-34 - 10 * 28, 3, 36 + 6 * 20), corners)
        copied = frame_profile.copied_factory(factory, large)
        self.assertEqual(len(copied["machines"]), 8)
        lines = frame_profile.factory_lines(7, corners[0], copied)
        kinds = [frame_profile.placed_kind(line) for line in lines]
        self.assertEqual((kinds.count("foundation"), kinds.count("machine")), (468, 8))
        placed = {"foundation": 76 * 468, "machine": 76 * 8}
        self.assertEqual(
            frame_profile.factory_large_note(factory, large, placed),
            "placed 621 of 621 machines, 36036 of 36036 foundations",
        )
        target = frame_profile.factory_large_target_cells(corner, factory, large["copies"])
        self.assertEqual(target, ((-314 - 8) / 2, 4.5, (36 + 174) / 2))
        frame = {"origin": (0, 0, 0), "pitch": 0.5, "right": (1, 0, 0), "up": (0, 1, 0), "forward": (0, 0, 1)}
        self.assertEqual(frame_profile.factory_large_eye(frame, (10, 20, 30), large), (10, 45, -15))

    def test_the_game_command_names_the_water_model(self):
        directories = frame_profile.run_directories(pathlib.Path("/output"), "/run", 1)
        bodies = frame_profile.game_command(pathlib.Path("/game"), directories, False, "bodies")
        self.assertIn("--water-model=bodies", bodies)
        default = frame_profile.game_command(pathlib.Path("/game"), directories, False, None)
        self.assertFalse(any(argument.startswith("--water-model") for argument in default), default)

    def test_a_new_water_model_starts_a_game_without_counting_a_restart(self):
        bodies_run = frame_profile.new_run("spring_bodies", 1, 512, 600, "bodies")
        default_run = frame_profile.new_run("spring", 1, 512, 600)
        self.assertEqual(frame_profile.run_needs_start(frame_profile.new_game("bodies"), bodies_run, False), (False, False))
        self.assertEqual(frame_profile.run_needs_start(frame_profile.new_game(), default_run, False), (False, False))
        self.assertEqual(frame_profile.run_needs_start(frame_profile.new_game(), bodies_run, False), (True, False))
        self.assertEqual(frame_profile.run_needs_start(frame_profile.new_game("bodies"), default_run, False), (True, False))
        for game in (frame_profile.new_game(), frame_profile.new_game("bodies")):
            self.assertEqual(frame_profile.run_needs_start(game, bodies_run, True), (True, True))
            self.assertEqual(frame_profile.run_needs_start(game, default_run, True), (True, True))


if __name__ == "__main__":
    unittest.main()
