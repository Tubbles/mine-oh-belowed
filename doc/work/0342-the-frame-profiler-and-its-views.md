# 0342: The frame profiler and its views

Status: designed (2026-11-11)

0340's research found that nothing has ever timed a frame on the couch's GPU: the F3 frame time includes the wait for the display, and the cost items (0310, 0311, 0328) left estimates. The target (the user, 2026-11-11): 60 frames a second on average at 1080p and 60 Hz on the couch, with the view at 512 m, in split screen too, with an early game factory of a handful of machines; the Steam Deck is a target, the phone secondary.

## Goal

A table of what a frame costs on the couch's GPU in fixed views, CPU and GPU apart, repeatable from one command in the night window without the TV, so every later performance item is chosen and accepted by it.

## Controls

None.

## Change

- A frame profile in the game: the frame's CPU sections, the GPU's time for the frame and its passes, the tick's sections, the draw calls and vertices of the field's renderer, read through the command socket and shown on the F3 Render page (whose counters are the block renderer's today).
- Fixed views (the home, the spring, a forest, a lake, a cave mouth after 0327, a ridge line, an early factory of a handful of machines, each also in split screen, at a 512 m and a 1024 m view) set through the command socket, and a script that runs them and writes the table.
- The run: under a nested `gamescope --backend headless -W 1920 -H 1080`, which gave the game the RX 5700 on 2026-11-11 with no TV and no root (the `gl:` line of `tmp/gamescope_try/out.log`), vsync and the frame cap off, a session that reads no device (0341), its own runtime directory so its command socket cannot meet a play session's, the GPU's clock and load logged beside the timers and never forced. A benchmark under the global rules: 03:00 to 06:00 Europe/Stockholm, `~/benchmark.lock`.
- The trial's log read `window 1920 x 1080, render 1280 x 720`: whether the game draws at 720p on a 1080p display is settled here first, since it changes the fill by 2.25 times.
- Docs: `doc/architecture.md` (Performance: the method, the budget, the table), `doc/build.md` (the command), `doc/commands.md`.

## Verify

- The checks and the suite.
- The night's table on `main` for every view against the budget, with the `gl:` line naming the RX 5700, sent to the user.

## Specification (design, 2026-11-11)

Designed against `main` at `b834a1a` and the specifications of 0341 (`--input=none`, `stick`) and 0343 (`view_distance <metres>`, answering `ok view distance <metres> m`). The game's side needs neither; the run script needs both. `Command_Control` gains fields beside 0341's `input_waiting`, and `serve_command_socket`'s loop condition takes both waits.

### Decisions

1. **The 720p line is stale, the game draws at 1920 by 1080.** `update_display` logs `log_display_diagnostics` right after `apply_display_changes`. raylib's `ToggleBorderlessWindowed` sets `CORE.Window.screen` to the monitor's mode in the call (`rcore_desktop_glfw.c`, 279 to 285), but `CORE.Window.render`, which `GetRenderWidth` reads, changes only in `FramebufferSizeCallback`. GLFW calls that when it processes the X server's `ConfigureNotify` (`x11_window.c`, 1487 to 1497), in the next `glfwPollEvents` (EndDrawing's `PollInputEvents`). So the line printed the render size from before the window grew, and nothing logged after. No code path keeps 720p. Fix: the loop logs the display line again when the render size differs from the last logged one (`Frame_Presentation.logged_render_size`). A settings change whose size changes at once logs twice, and a window drag logs once per changed frame; both are accepted. Proof in the run: every sample answers `display render W H`, and the script refuses a run whose render is not 1920 1080.
2. **CPU sections, always on.** A mark reads `time.tick_now()`, adds the time since the last mark (and the draw calls since then) to the open section and opens its own. A section entered twice in a frame adds up, so in split screen each section sums its viewports. Cost: about 25 marks a frame with one viewport and 70 with four, plus about 30 clock reads a tick (decision 4), each a vDSO read of tens of nanoseconds. That stays on in every build, with no switch, so F3 shows live numbers anywhere. Work is the frame's sum less Present; wall is the sum.

   | Section | Mark (opens it) | Covers |
   |---|---|---|
   | Input | `begin_profiled_frame`, first line of `update_frame` | frame time, pads, input frames, `update_frame_world` up to the ticks |
   | Ticks | `update_session`, before `hold_local_commands` | held lines, the tick loop, the exchange, the tick command's ticks, `rebuild_prediction` |
   | Save | before `save_when_due` | the save, `show_network_notices` |
   | Streaming | before `stream_session_chunks` | the selection and the jobs |
   | Requests | `update_frame`, after `update_frame_world` | the socket, the haptics, `serve_frame_requests_before_draw` |
   | Prepare | first line of `render_frame` | `place_viewports`, the block meshes, the sky, `prepare_field_frame`, a single viewport's BeginDrawing and clear |
   | Sky | `draw_field_viewport_world`, after the ready check | camera, lights, `draw_field_sky` |
   | Shadow_Terrain | `draw_field_sun_shadows`, after its early returns | the map's begin, `draw_sun_shadow_terrain` |
   | Shadow_Trees | before the trees' `if` | the casting trees |
   | Shadow_Models | before `rl.BeginShaderMode` | frames, machines and players into the map; the target bound again, BeginMode3D |
   | Lights | first line of `draw_field_scene` | interior, point and spot lights, the open sky |
   | Globe | before `draw_field_globe` | |
   | Terrain | before `draw_field` | the frustum and the node loop |
   | Cover | in `draw_field`, before `draw_field_cover` | |
   | Water | in `draw_field`, before `draw_field_water` | |
   | Foundations | before the first `push_pod_transform` | `draw_frames` |
   | Machines | before `draw_entities` | |
   | Trees | before `draw_field_trees` | |
   | Runs | before `draw_belt_runs` | |
   | Effects | before `draw_field_torches` | torches, players, flames, ghosts, the arrival's entry and debris, EndMode3D |
   | Interface | split: in `draw_split_viewports` before `run_viewport_ui`; both: in `render_frame` before the sounds | UI, sounds, the F3 page, screenshots |
   | Composite | split only: before `rl.BeginDrawing()` | the targets onto the window |
   | Present | `end_profiled_drawing`, before `rl.EndDrawing()` | the swap, the event poll, the cap's wait |
   | Between | after `rl.EndDrawing()` | audio, the requests after the draw, the display, the settings, `free_all` |

   A block world session marks no field section, so its world falls in Prepare. The planet preview passes no profile.
3. **GPU timing: timestamp queries per mark.** `glQueryCounter(id, GL_TIMESTAMP)` (core since GL 3.3, raylib's context) at every mark from Prepare up to Present, so the GPU's sections are the CPU's, Prepare to Composite, and the total is Present's timestamp less Prepare's. Elapsed-time queries were rejected: they cannot nest, and they take a begin and an end per pass.
   - Reach: `rl.glfwGetProcAddress` with `proc "c"` types, as `log_gl_info` does, under `when ODIN_PLATFORM_SUBTARGET != .Android`. Never `vendor:raylib`; rlgl's binding has no query call.
   - Latency: a ring of 6 sets of 96 query ids. At each frame's begin the pending sets are read, oldest first, once the last id of the set reports `GL_QUERY_RESULT_AVAILABLE`. The read never waits, and results come one to three frames late. A set still unread when its slot comes round is dropped and counted. After 32 drops in a row the GPU state turns Unavailable, with one log line.
   - Batching: while the GPU is timed, each mark first calls `rlgl.DrawRenderBatchActive()`. That way the batched cubes (foundations, torches, ghosts) are drawn, and timed, inside their own section. Outside timing, no flush happens and play is unchanged.
   - When: only while the F3 Render page shows or a sample runs. The procedures and ids are made at the first want.
   - Android is Unavailable without trying: GLES 3.0 has no timestamp query, and the phone is secondary. Windows takes the Linux path. A translation layer without the procedures is Unavailable, with the log line.
   - Split screen: each viewport's passes mark again, at most 64 marks with four viewports. A mark past 95 is skipped, except Present.
   - Draw calls: a global `frame_draw_calls` (main thread only, like `global_string_table`) counts at the nine mesh draw sites (decision 5). A section's `draws` are the calls between its marks. rlgl's batched cubes are not counted.
4. **Tick sections.** In the game every tick is profiled: `run_ready_ticks` passes the frame profile's `Tick_Profile`, while the server, the benchmark and the tick command pass none. `Tick_Section` gains these sections first: Chunk_Set (`update_simulated_chunks`), Commands (the hook's lines, `apply_player_commands`), Field_Players, Field_Edits (the edits, placements, water edits, pumps), Field_Water (`step_field_water_keeping_events`), Field_Light and Field_Rest (airlocks, refusals, the hit, the landing). It gains State_Hash last. `.Players` keeps only the block players' loop, so the factory benchmark's table gains rows and its `players` row shrinks. `Tick_Profile` gains `longest_seconds` (a whole tick in `run_session_tick`) and `state_hashes`. Hashes run on a host, which every windowed world is, so the run sees them every 300 ticks.
5. **Counters per frame.** Selected_Nodes and Mesh_Uploads are counted in `prepare_field_frame` (the field streaming's `pending_jobs` before and after `upload_streamed_field_meshes`). Mesh_Jobs is the change in `field_streaming.next_revision` across `stream_session_chunks`. Terrain_Nodes, Terrain_Triangles (`mesh.triangleCount` of the drawn nodes), Water_Nodes and Cover_Instances (`cover.drawn_count`) are counted in `draw_field`. Near_Trees, Far_Tiles and Far_Cards (the sum of `tile.count`) are counted in `draw_field_trees`. Shadow_Nodes and Shadow_Trees are counted in `draw_field_sun_shadows`. They sum over the viewports. Events: State_Hash (the frame's ticks hashed) and Save (`save_when_due` saved).
6. **Storage.** `Frame_Developer_Tools.frame_profile`. It holds a ring of the last 64 records and their GPU records for the F3 page, and one sample of up to 36000 frames for the socket. The sample's arrays are reserved at its start, so no allocation lands inside it, and its records are about 400 bytes each, 14 MB at the cap. A new sample clears the last one. The statistics are computed in the game (mean, and p50, p99 and worst by nearest rank: index `ceil(p·n/100) − 1` of the sorted values), so the script only lays them out.
7. **Commands.** `profile`, `viewport` and `query profile` run in the loop, which has the frame state. They are served in `execute_queued_command` like `save`. In any other context (the tick, the server, the benchmark), `execute_command` answers `error <name> runs only in the game`. `as` is a world-changing line, run by the tick.
   - `profile settle [frames]`: frames 1 to 36000, default 3600. It answers once 30 frames in a row (`PROFILE_SETTLED_FRAMES`) had every selected node meshed and the trees' tiles up: `ok settled after <n> frames`. Otherwise, at the limit: `error not settled after <n> frames: <u> nodes unmeshed, trees <settled|loading>`. "Meshed" means the node is in `mesh_revisions` and either has a render or is not in flight (`field_view_unmeshed_nodes`). `pending_jobs` is not used, since the waves' remeshes keep it above 0 near water. On a block world it answers `error no field world`.
   - `profile sample <frames>`: 1 to 36000. It takes the frames that begin after the line, and answers `ok sampled <n> frames` once they and their GPU results (or drops) are in.
   - `query profile`: the last complete sample (lines below). With none taken, it answers `error no profile sample: run profile sample <frames> first`.
   - `viewport add`: a viewport through `add_viewport(state, 0, {})`, with no pad, so its player stands still under `--input=none`. It answers once `viewport_player_ready`: `ok viewport <n> of <count>, player <index>`. With four, `error 4 viewports already`.
   - `viewport remove`: every viewport but the first gets `.Remove_Viewport`, which `serve_viewport_removals` serves after the draw. It answers `ok viewports 1` once one is left, at once when one already is.
   - `as <player> <command> [arguments]`: runs a world-changing command, other than `as` and `blueprint`, for that player index, so the second viewport's player can be teleported and turned. The player index is from 0 to `len(players) − 1` (`parse_ranged_word`). Answer: the inner command's.
   - `viewport` and `as` are refused with other machines, like `tick`: one machine must not move another's player.
   - The waits: `Command_Control.profile_wait` holds later lines as `line_waiting` does. A settle or viewport wait answers `error the world was closed` when the session ends. A sample completes regardless.
8. **The views** (`tools/frame_profile_views.sjson`, read by the script; a cave view is added by the item that lands 0327). Each view runs at 512 m and 1024 m (0343's `view_distance`), in one viewport and in two, at noon, in clear weather. The two viewports are stacked by the default `split_screen` setting, and both players stand at the same place, so the second viewport costs only its drawing, not a second region of streaming.
   - Positions: `stand` (latitude, longitude) plus either `target` (latitude, longitude) with `target_height` metres, or `look` (yaw, pitch).
   - Shipped views: `home` (stand 83.171, 130.477; target 79, 151 at 1.5 m), `spring` (stand 79.159, 150.561; target 79, 151 at 1 m), `forest` (stand 80.6, 132; look 0 0), `lake`, `lake_walk` (`walk [0, 1]`, 3000 frames, one viewport, at the walking pace since sprint toggles), `sea`, `ridge` (coordinates: question 1) and `factory`.
   - `factory`, built last, because machines are drawn at any distance:
     - A pad of 26 by 18 `wooden_foundation` cells on the pod's frame, at the pod's base row. Its corner is at cell x = pod x + size x + 2, at the pod's z.
     - Thirteen machines one row up, at rotation 0, given relative to the pad's corner (x, y, z):
       - `stone_furnace` at (1, 1, 1) and (14, 1, 1), each with coal 20 and hematite 50;
       - `burner_inserter` at (5, 1, 11) and (18, 1, 11);
       - `wooden_chest` at (5, 1, 12) and (18, 1, 12);
       - `assembler_1` at (1, 1, 14);
       - `lab` at (8, 1, 14);
       - `boiler` at (13, 1, 14), with coal 20;
       - `steam_engine` at (17, 1, 13);
       - `small_pole` at (22, 1, 14) and (24, 1, 4);
       - `lamp` at (24, 1, 16).
     - The footprints from `data/machines.sjson` fit the pad. Belts are left out, since `place` refuses runs (question 2).
     - The camera targets the mean of the machines' centres. The stand is 12 m back along the frame's forward axis and 2 m up its up axis.
9. **The run** (`./build.sh frame-profile [view ...]`, a heavy benchmark).
   - Sandbox: build.sh's `guard_benchmark` (40 minutes) and the release build come first. Then `tools/frame_profile.py` starts the game under a nested `gamescope --backend headless -W 1920 -H 1080`, keeping the trial's form for gamescope: `env -u DISPLAY`, the real `XDG_RUNTIME_DIR` (its `gamescope-N` socket and lock), and `XDG_CONFIG_HOME` of the run (none of the user's gamescope scripts).
   - The game's own runtime directory is `$XDG_RUNTIME_DIR/mine-oh-belowed-profile-<pid>` (0700, removed at the end). A path under `tmp/` would exceed the 108 byte socket path limit. So the socket cannot meet a play session's, GLFW finds no `wayland-0` there, and the game reaches no PulseAudio. The game's environment also sets:
     - `-u WAYLAND_DISPLAY`, `XDG_SESSION_TYPE=x11` (gamescope's Xwayland, never the parent compositor);
     - `XDG_CONFIG_HOME`, `XDG_CONFIG_DIRS`, `XDG_STATE_HOME` and `XDG_DATA_HOME` under the run's directory, and `-u MINE_OH_BELOWED_SAVES`: a fresh world, default settings, the user's saves untouched.
   - The game is started as `--dev --input=none --name=frame_profile --set=settings.vsync=false --set=settings.frame_rate_cap=0 --set=settings.master_volume=0 --set=settings.autosave_minutes=0`. It runs free (no vsync, no cap), so the GPU's clock is its own choice and is logged, never forced.
   - World preparation: `pause`, then `tick <arrival_ticks + arrival_settle_ticks>` (read from `data/game.sjson`, 1920 shipped), `resume`, `seat stand`, `camera first`, `weather clear`.
   - Warm-up: `profile settle`, the screenshot, then `profile settle` again. The sample: 600 frames (2 to 4 s at the expected rates; p99 is the sixth worst frame). The run covers 30 configurations in about 25 minutes.
   - The 60 Hz estimate. A free run has fewer ticks per frame than 60 Hz, so the CPU at 60 Hz is `cpu_60 = work_mean + (1 − ticks/frames) × tick_mean`. The frame at 60 Hz is `max(cpu_60, gpu_mean)`.
10. **The budget** (judged at 512 m, in one and two viewports). A run passes when the frame at 60 Hz is at most 16.67 ms: the user's bar, 60 frames a second on average at 60 Hz. The notes column flags:
    - `gpu` when the GPU mean is over 14 ms, or `cpu` when cpu_60 is over 14 ms (less than 2.6 ms of headroom left for the compositor and a busier world);
    - `tick` when the tick mean is over 2 ms or its worst over 3 ms (0340's tick budget);
    - `hitch` when the work's or the GPU's p99 is over 16.67 ms, or the worst over 33.3 ms.

    1024 m runs are reported, not judged.

### Files and procedures

`src/render_frame_profile.odin` (new, presentation)
- Constants:
  - `FRAME_PROFILE_RECENT_FRAMES :: 64`;
  - `FRAME_PROFILE_GPU_SETS :: 6`;
  - `FRAME_PROFILE_MAXIMUM_MARKS :: 96`;
  - `FRAME_PROFILE_GPU_DROP_LIMIT :: 32`;
  - `MAXIMUM_PROFILE_SAMPLE_FRAMES :: 36000`;
  - `GL_TIMESTAMP :: 0x8E28`, `GL_QUERY_RESULT :: 0x8866`, `GL_QUERY_RESULT_AVAILABLE :: 0x8867`.
- Types:
  - `Frame_Section` (the 24 of decision 2, in that order);
  - `Frame_Counter` (Selected_Nodes, Terrain_Nodes, Terrain_Triangles, Water_Nodes, Cover_Instances, Near_Trees, Far_Tiles, Far_Cards, Shadow_Nodes, Shadow_Trees, Mesh_Jobs, Mesh_Uploads);
  - `Frame_Event :: enum u8 {State_Hash, Save}`.
- `Frame_Record :: struct`:
  - `frame: int`;
  - `cpu: [Frame_Section]f32` (ms);
  - `draws: [Frame_Section]u32`;
  - `counters: [Frame_Counter]i32`;
  - `ticks: u16`;
  - `tick_sections: [Tick_Section]f32` (ms summed over the frame's ticks);
  - `longest_tick: f32`;
  - `events: bit_set[Frame_Event]`.
- `Frame_Gpu_Record :: struct {frame: int, sections: [Frame_Section]f32, total: f32}` (ms).
- `Profile_Display :: struct {render, window: [2]int, viewports: int, vsync: bool, frame_rate_cap: int}`.
- `Frame_Sample :: struct {wanted, first, gpu_dropped: int, records: [dynamic]Frame_Record, gpu: [dynamic]Frame_Gpu_Record, display: Profile_Display}`.
- `Frame_Gpu_State :: enum u8 {Off, Ready, Unavailable}`.
- `Frame_Gpu_Procedures`: five `proc "c"` fields:
  - `generate_queries(count: i32, ids: [^]u32)`;
  - `delete_queries(count: i32, ids: [^]u32)`;
  - `query_counter(id, target: u32)`;
  - `get_query_object_int(id, name: u32, value: ^i32)`;
  - `get_query_object_u64(id, name: u32, value: ^u64)`.
- `Frame_Gpu_Set :: struct {ids: [FRAME_PROFILE_MAXIMUM_MARKS]u32, sections: [FRAME_PROFILE_MAXIMUM_MARKS]Frame_Section, count, frame: int, pending: bool}`.
- `Frame_Gpu :: struct {state: Frame_Gpu_State, procedures: Frame_Gpu_Procedures, sets: [FRAME_PROFILE_GPU_SETS]Frame_Gpu_Set, timing: bool, drops_in_a_row, dropped: int}`.
- `Frame_Profile :: struct`:
  - `frame: int`;
  - `current: Frame_Record`;
  - `open: Frame_Section`;
  - `last_mark: time.Tick`;
  - `draws_at_last_mark: int`;
  - `tick_profile: Tick_Profile`;
  - `recent: [FRAME_PROFILE_RECENT_FRAMES]Frame_Record`, `recent_gpu: [FRAME_PROFILE_RECENT_FRAMES]Frame_Gpu_Record`, `recent_count, recent_gpu_count: int`;
  - `sample: Frame_Sample`;
  - `sampling: bool`;
  - `gpu: Frame_Gpu`.
- `Section_Statistics :: struct {mean, p50, p99, worst: f32}`.
- `Profile_Report :: struct`:
  - `frames, gpu_frames, gpu_dropped: int`;
  - `seconds: f64`;
  - `display: Profile_Display`;
  - `work, wall, gpu: Section_Statistics`;
  - `cpu, gpu_sections: [Frame_Section]Section_Statistics`;
  - `draws_mean: [Frame_Section]f32`, `draws_worst: [Frame_Section]u32`;
  - `counters_mean: [Frame_Counter]f32`, `counters_worst: [Frame_Counter]i32`;
  - `ticks: int`, `tick_mean, tick_worst: f32`, `state_hashes, saves: int`;
  - `tick_sections: [Tick_Section]f32` (mean ms per tick);
  - `worst: Frame_Record` (the frame of the largest work).
- `frame_draw_calls: int`, package level, with a comment saying it is main thread only. `count_draw_call :: proc()` adds 1.
- Pure:
  - `mark_frame_section :: proc(profile: ^Frame_Profile, section: Frame_Section, now: time.Tick, draw_calls: int)`: the interval and the draws since the last mark go to `open`; then `open = section`.
  - `begin_profiled_frame_at :: proc(profile: ^Frame_Profile, now: time.Tick, draw_calls: int)`: when `frame > 0`, it closes the open section, moves the tick profile into the record (`take_tick_profile`) and files it (`file_frame_record`). Then `frame += 1`, `current = {frame = frame}`, and Input opens at `now`.
  - `take_tick_profile :: proc(record: ^Frame_Record, ticks: ^Tick_Profile)`: copies in ms, sets `.State_Hash` when `state_hashes > 0`, and zeroes the tick profile.
  - `file_frame_record :: proc(profile: ^Frame_Profile, record: Frame_Record)`: puts the record in the ring, and appends it to the sample while `sampling` and `first <= record.frame < first + wanted`.
  - `gpu_record_from_marks :: proc(frame: int, sections: []Frame_Section, timestamps: []u64) -> Frame_Gpu_Record`: the interval from mark i−1 to mark i goes to `sections[i−1]`, a negative difference counts 0, and `total` is the last timestamp less the first.
  - `file_gpu_record :: proc(profile: ^Frame_Profile, record: Frame_Gpu_Record)` and `file_gpu_drop :: proc(profile: ^Frame_Profile, frame: int)`: the ring, or the counts, plus the sample within its frames.
  - `start_frame_sample :: proc(profile: ^Frame_Profile, frames: int)`: clears both arrays, reserves `frames`, sets `first = frame + 1` and `sampling = true`.
  - `frame_sample_complete :: proc(profile: Frame_Profile) -> bool`: all records are in, and either the GPU is not Ready or `len(gpu) + gpu_dropped >= wanted`.
  - `section_statistics :: proc(values: []f32) -> Section_Statistics`: sorts in place, nearest rank, all zero when empty.
  - `frame_record_work :: proc(record: Frame_Record) -> f32` (the sum less Present) and `frame_record_wall` (the sum).
  - `frame_profile_report :: proc(records: []Frame_Record, gpu: []Frame_Gpu_Record, gpu_dropped: int, display: Profile_Display) -> Profile_Report`: works in temp memory. `seconds` is the sum of the walls. `tick_mean` is the sum of every tick section over `ticks`, and `tick_worst` is the largest `longest_tick`.
  - `recent_frame_profile_report :: proc(profile: ^Frame_Profile) -> Profile_Report`: the report over the ring's filled part.
- Impure:
  - `begin_profiled_frame :: proc(profile: ^Frame_Profile, gpu_wanted: bool)`:
    - collects the readable sets (`collect_gpu_sets`);
    - calls `begin_profiled_frame_at(profile, time.tick_now(), frame_draw_calls)`;
    - on the first want, calls `load_frame_gpu`;
    - sets `gpu.timing = gpu_wanted && gpu.state == .Ready`;
    - when timing, takes slot `frame % FRAME_PROFILE_GPU_SETS`. A pending set there is a drop (`file_gpu_drop`, `drops_in_a_row += 1`; at the limit the state turns Unavailable and logs `profile: GPU timer queries never became readable, the profile times the CPU only`). Then `count = 0`, `frame = frame`.
  - `profile_mark :: proc(profile: ^Frame_Profile, section: Frame_Section)`: nil-safe.
    - When timing, it flushes `rlgl.DrawRenderBatchActive()`.
    - Calls `mark_frame_section(profile, section, time.tick_now(), frame_draw_calls)`.
    - When timing and `section >= .Prepare`, issues `query_counter` into the slot. Count is below 95, or Present takes the last.
    - At Present, sets `pending = count >= 2`.
  - `end_profiled_drawing :: proc(profile: ^Frame_Profile)`: `profile_mark(.Present)`, `rl.EndDrawing()`, then marks Between.
  - `count_frame :: proc(profile: ^Frame_Profile, counter: Frame_Counter, amount: int)` and `note_frame_event :: proc(profile: ^Frame_Profile, event: Frame_Event)`: both nil-safe.
  - `collect_gpu_sets :: proc(profile: ^Frame_Profile)`: oldest first. A pending set whose last id is available is read with `get_query_object_u64(GL_QUERY_RESULT)`, filed, and resets `drops_in_a_row`.
  - `load_frame_gpu :: proc(gpu: ^Frame_Gpu)`:
    - Android: Unavailable.
    - Otherwise it loads the five procedures (`glGenQueries`, `glDeleteQueries`, `glQueryCounter`, `glGetQueryObjectiv`, `glGetQueryObjectui64v`).
    - A nil procedure makes it Unavailable and logs `profile: GPU timer queries unavailable (no <name>), the profile times the CPU only`.
    - Otherwise it generates every set's ids, logs `profile: GPU timer queries on`, and turns Ready.
  - `release_frame_profile :: proc(profile: ^Frame_Profile)`: deletes the ids while Ready, and frees the sample.

`src/tick_profile.odin`
- The header comment: the game profiles every tick (0342), and the server and the benchmark keep theirs.
- `Tick_Section` gains the eight sections of decision 4, each with a one-line comment.
- `Tick_Profile` gains `longest_seconds: f64` and `state_hashes: int`.
- `note_longest_tick :: proc(profile: ^Tick_Profile, start: time.Tick)`: nil-safe.

`src/simulation_world.odin`, `simulation_tick`: marks Chunk_Set after `update_simulated_chunks` and Commands after `apply_player_commands`. It passes `profile` to `tick_field_session_players` and reads `profile_now` after it, then marks `.Players` after the block loop as today.

`src/simulation_field.odin`: `tick_field_session_players(state, content, inputs, profile: ^Tick_Profile = nil)`. It marks Field_Players after the loop, passes `profile` to `finish_field_tick`, and marks Field_Rest at its end.

`src/field_mining.odin`: `finish_field_tick(state, content, profile: ^Tick_Profile = nil)`. It marks Field_Edits after `tick_water_pumps`, Field_Water after the step and Field_Light after the light. The two test callers are unchanged.

`src/session_network.odin`: `report_state_hash` returns `hashed: bool`.

`src/lockstep.odin`
- `run_session_tick(session, content, control, answers, profile: ^Tick_Profile = nil)`:
  - reads `start := profile_now(profile)`;
  - passes `profile` to `simulation_tick`;
  - times `report_state_hash` into State_Hash and counts `state_hashes` when it hashed;
  - calls `note_longest_tick(profile, start)`.
- `run_ready_ticks(..., profile: ^Tick_Profile = nil)` passes it on.

`src/loop.odin`
- `Frame_Developer_Tools.frame_profile: Frame_Profile`. `Frame_Presentation.logged_render_size: [2]int` is set to `render_size()` in `run_game`'s literal.
- `update_frame`:
  - first line: `begin_profiled_frame(&state.developer.frame_profile, frame_gpu_wanted(state))`;
  - `profile_mark(.Requests)` after `update_frame_world`;
  - `answer_profile_wait` is called by `serve_command_socket` after `answer_command_ticks`, whose loop adds `&& control.profile_wait == .None`.
- `update_session`:
  - marks Ticks before `hold_local_commands`;
  - passes `&state.developer.frame_profile.tick_profile` to both `run_ready_ticks`, and to the joined catch-up's at line 745;
  - marks Save, and calls `note_frame_event(.Save)` when `save_when_due` returns true;
  - marks Streaming, and counts Mesh_Jobs across `stream_session_chunks`.
- `save_when_due :: proc(state: ^Frame_State) -> (saved: bool)`.
- `render_frame`:
  - first line `profile_mark(.Prepare)`;
  - both `defer rl.EndDrawing()` become `defer end_profiled_drawing(&state.developer.frame_profile)`;
  - the title path marks Interface after its clear;
  - split: marks Composite before `rl.BeginDrawing()`;
  - both: marks Interface after the world, before the sounds.
- `draw_split_viewports`: marks Interface before `run_viewport_ui`.
- `render_facts`:
  - always: `profile = recent_frame_profile_report(...)`, `profile_gpu = frame_profile.gpu.state`;
  - in a field session: `field_session = true`, `loaded_chunk_count = len(field meshes)`, `drawn_chunk_count = drawn_node_count`, `vertex_count` (the field renderer's), `uploaded_mesh_count` (the frame's Mesh_Uploads), `pending_job_count` (the field streaming's).
- `execute_queued_command`:
  - a case placed before the writes case, `words[0] == "as" && !session_alone(state.session.network)`, answers `error as runs only without other machines`;
  - `viewport` joins the `tick`, `pause`, `reload` refusal;
  - `profile`, `viewport` and `query profile` go to `execute_profile_line` where `save` is handled.
- The loop after `update_display`: `state.presentation.logged_render_size = log_display_when_render_changed(state.presentation.logged_render_size, state.presentation.platform)`.
- `run_game` defers `release_frame_profile` before the window closes.

`src/loop_profile.odin` (new, loop)
- `PROFILE_SETTLED_FRAMES :: 30`.
- `frame_gpu_wanted :: proc(state: ^Frame_State) -> bool`: the Render page shows, or `frame_profile.sampling`.
- `profile_display :: proc(state: ^Frame_State) -> Profile_Display`: `render_size()`, the screen size, `viewport_count` and the settings' vsync and cap.
- `execute_profile_line :: proc(state: ^Frame_State, client: u64, words: []string) -> Command_Response`: sends the line to `command_profile`, `command_viewport` or the report.
  - The report is `profile_report_response(frame_profile_report(sample...))`, or the no-sample error.
  - No session gives `error no world is loaded`.
- `command_profile :: proc(state: ^Frame_State, client: u64, arguments: []string) -> Command_Response`:
  - takes `parse_profile_command`, sets the wait, `profile_client` and `profile_frames_left`;
  - for a sample, also calls `start_frame_sample`;
  - returns deferred.
- `command_viewport :: proc(state: ^Frame_State, client: u64, arguments: []string) -> Command_Response`: decision 7.
- `answer_profile_wait :: proc(state: ^Frame_State)`: once a frame, per decision 7.
  - Settle counts `field_view_unmeshed_nodes(&session.field_streaming, &field_renderer, frame_field_selection(state))` and `field_tree_cache_settled(&field_renderer.trees, field_tree_generation(&session.simulation.field), field_viewport_eyes(state))`.
  - A complete sample takes `profile_display(state)` and clears `sampling`.
  - It answers through `send_logged_response` and clears the wait.

`src/command_profile.odin` (new, tools)
- `PROFILE_SETTLE_DEFAULT_FRAMES :: 3600`.
- `parse_profile_command :: proc(arguments: []string) -> (wait: Profile_Wait, frames: int, problem: string)`.
  - The usage is `profile settle [frames] | profile sample <frames>`.
  - Frames go through `parse_ranged_word(word, 1, MAXIMUM_PROFILE_SAMPLE_FRAMES, "the frames")`.
- `parse_viewport_command :: proc(arguments: []string) -> (add: bool, problem: string)`, with the usage `viewport add|remove`.
- `profile_report_response :: proc(report: Profile_Report) -> Command_Response`: the lines below, through `query_response`. Names are the enums' lower case words, and every number is in ms with `%.3f` unless the line says otherwise.

  ```
  ok profile <frames> frames
  frames <n> gpu <n> dropped <n> seconds <%.3f> fps <%.1f>
  display render <w> <h> window <w> <h> viewports <n> vsync <yes|no> cap <n>
  frame work <mean> <p50> <p99> <worst>
  frame wall <mean> <p50> <p99> <worst>
  frame gpu <mean> <p50> <p99> <worst>          (or: frame gpu none)
  ticks <n> mean <ms> worst <ms> hashes <n> saves <n>
  cpu <section> <mean> <p50> <p99> <worst>      (24 lines)
  gpu <section> <mean> <p50> <p99> <worst>      (17 lines, prepare to composite; or one line: gpu none)
  tick <section> <mean per tick>                (28 lines)
  draws <section> <%.1f mean> <worst>           (24 lines)
  count <counter> <%.1f mean> <worst>           (12 lines)
  worst frame <frame> work <ms> ticks <n> events <none|state_hash,save>
  worst cpu <section> <ms>                      (24 lines)
  ```

`src/command.odin`
- `Profile_Wait :: enum u8 {None, Settle, Sample, Viewport_Added, Viewports_Removed}`.
- `Command_Control` gains these fields, under a comment naming `answer_profile_wait`:
  - `profile_wait: Profile_Wait`;
  - `profile_client: u64`;
  - `profile_frames_left, profile_settled_frames, profile_viewport: int`.
- `command_writes_simulation` gains `as`.
- `execute_command`:
  - `case "profile", "viewport"`: `command_error("%s runs only in the game", name)`;
  - under `query`, `profile`: `command_error("query profile runs only in the game")`;
  - after the world check, `case "as": return command_as(...)`.
- `command_as :: proc(command_context: Command_Context, arguments: []string) -> Command_Response`:
  - fewer than two arguments: `usage_error("as <player> <command> [arguments]")`;
  - the player through `parse_ranged_word(arguments[0], 0, len(players) − 1, "the player")`;
  - an inner name that is not `command_writes_simulation`, or is `as` or `blueprint`: `command_error("as takes a command that changes the world, other than as and blueprint")`;
  - then `execute_world_command` with `player` replaced.
- `command_usages` gains these rows:
  - `{"profile settle [frames]", "waits until the view is meshed and its trees are up, 30 frames in a row (frames 1 to 36000, default 3600)"}`;
  - `{"profile sample <frames>", "times the next frames (1 to 36000) for query profile"}`;
  - `{"viewport add|remove", "a split screen viewport with a new local player, or every viewport but the first removed"}`;
  - `{"as <player> <command>", "a world changing command for another local player"}`.
- `command_query`'s usage adds `profile`.

`src/render_field.odin`
- `draw_field(..., profile: ^Frame_Profile = nil)`:
  - marks Cover and Water;
  - counts Terrain_Nodes, Terrain_Triangles, Cover_Instances, and Water_Nodes (`has_water` over `visible`).
- `count_draw_call()` at the three `rl.DrawMesh` sites.
- `field_view_unmeshed_nodes :: proc(streaming: ^Field_Streaming, renderer: ^Field_Renderer, selection: []Field_Node) -> int`: decision 7's rule.

`src/loop_field_session.odin`
- `Field_Scene.profile: ^Frame_Profile`, set in `draw_field_viewport_world` and nil in the planet preview.
- The marks of decision 2 in `draw_field_viewport_world`, `draw_field_sun_shadows` and `draw_field_scene` (which passes `scene.profile` to `draw_field`).
- `draw_sun_shadow_terrain` returns the count it drew. Shadow_Nodes and Shadow_Trees are counted.
- `count_draw_call()` at line 685.
- `prepare_field_frame` counts Selected_Nodes and Mesh_Uploads.

Count sites
- `count_draw_call()` at `render_field_cover.odin:520`, `render_field_trees.odin:691` and `:718`, `render_models.odin:435` and `render_sky.odin:280`.
- `draw_field_trees` counts Near_Trees, Far_Tiles and Far_Cards through `scene.profile`.

`src/diagnostics.odin`
- `Render_Facts` gains `field_session: bool`, `profile: Profile_Report` and `profile_gpu: Frame_Gpu_State`.
- `render_page_lines`:
  - The chunk line reads `field nodes meshed %d  drawn %d  vertices %d` in a field session.
  - The water and particle lines merge into `water meshes drawn %d  flames %d  particles %d  weather particles %d`.
  - After the atlas line come a blank, then the header `profile %d frames  work %.2f ms  gpu <%.2f ms|off|unavailable>  present %.2f ms  draws %d`.
  - Then six rows of four sections in the enum's order, each `<section> %.2f`, or `<section> %.2f/%.2f` (cpu/gpu) for a GPU section while GPU frames exist.
  - Then `tick %.2f  field players %.2f  edits %.2f  water %.2f  light %.2f  machines %.2f  hash %.2f`, means per tick, where machines is Belts through Outcrops_And_Crates.
  - Then three rows of four counters, `<counter words> %d` (rounded means).
  - That makes 27 lines.

`src/display.odin`: `log_display_when_render_changed :: proc(logged: [2]int, platform: Window_Platform) -> [2]int` logs `log_display_diagnostics` when `render_size()` differs, and returns it.

`build.sh`
- Header comment and usage line: `frame-profile [view ...]`.
- `frame-profile) shift; guard_benchmark "./build.sh frame-profile" 40; build "${release_flags[@]}"; python3 tools/frame_profile.py "$@" ;;`, not `exec`, so the trap releases the lock.
- `nightly` does not run it: the views need gamescope and 25 minutes of the GPU.

`tools/frame_profile.py` (new; Python standard library and `tools/sjson.py`)
- Arguments:
  - `--frames 600`;
  - `--views tools/frame_profile_views.sjson`;
  - `--binary build/mine-oh-belowed`;
  - `--output tmp/frame_profile/<UTC stamp>`;
  - `--check`;
  - view names (default all).
- Outside `--check` it exits 2 unless `~/benchmark.lock` exists and its `pid=` is `os.getppid()` (`run through ./build.sh frame-profile`).
- `--check` exits 2 while the lock exists. It runs every view once at 512 m in one and two viewports, with `--set=settings.frame_rate_cap=30` and 30 frames sampled, for the framing and the setup, and heads the table `check, not a measurement`.
- Start: decision 9's environment and command, with gamescope's output to `<output>/gamescope.log` in a new process group.
  - Wait up to 120 s for the socket, then `query world` until it answers `ok`.
  - Refuse (exit 1, the line printed) when the log's `gl:` line names `llvmpipe` or `softpipe`, or its last `display:` line does not say `session x11`.
- Socket: its own client (`AF_UNIX`; a line in; the answer's lines up to a line `.`), with a 900 s timeout per line.
  - A setup line answered `error` marks that run `failed: <line>: <answer>` and goes on to the next.
  - A dead game or socket stops the whole run and writes the partial table.
- Order, so one extra player is ever added:
  1. Preparation.
  2. Every view but the factory in one viewport.
  3. `viewport add`, keeping its answered player index `p`, then those views in two viewports.
  4. The factory built.
  5. The factory in two viewports, `viewport remove`, then the factory in one viewport.
- One run (view, viewports, distance):
  1. `view_distance <d>`, `time noon`, `weather clear`.
  2. Positioning:
     - With a target: `teleport <target>` (the answer's `at x y z` is the surface point T), then `teleport <stand>` and `look at <T + target_height × T/|T|>`.
     - With a look: `teleport <stand>` and `look <yaw> <pitch>`.
     - In two viewports, the same lines for player p through `as p`.
  3. `profile settle`, the look lines again (the player dropped onto the ground), then `screenshot <view>_<viewports>vp_<d>m`, waiting up to 10 s for the PNG under the run's state directory.
  4. `profile settle`, then `stick left <walk>` for the walk.
  5. The sampler thread starts, `profile sample <frames>` runs, and the thread stops. Then `stick left 0 0`, and `query profile`, saved as `<view>_<viewports>vp_<d>m.txt`.
- The factory build:
  - `teleport pod`, then `query entities pod 64` (frame f, cell, size), then `query frames 64` (f's up and forward).
  - `pause`, then the 468 foundation lines `place wooden_foundation <f> <x> <y> <z> 0`, the machine lines `place <machine> <f> <x> <y> <z> 0` and the `insert <item> <count> <f> <x> <y> <z>` lines, then `resume`.
  - `query entities <machine> 64` for each machine id; the centres whose cell was placed give the target.
  - The stand is the target − 12 × forward + 2 × up, by `teleport x y z`.
  - A refused line fails the factory runs, with the line and the answer in the table.
- Sampler thread: every 0.1 s, on the DRM card whose `device/vendor` is `0x1002`, it reads `pp_dpm_sclk` (the `*` line, in MHz) and `gpu_busy_percent`. It gives their means and the clock's maximum, or `-` without such a card.
- End: `os.killpg` with SIGTERM, then SIGKILL after 10 s. The game's log, the screenshots and the answers are copied into `<output>`, and the private runtime directory is removed.
- `<output>/table.md`:
  - The head: the date, `--version`'s stamp, the `gl:` line and the budget.
  - The main table: `| view | viewports | m | fps | GPU mean | GPU p99 | CPU 60 Hz | work p99 | tick mean | tick worst | frame 60 Hz | headroom | sclk MHz (mean/max) | busy % | verdict | notes |`, where verdict is `pass`, `fail`, `report` (1024 m), `failed: ...` or `unsettled`.
  - Then `CPU sections (mean ms)`, `GPU sections (mean ms)` and `Counts (mean)`, a row per run.

`tools/frame_profile_views.sjson` (new)
- `frames = 600`, `distances = [512, 1024]`, `viewports = [1, 2]`.
- `views = [...]`: decision 8's entries with keys `name`, `stand`, `target`, `target_height`, `look`, `walk`, `frames`, `viewports`.
- `factory = {pad = [26, 18], gap = 2, back_metres = 12, up_metres = 2, machines = [{machine, cell, insert = [[item, count]]}]}`, with decision 8's values.
- A head comment names 0342 and the script.

### Tests

`src/render_frame_profile_test.odin`
- `test_marks_add_each_interval_to_the_open_section`:
  - Times built with `time.tick_add` from a zero tick: begin at 0, Ticks at 1 ms, Prepare at 3 ms, Ticks at 4 ms, the next begin at 6 ms.
  - The filed record: Input 1, Ticks 4, Prepare 1, wall 6, work 6 (no Present), frame 1.
- `test_draw_calls_are_counted_per_section`: `draw_calls` 0, then 5 at the Terrain mark, then 12 at the next. Terrain holds 7, and the section before it holds 5.
- `test_gpu_timestamps_sum_into_their_sections`:
  - Sections [Prepare, Terrain, Prepare, Present] at [0, 1e6, 3e6, 4e6] ns: Prepare 2 ms (1 + 1), Terrain 2 ms, total 4.
  - A timestamp below its predecessor counts 0.
- `test_section_statistics_take_the_nearest_rank`:
  - Values 100 down to 1: mean 50.5, p50 50, p99 99, worst 100.
  - [7]: all 7.
  - [] gives zeros.
- `test_a_sample_takes_the_frames_after_its_start_and_completes`:
  - A sample of 3 started at frame 5 with the GPU Off takes frames 6, 7 and 8 only, and is complete after 8.
  - With the GPU Ready, it is complete only once three GPU records or drops are filed.
  - A GPU record of frame 4 is not taken.
- `test_the_recent_report_averages_the_ring`: 70 records with work k ms (k = 1 to 70): frames 64, work mean 38.5, worst 70.

`src/command_profile_test.odin`
- `test_the_profile_report_names_every_section`:
  - Two records: Input 1 and Present 3, then Input 2 and Present 1; ticks 1 and 0; Field_Water 0.5; `longest_tick` 0.5; display 1920 by 1080, one viewport, vsync off, cap 0; no GPU.
  - The text starts `profile 2 frames\nframes 2 gpu 0 dropped 0 seconds 0.007 fps 285.7\ndisplay render 1920 1080 window 1920 1080 viewports 1 vsync no cap 0\nframe work 1.500 1.000 2.000 2.000\nframe wall 3.500 3.000 4.000 4.000\nframe gpu none\nticks 1 mean 0.500 worst 0.500 hashes 0 saves 0\n`.
  - The text holds `gpu none`, `tick field_water 0.500`, a `cpu`, `draws` and `worst cpu` line for every section, and a `count` line for every counter. It has 121 lines.
  - With two GPU records, it holds 17 `gpu <section>` lines and a `frame gpu` statistics line.
- `test_profile_commands_check_their_numbers`:
  - `settle` gives Settle 3600.
  - `settle 0` and `settle 36001` are refused (`the frames must be a number from 1 to 36000`).
  - `sample` without a number, `sample 1 2` and `bogus` give the usage.
  - `viewport add` and `remove` parse; `viewport sideways` gives its usage.
- `test_as_runs_a_command_for_another_local_player`:
  - Uses `make_field_command_test` with `add_player_entry(&test.session.simulation, test.content, 1, Player_Start{})`.
  - `as 1 look 90 0` turns player 1 to yaw 90, and player 0 keeps its yaw.
  - Refused: `as 2 look 0 0` (the player range), `as 1 query player`, `as 1 as 0 look 0 0` and `as 1 blueprint x.sjson`, each with the message.
  - `as 1` gives the usage.
- `test_profile_and_viewport_run_only_in_the_game`: `profile sample 10`, `viewport add` and `query profile` through `run_field_command` answer `error ... runs only in the game`.

`src/viewport_test.odin`: `test_the_viewport_command_waits_for_its_player_and_removes_after_the_draw`, over `make_viewport_test_frame`:
- `command_viewport(state, 7, {"add"})` is deferred with `.Viewport_Added`, and the count is 2.
- `run_viewport_test_frames_until_ready(state, 1)`, then `answer_profile_wait` clears the wait.
- `remove` is deferred, `.Remove_Viewport` is in `viewports[1].requests`, and the count is still 2. `serve_viewport_removals`, then `answer_profile_wait`: the count is 1 and the wait is clear.
- `remove` with one viewport answers `viewports 1` at once.
- A fifth `add` is refused.

`src/render_field_test.odin`: `test_a_view_counts_the_selected_nodes_without_a_mesh`, with hand-built maps:
- a node not in `mesh_revisions` counts;
- one in flight with no render counts;
- one in flight with a render does not;
- one meshed empty (in revisions, not in flight, no render) does not.

`src/tick_profile_test.odin`: `test_a_field_tick_fills_the_field_sections`:
- `make_field_test_game_content`, `start_field_test_session(test_field_game_config(), game)` and `field_test_content`.
- The set is staged as `tick_field_test_simulation` does, then `simulation_tick` runs twice with a profile.
- Expected: `ticks == 2`, the five field sections summed > 0, and `State_Hash == 0`.

`src/diagnostics_test.odin`
- `test_render_page_lines_from_facts` is updated for the merged line.
- `test_the_render_page_fits_with_the_profile`: a field session's facts, with every statistic at 99.99, the counters at 9999999 and GPU frames, give at most 28 lines of at most 94 characters. Those are the binding sizes: at 1280 by 720 (the start window, font 20 px) 28 lines fit, and at 1280 by 800 (the audits' smallest window, font 22 px) 94 characters fit.

### Docs

- `doc/architecture.md`, Performance:
  - The profile bullet: the game profiles every tick, with the new sections.
  - A bullet group "The frame profile (0342)": decisions 2 to 6 in a few lines, with the 60 Hz estimate and the budget.
  - A subsection `### The frame table`, with one line on the run command; the main agent writes the night's table under it.
- `doc/build.md`:
  - The build.sh block and its bullets: `frame-profile`, a heavy benchmark, under the same guard.
  - A section `## Frame profile` after Test tiers: decision 9, `--check`, the outputs and the sysfs sampler.
  - Display: the display line is logged again when the render size changes on a later frame, and why.
- `doc/commands.md`:
  - The Commands table: the four rows and `query profile`.
  - Protocol: `profile`, `viewport` and `query profile` run only in the game and wait as a tick line does.
  - A section `## Frame profile` with the query's lines.
  - Multiplayer: `viewport` and `as` are refused with other machines.
- `doc/developer_tools.md`: the Render row, with the field line, the merged line, the profile's header, sections, tick line and counters, and the GPU only while the page shows.
- `doc/code_map.md`:
  - The three new files in their clusters, and the counts.
  - `Frame_Developer_Tools` goes to 12 and `Frame_Presentation` to 18.
  - The `tick_profile.odin` line.

### Hand-back check

- Memory a frame draws from: `viewport remove` goes through `.Remove_Viewport`, served after the draw. A new sample frees only the sample, which nothing draws.
- A number parsed from text: frames and the player through `parse_ranged_word`.
- A list that grows: the sample is capped at 36000 and reserved at its start. The rings and the marks are fixed. The Render page is checked at 28 lines and 94 characters by its test.
- A start-up load that can fail: GPU queries fall back to the CPU only, with one log line.
- Tests touch no state directory: everything is in memory, and the viewport test uses `make_viewport_test_frame`.

### Questions to the main agent

1. The lake, the sea shore and the ridge: their stand and target (or look) are to be picked before approval. The source is `./build/mine-oh-belowed --relief-map=83,132,6000 --relief-map-file=tmp/0342_relief.png` (and a wider square for the sea), the lake also being `lake_walk`'s start with a walk across its shore. I may not run the binary.
2. Belts in the factory. `place` refuses runs. They can be laid by 0341's injected input (select the belt, `pointer` and `press Place` along the run) once the run tool drives that, or left out of this item. I left them out.
3. The free run (as the item says) or a 60 Hz cap. Free keeps the GPU's clock high and measures capacity. A cap shows what DPM does at 60 Hz, at the price of the timer's clock being lower. The sysfs columns show which one the table saw.
4. When `--check` runs: it loads the GPU lightly (capped at 30) for a few minutes outside the window. It is not a benchmark by the rules, but the user may be playing.

### Decisions (main agent, 2026-11-11)

1. The lake's, the sea's and the ridge's coordinates: the implementer finds them with a probe test on the shipped 8 km world (the largest kept lake of the tiles round the home, the nearest coast, the highest crest within 1500 m), writes them into the views file with the probe's log line as the reason, and removes the probe. The main agent checks each by a capture.
2. No belts in the factory view: the user's bar is an early game factory of a handful of machines, which is fed by hand.
3. Uncapped, vsync off: the table is in milliseconds against the budget, not in frames a second.
4. `--check` is the main agent's, after the implementation and at the landing. It is capped and short, so it is no benchmark.
5. A cave view (the spring's cave mouth) joins the views file at 0327's landing, by the main agent.
6. Built on 0343 (`view_distance`) and on 0341 (`--input=none`, landed): the worktree is made from 0343's branch once its review is weighed.
7. Every build or test run goes inside `systemd-run --user --scope --quiet -p MemoryMax=8G -p MemorySwapMax=0`.
8. The ridge view stands at 76.552 N, 133.534 E, the ridge 0349's design counted nodes at, so the two items read one place.
