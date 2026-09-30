# Mine oh Belowed

A voxel automation game: Minecraft's diggable, procedurally generated open world with Factorio's build-a-factory game loop. Couch first: designed around the 2026 Steam Controller (trackpads, gyro aim, grip buttons). No keyboard needed beyond the occasional name field.

Status: pre-alpha and playable. All eight gameplay phases, from landing to the first rocket shipment, are in the game with placeholder art; the polish pass towards the first alpha is under way ([PLAN.md](PLAN.md)).

## What it is

- A factory game first: the Factorio loop of mining and crafting by hand once, then automating with drills, belts, inserters, assemblers, power and research, guided by quests from landing to a rocket program.
- In an open voxel world where every block can be dug, placed or built on. Ore comes from surface veins at Factorio scale, finite or infinite as a world setting; the underground is optional.
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
