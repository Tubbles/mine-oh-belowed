# Plan

## End goal

A coherent, polished factory game in a voxel world, fully playable from the couch with a gamepad, guided by quests from the first minute to a rocket program. Peaceful mode is the default. After the first alpha: the later gameplay phases, rails, local co-op, and optional enemies with pollution as a game mode.

## Alpha 1 definition

Gameplay phases 1 to 4 of [DESIGN.md](DESIGN.md): a player lands, digs and crafts by hand, runs a hand fed workshop, automates the first plate line, powers it with steam and researches far enough to place electric drills and assemblers. The quest journal carries the player through all four chapters. Everything is reachable with the Steam Controller. Worlds save and load. Art is placeholder.

Verify: a fresh player on the couch follows the quest journal from landing to an unattended line that mines iron ore, smelts it, assembles iron gear wheels into a chest, powered by steam, and completes at least one research, in one sitting of one to two hours, with no keyboard except for the world name and no outside help.

## Milestones

Each milestone has a single verify statement. Work items in `doc/work/` reference their milestone.

### M0 Foundation

Toolchain, repository layout, nix flake, CI, build script, a window with a live controller diagnostics view, the Steam library shortcut.

Verify: `./build.sh` produces a binary that opens a window showing live values for every Steam Controller input (sticks, pads, gyro, grips, buttons). `nix build` passes in CI. The game starts from the Steam library.

### M1 World

Chunked voxel world, procedural terrain with strata and biomes, trees, flowing water, vein reservoirs with outcrops, lighting, first person player with gyro aim and the third person toggle, dig and place by hand.

Verify: walk 500 blocks in any direction and dig to the deep stone at 60 fps in 1080p without hitches from chunk loading, and find at least three vein outcrops on the way.

### M2 Hand crafting loop

Inventory, radial hotbar on the trackpad, recipe graph browser without a search box, multi output recipes from the first recipe on, tools, stone furnace, chests, the quest runtime and journal with chapters 1 and 2.

Verify: following the journal only, craft a stone furnace and an iron pickaxe using only the controller, starting from an empty inventory.

### M3 Burner automation

Burner mining drill on a vein reservoir, belts (flat, ramp, lift), splitters, burner and filter inserters, multi block machines with odd footprints, ghost placement with rotation and snapping, pipette, selection assist, chapter 3.

Verify: drill, belt, furnace, inserter, chest runs unattended for ten minutes and the chest fills with plates.

### M4 Power and research

Pipes with fluid phases (water, steam), offshore pump, boiler, steam engine, tanks, poles with supply volumes, networks, proportional brownouts, power switch, power overview, electric mining drill, inserter, assembler, lab, science pack 1, a tree of about ten technologies, chapter 4.

Verify: the alpha verify statement above.

### M5 Alpha polish

Save and load, world settings, settings screens, pause menu, on-screen keyboard, art consistency pass, performance pass, 10 foot UI pass, playtest on the couch. Tag `alpha-1` and publish a GitHub release.

Verify: two consecutive playtest sessions with no keyboard use and no crash, saved and resumed between sessions.

## Post alpha milestones

In order, each one a gameplay phase from DESIGN.md.

### M6 Intermediates and byproducts

More ores and alloys, crushing and washing, slag and spoils, the byproduct rule in data, the recycler, production statistics and the bottleneck overlay, chapter 5.

### M7 Fluids and plastics

Oil from tar flats, gases, refinery, cracking, both plastics routes, combustion generators, byproduct strictness setting, chapter 6.

### M8 Scale

Bore drills, deep veins, vein revival, caves with schematics and alternate recipes, hydro power, factory floors polish, chapter 7.

### M9 Rocket program

Launch pad, rocket parts, contracts and trade with Mission Control, infinite research, chapter 8.

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
