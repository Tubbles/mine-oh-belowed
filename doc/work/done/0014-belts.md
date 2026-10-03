# 0014 Belts: transport lines, ramps, lifts, drag placement

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/machines.sjson` (kind `belt`, machines `belt`, `belt_ramp`, `belt_lift` with `belt_shape` and `belt_speed_blocks_per_second`), `data/strings/en.sjson`, `belt.odin` (entity, graph, line rebuild, per cell item records), `belt_movement.odin` (per tick movement, hand off, side load, lane insert and extract), `belt_placement.odin` (single placement, drag, rotate, F7), `item_transfer.odin` (`entity_accepts`, `entity_insert`, `entity_extract`), `render_belts.odin`, plus changes to entity, machine, placement, player, collision, interaction, input, loop, HUD, machine panel and the target ghost. Tests in `belt_test.odin`, `belt_placement_test.odin`, `item_transfer_test.odin`, and the adjusted machine test and test world.

### Deviations

- Belt direction is the player's facing quarter turned by the placement rotation (rotation 0 points away from the player), not an absolute direction. A flat belt placed where another belt's items come out takes that belt's direction.
- The transfer interface takes two extra arguments: `lane` (belts only, the lane is the returned `slot`) and `maximum_count` on `entity_extract` (inserters move one item). A furnace takes a smeltable item into its input first and fuel into its fuel slot second, so a log goes to the input. Belt extract takes the item nearest the middle of the block from either lane, left first on a tie. Belt insert puts one item mid block and needs a spacing of room on both sides.
- Geometry where doc/logistics.md is silent: a ramp occupies the lower cell of its step. An up lift is entered from a flat belt at its bottom block's level and leaves at the top onto the cell forward and one up (like a ramp up). A down lift is entered from the level above its top block and leaves at the bottom onto the cell forward. Ramps and lifts only take items straight on (no side loading onto them); a belt facing into the middle of a lift column does not connect.
- Lifts have eight rotations: 0 to 3 place an up lift, 4 to 7 a down lift. A lift placed on a lift continues that column whatever the rotation. A single ramp item places a ramp down when a block stands behind it and none in front, otherwise a ramp up.
- Drag placement works with the flat belt item only; ramp and lift items place one at a time. Automatic ramps take a `belt_ramp` item from the inventory (the flat belt it replaces goes back); without one the belt stays flat and the run is broken at the step. Only belts placed by the current drag are turned or reshaped; a drag started on an existing belt continues from it without turning it. At most 16 steps per tick, along the current direction's axis first.
- Rotating a placed belt: Rotate with no machine item selected while targeting a belt turns it a quarter turn (a lift together with its column).
- Lines are maximal chains. All lines are rebuilt on every belt placement, removal or reshape (linear in the number of belts) from the belts plus `Belt_Cell_Item` records (belt, lane, offset in the block), which is also the save form. Where two belts continue straight into one belt, the first in pool order wins and the other is a dead end.
- Straight hand off between lines happens only where the belt speed changes and at the seam of a loop. A loop lane is processed from the item with the most room ahead, and a full loop (every gap exactly the spacing) moves as a whole; without this a full loop stalls.
- Side loaded items wait at the end of the feeding line (half a spacing before it) and land mid block on the near lane when there is a spacing of room.
- Picking up a belt returns its item and the items on its block to the inventory, all or nothing like machines. Those items then count as obtained (the holdings growth rule of 0013), like items taken from a chest. Items on belts are never counted as produced or obtained while on the belt.
- Player carrying: flat belts and ramps move the player by the belt speed as a swept offset before the player's own movement; lifts do not carry. The carry is not counted as distance walked. Belts are not solid, so a ramp is not a slope for the player: walking up a ramp needs a jump onto the block ahead.
- Interact on a belt does nothing (no panel), so A jumps there. F7 (`Debug_Drop_Item`) runs at frame level like F5 and names the `iron_plate` item in code.
- Rendering: items are one `DrawCube` each, not instanced. Five quad meshes (flat, ramp up, ramp down, lift up, lift down) share one procedural striped texture whose texture coordinates are rewritten once per frame for the scroll. Belts use raylib's default shader, so they are not darkened at night like the chunks. Curves use the flat mesh; their items follow a quadratic curve from the entry edge to the exit edge. Items are drawn at their tick positions without interpolation.

### Constants

Speed 1.875 blocks per second is 480 units per second, 8 units (1/32 block) per tick at 60 Hz; the per tick speed is an integer division of units per second by the tick rate. Spacing 64 units, dead end margin 32, insert and side load offset 128. Item cube 0.2 blocks, lane offset 0.25, surface 0.03 above the cell bottom, at most 8 items drawn per block.

### Not verified

Everything visual and the feel: belt meshes and the texture scroll direction and speed on all five shapes and rotations, the lift quad and item placement on it, item cubes on curves, the belt ghost and its arrow, riding a belt, the drag gesture with a gamepad and a mouse (reticle path to columns, turns, ramps on steps), rotation feel for lifts, F7 with both input backends. The user verify (loop with a ramp and a lift, circulating plates) is not run. The shipped data was loaded through the real loader by starting the binary without a display.

### Open questions

- Should belt direction be absolute (rotation only) instead of relative to the facing?
- Is rotation 4 to 7 the right gesture for down lifts?
- Should automatic ramps fall back to consuming belt items when no ramp item is at hand, or should the drag stop?
- Should ramps be walkable slopes for the player?
- `doc/logistics.md` (lift and ramp geometry, transfer interface arguments, furnace slot priority, loop behaviour), `doc/input.md` (F7, rotating a placed belt, lift rotations), `doc/content.md` (belt values now in `data/machines.sjson`) and `doc/architecture.md` (line rebuild of all lines) need updates; this run could not touch them.
