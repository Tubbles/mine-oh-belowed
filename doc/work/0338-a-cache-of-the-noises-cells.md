# 0338: A cache of the noises' cells

Status: verified (2026-11-12)

From 0337's design (its part B) and 0314's (its next lever). A relief read in the home's view is 83 lattice hashes, 82 of them the 8 corners of its 10.3 noise evaluations, and neighbouring reads fall in the same cells: a simulated cache of 256 cells served 94 to 95 percent of the tree tiles' reads' noise evaluations (0337, The counts that decided it).

## Goal

Every relief read hashes a noise cell once while it stays near, with the same noise.

## Controls

None.

## Change

- Value and gradient noise take their cell's 8 corner hashes from a small per thread cache keyed by the seed and the cell.
- Docs: `doc/architecture.md` (World generation, the terrain field).

## Verify

- The checks and the suite, with the parity tests of 0306 and 0314 unchanged.
- `test_report_the_relief_cost` on `main` and on the item, in the night window: the landing waits for a gain in its grid, chunk and tree lines.

## Specification (design, 2026-11-11)

Cut from 0337's specification (designer's probe in `tmp/0337/tree`, the simulated cache in `tmp/0337/probe_tree_source.diff`), designed on `main` at 2e7d874.

The change (`generation_planet.odin`, `generation_planet_landforms.odin`): `value_noise` and `gradient_noise` take their cell's 8 corner hashes from a per thread cache of 256 cells keyed by the seed and the cell. The hashes are `hash_lattice`'s, a pure function of the two, so every noise gives the same value. A simulated cache of 256 cells served 95% of the reads' noise evaluations (82 of a read's 83 hashes) and every other reader of the two noises: the chunks, the grids, the climate, the cover, the waters' tiles (0326) and the caves (0327). What it saves in time the night's report shows; the hashes are a count, not the cost.

### Files and procedures

`src/generation_planet.odin`, beside `hash_lattice`:
- `NOISE_CELL_CACHE_SLOTS :: 256`; `Noise_Cell_Slot :: struct {seed: u64, cell: [3]i64, hashes: [8]u64, filled: bool}`; `@(thread_local) noise_cell_cache: [NOISE_CELL_CACHE_SLOTS]Noise_Cell_Slot` (26.6 KB a thread), comment: the last cell each slot saw, per thread, so no lock; the hashes are a pure function of the seed and the cell, so the noise is the same bytes with or without it (0338).
- `noise_cell_slot :: proc(seed: u64, cell: [3]i64) -> int`: `mixed := seed ~ u64(cell.x) * 0x9E3779B97F4A7C15 ~ u64(cell.y) * 0xC2B2AE3D27D4EB4F ~ u64(cell.z) * 0x165667B19E3779F9`, slot `(mixed * 0x9E3779B97F4A7C15) >> 56`, with `#assert(NOISE_CELL_CACHE_SLOTS == 256)`.
- `noise_cell_hashes :: proc(seed: u64, cell: [3]i64) -> [8]u64`: the slot's hashes when it is `filled` with the seed and the cell, else `hash_lattice(seed, cell + {index & 1, index >> 1 & 1, index >> 2})` for each corner index stored with the key.
- `lattice_value_of_hash :: proc(hash: u64) -> i64`: `i64(hash >> 47) - NOISE_ONE`; `lattice_value` calls it.
- `value_noise`: the corners from `noise_cell_hashes(seed, cell)` through `lattice_value_of_hash`. The header names the cache.
- `generation_planet_landforms.odin` `gradient_noise`: `direction := directions[hashes[index] >> 60]` from `noise_cell_hashes(seed, cell)`.
- `lattice_noise_range` (0314) keeps reading `lattice_value` and `hash_lattice`.

No data key, no record field, no save change, no string.

### Tests

`src/generation_planet_test.odin`:
- `test_the_noise_cell_cache_gives_the_noise`: helpers `value_noise_uncached` and `gradient_noise_uncached`, today's bodies with the corners from `lattice_value` and `hash_lattice`. Three seeds (`hash_combine(DEFAULT_WORLD_SEED, 1 to 3)`) taken in turn point by point so slots are evicted; wavelengths 12, 96, 520 and 2400 m; 20,000 hashed points within 40 km per axis and a walk of 2,000 points a metre apart along a hashed direction: `value_noise` and `gradient_noise` equal the uncached ones at every point; then `noise_cell_hashes` of 1000 hashed cells equals `hash_lattice` at each corner.

Unchanged and passing: 0306's and 0314's parity tests (`test_the_bounded_generation_matches_the_samples` and its three siblings, `test_an_old_world_file_keeps_its_relief`), `test_landform_relief_matches_the_design` and the value noise tests, which pin values the cache must keep.

### Docs

- `doc/architecture.md`, World generation, the terrain field's bullet, after the sentence naming gradient noise: value and gradient noise take their cell's 8 corner hashes from a per thread cache of 256 cells (`noise_cell_hashes`, 0338), so nearby reads hash a cell once; the hashes are the lattice's, so nothing generated changes.

### Hand-back check lines that apply

- A changed save layout: none; every noise is the same bytes, proven by `test_the_noise_cell_cache_gives_the_noise` with the parity tests.
- A new participant in a shared budget: the cache takes 26.6 KB of thread local memory on every thread that generates (the workers, the simulation, the main thread, the test runner's).
- Tests never touch the state directory: all generate in memory.

### Decisions (main agent, 2026-11-11)

1. A stream of its own from `main`. 0326 changes `generate_field_chunk` in the same file and 0327 reads `gradient_noise`; neither changes the two noise procedures, so the rebases meet no shared line.
2. The landing waits for the night's report: the counts are hashes, not cost, and a lookup of a 26.6 KB table competes with the generation's own data for the first level cache. A run without a gain in the grid and chunk lines closes the item as cancelled with its figures in the log.
3. The cache holds nothing a result depends on: no test and no code may read `noise_cell_cache` except `noise_cell_hashes`. The review checks that a slot's key compares the whole seed and all three coordinates.
