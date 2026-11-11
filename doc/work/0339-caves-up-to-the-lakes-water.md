# 0339: Caves up to the lakes' water

Status: todo (2026-11-11)

0327 keeps its caves and notches out of every lake's bound sphere plus 4 m (`cave_lake_fade`). The sphere is sized from 0312's refine window, not from the water: about 300 m round each pit (`bound_radius`, `find_planet_lakes`). With 0326's lakes over the whole planet (1.6 a square kilometre at 8 km) that leaves no cave under roughly half the land, as 0327's fix round reported for the 1500 m round the home. After 0327, on its tree.

## Goal

Caves and wall overhangs everywhere 0327's rules want them, up to a margin round a lake's water itself, and no cave that opens into a lake or drains one.

## Controls

None.

## Change

- The caves' fade near a lake reads the lake's water (its mask, its level and its floor) instead of its bound sphere, in integers, the same from every thread and in any order of asking.
- A lake's water never meets cave air: not at its shore, not under its floor, not through a notch in a wall beside it.
- Worlds: 0327's caves are new with it, so the rule lands with 0327 before a play build holds caves, or behind a recorded key if it cannot.
- The cost of the query per sample stays what 0327's fix round left (asked only for a sample that can be cave air).
- Docs: `doc/architecture.md` (World generation, the caves), `doc/content.md` if a key is added.

## Verify

- The checks and the suite, with 0327's lake test (`test_the_caves_leave_the_lakes`) holding cave air within a lake's old bound and no changed water.
- The share of the land within 1500 m of the 8 km home that can hold a cave, before and after.
- A capture of a cave mouth near a lake's shore, sent to the user.
