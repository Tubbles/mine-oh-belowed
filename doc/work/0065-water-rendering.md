# 0065 Water that looks like water

Status: todo
Milestone: M11

## Goal

Water is an opaque block colour. Transparency, waves, shore foam, an underwater tint and visible flow.

## Deliverables

- A water pass after the solid chunks: transparent surface with a small wave animation in the shader, foam at shores, underwater fog and tint, flow direction from the flowing water levels shown as texture motion.
- Tests: water faces sorted into the transparent pass, level to flow direction mapping.

## Verify

- Builds and tests pass.
- User: Screenshots at a lake and a river.

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous. Lands after 0063 weather; read 0064's and 0063's Implemented paragraphs for the fog and sky names.

- Water pass: the mesher (`src/world_mesh.odin`) routes every face of a water block (`block_water_level > 0`) into `Chunk_Mesh_Data.water_parts`, separate `Mesh_Part`s with the same layout plus a tangent per vertex (`[4]f32`: flow x, flow z, shore, unused), uploaded as `Chunk_Render.water_meshes` (`src/render_chunks.odin`) and drawn by `draw_water_chunks` after the opaque chunks, the entities, the belts and the loose items and before the weather particles and the player overlay (`draw_session_world`, `src/loop.odin`), with alpha blending, depth test on and depth writes off, backface culling off so a surface seen from below shows. The opaque pass no longer draws water. A second material with its own shader pair `data/shaders/water.vs` and `water.fs` (hot reloaded like the chunk shaders: `src/data_watch.odin` names them, `src/hot_reload.odin` reloads both pairs), taking the same atlas, camera position, fog and day uniforms plus `time` and the wave and flow constants.
- Look, in the fragment shader: the texel at alpha 0.6; a ripple from two scrolling sine waves over the world xz and the time that lightens the surface by up to 15 percent (no geometry moves); the texture coordinates offset by the flow vector times the time, so flowing water visibly runs and a source (level 8) only ripples; a foam band where the shore value is high: lighter, with its own faster scroll; the fog as the chunk shader applies it.
- Flow and shore from the mesher (pure, tested): for a water cell the flow vector is the sum over the four horizontal neighbours of the level difference (neighbour minus cell, water neighbours only) times the direction away from the higher one, normalised, zero for a source or a level cell; every vertex of the cell's faces carries it. The shore value of a vertex is 1 when any of the four cells around it at the surface height is solid (the corner cells `vertex_light` already visits), else 0.
- Underwater, in a new `src/render_water.odin` (pure parts tested): the camera is under water when the eye's cell holds water (`block_water_level` of `world_get_block` at `camera_world_coordinate` of the eye); then the fog uniforms take `UNDERWATER_FOG_START` 2 and `UNDERWATER_FOG_END` 14 blocks and the fog colour a blue green, on both materials, overriding the weather's fog; after the 3D pass a full screen rectangle in the same blue green at alpha 0.35 tints the view. The sky pass still draws.
- Tests (`src/world_mesh_test.odin`, `src/render_water_test.odin`): water faces land in the water parts and none in the opaque parts, and a cube face against water stays opaque; the flow vector for a cell between a higher and a lower neighbour points downhill and is zero for a source; the shore value at a vertex next to stone and zero in open water; the eye under and above water; the fog values underwater; the shader pair names are shader files for the watcher.
- Docs: `doc/architecture.md` (the meshing and rendering lines: the water pass), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: `src/world_mesh.odin`, `src/world_mesh_light.odin`, `src/world_mesh_test.odin`, `src/render_chunks.odin`, new `src/render_water.odin` and `src/render_water_test.odin`, new `data/shaders/water.vs` and `data/shaders/water.fs`, `src/data_watch.odin`, `src/data_watch_test.odin`, `src/hot_reload.odin`, `src/loop.odin` (the draw order, the underwater uniforms and overlay), the docs above, this file.
