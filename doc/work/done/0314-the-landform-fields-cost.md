# 0314: The landform field's cost

Status: landed (2026-11-11, 2e7d874)

Milestone: the world generation series, after 0306. 0306's design measured its relief at about three times the cost of an evaluation in the wild and a fresh view at 5 to 6.5 times the CPU of before (a start, a teleport, the tech demo), about a quarter of a core while walking. The design left out an estimated reject per node: the steepest crests (about 64 degrees) make the slack swamp the coarse nodes, and a missed fold leaves a hole.

## Goal

A fresh view and a walk generate at about the cost of before 0306 on the couch and the phone, with the same ground.

## Controls

None.

## Change

- Measure first, from 0306's `test_report_the_relief_cost` figures and the couch's and the phone's start and walk.
- Candidates: the low frequency terms (the warp and the region) read once per chunk or node on a lattice and interpolated smoothly enough that no crease shows, the relief evaluated once per sample column where the grid allows, a reject per node that is exact by construction.
- Old worlds and the new ones generate the same bytes, or the change is recorded as 0306's terms were.
- Docs: `doc/architecture.md` (World generation); the log.

## Verify

- The checks and the suite, with 0306's parity tests unchanged.
- The cost figures before and after; the start and a walk on the couch and the phone.

## Specification (design, 2026-11-07)

Designed against `main` at 6be9cc0; the probe ran at 863dd02, and since then only `doc/code_map.md` changed among the files below (0328). 0311 (landed) shares no changed file; the report reads its tree tiles. 0334 and 0335 touch none of the source files below; 0334 edits `doc/architecture.md`'s water field section and 0336 (todo) its World generation waters, beside this item's paragraph. The counts come from the probe in `tmp/0314/tree` (`src/probe_0314_*_test.odin`, thread local counters in `generation_planet.odin`), unoptimised, counts only.

### The counts that decided it

Fresh views at radius 8000 m (the shipped levels, then the 7 by 7 by 7 chunks), from `tmp/0314/run9.log` and `run10.log`. "Left" is the samples still reading a column; "floor" is what an exact range per box of 8 would leave.

| View | Need the relief | Left, boxes of 8 | Left, two levels | Floor | Lattice hashes per relief | Hashes, reliefs and bounds |
|---|---|---|---|---|---|---|
| pre 0306, home | 14.07M | 1.93M | | 1.63M | 32.2 | 453M |
| pre 0306, spring | 13.78M | 1.59M | | 1.22M | 32.2 | 444M |
| shipped, home | 28.03M | 4.11M | 3.07M | 2.44M | 48.5 | 1359M today, 165M |
| shipped, spring | 24.03M | 8.65M | 4.92M | 2.11M | 82.1 | 1973M today, 432M |

- The spring's levels 0 to 3 and chunks, two levels: 0.91, 0.98, 0.98, 0.74 and 1.31M left of 5.32, 4.63, 3.52, 2.13 and 8.43M.
- 0306's prototype timed a relief at 377 ns before and 1116 ns at the spring, so the spring's fresh view is about 5.2 s of CPU before 0306, 26.8 s today and 5.5 s plus the bounds (28M hashes) after.
- The bounds held every sample of every probe box: no box, size or form had a relief outside its range.
- The trees (0311) read 1.27M reliefs at the home's view to 1024 m, 0.40M to 512 m and 0.43M at the spring; this design leaves them (question 1).

### The change

Every chunk and grid is cut into boxes of 8 by 8 by 8 samples, each cut into 8 boxes of 4. The first sample of a box of 8 that needs the relief computes a range that holds the relief of every column of the box, by interval arithmetic over every term of `uncratered_column`. A sample reads no column when the range decides it: air at or above the range's highest plus a spacing, deep stone at or below its lowest less 40 m, plain stone above its highest less 40 m and at or below its lowest less the topsoil. A sample the 8's range leaves computes, on first use, the range of its box of 4 (intersected with the 8's) and tries again. Everything else is evaluated as today. A decided sample gets the bytes its column would give, so no record changes and old and new worlds generate the same bytes. 0306's parity tests stand unchanged.

Rejected:
- A lattice of the low frequency terms, interpolated: it changes bytes, so it needs a record flag and keeps a second path forever. It saves at most the warp and the region (4 of the 10 to 12 noises of a wild evaluation), and the band, not the evaluation, is what grew.
- The relief once per sample column: the grids are axis aligned, so no two samples share a projection. A height lattice per node changes bytes.
- 0306's reject per node from a slope bound: crests at 64 degrees swamp it, and a missed fold leaves a hole. The range here is a bound by construction.
- One range per chunk or node: it leaves 2.2 to 2.5 times the samples of boxes of 8 (9.9M at the home, 17.1M at the spring). Boxes of 16 leave 1.5 to 1.6 times; 16 then 8 leaves no fewer than 8 alone.
- Boxes of 4 everywhere: eight times the boxes to bound; the two levels bound a 4 only under an 8 that leaves a sample (28M bound hashes at the spring against 7.7M for the 8s alone).
- Each noise's range also from its 8 corner values widened by a proven curvature and rounding bound, intersected with the cell form: 5 to 15 percent fewer samples left, but 6 times the bound hashes, so more in all (233M at the home, 518M at the spring, with two levels). It also needs two derived constants and an f64 reference test.
- A cache of each noise's lattice corners per worker: exact, and it would spare most of a relief's 49 to 82 hashes, but it threads a cache through every term. The next lever if the night's figures fall short.

### New file `src/generation_planet_bound.odin`

Header comment: the relief's range over a box of samples (work item 0314, doc/architecture.md, World generation), why it holds every column (each term's range from monotone integer steps on the term's own integers), and that a sample it decides gets the bytes of its column.

Types and constants:
- `Value_Range :: struct {lowest, highest: i64}`: a closed range of integers.
- `Point_Box :: struct {lowest, highest: [3]i64}`: an axis aligned box of points, both corners in it.
- `Relief_Box_Bound :: struct {relief: Value_Range, carving: bool, crater: bool}`: every column of the box's samples has `surface_column(...).relief` in `relief`; `carving` when a carving site (0324) may reach one of them; `crater` when the crater may change a sample (`impact_crater_reaches_box`), and then nothing is decided and `relief` is not computed.
- `Landform_Range :: struct {relief, wildness, region, mask, hill: Value_Range, warped: Point_Box}`: the ranges of `Landform_Reading`'s fields.
- `Relief_Boxes :: struct {first: Sample_Coordinate, step: i32, samples: i32, spacing_millimetres: int, bounds: [RELIEF_BOX_COUNT]Relief_Box_Bound, computed: [RELIEF_BOX_COUNT]bool, half_bounds: [RELIEF_HALF_BOX_COUNT]Relief_Box_Bound, half_computed: [RELIEF_HALF_BOX_COUNT]bool}`: the boxes of 8 and of 4 of one chunk or grid (about 21 KB, on the generating worker's stack), `first` its first sample (a grid's at -1), `samples` per axis (`FIELD_CHUNK_SIZE` or `FIELD_GRID_SIZE`), the positions' spacing (the fine one, as the loops convert samples).
- `RELIEF_BOX_SAMPLES :: 8`, `RELIEF_BOXES_PER_AXIS :: (FIELD_GRID_SIZE + RELIEF_BOX_SAMPLES - 1) / RELIEF_BOX_SAMPLES` (5), `RELIEF_BOX_COUNT :: RELIEF_BOXES_PER_AXIS * RELIEF_BOXES_PER_AXIS * RELIEF_BOXES_PER_AXIS`; `RELIEF_HALF_BOX_SAMPLES :: RELIEF_BOX_SAMPLES / 2`, `RELIEF_HALF_BOXES_PER_AXIS` (9) and `RELIEF_HALF_BOX_COUNT` alike. A box of 4 at `h` per axis lies in the box of 8 at `h / 2`. Both arrays index `box.x + per_axis * (box.y + per_axis * box.z)` with their own `per_axis`, for a chunk too.
- `NOISE_RANGE_CELL_LIMIT :: 2`: more lattice cells than this on an axis, and `lattice_noise_range` gives the full range.
- `CURVE_RANGE_PIECE :: 128`, `CURVE_RANGE_PIECES :: 32`: the curve range's sampling.

Procedures, in this order:
- `range_union(first, second: Value_Range) -> Value_Range`, `range_add(first, second: Value_Range) -> Value_Range`.
- `range_product(first, second: Value_Range, divisor: i64) -> Value_Range`: the least and most of the four `a * b / divisor`, truncated as the point code truncates (a product is bilinear, so its extremes lie at the corners, and truncation keeps the order). A chain `x * y / N * z / N` is two calls.
- `interpolate_range(first, second, fraction: Value_Range) -> Value_Range`: lowest `min(noise_interpolate(first.lowest, second.lowest, fraction.lowest), noise_interpolate(first.lowest, second.lowest, fraction.highest))`, highest the same of the highests. Comment why: for a fraction in 0 to `NOISE_ONE`, `noise_interpolate` never falls when either end rises, and is monotone in the fraction for fixed ends.
- `lattice_noise_range(seed: u64, box: Point_Box, wavelength: i64, gradient: bool) -> Value_Range`: holds the integer noise at every point of the box, by monotonicity. Every noise range below is this call, with the seed and wavelength the point code passes. Per axis the first and last cell (`floor_divide_i64`); more than `NOISE_RANGE_CELL_LIMIT` cells on an axis returns `{-NOISE_ONE, NOISE_ONE}`. For each cell the box clipped to it, per axis the fraction range (the point code's `(p - cell * wavelength) * NOISE_ONE / wavelength` at the clipped ends) and the fade range (`quintic_fade` for gradient, `noise_fade` for value, at both ends; `test_the_fades_are_monotone` proves the order); the corners: value noise `lattice_value` exactly, gradient noise the range of `direction · (fraction - offset * NOISE_ONE)` summed per axis (a direction component of -1 swaps the ends); the corners interpolated with `interpolate_range` in `value_noise`'s order (x pairs, then y, then z); gradient noise clamps both ends to `±NOISE_ONE`. The union over the cells.
- `landform_curve_range(knots: [LANDFORM_KNOT_COUNT]int, noise: Value_Range, scale: i64) -> Value_Range`: the segments the range spans (`index := min(clamp(n + LANDFORM_KNOT_SPAN, 0, 2 * LANDFORM_KNOT_SPAN) / LANDFORM_KNOT_STEP, LANDFORM_KNOT_COUNT - 2)` at both ends); `hull` the union of `[min(p1, p2), max(p1, p2)]` over them; over the same segments, with `p0..p3` as `landform_curve` picks them, `c1 := |p2 - p0|`, `c2 := |2p0 - 5p1 + 4p2 - p3|`, `c3 := |3p1 - p0 - 3p2 + p3|`, `slope := max((c1 + 2c2 + 3c3) / 2 + 1)` (the cubic's derivative per unit t) and `rounding := max(4 + (c1 + c2 + 2c3) / NOISE_ONE)`. The curve at `pieces + 1` points evenly from lowest to highest, `pieces := clamp((width + CURVE_RANGE_PIECE - 1) / CURVE_RANGE_PIECE, 1, CURVE_RANGE_PIECES)`; their least and most widened by `slope * ceil(width / pieces) / LANDFORM_KNOT_STEP / 2 + slope / NOISE_ONE + 2 * rounding + 1`; intersected with `hull`. Comment why: between two sampled points the real curve moves at most the slope times half the piece (clamping keeps the slope and the flat ends have none), and the integer curve is within the rounding of it.
- `squared_chord_range(box: Point_Box, point: [3]i64) -> Value_Range`: per axis the nearest (0 when the box straddles the point) and farthest squared offset, summed.
- `ridge_range(noise: Value_Range) -> Value_Range`: `{landform_ridge(most |n|), landform_ridge(least |n|)}`, the least 0 when the range straddles 0.
- `projected_box(generation: Planet_Generation, lowest, highest: World_Position) -> Point_Box`: the points `project_onto_sphere` gives the samples of the box of positions. The 8 corners and the centre projected (`position * radius / max(isqrt(|position|²), 1)`); the corners' box widened per axis by `(root + 8)² / (2 * radius) + 8`, `root` the root of the largest squared chord from the centre's projection to a corner's; when `root` reaches the radius, the cube of the radius plus 8. Comment why: a sample's direction is a normalised convex combination of the corners' directions, so its projection lies within the corners' hull pushed out by the radius times one less the cosine of their spread, which is the squared chord over twice the radius; 8 covers the truncation of the projections and of the chords.
- `landform_reading_range(generation: Planet_Generation, box: Point_Box) -> Landform_Range`: the point code's steps on ranges. `{}` when the landforms are off. `wildness` from `squared_chord_range(box, generation.landform_home)` through `home_wildness_at_squared` at both ends; a highest of 0 returns `relief = {home, home}` only. Per axis the warp's range (seed `hash_combine(landform_seed, axis)`), `warped` the box moved by `warp_metres * warp / NOISE_ONE` at both ends, `mask` the first axis's warp. `region` over `warped`. `base := landform_curve_range(region_heights_metres, region, POSITION_UNITS_PER_METRE)`, `relief := home + range_product(base - home, wildness, NOISE_ONE)`. The range share `landform_curve_range(region_ranges_percent, region, NOISE_ONE) / 100`; when `range_metres > 0` and its highest is above 0: the ridge from the range noise over `warped`, through the spurs when its highest is above 0 and `spur_percent > 0` (`ridge * ((100 - spur) * N + spur * spur_ridge) / (100 * N)` at the matching ends, all non negative), times the amplitude, then by `range_product` the share with its lowest raised to 0 (a point whose share is 0 or less skips the term, which the 0 in the share's range holds) and the wildness; added. The hill share likewise; when `hill_metres > 0` and its highest is above 0: `hill` the hill noise over `warped`, the hills' height by `range_product` with the share (its lowest raised to 0) and the wildness, added, and `hill` widened to hold 0 when the share's lowest is 0 (the point code leaves the reading's hill 0 there).
- `landmark_relief_range(generation: Planet_Generation, box: Point_Box, relief: Value_Range, reading: Landform_Range) -> (result: Value_Range, carving: bool)`: `relief` when the landmarks are off or the wildness's highest is 0. Otherwise, with `floor` as `landmark_relief` takes it:
  - The gorge may cut when `gorge_metres > 0`, `gorge_width_permille > 0`, `relief.highest > floor`, `landmark_ramp(-mask.lowest, gorge mask, fade) > 0`, and the gorge noise over `warped` plus `gorge_meander_percent * hill / 100` (a range) comes nearer 0 than `gorge_width_permille * NOISE_ONE / 1000`. Its cut is at most `metres(gorge_metres)`.
  - The mesas: `patch` the ramp at both ends of `mask`; when its highest is above 0, `strength := range_product(range_product(patch, mesa share, N), wildness, N)` with the share `landform_curve_range(region_mesas_percent, region, N) / 100` (lowest at least 0); when its highest is above 0, the mesa noise over `box` (unwarped) plus `mesa_rough_percent * hill / 100`; `mesa.highest := mesa_raise_at(landmarks, noise.highest, strength.highest)`, `mesa.lowest := strength.lowest > 0 ? mesa_raise_at(landmarks, noise.lowest, strength.lowest) : 0`.
  - The sites: every lattice cube the box meets (per axis `floor_divide_i64` of both ends by the spacing): `landmark_site_candidate`, skipped at None; `place_landmark_site`, skipped at None; skipped when `squared_chord_range(box, placed.centre).lowest >= outer * outer`, `outer := landmark_site_outer(placed)` (the reading's own refusal); otherwise a carving kind sets `carving` and raises the most `landmark_raise_most(placed)`, a sinkhole cuts the most `placed.height`, a spire or butte raises the most `placed.height`.
  - `result.highest := min(relief.highest + mesa.highest + site_raise, relief_highest)`; `result.lowest := min(relief.lowest + mesa.lowest, relief_highest)`; when the wildness's lowest is 0, `min(result.lowest, relief.lowest)` (a point of wildness 0 skips the landmarks); with a gorge `min(result.lowest, max(relief.lowest - gorge, floor))`; with a sinkhole `min(result.lowest, max(result.lowest - site_cut, floor))`.
- `uncratered_relief_range(generation: Planet_Generation, box: Point_Box) -> (relief: Value_Range, carving: bool)`: the octaves (index 0 through `long_octave_relief` at both ends of its noise range, the others `amplitude * noise / NOISE_ONE` at both ends), the ledges when on (`ledge_profile` at both ends), `landform_reading_range`, then `landmark_relief_range` over the sum.
- `relief_box_bound(generation: Planet_Generation, lowest, highest: World_Position) -> Relief_Box_Bound`: `{crater = true}` when `impact_crater_reaches_box(generation, {lowest, highest})`, else `uncratered_relief_range(generation, projected_box(generation, lowest, highest))`.
- `relief_box_bound_at(generation: Planet_Generation, boxes: ^Relief_Boxes, offset: [3]i32, half: bool) -> Relief_Box_Bound`: the bound of the box of 8 (or with `half` of 4) holding the sample `offset` from `boxes.first` (0 to `samples - 1` per axis), computed on first use from the positions (`sample_to_world_position(boxes.first + Sample_Coordinate(local * boxes.step), boxes.spacing_millimetres)`) of the box's first sample and its last (`min(box * size + size - 1, samples - 1)` per axis). A box of 4's bound is intersected with its 8's (the larger lowest, the smaller highest, `carving` only when both say so, `crater` its own).
- `planet_sample_by_boxes(generation: Planet_Generation, boxes: ^Relief_Boxes, offset: [3]i32, position: World_Position, distance: i64) -> (sample: Field_Sample, decided: bool)`: `planet_sample_by_bound` with the 8's bound; undecided and the 8 not `crater`, again with the 4's.
- `planet_sample_by_bound(generation: Planet_Generation, bound: Relief_Box_Bound, position: World_Position, distance: i64) -> (sample: Field_Sample, decided: bool)`: nothing with `crater`. `height := distance - radius`. `FIELD_AIR_SAMPLE` when `height >= bound.relief.highest + generation.spacing`. Nothing more with `carving`. With `deep := max(metres(DEEP_STONE_DEPTH_METRES), generation.spacing)` and `top := max(generation_topsoil_depth(generation), metres(OUTCROP_DEPTH_METRES))`: `.Deep_Stone` when `height <= relief.lowest - deep`, `.Stone` when `height > relief.highest - metres(DEEP_STONE_DEPTH_METRES)` and `height <= relief.lowest - top`, either `.Bedrock` when `distance <= bedrock_radius`, as `{MAXIMUM_DENSITY, material, planet_tint(generation, position)}`; nothing otherwise. Comment each band against `planet_sample_at_column`: the depth saturates the density a spacing from the surface, the stratum and the outcrop follow the depth, and carved air lies under the top.
- `planet_sample_reading_boxed(generation: Planet_Generation, position: World_Position, boxes: ^Relief_Boxes, offset: [3]i32) -> (sample: Field_Sample, shaded, carved: bool)`: `planet_sample_reading` with the boxes: the shortcut, then `planet_sample_by_boxes` (decided: not shaded, not carved), then `planet_sample_reading_at`.

### Changed files

- `src/generation_planet.odin`: `planet_sample_reading`'s part after the shortcut moves into `planet_sample_reading_at(generation, position, distance, on_sphere) -> (sample, shaded, carved)`, which it calls. `generate_field_chunk` makes `Relief_Boxes{first = origin, step = 1, samples = FIELD_CHUNK_SIZE, spacing_millimetres = spacing_millimetres}`; a sample that needs the relief first tries `planet_sample_by_boxes(generation, &boxes, field_index_to_local(index), position, distance)` and, decided, takes it and skips the shade, carve and overlay steps; the loop stays in index order, so the crater overlay keeps its order. The header comment names 0314.
- `src/world_field_lod.odin`: `generate_field_grid` makes `Relief_Boxes{first = grid.origin - grid.step, step = grid.step, samples = FIELD_GRID_SIZE, spacing_millimetres = generation.spacing_millimetres}` and calls `planet_sample_reading_boxed(density_generation, position, &boxes, {x + 1, y + 1, z + 1})`. The bound is of the coarse generation, whose spacing gives the air band and the topsoil.
- `src/generation_planet_landforms.odin`: `home_wildness`'s body after the squared chord moves into `home_wildness_at_squared(generation: Planet_Generation, squared: i64) -> i64`, which it calls.
- `src/generation_planet_landmarks.odin`: `landmark_mesa_raise`'s steps after the noise move into `mesa_raise_at(landmarks: Planet_Landmarks, noise, strength: i64) -> i64`; new `landmark_raise_most(site: Landmark_Site) -> i64`: the most a site of a carving kind raises, `site.height * (100 + CARVE_RELIEF_ROUGH_PERCENT) * (100 + GROTTO_KNOLL_ROUGH_PERCENT) / 10000 + 2` (the shape's share is at most `NOISE_ONE`, each roughening at most its percent).

No data key, no record field, no save change, no string.

### Tests

New `src/generation_planet_bound_test.odin`, its places from the existing helpers (`shipped_test_home_at`, `pre_0306_test_home_at`, `design_landform_test_planet`, `design_landmark_test_planet`, `design_carving_test_planet`, `test_landmark_sites`, `test_nearest_carving_site`, `test_degree_point`):

- `test_the_fades_are_monotone`: `noise_fade` and `quintic_fade` never fall over every fraction 0 to `NOISE_ONE`, 0 at 0 and `NOISE_ONE` at `NOISE_ONE`.
- `test_the_relief_terms_are_monotone`: over every noise from `-NOISE_ONE` to `NOISE_ONE`: `long_octave_relief` never falls for the shipped, the pre 0306 and the design shapes and for terraces of 1200 mm with risers of 10 and 990 permille and basins of 16 m at thresholds -90, 0 and 90; `ledge_profile` never falls at sharpness 1, 2, 3, 128 and the data's most. `landform_ridge` never rises with |noise|. `home_wildness_at_squared` never falls over 10,000 squared chords from 0 past the wild distance's square. `mesa_raise_at` never falls with the noise (every 64 units over `±2 NOISE_ONE`) nor with the strength (every 256 over 1 to `NOISE_ONE`) for the shipped and the design landmarks.
- `test_the_noise_ranges_hold_every_point`: both kinds, wavelengths 12, 96, 180, 800 and 2400 m, 300 boxes each from hashed corners within ±40 km and extents from 0 to 2.5 wavelengths per axis (some flat on one axis): the noise at the 7 by 7 by 7 points spread evenly over the box (corners and edges included) and at 50 hashed interior points lies in `lattice_noise_range`, and a box of one point gives exactly the point's noise.
- `test_the_curve_range_holds_every_noise`: the shipped and the design curves (heights at `POSITION_UNITS_PER_METRE`, the percents at `NOISE_ONE`) and 20 hashed knot sets within the data's bounds: the curve at every noise from `-NOISE_ONE - 1000` to `NOISE_ONE + 1000`, then 2000 hashed ranges of widths 0, 1, 10, 100, 1000, 10,000 and 2 `NOISE_ONE`: every value inside the range, and a width of 0 gives the value exactly.
- `test_the_projected_box_holds_every_sample`: radii 1000, 4000, 8000 and 16000 m, 200 hashed directions plus the six axis directions and directions on the axis planes, boxes of 8 and of 4 samples at steps 1, 2, 4 and 8 (1000 mm) and at step 1 of 333 mm, at heights from the bound's lowest less 60 m to its highest plus 10 m: every sample's `project_onto_sphere(position, isqrt, radius)` lies in `projected_box`.
- `test_the_relief_box_bound_holds_every_sample` (slow): for the shipped home at 4000, 8000 and 16000 m, `design_landform_test_planet(8000)`, `design_landmark_test_planet(8000)`, `design_carving_test_planet(8000)` and `pre_0306_test_home_at(8000)`, boxes of 8 and of 4 samples at steps 1 and 8: boxes round the home, the spring (79, 151), the nearest site of each kind (`test_landmark_sites` and `test_nearest_carving_site`) and 40 hashed directions, at the relief's height there and 8 and 40 m under it: `uncratered_column` at every sample's projection has its relief in `uncratered_relief_range(projected_box(...))` and, when its carve is a carving kind, `carving` is set.
- `test_the_bounded_generation_matches_the_samples`: for the shipped home at 8000 m with `crater_at_impact` on and off, `pre_0306_test_home_at(8000)` and `design_carving_test_planet(8000)`: the chunks at the home's surface, one above and one and two under it, at the spring's surface (79, 151), at an arch's and a grotto's (`test_site_sample`) and at four hashed directions' surfaces; `generate_field_chunk(..., crater_overlay = true)` equals, sample by sample, `planet_sample_reading` at the sample's position (density, material, tint), its sky light is 0 exactly where that is shaded air, and its crater overlay lists exactly the indices where `impact_crater_sample` says changed, with those samples, in index order. The nodes of levels 1, 2 and 3 holding the same places: `generate_field_grid` equals `planet_sample_reading(field_grid_generation(generation, step), position)` at every grid position (density, material, tint, sky light 0 in ground and shaded air, full elsewhere), and `planet_sample_reading_boxed` gives the same sample, `shaded` and `carved` there (the lakes read `carved`).
- `test_the_box_bound_leaves_few_columns` (slow): the shipped home at 8000 m, the 7 by 7 by 7 chunks round the spring's camera (79, 151, 2 m over the ground): of the samples `planet_sample_shortcut` sends to the relief, those `planet_sample_by_boxes` leaves undecided are under 20 percent (the probe: 1.31M of 8.43M, 15.6 percent), so a change that loosens a term shows. Only shortcuts and bounds, no column.

Unchanged and passing: every 0306, 0323 and 0324 parity and bound test (`test_a_record_without_landforms_generates_as_before`, `test_an_old_world_file_keeps_its_relief`, `test_a_world_file_before_the_landmarks_keeps_its_relief`, `test_a_world_file_before_the_carving_keeps_its_ground`, `test_landform_relief_matches_the_design`, `test_landmark_relief_matches_the_design`, `test_the_carve_matches_the_design`).

The report (`test_report_the_relief_cost`, `src/generation_planet_landforms_test.odin`, inside `when RELIEF_COST`): `report_relief_cost_of_view` adds per level and for the 7 by 7 by 7 chunks the samples left undecided by the box bound beside those needing the relief, and replaces the 16 coarsest nodes' timing by the wall time of `generate_field_grid` over every node of levels 1 to 3 of the view and of `generate_field_chunk` over the 343 chunks, each beside the same grids and chunks read sample by sample through `planet_sample_reading` (the cost before this item), so one run gives before and after for the three planets. A line for the tree tiles: `generate_field_tree_tile` over `field_tree_tiles_around` at 1024 and 512 m, wall time and tile count.

### Docs

- `doc/architecture.md`, World generation: after "Samples beyond the relief band skip the noise.", the box bound: the boxes of 8 samples and of 4 under an 8 that leaves a sample, the range by interval arithmetic (each noise from its lattice cells, the curves sampled with their slope bound, the sphere's projection widened by its bulge, the landmarks' sites by their cubes), the three bands a sample is decided in, the crater's and the carving sites' boxes left to the column, and that a decided sample gets the column's bytes. Replace "in the wild a relief costs about three times as much" with that figure and the band's share now read (the report's numbers). A sentence for 0327: a three dimensional term adds its own range to the box (a box its range proves untouched keeps the bands; otherwise the ground bands stop above its shell, as a carving site's box keeps only the air band).
- `doc/code_map.md`, world: `generation_planet_bound.odin` after the landmarks' line: the relief's range over a box of samples (0314), `relief_box_bound`, `planet_sample_by_boxes`.

### Hand-back check lines that apply

- A changed save layout loads an old save: nothing changes in the save or the record; old and new records generate the same bytes, shown by `test_the_bounded_generation_matches_the_samples` over the pre 0306 and the shipped planets and by the unchanged parity tests.
- A new participant in a shared budget: the bound takes the workers' CPU only to give back more; the report measures both.
- Tests never touch the machine's state directory: every new test generates in memory.

### Measurements for the Verify

- Night window (the main agent, `./build.sh nightly` in the item's worktree, 03:00 to 06:00): `test_report_the_relief_cost` gives, for its three planets (pre 0306, the shipped without landmarks, the shipped), at the home and at (79, 151), the grids and chunks' wall time sample by sample (before) and bounded (after). Success: each of the shipped planet's views, bounded, within about 1.3 times the same view of the pre 0306 planet sample by sample (question 2). Run once on `main` too for the existing lines.
- The couch and the phone (the user): with the current play build and then the item's, a new world's start at the home, the tech demo (its teleport to the spring), and a walk of a few hundred metres along a range: how long the view takes to stop filling and whether the finest level keeps up ahead. On the phone the same with the Android row (trees to 512 m).

### Questions to the main agent

1. The trees (0311) read a relief per candidate: 1.27M at the home's view to 1024 m, 0.40M to 512 m, about a third of the bounded home view's hashes, and they came after the pre 0306 baseline. Chosen: not in this item; the report's tree line shows their share, and a new item takes them if the night figures or the couch ask for it.
2. The success line in the night window (the shipped spring's fresh view within about 1.3 times the pre 0306 one, CPU summed) is mine from the counts (about 1.1 expected); set another if you want one.

### Decisions (main agent, 2026-11-07)

1. The tree tiles' relief reads (1.27M at the home's 1024 m view, a third of the view's cost after this item) stay out of this item; 0337 takes them.
2. The night bar: each shipped view within 1.3 times its pre-0306 cost, as designed.
3. The implementation starts from main. 0326 (planet-wide waters) shares `generation_planet.odin` and `world_field_lod.odin` with it and follows in the same stream.

### Deviations (implementation, 2026-11-11)

- `noise_fade` and `quintic_fade` fall by at most 1 and 3 in integers, so they are not monotone: a fade's range goes through `fade_range` with `FADE_FALL_LIMIT`, the mesa's range is widened by `mesa_raise_fall`, and `test_the_fades_fall_at_most_the_limit` replaces `test_the_fades_are_monotone`.
- The deep stone band's depth includes the topsoil's, `projected_box` answers the radius cube for a box nearer the centre than 3/4 of the radius, and a box of 4 under a box of 8 below the crater skips the intersection.
- `test_the_bounded_generation_matches_the_samples` is four tests, one per planet (plain, `_with_the_crater_baked`, `_before_0306`, `_with_the_carving`).

