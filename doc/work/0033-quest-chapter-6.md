# 0033 Quest chapter 6: fluids

Status: implemented
Milestone: M7

## Goal

Chapter 6 from `doc/quests.md`: a water network with a pump uphill, the tar pit pump, refinery, gases into tanks, plastic on both routes, waste gas into a generator, and the main quest gate: a deep mining permit that unlocks bore drills and the seismic survey (placeholder technologies until M8).

## Deliverables

- `data/quests/chapter_06.sjson` with those quests using existing objective types, hints for a closed mixing port ("Two fluids, one pipe. The pipe declined.") on a new counter of mixing refusals and for the flare stack burning more than a threshold, Mission Control strings in the established tone, the main quest delivering plastic and sulfur and rewarding the `deep_mining` placeholder technology plus items that exist.
- Tests: chapter loading, sequence on synthetic counters, the mixing counter, the ordering test.

## Verify

- Builds and tests pass.
- User: couch test 3. Plastic is produced on both routes and the waste gas runs a generator.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `data/quests/chapter_06.sjson` and `src/quest_chapter_06_test.odin`; changes to `fluid.odin` (phase filter `burnable_gas`), `machine_fluid_ports.odin`, `fluid_machine.odin` (relief valve, `flared_litres`), `fluid_network.odin` (mixing refusals), `power_network.odin` (`generator_gas_litres`), `statistics.odin` (three counters), `quest.odin` (`produce_fluid`, three hint counters, `Quest_References.fluids`), `quest_runtime.odin`, `ui_journal.odin`, `main.odin`; data in `machines.sjson`, `technologies.sjson`, `strings/en.sjson`, `quests/chapter_01.sjson` (format description); the oil, combustion, quest, lab and recipe tests.

### Carry overs from 0032

- Flare stack as a relief valve: it burns (and asks for power) only while its port holds at least 90 percent of its capacity (180 of 200 L), otherwise it is Idle. Since the network evens out fill fractions, the port only gets there once the other ports and tanks on the network are about as full. This is fill fraction, not a strict priority: the 0020 push rule and the branch fairness gap still let a flare close to the refinery fill before a generator on another branch, and a flare keeps up to 179 L it never burns. The 0030 flare test now starts from a full port (burns 21 L down to 179), a new test pipes the flare to a storage tank (no flaring at 80 percent, flaring at 98), and the 0030 determinism test now expects 0 L of gas voided (90 L spread over pipes and the flare never reach 90 percent).
- Combustion generator port: a port filter, not an insertion check. `Fluid_Phase_Filter` gained `burnable_gas` (a gas with `fuel_kilojoules_per_litre > 0`), the generator's port uses it and the loader requires it. Steam on the network closes the port like any mixing refusal and stays in the pipe (test `test_combustion_generator_port_refuses_steam`).

### Chapter 6 as shipped

1. `uphill`: research `fluid_handling`, place 1 pump and 1 storage tank.
2. `tar`: place 1 tar pit pump and 1 refinery; hint "Two fluids, one pipe. The pipe declined." on `mixing_refusals` 1.
3. `fractions`: 500 L of petroleum gas produced since activation (`produce_fluid`), research `cracking`.
4. `flare`: place 1 flare stack; hint "Burning gas to make nothing. The venture calls that a rounding error." on `flared_litres` 1000.
5. `plastic`: research `plastics`, place 1 chemical plant, 50 plastic bars produced since activation.
6. `two_routes`: research `renewable_plastics`, place 1 wood gasifier, 20 more plastic bars since activation.
7. `waste_power`: research `combustion_power`, place 1 combustion generator, counter `generator_gas_litres` 300.
8. `deep_mining_permit` (main): deliver 200 plastic bars and 50 sulfur (3 of 8 capsule slots); rewards `deep_mining` through `unlocks_technology`, 100 steel, 50 electronic circuits.

No reorder was needed: the whole chapter ordering test passes with chapter 6 appended.

### Deviations and choices

- `produce_fluid` always counts from activation (no flag): `{type = "produce_fluid", fluid, litres}`, a count is refused. It reads `Statistics.fluids.produced`, so pumps, boilers and crafting machines count; petroleum gas from cracking counts like gas from the refinery. `Quest_References` gained `fluids`.
- `mixing_refusals` counts a machine port going from open to closed in `mark_closed_ports`, so a port that stays closed counts once. It covers every closure: another fluid, a fixed fluid filter, and phase or `burnable_gas` filters (a liquid at a flare stack, steam at a generator).
- `flared_litres` is a new counter instead of `fluids.voided`, since voided also holds fluid byproducts a lenient world dropped. `generator_gas_litres` counts gas combustion generators drew, steam engines excluded.
- Not measurable, said in the chapter header: that the pump lifts water uphill, that gases go into tanks, and which route made the plastic (one item on both), so `two_routes` asks for 20 more bars after the gasifier is placed.
- `deep_mining`: `placeholder = true` and `quest_gate = true`, unlocks nothing, labs refuse it (`Placeholder` refusal comes first). Guessed: prerequisite `plastics`, 200 packs of 30 s, science packs 1 and 2.
- `doc/quests.md` bends (not edited, outside the file list): the objective table needs `produce_fluid`, the hint counter list needs `mixing_refusals`, `flared_litres`, `generator_gas_litres`, and chapter 6 needs an "As implemented" note. `doc/fluids.md` needs a 0033 note (relief valve, `burnable_gas`, mixing refusals). The format description in `chapter_01.sjson` is updated.
- Saves: `Statistics` gained three fields and the data changed, so older saves are refused.

### Not verified

Everything played or seen: the journal lines ("Produce Petroleum gas 0 / 500 L", the generator gas label), the tone of the new lines in context, and the pacing of every count. Whether the flare hint at 1000 L fires in play now that the flare burns only on a full network (it needs a refinery with no gas consumer for a while). The relief valve against a generator on a real refinery network is covered only by the tank test, not by a generator test. The shipped data loads through the real loader (the binary gets past content loading and fails only at opening a window).

### Open questions

- Should the mixing hint also fire for phase refusals (a liquid at a flare stack, steam at a generator), as it does now, or only for two fluids of the same phase?
- Should the flare stack get a strict priority below consumers instead of the 90 percent threshold, given the branch fairness gap from 0020?
- Is 90 percent the right threshold, given that a flare keeps up to 179 L of gas that nothing burns?
