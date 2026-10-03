# 0006 World generation and streaming

Status: implemented
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

## Notes

Implemented 2026-09-27. Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (69 tests), `./build.sh`, `./build.sh release`, `--version`, `--seed=bogus` (exit 2). Without a display the game prints the spawn (`world: seed 20260927, spawn at -64 46 64`) and stops at the "could not open a window" error as before.

### Layout

- `generation_seed.odin`: `--seed` default, one sub seed per `Generation_Purpose` from hashing (seed, purpose), column hashes.
- `generation_terrain.odin`: height (continental, hills masked to higher ground, detail, rivers along a noise zero line), moisture, strata, still water up to `SEA_LEVEL` (32), caves from 3D noise on a 4 block lattice with trilinear interpolation. Chunks above `GENERATION_CEILING` are air and chunks below `CAVE_FLOOR` (-128) are deep stone, both without noise. Deep stone starts below y -24.
- `generation_biome.odin` plus `data/biomes.sjson`; `generation_vein_tables.odin` plus `data/veins.sjson` (size classes, vein types, richness, spawn vein types).
- `generation_features.odin`: trees (cell 6) and boulders (cell 16) from per cell hashes, placed into air only, in the order logs, boulders, leaves.
- `generation_veins.odin`, `world_vein.odin`: veins per region, outcrops, registration in `World` (`veins`, `vein_indices`, `column_veins`).
- `generation_spawn.odin`: spawn search. `world_streaming.odin`: job queue, workers, load and unload.

### Deviations

- Vein type definitions and size classes live in `data/veins.sjson`, since content is never hardcoded. Units are the vein's total output split over its outputs by percent (spoil included). The spoil of the mixed vein type is gravel (content.md leaves it open).
- Veins get richer and larger with the distance of their region centre from the world origin, not from the spawn: the spawn search depends on the veins, so the veins cannot depend on the spawn. Units grow by 1 + d / 2048, the radius by one block per 2048 (at most 3). Concentrations need at least 1024 blocks.
- Vein footprints lie wholly inside their region, so a column's veins come from its own region alone. A vein that finds no free spot after 16 tries is skipped, so a region can hold fewer than the class minimum (never observed in the tests over 3 seeds and 144 regions each).
- Caves never open to the surface: every cave keeps at least one block of roof below the lowest surface among its column and the four face neighbours, four blocks where any of those has water. That is the simplest rule that guarantees no cave touches water.
- Water is not solid. The mesher now draws a face against any different non solid block, so solid blocks show against water and water shows against air only. Water is opaque (no blending) until lighting and transparency land.
- Trees and boulders skip columns inside vein footprints so outcrops stay readable. Hills have stone as top and filler block, which gives the "exposed stone" of the spawn requirements along with boulders.
- The spawn search tests candidates on square rings 32 blocks apart around the origin and takes the first that satisfies every requirement; mixed veins do not count as iron or copper. Vein distance is measured to the disc centre. If nothing within 2048 blocks qualifies it prints a warning and starts at the origin.
- A chunk is meshed only once every face neighbour inside the load volume is loaded, so a chunk is normally meshed once instead of once per arriving neighbour. A neighbour arriving later (camera moved) marks loaded non air neighbours dirty. Stale mesh results (an older revision than the latest submitted) are dropped. Mesh jobs carry private copies of the chunk and its six neighbours.
- Limits per frame: 16 generated chunks inserted, 8 mesh jobs submitted (each copies up to seven chunks on the main thread), 6 non empty mesh uploads, 48 jobs pending. Workers: processor cores minus one, 1 to 6.
- `build_debug_terrain` stays behind `--debug-terrain`: the world is built on the main thread as before, nothing streams or unloads, meshing goes through the workers.
- `--seed` takes decimal digits only. `strconv.parse_u64` accepts separators and silently wraps past the u64 range, so a small parser does it.
- Vein registration keeps veins and column entries when chunks unload, so vein state survives until saving lands.

### Timings (this machine, headless tests)

- Release (`-o:speed`, one test thread): generation 0.44 ms per chunk, meshing 1.9 ms per chunk (100 chunks at y -1 to 2 around the origin). Streaming the full load volume (13 by 7 by 13 = 1183 chunks, 716 non empty meshes) with 4 workers took 0.73 s.
- Debug test build under the parallel test runner: about 7 ms generation and 9 ms meshing per chunk, full volume in about 3.5 s.

### Not verified

Everything visual: the terrain look, biome bands, water rendering, trees, outcrop colours, fog against the load boundary, seams closing after late neighbours, the F5 hole on generated terrain. Real thread timing and frame pacing on the couch machine, 60 fps at 1080p while sprinting, memory use with about 1200 to 2000 chunks of 96 KiB loaded (roughly 110 to 190 MiB), the M1 walk of 500 blocks with three outcrops found.

### Open questions

- Water covers about 29 % and hills are capped at `TERRAIN_MAXIMUM_HEIGHT` (sea level plus 64), which makes flat tops on the highest peaks. Worth a look on the couch.
- All air and all solid chunks are stored in full. Storing uniform chunks as one block id would cut memory by about half; left for when saving touches the chunk layout.
- `doc/build.md` and `doc/architecture.md` do not yet mention `--seed`, `--debug-terrain` or the streaming limits (outside this item's allowed files).
- Moisture bands in `data/biomes.sjson` were tuned against a throwaway sample (lake 29 %, forest 20 %, plains 20 %, desert 13 %, hills 13 %, tar flats 5 %); coal veins (plains and hills only) are about 10 % of veins.
