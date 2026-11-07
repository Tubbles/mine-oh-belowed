#!/usr/bin/env python3
"""Tests of tools/test_tiers.py (work item 0316): the lister on source
trees written into temporary directories, the selections, the runner
arguments and the judging of a run.

Usage: python3 tools/test_tiers_test.py
"""

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import test_tiers  # noqa: E402

A_TEST = """package game

import "core:testing"

@(test)
test_plain :: proc(t: ^testing.T) {
}

@(test) // slow
test_heavy :: proc(t: ^testing.T) {
}

REPORT_COST :: #config(REPORT_COST, false)

when REPORT_COST {
	@(test)
	test_report_cost :: proc(t: ^testing.T) {
	}
}
"""

B_TEST = """#+build windows
package game

import "core:testing"

@(test)
test_windows_only :: proc(t: ^testing.T) {
}
"""

LEAF_TEST = """package leaf

import "core:testing"

@(test)
test_leaf :: proc(t: ^testing.T) {
}
"""

PLAIN_HEADER = """package game

import "core:testing"

"""


def write_tree(root, files):
    for relative, text in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def sample_tree(root):
    write_tree(root, {
        "src/a_test.odin": A_TEST,
        "src/a.odin": "package game\n",
        "src/b_test.odin": B_TEST,
        "src/c.odin": "package game\n",
        "src/leaf/leaf_test.odin": LEAF_TEST,
    })
    return test_tiers.list_tests(root)


def tiers(tests):
    return {test.name: (test.tier, test.define) for test in tests}


class TestTiersTest(unittest.TestCase):
    def test_build_lines_admit_the_linux_desktop(self):
        for line in ("linux", "!windows", "!linux:android", "windows, linux"):
            self.assertTrue(test_tiers.line_admits_host(line), line)
        for line in ("windows", "linux:android", "!linux"):
            self.assertFalse(test_tiers.line_admits_host(line), line)

    def test_tiers_are_listed_from_the_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            tests = sample_tree(pathlib.Path(temporary))
        self.assertEqual(tiers(tests), {
            "game.test_plain": ("unit", None),
            "game.test_heavy": ("slow", None),
            "game.test_report_cost": ("report", "REPORT_COST"),
            "leaf.test_leaf": ("unit", None),
        })
        self.assertNotIn("game.test_windows_only", tiers(tests))

    def test_a_malformed_marker_or_gate_is_refused(self):
        cases = {
            "@(test) //slow\ntest_x :: proc(t: ^testing.T) {\n}\n": 5,
            "@(test) // Slow\ntest_x :: proc(t: ^testing.T) {\n}\n": 5,
            "when ODIN_OS == .Linux {\n\t@(test)\n\ttest_x :: proc(t: ^testing.T) {\n\t}\n}\n": 6,
        }
        for body, line in cases.items():
            with tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary)
                write_tree(root, {"src/d_test.odin": PLAIN_HEADER + body})
                with self.assertRaises(test_tiers.Tier_Error) as raised:
                    test_tiers.list_tests(root)
                self.assertIn(f"src/d_test.odin:{line}:", str(raised.exception), body)

    def test_a_gate_without_its_declaration_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            body = "when UNDECLARED {\n\t@(test)\n\ttest_x :: proc(t: ^testing.T) {\n\t}\n}\n"
            write_tree(root, {"src/d_test.odin": PLAIN_HEADER + body})
            with self.assertRaises(test_tiers.Tier_Error) as raised:
                test_tiers.list_tests(root)
            self.assertIn("src/d_test.odin:6:", str(raised.exception))

    def test_quick_maps_files_and_names(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            tests = sample_tree(root)
            # A path leaves its file's report test out, with a notice.
            for selector in ("src/a.odin", "src/a_test.odin"):
                names, notices = test_tiers.select_tests("quick", tests, [selector], root)
                self.assertEqual(names, ["game.test_plain", "game.test_heavy"])
                self.assertEqual(len(notices), 1)
                self.assertIn("game.test_report_cost", notices[0])
            # A name selects any tier, a report included.
            names, notices = test_tiers.select_tests("quick", tests, ["test_leaf", "game.test_heavy", "test_report_cost"], root)
            self.assertEqual(names, ["leaf.test_leaf", "game.test_heavy", "game.test_report_cost"])
            self.assertEqual(notices, [])
            names, notices = test_tiers.select_tests("quick", tests, ["src/c.odin", "src/gone.odin", "test_plain"], root)
            self.assertEqual(names, ["game.test_plain"])
            self.assertEqual(len(notices), 2)
            self.assertIn("src/c.odin: no tests of its own and no partner test file", notices)
            # Paths alone that select nothing are an empty selection.
            names, notices = test_tiers.select_tests("quick", tests, ["src/c.odin", "README.md"], root)
            self.assertEqual((names, len(notices)), ([], 2))
            with self.assertRaises(test_tiers.Tier_Error):
                test_tiers.select_tests("quick", tests, ["test_unknown"], root)
            with self.assertRaises(test_tiers.Tier_Error):
                test_tiers.select_tests("quick", tests, [], root)

    def test_unit_slow_and_nightly_select_their_tiers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            tests = sample_tree(root)
            self.assertEqual(test_tiers.select_tests("unit", tests, [], root)[0], ["game.test_plain", "leaf.test_leaf"])
            self.assertEqual(test_tiers.select_tests("slow", tests, [], root)[0], ["game.test_heavy"])
            with self.assertRaises(test_tiers.Tier_Error):
                test_tiers.select_tests("nightly", tests, [], root)
            benchmark = test_tiers.Listed_Test(test_tiers.BENCHMARK_TEST, "src/benchmark_test.odin", 1, "slow", None)
            names, _ = test_tiers.select_tests("nightly", tests + [benchmark], [], root)
            self.assertEqual(names, ["game.test_report_cost", test_tiers.BENCHMARK_TEST])
            unmarked = [test for test in tests if test.tier != "slow"]
            with self.assertRaises(test_tiers.Tier_Error):
                test_tiers.select_tests("slow", unmarked, [], root)
        self.assertEqual(test_tiers.report_defines(tests), ["-define:REPORT_COST=true"])

    def test_runner_arguments_hold_two_hundred_names(self):
        names = [f"game.test_{index}" for index in range(450)]
        arguments = test_tiers.runner_arguments(names)
        self.assertEqual([len(argument.removeprefix("-tests:").split(",")) for argument in arguments], [200, 200, 50])
        self.assertTrue(all(argument.startswith("-tests:") for argument in arguments))
        self.assertEqual(",".join(argument.removeprefix("-tests:") for argument in arguments), ",".join(names))

    def test_the_run_is_judged(self):
        with tempfile.TemporaryDirectory() as temporary:
            tests = sample_tree(pathlib.Path(temporary))
        notices, problems = test_tiers.judge_run("unit", tests, {"game.test_plain": 12.0}, [], True)
        self.assertEqual((len(notices), len(problems)), (0, 1))
        self.assertIn("game.test_plain", problems[0])
        notices, problems = test_tiers.judge_run("unit", tests, {"game.test_plain": 4.0}, [], True)
        self.assertEqual((len(notices), len(problems)), (1, 0))
        notices, problems = test_tiers.judge_run("unit", tests, {"game.test_plain": 2.0}, [], True)
        self.assertEqual((notices, problems), ([], []))
        notices, problems = test_tiers.judge_run("slow", tests, {"game.test_heavy": 12.0}, [], True)
        self.assertEqual((notices, problems), ([], []))
        _, problems = test_tiers.judge_run("quick", tests, {}, ["game.test_gone"], True)
        self.assertEqual(len(problems), 1)
        self.assertIn("game.test_gone", problems[0])
        whole = {"game.test_plain": 0.1, "game.test_heavy": 1.5, "game.test_extra": 0.1}
        _, problems = test_tiers.judge_run("all", tests, whole, [], True)
        self.assertEqual(sorted(problems), ["listed but did not run: leaf.test_leaf", "ran but is not listed: game.test_extra"])
        _, problems = test_tiers.judge_run("all", tests, whole, [], False)
        self.assertEqual(problems, [])
        complete = {"game.test_plain": 0.1, "game.test_heavy": 1.5, "leaf.test_leaf": 0.1}
        self.assertEqual(test_tiers.judge_run("all", tests, complete, [], True), ([], []))
        _, problems = test_tiers.judge_run("all", tests, dict(complete, **{"game.test_report_cost": 1.0}), [], True)
        self.assertEqual(problems, [])

    def test_state_changes_are_parsed(self):
        line = "[INFO ] --- [2026-11-07 08:47:44] Test #322 game.test_x changed state to Running.\n"
        self.assertEqual(test_tiers.state_change(line), ("game.test_x", "Running"))
        self.assertIsNone(test_tiers.state_change("[INFO ] --- [2026-11-07 08:47:44] [a_test.odin:3:test_x()] a log line\n"))


if __name__ == "__main__":
    unittest.main()
