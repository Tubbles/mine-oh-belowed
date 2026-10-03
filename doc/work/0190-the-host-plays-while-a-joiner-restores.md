# 0190: The host keeps playing while a joiner restores

Status: implemented (found landing 0188 on 2026-10-03, from the headless two game join; after 0185)

## Goal

A join does not freeze the host. Today `host_join` (`session_network.odin`) gives the joiner the tick after the frontier as its join tick and `lockstep_records_ready` (`lockstep.odin`) holds every tick from there until the joiner's record for it arrives, so the host's world stands still for the joiner's whole restore and catch up. Measured headless on 2026-10-03 (two games under llvmpipe, the shipped set): the joiner's restore took 11 s and the host's tick stayed at the join tick throughout; 0185 shortens the restore, it does not remove the wait, and a phone joining a couch will restore for seconds.

## Change

Built as a follower join (decision in `doc/log/2026-10-03.md`) instead of host authored empty records:

- The snapshot carries the world, the simulated chunk set, the members and the held records, but no player and no join tick (`encode_join_snapshot`, `host_join`). From the snapshot on the joiner gets every record and member change (`Network_Peer.receives_records`) and has no member, so no machine waits for it while it restores and runs the relayed ticks (`catch_up_joined_session`).
- Once its world is restored and no relayed tick is left to run (`joined_world_caught_up`), the joiner asks for its player once (`request_own_player`) through `Add_Local_Player`; the host takes the entry from the tick after the newest record relayed (`next_join`), announces the member and answers `Local_Player_Added`, which makes it the joiner's first local member. The host toasts the player count then.
- A host with a joiner restoring is not alone (`session_alone`), and a server with nobody playing holds its clock's ticks while one restores (`run_ready_ticks`), since an unpaced tick carries no record for the joiner to follow.
- A joiner that drops before it asked leaves nothing behind: no member, no entry, no tick waited for.
- `doc/architecture.md` (Multiplayer, Join) documents it.

## Verify

- The build and check commands of 0168.
- Tests: a host runs ticks past the snapshot tick before the joiner's first record exists; the joiner's entry is added at the tick both sides agree on and `lockstep_state_hash` agrees after it (`test_a_joiner_restores_while_the_others_play_and_reaches_their_hash`); a joiner dropped during its restore leaves the host's members and tick count unaffected (`test_a_joiner_dropped_while_it_restores_leaves_nothing_behind`); a second joiner arrives while the first restores (`test_a_second_joiner_arrives_while_the_first_restores`).
- Headless: the two game join of 0185's verify, with the host's tick read from the socket (`tools/moc`) during the joiner's restore, advancing.
