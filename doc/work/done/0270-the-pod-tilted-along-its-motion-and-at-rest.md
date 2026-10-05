# 0270: The pod tilted along its motion and at rest

Status: landed (2026-10-05, b6014f7)

## Goal

The pod flies base first along its path, turned so the chair's porthole looks along the travel, and the path steepens towards vertical as the drag takes the forward speed, so the horizon shows once the flames die. At rest it lies tilted and rolled in its crater, the outer hatch pointing to the side or up, so the player climbs out; the cabin is walkable tilted. After 0269 (the path) and with 0271 (the crater it rests in).

## Controls

No binding changes.

## Change

- During the fall the pod's axes follow the path's tangent (presentation, with the offset of 0223); the seated eye follows the frame as it does.
- The pod rests as it hits (user, 2026-10-05: no rocking at the crash or the settle): leaning `arrival_rest_tilt_degrees` (15, 0 to 25) from the planet's up towards its travel, the roll fixed by the chair's porthole facing the travel, so the outer hatch lies at the side and level; nothing hashed from the seed. The simulation sets the pod frame's resting axes at the hit (`Frame.axes` already holds any unit vectors); the spawn, the seat, the hatches and the fixtures follow the frame.
- A joiner and a loaded world read the axes from the frame; old worlds keep their level pod.
- Docs: `doc/content.md` (The pod, The arrival), `doc/architecture.md` (Frames, The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: for the homes of seeds 1 to 64 the resting lean is the data's and the hatch's direction is level; a player walks the tilted cabin and crawls the bore both ways; two machines hash alike through the hit and the landing; an old save loads level.
- The couch: unbuckle in a tilted cabin, climb out through the airlock.

## Specification (design, 2026-10-05)

Designed on 0269 as landed (`245c144`, "Fall through black space and a glowing atmosphere before the hit"). The user's decision of 2026-10-05 replaces the hashed tilt and roll: the pod rests as it hits; the drawn attitude eases from the tangent's into the resting one over the curve's last real seconds, and the settle keeps it with the shake alone on top. No save, record or network layout changes.

### The rule

- The travel heading `H` is the chair's facing: `tangent_of(U, pod_seat_facing(frame, pod, machine))`, `U` the placed frame's up (the frame's right for the shipped record). 0269's curve runs along `H` instead of the frame's forward, so the chair's porthole looks along the travel with no quarter turn between the falling and the resting pod, and the door keeps 0260's heading to the spring (question 1).
- The resting pose: every axis of the placed frame turned by `θ = degrees_to_angle_units(arrival_rest_tilt_degrees)` in the plane of `U` and `H`, `U` towards `H`, about the pivot `B`, the model's base centre (`model_point_in_frame(frame, pod.origin, pod.size, pod.rotation, {})`). The up leans `θ` towards the travel; the door axis (model `+x`, the frame's forward) is perpendicular to that plane and keeps its direction, so the outer hatch is level by construction. `validate_pod_seat` gains the rule that makes this hold for any record: the seat faces `"+z"` or `"-z"`, across the door (`"pod %q seat facing %q is not across its door (+z or -z), so its rest would tip the door"`).
- The door axis passes through `B`, so the airlock's sill stays on the floor; the travel half of the base sinks up to `2.725 m · sin θ` (0.71 m at 15 degrees) and the far half rises as much. At the hit the simulation beds the pod: the ground within half the footprint's width (3 m) of `B` is set to the rested base plane, dug above it and filled below it (question 3). The capsule's up stays the planet's: the floor is a slope of the tilt (walkable to 60), the bore runs level along the door's axis, tilted across.

### Data

`arrival_rest_tilt_degrees = 15` in `data/game.sjson` after `arrival_real_seconds`, the comment block naming it ("the pod rests leaning arrival_rest_tilt_degrees (0 to 25) from the planet's up towards its travel, about its door's axis"). `Game_Config.arrival_rest_tilt_degrees: int`; a `Config_Bound` row in `arrival_problem`, 0 to `MAXIMUM_ARRIVAL_REST_TILT_DEGREES :: 25`. `Field_Content` gains `pod_rest: Pod_Rest_Tuning` (`Pod_Rest_Tuning :: struct { tilt_degrees, settle_ticks: int }`, beside `Pod_Airlock_Tuning`), set in `make_field_content` from `arrival_rest_tilt_degrees` and `arrival_settle_ticks`: the tick reads data through `Simulation_Content`, never `Game_Config`.

### Simulation

- `world_field_vector.odin`: `rotate_in_plane :: proc(vector, first, second: [3]i64, cosine, sine: i64) -> [3]i64`: the vector turned in the plane of the orthonormal units `first` and `second`, `first` towards `second`, its part off the plane kept: `v + (c - 1)·((v·f)f + (v·s)s) + sin·((v·f)s − (v·s)f)` with `fixed_dot` and `fixed_scale`; not normalised, so an offset keeps its length.
- `world_frame.odin`: `set_frame_pose :: proc(table: ^Frame_Table, id: Frame_Id, origin: World_Position, axes: [3][3]i64)`: the record and the `frame` copy every `Frame_Body` on it holds (`make_frame_body` copies the frame and collision reads the copy); nothing for an unknown id.
- `entity_pod.odin`:
  - `pod_travel_heading :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> [3]i64`: `tangent_of(frame.axes[FRAME_UP], pod_seat_facing(frame, pod, machine))`.
  - `pod_rest_pose :: proc(frame: Frame, pod: Entity_Common, machine: Machine, tilt_degrees: int) -> (origin: World_Position, axes: [3][3]i64)`: tilt 0 returns the frame's own; else `c, s` from `fixed_cosine`, `fixed_sine`; each axis `normalize_fixed(rotate_in_plane(axis, U, H, c, s))`; `origin = B + rotate_in_plane(frame.origin − B, U, H, c, s)`.
  - `place_body_in_seat :: proc(frame: Frame, pod: Entity_Common, machine: Machine, tuning: Field_Player_Tuning, body: ^Field_Player) -> bool`: the part of `seat_field_player` that puts the body at the seat (eye, up, position, previous position, velocity, fraction, on ground, not crouching); `seat_field_player` calls it, then sets the forward, the yaw, the pitch and the seat as today.
- `simulation_arrival.odin`:
  - `field_arrival_hit_tick :: proc(arrival: Field_Arrival, settle_ticks: int) -> u64`: `start_tick + fall_ticks − settle_ticks`; `field_arrival_skippable` becomes `field_arrival_falling(arrival) && tick < field_arrival_hit_tick(arrival, settle_ticks)` (unchanged meaning).
  - `pod_bed_edits :: proc(frame: Frame, pod: Entity_Common, machine: Machine, material: Field_Material, tint: u8) -> [2]Field_Edit`: the rested frame's; both `.Level`, radius `max(footprint.x, footprint.z) · pitch / 2`, rate `MAXIMUM_DENSITY`, centre `B`, up the frame's up; `[0]` `.Dig` with every material diggable, `[1]` `.Place` of the material and tint with the budget `max(i64)`.
  - `pod_bed_material :: proc(world: ^Field_World, spacing_millimetres: int, centre: World_Position, up: [3]i64) -> (material: Field_Material, tint: u8, found: bool)`: the sample `raycast_field` hits from a metre above `centre` down along `up` over 3 m; no fill when nothing is hit. (implementer, 2026-10-05) The hit's nearest sample is air at a flat surface (density 0), so the first sample that is ground from the hit down one sample in quarter steps is read.
  - `rest_field_pod :: proc(state: ^Simulation_State, content: Simulation_Content)`: `find_pod`; the pose from `pod_rest_pose(frame, pod, machine, content.field.pod_rest.tilt_degrees)` through `set_frame_pose`; the bed's material read before the dig, the dig, the fill, `fell_trees_over_dug_ground` with the dig, `update_field_sky_after_edits` (as `drain_field_edits` ends); the dug steps go to nobody. Then every player whose seat is not `.Standing`: `look := field_look_direction(forward, up, yaw, pitch)` before, `turned := normalize_fixed(rotate_in_plane(look, U, H, c, s))`, `place_body_in_seat` on the rested frame, then `forward = tangent_of(body.up, turned)`, yaw 0, pitch `clamp(angle_of_sine(fixed_dot(turned, body.up)), −FIELD_PITCH_LIMIT, FIELD_PITCH_LIMIT)` (as `look_field_player_at`), so the camera after the hit looks where the drawn camera looked at progress 1.
  - Called once per world: in `tick_field_session_players` before the landing check, `if field_arrival_falling(arrival) && state.tick == field_arrival_hit_tick(arrival, content.field.pod_rest.settle_ticks)`; and at the top of `land_field_arrival` when `state.tick < field_arrival_hit_tick(...)` (a Skip before the hit). With `arrival_settle_ticks` 0 the hit is the landing tick: rest, then land. A world without a fall never rests.
  - (implementer, 2026-10-05) `land_field_arrival` rests at `state.tick <= hit` and the tick's own check skips a tick whose landing is due (`field_arrival_rests_now`): a Skip applied in the hit's own tick lands before the players' step, so with `<` its pod would never rest.
- Why the hit tick, not the landing tick: the settle draws the rested frame unmoved, with the bed already dug (at the landing tick the ground would stand in the cabin's travel half for the settle's second), and the presentation's rotation is confined to the descent. `state.tick` is the tick just run (`simulation_world.odin` increments first), so `arrival_view` is Descent exactly while the frame is unrested.
- Save, join, hash: frames are written whole (`write_frame_tables`, origin and axes) and the bed is field edits, saved and hashed with the field's chunks; both travel in the join snapshot. `Field_Arrival` is unchanged. The pose and the bed change in the hit tick on every machine, from the placed frame and the data alone. Old worlds: a world landed before 0270 keeps its level pod (no remap, no log line); one saved by an older build between the hit and the landing has passed its hit tick and stays level; one saved before the hit rests at it.

### Presentation

- `Arrival_View.rest_share: f32`: in Descent `smoothstep(0, 1, clamp((elapsed − (descent − real_ticks)) / real_ticks, 0, 1))`, `real_ticks = arrival_real_seconds · tick_rate` (0269's 1:1 seconds); 1 at progress 1, 0 outside Descent.
- `render_arrival.odin`: `arrival_pod_transform :: proc(view: Arrival_View, frame: Frame, pod: Entity_Common, machine: Machine, rest_tilt_degrees: int, curve: ^Arrival_Curve) -> (transform: matrix[4, 4]f32, rotation: matrix[3, 3]f32, travel: [3]f32)`: identity and zero travel outside Descent. Else in f32 metres: `U`, `H` (from `pod_travel_heading`), `d = arrival_travel_direction(arrival_curve_at(curve, view.curve_progress), U, H)`, `n = normalize(H − d·dot(H, d))`; the tangent rotation takes `(H, U, H×U)` to `(n, −d, n×(−d))`; the resting rotation is `Σ rest.axes[i] ⊗ frame.axes[i]` from `pod_rest_pose`; `rotation = matrix3_from_quaternion(quaternion_slerp(q_tangent, q_rest, view.rest_share))`; `transform = translate(B + offset) · rotation · translate(−B)`, `offset = arrival_descent_offset(view, U, H, curve)`; `travel = d`. Base first: the model's up opposite the travel, the chair's facing on the travel's side of the motion's vertical plane.
- `arrival_descent_offset` and `arrival_travel_direction` are called with `H` in place of the frame's forward (`arrival_viewport_camera`, `draw_field_viewport_world`).
- `loop_field_session.odin`: `Field_Scene.pod_offset` becomes `pod_transform: Maybe(matrix[4, 4]f32)` (nil: unmoved, no push). `draw_field_scene`'s two pushes multiply it (`rlgl.MultMatrixf` of the flattened matrix, as `render_frames.odin` does). `moved_point_light :: proc(light: Point_Light, transform: matrix[4, 4]f32) -> Point_Light`: position `transform_point`, clip box `box · matrix4_inverse(transform)`; the lamps go with the cabin. `arrival_viewport_camera` returns `pod_transform: Maybe(...)` and the rotation and travel; in Descent `moved.position` and `moved.target` are transformed, the up stays the player's (the planet's): straight ahead the view is the same with either up, a sideways look keeps the horizon level, and the rested body's camera takes the planet's up, so nothing snaps at the hit; the buffet after it. The windows' push multiplies the transform and `draw_arrival_windows` gets `transpose(rotation) · travel`, since the windows draw in the frame's unmoved space. The stored HUD camera stays the resting one.
- `draw_arrival_dust`: the ring about the planet's up at the frame's origin (`normalize` of the origin in metres) and the tangent of the frame's forward, not the frame's axes, which tip with the rest.
- Settled draws the rested frame unmoved; the shake on top as today.

### Tests

- `world_field_vector_test.odin`: `test_rotate_in_plane_turns_within_the_plane`: `first` +y, `second` +x: +y turned 90 degrees is +x within 2 units; +z unchanged; a vector at 15 degrees keeps its length within 2 units.
- `entity_pod_test.odin`:
  - `test_the_rest_pose_leans_towards_the_travel_and_keeps_the_hatch_level`: for seeds 1 to 64 the pod placed at the home as `enable_new_field_world` places it (`field_home_site`, `place_pod` into fresh entities), tilts 0, 15 and 25: tilt 0 returns the frame unchanged; else every axis `vector_length` within 2 of `UNIT_VECTOR_ONE`, pairwise `|fixed_dot|` ≤ 16; `fixed_dot(up, U)` within `UNIT_VECTOR_ONE / 4096` of `fixed_cosine(θ)` and `fixed_dot(up, H)` of `fixed_sine(θ)`; the outer hatch's direction (`frame_world_direction(rested, body_direction_to_frame(pod.rotation, {UNIT_VECTOR_ONE, 0, 0}))`) has `|fixed_dot(·, U)|` ≤ `UNIT_VECTOR_ONE / 4096`; `B` of the rested frame within 1 mm of the placed one's.
  - `test_a_player_stands_and_walks_in_the_rested_cabin`: shipped volumes (`load_machine_collision`), flat field at every spacing, tilts 15 and 25: `place_test_pod`, `pod_rest_pose`, `set_frame_pose`, `pod_bed_edits` applied with `apply_field_edit` (dug steps above 0, none at tilt 0); `field_pod_spawn` and 60 still ticks: on the ground, the feet's frame-local height 0 to 60 mm; from the spawn 90 ticks of walk along each of the tangents of ±right and ±forward: never 4 ticks in a row off the ground, the feet's local height never below −10 mm (no fall through the floor plate, no ground in the cabin).
  - `test_a_player_crawls_out_of_and_into_the_rested_airlock`: the same set up, both hatches opened (`toggle_hatch`): from the bore's floor centre (`pod_box_floor_centre` of `open_cells[2]`) crouched, Sneak forward 150 ticks and 60 still: past the front face, on the ground; from `test_pod_outside_floor_point` a metre up, 90 ticks to land, Sneak along the tangent of −forward 600 ticks: the feet past the inner hatch's face, local height at least −pitch/4 and local z above −3 m (in the cabin, not under the pod).
- `simulation_arrival_test.odin` (`arrival_test_config` gains the tilt):
  - `test_the_pod_rests_at_the_hit`: at the hit tick − 1 the pod's frame is the placed one; after the hit tick it is `pod_rest_pose` of the placed one exactly, and unchanged after the landing and 60 ticks more; a strapped player's eye is `pod_seat_eye` of the rested frame within 1 mm and its look the turned look within `UNIT_VECTOR_ONE / 1024`.
  - `test_skip_before_the_hit_rests_the_pod_once`: a Skip at tick 100 rests the pod at that tick to the same pose, and the field's hash (`field_state_hash`) equals that of a run that rested at the hit; the landing changes neither.
  - `test_a_world_landed_level_loads_level`: a world landed without the rest (its arrival set landed directly, as an older build left it), saved and loaded: the frame as saved, still after 120 ticks.
  - Extended: `test_two_machines_hash_alike_through_a_fall_with_input` runs through the hit and the landing and asserts the pose changed at the hit on both; `test_a_save_taken_during_the_fall_resumes_it` saves before the hit and reaches the unsaved run's pose and hash; `test_a_joiner_after_the_fall_has_no_fall` asserts the joiner's pod frame is the host's rested one; `test_the_arrivals_presentation_leaves_the_hash` calls `arrival_pod_transform` every tick.
- `render_arrival_test.odin`: `test_the_drawn_attitude_follows_the_tangent_then_rests`: shipped config and curve, a pod placed and tilt 15: `rest_share` 0 up to the last real seconds, non-decreasing, 1 at progress 1; at progress 0 `rotation·U = −d`, `rotation·H = n` and `rotation·forward = forward` within 1e-4; at the last descent tick with alpha 0.9999 the transform takes the frame's axes to `pod_rest_pose`'s within 1e-3 and `B` to itself within 1 mm; identity in Settled and None. `test_a_moved_light_keeps_its_clip_box`: a rotation and translation; the light's position moved, and a point inside the old clip box, moved, lands inside the new one.
- `data_load_test.odin`: `test_arrival_values_are_bounded` gains a tilt of 26 failing naming "arrival_rest_tilt_degrees", 0 and 25 passing. `machine_test.odin`: a pod whose seat faces "+x" fails naming "across its door".

### Docs

- `doc/content.md`, The pod: "A new world's pod rests as it hit (0270): leaning `arrival_rest_tilt_degrees` from the planet's up towards its travel, about its door's axis, so the outer hatch stays level; the seat faces across the door (+z or -z), which keeps it so. A world without a fall, or landed before 0270, keeps its pod level." The arrival: the key's sentence, and the path's direction is the chair's facing, not the door's.
- `doc/architecture.md`, Frames: "A frame keeps its pose but the pod's, which `set_frame_pose` turns once at the arrival's hit; the bodies hold a copy of their frame and are refreshed with it." The field session (The arrival): "At the hit tick (`field_arrival_hit_tick`), or at a Skip before it, `rest_field_pod` sets the pod's resting pose (`pod_rest_pose`), beds it in the ground (a dig and a fill to its base plane within half its width) and turns every strapped player's eye and look with it."
- `doc/presentation.md`, The arrival: the Descent bullet: the pod drawn base first along the tangent, the chair's porthole on the travel's side, easing into the resting pose over the last real seconds (`arrival_pod_transform`, `rest_share`); the camera's position and target moved with it, its up the planet's; the lamps and the windows with it; the dust about the planet's up.
- `doc/code_map.md`: as `tools/code_graph.py --check` asks.
- `doc/log/2026-10-05.md`, at the landing:

  ```
  ## The pod tilted along its motion and at rest (0270)

  Tags: field, arrival, pod, frame, rest, tilt, airlock, presentation, 0270, m14

  The user's decision replaced the seed's tilt and roll: the pod rests as it hit, leaning 15 degrees towards its travel about its door's axis, so the hatch is level by construction and the seat must face across the door. The travel runs along the chair's facing, not the door, so the door keeps facing the spring and no quarter turn lies between the falling and the resting pod. The pivot is the base centre on the door's axis: a lift instead (the base's rim on the floor) raised the sill 0.78 m and let a crouched player crawl under the pod, while the pivot leaves the airlock as it was, so the pod is bedded in the ground at the hit (a dig and a fill to its base plane). The pose and the bed come at the hit tick, not the landing, so the settle draws the rested frame unmoved. On a tilted floor the step can climb a fixture's leaning face (up to 0.95 m at 25 degrees). Old worlds keep their level pod.
  ```

### Hand-back check lines that apply

- A number parsed from text is range checked: `arrival_rest_tilt_degrees` in `arrival_problem`, the seat's facing in `validate_pod_seat`.
- A behaviour change that stops old saves: none; old worlds keep their level pod, named in the log.
- Tests never touch the state directory: all of the above are pure or use the in-memory session.

### Verify

`taskset -c 8-15 nice -n 10 ./build.sh check`, `check-android`, `test`; `python3 tools/check_docs.py`; `python3 tools/code_graph.py --check doc/code_map.md`.

Screenshots (the main agent, 0269's recipe: isolated XDG directories, Xvfb, `--dev --seed=270 --name=rest`; the shipped descent is 1800 ticks, the ease from 1440): `tools/moc pause`, `tick 1740`, `query player` (yaw Y), `look Y+32 -2` (the chair's porthole lies 32 degrees from the chair's facing towards the door; its sight line is 11 degrees above the base plane, so base first it shows sky, and the 15 degree lean brings the horizon into it), `screenshot 0270_porthole`; `tick 180` (landed), `seat stand`, `tick 30`, `look` down the cabin towards the travel's low side, `screenshot 0270_cabin`; `query frames` (the pod frame's origin and axes), `teleport` to 8 m along the frame's right and 2 m up the planet's, `look at` the origin, `screenshot 0270_outside`.

### Questions answered

1. The travel heading: the chair's facing, not the door's direction the decision names. With the door's, the resting pod is a quarter turn about the up from the placed frame and the door no longer faces the spring (0260); with the chair's, the rest is a pure turn about the door's axis. To take the door's instead: `H` becomes the frame's forward and `pod_rest_pose` adds the quarter turn that brings the seat's facing onto it.
2. The hit tick for the pose and the bed, the landing tick kept for the touchdown: reasons above.
3. The bed in 0270, though the crater is 0271's: without it the ground stands up to 0.6 m in the cabin's travel half (the lab's spawn stood 14 cm over the floor on it); with a lift instead the sill rises 0.78 m and a crouched player crawls under the pod (the lab, every spacing). 0271 digs its crater first, stands the placed frame's `B` on the dug floor, then this rest and bed run.
4. The camera's up stays the planet's, reasons above.
5. No new key for the ease: it rides on 0269's `arrival_real_seconds`, where the stretch ends and the eye sees the ground move.

### For the main agent

- Accept the chair's facing as the travel heading (question 1)?
- On the tilted floor the step climbs the leaning face of a fixture on the low side (the lab: 0.33 m at 15 degrees and 1000 mm spacing, up to 0.95 m at 25 degrees); nothing falls through and the walk test allows it. Accept, or a separate item?

Ran: experiments in a `git archive` copy (scratchpad) with the shipped pod's volumes on a flat field at every spacing: the rest pose at 0, 10, 15, 20 and 25 degrees with the pivot at the base centre or lifted, with and without the bed, a player spawned, walked, crawled out of and into the airlock; read the code and docs named above.

### Decisions (main agent, 2026-10-05)

1. The chair's facing is the travel heading: accepted. The door keeps 0260's heading to the spring and the rest is a pure turn about the door's axis, so the hatch is level without a rule of its own.
2. The pivot at the base centre with the bed at the hit: accepted. 0271 digs its crater at the hit before the rest and the bed run, and is designed against this specification.
3. The pose and the bed at the hit tick, the settle ticks reaching the simulation through `Pod_Rest_Tuning`: accepted. It is the simulation's first read of `arrival_settle_ticks`; a data change between a save and its load moves the hit, alike on every machine.
4. The step climbing a fixture's leaning face on the low side: accepted as it is and named in the log; a new item if the couch finds it matters.
5. The camera's up the planet's during the descent: accepted.
6. The `look` yaw's sign in the screenshot recipe: the main agent settles it at the shot.
