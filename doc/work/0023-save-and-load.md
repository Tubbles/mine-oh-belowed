# 0023 Save and load

Status: todo
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
