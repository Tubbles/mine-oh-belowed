# 0282: The ground's look under the shovel

Status: todo (2026-10-05)

## Goal

The sculpted ground keeps looking made. Techtonica's world is blocks hidden by doodads and a blending at material boundaries, the moss next to an iron vein growing a little onto the iron, and the textures mesh so well the blocks are hard to see (user, 2026-10-05, from play). Ours is a smooth field with triplanar tiles: where two materials meet the seam is a line, and a dug face shows the top's tile. The item: a blend at material boundaries driven by a height or noise mask so the softer material laps over the harder one (moss over ore, soil over stone), a slope and a depth term so a cut face reads as a cut, and scattered doodads (pebbles, tufts, ore specks) on the surface by material, hashed, never tiling (`DESIGN.md`, No perceivable repetition).

## Controls

None.

## Change

- `data/shaders/field.fs` and the field mesh's material weights (the design decides whether a vertex carries two materials and a blend); `data/materials.sjson` gains the lap order and the doodad set per material.
- A doodad pass in the presentation, instanced per chunk and culled with it.
- Reference: the user sends Techtonica screenshots of a moss and ore boundary and of a fresh cut before the design starts.
- Docs: `doc/presentation.md` (The field), `doc/content.md` (Materials).

## Verify

- Screenshots of one boundary and one cut before and after, sent to the user.
- The frame cost measured on the couch, the doodad pass within the field's budget at the view distance.
- `shader_source_test.odin`, the suite.
