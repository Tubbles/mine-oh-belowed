# 0030 Oil, gases and the refinery

Status: todo
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
