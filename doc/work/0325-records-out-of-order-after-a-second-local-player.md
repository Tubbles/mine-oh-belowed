# 0325: Records out of order after a second local player

Status: todo (2026-11-07)

CI run 42364333774 (the nix job, on a994f07) failed `test_a_joined_machine_adds_and_removes_a_local_player`: the host closed the joined machine's connection with "an input record for player 0 tick 245 out of order or out of range", 183 ticks after the machine's second local player joined at tick 62. The same code passed on the next run and locally (4.7 s). The check is `record_tick_expected` (`src/session_network.odin`). A host that drops a couch machine in split screen is a bug players meet, not only a flaky test.

## Goal

A joined machine with two local players never sends a record the host refuses, on any timing.

## Controls

None.

## Change

- Find which half of `record_tick_expected` refused the record (the order, `last_tick + 1`, or the bound over the host's tick) and why: the second player's records sharing the connection, the window, the frames the test runs, or the host's tick lagging the records it relays.
- Fix the cause in the client or the host, whichever sends or judges wrongly. A wider margin only if the bound itself is wrong, with the reason.
- A test that reproduces the refusal deterministically (a scripted order of frames or records), not by timing.

## Verify

- The checks and the suite, with the new test failing before the fix.
- `test_a_joined_machine_adds_and_removes_a_local_player` passes 50 runs in a row under load (`./build.sh test quick` with the test's name, several suites at once).
