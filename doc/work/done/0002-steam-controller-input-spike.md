# 0002 Steam Controller input spike

Status: implemented
Milestone: M0

## Goal

Decide the controller path (see `doc/input.md`): confirm that SDL3 reads the Steam Controller (2026) directly on the couch machine, with Steam running and Steam Input disabled for the game.

## Deliverables

- SDL3 input backend in `src/` (joystick, gamepad and sensor subsystems only, no SDL video) feeding the action layer from 0001.
- The diagnostics screen shows: both sticks with capacitive touch state, both trackpads with position, pressure and click, gyro and accelerometer, grip sense, L4 L5 R4 R5, all face and system buttons the driver reports.
- Findings written into `doc/input.md` (replace the "Spike questions" paragraph with answers) and a decision entry in `doc/log/`.

## Verify

- Builds and tests pass as in 0001.
- User, on the couch: with the game launched from Steam and Steam Input disabled for the shortcut, every input listed above moves on the diagnostics screen, over the puck and over Bluetooth.
- If SDL3 does not see the controller, document why and switch `doc/input.md` to the fallback path.

## Notes

Implemented 2026-09-27 by an agent without a display or controller: `odin check`, `odin test` and both builds pass, and a run without a display printed `input: sdl3 backend (default)` before raylib failed to open its window. Nothing that reads the controller has run yet.

- Code: `src/input_sdl3.odin` (backend), `Raw_Input` extended in `src/input_actions.odin` with touchpads, gyro, accelerometer and touch sense, `--input=sdl3|raylib` in `src/main.odin` (default SDL3 with raylib fallback), a third diagnostics column in `src/diagnostics.odin`. Keyboard and mouse come from raylib under both backends because SDL runs without video.
- What SDL 3.4.16 reports and where in its source: `doc/input.md`, "How SDL3 exposes the controller". The couch test steps, including how to disable Steam Input for the shortcut: `doc/input.md`, "Couch test checklist".
- Not verified: that SDL sees the controller with Steam running, over the puck, over Bluetooth; the gyro and accelerometer axis signs; the touchpad range and pressure range; whether Menu and View are swapped by the driver; the look sensitivities (`TOUCHPAD_LOOK_PIXELS_PER_PAD_WIDTH`, `GYRO_LOOK_PIXELS_PER_DEGREE`, placeholders); that the three diagnostics columns fit at 1080p without overlap.
- Gyro look is scaled by the frame time, not by the sensor timestamps SDL keeps, which is enough for the spike.
- Actions from the `doc/input.md` table that the `Action` enum still lacks, so their inputs are unbound: Interact (right pad click is bound to Confirm only), Sort, Info panel, previous and next hotbar slot (d-pad left and right, L1 and R1), Drop (d-pad down), Close all, the L2 secondary action and list scrolling. Sprint is bound as held, not as the toggle the table describes.
- Still open for this item: answers to the spike questions in `doc/input.md` and a decision entry in `doc/log/`, both after the couch test.
