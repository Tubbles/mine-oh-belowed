package game

import "core:math"
import "core:math/linalg"
import "core:testing"

// Work item 0268: the seated pose in the chair's basis. No raylib: the
// shipped limb files, the transforms and the pod's frame.

seated_test_chair :: proc() -> Seated_Chair {
	return Seated_Chair{eye = {3, 40, -2}, forward = {0, 0, -1}, up = {0, 1, 0}}
}

// A point of the chair's basis (forward, up, side) in the world.
seated_test_point :: proc(chair: Seated_Chair, offset: [3]f32) -> [3]f32 {
	return transform_point(seated_chair_transform(chair), offset)
}

seated_test_direction :: proc(transform: matrix[4, 4]f32, direction: [3]f32) -> [3]f32 {
	return (transform * [4]f32{direction.x, direction.y, direction.z, 0}).xyz
}

// The joints of the design's table, each through its part's transform,
// within 0.005 m of the eye plus the table's offset.
@(test)
test_the_seated_pose_keeps_the_eye_on_the_seat :: proc(t: ^testing.T) {
	mesh, problem := load_player_model_mesh(test_data_directory(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	chair := seated_test_chair()
	body := seated_player_transforms(chair, 1.6, mesh.pivots, mesh.leg_part_pivots, chair.forward)
	torso := body.limbs[.Torso]
	expect_f32_vector_near(t, transform_point(torso, {0, 1.6, 0}), chair.eye, 1e-4, "eye")
	expect_f32_vector_near(t, transform_point(torso, mesh.pivots[.Head]), seated_test_point(chair, {0.023, -0.161, 0}), 0.005, "neck")
	for side in ([2]f32{-1, 1}) {
		right := side > 0
		arm := right ? Player_Limb.Arm_Right : .Arm_Left
		leg := right ? Player_Limb.Leg_Right : .Leg_Left
		thigh := right ? Player_Leg_Part.Thigh_Right : .Thigh_Left
		shin := right ? Player_Leg_Part.Shin_Right : .Shin_Left
		expect_f32_vector_near(t, transform_point(torso, mesh.pivots[arm]), seated_test_point(chair, {0.031, -0.223, side * 0.250}), 0.005, "shoulder")
		expect_f32_vector_near(t, transform_point(torso, mesh.pivots[leg]), seated_test_point(chair, {0.110, -0.780, side * 0.094}), 0.005, "hip")
		knee := mesh.leg_part_pivots[shin]
		expect_f32_vector_near(t, transform_point(body.leg_parts[thigh], knee), seated_test_point(chair, {0.485, -0.780, side * 0.094}), 0.005, "knee")
		expect_f32_vector_near(t, transform_point(body.leg_parts[shin], {0, 0, knee.z}), seated_test_point(chair, {0.485, -1.217, side * 0.094}), 0.005, "foot")
		expect_f32_vector_near(t, transform_point(body.limbs[arm], {0, 12.0 / 16, side * 4.0 / 16}), seated_test_point(chair, {0.496, -0.613, side * 0.099}), 0.005, "hand")
	}
}

// The head's front follows the look within the limits, about the neck.
@(test)
test_the_seated_head_follows_the_look :: proc(t: ^testing.T) {
	mesh, problem := load_player_model_mesh(test_data_directory(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	chair := seated_test_chair()
	side := linalg.cross(chair.forward, chair.up)
	radians :: proc(degrees: f32) -> f32 {return degrees * math.RAD_PER_DEG}
	looks := [3][3]f32 {
		chair.forward,
		chair.forward * math.cos(radians(30)) + side * math.sin(radians(30)),
		chair.forward * math.cos(radians(40)) + chair.up * math.sin(radians(40)),
	}
	neck := mesh.pivots[.Head]
	torso := seated_torso_transform(chair, 1.6, mesh.pivots[.Leg_Left].y)
	for look in looks {
		body := seated_player_transforms(chair, 1.6, mesh.pivots, mesh.leg_part_pivots, look)
		expect_f32_vector_near(t, seated_test_direction(body.limbs[.Head], {1, 0, 0}), look, 1e-3, "the head's front")
		expect_f32_vector_near(t, transform_point(body.limbs[.Head], neck), transform_point(torso, neck), 1e-4, "the neck")
	}
	yaw, _ := seated_head_angles(chair, chair.forward * math.cos(radians(120)) + side * math.sin(radians(120)))
	testing.expectf(t, abs(yaw - SEATED_HEAD_YAW_LIMIT_DEGREES) < 1e-3, "a look 120 degrees right gives yaw %v", yaw)
	_, pitch := seated_head_angles(chair, chair.forward * math.cos(radians(80)) + chair.up * math.sin(radians(80)))
	testing.expectf(t, abs(pitch - HEAD_PITCH_LIMIT_DEGREES) < 1e-3, "a look 80 degrees up gives pitch %v", pitch)
}

// The rested pod (tilts 15 and 25): the chair is the rested frame's, the
// torso leans the tilt less the recline from the planet's up, square to
// the side, and each hip falls in a seat cell.
@(test)
test_the_seated_pose_follows_the_pods_tilt :: proc(t: ^testing.T) {
	mesh, problem := load_player_model_mesh(test_data_directory(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	machines := make_test_machines()
	pod_id := find_machine_of_kind(machines, .Pod)
	volumes, collision_problem := load_machine_collision(test_data_directory(), machines.machines[pod_id], context.temp_allocator)
	testing.expect_value(t, collision_problem, "")
	machines.machines[pod_id].collision = volumes
	for tilt in ([2]int{15, 25}) {
		entities: Entities
		defer destroy_entities(&entities)
		place_test_pod(&entities, machines)
		pod, placed, _ := find_pod(&entities, machines)
		machine := machines.machines[pod.machine]
		origin, axes := pod_rest_pose(placed, pod, machine, tilt)
		set_frame_pose(&entities.frames, placed.id, origin, axes)
		rested_pod, frame, found := find_pod(&entities, machines)
		testing.expect(t, found)
		chair := field_seated_chair(frame, rested_pod, machine)
		expect_f32_vector_near(t, chair.eye, world_position_to_metres(pod_seat_eye(frame, rested_pod, machine)), 1e-3, "the seat's eye")
		expect_f32_vector_near(t, chair.up, unit_vector_to_f32(frame.axes[FRAME_UP]), 1e-6, "the frame's up")

		body := seated_player_transforms(chair, 1.6, mesh.pivots, mesh.leg_part_pivots, chair.forward)
		torso_up := linalg.normalize(seated_test_direction(body.limbs[.Torso], {0, 1, 0}))
		lean := math.acos(clamp(linalg.dot(torso_up, linalg.normalize(chair.eye)), -1, 1)) * math.DEG_PER_RAD
		testing.expectf(t, abs(lean - (f32(tilt) - SEATED_RECLINE_DEGREES)) < 0.5, "tilt %d: the torso leans %v degrees", tilt, lean)
		side := linalg.cross(chair.forward, chair.up)
		testing.expectf(t, abs(linalg.dot(torso_up, side)) < 1e-3, "tilt %d: the torso leans %v sideways", tilt, linalg.dot(torso_up, side))
		for leg in ([2]Player_Limb{.Leg_Left, .Leg_Right}) {
			hip := transform_point(body.limbs[.Torso], mesh.pivots[leg])
			cell := world_to_frame_cell(frame, metres_to_world_position(hip))
			testing.expectf(t, pod_seat_contains_cell(rested_pod, machine, cell), "tilt %d: the %v hip in cell %v, outside the seat", tilt, leg, cell)
		}
	}
}
