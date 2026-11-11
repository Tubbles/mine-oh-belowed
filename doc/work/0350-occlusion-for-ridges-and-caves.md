# 0350: Occlusion for ridges and caves

Status: todo (2026-11-11)

The frustum keeps far terrain nodes and tree tiles that a ridge hides, and after 0327 the finest nodes mesh cave walls under the ground the eye stands on (`work/performance_research_0340.md`, 2.4). After 0327 and 0339.

## Goal

What a ridge or the ground hides is not drawn, and nothing pops into view at a corner.

## Controls

None.

## Change

- Ridges: last frame's visibility for nodes and far tree tiles (occlusion queries on their boxes, or a depth pyramid), what was visible drawn first.
- Caves: per chunk, which faces connect through open space, computed on the workers with the mesh, and a walk from the eye's chunk through the connected faces, as Minecraft's cave culling does.
- The phone's GLES path and the Windows build keep working where a query is missing.

## Verify

- The checks and the suite, with a test of the connectivity on hand-made chunks.
- 0342's table: the GPU's time and the drawn counts in the ridge, forest and cave views, before and after.
- A capture series round a corner and out of a cave mouth with no pop, sent to the user.
