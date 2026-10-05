# Mine oh Belowed

Techtonica in space: a first person automation game on the diggable, procedurally generated planets of one star system, with Factorio's build-a-factory game loop and Techtonica's look and feel. Couch first: designed around the 2026 Steam Controller (trackpads, gyro aim, grip buttons). No keyboard needed beyond the occasional name field.

Status: pre-alpha, in a rebuild. The block world (all eight gameplay phases, from landing to the first rocket shipment) is retired; since the first slice (M13) a new world is a small planet of smooth, diggable terrain with water, light, a day and night, and factories on foundation frames joined by belts and pipes on poles, shared in lockstep between machines and split screen players. The ground game returns on it with M14 ([PLAN.md](PLAN.md)).

## What it is

- A factory game first: the Factorio loop of mining and crafting by hand once, then automating with drills, belts, inserters, assemblers, power and research, guided by quests from landing to a rocket program.
- On a small planet of smooth voxel terrain that can be dug and filled anywhere, walked round with gravity towards its centre; factories stand on foundation frames laid on the ground at any angle. Ore comes from surface veins at Factorio scale, finite or infinite as a world setting; the underground is optional.
- Deep recipes: many ores and alloys, byproducts that must go somewhere, recycling, liquids and gases in pipes, plastics, and power as part of the puzzle.
- Peaceful: no enemies and no pollution in the first alpha. Built to be played while the kids watch.
- Written in Odin with raylib. Content (blocks, items, recipes, machines, technologies, quests) is data driven in SJSON.

## Building

`./build.sh` with the Odin toolchain at `~/opt/odin` (dev-2026-09), or `nix build`. Everything else is in [doc/build.md](doc/build.md).

## Playing

- Couch: launched from Steam as a non-Steam game, reading the Steam Controller through SDL3 ([doc/build.md](doc/build.md), Play build and Steam shortcut, and [doc/input.md](doc/input.md)).
- Steam Deck: the same build and launcher with the Deck's own controls ([doc/build.md](doc/build.md), Steam Deck).
- Android phone: a native APK with a touch overlay, or the Windows build under GameNative ([doc/android.md](doc/android.md), [doc/touch_overlay.md](doc/touch_overlay.md), and [doc/build.md](doc/build.md), Windows).

## Documentation

- [DESIGN.md](DESIGN.md): the design intent.
- [PLAN.md](PLAN.md): end goal, alpha definition, milestones and where they stand, backlog.
- [doc/README.md](doc/README.md): the index of the detail documents, the decision log (`doc/log/`) and the work items (`doc/work/`).
- [SUGGESTIONS.md](SUGGESTIONS.md): open questions and follow ups.

## License

AGPL-3.0-only, see [LICENSE](LICENSE).
