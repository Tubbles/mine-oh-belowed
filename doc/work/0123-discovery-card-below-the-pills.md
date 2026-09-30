# 0123: The discovery card below the touch overlay's pills

Status: todo

## Goal

Since the review of 0115 the Back and Start pills sit at the top centre and overlap the discovery card (`ui_mission_control.odin`, top centre from the safe area's top, y 54 to 110 at UI scale 1; the pills y 20 to 100 at 1080 high) while it shows. Accepted then as a later item; this is it.

## Change

- While the overlay is drawn (`touch_overlay_on`), the discovery card's top is the bottom of the lowest `top_center` element plus a gap, in UI units (the placed elements are in render pixels, `pixels_to_units_rectangle` converts). With the overlay off nothing moves. The card's placement gets the offset as a parameter so the test can pass it.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. A test: with the shipped layout at 2272 by 1080 the card's rectangle does not intersect Start's or Back's; with the overlay off it sits where it did.
