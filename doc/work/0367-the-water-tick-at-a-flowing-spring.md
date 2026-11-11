# 0367: The water tick at a flowing spring

Status: verified (2026-11-11)

0342's first check run (2026-11-11, the couch's RX 5700 under headless gamescope, 512 m, capped at 30) found what holds the spring start at 3 to 6 frames a second, the figure the user saw: not the GPU (2.0 ms a frame) but the simulation. At the spring view `field_water` costs 14.1 ms of a 14.9 ms tick (worst 24.4 ms), so the frame falls behind, runs about 10 ticks a frame (155 ms) and never catches up; beside it the streaming remeshes 8 nodes every frame (14.8 ms). The view never settles. Every other view of the run ticks in 0.3 to 1.0 ms and draws in under 6 ms. The user's bar is 60 frames a second at 512 m.

## Goal

Standing at a flowing spring, a tick costs what it costs elsewhere, and the frame holds 60.

## Controls

None.

## Change

- Find what the water tick does at the spring every tick (the stream's flow, the bodies it feeds, a body that never comes to rest) and make its steady state cost nothing: water that only repeats itself sleeps, deterministically, as 0301's budgets and the rest rule intend.
- The remeshing every frame: a mesh is rebuilt only when its water changed by what shows.
- 0301 (the water's cost per edit) and 0344 (the water's look on the workers) touch the same code: the design says what each keeps.

## Verify

- The checks and the suite, with the state hash of a session at the spring equal with and without the change where the change is a pure saving, or the behaviour change named in the log.
- 0342's spring view settles and passes at 512 m, in one and two viewports.

## Specification (design, 2026-11-11)

### What the code does at the spring

The profiled world is teleport: 0342's `tools/frame_profile.py` (its worktree, lines 67 to 74) starts `--name=frame_profile`, a new world from `default_world_file_settings` (`main.odin` 704 to 708, `ui_world_setup.odin` 40 to 52), whose `water_model` is the zero value, `Teleport` (`world_chunk.odin` 62 to 65). The 14.1 ms are the teleport model's. The tech demo's bodies model is covered too.

Teleport, every tick (`world_field_water.odin`):

- Every sample awake at the tick's start runs once (`step_field_water_teleport`, 1020 to 1049). A spring refills to full on every tick it runs (`field_water_source_fill` 687 to 697, applied at 903 to 906), and a sample that moved anything stays awake (932 to 935). So the spring and every sample its water passes through run every tick for as long as the spring can spread.
- Nothing above the sea drains. The sources only add, and a missing chunk's sample above the sea is a wall (376 to 382, 419 to 424). The spring's water ends as films, each losing a fill every 60 ticks while awake (701 to 719, 911 to 919), or as standing water that only grows: a hollow, or the set's edge 64 to 128 m from the player. A teleport spring never reaches a state that repeats.
- Each move writes two samples (721 to 724). Each write marks the look and wakes the sample and its six neighbours (533 to 541, 522 to 529). A wake of a dry sample checks the sea and the full water under it: up to eight spans (443 to 461), each an integer square root by Newton steps of 64-bit division (`generation_planet.odin` 190 to 202). A write the same tick undoes (a stream sample losing and regaining its flow, the spring refilled and drained) costs all of this too.
- Every wake clears the pull's failed bit (484 to 489), so a not-full sample resting on full water beside moving water searches again on every tick (927 to 929): up to 128 visits a search and 20,000 a tick (`data/game.sjson` 169, 170), six spans per full sample visited (853). A search the tick's budget postponed keeps its sample awake (932).
- At the lake and the sea, by the rules, nothing stays awake (generated water sleeps until woken, 0312; a settled lake is held by the band), so the step has nothing to run: the profile's `tick field_water` is 0.001 ms at the lake, the sea and the home.

Bodies at a spring: the front plans per awake sample (1122 to 1205), `apply_field_water_front` visits all 32,768 samples of every pass chunk every tick (1219), and the spring is written twice a tick (the refill 1104, 1105, the apply 1229).

The meshes:

- Every write during the step marks the chunks that read the sample (`mark_field_look_dirty`, `world_field_water_look.odin` 133 to 136, from 539, 551, 718, and 172 when the moving stamp ends), whatever the sample holds when the tick ends, though a frame only ever reads the state between ticks. Each mark also lists the chunk in `edited_chunks` (128), so every meshed coarse node over the 27 chunks round it remeshes (`mark_edited_coarse_nodes`, `world_field_streaming.odin` 630 to 651).
- `schedule_field_jobs` (591 to 621) sends the finest nodes first, nearest first, then the coarser ones, 8 a frame (39). At the spring about 10 ticks run between two frames, so the stream's chunks are dirty again at every frame, the finest pass fills the 8 with them and the coarse pass never runs. The 317 selected nodes never meshed starve: 0342's settle counts a node not in `mesh_revisions` (`render_field.odin` 476 to 484 in its worktree). The remeshed nodes are not stale at once, they are written again by the next frame's ticks.

Not settled without the probe: the split of the 14.1 ms between the writes and wakes, the pull, the films and a growing pool; whether the stream's bytes repeat from tick to tick (B1 and C1 pay on it); what a spring pours a tick; whether the water reaches the set's edge.

### Target

The water tick at the spring under 1 ms in 0342's profile under both models. Mesh jobs only for a change of the look between ticks, never-meshed nodes before any remesh, so the view settles. Where the water repeats itself, no mesh job. Under teleport the films' drying, a growing pool and the waves (question 4) still remesh; the probe says how much is left.

### Step 1: the probe, before any other change

Counters, the one production change before the figures, not saved, not hashed: `Field_Water_Step_Counts :: struct {writes, moves, moved_fill, wake_checks, wakes, neighbour_sets, searches, postponed, spring_outflow: i64}` in `world_field_water.odin`, held in `Field_World.water_step_counts`, reset at the top of `step_field_water_keeping_events`. Incremented: `writes` in `set_field_water`; `moves` and `moved_fill` in `move_field_water` and per planned move in `plan_field_water_front`; `wake_checks` per `wake_field_water_sample`, `wakes` when it or `force_wake_field_water_sample` sets a clear bit; `neighbour_sets` per `field_water_neighbours`; `searches` in `pull_field_water_pressure` past its two early returns, `postponed` at the budget's return; `spring_outflow` the fill a source sample moved out (teleport: `moved` in `step_field_water_sample`; bodies: its `outflow` after planning).

`test_report_the_water_at_a_flowing_spring`, new file `src/world_field_water_spring_report_test.odin`, inside `when WATER_SPRING_REPORT {` with `WATER_SPRING_REPORT :: #config(WATER_SPRING_REPORT, false)` above it. Run: `./build.sh test quick test_report_the_water_at_a_flowing_spring -define:WATER_SPRING_REPORT=true` in a `systemd-run --user --scope -p MemoryMax=8G` scope. It counts; its times are indicative (unoptimised), the timed figures are 0342's profile in the night window.

Scenarios, 7,200 ticks each, an empty input frame (`tick_field_test_simulation`):

- S1, teleport at the profile's spring: `test_field_game_config()`, `make_field_test_game_content()` with `content.planets = shipped_test_planets()` set again (the waters kept, as in the game), `start_field_test_session`, player 0 put by `teleport_field_player` at `surface_point_feet(&simulation, {"79.159", "150.561"})`.
- S2, the same under bodies: `start_field_test_session` gains `water_model := Water_Model.Teleport`, set into the settings.
- S3, the tech demo's start under bodies: `start_tech_demo_session(config, content, make_test_generator(DEFAULT_WORLD_SEED), DEFAULT_WORLD_SEED, {water_model = .Bodies, start = .Spring})`, run only when `planet_spring_start`'s spring lies outside S1's set (both positions logged).

Per window of 600 ticks, one line per scenario, means per tick (and the maximum where it says so):

- awake samples (wet, dry, springs) and awake chunks at the tick's start;
- the counters; the pull's `water_pressure` visits (and maximum), teleports, failures;
- samples whose fill differs from the tick before (a snapshot of every loaded chunk's `water`), samples changed at least once in the window, samples whose fill at the window's end differs from its start;
- films (awake, fill 1 to `minimum_fill`), standing water (awake, over the minimum, `water_flow` 0), wet samples with a face neighbour in a missing chunk;
- the loaded chunks' total fill and its growth;
- chunks marked a tick (`dirty` and `edited_chunks` cleared before each tick and counted after, outside the streaming window), `len(water_events)`, the tick's wall time.

At the end, per scenario, the digest of `field_state_hash` chained by `fingerprint_u64` over every tick: the before and after of the pure steps.

Streaming, in S1 and S2, starting at tick 6,600 with nothing meshed, as the profile's teleport left it: `start_field_streaming(seed, planet, spacing, 0)`, the selection `select_field_nodes(make_field_view(eye, planet, spacing, field_view_level_distances(config.field_view, 512)))` at `field_player_eye`, one frame every 10 ticks: `update_field_streaming` with `requested = nil`, `run_queued_field_jobs`, `take_current_field_meshes` (freed). Per frame: chunks `dirty` and `wave_dirty` before the update, `edited_chunks`, the jobs sent split into first meshes, remeshes, and remeshes of a node sent within the last 6 frames (a second), and the selected nodes not in `mesh_revisions` after the frame.

The implementer reports the figures and stops. What they decide:

- B1 and C1 pay when the samples whose fill differs from the tick before are far fewer than the writes.
- C1 is teleport's fix when the pull's visits and the wake checks are the larger part.
- C2 ships when `spring_outflow` exceeds 16 a tick.
- A total fill and a standing count that keep growing are a pool: question 3.

### Step 2: pure savings (the state bit identical)

**B1, the look marked by its change over the tick, both models.** In `world_field_water.odin`:

- `Field_Water_Touch :: struct {chunk: ^Field_Chunk, index: int, water: u8, moved, front: bool}`: a sample's look inputs as the step found them.
- `Field_Water_Touches :: struct {list: [dynamic]Field_Water_Touch, on, defer_wakes: bool}`, held in `Field_World.water_touches`, the list freed in `destroy_field_world`.
- `Field_Chunk.water_touched: Field_Sample_Bits`: the samples with a touch this step, zero between steps. Not saved, not hashed, not compared.
- `begin_field_water_touches :: proc(world: ^Field_World, defer_wakes: bool)`: on, the list empty. Called first in `step_field_water_keeping_events`, with false until C1.
- `note_field_water_change :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, mark: bool)`: while on, a sample's first call sets its bit and appends its `water`, `water_moved != 0` and awake and not a spring; while off, `mark_field_look_dirty` when `mark`. Called before the write in `set_field_water` (in place of 539), `write_field_water_quiet` (after its equality return, in place of 551), `dry_field_water_film` (in place of 718), `expire_field_water_moved` when `water_moved` is 1 (in place of 172), and with `mark = false` before `wake_field_water_sample` and `force_wake_field_water_sample` set a clear awake bit.
- `finish_field_water_touches :: proc(world: ^Field_World)`: C1's wakes first (below); then each touch whose `water`, `water_moved != 0`, or (owner not none) awake and not a spring differs from now gets `mark_field_look_dirty`, and its bit clears; the list empties, off. Called last in `step_field_water_keeping_events`.
- The bodies' level marks (`write_water_body_fills` 460 to 468, 650, 1281) and `note_water_owner_change` stay immediate. Outside the step every mark is immediate as today.
- Inside the step every change of `water`, `water_moved` or an awake bit goes through a note first, so a touch holds the tick's start: `sleep_field_water_sample` gains the world (its 12 calls) and notes with `mark = false` before it clears a set bit. Today a sleep marks nothing, so an owned sample going from front to plane without a write was never remeshed; B1 marks it. `absorb_front_water` zeroes the stamp after its immediate mark (1289 to 1291).

**B2, never-meshed nodes first.** `schedule_field_jobs`: its finest pass and its coarse pass run twice, first over the selected nodes not in `mesh_revisions` (the finest, then the coarser, nearest first), then over the rest as today, then the waves. A node's membership is read before its own submission. Its comment follows.

**B3, the square root.** `integer_square_root` (`generation_planet.odin` 190): an estimate from `math.sqrt(f64(value))` clamped to `0xFFFF_FFFF`, then lowered while the root squared exceeds the value and raised while the root is under `0xFFFF_FFFF` and the next root squared is at most the value. Exact for every u64, so every caller, the generation's included, gets the same result. The float is an estimate, never state. Imports `core:math`.

**B4, the bodies' apply.** `Field_Water_Front_Pass.received: Field_Sample_Bits`, set in `plan_field_water_front` where the receiver's delta grows (1194). `apply_field_water_front` visits the bits of `awake | received` in index order in place of every index (1219): the same samples in the same order.

### Step 3: behaviour changes

**C1, teleport: a write wakes at the step's end, and only for a changed fill.**

- `begin_field_water_touches(world, world.water_model == .Teleport)`. `Field_Chunk.water_written: Field_Sample_Bits`, zero between steps, not saved.
- While `defer_wakes`, `set_field_water` sets the sample's `water_written` bit in place of `wake_field_water_around`.
- `finish_field_water_touches` first clears `defer_wakes`, then for each touch of the list as it stood (the wakes append flips): a sample whose `water_written` bit is set and whose fill differs from its touch gets `wake_field_water_around`, and the bit clears. The wakes write no fill, so their order changes nothing.
- What changes: a write the tick undoes wakes nobody and clears no failed bit; a film's drying still wakes nobody (no `water_written`); the wakes land after every sample ran, so a sample an earlier change woke counts its still tick and then restarts at zero (it sleeps a tick later), and a failed bit an earlier change would have cleared waits a tick. The player sees nothing in a pour, a dig or a stream; the banks of water that repeats itself and the air over it sleep instead of searching.
- An old save: no layout change; its awake and failed bits run under the rule from the next tick. The log names the rule, why, and each test whose tick count moved.

**C2, a spring's rate.** `field_water.spring_fill_per_tick` in `data/game.sjson` (its comment paragraph), `Field_Water_Config.spring_fill_per_tick`, `Field_Water_Tuning.spring_rate: i32`, 1 to 254 in `field_water_problem`, shipped 64: the link rate, about 15 cubic metres a second at 1 m spacing.

- Teleport: `field_water_source_fill` takes the sample's fill and the rate; a spring refills to `min(FIELD_WATER_FULL, fill + spring_rate)`, the sea edge as today.
- Bodies: `refill_field_water_front_springs` refills the start and the byte to `min(FIELD_WATER_FULL, start + spring_rate)`, skipping an equal one; a spring under a body's level or the sea's pours `spring_rate` (1136, 1144) in place of `rate`.
- The player sees thinner streams from springs, films nearer the spring, a spring under a lake raising it by its rate, 64 a tick as before. An old save: no layout change; springs pour at the rate from the first tick, the water already out stays. The log line gives the rate before and after.

### Tests

Recorded first, at the base commit, before any production edit (as 0344 does):

- `test_the_water_steps_state_stays_as_recorded` (`world_field_water_test.odin`, slow): per scenario one digest chained over every tick of every chunk's `field_chunk_state_hash` in coordinate order, `water_dropped`, `water_to_sea` and each live body's volume and level. (a) Teleport: the steps of `run_water_test_sequence` written inline on `make_two_chunk_water_world({0, 1})`. (b) Teleport: the pour of `test_a_pour_on_flat_ground_spreads_alike_both_ways`, 300 ticks. (c) Bodies: `make_body_test_world`, `carve_trough_test_lakes(&world, 0)`, settled, `dig_test_trough`, 200 ticks. (d) Bodies: `fed_outlet_trough_world`, 300 ticks. (e) The spring of `test_a_spring_refills_before_a_sender_plans_against_it` under each model, 300 ticks. All equal after step 2. C1 records (a), (b) and (e) teleport again, C2 (e) both, each named in the test's comment with the part.

New:

- `test_integer_square_root_edges` gains 0 to 4, k² and k² ± 1 for k at every power of two and its neighbours up to `0xFFFF_FFFF`, `max(u64)`, and 100,000 hashed values, each against a Newton reference kept in the test.
- `test_a_write_the_step_undoes_marks_no_chunk` (B1): touches on, a sample written 10 down and back: after the finish no chunk is `dirty` and `edited_chunks` is empty. A sample left changed within 3 of a border marks its chunk and the one across.
- `test_every_change_of_the_waters_look_marks_its_chunk` (B1, slow): scenarios (a), (c) and (e) teleport, after every tick: a loaded chunk whose look digest (its `gather_field_grid` grid's `water` and `water_exact`, 0344's `look_test_grid` if 0344 landed first) changed since the last check is `dirty`; `dirty` is cleared after each check. Skipped on ticks where a live body's `level` differs from its `meshed_level` (rate limited by design, `FIELD_WATER_LOOK_LEVEL_STEP`).
- `test_a_never_meshed_node_goes_before_a_remesh` (B2, `world_field_streaming_test.odin`): eight meshed finest nodes made dirty and a coarse node never meshed: the frame's jobs hold the coarse node, and a dirty finest node waits for the next frame.
- `test_a_teleport_write_the_tick_undoes_wakes_nobody` (C1): a full sample under a dry one that sleeps with its failed bit set; inside a teleport step's touches the full sample written down and back: after the finish the dry sample sleeps, failed. Written down only: it is awake, its failed bit clear.
- `test_a_spring_pours_at_most_its_rate` (C2), under each model: a spring at the top of a carved ramp, 600 ticks: the spring's `water_flow` is at most `spring_rate` every tick and the water reaches the ramp's foot.

Adapted: `test_a_spring_refills_before_a_sender_plans_against_it` (the refill is capped), `test_a_spring_under_a_lake_raises_it_by_its_rate` and `test_the_sea_does_not_rise_under_a_spring` (`spring_rate`), `test_field_water_pressure_values_are_bounded` or a sibling for the new key's bounds, and every teleport test whose tick count C1 moves, each named in the report with the old and new count.

Before reporting: `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, and the probe again after each step with its figures and its digests (S1 and S2 equal after step 2).

### Docs

- `doc/architecture.md`, The water field: Storage (`water_touched`, `water_written`, the step's scratch bits), Sleeping (C1), Sources and Bodies' front (C2's rate), The look (B1: the marks at the step's end for the samples whose look changed, `Field_Water_Touches`).
- `doc/architecture.md`, Threads and chunk streaming: the sentence on the order (B2).
- `doc/content.md`, the `field_water` paragraph: `spring_fill_per_tick`, its bound and shipped value.
- `doc/code_map.md`, the `world_field_water.odin` line: the step's touches.

### 0301 and 0344

- 0301 keeps its scope, the cost of an edit at a lake: the floods, the release and finish sweeps, `claim_sea`, the pull's budget after a dig. B3 and C1 lower its bench's figures, so it measures again; its optimised bench can be a report test beside this probe. Not overtaken.
- 0344 keeps all of it: B1 lowers how often its look runs, and B3 being exact leaves its golden digests as they are. Both edit `world_field_streaming.odin`: B2 reorders `schedule_field_jobs`, 0344 changes the gather call in its coarse pass. One stream, in series.

### Hand-back check

- A number from text: the new key bounded 1 to 254.
- A changed save layout: none. C1 and C2 change behaviour, named in the log; no old save stops.
- A shared budget: B2 puts a never-meshed node ahead of remeshes in the frame's 8, so a remesh waits behind the view's holes; the waves' room is unchanged. C1 lowers the searches that compete for the pull's 20,000.
- A list without bound: the touch list holds at most the samples a step writes, emptied every step, never drawn.
- Tests: in-memory sessions, saves "".

### Decided

1. Step 2 before step 3, proven by digests recorded at the base.
2. The look's inputs compared, not what the mesher would draw: a test of what shows would need the look per sample, the inputs are exact and cheap.
3. Holes before stale meshes, across the levels.
4. C1 for teleport only: the bodies' writes are already the tick's net delta (`apply_field_water_front` 1220 to 1230).
5. The pull's budgets stay (0301's).

### Questions for the main agent

1. The profile measured teleport, the brief says the user played bodies. The design covers both. Is the spring's target meant for both models?
2. C2 changes play (thinner streams, a submerged spring filling its lake at a quarter of the speed). Ship 16 with captures when the probe shows springs pouring more than that?
3. A teleport spring in a closed basin grows a pool for good, since nothing above the sea drains. If the probe shows the pool is the cost, nothing here meets the target there; the fix (a sink for standing teleport water, or a steady stream held as a rate) is a new item. Write it?
4. Under teleport every move into wet water is a wave event (775 to 777), so a teleport stream keeps the waves and their two remeshes a frame going along its whole length. Leave it (0294's look), or events only into sleeping water (presentation only)?
5. 0344 and this item edit `schedule_field_jobs`: which lands first?
6. Outside this item: `field_players` is most of every other view's tick (0.35 ms at the home, 0.93 at the lake, 0.77 at the sea and at the spring), one player standing still.

### Decisions (main agent, 2026-11-11)

1. Question 1: the target holds for both models. The check run's spring was a new world's default, teleport; the tech demo's captures were bodies.
2. Question 2: yes, C2 ships at 16 with captures if the probe shows springs pouring more.
3. Question 3: a teleport spring in a closed basin is 0370, written after the probe's figures.
4. Question 4: wave events fire only into sleeping water, as part of step 2 (presentation only), if the probe shows the waves' remeshes along the stream.
5. Question 5: this item lands first; 0344 follows in the same stream, in series, since both edit `schedule_field_jobs`.
6. Question 6: `field_players` is 0371.
7. The implementer stops after step 1 and reports the probe's figures; the main agent then confirms steps 2 and 3 or changes them.
8. 0342's views file gains a spring view under bodies beside the default's in this item, so the table judges both.

### Deviations (implementer, 2026-11-11)

- C1: an undone write leaves no moving stamp on a sample asleep (`finish_field_water_touches`), since no tick would count it down and the sheet would show moving for good.
- 0342's views file is not in this tree (ae770c5 landed after it was made): the spring view under bodies is added at the landing.
