# 0323: Landmarks worth exploring

Status: todo (2026-11-07)

The user (2026-11-07, after 0306 and 0307 on the phone): "while the terrain elevation now looks much more natural, it doesn't excite natural exploration. It needs to be more interesting and whimsical. Minecraft is really good at this, with gorges, cliffs, and even arcs, and other exciting features." The planet is a height map: a sample's density is its depth below `surface_relief` (`planet_sample_at_relief`), so it holds valleys and ranges but no feature that makes a player walk over to look. The research is `work/world_generation_research.md`.

## Goal

Within a few minutes' walk of any point there is something to go and see: a gorge with sheer walls, a cliff band or escarpment, a mesa or a butte, a spire, a sinkhole. Each is visible from a distance, and none repeats so that it reads as stamped.

## Controls

None.

## Change

- Height map landforms, after Minecraft's carvers and its jagged and badlands surfaces, each a term of the relief with its own rarity, scale and data keys:
  - gorges and ravines: a ridged noise carved deep and narrow, with steep walls that take the rock look;
  - cliff bands and escarpments: large steps of several metres to tens of metres, unlike the half-metre ledges 0322 removes;
  - mesas, buttes and spires: flat-topped and needle forms rising from plains;
  - sinkholes.
- A placement rule that spreads them so the player meets one at a walking pace, with the home's calm start of 0306 kept.
- The relief bound, the springs' streams (0312's water), the trees and the ground's look follow the new terms. Old worlds keep their relief through the record.
- The design prototypes the terms in the relief map mode and the captures, as 0306 did, and measures the cost against 0314's work.
- Docs: `doc/content.md` (Planets), `doc/architecture.md` (World generation).

## Verify

- The checks and the suite, with bounds, determinism and old world parity tests.
- Relief maps and captures of each landform, sent to the user.
