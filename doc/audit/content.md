# Audit: the content cluster

The content cluster (work item 0143) is what the graph left over: 41 files and 10880 lines in five groups that share little but a prefix table. The registries and the game rules (4853 lines), the loading and reload machinery (1429), the developer tools (2575), configuration and settings (974), and a platform layer of leaves (1049). Its debt:

- It is the most depended on cluster: 2029 references come in. 641 are the string table, 107 logging, 51 platform; 934 are the registries and the rules the tick and the screens read. The groups that are pure infrastructure have almost no edges out: strings none, logging one (`BUILD_STAMP`), platform one (the JNI helpers in `haptics_android.odin`).
- The content registries parse without strictness: `json.unmarshal` skips a key the struct lacks (`core/encoding/json/unmarshal.odin:631`), so a misspelled key in `items.sjson` or `machines.sjson` loads silently as its default, while the configuration, the UI theme, the procedural textures and the blueprints refuse an unknown key.
- One loader body is written 15 times (read, unmarshal, log "cannot parse", resolve, log "invalid"), and its failure reaches the caller through the log: `log_printf` copies the last "error: " line into `captured_log_error` for `Log_Capture`.
- Validation is split between load time, use time and tests: block name keys and description keys are checked at load, item, machine, recipe and technology name keys only by tests; three volume settings are clamped at use and never range checked at load.
- The game's own settings file is written in place (`write_settings_file`, `configuration_output.odin:123`), and a cut off file stops the next start (`main.odin:208` exits on a configuration problem): a defect by the hand-back rule.

## 1. What the cluster is

Rule: content turns files under `data/` and the configuration into typed tables once, and gives every cluster the string table and the log.

- Entry procedures: the load of all content `load_game_data` (`data_reload.odin:40`, through `load_game_tables` and `load_content_registries`); the reload `reload_content` (`hot_reload.odin:319`) and `reload_simulation` (`data_reload.odin:197`); the string lookup `text` (`data_strings.odin:127`); the configuration merge `load_configuration` (`configuration.odin:566`) with `merge_configuration_layers`; the command dispatch `execute_command_line` (`command.odin:223`) into `execute_command` and `execute_world_command`; the logging entry `log_printf` (`logging.odin:136`) after `open_log_file`.
- Rules run per tick from content files: `tick_quests`, `update_recipe_unlocks`, `tick_venture`, `log_discoveries`, `serve_developer_requests`.

| File | Lines | Commits | Purpose |
|---|---|---|---|
| `item.odin` | 609 | 12 | `Item_Registry`, drops per block, icons, names, prices |
| `recipe.odin` | 705 | 11 | `Recipe_Registry`, channels, makers, graph queries, name order |
| `technology.odin` | 415 | 10 | `Technology_Registry`, prerequisites, packs, level costs, the recipe back link |
| `recipe_unlocks.odin` | 180 | 5 | `Recipe_Unlocks`, availability per tick |
| `quest.odin` | 684 | 18 | chapter files, objectives, hints, rewards resolved to indices |
| `quest_runtime.odin` | 523 | 18 | `Quest_State`, objective progress, rewards into the capsule, messages |
| `contract.odin` | 233 | 2 | `Contract_Registry`, catalogue |
| `venture.odin` | 422 | 1 | `Contract_State`, shipments served, offers, the orbital survey |
| `notes.odin` | 218 | 2 | `Note_Registry`, unlock rules for the journal |
| `discovery.odin` | 65 | 2 | discoverable ores, discovery messages |
| `developer.odin` | 549 | 8 | `Developer_Request`, kits, `serve_developer_request` |
| `schematic.odin`, `recycler.odin` | 250 | 4 | an entity kind and the recycle rule (simulation audit) |
| `data_load.odin` | 316 | 14 | `Game_Config`, the data directory, Android assets, the data edits overlay, `read_data_file`, `find_definition_index` |
| `data_reload.odin` | 387 | 4 | `Game_Data`, the load order, reload of the simulation, `Log_Capture`, arenas |
| `data_strings.odin` | 129 | 7 | `String_Table`, `text` |
| `data_watch.odin` | 238 | 15 | `Data_Watch`, file categories, the settle |
| `hot_reload.odin` | 359 | 16 | reload per category on `Frame_State` (loop audit) |
| `command.odin` | 1160 | 10 | the command protocol, 30 usage rows, blueprints, queries |
| `command_socket.odin`, `command_socket_posix.odin`, `command_socket_windows.odin` | 384 | 8 | paths, the Unix socket, the Windows stub |
| `data_browser.odin` | 709 | 3 | the Data files screen's trees and edits |
| `data_export.odin` | 322 | 1 | export, `write_file_replacing` |
| `configuration.odin`, `configuration_output.odin` | 710 | 14 | layers, provenance, strict typed assign, dump, the settings file |
| `settings.odin`, `deck_preset.odin` | 264 | 23 | `Settings` (37 fields), ranges, the Steam Deck preset |
| `logging.odin`, `logging_posix.odin`, `logging_windows.odin` | 347 | 14 | the log file, stderr redirect, crash traces |
| `platform_paths.odin`, `platform_android.odin` | 209 | 7 | base directories, Android entry points and logcat |
| `local_zone.odin`, `local_zone_posix.odin`, `local_zone_windows.odin` | 80 | 3 | the local time zone |
| `export_access_android.odin`, `export_access_desktop.odin`, `jni_indices.odin` | 172 | 5 | Android all files access, JNI table indices |
| `sjson_text.odin`, `run_length.odin` | 241 | 2 | SJSON writer of the data edits, the chunk run length codec |

Cluster assignment (`tools/code_graph.py` puts every file above in content):

- Simulation: `quest_runtime.odin`, `recipe_unlocks.odin`, `venture.odin` (state saved in `Simulation_State` or `World`, advanced inside `simulation_tick`), `developer.odin` (loop audit), `schematic.odin`, `recycler.odin` (simulation audit). `discovery.odin` splits: its predicates are content, `log_discoveries` is tick.
- Loop: `hot_reload.odin` (loop audit).
- A `platform` cluster of its own: the logging trio, `platform_paths.odin`, `platform_android.odin`, the local zone trio, the export access pair, `jni_indices.odin`, `run_length.odin`, `sjson_text.odin` (13 files, 1049 lines). After the cuts of refactor 2 none of them has an edge into the big component.
- A `tools` cluster: `command_socket.odin` and its pair, `data_browser.odin`, `data_export.odin`, `command.odin` (2575 lines). The transport and the browser are engine, `command.odin`'s vocabulary is game (27 files out).
- Configuration (`configuration.odin`, `configuration_output.odin`, `settings.odin`, `deck_preset.odin`) stays one group: its 44 edges out are the types of the settings it holds (`Slider_Range`, `Binding`, `Marker_Palette`, display constants) and join_save_path (`join_path` since 0145).
- What remains as content: the registries (`item.odin`, `recipe.odin`, `technology.odin`, `quest.odin`, `contract.odin`, `notes.odin`) and the loading files (`data_load.odin`, `data_reload.odin`, `data_strings.odin`, `data_watch.odin`).

## 2. State

Rule: prototype tables are written once per load into one arena; everything that changes during play lives elsewhere.

- The registries are structs of slices indexed by a dense index: items, machines, fluids and blocks by distinct ids (`Item_Id`, `Machine_Id`, `Fluid_Id`, `Block_Id`), recipes, technologies, quests, contracts, notes and vein types by plain `int` with -1 sentinels (`NO_RECIPE`, `NO_TECHNOLOGY`, `NO_QUEST`).
- Load order and cross links (`load_content_registries`, `data_reload.odin:84`): blocks, items (drops per block), fluids, machines (item, ports), recipes (items, fluids), machines against recipes, technologies (items, recipes; `link_recipe_technologies` writes each research recipe's technology back into the recipe registry), `lab_packs` set on the machines (`data_reload.odin:95`), quests, contracts, description keys, notes; then kits, touch overlay, generator, veins against items, the sapling.
- Written after load by others: `icon_loaded` on the item registry by `render_icons.odin:117` (presentation state in a prototype table); `schematics_found` on copies of the recipe registry by `with_schematics_found` (session unlocks, loop audit); `refresh_content_names` on a strings reload; a per session copy of the technologies by `scaled_technology_registry`.
- The content arena (`content_arena` on `Frame_State`): a content reload replaces it whole in `replace_frame_content`. `reload_developer_kits` and `refresh_content_names` allocate into the live arena on every kits or strings reload, so it grows until the next content reload.
- The string table: `global_string_table`, read without the lock, swapped under it by `replace_string_entries`; the old entries wait in `retired_strings` until nothing can point into them. Tests point `thread_string_table` at their own. Missing keys are reported once and shown as the key.
- `Settings` (37 fields) comes from `Loaded_Configuration` with its `Configuration_Provenance`; the screens write it through `Screen_Context`, the deck preset at start, and `write_changed_settings` persists every frame it differs from `stored_settings`.
- `Game_Config` is parsed once from `game.sjson` by `main` and never reloaded (`data_file_category` gives it Restart). It mixes an engine value (`tick_rate`) with game rules (starting items, loose item despawn) and two new world defaults.
- Game state in content files: `Quest_State` and `Recipe_Unlocks` on `Simulation_State`, `Contract_State` on `World` (world audit). Writers: `tick_quests`, `update_recipe_unlocks`, `tick_venture`, `serve_developer_request`, the save remap's settle rules (world audit), and the loop, which drains `Quest_State.notices`. `Quest_Message` stores string keys, never text.
- `Game_Content` against `Simulation_Content` is the loop audit's finding; it also carries two process flags (`unlock_all`, `developer_mode`).

## 3. Coupling

Rule: into content, types, lookups, strings and logging are essential; out of content, only the loaders' dependencies on the types they resolve against are.

| Direction | References | What they are |
|---|---|---|
| content -> simulation | 240 | `quest_runtime.odin` 49 (`Statistics` 13, `item_counter` 7), `developer.odin` 38, `recipe.odin` 27 (`Item_Stack`, `Furnace`, `Fluid_Registry`), `command.odin` 21, `quest.odin` 21, `schematic.odin` 19, `recycler.odin` 17; 12 are `block_name` parameter noise in `item.odin` |
| content -> world | 200 | `data_reload.odin` 41 (generator, chunk remap), `item.odin` 35 (`Block_Registry`, `Block_Id`), `developer.odin` 27, `venture.odin` 26, `command.odin` 20; join_save_path (`join_path` since 0145) 21 |
| content -> ui | 114 | `export_access_android.odin` 42 (JNI helpers), `settings.odin` 17 (`Slider_Range` 10, `Input_Frame` 4), `hot_reload.odin` 11, `data_watch.odin` 8 (file names of fonts, theme, bindings); `column` noise 5 |
| content -> loop | 98 | `hot_reload.odin` 26 (`Frame_State`), `data_reload.odin` 21 (`Game_Content`, `Session`), `venture.odin` 18, `developer.odin` 12 (`Simulation_State`, `Simulation_Content`); the quest field `main` 5 is noise |
| content -> presentation | 35 | `hot_reload.odin` 14 (renderer rebuilds), `data_watch.odin` 11 (directory and extension constants), display limits in `configuration.odin` |

Into content (2029), by the group referenced:

| From | Strings | Logging | Platform | Configuration | Loading | Tools | Registries and rules |
|---|---|---|---|---|---|---|---|
| ui | 574 | 22 | 32 | 74 | 18 | 31 | 301 |
| simulation | 18 | 6 | 0 | 1 | 7 | 0 | 454 |
| loop | 32 | 52 | 8 | 17 | 47 | 50 | 55 |
| world | 2 | 10 | 9 | 0 | 15 | 10 | 89 |
| presentation | 15 | 17 | 2 | 19 | 7 | 0 | 35 |

- Essential: the simulation's 454 (`Item_Id`, `Item_Registry`, `Recipe_Registry`, `NO_ITEM`, `item_stack_size`), the screens' registry reads, `text` and `log_printf` everywhere.
- Misplaced: `Item_Stack` (defined in `inventory.odin`) is named 50 times from content; it is the registries' value type. `find_vein_type` and `find_size_class` live in `command.odin` and are called by the benchmark. `find_technology` lives in `quest.odin`, `find_quest_index` in `notes.odin`.
- Reach through: `developer.odin` places machines and sets blocks on `World` directly (`world_set_block`, `add_vein`); `venture.odin` reads the generator's veins; `data_export.odin` takes `Frame_State` and `Ui_State` for a toast (loop audit refactor 3).
- Cycles: content is in a mutual pair with every cluster. Only `local_zone.odin`, its pair, `jni_indices.odin`, `run_length.odin` and `export_access_desktop.odin` are outside the 185 file component.

For 0145, by the name level probe with the noise removed:

- True leaves (no real edge into the component): `local_zone.odin`, `local_zone_posix.odin`, `local_zone_windows.odin`, `jni_indices.odin`, `run_length.odin`, `export_access_desktop.odin`, `platform_android.odin` and `logging_windows.odin` (their only edges are a parameter named `text`), `platform_paths.odin` (only `android_data_paths`, a leaf).
- One edge away: `logging.odin` (`BUILD_STAMP` in `main.odin`), `logging_posix.odin` (joins `logging.odin`), `sjson_text.odin` (`sorted_object_keys` in `configuration.odin`), `data_strings.odin` (`read_data_file` and `read_logged_data_file`, plus logging), `export_access_android.odin` (the JNI helpers in `haptics_android.odin`), `command_socket.odin` (`SCREENSHOT_DIRECTORY_NAME`), `command_socket_windows.odin` (`Queued_Command_Line`).
- Two edges: `command_socket_posix.odin` (`command_error`, `format_command_response`); `deck_preset.odin` (configuration and settings only).

## 4. Abstraction gaps

Loading:

- 15 loaders repeat one body (`read_logged_data_file`, `json.unmarshal` through a one line `parse_*_file`, "cannot parse", `resolve_*`, "invalid"): items, recipes, technologies, machines, fluids, blocks, contracts, notes, kits, strings, game config, biomes, veins, trees, chapters. 19 `parse_*` procedures wrap `json.unmarshal` alone.
- Two failure conventions: these 15 return `ok` and log; the sound table, bindings, theme, fonts and models return a problem string. `load_game_data`, `reload_developer_kits`, `load_start_data_into` and the frame loop recover the problem through `Log_Capture` and `captured_log_error`, which keep only the last "error: " line and give `logging.odin` a hook for data loading.
- No strictness in the content tables (summary); the configuration's reflective assign (`assign_configuration_value`, `configuration.odin:323`) already does strict typed loading with provenance and is not used for data.
- The data file list is written four times: each loader's file name constant, `top_level_data_file_category` and `data_file_category` (switches over names and directories), the call order in `load_content_registries` and `load_game_tables`, and `content_tables` for the remap.

Validation:

- Name keys of items, machines, recipes and technologies are never checked against the string table at load (blocks' are, `world_block.odin:272`); only `test_shipped_item_names_are_in_the_string_table`, `test_machine_strings_exist` and `test_recipe_and_technology_strings_exist` catch a bad key, so an overlay edit with one loads and shows the key.
- A strings reload re-checks nothing: `reload_strings` does not run `validate_content_description_keys`.
- One string key check is written four times: `check_contract_key`, `check_note_key`, `check_string_key`, `description_key_problem`.
- The burner or electric rule of a machine definition is written twice verbatim (`validate_drill_definition`, `validate_crafting_machine_definition`) and once as a switch (`validate_inserter_definition`). Drills, inserters and labs refuse fields of other kinds, chests, belts and splitters do not.
- `validate_settings` lists 13 keys with their ranges by hand; the three volumes are missing although `VOLUME_RANGE` exists, and `audio.odin:246` clamps them at use.

Lookups by id:

- `find_definition_index` exists and 8 call sites use it; 12 procedures write the same loop by hand (`find_item_id`, `find_fluid_id`, `find_machine_id`, `find_recipe`, `find_technology`, `find_quest_index`, `find_vein_type`, `find_size_class`, `find_biome_index`, `find_tree_species_index`, `find_vein_type_index`, `find_sound`), and the tests add `test_item`, `test_machine`, `test_recipe`.
- Ids resolve once at load except in two tick paths: `simulation_tick` calls `simulation_tree_felling` (`loop.odin:283`), which searches the items for the sapling every tick (`tree_felling.odin:63`); `offer_contracts` calls `venture_started`, which searches the machines for the launch pad every tick (`venture.odin:70`).

Content in code (`CLAUDE.md`: never hardcode a block, recipe, machine or technology):

- `resolve_generation_blocks` (`generation.odin:42`, world cluster) names six blocks (stone, deep stone, water, sand, landing pad, gold quartz); `world_debug_terrain.odin:28` names five and `texture_generate.odin:31` one (`ORE_GROUND_BLOCK`). Roles such as the generator's stone could be keys of `biomes.sjson` or `veins.sjson`.
- `debug_drop_item_on_belt` (`belt_placement.odin:374`) looks up "iron_plate" by id; developer only.
- Behaviour is code by design: `Machine_Kind` (25), `Recipe_Maker`, `Technology_Effect`, `Objective_Type`, `Hint_Counter` are enums the data names by string (`parse_named_enum`); a new kind of behaviour is a code change, a new machine of a kind is not.

Commands:

- A command is written in four places: a row in `command_usages` (help only), a case in `execute_command` or `execute_world_command`, its procedure, and for world edits a `Developer_Action` (19 values) with a case in `serve_developer_request` over the 14 field `Developer_Request`. `save` and `reload` answer "runs only in the game" in `command.odin` and are intercepted by string in `execute_queued_command` (`loop.odin:1292`).

Configuration against the global preference for layered SJSON configuration:

- Matches: SJSON, the system, user and `config.d` layers in order, command line last, recursive merge with arrays replacing, strict unknown keys and types, provenance per key, the `config` subcommand, state and logs under the state home, `~/` expansion of `paths.saves`.
- Differs: no project layer (documented, a game has no project), no `profile` and `profiles` selector, and two more configuration files outside the layering: `touch_overlay.sjson` beside `config.d` (ui cluster) and `texture_edits.sjson` in the state directory.
- Two home expansions (`expand_home` for the configuration, `expand_home_path` in `data_export.odin` at use time) and four SJSON writers: `sjson_text`, `write_configuration_dump_value` (settings file and dump), `touch_layouts_file_text` and the texture edits text by hand.
- In place writes: `write_settings_file` (this cluster, above) and the touch layouts (`touch_overlay.odin:971`, ui cluster); the texture edits are the presentation audit's.

Platform pairs:

- Four `#+build` pairs repeat their signatures by hand (logging 4 procedures, command socket 7 and `Command_Server`, local zone 2, export access 2); a drifted signature shows only in `./build.sh check-windows` or `./build.sh check-android`, not in `./build.sh check`. Shared logic stays in the shared file, so the stubs are one line each; the shape is sound.

## 5. Refactors, ranked by gain per risk

1. The settings file through `write_file_replacing`, and one home expansion. `write_settings_file` writes 90-settings.sjson through `write_file_replacing`; `expand_home_path` becomes `expand_home`. The touch layouts' writer is the same one line change in the ui cluster. Files: `configuration_output.odin`, `data_export.odin`, `touch_overlay.odin`. Guards: `test_settings_file_round_trip`, `test_deck_preset_marker_round_trip`, `data_export_test.odin`. Gain: the hand-back rule holds for the one file whose damage stops the start. Risk: none. Prerequisite: no.
2. The platform leaves. Pass the stamp into `open_log_file` instead of naming `BUILD_STAMP`; move `sorted_object_keys` into `sjson_text.odin`; move join_save_path (`join_path` since 0145) into `platform_paths.odin` (world audit refactor 1) and the JNI helpers into `platform_android.odin` (ui audit refactor 1); map the platform files, `quest_runtime.odin`, `recipe_unlocks.odin`, `venture.odin` and `hot_reload.odin` in `tools/code_graph.py`. Files: `logging.odin`, `main.odin`, `sjson_text.odin`, `configuration.odin`, `platform_paths.odin`, `save_world.odin`, `haptics_android.odin`, `platform_android.odin`, `tools/code_graph.py`. Guards: `./build.sh check`, `./build.sh check-windows`, `./build.sh check-android`, `platform_paths_test.odin`, `test_sjson_text_parses_back_to_an_equal_tree`, `test_static_runtime_imports_stay_out_of_windows`. Gain: 13 files, 1049 lines, no edge into the component. Risk: none (moves and one parameter). Prerequisite: yes, it is the 0145 pilot.
3. Resolve the two tick lookups at load: the sapling's item id into the generator's tree data when the content loads, the launch pad's machine id beside `lab_packs` on the machine registry. Files: `tree_felling.odin`, `venture.odin`, `data_reload.odin`, `machine.odin`. Guards: `venture_test.odin`, `test_quest_simulation_is_deterministic`, `data_reload_test.odin`, the tree felling tests. Gain: two linear searches per tick gone, the "resolve once" rule holds. Risk: low (a reload must refresh them, which the load path does). Prerequisite: no.
4. One SJSON table reader and problems instead of captured log lines. A generic reader over the overlay that returns the parsed struct or a problem naming the file replaces the 15 loader bodies and the 19 `parse_*` wrappers; the `load_*` procedures return problems as the `resolve_*` do; `load_game_data` logs once; `Log_Capture` and `captured_log_error` go. Files: `data_load.odin`, `data_reload.odin`, `logging.odin`, `hot_reload.odin`, `main.odin`, `loop.odin`, the 15 loader files. Guards: every `test_shipped_*` loader test, `test_a_failing_recipe_file_keeps_the_old_content`, `test_a_refused_reload_leaves_the_world`, `test_a_broken_data_edit_turns_the_overlay_off_at_start`. Gain: about 150 lines, one failure convention, `logging.odin` loses its data hook. Risk: low; the toast texts keep their wording. Prerequisite: yes, it is the engine's loader.
5. Strict content keys. The reader of refactor 4 compares each object's keys to the target struct's fields (the walk `assign_configuration_struct` does) before unmarshalling and refuses an unknown key naming the file and the key path. Files: `data_load.odin`, `configuration.odin` (the field lookup shared). Guards: the `test_shipped_*` tests (the shipped data must pass), a new test of a misspelled item key. Gain: a typo in a data file or an overlay edit refuses the load instead of loading a zero. Risk: medium; keys the structs dropped earlier surface as errors in the shipped data, whose fix is a data edit. Prerequisite: no.
6. Complete load time validation. `validate_content_description_keys` also checks the name keys of items, machines, recipes and technologies and runs again after a strings reload; one key check procedure replaces `check_contract_key`, `check_note_key`, `check_string_key` and `description_key_problem`; `validate_settings` gains the three volumes. Files: `data_reload.odin`, `hot_reload.odin`, `item.odin`, `contract.odin`, `notes.odin`, `quest.odin`, `configuration.odin`. Guards: `test_description_key_is_optional_but_must_resolve`, `test_quest_data_rejects_bad_definitions`, `test_note_validation`, `test_configuration_unknown_key_and_wrong_type`. Gain: a bad key is refused at load; three test only checks become load checks. Risk: low. Prerequisite: no.
7. One lookup by id. The typed `find_*_id` procedures call `find_definition_index`; `find_technology` moves to `technology.odin`, `find_quest_index` to `quest.odin`, `find_vein_type` and `find_size_class` to `world_vein.odin`; the test helpers call the real ones. Files: `item.odin`, `fluid.odin`, `machine.odin`, `recipe.odin`, `quest.odin`, `notes.odin`, `command.odin`, `world_vein.odin`, `generation_biome.odin`, `generation_trees.odin`, `generation_vein_tables.odin`, the test helpers. Guards: `./build.sh test`. Gain: about 70 lines; world -> content loses the benchmark's 4 references to `command.odin`. Risk: none. Prerequisite: no.
8. A command table. One row per command: name, usage, summary, needs a world, runs in the frame (save, reload, screenshot) and the procedure; `command_help` and dispatch read it, `execute_queued_command` asks the row instead of comparing strings. Files: `command.odin`, `loop.odin`. Guards: `command_test.odin` (15 tests), `test_commands_without_a_world`, `test_command_socket_round_trip`. Gain: a command is one row and its procedure; the table is the registration surface a game plugin needs. Risk: low. Prerequisite: yes, for a plugin that adds commands.
9. Settings free of input logic. Move `apply_look_settings` and `apply_hold_settings` to the input files and define the range type beside `Settings` (the widget takes it), so `settings.odin`'s 17 ui references drop to its enum field types. Files: `settings.odin`, `ui_widgets.odin`, `input_actions.odin`, `ui_screens.odin`. Guards: `test_look_settings`, `test_gyro_setting_and_sensitivities`, `test_every_screen_stays_inside_the_screen`. Gain: 14 edges; configuration moves toward an engine group. Risk: none. Prerequisite: no.

## 6. Engine or game

Rule: the engine reads, watches, overlays, validates the syntax of and reloads files; the game says what a file means.

- Engine: `read_data_file` with the overlay, `data_watch.odin`, the reload sequencing, the arena lifetime, `data_strings.odin`, configuration and `Settings` persistence, logging, the command transport, `data_browser.odin` and `data_export.odin` (both work on `json.Value` and never on a registry), `sjson_text.odin`, the platform pairs, `run_length.odin`.
- Game: what a recipe, technology, machine, quest, contract and note are and how they cross link; `quest_runtime.odin`, `recipe_unlocks.odin`, `venture.odin`, `discovery.odin`, `developer.odin` and the kits; `command.odin`'s commands; `game.sjson` except `tick_rate`.
- Both today: `Game_Config` (engine tick rate, game rules), `Settings` (window, audio and input beside `bottleneck_overlay` and the marker palette), `load_content_registries` (engine order and failure, game cross links), `item.odin` (a registry the world's drops and the renderer's icons read).
- Blocks stay engine data: the world stores, meshes and remaps them (world audit), so the engine parses `blocks.sjson` itself and hands the block table to the game.

What the engine would load for a game plugin:

- Files by path and category, handed over as bytes: the engine resolves the overlay, watches the file, logs and toasts problems; the plugin unmarshals into its own types, since the host's type information cannot see a wasm module's structs. Strictness then runs in the plugin with the same reader compiled in.
- Back to the engine per table: the id list (what `content_tables` builds today), so the reload summary (`content_table_changes`) and the save remap's tables stay generic, and the names the UI shows as string keys.
- The string table stays in the engine. The game already stores keys, not text (`Quest_Message`, the venture's message keys); its loaders need the key set to validate against, which `load_game_data` already takes as a parameter (`string_entries`). The name sorts (`refresh_content_names`) move to the UI side.

A content reload with a live world and a plugin, along `reload_simulation`:

- The old plugin instance encodes the simulation with its codec (world audit: the game writes `entities.bin` itself); the engine loads the new files, keeps the chunk block remap (`move_world_chunks`) and hands the new plugin instance the bytes, the old and new id tables; the plugin decodes with the remap; on a problem the old instance stays. A plugin code reload is the same path with a new module.
- Between frames only, as today; the renderers built from content (atlases, models, belts) rebuild from the engine side tables the plugin returns.

## 7. Entity component lens

- The registries are the prototypes the kinds are instantiated from: `Machine_Definition` is one flat struct of 45 fields for 25 kinds; `validate_machine_kind_fields` switches over the kinds into 11 validators in 6 files, and `Machine` repeats the resolved fields flat.
- A component style prototype (a machine lists a burner with its fuel slot and power, slots, fluid ports, an electric draw, a work speed) maps onto the simulation audit's component table (burner, item slots, power draw and supply, progress, fluid ports): each component's keys are validated once (the burner or electric rule written twice today disappears), and a stray key is an unknown key of a component (refactor 5).
- It replaces the per kind field lists and most per kind validators; it does not replace `Machine_Kind`, whose behaviour stays code. With the simulation audit's kind table, the prototype's component set would fill the per kind component locations.
- Cost: `machines.sjson` (912 lines, 50 machines) and its header rewritten, the model and blueprint tools unchanged, no save change (machines are saved by id). Order: after the simulation audit's shared component structs (its refactor 8), so a component's loader fills the struct the tick reads.

## 8. Tests

Rule: loaders and rules are well tested through the shipped data; the file writers and the platform code are not.

- Loaders and validators: every shipped table loads (`test_shipped_items_resolve`, `test_shipped_recipes_resolve`, `test_machine_data_loads`, `test_shipped_blocks_parse_and_validate`, `test_shipped_generation_data_resolves`, `test_shipped_tree_species_resolve`, `test_shipped_notes_resolve`, `test_shipped_quest_chapters_load`, `test_shipped_developer_kits_resolve`, `test_shipped_game_config_parses_and_validates`, `test_shipped_touch_overlay_loads`, the contracts through `make_test_contracts`); bad definitions are refused per table (`test_machine_data_rejects_bad_definitions`, `test_recipe_data_rejects_bad_definitions`, `test_technology_data_rejects_bad_links`, `test_quest_data_rejects_bad_definitions`, `test_note_validation`, `test_item_loading_rejects_bad_tables`); strings cover the UI and descriptions (`data_strings_test.odin`).
- Reload: `data_reload_test.odin` (5): same content keeps the world, an inserted item, a failing recipe file, a refused reload, a bad strings file.
- Quests: `quest_runtime_test.odin` (8, every objective type, determinism) and seven chapter files (39 tests, 1739 lines) that play the shipped chapters; `test_shipped_quests_never_need_a_locked_recipe`.
- Commands: `command_test.odin` (15, every command and query, blueprints, ticks), `test_command_socket_round_trip`, `test_command_socket_is_off_on_windows`.
- Configuration: `configuration_test.odin` (11: layers, merge rules, strictness, home expansion, the settings file round trip, dump), `deck_preset_test.odin` (3), `data_watch_test.odin` (6, categories and the settle).
- Uncovered: `export_access_android.odin` and `export_access_desktop.odin`; the log file, the stderr redirect and the crash handlers (`log_session_header`, `open_log_file`); `load_local_zone` (only the offset arithmetic); `platform_android.odin`; `hot_reload.odin` (loop audit); `recipe_unlocks.odin` and `technology.odin` have no test file and are covered through crafting, lab and quest tests; a strings reload's effect on content validation.
- Pinning implementation: `make_test_content` (`machine_test.odin:21`, used 290 times in 46 test files) repeats `load_content_registries`' cross links by hand (`lab_packs`, the crafting check) and omits quests, kits and the key checks, so a new cross link is absent from most tests. `test_shipped_items_resolve` pins 143 items and `test_shipped_recipes_resolve` 122 recipes and 27 technologies; `test_chapter_05_loads` pins the chapter's quest ids in order: adding content fails a loader test.

## Claims to spot check

1. Content tables accept unknown keys: `parse_items_file` (`item.odin:123`) is `json.unmarshal`, whose struct branch skips a key without a field (`~/opt/odin/core/encoding/json/unmarshal.odin:631`); the configuration refuses one (`configuration.odin:411`).
2. `write_settings_file` writes 90-settings.sjson in place with `os.write_entire_file` (`configuration_output.odin:123`), and `main` exits on a configuration problem (`main.odin:208` to `main.odin:211`).
3. The loaders' problem reaches the reload through the log: `log_printf` stores the last "error: " line in `captured_log_error` (`logging.odin:138`), read back by `end_log_capture` (`data_reload.odin:368`).
4. Two id lookups run every tick: `simulation_tree_felling` (`tree_felling.odin:63`, called at `loop.odin:283`) and `venture_started` (`venture.odin:70`, from `offer_contracts` at `venture.odin:133`).
5. `validate_settings` (`configuration.odin:487`) checks no volume although `VOLUME_RANGE` exists (`settings.odin:163`); `audio.odin:246` clamps the volumes at use.
