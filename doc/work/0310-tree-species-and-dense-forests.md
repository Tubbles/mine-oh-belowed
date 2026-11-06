# 0310: Tree species and dense forests

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313, after 0308. The user (2026-11-06): "More dense forests, varied tree types".

## Goal

Forests you can get lost in: several species per biome (a broadleaf, a birch like tree, the pine, a dead snag, bushes), sizes from saplings to giants, forest interiors at 2 to 3 m spacing with clearings, groves thinning into the plains. Today a single pine stands in groves on a 4 m lattice, at most 256 drawn within 128 m.

## Controls

None.

## Change

- Placement from the biome's density and a noise in place of the grove circles (Horizon Zero Dawn's density maps, `work/world_generation_research.md`), the species by the biome's weights.
- One model per species from the sealed lab (CLAUDE.md, Model items), one species at a time, each its own lab item.
- The draw: instancing and a far form (an impostor or crossed quads) so a forest shows out to the fog within the Deck's budget, the cap and the distance from data; felling, the trunk's collision and the felled table follow the new keys.
- Old worlds keep their trees: the new placement is off in a world record without it.
- Docs: `doc/content.md` (Trees), `doc/presentation.md`; the log.

## Verify

- The checks and the suite.
- Captures of a forest interior, a forest edge and a forest from 120 m up; the frame cost on the couch with the forest in view; sent to the user.
