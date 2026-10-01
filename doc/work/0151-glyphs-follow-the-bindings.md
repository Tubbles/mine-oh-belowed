# 0151: Glyphs follow the bindings

Status: todo

## Goal

`glyph_key` and `glyph_icon` (`ui_widgets.odin`) take a device and a button but no bindings, so after a rebinding in the configuration the glyph bar and the button glyphs keep showing the default control (ui audit, claim 3; `SUGGESTIONS.md`).

## Change

- The glyph lookups take the active bindings and show the control bound to the action: the first binding when an action has several (decision: the first; all of them would not fit the glyph bar). The keyboard glyph is the bound key's label, the gamepad glyph the bound button's icon.
- `doc/input.md` (bindings) and `doc/ui.md` (glyph bar) state that glyphs show the bound control.

## Verify

- A test rebinds an action in a temporary configuration, builds the glyph for it and checks the glyph changed; the UI audit still draws every screen.
- `./build.sh check`, `./build.sh test`, `python3 tools/check_docs.py`.
