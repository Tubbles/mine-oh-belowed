# 0061 Blocks that are not cubes

Status: todo
Milestone: M11

## Goal

Torches, slabs, stairs, pipes and poles are full cubes. Shapes for what should be thin or partial, with their own collision and light.

## Deliverables

- A shape per block in data: cube, slab, stairs, post (torches, poles), pipe; meshes from the model pipeline (0055) or built in.
- Torches with a flame quad, flicker, and their light; slabs and stairs for factory floors placed with rotation; pipes and poles drawn thin with connections to neighbours.
- Collision and raycasting respect shapes; outcrops get an ore texture and spent rock a cracked look.
- Tests: shape collision boxes, connection resolution for pipes and poles.

## Verify

- Builds and tests pass.
- User: Screenshots of a floor with stairs and a pipe run.
