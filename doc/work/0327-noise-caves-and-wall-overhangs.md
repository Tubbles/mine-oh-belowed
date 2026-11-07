# 0327: Noise caves and overhangs along the walls

Status: todo (2026-11-07)

0324 carves its arches, grottos and mushroom rocks as shapes under 0323's sites and left out the rest of its scope: Minecraft's noise caves (cheese, spaghetti, noodle) and overhangs along the gorge walls and the mesas' tier edges. Each needs a three-dimensional noise at every sample of the shell near the surface, on a relief 0306 made three times as costly, and air under ground that the generated light of 0324 shades everywhere instead of in a few chunks. After 0314 (the generation's cost).

## Goal

Caves that open from the hillsides and run under the ground, and walls that overhang, generated deterministically, without a slower fill of the view.

## Controls

None.

## Change

- A three-dimensional density term bounded to a shell under the surface and to where it is wanted (hills, ranges, gorge walls, tier edges), integer and fixed point. None under the home's calm circle.
- The generated light shades all of its roofed air, on 0324's seed at arrival.
- The readers of 0324's table follow it.
- What a cave under a player's building does: a rule the design proposes (no caves under ground a player has edited, or none near the start, or accepted).
- Old worlds keep their ground through the record.
- The cost per sample and per view measured against 0314's.
- Docs: `doc/content.md` (Planets), `doc/architecture.md` (World generation).

## Verify

- The checks and the suite, with the bound, determinism and old world parity tests.
- Captures into a cave mouth and along an overhanging gorge wall, sent to the user.
