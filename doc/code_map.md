# Code map

The entry page for the source: 199 files under `src/` plus 139 test files beside them. 181 are the `game` package, grouped into seven clusters; 18 are seven leaf packages under `src/` (section Packages), each a cluster named after its directory. Read the cluster table, pick a cluster, open its entry file; the section of each cluster lists its files in reading order. How the parts work is in [architecture.md](architecture.md), the why of the clusters in the audits under [audit/](audit/).

- Rule: a new file goes into a cluster and takes one of its file name prefixes (or a line in the file table of `tools/code_graph.py`); a reference against the allowed dependency table below is a finding until it is refactored away.
- The map is kept true by two checks: `python3 tools/check_docs.py` checks every backticked file and name in it, and `python3 tools/code_graph.py --check doc/code_map.md` compares every cluster edge the allowed table does not allow with the map's record of it ([build.md](build.md), Source checks).
- The record is the "Reaches into" line of each cluster section: `target count (notes)` parts separated by commas, or `nothing`. The check fails when an edge is missing from the record or above its recorded count, so a new reach through is caught; when a refactor lowers a count, lower the record by hand in the same commit.
- The clusters of the map and of `tools/code_graph.py` are the same: the script assigns each file of the game package by its prefix, a few files by name, and prints any file it had to place by its edges. A package's files are its cluster; the script names them with the directory (`platform/logging.odin`) and resolves a name after an import's name and a dot (`platform.log_printf`) in that package, so a package's edges are only the ones the compiler allows: into the packages it imports, never into the game package.

## Clusters

| Cluster | Purpose | Entry | Files | Lines | Audit |
|---|---|---|---|---|---|
| loop | the process: start-up, the frame, when the tick runs, sessions, the requests served between frames | `loop.odin` | 5 | 2629 | [loop](audit/loop.md) |
| ui | the input layer, the immediate mode toolkit, every screen, the HUD and the touch overlay | `ui_core.odin` | 48 | 16975 | [ui](audit/ui.md) |
| world | blocks and what follows a block: chunks, light, water, meshing, streaming, generation, the save codec | `world_chunk.odin` | 34 | 9613 | [world](audit/world.md) |
| simulation | the factory per tick: entity pools, networks, players, inventories, crafting, statistics, the game's records | `entity.odin` | 40 | 15407 | [simulation](audit/simulation.md) |
| presentation | pixels and sound from the world and the tick: shaders, atlases, models, sky, weather, particles, audio, the window | `render_chunks.odin` | 31 | 8381 | [presentation](audit/presentation.md) |
| content | data files into typed tables, the string table, configuration and settings | `data_reload.odin` | 15 | 5024 | [content](audit/content.md) |
| tools | the command socket, the diagnostics pages, the Data files browser and export, the factory benchmark | `command.odin` | 8 | 3859 | [loop](audit/loop.md), [content](audit/content.md) |
| platform | the package `src/platform/`: logging, paths, the time zone, JNI, the export's file access, the replacing file write | `logging.odin` | 13 | 1014 | [content](audit/content.md) |
| generation_seed | the package `src/generation_seed/`: purpose seeds and the integer hashes | `generation_seed.odin` | 1 | 74 | [world](audit/world.md) |
| model_vox | the package `src/model_vox/`: the MagicaVoxel parser | `model_vox.odin` | 1 | 283 | [presentation](audit/presentation.md) |
| render_frustum | the package `src/render_frustum/`: frustum planes and the box test | `render_frustum.odin` | 1 | 35 | [presentation](audit/presentation.md) |
| run_length | the package `src/run_length/`: the chunk run length codec | `run_length.odin` | 1 | 39 | [world](audit/world.md) |
| sjson_text | the package `src/sjson_text/`: the SJSON writer and `sorted_object_keys` | `sjson_text.odin` | 1 | 212 | [content](audit/content.md) |
| android_libc | the package `src/android_libc/`: the glibc functions bionic lacks, for the Android link | `android_libc.odin` | 1 | 63 | [content](audit/content.md) |

## Allowed dependencies

Rule: a cluster references only the clusters of its row. The pilot split (0145) and any later package split follow it. The edges that run against it are recorded in the "Reaches into" line of each cluster below.

| Cluster | May reference |
|---|---|
| loop | ui, world, simulation, presentation, content, tools, platform, generation_seed, model_vox, render_frustum, run_length and sjson_text |
| ui | presentation, simulation, world, content, platform, generation_seed, model_vox, render_frustum, run_length and sjson_text |
| world | content, platform, generation_seed, model_vox, render_frustum, run_length and sjson_text |
| simulation | world, content, platform, generation_seed, model_vox, render_frustum, run_length and sjson_text |
| presentation | simulation, world, content, platform, generation_seed, model_vox, render_frustum, run_length and sjson_text |
| content | platform, generation_seed, model_vox, render_frustum, run_length and sjson_text |
| tools | ui, world, simulation, presentation, content, platform, generation_seed, model_vox, render_frustum, run_length and sjson_text |
| platform | android_libc |
| generation_seed | nothing |
| model_vox | platform |
| render_frustum | nothing |
| run_length | nothing |
| sjson_text | nothing |
| android_libc | nothing |

- The packages sit where the platform cluster sat: every game cluster may reference them, and they reference only the packages of their row (`platform` imports `android_libc` for the link alone, `model_vox` names `platform.join_path`).
- The order is engine below game only in part: world storage and the platform are engine, the simulation is game, presentation and ui mix both ([audit/](audit/), section 6 of each report).
- In the records, "accepted" means essential today and named in an audit; "queued" names the entry of the 0143 refactor queue that removes the references (1 pure moves, 3 the hubs, 5 the seams). Graph noise (a field or parameter named like a top level procedure, such as `block_name`) counts as a reference; the rename that ends it is queued where one is.

## loop

The process: the loop decides when things run, the clusters decide what runs.

- Entry: `loop.odin`, `run_game` (the window and the frame order), from `main`.
- Files in reading order:
  - `main.odin`: `Command_Line`, `main`, `load_start_data` with the overlay fallback, the world start.
  - `loop.odin`: `Frame_State`, `run_game` and `update_frame`, `make_screen_context`, the serve procedures, `Game_Content`.
  - `session.odin`: `Session`, `start_session`, `end_session`, `save_session`.
  - `hot_reload.odin`: the reload per data category on `Frame_State`, served between frames.
  - `main_android.odin`: the Android C entry wrapping `main`.
- State: `Frame_State` (69 fields, 57 of them other clusters' parked here), `Session`, `Game_Content`.
- Tests: `main_test.odin`; the frame, the session lifecycle and the reloads are untested (loop audit, section 8).
- Reaches into: nothing.

## ui

The toolkit turns an input frame into a draw list; the screens decide what the widgets mean.

- Entry: `ui_core.odin`, `ui_begin` and `ui_end`; the screens start at `run_screens` in `ui_screens.odin`.
- Files in reading order:
  - `ui_core.odin`: `Ui_State`, `Ui_Input`, `Draw_Command`, the screen stack, ids, focus, pointer, slot drag, toasts, layout cuts (`column_rectangle`).
  - `ui_widgets.odin`: every widget, the theme colour variables, glyph bar, tooltips, radial, `cut_row`, `Scroll_List`, `wrap_text` and `detail_line`.
  - `ui_draw.odin`: the draw list to raylib, icon atlases, image cache.
  - `ui_font.odin`, `ui_theme.odin`, `ui_format.odin`: fonts and `Font_Cache`; the theme loader and icon names; one formatter per unit and `format_game_time`.
  - `input_actions.odin`: `Action`, `Raw_Input`, `Input_Frame`, `Tick_Input_Accumulator`, gyro calibration.
  - `input_raylib.odin`, `input_sdl3.odin`, `input_sdl3_android.odin`: the raylib backend with keyboard and mouse; the SDL3 backend; its Android stubs.
  - `bindings.odin`, `ui_input.odin`: the bindings file and `Input_Bindings`; `make_ui_input`, device detection.
  - `text_input.odin`, `ui_keyboard.odin`: `Text_Field` and `Keyboard_State`; the text field widget and the game's keyboard.
  - `ui_screens.odin`: `Screen_Context`, `handle_screen_keys`, `run_screens`, the pause menu, settings.
  - `ui_title.odin`, `ui_world_setup.odin`: `Title_State`, load and delete; the new world values.
  - `ui_inventory.odin`, `quick_transfer.odin`: the inventory screen and `finish_slot_drag`; quick move and transfer buttons (half ui state, half simulation verbs).
  - `ui_machine.odin`: the machine panel frame, furnace, inserter, drill and splitter sections.
  - `ui_crafting_machines.odin`, `ui_fluid.odin`, `ui_power.odin`, `ui_launch_pad.odin`, `ui_prospecting.odin`, `ui_contracts.odin`: the panel sections for assemblers and labs, fluids, power, launch pads, prospecting, the venture.
  - `ui_recipes.odin`, `ui_recipe_browser.odin`: the recipe screen; its pure filtering and detail.
  - `ui_technologies.odin`, `ui_technology_browser.odin`: the technology screen; its pure filtering.
  - `ui_statistics.odin`, `ui_map.odin`, `ui_journal.odin`, `ui_mission_control.odin`: statistics; `Map_View`; the journal; Mission Control and the discovery card.
  - `ui_developer.odin`, `ui_data_browser.odin`, `ui_texture_editor.odin`, `ui_touch_layout_editor.odin`: the Developer, Data files, Textures and touch layout screens.
  - `hud.odin`, `biome_banner.odin`: crosshair, `target_status_lines`, hotbar, craft queue, glyph hints; the biome banner.
  - `touch_overlay.odin`: the virtual gamepad, its layout files, gestures, drawing ([touch_overlay.md](touch_overlay.md)).
  - `haptics.odin`, `haptics_android.odin`, `haptics_desktop.odin`: `Haptic_Request` and the rumble constants for every target; the phone's vibrator, through the JNI helpers of the platform package; the desktop stub.
  - `system_keyboard.odin`, `system_keyboard_linux.odin`, `system_keyboard_android.odin`, `system_keyboard_windows.odin`: `System_Keyboard_Field`, a text field's window rectangle; show and hide the platform keyboard for it.
- State: `Ui_State` (57 fields), `Screen_Context` (54), `Input_Frame`, `Touch_Overlay_State`, `Title_State`; the four session views (`Map_View` and the browsers) sit on `Session`.
- Tests: every `*_test.odin` beside its file; `ui_audit_test.odin` draws every screen at every audit size, `ui_pointer_test.odin` the pointer and taps, `accessibility_test.odin`.
- Reaches into: tools 43 (accepted: the Data files screen on `Data_Browser` 31, the diagnostics page names 3, a `block_name` field as noise 9), loop 14 (queued 3: `Frame_State` in `touch_overlay.odin` 8; accepted 6: `mining_ring_centre`, `BUILD_STAMP`, `parse_seed`, noise).

## world

The world owns blocks and what is derived from blocks; generation is a pure function of seed and coordinate; the save codec turns state into files and back.

- Entry: `world_chunk.odin`, `World` with `world_get_block` and `world_set_block`.
- Files in reading order:
  - `world_chunk.odin`: `Chunk`, `World`, `World_Settings` and `world_settings_from_file`, coordinates, `camera_world_coordinate`, `coordinate_before`, `Direction` and `rotate_direction`, get and set, dirty marking.
  - `world_tick.odin`: `tick_world` and `apply_block_changes`, the world's part of `simulation_tick` (block changes, water, leaf decay, light).
  - `world_block.odin`, `block_shape.odin`: `Block_Registry`, shapes and variants; `Box`, collision boxes and quads of slabs, stairs, posts.
  - `world_light.odin`, `world_light_sky.odin`: light nibbles, removal and addition queues; sky light of a chunk.
  - `world_water.odin`: `Water_Flow`, scheduling, flow rules.
  - `world_mesh.odin`, `world_mesh_light.odin`, `world_mesh_border.odin`: the greedy mesher, vertex light, the border copy.
  - `world_raycast.odin`, `world_serialize.odin`: the voxel walk; `Byte_Reader`, chunk palette and runs.
  - `world_streaming.odin`: `Chunk_Streaming`, workers, insert, unload, mesh revisions.
  - `world_vein.odin`, `world_explored.odin`: the vein registry and outcrops; explored columns for the map.
  - `world_debug_edit.odin`, `world_debug_terrain.odin`: the F-key dig; the flat debug terrain.
  - `generation.odin`: `Generator`, `DEFAULT_WORLD_SEED`; the purpose seeds and the hashes are the `generation_seed` package (Packages).
  - `generation_chunk.odin`, `generation_terrain.odin`, `generation_caves.odin`: the per chunk steps; height, climate, the column grid and the cave carving; the crate site search in cave pockets.
  - `generation_biome.odin`, `generation_trees.odin`, `generation_features.odin`: biomes and species, trees, boulders and ground cover.
  - `generation_veins.odin`, `generation_vein_tables.odin`, `generation_starter_veins.odin`: vein placement and outcrops, the vein file, starter veins.
  - `generation_spawn.odin`, `landing_pad.odin`: the spawn search; the landing pad stamp.
  - `save_binary.odin`: the type driven codec (schemas, enums by name, lists).
  - `save_state.odin`, `save_remap.odin`: the entities.bin body and `simulation_state_hash`; content tables and the id remap.
  - `save_world.odin`, `save_list.odin`: world.sjson, region files, staging and swap; the save list.
- State: `World` (27 fields; 13 are the simulation's records parked here), `Chunk`, `Chunk_Streaming` (on `Session`), `Generator`, `Block_Registry`, `World_Settings`.
- Tests: every `*_test.odin` beside its file; `save_test.odin` and `save_codec_test.odin` (save, load and run to the same hash).
- Reaches into: simulation 220 (accepted 197: the save codec encoding pools, records, `Simulation_State` and `Simulation_Content`, and `save_world.odin` calling `make_simulation` and `simulation_day_ticks` 193, `vein_is_exhausted` 1, `tick_world` running the leaf decay of `tree_felling.odin` 3; queued 3: the game's records on `World` 15; queued 5: raycast and water reading entities, the crate sites at chunk arrival 8), presentation 12 (accepted: the mesher's atlas and tile variation).

## simulation

The factory: what changes per tick; blocks belong to the world, prototypes to content.

- Entry: `entity.odin`, `tick_entities` (called by `simulation_tick` in `simulation_world.odin`).
- Files in reading order:
  - `simulation_state.odin`: `Simulation_State`, `Simulation_Event`, `make_simulation` with `place_capsule`, `destroy_simulation`, `simulation_day_ticks`.
  - `simulation_world.odin`: `Simulation_Content`, `simulation_tick`, `apply_research_result`, `simulation_quest_context`.
  - `entity.odin`: `Entity_Kind`, `Entity_Handle`, `Entity_Common`, `Entity_Pool`, `Entities`, add and remove, `tick_entities`.
  - `entity_placement.odin`: placement rules, `commit_placement`, rotation, pick up.
  - `machine.odin`: `Machine_Kind`, `Machine`, `Machine_Registry` and per kind validation.
  - `item_transfer.odin`: `entity_accepts`, `entity_insert`, `entity_extract`.
  - `belt.odin`, `belt_movement.odin`, `belt_placement.odin`: transport lines and their rebuild, lane movement, drag placement.
  - `splitter.odin`, `inserter.odin`, `loose_item.odin`: round robin and filters; the swing cycle; stacks lying in cells.
  - `drill.odin`, `furnace.odin`: vein draws, boring, revival; the furnace and the shared burner step.
  - `assembler.odin`, `recycler.odin`: crafting machines; recycle recipes and returns.
  - `lab.odin`, `launch_pad.odin`: `Research_State`, units and queueing; assembly stages, launch, shipments.
  - `schematic.odin`, `prospecting.odin`: the schematic crate kind; core sample drills, the magnetometer and seismic records.
  - `fluid.odin`, `fluid_machine.odin`, `machine_fluid_ports.odin`, `fluid_network.odin`: the fluid registry; pipes and fluid machines; port layouts; segments and flow.
  - `power_machine.odin`, `power_network.odin`: generators, poles, lamps; nodes, memberships, balance.
  - `player.odin`, `player_interaction.odin`, `player_collision.odin`: `Player` and movement; mining and placing; swept collision.
  - `inventory.odin`, `inventory_interaction.odin`, `crafting.odin`: `Item_Stack`, `Inventory`; slot clicks; `Craft_Queue` and hand crafting.
  - `statistics.odin`, `production_statistics.odin`: `Statistics` and rate rings; statistics rows and the marker colours.
  - `recipe_unlocks.odin`, `quest_runtime.odin`: `Recipe_Unlocks` per tick; `Quest_State`, objectives, rewards, messages.
  - `venture.odin`, `tree_felling.odin`: `Contract_State`, shipments served, the orbital survey; felling and leaf decay.
  - `developer.odin`: developer kits and `serve_developer_requests`, run inside the tick.
  - `tick_profile.odin`: `Tick_Profile`, wall time per tick section.
- State: `Simulation_State`, `Simulation_Content`, `Entities` (16 pools, the belt, fluid and electric networks, the cell map, loose items), `Player`, `Inventory`, `Statistics`, `Research_State`, `Quest_State`, `Recipe_Unlocks`, `Contract_State`, `Tick_Profile`.
- Tests: every `*_test.odin` beside its file; `simulation_tick` through the simulation and save tests; the systems in `byproduct_test.odin`, `chemistry_test.odin`, `combustion_test.odin`, `deep_mining_test.odin`, `hydro_grid_test.odin`, `oil_test.odin`, `ore_processing_test.odin`, `power_test.odin`; the whole chain in `benchmark_test.odin` (tools).
- Reaches into: loop 1 (accepted: `parse_seed`), ui 29 (accepted: the tick's input types `Input_Frame`, `Action_Set`, `Action`), presentation 18 (accepted: machine models and motion 6, `Fly_Camera` 6, `block_centre` and `line_block_belt` 5, `DAY_START_FRACTION` 1).

## presentation

Presentation turns the world, the tick and the render time into pixels and sound; nothing reads it back.

- Entry: `render_chunks.odin`, `Chunk_Renderer`; the frame's draw order is `draw_session_world` in `loop.odin`.
- Files in reading order:
  - `render_chunks.odin`: shader loading with retry and the GLES rewrite, mesh upload, uniforms, `draw_chunks`.
  - `render_atlas.odin`, `texture_generate.odin`, `texture_variation.odin`: `Atlas_Layout`, `load_rgba_texture` (the hashes are the `generation_seed` package); procedural ore tiles and texture edits; the Odin mirror of the shader's tile variation.
  - `render_water.odin`: `Water_Renderer`, underwater fog; the frustum test is the `render_frustum` package (Packages).
  - `render_day.odin`, `render_sky.odin`: `Day_Sky`, sun and moon; the sky dome, stars, the survey satellite.
  - `weather.odin`, `render_weather.odin`: `weather_at`, the hourly schedule; `Weather_Look`, rain, snow, clouds.
  - `render_entities.odin`, `render_models.odin`: `draw_entities` over the pools, bottleneck markers; `Model_Renderer`, posed and ghost models.
  - `model_mesh.odin`, `model_motion.odin`: the voxel mesher over the `model_vox` package's parser (Packages); `Machine_Motion` and part transforms.
  - `render_belts.odin`, `render_fluids.odin`, `render_power.odin`, `render_loose_items.odin`: belts and lane items; pipes and ports; poles and wires; loose stacks.
  - `render_icons.odin`: `Item_Atlas` for items and UI icons, item billboards.
  - `render_player.odin`, `render_player_model.odin`, `player_animation.odin`, `render_fly_camera.odin`: pose, camera, ghosts, hands; limb models; walk cadence and limb angles; `Fly_Camera`.
  - `particles.odin`, `render_particles.odin`: `Particle_System`; emitters, `Particle_Memory`, capsule descent.
  - `ambient_life.odin`, `render_life.odin`, `render_flames.odin`: flocks, insects, fish; their draws; torch flames.
  - `audio.odin`, `sound_events.odin`: `Audio_Mixer`, sound table, loop fades; `Sound_Memory`, cues, hum, ambience clusters.
  - `display.odin`, `raylib_log.odin`: window modes, resolutions, scale, GL info; raylib's log into the game log.
- State: the GPU resources (`Chunk_Renderer`, `Item_Atlas`, `Belt_Renderer`, `Model_Renderer`) and `Audio_Mixer` for the run, the memories (`Particle_System`, `Particle_Memory`, `Player_Animation_Memory`, `Sound_Memory`) for a session; nothing is saved.
- Tests: every `*_test.odin` beside its file; `shader_source_test.odin` (the `u` suffix rule), `render_ghost_test.odin`, `texture_periodicity_test.odin`; the draw procedures are untested.
- Reaches into: ui 17 (accepted: theme colours and marker palettes 13, `Input_Frame` for the fly camera 2, `Ui_Sound_Event` 2), loop 1 (accepted: `texture_edits_path`), tools 2 (accepted: a `block_name` parameter, noise).

## content

Content turns files under `data/` and the configuration into typed tables once, and gives every cluster the string table.

- Entry: `data_reload.odin`, `load_game_data`; strings through `text` in `data_strings.odin`.
- Files in reading order:
  - `data_load.odin`: `Game_Config`, the data directory, the data edits overlay, `read_data_file`, `find_definition_index`.
  - `data_reload.odin`: `Game_Data`, the load order (`load_content_registries`), `reload_simulation`, `Log_Capture`.
  - `data_strings.odin`: `String_Table`, `text`.
  - `data_watch.odin`: `Data_Watch`, file categories, the settle.
  - `item.odin`, `recipe.odin`, `technology.odin`: `Item_Registry`; `Recipe_Registry` and graph queries; `Technology_Registry`.
  - `quest.odin`, `contract.odin`, `notes.odin`, `discovery.odin`: `Quest_Registry` and chapter files; `Contract_Registry`; `Note_Registry`; discoverable ores and `log_discoveries`.
  - `configuration.odin`, `configuration_output.odin`: `Loaded_Configuration`, layers, provenance, strict assignment; the dump and the settings file.
  - `settings.odin`, `deck_preset.odin`: `Settings` and ranges; the Steam Deck preset.
- State: the registries, one arena per load (`content_arena` on `Frame_State`), the global `String_Table`, `Settings`, `Game_Config`, `Data_Watch`.
- Tests: every `*_test.odin` beside its file; the shipped chapters in `quest_chapter_02_test.odin` to `quest_chapter_08_test.odin`; most simulation tests build content through `make_test_content` (`machine_test.odin`).
- Reaches into: world 93 (accepted: item, quest and discovery definitions naming blocks 48, the content reload remapping the world 41, data file names 4), simulation 96 (accepted 87: the registries' cross links and value types such as `Item_Stack`, `Furnace`, `Quest_State`; queued 1: `reload_simulation` rebuilding `Simulation_State` through `make_simulation` and `destroy_simulation` with `Simulation_Content` 9, the reload route of a content file that belongs to the loop), ui 42 (accepted 40: settings typed by `Slider_Range`, `Binding` and the overlay enums, UI data file names and colours; queued 3: the session's UI views made by `data_reload.odin` 2), loop 19 (accepted: `Game_Content` and `Session` in the reload, `data_edits_directory`, `BUILD_INFO`, noise), presentation 16 (accepted: data file names, display limits), tools 12 (accepted: a `block_name` parameter, noise).

## tools

The developer's and the assistant's instruments: they drive, inspect or measure a running game (developer mode, the command socket, the benchmark).

- Entry: `command.odin`, `execute_command_line`.
- Files in reading order:
  - `command.odin`: the command protocol, usage rows, blueprints, queries ([commands.md](commands.md)).
  - `command_socket.odin`, `command_socket_posix.odin`, `command_socket_windows.odin`: paths and `Queued_Command_Line`; the Unix socket and `Command_Server`; the Windows stub.
  - `diagnostics.odin`: `Render_Facts`, `World_Facts`, `Frame_Time_Ring`, the diagnostics pages and world overlay.
  - `data_browser.odin`, `data_export.odin`: `Data_Browser`, the Data files screen's trees and edits; the export.
  - `benchmark_factory.odin`: the factory benchmark, a second driver of `simulation_tick`.
- State: `Command_Context`, `Command_Server`, `Data_Browser`, `Frame_Time_Ring`; they live on `Frame_State` or the stack of a run.
- Tests: every `*_test.odin` beside its file; `benchmark_test.odin` runs sizes 1 and 4 and requires no idle machine.
- Reaches into: loop 19 (queued 3: `Frame_State` in `diagnostics.odin` and `data_export.odin` 14; accepted 5: `session_generator`, `game_simulation_content`, `interpolation_alpha`, `parse_seed`, `BUILD_STAMP`).

## platform

The package `src/platform/`, one of the leaf packages below; the leaves over the operating system. The platform shims that take a game type stay in the game package: haptics and the system keyboard in ui, `raylib_log.odin` in presentation.

- Entry: `logging.odin`, `log_printf`, called as `platform.log_printf`.
- Files: section Packages.
- State: `global_log` (`Log_State`) and `captured_log_error` behind `begin_log_capture` and `end_log_capture`.
- Tests: `jni_indices_test.odin` and `platform_paths_test.odin` beside the package; the game's `platform_paths_test.odin` checks the directory mappings through the game's path helpers and scans every package for the Windows static runtime imports; `write_file_replacing` and `rename_file_aside` are tested through the game's writer and settings fallback tests; the log file, the time zone lookup and the export access are untested.
- Reaches into: nothing.

## Packages

Leaf packages under `src/` (work item 0145, the pilot split): each is a directory with its own `package` line, imported by the files that use it (`import "platform"`, `import "../platform"` from a package), its names qualified at every use (`platform.log_printf`). A package imports no game file, so the compiler keeps it a leaf. `./build.sh test` runs their tests with `-all-packages` ([build.md](build.md)).

- `platform`: `logging.odin`, `logging_posix.odin`, `logging_windows.odin` (`Log_State`, the log file and `log_printf`, `Log_Capture`; the stderr redirect and crash traces per system); `platform_paths.odin` (`Platform_Directories`, `join_path`, `make_directory_path`); `file_write.odin` (`write_file_replacing`, every file the game writes, and `rename_file_aside`); `platform_android.odin` (the Android entry points and logcat, imports `android_libc` for the link); `local_zone.odin`, `local_zone_posix.odin`, `local_zone_windows.odin` (the local time zone); `jni_indices.odin`, `jni_android.odin` (JNI table indices; `Jni_Calls` and the call helpers); `export_access_android.odin`, `export_access_desktop.odin` (All files access for the export). Tests: `jni_indices_test.odin`, `platform_paths_test.odin`.
- `generation_seed`: `generation_seed.odin` (`Generation_Purpose`, `Purpose_Seeds`, `hash_u64`, `hash_combine` and the hash helpers).
- `model_vox`: `model_vox.odin` (`Voxel_Model`, the .vox parser, `model_file_path`), imports `platform`. Tests: `model_vox_test.odin`.
- `render_frustum`: `render_frustum.odin` (`Frustum`, `frustum_from_matrix`, `frustum_contains_box`). Tests: `render_frustum_test.odin`.
- `run_length`: `run_length.odin` (`Run`, `run_length_encode`, `run_length_decode`). Tests: `run_length_test.odin`.
- `sjson_text`: `sjson_text.odin` (the SJSON writer of the data edits and `sorted_object_keys`). Tests: `sjson_text_test.odin` (the writer's round trip, with its own copy of the game's `json_values_equal` test helper); the round trip of every shipped file needs the game's data file listing and stays in `data_browser_test.odin` (`test_shipped_sjson_files_round_trip`).
- `android_libc`: `android_libc.odin` (the glibc functions bionic lacks, [android.md](android.md)).
