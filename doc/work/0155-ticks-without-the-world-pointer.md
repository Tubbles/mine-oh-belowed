# 0155: Tick procedures without the world pointer

Status: todo (after 0154)

## Goal

Queue entry 3 of the architecture audits (`doc/audit/simulation.md`, refactor 7). After 0154 the kind ticks reach the records explicitly; what they still need from `^World` is the block store (reads at 26 sites, writes at 4) and the entity pools. For the engine cut, the game's tick takes its own state and a block interface, never the chunk store.

## Change

- One tick context struct (the entities, the game records, the content, the tick, the block query and the block write) that `tick_entities` builds once and the kind ticks take instead of `^World`; the block query and write are the two procedures the plugin boundary will carry.
- `tick_entities` takes the context; the player tick, which moves through blocks, keeps `^World` for now and is named in the item's notes as the next cut.
- `doc/architecture.md` (the simulation) states the shape; `doc/code_map.md` records lowered (simulation -> world falls by the block reads that go through the context).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`; the factory benchmark's two sizes in the suite still pass with the same state hash as before the change (the implementer records the hashes).
