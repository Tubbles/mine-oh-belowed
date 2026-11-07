# 0322: No more ledges

Status: todo (2026-11-07)

The user (2026-11-07, a phone screenshot): "there is dirt striping that doesn't look good. Furthermore, there are weird half meter drop features snaking around the world. Feels like the height map has two frequencies or something. Get rid of the half meter features, they look artificial." Both come from the ledges of 0189 (`relief_shape.ledge_*` in `data/planets.sjson`: a 32 m wavelength, 700 mm amplitude, sharpness 128), which 0306 kept as detail. Each ledge is a step of about half a metre snaking along a contour. Since 0307 its riser is steep enough to take the rock look, so every slope is striped with brown bands (`tmp/shot_terrain_colours/state/mine-oh-belowed/screenshots/home_air120.png`).

## Goal

New worlds have no ledges: no snaking steps, and no rock bands across grassy slopes.

## Controls

None.

## Change

- The shipped planets' ledge amplitude goes to 0. The record keeps old worlds' ledges, as it keeps their other relief terms.
- If grass slopes still show rock bands without the ledges (from the detail octaves), the design names the cause and the fix (the rock look's steepness from a broader normal, or a minimum height of a steep face).
- The golden values of 0306's tests that pin the shipped relief are pinned again, and each re-pin is named.
- Docs: `doc/content.md` (Planets).

## Verify

- The checks and the suite.
- 0307's captures again (the home and the new spring from the ground, 40 m and 120 m): no steps along the contours, no rock bands across grass, rock on the range's faces.
