# 0008 Lighting and flowing water

Status: implemented
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

## Notes

Implemented 2026-09-27. Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (120 tests), `./build.sh`, `./build.sh release`, `--version`. Without a display the game loads the new data, prints the spawn and stops at the "could not open a window" error as before.

### Layout

- `world_light.odin`: nibble packing, the incremental add and remove propagation (removal queue first, then additions), chunk border seeding, the bounded `propagate_light`. `world_light_sky.odin`: a chunk's initial sky light from its own blocks, run by the generation workers.
- `world_water.odin`: levels, desired level rule, the scheduled update FIFO. `simulation_world.odin`: `tick_world`, called by `simulation_tick` after the players.
- `world_mesh_border.odin`: the one cell shell around a chunk copied for mesh jobs. `world_mesh_light.odin`: per vertex light and ambient occlusion, the colour packing. `render_day.odin`: the day curve and sky colour.
- Every `world_set_block` appends to `World.block_changes`. The next tick turns each change into an incremental light update and, next to water, water updates for the cell and its six neighbours.

### Choices

- Water levels are eight block ids (`water` is the source, level 8, `flowing_water_7` to `flowing_water_1`), marked by a `water_level` field in `data/blocks.sjson`. A metadata byte would grow every chunk by 32 KiB and change the chunk format for one user; block ids keep the layout, the serialisation and the greedy merge key as they are, and water levels are saved for free. Validation requires one block per level or no water at all.
- Levels count remaining spread: 7 next to a source, 1 at the end, so a level is also the surface height in eighths. Water under any water is level 7 (falling). Water spreads sideways only from a source or from water resting on solid ground or a source, so it falls first.
- Opaque means solid: water and torches let light through, leaves block it.
- Worker sky light: a column is open above a chunk when its surface and every tree or boulder box over it lie below the chunk's top. Boxes overestimate, so worker values are never brighter than final and the main thread only has to add light across borders (no removals on arrival). On 100 generated chunks the border seeding needed 256 queue nodes in 25 ticks.
- Mesh jobs no longer copy six neighbour chunks. They copy the chunk plus a 34 cubed shell of blocks and light from all 26 neighbours (118 KiB instead of 576 KiB), because smooth lighting and occlusion read edge and corner neighbours.
- Greedy merging keys on block, top height and the four corner colours, and faces whose corners differ never merge, so a gradient is never stretched over a merged quad.
- Shader: `light_curve(l) = l / (4 - 3 l)` per channel, `min(sky * day_factor + block, 1) * mix(0.5, 1, occlusion)`, floored at 0.06. Day factor runs from 0.2 at midnight to 1 by day (smoothstep of the sun height), the world starts shortly after sunrise, sky and fog blend from a night blue to the old sky colour.

### Per tick bounds

- Light: 4096 queue nodes per tick (removals and additions together), border seeding of 4 arrived chunks per tick.
- Water: 256 updates per tick, each due 10 ticks after it was scheduled (about 6 blocks per second).
- Light and water share no budget. A slow tick in the settling test (release, 4 chunk seedings) took about 1.3 ms.

### Deviations

- `starting_blocks` in `data/game.sjson` gives every player 64 torches: there is no crafting, and the verify statement needs a torch in the hole. Validated against the block registry at startup.
- A waterfall spreads 6 blocks where it lands instead of 7, since the eight ids leave no separate falling state.
- No new source blocks form where two sources meet (Minecraft does that). Rivers and lakes are infinite anyway.
- Flowing water does not look for the nearest drop within a few blocks as Minecraft does; it spreads evenly.
- The raycast now stops at minable blocks as well as solid ones, so a torch can be targeted and mined. The third person camera pulls in in front of a torch too.
- Water shows a side face against lower water (the step between levels); water against water of the same or higher surface stays hidden.
- `world_set_block` now dirties all chunks around a border cell, edges and corners included, since occlusion reads them.
- An all air chunk that is not fully sky lit (a large cave chunk) now dirties its neighbours on arrival.
- Swimming: in water the jump turns into the swim speed (2.5 blocks per second up), sinking is capped at 1.5 blocks per second. There is no boost for climbing out onto a ledge one block above the water surface.

### Timings (this machine, headless tests)

- Release, one test thread: generation 0.72 ms per chunk (was 0.44), meshing 3.9 ms per chunk (was 1.9), over the same 100 chunks. The extra cost is the sky flood fill and the four corner samples per face.

### Not verified

Everything visual: the light curve and minimum brightness, smooth lighting and occlusion on screen, seams at chunk borders, the torch cube and its glow, day and night colours and fog, water surfaces and level steps. The feel of water (speeds, sinking, swimming up). Real timings of light propagation and remeshing while streaming on the couch machine, and whether the 1.3 ms seeding ticks show as hitches. The M1 verify walk.

### Open questions

- Water spreading into a chunk that is not loaded stops at the border and does not resume when the chunk loads. Same for light removal into unloaded chunks: a torch removed next to an unloaded chunk leaves no stale light only because unloaded chunks are regenerated.
- Saving: light is not stored, and only generation can compute a chunk's sky light (it knows the column heights). Loading saved chunks needs a relight path, for example a stored height map per chunk column.
- Quads are split along the diagonal of the first corner, so occlusion on non uniform faces can look anisotropic; flipping the diagonal by corner values is the usual fix if it shows.
- Water rendering is still opaque and the texcoords of a lowered face are not shortened.
- Leaves block light entirely, so forests are darker underneath than in Minecraft.
- `doc/architecture.md` (world storage, mesh jobs now copy a shell) and `DESIGN.md` do not yet describe these choices (outside this item's allowed files).
