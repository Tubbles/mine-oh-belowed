# 0169: The field mesher and the level of detail

Status: implemented (2026-10-03; seen through the preview's screenshot under a virtual display)

## Goal

The field drawn: naive surface nets over the samples on the chunk workers, normals from the gradient, a material blended per vertex into a triplanar shader, an octree of coarser samplings for distance with skirts at the seams, and a globe at the far end (0167, Meshing and level of detail).

## Change

- A `world_field_mesh` file: for a chunk, one vertex per cell that the surface crosses at the mean of its edge crossings, quads between neighbouring cells' vertices, normals from the density gradient, the material ids of the cell's samples carried per vertex for blending, the tint as a vertex colour, read from the planet's palette modulo its length, since a saved tint is not checked against the palette (0168's review). The mesher reads the neighbouring chunks' border samples as the greedy mesher's border copy does today.
- A triplanar shader in the presentation cluster: the material's generated texture projected along the three axes and blended by the normal, materials blended at boundaries by the vertex weights, the tint multiplied in, the field light of 0173 read as vertex light when it lands (flat sky light until then). Every integer literal carries the `u` suffix (`shader_source_test.odin`).
- Level of detail: an octree over chunks; a node farther than a distance in data is meshed from the field sampled at half, quarter or eighth resolution, and the finer chunk at a seam hangs a skirt down its edge; the far end is a sphere mesh at the planet's radius drawn with a solid palette colour until the explored map exists.
- Meshing on the existing worker pattern (`world_streaming.odin`), revisions as today, so an edited chunk remeshes on the next revision.
- `doc/presentation.md` (Chunk meshes) gains the field mesher and the shader; `doc/code_map.md` the files.

## Verify

- The build and check commands of 0168.
- Tests: a chunk whose field is a flat plane meshes to a plane with normals along the gradient; a chunk with no surface crossing meshes to nothing; a sphere of a few chunks meshes watertight at chunk borders (every border edge shared by two triangles); the half resolution mesh of a chunk group has about a quarter of the vertices (a surface's vertex count follows its area, not its volume; the item first said an eighth); the shader source passes `shader_source_test.odin`.
- A headless render test draws a small planet to an image and the main agent reads it (the surface smooth, no holes at chunk borders, the skirt invisible from above).
