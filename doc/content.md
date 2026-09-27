# Content catalogue

Living document. Every item, machine, recipe and technology, the values that connect them, and the rules those values follow. Phases 1 to 4 are listed in full as the first cut for the data files. Phases 5 to 8 are listed at machine level and grow as their milestones approach. Once `data/*.sjson` exists, the value tables move there and this document keeps the rules, the phase budgets, the ratio checks and the lessons. Nothing here is final: the couch tests decide.

## Rules of thumb

- A tick is one sixtieth of a second. Recipe times are stated in seconds and are always a whole number of ticks. The UI shows every rate per minute.
- Power is in kilowatts and megawatts, energy in megajoules. A fuel item's value is the energy a machine extracts from it, no efficiency factor.
- Fluids are in litres. One water unit is one litre.
- Factorio's proportions are the anchor, its absolute values are not. Where a ratio below matches Factorio it is on purpose: a decade of players proved those ratios produce interesting math.
- Stack sizes are small so pockets fill fast in phase 2 and belts win early: ore, plates, steel and spoils 50, other intermediates 100, machines and tools 10, blocks 50, fluids are not items. Mining a block yields exactly one item: the item that places it, or for grass and the ore blocks the item listed as mined from them (dirt, hematite, coal, chalcopyrite, cassiterite).
- Hand crafting has speed 1. A hand crafted recipe takes its listed time.
- When a phase runs long in a couch test the fix is lower cost, not fewer steps.

## Phase budgets

Target playtime and what the player owns at the end of each phase. These drive recipe costs.

| Phase | Target | End state |
| --- | --- | --- |
| 1 Arrival | 10 min | Wooden pickaxe, a stack of logs, stone, one stone furnace placed |
| 2 Workshop | 30 min | 3 stone furnaces, 2 burner drills, 200 plates, first gears, belts discovered |
| 3 Automation | 45 min | One self feeding coal drill, 4 drills feeding 3 furnaces, inserters, chests, ten unattended minutes |
| 4 Power | 75 min | 1 offshore pump, 1 boiler, 2 steam engines, 10 poles, 4 electric drills, 4 assemblers, 2 labs, 5 technologies |

Phases 1 to 4 together are about two hours forty minutes, spread over two or three sittings. Budgets for phases 5 to 8 follow when their content is listed. The user suspects this pacing is on the quick side; couch test 1 checks it first.

## Raw materials (phases 1 to 4)

| Item | Source | Fuel value | Notes |
| --- | --- | --- | --- |
| Log | Trees, by hand or harvester | 2 MJ | |
| Stone | Dug stone blocks, quarry veins | | |
| Dirt | Dug topsoil | | Placeable, no recipe use yet |
| Sand | Dug sand, spoil from veins | | Glass |
| Clay | Dug clay layers near water | | Bricks, phase 5 |
| Gravel | Spoil from veins, crushed stone | | Concrete, phase 5 |
| Coal | Coal veins | 4 MJ | |
| Hematite | Iron veins | | Iron ore |
| Chalcopyrite | Copper veins | | Copper ore |
| Cassiterite | Copper and tin veins | | Tin ore |
| Water | Rivers and lakes, offshore pump | | Fluid |
| Steam | Boiler | | Fluid, gas phase |

## Processed materials and intermediates (phases 1 to 4)

| Item | Recipe | Time | Made in | Channel |
| --- | --- | --- | --- | --- |
| Plank ×4 | 1 log | 0.5 s | Hand, assembler | Start |
| Stick ×4 | 1 plank | 0.5 s | Hand, assembler | Start |
| Stone brick | 2 stone | 3.2 s | Furnace | Start |
| Charcoal | 2 logs | 3.2 s | Furnace | Discovery (logs smelted) |
| Iron plate | 1 hematite | 3.2 s | Furnace | Start |
| Copper plate | 1 chalcopyrite | 3.2 s | Furnace | Start |
| Tin plate | 1 cassiterite | 3.2 s | Furnace | Discovery (cassiterite obtained) |
| Bronze plate ×4 | 3 copper plate, 1 tin plate | 6.4 s | Furnace | Discovery (both plates produced) |
| Glass | 2 sand | 3.2 s | Furnace | Discovery (sand obtained) |
| Steel | 5 iron plate, 1 coal | 16 s | Steel furnace | Research: steel processing |
| Iron gear | 2 iron plate | 0.5 s | Hand, assembler | Start |
| Iron rod ×2 | 1 iron plate | 0.5 s | Hand, assembler | Start |
| Copper wire ×2 | 1 copper plate | 0.5 s | Hand, assembler | Start |
| Electronic circuit | 1 iron plate, 3 copper wire | 0.5 s | Hand, assembler | Discovery (wire produced) |
| Pipe | 1 iron plate | 0.5 s | Hand, assembler | Start |
| Science pack 1 | 1 copper plate, 1 iron gear | 5 s | Hand, assembler | Discovery (gear produced) |

Charcoal has a fuel value of 3 MJ. Planks and sticks burn for 1 MJ and 0.5 MJ.

## Tools (phases 1 to 4)

Pending the decision on whether tools gate anything (SUGGESTIONS.md). Listed as speed multipliers only.

| Tool | Recipe | Mining speed |
| --- | --- | --- |
| Hands | | 1 (three seconds for stone) |
| Wooden pickaxe | 3 plank, 2 stick | 1.5 |
| Stone pickaxe | 3 stone, 2 stick | 2 |
| Iron pickaxe | 3 iron plate, 2 stick | 3 |
| Geologist's hammer | 2 iron plate, 1 stick | Assays veins, mines like a stone pickaxe |

## Machines (phases 1 to 4)

Footprint is width by depth by height in blocks. Power is electric unless marked fuel.

| Machine | Footprint | Recipe | Rate | Power | Channel |
| --- | --- | --- | --- | --- | --- |
| Stone furnace | 2×2×2 | 5 stone | Speed 1 (one plate per 3.2 s, 18.75 per min) | 90 kW fuel | Start |
| Steel furnace | 2×2×2 | 6 steel, 10 stone brick | Speed 2 | 90 kW fuel | Research: steel processing |
| Burner mining drill | 2×2×2 | 3 iron gear, 3 iron plate, 1 stone furnace | 18.75 vein units per min, 15 ore on an 80% vein | 150 kW fuel | Start |
| Electric mining drill | 3×3×3 | 3 circuit, 5 iron gear, 10 iron plate | 30 ore per min plus 6 spoil | 90 kW | Research: electric mining |
| Burner inserter | 1×1×1 | 1 iron plate, 1 iron gear | 36 items per min | 94 kW fuel | Start |
| Inserter | 1×1×1 | 1 iron plate, 1 iron gear, 1 circuit | 50 items per min | 13 kW | Discovery (circuit produced) |
| Filter inserter | 1×1×1 | 1 inserter, 2 circuit | 50 items per min, one filter | 13 kW | Research: logistics |
| Belt ×2 | 1×1×1 | 1 iron plate, 1 iron gear | 900 items per min, two lanes | | Start |
| Belt ramp | 1×1×1 | 1 belt, 1 iron plate | As belt, one block of rise | | Start |
| Belt lift | 1×1×1 per block | 2 belt, 2 iron gear | As belt, vertical | | Start |
| Splitter | 1×2×1 across the flow | 5 circuit, 5 iron plate, 4 belt | Splits or merges two belts, priority and filter | | Research: logistics |
| Wooden chest | 1×1×1 | 4 plank | 16 slots | | Start |
| Iron chest | 1×1×1 | 8 iron plate | 32 slots | | Start |
| Offshore pump | 2 wide along its facing | 2 circuit, 1 pipe, 1 iron gear | 1200 L per s | | Start |
| Pipe | 1×1×1 | 1 pipe | 100 L capacity per block | | Start |
| Pump | 1×2×1 | 1 steel, 1 iron gear, 1 pipe | 1200 L per s, lifts liquid | 30 kW | Research: fluid handling |
| Storage tank | 3×3×3 | 20 steel, 5 iron plate | 25,000 L | | Research: fluid handling |
| Boiler | 3×2×2 | 1 stone furnace, 4 pipe | 60 L steam per s from 60 L water | 1.8 MW fuel | Start |
| Steam engine | 3×5×2 | 8 iron gear, 5 pipe, 10 iron plate | 900 kW from 30 L steam per s | | Main quest gate, phase 4 (channel quest in the data) |
| Small pole | 1×1×3 | 1 log, 2 copper wire | Supply volume 5×5 footprint, 4 high. Reach 7 | | Start |
| Lamp | 1×1×1 | 1 circuit, 3 copper wire, 1 iron plate, 1 glass | Light level 14 | 5 kW | Research: optics |
| Power switch | 1×1×1 | 2 circuit, 5 iron plate | Splits a network | | Research: electric mining |
| Assembler 1 | 3×3×2 | 3 circuit, 5 iron gear, 9 iron plate | Speed 0.5 | 75 kW | Research: automation |
| Lab | 3×3×2 | 10 circuit, 10 iron gear, 4 belt | Speed 1 | 60 kW | Start |
| Core sample drill | 1×1×2 | 2 circuit, 5 steel, 5 iron gear | One column per 60 s | 40 kW | Research: prospecting |
| Magnetometer | Handheld | 5 circuit, 2 copper wire, 1 iron plate | Iron veins within 30 blocks | | Research: prospecting |

Machine recipes take 2 s each by hand, 0.5 s for inserters, belts, pipes, poles and chests, tools 1 s. Recipes live in `data/recipes.sjson` and technologies in `data/technologies.sjson` from work item 0012 on. Machine values live in `data/machines.sjson` from work item 0011 on (footprint, kind, slots, speed in percent, fuel power in kilowatts, fluid ports and buffers from 0019); this table stays the design intent.

## Technologies (phase 4, science pack 1)

Costs are packs times seconds per pack in a speed 1 lab. About ten technologies in the first tier.

| Technology | Unlocks | Cost |
| --- | --- | --- |
| Automation | Assembler 1 | 10 × 10 s |
| Logistics | Splitter, filter inserter | 20 × 15 s |
| Electric mining | Electric mining drill, power switch | 25 × 15 s |
| Optics | Lamp | 10 × 15 s |
| Steel processing | Steel, steel furnace | 50 × 15 s |
| Fluid handling | Pump, storage tank | 50 × 15 s |
| Prospecting | Core sample drill, magnetometer | 50 × 15 s |
| Logistics science | Science pack 2 recipe | 75 × 15 s |
| Fast belts | Belt 2 (1800 per min) | 100 × 30 s, phase 5 |

Prerequisites (added by 0021, in `data/technologies.sjson`): logistics, electric mining and steel processing need automation; optics needs electric mining; fluid handling and prospecting need steel processing; logistics science needs logistics; fast belts need logistics science.

Main quest gate for phase 4: the venture releases the steam engine schematics once the outpost has run unattended, sustaining 10 iron plates per minute for ten minutes (chapter 3's main quest in `quests.md`). Until then the player has boilers and no way to use the steam. One gate for the phase, nothing else waits on it.

## Veins (phases 1 to 4)

Vein sizes before the richness multiplier, pending SUGGESTIONS.md item 3.

| Class | Ore units | Frequency |
| --- | --- | --- |
| Scattering | 2,000 to 5,000 | Common, several within sight of spawn |
| Deposit | 20,000 to 60,000 | Regular, a few minutes walk apart |
| Concentration | 100,000 to 300,000 | Rare, far from spawn |
| Deep vein | Five times the surface class | Phase 7, bore drills |

| Vein type | Output mix | Where |
| --- | --- | --- |
| Iron | 80% hematite, 20% spoil (gravel) | Everywhere |
| Copper | 70% chalcopyrite, 10% cassiterite, 20% spoil (sand) | Everywhere |
| Coal | 90% coal, 10% spoil (gravel) | Plains, hills |
| Mixed | 40% hematite, 40% chalcopyrite, 20% spoil | Hills |
| Quarry | 60% stone, 20% sand, 20% gravel | Everywhere |

High grade ore smelts directly. Low grade ore needs crushing and washing (phase 5, work item 0026): the share of low grade rises linearly from 10% at a full reservoir to 60% at 5% remaining, infinite veins stay at 10%. Crushers, washers, the alloy furnace and the assembler are one data kind, `crafting_machine`, with a recipe category and either a player chosen or a fixed recipe picked by the loaded inputs (a fixed category refuses recipes whose inputs are a subset of another's). Steel, bronze and brass are alloy furnace recipes; the stone furnace only makes one input, one output recipes.

## Ratio checks

- Five burner drills on iron veins (75 hematite per min) feed four stone furnaces (75 plates per min). Spoil comes out of the same unit stream, so a drill's total output is 18.75 units per minute.
- Five electric drills (150 ore per min) feed eight stone furnaces or four steel furnaces.
- A yellow belt carries the output of sixty burner drills or thirty electric drills.
- One boiler feeds two steam engines. One offshore pump feeds twenty boilers, so forty engines and 36 MW.
- One boiler burns 1.8 MW: 27 coal per min, or two burner drills' worth of a coal vein. The coal loop is self sustaining with room to spare.
- An assembler at speed 0.5 makes six science pack 1 per minute. Two labs consume eight per minute on a 15 s technology. Three assemblers for two labs.
- A 30,000 unit deposit lasts one burner drill 33 hours and ten electric drills 100 minutes. Finite veins matter only at scale, which is the intent.
- A phase 4 base draws about 1 MW (4 electric drills 360 kW, 4 assemblers 300 kW, 2 labs 120 kW, 20 inserters 260 kW, lamps). One boiler and two engines cover it with a brownout the first time a fifth assembler is placed.

## Phases 5 to 8, machine level

Listed for planning, values follow with their milestones.

- Phase 5: crusher, washer (consumes water, outputs mud), alloy furnace, recycler, assembler 2, fast belt, fast inserter, long inserter, steel chest, medium pole, science pack 2, lead, zinc, nickel, brass. Crusher, washer, alloy furnace, galena, sphalerite and pentlandite veins, lead, zinc and nickel plates and brass landed with 0026; guessed times and costs are listed in its work item.
- Phase 6: tar pit pump, refinery, cracking unit, chemical plant, gas tank, flare stack, combustion generator, wood gasifier, plastics, sulfur, bitumen, asphalt, science pack 3.
- Phase 7: bore drill, mining fluid, seismic thumper, hydro turbine, big pole, substation, assembler 3, express belt, stack inserter, bauxite, gold, quartz, silicon, science pack 4.
- Phase 8: launch pad, rocket assembly, rocket parts, cargo capsule, orbital survey, infinite research, science pack 5.

## Learned from couch tests

Empty until the first couch test. Each entry: date, what was played, what the numbers did wrong, what changed.
