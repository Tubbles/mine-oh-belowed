# 0277: The crafting view, the inventory beside the schematics

Status: todo (2026-10-05)

## Goal

The inventory binding opens one view with the inventory on the left half and the schematics on the right half, Techtonica's way (user, 2026-10-05: with a chest or a machine open one shuffles items, with the own inventory open one crafts). The schematics are a grid of icons under category tabs with the detail panel for the focused one, in place of the Recipes tab's list. The machine and chest panels keep the transfer view and gain no schematics. The list with the letter wheel stays as the browser of the picker and station modes. On the 0276 layer.

## Controls

- D-pad or left stick: the focus across both halves, Left and Right crossing the seam.
- A: craft one. R1 with A: craft five. L1 with A: craft the most the inventory affords (the planner's N).
- X on the schematics half: clears the whole crafting queue; on the inventory half: sort or configure as now. Open (design): where Cancel last lives once L2 steps the windows (the queue's boxes on the HUD are not focus targets).
- Right stick: steps the category tabs. Open (design): the tabs from the data's categories (machines, logistics, power, blocks, intermediates and materials, tools) mapped by a key on the category, never by name in code, and whether the "Unlocked only" filter becomes the last tab or a toggle on the title row.
- Y: assigns the focused schematic or slot to the toolbar (0278).
- B: closes to the world.

## Change

- `ui_inventory.odin`: the schematics half with a grid widget, the recipe browser's detail panel and plans (`Recipe_Plans`) reused; the Recipes tab goes with the strip (0276), the Research tab becomes the research window of the carousel.
- The crafting queue's clear as a `Player_Command` (lockstep as the crafts are).
- Docs: `doc/ui.md` (Screens: the crafting view, the recipe browser's remaining modes), `doc/hud.md` (the glyph bar's hints).

## Verify

- Tests: the focus crosses the seam and wraps inside each half; the craft counts through the modifiers; the clear queue command; the categories come from the data.
- The UI audit at every size, the grid at 1080 and at the smallest size.
- The couch.
