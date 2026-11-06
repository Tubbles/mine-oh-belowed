# 0305: The wake's colours from KSP

Status: todo (2026-11-06)

Milestone: the entry's look, after 0304. The user (2026-11-06), on 0304's captures: "For the color, let's take it from KSP" (`work/reference/0303/ksp_reentry_outside.jpg`). Those captures showed the shield and the wake's root burned to plain white, hiding the pod's lower half, and the wake above its orange band turning a grey lilac that reads as smoke, the porthole paler than 0288's.

## Goal

The wake and the shield's glow take the reference's colours: orange to red along the whole length, fading to clear rather than to grey or lilac, the shield yellow white inside an orange rim, nothing burned to plain white. Through the porthole the same wake reads in those colours. The opacity stays the user's 60.

## Controls

None.

## Change

- Measure the reference: the trail's colour by distance from the rim along it, the shield's centre and rim, how the trail's light and its saturation fall together.
- Set the wake's colour ramp (`arrival_wake.fs`) and the data colours (`arrival_plasma` in `data/game.sjson`) from it, and bound the intensity's mapping so the root and the shield keep their hue; the flakes' gold edge and dark plate still read against the new colours.
- Docs: `doc/presentation.md` (The wake), `doc/content.md` (`arrival_plasma`); the log.

## Verify

- The checks and the suite.
- Captures at the peak (tick 1271, seed 290) from the side, from below and from the chair's porthole, beside the reference; sent to the user.
