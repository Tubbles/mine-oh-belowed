# 0012 Recipes, hand crafting, discovery and the graph browser

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/recipes.sjson` (45 recipes), `data/technologies.sjson` (9 technologies), `recipe.odin` (registry, validation, furnace lookup, graph queries, name order), `technology.odin` (registry, two way link with the research recipes), `recipe_unlocks.odin` (obtained items, researched technologies, available recipes), `crafting.odin` (hand crafting queue), `recipe_browser.odin` (pure filtering, letter jump, silhouette detail), `ui_recipes.odin` (the screen), plus changes to furnace, machine, entity, inventory interaction, machine panel, inventory screen (tab), pause menu, HUD (queue), UI core and input (Open_Recipes, typed letter, `cut_left`), player (queue ticks in `tick_player`), loop, main (`--unlock-all`), data loading (`all_recipes_unlocked`), diagnostics and strings. Tests in `recipe_test.odin`, `crafting_test.odin`, `recipe_browser_test.odin` and the adjusted furnace, machine, player and interaction tests.

### Deviations

- Obtained items: an item counts as obtained once it has been in any player's inventory or on the cursor. The simulation scans inventories and cursors every tick (cheap) and recomputes availability only when that set grows. This covers mining, crafting and taking from a machine without hooks in each path, and starting items count as obtained.
- A fourth channel `quest` for the steam engine (main quest gate in `doc/content.md`). It stays locked until quests exist (0013); unlock all opens it.
- The furnace smelts recipes with `furnace` in `made_in` and exactly one input and one output (its slot layout); two such recipes may not share an input (load error). Bronze and steel are furnace recipes with two inputs, so no furnace makes them until a machine with more input slots exists. The furnace does not check whether a recipe is unlocked: every single input furnace recipe is a start recipe or is discovered by obtaining its only input.
- Recipe times not in `doc/content.md`: tools 1 s, lamp 2 s. Lamp, pump, storage tank and power switch take the 2 s machine time.
- Technologies `logistics_science` and `fast_belts` are listed with empty unlock lists (their recipes are phase 5). Technology cost is `packs` and `seconds` per pack; the pack item is not named yet.
- `game.sjson` starting items are down to the torches, since the machines added by 0011 can now be crafted.
- The tag filter shows the tags of the current category and a recipe must carry every selected tag (AND). Switching the category clears the tags.
- Letter jump lands on the first recipe starting with the letter, or the first with a later letter when none does. Keyboard letters jump except A, C, D, E, F, Q, R, S and W, which are menu bindings (WASD navigate, Q E tabs, R info, F context, C closes the browser). The wheel is on the left pad (SDL3), or Tab with the right stick like the hotbar radial; raylib gamepads have no wheel.
- Crafting input: Confirm on a list row queues one, the context action (X, F) queues five of the focused recipe, the secondary action (L2, Left Shift) cancels the newest entry. Cancel is refused with a toast when the ingredients no longer fit. No hold gesture or count widget.
- Open_Recipes is bound to C only. On the gamepad the browser opens from the inventory's second tab (bumpers) or the pause menu, which closes the pause menu so the factory keeps running. In the inventory, keyboard E stays close (it is also Tab_Next).
- Graph lists hide for silhouettes as well, since they would reveal the product. Silhouette rows are dimmed with a `?` icon.
- The UI queues and cancels crafts directly on the player between ticks, like the inventory edits of 0010.

### Not verified

Everything visual and the feel: the three column layout at 720p, 1080p and UI scale 1.5 (columns are fixed widths, the detail column gets the rest), the letter wheel size and legibility with 26 slots, focus movement between the columns and into the graph lists, the focus landing on the list when the browser opens or a category changes, scrolling, the HUD queue left of the hotbar and the waiting text, the inventory tab strip, pointer clicks on tabs and rows. The user verify (furnace and iron pickaxe from an empty inventory with the controller) is not run. The shipped data files were loaded through the real loader by starting the binary without a display (it stops at window creation).

### Open questions

- Should research gated furnace recipes be checked against unlocks once one exists?
- Keyboard letter jump loses nine letters to menu bindings. Move the menu bindings off letters in the browser, or accept?
- A gamepad button for Open_Recipes (doc/input.md has none)?
- Hold A or a count widget instead of X for five?
- `doc/input.md` (Open_Recipes, browser bindings), `doc/ui.md` (browser layout, letter jump rule), `doc/content.md` (quest channel, tool times, recipe values now in `data/recipes.sjson`) and DESIGN.md need updates; this run could not touch them.
