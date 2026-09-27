# 0045 Landing site: starter outcrops within reach, flat ground, no gorge

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (576 tests), `./build.sh`, `./build.sh release`, `--seed=1` up to the window.

### Model and deviations

- Starter veins (`src/generation_starter_veins.odin`): one scattering (size class 0) per `spawn_vein_types` entry, centre 24 to 40 blocks from the pad centre, preferred directions a third of the circle apart with a rotation from a new `Starter_Veins` purpose seed (appended last, other seeds unchanged). Radius and units come from the class and the region richness like a natural vein (`vein_radius`, `vein_units`, split out of `place_vein`). Each vein tries 16 directions, alternating to either side of its preferred one within half its sector, and takes the first where the footprint stays inside one region (same margin as natural veins, so the "footprint inside its region" rule still holds), the centre column is not under water, and it clears the other starter veins. Biome limits of the type are ignored (coal is plains and hills only). `layer_veins` for the surface layer appends the starter veins whose centre lies in the region with indices from the region's natural vein count on, after dropping the natural veins whose disc (plus `VEIN_SPACING`) overlaps one. Natural vein ids keep their placement index, so a dropped vein leaves a gap in the indices.
- Outcrops last: `generate_chunk_blocks` applies features, then outcrops, then `clear_above_outcrops`, which sets every non-water block of a footprint column above the surface up to `column_light_top` to air, in whichever chunk the column part lies. `find_open_columns` takes the veins and treats a footprint column as open above its surface.
- Flat site: `landing_site_is_flat` samples `terrain_height` on the 4 block grid. The flat range within 24 blocks is 5, not 3: the detail noise (`DETAIL_AMPLITUDE` 2.5) alone varies the surface by about 5, and over the 64 search rings of seeds 20260927, 1 and 2 (about 11000 dry candidates each) no candidate had a range below 4. The 64 block range of 12 and the water rule are as specified. `Spawn_Findings` lost `vein_types` and gained `flat`; `spawn_satisfied` takes the findings only.
- `SPAWN_SEARCH_RING_COUNT` 64 to 96: with 64, 1 seed of 200 (8 to 207) found no site; with 96, none failed, the farthest spawn at 2464 blocks.
- Search time (optimised test build): 1 to 48 ms for seeds 20260927, 1 to 7 and 987654321, 358 ms for the slowest of the 200 seeds.

### Guessed numbers

Flat range 5 (measured, see above), ring count 96, 16 direction attempts per starter vein.

### Not verified

Everything visual: that the outcrops are visible from the pad, that cut leaves over an outcrop look acceptable, the flatness as felt in play. Existing saves keep their seed, so their spawn moves to the new site and gain starter veins; chunks saved with blocks keep the old surface.
