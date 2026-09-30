# Command socket

A running game in developer mode listens on a Unix domain socket for command lines: give items, skip chapters, add a vein, build a blueprint, run ticks, take a screenshot, read the state back (0053). `tools/moc` is the client.

- Source: `command_socket.odin` (paths, queue, command log), `command_socket_posix.odin` (the socket), `command.odin` (protocol and commands), `developer.odin` (the requests the commands serve), `loop.odin` (`save`, `reload`, ticks, screenshots).
- Linux only, not on Windows ([build.md](build.md), What the Windows build lacks).
- The simulation never reads the socket: lines run on the main thread after the frame's ticks, through the same `serve_developer_request` the Developer screen uses ([developer_tools.md](developer_tools.md)).

## For the assistant

1. Start the game with developer mode: `--dev`, or the Developer mode setting. The log says `command: listening on <path>`.
2. `tools/moc <command words>` (`tools/moc give iron_plate 50`) prints the response and exits 0 on `ok`, 1 on `error`, 2 when the socket is missing or refuses the connection. `tools/moc -` sends one command per stdin line and prints each response.
3. `tools/moc help` lists the commands; `tools/moc query player` and `tools/moc query world` show where things stand.
4. `tools/moc screenshot base` answers the PNG's path under `$XDG_STATE_HOME/mine-oh-belowed/screenshots/`; the file exists once the game drew its next frame.
5. Every line and response line goes to the game log (`$XDG_STATE_HOME/mine-oh-belowed/log.txt`) prefixed `command:`.

## Transport

- Path: `$XDG_RUNTIME_DIR/mine-oh-belowed/command.sock` when the runtime directory is absolute, else `$XDG_STATE_HOME/mine-oh-belowed/command.sock`, else `~/.local/state/mine-oh-belowed/command.sock`. The directory is made with mode 0700, so only the user connects.
- Open while developer mode is on; switching the setting off closes it and removes the file. A failure to listen is logged once (`error: command socket: ...`).
- A stale socket file is removed at start. A socket another running game listens on is left alone and this game does not listen.
- The loop polls once per frame without blocking. Several clients may connect; lines run in arrival order, one response per line.

## Protocol

- One command per line. Words are separated by spaces or tabs; a double quoted word may hold spaces, with `\"` and `\\` inside.
- `#` outside quotes starts a comment. Blank and comment lines get no response.
- A response is `ok`, `ok <text>` or `error <text>`, then further lines for queries, then a line holding only `.`.
- Coordinates are world block coordinates as the diagnostics show them. Rotations: 0 points to +x, 1 to +z, 2 to -x, 3 to -z. Names are the ids in the data files.
- Commands other than `help`, `pause`, `resume`, `screenshot`, `reload` and `query textures` need a loaded world (`error no world is loaded`).
- Changes land between two ticks. While a pausing screen is open the world changes at once but time does not move.

## Commands

| Command | What it does |
|---|---|
| `help` | The command list. |
| `give <item> <count>` | Items into the inventory, the rest into the drop capsule's pending rewards. Count 1 to 10000 (`MAXIMUM_DEVELOPER_GRANT_COUNT`). |
| `take <item> <count>` | Items out of the inventory; the answer says how many were taken. |
| `kit <chapter>` | The chapter's kit from `data/dev_kits.sjson`. |
| `chapter <n>` | Completes every quest before chapter n with its rewards (items to the capsule, recipes and technologies unlocked). One past the last chapter completes all. Gives no kit. |
| `quest finish` | Completes the active quest with its rewards (deliveries not taken), logs its message and activates the next. An error once every quest is done. |
| `research <technology>` | Marked researched as a quest reward does; an infinite technology gains one level. |
| `unlock_all` | Every recipe and technology. |
| `teleport <x> <y> <z>`, `teleport pad` | Feet into that block's centre, or onto the landing pad. |
| `time <dawn\|noon\|dusk\|midnight>` | Sets the time of day. |
| `weather <clear\|overcast\|rain\|fog\|auto>` | Forces a weather kind at full intensity (0063); `auto` returns to the schedule. Kept in the session, not saved; with the Weather setting off the weather stays clear. |
| `fly <on\|off>` | Fly mode, swept against blocks unless no clip is on. |
| `noclip <on\|off>` | Flying passes through blocks (0112). Walking ignores it. |
| `cheat_speed <on\|off>` | Faster movement and hand mining ([developer_tools.md](developer_tools.md)). |
| `vein <type> <x> <z> [size_class]` | A new surface vein centred on the column at the generated surface height; size class by id from the `size_classes` of `data/veins.sjson`, default the first (`scattering`). Refused for a deep vein type and where its disc (with the vein spacing) reaches another vein. Outcrops appear in loaded chunks at once, in others when they load; saved with the world. |
| `place <machine> <x> <y> <z> <rotation>` | The machine with its minimum corner at the cell, by the player's rules (free air in loaded chunks, solid ground under it, clear of the player, a drill over a vein, a pump at water), no item taken. A belt lift takes rotation 4 to 7 for going down. |
| `remove <x> <y> <z>` | The entity covering the cell (contents discarded), or else the block. An entity that cannot be picked up, such as the capsule, is refused. |
| `block <block> <x> <y> <z>` | Sets a block in a loaded chunk; refused where an entity stands. |
| `insert <item> <count> <x> <y> <z>` | Items into the entity at the cell as an inserter would put them (fuel into a fuel slot); what does not fit is discarded. |
| `recipe <recipe> <x> <y> <z>` | The crafting machine's recipe, through the panel's path: its contents go to the inventory, refused with the panel's reasons (a fixed recipe machine, another category, contents that do not fit). |
| `filter <item> <x> <y> <z>` | The filter of the filter inserter or splitter at the cell, as its panel sets it. A splitter sends the item to its filter side (the left half unless the panel turned it), the rest to the other half. |
| `blueprint <path>` | Runs a blueprint file (below). |
| `tick <n>` | Runs n ticks (1 to 1000000) with no player input, up to one second of wall time per frame, then answers `ok ran n ticks, now at tick T`. Later lines wait for it. |
| `pause`, `resume` | Holds the ticks like a pausing screen, or releases them. `tick` still runs while paused. |
| `save` | Saves the world like the pause menu's Save. |
| `reload` | The content reload of F8 and the Developer screen ([architecture.md](architecture.md), Data driven content). Answers `ok reloaded: ...` with the ids added and removed per table, or `error <file and problem>` with the old data and world kept. |
| `screenshot [name]` | A PNG of the next frame at `<state>/screenshots/<name>.png`, default name the UTC time (`2026-09-27T12-00-00Z`). A name holds letters, digits, `.`, `-` and `_`, up to 64, not starting with a dot. |
| `query player` | `position`, `block`, `yaw`, `pitch`, `flying`, `no_clip`, `on_ground`, `cheat_speed`, one `item <id> <count>` line per item held, `pending_reward` lines. |
| `query world` | `seed`, `tick`, `day_ticks`, `day_length_ticks`, `pad`, `loaded_chunks`, `registered_veins`, `paused`. |
| `query veins [radius]` | Registered veins (loaded columns and added veins) whose centre lies within the radius (default 64) of the player's column: type, size, layer (`surface` or `deep`), centre, radius, remaining units, id, `added`, `exhausted`. |
| `query entities [kind] [radius]` | Entities with a cell within the radius (default 32): machine id, minimum corner, rotation. kind is a machine id or an entity kind in lower case (`drill`, `belt`, `inserter`, `furnace`, `chest`, and so on). |
| `query quests` | The active quest and its chapter, `objective <n> <current>/<required>` lines, quests done, pending rewards. |
| `query contracts` | Venture credit, each open contract with its tier, offer tick and requests delivered. |
| `query stats <item>` | `produced`, `consumed`, `obtained`, `delivered`, `voided`, `rate_per_minute`, `inventory`. |
| `query textures` | `textures <n>`, then one line per procedural texture with the texture editor's current parameters (saved or not) in the form of `data/textures/procedural.sjson`. Copy a line into the data file to make it the default. |

A query radius is 1 to 4096 (`MAXIMUM_QUERY_RADIUS`).

## Blueprints

An SJSON file with exactly two keys:

```
origin = {vein = "iron"}   // or "pad", or [x, y, z]
commands = [
	"place burner_mining_drill -2 0 -2 1"
	"insert coal 20 -2 0 -2"
]
```

- `origin`: `"pad"` is the cell above the landing pad's centre; `{vein = "<type>"}` the cell above the centre of the registered surface vein of that type nearest the pad (the starter vein once its chunks loaded); `[x, y, z]` a world cell. Relative y 0 stands on the surface.
- `commands`: `place`, `block`, `remove`, `insert`, `recipe` and `filter` lines with coordinates relative to the origin, run in order. The first failure stops the run with `error blueprint command <n> (<line>): <reason>` (n from 1); what ran before stays.
- The game reads the path as given; `tools/moc blueprint <path>` sends it absolute.
- `data/blueprints/tier1_factory.sjson` builds a burner iron line east of the iron starter vein: two drills onto a belt, two stone furnaces fed from it, a coal chest per furnace, output chests and an overflow chest at the belt's end, with starting coal. It needs flat ground over about 12 by 11 blocks east of the vein centre.
- The factory benchmark ([architecture.md](architecture.md), Performance) runs its modules through the same `run_blueprint`.

## Safety

- The socket exists only in developer mode, in a directory only the user reaches.
- Commands write only inside the game's own directories: the save (`save`, and the world changes the next save stores) and the screenshots directory. `blueprint` reads the file it is given.
