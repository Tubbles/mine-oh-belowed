# 0337: The tree tiles' relief cost

Status: designed (2026-11-11)

From 0314's design. 0310's tree tiles read the relief once per candidate tree: 1.27 million reads for the home's 1,024 m view at 8 km, about a third of that view's generation cost once 0314 has bounded the chunks and grids. They came after the pre-0306 baseline 0314 measures against, so 0314 left them out.

## Goal

A fresh view's tree tiles cost a small share of its generation, with the same trees.

## Controls

None.

## Change

- Measure the reads per tile and per view from 0314's extended `test_report_the_relief_cost` (its tree line).
- Candidates: 0314's box ranges reused to reject a tile's candidates in water or above the tree line without reading their columns, one read per tree instead of per candidate, the far cards' tiles reading a coarser relief. The trees stay the bytes they are, or the change is recorded through the planet record.
- Docs: `doc/architecture.md` (World generation, the trees); the log.

## Verify

- The checks and the suite, with 0310's tree tests unchanged.
- The tree line of the report before and after, in the night window.

## Specification (design, 2026-11-11)

Designed on `main` at 2e7d874 (0314 landed). The counts come from a probe in `tmp/0337/tree`, 0314's snapshot a22a996, whose source files read here equal 2e7d874's: `src/probe_0337_test.odin` (text in `tmp/0337/probe.odin.txt`) replays the forest's rules candidate by candidate (checked equal to `planet_trees_in_box` on every 8th tile) with thread local counters in `generation_planet.odin` and a simulated noise cell cache in `value_noise` and `gradient_noise` (`tmp/0337/probe_tree_source.diff`); logs `tmp/0337/logs/run1.log` to `run6.log`. The shipped home at a preset with `new_world_home` and its waters, `DEFAULT_WORLD_SEED`, the tiles `field_tree_tiles_around` gives to 1024 m. The tech demo's start at 8 km (`planet_spring_start`) lies at (79, 151) and gives the same tiles as 0314's spring camera. Counts only.

### The counts that decided it

| To 1024 m | Home 8 km | Start 8 km | Home 4 km | Home 16 km |
|---|---|---|---|---|
| Tiles; candidates; trees | 275; 917k; 391k | 292; 911k; 390k | 301; 906k; 335k | 277; 924k; 265k |
| Cube tests; straddling; in the z windows | 72.1M; 1.13M; 1.40M | 76.5M; 1.21M; 1.49M | 78.9M; 1.20M; 1.60M | 72.6M; 1.13M; 1.40M |
| Reads: ground + slope (a standing tree) | 442k + 825k (3.24) | 430k + 850k (3.28) | 413k + 682k (3.26) | 380k + 538k (3.46) |
| Refused after the ground read: carving, sea, lake, climate; at the slope | 382, 26.5k, 2.4k, 0; 21.0k | 210, 183, 4.4k, 0; 35.4k | 41, 71.0k, 1.1k, 0; 5.3k | 103, 109.7k, 1.1k, 348; 3.7k |
| Lattice hashes; of them the reads' | 154.1M; 105.7M | 155.9M; 107.1M | 136.6M; 89.6M | 116.7M; 72.8M |
| Spared by the density and the sea boxes: hashes, reads | 4.0M, 9.7k | 2.9M, 0 | 8.6M, 44.2k | 14.4M, 79.8k |
| The reads' noise evaluations a 256 cell cache serves | 95.0% | 95.1% | 95.2% | 94.2% |

- The rules run in this order: the clearing, the draw against the cover (the moisture and two cover noises, 32 hashes), the gap, the ground read (carving, sea, lake), the climate, the two slope reads, the stands. At the home they refuse 440, 426k (92k of them with the draw at or over the density), 48k, 29k, 0 and 21k candidates.
- The reads are the trees' own: a base and two slope probes per standing tree, 93% of the home's reads. A read in the home's view is 83 lattice hashes, 82 of them its 10.3 noise evaluations' corners. The tree line (the climate) refuses 348 candidates at 16 km and none at the others.
- 512 m (the Android row): the home 403k reads for 129k trees, none refused by the sea; the start 365k for 114k.

### The change

Three steps in `generation_planet_trees.odin` spare the candidates' work and keep every tree's bytes (the design's part A; its part B, a cache of the noises' cells that makes every read cheaper, is 0338, Decisions):
1. The cube loop: `planet_trees_in_box` tests, per (x, y) column of cubes, only the z windows where a cube can straddle the sphere, still through `cube_straddles_sphere`, in the same order. 72.1M tests become 1.40M at the home.
2. The density: a forest candidate whose draw is at or over `term.forest_density` is refused before the moisture and the cover's noises. Exact: `upper` is at most the density, since `max(cover, scatter)` is at most `NOISE_ONE` (`scatter_percent` at most 100, the cover a ramp times a share). 10% of the candidates.
3. The sea boxes, the tiles only: boxes of `PLANET_TREE_SEA_BOX_CUBES` (8) cubes. When a candidate's ground read refuses it with its relief under the sea plus the margin, its box's relief range (0314's `relief_box_bound` over the box's cubes) is read once; while that range's highest lies under the sea plus the margin, the box's later candidates are refused before the cover. Exact: every candidate's point lies in its cube, so the range holds its relief; a box the crater may reach decides nothing. 733 bounds at the home (77k hashes), 5.8k at 16 km, 15 at the start.

Rejected:
- 0314's range at the ground read for the sea, the lakes and the tree line, boxes of 8 cubes: 10.2k reads spared at the home for 1.98M hashes of bounds (the reads spared are 0.85M hashes), 46k at 4 km, 85k at 16 km; the lakes and the tree line 69 and 504 at most, at boxes of 8 to 32 cubes. The triggered sea box keeps the gain without the bounds where no sea lies.
- A range for every box before the cover: 2.0 to 2.3M bound hashes a view, 0 candidates refused at the start.
- The cover's most per box (its noises' ranges): 239k candidates at the home against 92k by the density, 4.7M hashes more for 0.65M and a second range path.
- The slope's two reads from a range over the probes' box against the base's exact relief: 44k of 412k candidates at the home, 35.5M hashes of ranges to spare 7.4M; the ranges are 2.35 m wide over 1.4 m.
- One read per tree instead of per candidate: the reads already are per tree (3.24), see above.
- The far cards' tiles from a coarser relief: other bytes, and a tile stays cached as the eye nears it while the felling and the trunks regenerate their tree by key.
- A slope from a lattice of reads: other bytes, needs the record (question 2).

### Files and procedures

`src/generation_planet_trees.odin` (header: add one sentence after the Matérn sentence: "`planet_trees_in_box` tests only the cubes its column windows can make straddle the sphere, a draw over the density skips the cover, and a tile's sea boxes refuse candidates under the sea before it (0337); the trees are the same either way."):
- `PLANET_TREE_SEA_BOX_CUBES :: 8`, comment: a tile's sea boxes are this many tree cubes an edge (16 m at the shipped spacing; at 8 km the probe's boxes of 8 refused 13.4k candidates where 16 refused 0.5k).
- `Tree_Sea_Box :: enum u8 {Unread, Sea, Open}`; `Tree_Sea_Boxes :: struct {first: [3]i64, count: [3]i64, boxes: []Tree_Sea_Box}`, comment: a box query's sea boxes (0337), `first` the key of the box holding the query's first cube, `count` per axis, `boxes` x fastest.
- `make_tree_sea_boxes :: proc(term: Planet_Tree_Term, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> Tree_Sea_Boxes`: the keys `floor_divide_i64(floor_divide_i64(corner, spacing), PLANET_TREE_SEA_BOX_CUBES)` per axis of both corners, all `Unread`. Called by `generate_field_tree_tile`.
- `tree_sea_box_of :: proc(sea: ^Tree_Sea_Boxes, cell: [3]i64) -> ^Tree_Sea_Box`: the box holding the cube, by the key less `first`, flattened `x + count.x * (y + count.y * z)`.
- `planet_tree_sea_floor :: proc(generation: Planet_Generation) -> i64`: `generation.sea_radius - generation.radius + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES)`, the least relief a tree stands on; `planet_tree_ground` and the box read it.
- `tree_sea_box_under_sea :: proc(generation: Planet_Generation, key: [3]i64) -> bool`: `relief_box_bound(generation, World_Position(key * N * spacing), World_Position((key + 1) * N * spacing - 1))` with `N` the box cubes; true when not `crater` and `relief.highest < planet_tree_sea_floor(generation)`. Comment: a candidate's point lies in its cube, which the box holds, so the range holds its relief (0314).
- `tree_cube_z_windows :: proc(x, y, first_z, last_z, spacing, radius: i64) -> (windows: [2][2]i64, count: int)`: per axis x and y of the column `near := clamp(0, value * spacing, value * spacing + spacing)`, `far := max(abs(value * spacing), abs(value * spacing + spacing))`, summed squares `near_squared`, `far_squared`; none when `near_squared > radius²`; `most := isqrt(radius² - near_squared)`, `least := isqrt(max(radius² - far_squared, 0))`; the window below `{floor_divide_i64(-most - spacing, spacing) - 1, min(floor_divide_i64(-least, spacing) + 1, -1)}`, above `{max(floor_divide_i64(least - spacing, spacing) - 1, 0), floor_divide_i64(most, spacing) + 1}`, each clipped to `first_z ..= last_z`, dropped when empty, merged with the one before when they touch, ascending. Comment why: a cube straddles when its nearest point is within the radius and its farthest beyond, so its z span must reach `least` and its nearest z offset stay within `most`; each end is widened by a cube, so the windows hold every straddling cube and the test in the loop decides.
- `planet_tree_ground`: returns the column's relief also when it refuses (`ok` false); the comment says so. Its callers keep `or_return`.
- `forest_tree_from_candidate :: proc(generation: Planet_Generation, cell, on_sphere: [3]i64, hash: u64, sea: ^Tree_Sea_Boxes = nil) -> (tree: Planet_Tree, ok: bool)`: after the clearing and the draw, refuses when `draw >= term.forest_density` (comment: `upper` never exceeds it), then when `sea != nil` and the cell's box is `Sea`; at the ground's refusal, when `sea != nil`, the relief lies under `planet_tree_sea_floor` and the box is `Unread`, sets it to `Sea` or `Open` by `tree_sea_box_under_sea`. The comment's rule list names both.
- `append_planet_tree` gains `sea: ^Tree_Sea_Boxes` (passed to the forest's rule; the groves ignore it).
- `planet_trees_in_box :: proc(generation: ^Planet_Generation, minimum, maximum: [3]i64, allocator := context.temp_allocator, sea: ^Tree_Sea_Boxes = nil) -> [dynamic]Planet_Tree`: x, then y, then each window of `tree_cube_z_windows` ascending. The box assert stays. The comment names the windows and the sea boxes, built by the caller for a tile.

`src/world_field_streaming.odin`: `generate_field_tree_tile` makes `make_tree_sea_boxes(generation.trees, minimum, maximum)` and passes it. Every other caller (the trunks, the felling, the tests) passes none and pays no bound.

No data key, no record field, no save change, no string.

### Same bytes, and the tests

The trees stay the bytes they are; nothing is recorded. New tests:

`src/generation_planet_trees_test.odin`:
- Helpers: `tree_test_watered_planet(radius_metres: int) -> Planet` (`waters_test_planet` with `water_features = make_planet_water_features(DEFAULT_WORLD_SEED, planet)`, freed with `destroy_planet_water_features` by the test); `tree_test_coast(generation: Planet_Generation, planet: Planet) -> (point: [3]i64, found: bool)`, from the home on 32 bearings (`i32(bearing * ANGLE_UNITS_PER_TURN / 32)`) in steps of 16 m to 1024 m, bearing by bearing, the first `tree_test_point_from_home` whose `surface_relief` lies under `planet_tree_sea_floor`; `forest_tree_reference`, 0310's `forest_tree_from_candidate` as it stands at 2e7d874, copied (comment: the oracle the new rules are held to); `trees_by_every_cube(generation: ^Planet_Generation, minimum, maximum: [3]i64) -> [dynamic]Planet_Tree`, 0310's loop: every cube x, then y, then z, `cube_straddles_sphere`, `lattice_candidate`, `forest_tree_reference` or, without the forest, `grove_strength` and `planet_tree_from_candidate` as `append_planet_tree` does.
- `test_the_cube_windows_hold_every_straddling_cube`: radii 1000, 4000, 8000 and 16000 m, spacings 2 and 4 m, the tile of `field_tree_tile_cells` cubes an edge holding the point on the sphere of 26 directions (the six axes, the 12 edge midpoints and the 8 corners of the cube, normalised) and 8 hashed ones: for every (x, y) column of the tile every z whose cube `cube_straddles_sphere` lies in one of the windows; the windows ascend, do not overlap and lie within the tile; their summed length is at most the column's straddling cubes plus 8.
- `test_the_tile_trees_match_every_cube` (slow): `tree_test_watered_planet` at 4000, 8000 and 16000 m, the tiles of `field_tree_tiles_around` within 64 m of the home's surface and of `tree_test_coast` (found at each radius: the probe's sea refusals lie within 1024 m at all three); the 8000 m home's tiles at `DEFAULT_WORLD_SEED + 1`; `grove_test_planet()`'s home tiles. Per tile `planet_trees_in_box` with the sea boxes `make_tree_sea_boxes` makes, `planet_trees_in_box` without them and `trees_by_every_cube` are equal (`trees_equal`); at 4000 and 16000 m the coast's tiles mark at least one box `Sea`.

Unchanged and passing: 0310's tree tests, 0306's and 0314's parity tests (`test_the_bounded_generation_matches_the_samples` and its three siblings, `test_an_old_world_file_keeps_its_relief`).

The report (`test_report_the_relief_cost`, `generation_planet_landforms_test.odin`): after the planets' loop, `report_tree_tile_cost` also for the shipped home at 16000 m (`waters_test_planet(16000)`, its home camera as the loop's), whose tiles hold the most sea. No other change.

### Docs

- `doc/architecture.md`, World generation: the trees' bullet, after "`planet_trees_in_box` returns the standing trees of a box in key order": it tests only the cubes of each column's windows that can straddle the sphere (`tree_cube_z_windows`); a forest candidate whose draw is at or over the density skips the cover's noises; a tree tile's boxes of 8 cubes refuse their candidates before the cover once a candidate met the sea and the box's relief range (0314's bound) lies under the sea plus the margin (`Tree_Sea_Boxes`); the trees are the same bytes either way, and what remains is the trees' own reads, a base and two slope probes each (0337).
- `doc/code_map.md`: no new file; `python3 tools/code_graph.py --check doc/code_map.md` passes.
- The log (main agent): the counts table, that the reads are the trees' own, the rejected ranges with their counts.

### Hand-back check lines that apply

- A changed save layout: none; the trees' bytes are unchanged, proven by `test_the_tile_trees_match_every_cube` against 0310's rule, with the parity tests.
- A new participant in a shared budget: none; the tree jobs on the workers shrink.
- A list that grows without bound: the sea boxes are sized from the query's box, which `PLANET_TREE_BOX_CELL_LIMIT` already caps (a tile 512 bytes).
- Tests never touch the state directory: all generate in memory.

### Where it meets 0326 and 0327

Both land before this item, so the implementation starts from their tree.
- 0326 makes `planet_trees_in_box` read a copy of the generation whose `lakes` come from `generation_lakes_meeting_box`: the windows and the sea boxes go into the same procedure and read that copy (`relief_box_bound` reads no lakes).
- 0327 adds a cave refusal to `planet_tree_ground` after the lakes: it returns the relief like the others, and a relief over the sea floor never marks a box. Its `Relief_Box_Bound` gains the caves' fields and `relief_box_bound` computes them after the relief: `tree_sea_box_under_sea` reads only `relief` and `crater`, and pays the caves' bounds only for the few boxes a sea refusal reads.
- The rebase meets them in `planet_trees_in_box` (0326's copy), `planet_tree_ground` (0327's refusal) and the trees' header comment.

### The item's open questions

- Which candidate: the three steps above and 0338's cache; the item's three fail by the counts above (the range at the ground spares 1% at the home, the reads are already per tree, the coarser far relief changes bytes).
- The same bytes or a record change: the same bytes; nothing is recorded.
- The measure: the report's tree line as 0314 left it, plus the 16 km home.

### Night window (the main agent)

`test_report_the_relief_cost` on `main` and on the item: per place the same tile and tree counts, the tree line's time against the same view's bounded grids and chunks (the share the goal names).

### Questions for the main agent

1. B is generation wide: it changes the hot path of every chunk, grid and water tile, the lever 0314 named as its next. Chosen: in this item, since by the counts it is the only exact lever on the reads, and A alone leaves them within 1 to 9% of today. Or a new item for B, this one keeping A.
2. The slope's reads are 65% of the tiles' reads and fall only with other bytes: a slope from a coarser lattice of reads (recorded with the forest, new worlds only) would read about 0.1M in place of the home's 0.82M (an estimate from the tiles' area at an 8 m lattice, not probed). Open an item for it?

### Decisions (main agent, 2026-11-11)

1. The noise cell cache (the design's part B) is 0338, an item and a stream of its own from `main`: it changes every noise's hot path, so it is reviewed and measured alone, and its landing waits for the night's figures. This item keeps the three steps in the trees' file. With them alone the reads stay within 1 to 9 percent of today, since the reads are the standing trees' own; the item's goal is met only as far as the cube tests (72.1M to 1.40M at the home) and 0338 carry it, and the log says so.
2. No item for a slope from a coarser lattice: it changes new worlds' trees on an estimate nobody probed. It is in `SUGGESTIONS.md`, to weigh once the night's tree line shows what the tiles still cost.
3. The implementation follows 0327 in the stream 0326, 0327, 0337, from 0327's snapshot, as the design says.
