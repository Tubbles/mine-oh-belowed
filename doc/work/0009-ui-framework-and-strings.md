# 0009 UI framework and strings

Status: todo
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
