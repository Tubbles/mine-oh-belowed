# 0271: The impact digs the crater

Status: designed (2026-10-05)

## Goal

A new world's ground is whole until the pod hits; the bang digs the crater, the bowl and its rim, out of the natural relief at the hit tick (0270's `field_arrival_hit_tick`, 60 ticks before the landing), on every machine alike. Old worlds keep the crater their generation baked. Today the generation bakes the planet record's crater at the home (0199) and the pod is placed on its floor (0221).

## Controls

No binding changes.

## Change

- The planet record's crater keys become the impact's shape; the generation no longer bakes it for a new world (a world records whether its crater is baked, so an old world loads as before).
- A sample pass of the field at the hit tick, before 0270's rest and bed run in the same tick, and on every chunk that enters the set after it: the baked generation's sample written wherever it differs from the whole one, in the simulation, deterministic, so the dug field equals the crater the generation baked. The trees' clearing rule keeps the reach empty, so nothing is felled. Built on 0270's specification (`rest_field_pod`, the hit tick), designed against it.
- The home search of 0180 runs on the natural relief; the pod frame is placed at generation where the crater's floor will be, the ground whole round it until the hit, and rests on the dug floor; the streaming meshes the reach finest from the first frame as today.
- Docs: `doc/content.md` (Planets, the crater), `doc/architecture.md` (The field session, The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the field at the home before and after the hit tick differs by the crater's profile and nowhere else; two machines hash alike through it; a join after the landing carries the crater; an old save loads unchanged.
- The couch and the phone: a new world, the ground whole from the chair, the crater after the bang.

## Specification (design, 2026-10-05)

Designed against 0270's specification and decisions on `main` (`rest_field_pod`, `field_arrival_hit_tick`, `Pod_Rest_Tuning.settle_ticks`, the landing that rests at or before the hit). Its worktree was read as it stood and matches those names. The generation is integer only (`crater_relief`, `crater_distance`, `integer_square_root`, value noise on `generation_seed` hashes) and reads nothing but the seed, the planet and the spacing, so the dig, which calls the same procedures, is the same on every machine.

### The seam: a sample pass, not a brush

A `Field_Edit` cannot carry the profile (a level brush is one plane, a sphere brush digs to air), and the baked crater also moves the strata (topsoil lines the bowl, the stone to deep stone face 40 m down follows the surface). The dig is a sample pass that writes, through `field_world_set_sample`, the baked generation's sample wherever it differs from the whole one: the water, the light, the dirty and edited chunks, the save and the hash follow as for any edit, and the field after it equals a baked generation's exactly. Chunks not loaded at the hit (the stone face below the set, a reach past the set at 333 mm) take the same pass when they enter the set later.

### Record and generation

- `Planet_Generation_Record.crater_at_impact: bool` after `crater_recorded`: true for a world made since 0271, whose crater the hit digs. A `world.sjson` without the key reads false and generates the crater baked as before, so no remap and no log line. `planet_generation_record` copies it from the planet. `resolve_world_planet`, in its `!planet_generation_is_recorded` branch, sets `record.crater_at_impact = !loading` (a new world true, a file from before 0179 false). `make_recorded_planet` copies it.
- `Planet.crater_at_impact: bool` tagged `json:"-"`, last field, commented as set only by `make_recorded_planet`. `missing_struct_key` skips a field whose key is `"-"`, so `planets.sjson` neither needs nor can set it (its key matches no file key, so the strict assignment refuses one).
- `Planet_Generation.crater_baked: bool`: `!planet.crater_at_impact` in `make_planet_generation`. The term `crater` is built as today either way.
- `surface_relief`: `uncratered_relief`, passed through `crater_relief` only when `crater_baked`.
- `baked_planet_generation :: proc(generation: Planet_Generation) -> Planet_Generation`: the copy with `crater_baked` true, the ground as it stands once the crater is dug.
- `field_home_site` reads `field_surface_under(baked_planet_generation(generation), ...)`: the pod is placed at the future floor. `field_home_player` (no pod) keeps the generation as given. The home search is unchanged: `planet_home_floor_height` already reads `uncratered_relief` less the depth.
- `loop_planet_preview.odin` and `loop_planet_preview_runs.odin`: the four `make_planet_generation` calls are wrapped in `baked_planet_generation`, since the preview's world has no fall and its chunks are dug as they enter.
- The benchmark plays the data's planet (`crater_at_impact` false), baked as today.

### The pass (generation_planet.odin, world_field_edit.odin)

- `planet_sample` splits without a change of result: `planet_sample_shortcut :: proc(generation: Planet_Generation, position: World_Position) -> (sample: Field_Sample, distance: i64, on_sphere: [3]i64, needs_relief: bool)` (the early outs, and the distance and projection when none applies) and `planet_sample_at_relief :: proc(generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64, relief: i64) -> Field_Sample` (the tail from `surface :=`).
- `impact_crater_sample :: proc(generation: Planet_Generation, position: World_Position) -> (baked: Field_Sample, changed: bool)`: false past the shortcut or at `crater_distance >= reach`. Else one `uncratered_relief` `u`, `baked = planet_sample_at_relief(..., crater_relief(term, distance, u))`, `changed = baked != planet_sample_at_relief(..., u)`. One relief evaluation per sample in the reach.
- `impact_crater_reaches :: proc(generation: Planet_Generation, position: World_Position) -> bool`: the position projected onto the sphere lies within the term's reach (the trees).
- `dig_impact_crater_in_chunk :: proc(world: ^Field_World, generation: Planet_Generation, coordinate: Field_Chunk_Coordinate) -> bool` (world_field_edit.odin): nothing when the chunk is not loaded or its box (`field_node_box(field_chunk_node(coordinate), spacing)`) lies farther from `term.home` than `term.reach + MAXIMUM_RELIEF_METRES + DEEP_STONE_DEPTH_METRES` plus two spacings. Else every sample in index order whose `impact_crater_sample` changed and whose current sample is not the baked one is set to it (`field_world_set_sample`). Returns whether it wrote one. The current sample is compared so a second pass over a dug chunk writes nothing.

### The simulation (simulation_arrival.odin, simulation_field_chunk_set.odin, field_trees.odin)

- `impact_crater_dug :: proc(planet: Planet, arrival: Field_Arrival, tick: u64, settle_ticks: int) -> bool`: `planet.crater_at_impact && !field_arrival_skippable(arrival, tick, settle_ticks)`. True from the hit tick on, after a Skip, and from the start of a world without a fall.
- `dig_impact_crater :: proc(state: ^Simulation_State, content: Simulation_Content)`: nothing unless `state.world.planet.crater_at_impact`. Then `dig_impact_crater_in_chunk` over `sorted_field_chunk_coordinates(world.chunks)` with the world's generation (`field.world.water_planet.generation`, the one `field_tree_generation` returns), then `fell_trees_in_impact_crater`, then `update_field_sky_after_edits`. Called as the first statement of `rest_field_pod`, before `find_pod`, so it runs once per world in the hit tick (or the Skip's), before the pose and the bed, and also without a pod.
- `fell_trees_in_impact_crater :: proc(state: ^Simulation_State, content: Simulation_Content)` (field_trees.odin): every tree of `field_trees_near(field, term.home, term.reach + field_tree_widest_reach(content.field))` whose base `impact_crater_reaches` goes into `felled_trees`, without yield. Idempotent.
- `update_simulated_field_chunks(state, content)` (its caller and the two test calls pass the content): `dig := impact_crater_dug(state.world.planet, field.arrival, state.tick, content.field.pod_rest.settle_ticks)`. `insert_field_chunk_arrival(field, chunk, dig) -> bool` notes `chunk.coordinate in field.saved_chunks` before `apply_saved_field_chunk` and, when `dig` and it had none, runs `dig_impact_crater_in_chunk` after the insert. When any insert dug: `fell_trees_in_impact_crater`, `update_field_sky_after_edits`. `restore_arrived_field_set` is unchanged: a loaded set is the saving machine's, dug already.
- Cost: the pass runs the relief once per sample in the reach's band on the tick's thread, at most what generating those samples costs. Not measured (see the questions).

### What follows from it

- Arrival and presentation: the pod frame is where 0269 and 0270 expect it, so `arrival_start_metres` above the floor is unchanged. The ground stays whole through the descent. The dug chunks remesh in the frames after the hit (eight finest submissions a frame), and the coarse nodes over them follow `mark_edited_coarse_nodes`. The shipped reach lies inside the simulated set at every spacing (two chunks, 21.3 m at 333 mm, the chair 1.3 m from the home).
- Save: before the hit the record says `crater_at_impact` and the chunks are whole, so the load digs at the hit. After it, the dug chunks are changed chunks and saved whole (`encode_field_file`, `field_saved_chunk` against the whole generation). The join snapshot carries both, and `field_state_hash` covers them.
- Trees: `trees_problem` keeps `clearing_metres >= reach`, so the shipped and any valid planet has no tree in the reach. The felling acts on code built planets (the test) until the rule changes (question 1).

### Tests

A shared helper `expect_field_holds_the_crater(t, state, except_centre, except_radius)` in simulation_arrival_test.odin: every loaded sample farther than `except_radius` from the centre equals `planet_sample(baked_planet_generation(world generation), ...)` on density, material and tint.

- generation_planet_test.odin `test_the_impact_dig_makes_the_baked_crater`: at 333, 500 and 1000 mm, the shipped planet with `crater_at_impact` true: a `Field_World` of the chunks whose box meets 20 m round the home, generated whole, then `dig_impact_crater_in_chunk` on each in coordinate order: every sample equals the baked generation's, a chunk whose box lies past the bound reports false, a second pass reports false, and the floor at the home lies where `test_the_crater_floor_is_flat_in_the_generated_field` finds it, with its tolerance. Before the dig every sample equals `planet_sample` of the whole generation and the surface at the home is `uncratered_relief` there.
- generation_planet_test.odin `test_an_impact_world_generates_whole_and_an_old_one_baked`: `generate_field_chunk` of the home's chunk differs between `crater_at_impact` true and false, a chunk past the bound is byte equal, and false equals today's (the data planet's).
- generation_planet_record_test.odin `test_a_world_file_without_the_impact_key_bakes_its_crater`: a recorded record without the key resolves false, a new world's resolves true, a file from before 0179 resolves false, `make_recorded_planet` copies it. data_planet_test.odin: a planet record with `crater_at_impact` is refused naming the key.
- simulation_arrival_test.odin:
  - `test_the_hit_digs_the_crater_and_nothing_else`: `arrival_test_config` at 1000 and 500 mm, ticked to the hit tick less one: every loaded sample equals the whole generation's. A copy of the terrain taken, `dig_impact_crater` called: the samples `impact_crater_sample` marks changed hold the baked value, every other equals the copy. A second world ticked through the hit: `expect_field_holds_the_crater` outside the bed (0270's bed radius plus two spacings round the rested base centre), and the raycast down from a metre above the placed frame's base centre meets the ground within a spacing of it.
  - `test_the_hit_fells_the_trees_in_the_crater`: the content's home with `clearing_metres` 0, `grove_share_percent` and `density_percent` 100, `grove_radius_metres` its grove spacing: at the hit tick less one some standing tree's base lies in the reach, after the hit none does, and the standing trees outside the reach are the same keys as before.
  - `test_a_world_from_before_the_impact_keeps_its_baked_crater`: a new world saved at tick 0, its `world.sjson` record's `crater_at_impact` set false, loaded and ticked through the hit: `expect_field_holds_the_crater` outside the bed at the hit tick less one and after the landing.
  - `test_a_world_without_a_fall_digs_its_crater_as_it_enters`: `test_field_game_config` (no fall), 2 ticks: `expect_field_holds_the_crater` with no exception.
  - Extended (0270's extensions kept): `test_two_machines_hash_alike_through_a_fall_with_input` asserts the field's hash changes in the hit tick on both. `test_a_save_taken_during_the_fall_resumes_it` (saved before the hit) holds the crater after it. `test_a_joiner_after_the_fall_has_no_fall` holds the crater outside the bed and equals the host's `field_state_hash`.
- Tests that read a new session's ground at the home straight from `make_planet_generation(session planet)` take `baked_planet_generation`. If 0270's `test_skip_before_the_hit_rests_the_pod_once` parts on the field hash because the light or the water settle at different ticks after a dig at tick 100, it compares the terrain of the loaded samples instead, named in the report.

### Docs

- `doc/content.md`, Planets, `crater`: "A world made since 0271 records `crater_at_impact`: its generation leaves the ground whole and the arrival's hit digs the crater. A `world.sjson` without the key bakes it as before."
- `doc/architecture.md`, World generation: after the crater's sentence, "A world whose record has `crater_at_impact` generates without the term (`crater_baked` false); its crater is the baked generation written into the field at the hit (The arrival)." Line 47 (the start): the pod stands where the crater's floor will be (`field_home_site` reads the baked generation). Save format: `crater_at_impact` beside `crater_recorded`, absent read as baked.
- `doc/architecture.md`, The field session, The arrival: "At the hit, before the rest, `dig_impact_crater` writes the baked generation's sample wherever it differs from the whole one into every loaded chunk (`impact_crater_sample`, through `field_world_set_sample`, so the water, the light and the save follow) and fells the trees within the reach without yield. A chunk entering the set later without saved bytes takes the same pass (`insert_field_chunk_arrival`), as does every chunk of a world without a fall."
- `doc/presentation.md`, The arrival: "The ground is whole through the descent. The dug chunks remesh in the frames after the hit, under the settle's dust."
- `doc/code_map.md`: the new procedures in the lines of `generation_planet.odin`, `world_field_edit.odin`, `simulation_arrival.odin` and `field_trees.odin`, as `tools/code_graph.py --check` asks.
- `doc/log/2026-10-05.md` at the landing:

  ```
  ## The impact digs the crater (0271)

  Tags: field, arrival, crater, generation, save, trees, 0271, m14

  A new world's generation leaves the crater out and the hit writes it in: every loaded sample where the baked and the whole generation differ takes the baked one, so the dug field equals the crater 0199 baked, strata included (the bowl keeps its topsoil lining, the stone to deep stone face 40 m down moves with it). A level or sphere brush cannot carry the profile, so the pass is not a Field_Edit, but it writes through the same sample setter, so the water, the light and the save follow. Chunks outside the set at the hit take the pass as they enter, which also covers a world without a fall. The world records crater_at_impact, and a file without it bakes as before, so old worlds load unchanged with no log line. The trees in the reach fall without yield, since the field has no loose items, and the clearing rule keeps the shipped planet's reach empty of them.
  ```

### Hand-back check lines that apply

- A changed save layout loads an old save: `crater_at_impact` absent reads false, the baked generation of before, covered by `test_a_world_from_before_the_impact_keeps_its_baked_crater` and named in the log. No log line, since nothing changes for that world.
- A number parsed from text is range checked: no number is added (a bool).
- Tests never touch the state directory: all of the above are pure or use the in-memory session and save files.

### Questions answered

1. Edit or pass: the pass, for the reasons above.
2. Which samples: those where baked and whole differ, so the field differs by the crater's profile and nowhere else, and a pass is idempotent.
3. Where the flag lives: on `Planet` (not a data key) so every generation built from the world's planet, the workers', the water's and the trees', follows without a new parameter.
4. Determinism: the dig calls the generation's integer procedures with the world's recorded planet. Its order (chunks by coordinate, samples by index) only matters for the water and light queues, and it is fixed.

### For the main agent

1. Keep `trees_problem`'s `clearing_metres >= reach` (the felling then acts only on code built planets), or drop it so a planet may grow trees in the reach for the bang to fell? A baked old world then could hold trees standing on its bowl.
2. The item's "felled into logs": the field has no loose items, so the felled trees give nothing. A yield to the strapped players' inventories is possible but not physical. Accept no yield?
3. The hit's tick cost is unmeasured. The pass evaluates the relief for the samples within 18 m of the home inside the loaded band: by count about 0.1 million at 1000 mm and about 1.1 million at 333 mm (the set's 21 m above and below). It runs in the tick, so a phone at 333 mm may hitch at the bang. Measure it in the benchmark window before landing, or accept?

### Decisions (main agent, 2026-10-05)

1. The pass, the flag on the record and on `Planet`, and the dig of chunks entering after the hit: accepted.
2. The felling goes: `trees_problem` keeps `clearing_metres` at least the reach, so no valid planet has a tree in the reach and the felling would act on code built planets alone. Drop `fell_trees_in_impact_crater`, `impact_crater_reaches`, the test `test_the_hit_fells_the_trees_in_the_crater`, the content parameter the felling needed where nothing else needs it, and the felling clauses of the docs and the log paragraph. The item's Goal, Change and Verify are corrected above. Question 2 falls with it.
3. The cost: the implementer wraps the first `dig_impact_crater` of `test_the_hit_digs_the_crater_and_nothing_else` in `time.tick_now` at each spacing it runs (add 333 mm there) and logs the wall time (`log.infof`, not asserted), and reports the three numbers. Whether the pass is spread over the settle ticks is decided on them, as a new item; not a benchmark, so it runs at any hour.
4. One seam for the hit: `hit_field_arrival :: proc(state: ^Simulation_State, content: Simulation_Content)` in `simulation_arrival.odin` calls `dig_impact_crater`, then `update_field_sky_after_edits` once, then 0270's `rest_field_pod`, and replaces its two call sites (the hit tick and the Skip before it); `rest_field_pod` stays as 0270 wrote it. 0272 hooks the presentation, not this.
5. If 0270's `test_skip_before_the_hit_rests_the_pod_once` parts on the field hash as the design warns, the terrain comparison it names is the fix, reported.
