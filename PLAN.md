# Plan

## End goal

A coherent, polished voxel automation game that is fully playable from the couch with a gamepad. Peaceful mode is the default. After the first alpha: deeper tech tiers, optional enemies and pollution as a game mode, and local co-op.

## Alpha 1 definition

A player starts a new world, walks, digs and places blocks, crafts by hand, builds a burner tier factory, powers it with steam, and researches far enough to place electric drills and assemblers. Everything is reachable with the Steam Controller. Worlds save and load. Art is placeholder.

Verify: a fresh player on the couch goes from spawn to an unattended line that mines iron ore, smelts it, assembles iron gear wheels into a chest, and completes at least one research, in one sitting of one to two hours, without touching a keyboard except for the world name.

## Milestones

Each milestone has a single verify statement. Work items in `doc/work/` reference their milestone.

### M0 Foundation

Toolchain, repository layout, nix flake, CI, build script, a window with a live controller diagnostics view, the Steam library shortcut.

Verify: `./build.sh` produces a binary that opens a window showing live values for every Steam Controller input (sticks, pads, gyro, grips, buttons). `nix build` passes in CI. The game starts from the Steam library.

### M1 World

Chunked voxel world, procedural terrain with strata and biomes, trees, ore veins by depth, lighting, first person player with gyro aim, dig and place by hand.

Verify: walk 500 blocks in any direction and dig to bedrock at 60 fps in 1080p without hitches from chunk loading.

### M2 Hand crafting loop

Inventory, radial hotbar on the trackpad, recipe browser without a search box, tools, stone furnace, chests.

Verify: craft a stone furnace and an iron pickaxe using only the controller, starting from an empty inventory.

### M3 Burner automation

Burner mining drill, belts (flat, ramp, lift), burner inserters, multi block machines, ghost placement with rotation, pipette.

Verify: drill, belt, furnace, inserter, chest runs unattended for ten minutes and the chest fills with plates.

### M4 Power and research

Offshore pump, boiler, steam engine, power poles, electric mining drill, inserter, assembler, lab, science pack 1, a tree of about ten technologies.

Verify: the alpha verify statement above.

### M5 Alpha polish

Save and load, settings, pause menu, on-screen keyboard, art consistency pass, performance pass, 10 foot UI pass, playtest with the kids. Tag `alpha-1` and publish a GitHub release.

Verify: two consecutive playtest sessions with no keyboard use and no crash, saved and resumed between sessions.

## Post alpha backlog

Not ordered. Each becomes a milestone when picked.

- Fluids beyond water and steam (oil chain).
- Rails and minecarts as the long distance transport layer.
- Blueprints and copy/paste of built areas.
- Split screen local co-op (the simulation is designed for several players from the start).
- Full Xbox-style controller support without trackpads.
- Peaceful animals, then optional enemies and pollution as a game mode.
- More strata and ores (gold, uranium), deeper worlds.
- Steam Deck verification.
- Real art, sound and music.
- Modding through the data files.
