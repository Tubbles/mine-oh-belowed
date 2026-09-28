# 0094 One tab strip over inventory, recipes and research; a shorter pause menu

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-28): R1 from the inventory opens Recipes, but R1 again switches the recipe categories instead of going on to Research, so the bumpers do not read as one tab strip. Recipes and Research can leave the pause menu since the inventory reaches them.

## Deliverables

- The inventory, the recipe browser and the technology screen become three tabs of one screen strip: L1 and R1 always step between them, from any of the three, wrapping; the strip stays visible on all three (`inventory_tabs` in `src/ui_inventory.odin`, `src/ui_recipes.odin`, `src/ui_technologies.odin`, the screen stack in `src/ui_core.odin`: opening the inventory pushes one screen whose tab is the state).
- Recipe categories: the category tabs in the recipe browser become a focusable row (up from the list reaches it, left and right change the category, Confirm not needed), and the bumpers no longer touch them. The technology screen's own tabs, if any, follow the same rule.
- The pause menu (`src/ui_screens.odin`) loses Recipes and Technologies; Journal, Power, Statistics, Settings, Developer and the rest stay. The strings for the removed buttons go.
- Initial focus (couch, 2026-09-28): opening the inventory screen or any machine panel puts the focus on the hotbar slot that is selected in the world, not the top left backpack slot; the focus fallback in `src/ui_core.odin` takes a preferred widget id the screen names on its first frame (`ui_prefer_focus`), and the inventory and machine screens name the selected hotbar slot's id. The pointer is unaffected.
- Item info always on (couch, 2026-09-28): the item info panel that the Info action opened on a focused or hovered stack shows by itself, in every slot view (the inventory, the machine panels, the recipe browser's lists), as a tooltip after `UI_TOOLTIP_DELAY` on the focused or hovered stack and gone when the focus moves; the Info action and its glyph hint leave the slot views (the binding stays for screens that use Info for something else; the subagent lists them). Never a way to disable it.
- Tests: the info tooltip appears on a focused stack after the delay and follows the focus; the initial focus on the selected hotbar slot for the inventory and a machine panel; bumper steps across the three tabs from each, the category row's focus and left and right, the audit for the three screens and the pause menu.
- Docs: `doc/ui.md`, `doc/input.md`, `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: R1 twice from the inventory lands on Research; in Recipes, up reaches the categories and left and right change them.

## Notes

Files a subagent may touch: `src/ui_inventory.odin`, `src/ui_recipes.odin`, `src/ui_technologies.odin`, `src/ui_core.odin`, `src/ui_screens.odin`, `src/ui_widgets.odin` (the tabs widget's focus mode), `src/recipe_browser.odin`, `src/recipe_browser_test.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.
