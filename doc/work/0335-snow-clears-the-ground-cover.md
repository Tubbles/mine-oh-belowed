# 0335: Snow clears the ground cover

Status: implementing (2026-11-07)

From 0311's landing captures: at the cold spot (81.4358 N, 159.9575 E, 0 °C, 70 % moisture) the terrain draws the ground white with snow, while grass tufts stand all over it (`test_the_cover_follows_the_climate` logs grass at 2.4 a square metre there). The user (2026-11-07): "Grass doesn't grow through snow no, if its not very freshly fallen and just a little amount. And I mean very freshly, like within a day, and at most 1 cm or something". The generated snow is settled snow, so no plant shows through it.

The grass kind already grows on no snow (`surfaces.snow = 0` in `data/planets.sjson`), so the cover's snow share (`cover_ground_shares`, from the look's weights) reads less snow than `field.fs` draws at that place.

## Goal

No grass, flowers or ferns on ground the terrain draws as snow, at any climate and slope; where snow thins out at its edge, the plants thin out with it.

## Controls

None.

## Change

- Find where the cover's snow share and `field.fs`'s snow part (the inputs, the per vertex against per fragment terms, a noise or a height term one side has and the other lacks) and make the cover read the snow the ground shows.
- Pebbles and the ore specks lie under settled snow too; boulders (up to 0.65 m) may stand above it. The design proposes what the stones do, the main agent decides.
- A fresh dusting that tufts show through belongs to the weather's snowfall (M15), not here.
- Docs: `doc/presentation.md` (the ground cover), `doc/content.md` (the cover's kinds) if a key changes; the log.

## Verify

- The checks and the suite, with a test that no plant instance stands where the ground's snow share (as `field.fs` computes it) is over a threshold the design names, at the cold spot and on a snow line.
- Captures at the cold spot and along a snow edge at eye height, sent to the user.

## Specification (design, 2026-11-07)

Measured with a probe on the shipped home at 8 km, `DEFAULT_WORLD_SEED`, the cold spot's 3 by 3 nodes (9683 m²), triangles bucketed by `field.fs`'s snow weight at their centroid (an Odin port of the shader reading the mesh's vertex arrays as `field.vs` unpacks them):

| `field.fs` snow weight | cover's snow share | snow tile's share of the drawn albedo | grass a m², now | with this change |
|---|---|---|---|---|
| 0.0 to 0.1 (2365 m²) | 0.028 | 0.019 | 4.23 | 4.10 |
| 0.1 to 0.2 (1352 m²) | 0.147 | 0.132 | 3.33 | 1.81 |
| 0.2 to 0.3 (937 m²) | 0.246 | 0.235 | 1.67 | 0.15 |
| 0.3 to 0.6 (4553 m²) | 0.354 to 0.544 | 0.348 to 0.546 | 1.44 to 1.62 | 0 |
| 0.6 to 0.9 (476 m²) | 0.639 to 0.822 | 0.644 to 0.835 | 0.48 to 0.76 | 0 |

The drawn colour at the cold spot (the tiles' means, the cold grass colour): L* 66 and a green lead of 0.16 at weight 0, 75 and 0.12 at 0.25, 83 and 0.07 at 0.5, 95 and none at 1. The capture's place, the cold spot's own node, lies at 0.4 to 0.6.

Cause: the two numbers agree (the centroid's shader weight equals the triangle's `cover_ground_shares` snow to three places), but they mean different things. `field.fs` blends the snow over every fragment by its weight, so at 0.5 the whole ground is half way to white and reads as snow, while the cover reads the weight as the share of the ground under snow and grows grass at the rest of its rate.

### Change

No shader and no data change. `src/world_field_cover.odin`:

- `COVER_SNOW_THIN_WEIGHT :: 0.05` and `COVER_SNOW_GONE_WEIGHT :: 0.25`, beside `GROUND_SAND_END_STEEPNESS`: `field.fs`'s snow weight where a kind that grows on no snow starts to thin, and where none of it stands.
- `cover_point_snow :: proc(triangle: Cover_Triangle, shares: [3]f64, point: [3]f64) -> f32`: `field.fs`'s snow weight at a point of the triangle, its corners weighed by the barycentric `shares`, `point` in world metres. In f64: the topsoil's share of the seven weights' sums (`field_material_slot(.Topsoil)` over all of `corner.weights`; 0 when the sum is 0), the steepness `1 - dot(normalize(sum of shares times corners[i].normal), normalize(point))`, rock the topsoil times `math.smoothstep` of `GROUND_ROCK_START_STEEPNESS` to `GROUND_ROCK_FULL_STEEPNESS`, the result `(topsoil - rock) * natural * snow` with the look's bytes over 255, interpolated.
- `cover_snow_buries :: proc(kind: Field_Cover_Kind, snow, unit: f32) -> bool`: `unit < (1 - kind.surfaces[.Snow]) * clamp((snow - COVER_SNOW_THIN_WEIGHT) / (COVER_SNOW_GONE_WEIGHT - COVER_SNOW_THIN_WEIGHT), 0, 1)`. A unit is under 1, so a kind with no snow share is always buried at `COVER_SNOW_GONE_WEIGHT` and over.
- `place_field_cover`: after `light`, `snowy := triangle.surfaces[0].look.snow > 0 || triangle.surfaces[1].look.snow > 0 || triangle.surfaces[2].look.snow > 0`; in the instance loop, right after `point`, `if snowy && kind.surfaces[.Snow] < 1 && cover_snow_buries(kind, cover_point_snow(triangle, {1 - along - across, along, across}, point), cover_unit(hashes[3], 2)) { continue }`. Slot 2 of `hashes[3]` is unused today; `cover_instance`'s comment names it as the caller's, as slot 1.
- The comments: the file header (the snow buries the kinds that do not grow on it), `place_field_cover`'s (an instance is also skipped where the snow buries it), `cover_ground_shares`'s stays true.

The gate reads only the triangle's surface vertices and the instance's hashes, so a node gives the same cover on every machine and from a generated grid as from its loaded chunks. Its cost is a dozen products per candidate instance on snowy triangles of kinds not growing on snow; nothing on warm ground. With the probe's prototype the 0311 tests pass, the cold spot's grass falls from 2.41 to 1.27 a square metre (`test_the_cover_follows_the_climate`'s bound of 2.5 stays).

### Tests

`src/world_field_cover_test.odin`:

- `cover_test_ray_barycentric :: proc(origin, direction, a, b, c: [3]f64) -> (distance, along, across: f64, hit: bool)`: `cover_test_ray_hit`'s body returning its two barycentric terms too; `cover_test_ray_hit` returns its distance and hit.
- `cover_test_fragment_snow :: proc(mesh: Field_Mesh_Data, origin: [3]f64, indices: [3]int, shares: [3]f64) -> f64`: `field.fs`'s snow weight from the vertex arrays as `field.vs` unpacks them (`weights`, the ores from `lights[i][1]`, snow and natural from `looks[i][1]`, bytes as `unpack_bytes` gives them, normals, the up the normalised `origin + position`), so it is independent of `cover_point_snow`.
- `test_cover_snow_buries_by_the_kinds_snow` (unit): the shipped grass is not buried at weight 0.05 with unit 0, buried at 0.25 with unit 65535/65536, at 0.15 buried with unit 0.4 and not with 0.6; the boulders are not buried at 1 with unit 0; a kind with `surfaces.snow` 0.5 at 0.25 is buried with unit 0.4 and not with 0.6.
- `test_cover_point_snow_twins_field_fs` (unit): `field.fs` holds `float topsoil = weights.x;`, `float rock = topsoil * ground_look_on * smoothstep(rock_start_steepness, rock_full_steepness, steepness);`, `float cover = (topsoil - rock) * ground_look_on * fragment_look.z;` and `float snow = cover * fragment_look.x;`; on a hand triangle at (0, 8000, 0) m with every normal (0, 1, 0), topsoil 255, snow 128 and natural 255, `cover_point_snow` is 128/255 within 1e-6 at the centroid; with every normal 60 degrees off the up it is 0; with corner 0 all stone it is 0 at shares (1, 0, 0) and 64/255 at (0.5, 0.5, 0); with natural 0 it is 0.
- `test_snow_buries_the_plants` (slow; 3.5 s in the probe at `-o:none`): the cold spot's node (`cover_test_surface_node(generation, cover_test_direction(81.4358, 159.9575), 0, 0)`) and the snow line, `COVER_TEST_SNOW_LINE :: [4][2]i64{{-256, -672}, {-256, -640}, {-256, -608}, {-256, -576}}` as ahead and aside from the same direction (weight 0 to 1 across them at the shipped seed), each meshed by `cover_test_grid_cover`. Each instance is found on its triangle as `test_the_cover_lies_on_its_triangles` finds it (only triangles whose centroid lies within 3 m of the base tried) and is checked at its hit's barycentric point with `cover_test_fragment_snow`. Asserts: every instance is found; every instance of a kind whose `surfaces.snow` is 0 stands under `COVER_SNOW_GONE_WEIGHT` + 0.001 (most measured 0.249); the cold spot's node holds no grass (measured 0); on the snow line the grass a square metre on triangles whose centroid weight is under `COVER_SNOW_THIN_WEIGHT` is at least 2 (2.73), and on those between the two weights above 0 and under half that (1.12); at least one boulder stands at `COVER_SNOW_GONE_WEIGHT` or over (9). The densities are logged.

### Docs

- `doc/presentation.md`, The field session, the ground cover's bullet, after the density sentence: an instance of a kind growing on less than the full snow is buried where `field.fs` draws snow (`cover_snow_buries`, 0335): the shader blends the snow over the whole ground by its weight, so 0.5 already reads as snow; at the instance's own point (`cover_point_snow`, the shader's term) such a kind thins from `COVER_SNOW_THIN_WEIGHT` (0.05) to none at `COVER_SNOW_GONE_WEIGHT` (0.25), times its share not growing on snow, against a hash of the instance.
- `doc/content.md`, Planets, `cover`, the `surfaces` key: the snow share also says how far the drawn snow buries the kind (0 buried from 0.25 of the snow's weight, 100 standing on it, presentation.md, The field session). No key changes.

### Hand-back check

None applies: no memory freed under a frame, no file written, no parsed number, no save layout, no shared budget, no HUD list, no audit case; the tests read generated grids only.

### Questions to the main agent

1. The stones. Recommended: no data change, the rule reads each kind's `surfaces.snow`. Pebbles, dry stones and the three specks (0) lie under the snow as the plants do; the boulders (100) stand on it. `field.fs` lays snow only on natural topsoil, never on the steep face's rock, on stone or on ore, so pebbles on a rock face and specks on an outcrop still show in the cold, on ground drawn without snow. Snow on those surfaces is a look change for its own item.
2. The weights as constants or a key (`cover.snow_weight_percent = [5, 25]`). Recommended: constants, since they read `field.fs`'s blend as `GROUND_ROCK_START_STEEPNESS` does; which kinds the snow buries is already data. A key would let the user tune them with a data reload.
3. The gone weight. 0.25 draws the ground a quarter of the way to white (L* 75). The captures may show the user wants 0.2 or 0.3.

### Decisions (main agent, 2026-11-07)

1. The stones follow each kind's `surfaces.snow`, no data change: pebbles, dry stones and the specks lie under the snow, the boulders stand on it. Snow on rock, stone and ore is a look change for an item of its own if the user asks.
2. The weights are constants beside `GROUND_ROCK_*`, since they read `field.fs`'s blend.
3. The gone weight ships at 0.25; the captures at the cold spot and along a snow edge go to the user, who may move it to 0.2 or 0.3.
