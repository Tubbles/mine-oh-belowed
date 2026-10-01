package game

import "core:testing"

// Belt worlds stand on the stone floor of make_floor_world (top at y 1).

lay_belt :: proc(world: ^World, content: Simulation_Content, cell: World_Coordinate, direction: u8, shape := Belt_Shape.Flat) -> Entity_Handle {
	machine := find_belt_machine(content.machines, belt_shape_item_shape(shape))
	return add_belt(&world.entities, content.machines, machine, cell, direction, shape)
}

lay_belt_row :: proc(world: ^World, content: Simulation_Content, start: World_Coordinate, count: int, direction: u8) -> []Entity_Handle {
	handles := make([]Entity_Handle, count, context.temp_allocator)
	for index in 0 ..< count {
		handles[index] = lay_belt(world, content, start + belt_direction_offset(direction) * i32(index), direction)
	}
	return handles
}

lane_positions :: proc(line: Belt_Line, lane: Belt_Lane) -> []i32 {
	positions := make([]i32, len(line.lanes[lane]), context.temp_allocator)
	for entry, index in line.lanes[lane] {
		positions[index] = entry.position
	}
	return positions
}

expect_positions :: proc(t: ^testing.T, actual, expected: []i32, location := #caller_location) {
	testing.expect_value(t, len(actual), len(expected), location)
	for value, index in expected {
		if index < len(actual) {
			testing.expect_value(t, actual[index], value, location)
		}
	}
}

tick_belts :: proc(world: ^World, ticks: int) {
	for _ in 0 ..< ticks {
		tick_belt_network(&world.entities.belt_network, TEST_TICK_RATE, world.entities.splitters.entries[:])
	}
}

line_of :: proc(world: ^World, handle: Entity_Handle) -> ^Belt_Line {
	line, _ := belt_line_of(&world.entities, handle)
	return line
}

@(test)
test_belt_speed_and_spacing_arithmetic :: proc(t: ^testing.T) {
	content := make_test_content()
	belt := content.machines.machines[find_belt_machine(content.machines, .Flat)]
	// 1.875 blocks per second is 480 units per second, 8 per tick at 60 Hz.
	testing.expect_value(t, belt.belt_speed_units_per_second, 480)
	testing.expect_value(t, belt_units_per_tick(Belt_Line{speed_units_per_second = 480}, TEST_TICK_RATE), 8)
	// Front first: the front item moves, the one behind waits a spacing back.
	items := []Lane_Item{{position = 0}, {position = 10}}
	advance_lane_items(items, 8, 1000)
	testing.expect_value(t, items[0].position, 0)
	testing.expect_value(t, items[1].position, 18)
	items = []Lane_Item{{position = 0}, {position = 100}}
	advance_lane_items(items, 8, 1000)
	testing.expect_value(t, items[0].position, 8)
	testing.expect_value(t, items[1].position, 108)
	// The front limit clamps, and nothing moves backwards.
	items = []Lane_Item{{position = 500}}
	advance_lane_items(items, 8, 400)
	testing.expect_value(t, items[0].position, 500)
	// Insertion needs a spacing on both sides.
	lane := []Lane_Item{{position = 100}, {position = 300}}
	index, room := lane_insert_index(lane, 200)
	testing.expect_value(t, index, 1)
	testing.expect(t, room)
	_, room = lane_insert_index(lane, 150)
	testing.expect(t, !room)
	_, room = lane_insert_index(lane, 240)
	testing.expect(t, !room)
}

@(test)
test_belt_items_compress_at_a_dead_end :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {0, 1, 0}, 3, 0)
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	line := line_of(&world, belts[0])
	testing.expect_value(t, line.end.kind, Belt_Line_End_Kind.Dead_End)
	testing.expect(t, belt_insert_item(&world.entities, belts[0], .Left, test_item(content.items, "iron_plate")))
	// From 128 to the end limit 768 - 32 = 736 takes 76 ticks at 8 per tick.
	tick_belts(&world, 75)
	expect_positions(t, lane_positions(line^, .Left), {728})
	tick_belts(&world, 5)
	expect_positions(t, lane_positions(line^, .Left), {736})
	// Keep dropping mid first block: the lane fills back to the drop point.
	for _ in 0 ..< 600 {
		belt_insert_item(&world.entities, belts[0], .Left, test_item(content.items, "iron_plate"))
		tick_belts(&world, 1)
	}
	expect_positions(t, lane_positions(line^, .Left), {160, 224, 288, 352, 416, 480, 544, 608, 672, 736})
	testing.expect_value(t, len(line.lanes[.Right]), 0)
}

make_test_line :: proc(belt_count: int, speed: u32, end: Belt_Line_End) -> Belt_Line {
	line := Belt_Line {
		belts                  = make([dynamic]Entity_Handle, belt_count, context.temp_allocator),
		speed_units_per_second = speed,
		end                    = end,
	}
	for lane in Belt_Lane {
		line.lanes[lane] = make([dynamic]Lane_Item, context.temp_allocator)
	}
	return line
}

@(test)
test_belt_hand_off_between_lines :: proc(t: ^testing.T) {
	network: Belt_Network
	network.lines = make([dynamic]Belt_Line, context.temp_allocator)
	network.order = make([dynamic]i32, context.temp_allocator)
	append(&network.lines, make_test_line(1, 480, {kind = .Straight, line = 1}))
	append(&network.lines, make_test_line(2, 480, {}))
	compute_belt_line_order(&network)
	testing.expect_value(t, network.order[0], 1)
	testing.expect_value(t, network.order[1], 0)
	iron := Item_Id(3)
	append(&network.lines[0].lanes[.Right], Lane_Item{item = iron, position = 200})
	for _ in 0 ..< 6 {
		tick_belt_network(&network, TEST_TICK_RATE)
	}
	expect_positions(t, lane_positions(network.lines[0], .Right), {248})
	// 256 is past the end: the item continues at 0 of the next line and
	// is not moved again in the same tick.
	tick_belt_network(&network, TEST_TICK_RATE)
	testing.expect_value(t, len(network.lines[0].lanes[.Right]), 0)
	expect_positions(t, lane_positions(network.lines[1], .Right), {0})
	testing.expect_value(t, network.lines[1].lanes[.Right][0].item, iron)
	tick_belt_network(&network, TEST_TICK_RATE)
	expect_positions(t, lane_positions(network.lines[1], .Right), {8})
	// A stopped next line holds the item a spacing behind its back item.
	network.lines[1].speed_units_per_second = 0
	append(&network.lines[0].lanes[.Left], Lane_Item{item = iron, position = 200})
	append(&network.lines[1].lanes[.Left], Lane_Item{item = iron, position = 40})
	for _ in 0 ..< 20 {
		tick_belt_network(&network, TEST_TICK_RATE)
	}
	expect_positions(t, lane_positions(network.lines[0], .Left), {40 + 256 - BELT_ITEM_SPACING})
}

@(test)
test_belt_side_loads_onto_the_near_lane :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	main := lay_belt_row(&world, content, {0, 1, 0}, 4, 0)
	// Travelling +z into the -z side of an eastbound belt: its left side.
	feeder := lay_belt(&world, content, {2, 1, -1}, 1)
	testing.expect_value(t, len(world.entities.belt_network.lines), 2)
	feeder_line := line_of(&world, feeder)
	testing.expect_value(t, feeder_line.end, Belt_Line_End{kind = .Side_Load, line = pool_get(&world.entities.belts, main[0]).line, lane = .Left, position = 2 * 256 + 128})
	plate := test_item(content.items, "iron_plate")
	testing.expect(t, belt_insert_item(&world.entities, feeder, .Right, plate))
	// 128 to the end limit 224 is 12 ticks; the hand off happens at once.
	tick_belts(&world, 12)
	testing.expect_value(t, len(feeder_line.lanes[.Right]), 0)
	main_line := line_of(&world, main[0])
	expect_positions(t, lane_positions(main_line^, .Left), {640})
	testing.expect_value(t, len(main_line.lanes[.Right]), 0)
	tick_belts(&world, 1)
	expect_positions(t, lane_positions(main_line^, .Left), {648})
	// From the other side it lands on the right lane.
	other := lay_belt(&world, content, {1, 1, 1}, 3)
	testing.expect_value(t, line_of(&world, other).end.lane, Belt_Lane.Right)
}

@(test)
test_belt_curve_keeps_lanes :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	first := lay_belt(&world, content, {0, 1, 0}, 0)
	curve := lay_belt(&world, content, {1, 1, 0}, 1)
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	line := line_of(&world, first)
	testing.expect_value(t, len(line.belts), 2)
	testing.expect_value(t, pool_get(&world.entities.belts, curve).entry_direction, 0)
	testing.expect(t, belt_insert_item(&world.entities, first, .Left, test_item(content.items, "coal")))
	// Both lanes of the curve are one block long: 128 to 480 in 44 ticks.
	tick_belts(&world, 44)
	expect_positions(t, lane_positions(line^, .Left), {480})
	testing.expect_value(t, len(line.lanes[.Right]), 0)
	// A second side feeder turns the curve back into two side loads.
	lay_belt(&world, content, {2, 1, 0}, 2)
	testing.expect_value(t, len(world.entities.belt_network.lines), 3)
	testing.expect_value(t, pool_get(&world.entities.belts, curve).entry_direction, 1)
}

@(test)
test_belt_ramps_count_one_block :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	stone := test_block(content.blocks, "stone")
	set_blocks(&world, stone, {2, 1, 0}, {3, 1, 0})
	first := lay_belt(&world, content, {0, 1, 0}, 0)
	lay_belt(&world, content, {1, 1, 0}, 0, .Ramp_Up)
	lay_belt(&world, content, {2, 2, 0}, 0)
	lay_belt(&world, content, {3, 2, 0}, 0)
	lay_belt(&world, content, {4, 1, 0}, 0, .Ramp_Down)
	lay_belt(&world, content, {5, 1, 0}, 0)
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	line := line_of(&world, first)
	testing.expect_value(t, len(line.belts), 6)
	testing.expect(t, belt_insert_item(&world.entities, first, .Right, test_item(content.items, "coal")))
	// 128 to 6 * 256 - 32 = 1504 is 172 ticks.
	tick_belts(&world, 171)
	expect_positions(t, lane_positions(line^, .Right), {1496})
	tick_belts(&world, 5)
	expect_positions(t, lane_positions(line^, .Right), {1504})
}

@(test)
test_belt_lift_column_is_one_line :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	stone := test_block(content.blocks, "stone")
	set_blocks(&world, stone, {2, 1, 0}, {2, 2, 0}, {2, 3, 0})
	first := lay_belt(&world, content, {0, 1, 0}, 0)
	lay_belt(&world, content, {1, 1, 0}, 0, .Lift_Up)
	lay_belt(&world, content, {1, 2, 0}, 0, .Lift_Up)
	lay_belt(&world, content, {1, 3, 0}, 0, .Lift_Up)
	top := lay_belt(&world, content, {2, 4, 0}, 0)
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	line := line_of(&world, first)
	testing.expect_value(t, len(line.belts), 5)
	testing.expect_value(t, line.belts[4], top)
	// A belt facing into the middle of the column does not connect.
	middle_feeder := lay_belt(&world, content, {0, 2, 0}, 0)
	testing.expect_value(t, line_of(&world, middle_feeder).end.kind, Belt_Line_End_Kind.Dead_End)
	testing.expect_value(t, len(line_of(&world, first).belts), 5)
	// A down lift is entered from the level above its top block.
	world = make_floor_world(content.blocks, 32)
	set_blocks(&world, stone, {0, 1, 0}, {0, 2, 0}, {0, 3, 0})
	upper := lay_belt(&world, content, {0, 4, 0}, 0)
	lay_belt(&world, content, {1, 3, 0}, 0, .Lift_Down)
	lay_belt(&world, content, {1, 2, 0}, 0, .Lift_Down)
	lay_belt(&world, content, {1, 1, 0}, 0, .Lift_Down)
	lower := lay_belt(&world, content, {2, 1, 0}, 0)
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	down_line := line_of(&world, upper)
	testing.expect_value(t, len(down_line.belts), 5)
	testing.expect_value(t, down_line.belts[4], lower)
}

@(test)
test_belt_lines_rebuild_after_removing_a_middle_belt :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {0, 1, 0}, 5, 0)
	plate := test_item(content.items, "iron_plate")
	for belt in belts {
		testing.expect(t, belt_insert_item(&world.entities, belt, .Left, plate))
	}
	expect_positions(t, lane_positions(line_of(&world, belts[0])^, .Left), {128, 384, 640, 896, 1152})
	testing.expect(t, remove_entity(&world.entities, content.machines, belts[2]))
	testing.expect_value(t, len(world.entities.belt_network.lines), 2)
	before, after := line_of(&world, belts[0]), line_of(&world, belts[3])
	testing.expect(t, before != after)
	testing.expect_value(t, len(before.belts), 2)
	testing.expect_value(t, len(after.belts), 2)
	expect_positions(t, lane_positions(before^, .Left), {128, 384})
	expect_positions(t, lane_positions(after^, .Left), {128, 384})
	testing.expect_value(t, before.end.kind, Belt_Line_End_Kind.Dead_End)
	// Putting it back joins the runs again with the items where they were.
	lay_belt(&world, content, {2, 1, 0}, 0)
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	expect_positions(t, lane_positions(line_of(&world, belts[0])^, .Left), {128, 384, 896, 1152})
}

@(test)
test_belt_loop_continues_into_itself :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	lay_loop(&world, content, {0, 1, 0})
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	line := world.entities.belt_network.lines[0]
	testing.expect_value(t, len(line.belts), 10)
	testing.expect_value(t, line.end, Belt_Line_End{kind = .Straight, line = 0})
	testing.expect(t, belt_insert_item(&world.entities, line.belts[9], .Left, test_item(content.items, "coal")))
	// 9 * 256 + 128 = 2432 of 2560; 16 ticks later it is at 2560 = 0.
	tick_belts(&world, 16)
	expect_positions(t, lane_positions(world.entities.belt_network.lines[0], .Left), {0})
}

// A 4 by 3 rectangle of belts running clockwise seen from above.
lay_loop :: proc(world: ^World, content: Simulation_Content, corner: World_Coordinate) {
	lay_belt_row(world, content, corner, 3, 0)
	lay_belt_row(world, content, corner + {3, 0, 0}, 2, 1)
	lay_belt_row(world, content, corner + {3, 0, 2}, 3, 2)
	lay_belt_row(world, content, corner + {0, 0, 2}, 2, 3)
}

// Two identical worlds with a loop, a feeder side loading into it and a
// ramp run moving items for 1200 ticks end in the same state, and no
// lane ever holds two items closer than the spacing.
@(test)
test_belt_movement_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_floor_world(content.blocks, 32), make_floor_world(content.blocks, 32)}
	stone := test_block(content.blocks, "stone")
	coal, plate := test_item(content.items, "coal"), test_item(content.items, "iron_plate")
	for &world in worlds {
		lay_loop(&world, content, {0, 1, 0})
		feeder := lay_belt_row(&world, content, {1, 1, -4}, 4, 1)
		set_blocks(&world, stone, {10, 1, 0}, {11, 1, 0})
		ramp_run := lay_belt(&world, content, {8, 1, 0}, 0)
		lay_belt(&world, content, {9, 1, 0}, 0, .Ramp_Up)
		lay_belt(&world, content, {10, 2, 0}, 0)
		for tick in 0 ..< 1200 {
			belt_insert_item(&world.entities, feeder[0], Belt_Lane(tick % 2), tick % 3 == 0 ? coal : plate)
			belt_insert_item(&world.entities, ramp_run, .Right, plate)
			tick_belt_network(&world.entities.belt_network, TEST_TICK_RATE)
		}
	}
	first, second := worlds[0].entities.belt_network, worlds[1].entities.belt_network
	testing.expect_value(t, len(first.lines), len(second.lines))
	total := 0
	for line, line_index in first.lines {
		for lane in Belt_Lane {
			items, other := line.lanes[lane][:], second.lines[line_index].lanes[lane][:]
			testing.expect_value(t, len(items), len(other))
			for entry, index in items {
				testing.expect_value(t, entry, other[index])
				if index > 0 {
					testing.expect(t, entry.position - items[index - 1].position >= BELT_ITEM_SPACING)
				}
			}
			total += len(items)
		}
	}
	testing.expect(t, total > 20)
	// The loop filled up to its 40 items per lane and still moves.
	loop_line := line_of(&worlds[0], entity_at(&worlds[0].entities, {0, 1, 0}))
	testing.expect_value(t, len(loop_line.lanes[.Left]), 40)
	before := loop_line.lanes[.Left][0].position
	tick_belts(&worlds[0], 1)
	testing.expect(t, loop_line.lanes[.Left][0].position != before)
}

@(test)
test_player_walks_over_and_rides_a_belt :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {2, 1, 0}, 8, 0)
	testing.expect(t, !cell_blocks_movement(&world, content.blocks, {3, 1, 0}))
	testing.expect(t, cell_is_solid_or_entity(&world, content.blocks, {3, 1, 0}))
	players := []Player{make_test_player(content.blocks, {4.5, 1, 0.5})}
	players[0].on_ground = true
	tick_player(&world, content, players, 0, {}, TEST_TICK_RATE, 0)
	// One tick of 8 units is 1/32 block, exact in f32.
	testing.expect_value(t, players[0].position.x, 4.53125)
	testing.expect_value(t, players[0].position.y, 1)
	// Standing beside the belt does nothing.
	players[0].position = {4.5, 1, 1.5}
	tick_player(&world, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].position.x, 4.5)
	_ = belts
}

// A dead end over a drop lets the front items fall off into the cell in
// front, keeping their lane when they land on a belt below; a dead end
// on level ground holds them.
@(test)
test_belt_end_over_a_ledge_drops_and_a_level_dead_end_holds :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 3)
	use_temporary_loose_items(&world)
	plate := test_item(content.items, "iron_plate")
	set_blocks(&world, test_block(content.blocks, "stone"), {3, -3, 0}, {4, -3, 0}, {0, 0, 4}, {1, 0, 4}, {2, 0, 4}, {3, 0, 4})
	ledge := lay_belt_row(&world, content, {0, 1, 0}, 3, 0)
	below := lay_belt(&world, content, {3, -2, 0}, 0)
	level := lay_belt_row(&world, content, {0, 1, 4}, 3, 0)
	testing.expect(t, belt_insert_item(&world.entities, ledge[0], .Left, plate))
	testing.expect(t, belt_insert_item(&world.entities, ledge[0], .Right, plate))
	testing.expect(t, belt_insert_item(&world.entities, level[0], .Left, plate))
	cell, drops := belt_end_drop_cell(&world, content.blocks, line_of(&world, ledge[0])^)
	testing.expect(t, drops)
	testing.expect_value(t, cell, World_Coordinate{3, 1, 0})
	_, drops = belt_end_drop_cell(&world, content.blocks, line_of(&world, level[0])^)
	testing.expect(t, !drops)
	// 76 ticks to the end, then one falling cell per period from y 1 to
	// the belt at y -2.
	tick_loose_item_test(&world, content, 76)
	testing.expect_value(t, len(line_of(&world, ledge[0]).lanes[.Left]), 0)
	testing.expect_value(t, len(world.entities.loose_items.items), 2)
	testing.expect_value(t, world.entities.loose_items.items[0].offset, [2]i8{0, -1})
	testing.expect_value(t, world.entities.loose_items.items[1].offset, [2]i8{0, 1})
	tick_loose_item_test(&world, content, 3 * LOOSE_ITEM_FALL_TICKS + 1)
	testing.expect_value(t, len(world.entities.loose_items.items), 0)
	lower := line_of(&world, below)
	testing.expect_value(t, len(lower.lanes[.Left]), 1)
	testing.expect_value(t, len(lower.lanes[.Right]), 1)
	// The level line still holds its plate at the end.
	expect_positions(t, lane_positions(line_of(&world, level[0])^, .Left), {736})
	testing.expect(t, line_of(&world, level[0]).front_held_at_dead_end)
	testing.expect(t, !line_of(&world, ledge[0]).front_held_at_dead_end)
}
