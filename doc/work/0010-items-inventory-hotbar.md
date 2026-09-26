# 0010 Items, inventory and the radial hotbar

Status: todo
Milestone: M2

## Goal

Items as data, a player inventory of 36 slots plus an 8 slot hotbar, the inventory screen, and the hotbar as a radial menu on the left trackpad. Replaces the per block counts from 0007.

## Deliverables

- `data/items.sjson`: every item from `doc/content.md` phases 1 to 4 with id, name key, stack size, and for block items the block they place. Blocks that drop themselves need no separate entry beyond a flag.
- Inventory struct: fixed slots of (item id, count), stacking rules, add with overflow report, remove, move and swap between slots, split. Pure procedures with tests.
- Mining puts the block's item into the inventory (hotbar first, then the grid); placing consumes from the selected hotbar slot; a full inventory drops nothing yet but shows a toast.
- Inventory screen (X or E): the grid and the hotbar as slot grids with the gamepad slot interaction from `doc/ui.md` (pick up, drop, swap, split, info, distribute placeholder), sort on the context action, item tooltips from strings.
- Radial hotbar on the left trackpad: touch shows the wheel around the screen centre, the finger angle highlights a slot, release selects it; d-pad left and right and the bumpers still cycle. On pads without a trackpad the right stick drives the wheel while a held button shows it (keyboard Tab for now).
- HUD hotbar per `doc/ui.md`.
- Tests: inventory arithmetic (stacking to the limit, overflow, swap, split, sort order), item data loading, radial slot to hotbar slot mapping.

## Verify

- Builds and tests pass.
- User: mine three block types, open the inventory, move and split stacks with the sticks and again with the pointer, close, select each type from the radial with the left pad and place it.
