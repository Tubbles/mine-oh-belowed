# 0151: Glyphs follow the bindings

Status: implemented

## Goal

`glyph_key` and `glyph_icon` (`ui_widgets.odin`) take a device and a button but no bindings, so after a rebinding in the configuration the glyph bar and the button glyphs keep showing the default control (ui audit, claim 3; `SUGGESTIONS.md`).

## Change

- The glyph lookups take the active bindings and show the control bound to the action: the first binding when an action has several (decision: the first; all of them would not fit the glyph bar). The keyboard glyph is the bound key's label, the gamepad glyph the bound button's icon.
- `doc/input.md` (bindings) and `doc/ui.md` (glyph bar) state that glyphs show the bound control.

## Verify

- A test rebinds an action in a temporary configuration, builds the glyph for it and checks the glyph changed; the UI audit still draws every screen.
- `./build.sh check`, `./build.sh test`, `python3 tools/check_docs.py`.

## Implementation notes

- Shape found: `Glyph_Button` (`ui_widgets.odin`) enumerated 14 logical buttons, every one standing for an action (Confirm, Back, tabs, Info_Panel, Context_Action, Pause, Open_Inventory, Menu_Secondary, Interact, Use_Item, Sprint, Menu_Quick_Move, Menu_Drop). A screen passes `Glyph_Hint`s to `ui_glyph_bar`, which asked `glyph_key` (a string key per device and button, `glyph_gamepad_*` and `glyph_keyboard_*` in `en.sjson`) and `glyph_icon` (a fixed pad icon per button). Nothing else called them. The effective `[]Binding` lived on `Frame_State.bindings` (and `Screen_Context.bindings` for the Bindings tab), not on `Ui_State`.
- Change: `Ui_State` carries `bindings` and `input_backend`, set by `run_ui_frame` before every UI pass, so no widget call gained a parameter. `glyph(state, button)` replaces both lookups: `glyph_action` names the action, `first_binding_on_device` takes its first binding on the active device (gamepad, or keyboard and mouse) and backend, `gamepad_control_icon` gives the pad icon where the control has one, else a key cap with `control_label`. Labels: the string table for the names that read poorly (`control_label_keys`: Enter, Esc, Shift, Ctrl, the mouse buttons), the control's name otherwise (`readable_control_name`, `PAGE_DOWN` as Page Down). An action with no control on the device shows `glyph_unbound` ("?"). The old `glyph_gamepad_*` and `glyph_keyboard_*` strings are gone.
- No fixed glyphs: every `Glyph_Button` is an action. Two map to another action on the keyboard so the defaults keep their glyphs: Back shows Pause (Esc, which steps back a screen as Back does in `handle_screen_keys`; Back's own key is Backspace) and Sprint shows `Sprint_Hold` (Ctrl). The default glyphs are unchanged on both devices.
- Pad controls without an icon (paddles, MISC buttons, GUIDE, TOUCHPAD) show their name on a key cap (`LEFT_PADDLE1` as Left Paddle 1, `F3` stays); the four d-pad directions share the `Dpad` icon.
- Tests: `test_glyphs_follow_a_rebinding` (`ui_theme_test.odin`) rebinds Confirm and Info_Panel through a bindings text in the configuration's shape and checks the gamepad icon, the keyboard label (the first of two bindings), a paddle's key cap and the unbound glyph. `test_glyph_icon_per_button_and_device` and `test_glyph_bar_draws_icons_and_key_caps` now run on the shipped bindings; the UI audit's states carry the shipped bindings.
- Review (one medium, four low), fixed:
  - Medium: on raylib a binding without a `backend` key counted as readable, so a paddle listed first showed a cap for a control that does nothing there. `raylib_reads_gamepad_control` (`bindings.odin`) is now the one test `bind_gamepad_control` and the glyph lookup (`binding_on_backend`) share.
  - The keyboard's Back and Sprint fall back to their own action (Back's Backspace, Sprint) when Pause or `Sprint_Hold` has no key.
  - `data_strings_test.odin` scans `ui_widgets.odin`, so `glyph_unbound` is checked.
  - `readable_control_name` spaces a trailing number after more than one letter; the mouse's SIDE, EXTRA, FORWARD and BACK have labels with "mouse" in them.
  - `test_glyph_icon_per_button_and_device` pins all 14 buttons on both devices and both backends to the pre-0151 glyphs: the old icons on the gamepad and the old `glyph_keyboard_*` texts on the keyboard, read from the shipped string table. (The old `glyph_gamepad_*` texts were never drawn, the gamepad drew only icons.) `test_glyphs_follow_a_rebinding` runs the paddle on SDL3, skips it on raylib, and checks the Back fallback; `test_readable_control_names` covers the names.
