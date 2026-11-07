# 0311: Ground cover: tufts, flowers, ferns and stones

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313, after 0307 and 0310. Biomes (0308) are skipped for now (user, 2026-11-07), so the cover reads the climate (0307) and the slope directly.

## Goal

The ground near the eye is not bare: grass tufts, flowers, ferns, pebbles and boulders by climate and slope, placed by hash, never tiling (DESIGN.md, No perceivable repetition), fading out with distance, cleared by digging and by building.

## Controls

None.

## Change

- One instanced pass per field node, culled with it, the cover's kinds and densities over temperature, moisture and slope in data.
- 0282 holds the doodads by material at material boundaries (pebbles, ore specks). The design merges the two into one pass.
- Docs: `doc/presentation.md`, `doc/content.md`; the log.

## Verify

- The checks and the suite.
- Captures at eye height in three climates (wet and warm, dry, cold); the frame cost on the couch; sent to the user.
