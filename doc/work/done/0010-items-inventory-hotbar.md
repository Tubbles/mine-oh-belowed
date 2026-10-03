# 0010 Items, inventory and the radial hotbar

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/items.sjson` (60 items), `item.odin` (registry, drops, sort ranks, icon description), `inventory.odin` (slots and arithmetic), `inventory_interaction.odin` (slot interaction, held stack, distribute stub), `ui_inventory.odin` (screen, `machine_slot_region` hook), `hud.odin` (hotbar, radial), plus changes to player, loop, UI core, widgets, draw layer, diagnostics and strings.

### Deviations

- Drops: an item with `places_block` is what mining that block yields; `mined_from` lists further blocks (grass gives dirt, the four ore blocks give hematite, coal, chalcopyrite, cassiterite). Loading fails when a minable block yields nothing or two items. Ore items place nothing, so ore cannot be put back as vein blocks.
- Blocks that drop themselves and are not in the catalogue got category `block`, stack 50: leaves, tar, deep stone, spent rock, torch. Water and steam are not items (fluids do not stack). Pipe is one item (intermediate, stack 100) although the catalogue lists it under intermediates and machines. Plates and steel stack 50, stone brick, glass and charcoal 100. The magnetometer is a tool.
- Fuel is stored as integer kilojoules (`fuel_kilojoules`) so 0011 can burn it without floats.
- `game.sjson` `starting_blocks` became `starting_items` (item ids), validated against the item registry.
- X is both Open_Inventory and Context_Action on the gamepad, so in the inventory X splits when the focused stack holds two or more, and otherwise sorts the grid (the hotbar keeps its order). Holding a stack, X does nothing. `doc/input.md` puts Sort on X and split on L2; that binding is not added. Open_Inventory closes the screen only when it is not also the context action (so E closes, X does not).
- Sorting merges stacks and orders by category, then display name. Ranks are computed once at startup from the string table.
- A full inventory: the block still breaks and the item is lost (no world drops yet), and the toast shows. One toast per broken block.
- A held stack goes back when the inventory closes: origin slot, then anywhere. If nothing fits (possible after split then swap in a full inventory) the rest stays held on the player and shows again next time the inventory opens.
- The UI edits the player's inventory and selected slot directly between ticks, not through tick input. Fine for one local player; replays or co-op need these as commands.
- While the hotbar radial is open the world gets no Look, so the right stick does not turn the camera. The raylib pointer (mouse) does not drive the radial.
- New Glyph_Button `.Inventory` (X, E). New draw command `.Atlas_Tile`; `ui_end` takes the atlas.

### Not verified

Everything visual and the feel: icon tiles from the atlas (UV math untested on screen), lettered icon legibility, the HUD hotbar next to the glyph bar at 720p and at UI scale 1.5, the held stack following focus and pointer, the radial layout and highlight feel on the left pad, Tab with the right stick, toast spam when mining with a full inventory.

### Open questions

- Split and sort on one button is a compromise; bind split to L2 as `doc/input.md` proposes?
- Should mining refuse to break a block when its item does not fit, instead of losing it?
- Should the pointer (mouse) steer the Tab radial for keyboard players?
- `doc/input.md`, `doc/ui.md` and `doc/content.md` need the notes above (bindings, X rule, drop rules, stack size choices); this run could not touch them.
