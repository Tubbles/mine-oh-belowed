# 0382: The state hash on a thread, alone or not

Status: implementing (2026-11-12)

0345 took the state hash off a lone host only (`report_state_hash`, `session_alone`). A session of two or more still hashes on the frame, about 30 ms at a due tick whose loaded chunks are not yet hashed (after a load, a join, a teleport or a walk into new ground) and 1 to 2 ms otherwise, so multiplayer has long frames that single player has not. The user (2026-11-12): "I don't want there to be a difference on single player and multi player except network effects", and of the two ways `SUGGESTIONS.md` held for 0345, "the thread, design and implement".

## Goal

Every machine, alone or not, takes the hash the same way: a snapshot of what the hash reads between ticks, hashed on a thread, the report sent when the thread ends. No frame pays the hash, and `session_alone` no longer decides whether a machine hashes.

## Controls

None.

## Change

- The tick that is due copies what `simulation_state_hash` reads and starts the hash on a thread, as the save does since 0345 (`src/session_save.odin`). The report of that tick goes out when the thread has ended and is compared by its tick as today.
- A lone machine runs the same path, so the frame's cost is the same alone and in a session (a lone host keeps the result, Offline drops it, Decision 5).
- The copy is the part that stays on the frame. The design measures or bounds it against the hash it replaces and says how it stays small (what is copied whole, what is shared because nothing writes it between ticks).
- The hash's value for a state is what every machine of one version computes; whether it stays equal to today's is the design's to say.

## Verify

- The checks and the suite.
- A test that the thread's hash of a snapshot equals the direct hash of the same state, and a probe under the thread sanitizer with ticks running while the thread hashes.
- A session of two machines still reports a deliberate divergence, at the tick it was due.
- In the night window: the frame table shows no long tick and the hash's section (`.State_Hash`) at the copy's cost, for a lone host, which now runs the session's path.

## Specification (design, 2026-11-12)

### What the hash costs, and the copy against it

- **Cold hash, about 27 to 33 ms.** The night table of 2026-11-12, 03:14 (`tmp/frame_profile/night*/`, before 0345, so every lone host hashed): the worst tick at a hash is 28.0 to 34.0 ms in the 512 m runs that follow a teleport to a new view, a tick being about 1 ms. Nearly all of it is `field_chunk_state_hash` over loaded field chunks whose `hash_current` is false, which after a teleport, a load or a join is every loaded chunk (0345's probe: 150 stale of 125 to 175 loaded, 208,896 hashed bytes each, 31.3 MB). `hash.fnv64a` folds one byte at a time: 31 MB in about 30 ms is about a byte per nanosecond (an estimate joining the probe's counts and the table's times, two different runs).
- **Warm hash, about 1.1 to 2.3 ms.** The same table's 1024 m runs, at views the 512 m run had hashed (`tick state_hash` times the ticks, from rounded values): home 1.3, forest 1.1, ridge 1.5, sea 1.3 to 1.4, lake 1.2 to 2.2, factory 2.3. That is `write_simulation_state` (306 to 308 KB at the probe, a reflection codec appending byte by byte), its FNV (about 0.3 ms at the rate above, estimate), the sorts, and the chunks a tick changed since the last hash (1 standing, 25 walking: 0.2 and 5.2 MB). The factory's 2.3 ms with few stale chunks points at the encode as the larger share; no section times it alone.
- **The snapshot on the frame, estimated:** the encode as today (the warm hash less its FNV, about 0.8 to 2 ms), the stale chunks' planes copied (taking memcpy at about 10 GB/s: 31 MB cold about 3 ms, 5.2 MB walking about 0.5 ms, one chunk about 0.02 ms), 8 bytes per cached and per kept chunk. The session's first cold copy also faults its buffer's pages in (7,600 pages for 31 MB, perhaps 2 to 8 ms more); later copies reuse them (Decision 4).
- **So** the cold frame falls from about 30 ms to about 4 to 5 ms, and the warm one hardly moves: the warm copy costs about as much as the warm hash, both being mostly the encode, which carries no revision. What keeps the copy small is the part that does carry one, a field chunk's cached hash (`hash_current`, cleared by `note_field_chunk_change`): the snapshot takes a cached chunk's hash by value and copies only the stale chunks' planes, and the thread's hash of each copied chunk is written back to the live chunk when no write touched it since (`hash_pending`), so a chunk is copied once per change. Without the write-back every chunk never hashed on the frame would be copied at every hash, 31 MB every five seconds.

### What the snapshot copies and shares

Every byte the thread reads is in `State_Hash_Snapshot`; nothing live is shared. Taken on the main thread right after the due tick:
- `refresh_loaded_surfaces` on the live state first, as `lockstep_state_hash` does (a state write, so it stays on the frame).
- The tick, `cheat_speed`, `free_crafting` and `field.enabled` by value.
- `state_bytes`: `write_simulation_state` into the snapshot's own buffer, so the encode is the copy (0345, decision 3).
- `loaded_blocks` over `block_bytes`: each `World.chunks` entry's `blocks` (64 KB) in `chunk_coordinate_before` order; `unloaded_blocks`: each `World.saved_chunks` entry not loaded, its bytes, same order. A field world has neither (0345 probe: 0). The tests' block worlds and the debug terrain copy every loaded block chunk at every hash, since block chunks carry no hash cache.
- `field_chunks`: per `Field_World.chunks` entry in `sorted_field_chunk_coordinates` order, its `state_hash` when `hash_current`, else its eight hashed planes appended to `field_planes` and `hash_pending` set on the live chunk.
- `kept_hashes`: the `Field_Saved_Chunk.state_hash` of each `Field_Simulation.saved_chunks` entry not loaded, in coordinate order.

Nothing is shared by reference because every source changes during ticks. Writers checked: the field planes (the water step, the light, the brushes, the bodies, `set_field_water`, each through `note_field_chunk_change`), `Field_Simulation.saved_chunks` (`unload_left_field_chunks` adds, `decode_field_file` replaces and deletes), the block chunks (`tick_world`, arrivals), `World.saved_chunks` (an unload replaces and deletes the bytes, a load takes the entry out), the pools and records (every tick). The large unchanged part reaches the thread as 8 byte hashes (the cached chunks), and the kept chunks' bytes are never read.

### The hash's value

Equal to today's `lockstep_state_hash` of the same state: the same bytes in the same order (`hash_state_snapshot`). FNV-1a is a byte serial fold, so one call over a chunk's eight planes laid end to end equals today's eight calls. Machines of one version agree; no message, protocol or build stamp changes.

### The life of a job

- **Start.** `run_session_tick` calls `start_state_hash_when_due` after each tick. On a due tick it first finishes a job still in flight (waits for its thread, writes back, reports), then takes the snapshot and starts a thread. One job per session: a due tick while the previous job runs (a joiner catching up, ticks under `--input=none`) waits for it, and the wait counts in `.State_Hash`.
- **Finish.** Between frames, after the frame's ticks, `poll_state_hash` finishes a job whose thread is done: the join, the write-back (a chunk still in `Field_World.chunks` at the entry's coordinate with `hash_pending` set), the report with the snapshot's tick (`report_state_hash`). Called from `update_session`, `catch_up_joined_session` and `run_server_frame`.
- **A late local report.** On the host a client's report waits in `network.reports` until `record_host_hash` brings the host's own hash for its tick (`compare_hash_reports`, unchanged); a few frames is far inside `MAXIMUM_PENDING_HASH_REPORTS`. A client's report reaching the host a few frames later meets the host's hash, kept `KEPT_HOST_HASHES` intervals.
- **A joiner's first report** is, as today, of the first due tick after its snapshot. The host hashes every due tick now, so its hash of that tick exists or comes within frames; its hashes from before the join are never named by a report and `record_host_hash` prunes them.
- **A leaving peer:** nothing for the job; its waiting reports go as today. **A lost host:** the client's job finishes and `send_hash_report` sends nothing on the closed connection.
- **Session end and quit:** `end_session` joins a thread still running and drops its result (`destroy_state_hash_job`), since the session's connections close in the same call. A quit and a dropped joined world go through `end_session`.
- **Hot reload:** `reload_content` finishes the job (waits, writes back into the simulation about to be replaced, reports) before `reload_session`. A reload runs only alone.
- **Fallback:** without a thread (`thread.create_and_start_with_poly_data` gives nil) the job runs on the calling thread at once and the next poll reports it; when a buffer cannot be reserved, `lockstep_state_hash` runs on the frame and is reported at once. Either logs `network: the state hash runs on the frame (<reason>)` once per session; neither exits.

### The lone machine

The same path: `report_state_hash` loses its `session_alone` test and its hashing, and the role alone decides where a result goes. A Host keeps it (`record_host_hash`; a lone host's map is pruned like any, and the tests read it), a Client sends it, Offline drops it. Every other caller of `session_alone` stays, none being a periodic frame cost:
- `session_ticks_held` (`loop.odin`): only a machine alone may hold the world for a pause.
- `update_session`'s `offline` (`loop.odin`): alone the records come straight back and each clock tick runs at once; with others they wait for the exchange (a network effect).
- `update_session`'s `fast` and the tick command, `answer_command_ticks`, `execute_queued_command`'s `as`, `tick`, `pause`, `reload` and `viewport` (`loop.odin`): developer socket commands that stop or steer the world, refused with others.
- `run_ready_ticks` (`lockstep.odin`): an unpaced tick runs on the clock alone and waits for a record with others (pacing); alone a tick waiting for chunks takes the arrived ones (an insertion order rule).
- `reload_content` (`hot_reload.odin`): every machine must run one content.

### Determinism

- A result reaches only `Session_Network` (`hashes`, `reports`, `mismatch_count`, the notices) and the Hash_Report message. No tick reads them: `simulation_tick` takes no network, and outside the hash's files no reader of `mismatch_count`, `.hashes` or `state_hash` exists (grep).
- The write-back writes `state_hash`, `hash_current` and `hash_pending`, read only by `field_chunk_state_hash`, whose results feed only hashes (`field_saved_chunk` keeps a chunk by `field_chunk_terrain_and_water_equal`; its stored hash feeds `field_state_hash` alone). The value written is the chunk's hash at the snapshot's tick, alike on every machine. The frame of the write-back differs between machines, its value does not, because `note_field_chunk_change` clears `hash_pending` at the same ticks everywhere. This rests on the rule stated at `note_field_chunk_change` (every tick write into a loaded chunk goes through it), which the cache already relies on: a hash test that starts failing with this change points at a write that skips it, and the fix is that write.
- `refresh_loaded_surfaces` stays on the main thread at the due tick, as in `lockstep_state_hash`, so every machine of a session runs it at the same ticks. A lone host runs it every 300 ticks again, as before 0345; a field world loads no block chunks, where it changes nothing.
- Thread timing decides only when a report leaves and when a cache warms; no wall clock reaches the simulation.

### Files and procedures

`src/session_hash.odin` (new, loop cluster by its `session` prefix; imports `core:slice`, `core:thread`, `platform`). Header comment: the state hash off the frame (0382), the snapshot, the thread, one job per session, the write-back, who finishes it.
- `State_Hash_Block_Bytes :: struct {coordinate: Chunk_Coordinate, start, end: int}`: a block chunk's bytes at `block_bytes[start:end]`.
- `State_Hash_Field_Chunk :: struct {coordinate: Field_Chunk_Coordinate, hash: u64, planes: int}`: `planes` the offset of the chunk's copied planes in `field_planes`, -1 when `hash` is the cached one; the thread writes `hash` of a copied chunk.
- `State_Hash_Snapshot :: struct {tick: u64, cheat_speed, free_crafting, field_enabled: bool, state_bytes: [dynamic]byte, loaded_blocks, unloaded_blocks: [dynamic]State_Hash_Block_Bytes, block_bytes: [dynamic]byte, field_chunks: [dynamic]State_Hash_Field_Chunk, field_planes: [dynamic]byte, kept_hashes: [dynamic]u64}`: heap buffers kept across jobs.
- `State_Hash_Job :: struct {snapshot: State_Hash_Snapshot, thread: ^thread.Thread, pending: bool, result: u64, fallback_logged: bool}`: `pending` from the start to the report; `result` written by the thread before it ends, read after the join.
- `take_state_hash_snapshot :: proc(snapshot: ^State_Hash_Snapshot, simulation: ^Simulation_State) -> (ok: bool)`: what "What the snapshot copies" lists, the buffers cleared with their capacity kept. `field_planes` and `block_bytes` are reserved to their exact sizes (stale chunks times `FIELD_CHUNK_HASHED_BYTES`; loaded block chunks times the blocks' size plus the unloaded bytes) before anything is filled or flagged; false when a `reserve` returns an error. Main thread, with no job reading the snapshot.
- `hash_state_snapshot :: proc(snapshot: ^State_Hash_Snapshot) -> u64`: `lockstep_state_hash`'s parts in its order: `fingerprint_bytes(fingerprint_u64(FINGERPRINT_START, tick), state_bytes)`; each loaded block chunk's coordinate words (`x | z << 32`, then `y`, as `simulation_state_hash`) and bytes; when `field_enabled` each field chunk's hash folded by `fingerprint_u64` (a copied chunk's computed as `fingerprint_bytes(field_chunk_hash_start(coordinate), its planes)` and stored in its entry), then each kept hash; cheat speed and free crafting as 1 or 0; each unloaded block chunk's coordinate words and bytes. Allocates nothing.
- `run_state_hash_job :: proc(job: ^State_Hash_Job)`: the thread's procedure, `job.result = hash_state_snapshot(&job.snapshot)`.
- `start_state_hash_job :: proc(job: ^State_Hash_Job, threaded := true)`: sets `pending` and starts the thread; without one (nil, or `threaded` false, which only the fallback test passes) runs `run_state_hash_job` at once and logs the fallback line unless `fallback_logged`.
- `state_hash_job_done :: proc(job: ^State_Hash_Job) -> bool`: `job.thread == nil || thread.is_done(job.thread)`.
- `keep_hashed_field_chunks :: proc(snapshot: ^State_Hash_Snapshot, field: ^Field_Simulation)`: the write-back, main thread, after the join: for each entry with `planes >= 0` whose coordinate holds a chunk with `hash_pending`, its `state_hash` from the entry, `hash_current` true, `hash_pending` false.
- `finish_state_hash_job :: proc(job: ^State_Hash_Job, field: ^Field_Simulation) -> (tick, hash: u64, finished: bool)`: nothing unless `pending`; else the join (`thread.destroy`, `thread` nil), `keep_hashed_field_chunks` when the snapshot's `field_enabled` and `field.enabled`, `pending` cleared, the snapshot's tick and the result.
- `destroy_state_hash_job :: proc(job: ^State_Hash_Job)`: joins a thread still running, deletes the buffers, zeroes the job; no write-back, no report.
- `start_state_hash_when_due :: proc(session: ^Session) -> (started: bool)`: false unless `state_hash_due(session.simulation.tick)`; else `finish_state_hash(session)`, then the snapshot and `start_state_hash_job`, or after a failed snapshot the fallback line and `report_state_hash(&session.network, tick, lockstep_state_hash(&session.simulation))`; true. Called by `run_session_tick`.
- `poll_state_hash :: proc(session: ^Session)`: `finish_state_hash` when `pending` and `state_hash_job_done`. Called between frames (The life of a job).
- `finish_state_hash :: proc(session: ^Session) -> (finished: bool)`: `finish_state_hash_job(&session.hash_job, &session.simulation.field)`, then `report_state_hash` when finished. Waits.

`src/session_network.odin`
- `report_state_hash :: proc(network: ^Session_Network, tick, hash: u64)`: Host `record_host_hash`, Client `send_hash_report`, Offline nothing. Comment: a hash job's result by role (0382); a lone host keeps its own, pruned like any.
- The header's Hash_Report bullet: every machine hashes every `STATE_HASH_INTERVAL_TICKS` on a thread (`session_hash.odin`, 0382) and a client sends its hash with its tick when the thread ended; "only while the machine is not alone" goes.
- `encode_join_snapshot`'s comment: "(lockstep_state_hash does the same on every machine)" becomes "(the state hash's snapshot does the same on every machine, take_state_hash_snapshot)".

`src/lockstep.odin`
- `run_session_tick`: `report_state_hash(...)` becomes `start_state_hash_when_due(session)`, the profile lines as they are; its comment: the hash's snapshot when due.
- `STATE_HASH_INTERVAL_TICKS`'s comment: every machine hashes at these ticks, on a thread (`session_hash.odin`), and the host compares.
- `lockstep_state_hash`: body unchanged; one comment line: `hash_state_snapshot` folds the same parts in the same order from a snapshot, and the two change together.

`src/session.odin`: `Session.hash_job: State_Hash_Job` after `save_job`, commented (the state hash's snapshot and thread, 0382). `end_session`: `destroy_state_hash_job(&session.hash_job)` after `finish_session_save`.

`src/loop.odin`: `update_session` calls `poll_state_hash(session)` after the frame's ticks (after the `fast` block), before `send_line_answers`; `catch_up_joined_session` after `run_ready_ticks`.

`src/session_server.odin`: `run_server_frame` calls `poll_state_hash(session)` after `run_ready_ticks`.

`src/hot_reload.odin`: `reload_content` calls `finish_state_hash(state.session)` before `reload_session`, commented: the write-back goes into the simulation the reload replaces.

`src/simulation_field_save.odin`
- `FIELD_CHUNK_HASHED_PLANE_COUNT :: 8` and `FIELD_CHUNK_HASHED_BYTES :: 4 * FIELD_CHUNK_SAMPLE_COUNT + 3 * size_of(Field_Sample_Bits) + FIELD_CHUNK_SAMPLE_COUNT * size_of(Water_Owner)` (208,896).
- `field_chunk_hash_start :: proc(coordinate: Field_Chunk_Coordinate) -> u64`: today's two coordinate words from `FINGERPRINT_START`.
- `field_chunk_hashed_planes :: proc(chunk: ^Field_Chunk) -> [FIELD_CHUNK_HASHED_PLANE_COUNT][]byte`: views of the hashed planes in today's order (density, material, water, water_still, water_awake, water_source, water_owner, water_pressure_failed), the one list of what a chunk's hash covers.
- `field_chunk_state_hash`: the cache as today, else `field_chunk_hash_start` folded over the views; value unchanged. Its comment names `hash_state_snapshot` as the other reader of the list.

`src/world_field.odin`: `Field_Chunk.hash_pending: bool` after `state_hash`, commented: a state hash snapshot copied the planes while stale (0382), and the thread's hash is kept unless a write clears this first; never saved (the codec writes the planes by name) or hashed. `note_field_chunk_change` also clears it.

`src/tick_profile.odin`: `Tick_Section.State_Hash`'s comment: the hash's snapshot on a due tick, with a wait for the previous job and either fallback (0382); `Tick_Profile`'s comment: `state_hashes` the ticks that took a snapshot. `src/render_frame_profile.odin`: `Frame_Event.State_Hash`'s comment: the frame's ticks took the hash's snapshot.

Test helpers: `run_lockstep_test_ticks` (`lockstep_test.odin`) ends with `poll_state_hash(&machine.session)`, as a frame does; `destroy_lockstep_test_machine` calls `destroy_state_hash_job(&machine.hash_job)` before `destroy_simulation`. A test that tears a `Session` down without `end_session` after a due tick ran adds `destroy_state_hash_job` (the leak check names any).

### Tests

`src/session_hash_test.odin` (new; writes no files):
- `test_a_snapshot_hashes_to_the_direct_state_hash`, twice. Field: `start_field_test_session`, `make_field_save_test_state` (its kept chunk included), `cheat_speed` and `free_crafting` true; `lockstep_state_hash` as the direct hash (it warms every chunk) and each loaded chunk's `state_hash` noted; `note_field_chunk_change` on every other chunk in coordinate order, data unchanged; `take_state_hash_snapshot` true with `len(field_planes)` the stale count times `FIELD_CHUNK_HASHED_BYTES` and one kept hash; `start_state_hash_job`, `finish_state_hash_job`: finished, the state's tick, the direct hash, and every loaded chunk `hash_current`, not `hash_pending`, with its noted hash. The lengths of `field_chunk_hashed_planes` sum to `FIELD_CHUNK_HASHED_BYTES`. Block: `make_save_test_simulation`, `load_save_test_chunks`, one `World.saved_chunks` entry at an unloaded coordinate (cloned bytes), both flags true; `len(loaded_blocks) == len(world.chunks) > 0`, one unloaded entry, the job's hash `lockstep_state_hash`'s.
- `test_ticks_while_the_hash_runs_leave_the_snapshots_hash`: field session with network role Host, `make_field_save_test_state`, the tick set to `STATE_HASH_INTERVAL_TICKS - 1` (it spares 298 ticks) and one `tick_field_test_simulation`; the reference `lockstep_state_hash`; `note_field_chunk_change` on every loaded chunk; `start_state_hash_when_due` true; at once `field_world_set_sample` on the player's sample to another value and 30 more ticks; `finish_state_hash`: `network.hashes[due]` is the reference, the written chunk's `hash_current` is false, and every chunk with `hash_current` holds a `state_hash` equal to its recomputation (the flag cleared, `field_chunk_state_hash`). This is the test the verifier runs under the thread sanitizer.
- `test_every_machine_takes_the_hash_and_keeps_it_by_role` (replaces `test_only_a_machine_with_another_hashes_its_state` in `session_network_test.odin`, deleted): per case a `Session` holding `make_save_test_simulation` at tick 300; roles Offline, Host without peers, Host with a peer not receiving records, Host with a receiving peer, Client without peers: `start_state_hash_when_due` true and `pending` for each; after `finish_state_hash`, `len(network.hashes)` 0, 1, 1, 1, 0 (key 300 for the hosts); at tick 301 `start_state_hash_when_due` false. Torn down with `destroy_state_hash_job`, `destroy_session_network`, `destroy_simulation`.
- `test_the_hash_runs_on_the_frame_without_a_thread`: a block world at tick 300, role Host; the snapshot, `start_state_hash_job(&job, threaded = false)`: `thread` nil, `fallback_logged`, `state_hash_job_done`; `finish_state_hash` keeps `lockstep_state_hash`'s value under 300.
- `test_a_session_ends_with_its_hash_in_flight`: field session after two `tick_field_test_simulation` ticks, every loaded chunk stale, the tick set to 300, `start_state_hash_when_due` true, `end_session` at once: no crash, no leak.

`src/session_network_test.odin`:
- `test_a_host_alone_hashes_nothing_and_a_joiner_finds_a_desync_at_its_first_hash_tick` becomes `test_a_lone_host_hashes_and_a_divergence_is_reported_at_its_due_tick`: alone to 601 and `finish_state_hash(host.session)`: `network.hashes` holds 300 and 600. The join and the run to `first_due + 300` as today: no mismatch, no report waiting. The flip of the client's `free_crafting` as today, no mismatch right after; frames until both `mismatch_count` are 1, bounded by the host's tick below `next_due + 300` and a minute; both are 1, and on each machine a toast in `primary_ui(...).toasts` contains `state hash mismatch at tick <next_due>`.
- `test_a_join_at_a_hash_tick_is_compared_from_the_next_one`: at 300, after `finish_state_hash(&host.session)`, the host holds 300 (was none); at the end `finish_state_hash(&host.session)` before reading, and 600 equals the joiner's `lockstep_state_hash`; the comment says the joiner is compared from the next due tick though the host hashed 300.

### Docs

- `doc/architecture.md`. The opening bullet: the state hash is also taken on a thread of its own (0382). Multiplayer, Every game hosts: "and it hashes nothing (State hash)" goes. Multiplayer, State hash: every machine, alone or not, hashes a snapshot every 300 ticks on a thread (Threads and chunk streaming) and reports it with its snapshot's tick when the thread ends; a lone host keeps its own, Offline drops it; the comparison by tick as before; the 0345 sentences on the machine alone and the cold cache go. Threads and chunk streaming, a bullet after the save's thread: the snapshot's contents, the stale chunks' planes copied once per change and their hashes written back (`hash_pending`), one job per session (a due tick waits for the previous), finished between frames, buffers kept for the session, `end_session` drops a job in flight, `reload_content` finishes it first, the fallback. Performance, the counters line: "A solo run hashes nothing ... joined machine" becomes: every run hashes every 300 ticks, the event and the `State_Hash` section being the snapshot's frame and cost, the hash on its thread.
- `doc/code_map.md`: `session_hash.odin` in the loop files after `session_save.odin` with its procedures; the loop row's counts as measured; the Tests line: `session_hash_test.odin` (0382), and "a lone host's hash, 0345" becomes "a divergence reported at its due tick, 0382"; any record line `tools/code_graph.py --check` names.
- `SUGGESTIONS.md`: the first bullet of "Suggestions from the hash and the autosave (0345, 2026-11-12)" goes.

### Hand-back check

- Memory a frame may draw from: nothing draws from the snapshot; its buffers are reused only after a join and freed in `end_session`.
- A load the game can make fail: both fallbacks hash on the frame with one log line and never exit.
- A changed save layout: none; `hash_pending` is not saved.
- A new participant in a shared budget: the hash's thread beside the field workers, at most one per session every 300 ticks; the host's comparison queue waits a few frames longer for its own hash, far inside `MAXIMUM_PENDING_HASH_REPORTS`.
- A list that grows without bound: a lone host's `network.hashes` is pruned by `record_host_hash` to `KEPT_HOST_HASHES` intervals.
- Tests and the state directory: the new tests write no files.

### Decisions

1. Nothing live is shared; a cached chunk goes by its 8 byte hash. Why: every source is written by ticks, and the cache is the one revision the state carries.
2. The thread's chunk hashes are written back under `hash_pending`. Why: without it every chunk would be copied at every hash; the flag is the cheapest proof a chunk is unchanged since the snapshot, and a chunk newly at the coordinate starts with it clear.
3. One job per session, an overlapping due tick waits. Why: overlap happens only when ticks outrun the hash (catching up, `--input=none`), where a frame's length is not the concern, and two jobs would need two buffer sets and two kinds of pending flag.
4. The buffers stay with the session. Why: a cold copy into resident pages saves the page faults (estimated at 2 to 8 ms for 31 MB) at every teleport or join after the first. The price is memory (Question 1).
5. A lone host keeps its result, Offline drops it. Why: `report_state_hash` then decides by role alone, the map is bounded, and the tests read it.
6. The value is unchanged and `lockstep_state_hash` stays as the direct hash: the tests' reference and the buffers' fallback.
7. A job in flight at the session's end is dropped; a reload finishes it. Why: no reader is left at the end, while a reload keeps the session and its network.
8. The encode stays on the frame (0345, decision 3).

### Questions to the main agent

1. The buffers keep the largest snapshot of the session: after a cold hash the loaded set's planes (125 to 175 times 208,896 bytes, 26 to 37 MB at 0345's probe) plus about 0.3 MB. Acceptable on the phone, or release `field_planes` after a job whose copy passed a bound, paying the faults on the next cold copy?
2. The warm snapshot (mostly the encode, about 0.8 to 2 ms, estimated) now lands on every machine every 300 ticks, the lone host included, which paid nothing since 0345. Accept here, and look at the encode only if the night table shows it?

### Decisions (main agent, 2026-11-12)

1. Approved as specified.
2. Question 1: the buffers stay with the session, on the phone too. 26 to 37 MB is held only after a cold hash of a full loaded set, and releasing them buys the page faults back on the frame this item is about.
3. Question 2: accepted. Every machine pays the warm snapshot every 300 ticks, the lone host again; that is the equality the item asks for. The encode's cost is looked at only if the night table shows it, as a new item.
4. The implementer measures nothing with a benchmark; the copy's cost is read from the night table's `.State_Hash` section at the next window.
