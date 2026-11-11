# 0373: The netlist's charge for a poorer child

Status: todo (2026-11-11)

Found by 0355's review. In the solve's slow path (`src/netlist/solve.odin`, `add_clamped_response`, `region_levels`) the region that feeds a poorer one across a limiting edge is charged the edge's full capacity, while the poorer region at its whole per mille level takes less. The difference is withheld from the feeding region, and when its demand is small that is tens of per mille with its own generation idle: a box with one 13 kW machine and a 12 kW generator on a light cable that passes on to an overloaded box runs its machine at 92.5 percent where full power is reachable. The main agent had accepted the charge as "a few per mille" before the review measured it; that was wrong. Under the poles it cannot occur (every edge unlimited), so 0355 landed with it named.

## Goal

A region is never held under what its own supply and its cables can give it.

## Controls

None.

## Change

- Above a poorer child's level the child is charged what it takes at that level, not the edge's capacity (the review's proposal: `clamp(R_child(poor_level), low, high)`), with the repair pass and the feasibility argument checked again.
- The brute force reference charges the same, and its capacities include the corners the review used (0, 1, 999, 1000, 1001, 1999, 2000, 3000, 4500, unlimited).
- The definition test measures the feeding region's idle reachable supply, and its bound is derived or zero.
- Before 0368.

## Verify

- The checks and the suite, with the review's two hand cases as tests (the middle at 990 and at full power).
- The adapter's paired test unchanged: no behaviour change under the poles.
