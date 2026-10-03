# 0191: A joiner restores a set the host holds only partly

Status: todo (review of 0185, 2026-10-03; needs a reproducing test first)

## Goal

A join never diverges from a host whose set was still arriving. `run_ready_ticks` (`lockstep.odin`) lets a host alone insert the chunks that have arrived while its tick waits for the rest, each through the arrival path with light seeding and water wake, and the comment above it says a joiner "takes the world as it is". The snapshot then carries a `chunk_set.chunks` ahead of the world's chunks: the joiner restores the whole set at once, without seeding (`restore_arrived_field_set`, 0185), while the host inserts the remaining chunks later as seeded arrivals. The light queues would differ from there and the hash reports would disagree. The old synchronous restore had the same gap; the review of 0185 found it and did not reproduce it.

## Change

- First a test: a host alone with half its set inserted takes a snapshot; a joiner restores it; both run the remaining arrivals; `simulation_state_hash` is compared. If it agrees, close this item with the reason in the log.
- If it differs, pick one of: the snapshot names which chunks of the set are in the world, and the joiner restores only those without seeding and takes the rest as arrivals as the host does; or a host does not answer a join until its set is complete (`host_join` refuses with a reason the joiner's toast shows, and the Multiplayer screen retries).
- `doc/architecture.md` (Lockstep, the join) says which.

## Verify

- The build and check commands of 0168.
- The test above, green for the chosen rule, with the hash compared after the host's remaining arrivals entered.
