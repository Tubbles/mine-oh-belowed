# 0008 Lighting and flowing water

Status: todo
Milestone: M1

## Goal

Sixteen level sky light and block light in the per vertex colour, so nights, caves and interiors are dark until lit, a torch as the first light source, a cosmetic day and night cycle, and Minecraft style flowing water. This closes M1.

## Deliverables

- Light storage: the existing `light: u8` per block holds sky light in the high nibble and block light in the low nibble (0 to 15 each).
- Sky light: a column receives 15 from above until the first opaque block; below it, light spreads to neighbours losing one level per block (flood fill), so cave mouths and overhangs are lit near their openings and dark deeper in. Computed per chunk at generation from the chunk's own columns plus a border margin, then propagated across chunk borders on the main thread when neighbours arrive or change, with a bounded work queue per frame.
- Block light: light emitting blocks (a `light_level` field in `data/blocks.sjson`, torch 14, others 0) flood fill the same way. Adding or removing a light source or an opaque block updates light incrementally (the standard add and remove propagation with a removal queue), never a full chunk recompute for one block.
- Rendering: the mesher writes light into the per vertex colour. Per face light is the light of the air cell in front of the face, and the vertex value averages the four cells around the vertex for smooth lighting and simple ambient occlusion (a solid neighbour darkens the vertex). Sky light is scaled by the day factor in the shader (a uniform), block light is not, so torches glow at night. Minimum brightness stays above black so caves are dark but readable.
- Day and night: a cosmetic cycle with the length from the world setting in `data/game.sjson` (default 20 minutes), sky colour and fog colour following the day factor, no gameplay effect.
- Torch: a placeable block (non solid, light 14) with a placeholder texture, in the block data, minable and placeable through the existing paths.
- Flowing water: Minecraft style cellular flow. Source blocks are infinite. Flowing water has a level 1 to 7 stored in the block id (eight water block ids, or a level nibble in a metadata byte per block if you add one; say which and why). Each tick a bounded number of scheduled water updates run: water spreads down first, then sideways up to seven blocks from a source, and drains when the source is removed. Rivers and lakes from generation are source blocks. Digging under a lake floods the hole. The player can move through water slower and sinks slowly (no drowning, no health). Rendering: water faces at the top show the level as a lower surface.
- Simulation ownership: water updates and light propagation are part of `simulation_tick`, bounded per tick so the tick never spikes, deterministic in order.
- Diagnostics: sky and block light at the targeted block, day factor, pending light and water updates.
- Tests (headless): sky light column and flood fill on hand made chunks (a roof leaves darkness under it, an opening lights the first cells), block light add and remove, light across a chunk border, water spreads and drains as specified on a small hand made world, water update determinism, and the mesher writing the expected vertex light values for a lit and an unlit face.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh`, `./build.sh release` pass.
- User: the M1 verify statement. Walk 500 blocks in any direction and dig to the deep stone at 60 fps in 1080p without hitches from chunk loading, finding at least three vein outcrops on the way, with a torch lit in the hole and a lake drained into a dug channel.
