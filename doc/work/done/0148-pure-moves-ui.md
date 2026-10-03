# 0148: Pure moves, ui

Status: implemented

## Goal

Queue entry 1 of the architecture audits, the ui half (`doc/audit/ui.md`, refactors 1 and 2; the small misplacements of `doc/work/done/0144-code-map.md`'s notes). No behaviour change.

## Change

- The layout procedure `column` (`ui_core.odin`, 39 call sites in 8 files) gets a name that no local shares, such as `column_rectangle`; 148 references into the ui cluster were this collision.
- Toolkit pieces out of the screen files: the four identical row helpers (`settings_row`, `choice_row`, `developer_row`, `title_row`) become one in `ui_widgets.odin`; `Scroll_List` and its procedures, `wrap_text`, `take_line`, `draw_wrapped`, `detail_line`, `panel_height` move to `ui_widgets.odin`; `format_game_time` to `ui_format.odin`; `target_status_lines` and its helpers to `hud.odin`.
- The types the platform pairs reach up for move down so the pairs can leave the game package later: `Haptic_Request` and the rumble constants into a `haptics.odin` shared by the two haptics files; the system keyboard's rectangle parameter takes a plain `[4]f32` or a type defined beside the keyboard files instead of `Ui_Rectangle`, with `ui_keyboard.odin` converting.
- The small misplacements the map's borders exposed: `enum_label`, `first_letter`, `shipment_cargo_text`, `STEAM_DECK_ENVIRONMENT_VARIABLE`, `store_unsigned` each move to the cluster that owns them (0144 notes name the edges).
- `doc/code_map.md` records lowered, `doc/ui.md` where it names a moved procedure.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (1290 tests; the UI audit `ui_audit_test.odin` draws every screen), `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`.

## Implementation notes

- Rename: `column_rectangle`, the definition and 39 call sites in 8 files (plus one in `ui_core_test.odin`). The remaining whole word `column` hits under `src/` are locals, fields and comments.
- Row helpers: the four were identical (cut `UI_ROW_HEIGHT` off the top, then `UI_GAP`); one `cut_row` in `ui_widgets.odin`, every call site follows.
- Moves into `ui_widgets.odin`: `panel_height` (from `ui_screens.odin`), `take_line`, `wrap_text`, `draw_wrapped` (from `ui_journal.odin`), `detail_line` (from `ui_power.odin`), `Scroll_List` with `scroll_list_begin`, `scroll_list_row`, `scroll_list_keep_visible`, `scroll_list_end` (from `ui_recipes.odin`). `format_game_time` into `ui_format.odin`. Into `hud.odin` from `ui_machine.odin`: `target_status_lines` and the helpers only it and the HUD call, `entity_status_text`, `bore_drill_ghost_line`, `vein_status_text`, `vein_size_class_name`.
- Haptics: `Haptic_Request`, `HAPTIC_RUMBLE_MILLISECONDS`, `rumble_level` and `vibration_amplitude` from `input_actions.odin` into `haptics.odin` (all targets); `test_vibration_amplitude_follows_the_strength` into `haptics_test.odin`.
- System keyboard: `System_Keyboard_Field` in `system_keyboard.odin` (all targets), a field copy of `Ui_Rectangle`'s four floats; `show_system_keyboard` and `steam_keyboard_link` take it. The one caller is `sync_system_keyboard` in `loop.odin` (not `ui_keyboard.odin`), which converts after `units_to_window_rectangle`.
- Misplacements, each to the lower of its users' clusters: `enum_label` from `diagnostics.odin` (tools) to `input_actions.odin` (ui, its only users are the input backends); `first_letter` from `ui_recipe_browser.odin` to `production_statistics.odin` (simulation); `shipment_cargo_text` from `ui_launch_pad.odin` to `launch_pad.odin` (simulation); `store_unsigned` from `save_binary.odin` (world) to `configuration.odin` (content).
- Not moved: `STEAM_DECK_ENVIRONMENT_VARIABLE`. Its users are `deck_preset.odin` (content) and `system_keyboard_linux.odin` (ui since 0145), and content is the lower of the two, where it already is; the platform -> content edge the 0144 notes named went away when 0145 moved the keyboard files out of the platform cluster.
- `tools/code_graph.py --check doc/code_map.md` before: 18 edges, 805 references, 0 new or grown. After: 17 edges, 654 references, 0 new or grown. Edges cut: world -> ui 117 to 0 (gone), simulation -> ui 45 to 29, presentation -> ui 28 to 17 (the `column` noise, `first_letter`, `shipment_cargo_text`), ui -> tools 49 to 43 (`enum_label`), content -> world 94 to 93 (`store_unsigned`). The map's records are lowered to match, and its file counts and line counts follow.
- `doc/audit/ui.md` names the merged helpers without backticks and points at `cut_row`, as 0145 did for renamed names; `doc/android.md` names `haptics.odin` for `vibration_amplitude`.
