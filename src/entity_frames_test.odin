package game

import "core:testing"

test_foundation :: proc(machines: Machine_Registry) -> Machine_Id {
	return test_machine(machines, "foundation")
}

// A free foundation's frame has its up along the radial at the hit and
// holds the foundation at cell (0, 0, 0).
@(test)
test_a_free_foundation_starts_a_frame_whose_up_is_the_radial :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	handle, frame := place_free_foundation(&entities, machines, test_foundation(machines), TEST_FRAME_HIT, {0, 0, UNIT_VECTOR_ONE}, 500)
	record, found := find_frame(&entities.frames, frame)
	testing.expect(t, found && frame != BLOCK_FRAME)
	up, _ := normalize_fixed(cast([3]i64)(TEST_FRAME_HIT))
	testing.expect_value(t, record.axes[FRAME_UP], up)
	testing.expect_value(t, record.pitch_millimetres, 500)
	testing.expect_value(t, entity_at(&entities, {}, frame), handle)
	testing.expect_value(t, entity_at(&entities, {}), NO_ENTITY)
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 1)
}

// Snapping joins the frame exactly: the count grows by one and no frame
// is added; a free foundation fifty metres away starts a second frame,
// and the two keep their own cells.
@(test)
test_snapped_foundations_join_and_free_ones_fifty_metres_apart_are_two_frames :: proc(t: ^testing.T) {
	machines := make_test_machines()
	foundation := test_foundation(machines)
	entities: Entities
	defer destroy_entities(&entities)
	_, first := place_free_foundation(&entities, machines, foundation, TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	_, refusal := place_on_frame(&entities, machines, foundation, first, {1, 0, 0}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	testing.expect_value(t, frame_cell_count(&entities.frames, first), 2)
	testing.expect_value(t, len(entities.frames.frames), 1)
	_, refusal = place_on_frame(&entities, machines, foundation, first, {1, 0, 0}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.Occupied)
	up, _ := normalize_fixed(cast([3]i64)(TEST_FRAME_HIT))
	across := fixed_cross(up, {0, UNIT_VECTOR_ONE, 0})
	across, _ = normalize_fixed(across)
	away := TEST_FRAME_HIT + World_Position(fixed_scale(across, metres_to_position_units(50)))
	_, second := place_free_foundation(&entities, machines, foundation, away, {UNIT_VECTOR_ONE, 0, 0}, 500)
	testing.expect(t, second != first)
	testing.expect_value(t, len(entities.frames.frames), 2)
	testing.expect_value(t, frame_cell_count(&entities.frames, first), 2)
	testing.expect_value(t, frame_cell_count(&entities.frames, second), 1)
	first_record, _ := find_frame(&entities.frames, first)
	second_record, _ := find_frame(&entities.frames, second)
	testing.expect(t, first_record.axes[FRAME_UP] != second_record.axes[FRAME_UP], "fifty metres round the planet the up differs")
}

// A 2 by 2 by 2 furnace on a 3 by 3 pad occupies its eight cells; a
// second over them is refused, one off the pad is unsupported, and
// picking the first up frees its cells.
@(test)
test_a_machine_on_a_frame_occupies_its_footprint_and_a_second_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	foundation := test_foundation(machines)
	furnace := test_machine(machines, "stone_furnace")
	entities: Entities
	defer destroy_entities(&entities)
	_, frame := place_free_foundation(&entities, machines, foundation, TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	for x in i32(0) ..< 3 {
		for z in i32(0) ..< 3 {
			if x != 0 || z != 0 {
				place_on_frame(&entities, machines, foundation, frame, {x, 0, z}, 0)
			}
		}
	}
	handle, refusal := place_on_frame(&entities, machines, furnace, frame, {0, 1, 0}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	for cell in footprint_cells({0, 1, 0}, machines.machines[furnace].footprint, 0) {
		testing.expect_value(t, entity_at(&entities, cell, frame), handle)
	}
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 9 + 8)
	testing.expect_value(t, frame_placement_refusal(&entities, machines, furnace, frame, {1, 1, 1}, 0), Frame_Placement_Refusal.Occupied)
	testing.expect_value(t, frame_placement_refusal(&entities, machines, furnace, frame, {2, 1, 2}, 0), Frame_Placement_Refusal.Unsupported)
	testing.expect_value(t, frame_placement_refusal(&entities, machines, furnace, Frame_Id(99), {0, 1, 0}, 0), Frame_Placement_Refusal.Unknown_Frame)
	testing.expect(t, remove_entity(&entities, machines, handle))
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 9)
	testing.expect_value(t, frame_placement_refusal(&entities, machines, furnace, frame, {1, 1, 1}, 0), Frame_Placement_Refusal.None)
}

// An entity's world position is its frame's transform of its cell: the
// chest's cell centre lies along the frame's axes from the origin, and
// world to cell gives the cell back, a few thousand cells out.
@(test)
test_an_entitys_world_position_is_the_frame_transform_of_its_cell :: proc(t: ^testing.T) {
	machines := make_test_machines()
	chest := test_machine(machines, "wooden_chest")
	entities: Entities
	defer destroy_entities(&entities)
	_, frame := place_free_foundation(&entities, machines, test_foundation(machines), TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	record, _ := find_frame(&entities.frames, frame)
	pitch := frame_pitch_units(record)
	for cell in ([?]World_Coordinate{{0, 1, 0}, {2_500, 1, -3_000}, {-4_000, 3, 4_000}}) {
		handle := add_entity(&entities, machines, chest, cell, 0, frame)
		common := entity_common(&entities, handle)
		testing.expect_value(t, common.frame, frame)
		position := frame_cell_centre(record, common.origin)
		along := record.origin + World_Position(fixed_scale(record.axes[FRAME_RIGHT], i64(cell.x) * pitch + pitch / 2) + fixed_scale(record.axes[FRAME_UP], i64(cell.y) * pitch + pitch / 2) + fixed_scale(record.axes[FRAME_FORWARD], i64(cell.z) * pitch + pitch / 2))
		testing.expectf(t, vector_length(cast([3]i64)(position - along)) <= 3, "%v: %v against %v", cell, position, along)
		testing.expect_value(t, world_to_frame_cell(record, position), cell)
		testing.expect_value(t, entity_at(&entities, world_to_frame_cell(record, position), frame), handle)
	}
}

// The field: holding a foundation, Place on the ground ahead starts a
// frame through the queue and takes an item; Place again on the face the
// reticle meets (the near side, looking down at 45 degrees) snaps the next
// one into the cell in front of it on that frame.
@(test)
test_the_field_places_foundations_through_the_queue :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation = find_foundation_machine(content.machines)
	content.field.foundation_pitch_millimetres = 500
	simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"foundation", 3})
	simulation.players[0].field.pitch = degrees_to_angle_units(-45)
	tick_field_simulation(&simulation, content, {})
	testing.expect(t, simulation.players[0].field.target.hit)
	simulation.players[0].field.tool = .Foundation
	place := [1]Field_Player_Input{{held = {.Place}, just_pressed = {.Place}}}
	tick_field_simulation(&simulation, content, place[:])
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, len(simulation.field.placements), 0)
	testing.expect_value(t, len(simulation.world.entities.frames.frames), 1)
	frame := simulation.world.entities.frames.frames[0].id
	testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame), 1)
	testing.expect_value(t, inventory_count(simulation.players[0].inventory, test_item(items, "foundation")), 2)
	// The tick aims before the queue drains, so the next tick sees the frame.
	tick_field_simulation(&simulation, content, {})
	testing.expect(t, simulation.players[0].field.frame_target.hit && !simulation.players[0].field.target.hit, "the frame is nearer than the ground under it")
	snapped := simulation.players[0].field.frame_target.adjacent
	tick_field_simulation(&simulation, content, place[:])
	testing.expect_value(t, len(simulation.world.entities.frames.frames), 1)
	testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame), 2)
	testing.expect(t, snapped != World_Coordinate{})
	testing.expect_value(t, entity_at(&simulation.world.entities, snapped, frame).kind, Entity_Kind.Foundation)
}

// A belt into an inserter into a chest on a foundation pad of frame 1,
// over a block world whose frame 0 holds a chest at the belt's cell, a
// chest at the inserter's drop cell and a belt at the belt's output cell:
// every neighbour lookup stays in frame 1, so the plate reaches frame 1's
// chest and frame 0's entities are left alone.
@(test)
test_a_belt_feeds_an_inserter_into_a_chest_on_frame_1 :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	foundation := test_foundation(content.machines)
	_, frame := place_free_foundation(&world.entities, content.machines, foundation, TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	testing.expect_value(t, frame, Frame_Id(1))
	for x in i32(0) ..< 3 {
		for z in i32(0) ..< 3 {
			if x != 0 || z != 0 {
				place_on_frame(&world.entities, content.machines, foundation, frame, {x, 0, z}, 0)
			}
		}
	}
	belt_machine := find_belt_machine(content.machines, .Flat)
	first := add_belt(&world.entities, content.machines, belt_machine, {0, 1, 0}, 0, .Flat, frame)
	second := add_belt(&world.entities, content.machines, belt_machine, {1, 1, 0}, 0, .Flat, frame)
	// The arm reaches four cells at 500 mm (work item 0175).
	inserter := add_entity(&world.entities, content.machines, test_machine(content.machines, "burner_inserter"), {1, 1, 4}, 1, frame)
	pool_get(&world.entities.inserters, inserter).slots[INSERTER_FUEL_SLOT] = Item_Stack{test_item(content.items, "coal"), 5}
	chest := add_entity(&world.entities, content.machines, test_machine(content.machines, "wooden_chest"), {1, 1, 8}, 0, frame)
	block_source := place_test_entity(&world, content, "wooden_chest", {1, 1, 0})
	block_target := place_test_entity(&world, content, "wooden_chest", {1, 1, 2})
	block_belt := lay_belt(&world, content, {2, 1, 0}, 0)
	plate, copper := test_item(content.items, "iron_plate"), test_item(content.items, "copper_plate")
	entity_insert(&world.entities, content, block_source, Item_Stack{copper, 10}, .Left)
	testing.expect_value(t, line_of(&world, first), line_of(&world, second))
	testing.expect(t, line_of(&world, first) != line_of(&world, block_belt), "frame 1's line ends at its own last belt")
	testing.expect(t, belt_insert_item(&world.entities, first, .Left, plate))
	tick_test_entities(&world, &records, content, 120)
	testing.expect_value(t, chest_count_of(&world, chest, plate), 1)
	testing.expect_value(t, chest_count_of(&world, chest, copper), 0)
	testing.expect_value(t, chest_count_of(&world, block_target, plate), 0)
	testing.expect_value(t, chest_count_of(&world, block_target, copper), 0)
	testing.expect_value(t, chest_count_of(&world, block_source, copper), 10)
	testing.expect_value(t, len(line_of(&world, block_belt).lanes[.Left]), 0)
}

// Two field players with a foundation each and one with none, a frame far
// from them all.
make_field_placement_test :: proc() -> (simulation: Simulation_State, content: Simulation_Content, items: Item_Registry, frame: Frame_Id) {
	items = make_test_items()
	content = test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation = find_foundation_machine(content.machines)
	content.field.foundation_pitch_millimetres = 500
	simulation = make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	add_test_miner(&simulation, items, FAR_FEET, {"foundation", 1})
	add_test_miner(&simulation, items, FAR_FEET + {0, 0, 10 * POSITION_UNITS_PER_METRE}, {"foundation", 1})
	add_test_miner(&simulation, items, FAR_FEET + {0, 0, 20 * POSITION_UNITS_PER_METRE})
	_, frame = place_free_foundation(&simulation.world.entities, content.machines, content.field.foundation, TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	return
}

// The drain checks each placement against the world as the ones before it
// left it: two players snapping into one cell in one tick place one
// foundation, and only the first pays; a player without a foundation is
// refused Nothing_Held; a frame that is gone is Unknown_Frame; a free
// foundation over a player's feet is Would_Bury_Player.
@(test)
test_the_drain_validates_each_field_placement :: proc(t: ^testing.T) {
	simulation, content, items, frame := make_field_placement_test()
	defer destroy_simulation(&simulation)
	foundation_item := test_item(items, "foundation")
	snap := Field_Placement{machine = content.field.foundation, frame = frame, cell = {1, 0, 0}}
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = snap}, Queued_Field_Placement{player = 1, placement = snap})
	append(&simulation.field.placements, Queued_Field_Placement{player = 2, placement = Field_Placement{machine = content.field.foundation, frame = frame, cell = {2, 0, 0}}})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, len(simulation.field.placements), 0)
	testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame), 2)
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, inventory_count(simulation.players[0].inventory, foundation_item), 0)
	testing.expect_value(t, simulation.players[1].field_refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	testing.expect_value(t, inventory_count(simulation.players[1].inventory, foundation_item), 1)
	testing.expect_value(t, simulation.players[2].field_refusal, Field_Edit_Refusal.Nothing_Held)

	gone := Field_Placement{machine = content.field.foundation, frame = Frame_Id(99), cell = {0, 1, 0}}
	append(&simulation.field.placements, Queued_Field_Placement{player = 1, placement = gone})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[1].field_refusal, Field_Edit_Refusal.Unknown_Frame)

	over_feet := Field_Placement{machine = content.field.foundation, new_frame = true, hit = simulation.players[1].field.position, heading = {UNIT_VECTOR_ONE, 0, 0}}
	append(&simulation.field.placements, Queued_Field_Placement{player = 1, placement = over_feet})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[1].field_refusal, Field_Edit_Refusal.Would_Bury_Player)
	testing.expect_value(t, len(simulation.world.entities.frames.frames), 1)
	testing.expect_value(t, inventory_count(simulation.players[1].inventory, foundation_item), 1)
}

// Foundations on the flat test site: a free one at (x, 0, z) metres from
// the site and its frame's cells from low to high (frame cells) snapped to
// it, the pad's top a pitch over the ground.
lay_test_pad :: proc(entities: ^Entities, machines: Machine_Registry, x, z: i64, low, high: World_Coordinate) -> Frame {
	foundation := test_foundation(machines)
	hit := test_site_point(x, 0, z)
	_, frame := place_free_foundation(entities, machines, foundation, hit, {UNIT_VECTOR_ONE, 0, 0}, 500)
	for cell_z in low.z ..= high.z {
		for cell_y in low.y ..= high.y {
			for cell_x in low.x ..= high.x {
				place_on_frame(entities, machines, foundation, frame, {cell_x, cell_y, cell_z}, 0)
			}
		}
	}
	record, _ := find_frame(&entities.frames, frame)
	return record
}

run_field_player_with_frames :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, input: Field_Player_Input, ticks: int) {
	for _ in 0 ..< ticks {
		tick_field_player(world, frames, tuning, player, input)
	}
}

// Dropped from two metres onto a five by five pad, the player rests on
// its top, a pitch over the ground, at every spacing, clear of the cells.
@(test)
test_a_field_player_rests_on_a_foundation_pad :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		entities: Entities
		defer destroy_entities(&entities)
		frame := lay_test_pad(&entities, machines, 0, 0, {-2, 0, -2}, {2, 0, 2})
		tuning := test_field_tuning(spacing)
		player := make_field_player(test_site_point(0, 2 * POSITION_UNITS_PER_METRE, 0), {UNIT_VECTOR_ONE, 0, 0})
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 90)
		top := frame_pitch_units(frame)
		testing.expectf(t, player.on_ground, "%d mm: not on the pad", spacing)
		testing.expectf(t, abs(site_height(player.position) - top) <= tenth_sample(spacing), "%d mm: feet at %d, the top at %d", spacing, site_height(player.position), top)
		testing.expectf(t, !field_capsule_overlaps(&world, &entities.frames, tuning, player.position, player.up), "%d mm: the capsule overlaps the pad", spacing)
	}
}

// A column of four cells 1.5 m ahead stops a walk into it: the feet stay
// short of its near face and the step does not climb it.
@(test)
test_walking_into_a_foundation_column_is_blocked :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		entities: Entities
		defer destroy_entities(&entities)
		frame := lay_test_pad(&entities, machines, 3 * POSITION_UNITS_PER_METRE / 2, 0, {0, 1, 0}, {0, 3, 0})
		tuning := test_field_tuning(spacing)
		player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), {UNIT_VECTOR_ONE, 0, 0})
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 120)
		near_face := 3 * POSITION_UNITS_PER_METRE / 2 - frame_pitch_units(frame) / 2
		testing.expectf(t, player.position.x <= near_face - tuning.capsule_radius + FIELD_GROUND_TOLERANCE, "%d mm: the feet reached %d, the face is at %d", spacing, player.position.x, near_face)
		testing.expectf(t, abs(site_height(player.position)) <= tenth_sample(spacing), "%d mm: the feet rose to %d", spacing, site_height(player.position))
		testing.expectf(t, !field_capsule_overlaps(&world, &entities.frames, tuning, player.position, player.up), "%d mm: the capsule overlaps the column", spacing)
	}
}

// A pad one cell high, its near edge 1.25 m ahead and 3.5 m long, is a
// step at every spacing: walking on lifts the feet onto its top. The walk
// stops short of the far edge, also after the 1000 mm ledge move.
@(test)
test_walking_onto_a_one_cell_pad_steps_up :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		entities: Entities
		defer destroy_entities(&entities)
		frame := lay_test_pad(&entities, machines, 3 * POSITION_UNITS_PER_METRE, 0, {-3, 0, -3}, {3, 0, 3})
		tuning := test_field_tuning(spacing)
		player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), {UNIT_VECTOR_ONE, 0, 0})
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 30)
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, FIELD_WALK_FORWARD, 40)
		top := frame_pitch_units(frame)
		testing.expectf(t, player.on_ground, "%d mm: not on the ground", spacing)
		testing.expectf(t, abs(site_height(player.position) - top) <= tenth_sample(spacing), "%d mm: feet at %d, the top at %d (x %d)", spacing, site_height(player.position), top, player.position.x)
		testing.expectf(t, player.position.x > 3 * POSITION_UNITS_PER_METRE - 3 * top, "%d mm: the feet stopped at %d", spacing, player.position.x)
	}
}

// Standing on a pad and looking down past its edge, the tool still meets
// the field beside it, so the brush works from a pad.
@(test)
test_the_field_target_from_a_pad_hits_the_ground_beside_it :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		entities: Entities
		defer destroy_entities(&entities)
		lay_test_pad(&entities, machines, 0, 0, {-2, 0, -2}, {2, 0, 2})
		tuning := test_field_tuning(spacing)
		player := make_field_player(test_site_point(0, 2 * POSITION_UNITS_PER_METRE, 0), {UNIT_VECTOR_ONE, 0, 0})
		player.pitch = degrees_to_angle_units(-45)
		run_field_player_with_frames(&world, &entities.frames, tuning, &player, {}, 90)
		aim_field_player_at_frames(&player, &entities.frames, tuning)
		testing.expectf(t, player.target.hit && !player.frame_target.hit, "%d mm: the target is %v, the frame target %v", spacing, player.target.hit, player.frame_target.hit)
		testing.expectf(t, abs(site_height(player.target.position)) <= tenth_sample(spacing), "%d mm: the hit is %d over the ground", spacing, site_height(player.target.position))
	}
}

// Foundation blocks (0193).

// The content of make_field_placement_test with the block lists of a
// shipped game.sjson's shape.
TEST_FOUNDATION_SIZES := [?]int{1, 2, 5}
TEST_FOUNDATION_HEIGHTS := [?]int{1, 2}

with_test_foundation_blocks :: proc(content: ^Simulation_Content) {
	content.field.foundation_sizes = TEST_FOUNDATION_SIZES[:]
	content.field.foundation_heights = TEST_FOUNDATION_HEIGHTS[:]
}

// A top face's square is centred on the anchor (an even side's extra cell
// on the high side) and the block rises along the normal; a side face's
// square rises from the anchor's row; a bottom face's block runs down.
@(test)
test_a_foundation_block_spans_the_face_and_runs_along_its_normal :: proc(t: ^testing.T) {
	top := foundation_block_cells({0, 1, 0}, UP, 3, 2)
	testing.expect_value(t, len(top), 18)
	testing.expect_value(t, top[0], World_Coordinate{-1, 1, -1})
	testing.expect_value(t, top[17], World_Coordinate{1, 2, 1})
	even := foundation_block_cells({}, {}, 2, 1)
	testing.expect_value(t, even[0], World_Coordinate{0, 0, 0})
	testing.expect_value(t, even[3], World_Coordinate{1, 0, 1})
	side := foundation_block_cells({1, 0, 0}, {1, 0, 0}, 3, 2)
	testing.expect_value(t, side[0], World_Coordinate{1, 0, -1})
	testing.expect_value(t, side[8], World_Coordinate{1, 2, 1})
	testing.expect_value(t, side[17], World_Coordinate{2, 2, 1})
	bottom := foundation_block_cells({0, -1, 0}, -UP, 1, 2)
	testing.expect_value(t, bottom[1], World_Coordinate{0, -2, 0})
}

// Holding a 2 by 2 foundation block 2 high, Place on the ground ahead
// starts one frame holding eight foundations in cells (0..1, 0..1, 0..1)
// and takes eight items.
@(test)
test_a_free_foundation_block_fills_its_cells_and_costs_one_each :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation = find_foundation_machine(content.machines)
	content.field.foundation_pitch_millimetres = 500
	with_test_foundation_blocks(&content)
	simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"foundation", 10})
	player := &simulation.players[0]
	player.field.pitch = degrees_to_angle_units(-45)
	player.field.tool = .Foundation
	player.field.foundation_size_index, player.field.foundation_height_index = 1, 1
	tick_field_simulation(&simulation, content, {})
	place := [1]Field_Player_Input{{held = {.Place}, just_pressed = {.Place}}}
	tick_field_simulation(&simulation, content, place[:])
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, len(simulation.world.entities.frames.frames), 1)
	frame := simulation.world.entities.frames.frames[0].id
	testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame), 8)
	for cell in foundation_block_cells({}, UP, 2, 2) {
		testing.expectf(t, entity_at(&simulation.world.entities, cell, frame).kind == .Foundation, "cell %v", cell)
	}
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "foundation")), 2)
}

// A 3 by 3 block on a side face stands as a wall from the adjacent cell's
// row; on the top face a block rises from the adjacent cell; a block
// reaching a taken cell is refused whole and places nothing.
@(test)
test_a_foundation_block_on_a_top_face_rises_from_the_adjacent_cell :: proc(t: ^testing.T) {
	simulation, content, items, frame := make_field_placement_test()
	defer destroy_simulation(&simulation)
	foundation_item := test_item(items, "foundation")
	inventory_add(simulation.players[0].inventory, items, foundation_item, 9)
	entities := &simulation.world.entities
	over_cell := Field_Placement{machine = content.field.foundation, frame = frame, cell = {1, 0, 0}, normal = {1, 0, 0}, size = 3}
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = over_cell})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 10)
	single := Field_Placement{machine = content.field.foundation, frame = frame, cell = {0, 1, 0}, normal = UP, size = 1, height = 1}
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = single})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
	top := Field_Placement{machine = content.field.foundation, frame = frame, cell = {0, 1, 0}, normal = UP, size = 2, height = 2}
	inventory_add(simulation.players[1].inventory, items, foundation_item, 7)
	append(&simulation.field.placements, Queued_Field_Placement{player = 1, placement = top})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[1].field_refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 11)
	testing.expect_value(t, inventory_count(simulation.players[1].inventory, foundation_item), 8)
	top.cell = {-2, 1, 0}
	// The tick resets the refusal before its queue (queue_field_player_edit).
	simulation.players[1].field_refusal = .None
	append(&simulation.field.placements, Queued_Field_Placement{player = 1, placement = top})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[1].field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 19)
	expected := [?]World_Coordinate{{-2, 1, 0}, {-1, 1, 1}, {-2, 2, 0}, {-1, 2, 1}}
	for cell in expected {
		testing.expectf(t, entity_at(entities, cell, frame).kind == .Foundation, "cell %v", cell)
	}
	testing.expect_value(t, inventory_count(simulation.players[1].inventory, foundation_item), 0)
}

// Two sessions placing the same block hash the same: the cells enter the
// entity table in one order.
@(test)
test_two_sessions_placing_one_foundation_block_hash_the_same :: proc(t: ^testing.T) {
	hashes: [2]u64
	for index in 0 ..< 2 {
		simulation, content, items, frame := make_field_placement_test()
		defer destroy_simulation(&simulation)
		inventory_add(simulation.players[0].inventory, items, test_item(items, "foundation"), 49)
		block := Field_Placement{machine = content.field.foundation, frame = frame, cell = {0, 1, 0}, normal = UP, size = 5, height = 2}
		append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = block})
		drain_field_placements(&simulation, content)
		testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame), 51)
		hashes[index] = simulation_state_hash(&simulation)
	}
	testing.expect_value(t, hashes[0], hashes[1])
}

// A player aimed at a free foundation's top face places a 2 by 2 block
// through its own aim (field_player_placement): the face's normal is up
// and the block rises from the adjacent cell, (0..1, 1, 0..1).
@(test)
test_an_aimed_foundation_block_rises_from_the_top_face :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation = find_foundation_machine(content.machines)
	content.field.foundation_pitch_millimetres = 500
	with_test_foundation_blocks(&content)
	simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"foundation", 10})
	player := &simulation.players[0]
	player.field.pitch = degrees_to_angle_units(-45)
	player.field.tool = .Foundation
	place := [1]Field_Player_Input{{held = {.Place}, just_pressed = {.Place}}}
	tick_field_simulation(&simulation, content, {})
	tick_field_simulation(&simulation, content, place[:])
	testing.expect_value(t, len(simulation.world.entities.frames.frames), 1)
	frame := simulation.world.entities.frames.frames[0].id
	player.field.pitch = degrees_to_angle_units(-35)
	player.field.foundation_size_index = 1
	tick_field_simulation(&simulation, content, {})
	target := player.field.frame_target
	testing.expect(t, target.hit && target.frame == frame && target.cell == World_Coordinate{}, "the reticle meets the first foundation")
	testing.expect_value(t, target.adjacent - target.cell, UP)
	placement, wanted := field_player_placement(player.field, content.field.foundation, content.field)
	testing.expect(t, wanted)
	testing.expect_value(t, placement.normal, UP)
	tick_field_simulation(&simulation, content, place[:])
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame), 5)
	expected := [?]World_Coordinate{{0, 1, 0}, {1, 1, 0}, {0, 1, 1}, {1, 1, 1}}
	for cell in expected {
		testing.expectf(t, entity_at(&simulation.world.entities, cell, frame).kind == .Foundation, "cell %v", cell)
	}
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "foundation")), 5)
}

// Picking up on the field (0195).

PICK_UP_TEST_TICKS :: 36

// The flat test site with the test machines, the foundation and its
// pitch; no player yet.
make_pick_up_test :: proc() -> (simulation: Simulation_State, content: Simulation_Content, items: Item_Registry) {
	items = make_test_items()
	content = test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation = find_foundation_machine(content.machines)
	content.field.foundation_pitch_millimetres = 500
	simulation = make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	return
}

// A player standing on the top face of the cell, looking straight down at
// it, carrying the stacks; one tick aims it.
stand_test_player_on_cell :: proc(simulation: ^Simulation_State, content: Simulation_Content, items: Item_Registry, frame: Frame, cell: World_Coordinate, stacks: ..Starting_Item) {
	feet := frame_cell_centre(frame, cell) + World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2))
	add_test_miner(simulation, items, feet, ..stacks)
	tick_field_simulation(simulation, content, {})
}

// Mine held for the ticks.
hold_test_mine :: proc(simulation: ^Simulation_State, content: Simulation_Content, ticks: int) {
	hold := [1]Field_Player_Input{{held = {.Dig}}}
	for _ in 0 ..< ticks {
		tick_field_simulation(simulation, content, hold[:])
	}
}

// The pitch, looking ahead, at which the player's reticle meets the cell,
// found by raising the reticle a degree a tick from straight down.
aim_test_player_at_cell :: proc(simulation: ^Simulation_State, content: Simulation_Content, frame: Frame_Id, cell: World_Coordinate) -> bool {
	player := &simulation.players[0]
	for degrees := -89; degrees <= 0; degrees += 1 {
		player.field.pitch = degrees_to_angle_units(degrees)
		tick_field_simulation(simulation, content, {})
		if target := player.field.frame_target; target.hit && target.frame == frame && target.cell == cell {
			return true
		}
	}
	return false
}

// Mine held on a lone foundation picks it up after PICK_UP_SECONDS, not a
// tick before: the item comes back and the empty frame is gone.
@(test)
test_mine_held_on_a_lone_foundation_picks_it_up_and_removes_its_frame :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	testing.expect_value(t, mining_required_ticks(PICK_UP_SECONDS, simulation.tick_rate), u32(PICK_UP_TEST_TICKS))
	_, frame_id := place_free_foundation(&simulation.world.entities, content.machines, content.field.foundation, test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	frame, _ := find_frame(&simulation.world.entities.frames, frame_id)
	stand_test_player_on_cell(&simulation, content, items, frame, {})
	player := &simulation.players[0]
	testing.expect(t, player.field.frame_target.hit && player.field.frame_target.cell == World_Coordinate{}, "the reticle meets the foundation")
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS - 1)
	testing.expect_value(t, len(simulation.world.entities.frames.frames), 1)
	testing.expect(t, mining_fraction(player.mining) > 0.9, "the progress the HUD draws")
	hold_test_mine(&simulation, content, 1)
	testing.expect_value(t, len(simulation.world.entities.frames.frames), 0)
	testing.expect_value(t, entity_at(&simulation.world.entities, {}, frame_id), NO_ENTITY)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "foundation")), 1)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, !player.mining.active)
}

// A foundation under a furnace refuses with Something_Stands_On_It and
// gets no progress; the furnace is picked up first, then the foundation.
// A pole with a run refuses until the run is gone.
@(test)
test_a_foundation_under_a_furnace_refuses_until_the_furnace_is_gone :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	frame := lay_test_pad(entities, content.machines, 0, 0, {0, 0, 0}, {1, 0, 0})
	for cell in ([?]World_Coordinate{{0, 0, 2}, {1, 0, 2}, {0, 0, 3}, {1, 0, 3}}) {
		place_on_frame(entities, content.machines, content.field.foundation, frame.id, cell, 0)
	}
	furnace := test_machine(content.machines, "stone_furnace")
	_, refusal := place_on_frame(entities, content.machines, furnace, frame.id, {0, 1, 2}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	stand_test_player_on_cell(&simulation, content, items, frame, {})
	player := &simulation.players[0]
	held := World_Coordinate{0, 0, 2}
	testing.expect(t, aim_test_player_at_cell(&simulation, content, frame.id, held), "the reticle meets the foundation under the furnace")
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS + 4)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Something_Stands_On_It)
	testing.expect(t, !player.mining.active)
	testing.expect_value(t, entity_at(entities, held, frame.id).kind, Entity_Kind.Foundation)
	testing.expect(t, aim_test_player_at_cell(&simulation, content, frame.id, {0, 1, 2}) || aim_test_player_at_cell(&simulation, content, frame.id, {0, 2, 2}), "the reticle meets the furnace")
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS)
	testing.expect_value(t, entity_at(entities, {0, 1, 2}, frame.id), NO_ENTITY)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "stone_furnace")), 1)
	testing.expect(t, aim_test_player_at_cell(&simulation, content, frame.id, held), "the reticle meets the foundation again")
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, entity_at(entities, held, frame.id), NO_ENTITY)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "foundation")), 1)

	// A pole with a run on it refuses the same way and keeps the run; with
	// the run gone it comes off.
	first := add_test_pole(entities, content.machines, test_site_point(20 * TEST_RUN_METRE, 0, 0), 0)
	second := add_test_pole(entities, content.machines, test_site_point(30 * TEST_RUN_METRE, 0, 0), 0)
	run, run_refusal := add_test_run(entities, content.machines, first, second)
	testing.expect_value(t, run_refusal, Belt_Run_Refusal.None)
	pole := pool_get(&entities.belt_poles, first)^
	pick_up := Field_Placement{kind = .Pick_Up, frame = pole.frame, cell = pole.origin}
	player.field_refusal = .None
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = pick_up})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Something_Stands_On_It)
	testing.expect(t, pool_get(&entities.belt_poles, first) != nil && pool_get(&entities.belt_runs, run) != nil, "the pole and its run stay")
	remove_belt_run(entities, content.machines, run)
	player.field_refusal = .None
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = pick_up})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, pool_get(&entities.belt_poles, first) == nil, "the pole is picked up")
}

// The pod's pad and the pod stay under a held Mine, with no progress and
// no refusal told; a foundation the player added beside the pad goes.
@(test)
test_the_pod_and_its_pad_refuse_a_pick_up :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	frame_id, ok := place_pod(entities, content.machines, test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	testing.expect(t, ok)
	frame, _ := find_frame(&entities.frames, frame_id)
	beside := World_Coordinate{POD_PAD_FIRST_CELL + POD_PAD_SIZE, 0, 0}
	place_on_frame(entities, content.machines, content.field.foundation, frame_id, beside, 0)
	cells := frame_cell_count(&entities.frames, frame_id)
	pod := content.machines.machines[find_machine_of_kind(content.machines, .Pod)]
	top := pod_origin(pod) + {0, pod.footprint.y - 1, 0}
	for cell in ([?]World_Coordinate{{POD_PAD_FIRST_CELL, 0, POD_PAD_FIRST_CELL}, top}) {
		clear(&simulation.players)
		stand_test_player_on_cell(&simulation, content, items, frame, cell)
		testing.expectf(t, simulation.players[0].field.frame_target.cell == cell, "the reticle meets %v", cell)
		hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS + 4)
		testing.expect(t, !simulation.players[0].mining.active)
		testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
		testing.expect_value(t, frame_cell_count(&entities.frames, frame_id), cells)
		destroy_player(simulation.players[0])
	}
	clear(&simulation.players)
	stand_test_player_on_cell(&simulation, content, items, frame, beside)
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS)
	testing.expect_value(t, frame_cell_count(&entities.frames, frame_id), cells - 1)
}

// With no room for the foundation the pick up is refused with
// Inventory_Full and the foundation stays: the field has no loose items
// to spill it as. A Mine held for 100 ticks makes no progress and tells
// the refusal once.
@(test)
test_a_pick_up_into_a_full_inventory_is_refused_and_the_foundation_stays :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	_, frame_id := place_free_foundation(&simulation.world.entities, content.machines, content.field.foundation, test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	frame, _ := find_frame(&simulation.world.entities.frames, frame_id)
	stand_test_player_on_cell(&simulation, content, items, frame, {})
	player := &simulation.players[0]
	stone := test_item(items, "stone")
	for &slot in player.inventory.slots {
		slot = Item_Stack{item = stone, count = item_stack_size(items, stone)}
	}
	hold := [1]Field_Player_Input{{held = {.Dig}}}
	news := 0
	for tick in 0 ..< 100 {
		previous := player.field_refusal
		tick_field_simulation(&simulation, content, hold[:])
		if field_refusal_is_news(player.field_refusal, previous, false) {
			news += 1
		}
		testing.expectf(t, !player.mining.active && mining_fraction(player.mining) == 0, "tick %d: no progress", tick)
	}
	testing.expect_value(t, news, 1)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Inventory_Full)
	testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame_id), 1)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "foundation")), 0)
}

// Two simulations picking up the same foundation hash the same, and the
// prediction's copy (predict_field_player_motion) holding Mine past
// PICK_UP_SECONDS picks nothing up and leaves the progress alone.
@(test)
test_two_sessions_picking_up_hash_the_same_and_the_prediction_picks_nothing :: proc(t: ^testing.T) {
	hashes: [2]u64
	for index in 0 ..< 2 {
		simulation, content, items := make_pick_up_test()
		defer destroy_simulation(&simulation)
		_, frame_id := place_free_foundation(&simulation.world.entities, content.machines, content.field.foundation, test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
		frame, _ := find_frame(&simulation.world.entities.frames, frame_id)
		stand_test_player_on_cell(&simulation, content, items, frame, {})
		if index == 1 {
			predicted := simulation.players[0]
			for _ in 0 ..< PICK_UP_TEST_TICKS + 4 {
				predict_field_player_motion(&simulation, content, &predicted, Input_Frame{pressed = {.Mine}})
			}
			testing.expect_value(t, frame_cell_count(&simulation.world.entities.frames, frame_id), 1)
			testing.expect(t, !predicted.mining.active)
			testing.expect_value(t, len(simulation.field.placements), 0)
		}
		hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS)
		testing.expect_value(t, len(simulation.world.entities.frames.frames), 0)
		hashes[index] = simulation_state_hash(&simulation)
	}
	testing.expect_value(t, hashes[0], hashes[1])
}
