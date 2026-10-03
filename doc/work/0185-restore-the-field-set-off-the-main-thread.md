# 0185: Restore a loaded field world's set off the main thread

Status: implemented (M13 follow up, from the switch of 0179; before the phone plays a field world)

## Goal

Loading a field world shows no pause. Today `restore_field_chunks` (`simulation_field_save.odin`) generates every chunk of the saved set that is not in `field.bin` on the main thread before the first tick, 125 chunks at the shipped radius; a larger set or a slow phone shows it as a freeze on load.

The same restore broke a LAN join (2026-10-03, headless under Xvfb and llvmpipe): the joiner's `start_joined_session` spent 11 s generating the set without a frame, so it sent no keepalive and the host dropped it after `NETWORK_TIMEOUT` (10 s).

## Change

- The restore decodes the saved chunks on the main thread (cheap) and submits the rest as generation jobs to the field workers; the session's start waits in a loading state (the title's loading screen or a frame that draws it) until the set is complete, the same wait a tick does for arrivals (`field_chunks_ready`).
- The order of insertion stays deterministic (coordinate order), so the restored set and its hash equal the saved ones on every machine.
- `doc/architecture.md` (Save format, the field) updated.

## Verify

- The build and check commands of 0168.
- Tests: a restored set equals the saved one and hashes alike whichever order the jobs finish in; the main thread's part of a load of the shipped set is bounded by the decode of the saved chunks (measured in the test's log, no benchmark).
