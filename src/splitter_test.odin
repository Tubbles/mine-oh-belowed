package game

import "core:testing"

// Splitter worlds stand on the stone floor of make_floor_world (top at y
// 1). The standard layout: a splitter facing +x at x 3 with its left half
// at z 0 and its right half at z 1, input rows of three belts at x 0 to 2
// and output rows from x 4.

MAXIMUM_FEED_TICKS :: 10_000

place_test_splitter :: proc(world: ^World, content: Simulation_Content, left_cell: World_Coordinate, direction: u8) -> Entity_Handle {
	machine := test_machine(content.machines, "splitter")
	return add_entity(&world.entities, content.machines, machine, splitter_origin(left_cell, direction), direction)
}

test_splitter :: proc(world: ^World, handle: Entity_Handle) -> ^Splitter {
	return pool_get(&world.entities.splitters, handle)
}

Splitter_Layout :: struct {
	splitter: Entity_Handle,
	// The first belt of each input and output row, NO_ENTITY for none.
	inputs:   [Splitter_Side]Entity_Handle,
	outputs:  [Splitter_Side]Entity_Handle,
}

lay_splitter_layout :: proc(world: ^World, content: Simulation_Content, inputs: bit_set[Splitter_Side], output_lengths: [Splitter_Side]int) -> Splitter_Layout {
	layout: Splitter_Layout
	for side in Splitter_Side {
		z := i32(side)
		if side in inputs {
			layout.inputs[side] = lay_belt_row(world, content, {0, 1, z}, 3, 0)[0]
		}
		if output_lengths[side] > 0 {
			layout.outputs[side] = lay_belt_row(world, content, {4, 1, z}, output_lengths[side], 0)[0]
		}
	}
	layout.splitter = place_test_splitter(world, content, {3, 1, 0}, 0)
	return layout
}

half_line :: proc(world: ^World, handle: Entity_Handle, side: Splitter_Side) -> ^Belt_Line {
	return &world.entities.belt_network.lines[test_splitter(world, handle).output_lines[side]]
}

lane_items :: proc(line: Belt_Line, lane: Belt_Lane) -> []Item_Id {
	items := make([]Item_Id, len(line.lanes[lane]), context.temp_allocator)
	for entry, index in line.lanes[lane] {
		items[index] = entry.item
	}
	return items
}

expect_items :: proc(t: ^testing.T, actual, expected: []Item_Id, location := #caller_location) {
	testing.expect_value(t, len(actual), len(expected), location)
	for value, index in expected {
		if index < len(actual) {
			testing.expect_value(t, actual[index], value, location)
		}
	}
}

repeated_items :: proc(item: Item_Id, count: int) -> []Item_Id {
	items := make([]Item_Id, count, context.temp_allocator)
	for &entry in items {
		entry = item
	}
	return items
}

// Drops the items one at a time mid block on the belt as room allows,
// ticking the belts, then ticks `extra` more.
feed_belt :: proc(world: ^World, belt: Entity_Handle, left, right: []Item_Id, extra: int) {
	queues := [Belt_Lane][]Item_Id {
		.Left  = left,
		.Right = right,
	}
	for tick := 0; tick < MAXIMUM_FEED_TICKS && (len(queues[.Left]) > 0 || len(queues[.Right]) > 0); tick += 1 {
		for lane in Belt_Lane {
			if len(queues[lane]) > 0 && belt_insert_item(&world.entities, belt, lane, queues[lane][0]) {
				queues[lane] = queues[lane][1:]
			}
		}
		tick_belts(world, 1)
	}
	tick_belts(world, extra)
}

// Five items a spacing apart at the end of a three belt input.
compress_input :: proc(world: ^World, belt: Entity_Handle, item: Item_Id) {
	line := line_of(world, belt)
	for index in 0 ..< 5 {
		append(&line.lanes[.Left], Lane_Item{item = item, position = 504 + i32(index) * BELT_ITEM_SPACING})
	}
}

@(test)
test_splitter_halves_follow_the_direction :: proc(t: ^testing.T) {
	left := World_Coordinate{5, 1, 5}
	for direction in u8(0) ..< 4 {
		right := left + belt_direction_offset(turn_right(direction))
		origin := splitter_origin(left, direction)
		testing.expect_value(t, splitter_half_cell(origin, direction, .Left), left)
		testing.expect_value(t, splitter_half_cell(origin, direction, .Right), right)
		cells := footprint_cells(origin, {1, 1, 2}, direction)
		testing.expect_value(t, len(cells), 2)
		testing.expect(t, (cells[0] == left && cells[1] == right) || (cells[0] == right && cells[1] == left))
	}
	testing.expect_value(t, next_splitter_priority(.None), Splitter_Priority.Left)
	testing.expect_value(t, next_splitter_priority(.Left), Splitter_Priority.Right)
	testing.expect_value(t, next_splitter_priority(.Right), Splitter_Priority.None)
}

@(test)
test_splitter_line_ends_and_starts :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left, .Right}, {.Left = 3, .Right = 3})
	// Two input lines, two output rows and the two halves.
	testing.expect_value(t, len(world.entities.belt_network.lines), 6)
	splitter := test_splitter(&world, layout.splitter)
	for side in Splitter_Side {
		input := line_of(&world, layout.inputs[side])
		testing.expect_value(t, input.end, Belt_Line_End{kind = .Splitter, splitter = layout.splitter, side = side})
		testing.expect_value(t, splitter.input_lines[side], pool_get(&world.entities.belts, layout.inputs[side]).line)
		half := half_line(&world, layout.splitter, side)
		testing.expect_value(t, len(half.belts), 1)
		testing.expect_value(t, half.end, Belt_Line_End{kind = .Straight, line = pool_get(&world.entities.belts, layout.outputs[side]).line})
	}
	// A belt facing into the splitter's side ends there.
	side_feeder := lay_belt(&world, content, {3, 1, -1}, 1)
	testing.expect_value(t, line_of(&world, side_feeder).end.kind, Belt_Line_End_Kind.Dead_End)
	// Walked over, not into.
	testing.expect(t, !cell_blocks_movement(&world, content.blocks, {3, 1, 1}))
}

@(test)
test_splitter_splits_one_input_evenly :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 3})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	feed_belt(&world, layout.inputs[.Left], {plate, coal, plate, coal, plate, coal, plate, coal}, {}, 300)
	// Round robin per item: plates go left, coal right.
	expect_items(t, lane_items(line_of(&world, layout.outputs[.Left])^, .Left), repeated_items(plate, 4))
	expect_items(t, lane_items(line_of(&world, layout.outputs[.Right])^, .Left), repeated_items(coal, 4))
	expect_positions(t, lane_positions(line_of(&world, layout.outputs[.Left])^, .Left), {544, 608, 672, 736})
}

@(test)
test_splitter_round_robin_is_per_lane_and_keeps_the_lane :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 3})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	feed_belt(&world, layout.inputs[.Left], repeated_items(plate, 4), repeated_items(coal, 6), 300)
	for side in Splitter_Side {
		output := line_of(&world, layout.outputs[side])
		expect_items(t, lane_items(output^, .Left), repeated_items(plate, 2))
		expect_items(t, lane_items(output^, .Right), repeated_items(coal, 3))
	}
}

@(test)
test_splitter_merges_two_inputs_alternately :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	// Only the left half has a belt in front: the right one takes nothing.
	layout := lay_splitter_layout(&world, content, {.Left, .Right}, {.Left = 4, .Right = 0})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	compress_input(&world, layout.inputs[.Left], plate)
	compress_input(&world, layout.inputs[.Right], coal)
	tick_belts(&world, 400)
	output := line_of(&world, layout.outputs[.Left])
	// Front to back: plate, coal, plate, coal, ... the left input first.
	expected := make([]Item_Id, 10, context.temp_allocator)
	for &item, index in expected {
		item = index % 2 == 0 ? coal : plate
	}
	expect_items(t, lane_items(output^, .Left), expected)
	expect_positions(t, lane_positions(output^, .Left), {416, 480, 544, 608, 672, 736, 800, 864, 928, 992})
	testing.expect_value(t, len(half_line(&world, layout.splitter, .Right).lanes[.Left]), 0)
}

@(test)
test_splitter_input_priority_drains_the_priority_input_first :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left, .Right}, {.Left = 4, .Right = 0})
	test_splitter(&world, layout.splitter).input_priority = .Right
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	compress_input(&world, layout.inputs[.Left], plate)
	compress_input(&world, layout.inputs[.Right], coal)
	tick_belts(&world, 400)
	expected := make([dynamic]Item_Id, context.temp_allocator)
	append(&expected, ..repeated_items(plate, 5))
	append(&expected, ..repeated_items(coal, 5))
	expect_items(t, lane_items(line_of(&world, layout.outputs[.Left])^, .Left), expected[:])
}

@(test)
test_splitter_priority_output_takes_everything_until_full :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 1, .Right = 3})
	test_splitter(&world, layout.splitter).output_priority = .Left
	plate := test_item(content.items, "iron_plate")
	right_half := half_line(&world, layout.splitter, .Right)
	for tick := 0; tick < 2000 && len(right_half.lanes[.Left]) == 0; tick += 1 {
		belt_insert_item(&world.entities, layout.inputs[.Left], .Left, plate)
		tick_belts(&world, 1)
	}
	// The first overflow item comes once the left belt and half are full.
	testing.expect_value(t, len(right_half.lanes[.Left]), 1)
	left_belt := line_of(&world, layout.outputs[.Left])
	left_half := half_line(&world, layout.splitter, .Left)
	expect_positions(t, lane_positions(left_belt^, .Left), {32, 96, 160, 224})
	expect_positions(t, lane_positions(left_half^, .Left), {32, 96, 160, 224})
	testing.expect_value(t, len(line_of(&world, layout.outputs[.Right]).lanes[.Left]), 0)
	feed_belt(&world, layout.inputs[.Left], repeated_items(plate, 6), {}, 300)
	testing.expect_value(t, len(left_belt.lanes[.Left]), 4)
	testing.expect_value(t, len(left_half.lanes[.Left]), 4)
	testing.expect(t, len(line_of(&world, layout.outputs[.Right]).lanes[.Left]) >= 6)
}

@(test)
test_splitter_filter_routes_the_filter_item :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 3})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	splitter := test_splitter(&world, layout.splitter)
	splitter.filter, splitter.filter_side = coal, .Right
	feed_belt(&world, layout.inputs[.Left], {plate, coal, plate, coal, coal, plate, plate}, {}, 300)
	expect_items(t, lane_items(line_of(&world, layout.outputs[.Left])^, .Left), repeated_items(plate, 4))
	expect_items(t, lane_items(line_of(&world, layout.outputs[.Right])^, .Left), repeated_items(coal, 3))
}

@(test)
test_splitter_filter_output_full_stalls_without_leaking :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 1})
	coal := test_item(content.items, "coal")
	splitter := test_splitter(&world, layout.splitter)
	splitter.filter, splitter.filter_side = coal, .Right
	feed_belt(&world, layout.inputs[.Left], repeated_items(coal, 12), {}, 600)
	testing.expect_value(t, len(line_of(&world, layout.outputs[.Right]).lanes[.Left]), 4)
	testing.expect_value(t, len(half_line(&world, layout.splitter, .Right).lanes[.Left]), 4)
	testing.expect_value(t, len(line_of(&world, layout.outputs[.Left]).lanes[.Left]), 0)
	testing.expect_value(t, len(half_line(&world, layout.splitter, .Left).lanes[.Left]), 0)
	// The rest waits a spacing behind the full half's back item.
	expect_positions(t, lane_positions(line_of(&world, layout.inputs[.Left])^, .Left), {544, 608, 672, 736})
}

@(test)
test_splitter_skips_a_blocked_or_missing_output :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 1})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	blocked := line_of(&world, layout.outputs[.Right])
	for position in ([4]i32{32, 96, 160, 224}) {
		append(&blocked.lanes[.Left], Lane_Item{item = coal, position = position})
	}
	feed_belt(&world, layout.inputs[.Left], repeated_items(plate, 12), {}, 300)
	// Every second item went right until the half filled up, the rest left.
	testing.expect_value(t, len(half_line(&world, layout.splitter, .Right).lanes[.Left]), 4)
	expect_items(t, lane_items(blocked^, .Left), repeated_items(coal, 4))
	expect_items(t, lane_items(line_of(&world, layout.outputs[.Left])^, .Left), repeated_items(plate, 8))
	// Nothing in front of the right half: everything goes left.
	world = make_floor_world(content.blocks, 32)
	layout = lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 0})
	feed_belt(&world, layout.inputs[.Left], repeated_items(plate, 6), {}, 300)
	expect_items(t, lane_items(line_of(&world, layout.outputs[.Left])^, .Left), repeated_items(plate, 6))
	testing.expect_value(t, len(half_line(&world, layout.splitter, .Right).lanes[.Left]), 0)
}

@(test)
test_splitter_stalls_when_both_outputs_are_blocked :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 1, .Right = 1})
	plate := test_item(content.items, "iron_plate")
	feed_belt(&world, layout.inputs[.Left], repeated_items(plate, 20), {}, 600)
	for side in Splitter_Side {
		expect_positions(t, lane_positions(half_line(&world, layout.splitter, side)^, .Left), {32, 96, 160, 224})
		expect_positions(t, lane_positions(line_of(&world, layout.outputs[side])^, .Left), {32, 96, 160, 224})
	}
	input := line_of(&world, layout.inputs[.Left])
	expect_positions(t, lane_positions(input^, .Left), {544, 608, 672, 736})
	tick_belts(&world, 100)
	expect_positions(t, lane_positions(input^, .Left), {544, 608, 672, 736})
}

// An item crossing the splitter is where it would be on a straight run
// of belts: the splitter counts as one block.
@(test)
test_splitter_crossing_keeps_exact_positions :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 0})
	plate := test_item(content.items, "iron_plate")
	testing.expect(t, belt_insert_item(&world.entities, layout.inputs[.Left], .Left, plate))
	straight := make_floor_world(content.blocks, 32)
	row := lay_belt_row(&straight, content, {0, 1, 0}, 7, 0)
	testing.expect(t, belt_insert_item(&straight.entities, row[0], .Left, plate))
	input, half, output := line_of(&world, layout.inputs[.Left]), half_line(&world, layout.splitter, .Left), line_of(&world, layout.outputs[.Left])
	straight_line := line_of(&straight, row[0])
	for tick in 1 ..= 210 {
		tick_belts(&world, 1)
		tick_belts(&straight, 1)
		expected := straight_line.lanes[.Left][0].position
		switch {
		case len(input.lanes[.Left]) == 1:
			testing.expect_value(t, input.lanes[.Left][0].position, expected)
		case len(half.lanes[.Left]) == 1:
			testing.expect_value(t, 3 * BELT_UNITS_PER_BLOCK + half.lanes[.Left][0].position, expected)
		case len(output.lanes[.Left]) == 1:
			testing.expect_value(t, 4 * BELT_UNITS_PER_BLOCK + output.lanes[.Left][0].position, expected)
		case:
			testing.fail_now(t, "the item was lost")
		}
		if tick == 80 {
			expect_positions(t, lane_positions(half^, .Left), {0})
		}
		if tick == 112 {
			expect_positions(t, lane_positions(output^, .Left), {0})
		}
	}
	expect_positions(t, lane_positions(output^, .Left), {736})
}

@(test)
test_splitter_lines_rebuild_after_removing_and_turning :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	layout := lay_splitter_layout(&world, content, {.Left}, {.Left = 3, .Right = 3})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	input_belts := [3]Entity_Handle{layout.inputs[.Left], entity_at(&world.entities, {1, 1, 0}), entity_at(&world.entities, {2, 1, 0})}
	for belt in input_belts {
		testing.expect(t, belt_insert_item(&world.entities, belt, .Left, plate))
	}
	testing.expect(t, belt_insert_item(&world.entities, layout.outputs[.Right], .Right, plate))
	append(&half_line(&world, layout.splitter, .Left).lanes[.Left], Lane_Item{item = coal, position = 100})
	testing.expect_value(t, len(splitter_held_stacks(&world.entities, layout.splitter)), 1)
	// Turning half way keeps the cells and the item in its cell, and the
	// input now faces the splitter's front, so it ends there.
	testing.expect(t, rotate_splitter(&world.entities, content.machines, layout.splitter))
	testing.expect_value(t, test_splitter(&world, layout.splitter).rotation, 2)
	expect_items(t, lane_items(half_line(&world, layout.splitter, .Right)^, .Left), {coal})
	testing.expect_value(t, line_of(&world, layout.inputs[.Left]).end.kind, Belt_Line_End_Kind.Dead_End)
	testing.expect(t, rotate_splitter(&world.entities, content.machines, layout.splitter))
	expect_items(t, lane_items(half_line(&world, layout.splitter, .Left)^, .Left), {coal})
	testing.expect_value(t, line_of(&world, layout.inputs[.Left]).end.kind, Belt_Line_End_Kind.Splitter)
	// Removing it drops the items inside and leaves three dead end rows
	// with their items in place.
	testing.expect(t, remove_entity(&world.entities, content.machines, layout.splitter))
	testing.expect_value(t, len(world.entities.belt_network.lines), 3)
	testing.expect_value(t, entity_at(&world.entities, {3, 1, 1}), NO_ENTITY)
	input := line_of(&world, layout.inputs[.Left])
	testing.expect_value(t, input.end.kind, Belt_Line_End_Kind.Dead_End)
	expect_positions(t, lane_positions(input^, .Left), {128, 384, 640})
	expect_positions(t, lane_positions(line_of(&world, layout.outputs[.Right])^, .Right), {128})
	// Placing it again joins the rows through it.
	splitter := place_test_splitter(&world, content, {3, 1, 0}, 0)
	testing.expect_value(t, len(world.entities.belt_network.lines), 5)
	testing.expect_value(t, line_of(&world, layout.inputs[.Left]).end, Belt_Line_End{kind = .Splitter, splitter = splitter, side = .Left})
	testing.expect_value(t, len(splitter_held_stacks(&world.entities, splitter)), 0)
	expect_positions(t, lane_positions(line_of(&world, layout.inputs[.Left])^, .Left), {128, 384, 640})
}

// A belt of four blocks into a splitter, two rows of two belts out of it,
// a burner inserter at the end of each row dropping into a chest.
lay_splitter_to_chests :: proc(world: ^World, content: Simulation_Content) -> (input: Entity_Handle, chests: [Splitter_Side]Entity_Handle) {
	input = lay_belt_row(world, content, {0, 1, 0}, 4, 0)[0]
	place_test_splitter(world, content, {4, 1, 0}, 0)
	for side in Splitter_Side {
		z := i32(side)
		lay_belt_row(world, content, {5, 1, z}, 2, 0)
		place_fuelled_inserter(world, content, {7, 1, z}, 0)
		chests[side] = place_test_entity(world, content, "wooden_chest", {8, 1, z})
	}
	return
}

@(test)
test_splitter_to_chests_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_floor_world(content.blocks, 32), make_floor_world(content.blocks, 32)}
	chests: [2][Splitter_Side]Entity_Handle
	plate, copper := test_item(content.items, "iron_plate"), test_item(content.items, "copper_plate")
	for &world, index in worlds {
		input: Entity_Handle
		input, chests[index] = lay_splitter_to_chests(&world, content)
		for tick in 0 ..< 1200 {
			belt_insert_item(&world.entities, input, Belt_Lane(tick % 2), tick % 3 == 0 ? copper : plate)
			tick_test_entities(&world, content, 1)
		}
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	testing.expect(t, first.splitters.entries[0] == second.splitters.entries[0])
	for inserter, index in first.inserters.entries {
		testing.expect(t, inserter == second.inserters.entries[index])
	}
	for chest, index in first.chests.entries {
		testing.expect(t, chest == second.chests.entries[index])
	}
	testing.expect_value(t, len(first.belt_network.lines), len(second.belt_network.lines))
	for line, line_index in first.belt_network.lines {
		for lane in Belt_Lane {
			other := second.belt_network.lines[line_index].lanes[lane][:]
			testing.expect_value(t, len(line.lanes[lane]), len(other))
			for entry, index in line.lanes[lane] {
				testing.expect_value(t, entry, other[index])
				if index > 0 {
					testing.expect(t, entry.position - line.lanes[lane][index - 1].position >= BELT_ITEM_SPACING)
				}
			}
		}
	}
	// Both chests fill.
	for side in Splitter_Side {
		filled := chest_count_of(&worlds[0], chests[0][side], plate) + chest_count_of(&worlds[0], chests[0][side], copper)
		testing.expect(t, filled >= 5)
		testing.expect_value(t, filled, chest_count_of(&worlds[1], chests[1][side], plate) + chest_count_of(&worlds[1], chests[1][side], copper))
	}
}
