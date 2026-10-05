# 0223: The arrival seen from the chair

Status: verified (2026-10-05)

## Goal

A new world starts in the chair of the pod, strapped in: the player looks around freely from the first tick and sees the fiery inferno of the atmospheric entry raging outside the windows, the cabin round them with the screens lit, the hit shaking the cabin. Controls beyond the look are withheld until touchdown is confirmed; then the player unbuckles, stands up and walks. The chair stays a seat afterwards: the player can sit in it at any time. Today the descent hides the pod and draws a shader window over the whole viewport (0200, [doc/presentation.md](../presentation.md), The arrival), and the player stands in the cabin from the first tick (0221).

## Controls

No new binding. From the first tick the look turns the seated eye; the sticks' walk, Jump, Sneak, Mine, Place and the tools do nothing while strapped in. Once touchdown is confirmed the HUD shows Interact on the chair as "Unbuckle"; Interact (X, the touch tap on the chair) unbuckles and stands the player in the cabin. Afterwards Interact on the chair sits the player (the look free, the walk and the tools off) and Interact again stands them up; Jump does nothing while seated (A jumps alone, 0233). The chair takes Interact like a switch, so the touch tap routes to it (0233).

## Change

- The seated state per player (strapped during the fall, seated later) in the simulation, deterministic, with the eye in the chair's seat read from the pod's record; a joiner arriving after the fall spawns standing as today.
- The pod drawn during the descent, moving with the camera along the path, the window shader's flames moved from the viewport's edges to the windows' glass, the planet seen through them along the path as today; the hit's shake kept; "touchdown confirmed" as a cue and a HUD line.
- Docs: `doc/presentation.md` (The arrival), `doc/architecture.md` (The field session, the start), `doc/content.md` (the pod), `doc/input.md` (Interact on the chair), `doc/hud.md`, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the fall ignores the walk and the tools and takes the look; Interact before touchdown does nothing, after it stands the player; Interact on the chair seats and unseats; the arrival's presentation leaves the hash alone; two machines hash alike through a fall with input.
- The couch and the phone: a new world from the chair to the first steps outside, the flames in the windows.

## Specification (design, 2026-10-05)

Model units below are cells of the model's frame as the OBJ and `pod.collision.sjson` write them (x and z centred on the unrotated footprint, y from its bottom, +x the door). No model change: the chair (`chair()` of `tools/models/machines/pod.py`, facing the model's -z) and the five portholes (`PORTHOLES`, open holes lined by a black sleeve, no glass) are used as they are.

### Data

- `data/machines.sjson`, pod record, after `open_cells`:
  - `seat = {cells = {from = {x = 3, y = 0, z = 6}, to = {x = 4, y = 3, z = 7}}, eye = [-2.0, 2.7, 1.0], facing = "-z"}`. `cells`: the chair's footprint cells (content.md already names x 3 to 4, z 6 to 7), inclusive, inside the footprint, overlapping no `open_cells` box and no fixture box. `eye`: the seated eye in model units, inside the cells' span (model x -3 to -1, y 0 to 4, z 0 to 2) with `MODEL_FOOTPRINT_TOLERANCE_CELLS` slack: 1.35 m over the floor, 0.175 m before the headrest's face (collision box z 1.35), over the back's top (y 2.5). `facing`: `+x`, `-x`, `+z` or `-z`, the seated look at yaw 0.
  - `windows`, the glass of the portholes, 0.2 cells out from the lining along each sleeve (computed from `PORTHOLES`, `wall()`, `FACET`, the OBJ's z being Blender's -y), presentation only: `{centre = [3.473, 3.798, -2.005], normal = [-0.755, -0.490, 0.436], radius = 0.4}`, `{centre = [1.031, 3.848, -3.846], normal = [-0.226, -0.490, 0.842], radius = 0.4}`, `{centre = [-2.005, 3.798, -3.473], normal = [0.436, -0.490, 0.755], radius = 0.4}`, `{centre = [-3.873, 3.798, 1.038], normal = [0.842, -0.490, -0.226], radius = 0.4}`, `{centre = [-1.991, 3.848, 3.449], normal = [0.436, -0.490, -0.755], radius = 0.4}`. The normal points into the cabin.
  - The header comment gains both keys: `seat` (optional, pods only) and `windows` (optional, pods only, at most 8; centre inside the footprint with the lamps' slack, normal of length 0.5 to 2, normalised at load, radius 0.05 to 2 cells). The `open_cells` paragraph's "there is no seated posture" goes.
- `data/game.sjson`: `arrival_window_pitch_degrees` and its sentence go (the look is the player's now); "the players held in its cabin" becomes "the players strapped into the pod's chair, the look free".
- `data/strings/en.sjson`: `hint_unbuckle = "Unbuckle"`, `hint_sit = "Sit"`, `hint_stand = "Stand"`, `mc_touchdown_confirmed = "Touchdown confirmed, Contractor. Unbuckle when the dust settles."`.
- `data/shaders/arrival.fs` rewritten for one window's disc: uniforms `flame_strength`, `seconds`, `flame_seed` (`aspect` and `wall_color` go); `p = fragment_texture_coordinate - vec2(0.5)`, `d = length(p) - 0.5`, `discard` for `d > 0.0`; the flames grow from the rim with `lead = clamp(0.5 + p.y, 0.0, 1.0)` (texture y grows along the travel, so that edge leads), `along = atan(p.y, p.x) * 3.0`, height factor 0.3 instead of 0.22, the rest of the flame and glow maths kept; every integer literal keeps its `u`. `arrival.vs` keeps its code; both comments say "a porthole's glass" instead of "a quad over the viewport".

### The seated state (simulation, deterministic)

- `player_field.odin`: `Field_Seat :: enum u8 {Standing, Strapped, Seated}` (Strapped: put in the chair by the fall, Interact says Unbuckle; Seated: sat down later, Interact says Stand). `Field_Player.seat: Field_Seat`, saved and hashed with the player, read by name: a save from before 0223 loads Standing.
- `machine.odin`: `Pod_Seat_Definition :: struct {cells: Machine_Cell_Box_Definition, eye: [3]f64, facing: string}`, `Pod_Window_Definition :: struct {centre, normal: [3]f32, radius: f32}`; `Machine_Definition.seat: Maybe(Pod_Seat_Definition)`, `.windows: []Pod_Window_Definition`. `Pod_Seat :: struct {present: bool, cells: Cell_Box, eye: [3]i64, facing: [3]i64}` (eye in `COLLISION_UNITS_PER_CELL` units through `collision_point_units`, facing a model axis times `UNIT_VECTOR_ONE`); `Pod_Window :: struct {centre, normal: [3]f32, radius: f32}`; `Machine.seat`, `Machine.windows: [MAXIMUM_POD_WINDOWS]Pod_Window`, `Machine.window_count`; `MAXIMUM_POD_WINDOWS :: 8`, `MINIMUM_POD_WINDOW_RADIUS_CELLS :: 0.05`, `MAXIMUM_POD_WINDOW_RADIUS_CELLS :: 2`.
  - `validate_pod_seat :: proc(definitions: []Machine_Definition, index: int) -> string`, called after `validate_pod_fixtures`, every comparison fail closed (NaN): `machine %q has a seat, which only a pod may`; `pod %q seat cells are not a box inside the footprint`; `pod %q seat cells overlap open_cells box %d`; `pod %q seat cells overlap fixture %d` (boxes by `pod_fixture_box`); `pod %q seat eye is not inside its cells`; `pod %q seat facing %q is not +x, -x, +z or -z`. Helpers `pod_seat_facing_axis :: proc(word: string) -> (axis: [3]i64, found: bool)`, `pod_seat_eye_inside_cells :: proc(eye: [3]f64, cells: Cell_Box, footprint: Machine_Footprint_Definition) -> bool`.
  - `validate_pod_windows :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string`: `machine %q has windows, which only a pod may`; `pod %q has more than %d windows`; `pod %q window %d is not inside the footprint` (`machine_light_inside_footprint`); `pod %q window %d has a normal of length %.3f, not 0.5 to 2`; `pod %q window %d has radius %.3f, not 0.05 to 2`.
  - `resolve_pod_seat`, `resolve_pod_windows` fill the machine where the lamps are resolved.
- `world_frame_body.odin`: `frame_body_centre :: proc(origin: World_Coordinate, size: [3]i32, pitch: i64) -> [3]i64` (the expression `make_frame_body` has, which then calls it); `model_point_in_frame :: proc(frame: Frame, origin: World_Coordinate, size: [3]i32, rotation: u8, point: [3]i64) -> World_Position` (point in collision units: `frame.origin + frame_world_direction(frame, frame_body_centre(...) + body_direction_to_frame(rotation, scale_collision_point(point, pitch)))`).
- `entity_pod.odin`:
  - `find_pod :: proc(entities: ^Entities, machines: Machine_Registry) -> (pod: Entity_Common, frame: Frame, found: bool)`: the first alive pod in pool order and its frame; `find_pod_frame` calls it.
  - `pod_seat_eye :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> World_Position` (`model_point_in_frame` of `machine.seat.eye`); `pod_seat_facing :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> [3]i64` (`frame_world_direction` of `body_direction_to_frame(pod.rotation, machine.seat.facing)`).
  - `pod_seat_contains_cell :: proc(pod: Entity_Common, machine: Machine, cell: World_Coordinate) -> bool`: the seat box turned and placed as `pod_fixture_placement` turns a fixture box (`rotate_footprint_cell` of both corners, min and max, plus `pod.origin`).
  - `field_aimed_chair :: proc(entities: ^Entities, machines: Machine_Registry, target: Frame_Raycast_Hit) -> bool`: the target hits an alive pod with `seat.present`, on its frame, in a seat cell. The ray meets the chair's collision boxes; `frame_body_hit` puts the hit's cell a quarter pitch inside the surface, so it lies in the chair's cells.
  - `seat_field_player :: proc(entities: ^Entities, machines: Machine_Registry, tuning: Field_Player_Tuning, body: ^Field_Player, seat: Field_Seat) -> bool`: in the first pod's chair (`find_pod`), false and nothing changed without a seated pod. `up` is the normalised eye, `position = previous_position = eye - fixed_scale(up, tuning.eye_height)` (standing eye height, so `field_player_eye` gives the seat's eye exactly), `forward = tangent_of(up, pod_seat_facing(...))`, yaw and pitch 0, velocity and `motion_fraction` zero, `on_ground` true, `crouching` false, `seat = seat`.
  - `stand_field_player_from_seat :: proc(entities: ^Entities, machines: Machine_Registry, body: ^Field_Player)`: `seat = .Standing`; with `field_pod_spawn` found the feet go to its position (`previous_position` too), `up` to its up, velocity and `motion_fraction` zero, `on_ground` false; forward, yaw and pitch kept, so the look does not jump.
  - `move_field_player_body` also sets `seat = .Standing`.
- `simulation_field.odin`:
  - `SEATED_FIELD_ACTIONS :: Action_Set{.Open_Aimed}`; `seated_field_frame :: proc(frame: Input_Frame) -> Input_Frame`: the frame with `move` zero and `pressed`, `just_pressed` intersected with `SEATED_FIELD_ACTIONS`. The look, the pointer delta and the flags stay. Open_Aimed stays so the inventory binding at the bench opens its panel from the chair, as the HUD's Open promises.
  - `interact_on_field_chair :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, frame: Input_Frame) -> bool`: nothing while the world falls or without Interact just pressed; Strapped or Seated stands (`stand_field_player_from_seat`) whatever the aim; Standing with `field_aimed_chair(frame_target)` sits (`seat_field_player(..., .Seated)`) and clears `Player.sneaking`. True when it acted.
  - `tick_field_session_player`, first: `if interact_on_field_chair(...) { frame.just_pressed -= {.Interact}; frame.pressed -= {.Interact} }`, then `if player.field.seat != .Standing { frame = seated_field_frame(frame) }`, then the existing body from `update_sneaking` on. So a seated player keeps the look, the hotbar is not cycled, Jump, Sneak, the walk, Mine, Place, Rotate, the camera and fly toggles do nothing, no torch, edit, placement, pick up or felling is queued; hand crafting runs on.
  - `make_field_session_player`: `if field_arrival_falling(state.field.arrival) { seat_field_player(..., .Strapped) }` after the spawn: the first player of a new world joins at tick 1, inside the fall. A joiner after the fall stands as today.
- `simulation_arrival.odin`:
  - `arrival_input` returns `seated_field_frame(frame)` while falling (the look and Open_Aimed through, Interact never), unchanged otherwise; the tick and `rebuild_prediction` already call it.
  - `strap_players_for_the_fall :: proc(state: ^Simulation_State, machines: Machine_Registry, tuning: Field_Player_Tuning)`: every player `seat_field_player(..., .Strapped)`; `start_field_world` calls it right after `begin_field_arrival` (players present before the fall).
  - `land_field_arrival` appends `Simulation_Event{player = index, kind = .Touchdown_Confirmed}` for every player whose seat is Strapped. A Skip lands through it too, so the line follows a Skip.
- `player_field.odin`, `tick_field_player`: after `previous_position`, a seated body runs `tick_seated_field_player :: proc(world: ^Field_World, tuning: Field_Player_Tuning, player: ^Field_Player, input: Field_Player_Input)` and returns: `turn_field_player`, velocity and `motion_fraction` zero, `crouching` false, `target = raycast_field(...)` from the eye along the look as the end of the tick does. No toggles, no jump tap, no orient, no crouch update, no move.
- `field_trees.odin`, `move_and_aim_field_player`: no `push_field_player_out_of_trunks` while seated; the aims at the frames and the trunks stay.
- `lockstep.odin`, `predict_field_player_motion`: `if player.field.seat != .Standing { frame = seated_field_frame(frame) }` before `update_sneaking`; the prediction then follows the tick through `move_and_aim_field_player`. It never runs the chair's Interact (as it never turns a switch): the stand lands a window late, a snap.
- `player.odin`: `Player_Event.Touchdown_Confirmed` (last member). The seated player's capsule hangs 0.25 m below the cabin floor (eye 1.35 m, eye height 1.6 m); it meets nothing, and its edge stays 1.2 m from the inner hatch's cells, outside the airlock's reach.
- `developer.odin`: `teleport_field_player` sets `seat = .Standing`. Developer action `.Set_Field_Seat` with `Developer_Request.seat: Field_Seat`: refused `the world is falling` while it falls, `there is no seat` when sitting finds no seated pod; Standing runs `stand_field_player_from_seat`, Seated `seat_field_player`.
- `command_field.odin`, `command.odin`: `seat <stand|sit>` (field world only, written with `look` and `crouch` in both lists), answering `ok seat standing` or `ok seat seated`; `query player` adds `seat <standing|strapped|seated>` after `camera`.

### Interact on the chair (the route)

The chair is the pod's seat cells, not an entity: no fixture, no model split, no save change. `player.odin`: `field_chair_takes_interact :: proc(entities: ^Entities, machines: Machine_Registry, body: Field_Player, falling: bool) -> bool`: false while falling; true for Strapped and Seated (the chair is under the player); for Standing, `field_aimed_chair(body.frame_target)`. `aimed_target_calls_for` becomes `(entities, machines, block_target: Entity_Handle, body: Field_Player, falling: bool) -> (takes_interact, has_panel: bool)`, its Interact answer `entity_takes_interact(aimed_entity(...)) || field_chair_takes_interact(...)`. Callers pass the predicted field player they already read and `field_arrival_falling(simulation.field.arrival)`: `viewport_aimed_target` (`loop.odin`), `touch_interaction_frame` (`touch_overlay.odin`). So the X press is Interact's alone on the chair (`route_open_inventory_press`) and the touch tap presses Interact through `tap_control`; seated, any tap on the free screen stands the player.

### Touchdown confirmed

Touchdown is the landing (`landed_tick` set: the fall's last tick, `arrival_settle_ticks` after the hit, or the tick a Skip applies), the only moment the simulation knows; the hit is the presentation's. Interact on the chair works from the tick after. The cue and the line: `show_simulation_events` (`loop.odin`) shows `.Touchdown_Confirmed` as `ui_mission_control_line(state, text("mc_touchdown_confirmed"))`, which plays `mission_control_chime`; one per strapped player's viewport, nothing from a wall clock. It is not in the journal (not a quest message).

### HUD

- `hud.odin`: `field_chair_hint_key :: proc(screen_context: Screen_Context, hud: Hud_Context) -> string`: "" outside a field session or while `screen_context.arrival_falling`; else by `hud_field_player(...).seat`: Strapped `hint_unbuckle`, Seated `hint_stand`, Standing `hint_sit` when `field_aimed_chair`, else "". `aimed_glyph_hints` returns `{Glyph_Hint{.Interact, text(key)}}` first when the key is set. `hud_target_takes_interact` also answers `field_chair_takes_interact`, so on the gamepad the bar shows the chair's hint without Open or Inventory. `world_glyph_hints` shows the held hints only while the HUD's field player is Standing.

### The descent drawn from the chair (render only)

- `render_arrival.odin`: `arrival_descent_camera`, `arrival_window_look`, `draw_arrival_window` and `ARRIVAL_WALL_COLOR` go; `Game_Config.arrival_window_pitch_degrees`, its bound `MAXIMUM_ARRIVAL_WINDOW_PITCH_DEGREES` and its check in `arrival_problem` go.
  - `arrival_descent_offset :: proc(view: Arrival_View, up, forward: [3]f32, config: Game_Config) -> [3]f32`: zero outside `.Descent`; else `arrival_start_offset(arrival_path_direction(up, forward, angle), ...) * (1 - arrival_eased_share(view.progress))`. Zero at the hit, so the pod reaches the floor exactly there and the old cut is gone; the crash and the shake stay on the phase change as today.
  - `arrival_window_corners :: proc(centre, normal, travel, fallback: [3]f32, radius: f32) -> [4][3]f32`: `b` the travel projected on the window's plane and normalised (the fallback projected when that is shorter than 0.1), `a = cross(normal, b)`; corners for texture coordinates (0,0), (1,0), (1,1), (0,1): `centre - a*r - b*r`, `centre + a*r - b*r`, `centre + a*r + b*r`, `centre - a*r + b*r`.
  - `draw_arrival_windows :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, entities: ^Entities, pod: Entity_Common, machine: Machine, travel: [3]f32, salt: u64)`: only in `.Descent` with the shader ready. Per window: centre and normal through `entity_body_matrix(entities, pod)` (the normal by its upper 3 by 3, normalised), radius times the frame's pitch in metres, fallback the pod's up; shader mode, `flame_strength`, `seconds`, `flame_seed = f32(salt % 1000) / 1000 + f32(index) * 0.618` (no two windows alike), depth test on, depth writes and back face culling off, one `rlgl` quad with the default texture, `rlgl.DrawRenderBatchActive()` after each window (the uniforms change per window), state restored after. The travel is `-arrival_path_direction(pod up, pod forward, angle)`.
- `loop_field_session.odin`:
  - `Field_Scene.hide_frames` becomes `pod_offset: [3]f32` (zero but in the descent). `draw_field_scene` draws the frames and the entities, and later the players and the ghosts, each inside `rlgl.PushMatrix()`, `rlgl.Translatef(pod_offset)`, `rlgl.PopMatrix()`. raylib's `DrawMesh` multiplies the `rlgl` transform into the `mvp` but sends `matModel` as the mesh's own transform, so the model shader's lamps and fragments stay in the resting place's space and agree; the model shader has no fog. The terrain, the trees, the runs, the torches and the sky are drawn with the moved camera as today.
  - `set_field_scene_point_lights` always gathers the machines' lamps (the cabin is lit through the fall) and picks the nearest round `camera.position - scene.pod_offset`.
  - `draw_field_players` skips every body whose seat is not Standing (there is no seated pose).
  - `field_view_camera_mode :: proc(body: Field_Player) -> Camera_Mode`: First_Person while seated, else `body.camera_mode`; `field_viewport_camera` passes it to `pulled_in_field_camera`. The stored mode is kept for standing up.
  - `arrival_viewport_camera` returns `(camera: rl.Camera3D, pod_offset: [3]f32)`: `.Descent` adds `arrival_descent_offset` (the pod's axes, or the player's without a pod) to the seated first person camera's position and target, the look the player's; `viewport.presentation.camera` keeps the camera without the offset, so the HUD's projections stay on the cabin. `.Settled` shakes as today.
  - `draw_field_viewport_world`: `scene.pod_offset` from it; after `draw_field_scene`, inside the same offset push, `draw_arrival_windows` for the pod of `find_pod`; the dust unchanged.
- `loop.odin`, `draw_viewport_world`: the `draw_arrival_window` call goes.
- Unchanged: the streaming, the node selection and the tree cache round the resting eye; the planet through the open portholes is the world pass along the path, as today.

### Save and network

`Field_Player.seat` is the only new saved field, read by name: an old save's players load Standing, no remap and no log line, since nothing is lost (they stood before 0223). `Field_Arrival` and its table do not change. The join snapshot carries the players through the same codec; the input record does not change. A world saved strapped or seated loads so.

### Tests

- `simulation_arrival_test.odin`: `ARRIVAL_TEST_RESTLESS` loses `look_delta` and gains `.Sneak`, `.Mine`, `.Place` in `pressed` and `.Mine`, `.Place` in `just_pressed`; `ARRIVAL_TEST_LOOK :: Input_Frame{look_delta = {40, 0}}`; `ARRIVAL_TEST_INTERACT :: Input_Frame{pressed = {.Interact}, just_pressed = {.Interact}}`; `step_arrival_lockstep_test` takes `input := Input_Frame{}` and stamps it.
  - `test_a_new_world_holds_its_players_through_the_fall`: as today with the new restless frame; after the landing one `ARRIVAL_TEST_INTERACT` tick, then the walk moves the player.
  - `test_the_fall_ignores_the_walk_and_the_tools_and_takes_the_look`: ticks 1 to 599 with restless plus `look_delta {40, 0}`: seat Strapped, `field_player_eye` equal to `pod_seat_eye`, the inventory, `field.edits` and `field.placements` as a still session's, `crouching` false, and the yaw advances every tick against the still session's.
  - `test_interact_before_touchdown_does_nothing_and_after_it_stands_the_player`: Interact every tick: still Strapped through tick 600 (the landing runs after the players), `.Touchdown_Confirmed` for player 0 among tick 600's events and on no other tick; on tick 601 Standing, the feet within 100 mm of `field_pod_spawn`'s; ten ticks of walk then move the player.
  - `test_interact_on_the_chair_seats_and_unseats` (`arrival_ticks` 0, so the spawn stands): `look_field_player_at` the chair's cushion (`model_point_in_frame` of model (-2.0, 1.0, 1.0)), one tick, `field_aimed_chair` true; Interact: Seated, the eye on `pod_seat_eye`; 30 ticks of walk with Jump: the position unchanged; Interact: Standing at the cabin spawn. Aimed at the bench, Interact leaves the player Standing.
  - `test_two_machines_hash_alike_through_a_fall_with_input`: two sessions in lockstep (window 2), A stamping restless plus the look through the fall and `ARRIVAL_TEST_INTERACT` at the landing and every 50 ticks after; the hashes equal at ticks 300, 600, 601, 650 and 700.
  - `test_the_arrivals_presentation_leaves_the_hash`: calls `arrival_descent_offset` and `arrival_window_corners` for every shipped window in place of `arrival_descent_camera`.
  - `test_a_save_loaded_after_the_fall_has_no_fall`: the loaded player is Strapped; one Interact tick before the walk. `test_a_joiner_after_the_fall_has_no_fall`: the joiner is Standing. `test_the_doors_stay_closed_at_the_landing_until_the_player_comes`: one Interact tick before the crawl.
  - `arrival_test_config` drops the window pitch.
- `lockstep_test.odin`: `test_the_prediction_holds_a_seated_player`: `predict_field_player_motion` on a Seated copy with restless plus the look: the position and the seat unchanged, the yaw turned.
- `entity_pod_test.odin`: `test_the_pod_seat_eye_is_clear_of_the_chair`: on the shipped pod `frame_body_probe(&entities.frames, pod_seat_eye(...), millimetres_to_position_units(100))` finds nothing (the near plane is 0.1 m), and the facing is a unit tangent within 1/64 of the frame's right (`POD_ROTATION` turns the model's -z there).
- `machine_test.odin`: `test_the_pod_seat_and_windows_are_validated`: each message above from a broken copy of the shipped pod (a seat on a non pod, cells past the footprint, cells on open box 0, cells on the locker, the eye at y 5, the eye NaN, facing `"up"`, nine windows, a window at x 7, a zero normal, radius 3); the shipped record passes.
- `player_field_test.odin`: `test_the_field_player_saves_its_seat`: Seated round trips; `Field_Player_Before_Crouch` loads Standing.
- `player_test.odin`: `test_the_chair_takes_interact_like_a_switch`: `field_chair_takes_interact` false Strapped while falling, true Strapped landed, true Seated, true Standing aimed at the chair, false Standing aimed at the bench; `route_open_inventory_press` with it drops Open_Inventory.
- `hud_test.odin`: `test_the_chair_hints_unbuckle_stand_and_sit`: the four keys of `field_chair_hint_key`, none while falling, no held hints in `world_glyph_hints` while Strapped.
- `render_arrival_test.odin`: `test_the_fall_ends_at_the_eye_and_its_last_second_is_fastest` on `arrival_descent_offset` (the start offset at progress 0, zero at 1 and outside the descent); `test_the_window_looks_up_from_the_path` goes; `test_the_window_quad_leads_along_the_travel`: the corners in the plane, each `radius * sqrt(2)` from the centre, the midpoint of corners 2 and 3 along the projected travel, a travel along the normal using the fallback.
- `render_field_camera_test.odin`: `test_a_seated_player_sees_in_first_person`: `field_view_camera_mode` First_Person when seated in third person, the stored mode when standing.
- `command_test.odin`: `test_the_seat_command_sits_and_stands`: `seat sit` then `query player` says `seat seated` and the eye is on the seat; `seat stand` says standing; refused while falling.
- `ui_audit_test.odin`: `Ui_Audit_Case.seat: Field_Seat`; the case `hud field strapped` (`field_session`, Strapped, landed): Unbuckle on the bar, kept at every size. `hud mission control` already audits the longest `mc_` line, the new one included.

### Docs (in the same commit)

- `doc/presentation.md`, The arrival: the Descent bullet: "The viewport's camera is the seated player's first person camera moved by the path's offset (`arrival_descent_offset`), the look the player's own; the frames, the machines, the players and the windows are drawn moved by the same offset (`Field_Scene.pod_offset`), so the cabin travels with the eye and its lamps light it." The window bullet: "Each of the pod's `windows` gets a disc of the arrival shader on its glass (`draw_arrival_windows`), its flames leading on the edge the pod travels towards; the planet shows through the portholes' holes." The hit bullet: "The pod meets the floor at the hit, the offset reaching zero there, and the camera shakes as before."
- `doc/architecture.md`, The field session, The arrival: "While it falls every player's frame is cut to the look (`arrival_input`, `seated_field_frame`); players made during it are strapped into the chair (`Field_Seat`); the landing tells each strapped player `Touchdown_Confirmed`." The player on the field: a bullet for the seat (Strapped and Seated skip the move, keep the turn and the aim, `tick_seated_field_player`; Interact on the chair stands or seats, `interact_on_field_chair`). Save format: `Field_Player.seat` by name, an old save standing.
- `doc/content.md`, The pod: the `seat` and `windows` keys with the shipped values, and "there is no seated posture" goes; The arrival: the window pitch bullet goes, `arrival_ticks` says "the players strapped into the chair".
- `doc/input.md`, the Interact bullet and the X row: "On the pod's chair Interact unbuckles after touchdown, then stands and sits; while seated it is the chair's whatever the aim, and the touch tap presses it."
- `doc/hud.md`, Layout, the glyph bar: Unbuckle, Stand, Sit with the Interact glyph and no held hints while seated; Notices: the touchdown line.
- `doc/commands.md`: the `seat` row; `seat` in `query player`.
- `doc/code_map.md`: the entries of `render_arrival.odin`, `simulation_arrival.odin`, `entity_pod.odin`, `player_field.odin`; the counts `code_graph.py --check` reports.
- `doc/log/2026-10-05.md`: "## The arrival seen from the chair (0223)" / "Tags: field, arrival, pod, chair, seat, interact, presentation, shader, save, lockstep, 0223, m14" / the paragraph: touchdown is the landing, not the hit; the chair is the pod's seat cells, not an entity; seated Interact is the chair's whatever the aim; the seated frame keeps the look and Open_Aimed; every player made in the fall is strapped; the pod moves upright along the path by translation; the window pitch key went; the touchdown line is a Mission Control line outside the journal; an old save loads standing with no log line.

### Hand-back check lines that apply

- A number parsed from text: the record's floats are checked fail closed; `seat` takes two words only.
- A changed save layout: by name, standing, no log line (above).
- A shared budget: the seated capsule against the airlock's reach (above).
- A long string: the touchdown line goes through Mission Control's wrapped, queue capped panel.
- A UI audit case: none obsolete; `hud field strapped` added.
- Tests touch no state directory.

### Verify

`taskset -c 8-15 nice -n 10 ./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, each pinned the same way.

### The screenshots (main agent, 0183 socket)

Isolated `XDG_RUNTIME_DIR`, `XDG_STATE_HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME` under the main checkout's `tmp/shot0223/`, `Xvfb :96`, the worktree's build run with `--dev --seed=223 --name=chair`; then `tools/moc pause`, `tick 470` (flames at about half), `query player` (seat strapped, yaw Y), `look Y 14` (the porthole straight ahead of the chair, flames on its glass), `screenshot 0223_window`, `look Y -55` (harness, armrests, the bench's screens), `screenshot 0223_chair`, `tick 140` (landed at 600), `screenshot 0223_touchdown` (the Mission Control line, Unbuckle on the bar), `seat stand`, `look Y+180 -15` (taken into -360 to 360), `screenshot 0223_unbuckled` (the empty chair, Sit on the bar). `kill -9` the game after.

### Open questions, answered

- The chair as an entity, a fixture or pod cells: pod cells (`seat.cells`), since the chair is part of the pod's model and an entity would need a model split and a save change.
- Interact while seated: the chair's whatever the aim, since the chair is under the player and cannot be aimed at from it.
- Players beyond the first during the fall: all strapped into the one chair; a seated body is not drawn.
- The pod's attitude on the path: upright, translated, as the camera's path today.
- The camera while seated: first person, the stored mode kept.
- `arrival_window_pitch_degrees`: removed with the window look it fed.
- The socket's `seat` command: added, so the shots need no xdotool.

### Questions to the main agent

- `mc_arrival` ("You have landed on schedule") is the first quest's message at tick 0, inside the fall. Move it to the landing (a quest data change outside this spec), or leave it?
- From the seat the portholes sit 0.5 m over the eye and their sleeves tilt up, so the view through them is sky and horizon, not the crater. Ground in the windows needs a porthole near the seated eye ahead of the chair (a modelling item, e.g. one more `PORTHOLES` entry low at about 105 degrees) or a pod tilted along the path. Accept for the first playtest?
- No seated pose for the player model: another player in the chair is invisible. A modelling item for the pose, or acceptable?

Decided (main agent, 2026-10-05): approved with these changes.

- During the fall no action passes, Open_Aimed included (the user: only the look from the get go): `arrival_input` returns the frame with `move` zero and both action sets empty while the world falls; `seated_field_frame` keeps Open_Aimed for the chair after touchdown. The fall test also presses Open_Aimed and reads an empty action set off `arrival_input`.
- `mc_arrival` keeps its key and its tick and gets a text that fits the fall: "Contractor. Entry interface on schedule. Stay strapped in. The lease starts at touchdown, and so does the invoice."
- The portholes showing sky and horizon from the seat is accepted for the first playtest; a low porthole ahead of the chair is the user's call (SUGGESTIONS.md).
- The seated pose is 0268; until it lands a seated body is not drawn, as specified.
- The `seat` socket command is approved.
- Before relying on it, the implementer reads `DrawMesh` in the vendored raylib source under `shared/raylib` and confirms that `matModel` is the mesh transform alone while the `rlgl` stack goes into the mvp; if raylib 6.0 combines them, the lamps are gathered in the moved space instead and the report says so.
- The stream: 0223 is built on 0265's branch (both change `simulation_field.odin`, `player_field.odin`, `hud.odin` and the strings), after 0261 has landed (`Field_Scene`).

Ran: read the code and docs named above; computed the porthole glass centres with Python from `pod.py`'s constants; no build or test.
