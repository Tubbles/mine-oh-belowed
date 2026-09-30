# 0118: Tap to interact on the touch screen

Status: todo

## Goal

The second part of the touch overlay the user approved on 2026-09-29 ("i like all your recommendations, lets do it"), left out of 0115 by mistake. Bedrock's touch scheme: interaction goes through the world, not buttons. Hold a finger on a block to break it, tap a block or a machine to place or use, and the break progress is drawn on the block, since no button gives feedback. The crosshair scheme of 0115 (aim with the view, RT mines, LT places, A interacts) stays as the fallback, chosen in settings.

## Change

- A setting `touch_interaction` (`settings.odin`, the Accessibility tab next to Touch controls, `ui_screens.odin`; the configuration dump and its tests follow): `tap` (default) or `crosshair`. It matters only while the overlay drives the world (`touch_overlay_drives_world`).
- In tap mode a touch that begins on the free right half (the look zone) is undecided at first. It becomes the look drag once it moves more than a slop distance (`TOUCH_TAP_SLOP`, about 12 render pixels at 1080 high, scaled like the layout) before the hold delay. It becomes a hold once it rests for `TOUCH_HOLD_SECONDS` (0.25): while it holds, Mine is pressed and the aim is the touched point. It is a tap when it lifts before either: a single press of Interact when the target under it takes one (a machine, an entity, a block with an interaction), else a single press of Place. The left half keeps the stick. `Touch_Overlay_Frame` gains the aim point (render pixels) and the tap or hold state; `Touch_Overlay_Output` presses the actions, not gamepad controls, since Mine and Place are triggers on the gamepad and a tap is not a trigger pull: `Input_Frame` gets `aim_direction: [3]f32` and `aim_overrides: bool`, set by the frontend from the render camera's ray through the aim point (`rl.GetScreenToWorldRay`), and `player.target` (`player.odin:476`) uses that direction instead of the look direction while it is set. The simulation stays deterministic: the direction arrives in the input frame like the look delta does.
- The crosshair is not drawn in tap mode while the overlay drives the world, and the mining progress is a ring around the mined block's screen position (`rl.GetWorldToScreen` of the block centre, `draw_mining_progress` in `hud.odin` gets the position) instead of the bar above the crosshair. In crosshair mode everything draws as today.
- `doc/input.md` touch overlay section: the two schemes and the tap, hold and drag thresholds. `doc/log/<date>.md`: the decision, including why the actions are pressed directly.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a rest becomes a hold that presses Mine with the aim at the point; a move before the delay becomes the look drag and presses nothing; a lift before both presses Interact on an interactable target and Place otherwise; crosshair mode leaves the right half as the look drag; the setting round trips through the configuration dump.
- The user, on the phone: hold on a block to dig it with the ring, tap a stone to place the selected block, tap a machine to open it; switch to crosshair in settings and get 0115's scheme back.
