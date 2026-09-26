# Mine oh Belowed

A voxel automation game: Minecraft's diggable, procedurally generated open world with Factorio's build-a-factory game loop. Couch first: designed around the 2026 Steam Controller (trackpads, gyro aim, grip buttons). No keyboard needed beyond the occasional name field.

Status: pre-alpha, design phase. Nothing playable yet. Milestones are in [PLAN.md](PLAN.md).

## What it is

- Open world where every block can be dug, placed, or built on.
- Ore lies in veins by depth, and depth is the progression axis. Vertical logistics (ramps, lifts) bring material back up, or you build the factory down there.
- Factorio loop: mine and craft by hand once, then automate with drills, belts, inserters, assemblers, steam power and research.
- Peaceful by default: no enemies and no pollution in the first alpha. Built to be played while the kids watch.
- Written in Odin with raylib. Content (blocks, items, recipes, machines, technologies) is data driven in SJSON.

## Building

See [doc/build.md](doc/build.md). Short version: Odin toolchain at `~/opt/odin` (dev-2026-09), then `./build.sh` (arrives with milestone M0), or `nix build`.

## Playing

The game is launched from Steam as a non-Steam game with Steam Input disabled for that shortcut, so it reads the Steam Controller directly through SDL3. Controller layout and the reasoning are in [doc/input.md](doc/input.md).

## Documentation

- [PLAN.md](PLAN.md): end goal, alpha definition, milestones, post-alpha backlog.
- [DESIGN.md](DESIGN.md): game design overview.
- [doc/](doc/README.md): detail documents, decision log (`doc/log/`), work items (`doc/work/`).
- [SUGGESTIONS.md](SUGGESTIONS.md): open questions and proposed next steps.

## License

AGPL-3.0-only, see [LICENSE](LICENSE).
