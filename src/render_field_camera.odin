package game

import rl "shared:raylib"

// The first and third person cameras of the field player (work item 0170):
// the camera's up is the player's up, so the horizon tilts with the
// planet as the player walks round it. The look comes from the integer
// frame (field_look_direction); the camera is f32 metres from the planet's
// centre, as the field renderer draws. The eye dips over the crouch's
// progress (0218). The third person camera is pulled in along its line
// from the eye by the field, the solid frame cells and volumes and the
// trunks, kept THIRD_PERSON_WALL_MARGIN off the surface it meets
// (pulled_in_field_camera, 0220).

// A full swing of the crouch's progress, frame time, presentation only
// (0218).
CROUCH_EASE_SECONDS :: 0.15

Field_Camera_View :: struct {
	eye:     World_Position,
	up:      [3]i64,
	forward: [3]i64,
	yaw:     i32,
	pitch:   i32,
}

unit_vector_to_f32 :: proc(vector: [3]i64) -> [3]f32 {
	return {f32(f64(vector.x) / UNIT_VECTOR_ONE), f32(f64(vector.y) / UNIT_VECTOR_ONE), f32(f64(vector.z) / UNIT_VECTOR_ONE)}
}

world_position_to_metres :: proc(position: World_Position) -> [3]f32 {
	return {f32(f64(position.x) / POSITION_UNITS_PER_METRE), f32(f64(position.y) / POSITION_UNITS_PER_METRE), f32(f64(position.z) / POSITION_UNITS_PER_METRE)}
}

// The crouch's progress from 0 (standing) to 1 (crouched): towards 1
// while crouching, towards 0 otherwise, a full swing in
// CROUCH_EASE_SECONDS of frame time.
advance_field_crouch :: proc(progress: f32, crouching: bool, frame_seconds: f32) -> f32 {
	step := frame_seconds / CROUCH_EASE_SECONDS
	return crouching ? min(progress + step, 1) : max(progress - step, 0)
}

// The player's entry, 0 (standing) out of range.
field_crouch_progress_of :: proc(progress: []f32, index: int) -> f32 {
	return index >= 0 && index < len(progress) ? progress[index] : 0
}

// Smoothstep of the progress.
field_crouch_eased :: proc(progress: f32) -> f32 {
	return progress * progress * (3 - 2 * progress)
}

// The eye's height over the feet at the crouch's progress, position units.
field_eye_height_units :: proc(tuning: Field_Player_Tuning, progress: f32) -> i64 {
	return tuning.eye_height + i64(f32(tuning.crouch_eye_height - tuning.eye_height) * field_crouch_eased(progress))
}

// The body's scale along the up: 1 standing, the crouch height over the
// standing one crouched.
field_body_up_scale :: proc(tuning: Field_Player_Tuning, progress: f32) -> f32 {
	ratio := f32(tuning.crouch_capsule_height) / f32(tuning.capsule_height)
	return 1 + (ratio - 1) * field_crouch_eased(progress)
}

// The eye between two ticks: alpha from 0 (the previous tick) to 1. tuning
// is the base tuning; the eye's height follows crouch_progress.
field_player_view :: proc(player: Field_Player, tuning: Field_Player_Tuning, alpha: f32, crouch_progress: f32) -> Field_Camera_View {
	eye := player.position + World_Position(fixed_scale(player.up, field_eye_height_units(tuning, crouch_progress)))
	step := cast([3]i64)(player.position - player.previous_position)
	back := [3]i64{i64(f32(step.x) * (1 - alpha)), i64(f32(step.y) * (1 - alpha)), i64(f32(step.z) * (1 - alpha))}
	return {eye = eye - World_Position(back), up = player.up, forward = player.forward, yaw = player.yaw, pitch = player.pitch}
}

// viewer_body_shown for a field view, the body's axis from the eye down
// the up by the eye's height at crouch_progress (the one the view was
// built with).
field_viewer_body_shown :: proc(mode: Camera_Mode, camera_position: [3]f32, view: Field_Camera_View, tuning: Field_Player_Tuning, crouch_progress: f32) -> bool {
	eye_height := f32(f64(field_eye_height_units(tuning, crouch_progress)) / POSITION_UNITS_PER_METRE)
	return viewer_body_shown(mode, camera_position, world_position_to_metres(view.eye), unit_vector_to_f32(view.up), eye_height)
}

// distance and shoulder place the third person camera behind the eye and
// to its right (settings.third_person_distance and _shoulder).
field_camera :: proc(view: Field_Camera_View, mode: Camera_Mode, distance, shoulder, field_of_view: f32) -> rl.Camera3D {
	up := unit_vector_to_f32(view.up)
	look := unit_vector_to_f32(field_look_direction(view.forward, view.up, view.yaw, view.pitch))
	position := world_position_to_metres(view.eye)
	if mode == .Third_Person {
		position += field_third_person_offset(view, distance, shoulder)
	}
	return rl.Camera3D{position = position, target = position + look, up = up, fovy = field_of_view, projection = .PERSPECTIVE}
}

// The third person camera's offset from the eye in metres: behind the
// look by distance, THIRD_PERSON_HEIGHT along the up and shoulder to the
// right.
field_third_person_offset :: proc(view: Field_Camera_View, distance, shoulder: f32) -> [3]f32 {
	up := unit_vector_to_f32(view.up)
	look := unit_vector_to_f32(field_look_direction(view.forward, view.up, view.yaw, view.pitch))
	right := unit_vector_to_f32(fixed_cross(field_heading(view.forward, view.up, view.yaw), view.up))
	return -look * distance + up * THIRD_PERSON_HEIGHT + right * shoulder
}

// The nearest surface along the unit direction within reach: the field,
// the solid frame cells and the bodies (field_solid_raycast, the walk's
// filter), or a trunk where that is nearer, with the surface's normal.
field_camera_obstacle :: proc(world: ^Field_World, frames: ^Frame_Table, trunks: []Field_Capsule, spacing_millimetres: int, origin: World_Position, direction: [3]i64, reach: i64) -> (distance: i64, normal: [3]i64, hit: bool) {
	solid := field_solid_raycast(world, frames, spacing_millimetres, origin, direction, reach)
	distance, normal, hit = solid.distance, solid.normal, solid.hit
	for trunk in trunks {
		along, met := field_trunk_ray_distance(trunk, origin, direction, reach)
		if met && (!hit || along < distance) {
			distance, normal, hit = along, field_capsule_normal_at(trunk, field_ray_point(origin, direction, along)), true
		}
	}
	return
}

// The unit vector from the nearest point of the capsule's axis to the
// point; zero on the axis.
field_capsule_normal_at :: proc(capsule: Field_Capsule, point: World_Position) -> [3]i64 {
	along := clamp(fixed_dot(cast([3]i64)(point - capsule.bottom), capsule.up), 0, capsule.length)
	normal, _ := normalize_fixed(cast([3]i64)(point - capsule.bottom) - fixed_scale(capsule.up, along))
	return normal
}

// Metres along the ray where the camera stops, distance metres to the
// surface met at cosine (between the ray and the surface's inward
// normal): THIRD_PERSON_WALL_MARGIN off the surface along its normal, or
// the eye (0) where the margin does not fit, which covers a ray starting
// in the ground and a normal facing away.
field_camera_pulled_distance :: proc(distance, cosine: f32) -> f32 {
	if cosine * distance <= THIRD_PERSON_WALL_MARGIN {
		return 0
	}
	return distance - THIRD_PERSON_WALL_MARGIN / cosine
}

// The eye moved by offset (metres), pulled in when the field, a solid
// frame cell, a body or a trunk lies between the eye and that spot; the
// field's third_person_position.
field_third_person_position :: proc(world: ^Field_World, frames: ^Frame_Table, trunks: []Field_Capsule, spacing_millimetres: int, eye: World_Position, offset: [3]f32) -> [3]f32 {
	units := [3]i64{i64(offset.x * POSITION_UNITS_PER_METRE), i64(offset.y * POSITION_UNITS_PER_METRE), i64(offset.z * POSITION_UNITS_PER_METRE)}
	direction, _ := normalize_fixed(units)
	reach := vector_length(units)
	distance, normal, hit := field_camera_obstacle(world, frames, trunks, spacing_millimetres, eye, direction, reach)
	if !hit {
		return world_position_to_metres(eye) + offset
	}
	cosine := -f32(fixed_dot(direction, normal)) / UNIT_VECTOR_ONE
	return world_position_to_metres(eye) + unit_vector_to_f32(direction) * field_camera_pulled_distance(f32(distance) / POSITION_UNITS_PER_METRE, cosine)
}

// field_camera with the third person camera pulled in by the field, the
// frames and the trunks round the eye; the look is field_camera's. Runs
// per viewport per frame and reads only; the tree lists are temp
// allocated.
pulled_in_field_camera :: proc(simulation: ^Simulation_State, content: Field_Content, view: Field_Camera_View, mode: Camera_Mode, distance, shoulder, field_of_view: f32) -> rl.Camera3D {
	camera := field_camera(view, mode, distance, shoulder, field_of_view)
	if mode != .Third_Person {
		return camera
	}
	reach := i64((distance + THIRD_PERSON_HEIGHT + abs(shoulder)) * POSITION_UNITS_PER_METRE) + millimetres_to_position_units(FIELD_TREE_QUERY_MARGIN_MILLIMETRES)
	trunks := field_tree_trunks(field_trees_near(&simulation.field, view.eye, reach), content)
	offset := field_third_person_offset(view, distance, shoulder)
	position := field_third_person_position(&simulation.field.world, &simulation.world.entities.frames, trunks, simulation.field.spacing_millimetres, view.eye, offset)
	camera.target += position - camera.position
	camera.position = position
	return camera
}
