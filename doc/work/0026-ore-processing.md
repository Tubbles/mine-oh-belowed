# 0026 Ore processing: crusher, washer, alloy furnace, ore grades

Status: todo
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
