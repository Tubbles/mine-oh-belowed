# 0316: Test tiers and fewer full runs per item

Status: todo (2026-11-07)

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
