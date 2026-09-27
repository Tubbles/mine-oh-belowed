# 0027 Recycler and the byproduct rule

Status: implemented
Milestone: M6

## Goal

The byproduct rule from DESIGN.md: every byproduct has a use and a sink, and the sink costs something. The recycler as the universal sink, slag and mud and gravel given uses as building blocks, and the byproduct strictness world setting given its effect.

## Deliverables

- Slag as a byproduct of every smelting recipe in the stone and alloy furnaces (a second output, small count), with recipes slag to gravel (crusher) and gravel plus water to concrete blocks (a new placeable block item), mud to clay (drying in a furnace) and clay to bricks, so each byproduct has a use.
- Recycler (2 by 2 by 2, electric 100 kW): any item with a recipe back into 25 percent of its ingredients rounded down, at least nothing, at the recipe's time; a data flag marks items that cannot be recycled. It is the universal sink and the fix for overproduction.
- Byproduct strictness: strict (default) means byproducts must be handled, so a machine whose byproduct output is full stalls, as it already does; lenient means byproducts that do not fit are voided. Read the world setting where machines complete a craft.
- A flare stack placeholder is phase 6 (gases); not in this item.
- Concrete and brick as placeable blocks with placeholder textures and hardness; paving.
- Tests: slag output shares, recycler arithmetic including the rounding floor and the cannot recycle flag, strictness voiding versus stalling, the new block items placing and mining.

## Verify

- Builds and tests pass.
- User: a furnace line's slag goes to a crusher and a concrete line and paves the floor; the recycler eats an overproduced stack and gives some of it back.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `recycler.odin` and `byproduct_test.odin`; `assembler.odin` (a `Craft` value per machine and recipe, lenient output check, recycler branches in the category lookups), `furnace.odin` (byproduct slot 3), `recipe.odin` (`byproduct` output flag, `Recipe_Output_Set`, maker `recycler`, `recycle_recipes` table), `item.odin` (`cannot_recycle`), `statistics.odin` (crafting stalls, `voided` per item, furnace byproduct), `machine.odin`, `entity.odin`, `entity_placement.odin`, `item_transfer.odin`, `power_network.odin`, `ui_machine.odin`, `render_entities.odin`, `world_vein.odin`; data in all six data files and `strings/en.sjson`. Count and shape updates in the item, recipe, machine, lab, statistics and ore processing tests.

### Carry overs from 0026

- The alloy furnace recipe is on the `start` channel; bronze and brass stay discovery recipes in it, steel stays under `steel_processing`. `ore_processing` unlocks only the crusher, the washer and the twelve crushing and washing recipes.
- Crushing: 2 low grade to 2 crushed plus 1 gravel. Washing unchanged (1 crushed plus 30 L to 1 ore plus 1 mud), so the chain recovers every unit of ore.
- `steel_furnace` machine: kind furnace, speed 2, 90 kW fuel, same slots as the stone furnace (now fuel, input, output, byproduct).
- Crafting machines count `Crafting_Output_Full`, `Crafting_Missing_Input` (missing ingredients or missing fluid), `Crafting_No_Power` and `Crafting_No_Fuel` when they enter the state, and fuel items lit into `fuel_burned`, like the furnace.

### Model and deviations

- Slag: 1 slag per craft, slag stacking to 100, rather than a 25 percent chance. A fixed count needs no hash state, keeps the per minute ratios readable (one slag per plate), and fills the slot after 100 plates, 5.3 minutes for a stone furnace at speed 1 and 2.7 for a steel furnace, which the tests pin. The chance version would take about 21 minutes to fill 100.
- "Every smelting recipe" is read as every ore smelting recipe (iron, copper, tin, lead, zinc, nickel plates) plus every alloy (bronze, brass, steel). Stone brick, charcoal, glass, clay and brick are slag free.
- The furnace rule is now one input, one main output and at most one byproduct output (the second, flagged), and the furnace machine entry needs `output_slots = 2`. The alloy furnace entry has 2 output slots for the same reason.
- Byproduct flag: `byproduct = true` per output in `recipes.sjson`, set on slag, gravel from crushing and mud. Inputs may not carry it, and a recipe needs one output without it.
- Lenient mode: byproducts are left out of the room check before a craft starts, and at completion each product is added as far as its slot has room; the rest is voided. Main outputs still wait. Both machines take the setting as a parameter every tick (`world.settings.byproducts_lenient`), including the completion tick; electric demand uses it too.
- Produced versus voided: `produced` counts what reached a slot, `voided` (new, per item) what a lenient world dropped. Both are measured as slot growth across the machine tick, like the furnace's existing counters.
- Concrete: `concrete` recipe in the washer category (1 gravel plus 30 L water to 1 concrete, fixed choice; gravel is not a subset of any crushed ore input). Slag to gravel is `crush_slag` in the crusher. Mud to clay and clay to brick are stone furnace recipes. All four are discovery recipes; the fixed machines and the furnace ignore unlocks anyway. A washer switching between ore and gravel shares its positional output slots, so a concrete craft waits while the first output slot holds ore and the reverse.
- Recycler: a crafting machine entry with `recipe_maker = "recycler"`, fixed, 1 input and 4 output slots, 100 kW, speed 1. It goes through the shared crafting machine tick rather than the fixed recipe matcher: `machine_craft` turns the recipe into a `Craft`, and for the recycler that is the reversed recipe (takes the recipe's count of the item, gives 25 percent of each input rounded down) whose returns go into any output slot holding the item or an empty one. `Recipe_Registry.recycle_recipes` maps each item to the first recipe making it in data order, or none when the item is flagged. A craft takes the recipe's time at the recycler's speed. Picking a recycler up mid craft returns the item it took, not the ingredients. The loader refuses recipes made in the recycler and recyclable items whose returns need more stacks than the recycler has output slots.
- Fixed choice fuel routing: the rule that keeps coal out of the inputs now applies only to machines with a fuel slot, so the recycler takes planks and charcoal.
- Research: a new `recycling` technology (science pack 1, 50 packs of 15 s, after `ore_processing`) unlocks the recycler; the brief named no gate. `doc/content.md` lists the recycler under phase 5 without a technology.
- `cannot_recycle` is set on every raw item (including gravel, clay, mud, slag, hematite and the other ores), the crushed ores, stone brick, concrete and brick.
- Concrete and brick blocks are appended at the end of `blocks.sjson`, items with `places_block`; they mine back into themselves.

### Guessed numbers

Slag stack 100. Crush slag 1 s, concrete 1 s, clay 3.2 s, brick 3.2 s. Recycler recipe 5 circuit, 10 iron gear, 5 steel; recycler speed 1, 100 kW, 4 output slots; `recycling` 50 packs of 15 s. Block colours concrete (176, 174, 168), brick (168, 80, 60); recycler render colour (90, 120, 70).

### Not verified

Everything visual and the feel: the furnace panel's new byproduct slot under the output, the recycler panel (its recipe line shows the name of the recipe being reversed), the new block textures, the world setup tooltip text length. The user verify (slag through a crusher into concrete paving, the recycler eating an overproduced stack) is covered in parts by tests, not played. The shipped data loads through the real loader (the binary starts and fails only at opening a window).

### Open questions

- Slag from phase 2 on: with strict byproducts a hand fed stone furnace stops after 100 plates until the player empties the slag slot, well before the crusher exists (phase 5). Is that the intended phase 2 pressure, or should slag start with the ore processing phase (for example only from the alloy and steel furnaces, or a lenient default)?
- Should the recycler panel say "Recycling: <item>" instead of the reversed recipe's name?
- Should `produced` include voided byproducts (the rate a machine makes) rather than only what was kept?
- `doc/content.md` (slag, byproduct uses, recycler values, alloy furnace channel, crushing yield, steel furnace), DESIGN.md (World settings still says strictness has no effect until phase 5), `doc/logistics.md` (furnace byproduct slot in the transfer interface) and `doc/architecture.md` with `doc/quests.md` (voided counter, crafting stalls) need updates; this run could not touch them.
