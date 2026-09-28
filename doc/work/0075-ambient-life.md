# 0075 Ambient life

Status: todo
Milestone: M11

## Goal

The planet is empty. Birds, insects and fish as light ambient life with no interaction keep the peaceful tone.

## Deliverables

- Birds as small flocks over forests and plains, insects near flowers, fish shadows in water; render only, driven by seed and tick, no simulation state.
- Tests: flock paths are deterministic.

## Verify

- Builds and tests pass.
- User: Screenshots over a forest.

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous. Lands after 0074; reduced motion stills nothing here (the life is slow and far), but the weather setting off keeps birds grounded in rain as the weather does anyway.

- Everything is render only in a new `src/render_life.odin` with the pure parts in `src/ambient_life.odin`: a function of the world seed, the tick and the camera, no state saved, like the weather.
- Birds: flocks are placed on a world aligned grid of 96 blocks; a cell has a flock when a hash of the seed and the cell passes the biome's `bird_density` (a new optional biome field in `data/biomes.sjson`, forest 0.6, plains 0.4, highland 0.3, wetland 0.5, beach 0.3, the rest 0; the column at the cell's centre picks the biome), of 5 to 9 birds; a flock flies a loop (a rounded rectangle of 40 by 24 blocks at 18 to 26 blocks above the surface at the cell's centre) with a period of 60 seconds, each bird offset along the path and by a bob, drawn as two dark quads (a body and flapping wings, the flap from the render time) only within 160 blocks of the camera and only by day and not in rain; nothing lands.
- Insects: near flowers, within 24 blocks of the camera: for the loaded chunks around the camera the mesher's flame list pattern is reused as a `covers` list per chunk (`Chunk_Mesh_Data` gains the cells of flower blocks, kept in `Chunk_Render`), and each flower cell gets two motes circling it (a small quad, a Lissajous path from a hash of the cell and the time), by day only.
- Fish: shadows in water, within 32 blocks: for each loaded chunk's water surface cells (the water parts' top faces are known to the mesher: keep a sparse list of surface cells per chunk with at least 2 blocks of water below), a hash decides on a fish shadow (one in eight cells); a dark ellipse quad half a block long glides just under the surface along a slow figure of eight from the time, drawn in the water pass order (before the water so the surface tints it).
- Cost: the visible flocks are a handful, insects tens, fish tens; say in the report what a forest lake view draws.
- Tests (`src/ambient_life_test.odin`): flock placement is deterministic per seed and cell and follows the density, the path stays above the surface height sampled at the cell, bird positions along the loop at phases 0, 0.25, 0.5, the insect and fish selection per cell, the mesher's cover and surface cell lists on a small chunk.
- Docs: `doc/architecture.md` (rendering: ambient life), `doc/content.md` (`bird_density`), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: new `src/ambient_life.odin`, `src/ambient_life_test.odin`, `src/render_life.odin`; `src/generation_biome.odin`, `src/generation_biome_test.odin`, `src/world_mesh.odin`, `src/world_mesh_test.odin`, `src/render_chunks.odin`, `src/loop.odin` (the draw calls), `data/biomes.sjson`, the docs above, this file.
