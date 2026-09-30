# 0120: Static stick and double tap toggles in the touch layout

Status: todo

## Goal

Two Bedrock options approved on 2026-09-29 and left out of 0115: a static joystick for people who want the stick in a fixed place, and hold versus toggle per element in the layout data (Bedrock's double tap sneak to toggle it), on top of the `sneak_hold` and `sprint_hold` settings, which apply to every device.

## Change

- `data/touch_overlay.sjson`, stick element: `static = false` by default. A static stick has `anchor` and `position` like a button and draws its base ring at rest; a touch that begins inside its base circle drives it, centred on the base, a touch elsewhere on its half is ignored (it is not the look zone). `resolve_touch_overlay_stick` validates the keys (a static stick needs anchor and position, a floating one refuses them).
- Button element: `double_tap_toggles = false` by default. When true, a second tap on the button within `TOUCH_DOUBLE_TAP_SECONDS` (0.3) latches it down until the next tap; a single tap presses it as today. The shipped layout sets it on B (Sneak), so double tapping B toggles sneak while the sneak setting is Hold. `draw_touch_overlay_button` draws a latched button filled like a held one.
- `doc/input.md` and the comment block at the top of `data/touch_overlay.sjson`: both keys.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a static stick reads a touch inside its base and ignores one outside; a double tap latches B and the next tap releases it; a single tap presses and releases; a floating stick with a position fails to load with the element named.
