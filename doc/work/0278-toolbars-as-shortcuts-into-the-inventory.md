# 0278: Toolbars as shortcuts into the inventory

Status: todo (2026-10-05)

## Goal

The hotbar stops being a row of the inventory and becomes toolbars of shortcuts into it, Techtonica's way (user, 2026-10-05): a toolbar slot names an item kind and shows the inventory's count of it, selecting it holds that item, placing draws from the inventory by kind. Two toolbars at the start (a data number, more later), stacked on the HUD, the lower one active; the d-pad swaps the rows as a carousel and steps along the active one (0280). Y on a slot or a schematic assigns it to the selected toolbar slot (0276). The left trackpad's radial shows the active toolbar.

## Controls

None beyond 0276 (Y assigns) and 0280 (the d-pad). The toolbar edit mode is 0279.

## Change

- The simulation: the player's hotbar grid becomes `toolbars` of item kinds in the save, with a remap for old saves (the hotbar's stacks move into the main grid, their kinds become the first toolbar, one log line). Open (design): the main grid grows by the hotbar's eight slots or stays at 36 with a spill to the ground.
- Place, Use_Item, the tools and Drop_Stack take the first stack of the selected kind; a kind the inventory lacks greys the slot and does nothing. The quick move between the backpack and the hotbar goes.
- The HUD's two rows, the radial, the touch overlay's slot taps (0119), the glyph bar's held hints, the UI audit's HUD cases.
- Data: the toolbar count in `game.sjson` (1 to 4).
- Docs: `DESIGN.md` (The player, the inventory line), `doc/ui.md` (Item slots, Active grid), `doc/hud.md`, `doc/architecture.md` (the save), `doc/content.md` (the key), `doc/touch_overlay.md`.

## Verify

- Tests: assign, select, place consumes by kind, an empty kind places nothing, the carousel's order, the remap of an old save (the dev kits).
- The UI audit's HUD cases at every size.
- The couch.
