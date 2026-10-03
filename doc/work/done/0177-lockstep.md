# 0177: Lockstep multiplayer: tick stamped inputs, the host relay and the state hash

Status: implemented (2026-10-03; the twenty minute two machine run and the split screen pair wait for 0178 and 0179, and the slot transfers still write from the frame, see 0179)

## Goal

Several machines running one simulation: every player's input frame stamped with its tick and relayed through a host, a tick running when every player's inputs are in, a latency window from the measured round trip predicting only the local player's movement and camera, the state hash as the desync check, a joining player receiving the save, a headless server, the simulated chunk set derived in the tick, every write into the simulation a queued input (0167, Multiplayer: lockstep; decision 30; 0166).

## Change

- The queued writes of 0166 land here first: one player command list drained at the start of the tick, the screens' writes through it; chunk arrivals as a "chunk ready" event; the command socket's edits through the same list.
- The lockstep driver in the loop cluster (`lockstep.odin` with a line in the file table of `tools/code_graph.py`): per player per tick an input frame with the tick number; the local player's frames go to the host and the host relays every player's frames to everyone; the tick runs when every frame for it is present; the latency window in ticks, set at join from the round trip, inside which the local player's movement and camera run ahead on a copy and are reconciled when the tick confirms.
- The transport in the platform package (`src/platform/network.odin` and its pairs): TCP, length prefixed messages, a host that accepts connections and a client that connects, no UDP for the slice.
- The simulated chunk set: derived inside the tick from every player's position with a radius in data; a machine whose worker has not generated a chunk of the set stalls its tick until it has; generation is from the seed, so only the save's deltas cross the network at join.
- The state hash (the benchmark's) every few seconds, sent to the host and compared; a mismatch logs both hashes with the tick and shows a toast naming the machine, and play continues (the slice measures, it does not yet resync).
- Join: the host sends the save and the current tick, the joiner loads and runs ticks fast to catch up, then enters the window.
- The headless server: the game started with a `--server` flag runs the simulation without a window and without a player, hosting; the test suite already runs headless.
- The player array of the simulation (`doc/architecture.md`, players) holds one entry per connected player; a new player spawns at the pod.
- `doc/architecture.md` gains a Multiplayer section (the driver, the window, the hash, the chunk set, the join); `doc/commands.md` the server flag.

## Verify

- The build and check commands of 0168.
- Tests: two simulations fed the same tick stamped inputs through an in-process relay produce the same state hash for a thousand ticks; a tick does not run until the last player's input for it arrives; the local prediction's position equals the confirmed position when the inputs match and is reconciled when they differ; a joiner loaded from the host's save reaches the host's hash; a chunk outside the simulated set is never read by the tick; a server started with the flag ticks without a window.
- Two machines on the home network and a split screen pair (0178) play the slice (0179) for twenty minutes without a hash mismatch, the user and the main agent reading the log.
