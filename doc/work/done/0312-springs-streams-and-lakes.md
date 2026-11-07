# 0312: Springs, streams and lakes in the highlands

Status: landed (2026-11-07, de88648)

Milestone: the world generation series 0306 to 0313, after 0306. The user (2026-11-06): elevation "for testing the water tech demos".

## Goal

Water belongs to the landscape: springs at valley heads in the highlands, lakes filled in basins above the sea, streams running between them under the water field, all from the seed. The tech demo can start at a spring with a long fall to the sea.

## Controls

None.

## Change

- Springs generated from the relief (valley heads, a count per area from data) beside the record's springs; lakes in basins above the sea filled at generation as the sea is, each a water body (0293).
- The cost of many sources under both water models measured, and a cap or a sleep rule if needed.
- Old worlds keep their water: off in a world record without it.
- Docs: `doc/fluids.md`, `doc/content.md` (Planets); the log.

## Verify

- The checks and the suite.
- A map of the springs and lakes over 0306's relief map; a clip of a stream from its spring to a lake in the tech demo; sent to the user.

## Specification (design, 2026-11-07)

Designed on 0322's ground (the shipped ledges at 0, 0322 lands first in this stream) and today's relief otherwise; every figure below is measured with `ledge_amplitude_millimetres = 0`. The finder was tuned in an integer prototype that copies the generation (`tmp/0312/proto/`, `~/opt/odin/odin build tmp/0312/proto -out:tmp/0312/proto0.bin -o:speed -define:COARSE_DEPTH=100 -define:LEDGES=0`, mode `waters <radius> <reach> <grid> <catchment> <spacing> <map size> <out.ppm>`). Images: `tmp/0312/springs_lakes_sheet.png` (8 km over 5 km and 2 km round the home, 4 km, 16 km; lakes blue, derived springs cyan, the first ranked yellow, the record's orange, the drainage pink), `tmp/0312/springs_lakes_sheet_ledged.png` (the same on main's ledged ground). The implementation's figures will differ in detail from the prototype's; the tests pin the implementation's and the report names both.

### The answers

1. **Springs** are the channel heads of the drainage in the highlands: on a grid round the home a priority flood from the border and the sea gives every cell its filled height and the cell it drains to; a cell draining at least `spring_catchment_square_metres` with no donor that does, not in a depression, at least `spring_minimum_metres` over the sea, is a valley head. Ranked by the fall to the sea, kept at least `spring_spacing_metres` from every spring kept before and from the record's springs. The count per area is that spacing (the shipped 400 m gives 22 springs over the 25 km² round the home at 8 km, 11 at 4 km, 4 at 16 km). Integer, deterministic, ties by grid index. Only within `reach_metres` of the home (at most half the radius): question 1.
2. **Lakes** are the grid's depressions (filled height over the relief) at least the minimum depth and half the minimum area, each refined round its pit on a 2 m grid: a priority flood from the pit that passes saddles lower than the coarse level less 2 m and stops at the first saddle above (the pour point), bounded by a `lake_maximum_metres` window; the level is that sill less `lake_margin_millimetres`, the lake is the pit's 4-connected cells under it, dilated by one cell into a bit mask, then sealed on the 1 m lattice (a column under the level in the mask beside one outside it and under the level lowers the level to that column's height, up to 4 rounds). The generation fills every air sample the mask holds under the level with `field_sea_fill(level)`, asleep and no one's, as the sea is filled. At 8 km 20 lakes, the largest 5.8 ha and 10.9 m deep inside the ring range, most 0.1 to 1 ha and 1.5 to 4 m; 9 at 4 km, 11 at 16 km; no lake leaks on the 1 m lattice. Cost: the finder runs once per session on the main thread, 224k relief evaluations at 8 km (98k grid, 118k refine, 7k seal), 0.31 s at `-o:speed` on a loaded machine; a chunk pays only when a lake's bound meets it, a projection per air sample.
3. **Streams are not generated.** Water on a slope is not at rest, so a generated stream is either awake in every chunk from its first tick or asleep and wrong; the simulation makes each stream from its spring as today. A spring exists only in loaded chunks, so no distance activation is needed. The cap is the spacing: `MINIMUM_SPRING_SPACING_METRES` (400) exceeds the space diagonal of the largest simulated set (7 chunks of 32 m at 1 m spacing, 388 m), so a player's set holds at most one derived spring, and the cost per player is the one spring 0301 measured (unoptimised worst tick 4.6 ms bodies, 15.3 ms teleport). `test_report_the_waters_cost` measures it optimised under both models. No sleep rule.
4. **Old worlds**: the record gains `waters`, zero in a file written before it: no derived springs, no lakes, the tech demo's start the record's first spring, one log line.
5. **The tech demo's start** is the spring, the record's or a derived one, whose drainage falls furthest to the sea: at 8 km the record's (79, 151) (78.8 m against the best derived 69.1 m), at 4 km a derived one (79.6 m against 21.4 m), at 16 km the record's (81, 139) (66.2 m). The pod's heading stays on the record's first spring. Question 2.

Lakes under the models: teleport reads only bytes, so a generated lake is asleep water until something wakes it. Under bodies a still sample no one owns that a flood claims now joins the body's volume asleep (it used to wake as front), and an arriving chunk's generated lake water either makes the body across its face flood again or wakes its lowest sample, which seeds a body by the front's rule after `still_ticks_to_sleep`: a lake becomes one body without its samples ever turning front.

### Data: `Planet_Waters` (`data_planet.odin`)

A new optional planet object `waters`, off at the zero value; `OPTIONAL_PLANET_KEYS` gains `"waters"` (appended after whatever 0323 and 0324 appended), `missing_planet_key_problem` checks a present `waters` object for every key (`planets[%d].waters is missing %s`).

| Key | Bounds | Shipped |
|---|---|---|
| `reach_metres` | `MINIMUM_WATERS_REACH_METRES` (256) to `MAXIMUM_WATERS_REACH_METRES` (8192); used as `min(reach, radius_metres / 2)` | 2500 |
| `grid_metres` | 4 to 64, and `reach_metres / grid_metres` at most `MAXIMUM_WATERS_GRID_HALF_CELLS` (512) | 16 |
| `clearing_metres` | 0 to `reach_metres` | 250 |
| `spring_catchment_square_metres` | `grid_metres²` to 4,000,000 | 4000 |
| `spring_minimum_metres` | 0 to `MAXIMUM_RELIEF_HEIGHT_METRES` (over the sea) | 25 |
| `spring_spacing_metres` | `MINIMUM_SPRING_SPACING_METRES` (400) to 10,000 | 400 |
| `lake_minimum_depth_millimetres` | 100 to 64,000 | 1500 |
| `lake_minimum_area_square_metres` | 4 to 1,000,000 | 400 |
| `lake_maximum_metres` | 16 to 1024 (the refine window's edge) | 384 |
| `lake_margin_millimetres` | 0 to 4000 | 500 |

- `waters_problem :: proc(waters: Planet_Waters) -> string`: the zero value passes; otherwise every key in its bounds, the message naming the key (`waters.grid_metres 3 is outside 4 to 64`). Called from `planet_problem` after `climate_problem`.
- Constants beside it, each with a one line comment: the five bounds above, `MAXIMUM_PLANET_LAKES :: 128`, `MAXIMUM_DERIVED_SPRINGS :: 128`, and `MINIMUM_SPRING_SPACING_METRES :: 400` ("the space diagonal of the largest simulated set, 7 chunks of 32 m at 1 m spacing, is 388 m: a player's set holds at most one derived spring").
- The derived types, plain data in `data_planet.odin` (the content cluster may not reference the world cluster, and `Planet` holds them):
  - `Planet_Water_Spring :: struct { direction: [3]i64, height, drop: i64, to_sea: bool }`: the unit direction of the grid cell, its relief over the radius, the fall to its outlet (to the sea level when `to_sea`, else to the border cell), position units.
  - `Planet_Lake :: struct { centre, east, north, origin, bound_centre: [3]i64, level, floor, bound_radius, half: i64, cells: i32, mask: []u64 }`: the pit's unit direction and its tangents, `origin` the pit on the sphere of the radius, the level and the floor over the radius, the mask's half width in 2 m cells (side `2 half + 1`, bits row `v + half` then column `u + half`), the water cells before the dilation, and the sphere holding every water sample.
  - `Planet_Water_Features :: struct { springs: []Planet_Water_Spring, lakes: []Planet_Lake, start: [3]i64, has_start: bool }`.
  - `destroy_planet_water_features :: proc(features: ^Planet_Water_Features)`: deletes every mask, both slices, zeroes it.
- `Planet` gains `waters: Planet_Waters` (comment "Optional in the file, off at zero (0312).") and `water_features: Planet_Water_Features \`json:"-"\`` ("set by the session from the seed and the record (make_planet_water_features), never by the data").
- `data/planets.sjson`, after `climate`: a `waters` block with the shipped values and a comment line per key; the `springs` comment gains "The waters below add springs at the highlands' valley heads and lakes, and the tech demo starts at the spring whose water falls furthest to the sea."

### The record (`generation_planet_record.odin`)

- `Planet_Generation_Record` gains `waters: Planet_Waters` ("Zero in a file written before it (0312): no derived springs, no lakes."), copied by `planet_generation_record`.
- `make_recorded_planet`: `result.waters = record.waters` set explicitly (the data's never reach an old world) and `result.water_features = {}`.
- `destroy_recorded_planet` calls `destroy_planet_water_features(&planet.water_features)` first.
- `recorded_waters_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string`: for a recorded file whose `waters` is zero while the data planet's is not, `"world: the world file records no waters, it keeps its springs and has no lakes"`, else "". `resolve_world_planet` logs it after the climate note.
- No remap: zero is off.

### The finder: new file `src/generation_planet_waters.odin`

Header comment: the waters of 0312 (doc/architecture.md, World generation), integer and fixed point, a pure function of the seed and the recorded planet (the spacing never moves a spring or a lake), run once per session; read `uncratered_relief` only, so the crater never makes a lake. Heights and levels are position units over the radius, as `uncratered_relief` returns them; `sea` is `generation.sea_radius - generation.radius`; metres and millimetres go through `metres_to_position_units` and `millimetres_to_position_units`.

Constants: `LAKE_CELL_METRES :: 2`, `WATERS_REFINE_TOLERANCE_METRES :: 2`, `LAKE_SEAL_ROUNDS :: 4`, `LAKE_DESCENT_STEPS :: 64`, `WATERS_BORDER_CELLS :: 4`, `WATERS_NEIGHBOURS :: [8][2]i64{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}`, `WATERS_FACES :: [4][2]i64{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}`.

Types: `Waters_Plane :: struct { centre, east, north: [3]i64, radius, step: i64 }`; `Waters_Entry :: struct { height: i64, index: i32 }`; `Waters_Grid :: struct { plane: Waters_Plane, half, side: int, heights, filled: []i64, parent, order, area, outlet: []i32 }`; `Waters_Depression :: struct { cells, pit: int, level, floor: i64, border: bool }`.

Procedures, each with a one line comment:

- `planet_tangents :: proc(direction: [3]i64) -> (east, north: [3]i64)`: `relief_map_tangents` moved here unchanged (east the cross of +y with the direction, +x where `|y| >= 9/10`); the relief map calls it and `relief_map_tangents` is removed.
- `waters_plane_direction :: proc(plane: Waters_Plane, east_cells, north_cells: i64) -> [3]i64`: `normalize_fixed(fixed_scale(centre, radius) + fixed_scale(east, east_cells * step) + fixed_scale(north, north_cells * step))`, the gnomonic plane's point.
- `waters_plane_coordinates :: proc(plane: Waters_Plane, point: [3]i64) -> (east, north: i64, ok: bool)`: the inverse in position units: `along := fixed_dot(point, centre)`, false when `along <= 0`, else `fixed_dot(point, east) * radius / along` and the same for north.
- `waters_plane_height :: proc(generation: Planet_Generation, plane: Waters_Plane, east_cells, north_cells: i64) -> i64`: `uncratered_relief(generation, fixed_scale(waters_plane_direction(...), generation.radius))`.
- `push_waters_entry`, `pop_waters_entry :: proc(heap: ^[dynamic]Waters_Entry, ...)`: a binary min heap by (height, index), the water bodies' heap pattern, so the order never depends on a library.
- `make_waters_grid :: proc(generation: Planet_Generation, home: [3]i64, waters: Planet_Waters, radius_metres: int, allocator := context.allocator) -> Waters_Grid`: `plane = {home, planet_tangents(home), generation.radius, metres_to_position_units(grid_metres)}`, `half = min(reach_metres, radius_metres / 2) / grid_metres`, row major from (-half, -half), every height.
- `flood_waters_grid :: proc(grid: ^Waters_Grid, sea: i64)` (`sea` the sea level over the radius): every border cell and every cell under the sea is an outlet (filled its height, parent -1) pushed in index order; pop, append to `order`, push each unvisited 8-neighbour in `WATERS_NEIGHBOURS` order with `filled = max(height, popped filled)` and the popped cell as parent. Then `area` (1 each, added to the parent in reverse `order`) and `outlet` (in `order`: its own index for an outlet, else the parent's outlet).
- `destroy_waters_grid`.
- `find_waters_depressions :: proc(grid: ^Waters_Grid, allocator := context.temp_allocator) -> [dynamic]Waters_Depression`: the 8-connected components of `filled > height` in index order of their first cell: cells, the pit (lowest height, then lowest index), the level (the component's filled height), the floor, and whether a cell lies within one cell of the grid's edge.
- `planet_lake_holds :: proc(lake: Planet_Lake, on_sphere: [3]i64, radius: i64) -> bool`: `waters_plane_coordinates({lake.centre, lake.east, lake.north, radius, metres_to_position_units(LAKE_CELL_METRES)}, on_sphere)`, cells `u = floor_divide_i64(east + step / 2, step)` and `v` alike, inside the window and the bit set. The generation, the trees, the coarse grid and the relief map read lakes only through it.
- `planet_lake_level_at :: proc(lakes: []Planet_Lake, on_sphere: [3]i64, radius: i64) -> (level: i64, found: bool)`: the first lake in order holding the point.
- `refine_planet_lake :: proc(generation: Planet_Generation, waters: Planet_Waters, pit: [3]i64, coarse_level: i64, allocator := context.allocator) -> (lake: Planet_Lake, ok: bool)`: the plane at `pit` with a 2 m step, `half = lake_maximum_metres / (2 * LAKE_CELL_METRES)`, heights evaluated once each on demand. Descend from (0, 0) at most `LAKE_DESCENT_STEPS` times to the strictly lowest 8-neighbour. Priority flood from there: pop; when its height is under the running sill and the sill is at least `coarse_level - metres_to_position_units(WATERS_REFINE_TOLERANCE_METRES)`, the sill is the spill, stop; when under the sea level, the spill too, stop; else the sill rises to it, the cell is claimed, its unpushed 8-neighbours pushed; a neighbour at `|u|` or `|v| >= half` refuses the lake (too big), an empty heap refuses it. `level = sill - millimetres_to_position_units(margin)`; refused when `level - floor` is under the minimum depth. Water: the pit's 4-connected claimed cells under the level; refused when `cells * 4` is under the minimum area. The mask: the water dilated by one 8-neighbour cell. Then `seal_planet_lake`; refused when it fails or the sealed depth is under the minimum. Fills `origin`, `cells`, `floor` (the pit's height), and the bound: `bound_centre = fixed_scale(pit, radius + level)`, `bound_radius = (half + 1) * step * 3 / 2 + (level - floor) + metres_to_position_units(2)`.
- `seal_planet_lake :: proc(generation: Planet_Generation, lake: ^Planet_Lake) -> (level: i64, ok: bool)`: on the lake's plane with a 1 m step, lattice points `x, y` in `-2 half ..= 2 half`, a point's cell `floor_divide_i64(x + 1, 2)`: for at most `LAKE_SEAL_ROUNDS` rounds, every point in the mask with a 4-neighbour outside it and its height under the level: the lowest height of those outside neighbours; none under the level ends it (ok), else the level drops to that lowest. Heights evaluated once each (a map in the temp allocator).
- `find_planet_lakes :: proc(grid: ^Waters_Grid, generation: Planet_Generation, waters: Planet_Waters, home: [3]i64, allocator := context.allocator) -> []Planet_Lake`: depressions in order, skipping one at the border, with `level - floor` under the minimum depth, with `cells * grid_metres²` under half the minimum area, whose pit lies within `clearing_metres` of the home (chord on the sphere of the radius) or in a lake kept before; refine at the pit's direction; keep when its `origin` lies outside the clearing; at most `MAXIMUM_PLANET_LAKES`.
- `find_planet_springs :: proc(grid: ^Waters_Grid, waters: Planet_Waters, lakes: []Planet_Lake, record: []Planet_Spring, home: [3]i64, sea, radius: i64, allocator := context.allocator) -> []Planet_Water_Spring`: catchment cells `spring_catchment_square_metres / grid_metres²`; a candidate cell has that area, no donor (a cell whose parent it is) with that area, `filled == height`, `height >= sea + metres_to_position_units(spring_minimum_metres)`, lies `WATERS_BORDER_CELLS` from the edge, outside the clearing, and no lake holds it under its level; `to_sea` when its outlet's height is under the sea, `drop` its height less the sea level, or less the outlet's height. Sorted by `to_sea` first, then the larger `drop`, then the lower index; kept when its point (on the sphere of the radius) lies at least `spring_spacing_metres` from every record spring's and every spring kept; at most `MAXIMUM_DERIVED_SPRINGS`.
- `planet_water_start :: proc(grid: ^Waters_Grid, record: []Planet_Spring, springs: []Planet_Water_Spring, sea: i64) -> (start: [3]i64, found: bool)`: the candidates draining to the sea: each record spring in order whose grid cell (`waters_plane_coordinates`, rounded to the nearest cell) lies inside the grid `WATERS_BORDER_CELLS` from the edge, its fall that cell's height less the sea, its own direction kept; then the derived springs with `to_sea`. The largest fall, the first in that order on a tie.
- `make_planet_water_features :: proc(seed: u64, planet: Planet, allocator := context.allocator) -> Planet_Water_Features`: `{}` when `planet.waters == {}`; else `generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)`, the home's direction, the grid, the flood, the lakes, the springs, the start, the grid destroyed.
- `planet_lake_fill_level :: proc(generation: Planet_Generation, lake: Planet_Lake) -> i64`: `floor_divide_i64((generation.radius + lake.level) * FIELD_WATER_FULL * MILLIMETRES_PER_METRE, i64(generation.spacing_millimetres) * POSITION_UNITS_PER_METRE)`, `field_sea_level`'s formula.
- `planet_lake_meets_box :: proc(lake: Planet_Lake, minimum, maximum: [3]i64) -> bool`: the squared distance from `bound_centre` to the box at most `bound_radius²`.
- `fill_field_chunk_lakes :: proc(generation: Planet_Generation, chunk: ^Field_Chunk)`: nothing without lakes; the lakes meeting the chunk's box (its first and last samples' positions) in a temp list; every sample with `density <= 0` and `water == 0`: `on_sphere = project_onto_sphere(position, vector_length(position), radius)`, the first listed lake holding it decides, `fill = field_sea_fill(planet_lake_fill_level(...), field_water_span(sample))`, written when above 0. Owner none, no awake or source bit. If 0324's three-dimensional term has landed, a sample whose air comes from that term stays dry (question 6).
- `planet_lake_density :: proc(generation: Planet_Generation, lakes: []Planet_Lake, position: World_Position, terrain: i8) -> i8`: `-MAXIMUM_DENSITY` in ground or held by no listed lake, else `depth_to_density(generation.radius + lake.level - distance, spacing)`, `planet_sea_density`'s rule.
- `planet_spring_may_lie_in_chunk :: proc(generation: Planet_Generation, direction: [3]i64, coordinate: Field_Chunk_Coordinate) -> bool`: the box centre `c` of the chunk, false when `fixed_dot(c, direction) <= 0`, else `vector_length(c - fixed_scale(direction, fixed_dot(c, direction)))` at most `29 * spacing` (the half diagonal of 32 samples and one more).

### Changed procedures

- `generation_planet.odin`: `Planet_Generation` gains `lakes: []Planet_Lake` (borrowed, `planet.water_features.lakes` in `make_planet_generation`'s literal). `planet_spring_sample_at :: proc(generation: Planet_Generation, direction: [3]i64) -> (sample: Sample_Coordinate, found: bool)` holds today's body; `planet_spring_sample` wraps it. `mark_field_chunk_springs` marks the record's springs as now, then each derived spring that `planet_spring_may_lie_in_chunk` lets through, through `planet_spring_sample_at`, skipping one without air quietly. `generate_field_chunk` calls `fill_field_chunk_lakes(generation, chunk)` after `fill_field_chunk_sea` and before the springs. The header comment names the lakes and the derived springs.
- `world_field_lod.odin` `generate_field_grid`: the lakes meeting the grid's box (origin to `origin + (FIELD_GRID_CELLS + 1) * step`, one step either side) listed once; with any, `water = max(water, planet_lake_density(density_generation, listed, position, value.density))` for a sample not loaded. The comment names the lakes.
- `generation_planet_trees.odin` `planet_tree_from_candidate`: after the sea's rule, no tree where `planet_lake_level_at(generation.lakes, on_sphere, generation.radius)` finds a level and `relief < level + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES)`. The header comment says "below the sea or a lake".
- `session.odin` `resolve_session_planet`: after the new world's home, `session.planet.water_features = make_planet_water_features(plan.seed, session.planet)` (loaded worlds too, from the recorded home). The copies in `simulation.world.planet`, the workers' and the water planet's generation borrow it; `end_session` and the failure path free it through `destroy_recorded_planet` after the workers stop, as now.
- `simulation_field.odin`: `planet_spring_start :: proc(planet: Planet) -> (direction: [3]i64, found: bool)`: `water_features.start` when `has_start`, else the record's first spring, else not found. `field_spring_spawn` starts from it (its comment: the spring whose water falls furthest to the sea, 0312); `field_home_heading` is unchanged.
- `world_field_water_body.odin` `claim_water_flood_sample`: the branch for `previous == WATER_OWNER_NONE` with water and no awake bit no longer wakes it: `world.water_bodies[id].volume += i64(chunk.water[index])` and it stays asleep, the body's still water from now (its byte is rewritten by the finish's `write_water_body_fills`). The comment: "still water no one owns (a generated lake, 0312) joins the volume as it stands". Old water of a chunk saved before 0293 is woken by `wake_old_field_chunk_water` before any flood, so it is unaffected.
- `world_field_water_body.odin`: `join_field_chunk_lake_water :: proc(world: ^Field_World, chunk: ^Field_Chunk)`: the chunk's samples with water, owner none, no awake or source bit, not ground; none returns. For each face (`FIELD_WATER_NEIGHBOUR_OFFSETS`, `field_face_pairs`) a loaded neighbour's sample across from such a sample owned by a live body (not the sea, not released) with no awake bit marks that body dirty (`mark_water_body_dirty`). When no body was marked, the lowest such sample by (bottom, sample order) is woken (`force_wake_field_water_sample`). `field_world_insert_chunk` calls it in its bodies block after `seed_water_sea_facing`.
- `loop_relief_map.odin`: `run_relief_map` sets `planet.water_features = make_planet_water_features(seed, planet)` and frees it; `relief_map_stream` gains `steps := RELIEF_MAP_STREAM_STEPS`. After the colours: `relief_map_mark_lakes :: proc(colours: [][4]u8, heights: []i64, generation: Planet_Generation, request: Relief_Map_Request, pixels: int)`, every pixel whose point a lake holds and whose height lies under its level takes `RELIEF_MAP_LAKE_COLOUR :: [4]u8{60, 120, 230, 255}`. Each derived spring's stream at `RELIEF_MAP_DERIVED_STREAM_STEPS :: 500` steps in magenta size 1, its marker black 3 under cyan 2; the start's black 5 under `RELIEF_MAP_START_COLOUR :: [4]u8{255, 230, 0, 255}` 3, after the record's markers. Stdout after the record springs' lines: `relief map: waters: <n> derived springs, <m> lakes`, per derived spring `relief map: derived spring <i> at latitude <a>, longitude <o>: <h> m over the sea, falls <d> m to <the sea|the edge>`, per lake `relief map: lake <i> at latitude <a>, longitude <o>: <level> m over the sea, <depth> m deep, <area> m2`, and `relief map: the tech demo's spring at latitude <a>, longitude <o>` (latitude and longitude of a direction in floats, one decimal).

### Tests

New, `src/generation_planet_waters_test.odin` (the shipped planet of `shipped_test_planets()` at a preset with `new_world_home`, features made once per test; those at 1 s or more get the slow mark):

- `test_the_waters_round_the_shipped_home` (8 km, `DEFAULT_WORLD_SEED`): 12 to 32 lakes and 12 to 32 derived springs (prototype 20 and 22). Every lake: depth at least 1.5 m, `cells * 4` at least 400, level over the sea, `origin` outside the clearing, `lake_leaks(generation, lake) == 0` (a helper in the test file: the seal's condition on the final level). Every spring: at least 25 m over the sea, outside the clearing, at least 400 m from every other and from both record springs. `has_start` and `start == planet_spring_direction(springs[0])`. The chunk holding the largest lake's centre at `level - 1 m`, generated: every air sample the lake holds under its level holds `field_sea_fill(planet_lake_fill_level(...))`, owner none, no awake or source bit; at least one does. The chunk of the first derived spring's sample has its source bit. `planet_trees_in_box` over the largest lake's bound: no tree whose base's point a lake holds under its level plus the margin. `generate_field_grid` of the level 1 node holding the largest lake's centre: some sample not loaded has lake water over the sea's density. The counts and the largest lake are logged.
- `test_the_waters_are_deterministic` (8 km): two makes equal field by field and mask by mask; seed 7 differs.
- `test_the_tech_demo_start_follows_the_longest_fall`: at 4 km the start is a derived spring's direction (prototype: 79.6 m against the record's 21.4 m), at 16 km the record's second (66.2 m); a tech demo session at 4 km with the shipped planets unstripped stands within 2 m of the surface under the start on its radial.
- `test_the_waters_are_off_without_their_keys`: the 0306 design planet (`design_landform_test_planet`) gives `{}`; its generated spring chunk holds no water no one owns.
- `test_waters_problems`: the zero value passes; each key out of its bounds refused by name, `reach_metres / grid_metres` over 512, a catchment under `grid_metres²`, a spacing of 399, and a planets file whose `waters` lacks a key (`planets[0].waters is missing lake_margin_millimetres`).
- `test_an_old_world_file_keeps_its_springs_and_has_no_lakes`: a `world.sjson` text with a `planet_generation` and no `waters`, resolved against the shipped planets: one log line holding "records no waters", the recorded planet's `waters` zero, its features empty.
- `test_a_new_world_records_its_waters`: `planet_generation_record(shipped)` holds the data's `waters`, through `encode_world_file` and `parse_world_file` unchanged.
- `test_report_the_waters_cost` inside `when WATERS_COST` (`WATERS_COST :: #config(WATERS_COST, false)`): per preset the wall time of `make_planet_water_features` and its counts; `generate_field_chunk` of the largest lake's chunk against the home's surface chunk (best of 5); a tech demo session at 8 km per water model at the start, 600 ticks: the worst and mean tick and the awake samples at the end (`./build.sh test quick test_report_the_waters_cost -o:speed -define:WATERS_COST=true`). The implementer puts the figures in its report.

New in `src/world_field_water_body_test.odin`, on the test worlds (`make_body_test_world`, `carve_water_test_box`) with a basin's samples given `field_sea_fill(level)` bytes directly (no wake, owner none):
- `test_still_water_no_one_owns_joins_a_flood_asleep`: `seed_water_body` at the lowest sample with an ample budget: every water sample the body's, none awake, the volume the bytes' sum, `conserved_water` unchanged.
- `test_a_generated_lake_becomes_one_body`: the chunk through `field_world_insert_chunk` wakes exactly one sample; `still_ticks_to_sleep + 10` steps later one body besides the sea owns every water sample, none awake, `conserved_water` unchanged.
- `test_an_arriving_lake_chunk_joins_the_lake_beside_it`: two chunks, the first holding a settled body, the second inserted with still water no one owns at the same level across the face: no sample of it wakes, the body is dirty; after its flood it owns the second chunk's water, still one body, `conserved_water` unchanged.

New in `src/world_field_water_test.odin`: `test_a_generated_lake_sleeps_under_teleport`: the same basin bytes inserted into a teleport world beside a loaded chunk; 40 steps later no sample is awake and every byte is as written.

New in `src/loop_relief_map_test.odin`: `test_the_relief_map_draws_the_lakes`: the shipped planet at 8 km, 128 pixels over 2000 m round the largest lake's origin: its centre pixel has `RELIEF_MAP_LAKE_COLOUR`.

Changed: `make_field_test_game_content` (`simulation_field_test.odin`) zeroes `waters` on its planets ("the suite's sessions skip the finder, about a second unoptimised; the waters' tests use the shipped planets"), so no existing test moves. `test_the_default_springs_stream_runs_downhill` and the other spring tests keep the record's springs.

### Docs

- `doc/content.md`, Planets: `waters` in the optional keys and its ten keys with bounds; the shipped home's waters (reach, grid, spacing, the counts per preset, the largest lake, the start per preset).
- `doc/architecture.md`, World generation: the waters (the region and its cap, the grid, the flood, the channel heads, the depressions, the refine and the seal, the lake fill per chunk and in the coarse grids, the trees, the cost per session). The water field: generated lakes asleep and no one's under both models; under bodies the claim rule and `join_field_chunk_lake_water`; a spring exists only in loaded chunks and the spacing keeps one derived spring per player's set. Save format: `waters` in the record, absent read as off with one log line. The item's `doc/fluids.md` is the pipes' document; the water field lives here, so `doc/fluids.md` is not touched.
- `doc/build.md`, The workbench: the relief map's lakes, derived springs, start marker and lines.
- `data/planets.sjson` comments as above.

### Hand-back lines that apply

- A changed save layout loads an old save: `waters` zero is off, one log line (`test_an_old_world_file_keeps_its_springs_and_has_no_lakes`).
- A new participant in a shared budget: the lakes' floods take `flood_visit_budget` like any body (an arriving lake chunk makes the body beside it flood again); a running derived spring is the one source per set the spacing allows; the finder's 0.3 s and the lake chunks' projections are measured (`test_report_the_waters_cost`).
- A list that grows without bound is capped: lakes and derived springs at 128, the relief map's derived streams at 500 steps, its lines by those caps.
- A file is written to `<path>.tmp`: the relief map as before. Tests never touch the state directory: the relief map test writes nothing.

### What 0323 and 0324 would change

The finder reads the relief, so their terms change the waters without code here. 0323's sinkholes are closed basins and become lakes when at least 1.5 m deep after the seal and inside the 384 m window; if 0323 wants some dry, a lake must skip them by its term. Its gorges gather the drainage: springs at gorge heads and streams down them, but a gorge narrower than about two grid cells (32 m) may be missed at 16 m, so `grid_metres` may go to 8 (four times the grid's 98k evaluations). Cliffs and mesas only move the heads and the paths. 0324's carved air under a lake's level inside its mask would fill (question 6).

### Questions for the main agent

1. The region: derived springs and lakes only within 2.5 km of the home (at most half the radius). The whole planet needs a lazily filled tile cache shared by the workers, a follow-up item. Accept the region?
2. The start: at 8 km it stays the record's (79, 151), which drains to the sea without a lake; no spring at 8 km has a lake within the simulated set's reach (64 to 96 m at 1 m spacing) along its drainage, the nearest 288 m, so the clip from a spring to a lake follows the stream on foot. Accept, or rank the start by the nearest lake on its path?
3. Lake sizes: 20 at 8 km, most ponds of 0.1 to 1 ha; on main's ledged ground 34, smaller. More and larger lakes need closed basins in the relief (0323's sinkholes). Accept?
4. The finder's 0.3 s runs on the main thread at the session's start, before the first chunk. Accept, or spread it over the workers (the grid's rows are independent)?
5. The suite's field sessions skip the finder (their content zeroes `waters`). Accept?
6. If 0324 lands first with its three-dimensional term, name the accessor the lake fill uses to keep 0324's carved air dry, or accept filling it.

### Decisions (main agent, 2026-11-07)

1. The region within 2.5 km of the home is accepted here; the whole planet is 0326.
2. The start stays the longest fall to the sea. The clip of a stream reaching a lake starts at a derived spring that feeds one, picked from the relief map's lines.
3. Twenty mostly small lakes are accepted; 0323's sinkholes become lakes where deep enough after the seal.
4. The finder's 0.3 s on the main thread at the session's start is accepted; `test_report_the_waters_cost`'s figures go into the log.
5. The suite's field sessions skip the finder, as designed.
6. 0324 lands before 0312 in this stream, so its carved air under a lake's level stays dry, through the accessor 0324's landed code gives for that air; the water simulation fills it if it meets the lake. The implementation starts from 0324's snapshot and is checked against 0323's and 0324's landed terms (the finder's figures and the test bounds move with them; report both).
7. The implementer lists where still water no one owns arises today besides the sea and old chunks (a bucket, a released body), and reports what the new claim rule does to each.
