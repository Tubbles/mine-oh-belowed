# 0050 Headless factory benchmark

Status: todo
Milestone: M10

## Goal

The performance pass needs a repeatable measurement, not a feeling on the couch: a headless integration test that builds a large factory, runs it for minutes of simulated time and reports the cost per tick per system, with a budget that fails when the simulation cannot hold 60 ticks per second on the couch machine.

## Deliverables

- A procedural base builder (`src/benchmark_factory.odin`) that lays out a factory of a given size from the shipped data on a flat test world: mining lines (electric drills on veins, belts to steel furnaces with inserters), an assembly block (assemblers making gears, circuits and science packs from belted plates, labs researching), a fluid block (offshore pumps, boilers, steam engines, a refinery with cracking and a chemical plant on tar), a power grid of poles and substations, splitters and belt lifts, plus a launch pad fed by inserters. Size 1 is a phase 4 base (about 200 entities), size 4 about a thousand entities, size 16 several thousand with belts in the tens of thousands of items. The builder is deterministic and asserts that every machine works after a warm up.
- A benchmark runner as a test (`src/benchmark_test.odin`): builds each size, ticks 10 simulated minutes, measures wall time per tick overall and per system (entities by kind, belts, fluids, power, lighting and water queues, statistics, quests) with `time.tick_now`, and logs a table. The test fails when size 4 exceeds 8 milliseconds per tick on average, half the 60 Hz budget, so CI runners have room; the numbers for every size go to the log as the record.
- A command line `--benchmark=<size>` in the release build that runs the same measurement without a window and prints the table, so the couch machine's and the Steam Deck's numbers can be quoted. The Steam Deck is a supported target (user, 2026-09-27): size 4 must hold 60 ticks per second there with room for rendering, so its budget is the one that counts.
- `doc/architecture.md` gains the measurement method, and `doc/content.md` "Learned from couch tests" the first numbers.

## Verify

- Builds and tests pass; the benchmark test prints its table.
- User: `./build/mine-oh-belowed --benchmark=16` on the couch machine finishes and the average tick stays under 16 milliseconds.
