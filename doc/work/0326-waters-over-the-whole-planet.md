# 0326: Waters over the whole planet

Status: designed (2026-11-07)

0312 finds springs and lakes on one grid within 2.5 km of the home (at most half the radius), once per session on the main thread. Past it the ground has no derived springs and no lakes, which a player meets after a few minutes' walk on the 8 km planet.

## Goal

Derived springs and lakes everywhere on the planet, by the same rules as 0312's, without a longer start.

## Controls

None.

## Change

- Tiles of 0312's grid over the planet, found lazily as chunks are wanted and shared by the generation workers, deterministic on every machine whatever order they are asked in. A lake or a drainage crossing a tile's edge is found whole.
- The home's tile is the one the session waits for; the others are found on the workers.
- The relief map draws every tile it covers.
- Docs: `doc/architecture.md` (World generation, the waters).

## Verify

- The checks and the suite, with a test that two orders of asking for the tiles give the same springs and lakes.
- The relief map of the whole 8 km planet, sent to the user.

## Specification (design, 2026-11-07)

Designed on `main` at 0c4916f. The counts come from a probe in `tmp/0326/tree` (`src/zz_probe_0326_test.odin`, relief evaluations counted in `waters_plane_height`), the shipped planet and `DEFAULT_WORLD_SEED`, the 5 by 5 tiles round the home's tile judged from the 7 by 7 analysed; no timings. Shared with designs in flight: 0314 may change how `uncratered_relief` is evaluated, and every relief read here goes through `waters_plane_height` and `refine_planet_lake` as 0312's do, so its change applies without code here; 0334 changes the bodies' merge, not the finder.

### Counts that decided it

| Tiles of 1024 m | 4 km | 8 km | 16 km |
|---|---|---|---|
| Tiles on the planet | 384 | 1536 | 6144 |
| Relief evaluations per tile: window (98 by 98) + refines and seals | 9604 + 3927 | 9604 + 5632 | 9604 + 3658 |
| Pits per tile; escape flood pops per pit, mean and most | 92; 32, 306 | 106; 34, 447 | 129; 19, 336 |
| Lakes, springs per km² | 1.30, 0.27 | 1.64, 0.53 | 0.80, 0.19 |
| Lakes crossing their tile's edge; dropped as overlapping | 7 of 34; 3 | 8 of 43; 1 | 4 of 21; 2 |
| Spring pairs under 400 m; lakes holding another's pit | 0; 0 | 0; 0 | 0; 0 |
| In 0312's disc less 400 m: 0312's lakes (matched by tiles), the tiles' (matched by 0312) | 8 (7), 15 (6) | 23 (22), 33 (22) | 8 (7), 11 (7) |
| The same, springs: 0312's, the tiles' | 6, 4 | 17, 11 | 4, 2 |
| 0312's finder, evaluations | 131,505 | 259,980 | 154,293 |
| Tiles within 1024, 1600, 2600 m of the home | 9, 16, 34 | 9, 15, 31 | 9, 15, 31 |

At 8 km the tile edge: 512 m costs 5741 evaluations a tile and 45 tiles within 1600 m (258 thousand), 1024 m 15,236 and 15 (228 thousand), 2048 m 46,098 and 8 (369 thousand): 1024 m, whose 3 by 3 round the home (137 thousand evaluations) is about half of 0312's finder and runs on the workers.

### The answers

1. **Tiles.** The planet's grid is the six faces of a cube, each the gnomonic plane of 0312's grid (`Waters_Plane`) centred on an axis with `planet_tangents` of it, cells of `grid_metres` (16 m) numbered from the axis; a direction belongs to the face of its largest component (ties to x, then y, then z), and a cell of a face's lattice is owned by that face when its own direction belongs to it. A tile is a square of `tile_metres / grid_metres` cells of one face (shipped 1024 m, 64 cells). Its analysis reads the relief over its cells and a margin of `max(escape reach, catchment cells + 2)` cells (17 shipped; the escape reach is the refine's half window in grid cells plus 4, 16), on its face's plane, past the face's edge where the tile lies there.
2. **No flood from the sea: every feature is a function of its own cell's neighbourhood.** 0312's flood from the grid's border and the sea made a lake's level and a cell's drainage depend on where the grid ends, and a tile far from the coast cannot know its outlet without the tiles between it and the sea. So the rules that read the whole grid take local forms, and a tile only decides which thread computes a feature:
   - A lake starts at a pit, a cell before its 8 neighbours in the order (height, then face, row, column). Its coarse level is the escape level within the escape reach round it: a priority flood from the pit whose first pop of a cell on the reach's ring or under the sea sets the level to the running sill, the minimax path out, which is 0312's filled height wherever the reach holds the basin and its spill. Its basin is the cells under the level popped before the sill last rose (0312's depression). The pit goes on only when it is its basin's first cell in the order (one lake per depression, 0312's lowest pit), the basin keeps off the reach's last two rings (0312's border rule) and 0312's depth, area and clearing filters pass; then 0312's `refine_planet_lake` and seal, unchanged.
   - A cell drains to its first neighbour in the order when that one is before it (0312's flood parent wherever neither lies in a depression). Areas are counted capped at the catchment's cells, exact for every cell `catchment cells + 1` inside the window. A head is 0312's: the catchment, no donor with it, a neighbour it drains to (in place of a filled height equal to its own), the minimum over the sea, outside the clearing, the spacing from the record's springs.
   - A head is a spring when no lake holds its point under the lake's level and no such head within `spring_spacing_metres` ranks before it (higher over the sea, then the cell): local maxima, so springs keep the spacing pairwise, each decided by what lies within the spacing and a lake's reach. 0312's greedy pass in rank order is the rejected form: one choice moves every later one, across any tile edge. Its price: about two thirds of 0312's springs where both count (question 1).
   - Of two lakes from different pits where either holds the other's pit, the later in (water cells descending, then the pit's cell) is dropped, so a basin seen from two pits (at a face seam, or by two reaches that see a far closure differently) fills once.
   - The one thing that needs an outlet, the tech demo's start (the spring whose water falls furthest to the sea), keeps 0312's grid flood round the home (answer 9).
   A lake or a drainage crossing a tile's edge is found whole: a lake by the tile owning its pit, whose refine reads the relief on its own plane wherever it reaches, and which consumers on the other side of the edge ask for (the lake's reach, below); a head by the tile owning its cell, whose margin holds its whole capped catchment; the spacing and the overlaps by the tile's final, which reads the analyses of every tile its items reach. At 8 km 8 of the 43 lakes cross an edge.
3. **Independent of the order.** An analysis is a function of the seed, the record and the tile's key, reading only the relief; a final a function of its analysis and the analyses of the tiles its pits and heads reach (functions of their positions); a consumer reads the finals of the tiles its box reaches and sorts what it gets (lakes by water cells descending then the pit's cell, springs by direction). Nothing reads which tiles happen to be found, so neither the order of finding, the threads, nor an eviction changes a byte; moving the tile lattice would change only the cost. `test_water_tiles_are_found_alike_in_any_order` asks the same tiles in three orders, on four threads and through a cache that evicts.
4. **Where they are found and how a chunk waits.** On whichever thread first asks: the field workers (chunk, mesh and tree jobs), the simulation thread (a leaving chunk's comparison with its generation, `field_trees_near`), the main thread (the tech demo's start, the relief map). A tile has two states, its analysis and its final, each Absent, Finding or Found, in one cache the session's planet points to. Asking claims each Absent state as Finding under the lock, computes it outside the lock and publishes it, then waits on a condition for the states another thread is finding; a final first asks the analyses it reads and an analysis asks nothing, so no wait closes a cycle. A chunk's generation asks the finals of the tiles its box reaches and gets copies. **Deviation from the item's "the home's tile is the one the session waits for":** nothing before the first chunk reads the waters, so the main thread waits for none; the first chunk jobs find the home's 3 by 3 (137 thousand evaluations at 8 km) on the workers in parallel, where 0312 spent 260 thousand on the main thread.
5. **Memory.** A cache keeps at most `MAXIMUM_WATER_TILES` (1024) tiles with a state Found; past it the least recently asked with neither state Finding is freed. Readers get copies (masks included) in their allocator, so an eviction frees nothing a reader holds, and a tile found again is the same function of its key, so identical. A tile holds about 1.9 lakes (a 4.7 KB mask each at the shipped `lake_maximum_metres`) and 11 heads at 8 km, about 10 KB; 1024 tiles about 10 MB. A fresh view needs the finals within the last level distance and a coarsest node (1024 + 256 m) plus a lake's reach of the camera, 15 tiles, and their analyses, 31 (480 thousand evaluations on the workers).
6. **Old worlds.** A world recorded with 0312's waters has no `tile_metres`, which reads 0: the session runs 0312's `make_planet_water_features` unchanged, so the disc holds the same springs and lakes byte for byte, and past it there are none, as before. One log line when the data's waters have tiles: `world: the world file records the waters round the home only, it keeps them and has none past them`. No remap.
7. **Lockstep.** The tiles are functions of the seed and the recorded planet (`waters.tile_metres` beside the other keys, carried by the join snapshot's record), so host and joiner generate the same chunks and trees; eviction and timing change only who computes when.
8. **The relief map** finds every tile its square covers and draws their lakes and springs; a new argument `planet[,<radius_metres>]` draws the six faces as a net of 4 by 3 squares from every tile of the planet (1536 at 8 km, about 23 million evaluations with the net's heights adding 3.8 million).
9. **The tech demo's start** stays the spring whose water falls furthest to the sea, ranked over 0312's grid round the home (`reach_metres`, at most half the radius) and its flood: the record's springs and the tiles' springs inside that grid, each with its cell's outlet and fall. Only the tech demo's spring start and the relief map compute it (`planet_spring_start`), so other sessions pay nothing; the tech demo pays the grid (98 thousand evaluations) and the tiles of the grid's square, about 50 analyses at 8 km (question 4).

### Rejected

- 0312's pipeline per tile window (flood from the window's border and the sea, features owned in the core): a basin's level and a cell's drainage depend on where a window's edge falls, so two tiles see one basin differently (two lakes at two levels over one place, or none), and the greedy spacing reaches past any margin.
- One flood over the planet at the start: the six faces hold 6.0 million cells at 8 km, 23 times 0312's finder, before the first chunk.
- An exact tiled flood (each tile's border spill graph solved over all tiles): every tile is needed before any is final.
- Old worlds gaining tiles past their disc: two rule sets would meet at a ring, and the worlds with 0312's waters date from today.
- No eviction: memory would grow with the ground explored.
- Tiles as cubes of a 3D lattice: exact neighbour lists, but a cube's cells need a window per face it touches and the slivers where the sphere clips a corner pay the whole margin.

### Data (`data_planet.odin`, `data/planets.sjson`)

- `LAKE_CELL_METRES` moves from `generation_planet_waters.odin` to `data_planet.odin` beside the waters' bounds (read below; the world cluster may read content).
- `Planet_Waters` gains, last, `tile_metres: int` (comment: "The tiles' edge on the cube faces' grids (0326); 0 keeps 0312's finder round the home only, as a world recorded before it does."). `waters_problem` after its bounds: `tile_metres` 0 to `MAXIMUM_WATER_TILE_METRES` (4096) and with tiles at least `MINIMUM_WATER_TILE_METRES` (256) (`waters.tile_metres %d is outside %d to %d`), a multiple of `grid_metres` (`waters.tile_metres %d is not a multiple of grid_metres %d`), and `spring_catchment_square_metres / grid_metres²` at most `MAXIMUM_TILE_CATCHMENT_CELLS` (64) (`waters.spring_catchment_square_metres %d is %d cells of grid_metres %d, more than %d with tiles`). The existing bounds stay.
- New constants with a one line comment each: `MINIMUM_WATER_TILE_METRES :: 256`, `MAXIMUM_WATER_TILE_METRES :: 4096`, `MAXIMUM_TILE_CATCHMENT_CELLS :: 64` ("a tile's margin stays at most 66 cells"), `MAXIMUM_WATER_TILES :: 1024` ("tiles a cache keeps found; the least recently asked past it are freed and found again alike"), `WATER_QUERY_BOX_METRES :: 512` ("twice the largest half diagonal of a box that asks for lakes: a coarsest node's with its margin at the widest spacing, 472 m").
- `water_lake_reach_metres :: proc(waters: Planet_Waters) -> int`: `(lake_maximum_metres / (2 * LAKE_CELL_METRES) + 1) * LAKE_CELL_METRES * 3 / 2`, the farthest a lake's mask holds a point from its pit (the window's half diagonal, 3/2 over √2); 291 shipped.
- `water_query_reach_metres :: proc(waters: Planet_Waters) -> int`: `max(spring_spacing_metres + lake, 2 * lake, lake + WATER_QUERY_BOX_METRES)` with `lake` the above; 803 shipped.
- `waters_planet_problem :: proc(planet: Planet) -> string`, from `planet_problem` after `waters_problem`: with tiles, `4 * water_query_reach_metres(planet.waters)` at most `radius_metres` (`waters reach %d m round a point, more than a quarter of the radius %d m`), the condition that makes `water_tiles_near`'s corner test exact. Shipped 803 against 1000 at 4 km.
- `Planet_Lake` gains `cell: [3]i32` ("its pit's face, column and row on the cube's grid (0326); zero from 0312's finder").
- New plain types beside the waters' (the procedures are `generation_planet_water_tiles.odin`'s; the file imports `base:runtime` and `core:sync`):
  - `Water_Spring_Candidate :: struct { spring: Planet_Water_Spring, cell: [3]i32 }`: a head, `drop` its height over the sea, `to_sea` false.
  - `Water_Tile_Key :: struct { face, column, row: i32 }`: cells `column * tile_cells` to `+ tile_cells - 1`, rows alike.
  - `Water_Tile_State :: enum u8 { Absent, Finding, Found }`.
  - `Water_Tile :: struct { analysis, final: Water_Tile_State, lakes: []Planet_Lake, candidates: []Water_Spring_Candidate, kept: []i32, springs: []Planet_Water_Spring, used: u64 }`: the analysis's lakes and heads, the final's kept lakes (indices into `lakes`) and springs, the clock of the last ask.
  - `Water_Tile_Cache :: struct { mutex: sync.Mutex, changed: sync.Cond, seed: u64, planet: Planet, radius, step, sea, face_cells, tile_cells, margin, escape_reach, lake_reach: i64, catchment_cells: i32, home: [3]i64, faces: [6][3][3]i64, maximum_tiles: int, tiles: map[Water_Tile_Key]^Water_Tile, clock: u64, allocator: runtime.Allocator }`: `planet` the session's, shallow, with `water_tiles` nil (the analyses' generation); `faces[f]` the face's centre, east and north; the geometry in position units and cells, set once.
- `Planet` gains `water_tiles: ^Water_Tile_Cache \`json:"-"\`` ("the waters' tiles (0326), set by the session when the record has tile_metres (make_water_tile_cache), never by the data").
- `data/planets.sjson`, `waters`: after `lake_margin_millimetres`, `tile_metres = 1024` with the comment "Springs and lakes over the whole planet, found in tiles of this edge as the ground is wanted (0 keeps them round the home only)."; `reach_metres`' comment becomes "Round the home on its own grid: with tiles the tech demo's start is ranked there, without them the waters are found only there."

### The record (`generation_planet_record.odin`)

- `make_recorded_planet`: `result.water_tiles = nil` beside `result.water_features = {}`.
- `destroy_recorded_planet`: `destroy_water_tile_cache(planet.water_tiles)` before the features.
- `recorded_waters_note`: a second case, recorded waters on with `tile_metres` 0 while the data's have tiles: `"world: the world file records the waters round the home only, it keeps them and has none past them"`.

### New file `src/generation_planet_water_tiles.odin` (world cluster)

Header comment: the waters over the whole planet (0326, doc/architecture.md, World generation): the cube's six gnomonic grids, tiles of them found as they are asked by whichever thread asks, each feature a function of its own cell's neighbourhood so the tiles are a cache and not a rule; integers and fixed point.

Constants: `WATER_FACE_COUNT :: 6`; `WATER_ESCAPE_EXTRA_CELLS :: 4` ("the escape flood reaches this many cells past the refine's half window"). Types: `Water_Cell_Order :: struct { height: i64, face: i32, row, column: i64 }`; `Water_Tile_Window :: struct { key: Water_Tile_Key, first_column, first_row, side: i64, heights: []i64 }` (row major).

Procedures, each with a one line comment:

- `water_cell_before :: proc(first, second: Water_Cell_Order) -> bool`: height, then face, row, column.
- `water_face_of :: proc(direction: [3]i64) -> i32`: the axis of the largest absolute component, ties to the lower axis, times 2, plus 1 when it is negative.
- `water_face_plane :: proc(cache: ^Water_Tile_Cache, face: i32) -> Waters_Plane`: `{faces[face][0], faces[face][1], faces[face][2], radius, step}`.
- `make_water_tile_cache :: proc(seed: u64, planet: Planet, maximum_tiles := MAXIMUM_WATER_TILES, allocator := context.allocator) -> ^Water_Tile_Cache`: nil when `tile_metres` is 0; else `radius` and `sea` as 0312's (one `make_planet_generation`), `step = metres_to_position_units(grid_metres)`, `face_cells = radius / step`, `tile_cells = tile_metres / grid_metres`, `escape_reach = lake_maximum_metres / 2 / grid_metres + WATER_ESCAPE_EXTRA_CELLS`, `catchment_cells` as 0312's, `margin = max(escape_reach, catchment_cells + 2)`, `lake_reach` from `water_lake_reach_metres`, `home = planet_home_direction(planet.home)`, face f's axis (component f / 2, negative for odd f) and `planet_tangents` of it, `planet` copied with `water_tiles` nil. Called by `resolve_session_planet`, `run_relief_map` and the tests.
- `destroy_water_tile_cache :: proc(cache: ^Water_Tile_Cache)`: nil does nothing; every tile (`free_water_tile`), the map, the cache. Only after every reader has stopped (`end_session` stops the workers first).
- `free_water_tile :: proc(cache: ^Water_Tile_Cache, tile: ^Water_Tile)`: each mask, the four slices, the tile, in the cache's allocator.
- `water_cell_owned :: proc(cache: ^Water_Tile_Cache, face: i32, column, row: i64) -> bool`: `water_face_of(waters_plane_direction(plane, column, row)) == face`.
- `water_tiles_near :: proc(cache: ^Water_Tile_Cache, direction: [3]i64, reach: i64, keys: ^map[Water_Tile_Key]struct{})`: adds every tile holding a cell whose point lies within `reach` (position units, a quarter of the radius at most) of the direction's point. The square of half side `reach * 9 / 8 + step` on the direction's tangent plane (`planet_tangents`) holds the disc's central projection (R tan θ is under 1.03 r for r up to R/4). Per face, its four corners `fixed_scale(direction, radius) ± fixed_scale(east, half) ± fixed_scale(north, half)` through `waters_plane_coordinates`: a face where a corner lies behind (`ok` false) is skipped, which is exact because the square spans under 35 degrees, so a corner behind puts the whole disc more than 54.7 degrees from the face's axis, outside its cells; else the corners' bounding box (the square's image is their convex hull) in cells, `floor_divide_i64(low + step / 2, step) - 1` to `floor_divide_i64(high + step / 2, step) + 1`, clamped to `-face_cells ..= face_cells`, divided by `tile_cells` with `floor_divide_i64`.
- `water_tiles_over_square :: proc(cache: ^Water_Tile_Cache, centre: [3]i64, half: i64, keys: ^map[Water_Tile_Key]struct{})`: `water_tiles_near` at every point `(i s, j s)` of the centre's tangent plane with `|i s|, |j s| <= half + s`, `s = metres_to_position_units(256)`, reach `s`. For the start and the relief map's square.
- `water_planet_tile_keys :: proc(cache: ^Water_Tile_Cache, allocator := context.allocator) -> [dynamic]Water_Tile_Key`: every tile of every face meeting `-face_cells ..= face_cells`.
- `water_tile_window :: proc(cache: ^Water_Tile_Cache, generation: Planet_Generation, key: Water_Tile_Key, allocator := context.temp_allocator) -> Water_Tile_Window`: `side = tile_cells + 2 * margin`, first cell `key.column * tile_cells - margin` (rows alike), each height `waters_plane_height(generation, water_face_plane(cache, key.face), column, row)`.
- `water_window_order :: proc(window: ^Water_Tile_Window, column, row: i64) -> Water_Cell_Order`: window coordinates in, the global row and column in the order.
- `water_escape_flood :: proc(window: ^Water_Tile_Window, column, row, reach, sea: i64) -> (level: i64, basin: [dynamic]i64, wide: bool)` (temp allocator): the cells within Chebyshev `reach` of the window cell, a `Waters_Entry` heap (index in the `2 reach + 1` square, `push_waters_entry`, `pop_waters_entry`), neighbours in `WATERS_NEIGHBOURS` order; each pop is appended and raises the sill when higher (remembering that pop's place); the first pop at Chebyshev `reach` or under `sea` sets `level` to the sill and stops; `basin` the window indices of the pops before the last raise under the level; `wide` when one of them lies at Chebyshev `reach - 1` or more.
- `find_water_tile_lakes :: proc(cache: ^Water_Tile_Cache, generation: Planet_Generation, window: ^Water_Tile_Window, allocator := context.allocator) -> []Planet_Lake`: the core cells row major, owned and before all 8 neighbours; per pit the escape flood; skipped when a basin cell is before the pit, `wide`, `level` less the pit's height under the minimum depth, `len(basin) * grid_metres²` under half the minimum area, or the pit's point within the clearing (chord to the home); `refine_planet_lake(generation, waters, pit direction, level, allocator)`, kept when ok with its `origin` outside the clearing, `cell` set; at most `MAXIMUM_PLANET_LAKES`.
- `find_water_tile_candidates :: proc(cache: ^Water_Tile_Cache, window: ^Water_Tile_Window, allocator := context.allocator) -> []Water_Spring_Candidate`: a parent for each window cell off its outer ring (its first neighbour in the order when before it, else -1); every window cell sorted by the order, latest first (`slice.sort_by` on a total order, so the sort never shows), adding its area to its parent's, capped at `catchment_cells`; draining marks as 0312's; the heads among the owned core cells, row major: area at the catchment, not draining, a parent, height at least `sea + spring_minimum_metres`, the point outside the clearing and at least the spacing (chord) from every record spring; each `{spring = {direction, height, height - sea, false}, cell}`.
- `find_water_tile_analysis :: proc(cache: ^Water_Tile_Cache, key: Water_Tile_Key, allocator := context.allocator) -> (lakes: []Planet_Lake, candidates: []Water_Spring_Candidate)`: `make_planet_generation(cache.seed, cache.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)`, the window, the two above.
- `water_lake_before :: proc(first, second: Planet_Lake) -> bool`: more water cells, then the pit's cell (face, row, column).
- `water_candidate_before :: proc(first, second: Water_Spring_Candidate) -> bool`: higher, then the cell (face, row, column).
- `find_water_tile_final :: proc(cache: ^Water_Tile_Cache, lakes: []Planet_Lake, candidates: []Water_Spring_Candidate, near_lakes: []Planet_Lake, near_candidates: []Water_Spring_Candidate, allocator := context.allocator) -> (kept: []i32, springs: []Planet_Water_Spring)`: a lake is kept unless a near lake with another `cell` and before it (`water_lake_before`) holds its `origin` or is held at its own `origin` by it (`planet_lake_holds`); a head is valid unless a near lake holds its point with the head under the lake's level; a valid head is a spring unless a valid near head with another cell and before it (`water_candidate_before`) lies under the spacing away (`squared_chord`); springs at most `MAXIMUM_DERIVED_SPRINGS`, in head order.
- `ensure_water_tiles :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key, finals: bool)`: answer 4's protocol for the analyses or the finals: under the lock each key's tile is made if missing and its Absent state claimed as Finding; outside it each claim is computed (a final: its own analysis taken; the keys `water_tiles_near` gives for each own lake's pit (`centre`) at `2 * lake_reach` and each own head at spacing plus `lake_reach`, with its own key; those analyses taken; `find_water_tile_final`) and published under the lock (Found, `used` the next clock, `evict_water_tiles`, `sync.cond_broadcast`); then under the lock `sync.cond_wait` while any key's state is Finding. Published states in the cache's allocator.
- `take_water_tile_analyses :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key, allocator := context.temp_allocator) -> (lakes: []Planet_Lake, candidates: []Water_Spring_Candidate)` and `take_water_tile_finals :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key, allocator := context.temp_allocator) -> (lakes: []Planet_Lake, springs: []Planet_Water_Spring)`: `ensure_water_tiles`, then under the lock, when every key's state is still Found, copies (masks cloned) and stamps `used`; a key evicted in between sends it round again.
- `evict_water_tiles :: proc(cache: ^Water_Tile_Cache)` (lock held): while more than `maximum_tiles` tiles hold a state Found, frees the least `used` with neither state Finding and deletes its key.
- `water_tile_lakes_near :: proc(cache: ^Water_Tile_Cache, direction: [3]i64, reach: i64, allocator := context.temp_allocator) -> []Planet_Lake`: the kept lakes of the finals `water_tiles_near` names, sorted by `water_lake_before`.
- `water_tile_springs_near :: proc(cache: ^Water_Tile_Cache, direction: [3]i64, reach: i64, allocator := context.temp_allocator) -> []Planet_Water_Spring`: their springs, sorted by direction (x, then y, then z).
- `planet_tile_water_start :: proc(seed: u64, planet: Planet) -> (start: [3]i64, found: bool)`: 0312's grid round the home and its flood (`make_waters_grid`, `flood_waters_grid`), the finals' springs of `water_tiles_over_square(home, grid.half * step)` (the grid's plane is the lattice's: both use `planet_tangents` of the home), each whose `waters_grid_cell` is inside rewritten with that cell's height, its outlet's fall and `to_sea` (0312's `find_planet_springs` rule), sorted by direction; `planet_water_start(&grid, planet.springs, those, sea)`.

### Changed procedures

- `generation_planet.odin`: `Planet_Generation` gains `water_tiles: ^Water_Tile_Cache` ("the waters' tiles (0326), borrowed from the planet; nil without them, whose lakes are the slice above"), set from `planet.water_tiles` by `make_planet_generation`. `mark_field_chunk_springs` ranges over `planet_derived_springs_near_chunk(generation, planet, chunk.coordinate)`. The header comment names the tiles.
- `generation_planet_waters.odin`:
  - `generation_lakes_meeting_box :: proc(generation: Planet_Generation, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> []Planet_Lake` (new): without tiles `planet_lakes_meeting_box(generation.lakes, ...)`; with them the box's centre's direction and `half = vector_length(maximum - minimum) / 2` (asserted at most half of `WATER_QUERY_BOX_METRES` in position units: "a box that asks for lakes is at most a coarsest node's"), `water_tile_lakes_near(generation.water_tiles, direction, lake_reach + 2 * half, allocator)` filtered by `planet_lake_meets_box`. Twice the half diagonal bounds the box's points projected onto the sphere.
  - `planet_derived_springs_near_chunk :: proc(generation: Planet_Generation, planet: Planet, coordinate: Field_Chunk_Coordinate) -> []Planet_Water_Spring` (new): without tiles `planet.water_features.springs`; with them `water_tile_springs_near` at the chunk's centre's direction, reach `32 * generation.spacing` (`planet_spring_may_lie_in_chunk`'s 29 spacings and more).
  - `fill_field_chunk_lakes` returns early only when `len(generation.lakes) == 0 && generation.water_tiles == nil` and lists through `generation_lakes_meeting_box`.
  - `make_planet_water_features` returns `{}` also when `planet.waters.tile_metres > 0`. The header comment: the home finder is 0312's and an old world's.
- `world_field_lod.odin` `generate_field_grid`: lists when `len(generation.lakes) > 0 || generation.water_tiles != nil`, through `generation_lakes_meeting_box`.
- `generation_planet_trees.odin` `planet_trees_in_box`: with tiles, the cubes read a copy of the generation whose `lakes` are `generation_lakes_meeting_box` over the cubes' box (`first * spacing` to `(last + 1) * spacing`) and whose `water_tiles` is nil, so `planet_tree_ground` reads one short list and the shared generation is never written.
- `session.odin` `resolve_session_planet`: with `tile_metres > 0`, `session.planet.water_tiles = make_water_tile_cache(plan.seed, session.planet)`, else 0312's features; the comment names both.
- `simulation_field.odin`: `planet_spring_start :: proc(seed: u64, planet: Planet) -> (direction: [3]i64, found: bool)`: the features' start when `has_start`, else with tiles `planet_tile_water_start`, else the record's first spring; `field_spring_spawn` passes its seed.
- `loop_relief_map.odin`:
  - `Relief_Map_Request` gains `whole_planet: bool` (last); `parse_relief_map_argument` takes `planet` or `planet,<radius_metres>` (`parse_integer_word`, 0 or more) as the whole planet; `RELIEF_MAP_ARGUMENT_FORM` gains ` or planet[,<radius_metres>]`; `main.odin`'s usage string follows.
  - `run_relief_map` sets `planet.water_tiles = make_water_tile_cache(seed, planet)` (freed by a defer). A square takes its lakes and derived springs from `relief_map_waters_of_square` (new: the features without tiles, else the finals of `water_tiles_over_square` at the square's centre with half `size / 2 * 3 / 2`, the map's frame being turned against `planet_tangents`), draws and prints them as now with the per lake and per derived spring lines capped at `RELIEF_MAP_MAXIMUM_LINES :: 128` each and then `relief map: and <n> more lakes` (springs alike); the start through `planet_spring_start(seed, planet)`.
  - `relief_map_mark_lakes` takes `lakes: []Planet_Lake` and paints lake by lake in order over each lake's bound's pixel rectangle (placed as `relief_map_mark` places a direction, radius in pixels plus one), a pixel taken by the first lake holding its point (a `decided` slice) and coloured when its height lies under that lake's level; the pixel by pixel scan over every lake would cost pixels times lakes.
  - `relief_map_planet_net :: proc(generation: Planet_Generation, planet: Planet, lakes: []Planet_Lake, springs: []Planet_Water_Spring, face_pixels: int, allocator := context.allocator) -> [][4]u8`, `4 face_pixels` wide and `3 face_pixels` high: each face drawn as the square map of size twice the radius round its centre (+y at latitude 90, longitude 0; +x at 0, 0; +z at 0, 90; -x at 0, 180; -z at 0, -90; -y at -90, 0), which is that face's grid north up, placed at (column, row) (0, 0), (0, 1), (1, 1), (2, 1), (3, 1), (0, 2), so the edges round +x and along the row meet; the rest black. Each face: heights, colours, lakes, the record springs' streams, the derived and record springs' markers, the home; no derived streams. With `whole_planet`, `run_relief_map` takes every tile's final (`water_planet_tile_keys`, `take_water_tile_finals`), draws at `RELIEF_MAP_PIXELS` a face (3200 by 2400) and prints the header line and `relief map: planet: <t> tiles, <n> derived springs, <m> lakes`. `write_relief_map_png` takes a width and a height.

### Tests

New `src/generation_planet_water_tiles_test.odin` (the shipped planet at a preset with `new_world_home`; a test at 1 s or more marked slow):

- `test_water_faces_own_every_cell_once`: `water_face_of` of each axis gives its face, of `{U, U, 0}` 0 and of `{0, -U, -U}` 3 (U is `UNIT_VECTOR_ONE`); at 8 km `face_cells` is 500, cell (500, 0) of face 0 is owned and (501, 0) is not, and for each face the cells (±501, 0) and (0, ±501) belong to the neighbouring faces' directions.
- `test_water_tiles_near_holds_every_cell_in_reach` (4 km, the largest reach against the radius): for 16 directions (the home, three axes, three cube corners' and six edge midpoints' directions, three from a seeded hash) at `water_query_reach_metres`, every owned cell of every face in a box of `3 * reach / step + 2` cells round the direction's projection whose point lies within the reach has its tile among the keys.
- `test_water_tiles_are_found_alike_in_any_order` (8 km; the item's Verify): the finals of the 3 by 3 round the home's tile from a cache asked row by row, one asked in reverse, one asked first through `water_tile_lakes_near` at nine points, one asked by four threads each in its own order (`core:thread`), one with `maximum_tiles` 4 asked twice: equal lake by lake (every field and the mask) and spring by spring.
- `test_water_tiles_round_the_shipped_home` (8 km): the finals within 1500 m of the home: every lake within 0312's bounds (depth, area, over the sea, outside the clearing, `lake_leaks == 0`, the floor a sample over the sea), no two holding each other's pit; every spring at least 25 m over the sea, outside the clearing, 400 m from every other and from the record's, under no lake's level; 1.2 to 2.2 lakes and 0.3 to 0.8 springs per km² (probe 1.64 and 0.53); a lake whose mask holds cells of two tiles exists (probe: 8) and the chunks on both sides of that edge, generated with `planet.water_tiles` set, hold its water as `fill_field_chunk_lakes` fills it; the chunk of a spring's sample has its source bit; `planet_trees_in_box` over the largest lake's bound stands no tree under its level plus the margin; `generate_field_grid` of the level 1 node over the largest lake shows it. Counts logged.
- `test_water_tiles_keep_to_their_bound`: a cache with `maximum_tiles` 4 asked for 16 tiles holds at most 4 with a state Found.
- `test_the_waters_tile_problems`: `tile_metres` 255, 4097 and 1000 at a 16 m grid refused by name; 0 passes; with tiles a catchment of 65 cells refused; the shipped waters at a radius of 3000 refused (803 m over a quarter).
- `test_an_old_world_keeps_the_waters_round_its_home`: a `world.sjson` text whose record has 0312's waters without `tile_metres`, through `resolve_session_planet` against the shipped planets: one log line holding "round the home only", `waters.tile_metres` 0, `water_tiles` nil, the features equal (`waters_features_equal`) to `make_planet_water_features` of the record's planet.
- `test_a_new_world_records_its_tiles`: `planet_generation_record(shipped)` holds `tile_metres` 1024, unchanged through `encode_world_file` and `parse_world_file`.

Changed:

- `generation_planet_waters_test.odin`: `waters_test_planet` sets `planet.waters.tile_metres = 0` ("0312's finder, as a world recorded before 0326 runs it"), so its tests keep pinning the home finder. `test_the_tech_demo_start_follows_the_longest_fall` runs with tiles: at 4 and 16 km `planet_spring_start(DEFAULT_WORLD_SEED, planet)` is a record spring or a tile spring of the grid's square, pinned to the one the implementation finds (named in the report); the tech demo session at 4 km stands on its radial as now. `planet_spring_start`'s other call passes the seed.
- `loop_relief_map_test.odin`: the argument test takes `planet` and `planet,16000` and refuses `planet,16000,1`, `planets` and `planet,-1`; `test_the_relief_map_draws_the_lakes` takes the largest lake of the finals round the home and paints through `relief_map_mark_lakes` with that list; new `test_the_planet_relief_map_lays_out_the_faces`: the planet with its waters off at 8 km, `face_pixels` 16: 64 by 48, cells (1, 0) to (3, 0) black, the +x square's centre pixel equal to the square map's centre at latitude 0, longitude 0, size 16000.
- `test_report_the_waters_cost` gains, behind its define: per preset an analysis and a final of the home's tile (best of 5, fresh caches), the home's 3 by 3 finals from a cold cache on one thread and on `default_worker_count()` threads (until all are found), the tech demo's spring start, each with its evaluations.
- Shipped data tests pinning the waters' keys take `tile_metres` 1024.

### Docs

- `doc/architecture.md`, World generation, the waters: 0312's finder becomes an old world's; the tiles (the cube's grids, the tile and its margin, the local rules and why, the final, the cache and its protocol, eviction and copies, the readers and through what, the start's grid, the cost per tile and per fresh view). Threads and chunk streaming: a field job may find tiles and wait for one another thread finds. Save format: `waters.tile_metres`, absent read as 0 and 0312's finder, one log line.
- `doc/content.md`, Planets: `tile_metres` and its bounds, the catchment's bound with tiles, the query reach's quarter of the radius, `reach_metres`' two meanings; the shipped waters' counts with tiles per preset from the test log.
- `doc/build.md`, The workbench: the relief map's `planet` argument, the net's layout, the tiles a square finds, the capped lines.
- `doc/code_map.md`, world: the new file's line after `generation_planet_waters.odin`; `data_planet.odin`'s line names the water tile types; the reach-into records as `tools/code_graph.py --check` reports them.

### Hand-back lines that apply

- Memory a reader may hold: an eviction frees a tile only under the lock and every reader holds copies (`take_water_tile_*`); the cache is destroyed after the workers stop.
- An old save: `tile_metres` absent reads 0, 0312's finder, one log line (`test_an_old_world_keeps_the_waters_round_its_home`).
- A shared budget: the workers' chunk, mesh and tree jobs now find tiles and may wait for one another worker finds, so a job grows the first time its ground is asked; `MAXIMUM_FIELD_PENDING_JOBS` stays. The simulation thread finds a tile on an unload or a tree query whose tiles were evicted or never asked: correct, a hitch the night run counts.
- Lists capped: tiles at `MAXIMUM_WATER_TILES`, lakes and springs per tile at 128, the relief map's lines at 128 each.
- A number parsed from text: the relief map's `planet,<radius>` through `parse_integer_word`.
- Tests touch no state directory; the relief map tests write only a temporary directory.

### Night window (main agent, `./build.sh nightly`)

- `test_report_the_waters_cost` with the new cases (an analysis and a final at the home, the home's 3 by 3 on one thread and on the workers, the tech demo's spring start) against 0312's finder (0.31 s); the figures into the log.
- The relief map of the whole 8 km planet (`--relief-map=planet,8000`, about 27 million evaluations on one thread): its run time, and the PNG for the user.

### Questions for the main agent

1. Springs come out at about two thirds of 0312's where both count (11 against 17 at 8 km), the price of a spacing rule decided locally (local maxima) with the 400 m pairwise guarantee kept; lakes come out more (33 against 23, 22 shared), sub-basins of large closed basins that 0312 merged and refused as too big. Accept both?
2. The session waits for no tile on the main thread (answer 4), against the item's line. Accept?
3. Old worlds keep 0312's disc and nothing past it. Accept, or give them tiles past the disc (a seam rule at the ring)?
4. The tech demo's spring start finds the tiles of 0312's grid square on the main thread, about 50 analyses at 8 km (some 0.75 million evaluations, three times 0312's finder) plus the grid. Accept, or rank the start over the home's 3 by 3 only (smaller falls)?
5. On the cube's gnomonic faces a cell shrinks to a third radially at a corner, so the catchment counted in cells drains less ground there (heads higher up their valleys) and the escape reach covers less; the spacing and the lakes' own 2 m planes are unaffected. Accept, or weight the catchment by the cell's area (the margin then grows to about 80 cells on corner tiles)?

### Decisions (main agent, 2026-11-07)

1. Springs at about two thirds of 0312's density and the extra lakes of sub-basins are accepted: the 400 m spacing holds and every result is local. The log names the change for new worlds.
2. The main thread waits for no tile; a chunk's generation waits for its tile on the worker, as designed.
3. Old worlds keep 0312's disc and nothing past it, with the one log line.
4. The tech demo ranks its spring start over the home's 3 by 3 tiles only, so its start costs no more than 0312's finder; the tests that read the tech demo's spring follow the new start.
5. The catchment is counted in cells, as designed: the cube's corners lie far from every shipped home.
6. The implementation follows 0314 in the same stream, from 0314's snapshot, since both change `generation_planet.odin` and `world_field_lod.odin`; 0334's change to `generation_planet_waters_test.odin` meets it at the rebase.
