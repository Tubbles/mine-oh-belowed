# 0082 Ground cover per biome

Status: todo
Milestone: M11

## Goal

Moved out of 0058 and 0061: grass tufts, flowers and dead wood as decoration on the ground, per biome, so plains, forests, steppe and wetlands read as living ground rather than flat grass.

## Deliverables

- Cross shaped blocks (0061) in `data/blocks.sjson`: `grass_tuft`, `tall_grass`, `flower_red`, `flower_yellow`, `dead_bush`, `reeds`, each non solid, no collision, mined instantly, dropping nothing (the tuft and tall grass) or a `sapling` like item where it makes sense later; textures from the generator with transparency.
- `Biome_Definition` gains `ground_cover = [{block = "grass_tuft", chance = 0.2}, ...]`: generation places one cover block on a column's top block from a per column hash when the column is dry land, not in a vein footprint and the cell above the surface is air after trees and boulders, so cover never floats and never blocks an outcrop. Plains and forest get tufts and flowers, steppe dry tufts and dead bushes, wetland reeds and tufts, badlands and desert a rare dead bush, cold barrens nothing.
- Walking through cover is free (no collision), mining it is instant, and placing a block on a cover cell replaces it.
- Tests: cover only on dry land top blocks with air above, the chance per biome over a sample, no cover on outcrops, placement replaces cover, and determinism.

## Verify

- Builds and tests pass.
- User: Walk a plain and a wetland; screenshots.
