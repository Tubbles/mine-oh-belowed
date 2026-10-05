# 0192: A server's clock is held by a joiner that never catches up

Status: todo (2026-10-03, from 0190)

## Goal

A headless server with nobody playing stops its clock ticks while a joiner restores (0190: an unpaced tick needs the session alone, so the joiner can follow the records). A joiner that stays connected but never catches up (its set never completes, its machine is too slow) holds that clock until `NETWORK_TIMEOUT` drops it, and only if it goes silent; a joiner that keeps pinging holds it for good. A windowed host is unaffected (its own player paces the ticks).

## Change

- A spectator (a peer with `receives_records` and no player) that has not asked for its player within a bound (a restore budget in ticks or seconds, named in `game.sjson` or a constant in `session_network.odin`, say which and why) is dropped with a notice, on the server and on a windowed host alike.
- `doc/architecture.md` (Multiplayer, the join; Server) names the bound.

## Verify

- The build and check commands of 0168.
- Tests: a spectator that never asks is dropped after the bound and the server's clock runs again; one that asks in time is not.
