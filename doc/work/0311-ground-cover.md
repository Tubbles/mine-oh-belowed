# 0311: Ground cover: tufts, flowers, ferns and stones

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313, after 0308.

## Goal

The ground near the eye is not bare: grass tufts, flowers, ferns, pebbles and boulders by biome and slope, placed by hash, never tiling (DESIGN.md, No perceivable repetition), fading out with distance, cleared by digging and by building.

## Controls

None.

## Change

- One instanced pass per field node, culled with it, the cover's kinds and densities per biome in data.
- 0282 holds the doodads by material at material boundaries (pebbles, ore specks). The design merges the two into one pass.
- Docs: `doc/presentation.md`, `doc/content.md`; the log.

## Verify

- The checks and the suite.
- Captures at eye height in three biomes; the frame cost on the couch; sent to the user.
