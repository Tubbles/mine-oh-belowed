# 0011 Entities: chest and stone furnace

Status: todo
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
