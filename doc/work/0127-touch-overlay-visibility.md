# 0127: Wider, more visible touch overlay lines

Status: implemented

## Goal

The user, on the phone (2026-09-30): "make the gamepad overlay lines wider, they are basically impossible to see now."

## Change

- `src/touch_overlay.odin`: `TOUCH_OVERLAY_LINE` from 2 to 4 UI units and the base colour's alpha from 89 to 140 (about 55 percent white). The per element `opacity` of 0121 still multiplies it, so a layout can dim elements again.
- The comment above the constants and `doc/input.md`'s drawing sentence follow.

## Verify

- `./build.sh check`, `./build.sh test` (the colour tests compare against the constant).
- The user, on the phone.

## Implemented

2026-09-30, by the main agent (a constant change). `TOUCH_OVERLAY_LINE` 2 to 4, the base alpha 89 to 140; `doc/input.md`'s drawing sentence names both values. The colour tests compare against the constants and pass unchanged.
