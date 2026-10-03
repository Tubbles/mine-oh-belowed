# 0030 Oil, gases and the refinery

Status: implemented
Milestone: M7

## Goal

The fossil half of phase 6: crude oil from tar flats, a refinery that splits it into a gas and two liquid fractions, gas storage, the flare stack as the paid sink for gases, and fluid outputs on crafting machines so later chemistry has its foundation.

## Deliverables

- Fluids in data: crude oil (liquid), petroleum gas (gas), light oil (liquid), heavy oil (liquid), with colours and name keys.
- Tar flats biome gets tar pit blocks that act as a fluid source for crude oil: the tar pit pump (2 wide like the offshore pump, electric 60 kW) is valid on a tar pit block and outputs 200 litres per minute of crude oil while powered. Tar pits are infinite in the alpha (a finite reservoir like veins is a follow up).
- Crafting machines gain fluid outputs: recipes may list `fluid_outputs` {fluid, litres} delivered into output ports at craft completion, with the same strictness rule as item byproducts (a flagged fluid byproduct is voided under lenient). The refinery (5 by 5 by 3, electric 400 kW, category `refinery`, fixed recipe) takes 100 litres of crude oil per craft (5 s) and outputs 45 litres of petroleum gas, 30 litres of light oil and 25 litres of heavy oil into three separate output ports; a port that would mix fluids stays closed as today.
- Gas storage: the storage tank already holds any fluid; add a `gas_tank` variant only if the tank cannot hold gases for a reason you find (say so), otherwise none.
- Flare stack (1 by 1 by 3, electric 10 kW): consumes up to 60 litres per second of any gas from its input port and destroys it, counting the volume as voided per fluid in the statistics; it is the paid sink for gases (the power draw is the price) and refuses liquids.
- Cracking: a `cracking_unit` (3 by 3 by 3, electric 200 kW, category `cracking`, fixed recipe by input fluid) with heavy oil plus 30 litres of water to light oil (40 to 30) and light oil plus water to petroleum gas (30 to 20), so every fraction has a use towards gas.
- Technology `oil_processing` stops being a placeholder: it unlocks tar pit pump, refinery, flare stack and the refining recipe; a new `cracking` technology (science pack 1 for now, 75 packs, prerequisite oil processing) unlocks the cracking unit and its recipes. The chapter 5 main quest already marks oil processing researched; check that the chapter ordering test still holds and that labs can research cracking afterwards.
- Statistics: fluids produced and consumed per fluid in rates like items (a parallel set of rings keyed by fluid id) and voided fluids; the statistics screen shows fluids in the Production tab below items.
- Rendering: placeholder boxes with port squares; the flare stack with a brighter top while burning.
- Tests: refinery split arithmetic and port routing, mixing refusal on a wrong port, flare stack destroying gas and refusing liquid, cracking ratios, tar pit pump placement, fluid rate rings, technology gating, save round trip with the new fluids, determinism over 1200 ticks with a tar pit pump, refinery, cracking unit and flare stack.

## Verify

- Builds and tests pass.
- User: crude oil from a tar pit runs through a refinery into three tanks, heavy oil cracks to light, and a flare stack burns off the gas until a use exists.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `oil_test.odin`; `fluid.odin` (phase filters), `machine_fluid_ports.odin` (port `phase`, layouts of the new kinds, crafting machines with output ports), `machine.odin` (kinds `tar_pit_pump`, `flare_stack`, field `fluid_litres_per_minute`), `fluid_machine.odin` (tar pit pump, flare stack, `accumulate_litres`, fluid statistics per machine tick), `fluid_network.odin` (phase filter closes a port), `power_network.odin` (demand of the new kinds, steam counted where engines draw it), `recipe.odin` (`fluid_outputs`, makers `refinery` and `cracking`, recipes without items), `assembler.odin` (fluid outputs, choice by input fluids), `statistics.odin` (`Fluid_Statistics`), `production_statistics.odin`, `ui_statistics.odin`, `world_block.odin` (`fluid_source`), `generation_biome.odin` and `generation_terrain.odin` (pits), `technology.odin` and `lab.odin` (`quest_gate`), `loop.odin`, entity, placement, render, recipe browser and panel files; data in all eight data files plus comments in `quests/chapter_01.sjson` and `chapter_05.sjson`. Count updates in the item, machine, recipe, lab, ore processing and chapter 5 tests; the save round trip test gained an unpowered oil site and fluid ring checks.

### Model and deviations

- `oil_processing` is no longer a placeholder but the labs must still refuse it (DESIGN.md: a gated technology waits for its main quest and nothing else), so technologies gained `quest_gate = true`, refused with `Research_Refusal.Quest_Gate` ("Not licensed yet", like placeholders). The chapter 5 test now checks `quest_gate` instead of `placeholder`.
- Fluid outputs: the n-th fluid output goes into the n-th output port in port order; the loader refuses a recipe whose output port is missing or filtered to another fluid. The room check covers fluid outputs, skipping flagged byproducts in a lenient world; at completion what does not fit is voided and counted. No shipped fluid output is flagged byproduct: all three fractions and both cracking products count as products, so a strict refinery stops when its gas has nowhere to go (the flare's job).
- Recipes may have no item inputs or outputs (then a `name_key` is required). Fixed crafting machines may have no item slots when they have fluid ports. A fixed machine now picks the recipe whose items match and whose fluid inputs are all present in its input ports, else the first item match as before (so a washer with ore and no water still reads "Missing fluid"). The ambiguity check counts a recipe as a subset of another only when both its items and its fluid inputs are. Fluid inputs are drawn only from input ports, so a cracking unit never takes back its own output.
- Refinery face order (unrotated, bottom layer): crude oil in on -z, petroleum gas out on -x, light oil out on +z, heavy oil out on +x, each port filtered to its fluid. Cracking unit: oil in on -z (unfiltered, heavy or light oil picks the recipe), water in on -x, product out on +z (unfiltered).
- Tar pits: a block field `fluid_source = "crude_oil"` on the new `tar_pit` block (solid, not minable); the tar pit pump is valid when the block in front of its intake, at its height or one below, has the fluid of its port. The tar flats biome has `pit_block = "tar_pit"` and `pit_maximum_height = 1`: a column at most 1 above sea level whose four face neighbours are no lower gets a pit instead of its top block.
- Tar pit pump and flare stack are fluid machines (new kinds, same pool). Both work one tick per power credit step, so a brownout slows them. The pump accumulates 200 per tick against 3600 (one litre every 18 ticks, exact per minute, remainder saved on the entity). The flare port is an every face input with `phase = "gas"`; a liquid network closes it ("Mixing refused").
- Fluid statistics: produced, consumed and voided counters plus rings per fluid under `Statistics.fluids`, reusing the item ring code with the fluid id as index. Measured as port buffer changes across each machine's own step (pumps, boilers, crafting machines; pumps excluded since they only move fluid) and where steam engines draw steam. Flare stacks count their gas as consumed and voided. The Production tab lists fluids below the items in litres per minute (letters in the fluid colour as the icon); the detail shows produced, consumed and voided rates. The letter jump still covers items only.
- The storage tank holds gases (test `test_storage_tank_holds_gas`), so no gas tank was added.
- Fluid-only recipes show a lettered icon in their first output's colour in the browser; their detail shows no fluids yet (the browser lists items only).

### Guessed numbers

Recipes: tar pit pump 5 steel, 3 circuit, 5 pipe; refinery 15 steel, 10 iron gear, 10 circuit, 10 pipe; cracking unit 10 steel, 5 iron gear, 5 circuit, 10 pipe; flare stack 5 steel, 5 pipe, 2 circuit (all 2 s). Cracking crafts 2 s each. `cracking` 75 packs of 30 s. Port buffers 200 L everywhere. Refinery and cracking unit speed 1. Colours: crude oil (48, 38, 32), petroleum gas (196, 160, 206), light oil (222, 180, 70), heavy oil (130, 66, 30), tar pit block (18, 16, 16) top, refinery (150, 130, 90), cracking unit (130, 90, 110), tar pit pump (70, 64, 60), flare stack (120, 110, 100) with an orange top (255, 170, 60) while flaring. Pit height 1.

### Not verified

Everything visual and the feel: the new machine colours, the flare's burning top, port squares on the refinery and cracking unit, the refinery panel (no slot rows, four port rows) and the statistics fluid rows at 720p, 1080p and UI scale 1.5. Whether tar pits appear in generated tar flats often enough, and whether they sit where a 2 wide pump can reach them (the pit rule is tested on a synthetic grid only). The user verify (tar pit to refinery to three tanks, cracking, flare) is covered in parts by tests (the 1200 tick determinism test runs a powered tar pit pump, refinery, cracking unit and flare stack), not played. The shipped data loads through the real loader (the binary fails only at opening a window).

### Open questions

- Should petroleum gas (or any fraction) be flagged as a byproduct, so lenient worlds void it instead of stalling the refinery?
- A crafting machine starts a craft with 1 L of a fluid input present and then waits for the rest (existing 0026 behaviour); the determinism test shows a second crack drawing the last 10 L of heavy oil and stalling. Wanted, or should a craft start only with its full litres present?
- A tar pit pump yields 200 L per minute and a refinery takes 1200: six pumps per refinery. Intended ratio?
- `doc/fluids.md` (fluid outputs, phase filters, tar pit pump, flare stack, fluid statistics), `doc/content.md` (phase 6 values, no gas tank), `doc/ui.md` (fluid rows) and `doc/architecture.md` (fluid statistics) need updates; this run could not touch them. DESIGN.md's "cracking to plastic" is left for 0031.
