# 0005 Voxel world core: chunks, meshing, fly camera

Status: implemented
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

## Notes

Implemented 2026-09-27. Verified headless only: `./build.sh check`, `./build.sh test` (49 tests), `./build.sh`, `./build.sh release`, `--version`. Running without a display loads `data/blocks.sjson` and then stops with the "could not open a window" error as before.

### Deviations

- Texture coordinates: a greedy quad covers many blocks, and an atlas tile cannot repeat with the sampler's wrap mode. Each vertex therefore carries texcoords in blocks across the quad (0 to width, 0 to height) plus the tile's atlas origin in `texcoords2` (shader attribute `vertexTexCoord2`). The fragment shader samples `tile_origin + fract(texcoord) * tile_size`.
- F5 removes the topmost solid block of a column picked by hashing a counter, in the chunk column under the camera, searching down through at most 8 loaded chunks. A random block anywhere in the chunk would usually be buried and the hole would not show.
- "Two adjacent blocks give 10 quads" holds for two different block types. Two blocks of the same type merge into 6 quads. Both are tested.
- Dirty chunks are remeshed in `render_frame` of the same frame, right after `update_frame` marked them, before drawing.
- Keyboard gained Left Shift for Sneak and Left Control for Sprint (Minecraft layout), since the fly camera needs them and the key table had neither. F3 and F5 are the new `Toggle_Diagnostics` and `Debug_Remove_Block` actions.
- The mouse is captured (`DisableCursor`) while the world is shown and released while the diagnostics screen is open. The game starts with the diagnostics screen off. The diagnostics screen draws over the world on a translucent backdrop and gained a chunks, drawn, vertices line.
- The atlas is generated as a plain RGBA pixel array (testable without raylib) and wrapped in a raylib `Image` for `LoadTextureFromImage`, instead of `GenImageColor` plus `ImageDrawPixel` per texel.
- The block registry loads in `main` before the window opens, so a data error is reported without a window.
- Serialised chunks store neither light (recomputed in 0008) nor the chunk coordinate (the key of the future region file).
- Meshing runs on the main thread. Worker threads (architecture.md) are left for when generation streams chunks.

### Numbers for the debug terrain

Computed with a throwaway test over the 8 by 2 by 8 terrain (chunks x and z from -4 to 3):

- `Chunk` is 98320 bytes (64 KiB block ids, 32 KiB light), 128 chunks are about 12 MiB.
- Mesh: 24570 quads, 98280 vertices, 147420 indices over all chunks. The largest chunk has 2236 vertices, so every chunk fits one mesh part. At 32 bytes per vertex plus 2 per index that is about 3.4 MB on the GPU, and the same again on the CPU because raylib's `DrawMesh` only draws indexed when `mesh.indices` is set, so the CPU arrays stay alive.
- Worst case chunk (3D checkerboard): 393216 vertices, split into 6 parts of 65536.
- 136 hematite surface blocks. All 128 chunks serialise to 345688 bytes in total.
- Meshing all 128 chunks plus building and serialising them took about 1.5 s in the unoptimised test build. The first frame meshes everything, so expect a short stall at startup, shorter in release.

### Not verified (everything visual)

Shader compile and link on the couch GPU, fog, atlas look, point filtering, per chunk frustum culling against raylib's real matrices (the plane extraction is unit tested with `core:math/linalg` matrices), face winding on screen (unit tested against counter clockwise front faces), mouse capture, gamepad look and move feel, 60 fps at 1080p, the F5 hole, seams between chunks.

### Open questions

- Should F5 stay "topmost block of a random column", or was an arbitrary block (usually invisible) intended?
- Side face texture orientation follows the axis permutation, not world up. Invisible with noise tiles, but directional tiles (a grass strip on the dirt side) need world up mapped to image up.
- Fly camera speeds and look sensitivities are constants in `render_fly_camera.odin` until bindings and sensitivities move to configuration.
