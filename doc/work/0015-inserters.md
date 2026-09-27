# 0015 Inserters

Status: todo
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
