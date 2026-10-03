# 0199: The pod sits in an impact crater, no pad

Status: implementing (2026-10-03, worktree item/0199; user, 2026-10-03: "the pod shouldn't come with foundation, it should just be buried directly in the ground inside an impact crater"; after 0198)

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

## Specification (design, 2026-10-03, revised for the generation term)

Designed against `main` at 2411594 plus the uncommitted 0189 tree (`surface_relief` with `long_octave_relief`, `basin_relief`, `terrace_height`, `ledge_relief` in `generation_planet.odin`; `Relief_Shape` in `data_planet.odin`; `relief_shape` in `Planet_Generation_Record`), which lands first and is the model for the term. 0198 has no approved specification yet: this item is designed against today's 6 by 6 by 8 pod and sizes the crater for 0198's 8 by 12 by 8 cells (what 0198 must keep is under Open questions). 0180 is not on `main`; what changes for it is under The dry spawn. Integer only throughout: position units (`POSITION_UNITS_PER_METRE` 4096), a fixed point fraction `CRATER_ONE :: 65536`.

### The crater record (`data/planets.sjson`, `data_planet.odin`)

- New type in `data_planet.odin`: `Planet_Crater :: struct { radius_metres, depth_metres, floor_radius_metres, rim_metres: int }`, and `crater: Planet_Crater` on `Planet` after `home`. Required in the file (not `OPTIONAL_PLANET_KEY`); `missing_planet_key_problem` checks its four keys as it checks `home` (`missing_struct_key(Planet_Crater, …)`, message `planets[%d].crater is missing %s`).
- Meaning, as heights of the relief (above the radius) along the radial, against the distance from the home direction: a flat floor out to `floor_radius_metres` at `depth_metres` below the home's uncratered relief; a smooth bowl rising from the floor's edge to the crest at `radius_metres`; a rim `rim_metres` high at the crest, falling back to the surrounding relief over `CRATER_RIM_FALL_PER_HEIGHT` (6) times its height outwards. The reach is `radius_metres + 6 * rim_metres`.
- Bounds, new `crater_problem(crater: Planet_Crater) -> string` called from `planet_problem` after `home_problem`, messages in the file's style (`crater.<key> %d is outside %d to %d`):
  - all four zero is no crater (the code-built test planets); otherwise
  - `radius_metres` `MINIMUM_CRATER_RADIUS_METRES` (4) to `MAXIMUM_CRATER_RADIUS_METRES` (24);
  - `depth_metres` 1 to `MAXIMUM_CRATER_DEPTH_METRES` (8);
  - `floor_radius_metres` 2 to `radius_metres - 2`;
  - `rim_metres` 0 to `MAXIMUM_CRATER_RIM_METRES` (4);
  - the reach at most `MAXIMUM_CRATER_REACH_METRES` (24), message `crater reaches %d m, more than %d`;
  - the bowl's steepest slope, 1.5 (depth + rim) / (radius − floor_radius) for the smoothstep, at most 1 (45°, under the 60° walkable angle): `3 * (depth + rim) <= 2 * (radius - floor_radius)`, message `crater bowl of %d m over %d m is steeper than 45 degrees`.
- `generation_planet_veins.odin` gains `#assert(MAXIMUM_CRATER_REACH_METRES < PLANET_VEIN_MINIMUM_DISTANCE_METRES - PLANET_VEIN_MAXIMUM_RADIUS_METRES)` (24 < 25), so the crater never reshapes a starter outcrop.
- Shipped in `home`: `crater = {radius_metres = 12, depth_metres = 3, floor_radius_metres = 4, rim_metres = 1}`, a comment naming each. Derived: the bowl climbs 4 m over 8 m (steepest 37°, flat at both ends), the rim falls 1 m over 6 m (steepest 14°), reach 18 m. The 4 m floor holds today's pod (corners 2.1 m out) and 0198's (4 by 6 m, corners 3.6 m out); 0198's airlock opens onto floor that then rises with zero slope at its edge.
- Recorded: `Planet_Generation_Record` gains `crater: Planet_Crater` and `crater_recorded: bool` beside `home`/`home_recorded`, because a loaded world regenerates its ground from the record and a data edit must not move a crater under a saved pod. `planet_generation_record` sets both; `make_recorded_planet` copies the crater when `crater_recorded`; `resolve_world_planet` gives a recorded file without it the data planet's crater with one log line, as it does for the home: `world: the world file records no crater, it takes the crater of %q from %s`. `planet_generation_record_problem` checks it through `planet_problem` as today. `world.sjson` gains the two keys like the home before it; no format version step and no binary layout change.

### The crater term of the relief (`generation_planet.odin`)

Where: `surface_relief` is the one place every reader of the generated ground goes through (`planet_sample` for every chunk and every coarse grid, `field_surface_under`, `planet_spring_sample`, the preview's pole). Its present body (0189's octaves, basins, terraces and ledges) is renamed `uncratered_relief(generation, point) -> i64` unchanged, and `surface_relief` becomes `crater_relief(generation.crater, crater_distance(generation, point), uncratered_relief(generation, point))`. So the crater reaches every level of detail through the same `planet_sample` call, reads no extra noise sample (the distance is a vector difference and, within the reach only, one `integer_square_root`), and the field, the coarse meshes, the sea fill and the springs agree.

New fields on `Planet_Generation`, set in `make_planet_generation`:

- `crater: Crater_Term`, with `Crater_Term :: struct { home: [3]i64, floor_height: i64, floor_radius, radius, reach, depth, rim: i64 }`, all lengths in position units; `home` is `fixed_scale(planet_home_direction(planet.home), radius)` (the home on the sphere); `floor_height` is `uncratered_relief(generation, home) - depth` clamped to at least `-metres_to_position_units(MAXIMUM_RELIEF_METRES)`; zero `reach` is no crater. One extra relief evaluation per `make_planet_generation`, none per sample.

Procedures (pure, integer):

- `crater_distance(generation: Planet_Generation, point: [3]i64) -> i64`: the chord from `crater.home` to the point on the sphere in position units, `reach + 1` without computing a root when the squared chord exceeds `reach²` (the early out every sample but the home's few takes). Over 24 m on a 4 km planet the chord is the arc to within 0.1 mm.
- `crater_smoothstep(fraction: i64) -> i64`: `fraction² (3 CRATER_ONE − 2 fraction) / CRATER_ONE²` for a fraction clamped to 0 to `CRATER_ONE`; zero slope at both ends.
- `crater_relief(term: Crater_Term, distance, relief: i64) -> i64`, with `a` floor radius, `b` radius, `W = reach − b`, `s = crater_smoothstep((distance − a) · CRATER_ONE / (b − a))`:
  - no crater or `distance >= reach`: `relief`;
  - `distance <= b`: `relief + (CRATER_ONE − s) · (floor_height − relief) / CRATER_ONE + rim · s / CRATER_ONE` — exactly `floor_height` on the floor (s = 0), the surrounding relief plus the rim's crest at b (s = 1), a smooth blend between, so a home on a slope gets a level floor and a bowl that meets the slope;
  - `b < distance < reach`: `relief + rim · (CRATER_ONE − crater_smoothstep((distance − b) · CRATER_ONE / W)) / CRATER_ONE`;
  - the result clamped to at most `+metres_to_position_units(MAXIMUM_RELIEF_METRES)`.
- The bound against `MAXIMUM_RELIEF_METRES`: the bowl is a blend of `floor_height` and the local relief, both within ±34 m (the floor by its clamp), and the rim's raise is clamped at +34 m, so `planet_sample`'s skip ranges, the light's sky top (`world_field_light.odin`), the coarse margin (`world_field_lod.odin`) and the globe (`render_field.odin`) hold unchanged; no data check is added to `relief_problem`. The clamps engage only at a home within 3 m of the deepest basin or within 1 m of the highest relief, which the dry home never is; a test holds the shipped home clear of both.
- The file's header comment (line 17, "at most MAXIMUM_RELIEF_METRES in all") names the crater term and its clamps.

Gone from the first version: the scratch world, the saved chunks at creation, the `apply_field_edit` path, `simulation_field_crater.odin` and the main thread cost.

### The pod in the crater (`entity_pod.odin`, `simulation_field.odin`)

- The floor is read from the term: `field_home_site` is unchanged and its surface (`field_surface_under` at the home) now is the crater floor, `floor_height` above the radius, since `surface_relief` includes the term. No new site procedure.
- `place_pod(entities: ^Entities, machines: Machine_Registry, floor_position: World_Position, heading: [3]i64, pitch_millimetres: int) -> (frame: Frame_Id, ok: bool)`: `free_frame_at(floor_position, heading, pitch)`, `add_frame`, then `add_entity(entities, machines, pod, pod_origin(machine), POD_ROTATION, frame)` directly as `place_on_bare_ground` does (`place_on_frame` would refuse the pod `Unsupported` with no foundation under its bottom row). `ok` is false only when the machines have no pod. No foundation is placed.
- `pod_origin(pod: Machine) -> World_Coordinate` returns `{-size.x / 2, 0, -size.z / 2}` for the rotated size: centred on cell (0, 0, 0) (half a cell off for even sizes, as the pad's was), the bottom row on cell row 0, whose base is the floor. The frame's up is the radial at the home; the floor is a sphere of constant radius, 0.8 mm below the frame's plane at 3.6 m on an 8 km planet.
- The door's heading: unchanged, the yaw step of `field_home_heading` towards the first spring, the model's front turned to it by `POD_ROTATION`.
- Removed: `POD_PAD_SIZE`, `POD_PAD_FIRST_CELL`, `pod_pad_cells`, `pod_pad_front_reach`, `FIELD_SPAWN_BEYOND_PAD_MILLIMETRES`, `cell_is_on_pod_pad`, `frame_holds_pod`. `find_foundation_machine` is no longer needed by `place_pod`. The file's header comment describes the crater and the frame without a pad.
- `enable_new_field_world`: as today but `place_pod(..., site, heading, pitch)` with no pad and every player through `field_spawn_player`. Its comment and the file header's "The home spawn" paragraph are updated.

### The spawn inside the cabin (`simulation_field.odin`, `machine.odin`)

Unchanged from the first version:

- `pod_cabin_floor_centre(frame: Frame, origin: World_Coordinate, pod: Machine, rotation: u8) -> World_Position`: the record's first `open_cells` box is the cabin; its bottom layer's two corner cells rotated with `rotate_footprint_cell` (as `machine_open_cells` does), the mean of their `frame_cell_centre`s lowered half a pitch along the frame's up. For today's pod, the floor point between cells x 3 to 4, z 2 to 3 beside the bed, 0.5 m from the bed and the wall.
- `field_pod_spawn(entities: ^Entities, machines: Machine_Registry) -> (player: Field_Player, found: bool)`: the first alive entity of kind `.Pod` in `entities.foundations` in pool order, its frame (`find_frame`), feet at `pod_cabin_floor_centre` plus up · `FIELD_SPAWN_CLEARANCE_MILLIMETRES`, `make_field_player(feet, frame.axes[FRAME_FORWARD])`: facing the door, towards the spring. It reads the saved frame and pitch, so it holds for a loaded world, a joiner, an old save with a pad (feet on the pad's top) and a cabin floor the player dug (the feet drop).
- `field_spawn_player(entities: ^Entities, machines: Machine_Registry, seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Player`: `field_pod_spawn`, else `field_home_player`.
- `field_home_player(seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Player` loses the pitch parameter and the pad distance: the fallback for content without a pod, the clearance above the generated surface at the home site (the crater floor), facing the spring.
- `make_field_session_player(state: ^Simulation_State, content, start)` takes the state by pointer (the call in `player_command.odin` passes `state`, not `state^`) and calls `field_spawn_player`.
- `machine.odin`: `validate_pod_cabin(definition: Machine_Definition, kind: Machine_Kind) -> string` after `validate_open_cells` in the chain: a pod needs an `open_cells` box whose first starts at `y = 0` and spans at least 2 cells on x and on z (the 600 mm capsule needs 1 m at the 500 mm pitch); message `machine %q is a pod whose first open_cells box is no cabin on its floor (y 0, 2 by 2 cells at least)`. Today's record passes. The `machines.sjson` comment over the pod names the first box the cabin where players spawn.

### The pad in 0195 and 0201

- 0195: `field_entity_is_placed_by_world` keeps only the pod's rule (no item, or no common data) and drops the pad clause. In an old save the pad's foundations become ordinary foundations: those under the pod refuse with `Something_Stands_On_It`, the 64 round it pick up and return a foundation each (decided by the main agent). The `hud.odin` comment at the pick up hint loses "and its pad".
- 0201: no refusal names the pad and `machine_wear.odin` does not change; the pod stays exempt (`stands_on_ground`, `.Pod` in `machine_wears`). A machine aimed at the pod's hull snaps onto the pod's frame and is refused `Unsupported` at row 0 (no foundation there any more), a foundation snapped there is allowed; a machine aimed at the crater floor goes the bare ground way, flat by construction, and `new_frame_cells_meet_a_frame` keeps it out of the pod's cells.
- The benchmark (`benchmark_factory.odin`): `BENCHMARK_PAD_DISTANCE_MILLIMETRES` 6000 → 24000, so its pad lies on the generated surface beyond the reach (18 m) instead of on the bowl's wall; its comment and `start_benchmark_field`'s say the player starts in the pod. `test_factory_benchmark` expects `pad + 1` foundations.

### Saves

- No binary layout change. `world.sjson` gains `crater` and `crater_recorded` in the planet generation record, read as the home's were (above).
- An old save (written before this item) takes the data's crater with one log line. Its unedited chunks regenerate with the crater: the ground under the old pad drops to the floor, the pad and the pod stay where they were saved as entities, standing 3 m over the floor on their frame; a chunk the old world changed keeps its saved terrain, so an old dig beside the pad meets the regenerated bowl at a chunk border. The spawn stays on the old pad (`field_pod_spawn`). This behaviour change is named in the log; old saves load and play.
- `field_saved_chunk`'s comparison on unload and the sea fill read the generation with the crater, so a crater chunk nobody edited is never saved.

### The dry spawn and the spring's heading

- The spring's heading is unchanged: it orients the pod's frame; the player now faces the door, which faces it.
- 0180 (not on `main`): its third bullet (spawn on current ground, the pad distance from the saved pitch) is met by `field_pod_spawn`. Its home pick must test the floor, which `field_surface_under` at the candidate now returns only at the chosen home; the pick compares `uncratered_relief(candidate) - depth` with the sea level. A note for 0180's design; this item adds no runtime sea check, and the test below holds the shipped home dry.
- The planet preview's walk start (0184) needs no change: `field_surface_under` already returns the bowl, the floor or the rim from the generation. The preview starts at the pole, 560 m from the home, so its screenshot is unchanged.

### Tests

- `data_planet_test.odin`, `test_a_crater_record_out_of_bounds_is_refused`: each key just past each bound, the reach and the slope rules, give their message; all zero and the shipped record pass.
- `generation_planet_record_test.odin`, `test_a_world_file_without_a_crater_takes_the_datas`: a record with `crater_recorded` false resolves to the data's crater; a recorded crater survives `make_recorded_planet` when the data's differs.
- `generation_planet_test.odin`:
  - `test_the_crater_relief_profile`: `crater_relief` on a term with the shipped values and a floor height of 0: for any relief (−20 m, 0, +5 m) it returns 0 at distances 0 and `a`; it rises monotonically from `a` to `b` for a relief of 0 and reaches `rim` at `b`; it returns the relief plus nothing from `reach` on; its outward slope between samples a centimetre apart never exceeds 1 (45°); the zero term returns the relief.
  - `test_the_crater_floor_is_flat_in_the_generated_field`: shipped planet, default seed, three presets, spacings 1000 and 333: chunks round the home from `generate_field_chunk` in a test `Field_World`; `bare_ground_is_flat` over a frame at the home site (`free_frame_at(site, heading, 500)`) for 8 by 12 cells centred as `pod_origin` holds at 250 mm (`bare_ground_flatness_millimetres`); the surface down the radial (`raycast_field` from 4 m above) at the home lies within an eighth of a spacing of `radius + floor_height`.
  - `test_the_rim_stands_above_the_surrounding_surface`: same set up, eight bearings: at `b` the field's surface lies above `uncratered_relief` by `rim` within one spacing; at `reach` plus two spacings it equals the uncratered surface within an eighth of a spacing.
  - `test_the_crater_shows_at_every_level`: for each level of `level_distances_metres` (`FIELD_LEVEL_COUNT`), `generate_field_grid` for the node holding the home: the grid's sample nearest one level step above the floor is air and one level step below is ground, and the grid's sample at the uncratered surface minus 2 m at a quarter of `b` is air (the bowl is in the coarse mesh).
  - `test_the_shipped_crater_floor_lies_above_the_sea`: default seed, three presets: `floor_height` exceeds `sea_level_metres` by at least 1 m and neither clamp engages.
  - `test_the_shaped_home_generates_identical_bytes_twice` (0189) gains a chunk at the home, so two generations from one seed agree on the crater; `test_two_new_worlds_from_one_seed_agree` below adds the session.
- `entity_pod_test.odin`: `test_place_pod_lays_the_pad_and_the_pod_with_its_door_to_the_heading` becomes `test_place_pod_stands_the_pod_on_its_frame_with_no_pad`: the frame holds only the pod's cells (`frame_cell_count` the footprint volume), no entity of kind `.Foundation`, the origin's y is 0, cell row 0's base on the given point within 4 units, the door to the heading (the existing 8° check). The other pod tests keep their assertions with the test terrain under row 0; the walk test's comment says it stands on the ground.
- `entity_frames_test.odin`: `test_the_pod_and_its_pad_refuse_a_pick_up` becomes `test_the_pod_refuses_a_pick_up`.
- `simulation_field_test.odin`:
  - `test_a_new_world_places_the_pod_and_players_spawn_at_its_door` becomes `test_a_new_world_sinks_the_pod_in_its_crater_and_players_spawn_in_the_cabin`: pod found, origin `pod_origin`, the frame's cell count the footprint's, no `.Foundation`; cell (0, 0, 0)'s base on `field_home_site`'s surface within 4 units and that surface `depth_metres` (within an eighth of a spacing) below `uncratered_relief` at the home; the door to the spring; the first player and a joiner (`add_player_entry`) at `field_pod_spawn`'s position, their cell (`world_to_frame_cell` a quarter pitch over the feet) a cell of the first open box with y 0, facing the frame's forward, with the starter kit; then `stage_generated_field_set` and 60 ticks with no input: `Field_Player.on_ground`, still in a cabin cell, the feet within a quarter pitch above the floor.
  - `test_two_new_worlds_from_one_seed_agree`: two `start_field_test_session` on one seed: `simulation_state_hash` equal at tick 0 and after 60 ticks with no input.
  - `test_an_old_save_with_a_pad_still_loads`: the old layout by hand on a field test world (a free foundation at the site through `place_free_foundation`, the 99 others at x, z from −4 to 5 through `place_on_frame`, the pod at `{-4 + (10 - 6) / 2, 1, -4 + (10 - 6) / 2}` with `POD_ROTATION` through `add_entity`), its world file's record with `crater_recorded` false, round tripped through the save path `test_a_field_world_save_round_trips` uses: the pod and 100 foundations load, the record takes the data's crater, `field_pod_spawn` puts the feet in a cabin cell of row 1 a clearance over the pad's top, a pad foundation outside the pod's footprint picks up and returns a foundation, one under the pod refuses `Something_Stands_On_It`.
- `machine_test.odin`, `test_a_pod_needs_a_cabin_on_its_floor`: a pod with no box, with a first box from y 1, with a first box 1 cell wide, each refused with the message; the shipped record passes.
- `benchmark_test.odin`: the count `pad + 1`; its comment says the player starts in the pod.

### Docs

- `doc/content.md`, Planets: the `crater` key, its four keys with bounds and meaning, the reach and slope rules, the shipped values; the `home` bullet says the pod lies on the crater floor and players spawn in its cabin.
- `doc/content.md`, The pod: the crater and the frame on its floor, no pad; the first `open_cells` box is the cabin (`validate_pod_cabin`) and the spawn stands at the centre of its floor facing the door; old saves keep their pad as ordinary foundations over the regenerated crater.
- `doc/architecture.md`, World generation: the crater term (`uncratered_relief`, `crater_relief`, the distance's early out, the clamps against `MAXIMUM_RELIEF_METRES`, every level through `planet_sample`).
- `doc/architecture.md`, The field session ("The start"): the pod on the floor read from the generation, the spawn in the cabin (`field_pod_spawn`).
- `doc/architecture.md`, Save format: `crater` and `crater_recorded` in the planet generation record, a file without them taking the data's crater.
- `doc/architecture.md`, the benchmark bullet ("beside a pad of foundations"): the player in the pod, the pad 24 m ahead.
- `doc/code_map.md`: `entity_pod.odin` ("the pod on its frame in the crater, `place_pod`"), `simulation_field.odin` ("the spawn in its cabin, `field_pod_spawn`"), `generation_planet.odin` (the crater term).
- `data/planets.sjson` the crater's comment; `data/machines.sjson` the pod comment (the crater, the cabin box); `tools/check_dead_code.py` the `place_pod` description ("the pod in its crater at the home").
- `doc/log/<date>.md`: the decision (the crater a term of the relief, recorded; no pad; the spawn in the cabin; old saves: the crater regenerates under the old pad, which stays as entities, and the pad's foundations become pickable). Tags: field, pod, crater, generation, m14.

### Hand-back lines that apply

- A number parsed from text range checked: `crater_problem` bounds every key plus the reach and slope rules; the record's crater passes the same check on load (`planet_generation_record_problem`).
- A changed save layout loads an old save: `world.sjson`'s new keys default through `crater_recorded` with one log line; `test_an_old_save_with_a_pad_still_loads`; the behaviour change is named in the log.
- Tests never touch the state directory: the new tests use the existing field test sessions and in-memory worlds only.
- Not applicable: no memory freed under a frame, no file written, no shared budget, no growing list, no UI audit case.

### Open questions of the item, answered

- Edits or generation: generation (the main agent's revision): smooth at every spacing, in every level's mesh, no creation cost.
- Floor flatness as a key: no; the term makes the floor a constant height, so the key is the floor's radius, and the test checks it against 0201's tolerance over 0198's footprint.
- Where the pod sits: centred on the home; the bowl's zero slope at the floor's edge is the ramp out, no separate ramp.
- "Half buried": the hull's base is 3 m below the surrounding ground and 4 m below the rim's crest; today's 4 m hull shows its top metre.
- The spawn cell: the first open box's floor centre, a rule plus a load check, not a new key.
- The distance unit: position units, not whole metres as the revision suggested: a profile on whole metres would step the bowl by up to 0.5 m per metre of distance, visible at 333 mm; position units cost the same.
- 0198: its record keeps the cabin as the first `open_cells` box (`validate_pod_cabin` enforces the floor and 2 by 2 cells); its footprint fits the 4 m floor centred.

### Questions to the main agent

- None blocking. One to confirm: the crater is recorded in `Planet_Generation_Record` (with `crater_recorded`) so a data edit cannot move a saved world's crater; the revision did not say, and without it an edit of `data/planets.sjson` would reshape the ground under every saved pod.

### Revision asked (main agent, 2026-10-03)

The crater becomes a term of the generation, not a list of edits: the specification above shows that edits on whole samples give a stepped bowl at the coarse spacing and never reach the distance meshes, which regenerate from the record, so a crater dug at creation pops in when the player nears it. Instead the relief gains a crater term at the home (0189's terms are its model): a radial profile of the distance from the home direction, a flat floor of `floor_radius_metres` at `depth_metres` below the home's surface height, a smooth bowl out to `radius_metres`, a rim of `rim_metres` falling back to the surface, evaluated for every sample at every level with the rest of the relief, integer only. No scratch world, no saved chunks, no main thread cost, no save layout change; an old save's unedited chunks regenerate with the crater under its old pad, which stays as entities and is named in the log as the behaviour change. The rest of the specification (the record keys, the pod on the floor with no pad, the spawn inside the cabin, the pad's removal from 0195 and 0201, the dry spawn testing the floor) stands. Question 1: the old pad's foundations become pickable, yes. Question 2: generation, as above. Question 3: moot.

### Approval (main agent, 2026-10-03)

Approved as revised. The crater is recorded in the world record like the relief octaves, so a data edit never reshapes a saved world; an old record takes the data's crater with one log line, as specified.
