# 0390: The solve's fed regions replayed

Status: todo (2026-11-13)

Found by 0373's review. The solve's pool reruns every inner fed region's capped greedy in each walk above it, so its work is quartic in the depth of nested fed regions that each have a cheap feeder: a chain of 321 nodes nested that way costs 28 million node visits a tick, one of 641 costs 445 million. Ordinary netlists do not nest so (2,701 nodes with every chain edge saturated and generators behind thin cables: 1.3 million), but a long line of generator and consumer pairs joined by thin cables does, and the solve runs every tick on every machine of a session. After 0373, in the same file, before or with 0389.

## Goal

The solve's work on a netlist is bounded near its size times the levels it moves, also for nested fed regions.

## Controls

None.

## Change

- Each fed region's greedy steps are recorded once, uncapped, and replayed up to a cap by every walk above it (a capped run is the uncapped run's prefix, 0373's rule 6), in `src/netlist/solve.odin`.
- The levels and flows do not change: the reference, the definition test and the hand cases stay as they are.

## Verify

- `test_netlist_solve_cost`'s nested chain case (0373) in the night window, before and after.
- A count test, no timing: node visits on nested chains of 81, 161, 321 and 641 nodes grow no faster than the bound the design states.
- The brute force and definition tests unchanged.
