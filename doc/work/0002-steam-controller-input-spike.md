# 0002 Steam Controller input spike

Status: todo
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
