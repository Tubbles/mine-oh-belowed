# 0023 Save and load

Status: implemented
Milestone: M5

## Goal

Worlds persist. A world saves on quit, on request from the pause menu and on an autosave interval, and loads back into the same simulation state: blocks, light, entities with their contents, belt items, fluids, power, players, inventories, recipe unlocks, research, quests and statistics.

## Deliverables

- Save directory per `doc/architecture.md`: `$XDG_DATA_HOME/mine-oh-belowed/saves/<world>/` (fallback `~/.local/share`), with `world.sjson` (format version, seed, world settings, tick, day time, name) and binary files for chunks and entities. Refuse to load a newer format version with a clear message.
- Chunks: only chunks that differ from generation are written (a `modified` flag set by `world_set_block` and by outcrop exhaustion), each as the existing palette plus run length serialisation, grouped in region files by region coordinate. Unmodified chunks regenerate from the seed on load. Vein state (remaining amounts, exhaustion, draw counters) and the recorded outcrop cells save with the world since generation cannot recompute draws.
- Light on load: a loaded modified chunk gets its sky light recomputed with the same column procedure the generation workers use, applied to the saved blocks, then its border propagation queued like an arriving chunk; block light is re seeded from light emitting blocks in the chunk and from entity lights. Test that a saved torch lit cave is lit again after load.
- Entities: every pool serialised as plain values (they already hold no pointers), including belt cell items, fluid buffer levels, power credit, research state, quest progress, statistics, players with inventories, held stacks, selected slots and camera mode. Networks (belt lines, fluid networks, electric networks) are rebuilt after load, not saved.
- Autosave every N minutes (a `Settings` value, default 5) and on quit, with the simulation paused during the write; the pause menu gets a Save button and a toast confirms.
- Loading from the pause menu is not needed; loading happens from the title screen in 0024, so expose `load_world(name)` and `save_world(state, name)` with tests and a `--load=<name>` command line flag for now.
- Tests: round trip of a generated world with edits, entities of every kind with contents, belt items, fluid levels, research and quest progress, then 600 ticks of simulation after load compared bit for bit with 600 ticks of the original (the strongest test: save, load, run both, compare state hashes); the relight test; format version refusal; region file grouping.

## Verify

- Builds and tests pass.
- User: build a small base, save from the pause menu, quit, run again with `--load`, and find everything where it was and still running; then couch test 1.

## Notes

Implemented 2026-09-27. Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (359 tests), `./build.sh`, `./build.sh release`, `--version`. The binary was also run with `MINE_OH_BELOWED_SAVES` pointing at a scratch directory holding a save written by a throwaway test from the shipped data: `--load=<name>` read world.sjson, entities.bin and the regions (content fingerprint matched the real data) and then stopped at the missing display; with `format_version` edited to 2 it printed the "newer than this build reads" error and exited 1; `--load` with `--seed` exits 2.

Code: `src/save_binary.odin` (value codec, fingerprints), `src/save_state.odin` (entities.bin, rebuild after load, `simulation_state_hash`), `src/save_world.odin` (directories, world.sjson, regions, staging and swap, `save_world`, `load_world`, `make_simulation_from_save`), `src/save_test.odin`. `--load=<name>` and `--name=<name>` in `main.odin`, Save in the pause menu, autosave and save on quit in `loop.odin`, `Settings.autosave_minutes` (5).

### Deviations

- Saved chunks are kept in memory, not read from the region files per chunk. `World.saved_chunks` maps a chunk coordinate to its serialised bytes: load reads every region file into it (and checks that every chunk decodes), streaming hands a copy of the bytes to the generate job, and a modified chunk that streams out is serialised into it. Before this change an edited chunk lost its edits when it unloaded; it needs a home anyway, and with it saving never reads the old save while replacing it and workers never touch files. Memory is the serialised size of the modified chunks (a few KiB each).
- entities.bin is one file for the whole world, not per chunk as doc/architecture.md (Save format) says; entities are not bound to chunks in the simulation. The architecture section should be updated: whole world entities.bin, saved chunk store, `.saving` and `.previous` directories.
- The binary codec is written from type information (`write_value`, `read_value`): every field is written explicitly as little endian bytes of its size, booleans as one byte, slices length prefixed, nothing is copied as raw memory. This covers every field of the 13 pools, players, statistics, research and unlocks without a hand written line per field, which would silently drop fields added later. Dynamic arrays, maps, strings and pointers are refused and written by the callers. A layout fingerprint over the saved types is in the header, so a build whose saved structs changed refuses the save with a clear message instead of misreading it.
- Every file also carries a content fingerprint over the ids of blocks, items, machines, fluids, recipes, technologies, quests and vein types, because saved ids are dense indices into the data. Any change to those lists refuses old saves ("written with different game data"). Remapping by string id is left for later.
- A new world never overwrites an existing save: the directory becomes "world 2", "world 3" and so on when the sanitised name is taken. Otherwise starting the game without `--load` would clobber the last save on the first autosave.
- Replacing a directory cannot be one rename on Linux, so the swap is: write `<world>.saving`, move the old save to `<world>.previous`, move `.saving` into place, remove `.previous`. Loading falls back to `.previous` when only it exists.
- Beyond the listed state, the save also holds pending block changes, pending water updates, spent outcrop cells, each fluid network's fluid (a network fed only through machine ports keeps a fluid a rebuild cannot see), pool free lists and dead entries (for handle generations), and every player field (velocity, mining progress, craft queue, belt drag). All of it is needed for the bit for bit test.
- `queue_spent_outcrops` now sorts the cells it queues: it iterated a map, whose order differs between a world and its loaded save.
- Autosave counts simulated ticks, so a paused game does not autosave. Save and autosave show a toast. Saving is off on the debug terrain; `--load` refuses `--seed`, `--name` and `--debug-terrain`.
- world.sjson is written by `json.marshal` with `Specification.SJSON` (unquoted keys, no outer braces). `last_played_unix_seconds` is wall clock time, outside the simulation. `day_time_ticks` is informational; the day comes from the tick on load.
- Light on load: a restored chunk is generated first (veins, outcrop cells, open columns), then gets the saved blocks, its sky light from `fill_chunk_sky_light` with the open columns generation found, border seeding through `arrived_chunks`, and block light from its emitting blocks. Entity lights of lit lamps are registered on load and seeded into every arriving chunk (also fixes lamps going dark when their chunk reloaded).

### Not verified

- Anything in a window: the Save button, the toasts, autosave timing, save on quit, streaming of saved chunks while walking, and relight as seen on screen.
- A roof the player built in a modified chunk above a saved chunk is not seen by the open column test, so the chunk below can come back brighter than before (the same limitation as a generated chunk under a player built roof). Not tested.
- Malformed files: headers, counts, enums, booleans, slice lengths, pool handles, machine ids and chunk bytes are checked; item ids inside stacks and vein references are not range checked, a hand edited file with a wrong item id could still crash.

### Sizes

The round trip test world (8 chunks, 4 carved to a floor, one dug by the player, entities of every kind, after 300 ticks): world.sjson 212 bytes, entities.bin 34438 bytes, 4 region files with 4598 bytes in total.

### Open questions

- Should saves survive data changes (id remapping by string id, with a migration step), or stay strict until the content settles?
- Should autosave count wall time instead of simulated time?
- Should 0024's world list read `last_played_unix_seconds` and `day_time_ticks` as they are, or should world.sjson grow a play time counter?
