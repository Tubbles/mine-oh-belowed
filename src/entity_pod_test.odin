package game

import "core:slice"
import "core:testing"

// The pod's frame holds the pod alone, every footprint cell the pod's,
// its bottom row on cell row 0 standing on the given point, no
// foundation; the door (the middle of the model's front) lies from the
// back towards the heading.
@(test)
test_place_pod_stands_the_pod_on_its_frame_with_no_pad :: proc(t: ^testing.T) {
	machines := make_test_machines()
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
	origin := pod_origin(pod)
	testing.expect_value(t, origin.y, 0)
	pod_handle := entity_at(&entities, origin, frame)
	testing.expect_value(t, entity_common(&entities, pod_handle).machine, pod_machine)
	for cell in machine_held_cells(origin, pod, POD_ROTATION) {
		testing.expect_value(t, entity_at(&entities, cell, frame), pod_handle)
	}
	for index in 0 ..< pod.fixture_count {
		fixture_origin, fixture_rotation := pod_fixture_placement(pod, origin, POD_ROTATION, index)
		fixture := entity_at(&entities, fixture_origin, frame)
		testing.expect_value(t, entity_common(&entities, fixture).machine, pod.fixtures[index].machine)
		for cell in footprint_cells(fixture_origin, machines.machines[pod.fixtures[index].machine].footprint, fixture_rotation) {
			testing.expect_value(t, entity_at(&entities, cell, frame), fixture)
		}
	}
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), int(size.x * size.y * size.z))
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 1152)
	for foundation in entities.foundations.entries {
		testing.expect(t, !foundation.alive || machines.machines[foundation.machine].kind != .Foundation, "a foundation was laid")
	}
	base := frame_cell_centre(record, {}) - World_Position(fixed_scale(record.axes[FRAME_UP], frame_pitch_units(record) / 2))
	testing.expectf(t, vector_length(cast([3]i64)(base - TEST_FRAME_HIT)) <= 4, "cell row 0's base lies %v off the point", base - TEST_FRAME_HIT)
	testing.expect(t, !entity_has_panel(&entities, machines, pod_handle))
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

// The pod's fixture of the index as placed by place_test_pod.
test_pod_fixture :: proc(entities: ^Entities, frame: Frame, pod: Machine, index: int) -> Entity_Handle {
	origin, _ := pod_fixture_placement(pod, pod_origin(pod), POD_ROTATION, index)
	return entity_at(entities, origin, frame.id)
}

// The shipped record's fixtures: the outer hatch, the inner hatch, the
// locker, the bench and the oxygen generator.
TEST_OUTER_HATCH :: 0
TEST_INNER_HATCH :: 1
TEST_LOCKER :: 2
TEST_BENCH :: 3
TEST_GENERATOR :: 4

// The shipped record's open cells boxes (0221): the floor before the
// chair, the lane to the inner hatch and the airlock's bore.
TEST_CABIN_BOX :: 0
TEST_LANE_BOX :: 1
TEST_AIRLOCK_BOX :: 2

// A cell of the pod's unrotated record (x along the width, y up, z along
// the depth) on the frame of place_test_pod: record x is the frame's z
// offset from the pod's origin.
test_pod_record_cell :: proc(pod: Machine, cell: [3]i32) -> World_Coordinate {
	turned := rotate_footprint_cell({cell.x, cell.z}, pod.footprint.x, pod.footprint.z, POD_ROTATION)
	return pod_origin(pod) + {turned.x, cell.y, turned.y}
}

// The record cell in front of a fixture's box at its minimum corner's
// row, on the side its rotation faces.
test_fixture_front_cell :: proc(pod: Machine, index: int) -> [3]i32 {
	box := pod.fixture_boxes[index]
	switch pod.fixtures[index].rotation {
	case 1:
		return {box.from.x, box.from.y, box.to.z + 1}
	case 2:
		return {box.from.x - 1, box.from.y, box.from.z}
	case 3:
		return {box.from.x, box.from.y, box.from.z - 1}
	}
	return {box.to.x + 1, box.from.y, box.from.z}
}

// The placed open cells of the boxes touching neither the footprint's
// sides nor its top row: the cells the sealed room holds with both
// hatches closed.
test_pod_inside_cells :: proc(pod: Machine) -> []World_Coordinate {
	cells := make([dynamic]World_Coordinate, context.temp_allocator)
	for index in 0 ..< pod.open_cell_box_count {
		box := pod.open_cells[index]
		on_side := box.from.x == 0 || box.to.x == pod.footprint.x - 1 || box.from.z == 0 || box.to.z == pod.footprint.z - 1
		if on_side || box.to.y == pod.footprint.y - 1 {
			continue
		}
		append(&cells, ..test_pod_box_cells(pod, index))
	}
	return cells[:]
}

// A crouched player at the centre of the airlock's bore floor, facing out.
test_airlock_player :: proc(frame: Frame, pod: Machine) -> Field_Player {
	player := make_field_player(pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, pod.open_cells[TEST_AIRLOCK_BOX]), frame.axes[FRAME_FORWARD])
	player.crouching = true
	return player
}

// Whether a record cell lies in an open cells box of the pod.
test_record_cell_is_open :: proc(pod: Machine, cell: [3]i32) -> bool {
	for index in 0 ..< pod.open_cell_box_count {
		if cell_box_contains(pod.open_cells[index], cell) {
			return true
		}
	}
	return false
}

// The cells of the entity, from its pool entry.
test_entity_cells :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> []World_Coordinate {
	return common_cells(entity_common(entities, handle)^, machines)
}

// For every pair of pod and fixture rotations and every box position in
// the footprint, each unrotated fixture cell lands where the pod's turn
// takes the corresponding cell of the fixture's box.
@(test)
test_pod_fixture_placement_composes_the_rotations :: proc(t: ^testing.T) {
	fixture_footprint := [3]i32{1, 1, 3}
	pod := Machine{footprint = {7, 1, 4}, fixture_count = 1}
	for pod_rotation in u8(0) ..< 4 {
		for fixture_rotation in u8(0) ..< 4 {
			size := rotated_footprint_size(fixture_footprint, fixture_rotation)
			for box_z in i32(0) ..= pod.footprint.z - size.z {
				for box_x in i32(0) ..= pod.footprint.x - size.x {
					cell := [3]i32{box_x, 0, box_z}
					pod.fixtures[0] = Pod_Fixture{cell = cell, rotation = fixture_rotation}
					pod.fixture_boxes[0] = Cell_Box{from = cell, to = cell + size - 1}
					origin, rotation := pod_fixture_placement(pod, {}, pod_rotation, 0)
					placed := footprint_cells(origin, fixture_footprint, rotation)
					for z in i32(0) ..< fixture_footprint.z {
						in_box := rotate_footprint_cell({0, z}, fixture_footprint.x, fixture_footprint.z, fixture_rotation) + {box_x, box_z}
						through_pod := rotate_footprint_cell(in_box, pod.footprint.x, pod.footprint.z, pod_rotation)
						testing.expectf(t, placed[z] == World_Coordinate{through_pod.x, 0, through_pod.y}, "pod %d fixture %d box %v cell %d: %v, not %v", pod_rotation, fixture_rotation, cell, z, placed[z], through_pod)
					}
				}
			}
		}
	}
}

// The pod places both hatches closed, the locker as a chest of 16 empty
// slots, the bench and the generator, each at its placement; the panels
// are the locker's, the bench's and the generator's, and none of them is
// picked up.
@(test)
test_place_pod_places_its_hatches_and_fixtures :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	testing.expect_value(t, pod_origin(pod), World_Coordinate{-5, 0, -5})
	for index in ([2]int{TEST_OUTER_HATCH, TEST_INNER_HATCH}) {
		handle := test_pod_fixture(&entities, frame, pod, index)
		hatch := pool_get(&entities.foundations, handle)
		testing.expect(t, hatch != nil && machines.machines[hatch.machine].kind == .Hatch)
		if hatch != nil {
			testing.expect(t, !hatch.hatch_open)
			testing.expect_value(t, hatch.hatch_toggle_tick, 0)
		}
		testing.expect(t, !entity_has_panel(&entities, machines, handle))
	}
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	outer_box := pod.fixture_boxes[TEST_OUTER_HATCH]
	for y in outer_box.from.y ..= outer_box.to.y {
		for z in outer_box.from.z ..= outer_box.to.z {
			testing.expect_value(t, entity_at(&entities, test_pod_record_cell(pod, {outer_box.from.x, y, z}), frame.id), outer)
		}
	}
	locker := test_pod_fixture(&entities, frame, pod, TEST_LOCKER)
	testing.expect_value(t, locker.kind, Entity_Kind.Chest)
	chest := pool_get(&entities.chests, locker)
	testing.expect(t, chest != nil && machines.machines[chest.machine].id == "pod_locker")
	if chest != nil {
		testing.expect_value(t, chest.slot_count, 16)
		for slot in chest.slots[:chest.slot_count] {
			testing.expect(t, stack_is_empty(slot))
		}
	}
	bench := test_pod_fixture(&entities, frame, pod, TEST_BENCH)
	generator := test_pod_fixture(&entities, frame, pod, TEST_GENERATOR)
	testing.expect_value(t, machines.machines[entity_common(&entities, bench).machine].kind, Machine_Kind.Crafting_Bench)
	testing.expect_value(t, machines.machines[entity_common(&entities, generator).machine].kind, Machine_Kind.Oxygen_Generator)
	for handle in ([3]Entity_Handle{locker, bench, generator}) {
		testing.expect(t, entity_has_panel(&entities, machines, handle))
	}
	pod_handle := entity_at(&entities, pod_origin(pod), frame.id)
	testing.expect(t, !entity_has_panel(&entities, machines, pod_handle))
	for handle in ([6]Entity_Handle{pod_handle, outer, test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH), locker, bench, generator}) {
		testing.expect(t, field_entity_is_placed_by_world(&entities, machines, handle))
	}
}

// Every held cell of the pod is solid exactly when it is no open cell;
// the fixtures, the drum over the bore and the top row are solid.
@(test)
test_the_pods_open_cells_are_open_and_the_rest_solid :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	origin := pod_origin(pod)
	pod_handle := entity_at(&entities, origin, frame.id)
	open := machine_open_cells(origin, pod, POD_ROTATION)
	for cell in machine_held_cells(origin, pod, POD_ROTATION) {
		is_open := slice.contains(open, cell)
		testing.expect_value(t, entity_at(&entities, cell, frame.id), pod_handle)
		testing.expectf(t, frame_cell_is_solid(&entities.frames, frame.id, cell) == !is_open, "cell %v open %v", cell, is_open)
	}
	for index in 0 ..< pod.fixture_count {
		handle := test_pod_fixture(&entities, frame, pod, index)
		for cell in test_entity_cells(&entities, machines, handle) {
			testing.expectf(t, frame_cell_is_solid(&entities.frames, frame.id, cell), "fixture %d cell %v", index, cell)
			testing.expect_value(t, entity_at(&entities, cell, frame.id), handle)
		}
	}
	bore := pod.open_cells[TEST_AIRLOCK_BOX]
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, test_pod_record_cell(pod, {bore.from.x, 2, bore.from.z})), "the drum over the bore")
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, test_pod_record_cell(pod, {pod.footprint.x / 2, 7, pod.footprint.z / 2})), "the top row")
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

// Opened, the outer hatch's rows but the top are open cells and the top
// row neither open nor solid; closed again every cell is solid. The cell
// count stays; a locker or no handle does not toggle.
@(test)
test_a_hatch_toggles_its_cells :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	hatch_machine := machines.machines[pod.fixtures[TEST_OUTER_HATCH].machine]
	count := frame_cell_count(&entities.frames, frame.id)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 10, nil))
	for cell in test_entity_cells(&entities, machines, outer) {
		occupant, found := frame_occupant(&entities.frames, frame.id, cell)
		testing.expect(t, found && .Solid not_in occupant.flags)
		testing.expectf(t, (.Open in occupant.flags) == (cell.y < hatch_machine.footprint.y - 1), "cell %v flags %v", cell, occupant.flags)
		testing.expect_value(t, entity_from_occupant(occupant.handle), outer)
	}
	testing.expect_value(t, frame_cell_count(&entities.frames, frame.id), count)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 20, nil))
	for cell in test_entity_cells(&entities, machines, outer) {
		testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, cell))
	}
	hatch := pool_get(&entities.foundations, outer)
	testing.expect(t, !hatch.hatch_open)
	testing.expect_value(t, hatch.hatch_toggle_tick, 21)
	testing.expect(t, !toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_LOCKER), 30, nil))
	testing.expect(t, !toggle_hatch(&entities, machines, NO_ENTITY, 30, nil))
}

// An open hatch does not close on a crouched player in its cells; a
// crouched player in the middle of the airlock lets it close.
@(test)
test_closing_a_hatch_on_a_player_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	door_player := make_field_player(pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, pod.fixture_boxes[TEST_OUTER_HATCH]), frame.axes[FRAME_FORWARD])
	door_player.crouching = true
	in_door := [1]Field_Capsule{field_player_capsule(tuning, door_player)}
	testing.expect(t, !toggle_hatch(&entities, machines, outer, 2, in_door[:]))
	testing.expect(t, hatch_is_open(&entities, outer))
	in_airlock := [1]Field_Capsule{field_player_capsule(tuning, test_airlock_player(frame, pod))}
	testing.expect(t, toggle_hatch(&entities, machines, outer, 3, in_airlock[:]))
	testing.expect(t, !hatch_is_open(&entities, outer))
}

// From two cells outside the pod's front, standing: with both hatches
// closed, and with both open, the walk stops at the pod's front (the drum
// is 1 m high, the hull over it). Crouched, the closed outer hatch stops
// the crawl at its face. Crouched the player crawls through the open
// airlock, stands up in the cabin once the standing capsule fits, and
// walks on in the cabin's open cells; from the cabin, crouched, the
// closed inner hatch stops the crawl at its face (0221).
@(test)
test_a_field_player_crawls_through_the_airlock_and_stands_in_the_cabin :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		entities: Entities
		defer destroy_entities(&entities)
		frame, pod := place_test_pod(&entities, machines)
		origin := pod_origin(pod)
		pitch := frame_pitch_units(frame)
		tuning := test_field_tuning(spacing)
		player := make_field_player(test_pod_outside_floor_point(frame, pod), -frame.axes[FRAME_FORWARD])
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		front_face := i64(origin.z + pod.footprint.x) * pitch
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 120)
		stopped := frame_local_position(frame, player.position).z
		testing.expectf(t, stopped >= front_face + tuning.capsule_radius - FIELD_GROUND_TOLERANCE, "%d mm: the feet passed the closed hatch to %d", spacing, stopped)

		outer := pod.fixture_boxes[TEST_OUTER_HATCH]
		outer_face := i64(origin.z + outer.to.x + 1) * pitch
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_SNEAK_FORWARD, 240)
		stopped = frame_local_position(frame, player.position).z
		testing.expectf(t, player.crouching, "%d mm: not crouching at the closed outer hatch", spacing)
		testing.expectf(t, stopped >= outer_face + tuning.capsule_radius - FIELD_GROUND_TOLERANCE, "%d mm: crouched, the feet passed the closed outer hatch's face %d to %d", spacing, outer_face, stopped)
		testing.expectf(t, stopped < front_face, "%d mm: crouched, the crawl stopped at %d, outside the pod's front", spacing, stopped)
		player = make_field_player(test_pod_outside_floor_point(frame, pod), -frame.axes[FRAME_FORWARD])
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)

		testing.expect(t, toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), 1, nil))
		testing.expect(t, toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH), 1, nil))
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 120)
		stopped = frame_local_position(frame, player.position).z
		testing.expectf(t, stopped >= front_face + tuning.capsule_radius - FIELD_GROUND_TOLERANCE, "%d mm: standing, the feet passed the hull over the door to %d", spacing, stopped)

		// Two cells past the inner hatch's face: the standing capsule's
		// radius then clears the hatch and the drum over it.
		inner := pod.fixture_boxes[TEST_INNER_HATCH]
		for _ in 0 ..< 600 {
			if frame_cell_of_feet(frame, player).z - origin.z <= inner.from.x - 2 {
				break
			}
			run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_SNEAK_FORWARD, 1)
		}
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		inside := frame_cell_of_feet(frame, player)
		testing.expectf(t, inside.z - origin.z <= inner.from.x - 2, "%d mm: the crawl ended in cell %v", spacing, inside)
		testing.expectf(t, !player.crouching, "%d mm: still crouching in the cabin", spacing)
		testing.expectf(t, player.on_ground, "%d mm: not on the floor", spacing)
		cabin := make([dynamic]World_Coordinate, context.temp_allocator)
		append(&cabin, ..test_pod_box_cells(pod, TEST_CABIN_BOX))
		append(&cabin, ..test_pod_box_cells(pod, TEST_LANE_BOX))
		testing.expectf(t, slice.contains(cabin[:], inside), "%d mm: the feet are in cell %v, not the cabin's", spacing, inside)
		testing.expectf(t, !field_capsule_overlaps(&world, &entities.frames, tuning, player.position, player.up), "%d mm: the capsule overlaps the pod", spacing)

		for _ in 0 ..< 120 {
			run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 1)
			feet := frame_cell_of_feet(frame, player)
			testing.expectf(t, slice.contains(cabin[:], feet), "%d mm: walking on, the feet left the cabin for %v", spacing, feet)
			testing.expectf(t, !field_capsule_overlaps(&world, &entities.frames, tuning, player.position, player.up), "%d mm: walking on, the capsule overlaps the pod", spacing)
			if !slice.contains(cabin[:], feet) {
				break
			}
		}

		testing.expect(t, toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), 2, nil))
		testing.expect(t, toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH), 2, nil))
		player = make_field_player(pod_cabin_floor_centre(frame, origin, pod, POD_ROTATION), frame.axes[FRAME_FORWARD])
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_SNEAK_FORWARD, 240)
		inner_face := i64(origin.z + inner.from.x) * pitch
		reached := frame_local_position(frame, player.position).z
		testing.expectf(t, player.crouching, "%d mm: not crouching at the closed inner hatch", spacing)
		testing.expectf(t, reached <= inner_face - tuning.capsule_radius + FIELD_GROUND_TOLERANCE, "%d mm: crouched, the feet passed the closed inner hatch's face %d to %d", spacing, inner_face, reached)
		testing.expectf(t, reached > inner_face - 2 * pitch, "%d mm: crouched, the crawl stopped at %d, short of the inner hatch", spacing, reached)
	}
}

// The floor point two cells outside the pod's front (record x W + 1),
// centred on the outer hatch's z span: clear of the pod's cells.
test_pod_outside_floor_point :: proc(frame: Frame, pod: Machine) -> World_Position {
	outer := pod.fixture_boxes[TEST_OUTER_HATCH]
	outside := Cell_Box{from = {pod.footprint.x + 1, 0, outer.from.z}, to = {pod.footprint.x + 1, 0, outer.to.z}}
	return pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, outside)
}

// The occupant index is rebuilt from the pools on load: the pod's open
// cells come back open, its walls solid and its fixtures' cells theirs.
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
	for cell in machine_held_cells(origin, pod, POD_ROTATION) {
		occupant, found := frame_occupant(&loaded.world.entities.frames, frame.id, cell)
		testing.expectf(t, found && (.Solid in occupant.flags) == !slice.contains(open, cell), "cell %v", cell)
	}
	for index in 0 ..< pod.fixture_count {
		handle := test_pod_fixture(&original.world.entities, frame, pod, index)
		for cell in test_entity_cells(&original.world.entities, content.machines, handle) {
			testing.expectf(t, entity_at(&loaded.world.entities, cell, frame.id) == handle, "fixture %d cell %v", index, cell)
		}
	}
	testing.expect_value(t, len(loaded.world.entities.frames.occupants), len(original.world.entities.frames.occupants))
	testing.expect_value(t, len(loaded.world.entities.sealed_rooms), 1)
}

// From the crouched eye in the airlock's bore the aiming ray meets the
// closed outer hatch's row 1 and, open, its top row, so it is closed from
// inside; on row 0 the open hatch lets the ray out to the chests
// outside; straight up it meets the drum over the bore (0221).
@(test)
test_the_aiming_ray_meets_the_airlocks_hatches_from_the_bore :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	outer_box := pod.fixture_boxes[TEST_OUTER_HATCH]
	for z in outer_box.from.z ..= outer_box.to.z {
		outside := test_pod_record_cell(pod, {pod.footprint.x + 1, 0, z})
		_, refusal := place_on_frame(&entities, machines, test_foundation(machines), frame.id, outside - UP, 0)
		testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
		_, refusal = place_on_frame(&entities, machines, test_machine(machines, "wooden_chest"), frame.id, outside, 0)
		testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	}
	player := test_airlock_player(frame, pod)
	eye := field_player_eye(player, tuning)
	reach := 10 * frame_pitch_units(frame)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	at_hatch := raycast_frames(&entities.frames, eye, frame.axes[FRAME_FORWARD], reach, excluded = {.Open})
	testing.expectf(t, at_hatch.hit && at_hatch.cell.y == 1 && entity_from_occupant(at_hatch.occupant.handle) == outer, "the ray at the closed hatch hit %v", at_hatch.cell)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	at_top := raycast_frames(&entities.frames, eye, frame.axes[FRAME_FORWARD], reach, excluded = {.Open})
	testing.expectf(t, at_top.hit && at_top.cell.y == 1 && entity_from_occupant(at_top.occupant.handle) == outer, "the ray at the open hatch's top row hit %v", at_top.cell)
	low := player.position + World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 4))
	out_of_door := raycast_frames(&entities.frames, low, frame.axes[FRAME_FORWARD], reach, excluded = {.Open})
	testing.expectf(t, out_of_door.hit && entity_at(&entities, out_of_door.cell, frame.id).kind == .Chest, "the ray through the door hit %v", out_of_door.cell)
	up := raycast_frames(&entities.frames, eye, frame.axes[FRAME_UP], reach, excluded = {.Open})
	pod_handle := entity_at(&entities, pod_origin(pod), frame.id)
	testing.expectf(t, up.hit && up.cell.y == 2 && entity_at(&entities, up.cell, frame.id) == pod_handle, "the ray up hit %v", up.cell)
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, up.cell))
}

// The cells of a box of the pod's record, placed with the pod.
test_pod_box_cells :: proc(pod: Machine, box: int) -> []World_Coordinate {
	only := pod
	only.open_cells[0] = pod.open_cells[box]
	only.open_cell_box_count = 1
	return machine_open_cells(pod_origin(pod), only, POD_ROTATION)
}

// Both hatches closed: one room of exactly the pod's inside open cells
// (the cabin, the lane and the bore), supplied by the generator. Outer
// open: the cabin alone. Inner open: the inside cells and the inner
// hatch's. Both open: no room.
@(test)
test_the_sealed_room_follows_the_hatches :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	open := test_pod_inside_cells(pod)
	generator := test_pod_fixture(&entities, frame, pod, TEST_GENERATOR)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	inner := test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)
	testing.expect_value(t, len(entities.sealed_rooms), 1)
	if len(entities.sealed_rooms) != 1 {
		return
	}
	room := entities.sealed_rooms[0]
	testing.expect(t, slice.equal(sorted_cells(room.cells[:]), sorted_cells(open)), "the room is the inside open cells")
	testing.expect_value(t, room.supplier, generator)
	testing.expect_value(t, room.oxygen, Oxygen_Supply.Unlimited)
	testing.expect(t, oxygen_generator_supplies_a_room(&entities, generator))

	toggle_hatch(&entities, machines, outer, 1, nil)
	airlock := test_pod_box_cells(pod, TEST_AIRLOCK_BOX)
	cabin := make([dynamic]World_Coordinate, context.temp_allocator)
	for cell in open {
		if !slice.contains(airlock, cell) {
			append(&cabin, cell)
		}
	}
	testing.expect_value(t, len(entities.sealed_rooms), 1)
	if len(entities.sealed_rooms) == 1 {
		testing.expect(t, slice.equal(sorted_cells(entities.sealed_rooms[0].cells[:]), sorted_cells(cabin[:])), "outer open: the cabin")
		testing.expect_value(t, entities.sealed_rooms[0].oxygen, Oxygen_Supply.Unlimited)
	}

	toggle_hatch(&entities, machines, outer, 2, nil)
	toggle_hatch(&entities, machines, inner, 3, nil)
	with_hatch := make([dynamic]World_Coordinate, context.temp_allocator)
	append(&with_hatch, ..open)
	append(&with_hatch, ..test_entity_cells(&entities, machines, inner))
	testing.expect_value(t, len(entities.sealed_rooms), 1)
	if len(entities.sealed_rooms) == 1 {
		testing.expect(t, slice.equal(sorted_cells(entities.sealed_rooms[0].cells[:]), sorted_cells(with_hatch[:])), "inner open: the inside cells and the inner hatch")
	}

	toggle_hatch(&entities, machines, outer, 4, nil)
	testing.expect_value(t, len(entities.sealed_rooms), 0)
	testing.expect(t, !oxygen_generator_supplies_a_room(&entities, generator))
}

// The spawn's feet are in the sealed room with its unlimited supply, a
// point in front of the outer hatch is outside; the F3 line says which.
@(test)
test_the_feet_tell_the_sealed_room :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, _ := place_test_pod(&entities, machines)
	spawn, found := field_pod_spawn(&entities, machines)
	testing.expect(t, found)
	room, inside := sealed_room_at_feet(&entities, spawn.position)
	testing.expect(t, inside)
	testing.expect_value(t, room.oxygen, Oxygen_Supply.Unlimited)
	_, outside := sealed_room_at_feet(&entities, frame_floor_point(frame, 1, 0, 11))
	testing.expect(t, !outside)
	testing.expect_value(t, sealed_room_line(true, .Unlimited), "sealed room: inside the pod, oxygen unlimited")
	testing.expect_value(t, sealed_room_line(true, .None), "sealed room: inside the pod, no oxygen")
	testing.expect_value(t, sealed_room_line(false, .None), "sealed room: outside")
}

// A machine or a foundation over the bench or in front of the locker is
// refused, and Mine held on the bench leaves it standing.
@(test)
test_the_fixtures_refuse_pick_up_and_placement_over_them :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	frame_id, ok := place_pod(entities, content.machines, test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	testing.expect(t, ok)
	frame, _ := find_frame(&entities.frames, frame_id)
	pod := content.machines.machines[find_machine_of_kind(content.machines, .Pod)]
	bench_origin, _ := pod_fixture_placement(pod, pod_origin(pod), POD_ROTATION, TEST_BENCH)
	for cell in ([2]World_Coordinate{bench_origin + {0, 2, 0}, test_pod_record_cell(pod, test_fixture_front_cell(pod, TEST_LOCKER))}) {
		for machine in ([2]Machine_Id{test_machine(content.machines, "wooden_chest"), test_foundation(content.machines)}) {
			_, refusal := place_on_frame(entities, content.machines, machine, frame_id, cell, 0)
			testing.expectf(t, refusal == .Occupied, "cell %v: %v", cell, refusal)
		}
	}
	bench := entity_at(entities, bench_origin, frame_id)
	count := frame_cell_count(&entities.frames, frame_id)
	stand_test_player_on_cell(&simulation, content, items, frame, bench_origin + {0, 1, 0})
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS + 4)
	testing.expect(t, entity_is_alive(entities, bench))
	testing.expect_value(t, frame_cell_count(&entities.frames, frame_id), count)
}

// A pod of an older size in a save is replaced at load by the record's
// pod with its fixtures, on a frame of its own at the old floor; the old
// frame goes and the player inside moves into the cabin.
@(test)
test_an_old_pod_is_replaced_at_load :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	entities := &original.world.entities
	machines := content.machines
	old_origin := World_Coordinate{-2, 0, -2}
	old_size := [3]i32{6, 8, 6}
	frame_origin, axes := free_frame_at(test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	old_frame_id := add_frame(&entities.frames, frame_origin, axes, 500)
	old_frame, _ := find_frame(&entities.frames, old_frame_id)
	old_pod := add_entity(entities, machines, find_machine_of_kind(machines, .Pod), old_origin, POD_ROTATION, old_frame_id)
	pool_get(&entities.foundations, old_pod).size = old_size
	floor := pod_floor_centre(old_frame, old_origin, old_size)
	original.players[0].field = make_field_player(floor + World_Position(fixed_scale(old_frame.axes[FRAME_UP], frame_pitch_units(old_frame))), old_frame.axes[FRAME_FORWARD])
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	location := save_test_location(directory)
	testing.expect_value(t, save_world(&original, content, location, 1_700_000_000), "")
	loaded := load_save_test_simulation(t, location, content)
	defer destroy_simulation(&loaded)
	restored := &loaded.world.entities
	pods := 0
	pod: Foundation
	for entry in restored.foundations.entries {
		if entry.alive && machines.machines[entry.machine].kind == .Pod {
			pods += 1
			pod = entry
		}
	}
	testing.expect_value(t, pods, 1)
	machine := machines.machines[pod.machine]
	testing.expect_value(t, pod.size, rotated_footprint_size(machine.footprint, POD_ROTATION))
	testing.expect(t, pod.frame != old_frame_id)
	_, old_found := find_frame(&restored.frames, old_frame_id)
	testing.expect(t, !old_found, "the old frame is gone")
	frame, found := find_frame(&restored.frames, pod.frame)
	testing.expect(t, found)
	expected_origin, expected_axes := free_frame_at(floor, old_frame.axes[FRAME_FORWARD], 500)
	testing.expect_value(t, frame.origin, expected_origin)
	testing.expect_value(t, frame.axes, expected_axes)
	for index in 0 ..< machine.fixture_count {
		fixture_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, index)
		handle := entity_at(restored, fixture_origin, pod.frame)
		testing.expectf(t, entity_is_alive(restored, handle) && entity_common(restored, handle).machine == machine.fixtures[index].machine, "fixture %d", index)
	}
	cell := frame_cell_of_feet(frame, loaded.players[0].field)
	testing.expectf(t, cell.y == 0 && slice.contains(test_pod_box_cells(machine, 0), cell), "the player stands in cell %v", cell)
	testing.expect_value(t, len(restored.sealed_rooms), 1)
}

// Work item 0221: the shipped record follows the lab's model: the cabin
// box on the floor, 4 rows high, the lane and the cabin before the inner
// hatch's face, the bore exactly between the hatches, nothing but open
// cells or the outside before the outer hatch, every fixture facing an
// open cell and the generator touching the sealed room.
@(test)
test_the_pods_record_follows_the_model :: proc(t: ^testing.T) {
	machines := make_test_machines()
	pod := machines.machines[find_machine_of_kind(machines, .Pod)]
	cabin := pod.open_cells[TEST_CABIN_BOX]
	testing.expect_value(t, cabin.from.y, 0)
	testing.expect_value(t, cabin.to.y - cabin.from.y + 1, 4)
	testing.expect(t, cabin.to.x - cabin.from.x >= 1 && cabin.to.z - cabin.from.z >= 1, "the cabin box is 2 by 2 cells at least")
	lane := pod.open_cells[TEST_LANE_BOX]
	testing.expect_value(t, lane.to.y - lane.from.y + 1, 4)
	inner, outer := pod.fixture_boxes[TEST_INNER_HATCH], pod.fixture_boxes[TEST_OUTER_HATCH]
	for y in i32(0) ..= 1 {
		for z in inner.from.z ..= inner.to.z {
			before := [3]i32{inner.from.x - 1, y, z}
			testing.expectf(t, cell_box_contains(cabin, before) || cell_box_contains(lane, before), "record cell %v before the inner hatch is neither the cabin's nor the lane's", before)
		}
	}
	bore := pod.open_cells[TEST_AIRLOCK_BOX]
	testing.expect_value(t, bore, Cell_Box{from = {inner.from.x + 1, 0, inner.from.z}, to = {outer.from.x - 1, 1, inner.to.z}})
	testing.expect_value(t, [2]i32{outer.from.z, outer.to.z}, [2]i32{inner.from.z, inner.to.z})
	if outer.to.x != pod.footprint.x - 1 {
		for y in outer.from.y ..= outer.to.y {
			for z in outer.from.z ..= outer.to.z {
				testing.expectf(t, test_record_cell_is_open(pod, {outer.to.x + 1, y, z}), "record cell %v before the outer hatch is solid", [3]i32{outer.to.x + 1, y, z})
			}
		}
		for x in outer.to.x + 1 ..< pod.footprint.x {
			testing.expect(t, test_record_cell_is_open(pod, {x, 0, outer.from.z}), "the way out runs to the footprint's front")
		}
	}
	for index in ([3]int{TEST_LOCKER, TEST_BENCH, TEST_GENERATOR}) {
		front := test_fixture_front_cell(pod, index)
		testing.expectf(t, test_record_cell_is_open(pod, front), "fixture %d faces record cell %v, no open cell", index, front)
	}
	inside := test_pod_inside_cells(pod)
	generator := pod.fixture_boxes[TEST_GENERATOR]
	touches := false
	for x in generator.from.x ..= generator.to.x {
		for z in generator.from.z ..= generator.to.z {
			for step in ([4][3]i32{{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}) {
				touches ||= slice.contains(inside, test_pod_record_cell(pod, [3]i32{x, generator.from.y, z} + step))
			}
		}
	}
	testing.expect(t, touches, "the oxygen generator touches the sealed room")
}

// Work item 0221: both hatches close round a crouched player in the
// middle of the bore, and the crouched body fits the closed airlock.
@(test)
test_both_hatches_close_round_a_crouched_player_in_the_airlock :: proc(t: ^testing.T) {
	machines := make_test_machines()
	world := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&world)
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	inner := test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	testing.expect(t, toggle_hatch(&entities, machines, inner, 1, nil))
	player := test_airlock_player(frame, pod)
	capsules := [1]Field_Capsule{field_player_capsule(tuning, player)}
	testing.expect(t, toggle_hatch(&entities, machines, outer, 2, capsules[:]))
	testing.expect(t, toggle_hatch(&entities, machines, inner, 3, capsules[:]))
	testing.expect(t, !hatch_is_open(&entities, outer) && !hatch_is_open(&entities, inner), "both hatches closed")
	testing.expect(t, !field_capsule_overlaps(&world, &entities.frames, field_posture_tuning(tuning, true), player.position, player.up), "the crouched body fits the closed airlock")
}

// Work item 0221: a 0198 pod in a save is replaced at load with its
// fixtures: the old hatches, locker, bench and generator go with the old
// frame, the old locker's stacks fill the new locker's first slots, and
// nothing keeps its saved size.
@(test)
test_an_old_pod_and_its_fixtures_are_replaced_at_load :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	entities := &original.world.entities
	machines := content.machines
	frame_origin, axes := free_frame_at(test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	old_frame_id := add_frame(&entities.frames, frame_origin, axes, 500)
	old_pod := add_entity(entities, machines, find_machine_of_kind(machines, .Pod), {-3, 0, -5}, POD_ROTATION, old_frame_id)
	pool_get(&entities.foundations, old_pod).size = {8, 8, 12}
	for x in ([2]i32{10, 12}) {
		hatch := add_entity(entities, machines, test_machine(machines, "pod_hatch"), {x, 0, 0}, 0, old_frame_id)
		pool_get(&entities.foundations, hatch).size = {1, 4, 2}
	}
	locker := add_entity(entities, machines, test_machine(machines, "pod_locker"), {14, 0, 0}, 0, old_frame_id)
	stone, coal := test_item(content.items, "stone"), test_item(content.items, "coal")
	old_chest := pool_get(&entities.chests, locker)
	old_chest.slots[0] = Item_Stack{stone, 5}
	old_chest.slots[4] = Item_Stack{coal, 3}
	add_entity(entities, machines, test_machine(machines, "crafting_bench"), {16, 0, 0}, 0, old_frame_id)
	add_entity(entities, machines, test_machine(machines, "oxygen_generator"), {18, 0, 0}, 0, old_frame_id)
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	location := save_test_location(directory)
	testing.expect_value(t, save_world(&original, content, location, 1_700_000_000), "")
	loaded := load_save_test_simulation(t, location, content)
	defer destroy_simulation(&loaded)
	restored := &loaded.world.entities
	pods := 0
	pod: Foundation
	for entry in restored.foundations.entries {
		if !entry.alive {
			continue
		}
		kind := machines.machines[entry.machine].kind
		testing.expectf(t, entry.frame != old_frame_id, "a %v stays on the old frame", kind)
		if kind == .Pod {
			pods += 1
			pod = entry
		}
	}
	for entry in restored.chests.entries {
		testing.expect(t, !entry.alive || entry.frame != old_frame_id, "a locker stays on the old frame")
	}
	testing.expect_value(t, pods, 1)
	machine := machines.machines[pod.machine]
	testing.expect_value(t, pod.size, rotated_footprint_size(machine.footprint, POD_ROTATION))
	_, old_found := find_frame(&restored.frames, old_frame_id)
	testing.expect(t, !old_found, "the old frame is gone")
	for index in 0 ..< machine.fixture_count {
		fixture_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, index)
		handle := entity_at(restored, fixture_origin, pod.frame)
		testing.expectf(t, entity_is_alive(restored, handle) && entity_common(restored, handle).machine == machine.fixtures[index].machine, "fixture %d", index)
	}
	locker_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, TEST_LOCKER)
	new_chest := pool_get(&restored.chests, entity_at(restored, locker_origin, pod.frame))
	testing.expect(t, new_chest != nil)
	if new_chest != nil {
		testing.expect_value(t, new_chest.slots[0], Item_Stack{stone, 5})
		testing.expect_value(t, new_chest.slots[1], Item_Stack{coal, 3})
		testing.expect(t, stack_is_empty(new_chest.slots[2]))
	}
	testing.expect_value(t, count_entities_keeping_saved_size(restored, machines), 0)
	testing.expect_value(t, len(restored.sealed_rooms), 1)
}

// Work item 0221: an old locker's stacks beyond the new locker's slots
// are counted as dropped, and the ones that fit fill its slots in order.
@(test)
test_an_old_lockers_stacks_past_the_new_lockers_slots_are_dropped :: proc(t: ^testing.T) {
	machines := make_test_machines()
	locker_machine := test_machine(machines, "pod_locker")
	machines.machines[locker_machine].slot_count = CAPSULE_SLOT_COUNT
	items := make_test_items()
	stone := test_item(items, "stone")
	entities: Entities
	defer destroy_entities(&entities)
	frame_origin, axes := free_frame_at(test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	old_frame := add_frame(&entities.frames, frame_origin, axes, 500)
	old_pod := add_entity(&entities, machines, find_machine_of_kind(machines, .Pod), {-3, 0, -5}, POD_ROTATION, old_frame)
	pool_get(&entities.foundations, old_pod).size = {8, 8, 12}
	old_locker := pool_get(&entities.chests, add_entity(&entities, machines, locker_machine, {14, 0, 0}, 0, old_frame))
	old_locker.slot_count = 16
	for slot in 0 ..< CAPSULE_SLOT_COUNT + 2 {
		old_locker.slots[slot] = Item_Stack{stone, u16(slot + 1)}
	}
	upgraded := upgrade_resized_pods(&entities, machines)
	testing.expect_value(t, len(upgraded), 1)
	if len(upgraded) != 1 {
		return
	}
	testing.expect_value(t, upgraded[0].moved_stacks, CAPSULE_SLOT_COUNT)
	testing.expect_value(t, upgraded[0].dropped_stacks, 2)
	pod := pool_get(&entities.foundations, upgraded[0].pod)
	locker_origin, _ := pod_fixture_placement(machines.machines[pod.machine], pod.origin, pod.rotation, TEST_LOCKER)
	new_locker := pool_get(&entities.chests, entity_at(&entities, locker_origin, pod.frame))
	testing.expect(t, new_locker != nil)
	if new_locker != nil {
		testing.expect_value(t, new_locker.slot_count, CAPSULE_SLOT_COUNT)
		for slot in 0 ..< CAPSULE_SLOT_COUNT {
			testing.expect_value(t, new_locker.slots[slot], Item_Stack{stone, u16(slot + 1)})
		}
	}
}

// Work item 0224: the pod always counts as working for its model (its
// emissive materials and its lamps), a hatch while open, the oxygen
// generator while it supplies a room.
@(test)
test_the_pod_counts_as_working_for_its_model :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	working := proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
		foundation := pool_get(&entities.foundations, handle)^
		return foundation_model_working(entities, foundation, machines.machines[foundation.machine])
	}
	pod_handle := entity_at(&entities, pod_origin(pod), frame.id)
	generator := test_pod_fixture(&entities, frame, pod, TEST_GENERATOR)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	inner := test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)
	testing.expect(t, working(&entities, machines, pod_handle))
	testing.expect(t, working(&entities, machines, generator))
	testing.expect(t, !working(&entities, machines, outer))
	testing.expect(t, !working(&entities, machines, inner))
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	testing.expect(t, working(&entities, machines, outer))
	testing.expect(t, toggle_hatch(&entities, machines, inner, 2, nil))
	testing.expect(t, !working(&entities, machines, generator))
	testing.expect(t, working(&entities, machines, pod_handle))
}

// Work item 0224: the lamps of the machines whose model works, in the
// world's metres on the pod's 500 mm frame.
@(test)
test_machine_lights_shine_while_their_model_works :: proc(t: ^testing.T) {
	machines := make_test_machines()
	pod_machine := find_machine_of_kind(machines, .Pod)
	generator_machine := find_machine_of_kind(machines, .Oxygen_Generator)
	machines.machines[pod_machine].lights[0] = {position = {0, 5.8, 0}, color = {1, 0.6, 0.15}, radius_cells = 6, clip = true}
	machines.machines[pod_machine].lights[1] = {position = {3, 2, 0}, color = {0.77, 0.89, 1}, radius_cells = 2, clip = true}
	machines.machines[pod_machine].light_count = 2
	machines.machines[generator_machine].lights[0] = {position = {0, 1, 0}, color = {0.77, 0.89, 1}, radius_cells = 3}
	machines.machines[generator_machine].light_count = 1
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	lights := make([dynamic]Point_Light, context.temp_allocator)
	gather_machine_lights(&lights, &entities, machines, Model_Renderer{})
	testing.expect_value(t, len(lights), 3)
	radii := [3]f32{6 * 0.5, 2 * 0.5, 3 * 0.5}
	for radius in radii {
		found := false
		for light in lights {
			found ||= abs(light.radius - radius) < 1e-5
		}
		testing.expectf(t, found, "no light of radius %v in %v", radius, lights[:])
	}
	pod_common := entity_common(&entities, entity_at(&entities, pod_origin(pod), frame.id))^
	body := entity_body_matrix(&entities, pod_common)
	expected := machine_point_light(pod.lights[0], body, 500, machine_light_clip_box(body, pod.footprint, f32(pod.footprint.y)))
	testing.expect(t, slice.contains(lights[:], expected), "the pod's first lamp is gathered where its model is drawn")

	toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), 1, nil)
	toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH), 2, nil)
	clear(&lights)
	gather_machine_lights(&lights, &entities, machines, Model_Renderer{})
	testing.expect_value(t, len(lights), 2)
	testing.expect_value(t, entity_frame_pitch_millimetres(&entities, frame.id), 500)
	testing.expect_value(t, entity_frame_pitch_millimetres(&entities, BLOCK_FRAME), 1000)
}

// Work item 0225: the pod and its fixtures are lit at the pod's interior
// light share, a working emissive layer keeps its brightness and an idle
// one follows the darkened tint; outside the box or on another frame the
// light is full.
@(test)
test_the_pod_and_its_fixtures_take_the_interior_light_share :: proc(t: ^testing.T) {
	machines := make_test_machines()
	machines.machines[find_machine_of_kind(machines, .Pod)].interior_light_share = 0.25
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	model_frame := Model_Frame {
		open_sky   = true,
		day_factor = 1,
		sky_tint   = {1, 1, 1},
		interiors  = gather_interior_lights(&entities, machines),
	}
	testing.expect_value(t, len(model_frame.interiors), 1)
	expect_channels :: proc(t: ^testing.T, got: [3]f32, want: f32, what: string) {
		for channel in 0 ..< 3 {
			testing.expectf(t, abs(got[channel] - want) < 1e-5, "%s: %v, not %v", what, got, want)
		}
	}
	foundation_light :: proc(entities: ^Entities, machines: Machine_Registry, frame: Model_Frame, handle: Entity_Handle) -> (light_tint, glow: [3]f32) {
		foundation := pool_get(&entities.foundations, handle)^
		machine := machines.machines[foundation.machine]
		pose := machine.kind == .Hatch ? hatch_pose(frame, foundation, machine) : Model_Pose{working = foundation_model_working(entities, foundation, machine)}
		return posed_model_light(frame, foundation.common, machine, pose)
	}
	pod_handle := entity_at(&entities, pod_origin(pod), frame.id)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	tint, glow := foundation_light(&entities, machines, model_frame, pod_handle)
	expect_channels(t, tint, 0.25, "the pod")
	expect_channels(t, glow, 1, "the pod's emissive")
	for hatch in ([2]int{TEST_OUTER_HATCH, TEST_INNER_HATCH}) {
		tint, glow = foundation_light(&entities, machines, model_frame, test_pod_fixture(&entities, frame, pod, hatch))
		expect_channels(t, tint, 0.25, "a closed hatch")
		expect_channels(t, glow, 0.25, "a closed hatch's emissive")
	}
	tint, _ = foundation_light(&entities, machines, model_frame, test_pod_fixture(&entities, frame, pod, TEST_BENCH))
	expect_channels(t, tint, 0.25, "the bench")
	tint, glow = foundation_light(&entities, machines, model_frame, test_pod_fixture(&entities, frame, pod, TEST_GENERATOR))
	expect_channels(t, tint, 0.25, "the generator")
	expect_channels(t, glow, 1, "the supplying generator's emissive")
	locker := entity_common(&entities, test_pod_fixture(&entities, frame, pod, TEST_LOCKER))^
	tint, _ = posed_model_light(model_frame, locker, machines.machines[locker.machine], {})
	expect_channels(t, tint, 0.25, "the locker")
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	model_frame.tick = 2
	_, glow = foundation_light(&entities, machines, model_frame, outer)
	expect_channels(t, glow, 1, "an open hatch's emissive")

	furnace := machines.machines[find_machine_of_kind(machines, .Furnace)]
	beside := Entity_Common{frame = frame.id, origin = pod_origin(pod) + {-2, 0, 0}, size = {1, 1, 1}}
	tint, _ = posed_model_light(model_frame, beside, furnace, {})
	expect_channels(t, tint, 1, "a machine beside the pod")
	elsewhere := Entity_Common{frame = BLOCK_FRAME, origin = pod_origin(pod), size = {1, 1, 1}}
	tint, _ = posed_model_light(model_frame, elsewhere, furnace, {})
	expect_channels(t, tint, 1, "a machine on another frame")
	pod_common := pool_get(&entities.foundations, pod_handle).common
	model_frame.interiors = nil
	tint, _ = posed_model_light(model_frame, pod_common, pod, {working = true})
	expect_channels(t, tint, 1, "the pod without interiors")
}

// Work item 0225: a player standing in the cabin is lit at the pod's
// share, one beside the pod at full light.
@(test)
test_a_player_in_the_cabin_takes_the_interior_light_share :: proc(t: ^testing.T) {
	machines := make_test_machines()
	machines.machines[find_machine_of_kind(machines, .Pod)].interior_light_share = 0.25
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	interiors := gather_interior_lights(&entities, machines)
	spawn, found := field_pod_spawn(&entities, machines)
	testing.expect(t, found)
	testing.expect_value(t, field_player_interior_light_share(interiors, spawn), 0.25)
	beside := spawn
	beside.position = frame_cell_centre(frame, pod_origin(pod) + {-2, 0, 0})
	beside.previous_position = beside.position
	testing.expect_value(t, field_player_interior_light_share(interiors, beside), 1)
	testing.expect_value(t, field_player_interior_light_share(nil, spawn), 1)
}

// Work item 0229: a pod's lamp lights inside its box: its own position and
// the footprint's middle are inside, a cell centre beyond the footprint's
// +x face is outside.
@(test)
test_a_pods_lamp_lights_only_inside_its_box :: proc(t: ^testing.T) {
	machines := make_test_machines()
	pod_machine := find_machine_of_kind(machines, .Pod)
	machines.machines[pod_machine].lights[0] = {position = {0, 5.8, 0}, color = {1, 0.6, 0.15}, radius_cells = 6, clip = true}
	machines.machines[pod_machine].light_count = 1
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	lights := make([dynamic]Point_Light, context.temp_allocator)
	gather_machine_lights(&lights, &entities, machines, Model_Renderer{})
	testing.expect_value(t, len(lights), 1)
	if len(lights) != 1 {
		return
	}
	box, clipped := lights[0].clip_box.?
	testing.expect(t, clipped, "the pod's lamp has a box")
	testing.expect(t, clip_box_reach(box, lights[0].position) <= 1, "the lamp lies inside its box")
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	beyond := world_position_to_metres(frame_cell_centre(frame, pod_origin(pod) + {size.x + 2, 1, size.z / 2}))
	testing.expect(t, clip_box_reach(box, beyond) > 1, "a cell beyond the +x face lies outside")
	middle := world_position_to_metres(frame_cell_centre(frame, pod_origin(pod) + {size.x / 2, 1, size.z / 2}))
	testing.expect(t, clip_box_reach(box, middle) <= 1, "the footprint's middle lies inside")
}
