# 0208: Re-record the code map's grown edges from the field series

Status: landed (2026-10-03, 9580427; verified 2026-10-03 by the main agent reading the diff, two moves and four record lines)

## Goal

`doc/code_map.md` records, per cluster, the references the allowed dependency table does not allow, and `tools/code_graph.py --check` fails when one grows. The items of 2026-10-03 (0193 to 0203) grew five edges without the check running, since no verify list named it: world to simulation 232 to 237, content to simulation 101 to 105, content to world 93 to 96, simulation to ui 42 to 44, ui to loop 9 to 10. The record is false until the counts are re-recorded or the references refactored.

## Change

- Run the check, read each grown edge's new references (`tools/code_graph.py --files`), and for each decide: refactor it away where the reference is a plain misplacement (a procedure that belongs in the cluster it reaches into), else re-record the count with the reference named in the cluster's "Reaches into" line, so the M12 audit queue (paused) finds it later.
- `doc/code_map.md` updated; the log names the edges kept and why.

## Verify

- `python3 tools/code_graph.py --check doc/code_map.md` exits 0 on `main`; `python3 tools/check_docs.py` clean; the build and check commands of 0168.

## Specification (design, 2026-10-03)

### The check on `main` at `fc42846`

`python3 tools/code_graph.py --check doc/code_map.md` exits 1 with six edges new or grown (one more than the Goal lists: world to loop is new, and world to simulation and content to simulation grew further with 0201). The references were found by running the script's own resolution per reference on `fc42846` and on `e9090bf` (the 0179 commit that last set the counts) and diffing them; each total below matches the check.

| Edge | Recorded, now | References that grew it (file:line, symbol, item) |
|---|---|---|
| world to simulation | 232, 239 | `save_state.odin`:172 `write_machine_wear_table`, :459 `read_machine_wear_table`, :605 `refresh_all_founded`, :325 and :326 `MACHINE_BROKE_DOWN_KEY` (0201, `67ad45a`); `save_remap.odin`:216 `Simulation_Content` (`content_former_ids`), :267 `MACHINES_FILE_NAME` (`former_id_file_name`) (0196, `6e187aa`) |
| content to simulation | 101, 108 | `data_load.odin`:535 `MAXIMUM_BARE_GROUND_FLATNESS_MILLIMETRES`, :536 `MAXIMUM_BARE_GROUND_LIFE_MINUTES`, :90 and :536 `bare_ground_life_minutes` (the `Game_Config` field, named like the procedure in `machine_wear.odin`, noise) (0201); `data_reload.odin`:77 `field_pad_foundation_problem`, :106 `crafting_station_recipes_problem`, :107 `MACHINES_FILE_NAME` (0196) |
| content to world | 93, 97 | `data_planet.odin`:33, :182, :190 `MILLIMETRES_PER_METRE` (0189, `83391f9`); `data_reload.odin`:110 `content_former_id_problem` (0196) |
| simulation to ui | 42, 44 | `simulation_field.odin` `without_field_interact_jump`, its `Input_Frame` parameter and result (0194, `4ce7683`) |
| ui to loop | 9, 10 | `touch_overlay.odin`:1825 `lockstep_view_player` in `touch_interaction_frame` (0194) |
| world to loop | none, 1 | `save_remap.odin`:241 `Game_Content`, the parameter of `content_former_id_problem` (0196) |

### Decisions

Refactored away (two moves, behaviour byte for byte):

1. The bare ground bounds are the bounds of `data/game.sjson` values, checked by `bare_ground_problem` in `data_load.odin`, as the planet file's bounds live in `data_planet.odin`. Move the comment line and the two constants from `machine_wear.odin` lines 21 to 23 (`// The bounds of data/game.sjson's bare ground values (bare_ground_problem).`, `MAXIMUM_BARE_GROUND_FLATNESS_MILLIMETRES :: 2000`, `MAXIMUM_BARE_GROUND_LIFE_MINUTES :: 7 * 24 * 60`) unchanged into `data_load.odin`, directly above the comment of `bare_ground_problem` (line 531, `// Every value of the bare ground (0201) inside its bound;`), followed by one blank line. The remaining readers, `machine.odin`:593 and :594 and the `#assert` of `machine_wear.odin`:37, then reference content from simulation, which the table allows. Content to simulation loses 2.
2. `content_former_id_problem` (`save_remap.odin`:241) takes `Game_Content`, a loop type, but reads only its `simulation_content`. Narrow the parameter: `content_former_id_problem :: proc(content: Simulation_Content) -> string`, its two first lines `former := content_former_ids(content)` and `current := content_tables(content)`; the caller `data_reload.odin`:110 passes `content.simulation_content`; `save_remap_test.odin`:416, :420 and :425 pass `content`, `clashing` and `twice` directly instead of wrapping them in `Game_Content{simulation_content = ...}`. The world to loop edge disappears; world to simulation gains 1 (`Simulation_Content` in the signature).

Re-recorded (each is the kind of reference the record already accepts):

- world to simulation 240: the wear table and `refresh_all_founded` are the save codec writing and rebuilding simulation state, as the frame and field tables before them; the toast key sits in `known_message_key` beside the other saved message keys; the former ids are the content remap of the save, which already reads `Simulation_Content`.
- content to simulation 106: the foundations' load checks are registry cross links, as the torch check of 0179; the field name is graph noise, recorded like the `block_name` noise.
- content to world 97: `MILLIMETRES_PER_METRE` is the field's unit, read by every cluster; the relief bound converts the planet record's metres with it. The content load calling `content_former_id_problem` is the load's validation of a table the save remap owns.
- simulation to ui 44: one more procedure of the tick taking the tick's input type, as 0179's.
- ui to loop 10: the tap target reads the predicted player the HUD shows. Removing it would mean the loop computes the target into `Touch_Overlay_Context`, which moves when the read happens in the frame: not a pure move, left to the paused audit queue.

### Files

- `src/machine_wear.odin`: delete lines 21 to 23.
- `src/data_load.odin`: insert those three lines and a blank line before line 531.
- `src/save_remap.odin`: lines 241 to 243 as in decision 2.
- `src/data_reload.odin`: line 110, `content_former_id_problem(content.simulation_content)`.
- `src/save_remap_test.odin`: lines 416, 420, 425 as in decision 2.
- `doc/code_map.md`, the four record lines. Each replacement below is exact; the rest of each line stays.
  - Line 113 (ui): `loop 9 (accepted 3: ... 0158; accepted 6:` becomes `loop 10 (accepted 3: ... 0158; accepted 1: `touch_interaction_frame` reads the tap's aimed frame cell from the predicted field player through `lockstep_view_player`, 0194; accepted 6:`.
  - Line 151 (world): `simulation 232 (accepted 225:` becomes `simulation 240 (accepted 233:`; `simulation_day_ticks` 220, of which` becomes `... 228, of which`; after `read for the field flag 2 (0179),` insert ` the machine wear table (`write_machine_wear_table`, `read_machine_wear_table`), `refresh_all_founded` after a load and the saved toast key `MACHINE_BROKE_DOWN_KEY` in `save_state.odin` 5 (0201), the former ids in `save_remap.odin` (`content_former_ids` and `content_former_id_problem` on `Simulation_Content`, `MACHINES_FILE_NAME` in the load's error line) 3 (0196),` before ` `vein_is_exhausted` 1`.
  - Line 195 (simulation): `ui 42 (` becomes `ui 44 (`; `of which `field_tick_input` and `field_frame_turn` 8, 0179)` becomes `of which `field_tick_input` and `field_frame_turn` 8, 0179, and `without_field_interact_jump` 2, 0194)`.
  - Line 248 (content): `world 93 (accepted:` becomes `world 97 (accepted:`; `deep stone band 1)` becomes `deep stone band 1, the relief bound in `data_planet.odin` reading the field's `MILLIMETRES_PER_METRE` 3 (0189), the content load calling the former id check `content_former_id_problem` of `save_remap.odin` 1 (0196))`; `simulation 101 (accepted 92:` becomes `simulation 106 (accepted 97:`; `torch check loading with the tables 5 (0179);` becomes `torch check loading with the tables 5 (0179), the foundations' load checks `crafting_station_recipes_problem` and `field_pad_foundation_problem` with a `MACHINES_FILE_NAME` error line 3 (0196), the `Game_Config` field `bare_ground_life_minutes` named like the wear's procedure 2 (0201, noise);`.
- `doc/log/2026-10-03.md`: a paragraph at the end, below.

No other doc names the moved constants (`doc/content.md` names `bare_ground_problem` only, which stays), so no other doc changes.

Design check: these edits applied to a scratch copy of `src/` and `doc/code_map.md` give `17 edges against the table, 682 references, 0 new or grown` and exit 0; `tools/check_docs.py` finds nothing in `doc/code_map.md`.

### Log entry

```
## The code map's grown edges (0208)

Tags: code_map, audit

The items of 2026-10-03 grew six cluster edges without the check running. Two references were misplaced and moved: the bare ground bounds now sit beside `bare_ground_problem` in `data_load.odin`, and `content_former_id_problem` takes `Simulation_Content` instead of the loop's `Game_Content`, which ends the new world to loop edge. The rest are re-recorded: the wear table, `refresh_all_founded`, the saved toast key and the former ids are the save codec reading simulation state as before (world to simulation 240); the foundations' load checks are registry cross links and a `Game_Config` field named like a procedure is graph noise (content to simulation 106); the relief bound reads the field's `MILLIMETRES_PER_METRE` and the load calls the former id check (content to world 97); `without_field_interact_jump` takes the tick's `Input_Frame` (simulation to ui 44); the touch overlay's tap target reads `lockstep_view_player` (ui to loop 10), since moving that read into the loop changes when it happens in the frame, which is the paused audit queue's work.
```

### Tests and verify

No new test; the three `save_remap_test.odin` calls change with the signature. Run `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py` (clean) and `python3 tools/code_graph.py --check doc/code_map.md` (exit 0).

Items 0199 (crater; world and simulation) and 0209 (test leaks) are in worktrees now and may land first with references of their own. The implementer reruns the check on its own tree after rebasing onto `main`, and records any newer edge the same way: a misplaced constant or a parameter wider than it reads is moved, anything else is named with its item in the cluster's record and its count raised; the log paragraph names it.

### Hand-back check

None of the lines applies: nothing frees memory, writes a file, parses a number, changes a save layout, joins a shared budget or touches the UI.

### Open questions answered

- The `bare_ground_life_minutes` noise could end by renaming the procedure in `machine_wear.odin`; a rename is outside a move only item, so it is recorded as noise, like `block_name`.
- Moving `content_former_id_problem` and `former_id_file_name` into the content cluster instead would end world to loop too, but adds about five content to world references (`content_former_ids`, `content_tables`, `Content_Table`, `content_table_names`) and one content to loop; narrowing the parameter costs one.
- `MILLIMETRES_PER_METRE` stays in `world_field.odin`: every cluster reads it, and moving the field's unit into content to save three references would misplace it instead.

### For the main agent

- Decision 2 changes a signature rather than moving a procedure. It keeps behaviour byte for byte; approve it, or re-record world to loop 1 instead (`content_former_id_problem` on `Game_Content`, 0196).
- The new references are filed as "accepted" with their item number, as 0179 did, though no audit names them yet. Say if they should carry another label.

### Approval (main agent, 2026-10-03)

Approved. Decision 2 stands: narrowing a parameter to the type the procedure reads keeps behaviour byte for byte and is within a moves only item. The new references carry "accepted" with their item number, as 0179's do; the paused audit queue (0163 and later) is where a label changes. 0209 landed before this item (test files only, no new edge); 0199 is still in its worktree, so the implementer reruns the check on its own tree as the specification says.
