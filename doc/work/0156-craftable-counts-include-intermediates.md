# 0156: The recipe browser counts crafts the planner can make

Status: todo

## Goal

User report (2026-10-01): "when crafting recipes, the can craft X doesn't take into consideration that we now automatically craft needed intermediates, and the missing items are still marked red even though I have materials for the intermediates." Since 0138 the hand crafting queue crafts missing intermediates on demand (`plan_crafts`, `crafting.odin`), but the recipe browser still judges a recipe by the inventory alone: `recipe_craftable_now` (`crafting.odin`) and `crafts_covered` (`ui_recipe_browser.odin`) count direct inputs, `craftable_recipes` feeds the "Can craft" filter and the row colour from them, and `ingredient_color` (`ui_recipes.odin`) paints an input red whenever have is below need, even when the planner would make it from what the player holds.

## Change

- One pure procedure beside the planner answers the browser's question: how many crafts of a recipe the planner can make now, intermediates included, from the inventory and the available recipes, and for each direct input whether it is held, craftable from held materials, or missing. It reuses `make_craft_plan` and `plan_recipe` (or their inner steps) with a count search (plan one craft, then more until the plan refuses; or compute from the plan's virtual counts), bounded by the queue's depth and the plan limits (`Plan_Too_Deep`), so the browser and the queue never disagree about what can be crafted.
- `craftable_recipes` and `crafts_covered` use it: the "Can craft" filter and the row colour follow the planner; the "can craft X" count shows the planner's count.
- `draw_ingredient_rows` shows three states: held (the accent colour as today), craftable from held materials (a third colour or the dim text colour, with the line saying how many the planner would make, for example "0 of 2, craftable"), missing (red as today). The theme's colour set may gain one entry if no existing one fits; the UI audit cases that show the recipe detail cover the three states.
- `doc/ui.md` (the recipe browser) states the rule: craftable means the queue would make it, intermediates included; `doc/content.md` or `doc/quests.md` only if they describe the count.

## Verify

- Tests: a recipe whose input is an intermediate the player can craft from held raw materials counts as craftable with the planner's count, its input row is marked craftable not missing; a recipe missing a raw material stays uncraftable with the input red; a recipe whose intermediates exceed the plan depth is refused as the queue refuses it; the UI audit draws the detail panel in all three states.
- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
