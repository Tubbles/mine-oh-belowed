# 0190: The host keeps playing while a joiner restores

Status: todo (found landing 0188 on 2026-10-03, from the headless two game join; after 0185)

## Goal

A join does not freeze the host. Today `host_join` (`session_network.odin`) gives the joiner the tick after the frontier as its join tick and `lockstep_records_ready` (`lockstep.odin`) holds every tick from there until the joiner's record for it arrives, so the host's world stands still for the joiner's whole restore and catch up. Measured headless on 2026-10-03 (two games under llvmpipe, the shipped set): the joiner's restore took 11 s and the host's tick stayed at the join tick throughout; 0185 shortens the restore, it does not remove the wait, and a phone joining a couch will restore for seconds.

## Change

- The joiner's player is authored by the host until the joiner arrives: from the join tick the host stamps empty records for the joiner's player and relays them like any other, so the host and the other machines keep running. The joiner's own stamping starts at the first tick after the last record it was given (its arrival tick), announced to the host, which stops authoring from there; the handover tick is exact on both sides, so the hashes agree.
- The joiner's catch up (`catch_up_joined_session`, `loop.odin`) runs the authored empties as remote records, then plays from its arrival tick. The snapshot is unchanged; the records after it carry the empties.
- A joiner that never arrives leaves as a timed out client does today (`NETWORK_TIMEOUT`), and the host's world never waited for it.
- `doc/architecture.md` (Lockstep, the join) documents the authored window and the handover.

## Verify

- The build and check commands of 0168.
- Tests: a host runs ticks past the join tick before the joiner's first record exists; the joiner's handover tick equals the host's last authored tick plus one; `lockstep_state_hash` agrees on both sides after the handover; a joiner dropped during its restore leaves the host's tick count unaffected.
- Headless: the two game join of 0185's verify, with the host's tick read from the socket (`tools/moc`) during the joiner's restore, advancing.
