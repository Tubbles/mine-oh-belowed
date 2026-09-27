# 0026 Ore processing: crusher, washer, alloy furnace, ore grades

Status: implemented
Milestone: M6

## Goal

The phase 5 processing chain from DESIGN.md: two ore grades from veins, the crusher and washer that turn low grade ore into smeltable ore plus spoils, the alloy furnace with two inputs that finally makes bronze and steel, and the first new ores and alloys (lead, zinc, nickel, brass) as data.

## Deliverables

- Ore grades: each ore item gets a low grade twin (`hematite_low_grade` and so on) in `data/items.sjson`; a finite vein outputs low grade with a share that rises from 10 percent at full reservoir to 60 percent when nearly empty (per `DESIGN.md`), infinite veins stay at 10 percent. Deterministic through the existing draw hash.
- Crusher (2 by 2 by 2, electric 60 kW, speed 100 percent): low grade ore to crushed ore plus gravel (recipes in data, two outputs). Washer (3 by 2 by 2, electric 50 kW, consumes water through a fluid port at 30 L per second while working): crushed ore to ore plus mud (a new item). Both are generic recipe machines: build them on the assembler's recipe machine code with a `made_in` category each, so the data decides what they make; the assembler code should become the shared "crafting machine" with the assembler, crusher, washer and alloy furnace as machine entries with fixed recipe categories.
- Alloy furnace (3 by 2 by 2, fuel burning 180 kW, two input slots, one output): bronze (3 copper plate, 1 tin plate to 4 bronze) and steel (5 iron plate, 1 coal to 1 steel) and brass (copper and zinc) move from the furnace category to the alloy furnace category; remove any furnace recipe with two inputs that the stone furnace could not make anyway.
- New ores and metals in data: galena (lead), sphalerite (zinc), pentlandite (nickel) as vein types with plausible mixes and biome preferences from `doc/content.md`'s phase 5 list, their ore items, plates and the brass alloy, and the electric machine recipes for crusher, washer and alloy furnace on the research channel under a new `ore_processing` technology (science pack 1, 50 packs) that also unlocks the low grade recipes.
- Mud and gravel are byproducts with no sink yet (0027 adds the recycler and the sinks); they stack and can be chested.
- Tests: grade share by reservoir level, crusher and washer recipes through the shared machine code including the water port consumption, alloy furnace two input crafting, new vein types loading and placing, technology gating.

## Verify

- Builds and tests pass.
- User: a low grade hematite line runs drill, crusher, washer with water, furnace, and bronze comes out of an alloy furnace fed by two inserters.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `assembler.odin` (now the shared crafting machine), `recipe.odin` (makers `crusher`, `washer`, `alloy_furnace`, `fluid_inputs`, furnace recipes must have one input and one output), `machine.odin` (kind `crafting_machine`, fields `recipe_maker`, `recipe_choice`), `machine_fluid_ports.odin`, `fluid_network.odin` (ports of crafting machines join networks), `drill.odin` and `world_vein.odin` (grades), `generation_vein_tables.odin` (`low_grade` per vein output), `item_transfer.odin`, `inventory_interaction.odin` (slot filter `Crafting_Input`), `entity.odin`, `power_network.odin`, `ui_crafting_machines.odin`, `ui_machine.odin`, `ui_recipes.odin`, `render_entities.odin`, `render_fluids.odin`, `main.odin`; data in `items.sjson`, `blocks.sjson`, `veins.sjson`, `recipes.sjson`, `machines.sjson`, `technologies.sjson`, `strings/en.sjson`. New tests in `ore_processing_test.odin`; adjusted counts and signatures in the assembler, drill, recipe, item, machine, generation, lab and chapter 4 quest tests.

### Model and deviations

- One entity kind: the `Assembler` struct, pool and entity kind keep their names (renaming churns saves and a dozen files), but the machine kind in the data is now `crafting_machine` for the assembler, crusher, washer and alloy furnace. A machine entry names its `recipe_maker` and `recipe_choice` (`chosen` or `fixed`), and has either `electric_power_kilowatts` or one fuel slot with `fuel_power_kilowatts`. Slots are laid out fuel, inputs, outputs.
- Fixed choice: the input and output slot counts are in the machine entry (crusher 1 and 2, washer 1 and 2, alloy furnace 2 and 1) rather than derived from the recipes; a cross check after loading (`validate_crafting_machine_recipes`, run in `main` and in `make_test_content`) refuses recipes that do not fit, fluid inputs without a matching input port, and ambiguous fixed categories. Ambiguous means one recipe's input items are a subset of another's (not only equal), since with only the subset loaded the machine would start the smaller recipe. The machine makes the recipe whose input items are exactly the loaded ones.
- Inserter routing into a fixed choice: an item goes into the slot already holding it, or an empty input slot while some recipe of the category takes it together with everything loaded. A fuel item goes into an input slot only while another ingredient it completes a recipe with is loaded (coal with iron plate), otherwise into the fuel slot, so fuel coal never blocks an alloy furnace making bronze. Insertion limit is twice the most one recipe of the category takes.
- Fluid inputs: `fluid_inputs = [{fluid, litres}]` on the recipe, drawn from the input port buffer a share per progress tick (cumulative, so a craft draws exactly its litres). A step needs at least one litre present, so a craft never starts dry; running dry stalls in state "Missing fluid" and keeps progress. The work item says 30 L per second, the brief 30 L per craft: the washer recipe is 1 s at speed 1, so both hold at full power (under brownout it stays 30 L per craft).
- Fixed choice machines do not check recipe unlocks, like the stone furnace; the machines themselves are research gated.
- Grades: the share is computed from `remaining + draws` as the vein's size at generation (every finite draw takes one unit), so the `Vein` record gained no field. A low grade unit still comes out of its ore's reservoir amount. The grade roll hashes the draw hash once more with its own salt. Coal, stone, sand and gravel stay single grade; hand mining an outcrop yields high grade.
- `validate_furnace_recipes` now refuses a furnace recipe with more than one input or output; bronze and steel moved to `alloy_furnace`.
- The chapter 4 quest test helper `item_reachable` treats items mined from blocks as reachable, since the washer's research recipes now also make ore.
- Rendering: crafting machines are coloured by category, the washer's port square is drawn like a fluid machine's and pipes connect to it.

### Guessed numbers

Crushing 2 s, washing 1 s, brass 4.8 s (2 copper plate, 1 zinc plate to 3 brass), lead, zinc and nickel plates 3.2 s from one ore in the stone furnace on the discovery channel. Crusher and washer speed 1, alloy furnace speed 1. Machine recipes: crusher 3 circuit, 10 iron gear, 10 iron plate; washer 3 circuit, 5 iron gear, 10 pipe; alloy furnace 2 stone furnace, 10 stone brick, 4 iron gear (no steel, which it makes). `ore_processing` 50 packs of 15 s. Veins: lead 70 galena, 10 sphalerite, 20 gravel, weight 8, hills and forest; zinc 70 sphalerite, 10 galena, 20 gravel, weight 8, hills and desert; nickel 60 pentlandite, 20 chalcopyrite, 20 sand, weight 6, desert and plains. Block colours galena (100, 110, 150), sphalerite (92, 70, 40), pentlandite (140, 160, 110). Washer water port at the middle of its negative z side, 200 L buffer.

### Not verified

Everything visual and the feel: machine colours, the washer's port square, the crafting machine panel (recipe line, fuel row, fluid rows) at 720p, 1080p and UI scale 1.5, the new ore blocks in generated terrain, and whether the new vein types crowd the old ones near spawn (the spawn tests still pass). The user verify (drill, crusher, washer with water, furnace, bronze from an alloy furnace fed by two inserters) is covered in parts by tests but not played. The shipped data was loaded through the real loader by starting the binary without a display.

### Open questions

- Steel is now made only in the alloy furnace, which `ore_processing` unlocks after `steel_processing`. Researching steel processing alone makes no steel, and everything needing steel (pump, storage tank, core sample drill, steel furnace item) waits for ore processing; bronze (discovery) waits for research too. Move the alloy furnace recipe to `steel_processing` or the start channel?
- DESIGN.md says crushing and washing raise the yield per ore; the briefed recipes (2 low grade to 1 crushed to 1 ore) halve it. Which is intended?
- The steel furnace item has no machine and now no reachable use before ore processing; drop it or make it a faster alloy furnace?
- No statistics for crafting machine stalls or fuel burned in the alloy furnace yet.
- `doc/content.md` (phase 5 values, bronze and steel in the alloy furnace, the new veins), `doc/fluids.md` (crafting machines as implemented, fluid inputs), `doc/logistics.md` (grades in the drill draw) and DESIGN.md (yield sentence) need updates; this run could not touch them.
