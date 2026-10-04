# Code map

The entry page for the source: 269 files under `src/` plus 189 test files beside them. 243 are the `game` package, grouped into seven clusters; 26 are eight leaf packages under `src/` (section Packages), each a cluster named after its directory. Read the cluster table, pick a cluster, open its entry file; the section of each cluster lists its files in reading order. How the parts work is in [architecture.md](architecture.md), the why of the clusters in the audits under [audit/](audit/).

- Rule: a new file goes into a cluster and takes one of its file name prefixes (or a line in the file table of `tools/code_graph.py`); a reference against the allowed dependency table below is a finding until it is refactored away.
- The map is kept true by two checks: `python3 tools/check_docs.py` checks every backticked file and name in it, and `python3 tools/code_graph.py --check doc/code_map.md` compares every cluster edge the allowed table does not allow with the map's record of it ([build.md](build.md), Source checks).
- The record is the "Reaches into" line of each cluster section: `target count (notes)` parts separated by commas, or `nothing`. The check fails when an edge is missing from the record or above its recorded count, so a new reach through is caught; when a refactor lowers a count, lower the record by hand in the same commit.
- The clusters of the map and of `tools/code_graph.py` are the same: the script assigns each file of the game package by its prefix, a few files by name, and prints any file it had to place by its edges. A package's files are its cluster; the script names them with the directory (`platform/logging.odin`) and resolves a name after an import's name and a dot (`platform.log_printf`) in that package, so a package's edges are only the ones the compiler allows: into the packages it imports, never into the game package.

## Clusters

| Cluster | Purpose | Entry | Files | Lines | Audit |
|---|---|---|---|---|---|
| loop | the process: start-up, the frame, when the tick runs (the lockstep driver), sessions, the network, the LAN discovery and the server, the requests served between frames | `loop.odin` | 16 | 7887 | [loop](audit/loop.md) |
| ui | the input layer, the immediate mode toolkit, every screen, the HUD and the touch overlay | `ui_core.odin` | 50 | 17617 | [ui](audit/ui.md) |
| world | blocks and what follows a block: chunks, light, water, meshing, streaming, generation, the save codec; the terrain field and the foundation frames beside them (M13) | `world_chunk.odin` | 51 | 14758 | [world](audit/world.md) |
| simulation | the factory per tick: entity pools, networks, players, inventories, crafting, statistics, the game's records | `entity.odin` | 54 | 21490 | [simulation](audit/simulation.md) |
| presentation | pixels and sound from the world and the tick: shaders, atlases, models, sky, weather, particles, audio, the window | `render_chunks.odin` | 43 | 10737 | [presentation](audit/presentation.md) |
| content | data files into typed tables, the string table, configuration and settings | `data_reload.odin` | 17 | 6000 | [content](audit/content.md) |
| tools | the command socket, the diagnostics pages, the Data files browser and export, the factory benchmark | `command.odin` | 8 | 3977 | [loop](audit/loop.md), [content](audit/content.md) |
| platform | the package `src/platform/`: logging, paths, the time zone, JNI, the export's file access, the replacing file write, the TCP transport and the LAN discovery's UDP, the stop signal | `logging.odin` | 19 | 1843 | [content](audit/content.md) |
| generation_seed | the package `src/generation_seed/`: purpose seeds and the integer hashes | `generation_seed.odin` | 1 | 79 | [world](audit/world.md) |
| model_vox | the package `src/model_vox/`: the MagicaVoxel parser | `model_vox.odin` | 1 | 283 | [presentation](audit/presentation.md) |
| model_obj | the package `src/model_obj/`: the Wavefront OBJ and MTL reader | `model_obj.odin` | 1 | 399 | [presentation](audit/presentation.md) |
| render_frustum | the package `src/render_frustum/`: frustum planes and the box test | `render_frustum.odin` | 1 | 35 | [presentation](audit/presentation.md) |
| run_length | the package `src/run_length/`: the chunk run length codec | `run_length.odin` | 1 | 39 | [world](audit/world.md) |
| sjson_text | the package `src/sjson_text/`: the SJSON writer and `sorted_object_keys` | `sjson_text.odin` | 1 | 212 | [content](audit/content.md) |
| android_libc | the package `src/android_libc/`: the glibc functions bionic lacks, for the Android link | `android_libc.odin` | 1 | 63 | [content](audit/content.md) |

## Allowed dependencies

Rule: a cluster references only the clusters of its row. The pilot split (0145) and any later package split follow it. The edges that run against it are recorded in the "Reaches into" line of each cluster below.

| Cluster | May reference |
|---|---|
| loop | ui, world, simulation, presentation, content, tools, platform, generation_seed, model_vox, model_obj, render_frustum, run_length and sjson_text |
| ui | presentation, simulation, world, content, platform, generation_seed, model_vox, model_obj, render_frustum, run_length and sjson_text |
| world | content, platform, generation_seed, model_vox, model_obj, render_frustum, run_length and sjson_text |
| simulation | world, content, platform, generation_seed, model_vox, model_obj, render_frustum, run_length and sjson_text |
| presentation | simulation, world, content, platform, generation_seed, model_vox, model_obj, render_frustum, run_length and sjson_text |
| content | platform, generation_seed, model_vox, model_obj, render_frustum, run_length and sjson_text |
| tools | ui, world, simulation, presentation, content, platform, generation_seed, model_vox, model_obj, render_frustum, run_length and sjson_text |
| platform | android_libc |
| generation_seed | nothing |
| model_vox | platform |
| model_obj | platform |
| render_frustum | nothing |
| run_length | nothing |
| sjson_text | nothing |
| android_libc | nothing |

- The packages sit where the platform cluster sat: every game cluster may reference them, and they reference only the packages of their row (`platform` imports `android_libc` for the link alone, `model_vox` and `model_obj` name `platform.join_path`).
- The order is engine below game only in part: world storage and the platform are engine, the simulation is game, presentation and ui mix both ([audit/](audit/), section 6 of each report).
- In the records, "accepted" means essential today and named in an audit; "queued" names the entry of the 0143 refactor queue that removes the references (1 pure moves, 3 the hubs, 5 the seams). Graph noise (a field or parameter named like a top level procedure, such as `block_name`) counts as a reference; the rename that ends it is queued where one is.

## loop

The process: the loop decides when things run, the clusters decide what runs.

- Entry: `loop.odin`, `run_game` (the window and the frame order), from `main`.
- Files in reading order:
  - `main.odin`: `Command_Line`, `main`, `load_start_data` with the overlay fallback, the world start.
  - `loop.odin`: `Frame_State` and its four groups, `run_game` and `update_frame`, `make_screen_context`, `serve_frame_requests_before_draw` (the order of the frame requests) and the serve procedures it calls, `Game_Content`.
  - `session.odin`: `Session`, `start_session`, `end_session`, `save_session`.
  - `viewport.odin`: `Viewport` with `Viewport_Interaction` and `Viewport_Presentation` (the per player halves of the two groups, 0178), `viewport_rectangles`, `viewport_ui_scale`, `pad_claim`, adding and removing a viewport, `collect_global_requests`, the split screen render targets.
  - `lockstep.odin`: `Lockstep`, `Local_Member`, `Input_Record`, the driver (stamp, receive, `lockstep_records_ready`, `begin_lockstep_tick`), the prediction, `lockstep_state_hash`, and `run_ready_ticks` with the socket lines of a tick.
  - `session_network.odin`: `Session_Network`, `Session_Join`, the message codec, the host's relay, join, keepalive and hash comparison, the client's side, `Join_Snapshot`, a split screen player's join and leave (`request_local_player`, `leave_local_player`).
  - `session_server.odin`: `Server_State`, `run_server` (`--server`).
  - `session_discovery.odin`: every game hosts and the LAN finds it (0188): `Hosting_Plan` (the port range, the discovery port), `host_windowed_session`, `session_player_count`, `answer_discovery_queries` (the host's side), `Lan_Query` and `serve_lan_query` (the Multiplayer screen's side).
  - `hot_reload.odin`: the reload per data category on `Frame_State`, served between frames.
  - `main_android.odin`: the Android C entry wrapping `main`.
  - `loop_field_session.odin`: a field session's frame side (0179): `stream_field_session` (the simulated set's requests and arrivals as commands, the meshes), `field_viewport_selection` over every viewport's eye made once a frame (`frame_field_selection`), `carry_field_turn` (the turn's fraction carried from record to record), `start_field_presentation`, `draw_field_viewport_world` and `draw_field_scene` (the sky, the field, the foundations, the entities, the trees, the runs, the torches, the players, the ghosts), `prepare_field_frame`.
  - `loop_planet_preview.odin`: `run_planet_preview`, the `--planet-preview` window over the terrain field (0169) with its walk mode; since 0179 a field session of its own (`start_planet_preview_session`) ticked on a fixed step (`walk_planet_preview`) and drawn through `draw_field_scene`, the walk screenshot's pit and pad (`dig_planet_preview_pit`, `lay_planet_preview_foundations`).
  - `loop_planet_preview_arms.odin`: the walk screenshot's two arms on the pad, one posed at full reach, their models and point lights (0175, `lay_planet_preview_arms`).
  - `loop_planet_preview_runs.odin`: the walk screenshot's second pad and the belt run between a free pole off each pad (0176, `lay_planet_preview_run`).
  - `loop_model_check.odin`: `run_model_check`, the `--model-check` command (0207), and `model_workbench_selection`, the machines both workbench flags take.
  - `loop_model_preview.odin`: `run_model_preview`, the `--model-preview` window (0207): a machine on a pad from five cameras at four phases, one PNG per shot.
- State: `Frame_State` (21 top level fields: the loop's 17, the request set `Frame_Requests` and the viewports among them, and four groups holding 48 other clusters' fields, `Frame_Interaction` 16, `Frame_Presentation` 17, `Frame_Developer_Tools` 8, `Frame_Reload` 7), `Viewport` (10 fields, with `Viewport_Interaction` 8 and `Viewport_Presentation` 7, the per player fields the two groups held before 0178), `Session`, `Lockstep`, `Session_Network`, `Game_Content`.
- Tests: `main_test.odin`; `lockstep_test.odin` (machines through an in-process relay) and `session_network_test.odin` (the join, a joiner restoring while the others play, dropping or a second one arriving, the server, a joined machine's split screen player); `session_discovery_test.odin` (a host answers the LAN over the loopback, two hosts on one machine, a windowed host alone, a join from the list); `viewport_test.odin` (layouts, joining with a pad, two viewports' cameras and draw lists, requests per viewport and once for the game, four viewports and one tick); the draw path, the session lifecycle and the reloads are untested (loop audit, section 8).
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
  - `ui_screens.odin`: `Frame_Request` (what a screen asks of the loop), `Screen_Context` and `Developer_Context`, `handle_screen_keys`, `run_screens`, the pause menu, settings.
  - `ui_title.odin`, `ui_world_setup.odin`: `Title_State`, load and delete; the new world values.
  - `ui_multiplayer.odin`: the Multiplayer screen (0188), `Multiplayer_State` and its list of `Lan_Game` (`add_lan_answer`, `prune_lan_games`), the join request.
  - `ui_inventory.odin`, `quick_transfer.odin`: the inventory screen, `finish_slot_drag` and `queue_slot_command`; the quick move state machine and the transfer buttons, which queue slot commands.
  - `ui_machine.odin`: the machine panel frame, furnace, inserter, drill and splitter sections.
  - `ui_crafting_machines.odin`, `ui_fluid.odin`, `ui_power.odin`, `ui_launch_pad.odin`, `ui_prospecting.odin`, `ui_contracts.odin`: the panel sections for assemblers and labs, fluids, power, launch pads, prospecting, the venture.
  - `ui_recipes.odin`, `ui_recipe_browser.odin`: the recipe screen; its pure filtering and detail.
  - `ui_technologies.odin`, `ui_technology_browser.odin`: the technology screen; its pure filtering.
  - `ui_statistics.odin`, `ui_map.odin`, `ui_journal.odin`, `ui_mission_control.odin`: statistics; `Map_View`; the journal; Mission Control and the discovery card.
  - `ui_session_views.odin`: `Session_Views`, the played world's browsers, statistics and map, made, destroyed and reset with the session.
  - `ui_developer.odin`, `ui_data_browser.odin`, `ui_texture_editor.odin`, `ui_touch_layout_editor.odin`: the Developer, Data files, Textures and touch layout screens.
  - `hud.odin`, `biome_banner.odin`: `Hud_Context`, crosshair, `target_status_lines`, hotbar, craft queue, glyph hints, the tools radial; the biome banner.
  - `ui_placement_editor.odin`: the placement editor's state, its world frame and its ghost, 0215.
  - `touch_overlay.odin`: the virtual gamepad, its layout files, gestures, drawing ([touch_overlay.md](touch_overlay.md)).
  - `haptics.odin`, `haptics_android.odin`, `haptics_desktop.odin`: `Haptic_Request` and the rumble constants for every target; the phone's vibrator, through the JNI helpers of the platform package; the desktop stub.
  - `system_keyboard.odin`, `system_keyboard_linux.odin`, `system_keyboard_android.odin`, `system_keyboard_windows.odin`: `System_Keyboard_Field`, a text field's window rectangle; show and hide the platform keyboard for it.
- State: `Ui_State` (58 fields, one per viewport), `Screen_Context` (32), `Hud_Context`, `Input_Frame`, `Touch_Overlay_State`, `Title_State`; `Session_Views` (the map and the browsers) sits beside the session on each viewport's `Viewport_Interaction`.
- Tests: every `*_test.odin` beside its file; `ui_audit_test.odin` draws every screen at every audit size, `ui_pointer_test.odin` the pointer and taps, `accessibility_test.odin`.
- Reaches into: tools 43 (accepted: the Data files screen on `Data_Browser` 31, the diagnostics page names 3, a `block_name` field as noise 9), loop 10 (accepted 3: `Touch_Overlay_Context` in `touch_overlay.odin` names `Frame_Interaction`, `Game_Content` and `Session`, 0158; accepted 1: `touch_interaction_frame` reads the tap's aimed frame cell from the predicted field player through `lockstep_view_player`, 0194; accepted 6: `mining_ring_centre`, `BUILD_STAMP`, `parse_seed`, noise).

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
  - `world_field.odin`, `world_field_codec.odin`: the terrain field (0168): `Field_Chunk`, `Field_World`, `World_Position` and the sample conversions, get and set, dirty marking; the field chunk's delta bytes.
  - `world_field_mesh.odin`, `world_field_lod.odin`, `world_field_streaming.odin`: the field mesher (0169), `Field_Grid`, `gather_field_grid`, `mesh_field_surface`, `field_mesh_from_surface`; the level of detail, `Field_Node`, `select_field_nodes`, `generate_field_grid`, `append_field_skirts` on the faces `field_node_skirt_faces` gives; `Field_Streaming`, its workers and mesh revisions.
  - `world_field_water.odin`: the water field (0172), `Field_Water_Tuning`, `step_field_water` in chunk and sample order, the potential, sleeping and waking, the sources and films, `displace_field_water`, `field_water_density` for the mesher.
  - `world_field_light.odin`: the field light (0173), `Field_Lighting` with its removal and addition queues per channel, `propagate_field_light`, the emitters (`add_field_light_source`), the sky march `field_sky_is_open` and the edit's shadow (`update_field_sky_after_edits`), the arrived chunks' borders, `tick_field_light`.
  - `world_field_edit.odin`: the brush edits (0171), `Field_Edit`, `apply_field_edit` in one sample order, the level plane, `field_place_meets_capsule` (the bury dry run), `field_ground_sample_at`.
  - `world_frame.odin`, `world_frame_raycast.odin`, `world_frame_collision.odin`: the foundation frames (0174), `Frame`, `Frame_Table` with the occupant index (`occupy_frame_cell`, `vacate_frame_cell`, `frame_occupant`), `remove_frame`, `BLOCK_FRAME`, the cell and world transforms, `frame_axes` and `free_frame_at`; `raycast_frames`, the voxel walk in each frame's axes; the solid cells as boxes for the field player (`field_solid_probe`, `field_solid_raycast`).
  - `world_field_vector.odin`, `world_field_distance.odin`, `world_field_raycast.odin`: fixed point unit vectors and angles, `fixed_sine` (0170); the field as a signed distance, `field_density_at` and `field_surface_probe`; `raycast_field`, the field's counterpart of the voxel walk.
  - `world_vein.odin`, `world_explored.odin`: the vein registry and outcrops, `vein_under_world_position` for the discs on the sphere (0179); explored columns for the map.
  - `world_debug_edit.odin`, `world_debug_terrain.odin`: the F-key dig; the flat debug terrain.
  - `generation.odin`: `Generator`, `DEFAULT_WORLD_SEED`; the purpose seeds and the hashes are the `generation_seed` package (Packages).
  - `generation_chunk.odin`, `generation_terrain.odin`, `generation_caves.odin`: the per chunk steps; height, climate, the column grid and the cave carving; the crate site search in cave pockets.
  - `generation_biome.odin`, `generation_trees.odin`, `generation_features.odin`: biomes and species, trees, boulders and ground cover.
  - `generation_veins.odin`, `generation_vein_tables.odin`, `generation_starter_veins.odin`: vein placement and outcrops, the vein file, starter veins.
  - `generation_spawn.odin`, `landing_pad.odin`: the spawn search; the landing pad stamp.
  - `generation_planet.odin`: the terrain field's planet generation, `generate_field_chunk`, `integer_square_root`, the relief and its crater term at the home (`uncratered_relief`, `crater_relief`, 0199).
  - `generation_planet_trees.odin`: the trees as a generation function (0197): the grove and tree lattices on the sphere, `planet_trees_in_box`, `planet_tree_at_key`, `Tree_Key`.
  - `generation_planet_veins.odin`: the veins on the sphere (0179): `Planet_Veins` in `Planet_Generation`, `plan_planet_veins` round the home, the outcrop material of `planet_sample`, `register_planet_veins` into the vein registry.
  - `generation_planet_record.odin`: `Planet_Generation_Record`, the generation values a world file records, and `resolve_world_planet`, the world's planet against the data (0179).
  - `save_binary.odin`: the type driven codec (schemas, enums by name, lists).
  - `save_state.odin`, `save_remap.odin`: the entities.bin body and `simulation_state_hash`; content tables and the id remap.
  - `save_world.odin`, `save_list.odin`: world.sjson, region files, staging and swap; the save list.
- State: `World` (13 fields: chunks, settings, veins and their indices, outcrops, block changes, light, water, saved chunks and `entities`, which carries the frame table and its occupant index, `Frame_Table`), `Chunk`, `Chunk_Streaming` (on `Session`), `Generator`, `Block_Registry`, `World_Settings`, `Field_World` and `Field_Streaming` (on `Session` and `Field_Simulation` in a field session, 0179).
- Tests: every `*_test.odin` beside its file; `save_test.odin` and `save_codec_test.odin` (save, load and run to the same hash).
- Reaches into: simulation 251 (accepted 244: the save codec encoding pools, `Game_Records`, `Simulation_State` and `Simulation_Content`, and `save_world.odin` calling `make_simulation` and `simulation_day_ticks` 234, of which the frame tables 5 (0174) and the belt poles' and runs' pools in `entity_pool_length` and `entity_common_at` 4 (0176, the kinds `.Belt_Pole` and `.Belt_Run` read as the types of `belt_run.odin`), the field tables and `field.bin` through `simulation_field_save.odin` 5 and `Simulation_State.field` read for the field flag 2 (0179), the machine wear table (`write_machine_wear_table`, `read_machine_wear_table`), `refresh_all_founded` after a load and the saved toast key `MACHINE_BROKE_DOWN_KEY` in `save_state.odin` 5 (0201), the felled trees' table (`write_felled_tree_table`, `read_felled_tree_table`) in `save_state.odin` 2 (0197), the older pod's replacement at load (`upgrade_resized_pods`, `finish_pod_upgrades`) and the sealed rooms' rebuild (`rebuild_sealed_rooms`) in `save_state.odin` 3 (0198), the quests' reward target settled at load and the locker's toast key in `save_state.odin` 3 (0210), the count of machines that keep their saved size (`count_entities_keeping_saved_size`) for the load's log line in `save_state.odin` 1 (0212), the arrival's table (`write_field_arrival_table`, `read_field_arrival_table`) in `save_state.odin` 2 (0200), the former ids in `save_remap.odin` (`content_former_ids` and `content_former_id_problem` on `Simulation_Content`, `MACHINES_FILE_NAME` in the load's error line) 3 (0196), `vein_is_exhausted` 1, `tick_world` running the leaf decay queue of `tree_felling.odin` 4; queued 4: streaming registering the crate sites and the explored column into `Game_Records` at chunk arrival 5; queued 5: `World.entities` 2, since the raycast and the water read the occupant index (0174)), presentation 12 (accepted: the mesher's atlas and tile variation).

## simulation

The factory: what changes per tick; blocks belong to the world, prototypes to content.

- Entry: `entity.odin`, `tick_entities` (called through `tick_entities_on_world` by `simulation_tick` in `simulation_world.odin`).
- Files in reading order:
  - `player_command.odin`: `Player_Command`, the queue every write from outside the tick goes through, applied at the start of `simulation_tick`.
  - `player_command_slots.odin`: the slot commands of the inventory screen and the machine panel (0179), `slot_command_stale`, the check both sides make.
  - `simulation_chunk_set.odin`: `Simulated_Chunk_Set`, the chunks the tick may read, derived from the players.
  - `simulation_state.odin`: `Simulation_State`, `Game_Records` (the game's records beside the world), `Simulation_Event`, `make_simulation` with `place_capsule`, `destroy_simulation` and `destroy_game_records`, `simulation_day_ticks`.
  - `simulation_world.odin`: `Simulation_Content`, `Entity_Tick_Context` with its block procedures, `simulation_tick`, `apply_research_result`, `simulation_quest_context`.
  - `entity.odin`: `Entity_Kind`, `Entity_Handle`, `Entity_Common`, `Entity_Pool`, `Entities`, add and remove, `tick_entities`.
  - `entity_placement.odin`: placement rules, `commit_placement`, rotation, pick up; a drill on a frame with its vein (`place_drill_on_frame`, `frame_drill_placement_refusal`, 0179).
  - `entity_pod.odin`: the pod in its crater with its hatches and fixtures (`place_pod`, `toggle_hatch`), the sealed room (`Sealed_Room`, `rebuild_sealed_rooms`, `sealed_room_at_feet`), the old pod's upgrade at load with its fixtures and locker (`upgrade_resized_pods`, `take_old_pod_fixtures`) and the first pod's locker (`pod_locker`) (0179, 0199, 0198, 0210, 0221).
  - `entity_pod_airlock.odin`: the pod's airlock (0222): the doors open for a player close and facing them and close behind after a hashed hold, `tick_pod_airlocks`, the interlock `pod_airlock_refuses_opening`.
  - `machine_wear.odin`: machines on bare ground (0201): the flatness check and the placement on a frame of its own (`bare_ground_is_flat`, `place_on_bare_ground`), the founded flag, the wear tick and the breakdown (`record_operation`, `log_machine_breakdowns`), the salvage (`machine_return_stacks`) and the wear table of the save.
  - `entity_frames.odin`: placement on foundation frames (0174), `place_on_frame`, `place_free_foundation`, `frame_placement_refusal`; the field's place commands (`Field_Placement`, `drain_field_placements`, `apply_field_placement`, `aim_field_player_at_frames`); the frame tables of the save (`write_frame_tables`, `read_frame_tables`).
  - `machine.odin`: `Machine_Kind`, `Machine`, `Machine_Registry` and per kind validation.
  - `item_transfer.odin`: `entity_accepts`, `entity_insert`, `entity_extract`.
  - `belt.odin`, `belt_movement.odin`, `belt_placement.odin`: transport lines and their rebuild (segments of a run's length, `belt_line_segment_start`), lane movement, drag placement.
  - `belt_run.odin`, `belt_run_placement.odin`: belt and pipe runs between belt poles and belt ends (0176), `Belt_Run`, the curve (`belt_run_curve`, `belt_run_point_at`), the constraints (`belt_run_shape_refusal`), `link_belt_runs`, the run tables of the save; the field's run tool (`update_field_run_tool`, the selection assist `nearest_belt_run_option`, `drain_field_run_placement`).
  - `splitter.odin`, `inserter.odin`, `loose_item.odin`: round robin and filters; the swing cycle; stacks lying in cells.
  - `drill.odin`, `furnace.odin`: vein draws, boring, revival; the furnace and the shared burner step.
  - `assembler.odin`, `recycler.odin`: crafting machines; recycle recipes and returns.
  - `lab.odin`, `launch_pad.odin`: `Research_State`, units and queueing; assembly stages, launch, shipments.
  - `schematic.odin`, `prospecting.odin`: the schematic crate kind; core sample drills, the magnetometer and seismic records.
  - `fluid.odin`, `fluid_machine.odin`, `machine_fluid_ports.odin`, `fluid_network.odin`: the fluid registry; pipes and fluid machines; port layouts; segments and flow.
  - `power_machine.odin`, `power_network.odin`: generators, poles, lamps; nodes, memberships, balance.
  - `player.odin`, `player_interaction.odin`, `player_collision.odin`: `Player` and movement; mining and placing; swept collision.
  - `player_field.odin`: `Field_Player` on the terrain field (0170), `tick_field_player`, the capsule against the signed distance, slopes, step, jump, mantle and fly mode in the planet's frame; each player's body in a field session (`Player.field`, 0179).
  - `field_mining.odin`: the hand tool on the field (0171), `Field_Simulation` with its edit queue drained in `finish_field_tick`, the material table of `data/materials.sjson`, the yield and the credit, the tool tier, the place refusals, the torches.
  - `field_trees.odin`: the trees on the field (0197), `Field_Tree_Species` from the planet's species, the trunks the field player is pushed out of and aims at (`move_and_aim_field_player`), felling (`advance_field_felling`, `drain_field_felling`), the trees felled by a dig under their base (`fell_trees_over_dug_ground`), the trunk refusal of a placement, `clear_trees_under_frames`, the felled table of the save.
  - `simulation_field.odin`: a field session's tick (0179): `field_tick_input`, the hotbar's tool (`field_tool_for_item`), `tick_field_session_players`, `finish_field_tick`, the pod's site and the spawn in its cabin (`field_home_site`, `field_pod_spawn`, `field_spawn_player`, `field_home_player`, `make_field_session_player`), `enable_new_field_world`, `make_field_content`.
  - `simulation_field_chunk_set.odin`: the field's simulated chunk set (0179), `update_simulated_field_chunks`, `field_chunk_requests` and `needed_field_chunks`, the arrivals (`Field_Chunk_Ready_Command`), `stage_generated_field_set`.
  - `simulation_field_save.odin`: the field tables at the end of `entities.bin` and `field.bin` (0179), `restore_arrived_field_set` (0185), the state hash's field part (`field_state_hash`).
  - `simulation_arrival.odin`: a new world's fall (0200), `Field_Arrival`, the held input (`arrival_input`), the landing, which leaves the hatches closed since 0222 (`land_field_arrival`), the arrival's table of the save.
  - `inventory.odin`, `inventory_interaction.odin`, `crafting.odin`: `Item_Stack`, `Inventory`; slot clicks; `Craft_Queue` and hand crafting.
  - `inventory_transfer.odin`: the verbs the slot commands run: quick moves, the transfer buttons, the grid transfers, the inserter's hand, the slot filters of a machine.
  - `statistics.odin`, `production_statistics.odin`: `Statistics` and rate rings; statistics rows and the marker colours.
  - `recipe_unlocks.odin`, `quest_runtime.odin`: `Recipe_Unlocks` per tick; `Quest_State`, objectives, rewards, messages, the reward target (`quest_reward_target`, `settle_quest_reward_target`).
  - `venture.odin`, `tree_felling.odin`: `Contract_State`, shipments served, the orbital survey; felling and leaf decay.
  - `developer.odin`: developer kits and `serve_developer_request`, run inside the tick for a `Developer_Request` command.
  - `tick_profile.odin`: `Tick_Profile`, wall time per tick section.
- State: `Simulation_State`, `Game_Records` (the records beside the world), `Simulation_Content`, `Player_Command`, `Simulated_Chunk_Set`, `Entities` (19 pools with the foundations, the belt poles and runs, the belt, fluid and electric networks, the frame table with the occupant index, loose items), `Player`, `Field_Player` and `Field_Simulation` (a field session's, 0179), `Inventory`, `Statistics`, `Research_State`, `Quest_State`, `Recipe_Unlocks`, `Contract_State`, `Tick_Profile`.
- Tests: every `*_test.odin` beside its file; `simulation_tick` through the simulation and save tests; the systems in `byproduct_test.odin`, `chemistry_test.odin`, `combustion_test.odin`, `deep_mining_test.odin`, `hydro_grid_test.odin`, `oil_test.odin`, `ore_processing_test.odin`, `power_test.odin`; the whole chain in `benchmark_test.odin` (tools).
- Reaches into: loop 1 (accepted: `parse_seed`), ui 47 (accepted: the tick's input types `Input_Frame`, `Action_Set`, `Action`, of which `field_tick_input` and `field_frame_turn` 8, 0179, `without_field_interact_jump` 2, 0194, and `arrival_input` holding the tick's frame during the fall 3, 0200), presentation 21 (accepted: machine models and motion 7, of which a hatch's motion kind read in `validate_hatch_definition` 1 (0198), `Fly_Camera` 6, its look rates 2 (0179: `field_tick_input` turns the frame's stick and pointer look into the tick's turn with the rates the fly camera turns by, so they are input rates the tick reads, kept beside the camera that shares them), `block_centre` and `line_block_belt` 5, `DAY_START_FRACTION` 1).

## presentation

Presentation turns the world, the tick and the render time into pixels and sound; nothing reads it back.

- Entry: `render_chunks.odin`, `Chunk_Renderer`; the frame's draw order is `draw_session_world` in `loop.odin`.
- Files in reading order:
  - `render_chunks.odin`: shader loading with retry and the GLES rewrite, mesh upload, uniforms, `draw_chunks`.
  - `render_field.odin`, `texture_field_materials.odin`: `Field_Renderer`, the field's triplanar shader, node meshes and the globe (0169); the field materials' generated tiles.
  - `render_atlas.odin`, `texture_generate.odin`, `texture_variation.odin`: `Atlas_Layout`, `load_rgba_texture` (the hashes are the `generation_seed` package); procedural ore tiles and texture edits; the Odin mirror of the shader's tile variation.
  - `render_water.odin`: `Water_Renderer`, underwater fog; the frustum test is the `render_frustum` package (Packages).
  - `render_day.odin`, `render_sky.odin`: `Day_Sky`, sun and moon; the sky dome, stars, the survey satellite.
  - `weather.odin`, `render_weather.odin`: `weather_at`, the hourly schedule; `Weather_Look`, rain, snow, clouds.
  - `render_entities.odin`, `render_models.odin`: `draw_entities` over the pools, bottleneck markers, the models' working procedures (`foundation_model_working` and the others) and `gather_machine_lights` (0224); `Model_Renderer`, posed and ghost models, the model shader for the lit layer (0224), the pods' interior light (`gather_interior_lights`, `posed_model_light`, 0225).
  - `render_frames.odin`: the frames' placeholder boxes per occupied cell and the placement ghost (0174), `frame_render_matrix`.
  - `model_mesh.odin`, `model_motion.odin`: the voxel mesher over the `model_vox` package's parser (Packages), the choice of an .obj over a .vox and `model_mesh_triangle`, the reader of a layer's triangles in either shape (0226); `Machine_Motion` and part transforms.
  - `model_triangle_mesh.odin`: the OBJ mesher over the `model_obj` package's reader (Packages): flat shade, footprint check.
  - `model_check.odin`: the workbench's checks (0207): budget, sweep, a pod's fixture parts, arm clearance, open cells.
  - `model_arm.odin`, `render_arm.odin`: the inserter's arm (0175): its part files, `arm_pose_at` from the cycle, the joint transforms; its draw and its lamp's light.
  - `render_point_lights.odin`: `Point_Light`, the nearest working lights for the field shader and the model shader (0175), machine lights in the world and the uniform packing (0224), the clip boxes (0229).
  - `render_belts.odin`, `render_fluids.odin`, `render_power.odin`, `render_loose_items.odin`: belts and lane items; pipes and ports; poles and wires; loose stacks.
  - `render_belt_runs.odin`: belt and pipe runs swept along their polylines, their items and the belt poles (0176), `draw_belt_runs`, `draw_belt_run_ghost`.
  - `render_icons.odin`: `Item_Atlas` for items and UI icons, item billboards.
  - `cues.odin`: `Cue_Memory`, `detect_cues`, the frame's cues from the simulation's counters that the player, the particles and the sounds read.
  - `render_player.odin`, `render_player_model.odin`, `player_animation.odin`, `render_fly_camera.odin`: pose, camera, ghosts, hands; limb models; walk cadence and limb angles; `Fly_Camera`.
  - `render_field_trees.odin`: the trees' draw (0197), `Field_Tree_Cache` of the regions round the eyes (`update_field_tree_cache`), `field_visible_trees` capped nearest first, `draw_field_trees`.
  - `render_field_camera.odin`: `field_camera`, the field player's first and third person cameras with the player's up (0170); the crouch's easing and eye (0218).
  - `render_arrival.odin`: the arrival's presentation (0200): `arrival_view`, the descent's camera on the tilted path, the window overlay and its flames, the shake, the dust, the arrival's sounds and the hatch cue (`play_hatch_sounds`).
  - `particles.odin`, `render_particles.odin`: `Particle_System`; emitters, `Particle_Memory`, capsule descent.
  - `ambient_life.odin`, `render_life.odin`, `render_flames.odin`: flocks, insects, fish; their draws; torch flames.
  - `audio.odin`, `sound_events.odin`: `Audio_Mixer`, sound table, loop fades; `Sound_Memory`, the sounds of the cues, hum, ambience clusters.
  - `display.odin`, `raylib_log.odin`: window modes, resolutions, scale, GL info; raylib's log into the game log.
- State: the GPU resources (`Chunk_Renderer`, `Item_Atlas`, `Belt_Renderer`, `Model_Renderer`; `Field_Renderer` in the planet preview) and `Audio_Mixer` for the run, the memories (`Cue_Memory`, `Particle_System`, `Particle_Memory`, `Player_Animation_Memory` per viewport, `Sound_Memory` once) for a session; nothing is saved.
- Tests: every `*_test.odin` beside its file; `shader_source_test.odin` (the `u` suffix rule), `render_ghost_test.odin`, `texture_periodicity_test.odin`; the draw procedures are untested; `model_arm_test.odin` tests the arm's poses; `model_check_test.odin` the workbench's checks against hand built meshes and over the shipped models.
- Reaches into: ui 17 (accepted: theme colours and marker palettes 13, `Input_Frame` for the fly camera 2, `Ui_Sound_Event` 2), loop 3 (accepted: `texture_edits_path` 1, `draw_field_trees` and `field_tree_model_extent` taking the frame's `Field_Scene` like the other field draws of `loop_field_session.odin` 2 (0197)), tools 2 (accepted: a `block_name` parameter, noise).

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
  - `data_planet.odin`: `Planet`, the planet records of `data/planets.sjson`.
  - `data_lighting.odin`: `Lighting_File`, the field light's curve, budget and emitters of `data/lighting.sjson` (0173), held to the strict keys.
- State: the registries, one arena per load (`content_arena` in `Frame_Reload`), the global `String_Table`, `Settings`, `Game_Config`, `Data_Watch`.
- Tests: every `*_test.odin` beside its file; the shipped chapters in `quest_chapter_02_test.odin` to `quest_chapter_08_test.odin`; most simulation tests build content through `make_test_content` (`machine_test.odin`).
- Reaches into: world 98 (accepted: item, quest and discovery definitions naming blocks 48, the content reload remapping the world 40, data file names 4, the planet record's bedrock floor reading generation's deep stone band 1, the relief bound in `data_planet.odin` reading the field's `MILLIMETRES_PER_METRE` 3 (0189), the content load calling the former id check `content_former_id_problem` of `save_remap.odin` 1 (0196), the arrival's path bound in `arrival_problem` reading `FIELD_COARSEST_LEVEL` 1 (0200)), simulation 109 (accepted 100: the registries' cross links and value types such as `Item_Stack`, `Furnace`, `Quest_State`, and the field's material table and torch check loading with the tables 5 (0179), the foundations' load checks `crafting_station_recipes_problem` and `field_pad_foundation_problem` with a `MACHINES_FILE_NAME` error line 3 (0196), the reload's tree species check `planet_tree_species_problem` (it needs the item and machine tables, so it lives with the field's trees) and `destroy_field_content` 3 (0197), the `Game_Config` field `bare_ground_life_minutes` named like the wear's procedure 2 (0201, noise); queued 1: `reload_simulation` rebuilding `Simulation_State` through `make_simulation` and `destroy_simulation` with `Simulation_Content` 9, the reload route of a content file that belongs to the loop), ui 40 (accepted: settings typed by `Slider_Range`, `Binding` and the overlay enums, UI data file names and colours), loop 18 (accepted: `Game_Content` and `Session` in the reload, `data_edits_directory`, `BUILD_INFO`, noise), presentation 17 (accepted: data file names, display limits, the arrival's path bound in `arrival_problem` reading the fog's `FOG_START_SHARE` 1 (0200)), tools 12 (accepted: a `block_name` parameter, noise).

## tools

The developer's and the assistant's instruments: they drive, inspect or measure a running game (developer mode, the command socket, the benchmark).

- Entry: `command.odin`, `execute_command_line`.
- Files in reading order:
  - `command.odin`: the command protocol, usage rows, blueprints, queries ([commands.md](commands.md)).
  - `command_socket.odin`, `command_socket_posix.odin`, `command_socket_windows.odin`: paths and `Queued_Command_Line`; the Unix socket and `Command_Server`; the Windows stub.
  - `diagnostics.odin`: `Render_Facts`, `World_Facts`, `Diagnostics_Context`, `Frame_Time_Ring`, the diagnostics pages and world overlay.
  - `data_browser.odin`, `data_export.odin`: `Data_Browser`, the Data files screen's trees and edits; the export.
  - `benchmark_factory.odin`: the factory benchmark, a second driver of `simulation_tick`.
- State: `Command_Context`, `Command_Server`, `Data_Browser`, `Frame_Time_Ring`; they live on `Frame_State` or the stack of a run.
- Tests: every `*_test.odin` beside its file; `benchmark_test.odin` runs sizes 1 and 4 and requires no idle machine.
- Reaches into: loop 3 (accepted: `session_generator`, `parse_seed`, `BUILD_STAMP`).

## platform

The package `src/platform/`, one of the leaf packages below; the leaves over the operating system. The platform shims that take a game type stay in the game package: haptics and the system keyboard in ui, `raylib_log.odin` in presentation.

- Entry: `logging.odin`, `log_printf`, called as `platform.log_printf`.
- Files: section Packages.
- State: `global_log` (`Log_State`) and `captured_log_error` behind `begin_log_capture` and `end_log_capture`.
- Tests: `jni_indices_test.odin`, `platform_paths_test.odin`, `network_test.odin` and `network_discovery_test.odin` beside the package; the game's `platform_paths_test.odin` checks the directory mappings through the game's path helpers and scans every package for the Windows static runtime imports; `write_file_replacing` and `rename_file_aside` are tested through the game's writer and settings fallback tests; the log file, the time zone lookup and the export access are untested.
- Reaches into: nothing.

## Packages

Leaf packages under `src/` (work item 0145, the pilot split): each is a directory with its own `package` line, imported by the files that use it (`import "platform"`, `import "../platform"` from a package), its names qualified at every use (`platform.log_printf`). A package imports no game file, so the compiler keeps it a leaf. `./build.sh test` runs their tests with `-all-packages` ([build.md](build.md)).

- `platform`: `logging.odin`, `logging_posix.odin`, `logging_windows.odin` (`Log_State`, the log file and `log_printf`, `Log_Capture`; the stderr redirect and crash traces per system); `platform_paths.odin` (`Platform_Directories`, `join_path`, `make_directory_path`); `file_write.odin` (`write_file_replacing`, every file the game writes, and `rename_file_aside`); `network.odin` (`Network_Listener`, `listen_on_free_port`, `Network_Connection`, length prefixed messages over TCP, `Network_Dial`, the connect on a thread); `network_discovery.odin`, `network_discovery_linux.odin`, `network_discovery_windows.odin` (the LAN discovery's UDP sockets and datagrams, `parse_discovery_datagram`; the interfaces' broadcast addresses and the machine's name per system); `stop_signal_posix.odin`, `stop_signal_windows.odin` (SIGINT and SIGTERM ask the server to stop; a stub on Windows); `platform_android.odin` (the Android entry points and logcat, imports `android_libc` for the link); `local_zone.odin`, `local_zone_posix.odin`, `local_zone_windows.odin` (the local time zone); `jni_indices.odin`, `jni_android.odin` (JNI table indices; `Jni_Calls` and the call helpers); `export_access_android.odin`, `export_access_desktop.odin` (All files access for the export). Tests: `jni_indices_test.odin`, `platform_paths_test.odin`, `network_test.odin` (a loopback connection), `network_discovery_test.odin` (the datagrams, a query and answer over the loopback, a taken port skipped).
- `generation_seed`: `generation_seed.odin` (`Generation_Purpose`, `Purpose_Seeds`, `hash_u64`, `hash_combine` and the hash helpers).
- `model_vox`: `model_vox.odin` (`Voxel_Model`, the .vox parser, `model_file_path`), imports `platform`. Tests: `model_vox_test.odin`.
- `model_obj`: `model_obj.odin` (`Obj_Model`, `load_obj_model_file`, `model_file_path`), imports `platform`. Tests: `model_obj_test.odin`.
- `render_frustum`: `render_frustum.odin` (`Frustum`, `frustum_from_matrix`, `frustum_contains_box`). Tests: `render_frustum_test.odin`.
- `run_length`: `run_length.odin` (`Run`, `run_length_encode`, `run_length_decode`). Tests: `run_length_test.odin`.
- `sjson_text`: `sjson_text.odin` (the SJSON writer of the data edits and `sorted_object_keys`). Tests: `sjson_text_test.odin` (the writer's round trip, with its own copy of the game's `json_values_equal` test helper); the round trip of every shipped file needs the game's data file listing and stays in `data_browser_test.odin` (`test_shipped_sjson_files_round_trip`).
- `android_libc`: `android_libc.odin` (the glibc functions bionic lacks, [android.md](android.md)).
