# 0015 Inserters

Status: implemented
Milestone: M3

## Goal

Burner inserters, the electric inserter as an idle placeholder, and filter inserters, moving items between belts, chests, furnaces, drills and the capsule through the transfer interface.

## Deliverables

- Inserter entity kind with direction, the cycle from `doc/logistics.md` with tick counts derived from `data/machines.sjson` rates, a fuel slot for the burner variant, a filter item for the filter variant, and the powered flag for the electric variant that stays false until M4.
- Pickup and drop rules per `doc/logistics.md`, including the far lane rule on belts and slot filters on machines.
- Panel: fuel slot, filter slot, state text (idle, no fuel, waiting for room, unpowered).
- Statistics: stall counts feed the existing hint counters.
- Tests: cycle timing against the rate, belt to chest, chest to belt on the far lane, belt to furnace input with filter rules, output slot never emptied by a wrong side inserter, filter inserter ignoring other items, burner stall on fuel out, determinism over 1200 ticks.

## Verify

- Builds and tests pass.
- User: drill, belt, furnace, inserter, chest runs unattended for ten minutes and the chest fills with plates (the M3 verify statement, together with 0016).

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/machines.sjson` (kind `inserter`, machines `burner_inserter`, `inserter`, `filter_inserter` with `items_per_minute`, `fuel_slots`, `fuel_power_kilowatts`, `electric_power_kilowatts`, `filter_slots`), `data/strings/en.sjson`, the hint counter comment in `data/quests/chapter_01.sjson`, `inserter.odin` (entity, cycle, pick and drop), `inserter_test.odin`, plus changes to machine, entity, placement, item transfer, belt movement (peek), furnace (shared `refuel_from_slot`), statistics, quest hint counters, renderer, placement ghost, machine panel and the test world.

### Deviations

- The transfer interface gained two read only procedures: `entity_offered_items` (the distinct items `entity_extract` would give, in its order) and `entity_takes_item_kind` (whether an entity ever takes an item, full or not). An inserter picks the first offered item its target takes, so it never picks something it can never drop (a plate for a furnace, anything but fuel for a burner inserter). Moving items still goes only through `entity_extract` and `entity_insert`. A full target does not stop the pick: the inserter carries the item over and waits with it (Factorio's behaviour).
- Inserters are a transfer target too: a burner inserter takes fuel into its fuel slot and gives nothing.
- Direction on placement is relative to the facing like belts: rotation 0 drops away from the player, so the player stands on the pickup side. There is no rotate of a placed inserter yet.
- Far lane: the lane on the belt's side away from the inserter. A belt running straight away from or towards the inserter has no far side; it takes items on its right lane (a choice, not in the docs).
- Checks at the pickup, in order: no filter (filter inserter), nothing pickable (idle), no fuel (only when there is something to pick, so an idle burner with an empty fuel slot shows idle, like the furnace).
- Stalls are new `Machine_Stall` members (`Inserter_Out_Of_Fuel`, `Inserter_Waiting_For_Room`), not the furnace ones, so the chapter 2 furnace hint does not fire on inserters. Hint counters `inserter_out_of_fuel`, `inserter_waiting_for_room`, `inserter_idle_ticks`. Fuel burned by inserters adds to `fuel_burned`.
- Held items and the fuel slot come back on pick up; the filter is only an id and is lost.
- Filter slot: A with a stack held copies its item id (the stack stays held), the context action clears it; while the filter slot has focus the context action does not also sort the inventory. The panel uses a `Machine_Slot_Result` wrapping `Slot_Grid_Result` for this.

### Constants

Cycle ticks `tick rate * 60 / items_per_minute`: 100 at 36 per minute, 72 at 50. Swing to drop `cycle / 2`, back the rest. Pick and drop are instant on the arrival tick, so with an always ready source and sink the pick ticks are 1, 101, 201 and a minute moves exactly 36. Burner fuel 94 kW is 1566 J per tick (integer division like the furnace), burned only on swing ticks. Render: post 0.3 by 0.4 by 0.3, pivot 0.45 up, arm 0.7 long, turning through the right hand side, held item cube 0.2.

### Not verified

Everything visual and the feel: the post and arm, the swing direction, the held cube, arm colours, the ghost arrow, the panel layout (fuel slot and burn bar, filter slot, cycle bar, state text) at the usual resolutions and UI scale, the filter slot with gamepad focus and the mouse, the HUD status text. The user verify (drill, belt, furnace, inserter, chest for ten minutes) needs 0016.

### Open questions

- Should the right lane stay the rule for belts running straight towards or away from an inserter?
- Should a placed inserter rotate with Rotate like belts?
- Burner inserters in Factorio refuel themselves from fuel they carry. Wanted here, for the coal loop of chapter 3?
- `doc/logistics.md` (the two peek procedures in Item transfer, the far lane choice for in line belts, the check order at the pickup) and `doc/content.md` (inserter values now in `data/machines.sjson`) need updates; this run could not touch them.
