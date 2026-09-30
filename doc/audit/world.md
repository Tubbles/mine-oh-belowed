# Audit: the world cluster

The world cluster (work item 0143) is the block store and everything that follows a block: chunks, light, water, meshing, streaming with its workers, the raycast, world generation and the save codec. 33 files and 9551 lines, plus 4 edge assigned files (1323 lines). Its core is already shaped like an engine; the debt is what sits on and around it:

- `World` (`world_chunk.odin:31`) has 27 fields; 13 belong to the simulation or to content (entities, leaf decay, statistics, research, shipments, contracts, venture credit, catalogue orders and five prospecting records) and sit there so the tick procedures reach them through one pointer.
- The storage files (chunk, block, light, water, mesh, raycast, serialize, streaming, `block_shape.odin`) have 108 references out of themselves; the light files have none. What ties them to the game is a short list: `Box` in `player_collision.odin` (25), the entity cell map read by the raycast and by water (7), the game types on `World` with their destroy calls (15), streaming calling generation and registering its records (21), and the mesher reading the texture atlas (12).
- There is no cell change seam: a block edit reaches light and water through `block_changes` and meshing through a dirty flag, an entity light through a direct call, and an entity leaving a cell reaches nothing, so water does not flow into a cell a machine was picked up from (section 4).
- The save codec is type driven inside a struct but positional at the top: `write_world_state` writes 17 lists in a fixed order, new tables go through `write_later_tables`, and `save_state.odin` names every entity pool in four places.
- Chunk arrival is one procedure with seven side effects (`insert_generated_chunk`), the frame side write the loop audit found (its section 3); it is also the place a chunk load notification for a game plugin would go.

## 1. What the cluster is

Rule: the world owns blocks and what is derived from blocks; generation is a pure function of seed and coordinate; the save codec turns state into files and back.

- Responsibilities: block storage in 32 cubed chunks (`Chunk`, a map of chunk pointers), the block registry and shapes, sky and coloured block light, cellular water, greedy meshing on workers, loading and unloading around the camera, the raycast, chunk bytes (palette plus runs), terrain, biomes, caves, features, trees, veins, starter veins, spawn, and the save files with the content remap.
- Block get and set: `world_get_block`, `world_set_block` (records a `Block_Change`, marks the chunk and its border neighbours dirty), `chunk_get_block`, `world_get_light`.
- Chunks: `world_create_chunk`, `insert_generated_chunk`, `insert_saved_chunk`, `load_chunk_now` (tests and tools), `unload_distant_chunks`, `store_modified_chunk`, `destroy_world`.
- Streaming: `start_chunk_streaming`, `update_chunk_streaming` (main thread, once per frame after the ticks), `take_current_meshes` (called by `render_chunks.odin`), `stop_chunk_streaming`; workers run `run_chunk_job`.
- Generation: `load_generator`, `make_generator`, `generate_chunk`, `generate_saved_chunk`, `find_spawn`, `sample_column`, `region_veins`, `column_veins`.
- Light and water scheduling: `tick_world` (`simulation_world.odin:37`, in the loop cluster's file) runs `apply_block_changes`, `run_water_updates`, `run_leaf_decay`, `seed_arrived_chunks`, `propagate_light`; `set_entity_light` from the lamps.
- Save and load: `save_world`, `load_world`, `make_simulation_from_save`, `decode_entities` (also the content reload's route), `list_saves`, `delete_save`, `simulation_state_hash`.

| File | Lines | Commits | Purpose |
|---|---|---|---|
| `world_chunk.odin` | 268 | 15 | `Chunk`, `World`, coordinates, `Direction`, get and set, dirty marking |
| `world_block.odin` | 485 | 14 | `Block_Registry`, block definitions, shapes and variants, block queries |
| `block_shape.odin` | 251 | 1 | collision boxes, target boxes and quads of slabs, stairs, posts, crosses |
| `world_light.odin`, `world_light_sky.odin` | 512 | 7 | light nibbles, removal and addition queues, border seeding, sky light of a chunk |
| `world_water.odin` | 157 | 3 | `Water_Flow`, scheduling, flow rules |
| `world_mesh.odin`, `world_mesh_light.odin`, `world_mesh_border.odin` | 807 | 20 | greedy mesher, vertex light and occlusion, the 34 cubed border copy |
| `world_raycast.odin` | 127 | 4 | voxel walk, shaped block hits, entity hits |
| `world_serialize.odin` | 129 | 5 | `Byte_Reader`, chunk palette and runs |
| `world_streaming.odin` | 506 | 7 | job queue, workers, insert, unload, mesh revisions |
| `world_vein.odin` | 415 | 12 | `World_Settings`, `Vein_Content`, the vein registry, outcrops, added veins |
| `world_explored.odin` | 183 | 1 | explored columns and their surfaces for the map |
| `world_debug_edit.odin`, `world_debug_terrain.odin` | 159 | 5 | the F-key dig and the flat debug terrain |
| `generation.odin`, `generation_seed.odin` | 195 | 16 | `Generator`, purpose seeds, hashes |
| `generation_terrain.odin`, `generation_caves.odin` | 700 | 10 | height, climate, column grid, cave grid, crate sites |
| `generation_biome.odin`, `generation_trees.odin`, `generation_features.odin` | 940 | 15 | biome and species tables, trees, boulders, ground cover |
| `generation_veins.odin`, `generation_vein_tables.odin`, `generation_starter_veins.odin` | 685 | 13 | regions, vein placement and outcrops, the vein file, starter veins |
| `generation_spawn.odin`, `generation_chunk.odin` | 377 | 11 | spawn search; the per chunk step sequence |
| `save_binary.odin` | 634 | 3 | the type driven codec (schemas, enums by name, lists) |
| `save_state.odin` | 599 | 9 | entities.bin body, rebuild after load, `simulation_state_hash` |
| `save_remap.odin` | 666 | 2 | content tables and the remap of every id |
| `save_world.odin`, `save_list.odin` | 756 | 17 | world.sjson, region files, staging and swap, the save list |

Verdicts on edge assigned files:

- `prospecting.odin` (graph: world) is simulation: `apply_item_use`, `update_magnetometer`, `tick_core_sample_drills` and the `Core_Sample_Drill` entity run in the tick; its world edges are block and vein reads. Its five record types are why `World` holds five prospecting lists.
- `tree_felling.odin` (graph: world) is simulation: felling and leaf decay are game rules with item drops (`spill_stack`, `block_drop`); only its bounded queue is shaped like the world's water queue (section 4).
- `landing_pad.odin` (graph: world) is split: `apply_landing_pad` and `close_landing_pad_columns` are generation steps, `place_capsule` is simulation set-up called from `make_simulation`.
- `benchmark_factory.odin` (graph: world) is the game side test harness the loop audit named; its 20 world -> loop references are `simulation_tick` and `Simulation_Content`.

## 2. State

Rule: storage fields are written by the world's own procedures; the rest of `World` is simulation state parked there.

`World` (`world_chunk.odin:31`) by owner:

| Group | Fields | Count | Writers besides the owner files |
|---|---|---|---|
| storage | chunks, saved_chunks, block_changes, settings | 4 | settings: `session.odin`, `save_world.odin`, `data_reload.odin`, the benchmark |
| light | lighting, entity_lights | 2 | `power_machine.odin` (`sync_entity_lights`), `save_state.odin` |
| water | water | 1 | `save_state.odin` |
| generation records | veins, vein_indices, column_veins, outcrop_cells, spent_outcrops, crate_sites, explored | 7 | `schematic.odin` (crate_sites), `save_state.odin`, the drills through `queue_spent_outcrops` |
| simulation | entities, leaf_decay, statistics, research, shipments | 5 | `world.entities` is named 225 times in 44 files, `world.statistics` 81 times in 27 |
| venture | contracts, venture_credit, catalogue_orders | 3 | `venture.odin`, `ui_contracts.odin`, `command.odin` |
| prospecting | assayed_veins, magnetometer_readings, core_samples, seismic_shots, seismic_outlines | 5 | `prospecting.odin`, `venture.odin`, `save_remap.odin` |

- `World_Settings` (`world_vein.odin:8`): the seed plus four game rules (veins_infinite, vein_richness_percent, research_cost_percent, byproducts_lenient) read by drills, assemblers, power and the venture; it is defined in the vein file and built by `world_settings_from_file` in a UI file (ui audit, refactor 1).
- `Chunk` (`world_chunk.odin:15`): coordinate, blocks, light, dirty, modified. It holds no entity reference; entities keep their cells in `Entities.cells`, a world wide map, and loose items are in `Loose_Items`, in no chunk.
- The block registry is not on `World`: 78 procedure signatures take `world: ^World, registry: Block_Registry`, and `Generator` and `Worker_Shared` each keep their own copy.
- `Chunk_Streaming` (`world_streaming.odin:81`) lives on `Session`: the shared worker block (queue, generator pointer, registry, atlas layout, allocator), threads, the load offsets, generating and mesh revision maps, pending count and the unloaded list the renderer drains.
- `Generator` (`generation.odin:17`): seed and purpose seeds, registry, generation blocks, biomes, species, tree blocks, sapling item, vein tables, densities, the landing pad site, richness. Read only after `make_generator`, shared by workers; `Simulation_Content.generator` hands it to the simulation (tree felling, the orbital survey).
- Saved, and from where: world.sjson from `Simulation_State` and `World_Settings` (`make_world_file`); regions from `saved_chunks` and loaded modified chunks (`collect_saved_chunks`); entities.bin from `write_simulation_state`: the world lists, the 16 pools, belt items, network fluids, statistics, research, shipments, contracts, credit, orders, unlocks, quests, players, then the later tables (loose items, leaf decay). Light, meshes, the entity cell map, networks and vein indices are rebuilt (`rebuild_loaded_world`).

## 3. Coupling

Rule: the simulation reading blocks is essential; the world knowing entities, items or quests is reach through that a package split must remove.

world -> simulation (213), by source: `save_state.odin` 84 and `save_remap.odin` 39 (the pools and records they encode), `block_shape.odin` 24 (`Box` 23), the benchmark 22, `prospecting.odin` 12, `landing_pad.odin` 8, `tree_felling.odin` 6, `world_chunk.odin` 6 (the field types and their destroy calls), `world_raycast.odin` 6 (`Box`, `entity_at`), `world_water.odin` 3 (`pool_get` for the hydro turbine), `world_vein.odin` 2.

world -> content (135): `save_remap.odin` 45 (registries it remaps, plus `activate_quest`, `refresh_available_recipes`, `mark_everything_unlocked`: game rules run by the remap; 9 are the local `in_range` matching a quest procedure), the benchmark 23, `save_state.odin` 15 (quest message keys, `Schematic_Crate`, `venture_state_is_consistent`), infrastructure (`log_printf` 10, `read_logged_data_file` 4, the run length codec 5, paths 2, local zone 2), item lookups in `tree_felling.odin` and `world_vein.odin` 14, `register_crate_sites` from streaming.

world -> loop 52 (`Simulation_Content` 26, `Simulation_State` 18; the loop audit's refactor 1 moves them), world -> presentation 16 (`hash_u64` 4 from generation and the debug edit, the atlas and tile variation 12 from the mesher and streaming), world -> ui 122 (the `column` noise, ui audit).

Edges in:

- simulation -> world 497: 302 are five types (`World_Coordinate` 113, `World` 107, `Block_Registry` 52, `Direction` 19, `Block_Id` 11); block and light reads (`world_get_block` 26, `light_level` 12, `block_is_solid` 9, `block_shape` 6, `block_water_level` 4); writes are `world_set_block` 4; veins 26 (`Vein` 10, `Vein_Id` 7, `Vein_Content` 6, `registered_vein` 3); `Core_Sample_Drill` 12 is the misassigned prospecting file. Field reach does not show in the graph: the tick procedures take `^World` to get `world.entities`.
- presentation -> world 254: the same five types 116, generation hashes and `smoothstep` 23 (the ambient life and particles reuse them), `render_player.odin` 37 (collision, light, raycast), `render_chunks.odin` 29 (meshes, streaming), `sound_events.odin` 22.
- content -> world 200: `data_reload.odin` 41 (the content reload remaps the world), `item.odin` 35 (block ids in item definitions), `developer.odin` 27, `venture.odin` 26 (the orbital survey reads `veins_near_box` on the generator), `command.odin` 20; join_save_path (`join_path` since 0145), a general path join in `save_world.odin`, accounts for 21; it is used in 11 files outside the cluster.
- ui -> world 145 and loop -> world 101: in the ui and loop audits.
- Cycles: world is in a mutual pair with every cluster. Without noise, world <-> simulation rests on the save codec, `Box`, the entity cell map and the fields on `World`.

For the storage (chunk, block, light, water, mesh, raycast, serialize, streaming, `block_shape.odin`) to be a package below the simulation, these of its 108 outgoing references must go:

- `Box` 25 and `rotate_direction` 1: move into the world.
- The 12 game types of the 13 game fields on `World` and their 3 destroy calls (15): off `World` (refactor 3).
- Raycast and water reading `Entities` (7): a cell occupant index the world owns (refactor 5).
- Streaming calling generation (`Generator`, `generate_chunk`, `generate_saved_chunk`, `Generated_Chunk`, 9) and registering records (`register_column_veins`, `register_outcrop_cells`, `register_crate_sites`, `mark_column_explored`, `refresh_unloading_surfaces`, `apply_added_veins_to_chunk` and their record types, 12): a generation procedure value and an arrival list (refactor 4).
- The mesher's `Atlas_Layout`, `atlas_tile_index`, `atlas_tile_origin`, `face_tile_variation` (12): the mesher goes with the renderer, or the atlas layout moves down.
- `world_block.odin`'s loading helpers (8) and `Content_Remap` on `Byte_Reader` (1): a leaf infrastructure package below both; the remap pointer moves to the codec's own reader.

## 4. Abstraction gaps

- No cell change seam. `world_set_block` appends to `block_changes`, which `apply_block_changes` turns into light and water updates next tick; meshing polls the dirty flag every frame (`schedule_chunk_jobs`); lamps call `set_entity_light` directly; entity placement and removal change `Entities.cells` without telling the world. `update_water_cell` skips an occupied cell without rescheduling it (`world_water.odin:85`), and `remove_entity` (`entity.odin:427`) takes only `^Entities`, so after `pick_up_entity` or `remove_for_developer` nothing schedules water there until a neighbouring block changes (read in the code, not reproduced).
- Chunk arrival fans out by hand: `insert_generated_chunk` (`world_streaming.odin:312`) stores the chunk, marks the column explored, registers veins, outcrops and crate sites, queues light, seeds entity lights and marks neighbours; the caller then runs `apply_added_veins_to_chunk`. `load_chunk_now` repeats `receive_generated_chunks`' sequence. Unload tells only the explored map and the renderer (`streaming.unloaded`).
- "Is the chunk loaded" is written inline 11 times in 9 files (`world_to_chunk_coordinate(cell) not_in world.chunks`), while `world_get_block` answers air for a missing chunk; belts, loose items, the player, placement and water each guard on their own.
- Column indexing three ways: `column_index` (`world_light_sky.odin:16`), `column_grid_index` with its border, and inline `(z %% CHUNK_SIZE) * CHUNK_SIZE + x %% CHUNK_SIZE` in `surface_at`; `COLUMN_COUNT` and `COLUMN_AREA` are the same constant in two files.
- Deterministic order of maps written four times: `sorted_outcrop_cells`, `sorted_explored_columns`, `collect_saved_chunks`, `simulation_state_hash`, over four comparators (`coordinate_before` in `fluid_network.odin`, `chunk_coordinate_before`, `saved_chunk_before`, `explored_column_before`).
- Two identical scheduled queues: `Water_Update` and `Leaf_Decay_Update` have the same two fields, `Water_Flow` and `Leaf_Decay` the same scheduled set; one pops a `queue.Queue`, the other compacts a dynamic array (`take_due_leaf_decays`).
- The god struct: `World` mixes storage, derived indices (vein_indices, outcrop_cells) and 13 game fields; `destroy_world` frees all 27.
- Parameters in bundles: the block registry beside every `^World` (section 2); in `generate_chunk_blocks` the column grid, nearby veins, trees and boulders go separately to `apply_outcrops`, `clear_above_outcrops`, `apply_ground_cover` and `find_open_columns`; `Terrain_Input` bundles them for `fill_terrain` only.
- Feature kinds by ternary: `feature_cell_size`, `feature_seed`, `feature_maximum_density`, `feature_density` each switch Tree or Boulder inline; `chunk_trees` and `chunk_boulders` are one loop twice.
- The generation step order in `generate_chunk_blocks` is a hand sequence with two early returns; that is right for an order dependent pipeline, but its result `Generated_Chunk` carries game records (veins, outcrops, crates) beside the blocks.
- The save codec's coupling: positional framing of 17 lists in `write_world_state` and the players, with `write_later_tables` as the extension point; four per kind lists in `save_state.odin` (`write_entity_pools`, `read_entity_pools`, `entity_pool_length`, `entity_common_at`, the last a copy of `entity_common` without the generation check); the remap knows ten content tables, only `Blocks` is the world's; `Byte_Reader` (`world_serialize.odin`) carries the remap, so the chunk format type depends on `save_remap.odin`.
- Misplaced helpers: `hash_u64` (the generation hash) in `render_atlas.odin`; join_save_path (`join_path` since 0145) used as the general path join by 11 files outside the cluster; `camera_world_coordinate` in the debug edit file, used by the raycast, the renderer and the simulation; `tick_world` in `simulation_world.odin`; `Box` in `player_collision.odin`; `World_Settings` in the vein file.

## 5. Refactors, ranked by gain per risk

1. Pure moves. `Box` to `block_shape.odin`; `coordinate_before`, `rotate_direction` and `camera_world_coordinate` to `world_chunk.odin`; `hash_u64` to `generation_seed.odin`; join_save_path (`join_path` since 0145) to `platform_paths.odin` under a general name; `tick_world` and `apply_block_changes` to a world file; `World_Settings` to `world_chunk.odin`; `COLUMN_AREA` replaced by `COLUMN_COUNT`. Files: those named, `tools/code_graph.py` unchanged. Guards: `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Gain: world -> simulation 213 to about 183, world -> presentation 16 to 12, the storage's outgoing list shrinks by 27, and 11 files stop naming a save procedure to join a path. Risk: none (one package). Prerequisite: yes.
2. Tell the world when an entity leaves a cell. `pick_up_entity` and `remove_for_developer` schedule water around the freed cells through a world procedure (a sibling of `schedule_water_around` taking the cells and the tick); placement already clears cover through `world_set_block`. Files: `world_water.odin`, `entity_placement.odin`, `developer.odin`, `world_water_test.odin`. Guards: `test_water_stays_out_of_entity_cells`, a new test that water flows into a picked up machine's cell. Gain: the behaviour fix and the first named cell change entry. Risk: low; the tick needs to be at hand (`Simulation_State.tick`). Prerequisite: no, but it is the seam a plugin's entity changes would call.
3. Take the game's records off `World`, byte compatible. Move statistics, research, shipments, contracts, venture_credit, catalogue_orders, the five prospecting lists, crate_sites, explored and leaf_decay into one game records struct (on `Simulation_State` after the loop audit's refactor 1), entities last. `save_state.odin` writes field by field, so the bytes stay the same. Files: `world_chunk.odin`, `save_state.odin`, `save_remap.odin`, then every `world.statistics` and record reader (about 40 files). Guards: `test_save_load_run_matches_the_original`, `test_prospecting_records_round_trip`, `save_remap_test.odin`, `./build.sh test`. Gain: `World` 27 fields to 13, then 12; the 13 type references out of `world_chunk.odin` leave. Risk: low, large diff; the tick procedures then take the records beside `^World`. Prerequisite: yes.
4. Chunk arrivals as an arrival list. `insert_generated_chunk` stores the chunk, queues light and marks neighbours; the veins, outcrops, crate sites, explored column and added vein stamps of the arrival go on a list the tick drains first. One insertion procedure serves `receive_generated_chunks` and `load_chunk_now`. Files: `world_streaming.odin`, `world_vein.odin`, `world_explored.odin`, `schematic.odin`, the tick, the tests that call `load_chunk_now` (`prospecting_test.odin`, `command_test.odin`, `schematic_test.odin`, `save_test.odin`). Guards: those tests, `test_streaming_loads_meshes_and_unloads`, `test_vein_lookup_same_from_each_overlapping_chunk`, `test_explored_surface_is_recorded_for_unloaded_chunks`. Gain: streaming's 12 references into records leave; chunk arrivals become tick input at a defined tick (the loop audit's frame write). Risk: medium; registration lands one tick later and a HUD vein read in between sees nothing. Prerequisite: yes.
5. A cell occupant index owned by the world. Move `Entities.cells` to the storage as cell to an opaque handle plus flags (blocks water, emits light), maintained by `add_entity`, `remove_entity` and `rebuild_entity_cells`; `entity_at`, the raycast and `update_water_cell` read it; `entity_lights` folds into the flag plus colour. Files: `entity.odin`, `world_raycast.odin`, `world_water.odin`, `world_light.odin`, `power_machine.odin`, `save_state.odin`. Guards: `world_raycast_test.odin`, `world_water_test.odin`, `hydro_grid_test.odin`, `test_saved_torch_lit_cave_is_lit_after_load`. Gain: the storage's 7 references to entities leave; the world stores what it needs of an entity and nothing more. Risk: low to medium (handle packing, lamp lights). Prerequisite: yes.
6. Generation per chunk context. A chunk plan (column grid, nearby veins, trees, boulders) built once in `generate_chunk_blocks` and passed to each step; a `[Feature_Kind]` table for cell size, seed, densities; `chunk_trees` and `chunk_boulders` merged. Files: `generation_chunk.odin`, `generation_features.odin`, `generation_veins.odin`. Guards: `test_generation_is_deterministic`, `test_tree_across_border_matches_from_both_chunks`, `test_columns_agree_across_chunk_borders`, `generation_trees_test.odin`, `generation_biome_test.odin`. Gain: about 40 lines, four ternary procedures to one table. Risk: low. Prerequisite: no; it gives a generation step a signature a plugin could implement.
7. One scheduled cell queue for water and leaf decay (due tick, position, scheduled set), keeping the saved lists' field names so the codec reads old files. Files: `world_water.odin`, `tree_felling.odin`, `save_state.odin`. Guards: `test_water_updates_are_deterministic_and_bounded`, `test_leaf_decay_queue_order_and_bound`, `test_leaf_decay_queue_round_trips`. Gain: about 25 lines, one queue for future delayed block rules. Risk: low.
8. The block registry on `World`. A registry pointer set by `make_simulation` and repointed by the content reload; world procedures drop the parameter. Files: the 22 files with the pair in section 2, `data_reload.odin`, the tests' world builders. Guards: `./build.sh test`. Gain: 78 signatures lose a parameter; a world package carries its own block table. Risk: low per line, very large diff; do it with the package split, not before.
9. Name framed save. Split the saved pools of `Entities` into one struct and write it, and the world's saved lists, as struct values so the codec's by name schema covers the top level; keep the positional reader as the format version 2 path with one log line on load (hand-back check). Files: `entity.odin`, `save_state.odin`, `save_world.odin`, `save_test.odin`. Guards: `save_test.odin`, `save_codec_test.odin`, `save_remap_test.odin`, a version 2 fixture. Gain: the four per kind lists and `write_later_tables` go; a new pool or record needs no save edit. Risk: medium to high (format change). Prerequisite: yes, for game state saved by name from a plugin.

## 6. Engine or game

Rule: what knows no item, machine or quest is engine.

- Engine: chunks and coordinates, the block registry mechanism, `block_shape.odin`, light, water, the mesher, the raycast over blocks, chunk bytes, streaming and workers, `save_binary.odin`, the staging and swap of `save_world.odin`, the chunk palette remap, the generation framework (purpose seeds, hashes, noise, the column grid, the per chunk sequence).
- Game: vein tables and placement, starter veins, biomes, trees and features, caves' crate sites, the spawn rules and landing pad, `World_Settings`' rules, the prospecting records, leaf decay's drops, the remap's settle rules (`settle_active_quest`, `remap_recipe_unlocks`, `settle_gone_machines`), `list_saves`' summary text.
- Both today: `World`, `Generated_Chunk`, `tick_world` (engine light and water, game leaf decay), `insert_generated_chunk`, `Content_Remap` (one engine table among ten).

What the game would need from an engine world across a plugin boundary:

- Block reads per tick: `world_get_block` at 26 simulation sites, plus `block_is_solid`, `block_shape`, `block_water_level` and `light_level`; mostly placement and player movement, a few in entity ticks (belt lifts, loose items, offshore pump intake). Batched per tick as a query list, or as a guest copy of the few chunks around entities.
- Block writes: `world_set_block` at 4 simulation sites plus tree felling and water; each call already queues a change, so a write list per tick maps onto today's `block_changes`.
- Entity storage: the engine needs only the cell occupant index of refactor 5; pools, networks and loose items stay in the game.
- Veins: the registry, column index and outcrops are game records the engine never reads except for streaming's registration; after refactor 4 the engine hands the game an arrival list (coordinate, and the game's own records if generation is in the game).
- Chunk load and unload notifications: arrival today goes to explored, veins, outcrops, crates, light; unload to explored and the renderer. Both become per frame lists across the boundary; entities keep ticking in unloaded chunks and read air there.
- Saving game state: the engine keeps world.sjson's storage fields and the regions with the block remap; the game writes entities.bin itself through the codec compiled into the plugin, with its own content tables. A raw guest memory snapshot would not survive a rebuilt plugin; the codec's by name schema would (refactor 9).
- Generation as a plugin: one call per chunk on each worker, so one plugin instance per worker thread (a wasmtime store is single threaded). In: seed and coordinate. Out: 32768 block ids (64 KiB), the open columns (1024 flags) for the engine's sky light, and the game records. The crossing is small against the measured 19.9 ms per chunk (debug build). The harder part is the column query surface used outside workers: `sample_column` (map pixels, biome banner, weather, ambient life), `terrain_height`, `find_spawn`, `veins_near_box` (orbital survey, added veins), `region_veins`, and the tree tables felling reads from `Generator`.

## 7. Entity component lens

Rule: the world needs a position index for entities, not their components.

- What the world stores per entity: the occupant map `Entities.cells` (cell to handle, read by the raycast, water, placement), `entity_lights` (cell to colour, lamps only), nothing per chunk. Loose items are not in the map.
- Vein-like records: `World.veins` with `vein_indices` (id to index), `column_veins` (column to ids) and `outcrop_cells` (cell to vein); drills hold a `Vein_Id`. Crate sites are a list with a placed flag; the crates themselves are `Schematic_Crate` entities.
- The world's own reads of entity data are two flags (occupied, water passes through a hydro turbine) and a colour; a component store would not replace anything the world needs. A position index with flags (refactor 5) does, whatever the game's storage becomes.
- Veins would fit an entity component model (position, footprint, reservoir, assay state) and would then be saved like other entities; the column and cell indices stay as world side spatial indices either way.
- The save's four per kind lists are what an ECS or a pool table would remove on the world's side; the codec itself is already generic.

## 8. Tests

Rule: storage, light, water, meshing and the codec are unit tested; streaming is tested end to end and slowly; the seams between world and game are not.

- Covered: coordinates and dirty marking (`world_chunk_test.odin`, 7); light add, remove, borders, arrival, colours, slabs (`world_light_test.odin`, 16); water spread, drain, fall, bound, entity cells (7); meshing, water surfaces, shapes, sway and orientation marks (`world_mesh_test.odin`, 30); raycast (5); chunk bytes and malformed input (4); the job queue, streaming load and unload, neighbour remesh (5); outcrop spending (4); generation determinism, borders, climate, spawn, trees, biomes (50 over four files); the codec's schema rules (4), the remap (8), save and run to the same hash every 100 ticks, modified chunks across unloading, the staged swap, older formats (12); the save list's loadable flag (`ui_world_setup_test.odin`).
- Uncovered: water or light after an entity leaves a cell; the stale mesh result dropped by revision in `take_current_meshes`; `stop_chunk_streaming` with jobs still queued (`drain_job_queue`); `build_debug_terrain` and the dirty only streaming path; the per frame limits as limits; `seed_arrived_chunks` for a chunk unloaded before its turn.
- Pinning implementation: `world_serialize_test.odin` asserts byte lengths of the chunk format (`4 + 2 + 4 + RUN_BYTE_SIZE`); `world_mesh_test.odin` asserts exact quad counts of the greedy merge; `prospecting_test.odin` pins the magnetometer strength formula (500). Generation tests do not pin one seed's output: they check ranges and properties over `TEST_SEEDS`, and determinism by comparing two runs.
- The streaming test's time (measured this session in `./build.sh test`, all tests in parallel): `test_streaming_loads_meshes_and_unloads` logged 12.2 s to settle 1183 chunks (721 non empty meshes) with 4 workers, then streams 273 more after the move. `test_report_generation_and_meshing_time` in the same run measured 19.9 ms generation and 42.3 ms meshing per chunk in the unoptimised test build, so the time is worker work (about 1183 generations and 721 meshes over 4 threads that share the cores with the other tests), not the per frame caps or the 1 ms sleep. That report test itself generates and meshes 100 chunks on one thread (about 6 s in that run) to assert only that quads exist.

## Claims to spot check

1. `World` (`world_chunk.odin:31`) has 27 fields, 13 of them simulation or content state (entities, leaf_decay, statistics, research, shipments, contracts, venture_credit, catalogue_orders, and five prospecting lists); `Chunk` (`world_chunk.odin:15`) holds no entity reference.
2. Water never re-evaluates a cell a machine leaves: `update_water_cell` returns early for an occupied cell (`world_water.odin:85`) without rescheduling, and `remove_entity` (`entity.odin:427`), called by `pick_up_entity` and `remove_for_developer`, touches only `Entities`.
3. `Box` (`player_collision.odin:16`) accounts for 25 of the 213 world -> simulation references (23 in `block_shape.odin`, 2 in `world_raycast.odin`) (probe over `tools/code_graph.py`'s parser).
4. The save framing is positional: `write_world_state` (`save_state.odin:110`) writes the world's lists in a fixed order, later tables go through `write_later_tables` (`save_state.odin:174`), and the 16 pools are listed in `write_entity_pools` (`save_state.odin:59`), `read_entity_pools` (`save_state.odin:209`), `entity_pool_length` (`save_state.odin:458`) and `entity_common_at` (`save_state.odin:499`).
5. `insert_generated_chunk` (`world_streaming.odin:312`) registers veins, outcrops, crate sites (`register_crate_sites` in `schematic.odin`) and the explored column besides storing the chunk, and `load_chunk_now` (`world_streaming.odin:341`) repeats `receive_generated_chunks`' insertion sequence.
