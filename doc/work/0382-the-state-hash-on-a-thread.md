# 0382: The state hash on a thread, alone or not

Status: todo (2026-11-12)

0345 took the state hash off a lone host only (`report_state_hash`, `session_alone`). A session of two or more still hashes on the frame, about 30 ms every 300 ticks at the profiled views, so multiplayer has a long frame every five seconds that single player has not. The user (2026-11-12): "I don't want there to be a difference on single player and multi player except network effects", and of the two ways `SUGGESTIONS.md` held for 0345, "the thread, design and implement".

## Goal

Every machine, alone or not, takes the hash the same way: a snapshot of what the hash reads between ticks, hashed on a thread, the report sent when the thread ends. No frame pays the hash, and `session_alone` no longer decides whether a machine hashes.

## Controls

None.

## Change

- The tick that is due copies what `simulation_state_hash` reads and starts the hash on a thread, as the save does since 0345 (`src/session_save.odin`). The report of that tick goes out when the thread has ended and is compared by its tick as today.
- A lone machine runs the same path and drops the result, so the frame's cost is the same alone and in a session.
- The copy is the part that stays on the frame. The design measures or bounds it against the hash it replaces and says how it stays small (what is copied whole, what is shared because nothing writes it between ticks).
- The hash's value for a state is what every machine of one version computes; whether it stays equal to today's is the design's to say.

## Verify

- The checks and the suite.
- A test that the thread's hash of a snapshot equals the direct hash of the same state, and a probe under the thread sanitizer with ticks running while the thread hashes.
- A session of two machines still reports a deliberate divergence, at the tick it was due.
- In the night window: the frame table shows no long tick and the hash's section (`.State_Hash`) at the copy's cost, for a lone host, which now runs the session's path.
