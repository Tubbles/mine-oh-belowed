# 0014 Belts: transport lines, ramps, lifts, drag placement

Status: todo
Milestone: M3

## Goal

Belts as described in `doc/logistics.md`: flat, ramp and lift shapes as entities, transport lines with fixed point item movement, side loading and curves, drag placement with automatic turns, the player carried by belts, and rendering with animated surfaces and instanced items.

## Deliverables

- Belt entity kind with shape and direction, in the entity pools and the cell map, non solid for collision, walkable, carrying the player at belt speed.
- Transport lines per `doc/logistics.md`: lane items as fixed point positions, spacing, speed from `data/machines.sjson`, line construction and rebuild on placement, removal or rotation, end of line compression, side loading, curves, ramps (length one), lifts (a column is a line).
- The item transfer interface from `doc/logistics.md` implemented for belts (insert at a lane position, extract the nearest item), chests, furnaces and the capsule, so 0015 only adds callers.
- Placement: rotation sets direction, drag placement while Place is held along the reticle path with automatic turns and ramps on one block steps, re orientation when placing into an existing run, pick up returns the belt and its items.
- Debug: a developer action (keyboard F7) drops one iron plate onto the targeted belt so lines can be watched before inserters exist.
- Rendering: belt meshes for the four shapes with a scrolling texture, items as instanced small cubes at line positions with the item's icon colour, lifts drawn vertically.
- Tests: line movement and spacing arithmetic, compression at a dead end, hand off between lines, side loading onto the near lane, a curve, a ramp, a lift column, line rebuild after removing a middle belt, drag placement path to belt runs with turns, and a determinism test moving items for 1200 ticks in two simulations.

## Verify

- Builds and tests pass.
- User: lay a belt loop with a ramp and a lift using the drag gesture, drop plates on it with F7, ride the belt, and watch items circulate without gaps opening or closing.
