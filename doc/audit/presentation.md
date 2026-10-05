# Audit: the presentation cluster

The presentation cluster (work item 0143) draws and plays the world: chunk meshes and their shaders, the sky, weather and water, machine and player models, belts, fluids, particles, ambient life, sound and the window. 33 files and 8693 lines; 12 files (3221 lines) import no raylib. It never writes simulation or world state (a grep of its files finds no assignment into `World`, the entities or a player), so its debt is how it reads:

- The renderers and the sound read the entity pools directly: 35 pool loops (the simulation audit's count, confirmed), and `^World` is a parameter of 29 procedures. 23 of the 35 loops read only parts every kind shares (section 7).
- Nothing draws only what is in view: `draw_chunks` and `draw_water_chunks` test the frustum, every entity, belt item, pipe, wire, loose item and marker is drawn every frame wherever it is.
- What happened since the last frame is found by diffing counters three times over: `Player_Animation_Memory`, `Sound_Memory` and `Particle_Memory` each keep their own copy of the walked distance, the placed count, the dig or the message count. The simulation's event list (`Simulation_Event`) carries only player events for the UI.
- The GPU and audio resources (8 of the 18 presentation fields of `Frame_State`) are created in `run_game`, replaced in `hot_reload.odin` with three different failure conventions and reset on a session change one field at a time.
- The "no perceivable repetition" rule is one idea written as many local hashes: five integer finalisers and six hash to fraction conversions, plus one stateful scheduler (the ambience clusters).

## 1. What the cluster is

Rule: presentation turns the world, the tick and the render time into pixels and sound; the simulation never reads it back.

- Responsibilities: the block and item atlases, chunk mesh upload and the chunk and water shaders, the day cycle and sky, the weather schedule and look, machine models (vox loading, meshing, motion), per kind entity drawing, belts, fluids, power, loose items, placement ghosts and the target outline, the player's camera, body and hands, particles, ambient life, the sound mixer and triggers, window modes, raylib's log.
- Entries the loop calls per frame: `upload_streamed_meshes`, `session_weather`, `apply_daylight` and then, inside `draw_session_world` (the loop's, see the loop audit), `update_player_presence`, `player_view_camera`, `apply_weather`, `draw_sky`, `draw_chunks`, `draw_entities`, `draw_machine_markers`, `draw_fluid_entities`, `draw_power_entities`, `draw_belts`, `draw_loose_items`, `draw_session_flames`, `draw_fish_shadows`, `draw_water_chunks`, `draw_bird_flocks`, `draw_insect_motes`, `update_particles`, `update_satellite_pass`, `draw_particles`, `draw_player_world_overlay`, `draw_first_person_hands`; after the world `play_frame_sounds`, after the UI `play_ui_sounds` and `update_audio`, between frames `update_display`.
- Start and reload entries: `init_chunk_renderer`, `upload_item_atlas`, `upload_ui_icon_atlas`, `init_belt_renderer`, `init_model_renderer`, `init_particle_renderer`, `init_player_model`, `init_audio` (all from `run_game`); `reload_chunk_shader`, `reload_water_shader`, `replace_chunk_atlas`, `replace_item_atlas`, `replace_machine_models`, `replace_player_model`, `load_mixer_sounds`, `use_machine_models` (from `hot_reload.odin`); `update_atlas_block_tile` (from `serve_texture_editor`).

| File | Lines | Commits | Purpose |
|---|---|---|---|
| `render_chunks.odin` | 437 | 21 | `Chunk_Renderer`, shader loading with retry and the GLES rewrite, mesh upload, daylight and weather uniforms, `draw_chunks` |
| `render_entities.odin` | 378 | 20 | `draw_entities` over 10 pools, inserter arm, drill bit, rocket, bottleneck markers |
| `render_player.odin` | 394 | 20 | pose interpolation, view camera, sprint kick, target outline, placement ghosts, hands, footstep dust |
| `render_fluids.odin` | 216 | 15 | pipes with connections and level, fluid machines, port squares, ghosts |
| `render_belts.odin` | 372 | 8 | belt shape models with a scrolled texture, lane items, splitters, belt ghost |
| `render_atlas.odin` | 256 | 7 | `Atlas_Layout`, block atlas pixels and upload, `load_rgba_texture`, `hash_u64` |
| `render_sky.odin` | 359 | 6 | sky dome, stars, sun, moon, the survey satellite |
| `render_models.odin` | 221 | 5 | `Model_Renderer`, `Model_Frame`, posed and ghost models |
| `render_water.odin` | 167 | 5 | `Water_Renderer`, water shader, underwater fog |
| `render_icons.odin` | 183 | 4 | `Item_Atlas` for items and UI icons, item billboards |
| `render_power.odin` | 104 | 4 | poles, switches, substations, lamps, wires, supply ghost |
| `render_weather.odin` | 297 | 4 | `Weather_Look` per kind, rain and snow, cloud texture |
| `render_day.odin` | 150 | 3 | `Day_Sky`, sun and moon directions, day colours |
| `render_fly_camera.odin` | 64 | 3 | `Fly_Camera`, look turning and fly velocity (called by the player tick) |
| `render_life.odin` | 191 | 3 | draws flocks, insect motes and fish shadows |
| `render_loose_items.odin` | 51 | 3 | loose stacks with fall and bob |
| `render_particles.odin` | 429 | 3 | machine and dig emitters, `Particle_Memory`, capsule descent, satellite pass |
| `render_player_model.odin` | 295 | 3 | limb models, pivots, body and arm transforms |
| `render_flames.odin` | 59 | 2 | torch flames |
| `render_frustum.odin` | 35 | 1 | frustum planes and box test |
| `model_vox.odin` | 282 | 2 | MagicaVoxel parser |
| `model_mesh.odin` | 306 | 2 | greedy voxel mesher, lit and emissive layers, model loading per machine |
| `model_motion.odin` | 285 | 3 | `Machine_Motion`, phase, part transforms, model light tint |
| `texture_generate.odin` | 637 | 4 | procedural ore tiles, the procedural textures file, texture edits file |
| `texture_variation.odin` | 131 | 2 | the Odin mirror of the shader's per block tile variation |
| `particles.odin` | 197 | 1 | `Particle_System` pool, kinds, step, keyed spawning |
| `ambient_life.odin` | 325 | 1 | flocks, bird paths, insect and fish selection, fog fade |
| `audio.odin` | 391 | 4 | sound table, `Audio_Mixer`, effect gap, loop fades |
| `sound_events.odin` | 624 | 4 | `Sound_Memory`, cues, footsteps, hum, ambience clusters, rain |
| `display.odin` | 421 | 6 | window modes, resolutions, platform, scale, GL info |
| `raylib_log.odin` | 101 | 3 | raylib's log into the game log |
| `weather.odin` | 112 | 1 | `weather_at`, the hourly weather schedule |
| `player_animation.odin` | 223 | 4 | walk cadence, limb angles, head bob, place swing |

Verdicts on the edge assigned files:

- `weather.odin` (graph: presentation) is presentation: a pure function of seed and tick that no simulation file calls; its callers are the loop, the renderers, the sounds, the `weather` command and diagnostics. It is game look (the schedule and its weights), not engine.
- `player_animation.odin` (prefix: simulation) is presentation, as the simulation audit says: its callers are `render_player.odin`, `render_player_model.odin`, `sound_events.odin` and the loop. Reassigned, presentation -> simulation drops from 289 to 274 (probe over `tools/code_graph.py` with the file table changed).
- `render_fly_camera.odin` (prefix: presentation) is two things: `turn_fly_camera` and `fly_camera_velocity` are the player tick's look and fly physics (`player.odin` calls them), `fly_camera_to_raylib` is the view.

## 2. State

Rule: nothing here is saved; GPU state lives for the run, memories for a session, everything else for one frame.

The 18 presentation fields of `Frame_State` (loop audit, section 2) and their writers:

| Field | Kind | Writers |
|---|---|---|
| renderer (`Chunk_Renderer`: chunk material, atlas, cloud texture, per chunk meshes, nested `Sky_Renderer` and `Water_Renderer`, 11 uniform locations) | GPU | `run_game`; `upload_streamed_meshes` per frame; `apply_daylight`, `apply_weather`, `apply_fog` set uniforms per frame; `unload_all_chunk_meshes` in `leave_session`; `hot_reload.odin` (shaders, atlas); `serve_texture_editor` (atlas texels, every frame the Textures screen is open) |
| item_atlas, ui_icon_atlas (`Item_Atlas`) | GPU | `run_game`, `hot_reload.odin` |
| belt_renderer (`Belt_Renderer`) | GPU | `run_game`, a content reload (destroy and init); `draw_belts` rewrites the shape meshes' texcoords once per belt speed per frame |
| model_renderer (`Model_Renderer`) | GPU | `run_game`, `hot_reload.odin` (model files, content reload) |
| particle_renderer, player_model | GPU | `run_game`; the player model also `hot_reload.odin` |
| audio (`Audio_Mixer`: table, sounds, music streams, `Mixer_State`, arena) | device and memory | `run_game`, `hot_reload.odin`, `play_frame_sounds`, `play_ui_sounds`, `update_audio` |
| particles (`Particle_System`), particle_memory (`Particle_Memory`) | memory across frames | `update_player_presence` (dust), `update_particles`, `update_satellite_pass`; reset in `enter_session`; the map screen reads particle_memory through a `Screen_Context` pointer |
| player_animation (`Player_Animation_Memory`), sound_memory (`Sound_Memory`) | memory across frames | `update_player_presence`, `play_frame_sounds`; reset in `enter_session` |
| sprint_kick, render_camera | per frame, kept one frame | `draw_session_world`; render_camera is read by the touch overlay's aim and `mining_ring_centre` |
| window_settings, monitor_size, window_scale, platform | window | `run_game`, `update_display` |

- Derived per frame and never stored: `Day_Sky`, `Weather`, `Weather_Look`, `Model_Frame`, the interpolated `Player_Pose`, `Life_Frame`, `Sound_Frame`, the emitters and hum sources, every model's phase (`clock_pose` from tick plus alpha), the belt scroll and the loose item bob.
- Anchors derived from the mesher and kept per chunk: `Chunk_Render` holds the chunk's flames, ground covers (insects) and fish cells beside its meshes, filled by `apply_chunk_mesh` from `Chunk_Mesh_Data`.
- State the repetition rule keeps: only the sound's `Ambience_Cluster_Memory`, `Hum_Drift_Memory` and the footstep count (pitch). Machine phases, flames, textures, birds, insects and fish vary by a hash of position, seed and tick and keep nothing.
- The four session memories are reset one by one in `enter_session` (`loop.odin:1002`).

## 3. Coupling

Rule: reading the mesh, the light and the camera's surroundings is essential; walking entity pools to learn what each machine looks like is reach through.

presentation -> simulation (289, probe over `tools/code_graph.py`'s parser): by file `render_entities.odin` 56, `render_fluids.odin` 48, `render_belts.odin` 47, `render_player.odin` 40, `sound_events.odin` 38, `render_particles.odin` 19, `render_models.odin` 13, `render_power.odin` 13.

- Per entity, through the 35 loops: `Entity_Common` 16 (origin, size, rotation, machine), `Machine_Registry` 30 and `Machine` 14 (prototype, model, motion), `machine_marker_colour` 15 and `marker_means_working` 10 (the state enums to "working"), the phase procedures (`inserter_arm_fraction`, `drill_progress_fraction`, `launch_pad_progress`), held items (`stack_is_empty` 5 on the inserter's hand and the crate's slot), fluid port buffers, the kind structs by name.
- Networks: belt lines and lanes (`Belt_Line`, `Belt_Lane`, `line_block_belt`), electric nodes and wires (`draw_wires`), and `pipe_connects_through`, which runs `entity_at` on all six faces of every pipe every frame.
- The player (40): pose and look, `Mining_State`, `Placement` 9 through `placement_for_player`, which the renderer runs every frame to draw the ghost (the placement rules are simulation code).
- Sound (38): `placed_total` over the statistics, the walked distance, the dig, the launching pads, the working machines, the quest messages.
- A per frame view (machine id, cell, size, rotation, working, marker colour, phase, held item, port fluids) would remove about 100 of the 289: `Entity_Common`, the marker procedures, the phase procedures, the kind structs and `Entities` in the draw files (probe: 103 references to those names, excluding the 8 `placed_total` field matches), plus the per entity lookups of `Machine_Registry`. The belts' 47 and the player's 40 need their own views (lane items, ghost).

presentation -> world (254): the five common types 116 (`World` 31, `World_Coordinate` 28, `Block_Registry` 27, `Block_Id` 17, `Direction` 13); generation hashes and `smoothstep` 24 (ambient life, particles, sky); `render_chunks.odin` 29, mostly the mesh handoff (`Mesh_Part`, `Chunk_Mesh_Data`, `take_current_meshes`); light 10 (`world_get_light`, `light_level`); the camera's surroundings in `render_player.odin` 37 (raycast for the third person camera, block bounds, water); `sample_column`, `terrain_height` and `terrain_temperature` for flocks, ambience and rain. The day cycle is presentation's own (`render_day.odin`).

presentation -> content (95): infrastructure (`log_printf` 16, `text` 15, `read_data_file` 4), `Item_Registry` 14 and `Item_Id` 7 (icons and cube colours), `Settings` 12. Blocks and machines are counted under world and simulation.

Into the cluster:

- loop -> presentation 156: `loop.odin` 155, the frame composition of `draw_session_world`, `session_sound_frame`, `render_facts` and the init and destroy lines of `run_game`.
- ui -> presentation 83: `ui_texture_editor.odin` 48 (procedural texture parameters and tiles), `touch_overlay.odin` 12 and `input_raylib.odin` 3 (render size, pointer mapping), `ui_screens.odin` 9 (window modes), `ui_draw.odin` 7 (`Atlas_Layout`, `load_rgba_texture`), `ui_map.odin` 3 (`Satellite_Pass`, `Particle_Memory`).
- simulation -> presentation 40: `diagnostics.odin` 23 (the loop's), `machine.odin` 6 (`validate_machine_models` meshes every model at content load; `Machine` carries a `Machine_Motion`), `player.odin` 6 (`Fly_Camera`), `block_centre` 3 and `line_block_belt` 2 (helpers defined here, used by `loose_item.odin`, `belt_placement.odin`, `belt_movement.odin`).
- content -> presentation 35: `hot_reload.odin` 14 (the loop's), `data_watch.odin` 11 (directory and extension constants), `configuration.odin` 4 (resolution and frame cap limits), `command.odin` 2 (weather words).
- world -> presentation 16: `hash_u64` 4 (the world audit moves it), the mesher's `Atlas_Layout`, `atlas_tile_index` and `face_tile_variation` 12.

Cycles: 31 of the 32 graph assigned files are in the 185 file strongly connected component; only `render_frustum.odin` is outside. Leaf files join it through one helper each (`model_vox.odin` through join_save_path (`join_path` since 0145), `render_day.odin` through `smoothstep`, `render_fly_camera.odin` through `Input_Frame`). The back edges listed above (after the loop audit takes `diagnostics.odin` and `hot_reload.odin`: 17 from simulation, 21 from content, 16 from world) are what keeps presentation from sitting above world, simulation and content.

## 4. Abstraction gaps

- Per kind draw loops: 35 pool loops in 6 files; each draw computes "working" from the state again and none culls. `draw_entities`, `draw_machine_markers` and `working_hum_sources` walk the same five pools with the same rule.
- "Working" has three definitions: the marker colours (`production_statistics.odin`, five kinds), `core_sample_drill_is_working` and `launch_pad_is_working` in `render_entities.odin`, and the emitters' own state tests (`furnace.state == .Burning` in `append_machine_emitters`' helpers).
- Culling per file: the frustum is built three times a frame (`draw_chunks`, `draw_water_chunks`, `water_meshes_in_view`); flocks, insects and fish cull by distance with their own tests (`chunk_distance_squared`, `fog_fade`); entities, belt items, pipes, wires, loose items, markers and particles are not culled.
- Interpolation: models follow tick plus alpha (`motion_phase`), loose items fall by alpha, the belt surface scrolls by alpha (`belt_scroll_offset`), but belt items stand at their tick position (`draw_belt_line_items` passes no alpha to `belt_item_point`), so above 60 frames per second the items step while the surface under them glides (read in the code, not seen).
- No cue seam: the frame learns events by diffing. Footstep cadence and place swing are detected in both `advance_player_animation_memory` and `advance_sound_memory`; the dig in both Mining_Memory and Mining_Sound_Memory; new quest messages by discovery_since and orbital_survey_since, each with its own count; shipments and launches by counts. Since 0162 one detector (`detect_cues`, `cues.odin`) does all of it once a frame.
- Environment at the eye sampled twice a frame: `draw_session_weather` and `set_ambience_targets` each compute `terrain_temperature` and the open sky; the biome under the player is sampled by `set_ambience_targets` and `draw_biome_banner` every frame.
- Sound by name every frame: `set_loop_target` and `play_effect` search the table linearly (`find_sound`), `ambience_variant_count` formats and searches ids until one is missing on every frame the ambience plays, `footstep_sound_id` and `mining_hit_sound_id` format strings per cue.
- Bundles: 29 procedures take `world: ^World`, 15 take `machines: Machine_Registry` with `models: Model_Renderer`, 20 take a `Model_Frame`, 13 a camera. `Model_Frame` carries `^World` only for `world_get_light` (in `draw_posed_model` and `player_body_light`). `draw_session_world` builds `Item_Billboards` three times and `frame_simulation_content` twice.
- Features as branches: `draw_fluid_machine` picks top colours by `Machine_Kind`, `fluid_machine_emitter` switches over four kinds, the alloy furnace's sparks test the recipe maker, `draw_pole` branches on switch and substation; the fallback colours per kind are Odin tables (`fluid_machine_colors`, `crafting_machine_colors`), so a new machine's look is a code change even with a model.
- Shader and GPU lifetime: 8 resources created in `run_game` with 8 `defer` lines; `hot_reload.odin` replaces them through procedures that report failure as a bool (`reload_chunk_shader`), a problem string (`replace_machine_models`), a fallback to boxes (`use_machine_models`) or not at all (`replace_item_atlas`). `destroy_chunk_renderer` must free the water material before the chunk material, since they share the atlas. Every per frame uniform is set on both materials by hand (`apply_daylight` 6 calls, `apply_weather` 10).
- The shaders have no shared source: `light_curve`, the variation hash and its brightness are written in `data/shaders/chunk.fs` and `data/shaders/water.fs`, and mirrored in Odin by `texture_variation_hash` and `light_curve` (`model_motion.odin`); no test compares them.
- The repetition rule is a pattern, not a mechanism: finalisers `hash_u64` (splitmix64), `sound_hash`, the mix inside `footstep_pitch`, and the lowbias32 in both `motion_phase_offset` and `texture_variation_hash`; fraction conversions `hash_to_unit`, `hash_unit` (in `render_sky.odin`, used by `particles.odin`), `hash_fraction`, `hash_share`, and inline ones in `footstep_pitch` and `weather_peak_for_hash`; cell to key packing in `flame_salt`, `life_cell_hash` and `emitter_random_key`. The tests check it per use (`test_each_origin_has_its_own_phase_offset`, `test_texture_variation_hash_differs_between_neighbours`, `test_ambience_variant_never_repeats_the_last`).
- A defect by the hand-back rule: `write_texture_edits_file` writes the edits file in place with `os.write_entire_file`, not through `write_file_replacing`.
- Misplaced helpers: `block_centre` (`render_player.odin`) and `box_centre` (`render_entities.odin`) are coordinate helpers; `line_block_belt` serves the belt tick; `color_to_vector3` lives in `render_chunks.odin`.

## 5. Refactors, ranked by gain per risk

1. Texture edits through `write_file_replacing`. Files: `texture_generate.odin`. Guards: `texture_generate_test.odin`. Gain: the hand-back rule holds; a crash mid write keeps the old edits. Risk: none. Prerequisite: no.
2. Pure moves and the cluster table. `player_animation.odin` to presentation in `tools/code_graph.py`; `turn_fly_camera` and `fly_camera_velocity` into `player.odin`; `block_centre`, `box_centre` beside `World_Coordinate` (`world_chunk.odin`); `line_block_belt` into `belt.odin`; `hash_unit` beside `hash_u64` (where the world audit's refactor 1 puts it). Files: those named, `render_sky.odin`, `particles.odin`. Guards: `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Gain: presentation -> simulation 289 to 274, simulation -> presentation 40 to 33, the graph shows the real seam. Risk: none. Prerequisite: yes.
3. One cue detector. One memory and one pure step per frame that turns the counters into cues (footstep, place, break, dig quarter, launch, landing, shipment, discovery, survey); `advance_player_animation_memory`, `advance_sound_memory` and the particle memory's counts read its output, and the four `enter_session` resets become one. Files: `player_animation.odin`, `sound_events.odin`, `render_particles.odin`, `render_player.odin`, `loop.odin`. Guards: `test_step_detector_fires_once_per_half_cycle`, `test_footstep_fires_once_per_half_cycle`, `test_counter_cues`, `test_cheat_speed_footsteps_keep_the_normal_rate`, `test_place_swing_fires_once_per_growth`, `test_break_puff_fires_once`, `test_shipment_starts_a_descent`. Gain: two step detectors, two message scans and two dig memories become one each, about 60 lines. Risk: low (all pure, all tested). Prerequisite: yes, the cue list is what a game plugin would emit per tick instead of the frame diffing counters.
4. The per frame machine view (the simulation audit's refactor 5), sized here: one list of (machine id, origin, size, rotation, working, marker colour, phase, held item, port fluids) built once, with the working rule for core sample drills and launch pads moved beside the marker colours. Readers: `draw_entities`, `draw_machine_markers`, `working_hum_sources`, `launching_pad_count`, `capsule_landing_point`, the port loops of `draw_fluid_entities`, the lamps. Guards: `test_marker_colour_of_every_state`, `test_nearest_working_machine_and_its_volume`, `test_emitters_for_frame_from_the_world`, a new test of the list; a playtest of every machine's model and markers. Gain: 23 of the 35 pool loops, one working rule, about 100 presentation -> simulation references. Risk: low to medium (draw order, untested draws). Prerequisite: yes.
5. Sounds by index. Resolve at load the footstep per block material, the hum per family, the ambience per biome with its variant count and day flag, the mining hit per tier; the frame plays indices. Files: `audio.odin`, `sound_events.odin`. Guards: `audio_test.odin`, `test_shipped_ambience_clusters`, `test_biome_ambience_mapping`, `test_mining_hit_per_tool_tier`. Gain: no string formatting or linear search per frame; sounds by id across a boundary. Risk: low; a sounds reload must rebuild the indices. Prerequisite: yes.
6. The frame's environment sampled once: biome, temperature and open sky at the eye into one frame fact that the weather draw, the rain and ambience and the biome banner read. Files: `loop.odin`, `sound_events.odin`, `biome_banner.odin`. Guards: `test_rain_volume`, `test_biome_ambience_mapping`; a playtest of rain under a roof and the biome banner. Gain: two generator samples and a light read less per frame, one fewer `^Generator` in `Sound_Frame`. Risk: low. Prerequisite: no.
7. A shared shader prelude and a mirror test. `load_shader_pair` prepends one common source (light curve, variation hash and brightness, cell lookup) to both fragment shaders; a test runs `texture_variation_hash` and `light_curve` on fixed inputs and checks the constants appear in the prelude. Files: `render_chunks.odin`, `data/shaders/chunk.fs`, `data/shaders/water.fs`, `shader_source_test.odin`, `texture_variation_test.odin`. Guards: `test_shipped_shaders_have_no_bare_integer_literals`, the GLES rewrite tests. Gain: three copies of each function to one plus a checked mirror. Risk: medium: the `#version` line must stay first for `shader_source_for_gles`, and Gladio on the phone needs a playtest. Prerequisite: no.
8. Cull by view. Build the frustum once per frame and pass it; bucket the per frame view (4) and the belt lines by chunk, and skip chunks outside the frustum or beyond the fog end. Files: `render_chunks.odin`, `render_water.odin`, `diagnostics.odin`, `render_entities.odin`, `render_belts.odin`, `render_fluids.odin`, `render_power.odin`, `render_loose_items.odin`. Guards: `render_frustum_test.odin`; a playtest turning in a large factory. Gain: draw work follows the view instead of the factory (not measured here; benchmarks wait for their window). Risk: medium (a wrong box pops machines in and out). Prerequisite: no; after 4.
9. One presentation resource group: the 8 GPU and audio resources in one struct with one start, one destroy in a fixed order and one reload procedure per data category, each keeping the old resource and returning a problem string. Files: `loop.odin`, `hot_reload.odin`, `render_chunks.odin`, `render_icons.odin`, `render_models.odin`, `render_player_model.odin`, `audio.odin`. Guards: `data_reload_test.odin` for the content path; a playtest editing a shader, a model, a texture and a sound with the watcher on. Gain: the loop audit's presentation group (its refactor 5) with a single failure contract; 16 lines of `run_game` and the 12 reload call lines of `hot_reload.odin` in one place. Risk: medium (the shared atlas destroy order). Prerequisite: yes, it is the engine's renderer.
10. Draw procedures without `^World`: the light cell's value in the per frame view, pipe connection masks and wire anchors computed on topology change (the simulation audit's refactor 6 seam), the ghost from a placement the tick already computed. Files: `render_models.odin`, `render_fluids.odin`, `render_power.odin`, `render_player.odin`, `entity_placement.odin`. Guards: `render_ghost_test.odin`, `fluid_test.odin`; a playtest. Gain: most of the 29 `^World` parameters, the per frame `entity_at` calls of pipes. Risk: medium. Prerequisite: yes, for a renderer that reads only a description.

## 6. Engine or game

Rule: the engine owns the GPU, the device and the generic machinery; the game decides what each thing looks and sounds like.

- Engine: `render_atlas.odin` (layout, upload, `load_rgba_texture`), mesh upload (`upload_mesh_part`, `clone_for_raylib`), `load_shader_pair` and `shader_source_for_gles`, the chunk and water shaders with their uniforms, `render_frustum.odin`, the view half of `render_fly_camera.odin`, `display.odin`, `raylib_log.odin`, the mixer (`Audio_Mixer`, `Mixer_State`, the gap and fade rules), `particles.odin`, `model_vox.odin`, `model_mesh.odin`, the motion shapes of `model_motion.odin`, `render_models.odin`, the sky dome mechanics, item billboards, `texture_variation.odin` (it mirrors the engine's shader).
- Game: the per kind draws (`render_entities.odin`, `render_fluids.odin`, `render_power.odin`, the belt look), the emitter choices, `sound_events.odin`, `ambient_life.odin` and `render_life.odin`, `weather.odin` and the weather look tables, the day colours, `player_animation.odin`, placement ghosts and the target outline, `texture_generate.odin` (a content tool for ore tiles).
- Both today: `Model_Frame` (engine light and game tick), `Chunk_Render` (engine meshes beside game anchors: flames, covers, fish), `Machine` (a game prototype carrying the model name and `Machine_Motion`), `Particle_Memory` (engine pool bookkeeping beside the capsule descent and the satellite pass).

What a game side plugin would hand the engine per frame:

- Model instances: machine or model id, transform (origin, size, rotation), motion phase, working flag and glow. The engine applies its own light per instance (today `model_light_cell` and `world_get_light`).
- Primitives for what has no model: the fallback boxes, the inserter arm, the drill bit, the rocket, arrows, markers, pipes, wires. Today 67 raylib draw calls of 12 kinds (`rl.DrawCubeV` 19, `rl.DrawCubeWiresV` 13, `rl.DrawBillboardRec` 7, `rl.DrawLine3D` 6, and 8 more); a description needs about these 12 shapes.
- Item quads: item id and position (belt lanes, held items, loose stacks).
- Particle spawns: `Emitter` values and bursts, already plain data.
- Sounds: effect ids with volume and pitch, loop targets; already by id through `play_effect` and `set_loop_target`.
- Scene parameters: `Day_Sky`, `Weather_Look`, precipitation and count, fog; all plain values today.
- The engine needs from content: models by machine id (vox files), block and item textures, the procedural texture file, sounds by id, shaders.

Could the current renderers become that description without a rewrite: mostly. The draws are already pure in their inputs (an entity struct, its `Machine`, a `Model_Frame`) and call raylib only at the leaves; `Emitter`, `Hum_Source`, `Model_Pose`, `Belt_Surface_Pose` and `Ghost_Chevron` are values. The work is replacing the 67 draw calls with appends to a list the engine executes (the shape the UI toolkit already has with `Draw_Command`), taking the pool reads out through refactor 4, and moving the light lookup to the engine. The cue diffing (refactor 3) would move to the game side's tick output.

## 7. Entity component lens

Rule: what every kind has (a model at a cell with a rotation, a phase, a working flag, a held item) belongs in the view; the geometry of an arm, a bit or a rocket stays per kind.

The 35 pool loops by what they need:

| Loop | Pools | Needs |
|---|---|---|
| `draw_entities` | chests, capsules, furnaces, crates, assemblers, labs, core sample drills | shared: common, working, a state colour for the fallback box top |
| `draw_entities` | inserters, drills, launch pads | kind: arm geometry and hand, bit angle and drop arrow, rocket height and lift |
| `draw_machine_markers` | furnaces, assemblers, drills, labs, fluid machines | shared: common, marker colour |
| `working_hum_sources`, `launching_pad_count` | the same five, launch pads | shared: common, working, hum family, state |
| `capsule_landing_point` | capsules | shared: common |
| `draw_fluid_entities` | assemblers, drills, launch pads (ports) | shared: port buffers |
| `draw_fluid_entities` | fluid machines | shared plus a per kind table (top colour, arrow) |
| `draw_fluid_entities` | pipes | kind: connections and level |
| `append_machine_emitters` | furnaces, fluid machines, assemblers | shared plus a per kind table (which state emits which kind) |
| `append_machine_emitters` | launch pads | kind: exhaust follows the rocket |
| `draw_power_entities` | lamps / poles | shared (lit) / kind (switch, substation) |
| `draw_belt_surfaces` | belts, splitters | kind: shape, speed tier, half cells |

- 23 loops read shared parts only, 4 read shared parts plus a per kind table that could be data in `machines.sjson`, 8 need kind specific fields.
- The components a view would carry: placement (all 16 kinds), working and marker colour (the five marker kinds plus core sample drills, launch pads, lamps, switches), phase (inserter arm, drill, launch pad; the rest run on the clock), held item (inserter), port fluids (four kinds).
- An ECS would not change this cluster's cost: the per kind geometry stays, and the gain (one loop over a view instead of 35 over pools) is available from refactor 4 without changing the pools; the simulation audit's recommendation against an ECS holds here.

## 8. Tests

Rule: the pure halves are tested, the draws and the GPU lifetime are not.

- Covered (27 test files, 186 tests): the shader literal rule and the GLES rewrite (`shader_source_test.odin`, 6), atlases and icons (11), procedural textures and periodicity (10), tile variation (9), vox parsing (7), model meshing (11), motion and model light (15), the frustum (4), the fly camera (3), day, sky and weather look (19), the weather schedule (8), particles and emitters (14), ambient life (6), player animation (10), the player model and camera helpers (8), ghosts (4), water (3), the mixer (7), sound cues and clusters (18), display (12), raylib's log (1).
- Uncovered: every draw procedure (`draw_entities`, `draw_belts`, `draw_fluid_entities`, `draw_power_entities`, `draw_loose_items`, `draw_session_world`'s order); `working_hum_sources` and observe_sounds (`observe_cue_counters` since 0162) against a world; `belt_scroll_offset`, `loose_item_draw_centre`, `rocket_ascent`, `inserter_arm_end`; `apply_chunk_mesh` and mesh upload; `load_shader_pair`'s retry; every reload in `hot_reload.odin` of a GPU resource; `update_display` applying a change; `update_audio` with a device.
- Pinning implementation: `test_step_detector_fires_once_per_half_cycle` and `test_footstep_fires_once_per_half_cycle` test the same detector written twice; `texture_variation_test.odin` tests the Odin mirror, not the shader it mirrors; `model_mesh_test.odin` asserts exact vertex counts of the greedy merge (`test_a_bar_merges_its_long_faces`).
- Testable headless after the refactors: with refactor 4 the view is a list a test builds from a world and compares; with a draw description (section 6) the draw order and the per kind shapes are a list a test reads, as `ui_data_browser_test.odin` reads the UI's draw list; with refactor 3 the cues are one pure step.

## Claims to spot check

1. Only chunks and water test the frustum: `draw_chunks` (`render_chunks.odin:398`) and `draw_water_chunks` (`render_water.odin:142`); `draw_entities` (`render_entities.odin:202`) draws every live entry of 10 pools, and the frustum is built three times a frame (`render_chunks.odin:400`, `render_water.odin:144`, `diagnostics.odin:232`).
2. The footstep cadence and the place count are detected twice: `advance_player_animation_memory` (`player_animation.odin:185`) and `advance_sound_memory` (`sound_events.odin:407`) each keep distance_millimetres, cadence_millimetres and placed_total and call `advance_cadence_millimetres`.
3. `Model_Frame` (`render_models.odin:32`) carries `^World` only for `world_get_light`, at `render_models.odin:200` and `render_player.odin:240`.
4. `write_texture_edits_file` (`texture_generate.odin:628`) writes in place with `os.write_entire_file` (line 633), not through `write_file_replacing` (`data_export.odin:148`).
5. The variation hash is written three times (`texture_variation.odin:28`, `data/shaders/chunk.fs` line 112, `data/shaders/water.fs` line 101) and the light curve three times (`data/shaders/chunk.fs` line 89, `data/shaders/water.fs` line 66, `model_motion.odin:254`), with no test comparing the shaders to Odin.
