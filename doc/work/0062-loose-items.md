# 0062 Loose items on the ground

Status: todo
Milestone: M11

## Goal

A mined block whose items do not fit refuses to break. Loose items on the ground make the world feel handled and give drills and players a place to overflow.

## Deliverables

- An item entity: a small spinning model or icon, gravity, a stack merge rule, a despawn timer (data), saved.
- Mining with a full inventory drops the items; walking over them picks them up when they fit; a Drop action from the inventory places an item on the ground.
- Drills keep handing units to their drop cell entity; the design that drills never drop on the ground stays.
- Tests: drop, merge, pickup, despawn, save round trip.

## Verify

- Builds and tests pass.
- User: Fill the inventory, mine, see the items, pick them up.
