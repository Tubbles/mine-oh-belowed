# 0005 Voxel world core: chunks, meshing, fly camera

Status: todo
Milestone: M1

## Goal

The rendering and storage foundation of the world: chunks in memory, meshed and drawn at 60 fps, with a free flying camera driven by the action layer. No generation, lighting, physics or editing yet beyond a debug action that proves remeshing works.

## Deliverables

- Chunk storage per `doc/architecture.md`: 32 by 32 by 32 blocks, block id `u16` and light `u8` in flat arrays, chunks in a map keyed by chunk coordinate, world to chunk and local coordinate conversion, block get and set with a dirty flag per chunk.
- Block prototypes loaded from `data/blocks.sjson` (id, name, solid, texture per face group), at least air, stone, dirt, grass, sand, and an ore textured block. Ids resolved to dense indices at load time.
- A placeholder texture atlas generated at startup (flat colours with a little noise per block type, 16 by 16 texels per tile), no image files. The art direction for this era is Minecraft flatness.
- Greedy meshing per chunk into one raylib `Mesh` per chunk with per vertex colour for later light, face culling against neighbour chunks, uploaded with `UploadMesh`, freed and rebuilt when dirty. Frustum culling per chunk. Fog to hide the load boundary.
- A fixed test world built in code at startup (about 8 by 2 by 8 chunks: stone below, dirt and grass on top, some sand patches, a few ore blocks) so the mesher has something real to chew on until generation lands in 0006.
- A free flying camera using the action layer: `move` from the left stick and WASD, `look` and `look_delta` for the view, `Jump` up and `Sneak` down, `Sprint` for speed. Gyro and trackpad already feed `look_delta`.
- A debug action (keyboard F5 is enough) that sets a random block in the chunk under the camera to air and remeshes it, proving the dirty path.
- Palette plus run length chunk serialisation (`serialize_chunk`, `deserialize_chunk`) using the existing run length codec, round trip tested. Not yet written to disk.
- Tests: coordinate conversion at negative coordinates and chunk borders, greedy mesher on tiny hand made chunks (face and quad counts for a single block, two adjacent blocks, a full chunk with no exposed inner faces), chunk serialisation round trip.
- The diagnostics screen stays reachable behind a toggle (F3) and shows fps, tick, chunk count, drawn chunk count, vertex count.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh`, `./build.sh release` pass.
- User: flying around the test world at 1080p holds 60 fps, the F5 edit shows a hole appear, no seams or missing faces between chunks.
