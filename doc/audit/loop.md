# Audit: the loop cluster

The loop cluster (work item 0143) is the process: `main.odin` starts it, `run_game` owns the window and `Frame_State`, and every frame reads input, runs the ticks, draws, runs the UI and serves the requests the screens left. Its debt is not its own logic but what it holds for others:

- `Frame_State` has 69 fields; 12 belong to the loop, the other 57 are input, presentation, developer tools and hot reload state parked here because the loop is the one place that lives for the whole run.
- 172 of the 252 references into the cluster are to the simulation's own types and procedures (`Simulation_Content`, `Simulation_State`, `simulation_tick`) that happen to be defined in `loop.odin` and `simulation_world.odin`. Moving them out is a pure move and the first refactor.
- `loop.odin` is the most changed file of the game (86 commits): each new screen with file work, each new renderer and each developer tool added a field, a line in `run_game` and often a serve procedure.
- The frame writes simulation state outside the tick in three places (chunk arrivals, the UI's inventory transfers, the command socket), which is where a plugin boundary or a replay would have to put a queue.

## 1. What the cluster is

Rule: the loop decides when things run; the clusters decide what runs.

- Responsibilities: argument parsing and start-up (`main`), the start data with its overlay fallback (`load_start_data`), the window's lifetime and the frame order (`run_game`), the fixed tick accumulator (`advance_simulation_clock`), the session lifecycle (`start_session`, `end_session`, `save_session`), the requests served between frames, and the tick order (`simulation_tick`).
- Entry procedures: `main` (desktop), `android_wrapped_main` (Android, calls `main`), `run_game` (window and frame loop), `run_command_line_benchmark` (headless, from `main`).
- The frame, in `run_game`'s loop: `update_frame` (input, ticks through `update_session`, streaming, autosave, command socket, haptics), `serve_texture_editor`, `serve_data_browser`, `serve_touch_layouts`, `render_frame` (world, diagnostics, UI, screenshot), `update_audio`, `apply_session_request`, `update_data_watch`, `apply_reload_request`, `update_display`, `write_changed_settings`.

| File | Lines | Commits | Purpose |
|---|---|---|---|
| `loop.odin` | 1565 | 86 | `Simulation_State`, `simulation_tick`, `Frame_State`, the frame, the renderer composition, `make_screen_context`, the command socket's frame side, the serve procedures |
| `main.odin` | 538 | 39 | `Command_Line`, `main`, `load_start_data`, the world start (`choose_world_start`) |
| `main_android.odin` | 51 | 3 | the Android C entry wrapping `main` |
| `session.odin` | 214 | 7 | `Session`, `Session_Plan`, start, end, save |
| `simulation_world.odin` | 43 | 10 | `Simulation_Content` and `tick_world` (block changes, water, leaf decay, light) |

Verdict on the edge assigned files (`tools/code_graph.py` puts them by edge count):

- `hot_reload.odin` (graph: content) belongs to the loop. Every procedure in it takes `^Frame_State`, it is served between frames (`apply_reload_request`, `update_data_watch`), and its 65 content references are the loaders it calls, not state it owns. Add it to the loop's prefixes.
- `tick_profile.odin` (graph: simulation) is right: `Tick_Section` names the simulation's systems and only `simulation_tick`, `tick_entities` and the benchmark use it.
- `diagnostics.odin` (graph: simulation) is split: `Render_Facts`, `World_Facts`, `render_page_lines`, `world_page_lines` and `Frame_Time_Ring` are pure developer tool code; `mapped_lines`, `draw_diagnostics_page`, `draw_world_overlay` and the `*_text` procedures take the whole `Frame_State` and reach through `session` 20 times. It belongs to a developer tools group, fed by facts built in the loop.
- `developer.odin` (graph: content) is simulation: `serve_developer_requests` runs inside `simulation_tick`, and the kits it loads are its data.
- `benchmark_factory.odin` (graph: world) is a second driver of the simulation (it calls `simulation_tick` from `warm_up_benchmark` and `measure_benchmark`), a game side test harness; it stays out of the engine side of any cut.

## 2. State

Rule: `Frame_State` lives for the process, `Session` for a world, `Simulation_State` is the saved part.

- `Simulation_State` (`loop.odin:20`, 12 fields): tick, day cycle, `World`, players, unlocks, quests, events, developer requests, cheat speed, landing pad. Written by `simulation_tick`, `serve_developer_requests`, `tick_venture`, `apply_item_use`, the save codec (`read_simulation_state`), `reload_simulation` and the command socket (`Command_Context` holds a pointer).
- `Session` (`session.odin:12`, 16 fields): the simulation, the generator, streaming, the tick accumulator and input, the save location, and four UI views (`Recipe_Browser`, `Technology_Browser`, `Statistics_View`, `Map_View`) that belong to the ui cluster.
- `Game_Content` (`loop.odin:919`, 17 fields) repeats the ten registries of `Simulation_Content` and adds the presentation only tables; game_simulation_content (the field `simulation_content` since 0152), `session_simulation_content` and `frame_simulation_content` convert between them.

`Frame_State` (`loop.odin:65`) by the cluster that reads and writes each field:

| Group | Fields | Count |
|---|---|---|
| loop | config, content, base_generator, session, frame_seconds, frame_times, frame_tick_count, quit_requested, data_directory, environment, settings, stored_settings | 12 |
| ui and input | biome_banner, title, input_backend, sdl3_input, input, previous_input, touch_overlay, touch_overlay_forced, haptic, vibrator, system_keyboard_available, system_keyboard_shown, world_action_guard, bindings, input_bindings, ui, ui_images, fonts, font_cache, cursor_enabled, touch_layouts, touch_layout_editor | 22 |
| presentation | sprint_kick, render_camera, window_settings, monitor_size, window_scale, platform, renderer, item_atlas, ui_icon_atlas, belt_renderer, model_renderer, particles, particle_memory, particle_renderer, player_model, player_animation, audio, sound_memory | 18 |
| developer tools | diagnostics_page, show_world_overlay, command_server, command_control, command_socket_path, screenshot_directory, screenshot_requested, texture_editor, data_browser | 9 |
| hot reload | content_arena, data_watch, watch_data_flag, binding_overrides, bindings_arena, retired_strings, retired_font_arenas, reload_requested | 8 |

Writers of `Frame_State` outside `loop.odin`:

- `hot_reload.odin`: content, base_generator, content_arena, fonts, retired_font_arenas, bindings, input_bindings, bindings_arena, retired_strings, renderer, item_atlas, ui_icon_atlas, belt_renderer, model_renderer, player_model, audio, touch_overlay, data_watch, reload_requested, ui (toasts, theme).
- `touch_overlay.odin`: touch_overlay (reset in `read_touch_overlay_frame`); it reads session, settings, render_camera, frame_tick_count, bindings.
- `data_export.odin`: data_browser and ui (`export_data_browser_files`, `sync_data_edit_export`).
- The screens through `Screen_Context` pointers: settings, quit_requested, screenshot_requested, reload_requested, title, diagnostics_page, show_world_overlay, texture_editor, data_browser, touch_layouts, touch_layout_editor, biome_banner.
- `diagnostics.odin` takes `Frame_State` by value and only reads.

`Screen_Context` (`ui_screens.odin:19`, 54 fields), in groups: 8 process fields (settings, fonts, bindings, quit and save requests, title), 14 content tables copied from `Game_Content`, 10 simulation fields (player, world, unlocks, quest state, tick, generator, cheat speed, developer requests, landing pad), 4 session held UI views, 9 developer tool fields, 9 HUD and touch derivations computed by the loop (`mining_ring_centre`, `discovery_card_clearance`, `touch_overlay_aims`).

`Ui_State` (`ui_core.odin:385`, 57 fields by count; the 0143 item says 58): the loop writes screens, keyboard, tooltip_open, system_keyboard and mission_control (`enter_session`, `show_title`, `run_ui_frame`), drains toasts' sources (`show_simulation_events`, `show_quest_notices`) and sound_events (`play_ui_sounds`). Game specific groups inside it: mission_control, slot_drag, distribute, quick_move, active_slot. The ui audit takes the rest.

How the other hubs meet in the loop:

- `World` (`world_chunk.odin:31`) is reached through the session 12 times in `loop.odin`: ticked by `simulation_tick`, streamed into by `update_chunk_streaming` (`loop.odin:461`), drawn by `draw_session_world`, and handed as `^World` to every screen.
- `Entities` (`entity.odin:84`) is reached only through `World`; the loop touches it directly in `make_simulation` (`place_capsule`) and `world_facts`.
- `Player` (`player.odin:50`): the loop always takes the first player (`players[0]`, 9 places) for camera, haptics, streaming centre, sound, HUD and the command socket.

## 3. Coupling

Rule: an edge is essential when the loop must make the call every frame or tick; the rest is reach through.

Edges from `python3 tools/code_graph.py`:

| Direction | References | What they are |
|---|---|---|
| loop -> content | 261 | `log_printf` 47 and `text` 24 (infrastructure), `Game_Config`, registries, command responses, the data edits fallback |
| loop -> ui | 212 | `ui_toast` 22, input backends, touch overlay, keyboard, `Screen_Context` building; about 25 are name collisions (below) |
| loop -> presentation | 156 | the world draw (`draw_session_world`), weather, sky, particles, sound frames, `render_size`, `window_scale` |
| loop -> world | 101 | `Generator`, `Landing_Pad_Site`, `World`, save locations, streaming |
| loop -> simulation | 83 | `profile_section` 10, diagnostics facts, player start, statistics set-up |
| content -> loop | 98 | `Frame_State` 24 (`hot_reload.odin`), `Simulation_Content` 23, `Simulation_State` 19, `Game_Content` 7 |
| simulation -> loop | 80 | `Simulation_Content` 66, `Frame_State` 12 (`diagnostics.odin`), `interpolation_alpha`, `simulation_day_ticks` |
| world -> loop | 52 | `Simulation_Content` 26, `Simulation_State` 18 (the save codec, the benchmark), `simulation_tick` |
| ui -> loop | 16 | `Frame_State` 8 (`touch_overlay.odin`), `mining_ring_centre`, `BUILD_STAMP` |
| presentation -> loop | 6 | `Simulation_Content` 5, `texture_edits_path` |

- Essential: `simulation_tick`, `read_input_frame`, `update_chunk_streaming`, `upload_streamed_meshes`, `ui_begin`, `run_screens`, `ui_end`, `update_audio`, `update_display`, the save and session calls.
- Misplaced, not coupling: the 122 `Simulation_Content` and 37 `Simulation_State` references are the simulation, save and content clusters naming their own state, which lives in the loop's files. Moving those definitions removes 172 of the 252 references into the loop.
- Reach through, loop into others: `draw_session_world` (`loop.odin:674`) composes 20 draw calls with their arguments; `render_facts` and `world_facts` fill 39 fields from renderer, streaming and entities for the diagnostics page; `draw_session_weather` samples terrain temperature from the generator; `make_screen_context` copies 14 content tables every frame.
- Reach through, others into the loop: `hot_reload.odin`, `touch_overlay.odin` (8 procedures), `data_export.odin` and `diagnostics.odin` take `^Frame_State` or `Frame_State` where they need two to six fields.
- The frame writes simulation state outside the tick: `insert_generated_chunk` (`world_streaming.odin:312`) registers veins, outcrops and crate sites once per frame after the ticks; the screens call `apply_grid_transfer`, `apply_quick_move`, `take_inserter_hand`, `drop_player_stack` and `queue_research` on the `^World` of `Screen_Context`; the command socket runs requests between ticks.
- Cycles: the loop is in a mutual pair with all five other clusters; every loop file except `main_android.odin` is in the 185 file strongly connected component.
- Graph noise to know: the tool counts field names equal to a top level name. `system_keyboard_available` has three platform definitions, so each of its 5 uses counts 3; the Frame_State field window_settings shares its name with the settings screen's `window_settings` procedure; `main` matches the quest field of that name (6 references from `quest.odin` and `ui_journal.odin`).

## 4. Abstraction gaps

- The requests served between frames are one pattern written 15 ways: a boolean on a sub-struct that a screen sets and a serve procedure takes and clears (`screenshot_requested`, `reload_requested`, the save flag on `Session`, the texture editor's two, the data browser's six, the touch layouts' write and change), plus an enum request on `Title_State` and a path used as a flag in `Command_Control`. The order lives only in `run_game` and in comments ("a close first").
- Three tick drivers call `simulation_tick`: `update_session` (with input, then streaming and autosave), `run_command_tick` (`command.odin:667`, no input, under a wall budget) and the benchmark (with a profile). Only the first advances streaming.
- `Game_Content` and `Simulation_Content` list the same ten registries; three procedures copy one into the other, and `with_schematics_found` is applied in three places (`loop.odin:244`, `loop.odin:795`, `command.odin:238`) because the recipe view depends on the simulation's unlocks.
- `frame_simulation_content` is rebuilt 7 times per frame in `loop.odin` instead of once per frame.
- `Frame_State` is passed whole where a procedure needs a few fields: `serve_data_browser` needs the browser, the data directory, the settings and the UI; the tests allocate a whole `Frame_State` for that (`data_browser_test.odin:49`, `data_export_test.odin:83`, `ui_data_browser_test.odin:175`).
- `run_game` (`loop.odin:1053`, 140 lines) initialises 20 subsystems with 23 `defer` lines whose order carries meaning ("After the session left, which saves with the content").
- The presentation of a frame is written in the loop: `draw_session_world`, `session_sound_frame`, `session_life_frame`, `session_weather`, `draw_session_weather`, `render_facts`, `world_facts` (`loop.odin:490` to `loop.odin:740`, about 250 lines).
- `render_frame` picks the diagnostics page with a switch over `Diagnostics_Page`, one branch per page; a page is a new branch in the loop.
- Session holds UI views, so `session.odin` depends on `ui_recipes.odin`, `ui_technologies.odin`, `ui_statistics.odin` and `ui_map.odin`, and `reset_session_views` in `data_reload.odin` resets them on a content reload.

## 5. Refactors, ranked by gain per risk

1. Move the simulation's state out of the loop. Move `Simulation_State`, `Simulation_Event`, `make_simulation`, `destroy_simulation`, `simulation_tick`, `apply_research_result`, `simulation_quest_context` and `simulation_day_ticks` (`loop.odin:18` to `loop.odin:320`) into `simulation_world.odin` or a new simulation file, and change `tools/code_graph.py` so the simulation prefix maps to the simulation cluster (today it maps to loop). Files: `loop.odin`, `simulation_world.odin`, `tools/code_graph.py`. Guards: `./build.sh check`, every test that calls `simulation_tick` (`save_test.odin`, `tick_profile_test.odin`, `quest_runtime_test.odin`). Gain: 172 of 252 references into the loop leave it, loop.odin loses about 300 lines. Risk: none in behaviour (same package, pure move). Prerequisite for a package split: yes, the simulation must own its state type.
2. Embed `Simulation_Content` in `Game_Content`. Replace the ten repeated fields with one embedded field (Odin `using`), so game_simulation_content (the field `simulation_content` since 0152) becomes a field read and `session_simulation_content` a one field override. Files: `loop.odin`, `session.odin`, `hot_reload.odin`, `data_reload.odin`, `main.odin`, `command.odin`. Guards: `data_reload_test.odin`, `save_test.odin`, `developer_test.odin`. Gain: about 30 lines, one list of registries. Risk: low; the literal constructors in tests change shape. Prerequisite: yes, the content passed to the game side is then one type.
3. Narrow the serve procedures. `serve_data_browser`, `discard_data_edit`, `save_data_edit`, `export_data_browser_files` and `sync_data_edit_export` take the browser, data directory, settings and UI; `save_data_edit` and `discard_data_edit` return the changed path's category instead of calling `apply_data_edit_change`, which the loop then applies. Same for `serve_touch_layouts` and `serve_texture_editor`. Files: `loop.odin`, `data_export.odin`, the three tests above. Guards: `test_a_data_edit_reports_its_category`, `ui_data_browser_test.odin`, `data_export_test.odin`. Gain: the tests stop building a 69 field struct; `data_export.odin` no longer depends on the loop. Risk: low. Prerequisite: no.
4. Feed diagnostics with facts only. Give `draw_diagnostics_page` and `draw_world_overlay` a facts struct the loop builds (the input page and the overlay lines join `Render_Facts` and `World_Facts`), so `diagnostics.odin` never names `Frame_State`; reassign `hot_reload.odin` to the loop in `tools/code_graph.py`. Files: `diagnostics.odin`, `loop.odin`, `tools/code_graph.py`, `diagnostics_test.odin`. Gain: 12 `Frame_State` references and 20 session reach throughs leave `diagnostics.odin`. Risk: low; the pages are verified by playing. Prerequisite: no.
5. Group `Frame_State` into sub-structs along the table in section 2: an input group (13 fields), a presentation group (18), a developer tools group (9), a hot reload group (8). Files: `loop.odin`, `hot_reload.odin`, `touch_overlay.odin`, `data_export.odin`, `diagnostics.odin`, `developer_test.odin`, the data browser tests. Guards: `./build.sh check`, `./build.sh test`. Gain: 69 top level fields to about 16; each serve and reload procedure can take its group. Risk: low per change, large diff; do it after 3 and 4 so fewer procedures take the whole state. Prerequisite: yes, the presentation group is the engine's renderer state.
6. Move the frame's presentation out of `loop.odin`. `draw_session_world`, `session_sound_frame`, `session_life_frame`, `session_weather`, `draw_session_weather`, `Frame_Render_Counts`, `render_facts` and `world_facts` go to a presentation file taking the presentation group of 5 and the session. Files: `loop.odin`, a new render file. Guards: `./build.sh check`; rendering has no tests, so a playtest. Gain: about 250 lines and most of the 156 loop -> presentation references leave the loop. Risk: medium (camera, fog and sprint kick state order inside the draw; untested). Prerequisite: yes.
7. One request table. A bit set of frame requests (proposed, no such type yet) that the screens set through one pointer, and one serve procedure that runs them in a documented order between frames: data browser close, discard, save, export, refresh, open, texture editor, touch layouts, then after the draw screenshot, session request, reload. Files: `loop.odin`, `ui_screens.odin`, `ui_developer.odin`, `ui_data_browser.odin`, `ui_texture_editor.odin`, `ui_touch_layout_editor.odin`, `data_browser.odin`. Guards: `ui_data_browser_test.odin` (draw list after the serve), `ui_touch_layout_editor_test.odin`. Gain: 4 request pointers leave `Screen_Context`, the hand-back rule on freeing memory between frames becomes one place. Risk: medium; the order within the data browser matters (close before discard). Prerequisite: no, but it is the engine's request pattern.
8. Take the UI views out of `Session`: `recipe_browser`, `technology_browser`, `statistics_view` and `map_view` move to a per session UI struct the loop owns beside the session and resets with it. Files: `session.odin`, `loop.odin`, `data_reload.odin`. Guards: `data_reload_test.odin`, `ui_recipe_browser_test.odin`, `ui_technology_browser_test.odin`. Gain: 7 session -> ui references; `Session` becomes engine plus simulation only. Risk: low. Prerequisite: yes, for an engine side session.
9. Split `run_game` into a start procedure that builds `Frame_State`, a destroy procedure that tears it down in the current reverse order, and a frame procedure holding the order of section 1. Files: `loop.odin`. Guards: none automatic (needs a window); a playtest and a quit to title then exit. Gain: the frame order readable in one 15 line procedure; no line change. Risk: medium, the defer order encodes the save on exit before the content arena goes. Prerequisite: no.

## 6. Engine or game

Rule: the engine decides when a tick, a frame or a request runs; the game decides what a tick does.

- Engine: `main` (arguments, configuration, logging, the data directory), `main_android.odin`, `run_game`'s window and frame order, `Tick_Accumulator` and `interpolation_alpha`, input reading, the serve procedures, `hot_reload.odin`'s presentation reloads and watcher, the command socket's transport (`serve_command_socket`, `update_command_server_open`), screenshots, `tick_profile.odin`, `Session`'s lifecycle (streaming start and stop, the save swap), `tick_world` (light, water, leaf decay).
- Game: the order inside `simulation_tick`, `make_simulation` (capsule, starting items, first quest), `developer.odin`, `show_simulation_events` and `show_quest_notices` (which event becomes which toast), `choose_world_start` with the landing pad, `--chapter` and `--give`, `benchmark_factory.odin`.
- Both today: `Game_Content` (content tables beside presentation tables), `frame_simulation_content` (game content plus the engine's generator pointer), `reload_content` (engine mechanism, game remap), `apply_debug_actions` (engine keys, game edits), `make_screen_context` (engine frame data and game state in one struct).

What would cross a plugin boundary per tick, if the game sat behind one:

- One call per tick, `simulation_tick` with the players' `Input_Frame` array; up to 15 per frame (`MAXIMUM_FRAME_SECONDS` times the tick rate), more under a tick command.
- Into the game between ticks, today written straight into `World`: chunk arrivals with their veins, outcrops and crate sites (`insert_generated_chunk`); the UI's inventory transfers, research queueing and launch requests; developer requests; command socket edits. Each would become a queued call the game applies at the next tick, which also fixes the tick at which it lands.
- Out of the game per tick: `Simulation_Event` entries and quest notices (both drained each frame), the tick count, the day cycle.
- Out of the game per frame, the large part: the renderer, particles and sounds read `World` and its entity pools directly (`draw_entities`, `draw_belts`, `update_particles`, `session_sound_frame`), and every screen reads `World` through `Screen_Context`. Behind a boundary this becomes a per frame draw description (kind, cell, rotation, animation state) and a query surface for the panels, which is what 0146 asks the audits to size.
- Engine calls from the game side: `world_set_block` and the block reads of the machines, light and water scheduling through `tick_world`, which today runs last in the tick on the same `World`.
- Determinism binds at the tick call: `simulation_tick` reads no clock (the profile only when given). What breaks replay today is the frame side writers above, which land between ticks at a point set by frame timing and worker threads.
- Save state binds at `save_world` and `read_simulation_state`: the type driven codec encodes the whole `Simulation_State`. `reload_simulation` already encodes, loads new content and decodes, which is the route a plugin reload with a live world would take.

## 7. Entity component lens

- The systems exist already and are named: `Tick_Section` has 20 entries, and `simulation_tick` plus `tick_entities` run them in a fixed order with a profile call between each. The order is semantic and documented in comments (players before entities so a dropped stack is seen at once; power before the machines; fluids after the inserters).
- As systems: developer requests, players (use item, move, magnetometer), unlocks, belts, loose items, belt statistics, power, drills, inserters, furnaces, assemblers, labs, core sample drills, launch pads, fluids, lamps, outcrops and crates, launch requests, venture, research, statistics, quests, world.
- Singletons, not components: statistics, research, shipments and the venture sit on `World`; unlocks and quests on `Simulation_State`. An ECS would keep them as resources.
- Components the loop cluster itself holds: none per entity. The presentation memories in `Frame_State` (particle_memory, sound_memory, player_animation) are keyed by the one player or by nothing.
- What an ECS would buy here: the tick order as a table of (section, procedure) instead of a hand written sequence with 27 profile calls, so a new machine kind is a row. The same gain is available without an ECS by turning the sequence into an array of procedures over `Simulation_State` and content, since `Tick_Section` already names them.
- What it would cost here: nothing is gained on coupling for the loop, whose reach is into `Frame_State` and the frame, not into entity pools; the order would still be a fixed list, since determinism depends on it.

## 8. Tests

Rule: the loop's pure parts are tested, its frame is not.

- Covered: argument parsing and conflicts (`main_test.odin`, `developer_test.odin`), the paused clock (`settings_test.odin` through `advance_simulation_clock`), the profile (`tick_profile_test.odin`), the start data fallback with a broken overlay (`test_a_broken_data_edit_turns_the_overlay_off_at_start`), the data browser serve followed by a frame's draw list (`ui_data_browser_test.odin`), data edit save and discard (`data_browser_test.odin`, `data_export_test.odin`), reload of the simulation (`data_reload_test.odin` through `reload_session`), the saved world start (`ui_world_setup_test.odin`), `units_to_window_rectangle` (`input_raylib_test.odin`), command ticks (`command_test.odin` through `run_command_tick`), and `simulation_tick` in eight test files.
- Uncovered: the catch up clamp (`MAXIMUM_FRAME_SECONDS`) and `interpolation_alpha`; `autosave_due` and `save_when_due`; `apply_session_request`, `enter_session`, `leave_session`; `start_session`, `end_session`, `save_session` as a unit; `show_simulation_events` and `show_quest_notices`; `serve_touch_layouts` and `serve_texture_editor`; `reload_content` and `replace_frame_content` (only `reload_session` is tested); `execute_queued_command` and `answer_command_ticks`; the frame order in `run_game`; the theme and chunk shader fallbacks after the window opens.
- Pinning implementation: `audit_screen_context` (`ui_audit_test.odin:255`) is a second copy of `make_screen_context` and `audit_frame` of `run_ui_frame`, so a field added to one drifts from the other unseen. `test_world_overlay_starts_off_and_toggles` builds a `Frame_State` to read a zero field. The data browser tests pin that the serve procedures take `Frame_State`.
- Testable after refactors 3, 7 and 9: the serve order and `update_session` without a window, since neither needs raylib once they take their groups.

## Claims to spot check

1. `Simulation_Content` (`simulation_world.odin:13`) and `Simulation_State` (`loop.odin:20`) account for 159 of the 252 references into the loop cluster; with `simulation_tick`, `make_simulation`, `destroy_simulation`, game_simulation_content (the field `simulation_content` since 0152) and `simulation_day_ticks` it is 172 (probe over `python3 tools/code_graph.py`'s parser).
2. Chunk arrivals write simulation state outside the tick: `update_session` calls `update_chunk_streaming` after the tick loop (`loop.odin:461`), and `insert_generated_chunk` (`world_streaming.odin:312`) registers veins, outcrops and crate sites into `World`.
3. The screens mutate the simulation during the UI pass through the `^World` in `Screen_Context` (`ui_screens.odin:42`), for example `apply_grid_transfer` (`quick_transfer.odin:507`) and `take_inserter_hand` (`quick_transfer.odin:143`).
4. `hot_reload.odin` belongs to the loop: all its procedures take `^Frame_State` (22 mentions), none of its state is content's own.
5. `audit_screen_context` (`ui_audit_test.odin:255`) duplicates `make_screen_context` (`loop.odin:744`) field by field.
