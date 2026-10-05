package game

// The player on the terrain field (work item 0170, doc/architecture.md, The
// player on the field): a capsule in the planet's frame whose up is the
// normalised position, colliding with the field read as a signed distance
// (world_field_distance.odin). Integer and fixed point only, since every
// machine of a lockstep game (0177) must agree: positions in
// 1/POSITION_UNITS_PER_METRE m, velocities in 1/VELOCITY_FRACTION_ONE of a
// position unit per tick, directions in UNIT_VECTOR_ONE, angles in
// ANGLE_UNITS_PER_TURN. It is the field part of the session's Player
// (Player.field, 0179), ticked by simulation_field.odin.
//
// Movement: on ground at most the walkable angle steep the walk follows the
// ground at full speed, and a ledge up to the step height is walked over;
// on steeper ground the walk loses its uphill part and slows with the
// grade, and gravity slides the player down at up to the slide speed. Jump
// on walkable ground rises the jump height, or, walking into a ledge up to
// the mantle height, lifts onto it. The ground is steep only when it is
// steep across the footprint too (the plane through the ground heights at
// the feet and a radius round them, 0203), an impeded walk also tries the
// same move a step height higher and keeps the farther one that ends on
// walkable ground, and steep ground with walkable ground a step up and a
// stride ahead is stepped onto instead of slid down. Sneak on foot shrinks
// the capsule to the crouch height (0218); standing waits for room. A
// machine's collision volumes are surfaces like the field's (0230).

VELOCITY_FRACTION_ONE :: 65536
// Full stick in Field_Player_Input.move.
FIELD_MOVE_ONE :: 1000
// A drop ends within this of the ground, and the collision leaves this
// much overlap alone.
FIELD_GROUND_TOLERANCE :: POSITION_UNITS_PER_METRE / 64
FIELD_PENETRATION_TOLERANCE :: POSITION_UNITS_PER_METRE / 256
// The ground under the feet (probe_field_ground) catches a player in the
// air within a sixteenth of a spacing and lets one standing go only past
// a quarter, so on_ground cannot toggle every tick.
FIELD_GROUND_LAND_SPACING_DIVISOR :: 16
FIELD_GROUND_LEAVE_SPACING_DIVISOR :: 4
// field_push_direction's threshold below every cosine, so every contact
// pushes along its normal.
FIELD_PUSH_ALONG_NORMAL :: -2 * UNIT_VECTOR_ONE
// Passes over the capsule's spheres per collision step.
FIELD_COLLISION_ITERATIONS :: 4
// Sphere tracing steps of a drop onto the ground, each at most half a
// spacing.
FIELD_DROP_ITERATIONS :: 64
// A walk is blocked (and tries the step) when it went less than this
// fraction of its displacement, in 1/4.
FIELD_BLOCKED_QUARTERS :: 2
// A walk is impeded (and tries the move a step higher) when it went less
// than this fraction of its displacement, in 1/16.
FIELD_IMPEDED_SIXTEENTHS :: 15
// The feet and the four points a capsule radius ahead, behind, right and
// left of them, where the footprint's ground heights are probed.
FIELD_FOOTPRINT_POINT_COUNT :: 5
FIELD_PITCH_LIMIT :: 89 * ANGLE_UNITS_PER_TURN / 360

Field_Player_Button :: enum u8 {
	Jump,
	Sneak,
	Sprint,
	Toggle_Fly_Mode,
	Toggle_No_Clip,
	Toggle_Camera_Mode,
	// The hand tool (0171, field_mining.odin): dig or place with the
	// brush while held; the next brush, or with a machine held its next
	// quarter turn (0179).
	Dig,
	Place,
	Next_Brush,
	// Cancels a run's first endpoint (0176, belt_run_placement.odin).
	Back,
}

// What the selected hotbar stack holds (0179, field_tool_for_item): a
// material's item, the foundation (0174), a belt or a pipe for the run
// tools (0176), another machine to place on a frame, the torch, nothing
// Place uses (the hand, which digs nothing), or a shovel, pickaxe or axe
// (0265), whose role and tier the player carries.
Field_Held_Tool :: enum u8 {
	Material,
	Foundation,
	Belt_Run,
	Pipe_Run,
	Machine,
	Torch,
	Hand,
	Tool,
}

Field_Player_Buttons :: bit_set[Field_Player_Button]

// One tick's input, quantised from the input frame before the tick
// (field_tick_input, simulation_field.odin), so the tick reads
// integers only.
Field_Player_Input :: struct {
	// FIELD_MOVE_ONE is full stick: x right, y forward.
	move:          [2]i32,
	// Angle units this tick: x turns right, y looks up.
	turn:          [2]i32,
	held:          Field_Player_Buttons,
	just_pressed:  Field_Player_Buttons,
	// Developer mode, for the Jump double tap that toggles flying.
	developer:     bool,
	// A screen blocked the world since the last tick: the double tap's
	// window closes (update_jump_double_tap).
	world_blocked: bool,
}

// The config of data/game.sjson in the controller's units, for one planet,
// sample spacing and tick rate (make_field_player_tuning).
Field_Player_Tuning :: struct {
	spacing_millimetres: int,
	// Position units.
	capsule_radius:      i64,
	capsule_height:      i64,
	eye_height:          i64,
	crouch_capsule_height: i64,
	crouch_eye_height:   i64,
	step_height:         i64,
	mantle_height:       i64,
	reach:               i64,
	// UNIT_VECTOR_ONE: the cosine of the walkable angle.
	walkable_cosine:     i64,
	// Velocity units, and velocity units per tick for gravity.
	gravity:             i64,
	jump_speed:          i64,
	slide_speed:         i64,
	fall_speed_limit:    i64,
	walk_speed:          i64,
	sprint_speed:        i64,
	sneak_speed:         i64,
	fly_speed:           i64,
	fly_sprint_speed:    i64,
}

// position is the feet, the bottom of the capsule. forward is the
// heading at yaw 0, kept tangent to the up (orient_field_player); the yaw
// turns from it towards forward cross up, as Fly_Camera's yaw turns from
// +x towards +z.
Field_Player :: struct {
	position:          World_Position,
	previous_position: World_Position,
	// What the velocity moved short of a whole position unit, carried
	// into the next tick.
	motion_fraction:   [3]i64,
	// Gravity, jumps and slides; the walk is set from the input each tick.
	velocity:          [3]i64,
	up:                [3]i64,
	forward:           [3]i64,
	yaw:               i32,
	pitch:             i32,
	on_ground:         bool,
	// Sneak on foot, held until the standing capsule has room
	// (update_field_crouch, 0218); a save from before 0218 loads it false.
	crouching:         bool,
	// The developer's hold (`crouch on` of the command socket, 0183),
	// read like Sneak held by update_field_crouch until `crouch off`; a
	// save from before 0183 loads it false (the save reads fields by
	// name, as crouching of 0218).
	crouch_held:       bool,
	ground_normal:     [3]i64,
	flying:            bool,
	no_clip:           bool,
	jump_tap_ticks:    u8,
	camera_mode:       Camera_Mode,
	// The field under the reticle within the tool reach, and the
	// foundation frames' cell (0174); the nearer of the two is kept
	// (aim_field_player_at_frames).
	target:            Field_Raycast_Hit,
	frame_target:      Frame_Raycast_Hit,
	// The trunk under the reticle when it is nearer than both (0197,
	// aim_field_player_at_trees), which then clears them. A save from
	// before 0197 loads it clear.
	tree_target:       Field_Tree_Target,
	// The hand tool (0171): an index into the brushes of data/game.sjson
	// and the material a place raises the field from, or the tool held
	// instead of the material (0174, 0176), the machine a Machine tool
	// places and its quarter turns (0179), and the indices into a held
	// foundation's block sizes and heights (0193, field_foundation_block).
	// A save from before 0193 lacks the indices and loads them as 0, the
	// first of each list.
	brush:             u8,
	held_material:     Field_Material,
	tool:              Field_Held_Tool,
	// The Tool's role and tier (0265), None and 0 for any other tool. A
	// save from before 0265 loads them so and the first tick sets them.
	held_tool_role:    Item_Tool_Role,
	held_tool_tier:    u8,
	held_machine:      Machine_Id,
	placement_rotation: u8,
	foundation_size_index:   u8,
	foundation_height_index: u8,
	// A run tool's first endpoint, chosen by the first Place (0176).
	run_started:       bool,
	run_start:         Belt_Run_Candidate,
}

Field_Ground :: struct {
	on:       bool,
	walkable: bool,
	normal:   [3]i64,
	cosine:   i64,
	// The feet above the ground straight under them, negative inside it.
	below:    i64,
}

// The ground heights over the ground under the feet (along the up,
// position units) at offsets across the up (along the forward and the
// right, position units).
Field_Footprint :: struct {
	offsets: [FIELD_FOOTPRINT_POINT_COUNT][2]i64,
	heights: [FIELD_FOOTPRINT_POINT_COUNT]i64,
}

speed_to_velocity :: proc(millimetres_per_second: int, tick_rate: int) -> i64 {
	return i64(millimetres_per_second) * POSITION_UNITS_PER_METRE * VELOCITY_FRACTION_ONE / (MILLIMETRES_PER_METRE * i64(tick_rate))
}

// Velocity units gained per tick.
gravity_to_velocity_step :: proc(centimetres_per_second_squared: int, tick_rate: int) -> i64 {
	return i64(centimetres_per_second_squared) * POSITION_UNITS_PER_METRE * VELOCITY_FRACTION_ONE / (100 * i64(tick_rate) * i64(tick_rate))
}

// The launch speed that rises height (position units) under gravity:
// v^2 = 2 g h, with v and g in velocity units, so v is the root of 2 g h
// in position units times the root of VELOCITY_FRACTION_ONE (256), which
// keeps the square inside an i64 at a tick rate of 1.
jump_speed_for_height :: proc(height, gravity: i64) -> i64 {
	return i64(integer_square_root(u64(2 * gravity * height))) * 256
}
#assert(VELOCITY_FRACTION_ONE == 256 * 256, "jump_speed_for_height takes the root of VELOCITY_FRACTION_ONE as 256")

make_field_player_tuning :: proc(config: Field_Player_Config, planet: Planet, spacing_millimetres: int, tick_rate: int) -> Field_Player_Tuning {
	gravity := gravity_to_velocity_step(planet.surface_gravity_centimetres_per_second_squared, tick_rate)
	return Field_Player_Tuning {
		spacing_millimetres = spacing_millimetres,
		capsule_radius = millimetres_to_position_units(config.capsule_radius_millimetres),
		capsule_height = millimetres_to_position_units(config.capsule_height_millimetres),
		eye_height = millimetres_to_position_units(config.eye_height_millimetres),
		crouch_capsule_height = millimetres_to_position_units(config.crouch_height_millimetres),
		crouch_eye_height = millimetres_to_position_units(config.crouch_eye_height_millimetres),
		step_height = i64(config.step_height_samples) * sample_axis_to_position(1, spacing_millimetres),
		mantle_height = millimetres_to_position_units(config.mantle_height_millimetres),
		reach = millimetres_to_position_units(config.tool_reach_millimetres),
		walkable_cosine = fixed_cosine(degrees_to_angle_units(config.walkable_angle_degrees)),
		gravity = gravity,
		jump_speed = jump_speed_for_height(millimetres_to_position_units(config.jump_height_millimetres), gravity),
		slide_speed = speed_to_velocity(config.slide_speed_millimetres_per_second, tick_rate),
		fall_speed_limit = speed_to_velocity(config.fall_speed_limit_millimetres_per_second, tick_rate),
		walk_speed = speed_to_velocity(config.walk_speed_millimetres_per_second, tick_rate),
		sprint_speed = speed_to_velocity(config.sprint_speed_millimetres_per_second, tick_rate),
		sneak_speed = speed_to_velocity(config.sneak_speed_millimetres_per_second, tick_rate),
		fly_speed = speed_to_velocity(config.fly_speed_millimetres_per_second, tick_rate),
		fly_sprint_speed = speed_to_velocity(config.fly_sprint_speed_millimetres_per_second, tick_rate),
	}
}

// A tangent of the up: look projected onto the tangent plane, or any
// axis that is not along the up when look is.
tangent_of :: proc(up, look: [3]i64) -> [3]i64 {
	candidates := [3][3]i64{look, {UNIT_VECTOR_ONE, 0, 0}, {0, 0, UNIT_VECTOR_ONE}}
	for candidate in candidates {
		projected := project_onto_plane(candidate, up)
		if vector_length(projected) > UNIT_VECTOR_ONE / 16 {
			tangent, _ := normalize_fixed(projected)
			return tangent
		}
	}
	return {0, UNIT_VECTOR_ONE, 0}
}

// Standing at feet, heading along look's tangent with yaw and pitch 0.
make_field_player :: proc(feet: World_Position, look: [3]i64) -> Field_Player {
	player := Field_Player {
		position          = feet,
		previous_position = feet,
		up                = {0, UNIT_VECTOR_ONE, 0},
	}
	if up, ok := normalize_fixed(cast([3]i64)(feet)); ok {
		player.up = up
	}
	player.forward = tangent_of(player.up, look)
	return player
}

// The generated surface along the radial through position, raised by
// clearance; the start of a player standing under a camera.
field_surface_under :: proc(generation: Planet_Generation, position: World_Position, clearance: i64) -> World_Position {
	up, ok := normalize_fixed(cast([3]i64)(position))
	if !ok {
		up = {0, UNIT_VECTOR_ONE, 0}
	}
	on_sphere := fixed_scale(up, generation.radius)
	surface := generation.radius + surface_relief(generation, on_sphere)
	return World_Position(fixed_scale(up, surface + clearance))
}

// The up from the position and the forward re-projected onto its tangent
// plane, so a walk round the planet carries the heading along.
orient_field_player :: proc(player: ^Field_Player) {
	if up, ok := normalize_fixed(cast([3]i64)(player.position)); ok {
		player.up = up
	}
	player.forward = tangent_of(player.up, player.forward)
}

field_heading :: proc(forward, up: [3]i64, yaw: i32) -> [3]i64 {
	right := fixed_cross(forward, up)
	return fixed_scale(forward, fixed_cosine(yaw)) + fixed_scale(right, fixed_sine(yaw))
}

field_player_heading :: proc(player: Field_Player) -> [3]i64 {
	return field_heading(player.forward, player.up, player.yaw)
}

field_player_right :: proc(player: Field_Player) -> [3]i64 {
	return fixed_cross(field_player_heading(player), player.up)
}

field_look_direction :: proc(forward, up: [3]i64, yaw, pitch: i32) -> [3]i64 {
	return fixed_scale(field_heading(forward, up, yaw), fixed_cosine(pitch)) + fixed_scale(up, fixed_sine(pitch))
}

// The tuning with the crouch's capsule and eye heights in place of the
// standing ones while crouching (0218). The crouch fields stay, so the
// crouched posture of a crouched posture is the same tuning.
field_posture_tuning :: proc(tuning: Field_Player_Tuning, crouching: bool) -> Field_Player_Tuning {
	posture := tuning
	if crouching {
		posture.capsule_height = tuning.crouch_capsule_height
		posture.eye_height = tuning.crouch_eye_height
	}
	return posture
}

field_player_eye :: proc(player: Field_Player, tuning: Field_Player_Tuning) -> World_Position {
	return player.position + World_Position(fixed_scale(player.up, field_posture_tuning(tuning, player.crouching).eye_height))
}

// Sneak on foot crouches; otherwise a crouching player stands once the
// standing capsule has room at the feet, or at once flying with no clip.
// tuning is the base tuning.
update_field_crouch :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, sneak: bool) {
	switch {
	case sneak && !player.flying:
		player.crouching = true
	case !player.crouching:
	case player.flying && player.no_clip:
		player.crouching = false
	case !field_capsule_overlaps(world, frames, field_posture_tuning(tuning, false), player.position, player.up):
		player.crouching = false
	}
}

turn_field_player :: proc(player: ^Field_Player, turn: [2]i32) {
	player.yaw = i32((int(player.yaw) + int(turn.x)) %% ANGLE_UNITS_PER_TURN)
	player.pitch = clamp(player.pitch + turn.y, -FIELD_PITCH_LIMIT, FIELD_PITCH_LIMIT)
}

// The look as a bearing from the planet's north and a pitch, both in
// ANGLE_UNITS_PER_TURN (the command socket's look, 0183): the forward
// becomes the north tangent and the yaw the bearing, so the heading turns
// from north the way the yaw turns.
set_field_look :: proc(player: ^Field_Player, bearing, pitch: i32) {
	player.forward = frame_north_tangent(player.up)
	player.yaw = i32(int(bearing) %% ANGLE_UNITS_PER_TURN)
	player.pitch = clamp(pitch, -FIELD_PITCH_LIMIT, FIELD_PITCH_LIMIT)
}

// A look target nearer the eye than this is the eye (look_field_player_at):
// a socket position has millimetres, so the eye's own metres read back
// within a few units of it, and so short an offset has no direction.
FIELD_LOOK_AT_MINIMUM_DISTANCE :: POSITION_UNITS_PER_METRE / 100

// The look from the eye towards target (0183): the forward along the
// direction's tangent with yaw 0, the pitch its angle over the tangent
// plane within FIELD_PITCH_LIMIT. False, and nothing changed, when the
// target is within FIELD_LOOK_AT_MINIMUM_DISTANCE of the eye.
look_field_player_at :: proc(player: ^Field_Player, tuning: Field_Player_Tuning, target: World_Position) -> bool {
	offset := cast([3]i64)(target - field_player_eye(player^, tuning))
	if vector_length(offset) < FIELD_LOOK_AT_MINIMUM_DISTANCE {
		return false
	}
	direction, _ := normalize_fixed(offset)
	player.forward = tangent_of(player.up, direction)
	player.yaw = 0
	player.pitch = clamp(angle_of_sine(fixed_dot(direction, player.up)), -FIELD_PITCH_LIMIT, FIELD_PITCH_LIMIT)
	return true
}

toggle_field_flying :: proc(player: ^Field_Player) {
	player.flying = !player.flying
	player.velocity = {}
}

apply_field_player_toggles :: proc(player: ^Field_Player, just_pressed: Field_Player_Buttons) {
	if .Toggle_Camera_Mode in just_pressed {
		player.camera_mode = player.camera_mode == .First_Person ? .Third_Person : .First_Person
	}
	if .Toggle_Fly_Mode in just_pressed {
		toggle_field_flying(player)
	}
	if .Toggle_No_Clip in just_pressed {
		player.no_clip = !player.no_clip
	}
}

// The block player's double tap (update_jump_double_tap) on the field
// player: a second Jump press within JUMP_DOUBLE_TAP_TICKS toggles flying
// in developer mode.
update_field_jump_double_tap :: proc(player: ^Field_Player, input: Field_Player_Input) {
	if input.world_blocked {
		player.jump_tap_ticks = 0
	}
	if .Jump not_in input.just_pressed {
		player.jump_tap_ticks = player.jump_tap_ticks > 0 ? player.jump_tap_ticks - 1 : 0
		return
	}
	if player.jump_tap_ticks > 0 && input.developer {
		toggle_field_flying(player)
		player.jump_tap_ticks = 0
		return
	}
	player.jump_tap_ticks = JUMP_DOUBLE_TAP_TICKS
}

// The sneak speed follows the crouch, not the button, so a player held
// crouched under a ceiling walks slowly until there is room to stand.
field_walk_speed :: proc(tuning: Field_Player_Tuning, held: Field_Player_Buttons, crouching: bool) -> i64 {
	switch {
	case crouching:
		return tuning.sneak_speed
	case .Sprint in held:
		return tuning.sprint_speed
	}
	return tuning.walk_speed
}

// Tangent to the up, in velocity units.
field_walk_velocity :: proc(player: Field_Player, move: [2]i32, speed: i64) -> [3]i64 {
	forward := fixed_scale(field_player_heading(player), speed) * i64(move.y) / FIELD_MOVE_ONE
	right := fixed_scale(field_player_right(player), speed) * i64(move.x) / FIELD_MOVE_ONE
	return forward + right
}

// The capsule is spheres along its axis, from the bottom one (a radius
// above the feet) to the top one, at most a radius apart.
field_capsule_sphere_count :: proc(tuning: Field_Player_Tuning) -> i64 {
	span := tuning.capsule_height - 2 * tuning.capsule_radius
	return max(ceiling_divide_i64(span, tuning.capsule_radius), 1) + 1
}

field_capsule_centre :: proc(tuning: Field_Player_Tuning, feet: World_Position, up: [3]i64, index: i64) -> World_Position {
	span := tuning.capsule_height - 2 * tuning.capsule_radius
	return feet + World_Position(fixed_scale(up, tuning.capsule_radius + span * index / (field_capsule_sphere_count(tuning) - 1)))
}

// The surface nearest a point of the capsule: the field's, or a solid
// frame cell's (world_frame_collision.odin) within a radius and half a
// spacing, the farthest a sweep or a drop step moves before probing again.
field_player_probe :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, position: World_Position) -> Field_Surface_Probe {
	return field_solid_probe(world, frames, tuning.spacing_millimetres, position, field_frame_probe_reach(tuning))
}

field_frame_probe_reach :: proc(tuning: Field_Player_Tuning) -> i64 {
	return tuning.capsule_radius + sample_axis_to_position(1, tuning.spacing_millimetres) / 2 + FIELD_GROUND_TOLERANCE
}

// The step against a frame: a solid cell in front of the bottom sphere is
// stepped onto when one pitch high, whatever the field's step height, so
// a foundation pad is a step at every spacing; a body's volume is
// stepped at the data's step height (0230).
field_step_height :: proc(frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up, direction: [3]i64) -> i64 {
	bottom := feet + World_Position(fixed_scale(up, tuning.capsule_radius) + fixed_scale(direction, tuning.capsule_radius / 2))
	cells, pitch := frame_solid_probe(frames, bottom, tuning.capsule_radius + FIELD_GROUND_TOLERANCE)
	if !cells.found {
		return tuning.step_height
	}
	return max(tuning.step_height, pitch + FIELD_GROUND_TOLERANCE)
}

// Whether any sphere of the capsule at feet overlaps the ground.
field_capsule_overlaps :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up: [3]i64) -> bool {
	for index in 0 ..< field_capsule_sphere_count(tuning) {
		if field_player_probe(world, frames, tuning, field_capsule_centre(tuning, feet, up, index)).distance < tuning.capsule_radius - FIELD_PENETRATION_TOLERANCE {
			return true
		}
	}
	return false
}

// The way out of a contact. A surface whose normal's cosine against the
// up lies below flatten_below pushes along the tangent plane only: the
// walk flattens what is steeper than walkable, so walking into it never
// lifts the player (gravity's move slides down it with the full normal),
// and the settle does the same. A ceiling keeps its normal.
// depth comes back as the push along that way.
field_push_direction :: proc(normal, up: [3]i64, depth, flatten_below: i64) -> (direction: [3]i64, push: i64) {
	if fixed_dot(normal, up) >= flatten_below {
		return normal, depth
	}
	flat, ok := normalize_fixed(project_onto_plane(normal, up))
	along := fixed_dot(flat, normal)
	if !ok || along <= 0 {
		return normal, depth
	}
	return flat, min(depth * UNIT_VECTOR_ONE / along, 4 * depth)
}

// Pushes each overlapping sphere out along the surface normal (along the
// up deep in the ground, where the normal is unknown) and takes the part
// of velocity running into the surface away.
resolve_field_penetration :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: ^World_Position, up: [3]i64, velocity: ^[3]i64, flatten_below: i64 = FIELD_PUSH_ALONG_NORMAL) {
	for _ in 0 ..< FIELD_COLLISION_ITERATIONS {
		pushed := false
		for index in 0 ..< field_capsule_sphere_count(tuning) {
			centre := field_capsule_centre(tuning, feet^, up, index)
			cells := frame_probe(frames, centre, field_frame_probe_reach(tuning))
			// The field and the frames each push, so a floor nearer than a
			// wall never hides the wall; the frames' probe is the nearer of
			// a solid cell and a body's volume (0230).
			for probe in ([2]Field_Surface_Probe{field_surface_probe(world, tuning.spacing_millimetres, centre), cells}) {
				depth := tuning.capsule_radius - probe.distance
				if depth <= FIELD_PENETRATION_TOLERANCE {
					continue
				}
				normal := probe.normal
				direction, push := field_push_direction(normal, up, depth, flatten_below)
				feet^ += World_Position(fixed_scale(direction, push))
				if into := fixed_dot(velocity^, normal); into < 0 {
					velocity^ -= fixed_scale(normal, into)
				}
				pushed = true
			}
		}
		if !pushed {
			return
		}
	}
}

// Moves the feet by displacement (position units) in steps of half a
// radius, resolving the collision after each.
sweep_field_capsule :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: ^World_Position, up: [3]i64, displacement: [3]i64, velocity: ^[3]i64, flatten_below: i64 = FIELD_PUSH_ALONG_NORMAL) {
	steps := 1 + vector_length(displacement) / max(tuning.capsule_radius / 2, 1)
	for index in 0 ..< steps {
		feet^ += World_Position(displacement * (index + 1) / steps - displacement * index / steps)
		resolve_field_penetration(world, frames, tuning, feet, up, velocity, flatten_below)
	}
}

// Whole position units of the velocity this tick; the rest is carried.
take_field_motion :: proc(velocity: [3]i64, fraction: ^[3]i64) -> [3]i64 {
	displacement: [3]i64
	for axis in 0 ..< 3 {
		total := velocity[axis] + fraction[axis]
		displacement[axis] = floor_divide_i64(total, VELOCITY_FRACTION_ONE)
		fraction[axis] = total - displacement[axis] * VELOCITY_FRACTION_ONE
	}
	return displacement
}

// The ground straight under the feet: a ray down from the bottom
// sphere's centre, so feet up to a radius inside the ground still find
// it. below is the feet's height over the hit, normal the field's there.
field_ground_under :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up: [3]i64) -> (below: i64, normal: [3]i64, found: bool) {
	centre := feet + World_Position(fixed_scale(up, tuning.capsule_radius))
	reach := tuning.capsule_radius + max(tuning.step_height, sample_axis_to_position(1, tuning.spacing_millimetres))
	hit := field_solid_raycast(world, frames, tuning.spacing_millimetres, centre, -up, reach)
	if !hit.hit {
		return 0, {}, false
	}
	return hit.distance - tuning.capsule_radius, hit.normal, true
}

// The feet's height over a slope of this cosine with the bottom sphere
// resting on it: r (1 / cosine - 1).
field_resting_height :: proc(tuning: Field_Player_Tuning, cosine: i64) -> i64 {
	return tuning.capsule_radius * (UNIT_VECTOR_ONE - cosine) / max(cosine, UNIT_VECTOR_ONE / 8)
}

// On the ground when the ground under the feet faces the up, the feet are
// not moving away from it and stand within the tolerance of their resting
// height over it: a sixteenth of a spacing to land, a quarter to stay
// (was_on), the hysteresis. below counts from the resting height.
probe_field_ground :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up, velocity: [3]i64, was_on: bool) -> Field_Ground {
	below, normal, found := field_ground_under(world, frames, tuning, feet, up)
	cosine := fixed_dot(normal, up)
	if !found || fixed_dot(velocity, up) > 0 || cosine <= 0 {
		return {}
	}
	spacing := sample_axis_to_position(1, tuning.spacing_millimetres)
	tolerance := spacing / (was_on ? FIELD_GROUND_LEAVE_SPACING_DIVISOR : FIELD_GROUND_LAND_SPACING_DIVISOR)
	over := below - field_resting_height(tuning, cosine)
	if over > tolerance {
		return {}
	}
	return {on = true, walkable = cosine >= tuning.walkable_cosine, normal = normal, cosine = cosine, below = over}
}

// The least squares plane through the footprint's heights, as its normal
// in the footprint's frame (x along the first offset axis, y along the
// up, z along the second) in UNIT_VECTOR_ONE. A bump narrower than the
// offsets raises the plane without tilting it. Offsets up to 2^13 and
// heights up to 2^16 position units keep the products inside an i64.
footprint_plane_normal :: proc(footprint: Field_Footprint) -> [3]i64 {
	sum_offset: [2]i64
	sum_height: i64
	for index in 0 ..< FIELD_FOOTPRINT_POINT_COUNT {
		sum_offset += footprint.offsets[index]
		sum_height += footprint.heights[index]
	}
	mean_offset := sum_offset / FIELD_FOOTPRINT_POINT_COUNT
	mean_height := sum_height / FIELD_FOOTPRINT_POINT_COUNT
	xx, xz, zz, xh, zh: i64
	for index in 0 ..< FIELD_FOOTPRINT_POINT_COUNT {
		offset := footprint.offsets[index] - mean_offset
		height := footprint.heights[index] - mean_height
		xx += offset.x * offset.x
		xz += offset.x * offset.y
		zz += offset.y * offset.y
		xh += offset.x * height
		zh += offset.y * height
	}
	// The slopes are these over the determinant.
	determinant := xx * zz - xz * xz
	if determinant <= 0 {
		return {0, UNIT_VECTOR_ONE, 0}
	}
	normal := shift_below_unit_scale({-(xh * zz - zh * xz), determinant, -(zh * xx - xh * xz)})
	unit, _ := normalize_fixed(normal)
	return unit
}

// The vector shifted down until no component reaches 2^30, so
// normalize_fixed's product with UNIT_VECTOR_ONE stays inside an i64.
shift_below_unit_scale :: proc(vector: [3]i64) -> [3]i64 {
	result := vector
	for max(abs(result.x), abs(result.y), abs(result.z)) >= VECTOR_LENGTH_EXACT_LIMIT {
		result = {result.x >> 1, result.y >> 1, result.z >> 1}
	}
	return result
}

// The ground's height over base (the ground under the feet) at a point
// offset across the up: a ray down from the step height (at least a
// sample) over it, twice that long, and the ray's end without ground on
// it. clear is false when the ray starts inside the ground, a face taller
// than the step, which no plane through the footprint stands for.
field_ground_height_at :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, base: World_Position, up, offset: [3]i64) -> (height: i64, clear: bool) {
	lift := max(tuning.step_height, sample_axis_to_position(1, tuning.spacing_millimetres))
	origin := base + World_Position(offset + fixed_scale(up, lift))
	hit := field_solid_raycast(world, frames, tuning.spacing_millimetres, origin, -up, 2 * lift)
	if !hit.hit {
		return -lift, true
	}
	return lift - hit.distance, hit.distance > 0
}

// The ground heights over the ground under the feet, there and a capsule
// radius ahead, behind, right and left of it; found is false beside a
// face taller than the step.
probe_field_footprint :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up, forward: [3]i64, ground: Field_Ground) -> (footprint: Field_Footprint, found: bool) {
	radius := tuning.capsule_radius
	right := fixed_cross(forward, up)
	base := feet - World_Position(fixed_scale(up, ground.below + field_resting_height(tuning, ground.cosine)))
	footprint.offsets = {{0, 0}, {radius, 0}, {-radius, 0}, {0, radius}, {0, -radius}}
	for index in 1 ..< FIELD_FOOTPRINT_POINT_COUNT {
		across := footprint.offsets[index]
		offset := fixed_scale(forward, across.x) + fixed_scale(right, across.y)
		height, clear := field_ground_height_at(world, frames, tuning, base, up, offset)
		if !clear {
			return footprint, false
		}
		footprint.heights[index] = height
	}
	return footprint, true
}

// Steep ground under the feet is judged again over the footprint: the
// flatter of the two planes is the ground's, so a bump narrower than the
// capsule is walkable and only ground steep across it slides, while the
// feet's plane keeps a player at a drop's edge standing. Walkable ground
// under the feet is not probed further, since the flatter plane is
// walkable then anyway, and beside a face taller than the step the feet's
// plane stays.
judge_ground_over_footprint :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up, forward: [3]i64, ground: Field_Ground) -> Field_Ground {
	if !ground.on || ground.walkable {
		return ground
	}
	axis := tangent_of(up, forward)
	footprint, found := probe_field_footprint(world, frames, tuning, feet, up, axis, ground)
	if !found {
		return ground
	}
	local := footprint_plane_normal(footprint)
	normal := fixed_scale(axis, local.x) + fixed_scale(up, local.y) + fixed_scale(fixed_cross(axis, up), local.z)
	cosine := fixed_dot(normal, up)
	if cosine <= ground.cosine {
		return ground
	}
	result := ground
	result.normal, result.cosine, result.walkable = normal, cosine, cosine >= tuning.walkable_cosine
	return result
}

// Lowers the capsule by sphere tracing its bottom sphere, at most half a
// spacing a step, until it rests on the ground; landed is false when that
// lies farther than limit.
drop_field_capsule :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up: [3]i64, limit: i64) -> (result: World_Position, landed: bool) {
	result = feet
	dropped: i64 = 0
	step := max(sample_axis_to_position(1, tuning.spacing_millimetres) / 2, 1)
	for _ in 0 ..< FIELD_DROP_ITERATIONS {
		bottom := result + World_Position(fixed_scale(up, tuning.capsule_radius))
		gap := field_player_probe(world, frames, tuning, bottom).distance - tuning.capsule_radius
		if gap <= FIELD_GROUND_TOLERANCE {
			return result, true
		}
		gap = min(gap, step, limit - dropped)
		if gap <= 0 {
			return feet, false
		}
		result -= World_Position(fixed_scale(up, gap))
		dropped += gap
	}
	return feet, false
}

// The capsule lifted to height over the ground under the feet (below,
// probe_field_ground), moved along direction by a radius and a sample and
// dropped back: found when nothing overlaps on the way and it lands on
// walkable ground more than min_gain over that ground. Measuring from the
// ground rather than the feet keeps a capsule pushed up a face's rounded
// foot from stepping or mantling higher than the data says. The field
// blurs a ledge's face over a sample (the walk stops up to that far short
// of it), and the normal is the top's only half a sample past the edge,
// so the move is that long; the step and the mantle take one tick.
find_field_ledge :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up, direction: [3]i64, height, min_gain, below: i64) -> (landing: World_Position, found: bool) {
	clearance := i64(2 * FIELD_PENETRATION_TOLERANCE)
	lift := height - below + clearance
	if lift <= 0 {
		return feet, false
	}
	raised := feet + World_Position(fixed_scale(up, lift))
	if field_capsule_overlaps(world, frames, tuning, raised, up) {
		return feet, false
	}
	ahead_distance := tuning.capsule_radius + sample_axis_to_position(1, tuning.spacing_millimetres)
	if !field_capsule_path_clear(world, frames, tuning, raised, up, direction, ahead_distance) {
		return feet, false
	}
	ahead := raised + World_Position(fixed_scale(direction, ahead_distance))
	dropped, landed := drop_field_capsule(world, frames, tuning, ahead, up, lift)
	if !landed {
		return feet, false
	}
	gain := fixed_dot(cast([3]i64)(dropped - feet), up) + below
	ground := probe_field_ground(world, frames, tuning, dropped, up, {}, true)
	if gain <= min_gain || !ground.walkable {
		return feet, false
	}
	return dropped, true
}

// Whether the capsule moved from start along direction by distance
// overlaps nothing on the way, checked every radius, so the ledge's move
// does not pass through a solid frame cell thinner than a sample.
field_capsule_path_clear :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, start: World_Position, up, direction: [3]i64, distance: i64) -> bool {
	stride := max(tuning.capsule_radius, 1)
	for travelled := stride; ; travelled += stride {
		travelled = min(travelled, distance)
		if field_capsule_overlaps(world, frames, tuning, start + World_Position(fixed_scale(direction, travelled)), up) {
			return false
		}
		if travelled == distance {
			return true
		}
	}
}

// Past the walkable angle the walk loses its uphill part and slows with
// the grade (the slope's cosine over the walkable one).
steep_walk_velocity :: proc(walk: [3]i64, ground: Field_Ground, up: [3]i64, walkable_cosine: i64) -> [3]i64 {
	result := walk
	if uphill, ok := normalize_fixed(project_onto_plane(up, ground.normal)); ok {
		if climb := fixed_dot(result, uphill); climb > 0 {
			result -= fixed_scale(uphill, climb)
		}
	}
	return result * ground.cosine / max(walkable_cosine, 1)
}

// On walkable ground the walk follows the ground's plane at its full
// speed, so a slope does not slow it.
ground_walk_velocity :: proc(walk: [3]i64, normal: [3]i64) -> [3]i64 {
	along, ok := normalize_fixed(project_onto_plane(walk, normal))
	if !ok {
		return {}
	}
	return fixed_scale(along, vector_length(walk))
}

limit_speed :: proc(velocity: [3]i64, limit: i64) -> [3]i64 {
	if vector_length(velocity) <= limit {
		return velocity
	}
	direction, _ := normalize_fixed(velocity)
	return fixed_scale(direction, limit)
}

// Whether a walk from start went less than FIELD_BLOCKED_QUARTERS of
// displacement along it.
field_walk_blocked :: proc(start, end: World_Position, displacement: [3]i64) -> bool {
	wanted := displacement.x * displacement.x + displacement.y * displacement.y + displacement.z * displacement.z
	if wanted == 0 {
		return false
	}
	moved := cast([3]i64)(end - start)
	went := moved.x * displacement.x + moved.y * displacement.y + moved.z * displacement.z
	return 4 * went < FIELD_BLOCKED_QUARTERS * wanted
}

// How far a walk from start to end went along its displacement, in
// position units squared times the displacement's length.
field_walk_progress :: proc(start, end: World_Position, displacement: [3]i64) -> i64 {
	moved := cast([3]i64)(end - start)
	return moved.x * displacement.x + moved.y * displacement.y + moved.z * displacement.z
}

// Whether a walk from start went less than FIELD_IMPEDED_SIXTEENTHS of
// displacement along it.
field_walk_impeded :: proc(start, end: World_Position, displacement: [3]i64) -> bool {
	wanted := field_walk_progress(start, start + World_Position(displacement), displacement)
	return wanted > 0 && 16 * field_walk_progress(start, end, displacement) < FIELD_IMPEDED_SIXTEENTHS * wanted
}

// The walk's move a step higher: the capsule raised to height over the
// ground under the feet (below, probe_field_ground) where nothing overlaps
// it, swept by motion and dropped back, at most a step height under the
// start. Taken when it went
// farther along motion than the plain walk's end and stands on walkable
// ground (judged over the footprint, so a lip lower than the step whose
// own face is steep counts by the ground round it).
step_field_walk :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, start, plain_end: World_Position, up, forward, motion: [3]i64, height, below: i64) -> (end: World_Position, taken: bool) {
	lift := height - below + 2 * FIELD_PENETRATION_TOLERANCE
	if lift <= 0 {
		return plain_end, false
	}
	raised := start + World_Position(fixed_scale(up, lift))
	if field_capsule_overlaps(world, frames, tuning, raised, up) {
		return plain_end, false
	}
	unused_velocity: [3]i64
	sweep_field_capsule(world, frames, tuning, &raised, up, motion, &unused_velocity, tuning.walkable_cosine)
	risen := fixed_dot(cast([3]i64)(raised - start), up)
	dropped, landed := drop_field_capsule(world, frames, tuning, raised, up, risen + tuning.step_height + FIELD_GROUND_TOLERANCE)
	if !landed || field_walk_progress(start, dropped, motion) <= field_walk_progress(start, plain_end, motion) {
		return plain_end, false
	}
	under := probe_field_ground(world, frames, tuning, dropped, up, {}, true)
	ground := judge_ground_over_footprint(world, frames, tuning, dropped, up, forward, under)
	if !ground.on || !ground.walkable || field_landing_held_by_steep_contact(frames, tuning, dropped, up, motion, under) {
		return plain_end, false
	}
	return dropped, true
}

// A step's landing held up by a machine's collision volume (0230) whose
// contact with the bottom sphere is steeper than walkable while the ray
// under its centre finds walkable ground more than the land tolerance
// (spacing/16) below: the foot of a steep volume, which the next tick's
// settle would drop the player off again. Only the volumes count: a steep
// bump of the field narrower than the footprint (0203) rests the sphere
// the same way and is walked over by design. A landing on a lip's edge
// whose centre is still short of the top, steep at crouch speed, is taken
// when the point a radius ahead reads the top (field_walkable_volume_ahead,
// 0232, test_a_low_lip_is_stepped_onto_at_crouch_and_walking_speed), while
// a steep slope reads steep there too.
field_landing_held_by_steep_contact :: proc(frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up, motion: [3]i64, under: Field_Ground) -> bool {
	contact := frame_body_probe(frames, field_capsule_centre(tuning, feet, up, 0), field_frame_probe_reach(tuning))
	touching := contact.found && contact.distance <= tuning.capsule_radius + FIELD_GROUND_TOLERANCE
	land_tolerance := sample_axis_to_position(1, tuning.spacing_millimetres) / FIELD_GROUND_LAND_SPACING_DIVISOR
	return touching && fixed_dot(contact.normal, up) < tuning.walkable_cosine && under.walkable && under.below > land_tolerance && !field_walkable_volume_ahead(frames, tuning, feet, up, motion)
}

// The point a capsule radius ahead of the bottom sphere's centre along the
// walk is near a volume's walkable surface, as over a lip's top once the
// sphere rests on its edge (0232). A point inside a volume does not count:
// its normal is only that of the nearest face.
field_walkable_volume_ahead :: proc(frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up, motion: [3]i64) -> bool {
	direction, ok := collision_unit(project_onto_plane(motion, up))
	if !ok {
		return false
	}
	point := field_capsule_centre(tuning, feet, up, 0) + World_Position(fixed_scale(direction, tuning.capsule_radius))
	contact := frame_body_probe(frames, point, field_frame_probe_reach(tuning))
	return contact.found && contact.distance >= 0 && contact.distance <= tuning.capsule_radius + FIELD_GROUND_TOLERANCE && fixed_dot(contact.normal, up) >= tuning.walkable_cosine
}

// A step or a mantle's landing: the player stands there, still.
stand_on_field_landing :: proc(player: ^Field_Player, landing: World_Position) {
	player.position = landing
	player.velocity = {}
	player.on_ground = true
	player.ground_normal = player.up
}

// The ground before the move decides: walkable ground (judged over the
// footprint where the feet's reads steep) holds the player and takes a
// jump or a mantle, steep ground slides it, the air lets it fall. On
// steep ground a walk first tries the ledge a step up and a stride ahead.
// An impeded walk on either ground also tries its move a step higher and
// keeps the farther end on walkable ground; a walk still blocked on
// walkable ground tries the ledge, and the feet follow the ground down a
// step's height.
walk_field_player :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, input: Field_Player_Input) {
	resolve_field_penetration(world, frames, tuning, &player.position, player.up, &player.velocity)
	ground := probe_field_ground(world, frames, tuning, player.position, player.up, player.velocity, player.on_ground)
	ground = judge_ground_over_footprint(world, frames, tuning, player.position, player.up, player.forward, ground)
	walk := field_walk_velocity(player^, input.move, field_walk_speed(tuning, input.held, player.crouching))
	raw_walk_motion := walk / VELOCITY_FRACTION_ONE
	walk_direction, walking := normalize_fixed(walk)
	held_on_ground := ground.on && ground.walkable
	step_height := tuning.step_height
	if walking {
		step_height = field_step_height(frames, tuning, player.position, player.up, walk_direction)
	}
	switch {
	case held_on_ground:
		player.velocity = {}
		walk = ground_walk_velocity(walk, ground.normal)
		if .Jump in input.held {
			if walking {
				if landing, found := find_field_ledge(world, frames, tuning, player.position, player.up, walk_direction, tuning.mantle_height, tuning.step_height, ground.below); found {
					stand_on_field_landing(player, landing)
					return
				}
			}
			player.velocity = fixed_scale(player.up, tuning.jump_speed)
			held_on_ground = false
		}
	case ground.on:
		if walking {
			if landing, found := find_field_ledge(world, frames, tuning, player.position, player.up, walk_direction, step_height, 0, ground.below); found {
				stand_on_field_landing(player, landing)
				return
			}
		}
		walk = steep_walk_velocity(walk, ground, player.up, tuning.walkable_cosine)
		player.velocity = limit_speed(player.velocity - fixed_scale(player.up, tuning.gravity), tuning.slide_speed)
	case:
		player.velocity = limit_speed(player.velocity - fixed_scale(player.up, tuning.gravity), tuning.fall_speed_limit)
	}
	held_on_walkable := held_on_ground
	start := player.position
	motion := take_field_motion(walk + player.velocity, &player.motion_fraction)
	fall_motion := player.velocity / VELOCITY_FRACTION_ONE
	walk_motion := motion - fall_motion
	unused_velocity: [3]i64
	sweep_field_capsule(world, frames, tuning, &player.position, player.up, walk_motion, &unused_velocity, tuning.walkable_cosine)
	// On steep ground the walk lost its uphill part, so the step tries
	// the walk the stick asked for.
	wanted := held_on_ground ? walk_motion : raw_walk_motion
	stepped_up := false
	if walking && ground.on && fixed_dot(player.velocity, player.up) <= 0 && field_walk_impeded(start, player.position, wanted) {
		if stepped, taken := step_field_walk(world, frames, tuning, start, player.position, player.up, player.forward, wanted, step_height, ground.below); taken {
			player.position = stepped
			stepped_up = true
			if !held_on_ground {
				player.velocity = {}
				fall_motion = {}
				held_on_ground = true
			}
		}
	}
	sweep_field_capsule(world, frames, tuning, &player.position, player.up, fall_motion, &player.velocity)
	if held_on_ground {
		if held_on_walkable && walking && field_walk_blocked(start, player.position, walk_motion) {
			if landing, found := find_field_ledge(world, frames, tuning, start, player.up, walk_direction, step_height, 0, ground.below); found {
				player.position = landing
			}
		}
		if dropped, landed := drop_field_capsule(world, frames, tuning, player.position, player.up, tuning.step_height + FIELD_GROUND_TOLERANCE); landed {
			player.position = dropped
		}
	}
	after := probe_field_ground(world, frames, tuning, player.position, player.up, player.velocity, held_on_ground || ground.on)
	if held_on_ground && !stepped_up && after.on && after.below > 0 {
		settle_field_player(world, frames, tuning, player, after.below)
		after = probe_field_ground(world, frames, tuning, player.position, player.up, player.velocity, true)
	}
	player.on_ground = after.on
	player.ground_normal = after.normal
}

// On walkable ground the feet go down to their resting height over the
// ground straight under them, and whatever steeper than walkable they
// then touch pushes them across the up only: a walk pushed up a face's
// rounded foot never climbs on without the step, and a player left there
// settles to the floor, while walkable ground lifts them (a lip lower
// than the step whose blurred face is walkable is walked up, 0203). A
// capsule whose bottom sphere rests on a walkable surface of a frame's
// cell or a body's volume (a lip's edge, a rim) is left where the walk's
// drop rested it, since lowering it into the sharp corner and pushing it
// back out would roll it down over the edge (0232). A tick whose walk
// took the move a step higher stands where that landed.
settle_field_player :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, over: i64) {
	if capsule_rests_on_walkable_frame_contact(frames, tuning, player.position, player.up) {
		return
	}
	lowered := player.position - World_Position(fixed_scale(player.up, over))
	unused_velocity: [3]i64
	resolve_field_penetration(world, frames, tuning, &lowered, player.up, &unused_velocity, tuning.walkable_cosine)
	if fixed_dot(cast([3]i64)(player.position - lowered), player.up) > 0 {
		player.position = lowered
	}
}

// Whether the bottom sphere, the one that rests on ground, touches a solid
// frame cell or a body's volume (0230) on a surface no steeper than
// walkable. The upper spheres are not read, so a volume's top edge at
// chest height does not hold the capsule (0232).
capsule_rests_on_walkable_frame_contact :: proc(frames: ^Frame_Table, tuning: Field_Player_Tuning, feet: World_Position, up: [3]i64) -> bool {
	contact := frame_probe(frames, field_capsule_centre(tuning, feet, up, 0), field_frame_probe_reach(tuning))
	return contact.found && contact.distance <= tuning.capsule_radius + FIELD_GROUND_TOLERANCE && fixed_dot(contact.normal, up) >= tuning.walkable_cosine
}

// The developer fly mode in the planet's frame: the heading and its right
// across, Jump and Sneak along the up, no gravity. The field stops it like
// walking unless no clip is on.
fly_field_player :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, input: Field_Player_Input) {
	speed := .Sprint in input.held ? tuning.fly_sprint_speed : tuning.fly_speed
	velocity := field_walk_velocity(player^, input.move, speed)
	if .Jump in input.held {
		velocity += fixed_scale(player.up, speed)
	}
	if .Sneak in input.held {
		velocity -= fixed_scale(player.up, speed)
	}
	player.velocity = {}
	player.on_ground = false
	motion := take_field_motion(velocity, &player.motion_fraction)
	if player.no_clip {
		player.position += World_Position(motion)
		return
	}
	sweep_field_capsule(world, frames, tuning, &player.position, player.up, motion, &player.velocity)
	player.velocity = {}
}

// The chunk a sample below the feet lies in. While it is missing the
// ground reads as air, so the player holds still instead of falling.
field_ground_loaded :: proc(world: ^Field_World, tuning: Field_Player_Tuning, player: Field_Player) -> bool {
	below := player.position - World_Position(fixed_scale(player.up, sample_axis_to_position(1, tuning.spacing_millimetres)))
	return sample_to_field_chunk_coordinate(world_position_to_sample(below, tuning.spacing_millimetres)) in world.chunks
}

tick_field_player :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, input: Field_Player_Input) {
	player.previous_position = player.position
	apply_field_player_toggles(player, input.just_pressed)
	update_field_jump_double_tap(player, input)
	orient_field_player(player)
	turn_field_player(player, input.turn)
	// The crouch is decided from the input and the world before the move,
	// here and in the prediction alike (0218).
	update_field_crouch(world, frames, tuning, player, .Sneak in input.held || player.crouch_held)
	posture := field_posture_tuning(tuning, player.crouching)
	switch {
	case player.flying && player.no_clip:
		fly_field_player(world, frames, posture, player, input)
	case !field_ground_loaded(world, posture, player^):
		player.velocity = {}
	case player.flying:
		fly_field_player(world, frames, posture, player, input)
	case:
		walk_field_player(world, frames, posture, player, input)
	}
	orient_field_player(player)
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	player.target = raycast_field(world, posture.spacing_millimetres, field_player_eye(player^, posture), look, posture.reach)
}
