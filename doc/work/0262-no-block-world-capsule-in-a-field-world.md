# 0262: No block world capsule in a field world

Status: todo (2026-10-05, found by the 0183 design: `make_simulation` places the block world's drop capsule in every world, so a field world carries a `drop_capsule` entity on frame 0 at the block pad (`query entities` lists it at 354 35 66 on the default seed) that nothing on the field draws, uses or saves on purpose; after 0183)

## Goal

A field world holds only the field's entities: the pod on its frame and what the player builds. The block world's drop capsule is placed only in a block world.

## Controls

No binding changes.

## Change

- `make_simulation` (or `choose_world_start`, where the block spawn search runs for every new world) places the drop capsule and runs the block spawn search only when the world is a block world; a field world's `World` carries no block pad.
- Old field saves that carry the capsule load as they are (the entity table reads what is there) or drop it with one log line; the design stage decides which and names what a joiner's snapshot does.
- Docs: `doc/architecture.md` (The field session, the start; the block world's capsule), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: a new field world's entity table holds no `drop_capsule` and `query entities` lists the pod only; a new block world (`--debug-terrain`) still holds its capsule; an old field save with the capsule loads.
