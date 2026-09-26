# 0012 Recipes, hand crafting, discovery and the graph browser

Status: todo
Milestone: M2

## Goal

Recipes as data with any number of inputs and outputs, hand crafting with a queue, the discovery channel, and the recipe browser as a graph with silhouettes, all without a search box.

## Deliverables

- `data/recipes.sjson` for phases 1 to 4 from `doc/content.md`: inputs and outputs (items now, fluids later but the format has them), time, the machine categories that can make it (hand, furnace, assembler), and its channel (start, discovery, research with the technology id).
- Discovery: a recipe becomes available the first time every input item has been produced or obtained; the set of produced items is simulation state. World setting "all recipes unlocked at start" honoured.
- Hand crafting: a queue on the player, one recipe at a time at speed 1, progress in ticks, ingredients taken when queued and returned on cancel, outputs into the inventory.
- Recipe browser (from the inventory screen and from the pause menu): category tabs on the bumpers, a tag filter list, "can craft now" toggle, first letter jump through the letter wheel on the left pad, and for the focused recipe a detail panel with inputs, outputs, byproducts, time, made in, and two lists "what makes this" and "what uses this" that navigate the graph. Undiscovered recipes appear as silhouettes: name and category shown, ingredients hidden.
- The stone furnace uses the furnace recipes from data (remove any hardcoded table from 0011).
- Tests: recipe loading, discovery rules, crafting queue arithmetic, the graph queries (makes and uses) on the shipped data, silhouettes hiding ingredients.

## Verify

- Builds and tests pass.
- User: starting from an empty inventory, craft a stone furnace and an iron pickaxe using only the controller and the browser, without a search box.
