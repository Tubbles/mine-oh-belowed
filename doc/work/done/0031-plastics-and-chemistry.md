# 0031 Plastics and chemistry: both routes

Status: implemented
Milestone: M7

## Goal

Plastic on the fossil route and on the renewable route from DESIGN.md, with sulfur and bitumen as byproducts that have uses, so the phase 6 puzzle has its trade off.

## Deliverables

- Chemical plant (3 by 3 by 3, electric 210 kW, category `chemistry`, fixed recipe by inputs): plastic bar from 20 litres of petroleum gas plus 1 coal (2 plastic, 1 s), sulfur from 30 litres of petroleum gas plus 30 litres of water (2 sulfur, 1 s), bitumen from 40 litres of heavy oil (1 bitumen, 2 s, a byproduct flagged output of the refining recipe is an alternative; choose the chemical plant route and say why), asphalt block from 2 bitumen plus 4 gravel (a placeable paving block with hardness 3, made in the washer category like concrete, or in the chemical plant; say which).
- Renewable route: wood gasifier (2 by 2 by 3, fuel free, electric 90 kW, category `gasifier`): 4 logs to 60 litres of wood gas (a new gas) plus 1 charcoal; chemical plant recipe syngas plastic: 30 litres of wood gas plus 1 charcoal to 1 plastic (2 s), slower and land hungry as designed. Wood gas also burns in the combustion generator (0032).
- Technologies: `plastics` (100 packs, prerequisite oil processing) unlocks the chemical plant and the fossil plastic and sulfur recipes; `renewable_plastics` (75 packs, prerequisite plastics) unlocks the wood gasifier and the syngas recipe; `bitumen_paving` (50 packs, prerequisite plastics) unlocks bitumen and asphalt.
- Science pack 2 recipe (1 inserter, 1 belt as in Factorio's logistic pack, or plastic based; choose plastic based: 1 plastic bar, 1 copper wire, 1 iron gear, 6 s) and the `logistics_science` technology stops being a placeholder by unlocking it; later technologies may cost pack 2 (make the pack list per technology data driven as it already is).
- Statistics and the recipe browser pick up the new recipes automatically; check the browser's tags (add `oil`, `plastic`, `wood`).
- Tests: every new recipe through the shared machine code including fluid inputs and outputs, gasifier byproduct, technology gating, science pack 2 costs on a technology, the ordering test.

## Verify

- Builds and tests pass.
- User: plastic comes out of a chemical plant on both routes side by side, and the statistics screen shows which route is faster.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `chemistry_test.odin`; `assembler.odin` (fluid inputs taken at the start), `fluid.odin` (`fuel_kilojoules_per_litre`), `recipe.odin` (makers `chemistry` and `gasifier`), `render_entities.odin` (their colours), `power_network.odin` (`assembler_wants_power` lost its tick rate); data in `fluids.sjson`, `items.sjson`, `blocks.sjson`, `machines.sjson`, `recipes.sjson`, `technologies.sjson`, `strings/en.sjson`. Count and shape updates in the item, machine, recipe, lab, recipe browser, ore processing and oil tests.

### Carry overs from 0030

- A craft with fluid inputs starts only when every fluid input's full litres sit in the input ports, and takes them at the start with its items; until then the state is "Missing fluid" and the machine asks for no power. A started craft never waits for fluid again. The washer test became `test_washer_takes_water_at_the_start`; the 0030 determinism test now sees one heavy oil crack (40 L) instead of a second one stalled on 10 L. Fluid taken by a craft in progress is lost when the machine is picked up, like any fluid in a picked up machine.
- The tar pit pump pumps 600 L per minute (a litre every 6 ticks), so two feed one refinery.

### Model and deviations

- Chemical plant ports: gas in on -z with `phase = "gas"` rather than a petroleum gas filter, so wood gas can use it too; the second input on -x is unfiltered (water, heavy oil or wood gas). One input slot (coal, charcoal or nothing) and one output slot shared by plastic, sulfur and bitumen, so a slot holding sulfur blocks a plastic craft until emptied, as with the washer. The ambiguity rule accepts the four recipes without filter changes (plastic needs coal, syngas plastic needs charcoal, sulfur needs gas and water, bitumen needs heavy oil); `test_chemistry_data_loads` checks it for both fixed machines.
- Bitumen is a chemical plant recipe (40 L heavy oil to 1 bitumen, 2 s), not a refinery byproduct: the refinery already has three fluid outputs and a fourth output would need a fourth port and change the 0030 refining recipe.
- Asphalt is an assembler recipe (player chosen, 2 s), not washer or chemical plant: 2 bitumen and 4 gravel to 4 asphalt, a placeable block with hardness 3 appended at the end of `blocks.sjson`.
- Wood gasification: 4 logs to 60 L wood gas plus 1 charcoal flagged `byproduct = true` (wood gas is the product), so a lenient world voids charcoal that has no room and a strict gasifier stops. Wood gas is a new gas fluid with `fuel_kilojoules_per_litre = 100`, read by nothing yet (0032). The machine panel's output rate counts the first non byproduct item, so the gasifier (and the refinery) show 0 there.
- Science pack 2 (1 plastic bar, 1 copper wire, 1 iron gear, 6 s) is assembler only, per the brief. `logistics_science` unlocks it and keeps its cost (75 packs of 15 s, science pack 1). `fast_belts` costs science packs 1 and 2 (read "cost science pack 2" as adding pack 2 to pack 1, as in Factorio), which gives labs a second slot.
- `belt_2` was not added: it is not a data change. Belt placement turns shaped belts into the first flat belt machine (`find_belt_machine(.Flat)` in `belt_placement.odin`) and the belt renderer uses the first flat belt's speed for every belt, so a second flat belt would need code. `fast_belts` stays a placeholder.
- Tags: `plastic` and `gas` are new; `gas` also went on refining, light oil cracking and the flare stack. Plastic, sulfur, bitumen and asphalt are flagged `cannot_recycle` (chemical products, like concrete); science pack 2 recycles.

### Guessed numbers

Chemical plant recipe 5 steel, 5 iron gear, 5 circuit, 5 pipe; wood gasifier recipe 10 stone brick, 5 iron plate, 5 pipe, 2 circuit (both 2 s, hand and assembler). Both machines speed 1, 200 L port buffers. Technologies `plastics` 100, `renewable_plastics` 75 and `bitumen_paving` 50 packs, all 30 s per pack. Stack sizes plastic bar 100, sulfur and bitumen 50, asphalt 50. Colours: wood gas (168, 150, 112), asphalt block (44, 44, 46) top and (52, 52, 54) sides, chemical plant (110, 150, 110), wood gasifier (120, 100, 80).

### Not verified

Everything visual and the feel: machine colours, port squares, the chemical plant and gasifier panels, the asphalt texture. The user verify (plastic from both routes side by side, and statistics showing which is faster) is covered by the 1200 tick determinism test (both chemical plants make plastic), not played. The shipped data loads through the real loader (the binary fails only at opening a window).

### Open questions

- Sulfur has no use yet. Which later recipe consumes it (batteries, science pack 3)?
- Should `logistics_science` need `plastics` as a prerequisite? Today it can be researched before plastic exists, which unlocks a science pack 2 recipe nobody can feed.
- Should petroleum gas get a `fuel_kilojoules_per_litre` for the combustion generator (0032)? Only wood gas has one.
- `doc/fluids.md` (fluid inputs taken at the start, the pump rate, wood gas, chemical plant and gasifier), `doc/content.md` (phase 6 values, science pack 2, fast belts cost) and DESIGN.md ("cracking to plastic" should read "chemical plant", bitumen is a chemical plant product rather than a refinery byproduct) need updates; this run could not touch them.
