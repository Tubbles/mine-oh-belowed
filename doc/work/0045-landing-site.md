# 0045 Landing site: starter outcrops within reach, flat ground, no gorge

Status: todo
Milestone: M10

## Goal

Couch test 1 (2026-09-27): the player flew around for minutes looking for the hematite outcrop, which lay far away and under trees, and the spawn search accepted a site next to a river gorge. The first minutes must not be a search.

## Deliverables

- Starter veins: one small vein of each spawn vein type (the types `data/veins.sjson` marks for the spawn, hematite, chalcopyrite and coal today) stamped at fixed distances of 24 to 40 blocks from the landing pad in different directions, deterministic from the seed, sized like a scattering. They are real veins: `layer_veins` includes them for the region their centre falls in (after the region's natural veins, with the next indices), so drills, assays, the map, the orbital survey and outcrops see them like any other vein. Natural veins stay as they are.
- Outcrops last: in `generate_chunk_blocks` (`src/generation_chunk.odin`) outcrops are applied after trees and boulders, and the column above every outcrop cell is cleared of tree and boulder blocks up to the feature height, so every outcrop cell is exposed to the sky. Sky light and open columns account for that.
- Flat landing site: a spawn candidate (`src/generation_spawn.odin`) is accepted only if, within 24 blocks of the centre, the surface height range is at most 3 and no column is water, and within 64 blocks the height range is at most 12 (no river gorge next to the pad). Trees, sand and water within 150 blocks stay required; the natural vein requirement is dropped since the starter veins cover it. The search step and ring count may grow so a site is still found for every seed.
- Tests: for several seeds the shipped generator finds a spawn; the three starter veins lie within 40 blocks with every outcrop cell open to the sky; the flatness holds; chunk generation stays deterministic (same seed, same blocks).

## Verify

- Builds and tests pass.
- User: on a new world the three outcrops are visible from the landing pad or a few steps from it, the ground around the pad is flat, no gorge or lake borders it.
