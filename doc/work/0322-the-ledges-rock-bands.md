# 0322: No more ledges

Status: implementing (2026-11-07)

The user (2026-11-07, a phone screenshot): "there is dirt striping that doesn't look good. Furthermore, there are weird half meter drop features snaking around the world. Feels like the height map has two frequencies or something. Get rid of the half meter features, they look artificial." Both come from the ledges of 0189 (`relief_shape.ledge_*` in `data/planets.sjson`: a 32 m wavelength, 700 mm amplitude, sharpness 128), which 0306 kept as detail. Each ledge is a step of about half a metre snaking along a contour. Since 0307 its riser is steep enough to take the rock look, so every slope is striped with brown bands (`tmp/shot_terrain_colours/state/mine-oh-belowed/screenshots/home_air120.png`).

## Goal

New worlds have no ledges: no snaking steps, and no rock bands across grassy slopes.

## Controls

None.

## Change

- The shipped planets' ledge amplitude goes to 0. The record keeps old worlds' ledges, as it keeps their other relief terms.
- If grass slopes still show rock bands without the ledges (from the detail octaves), the design names the cause and the fix (the rock look's steepness from a broader normal, or a minimum height of a steep face).
- The golden values of 0306's tests that pin the shipped relief are pinned again, and each re-pin is named.
- Docs: `doc/content.md` (Planets).

## Verify

- The checks and the suite.
- 0307's captures again (the home and the new spring from the ground, 40 m and 120 m): no steps along the contours, no rock bands across grass, rock on the range's faces.

## Specification (design, 2026-11-07)

Measured with probes on the real code (scratch copies under `tmp/0322/`; the edits below were applied there and the named tests run).

The striping has two causes. The ledges make the snaking steps and speckle the near ground with rock: at the 1 m level 1.7 percent of the gentle ground (under 25 degrees over 16 m) within 300 m of the home shows rock with them, none without (2 of 338,724 cells reach 40 degrees at 8 km, neither past the shader's floor). The far bands are the strata, not the ledges: a coarse level's surface cell takes its look from its ground corners, which lie up to a cell below the surface, under the 2 m of topsoil. Through `generate_field_grid` at 1000 mm, 50 to 52 percent of those corners are stone at level 2 (4 m) and 71 to 73 at level 3 (8 m), with or without the ledges, and only the topsoil takes the grass, so the far ground alternates grass and the stone tile in bands along its contours against the grid's layers. The fix gives a coarse grid a topsoil of two of its spacings, as the 1 m level has, which brings the stone share to 0.0 to 0.1 percent at every level at the home and the spring. Without the ledges the detail octaves leave no rock bands: at 2, 4 and 8 m cells over 2.4 km round the spring, slopes under 20 degrees (over 48 m) show visible rock on 0.11 to 0.17 percent of the cells, 20 to 30 degrees on 2.5 to 2.9 percent, and the range's faces over 40 degrees keep rock on 57 to 78 percent (64 to 85 with the ledges). No rock look change.

### Data

`data/planets.sjson`, `home`: `relief_shape.ledge_amplitude_millimetres = 0`; the other six keys stay (inert while the amplitude is 0). The comments, old to new:

- `(76 m with the landforms below)` to `(75 m with the landforms below)`.
- `its floor down to about 55 m under the surface` to `its floor down to about 54 m under the surface`.
- The springs: `stream runs about 400 m down and drops 65 m at 8 km (170 m at 16 km, 90 m at 4 km)` to `stream runs about 390 m down and drops 64 m at 8 km (170 m at 16 km, 24 m into a hollow at 4 km)`; `its stream runs about 220 m down and drops 30 m into the home's plain` to `its stream runs about 260 m down and drops 28 m into the home's plain`.
- `crater's floor lies 9.5, 8.7 and 9.1 m over the sea` to `crater's floor lies 10.2, 8.0 and 9.8 m over the sea`.
- `add up to 34 m at most (7.7 here)` to `add up to 34 m at most (7 here)`.
- The relief shape: drop `(1.4 m, under the mantle's 1.5 m)` from the ledges' sentence, and the last sentence `The terraces and the basins are off here: the landforms make the basins, and the terraces stepped only the old long octave.` becomes `Every term is off here: the landforms make the basins, the terraces stepped only the old long octave, and the ledges' half metre steps snaking along the contours looked artificial (0322). A world made with them keeps them through its record.`
- `The relief reaches 75.7 m below and 125.7 m above` to `The relief reaches 75 m below and 125 m above`.
- The climate: `lies at 13.3 degrees at 8 km` to `lies at 13.4 degrees at 8 km` (the moisture's 88 stays).

Old worlds: `planet_generation_record` copies `relief_shape`, the world file writes and reads it, `make_recorded_planet` takes the record's, and `resolve_world_planet` replaces a record only when the file has none (a file from before 0179, which already takes the data's landforms since 0306). So a world made with the ledges keeps them (the new test below). No layout change, no log line.

### Generation: the coarse levels' topsoil

`src/generation_planet.odin`:

- New, beside `planet_tint`: `generation_topsoil_depth :: proc(generation: Planet_Generation) -> i64`, `max(metres_to_position_units(TOPSOIL_DEPTH_METRES), 2 * generation.spacing)`. Its comment: the topsoil's depth below the local surface in the generation's spacing, two spacings of a coarse grid wider than a metre (0322), so a coarse surface cell's ground corners read topsoil as the finest grid's do instead of the stone under it, which striped the far ground along the contours.
- `planet_stratum :: proc(depth, distance, bedrock_radius, topsoil_depth: i64) -> Field_Material`: the topsoil case becomes `depth < topsoil_depth`.
- `planet_sample_at_relief` passes `generation_topsoil_depth(generation)`.
- The file's header comment: strata by depth, the topsoil at least two of the generation's spacings (one clause).

Chunks are generated at the world's spacing, at most 1000 mm, so their topsoil stays 2 m and their bytes, the saves and the simulation do not change; only `field_grid_generation`'s grids (levels 1 to 3, the planet preview's) do. At 333 mm level 1 keeps 2 m (666 mm cells).

`src/world_field_lod.odin`, `coarse_field_sample`: a coarse grid over loaded chunks (level 1 within the field's chunk radius, sometimes level 2) takes the chunk's material, which keeps the 2 m band: over the chunks round the home 346 of 3279 ground corners of the level 1 surface cells are stone, 1252 of 3077 at level 2. The material becomes the loaded one except `.Stone` where the generated sample is `.Topsoil`, which reads `.Topsoil` (then 1 and 0). Its comment: the material and tint are the chunk's, but stone where the coarse generation holds topsoil reads topsoil, the coarse topsoil band (0322). The cost: a pit dug into the stone shows bare topsoil rather than stone from 64 m out (its cut takes no grass); a placed stone stands where the generation is air and stays stone.

### Tests

Iterate with `./build.sh test quick` on the files below.

- `src/data_planet_test.odin`, `test_the_shipped_planets_file_loads`: the relief shape line asserts `ledge_amplitude_millimetres == 0 && terrace_rise_millimetres == 0 && basin_depth_metres == 0`, message `the shipped home's 0189 terms are off`; its comment: the landforms make the basins and the ledges went in 0322, so every 0189 term is off.
- `src/generation_planet_test.odin`, `test_the_ledges_make_a_slope_above_the_walkable_angle_within_a_chunk`: reads `pre_0306_test_home_at(8000)` (same home and ledge keys, so the same slopes), message `the home of before 0306 has ledges`, comment names the home of before the landforms since the shipped one has none. Pins the term, so it moves to a frozen planet.
- Same file, `test_the_shaped_home_generates_identical_bytes_twice`: loops `design_landform_test_planet(8000).radius_presets_metres` and builds `design_landform_test_planet(radius)` (0306's home, ledges on). With the shipped shape all off, the unshaped home is the same ground and every case failed.
- Same file, `test_the_rim_stands_above_the_surrounding_surface`: comment only, `on a ledge's face` to `on a steep face`.
- Same file, `test_strata_follow_the_depth_below_the_local_surface`: the four `planet_stratum` calls take `topsoil := metres_to_position_units(TOPSOIL_DEPTH_METRES)` as the fourth argument (the second asserts `planet_stratum(topsoil, ...) == .Stone`); add: `generation_topsoil_depth` of `make_planet_generation(DEFAULT_WORLD_SEED, make_test_planet(), spacing)` is that 2 m at 1000, 500 and 333 mm, and of `field_grid_generation(generation, 8)` for the 1000 mm generation `metres_to_position_units(16)`.
- Same file, two new helpers. `coarse_grid_stone_corners :: proc(grid: ^Field_Grid) -> (ground, stone: int)`: over the cells 0 to `FIELD_GRID_CELLS - 1` on each axis whose 8 corners (`field_grid_index({x + corner & 1, y + (corner >> 1) & 1, z + corner >> 2})`) are neither all ground (`density > 0`) nor all air, the count of ground corners and of those `.Stone`. `test_surface_node :: proc(position: World_Position, spacing_millimetres: int, level: i32) -> Field_Node`: the node of the level holding the position's sample (each coordinate floor divided by `field_node_samples(level)` with `floor_divide_i64`). New `test_the_coarse_levels_read_topsoil_at_the_surface`: `shipped_test_home_at(8000)` at 1000 and 333 mm, the surface under the home (83, 132) and the first spring (79, 151), levels 1 to `FIELD_LEVEL_COUNT - 1`, `generate_field_grid` of the node into a `new(Field_Grid, context.temp_allocator)`: ground at least 1000 and `stone * 100 <= ground`. Then over loaded chunks: `make_test_home_field(planet, 1000, 2)` (destroyed at the end), the node at levels 1 and 2 holding `field_home_site`'s sample, `gather_coarse_field_grid` (not nil) completed by `generate_field_grid`: the same bound. On main's generation it fails at 1000 mm levels 1 to 3 (12 to 73 percent of the corners stone) and at 333 mm level 2 at the spring (4.7) and level 3 (34 to 36); with the change at most 3 of 2025 to 5764 ground corners are stone. Over the loaded chunks it fails without the `coarse_field_sample` rule (346 of 3279 and 1252 of 3077). About 3 s with the loaded field: mark it slow if `build/test_times.tsv` agrees.
- `src/generation_planet_record_test.odin`, `test_a_world_file_before_the_relief_shape_keeps_the_plain_relief`: `planet := design_landform_test_planet(8000)`, assert `record.relief_shape.ledge_amplitude_millimetres > 0`, message `0306's home shapes its relief` (it passed unchanged, but on the shipped shape it no longer shows that stripping the key changes the ground).
- Same file, new `test_a_world_recorded_with_ledges_keeps_them`, before the crater test: `old := design_landform_test_planet(8000)` has ledges; `default_planet(shipped_test_planets())` has amplitude 0; encode a `World_File` (`format_version = SAVE_FORMAT_VERSION`, `settings = {day_length_seconds = 1200, planet_id = old.id}`, `planet_generation = planet_generation_record(old)`), parse it, `resolve_world_planet(..., shipped_test_planets(), true)`, `make_recorded_planet`; expect the recorded `relief_shape == old.relief_shape`; over `test_line_point(generation, index * 200)` for 100 indexes `surface_relief` of the recorded planet's generation equals the old one's, and differs from the recorded planet with amplitude 0 at more than 50 (all 100 do); the crater's `floor_height` equals the old one's.
- `src/field_trees_test.odin`, `test_a_tree_falls_into_a_hole_dug_under_it`: the three digs at 200, 800 and 1400 mm become one hole round the fell rule's probe. The test's tree (key -167, 1984, 186) stands 0.69 m higher without the ledges, its probe (half the trunk below the base) sits lower in its sample cell over stone, and the 600 mm sphere reached one of the cell's eight corners; with the ledges that corner held 72 percent of the weight, now 42. The shallow dig and its assertion stay; after them:

  ```odin
  // The hole: a sphere round the fell rule's probe, half the trunk below
  // its base, reaching every corner of the probe's sample cell, with every
  // material that has an item dug by the held shovel, since the probe of a
  // tree on thin topsoil reads the stone under it (0322).
  probe := test.trunk.bottom - World_Position(fixed_scale(test.trunk.up, test.trunk.length / 2))
  for &record in content.field.materials {
  	if record.item != NO_ITEM {
  		record.dug_with, record.tool_tier = .Shovel, 1
  	}
  }
  deep := shallow
  deep.centre = probe
  deep.brush.radius = 2 * sample_axis_to_position(1, state.field.spacing_millimetres)
  for _ in 0 ..< 4 {
  	append(&state.field.edits, Queued_Field_Edit{player = 0, edit = deep})
  	tick_field_test_simulation(state, content, {})
  }
  testing.expect(t, field_density_at(&state.field.world, state.field.spacing_millimetres, probe) <= 0, "the hole reaches the probe")
  ```

  then the existing felled and log assertions. `content` is the test's copy, so the table change stays in the test.

Nothing else pins the shipped relief: with the data change alone the suite failed exactly the four tests above (`test_a_tree_falls_into_a_hole_dug_under_it`, `test_the_ledges_make_a_slope_above_the_walkable_angle_within_a_chunk`, `test_the_shaped_home_generates_identical_bytes_twice`, `test_the_shipped_planets_file_loads`). 0306's goldens (`test_landform_relief_matches_the_design`, `test_the_relief_bounds_follow_the_record`, `test_landforms_problems`) and parity tests (`test_a_record_without_landforms_generates_as_before`, `test_an_old_world_file_keeps_its_relief`) read the frozen `design_landform_test_planet` and `pre_0306_test_home_at` and keep their values. The springs' thresholds of `test_the_default_springs_stream_runs_downhill` hold: the first at 8 km stands 84.9 m over the sea, runs 388 m and drops 64.0 m (at least 20, 300 and 50), at 16 km runs 170 m (100), the second at 8 km runs 262 m (150); before 85.6 m, 402, 65.4, 174 and 222.

### Docs

- `doc/content.md`, Planets: the bedrock's minimum `116 for the shipped home` becomes 115. The shipped home's paragraph: the detail sentence ends `the detail of octaves of 96, 32 and 12 m at 4, 2 and 1 m, the ledges (off since 0322), the terraces and the basins off`; `a relief bound of 75 m below the radius and 125 m above`; the census `its floor down to 54 m under it`, `the highest 120 m`, `slopes have a median of 6 degrees and a 99th percentile of 27` (the bands' percentages round the same: 27.3, 10.6, 26.0, 17.4, 11.3, 6.2, 1.27); the climate `13.4 degrees and 88 percent moisture at 8 km (lush green; 12.4 and 48 at 4 km, 21.0 and 46 at 16 km)`. The crater paragraph: `the floor lies 10.2, 8.0 and 9.8 m above the sea at 4, 8 and 16 km with the default seed (the home's ground less the depth, 0322)`. Trees: `That is about 113 trees in a circle 200 m across by the expectation; `test_the_tree_density_stays_within_its_bounds` measures 104 percent of it over the 13 of its 16 circles above the sea.` (the 151 and 79 were stale before this item; the test logs 117 against 113 now, 114 with the ledges).
- `doc/presentation.md`, the Level of detail bullet, after the sentence ending `which keeps the generation's coarse density (`coarse_field_sample`).`: its material is the chunk's, except stone where the coarse generation holds topsoil, which reads topsoil. A coarse grid's generation takes topsoil down to two of its spacings (`generation_topsoil_depth`, 0322), so a surface cell, whose ground corners lie up to a cell below the surface, reads topsoil as the finest level's does; with the 2 m band half the corners at 4 m and over two thirds at 8 m were stone, which striped the far ground along its contours.
- `doc/architecture.md`, World generation, after `Strata go by depth below the local surface: ...; bedrock from the planet's bedrock depth below the radius.`: one clause, a coarse level of detail reads topsoil down to two of its spacings ([presentation.md](presentation.md), Level of detail), chunks keep the 2 m.

### Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test quick src/generation_planet.odin src/world_field_lod.odin src/generation_planet_record_test.odin src/data_planet_test.odin src/field_trees_test.odin` while iterating, the whole suite once (`./build.sh test`; with every change above it passed in the scratch copy on dev-2026-11a), the slow mark for a new test `build/test_times.tsv` shows at 1 s or more, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- The captures (the main agent): near the home no snaking steps and no rock specks on the plain; at 120 m the far ground (levels 2 and 3) green without bands along the contours; rock on the range's faces.

### Hand-back check

The save line: no layout change; new worlds lose the ledges, old ones keep them (the new record test). The tests line: nothing touches the state directory. The rest does not apply.

### Answers

1. The amplitude goes to 0 and the record keeps old worlds' ledges, read in the code above; 0306's parity test reads the frozen pre-0306 home and still holds.
2. Re-pins: frozen planets for the tests that exist to show the ledges or the shape (they test the term, which old worlds still use); the shipped data test asserts the new data; the tree hole test is made independent of where the tree sits in its sample cell, since its pass hung on one corner of eight. No golden constant changes.
3. The rock bands do not survive on gentle ground (numbers above); the far bands are the coarse strata, fixed here.
4. The springs' thresholds hold (numbers above). The first spring at 4 km is the one that moves: its traced stream ends in a hollow after 24 m (2.5 m drop) where it ran 90 m (6.9 m); no test reads it and the tech demo's default radius is 8 km.

### Questions for the main agent

- The coarse topsoil is a second cause outside the item's Change list. It is in this specification because the Verify's "no rock bands across grass" fails without it at 4 and 8 m cells. Split it into an item of its own if you prefer; 0322's captures then still show the far bands. Its one cost is the `coarse_field_sample` rule: a pit dug into the stone reads bare topsoil from 64 m out.
- The tree hole test exposed a gameplay edge: the fell rule's probe lies 1.06 to 1.44 m under the base, so its sample cell reaches below the 2 m of topsoil, and a wooden shovel alone may not be able to fell a tree by digging under it. The test now digs every material. A follow-up item if you want the shovel to always suffice.

### Decisions (main agent, 2026-11-07)

1. The coarse topsoil stays in this item: the user's "dirt striping" is the far bands it fixes. A pit dug into stone reading bare topsoil from 64 m out is accepted.
2. The tree hole test digs every material with the shovel, as specified. Whether a shovel alone should fell a tree on 2 m of topsoil goes to `SUGGESTIONS.md` at the landing.
