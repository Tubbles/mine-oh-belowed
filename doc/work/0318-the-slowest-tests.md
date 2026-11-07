# 0318: The slowest tests

Status: todo (2026-11-07)

0316's measurement (`tmp/0316/test_times.tsv`, on a loaded machine): the whole suite is 664 s of wall time against 4345 s of summed test time on 8 threads, and the test binary took 75 s to compile at any selection on Odin dev-2026-09, 23 s on dev-2026-11a since 0315.

## Goal

The whole suite and every tier's compile take less time, and each test checks what it checks today.

## Controls

None.

## Change

- `test_the_hit_digs_the_crater_and_nothing_else` (346 s) is the tail. It starts at 318 s, since the runner sorts by name, and runs alone for the last 150 s. It checks every sample of the 125 loaded chunks at three spacings. Checking the chunks the crater reaches, and comparing the rest byte for byte with a copy, keeps "nothing else".
- The arrival tests (`run_arrival_test_world`, `arrival_test_bed`) re-run the 600 tick fall in 13 slow tests (626 s together). One fall shared per process, safe across the runner's threads and its memory tracking per test.
- A `-o:none` or `-debug` test build crashed LLVM on Odin dev-2026-09, while the game's `-debug` build compiles in 21 s. Retry it on dev-2026-11a, and use the faster build for the tiers if it compiles and the suite runs no slower.
- Each change is measured before and after with 0316's `build/test_times.tsv`.

## Verify

- The checks and the suite, with the same tests passing.
- The suite's wall time and the compile time before and after, on an idle machine.
