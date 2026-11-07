#!/usr/bin/env python3
"""The test tiers of build.sh (work item 0316, doc/build.md, Test tiers).

The tiers:

- all: every test the build compiles, what CI runs
- unit: the tests marked neither slow nor report, the default for
  iterating
- slow: the tests marked `@(test) // slow`, those that take 1 s or more
- quick: the tests of the files (without their report tests) or the
  tests named
- nightly: the report tests and the factory benchmark

A test's tier is stated where the test is: `@(test)` at column 0 is unit,
exactly `@(test) // slow` is slow, and an indented `@(test)` inside a file
level `when NAME {` block, with `NAME :: #config(NAME, false)` declared in
its package, is a report that runs only with -define:NAME=true. Any other
comment on the attribute line or any other enclosing block is refused, so
no test silently drops out of a tier.

The runner selects by name only (ODIN_TEST_NAMES at compile time, or the
binary's runtime -tests: arguments), so the lister reads the sources and
prints the tier's names as -tests: arguments. The filter times each test
from the runner's state change lines (built with
-define:ODIN_TEST_LOG_STATE_CHANGES=true), stamped on arrival, fails an
unmarked test of 10 s or more, names one of 3 s or more, fails a name the
build lacks, checks a whole run of all against the listing, and writes
build/test_times.tsv.

Usage, from build.sh:
    python3 tools/test_tiers.py arguments <tier> [files or tests]
    python3 tools/test_tiers.py defines
    <test binary> ... 2>&1 | python3 tools/test_tiers.py filter <tier>

arguments prints no argument when the paths given to quick select no test
(the files of a diff that touches no tested source), and build.sh then
builds and runs nothing.

Exit codes: 0 fine, 1 a problem with the run, 2 a malformed mark, gate or
selection (printed).
"""

import collections
import pathlib
import re
import sys
import time

NAMES_PER_ARGUMENT = 200
NOTICE_SECONDS = 3.0
FAILURE_SECONDS = 10.0
BENCHMARK_TEST = "game.test_factory_benchmark"
TIMES_PATH = "build/test_times.tsv"
TIERS = ("all", "unit", "slow", "quick", "nightly")

ATTRIBUTE = re.compile(r"^(\s*)@\(test\)(.*)$")
DECLARATION = re.compile(r"^\s*(test_\w+)\s*::\s*proc\b")
PACKAGE = re.compile(r"^package\s+(\w+)", re.MULTILINE)
BUILD = re.compile(r"^#\+build\s+(.*)$", re.MULTILINE)
GATE = re.compile(r"^when (\w+) \{$")
TEST_NAME = re.compile(r"^(\w+\.)?test_\w+$")
STATE_CHANGE = re.compile(r"Test #\d+ (\S+) changed state to (\w+)\.$")
MISSING = re.compile(r'No test found for the name: "(.*)"')
FINISHED = re.compile(r"^Finished \d+ tests? in ")

Listed_Test = collections.namedtuple("Listed_Test", "name path line tier define")


class Tier_Error(Exception):
    pass


def repository_root():
    return pathlib.Path(__file__).resolve().parent.parent


def term_admits_host(term):
    """One term of a #+build line, [!]os[:subtarget], for the Linux
    desktop: linux with no subtarget."""
    negated = term.startswith("!")
    system, _, subtarget = term.lstrip("!").partition(":")
    return (system == "linux" and subtarget == "") != negated


def line_admits_host(build_line):
    """A #+build line's expression for the Linux desktop: commas separate
    alternatives, spaces the terms of a conjunction."""
    return any(
        all(term_admits_host(term) for term in alternative.split())
        for alternative in build_line.split(",")
    )


def gate_declared(directory, name, declarations):
    """Whether NAME :: #config(NAME, false) is in the package of the
    directory. The texts are read once per directory."""
    if directory not in declarations:
        declarations[directory] = "\n".join(
            path.read_text(errors="replace") for path in sorted(directory.glob("*.odin"))
        )
    declaration = re.compile(r"^%s :: #config\(%s, false\)" % (name, name), re.MULTILINE)
    return declaration.search(declarations[directory]) is not None


def enclosing_line(lines, index):
    """The nearest code line at column 0 above the index, or ""."""
    for line in reversed(lines[:index]):
        if line and not line[0].isspace() and not line.startswith("//"):
            return line.rstrip()
    return ""


def marked_tier(lines, index, place, directory, declarations):
    """The tier and gate of the @(test) line at the index."""
    indentation, trailing = ATTRIBUTE.match(lines[index].rstrip()).groups()
    if not indentation:
        if trailing == "":
            return "unit", None
        if trailing == " // slow":
            return "slow", None
        raise Tier_Error(f"{place}: the only mark is @(test) // slow, found '{lines[index].strip()}'")
    if trailing != "":
        raise Tier_Error(f"{place}: a report test takes no mark, found '{lines[index].strip()}'")
    enclosing = enclosing_line(lines, index)
    gate = GATE.match(enclosing)
    if gate is None:
        raise Tier_Error(f"{place}: an indented test sits under '{enclosing}', not a file level when NAME {{ block")
    name = gate.group(1)
    if not gate_declared(directory, name, declarations):
        raise Tier_Error(f"{place}: the package does not declare {name} :: #config({name}, false)")
    return "report", name


def file_tests(root, path, declarations):
    """The listed tests of one source file, none when its #+build lines
    exclude the Linux desktop."""
    text = path.read_text(errors="replace")
    if not all(line_admits_host(line) for line in BUILD.findall(text)):
        return []
    relative = path.relative_to(root).as_posix()
    package = PACKAGE.search(text)
    lines = text.split("\n")
    tests = []
    for index, line in enumerate(lines):
        if not ATTRIBUTE.match(line.rstrip()):
            continue
        place = f"{relative}:{index + 1}"
        declaration = DECLARATION.match(lines[index + 1]) if index + 1 < len(lines) else None
        if package is None or declaration is None:
            raise Tier_Error(f"{place}: @(test) is not followed by a test_ procedure in a package")
        tier, define = marked_tier(lines, index, place, path.parent, declarations)
        tests.append(Listed_Test(f"{package.group(1)}.{declaration.group(1)}", relative, index + 1, tier, define))
    return tests


def list_tests(root):
    """Every test under src/ the Linux desktop compiles, in path and line
    order."""
    declarations = {}
    tests = []
    for path in sorted((root / "src").rglob("*.odin")):
        tests += file_tests(root, path, declarations)
    return tests


def tests_of_path(root, tests, selector):
    """The tests a path selects, and the notices: a path that selects
    none, and the report tests it leaves out, since they run only with
    their define (a report is named to run)."""
    path = pathlib.Path(selector)
    if not path.is_absolute():
        path = root / path
    if not path.is_file() or path.suffix != ".odin" or not path.resolve().is_relative_to(root.resolve()):
        return [], [f"{selector}: skipped, no .odin file of the repository"]
    relative = path.resolve().relative_to(root.resolve()).as_posix()
    partner = pathlib.PurePosixPath(relative).with_name(path.stem + "_test.odin").as_posix()
    selected = [test for test in tests if test.path == relative] or [test for test in tests if test.path == partner]
    if not selected:
        return [], [f"{selector}: no tests of its own and no partner test file"]
    notices = [
        f"{selector}: leaves out the report test {test.name}, which runs by name with -define:{test.define}=true"
        for test in selected if test.tier == "report"
    ]
    return [test.name for test in selected if test.tier != "report"], notices


def tests_of_name(tests, selector):
    """The one listed test a bare or package qualified name selects."""
    if "." in selector:
        found = [test.name for test in tests if test.name == selector]
    else:
        found = [test.name for test in tests if test.name.split(".", 1)[1] == selector]
    if len(found) != 1:
        raise Tier_Error(f"{selector}: names {len(found)} listed tests, not one")
    return found


def quick_selection(tests, selectors, root):
    names = []
    notices = []
    for selector in selectors:
        if TEST_NAME.match(selector):
            selected = tests_of_name(tests, selector)
        else:
            selected, path_notices = tests_of_path(root, tests, selector)
            notices += path_notices
        names += [name for name in selected if name not in names]
    return names, notices


def select_tests(tier, tests, selectors, root):
    """The names a tier runs, in listing order, and the notices. Paths
    alone that select nothing (the files of a diff touching no tested
    source) are an empty selection, not an error."""
    if tier != "quick" and selectors:
        raise Tier_Error(f"{tier} takes no files or tests, name them with quick")
    notices = []
    if tier in ("unit", "slow"):
        names = [test.name for test in tests if test.tier == tier]
    elif tier == "nightly":
        if BENCHMARK_TEST not in (test.name for test in tests):
            raise Tier_Error(f"nightly: {BENCHMARK_TEST} is not listed")
        names = [test.name for test in tests if test.tier == "report"] + [BENCHMARK_TEST]
    elif tier == "quick":
        names, notices = quick_selection(tests, selectors, root)
    else:
        raise Tier_Error(f"{tier}: no such tier to select, the tiers are unit, slow, quick and nightly")
    if not names and not (tier == "quick" and selectors):
        raise Tier_Error(f"{tier}: no tests selected")
    return names, notices


def runner_arguments(names):
    return [
        "-tests:" + ",".join(names[start:start + NAMES_PER_ARGUMENT])
        for start in range(0, len(names), NAMES_PER_ARGUMENT)
    ]


def report_defines(tests):
    return [f"-define:{name}=true" for name in sorted({test.define for test in tests if test.tier == "report"})]


def state_change(line):
    match = STATE_CHANGE.search(line.rstrip())
    return (match.group(1), match.group(2)) if match else None


def judge_run(tier, tests, times, missing, finished):
    """The notices and problems of a run: times maps each finished test to
    its seconds, missing holds the names the build lacks, finished tells
    whether the runner printed its Finished line."""
    tier_of = {test.name: test.tier for test in tests}
    notices = []
    problems = []
    for name, seconds in sorted(times.items(), key=lambda item: -item[1]):
        if tier_of.get(name, "unit") != "unit":
            continue
        if seconds >= FAILURE_SECONDS:
            problems.append(f"unmarked and over {FAILURE_SECONDS:g} s: {name} ({seconds:.1f} s); mark it @(test) // slow (doc/build.md, Test tiers)")
        elif seconds >= NOTICE_SECONDS:
            notices.append(f"unmarked and over {NOTICE_SECONDS:g} s: {name} ({seconds:.1f} s), a test of 1 s or more is marked @(test) // slow (doc/build.md, Test tiers)")
    problems += [f"no test of that name in the build: {name}" for name in missing]
    if tier == "all" and finished:
        listed = {test.name for test in tests if test.tier != "report"}
        problems += [f"listed but did not run: {name}" for name in sorted(listed - times.keys())]
        problems += [f"ran but is not listed: {name}" for name in sorted(times.keys() - tier_of.keys())]
    return notices, problems


def write_times(root, tests, times):
    """build/test_times.tsv, slowest first, written beside and renamed
    over."""
    tier_of = {test.name: test.tier for test in tests}
    path = root / TIMES_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = ["test\tseconds\ttier"]
    for name, seconds in sorted(times.items(), key=lambda item: -item[1]):
        rows.append(f"{name}\t{seconds:.3f}\t{tier_of.get(name, 'unlisted')}")
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text("\n".join(rows) + "\n")
    temporary.replace(path)


def filter_run(tier, root):
    """Pass the runner's output through without its state change lines,
    then judge the run."""
    started = {}
    times = {}
    missing = []
    finished = False
    while True:
        raw = sys.stdin.buffer.readline()
        if not raw:
            break
        stamp = time.monotonic()
        text = raw.decode("utf-8", "replace")
        change = state_change(text)
        if change is None:
            sys.stdout.buffer.write(raw)
            sys.stdout.flush()
            missing += MISSING.findall(text)
            finished = finished or FINISHED.match(text) is not None
        elif change[1] == "Running":
            started[change[0]] = stamp
        elif change[0] in started:
            times[change[0]] = stamp - started.pop(change[0])
    tests = list_tests(root)
    write_times(root, tests, times)
    notices, problems = judge_run(tier, tests, times, missing, finished)
    for line in notices + problems:
        print(f"test tiers: {line}")
    return 1 if problems else 0


def run(arguments, root):
    command = arguments[0] if arguments else ""
    if command == "arguments" and len(arguments) >= 2:
        names, notices = select_tests(arguments[1], list_tests(root), arguments[2:], root)
        for notice in notices + ([] if names else ["quick: no tests selected"]):
            print(f"test tiers: {notice}", file=sys.stderr)
        if names:
            print("\n".join(runner_arguments(names)))
        return 0
    if command == "defines" and len(arguments) == 1:
        defines = report_defines(list_tests(root))
        if defines:
            print("\n".join(defines))
        return 0
    if command == "filter" and len(arguments) == 2 and arguments[1] in TIERS:
        return filter_run(arguments[1], root)
    raise Tier_Error("usage: test_tiers.py arguments <tier> [files or tests] | defines | filter <tier>")


def main():
    try:
        return run(sys.argv[1:], repository_root())
    except Tier_Error as error:
        print(f"test tiers: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
