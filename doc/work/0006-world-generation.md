# 0006 World generation and streaming

Status: todo
Milestone: M1

## Goal

An unbounded procedural world generated lazily around the camera on worker threads, with the strata, biomes, trees and vein outcrops the design needs.

## Deliverables

- Layered OpenSimplex noise (`core:math/noise`) for height and moisture, a small biome table in `data/biomes.sjson` (plains, forest, hills, desert, lake, tar flats), strata (topsoil, stone, deep stone), rivers and lakes as still water blocks for now (flow is 0008), caves.
- Trees as block structures placed per biome density. Boulders.
- Vein reservoirs as entities per `doc/architecture.md`: placement from noise with the size classes and vein types of `doc/content.md`, an outcrop of ore textured blocks on the surface above each vein, the reservoir amounts stored on the vein, not in blocks.
- Spawn placement that satisfies the requirements in `doc/quests.md` (trees, stone, sand, water, iron, copper and coal outcrops within about 150 blocks).
- Chunk streaming: generation and meshing on worker threads (`core:thread`) with results handed to the main thread through a queue, a load radius around the camera, unloading beyond it, no hitches while sprinting.
- Determinism: the same seed and chunk coordinate always produce the same chunk, independent of load order and thread count. Tested.
- `--seed` command line argument for testing.

## Verify

- Builds and tests pass.
- User: walk 500 blocks in any direction and dig to the deep stone at 60 fps in 1080p without hitches from chunk loading, and find at least three vein outcrops on the way (the M1 verify statement).
