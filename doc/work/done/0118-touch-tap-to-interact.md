# 0118: Tap to interact on the touch screen

Status: implemented

## Goal

The second part of the touch overlay the user approved on 2026-09-29 ("i like all your recommendations, lets do it"), left out of 0115 by mistake. Bedrock's touch scheme: interaction goes through the world, not buttons. Hold a finger on a block to break it, tap a block or a machine to place or use, and the break progress is drawn on the block, since no button gives feedback. The crosshair scheme of 0115 (aim with the view, RT mines, LT places, A interacts) stays as the fallback, chosen in settings.

## Change

- A setting `touch_interaction` (`settings.odin`, the Accessibility tab next to Touch controls, `ui_screens.odin`; the configuration dump and its tests follow): `tap` (default) or `crosshair`. It matters only while the overlay drives the world (`touch_overlay_drives_world`).
- In tap mode a touch that begins on the free right half (the look zone) is undecided at first. It becomes the look drag once it moves more than a slop distance (`TOUCH_TAP_SLOP`, 12 pixels at 1080 high, scaled like the layout) before the hold delay. It becomes a hold once it rests for `TOUCH_HOLD_SECONDS` (0.25): while it holds, the overlay presses the look element's `hold_control` (`RIGHT_TRIGGER`, Mine through the bindings) and the aim is the touched point. It is a tap when it lifts before either: the overlay aims at the point until a simulation tick has run with the aim, then presses `tap_interact_control` (`SOUTH`, Interact) when that tick's target takes an interaction, else `tap_place_control` (`LEFT_TRIGGER`, Place), until a tick has run with the press. The three controls are keys of the `look` element in `data/touch_overlay.sjson`, validated like a button's `control`. A lift while a tap is in flight or while another finger holds starts no tap, and a tap that waits longer than `TOUCH_HOLD_SECONDS` for a tick is dropped. The left half keeps the stick. This keeps the project rule that a world action reaches touch through a gamepad binding: the overlay emits controls, never actions.
- The aim: `Input_Frame` gets `aim_direction: [3]f32` and `aim_overrides: bool`, set by the frontend (`touch_aim_direction`): the render camera's ray through the aim point (`rl.GetScreenToWorldRayEx`) is cast against the world, and the direction from the eye to the hit point (or the ray's far end) goes into the frame, so third person aims at the block under the finger. `player.target` (`tick_player`) uses that direction instead of the look direction while it is set, and keeps it as `Player.target_direction` for the slab half. The simulation stays deterministic: the direction arrives in the input frame like the look delta does. For the tap's decision the frontend hands the overlay whether the last tick's `players[0].target` takes Interact (`entity_takes_interact`, composed of the predicates `resolve_interact` and `resolve_use_item` act on, so both agree).
- The crosshair is not drawn in tap mode while the overlay is on in a world, and the mining progress is a ring around the mined block's screen position (`rl.GetWorldToScreenEx` of the block centre, `draw_mining_ring` in `hud.odin`) instead of the bar above the crosshair. In crosshair mode everything draws as today.
- `doc/input.md` touch overlay section: the two schemes and the tap, hold and drag thresholds. `doc/log/<date>.md`: the decision, including why the overlay presses gamepad controls and not actions.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a rest becomes a hold that presses Mine with the aim at the point; a move before the delay becomes the look drag and presses nothing; a lift before both presses Interact on an interactable target and Place otherwise; crosshair mode leaves the right half as the look drag; the setting round trips through the configuration dump.
- The user, on the phone: hold on a block to dig it with the ring, tap a stone to place the selected block, tap a machine to open it; switch to crosshair in settings and get 0115's scheme back.

## Implemented

- Deviations from the first draft of this item, which the Change section above now describes:
- A tap does not press on "the next frame". It waits for ticks (`advance_touch_tap`, fed `frame_tick_count > 0`): Interact acts only while in `pressed` during a tick, and on a display faster than 60 Hz a single frame often runs no tick, so a one frame press could be lost.
- `draw_mining_progress` keeps the bar; the ring is a new `draw_mining_ring`. It needed an arc draw command (`.Arc`, `draw_arc`, `ui_core.odin`, `ui_widgets.odin`, `ui_draw.odin`, and the audit switch in `ui_audit_test.odin`).
- Interact is handled in two places, so the predicate `entity_takes_interact` composes `entity_has_panel` (`resolve_interact`) and a new `schematic_crate_takes_interact` (`schematic.odin`, `resolve_use_item`).
- `Player.target_direction` was added: the slab half placement computed the hit point from the look direction, which is wrong under a touch aim.
- The render camera is kept in `Frame_State.render_camera` (set in `draw_session_world`): the aim uses the previous frame's camera, the ring this frame's.
- The crosshair is hidden whenever the overlay is on in a world in tap mode, also under an open screen, so it does not come and go as screens open.
- Review fixes: the third person aim through the world, no overlapping taps, no tap during a hold (and a hold that begins mid tap drops the tap), the stale tap drop, and the controls in data.
- Also touched: `doc/ui.md` (the Accessibility tab's row count, the Touch aiming row, the ring).
