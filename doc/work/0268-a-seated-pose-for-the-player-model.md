# 0268: A seated pose for the player model

Status: implementing (2026-10-05)

## Goal

A player sitting in the pod's chair is seen by the others as a seated body, legs bent and hands on the armrests, instead of not at all. Until this lands 0223 draws no body for a seated player.

## Controls

No binding changes.

## Change

- A seated pose for the player model (the limbs of `draw_field_players`), chosen where the seat is not Standing, the body placed on the chair's seat cells with the eye at the pod record's `seat.eye`; the viewer's own body stays hidden while seated (first person).
- Docs: `doc/presentation.md` (The player), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: a seated other player is drawn with the seated pose; the seated viewer is not drawn.
- The couch and a second machine: one player sits, the other sees them in the chair.

## Specification (design, 2026-10-05)

Designed on `main` at `ae2b0dc` (0223 and 0270 landed). Presentation only: no simulation, save, record, network or data change. The chair basis below is the pod frame's: forward `F` the chair's facing (`pod_seat_facing`), up `U` the frame's `FRAME_UP` (the rested pod's after the hit, so the body leans with the pod), side `S = cross(F, U)` (the model's +z, the right, as `field_player_body_transform` builds it), origin the seat's eye `E` (`pod_seat_eye`). Distances are metres (the player model's blocks), the model's pivots as `load_player_model_mesh` reads them from the shipped limbs (hip 13/16, shoulder 22/16, neck 23/16, hand 12/16), the eye height `tuning.eye_height` (1.6 m). During the descent the bodies are drawn under the pod's transform already (`push_pod_transform`), so the unmoved frame is the right one there too.

### The pose (shipped values, chair basis, from the eye)

| Joint | forward | up | side |
| --- | --- | --- | --- |
| eye | 0 | 0 | 0 |
| neck | 0.023 | -0.161 | 0 |
| shoulders | 0.031 | -0.223 | ±0.250 |
| hips | 0.110 | -0.780 | ±0.094 |
| knees | 0.485 | -0.780 | ±0.094 |
| feet (the boot's bottom) | 0.485 | -1.217 | ±0.094 |
| hands (the arm's bottom middle) | 0.496 | -0.613 | ±0.099 |

The torso leans back `SEATED_RECLINE_DEGREES` about the hip so the eye stays on `E`. The thighs are level along `F` (82 degrees from the torso), the shins hang along `-U` (the knee folds 90 degrees), the straight arms reach forward 42 degrees from the torso and 14 degrees inward, so the hands lie on the knees. The feet hang 0.13 m over the cabin floor (the seat's eye is 1.35 m over it): the model's legs (0.8125 m) are short for the chair's 0.5 m seat, and a thigh pitched down to reach the floor sinks 0.13 m into the cushion's front roll instead.

### Files and procedures

- `render_player_model.odin` (the knee split, at load):
  - `Player_Leg_Part :: enum u8 {Thigh_Left, Shin_Left, Thigh_Right, Shin_Right}`, and `@(rodata) player_leg_part_limbs := [Player_Leg_Part]Player_Limb` (the leg each part is cut from). `@(rodata) player_leg_part_is_shin := [Player_Leg_Part]bool`.
  - `PLAYER_KNEE_SHARE :: 0.54`: the knee's height up the leg's voxels (7 of the shipped 13).
  - `Player_Model_Mesh` gains `leg_parts: [Player_Leg_Part]Model_Layers` and `leg_part_pivots: [Player_Leg_Part][3]f32` (a thigh's is the hip, its leg's pivot, a shin's the knee). `Player_Model` gains `leg_parts: [Player_Leg_Part]Uploaded_Layers` and `leg_part_pivots`.
  - `player_knee_voxel :: proc(bounds: Voxel_Bounds) -> i32`: `bounds.minimum.y + i32(f32(bounds.maximum.y - bounds.minimum.y) * PLAYER_KNEE_SHARE)`.
  - `player_leg_part_model :: proc(model: model_vox.Voxel_Model, knee: i32, shin: bool, allocator := context.temp_allocator) -> model_vox.Voxel_Model`: a copy whose cells at or above the knee (shin) or below it (thigh) are cleared, of the same size and palette.
  - `load_player_leg_parts :: proc(mesh: ^Player_Model_Mesh, limb: Player_Limb, model: model_vox.Voxel_Model, bounds: Voxel_Bounds, allocator := context.allocator) -> string`: for both parts of the leg, `mesh_voxel_model` of the cut copy and the pivot (a shin's `player_model_point` of the bounds' middle across at the knee voxel). Called from `load_player_limb` for `.Leg_Left` and `.Leg_Right` after the leg's own mesh. The standing legs stay whole.
  - `destroy_player_model_mesh`, `upload_player_model`, `unload_player_model` take the parts with the limbs.
  - `draw_player_leg_part :: proc(renderer: Model_Renderer, model: Player_Model, part: Player_Leg_Part, transform: matrix[4, 4]f32, light: rl.Color)`: as `draw_player_limb`.
- `render_player_seated.odin` (new, the render cluster, pure, no raylib draw call):
  - `SEATED_RECLINE_DEGREES :: 8.0` (the chair's back leans 8.5), `SEATED_THIGH_DEGREES :: 82.0`, `SEATED_KNEE_DEGREES :: -90.0`, `SEATED_ARM_DEGREES :: 42.0`, `SEATED_ARM_INWARD_DEGREES :: 14.0`, `SEATED_HEAD_YAW_LIMIT_DEGREES :: 75.0`, and the head's pitch limit is `HEAD_PITCH_LIMIT_DEGREES` (60).
  - `Seated_Chair :: struct {eye, forward, up: [3]f32}` (metres, unit vectors).
  - `Seated_Body_Transforms :: struct {limbs: [Player_Limb]matrix[4, 4]f32, leg_parts: [Player_Leg_Part]matrix[4, 4]f32}`: model blocks to the world (the draw multiplies `player_model_scale()`), and the legs' entries of `limbs` are unused.
  - `seated_chair_transform :: proc(chair: Seated_Chair) -> matrix[4, 4]f32`: columns `F`, `U`, `S`, origin `E`.
  - `seated_torso_transform :: proc(chair: Seated_Chair, eye_height, hip_height: f32) -> matrix[4, 4]f32`: `chair * translate(sin r · d, -cos r · d, 0) * limb_swing_transform({}, r) * translate(0, -hip_height, 0)`, `r` the recline, `d = eye_height - hip_height`, so the model's eye `(0, eye_height, 0)` lands on `E`.
  - `seated_head_angles :: proc(chair: Seated_Chair, look: [3]f32) -> (yaw, pitch: f32)`: degrees in the chair basis, `yaw = clamp(atan2(dot(look, S), dot(look, F)), ±SEATED_HEAD_YAW_LIMIT_DEGREES)`, `pitch = clamp(asin(clamp(dot(look, U), -1, 1)), ±HEAD_PITCH_LIMIT_DEGREES)`.
  - `seated_head_transform :: proc(chair: Seated_Chair, torso: matrix[4, 4]f32, neck: [3]f32, yaw, pitch: f32) -> matrix[4, 4]f32`: `translate(transform_point(torso, neck)) * rotation(chair) * matrix4_rotate_f32(-yaw rad, +y) * matrix4_rotate_f32(pitch rad, +z) * translate(-neck)`: placed at the neck on the reclined torso, turned in the chair's basis, so it looks along the look exactly within the limits (positive yaw takes the front, +x, towards +z, the right, and positive pitch takes it up).
  - `seated_arm_transform :: proc(torso: matrix[4, 4]f32, shoulder: [3]f32, side: f32) -> matrix[4, 4]f32`: `torso * translate(shoulder) * limb_swing_transform({}, SEATED_ARM_DEGREES) * matrix4_rotate_f32(side · SEATED_ARM_INWARD_DEGREES rad, +x) * translate(-shoulder)`. `side` +1 for the right arm, -1 for the left (positive about +x takes +y to +z, so the hanging arm turns inward).
  - `seated_player_transforms :: proc(chair: Seated_Chair, eye_height: f32, pivots: [Player_Limb][3]f32, leg_part_pivots: [Player_Leg_Part][3]f32, look: [3]f32) -> Seated_Body_Transforms`: the torso (hip height `pivots[.Leg_Left].y`), the head, both arms, each thigh `torso * limb_swing_transform(its pivot, SEATED_THIGH_DEGREES)`, each shin `its thigh * limb_swing_transform(its knee, SEATED_KNEE_DEGREES)`.
- `loop_field_session.odin`:
  - `Field_Body_Pose :: enum u8 {Hidden, Standing, Seated}`.
  - `first_seated_player :: proc(scene: Field_Scene) -> int`: the viewer (when in range) when it is not Standing, else the lowest index not Standing, -1 for none. The one chair holds every seated player (0223), so it shows one body.
  - `field_player_body_pose :: proc(scene: Field_Scene, index: int) -> Field_Body_Pose`: Hidden when not `field_player_body_drawn`. Standing for a standing player. Seated when `index == first_seated_player(scene)`. Hidden otherwise. So a seated viewer's own body hides in first person (its camera mode is First_Person while seated, `field_view_camera_mode`), and a viewer in the chair sees no other seated body round its eye.
  - `field_seated_chair :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> Seated_Chair`: `world_position_to_metres(pod_seat_eye(...))`, `unit_vector_to_f32(pod_seat_facing(...))`, `unit_vector_to_f32(frame.axes[FRAME_UP])`.
  - `field_seated_look :: proc(player: Field_Player) -> [3]f32`: `linalg.normalize(unit_vector_to_f32(field_look_direction(player.forward, player.up, player.yaw, player.pitch)))`.
  - `draw_field_player_seated :: proc(scene: Field_Scene, player: Field_Player)`: nothing without the model (the capsule stands for a missing file and would cut the floor seated) or without `find_pod`. Else `seated_player_transforms` of `field_seated_chair`, the eye height in metres, the model's pivots and the look, lit by `player_body_light(scene.frame, chair.eye, machine.interior_light_share)` (the seated feet lie under the cabin's floor, so `field_player_interior_light_share` would light it as outdoors). Torso, head and arms through `draw_player_limb`, the four leg parts through `draw_player_leg_part`, each times `player_model_scale()`.
  - `draw_field_players`: switches on `field_player_body_pose`. Its comment loses "there is no seated pose".

### Questions the item left open

1. The armrests: the record has no armrest cells, and the chair's pads (0.43 m to each side, 0.78 m over the floor) are out of reach of the model's straight arm at shoulder width without a wide splay, so the hands rest on the knees, the prompt's fallback. No record key added.
2. The legs have no knee: split at load into thigh and shin meshes from the same voxel files, so the model files and `tools/make_placeholder_models.py` stay as they are.
3. Several seated players: one body in the chair (`first_seated_player`), since 0223 straps every player into the one chair and two bodies there would overlap. A seated viewer sees none of the others, whose heads would sit on its eye.
4. The head turns with the look in the chair's basis, clamped, since the seated body cannot turn as the standing one does by its heading. Standing on the field the head does not pitch. Seated it pitches, so the others see where the player looks.
5. The third person camera stays forced to first person while seated (0223, `field_view_camera_mode`), unchanged here. The pose is still chosen for the viewer whenever `viewer_body_shown` holds, which the tests cover. See For the main agent.

### Tests

- `render_player_model_test.odin`:
  - `test_the_legs_split_at_the_knee`: the shipped mesh: `player_knee_voxel` of each leg's bounds is 7. `leg_part_pivots[.Thigh_Left] == pivots[.Leg_Left]`, `[.Shin_Left]` is `{0, 7/16, -1.5/16}` and `[.Shin_Right]` `{0, 7/16, 1.5/16}`. Every part has lit faces, a thigh's positions all at y 7 or above, a shin's all at 7 or below (voxel units).
- `render_player_seated_test.odin` (new), a chair at `E = {3, 40, -2}`, `F = {0, 0, -1}`, `U = {0, 1, 0}`, the shipped mesh's pivots, eye height 1.6:
  - `test_the_seated_pose_keeps_the_eye_on_the_seat`: the torso takes the model's eye `(0, 1.6, 0)` to `E` within 1e-4. Each joint of the table above, through its part's transform (the hip and the shoulder by the torso, the knee by the thigh, the foot `(0, 0, z)` by the shin, the hand `(0, 12/16, ±4/16)` by the arm, the neck by the torso), within 0.005 m of `E` plus the table's offset in the chair basis.
  - `test_the_seated_head_follows_the_look`: the head's front (`transform` of the model's +x direction) along the look within 1e-3 for the look along `F`, turned 30 degrees right, and pitched 40 degrees up. A look 120 degrees right gives yaw 75, 80 degrees up gives pitch 60. The neck point fixed by the head transform within 1e-4 for each.
  - `test_the_seated_pose_follows_the_pods_tilt`: shipped machines and collision, `place_test_pod`, tilts 15 and 25 through `pod_rest_pose` and `set_frame_pose`, then `find_pod`: `field_seated_chair` gives `E` equal to `pod_seat_eye` of the rested frame in metres and `U` its up. The torso's up direction makes `tilt - SEATED_RECLINE_DEGREES` with the planet's up (`normalize(E)`) within 0.5 degree and has no part along `S` (within 1e-3). Each hip, in the world, falls in a seat cell (`pod_seat_contains_cell` of `world_to_frame_cell(rested frame, metres_to_world_position(hip))`).
- `render_field_camera_test.odin`:
  - `test_a_seated_player_is_drawn_seated_and_hidden_from_its_own_eye`: a `Simulation_State` with three players: player 1 Seated, player 2 Standing, the viewer 0 Seated with `viewer_body_shown(field_view_camera_mode(seated in third person), ...)` (false): viewer Hidden, player 1 Hidden (the viewer holds the chair), player 2 Standing. The viewer Standing: player 1 Seated. The viewer Seated with `viewer_body_shown = true`: the viewer Seated and player 1 Hidden. Players 1 and 2 both Strapped with a standing viewer: 1 Seated, 2 Hidden.

### Docs (in the same commit)

- `doc/presentation.md`, The player: a bullet after the third person one: "A player in the pod's chair (Strapped or Seated, 0268, `render_player_seated.odin`) is drawn seated in the chair's basis (its facing, the pod frame's up, so it leans with the rested pod): the eye on the seat's, the torso leaning back 8 degrees, the thighs level, the shins down (each leg cut at the knee at load, `PLAYER_KNEE_SHARE`), the hands on the knees, the head turned to the look within 75 degrees of yaw and 60 of pitch, lit at the pod's interior share. The chair shows one body: the viewer's own when it sits, else the first seated player's. A seated viewer in first person sees none." The field session's scene bullet: "every player's body" gains "(seated in the chair, The player)".
- `doc/code_map.md`: the render cluster's file list gains `render_player_seated.odin` (seated pose). `loop_field_session.odin`'s entry names `field_player_body_pose`. The counts `python3 tools/code_graph.py --check` asks for.
- `doc/log/2026-10-05.md` at the landing, tags: `field, player, model, seat, chair, pose, presentation, 0268, m14`.

### Hand-back check lines that apply

- Memory a frame may draw from: the leg parts are uploaded and unloaded with the limbs in `replace_player_model`, the reload path that already serves the limbs. Nothing new frees mid frame.
- A changed save layout: none.
- A UI audit case: none (nothing on the HUD).
- Tests never touch the state directory: all are pure or load the shipped data read only.

### Verify

`taskset -c 8-15 nice -n 10 ./build.sh check`, `check-android`, `test`. `python3 tools/check_docs.py`. `python3 tools/code_graph.py --check doc/code_map.md`.

Screenshots (the main agent): a second player standing in the cabin looking at the chair with player 0 seated, at rest (tilt 15), and during the descent's last seconds.

### For the main agent

- Lift 0223's forced first person for `Seated` (after the player sat down by choice), so a player in third person sees itself in the chair? `Strapped` would keep first person, since the descent's camera is the seated eye. One line in `field_view_camera_mode`. Left out as it changes 0223's decision.
- The feet hang 0.13 m over the floor with the level thighs. Accept, or prefer the thighs 10 degrees down (feet 0.07 m over it, the thighs 0.13 m into the cushion's front)?

### Decisions (main agent, 2026-10-05)

1. The forced first person camera is lifted for `Seated`: a player who sits after the touchdown may toggle the third person camera as a standing one does, and `Strapped` keeps the first person of 0223 for the descent. One line in `field_view_camera_mode`, named in the log as the change to 0223.
2. Thighs level, the feet 0.13 m above the floor: a thigh sunk into the cushion's front is seen from every angle, floating feet only from in front of the chair at floor height.
3. Hands on the knees, one body in the chair, no capsule fallback: as designed.
