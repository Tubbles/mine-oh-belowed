package game

import "core:testing"

@(test)
test_belt_drag_path_plans_turns_and_ramps :: proc(t: ^testing.T) {
	cells := []World_Coordinate{{0, 1, 0}, {1, 1, 0}, {1, 1, 1}, {1, 2, 2}, {2, 2, 2}, {3, 1, 2}}
	plan := plan_belt_run(cells, 3)
	expected := []Planned_Belt {
		{{0, 1, 0}, 0, .Flat},
		// Turns towards +z.
		{{1, 1, 0}, 1, .Flat},
		// The ground steps up: the belt below the step becomes a ramp up.
		{{1, 1, 1}, 1, .Ramp_Up},
		{{1, 2, 2}, 0, .Flat},
		{{2, 2, 2}, 0, .Flat},
		// The ground steps down: the new belt is a ramp down.
		{{3, 1, 2}, 0, .Ramp_Down},
	}
	testing.expect_value(t, len(plan), len(expected))
	for entry, index in expected {
		testing.expect_value(t, plan[index], entry)
	}
	testing.expect_value(t, plan_belt_run(cells[:1], 3)[0], Planned_Belt{{0, 1, 0}, 3, .Flat})
}

@(test)
test_belt_drag_columns_go_straight_before_turning :: proc(t: ^testing.T) {
	x_first := belt_drag_columns({0, 0}, {2, -1}, true)
	testing.expect_value(t, len(x_first), 3)
	testing.expect_value(t, x_first[0], [2]i32{1, 0})
	testing.expect_value(t, x_first[1], [2]i32{2, 0})
	testing.expect_value(t, x_first[2], [2]i32{2, -1})
	z_first := belt_drag_columns({0, 0}, {2, -1}, false)
	testing.expect_value(t, z_first[0], [2]i32{0, -1})
	testing.expect_value(t, z_first[2], [2]i32{2, -1})
	testing.expect_value(t, len(belt_drag_columns({4, 4}, {4, 4}, true)), 0)
}

@(test)
test_yaw_direction_and_steps :: proc(t: ^testing.T) {
	testing.expect_value(t, yaw_direction(0), 0)
	testing.expect_value(t, yaw_direction(44), 0)
	testing.expect_value(t, yaw_direction(90), 1)
	testing.expect_value(t, yaw_direction(-90), 3)
	testing.expect_value(t, yaw_direction(-30), 0)
	testing.expect_value(t, yaw_direction(530), 2)
	direction, ok := horizontal_step_direction({0, 0, 0}, {0, 1, -1})
	testing.expect(t, ok)
	testing.expect_value(t, direction, 3)
	_, ok = horizontal_step_direction({0, 0, 0}, {1, 0, 1})
	testing.expect(t, !ok)
}

give_test_items :: proc(player: ^Player, items: Item_Registry, id: string, count: int) {
	inventory_add(player.inventory, items, test_item(items, id), count)
}

// Dragging over the floor: straight, up a one block step, then a turn
// that drops back down. The belts join into one line.
@(test)
test_belt_drag_places_a_run_in_the_world :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	set_blocks(&world, test_block(content.blocks, "stone"), {3, 1, 0})
	players := []Player{make_test_player(content.blocks, {-3.5, 1, 0.5})}
	player := &players[0]
	give_test_items(player, content.items, "belt", 10)
	give_test_items(player, content.items, "belt_ramp", 2)
	// Facing +x, rotation 0: the first belt points away from the player.
	player.target = Raycast_Hit{hit = true, block = {0, 0, 0}, face = .Positive_Y, adjacent = {0, 1, 0}}
	place_with_player(&world, content, players, 0, {.Place}, {.Place})
	testing.expect(t, player.belt_drag.active)
	for column in ([?][2]i32{{2, 0}, {3, 1}}) {
		player.target = Raycast_Hit{hit = true, block = {column.x, 0, column.y}, face = .Positive_Y, adjacent = {column.x, 1, column.y}}
		place_with_player(&world, content, players, 0, {}, {.Place})
	}
	expected := []Planned_Belt {
		{{0, 1, 0}, 0, .Flat},
		{{1, 1, 0}, 0, .Flat},
		{{2, 1, 0}, 0, .Ramp_Up},
		{{3, 2, 0}, 1, .Flat},
		{{3, 1, 1}, 1, .Ramp_Down},
	}
	for entry in expected {
		belt := belt_at(&world.entities, entry.cell)
		testing.expectf(t, belt != nil, "no belt at %v", entry.cell)
		if belt != nil {
			testing.expect_value(t, Planned_Belt{belt.origin, belt.rotation, belt.shape}, entry)
		}
	}
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	testing.expect_value(t, len(world.entities.belt_network.lines[0].belts), 5)
	// Four flat belts taken, one given back for the ramp up, two ramps used.
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "belt")), 7)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "belt_ramp")), 0)
	// Releasing Place ends the drag.
	place_with_player(&world, content, players, 0, {}, {})
	testing.expect(t, !player.belt_drag.active)
}

@(test)
test_belt_placed_at_a_run_end_continues_it :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	lay_belt(&world, content, {0, 1, 0}, 1)
	// The player faces +x, but the new belt continues the run towards +z.
	plan := single_belt_plan(&world, content.blocks, {0, 1, 1}, .Flat, 0, 0)
	testing.expect_value(t, plan.direction, 1)
	plan = single_belt_plan(&world, content.blocks, {5, 1, 5}, .Flat, 0, 1)
	testing.expect_value(t, plan.direction, 1)
	// A lift on a lift continues the column; rotation 4 and up start a down lift.
	lay_belt(&world, content, {4, 1, 0}, 2, .Lift_Up)
	plan = single_belt_plan(&world, content.blocks, {4, 2, 0}, .Lift, 0, 5)
	testing.expect_value(t, plan, Planned_Belt{{4, 2, 0}, 2, .Lift_Up})
	testing.expect(t, belt_cell_supported(&world, content.blocks, {4, 2, 0}, .Lift_Up))
	testing.expect(t, !belt_cell_supported(&world, content.blocks, {4, 2, 0}, .Flat))
	plan = single_belt_plan(&world, content.blocks, {6, 1, 0}, .Lift, 0, 5)
	testing.expect_value(t, plan, Planned_Belt{{6, 1, 0}, 1, .Lift_Down})
	// A ramp against a block behind it descends away from it.
	set_blocks(&world, test_block(content.blocks, "stone"), {7, 1, 3})
	testing.expect_value(t, single_ramp_shape(&world, content.blocks, {8, 1, 3}, 0), Belt_Shape.Ramp_Down)
	testing.expect_value(t, single_ramp_shape(&world, content.blocks, {6, 1, 3}, 0), Belt_Shape.Ramp_Up)
}

@(test)
test_belt_pick_up_returns_its_items :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {0, 1, 0}, 3, 0)
	plate := test_item(content.items, "iron_plate")
	belt_insert_item(&world.entities, belts[1], .Left, plate)
	belt_insert_item(&world.entities, belts[1], .Right, plate)
	belt_insert_item(&world.entities, belts[2], .Left, plate)
	player := make_test_player(content.blocks, {-3.5, 1, 0.5})
	testing.expect(t, pick_up_entity(&world, content, &player, belts[1]))
	testing.expect_value(t, inventory_count(player.inventory, plate), 2)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "belt")), 1)
	testing.expect_value(t, len(world.entities.belt_network.lines), 2)
	expect_positions(t, lane_positions(line_of(&world, belts[2])^, .Left), {128})
}

@(test)
test_rotate_and_debug_drop_on_a_targeted_belt :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {0, 1, 0}, 2, 0)
	players := []Player{make_test_player(content.blocks, {1.5, 1, 2.5})}
	players[0].target = Raycast_Hit{hit = true, block = {1, 1, 0}, face = .Positive_Z, adjacent = {1, 1, 1}, entity = belts[1]}
	// The player stands on the +z side of an eastbound belt: its right lane.
	testing.expect(t, debug_drop_item_on_belt(&world, content, players[0]))
	line := line_of(&world, belts[1])
	expect_positions(t, lane_positions(line^, .Right), {256 + 128})
	// Rotate with an empty hand turns the belt; its item stays on it.
	place_with_player(&world, content, players, 0, {.Rotate_Building})
	testing.expect_value(t, pool_get(&world.entities.belts, belts[1]).rotation, 1)
	testing.expect_value(t, len(line_of(&world, belts[1]).lanes[.Right]), 1)
	testing.expect_value(t, len(line_of(&world, belts[1]).lanes[.Left]), 0)
	// Interact on a belt does not open a panel.
	testing.expect(t, !entity_has_panel(&world.entities, belts[1]))
}
