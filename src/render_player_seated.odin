package game

import "core:math"
import "core:math/linalg"

// The player seated in the pod's chair (work item 0268, doc/presentation.md,
// The player). The body is built in the chair's basis: forward the chair's
// facing, up the pod frame's, the side (the model's +z, the right) their
// cross, the origin the seat's eye. The torso leans back about the hip so
// the model's eye lands on the seat's, the thighs lie level, the shins
// hang straight down (the legs cut at the knee, Player_Leg_Part), the
// straight arms reach forward and inward so the hands rest on the knees,
// and the head turns to the look in the chair's basis within its limits.
// Pure: the transforms take the model's blocks to the world, and the draw
// (draw_field_player_seated) multiplies player_model_scale.

// The chair's back leans 8.5 degrees.
SEATED_RECLINE_DEGREES :: 8.0
SEATED_THIGH_DEGREES :: 82.0
SEATED_KNEE_DEGREES :: -90.0
SEATED_ARM_DEGREES :: 42.0
SEATED_ARM_INWARD_DEGREES :: 14.0
SEATED_HEAD_YAW_LIMIT_DEGREES :: 75.0

// The seat's eye in metres, the chair's facing and the frame's up as unit
// vectors.
Seated_Chair :: struct {
	eye:     [3]f32,
	forward: [3]f32,
	up:      [3]f32,
}

// The legs' entries of limbs are unused: the legs are drawn by their parts.
Seated_Body_Transforms :: struct {
	limbs:     [Player_Limb]matrix[4, 4]f32,
	leg_parts: [Player_Leg_Part]matrix[4, 4]f32,
}

// The chair's basis: forward, up and side as the model's x, y and z, at
// the seat's eye.
seated_chair_transform :: proc(chair: Seated_Chair) -> matrix[4, 4]f32 {
	side := linalg.cross(chair.forward, chair.up)
	return matrix[4, 4]f32{
		chair.forward.x, chair.up.x, side.x, chair.eye.x,
		chair.forward.y, chair.up.y, side.y, chair.eye.y,
		chair.forward.z, chair.up.z, side.z, chair.eye.z,
		0, 0, 0, 1,
	}
}

// The torso leant back about the hip, the model's eye (0, eye_height, 0)
// on the seat's.
seated_torso_transform :: proc(chair: Seated_Chair, eye_height, hip_height: f32) -> matrix[4, 4]f32 {
	recline := f32(SEATED_RECLINE_DEGREES) * math.RAD_PER_DEG
	reach := eye_height - hip_height
	hip := [3]f32{math.sin(recline) * reach, -math.cos(recline) * reach, 0}
	return seated_chair_transform(chair) * translation_matrix(hip) * limb_swing_transform({}, SEATED_RECLINE_DEGREES) * translation_matrix({0, -hip_height, 0})
}

// The look in the chair's basis, in degrees: positive yaw to the right,
// positive pitch up, each clamped to the head's limits.
seated_head_angles :: proc(chair: Seated_Chair, look: [3]f32) -> (yaw, pitch: f32) {
	side := linalg.cross(chair.forward, chair.up)
	yaw = math.atan2(linalg.dot(look, side), linalg.dot(look, chair.forward)) * math.DEG_PER_RAD
	pitch = math.asin(clamp(linalg.dot(look, chair.up), -1, 1)) * math.DEG_PER_RAD
	return clamp(yaw, -SEATED_HEAD_YAW_LIMIT_DEGREES, SEATED_HEAD_YAW_LIMIT_DEGREES), clamp(pitch, -HEAD_PITCH_LIMIT_DEGREES, HEAD_PITCH_LIMIT_DEGREES)
}

// The head at the neck of the reclined torso, turned in the chair's basis
// (upright, not leant with the torso).
seated_head_transform :: proc(chair: Seated_Chair, torso: matrix[4, 4]f32, neck: [3]f32, yaw, pitch: f32) -> matrix[4, 4]f32 {
	rotation := seated_chair_transform(chair)
	rotation[3].xyz = {}
	turn := linalg.matrix4_rotate_f32(-yaw * math.RAD_PER_DEG, {0, 1, 0}) * linalg.matrix4_rotate_f32(pitch * math.RAD_PER_DEG, {0, 0, 1})
	return translation_matrix(transform_point(torso, neck)) * rotation * turn * translation_matrix(-neck)
}

// An arm held forward and turned inward; side +1 for the right arm, -1
// for the left.
seated_arm_transform :: proc(torso: matrix[4, 4]f32, shoulder: [3]f32, side: f32) -> matrix[4, 4]f32 {
	inward := linalg.matrix4_rotate_f32(side * SEATED_ARM_INWARD_DEGREES * math.RAD_PER_DEG, {1, 0, 0})
	return torso * translation_matrix(shoulder) * limb_swing_transform({}, SEATED_ARM_DEGREES) * inward * translation_matrix(-shoulder)
}

// Every part of the seated body; the hip height is the left leg's pivot.
seated_player_transforms :: proc(chair: Seated_Chair, eye_height: f32, pivots: [Player_Limb][3]f32, leg_part_pivots: [Player_Leg_Part][3]f32, look: [3]f32) -> (body: Seated_Body_Transforms) {
	torso := seated_torso_transform(chair, eye_height, pivots[.Leg_Left].y)
	yaw, pitch := seated_head_angles(chair, look)
	body.limbs[.Torso] = torso
	body.limbs[.Head] = seated_head_transform(chair, torso, pivots[.Head], yaw, pitch)
	body.limbs[.Arm_Left] = seated_arm_transform(torso, pivots[.Arm_Left], -1)
	body.limbs[.Arm_Right] = seated_arm_transform(torso, pivots[.Arm_Right], 1)
	for leg in ([2][2]Player_Leg_Part{{.Thigh_Left, .Shin_Left}, {.Thigh_Right, .Shin_Right}}) {
		thigh, shin := leg[0], leg[1]
		body.leg_parts[thigh] = torso * limb_swing_transform(leg_part_pivots[thigh], SEATED_THIGH_DEGREES)
		body.leg_parts[shin] = body.leg_parts[thigh] * limb_swing_transform(leg_part_pivots[shin], SEATED_KNEE_DEGREES)
	}
	return body
}
