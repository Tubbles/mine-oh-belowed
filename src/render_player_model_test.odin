package game

import "core:math"
import "core:strings"
import "core:testing"

// The player model set (work item 0066): the committed limb files load,
// fill the expected voxels, and their pivots lie inside the frame. No
// raylib: only the files, the meshes and the transforms.

@(test)
test_player_model_set_loads_with_limb_bounds_and_pivots :: proc(t: ^testing.T) {
	mesh, problem := load_player_model_mesh(test_data_directory(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	expected := [Player_Limb]Voxel_Bounds {
		.Torso     = {{3, 13, 2}, {7, 23, 8}},
		.Head      = {{2, 23, 2}, {8, 29, 8}},
		.Arm_Left  = {{4, 12, 0}, {6, 23, 2}},
		.Arm_Right = {{4, 12, 8}, {6, 23, 10}},
		.Leg_Left  = {{3, 0, 2}, {7, 13, 5}},
		.Leg_Right = {{3, 0, 5}, {7, 13, 8}},
	}
	half := [3]f32{f32(PLAYER_MODEL_FRAME.x), 0, f32(PLAYER_MODEL_FRAME.z)} / (2 * PLAYER_MODEL_VOXELS_PER_BLOCK)
	height := f32(PLAYER_MODEL_FRAME.y) / PLAYER_MODEL_VOXELS_PER_BLOCK
	for limb in Player_Limb {
		testing.expect_value(t, mesh.bounds[limb], expected[limb])
		testing.expect(t, len(mesh.limbs[limb][.Lit].positions) > 0, "a limb has faces")
		pivot := mesh.pivots[limb]
		testing.expectf(t, abs(pivot.x) <= half.x && abs(pivot.z) <= half.z && pivot.y >= 0 && pivot.y <= height, "%v pivot %v inside the frame", limb, pivot)
	}
	// The shoulders and hips on the right side (+z) and the left, at
	// their heights: an arm turns one voxel below its top, a leg at its
	// top, the head at its bottom.
	expect_near_point(t, mesh.pivots[.Arm_Right], {0, 22.0 / 16, 4.0 / 16}, "right shoulder")
	expect_near_point(t, mesh.pivots[.Arm_Left], {0, 22.0 / 16, -4.0 / 16}, "left shoulder")
	expect_near_point(t, mesh.pivots[.Leg_Left], {0, 13.0 / 16, -1.5 / 16}, "left hip")
	expect_near_point(t, mesh.pivots[.Head], {0, 23.0 / 16, 0}, "neck")
	expect_near_point(t, mesh.hand, {0, 12.0 / 16, 4.0 / 16}, "hand")
	// About the collision box: 0.6 by 1.8 by 0.6 blocks.
	testing.expect(t, abs(height - PLAYER_HEIGHT) < 1.0 / 16, "height")
	testing.expect(t, abs(2 * half.x - PLAYER_WIDTH) < 1.0 / 16, "width")
}

@(test)
test_player_model_missing_files_report_the_file :: proc(t: ^testing.T) {
	_, problem := load_player_model_mesh("/nonexistent-player-model-directory", context.temp_allocator)
	testing.expect(t, problem != "", "a problem")
	testing.expect(t, strings.contains(problem, "player_torso.vox"), problem)
}

// A hanging limb swings forward (+x) for a positive angle; the pivot
// stays put; the body turns its front to the yaw.
@(test)
test_player_limb_transforms :: proc(t: ^testing.T) {
	pivot := [3]f32{0, 1, 0}
	swing := limb_swing_transform(pivot, 90)
	expect_near_point(t, transform_point(swing, pivot), pivot, "pivot")
	expect_near_point(t, transform_point(swing, {0, 0, 0}), {1, 1, 0}, "foot forward")
	body := player_body_transform({10, 2, 5}, 90)
	expect_near_point(t, transform_point(body, {1, 0, 0}), {10, 2, 6}, "front to +z at yaw 90")
	expect_near_point(t, transform_point(body, {0, 0, 1}), {9, 2, 5}, "right side to -x")
	camera := camera_frame_transform({0, 0, 0}, 0, 0)
	expect_near_point(t, transform_point(camera, {1, 2, 3}), {1, 2, 3}, "camera at yaw 0 is the model frame")
	looking_up := camera_frame_transform({0, 0, 0}, 0, 90)
	expect_near_point(t, transform_point(looking_up, {1, 0, 0}), {0, 1, 0}, "forward is up")
}

// The first person hand and the held item sit in the lower right of the
// view at rest: in front, below and right of the centre, inside the
// narrowest vertical field of view the settings allow.
@(test)
test_first_person_hand_is_in_view :: proc(t: ^testing.T) {
	mesh, problem := load_player_model_mesh(test_data_directory(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	arm := first_person_arm_transform(mesh.pivots[.Arm_Right], 0)
	expect_near_point(t, transform_point(arm, mesh.pivots[.Arm_Right]), FIRST_PERSON_SHOULDER, "shoulder")
	half_height := math.tan(FIELD_OF_VIEW_RANGE.minimum / 2 * math.RAD_PER_DEG)
	for point in ([2][3]f32{mesh.hand, mesh.hand - {0, HELD_ITEM_REACH, 0}}) {
		view := transform_point(arm, point)
		testing.expectf(t, view.x > 0.3 && view.y < 0 && view.z > 0, "%v in the lower right, in front", view)
		testing.expectf(t, -view.y < view.x * half_height, "%v inside the view", view)
	}
}

// Dust only for a step on the ground out of water.
@(test)
test_footstep_dust_needs_ground_and_dry_feet :: proc(t: ^testing.T) {
	testing.expect(t, footstep_dust_due(true, true, false), "a step on the ground")
	testing.expect(t, !footstep_dust_due(false, true, false), "no step")
	testing.expect(t, !footstep_dust_due(true, false, false), "in the air")
	testing.expect(t, !footstep_dust_due(true, true, true), "in water")
}
