# Plan

## End goal

A coherent, polished factory game in a voxel world, fully playable from the couch with a gamepad, guided by quests from the first minute to a rocket program. Peaceful mode is the default. After the first alpha: rails, local co-op, and optional enemies with pollution as a game mode.

## Alpha 1 definition

All eight gameplay phases of [DESIGN.md](DESIGN.md), from landing to the first rocket shipment, with the quest journal carrying the player the whole way. It is a game, not a technology demonstration: placeholder art is acceptable, missing systems are not. Everything is reachable with the Steam Controller. Worlds save and load.

Verify: a fresh player on the couch follows the quest journal from landing to the first rocket shipment over several sessions, saving and resuming between them, with no keyboard except for the world name and no outside help.

## Couch tests

Pre-alpha builds the user plays on the couch to try the core loop long before the alpha is complete. A couch test follows every milestone from M3 on. Each has its own verify statement, and the feedback goes into `TODO.md` and from there into work items. The first couch test needs M5's save and load, so M5 is pulled forward: it is usability, not polish.

## Milestones

Each milestone has a single verify statement. Work items in `doc/work/` reference their milestone. Milestones are in dependency order, and the phase numbers refer to the gameplay phases in DESIGN.md.

### M0 Foundation

Toolchain, repository layout, nix flake, CI, build script, a window with a live controller diagnostics view, the Steam library shortcut.

Verify: `./build.sh` produces a binary that opens a window showing live values for every Steam Controller input (sticks, pads, gyro, grips, buttons). `nix build` passes in CI. The game starts from the Steam library.

### M1 World

Chunked voxel world, procedural terrain with strata and biomes, trees, flowing water, vein reservoirs with outcrops, lighting, first person player with gyro aim and the third person toggle, dig and place by hand.

Verify: walk 500 blocks in any direction and dig to the deep stone at 60 fps in 1080p without hitches from chunk loading, and find at least three vein outcrops on the way.

### M2 Hand crafting loop (phases 1 and 2)

Inventory, radial hotbar on the trackpad, recipe graph browser without a search box, multi output recipes from the first recipe on, tools, stone furnace, chests, the quest runtime and journal with chapters 1 and 2.

Verify: following the journal only, craft a stone furnace and an iron pickaxe using only the controller, starting from an empty inventory.

### M3 Burner automation (phase 3)

Burner mining drill on a vein reservoir, belts (flat, ramp, lift), splitters, burner and filter inserters, multi block machines with odd footprints, ghost placement with rotation and snapping, pipette, selection assist, chapter 3.

Verify: drill, belt, furnace, inserter, chest runs unattended for ten minutes and the chest fills with plates.

### M4 Power and research (phase 4)

Pipes with fluid phases (water, steam), offshore pump, boiler, steam engine, tanks, poles with supply volumes, networks, proportional brownouts, power switch, power overview, electric mining drill, inserter, assembler, lab, the first research tier, chapter 4.

Verify: following the journal only, an unattended line mines iron ore, smelts it, assembles iron gear wheels into a chest, powered by steam, and completes at least one research.

### M5 Pre-alpha usability

Save and load, world settings, settings screens, pause menu, on-screen keyboard, first performance pass.

Verify: couch test 1. Two consecutive sessions through phases 1 to 4 with no keyboard use and no crash, saved and resumed between sessions.

### M6 Intermediates and byproducts (phase 5)

More ores and alloys, crushing and washing, slag and spoils, the byproduct rule in data, the recycler, production statistics and the bottleneck overlay, chapter 5.

Verify: couch test 2. A line that turns mixed ore into two alloys while every byproduct ends in a use or a sink.

### M7 Fluids and plastics (phase 6)

Oil from tar flats, gases, refinery, cracking, both plastics routes, combustion generators, byproduct strictness setting, chapter 6.

Verify: couch test 3. Plastic is produced on both routes and the waste gas runs a generator.

### M8 Scale (phase 7)

Bore drills, deep veins, vein revival, caves with schematics and alternate recipes, hydro power, factory floors polish, chapter 7.

Verify: couch test 4. A base with several veins, a deep vein tapped from the surface, and a two floor factory keeps 60 ticks per second.

### M9 Rocket program (phase 8)

Launch pad, rocket parts, contracts and trade with Mission Control, infinite research, chapter 8.

Verify: couch test 5. The first rocket shipment leaves and the returns arrive.

### M10 Alpha polish and release

Art consistency pass, performance pass, 10 foot UI pass, full playthrough on the couch. Tag `alpha-1` and publish a GitHub release.

Verify: the alpha verify statement above.

## Backlog

Not ordered. Each becomes a milestone when picked.

- Rails and minecarts as the long distance transport layer.
- Blueprints and copy/paste of built areas.
- Split screen local co-op (the simulation is designed for several players from the start).
- Full Xbox-style controller support without trackpads.
- Peaceful animals, then optional enemies and pollution as a game mode.
- Steam Deck verification.
- Real art, sound and music.
- Modding through the data files.
