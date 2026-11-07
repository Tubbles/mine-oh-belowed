# 0321: Cracks along the crests

Status: todo (2026-11-07)

The captures of 0306 and 0307 from 120 m over the home, looking south west (`tmp/shot_terrain_colours/crest_crop.png`, the same place in both builds), show a dashed line of sky along a contour on a far slope and along a crest's silhouette. The seam between two detail levels opens and the skirts do not close it. It came with 0306's relief: the slopes are steeper and taller than the 34 m relief the skirts were sized for.

## Goal

No sky shows through the ground at any distance or height on the shipped planets.

## Controls

None.

## Change

- Find which seam opens: neighbouring levels whose vertices do not meet, or skirts too short for the drop of a steep slope across a coarse cell. Measure it from the relief map mode and a capture.
- Size the skirt from the planet's relief bound or the slope across the cell, or close the seam where the levels meet, whichever the cause needs.
- Docs: `doc/presentation.md` (The field, the skirts).

## Verify

- The checks and the suite, with a test of the seam at the steepest slope the shipped planets make.
- The captures of 0306's views from 40 m and 120 m, with no sky through the ground.
