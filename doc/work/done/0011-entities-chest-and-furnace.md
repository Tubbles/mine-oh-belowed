# 0011 Entities: chest and stone furnace

Status: implemented
Milestone: M2

## Goal

The entity foundation from `doc/architecture.md`: typed pools with generational handles, multi block placement on a flat footprint with a preview and rotation, occupancy in block cells, selection through the raycast, and the first two entities with panels: the wooden chest and the stone furnace with a fuel slot.

## Deliverables

- `data/machines.sjson` with footprint, name key, panel type, slots (input, output, fuel), speed and fuel power for the wooden chest, iron chest and stone furnace from `doc/content.md`.
- Entity pools per type in the simulation with generational handles; a cell to handle lookup so the raycast reports entities and placement checks are cell lookups; save format hooks (serialise per chunk) can wait for M5 but the data layout should not fight it.
- Placement: the selected hotbar item that is a machine shows a ghost of its footprint on the targeted surface, rotation with Y or R, valid only when every footprint cell is empty and every cell below is solid, placed with the place action. Pick up with a long press of mine returns the item and its contents.
- Selection assist: the raycast snaps to the entity occupying the hit cell; the outline covers the whole footprint.
- Machine panels: chest shows its slots; stone furnace shows fuel, input and output slots, a burn bar and a progress bar, and smelts the recipes marked for the furnace from 0012 (until 0012 lands, a hardcoded ore to plate table is acceptable and must be removed by 0012). Fuel value from `data/items.sjson`. Furnaces tick in the simulation at fixed cost per tick, deterministic.
- Tests: handle generation and reuse, footprint validity, rotation of footprints, furnace tick arithmetic (fuel burn, progress, output stacking, stall when the output is full).

## Verify

- Builds and tests pass.
- User: place a furnace against a slope with rotation, fill it from the inventory with the distribute gesture, watch plates appear, pick it up and get its contents back.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/machines.sjson`, `machine.odin` (registry), `entity.odin` (handles, pools, footprint rotation, cell map, entity tick), `furnace.odin` (furnace state, hardcoded smelting table, tick), `entity_placement.odin` (ghost, validity, place, pick up), `ui_machine.odin` (machine panel, distribute gesture wiring, HUD status text), `render_entities.odin`, plus changes to player, mining, raycast, collision, input bindings, UI core, inventory screen, HUD, loop, main, strings and `game.sjson`. Tests in `entity_test.odin`, `furnace_test.odin`, `machine_test.odin` and the existing test files.

### Deviations

- Direction of the reference: the machine names its placing `item`; items know nothing about machines and `machine_for_item` is derived at load. This keeps the load order one way (blocks, items, machines), like items referencing blocks. An item may place a block or a machine, never both, and at most one machine.
- The pools and the cell map live in `World.entities` (the simulation owns the world), not directly in `Simulation_State`, so `tick_player`, the raycast and collision reach them through the world they already get. `tick_player` and `simulation_tick` take a `Simulation_Content` (blocks, items, machines) instead of separate registries.
- The fuel buffer is in joules, not kilojoules: 90 kW at 60 ticks per second is 1.5 kJ per tick, which is not an integer in kJ. Item fuel stays in kJ in the item table and is converted when an item is burned.
- Speed is kept as a percentage and power in watts after loading; recipe ticks are `milliseconds * tick_rate * 100 / (1000 * speed_percent)`, at least one.
- The furnace keeps progress while stalled (no fuel, output full) and restarts it only when the input changes to another recipe or runs short.
- The distribute gesture defers the drop: with a stack held, A on an accepting machine slot starts the gesture, and the release either drops normally (one slot visited) or spreads the stack (several). Picking up from a machine slot still happens on the press. Only slots that accept the held item and hold it or nothing join. Player slots do not take part. The world gesture from `doc/input.md` (L2 sweep across machines) is not implemented.
- A starts the gesture only with a stack held; with the mouse the left button does the same (press on a slot, drag, release).
- X is sort only on every backend: the player grid, or the chest's slots when a chest slot is focused. Split moved to `Menu_Secondary` (L2 on both gamepad backends, Left Shift on the keyboard). Left Shift is also Sneak, which a screen blocks anyway.
- Interact: A (and L4 on SDL3) carry Jump and Interact. `resolve_interact` drops Jump from the tick while Interact is held and an entity is targeted, so A on a machine opens it instead of jumping; looking elsewhere A jumps. The right pad click (SDL3) and F (keyboard) interact too. F stays the context action in menus. Space never interacts.
- Footprint placement: the footprint extends away from the targeted face; on a top face it stands on it, on a side face its bottom is level with the adjacent cell, and across the face it is centred on the adjacent cell (rounded towards the minimum for even sizes). Support must be solid blocks, not entities, so picking one machine up never leaves another floating. Cells outside loaded chunks are never valid.
- Mining refusal: a finished dig whose item does not fit keeps its full progress while Mine is held, shows one toast, and finishes on the next tick once a slot is free. Releasing Mine still resets progress. The same refusal applies to picking up an entity whose contents and item do not fit.
- Starting items now include 2 stone furnaces, 2 wooden chests and 1 iron chest, since nothing can be crafted before 0012.
- The HUD shows the targeted entity's name (and the furnace state) under the crosshair, and an Interact hint in the glyph bar. Block names still come later.

### Not verified

Everything visual and the feel: the ghost boxes and their colours, the placeholder cubes and the burning top, the footprint outline and the pick up progress outline, the machine panel layout at 720p and 1080p and at UI scale 1.5 (the chest panel is about 1500 units wide), the furnace bars, the HUD status text position, the distribute gesture with the sticks, the right pad pointer and the mouse, A opening a machine without a jump on both gamepad backends, L2 split on raylib pads (LEFT_TRIGGER_2 as a button) and the SDL3 trigger threshold, the placement origin rule on slopes and side faces.

### Known gaps

- Entity cells are air in the chunk data: light passes through machines, and water can flow into their cells. Mining the block under a machine leaves it floating.
- Holding Mine after a pick up goes on to dig the block behind it.
- The smelting table is hardcoded in `furnace.odin` (`HARDCODED_SMELTING_TABLE`, `resolve_smelting_table`, `Machine_Registry.smelting`) and must be removed by 0012.
- Entities are drawn every frame without culling, fine for a handful.

### Open questions

- Should water be kept out of entity cells now (a one line check in `update_water_cell`), or wait for pipes and fluids?
- Is the placement rule on side faces (bottom level with the adjacent cell, centred across) what the user wants, or should a side face snap the footprint down to the ground?
- `doc/input.md` (Interact, L2 split, X sort only, Left Shift), `doc/ui.md` (the gesture on release, sort only on X) and `doc/content.md` (machine values now in `data/machines.sjson`) need updates; this run could not touch them.
