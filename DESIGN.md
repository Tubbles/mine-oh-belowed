# Design overview

Mine oh Belowed is a factory game in a voxel world. This document is the map. Details live in [doc/](doc/README.md), and [doc/inspiration.md](doc/inspiration.md) records what we take from other games and why. This file should stay readable in one sitting.

## Pillars

1. The factory is the game. The loop is Factorio's: do it by hand once, build the machine that does it, then build the machine that feeds that machine. Time is spent on recipes, logistics and scale, above ground, in the factory.
2. Dig anywhere. The world is blocks and every one of them can be mined, placed or built on. Terrain is a canvas for the factory (foundations, floors, tunnels, dams) and a raw material (sand, clay, gravel). Digging is never required to reach ore.
3. Visible logistics only. Belts, ramps, lifts, inserters and pipes move everything. Nothing teleports. No bots, no storage network. Rails come later as more visible logistics.
4. Depth of recipes, not depth of tunnels. Many ores, alloys and intermediates, byproducts that must go somewhere, fluids in two phases, two routes to most things. All of it lives in data.
5. Couch first. Every interaction is designed for the Steam Controller from the start. Text entry is limited to naming things.
6. Peaceful. No enemies, no violence, no pollution in the first alpha. Failure is a stalled belt, never a death screen. It is not a children's game, it is a game that can be played while children watch, so nothing else is simplified for them.
7. One coherent game. One art style, one UI language, one rule set. No mod seams.

## The world

- Blocks are one metre cubes stored in cubic chunks of 32 by 32 by 32, generated lazily around each player. The world is unbounded in every direction, depth included, so there is no world height constant.
- Procedural generation uses layered OpenSimplex noise for height and moisture, a small set of biomes (plains, forest, hills, desert, lake, tar flats), trees, boulders, rivers and lakes, and caves.
- Ore veins are reservoirs, not blocks. A vein is a region holding a fixed amount of ore, a weighted mix of ore types plus spoils such as gravel and sand, and it shows on the surface as an outcrop of ore textured blocks. Hand mining the outcrop yields ore for the bootstrap without noticeably depleting the vein. A drill placed anywhere on the outcrop taps the reservoir, and several drills share one vein. When a finite vein is exhausted the outcrop turns to spent rock and its drills stop.
- Vein sizes follow the Manufactio scale: common scatterings of a few thousand units, regular deposits of tens of thousands, rare concentrations of hundreds of thousands, richer and larger farther from spawn. The numbers live in data and a richness world setting multiplies them.
- Vein finiteness is a world setting: finite (default) or infinite. The finite default also gets a late game revival route: an electric or bore drill supplied with mining fluid keeps an exhausted vein producing at half rate and at a cost per unit, so the world never runs dry, only expensive.
- Deep veins lie below the surface veins, richer and with the rarer ores. They are reached from the surface by bore drills in the late tiers, never by digging. Caves hold small rare deposits (gold quartz) and schematic crates for players who like to explore: a schematic read from the hotbar unlocks one alternate recipe through the schematic channel, and machines only make an alternate once it is found. Underground time is optional and meant to stay around a tenth of play.
- Tools gate hand mining (user decision 2026-09-27): every block has a tool tier and the best pickaxe carried must reach it, so the first pickaxe is a real first goal. No speed bonus, no durability, and machines are not gated.
- Prospecting is its own tool tier ladder, and the tools complement each other because each reveals a different attribute (location, composition, size, depth). See the prospecting section below.
- Strata are topsoil, stone and deep stone. Dug blocks become items (dirt, sand, clay, gravel, stone) and the factory uses all of them, for glass, bricks, concrete and paving. Terrain is a raw material.
- Water flows, Minecraft style: source blocks spread into neighbouring air and drain when the source is removed. Rivers and lakes are infinite for pumps. Digging under a lake floods the hole, which is a puzzle rather than a punishment, since nothing hurts the player. Flowing water is also a power source later (hydro turbines, dams).
- Lighting is Minecraft style: 16 level sky light and block light propagation, so nights and interiors need lamps. The day and night cycle is cosmetic in alpha.
- Nothing falls. There are no gravity blocks.

## The player

- First person by default, with a third person camera as a toggle. The player is one block wide and two blocks tall, reaches five blocks, jumps one block, sneaks and sprints. Gyro aim gives fine pointing for block placement in both camera modes.
- Hand mining is fast: one to three seconds per block by hand. Tools multiply mining speed. Whether tools also gate anything is open (see [SUGGESTIONS.md](SUGGESTIONS.md)).
- Inventory is a grid of 36 slots plus an 8 slot hotbar. The hotbar doubles as the radial menu on the left trackpad. A distribute gesture spreads the held stack evenly over several machines, because hand feeding is the whole early game.
- No health, hunger, weight or drowning.
- A flying and instant mining toggle exists as a developer and creative tool.

## Gameplay phases

One long progression from bare hands to a rocket program. Each phase ends when the player feels the pain the next phase relieves, so automation arrives as relief, never as a lecture. Quests are chapters over these phases.

1. Arrival. You land with a small kit and a radio to Mission Control, the orbital station that sends requests and rewards, on flat ground with the first iron, copper and coal outcrops in sight of the pad. Punch trees, pick up stone, craft a pickaxe, dig a little. Learn dig, place, craft and the radial hotbar.
2. Hand fed workshop. Stone furnaces you feed coal by hand, burner drills you refuel by hand, ore carried in your pockets. The quest asks for fifty plates. The furnace goes cold while you are away. Nobody has to explain why belts exist.
3. First automation. A coal drill feeding its own belt, inserters, the first unattended plate line. Quest: five minutes without touching it.
4. Power. Pump, boiler, steam engine, poles. A lamp comes on. Electric drills and assemblers replace the burner ones, labs research the first technology. Fuel for the boilers is now a belt problem.
5. Intermediates and byproducts. Gears, circuits, several ores, crushing and washing, the first slag and the first recycler. The first rocket contract asks for circuits.
6. Fluids. Water networks with gravity, oil, refinery, plastics, gases, generators burning waste gas.
7. Scale. Several veins, bore drills, factory floors, grid management, production statistics as a daily tool, cave schematics for alternate recipes.
8. Rocket program. Launch pad and rocket parts as the big sink, regular shipments as the trade loop, infinite research.

Alpha 1 covers all eight phases. Couch tests along the way let the core loop be played long before that, see [PLAN.md](PLAN.md).

## Prospecting

Surface veins show as outcrops, so the early game needs no tool. Everything below is data, and each tool reveals one attribute, so the ladder complements itself instead of replacing itself.

1. Eyes. Outcrops on the ground, in cliff faces and cave walls. Vegetation and soil colour hint at what lies below (sparse grass over copper, red soil over bauxite), which is how real prospectors start.
2. Geologist's hammer. Strike an outcrop block to assay the vein: its ore mix and its size class (scattering, deposit, concentration). The assay marks the vein's footprint on the map. One vein at a time, on foot.
3. Magnetometer. A handheld that reads iron bearing veins at range, including buried ones, through the trackpad haptics: the pad buzzes harder the closer you get. Location only, iron only.
4. Core sample drill. A powered machine that drills a core over time and reports the strata and any vein below its position, with composition and depth. Confirms one column, finds deep veins where you already suspect them.
5. Seismic survey. Thumper charges placed in a pattern, each shot images a radius, several shots together outline deep veins over a wide area on the map. Location and shape of deep veins, not their composition. Consumes charges. (0038 draws each shot's veins as their true circles; a coarser outline for unresolved veins is a follow up.)
6. Orbital survey. Bought from the venture with a shipment: one satellite pass reveals surface veins with size classes over a large radius. Late, expensive, and a reason to ship.

Rarer ores are tied to strata and biomes with plausible geology (gold in quartz veins in hills, sulfur near tar flats, bauxite under red laterite soil), so knowing the world is prospecting too.

## Automation and logistics

- Machines are multi block entities placed on a flat footprint. Footprints are defined in data and vary on purpose, odd shapes included: fitting a 3 by 2 boiler next to a 2 by 2 drill is part of the puzzle. Snapping and the rotation preview carry the gamepad ergonomics, not uniform sizes.
- Drills tap the vein reservoir under their outcrop. Drill tiers raise the rate and the power draw. Bore drills reach deep veins and revive exhausted ones.
- Drills output what the vein holds: the ore mix and the spoils (gravel, sand, mud). Sorting and spoil disposal are the first logistics problems a drill creates, and spoil heaps are the visible cost of mining.
- Ore comes in two grades. High grade ore smelts directly, low grade ore needs crushing and washing first, and the share of low grade rises as a finite vein depletes. The problem changes over the life of a vein.
- Outcrops under water or in a hillside are ordinary veins with a terrain problem attached: drain the lake, dam the river, or cut the platform. Flowing water and dig anywhere exist for this.
- Belts come in three shapes: flat, ramp (one block of rise per block of run) and lift (a vertical belt block that stacks). Two lanes per belt, as in Factorio. Splitters with priority and filters. Items on belts are simulated per belt line, not as individual entities, so thousands of belts stay cheap. Underground and elevated belts are emergent: dig a tunnel or place a floor.
- Inserters reach one block in four horizontal directions and move items between belts, machines and chests. Filter inserters exist. Vertical movement is the lift's job.
- Pipes connect in six directions and carry liquids and gases in one network model with a phase per fluid. Liquids obey gravity: they run downhill for free and need pumps to climb. Gases fill any connected volume regardless of height. Tanks, overflow and top up valves, powered pumps. Pipe crossings are emergent: go over or under.
- Building uses ghost placement with rotation and a snapping preview, so a 3 by 3 machine can be placed flush against a belt with a stick. Pipette picks the block or entity under the cursor. Everything can be picked up again. Placed blocks are foundations, so multi floor factories cost nothing extra.

## Power

Power is part of the logistics puzzle from the alpha on. Boilers need fuel, which is a belt problem. Steam engines make electricity. Poles have a supply volume and connect automatically to poles in reach, connected poles form one network, and demand above supply browns out every machine on the network proportionally. A power switch splits networks. The power overview screen shows each network's supply, demand and biggest consumers. Later generators: combustion generators burning waste gas or wood gas, hydro turbines in flowing water, solar. Power is never free.

## Recipes, byproducts and recycling

- Recipes take any number of inputs and produce any number of outputs, each an item or a fluid. Byproducts are ordinary outputs.
- The byproduct rule: every byproduct has a use and a sink, and the sink costs something. Slag to gravel to concrete blocks. Mud to clay to bricks. Waste gas to a generator or a flare. Bitumen to asphalt paving.
- The recycler turns any item back into a fraction of its ingredients. It is the universal sink and the fix for overproduction.
- Ore processing: crushing and washing raise the yield per ore and create spoils.
- The ore set grows in data. Alpha: iron, copper, tin, coal, stone, sand, wood. Later: lead, zinc, nickel, bauxite, gold, quartz, sulfur, oil from tar flats and deep wells. Alloys: bronze and steel in alpha, brass and more later.
- Plastics have two routes. Fossil: oil from tar flats early and bore drills later, refinery into gas, light and heavy fractions, cracking of the heavier fractions towards gas, and a chemical plant making plastic from gas and coal, sulfur from gas and water, and bitumen from heavy oil, with bitumen becoming asphalt paving blocks. Renewable: wood to wood gas and charcoal in a gasifier, syngas plastic in the chemical plant, slower and land hungry with tree farms and automated harvesters.
- Most products have more than one route. Alternate recipes come from research or from cave schematics and trade fewer byproducts, cheaper inputs, or a byproduct turned into a product.
- Byproduct strictness is a world setting: byproducts must be handled (default) or may be voided.
- Direction (user, 2026-09-27, to design after the play experience exists): byproducts grow past "the mineral you want and slag" into the minerals that occur together in reality, companion and gangue minerals of little use at first, with later technologies that recirculate, concentrate or enrich them into products.

## Research, quests and rockets

- Three progression channels. Small steps are discovered: a recipe becomes available the first time all of its ingredients have been obtained by a player. Bigger steps are researched: labs consume science packs (coloured bottles, the abstraction is good) to unlock machine tiers and new processes such as electrolysis, cracking and fracking. Massive steps come from a few main quest gates. In the data every recipe carries its channel: start, discovery, research with a technology id, or quest. The tree lives in data and ends in infinite research.
- Undiscovered recipes show in the recipe graph as silhouettes: name and category visible, ingredients revealed on discovery. A first playthrough is never faced with the whole tree at once. The world setting "all recipes unlocked at start" is there for repeat playthroughs.
- Quests are data driven chapters over the gameplay phases. Objectives: craft, place, sustain a rate, research, ship. Contextual hints ("your drill ran out of fuel three times"). Rewards: items, unlocks, schematics. Mission Control is the voice. Quests replace the tutorial. They only ever guide and reward, a player who ignores the journal is never blocked.
- A few main quest gates open the massive steps, on the order of one per gameplay phase, never hundreds of small ones. A gated technology waits for its main quest and for nothing else, and no other path waits for it.
- Rockets close the loop in phase 8. A launch pad and rocket parts are the big sink. Shipments fulfil contracts and trade for returns. Contracts carry soft deadlines: a late shipment pays less, nothing fails. Contracts come in tiers opened by the number of rockets launched, and cargo no contract takes is sold for venture credit, which buys returns from a small catalogue: rare materials and the orbital survey. No building is mandatory, the pad included.
- The ending is soft. After the first shipment the venture declares the outpost self sufficient in one message. Contracts and infinite research continue. There is no victory screen.

## Lore and tone

Realistic rather than cartoonish. The player is a contractor establishing an industrial outpost on an uninhabited planet for a venture that holds the planet's exploitation lease and stays in contact through Mission Control, its orbital station. The venture sets the contracts, the prices and the targets, and the cynical hand of capitalism is felt through its messages and its demands. Spoil heaps, spent veins and flare stacks are what the outpost does to the planet, and the game shows it without a pollution mechanic in the alpha. Materials, processes and machines carry their real names and real units: hematite and chalcopyrite, smelting and cracking, kilowatts and items per minute. The planet's geology is plausible. There are no aliens, no magic and no mascots. Humour lives in Mission Control's corporate messages, not in the world.

## Sound

Sparse. A handful of quiet, positional machine loops with a hard cap on simultaneous voices, so a large base is a hum rather than a choir. Distinct sounds are reserved for state changes: a machine stopping, a brownout starting, a quest completing, a capsule landing. The visual layer (bottleneck overlay, HUD warnings) is the primary feedback and sound only confirms it. In the placeholder era that means one hum, a few soft clicks, or silence. No synthesised tone per machine type.

## World settings

Chosen at world creation: seed, name, vein finiteness, vein richness (50, 100, 200 or 400 percent), research cost multiplier (the same steps), byproduct strictness (strict: a machine whose byproduct output is full waits; lenient: byproducts that do not fit are voided and counted), all recipes unlocked at start, day length (5, 10, 20 or 40 minutes). `data/game.sjson` holds only the defaults for the new world screen.

## User interface

- 10 foot UI: readable from a couch at 1080p, large icons, little text.
- Two navigation styles, always both: focus navigation (d-pad or left stick moves a highlight) and pointer (right trackpad moves a cursor). Every screen works fully with either. Bumpers switch tabs, B goes back, Y opens the info panel, the left pad opens a letter or category wheel on any list.
- Selection assist in the world: the reticle snaps to the nearest entity in the aim direction and bumpers cycle overlapping candidates, because picking one entity among dense neighbours is the known weak spot of factory games on a pad.
- The recipe browser is a graph: categories, tags, "can craft now", and for any item what makes it, what uses it, and where its byproducts go. No search box.
- Built in information: a rate readout on every machine panel, a bottleneck overlay, production statistics, a power overview.
- Screens: title and world setup, settings, HUD (hotbar, held item, what you look at, current objective, warnings, button glyph bar, compass strip), inventory with hand crafting queue, recipe browser, machine panels, technology tree, quest journal, production statistics, power overview, top down map, build overlay, launch pad (post alpha), pause menu, on-screen keyboard, toasts, debug overlay.
- Text entry (world name, player name) uses an on-screen keyboard driven by the trackpads. A physical keyboard works too when present.
- Tooltips are panels that open on a button, never hover only.

## Input

Steam Controller (2026) first. The layout proposal and the technical path are in [doc/input.md](doc/input.md).

## Art direction

Placeholder art first. The intermediate target after placeholders is Minecraft flatness: small textures, flat shading, per vertex light and ambient occlusion. That fixes the texture atlas, the lighting model and the shaders for M1 and it is achievable without an artist. Realism is carried by the lore and the numbers, not the rendering.

## Technical

Targets: the couch machine at 1080p with the Steam Controller, and the Steam Deck at 1280 by 800 with its built in controls (user, 2026-09-27); every rendering feature is budgeted for the Deck's APU and sits behind a setting when it costs. Odin with raylib for windowing and rendering and SDL3 for controller input. Deterministic fixed step simulation decoupled from rendering, typed entity pools, data driven prototypes in SJSON. The simulation holds an array of players from the start, so local co-op later needs no redesign. See [doc/architecture.md](doc/architecture.md).

## Out of scope for alpha 1

Enemies, pollution, combat, health and hunger, gravity blocks, multiplayer, rails, blueprints, polished Xbox-style controller support, achievements, localisation.

## Open questions

Listed with recommendations in [SUGGESTIONS.md](SUGGESTIONS.md).
