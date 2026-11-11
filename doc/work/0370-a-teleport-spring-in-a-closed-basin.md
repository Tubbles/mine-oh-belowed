# 0370: Water leaves at the loaded set's edge

Status: implementing (2026-11-11)

Found by 0367's design: under the teleport water model sources only add and nothing above the sea takes water away, so a spring in a closed basin grows a pool for ever and its water never reaches a repeating state. 0367's savings do not meet its target there.

0367's probe (2026-11-11, 7,200 ticks at the tech demo's spring, both models): the one spring sample pours 180 fill a tick, a little over 0.7 of a sample; nothing leaves the loaded set, a chunk that is not loaded being a wall; the water stands against the set's edge within 10 seconds and a pool grows there without end, under teleport and under bodies alike (the fill grows by 108,000 a 600 tick window). Under teleport the pull is pinned at its 20,000 visits a tick from about tick 3000. So this is not only a closed basin's matter: every spring whose stream leaves the loaded set pools at its edge, and it is what keeps the tick up after 0367's savings.

## Goal

A spring's water reaches a steady state that costs nothing to hold.

## Controls

None.

## Change

- A sink (evaporation or seepage by area, in integers) or a steady stream held as a rate and not as moving samples, decided by the design from 0367's probe figures.
- After 0367.

## Verify

- The checks and the suite, with 0367's report test showing the tick at rest in a closed basin.

## Specification (design, 2026-11-11)

Designed against main and 0367's approved specification (B1 to B4, C1, and C2: a spring pours at most `field_water.spring_fill_per_tick`, 16, `Field_Water_Tuning.spring_rate`), which lands first in this stream. Its probe, `test_report_the_water_at_a_flowing_spring`, is reused.

### The choice

A spring's water goes across the simulated set's edge or into the sea, and is held nowhere else. Water that moves into a sample outside the loaded chunks leaves the simulation as far as it stands over the water the generation puts there (none in air, a lake's or the sea's fill); the generation's ground stays a wall. Under teleport, water that moves into the sea's samples over the sea's fill leaves too, as it does under bodies (step 2). Both models.

1. The set's edge as a sink: chosen. Cost: a generation read per missing sample that moving water touches, cached until the set changes, and a branch in each spread, the flood and the weir. The player sees the stream run to the set's edge, 64 to 128 m off at 1 m spacing, and leave it; no water stands against an invisible wall. Deterministic: the set is lockstep state and the read a pure function of the generation. The water depends on where the players stood, as it does already (a spring pours only where it is simulated, a leaving chunk freezes its water); acceptable, since every machine does alike and every spring's water is bounded wherever the players stand: each path ends at the edge, the sea, or fills a basin to its spill.
2. The generation's stream as the truth: rejected here. The analysis knows a spring's cell, its height and its fall, not its course (the tiles keep a cell's drainage only inside an analysis window while finding; the relief map walks a descent of its own). It needs a course per spring at sample resolution, water asleep on a slope with a moving look, its collision, and a rule to turn it live and back to rest, which 0312's answer 3 declined; live water would still need a terminus at the edge. Several items. Its look would hide the stream's cut at the set's edge (question 4).
3. A sink by area: rejected. Under teleport an evaporating sample must stay awake, so a balanced pool costs its surface every tick; under bodies it is cheap by a body's area but dries generated lakes and players' ponds unless restricted; and a bounded pool still stands against the invisible wall.
4. A steady stream held as a rate: not now. A sample that sleeps alone stops feeding the next, so the whole stream must be held and released at once, as a record saved and hashed, with its look kept while asleep, and only once the integer rule repeats exactly (the films at a stream's margins dry and refill every 60 ticks). Only if the probe shows the steady stream over the target (question 3).

A returning player meets the stream as its chunks froze when they left (their saved bytes), resuming from the first tick; chunks downstream that were never loaded stay dry until the front reaches them, a sample a tick on a slope; water that left at an old edge is gone; no pool anywhere.

An old save: no remap. A teleport pool saved against the set's edge drains through it within seconds of its first awake tick (the probe's cost for those seconds, then the stream's); one saved asleep stays until something wakes it. A developer's bodies save (the tech demo never saves) keeps a body sealed at the edge until its next flood. No runtime line, nothing being remapped (as 0300's joined saddle); the log names the change.

0367: nothing becomes unnecessary, B1 to B4 and C1 being what make a steady stream cheap. C2 stays at 16: with a sink the rate no longer sets a growth, only the stream's width and its awake samples; 16 keeps a running stream over the films' minimum (8), and it draws as the moving sheet (at least 0.2 sample thick, 0294); more widens it at its cost. Captures decide, as 0367 decided.

The first seconds at a spring: it pours from the tick its chunk enters; the stream's awake samples grow to their steady count as the front runs to the edge (the probe's first window), its chunks remesh while the front moves, and no pull runs (a stream rests on no full water). Then the steady stream's samples every tick, nothing growing.

Not covered (question 2): under teleport a stream into a lake, or a closed basin, inside the set keeps that water's surface and the pull busy while it is fed; under bodies it is a volume and a weir.

### The probe, before and after

0367's report test, run as 0367 says, on 0367's landed tree (before) and after each step. Each window line gains `to the edge %.1f a tick`: the growth of `Field_World.water_to_edge` over the window, over its ticks. S1's and S2's digests change (a behaviour change): `SPRING_REPORT_BASE_DIGESTS` holds 0367's landed digests, its comment says so, and the verdict reads "differs".

- Before: the fill grows by about `16 × 600` a window less the films' drying; the wet samples beside a chunk not loaded and the standing samples grow.
- After, from the second window, both models: the fill's change a window under a quarter of a window's pour (2,400); `to the edge` at least 4 a tick; the wet samples beside a chunk not loaded and the standing samples flat; under teleport the pull under 1,000 visits a tick. In the settled windows the figures that judge 0367's target: awake samples, samples changed from the tick before, chunks marked a tick, the streaming's remeshes, the tick's time.
- When the stream has not reached the edge by tick 1,800 at the stand, the implementer reports the figures and stops.

The timed figures are 0342's spring view under both models in the night window (the main agent's).

### Step 1: the set's edge, both models

`world_field.odin`:

- `Field_World` gains, after `water_to_sea`: `water_to_edge: i64`, the fill the set's edge took since the world was made or loaded (moves into a missing sample, a weir over a spill out of the set, a dying body whose spill was out), not saved, not hashed; and `water_outside: map[Sample_Coordinate]i32`, the cache of `field_water_outside`, a pure function of the generation emptied whenever a chunk enters or leaves, not saved, not hashed.
- `field_world_insert_chunk`: `clear(&world.water_outside)` first; in its bodies block after `thaw_water_body_chunk`, `flood_water_bodies_spilling_into(world, chunk.coordinate)`. `field_world_detach_chunk`: `clear(&world.water_outside)`. `destroy_field_world`: `delete(world.water_outside)`.

`generation_planet_waters.odin`:

- `lake_fill_of_sample :: proc(generation: Planet_Generation, listed: []Planet_Lake, sample: Sample_Coordinate, span: Field_Water_Span) -> i32`: the inner loop of `fill_field_chunk_lakes` (the projection, the first listed lake holding the point, its `field_sea_fill`), which that procedure now calls, its bytes unchanged.
- `planet_lake_fill_at :: proc(generation: Planet_Generation, sample: Sample_Coordinate) -> i32`: the lakes meeting the sample's position (`generation_lakes_meeting_box`, the position as both corners), then `lake_fill_of_sample`; 0 for none. Without `fill_field_chunk_lakes`'s carved test: a carved sample under a lake reads as water, so the edge takes less there, never more.

`world_field_water.odin`:

- `field_water_outside :: proc(world: ^Field_World, sample: Sample_Coordinate, span: Field_Water_Span) -> i32`: the water a missing sample holds as the generation makes it, through the cache: -1 in a world without a planet (`water_planet.generation.spacing_millimetres == 0`, the tests' worlds) and where `planet_sample` is ground; else `max(field_sea_fill(sea_level, span), planet_lake_fill_at(generation, sample))`.
- `field_water_edge_share :: proc(world: ^Field_World, span: Field_Water_Span, fill: i32, neighbour: Field_Water_Neighbour, tuning: Field_Water_Tuning, left: i32) -> i32`: for a neighbour whose chunk is not loaded, 0 when `field_water_outside` is -1, else `field_water_share_from(span, fill, neighbour.span, outside, FIELD_WATER_FULL - outside, tuning, left)`: banded and capped as every move.
- `spread_field_water` (teleport): a missing neighbour takes `field_water_edge_share(world, span, i32(chunk.water[index]), neighbour, tuning, left)`; the sender is written down by it through `set_field_water`, `water_to_edge` credited, `left` lowered, no event.
- `plan_field_water_front` (bodies): a missing receiver, skipped today, takes `field_water_edge_share(world, span, start + i32(pass.delta[index]), neighbour, tuning, left)` into `pass.delta[index]` and `pass.outflow[index]` as any move, `left` lowered, `water_to_edge` credited in the plan as the sea's share is; no receiver pass, no event.
- Unchanged: `field_water_room` stays 0 for a missing chunk, so the films' test, the displacement, the pull and its search keep it a wall; a film at the edge dries where it stands. Asleep water at the edge stays asleep: the edge takes moving water only.

`world_field_water_body.odin`:

- `Water_Body.spill_outside: bool`: the spill leaves the set, a sample beside a chunk not loaded that the generation makes dry air.
- `water_body_has_frozen_part :: proc(body: ^Water_Body, chunk: Field_Chunk_Coordinate) -> bool`.
- `run_water_body_flood`, a missing neighbour after the sea's test: when `field_water_outside` is 0 and the body has no frozen part in that chunk, `body.spill, body.spill_level, body.spill_outside = entry.sample, max(flood.sill, field_water_bottom(next_span)), true` and the flood is done, as at the sea. A missing sample holding a lake's water, the ground and the body's own frozen part stay walls: a lake straddling the edge spills at its dry shore, at its level (a sample its mask holds with no lake fill lies at or over the level; a notch beside the mask up to 13 fill under it, 0336, spills as it would with the chunk loaded), and a pond the body froze keeps its part.
- `start_water_body_flood` clears `spill_outside` with the other spill fields.
- `emit_water_body_weirs`: after the sea's branch, a body with `spill_outside`, or whose spill sample's chunk is not loaded (it waits today), sends the flow to `water_to_edge`, its volume lowered and relevelled.
- `water_body_joined_under_water`: false with `spill_outside`, as with `spill_to_sea`.
- `free_empty_water_body` without an heir and `finish_water_body_flood` for a body left with no cells: its volume to `water_to_edge` when `spill_outside`.
- `flood_water_bodies_spilling_into :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate)`: each live body, not the sea, with `spill_outside` whose spill sample has a face neighbour in the arriving chunk is marked dirty: the edge there is gone.

Elsewhere:

- `simulation_field_save.odin`: `Water_Body_Record.spill_outside: bool`, written and read with the body; by name, so an older record reads false and its body spills out at its next flood. `WATER_BODY_RECORD_BYTES` counts five bools.
- `data_reload.odin` `move_field_chunks`: `water_to_edge` moves with the world.
- `diagnostics.odin`, `loop.odin`: `World_Facts.water_to_edge` in a field session; the water line ends `  to the edge %d`.

### Step 2: the sea's samples under teleport

- `spread_field_water`: a loaded neighbour the sea owns (`WATER_OWNER_SEA`, which `fill_field_chunk_sea` marks under both models) holding at least its sea fill (`field_sea_fill(sea_level, neighbour.span)`, over 0) takes `field_water_share_from(span, fill, neighbour.span, sea, FIELD_WATER_FULL - sea, tuning, left)`: the sender written down, `water_to_sea` credited, the sea's byte untouched, the wave event as today. A sea sample under its fill (after a pump or a dig beside it) fills as today.
- So under teleport a stream reaching the sea leaves at the sea's level, the generated sea stays asleep at its mouth, and the known limit of a rising teleport sea ends. A chunk saved before 0293 carries no owners: its sea rises as before.

### Tests

New in `world_field_water_test.odin`, teleport. Fixture `make_edge_test_world :: proc(open: bool) -> Field_World`: one chunk, ground to local y 8, air above, on a bare sphere's generation (`light_test_sky_planet`'s pattern, no relief, sea level 0) whose radius lies under the chunk (`open`: every missing sample air, checked with `planet_sample`) or over its top (every missing sample ground); a heap of 128 full samples (local x 26 to 29, y 9 to 16, z 14 to 17) written through `set_field_water`. Films' bound: 10,240 (1,024 floor samples drying 10 each in 600 ticks).

- `test_moving_water_leaves_through_the_sets_edge`: open, 600 ticks: `water_to_edge > 0`; the chunk's fill plus `water_to_edge` at most 32,512 and at least it less the films' bound; no sample on a face holds more than `minimum_fill`.
- `test_the_sets_edge_is_a_wall_in_the_generations_ground`: closed, 600 ticks: `water_to_edge == 0`.
- `test_a_world_without_a_planet_keeps_its_edge_a_wall`: open with the zero water planet: `water_to_edge == 0`.
- `test_the_edge_cache_never_changes_a_result`: two open worlds, one emptying `water_outside` before every step: every chunk's `field_chunk_state_hash` and `water_to_edge` equal every 60 ticks over 600.
- `test_the_edge_takes_only_the_water_over_a_missing_lake` (slow): `waters_test_planet(8000)` with its features, the chunk `shipped_lake_centre_chunk` of the lake at 72.02, 143.04 generated and inserted alone under teleport; its +x neighbour generated, not inserted, holding lake water on its -x face (a precondition). The centre's wet samples on its +x face woken, 300 ticks: `water_to_edge == 0`, every byte as generated. Then 8 × 254 written onto that face's surface sample: after 600 ticks `water_to_edge > 0`, and the chunk's fill over its generated fill at most the pour less `water_to_edge`.
- `test_the_sea_takes_a_stream_at_its_level` (step 2): closed, sea level at local y 12, the samples under it written as `fill_field_chunk_sea` writes them (the sea's, its fill, asleep), the heap over them: after 600 ticks every sea sample holds its sea fill and sleeps, `water_to_sea > 0`, `water_to_edge == 0`.

New in `world_field_water_body_test.odin`, bodies, the same fixture open:

- `test_front_water_leaves_through_the_sets_edge`: the heap as front water: after 600 ticks `water_to_edge > 0`, `conserved_water + water_to_edge` within the films' bound under 32,512 and at most it; no body but the sea owns a sample on a face.
- `test_a_body_spills_out_where_its_basin_meets_the_sets_edge`: a basin, floor at y 4, x 8 to 30, z 8 to 23, walled in ground to y 12 except at x 31, the chunk's +x face, ground to y 9; filled to y 11 as front water (`set_front_water`) and settled (`settle_body_test_water`): one body, `spill_outside`, its spill at local x 31, y 10. Then 40 × 254 more poured: after 1,200 ticks its volume at most `spill_volume + weir_dead_band`, and `water_to_edge` grown by at least the pour less `weir_dead_band` and the films' bound.
- `test_a_frozen_part_keeps_the_sets_edge_a_wall`: a basin across chunks x 0 and 1 settled as one body; chunk 1 detached (`field_world_detach_chunk`), the body marked dirty, 300 ticks: `spill_outside` false, the volume unchanged, `water_to_edge == 0`.
- `test_a_chunk_arriving_where_a_body_spilled_out_floods_it_again`: after the spill test's settle its +x chunk inserted, ground to y 12: the body dirty at once; after its flood `spill_outside` false.
- `test_a_weir_whose_spill_chunk_left_pours_out_of_the_set`: a lake in chunk 0 spilling into chunk 1 (`run_body_test_trough_across_chunks`'s pattern), settled with its weir running; chunk 1 detached; 20 × 254 poured into the lake: after 1,200 ticks the volume within `weir_dead_band` of `spill_volume`, `water_to_edge` grown by the pour less the dead band.

New in `simulation_field_test.odin`, sessions, slow. `start_session_at_the_test_spring :: proc(config: Game_Config, content: ^Game_Content, model: Water_Model) -> ^Session`: the probe's setup (the shipped planets with their waters, player 0 at 0342's stand), which the probe then calls.

- `test_a_spring_stream_leaves_the_set_and_its_fill_holds`, each model: 2,400 ticks; over ticks 1,800 to 2,400 the loaded fill changes by at most `spring_rate × 150` and `water_to_edge` grows by at least `spring_rate × 150`.
- `test_a_returning_player_finds_the_stream_and_no_pool`, teleport: 1,200 ticks; player 0 put 5 degrees of latitude away (`surface_point_feet`, `teleport_field_player`) for 600 ticks, the spring's chunk then in `saved_chunks`; back for 1,800 ticks: the bounds above over the last 600, and the loaded fill at the end at most the fill at tick 1,200 plus `spring_rate × 600`.
- `test_two_machines_at_a_spring_keep_one_state_hash`, each model: 900 ticks; the files encoded and loaded as a second session (`load_test_field_save`, `stage_cached_field_set`, `restore_arrived_field_set`; its edge cache cold); both 900 ticks more of an empty frame: `simulation_state_hash` equal every 100 ticks, `water_to_edge` grown alike.

Adapted: each test whose world has a planet and whose water reaches a chunk not loaded (the spring sessions, `test_two_tech_demo_bodies_sessions_run_alike_at_the_spring`), named in the report with what moved; `diagnostics_test.odin`'s World line; the malformed table test's record size. `test_shipped_lakes_settle_under_bodies`, its streamed form and `test_a_lake_over_its_inner_saddles_settles_as_one_body` must pass unchanged: their lakes straddle the 27 chunks' edge, so they prove a lake beyond the edge holds at its level.

Before reporting: `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, and the probe after each step with its figures.

### Docs

- `doc/architecture.md`, The water field: the rule's "Ground and a missing chunk take nothing" (the set's edge takes moving water over the generation's water there), Sources (the edge, `field_water_outside` and its cache; step 2's sea samples), Volume (conserved but at the edge and the teleport sea too), Known limits (the teleport sea no longer rises; a teleport lake or basin fed by a stream stays busy), Storage (`water_to_edge`, `water_outside`), Bodies: the front (moves across the edge), the flood (the spill out of the set and its three walls), the weir (a spill out, a spill chunk that left), the set's edges (an arrival beside a spill out floods the body again).
- `doc/architecture.md`, The field session, the simulated set: the water's edge rule beside the sea edge and the missing chunk rule that read the set.
- `doc/architecture.md`, Save format, the water bodies' table: the record's `spill_outside` since 0370, an older record reading false.
- `doc/developer_tools.md`, Diagnostics pages, World: the water line's "to the edge 9".
- `doc/code_map.md`: `world_field_water.odin` gains the set's edge (`field_water_outside`, `field_water_edge_share`), `world_field_water_body.odin` the spill out of the set.

### Hand-back check

- A changed save layout: `Water_Body_Record.spill_outside` read by name, no remap and no line (0300's joined saddle); the behaviour change named in the log; old saves load (above).
- A shared budget: a body marked dirty by an arrival beside its spill out takes the flood budget as a thaw does; a missing sample's first read costs a `planet_sample` and a lake query after each set change, outside the budgets, bounded by the face samples moving water reaches; the pull's budget loses the pool's searches.
- A list without bound: `water_outside` holds at most the samples across the set's faces and empties at every set change.
- Memory a frame may draw from: none; the cache and the counter are the tick's.
- Tests: in-memory worlds and sessions, saves encoded in memory.

### Decided

1. The edge reads the generation, never a missing chunk's saved bytes, as the sea's rule does: decoding a saved chunk per read costs, and the edge lies 64 m or more from every player. A teleport pond a player built across the edge drains there once woken; under bodies its frozen part keeps it.
2. A missing lake's water is a reservoir at its level for the moves and a wall for the flood, which spills at the dry shore over it: the loaded part of a lake straddling the edge holds its level under both models.
3. The edge takes moving water only; nothing new wakes at a chunk's departure.
4. `water_to_edge` is a counter, not state, as the pull's counts.
5. C2's 16 stays (above).
6. One implementer: step 1, the probe, step 2, the probe.

### Questions for the main agent

1. The title no longer fits: the water stands at the set's edge under both models. "Water leaves at the set's edge"?
2. Under teleport a stream into a lake, or a closed basin, inside the set keeps that water's surface and the pull busy while it is fed (the probe's pool in another place; a 1 ha lake 0.5 m under its pour point takes about 22 minutes at 16 a tick before it spills, and after that the surface carries the flow). Bodies hold it as a volume and a weir. Generated lakes as reservoirs at their level under teleport (step 2's rule for the lakes; a player could then not raise one), bodies as a new world's model, or leave it: a new item either way?
3. If the settled windows show the steady stream over 1 ms in 0342's profile, or remeshing along it, a held stream (option 4) as a new item?
4. The stream ends at the set's edge with dry generated ground beyond, as the pool's wall did. Drawing a spring's course beyond the set from the generation (option 2's look, presentation only) would hide it. A suggestion for `SUGGESTIONS.md`?
5. Step 2 is separable from the edge: keep it here?

### Decisions (main agent, 2026-11-11)

1. Question 1: the title is changed to what the design does; the file keeps its name, which other items refer to. The Verify list above is read as the specification's: the probe's stream holds its fill and reaches rest at the edge.
2. Question 2: left as it is here. Which water model a new world uses is the user's decision (`SUGGESTIONS.md`); a teleport lake fed by a stream stays busy until then.
3. Question 3: a held stream becomes an item only if 0342's table shows the steady stream over 1 ms or remeshing along it after this item.
4. Question 4: the spring's course drawn beyond the set goes to `SUGGESTIONS.md`.
5. Question 5: step 2 (the sea's samples under teleport) stays in this item.
6. Order: after 0367 has landed, in its stream, since both edit the water's spread and the probe. One implementer.

### After 0367's landing (main agent, 2026-11-11)

0367 landed with `spring_fill_per_tick = 64`, not 16: at 16 the stream spread too thin to be drawn. Wherever this specification says 16, the shipped rate is 64 and stays; the expected figures scale (the growth is `64 × 600` a window before this item). The probe's constant is `SPRING_REPORT_RECORDED_DIGESTS`, recorded at 64. Everything else stands.
