# 0009 UI framework and strings

Status: implemented
Milestone: M2

## Goal

The immediate mode UI described in `doc/ui.md`, with strings from data and unit formatting, proven by a pause menu and a settings screen that work with focus navigation and the pointer alike.

## Deliverables

- `Ui_State` and the `ui_begin`, widget, `ui_end` cycle with a deferred draw list, UI units scaled from screen height and a UI scale setting, the safe area, focus movement by spatial rule with wrapping inside a panel, pointer hover setting focus, stick repeat timing, and a screen stack over the HUD.
- Widgets: label, button, toggle, slider, tabs, vertical list with letter jump hook, grid of slots (empty for now), progress bar, tooltip panel on Y, glyph bar showing the active device's glyphs, toast.
- Radial menu widget driven by a touchpad position or the right stick, using `radial_slot_from_touchpad`, with a dead centre.
- `data/strings/en.sjson` and a `text(key)` lookup that reports missing keys once to stderr and shows the key in the UI, plus `format_per_minute`, `format_power`, `format_volume`, `format_blocks`. The diagnostics screen may keep its literals.
- Pause menu (Menu button or Escape): resume, settings, quit to desktop. Settings: UI scale, gyro on or off, look sensitivity for stick, gyro and trackpad, invert pitch, stored in a `Settings` struct in memory for now (configuration files are a later item) and applied live.
- The pause menu pauses the simulation; the accumulator does not run catch up ticks on resume.
- Tests (headless): focus movement on a hand made set of rectangles (nearest in direction, wrapping, no candidate), UI unit scaling, stick repeat timing, radial selection through the widget, string lookup with a missing key, every formatter at boundary values.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh`, `./build.sh release` pass.
- User: open the pause menu with the Menu button, change the UI scale and gyro sensitivity with the sticks alone, then again with the right trackpad alone, resume, and see the change applied.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `ui_core.odin` (state, ids, frame cycle, focus rule, repeat, pointer, layout helpers, screen stack), `ui_widgets.odin` (widgets, glyph bar, tooltip, toasts, radial), `ui_draw.odin` (the only UI file that calls raylib), `ui_input.odin` (`Ui_Input` from two input frames, device detection), `ui_screens.odin` (pause and settings), `ui_format.odin`, `data_strings.odin`, `settings.odin`, `hud.odin`, `data/strings/en.sjson`.

### Deviations

- Look sensitivities are applied in the input layer, not inside `turn_fly_camera`. The turning code runs in the simulation tick, and `Settings` is frame state; routing settings into the tick would make the simulation read something other than its input. `apply_look_settings` scales the stick rate and inverts pitch before the frame reaches the simulation, and the SDL3 backend scales the trackpad and gyro deltas (and skips the gyro when it is off). The constants in `render_fly_camera.odin` and `input_sdl3.odin` are now base rates at multiplier 1.
- Activation is decided inside the widget call (Confirm on last frame's focus, or a click hit tested against this frame's rectangle), so widget results are not delayed. Only focus moves have the one frame latency: `ui_end` resolves them, the highlight is drawn in the same frame (focus outline commands are styled at execution time), and widgets see the new focus next frame.
- The UI runs in `render_frame`, so a screen opened or closed takes effect on the world one frame later. `update_world_action_guard` keeps a world action that was held while a screen was open away from the world until it is released, so the A press on Resume does not jump.
- With a screen open, Pause steps back one screen like Back (Escape is Pause on the keyboard, so Escape backs out of Settings instead of closing everything). Back first closes an open info panel.
- New actions: `Navigate_Up/Down/Left/Right` (d-pad, arrow keys, R5 as d-pad up), `Tab_Previous/Tab_Next` (L1 R1, Q E), `Info_Panel` (Y, L5, R), `Context_Action` (X, F). R2 also produces Confirm. The right pad click stays bound to Confirm, but `make_ui_input` treats it as a pointer click (it confirms the focus only while the pointer is hidden).
- Tabs are not focus targets; the bumpers and the pointer switch them. Settings uses two tabs (Display: UI scale, pointer speed. Controls: gyro, three sensitivities, invert pitch). Pointer speed is an extra setting, because the brief asks for a configurable pointer speed.
- Unit symbols (`/min`, `kW`, `MW`, `L`, `kL`, `ML`) are literal in the formatters; only the block word comes from the string table. Volume shows whole litres below 1000 L and one decimal for kL and ML. Each formatter switches unit on the rounded value, so 999.96 kW reads 1.0 MW.
- `text(key)` reads a global table filled by `main`; `lookup_text` and `format_blocks_with` take a table so tests stay independent of it.
- The world overlay lines (developer text) stay in `diagnostics.odin`; only the crosshair moved to `hud.odin`, plus a glyph bar with the Pause hint.

### Constants

Repeat 350 ms then 80 ms. Stick navigation threshold 0.5. Perpendicular penalty 2. Pointer speed default 1.5 screen heights per pad width (range 0.5 to 3). UI scale 0.75 to 1.5 in steps of 0.05. Sensitivity multipliers 0.25 to 3 in steps of 0.05. Row height 56 units, padding 16, gap 8, focus border 4, slot 80, tooltip width 420, text 24, headings 32, glyph bar 28. Toasts: at most 4, 4 seconds each. Safe area 5 percent per side.

### Not verified

Everything visual and all feel: layout at 720p, 1080p and 4K, the default font scaled to 24 units, focus movement and repeat feel, trackpad pointer speed, slider dragging, the glyph bar switching between devices, the cursor behaviour when the pause menu opens and closes (raylib `EnableCursor` recentres the cursor; if that reports a mouse delta, hover would move the focus to the centre button), and the pause freezing the day cycle and water. The diagnostics screen lists eight more actions than before and may run off the bottom at 720p.

### Open questions

- Dragging the UI scale slider with the pointer rescales the UI under the pointer. Apply the scale on release instead?
- Should the unit symbols move into the string table as format patterns?
- Keyboard bindings for the info panel (R) and context action (F) are placeholders.
- `doc/input.md` ("Bindings implemented so far") and `doc/ui.md` (latency, sensitivities in the input layer, Pause as Back) need the updates above; this run could not touch them.
