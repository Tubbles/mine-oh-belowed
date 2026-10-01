# Content catalogue

The rules behind the numbers in `data/*.sjson`. Every value lives in its data file, and each file's header comment states the keys, their ranges and the local rules. This document keeps what spans files: units, the stack and price classes, the phase budgets, the gates, the ratio checks, and the authoring rules for textures, models, sounds and text.

- A value is changed in its data file, never copied here. A ratio check below is recomputed when a value it names changes.
- Every number is a guess until the couch tests confirm it. When a phase runs long, lower the cost, not the step count.
- The fluid and power mechanisms are in [fluids.md](fluids.md), belts, inserters and drills in [logistics.md](logistics.md).

## Units

- A tick is a sixtieth of a second (`tick_rate` in `data/game.sjson`). A recipe's `seconds` is its time at speed 1 and a whole number of ticks. `recipe_ticks` truncates to whole ticks, at least one.
- Power in kilowatts and megawatts, energy in megajoules. An item's `fuel_megajoules` is what a machine extracts, with no efficiency factor, except a combustion generator's `fuel_efficiency_percent`.
- Fluids in litres. Fluids are never items and never stack.
- Factorio's proportions are the anchor, its absolute values are not: where a ratio matches Factorio it does so on purpose.

## Items

`data/items.sjson`.

- Nothing stacks below 50 (user, 2026-10-01), so a pocket holds a useful amount of anything. Classes: raw material, ore, spoils, blocks, plates, alloys, steel, crushed ore, alumina, sulfur and bitumen 50, slag 100, the other intermediates (planks, gears, wire, circuits, glass, silicon, plastic, science packs) 100, machines, tools, rocket parts (the stack also caps a launch pad slot, and a rocket takes at most 10), thumper charges and schematics 50, the machines placed by the dozen (inserters, belts with ramps and lifts, poles, pipes, lamps) 100. `item_test.odin` pins a plate, a gear and a machine.
- Mining a block yields exactly one item: the item whose `places_block` it is, or whose `mined_from` lists it. `also_mined_from` adds a second drop (gold quartz gives quartz and gold ore).
- Prices in venture credit grow with recipe depth. The classes are in the header of `data/items.sjson`.

### Tools

Tools gate hand mining and nothing else (0051).

- Each block needs a tool tier that climbs with the hardness of the material, from bare hands for soil and wood to an iron pickaxe for deep rock. The tier list is in the header of `data/blocks.sjson`.
- The best `tool_tier` of any item in the inventory or on the cursor counts (`player_tool_tier`), so the geologist's hammer mines at tier 2. There is no speed bonus and no durability. The time is the block's `hardness_seconds`.
- Drills ignore tiers, and the developer cheat speed mines every tier (`effective_tool_tier`). `test_tool_tier_gates_hand_mining` guards the gate.

## Recipes

`data/recipes.sjson`. Its header gives the channels (start, discovery, research, quest, schematic), the byproduct rule and the furnace limits.

- Craft times by kind: machines 2 s, inserters, belts, pipes, poles and chests 0.5 s, tools 1 s.
- A furnace makes one input recipes with at most a slag byproduct. Two input alloys (steel, bronze, brass) are alloy furnace recipes. Every ore smelt and alloy craft gives one slag.
- Low grade ore goes back to ore through the crusher and the washer (the chain is in the header of `data/recipes.sjson`). It smelts directly only through the low grade iron plate schematic.
- Crushers, washers, the alloy furnace and the assembler, among them, are one kind: `crafting_machine` (`data/machines.sjson`).
- The recycler reverses the first recipe that makes its input and returns 25 percent of each input, rounded down.

### Hand crafting

`crafting.odin` (0138). The hand crafts at speed 1, one run at a time. The HUD shows the queue ([hud.md](hud.md)).

- Queuing takes nothing. It plans the crafts against a virtual inventory: the inventory plus what the queued runs make minus what they use.
- An ingredient short by M gets ceil(M / output count) crafts of its hand recipe queued ahead: the first unlocked hand recipe in `data/recipes.sjson` order whose first product is the item. The resolution recurses up to `HAND_CRAFT_PLAN_DEPTH` levels.
- A raw shortage, a recipe cycle or a chain past the depth refuses the whole plan, and a toast names the reason ([ui.md](ui.md), Recipe browser).
- A plan never counts on covering a deficit of runs already queued: an item's planned count stops at zero.
- A craft takes its ingredients when it starts at the front of the queue. A front craft whose ingredient was spent or dropped waits. The next queue action first plans the makers of what the whole front run lacks against the inventory alone and queues them ahead (`plan_front_repair`), or leaves it waiting when the inventory cannot make the item.
- A finished craft whose outputs do not fit waits with its progress kept. Cancelling takes one craft off the newest run and gives back the ingredients of a craft in progress, refused when they no longer fit.

## Phase budgets

Target playtime and what the player owns at the end of each phase. They drive recipe costs. Phases 1 to 4 add up to about two hours forty minutes over two or three sittings.

| Phase | Target | End state |
| --- | --- | --- |
| 1 Arrival | 10 min | Wooden pickaxe, a stack of logs, stone, one stone furnace placed |
| 2 Workshop | 30 min | 3 stone furnaces, 2 burner drills, 200 plates, first gears, belts discovered |
| 3 Automation | 45 min | One self feeding coal drill, 4 drills feeding 3 furnaces, inserters, chests, ten unattended minutes |
| 4 Power | 75 min | 1 fuel generator, 1 offshore pump, 1 boiler, 2 steam engines, 10 poles, 4 electric drills, 4 assemblers, 2 labs, 5 technologies |

Budgets for phases 5 to 8 come with their couch tests. Planned machines not in the data yet: assembler 2, steel chest and medium pole (phase 5), assembler 3, express belt, stack inserter and science pack 4 (phase 7), science pack 5 (phase 8).

## Technologies and gates

`data/technologies.sjson`: packs times seconds per pack in a speed 1 lab, prerequisites listed earlier in the file.

- One main quest gate per phase, and nothing else waits on it ([DESIGN.md](../DESIGN.md), Research, quests and rockets). Phase 4: the steam engine is a quest channel recipe that chapter 3's main quest unlocks, so until then boilers make steam nothing can use. Phases 6 to 8: `oil_processing`, `deep_mining` and `rocket_program` carry `quest_gate`, labs refuse them, and the main quests of chapters 5 to 7 research them.
- `mining_productivity` and `research_speed` are infinite: each level costs `level_cost_growth_percent` of the one before and adds `effect_percent`.
- The venture's contracts and catalogue are in `data/contracts.sjson`. An orbital survey charts the surface veins within `ORBITAL_SURVEY_RADIUS` of the pad.

## Veins

`data/veins.sjson`: size classes (scattering, deposit, concentration), vein types with their output mix, deep veins at five times the surface class (`deep_units_factor`) for the phase 7 bore drills.

- An outcrop is the visible top of a vein, not its reservoir: hand mining takes outcrop blocks, drills draw from the reservoir under the whole footprint disc.
- Mining a vein's last outcrop block while its reservoir has units makes Mission Control say once per vein that the vein continues below (`mc_outcrop_spent`, 0096). The vein then counts as known: the map keeps its footprint drawn like an assayed one, while the drill panel does not call it assayed.
- A finite vein drained by drills turns its outcrop to `spent_block`.
- The low grade share of a draw rises linearly from `LOW_GRADE_START_PPM` at a full reservoir to `LOW_GRADE_END_PPM` with `LOW_GRADE_END_REMAINING_PERCENT` left (`drill.odin`). Infinite veins stay at the start.
- The starter veins by the landing pad: [quests.md](quests.md), Spawn requirements.

## Ratio checks

Recomputed from the data. A unit is one draw from a vein, ore or spoil.

- A burner drill draws 18.75 units a minute: 15 hematite on an iron vein. A stone furnace smelts 18.75 plates a minute. Five burner drills (75 hematite) feed four stone furnaces.
- Five electric drills (150 hematite) feed eight stone furnaces or four steel furnaces.
- A belt carries 900 items a minute: the hematite of sixty burner or thirty electric drills, fewer once spoil rides along.
- One boiler (60 L of steam a second) feeds two steam engines (30 L each). One offshore pump (1200 L a second) feeds twenty boilers, so forty engines and 36 MW.
- A boiler burns 1.8 MW, 27 coal a minute. A burner drill on a coal vein draws 16.9 coal a minute and burns 2.25, so the coal loop feeds itself with room to spare.
- The fuel generator lights a coal at 25 percent, 1 MJ, which lasts 13 seconds at its full 75 kW. For the same energy it burns four times the fuel of a boiler and engine: it starts the steam plant and is no substitute for it.
- A speed 0.5 assembler makes 6 science pack 1 a minute. A lab on a 15 second technology uses 4.
- A 30,000 unit deposit lasts one burner drill about 27 hours and ten electric drills 80 minutes. Finite veins matter only at scale, which is the intent.
- A phase 4 base draws about 1.1 MW: 4 electric drills 360 kW, 4 assemblers 300 kW, 2 labs 120 kW, 20 inserters 260 kW, the offshore pump 60 kW, lamps. One boiler and two engines cover it.

## World

- Biomes (`data/biomes.sjson`): a column takes the first biome whose height, moisture and temperature ranges hold it. Temperature is a latitude band along z (`ORIGIN_TEMPERATURE` at the origin, colder towards -z, over `TEMPERATURE_PERIOD`), noise (`TEMPERATURE_NOISE_AMPLITUDE` at `TEMPERATURE_WAVELENGTH`) and a lapse of `TEMPERATURE_LAPSE` per block above sea level (`generation_terrain.odin`).
- Trees (`data/trees.sjson`, shapes in `generation_features.odin`): every log block drops `log` and every leaves block `leaves`, so recipes see one kind of wood. Trees have no roots: log blocks beside a trunk's foot read badly (0083).
- Trees and boulders keep off water and vein footprints. A clearing noise of `CLEARING_WAVELENGTH` keeps about a biome's `clearing_share` free of trees. Trees root at least `LEAF_REACH` off the landing pad, which clears only `LANDING_PAD_CLEARANCE` blocks above itself.
- Felling (`tree_felling.odin`): mining a log drops every log above it as loose items and queues the leaves near the column. Placed leaves decay only when a log near them is felled.
- A queued leaf decays after `LEAF_DECAY_MINIMUM_DELAY_TICKS` to `LEAF_DECAY_MAXIMUM_DELAY_TICKS` unless a log lies within `LEAF_SUPPORT_DISTANCE` (Manhattan), then queues its leaf neighbours. One decay in `LEAF_LITTER_CHANCE` drops leaves and one in `SAPLING_CHANCE` a sapling (no use yet).
- Ground cover (a biome's `ground_cover`, 0082): one hash of the column (the `Ground_Cover` sub seed) picks at most one entry, in order against the running sum of the chances. The cover goes into the cell above the surface when it is still air after trees and boulders and the column is outside every vein footprint. The landing pad clears its own cells, and mining under cover spills it ([hud.md](hud.md), Targeting).
- Ambient life (render only): a biome's `bird_density` and a ground cover entry's `insects` ([presentation.md](presentation.md), Ambient life).

## Blocks

`data/blocks.sjson` holds the shapes, orientation flags, light and sound materials.

- Slabs and stairs are solid and collide with their boxes. There is no step up: the player jumps onto them.
- A tile that varies per block is slid by whole texels and wrapped, so it must be periodic: `test_varying_block_tiles_are_periodic` fails when the mean texel difference across the wrap edge exceeds `TILE_WRAP_ROUGHNESS_FACTOR` times the mean across interior edges. `keep_orientation` and `framed` blocks are exempt ([presentation.md](presentation.md), Per block variation).
- Coloured light: the largest channel of `light_color` equals `light_level`, which stays the one level everything else reads. The furnace's and the boiler's glow is emissive voxels in their models, not light.

## Textures

Block tiles and item icons are 16 by 16 RGBA PNG files under `data/textures/`, or generated tiles, loaded into atlases at start, on a content reload and when a file changes (`render_atlas.odin`).

- `textures/blocks/<id>.png` serves all three face groups, and `<id>_top.png`, `<id>_side.png` and `<id>_bottom.png` override one group each. A block or group without a file takes its colour from `data/blocks.sjson` with a little noise. Shape variants use the listed block's tiles.
- `textures/items/<id>.png` is the item's icon ([ui.md](ui.md), Text and theme).
- A file that is not 16 by 16 with 8 bit channels, or does not decode, is logged and takes the fallback.
- `data/textures/procedural.sjson` (0099) lists the blocks whose tile the game generates (`texture_generate.odin`, pure): the seven ores. Its header gives the parameters and ranges. A generated tile serves every face group and wins over any file.
- `blob_width` below about 0.55 blurs little, and the blobs join diagonally into a checkerboard. Above about 0.8 a tile holds a few large blobs that read per block.
- The texture editor ([developer_tools.md](developer_tools.md)) saves `$XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson` in the data file's form. Its entries replace the data file's per block on every atlas build, so once the chosen values are copied into `procedural.sjson`, delete the edits file. A file that does not load is logged and ignored whole.
- `tools/make_placeholder_textures.py` writes the placeholder block tiles, item icons and UI icons from the ids and colours in the data, skipping the procedural blocks. Rerun it after adding a block or item. Hand made files replace its output one by one.
- Placeholder patterns follow the per block variation: stone, gold quartz, leaves and water use isotropic noise only (`isotropic_field`), with no rows or diagonals, and every varying pattern wraps at the tile edge. The log rings need not, being framed.

## Models

How models are loaded, lit and moved: [presentation.md](presentation.md), Machine models and The player.

- A machine model is authored at 8 or 16 voxels per block, z up, with its +x side as the front. The keys are in the header of `data/machines.sjson`.
- The player is six files (`player_torso.vox` and the limbs), each the whole `PLAYER_MODEL_FRAME` at 16 voxels per block with only its limb filled, +x the front and +z the right side. A replacement keeps the frame and puts the shoulders at the tops of the arms, the hips at the tops of the legs and the neck under the head.

## Sounds

`data/sounds/sounds.sjson` lists every sound and the ids the game asks for. The mixer and triggers, footsteps and mining hits included, are in [presentation.md](presentation.md), Sound.

- Every block's `sound_material` needs its `footstep_<material>` and every biome's `ambience` its loop or variants, or the table does not load.
- Ambience calls (`sound_events.odin`): a cluster plays two variants `AMBIENCE_CALL_GAP_MINIMUM_TICKS` to `AMBIENCE_CALL_GAP_MAXIMUM_TICKS` apart, a third in `AMBIENCE_THIRD_CALL_PERCENT` of clusters, then pauses `AMBIENCE_CLUSTER_PAUSE_MINIMUM_TICKS` to `AMBIENCE_CLUSTER_PAUSE_MAXIMUM_TICKS`. The variant never repeats the last one, and the pitch varies by `AMBIENCE_CALL_PITCH_SHARE`, all from a hash of the tick and the cluster count.
- A `day_only` ambience calls only while the daylight blend is above `AMBIENCE_DAYLIGHT_MINIMUM`. The first variant's flag speaks for all.
- The hum drifts by `HUM_DRIFT_SHARE` over `HUM_DRIFT_MINIMUM_TICKS` to `HUM_DRIFT_MAXIMUM_TICKS`.
- `tools/make_placeholder_sounds.py` (standard library only, deterministic) writes the placeholder files, mono at 22050 Hz, into `data/sounds/` or a directory given. The table is written by hand, and recorded sounds replace files one by one.

## Descriptions and notes

- Every item, machine and technology names a `description_key` (`describe_item_<id>` and so on, 0070). `test_shipped_descriptions_exist` keeps every shipped entry described.
- A description is one to three sentences in the venture's register ([DESIGN.md](../DESIGN.md), Lore and tone): what the thing is, what it does for the outpost, and one concrete fact, real (a formula, a melting point, an ore's metal content) or the game's own (a rate, a draw, a capacity).
- A game fact in a description copies a value in the data: changing the value means changing the text.
- A machine's item and the machine have two texts: what it is for (the recipe browser) and how it runs (the machine panel).
- Temperatures read "degrees Celsius": not every selectable font has a degree sign.
- Notes (`data/notes.sjson`, `notes.odin`) are the journal's world building, one unlock each, in the order their milestones come in play. Geology in a note is real geology (Mississippi Valley type lead and zinc, magmatic nickel with copper, lateritic bauxite), the rest is the venture.

## Tick cost baseline

The factory benchmark on the couch machine (Ryzen 7 2700X, headless, release build), 2026-09-28, in milliseconds per tick ([architecture.md](architecture.md), Performance).

| Size | Entities | Average | Worst |
| --- | --- | --- | --- |
| 1 | 321 | 0.026 | 0.046 |
| 4 | 1281 | 0.075 | 0.18 |
| 16 | 5121 | 0.27 | 0.77 |
| 64 | 20481 | 1.35 | 6.5 |

- Electric networks (`tick_electric_networks`) take the largest share at every size (22 to 29 percent), then inserters and fluids (about 20 percent each). At size 64 statistics grows to 20 percent.
