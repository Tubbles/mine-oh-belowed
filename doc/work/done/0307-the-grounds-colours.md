# 0307: The ground's colours: grass, rock, sand and snow

Status: landed (2026-11-07, 17a7fd6)

Milestone: the world generation series 0306 to 0313, built on 0306's relief. The user (2026-11-06): "better visuals because right now it is very bland and depressing to look at", "varied textures". The research is `work/world_generation_research.md`.

## Goal

The ground stops being one orange brown. Gentle open ground is grass coloured by a climate (lush green, dry yellow, dark cold green), steep faces show rock, a band of sand lines the sea and the lakes, cold heights carry snow, and a broad colour variation keeps the distance from looking tiled. The hard edged 256 m tint cubes go.

## Controls

None.

## Change

- A climate field of the planet (temperature and moisture), integer noise in the generation, one pure function read by the mesher now and by the biomes (0308) and the trees (0310) later. Height cools it (a lapse), so the snow line follows the relief of 0306.
- Look layers in the field shader over the strata: grass, sand, snow and the steep face's rock, chosen from the slope against the local up (the radial), the height above the sea and the climate, blended rather than cut. They are looks, not materials: a dug surface still yields topsoil (real surface materials are 0309).
- The climate's ground colours in data: a few anchors over temperature and moisture (Minecraft's grass colour map), the snow line and the sand band beside them, in the planet record.
- Generated tiles for grass, sand and snow in `data/textures/field_materials.sjson`'s manner, isotropic, each with its grain (DESIGN.md, Art direction: sand smooth, rock faceted).
- The fragment's texture reads do not grow: the design picks a scheme that pays for the new layers (only a vertex's dominant materials sampled, or a texture array) and names the count before and after. The Deck's budget holds (DESIGN.md, Targets).
- A dug pit's floor: the design names the rule that keeps fresh cuts from turning to grass (the generated surface, a mark per sample) or why a green pit floor is acceptable until 0309.
- Docs: `doc/presentation.md` (The field), `doc/content.md` (Planets, the field's textures); the log.

## Verify

- The checks, the suite, `shader_source_test.odin`.
- The captures of 0306 (the spring start, the home, a far point, from the ground and from 40 m and 120 m up) before and after this item, and one of a dug pit; sent to the user.

## Specification (design, 2026-11-06)

0306's specification was not written when this was designed. 0307 reads the relief only through `uncratered_relief(generation, point)` (the generated surface's height above the radius without the crater) and never reads the relief bound. Assumptions for the main agent to reconcile: 0306 keeps that procedure (or names its successor), appends its own `Generation_Purpose` members before 0307's, and may have turned `OPTIONAL_PLANET_KEY` into a list already.

The prototype is `tmp/0307/proto/main.odin` (today's relief ported, the climate and the look below, `tmp/0307/proto.bin`). Images: `tmp/0307/colormap.png` (the grass colour over -12 to 34 °C left to right by moisture, wet at the top, snow at the left), `tmp/0307/sheet_4km.png` (4 km round the home: before, after, after with the relief tripled about the sea as a stand in for 0306), `tmp/0307/sheet_zoom.png` (the same for 512 m), `tmp/0307/wide16km_tall.png` (16 km, tripled relief: snow on cold heights).

### Decisions

- The climate reaches the shader per vertex: the mesher evaluates it at each vertex. The tint byte stays what it is, the sample's identity that a dug item and a placed sample carry and the save holds. Reusing it would change generated chunks and old saves, and one byte cannot hold two climate values. A pure function of the position gives neighbouring nodes and levels the same value at a shared vertex.
- The tint cubes go in a world with a climate: the strata (topsoil, stone, deep stone, bedrock, the ores) and the rock look take the palette as a smooth field, a noise of 256 m wavelength read as a continuous index along the palette. The sample's tint byte is unchanged. A world without a climate keeps the cubes.
- Old worlds keep today's look: the record's `climate` is zero in a world file written before 0307, so the look is off (0189's rule for `relief_shape`). The field's keys are recorded (0308 and 0310 will generate from them), the look's keys are the data's in every world, as the palette's colours are.
- Texture reads: one 256 by 256 atlas holding every tile, read with `textureLod` at a level computed from the position's derivatives outside any branch, so the reads sit in branches and loops without the derivative problem. A projection whose sharpened share is under 0.05 is not read, and only the four largest tile weights of a fragment are read. Before: 42 reads at every fragment, water included. After: 2 per tile and projection read (the two scales), so 2 on ground flatter than about 25 degrees with one tile, 4 on a steeper slope, at most 4 tiles by 3 projections by 2 scales = 24, and 0 in the water pass (its vertices have no weights). The atlas also frees the material maps, so 0309's materials need no shader change beyond the tile count.
- The dug pit: the mesher compares each vertex with the generated surface along its radial (`uncratered_relief`). Within `max(750 mm, the grid's cell)` it is natural ground, past twice that a cut or a fill, linear between. Grass, sand and snow lie only on natural ground, so a pit's floor and a mound show bare topsoil. A scrape shallower than the tolerance (0.75 m at the finer spacings, a cell at 1 m) stays green. Steep faces take the rock look whether cut or not (a pit's walls read as rock, as a cliff does). The comparison is against the relief without the crater, so the arrival's crater reads as fresh ground. It runs only for grids holding loaded samples, at every vertex of such a grid (the review: a stone vertex counted natural beside a cut topsoil one put grass on a mined floor). A grid generated whole is natural throughout.
- The snow line is a temperature: snow lies where the vertex's temperature (with the lapse, at its own height) is below `snow_celsius`. On the home it starts about 95 m over the sea at the mean climate and about 45 m where the sea level is at 7 °C, so 0306's peaks of about 100 m carry snow wherever the sea level is below about 13 °C, some 40 percent of the ground. Any relief works through the lapse.
- Sand lies within `sand_metres` of the sea level and on the sea floor below it, on gentle ground. Basins the sea fills get it. Ponds of springs above the sea do not: their water is simulated, so it is not cheap (0312).
- No home calm: the home's climate is the seed's. The default seed's home is 13.3 °C and 88 percent moisture at 8 km (the climate seed is purpose 26, the prototype used 25), lush green.
- The home planet's palette moves from orange tints to warm greys, so the rock look on cliffs reads as stone beside the green (see the questions: old worlds take the data's palette colours too).

### Data

`data/planets.sjson`, the home planet, a new optional object `climate` (off when absent, every key required and checked when present). Field keys, recorded by a world:

| key | bounds | shipped |
|---|---|---|
| `temperature_wavelength_metres` | 64 to `MAXIMUM_RELIEF_WAVELENGTH_METRES` | 1600 |
| `moisture_wavelength_metres` | 64 to `MAXIMUM_RELIEF_WAVELENGTH_METRES` | 1100 |
| `sea_level_celsius` (the mean at the sea level) | -100 to 100 | 13 |
| `temperature_spread_celsius` (the noise's reach either side, 90 percent of the ground within half of it) | 0 to 100 | 14 |
| `lapse_millicelsius_per_metre` (cooling per metre above the sea, warming below) | 0 to 1000 | 120 |
| `moisture_percent` | 0 to 100 | 55 |
| `moisture_spread_percent` | 0 to 100 | 70 |

Look keys, the data's in every world:

| key | bounds | shipped |
|---|---|---|
| `grass_colors` (9 colours, rows cold, temperate, hot, each dry, moderate, wet: the colour the grass shows at full light, the tile's mean times two applied) | components 0 to 255 | `[146,150,104] [80,124,78] [44,98,70]` / `[190,182,82] [96,166,58] [52,140,58]` / `[220,180,90] [158,180,56] [60,160,50]` |
| `grass_cold_celsius`, `grass_hot_celsius` (the first and the last row, the middle row at their mean) | -100 to 100, hot above cold | 2, 26 |
| `snow_celsius`, `snow_fade_celsius` | -100 to 100, 1 to 50 | 0, 3 |
| `snow_color` | components 0 to 255 | `[210, 218, 232]` |
| `sand_metres`, `sand_fade_metres` (above the sea level) | -64 to 64, 1 to 64 | 1, 2 |
| `sand_color` | components 0 to 255 | `[208, 188, 142]` |

`palette` of the home: `[136,124,104] [122,116,106] [148,132,108] [112,108,100]`.

`data/textures/field_materials.sjson`: a second required array `looks` beside `materials`, one entry per look (`grass`, `sand`, `snow`), keyed `look` instead of `material`, the same colour and ore parameter keys and the crystal size 1 rule. The tiles are near neutral, the planet's colour multiplies them.

- `{look = "grass", ground = [134, 134, 130], fleck = [100, 104, 96], seed = 2108, share = 0.35, blob_width = 0.5, crystal_size = 1, stone_grain = 14, stone_mottle = 16, ore_grain = 10, rim_strength = 0.1}` (busy, blades)
- `{look = "sand", ground = [134, 132, 128], fleck = [112, 108, 102], seed = 2109, share = 0.2, blob_width = 0.4, crystal_size = 1, stone_grain = 6, stone_mottle = 8, ore_grain = 4, rim_strength = 0}` (smooth)
- `{look = "snow", ground = [130, 130, 132], fleck = [146, 146, 150], seed = 2110, share = 0.12, blob_width = 0.35, crystal_size = 1, stone_grain = 3, stone_mottle = 10, ore_grain = 6, rim_strength = 0}` (smooth with sparkle)

### Generation (world cluster)

- `src/generation_seed/generation_seed.odin`: append `Planet_Climate` and `Planet_Ground_Look` to `Generation_Purpose`, after 0306's.
- `src/data_planet.odin`: `Planet_Climate` (the 16 keys above, `grass_colors: [9][3]int`, row times 3 plus column) and `Planet_Climate_Field` (the 7 field keys). `Planet.climate: Planet_Climate`, optional. `OPTIONAL_PLANET_KEY` becomes `OPTIONAL_PLANET_KEYS :: [2]string{"relief_shape", "climate"}` and `missing_struct_key` takes `optional: []string`. `missing_planet_key_problem` checks a present `climate` for every key as it does `relief_shape`. `climate_problem(climate: Planet_Climate) -> string` (`{}` passes, any other is held to every bound above, through `climate_field_problem`, messages in the form `climate.snow_fade_celsius 0 is outside 1 to 50` and `climate.grass_hot_celsius 2 is not above grass_cold_celsius 2`), called from `planet_problem`. `climate_field_problem(field: Planet_Climate_Field) -> string` (`{}` passes). `planet_climate_field(climate) -> Planet_Climate_Field` and `with_climate_field(climate, field) -> Planet_Climate` copy the seven keys. Constants `MINIMUM_CLIMATE_WAVELENGTH_METRES :: 64`, `MAXIMUM_CLIMATE_CELSIUS :: 100`, `MAXIMUM_LAPSE_MILLICELSIUS_PER_METRE :: 1000`, `MAXIMUM_SNOW_FADE_CELSIUS :: 50`, `MAXIMUM_SAND_METRES :: 64`.
- `src/generation_planet.odin`: `Planet_Generation` gains `climate: Planet_Climate_Field`, `climate_seed: u64`, `ground_look_seed: u64`, set in `make_planet_generation` from `planet_climate_field(planet.climate)` and the two purposes. No sample changes, no `GENERATOR_VERSION` change.
- New `src/generation_planet_climate.odin`, integers only, so the later simulation readers agree:
  - `Planet_Climate_Sample :: struct {temperature_millicelsius: i64, moisture_permille: i64}`.
  - `CLIMATE_SECOND_OCTAVE_PERMILLE :: 309`.
  - `planet_climate_noise(seed: u64, point: [3]i64, wavelength_metres: int) -> i64`: `(2 * value_noise(seed, point, w) + value_noise(hash_combine(seed, 1), point, w * 309 / 1000)) / 3`, within ±`NOISE_ONE`.
  - `planet_climate(generation: Planet_Generation, on_sphere: [3]i64, height: i64) -> Planet_Climate_Sample`: `{}` when `generation.climate.temperature_wavelength_metres == 0`, else temperature `sea_level_celsius * 1000 + spread * 1000 * noise / NOISE_ONE - lapse * height / POSITION_UNITS_PER_METRE` with the noise from `hash_combine(climate_seed, 0)`, moisture `clamp(moisture_percent * 10 + moisture_spread_percent * 10 * noise / NOISE_ONE, 0, 1000)` with the noise from `hash_combine(climate_seed, 2)`. `on_sphere` is the point projected onto the sphere of the radius (as the relief reads it), `height` the height above the sea level in position units. The one pure function the mesher reads now and 0308 and 0310 later.
- `src/generation_planet_record.odin`: `Planet_Generation_Record.climate: Planet_Climate_Field` (zero in a file written before it). `planet_generation_record` records `planet_climate_field(planet.climate)`. `make_recorded_planet`: the result's climate is `with_climate_field(planet.climate, record.climate)` when both are on, `{}` otherwise. `planet_generation_record_problem` also returns `climate_field_problem(record.climate)`. `resolve_world_planet` logs one line for a recorded world: `world: the world file records no climate, its ground keeps the look without one` (record off, data on) or `world: the world file records a climate but %q in %s has none, its ground keeps the look without one` (record on, data off).

### Mesher (world cluster, floats allowed)

- New `src/world_field_ground_look.odin`:
  - `Field_Vertex_Look :: struct {grass: [3]u8, snow: u8, sand: u8, natural: u8}`.
  - `Field_Ground_Look :: struct {on: bool, generation: Planet_Generation, climate: Planet_Climate, palette: [][3]int}` and `make_field_ground_look(generation, planet) -> Field_Ground_Look` (`on` is `planet.climate != {}`).
  - Constants: `GROUND_VARIATION_WAVELENGTH_METRES :: 48`, `GROUND_VARIATION_SECOND_PERMILLE :: 277`, `GROUND_VARIATION_STRETCH :: 1.6`, `GROUND_VARIATION_CELSIUS :: 1.0`, `GROUND_VARIATION_MOISTURE :: 0.14`, `GROUND_VARIATION_BRIGHTNESS :: 0.07`, `GROUND_VARIATION_SAND_METRES :: 0.8`, `GROUND_TINT_WAVELENGTH_METRES :: 256`, `FIELD_CUT_TOLERANCE_MILLIMETRES :: 750`.
  - `ground_variation(generation, on_sphere) -> f32`: `clamp((2 * first + second) / (3 * NOISE_ONE) * 1.6, -1, 1)`, first at 48 m from `hash_combine(ground_look_seed, 0)`, second at 48 m times 277 per mille from `hash_combine(ground_look_seed, 1)`.
  - `field_ground_tint(generation, palette, on_sphere) -> [3]u8`: noise at 256 m from `hash_combine(ground_look_seed, 2)`, index `clamp((noise * 1.6 / NOISE_ONE + 1) / 2, 0, 1) * (len - 1)`, linear between the two entries round it. A one colour palette gives that colour. Also the debris' tint.
  - `field_grass_color(climate: Planet_Climate, celsius, moisture: f32) -> [3]f32`: bilinear over the 3 by 3 grid, `t = clamp((celsius - cold) / (hot - cold), 0, 1) * 2`, `m = clamp(moisture, 0, 1) * 2`, row and column `min(int(t), 1)` and `min(int(m), 1)`.
  - `field_snow_cover(climate, celsius: f32) -> u8`: `255 * clamp((snow_celsius - celsius) / snow_fade_celsius + 0.5, 0, 1)`.
  - `field_sand_cover(climate, height_metres: f32) -> u8`: `255 * clamp((sand_metres - height_metres) / sand_fade_metres + 0.5, 0, 1)`.
  - `field_natural_share(generation, on_sphere: [3]i64, distance, cell: i64) -> u8`: the dug pit rule above with `off = abs(distance - generation.radius - uncratered_relief(generation, on_sphere))` and `tolerance = max(millimetres_to_position_units(750), cell)`.
  - `field_vertex_world_position(grid: ^Field_Grid, position: [3]i32, spacing_millimetres: int) -> World_Position`: the grid origin's position plus `position * step * spacing * POSITION_UNITS_PER_METRE / (FIELD_MESH_POSITION_UNITS * MILLIMETRES_PER_METRE)`.
  - `field_vertex_ground_look(look: Field_Ground_Look, position: World_Position, cell: i64, measure_cuts, has_topsoil: bool) -> (tint: [3]u8, vertex: Field_Vertex_Look)`: distance by `vector_length`, `on_sphere` by `project_onto_sphere`, height `distance - generation.sea_radius`, the climate at that height, celsius and moisture shifted by the variation times their constants, the grass colour times `1 + variation * 0.07` rounded and clamped, snow from the shifted celsius, sand from the height in metres plus the variation times 0.8, natural from `field_natural_share` when `measure_cuts && has_topsoil`, else 255.
  - `write_field_ground_look(surface: ^Field_Surface, grid: ^Field_Grid, look: Field_Ground_Look, spacing_millimetres: int, measure_cuts: bool)`: for every vertex, its colour and look from the above (`has_topsoil` is the topsoil slot's weight above 0). Nothing when `!look.on`. It runs before the skirts, which copy their border vertex's look. Computed after, the skirts' lower vertices would read as cut and show bare seams.
- `src/world_field_mesh.odin`: `Field_Surface_Vertex.look: Field_Vertex_Look` (zero without a climate). `Field_Mesh_Data.ore_weights` becomes `looks: [dynamic][2]f32`. `field_pack_bytes(bytes: [3]u8) -> f32` returns `f32(bytes[0]) + 256 * f32(bytes[1]) + 65536 * f32(bytes[2])`, exact in f32. `mesh_field_grid(grid, palette, spacing_millimetres, skirt_faces, allocator := context.allocator, look: Field_Ground_Look = {}, measure_cuts := false)` calls `write_field_ground_look` between `mesh_field_surface` and `append_field_skirts`. `mesh_field_water_grid` takes no look.
- Vertex layout (`field_mesh_from_surface`, `upload_field_mesh`):
  - colour: rgb the strata tint (the corners' palette mean without a climate, `field_ground_tint` with one), alpha the sky light. Unchanged attribute.
  - tangent: topsoil, stone, deep stone, bedrock weights, 0 to 1. Unchanged.
  - texture coordinate: x the block light, 0 to 1, and y `field_pack_bytes` of the hematite, chalcopyrite and coal weights.
  - second texture coordinate: x `field_pack_bytes(look.grass)`, y `field_pack_bytes({look.snow, look.sand, look.natural})`.
- `src/world_field_streaming.odin`: `Field_Worker_Shared.look: Field_Ground_Look`, set in `start_field_streaming` by `make_field_ground_look(shared.generation, planet)`. `run_field_job` passes `look = shared.look, measure_cuts = job.grid != nil` (a grid holding loaded samples).

### Renderer (presentation cluster)

- `src/texture_field_materials.odin`: `Field_Look :: enum u8 {Grass, Sand, Snow}`, `FIELD_GROUND_TILE_COUNT :: FIELD_MATERIAL_TILE_COUNT + len(Field_Look)`, `field_look_tile(look) -> int`. `Field_Ground_Tiles :: [FIELD_GROUND_TILE_COUNT]Tile_Pixels` replaces `Field_Material_Tiles`: the materials in enum order, then the looks, which is the shader's tile index. The parser takes `materials` and `looks` and nothing else (`%s: expected only materials and looks, arrays`). A look entry missing, repeated or unknown is refused (`no entry for look snow`, `looks[1] repeats grass`, `unknown look moss`). Atlas: `FIELD_GROUND_ATLAS_COLUMNS :: 4`, `FIELD_GROUND_ATLAS_CELL_TEXELS :: 64`, `FIELD_GROUND_ATLAS_TEXELS :: 256`, `FIELD_GROUND_ATLAS_MARGIN_TEXELS :: 24`, an assert that the tiles fit the 16 cells. `field_ground_atlas_pixels(tiles: Field_Ground_Tiles, allocator := context.allocator) -> [][4]u8` (pure): tile `i` fills cell column `i % 4`, row `i / 4`, cell texel `(x, y)` taking tile texel `((x - 24) %% 16, (y - 24) %% 16)`, unused cells zero. Level 4 of each cell is then exactly the tile's mean.
- `src/render_field.odin`: `field_material_sampler_names` and the two map asserts go. `upload_field_ground_atlas(tiles) -> rl.Texture2D` through `load_rgba_texture`, mipmaps, trilinear, clamped, on map 0 (`MAP_ALBEDO`, uniform `ground_atlas`). `init_field_renderer` takes `Field_Ground_Tiles`, and `material_colors` keeps the seven materials' means. `set_field_ground_look_uniforms(shader, planet)` at init: `ground_look_on` 1 or 0, `sand_color` and `snow_color` over 255. `field_globe_color(planet: Planet, grass_mean: [3]f32) -> rl.Color`: with a climate the temperate moderate anchor times the grass tile's mean times two, else `palette[0]` as today. Callers in `loop_field_session.odin` and `loop_planet_preview.odin` take the new tile type.
- `src/render_arrival_debris.odin`, `arrival_debris_colors`: with `site.generation.climate != {}` the tint is `field_ground_tint` at the home, else the palette cube as today.
- `data/shaders/field.vs`: `vec3 unpack_bytes(float packed_bytes)` (`packed` is reserved in GLSL and Mesa refuses it; floor by 65536.0, then by 256.0, each byte over 255.0) and the outs `fragment_ore_weights` from the texture coordinate's y, `fragment_grass_color` and `fragment_look` (snow, sand, natural) from the second texture coordinate.
- `data/shaders/field.fs`, structure:
  - Uniforms: `sampler2D ground_atlas` (the only sampler), `float ground_look_on`, `vec3 sand_color`, `vec3 snow_color`. The seven `material_texture_*` go.
  - Constants: `ground_tile_count = 10u`, `strata_tile_count = 7u`, `grass_tile = 7u`, `sand_tile = 8u`, `atlas_columns = 4u`, `atlas_cell_texels = 64.0`, `atlas_texels = 256.0`, `tile_texels = 16.0`, `tile_margin_texels = 24.0`, `largest_lod = 4.0`, `most_tiles_read = 4u`, `projection_floor = 0.05`, `weight_floor = 0.02`, `far_lod_shift = 1.442695` (log2 of e), rock from steepness 0.234 to 0.357 (40 to 50 degrees), sand giving way from 0.134 to 0.234 (30 to 40 degrees). `tile_metres`, `second_scale_ratio`, `blend_sharpness`, `tint_scale` as today.
  - Outside every branch: `position = fragment_world_position / tile_metres`, `dx = dFdx(position)`, `dy = dFdy(position)`, one level per plane `log2(max(length(dx.yz), length(dy.yz)) * tile_texels)` and likewise for `zx` and `xy`, and the projection shares sharpened as today, then `max(share - projection_floor, 0.0)` renormalised.
  - `atlas_texel(uint tile, vec2 coordinate, float lod)`: `textureLod(ground_atlas, (cell + tile_margin_texels + fract(coordinate) * tile_texels) / atlas_texels, min(lod, largest_lod))`. `plane_color` is the mean of the near read and the far read at `coordinate / second_scale_ratio` and `lod - far_lod_shift` (today's second scale reads the same planes, scaled). `tile_color` adds the planes whose share is above 0.
  - Look weights per fragment: `up = normalize(fragment_world_position)` (the planet's centre is the origin), `steepness = 1.0 - dot(normal, up)`. With the strata weights normalised as today and `topsoil = weights.x`: `rock = topsoil * ground_look_on * smoothstep(rock start, rock full, steepness)`, `cover = (topsoil - rock) * ground_look_on * fragment_look.z`, `snow = cover * fragment_look.x`, `sand = (cover - snow) * fragment_look.y * (1.0 - smoothstep(sand start, sand full, steepness))`, `grass = cover - snow - sand`. Tile weights: topsoil `topsoil - rock - cover`, stone `weights.y + rock`, deep stone, bedrock, the three ores, grass, sand, snow, each `max(weight - weight_floor, 0.0)`.
  - A loop of `most_tiles_read` picks the largest remaining weight, zeroes it, stops at 0, and adds `weight * tile_color(tile) * tile_tint(tile)`. The albedo is that sum times `tint_scale` over the picked weights' sum. `tile_tint`: the strata tiles take `fragment_color.rgb`, grass `fragment_grass_color`, sand `sand_color`, snow `snow_color`.
  - Lighting, the point lights, the torchlight, the glint and the fog unchanged, `point_light_sum` and `spot_light` stay line for line. The header comment's derivative paragraph names the new rule (levels from the position's derivatives outside any branch, every read `textureLod`).
  - Every integer literal carries `u`.

### Tests

- `generation_planet_climate_test.odin`: `test_the_climate_is_off_without_a_climate` (zero field gives `{}`), `test_the_climate_is_a_pure_function_of_the_seed_and_the_point` (same inputs equal, two seeds differ at some of 64 points), `test_the_climate_stays_within_its_spread` (a 64 by 64 lattice of points 200 m apart on the 8 km home sphere at height 0: temperature within 13 ± 14 °C, moisture 0 to 1000, the 5th to 95th percentile of the temperature spans at least 7 °C), `test_the_lapse_cools_the_heights` (at one point, +100 m is exactly 12000 millicelsius colder, -10 m 1200 warmer), `test_the_climate_varies_smoothly` (points 1 m apart along 2 km differ by at most 100 millicelsius and 10 permille).
- `data_planet_test.odin`: `test_a_planet_record_takes_an_optional_climate` (absent gives `{}`, the shipped line parses to its values, a missing key is refused naming `planets[0].climate is missing snow_color`, bound messages for a wavelength of 0, a fade of 0, hot not above cold, a component of 256, an unknown key). `test_the_shipped_planets_file_loads` also expects the home's climate on.
- `generation_planet_record_test.odin`: `test_a_world_file_before_the_climate_keeps_the_old_look` (the record text without `climate` parses to zero, the recorded planet's climate is `{}`, `make_field_ground_look(...).on` is false), `test_the_world_file_records_the_climate_field` (round trip equal, a data edit of a field key leaves the recorded planet's, a data edit of a grass colour reaches it, a recorded wavelength of 10 is a record problem).
- `world_field_ground_look_test.odin` (planet: `make_test_planet` with the shipped climate, home and generation `TEST_PLANET_SEED`): `test_the_ground_look_is_off_without_a_climate` (vertices keep the corners' palette mean and a zero look), `test_a_generated_node_meshes_natural_with_its_skirts` (a level 0 node 200 m from the home, generated, meshed with `EVERY_FIELD_FACE`, look on, `measure_cuts` true: at least 98 percent of all vertices, skirts included, natural 255), `test_a_dug_pit_floor_is_not_natural` (the same grid with every sample within 2.5 m of the surface vertex nearest the node's centre made air: the vertex nearest the pit's bottom has natural 0, vertices farther than 6 m from it keep the value they had before the dig), `test_the_crater_reads_as_cut_ground` (`make_test_planet` with the shipped crater `{12, 3, 4, 1}`, its generation baked, the node over the home: the floor's vertices natural 0), `test_the_grass_colour_meets_the_anchors` (the corners and the centre of the grid exactly, clamped outside), `test_the_snow_and_the_sand_fade_across_their_lines` (255 well inside, 0 well outside, monotone between), `test_the_ground_tint_has_no_seam` (along 1 km in 1 m steps no channel changes by more than 2 between neighbours, and more than one palette colour is approached).
- `world_field_mesh_test.odin`: `test_the_packed_bytes_unpack_exactly` (every value of each byte position and 1000 hashed triples through `field_pack_bytes` and an Odin mirror of `unpack_bytes` in f32). The ore weight tests move to the packed layout.
- `texture_field_materials_test.odin`: the shipped file loads ten tiles, `test_field_look_textures_need_every_look_once`, `test_the_ground_atlas_cells_repeat_their_tile` (cell texel `(24 + i, 24 + j)` equals tile texel `(i, j)` and the texel 16 away equals it, for every tile, unused cells zero).
- `shader_source_test.odin`: `test_the_field_shader_reads_the_ground_atlas_by_level` (`uniform sampler2D ground_atlas;` is field.fs's only sampler, no `texture(` call, the three look uniforms declared, field.vs declares `unpack_bytes`), `test_the_field_shader_knows_the_atlas_layout` (the constants' lines equal the Odin constants, formatted: tile count, columns, cell, atlas, tile texels, margin, `largest_lod` as log2 of the tile size). The bare integer test covers the `u` suffix.
- `render_field_test.odin`: `test_the_globe_takes_the_temperate_grass` (with and without a climate).

### Docs

- `doc/presentation.md`, Field meshes: the per vertex paragraph (the layout above, the look pass and its order before the skirts), the globe, the field shader paragraph (the atlas, the levels, the projection floor, the four tiles, the read count, the look layers and their slopes). Textures: the field's tiles in one atlas, the looks.
- `doc/content.md`, Planets: the `climate` keys and the palette's role as the smooth strata tint. Textures: `looks`.
- `doc/architecture.md`, World generation: `planet_climate`, its seeds, what a world records.
- `doc/code_map.md`: the two new files in the world cluster, the new tests.

### Hand-back check

- A number parsed from text is range checked: every `climate` key and the record's field keys (`climate_problem`, `climate_field_problem`).
- A changed save layout loads an old save: `planet_generation.climate` reads zero from an old world file, the old look follows, one log line.
- A new participant in a shared budget: the mesh jobs share the workers. The look pass costs about 7 value noises a vertex, plus the relief's for topsoil vertices of grids with loaded samples (the prototype: about 0.12 µs a noise, so 1 to 2 ms more a job of 2000 vertices). The implementer reports the streaming staying level on the default seed's start (pending jobs drain as before), without a benchmark.
- Tests never touch the machine's state: the data files are read only.

### Questions to the main agent

1. The palette change reaches old worlds too (their cubes take the data's colours): warm grey instead of orange. Ship it, or keep the old palette and accept tan rock?
2. Old worlds keep the old look per the brief. Nothing generated reads the climate in 0307, so the data's climate could colour old worlds as well. I kept the rule so 0308 finds the field recorded from the start.
3. `textureLod` from an atlas and float packed bytes are standard GLSL 330 and ES 300 but untested under Gladio. Should the verify include a phone capture?

### Main agent's decisions (2026-11-06)

- Built on 0306's tree. 0306 keeps `uncratered_relief` (its landform term is added inside it), appends `Generation_Purpose.Planet_Landforms` after `Planet_Trees` (this item's two members follow it), and makes `OPTIONAL_PLANET_KEYS :: [2]string{"relief_shape", "landforms"}` with `missing_struct_key` taking `optional: []string`; this item makes it three. The natural share's `uncratered_relief` includes the landforms, so the look pass's cost per topsoil vertex of a loaded grid rises with 0306's relief; the implementer measures the mesh job with and without the look and reports it.
- The palette's warm greys ship, and old worlds take them too (cosmetic, `PLAN.md`, The rebuild: saves break as the rebuild needs).
- Old worlds keep the old look (the record's zero climate), as designed.
- The phone: `./build.sh check-android` in the verify; the look on Gladio is checked by the user at the next phone playtest, named in the landing's report.
