# Command socket

A running game in developer mode listens on a Unix domain socket for command lines: give items, skip chapters, add a vein, build a blueprint, run ticks, take a screenshot, read the state back (0053); on a field world (0179, the default since the play build switch) the commands read and move the field player, and the ones that only mean something on the block world answer `error no block world` (0183). `tools/moc` is the client.

- Source: `command_socket.odin` (paths, queue, command log), `command_socket_posix.odin` (the socket), `command.odin` (protocol and commands), `command_field.odin` (the field world's forms, 0183), `command_input.odin` (the input commands and `query ui`, 0341), `input_injected.odin` (the virtual devices they set), `developer.odin` (the requests the commands serve), `loop.odin` (`save`, `reload`, ticks, screenshots).
- Linux only, not on Windows ([build.md](build.md), What the Windows build lacks).
- The simulation never reads the socket. A line that changes the world (`command_writes_simulation`: every command of the table below from `give` to `blueprint`, and `look`, `camera`, `crouch` and `seat`, except `weather` and `arrival_camera`, which only the local session keeps) goes into the local player's next input record and runs at the start of that tick, through the same `serve_developer_request` the Developer screen uses ([developer_tools.md](developer_tools.md)); its answer comes once that tick ran, and later lines wait for it. Other lines (queries, `screenshot`, `save`, `tick`) run on the main thread after the frame's ticks. The input commands (`press` to `type`, 0341) are neither kind: they set the virtual devices the frames read under `--input=none`, and a world action they press reaches the simulation in the local player's input record as a device's does (Input, below).

## For the assistant

1. Start the game with developer mode: `--dev`, or the Developer mode setting. The log says `command: listening on <path>`.
2. `tools/moc <command words>` (`tools/moc give iron_plate 50`) prints the response and exits 0 on `ok`, 1 on `error`, 2 when the socket is missing or refuses the connection. `tools/moc -` sends one command per stdin line and prints each response. `tools/moc --until <regular expression> <command words>` sends the command again after each answer until a line of an answer matches (Python's `re.search`), at most 600 times, and prints the last answer: exit 0 on a match, 1 on an error answer or when the tries ran out, 2 on a bad expression or a missing socket. The game reads the socket once a frame, so each try lands in a later frame and `tools/moc --until '^top recipes$' query ui` waits for a screen without a sleep.
3. `tools/moc help` lists the commands; `tools/moc query player` and `tools/moc query world` show where things stand.
4. `tools/moc screenshot base` answers the PNG's path under `$XDG_STATE_HOME/mine-oh-belowed/screenshots/`; the file exists once the game drew its next frame.
5. Every line and response line goes to the game log (`$XDG_STATE_HOME/mine-oh-belowed/log.txt`) prefixed `command:`.
6. `tools/capture_clip.sh <name> [frames=60] [crop=140x150+580+160]` (0286) captures a clip from a session paused where wanted: per frame `tick 1` and `screenshot <name>_NN`, waiting for the file, then `<name>_strip.png` (every third frame cropped, ten a row) and `<name>.gif` (every frame at 640x360) in the screenshot directory. `MOC` names the client (default `tools/moc`), `SCREENSHOTS` the directory.
7. `python3 tools/motion_stats.py <frames directory> [--name NAME] [--crop WxH+X+Y] [--fps N] [--steady WxH+X+Y] [--window PIXELS]` (0289) prints the same lines for every series of frames `<name>_NN.png` (a capture's, or footage cut with `ffmpeg`, with its rate as `--fps`, default 60): the motion energy, its 30 fps form and its concentration, the brightness and its share in the bands under 2, 2 to 6, 6 to 15 and over 15 Hz (also resampled to 30 fps, so a 60 fps clip and 30 fps footage compare), the flow by phase correlation (degrees with 0 right and 90 up, net and median pixels a frame and crop widths a second, consistency), the streaks' orientation and coherence, the persistence and its decorrelation time, and writes `<name>_delta_strip.png` beside the frames (every third difference amplified eight times, ten a row). Statistics run on the crop reduced to at most 64 pixels a side, so crops of different sizes compare. No command turns the view's buffet off alone, so `--steady` subtracts a box's own motion from the flow (the porthole's ring against the buffet). `--window` gives the window's width in the frame's pixels (it may be wider than the crop) and prints every speed a second time in window widths a second, so a game crop and a footage crop of different shares of their windows compare.
8. A headless capture (0341) starts the game under Xvfb with `--dev --input=none`, so it reads no keyboard, mouse or controller of the machine: the input commands reach every screen (Input, below), `tools/moc --until` waits for one, and `screenshot` takes it.

## Transport

- Path: `$XDG_RUNTIME_DIR/mine-oh-belowed/command.sock` when the runtime directory is absolute, else `$XDG_STATE_HOME/mine-oh-belowed/command.sock`, else `~/.local/state/mine-oh-belowed/command.sock`. The directory is made with mode 0700, so only the user connects.
- Open while developer mode is on; switching the setting off closes it and removes the file. A failure to listen is logged once (`error: command socket: ...`).
- A stale socket file is removed at start. A socket another running game listens on is left alone and this game does not listen.
- The loop polls once per frame without blocking. Several clients may connect; lines run in arrival order, one response per line.

## Protocol

- One command per line. Words are separated by spaces or tabs; a double quoted word may hold spaces, with `\"` and `\\` inside.
- `#` outside quotes starts a comment. Blank and comment lines get no response.
- A response is `ok`, `ok <text>` or `error <text>`, then further lines for queries, then a line holding only `.`.
- On the block world coordinates are world block coordinates as the diagnostics show them. On a field world a position is metres in the world's frame (the planet's centre at the origin, +y through latitude 90), up to three decimals; latitude and longitude are degrees as the F3 page shows them (longitude 0 towards +x, 90 towards +z); a height is metres above the sea level; a yaw is the bearing in degrees from north, turning the way the game's yaw turns, and a pitch is degrees up. A frame cell is the frame's id and the cell's three integers ([architecture.md](architecture.md), Frames). Rotations: 0 points to +x, 1 to +z, 2 to -x, 3 to -z (on a frame along its axes). Names are the ids in the data files. Numbers outside a command's bounds are refused.
- Commands other than `help`, `pause`, `resume`, `view_distance`, `screenshot`, `reload`, `query textures`, `query ui` and the input commands need a loaded world (`error no world is loaded`).
- Changes land at the start of the next tick. While a pausing screen is open in single player the world changes at once but time does not move.

## Commands

| Command | What it does |
|---|---|
| `help` | The command list. |
| `give <item> <count>` | Items into the inventory, the rest into the pending rewards, which land in the reward target. Count 1 to 10000 (`MAXIMUM_DEVELOPER_GRANT_COUNT`). |
| `take <item> <count>` | Items out of the inventory; the answer says how many were taken. |
| `kit <chapter>` | The chapter's kit from `data/dev_kits.sjson`. |
| `chapter <n>` | Completes every quest before chapter n with its rewards (items to the reward target, recipes and technologies unlocked). One past the last chapter completes all. Gives no kit. |
| `quest finish` | Completes the active quest with its rewards (deliveries not taken), logs its message and activates the next. An error once every quest is done. |
| `research <technology>` | Marked researched as a quest reward does; an infinite technology gains one level. |
| `unlock_all` | Every recipe and technology. |
| `teleport <x> <y> <z>`, `teleport <latitude> <longitude>`, `teleport pod`, `teleport pad` | On a field world: the feet at the world position in metres (exactly there; inside ground the next tick pushes them out), or on the generated surface at the latitude (-90 to 90) and longitude (-180 to 180) plus 0.25 m (`FIELD_SPAWN_CLEARANCE_MILLIMETRES`, the player drops onto it), or in the pod's cabin (`field_pod_spawn`, refused without a pod). The look keeps its bearing and pitch. Answers `ok at <x> <y> <z> latitude <latitude> longitude <longitude> height <height>`, the feet as set. On the block world: the feet into that block's centre, or onto the landing pad. |
| `look <yaw> <pitch>`, `look at <x> <y> <z>` | Field world only: the look's bearing from north (-360 to 360) and pitch (-89 to 89) in degrees, or the look from the eye towards the world position in metres (the pitch limited to 89 degrees either way; `error the point is at the eye` within a centimetre of it). Answers `ok yaw <yaw> pitch <pitch>` read back from the stored look. |
| `camera <first\|third>` | First or third person camera, as the Toggle camera binding sets it, on either world; the field's third person camera is pulled in by walls as the frame draws it (0220). |
| `crouch <on\|off>` | Field world only: holds the crouch as Sneak held does (0218), whatever the Sneak hold setting, until `crouch off`; standing again waits for room, and there is no crouch while flying. The hold is kept in the world and saved, so a loaded world is still crouched until `crouch off`. |
| `seat <stand\|sit>` | Field world only: stands up from the pod's chair (at the cabin's spawn, the look kept) or sits in the first pod's chair as Interact on it does (0223), answering `ok seat standing` or `ok seat seated`; refused `the world is falling` while the arrival falls, and `there is no seat` when sitting finds no pod with a seat. |
| `time <dawn\|noon\|dusk\|midnight>` | Sets the time of day. |
| `weather <clear\|overcast\|rain\|fog\|auto>` | Forces a weather kind at full intensity (0063); `auto` returns to the schedule. Kept in the session, not saved; with the Weather setting off the weather stays clear. |
| `arrival_camera <x> <y> <z> \| arrival_camera off` | During the fall, puts the viewport's camera at the point in cells of the pod's model frame (x and z centred, y up from the base, each within 200), looking at the pod's middle and moved with the pod, for captures of the wake from outside (0304); `off` returns to the seat. Render only: kept in the session, not saved, and outside the descent the seat's camera holds. |
| `fly <on\|off>` | Fly mode, swept against blocks unless no clip is on; on a field world the field player's (0183). |
| `noclip <on\|off>` | Flying passes through blocks (0112). Walking ignores it. On a field world the field player's (0183). |
| `cheat_speed <on\|off>` | Faster movement and hand mining ([developer_tools.md](developer_tools.md)). |
| `free_crafting <on\|off>` | Crafts take no ingredients (0234, [developer_tools.md](developer_tools.md)). |
| `vein <type> <x> <z> [size_class]` | A new surface vein centred on the column at the generated surface height; size class by id from the `size_classes` of `data/veins.sjson`, default the first (`scattering`). Refused for a deep vein type and where its disc (with the vein spacing) reaches another vein. Outcrops appear in loaded chunks at once, in others when they load; saved with the world. |
| `place <machine> <x> <y> <z> <rotation>`, `place <machine> <frame> <x> <y> <z> <rotation>` | The machine with its minimum corner at the cell, no item taken and no placement counted. On the block world by the player's rules (free air in loaded chunks, solid ground under it, clear of the player, a drill over a vein, a pump at water); a belt lift takes rotation 4 to 7 for going down. On a field world on the frame's cell, rotation 0 to 3, by the frame's rules (every footprint cell free, a machine other than a foundation with a solid cell under each bottom cell, a drill over a vein's disc) and the field's (no trunk in a cell, no player buried); a foundation takes one cell and ignores the rotation. A free foundation or a machine on bare ground (a new frame) is not placed this way; belts, belt poles and pipes are runs and refused, as is a machine no item places, and frame 0 answers `error no block world`. Answers `ok placed <machine> on frame <frame> at <x> <y> <z>`. |
| `remove <x> <y> <z>` | The entity covering the cell (contents discarded), or else the block. An entity that cannot be picked up, such as the capsule, is refused. |
| `block <block> <x> <y> <z>` | Sets a block in a loaded chunk; refused where an entity stands. |
| `insert <item> <count> <x> <y> <z>`, `insert <item> <count> <frame> <x> <y> <z>` | Items into the entity at the cell as an inserter would put them (fuel into a fuel slot); what does not fit is discarded. On a field world (0274) into the entity at the frame's cell, answering `ok frame <frame> at <x> <y> <z>`. |
| `recipe <recipe> <x> <y> <z>` | The crafting machine's recipe, through the panel's path: its contents go to the inventory, refused with the panel's reasons (a fixed recipe machine, another category, contents that do not fit). |
| `filter <item> <x> <y> <z>` | The filter of the filter inserter or splitter at the cell, as its panel sets it. A splitter sends the item to its filter side (the left half unless the panel turned it), the rest to the other half. |
| `blueprint <path>` | Runs a blueprint file (below). |
| `tick <n>` | Runs n ticks (1 to 1000000) with no player input (under `--input=none` with the first viewport's, Input, Timing), up to one second of wall time per frame; a tick whose chunks are not there yet (a loaded field world's set while it generates) waits for a later frame as a lockstep tick does. Then answers `ok ran n ticks, now at tick T`. Later lines wait for it. |
| `pause`, `resume` | Holds the ticks like a pausing screen, or releases them. `tick` still runs while paused. |
| `view_distance <metres>` | Sets the View distance setting (0343, [ui.md](ui.md), Display) to 256 to 1024 whole metres as its Settings row does, answering `ok view distance <metres> m`; the next frame draws at it and the farther nodes and tree tiles stream in over the frames after. Presentation only, so a joined machine may use it; the change persists in `config.d/90-settings.sjson` at the end of the frame like any setting. |
| `save` | Saves the world like the pause menu's Save. |
| `reload` | The content reload of F8 and the Developer screen ([architecture.md](architecture.md), Data driven content). Answers `ok reloaded: ...` with the ids added and removed per table, or `error <file and problem>` with the old data and world kept. |
| `screenshot [name]` | A PNG of the next frame at `<state>/screenshots/<name>.png`, default name the UTC time (`2026-09-27T12-00-00Z`). A name holds letters, digits, `.`, `-` and `_`, up to 64, not starting with a dot. |
| `press <action> [frames]`, `press <gamepad\|keyboard\|mouse> <control> [frames]` | `--input=none` (Input, below): the control down for the frames (1 to 600, `MAXIMUM_PRESS_FRAMES`, default 1), then up; refused while the control is held. Answers `ok pressed gamepad SOUTH (Confirm) for 1 frame` (`frames` from 2) once the UI saw it go up. |
| `hold <action>`, `hold <gamepad\|keyboard\|mouse> <control>` | `--input=none`: the control down until released, at most 16 keys at once (`RAW_KEYS_DOWN_CAPACITY`). Answers `ok holding gamepad SOUTH (Jump)`. |
| `release <action>`, `release <gamepad\|keyboard\|mouse> <control>`, `release all` | `--input=none`: a held control up; `all` lets go of every control, rests the sticks and triggers and drops untyped text, the pointer stays. Answers `ok released gamepad SOUTH (Jump)`, `ok released all`. |
| `stick <left\|right> <x> <y>` | `--input=none`: the stick at x (right) and y (up), each -1 to 1 with up to three decimals, held until set again. Answers `ok stick left at 0.500 -1`. |
| `trigger <left\|right> <value>` | `--input=none`: the trigger at 0 to 1 with up to three decimals, held until set again; past 0.5 it presses its actions. Answers `ok trigger right at 1`. |
| `pointer <x> <y>` | `--input=none`: the mouse to the render pixel, 0 to the width or height minus 1, a mouse's move for one frame. Answers `ok pointer at 960 540`. |
| `type <text>` | `--input=none`: one word (quoted for spaces) of 1 to 512 printable ASCII characters (`MAXIMUM_TYPED_TEXT_LENGTH`) into the open text field. Answers `ok typed 9 characters`. |
| `query player` | `position`, `block`, `yaw`, `pitch`, `flying`, `no_clip`, `on_ground`, `cheat_speed`, one `item <id> <count>` line per item held, `pending_reward` lines. On a field world: `position` (metres, three decimals), `latitude` and `longitude` (four decimals), `height` (above the sea level), `yaw` (the bearing from north) and `pitch`, `camera` (`first` or `third`), `seat` (`standing`, `strapped` or `seated`, 0223), `crouching`, `crouch_held`, `flying`, `no_clip`, `on_ground`, `cheat_speed`, `hotbar_slot` (1 to 8), `tool` (the held tool of `Field_Held_Tool` in lower case: hand, material, foundation, belt_run, pipe_run, machine or torch), `held` (the selected hotbar stack's item or `none`), then the `item` and `pending_reward` lines; no `block` line. |
| `query world` | `seed`, `tick`, `day_ticks`, `day_length_ticks`, `pad`, `loaded_chunks`, `registered_veins`, `paused`. On a field world: `seed`, `tick`, `day_ticks`, `day_length_ticks`, `planet <id> radius <metres> sea_level <metres> spacing <millimetres>`, `home <latitude> <longitude>` (whole degrees), `pod frame <id> centre <x> <y> <z>` (the first pod's footprint centre, `pod none` without one), `frames`, `field_chunks`, `registered_veins`, `paused`. |
| `query veins [radius]` | Registered veins (loaded columns and added veins) whose centre lies within the radius (default 64) of the player's column: type, size, layer (`surface` or `deep`), centre, radius, remaining units, id, `added`, `exhausted`. On a field world the sphere's veins whose disc centre lies within the radius (default 128 m) of the feet, in registration order: `vein <type> size <size_class> layer surface latitude <latitude> longitude <longitude> surface <x> <y> <z> radius <metres> distance <metres> remaining <units> id <index> exhausted <true\|false>`, where `surface` is the generated surface over the disc's centre (the point to `look at` or teleport above) and `distance` is from the feet to it. |
| `query entities [kind] [radius]` | Entities with a cell within the radius (default 32): machine id, minimum corner, rotation. kind is a machine id or an entity kind in lower case (`drill`, `belt`, `inserter`, `furnace`, `chest`, and so on). On a field world the entities with a cell centre on a frame other than frame 0 within the radius (metres) of the feet, by frame and minimum corner: `entity <machine> frame <id> cell <x> <y> <z> size <x> <y> <z> rotation <r> centre <x> <y> <z>`, `size` the turned footprint and `centre` the footprint's centre in metres; `pod` and `foundation` both find the pod, and runs, which hold no cell, are not listed. |
| `query frames [radius]` | Field world only: the frames whose origin lies within the radius (default 64 m) of the feet, by id: `frame <id> origin <x> <y> <z> pitch <millimetres> right <x> <y> <z> up <x> <y> <z> forward <x> <y> <z> cells <n>`, the axes as unit vectors and `cells` the occupied count. `place` needs a frame and a cell, and the axes say which way the cells run. |
| `query quests` | The active quest and its chapter, `objective <n> <current>/<required>` lines, quests done, pending rewards. |
| `query contracts` | Venture credit, each open contract with its tier, offer tick and requests delivered. |
| `query stats <item>` | `produced`, `consumed`, `obtained`, `delivered`, `voided`, `rate_per_minute`, `inventory`. |
| `query textures` | `textures <n>`, then one line per procedural texture with the texture editor's current parameters (saved or not) in the form of `data/textures/procedural.sjson`. Copy a line into the data file to make it the default. |
| `query ui` | The first viewport's UI after its last pass, on every backend and without a world (Input, below). |

A query radius is 1 to 4096 (`MAXIMUM_QUERY_RADIUS`); on a field world it is metres.

## Input

`--input=none` (0341, [input.md](input.md), The none backend) starts a game that reads no keyboard, mouse or controller. Its first viewport reads virtual devices instead, a gamepad in SDL3's numbering, a keyboard and a mouse, which the input commands set. The UI's focus navigation, the pointer, typed text and the world actions take them as they take a device's, and a world action reaches the simulation only in the local player's input record. Under `sdl3` and `raylib` the input commands answer `error input commands need --input=none`: a virtual pointer and a physical mouse have no common position.

- A target is an action name (`Confirm`) or `<gamepad|keyboard|mouse> <control>` in the bindings' vocabulary ([input.md](input.md), Bindings): SDL button names and `LEFT_TRIGGER`, `RIGHT_TRIGGER`, raylib key names, raylib mouse button names (not the wheel words, no trackpad). An action resolves through the effective bindings to its first gamepad control the backend reads (the one its glyph shows), else its first key or mouse button, and the answer names the control. A pressed control carries every action bound to it, as a device's does: Confirm's `SOUTH` is Jump in the world.
- The pointer is in the screenshot's pixels (render pixels, the window's on X11), origin top left, starting at 0 0. A move is the mouse's delta for one frame: over a screen it moves the UI's pointer, in the world it turns the view as a mouse does (`look` frames a shot). `press mouse LEFT` clicks where it is.
- `type` fills the frames' typed text, 16 characters a frame; only an open text field takes it, and it holds no key. `press keyboard <key>` holds a key and types no character: `press keyboard ENTER` ends an entry (Enter is Confirm too, as on a keyboard), `press keyboard BACKSPACE` deletes a character.
- `press` is a press of frames, made for the screens. A world action that reads the held control (walking's Jump, Mine, Place) takes `hold`, `tick <n>`, `release` in a stepped session.
- Errors answer at once and change nothing: `usage: <the row's usage>`, `unknown action or device "<word>"`, `<Action> is bound to no gamepad control, key or mouse button`, `<device> <control> is no control of the virtual devices` (an unknown name, a wheel word, `trackpad`), `<label> is held; release it first`, `<label> is not held`, `16 keys are held already`, a number outside its bounds (`the frames`, `x`, `y`, `the trigger`), `the text holds 1 to 512 printable ASCII characters`.
- The glyphs start on the gamepad's ([input.md](input.md), The none backend); `press gamepad GUIDE`, bound to nothing, switches back to them without an action.

`query ui` answers the first viewport after its last UI pass (the notes in parentheses are not part of the answer):

```
ui
screens pause settings        (bottom to top, the Screen names in lower case; screens none)
top settings                  (top none)
device gamepad                (the glyphs shown, or keyboard_mouse)
pointer 200.0 100.0 mouse     (render pixels; the source none, mouse, trackpad or touch)
focus 20 40 200 80            (the focused widget's x, y, width and height in render pixels; focus none)
text_field closed             (open while a text field takes typed text)
backend none                  (sdl3, raylib or none)
```

### Timing

- A frame reads the input, runs the ticks, serves the socket, then runs the UI. A line run in frame N changes the virtual devices; frame N+1's read takes the change.
- An input command answers once a frame's UI saw its last change: `press` three frames after it ran (down, up, the UI pass of the release, so a tap that acts on release is done), the others two, `type` one more per 16 characters. Later lines wait behind it as behind `tick`, so a `query ui` or `screenshot` after it sees the result.
- Ticks follow the wall clock while the session runs. While only the socket's `pause` holds them (no pausing screen open on the first viewport) the frames' presses and pointer moves wait in the tick input instead of being dropped, and `tick <n>` runs its ticks from the first viewport's input the way a frame's ticks run: one input record a tick, the held controls on every tick, the waiting presses on the first. So `hold Mine`, `tick 120`, `release Mine` holds Mine for exactly 120 ticks. A pausing screen still drops the presses. Under `sdl3` and `raylib` `tick` takes no input, so a controller the machine sees moves nothing between framing lines.
- On a joined machine and on a host with others the input commands work frame by frame; `tick` and `pause` stay refused there (Multiplayer).

## The field world

- On a field world `teleport pad`, `vein`, `remove`, `block`, the five word `insert`, `recipe`, `filter`, `blueprint`, and `place` and `insert` on frame 0 answer `error no block world` before any argument is read. The sphere's veins come from the seed and the home and shape the generated ground, so `vein` adds none there.
- On the block world (an old block save, `--debug-terrain`) `look`, `crouch`, `seat`, `teleport pod`, `teleport <latitude> <longitude>` and `query frames` answer `error no field world` before any argument is read.
- `teleport <latitude> <longitude>` reads the generated surface: an edit or a frame there is not seen, and the player drops onto what is there.
- Framing a screenshot: `pause`, then `tick 800` (the arrival's fall), then the framing lines (`teleport`, `look at`, `camera`, `crouch`), then `screenshot`. With the ticks held the lines run at once and only `tick` advances the world, and under `--input=none` no device of the machine is read at all.

## Multiplayer

A lockstep session ([architecture.md](architecture.md), Multiplayer) runs every machine from the same input records, so a command must reach every machine to keep them equal.

- Every game hosts its own world on the LAN while it plays (0188): the title's Multiplayer screen lists the games that answer and joins one, or joins the address typed under the list. The flags below do the same from the command line.
- `--server` runs the world of the command line (`--load=<world>`, or a new one from `--seed` and `--name`) without a window, an input backend or a local player, and hosts it on `--port=<n>` alone, or without `--port` on the first free port of the game's range. It logs `server: running` and runs until SIGINT or SIGTERM stops it, saving on the autosave interval of the settings and once more when stopped (on Windows Ctrl+C ends it without that save). It does not open the command socket.
- `--join=<address>[:port]` starts the game, joins the server or game at that address instead of showing the title (the port defaults to 47317, the first of the range), and plays the host's world; the phone needs an IP address, since it has no resolver. The title shows a notice while the join runs; a host that does not answer within ten seconds, or refuses another build or other game data, leaves the title with a toast.
- Ports: a game or server listens on TCP 47317 (`DEFAULT_NETWORK_PORT`), or the next free one up to 47326 when another game on the machine holds it, and logs `network: hosting on port N` (`server: hosting on port N` for `--server`); every host answers the LAN's discovery on UDP 47316 (`DISCOVERY_PORT`). A firewall that blocks incoming connections must pass both; Fedora Workstation's default zone (`FedoraWorkstation`) opens every port above 1024, so nothing is needed there, while a restrictive zone such as `FedoraServer` needs `sudo firewall-cmd --add-port=47316/udp --add-port=47317-47326/tcp` (with `--permanent` and a second run to keep them). A home router's inbound blocking is the internet side and does not apply between machines on one LAN. Without the UDP port the screen lists nothing and joining by address still works; without the TCP range nobody can join.
- `--server` cannot be combined with `--join`, `--debug-terrain`, `--chapter` or `--give`, `--join` not with the flags that start a world, `--port` only with `--server`.
- On a joined machine the socket's world changing lines travel in the local player's input record, so every machine runs them at the same tick, for the local player; a blueprint's file is read on the machine that sent the line. The input commands work there too, frame by frame as a device's input does (0341). `tick` and `pause` answer `error` there and on a host another machine joined or is joining (a host alone runs them as single player), since one machine cannot hold the others' ticks, and so does `reload` (every machine must run the same content; F8 and the Developer screen's reload are refused with a toast too).

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
- `data/blueprints/tier1_factory.sjson` builds a burner iron line east of the iron starter vein: two drills onto a belt, two stone furnaces fed from it, a coal chest per furnace, output chests and an overflow chest at the belt's end, with starting coal. It needs flat ground over about 20 by 27 blocks round the vein centre (x -2 to 17, z -13 to 13), since a stone furnace is 10 by 10 by 12 blocks (0212).
- The factory benchmark ([architecture.md](architecture.md), Performance) runs its modules through the same `run_blueprint`.

## Safety

- The socket exists only in developer mode, in a directory only the user reaches.
- Commands write only inside the game's own directories: the save (`save`, and the world changes the next save stores) and the screenshots directory. `blueprint` reads the file it is given.
