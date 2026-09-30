# 0144: Code map

Status: implemented

## Goal

The third step of the architecture cleanup (user, 2026-09-30): progressive disclosure for the code. An agent opening the source today faces 329 files in one directory; the map lets it read one page, pick a cluster, and open its entry file.

## Change

- `doc/code_map.md`: one section per cluster (the clusters of 0143, refined by its audits): purpose in one line, the entry file, the files in reading order with a half line each, the state it owns, the clusters it may depend on and the ones it must not, the tests that guard it. Generated in part by `tools/code_graph.py` (the file lists and the edges), written by hand for the rest, kept true by `tools/check_docs.py` (every file and name it cites must exist).
- `CLAUDE.md` points at it in the Layout section, `doc/README.md` lists it, `doc/architecture.md` keeps the mechanism and links the map for the file level.
- The allowed dependency table is the first statement of the layering the pilot split (0145) and any later package split follow; a violation found by the graph script is a finding, not a build error, until packages enforce it.

## Verify

- `python3 tools/check_docs.py` passes; `python3 tools/code_graph.py --check doc/code_map.md` (or equivalent) reports every edge that runs against the map's allowed table, and the item lists them as accepted or as refactors queued.

## Implementation notes

`doc/code_map.md` (the cluster table, the allowed dependency table, one section per cluster with its "Reaches into" record). `tools/code_graph.py` carries the 0143 corrections and the same eight clusters, so it places no file by its edges today; the edge rule stays for new prefixes. The single file prefixes went where the audits' verdicts put them: `biome_banner.odin` and `quick_transfer.odin` to ui, `landing_pad.odin` to world, `production_statistics.odin`, `tree_felling.odin` (the world audit's verdict; the 0143 notes did not list it) and `tick_profile.odin` to simulation, `deck_preset.odin` and `discovery.odin` to content, `diagnostics.odin` and `benchmark_factory.odin` to tools.

`--check` is a ratchet: it compares each edge against the allowed table with the map's "Reaches into" record and exits 1 only when an edge is new or above its record. At implementation (2026-09-30) it exits 0 with 22 edges and 1018 references against the table, every edge at its record. The record at implementation time, by 0143 queue entry (1 pure moves, 3 the hubs, 5 the seams); "accepted" is essential today and named in an audit, noise included:

| Edge | Refs | Accepted | Queued |
|---|---|---|---|
| world -> simulation | 227 | 169: the save codec encoding pools and records (`save_state.odin`, `save_remap.odin`, `save_world.odin`, 9 of them the noise `in_range`), `vein_is_exhausted` | 1: `Box`, `rotate_direction`, `coordinate_before` (27), `place_capsule` in the split `landing_pad.odin` (8) (35); 3: the game's records on `World` (15); 5: raycast and water reading entities, crate sites at chunk arrival (8) |
| world -> ui | 118 |  | 1: `column` noise (117), `world_settings_from_file` (1) (118) |
| content -> world | 105 | 93: definitions naming blocks, the content reload remapping the world, data file names | 1: `join_save_path` (11), `store_unsigned` (1) (12) |
| simulation -> loop | 93 | 1: `parse_seed` | 1: `Simulation_Content` and `Simulation_State` in the loop's files (92) |
| content -> simulation | 87 | 87: the registries' cross links and value types (`Item_Stack`, `Furnace`, `Quest_State`, the loaders) |  |
| ui -> tools | 49 | 43: `Data_Browser` in its screen, the diagnostics page names, the `block_name` field noise | 1: `enum_label` (6) |
| tools -> loop | 46 | 5: `session_generator`, `game_simulation_content`, `interpolation_alpha`, `parse_seed`, `BUILD_STAMP` | 1: the simulation state and `simulation_tick` in the benchmark and the commands (27); 3: `Frame_State` in `diagnostics.odin` and `data_export.odin` (14) |
| simulation -> ui | 43 | 27: the tick's input types | 1: `column` noise (14), `first_letter` and `shipment_cargo_text` (2) (16) |
| content -> ui | 42 | 40: settings typed by widget, binding and overlay types, UI data file names, colours | 3: the session's UI views made in `data_reload.odin` (2) |
| content -> loop | 28 | 19: `Game_Content` and `Session` in the reload, `data_edits_directory`, `BUILD_INFO`, the quest field `main` | 1: the simulation state (9) |
| presentation -> ui | 28 | 17: theme colours and marker palettes, `Input_Frame` for the fly camera, `Ui_Sound_Event` | 1: `column` noise (11) |
| world -> loop | 27 |  | 1: the simulation state in the save files (27) |
| ui -> loop | 25 | 6: `mining_ring_centre`, `BUILD_STAMP`, `parse_seed`, the quest field `main` | 1: `Simulation_Content` (11); 3: `Frame_State` in `touch_overlay.odin` (8) |
| content -> presentation | 18 | 18: data file names, display limits |  |
| platform -> content | 18 | 15: a parameter named `text`, noise | 1: `sorted_object_keys` (2), `STEAM_DECK_ENVIRONMENT_VARIABLE` (1) (3) |
| simulation -> presentation | 18 | 18: machine models and motion, `Fly_Camera`, `block_centre`, `line_block_belt`, `DAY_START_FRACTION` |  |
| world -> presentation | 16 | 12: the mesher's atlas and tile variation | 1: `hash_u64` (4) |
| content -> tools | 12 | 12: the `block_name` parameter noise |  |
| platform -> ui | 9 |  | 1: `Haptic_Request` and the rumble constants (4), `Ui_Rectangle` for the system keyboard (4), `column` noise (1) (9) |
| presentation -> loop | 6 | 1: `texture_edits_path` | 1: `Simulation_Content` (5) |
| presentation -> tools | 2 | 2: the `block_name` parameter noise |  |
| platform -> loop | 1 |  | 1: `BUILD_STAMP`, the build stamp parameter (1) |

- Totals: 585 accepted, queued 1 386, queued 3 39, queued 5 8 (`hash_u64` counted under 1, as the world audit's refactor 1 moves it).
- The small misplacements the new borders exposed are queued under 0143's entry 1 (its notes now say so): `enum_label` (input backends into `diagnostics.odin`), `first_letter` and `shipment_cargo_text` (simulation into ui screens), `STEAM_DECK_ENVIRONMENT_VARIABLE` (the Linux keyboard into `deck_preset.odin`), `Haptic_Request`, the rumble constants and `Ui_Rectangle` (platform into the input layer and the toolkit, an edge this item created by moving `haptics_*` and `system_keyboard_*` down), `store_unsigned` (configuration into the save codec), and `place_capsule` (the simulation half of `landing_pad.odin`). `Item_Stack` as the registries' value type stays accepted (named by the content audit).
- File coverage: a script under `tmp/` lists `src/*.odin` without `_test` (193 files) against the backticked names in the map's file list lines; every file is listed exactly once, none is missing, none is unknown. The entry column, the entry lines and the records name some files a second time by design.
- `src/android_libc/` is its own package, outside the graph; the map names it under platform.
