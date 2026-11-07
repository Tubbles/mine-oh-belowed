# 0325: Records out of order after a second local player

Status: verified (2026-11-07)

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
- `test_a_joined_machine_adds_and_removes_a_local_player` passes 50 runs in a row under load (the binary of `./build.sh test quick` run 50 times in each of four shells at once, Specification).

## Specification (design, 2026-11-07)

Cause: the range half of `record_tick_expected` (`src/session_network.odin:721`) bounds a client's record by the host's own tick, but a server's tick is no member: nobody waits for it, and the client runs on as soon as its records come back relayed. The second player's entry (tick 62) moves the simulated set to its spawn, both machines wait before tick 63 for those chunks (probe: `Host chunk stall before tick 63`, `Client chunk stall before tick 63`), and when the server's wait outlasts the client's by 183 ticks the record 62 + window 2 + `RECORD_TICK_MARGIN` 180 + 1 = 245 is refused. Both CI failures name 245 because the server sat at 62 in both; timing only decides whether its wait lasted that long (2.5 s on the runner). The order half held (both players left at 245, so `last_tick` was 244). The client is right; the host judges against a tick nothing paces.

Fix: a record past the bound is not refused but waits on the connection, with every message after it, until the host's tick catches up; the client's records stop coming back and its ticks wait (a hitch while the server's chunks come, not a drop). The order half stays a refusal. No message, save or network layout changes.

Code:
- `src/platform/network.odin`: `peek_message :: proc(connection: ^Network_Connection) -> (payload: []byte, ok: bool)`, the next whole message as a view into `received`, valid until the next take or poll, with take_message's length check (closing over `MAXIMUM_NETWORK_MESSAGE_SIZE`) moved into it. `take_message` becomes peek, copy into the allocator, `remove_range`; its behaviour is unchanged.
- `src/session_network.odin`:
  - `record_tick_expected :: proc(peer_player: Peer_Player, tick: u64) -> bool`: the order half only. handle_client_message's refusal reads "an input record for player %d tick %d out of order".
  - `record_tick_bound :: proc(peer_player: Peer_Player, window: int, host_tick: u64) -> u64`: `max(host_tick, joined_tick) + window + RECORD_TICK_MARGIN`, the old range half.
  - `record_waits_for_host :: proc(peer: Network_Peer, payload: []byte, host_tick: u64) -> bool`: reads the kind byte, then the tick (`u64`) and the player (`u32`) that `encode_input_record` writes first; true only for an `Input_Record` of one of the peer's players (`find_peer_player`) past `record_tick_bound`. Any other kind, a payload too short for the header, or a player the peer lacks gives false, so handle_client_message refuses those as today.
  - update_host_network's message loop: `peek_message`; when `record_waits_for_host(peer^, next, session.simulation.tick)`, close the connection with "too far ahead of the host (its waiting bytes passed the cap)" if `len(peer.connection.received) > MAXIMUM_CLIENT_BACKLOG_BYTES`, and stop taking this peer's messages this frame; else `take_message` and `handle_client_message` as now. The close falls through to the existing `!open` drop.
  - Comments: `MAXIMUM_CLIENT_BACKLOG_BYTES` (also caps a waiting client's received bytes), `RECORD_TICK_MARGIN` (how far a record may run past the host's tick before it waits; a server's tick may wait for its chunks), the comment above `record_tick_expected`.
- The cap never meets a client that follows the protocol: no record past the bound comes back while it waits, so its tick stops at the bound and it stamps at most window + 1 more per local player; pings and hash reports are small.

Tests (`src/session_network_test.odin`):
- `test_a_stalled_server_holds_a_joined_machine_instead_of_dropping_it`, `@(test) // slow`, with `run_stalled_server_frame :: proc(server: ^Server_State)` (the server's frame without ticks or streaming: `update_host_network` with the content run_server_frame builds) and `run_stalled_server_frames :: proc(server: ^Server_State, client: ^Frame_State, tick: u64, duration: time.Duration) -> bool` (stalled server frame, client frame, stalled server frame, 100 µs sleep; true once the client's tick reaches `tick`, false after `duration` or once the client lost the host). Steps: join as `test_a_joined_machine_adds_and_removes_a_local_player` does, `add_viewport`, a second more of `run_join_test_frames` so both entries exist (expect `player_count` 2); `stalled_tick` the host's tick, `bound := stalled_tick + window + RECORD_TICK_MARGIN`; stalled frames until the couch reaches `bound - window` (it has then stamped `bound + 1`), then one more second of them. Expect the host still at `stalled_tick`, one peer and the couch's host not lost (return when not, before indexing `peers[0]`), the couch at most at `bound`; then `run_join_test_frames` to `bound + STATE_HASH_INTERVAL_TICKS`, the host past that minus window + 1, `player_count` 2, no mismatch on either machine. It fails on main every run, since the test holds the host's tick: a probe dropped the machine at record 305 (host held at 122). It passes with a prototype of this fix (18 tests of the two network test files, 5 repeats).
- `test_a_client_record_out_of_order_or_too_far_ahead_is_refused` becomes `test_a_client_record_out_of_order_is_refused_and_one_too_far_ahead_waits`: the three order cases on `record_tick_expected`; `record_waits_for_host` on `record_message` payloads with a peer of window 3 and `{last_tick = 1000, joined_tick = 5}`: tick 1001 waits at host tick 10, not at `1001 - 3 - RECORD_TICK_MARGIN`; a record of player 4 (not the peer's) and a `Ping` never wait.
- `src/platform/network_test.odin`, `test_a_peeked_message_stays_until_taken`: on a closed `Network_Connection` with two framed messages in `received`, `peek_message` twice gives the first message and leaves `received` whole, then `take_message` gives the same bytes and the next peek the second; the oversized length test also covers `peek_message`.

Stress check (Verify): `./build.sh test quick` takes no repeat count. Build once with `taskset -c 8-15 nice -n 10 ./build.sh test quick test_a_joined_machine_adds_and_removes_a_local_player`, then in four shells at once `for run in $(seq 50); do taskset -c 8-15 nice -n 10 build/mine-oh-belowed-tests -tests:game.test_a_joined_machine_adds_and_removes_a_local_player || break; done` (each server takes its own loopback port).

Docs:
- `doc/architecture.md`, Multiplayer, the bullet "The host trusts no client's numbers": a record out of order drops the client; one further ahead of the host's tick than the client's window plus `RECORD_TICK_MARGIN` waits on the connection with every message after it until the host's tick catches up (a server whose tick waits for its chunks holds its clients there, 0325), and a client whose waiting bytes pass `MAXIMUM_CLIENT_BACKLOG_BYTES` is dropped.
- `doc/code_map.md`, the loop cluster's Tests line: `session_network_test.odin` adds "a stalled server holding a machine".

Hand-back check: a list that grows without bound is capped (the waiting bytes, above); a number parsed from bytes is only compared, never indexed.

### Decisions (main agent, 2026-11-07)

1. Holding, as designed: a server more than its clients' window plus `RECORD_TICK_MARGIN` behind paces them. Dropping the bound instead would let every machine's stored records grow while the server lags.
2. Why the server's chunk wait outlasted the client's by 2.5 s on the nix runner stays open; the fix makes the protocol hold under any such lag, which is the goal.
