package game

import "core:testing"

// The pod's frame holds the ten by ten pad of foundations and the pod on
// it, every footprint cell the pod's, centred on the pad; the door (the
// middle of the model's front) lies from the back towards the heading.
@(test)
test_place_pod_lays_the_pad_and_the_pod_with_its_door_to_the_heading :: proc(t: ^testing.T) {
	machines := make_test_machines()
	foundation := test_foundation(machines)
	pod_machine := find_machine_of_kind(machines, .Pod)
	testing.expect(t, pod_machine != NO_MACHINE)
	pod := machines.machines[pod_machine]
	entities: Entities
	defer destroy_entities(&entities)
	up, _ := normalize_fixed(cast([3]i64)(TEST_FRAME_HIT))
	heading := test_tangent_at(up, {UNIT_VECTOR_ONE, 0, 0})
	frame, ok := place_pod(&entities, machines, TEST_FRAME_HIT, heading, 500)
	testing.expect(t, ok)
	record, found := find_frame(&entities.frames, frame)
	testing.expect(t, found && frame != BLOCK_FRAME)
	pad_count := 0
	for z in i32(POD_PAD_FIRST_CELL) ..< POD_PAD_FIRST_CELL + POD_PAD_SIZE {
		for x in i32(POD_PAD_FIRST_CELL) ..< POD_PAD_FIRST_CELL + POD_PAD_SIZE {
			handle := entity_at(&entities, {x, 0, z}, frame)
			common := entity_common(&entities, handle)
			testing.expectf(t, common != nil && common.machine == foundation, "pad cell %d, %d", x, z)
			pad_count += 1
		}
	}
	testing.expect_value(t, pad_count, POD_PAD_SIZE * POD_PAD_SIZE)
	origin := pod_origin(pod)
	pod_handle := entity_at(&entities, origin, frame)
	testing.expect_value(t, entity_common(&entities, pod_handle).machine, pod_machine)
	for cell in footprint_cells(origin, pod.footprint, POD_ROTATION) {
		testing.expect_value(t, entity_at(&entities, cell, frame), pod_handle)
	}
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	testing.expect_value(t, origin.x - POD_PAD_FIRST_CELL, POD_PAD_FIRST_CELL + POD_PAD_SIZE - (origin.x + size.x))
	testing.expect_value(t, origin.z - POD_PAD_FIRST_CELL, POD_PAD_FIRST_CELL + POD_PAD_SIZE - (origin.z + size.z))
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), POD_PAD_SIZE * POD_PAD_SIZE + int(size.x * size.y * size.z))
	testing.expect(t, !entity_has_panel(&entities, pod_handle))
	front := rotate_footprint_cell({pod.footprint.x - 1, pod.footprint.z / 2}, pod.footprint.x, pod.footprint.z, POD_ROTATION)
	back := rotate_footprint_cell({0, pod.footprint.z / 2}, pod.footprint.x, pod.footprint.z, POD_ROTATION)
	door := frame_cell_centre(record, origin + {front.x, 0, front.y})
	rear := frame_cell_centre(record, origin + {back.x, 0, back.y})
	towards, _ := normalize_fixed(cast([3]i64)(door - rear))
	// Within the 7.5 degrees of a yaw step: cos 8 degrees is 0.990.
	testing.expectf(t, fixed_dot(towards, heading) > UNIT_VECTOR_ONE * 990 / 1000, "the door faces %v against the heading %v", towards, heading)
}
