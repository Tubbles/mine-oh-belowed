# 0227: A crouch control on the touch overlay

Status: todo (2026-10-04, from the user on the phone with the round three pod preview: "How do i toggle crouch on phone"; there is none, Default carries no Sneak control since 0134 took the buttons out, and the airlock of 0221 needs crouching)

## Goal

A player on the phone can crouch, hold the crouch and stand up again without writing a layout file by hand: the pod's airlock (0221, the user's rule "the pod airlock doors shall need crouching to pass through") is passable on touch.

## Controls

Touch is a virtual gamepad, so the control presses the Sneak binding (`EAST`), never a touch code path of its own (Code rules). The control design, to be written by the main agent before the design stage starts, chooses between: a B button in Default (a circle above the right hand HUD buttons with `double_tap_toggles`, which latches only while the Sneak setting is Hold, [touch_overlay.md](../touch_overlay.md)); a gesture on the stick (a press and hold past the rim's opposite, or a two finger tap); or a HUD button beside the hotbar that follows the Sneak setting (Hold or Toggle) like the pause button follows its binding. Until then the user layout in the reply of 2026-10-04 (a B button, `tmp/touch_overlay.sjson`) serves the preview.

## Change

- Decided by the control design: the element or the HUD button, its place against `test_no_touch_overlay_element_covers_a_hotbar_slot` and the placement editor's grid (0215), and how it reads under the Sneak setting (Hold: held while touched, double tap latches; Toggle: a tap toggles).
- Docs: `doc/touch_overlay.md` (Default's elements, the Sneak line), `doc/input.md` (the touch column of the bindings table), `data/touch_overlay.sjson`'s header.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
- Tests: the control presses Sneak in the world context and nothing in a menu; the latch follows the Sneak setting; the element covers no hotbar slot and none of the HUD's touch buttons at the smallest audit size.
- On the phone: crawl through the airlock of the round three pod crouched, both doors, and stand up in the cabin.
