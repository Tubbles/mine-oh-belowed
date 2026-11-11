# 0349: The globe after the terrain, and tighter culling boxes

Status: todo (2026-11-11)

The far globe is drawn first, under all the terrain, so its covered pixels are shaded; and a terrain node is culled by its whole cube (256 m at level 3) widened by 4 cells, though its mesh's bounds are known at upload (`work/performance_research_0340.md`, 2.6).

## Goal

Less overdraw from the globe and fewer terrain nodes drawn, with the same picture.

## Controls

None.

## Change

- The globe drawn after the opaque terrain, so the depth test rejects what the terrain covers.
- A node culled by its mesh's own bounds.

## Verify

- The checks and the suite.
- 0342's table: the terrain pass on the GPU and the drawn node count in the spring and ridge views, before and after.
- Captures before and after, sent to the user.
