# 0183: The command socket on the field world

Status: implementing (2026-10-05, in `.claude/worktrees/0183` on `item/0183` from `main` at 330c710, the specification approved the same day with the decisions below; M13 follow up, from the switch of 0179; whenever the assistant needs it)

## Goal

The assistant drives a field session through the command socket (`doc/commands.md`) as it drove the block world: where the player stands and looks, moving and turning them, the veins on the sphere, the entities with their frame cells, placing on a frame. Today `query player` reads the block player's fields, `teleport` takes block coordinates, `query veins` and `vein` read the block world's registry, and the commands that read `World.chunks` answer about an empty block world. A headless screenshot of a field session therefore shows the spawn's view only (2026-10-03, the pod and the outcrops never framed).

## Change

- `query player` answers the field player: feet as a world position and as latitude, longitude and height, yaw, pitch, the held tool and hotbar slot; `teleport <x> <y> <z>` takes a world position in metres and `teleport <latitude> <longitude>` a surface point; a new `look <yaw> <pitch>` sets the field player's look (a frame side write through the input record, as the other commands go).
- `query veins` lists the sphere veins (direction as latitude and longitude, radius, reservoir); `vein` adds one on the sphere at a surface point; `query entities` prints the frame and cell; `place` takes a frame and cell.
- Commands that only mean something on the block world answer `error no block world` instead of an empty answer.
- `doc/commands.md` updated per command.

## Verify

- The build and check commands of 0168; the socket's tests per changed command.
- A headless run: start a new world under `xvfb-run` with `--dev`, `look` at the pod and `screenshot`; the PNG shows the pod and an outcrop.

## Specification (design, 2026-10-05)

Designed against `main` at 3ee0d08. Nothing here depends on an item not yet landed.

### What changed since the item was written

A probe on the scratch copy (a test that starts `start_field_test_session` with the shipped planet and default seed, ticks three times and runs the lines through `execute_command_line`, see "What the design ran" below) answered, on a field session today:

| Line | Answer today on a field session | Why |
|---|---|---|
| `query player` | `position 352.50 35.00 64.50`, `block 352 35 64`, `yaw 45.0`, `pitch 0.0`, `flying false`, `no_clip false`, `on_ground false`, the items (right: `Player.inventory` is shared) | The block `Player` fields. `choose_world_start` (`main.odin`) still runs the block spawn search for every new world, `player_start_on(spawn)` puts the block body on block 352 34 64 at yaw 45, and nothing moves it since a field session never runs `tick_player`. These are the numbers the 0220 shots printed. |
| `query world` | `pad 352 34 64`, `loaded_chunks 0`, `registered_veins 3` | `landing_pad` is the block spawn search's site; `World.chunks` is empty (a field session makes no block chunk set, `session.odin`); the three veins are the sphere's starters. |
| `query veins` | nothing at radius 64; at 4096 the three sphere veins with `centre 0 0 0 radius 0` | `register_planet_veins` fills only `sphere_centre` and `sphere_radius`; the block fields stay zero and the distance is from the block body's column. |
| `query entities` | `entities 1`, `entity drop_capsule 354 35 66 rotation 0` | Only `BLOCK_FRAME` cells are listed. The one there is the block world's drop capsule that `make_simulation` places on the pad for every world, a field world included (a leftover, see the questions). The pod and its fixtures on frame 1 are not listed. |
| `fly on` | `ok fly on`, but `players[0].field.flying` stays false | `toggle_command_state` reads `Player.flying` and `serve_developer_request` toggles the block body (`apply_player_toggles`). The Developer screen's Fly and No clip toggles are dead on the field for the same reason. |
| `teleport 1 2 3`, `teleport pad` | `ok at 1.50 2.00 3.50`, `ok at 352.50 35.00 64.50` | Moves the block body; the field body does not move. |
| `vein iron 0 0` | `error a vein of radius 4 at 0 0 would overlap another vein` | `added_vein_overlaps` meets the sphere veins' zero block centres. |
| `place stone_furnace 0 0 0 0` | `error a player could not place it there ...` | Block cells in an empty block world. |
| `remove 0 0 0` | `error the chunk is not loaded` | Same. `block`, `insert`, `recipe`, `filter` and `blueprint` answer about the empty block world alike. |
| `camera third`, `look 10 10` | `error unknown command` | Not there. |
| `time`, `weather`, `give`, `take`, `kit`, `chapter`, `quest`, `research`, `unlock_all`, `cheat_speed`, `free_crafting`, `tick`, `pause`, `resume`, `save`, `reload`, `screenshot`, `query quests`, `query contracts`, `query stats`, `query textures` | work on the field as on the block world | They read nothing of the block world. |

The block world still exists to answer about: an old block save (`session_plays_field` is false for a file without `field_world`) and `--debug-terrain` start one, and the block world cluster is kept (`doc/code_map.md`). So every command keeps its block world form on a block session, and the field forms below apply when `simulation.field.enabled`.

Since the item was written: the crater (0199) puts the pod and the cabin spawn (0221) on a flat floor 3 m down, reaching 18 m from the home; the pod's collision volumes (0230) make the cabin a closed space, which is where 0220's pull in matters; the placement editor (0215) is a UI path, the socket does not go through it; the data edits directory (0228) changes nothing here.

### The seam

Every world writing line already reaches the simulation deterministically: the socket thread only queues the text (`queue_socket_line`, `loop.odin`), the text travels in the local player's next input record, and every machine runs it inside `simulation_tick`'s hook (`run_tick_lines`, `lockstep.odin`), after the simulated sets are derived and before the players tick, through `execute_command_line` and then `serve_command_request` and `serve_developer_request` (`developer.odin`). While the ticks are held in single player the lines run at once (`run_held_lines`). The new and changed writes follow the same path: the command parses and range checks the text, builds a `Developer_Request`, and `serve_developer_request` writes. Everything the serve does is integer: positions in position units, directions in `UNIT_VECTOR_ONE`, angles in `ANGLE_UNITS_PER_TURN`. Floats appear only in answer and query text, which no simulation state reads. The lockstep prediction is rebuilt from the confirmed player every frame (`rebuild_prediction`), so the view follows a write on the next frame.

`command_writes_simulation` gains `look`, `camera` and `crouch`. `query frames` is a query and stays a frame side line.

### Units

- World positions: metres with up to three decimals, the world position of `Field_Player.position` (the feet) over `POSITION_UNITS_PER_METRE` (4096). Each component within plus or minus `FAR_LIMIT_METRES`.
- Latitude and longitude: degrees with up to three decimals, laid out as `planet_spring_direction` does (latitude 90 towards +y, longitude 0 towards +x and 90 towards +z), the same as the F3 page's feet line (`append_field_feet_lines`). Latitude from -90 to 90, longitude from -180 to 180. Turned into `ANGLE_UNITS_PER_TURN` rounded to the nearest unit, so a teleport by latitude and longitude lands within half an angle unit (0.0055 degrees) of the point asked for: 0.38 m of arc at 8 km, 0.77 m at 16 km. The answer prints where it landed (83 asked reads back 83.0017).
- Height: metres above the sea level, `|feet| / POSITION_UNITS_PER_METRE - (radius_metres + sea_level_metres)` of `simulation.world.planet`. The F3 page measures from the radius instead; the socket says "height" for the sea's.
- Yaw: the bearing in degrees from the planet's north (`frame_north_tangent` of the player's up), turning the way the game's yaw turns (`field_heading`: from the forward towards forward cross up), 0 up to but not including 360. This is the convention the frames' yaw steps and the vein bearings already use (`planet_home_tangent`). The stored `Field_Player.yaw` counts from the carried `forward` (the spawn's heading, re-projected every tick), which means nothing to a caller, so the answers print the bearing and `look` stores its bearing by setting `forward` to the north tangent and `yaw` to the bearing.
- Pitch: degrees, up positive, from -89 to 89 (`FIELD_PITCH_LIMIT`).
- Decimal words go through an integer parser (`parse_decimal_word`), never through a float: the line runs on every machine, and an integer parse gives the same thousandths everywhere.

### Commands (as `doc/commands.md` will print them)

Changed and new rows of the commands table, each followed by its answer. "On the field" means `simulation.field.enabled`; "on the block world" means it is not.

- `teleport <x> <y> <z>`, `teleport <latitude> <longitude>`, `teleport pod`, `teleport pad`. On the field: feet at the world position in metres (exactly there; inside ground the next tick pushes them out), or on the generated surface at the latitude and longitude plus 0.25 m (`FIELD_SPAWN_CLEARANCE_MILLIMETRES`, the player drops onto it; the surface is the generation's, so an edit or a frame there is not seen), or in the pod's cabin (`field_pod_spawn`; refused without a pod). The look keeps its bearing and pitch. `teleport pad` answers `error no block world`. On the block world: unchanged (`<x> <y> <z>` a block, feet at its centre; `pad`); `teleport pod` and the two word form answer `error no field world`.
  - Answer on the field: `ok at <x> <y> <z> latitude <latitude> longitude <longitude> height <height>`, the feet as set, positions `%.3f`, latitude and longitude `%.4f`, height `%.2f`.
- `look <yaw> <pitch>`, `look at <x> <y> <z>` (new). On the field: the look's bearing and pitch, or the look from the eye towards the world position in metres (pitch limited to 89 degrees either way; `error the point is at the eye` when it is). The answer: `ok yaw <yaw> pitch <pitch>`, `%.1f`, read back from the stored state. On the block world: `error no field world`.
- `camera <first|third>` (new). On the field `Field_Player.camera_mode`, on the block world `Player.camera_mode`, as the Toggle camera binding sets it; the third person camera is pulled in by the walls as the frame draws it (0220). Answer `ok camera first` or `ok camera third`.
- `crouch <on|off>` (new). On the field: holds the crouch as Sneak held does (0218), whatever the Sneak hold setting, until `crouch off`; standing again waits for room, as after Sneak; no crouch while flying. Kept in the world (saved) like fly mode. Answer `ok crouch on` or `ok crouch off`. On the block world: `error no field world`.
- `fly <on|off>`, `noclip <on|off>`. On the field they now set the field body's `flying` and `no_clip` (they set the block body's before). Answer unchanged.
- `place <machine> <frame> <x> <y> <z> <rotation>` on the field: the machine with its minimum corner at the frame's cell, rotation 0 to 3, by the frame's rules (`frame_placement_refusal`: every footprint cell free, a machine other than a foundation with a solid cell under each bottom cell, a drill over a vein's disc) and the field's (no trunk in a cell, no player buried), no item taken and no placement counted, as the block form. A foundation takes one cell (its rotation is ignored); a free foundation or a machine on bare ground (a new frame) cannot be placed through the socket. Belts, belt poles and pipes are runs and refused, as is a machine no item places. Frame 0 answers `error no block world`. Answer `ok placed <machine> on frame <frame> at <x> <y> <z>`. The block form `place <machine> <x> <y> <z> <rotation>` is unchanged on the block world; five arguments on the field answer the field form's usage.
- `query player` on the field:
  ```
  player
  position <x> <y> <z>
  latitude <latitude>
  longitude <longitude>
  height <height>
  yaw <yaw>
  pitch <pitch>
  camera <first|third>
  crouching <true|false>
  crouch_held <true|false>
  flying <true|false>
  no_clip <true|false>
  on_ground <true|false>
  cheat_speed <true|false>
  hotbar_slot <1 to 8>
  tool <hand|material|foundation|belt_run|pipe_run|machine|torch>
  held <item id|none>
  item <id> <count>              (one per item, as today)
  pending_reward <id> <count>    (as today)
  ```
  Positions `%.3f`, latitude and longitude `%.4f`, height `%.2f`, yaw and pitch `%.1f`. `hotbar_slot` is `selected_hotbar_slot + 1`; `tool` is `Field_Player.tool` in lower case; `held` is the selected hotbar stack's item. No `block` line. The block world's form is unchanged.
- `query world` on the field: `world`, `seed`, `tick`, `day_ticks`, `day_length_ticks`, then `planet <id> radius <metres> sea_level <metres> spacing <millimetres>`, `home <latitude> <longitude>` (the world's home in whole degrees, `world.planet.home`, after the dry search of 0180), `pod frame <id> centre <x> <y> <z>` (the first alive pod's footprint centre, as `query entities` prints it; `pod none` without one), `frames <n>` (`len(frames.frames)`), `field_chunks <n>` (`len(field.world.chunks)`), `registered_veins <n>`, `paused`. No `pad` or `loaded_chunks` line. The block world's form is unchanged.
- `query veins [radius]` on the field: the registered veins with a disc on the sphere (`sphere_radius > 0`) whose disc centre lies within the radius in metres of the feet (straight line, default 128, `DEFAULT_FIELD_VEIN_QUERY_RADIUS_METRES`, since the starter veins lie 30 to 80 m from the home plus their radius), in registration order: `vein <type> size <size_class> layer surface latitude <latitude> longitude <longitude> surface <x> <y> <z> radius <metres> distance <metres> remaining <units> id <index> exhausted <true|false>`. `surface` is the generated surface on the disc centre's radial (`field_surface_under` of the field's `water_planet.generation`, clearance 0), the point to `look at` or to teleport above; `radius` is `sphere_radius` in metres `%.1f`; `distance` from the feet to `surface`, `%.1f`. The answer's first line stays `veins`.
- `query entities [kind] [radius]` on the field: the entities with an occupied cell on a frame other than frame 0 whose cell centre lies within the radius in metres of the feet (default 32), sorted by frame id and then by `coordinate_before` of the minimum corner: `entities <n>`, then `entity <machine> frame <id> cell <x> <y> <z> size <x> <y> <z> rotation <r> centre <x> <y> <z>`. `cell` is `Entity_Common.origin`, `size` is `Entity_Common.size` (the turned footprint), `centre` the midpoint of the centres of the corner cells `origin` and `origin + size - 1`, in metres. kind as today (a machine id, or an entity kind in lower case, so `pod` and `foundation` both find the pod, which lives in the foundations' pool). Runs hold no cell and are not listed (`belt_run.odin`: "A run is no entity"); the block frame's leftover drop capsule is not listed.
- `query frames [radius]` (new): the frames whose origin lies within the radius in metres of the feet (default 64), by id: `frames <n>`, then `frame <id> origin <x> <y> <z> pitch <millimetres> right <x> <y> <z> up <x> <y> <z> forward <x> <y> <z> cells <n>` with the axes as unit vectors `%.4f` and `cells` the frame's occupied count (`Frame_Table.extents[id].cell_count`, 0 when absent). On the block world: `error no field world`. Why it is added: `place` needs a frame and a cell, and choosing a cell next to the pod for a shot needs the frame's axes; `query entities` gives cells but not which way they run.
- Answering `error no block world` on the field, before any argument is parsed: `teleport pad`, `vein`, `remove`, `block`, `insert`, `recipe`, `filter`, `blueprint`, and `place` with frame 0.
- Answering `error no field world` on the block world, before any argument is parsed: `look`, `crouch`, `teleport pod`, `teleport <latitude> <longitude>`, `query frames`.
- Unchanged on both: everything else, `screenshot` included.

Usage rows in `command_usages` (`command.odin`), replacing or adding:

```
{"teleport <x> <y> <z> | teleport <latitude> <longitude> | teleport pod | teleport pad", "feet to the position (metres on the field, a block on the block world), the surface point, the pod's cabin or the landing pad"},
{"look <yaw> <pitch> | look at <x> <y> <z>", "the field player's look: bearing from north and pitch in degrees, or towards a point"},
{"camera <first|third>", "first or third person camera"},
{"crouch <on|off>", "hold the field player's crouch"},
{"place <machine> <x> <y> <z> <rotation> | place <machine> <frame> <x> <y> <z> <rotation>", "a machine by its minimum corner (on the field on a frame's cell), by the player's rules, no item taken"},
{"query veins [radius] | query entities [kind] [radius] | query frames [radius] | query stats <item>", "state around the player, or of an item"},
```

### Files and procedures

New file `src/command_field.odin` (tools cluster, prefix `command`), the field forms of the commands, called from `command.odin`'s dispatch when `command_context.simulation.field.enabled`:

- `NO_BLOCK_WORLD_PROBLEM :: "no block world"`, `NO_FIELD_WORLD_PROBLEM :: "no field world"`, `DEFAULT_FIELD_VEIN_QUERY_RADIUS_METRES :: 128`, `DEFAULT_FIELD_ENTITY_QUERY_RADIUS_METRES :: 32`, `DEFAULT_FRAME_QUERY_RADIUS_METRES :: 64`, `MAXIMUM_DECIMAL_DIGITS :: 12` (integer digits of a decimal word).
- `parse_decimal_word :: proc(word: string) -> (thousandths: i64, ok: bool)`: an optional minus, 1 to `MAXIMUM_DECIMAL_DIGITS` digits, optionally a dot and 1 to 3 digits (padded to thousandths); anything else (an exponent, a plus, an empty part, a fourth decimal) is not ok. No float. Called by `parse_ranged_decimal_word`.
- `parse_ranged_decimal_word :: proc(word: string, minimum, maximum: i64, what: string) -> (thousandths: i64, problem: string)`: bounds in thousandths; the problem reads `<what> must be a number from <minimum> to <maximum> with up to three decimals`, the bounds printed as whole numbers when they are. Every decimal argument goes through it.
- `parse_metres_words :: proc(words: []string, what: string) -> (position: World_Position, problem: string)`: three words, each within plus or minus `FAR_LIMIT_METRES * 1000`, then `thousandths * POSITION_UNITS_PER_METRE / 1000` per axis. Used by `teleport` and `look at`.
- `millidegrees_to_angle_units :: proc(millidegrees: i64) -> i32`: `millidegrees * ANGLE_UNITS_PER_TURN / 360_000` rounded to the nearest unit (half away from zero), integer only.
- `field_world_command :: proc(command_context: Command_Context, name: string, arguments: []string) -> (response: Command_Response, handled: bool)`: the field dispatch, called first by `execute_world_command` when the field is enabled; `handled` false lets every other command (give, time, tick, camera, fly, noclip and so on) fall through to `execute_world_command`'s switch. Handles `teleport`, `look`, `crouch`, `place`, `query player|world|veins|entities|frames` (other query subjects fall through), and the block only names `vein`, `remove`, `block`, `insert`, `recipe`, `filter`, `blueprint` (answers `command_error(NO_BLOCK_WORLD_PROBLEM)`).
- `command_field_teleport`, `command_look`, `command_crouch`, `command_field_place`: parse, range check, build the request, `serve_command_request`, answer. (`camera`, `fly` and `noclip` serve both worlds and stay in `command.odin`.) `command_field_teleport` computes the feet for the latitude form with `field_surface_under(simulation.field.world.water_planet.generation, World_Position(fixed_scale(planet_direction_at(latitude, longitude), generation.radius)), millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES))` and for `pod` with `field_pod_spawn(&simulation.world.entities, content.machines)`, then sends `Teleport_Field` with the feet. Both computations are integer and run inside the tick on every machine.
- `query_field_player`, `query_field_world`, `query_field_veins`, `query_field_entities`, `query_frames`: the answers above, reading only (floats allowed). `query_field_entities` reuses `entity_matches_kind` and `query_radius`.
- `field_player_bearing_degrees :: proc(player: Field_Player) -> f64`: `atan2(dot(heading, north cross up), dot(heading, north))` in degrees wrapped into [0, 360), with `heading := field_player_heading(player)`, `north := frame_north_tangent(player.up)`. Read by `query player` and the `look` answer.
- `metres_text :: proc(position: World_Position) -> string`: `%.3f %.3f %.3f`, temp allocator. `entity_centre :: proc(frame: Frame, common: Entity_Common) -> World_Position`: the midpoint of `frame_cell_centre` of the two corner cells.

`src/command.odin`:

- `command_writes_simulation`: add `"look", "camera", "crouch"`.
- `execute_world_command`: first `if command_context.simulation.field.enabled { if response, handled := field_world_command(command_context, name, arguments); handled { return response } }`; then for `look`, `crouch` (block world) answer `command_error(NO_FIELD_WORLD_PROBLEM)`; add `case "camera": return command_camera(command_context, arguments)`.
- `command_teleport` (block): a two word form or `pod` answers `NO_FIELD_WORLD_PROBLEM`.
- `command_query`: `case "frames"` answers `NO_FIELD_WORLD_PROBLEM` on the block world (the field dispatch handles it on the field); the usage line adds `frames`.
- `command_camera :: proc(command_context: Command_Context, arguments: []string) -> Command_Response`: `first` or `third`, `Set_Camera_Mode`, answer `camera <word>`.
- `toggle_command_state`: on the field `fly` and `noclip` read `players[player].field.flying` and `.no_clip`.
- `serve_command_request`: `before` and the log go through the field aware toggles (below).
- `command_usages`: the rows above.

`src/developer.odin`:

- `Developer_Action` appends, in this order after `Toggle_Free_Crafting`: `Teleport_Field`, `Set_Field_Look`, `Look_At_Field`, `Set_Camera_Mode`, `Hold_Field_Crouch`, `Place_On_Frame` (appended, so the existing values keep their numbers on the wire).
- `Developer_Request` adds `field_position: World_Position` (the feet of `Teleport_Field`, the target of `Look_At_Field`), `look_angles: [2]i32` (`Set_Field_Look`: bearing and pitch in angle units), `camera_mode: Camera_Mode`, `crouch_held: bool`, `frame: Frame_Id` (`Place_On_Frame`, with `machine`, `cell`, `rotation`); the comment above the struct names them.
- `serve_developer_request`: `Toggle_Fly_Mode` and `Toggle_No_Clip` on the field flip `player.field.flying` (through `toggle_field_flying`) and `player.field.no_clip`; the new cases: `Teleport_Field` calls `teleport_field_player(&player.field, request.field_position)`; `Set_Field_Look` calls `set_field_look(&player.field, request.look_angles.x, request.look_angles.y)`; `Look_At_Field` returns `"the point is at the eye"` when `look_field_player_at(&player.field, content.field.tuning, request.field_position)` is false; `Set_Camera_Mode` sets `player.field.camera_mode` on the field, `player.camera_mode` otherwise; `Hold_Field_Crouch` sets `player.field.crouch_held`; `Place_On_Frame` returns `place_on_frame_for_developer(...)`. The field only cases return `NO_FIELD_WORLD_PROBLEM` text (`"no field world"`, a literal here since developer.odin is in the simulation cluster) when `!state.field.enabled`, so a record from a malformed source changes nothing.
- `teleport_field_player :: proc(body: ^Field_Player, feet: World_Position)`: position and previous position to the feet, velocity, motion fraction cleared, `on_ground` false, `target`, `frame_target`, `tree_target` cleared, then `orient_field_player(body)` (the up from the new feet, the forward re-projected). Next to `teleport_player`.
- `place_on_frame_for_developer :: proc(state: ^Simulation_State, content: Simulation_Content, machine: Machine_Id, frame: Frame_Id, origin: World_Coordinate, rotation: u8) -> string`: refuses `frame == BLOCK_FRAME` (`"no block world"`), an unknown frame (`"no frame <id>"`), a machine `machine_takes_placement_command` refuses (`"<id> is not placed on a frame (a run's belt, pole or pipe, or a machine no item places)"`); a foundation's rotation is 0; then `snapped_placement_refusal` of `Field_Placement{kind = .Machine, machine, rotation, frame, cell = origin}` (`.Occupied` `"a cell of the footprint is taken"`, `.Unsupported` `"a bottom cell has no solid cell under it"`, `.No_Vein` `"a drill must stand over a vein's disc"`, `.Unknown_Frame` as above), `placement_cells_meet_a_trunk` (`"a tree is in the way"`), `field_footprint_buries_a_player` (`"it would bury a player"`); then `place_drill_on_frame` for a drill, `place_on_frame` otherwise. No `record_placed`, no inventory change, as `place_for_developer`.

`src/player_command.odin`: `developer_request_valid` lists the new actions: `Teleport_Field` and `Look_At_Field` with every `field_position` component within plus or minus `FAR_LIMIT_METRES * POSITION_UNITS_PER_METRE`; `Set_Field_Look` with the bearing within one turn either way and the pitch within `FIELD_PITCH_LIMIT`; `Set_Camera_Mode` with `enum_in_range(request.camera_mode)`; `Hold_Field_Crouch` true; `Place_On_Frame` with the machine in range, `machine_takes_placement_command` and `rotation < 4`. (The socket's lines travel as text and never reach it, but the switch is exhaustive and the Developer screen's records do.)

`src/player.odin`: `field_movement_toggles :: proc(player: Player) -> Movement_Toggles` (`{player.field.flying, player.field.no_clip}`); `log_movement_toggles` keeps its signature and calls a new `log_movement_toggle_change :: proc(before, after: Movement_Toggles, cause: string, tick: u64)`, which `serve_command_request` and `apply_developer_command` call with the field's toggles on the field (`session_movement_toggles :: proc(state: ^Simulation_State, index: int) -> Movement_Toggles` picks the pair), so the log names a socket or screen toggle on the field too.

`src/player_field.odin`:

- `Field_Player` adds `crouch_held: bool` after `crouching`, commented: the developer's hold (`crouch on`, 0183), read like Sneak held by `update_field_crouch`; a save from before 0183 loads it false (the save reads fields by name, as `crouching` of 0218).
- `tick_field_player`: `update_field_crouch(world, frames, tuning, player, .Sneak in input.held || player.crouch_held)`. The prediction runs through `tick_field_player` (`move_and_aim_field_player`), so it crouches alike.
- `set_field_look :: proc(player: ^Field_Player, bearing, pitch: i32)`: `forward = frame_north_tangent(player.up)`, `yaw = bearing %% ANGLE_UNITS_PER_TURN`, `pitch` clamped to `FIELD_PITCH_LIMIT`.
- `look_field_player_at :: proc(player: ^Field_Player, tuning: Field_Player_Tuning, target: World_Position) -> bool`: the unit direction from `field_player_eye(player^, tuning)` to the target (false for none), `forward = tangent_of(player.up, direction)`, `yaw = 0`, `pitch = clamp(angle_of_sine(fixed_dot(direction, player.up)), -FIELD_PITCH_LIMIT, FIELD_PITCH_LIMIT)`.

`src/world_field_vector.odin`: `angle_of_sine :: proc(sine: i64) -> i32`, the angle from minus to plus a quarter turn whose `fixed_sine` is the largest not above `sine` (clamped to plus or minus `UNIT_VECTOR_ONE`), by a binary search over the 16385 candidates; integer only.

`src/generation_planet.odin`: `planet_direction_at :: proc(latitude, longitude: i32) -> [3]i64` (angle units), the body of `planet_spring_direction`, which then returns `planet_direction_at(degrees_to_angle_units(spring.latitude_degrees), degrees_to_angle_units(spring.longitude_degrees))`: the same integers, so no generated ground moves.

`src/diagnostics.odin`: `field_feet_coordinates :: proc(position: World_Position) -> (latitude, longitude, distance_metres: f64)` taken out of `append_field_feet_lines` (which calls it), used by `query_field_player` and `query_field_veins`.

`src/ui_developer.odin`, `src/ui_screens.odin`, `src/loop.odin`: `Screen_Context` gains `field_session: bool`, set by `make_screen_context` from `session.simulation.field.enabled`; `developer_toggles` shows the field's toggles on the field (`field_movement_toggles(screen_context.player^)`), so the Fly and No clip toggles, which now act on the field body, show its state. The Developer screen's Teleport button stays the block world's (a question below).

No save layout change beyond the named `crouch_held` (no remap, no version bump, the 0218 precedent). No network layout change beyond the reflected `Developer_Request` fields and actions, which every machine of a session shares (the join refuses another build). No string keys (the socket's text is not translated). No data keys.

### Tests (in `src/command_test.odin`)

A helper `Field_Command_Test` (the `^Session` of `start_field_test_session(test_field_game_config(), make_field_test_game_content())`, its `field_test_content`, a `Command_Control`), `make_field_command_test`, `destroy_field_command_test` (`end_session`), `run_field_command`, and expectations like `expect_command_ok`; ticks through `tick_field_test_simulation` with an empty frame. Each test names what it asserts:

1. `test_decimal_words_parse_and_range_check`: `parse_decimal_word` gives 1500 for `1.5`, -1 for `-0.001`, 83000 for `83`, refuses `1.2345`, `abc`, `""`, `-`, `.5`, `5.`, `1e3`, `+1` and a 13 digit integer; `parse_ranged_decimal_word("90.001", -90000, 90000, "the latitude")` gives a problem naming the bounds.
2. `test_angle_of_sine_inverts_the_fixed_sine`: for every 97th angle from minus to plus a quarter turn, `angle_of_sine(fixed_sine(angle))` is within one unit of the angle; `UNIT_VECTOR_ONE` gives a quarter, its negation minus a quarter.
3. `test_field_query_player_answers_the_field_body`: on a new field world, `query player` holds `position ` followed by the feet's metres (`metres_text(players[0].field.position)`), `latitude 83.`, `longitude 132.` (the default seed's home, which 0180 does not move), a `height` line whose value is between 0 and 20, `camera first`, `crouch_held false`, `flying false`, `hotbar_slot 1`, `tool `, and no `\nblock ` line.
4. `test_field_query_world_veins_entities_and_frames`: `query world` holds `home 83 132`, `pod frame `, `field_chunks `, no `\npad `; `query veins` lists three `layer surface` veins (iron, copper, coal by type id) each with a `distance` under 100; `query entities pod` lists one entity whose frame is the pod's (`find_test_pod`) and whose `cell` is `pod_origin`; `query entities` does not list `drop_capsule`; `query frames` lists the pod's frame with `pitch 500`.
5. `test_field_teleport_to_a_surface_point_lands_on_the_ground`: `teleport <home latitude> <home longitude + 1.5>` (formatted from `world.planet.home`, 26 m from the cabin with the default seed, outside the crater) answers ok with a latitude within 0.006 of 83; the feet are 0.25 m over `field_surface_under` at that direction; within 60 ticks `on_ground` is true and the feet lie within 0.3 m of the generated surface along the up. The design's probe landed in 11 ticks with a drop of 0.256 m.
6. `test_field_teleport_to_metres_and_to_the_pod`: `teleport <x> <y> <z>` with the feet's current metres plus 2 m along x sets `position` to exactly the parsed position units and `previous_position` alike; `teleport pod` puts the feet back in the cabin (`feet_in_test_cabin`); `teleport pad` and `teleport 91 0` answer errors (`no block world`, the latitude's bounds).
7. `test_field_look_sets_the_bearing_and_the_camera_follows`: `look 90 -30` answers `yaw 90.0 pitch -30.0`; `field_player_bearing_degrees` is within 0.1 of 90 and `pitch` is `millidegrees_to_angle_units(-30000)`; after one tick with no input both hold; the first person `field_camera` of `field_player_view(players[0].field, tuning, 1, 0)` looks along a direction whose dot with the north tangent is within 0.01 of 0, with `north cross up` within 0.01 of cos 30 degrees and with the up within 0.01 of -0.5; `look 0 95` and `look 0 x` answer errors.
8. `test_field_look_at_a_point_faces_it`: `look at` the pod's footprint centre (from `query entities pod`'s `centre`, after `move_test_players_out_of_the_pod`) answers ok; the look direction's dot with the unit direction from the eye to that point is above cos 1 degree; `look at` the eye's own metres answers `error the point is at the eye`.
9. `test_field_camera_third_is_pulled_in_in_the_cabin`: at the cabin spawn `camera third` sets `players[0].field.camera_mode` to `.Third_Person`; `pulled_in_field_camera(&session.simulation, field_content, view, .Third_Person, THIRD_PERSON_DISTANCE, 0.6, 70)` lies closer to the eye than `field_camera`'s unpulled position by at least 0.5 m (the hull pulls it in, 0220); `camera first` sets the mode back and `pulled_in_field_camera` then equals `field_camera` (first person is never pulled); `camera side` answers the usage.
10. `test_field_crouch_holds_and_releases`: outside the pod `crouch on`, one tick: `crouching` true and `field_player_eye` is `crouch_eye_height` over the feet; ten more ticks with no input: still crouching; `crouch off`, one tick: standing; `fly on`, `crouch on`, one tick: not crouching while flying.
11. `test_field_fly_and_noclip_act_on_the_field_body`: `fly on` sets `players[0].field.flying` (the block body's `flying` stays false), `fly on` again changes nothing, `noclip on` sets `field.no_clip`, `query player` shows `flying true` and `no_clip true`, `fly off` clears it.
12. `test_field_place_on_a_frame_cell`: after `move_test_players_out_of_the_pod`, with the pod's frame id F and the inventory's counts noted (if a moved player's capsule reaches cell 8 0 0, use the mirrored cell -7 on the side away from the door and say so): `place wooden_foundation F 8 -1 0 0` and `place wooden_chest F 8 0 0 0` answer ok and an entity stands at cell 8 0 0 of F (`entity_at`); the inventory counts are unchanged; `place wooden_chest F 8 0 0 0` again answers the taken text; `place wooden_chest F 9 0 0 0` the unsupported text; `place wooden_chest F 0 0 0 0` the taken text (the pod's cell); `place wooden_chest 0 8 0 0 0` `no block world`; `place wooden_chest 999 8 0 0 0` `no frame 999`; `place belt F 8 1 0 0` the run text; `place wooden_chest F 8 1 0 4` the rotation's bounds; `query entities chest` lists `entity wooden_chest frame F cell 8 0 0`.
13. `test_field_refuses_the_block_world_commands`: on the field `teleport pad`, `vein iron 0 0`, `remove 0 0 0`, `block stone 0 0 0`, `insert coal 1 0 0 0`, `recipe nothing 0 0 0`, `filter coal 0 0 0`, `blueprint /nonexistent` each answer an error whose text is `no block world`.
14. `test_block_world_refuses_the_field_commands`: on `make_command_test`'s block world `look 0 0`, `look at 0 0 0`, `crouch on`, `teleport pod`, `teleport 10 20`, `query frames` answer `no field world`; `camera third` sets `players[0].camera_mode`; `teleport 3 20 -4` still lands at 3.5 20 -3.5 and `query player` still has its `block` line.

The existing `test_command_teleport_time_and_toggles` and `test_command_queries` stay as they are (block world). A field session in the tests needs no state directory (`start_field_test_session` makes no save), and no test takes a screenshot.

### Docs

- `doc/commands.md`:
  - The opening paragraph: after "read the state back (0053)" add "; on a field world (0179, the default since the play build switch) the commands read and move the field player, and the ones that only mean something on the block world answer `error no block world` (0183)".
  - The paragraph on `command_writes_simulation`: "every command of the table below from `give` to `blueprint` except `weather`" becomes "every command of the table below from `give` to `blueprint`, and `look`, `camera` and `crouch`, except `weather`".
  - Protocol, the coordinates bullet becomes: "On the block world coordinates are world block coordinates as the diagnostics show them. On a field world a position is metres in the world's frame (the planet's centre at the origin, +y through latitude 90), up to three decimals; latitude and longitude are degrees as the F3 page shows them (longitude 0 towards +x, 90 towards +z); a height is metres above the sea level; a yaw is the bearing in degrees from north, turning the way the game's yaw turns, and a pitch is degrees up. A frame cell is the frame's id and the cell's three integers ([architecture.md](architecture.md), Frames). Rotations: 0 points to +x, 1 to +z, 2 to -x, 3 to -z (on a frame along its axes). Names are the ids in the data files. Numbers outside a command's bounds are refused."
  - The commands table: the rows of "Commands" above (teleport, look, camera, crouch, fly and noclip noting the field body, place with both forms, query player and query world with "On a field world:" sentences listing the keys, query veins, query entities, query frames).
  - A new section `## The field world` after Commands: one bullet listing the commands that answer `error no block world` on a field world, one listing the ones that answer `error no field world` on the block world, one saying `teleport <latitude> <longitude>` reads the generated surface (an edit or a frame there is not seen, the player drops onto what is there), and one with the shot recipe: "`pause`, then `tick 800` (the arrival's fall), then the framing lines, `screenshot`: with the ticks held the lines run at once and only `tick` advances the world, so a gamepad the machine sees cannot turn the view between them."
  - "A query radius is 1 to 4096 (`MAXIMUM_QUERY_RADIUS`)." add "; on a field world it is metres".
- `doc/developer_tools.md`, the Toggles row: "Fly mode; no clip (0112: flight passes through blocks)" becomes "Fly mode; no clip (0112: flight passes through blocks; on a field world the field player's, 0183)".
- `doc/build.md`: names the socket only for Windows; no change.
- `doc/code_map.md`: the tools section's file list gains `- \`command_field.odin\`: the field world's forms of the commands and queries (0183).` after `command.odin`; the header's file count and the tools row's Files and Lines follow (the implementer reads the new numbers off `python3 tools/code_graph.py`); the "Reaches into" record changes only if `--check` asks.
- `doc/log/2026-10-05.md`, appended after the 0220 section:

  ```
  ## The command socket on the field (0183)

  Tags: commands, socket, field, teleport, look, camera, crouch, frames, screenshots, lockstep, 0183, m14

  The socket's commands read the block player while the default world became the field, so a field session's answers came from a body that never moved (`query player` printed the block spawn search's 352.50 35.00 64.50) and `fly`, `teleport` and `place` wrote where nothing looked. On a field world they now read and move the field player: positions in metres, latitude and longitude, a height above the sea, the look as a bearing from north and a pitch. The stored yaw counts from a heading carried along since the spawn, which a caller cannot know, so `look` sets the heading to north and the yaw to the bearing, and every answer prints the bearing. The new `look`, `camera` and `crouch` go through the input record and `serve_developer_request` as the other writes do, integer only, so a lockstep session stays equal; `crouch` is a hold kept in the field body and saved (a hold left out of the save would be lost on a join's snapshot and part the machines), since the Sneak hold setting's default would release a one tick crouch at once. `place` takes a frame and a cell and the frame's rules, with no free placement (a foundation on the pod's frame below the floor row starts one). `vein` is refused on the field: the sphere's veins are a function of the seed and the home and shape the generated ground, so an added one would need the generation to read saved veins. The commands that only mean something on the block world answer `no block world`, and the field's new ones `no field world` on an old block save. The Developer screen's fly and no clip toggles, dead on the field for the same reason, act on the field body too. The point of it all is framing headless screenshots without xdotool: with the ticks held (`pause`) the lines run at once and only `tick` moves the world, so the couch's gamepad cannot turn the view between a `look` and a `screenshot`.
  ```

### Hand-back check lines that apply

- A number parsed from text is range checked: every argument. Integers through `parse_integer_word` (i32) and `parse_ranged_word` (frame id 1 to `max(i32)`, rotation 0 to 3, query radii 1 to 4096); decimals through `parse_ranged_decimal_word` (metres within `FAR_LIMIT_METRES`, latitude -90 to 90, longitude -180 to 180, yaw -360 to 360, pitch -89 to 89). Satisfied by tests 1, 6, 7 and 12.
- A changed save layout loads an old save: `Field_Player.crouch_held` is new; the save reads fields by name and an older save loads it false (as `crouching` of 0218). No remap, no log line needed, since nothing is renamed or reinterpreted; the comment on the field says so.
- Tests never touch the machine's state directory or settings: the field sessions of the tests make no save and no screenshot.
- The rest (frame drawn memory, file writes, start-up loads, shared budgets, HUD lists, UI audit cases) do not apply: the change draws nothing new and writes no file.

### Verify

- `taskset -c 8-15 nice -n 10 ./build.sh check`
- `taskset -c 8-15 nice -n 10 ./build.sh check-android`
- `taskset -c 8-15 nice -n 10 ./build.sh test`
- `python3 tools/check_docs.py`
- `python3 tools/code_graph.py --check doc/code_map.md`

The headless run (the main agent, after landing in the worktree's build), from the recipe of `tmp/camera_shot.sh` (0220): `Xvfb :96 -screen 0 1280x720x24` running, `DISPLAY=:96`, `XDG_RUNTIME_DIR` under the main checkout's `tmp/` (a worktree path is too long for the socket), the state, config and data homes under `tmp/xdg0183/`, then:

```
taskset -c 8-15 nice -n 10 ./build/mine-oh-belowed --dev --seed=20260927 --name=socket-shot &   # wait for the socket file
tools/moc pause
tools/moc tick 800                       # the arrival's fall (600 ticks) and its settle
tools/moc query world                    # home 83 132, pod frame F centre PX PY PZ
tools/moc query veins                    # three veins with latitude, longitude and surface points
tools/moc teleport 83 133.5              # 26 m from the cabin, outside the crater (reach 18 m)
tools/moc tick 30                        # drops onto the ground; tick runs with no player input
tools/moc look at PX PY PZ               # the pod's centre
tools/moc camera third
tools/moc screenshot pod_third           # the pod across the crater, the player's back in front
tools/moc look at VX VY VZ               # one vein's surface point from query veins
tools/moc camera first
tools/moc screenshot outcrop_first       # an outcrop
tools/moc place wooden_foundation F 8 -1 0 0
tools/moc place wooden_chest F 8 0 0 0
tools/moc query entities chest           # its centre CX CY CZ
tools/moc look at CX CY CZ
tools/moc screenshot frame_place         # the chest on its foundation beside the pod
tools/moc teleport pod
tools/moc crouch on
tools/moc tick 10
tools/moc camera third
tools/moc screenshot cabin_crouch_third  # the pulled in camera of 0220 over a crouched body
kill -9 <pid>                            # then pgrep to see it is gone
```

The ticks stay held from the first line to the last, so nothing but `tick` moves the world and a gamepad the machine sees cannot turn the view. Pass: `pod_third` shows the pod and the crater's rim, `outcrop_first` an ore outcrop, `frame_place` a chest on a foundation beside the hull, `cabin_crouch_third` the cabin with the camera inside the hull; every `query player` between them names the position, bearing and camera mode the lines set.

### Questions the design answered

- Which commands are new: `look` (both forms), `camera`, `crouch`, `query frames`. `look at` is added beside the item's `look <yaw> <pitch>` because the item's own Verify says "`look` at the pod": with a bearing alone the caller would have to compute the bearing from two positions on a sphere. `camera` and `crouch` because the 0220 shots needed them and the only other way is xdotool. `query frames` because `place` needs a frame's axes to choose a cell.
- `camera` works on both worlds (the block body has `camera_mode` too, set the same way); `look` and `crouch` only on the field, since the block world is kept for old saves and nothing needs them there.
- `teleport pod` instead of `teleport pad` on the field: the cabin is the field's spawn (`field_pod_spawn`), the pad is a block world site the field never uses.
- `vein` on the field is refused (`no block world`). The sphere's discs are planned from the seed, the radius and the home (`plan_planet_veins`), shape the generated outcrops through `planet_sample`, and are left out of the save (`Vein.sphere_centre` is `save:"-"`, set again at session start); "a data edit must not reshape the unedited ground round saved chunks" (`generation_planet_veins.odin`). An added vein would need the generation to read saved veins and the save to keep their discs: a design of its own, beyond framing screenshots. A reservoir without an outcrop would show nothing on a screenshot.
- `remove`, `insert`, `recipe`, `filter` and `blueprint` get no frame form: the item does not ask for them and framing does not need them. They answer `no block world`.
- `crouch` is a saved hold in `Field_Player`, not a one tick press: with the default Sneak hold setting (`sneak_hold = .Hold`) `update_sneaking` releases a crouch the next tick unless Sneak stays pressed, and the socket is no input device. A `save:"-"` hold would be lost in a join's snapshot (the snapshot is the save's bytes) and part the machines.
- `look` sets `forward` to the north tangent and stores the bearing as `yaw`, instead of solving for a yaw against the carried forward, which would need an integer arc tangent. `look at` sets `forward` to the target's tangent and `yaw` to 0, and needs only an integer arc sine (`angle_of_sine`, a binary search on `fixed_sine`).
- The look lands in the tick's hook, before the players tick, so that tick's turn input adds to it; with the ticks held (the shot recipe) or a `tick` command there is none.
- Teleport by latitude and longitude goes to the generated surface plus the spawn clearance, not to the edited ground or a frame: `field_surface_under` is integer, needs no loaded chunk, and the player then drops onto whatever is there.
- Default radii: veins 128 m on the field (the starters lie up to 85 m from the home; with the default seed the probe's numbers put the coal vein's disc centre 72 m from the cabin's feet, the iron's 33 m and the copper's 46 m, so 64 would miss the coal), entities 32 m and frames 64 m.
- The Developer screen's fly and no clip toggles follow the serve change, since the same action serves both, and the screen would otherwise show the block body's flags.

### Questions for the main agent

1. `vein` on the field: accept the refusal, or file a work item for added sphere veins (the generation reading saved veins, the save keeping their discs)? The design leaves it to M14's vein scattering.
2. The Developer screen's Teleport button on the field still teleports the block body to the pad (dead, like fly was). Fold a one line fix into this item (on the field it sends `Teleport_Field` with the cabin spawn), or a work item of its own?
3. A field world carries the block world's drop capsule on frame 0 at the block pad (`make_simulation` places it for every world; the probe listed `entity drop_capsule 354 35 66`). The quests' reward target is the pod's locker (0210), so it looks like a leftover. Not touched here; a work item?
4. `query frames` is beyond the item's list; keep it or strike it?
5. `crouch on` persists in the save until `crouch off`. Acceptable for a developer command, or should loading a world clear it (a log line and a reset at load)?

### What the design ran

- A `git archive` copy of 3ee0d08 under the scratchpad, with `build.sh`'s `test` taking extra flags, and a probe test file there; run with `PROBE_FLAGS=-define:ODIN_TEST_NAMES=game.test_probe_0183_field_socket_today taskset -c 8-15 nice -n 10 ./build.sh test`. It printed the answers in the table of "What changed" verbatim and confirmed that `fly on` leaves `field.flying` false and that the three sphere veins have zero block centres.
- A second probe test, `game.test_probe_0183_teleport_to_surface`, the same way: the default seed's home is 83 132 at 8000 m with the sea at -11 m and no arrival in the test config; a teleport to the generated surface at latitude 83, longitude 133.5 plus 0.25 m, built from `fixed_sine` and `field_surface_under` as specified, moved the feet 26.2 m from the cabin and the player stood on the ground after 11 ticks, 0.256 m lower.

### Decisions at the approval (main agent, 2026-10-05)

1. Question 1: `vein` stays refused on the field. The sphere veins come from the seed and the home and shape the ground; an added vein is a generation change, which the look items of 0237 (veins and caves) own if ever.
2. Question 2: folded in. On the field the Developer screen's Teleport sends `Teleport_Field` with the cabin spawn's feet (`field_pod_spawn`), the same request `teleport pod` builds, so the button stops moving the block body; one test asserts it (a field session, the button's action, the field feet at the spawn).
3. Question 3: the block world's drop capsule in a field world is item 0262.
4. Question 4: `query frames` stays; `place` needs a frame's axes and the F3 page shows none.
5. Question 5: acceptable. `crouch on` is a developer's hold and a developer tool; `doc/commands.md` says it persists in the save until `crouch off`.
