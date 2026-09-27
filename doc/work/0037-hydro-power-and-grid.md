# 0037 Hydro power and the larger grid

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (512 tests, 14 new in `hydro_grid_test.odin`, 1 new in `schematic_test.odin`), `./build.sh`, `./build.sh release`, `--version`; the shipped data loads through the real loader (the binary stops only at opening a window).

### Carry over from 0036: shallow crates

- `region_crate_site` now tries every candidate column for a pocket 20 to 40 blocks below the surface (`CRATE_SHALLOW_MAXIMUM_DEPTH`) before any column is searched down to the cave floor. Measured over 144 regions per test seed: 42 of 42, 35 of 36 and 31 of 31 crates within 40 blocks. The test checks that a deeper site only occurs when no candidate column has a shallow pocket, and that more than half are shallow.

### Model

- Hydro turbine: machine kind `hydro_turbine` in the fluid machine pool (no ports, no slots), a generator through the existing participant code. Placement: every footprint cell loaded, free of entities and air or water, bottom layer on solid ground, clear of players, and one cell with flowing water of `hydro_minimum_water_level` (3) or more. The offer is `hydro_kilowatts_per_water_level` (10 kW) times the sum of flowing levels in the eight cells, capped at `electric_output_kilowatts` (400), read from the blocks every tick. Water keeps updating in its cells: `Fluid_Machine.lets_water_through` exempts them from the entity check in `update_water_cell`. State Generating, Idle, or No water when it offers nothing while the network asks.
- Poles: the pole code already read reach and volume from the machine entry. What changed is that a pole may now have a square footprint wider than 1 (the substation): the supply volume centres on the footprint (`supply_volume_origin` takes the footprint size), validation asks for a volume whose width and depth differ from the footprint's by an even count, wires anchor at the footprint centre, and a wide pole draws as a frame around a post. Wire reach still measures between origins, which for the substation is its minimum corner.
- Fast belts: line construction already split lines where the speed changes and handed off straight with exact positions and a spacing limit, so the slower line holds the arriving item back; tests now cover it. Placement: `find_belt_machine_of_speed` picks the ramp or lift of the same speed as the held belt item, for single placement, drag steps and automatic ramps (a drag that turns an existing belt into a ramp uses that belt's tier). Rendering scrolls the shared meshes once per distinct belt speed and draws that speed's belts after, tinting faster tiers red. Player carry already used the belt's own speed.
- Inserters: `inserter_reach` (data, default 1, at most 2) is copied into `Inserter.reach` at creation; pickup and drop cells, the dead end statistic and the arm length use it.

### Deviations

- "Still water does not count" is read as source water: the water model has no velocity, so every flowing water block counts as moving and every source as still.
- The turbine needs solid ground under its bottom layer like every machine, so it cannot hang in a waterfall.
- The two new struct fields (`Fluid_Machine.lets_water_through`, `Inserter.reach`) change the save layout fingerprint; the new content changes the content fingerprint anyway.
- No fast splitter: a splitter keeps its own data speed (yellow), so a fast line through a splitter runs at yellow speed inside it. Not required by the brief.
- No placeholder technology is left, so the placeholder tests in `lab_test.odin` now build one themselves.

### Guessed numbers

10 kW per water level (full 400 kW at 40 levels: a 2 by 2 footprint of level 7 water gives 280 kW, deep water in all eight cells 400), minimum level 3. Recipes: hydro turbine 10 steel, 10 iron gear, 5 circuits, 5 pipes, 2 s; big pole 2 steel, 4 copper wire, 0.5 s; substation 10 steel, 5 circuits, 6 copper wire, 0.5 s; belt ramp 2 from 1 belt 2 and 1 iron plate, belt lift 2 from 2 belt 2 and 2 iron gears (the yellow pattern); fast inserter 1 inserter, 2 circuits, 2 iron plates; long inserter 1 inserter, 1 iron gear, 1 iron plate. Seconds per pack: 30 for electric grid and fast inserters. Fast inserter cycle 26 ticks (138.5 per minute, integer division). Colours: turbine (90, 120, 140), fast belt tint (255, 140, 130).

### Not verified

Everything visual and the feel: the turbine box in water, water rendering inside it, the substation frame and wire anchors, the big pole height, the fast belt tint and scroll speed, the long inserter arm length, the panel rows for the turbine. The user verify (a dammed river lighting a distant base through a substation, a fast belt outrunning a yellow one) is covered by tests only. Whether damming in the current water model can actually raise the levels in a turbine's footprint in a player built river has not been tried: flowing water only spreads one level down per block, so a dam mostly shortens the flow rather than deepening it.

### Open questions

- Is 10 kW per level right? A turbine in the first cells next to a source gives 240 kW; a full 400 kW needs water two blocks deep (a waterfall column), which the placement rule on solid ground makes awkward.
- Should water spreading into a turbine count as "moving" only when a lower neighbour exists (a real flow direction), instead of any flowing block?
- Should wire reach for multi cell poles measure from the footprint centre rather than the origin corner?
- `doc/fluids.md` (hydro turbine, big pole and substation, supply volume on wider footprints), `doc/logistics.md` (as implemented notes for fast belts and the long inserter), `doc/content.md` (new rows and technologies, fast belts no longer phase 5 placeholder) need updates; this run could not touch them.

