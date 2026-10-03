package game

import "core:fmt"
import "core:math"
import "model_vox"

// The inserter's arm (work item 0175): a base, a turret that turns about
// the vertical, an upper arm, a forearm, a gripper and two fingers, each
// its own file in data/models/ (<model>_turret.vox and the rest of
// arm_part_suffixes, the base being <model>.vox), written by
// tools/make_placeholder_models.py. Every file is the whole
// ARM_MODEL_FRAME at ARM_VOXEL_MILLIMETRES with only its part filled,
// standing in the authored pose: the arm straight up, the gripper's
// fingers pointing up, the joints on the frame's vertical centre line at
// the heights below. The meshes are in voxel units (x and z centred, y
// from the bottom), so arm_voxel_scale turns them into metres.
//
// Real scale: the parts keep their thickness in metres on every frame.
// The two segments scale with the span from the shoulder to the wrist
// over a cell at the reach (arm_dimensions), so they are their authored
// length at 2 m over the 500 mm data pitch and the elbow bends alike on
// every frame; the hand stops just over the target cell's top; the base
// plate's width follows the pitch, so the base fills one cell. The
// inserter's footprint stays one cell until the slice's real sizes (0179).
//
// The pose is a pure function of the inserter's cycle fraction
// (inserter_cycle_fraction): rest folded over the base at 0, reach to the
// pickup cell, grab, swing over the right hand side, lower onto the drop
// cell at one half, release, swing back and fold. The cycle runs on the
// simulation's ticks of movement, so the cadence follows the work and an
// idle arm rests. Floats only here and in the renderer; the simulation
// never sees a pose.

ARM_VOXEL_MILLIMETRES :: 25
ARM_MODEL_FRAME :: [3]i32{24, 128, 24}
// Authored, in metres: the shoulder's height above the base's bottom,
// the segments from joint to joint, and the wrist to the hand between
// the fingertips. The segments together are longer than the reach, so
// the elbow stays bent at full reach.
ARM_SHOULDER_HEIGHT_METRES :: 0.55
ARM_UPPER_ARM_METRES :: 1.25
ARM_FOREARM_METRES :: 1.05
ARM_GRIPPER_METRES :: 0.3
// The frame the authored segments are shaped for: 2 m of reach over the
// 500 mm pitch, where the arm is drawn at its real size, and the base
// plate's side as authored, one cell of that pitch.
ARM_AUTHORED_REACH_METRES :: 2.0
ARM_AUTHORED_PITCH_METRES :: 0.5
ARM_AUTHORED_BASE_METRES :: 0.5
// The hand stops this far above the top of the target cell; mid swing
// it is lifted and drawn in.
ARM_WORK_CLEARANCE_METRES :: 0.05
ARM_CARRY_LIFT_METRES :: 0.45
ARM_CARRY_REACH_SHARE :: 0.62
// The folded rest, from the turret's axis in the arm's plane: the elbow
// leans back behind it and the wrist hangs forward of it, at most the
// base's half width less the gripper's half width.
ARM_REST_ELBOW_OFFSET_METRES :: -0.1
ARM_REST_WRIST_OFFSET_METRES :: 0.16
ARM_GRIPPER_HALF_WIDTH_METRES :: 0.09
// The elbow's hub above the elbow, for the folded arm's top.
ARM_ELBOW_HUB_METRES :: 0.1
// Each finger's offset from the gripper's middle, across the arm.
ARM_FINGER_OPEN_METRES :: 0.13
ARM_FINGER_CLOSED_METRES :: 0.115
// The work lamp on the wrist block, in authored metres (x and z centred,
// y from the bottom): its glow voxels light up and a point light shines
// from here while the arm moves.
ARM_LAMP_POINT :: [3]f32{0, 2.9, 0.1125}

// The cycle fraction at which each move ends: reach out from rest, grab,
// swing to the middle of the turn, swing on and lower onto the drop
// cell (held until one half), release, swing back, fold to rest.
ARM_REACH_END :: 0.12
ARM_GRAB_END :: 0.18
ARM_SWING_MIDDLE :: 0.31
ARM_SWING_END :: 0.44
ARM_DROP_FRACTION :: 0.5
ARM_RELEASE_END :: 0.56
ARM_RETURN_MIDDLE :: 0.72

// The yaw over the pickup cell (behind, -x) and the drop cell (ahead,
// +x); a quarter turn about y takes +x to -z, so -pi/2 points the arm to
// the right hand side (+z), which the swing passes.
ARM_PICKUP_YAW :: -math.PI
ARM_DROP_YAW :: 0.0

Arm_Part :: enum u8 {
	Base,
	Turret,
	Upper_Arm,
	Forearm,
	Gripper,
	Finger,
}

@(rodata)
arm_part_suffixes := [Arm_Part]string {
	.Base      = "",
	.Turret    = "_turret",
	.Upper_Arm = "_upper_arm",
	.Forearm   = "_forearm",
	.Gripper   = "_gripper",
	.Finger    = "_finger",
}

// What the pose uses, in metres. stretch scales the authored segments,
// base_scale the base across (its width follows the pitch), work_height
// is the hand's height over the pickup and drop cells and rest_wrist the
// folded wrist's offset from the turret's axis.
Arm_Dimensions :: struct {
	stretch:     f32,
	base_scale:  f32,
	upper_arm:   f32,
	forearm:     f32,
	reach:       f32,
	work_height: f32,
	rest_wrist:  f32,
}

// Radians; shoulder and elbow are the upper arm's and the forearm's
// angle above the horizontal in the arm's plane, wrist the gripper's
// (pointing down at -pi/2). grip is 0 open and 1 closed.
Arm_Joint_Angles :: struct {
	yaw:      f32,
	shoulder: f32,
	elbow:    f32,
	wrist:    f32,
	grip:     f32,
}

// From the shoulder to the wrist over a cell at the reach.
arm_working_span :: proc(reach_metres, work_height_metres: f32) -> f32 {
	up := work_height_metres + ARM_GRIPPER_METRES - ARM_SHOULDER_HEIGHT_METRES
	return math.sqrt(reach_metres * reach_metres + up * up)
}

// The arm of an inserter whose reach on its frame is reach_metres, the
// frame's cell pitch_metres: the segments scale with the span they cover
// at work, so the elbow bends as much on every frame as on the authored
// one (stretch 1 at 2 m over 500 mm), and the hand stops over the top of
// a cell of the pitch.
arm_dimensions :: proc(reach_metres, pitch_metres: f32) -> Arm_Dimensions {
	work_height := pitch_metres + ARM_WORK_CLEARANCE_METRES
	authored := arm_working_span(ARM_AUTHORED_REACH_METRES, ARM_AUTHORED_PITCH_METRES + ARM_WORK_CLEARANCE_METRES)
	stretch := arm_working_span(reach_metres, work_height) / authored
	return Arm_Dimensions {
		stretch = stretch,
		base_scale = pitch_metres / ARM_AUTHORED_BASE_METRES,
		upper_arm = ARM_UPPER_ARM_METRES * stretch,
		forearm = ARM_FOREARM_METRES * stretch,
		reach = reach_metres,
		work_height = work_height,
		rest_wrist = min(ARM_REST_WRIST_OFFSET_METRES, pitch_metres / 2 - ARM_GRIPPER_HALF_WIDTH_METRES),
	}
}

// The arm on a frame: its reach in whole cells and the frame's pitch.
arm_dimensions_on_frame :: proc(reach_cells: i32, pitch_millimetres: int) -> Arm_Dimensions {
	pitch := f32(pitch_millimetres) / MILLIMETRES_PER_METRE
	return arm_dimensions(f32(max(reach_cells, 1)) * pitch, pitch)
}

// The shoulder and elbow angles that put the wrist at (distance, height)
// from the turret's axis and the base's bottom, the elbow up. A wrist out
// of reach is approached along the line to it.
arm_reach_angles :: proc(dimensions: Arm_Dimensions, distance, height: f32) -> (shoulder, elbow: f32) {
	along, up := distance, height - ARM_SHOULDER_HEIGHT_METRES
	upper, fore := dimensions.upper_arm, dimensions.forearm
	span := clamp(math.sqrt(along * along + up * up), abs(upper - fore) + 0.001, upper + fore - 0.0001)
	inner := math.acos(clamp((upper * upper + span * span - fore * fore) / (2 * upper * span), -1, 1))
	shoulder = math.atan2(up, along) + inner
	elbow_point := [2]f32{upper * math.cos(shoulder), ARM_SHOULDER_HEIGHT_METRES + upper * math.sin(shoulder)}
	direction := [2]f32{along, height} - elbow_point
	return shoulder, math.atan2(direction.y, direction.x)
}

// The hand over a cell: at the reach, the wrist the gripper above it.
arm_work_pose :: proc(dimensions: Arm_Dimensions, yaw, distance, lift, grip: f32) -> Arm_Joint_Angles {
	shoulder, elbow := arm_reach_angles(dimensions, distance, dimensions.work_height + lift + ARM_GRIPPER_METRES)
	return Arm_Joint_Angles{yaw = yaw, shoulder = shoulder, elbow = elbow, wrist = -math.PI / 2, grip = grip}
}

// Folded over the base: the upper arm standing with its elbow just
// behind the turret's axis, the forearm hanging forward and down to the
// wrist beside the axis, for any stretch of the segments.
arm_rest_pose :: proc(dimensions: Arm_Dimensions) -> Arm_Joint_Angles {
	elbow_offset := f32(ARM_REST_ELBOW_OFFSET_METRES)
	forearm_offset := dimensions.rest_wrist - elbow_offset
	return Arm_Joint_Angles {
		yaw = ARM_PICKUP_YAW,
		shoulder = math.acos(clamp(elbow_offset / dimensions.upper_arm, -1, 1)),
		elbow = -math.acos(clamp(forearm_offset / dimensions.forearm, -1, 1)),
		wrist = -math.PI / 2,
	}
}

// The folded arm's highest point above the base's bottom: the elbow's
// hub.
arm_rest_top_metres :: proc(dimensions: Arm_Dimensions) -> f32 {
	return arm_joints(dimensions, arm_rest_pose(dimensions)).elbow.y + ARM_ELBOW_HUB_METRES
}

// Eases in and out over the share of a move done.
arm_ease :: proc(share: f32) -> f32 {
	clamped := clamp(share, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
}

arm_blend :: proc(from, to: Arm_Joint_Angles, share: f32) -> Arm_Joint_Angles {
	eased := arm_ease(share)
	return Arm_Joint_Angles {
		yaw = math.lerp(from.yaw, to.yaw, eased),
		shoulder = math.lerp(from.shoulder, to.shoulder, eased),
		elbow = math.lerp(from.elbow, to.elbow, eased),
		wrist = math.lerp(from.wrist, to.wrist, eased),
		grip = math.lerp(from.grip, to.grip, eased),
	}
}

move_share :: proc(fraction, start, end: f32) -> f32 {
	return (fraction - start) / (end - start)
}

// The pose at a cycle fraction from 0 up to 1 (0 resting, one half over
// the drop cell).
arm_pose_at :: proc(dimensions: Arm_Dimensions, fraction: f32) -> Arm_Joint_Angles {
	rest := arm_rest_pose(dimensions)
	pickup_open := arm_work_pose(dimensions, ARM_PICKUP_YAW, dimensions.reach, 0, 0)
	pickup_closed := arm_work_pose(dimensions, ARM_PICKUP_YAW, dimensions.reach, 0, 1)
	carry_full := arm_work_pose(dimensions, (ARM_PICKUP_YAW + ARM_DROP_YAW) / 2, dimensions.reach * ARM_CARRY_REACH_SHARE, ARM_CARRY_LIFT_METRES, 1)
	carry_empty := carry_full
	carry_empty.grip = 0
	drop_closed := arm_work_pose(dimensions, ARM_DROP_YAW, dimensions.reach, 0, 1)
	drop_open := arm_work_pose(dimensions, ARM_DROP_YAW, dimensions.reach, 0, 0)
	switch {
	case fraction < ARM_REACH_END:
		return arm_blend(rest, pickup_open, move_share(fraction, 0, ARM_REACH_END))
	case fraction < ARM_GRAB_END:
		return arm_blend(pickup_open, pickup_closed, move_share(fraction, ARM_REACH_END, ARM_GRAB_END))
	case fraction < ARM_SWING_MIDDLE:
		return arm_blend(pickup_closed, carry_full, move_share(fraction, ARM_GRAB_END, ARM_SWING_MIDDLE))
	case fraction < ARM_SWING_END:
		return arm_blend(carry_full, drop_closed, move_share(fraction, ARM_SWING_MIDDLE, ARM_SWING_END))
	case fraction < ARM_DROP_FRACTION:
		return drop_closed
	case fraction < ARM_RELEASE_END:
		return arm_blend(drop_closed, drop_open, move_share(fraction, ARM_DROP_FRACTION, ARM_RELEASE_END))
	case fraction < ARM_RETURN_MIDDLE:
		return arm_blend(drop_open, carry_empty, move_share(fraction, ARM_RELEASE_END, ARM_RETURN_MIDDLE))
	}
	return arm_blend(carry_empty, rest, move_share(fraction, ARM_RETURN_MIDDLE, 1))
}

// The item in hand shows from the grab to the release; the simulation
// takes it at the cycle's start, while the arm still unfolds.
arm_shows_held_item :: proc(fraction: f32) -> bool {
	return fraction >= ARM_GRAB_END && fraction <= ARM_RELEASE_END
}

stretch_matrix :: proc(stretch: f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		1, 0, 0, 0,
		0, stretch, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

uniform_scale_matrix :: proc(scale: f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		scale, 0, 0, 0,
		0, scale, 0, 0,
		0, 0, scale, 0,
		0, 0, 0, 1,
	}
}

// Voxel units of a part's mesh to the authored metres.
arm_voxel_scale :: proc() -> matrix[4, 4]f32 {
	return uniform_scale_matrix(f32(ARM_VOXEL_MILLIMETRES) / MILLIMETRES_PER_METRE)
}

// The joints in the arm's plane (x out from the axis, y up) before the
// yaw.
Arm_Joints :: struct {
	elbow: [3]f32,
	wrist: [3]f32,
	hand:  [3]f32,
}

arm_plane_point :: proc(start: [3]f32, length, angle: f32) -> [3]f32 {
	return start + {length * math.cos(angle), length * math.sin(angle), 0}
}

arm_joints :: proc(dimensions: Arm_Dimensions, angles: Arm_Joint_Angles) -> Arm_Joints {
	elbow := arm_plane_point({0, ARM_SHOULDER_HEIGHT_METRES, 0}, dimensions.upper_arm, angles.shoulder)
	wrist := arm_plane_point(elbow, dimensions.forearm, angles.elbow)
	return Arm_Joints{elbow = elbow, wrist = wrist, hand = arm_plane_point(wrist, ARM_GRIPPER_METRES, angles.wrist)}
}

// A segment authored upright from its joint, turned to its angle and
// stretched along itself, with its joint moved to where the pose puts it.
segment_transform :: proc(joint, authored_joint: [3]f32, angle, stretch: f32) -> matrix[4, 4]f32 {
	return translation_matrix(joint) * axis_rotation_matrix(2, angle - math.PI / 2) * stretch_matrix(stretch) * translation_matrix(-authored_joint)
}

// Each part's authored metres to the arm's space; the finger's transform is the one at +z, the other finger is
// its mirror across the gripper (arm_finger_transforms).
arm_part_transforms :: proc(dimensions: Arm_Dimensions, angles: Arm_Joint_Angles) -> (transforms: [Arm_Part]matrix[4, 4]f32) {
	shoulder := [3]f32{0, ARM_SHOULDER_HEIGHT_METRES, 0}
	authored_elbow := shoulder + {0, ARM_UPPER_ARM_METRES, 0}
	authored_wrist := authored_elbow + {0, ARM_FOREARM_METRES, 0}
	joints := arm_joints(dimensions, angles)
	yaw := axis_rotation_matrix(1, angles.yaw)
	transforms[.Base] = matrix[4, 4]f32{
		dimensions.base_scale, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, dimensions.base_scale, 0,
		0, 0, 0, 1,
	}
	transforms[.Turret] = yaw
	transforms[.Upper_Arm] = yaw * segment_transform(shoulder, shoulder, angles.shoulder, dimensions.stretch)
	transforms[.Forearm] = yaw * segment_transform(joints.elbow, authored_elbow, angles.elbow, dimensions.stretch)
	transforms[.Gripper] = yaw * segment_transform(joints.wrist, authored_wrist, angles.wrist, 1)
	transforms[.Finger] = transforms[.Gripper]
	return transforms
}

arm_finger_offset :: proc(grip: f32) -> f32 {
	return ARM_FINGER_OPEN_METRES + (ARM_FINGER_CLOSED_METRES - ARM_FINGER_OPEN_METRES) * clamp(grip, 0, 1)
}

// The two fingers, one each side of the gripper's middle.
arm_finger_transforms :: proc(gripper: matrix[4, 4]f32, grip: f32) -> [2]matrix[4, 4]f32 {
	offset := arm_finger_offset(grip)
	return {gripper * translation_matrix({0, 0, offset}), gripper * translation_matrix({0, 0, -offset})}
}

// The hand in the arm's space.
arm_hand_point :: proc(dimensions: Arm_Dimensions, angles: Arm_Joint_Angles) -> [3]f32 {
	return transform_point(axis_rotation_matrix(1, angles.yaw), arm_joints(dimensions, angles).hand)
}

// The arm's space to its entity's cells: onto the footprint's bottom
// centre, turned to the facing (model_transform), metres to cells of
// the frame's pitch.
arm_entity_transform :: proc(common: Entity_Common, pitch_millimetres: int) -> matrix[4, 4]f32 {
	cells_per_metre := MILLIMETRES_PER_METRE / f32(pitch_millimetres)
	return model_transform(common.origin, common.size, common.rotation) * uniform_scale_matrix(cells_per_metre)
}

// The meshes. Loaded with the machine models (load_machine_model_mesh):
// every part file or none, each of ARM_MODEL_FRAME voxels.
load_arm_part_meshes :: proc(data_directory: string, machine: Machine, allocator := context.allocator) -> (parts: [Arm_Part]Model_Layers, problem: string) {
	for suffix, part in arm_part_suffixes {
		id := fmt.tprintf("%s%s", machine.model, suffix)
		model: model_vox.Voxel_Model
		if model, problem = model_vox.load_voxel_model_file(model_vox.model_file_path(data_directory, id), context.temp_allocator); problem == "" && model.size != ARM_MODEL_FRAME {
			problem = fmt.tprintf("model %s is %v voxels, not %v", id, model.size, ARM_MODEL_FRAME)
		}
		if problem == "" {
			parts[part], problem = mesh_voxel_model(model, model.size, allocator)
		}
		if problem != "" {
			destroy_arm_part_meshes(parts)
			return {}, fmt.tprintf("machine %q: %s: %s", machine.id, id, problem)
		}
	}
	return parts, ""
}

destroy_arm_part_meshes :: proc(parts: [Arm_Part]Model_Layers) {
	for layers in parts {
		destroy_model_layers(layers)
	}
}
