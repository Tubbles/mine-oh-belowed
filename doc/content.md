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
- Loose items (spilled, dropped, fallen off a belt end) vanish after `loose_item_despawn_minutes` in `data/game.sjson`: 15, generous on purpose so a spill can be walked back to; 0 keeps them forever, a week is the maximum (0062).

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

Tools gate hand mining (0051, user decision 2026-09-27): every minable block has a tool tier, hands mine tier 0 (soil, sand, wood, leaves, torches, tar, slag heaps), and the best pickaxe anywhere in the inventory must reach the block's tier; there is no speed bonus and no durability, and drills ignore tiers.

Pending the decision on whether tools gate anything (SUGGESTIONS.md). Listed as speed multipliers only.

| Tool | Recipe | Mining speed |
| --- | --- | --- |
| Hands | | 1 (three seconds for stone) |
| Wooden pickaxe | 3 plank, 2 stick | Tool tier 1: stone, spent rock, coal, hematite and chalcopyrite ore, brick, concrete, asphalt |
| Stone pickaxe | 3 stone, 2 stick | Tool tier 2: cassiterite, galena, sphalerite, pentlandite ore |
| Iron pickaxe | 3 iron plate, 2 stick | Tool tier 3: deep stone, gold quartz |
| Geologist's hammer | 2 iron plate, 1 stick | Assays veins, tool tier 2 |

## Machines (phases 1 to 4)

A machine's `model` key (0055) names a `.vox` file in `data/models`, authored in MagicaVoxel at 8 or 16 voxels per block with z up and the model's +x side as its front; the mesh is scaled to the footprint. Placeholders come from `tools/make_placeholder_models.py` until an artist replaces them; since 0056 every machine but belts and pipes has one. A `motion` key (kind `pump`, `spin`, `swing`, `bob` or `glow`; `axis`; `amplitude` in blocks or turns; `period_seconds`; `pivot` and, for arms, `hand` in footprint blocks) moves the machine's `<model>_part.vox` while it works: drills pump, assemblers and engines spin, inserter arms swing with their item, pumps bob, furnaces and labs glow. Palette indices 240 to 255 are emissive.

The player's body (0066) is six files in `data/models`: `player_torso.vox`, `player_head.vox`, `player_arm_left.vox`, `player_arm_right.vox`, `player_leg_left.vox` and `player_leg_right.vox`, each the whole 10 by 29 by 10 voxel frame at 16 per block (about the 0.6 by 1.8 by 0.6 block collision box) with only its limb filled, +x the front and +z the right side. The game swings each limb about a pivot it reads from the limb's voxel bounds, so a replacement keeps the frame size and puts the shoulders at the tops of the arms, the hips at the tops of the legs and the neck under the head. The placeholders come from the same script.

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
| Offshore pump | 2 wide along its facing | 2 circuit, 1 pipe, 1 iron gear | 1200 L per s, 6 m head | | Start |
| Pipe | 1×1×1 | 1 pipe | 100 L capacity per block | | Start |
| Pump | 1×2×1 | 1 steel, 1 iron gear, 1 pipe | 1200 L per s, 30 m head | 30 kW | Research: fluid handling |
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
| Fast belts | Belt 2, ramp 2, lift 2 (1800 per min) | 100 × 30 s, science packs 1 and 2 (landed with 0037) |

Prerequisites (added by 0021, in `data/technologies.sjson`): logistics, electric mining and steel processing need automation; optics needs electric mining; fluid handling and prospecting need steel processing; logistics science needs logistics; fast belts need logistics science.

Main quest gate for phase 4: the venture releases the steam engine schematics once the outpost reaches 40 iron plates per minute and holds it for five seconds (chapter 3's main quest in `quests.md`). Until then the player has boilers and no way to use the steam. One gate for the phase, nothing else waits on it.

## Biomes

A column takes the first biome in `data/biomes.sjson` whose height (relative to sea level), moisture and temperature ranges contain it. Temperature (0058) runs from -1 to 1: a latitude band along z (0.1 at the origin, cold about 1500 blocks north, towards -z, and hot about 1500 blocks south), noise of amplitude 0.35 at a wavelength of 600 blocks, minus 0.006 per block above sea level. Moisture is noise from -1 to 1.

| Biome | Height | Moisture | Temperature | Surface |
| --- | --- | --- | --- | --- |
| Lake | below sea level | any | any | Sand |
| Mountains | 48 and up | any | any | Stone, boulders, no trees |
| Cold barrens | 0 and up | any | -0.45 and below | Snow over frozen dirt, boulders, no trees (pine listed at density 0) |
| Highland | 24 to 47 | 0 and up | any | Grass over stone, few pines and birches, boulders |
| Badlands | 6 to 47 | -0.2 and below | 0.3 and up | Red rock layered with pale rock every 4 blocks, no trees (dead tree listed at density 0) |
| Steppe | 0 to 23 | -0.35 to 0.1 | 0.2 and up | Dry grass over dirt, rare acacias and dead trees |
| Wetland | 0 to 3 | 0.6 and up | -0.2 and up | Mud over dirt, few birches and oaks |
| Hills | 24 to 47 | any (dry side, the highland takes the wet) | any | Stone, few pines, boulders |
| Tar flats | 0 to 5 | -0.45 and below | 0.1 and up | Tar over dirt, tar pits in low spots |
| Desert | 0 and up | -0.35 and below | 0.1 and up | Sand, no trees (dead tree listed at density 0) |
| Beach | 0 to 1 | any | any | Sand, no trees (palm listed at density 0) |
| Coastal dunes | 1 to 3 | 0.3 and below | -0.2 and up | Sand, no trees (palm listed at density 0) |
| Forest | 0 and up | 0.3 and up | -0.45 to 0.6 | Grass, dense oaks and birches with clearings |
| Plains | any | any | any | Grass, groves of oaks and birches |

The climate biome blocks drop dirt (frozen dirt, dry grass) or stone (red and pale rock); snow drops itself and mud gives the mud item, which places it again.

Ground cover (0082): each biome's `ground_cover` list in `data/biomes.sjson` names cross shaped cover blocks, each with a chance per column and the top blocks it stands on. One hash of the column (the `Ground_Cover` sub seed) picks at most one entry, entries in order against the running sum of their chances (a biome's chances add up to at most 1), and the cover goes into the cell above the surface when that cell is still air after trees and boulders (so never under water) and the column is not in a vein footprint. The landing pad clears its own cells. Plains: grass tuft 0.25, tall grass 0.05, red and yellow flowers 0.02 each, on grass. Forest: grass tuft 0.15 on grass. Highland: grass tuft 0.1 on grass. Steppe: grass tuft 0.1 and dead bush 0.04 on dry grass. Wetland: reeds 0.2 and grass tuft 0.1 on mud. Badlands and desert: dead bush 0.01 on red rock and on sand. The other biomes have none. The six cover blocks (`grass_tuft`, `tall_grass`, `flower_red`, `flower_yellow`, `dead_bush`, `reeds`) are not solid, dig in 0.05 seconds by hand and drop their own item, which places them again. Cover needs the block below it: mining that block turns the cover to air and spills its item as a loose item.

Ambient life (0075, render only, nothing saved): a biome's optional `bird_density` (0 to 1, default 0) is the chance that a flock cell of 96 by 96 blocks whose loop centre lies in the biome holds a flock of birds: forest 0.6, wetland 0.5, plains 0.4, highland and beach 0.3, the rest 0. A `ground_cover` entry with `insects = true` (optional) marks its block as a flower: insect motes circle one in two of that block's cells wherever it stands, placed by the player too. Shipped: `flower_red` and `flower_yellow` in the plains. Fish shadows need no data: one in eight source water cells under an open cell with water below gets one. See `architecture.md` (Ambient life).

## Trees

Tree species (work item 0059) live in `data/trees.sjson`; each biome lists the species its trees are drawn from, by weight, in `data/biomes.sjson` (`trees`), and a biome with a `tree_density` above 0 must have the list. The shapes are pure procedures in `src/generation_features.odin`. Every log block drops the `log` item and every leaves block the `leaves` item, so recipes see one kind of wood.

| Species | Log | Leaves | Trunk | Crown |
| --- | --- | --- | --- | --- |
| Oak | log | leaves | 6 to 10 | round, radius 3 |
| Birch | birch log (pale bark) | birch leaves (light green) | 8 to 12 | round, radius 2 |
| Pine | pine log (dark bark) | pine needles (dark green) | 10 to 16 | conical, radius 3 |
| Acacia | log | acacia leaves (olive) | 5 to 8 | flat, radius 4 |
| Palm | palm log | palm fronds | 8 to 12 | flat, radius 2 |
| Dead tree | dead wood (grey) | none | 4 to 8 | none |

- Crowns: round runs from two layers below the trunk top to two above, widest at and just below the top; conical steps down from its radius near the bottom to 1 at the top in pairs of layers (the upper one of each pair narrower) with a tip block above, starting a third of the trunk up; flat is a disc at the trunk top and a disc of radius 1 above it. Discs have their corners cut.
- No roots (work item 0083): the log blocks beside the foot of a trunk read badly, so every tree is its trunk and crown alone.
- Biome lists: forest oak 3 and birch 1; plains oak 1 and birch 1; highland pine 2 and birch 1; hills pine; cold barrens pine; steppe acacia 3 and dead tree 1; wetland oak 1 and birch 2; badlands and desert dead tree; beach and coastal dunes palm; lake, mountains and tar flats none. Biomes at density 0 grow nothing; their list names the species for when a density is set.
- Clearings: a noise of wavelength 48 blocks keeps about `clearing_share` of a biome free of trees: forest 0.35, plains 0.5 (with its density raised from 0.06 to 0.15, so its trees stand in groves). Trees also keep off vein outcrops and at least 4 blocks off the landing pad, which clears only 10 blocks above itself.
- Felling (`src/tree_felling.odin`): mining a log drops every log straight above it as loose `log` items and queues the leaves near the felled column for decay. A queued leaf decays 1 to 4 seconds later unless a log lies within 4 blocks (Manhattan), then queues its leaves neighbours. One decaying leaf in 8 drops a `leaves` item and one in 20 a `sapling` (no use yet). Leaves the player places only decay when a log near them is felled.

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
| Coal | 90% coal, 10% spoil (gravel) | Plains, hills, steppe, wetland |
| Mixed | 40% hematite, 40% chalcopyrite, 20% spoil | Hills |
| Quarry | 60% stone, 20% sand, 20% gravel | Everywhere |

An outcrop is the visible top of a vein, not its reservoir: hand mining takes the outcrop blocks, drills draw from the reservoir under the whole footprint. When players mine a vein's last outcrop block while its reservoir still has units (0096), Mission Control says once per vein that the vein continues below (`mc_outcrop_spent`), and the vein counts as known: the map keeps its footprint drawn like an assayed one, while the drill panel does not call it assayed.

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

- Phase 5: crusher, washer (consumes water, outputs mud), alloy furnace, recycler, assembler 2, fast belt, fast inserter, long inserter, steel chest, medium pole, science pack 2, lead, zinc, nickel, brass. Crusher, washer, alloy furnace, galena, sphalerite and pentlandite veins, lead, zinc and nickel plates and brass landed with 0026; the recycler (25 percent of the first producing recipe's inputs, rounded down, behind a `recycling` technology), slag (one per plate or alloy craft, stacking to 100), slag to gravel, gravel and water to concrete, mud to clay to brick, and the steel furnace landed with 0027. Guessed times and costs are listed in both work items.
- Phase 6: tar pit pump, refinery, cracking unit, chemical plant, flare stack, combustion generator, wood gasifier, plastics, sulfur, bitumen, asphalt, science pack 2 (plastic based, from 0031). The storage tank holds gases, so there is no separate gas tank. Everything except the combustion generator landed with 0030 and 0031; guessed values are in their work items.
- Phase 7: bore drill, mining fluid, seismic thumper, hydro turbine, big pole, substation, assembler 3, express belt, stack inserter, bauxite, gold, quartz, silicon, science pack 4. Bore drill, mining fluid, deep veins, bauxite to aluminium through the washer and the electrolyser, gold and quartz to silicon landed with 0035; guessed values are in its work item.
- Phase 8: launch pad, rocket assembly, rocket parts, cargo capsule, orbital survey, infinite research, science pack 5. The launch pad, rocket structure, guidance unit, cargo capsule and rocket fuel landed with 0040. Contracts, venture credit, the catalogue, the orbital survey and infinite research landed with 0041: every item has a `price` in `data/items.sjson` (raw and ore 1, plates 2, steel 12, crafted items about the sum of their inputs, aluminium, silicon and gold well above); `data/contracts.sjson` holds eleven contracts in three tiers opened at 0, 3 and 10 rockets launched, deadlines of 30 to 60 game minutes paying 30 to 50 percent when late, up to three open at a time; the catalogue sells 50 silicon for 600 credit, 50 aluminium plate for 750, 20 gold plate for 600, 100 science pack 2 for 2250 and an orbital survey (surface veins within 256 blocks of the pad) for 3000. Mining productivity and research speed are infinite technologies after rocket program: 100 packs of science 1 and 2 at 30 s for level 1, 1.5 times more per level, 10 percent per level. Every number is a guess for playtesting.

## Block shapes

A block has a `shape` in `data/blocks.sjson` (0061, default `cube`): `slab` (the lower half of its cell), `stairs` (a lower half plus a quarter at the back, rising towards +x), `post` (a column 2 by 2 texels wide and 10 texels high: the torch) or `cross` (two diagonal quads drawn from both sides, for the ground cover of 0082). Slabs and stairs are solid, stop water and collide with their boxes, so the player stands on a slab half way up and jumps onto stairs (there is no step up); posts and crosses are not solid and are targeted by their bounds. Only solid cubes are opaque, so light passes slabs, stairs and torches. The loader expands an oriented shape into variant blocks right after the listed one: a slab `<id>` gets `<id>_upper`, stairs `<id>` get `<id>_r1` to `<id>_r3` for the other quarter turns. Variants share the listed block's name, textures and hardness, are never discoverable, and must be listed in the `mined_from` of the listed block's item so they drop it. Slabs and stairs of stone, concrete and planks (`stone_slab`, `stone_stairs`, `concrete_slab`, `concrete_stairs`, `plank_slab`, `plank_stairs`) are start recipes by hand or in the assembler: 1 block gives 2 slabs, 3 blocks give 4 stairs.

`keep_orientation = true` (0088, default false) keeps the tile of a block's side faces upright where the chunk shader otherwise turns and mirrors every tile per block to break up repetition (see [architecture.md](architecture.md)); shipped on the textures with an up: the logs, grass and dry grass (the fringe), the rock strata (red and pale rock, spent rock, slag heaps), brick, the torch, the ground cover and the slabs and stairs. Tops and bottoms vary on every block. A tile that varies is also slid by a whole texel offset per block and wrapped inside the tile (0101), so it must be periodic: `texture_periodicity_test.odin` reads every opaque varying tile under `textures/blocks/` and fails when the mean texel difference across the wrap edge (column 15 beside column 0, row 15 beside row 0) exceeds 2.5 times the mean across its interior edges. `framed = true` (0101, default false) marks a block whose varying faces are a picture with a centre rather than a periodic tile: the shader turns and mirrors them but never slides them, and the periodicity check leaves the block out; shipped on the logs (the rings inside a bark rim of their ends).

Coloured light (0072): a block's `light_level` (0 to 15) is the block light it emits, and an optional `light_color = [red, green, blue]` (0 to 15 each) colours it; the largest channel must equal `light_level`, which stays the one level everything else reads (the flame cells, the sound, the markers), and without `light_color` the light is white, `light_level` on all three channels. A lamp in `data/machines.sjson` takes the same two keys. Shipped: the torch is warm (`light_level = 15`, `light_color = [15, 11, 6]`), the lamp a cool white (`light_level = 15`, `light_color = [14, 14, 15]`). The furnace's and the boiler's glow is their models' emissive voxels, not light.

## Textures

Block textures and item icons are 16 by 16 RGBA PNG files under `data/textures/` (0060), or for the blocks in `textures/procedural.sjson` tiles the game generates (0099), loaded into atlases at start, on a content reload and when a file changes (a presentation hot reload category).

- `textures/blocks/<block id>.png` serves all three face groups of the block. `<id>_top.png`, `<id>_side.png` and `<id>_bottom.png` override one group each (grass: a green top, a dirt side with a green fringe, the plain file dirt for the bottom). A block or group without a file keeps its colour from `blocks.sjson` with a little noise. Shape variants (`<id>_upper`, `<id>_r1`) are drawn with the tiles of the block they were expanded from.
- `textures/procedural.sjson` (0099) lists the blocks whose tile the game generates from parameters instead of reading a file: the seven ores, whose PNG files are gone. The key `textures` holds entries `{block = "<id>", kind = "ore", seed = <int>, <parameter> = <value>, ...}`; every key is required, and an unknown key, an unknown block, a block listed twice, a value outside its range or a kind other than `ore` refuses the whole file (logged, naming the entry; the blocks then take their files or colour tiles). The generated tile serves all three face groups and is taken before any file. The ore colour is the block's `texture.side` in `blocks.sjson`, the ground colour `stone`'s. An ore tile (`src/texture_generate.odin`, pure: same parameters, same pixels) is white noise from a hash of the seed and the texel, blurred by a round Gaussian that wraps at the tile edge (on the torus, so every texel has the same statistics); the highest `share` of texels are blobs in the ore colour with their own grain, the rest is stone with a grain and a mottle, and stone next to a blob is darkened as a rim. Parameters (range, slider step): `seed` (0 to 2147483647, 1), `share` (0.05 to 0.5, 0.01: the fraction of texels in blobs, exact to a texel), `blob_width` (0.3 to 3, 0.05: the blur's standard deviation in texels; below about 0.55 the blur is close to white noise and the blobs join diagonally into a checkerboard, above about 0.8 a tile holds only a few large blobs that read per block), `crystal_size` (1 to 4, 1: the noise is constant over cells of that many texels, 2 and up give blocky blobs; 3 leaves a narrower last row and column of cells), `stone_grain` (0 to 32, 1: per texel brightness offset), `stone_mottle` (0 to 48, 1: smooth brightness offset, the stone mottle blurred at 1.5 texels), `ore_grain` (0 to 48, 1), `rim_strength` (0 to 0.8, 0.05: the fraction by which stone next to a blob is darkened). The file is a presentation file: a change rebuilds the atlas like a PNG change.
- Texture edits (0099): `$XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson` (`~/.local/state/...` without the variable) has the same form and checks; its entries replace the data file's per block (or add a block). The in-game texture editor (0100, `doc/ui.md`) writes it on Save with every procedural texture's current parameters, one entry per line in the data file's form, so an entry copies into `procedural.sjson` as it is; once the chosen values are in the data file, delete the edits file, or its entries keep replacing the data file's. A file that does not load is logged and ignored as a whole. It is read on every atlas build and when the texture editor opens, not watched.
- `textures/items/<item id>.png` is the item's icon; transparent texels show the slot behind. An item without one shows its placed block's tile, or two letters.
- A file that is not 16 by 16 with 8 bit channels, or does not decode, is refused with a line in the log and takes the fallback.
- `tools/make_placeholder_textures.py` writes the whole placeholder set (and the UI icons, see UI theme and icons) from the ids and colours in `blocks.sjson` and `items.sjson`: block patterns by material family from the id (stone, rock strata, gold quartz's blobs over stone, dirt, sand, grass, bark grain with ring tops, mottled leaves, water, snow, tar, concrete, brick, and ground cover as a plant silhouette on transparent texels: blades, a flower on a stem, a bare twiggy bush, reeds, and the torch as a stick with a flame head on transparent texels, which the post shows the stick of and the item icon whole), item shapes by category (plates, lumps, crushed grains, gears, rods, flasks for science packs, tool silhouettes standing upright with the head at the top, a box for machines) coloured from a material table or a hash of the id, and a block placing item as its block's plain texture. Stone, gold quartz, leaves and water use isotropic noise only (0088, `isotropic_field`: white noise blurred by a round Gaussian that wraps at the tile edge, gold quartz's blobs the highest fifth of such a field), with no rows or diagonals, since the chunk shader turns and mirrors those tiles per block. The shader also slides varying tiles per block (0101), so their patterns must wrap at the tile edge: `noise` per texel, `smooth_noise` and `isotropic_field` do by design, the brick's shade per brick and the rock strata (a line every 4 rows, stepping every 4 columns) do since 0101. The log rings do not and need not, since the logs are framed. It writes no file for a block listed in `textures/procedural.sjson`. Run it after adding a block or item; hand made files replace its output one by one.

## UI theme and icons

The UI's look is presentation data under `data/ui/` (0071, `doc/ui.md`, Theme), reloaded while the game runs like the textures:

- `ui/theme.sjson`: the colours (`[r, g, b, a]`, 0 to 255) and the `border`, `corner` and `focus_pulse` lengths in UI units. Every key is optional and defaults to the look from before the file; an unknown key, a wrong type or a value out of range refuses the file.
- `ui/icons/<name>.png`: one 16 by 16 RGBA icon per `Ui_Icon` in `src/ui_theme.odin` (pad buttons, the key cap, item and recipe categories, screens, the HUD's touch buttons), packed into the UI atlas. A test fails on a missing icon or a file that is no icon. `tools/make_placeholder_textures.py` writes the placeholders (its ui family); hand made files replace them one by one.

## Sounds

The sound table `data/sounds/sounds.sjson` (0068) lists every sound: `id`, `file` (a `.wav` under `data/sounds/`, 16 bit PCM), `volume` (above 0 up to 1, before the settings' volumes), `kind` (`effect`, played once, or `loop`, streamed and faded) and `day_only` (optional, see the clusters below). A missing file, a duplicate id, an unknown kind or a volume out of range refuses the table. The ids the game asks for: `footstep_<material>`, `mine_hit_<tier>` (the highest listed tier at or below the player's effective tool tier), `block_break`, `block_place`, `ui_move`, `ui_confirm`, `ui_back`, `hum_burner`, `hum_electric`, `hum_fluid`, `ambience_<name>` (a loop) or `ambience_<name>_1` and on (clustered calls), `rain`, `rocket_launch`, `capsule_landing`, `discovery_chime`, `mission_control_chime` (0069). Sounds are presentation data: a change reloads the table and every file in place (a failed load keeps the old sounds).

- Materials: a block's `sound_material` (default `stone`) picks its footstep, and the table must list `footstep_<material>` for every block's material or the sounds do not load. Shipped: `dirt` (dirt, grass, frozen dirt, dry grass, mud, tar, slag heaps), `sand`, `wood` (logs, plank slabs and stairs, torches), `leaves` (leaves and every ground cover), `snow`, `metal` (the landing pad), `water` (every water level; wading plays the water's material), `stone` for the rest.
- Biome ambience: a biome's `ambience` names either the loop `ambience_<name>` or the effect variants `ambience_<name>_1`, `_2` and on, one of which the table must list; empty is quiet. Shipped: wind over the mountains, cold barrens, highland, badlands, desert and coastal dunes; birds in the hills, forest and plains; insects on the steppe and in the wetland; water at the lake and the beach; nothing on the tar flats. Wind and water are loops.
- Ambience clusters (0089): birds (`ambience_birds_1` to `_3`, `day_only`) and insects (`ambience_insects_1` to `_2`) are short calls of three to five chirps or buzzes. In their biome the game plays one variant, a second 1 to 3 seconds later and in two clusters of five a third, then waits 20 to 60 seconds; each wait, the variant (never the last one again) and the pitch (plus or minus 8 percent) come from a hash of the tick and the cluster count. A `day_only` ambience calls only while the daylight blend is above one half (the first variant's flag speaks for all). The calls play on the ambience volume like the loops. The first cluster of a session waits a full pause.
- Cadence (0089): footsteps come every 2.4 metres walked (`WALK_CYCLE_MILLIMETRES` 4800), about two a second at walking speed; mining hits play at most three a second whatever the dig speed (a hit asked for sooner is dropped); the hum's volume drifts up to 5 percent either way, each drift taking 3 to 7 seconds.
- `tools/make_placeholder_sounds.py` (standard library only, deterministic) writes the placeholder files, 31 at 22050 Hz mono, about 1.7 MB; given a directory it writes there instead of `data/sounds/`: filtered noise bursts for the footsteps, clicks getting sharper per tier, a crunch, a thud, blips, hum loops of whole cycles with a little noise, wind, water and rain loops whose tail is crossfaded into the head, chirp and buzz calls, a rumble, a landing thud and a three note chime. The table is written by hand; recorded sounds replace the files one by one.

## Descriptions and notes

Descriptions (0070): every item, machine and technology names a `description_key` in its data file (optional, `describe_item_<id>`, `describe_machine_<id>` and `describe_technology_<id>` by convention), checked against the string table when the content loads, and a test keeps every shipped entry described. The texts in `data/strings/en.sjson` are one to three sentences in the venture's register (`DESIGN.md`, Lore and tone): what the thing is, what it does for the outpost, and one concrete fact, either real (a formula, a melting point, a density, an ore's metal content) or the game's own (a rate, a power draw, a capacity). A game fact in a description is a copy of a value in the data, so changing a rate means changing its description too. Item descriptions show in the recipe browser, machine descriptions in the machine panel (so a machine's item and the machine have two texts: what it is for, and how it runs), technology descriptions on the technology screen. The fonts load only the code points the string table uses, and a test checks that every shipped face has a glyph for each code point past ASCII in the table (0091, `test_shipped_fonts_have_every_string_glyph`; the multiplication sign is the first); not every selectable face has a degree sign, so temperatures read "degrees Celsius".

Notes (0070): `data/notes.sjson` lists the journal's notes in the order their milestones come in play, each with an `id`, a `title_key`, a `text_key` (`note_<id>_title` and `note_<id>_text`) and one `unlock`: `chapter` (from 1), `item`, `technology` or `quest`. The loader refuses a note with no unlock or two, a target that does not exist or a missing key. Twenty nine notes ship: the asset, the lease, Mission Control, the contractor and the capsule in chapter 1; iron, slag, coal and copper when each is first obtained; the strata, the survey and the ledger in chapter 2; the utility and the buyers in chapter 4; the station and ore grade in chapter 5; lead and zinc and nickel on their ores; the extraction rights, the tar flats and the flare in chapter 6; the deep strata, bauxite, gold, the previous tenants and aluminium in chapter 7; the launch permit, the orbital survey and self sufficiency in chapter 8. Geology in a note is real geology (Mississippi Valley type lead and zinc, magmatic nickel with copper, lateritic bauxite), the rest is the venture.

## Learned from couch tests

Each entry: date, what was played, what the numbers did wrong, what changed.

- 2026-09-27, couch test 1, chapter 1 on the M8 build. The hematite outcrop required within 150 blocks of the spawn was minutes of flying away and under trees; the spawn search accepted a river gorge next to the pad. Change (0045): three starter veins stamped 24 to 40 blocks from the pad, outcrops generated after trees and boulders with the column above cleared, and a flatness requirement on the spawn. Mining under a lake crashed the mesher (fixed). The statistics overlay was always on (0044).
- 2026-09-28, couch report, chapter 2. Fifty iron plates by hand emptied the starter iron outcrop's visible blocks before the chapter asked for a drill. Change (0096): the drill quest comes right after gears and the fifty plates count from their quest's activation, so they are the drill's output; mining the last outcrop block brings a Mission Control line that the vein continues below, and the map keeps the footprint.
- 2026-09-28, factory benchmark (0050), first numbers, from the couch machine (host `bazzite`, Ryzen 7 2700X, headless, release build); the Steam Deck's are still to come. Average and worst tick in milliseconds: size 1 (321 entities) 0.026 and 0.046, size 4 (1281) 0.075 and 0.18, size 16 (5121) 0.27 and 0.77, size 64 (20481) 1.35 and 6.5 (measured once; the command line now stops at 16 and larger sizes are read off it). Every size holds 60 ticks per second many times over. The electric networks (`tick_electric_networks`) are the largest share at every size (22 to 29 percent), then inserters and fluids (about 20 percent each); at size 64 statistics grows to 20 percent. Nothing changed yet; these are the baseline for the performance pass.
