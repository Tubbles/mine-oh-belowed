# 0119: Hotbar taps on the touch screen

Status: todo

## Goal

Approved on 2026-09-29 with the Bedrock recommendations, left out of 0115. The hotbar is touchable: a tap on a slot selects it, a long press on the selected slot drops its stack into the world as a loose item.

## Change

- The overlay learns the hotbar's slot rectangles in render pixels each frame (`hud_hotbar_rectangles`, `hud.odin`, converted with the UI scale; `test_no_touch_overlay_element_covers_a_hotbar_slot` already computes them for the tests). A touch that begins on a slot is role `.Hotbar` with the slot index, whether or not a screen is open (the hotbar shows in the world only, so in practice in the world). It presses nothing else: no stick, no look, no pointer click (`pointer_claimed`).
- A tap (lift within `TOUCH_HOLD_SECONDS` of 0118, or 0.25 s if 0119 lands first) presses the action `Hotbar_Slot_<n>` once. A long press on the selected slot presses a new world action `Drop_Stack`, bound also on the keyboard (Q) and on no gamepad control by default (`data/bindings.sjson`, the reference tables in `bindings_test.odin` follow), which drops the selected stack as `Menu_Drop` does from the inventory (`inventory_interaction.odin`). A long press on another slot selects it and does nothing more.
- `doc/input.md`: the hotbar taps and the new action. The key bindings table in `doc/input.md` or wherever the keyboard defaults are documented gains Q.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a tap on slot 3 presses `Hotbar_Slot_3` once and claims the pointer; a long press on the selected slot presses `Drop_Stack`; a long press on another slot selects it only; a tap on a slot while the stick is held changes nothing about the stick.
- The user, on the phone: tap slots to select, hold the selected slot to drop the stack.
