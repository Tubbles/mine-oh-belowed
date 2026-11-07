# 0322: The ledges' rock bands

Status: todo (2026-11-07)

0307's captures (`tmp/shot_terrain_colours/state/mine-oh-belowed/screenshots/home_air120.png`) show every hillside striped with brown bands along its contours. The relief kept the small ledges from before 0306 as detail, and since 0307 a face steeper than 40 to 50 degrees takes the rock look, so each ledge's riser draws a band of rock across the grass. The bands repeat along every slope, which `DESIGN.md` (No perceivable repetition) rules out.

## Goal

Rock shows on cliffs and steep slopes, not on every small step of a grassy hill.

## Controls

None.

## Change

- Candidates, which the design weighs from captures: drop or soften the ledges in the shipped planet's data, take the rock look's steepness from a broader normal (the slope over a few metres rather than the triangle's), or require a minimum height of the steep face.
- Old worlds keep their relief. A data change applies to new worlds through the record, as 0306's terms did.
- Docs: `doc/content.md` (Planets) or `doc/presentation.md` (the looks), whichever the change touches.

## Verify

- The checks and the suite.
- 0307's captures again, with rock on the range's faces and none in bands across the grassy slopes.
