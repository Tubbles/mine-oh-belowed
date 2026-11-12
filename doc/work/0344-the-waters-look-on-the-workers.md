# 0344: The water's look on the workers

Status: verified (2026-11-12)

`gather_field_grid` runs `write_field_water_look` on the main thread for every mesh job it gathers: 2.8 ms for a lake's chunk and 5.5 ms for a sea chunk in the test build, up to 8 jobs a frame (`work/performance_research_0340.md`, 2.1). It is there because the workers never read `Field_World`.

## Goal

No water look computed on the main thread, with the same bytes as today.

## Controls

None.

## Change

- The gather copies the raw arrays of the look's reach into the job, as it copies the samples, and the worker builds the sheet and the wall guard.
- The job's memory grows by the copied reach; the hand-back rule on memory a frame may draw from holds.

## Verify

- The checks and the suite, with the settled lake's water mesh byte for byte as before.
- 0342's table: the streaming section's worst frame along a lake shore and at the sea, before and after.

## Specification (design, 2026-11-11)

### The seam

The research's seam, kept: the gather copies the raw arrays of the look's reach into the job a row run at a time, and the worker does every per sample step of the look. The look, as it reads today (`world_field_water_look.odin`), takes from `Field_World`:

- `world.chunks` for the node's chunk and its 26 neighbours. Of each loaded chunk, over local `-3 ..= 34` on every axis (`FIELD_LOOK_SIZE` 38, 54,872 samples): `density`, `water`, `water_owner`, the bits `water_awake & ~water_source`, and `water_moved` (the sheet's mode, for wet samples in `-2 ..= 33` and their face neighbours).
- For each owner named there: `world.water_planet.sea_level` (the sea), or `world.water_bodies[id].level` through `water_owner_body`, which reads `world.water_flood.active` and `.body` for the released samples.
- Of the waves, for those 27 coordinates: `Field_Wave_Chunk.height` and `.active`, rounded (`field_wave_baked_at`), at the grid's samples and their radial up and down neighbours, and at the wall guard's samples beyond the grid and theirs. That is the same 38³ reach.

Nothing else. `field_water_sheet_mode`'s check of the owner's level is redundant there: it runs only for a sample whose still owner is none, and `field_water_look_level` is false for every such sample. So the worker's mode needs only `moved`, `loaded`, `density` and `water`.

Two parts. A is what the item asked. B is the coarse grids' base, decided in by the goal (question 1):

- **A, the finest look.** `gather_field_grid` stops calling the look. A new `gather_field_look_samples` copies the arrays into a `Field_Look_Samples` the job carries, and `run_field_job` calls `write_field_water_look(grid, samples)`.
- **B, the coarse base.** `gather_coarse_field_grid` runs `field_water_look_base` per loaded sample on the main thread today: one integer square root (`field_water_span`) per sample that is not ground. The probe counted 4,163 of them at level 1 and 599 at level 2 in the shore world below. It copies each loaded sample's fill and still owner into a `Field_Coarse_Water` instead, and `generate_field_grid` writes the base on the worker.

**The waves.** The gather copies `Field_Wave_Chunk.baked` (i8) by row runs, not the heights.

- At every gather, `baked[i]` equals `active ? field_wave_baked(height[i]) : 0`:
  - Heights change only in `advance_field_waves`, which ends in `mark_field_wave_changes`.
  - A sample leaving the active set has its `baked` zeroed in `step_field_waves`.
  - `stream_field_session` advances the waves before the gather.
  - `wave_clamp_percent` is at most 50, so `|round(h·128)| <= 64` and the i8 clamp never bites.
- The probe checked this over 400 frames of a settled lake's impact: 4,816,896 samples compared, none different, the largest offset 19.
- Copying the f32 heights instead was rejected: 219,488 bytes a job, and a float round per sample on the main thread.

**Alternatives rejected:**

- Building today's `Field_Look_Samples` on the main thread and shipping it. That keeps on the main thread the per sample owner, front and level work and the interior pass.
- Workers reading `Field_World` under a lock. The tick writes the chunks on the main thread, and the lockstep cannot wait on a mesher.
- Ref counted immutable chunk snapshots. That is lifetime machinery for a 400 KB copy.
- A copy of every body's level. Up to 65,534 bodies, and O(bodies) per job.
- `Water_Body.chunks` read backwards to find the owners. It is derived state, a superset whose completeness the look would then depend on.

### Types (`world_field_water_look.odin`)

- `Field_Look_Owner :: struct {owner: Water_Owner, owned: bool, level: i64}` (16 bytes): one owner's level and whether it names the sea or a live body.
- `Field_Look_Owners :: struct {list: [dynamic]Field_Look_Owner, cached: Field_Look_Owner}` (56 bytes): every owner a copy names, once, and the last one looked up. The zero `cached` is safe, since `WATER_OWNER_NONE` returns before the cache.
- `Field_Look_Samples` is replaced. Fields in this order: `loaded [N]bool`, `density [N]i8`, `water [N]u8`, `still_owner [N]Water_Owner`, `moved [N]u8`, `wave [N]i8`, `awake_front [S*S]u64`, `interior [S*S]u64`, `wavy: bool`, `owners: Field_Look_Owners`, where N = `FIELD_LOOK_SAMPLE_COUNT` and S = `FIELD_LOOK_SIZE`.
  - Size: 407,272 bytes (286,152 today).
  - `chunks: [27]^Field_Chunk` and the three `cached_*` fields go.
  - `still_owner` holds the chunks' owners as copied. `finish_field_look_samples` clears the front's and those of an owner that is not owned.
  - `moved` is `Field_Chunk.water_moved`.
  - `wave` holds the baked offsets of every slot whose coordinate is in `waves`, loaded or not, and zero elsewhere. `wavy` is set when any of the 27 coordinates is in `waves` (today's `field_waves_near_node`).
  - `awake_front` is bit x of row `y + S*z`: awake and not a spring.
  - Update the struct's comment and the `FIELD_LOOK_REACH` comment above it.
- `Field_Coarse_Water :: struct {fill: [FIELD_GRID_SAMPLE_COUNT]u8, still_owner: [FIELD_GRID_SAMPLE_COUNT]Water_Owner, owners: Field_Look_Owners}` (117,968 bytes). Per grid index: a loaded sample's fill, and its owner unless `field_water_is_front`.

### Procedures

`world_field_water_look.odin`, main thread:

- `gather_field_look_samples :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, waves: Field_Wave_Heights = nil, allocator := context.allocator) -> ^Field_Look_Samples`. Replaces `make_field_look_samples`.
  - Allocates with `new(..., allocator)` and `owners.list = make([dynamic]Field_Look_Owner, 0, 8, allocator)`.
  - Looks up the 27 chunks, and the 27 wave entries when `len(waves) > 0`.
  - Then today's `slots`, `inners` and `RUNS` loop, per run:
    - Copy the wave run from `entry.baked[first:]` when the slot has an entry.
    - On a nil chunk, fill `density` with `-MAXIMUM_DENSITY`, then continue.
    - Otherwise copy `density`, `water`, `water_owner` into `still_owner` and `water_moved` into `moved`, and fill `loaded` with true (`slice.fill`).
    - Then `awake_front[row] |= (front & (u64(1) << uint(count) - 1)) << uint(run[0])`, where `front := (awake[word] & ~source[word]) >> uint(first & 63)`.
  - Last, the owner scan: one pass over `still_owner` that calls `note_field_look_owner` on each value differing from the last.
  - Called from `schedule_finest_field_mesh` and `schedule_field_wave_remeshes`.
- `field_water_owner_level :: proc(world: ^Field_World, owner: Water_Owner) -> (level: i64, owned: bool)`: the sea gives `sea_level`, a live body (`water_owner_body`) its level, else `0, false`. This is today's `field_look_owner_level` world branch.
- `note_field_look_owner :: proc(owners: ^Field_Look_Owners, world: ^Field_World, owner: Water_Owner)`: returns for none or an owner already listed, else appends it with `field_water_owner_level`.

`world_field_water_look.odin`, worker:

- `field_look_owner_level :: proc(owners: ^Field_Look_Owners, owner: Water_Owner) -> (level: i64, owned: bool)`: none gives `0, false`. On a cache miss it searches `list`; an owner not listed reads as not owned.
- `finish_field_look_samples :: proc(samples: ^Field_Look_Samples)`: today's per sample owner loop of `make_field_look_samples`, in the same row and x order, over the copies.
  - A non-none owner whose `awake_front` bit is set, or that is not owned, becomes none.
  - The rest feed `row_owners` and `still_rows` as today, then `mark_field_look_interior` (unchanged).
  - It is idempotent.
- `write_field_water_look :: proc(grid: ^Field_Grid, samples: ^Field_Look_Samples)`: calls `finish_field_look_samples` first, then today's body. The waves gate is `samples.wavy && samples.loaded[look] && samples.density[look] <= 0`, and the stamp goes through `field_look_wave_shifted_value`. Called from `run_field_job` and tests.
- New signatures, the world and the waves dropped:
  - `field_look_base(samples, look, span)`.
  - `field_water_wall_limit(samples, base, origin, target, wet, target_density)`: beyond the grid, `samples.loaded[look] ? field_look_wave_shifted_value(...) : i32(fine)`.
  - `stamp_field_water_sheet(grid, samples, spans)`.
  - `stamp_field_water_sheet_sample(grid, samples, spans, base, wet, look)`: when not owned it calls `field_look_sheet_mode(samples, look, sample, span)` in place of `field_look_cell` and `field_water_sheet_mode`.
- `field_look_sheet_mode :: proc(samples: ^Field_Look_Samples, look: int, sample: Sample_Coordinate, span: Field_Water_Span) -> Field_Water_Sheet_Mode`:
  - `moved[look] == 0` gives Resting.
  - Otherwise the down sample is `look + field_look_step(offset)`, where `offset[axis] = -sign` from `field_radial_axis(sample)`. When it is loaded with density at or under 0, today's fall and stand tests apply, with `water[down]` and `field_water_span(sample + offset)`.
  - Then Moving when any face neighbour's `density > 0`. Unloaded samples are -127, as today's nil chunk.
  - Else Resting.
- `field_look_wave_offset :: proc(samples: ^Field_Look_Samples, look: int, sample: Sample_Coordinate) -> i32`: 0 unless `wavy`. Otherwise `wave[look]`, else the radial up neighbour's (`look + field_look_step(step)` with `step[axis] = sign`), else the down one's. Callers sit in `-2 ..= 33`, so both stay inside 38³.
- `field_look_wave_shifted_value :: proc(samples: ^Field_Look_Samples, value: i8, look: int, sample: Sample_Coordinate) -> i32`: the clamp of today's `field_wave_shifted_value`.
- `field_coarse_water_base :: proc(water: ^Field_Coarse_Water, index: int, density: i8, sample: Sample_Coordinate, step: i32) -> (value: i8, plane: bool)`: today's `field_water_look_base` for a loaded chunk.
  - `density > 0` gives -127, false.
  - An owned still owner gives `field_water_plane_value(level, field_water_span(sample).middle, step)`, true.
  - Else `field_water_density(density, fill, sample)`, false.
- `destroy_field_look_samples :: proc(samples: ^Field_Look_Samples)` and `destroy_field_coarse_water :: proc(water: ^Field_Coarse_Water)`: nil safe, `delete(owners.list)`, then `free`.

Removed, since this change leaves them without callers: `make_field_look_samples`, `field_look_cell`, `field_water_sheet_mode`, `field_radial_down_neighbour`, `field_water_look_level`, `field_water_look_base`, `field_wave_baked_at`, `field_wave_offset`, `field_wave_shifted_value` and `field_waves_near_node`. `field_wave_baked` and `field_radial_axis` stay. The file imports `core:slice`.

`world_field_mesh.odin`:

- `gather_field_grid :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, allocator := context.allocator) -> ^Field_Grid`: the terrain and the light only, with the waves parameter and the look call gone. Comments at lines 37 to 46, 150 and 173 to 177 follow.

`world_field_lod.odin`:

- `gather_coarse_field_grid :: proc(world, node, allocator := context.allocator) -> (grid: ^Field_Grid, water: ^Field_Coarse_Water)`: both nil when no loaded chunk.
  - Per loaded sample: `water.fill[index] = chunk.water[source]`.
  - Unless `field_water_is_front(chunk, source)`: `water.still_owner[index] = owner`, and `note_field_look_owner` when the owner differs from the last.
  - `grid.water` and `grid.water_exact` are left zero.
- `generate_field_grid :: proc(generation, node, grid, coarse_water: ^Field_Coarse_Water = nil)`: in the loaded branch, first, when `coarse_water != nil`: `grid.water[index], grid.water_exact[index] = field_coarse_water_base(coarse_water, index, grid.density[index], sample, grid.step)`. A nil parameter keeps a hand built grid's values.

`world_field_streaming.odin`:

- `Field_Job` gains `look: ^Field_Look_Samples` and `coarse_water: ^Field_Coarse_Water` (88 to 104 bytes), with comment lines. The header comment's lines 16 to 21 follow.
- `submit_field_mesh_job` gains `look: ^Field_Look_Samples = nil, coarse_water: ^Field_Coarse_Water = nil`.
  - Lines 512 and 578: `gather_field_grid(world, coordinate)` with `look = gather_field_look_samples(world, coordinate, waves)`.
  - Lines 523 and 615: `grid, coarse_water := gather_coarse_field_grid(world, node)`, passed on.
- `run_field_job`, `.Mesh`: `generate_field_grid(..., job.coarse_water)`, then `if job.look != nil { write_field_water_look(grid, job.look) }` before the meshing. The two frees become `free_field_job_copies(job)`.
- `free_field_job_copies :: proc(job: Field_Job)`: `free(job.grid)`, the two destroys, then `free_field_job_frames(job)`. It also replaces the pair in `stop_field_streaming`.

Comments: `render_field_waves.odin` line 16 names `field_look_wave_offset` and the copied baked offsets. `world_field_water_look.odin`'s header (lines 19 to 21) and line 68 say the gather copies the baked offsets.

### The wave remesh path

Its scheduling, its two a frame, its order and its marks are unchanged. Its jobs carry the look like any finest job.

### Memory per job

| Job | Added | Today |
|---|---|---|
| Level 0 node meshed from its chunks | 407,272 + 128 (owners list) = 407,400 bytes | grid 314,448 |
| Level 0 node beyond the set, or a level 1 to 3 node reading a loaded chunk | 117,968 + 128 = 118,096 bytes | grid 314,448 |
| A node generated whole | 0 | nothing |
| Every `Field_Job` | +16 | |

Peak:

- The frame's cap of 8 submissions: 8 × 407,400 = 3,259,200 bytes added.
- 32 pending: 13,036,800 added, so 23,099,136 in all against 10,062,336 today.

The job allocates with the gather's allocator, the heap (`context.allocator`, which is `shared.allocator`), as the grid does. The worker frees after the meshing, and `stop_field_streaming` frees the queued jobs after joining the workers.

The look's temporaries now go on the worker's temp allocator, freed per job: spans 628,864, base 39,304, the bit rows. The main thread's frame temp loses up to about 1 MB per finest gather.

`loaded` and `interior` (66,208 bytes) stay in the job for one struct; moving them to the worker's temp was weighed and left out.

### What stays on the main thread

Per finest job:

- Two zeroed allocations, the grid (as today) and the samples.
- `copy_field_grid_part`, unchanged.
- Up to 4,332 run copies: 329,232 bytes, plus up to 54,872 wave bytes when the node has waves.
- One OR per run.
- A pass over 54,872 owners. The probe found 1 new owner for the settled lake and the sea, 2 for the stream.

Per coarse job reading loaded chunks: today's strided loop, plus 3 bytes and two bit reads per loaded sample.

Gone from the main thread:

- 39,304 spans per finest job.
- The base, and up to three wave map lookups per non-ground sample.
- The interior pass.
- The sheet: 265 wet visits for the settled lake, 434 for the stream and 1,357 at the shore (probe), each with up to 27 stamps, spans and the guard.
- One span per loaded non-ground coarse sample.

Profiler: 0342's `Streaming` section (marked before `stream_session_chunks`: the selection and the jobs). Read its `worst cpu Streaming` along the lake shore and at the sea. The look's time moves to the workers, where it delays a node's result and not the frame.

### Tests

Order: record the golden digests at the base commit before any production edit.

1. Add the tests below with their grid makers on today's API:
   - `gather_field_grid(world, coordinate, waves, context.temp_allocator)`.
   - `gather_coarse_field_grid` then `generate_field_grid(generation, node, grid)`.
2. Leave the constants at 0, run `./build.sh test quick` on the two golden tests, and copy the digests their messages print.
3. Name the base commit in the test's comment, then change the makers.

The verifier repeats this on the snapshot's parent.

`world_field_water_look_test.odin` (`import "core:hash"`), helpers:

- `look_test_grid :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, waves: Field_Wave_Heights = nil, allocator := context.temp_allocator) -> ^Field_Grid`: `gather_field_grid` with `allocator`, then `write_field_water_look` from `gather_field_look_samples` in temp. `look_test_mesh` uses it.
- `look_test_digest :: proc(grid: ^Field_Grid, seed := u64(0xcbf29ce484222325)) -> u64`: `hash.fnv64a` over `slice.to_bytes(grid.water[:])`, chained over `water_exact`. The mesher is a pure function of the grid, and the terrain arrays are untouched, so equal water bytes are equal mesh bytes.
- `make_shore_look_test_world :: proc() -> (world: Field_World, planet: Planet, generation: Planet_Generation, finest: Field_Chunk_Coordinate)`:
  - `make_test_planet()` with `radius_metres = 1000`.
  - `sea_level_metres = int(uncratered_relief(generation, {radius, 0, 0}) / POSITION_UNITS_PER_METRE)` (21), where `radius = metres_to_position_units(1000)`.
  - The generation is made again after the sea level is set.
  - `world.water_planet = make_field_water_planet(TEST_PLANET_SEED, planet, 1000)`.
  - `finest` is the chunk of `World_Position{radius + relief, 0, 0}`, {31, 0, 0}.
  - Chunks `finest + {-2 ..= 1}³` are generated and inserted.
  - The probe found 1,410 sea samples, 1,528 wet and 45,746 ground of 54,872 in the reach.

New tests:

- `test_the_lakes_water_look_keeps_its_recorded_bytes`. One golden per scenario. Each is a node whose neighbours are not loaded (one chunk world), except (d):
  - (a) `settled_body_test_lake(t, 10, &tick)` at `LOOK_TEST_CHUNK`.
  - (b) That lake struck at `look_test_surface_sample(7, 7)`, digests chained over 10 frames of `advance_field_waves` (`SHIPPED_WATER_LOOK`), `look_test_grid` with `waves.heights`.
  - (c) The stream, a lake being edited: the setup of `test_a_moving_stream_has_mesh_within_a_sample_of_every_wet_sample` (trough, settle, dig, step until `{11, 9, 7}` holds water), chained over the next 20 ticks.
  - (d) `make_two_chunk_water_world({0, 1})` with the border impact of `test_a_wave_at_a_border_remeshes_both_nodes`. Both chunks are chained over 10 frames: a neighbour loaded and a wave crossing a chunk border.
- `test_the_shores_water_look_keeps_its_recorded_bytes_at_every_level`: the shore world.
  - Level 0 at `finest`, all 26 neighbours loaded.
  - Levels 1 to 3 at `{L, floor_divide(finest, 2^L)}`, through `gather_coarse_field_grid` and `generate_field_grid` with its water.
  - One golden per level.
- `test_the_gathers_leave_the_water_to_the_worker`, settled lake and shore world:
  - `gather_field_grid`'s `water` is all 0 and `water_exact` all false, and so are the level 1 coarse grid's.
  - `gather_field_look_samples` has `interior` all 0 and `still_owner` equal to the chunk's `water_owner` at every loaded sample, so nothing is derived on the main thread.
  - After `write_field_water_look`, the digest equals (a)'s.

Tests adapted, same assertions:

- `test_still_water_of_a_dead_owner_draws_as_the_front`: `gather_field_look_samples` then `finish_field_look_samples`. It adds: the owners list holds the dead owner once, not owned.
- Lines 386, 389, 402, 405, 460, 461 (`context.allocator`), 493 and 585, 589 use `look_test_grid`.
- `world_field_water_test.odin:734` and `world_field_lod_test.odin:766` use `look_test_grid`.
- `world_field_mesh_test.odin:138` calls `gather_field_grid(&world, coordinate, context.temp_allocator)`.
- The coarse sites take two results and pass the water to `generate_field_grid`: `world_field_edit_test.odin` 215, 225 (`far, _ :=`) and 260; `world_field_water_test.odin:838`; `generation_planet_test.odin:216`; `world_field_lod_test.odin` 626 and 777.
- `world_field_streaming_test.odin:531`: the job adds `look = gather_field_look_samples(&world, coordinate)`.

`world_field_streaming_test.odin`, `test_a_finest_mesh_job_carries_the_look_to_the_worker`: the shore world, `start_field_streaming(TEST_PLANET_SEED, planet, 1000, 0)`.

- `schedule_finest_field_mesh` at `{0, finest}` queues a job with `look != nil`, `coarse_water == nil` and the grid's water all zero.
- `run_field_job`'s `water_mesh` equals `mesh_field_water_grid(look_test_grid(&world, finest), planet.palette, 1000, context.temp_allocator)` by `mesh_data_equal`.
- `{0, finest + {1, 0, 0}}`, whose +x neighbour is not loaded, queues a job with `coarse_water != nil` and `look == nil`. Free it with `free_field_job_copies`.
- `{0, finest - {1, 0, 0}}` is left queued, so `stop_field_streaming` frees a look.

### Docs

- `doc/presentation.md`, Field meshes, the Water bullet: the worker writes the water from the gather's copies.
- `doc/presentation.md`, The water's look:
  - The base bullet: `field_look_base`, `field_coarse_water_base`, the still owners, in place of `field_water_look_base` and `field_water_look_level`.
  - The full resolution bullet: the main thread copies (`gather_field_look_samples`, `Field_Look_Owners`), the worker derives (`finish_field_look_samples`) and writes. The 2.8 and 5.5 ms are now the worker's.
  - The sheet bullet: `field_look_sheet_mode`.
  - The gather bullet: the copied `Field_Wave_Chunk.baked`, the invariant in one sentence, `field_look_wave_offset`.
- `doc/architecture.md`, Threads and chunk streaming, the field bullet: the finest job also carries the look's copies, the coarse job the loaded samples' fill and still owner, and the worker writes the water from them.
- `doc/code_map.md`, lines 135 and 141: the new names, the removed ones out. `tools/check_docs.py` fails on a stale name; `doc/work/done/0294` is history and stays.

### Hand-back check

- **Memory a frame may draw from:** the copies are the job's, never drawn. The main thread never touches them after `submit_field_job`, and the worker or `stop_field_streaming` frees them, as the grid and the cover frames are freed today. No request is needed, and no draw list is involved.
- **A new participant in a shared budget:** each finest job is longer on the workers (the look, 2.8 to 5.5 ms in the test build). The caps (8 a frame, 32 pending, 2 wave remeshes) and the order are unchanged. Tree tiles, which wait for an empty mesh queue, and a node gated by `in_flight` wait that much longer.
- **A list without bound:** the owners list is bounded by the reach's samples and never drawn.
- **Save layout:** nothing saved or hashed changes.
- **Tests:** in memory only.

### Decided

1. Part B is in, because the goal says no water look on the main thread and the coarse base is the look's.
2. The baked offsets, not the heights.
3. An owner table per job.
4. The moved stamp as bytes, a copy, not bits built per sample on the main thread.
5. `loaded` and `interior` in the job.
6. Golden digests recorded at the base, not a 250 line copy of today's look kept in a test file as an oracle.
7. The sheet mode's owner check dropped (shown redundant above).

### Questions for the main agent

1. Part B widens the item's Change section by the coarse base, about 60 lines and 7 test call sites. Keep it here, or split it into a new item?
2. The goldens break on any deliberate change to the look or to the test worlds; the test's comment says to record them again. Accept that?
3. Verify's before and after needs 0342 landed first, with the "before" run taken on `main` without 0344. Is that the sequence?

### Decisions (main agent, 2026-11-11)

1. Part B stays in this item: the coarse levels' water base is the same work on the main thread, and one before and after run of 0342 judges both.
2. Golden digests are accepted, recorded by the implementer at the base commit before any edit and named in the report with the commit they were taken at.
3. Implemented after 0342 has landed, so the before run is `main` without it.
4. The peak of 23.1 MB of pending jobs (10.1 MB today) is accepted on the desktop. The phone's cap on pending jobs is the same number: if the phone's memory shows it, the cap falls there, a value in data.

### Deviations (implementation, 2026-11-12)

- 0367 and 0370 left the seam as specified: 0367 moved the moving stamp's expiry mark to the step's end and split `schedule_field_jobs` into two rounds, 0370 touched neither the look nor the streaming. The call sites changed inside the two rounds, nothing else.
- The test lines drifted. Four sites the specification did not list take the same change: `world_field_water_test.odin` `water_look_digest` (0367) and `world_field_lod_test.odin`'s finest and coarse grids use `look_test_grid` and the coarse water, and `generation_planet_caves_test.odin` (0380) uses `look_test_grid`, so its grid keeps its water.
- `test_the_gathers_leave_the_water_to_the_worker` also asserts that the shore's reach holds sea samples, so the shore case covers the sea's plane.
- The goldens were taken at 7bac58d.
