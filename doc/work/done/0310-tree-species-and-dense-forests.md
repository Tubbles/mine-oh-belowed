# 0310: Tree species and dense forests

Status: landed (2026-11-07, 8186138)

Milestone: the world generation series 0306 to 0313, after 0306 and 0307. The user (2026-11-06): "More dense forests, varied tree types". Biomes (0308) are skipped for now (user, 2026-11-07), so the forest reads the climate (0307) and the relief (0306) directly.

## Goal

Forests you can get lost in: several species chosen by the climate and the height (a broadleaf, a birch like tree, the pine, a dead snag, bushes), sizes from saplings to giants, forest interiors at 2 to 3 m spacing with clearings, groves thinning into the plains. Today a single pine stands in groves on a 4 m lattice, at most 256 drawn within 128 m.

## Controls

None.

## Change

- Placement from a density read off the climate, the slope and the height, and a noise, in place of the grove circles (Horizon Zero Dawn's density maps, `work/world_generation_research.md`); the species by weights over temperature, moisture and height in data.
- One model per species from the sealed lab (CLAUDE.md, Model items), one species at a time, each its own lab item.
- The draw: instancing and a far form (an impostor or crossed quads) so a forest shows out to the fog within the Deck's budget, the cap and the distance from data; felling, the trunk's collision and the felled table follow the new keys.
- Old worlds keep their trees: the new placement is off in a world record without it.
- Docs: `doc/content.md` (Trees), `doc/presentation.md`; the log.

## Verify

- The checks and the suite.
- Captures of a forest interior, a forest edge and a forest from 120 m up; the frame cost on the couch with the forest in view; sent to the user.

## Specification (design, 2026-11-07)

Designed against the specifications of 0323 (`Planet_Landmarks` appended to `Generation_Purpose`), 0324 (`surface_column`, `CARVING_KINDS`), 0312 (`planet_lake_level_at`, `Planet_Generation.lakes`) and 0313 (`outdoor_light`, `apply_haze`, `set_model_open_sky`, `set_open_sky_uniforms`), all landing before 0310. The worktree is made from 0312's tip. The numbers below come from a placement prototype on 0323's relief and 0307's climate (`tmp/0310/proto`, maps in `tmp/0310/forest_sheet.png`). Its forest seed is `hash_combine(seed, L + 2)` with `L` the purpose count on `main` today, which is exactly `seeds[.Planet_Forest]` once 0323's `Planet_Landmarks` and this item's `Planet_Forest` are appended, so the shipped forest is the measured one.

### Measured on the shipped home at 8 km

- Forest share of the land (8 m grid, the 4 km square round the home): interior (at least 60% of the full density) 42.1%, edge (20 to 60%) 19.3%, open 38.6%, the 4 km preset 41.5/16.0/42.5, 16 km 39.2/17.9/42.8.
- Interior at 80.6 N 132 E (335 m south of the home): 1860 trees a hectare within 96 m, mean nearest neighbour 1.52 m, none nearer than the 0.9 m gap (without the gap 16% stood nearer than 0.9 m).
- Species over the 4 km square: pine 45.6%, broadleaf 37.5%, birch 7.5%, bush 7.2%, snag 2.1%, of 1.12 million trees.
- Start: the meadow keeps the home open to about 80 m (south and east the forest wall stands 70 to 100 m off, north it opens to scattered trees). Within 96 m: 992 trees, 173 of them a hand can fell for logs (4 km 1222/206, 16 km 327/24), and the nearest stands 24 to 43 m off.
- Trees within a radius of the home: 512 m 96 thousand, 1024 m 349 thousand. Round the interior point: 1024 m 318 thousand.
- Generation: 0.23 candidates a square metre, about 1.5 reliefs and 3 neighbour reads a candidate. A 128 m tile took 23 to 25 ms on average and 60 ms at worst under a load of about 10 on cores 8 to 15 (3201 trees at most), unloaded about 9 ms (the relief count times 0323's 1.27 µs a relief). The 1024 m disc (about 250 tiles) is 2.5 to 6 s of one core.

### Data

`data/planets.sjson`, the home's `trees` (the comment rewritten for the forest, the grove keys kept, read only by a planet without a forest and by old worlds):

- Shared keys: `tree_spacing_metres = 2`, `density_percent = 90`, `clearing_metres = 24`, `maximum_slope_percent = 70`. The grove keys unchanged (40, 50, 14).
- New optional object `forest` (`Planet_Forest`, off at zero, `cover_wavelength_metres` 0 is off), shipped `{cover_wavelength_metres = 520, clearing_wavelength_metres = 72, clearing_percent = 30, cover_threshold_percent = -8, edge_percent = 28, moisture_cover_percent = 30, scatter_percent = 3, meadow_metres = 56, minimum_gap_millimetres = 900, full_slope_percent = 40, stand_wavelength_metres = 80, stand_percent = 100, species_fade_celsius = 3, species_fade_moisture_percent = 10, species_fade_metres = 10, species_fade_cover_percent = 10}`. Bounds: cover wavelength 64 to 4096, clearing wavelength 16 to 1024, clearing 0 to 100, threshold -100 to 100, edge 1 to 100, moisture cover 0 to 100, scatter 0 to 100, meadow 0 to 512, gap 0 to the tree spacing in millimetres (the gap reads only the neighbour cubes), full slope 0 to `maximum_slope_percent`, stand wavelength 16 to 1024, stand 0 to 100, fades 1 to 50 °C, 1 to 100%, 1 to 1000 m, 1 to 100%. A forest needs the climate (`climate.temperature_wavelength_metres` above 0).
- Every species gains `temperature_celsius`, `moisture_percent`, `height_metres` (over the sea), `cover_percent`, `scale_percent` (each `[2]int`, least first) and `weight_percent`, required in the file, checked only while the forest is on: temperature -100 to 100, moisture 0 to 100, height -4000 to 4000, cover 0 to 100, scale 10 to `MAXIMUM_TREE_SCALE_PERCENT` (250, the `u8` of `Planet_Tree.scale_percent`), least at most most, weight 0 to 100, and some species above weight 0. `hand_felling_scale_percent` bound rises to `MAXIMUM_TREE_SCALE_PERCENT`.
- Shipped species (every stand-in names `pine_tree`, trunk 180 mm by 2500 mm):

| id | tint | yield | hand ≤ | hand ms | axe ms | T °C | M % | H m | cover % | weight | scale % |
|---|---|---|---|---|---|---|---|---|---|---|---|
| pine | 236,232,214 | log 4 | 100 | 10000 | 6000,4000,2500 | -6..16 | 15..100 | -20..256 | 0..100 | 100 | 45..210 |
| broadleaf | 196,236,160 | log 5 | 90 | 12000 | 7000,5000,3000 | 6..30 | 40..100 | -20..70 | 25..100 | 100 | 50..220 |
| birch | 250,250,236 | log 3 | 90 | 8000 | 5000,3500,2000 | -2..18 | 35..100 | -20..256 | 5..80 | 60 | 40..160 |
| snag | 150,132,112 | log 2 | 80 | 6000 | 4000,3000,1800 | -8..30 | 0..60 | -20..256 | 0..100 | 10 | 50..150 |
| bush | 176,220,150 | stick 2 | 45 | 1500 | 1000,800,600 | -4..32 | 10..100 | -20..256 | 0..70 | 70 | 20..45 |

Pine stays first, so an old world's single recorded species stays the pine. `data_planet.odin`: `Planet_Forest`, `Planet_Trees.forest`, the species fields, `forest_problem(forest, trees, climate)`, `tree_species_placement_problem(species, index)` (run from `trees_problem` while the forest is on). `trees_problem` returns early only when the grove share is 0 and the forest is off, and runs the grove keys' cases only when the grove share is above 0. `missing_trees_key_problem` takes `forest` as optional and checks `Planet_Forest`'s keys when present.

`data/game.sjson`, new required table `field_trees` (`Field_Trees_Config` in `Game_Config`, `field_trees_problem(config.field_trees, config.field_view)`): `near_metres = 96` (16 to 256), `near_limit = 1024` (1 to 8192), `far_metres = 1024` (near to the last level distance), `far_limit = 160000` (0 to 1000000, 0 draws no cards), `fade_metres = 12` (1 to near / 2), `far_fade_metres = 64` (1 to far / 4).

### Record and old worlds

- `Planet_Tree_Placement` gains `forest: Planet_Forest` and `species: [MAXIMUM_TREE_SPECIES]Planet_Tree_Species_Placement` (the six placement fields), filled by `planet_tree_placement`. `recorded_trees` copies the forest and sets each cloned species' placement fields from the record, so a data edit never moves a saved forest. Absent in a file written before 0310: zero, the forest off, the groves of the record.
- `recorded_forest_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string`: `world: the world file records no forest, its trees keep the groves` when the record holds trees, its forest is zero and the data's is not, logged by `resolve_world_planet` after 0312's waters note. A world recorded before 0197 takes the data's trees as today, forest included.
- `planet_generation_record_problem` runs the forest and species checks on a recorded forest (with the record's climate).
- `generation_seed.Generation_Purpose` gains `Planet_Forest` appended after `Planet_Landmarks` (comment: the forest of work item 0310).

### Placement (`generation_planet_trees.odin`)

- `planet_climate` splits into `planet_temperature(generation, on_sphere, height) -> i64` and `planet_moisture(generation, on_sphere) -> i64`, bit for bit, and `planet_climate` returns the two.
- `Planet_Tree_Term` gains `forest_on: bool`, `forest_seed`, the forest keys in position units and `NOISE_ONE` shares, and `species: [MAXIMUM_TREE_SPECIES]Planet_Tree_Species_Placement`, set by `make_planet_tree_term` (which now takes the forest seed). No trees when the forest is off and the grove share is 0, or with no species.
- `planet_tree_ground :: proc(generation: Planet_Generation, on_sphere: [3]i64) -> (relief: i64, ok: bool)`: `surface_column`, not ok on a carving kind, below the sea plus `PLANET_TREE_SEA_MARGIN_METRES`, or under a lake's level plus the margin (0312's rule). Both paths call it, so 0324's and 0312's tests on `planet_tree_from_candidate` cover the forest too.
- `forest_tree_from_candidate :: proc(generation: Planet_Generation, cell, on_sphere: [3]i64, hash: u64) -> (tree: Planet_Tree, ok: bool)`, cheapest first, `draw := hash_combine(hash, 1) % NOISE_ONE`:
  1. The clearing (chord to the home).
  2. `moisture := planet_moisture`, `cover := forest_cover(term, on_sphere, moisture) * forest_meadow_share(term, on_sphere) / NOISE_ONE`, `upper := max(cover, scatter) * density / NOISE_ONE`, out when `draw >= upper`.
  3. `forest_gap_keeps(term, radius, cell, on_sphere, hash)`: the neighbour cubes within the gap of the candidate (per axis -1 when nearer the low face than the gap, +1 likewise high), their candidates by `lattice_candidate`, out when one lies nearer than the gap with a lower `hash_combine(hash, 6)`.
  4. `planet_tree_ground`.
  5. `height := relief - sea`, `temperature := planet_temperature(generation, on_sphere, height)`, `weights, total := species_climate_weights(term, temperature, moisture, height, cover)`, `exact := upper * min(total / 100, NOISE_ONE) / NOISE_ONE`, out when `draw >= exact`.
  6. `forest_slope_percent(generation, on_sphere, up, relief)`: two probes 1 m along `frame_north_tangent(up)` and its `fixed_cross` with up, `isqrt(dn² + de²) * 100 / probe`, then `slope_share := NOISE_ONE - ramp(slope, full_slope, maximum_slope - full_slope)`, out when `draw >= exact * slope_share / NOISE_ONE`.
  7. `forest_stand_weights(term, on_sphere, &weights)`: each weight times `NOISE_ONE + stand_percent * gradient_noise(hash_combine(forest_seed, 16 + index), on_sphere, stand_wavelength) / 100`, over `NOISE_ONE`, and the species by `hash_combine(hash, 4) % total` walked over the weights.
  8. `scale_percent := forest_scale_percent(hash_combine(hash, 3), least, most)`: `t := ((hash & 0xFFFF) + (hash >> 16 & 0xFFFF)) / 2`, `least + (most - least) * t / 0xFFFF` (triangular). Yaw, shade, base and up as the grove path.
- `forest_cover`: `noise := ((100 - clearing) * gradient_noise(hash_combine(forest_seed, 0), p, cover_wavelength) + clearing * gradient_noise(hash_combine(forest_seed, 1), p, clearing_wavelength)) / 100 + moisture_cover * NOISE_ONE / 100 * (moisture - 500) / 500`, then `clamp((noise - threshold) * NOISE_ONE / edge, 0, NOISE_ONE)` with threshold and edge as `NOISE_ONE` shares. `forest_meadow_share`: 0 within `meadow_metres` of the home, smoothstep to `NOISE_ONE` at twice it. `species_climate_weights`: `weight * NOISE_ONE` times `species_tent` of the temperature (millicelsius), the moisture (permille), the height and the cover (`cover * 100` against the percent times `NOISE_ONE`), each fading to 0 over its fade outside the species' range, stopping at the first 0.
- `forest_density_at :: proc(generation: Planet_Generation, on_sphere: [3]i64) -> (density: i64, land: bool)`: the steps without the draw and the gap (`exact * slope_share`), for the tests.
- `planet_trees_in_box` and `planet_tree_at_key` take the forest path when `forest_on` (no groves read), the grove path otherwise.

### Felling (`field_trees.odin`)

- `Field_Tree_Species` gains `scales_with_size: bool` (the forest on) and `most_scale_percent: u8` (the species' most with the forest, `PLANET_TREE_MAXIMUM_SCALE_PERCENT` without).
- `field_tree_yield(species, tree)`: with `scales_with_size`, `max(1, (count * scale + 50) / 100)`, else the count. `field_felling_ticks`: with `scales_with_size`, the tick count times scale over 100 (at least 1). An old world's yields and times stay.
- `field_tree_widest_reach` and the draw's extent use each species' `most_scale_percent`. `FIELD_TREE_QUERY_MARGIN_MILLIMETRES` becomes `field_tree_query_margin(content) -> i64`: 1300 mm (a tick's step and the capsule) plus the widest trunk radius at its most scale. `render_field_camera.odin` takes it too.
- The felled table, `Felled_Tree_Record` and the trunk capsule are unchanged. `describe_machine_pine_tree` drops "for four logs" ("fells it for logs, more from a bigger tree").

### The draw

- `render_field_trees.odin` rewritten: tiles of `FIELD_TREE_TILE_METRES` 128 (`field_tree_tile_cells(spacing) = max(1, 128 m / spacing)` cubes an edge). `Field_Tree_Cache{tiles: map[Field_Tree_Tile]Field_Tree_Tile_Draw, pending: map[Field_Tree_Tile]struct{}, felled_seen: map[Tree_Key]struct{}}`. A tile holds its keys, its instances (`matrix[4, 4]f32`), the metres box of its bases widened by the extent, a VAO and VBO, its count and `dirty`.
- `tree_instance(tree, pitch_millimetres) -> matrix[4, 4]f32`: `tree_render_matrix(tree, pitch, 1)` with the bottom row `species, shade / 100, 0, 1` (tree.vs rebuilds `0, 0, 0, 1`, and raylib 6.0's `DrawMeshInstanced` sends the columns as `instanceTransform`, location 9 to 12).
- Workers (`world_field_streaming.odin`): `Field_Job_Kind.Trees`. `Field_Job` gains `tree_tile`, `tree_cells`, `tree_pitch_millimetres`, `Field_Job_Result` gains `tree_keys`, `tree_instances` (the shared allocator), `Field_Worker_Shared` gains `tree_jobs` and `trees_done`. `wait_for_field_job` takes a chunk job first, a tree job only when none waits. `run_field_job` runs `planet_trees_in_box(&shared.generation, the tile's box)` and packs. `submit_field_tree_tile` and `take_field_tree_tiles` serve the main thread. Stopping frees what is queued.
- `update_field_tree_cache(cache, streaming, generation, eyes, felled, config, pitch)` in `prepare_field_frame` and `stream_planet_preview`, before any viewport draws: take finished tiles (drop the unwanted), upload at most `FIELD_TREE_UPLOADS_PER_FRAME` 4, submit the wanted tiles (`field_tree_tiles_around(generation, eyes, far_metres)`: of the tile range round each eye's projection, those straddling the sphere of the radius whose box lies within the distance, nearest first) while under `FIELD_TREE_TILES_PENDING_LIMIT` 8 pending, evict beyond far plus two tiles (VAO and VBO freed here), apply new felled keys (`felled_seen`; the tile drops the key and uploads again; a shorter felled table rebuilds every tile). `field_tree_cache_settled`: every wanted tile uploaded.
- Near: `select_near_trees(cache, camera, frustum, extent, felled, config)`: the standing instances within `near_metres` in the frustum, the nearest `near_limit`, `near_distance` the first one cut, else `near_metres`. Drawn per tree machine with `rl.DrawMeshInstanced` of the model's lit body and the tree material (`card_on` 0).
- Far cards, baked at `replace_machine_models` for every machine of kind tree (`render_tree_cards.odin`, CPU, pure): `tree_card_size(mesh)` (half width the largest |x| or |z|, top the largest y, crown at `TREE_CARD_CROWN_PERMILLE` 550 of the top); `bake_tree_card(mesh, size, view, cell)` rasterises the triangles orthographically with depth into a 128 texel cell inside a 2 texel margin: view 0 along forward, view 1 along right, view 2 from above; the vertex colour, alpha 255 where covered. `fill_empty_card_texels` (2 passes, alpha stays 0). The atlas is 512 wide (4 cells, the fourth empty) by 128 times the row count rounded up to a power of two (rows at most 16). `tree_card_mip_chain` goes to 1 by 1, colour weighed by alpha, each cell's alpha scaled (8 bisection steps) so its share at or above 128 stays level 0's. Up through `load_rgba_texture` with `mipmaps = levels`, trilinear.
- `Model_Renderer.trees: Tree_Draw`: the tree material (shader `data/shaders/tree.vs` and `tree.fs`, the card atlas as albedo), its uniform locations, the open sky, point and spot locations, `cards` by `Machine_Id` (row or -1, size), the card VBO (18 vertices: three quads of `(card, u, v)`). `use_tree_shader` runs in `init_model_renderer`. `set_model_point_lights`, `set_model_spot_light`, `set_model_open_sky` also set the tree shader when it loaded.
- Far draw: `select_far_tiles(cache, camera, frustum, config)` the tiles within `far_metres` in the frustum, nearest first, while the running count stays within `far_limit`, `far_distance` the first tile left out, else `far_metres`. After `rlgl.DrawRenderBatchActive`, the tree shader with `mvp` set as rmodels.c's instanced path sets it (the rlgl transform times the modelview times the projection) and the atlas bound, one `rlgl.DrawVertexArrayInstanced(0, 18, count)` a tile with its VAO (the card VBO at location 0, the instances at 9 to 12, divisor 1), `card_on` 1.
- Shaders: tree.vs builds the near vertex from the model, or the card vertex from `species_card[species]` (half width, top, crown, row) and `card_rows`, puts every vertex of an instance outside clip space when its base lies nearer than `near_distance - fade_metres`, farther than `far_distance`, or its species has no card (row -1), and passes the fades. tree.fs: the card texel, discard below alpha 0.5 (read before any discard). The near model kept where an interleaved gradient noise on `gl_FragCoord` exceeds the fade over `[near_distance - fade, near_distance]` and the card where it does not (complementary, so no tree doubles or vanishes), the cards fading out the same way over the last `far_fade_metres`. The card normal runs from the crown centre to the fragment. `base` = albedo times `species_tint[species]` times the shade times `colDiffuse` (the daylight tint), then model.fs's main lines with `outdoor_on` 1. `outdoor_light`, `apply_haze`, `point_light_sum`, `spot_light` and their uniforms copied verbatim from model.fs, arrays `[8u]`, every integer literal `u`.
- `draw_field_trees(scene, camera)` keeps its call site: uniforms, near, far. `FIELD_TREE_DRAW_*`, the grow-in and `FIELD_TREE_REGION*` go.
- Estimate (not measured, the game binary was not run): about 100 to 130 thousand cards in view at the home (349 thousand within 1024 m, a quarter to a third in the frustum), 18 vertices each, 60 to 90 tile draws, plus up to 1024 near models (the 100 triangle pine, up to 600 with lab models): about 1 to 1.5 ms of the Deck's 25 ms, 0.3 to 0.5 ms of CPU a viewport. Memory 64 B a tree on the GPU and about 76 B on the CPU: 22 and 27 MB for 350 thousand.

### Tests

- `generation_planet_trees_test.odin`: `grove_test_planet(radius)` (the shipped home, forest off, spacing 4, density 80). `test_the_tree_density_stays_within_its_bounds` and `test_trees_stand_in_groves_not_on_a_grid` move to it, the other tests run on both. New: `test_the_forest_share_of_the_land_holds` (slow, 16 m grid over the 4 km square at 8 km: interior 35 to 50%, open 30 to 48%); `test_the_forest_interior_is_dense` (within 30 m of 80.6 N 132 E: 1300 to 2400 a hectare); `test_no_two_trees_stand_closer_than_the_gap` (a 64 m box there, every pair at least 900 mm); `test_overlapping_boxes_agree_on_their_trees` (two boxes offset by 7 m share their overlap's keys, and every key regenerates alone); `test_the_meadow_round_the_home_is_open` (each preset: within 56 m at most 100 trees, within 96 m at least 200 and at least 10 a hand fells for logs); `test_species_follow_the_climate` (`species_climate_weights` on the shipped table: 25 °C moist at 0 m has broadleaf and no pine, -5 °C only pine and snag, 5% moisture only snag, 100 m no broadleaf); `test_the_shipped_forest_mixes_species` (slow, 1 km square: every species at least 0.5%, pine and broadleaf together at least 60%); `test_the_forest_scale_is_triangular` (10000 hashes: in range, mean within 2% of the middle); `test_tree_sizes_span_saplings_to_giants` (the 64 m box: per species some tree below its range's lower third and some above its upper third); `test_the_forest_reads_the_same_ground_rules` (a sea point: `planet_tree_ground` and the forest path both refuse); `test_a_world_without_a_forest_keeps_its_groves`; `test_the_tree_query_cost_is_logged` adds the interior.
- `data_planet_test.odin`: `test_the_forest_keys_are_bounded` (each key past its bound names it, as do no climate and a gap above the spacing), `test_species_placement_is_bounded`, `test_the_forest_is_optional_in_the_file`.
- `generation_planet_record_test.odin`: `test_the_record_keeps_the_forest`, `test_an_old_record_keeps_the_groves_and_logs`. `test_a_world_file_without_trees_takes_the_datas` expects `species[index % len]`.
- `field_trees_test.odin`: `test_the_yield_and_time_scale_with_the_tree` (broadleaf 220 yields 11, 50 yields 3, the ticks likewise, an old world unchanged), `test_the_query_margin_covers_the_widest_trunk`, `test_a_bush_yields_sticks`.
- `render_field_trees_test.odin`: `test_tree_instance_packs_species_and_shade`, `test_tree_tiles_cover_the_far_distance`, `test_the_near_selection_caps_and_pulls_in`, `test_the_far_tiles_stop_at_the_card_limit`, `test_a_felled_tree_rebuilds_its_tile`, `test_a_worker_tile_equals_the_simulations_trees` (`run_field_job` on a `Field_Worker_Shared` made as `start_field_streaming` makes it, no threads). The grow-in test goes.
- `render_tree_cards_test.odin`: `test_a_card_bakes_the_models_outline` (a box mesh: covered share within 2% of its projection), `test_the_card_mips_keep_the_coverage` (within 10% down to 8 texel cells, the chain's length as raylib reads it), `test_the_shipped_tree_models_bake`.
- `shader_source_test.odin`: tree.fs joins `test_the_lit_shaders_share_the_open_sky` and `test_the_point_light_shaders_share_the_clip_and_the_sum`, and new `test_the_tree_shader_reads_the_instance` (`in mat4 instanceTransform;`, the species arrays sized by `MAXIMUM_TREE_SPECIES`).
- `data_load` tests: `test_the_field_trees_config_is_bounded`.

### Docs

`doc/content.md` (Trees: the forest, the species keys, the yields, the stand-ins), `doc/presentation.md` (The field session, the trees: tiles, near and far, the cards, `field_trees`), `doc/architecture.md` (World generation. Threads and chunk streaming: the workers also generate tree tiles, after the chunks. Save format: the record's forest), `doc/code_map.md` (`render_tree_cards.odin`, the shaders), the comments of `data/planets.sjson` and `data/game.sjson`. The log at the landing (the shipped forest's numbers above, the old worlds' groves, the yields).

### Hand-back check

Tile buffers are freed and replaced in `update_field_tree_cache` before the viewports draw, the atlas at the machine models' reload. Every new key is range checked. The record's fields read absent as zero and log one line. The tree jobs wait behind the chunk jobs and stay at most 8 pending, so the chunks' streaming keeps its share. The near and far draws are capped by `near_limit` and `far_limit`.

### Captures (the main agent, after landing)

On the shipped home at 8 km: the interior at 80.6 N 132 E at noon, the edge from the home looking south (the wall 70 to 100 m off), from 120 m over the home looking south, the meadow, the wall and the far forest to the fog, and the frame cost on the couch with the interior in view.

### Lab items (one species each, after 0310)

Proposed: pine (a remake of today's 100 triangle model), broadleaf, birch, dead snag, bush. Each adds its machine record and model, switches its species' `machine` and sets its trunk numbers. At most 600 triangles (the near budget is 1024 instances), no emissive material. The cards bake from the model by themselves.

### Questions to the main agent

1. The lab items' names and order above, and the 600 triangle cap.
2. Yield and time scale with size only in a forest world, so old worlds keep their four logs. Or everywhere?
3. The workers generate tree tiles: doc/architecture.md's rule that workers only generate and mesh chunks changes.
4. The phone's draw: `field_trees` is one table for all platforms. A phone or Deck may need `far_metres` 512 and `far_limit` 40000. Is there a per platform default to use, or a setting?
5. Bushes yield 2 sticks.
6. The simulation's tree query costs about 0.3 ms a player a tick in an interior (the box of 9.5 m half at 2 m spacing). No memo is designed, since a memo would alias through the simulation's copies.
7. The 56 m meadow round the home.

### Decisions (main agent, 2026-11-07)

1. The five lab items are written, 0329 to 0333, broadleaf first (it has no tree shape of its own today), then birch, bush, snag and the pine remade; 600 triangles each.
2. Size scales the yield and the felling time in forest worlds only, as specified; an old world's groves stay as they are.
3. The workers generate tree tiles when no chunk job waits: approved; `doc/architecture.md` (Threads and chunk streaming) says so.
4. No per platform default exists in the data. `field_trees` holds one row for desktop and one for Android (`far_metres` 512, `far_limit` 40000), chosen by the build target; the Deck takes desktop's until the user's playtest says otherwise.
5. Bushes yield 2 sticks: accepted.
6. The tree query's 0.3 ms per player per tick in an interior: accepted; `test_report_the_waters_cost`'s pattern reports it optimised, and a memo is a follow-up if the phone shows it.
7. The 56 m meadow round the home: accepted.
8. The implementation starts from 0312's snapshot (stream 0323, 0324, 0312, 0310).
