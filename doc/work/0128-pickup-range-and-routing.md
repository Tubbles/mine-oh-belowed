# 0128: A wider pickup range and where picked up items go

Status: todo

## Goal

The user, 2026-09-30: "widen the pickup range to lets say a full block size, is that 1 meter? And only pickup of tools and machines automatically goes to the hotbar, the rest go to main inventory (dirt, saplings, unless there is a non-full stack on the hotbar, in which case that takes prio for all item types)". A block is one metre (`DESIGN.md`).

## Change

- Range: `pick_up_loose_items` (`loose_item.odin`) takes every loose item whose cell centre is within one block of the player's feet horizontally, at the feet's level or the level below (the vertical rule of `loose_item_under_player` stays), instead of the feet cell alone. A pure predicate replaces `loose_item_under_player` and is tested at the boundary.
- Routing (`inventory_add` for automatic insertions: pickups and mining drops; manual moves in the UI keep their slot): first every non full stack of the item in the hotbar, whatever the item; then, for an item of category Tool or Machine (`Item_Category`), empty hotbar slots, then the main grid (non full stacks, then empty slots); for every other item the main grid (non full stacks, then empty slots), then empty hotbar slots as the last resort so nothing spills while a slot is free. Assumption to state in the log: mining drops route like pickups, since a mined block reaching the hotbar while a picked up one does not would look arbitrary; if a caller of `inventory_add` is a manual move, it keeps the old order through a separate procedure.
- `doc/ui.md` or wherever the inventory rules are documented, and `doc/logistics.md` if it describes pickups. `doc/log/<date>.md`: the decisions.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a loose item one block away is picked up and one at 1.5 is not; dirt goes to the main grid with an empty hotbar; a tool goes to the hotbar; dirt joins a non full dirt stack on the hotbar first; dirt goes to an empty hotbar slot only when the main grid is full.
- The user, on the phone or the couch.
