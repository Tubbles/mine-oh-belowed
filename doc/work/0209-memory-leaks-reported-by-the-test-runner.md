# 0209: Fix the memory leaks the test runner reports

Status: todo (main agent, 2026-10-03: the 0204 verifier saw the test runner's leak warnings from the inventory, machine_wear and rtti tests, none from 0204's diff)

## Goal

`./build.sh test` passes but the tracking allocator of the test runner prints leak warnings for tests of the inventory, of machine wear (0201) and of the runtime type information. A leak in a test is a missing `delete` or `destroy` in the test itself or in the code it exercises; either way the warning hides the next real one.

## Change

- Run the suite and collect every leak line with its test name; for each, read the test and the code it calls, and free what is allocated (the test's fixtures through `defer`, or the code's own cleanup where a procedure allocates and never frees), never by switching the allocator.
- The log names any leak that turned out to be in game code rather than in a test.

## Verify

- `./build.sh test` prints no leak warning; the build and check commands of 0168.
