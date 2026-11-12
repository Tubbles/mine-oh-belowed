# 0345: The state hash and the autosave off the frame

Status: landed (2026-11-12, 34b1e69)

Every windowed game hosts, so it hashes the whole state every 300 ticks, and the autosave (every minute in the user's settings) encodes and writes on the main thread (`work/performance_research_0340.md`, 2.1). Neither is timed today.

## Goal

No frame over its budget at a hash tick or an autosave.

## Controls

None.

## Change

- The hash: skipped while it can serve nobody, or spread, without changing what a client's comparison needs (the research left open whether a joiner's first comparison reads the lone host's hashes: the design settles it).
- The save: a snapshot on the main thread, the encoding and the write on a thread, through `write_file_replacing`, with a save in flight when the game closes finished first.
- The lockstep and the save format are unchanged.

## Verify

- The checks and the suite, with a save written off the frame equal byte for byte to one written on it.
- 0342's table: the worst frame at the hash ticks and at an autosave in a view held for a minute, before and after.

## Specification (design, 2026-11-11)

Builds on 0342: the same files (`lockstep.odin`, `session_network.odin`, `loop.odin`), and its table is the acceptance. Designed against 0342's specification: `report_state_hash` returns `hashed: bool`, `run_session_tick` times it into `Tick_Section.State_Hash`, `save_when_due` returns `saved: bool` and the loop calls `note_frame_event(.Save)` on true. The worktree is made from 0342's tip.

### What the code does today

- **The hash.** `run_session_tick` calls `report_state_hash` after every tick. On any role but Offline, at a tick that is a multiple of 300, it runs `lockstep_state_hash` on the main thread: `refresh_loaded_surfaces`, `write_simulation_state` into a temp buffer, FNV-1a over it, over the loaded block chunks, and over every loaded field chunk (`field_chunk_state_hash`, cached per chunk until `note_field_chunk_change`). A host keeps it (`record_host_hash`); a client sends it. Since 0188 a windowed game's own world is a Host from its first frame, so a player alone hashes every 300 ticks for nobody.
- **A joiner's first comparison.** `host_join` encodes the snapshot at the host's tick T and sets the peer's `receives_records` in the same call, so `session_alone` is false for every tick the host runs after T. The joiner starts at T and hashes only ticks it runs (`run_session_tick`), so its first report is of the first multiple of 300 above T. The host computes that hash when it runs that tick, already not alone. No report of a tick at or before T exists, and a client always has a host connection, so no report can name a tick the host ran alone. **Skipping the hash while `session_alone` changes no comparison.**
- **The save.** `save_when_due` (`loop.odin`) runs after the frame's ticks: for the pause menu's Save or when `autosave_due`, `save_session` → `save_world` on the main thread: `refresh_loaded_surfaces`, `encode_save_files` (world.sjson, entities.bin through `write_simulation_state`, the block regions, and field.bin through `encode_field_file`, which run length encodes 12 planes of 32,768 samples for each loaded chunk a tick changed and copies the kept chunks' bytes), then `write_save_files` into `<world>.saving` (field.bin through `write_file_replacing`) and `swap_in_save`. The frame stands still for all of it. A failed windowed save does not reset `ticks_since_save`, so it retries every frame. The other callers are synchronous: a new world's first save (`enter_planned_session`, `start_command_line_session`, `run_command_line_server`), `leave_session` (quit, quit to title), the socket's `save` (`command_save`), and the server's autosave and stop save (`session_server.odin`).
- **Android.** No Odin code runs at a pause: after `APP_CMD_LOST_FOCUS` raylib blocks the main thread inside its event poll (`rcore_android.c` of raylib 6.2, lines 790 and 1137 to 1140, read in `tmp/0319/verify/src62`), and nothing saves on a pause today. A destroyed activity ends the loop (`WindowShouldClose`), so `leave_session` saves.

### The probe (counts only)

A new field world at the shipped seed (the test planets, no waters), the scripted walk, dig, torch and place of `field_test_script_frame`, then 1,840 ticks of walking (`tmp/0345/tree/src/probe_0345_test.odin`):

| | |
|---|---|
| `size_of(Field_Chunk)` | 372,832 bytes |
| loaded field chunks | 125 standing, 150 to 175 walking |
| loaded chunks a tick changed (`modified`) | 8 to 10 |
| kept chunks (`Field_Simulation.saved_chunks`), block chunks, explored columns | 0, 0, 0 |
| `write_simulation_state` | 306 to 308 KB |
| world.sjson, entities.bin, field.bin | 6.5 KB, 315 KB, 69 to 90 KB |
| field chunks rehashed at a hash tick (`hash_current` false) | 150 at the first, 1 standing, 25 walking; 208,896 hashed bytes each |

### Part 1: the hash, skipped while alone

- **Seam.** `report_state_hash` returns false without hashing when `session_alone(network^)` (Offline, or a Host no peer `receives_records` from). A client is never alone. The server's network is the same code, so a server nobody joined hashes nothing either.
- **Detection.** With any other machine in the session every machine hashes exactly the ticks it hashes today, so every peer finds a desync at the same tick as today.
- **What moves.** The field chunks' hash cache stays cold on a lone host, so the host's first hash after a join reads every loaded chunk (125 to 175 × 208,896 bytes, 26 to 37 MB), as every session's first hash does today (150 stale in the probe) and as the joiner's first hash does. The lone host also stops refreshing the explored surfaces every 300 ticks: a field world loads no block chunks (probe: 0), and the record reaches a joiner through the snapshot, which refreshes first.
- **Rejected.** A hash on a worker from a snapshot: it needs the save's snapshot of the whole state every 300 ticks, more copying than the hash costs, for a case (alone) nobody reads. A hash spread over ticks: every peer must cut the same slices at the same ticks, and a slice hashed at tick N and another at N+1 describe no single state, so a desync found would name no tick. Hashing only what changed: the field chunks already do (`hash_current`); the rest is `write_simulation_state`, which has no change tracking. None is needed for the lone host; the cost with a client stays (Questions).

### Part 2: the save, a snapshot on the main thread and the write on a thread

- **Seam.** The main thread, between ticks, takes a snapshot that leaves the thread nothing live to read: it refreshes the explored surfaces, encodes world.sjson, entities.bin and the block regions as today (`encode_save_files_without_field`), and copies field.bin's inputs: each kept chunk's bytes and each loaded chunk a tick changed, whole. A thread of the save's own encodes those chunks (`assemble_field_file`, the code `encode_field_file` runs today), writes `<world>.saving` and swaps it in (`write_save_files_into_place`, today's tail of `save_world`). Both paths share every encoder, so the bytes are equal by construction and by test.
- **Snapshot size** (probe world): entities.bin 315 KB, world.sjson 6.5 KB, 8 to 10 chunk copies at 372,832 bytes (3.0 to 3.7 MB), kept bytes 0 (about 9 KB a kept chunk by field.bin's 90 KB over 10 chunks): about 4 MB, nine tenths of it chunk copies. The bound is the loaded set: every loaded chunk changed copies 125 to 175 × 372,832 bytes (47 to 65 MB).
- **One save at a time.** `Session.save_job` holds the save in flight. A pause menu Save or a due autosave while it is set waits: the request stays set, the autosave stays due, and the first frame after the job finished starts it. Every synchronous save (`save_session`) and `end_session` first wait for the job, since all write the same `<world>.saving`.
- **Interval and failure.** `ticks_since_save` is reset when the snapshot is taken, so the interval counts from the tick the save holds. A failed write logs `error: saving %q failed: %s` (today's line), toasts `save_failed` and waits for the next interval, as the server's save already does (a behaviour change: a failed windowed autosave retried every frame). The old save stands: the write is today's staging and swap.
- **Toasts.** `save_done`, `autosave_done` and `save_failed` show on the frame the job finished, not the frame it started. No new string keys.
- **Thread ownership and shutdown.** Only the main thread creates, polls, joins and frees the job; at most one exists, on the session. The thread runs `run_save_job` with the default context (its own temp allocator, freed at thread end by `core:thread`) and `context.allocator` set to the snapshot's arena; it reads only the snapshot and writes only `job.problem`, which the main thread reads after `thread.destroy` (a join). Every path that ends a session goes through `end_session`, which joins first: quit and quit to title (`leave_session`, whose own save joins earlier), a dropped joined world, the server's `defer end_session` after its stop save, the tests. The desktop window's close and Android's destroyed activity end the loop into `leave_session`. On an Android pause the main thread blocks in raylib's poll and the save's thread runs on to its end; a kill in the background before it ends leaves `<world>.saving` beside the previous save, which loads (`existing_save_directory`), as a kill during today's save would.
- **Memory.** The snapshot owns a growing virtual arena (`new_growing_arena`); every byte of it (the location's strings, the encoded files, the region names, the kept bytes, the chunk copies, the problem string) lives there and is freed at once by `destroy_arena` in `finish_save_job`, on the main thread, from `save_when_due` (before the draw; nothing draws from it) or a synchronous save or `end_session`.
- **Rejected.** Copy on write of the chunks: every sample write of the tick (`field_world_set_sample`, the water step, the light) would need a hook before it, and one missed hook lets the thread read a chunk mid tick, a torn save. A snapshot spread over frames: chunk A copied at tick N and chunk B at N+1 is a world no machine ever held (water moved between them counts twice or not at all, the flood's heap names samples in states they never had), which loads into a simulation no peer has; not acceptable. A per chunk cache of encoded bytes, so the snapshot copies only the chunks changed since the last save: bounds the copy by the change rather than the set, at the price of a third copy of the terrain with its own invalidation, where a missed one writes old terrain silently; not now (Questions). A persistent save thread: one thread a minute does not need one.

### Files and procedures

`src/session_network.odin`
- `report_state_hash :: proc(network: ^Session_Network, simulation: ^Simulation_State) -> (hashed: bool)`: returns false when `session_alone(network^)` or `!state_hash_due(simulation.tick)`, else hashes and keeps or sends as today and returns true. Comment: a machine alone hashes nothing; a joiner's first report is of the first due tick after its snapshot, which the host runs after `host_join` made it not alone (0345).
- The file header's Hash_Report bullet: the hash is taken while the machine is not alone.

`src/lockstep.odin`: the comment on `STATE_HASH_INTERVAL_TICKS`: every machine of a session that is not alone hashes.

`src/save_world.odin`
- `encode_save_files_without_field :: proc(state: ^Simulation_State, content: Simulation_Content, display_name: string, last_played_unix_seconds: i64) -> Save_Files`: today's `encode_save_files` without the field line, temp allocator.
- `encode_save_files`: calls it, then sets `files.field = encode_field_file(&state.field, make_save_header())` when the field is enabled. Same result as today.
- `write_save_files_into_place :: proc(location: Save_Location, files: Save_Files) -> string`: the staging paths, `write_save_files` and `swap_in_save` with today's two problem lines, temp allocator. `save_world` becomes refresh, `encode_save_files`, this.

`src/simulation_field_save.odin`
- `assemble_field_file :: proc(kept: map[Field_Chunk_Coordinate][]byte, changed: []^Field_Chunk, header: Save_Header) -> []byte`: today's body from `chunks := make(...)`: the kept bytes, then each changed chunk's `encode_field_chunk` under `chunk.coordinate` (its key in `Field_World.chunks`) over them, the header, the count and the chunks in coordinate order. Temp allocator.
- `encode_field_file`: builds `kept` from `field.saved_chunks` (views of the bytes) and `changed` from `field.world.chunks` with `modified`, both temp, and calls it.

`src/session_save.odin` (new, loop cluster by the `session` prefix; imports `core:mem/virtual`, `core:slice`, `core:strings`, `core:thread`, `core:time`, `platform`)
- Header comment: the save off the frame (0345), the snapshot's contents, one job at a time, who joins it.
- `Save_Snapshot :: struct {arena: ^virtual.Arena, location: Save_Location, world, entities: []byte, regions: [dynamic]Region_File, field_enabled: bool, field_kept: map[Field_Chunk_Coordinate][]byte, field_changed: [dynamic]^Field_Chunk}`, all memory in `arena`.
- `Save_Job :: struct {snapshot: Save_Snapshot, thread: ^thread.Thread, requested: bool, problem: string}`: `requested` marks the pause menu's Save; `problem` is written by the thread before it ends, in the arena.
- `Save_Outcome :: struct {requested: bool, problem: string}`: `problem` in the temp allocator, "" when written.
- `take_save_snapshot :: proc(state: ^Simulation_State, content: Simulation_Content, location: Save_Location, last_played_unix_seconds: i64) -> (snapshot: Save_Snapshot, ok: bool)`: false when `new_growing_arena` returns nil. `refresh_loaded_surfaces`, then `encode_save_files_without_field` cloned into the arena (each region's name and bytes too), the location's three strings cloned, and for a field world every `field.saved_chunks` entry's bytes cloned into `field_kept` (made with the map's length) and every loaded chunk with `modified` copied: `copy := new(Field_Chunk, allocator)`, `copy^ = chunk^`, `copy.crater_overlay = {}` (the live chunk owns it; the codec does not read it).
- `destroy_save_snapshot :: proc(snapshot: ^Save_Snapshot)`: `destroy_arena`, then zero.
- `save_snapshot_files :: proc(snapshot: ^Save_Snapshot) -> Save_Files`: the snapshot's world, entities and regions, and for a field world `assemble_field_file(snapshot.field_kept, snapshot.field_changed[:], make_save_header())`. Temp allocator of the calling thread.
- `write_save_snapshot :: proc(snapshot: ^Save_Snapshot) -> string`: `write_save_files_into_place(snapshot.location, save_snapshot_files(snapshot))`.
- `run_save_job :: proc(job: ^Save_Job)`: the thread's procedure: `context.allocator = virtual.arena_allocator(job.snapshot.arena)`, `job.problem = strings.clone(write_save_snapshot(&job.snapshot))`.
- `start_save_job :: proc(snapshot: Save_Snapshot, requested: bool) -> ^Save_Job`: `new(Save_Job)`, `thread.create_and_start_with_poly_data(job, run_save_job)`; when that returns nil the job runs `run_save_job` on the calling thread at once, so the save is still written.
- `save_job_done :: proc(job: ^Save_Job) -> bool`: `job.thread == nil || thread.is_done(job.thread)`.
- `finish_save_job :: proc(job: ^Save_Job) -> Save_Outcome`: `thread.destroy` (joins) when the thread exists, the outcome with the problem cloned to temp, the failure line logged with the location's display name, `destroy_save_snapshot`, `free(job)`.
- `start_session_save :: proc(session: ^Session, content: Game_Content, requested: bool) -> (problem: string)`: asserts `session.save_job == nil`; "saving is off for this world" when `!session.save.enabled` (today's text); else resets `ticks_since_save`, takes the snapshot with `session_simulation_content(content, session.technologies, session.field_content)`, `session.save.location` and `time.to_unix_seconds(time.now())`, and sets `session.save_job`. Without an arena it logs the failure line and returns "cannot reserve memory for the save".
- `begin_due_session_save :: proc(session: ^Session, content: Game_Content, autosave_minutes: int) -> (started: bool, problem: string)`: `requested := session.save_requested`, `autosave := session.save.enabled && autosave_due(...)`; nothing when neither, or while `session.save_job != nil` (the request stays set); else clears `save_requested` and calls `start_session_save`.
- `poll_session_save :: proc(session: ^Session) -> (outcome: Save_Outcome, finished: bool)`: when a job exists and `save_job_done`, `finish_save_job` and nil the field.
- `finish_session_save :: proc(session: ^Session) -> (outcome: Save_Outcome, finished: bool)`: the same without the done check (waits).

`src/session.odin`
- `Session.save_job: ^Save_Job`, after `ticks_since_save`, commented: the save in flight (0345), nil when none.
- `save_session`: first line `finish_session_save(session)`; comment: the synchronous save (a new world's first, the quit's, the socket's, the server's stop), after the save in flight.
- `end_session`: first line `finish_session_save(session)`, with a comment that a save in flight is written before the session goes.

`src/loop.odin`
- `save_when_due :: proc(state: ^Frame_State) -> (saved: bool)`: `poll_session_save`; a finished outcome toasts `text(save_outcome_text_key(outcome))`; then `begin_due_session_save(session, state.content, state.settings.autosave_minutes)`, a problem toasts `save_failed`; returns `started`, so 0342's Save event marks the snapshot's frame.
- `save_outcome_text_key :: proc(outcome: Save_Outcome) -> string`: `save_failed` with a problem, else `save_done` when requested, else `autosave_done`.

`src/session_server.odin`
- `run_server_frame`: the autosave block becomes `poll_session_save(session)` then `begin_due_session_save(session, server.content, server.autosave_minutes)`. `save_server_world` and `run_server`'s stop save stay (synchronous, after the job). Header comment: the autosave is written off the frame.

### Tests

`src/session_network_test.odin`
- `test_only_a_machine_with_another_hashes_its_state`: a `make_save_test_simulation` at tick 300 and a `Session_Network` per case, `report_state_hash` and `len(network.hashes)`: Offline false 0; Host without peers false 0; Host with a peer whose `receives_records` is false false 0; Host with a peer that receives records true 1 (key 300); Client without peers true 0. At tick 301 the receiving host returns false. Peers carry a zero connection, which sends nothing.
- `test_a_host_alone_hashes_nothing_and_a_joiner_finds_a_desync_at_its_first_hash_tick` (loopback): `make_hosting_test_frame`, `run_host_alone_until` tick 601: `network.hashes` empty. A client joins (`run_until_world_sent`, T the host's tick then); D, the first multiple of 300 above T. Both run to D + 300: the host holds D and no key at or below T, `network.reports` is empty (every report compared), no mismatch on either. Then the client's `simulation.free_crafting` (hashed, read by no tick without a craft) flips at its tick P, and E is the first multiple of 300 above P: right after the flip no mismatch on either; both run to E + 60: `mismatch_count` 1 on the host and 1 on the client (the next hash tick, E + 300, is not reached).
- `test_a_join_at_a_hash_tick_is_compared_from_the_next_one` (in process, as `test_a_joiner_restores_while_the_others_play_and_reaches_their_hash`): host (window 0, `network.role = .Host`, no peers) and guest play frame by frame until the host's tick is exactly 300: `host.network.hashes` empty. A peer `{receives_records = true}` is appended to the host's network and the joiner made from `encode_join_snapshot` at 300 (its tick 300, its network Offline). Host and guest play on, relayed to all three, until the host passes 600; the joiner's ticks run one at a time through `run_session_tick` (chunks fed as `run_lockstep_test_ticks` does) while below 600. Then: the host holds 600 and not 300, and `host.network.hashes[600] == lockstep_state_hash(&joiner.simulation)`.

`src/session_save_test.odin` (new; every save under `make_save_test_directory`)
- `test_a_save_off_the_frame_writes_the_bytes_of_one_on_it`: twice, for a field session set up as `make_test_field_save` does (two ticks, an edited sample, a torch, awake water) plus a kept chunk (a copy of the awake chunk with `hash_current` false and its coordinate moved by {0, 40, 0}, encoded into `field.saved_chunks` with its `field_chunk_state_hash`), and for `make_loopback_test_session` (a block world; its regions directory must hold at least one file). Two locations with one display name and the directory names "on frame" and "off frame": `save_world(..., 7)` into the first, `take_save_snapshot(..., 7)` for the second, then the live state is changed (the field case: the edited sample set to another value and the kept chunk's live bytes filled with zeros; both: the first player's held stack count plus one), then `start_save_job` and `finish_save_job` with an empty problem. world.sjson, entities.bin, field.bin and every region file are equal byte for byte between the two directories.
- `test_a_save_in_flight_finishes_before_a_save_on_the_frame_and_the_session_end`: `make_loopback_test_session` with an enabled save setup under the temp directory (the names heap clones, the old display name deleted as `make_loopback_test_session` does). `start_session_save` at tick T0; `simulation.tick += 1`; `save_session` returns "", `save_job` is nil, world.sjson reads tick T0 + 1 and the temp directory holds one entry (no `.saving`, no `.previous`). `start_session_save` again (tick T0 + 1), `simulation.tick += 1`, `end_session`: world.sjson reads T0 + 1 and the directory still holds one entry.
- `test_a_second_save_waits_while_one_is_in_flight`: the same session; `save_requested` set, `begin_due_session_save(..., 0)` starts (requested cleared, `ticks_since_save` 0). Then `ticks_since_save` = one minute of ticks (`60 * simulation.tick_rate`) and `save_requested` set: `begin_due_session_save(..., 1)` returns false and "", the job pointer is the first one, the request is still set and `ticks_since_save` unchanged. `finish_session_save` returns finished, requested, "". `begin_due_session_save(..., 1)` starts again and clears the request. `finish_session_save` before the end.
- `test_a_failed_save_off_the_frame_reports_its_problem`: the same session saving under `<temp>/blocker/saves`, where `blocker` is a regular file: `start_session_save` returns "", `finish_session_save` gives a problem and `requested` as passed, and nothing exists under `blocker`. `save_outcome_text_key` gives `save_failed`, `save_done` and `autosave_done` for a problem, a request and an autosave. (That a failed write keeps the old save is `write_save_files_into_place`, the code `test_save_swaps_a_staged_directory_into_place` covers.)

Existing tests stay as they are: the ones that read `network.hashes` all have a client joined (`session_network_test.odin` 446 and 548, `session_discovery_test.odin` 200), and `test_the_server_clears_its_events_and_a_failed_save_waits` calls the synchronous `save_server_world`.

### Docs

- `doc/architecture.md`: the opening bullet (workers only generate and mesh): a save is also written on a thread of its own (0345). Multiplayer, Every game hosts: a host alone hashes nothing. Multiplayer, State hash: each machine of a session that is not alone hashes; why a joiner's first comparison is served. Threads and chunk streaming: a bullet on the save's thread (the snapshot, one at a time, joined by a synchronous save and `end_session`, the Android pause). Save format, the bullet "Saving runs on the main thread between ticks": the snapshot between ticks, the write on the thread, the interval counted from the snapshot, a failed autosave waits for the next interval.
- `doc/commands.md`, the `save` row: saves on the main thread after a save in flight, and answers once written.
- `doc/android.md`, One process, many launches: a save in flight when the app goes to the background runs on while raylib blocks the main thread; a quit or a destroyed activity waits for it (`leave_session`); a kill before it ends leaves the previous save.
- `doc/code_map.md`: `session_save.odin` in the loop cluster's files after `session.odin` with its procedures, the cluster table's counts, and any record line `tools/code_graph.py --check` names (the new `encode_save_files_without_field` adds world to simulation references to the accepted save codec count, marked 0345).
- A line 0342 wrote saying a solo run hashes every 300 ticks (`grep -rn "300 ticks" doc/`) changes to: a solo run hashes nothing; a hash shows only with a joined machine.

### Hand-back check

- Memory a frame may draw from: the snapshot's arena is freed in `save_when_due` before the draw, or in a synchronous save or `end_session`; nothing draws from it.
- The staging directory and the swap are unchanged and shared; the location comes from the session's save setup, under the saves directory.
- Save layout: unchanged, no remap; the byte equality test holds it.
- A new participant in a shared budget: the save's thread runs beside the field workers for the length of one write per save, at most one at a time.
- Tests write only under `make_save_test_directory`.

### Decisions

1. The lone host skips the hash (`session_alone`); nothing else about the hash changes. Why: the code shows no comparison can read it (above), and the alternatives cost more for no reader.
2. The snapshot copies the changed chunks whole, a few MB in a typical world; no cache or copy on write. Why: the simplest snapshot that cannot tear; the profiler decides whether the worst case needs more.
3. world.sjson, entities.bin and the block regions are encoded on the main thread inside the snapshot, not deep copied. Why: their bytes are their copy (about 320 KB), the encoder is the one the hash already runs there, and a deep copy of the entity pools would be a second, error prone state copy.
4. Every synchronous save stays synchronous and waits for the job first (a new world's first save, quit, quit to title, the socket's `save` whose answer must say saved, the server's stop). Why: each needs the result before going on, and one writer of `<world>.saving` at a time.
5. The pause menu's Save goes off the frame with the autosave. Why: with a client the host's pause menu does not pause, so its save is a hitch like the autosave's.
6. The server's autosave goes off the frame too. Why: the same procedures, and a server's stall holds every client's records.
7. `ticks_since_save` resets at the snapshot, and a failed autosave waits for the next interval on every machine (the server's rule). Why: the result comes frames later, and retrying a failing disk every frame would start a snapshot and a thread each frame.
8. No save on an Android pause: none exists today and it is a new feature; a save in flight runs on by itself.

### Questions to the main agent

1. With a client, every hash tick still runs on the main thread: `write_simulation_state` (about 307 KB) and 208,896 bytes for each loaded field chunk changed since the last hash (25 walking, 5.2 MB), and the host's first hash after a join reads every loaded chunk (26 to 37 MB). 0342 has no view with a joined machine. Recommendation: no change here; a follow-up item only if a profile with a loopback client shows the hash frame over budget.
2. The snapshot's worst case copies every loaded chunk (47 to 65 MB) on the main thread when a tick has changed all of them (a dug out base, wide water). Recommendation: ship the plain copy and profile a dug out view; the encoded bytes cache of Rejected is the next step only if that frame is over budget.

### Acceptance by 0342's table

- Sections: `Frame_Section.Ticks` (the hash runs inside `run_session_tick`), `Tick_Section.State_Hash` with `Tick_Profile.state_hashes` and `Frame_Event.State_Hash`; `Frame_Section.Save` (the snapshot and the job's join and free) with `Frame_Event.Save` (the snapshot's frame). Report lines: `ticks <n> mean <ms> worst <ms> hashes <n> saves <n>`, `cpu ticks`, `cpu save`, `tick state_hash`, `worst frame <frame> work <ms> ticks <n> events <...>`.
- Run: view 2 with `--set=settings.autosave_minutes=1` instead of 0342's 0, held until the sample covers at least 3,600 ticks and `saves` is at least 1, on `main` before this item and after it. Before: `hashes` is the ticks over 300 and the worst frames carry `state_hash` and `save`. After: `hashes 0`, and `cpu save`'s worst is the snapshot alone.

### Decisions (main agent, 2026-11-11)

1. The hash with a client joined stays on the main thread here. It becomes an item of its own once 0342 has a view with a joined machine to measure it by.
2. The plain chunk copy ships. A cache of encoded bytes waits for 0342's table of a dug-out view.
3. Implemented after 0342, on its tree: the same files, and its table is the acceptance.

### Deviations (implementation, 2026-11-12)

- `copy_field_save_inputs` (`session_save.odin`, with a `core:mem` import for its allocator parameter) holds the field part of `take_save_snapshot`, so the snapshot procedure stays short.
- `begin_due_session_save` returns `started` false when `start_session_save` gives a problem: no snapshot was taken, so the profile's Save event stays off that frame. The toast still shows.
- The loopback hash test reads the host's tick before the frame that sent the world (`send_world_noting_alone_ticks`) and asserts no hash at or below it: a due tick between the snapshot and the end of that frame is hashed rightly, so the spec's T taken after the frame could fail by chance.
- `run_lockstep_test_ticks` takes `below_tick` (default `max(u64)`) for the joiner's ticks up to 600 instead of a copy of its loop.
- The byte equality test also asserts that the live state's encoding after the change differs from the on-frame save, so the equality cannot hold by a change that reaches no byte. The second save test sets `ticks_since_save` to 5 first, so its reset shows.
- The only "300 ticks" line is in 0342's done item, a record left as written. The fact went to architecture.md, Performance, the frame profile's counters.
- code_map.md's loop row has the measured 20 files and 10692 lines, which include drift from items before this one.
