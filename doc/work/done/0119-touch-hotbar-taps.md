# 0119: Hotbar taps on the touch screen

Status: implemented

## Goal

Approved on 2026-09-29 with the Bedrock recommendations, left out of 0115. The hotbar is touchable: a tap on a slot selects it, a long press on the selected slot drops its stack into the world as a loose item.

## Change

- The overlay learns the hotbar's slot rectangles in render pixels each frame (`hud_hotbar_rectangles`, `hud.odin`, converted with the UI scale; `test_no_touch_overlay_element_covers_a_hotbar_slot` already computes them for the tests). A touch that begins on a slot is role `.Hotbar` with the slot index, whether or not a screen is open (the hotbar shows in the world only, so in practice in the world). It presses nothing else: no stick, no look, no pointer click (`pointer_claimed`).
- A tap (lift within `TOUCH_HOLD_SECONDS` of 0118, or 0.25 s if 0119 lands first) presses the action `Hotbar_Slot_<n>` once. A long press on the selected slot presses a new world action `Drop_Stack`, bound also on the keyboard (Q) and on no gamepad control by default (`data/bindings.sjson`, the reference tables in `bindings_test.odin` follow), which drops the selected stack as `Menu_Drop` does from the inventory (`inventory_interaction.odin`). A long press on another slot selects it and does nothing more.
- `doc/input.md`: the hotbar taps and the new action. The key bindings table in `doc/input.md` or wherever the keyboard defaults are documented gains Q.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a tap on slot 3 presses `Hotbar_Slot_3` once and claims the pointer; a long press on the selected slot presses `Drop_Stack`; a long press on another slot selects it only; a tap on a slot while the stick is held changes nothing about the stick.
- The user, on the phone: tap slots to select, hold the selected slot to drop the stack.

## Implemented

- `src/touch_overlay.odin`: role `Hotbar` (`classify_touch`, ahead of the stick and the look halves, world only), `advance_hotbar_touch` (the slop, the long press), `lifted_hotbar_taps`; `update_touch_overlay` returns the frame's selected slot, which `touch_overlay_frame` puts into `Touch_Overlay_Frame.hotbar_tap`; `apply_touch_overlay_hotbar` is the one place that turns it into an action (called from `read_input_frame`, `src/loop.odin`). The long press on the selected slot holds the layout's `hotbar_drop_control` in the overlay's gamepad. `touch_interaction_frame` hands over the slot rectangles and the selected slot.
- `data/touch_overlay.sjson`: `hotbar_drop_control = "DPAD_DOWN"`, required and validated. `data/bindings.sjson`: `Drop_Stack` on gamepad `DPAD_DOWN` and keyboard X in the world.
- `src/hud.odin`: `hud_hotbar_pixel_rectangles`. `src/input_actions.odin`: `Drop_Stack`, a world action. `src/player.odin`: `tick_player` drops through `drop_player_stack` with the selected slot.
- Deviations:
  - `Drop_Stack` is on X, not Q: Q is Pipette in the world. X is the inventory's Drop already.
  - The drop goes through a gamepad control (d-pad down, `hotbar_drop_control`) instead of the overlay pressing the action, so a physical gamepad drops with d-pad down too; only the slot selection is pressed as an action.
  - A finger on the hotbar is the hotbar's in the world only, not also while a screen is open: the HUD's hotbar draws under screens too, and a claimed finger there would swallow the screen's clicks while the world strips the hotbar actions anyway.
  - A finger that moves past `TOUCH_TAP_SLOP` fires neither the tap nor the long press.
  - The selection reaches the input frame as a `just_pressed` edge only, without the 0118 tap's wait for a tick: it is read as an edge and the tick accumulator carries edges over tickless frames.
  - The long press fires while the finger is still down, once it has rested `TOUCH_HOLD_SECONDS`, not on the lift.
- Tests: `test_a_tap_on_a_hotbar_slot_selects_it_once_and_claims_the_pointer`, `test_a_long_press_on_the_selected_slot_drops_its_stack`, `test_a_finger_that_slides_off_the_selected_slot_fires_nothing`, `test_a_long_press_on_another_slot_only_selects_it`, `test_a_hotbar_tap_leaves_a_held_stick_alone`, `test_over_a_screen_a_hotbar_touch_is_the_pointers`, two `hotbar_drop_control` cases in `test_touch_overlay_errors_name_the_element` (`touch_overlay_test.odin`), `test_drop_stack_drops_the_selected_hotbar_stack_in_the_world` (`loose_item_test.odin`); the bindings reference tables gain d-pad down and X.
