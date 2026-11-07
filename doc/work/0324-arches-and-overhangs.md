# 0324: Arches, overhangs and caves in the generation

Status: verified (2026-11-07)

The user (2026-11-07): "Minecraft is really good at this, with gorges, cliffs, and even arcs, and other exciting features." An arch, a natural bridge, an overhang or a cave mouth needs ground above air. The field holds that, since players dig caves, but the generation is a height map (`planet_sample_at_relief`: the density is the depth below one surface height), so it can make none of them. 0323 makes the height map landforms. This item adds a three-dimensional density term.

## Goal

Rare arches and natural bridges, overhanging cliffs and cave mouths that open into the hills, generated deterministically, which a player can walk under and into.

## Controls

None.

## Change

- A three-dimensional term in the sample's density, after Minecraft's noise caves (cheese and spaghetti) and its overhangs, bounded to a shell near the surface and to where its features are wanted (rock faces, ranges, gorge walls). Integer and fixed point, as the relief is.
- What reads the surface as a height map follows it. The design lists each reader and its answer:
  - the sky light march (`field_relief_top`);
  - the ground look's natural share (0307);
  - the trees' placement;
  - the springs;
  - the dry home search and the arrival's crater;
  - `planet_sample_shortcut`'s bounds;
  - the relief map mode;
  - the level of detail.
- Old worlds keep their ground through the record.
- The cost per sample and per view is measured, against 0314's work.
- Docs: `doc/content.md` (Planets), `doc/architecture.md` (World generation).

## Verify

- The checks and the suite, with the bound, determinism and old world parity tests.
- Captures under an arch, beside an overhang and into a cave mouth, sent to the user.

## Specification (design, 2026-11-07)

Builds on 0323 and is designed against its specification (the site lattice, `Landmark_Site`, `landmark_relief`, `Landform_Reading`, `test_landmark_sites`, `design_landmark_test_planet`), and on 0322's (6da8927: `planet_stratum` takes the topsoil depth, `generation_topsoil_depth`, `test_surface_node`). Prototype, sources and figures: `tmp/0323/` (`research.md`); the weathered kinds, two sites each from two sides, `tmp/0323/carved_kinds_weathered.png`; vertical slices of the same sites `tmp/0323/carve_slices_weathered.png` (revision of 2026-11-07: the first shapes read as stamped primitives, `landmarks_from_the_ground.png`, the bottom three).

### What is carved, and what waits

Three more site kinds of 0323's lattice, each a height map raise like a butte with an analytic carve under it, after Dey, Doig and Gatzidis's procedural arches (SIGGRAPH 2017). No part is a primitive: two gradient noises of the site's own scale, read once per carving column, roughen the raise, the outline and every semi axis of the carve, the walls lean, and the tops are crowned and uneven, so no two sites and no two sides of one site match.

- Arch: a fin 30 to 48 m long and 18 to 28 m high, stretched 2.6 to 3.4 times along its axis, its top falling a quarter towards its ends and flanks and lumpy, its walls battered. The opening through it across is an ellipse about 36 percent of the half length wide and 62 percent of the height high, each semi axis moved by the shape noise, its centre shifted along the fin by the relief noise (so it twists through the fin), narrowing by up to 30 percent towards its crown (a slightly pointed, uneven vault).
- Grotto: a rocky knoll 18 to 28 m in radius and 12 to 20 m high, broad topped and steep sided, rougher than the arch, falling as a face on the side the tunnel leaves by. Inside a chamber (about 42 percent of the radius, 56 percent of the height) and a tunnel out through the face (about 12 percent of the radius half wide, 1.3 times that high), their semi axes moved by the shape noise and the tunnel meandering by up to 70 percent of its half width: a cave mouth in a rock face.
- Mushroom rock: a domed, uneven cap 7 to 12 m in radius and 9 to 16 m high on a stem of about 45 percent of the radius that narrows by up to 35 percent towards its foot (a pedestal rock); the cap's underside lies level, the cap about 22 percent of the height thick at its rim and up to 80 percent thicker towards the stem, and where the cap would thin under half a metre or close the gap under it to less than 1 m the column is carved whole, which leaves its rim ragged.

10 percent of the cubes each, the 30 percent 0323 leaves empty. Within 3 km of the home at 8 km stand 16 arches, 13 grottos and 8 mushroom rocks (10, 7 and 13 at 4 km, 13, 13 and 7 at 16 km); 1.3 carving sites a square kilometre, 0.09 percent of the columns. Picks at 8 km: arches of 28 m at 85.293 N 146.562 E (379 m from the home) and of 25 m at 79.140 N 139.007 E (558 m), grottos at 76.792 N 160.417 E (1086 m) and 88.242 N 18.486 W (1197 m), mushroom rocks at 80.524 N 106.372 E (610 m) and 85.620 N 178.090 W (747 m).

Noise caves and overhangs along the walls are 0327.

### Data

`Planet_Landmarks` gains, after 0323's keys: `arch_percent`, `grotto_percent`, `mushroom_percent` (each 0 to 100, the six shares together at most 100; shipped 10, 10, 10), and the pairs `arch_length_metres` (`[30, 48]`), `arch_metres` (`[18, 28]`), `grotto_radius_metres` (`[18, 28]`), `grotto_metres` (`[12, 20]`), `mushroom_radius_metres` (`[7, 12]`), `mushroom_metres` (`[9, 16]`), each 1 to `MAXIMUM_LANDMARK_METRES`, least at most most, checked only while the kind's share is above 0. `landmark_widest_site_metres` adds the kinds that are on: an arch's most length over 2, a grotto's and a mushroom rock's most radius times `GROTTO_STRETCH_PERCENT` and `MUSHROOM_STRETCH_PERCENT` over 100, rounded up (24, 33 and 14 shipped; the widest stays the butte's 88). `data/planets.sjson`: the keys after the sinkholes', with one comment: arches (a fin with an opening through it, its length and height), grottos (a dome with a chamber and a tunnel, its radius and height), mushroom rocks (a cap on a stem, its radius and height), carved under their raise (0324).

### Generation (`generation_planet_landmarks.odin`)

- `Landmark_Kind` gains `Arch, Grotto, Mushroom` after `Sinkhole`. `Landmark_Profile` gains `crown` (per mille of the height the top falls from the centre to the cap's edge, with the square of the way; 0323's entries gain a fourth value 0, so their shapes stay bit for bit); `LANDMARK_PROFILES` gains `.Arch = {400, 720, 150, 250}`, `.Grotto = {420, 900, 50, 150}`, `.Mushroom = {650, 780, 120, 200}`. `landmark_site_shape`: to the cap, `NOISE_ONE` when `cap` is 0, else `w := u * NOISE_ONE / cap` and `NOISE_ONE - crown * w / NOISE_ONE * w / NOISE_ONE`; the wall `talus + (NOISE_ONE - crown - talus) * (NOISE_ONE - fade) / NOISE_ONE` (all scaled to NOISE_ONE as 0323's). `CARVING_KINDS :: bit_set[Landmark_Kind]{.Arch, .Grotto, .Mushroom}`. All three are raises in `landmark_site_relief`.
- Constants: `ARCH_LEAST_STRETCH_PERCENT :: 260`, `ARCH_MOST_STRETCH_PERCENT :: 340`, `GROTTO_STRETCH_PERCENT :: 115`, `MUSHROOM_STRETCH_PERCENT :: 115`; per mille: `ARCH_OPENING_WIDTH_PERMILLE :: 360` (of the half length), `ARCH_OPENING_HEIGHT_PERMILLE :: 620` (of the height), `GROTTO_TUNNEL_PERMILLE :: 120` (its half width, of the radius), `GROTTO_TUNNEL_HEIGHT_PERMILLE :: 1300` (of the half width), `GROTTO_CHAMBER_PERMILLE :: 420` (of the radius), `GROTTO_CHAMBER_HEIGHT_PERMILLE :: 560` (of the height), `MUSHROOM_STEM_PERMILLE :: 450` (of the radius), `MUSHROOM_CAP_PERMILLE :: 220` (the cap's thickness at its rim, of the height). The weathering: `CARVE_RELIEF_ROUGH_PERCENT :: 18`, `CARVE_OUTLINE_ROUGH_PERCENT :: 12`, `CARVE_RELIEF_WAVE_PERCENT :: 50` (the relief noise's wavelength, of the radius, at least `CARVE_RELIEF_LEAST_WAVE_METRES :: 4`), `CARVE_SHAPE_WAVE_PERCENT :: 35` (the shape noise's, at least `CARVE_SHAPE_LEAST_WAVE_METRES :: 2`), `GROTTO_FACE_PERMILLE :: 600`, `GROTTO_KNOLL_ROUGH_PERCENT :: 15`, `ARCH_OPENING_ROUGH_PERCENT :: 22`, `ARCH_SKEW_PERCENT :: 18`, `ARCH_TAPER_PERMILLE :: 300`, `GROTTO_ROUGH_PERCENT :: 25`, `GROTTO_MEANDER_PERMILLE :: 700`, `MUSHROOM_STEM_ROUGH_PERCENT :: 20`, `MUSHROOM_FOOT_PERMILLE :: 350`, `MUSHROOM_THICKEN_PERCENT :: 80`, `MUSHROOM_UNDER_ROUGH_PERCENT :: 25`, `MUSHROOM_LEAST_CAP :: 2048` (position units, half a metre), `MUSHROOM_CLEARANCE_METRES :: 1`.
- `carve_rough :: proc(value, percent, noise: i64) -> i64`: `value * (100 * NOISE_ONE + percent * noise) / (100 * NOISE_ONE)`.
- `landmark_site_candidate`: the cumulative order spire, butte, sinkhole, arch, grotto, mushroom. An arch: `stretch_percent := ARCH_LEAST_STRETCH_PERCENT + i64((draw >> 32) % u64(ARCH_MOST_STRETCH_PERCENT - ARCH_LEAST_STRETCH_PERCENT + 1))`, `radius := hash_metres_range(draw >> 8, arch_length_metres) / 2 * 100 / stretch_percent` (the fin's half thickness, so its outer reach is half its length). A grotto and a mushroom rock as 0323's kinds, with their stretch constants. The height from `hash_combine(hash, 3)` and the kind's pair, as 0323's.
- `landmark_site_u` becomes `landmark_site_reading :: proc(generation: Planet_Generation, site: Landmark_Site, point: [3]i64) -> (u, along, across: i64, inside: bool)`: 0323's values, plus `across := i64(integer_square_root(u64(across_squared)))` inside the outer reach (one root more in a site's columns only).
- `Landmark_Carve :: struct {site: Landmark_Site, ground, raise, u, along, across, relief_noise, shape_noise: i64}`: the carving site the column lies in (kind `None` elsewhere), the column's ground (the relief before the site: `min(relief + raise, relief_highest)` of `landmark_relief`'s step 6, with the mesas, without the site, a gorge or a sinkhole), the site's raise there, the column's place in the site (`u` the weathered one below) and its two noises.
- `landmark_site_relief` returns `(raise, cut: i64, carve: Landmark_Carve)`. For a carving kind inside its reading, in this order: `relief_noise := gradient_noise(hash_combine(landmark_seed, 9), point, max(site.radius * CARVE_RELIEF_WAVE_PERCENT / 100, metres(CARVE_RELIEF_LEAST_WAVE_METRES)))`, `shape_noise := gradient_noise(hash_combine(landmark_seed, 10), point, max(site.radius * CARVE_SHAPE_WAVE_PERCENT / 100, metres(CARVE_SHAPE_LEAST_WAVE_METRES)))`; `u = carve_rough(u, CARVE_OUTLINE_ROUGH_PERCENT, relief_noise)`; a grotto with `along < 0` (its mouth's side) `u = u * (1000 * NOISE_ONE - GROTTO_FACE_PERMILLE * along * NOISE_ONE / landmark_site_outer(site)) / (1000 * NOISE_ONE)`; nothing (no raise, no carve) when now `u >= NOISE_ONE`; `raise := carve_rough(site.height * landmark_site_shape(kind, u) / NOISE_ONE, CARVE_RELIEF_ROUGH_PERCENT, relief_noise)`, a grotto's then `carve_rough(raise, GROTTO_KNOLL_ROUGH_PERCENT, shape_noise)`; the carve holds the site, `raise`, `u`, `along`, `across` and the two noises. `landmark_relief` returns `(relief: i64, carve: Landmark_Carve)` and sets `carve.ground`. The relief of 0323's kinds is 0323's.
- `ellipse_distance :: proc(x, semi_x, y, semi_y: i64) -> i64`: `q := x * x / semi_x * NOISE_ONE / semi_x + y * y / semi_y * NOISE_ONE / semi_y`, `min(semi_x, semi_y) * (i64(integer_square_root(u64(q * NOISE_ONE))) - NOISE_ONE) / NOISE_ONE`: the signed distance from the ellipse, approximated, negative inside.
- `landmark_carve_distance :: proc(carve: Landmark_Carve, height: i64) -> i64`: the signed distance at `height` over the carve's ground, negative in the carved air; `max(inside, -height)`, so nothing under the ground is carved. `inside` is `1 << 40` for a kind outside `CARVING_KINDS`; otherwise, with `site := carve.site`:
  - Arch: `a := carve_rough(landmark_site_outer(site) * ARCH_OPENING_WIDTH_PERMILLE / 1000, ARCH_OPENING_ROUGH_PERCENT, carve.shape_noise)`, `b := carve_rough(site.height * ARCH_OPENING_HEIGHT_PERMILLE / 1000, ARCH_OPENING_ROUGH_PERCENT * 2 / 3, carve.shape_noise)`, `along := carve.along - a * ARCH_SKEW_PERCENT / 100 * carve.relief_noise / NOISE_ONE`, `t := clamp(height * NOISE_ONE / b, 0, NOISE_ONE)`, `along = along * NOISE_ONE / (NOISE_ONE - ARCH_TAPER_PERMILLE * t / 1000)`, `ellipse_distance(along, a, height, b)`.
  - Grotto: `width := carve_rough(site.radius * GROTTO_TUNNEL_PERMILLE / 1000, GROTTO_ROUGH_PERCENT, carve.shape_noise)`, `across := carve.across - width * GROTTO_MEANDER_PERMILLE / 1000 * carve.relief_noise / NOISE_ONE`, `tunnel := max(ellipse_distance(across, width, height, width * GROTTO_TUNNEL_HEIGHT_PERMILLE / 1000), carve.along)`, `flat := i64(integer_square_root(u64(carve.along * carve.along + carve.across * carve.across)))`, `chamber := ellipse_distance(flat, carve_rough(site.radius * GROTTO_CHAMBER_PERMILLE / 1000, GROTTO_ROUGH_PERCENT, carve.shape_noise), height, carve_rough(site.height * GROTTO_CHAMBER_HEIGHT_PERMILLE / 1000, GROTTO_ROUGH_PERCENT, carve.shape_noise))`, `min(tunnel, chamber)`.
  - Mushroom rock: `nominal := site.height - site.height * MUSHROOM_CAP_PERMILLE / 1000`, `t := clamp(height * NOISE_ONE / max(nominal, 1), 0, NOISE_ONE)`, `stem := carve_rough(site.radius * MUSHROOM_STEM_PERMILLE / 1000, MUSHROOM_STEM_ROUGH_PERCENT, carve.shape_noise) * (1000 * NOISE_ONE - MUSHROOM_FOOT_PERMILLE * (NOISE_ONE - t)) / (1000 * NOISE_ONE)`; `thickness := (site.height * MUSHROOM_CAP_PERMILLE / 1000) * (100 * NOISE_ONE + MUSHROOM_THICKEN_PERCENT * (NOISE_ONE - min(carve.u, NOISE_ONE)) + MUSHROOM_UNDER_ROUGH_PERCENT * carve.shape_noise) / (100 * NOISE_ONE)`, `under := carve_rough(site.height * (1000 - LANDMARK_PROFILES[.Mushroom].crown) / 1000, CARVE_RELIEF_ROUGH_PERCENT, carve.relief_noise) - thickness` (level under the crowned top's rim height); when `under < metres(MUSHROOM_CLEARANCE_METRES) || carve.raise - under < MUSHROOM_LEAST_CAP`, `under = carve.raise + metres(1)` (the column is carved whole: the ragged rim, no skirt); `max(stem - carve.u * site.radius / NOISE_ONE, height - under)`.

  Each kind's carved air in a column is one span from the ground up, which the roof test relies on: the arch's taper and the mushroom's foot only narrow the air upward, the grotto's two ellipses share the ground. The prototype found no other over 69,185 random columns of the 37 carving sites within 3 km of the home.

### The column (`generation_planet.odin`)

- `Surface_Column :: struct {relief: i64, carve: Landmark_Carve}`.
- `uncratered_column :: proc(generation: Planet_Generation, point: [3]i64) -> Surface_Column`: 0323's `uncratered_relief` body with the carve; `uncratered_relief` returns its relief.
- `surface_column :: proc(generation: Planet_Generation, point: [3]i64) -> Surface_Column`: the uncratered column, the relief through `crater_relief` when baked; `surface_relief` returns its relief. No carving site reaches the crater: a site keeps `calm_metres` plus its reach from the home and the calm holds the crater's reach (`landforms_planet_problem`).
- `column_depth :: proc(column: Surface_Column, height: i64) -> i64`: `column.relief - height` (height over the radius), with a carving kind `min` that and `landmark_carve_distance(column.carve, height - column.carve.ground)`.
- `column_roofed :: proc(column: Surface_Column, spacing: i64) -> bool`: a carving kind, `roof := column.relief - column.carve.ground - spacing`, `roof > 0 && landmark_carve_distance(column.carve, roof) > 0`: ground at least a spacing thick stands over the carved span.
- `column_shades :: proc(column: Surface_Column, height, spacing: i64) -> bool`: a carving kind, `landmark_carve_distance(column.carve, height - column.carve.ground) <= 0` and `column_roofed`. The caller checks the sample is air.
- `planet_sample_at_column :: proc(generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64, column: Surface_Column) -> Field_Sample`: `height := distance - generation.radius`, the density from `column_depth(column, height)`; the material from the height map's depth, `column.relief - height`, through `planet_stratum` (with `generation_topsoil_depth(generation)`) and `planet_outcrop_material`, so a carved face shows the stone it was cut from and only the top keeps its topsoil; the tint as before. With the zero carve it is today's `planet_sample_at_relief` bit for bit, which becomes `planet_sample_at_column(..., Surface_Column{relief = relief})` (the crater's baked sample).
- `planet_sample_shaded :: proc(generation: Planet_Generation, position: World_Position) -> (sample: Field_Sample, shaded: bool)`: the shortcut, then `surface_column` and `planet_sample_at_column`; `shaded` when the sample is air and `column_shades(column, distance - generation.radius, generation.spacing)`. `planet_sample` returns its sample.
- `generate_field_chunk`: `column := surface_column(generation, on_sphere)`, the sample from `planet_sample_at_column`, the overlay given `column.relief`; a local `shaded: Field_Sample_Bits` takes each air sample `column_shades` holds. After `light_generated_field_chunk(chunk)`, every shaded sample's `sky_light` is 0, and `chunk.generated_shade = field_sample_bits_any(&shaded)` (assigned every time). Its comment: the light is full sky in every air sample but carved air under a roof (0324).

### Light

- `Field_Chunk.generated_shade: bool` (`world_field.odin`, comment: the generation left air under a carved roof without sky (0324), so its arrival seeds the fill into it from the chunk's lit air; never saved or hashed, false on a decoded chunk, whose saved light holds the fill).
- `world_field_light.odin`: `seed_field_chunk_shade :: proc(world: ^Field_World, chunk: ^Field_Chunk)`: in index order, each air sample at `FIELD_LIGHT_FULL` sky with a face neighbour inside the chunk that is air below `FIELD_LIGHT_FULL` gets `push_field_light_addition(world, .Sky, field_chunk_sample(chunk, index))`. `seed_field_chunk_light` calls it after the faces when `chunk.generated_shade`, which it clears. The fill then lights the roofed air from its openings with the falloff of `data/lighting.sjson`: under the 379 m arch's centre about 3.5 m from open air. The header comment's height field sentence names the carved air.
- `world_field_lod.odin`, `generate_field_grid`: `value, shaded := planet_sample_shaded(density_generation, position)`; an unloaded sample's sky is 0 in ground or when shaded, so a grotto's mouth reads dark from afar.
- The sky march (`field_sky_is_open`) reads `planet_sample` for a missing chunk within the shell, so an edit near a carve marches through the carve; `field_relief_top` stays (the carve lies under the height map).

### Readers of the height map

| Reader | Answer |
| --- | --- |
| Sky light march, `field_relief_top` | Top unchanged; the march reads the carve through `planet_sample`; the generated sky as above. |
| Ground look, `field_natural_share` | Unchanged: it reads `uncratered_relief`, so a carved face lies off the surface and reads as cut (no grass, sand or snow); its stone shows the stone tile, a steep face the rock as before. |
| Trees, `planet_tree_from_candidate` | Its relief comes from `surface_column`; a candidate whose column has a carving kind is dropped, so no tree stands on a fin, a dome or a cap, nor floats over an arch's flank where the carve opens the column. The slope probes stay. |
| Springs, `planet_spring_sample` | Unchanged: the climb starts at the height map's top and reads `planet_sample`, so a spring on a carving site rises on its top. The shipped springs lie on none (their streams as 0323 measured). |
| Dry home search, crater | Unchanged: no carving site within the calm circle. |
| `planet_sample_shortcut` | Unchanged: the carve lies between the ground and the height map's top, both within the bound, and never under the ground. |
| Relief map | Unchanged: it draws the height map, so a fin, a dome and a cap. |
| Level of detail | The shell unchanged; the grids read the carve and shade it. A thin roof under a coarse spacing reads as open. |
| `field_surface_under` | Unchanged: a start under a camera stands on the top. |
| The sea fill | Unchanged: carved air under the sea level holds the sea, so an arch or a grotto on the sea floor is flooded. |

### Record and old worlds

The nine keys travel in 0323's recorded `landmarks`. A world file written between 0323 and 0324 reads them as 0: no carving kind, and the ground, the trees and the light of before. New `recorded_carving_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string`: `world: the world file records no arches, grottos or mushroom rocks, it keeps the ground it was made with` when the record is present, records landmarks (`site_spacing_metres` above 0), its three carving shares are 0 and the data's are not all 0; "" otherwise. `resolve_world_planet` logs it after `recorded_landmarks_note`. No layout change.

### Tests

New `src/generation_planet_carve_test.odin`:

- Helper `design_carving_test_planet :: proc(radius_metres: int) -> Planet`: `design_landmark_test_planet` with the nine keys' shipped values.
- `test_the_carve_matches_the_design` (8 km, `DEFAULT_WORLD_SEED`, 1000 mm, `test_degree_point`): `uncratered_relief` (77, 144) 213207 (an arch's fin), (80, 160) 210557 (an arch), (86, 7) 44309, (86, 8) 34937, (86, 9) 786 (a grotto), and 0323's (85, 155) 26025 and (80, 110) 144312 unchanged. `uncratered_column` at (86, 7): `.Grotto`, ground -3250, along -10493, across 12001, `landmark_carve_distance` at 1, 2, 4, 8, 12 and 16 m: -4096, -8192, -7039, 7586, 23301, 39340; at (80, 160): `.Arch`, ground 197349, along 12386, across 20295: -4096, -8192, -14169, -7254, 920, 9132; at (77, 144): `.Arch`, ground 140031, along 26431, across 2831: -2080, -1406, 300, 4931, 10816, 17679.
- `test_carved_air_is_shaded_under_a_roof`: `planet_sample_shaded` at the radius plus the ground plus h along the direction of (86, 7): 2 m air and shaded, 9 m ground, -1 m ground; of (80, 160): 1 m air and not shaded (the raise is 3.2 m there, under the carve's top); of (77, 144): 1 m air and shaded (the opening's edge), 8 m ground.
- `test_the_carve_stays_between_the_ground_and_the_surface`: the three nearest sites of each carving kind (`test_landmark_sites`, 1500 m), columns on a 1 m grid over each site's outer square (`test_sphere_point` about its centre), heights from the ground less 2 m to the relief plus 2 m by 0.5 m: `column_depth` at most `relief - height`, above 0 under both the ground and the relief, at most 0 over the relief; and from the ground up the heights where `landmark_carve_distance` is at most 0 form one span (no carved height above an uncarved one). Mark slow if the times say so.
- `test_the_fill_lights_the_air_under_an_arch`: the nearest arch (379 m from the home; radius 6.7 m, stretch 335, height 28.0 m; at its centre the raise is 29.5 m and the carve's roof stands from about 20 m), the sample nearest 2 m over the ground at its centre. Its chunk generated twice is the same bytes and light, its sky is 0 and `generated_shade` is set. A `Field_World` of the 3 by 3 by 3 chunks round it, `seed_arrived_field_chunks(&world, max(int))`, `run_test_light` with `make_field_light_tuning(test_lighting_file(), 1000)`: its sky lies from 1 to `FIELD_LIGHT_FULL - 1`, the sample nearest 2 m over the relief at the centre holds `FIELD_LIGHT_FULL`, no chunk keeps `generated_shade`.
- `test_a_coarse_grid_shades_a_grotto`: `generate_field_grid` of the level 2 node (`test_surface_node`) holding 3 m over the nearest grotto's ground at its centre: at least one air sample with sky 0; the same node on `design_landmark_test_planet(8000)` has none.
- `test_no_tree_stands_on_a_carving_site`: `planet_tree_from_candidate(generation, {}, the nearest arch's centre, 1, NOISE_ONE * 100)` is not ok; on `design_landmark_test_planet(8000)` it is ok (the plain under it is dry and flat). If the plain fails the slope rule there, take the next arch and name it.
- `test_a_world_file_before_the_carving_keeps_its_ground`: a `World_File` of `planet_generation_record(design_landmark_test_planet(8000))` (its nine keys 0, as a file of before reads them) encoded, parsed and resolved against `design_carving_test_planet(8000)`: `recorded_carving_note` holds `records no arches`; the recorded planet's three shares are 0; the nearest arch's chunk generates the same bytes as on `design_landmark_test_planet` and other bytes on `design_carving_test_planet`.
- `test_landmarks_problems` gains: `arch_percent = 31` (the six shares add up to 101); `grotto_metres = {20, 12}` runs backwards; with `mushroom_percent = 0`, `mushroom_radius_metres = {0, 0}` passes.

### Docs

- `doc/content.md`, Planets: the carving keys in 0323's `landmarks` description; the shipped home's landmarks sentence names the three kinds and their counts within 3 km.
- `doc/architecture.md`, World generation: after 0323's landmarks, the carve (0324): the three kinds, the column (`Surface_Column`, `column_depth`, the minimum of the height map's depth and the carve's distance, nothing carved under the ground), the material by the height map's depth, the roof test and the readers that do not change; noise caves left for later and why (one sentence). The field light: the Sky light bullet's sentence on the generated full sky gains the carved air under a roof, 0 at generation and seeded at arrival (`seed_field_chunk_shade`). Save format: one clause, the carving keys read absent as 0 with `recorded_carving_note`.
- `doc/presentation.md`, Field meshes: the coarse grid's sentence `gives a generated sample full sky light in air and none in ground` adds `and none in carved air under a roof (0324)`.
- `doc/code_map.md`: the landmarks file's line names the carve.

### Hand-back check

- A number parsed from text is range checked: the nine keys in `landmarks_problem`.
- A changed save layout loads an old save: absent keys read as 0, the ground of before, one log line; the chunk format does not change and `generated_shade` is not saved.
- A new participant in a shared budget: the arrival's shade seed spends the light's per tick steps (8192). A grotto's chamber is about 3,000 samples, so it fills within a tick or two; it does not starve the other chunks' seeds, which keep `chunk_seeds_per_tick`.
- Tests never touch the state directory: worlds and files in memory.
- The rest does not apply.

### Cost

Per relief: the carving kinds add a root and two gradient noises in a carving site's columns (0.09 percent of them), so the mean is unchanged (1268 ns with them, 1272 without, within the noise). Per sample in a carving column, best of 15 interleaved over 69,185 points in the 37 sites within 3 km of the home at 8 km (the machine under a load of 18 to 20, so read the difference): the stamped shapes 1.57 to 1.60 µs a relief and 1.73 to 1.76 µs with the carve and the roof test; weathered 1.81 to 1.83 µs and 1.99 to 2.00 µs, about 0.25 µs more (the two noises). Per chunk: the 4 KB of shade bits; a chunk with shade (about four surface chunks a square kilometre at 8 km, well under 1 percent) is scanned once on arrival and its fill runs within the light's budget. The samples a view reads do not change.

### Questions to the main agent

None. Carved faces and cave floors show stone (answered 2026-11-07).

### Decisions (main agent, 2026-11-07)

1. The first draft's carves read as primitives (a plumb slab with an exact ellipse, a cylinder under a disc); this revision weathers them with two noises of the site. Accepted on `tmp/0323/carved_kinds_weathered.png`.
2. Stone on the carved faces and cave floors: accepted.
3. Noise caves and overhangs along the walls are 0327.
4. The worktree is made from 0323's snapshot with this specification cherry-picked.
