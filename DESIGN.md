# Design overview

Mine oh Belowed is a factory game on the smooth voxel planets of one procedurally generated star system. This document holds the design intent: pillars, the world, the player, building, the phases, the systems, space, tone and art direction. How each system works is in [doc/](doc/README.md), [doc/inspiration.md](doc/inspiration.md) records what we take from other games and why, and the decisions that reshaped this document on 2026-10-02 are in `doc/log/2026-10-02.md`. This file should stay readable in one sitting.

## Pillars

1. The factory is the game. The loop is Factorio's: do it by hand once, build the machine that does it, then build the machine that feeds that machine. It carries into orbit: every ship, station, satellite and terraforming plant is fed by production lines, so space is the factory's next customer, never a space game bolted on.
2. Dig anywhere. The terrain is a smooth field and every part of it can be dug away or raised, by hand, by drill or by explosives. Terrain is a canvas for the factory (foundations, tunnels, dams) and a raw material (stone, sand, clay). Digging is never required to reach ore.
3. Visible logistics only. Belts, arms, pipes, poles, rockets and ships move everything, and all of it is seen moving. Nothing teleports. No logistics bots, no storage network. Rails come later as more visible logistics.
4. Depth of recipes, not depth of tunnels. Many ores, alloys and intermediates, byproducts that must go somewhere, fluids in two phases, two routes to most things, and every new location in the system brings material found nowhere else. All of it lives in data.
5. Couch first. Every interaction is designed for the Steam Controller from the start, up to four players share one screen, and text entry is limited to naming things.
6. Peaceful by default, survival by choice. No enemies, no violence, no pollution. Peaceful has no stats at all and failure is a stalled belt. Survival adds health, hunger, oxygen and the suit's battery and allows death, shown as a quiet tinted screen and never gore. It is not a children's game, it is a game that can be played while children watch, so nothing else is simplified for them.
7. One coherent game. One art style, one UI language, one rule set from the ground to orbit, one world for every player in it. No mod seams.
8. No perceivable repetition (its own section below).

## The world

- One star system, six to ten planets with zero to ten moons each and one or two asteroid belts, generated from the seed. The generator fills a fixed list of roles from pools, so a seed is never unplayable: the home world (temperate, the full early ore set, two biome families), the first hop (a moon reached with the small ship), the ore world, the gas source (a gas giant whose moons are the bases), the second living world, the deep world (lava or high gravity, the core ores), the ice world, the belts. Each role brings a mechanic or a resource branch, never only colours, and every location holds at least one material found nowhere else.
- Each planet is a true sphere. Gravity points at the centre and every entity's up follows it continuously; the planet's gravity and shape are constant however much is mined. Radius, gravity, bedrock depth, cost to orbit, atmosphere, rotation and palette are values of the planet's record in data, never constants.
- The terrain is smooth voxels: a density field with a material per sample on a 3D grid, meshed into a soft sculpted surface, so there is no staircase, no seam and no corner, and a planet is a sphere at any radius. The sample spacing is a world setting between a third of a metre and one metre. Digging lowers the field in a brush and yields material by volume, a cubic metre per item whatever the spacing; placing raises it. The world is generated lazily from the seed with saved deltas, so a large planet costs storage only where someone digs.
- Terrain is varied at a walking scale: lowlands and raised masses, ridged ranges, terraced plateaus with cliffs, river valleys with beaches. Temperature and moisture pick the biome; the biomes, plant species and ground cover live in data and draw from pools with the planet's palette.
- Ore veins are reservoirs, not voxels. A vein holds a fixed amount of ore as a weighted mix of ore types plus spoils and shows on the surface as an outcrop of ore textured ground. Hand mining the outcrop feeds the bootstrap; drills anywhere on its footprint tap the reservoir, and several drills share one vein. Sizes follow the Manufactio scale, richer and larger farther from the pod; a richness world setting multiplies them; veins are finite (default) or infinite as a world setting, with a late revival route so the world never runs dry, only expensive.
- Deep veins lie below the surface veins, richer and with the rarer ores, reached by bore drills, never by digging. Caves hold small rare deposits and schematic crates. Underground time is optional and meant to stay around a tenth of play.
- Tools gate hand mining: every material has a tool tier and the best pickaxe carried must reach it, so the first pickaxe is a real goal. No speed bonus, no durability, and machines are not gated.
- Every natural material carries the tint of the place it was dug: tints never stack with each other in the inventory, the tint stays when the material is placed again, and every recipe counts all tints of a material as one. Filters carry an "accept all tints" toggle, on by default.
- Water is a second field beside the terrain, a fill fraction per sample moved by a cellular rule towards the planet's centre and meshed smooth. Volume is conserved: a breached dam empties its reservoir, a pump empties a pond, a dug lake floor lowers the lake. The sea at its level, springs at river heads and rain into basins are infinite sources, so the sea and rivers never run dry for pumps and a pond holds what it holds. Flowing water is also a power source (hydro). Digging under a lake floods the hole, a puzzle rather than a punishment.
- Light propagates through the field, so caves and halls are black until lit and lamps stay a product. Sources are generous: a torch lights a room, a lamp a hall, with a falloff gentle near the source and steep only at the edge, values in data. Sky light is the second channel. Point lights come on top for working parts and never replace the field's light.
- One day length for every planet and one clock shared by everyone. The sun moves across each planet's sky from that clock and the far side is night. When every player sleeps, eight hours pass. Weather is per planet in data, one texture and at most one mechanic per kind, never damage: rain fills the water sources, dust storms ground flights, wind varies the turbines, cold and heat drain the suit in survival.
- Nothing falls. The terrain is a field, there are no gravity blocks.

## The player

- First person by default, with a third person camera as a toggle, because a console review of Satisfactory found first person placement harder than it needs to be ([doc/inspiration.md](doc/inspiration.md)). Gyro aim gives fine pointing in both camera modes.
- Smooth ground has slopes instead of steps. Slopes slow the walk and slide the player back past a walkable angle of about 40 degrees, a value in data; ledges of one sample are stepped over; the jump is about a metre with a mantle onto ledges to about one and a half; the tool reaches a few metres, and raising the ground underfoot replaces pillaring up. Fall damage exists in survival only.
- Hand mining is fast, a second or a few per cubic metre.
- Inventory is a grid of 36 slots plus an 8 slot hotbar. The hotbar doubles as the radial menu on the left trackpad. A distribute gesture spreads the held stack evenly over several machines, because hand feeding is the whole early game.
- The suit is four tanks and nothing else: oxygen, battery (heater and lights), propellant for the jet pack and, in survival, the food carried. Peaceful has none of them. The starter planet's air is not breathable, so in survival oxygen is a stat from the first minute, refilled at the pod and at any base with an oxygen generator, at a ship's suit up room and at a station's airlock, and carried as canisters. A tank at zero is a slow drain of health, never an instant death.
- Death and loss are never gory: a tinted screen with a quiet word, then an immediate respawn at the pod or the bed. Whether the inventory comes along is a per save setting; otherwise the death site keeps it as a marked pack, and a wreck keeps a ship's cargo, for a salvage trip that recovers everything. A respawn action in the menu brings a stuck player home in every mode.
- Flying and instant mining are developer tools. A double tap of Jump toggles flying, as in Minecraft Bedrock's creative mode, so every device flies without a trip through the pause menu (`doc/log/2026-09-29.md`); flight collides with the terrain, and no clip is its own toggle. Creative mode turns these into a play mode.

## Building

- A factory needs a grid, so the grid is local. A foundation placed on the ground defines a frame, up along local gravity and any yaw, and everything snapped to it shares that grid: more foundations, machines, belts, arms, pipes, poles, walls. A frame never re-tangents: it is one flat plane however far it extends, so a long platform leaves the ground at its edges or cuts in, and the player bridges with supports or starts a new island. The grid pitch is 0.5 m, a value in data.
- Machines are meshes at real sizes placed on frames with footprints that vary on purpose; snapping and the rotation preview carry the gamepad ergonomics. Inserters are big industrial arms with an elbow and a folded resting pose that reach 2 m when unfolded, a value in data.
- Belts and pipes between foundation islands run on freely placed poles, and the run between two poles is a curve the game derives from the poles' positions and facings, Satisfactory's way: the player places poles and never draws a curve. The simulation does not notice the shape, an item is a distance along the belt.
- An enclosed volume of floors, walls and hatches is a sealed room that holds air from an oxygen generator and leaks a little; an unsealed room is entered in the suit. Sealed rooms and greenhouse domes are the first breathable zones and carry a simple farming mechanic. No breaches, no fires, no pressure physics.
- Tools that remove volume (brushes of several sizes, explosives) and a platform mode that lays foundations in a flat view, one layer at a time, come with the field.

## Gameplay phases

One long progression from bare hands to a star system. The starter planet is the first third of the game and the system the other two thirds. Each phase ends when the player feels the pain the next phase relieves, so automation arrives as relief, never as a lecture. Quests are chapters over the first third ([doc/quests.md](doc/quests.md)); from the first flight on, the venture's contracts carry the game.

1. Arrival. The pod lands on the unbreathable starter planet with an infinite water reserve feeding its oxygen generator, solar panels and batteries that last the night, a bed, and the first iron, copper and coal outcrops in sight. Dig, place, craft and the radial hotbar. In survival the suit is the clock from the first minute.
2. Hand fed workshop. Stone furnaces fed by hand, burner drills refuelled by hand, ore carried in pockets. The furnace goes cold while you are away.
3. First automation. A coal drill feeding its own belt, arms, the first plate line that runs on its own.
4. Power. Pump, boiler, steam engine, poles. A lamp comes on. Electric drills and assemblers, labs and the first research. The first breakdowns, and the repair kit.
5. Intermediates and byproducts. Gears, circuits, several ores, crushing and washing, slag and the recycler. The first comms satellite goes up on solid fuel and the contract board opens.
6. Fluids. Water networks with gravity, oil, refinery, plastics, gases, generators burning waste gas, electrolysis for oxygen and hydrogen. The first sealed dome and the first crops.
7. Scale. Several veins, bore drills, factory floors, statistics as a daily tool, cave schematics, the terraforming branch begun. The rocket program: pad, rocket fuel, the first capsule to low orbit, which stays as the station's seed.
8. Low orbit. The outpost built by hand from lifted material around the capsule, the suit and the jet pack, the return pod, the first repairs of the venture's rare derelicts. The main quest ends here.
9. The first hop. The dock and the small ship built in its cage, the moon with its own material, oxygen as the clock, landings that may be one way.
10. The system. New bases on the ore world and the gas giant's moons, hauling by hand until logistics rockets and the hauler take over, the asteroid belt from a hand drill to automatic miners, comms relays reaching further, the survey satellite.
11. The yard. Hydrogen, orbital refining of belt ore, medium and large ships, the deep world's explosives and core ores, the second living world, terraforming to a breathable home world, signals between planets and the programmable processor. Contracts and infinite research never end.

## Prospecting

Surface veins show as outcrops, so the early game needs no tool. Each tool reveals one attribute (location, composition, size, depth), so the ladder complements itself instead of replacing itself, and a new planet starts blank and is read the same way.

1. Eyes. Outcrops on the ground, in cliff faces and cave walls; vegetation and soil colour hint at what lies below.
2. Geologist's hammer. Assays one vein on foot: its ore mix and size class, and marks its footprint on the map.
3. Magnetometer. Reads iron bearing veins at range, buried ones included, as haptics that grow stronger closer in.
4. Core sample drill. A powered machine that reports the strata and any vein below it, with composition and depth.
5. Seismic survey. Thumper charges image deep veins over a wide area: location and shape, not composition.
6. Survey satellite. Built or repaired and put in orbit, it maps a planet's surface veins with size classes over its orbits, and its data arrives through the comms network.

Rarer ores are tied to strata, biomes and planet roles with plausible geology, so knowing the system is prospecting too. The globe map carries the explored skin, bases, veins, wrecks and the station's orbit, and is the landing picker.

## Automation and logistics

Mechanisms: [doc/logistics.md](doc/logistics.md).

- Drills output what the vein holds, ore mix and spoils. Sorting and spoil disposal are the first logistics problems a drill creates, and spoil heaps are the visible cost of mining.
- Ore comes in two grades; low grade needs crushing and washing, and its share rises as a finite vein depletes, so the problem changes over the life of a vein.
- Outcrops under water or in a hillside are ordinary veins with a terrain problem attached: drain the lake, dam the river, or cut the platform.
- Belts have two lanes and are simulated per belt line so thousands stay cheap. Splitters have priority and filters. Arms move items between belts, machines and chests.
- Pipes carry liquids and gases in one network model ([doc/fluids.md](doc/fluids.md)). Liquids run downhill for free and need pumps to climb; gases fill any connected volume.
- Building uses ghost placement with rotation and snapping, pipette, and pick up of everything.
- Things break. The player's own machines fail at random but seldom, a rate per machine class in data drawn from the seeded tick; a broken machine stops, its glow goes out and a flag shows on it and on the map. The repair is a trip out with a repair kit; later technology brings semi automatic repair drones that patrol a base from a dock. A breakdown is one more way a belt stalls.
- Down the line, a signal network in the spirit of Factorio's circuit network: named values on wires or on the pole network that machines read to switch and to set filters, carried between planets over the comms network, and a processor machine programmed in a visual block language like Scratch on a gamepad, running on an integer virtual machine with a bounded number of steps per tick.

## Power

Power is part of the logistics puzzle from the alpha on ([doc/fluids.md](doc/fluids.md), Power). Boilers need fuel, which is a belt problem. Poles connect into networks, demand above supply browns out every machine on a network proportionally, and a power overview shows each network's supply, demand and biggest consumers. Later generators burn waste gas, turn in flowing water, take the sun or the wind. The pod's panels and batteries are the first network, and a station's solar wings see a night each orbit, so its batteries matter from the first room. Power is never free.

## Recipes, byproducts and recycling

- Recipes take any number of inputs and produce any number of outputs, items or fluids. Byproducts are ordinary outputs.
- The byproduct rule: every byproduct has a use and a sink, and the sink costs something. Slag to gravel to concrete. Mud to clay to bricks. Waste gas to a generator or a flare. Bitumen to asphalt paving.
- The recycler turns any item back into a fraction of its ingredients. It is the universal sink and the fix for overproduction.
- The ore set is broad and lives in data: iron, copper, tin, lead, zinc, nickel, bauxite, gold, quartz, coal and oil, with bronze, brass and steel as the alloys and sulfur from chemistry ([doc/content.md](doc/content.md)); the system's roles add ores, gases, ices and biological products found on one body only.
- Plastics have two routes: fossil (oil, refinery, cracking, chemical plant) and renewable (wood to wood gas and charcoal in a gasifier, slower and land hungry).
- Most products have more than one route. Alternate recipes come from research or cave schematics and trade fewer byproducts, cheaper inputs, or a byproduct turned into a product.
- Byproduct strictness is a world setting: byproducts must be handled (default) or may be voided.
- Direction (user, 2026-09-27, to design after the play experience exists): byproducts grow past "the mineral you want and slag" into the companion and gangue minerals that occur together in reality, of little use at first, with later technologies that recirculate, concentrate or enrich them into products.

## Research, quests, contracts and rockets

- Three progression channels. Small steps are discovered: a recipe becomes available the first time all its ingredients have been obtained. Bigger steps are researched in labs with science packs. Massive steps come from a few main quest gates in the first third and from contracts after it. The tree lives in data and ends in infinite research.
- Undiscovered recipes show as silhouettes, so a first playthrough never faces the whole tree at once. The world setting "all recipes unlocked at start" is for repeat playthroughs.
- Quests are data driven chapters over the first third and replace the tutorial. Mission Control is the voice. They only guide and reward: a player who ignores the journal is never blocked, and a gated technology waits for its main quest and for nothing else. The main quest line ends with the first flight.
- Contracts are the venture's asks and the game's spine from there. They arrive through the comms network, a board offers a few, one is active at a time, taken or left and never timed: deliver material to the pad or into orbit, bring a service online, map a planet, build a station stage. They pay in what the factory cannot make yet, an alternate recipe, a part, the next planet's map, and each names a place the player has not been. The venture's story runs through them.
- Rockets follow the rocket equation. Every body has a cost to orbit in data and every engine an exhaust speed set by its fuel, so each body and engine pair is one number the player feels, tonnes of fuel per tonne lifted, and better fuel cuts it exponentially: solid fuel for satellites and the first capsule, rocket fuel from the oil chain as the workhorse, hydrogen from electrolysis for the heavy lifts, staging when the dock's loads outgrow one stage, a slow electric transit drive for ships between bodies that never lifts. The launch screen shows payload, fuel and the capacity for this body and refuses an overload. Landing has its own cost from the body's data: a parachute is free in an atmosphere, an airless moon needs a burn, so "the ship cannot lift off on the fuel left" is a readable number before the descent.
- The ending is soft. Contracts and infinite research continue. There is no victory screen.

## Space

- Planet to space and back always happens on a rocket and is not steered: up to low orbit as the terrain's level of detail fades into the globe, down by a return pod to a spot picked on the map, with no orbital mechanics. Travel between bodies is a timed hop on the system map costing fuel by distance. Orbits are circular with a period; moons, stations and asteroids move on them as flavour, the player never steers an orbit.
- Every place a ship parks (a planet's low orbit, a Lagrange point, a moon, a belt stop with several asteroids) is a playable scene: the ship stands still near the object of interest and the player goes out in the suit with the jet pack. Free flight is pinned for now.
- Mag boots hold the player to whatever surface they stand on, in any orientation, and switch off to float. The jet pack moves in all directions and brings the player to a smooth stop when no input is given, a feature of the pack. Loose items float where they were dropped. A safety line reels the player back to the nearest airlock.
- Low orbit holds nothing on first arrival. The first capsule the player launches stays up and is the station's core for the whole game. The currency of orbit is mass: a rocket lifts a fixed cargo, so a station is a count of launches and every launch is an order on the ground factory. The station is built by hand from lifted material in four stages, each gated by what the ground must build and lift: capsule; outpost (truss, solar wings, fuel tank, airlock); dock (sealed rooms and the open cage the small ship is assembled in from kit parts, so the cage's size is the ship size the station builds, and the small ship is the gate out of home orbit); yard (plates and tanks too heavy to lift are made in orbit from belt ore, and the station grows its own belts and arms). The dangers of a station are an empty tank and an open door.
- Ships are models with walkable interiors: the hull is one asset per size and the inside is a foundation frame, so interiors are built with the ground's tools. Small (two rooms, a few stacks of cargo, a backpack with wings), medium and large, built at stations. Rockets ferry between a ship and a surface.
- Early space is manual and risky: hauling by hand, repairs by hand, landings that may be one way. A stranded player respawns at home, the ship stays as a wreck with its cargo for a later salvage trip. With the tree filled, logistics rockets cross the system on schedules and asteroid mining runs itself.
- Comms work as Kerbal's network: relay satellites the player builds, a handful per planet, each with a maximum range, a chain of them carrying the signal across the system, with ground stations where satellites run out. Coverage is a graph of ranges and gates remote information only, a planet's map, far bases' status, the contract board and survey data, never play.
- The venture's derelicts are rare: a few satellites and one relay station, each a hands on repair with parts to bring and fuel to pour, which gives its service and can be towed to the station as a module.
- Terraforming is a branch of the factory, not its main loop: pressure, heat, oxygen, water, vegetation and micro fauna as machine classes fed by belts, an index per planet that moves only while the machines are fed, each stage unlocking a material class only a living world has. The home world starts partway up and becomes breathable late; a barren world starts at zero. The suit's oxygen consumption falls with the index until the stat stops.

## Multiplayer

- About 32 concurrent players as a guess and no cap in the design. Up to four players in local split screen on one machine, freely mixed with remote players; the phone joins as one remote player with its touch overlay. A dedicated headless server hosts; a player's machine hosts by running the server beside its own game, so there is one host path and the host never plays.
- The model is Factorio's lockstep on the deterministic tick: every machine runs the whole simulation, inputs are stamped with their tick and relayed by the host, a joining player receives the save, and the state hash is the desync check. The world has one home: every player starts at the pod and a new player spawns there.
- One shared clock and one bed rule for everyone (The world). Permissions are a host role that owns the world settings and can kick; everything else is open to every player, and no player can harm another.

## Lore and tone

Realistic rather than cartoonish. The player is a contractor establishing an industrial frontier in an uninhabited star system for a venture that holds the system's exploitation lease and stays in contact through Mission Control. The venture sets the contracts, the prices and the targets, and the cynical hand of capitalism is felt through its messages and its demands. Spoil heaps, spent veins, flare stacks and wrecks are what the frontier does to the system, and the game shows it without a pollution mechanic. Materials, processes and machines carry their real names and real units: hematite and chalcopyrite, smelting and cracking, kilowatts and items per minute, tonnes of fuel per tonne lifted. The geology is plausible. There are no aliens, no magic, no mascots and no NPCs; the planets' animals are ambient scenery. Humour lives in Mission Control's corporate messages, not in the world.

## Sound

Sparse, with a hard cap on simultaneous voices, so a large base is a hum rather than a choir. The visual layer (bottleneck overlay, HUD warnings) is the primary feedback and sound confirms it. Distinct sounds are reserved for state changes: a machine stopping or breaking, a brownout starting, a contract completing, a capsule landing. Nothing plays continuously but the biome ambience, the rain and one hum for the nearest working machine, one per machine family at most. Birds and insects are short calls in clusters, and effects are short and never layered. Mechanism: [doc/presentation.md](doc/presentation.md), Sound.

## World settings

Chosen at world creation: seed, name, planet and its radius preset, mode (peaceful, survival, creative), terrain sample spacing, keep inventory on death, vein finiteness, vein richness (50, 100, 200 or 400 percent), research cost multiplier, byproduct strictness, all recipes unlocked at start, day length. `data/game.sjson` holds only the defaults for the new world screen.

## User interface

Mechanism: [doc/ui.md](doc/ui.md) and [doc/hud.md](doc/hud.md).

- 10 foot UI: readable from a couch at 1080p, large icons, little text, and legible in a quarter of the screen for split screen.
- Two navigation styles, always both: focus navigation (d-pad or left stick) and pointer (right trackpad). Every screen works fully with either.
- Selection assist in the world: the reticle snaps to the nearest entity and the bumpers cycle overlapping candidates, because picking one entity among dense neighbours is the known weak spot of factory games on a pad. Placement snaps to the frame grid and to neighbours by default, free placement is the exception.
- The recipe browser is a graph: for any item what makes it, what uses it, and where its byproducts go. No search box.
- Built in information: a rate on every machine panel, a bottleneck overlay, production statistics, a power overview, the launch screen's capacity line.
- Text entry (world name) uses an on-screen keyboard driven by the trackpads. A physical keyboard or the phone's keyboard works too.
- Tooltips are panels that open on a button, never hover only.

## Editors

The game carries its own editors (user, 2026-09-28): the model is the Warcraft 3 world editor, and the long term aim is making one's own maps in the game. Every tunable presentation or generation parameter is data with an in-game editor in developer mode, applied on the fly, with a save that hands the chosen values to an agent so they become the new defaults. Editors are screens like any other, gamepad first. The Data files screen is the fallback editor for everything without one of its own ([doc/developer_tools.md](doc/developer_tools.md)).

## Input

Steam Controller (2026) first ([doc/input.md](doc/input.md), with the technical path decided in `doc/log/2026-09-26.md`). Touch is a first class input beside the gamepad and the pointer: on a touch screen the game draws its own virtual gamepad with gestures over the whole screen, instead of GameNative's button layout (0134), feeding the same gamepad state as the physical devices, and in menus a finger is the pointer ([doc/touch_overlay.md](doc/touch_overlay.md)).

## Art direction

The terrain is Astroneer's soft sculpted surface: smooth meshes with gentle shading and strong colour per planet palette, carried by textures the game generates from parameters in data, isotropic and applied triplanar with blending at material boundaries, and a grain per material (sand smooth, rock faceted). Everything built is industrial in Techtonica's hard surface manner at a lower fidelity (user, 2026-10-03: "we can maybe approach techtonica's look", "a slightly more low-fi look"): machines are low polygon meshes of arbitrary geometry at real scale, grimy metal, pipes, bolts and warning paint, no toy look, no blocky voxel look and no visual distinction for its own sake. The rules for a machine model (the pass of 2026-10-03, applied by `doc/work/0205-the-model-kit-and-the-first-machines.md` and 0206): silhouette first, one primary volume (a box, a drum, a hopper) with one to three secondary volumes (a chimney, a mast, a tank, an intake) on a base plate or skid, so a machine is told apart at 30 m; details are geometry (bevelled edges, ribs, pipe elbows, bolt rings, hatches), never a texture and never a pattern; flat shading, at most 800 triangles per body and 200 per moving part (the workbench of 0207 enforces the maxima; about 200 for a body is the guide for a machine of a cell or more, and a pole or a lamp stays far under it), cylinders of 8 to 12 sides, bevels of one segment; a palette of dark blue grey steel and galvanised light grey for the body with one accent per role (mining ochre, smelting brick red, power yellow with black hazard, fluids teal, logistics grey with yellow edges, science white with cyan; assemblers share the logistics colours and carry a cyan state strip), timber and stone for the hand built pieces (a wooden chest, a crate, a small pole, a workbench), a warm orange emissive for heat, a warm white one for a lamp's head and a cyan one for electric indicators as thin inset strips, at most 8 materials per machine, Techtonica's cavern palette desaturated a little for daylight; the moving part visible from the front and above and the emissive strips on the working side, so the state reads at a glance; a scale cue (a hatch, a valve wheel, a ladder rung of about 0.3 m) on every machine larger than one cell, so the player's height reads against it; ribs, bolts and vents in uneven counts and offsets within a model (No perceivable repetition). A machine's moving part moves and its glow lights only while it works, so a glance shows its state, and a broken one shows that too. The arm's cycle (reach, grab, swing, release, return) takes its timing from the belt and the machine it serves, so no two arms swing in step. Realism is carried by the lore and the numbers, not the rendering. Models and animals come from the generated pipelines ([doc/presentation.md](doc/presentation.md)). The default typeface is Exo 2, a geometric technical face chosen for the theme.

## No perceivable repetition

A major principle (user, 2026-09-28): people are very sensitive to patterns where there should be none. Anything made for human perception, sound, animation or imagery, must not repeat at a period the player can feel, and must not stripe or tile visibly at a larger scale than the thing itself.

- A texture must not produce rows or diagonals across a field of one material: it is isotropic, or a variation per place breaks the repetition, or both ([doc/presentation.md](doc/presentation.md), Per block variation).
- A sound that recurs (birds, insects, steps) plays in short clusters with long and varying pauses and a varied pitch, never on a fixed period; a looping sound drifts a little in volume.
- An animation cadence (the head bob, the footsteps, the mining chop, the arm's swing) follows the world (distance walked, work done, items moved) at a natural rate and does not speed up with a developer cheat.
- A breakdown's interval varies per draw.

Every new sound, animation, texture and generated asset is checked against this before it lands.

## Technical

Targets: the couch machine at 1080p with the Steam Controller, the Steam Deck at 1280 by 800 with its built in controls (user, 2026-09-27), and an Android phone, as a native app and through GameNative running the Windows build ([doc/build.md](doc/build.md), [doc/android.md](doc/android.md)). Every rendering feature is budgeted for the Deck's APU and sits behind a setting when it costs. The simulation is deterministic, fixed step and decoupled from rendering, holds an array of players, and is a pure function of its queued inputs, so lockstep multiplayer and replay follow from it; the terrain and water fields and their brushes are integer or fixed point like the rest of the simulation, so the phone's arm64 and the desktop's x86 agree ([doc/architecture.md](doc/architecture.md)). The engine and plugin direction of 2026-10-01 (`doc/work/0146-engine-and-game-logic-cut.md`) is kept in mind and on the back burner: the cut it draws stays the guide for where code goes, the plugin system itself waits.

## Not now

No NPCs; star travelling NPCs are a possible future. One star system; interstellar travel is a possible future. Free flight is pinned. Enemies, pollution and combat are not planned. Rails, blueprints of built areas, polished Xbox-style controller support, achievements and localisation wait for the backlog in [PLAN.md](PLAN.md).

## Open questions

Listed with recommendations in [SUGGESTIONS.md](SUGGESTIONS.md).
