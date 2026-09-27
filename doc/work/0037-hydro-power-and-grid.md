# 0037 Hydro power and the larger grid

Status: todo
Milestone: M8

## Goal

Power from flowing water and the grid pieces a large base needs: the hydro turbine in a river, the big pole and the substation, and the second belt speed that fast belts have waited for.

## Deliverables

- Hydro turbine (2 by 2 by 2, generator): valid in flowing water (at least one footprint cell holding flowing water with level 3 or more, with source water not counting), offering power proportional to the water level around it up to 400 kW, free of fuel; water keeps flowing through it (its cells are not solid to water). Dams are a terrain puzzle: the player builds them from blocks.
- Big pole (1 by 1 by 6, wire reach 24, small supply volume) and substation (2 by 2 by 3, supply volume 18 by 18 footprint 6 high, reach 18), both electric network entities through the existing pole code with data driven reach and volume.
- Fast belts: a second belt speed. Belt placement and rendering read the speed from the machine entry, ramps and lifts get fast variants, lines of mixed speed hand off correctly (an item entering a slower belt waits for room), `fast_belts` stops being a placeholder and unlocks belt 2, ramp 2 and lift 2 at 1800 items per minute. Fast inserter and long inserter as data variants of the inserter (fast: 138 per minute; long: reach two cells) unlocked by `fast_inserters` (packs 1 and 2).
- Tests: turbine validity and output by water level, poles and substations connecting by reach and covering by volume, mixed speed belt hand off exactness, long inserter reach, technology gating, determinism.

## Verify

- Builds and tests pass.
- User: a turbine in a dammed river lights a distant base through a substation, and a fast belt visibly outruns a yellow one.
