# 0058 Biomes from climate

Status: todo
Milestone: M11

## Goal

Six biomes chosen by independent noise. A temperature and moisture map chooses biomes so transitions read as a landscape, and new biomes give the planet variety.

## Deliverables

- Temperature (latitude band plus noise) and moisture maps choose the biome per column; the existing six keep their names and gain climate ranges in `data/biomes.sjson`.
- New biomes in data: wetland, steppe, highland, cold barrens with snow blocks, badlands with exposed rock layers, coastal dunes; each with ground blocks, ground cover (grass tufts, flowers, dead wood as decoration blocks), tree species, boulder style and a vein type bias.
- The map screen colours by biome; the HUD compass names the biome under the player.
- Tests: climate to biome mapping, every biome reachable for the test seeds, spawn still found.

## Verify

- Builds and tests pass.
- User: Walk a transition; screenshots.
