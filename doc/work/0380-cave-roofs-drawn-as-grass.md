# 0380: Cave roofs drawn as grass

Status: todo (2026-11-12)

Found by the main agent in 0327's landing captures (2026-11-12, 8 km, default seed, the cave mouth by the spring at latitude 79.007, longitude 151.054): seen from inside, the cave's roof is drawn in the grass's green over its whole underside, where the floor is stone grey. A row of single bright pixels also runs across the floor in the same capture (`tmp/shot_terrain_caves/state/mine-oh-belowed/screenshots/cave_mouth_in.png`).

## Goal

A cave's roof and walls read as rock or soil from inside, never as grass, and the floor shows no stray pixels.

## Controls

None.

## Change

- Find which of the two it is: the roof's samples hold topsoil whose look takes the grass colour whatever way the face points (the ground look of 0307 keys the grass on the material and the slope), or the caves carve under a topsoil layer the generation should not leave hanging.
- Faces that point down, and faces under a roof, take the soil's or the rock's colour. The surface's grass does not change.
- The pixel row: find whether it is a seam between two meshes or the cover's instances, and close it if it is this item's.
- Docs: `doc/presentation.md` (The field session, the ground look).

## Verify

- The checks and the suite, with a test of the look of a face pointing down under a roof.
- The same capture before and after, sent to the user.
