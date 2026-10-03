# 0128: A wider pickup range and where picked up items go

Status: implemented

## Goal

The user, 2026-09-30: "widen the pickup range to lets say a full block size, is that 1 meter? And only pickup of tools and machines automatically goes to the hotbar, the rest go to main inventory (dirt, saplings, unless there is a non-full stack on the hotbar, in which case that takes prio for all item types)". A block is one metre (`DESIGN.md`).

## Change

- Range: `pick_up_loose_items` (`loose_item.odin`) takes every loose item whose cell centre is within one block of the player's feet horizontally, at the feet's level or the level below (the vertical rule of `loose_item_under_player` stays), instead of the feet cell alone. A pure predicate replaces `loose_item_under_player` and is tested at the boundary.
- Routing (`inventory_add` for automatic insertions: pickups and mining drops; manual moves in the UI keep their slot): first every non full stack of the item in the hotbar, whatever the item; then, for an item of category Tool or Machine (`Item_Category`), empty hotbar slots, then the main grid (non full stacks, then empty slots); for every other item the main grid (non full stacks, then empty slots), then empty hotbar slots as the last resort so nothing spills while a slot is free. Assumption to state in the log: mining drops route like pickups, since a mined block reaching the hotbar while a picked up one does not would look arbitrary; if a caller of `inventory_add` is a manual move, it keeps the old order through a separate procedure.
- `doc/ui.md` or wherever the inventory rules are documented, and `doc/logistics.md` if it describes pickups. `doc/log/<date>.md`: the decisions.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a loose item one block away is picked up and one at 1.5 is not; dirt goes to the main grid with an empty hotbar; a tool goes to the hotbar; dirt joins a non full dirt stack on the hotbar first; dirt goes to an empty hotbar slot only when the main grid is full.
- The user, on the phone or the couch.

## Implemented

- Range: `loose_item_in_pickup_range` (`loose_item.odin`) replaces `loose_item_under_player`; the cell centre within a radius of `LOOSE_ITEM_PICKUP_RANGE` (1) of the position in the horizontal plane, the feet's layer or the one below. Tested at 1.0 (taken) and 1.5 (left), plus a standing pickup from the neighbouring cell.
- Routing: `inventory_add_picked_up` (`inventory.odin`), used by the loose item pickup, `mine_block` and `pick_up_entity`. `add_to_slots` is split into `fill_partial_stacks` and `fill_empty_slots` with unchanged behaviour. `inventory_add` is unchanged for every other caller.
- Deviation: `pick_up_entity` routes its returned stacks (contents and the machine item) the same way, since the user named the pickup of machines; the item listed only pickups and mining drops.
- Deviation, not in the item: a stack the player drops (`dropping_player` on `Loose_Item`, the index plus one, `NO_DROPPING_PLAYER` for no one) is not picked up by that player until a tick in which the player is out of its pickup range, which clears the field; other players take it at once. Reason: with the one block range the stack dropped into the next cell lies 0.5 to 1.5 blocks away and would come back on the next tick; the drop geometry stays what players know. A one second countdown came first and was replaced on review, since it returned the stack to a player standing still. A merge takes the dropper of the stack merged in when it has one, else keeps the existing one (`merged_dropping_player`, tested). `drop_player_stack` and `pick_up_loose_items` take the player's index; the screens pass `Screen_Context.player_index`. Tested: the player standing next to the drop for 200 ticks never takes it back, two blocks away and back takes it, another player takes a fresh drop at once; the save round trip carries a dropper.
- Review fix: `mine_entity`'s Inventory full check uses `inventory_fits_all_picked_up` (the routing on a copy of the slots) instead of `inventory_fits_all`; tested with the reviewer's probe (one empty hotbar slot, a partial machine stack in the full grid, a machine and an ore picked up).
- Existing tests updated to the new routing (mined and returned items in the main grid, dropped stacks carry their dropper); the player determinism test starts with one dirt on the hotbar so it can still pillar with mined blocks.
