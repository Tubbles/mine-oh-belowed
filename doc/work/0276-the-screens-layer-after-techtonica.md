# 0276: The screens layer after Techtonica

Status: todo (2026-10-05)

## Goal

One button layer for every screen, after Techtonica's (user, 2026-10-05, [inspiration.md](../inspiration.md), Techtonica's controls and screens): A is the primary act on the focused thing and the bumpers held are its modifiers, B always closes to the world, the triggers step between the windows, the right stick steps the window's tabs. The inventory tab strip and the bumper tabs go. 0277 to 0279 build on this layer.

## Controls

The screens layer, gamepad. The keyboard and the pointer keep their ways where nothing below replaces them.

- A: the primary act (pick up or drop a stack, craft one, queue a research, pick a row).
- R1 held with A: five (craft five; on a slot the quick move). L1 held with A: the most (craft as many as the inventory affords; on a slot the split). The bumpers alone do nothing, the tab step goes.
- B: closes every screen to the world from any window, no modifier. The tap off a panel stays.
- X: the context action as now (sort the active grid, configure); on a schematic it clears the crafting queue (0277).
- Y: assigns the focused slot or schematic to the toolbar (0278), held it opens the toolbar edit mode (0279); elsewhere the info panel as now. Open (design): a slot's tooltip already shows after 0.4 s, so whether any row still needs Y for its info.
- L2, R2: the previous and the next window of the carousel, wrapping: the crafting view (0277), the journal, research, the map, statistics (production, power, shipments). The split and the quick move leave the triggers for the modifiers above, R2 as Confirm goes. Q and E keep stepping on the keyboard.
- Right stick: steps the window's tabs (the schematics categories, the journal's chapters, the statistics' tabs); its click stays Menu_Drop. Lists scroll by the focus and the pointer drag as they do.
- D-pad, left stick: the focus, in grids too. View and Menu stay (the map is a window of the carousel as well).
- Touch (0134): the window's title row carries the carousel's arrows, the modifiers become a held A that expands to one, five, most. Open (design).

## Change

- `data/bindings.sjson`: `Tab_Previous` and `Tab_Next` become `Window_Previous` and `Window_Next` on the triggers, `Modifier_Five` (R1) and `Modifier_Most` (L1) replace `Menu_Quick_Move` and `Menu_Secondary`; every screen's handling of Confirm with a modifier held.
- The inventory tab strip (`inventory_tabs`) becomes the carousel's title row (the window's name between the arrows) on every window; the recipe browser's picker and station modes stay outside the carousel.
- The settings' Bindings tab, the glyph bar per window, the UI audit cases.
- Docs: `doc/input.md` (Gamepad, the menus column), `doc/ui.md` (Focus and navigation, Item slots, Screens), `doc/hud.md`.

## Verify

- Tests: A alone, R1 with A and L1 with A on a slot and on a schematic resolve to the acts above; the carousel's order and wrap; B from every window closes to the world; no control carries two meanings in one context.
- The UI audit at every size.
- The couch.
