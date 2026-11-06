# 0309: Surface materials you can dig: grass, sand, gravel, clay and snow

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313, after 0307 and 0308.

## Goal

The looks of 0307 become materials where the game wants them as resources (DESIGN.md, Pillars: terrain is a raw material, stone, sand, clay): a thin grass layer over topsoil, sand at the shores and in dry biomes, gravel on valley floors, clay in wet lowlands, snow on cold heights. Each has its item, its tile, its tool and its dig rate; a cut shows what lies below.

## Controls

None.

## Change

- New field materials in `data/materials.sjson` and the generation's strata by biome, slope and height; the items and the recipes that want them (glass from sand, bricks from clay) as the content asks.
- The look layers of 0307 that a material now carries leave the shader.
- Old worlds keep their strata: the new materials are off in a world record without them.
- Docs: `doc/content.md` (Field materials); the log.

## Verify

- The checks and the suite.
- Captures of a dug shore, a valley floor and a cut through grass; sent to the user.
