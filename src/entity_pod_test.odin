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
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 768)
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
	testing.expect_value(t, pod_origin(pod), World_Coordinate{-3, 0, -5})
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
	for y in i32(0) ..< 4 {
		for x in i32(0) ..= 1 {
			testing.expect_value(t, entity_at(&entities, {x, y, 6}, frame.id), outer)
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
// the hatches, the wall over the outer hatch, the bed, the roof, a side
// wall and the fixtures are solid.
@(test)
test_the_pods_interior_is_open_and_its_hull_bed_and_closed_hatches_solid :: proc(t: ^testing.T) {
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
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {0, 4, 6}), "the wall over the outer hatch")
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {2, 0, 6}), "the front wall beside the outer hatch")
	// The bed: unrotated x 1 to 4, z 5 to 6 on the floor row.
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {-1, 0, -3}), "the bed")
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {0, 7, 0}), "the roof")
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, {4, 1, 0}), "a side wall")
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
	count := frame_cell_count(&entities.frames, frame.id)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 10, nil))
	for cell in test_entity_cells(&entities, machines, outer) {
		occupant, found := frame_occupant(&entities.frames, frame.id, cell)
		testing.expect(t, found && .Solid not_in occupant.flags)
		testing.expectf(t, (.Open in occupant.flags) == (cell.y < 3), "cell %v flags %v", cell, occupant.flags)
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

// An open hatch does not close on a player standing in its cells; a
// player in the middle of the airlock lets it close.
@(test)
test_closing_a_hatch_on_a_player_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	in_door := [1]Field_Capsule{field_player_capsule(tuning, make_field_player(pod_floor_centre(frame, {0, 0, 6}, {2, 4, 1}), frame.axes[FRAME_FORWARD]))}
	testing.expect(t, !toggle_hatch(&entities, machines, outer, 2, in_door[:]))
	testing.expect(t, hatch_is_open(&entities, outer))
	in_airlock := [1]Field_Capsule{field_player_capsule(tuning, make_field_player(frame_floor_point(frame, 1, 0, 5), frame.axes[FRAME_FORWARD]))}
	testing.expect(t, toggle_hatch(&entities, machines, outer, 3, in_airlock[:]))
	testing.expect(t, !hatch_is_open(&entities, outer))
}

// With the outer hatch closed the walk from outside stops at it; with
// both hatches open the player walks through the airlock into the cabin
// and stands on its floor; walking on into the side wall, the wall stops
// the feet short of its inner face.
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
		pitch := frame_pitch_units(frame)
		tuning := test_field_tuning(spacing)
		inward := -frame.axes[FRAME_FORWARD]
		player := make_field_player(frame_floor_point(frame, 1, 0, front + 2), inward)
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 120)
		stopped := frame_local_position(frame, player.position).z
		testing.expectf(t, stopped >= i64(front + 1) * pitch + tuning.capsule_radius - FIELD_GROUND_TOLERANCE, "%d mm: the feet passed the closed hatch to %d", spacing, stopped)

		testing.expect(t, toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), 1, nil))
		testing.expect(t, toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH), 1, nil))
		for _ in 0 ..< 480 {
			if frame_cell_of_feet(frame, player).z <= 2 {
				break
			}
			run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 1)
		}
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		inside := frame_cell_of_feet(frame, player)
		testing.expectf(t, inside.z <= 2 && inside.y == origin.y, "%d mm: the feet are in cell %v", spacing, inside)
		testing.expectf(t, entity_at(&entities, inside, frame.id) == entity_at(&entities, origin, frame.id), "%d mm: cell %v is not the pod's", spacing, inside)
		testing.expectf(t, player.on_ground, "%d mm: not on the floor", spacing)
		testing.expectf(t, abs(site_height(player.position)) <= tenth_sample(spacing), "%d mm: feet at %d", spacing, site_height(player.position))
		testing.expectf(t, !field_capsule_overlaps(&world, &entities.frames, tuning, player.position, player.up), "%d mm: the capsule overlaps the pod", spacing)

		// The cabin's side away from the fixtures: the wall at x -3.
		player.forward = tangent_of(player.up, -frame.axes[FRAME_RIGHT])
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 120)
		wall_face := i64(origin.x + 1) * pitch
		reached := frame_local_position(frame, player.position).x
		testing.expectf(t, reached >= wall_face + tuning.capsule_radius - FIELD_GROUND_TOLERANCE, "%d mm: the feet reached %d, the wall's face is at %d", spacing, reached, wall_face)
		testing.expectf(t, reached < wall_face + 2 * pitch, "%d mm: the walk stopped at %d before the wall", spacing, reached)
		testing.expectf(t, frame_cell_of_feet(frame, player).y == origin.y, "%d mm: the feet left the floor for %v", spacing, frame_cell_of_feet(frame, player))
	}
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

// The aiming ray from the airlock towards a chest outside stops at the
// closed outer hatch; open, a ray at row 1 reaches the chest and one at
// row 3 stops at the hatch's top row. At the side wall it stops at the
// wall.
@(test)
test_the_aiming_ray_passes_the_pods_open_cells_and_stops_at_its_walls :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	origin := pod_origin(pod)
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	front := origin.z + size.z - 1
	outside := World_Coordinate{1, origin.y + 1, front + 2}
	_, refusal := place_on_frame(&entities, machines, test_foundation(machines), frame.id, outside - UP, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	_, refusal = place_on_frame(&entities, machines, test_machine(machines, "wooden_chest"), frame.id, outside, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	inside := World_Coordinate{1, origin.y + 1, front - 2}
	testing.expect(t, !frame_cell_is_solid(&entities.frames, frame.id, inside))
	eye := frame_cell_centre(frame, inside)
	reach := 10 * frame_pitch_units(frame)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	at_hatch := raycast_frames(&entities.frames, eye, frame.axes[FRAME_FORWARD], reach, excluded = {.Open})
	testing.expectf(t, at_hatch.hit && at_hatch.cell == World_Coordinate{1, 1, front}, "the ray at the closed hatch hit %v", at_hatch.cell)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	out_of_door := raycast_frames(&entities.frames, eye, frame.axes[FRAME_FORWARD], reach, excluded = {.Open})
	testing.expectf(t, out_of_door.hit && out_of_door.cell == outside, "the ray through the door hit %v", out_of_door.cell)
	testing.expect_value(t, entity_at(&entities, out_of_door.cell, frame.id).kind, Entity_Kind.Chest)
	high := frame_cell_centre(frame, inside + {0, 2, 0})
	at_top := raycast_frames(&entities.frames, high, frame.axes[FRAME_FORWARD], reach, excluded = {.Open})
	testing.expectf(t, at_top.hit && at_top.cell == World_Coordinate{1, 3, front}, "the ray at row 3 hit %v", at_top.cell)
	testing.expect_value(t, entity_from_occupant(at_top.occupant.handle), outer)
	at_wall := raycast_frames(&entities.frames, eye, frame.axes[FRAME_RIGHT], reach, excluded = {.Open})
	testing.expect_value(t, at_wall.cell, World_Coordinate{origin.x + size.x - 1, inside.y, inside.z})
	testing.expect(t, frame_cell_is_solid(&entities.frames, frame.id, at_wall.cell))
}

// The cells of a box of the pod's record, placed with the pod.
test_pod_box_cells :: proc(pod: Machine, box: int) -> []World_Coordinate {
	only := pod
	only.open_cells[0] = pod.open_cells[box]
	only.open_cell_box_count = 1
	return machine_open_cells(pod_origin(pod), only, POD_ROTATION)
}

// Both hatches closed: one room of exactly the pod's open cells, supplied
// by the generator. Outer open: the cabin alone. Inner open: the open
// cells and the inner hatch's. Both open: no room.
@(test)
test_the_sealed_room_follows_the_hatches :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	open := machine_open_cells(pod_origin(pod), pod, POD_ROTATION)
	generator := test_pod_fixture(&entities, frame, pod, TEST_GENERATOR)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	inner := test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)
	testing.expect_value(t, len(entities.sealed_rooms), 1)
	if len(entities.sealed_rooms) != 1 {
		return
	}
	room := entities.sealed_rooms[0]
	testing.expect(t, slice.equal(sorted_cells(room.cells[:]), sorted_cells(open)), "the room is the open cells")
	testing.expect_value(t, room.supplier, generator)
	testing.expect_value(t, room.oxygen, Oxygen_Supply.Unlimited)
	testing.expect(t, oxygen_generator_supplies_a_room(&entities, generator))

	toggle_hatch(&entities, machines, outer, 1, nil)
	airlock := test_pod_box_cells(pod, 3)
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
		testing.expect(t, slice.equal(sorted_cells(entities.sealed_rooms[0].cells[:]), sorted_cells(with_hatch[:])), "inner open: the open cells and the inner hatch")
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
	locker_origin, _ := pod_fixture_placement(pod, pod_origin(pod), POD_ROTATION, TEST_LOCKER)
	// The fixtures stand along the frame's x 3 wall, the cabin at x 2.
	for cell in ([2]World_Coordinate{bench_origin + {0, 2, 0}, locker_origin + {-1, 0, 0}}) {
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
	machines.machines[pod_machine].lights[0] = {position = {0, 5.8, 0}, color = {1, 0.6, 0.15}, radius_cells = 6}
	machines.machines[pod_machine].lights[1] = {position = {3, 2, 0}, color = {0.77, 0.89, 1}, radius_cells = 2}
	machines.machines[pod_machine].light_count = 2
	machines.machines[generator_machine].lights[0] = {position = {0, 1, 0}, color = {0.77, 0.89, 1}, radius_cells = 3}
	machines.machines[generator_machine].light_count = 1
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	lights := make([dynamic]Point_Light, context.temp_allocator)
	gather_machine_lights(&lights, &entities, machines)
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
	expected := machine_point_light(pod.lights[0], entity_body_matrix(&entities, pod_common), 500)
	testing.expect(t, slice.contains(lights[:], expected), "the pod's first lamp is gathered where its model is drawn")

	toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), 1, nil)
	toggle_hatch(&entities, machines, test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH), 2, nil)
	clear(&lights)
	gather_machine_lights(&lights, &entities, machines)
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
