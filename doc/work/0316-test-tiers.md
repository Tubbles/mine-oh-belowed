# 0316: Test tiers and fewer full runs per item

Status: implementing (2026-11-07)

The user (2026-11-07): "is it time for us to split up into multiple test suites? Like quick, light, unit, integration, nightly, all? So we can iterate faster because we've shipped only one work item in roughly 12 hours now." The suite is 2202 tests in about 7.5 minutes on an idle machine, and about 25 minutes while other agents build. Each item runs it at least four times (the implementer, the verifier, a fix round, the main agent on `main`), and a cost report behind a define took a 35 minute `-o:speed` build in 0306.

## Goal

An item's stages iterate on tests that take seconds to a minute, and the whole suite runs as few times per item as still catches what it catches today.

## Controls

None.

## Change

- Measure first: each test's time, from the runner's state change log or a wrapper. Find the long poles and what they share, such as field generation, sessions, lockstep or the network.
- Tiers in `build.sh`:
  - quick: the tests a change touches, by name or by file;
  - unit: everything but the slow tier, the default for iterating;
  - slow: the integration tests the measurement names;
  - all: what CI runs;
  - nightly: the cost reports behind defines, `-o:speed` builds and the benchmarks, inside the 03:00 to 06:00 window.
- A test's tier is stated where the test is, and a test checks that every slow test is marked.
- The pipeline's runs (`CLAUDE.md`, Work flow):
  - the implementer iterates on quick and unit, and runs all once before reporting;
  - the verifier runs the tiers the diff touches and its own probes;
  - the main agent runs all once on `main` before the push;
  - CI runs all on every push, and the main agent checks it.
- Docs: `doc/build.md` (the tiers), `CLAUDE.md` (the stages' runs).

## Verify

- The per-test times before, and each tier's time after, on an idle machine.
- `all` runs the same 2202 tests as today's suite.
- `python3 tools/test_tiers_test.py` passes.

## Specification (design, 2026-11-07)

### Measured (main `dc031a8`, `taskset -c 8-15 nice -n 10`, 8 runner threads; per-test table `tmp/0316/test_times.tsv` in the main checkout)

The machine was not idle: a headless game left running from the 0307 worktree (pid 703419, `--tech-demo=bodies,,spring` on Xvfb `:96`, 8.5 hours, 380% CPU pinned to 8-15) shared the CPUs throughout, and another agent's `odin test` part of the time (loadavg 6.2 before, 13.4 after).

- Compile of the test binary (`-o:minimal`, the default): 74.5 s wall, 75.2 s user. LLVM code generation is 72.6 s of it on one core, since the game package is one module; parse and type check take 1.2 s, `./build.sh check` 3.7 s. Every tier pays the 75 s, whatever it selects: it is quick's floor.
- A `-o:none` or `-debug` test build crashes the compiler (signal 11 in LLVM's `DAGCombiner`) after about 25 s; the game's `-debug` build compiles in 20.9 s. The source does not compile on the newer Odin in `~/opt` (dev-2026-11, `render_atlas.odin:137`), so that is untested.
- `all`: 2202 tests, 664 s wall, 4345 s of summed test time. The slowest 10, 20, 50, 100 and 200 tests take 25, 40, 65, 84 and 94% of it.
- The tail: all 8 threads stay busy until 510 s. `test_the_hit_digs_the_crater_and_nothing_else` (346 s) starts at 318 s, since the runner sorts by name, and runs alone for the last 150 s.
- 237 tests take 1 s or more (4147 s, 95%). The other 1965 tests take 198 s in all, and run alone in 22.2 s at 8 threads (35.2 s while another agent's suite ran), 20.5 s at 16 and 31.1 s at 4. The default thread count (physical cores, 8) stays.
- What the long poles share: field world sessions ticked for hundreds of ticks in the unoptimised build. `make_field_test_game_content` appears in 76 of the 237 (68% of the time) and `tick_field_test_simulation` in 61. Two files hold 56%: `simulation_arrival_test.odin` (25 tests, 1313 s; most re-run the fall, `ARRIVAL_TEST_TICKS` 600, and some loop over spacings down to 333 mm) and `simulation_field_test.odin` (32 tests, 1124 s; two sessions hashed tick by tick, save round trips). The network and the sleeps (1 ms poll loops) are minor: `session_network_test.odin` totals 48 s.
- Run to run, a test's time varies by 0.67 to 2.2 times (10th to 90th percentile), at most 3.1 times. The slowest of the 1965 in four unit runs took 2.45 s. That sets the check's thresholds below.
- One file's tests (`belt_test.odin`, 12 tests) run in 0.4 s, so quick costs about 76 s.

### Decisions

- **Marker**: `@(test) // slow` on the attribute line, nothing else. Odin's runner knows only `pkg` and `name` per test (`Internal_Test`), selects by name only (`ODIN_TEST_NAMES` or the runtime `-tests:`), and has no exclusion. An attribute is ruled out: `-custom-attribute:slow` would be needed on every compile (check, check-windows, check-android, the flake, the editor), and the runner would ignore it anyway. A `when` gate would re-indent each test body. Renames or `_slow_test.odin` files would churn names and history. A comment costs one token per test and moves with the test.
- **Selection**: a lister reads the sources and gives the runner the tier's names as runtime `-tests:` arguments, 200 names each. The unit list is 97 KB, close to Linux's 128 KB limit for one argument. `build.sh` builds the binary with `odin build src -all-packages -build-mode:test` (the same `ODIN_TEST` and build mode as `odin test`, probed). The binary is run from the repository root. `all` passes no names, so it runs exactly what today's `odin test src -all-packages` runs.
- **Slow**: a test that takes 1 s or more in a pinned `all` run (the knee: 0.5 s would mark 129 more to save about 10 s of unit's 22 s; 2 s would leave unit about 32 s). The first marking is the 237 names in `tmp/0316/slow_candidates.txt` (main checkout).
- **The check that slow tests are marked**: build.sh's runs pipe the runner through a filter that times each test from the runner's state change lines (`-define:ODIN_TEST_LOG_STATE_CHANGES=true`, stamped on arrival; the runner's own timestamps have whole seconds). An unmarked test over 10 s fails the run. One over 3 s is named in a notice. 10 s is four times the worst unit test seen under load, so it does not flake; a test is marked from the times file at 1 s.
- **Report tests**: a test inside a file level `when NAME {` block, with `NAME :: #config(NAME, false)` declared in its package, runs only in nightly, which passes every such define (today `RELIEF_COST`; `GROUND_LOOK_COST` when 0307 lands). Any other enclosing `when` is refused, so no test silently drops out. `TEXTURE_PREVIEW` and `FIRE_FLICKER_DUMP` gate inside running tests and stay as they are.
- Bare `./build.sh test` stays `all`, so every existing reference keeps meaning the whole suite.
- `bench` gets nightly's guard (the window and the lock) and keeps its selection.
- Not in this item (Options below): speeding up the slow tests, and the `-o:none` crash.

### build.sh

- Header comment: replace the `test` and `bench` lines with
  `./build.sh test [all|unit|slow|quick] [files or tests] [flags]` (the tests of a tier, `all` by default; doc/build.md, Test tiers),
  `./build.sh nightly` (the report tests and the factory benchmark, optimised, 03:00 to 06:00 Europe/Stockholm under `~/benchmark.lock`),
  `./build.sh bench` (the factory benchmark only, the same guard).
- `run_test_tier()`, called as `run_test_tier <tier> [arguments...]`. It sorts the arguments: those starting with `-` are odin flags, the rest are selectors. It refuses a flag containing `ODIN_TEST_NAMES` with "name the tests with ./build.sh test quick" (exit 2). Then:
  - `set_platform_flags`;
  - for a tier other than `all`, `listing="$(python3 tools/test_tiers.py arguments "$tier" "${selectors[@]}")"` (`set -e` stops on its exit 2) and `mapfile -t names <<< "$listing"`;
  - `"$odin" build src -all-packages -build-mode:test "$collection" "${platform_flags[@]}" -define:ODIN_TEST_LOG_STATE_CHANGES=true "${flags[@]}" -out:"$repository_root/build/mine-oh-belowed-tests"`;
  - `"$repository_root/build/mine-oh-belowed-tests" "${names[@]}" 2>&1 | python3 tools/test_tiers.py filter "$tier"`, whose status `pipefail` carries.
  - Selectors given to `all`, `unit` or `slow` are refused (exit 2).
- `guard_benchmark <command> <expected minutes>` (the global rules, Heavy benchmarks), in a loop:
  - leave with exit 2 unless `TZ=Europe/Stockholm date +%H` is 03, 04 or 05, naming the hour;
  - try `(set -o noclobber; printf ... > "$HOME/benchmark.lock")` with the lines `pid=$$`, `started` (ISO 8601 UTC), `expected_minutes`, `cwd`, `project=mine-oh-belowed`, `command`, `session=${CLAUDE_CODE_SESSION_ID:-none}` and `note=` (keep the machine idle: an -o:speed build and timed runs); on success `trap 'rm -f "$HOME/benchmark.lock"' EXIT` and return;
  - otherwise read the lock's `pid`. If `kill -0` fails, print the lock, say it is stale, remove it and retry. Else print the lock and `sleep 60`.
- `nightly`: `guard_benchmark "./build.sh nightly" 45`, then `listing="$(python3 tools/test_tiers.py defines)"`, `defines=()` filled by `mapfile` only when the listing is not empty, then `run_test_tier nightly -o:speed "${defines[@]}"`.
- The case: `test)` shifts, sets `tier=all`, shifts a first argument that is `all`, `unit`, `slow` or `quick` into `tier`, and calls `run_test_tier "$tier" "$@"`, so `./build.sh test -define:X=true` stays `all`. `nightly) nightly ;;` and `bench) guard_benchmark "./build.sh bench" 40; run_tests -o:speed -define:ODIN_TEST_NAMES=game.test_factory_benchmark ;;` (`run_tests` stays for bench only). The usage line gains `nightly`.

### tools/test_tiers.py (new, Python 3, no dependencies, the style of `check_docs.py`)

The docstring names the tiers, the marker, `ODIN_TEST_LOG_STATE_CHANGES` and the exit codes, so `check_docs.py` finds the define's name. Constants: `NAMES_PER_ARGUMENT = 200`, `NOTICE_SECONDS = 3.0`, `FAILURE_SECONDS = 10.0`, `BENCHMARK_TEST = "game.test_factory_benchmark"`, `TIMES_PATH = "build/test_times.tsv"`. The root is the script's parent's parent. Pure procedures, then `main`:

- `line_admits_host(build_line: str) -> bool`: one `#+build` line for the Linux desktop. Commas separate alternatives, spaces separate the terms of a conjunction. A term `[!]os[:subtarget]` matches when os is `linux` and the subtarget is empty. A file is skipped unless every `#+build` line admits it. The forms in `src/` today: `linux`, `!windows`, `windows`, `!linux:android`, `linux:android`.
- `Listed_Test(name, path, line, tier, define)`, a `namedtuple`. name is `package.test_name`, from the file's `package` line. tier is `unit`, `slow` or `report`, and define is the gate for a report.
- `list_tests(root) -> list[Listed_Test]`: every `src/**/*.odin`. An `@(test)` line takes the next line's `test_\w+ :: proc` name. Column 0 with no comment is unit; exactly `@(test) // slow` is slow. Indented, the nearest `when NAME {` above at column 0 gives a report, provided `NAME :: #config(NAME, false)` is in the package. Any other comment on the line, a missing declaration, or another gate raises `Tier_Error("<path>:<line>: <what>")`.
- `select_tests(tier, tests, selectors, root) -> (names, notices)`:
  - `unit` and `slow` take their tier's names, in listing order;
  - `nightly` takes the reports plus `BENCHMARK_TEST`;
  - `quick` maps each selector:
    - a path to a file that holds tests gives its tests (any tier);
    - another `src/x.odin` gives its partner `src/x_test.odin`'s tests, or a notice "no partner test file" if there is none;
    - a path that does not exist, or is not `.odin`, gives a notice "skipped", so a deleted file in a diff passes;
    - a bare `test_x` or a `package.test_x` must match exactly one listed test.
  - An unknown name, or an empty result, raises `Tier_Error`.
- `runner_arguments(names) -> list[str]`: `-tests:` plus up to 200 comma joined names each, in order.
- `report_defines(tests) -> list[str]`: `-define:NAME=true` per distinct gate, sorted.
- `state_change(line) -> (name, state) | None`: matches `Test #\d+ (\S+) changed state to (\w+)\.` at the end of the line.
- `judge_run(tier, tests, times, missing, finished) -> (notices, problems)`, `times` mapping each finished test to its seconds:
  - a problem for each unmarked unit test (unit tier in the listing, or unlisted) at `FAILURE_SECONDS` or more: "unmarked and over 10 s: <name> (<s> s); mark it @(test) // slow (doc/build.md, Test tiers)";
  - a notice for those at `NOTICE_SECONDS` or more;
  - a problem per `missing` name (the runner's `No test found for the name:` lines);
  - for `all` when `finished` (the runner's `Finished ` line was seen), a problem for each name the listing has and the run lacks, and each the run has and the listing lacks, both ignoring reports.
- `main`:
  - `arguments <tier> [selectors]` prints the runner arguments, one per line, and the notices to stderr;
  - `defines` prints the report defines one per line;
  - `filter <tier>` reads `sys.stdin.buffer.readline()` in a loop. It stamps each line with `time.monotonic()`, prints and flushes every line except the state changes, writes `TIMES_PATH` (test, seconds, tier; slowest first), and prints the notices and problems prefixed `test tiers: `;
  - exit 0, 1 for problems, 2 for a `Tier_Error` (printed).

### tools/test_tiers_test.py (new, `unittest`, the pattern of `tools/motion_stats_test.py`; trees in `tempfile` directories)

- `test_build_lines_admit_the_linux_desktop`: true for `linux`, `!windows`, `!linux:android` and `windows, linux`; false for `windows`, `linux:android` and `!linux`.
- `test_tiers_are_listed_from_the_sources`: a tree holding `src/a_test.odin` (package `game`) with a plain test, a `// slow` test and a `when REPORT_COST {` block with its `#config` and an indented test; `src/b_test.odin` with `#+build windows` and a test; `src/leaf/leaf_test.odin` (package `leaf`) with a test. The tiers come out as unit `game.test_plain` and `leaf.test_leaf`, slow `game.test_heavy`, report `game.test_report_cost` with the define `REPORT_COST`; `b_test.odin`'s test is absent.
- `test_a_malformed_marker_or_gate_is_refused`: `@(test) //slow`, `@(test) // Slow` and an indented test under `when ODIN_OS == .Linux {` each raise `Tier_Error` naming the file and line.
- `test_quick_maps_files_and_names`:
  - `src/a.odin` gives `src/a_test.odin`'s three tests, slow and report included;
  - a bare and a qualified name resolve;
  - `src/c.odin` without a partner and a missing path give notices;
  - an unknown name and a selection that ends up empty raise.
- `test_unit_slow_and_nightly_select_their_tiers`: nightly is the report plus `BENCHMARK_TEST` when the listing holds it, and raises when it does not. `slow` with no marked test raises (empty).
- `test_runner_arguments_hold_two_hundred_names`: 450 names give 3 arguments of 200, 200 and 50, in order.
- `test_the_run_is_judged`:
  - an unmarked test at 12 s is a problem, at 4 s a notice, at 2 s nothing; a marked test at 12 s is nothing;
  - a `missing` name is a problem;
  - for `all`, a listed name that did not run and a run name that is not listed are problems, but not when `finished` is false, and never for reports.
- `test_state_changes_are_parsed`: the runner's line `[INFO ] --- [2026-11-07 08:47:44] Test #322 game.test_x changed state to Running.` gives `("game.test_x", "Running")`, and an ordinary log line gives `None`.

### The marks and the sources

- Append ` // slow` to the `@(test)` line of each of the 237 names in `tmp/0316/slow_candidates.txt` (absolute path in the main checkout), with a one-off script in the worktree's `tmp/`. A name that no longer exists is skipped and named in the report.
- `src/generation_planet_landforms_test.odin`, the comment above `RELIEF_COST`: the run line becomes `./build.sh test quick game.test_report_the_relief_cost -o:speed -define:RELIEF_COST=true`, "or in ./build.sh nightly". If 0307 has landed, its comment above `GROUND_LOOK_COST` (`world_field_ground_look_test.odin`, an `ODIN_TEST_NAMES` line the new `build.sh` refuses) gets the same change.

### Docs

- `doc/build.md`, build.sh:
  - in the code block, the `test` line becomes `./build.sh test [tier] [files or tests] [flags]  # the tests of a tier, all by default (Test tiers)`, and a `nightly` line joins `bench`;
  - the `test` bullet: the binary `build/mine-oh-belowed-tests` from `odin build src -all-packages -build-mode:test`, flags passed on, and the `-all-packages` reason kept. The `ODIN_TEST_NAMES` example goes, since quick names tests;
  - the `bench` bullet: the window and the lock.
- `doc/build.md`, a new `## Test tiers` after build.sh, one bullet each:
  - the five tiers, with what each runs;
  - the marker and the 1 s rule, with this item's figures (237 tests, 95% of the time, unit 22 s);
  - the lister and the `-tests:` arguments;
  - the run's checks (10 s fails, 3 s notice, a name the build lacks fails, `all` against the listing);
  - `build/test_times.tsv`;
  - report tests behind `when NAME {` and their run;
  - the 75 s compile floor (one module, one core) and `./build.sh check` for compile errors in 4 s.
- `doc/build.md`, CI: "the whole suite (the `all` tier)" in the `nix` row.
- `doc/architecture.md`, Testing, the first bullet: "`./build.sh test` runs ... in tiers ([build.md](build.md), Test tiers)".
- `doc/README.md`: the build.md entry adds "the test tiers".
- `CLAUDE.md`:
  - Implement: "iterates on `./build.sh test quick <files or tests>` and `./build.sh test unit`; before it reports runs `./build.sh check`, `./build.sh check-android`, the whole suite once (`./build.sh test`), ...". Add "marks `@(test) // slow` each test it added that `build/test_times.tsv` shows at 1 s or more ([doc/build.md](doc/build.md), Test tiers)" and "a fix round runs quick and unit, not the whole suite".
  - Verify: "runs `./build.sh test quick $(git diff --name-only HEAD~1 -- src)` (the tests of the files the diff touches) and its probes through quick, and the checks the implementer did not, not the whole suite, which the implementer ran on the same tree". The last clause becomes "the main agent's one run of the whole suite is the landing's on `main` (Streams and worktrees)".
  - Streams, Landing: "runs the whole suite once on `main` (`./build.sh test`), pushes, checks CI's run of the push (`gh run watch`), installs ...".
  - Parallelism: "never runs the game binary as a session, a preview, the benchmark or `./build.sh nightly`".

### Hand-back check lines that apply

- Tests never touch the machine's state: the Python tests use temporary trees. `build.sh` writes only `build/` and the lock, which it removes on exit.

### Cost per item (this session's load; compile 75 s each)

- Today: at least four full runs (implementer, verifier, fix round, main), 4 × (75 + 664 s), about 49 minutes, plus the implementer's iterations at 12 minutes each.
- After:
  - the implementer: quick at about 76 s and unit at about 97 s per iteration, and one full run (12.3 minutes);
  - the verifier: quick at about 76 s plus its probe rounds;
  - the fix round: quick and unit (about 3 minutes);
  - the main agent: one full run (12.3 minutes);
  - in all, two full runs, about 25 minutes, and CI.

### Options for the main agent (not this item)

1. `test_the_hit_digs_the_crater_and_nothing_else` (346 s):
   - it runs three spacings (1000, 500, 333 mm). At each it ticks to the hit, then checks every sample of the 125 loaded chunks against `impact_crater_sample`; by its log lines the last spacing's check took 76 s;
   - comparing only the chunks the crater reaches, and the rest byte for byte with the copy, would keep "nothing else"; the saving is not measured;
   - it sets the tail, so `all` could approach 545 s, the summed time over 8 threads.
2. A shared fixture for the arrival tests: `run_arrival_test_world` and `arrival_test_bed` re-run the 600 tick fall in 13 slow tests (626 s). A once-per-process save at the hit, loaded by each test, needs a lock across the runner's threads and care with its per-test memory tracking.
3. The `-o:none` crash: the game builds at `-debug` in 21 s against 75 s for the test binary, so a test build that compiles at `-o:none` would lower every tier's floor. The fix is either finding the procedure that trips LLVM or waiting for 0315's toolchain. How fast the tests run unoptimised is not measured.

### Questions for the main agent

1. The leftover headless game (pid 703419, from the 0307 worktree, 380% CPU on 8-15 for 8.5 hours) slows every pinned run: stop it?
2. The fix round's runs: quick and unit, with the landing's full run as the gate. A fix that breaks a slow test then costs a round at the landing. Accept, or keep a full run in the fix round?
3. Who runs nightly: the main agent inside the window, when an item's Verify asks for a report or the benchmark. Scheduling it would need a systemd timer, which is an install and the user's call.
4. Landing order against 0315, which edits `build.sh` (check-windows), `doc/build.md` (toolchain, CI) and `CLAUDE.md` (Stack); the hunks differ.

### Main agent's decisions (2026-11-07)

- The leftover game is stopped. It was the 0307 capture, hung on a field shader Mesa refused (0317).
- A fix round runs quick and unit. The landing's full run on `main` and CI's run of the push are the gate.
- Nightly is the main agent's, run inside the window when an item's Verify asks for a report or the benchmark. No timer.
- Landing order: 0307, then 0315, then this item, each rebased onto the one before. 0307 lands first, so this item changes its `GROUND_LOOK_COST` comment, and the slow marks cover 0307's tests by the 1 s rule from this item's own `all` run.
- The options (the crater test, a shared arrival fixture, the `-o:none` crash) are 0318.
