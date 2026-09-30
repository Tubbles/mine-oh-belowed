# Design overview

Mine oh Belowed is a factory game in a voxel world. This document holds the design intent: pillars, the world, the player, the phases, the systems, tone and art direction. How each system works is in [doc/](doc/README.md), and [doc/inspiration.md](doc/inspiration.md) records what we take from other games and why. This file should stay readable in one sitting.

## Pillars

1. The factory is the game. The loop is Factorio's: do it by hand once, build the machine that does it, then build the machine that feeds that machine. Time is spent on recipes, logistics and scale, above ground, in the factory.
2. Dig anywhere. The world is blocks and every one of them can be mined, placed or built on. Terrain is a canvas for the factory (foundations, floors, tunnels, dams) and a raw material (sand, clay, gravel). Digging is never required to reach ore.
3. Visible logistics only. Belts, ramps, lifts, inserters and pipes move everything. Nothing teleports. No bots, no storage network. Rails come later as more visible logistics.
4. Depth of recipes, not depth of tunnels. Many ores, alloys and intermediates, byproducts that must go somewhere, fluids in two phases, two routes to most things. All of it lives in data.
5. Couch first. Every interaction is designed for the Steam Controller from the start. Text entry is limited to naming things.
6. Peaceful. No enemies, no violence, no pollution in the first alpha. Failure is a stalled belt, never a death screen. It is not a children's game, it is a game that can be played while children watch, so nothing else is simplified for them.
7. One coherent game. One art style, one UI language, one rule set. No mod seams.

## The world

- The world is unbounded in every direction, depth included, and generated lazily around each player from the seed ([doc/architecture.md](doc/architecture.md), World generation).
- Terrain is varied at a walking scale: lowlands and raised masses, ridged ranges, terraced plateaus with cliffs, river valleys with beaches. Temperature (a latitude band, noise and height) and moisture pick the biome; the biomes, tree species and ground cover live in data ([doc/content.md](doc/content.md), World).
- Ore veins are reservoirs, not blocks. A vein holds a fixed amount of ore as a weighted mix of ore types plus spoils (gravel, sand), and shows on the surface as an outcrop. Hand mining the outcrop feeds the bootstrap without noticeably depleting the vein; drills anywhere on its footprint tap the reservoir, and several drills share one vein.
- Vein sizes follow the Manufactio scale: scatterings of a few thousand units, deposits of tens of thousands, concentrations of hundreds of thousands, richer and larger farther from spawn. The numbers live in data and a richness world setting multiplies them.
- Veins are finite (default) or infinite as a world setting. A finite vein exhausts to spent rock and its drills stop; a late game revival route (a drill supplied with mining fluid, at half rate and a cost per unit) means the world never runs dry, only expensive.
- Deep veins lie below the surface veins, richer and with the rarer ores, reached from the surface by bore drills in the late tiers, never by digging. Caves hold small rare deposits and schematic crates that unlock alternate recipes. Underground time is optional and meant to stay around a tenth of play.
- Tools gate hand mining (0051): every block has a tool tier and the best pickaxe carried must reach it, so the first pickaxe is a real goal. No speed bonus, no durability, and machines are not gated.
- Strata are topsoil, stone and deep stone. Dug blocks become items and the factory uses all of them, for glass, bricks, concrete and paving.
- Water flows, Minecraft style: sources spread and drain. Rivers and lakes are infinite for pumps. Digging under a lake floods the hole, a puzzle rather than a punishment. Flowing water is also a power source (hydro).
- Lighting is Minecraft style (sky light and block light), so nights and interiors need lamps. The day and night cycle is cosmetic in the alpha.
- Nothing falls. There are no gravity blocks.

## The player

- First person by default, with a third person camera as a toggle, because a console review of Satisfactory found first person placement harder than it needs to be ([doc/inspiration.md](doc/inspiration.md)). The player fits a one by two block gap, reaches five blocks, jumps one block, sneaks and sprints. Gyro aim gives fine pointing in both camera modes.
- Hand mining is fast, a second or a few per block.
- Inventory is a grid of 36 slots plus an 8 slot hotbar. The hotbar doubles as the radial menu on the left trackpad. A distribute gesture spreads the held stack evenly over several machines, because hand feeding is the whole early game.
- No health, hunger, weight or drowning.
- Flying and instant mining are developer tools. A double tap of Jump toggles flying, as in Minecraft Bedrock's creative mode, so every device flies without a trip through the pause menu (`doc/log/2026-09-29.md`); flight collides with blocks, and no clip is its own toggle.

## Gameplay phases

One long progression from bare hands to a rocket program. Each phase ends when the player feels the pain the next phase relieves, so automation arrives as relief, never as a lecture. Quests are chapters over these phases ([doc/quests.md](doc/quests.md)).

1. Arrival. You land with a small kit and a radio to Mission Control, the orbital station that sends requests and rewards, on flat ground with the first iron, copper and coal outcrops in sight of the pad. Punch trees, pick up stone, craft a pickaxe, dig a little. Learn dig, place, craft and the radial hotbar.
2. Hand fed workshop. Stone furnaces you feed coal by hand, burner drills you refuel by hand, ore carried in your pockets. The furnace goes cold while you are away. Nobody has to explain why belts exist.
3. First automation. A coal drill feeding its own belt, inserters, the first plate line that runs on its own, held at a rate. No quest makes the player wait: sustain windows are seconds.
4. Power. Pump, boiler, steam engine, poles. A lamp comes on. Electric drills and assemblers replace the burner ones, labs research the first technology. Fuel for the boilers is now a belt problem.
5. Intermediates and byproducts. Gears, circuits, several ores, crushing and washing, the first slag and the first recycler. The first rocket contract asks for circuits.
6. Fluids. Water networks with gravity, oil, refinery, plastics, gases, generators burning waste gas.
7. Scale. Several veins, bore drills, factory floors, grid management, production statistics as a daily tool, cave schematics for alternate recipes.
8. Rocket program. Launch pad and rocket parts as the big sink, regular shipments as the trade loop, infinite research.

Alpha 1 covers all eight phases ([PLAN.md](PLAN.md)).

## Prospecting

Surface veins show as outcrops, so the early game needs no tool. Each tool reveals one attribute (location, composition, size, depth), so the ladder complements itself instead of replacing itself.

1. Eyes. Outcrops on the ground, in cliff faces and cave walls; vegetation and soil colour hint at what lies below, as real prospectors start.
2. Geologist's hammer. Assays one vein on foot: its ore mix and size class, and marks its footprint on the map.
3. Magnetometer. Reads iron bearing veins at range, buried ones included, as haptics that grow stronger closer in. Location only, iron only.
4. Core sample drill. A powered machine that reports the strata and any vein below it, with composition and depth. Confirms one column.
5. Seismic survey. Thumper charges image deep veins over a wide area: location and shape, not composition. Consumes charges.
6. Orbital survey. Bought from the venture with a shipment: surface veins with size classes over a large radius. Late, expensive, and a reason to ship.

Rarer ores are tied to strata and biomes with plausible geology (gold in quartz veins in hills, sulfur near tar flats, bauxite under red soil), so knowing the world is prospecting too.

## Automation and logistics

Mechanisms: [doc/logistics.md](doc/logistics.md).

- Machines are multi block entities on a flat footprint. Footprints vary on purpose, odd shapes included: fitting a 3 by 2 boiler next to a 2 by 2 drill is part of the puzzle. Snapping and the rotation preview carry the gamepad ergonomics, not uniform sizes.
- Drills output what the vein holds, ore mix and spoils. Sorting and spoil disposal are the first logistics problems a drill creates, and spoil heaps are the visible cost of mining.
- Ore comes in two grades; low grade needs crushing and washing, and its share rises as a finite vein depletes, so the problem changes over the life of a vein.
- Outcrops under water or in a hillside are ordinary veins with a terrain problem attached: drain the lake, dam the river, or cut the platform.
- Belts are flat, ramps and lifts, two lanes each, simulated per belt line so thousands stay cheap. Underground and elevated belts are emergent: dig a tunnel or place a floor. Splitters have priority and filters.
- Inserters move items between belts, machines and chests in the horizontal plane; vertical movement is the lift's job.
- Pipes carry liquids and gases in one network model ([doc/fluids.md](doc/fluids.md)). Liquids run downhill for free and need pumps to climb; gases fill any connected volume. Pipe crossings are emergent: go over or under.
- Building uses ghost placement with rotation and snapping, pipette, and pick up of everything. Placed blocks are foundations, so multi floor factories cost nothing extra.

## Power

Power is part of the logistics puzzle from the alpha on ([doc/fluids.md](doc/fluids.md), Power). Boilers need fuel, which is a belt problem. Poles connect into networks, demand above supply browns out every machine on a network proportionally, and a power overview shows each network's supply, demand and biggest consumers. Later generators burn waste gas, turn in flowing water or take the sun. Power is never free.

## Recipes, byproducts and recycling

- Recipes take any number of inputs and produce any number of outputs, items or fluids. Byproducts are ordinary outputs.
- The byproduct rule: every byproduct has a use and a sink, and the sink costs something. Slag to gravel to concrete. Mud to clay to bricks. Waste gas to a generator or a flare. Bitumen to asphalt paving.
- The recycler turns any item back into a fraction of its ingredients. It is the universal sink and the fix for overproduction.
- The ore set is broad and lives in data: iron, copper, tin, lead, zinc, nickel, bauxite, gold, quartz, coal and oil, with bronze, brass and steel as the alloys and sulfur from chemistry ([doc/content.md](doc/content.md)).
- Plastics have two routes: fossil (oil, refinery, cracking, chemical plant) and renewable (wood to wood gas and charcoal in a gasifier, slower and land hungry).
- Most products have more than one route. Alternate recipes come from research or cave schematics and trade fewer byproducts, cheaper inputs, or a byproduct turned into a product.
- Byproduct strictness is a world setting: byproducts must be handled (default) or may be voided.
- Direction (user, 2026-09-27, to design after the play experience exists): byproducts grow past "the mineral you want and slag" into the companion and gangue minerals that occur together in reality, of little use at first, with later technologies that recirculate, concentrate or enrich them into products.

## Research, quests and rockets

- Three progression channels. Small steps are discovered: a recipe becomes available the first time all its ingredients have been obtained. Bigger steps are researched in labs with science packs. Massive steps come from a few main quest gates, about one per phase. The tree lives in data and ends in infinite research.
- Undiscovered recipes show as silhouettes, so a first playthrough never faces the whole tree at once. The world setting "all recipes unlocked at start" is for repeat playthroughs.
- Quests are data driven chapters over the phases and replace the tutorial. Mission Control is the voice. They only guide and reward: a player who ignores the journal is never blocked, and a gated technology waits for its main quest and for nothing else.
- Rockets close the loop in phase 8. Shipments fulfil contracts with soft deadlines (a late shipment pays less, nothing fails), in tiers opened by the number of rockets launched, and sell other cargo for venture credit, which buys rare materials and the orbital survey. No building is mandatory, the pad included.
- The ending is soft. After the first shipment the venture declares the outpost self sufficient in one message. Contracts and infinite research continue. There is no victory screen.

## Lore and tone

Realistic rather than cartoonish. The player is a contractor establishing an industrial outpost on an uninhabited planet for a venture that holds the planet's exploitation lease and stays in contact through Mission Control, its orbital station. The venture sets the contracts, the prices and the targets, and the cynical hand of capitalism is felt through its messages and its demands. Spoil heaps, spent veins and flare stacks are what the outpost does to the planet, and the game shows it without a pollution mechanic in the alpha. Materials, processes and machines carry their real names and real units: hematite and chalcopyrite, smelting and cracking, kilowatts and items per minute. The planet's geology is plausible. There are no aliens, no magic and no mascots. Humour lives in Mission Control's corporate messages, not in the world.

## Sound

Sparse, with a hard cap on simultaneous voices, so a large base is a hum rather than a choir. The visual layer (bottleneck overlay, HUD warnings) is the primary feedback and sound confirms it. Distinct sounds are reserved for state changes: a machine stopping, a brownout starting, a quest completing, a capsule landing. Nothing plays continuously but the biome ambience, the rain and one hum for the nearest working machine, one per machine family at most, never a synthesised tone per machine type. Birds and insects are short calls in clusters, and effects are short and never layered. Mechanism: [doc/presentation.md](doc/presentation.md), Sound.

## World settings

Chosen at world creation: seed, name, vein finiteness, vein richness (50, 100, 200 or 400 percent), research cost multiplier (the same steps), byproduct strictness (strict, where a machine whose byproduct output is full waits, or lenient, where byproducts that do not fit are voided and counted), all recipes unlocked at start, day length (5, 10, 20 or 40 minutes). `data/game.sjson` holds only the defaults for the new world screen.

## User interface

Mechanism: [doc/ui.md](doc/ui.md) and [doc/hud.md](doc/hud.md).

- 10 foot UI: readable from a couch at 1080p, large icons, little text.
- Two navigation styles, always both: focus navigation (d-pad or left stick) and pointer (right trackpad). Every screen works fully with either.
- Selection assist in the world: the reticle snaps to the nearest entity and the bumpers cycle overlapping candidates, because picking one entity among dense neighbours is the known weak spot of factory games on a pad.
- The recipe browser is a graph: for any item what makes it, what uses it, and where its byproducts go. No search box.
- Built in information: a rate on every machine panel, a bottleneck overlay, production statistics, a power overview.
- Text entry (world name) uses an on-screen keyboard driven by the trackpads. A physical keyboard or the phone's keyboard works too.
- Tooltips are panels that open on a button, never hover only.

## Editors

The game carries its own editors (user, 2026-09-28): the model is the Warcraft 3 world editor, and the long term aim is making one's own maps in the game. Every tunable presentation or generation parameter is data with an in-game editor in developer mode, applied on the fly, with a save that hands the chosen values to an agent so they become the new defaults. Editors are screens like any other, gamepad first. The Data files screen is the fallback editor for everything without one of its own ([doc/developer_tools.md](doc/developer_tools.md)).

## Input

Steam Controller (2026) first ([doc/input.md](doc/input.md), with the technical path decided in `doc/log/2026-09-26.md`). Touch is a first class input beside the gamepad and the pointer: on a touch screen the game draws its own virtual gamepad with gestures over the whole screen, instead of GameNative's button layout (0134), feeding the same gamepad state as the physical devices, and in menus a finger is the pointer ([doc/touch_overlay.md](doc/touch_overlay.md)).

## Art direction

Placeholder art first. The intermediate target after placeholders is Minecraft flatness: small textures, flat shading, per vertex light and ambient occlusion, achievable without an artist. Realism is carried by the lore and the numbers, not the rendering. Machines are voxel models scaled to their footprint, and a machine's moving part moves and its glow lights only while it works, so a glance shows its state. Textures are generated by the game from parameters in data wherever the look allows, not painted. The default typeface is Exo 2, a geometric technical face chosen for the theme. Mechanism: [doc/presentation.md](doc/presentation.md).

## No perceivable repetition

A major principle (user, 2026-09-28): people are very sensitive to patterns where there should be none. Anything made for human perception, sound, animation or imagery, must not repeat at a period the player can feel, and must not stripe or tile visibly at a larger scale than the thing itself.

- A texture that tiles must not produce rows or diagonals across a field of one block: it is isotropic, or a variation per block breaks the repetition, or both ([doc/presentation.md](doc/presentation.md), Per block variation).
- A sound that recurs (birds, insects, steps) plays in short clusters with long and varying pauses and a varied pitch, never on a fixed period; a looping sound drifts a little in volume.
- An animation cadence (the head bob, the footsteps, the mining chop) follows the world (distance walked, work done) at a natural rate and does not speed up with a developer cheat.

Every new sound, animation and texture is checked against this before it lands.

## Technical

Targets: the couch machine at 1080p with the Steam Controller, the Steam Deck at 1280 by 800 with its built in controls (user, 2026-09-27), and an Android phone, as a native app and through GameNative running the Windows build ([doc/build.md](doc/build.md), [doc/android.md](doc/android.md)). Every rendering feature is budgeted for the Deck's APU and sits behind a setting when it costs. The simulation is deterministic, fixed step and decoupled from rendering, and holds an array of players from the start, so local co-op later needs no redesign ([doc/architecture.md](doc/architecture.md)).

## Out of scope for alpha 1

Enemies, pollution, combat, health and hunger, gravity blocks, multiplayer, rails, blueprints of built areas, polished Xbox-style controller support, achievements, localisation.

## Open questions

Listed with recommendations in [SUGGESTIONS.md](SUGGESTIONS.md).
