# 0199: The pod sits in an impact crater, no pad

Status: todo (user, 2026-10-03: "the pod shouldn't come with foundation, it should just be buried directly in the ground inside an impact crater"; after 0198)

## Goal

The pod lies where it fell: half buried in the ground at the bottom of a crater it made, with no pad of foundations around it. Today `place_pod` (`entity_pod.odin`) lays a free frame with a pad of `POD_PAD_SIZE` foundations that cost nothing and the pod on it, and the players spawn in front of its door (`field_home_player`).

## Change

- The crater is a field edit of the new world at the home site, deterministic from the seed and the planet record: a bowl dug to a depth and radius the planet names (`crater` in `data/planets.sjson`: `radius_metres`, `depth_metres`, `rim_metres`), a rim raised around it with the dug material, the floor flat enough for the pod. It is applied once when the world is created (`enable_new_field_world`), before the pod is placed, through the brush edits that exist (`apply_field_edit`), so a joiner's snapshot and a loaded save hold it as changed chunks and no machine regenerates it differently.
- The pod's frame stands on the crater floor with its floor cell at the floor's level, sunk so the hull's base is below the rim's ground; no foundations are placed (`pod_pad_cells` goes, `POD_PAD_SIZE` goes, 0196's pad foundation is the benchmark's only). The crater is wide enough that the airlock (0198) opens onto the floor and a ramp of slope the player walks (0189's slopes) leads out over the rim.
- The players spawn inside the pod (0200 opens the hatch; before it, the spawn is inside with the hatches open), not in front of it; `field_home_player` reads the pod's cabin cell.
- The planet preview's walk start (0184) and the dry spawn (0180) follow the crater floor.
- `doc/content.md` (The pod: the crater, no pad; Planets: the crater record), `doc/architecture.md` (the new world's home edit), the log.

## Controls

- None.

## Verify

- The build and check commands of 0168.
- Tests: a new world's home has a bowl below the generated surface and a rim above it within the record's radii; the pod's floor cell is at the floor's level and no foundation entity exists; two sessions with the seed hash alike after the edit; a save round trips the crater as changed chunks; the spawn is inside the cabin.
- The couch: the user starts a world in the pod, walks out of the airlock onto the crater floor and up the rim.

## Specification (design, 2026-10-03)

Designed against `main` at 2411594 plus the uncommitted 0189 tree (relief shape in `data_planet.odin` and `generation_planet.odin`), which lands first. 0198 has no approved specification yet, so this item is designed against today's 6 by 6 by 8 pod and sizes the crater for 0198's 8 by 12 by 8 cells; what 0198 must keep is under 0198 below. 0180 (dry home) is not on `main`; what changes for it is under 0180 below. Integer only throughout: position units (`POSITION_UNITS_PER_METRE` 4096), `fixed_scale`, `fixed_sine`/`fixed_cosine` on `ANGLE_UNITS_PER_TURN`, 2π as 710/113.

### The crater record (`data/planets.sjson`, `data_planet.odin`)

- New type in `data_planet.odin`: `Planet_Crater :: struct { radius_metres, depth_metres, floor_radius_metres, rim_metres: int }`, and `crater: Planet_Crater` on `Planet` after `home`. The key is required in the file (it is not `OPTIONAL_PLANET_KEY`); `missing_planet_key_problem` checks its four keys as it checks `home` (`missing_struct_key(Planet_Crater, …)`, message `planets[%d].crater is missing %s`).
- Meaning, measured from the generated surface at the home (G) along the home's up: `radius_metres` is the bowl's radius where it meets the generated surface; `depth_metres` is the floor (F = G minus depth along up) below G; `floor_radius_metres` is the radius of the exactly flat floor round F; `rim_metres` is the rim's crest height above the generated surface. The rim's half width is `CRATER_RIM_WIDTH_PER_HEIGHT` (3) times its height, a constant in `simulation_field_crater.odin` (outer slope about 37°, under the 60° walkable angle).
- Bounds, new `crater_problem(crater: Planet_Crater) -> string` called from `planet_problem` after `home_problem`, messages in the file's style (`crater.<key> %d is outside %d to %d`):
  - All four zero is no crater (the code-built test planets); otherwise:
  - `radius_metres` `MINIMUM_CRATER_RADIUS_METRES` (4) to `MAXIMUM_CRATER_RADIUS_METRES` (24).
  - `depth_metres` 1 to `MAXIMUM_CRATER_DEPTH_METRES` (16), and below `radius_metres`.
  - `floor_radius_metres` 2 to `radius_metres - 2`.
  - `rim_metres` 0 to `MAXIMUM_CRATER_RIM_METRES` (4).
  - The reach `radius_metres + 2 * 3 * rim_metres` at most `MAXIMUM_CRATER_REACH_METRES` (24), message `crater reaches %d m, more than %d`.
  - The bowl sphere (below) at most `MAXIMUM_CRATER_BOWL_METRES` (64): `radius² + depth² <= 2 * depth * 64`, message `crater radius %d and depth %d make a bowl of more than %d m, deepen or narrow it`. This bounds the scratch generation.
- `generation_planet_veins.odin` gains `#assert(MAXIMUM_CRATER_REACH_METRES < PLANET_VEIN_MINIMUM_DISTANCE_METRES - PLANET_VEIN_MAXIMUM_RADIUS_METRES)`, so no crater digs a starter outcrop (30 m minus 5 m today).
- Shipped in `home`: `crater = {radius_metres = 12, depth_metres = 3, floor_radius_metres = 4, rim_metres = 1}`, with a comment naming what each is. Derived: bowl sphere 25.5 m, wall slope 9° at the floor edge and 28° at the top, a 0.31 m step where the floor meets the bowl (within one sample at 333 mm, so 0203's step takes it at every spacing), rim ring at 15 m, 32 rim edits, outer reach 18 m. The floor of radius 4 m holds today's pod (corners 2.1 m out) and 0198's (4 by 6 m, corners 3.6 m out) with its airlock opening onto floor that rises at 9°.
- Not recorded in `Planet_Generation_Record`: the crater exists only as saved chunks after creation (below), so a loaded world never reads the key and an edit of it reshapes new worlds only. `make_recorded_planet` copies it from the data planet like every unrecorded field; no world file change.

### Digging at world creation (`simulation_field_crater.odin`, new, simulation cluster)

The rule that places it: centred on the home's generated surface G = `field_home_site`'s surface, its up the radial through G, its tangent axes those of the pod's frame (`free_frame_at(G, heading, pitch)`: `axes[FRAME_RIGHT]`, `axes[FRAME_FORWARD]`).

The edits, in this fixed order, every one with `rate = 2 * MAXIMUM_DENSITY` (one application reaches the target), `tick = 0`, `dig_rate_percent` zero, `up` the home's up:

1. Bowl: `.Dig`, `.Sphere`, centre F + up·S, radius S = (b² + D²) / (2D) in position units (b radius, D depth), `diggable = ~bit_set[Field_Material]{}`. The sphere's lowest point touches F and it crosses G at radius b.
2. Floor cut: `.Dig`, `.Level`, centre F, radius a (floor radius), same diggable. Clears the sliver the bowl leaves above F's plane and sets the plane's exact densities.
3. Floor fill: `.Place`, `.Level`, centre F, radius a, `budget = max(i64)`, material and tint from `planet_sample(generation, G - up·spacing)` (the ground one spacing under the home's surface). Fills only where the generated surface dips below F within a (a home on a slope or by a ledge); a no-op on level ground.
4. Rim, when `rim_metres > 0`: N = `ceiling_divide_i64(710 * r, 113 * w)` edits (r = b + w, w = 3h, h rim height), edit i: `.Place`, `.Sphere`, radius Q = (w² + h²) / (2h), budget `max(i64)`, the material and tint of 3; centre: the ring point P = G + (right·cos θ + forward·sin θ)·r with θ = i · `ANGLE_UNITS_PER_TURN` / N, taken to the generated surface under it (S_i = `field_surface_under(generation, P, 0)`), lowered by Q − h along S_i's radial. Each is a spherical cap h high and 2w wide on the ground under the ring; neighbours overlap (spacing ≤ w), so the crest scallops by about 15 cm.

Steps 3 and 4 are skipped when the sample read for the material is air (`density <= 0`). With no crater (all zero) the list is empty and F = G.

Procedures (the file's header comment says the above in prose, linking `doc/architecture.md`, The field session):

- `CRATER_RIM_WIDTH_PER_HEIGHT :: 3`
- `Crater_Site :: struct { surface: World_Position, up: [3]i64, right, forward: [3]i64, floor: World_Position }`: G, its up, the tangent axes, F.
- `make_crater_site(surface: World_Position, heading: [3]i64, pitch_millimetres: int, crater: Planet_Crater) -> Crater_Site`: up from `normalize_fixed(surface)`, axes from `free_frame_at`, floor = surface − up·depth. Called by `enable_new_field_world`.
- `crater_bowl_radius(crater: Planet_Crater) -> i64`, `crater_rim_cap_radius(crater: Planet_Crater) -> i64`, `crater_rim_count(crater: Planet_Crater) -> int`: the formulas above, pure.
- `crater_rim_centre(generation: Planet_Generation, site: Crater_Site, crater: Planet_Crater, index, count: int) -> World_Position`: step 4's centre.
- `home_crater_edits(generation: Planet_Generation, site: Crater_Site, crater: Planet_Crater) -> []Field_Edit`: the list in order, in the temp allocator; empty without a crater.
- `crater_chunk_coordinates(edits: []Field_Edit, spacing_millimetres: int) -> []Field_Chunk_Coordinate`: every chunk of the box spanned by the union of the edits' `field_edit_bounds`, in z, y, x rising order, temp allocator. At most 3 per axis at 1000 mm and 6 at 333 mm for the shipped record (the bowl's 51 m box); chunks wholly in air generate fast (`planet_sample` skips the noise there).
- `dig_home_crater(seed: u64, planet: Planet, spacing_millimetres: int, site: Crater_Site) -> Field_World`: a scratch zero `Field_World`; each coordinate of `crater_chunk_coordinates` generated with `generate_field_chunk` and put straight into `world.chunks` (no wake, no light seeding); the edits applied with `apply_field_edit` in list order. The caller destroys it.
- `keep_home_crater(field: ^Field_Simulation, scratch: ^Field_World)`: for each coordinate of `scratch.edited_chunks` in `sorted_field_chunk_coordinates` order: `light_generated_field_chunk(chunk)` (the crater is open to the sky along every radial: the bowl is cut from above and the rim is a cap, so the generation's sky rule is exact), then `field.saved_chunks[coordinate] = {bytes = encode_field_chunk(chunk), state_hash = field_chunk_state_hash(chunk)}`. One log line: `world: the crater at the home is dug, %d chunks kept`.

Why `apply_field_edit` and not the queue (`Field_Simulation.edits`): a queue entry belongs to a player and its drain checks that player's tool tier and credits that player's inventory; the queue drains only inside a tick and only touches loaded chunks, and at creation no chunk is loaded (the set enters at the first tick from the players' feet, and a server may have no player). `apply_field_edit` is what the drain calls, with the same one sample order, and the edit order above is fixed, so every machine computes the same bytes. The drain's own path is untouched.

Stored as edits or regenerated from the record, the two options:

- Stored (chosen): the edited chunks go into `Field_Simulation.saved_chunks` at creation, exactly as a chunk a tick changed and that left the set. They are in `field.bin` (`encode_field_file`), in the join snapshot, and in the state hash (`field_state_hash` reads the kept chunks' hashes), and a chunk entering the set gets them through `apply_saved_field_chunk` like any changed chunk. A loaded world never reads the record, so editing `data/planets.sjson` cannot move a crater under a saved pod, and the save layout does not change. Cost: the scratch generation at creation, about 27 chunks at 1000 mm and up to 216 at 333 mm.
- Regenerated (rejected): `dig_home_crater` would run again on every load and every join from a recorded crater. This needs the crater in `Planet_Generation_Record` with a zero-means-none rule for old files. It repeats the scratch cost on every load. It reshapes the ground if a generation change (0189's terraces) moves G after the pod was saved. A second order of edit application would also have to agree with the chunks a tick has changed since (a player's dig in the crater), which the stored form gets for free.

### The pod in the crater (`entity_pod.odin`, `simulation_field.odin`)

- `place_pod(entities: ^Entities, machines: Machine_Registry, floor_position: World_Position, heading: [3]i64, pitch_millimetres: int) -> (frame: Frame_Id, ok: bool)`: `free_frame_at(floor_position, heading, pitch)`, `add_frame`, then `add_entity(entities, machines, pod, pod_origin(machine), POD_ROTATION, frame)` directly, as `place_on_bare_ground` does. `place_on_frame` would refuse the pod `Unsupported` with no foundation under its bottom row. `ok` is false only when the machines have no pod. No foundation is placed.
- `pod_origin(pod: Machine) -> World_Coordinate` returns `{-size.x / 2, 0, -size.z / 2}` for the rotated size: footprint centred on cell (0, 0, 0) (half a cell off for even sizes, as the pad's was), the bottom row on cell row 0, whose base is F's plane. The frame's up is the radial at F, the radial the level edits used, so the cell base and the floor plane coincide to within rounding.
- The door's heading: unchanged. The frame's forward is the yaw step of `field_home_heading` (towards the first spring) and `POD_ROTATION` turns the model's front to it.
- Removed: `POD_PAD_SIZE`, `POD_PAD_FIRST_CELL`, `pod_pad_cells`, `pod_pad_front_reach`, `FIELD_SPAWN_BEYOND_PAD_MILLIMETRES`, `cell_is_on_pod_pad`, `frame_holds_pod` (its only caller goes). The file's header comment describes the crater and the frame without a pad.
- `enable_new_field_world`, in this order: generation and `field_home_site`; `make_crater_site`; `dig_home_crater` then `keep_home_crater` then `destroy_field_world(&scratch)`; `place_pod(..., crater_site.floor, heading, pitch)`; every player `field_spawn_player`; the water planet as today. Its comment and the file header's "The home spawn" paragraph are updated.

### The spawn inside the cabin (`simulation_field.odin`, `machine.odin`)

- `pod_cabin_floor_centre(frame: Frame, origin: World_Coordinate, pod: Machine, rotation: u8) -> World_Position`: the record's first `open_cells` box is the cabin. Its bottom layer's two corner cells are rotated with `rotate_footprint_cell` (as `machine_open_cells` does), the centres of the two frame cells are averaged with `frame_cell_centre`, and the result is lowered half a pitch along the frame's up. For today's pod that is the floor point between the four cells x 3 to 4, z 2 to 3 of the box beside the bed, 0.5 m from the bed and the wall.
- `field_pod_spawn(entities: ^Entities, machines: Machine_Registry) -> (player: Field_Player, found: bool)`: the first alive entity of kind `.Pod` in `entities.foundations` in pool order, its frame (`find_frame`), feet at `pod_cabin_floor_centre` + up·`FIELD_SPAWN_CLEARANCE_MILLIMETRES`, `make_field_player(feet, frame.axes[FRAME_FORWARD])`, so the player faces the door (towards the spring). It reads the saved frame and pitch, so it is right for a loaded world, a joiner, an old save with a pad (feet on the pad's top), and a cabin floor the player dug (the feet drop).
- `field_spawn_player(entities: ^Entities, machines: Machine_Registry, seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Player`: `field_pod_spawn`, else `field_home_player`.
- `field_home_player(seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Player` loses the pitch parameter and the pad distance and becomes the fallback for content without a pod: feet the clearance above the generated surface at the home site, facing the spring.
- `make_field_session_player(state: ^Simulation_State, content, start)` takes the state by pointer (the call in `player_command.odin` passes `state` instead of `state^`) and calls `field_spawn_player`.
- `machine.odin`: new `validate_pod_cabin(definition: Machine_Definition, kind: Machine_Kind) -> string` beside `validate_open_cells`, after it in the validation chain. A pod needs at least one `open_cells` box, and the first starts at `y = 0` and spans at least 2 cells on x and on z (the 600 mm capsule needs 1 m at the 500 mm pitch). Message `machine %q is a pod whose first open_cells box is no cabin on its floor (y 0, 2 by 2 cells at least)`. Today's record passes. The `machines.sjson` comment over the pod says the first box is the cabin where players spawn.

### The pad in 0195 and 0201

- 0195 (pick up): `field_entity_is_placed_by_world` keeps only the pod rule (no item, or nil common) and drops the pad clause. In an old save, the pad's foundations become ordinary foundations. Those under the pod refuse with `Something_Stands_On_It`; the 64 round it pick up and return a foundation item each. This is named in the log as a behaviour change of old saves; it does not stop them loading. The `hud.odin` comment at the pick-up hint ("any but the pod and its pad") loses "and its pad".
- 0201 (bare ground): no refusal names the pad, and nothing in `machine_wear.odin` changes. The pod stays exempt (`stands_on_ground`, `.Pod` in `machine_wears`). Two consequences, both intended: a machine aimed at the pod's hull snaps onto the pod's frame and is refused `Unsupported` at row 0 (there is no foundation there any more), and a foundation snapped there is allowed; a machine aimed at the crater floor beside the pod goes the bare ground way, is flat by construction, and `new_frame_cells_meet_a_frame` keeps it out of the pod's cells.
- The benchmark (`benchmark_factory.odin`): `BENCHMARK_PAD_DISTANCE_MILLIMETRES` goes from 6000 to 24000, so its pad lies on the generated surface beyond the rim's 18 m reach and not in the air over the bowl. Its comment and `start_benchmark_field`'s say the player starts in the pod. `test_factory_benchmark` expects `pad + 1` foundations (the benchmark's pad and the pod).

### The dry spawn and the spring's heading

- The spring's heading is unchanged: it orients the pod's frame, and the player now faces the door, which faces it.
- 0180 is not on `main`. After this item its third bullet (the spawn on current ground, the pad distance from the saved pitch) is met by `field_pod_spawn`, which reads the saved frame. Its home pick must then compare the floor F (the generated surface minus `crater.depth_metres`), not the surface, against the sea level. That is a note for 0180's design; this item adds no runtime sea check. The test below holds the shipped home dry.
- The planet preview's walk start (0184, `start_planet_preview_walk`): after `field_surface_under`, the feet are lifted out of loaded ground by a new `lift_out_of_field_ground(world: ^Field_World, spacing_millimetres: int, feet: World_Position, limit: i64) -> World_Position` in `player_field.odin`. When `field_position_is_ground` holds at the feet, it marches along `radial_up` with `march_to_field_surface(..., inside = true, limit)` and returns the crossing; otherwise the feet unchanged. The limit is `metres_to_position_units(2 * MAXIMUM_CRATER_RIM_METRES)`. The clearance is added after the lift. Over the bowl the player starts above the floor and drops onto it; over the rim it starts on the rim. The preview starts at the pole, 560 m from the home, so its screenshot is unchanged.

### Tests

- `data_planet_test.odin`, `test_a_crater_record_out_of_bounds_is_refused`: each key just past each bound and the bowl and reach rules give their message; all zero passes; the shipped record passes.
- `simulation_field_crater_test.odin` (new):
  - `test_the_crater_edits_come_in_a_fixed_order`: the shipped record gives 1 + 2 + 32 edits: the bowl (Dig, Sphere, radius 25.5 m in units, centre F + up·S), the floor cut (Dig, Level, centre F), the fill (Place, Level), then 32 rim places with θ rising. A record with `rim_metres = 0` gives 3 edits. All zero gives none. Two calls give equal lists.
  - `test_the_crater_floor_is_flat_and_the_rim_raised`: at spacings 1000 and 333, `dig_home_crater` on the shipped planet and default seed at the three presets. `bare_ground_is_flat` holds over a frame at F (`free_frame_at(F, heading, 500)`) for 8 by 12 cells (0198's footprint, centred as `pod_origin`) at `bare_ground_flatness_millimetres` 250. The surface along the radial at F lies within an eighth of a spacing of F. At b/2 the surface lies below the generated surface by at least D/2. At ring radius r on eight bearings the surface lies above the generated surface by h/2 to h + one spacing. At b + 2w + 2 spacings on eight bearings the surface equals the generated one within an eighth of a spacing. Surfaces are read with `raycast_field` down the radial from 4 m above.
  - `test_the_shipped_crater_floor_lies_above_the_sea`: default seed, three presets: |F| exceeds the sea radius by at least 1 m.
- `entity_pod_test.odin`: `test_place_pod_lays_the_pad_and_the_pod_with_its_door_to_the_heading` becomes `test_place_pod_stands_the_pod_on_its_frame_with_no_pad`. The frame holds only the pod's cells (`frame_cell_count` equals the footprint volume), no entity of kind `.Foundation` exists, the origin's y is 0, cell row 0's base lies on the given point within 4 units, and the door faces the heading (the existing 8° check). The other pod tests keep their assertions with the floor now the test terrain under row 0. The walk test's comment ("stands inside on the pad") says it stands on the ground.
- `entity_frames_test.odin`: `test_the_pod_and_its_pad_refuse_a_pick_up` becomes `test_the_pod_refuses_a_pick_up` (the pod's cells only).
- `simulation_field_test.odin`:
  - `test_a_new_world_places_the_pod_and_players_spawn_at_its_door` becomes `test_a_new_world_sinks_the_pod_in_its_crater_and_players_spawn_in_the_cabin`. Pod found, origin from `pod_origin`, the frame's cell count the footprint's, no `.Foundation` entity. Cell (0, 0, 0)'s base stands on `make_crater_site(...).floor` within 4 units. The door faces the spring. The first player and a joiner (`add_player_entry`) stand at `field_pod_spawn`'s position: their cell (`world_to_frame_cell` a quarter pitch over the feet) is a cell of the first open box with y 0, they face the frame's forward, and they hold the starter kit. Then the set is staged (`stage_generated_field_set`) and 60 ticks run with no input: the player is on the ground (`Field_Player.on_ground`), still in a cabin cell, and its feet lie within a quarter pitch above F's plane.
  - `test_two_new_worlds_from_one_seed_agree`: two `start_field_test_session` on one seed. Their `field.saved_chunks` have the same keys and bytes, and `field_state_hash` and `simulation_state_hash` are equal at tick 0 and after 60 ticks with no input.
  - `test_a_save_round_trips_the_crater_as_changed_chunks`: a new world's `encode_field_file`, then `decode_field_file` into a fresh `Field_Simulation`, gives the same `saved_chunks` coordinates and bytes, and the crater coordinates all appear among them. After the set loads, a sample at F + up·one spacing is air and one at F − up·one spacing is ground.
  - `test_an_old_save_with_a_pad_still_loads`: the old layout is built by hand on a field test world. A free foundation at the site goes in through `place_free_foundation`, the 99 others at x, z from −4 to 5 through `place_on_frame`, and the pod at `{-4 + (10 - 6) / 2, 1, -4 + (10 - 6) / 2}` with `POD_ROTATION` through `add_entity`. The world round trips through the save path `test_a_field_world_save_round_trips` uses. Pod and 100 foundations load. `field_pod_spawn` puts the feet in a cabin cell of row 1, a clearance over the pad's top. A pad foundation outside the pod's footprint picks up and returns a foundation; one under the pod refuses `Something_Stands_On_It`.
- `machine_test.odin`, `test_a_pod_needs_a_cabin_on_its_floor`: a pod with no box, with a first box from y 1, and with a first box 1 cell wide is refused with the message; the shipped record passes.
- `player_field_test.odin`, `test_lift_out_of_field_ground_reaches_the_surface`: on the flat test terrain, feet one metre under the surface come out within an eighth of a spacing of it; feet in air are returned unchanged.
- `benchmark_test.odin`: the count `pad + 1`; its comment says the player starts in the pod.

### Docs

- `doc/content.md`, Planets: the `crater` key with its four keys, bounds and meanings, the derived rim width, the shipped values. The `home` bullet says the pod lies in the crater and players spawn in its cabin.
- `doc/content.md`, The pod: the crater and the frame on its floor, no pad; the first `open_cells` box is the cabin (`validate_pod_cabin`) and the spawn stands at the centre of its floor facing the door; the floor row is the crater floor, not foundations; old saves keep their pad as ordinary foundations.
- `doc/architecture.md`, The field session (the "The start" bullet): the crater's edits at creation through `apply_field_edit` outside the queue, kept as saved chunks, then the pod on the floor and the spawn in the cabin (`field_pod_spawn`).
- `doc/architecture.md`, The terrain field's brushes: the one writer outside the queue (creation only, before the first tick) and why.
- `doc/architecture.md`, Save format: the crater is saved chunks from tick 0, with no new key and no record field.
- `doc/architecture.md`, the benchmark bullet (line 327, "beside a pad of foundations"): the player in the pod, the pad 24 m ahead.
- `doc/code_map.md`, simulation: the new `simulation_field_crater.odin` line; `entity_pod.odin` ("the pod on its frame in the crater, `place_pod`"); `simulation_field.odin` ("the spawn in its cabin, `field_pod_spawn`").
- `data/planets.sjson`, the crater's comment; `data/machines.sjson`, the pod comment (the crater, the cabin box); `tools/check_dead_code.py`, the `place_pod` description ("the pod in its crater at the home").
- `doc/log/<date>.md`: the decision. Edits stored as saved chunks, not regenerated; `apply_field_edit` not the queue; old pads become ordinary foundations; the spawn in the cabin. Tags: field, pod, crater, m14.

### Hand-back lines that apply

- Memory a frame may draw from: the scratch `Field_World` is made and destroyed inside `enable_new_field_world`, before the session's first frame, and nothing drawn reads it, so no request is needed. The implementer confirms that no frame can run between `start_session` and the end of `start_field_world`.
- A number parsed from text range checked: `crater_problem` bounds every key, plus the bowl and reach rules.
- A changed save layout loads an old save: there is no layout change. `test_an_old_save_with_a_pad_still_loads` covers the old pad, and the pad's pick up change is named in the log.
- A list that grows without bound: the rim count and the scratch chunks are bounded by the record's bounds (rim N at most 74, scratch at most 6³ chunks at 333 mm).
- Tests never touch the state directory: the new tests use the existing field test sessions only.

### Open questions of the item, answered

- Queue or direct: direct `apply_field_edit` in a fixed order (above). The queue cannot run before chunks load and credits a player.
- Stored or regenerated: stored, as saved chunks (above).
- Floor flatness as a key: no. The level cut makes the floor an exact plane, so the key is the floor's radius. The test checks it against the 0201 tolerance over 0198's footprint.
- Where the pod sits in the crater: centred on F. The floor of 4 m covers both pods, and the bowl's 9° start is the ramp out; no separate ramp edit.
- "Half buried": the hull's base is 3 m below the surrounding generated ground and 4 m below the rim's crest. Today's 4 m hull shows its top metre.
- The spawn cell: the first open box's floor centre, a rule plus a load check, not a new key.
- 0198: its record must keep the cabin as the first `open_cells` box (`validate_pod_cabin` enforces the floor and the 2 by 2 cells). Its footprint fits the 4 m floor centred; an airlock 2 cells deep at the front stays on the floor.

### Questions to the main agent

1. Pre-crater saves: the 64 free pad foundations round the pod become pickable. The alternative is to keep `cell_is_on_pod_pad` as a legacy rule. I chose to drop it because the item drops `POD_PAD_SIZE`; say if the old pad should stay unpickable.
2. Faceting: a sphere dig sets whole samples to air, so the bowl and the rim are stepped at the sample spacing (1 m terraces at the default 1000 mm, walkable by the one-sample step) and only the floor is smooth. A crater term in the generation would be smooth and would show in the coarse levels of detail too (a saved chunk outside the set draws as generated ground from afar, as any edit does today). The item chose edits; confirm before implementation.
3. The scratch generation runs on the main thread at world creation: about 27 chunks at 1000 mm, up to 216 (about 45 MB transient) at 333 mm. It is not measured. If the New world screen stalls visibly at 333 mm, it moves to the field streaming workers, which this item does not do.

### Revision asked (main agent, 2026-10-03)

The crater becomes a term of the generation, not a list of edits: the specification above shows that edits on whole samples give a stepped bowl at the coarse spacing and never reach the distance meshes, which regenerate from the record, so a crater dug at creation pops in when the player nears it. Instead the relief gains a crater term at the home (0189's terms are its model): a radial profile of the distance from the home direction, a flat floor of `floor_radius_metres` at `depth_metres` below the home's surface height, a smooth bowl out to `radius_metres`, a rim of `rim_metres` falling back to the surface, evaluated for every sample at every level with the rest of the relief, integer only. No scratch world, no saved chunks, no main thread cost, no save layout change; an old save's unedited chunks regenerate with the crater under its old pad, which stays as entities and is named in the log as the behaviour change. The rest of the specification (the record keys, the pod on the floor with no pad, the spawn inside the cabin, the pad's removal from 0195 and 0201, the dry spawn testing the floor) stands. Question 1: the old pad's foundations become pickable, yes. Question 2: generation, as above. Question 3: moot.
