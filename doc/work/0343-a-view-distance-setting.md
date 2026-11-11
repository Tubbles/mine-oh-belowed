# 0343: A view distance setting

Status: verified (2026-11-11)

The field draws its terrain and its trees to 1024 m, fixed in the code. The user (2026-11-11), asked whether the view may shrink for 60 frames a second: "yes let's make it into a setting if it isn't already, and I can play around with it and say if I think its performant enough. 512 m can be the threshold for 60 fps for now".

## Goal

The player chooses how far the world is drawn, and the 60 frames a second bar is judged at 512 m.

## Controls

No world control changes. The Settings screen gains one entry, View distance, in its graphics group, stepped left and right as the screen's other stepped entries are (focus navigation and the pointer): 256 m, 512 m, 768 m and 1024 m, shipped at 1024 m until 0342's table says what the couch holds.

## Change

- One setting that bounds what the field draws: the terrain's levels of detail, the trees and their cards, the cover, in every viewport, applied without a restart.
- Presentation only: the simulated and streamed set that the lockstep depends on is not the setting's, so two players with different view distances stay in step.
- What is streamed and meshed only for the view shrinks with it, so a shorter view also costs less to fill.
- The command socket sets it, so 0342's views run at 512 m and 1024 m.
- Docs: `doc/presentation.md` (the level of detail, the trees), the settings' doc.

## Verify

- The checks and the suite, with a test that a session's state hash is the same at two view distances.
- Captures of the same view at 512 m and 1024 m, sent to the user.

## Specification (design, 2026-11-11)

Designed against `main` at `704a8d6`. 0341 (implementing) edits the same places in `Command_Context`, `execute_command` (before the world check), `command_usages` and `frame_command_context`. The two changes sit side by side and are joined at the rebase.

### Decisions

1. **What it bounds.** One value, `settings.view_distance_metres`. The view is the smaller of the setting and the data's last distance (`field_view.level_distances_metres[3]`, 1024 shipped), so the setting can only shorten what the data allows.
   - Terrain: the levels are packed inside the view, neither dropped nor rescaled (`field_view_level_distances`). Working from the coarsest level down, the first level that can end at the view is the one that ends there, provided each finer level stays at least its gap below the next (`field_level_gap_metres`: 56, 111, 222 m) and level 0 keeps its data distance. Each finer level takes the smaller of its data distance and the next level's distance less the gap. The coarser levels are left empty: their distance is the view. Shipped data gives: 256 m: 64, 145, 256, 256 (no eighth level); 512 m: 64, 160, 290, 512; 768 m: 64, 160, 384, 768; 1024 m: the data. Why packing: rescaling would cut the full resolution to 16 m at 256, and the cover with it, since the cover ends 8 m inside level 0. It would also break the gap rule at 1 m spacing. Dropping (keep the data distances and stretch the last level kept out to the view) would leave the quarter level reaching from 160 to 512 m at 512. Rough flat ground node counts at 1 m spacing (ring area over node area): dropping gives about 75 nodes at 512, as many as 768 m (74), while packing gives 49. For reference, 1024 m is about 96 and 256 m about 34. Packing keeps the gap rule at every value, and with it the 2:1 balance the skirts assume and a far end without holes.
   - The edge of the view: the haze's end fade (`field.fs`, `model.fs`, `tree.fs`, `cover.fs`) runs from 0.6 to 1 of the view (`FOG_START_SHARE`), as it runs to 1024 m today. Inside the air it fades into the horizon colour at the eye's altitude, warmed towards a low sun. Above the air it fades into the globe's lit colour. The globe beyond takes the same colour, so the land dissolves into the haze and nothing pops. Coarsest nodes that reach past the view are drawn fully faded, as today.
   - Trees: the cards end at the smaller of the row's `far_metres` and the view, and the far fade is at most a quarter of that (`field_trees_view_row`). Tiles are kept out to that far distance plus two tiles, and the scan shrinks with it: 5 by 5 by 5 tiles at 256 m against 17 at 1024. The near trees (96 m) and the caps do not change. The Android row (512) already ends inside 1024.
   - Unchanged, because each already lies inside the least view:
     - the cover: it ends 8 m inside level 0's 64 m, which packing never moves (decision 7 makes sure of that);
     - the lights: the 8 nearest, and torches within 64 m;
     - the sun's shadow box: 64 + 96 m on the desktop, 48 + 64 m on Android. Its terrain is the frame's selection, so it follows the setting.
   - The fall takes the setting too. Below the start's distance from the crater (about 810 m), a short view shows the globe until the pod comes within the view. The data check of the start against the data's last distance stays as it is. The planet preview and the block world keep the data's distances.
2. **Presentation only (from the code).**
   - The simulated set comes from `next_field_chunks` over `field_player_chunk_centres(state.players)` with the data's `field_simulation.chunk_radius` and `chunk_margin`, derived in the tick (`update_simulated_field_chunks`). The frame's requests are `field_chunk_requests(simulation)`, which is the same function plus the prefetch ring. Only the tick inserts or unloads chunks.
   - The setting reaches three things only: `make_field_view` (the selection), the haze's end uniforms and the trees' row.
   - The selection drives `update_field_streaming`'s mesh scheduling. That code copies samples out of the world (`gather_field_grid`, `gather_coarse_field_grid`) and writes only `Field_Chunk.dirty`, `Field_Chunk.wave_dirty` and `Field_World.edited_chunks`. No tick reads those, and neither `simulation_state_hash` nor the save holds them.
   - The tree cache reads only the generation's radius and tree spacing, and its tile jobs run on the worker's own generation.
   - No simulation file references the presentation or `Settings`. Settings never cross the network: a record holds the input frame and commands only. A server meshes nothing and keeps the hash today.
   - Test: `test_two_view_distances_keep_one_state_hash`.
3. **A live change.** The Settings row and the socket write only the int. The rest happens on the next frame:
   - The selection is made at the new distances (`frame_field_selection`, from `update_session`), and `drop_unselected_field_nodes` lists the nodes that left it.
   - `prepare_field_frame` runs before any viewport draws, at the point where `serve_sun_shadows` already runs. It unloads the dropped nodes' meshes (`upload_streamed_field_meshes`), evicts the tree tiles past the new keep distance (`update_field_tree_cache`) and sets the haze's end. Nothing is freed in the UI pass.
   - Each frame uses one set of distances. They are made together with the selection and stored beside it (`Frame_Presentation.field_level_distances`), and `prepare_field_frame` reads them from there. So a socket line served after the selection (`serve_command_socket` runs after `update_frame_world`) takes effect everywhere at once from the next frame. Likewise, a split screen guest who changes the row between two viewports' draws changes neither draw.
   - When the view grows, the new nodes and tiles stream in over the following frames, finest first, as after a load (8 mesh jobs and 4 tiles a frame). A node whose level changes is replaced as on a walk: its old mesh goes when it leaves the selection.
4. **Split screen.** `Settings` belongs to the process, so one value serves every viewport on the machine. The one selection over every eye (`Field_View.more_cameras`), the haze's end and the trees' row all follow from it. In a network game each machine keeps its own value.
5. **The Settings entry.**
   - Placement: the Display tab (the graphics group), right after Sun shadows.
   - Widget: `ui_layout_slider` over `VIEW_DISTANCE_RANGE` {256, 1024, 256}. Left and Right step 256 m while the row is focused, and the pointer taps or drags the track. A drag applies on release, so dragging does not restream the field at every step under the finger. The value is shown by `whole_number_text`, with the unit in the label as Field of view does it.
   - Config key `settings.view_distance_metres`: a whole number from 256 to 1024, checked by `validate_settings`' `range_problem`. A value outside that is refused with the file named; at start the game's own settings file is set aside, as for any refused value (0149).
   - A value between the steps from a hand-edited file is kept and drawn as written. The row's first step puts it on a step by the slider's rounding (600: Right gives 768, Left gives 256).
   - Default: 1024 (`MAXIMUM_VIEW_DISTANCE_METRES`) on every build.
6. **The socket.** `view_distance <metres>` takes 256 to 1024 whole metres (`parse_ranged_word`), sets the setting as the row does and answers `ok view distance <metres> m`.
   - It needs no world and runs on the main thread like `pause`. It is not a tick line, so `command_writes_simulation` stays false and a joined machine may use it.
   - In a context without the frame's settings (the tick's and the benchmark's) it answers `error view_distance runs only in the game`.
   - The change lands in `config.d/90-settings.sjson` at the end of the frame, like any setting changed outside the screen (`write_changed_settings`).
   - What 0342's script can rely on: the answer comes at once and the next frame draws at the new view. Farther nodes and tiles stream in over the frames after, so the script waits for the streaming to settle before it times (that wait is 0342's to design).
   - No general `set` command exists. `--set=settings.view_distance_metres=512` sets the value for one start through the configuration layer.
7. **Data check.** `field_view_problem` refuses a first distance that packing at the least view (256 m) would cut. That keeps the full resolution distance and the cover's reach fixed under the setting. The shipped 64 passes.

### Files and procedures

`src/settings.odin`
- After the ranges: `MINIMUM_VIEW_DISTANCE_METRES :: 256`, `MAXIMUM_VIEW_DISTANCE_METRES :: 1024`, `VIEW_DISTANCE_STEP_METRES :: 256`, `VIEW_DISTANCE_RANGE :: Slider_Range{MINIMUM_VIEW_DISTANCE_METRES, MAXIMUM_VIEW_DISTANCE_METRES, VIEW_DISTANCE_STEP_METRES}`.
- `Settings.view_distance_metres: int` after `sun_shadows`, with a comment: how far the field is drawn, in whole metres (0343, `field_view_level_distances`). `DEFAULT_SETTINGS.view_distance_metres = MAXIMUM_VIEW_DISTANCE_METRES`.

`src/configuration.odin`
- In `validate_settings`, after the frame rate cap's check: `range_problem(provenance, "settings.view_distance_metres", f32(settings.view_distance_metres), MINIMUM_VIEW_DISTANCE_METRES, MAXIMUM_VIEW_DISTANCE_METRES)`.

`src/data_load.odin` (next to `field_view_problem` and `field_trees_row`; write the coarsest level as `FIELD_LEVEL_COUNT - 1`, as `field_view_problem` does, so the content cluster takes no new world reference)
- `field_view_level_distances :: proc(field_view: Field_View_Config, view_distance_metres: int) -> [FIELD_LEVEL_COUNT]int`: decision 1's packing. Let `last := min(view_distance_metres, data[FIELD_LEVEL_COUNT - 1])`. For `coarsest` from `FIELD_LEVEL_COUNT - 1` down to 1, return the first `pack_field_level_distances(data, last, coarsest)` whose `[0]` equals `data[0]`. If none does, return `pack_field_level_distances(data, last, 0)`.
- `pack_field_level_distances :: proc(data: [FIELD_LEVEL_COUNT]int, last, coarsest: int) -> [FIELD_LEVEL_COUNT]int`: the levels from `coarsest` up are set to `last`; each finer level gets `min(data[level], result[level + 1] - field_level_gap_metres(level + 1))`.
- `field_view_problem`: a new last check, after the maximum's: `if field_view_level_distances(field_view, MINIMUM_VIEW_DISTANCE_METRES)[0] != distances[0]`, return `"field_view.level_distances_metres[0] %d leaves the coarser levels no room inside the least view distance, %d m"`.
- `field_trees_view_row :: proc(row: Field_Trees_Row, view_distance_metres: int) -> Field_Trees_Row`: `far_metres = min(row.far_metres, view_distance_metres)`, `far_fade_metres = min(row.far_fade_metres, far_metres / 4)`, every other field from the row.

`src/loop.odin`
- `Frame_Presentation.field_level_distances: [FIELD_LEVEL_COUNT]int`, after `field_selection`: the frame's packed distances, made together with the selection. Not cleared at the end of the frame.
- `frame_command_context`: `settings = &state.settings`, with or without a session.

`src/loop_field_session.odin`
- `field_viewport_selection :: proc(state: ^Frame_State, level_distances_metres: [FIELD_LEVEL_COUNT]int) -> []Field_Node`: passes these distances to `make_field_view` in place of the data's.
- `frame_field_selection`: when it makes the selection, it first sets `state.presentation.field_level_distances = field_view_level_distances(state.config.field_view, state.settings.view_distance_metres)`, then makes the selection with them.
- `prepare_field_frame`:
  - First call `frame_field_selection(state)`, then take `last := state.presentation.field_level_distances[FIELD_COARSEST_LEVEL]`.
  - Before the uploads, set `state.presentation.field_renderer.last_distance_metres = f32(last)`.
  - `update_field_tree_cache` takes `field_trees_view_row(field_trees_row(state.config.field_trees), last)`.
  - The procedure's comment names the view distance.

`src/render_field.odin`
- `Field_Renderer.last_distance_metres`: comment only. `prepare_field_frame` sets it every frame from the frame's distances (0343); the planet preview keeps the data's value from `init_field_renderer`.

`src/ui_screens.odin`
- `DISPLAY_SETTINGS_ROW_COUNT :: 20`.
- `display_settings`, after the Sun shadows toggle: `view_distance := f32(settings.view_distance_metres)`; `if ui_layout_slider(state, cut_row(content), text("settings_view_distance"), &view_distance, VIEW_DISTANCE_RANGE, whole_number_text, text("settings_view_distance_tooltip")) { settings.view_distance_metres = int(math.round(view_distance)) }`. Comment: a drag applies on release, so it does not restream the field at each step.

`src/command.odin`
- `Command_Context.settings: ^Settings`: the frame's settings. It is nil in the tick's context (`session_command_context`) and the benchmark's.
- `command_usages`, after `arrival_camera`: `{"view_distance <metres>", "how far the field is drawn, 256 to 1024 m, as the View distance setting"}`.
- `execute_command`: `case "view_distance": return command_view_distance(command_context, arguments)` next to `pause`, before the world check.
- `command_view_distance :: proc(command_context: Command_Context, arguments: []string) -> Command_Response`:
  - nil `settings`: `command_error("view_distance runs only in the game")`;
  - not exactly one argument: `usage_error("view_distance <metres>")`;
  - a `parse_ranged_word(arguments[0], MINIMUM_VIEW_DISTANCE_METRES, MAXIMUM_VIEW_DISTANCE_METRES, "the view distance")` problem: `command_error` with it;
  - otherwise set the value and answer `command_ok("view distance %d m", metres)`.

`data/game.sjson`: the `field_view` comment adds that the View distance setting packs these levels inside a shorter view (0343), and that the first distance must fit the least view distance, 256 m, together with the gaps.

`data/strings/en.sjson`, after `settings_sun_shadows_tooltip`:
- `settings_view_distance = "View distance (metres)"`
- `settings_view_distance_tooltip = "How far the ground and the trees are drawn. A shorter view saves frame time, and the land beyond it fades into the haze"`

### Tests

`src/data_load_test.odin`
- `test_the_view_distance_packs_the_levels_inside_it`, on the shipped `field_view` (`parse_game_config` of `data/game.sjson`):
  - 256 gives {64, 145, 256, 256}; 512 gives {64, 160, 290, 512}; 768 gives {64, 160, 384, 768}; 1024 and 2048 give the data; 600 gives {64, 160, 378, 600}.
  - For every whole metre from 256 to 1024: `[0]` is 64 and `[3]` is the view. Each level whose distance exceeds the one before does so by at least `field_level_gap_metres` of its level. Once two neighbouring levels are equal, every coarser level equals the view (empty levels only at the coarse end).
- `test_the_first_level_must_fit_the_least_view`: `field_view_problem` passes {200, 300, 520, 1024} and the shipped block, and refuses {210, 300, 520, 1024} with the message above.
- `test_the_trees_row_ends_inside_the_view`:
  - the shipped desktop row at 256 gives far 256 and far fade 64, everything else unchanged; at 1024 it is unchanged;
  - the Android row is unchanged at 1024 (far 512) and gets far 256 at 256;
  - a row with far fade 256 gets far fade 64 at 256.

`src/world_field_streaming_test.odin`
- `test_a_shorter_view_drops_the_far_nodes`: `make_test_planet`, an eye 2 m above the radius, 1 m spacing, the shipped `field_view`. Make the selections at 1024 and at 256.
  - The 256 selection is shorter, holds no level 3 node and no node farther than 256 m (`box_distance_squared`). The 1024 selection holds level 3 nodes.
  - On a streaming with no workers, put every 1024 node in `mesh_revisions` (revision 1, faked as the waves' test does) and run `drop_unselected_field_nodes` with the 256 selection. `dropped` must list exactly the 1024 nodes missing from the 256 selection, and `mesh_revisions` must keep the shared ones.

`src/render_field_trees_test.odin`
- `test_a_shorter_view_evicts_the_far_tree_tiles`: `tree_draw_test_setup`; a cache whose `cells` is `field_tree_tile_cells` of the generation's tree spacing, holding an empty draw for every tile of `field_tree_tiles_around(generation, eyes, 1024)`. Run `update_field_tree_cache` with `field_trees_view_row(shipped desktop row, 256)`, then check:
  - `cache.config.far_metres` is 256;
  - every kept tile lies within 256 m plus `FIELD_TREE_KEEP_TILES` tile edges of the eye's point (`field_tree_tile_distance`), and every tile within that range is kept;
  - nothing is pending.

`src/simulation_field_test.odin`
- Helper `stream_view_distance_test_frame :: proc(session: ^Session, streaming: ^Field_Streaming, trees: ^Field_Tree_Cache, field_view: Field_View_Config, trees_row: Field_Trees_Row, view_distance_metres: int) -> []Field_Node` (temp allocator). In order:
  - make the selection round player 0's eye (`field_player_eye`) at `field_view_level_distances`;
  - call `update_field_streaming` with that selection, the frame table and no requested chunks (the set comes from `tick_field_test_simulation`);
  - `run_queued_field_jobs`, then free the current meshes (mesh, water and cover);
  - call `update_field_tree_cache` with `field_trees_view_row(trees_row, distances[3])`;
  - `run_queued_field_tree_jobs`.
- `test_two_view_distances_keep_one_state_hash` (mark it `// slow` if `build/test_times.tsv` says so):
  - Setup: two sessions prepared as in `test_two_field_simulations_hash_alike_and_part_on_one_input` (the digging kit, moved out of the pod, the script, the hotbar swap at 495), run for 600 ticks.
  - Each session gets its own `start_field_streaming(seed, planet, spacing, 0)` and its own tree cache, with the shipped `field_view` and desktop trees row. One streams at 256 and the other at 1024, every 100 ticks starting at tick 0.
  - Assert that the 256 selection is shorter and holds no level 3 node while the 1024 selection does, and that `simulation_state_hash` is equal at tick 600.

`src/configuration_test.odin`
- `test_settings_file_round_trip`: set `settings.view_distance_metres = 512` and expect the file to hold `\tview_distance_metres = 512\n`.
- `test_the_view_distance_setting_keeps_its_bounds`:
  - no key loads as 1024; 256 and 1024 load; 600 loads as 600;
  - 255 and 1025 are refused (`settings.view_distance_metres is 255, outside 256 to 1024`, and the same for 1025); 512.5 is refused (`must be a whole number`);
  - the assignment `settings.view_distance_metres=512` given to `load_configuration` loads 512, with the command line as its source.

`src/ui_pointer_test.odin`
- `test_the_view_distance_row_steps_by_256_metres`: the Settings screen over Pause at UI scale 1, focus requested on `settings_row_id("settings_view_distance")`, three frames as in `open_ui_scale_slider`. Then:
  - from 1024, Left gives 768, 512, 256, then 256 again; Right gives 512;
  - from 1024, a still tap at the track's left end (the slider's layout, as `open_ui_scale_slider` computes it) gives 256;
  - from 600, Right gives 768; from 600, Left gives 256.

`src/command_test.odin`
- `test_the_view_distance_command_sets_the_setting`, with `settings` set on the test context:
  - `view_distance 512` answers `ok view distance 512 m` and sets 512;
  - 255, 1025, `abc`, no argument and two arguments all fail and keep 512;
  - with nil `settings` it answers with `runs only in the game`;
  - with a nil simulation it still answers ok;
  - `command_writes_simulation("view_distance")` is false.

UI audit: no new case is needed. `settings tab 0` (walk_focus, every size and text scale, the smallest being 960 by 540) already draws the new row at its widest value, 1024, which is the default.

### Docs

- `doc/ui.md`, Settings table, Display, after Sun shadows: `| | View distance (`view_distance_metres`) | 256 to 1024 metres by 256, 1024 (0343): how far the field is drawn ([presentation.md](presentation.md), Field meshes); a value between the steps in a file is kept |`.
- `doc/presentation.md`:
  - Field meshes, Level of detail: the packing, the distances at the four steps, and the frame's stored copy (`Frame_Presentation.field_level_distances`).
  - The field session, the trees: the far distance is `field_trees_view_row`'s.
  - The field session, the selection bullet: one view distance for every viewport.
  - Light on the field, the haze: the end fade runs over 0.6 to 1 of the view distance.
  - The arrival, The start height: a shorter view shows the globe until the pod comes within it.
- `doc/architecture.md`, The field session, the frame side bullet: the setting reaches only the selection, the haze and the tree tiles. The simulated set is the data's radius round the players, so machines with different view distances keep one hash (`test_two_view_distances_keep_one_state_hash`).
- `doc/content.md`, the `field_view.level_distances_metres` line: the first distance must fit the least view distance together with the gaps (`field_view_problem`), and the setting packs the levels (presentation.md).
- `doc/commands.md`: a table row for `view_distance`, and `view_distance` added to the Protocol line's list of commands that need no world.
- `doc/code_map.md`: the content section's `data_load.odin` entry names `field_view_level_distances` and `field_trees_view_row` if it lists procedures. There is no new cluster edge (loop, ui and tools reach into content).

### Hand-back check

- Frees between frames: applies. The meshes of dropped nodes and the evicted tree tiles are freed in `prepare_field_frame`, before any viewport draws. The row and the socket only write an int (decision 3). The tests are `test_a_shorter_view_drops_the_far_nodes` and `test_a_shorter_view_evicts_the_far_tree_tiles`; the GL unload is on the draw path, which is untested.
- A number parsed from text: the socket goes through `parse_ranged_word` and the configuration through `range_problem`.
- A start-up load the game can make fail: a refused value in the game's own settings file goes through 0149's set-aside.
- A shared budget: the streaming's order is unchanged (chunk generation, finest meshes, coarser meshes, waves, then tree jobs only when no chunk or mesh job waits). A longer view adds coarser jobs behind the finest ones, as a load does.
- Tests touch no machine state: the configuration tests use their temporary directories, and the command test changes a struct only.
- File writes, save layout, capped lists and obsolete audit cases do not apply.

### Questions to the main agent

1. The socket's change persists, as a change to the Settings row does. A 0342 harness running on the play configuration would leave the user's view at whatever value it set last. I chose persistence (one value, no session override), so 0342 should run under its own `XDG_CONFIG_HOME` or set the value back. If you prefer a session-only override for the socket, say so.
2. At a short view the globe shows for most of the fall. Is that acceptable, as specified, or should the descent draw at the data's distance whatever the setting?

### Decisions (main agent, 2026-11-11)

1. The socket's `view_distance` persists as the Settings row does. 0342's runs use a configuration directory of their own, as every headless session does.
2. The fall at a short view is accepted as specified (the globe until the pod's ground comes within the view, through the haze). A capture of the descent at 256 m goes to the user with the landing; if it reads poorly, the descent at the data's distance is an item of its own.
3. `src/command.odin` is also changed by 0341, in flight on its own branch: add the command where the specification says and expect the main agent to merge the two at the landing.
4. Every build or test run goes inside `systemd-run --user --scope --quiet -p MemoryMax=8G -p MemorySwapMax=0`.

### Deviations (implementation, 2026-11-11)

- `doc/code_map.md`: the content to ui record rises from 40 to 41 (`VIEW_DISTANCE_RANGE` is a `Slider_Range`, the accepted kind); `code_graph.py --check` fails without it.
- `doc/presentation.md`: the field session's `prepare_field_frame` bullet also names the haze's end, since that bullet lists what the procedure does.
