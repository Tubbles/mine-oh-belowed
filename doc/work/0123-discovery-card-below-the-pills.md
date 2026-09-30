# 0123: The discovery card below the touch overlay's pills

Status: implemented

## Goal

Since the review of 0115 the Back and Start pills sit at the top centre and overlap the discovery card (`ui_mission_control.odin`, top centre from the safe area's top, y 54 to 110 at UI scale 1; the pills y 20 to 100 at 1080 high) while it shows. Accepted then as a later item; this is it.

## Change

- While the overlay is drawn (`touch_overlay_on`), the discovery card's top is the bottom of the lowest `top_center` element plus a gap, in UI units (the placed elements are in render pixels, `pixels_to_units_rectangle` converts). With the overlay off nothing moves. The card's placement gets the offset as a parameter so the test can pass it.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. A test: with the shipped layout at 2272 by 1080 the card's rectangle does not intersect Start's or Back's; with the overlay off it sits where it did.

## Implemented

- `touch_overlay_top_center_clearance` (`touch_overlay.odin`, next to `pixels_to_units_rectangle`) returns the bottom of the lowest `top_center` button plus `UI_GAP` in UI units, 0 without one. `discovery_card_clearance` applies it to the layout in use under the same condition `run_ui_frame` draws the overlay under.
- `discovery_card_rectangle` (`ui_mission_control.odin`) places the card and takes the clearance; `draw_discovery_card` gets it through the new `Screen_Context.discovery_card_clearance` (`ui_screens.odin`), set in `run_ui_frame` (`loop.odin`) and passed on in `draw_hud` (`hud.odin`).
- Deviation: the card's top is the larger of the safe area's top and the clearance, not the clearance alone, so a user layout with pills above the safe area's top does not pull the card up.
- Tests: `test_the_top_center_clearance_follows_back_and_start` (`touch_overlay_test.odin`) and `test_the_discovery_card_sits_below_back_and_start` (`ui_mission_control_test.odin`, at 2272 by 1080 the card at the full safe width clears both pills; with no clearance it sits at 986, 54 as before).
