# 0323: Landmarks worth exploring

Status: implementing (2026-11-07)

The user (2026-11-07, after 0306 and 0307 on the phone): "while the terrain elevation now looks much more natural, it doesn't excite natural exploration. It needs to be more interesting and whimsical. Minecraft is really good at this, with gorges, cliffs, and even arcs, and other exciting features." The planet is a height map: a sample's density is its depth below `surface_relief` (`planet_sample_at_relief`), so it holds valleys and ranges but no feature that makes a player walk over to look. The research is `work/world_generation_research.md`.

## Goal

Within a few minutes' walk of any point there is something to go and see: a gorge with sheer walls, a cliff band or escarpment, a mesa or a butte, a spire, a sinkhole. Each is visible from a distance, and none repeats so that it reads as stamped.

## Controls

None.

## Change

- Height map landforms, after Minecraft's carvers and its jagged and badlands surfaces, each a term of the relief with its own rarity, scale and data keys:
  - gorges and ravines: a ridged noise carved deep and narrow, with steep walls that take the rock look;
  - cliff bands and escarpments: large steps of several metres to tens of metres, unlike the half-metre ledges 0322 removes;
  - mesas, buttes and spires: flat-topped and needle forms rising from plains;
  - sinkholes.
- A placement rule that spreads them so the player meets one at a walking pace, with the home's calm start of 0306 kept.
- The relief bound, the springs' streams (0312's water), the trees and the ground's look follow the new terms. Old worlds keep their relief through the record.
- The design prototypes the terms in the relief map mode and the captures, as 0306 did, and measures the cost against 0314's work.
- Docs: `doc/content.md` (Planets), `doc/architecture.md` (World generation).

## Verify

- The checks and the suite, with bounds, determinism and old world parity tests.
- Relief maps and captures of each landform, sent to the user.

## Specification (design, 2026-11-07)

Designed against 0322's approved specification (6da8927), which lands first in this stream: the shipped home has no ledges, `planet_stratum` takes a topsoil depth and `generation_topsoil_depth` gives a coarse grid two of its spacings of topsoil. The measurements are on the shipped home without the ledges; the goldens read the frozen `design_landform_test_planet`, which keeps them. The terms were tuned in an Odin prototype that copies the generation's integer maths and reproduces 0306's goldens: `tmp/0323/proto/` (`~/opt/odin/odin build tmp/0323/proto -out:tmp/0323/proto.bin -o:speed`; `NO_LEDGES=1` is 0322's home, `NO_CARVE_KINDS=1` is this item without 0324). Sources, figures and picks: `tmp/0323/research.md`. Images: `tmp/0323/relief_before_after.png` (4 km round the home at 4, 8 and 16 km, before and after), `picks_8km.png`, `landmarks_from_the_ground.png`.

### The landforms

Three terms after the landforms, each off at zero:

- Gorges: a cut along the zero lines of a noise read at the landforms' warped point, meandering with the hill noise, up to 26 m deep and about 20 m wide with a flat floor, in patches. Only ground at least half the depth over the floor (the sea plus 1 m) is cut, fully from the whole depth, so a gorge runs through plains, hills and ranges and fades out before the coast, and its floor never floods. Minecraft's canyon carver is long, narrow and deep; as a height map cut it costs one noise where it applies.
- Mesas and cliff bands: two tiers of 13 m where a second noise passes a threshold, each edge steep, in patches on the lowlands and plains. Where the noise peaks they are mesas; where it runs along the threshold they are escarpments of one or two steps. A patch's weaker edge raises the threshold, so the patch ends in smaller mesas, never lower ones (lower ones were the half metre snakes of 0322).
- Sites on a jittered lattice of 448 m cubes, one site per cube at most, the disc kept inside its cube so a point reads one cube: spires (10 to 18 m radius, 28 to 52 m high, the badlands' hoodoos), buttes (20 to 40 m, 14 to 28 m, stretched up to 2.2 times along a drawn axis) and sinkholes (12 to 24 m, 9 to 18 m deep), 30, 25 and 15 percent of the cubes. The other 30 percent are 0324's arches, grottos and mushroom rocks. A site's outline wobbles by 30 percent with a noise of its own radius, so no two read as stamped.

The patches are the landforms' first warp noise (gorges below -8 percent, mesas above 16, each fading in over 14), so they cost no noise, alternate over about a kilometre and never overlap. Every term scales with `home_wildness` or keeps clear of the calm circle, so the home's plain is unchanged. Noise caves, overhangs and arches need a three-dimensional density: 0324.

How far apart, at 8 km without the ledges: from land the nearest change of 3 m or more lies at a median of 174 m, a 90th percentile of 364 m and a 99th of 559 m (40 s, 85 s and 2.2 minutes at the walk's 4.3 m/s); 185, 417 and 970 m at 4 km, 155, 321 and 539 m at 16 km; 204, 438 and 622 m at 8 km without 0324's kinds. Within 3 km of the home at 8 km stand 38 spires, 12 buttes and 18 sinkholes. Over the sphere the gorges lower 1.2 percent of the points, the mesas raise 3.9, the sites change 0.4; no raise reaches the bound; 0.9 percent of the land is steeper than 50 degrees. Picks at 8 km for the captures: a gorge 25 m deep at 75.617 N 121.539 E (1068 m from the home), a cliff band at 83.678 N 170.333 E (616 m), a mesa at 84.162 N 160.423 E (467 m), a spire of 42 m at 79.996 N 109.741 E (614 m), a butte at 78.346 N 114.596 E (752 m), a sinkhole at 84.236 N 108.982 E (393 m).

### Data

A new optional planet object `landmarks` (`Planet_Landmarks`, in `data_planet.odin` after `Planet_Landforms`), off at the zero value. All keys `int`; a pair is `[2]int`, least and most:

| Key | Bound | Shipped |
| --- | --- | --- |
| `gorge_mask_percent`, `mesa_mask_percent` | 0 to 100 | 8, 16 |
| `mask_fade_percent` | 1 to 100 | 14 |
| `region_gorges_percent`, `region_mesas_percent` | `[LANDFORM_KNOT_COUNT]int`, each 0 to 100 | `[0, 0, 0, 0, 40, 100, 100, 100, 100]`, `[0, 0, 30, 100, 100, 70, 20, 0, 0]` |
| `gorge_wavelength_metres` | 1 to `MAXIMUM_RELIEF_WAVELENGTH_METRES` | 700 |
| `gorge_meander_percent` | 0 to 100 | 18 |
| `gorge_width_permille` | 0 to 1000, 0 is off | 40 |
| `gorge_floor_percent` | 0 to 99 | 30 |
| `gorge_metres` | 0 to `MAXIMUM_RELIEF_DEPTH_METRES`, 0 is off | 26 |
| `dry_metres` | 0 to `MAXIMUM_RELIEF_HEIGHT_METRES` | 1 |
| `mesa_wavelength_metres` | 1 to the wavelength maximum | 640 |
| `mesa_rough_percent`, `mesa_threshold_percent`, `mesa_tier_percent` | 0 to 100 | 35, 12, 12 |
| `mesa_edge_permille` | 1 to 1000 | 30 |
| `mesa_metres` | 0 to `MAXIMUM_LANDMARK_METRES`, 0 is off | 13 |
| `site_spacing_metres` | 2 times the widest site plus 2 to `MAXIMUM_LANDFORM_WILD_METRES`; 0 is off (the zero value) | 448 |
| `spire_percent`, `butte_percent`, `sinkhole_percent` | each 0 to 100, together at most 100 | 30, 25, 15 |
| `spire_radius_metres`, `spire_metres` | pairs, each 1 to `MAXIMUM_LANDMARK_METRES`, least at most most | `[10, 18]`, `[28, 52]` |
| `butte_radius_metres`, `butte_metres` | pairs as above | `[20, 40]`, `[14, 28]` |
| `butte_stretch_percent` | 100 to `MAXIMUM_LANDMARK_STRETCH_PERCENT` | 220 |
| `sinkhole_radius_metres`, `sinkhole_metres` | pairs as above | `[12, 24]`, `[9, 18]` |
| `wobble_percent` | 0 to `MAXIMUM_LANDMARK_WOBBLE_PERCENT` | 30 |

New constants in `data_planet.odin`: `MAXIMUM_LANDMARK_METRES :: 128`, `MAXIMUM_LANDMARK_STRETCH_PERCENT :: 400`, `MAXIMUM_LANDMARK_WOBBLE_PERCENT :: 90`. `OPTIONAL_PLANET_KEYS :: [4]string{"relief_shape", "landforms", "landmarks", "climate"}`; `missing_planet_key_problem` checks a present `landmarks` object's keys with `missing_struct_key(Planet_Landmarks, ...)` (`planets[%d].landmarks is missing %s`). `Planet` gains `landmarks: Planet_Landmarks` after `landforms` (comment: optional in the file, off at zero (0323), needs the landforms).

`landmarks_problem :: proc(landmarks: Planet_Landmarks, landforms: Planet_Landforms) -> string`, called in `planet_problem` after `landforms_planet_problem`: the zero value passes; landmarks with `landforms == {}` give `landmarks need landforms`; then the bounds, each feature's keys only while it is on (the gorges while `gorge_metres` and `gorge_width_permille` are above 0, the mesas while `mesa_metres` is, a site kind while its share is; the masks, the fade, the spacing, the shares and the wobble always), so 0324's keys can be absent from a world recorded before it. Messages: `landmarks.%s %d is outside %d to %d`, `landmarks.%s[%d] %d is outside 0 to 100`, `landmarks.%s [%d, %d] runs backwards` (least above most), `landmarks' site shares add up to %d, more than 100`. The spacing's least is `2 * landmark_widest_site_metres(landmarks) + 2`, where `landmark_widest_site_metres :: proc(landmarks: Planet_Landmarks) -> int` is the largest over the kinds that are on of the most radius times the kind's most stretch over 100, rounded up (`SPIRE_STRETCH_PERCENT`, `butte_stretch_percent`, `SINKHOLE_STRETCH_PERCENT`): 88 m shipped, so at least 178.

The bound does not change: `relief_bounds` and `landforms_planet_problem` stay as they are.

`data/planets.sjson`: the header's optional list gains `landmarks (0323)`; after `landforms`, the object with these comments (one per group, before its keys): the landmarks (work item 0323, doc/content.md, Planets), optional and needing the landforms, gorges and mesas in patches of the landforms' first warp noise and sites on a lattice, recorded by a world; the patches (gorges below minus `gorge_mask_percent`, mesas above `mesa_mask_percent`, each fading in over `mask_fade_percent`); their share at the landforms' region knots (the gorges cut the plains and the high ground, the mesas stand on the lowlands and plains); the gorges (along the zero lines of a noise of the wavelength, meandering with the hills, `gorge_width_permille` of the noise's range wide with a flat floor of `gorge_floor_percent` of it, `gorge_metres` deep, the floor at least `dry_metres` over the sea, only ground half the depth over it cut); the mesas and cliff bands (two tiers of `mesa_metres` where a noise of the wavelength roughened by the hills passes the threshold and the threshold plus the tier, each edge rising over `mesa_edge_permille` of the noise's range); the sites (one per cube of `site_spacing_metres` at most, the kind drawn by the shares and the rest of the cubes empty, radius and height between the pair's values, buttes stretched up to `butte_stretch_percent` along a drawn axis, the outline wobbling by `wobble_percent`).

### Generation

`generation_seed.Generation_Purpose` gains `Planet_Landmarks` appended after `Planet_Ground_Look` (comment: the landmarks of work item 0323). `Planet_Generation` gains `landmarks: Planet_Landmarks` and `landmark_seed: u64` (`seeds[.Planet_Landmarks]`), set in `make_planet_generation`'s literal. The home is `landform_home`.

`generation_planet_landforms.odin`:

- New `Landform_Reading :: struct {relief, wildness, region: i64, warped: [3]i64, mask, hill: i64}`: the landforms' relief, `home_wildness`, the region noise, the warped point, the first warp noise (axis 0, -NOISE_ONE to NOISE_ONE) and the hill noise (0 where the hills are off or their share is 0).
- `landform_reading :: proc(generation: Planet_Generation, point: [3]i64) -> Landform_Reading`: today's `landform_relief` body, keeping each value it already computes: `{}` when off, `{relief = home}` when `wildness == 0`, `mask` the warp noise of axis 0, `hill` the hill noise when read. The relief is bit for bit 0306's.
- `landform_relief` returns `landform_reading(generation, point).relief`.

`generation_planet.odin`, `uncratered_relief`: `reading := landform_reading(generation, point)`, then `return landmark_relief(generation, point, relief + ledge_relief(generation, point) + reading.relief, reading)`. The comment names the landmarks (0323) as the last term.

New file `src/generation_planet_landmarks.odin` (all `i64`, `/` truncating, `metres` is `metres_to_position_units`, `hash_combine` is `generation_seed.hash_combine`, the keys are `generation.landmarks`', `spacing` is `metres(site_spacing_metres)` and `outer` is `landmark_site_outer(site)`):

- `SITE_JITTER_BITS :: 21`, `SPIRE_STRETCH_PERCENT :: 130`, `SINKHOLE_STRETCH_PERCENT :: 140` (a spire's and a sinkhole's most stretch), `MESA_SHRINK_PERCENT :: 40` (how far a weak patch raises the mesas' threshold).
- `Landmark_Kind :: enum u8 {None, Spire, Butte, Sinkhole}`.
- `Landmark_Site :: struct {kind: Landmark_Kind, centre: [3]i64, hash: u64, radius, height, stretch_percent: i64}`.
- `Landmark_Profile :: struct {cap, wall_end, talus: i64}` and `LANDMARK_PROFILES :: [Landmark_Kind]Landmark_Profile{.None = {}, .Spire = {80, 450, 180}, .Butte = {520, 640, 220}, .Sinkhole = {300, 700, 80}}`: per mille of the stretched radius, the cap out to `cap`, the wall to `wall_end` falling to `talus` per mille of the height, the talus falling with the square to none at the radius.
- `landmark_ramp :: proc(value, threshold, fade: i64) -> i64`: `clamp((value - threshold) * NOISE_ONE / fade, 0, NOISE_ONE)`.
- `hash_metres_range :: proc(hash: u64, range: [2]int) -> i64`: `least := metres(range[0])`, `most := metres(range[1])`, `least + i64(hash % u64(most - least + 1))`.
- `landmark_site_outer :: proc(site: Landmark_Site) -> i64`: `site.radius * site.stretch_percent / 100`.
- `landmark_site_candidate :: proc(generation: Planet_Generation, cell: [3]i64) -> (site: Landmark_Site, candidate: [3]i64)`: `spacing := metres(site_spacing_metres)`, `hash := hash_lattice(hash_combine(landmark_seed, 8), cell)`, `draw := hash_combine(hash, 1)`, `roll := int(draw % 100)`; the kind by the cumulative shares spire, butte, sinkhole (`roll < spire_percent` a spire, and so on), `None` past them (return then). `radius := hash_metres_range(draw >> 8, <kind>_radius_metres)`; `stretch_percent := 100 + i64((draw >> 32) % u64(most - 100 + 1))` with `most` the kind's most stretch (`SPIRE_STRETCH_PERCENT`, `butte_stretch_percent`, `SINKHOLE_STRETCH_PERCENT`); the site's `hash` is `hash`. `candidate[axis] = cell[axis] * spacing + (i64((hash >> uint(axis * SITE_JITTER_BITS)) & ((1 << SITE_JITTER_BITS) - 1)) * spacing) >> SITE_JITTER_BITS`. No root.
- `landmark_candidate_near :: proc(generation: Planet_Generation, site: Landmark_Site, candidate, point: [3]i64) -> bool`: `offset := candidate - point`, `radial := (offset.x * point.x + offset.y * point.y + offset.z * point.z) / generation.radius`, `widened := landmark_site_outer(site) * (generation.radius + 2 * spacing) / generation.radius`; near when `offset · offset - radial * radial < widened * widened` (the candidate's distance from the point's radial, widened by the most the candidate lies off the sphere). It drops no site the point lies in (`tmp/0323` prefilter check: 1,000,000 points at each preset).
- `place_landmark_site :: proc(generation: Planet_Generation, cell: [3]i64, site: Landmark_Site, candidate: [3]i64) -> Landmark_Site`: `distance := vector_length(candidate)` (`None` at 0), `centre := candidate * generation.radius / distance`; `None` when for any axis `within := centre[axis] - cell[axis] * spacing` is under `outer` or over `spacing - outer` (the disc stays in its cube); `None` when the squared chord from `landform_home` is under `(metres(calm_metres) + outer)` squared (the disc stays out of the calm circle); else `height := hash_metres_range(hash_combine(hash, 3), <kind>_metres)` and the site.
- `landmark_site_at :: proc(generation: Planet_Generation, point: [3]i64) -> Landmark_Site`: the point's cell (`floor_divide_i64(point[axis], spacing)`), its candidate, `None` unless near, then placed. One lattice hash and no root for most points.
- `landmark_site_axis :: proc(site: Landmark_Site, radius: i64) -> [3]i64`: `h := hash_combine(site.hash, 5)`, `v := {i64(h & 0xFFFFF) - (1 << 19), i64((h >> 20) & 0xFFFFF) - (1 << 19), i64((h >> 40) & 0xFFFFF) - (1 << 19)}`, `axis, _ := normalize_fixed(fixed_cross(site.centre * UNIT_VECTOR_ONE / radius, v))`: a unit tangent at the site.
- `landmark_site_u :: proc(generation: Planet_Generation, site: Landmark_Site, point: [3]i64) -> (u: i64, inside: bool)`: `offset := point - site.centre`, `squared := offset · offset`; `NOISE_ONE, false` when `squared >= outer * outer`; `along := (offset · axis) / UNIT_VECTOR_ONE`, `across_squared := max(squared - along * along, 0)`, `stretched := across_squared + along * along * 10000 / (stretch_percent * stretch_percent)`, `u := i64(integer_square_root(u64(stretched))) * NOISE_ONE / site.radius`; when `wobble_percent > 0`, `wobble := gradient_noise(hash_combine(landmark_seed, 7), point, max(site.radius, metres(4)))` and `u = u * (100 * NOISE_ONE + i64(wobble_percent) * wobble) / (100 * NOISE_ONE)`; `inside = u < NOISE_ONE`.
- `landmark_site_shape :: proc(kind: Landmark_Kind, u: i64) -> i64`: with the profile scaled to NOISE_ONE (`cap * NOISE_ONE / 1000` and so on): 0 at `u >= NOISE_ONE`; NOISE_ONE to `cap`; to `wall_end`, `fade := noise_fade((u - cap) * NOISE_ONE / (wall_end - cap))` and `talus + (NOISE_ONE - talus) * (NOISE_ONE - fade) / NOISE_ONE`; past it `v := (u - wall_end) * NOISE_ONE / (NOISE_ONE - wall_end)` and `talus * (NOISE_ONE - v) / NOISE_ONE * (NOISE_ONE - v) / NOISE_ONE`.
- `landmark_site_relief :: proc(generation: Planet_Generation, point: [3]i64) -> (raise, cut: i64)`: 0, 0 without a site or outside it; a sinkhole's `height * shape / NOISE_ONE` is the cut, any other kind's the raise.
- `landmark_gorge_cut :: proc(generation: Planet_Generation, reading: Landform_Reading, strength: i64) -> i64`: `root := i64(integer_square_root(u64(strength * NOISE_ONE)))`, `width := i64(gorge_width_permille) * NOISE_ONE / 1000 * root / NOISE_ONE` (0 when not above 0), `noise := abs(gradient_noise(hash_combine(landmark_seed, 1), reading.warped, metres(gorge_wavelength_metres)) + i64(gorge_meander_percent) * reading.hill / 100)`, 0 when `noise >= width`; `a := noise * NOISE_ONE / width`, `floor := i64(gorge_floor_percent) * NOISE_ONE / 100`, `shape := NOISE_ONE`, or when `a > floor` `i64(integer_square_root(u64((NOISE_ONE - a) * NOISE_ONE / (NOISE_ONE - floor) * NOISE_ONE)))`; returns `max(metres(gorge_metres) * shape / NOISE_ONE * root / NOISE_ONE, 1)`. Width and depth by the root of the strength, so a patch's edge narrows the gorge as it shallows.
- `landmark_mesa_raise :: proc(generation: Planet_Generation, point: [3]i64, hill, strength: i64) -> i64`: `noise := gradient_noise(hash_combine(landmark_seed, 2), point, metres(mesa_wavelength_metres)) + i64(mesa_rough_percent) * hill / 100` (the point unwarped: the warp drew the mesas into ribbons), `threshold := i64(mesa_threshold_percent) * NOISE_ONE / 100 + (NOISE_ONE - strength) * MESA_SHRINK_PERCENT / 100`, 0 when `noise <= threshold`; `edge := i64(mesa_edge_permille) * NOISE_ONE / 1000`, `tier := i64(mesa_tier_percent) * NOISE_ONE / 100`, returns `metres(mesa_metres) * (noise_fade(landmark_ramp(noise, threshold, edge)) + noise_fade(landmark_ramp(noise, threshold + tier, edge))) / NOISE_ONE`.
- `landmark_relief :: proc(generation: Planet_Generation, point: [3]i64, relief: i64, reading: Landform_Reading) -> i64`, in this order:
  1. `relief` when `site_spacing_metres == 0` (off) or `reading.wildness == 0`.
  2. `floor := max(generation.sea_radius - generation.radius + metres(dry_metres), generation.relief_lowest)`, `fade := i64(mask_fade_percent) * NOISE_ONE / 100`, `raise, gorge := 0, 0`.
  3. Gorges, when `gorge_metres > 0 && gorge_width_permille > 0`: `patch := landmark_ramp(-reading.mask, i64(gorge_mask_percent) * NOISE_ONE / 100, fade)`; when `patch > 0 && relief > floor`: `depth := metres(gorge_metres)`, `strength := patch * landmark_ramp(relief - floor, depth / 2, depth / 2) / NOISE_ONE`; when `strength > 0`, `strength = strength * (landform_curve(region_gorges_percent, reading.region, NOISE_ONE) / 100) / NOISE_ONE * reading.wildness / NOISE_ONE`; when still `> 0`, `gorge = landmark_gorge_cut(generation, reading, strength)`.
  4. Mesas, when `mesa_metres > 0`: `patch := landmark_ramp(reading.mask, i64(mesa_mask_percent) * NOISE_ONE / 100, fade)`; when `> 0`, `strength := patch * (landform_curve(region_mesas_percent, reading.region, NOISE_ONE) / 100) / NOISE_ONE * reading.wildness / NOISE_ONE`; when `> 0`, `raise = landmark_mesa_raise(generation, point, reading.hill, strength)`.
  5. `site_raise, site_cut := landmark_site_relief(generation, point)`.
  6. `result := min(relief + raise + site_raise, generation.relief_highest)`; when `gorge > 0`, `result = min(result, max(relief - gorge, floor))`; when `site_cut > 0 && result > floor`, `result = max(result - site_cut, floor)`; return it.

  The mask comes first, so a patch's ramp of 0 skips its curve and its noise. Raises clamp at the bound's highest (no point of 200,000 reached it) and cuts stop at the floor, so the relief stays within `relief_lowest` to `relief_highest` and every reader of the bound (the shortcuts, the crater's clamps, the sky march's top, the level of detail's shell, the globe, the bedrock's minimum) stays as it is.

### Readers

- The crater, the home and the dry home search: the terms are 0 within the calm circle (wildness 0, sites kept `calm_metres` plus their reach away), and landmarks need landforms, under which the search keeps the home. Unchanged.
- The springs: the first spring's stream is the same at every preset (8 km: 84.9 m over the sea, 370 m, drop 64.0 m, the prototype's measure); the second the same at 4 and 8 km, 230 m becomes 226 m at 16 km. `test_the_default_springs_stream_runs_downhill` holds.
- The trees follow `surface_relief`; the slope rule keeps them off the walls and the spires. The ground's look: the walls, the tier edges and the spires take the rock look by their steepness; `field_natural_share` reads `uncratered_relief`, which holds the landmarks, so their flats are natural and take the grass. No change in either.
- The level of detail's grids read `planet_sample`, so they show the terms; the relief map draws `surface_relief`. No change.
- The sea: a gorge floor stays 1 m over it, a sinkhole too; a spire, butte or mesa on the sea floor stands out of the water as a stack.

### Record and old worlds

`Planet_Generation_Record` gains `landmarks: Planet_Landmarks` after `landforms` (comment: zero in a file written before them (0323), the relief of before), copied by `planet_generation_record` and set by `make_recorded_planet` even when zero (comment as the landforms'). The record's check runs `landmarks_problem` through `planet_problem`. No format version step (Save format: fields added to `world.sjson` read absent as zero). New `recorded_landmarks_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string`: `world: the world file records no landmarks, it keeps the relief it was made with` when the record is present, records landforms, has `landmarks == {}`, and the data's planet has landmarks; "" otherwise (a file from before 0306 already logs the landforms' line). `resolve_world_planet` logs it after the landforms' note.

### Tests

New `src/generation_planet_landmarks_test.odin`:

- Helper `design_landmark_test_planet :: proc(radius_metres: int) -> Planet`: `design_landform_test_planet(radius_metres)` with `landmarks` the shipped values above as a literal (frozen, so later data edits leave the tests).
- Helper `test_landmark_sites :: proc(generation: Planet_Generation, kind: Landmark_Kind, reach_metres: int, allocator := context.temp_allocator) -> [dynamic]Landmark_Site`: every placed site of the kind whose cell lies in the box of `landform_home` plus and minus the reach (cells by `floor_divide_i64`), through `landmark_site_candidate` and `place_landmark_site`, sorted nearest the home first. 0324's tests use it too.
- `test_landmark_relief_matches_the_design`: `DEFAULT_WORLD_SEED`, spacing 1000, `uncratered_relief` at `test_degree_point` of `design_landmark_test_planet(8000)`: (83, 132) 2697, (81, 139) 113668 (the home and the plain, unchanged); mesas (85, 155) 26025, (85, 156) 41810, (84, 159) 13595; a sinkhole (82, 159) 102117; spires (80, 110) 144312, (80, 109) 84544, (80, 174) 228955; gorges (76, 121) 146494, (75, 135) 19593, (77, 166) 191302; a butte (85, -102) -150118, (85, -103) -148973; cells whose roll falls past the three kinds (77, 144) 140031 and (86, 7) -3250. On `design_landform_test_planet(8000)` the same function gives (85, 155) -12553, (82, 159) 154417, (80, 110) 101192, (76, 121) 199259, (85, -102) -153740, (77, 144) 140031 and (86, 7) -3250. At 4 km (60, -130): -78136 without, 28360 with (a mesa); at 16 km (60, -148): -12931 and 91978 (a mesa), (60, 79): 148182 and 90300 (a gorge).
- `test_the_landmarks_keep_the_relief_bound`: `planet_relief_bounds(design_landmark_test_planet(8000))` equals the landforms' planet's; at 4, 8 and 16 km over `test_line_point(generation, index)` for 20,000 indexes `surface_relief` lies within `relief_lowest` to `relief_highest`, and where it lies below the landforms' planet's it is at least `max(sea + metres(1), relief_lowest)` from the radius. Mark slow if `build/test_times.tsv` says so.
- `test_the_landmarks_keep_the_home_calm`: over `test_scattered_point(generation, home direction, index, 80 m)` for 2,000 indexes `uncratered_relief` equals the landforms' planet's; every site of `test_landmark_sites` within 1500 m, every kind, lies at least `calm_metres` plus its outer reach from `landform_home`.
- `test_every_site_kind_stands_near_the_home`: at 4, 8 and 16 km, at least 10 sites of each kind with centres within 3000 m of the home (measured 33, 18 and 14 at 4 km, 38, 12 and 18 at 8 km, 29, 21 and 14 at 16 km).
- `test_landmarks_problems`, in the form of `test_landforms_problems`: `landmarks_problem({}, {})` is ""; the design planet passes `planet_problem`; landmarks without landforms; `mask_fade_percent = 0`; `region_gorges_percent[4] = 101`; `gorge_floor_percent = 100`; `mesa_edge_permille = 0`; `spire_percent = 61` (the shares add up to 101); `butte_metres = {28, 14}` (runs backwards); `butte_stretch_percent = 401`; `site_spacing_metres = 177`; `wobble_percent = 91`; with `spire_percent = 0`, `spire_radius_metres = {0, 0}` passes (a kind's keys are checked only while it is on). The shipped file's text without `gorge_metres = 26` gives `planets[0].landmarks is missing gorge_metres` (`expect_planets_problem`).
- In `src/generation_planet_landforms_test.odin`, beside the two record tests: `test_a_world_file_before_the_landmarks_keeps_its_relief`, as `test_an_old_world_file_keeps_its_relief` with `old := design_landform_test_planet(8000)` and the `landmarks` object cut from the text: `recorded_landmarks_note` with the shipped planet holds `records no landmarks`, the resolved record's and the recorded planet's landmarks are zero, and `surface_relief` over 100 `test_line_point(generation, index * 200)` equals the old planet's; `test_a_new_world_records_its_landmarks`, as `test_a_new_world_records_its_landforms`.
- `test_report_the_relief_cost`: the loop takes three planets, `pre_0306_test_home_at(8000)`, the shipped home with `landmarks = {}` and `shipped_test_home_at(8000)`, labelled before, 0306 and after.

The shipped relief changes for the tests reading `shipped_test_home_at`: the springs' thresholds hold (above); the tree density's circles may lose a tree to a wall. If a test pinned on the shipped relief fails, re-pin it on the measured value and name it in the report.

### Docs

- `doc/content.md`, Planets: the keys sentence names `landmarks` among the optional keys and describes it after `landforms` (0323, optional, needs the landforms; the keys and bounds above in the paragraph's form; the bound unchanged); the shipped home's paragraph gains one sentence: the landmarks' shipped values, the walk's distances (median 174 m, 99th percentile 559 m at 8 km) and the counts within 3 km. Write it over 0322's text.
- `doc/architecture.md`, World generation: after the landforms' passage, the landmarks (0323, `generation_planet_landmarks.odin`, off at the zero value): the patches from the first warp noise, the gorge cut and its dry floor, the mesa tiers, the site lattice with one cube per point and the prefilter, the clamp and the floor that keep the bound, the cost (one site lookup always, a noise on about 16 and 26 percent of the evaluations, +17 percent per relief in the wild). Save format: the record's `landmarks` (0323) with the old file sentence and `recorded_landmarks_note`.
- `doc/code_map.md`: `generation_planet_landmarks.odin` after the landforms' line.

### Hand-back check

- A number parsed from text is range checked: every key in `landmarks_problem`, and the spacing against the widest site.
- A changed save layout loads an old save: the record's `landmarks` reads absent as zero, the old relief, with one log line.
- Tests never touch the state directory: the record tests encode and parse in memory.
- The rest does not apply: no memory a frame draws from, no file written, no shared budget, no list or string drawn.

### Cost

One `uncratered_relief` in the wild, best of seven over 500,000 points on one core without the ledges: 1084 ns without the landmarks, 1268 with (+17 percent) within 3 km of the home, 1060 and 1238 over the sphere. Always: one lattice hash for the site (70 to 90 ns); a gorge noise on 15.7 percent of the evaluations, a mesa noise on 26.3, a site's root on 1.3, the wobble on 0.6. The samples a view reads do not change (the bound is the same). Against 0314: 0306 made a relief about three times the cost of before; this adds a sixth of that, and 0314's candidates (the low frequency terms on a lattice, one relief per column) cover these terms too: the mask, the region and the hill come from the landforms' reading, the gorge noise is read at the warped point.

### Questions to the main agent

1. Cliff bands are the mesas' tier edges (13 m steps in one or two tiers along the threshold), not a term of their own: one noise gives both the escarpments and the tables. A separate step term over the whole planet looked like 0189's terraces in the prototype. Accept?
2. 0323 alone fills 70 percent of the lattice cubes and leaves 30 for 0324's three kinds, so 0324 adds sites without moving any. If 0324 is cut, raise the three shares instead.
3. A spire can reach 52 m on a plain 614 m from the home and is the first thing seen from the pod. Keep, or keep the tallest kinds out to 1 km?

### Decisions (main agent, 2026-11-07)

1. Cliff bands as the mesas' tier edges: accepted.
2. 0324 is not cut; it takes the 30 percent of the cubes 0323 leaves.
3. The 52 m spire 614 m from the pod stays: a landmark seen from the start is what the item asks for.
4. The worktree is made from 0322's snapshot with this specification cherry-picked; the implementation reads 0322's code there (`planet_stratum`'s topsoil argument, `generation_topsoil_depth`, no ledges on the shipped home).
