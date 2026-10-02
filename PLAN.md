# Plan

## End goal

A coherent, polished factory game across one procedurally generated star system of smooth voxel planets, fully playable from the couch with a gamepad, by many players in one shared world and up to four on one screen, from the landing pod to a shipyard in orbit. Peaceful by default, survival by choice. The design is [DESIGN.md](DESIGN.md); the decisions that set this direction are in `doc/log/2026-10-02.md`.

Beyond the game: a voxel 3D engine on which any style of game can be built, with all game logic and design in WebAssembly plugins, and Mine oh Belowed as its first plugin ([doc/work/0146-engine-and-game-logic-cut.md](doc/work/0146-engine-and-game-logic-cut.md)). On the back burner (user, 2026-10-02): the cut it draws stays the guide for where code goes and the architecture seams that lockstep multiplayer needs stay high priority, the plugin system itself waits for the new game.

## The rebuild

The block world of M0 to M12 is replaced by the smooth world of DESIGN.md (user, 2026-10-02): a true sphere of smooth voxels with radial gravity, foundation frames for the factory, free belts on poles, big arm inserters, conserved water, survival modes, a station built by hand, a star system, lockstep multiplayer. Saves break as the rebuild needs, no second world type is kept beside the new one, the work happens on `main`, and multiplayer is in the first slice rather than bolted on. The content carries over (items, recipes, machines, technologies, quests, strings); the world, the player's movement, placement and rendering are rewritten; the engine cut of 0146 already puts the line there. The couch keeps the last block build until the ground game plays on the new world.

## Alpha 1 definition

The first third of DESIGN.md's phases, 1 to 7, on the smooth starter planet: from the pod to the first capsule in low orbit, with the quest journal carrying the player the whole way, the three modes, and several players in one world from the couch and the network. It is a game, not a technology demonstration: placeholder art is acceptable, missing systems are not. Everything is reachable with the Steam Controller. Worlds save and load.

Verify: a group of players, some on one couch and one remote, follows the quest journal from the pod to the first capsule launch over several sessions, saving and resuming between them, with no keyboard except for the world name and no outside help.

Alpha 2 is phases 8 to 11, the space game, defined when alpha 1 is in sight.

## Where it stands

- The block world (M0 to M11) reached its alpha content in code and went through the presentation campaign; of its verify statements only M0's and couch test 1's ran on the couch (`doc/log/2026-09-27.md`, `doc/log/2026-09-30.md`). M12's cleanup, audits, code map, pilot split, pure moves and hubs are done (`doc/log/2026-10-01.md`); its queue paused after 0162 and is re-read against the new world before anything of it resumes (`SUGGESTIONS.md`, The paused audit queue).
- 2026-10-02: the vision was worked out and decided with the user (forty decisions, `doc/log/2026-10-02.md`), merged into DESIGN.md and this plan, and the technical brief for the smooth world engine with multiplayer is [doc/work/0167-smooth-world-engine-brief.md](doc/work/0167-smooth-world-engine-brief.md).
- Next: the brief fleshed out with the user, then its work items for M13, the first slice. Smaller items the user meets while playing the block build still take priority as they come.

## Couch tests

Pre-alpha builds the user plays on the couch to try the core loop long before the alpha is complete. A couch test follows every milestone from M13 on, each with its own verify statement, and the feedback goes into `TODO.md` and from there into work items. From M13 on a couch test includes at least one remote player, since lockstep is tested by playing.

## Milestones

Each milestone has a single verify statement. Work items in `doc/work/` reference their milestone and are written when the milestone is picked, the brief first. Milestones are in dependency order, and the phase numbers refer to the gameplay phases in DESIGN.md.

| Milestone | Work items | Status |
| --- | --- | --- |
| M0 to M11 The block world | 0001 to 0140 | Done in code, couch tests 2 to 5 never run; retired by the rebuild, the content carries over |
| M12 Architecture toward the engine cut | 0142 to 0166 | Cleanup, audits, code map, pilot split, pure moves and hubs done (0142 to 0162); the seams re-read against the new world, the ones lockstep needs move into M13 |
| M13 The first slice | 0167, then its items | Todo |
| M14 The ground game on the smooth world | | Todo |
| M15 Survival, the suit and the modes | | Todo |
| M16 Low orbit and the station | | Todo |
| M17 The first hop | | Todo |
| M18 The system | | Todo |
| M19 The yard and the living worlds | | Todo |
| M20 Signals and logic | | Todo |

### M0 to M11 The block world

Toolchain, CI and the Steam shortcut (M0); the chunked block world with veins, water and light (M1); hand crafting, the radial hotbar, the recipe graph and quests (M2); burner automation, belts, inserters and placement (M3); power and research (M4); save and load, settings and the pause menu (M5); intermediates and byproducts (M6); fluids and plastics (M7); bore drills, deep veins, caves and hydro (M8); the rocket program (M9); the couch findings of M10; the presentation campaign of M11 with the command socket, hot reload, the model pipeline, the Windows build, the native Android app, the touch overlay and the editors. The milestone texts live in the git history of this file before 2026-10-02 and in the work items.

### M12 Architecture toward the engine cut

The cleanup series (0142 to 0145) measured the code and settled two decisions: no entity component system in the engine, and no full package split until the layering holds (`doc/work/0143-architecture-audit.md`, Implementation notes). The pure moves and the hubs (0147 to 0162) are done: the game's records off `World`, the kind ticks on a context that reaches blocks through one query and one write, `Frame_State` in groups, the request table, `Screen_Context` by consumer, the cue detector. Of the seams, the queued writes (0166) stop being optional, since a tick that is a pure function of its inputs is what lockstep multiplayer runs on; they and the per tick event list belong to M13. The cell occupant index (0164) and the arrival list (0165) are re-read against the field world before they are kept or closed. The kind table and the game kit wait with the plugin system.

Verify: the simulation ticks from queued inputs only (no write into it from the frame side), and `python3 tools/code_graph.py --check doc/code_map.md` holds the layering the code map records.

### M13 The first slice

The smallest build that lets the user judge the direction by feel, on `main`, with multiplayer from the first commit: a sphere of a few hundred metres with the terrain field and its mesh, radial gravity and the slope walk, a dig and place tool with two brush sizes, water in one basin under the conserving rule, one torch in a dug cave with the new falloff, one foundation carrying a drill, an arm and a belt into a chest, a day and a night, and the lockstep of DESIGN.md's Multiplayer section with the state hash as the desync check. No space, no survival, one recipe chain. The brief is 0167; its work items follow it.

Verify: two machines on the home network and a split screen pair on the couch share the sphere for twenty minutes while all four dig, place and run the belt line, with no desync, and the user judges the walk, the digging and the arm.

### M14 The ground game on the smooth world (phases 1 to 7)

Every machine of the current content placed on foundation frames, belts and pipes on poles between islands, veins and outcrops, deep veins and caves on the sphere, water and hydro, the quest chapters 1 to 7 played from the pod, the arm model replacing the inserter, the dev kits rebuilt as field worlds, the benchmark sizes 1 to 16 on the new world, and the play build switched. The block world type is removed from the code at the end.

Verify: couch test 6. Chapters 1 to 7 played through by two players on the couch and one remote, saved and resumed between sessions, at 60 ticks per second at benchmark size 16.

### M15 Survival, the suit and the modes

The three modes at world creation, the suit's tanks and their fill points, the pod's oxygen generator and panels, the slow drain and the quiet death, the respawn action, keep inventory as a setting, the death pack, sealed rooms and the first dome with crops, weather's drains, the repair kit and the first breakdowns.

Verify: couch test 7. A survival world from the pod to the first sealed dome with crops, with one death and the pack recovered, and a peaceful world where none of it shows.

### M16 Low orbit and the station (phase 8)

The rocket equation in the launch screen, solid fuel and the first comms satellite, rocket fuel and the first capsule, the terrain's level of detail fading into the globe, the parking scene in low orbit, EVA with mag boots, the jet pack and the safety line, the station built by hand from lifted material through the outpost stage, the return pod landing at a picked spot, the system map, the contract board, the venture's rare derelicts and their repairs.

Verify: couch test 8. The first capsule launched, the outpost built around it over several launches by two players on EVA, and a return pod landed where the map said.

### M17 The first hop (phase 9)

The dock's sealed rooms and cage, the small ship from lifted kit parts, timed hops on the system map, the moon with its own material, landings refused on steep ground, the lift off line, wrecks and salvage trips.

Verify: a small ship built in the dock lands on the moon, brings back its material, and a ship stranded there is salvaged with its cargo on a second trip.

### M18 The system (phase 10)

The generator's planet roles from the seed, new bases on the ore world and a gas giant's moon, hauling by hand, logistics rockets and the hauler, belt stops with several asteroids from the hand drill to anchored miners, comms relays and ground stations reaching further, the survey satellite replacing the purchased survey, prospecting on a blank planet, contracts that pull the player outward.

Verify: three bases on three bodies linked by logistics rockets, and a contract completed with material only a far body has.

### M19 The yard and the living worlds (phase 11)

Hydrogen and cryogenics, staging, the orbital refinery on belt ore, medium and large ships from the yard, explosives and the deep world's core ores, the second living world's flora and fauna pools, terraforming stages to a breathable home world.

Verify: a large ship leaves the yard built from belt ore, and the home world's atmosphere becomes breathable with the suit's oxygen stat gone.

### M20 Signals and logic

The signal network on wires and poles, machines reading signals, signals between planets over the comms network, the processor machine with its block language on a gamepad, its integer virtual machine and step budget.

Verify: a processor on the ore world launches the home base's logistics rocket when a silo there fills, with every machine in a multiplayer world agreeing.

## Backlog

Not ordered. Each becomes a milestone when picked.

- The plugin system of 0146: the wasm host, lifetime, interop and intercom, the game kit's kind table.
- Rails and minecarts as the long distance transport layer on a planet.
- Blueprints and copy/paste of built areas.
- Free flight of ships, pinned on 2026-10-02.
- Full Xbox-style controller support without trackpads.
- Music, and hand made art replacing the generated placeholders.
- Modding through the data files.
- Star travelling NPCs and interstellar travel, possible futures.
