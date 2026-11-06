# 0306: Taller, varied relief: plains, hills, ranges and valleys

Status: implementing (2026-11-06)

Milestone: the world generation series 0306 to 0313 (the plan in `doc/log/2026-11-06.md`, The world generation series). The user (2026-11-06): "I need better and more varied elevation for testing the water tech demos, and just generally better visuals because right now it is very bland". The research is `work/world_generation_research.md`.

## Goal

The relief reads as landscape from the ground and from the air: plains and rolling lowlands round the home, hills, ridged ranges and deep valleys within walking distance, a few peaks on the horizon, basins and coasts below them. Water from the tech demo's spring runs a long way downhill.

## Controls

None.

## Change

- Relief terms after Minecraft's noise router and domain warping: a low frequency region noise read through a data spline (sea floor, coast, lowland, plain, hill, highland heights), a folded ridge noise for the ranges and the valleys between them, hills and detail octaves, a warp of the large terms' input that hides the value noise lattice, and the skew of real terrain (many lowlands, few peaks). Integer and fixed point, a pure function as today.
- The drama fades in with the distance from the home (Valheim's meadows at the spawn): the crater and the first base on gentle ground, hills within a few hundred metres, ranges in sight.
- The relief bound goes from the global 34 m to a bound per planet derived from its record, about 160 m of total range on the home planet (peaks about 100 m over the sea). Every reader of `MAXIMUM_RELIEF_METRES` takes the planet's bound: the generation's shortcuts, the level of detail shell, the sky march, the globe, the edits, the arrival's start, the bedrock depth rule. The generation's cost per node and the nodes generated per view are measured before and after, with a reject per node from the relief's range over its footprint if the thicker shell costs.
- Old worlds generate as before: the new terms are off in a world record without them (as `relief_shape` in 0189), one log line.
- The default seed's spring moves (data) to a slope above a valley or a basin, so the tech demo's spring start runs a stream at least 100 m downhill. The home keeps its rules (the dry crater floor, the dry home search).
- A relief map mode for tuning without a window (a workbench mode, as `--model-check`): a shaded height PNG of a square round a latitude and longitude with the sea, contour lines, the home and the springs. This item's verify uses it, and so do the later items of the series.
- Docs: `doc/content.md` (Planets), `doc/architecture.md` (World generation), `doc/build.md` (the map mode); the log.

## Verify

- The checks and the suite, with tests of the new terms' bounds, their determinism, and the old record's unchanged generation.
- Relief maps of 4 km round the home at the three radius presets, before and after.
- Captures of the tech demo's spring start, the home and a far point from the ground and from 40 m and 120 m up, beside the before set in `tmp/shot_terrain_before/`; sent to the user.

## Specification (design, 2026-11-06)

The terms were tuned in an Odin prototype that copies the generation's integer maths: `tmp/0306/proto/main.odin` (`~/opt/odin/odin build tmp/0306/proto -out:tmp/0306/proto4.bin -o:speed`, modes `map`, `legacy-map`, `stats`, `springs`, `section`, `view`, `nodes`, `timing`, `golden`). Images: `tmp/0306/relief_maps_before_after.png` (4 km round the home at 4, 8 and 16 km, before and after), `after_8km.png`, `spring_presets.png` (the spring and its stream at the three presets, 2 km square), `views_from_home.png` (from 2, 40 and 120 m over the home, looking south), `sections_spur.png`, `f0_w2.png` and `v2_8km.png` (the ridge forms compared). The golden values below are the prototype's, so the implementation that matches them generates the terrain the spring was chosen on.

### The landforms

A new optional planet object `landforms` (`Planet_Landforms`), off at the zero value. When on, `uncratered_relief` adds `landform_relief(generation, point)` (the on-sphere point) to today's octaves, basins, terraces and ledges, which stay as they are and become the small detail. With it off nothing new is read and every byte generates as before.

`landform_relief`, in this order (all `i64`, `/` truncating as Odin does, `metres` is `metres_to_position_units`):

1. `home := metres(home_metres)`, `wildness := home_wildness(generation, point)`, and `if wildness == 0 { return home }`. Within `calm_metres` of the home the relief is the home plain plus the detail, for every seed.
2. The warp: `warped := point`, then for axis 0, 1, 2: `warped[axis] += metres(warp_metres) * gradient_noise(hash_combine(landform_seed, u64(axis)), point, metres(warp_wavelength_metres)) / NOISE_ONE`.
3. `region := gradient_noise(hash_combine(landform_seed, 3), warped, metres(region_wavelength_metres))`.
4. `base := landform_curve(region_heights_metres, region, POSITION_UNITS_PER_METRE)`, then `relief := home + (base - home) * wildness / NOISE_ONE`.
5. `range_share := landform_curve(region_ranges_percent, region, NOISE_ONE) / 100`. When `range_metres > 0 && range_share > 0`: `ridge := landform_ridge(gradient_noise(hash_combine(landform_seed, 4), warped, metres(range_wavelength_metres)))`. When `ridge > 0 && spur_percent > 0`: `spur := landform_ridge(gradient_noise(hash_combine(landform_seed, 6), warped, metres(spur_wavelength_metres)))` and `ridge = ridge * (i64(100 - spur_percent) * NOISE_ONE + i64(spur_percent) * spur) / (100 * NOISE_ONE)`. Then `relief += metres(range_metres) * ridge / NOISE_ONE * range_share / NOISE_ONE * wildness / NOISE_ONE`.
6. `hill_share := landform_curve(region_hills_percent, region, NOISE_ONE) / 100`. When `hill_metres > 0 && hill_share > 0`: `relief += metres(hill_metres) * gradient_noise(hash_combine(landform_seed, 5), warped, metres(hill_wavelength_metres)) / NOISE_ONE * hill_share / NOISE_ONE * wildness / NOISE_ONE`.

The skips in 1, 5 and 6 change no value (each skipped term is exactly 0) and keep the cost of the home area, the sea floor and the lowlands down.

New file `src/generation_planet_landforms.odin`:

- `GRADIENT_NOISE_DIRECTIONS :: [16][3]i64{{1,1,0},{-1,1,0},{1,-1,0},{-1,-1,0},{1,0,1},{-1,0,1},{1,0,-1},{-1,0,-1},{0,1,1},{0,-1,1},{0,1,-1},{0,-1,-1},{1,1,0},{-1,1,0},{0,-1,1},{0,-1,-1}}` (Perlin's twelve edges, four repeated).
- `quintic_fade :: proc(fraction: i64) -> i64`: `cube := t * t / NOISE_ONE * t / NOISE_ONE; return cube * (t * (6 * t - 15 * NOISE_ONE) / NOISE_ONE + 10 * NOISE_ONE) / NOISE_ONE`.
- `gradient_noise :: proc(seed: u64, point: [3]i64, wavelength: i64) -> i64`: per axis `cell = floor_divide_i64(point, wavelength)`, `fraction = (point - cell * wavelength) * NOISE_ONE / wavelength`, `fade = quintic_fade(fraction)`. Per corner `index` 0..7 (offset `{index & 1, index >> 1 & 1, index >> 2}`) the direction `GRADIENT_NOISE_DIRECTIONS[hash_lattice(seed, cell + offset) >> 60]` dotted with `fraction - offset * NOISE_ONE`. The eight dots are interpolated along x, y, z with `noise_interpolate` and the fades, in `value_noise`'s order, and the result clamped to `-NOISE_ONE..NOISE_ONE`. Gradient noise, not value noise, because it has no axis aligned plateaus to show at 80 m amplitudes. The warp breaks up what lattice remains.
- `LANDFORM_KNOT_SPAN :: NOISE_ONE * 6 / 10`, `LANDFORM_KNOT_STEP :: 2 * LANDFORM_KNOT_SPAN / (LANDFORM_KNOT_COUNT - 1)`: the knots lie at noise -0.6, -0.45 ... 0.6 (the noise's standard deviation is 0.28).
- `landform_curve :: proc(knots: [LANDFORM_KNOT_COUNT]int, noise: i64, scale: i64) -> i64`: Catmull-Rom through the knots times scale, flat beyond the ends: `position := clamp(noise + SPAN, 0, 2 * SPAN)`, `index := min(position / STEP, COUNT - 2)`, `t := (position - index * STEP) * NOISE_ONE / STEP`, `p0..p3` the knots at `max(index - 1, 0)`, `index`, `index + 1`, `min(index + 2, COUNT - 1)` times scale, `t2 := t * t / NOISE_ONE`, `t3 := t2 * t / NOISE_ONE`, `value := 2 * p1 + (p2 - p0) * t / NOISE_ONE + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 / NOISE_ONE + (3 * p1 - p0 - 3 * p2 + p3) * t3 / NOISE_ONE`, return `clamp(value / 2, min(p1, p2), max(p1, p2))`. The clamp keeps the curve inside its knots, so the bound below holds.
- `landform_ridge :: proc(noise: i64) -> i64`: `ridge := max(NOISE_ONE - 2 * abs(noise), 0); return ridge * ridge / NOISE_ONE`. A crest along each zero line of the noise, gone where |noise| reaches one half.
- `home_wildness :: proc(generation: Planet_Generation, point: [3]i64) -> i64`: `offset := point - generation.landform_home` and its squared length. `NOISE_ONE` when that is at least `metres(wild_metres)` squared (no root), else `distance := i64(integer_square_root(u64(squared)))`, `fraction := clamp((distance - calm) * NOISE_ONE / (wild - calm), 0, NOISE_ONE)`, smoothstep `fraction * fraction / NOISE_ONE * (3 * NOISE_ONE - 2 * fraction) / NOISE_ONE`.
- `landform_relief :: proc(generation: Planet_Generation, point: [3]i64) -> i64`: returns 0 at once when `generation.landforms.region_wavelength_metres == 0` (off), else the steps above. Called from `uncratered_relief` (`return relief + ledge_relief(generation, point) + landform_relief(generation, point)`).

The ridge form: Minecraft's fold `1 - |3|w| - 2|` puts its peaks on the |w| = 2/3 contours, which close into rings round every extremum (craters, `v2_8km.png`). The zero lines of the noise run long and branch, so the crests above follow them (`f0_w2.png`) and the spurs notch them into peaks and saddles.

`generation_seed.Generation_Purpose` gains `Planet_Landforms` appended after `Planet_Trees` (comment: the landforms of work item 0306), so every other seed stays.

`Planet_Generation` gains, apart from 0307's fields: `landforms: Planet_Landforms`, `landform_seed: u64` (`seeds[.Planet_Landforms]`), `landform_home: [3]i64` (`fixed_scale(planet_home_direction(planet.home), radius)`), `relief_lowest, relief_highest: i64` (`planet_relief_bounds(planet)`), all set in `make_planet_generation`'s literal.

### The relief bound per planet

In `data_planet.odin`:

- `MAXIMUM_RELIEF_METRES` is renamed `OCTAVE_RELIEF_LIMIT_METRES` (34) and `MAXIMUM_RELIEF_MILLIMETRES` `OCTAVE_RELIEF_LIMIT_MILLIMETRES`: the most the octaves, the ledges and the basins add up to (`relief_problem` and `relief_shape_problem` unchanged otherwise), and the bound both ways of a planet without landforms. The rename makes the compiler find every reader.
- `MAXIMUM_RELIEF_DEPTH_METRES :: 128` and `MAXIMUM_RELIEF_HEIGHT_METRES :: 256`: the most any planet's relief reaches below and above its radius.
- `Relief_Bounds :: struct { lowest, highest: i64 }` in position units from the radius, and `relief_bounds :: proc(octaves: [RELIEF_OCTAVE_COUNT]Relief_Octave, shape: Relief_Shape, landforms: Planet_Landforms) -> Relief_Bounds`, with `planet_relief_bounds :: proc(planet: Planet) -> Relief_Bounds` wrapping it. Without landforms: `{-metres(34), metres(34)}` exactly, whatever the octaves add up to, so an old world's shortcuts and crater clamps stay bit for bit. With them: `above := sum of metres(octave amplitude) + millimetres_to_position_units(ledge_amplitude_millimetres)`, `below := above + metres(basin_depth_metres)`, `hills := metres(hill_metres) * most_hills_percent / 100`, `highest := metres(max(home_metres, every height knot)) + metres(range_metres) * most_ranges_percent / 100 + hills + above`, `lowest := metres(min(home_metres, every height knot)) - hills - below`. Each term is truncated toward zero no further than its bound, so no relief leaves it. The shipped record: -310067 and 514867 (-75.7 m and +125.7 m).
- `relief_depth_metres :: proc(bounds: Relief_Bounds) -> int`: `ceiling_divide_i64(-bounds.lowest, POSITION_UNITS_PER_METRE)` (76 shipped, 34 without landforms), for the readers in metres.

The readers:

| Where | Today | Becomes |
|---|---|---|
| `generation_planet.odin` `planet_sample_shortcut` | `relief_reach` both ways | air from `radius + relief_highest + spacing`, deep stone below `radius + relief_lowest - spacing - DEEP_STONE` |
| `make_crater_term` | floor `max(.., -34 m)` | `max(.., generation.relief_lowest)`, and `Crater_Term` gains `ceiling: i64 = generation.relief_highest` |
| `crater_relief` | `min(result, 34 m)` | `min(result, term.ceiling)` |
| `planet_spring_sample` | `highest` | `radius + relief_highest + spacing` |
| header comment of the file | the global bound | the planet's bound and the landforms term |
| `world_field_light.odin` `field_relief_top` | 34 m | `radius + relief_highest + spacing` |
| `world_field_lod.odin` `make_field_view` | one margin | `bounds := planet_relief_bounds(planet)`, `shell_inner = radius + bounds.lowest - 2 spacings`, `shell_outer = radius + bounds.highest + 2 spacings`, the `Field_View` comment |
| `render_field.odin` `field_globe_radius_metres` | `radius - 34 - margin` | `radius - relief_depth_metres(planet_relief_bounds(planet)) - FIELD_GLOBE_MARGIN_METRES` |
| `world_field_edit.odin` `impact_crater_axis` | `relief_reach` | `relief_highest + spacing` |
| `impact_crater_reaches_box` | `relief_reach` both ways | `radius + relief_highest + spacing` above, `radius + relief_lowest - spacing - DEEP_STONE` below |
| `data_load.odin` arrival check | `top + 34` | `top + MAXIMUM_RELIEF_DEPTH_METRES` (810 >= 650 + 128), the message and `data/game.sjson`'s comment naming 128 m |
| `data_planet.odin` bedrock check | `MINIMUM_BEDROCK_DEPTH_METRES` (74) | removed: `planet_problem` refuses `bedrock_depth_metres` below `relief_depth_metres(planet_relief_bounds(planet)) + DEEP_STONE_DEPTH_METRES` (74 without landforms, 116 shipped), checked after the relief and landform checks |

The arrival check stays planet free because `game.sjson` is validated without the planets: the global depth cap stands for every planet's bound. 0307 reads `Planet_Generation.relief_highest` (or `planet_relief_bounds`) for its snow line.

### Data and validation

`Planet_Landforms` (`data_planet.odin`), `LANDFORM_KNOT_COUNT :: 9`, fixed arrays so the struct compares with `== {}` and records without allocation:

| Key | Bounds | Shipped |
|---|---|---|
| `warp_wavelength_metres` | 1 to `MAXIMUM_RELIEF_WAVELENGTH_METRES` | 1200 |
| `warp_metres` | 0 to `MAXIMUM_LANDFORM_WARP_METRES` (10000) | 300 |
| `region_wavelength_metres` | 1 to the wavelength maximum | 2400 |
| `region_heights_metres` (9) | each -128 to 256 | -60, -46, -26, -9, -5, -1, 5, 16, 30 |
| `region_ranges_percent` (9) | each 0 to 100 | 0, 0, 0, 0, 15, 45, 80, 100, 100 |
| `region_hills_percent` (9) | each 0 to 100 | 0, 10, 30, 60, 80, 100, 100, 100, 100 |
| `range_wavelength_metres` | 1 to the wavelength maximum | 800 |
| `range_metres` | 0 to 256 | 80 |
| `spur_wavelength_metres` | 1 to the wavelength maximum | 300 |
| `spur_percent` | 0 to 100 | 35 |
| `hill_wavelength_metres` | 1 to the wavelength maximum | 180 |
| `hill_metres` | 0 to 256 | 8 |
| `home_metres` | -128 to 256 | 2 |
| `calm_metres` | 0 to `wild_metres - 1` | 120 |
| `wild_metres` | 1 to `MAXIMUM_LANDFORM_WILD_METRES` (8192) | 600 |

- `landforms_problem :: proc(landforms: Planet_Landforms) -> string`: the zero value passes (off, an old record), otherwise every key in its bounds, the message naming the key (and `[index]` for a knot). Called from `planet_problem` after `relief_problem`.
- In `planet_problem`, with landforms on: `-bounds.lowest <= metres(MAXIMUM_RELIEF_DEPTH_METRES)` and `bounds.highest <= metres(MAXIMUM_RELIEF_HEIGHT_METRES)`, `calm_metres >= crater_reach_metres(crater)` (the crater on the plain), and the home dry for every seed: `metres(home_metres) - below - metres(crater.depth_metres) >= metres(sea_level_metres) + millimetres_to_position_units(HOME_DRY_MARGIN_MILLIMETRES)` (shipped: `2 - 7.7 - 3 >= -11 + 1`). So `find_dry_planet_home` keeps the record's home on a landforms planet, and the landforms' centre is always the home the world records.
- `OPTIONAL_PLANET_KEY` becomes `OPTIONAL_PLANET_KEYS :: [2]string{"relief_shape", "landforms"}` (0307 appends `climate`). `missing_struct_key`'s `optional` becomes `[]string` (default `nil`), and `missing_planet_key_problem` checks a present `landforms` object for every key (`planets[%d].landforms is missing %s`).
- `data/planets.sjson`: the `landforms` block, a comment line per key. `relief_octaves` `{96, 4}, {32, 2}, {12, 1}` (the detail now). `relief_shape` keeps the ledges (32, 700, 128) and turns the terraces and basins off (`terrace_rise_millimetres = 0`, `basin_depth_metres = 0`, the other two keys as they are). `springs = [{latitude_degrees = 81, longitude_degrees = 139}]`. The comments of `sea_level_metres`, `springs`, `home` and the octaves rewritten for the new ground (the figures below). `sea_level_metres` stays -11 and `bedrock_depth_metres` 256.

What the shipped record makes (prototype, 200,000 points over the sphere at 8 km, heights over the sea): sea 27 percent, 0 to 5 m 10 percent, 5 to 15 m 26 percent, 15 to 30 m 17 percent, 30 to 50 m 11 percent, 50 to 80 m 6 percent, above 80 m 1.3 percent. The highest 121 m, the sea floor to 55 m under the sea, slopes median 6 degrees, 99th percentile 38, steepest about 64 at a few crests. Total range about 176 m against the target's 160: the peaks reach 100 m over the sea at the 99.9th percentile and the deep sea floor gives the rest. The home's crater floor lies 9.5, 8.7 and 9.1 m over the sea at 4, 8 and 16 km (doc/content.md's crater line).

### The spring

`(81, 139)`: at 8 km 310 m from the home on the foot of a range, 39 m over the sea, its trace runs 200 m down into the home's plain and drops 30 m. At 16 km it lies 620 m out on a ridge's flank, 218 m and 53 m, at 4 km 155 m out on the calm plain, 82 m and 7 m. Of the whole degree points 200 to 1200 m out (at 8 km), none runs further at its weakest preset: the ranges fade in from 120 to 600 m round the home, and at 4 km the same degrees lie half as far out. `(79, 151)` is the stronger 8 km choice (688 m out, 86 m over the sea, 366 m and 65 m) but only 80 m at 4 km.

### Old worlds

- `Planet_Generation_Record` gains `landforms: Planet_Landforms` ("zero in a file written before it (0306): the relief of before"), which `planet_generation_record` copies. `make_recorded_planet` sets `result.landforms = record.landforms` explicitly, since `result` starts as the data's planet and the data's landforms must not reach an old world.
- `resolve_world_planet`: when the file holds a record (`planet_generation_is_recorded`) whose `landforms` is zero and the data planet's is not: `platform.log_printf("world: the world file records no landforms, it keeps the relief it was made with")`. No remap: zero is off.
- `GENERATOR_VERSION` stays (it is the block world's).

### The relief map workbench mode

- Flags in `Command_Line` (`main.odin`): `relief_map: string` (`usage:"<latitude>,<longitude>,<size_metres>[,<radius_metres>]: write a shaded relief map of the square round the point on the default planet (seed from --seed) to --relief-map-file, then exit; no window"`) and `relief_map_file: string` (`usage:"<path>: the PNG --relief-map writes"`). `run_relief_map` runs right after the model preview's exit in `main`, before any world starts.
- `relief_map_conflict :: proc(command_line: Command_Line) -> string`, called from `command_line_conflict` after `workbench_conflict`: the map needs its file and the file its map, and the map refuses `--model-check`, `--model-preview`, the planet preview's flags, `--benchmark`, `--server`, `--join`, `--tech-demo`, `--load`, `--name`, `--debug-terrain`, `--chapter` and `--give`. `--seed` combines. `tech_demo_conflict` and `workbench_conflict` name `--relief-map` among theirs.
- New file `src/loop_relief_map.odin`:
  - `RELIEF_MAP_PIXELS :: 800`, `RELIEF_MAP_MINIMUM_METRES :: 100`, `RELIEF_MAP_MAXIMUM_METRES :: 20_000`, `RELIEF_MAP_STREAM_STEPS :: 4000`, `RELIEF_MAP_STREAM_STEP_METRES :: 2`.
  - `Relief_Map_Request :: struct { latitude_degrees, longitude_degrees: f64, size_metres, radius_metres: int }`.
  - `parse_relief_map_argument :: proc(argument: string) -> (request: Relief_Map_Request, problem: string)`: three or four comma separated words. Latitude and longitude by `strconv.parse_f64`, finite, -90 to 90 and -180 to 180, the size an integer from the minimum to the maximum, the radius an integer, 0 or absent for the planet's default.
  - `relief_map_planet :: proc(planets: []Planet, seed: u64, radius_metres: int) -> (planet: Planet, problem: string)`: the default planet, the radius one of its presets (`problem` naming them otherwise), `planet.home = new_world_home(seed, planet)`.
  - `relief_map_point :: proc(request: Relief_Map_Request, radius_metres: int, east_metres, north_metres: f64) -> [3]i64`: the gnomonic projection round the centre (centre `{cos(lat) cos(lon), sin(lat), cos(lat) sin(lon)}` as `planet_direction_at` lays it out, east `{-sin(lon), 0, cos(lon)}`, north `{-sin(lat) cos(lon), cos(lat), -sin(lat) sin(lon)}`), scaled to the radius in position units and rounded. Floats only place the pixels, every height is the generation's integer relief.
  - `relief_map_heights :: proc(generation: Planet_Generation, request: Relief_Map_Request, pixels: int) -> []i64`: `surface_relief` at each pixel's centre, row major, north up.
  - `relief_map_colours :: proc(heights: []i64, sea_level: i64, metres_per_pixel: f64, pixels: int) -> [][4]u8`: by the height over the sea, colour stops -60 (20, 40, 90), -20 (40, 80, 150), 0 under (90, 140, 200), 0 (196, 190, 140), 3 (120, 160, 90), 15 (90, 140, 70), 35 (150, 150, 90), 60 (140, 110, 80), 90 (170, 160, 150), 120 (240, 240, 240), linear between. A hill shade from central differences, light from the north west 45 degrees up (`{-0.5, 0.5, 0.707}`): land times `0.35 + 0.8 * shade`, sea times `0.75 + 0.25 * shade`. Contours: a land pixel whose 10 m band differs from its right or lower neighbour's darkens by 0.72, by 0.45 where the 50 m band differs. The coastline (20, 20, 60).
  - `Relief_Map_Stream_End :: enum { Sea, Pit, Limit }`, `Relief_Map_Stream :: struct { trail: [dynamic][3]i64, length_metres: int, drop: i64, end: Relief_Map_Stream_End }` and `relief_map_stream :: proc(generation: Planet_Generation, start_direction: [3]i64, allocator := context.allocator) -> Relief_Map_Stream`, in fixed point: from the spring's direction, each step the lowest of 32 headings (angles `k * ANGLE_UNITS_PER_TURN / 32`, `fixed_sine`, `fixed_cosine`) 2 m out in the tangent plane (east from `fixed_cross` of +y, or +x where `|direction.y| >= UNIT_VECTOR_ONE * 9 / 10`, north the cross of the direction and east, the candidate `normalize_fixed(fixed_scale(direction, radius) + offset)`), taken when lower than the current height. When none is, a small pit spills: the lowest of 64 headings on rings of 4, 8, 12 and 16 m, from the first ring holding one lower. None ends at `.Pit`. It ends at `.Sea` below the sea radius and at `.Limit` after `RELIEF_MAP_STREAM_STEPS` steps (the trail's cap). `length_metres` sums the distances moved, `drop` is the start height less the end height.
  - `relief_map_mark :: proc(colours: [][4]u8, pixels: int, request: Relief_Map_Request, radius_metres: int, metres_per_pixel: f64, direction: [3]i64, colour: [4]u8, size: int)`: a disc at the direction's gnomonic place, nothing when it lies behind the centre or off the image.
  - `run_relief_map :: proc(argument, path: string, seed: u64, planets: []Planet) -> int`: 2 for a bad argument or radius (`error: --relief-map=...: <problem>`), otherwise the baked generation (`baked_planet_generation(make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES))`), the image at `RELIEF_MAP_PIXELS`, each spring's trail (magenta, size 1) and marker (black size 5 under cyan size 3), the home's (black 5 under white 3), encoded with `rl.ExportImageToMemory` (no window) and written with `platform.write_file_replacing`, 1 when it cannot be written. Stdout: `relief map: seed <s>, radius <r> m, relief <lowest> to <highest> m from the radius, home at latitude <a>, longitude <o>, crater floor <f> m over the sea` and per spring `relief map: spring <i> at latitude <a>, longitude <o>: <h> m over the sea, stream <l> m, drop <d> m, ends at <sea|pit|limit>`.
- `doc/build.md`: a row in the Command line table and a bullet under The workbench (the flags, what is drawn, the stdout lines, the before maps: run it with `MINE_OH_BELOWED_DATA` set to a copy of `data/` holding the `planets.sjson` of before).

### Cost: what is measured, and no estimated reject

Prototype (`-o:speed`, one core): a relief costs 377 ns before and 1116 ns with the shipped landforms in the wild, 409 ns within the calm circle. At the home's view (2 m over the floor, the shipped view distances) the selected nodes go from 349 to 566, the samples needing the relief in the coarse grids from 4.8 to 11.3 million, and in the simulated set's request (7 by 7 by 7 chunks) from 5.6 to 11.2 million. Expected: a fresh view (a start, the tech demo's teleport) costs 5 to 6.5 times the CPU of today, about 19 s against 4 s at the home, spread over the workers. Walking costs about 1.8 s of CPU per 32 m slab, a quarter of a core at a walk.

A reject per node from a footprint lattice and a slope bound is not specified: the steepest slope is about 2 (64 degrees, at crests), so the slack swamps level 2 and 3 nodes. A 9 by 9 by 9 lattice with a bound of 3 saved 30 percent of the coarse samples (18 percent of a view), and a fold the lattice missed would leave a hole. The exact skips above are what the item does. Question 1 below.

The measurement: `test_report_the_relief_cost` in `src/generation_planet_landforms_test.odin`, inside `when RELIEF_COST` (`RELIEF_COST :: #config(RELIEF_COST, false)`), run alone with `./build.sh test -o:speed -define:RELIEF_COST=true -define:ODIN_TEST_NAMES=game.test_report_the_relief_cost` (seconds, not a benchmark). For `pre_0306_test_home_at(8000)` and `shipped_test_home_at(8000)`: the ns per `surface_relief` over 200,000 points on a line (as `test_the_shaped_relief_stays_within_the_bound` spreads them) and 200,000 within 50 m of the home. For a camera 2 m over the crater floor and one 2 m over the ground at (79, 151): the node count per level of `select_field_nodes(make_field_view(...))`, per level the grid positions (`generate_field_grid`'s 34 cubed per node) where `planet_sample_shortcut` says `needs_relief`, the same count over the 7 by 7 by 7 chunks round the camera's chunk, and the wall time of `generate_field_grid` over the first 16 coarse nodes. One `log.infof` line per figure, asserting only non-empty selections. The implementer puts the figures in its report.

### Tests

New, `src/generation_planet_landforms_test.odin` (a planet literal `design_landform_test_planet(radius)` holds the shipped values above with the home (83, 132), the crater 12, 3, 4, 1 and the sea -11, so a later data retune does not break the parity tests):

- `test_gradient_noise_matches_the_design`: `gradient_noise(77, p, 409600)` is 0 at `{0,0,0}` and `{1,2,3}`, -9185 at `{123456, -654321, 98765}`, 6569 at `{-4096000, 32768000, 777777}`, and within `±NOISE_ONE` and 0 at every lattice point over 10,000 points.
- `test_landform_relief_matches_the_design`: `DEFAULT_WORLD_SEED`, points `fixed_scale(planet_direction_at(...), radius)`: at 8 km `landform_relief` is 8192 at (83, 132), 108078 at (81, 139), 305724 at (79, 151), -14393 at (-30, 10), and `uncratered_relief` 2697 at (83, 132) and 113668 at (81, 139). At 4 km 9743 and at 16 km 211207 at (81, 139).
- `test_the_relief_bounds_follow_the_record`: `make_test_planet()` gives `{-metres(34), metres(34)}`, the design planet `{-310067, 514867}`, and a planet with ranges and hills at 100 percent and spur 0 adds the full `range_metres` and `hill_metres`.
- `test_the_landform_relief_stays_within_the_bound`: the shipped planet at each preset, 20,000 points spread as the existing bound test plus 20,000 within 1 km of (79, 151): `surface_relief` within `[relief_lowest, relief_highest]`.
- `test_the_home_is_calm`: the shipped planet at each preset: `landform_relief` equals `metres(home_metres)` at 1000 points within `calm_metres` of the home, and `home_wildness` is `NOISE_ONE` beyond `wild_metres`.
- `test_the_landform_relief_is_deterministic`: two generations of one seed agree at 1000 points, another seed differs at some, and `generate_field_chunk` of the shipped planet twice gives identical bytes at the spring's chunk.
- `test_a_record_without_landforms_generates_as_before`: `pre_0306_test_home_at(8000)` (below), a literal: the density, material and tint bytes of three chunks (the home's surface chunk, the chunk under (83, 144)'s surface, the chunk one below the home's) folded with `hash_combine`, and the sum of `uncratered_relief` over 1000 points, equal constants the implementer records on `main` before changing the generation (the test written first against the old code, the constants pasted in, then the change).
- `test_an_old_world_file_keeps_its_relief`: a `world.sjson` text with a `planet_generation` and no `landforms` key, resolved against `shipped_test_planets()`: one log line (captured with `platform.begin_log_capture`) holding "records no landforms", the resolved record's and `make_recorded_planet`'s landforms zero, and its generation's `surface_relief` equal to the legacy relief at 100 points.
- `test_a_new_world_records_its_landforms`: `planet_generation_record(shipped)` holds the data's landforms, and `encode_world_file` then `parse_world_file` keeps them.
- `test_landforms_problems`: the zero value passes. Refused, each with the key's name: every key out of its bounds (a knot as `region_ranges_percent[3]`), `wild_metres <= calm_metres`, a home under the dry margin, `calm_metres` under the crater's reach, bounds over either cap, a bedrock depth under the planet's minimum, and a planets file whose `landforms` lacks a key (`planets[0].landforms is missing hill_metres`).

New, `src/loop_relief_map_test.odin`:

- `test_the_relief_map_argument_is_checked`: three and four words parse, while a missing word, a word that is not a number, latitude 91, longitude -181, size 99 and 20,001, a negative radius are refused.
- `test_the_relief_map_marks_the_home_and_the_sea`: the shipped planet at 8 km, centred on the home, 64 pixels over 4000 m: the centre pixel is the home's white, some pixel whose height lies under the sea has blue above red, and the PNG written into a temporary directory starts with the PNG signature.
- `test_the_default_springs_stream_runs_downhill`: the shipped planet with `DEFAULT_WORLD_SEED`: at 8 km the first spring's ground at least 20 m over the sea and `relief_map_stream` at least 100 m long with at least 15 m drop, and at 16 km at least 100 m long. The prototype's float trace gave 200 m and 30 m, 218 m and 53 m. A fixed point trace that falls short is reported, not loosened.

Changed: a helper `pre_0306_test_home_at(radius)` (`generation_planet_test.odin`, beside `shipped_test_home_at`), a planet literal holding every generation value `data/planets.sjson` holds before 0306 (octaves 512/10, 128/5, 32/2, shape 32, 700, 128, 1200, 10, 16, -30, spring (83, 144), no landforms, the palette, home, crater and trees as they stand), so later data edits leave it. Tests that check the 0189 terms or the old ground (`test_the_basins_hold_the_sea_near_a_dry_home`, `test_the_shaped_relief_stays_within_the_bound`'s shipped half, `test_the_shipped_crater_floor_lies_above_the_sea`'s clamp line) move to it. Tests that check the shipped world (the crater floor over the sea, the spring above the sea, tree and vein counts) keep the shipped planet and are re-pinned where their figures change. Each moved or re-pinned test is named in the report with its old and new figure. The readers' tests (`generation_planet_test.odin` lines 101, 104, 166, 323, 556 and 630, `world_field_light_test.odin` 210, whose `Planet_Generation` literal sets the bounds, `world_field_lod_test.odin` 356, `simulation_field_test.odin` 145) take the planet's bounds.

### Docs

- `doc/content.md`, Planets: the keys line (`landforms` optional beside `relief_shape`, its keys and bounds, the octave limit renamed, the bedrock minimum per planet, the bound per planet and its caps), the crater line's floor heights (9.5, 8.7, 9.1 m), and The arrival's `arrival_start_metres` line (128 m).
- `doc/architecture.md`, World generation: the landform term after the 0189 terms (the warp, the region curve, the ridges and spurs, the hills, the calm circle, gradient noise, the skips), the per planet bound and its readers replacing "add up to at most `MAXIMUM_RELIEF_METRES`". Save format: `landforms` in the record list, absent read as off with one log line.
- `doc/build.md`: the map mode (above).
- `data/planets.sjson` and `data/game.sjson` comments as above.

### Hand-back check lines that apply

- A changed save layout loads an old save: the record's new object reads as zero (off) with one log line, covered by `test_an_old_world_file_keeps_its_relief` and `test_a_record_without_landforms_generates_as_before`.
- A number parsed from text is range checked: `parse_relief_map_argument`, `test_the_relief_map_argument_is_checked`.
- A file is written to `<path>.tmp` and renamed: the map through `write_file_replacing`.
- A list that grows without bound is capped: the stream trail at `RELIEF_MAP_STREAM_STEPS`.
- Tests never touch the machine's state directory: the map test writes into a temporary directory.
- A new participant in a shared budget: the generation workers' CPU, measured by `test_report_the_relief_cost` (above).

### Open questions answered

- Gradient or value noise: gradient for the landforms (above), while the detail octaves stay value noise, small enough that their lattice does not show.
- Old worlds: zero is off, nothing remapped, the bound without landforms stays 34 both ways so even the crater clamps match.
- The home: the calm circle blends the region to `home_metres` as well as fading the ranges and hills, so the home is a plain at the same height for every seed and the planet check proves it dry. The dry home search stays for planets without landforms.
- The sea level stays -11: the knots are heights from the radius like every other relief key, and moving the sea would reword more comments and tests than it saves.
- The ledges stay (they are the mantle steps of 0189 and the walking scale's texture). Terraces and basins go off in the data: the region and the ranges make the basins, and the terraces stepped only the old long octave.

### Questions to the main agent

1. The cost: 5 to 6.5 times the CPU per fresh view and about 1.8 s per 32 m slab, with no estimated reject. Accept and measure on the couch and the phone, or a follow-up item now (a landform field cached on a coarse lattice per chunk and node, exact by definition but with faint creases at the lattice planes unless tricubic)?
2. The spring at 4 km lies on the calm plain (82 m, 7 m drop). Accept, or prefer (79, 151) for a stronger 8 km start at the cost of 4 km?
3. The total range is about 176 m, not 160: keep (the peaks hit the 100 m target) or lower `range_metres` to 70?

### Main agent's decisions (2026-11-06)

- The cost is accepted for this item and measured as specified. Lowering it is 0314 (the landform field's cost), designed from this item's figures and the couch's and the phone's feel.
- The springs: `springs = [{latitude_degrees = 79, longitude_degrees = 151}, {latitude_degrees = 81, longitude_degrees = 139}]`. The first is the tech demo's spring start and the pod's heading (the prototype's trace: 366 m and 65 m at 8 km, 156 m at 16 km, 80 m at 4 km), the second keeps a stream near the home. `test_the_default_springs_stream_runs_downhill` checks the first at 8 km (at least 300 m and 50 m drop) and 16 km (at least 100 m), and the second at 8 km (at least 150 m). The `springs` and `home` comments follow.
- The range stays at about 176 m.
- 0307 lands on this tree: `OPTIONAL_PLANET_KEYS` grows to three there, and its `Generation_Purpose` members come after `Planet_Landforms`.
