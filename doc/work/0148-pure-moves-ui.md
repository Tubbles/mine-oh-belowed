# 0148: Pure moves, ui

Status: todo

## Goal

Queue entry 1 of the architecture audits, the ui half (`doc/audit/ui.md`, refactors 1 and 2; the small misplacements of `doc/work/0144-code-map.md`'s notes). No behaviour change.

## Change

- The layout procedure `column` (`ui_core.odin`, 39 call sites in 8 files) gets a name that no local shares, such as `column_rectangle`; 148 references into the ui cluster were this collision.
- Toolkit pieces out of the screen files: the four identical row helpers (`settings_row`, `choice_row`, `developer_row`, `title_row`) become one in `ui_widgets.odin`; `Scroll_List` and its procedures, `wrap_text`, `take_line`, `draw_wrapped`, `detail_line`, `panel_height` move to `ui_widgets.odin`; `format_game_time` to `ui_format.odin`; `target_status_lines` and its helpers to `hud.odin`.
- The types the platform pairs reach up for move down so the pairs can leave the game package later: `Haptic_Request` and the rumble constants into a `haptics.odin` shared by the two haptics files; the system keyboard's rectangle parameter takes a plain `[4]f32` or a type defined beside the keyboard files instead of `Ui_Rectangle`, with `ui_keyboard.odin` converting.
- The small misplacements the map's borders exposed: `enum_label`, `first_letter`, `shipment_cargo_text`, `STEAM_DECK_ENVIRONMENT_VARIABLE`, `store_unsigned` each move to the cluster that owns them (0144 notes name the edges).
- `doc/code_map.md` records lowered, `doc/ui.md` where it names a moved procedure.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (1290 tests; the UI audit `ui_audit_test.odin` draws every screen), `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
