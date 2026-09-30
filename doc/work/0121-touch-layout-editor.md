# 0121: In game editor for the touch layout

Status: implemented

## Goal

Approved on 2026-09-29 (the spitball: buttons "drawn from `data/touch_overlay.sjson` so an editor can move, resize and rebind them later, with profiles"; Bedrock: "Every element has position, size and opacity in settings"), left out of 0115. The user edits the overlay on the phone: move, resize, set the opacity and rebind every element, keep several layouts and pick one.

## Change

- User layouts live in `touch_overlay.sjson` in the user configuration directory (`user_configuration_directory`, next to `config.d/`): `selected = "<name>"` and `layouts = [{name = "…", reference_height = …, elements = […]}]`, the element entries as in the data file plus `opacity` (0.1 to 1, default 1, also accepted in the data file). The data file's layout is the layout "Default", which cannot be edited or deleted, only copied. `load_touch_overlay` loads the data file, then the user file when present, and takes the selected layout; a broken user file is reported like a broken data file and the default is used. The file is written through `make_directory_path` (0117) and `os.write_entire_file`, whole, since arrays replace wholesale.
- The editor is a screen (`ui_touch_layout_editor.odin`, opened from a Touch layout row on the Accessibility tab; the row also cycles the selected layout): the current layout drawn full size over a dimmed background at the real scale, every element with a handle. A drag on an element moves it (its anchor stays; the position is recomputed from the anchor so the element keeps its corner). The selected element (tap) shows a panel: size (plus and minus, keeping a circle round), opacity (plus and minus in steps of 0.1), rebind (cycles through the controls `touch_overlay_control_from_name` knows, the label follows), and for the stick its radius and static flag (0120). Screen level actions: Save, Save as (a name through `ui_text_field` and the on screen keyboard), Delete (not Default), Reset to Default. The editor works with the pointer and with the gamepad's focus navigation (gamepad first: the d-pad moves the selected element by steps, the shoulders resize), so the couch can edit it with `--touch-overlay` too.
- A hot reload of the data file (`hot_reload.odin`, if the touch layout is watched) keeps applying to Default.
- `doc/input.md` touch overlay section: the user file, its keys, the editor; `doc/configuration.md` or wherever the configuration directory's files are listed names `touch_overlay.sjson`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: the user file round trips (write, load, same layout); the selected layout wins over Default; a user file with a bad element reports the problem and Default loads; a move keeps the anchor and recomputes the position; a rebind changes the control the button presses; `test_no_touch_overlay_element_covers_a_hotbar_slot` applies to Default only.
- The user, on the phone: move A, make it larger and more transparent, save as "Mine", relaunch and find it selected; reset to Default.

## Implemented

- Format, loading and writing: `src/touch_overlay.odin` (`Touch_Layouts`, `parse_touch_layouts_file`, `load_touch_layouts`, `touch_layouts_file_text`, `write_touch_layouts_file`, `active_touch_layout`, `opacity` on the element and in drawing), wired in `src/loop.odin` (`serve_touch_layouts`, loading at start, the overlay reading `frame_touch_layout`).
- Editor: `src/ui_touch_layout_editor.odin`, screen `Touch_Layout` (`src/ui_core.odin`), rows on the Accessibility tab (`src/ui_screens.odin`). Tests in `src/touch_overlay_test.odin` and `src/ui_touch_layout_editor_test.odin`, audit cases in `src/ui_audit_test.odin`.
- Deviation: `load_touch_overlay` still loads the data file only. The user file is loaded separately into frame state (`load_touch_layouts`), so a content reload replaces Default without touching the user's layouts; the overlay takes the selected one each frame. Same result, clearer ownership.
- Deviation: the Accessibility tab has two rows, Touch layout (steps the selection) and Edit touch layout (opens the editor), rather than one row doing both: Confirm cannot both step a choice and open a screen.
- Deviation: the look element is not shown or edited (it draws nothing and has no place); its keys, including `opacity`, round trip.
- Deviation: Save as takes the name from a Name field in the panel (`ui_text_field` with the on-screen keyboard), then the Save as button saves under it, as the new world screen's name and Create work. A name already in the file is replaced.
- Review fixes: the panel's Save, Save as, Delete and Reset are requests served by the frame loop between frames (serving them in the screen freed the draft's arena under that frame's text commands, a reproduced crash); a user layout needs a START button (loader and editor); a broken user file locks writes until the next start; a Double tap latches toggle for buttons; a resize or a switch to static is held to the screen like a move; one shared `ui_stepper` in `src/ui_widgets.odin` replaces the texture editor's seed stepper and the editor's own.
- Added: `Adjusts_Vertically` in `Ui_Widget_Flag` (`src/ui_core.odin`) so the d-pad moves the selected element instead of the focus.
- Docs: `doc/input.md` (Touch overlay, Layouts and the editor), `doc/ui.md` (Accessibility rows, the editor), `data/touch_overlay.sjson` (`opacity`, Default). There is no `doc/configuration.md`; the user directory's files are listed in `doc/architecture.md` and, for the phone, `doc/build.md`, which both name `touch_overlay.sjson` now.
- Not done: the phone check in Verify is the user's.
