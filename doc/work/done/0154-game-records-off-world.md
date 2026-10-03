# 0154: The game's records off World, byte compatible

Status: implemented

## Goal

Queue entry 3 of the architecture audits, the hub change the engine cut depends on most (`doc/audit/world.md`, refactor 3; `doc/audit/simulation.md`, section 3). `World` (27 fields) carries 13 simulation or content records (statistics, research, shipments, contracts, venture credit, catalogue orders, the five prospecting lists, crate sites, explored, leaf decay) so the tick reaches them through one pointer; 136 of the 145 `world.` field reads in the simulation are those records. For the cut, `World` is the engine's block store and the records are the game's state.

## Change

- One game records struct holds the records; it lives on `Simulation_State` beside `World` (`simulation_state.odin`). `World` keeps blocks, chunks, light, water, streaming state, settings and, for now, `entities` (the cell occupant index of the world audit's refactor 5 comes later).
- Every reader and writer of a record follows (about 40 files: the tick procedures, the screens through `Screen_Context`, the save codec, the remap, the command socket, the diagnostics). Where a procedure took `^World` only for a record, it takes the records (or the one record) instead; where it needs both, both.
- The save bytes stay the same: `save_state.odin` writes each field separately, so the writer and reader address the records struct for those fields in the same order; `simulation_state_hash` covers the records as before. A save written before the change loads unchanged (the hand-back check's save line), and the run comparison test proves it.
- `doc/architecture.md` (World storage, the simulation) and `doc/code_map.md` (the world and simulation state lines, the records lowered: world -> simulation falls by the record readers) follow.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (`test_save_load_run_matches_the_original`, `test_prospecting_records_round_trip`, `save_remap_test.odin`, the statistics, quest and venture tests), `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- A save file written by the previous build (the implementer writes one with a test before the change, keeps it under `tmp/`, and loads it after) loads with the same state hash.

## Implementation notes

- `Game_Records` (`simulation_state.odin`) on `Simulation_State` beside `world`: statistics, research, shipments, contracts, venture_credit, catalogue_orders, assayed_veins, magnetometer_readings, core_samples, seismic_shots, seismic_outlines, crate_sites, explored, leaf_decay (14 fields). `destroy_game_records` frees them; `destroy_simulation` calls it after `destroy_world`.
- `World` went from 27 fields to 13: chunks, settings, veins, vein_indices, column_veins, outcrop_cells, spent_outcrops, block_changes, lighting, entity_lights, water, entities, saved_chunks.
- Leaf decay stays a record: `tick_world`, `run_leaf_decay`, `fell_tree`, `queue_felled_leaves` and `decay_leaf` take `^Leaf_Decay` beside `^World`, since the queue is game state run on the world's blocks.
- Call sites: 47 source files (90 procedure signatures, about 340 changed lines besides signatures and comments) and 49 test files (22 helper signatures). A procedure that wrote one record takes that record (`statistics: ^Statistics` through the placement and belt drag chain, `tick_assemblers`, `tick_launch_pads`, `drop_player_stack`; `crate_sites`, `core_samples`, `assayed_veins`, `explored` slices or pointers in the schematic, prospecting, HUD, map and explored procedures); one that needed several takes `records: ^Game_Records` beside `^World` (`tick_entities`, `tick_player`, `mine_block`, `tick_labs`, `advance_drill`, `tick_electric_networks`, the prospecting writers, `insert_generated_chunk` and the streaming update, the codec). `offer_contracts` takes the records and the seed. `Screen_Context` and `Sound_Frame` gained `records` and `statistics`.
- Tests: `make_test_records` and `make_fluid_test_records` (`drill_test.odin`) replace the statistics the drill and oil world builders put on `World`; the determinism tests keep one records per world; `settle_world` ticks with an empty local leaf decay queue.
- Save proof: before the change a temporary env gated test wrote the save test site (the full `build_save_test_site`: every machine kind, statistics, research, shipments, venture, prospecting records, crate sites, loose items, plus two scheduled leaf decays) after 300 ticks to `tmp/save_before_0154/` with `save_world`. After the change the same test wrote `tmp/save_after_0154/`: `diff -r` finds every file byte for byte equal (entities.bin, world.sjson, four region files). Loading `tmp/save_before_0154/` with the new build gives state hash 49808370bc6f4c39, the hash the old build logged for the original after saving and for the same load. The temporary test is removed; `test_save_load_run_matches_the_original` keeps guarding the round trip.
- `code_map.md`: world -> simulation is 221, one above 220. `world_chunk.odin` lost the 13 record type and destroy references, but the codec now names `Game_Records` in its seven world state procedures (save_state 7, save_remap 1) and streaming names it in the five arrival procedures (5), and `tick_world` names `Leaf_Decay` (1). Field reads through `world.` were never counted, so the record readers moving does not show; the streaming references go with the arrival list (world audit, refactor 4).

