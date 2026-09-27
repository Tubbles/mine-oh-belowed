# 0053 Command socket: cheat mode through the assistant

Status: implemented
Milestone: M11

## Goal

User request (2026-09-27): the assistant must be able to inject commands into the running game while the user plays on the couch: "advance me to blue science", "build me a full tier 1 factory", "spawn another ore vein at this chunk". A local command socket the game listens on in developer mode, a line protocol, and a small command line client the assistant runs from the repository.

## Deliverables

- Transport: a Unix domain socket at `$XDG_RUNTIME_DIR/mine-oh-belowed/command.sock` (fallback `$XDG_STATE_HOME/mine-oh-belowed/command.sock`), directory mode 0700, opened only when developer mode is on (the setting or `--dev`), through `core:sys/posix` (`sys_socket.odin`, `sys_un.odin`, non blocking accept with `fcntl`). The frame loop polls it once per frame: complete lines are parsed into requests and served on the main thread between ticks, like developer requests today, so the simulation stays deterministic; each request gets one response, `ok <text>` or `error <text>`, terminated by a newline. Several clients may connect in turn; a client may send several lines.
- Protocol: one command per line, words separated by spaces, SJSON-like quoting for strings with spaces. Commands, each mapped onto existing procedures where they exist (developer.odin, quest_runtime.odin, venture.odin, generation_starter_veins.odin, entity_placement.odin): `give <item> <count>`, `take <item> <count>`, `kit <chapter>`, `chapter <n>` (complete quests up to n), `research <technology>` (mark researched, or add a level for an infinite one), `unlock_all`, `teleport <x> <y> <z>` and `teleport pad`, `time <dawn|noon|dusk|midnight>`, `fly <on|off>`, `cheat_speed <on|off>`, `vein <type> <x> <z> [size_class]` (register a new surface vein with its footprint at the column, stamping outcrops into loaded chunks and remembering it so chunks loaded later get them; saved like a starter vein), `place <machine> <x> <y> <z> <rotation>` (through the placement rules, refusing what a player could not place), `remove <x> <y> <z>`, `block <block> <x> <y> <z>`, `blueprint <path>` (an SJSON file of place and block commands relative to a given origin, so "a full tier 1 factory" is one file), `tick <n>` (run n ticks as fast as possible, rendering paused, then resume), `pause` and `resume`, `save`, `reload` (0054 when it exists; until then `error`), `screenshot [name]` (`rl.TakeScreenshot` into `$XDG_STATE_HOME/mine-oh-belowed/screenshots/<name or timestamp>.png`, the response names the path), `query player` (position, yaw, pitch, flying, inventory as item counts), `query world` (seed, tick, day time, pad, loaded chunk count), `query veins [radius]`, `query entities [kind] [radius]`, `query quests`, `query contracts`, `query stats <item>`, `help`. Every command is also reachable from a Developer screen button where it makes sense (screenshot).
- Client: `tools/moc` (Python, standard library only): `tools/moc give iron_plate 50` connects, sends the line, prints the response and exits non zero on `error`; `tools/moc -` reads commands from stdin; `tools/moc blueprint work/factory.sjson` sends the file's commands. A `doc/commands.md` documents the protocol and every command with an example; the assistant reads it before driving a session.
- Blueprints: `data/blueprints/tier1_factory.sjson` as the first example: a burner mining line into furnaces with belts and inserters that works when placed next to the starter veins (the file names positions relative to the pad and the vein), so "build me a full tier 1 factory" is `tools/moc blueprint data/blueprints/tier1_factory.sjson`.
- Safety: the socket exists only with developer mode on, only local users can connect, commands never touch files outside the game's own directories, and the log records every command with its response.
- Tests: protocol parsing and quoting, each command as a pure request applied to a test simulation (give, chapter, research, vein registration with outcrops, place refused and accepted, blueprint expansion, tick count), query formatting, and the socket path resolution from the environment.

## Verify

- Builds and tests pass; `tools/moc help` against a running dev build lists the commands.
- User: while playing, the assistant runs `tools/moc chapter 5` and `tools/moc blueprint data/blueprints/tier1_factory.sjson` and the world changes on the next tick.

## Notes

Implemented by a subagent (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (15 new tests in `src/command_test.odin`, among them a real socket round trip and the shipped blueprint placing on a floor with an iron vein and producing iron plates within 3600 ticks), `./build.sh`, `./build.sh release`, `python3 -m py_compile tools/moc`, `tools/moc help` without a game (exit 2 with the hint). Protocol and commands: `doc/commands.md`.

Files: new `src/command.odin` (words, commands, blueprints, queries), `src/command_socket.odin` (path, listening, polling, per client buffers), `src/command_test.odin`, `tools/moc`, `data/blueprints/tier1_factory.sjson`, `doc/commands.md`; changes to `src/developer.odin` (seven new actions, `serve_developer_request` returns why a request was refused), `src/loop.odin` (frame state, serving after the frame's ticks, fast ticks, pause, screenshots), `src/world_vein.odin` and `src/world_streaming.odin` (added veins), `src/entity_placement.odin` (`commit_placement` shared with the player, `command_placement`), `src/generation_veins.odin` (`Vein.added`), the Developer screen and strings.

### Model and deviations

- Serving: the commands build `Developer_Request`s and call `serve_developer_request` directly on the main thread after the frame's ticks, instead of queueing them for the next tick, so each answer can say whether it was refused. The simulation never reads the socket. Queued lines run in arrival order, all in one frame, until a `tick` command; later lines wait for its answer.
- Responses always end with a line holding only `.`, for `ok` and `error` alike, so a client reads up to it.
- `insert <item> <count> <x> <y> <z>` is an extra command: burner drills and inserters need fuel, and without it the tier 1 blueprint could not run by itself.
- `chapter <n>` completes the quests before chapter n only (as the doc of this item says), no kit; `kit` is separate.
- `place` takes no item and does not count as a placement in the statistics (quest objectives on placed machines do not advance). Machines no item places (the capsule, crates) are refused.
- Added veins: the vein is kept in `World.veins` with `added` set (saved through the existing vein list, no format change). Its id is the region's next index after the generated veins and earlier added veins. Its centre and outcrop cells use the generated surface height; only solid cells are stamped. Loaded chunks are stamped through `world_set_block`, stored (modified, unloaded) chunks are rewritten, later chunks get it on arrival (`apply_added_veins_to_chunk`). It may reach past its region's border. The map survey and the orbital survey ask the generator and do not see added veins. The overlap check covers registered veins and the generated surface veins of the regions around the disc.
- Blueprint origin `{vein = "<type>"}` is the registered surface vein of that type nearest the landing pad, not the generator's starter vein list, so it needs the vein's chunks loaded (they are, near the pad). The origin is the cell above the pad or vein centre, so relative y 0 stands on the surface.
- Screenshots use `LoadImageFromScreen` and `ExportImage` at the end of the frame (after the UI, before `EndDrawing`): `TakeScreenshot` strips the directory and writes into the working directory. The command answers with the path at once; the file appears at the end of that frame.
- `tick <n>` answers when done; up to one second of wall time per frame, with the frame's normal ticks replaced; the window still draws once per frame. At most 1000000 ticks.
- Developer mode switched off closes the socket; switched on opens it. A socket another running game listens on is left alone.

### Not verified

The socket against a running game with a window: the frame loop integration, fast ticks, screenshots (the `LoadImageFromScreen` read back and the PNG), the Developer screen's third button in the last row (three buttons in 1000 units), and the blueprint on the real starter vein terrain (it needs flat ground over about 12 by 11 blocks).

### Open questions

- Should `place` count as a player placement for quests?
- Should the blueprint's `{vein}` origin come from the generator's starter veins, so it works before the chunks load?

