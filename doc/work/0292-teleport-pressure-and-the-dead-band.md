# 0292: Teleport pressure and the dead band

Status: designed (2026-11-05)

Milestone: the water tech demo (0291). The first of the water stream: 0292, then 0293, 0294, 0295, all on `world_field_water.odin` and `world_field_mesh.odin`.

## Goal

The field's water rule gains communicating vessels and static friction, so a shaft dug beside a lake and joined to its bed fills to the lake's level, a U-tube rises, and a settled lake is still: no transfer for a level difference under a minimum head, no film at a sill topped up every drying step. This is water model `teleport` of the tech demo, the browser demo `teleport-waves` (its notes: `/home/user/water-demos/notes/teleport-pressure.md`, `teleport-waves.md` revisions 3 to 6) carried into the field.

## Controls

None.

## Change

- `world_field_water.odin`: after `spread_field_water`, a not-full sample resting on full water (its nearer-centre neighbour full) that moved nothing runs a bounded depth-first search through full samples (nearer and farther neighbours alike, visited at most `pressure_visit_budget` per search and `pressure_visit_budget_per_tick` per tick, in sample order) for the surface sample with the highest level; when that level exceeds the sample's own by more than one cell height plus the dead band, the equalising fill (rate capped) moves from there to here in one step. A failed search sets a `water_pressure_failed` bit that a change next door clears. The dead band: `field_water_share` moves nothing for a level difference at or under `minimum_head` (fill units, shipped 4 of 254, about 1/64 cell); falling into room below is never banded. Films: `field_water_is_film` drying wakes only the film sample; a film that cannot be refilled above the band sleeps.
- Tuning keys in `field_water` of `data/game.sjson`: `pressure` (true), `pressure_visit_budget` (128), `pressure_visit_budget_per_tick` (20000), `minimum_head` (4). `Field_Water_Tuning` gains them; the planet preview's and the tech demo's debug line shows teleports, visits and failures per tick.
- The chunk codec: the failed bit is derived (cleared on load, rebuilt by the first tick), so `FIELD_CHUNK_FORMAT_VERSION` stays; the state hash is unchanged in its inputs. Lockstep: the search runs in sample order with the fixed budget, so every machine teleports alike.
- Docs: `doc/architecture.md` (The water field: pressure, the dead band), `doc/content.md` (the keys), the log.

## Verify

- `./build.sh check`, `check-android`, `test`, the doc checks.
- Tests in `world_field_water_test.odin`: U-tube (a lake, a sealed tunnel from its bed to a shaft open to air): the shaft reaches the lake level within the band in under 1500 ticks with pressure on, stays at the tunnel with it off; shaft beside a lake; a settled 20-sample lake stays asleep for 3000 ticks (no awake samples, volume constant); the sill film: a lake at a sill's height does not pulse (no wake every `dry_ticks`); the existing levelling and breach tests still pass; determinism: two worlds stepped alike hash alike.
- The bench: the water's ms per tick at the existing scenarios within 10 percent of before.

## Specification (design, 2026-11-05)

Designed against `main`. Units throughout: fill 0..`FIELD_WATER_FULL` (254) per sample; a span's `middle`, `height` and `field_water_bottom` in fill units from the centre (`i64`); an exact level `field_water_level_exact` = bottom × 254 + fill × height. The band in exact units is `BAND = i64(tuning.minimum_head) * FIELD_WATER_FULL`.

### The rule

1. Dead band (`field_water_share`, after `difference` is taken): `if difference <= (field_water_is_drop(span, neighbour.span) ? 0 : BAND) { return 0 }`. New `field_water_is_drop :: proc(span, below: Field_Water_Span) -> bool` = `field_water_bottom(below) + below.height <= field_water_bottom(span)` (the neighbour's cell lies entirely under the mover's: a fall, never banded; lateral and the sphere's staircase are banded). Nothing else in `share` changes; the teleport uses the same `share`, so it is banded too.
2. Films: new `dry_field_water_film :: proc(world, chunk, index, sample)`: `chunk.water[index] -= 1`, `note_field_chunk_change`, `mark_field_chunks_around_sample_dirty`, `world.edited_chunks[chunk.coordinate] = {}`; no wake (drying is a sink, not a flow). In `step_field_water_sample`'s film case call it in place of `set_field_water`, then `if chunk.water[index] == 0 { chunk.water_flow[index] = 0; sleep_field_water_sample(chunk, index); return }`. A film that nobody refills above the band dries alone and sleeps; the lake beside it is never woken by the drying.
3. Waking: `field_water_can_wake` also returns true for an air sample that rests on full water: after the sea test, `return field_water_rests_on_full(field_water_span(sample), field_water_neighbours(world, chunk, sample))` with `sample := field_chunk_sample(chunk, index)` (the lookups run only for a dry sample that is neither a spring nor below sea). New `field_water_rests_on_full :: proc(span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour) -> bool`: any neighbour with `chunk != nil`, `span.middle < span.middle` of the sample, `density <= 0` and `water == FIELD_WATER_FULL` (a missing sea sample does not count: the sea edge refill covers it). `wake_field_water_sample` first does `clear_field_sample_bit(&chunk.water_pressure_failed, index)`, before the can-wake return, so every change next door (every `set_field_water` wakes the six neighbours, every terrain set too) clears the flag.
4. The pull, in `step_field_water_sample` after the `switch`: `postponed := false; if !film && moved == 0 && tuning.pressure && i32(chunk.water[index]) < FIELD_WATER_FULL && field_water_rests_on_full(span, neighbours) { moved, postponed = pull_field_water_pressure(world, chunk, index, sample, span, neighbours, tuning, search) }`. `water_flow` keeps counting the spread only (fill moved out). The stay-awake test becomes `if film || moved > 0 || postponed || chunk.water[index] != before`.
5. `pull_field_water_pressure :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour, tuning: Field_Water_Tuning, search: ^Field_Water_Search) -> (moved: i32, postponed: bool)`:
   - `if field_sample_bit(&chunk.water_pressure_failed, index) { return 0, false }`; `if world.water_pressure.visits >= tuning.pressure_visit_budget_per_tick { return 0, true }` (the tick's budget postpones, it never flags).
   - Reset the search (`search.chunk_count = 0`, `clear(&search.stack)`), mark the receiver visited, then seed in slot order: every neighbour with `chunk != nil`, `span.middle < span.middle`, `density <= 0`, `water == FIELD_WATER_FULL` is marked and pushed.
   - Loop while the stack is not empty and `visits < tuning.pressure_visit_budget`: pop `c` (the last pushed), `visits += 1`, `c_fill := i32(c.chunk.water[c.index])`, `c_span := field_water_span(c.sample)`. If `c_fill < FIELD_WATER_FULL`: candidate test, no expansion. Else `c_neighbours := field_water_neighbours(world, c.chunk, c.sample)`; surface = any `c_neighbours[k]` with `chunk != nil`, `span.middle > c_span.middle` and `field_water_room > 0`; candidate test; then expand in two passes, pass 0 the neighbours with `span.middle <= c_span.middle`, pass 1 those with `span.middle > c_span.middle`, each in slot order: skip `chunk == nil` (a missing chunk is a wall), `density > 0`, or already visited (`field_water_search_visit` false); push the rest. The last pushed pops first, so the search climbs out of a tunnel before it wanders the lake bed.
   - Candidate test: `c_fill > 0`, `c` is not a face neighbour of the receiver (`abs(dx) + abs(dy) + abs(dz) == 1` on the sample coordinates: those level by the plain rule), `c` is a surface (a partial cell always is), and `field_water_level_exact(c_span, c_fill) > field_water_level_exact(span, fill) + span.height + c_span.height + BAND` (one fill of each cell plus the band: the margin that killed the study's ping-pong) and above the best so far; keep the highest.
   - After the loop `world.water_pressure.visits += visits`. With a best: `receiver := Field_Water_Neighbour{chunk = chunk, index = index, sample = sample, span = span}`, `amount := field_water_share(best.chunk, best.index, best.span, receiver, tuning, min(i32(best.chunk.water[best.index]), tuning.rate))`; `amount > 0`: `move_field_water(world, best.chunk, best.index, best.sample, receiver, amount)` (wakes both, marks the meshes), `world.water_pressure.teleports += 1`, return `amount, false`. Otherwise (no best, or a banded share of 0) `set_field_sample_bit(&chunk.water_pressure_failed, index)`, `world.water_pressure.failures += 1`, return `0, false`. The head gives from its fill as it stands (not its start fill, which lies in another chunk's pass): the one place the rule reads a current fill as a budget; deterministic, since the order is fixed.
6. The search state, one per tick: `Field_Water_Search :: struct { chunks: [FIELD_WATER_SEARCH_CHUNK_LIMIT]Field_Water_Search_Chunk, chunk_count: int, stack: [dynamic]Field_Water_Search_Cell }`, `Field_Water_Search_Chunk :: struct { chunk: ^Field_Chunk, visited: Field_Sample_Bits }`, `Field_Water_Search_Cell :: struct { chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate }`, `FIELD_WATER_SEARCH_CHUNK_LIMIT :: 8`. `make_field_water_search :: proc(tuning: Field_Water_Tuning, allocator := context.temp_allocator) -> ^Field_Water_Search` reserves the stack at `6 * pressure_visit_budget + 6` (every pop pushes at most six, the seeds at most six, so it never grows). `field_water_search_visit :: proc(search: ^Field_Water_Search, chunk: ^Field_Chunk, index: int) -> bool`: finds the chunk's entry by pointer among the first `chunk_count`, adds one (`visited = {}`) when absent and `chunk_count < FIELD_WATER_SEARCH_CHUNK_LIMIT`, else returns false (a ninth chunk is a wall); returns true and sets the bit when the bit was clear. `step_field_water` makes it once after the passes are built, resets `world.water_pressure = {}` first, and passes it through `step_field_water_pass` to `step_field_water_sample` (both gain a `search: ^Field_Water_Search` parameter, last).
7. Lockstep: the pull runs inside the existing order (chunks in coordinate order, samples in sample order, seeds and expansions in slot order), the budgets are data, a missing chunk is a wall on every machine since the set is shared; the postponed and the failed states follow from the same order. The search may overrun the per-tick budget by at most one search (the budget is checked before a search starts).

### Storage, codec, hash

- `Field_Chunk.water_pressure_failed: Field_Sample_Bits` (`world_field.odin`, after `water_source`; comment: the pull's failed bit, derived, never saved or hashed, zero on a fresh or decoded chunk). The codec's plane list, `FIELD_CHUNK_FORMAT_VERSION` (4), `field_chunk_terrain_and_water_equal`, `field_chunk_equals` and `field_chunk_state_hash` do not change; `decode_field_chunk_delta` assigns a fresh chunk, so the bit is cleared on load and rebuilt by the first tick. Add the bit to the codec's and the hash's head comments as left out.
- `Field_World.water_pressure: Field_Water_Pressure_Counts` (`world_field.odin`), `Field_Water_Pressure_Counts :: struct { teleports, visits, failures: i64 }` in `world_field_water.odin`: the last tick's counts, reset at the top of `step_field_water`; not saved, not hashed.

### Data

- `Field_Water_Config` (`data_load.odin`) gains `pressure: bool`, `pressure_visit_budget: int`, `pressure_visit_budget_per_tick: int`, `minimum_head: int`; `Field_Water_Tuning` gains `pressure: bool`, `pressure_visit_budget: i32`, `pressure_visit_budget_per_tick: i64`, `minimum_head: i32`, read in `make_field_water_tuning`.
- Bounds in `field_water_problem`: `pressure_visit_budget` 1 to `MAXIMUM_FIELD_WATER_PRESSURE_VISITS` (4096: the stack is six entries a visit), `pressure_visit_budget_per_tick` 1 to `MAXIMUM_FIELD_WATER_PRESSURE_VISITS_PER_TICK` (1_000_000), `minimum_head` 0 to `MAXIMUM_FIELD_WATER_MINIMUM_HEAD` (64, a quarter cell; the study's sweep tilts the surface from 16). `pressure` is a bool and cannot be refused when missing (it reads false, pressure off); say so in content.md.
- `data/game.sjson` `field_water`: `pressure = true`, `pressure_visit_budget = 128`, `pressure_visit_budget_per_tick = 20000`, `minimum_head = 4` (about 1/64 cell, the lowest band that stopped the study's 2-fill ping-pong); extend the block's comment.

### Debug line

- `World_Facts` (`diagnostics.odin`) gains `water_awake_chunk_count: int`, `water_teleports`, `water_visits`, `water_failures: i64`; `world_facts` (`loop.odin`) fills them from `session.simulation.field.world` (`len(water_awake_chunks)`, `water_pressure`) when `field_session`; `world_page_lines` appends, in the field branch after the sealed room line, `"water awake chunks %d  teleports %d  visits %d  failed %d"`. The planet preview and the tech demo (0291) both run the normal loop, so the F3 World page is the one place.

### Tests

`world_field_water_test.odin`. `water_test_tuning` keeps the plain rule (`pressure = false`, `minimum_head = 0`, budgets 128 and 20000), so every existing test asserts the same bytes as before; new `water_pressure_test_tuning :: proc() -> Field_Water_Tuning` = the shipped values with `rate = 64, still_ticks = 20, minimum_fill = 8, dry_ticks = 60`. Helpers: `water_level_at(world, sample) -> i64` (`field_water_level` of the span and fill), `highest_wet_level_in_column(world, x, z, low_y, high_y) -> (level: i64, found: bool)`, `carve_water_test_u_tube(world, lake_x: i32, tunnel_length: i32)`: air in the lake `{lake_x..lake_x+7, 3..20, 4..11}`, the tunnel `{lake_x+8 ..< lake_x+8+tunnel_length, 3, 7}` and the shaft `{lake_x+8+tunnel_length, 3..25, 7}`, then full water poured into the lake's `y` 3..14 (768 samples).

- `test_the_dead_band_holds_a_head_at_or_under_the_minimum_but_not_a_drop`: one ground chunk, air at `{0, 3200, 0}` and `{1, 3200, 0}` (equal spans), fills 100 and 96: `field_water_share` with `water_pressure_test_tuning` gives 0 (a head of 4 fill, the band), with 95 gives 2, with `minimum_head = 0` and 96 gives 2. The drop: air at `{0, 3201, 0}` (fill 1) over `{0, 3200, 0}` (fill 253): `field_water_is_drop` true and the share 1 with the band on.
- `test_a_shaft_joined_to_a_lake_bed_rises_to_the_lake_level`: for tunnel lengths 1 (the shaft beside the lake) and 8 (the U-tube), one chunk, `carve_water_test_u_tube(4, length)`, `water_pressure_test_tuning`, stepped tick by tick until no chunk is awake (under 1500 ticks) summing `world.water_pressure.teleports`, which ends positive; total water unchanged; `lake` = the maximum of `highest_wet_level_in_column` over the lake's `x`, `z`; `shaft` = the shaft column's; `lake - shaft <= 12` (two fill of margin, the band, the band's staircase across the lake and the rounding) and `shaft <= lake + 2`; every shaft sample under the highest wet one is full.
- `test_the_shaft_stays_at_the_tunnel_with_pressure_off`: the U-tube (length 8) with `water_pressure_test_tuning` and `pressure = false`, 1500 ticks: the tunnel's last sample `{19, 3, 7}` is full, `{20, 4, 7}` holds 0, total unchanged.
- `test_a_settled_lake_stays_asleep`: the basin `BASIN_LOW..BASIN_HIGH`, 20 full samples poured at `{4..8, 3, 4..7}`, `water_pressure_test_tuning`, settles under 5000 ticks; then 3000 more ticks asserting every tick `len(world.water_awake_chunks) == 0`, the total unchanged and `world.water_pressure == {}`.
- `test_a_film_at_a_sill_dries_without_waking_the_lake`: the basin, full water `y` 3..9 and fill 12 over the whole `y` 10 layer, `water_pressure_test_tuning`, settled under 5000; then `field_world_set_sample({12, 10, 7}, FIELD_AIR_SAMPLE)` (the sill: a hole in the wall at the top layer's height, ground under it; the lake level stands about 9 fill over its bottom, so the lake tops it up to a film of 4 to 6 and the band then holds). Precondition asserted within the next 20 ticks: the sill's fill is between 1 and `minimum_fill` on some tick (adjust the pour of 12 if the geometry gives otherwise). Then 600 ticks (six drying steps and the still ticks): no awake chunk, the sill at 0; then 3000 ticks asserting every tick no awake chunk and the total unchanged (the old rule woke the lake every 60 ticks and refilled the sill).
- `test_the_pressure_search_crosses_a_chunk_border_alike_in_either_order`: two worlds of chunks `{0, 1}` and `{1, 0}` (as `make_two_chunk_water_world`, without its basin), `carve_water_test_u_tube(20, 8)` (the lake in chunk 0, the tunnel across `x` 32, the shaft at `x` 36 in chunk 1), `water_pressure_test_tuning`, 600 ticks each; per chunk `field_chunk_state_hash` equal, `water_pressure_failed` and `water_flow` equal; the shaft's `{36, 4, 7}` holds water (the search crossed the border); `water_pressure` counts equal.
- `diagnostics_test.odin`, `test_the_world_page_counts_the_water_pressure`: `World_Facts{field_session = true, water_awake_chunk_count = 1, water_teleports = 3, water_visits = 400, water_failures = 2}` yields the line `"water awake chunks 1  teleports 3  visits 400  failed 2"`; `World_Facts{}` has no line starting `"water awake"`.
- `data_load_test.odin`, `test_field_water_pressure_values_are_bounded`: the shipped config's `field_water` passes with `pressure` true, 128, 20000 and 4; `pressure_visit_budget` 0 and 4097, `pressure_visit_budget_per_tick` 0 and `minimum_head` 65 are each refused naming the key.
- Existing: every test of `world_field_water_test.odin` unchanged; `test_field_game_config` (`player_test.odin`) copies the shipped block, so the field session tests run with pressure on and the band at 4, which the hash tests compare across sessions as before.

### Docs

- `doc/architecture.md`, The water field: in the rule bullet the band (a move between overlapping cells needs a head above `minimum_head`, a fall never); a new bullet "Pressure" after it (the pull, the search order and budgets, the margin, the failed bit, a missing chunk a wall, the counts); the sleeping bullet (an air sample on full water wakes; the failed bit cleared by every wake); the films bullet (drying wakes nobody, a dried film sleeps); the storage bullet (the failed bit, derived; the counts).
- `doc/content.md`, the `field_water` paragraph: the four keys, bounds, shipped values, `pressure` unrefusable when missing.
- `doc/developer_tools.md`, the diagnostics pages paragraph: the World page's water line on the field.
- `doc/code_map.md` line for `world_field_water.odin`: add the pressure pull; `python3 tools/code_graph.py --check doc/code_map.md` passes.
- `data/game.sjson` block comment, the head comments of `world_field_water.odin`, `world_field_codec.odin` and the hash in `simulation_field_save.odin`. The log entry is the main agent's at landing.

### Hand-back check

- Range checks: the four keys through `field_water_problem` and its bounds above.
- Save layout: unchanged (format 4); the failed bit is derived and cleared on load, which the codec's head comment says; no remap, no log line.
- Shared budget: the per-tick visits are spent in chunk and sample order; a postponed sample stays awake (`postponed` resets its still ticks), so a big lake's late searchers are delayed, never put to sleep by the budget; a search overruns the tick's budget by at most one search.
- Bounded lists: the stack never grows past `6 * pressure_visit_budget + 6`; the visited set holds at most `FIELD_WATER_SEARCH_CHUNK_LIMIT` chunks.
- Tests use worlds in memory only.
- The bench (`./build.sh bench`, tick average within 10 percent) is the main agent's at landing: an agent never runs the benchmark while the user plays (CLAUDE.md, Parallelism).

### Decisions on the open points

- The sea edge refill is not banded: `field_water_source_fill` sets the fill outright and stays as it is.
- The simulated set's boundary: a missing chunk is a wall to the search (never seeded, pushed, nor a surface through it) and a missing sea sample is never a head; the sea reaches a tunnel only through the sea edge refill, as today.
- The margin is one fill of each cell (`span.height + head.span.height` in exact units) plus the band, as the study's revision 6 states; the item's "one cell height" was the first note's wording for the same term.
- The existing tests keep the plain rule (band 0, pressure off): the basin test's 14 and the breach test's `64 * 16` derive from the plain rule's half-fill rounding, and a band of 4 compounds to a staircase of up to 32 across the basin's eight samples. The new tests cover the band and the pull at the shipped values.
- The empty-on-full wake is unconditional (the wake path has no tuning): with pressure off such a sample idles and sleeps after the still ticks.
- Sleeping does not clear the failed bit: the next wake does, and a sleeping sample's bit is never read.
- `water_flow` counts the spread only; the teleports are counted on the world.

### Main agent's decisions (approval, 2026-11-05)

- As designed. The bench runs at landing by the main agent.
- Approved.
