# 0314: The landform field's cost

Status: todo (2026-11-06)

Milestone: the world generation series, after 0306. 0306's design measured its relief at about three times the cost of an evaluation in the wild and a fresh view at 5 to 6.5 times the CPU of before (a start, a teleport, the tech demo), about a quarter of a core while walking. The design left out an estimated reject per node: the steepest crests (about 64 degrees) make the slack swamp the coarse nodes, and a missed fold leaves a hole.

## Goal

A fresh view and a walk generate at about the cost of before 0306 on the couch and the phone, with the same ground.

## Controls

None.

## Change

- Measure first, from 0306's `test_report_the_relief_cost` figures and the couch's and the phone's start and walk.
- Candidates: the low frequency terms (the warp and the region) read once per chunk or node on a lattice and interpolated smoothly enough that no crease shows, the relief evaluated once per sample column where the grid allows, a reject per node that is exact by construction.
- Old worlds and the new ones generate the same bytes, or the change is recorded as 0306's terms were.
- Docs: `doc/architecture.md` (World generation); the log.

## Verify

- The checks and the suite, with 0306's parity tests unchanged.
- The cost figures before and after; the start and a walk on the couch and the phone.
