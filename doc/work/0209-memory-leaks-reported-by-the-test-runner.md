# 0209: Fix the memory leaks the test runner reports

Status: todo (main agent, 2026-10-03: the 0204 verifier saw the test runner's leak warnings from the inventory, machine_wear and rtti tests, none from 0204's diff)

## Goal

`./build.sh test` passes but the tracking allocator of the test runner prints leak warnings for tests of the inventory, of machine wear (0201) and of the runtime type information. A leak in a test is a missing `delete` or `destroy` in the test itself or in the code it exercises; either way the warning hides the next real one.

## Change

- Run the suite and collect every leak line with its test name; for each, read the test and the code it calls, and free what is allocated (the test's fixtures through `defer`, or the code's own cleanup where a procedure allocates and never frees), never by switching the allocator.
- The log names any leak that turned out to be in game code rather than in a test.

## Verify

- `./build.sh test` prints no leak warning; the build and check commands of 0168.

## Specification (main agent, 2026-10-03)

The suite run of 2026-10-03 on `main` at 83391f9 (1641 tests) prints five `+++ leak` lines, each under a test, none under a session:

- `inventory.odin:27` `make_inventory()`, 176 B, under `test_a_pad_press_adds_a_viewport_and_a_player_at_the_start` and `test_two_local_members_keep_the_hash_of_one_member_machines`: an inventory made for a player who joins during the test (the pad press's second player, the second local member) is never destroyed. Find its owner (a player entry, a session state the test builds by hand) and free it through the owner's destroy procedure, deferred in the test; if the owner's destroy procedure skips the inventory, the leak is in game code and the free goes there.
- `machine_wear.odin:239` `record_operation()`, 16 B, under `test_a_steam_engine_breaks_on_the_tick_of_its_minutes` and `test_an_inserter_breaks_after_its_minutes_of_moving_and_not_while_idle`: `append(&entities.breakdowns, ...)` grows the breakdown list of an `Entities` the test builds; the test defers the entities' destroy as the other entity tests do, and if `destroy_entities` does not delete `breakdowns`, that is the leak in game code and the delete goes there.
- `core:flags` `internal_rtti.odin:449` `parse_and_set_pointer_by_type()`, 16 B, under `test_command_line_server_join_and_port`: the flags package allocates for a pointer or string typed field of the command line record while parsing the join and port flags. Find the field in the command line code, and free it after the parse the way the game's own start frees it; if the game never frees it either, add the free to the record's destroy (or write one) and name it in the log as a leak in game code.

Rules: each fix frees what was allocated through its owner, never an allocator switch, never `free_all`, never a changed assertion. The tests keep their names.

Tests: the suite prints no `+++ leak` line (`./build.sh test 2>&1 | grep -c '+++ leak'` prints 0). Docs: a destroy procedure that gains a delete updates its own comment; nothing else. Log: an entry in `doc/log/2026-10-03.md` only when a leak was in game code (its tags: tests, memory).

Hand-back lines that apply: tests never touch the state directory (unchanged by this item). The rest do not apply.

Verify: `./build.sh check`, `./build.sh check-android`, `./build.sh test` with no leak line, `python3 tools/check_docs.py`.
