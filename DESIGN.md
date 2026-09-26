# Design overview

Mine oh Belowed is a voxel automation game. This document is the map. Details live in [doc/](doc/README.md); this file should stay readable in one sitting.

## Pillars

1. Dig anywhere. The world is blocks and every one of them can be mined, placed or built on. Terrain is both a resource and a canvas.
2. Automate everything. The loop is Factorio's: do it by hand once, build the machine that does it, then build the machine that feeds that machine. Manual labour is the bootstrap, never the endgame.
3. Down is forward. Depth is the progression axis. Better ore lies deeper in harder rock, and hauling it back up (or building the factory down there) is the logistics puzzle neither parent game has.
4. Couch first. Every interaction is designed for the Steam Controller from the start. Text entry is limited to naming things.
5. Peaceful and kid friendly. No enemies, no violence, no pollution in the first alpha. Failure is a stalled belt, never a death screen.
6. One coherent game. One art style, one UI language, one rule set. No mod seams.

## The world

- Blocks are one metre cubes. The world is stored in cubic chunks of 32 by 32 by 32 blocks, loaded around each player. Cubic chunks make the world unbounded in every direction, depth included, and generation is lazy, so there is no world height constant.
- Procedural generation uses layered OpenSimplex noise for height and moisture, a small set of biomes (plains, forest, hills, desert, lake), trees, boulders and caves.
- Strata: the ground is layered. Topsoil, stone, deep stone, bedrock. Each stratum has a hardness that sets mining speed, and its own ore table. Alpha ores: coal, copper and iron near the surface, richer and larger veins deeper. Stone and sand are everywhere. Wood comes from trees.
- Ore veins are three dimensional blobs, not surface patches. A vein usually shows an outcrop at the surface or in a cave wall, so scouting works without x-ray vision.
- Water flows, Minecraft style: source blocks spread into neighbouring air and drain when the source is removed. Lakes and oceans are infinite for pumps. Digging under a lake floods the hole, which is a puzzle rather than a punishment, since nothing hurts the player.
- Lighting is Minecraft style: 16 level sky light and block light propagation, so underground bases need torches and lamps. The day and night cycle is cosmetic in alpha.
- Nothing falls. There are no gravity blocks in alpha.

## The player

- First person by default, with a third person camera as a toggle. The player is one block wide and two blocks tall, reaches five blocks, jumps one block, sneaks and sprints. Gyro aim gives fine pointing for block placement in both camera modes.
- Hand mining is fast and kid friendly: one to three seconds per block by hand, not tens of seconds. Tools multiply speed and gate hardness (wood, stone, iron).
- Inventory is a grid of 36 slots plus an 8 slot hotbar. The hotbar doubles as the radial menu on the left trackpad.
- No health, hunger, weight or drowning in the peaceful alpha.
- A flying and instant-mining toggle exists as a developer tool and as a mode for the youngest players.

## Progression

Alpha covers three tiers. Everything is defined in data; the list below is the intent.

- Tier 0, hands: punch trees, pick up stone, craft wooden pickaxe and axe, wooden chest. Hand crafting menu.
- Tier 1, burner: stone furnace (coal fuelled), burner mining drill, burner inserter, iron chest, belts with ramps and lifts, iron tools. Goal: the first unattended ore to plate line.
- Tier 2, steam: offshore pump, boiler, steam engine, small power pole, electric mining drill, inserter, assembler, lab, science pack 1, electric lamp. Goal: the research loop is running.

Later tiers (oil, rails, robots, deeper ores) come after the alpha.

## Automation and logistics

- Machines are multi block entities placed on a flat footprint. Footprints are defined in data and vary on purpose, odd shapes included: fitting a 3 by 2 boiler next to a 2 by 2 drill is part of the puzzle. Snapping and the rotation preview carry the gamepad ergonomics, not uniform sizes.
- Mining drills consume the blocks beneath them. A drill mines a column downward, turning ore blocks into items and leaving air. The factory literally carves the world. When the column is exhausted the drill reports it and can be picked up and moved.
- Belts come in three shapes: flat, ramp (one block of rise per block of run) and lift (a vertical belt block that stacks). Two lanes per belt, as in Factorio. Items on belts are simulated per belt line, not as individual entities, so thousands of belts stay cheap.
- Inserters reach one block in four horizontal directions and move items between belts, machines and chests. Vertical movement is the lift's job.
- Pipes connect in six directions. Alpha fluids are water and steam. Fluids use a network model (a graph with capacities), not block by block flow.
- Building uses ghost placement with rotation and a snapping preview, so a 3 by 3 machine can be placed flush against a belt with a stick. Pipette picks the block or entity under the cursor. Everything can be picked up again.
- Power poles have a supply volume and connect automatically to poles in reach. Connected poles form one electric network. Demand above supply causes a brownout that slows machines, as in Factorio.

## Research

Labs consume science packs to unlock technologies. The alpha tree has about ten nodes: automation, logistics, steam power, electric mining, lighting, iron tools, storage and a few more. It is defined in data.

## User interface

- 10 foot UI: readable from a couch at 1080p, large icons, little text.
- Two navigation styles, always both: focus navigation (d-pad or left stick moves a highlight) and pointer (right trackpad moves a cursor). Every screen works fully with either.
- Radial menus for quick actions: hotbar, build categories, rotate and pick tools.
- The recipe and item browser has category tabs on the bumpers, tag filters, first letter jumping through a radial letter wheel, and a "can craft now" filter. There is no search box.
- Text entry (world name, player name) uses an on-screen keyboard driven by the trackpads. A physical keyboard works too when present.
- Tooltips are panels that open on a button, never hover only.

## Input

Steam Controller (2026) first. The layout proposal and the technical path are in [doc/input.md](doc/input.md).

## Technical

Odin with raylib for windowing and rendering and SDL3 for controller input. Deterministic fixed step simulation decoupled from rendering, typed entity pools, data driven prototypes in SJSON. The simulation holds an array of players from the start, so local co-op later needs no redesign. See [doc/architecture.md](doc/architecture.md).

## Out of scope for alpha 1

Enemies, pollution, combat, health and hunger, flowing water, gravity blocks, multiplayer, oil, rails, blueprints, polished Xbox-style controller support, achievements, localisation.

## Open questions

Listed with recommendations in [SUGGESTIONS.md](SUGGESTIONS.md).
