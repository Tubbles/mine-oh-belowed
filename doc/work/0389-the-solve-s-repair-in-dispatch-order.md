# 0389: The solve's repair in dispatch order

Status: todo (2026-11-13)

Found by 0383's review. When a generator is held back by its own cable, the solve's slow path moves the shortfall onto the other nodes with `repair_dispatch` and `spread_over_rooms` (`src/netlist/solve.odin`), in proportion to each node's room and without regard to the dispatch order. So a battery gives while a second generator in the same tree has spare offer, and having given it gets no charge room that tick: beside a 900 kW engine on a 300 kW cable a docked vessel's battery drains instead of charging. The rule is older than the batteries (two generators of different orders are misordered the same way) and 0373 keeps it. After 0373, in the same files.

## Goal

The repair raises the nodes' gifts in dispatch order: every generator of an earlier order is at its offer or at its cable's limit before a later one gives more, and a store gives only what no generator can.

## Controls

None.

## Change

- `repair_dispatch` and `spread_over_rooms`: the shortfall goes to the rooms of the lowest dispatch order first, in proportion within one order.
- `doc/fluids.md`, Batteries: the qualification 0383 wrote goes.

## Verify

- 0383's reviewer's case as a test: a junction with a generator behind a 10 J cable (offer 100), a second generator (offer 200), a store (offer 50, room 50) and a consumer of 120. The second generator gives 110, the store gives 0 and takes its charge.
- Two generators of different orders with one held back by its cable.
- The definition test and the hand cases of 0373 unchanged.
