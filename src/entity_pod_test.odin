package game

import "core:slice"
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

// The pod on the flat test site, its door towards +x, and its record.
place_test_pod :: proc(entities: ^Entities, machines: Machine_Registry) -> (frame: Frame, pod: Machine) {
	frame_id, ok := place_pod(entities, machines, test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	assert(ok)
	frame, _ = find_frame(&entities.frames, frame_id)
	return frame, machines.machines[find_machine_of_kind(machines, .Pod)]
}

// A point in a frame's axes, in pitches from its origin, as a world
// position: the mean of the four cell centres round it on the floor at y.
frame_floor_point :: proc(frame: Frame, x, y, z: i32) -> World_Position {
	sum: World_Position
	for corner in ([4]World_Coordinate{{x - 1, y, z - 1}, {x, y, z - 1}, {x - 1, y, z}, {x, y, z}}) {
		sum += frame_cell_centre(frame, corner) / 4
	}
	return sum
}

// The cell of the frame the feet stand in, a quarter pitch over them.
frame_cell_of_feet :: proc(frame: Frame, player: Field_Player) -> World_Coordinate {
	lift := fixed_scale(player.up, frame_pitch_units(frame) / 4)
	return world_to_frame_cell(frame, player.position + World_Position(lift))
}

// Every open cell of the record is the pod's and not solid, every other
// footprint cell solid: the door on the front face from the floor up two
// metres, the interior, the bed and the hull.
@(test)
test_the_pods_door_and_interior_are_open_and_its_hull_and_bed_solid :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	testing.expect(t, pod.open_cell_box_count > 0)
	origin := pod_origin(pod)
	pod_handle := entity_at(&entities, origin, frame.id)
	open := machine_open_cells(origin, pod, POD_ROTATION)
	for cell in footprint_cells(origin, pod.footprint, POD_ROTATION) {
		is_open := slice.contains(open, cell)
		testing.expect_value(t, entity_at(&entities, cell, frame.id), pod_handle)
		testing.expectf(t, frame_cell_is_solid(&entities.frames, frame.id, cell) == !is_open, "cell %v open %v", cell, is_open)
	}
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	front := origin.z + size.z - 1
	for y in origin.y ..< origin.y + 4 {
		for x in i32(0) ..= 1 {
			testing.expectf(t, !frame_cell_is_solid(&entities.frames, frame.id, {x, y, front}), "door cell %v", World_Coordinate{x, y, front})
		}
	}
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {0, origin.y + 4, front}), "the door's lintel")
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {2, origin.y, front}), "the front wall beside the door")
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {0, origin.y, origin.z + 2}), "the bed")
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {0, origin.y + size.y - 1, origin.z + 2}), "the roof")
}

// A machine on an open cell of the pod is refused: the cell is the pod's.
@(test)
test_a_machine_on_an_open_pod_cell_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	cell := machine_open_cells(pod_origin(pod), pod, POD_ROTATION)[0]
	testing.expect(t, !frame_cell_is_solid(&entities.frames, frame.id, cell))
	_, refusal := place_on_frame(&entities, machines, test_machine(machines, "wooden_chest"), frame.id, cell, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.Occupied)
	_, refusal = place_on_frame(&entities, machines, test_foundation(machines), frame.id, cell, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.Occupied)
}

// Walked from the pad at the door, the player passes the door and stands
// inside on the pad under the pod, a pitch over the ground; walking on
// into the side wall, the wall stops the feet short of its inner face.
@(test)
test_a_field_player_walks_through_the_pods_door_and_the_walls_stop_it :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		entities: Entities
		defer destroy_entities(&entities)
		frame, pod := place_test_pod(&entities, machines)
		origin := pod_origin(pod)
		size := rotated_footprint_size(pod.footprint, POD_ROTATION)
		front := origin.z + size.z - 1
		tuning := test_field_tuning(spacing)
		inward := -frame.axes[FRAME_FORWARD]
		player := make_field_player(frame_floor_point(frame, 1, 1, front + 2), inward)
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		for _ in 0 ..< 240 {
			if frame_cell_of_feet(frame, player).z < front {
				break
			}
			run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 1)
		}
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		inside := frame_cell_of_feet(frame, player)
		testing.expectf(t, inside.z < front && inside.y == origin.y, "%d mm: the feet are in cell %v", spacing, inside)
		testing.expectf(t, entity_at(&entities, inside, frame.id) == entity_at(&entities, origin, frame.id), "%d mm: cell %v is not the pod's", spacing, inside)
		testing.expectf(t, player.on_ground, "%d mm: not on the floor", spacing)
		testing.expectf(t, abs(site_height(player.position) - frame_pitch_units(frame)) <= tenth_sample(spacing), "%d mm: feet at %d", spacing, site_height(player.position))
		testing.expectf(t, !field_capsule_overlaps(&world, &entities.frames, tuning, player.position, player.up), "%d mm: the capsule overlaps the pod", spacing)

		player.forward = tangent_of(player.up, frame.axes[FRAME_RIGHT])
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 120)
		wall_face := i64(origin.x + size.x - 1) * frame_pitch_units(frame)
		reached := frame_local_position(frame, player.position).x
		testing.expectf(t, reached <= wall_face - tuning.capsule_radius + FIELD_GROUND_TOLERANCE, "%d mm: the feet reached %d, the wall's face is at %d", spacing, reached, wall_face)
		testing.expectf(t, reached > wall_face - 2 * frame_pitch_units(frame), "%d mm: the walk stopped at %d before the wall", spacing, reached)
		testing.expectf(t, frame_cell_of_feet(frame, player).y == origin.y, "%d mm: the feet left the floor for %v", spacing, frame_cell_of_feet(frame, player))
	}
}

// The occupant index is rebuilt from the pools on load: the pod's open
// cells come back open and its walls solid.
@(test)
test_a_saved_pod_loads_with_its_open_cells :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	frame, pod := place_test_pod(&original.world.entities, content.machines)
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	location := save_test_location(directory)
	testing.expect_value(t, save_world(&original, content, location, 1_700_000_000), "")
	loaded := load_save_test_simulation(t, location, content)
	defer destroy_simulation(&loaded)
	origin := pod_origin(pod)
	open := machine_open_cells(origin, pod, POD_ROTATION)
	for cell in footprint_cells(origin, pod.footprint, POD_ROTATION) {
		occupant, found := frame_occupant(&loaded.world.entities.frames, frame.id, cell)
		testing.expectf(t, found && (.Solid in occupant.flags) == !slice.contains(open, cell), "cell %v", cell)
	}
	testing.expect_value(t, len(loaded.world.entities.frames.occupants), len(original.world.entities.frames.occupants))
}

// The aiming ray passes the pod's open cells: from inside, through the
// door, it reaches a chest on the pad outside; at the side wall it stops
// at the wall.
@(test)
test_the_aiming_ray_passes_the_pods_open_cells_and_stops_at_its_walls :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	origin := pod_origin(pod)
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	front := origin.z + size.z - 1
	outside := World_Coordinate{1, origin.y, front + 2}
	_, refusal := place_on_frame(&entities, machines, test_machine(machines, "wooden_chest"), frame.id, outside, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	inside := World_Coordinate{1, origin.y, front - 2}
	testing.expect(t, !frame_cell_is_solid(&entities.frames, frame.id, inside))
	eye := frame_cell_centre(frame, inside)
	reach := 10 * frame_pitch_units(frame)
	out_of_door := raycast_frames(&entities.frames, eye, frame.axes[FRAME_FORWARD], reach, excluded = {.Open})
	testing.expectf(t, out_of_door.hit && out_of_door.cell == outside, "the ray through the door hit %v", out_of_door.cell)
	testing.expect_value(t, entity_at(&entities, out_of_door.cell, frame.id).kind, Entity_Kind.Chest)
	at_wall := raycast_frames(&entities.frames, eye, frame.axes[FRAME_RIGHT], reach, excluded = {.Open})
	testing.expect_value(t, at_wall.cell, World_Coordinate{origin.x + size.x - 1, inside.y, inside.z})
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, at_wall.cell))
}
