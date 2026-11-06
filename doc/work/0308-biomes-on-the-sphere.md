# 0308: Biomes on the sphere

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313, after 0306 and 0307. The user (2026-11-06): "make sure there is variations and biomes".

## Goal

The home world has places with character and names: two biome families (DESIGN.md, The world: the home world is temperate with two biome families), for example meadow, broadleaf forest, birch woods, conifer highlands, dry scrub, wetland, alpine and shore. A biome is picked from the climate (0307) and the relief class (0306) by the nearest point in a table, as Minecraft's multi noise, so borders follow the terrain. Each biome names its ground colours, its tree species with weights and densities, its ground cover and its ambience.

## Controls

None.

## Change

- The biome as a pure function of the generation, read by the shader's colours, the trees (0310), the cover (0311), the biome banner and the map on the field.
- `data/biomes.sjson` rewritten for the field. The block world's biome file retires with the block world.
- Old worlds keep their trees and look: the biome terms are off in a world record without them.
- Docs: `doc/content.md` (Biomes); the log.

## Verify

- The checks and the suite.
- A biome map beside the relief map (0306's map mode) of 4 km round the home, and captures of each biome; sent to the user.
