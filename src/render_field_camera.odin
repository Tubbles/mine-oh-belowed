package game

import rl "shared:raylib"

// The first and third person cameras of the field player (work item 0170):
// the camera's up is the player's up, so the horizon tilts with the
// planet as the player walks round it. The look comes from the integer
// frame (field_look_direction); the camera is f32 metres from the planet's
// centre, as the field renderer draws. The third person camera is not yet
// pulled in by the field (the block camera's third_person_position). The
// eye dips over the crouch's progress (0218).

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

// distance and shoulder place the third person camera behind the eye and
// to its right (settings.third_person_distance and _shoulder).
field_camera :: proc(view: Field_Camera_View, mode: Camera_Mode, distance, shoulder, field_of_view: f32) -> rl.Camera3D {
	up := unit_vector_to_f32(view.up)
	look := unit_vector_to_f32(field_look_direction(view.forward, view.up, view.yaw, view.pitch))
	position := world_position_to_metres(view.eye)
	if mode == .Third_Person {
		right := unit_vector_to_f32(fixed_cross(field_heading(view.forward, view.up, view.yaw), view.up))
		position += -look * distance + up * THIRD_PERSON_HEIGHT + right * shoulder
	}
	return rl.Camera3D{position = position, target = position + look, up = up, fovy = field_of_view, projection = .PERSPECTIVE}
}
