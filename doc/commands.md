# Command socket

The game can be driven from outside while someone plays: give items, skip chapters, add a vein, build a blueprint, advance time, read the state back. Work item 0053. Source: `src/command_socket.odin` (transport), `src/command.odin` (protocol and commands), `src/developer.odin` (the requests the commands serve), `tools/moc` (the client).

Linux only. The Windows build (work item 0102, `build.md`) has no Unix domain sockets: with developer mode on it logs `error: command socket: no command socket on Windows` once and never listens.

## For the assistant

1. The game must run with developer mode on: `--dev`, or the `developer_mode` setting (Settings, Developer mode). The log then says `command: listening on <path>`.
2. Run `tools/moc <command words>` from the repository. It prints the response and exits 0 on `ok`, 1 on `error`, 2 when the socket is missing (game not running, or developer mode off).
3. Read `tools/moc help` for the command list, `tools/moc query player` and `tools/moc query world` to see where things stand before changing them.
4. Screenshots: `tools/moc screenshot base` answers with the PNG's path under `$XDG_STATE_HOME/mine-oh-belowed/screenshots/`; the file exists once the game drew its next frame. Read it with the Read tool.
5. Every command and response line is in the game log, `$XDG_STATE_HOME/mine-oh-belowed/log.txt`, prefixed `command:`.

## Transport

- A Unix domain stream socket at `$XDG_RUNTIME_DIR/mine-oh-belowed/command.sock`, or `$XDG_STATE_HOME/mine-oh-belowed/command.sock` (then `~/.local/state/...`) when `XDG_RUNTIME_DIR` is unset or relative. The directory is made with mode 0700, so only the user can connect.
- Open only while developer mode is on; switching the setting off closes it. A stale socket file is removed at start; a socket another running game listens on is left alone and this game does not listen (logged).
- The frame loop polls the socket once per frame without blocking. Lines are executed on the main thread after the frame's ticks, so a command always sees the simulation between two ticks. Several clients may connect; lines run in arrival order.

## Protocol

- One command per line (`\n`). Words are separated by spaces or tabs. A word in double quotes may contain spaces; inside quotes `\"` and `\\` escape. `#` outside quotes starts a comment. Blank and comment lines get no response.
- Every other line gets exactly one response: a first line `ok`, `ok <text>` or `error <text>`, possibly further lines (queries), then a line holding only `.`.
- Coordinates are world block coordinates as the diagnostics overlay shows them (the block the player's feet are in for `teleport`). Rotations: 0 points to +x, 1 to +z, 2 to -x, 3 to -z. Names are the ids of the data files (`data/items.sjson`, `data/machines.sjson`, `data/blocks.sjson`, `data/technologies.sjson`, `data/veins.sjson`).
- Changes land between two ticks; while a pausing screen (the pause menu) is open, the world changes at once but time does not move.

## Commands

| Command | Example | What it does |
|---|---|---|
| `help` | `tools/moc help` | The command list. |
| `give <item> <count>` | `tools/moc give iron_plate 50` | Items into the inventory, what does not fit into the drop capsule's pending rewards. Count 1 to 10000. |
| `take <item> <count>` | `tools/moc take stone 100` | Items out of the inventory; the answer says how many were there. |
| `kit <chapter>` | `tools/moc kit 4` | The chapter's kit from `data/dev_kits.sjson`. |
| `chapter <n>` | `tools/moc chapter 5` | Completes every quest before chapter n with its rewards (items to the capsule, recipes and technologies unlocked), like the Developer screen. One past the last chapter completes all. Does not give the kit. |
| `quest finish` | `tools/moc quest finish` | Completes the active quest with its rewards (items to the capsule, recipes and technologies unlocked, deliveries not taken), logs its complete message and activates the next, like the Developer screen's Finish active quest button. An error once every quest is done. |
| `research <technology>` | `tools/moc research ore_processing` | Marked researched as a quest reward does; an infinite technology gains one level. |
| `unlock_all` | `tools/moc unlock_all` | Every recipe and technology. |
| `teleport <x> <y> <z>`, `teleport pad` | `tools/moc teleport 40 70 -12` | Feet into that block's centre, or onto the landing pad. |
| `time <dawn\|noon\|dusk\|midnight>` | `tools/moc time noon` | Sets the time of day. |
| `weather <clear\|overcast\|rain\|fog\|auto>` | `tools/moc weather rain` | Forces a weather kind at full intensity for screenshots (0063); `auto` returns to the schedule. Kept in the session, not saved, and ignored while the Weather setting is off. |
| `fly <on\|off>` | `tools/moc fly on` | Fly mode. |
| `cheat_speed <on\|off>` | `tools/moc cheat_speed on` | Faster movement and hand mining. |
| `vein <type> <x> <z> [size_class]` | `tools/moc vein copper 120 -40 deposit` | A new surface vein centred on the column at the generated surface height, size class by id (default the smallest, `scattering`). Refused where its disc (with the vein spacing) reaches another vein. Outcrops appear in loaded chunks at once and in other chunks when they load; saved with the world. |
| `place <machine> <x> <y> <z> <rotation>` | `tools/moc place burner_mining_drill 30 71 -8 1` | Places the machine with its minimum corner at the cell, by the player's rules (free air in loaded chunks, solid ground under the bottom, clear of the player, a drill over a vein, a pump at water), without taking an item. A lift takes rotation 4 to 7 for going down. |
| `remove <x> <y> <z>` | `tools/moc remove 30 71 -8` | The entity covering the cell (its contents discarded), or else the block. The capsule stays. |
| `block <block> <x> <y> <z>` | `tools/moc block stone 30 70 -8` | Sets a block; refused where an entity stands. |
| `insert <item> <count> <x> <y> <z>` | `tools/moc insert coal 20 30 71 -8` | Items into the entity at the cell as an inserter would put them (fuel into a fuel slot); what does not fit is discarded. |
| `recipe <recipe> <x> <y> <z>` | `tools/moc recipe iron_gear 30 71 -8` | The chosen recipe of the crafting machine at the cell (work item 0050), through the assembler panel's path: its contents go to the inventory, and it is refused with the panel's reasons (a fixed recipe machine such as the chemical plant, a recipe of another category, contents that do not fit). |
| `filter <item> <x> <y> <z>` | `tools/moc filter hematite 30 71 -8` | The filter of the filter inserter or splitter at the cell, as its panel sets it (work item 0050). A splitter sends the item to its filter side, the left half unless the panel turned it, and everything else to the other half. |
| `blueprint <path>` | `tools/moc blueprint data/blueprints/tier1_factory.sjson` | Runs a blueprint file (below). |
| `tick <n>` | `tools/moc tick 3600` | Runs n ticks (up to 1000000) as fast as the machine allows, with no player input, up to one second of wall time per frame, then answers `ok ran n ticks, now at tick T`. Later lines wait for it. |
| `pause`, `resume` | `tools/moc pause` | Holds the ticks (like a pausing screen) or releases them. `tick` still runs while paused. |
| `save` | `tools/moc save` | Saves the world like the pause menu's Save. |
| `reload` | `tools/moc reload` | Loads and validates every content file (blocks, items, fluids, machines, recipes, technologies, quests, contracts, developer kits, biomes, tree species, veins) and reads the running world back under them through the save codec's content remap, like F8 and the Developer screen's Reload data (work item 0054). Answers `ok reloaded: items +1, recipes +1. Loaded chunks keep their blocks, ...` with the ids added and removed per table, or `error <file and problem>` with the old data and world kept. Loaded chunks keep their blocks; biome, tree and vein changes apply to chunks loaded later. `game.sjson` is not reloaded. |
| `screenshot [name]` | `tools/moc screenshot factory` | A PNG of the next frame at `$XDG_STATE_HOME/mine-oh-belowed/screenshots/<name>.png`, default name the UTC time (`2026-09-27T12-00-00Z`). Names hold letters, digits, `.`, `-` and `_`. The Developer screen's Screenshot button does the same. |
| `query player` | `tools/moc query player` | `position`, `block`, `yaw`, `pitch`, `flying`, `on_ground`, `cheat_speed`, one `item <id> <count>` line per item held, `pending_reward` lines. |
| `query world` | `tools/moc query world` | `seed`, `tick`, `day_ticks`, `day_length_ticks`, `pad`, `loaded_chunks`, `registered_veins`, `paused`. |
| `query veins [radius]` | `tools/moc query veins 100` | Registered veins (loaded columns and added veins) whose centre is within the radius (default 64) of the player: type, size class, layer, centre, radius, remaining units, id, `added`, `exhausted`. |
| `query entities [kind] [radius]` | `tools/moc query entities drill 40` | Entities with a cell within the radius (default 32): machine id, minimum corner, rotation. kind is a machine id or an entity kind (`drill`, `belt`, `inserter`, `furnace`, `chest`). |
| `query quests` | `tools/moc query quests` | The active quest and its chapter, `objective <n> <current>/<required>` lines, quests done, pending rewards. |
| `query contracts` | `tools/moc query contracts` | Venture credit and each open contract with its requests delivered. |
| `query stats <item>` | `tools/moc query stats iron_plate` | `produced`, `consumed`, `obtained`, `delivered`, `voided`, `rate_per_minute`, `inventory`. |
| `query textures` | `tools/moc query textures` | `textures <n>`, then one line per procedural texture with the texture editor's current parameters (0100, saved or not) in the form of `data/textures/procedural.sjson`, for example `{block = "hematite_ore", kind = "ore", seed = 1101, share = 0.2, blob_width = 0.65, crystal_size = 1, stone_grain = 8, stone_mottle = 16, ore_grain = 14, rim_strength = 0.15}`. Copy a line into the data file to make it the default. Answers without a world too. |

## Blueprints

An SJSON file with two keys:

```
origin = {vein = "iron"}   // or "pad", or [x, y, z]
commands = [
	"place burner_mining_drill -2 0 -2 1"
	"insert coal 20 -2 0 -2"
]
```

- `origin`: `"pad"` is the cell above the landing pad's centre, `{vein = "<type>"}` the cell above the centre of the registered surface vein of that type nearest the pad (the starter vein once its chunks loaded), `[x, y, z]` a world cell. Relative y 0 therefore stands on the surface.
- `commands`: `place`, `block`, `remove`, `insert`, `recipe` and `filter` lines with coordinates relative to the origin. They run in order; the first failure stops the run with `error blueprint command <n> (<line>): <reason>` (n counts from 1). What ran before stays.
- `tools/moc blueprint <path>` sends the path made absolute; the game reads it as given.

The factory benchmark (work item 0050, `doc/architecture.md`) builds its modules from the blueprints under `data/blueprints/benchmark/` (origin `[0, 0, 0]`, overridden with each copy's cell) as the manifest `data/blueprints/benchmark.sjson` lays them out: `smelting.sjson` (iron), `assembly.sjson` (gears, circuits, science pack 1 and a lab), `power.sjson` (steam) and `oil.sjson` (refinery, cracking, plastic, flare). The header comment of each describes it. The builder adds the veins the manifest lists for a module before its commands run; the commands go through the same `run_blueprint` as `tools/moc blueprint`.

`data/blueprints/tier1_factory.sjson` builds a burner iron line east of the iron starter vein: two drills onto a belt, two stone furnaces fed from the belt, a coal chest per furnace, output chests and an overflow chest at the belt's end, with starting coal. It needs flat ground over about 12 by 11 blocks east of the vein centre.

## Safety

- The socket exists only in developer mode and only the user can reach its directory.
- Commands write only inside the game's own directories: the save (`save`, and the world changes the next save stores) and the screenshots directory. `blueprint` reads the file it is given.
