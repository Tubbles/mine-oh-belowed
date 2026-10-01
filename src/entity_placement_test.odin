package game

import "core:testing"

// Picking up a chest with a full inventory takes what fits and spills the
// rest at the chest's cell; a long press of Mine reports the full
// inventory once.
@(test)
test_pick_up_with_a_full_inventory_spills_the_rest :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal, plate := test_item(content.items, "coal"), test_item(content.items, "iron_plate")
	chest_item := test_item(content.items, "wooden_chest")
	players := []Player{make_test_player(content.blocks, {4.5, 1, 1.5})}
	for &slot in players[0].inventory.slots {
		slot = Item_Stack{coal, 50}
	}
	players[0].inventory.slots[9] = Item_Stack{coal, 40}
	handle := place_test_entity(&world, content, "wooden_chest", {4, 1, 4})
	entity_insert(&world.entities, content, handle, {coal, 30})
	entity_insert(&world.entities, content, handle, {plate, 7})
	players[0].pitch, players[0].yaw = -30, 90
	events: Player_Events
	for _ in 0 ..< 60 {
		events += tick_player(&world, &records, content, players, 0, Input_Frame{pressed = {.Mine}}, TEST_TICK_RATE, 0)
	}
	testing.expect(t, !entity_is_alive(&world.entities, handle))
	testing.expect_value(t, events, Player_Events{.Inventory_Full})
	testing.expect_value(t, players[0].inventory.slots[9], Item_Stack{coal, 50})
	items := world.entities.loose_items.items[:]
	testing.expect_value(t, len(items), 3)
	testing.expect_value(t, items[0], Loose_Item{item = coal, count = 20, cell = {4, 1, 4}})
	testing.expect_value(t, items[1], Loose_Item{item = plate, count = 7, cell = {4, 1, 4}})
	testing.expect_value(t, items[2], Loose_Item{item = chest_item, count = 1, cell = {4, 1, 4}})
	// With room, nothing spills.
	players[0].inventory.slots[20] = EMPTY_STACK
	other := place_test_entity(&world, content, "wooden_chest", {6, 1, 6})
	testing.expect(t, pick_up_entity(&world, &records.statistics, content, &players[0], other, 0))
	testing.expect_value(t, len(world.entities.loose_items.items), 3)
	testing.expect_value(t, players[0].inventory.slots[20], Item_Stack{chest_item, 1})
}

// A machine placed over loose items lifts them onto its top; a belt takes
// them onto itself.
@(test)
test_placing_a_machine_lifts_loose_items_onto_it :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal := test_item(content.items, "coal")
	spill_stack(&world, content.blocks, {4, 1, 4}, {coal, 3})
	spill_stack(&world, content.blocks, {8, 1, 4}, {coal, 1})
	machine := test_machine(content.machines, "stone_furnace")
	placement := placement_at(&world, content, {}, machine, {4, 1, 4}, 0)
	testing.expect(t, placement.valid)
	commit_placement(&world, content.machines, placement)
	testing.expect_value(t, world.entities.loose_items.items[0].cell, World_Coordinate{4, 1 + placement.size.y, 4})
	belt := lay_belt(&world, content, {8, 1, 4}, 0)
	tick_loose_item_test(&world, &records, content, 1)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	line, _ := belt_line_of(&world.entities, belt)
	testing.expect_value(t, len(line.lanes[.Left]) + len(line.lanes[.Right]), 1)
}

// Work item 0082: a machine placed over ground cover clears it, and one
// aimed at cover stands on the ground under it.
@(test)
test_placing_a_machine_clears_ground_cover :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	tuft := test_block(content.blocks, "grass_tuft")
	machine := test_machine(content.machines, "stone_furnace")
	set_blocks(&world, tuft, {4, 1, 4}, {5, 1, 5})
	placement := placement_at(&world, content, {}, machine, {4, 1, 4}, 0)
	testing.expect(t, placement.valid)
	testing.expect(t, placement.clears_cover)
	commit_placement(&world, content.machines, placement)
	for cell in footprint_cells(placement.origin, content.machines.machines[machine].footprint, 0) {
		testing.expect_value(t, world_get_block(&world, cell), AIR_BLOCK)
	}
	// Cover under an entity is not free.
	set_blocks(&world, tuft, {4, 2, 4})
	testing.expect(t, !cell_takes_machine(&world, content.blocks, {4, 2, 4}))
	set_blocks(&world, tuft, {10, 1, 10})
	players := []Player{make_test_player(content.blocks, {16.5, 1, 16.5})}
	players[0].inventory.slots[0] = Item_Stack{test_item(content.items, "stone_furnace"), 1}
	players[0].target = Raycast_Hit{hit = true, block = {10, 1, 10}, face = .Positive_Y, adjacent = {10, 2, 10}}
	aimed := placement_for_player(&world, content, players, 0)
	testing.expect_value(t, aimed.origin.y, 1)
	testing.expect(t, aimed.valid)
	testing.expect(t, aimed.clears_cover)
}
