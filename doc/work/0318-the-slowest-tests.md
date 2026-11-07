# 0318: The slowest tests

Status: verified (2026-11-07)

0316's measurement (`tmp/0316/test_times.tsv`, on a loaded machine): the whole suite is 664 s of wall time against 4345 s of summed test time on 8 threads, and the test binary took 75 s to compile at any selection on Odin dev-2026-09, 23 s on dev-2026-11a since 0315.

## Goal

The whole suite and every tier's compile take less time, and each test checks what it checks today.

## Controls

None.

## Change

- `test_the_hit_digs_the_crater_and_nothing_else` (346 s) is the tail. It starts at 318 s, since the runner sorts by name, and runs alone for the last 150 s. It checks every sample of the 125 loaded chunks at three spacings. Checking the chunks the crater reaches, and comparing the rest byte for byte with a copy, keeps "nothing else".
- The arrival tests (`run_arrival_test_world`, `arrival_test_bed`) re-run the 600 tick fall in 13 slow tests (626 s together). One fall shared per process, safe across the runner's threads and its memory tracking per test.
- A `-o:none` or `-debug` test build crashed LLVM on Odin dev-2026-09, while the game's `-debug` build compiles in 21 s. Retry it on dev-2026-11a, and use the faster build for the tiers if it compiles and the suite runs no slower.
- Each change is measured before and after with 0316's `build/test_times.tsv`.

## Verify

- The checks and the suite, with the same tests passing.
- The suite's wall time and the compile time before and after, on an idle machine.
- The unit tier's compile and run at `-o:none` and at the default, on an idle machine: unit keeps `-o:none` if it is faster there (28.5 s against 38.8 s at load 5).
- The field session tests' times in the implementer's `build/test_times.tsv` against main's: none over 10 s but those the specification names.

## Specification (design, 2026-11-07)

Designed against `main` and 0312's specification: 0312 gives `Planet_Generation` a slice (`lakes`) and makes `generate_field_chunk` read the planet's derived springs, so the cache below keys on the generation record, not on the generation. Whichever of 0312, 0310 and this item lands first, nothing here changes: both add to the record what their generation reads (`waters`, the forest).

### Where the time goes

A probe timing one arrival session alone on CPUs 8-15, beside other agents' builds (`tmp/0318/tree/src/probe_0318_test.odin`): `start_field_test_session` 0.015 s; the first `stage_generated_field_set` (125 chunks) 12.7 s; ticks 1 to 1000 with the hit 0.48 s; the save 0.1 s; its load 0.04 s; the staging after the load 14.3 s. The fall is 4% of a session. Generating the set is the rest, paid by every field session in the suite at every start and every load: every sample of the 125 chunks needs the relief (the shortcut skips none), about 3 µs each. A shared fall (0316's option 2, a save at the hit loaded by each test) would still pay the 14.3 s per load. So what is shared is the generated chunk: a process cache that the tests' staging copies (0.08 s for 125 chunks against 12.7 s).

The crater test per spacing, same machine: generating the set 15 to 28 s, twice (the "through" world); `expect_field_world_is_generation` 13 to 25 s; the `impact_crater_sample` pass 15 to 21 s; `expect_field_holds_the_crater` 19 to 21 s. Inside the crater's reach (the projection within `Crater_Term.reach` of the home): 4% of the samples at 1000 mm, 16% at 500, 36% at 333; the shortcut and `crater_distance` over all samples 1.3 to 2.5 s.

With this specification applied in the probe tree (`tmp/0318/tree`), loads 8 to 20 on CPUs 8-15, so the ratios count, not the seconds:

- The 24 arrival tests without the crater test: 189 s wall and 1342 s summed before; 79 s and 413 s with the cache alone; 47 s and 183 s with all of it, the three crater tests and the cache test included.
- The crater test: 164 s in `build/test_times.tsv` (346 s in 0316's run); split, 12, 41 and 65 s side by side in the slow tier.
- The slow tier (245 tests): 2980 s summed in `build/test_times.tsv`; with all of it 1161 to 1682 s summed and 151 to 219 s wall over three runs, every test passing, no leak reported. The unit tier (2015 tests) passes too.

A compiled sketch of Changes 1 to 3 passed the slow and the unit tiers: `/var/home/Tubbles/dev/mine-oh-belowed/tmp/0318/tree/src/field_chunk_cache_test.odin` and that tree's `simulation_arrival_test.odin`. It prints the cache's size every 50 claims and holds 100000 entries, for the measurement; this specification drops both and names the file `simulation_field_chunk_cache_test.odin`.

### Change 1: the chunk cache, `src/simulation_field_chunk_cache_test.odin` (new)

A test file of the simulation cluster. Header comment: the field chunks the test process generated (0318), shared by every test's sessions. A session's chunk is fixed by the seed, the spacing, the planet's generation record, the overlay flag and the coordinate: the record holds what generation reads off a planet (`generation_planet_record.odin`'s header), and what a session derives besides (0312's water features) comes from the seed and the record. So a session staged from the cache holds the bytes it would generate. The entries live on `runtime.heap_allocator()` for the whole process: the runner frees each test's allocator after the test (`free_all` on the thread's rollback stack) and reports what is left in it as leaked, so a fixture made in one test's allocator would vanish under the next (`data_strings.odin`'s missing key records are the precedent).

- `FIELD_CHUNK_CACHE_CAPACITY :: 2048` (728 MiB at `size_of(Field_Chunk)`, 372,832 bytes): the slow tier filled 900 to 949 entries over about 540 coordinates (337 MiB); the slow tier's process peaked at 1.4 to 1.7 GB with it. Past it the cache claims nothing and the tests generate as before.
- `Field_Chunk_Cache_Key :: struct {seed: u64, spacing_millimetres: int, record: Planet_Generation_Record, crater_overlay: bool, coordinate: Field_Chunk_Coordinate}`.
- `Field_Chunk_Cache_Entry :: struct {key: Field_Chunk_Cache_Key, chunk: ^Field_Chunk}`: `chunk` nil while the test that claimed it generates it; the key's springs cloned on the heap.
- `Field_Chunk_Cache :: struct {mutex: sync.Mutex, entries: map[Field_Chunk_Coordinate][dynamic]Field_Chunk_Cache_Entry, count: int}`, the global `field_chunk_cache: Field_Chunk_Cache`; the map and the buckets made with the heap allocator on first use.
- `Field_Chunk_Cache_Lookup :: enum {Cached, Claimed, Claimed_Elsewhere, Full}`.
- `field_chunk_cache_key :: proc(state: ^Simulation_State, coordinate: Field_Chunk_Coordinate, crater_overlay: bool) -> Field_Chunk_Cache_Key`: `state.world.settings.seed`, `state.field.spacing_millimetres`, `planet_generation_record(state.world.planet)` (borrows the springs), the flag, the coordinate. The inputs `stage_generated_field_set` passes to `generate_field_chunk`.
- `field_chunk_cache_keys_equal :: proc(first, second: Field_Chunk_Cache_Key) -> bool`: seed, spacing, flag and coordinate `==`; the springs `slice.equal`; the rest of the records `runtime.memory_equal` over `size_of(Planet_Generation_Record)` on local copies with the springs set to nil (`==` does not compile on a struct holding a slice). Equal bytes are equal fields, so this can only miss, never hand out a wrong chunk; a field added to the record is compared without a change here; a slice added later would compare by address, so the cache would miss across sessions (and the comment says to compare it by content).
- `find_field_chunk_cache_entry :: proc(key: Field_Chunk_Cache_Key) -> ^Field_Chunk_Cache_Entry`: the bucket's entry with an equal key, or nil; called with the lock held, the pointer used only under it (a later append may move the bucket).
- `look_up_field_chunk_cache :: proc(key: Field_Chunk_Cache_Key) -> (cached: ^Field_Chunk, lookup: Field_Chunk_Cache_Lookup)`: under the lock. An entry gives `.Cached` with its chunk, or `.Claimed_Elsewhere` while its chunk is nil; no entry with `count` at the capacity gives `.Full`; otherwise it appends an entry with a nil chunk (springs cloned), counts it and gives `.Claimed`.
- `fill_field_chunk_cache :: proc(key: Field_Chunk_Cache_Key, chunk: ^Field_Chunk)`: a heap copy (`copied^ = chunk^`, the overlay through `copy_field_crater_overlay` with the heap allocator) made outside the lock, set as the claimed entry's chunk under it.
- `copy_field_crater_overlay :: proc(overlay: [dynamic]Field_Crater_Sample, allocator: runtime.Allocator) -> [dynamic]Field_Crater_Sample`: nil for nil (`dig_impact_crater` skips a chunk whose overlay is nil and counts the others), else a copy in the allocator.
- `copy_cached_field_chunk :: proc(cached: ^Field_Chunk, chunk: ^Field_Chunk)`: `chunk^ = cached^`, the overlay copied into `context.allocator` (the session frees it with the chunk). No lock: an entry's chunk is never written or freed once set.
- `generate_cached_field_chunk :: proc(state: ^Simulation_State, coordinate: Field_Chunk_Coordinate, chunk: ^Field_Chunk, crater_overlay := false, defer_claimed := false) -> (generated: bool)`: `generate_field_chunk(seed, state.world.planet, spacing, coordinate, chunk, crater_overlay)` through the cache, `chunk` zeroed as `new` leaves it. `.Cached`: the copy, true. `.Claimed_Elsewhere` with `defer_claimed`: false, `chunk` untouched. Otherwise it generates into `chunk` and, when `.Claimed`, fills the entry; true. It takes the state, not a planet, so only a session's planet (record and derived parts consistent) reaches the cache; a test with a hand-built planet calls `generate_field_chunk`.
- `stage_cached_field_set :: proc(state: ^Simulation_State)`: `stage_generated_field_set`'s loop (each coordinate of `needed_field_chunks` neither loaded nor arrived, a `new(Field_Chunk)`, `stage_field_chunk_arrival`) through `generate_cached_field_chunk(state, coordinate, chunk, crater_overlay = true, defer_claimed = true)`. A deferred coordinate's chunk is freed and the coordinate kept in a temp list; after the loop each is generated with `defer_claimed = false` (a copy when its claimer has filled it, else generated again here) and staged. Tests starting together so share the generation of one set instead of each generating it: in the probe the first eight arrival tests took about 21 s each without the claims, 4 to 10 s with them. A claimer that never fills (a test that crashed inside `generate_field_chunk`) leaves its entry claimed and later tests generate that chunk themselves; nothing waits.
- `field_chunks_equal :: proc(first, second: ^Field_Chunk) -> bool`: every field of `Field_Chunk` by `==` (fixed arrays and bit words compare whole) and the overlays by `slice.equal`, for the tests.

The runner: each test runs on a pool thread with a tracking allocator over that thread's rollback stack, reset and `free_all`ed after the test. Nothing the cache keeps comes from `context.allocator`; the copies handed to a session do, and `end_session` frees them as today, so the per-test leak reports do not change. Alone, in a tier or filtered by name, the cache starts empty in each process; the first session of a key generates and fills, every later one (another test, a second world of the same test, a load after a save, a joiner) copies. Which test generates a chunk depends on the threads' timing, the bytes do not.

### Change 2: the tests stage through the cache

- Every `stage_generated_field_set(` in `src/*_test.odin` becomes `stage_cached_field_set(` (19 calls): `simulation_field_test.odin` lines 68 (`tick_field_test_simulation`), 363, 509, 590, 758, 808, 858, 886, 927, 972, 1637, 1658, 1867; `simulation_arrival_test.odin` 75 (`tick_arrival_test_session`) and 419 (`reload_arrival_test_world`); `lockstep_test.odin` 599 (`run_field_lockstep_test_ticks`); `hud_test.odin` 150; `field_trees_test.odin` 264; `machine_wear_test.odin` 326. Comments saying the set is generated on the test's thread add "through the process's chunk cache".
- `test_a_restored_field_set_matches_the_save_in_either_arrival_order` (`simulation_field_test.odin` 461 and 472): `generate_field_chunk(state.world.settings.seed, ...)` becomes `generate_cached_field_chunk(state, coordinate, chunk)` (flag false as today, a key of its own).
- Unchanged: `stage_generated_field_set` and its call in `benchmark_factory.odin` (the benchmark times the generation); the single chunk `generate_field_chunk` calls of the generation, edit, lod and load tests; `make_test_home_field` (`generation_planet_test.odin`), whose planets are hand-built.

### Change 3: the crater checks, `src/simulation_arrival_test.odin`

Every sample is still checked. The expected value is computed from the generation only where the crater can change the sample, and read from the generated chunk (a cache copy) elsewhere, where the whole, the baked and the generated sample are one by the code: `impact_crater_baked_sample` returns the whole sample unchanged at or past `term.reach` (its first branch), `crater_relief` returns the relief unchanged there (its first branch), and `generate_field_chunk` and `planet_sample` run the same `planet_sample_shortcut`, `surface_column` and `planet_sample_at_column`.

- `arrival_test_crater_may_change :: proc(generation: Planet_Generation, position: World_Position) -> bool`: `needs_relief` of `planet_sample_shortcut` and, with its projection, `term.reach != 0 && crater_distance(term, on_sphere) < term.reach` (`term := generation.crater`). Comment: false is the first branch of `impact_crater_baked_sample` and of `crater_relief`, so neither the dig nor the baked generation changes the sample.
- `expect_arrival_test_ground :: proc(t: ^testing.T, state: ^Simulation_State, expected: Planet_Generation, except_centre: World_Position, except_radius: i64, label: string, location := #caller_location)`: `testing.expect(len(world.chunks) > 0)` as today; for each loaded chunk in coordinate order a fresh `new(Field_Chunk)` filled by `generate_cached_field_chunk(state, coordinate, chunk, crater_overlay = true)` (the staged sets' key, so a copy) and `destroy_field_chunk`ed after it (fresh each time: `generate_field_chunk` expects a zeroed chunk); every sample farther than `except_radius` from `except_centre` (all of them with a negative radius) must equal `planet_sample(expected, position)` where `arrival_test_crater_may_change(expected, position)`, else the generated chunk's sample. The first that does not is named, `"%s: the sample %v is %v, not %v"` with the label, and the check returns.
- `expect_field_holds_the_crater` keeps its signature and comment, its body `expect_arrival_test_ground(t, state, baked_planet_generation(state.field.world.water_planet.generation), except_centre, except_radius, "the crater", location)`. Its callers (the joiner, the save during the fall, the old world twice, the world without a fall, the save at the tick before the hit) do not change.
- `test_the_hit_digs_the_crater_and_nothing_else` becomes `run_the_hit_digs_the_crater_and_nothing_else :: proc(t: ^testing.T, spacing: int)`, its body one pass of today's loop, called by three tests marked `@(test) // slow`: `test_the_hit_digs_the_crater_and_nothing_else_at_1000_mm`, `_at_500_mm`, `_at_333_mm`. The runner runs them side by side instead of one for the last 150 s; the comment adds "One test per spacing, so the three run side by side (0318)". In the body:
  - before the hit, `expect_field_world_is_generation(t, world, generation, "before the hit")` becomes `expect_arrival_test_ground(t, state, generation, {}, -1, "before the hit")`;
  - the dig check keeps its `before` copy, its log line, its loop and messages; per sample `expected` starts as the copy's, and only when `arrival_test_crater_may_change(generation, position)` is `impact_crater_sample` called, its baked sample taken and counted when `changed` (`changed` false otherwise, for the message). This is, sample for sample over all 125 chunks, the value today's loop expects, since `impact_crater_sample` reports no change wherever the gate is false: "nothing else" holds as strictly as today;
  - the second world, the raycast and `changed_count > 0` stay; its `expect_field_holds_the_crater` is the narrowed one.
- `expect_field_world_is_generation` stays in `generation_planet_test.odin` for `test_the_impact_dig_makes_the_baked_crater`.

### Change 4: `build.sh`, unit and quick unoptimised

In `run_test_tier`, after the arguments are split, before the build:

```bash
	# unit and quick build unoptimised (0318): their compile outweighs
	# their run. A given -o flag stays alone, odin refuses a second.
	if [ "$tier" = unit ] || [ "$tier" = quick ]; then
		case " ${flags[*]-} " in
			*" -o:"*) ;;
			*) flags+=(-o:none) ;;
		esac
	fi
```

`all`, `slow` and `nightly` keep their flags. Measured on dev-2026-11a (9a69916), the test binary, loads 8 to 20 on CPUs 8-15:

- Compile: the default (`-o:minimal`) 25.0 s at load 5, 37 s at load 8, 54 to 64 s at 11 to 20; `-o:none` 7.6 s at load 5, 13 to 18.5 s loaded; `-debug` 20.2 s loaded. Both compile; dev-2026-09's LLVM crash is gone.
- Run at `-o:none` against the default: the unit tier 20.9 s wall and 162 s summed against 13.8 s and 107 s at load 5 (43.2 s and 336 s against 29.4 s and 229 s loaded); the 24 arrival tests with the cache 100 s and 521 s against 79 s and 413 s; `test_arrival_ticks_zero_starts_landed` alone 26.3 s against 20.0 s (`-debug` 25.0 s). Every test passed.
- So unit costs 7.6 + 20.9 = 28.5 s against 25.0 + 13.8 = 38.8 s at load 5 (61 s against 87 s loaded), and a quick of the arrival file 117 s against 139 s loaded, while `all` and `slow` would lose a third to a half more run time on about 1160 s summed than the 17 s of compile they save. `-o:none` over `-debug`: 2 s less compile, and the debug information buys nothing in a test run.

### Docs

- `doc/build.md`, build.sh, the `test` bullet: `unit` and `quick` add `-o:none` unless a `-o:` flag is given (Test tiers).
- `doc/build.md`, Test tiers, the compile bullet: `unit` and `quick` build with `-o:none` (0318), the compile about a third of the default's and the run about 1.5 times slower; `all` and `slow` keep the default, their run outweighing the compile; `build/test_times.tsv` after a unit or quick run holds unoptimised times, so the slow mark is still read off a run of `all`. A new bullet: the tests' field sessions stage through the process's chunk cache (`stage_cached_field_set`, `src/simulation_field_chunk_cache_test.odin`, 0318): a set is generated once per process and copied into every later session and load; a test whose subject is the generation, or with a hand-built planet, calls `generate_field_chunk`.
- `doc/code_map.md`, the simulation cluster's Tests line: `simulation_field_chunk_cache_test.odin` (the tests' chunk cache, 0318).

### Tests

- `src/simulation_field_chunk_cache_test.odin`, `test_the_cached_field_chunks_are_the_generated_ones`: one `start_field_test_session(test_field_game_config(), make_field_test_game_content())`. A helper `expect_cached_field_chunk_is_generated :: proc(t: ^testing.T, state: ^Simulation_State, coordinate: Field_Chunk_Coordinate, crater_overlay: bool, label: string) -> ^Field_Chunk` generates the chunk with `generate_field_chunk`, then takes it through `generate_cached_field_chunk` twice (the second a copy), expects each `field_chunks_equal` to it and returns the generated one (the caller destroys it). The home chunk (the first player's position) with the overlay is the base; then, each changed alone on the session and set back after, each chunk expected to differ from the base: the overlay off, `world.planet.crater_at_impact` false, `world.settings.seed` plus one, `field.spacing_millimetres` 500, `world.planet.radius_metres` plus 1000. Then the chunk of the planet's first spring (`planet_spring_sample`; expect springs and a sample) against the same with `world.planet.springs` set to nil (and back). A key that left a part out would hand out the earlier chunk and fail: with the seed, the spacing and the record dropped from the key, the probe failed at every one of them. 1.7 s in the probe, unit or slow by the `all` run's time.
- Same file, `test_the_cached_field_set_stages_as_the_generated_one`: `test_field_game_config()` with `field_simulation.chunk_radius` and `chunk_margin` 0, two sessions; one staged by `stage_generated_field_set`, the other by `stage_cached_field_set` twice (the second stages nothing); the same arrived coordinates (at least one), each pair `field_chunks_equal`. Guards the copied loop against drifting from the game's. 0.3 s.
- The three crater tests replace `test_the_hit_digs_the_crater_and_nothing_else`; every other test keeps its name and assertions.
- Before and after per test: `build/test_times.tsv` of main's run of 2026-11-07 14:38 is the before, the implementer's run of `all` the after. A field session test still at 10 s or more is named in the report.

### Hand-back check

- A list that grows without bound is capped: the cache claims nothing past `FIELD_CHUNK_CACHE_CAPACITY`.
- Tests never touch the state directory: the cache is memory.
- The other lines do not apply: no memory a frame draws from, no file, no parsed number, no save, record or network layout, no shared budget, no HUD or UI audit case.

### The item's questions, answered

1. The shared fall: replaced by the chunk cache, since the fall is 4% of a session and a loaded save stages the set again. It serves every field session and load of the suite, not only the arrival file's.
2. The crater test: still every sample of the 125 chunks; the crater's work is computed only inside its reach, by a gate that is the code's own early return, and the test is split per spacing.
3. The test build: `-o:none` for unit and quick, the default for all and slow (Change 4).
4. Other slow tests: the field session tests of every file share the set (Change 2). In the slow tier those of 10 to 85 s take 1 to 31 s; the ones still at 10 s or more generate a set no other test uses (another seed, the old world's baked ground, a walk's new chunks, the restored set test's key without the overlay) or hash both worlds every tick. Not worth it now: `make_test_home_field`'s chunks (`test_the_rim_stands_above_the_surrounding_surface`, `test_the_crater_floor_is_flat_in_the_generated_field`, 39 and 27 s) are shared between the two at 1000 mm, about 20 s summed, but their planets are hand-built; `test_the_impact_dig_makes_the_baked_crater` (49 s) checks the generation itself; `test_a_new_world_holds_its_players_through_the_fall` (31 s) hashes both worlds every tick, which is what it checks; the benchmark, the UI audit and the block streaming test are their own subjects.

### Question for the main agent

1. Outside the crater's reach the narrowed checks compare with the generated chunk, not with `planet_sample` computed again. They are equal by the code read above, and `test_the_impact_dig_makes_the_baked_crater` still compares generated chunks with `planet_sample` round the home at the three spacings, but the 125 chunk sets are no longer recomputed sample by sample outside the reach. Accept, or keep `expect_field_world_is_generation` before the hit (13 to 25 s per spacing)?

### Decisions (main agent, 2026-11-07)

1. The chunk cache in place of a shared fall, as designed: the fall is 4 percent of a session.
2. The narrowed checks compare with the generated chunk outside the crater's reach: accepted. "Nothing else" means the hit changed nothing the generation made, and `test_the_impact_dig_makes_the_baked_crater` keeps the chunk against `planet_sample` check.
3. `test_the_cached_field_chunks_are_the_generated_ones` also asserts a hit: a second session of the same planet and seed gets `.Cached` for a coordinate the first filled. A record field that defeats the comparison (a slice compared by address, as 0312's and 0310's additions to the record might hold) then fails a test instead of silently slowing the suite. 0312 and 0310 land before or after this item; whichever lands second checks the assertion still holds.
4. `-o:none` for unit and quick, as designed; the idle measurement in Verify decides whether quick keeps it.
