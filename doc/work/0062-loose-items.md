# 0062 Loose items on the ground

Status: todo
Milestone: M11

## Goal

A mined block whose items do not fit refuses to break, a belt that ends at a ledge holds its items at the edge, and picking up a chest whose contents do not fit does nothing. Couch requests (2026-09-27): items must be able to lie on the ground. Belts that stop at a ledge drop their items down, items dropped onto the ground spill out, and destroying a chest yields its contents.

## Deliverables

- An item entity: a stack lying at a cell (a small spinning model or the item icon), falling with gravity to the ground or water surface, merging with a stack of the same item within the cell, a despawn timer from data (`game.sjson`, generous), saved with the world through the codec.
- Spilling: a mined block whose drop does not fit spills the drop at the block; picking up an entity whose contents do not fit takes what fits and spills the rest around it (chests, furnaces, machines and their held items alike), so a pickup never refuses; the inventory's Drop action puts the held stack on the ground in front of the player; items spilled onto a belt land on it.
- Belt ends: a line whose end is a dead end over a drop (no block in front at the belt's height and air below) lets items fall off the end into the cell below, onto the ground or a belt there; a dead end against a wall or on level ground still holds items as today.
- Pickup: walking over loose items picks them up when they fit, hotbar first for items already there; a full inventory leaves them lying.
- Drills keep handing their unit to the entity in their drop cell and never spill: a refused unit (gravel into a fuel slot) stalls the drill on purpose, an early game mechanic the user keeps (2026-09-27); sorting is the answer.
- Tests: spill on a full inventory, pickup on walk over, merge, despawn, belt end over a ledge drops and a level dead end holds, chest pickup with a full inventory spills the rest, save round trip.

## Verify

- Builds and tests pass.
- User: fill the inventory and mine, see the items; run a belt off a ledge and watch the ore fall; pick up a full chest with a full inventory and see the rest on the ground.
