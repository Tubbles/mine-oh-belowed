package game

import "core:math"
import "core:testing"

// Work item 0175: the arm's pose from the inserter's cycle.

// The arms the tests pose: reach in cells over a pitch.
Arm_Test_Case :: struct {
	reach_cells:       i32,
	pitch_millimetres: int,
	frame:             Frame_Id,
}

@(rodata)
arm_test_cases := [?]Arm_Test_Case {
	{4, 500, 1},
	{6, 333, 1},
	{8, 500, 1},
	{2, 1000, 1},
	{1, BLOCK_FRAME_PITCH_MILLIMETRES, BLOCK_FRAME},
	{2, BLOCK_FRAME_PITCH_MILLIMETRES, BLOCK_FRAME},
}

// The base plate's half side follows the pitch.
expect_within_base :: proc(t: ^testing.T, point: [3]f32, pitch_millimetres: int, name: string, location := #caller_location) {
	half := f32(pitch_millimetres) / MILLIMETRES_PER_METRE / 2
	inside := abs(point.x) <= half && abs(point.z) <= half && point.y > 0
	testing.expectf(t, inside, "%s at %v is outside the base's half width %v", name, point, half, loc = location)
}

@(test)
test_the_arm_at_rest_folds_within_its_base :: proc(t: ^testing.T) {
	for entry in arm_test_cases {
		dimensions := arm_dimensions_on_frame(entry.reach_cells, entry.pitch_millimetres)
		angles := arm_pose_at(dimensions, 0)
		testing.expect_value(t, angles, arm_rest_pose(dimensions))
		joints := arm_joints(dimensions, angles)
		yaw := axis_rotation_matrix(1, angles.yaw)
		expect_within_base(t, transform_point(yaw, joints.elbow), entry.pitch_millimetres, "the elbow")
		expect_within_base(t, transform_point(yaw, joints.wrist), entry.pitch_millimetres, "the wrist")
		expect_within_base(t, arm_hand_point(dimensions, angles), entry.pitch_millimetres, "the hand")
		gripper := arm_part_transforms(dimensions, angles)[.Gripper]
		expect_within_base(t, transform_point(gripper, ARM_LAMP_POINT), entry.pitch_millimetres, "the lamp")
		testing.expect(t, arm_rest_top_metres(dimensions) > joints.wrist.y)
	}
}

// The hand of an arm on a frame of pitch_millimetres, in the frame's cells.
arm_hand_in_cells :: proc(common: Entity_Common, reach_cells: i32, pitch_millimetres: int, fraction: f32) -> [3]f32 {
	dimensions := arm_dimensions_on_frame(reach_cells, pitch_millimetres)
	transform := arm_entity_transform(common, pitch_millimetres)
	return transform_point(transform, arm_hand_point(dimensions, arm_pose_at(dimensions, fraction)))
}

// Over the cell's middle, and above its top by the clearance.
expect_over_cell :: proc(t: ^testing.T, hand: [3]f32, cell: World_Coordinate, pitch_millimetres: int, name: string, location := #caller_location) {
	centre := [3]f32{f32(cell.x) + 0.5, f32(cell.y) + 1, f32(cell.z) + 0.5}
	clearance := ARM_WORK_CLEARANCE_METRES * MILLIMETRES_PER_METRE / f32(pitch_millimetres)
	over := abs(hand.x - centre.x) < 0.02 && abs(hand.z - centre.z) < 0.02 && abs(hand.y - centre.y - clearance) < 0.02
	testing.expectf(t, over, "%s: the hand at %v is not over the top of cell %v", name, hand, cell, loc = location)
}

@(test)
test_the_arm_at_full_reach_holds_the_gripper_over_its_cells :: proc(t: ^testing.T) {
	for entry in arm_test_cases {
		reach_millimetres := entry.reach_cells * i32(entry.pitch_millimetres)
		machine := Machine{reach_millimetres = reach_millimetres, inserter_reach = entry.reach_cells}
		frame := Frame{id = entry.frame, pitch_millimetres = entry.pitch_millimetres}
		for rotation in u8(0) ..< 4 {
			inserter := make_inserter(Entity_Common{origin = {3, 1, -2}, size = {1, 1, 1}, rotation = rotation, frame = entry.frame}, machine, frame)
			testing.expect_value(t, inserter.reach, entry.reach_cells)
			drop := arm_hand_in_cells(inserter.common, inserter.reach, entry.pitch_millimetres, ARM_DROP_FRACTION)
			expect_over_cell(t, drop, inserter_drop_cell(inserter), entry.pitch_millimetres, "at the drop")
			pickup := arm_hand_in_cells(inserter.common, inserter.reach, entry.pitch_millimetres, ARM_GRAB_END)
			expect_over_cell(t, pickup, inserter_pickup_cell(inserter), entry.pitch_millimetres, "at the grab")
		}
	}
}

// The elbow stays bent at full reach: the forearm meets the upper arm at
// well under a straight line.
@(test)
test_the_elbow_stays_bent_at_full_reach :: proc(t: ^testing.T) {
	for entry in arm_test_cases {
		dimensions := arm_dimensions_on_frame(entry.reach_cells, entry.pitch_millimetres)
		angles := arm_pose_at(dimensions, ARM_DROP_FRACTION)
		bend := (angles.shoulder - angles.elbow) * math.DEG_PER_RAD
		testing.expectf(t, bend > 40, "%v: the elbow bends only %v degrees", entry, bend)
	}
}

// The swing passes the right hand side, and the pose changes only with
// the cycle: the same fraction gives the same pose.
@(test)
test_the_arm_swings_over_its_right_hand_side :: proc(t: ^testing.T) {
	dimensions := arm_dimensions_on_frame(4, 500)
	middle := arm_hand_point(dimensions, arm_pose_at(dimensions, ARM_SWING_MIDDLE))
	testing.expectf(t, middle.z > 1 && abs(middle.x) < 0.01, "mid swing the hand is at %v", middle)
	testing.expect_value(t, arm_pose_at(dimensions, 0.37), arm_pose_at(dimensions, 0.37))
	testing.expect(t, !arm_shows_held_item(0.05) && arm_shows_held_item(0.3) && !arm_shows_held_item(0.8))
}

// The lamp lights only while the arm moves; other machines keep their
// lit look at rest.
@(test)
test_the_arm_lamp_is_dark_at_rest :: proc(t: ^testing.T) {
	tint := [3]f32{0.8, 0.8, 0.8}
	testing.expect_value(t, emissive_brightness(.Arm, 0, true, tint), 1)
	testing.expect(t, emissive_brightness(.Arm, 0, false, tint).r < tint.r / 2)
	testing.expect_value(t, emissive_brightness(.Spin, 0, false, tint), tint)
	_, found := arm_point_light(Arm_Placement{transform = 1, dimensions = arm_dimensions_on_frame(4, 500)})
	testing.expect(t, !found)
}
