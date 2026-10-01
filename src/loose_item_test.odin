package game

import "core:testing"

// Loose item worlds stand on the stone floor of make_floor_world (top at
// y 1), whose test chunks span y -32 to 31.

// Test worlds keep their lists in the temp allocator.
use_temporary_loose_items :: proc(world: ^World) {
	world.entities.loose_items.items = make([dynamic]Loose_Item, context.temp_allocator)
}

make_loose_item_test_world :: proc(content: Simulation_Content, floor_end_x: i32 = 32) -> World {
	world := make_floor_world(content.blocks, floor_end_x)
	use_temporary_loose_items(&world)
	return world
}

tick_loose_item_test :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		tick_entities_on_world(world, records, content, TEST_TICK_RATE)
	}
}

@(test)
test_loose_stacks_of_one_item_in_one_cell_merge :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal, stone := test_item(content.items, "coal"), test_item(content.items, "stone")
	stack_size := item_stack_size(content.items, coal)
	spill_stack(&world, content.blocks, {2, 1, 2}, {coal, stack_size - 5})
	spill_stack(&world, content.blocks, {2, 1, 2}, {stone, 3})
	spill_stack(&world, content.blocks, {2, 1, 2}, {coal, 8})
	spill_stack(&world, content.blocks, {3, 1, 2}, {coal, 4})
	tick_loose_item_test(&world, &records, content, 1)
	items := world.entities.loose_items.items[:]
	// The first coal fills to the stack size, the rest of the second stays
	// beside it; another cell and another item stay apart.
	testing.expect_value(t, len(items), 4)
	testing.expect_value(t, items[0].count, stack_size)
	testing.expect_value(t, items[1], Loose_Item{item = stone, count = 3, cell = {2, 1, 2}, age_ticks = 1})
	testing.expect_value(t, items[2].count, 3)
	testing.expect_value(t, items[3].cell, World_Coordinate{3, 1, 2})
	// A stack emptied by a merge leaves the list.
	spill_stack(&world, content.blocks, {3, 1, 2}, {coal, 2})
	tick_loose_item_test(&world, &records, content, 1)
	testing.expect_value(t, len(world.entities.loose_items.items), 4)
	testing.expect_value(t, world.entities.loose_items.items[3].count, 6)
}

@(test)
test_loose_items_fall_to_the_ground_one_cell_per_fall_period :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	spill_stack(&world, content.blocks, {2, 5, 2}, {test_item(content.items, "coal"), 1})
	tick_loose_item_test(&world, &records, content, LOOSE_ITEM_FALL_TICKS - 1)
	loose := &world.entities.loose_items.items[0]
	testing.expect_value(t, loose.cell, World_Coordinate{2, 5, 2})
	testing.expect_value(t, loose.fall_ticks, LOOSE_ITEM_FALL_TICKS - 1)
	tick_loose_item_test(&world, &records, content, 1)
	testing.expect_value(t, loose.cell, World_Coordinate{2, 4, 2})
	testing.expect_value(t, loose.fall_ticks, 0)
	// Down to the air cell on the floor (y 1), where it rests.
	tick_loose_item_test(&world, &records, content, 3 * LOOSE_ITEM_FALL_TICKS + 20)
	testing.expect_value(t, loose.cell, World_Coordinate{2, 1, 2})
	testing.expect_value(t, loose.fall_ticks, 0)
}

@(test)
test_water_and_unloaded_chunks_hold_loose_items :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content, 0)
	records: Game_Records
	water := test_block(content.blocks, "water")
	set_blocks(&world, water, {5, 1, 5}, {5, 2, 5})
	spill_stack(&world, content.blocks, {5, 6, 5}, {test_item(content.items, "coal"), 1})
	// No floor at x 5: the stack in open air falls to the bottom of the
	// loaded chunks and stops above the unloaded one.
	spill_stack(&world, content.blocks, {8, -28, 8}, {test_item(content.items, "coal"), 1})
	tick_loose_item_test(&world, &records, content, 10 * LOOSE_ITEM_FALL_TICKS)
	items := world.entities.loose_items.items[:]
	testing.expect_value(t, items[0].cell, World_Coordinate{5, 3, 5})
	testing.expect_value(t, items[1].cell, World_Coordinate{8, -32, 8})
	// A stack inside water stays where it is.
	spill_stack(&world, content.blocks, {5, 2, 5}, {test_item(content.items, "stone"), 1})
	tick_loose_item_test(&world, &records, content, 2 * LOOSE_ITEM_FALL_TICKS)
	testing.expect_value(t, world.entities.loose_items.items[2].cell, World_Coordinate{5, 2, 5})
}

@(test)
test_loose_items_despawn_after_the_configured_time :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	testing.expect_value(t, loose_item_despawn_ticks(15, 60), 54_000)
	testing.expect_value(t, loose_item_despawn_ticks(0, 60), 0)
	world.entities.loose_items.despawn_ticks = 10
	coal := test_item(content.items, "coal")
	spill_stack(&world, content.blocks, {2, 1, 2}, {coal, 1})
	tick_loose_item_test(&world, &records, content, 5)
	// A fresh stack merged in keeps the merged stack for its full time.
	spill_stack(&world, content.blocks, {2, 1, 2}, {coal, 1})
	tick_loose_item_test(&world, &records, content, 5)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	testing.expect_value(t, world.entities.loose_items.items[0].count, 2)
	tick_loose_item_test(&world, &records, content, 4)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	tick_loose_item_test(&world, &records, content, 1)
	testing.expect_value(t, len(world.entities.loose_items.items), 0)
	// Zero keeps them forever.
	world.entities.loose_items.despawn_ticks = 0
	spill_stack(&world, content.blocks, {2, 1, 2}, {coal, 1})
	tick_loose_item_test(&world, &records, content, 100)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
}

@(test)
test_spilling_into_a_solid_cell_or_a_machine_goes_up :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal := test_item(content.items, "coal")
	spill_stack(&world, content.blocks, {1, 0, 1}, {coal, 1})
	place_test_entity(&world, content, "wooden_chest", {3, 1, 3})
	spill_stack(&world, content.blocks, {3, 1, 3}, {coal, 1})
	spill_stack(&world, content.blocks, {4, 1, 4}, EMPTY_STACK)
	items := world.entities.loose_items.items[:]
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[0].cell, World_Coordinate{1, 1, 1})
	testing.expect_value(t, items[1].cell, World_Coordinate{3, 2, 3})
	// On the chest it rests; a block put into its cell pushes it up.
	tick_loose_item_test(&world, &records, content, 2 * LOOSE_ITEM_FALL_TICKS)
	testing.expect_value(t, world.entities.loose_items.items[1].cell, World_Coordinate{3, 2, 3})
	set_blocks(&world, test_block(content.blocks, "stone"), {1, 1, 1})
	tick_loose_item_test(&world, &records, content, 1)
	testing.expect_value(t, world.entities.loose_items.items[0].cell, World_Coordinate{1, 2, 1})
}

@(test)
test_walking_over_loose_items_picks_them_up_when_they_fit :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal, stone := test_item(content.items, "coal"), test_item(content.items, "stone")
	players := []Player{make_test_player(content.blocks, {0.5, 1, 0.5})}
	players[0].inventory.slots[3] = Item_Stack{coal, 1}
	spill_stack(&world, content.blocks, {3, 1, 0}, {coal, 5})
	spill_stack(&world, content.blocks, {6, 1, 0}, {stone, 2})
	// Walking along +x (yaw 0) over both cells.
	for _ in 0 ..< 120 {
		tick_player(&world, &records, content, players, 0, WALK_FORWARD, TEST_TICK_RATE, 0)
	}
	testing.expect(t, players[0].position.x > 7)
	testing.expect_value(t, len(world.entities.loose_items.items), 0)
	// The hotbar slot already holding coal takes it; the stone goes to
	// the first slot of the main grid.
	testing.expect_value(t, players[0].inventory.slots[3], Item_Stack{coal, 6})
	testing.expect_value(t, players[0].inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{stone, 2})
}

@(test)
test_a_full_inventory_leaves_loose_items_lying :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal, stone := test_item(content.items, "coal"), test_item(content.items, "stone")
	players := []Player{make_test_player(content.blocks, {2.5, 1, 2.5})}
	for &slot in players[0].inventory.slots {
		slot = Item_Stack{coal, item_stack_size(content.items, coal)}
	}
	players[0].inventory.slots[7] = Item_Stack{coal, item_stack_size(content.items, coal) - 2}
	spill_stack(&world, content.blocks, {2, 1, 2}, {stone, 1})
	spill_stack(&world, content.blocks, {2, 1, 2}, {coal, 5})
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	// Two coal fit, the rest and the stone stay.
	testing.expect_value(t, players[0].inventory.slots[7].count, item_stack_size(content.items, coal))
	items := world.entities.loose_items.items[:]
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[0].item, stone)
	testing.expect_value(t, items[1], Loose_Item{item = coal, count = 3, cell = {2, 1, 2}})
}

@(test)
test_drop_puts_the_held_or_focused_stack_in_front_of_the_player :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal, stone := test_item(content.items, "coal"), test_item(content.items, "stone")
	player := make_test_player(content.blocks, {2.5, 1, 2.5})
	player.yaw = 90
	player.held = Held_Stack{stack = {coal, 4}, origin_slot = 2}
	player.inventory.slots[9] = Item_Stack{stone, 7}
	testing.expect(t, drop_player_stack(&world, &records.statistics, content.blocks, &player, 0, 9))
	testing.expect_value(t, player.held, EMPTY_HELD_STACK)
	testing.expect_value(t, player.inventory.slots[9], Item_Stack{stone, 7})
	testing.expect(t, drop_player_stack(&world, &records.statistics, content.blocks, &player, 0, 9))
	testing.expect_value(t, player.inventory.slots[9], EMPTY_STACK)
	testing.expect(t, !drop_player_stack(&world, &records.statistics, content.blocks, &player, 0, 9))
	testing.expect(t, !drop_player_stack(&world, &records.statistics, content.blocks, &player, 0, -1))
	items := world.entities.loose_items.items[:]
	testing.expect_value(t, len(items), 2)
	// Yaw 90 faces +z: the cell in front at feet height.
	testing.expect_value(t, items[0], Loose_Item{item = coal, count = 4, cell = {2, 1, 3}, dropping_player = dropping_player_value(0)})
	testing.expect_value(t, items[1], Loose_Item{item = stone, count = 7, cell = {2, 1, 3}, dropping_player = dropping_player_value(0)})
	testing.expect_value(t, records.statistics.world_actions, 2)
}

@(test)
test_drop_stack_drops_the_selected_hotbar_stack_in_the_world :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal, stone := test_item(content.items, "coal"), test_item(content.items, "stone")
	players := []Player{make_test_player(content.blocks, {2.5, 1, 2.5})}
	players[0].yaw = 90
	players[0].selected_hotbar_slot = 3
	players[0].inventory.slots[3] = Item_Stack{coal, 6}
	players[0].inventory.slots[4] = Item_Stack{stone, 2}
	// With a slot select in the same tick, the drop takes the slot
	// selected until then.
	tick_player(&world, &records, content, players, 0, {just_pressed = {.Drop_Stack, .Hotbar_Slot_5}}, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].inventory.slots[3], EMPTY_STACK)
	testing.expect_value(t, players[0].inventory.slots[4], Item_Stack{stone, 2})
	testing.expect_value(t, players[0].selected_hotbar_slot, 4)
	items := world.entities.loose_items.items[:]
	testing.expect_value(t, len(items), 1)
	testing.expect_value(t, items[0], Loose_Item{item = coal, count = 6, cell = {2, 1, 3}, dropping_player = dropping_player_value(0)})
	// An empty selected slot drops nothing.
	players[0].selected_hotbar_slot = 3
	tick_player(&world, &records, content, players, 0, {just_pressed = {.Drop_Stack}}, TEST_TICK_RATE, 0)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
}

// One block (one metre) from the position to the cell centre on x and z,
// in the feet's layer or the one below.
@(test)
test_pickup_range_is_one_block :: proc(t: ^testing.T) {
	feet := World_Coordinate{0, 1, 0}
	centred := [3]f32{0.5, 1, 0.5}
	testing.expect(t, loose_item_in_pickup_range({0, 1, 0}, feet, centred))
	testing.expect(t, loose_item_in_pickup_range({1, 1, 0}, feet, centred))
	testing.expect(t, loose_item_in_pickup_range({0, 0, -1}, feet, centred))
	testing.expect(t, !loose_item_in_pickup_range({1, 1, 1}, feet, centred))
	testing.expect(t, !loose_item_in_pickup_range({0, 2, 0}, feet, centred))
	testing.expect(t, !loose_item_in_pickup_range({0, -1, 0}, feet, centred))
	// 1.5 blocks away from a position on the cell's edge.
	testing.expect(t, !loose_item_in_pickup_range({1, 1, 0}, feet, {0, 1, 0.5}))
}

@(test)
test_standing_next_to_loose_items_picks_them_up :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal := test_item(content.items, "coal")
	players := []Player{make_test_player(content.blocks, {2.5, 1, 2.5})}
	spill_stack(&world, content.blocks, {3, 1, 2}, {coal, 2})
	spill_stack(&world, content.blocks, {4, 1, 2}, {coal, 3})
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, inventory_count(players[0].inventory, coal), 2)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	testing.expect_value(t, world.entities.loose_items.items[0].cell, World_Coordinate{4, 1, 2})
}

// The player who dropped a stack picks it up again only after having been
// out of its pickup range once; another player takes it at once.
@(test)
test_a_dropped_stack_waits_until_its_player_leaves_the_range :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_loose_item_test_world(content)
	records: Game_Records
	coal := test_item(content.items, "coal")
	players := []Player{make_test_player(content.blocks, {2.5, 1, 2.5}), make_test_player(content.blocks, {8.5, 1, 8.5})}
	players[0].yaw = 90
	players[0].inventory.slots[0] = Item_Stack{coal, 4}
	tick_player(&world, &records, content, players, 0, {just_pressed = {.Drop_Stack}}, TEST_TICK_RATE, 0)
	// Standing still next to the drop never takes it back.
	for _ in 0 ..< 200 {
		tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
		tick_entities_on_world(&world, &records, content, TEST_TICK_RATE)
	}
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	// Two blocks away and back.
	players[0].position = {2.5, 1, 0.5}
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	testing.expect_value(t, world.entities.loose_items.items[0].dropping_player, NO_DROPPING_PLAYER)
	players[0].position = {2.5, 1, 2.5}
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, len(world.entities.loose_items.items), 0)
	testing.expect_value(t, inventory_count(players[0].inventory, coal), 4)
	// The second player is not held back by the first one's drop.
	players[0].inventory.slots[0] = Item_Stack{coal, 4}
	tick_player(&world, &records, content, players, 0, {just_pressed = {.Drop_Stack}}, TEST_TICK_RATE, 0)
	players[1].position = players[0].position
	tick_player(&world, &records, content, players, 1, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, inventory_count(players[1].inventory, coal), 4)
}

@(test)
test_a_merge_keeps_the_dropper_of_the_stack_merged_in :: proc(t: ^testing.T) {
	first, second := dropping_player_value(0), dropping_player_value(1)
	testing.expect_value(t, merged_dropping_player(NO_DROPPING_PLAYER, first), first)
	testing.expect_value(t, merged_dropping_player(first, second), second)
	testing.expect_value(t, merged_dropping_player(first, NO_DROPPING_PLAYER), first)
	testing.expect_value(t, merged_dropping_player(NO_DROPPING_PLAYER, NO_DROPPING_PLAYER), NO_DROPPING_PLAYER)
	testing.expect(t, first != NO_DROPPING_PLAYER)
}
