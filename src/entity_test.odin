package game

import "core:slice"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
test_pool_handles_generation_free_and_reuse :: proc(t: ^testing.T) {
	pool: Entity_Pool(Chest)
	pool.entries = make([dynamic]Chest, context.temp_allocator)
	pool.free = make([dynamic]u32, context.temp_allocator)
	first := pool_add(&pool, .Chest, Chest{slot_count = 1})
	second := pool_add(&pool, .Chest, Chest{slot_count = 2})
	testing.expect_value(t, first, Entity_Handle{.Chest, 0, 1})
	testing.expect_value(t, second, Entity_Handle{.Chest, 1, 1})
	testing.expect(t, first != NO_ENTITY)
	testing.expect_value(t, pool_get(&pool, second).slot_count, 2)
	testing.expect(t, pool_remove(&pool, first))
	testing.expect(t, pool_get(&pool, first) == nil)
	testing.expect(t, !pool_remove(&pool, first))
	// The freed index is reused with the next generation; the old handle stays dead.
	third := pool_add(&pool, .Chest, Chest{slot_count = 3})
	testing.expect_value(t, third, Entity_Handle{.Chest, 0, 2})
	testing.expect(t, pool_get(&pool, first) == nil)
	testing.expect_value(t, pool_get(&pool, third).slot_count, 3)
	testing.expect_value(t, len(pool.entries), 2)
	testing.expect(t, pool_get(&pool, NO_ENTITY) == nil)
	testing.expect(t, pool_get(&pool, Entity_Handle{.Chest, 7, 1}) == nil)
}

sorted_cells :: proc(cells: []World_Coordinate) -> []World_Coordinate {
	slice.sort_by(cells, proc(first, second: World_Coordinate) -> bool {
		if first.y != second.y {
			return first.y < second.y
		}
		if first.z != second.z {
			return first.z < second.z
		}
		return first.x < second.x
	})
	return cells
}

// The rotated footprint is the box of the rotated size, whatever the rotation.
expect_footprint_box :: proc(t: ^testing.T, footprint: [3]i32, rotation: u8) {
	size := rotated_footprint_size(footprint, rotation)
	cells := sorted_cells(footprint_cells({10, 5, -3}, footprint, rotation))
	testing.expect_value(t, len(cells), int(size.x * size.y * size.z))
	index := 0
	for y in 0 ..< size.y {
		for z in 0 ..< size.z {
			for x in 0 ..< size.x {
				testing.expect_value(t, cells[index], World_Coordinate{10 + x, 5 + y, -3 + z})
				index += 1
			}
		}
	}
}

@(test)
test_footprint_rotation :: proc(t: ^testing.T) {
	square := [3]i32{2, 2, 2}
	oblong := [3]i32{3, 1, 2}
	for rotation in u8(0) ..< 4 {
		testing.expect_value(t, rotated_footprint_size(square, rotation), square)
		expect_footprint_box(t, square, rotation)
		expect_footprint_box(t, oblong, rotation)
	}
	testing.expect_value(t, rotated_footprint_size(oblong, 0), [3]i32{3, 1, 2})
	testing.expect_value(t, rotated_footprint_size(oblong, 1), [3]i32{2, 1, 3})
	testing.expect_value(t, rotated_footprint_size(oblong, 2), [3]i32{3, 1, 2})
	testing.expect_value(t, rotated_footprint_size(oblong, 3), [3]i32{2, 1, 3})
	// The unrotated corner cell (0, 0) of the 3 by 2 walks around the box.
	testing.expect_value(t, rotate_footprint_cell({0, 0}, 3, 2, 0), [2]i32{0, 0})
	testing.expect_value(t, rotate_footprint_cell({0, 0}, 3, 2, 1), [2]i32{1, 0})
	testing.expect_value(t, rotate_footprint_cell({0, 0}, 3, 2, 2), [2]i32{2, 1})
	testing.expect_value(t, rotate_footprint_cell({0, 0}, 3, 2, 3), [2]i32{0, 2})
	// Four quarter turns of the 2 by 2 are the identity on every cell.
	for cell in ([4][2]i32{{0, 0}, {1, 0}, {0, 1}, {1, 1}}) {
		testing.expect_value(t, rotate_footprint_cell(cell, 2, 2, 1), [2]i32{1 - cell.y, cell.x})
		testing.expect_value(t, rotate_footprint_cell(cell, 2, 2, 2), [2]i32{1 - cell.x, 1 - cell.y})
	}
}

@(test)
test_footprint_origin_extends_away_from_the_face :: proc(t: ^testing.T) {
	size := [3]i32{2, 2, 3}
	testing.expect_value(t, footprint_origin({4, 1, 4}, .Positive_Y, size), World_Coordinate{4, 1, 3})
	testing.expect_value(t, footprint_origin({4, 1, 4}, .Negative_X, size), World_Coordinate{3, 1, 3})
	testing.expect_value(t, footprint_origin({4, 1, 4}, .Positive_Z, size), World_Coordinate{4, 1, 4})
	testing.expect_value(t, footprint_origin({4, 1, 4}, .Negative_Y, size), World_Coordinate{4, 0, 3})
}

@(test)
test_add_and_remove_entity_updates_cells :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	furnace := test_machine(content.machines, "steel_furnace")
	handle := add_entity(&world.entities, content.machines, furnace, {2, 1, 2}, 1)
	testing.expect_value(t, handle.kind, Entity_Kind.Furnace)
	for cell in ([?]World_Coordinate{{2, 1, 2}, {3, 1, 2}, {2, 2, 3}, {3, 2, 3}}) {
		testing.expect_value(t, entity_at(&world.entities, cell), handle)
	}
	testing.expect_value(t, entity_at(&world.entities, {4, 1, 2}), NO_ENTITY)
	testing.expect_value(t, len(world.entities.frames.occupants), 8)
	testing.expect_value(t, entity_common(&world.entities, handle).size, [3]i32{2, 2, 2})
	testing.expect_value(t, len(entity_slots(&world.entities, handle)), FURNACE_SLOT_COUNT)
	// The cells stay air in the chunk, but the ray and the body stop there.
	testing.expect_value(t, world_get_block(&world, {2, 1, 2}), AIR_BLOCK)
	testing.expect(t, cell_is_solid_or_entity(&world, content.blocks, {3, 2, 3}))
	hit := raycast_blocks(&world, content.blocks, {2.5, 1.5, 0.5}, {0, 0, 1}, 5)
	testing.expect(t, hit.hit)
	testing.expect_value(t, hit.entity, handle)
	testing.expect_value(t, hit.block, World_Coordinate{2, 1, 2})
	testing.expect(t, remove_entity(&world.entities, content.machines, handle))
	testing.expect_value(t, len(world.entities.frames.occupants), 0)
	testing.expect(t, !entity_is_alive(&world.entities, handle))
}

@(test)
test_placement_validity :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 8)
	cells := footprint_cells({2, 1, 2}, {2, 2, 2}, 0)
	testing.expect(t, footprint_is_valid(&world, content.blocks, {}, cells, 1))
	// Occupied by an entity.
	chest := add_entity(&world.entities, content.machines, test_machine(content.machines, "wooden_chest"), {3, 2, 3}, 0)
	testing.expect(t, !footprint_is_valid(&world, content.blocks, {}, cells, 1))
	remove_entity(&world.entities, content.machines, chest)
	testing.expect(t, footprint_is_valid(&world, content.blocks, {}, cells, 1))
	// Occupied by a block.
	world_set_block(&world, {2, 2, 2}, test_block(content.blocks, "dirt"))
	testing.expect(t, !footprint_is_valid(&world, content.blocks, {}, cells, 1))
	world_set_block(&world, {2, 2, 2}, AIR_BLOCK)
	// Unsupported: the floor ends at x 8, so a footprint over x 7 and 8 hangs.
	edge := footprint_cells({7, 1, 2}, {2, 2, 2}, 0)
	testing.expect(t, !footprint_is_valid(&world, content.blocks, {}, edge, 1))
	// A player's body in the way.
	players := []Player{make_test_player(content.blocks, {3.5, 1, 3.5})}
	testing.expect(t, !footprint_is_valid(&world, content.blocks, players, cells, 1))
	players[0].position = {5.5, 1, 5.5}
	testing.expect(t, footprint_is_valid(&world, content.blocks, players, cells, 1))
	// Outside the loaded chunks.
	far := footprint_cells({40, 1, 2}, {1, 1, 1}, 0)
	testing.expect(t, !footprint_is_valid(&world, content.blocks, {}, far, 1))
}

// Work item 0212: a furnace saved at the old 2 by 2 by 2 keeps those
// cells after the record grew, until it is picked up.
@(test)
test_a_machine_saved_at_an_older_size_keeps_its_cells :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	furnace := test_machine(content.machines, "stone_furnace")
	handle := add_entity(&world.entities, content.machines, furnace, {4, 1, 4}, 0)
	common := entity_common(&world.entities, handle)
	vacate_entity_cells(&world.entities, content.machines, common^)
	common.size = {2, 2, 2}
	occupy_entity_cells(&world.entities, content.machines, common^)
	testing.expect(t, entity_keeps_saved_size(common^, content.machines.machines[furnace]))
	saved := footprint_cells({4, 1, 4}, {2, 2, 2}, 0)
	for cell in saved {
		testing.expect_value(t, entity_at(&world.entities, cell), handle)
	}
	testing.expect_value(t, len(world.entities.frames.occupants), 8)
	testing.expect_value(t, entity_at(&world.entities, {6, 1, 4}), NO_ENTITY)
	testing.expect_value(t, entity_at(&world.entities, {4, 1, 6}), NO_ENTITY)
	vacate_entity_cells(&world.entities, content.machines, common^)
	for cell in saved {
		testing.expect_value(t, entity_at(&world.entities, cell), NO_ENTITY)
	}
}

// A pod of an older size is upgraded instead (upgrade_resized_pods), and
// a machine at its record's size keeps nothing.
@(test)
test_entity_keeps_saved_size_spares_the_pod :: proc(t: ^testing.T) {
	machines := make_test_machines()
	pod := machines.machines[test_machine(machines, "pod")]
	furnace := machines.machines[test_machine(machines, "stone_furnace")]
	testing.expect(t, !entity_keeps_saved_size(Entity_Common{size = pod.footprint + {1, 0, 1}}, pod))
	testing.expect(t, !entity_keeps_saved_size(Entity_Common{size = furnace.footprint}, furnace))
	testing.expect(t, entity_keeps_saved_size(Entity_Common{size = {2, 2, 2}}, furnace))
}

@(test)
test_player_places_rotates_and_picks_up_a_machine :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	players := []Player{make_test_player(content.blocks, {0.5, 1, 0.5})}
	player := &players[0]
	furnace_item := test_item(content.items, "steel_furnace")
	player.inventory.slots[0] = Item_Stack{furnace_item, 2}
	player.target = Raycast_Hit{hit = true, block = {4, 0, 4}, face = .Positive_Y, adjacent = {4, 1, 4}}
	place_with_player(&world, &records.statistics, content, players, 0, {.Rotate_Building})
	testing.expect_value(t, player.placement_rotation, 1)
	testing.expect_value(t, len(world.entities.frames.occupants), 0)
	place_with_player(&world, &records.statistics, content, players, 0, {.Place})
	handle := entity_at(&world.entities, {4, 1, 4})
	testing.expect_value(t, handle.kind, Entity_Kind.Furnace)
	testing.expect_value(t, entity_common(&world.entities, handle).rotation, 1)
	testing.expect_value(t, player.inventory.slots[0].count, 1)
	// The same spot is now occupied: nothing more is placed.
	place_with_player(&world, &records.statistics, content, players, 0, {.Place})
	testing.expect_value(t, player.inventory.slots[0].count, 1)
	// Pick up returns the contents first, then the machine.
	furnace := pool_get(&world.entities.furnaces, handle)
	furnace.slots[FURNACE_OUTPUT_SLOT] = Item_Stack{test_item(content.items, "iron_plate"), 7}
	testing.expect(t, pick_up_entity(&world, &records.statistics, content, player, handle, 0))
	testing.expect(t, !entity_is_alive(&world.entities, handle))
	testing.expect_value(t, len(world.entities.frames.occupants), 0)
	testing.expect_value(t, player.inventory.slots[0], Item_Stack{furnace_item, 2})
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{test_item(content.items, "iron_plate"), 7})
}

// Work item 0233: X (Open_Inventory and Interact, routed as the frame
// routes it) opens the aimed furnace and turns a power switch in its
// place without opening its panel or jumping; A at the switch jumps and
// turns nothing; X looking away keeps Open_Inventory for the inventory.
@(test)
test_x_turns_a_switch_and_opens_a_furnace_and_a_jumps_at_a_switch :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "steel_furnace"), {4, 1, 4}, 0)
	players := []Player{make_test_player(content.blocks, {4.5, 1, 1.5})}
	players[0].pitch, players[0].yaw = -30, 90
	routed := proc(t: ^testing.T, world: ^World, content: Simulation_Content, player: Player, button: sdl.GamepadButton) -> Input_Frame {
		takes_interact, has_panel := aimed_target_calls_for(&world.entities, content.machines, player.target.entity, {})
		return route_open_inventory_press(shipped_gamepad_press(t, button), false, has_panel, takes_interact)
	}
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].target.entity, handle)
	events := tick_player(&world, &records, content, players, 0, routed(t, &world, content, players[0], .WEST), TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{.Open_Machine})
	testing.expect_value(t, players[0].open_machine, handle)
	// A switch in the furnace's place: X turns it.
	testing.expect(t, remove_entity(&world.entities, content.machines, handle))
	switch_handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "power_switch"), {4, 1, 4}, 0)
	players[0] = make_test_player(content.blocks, {4.5, 1, 1.5})
	players[0].pitch, players[0].yaw = -30, 90
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].target.entity, switch_handle)
	was_on := pool_get(&world.entities.poles, switch_handle).on
	players[0].on_ground = true
	events = tick_player(&world, &records, content, players, 0, routed(t, &world, content, players[0], .WEST), TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{.Toggled_Switch})
	testing.expect_value(t, pool_get(&world.entities.poles, switch_handle).on, !was_on)
	testing.expect_value(t, players[0].open_machine, NO_ENTITY)
	testing.expect(t, players[0].velocity.y <= 0)
	// A at the switch jumps and turns nothing.
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	players[0].on_ground = true
	events = tick_player(&world, &records, content, players, 0, routed(t, &world, content, players[0], .SOUTH), TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{})
	testing.expect_value(t, pool_get(&world.entities.poles, switch_handle).on, !was_on)
	testing.expect(t, players[0].velocity.y > 0)
	// Looking away, X keeps Open_Inventory and the tick does nothing.
	players[0] = make_test_player(content.blocks, {4.5, 1, 1.5})
	players[0].pitch = 60
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	x := routed(t, &world, content, players[0], .WEST)
	testing.expect(t, .Open_Inventory in x.just_pressed)
	events = tick_player(&world, &records, content, players, 0, x, TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{})
}

// Work item 0194: the aimed entity is the field's frame cell when one is
// hit, else the block world's target; only an entity with a panel turns
// the inventory binding into an open.
@(test)
test_aims_at_panel_reads_the_target_the_hud_shows :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	furnace := add_entity(&world.entities, content.machines, test_machine(content.machines, "steel_furnace"), {4, 1, 4}, 0)
	belt := add_entity(&world.entities, content.machines, test_machine(content.machines, "belt"), {6, 1, 4}, 0)
	testing.expect(t, aims_at_panel(&world.entities, content.machines, furnace, {}))
	testing.expect(t, !aims_at_panel(&world.entities, content.machines, belt, {}))
	testing.expect(t, !aims_at_panel(&world.entities, content.machines, NO_ENTITY, {}))
	on_frame := Frame_Raycast_Hit{hit = true, occupant = {handle = entity_occupant_handle(furnace)}}
	testing.expect_value(t, aimed_entity(NO_ENTITY, on_frame), furnace)
	testing.expect(t, aims_at_panel(&world.entities, content.machines, NO_ENTITY, on_frame))
	on_belt := Frame_Raycast_Hit{hit = true, occupant = {handle = entity_occupant_handle(belt)}}
	testing.expect(t, !aims_at_panel(&world.entities, content.machines, furnace, on_belt))
}

// Work item 0196: a crafting station in the foundations' pool has a
// panel; a foundation, the pod and a belt pole have none.
@(test)
test_a_crafting_station_has_a_panel :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	table := add_entity(&world.entities, content.machines, test_machine(content.machines, "stone_cutting_table"), {2, 1, 2}, 0)
	foundation := add_entity(&world.entities, content.machines, test_machine(content.machines, "wooden_foundation"), {6, 1, 2}, 0)
	pod := add_entity(&world.entities, content.machines, find_machine_of_kind(content.machines, .Pod), {10, 1, 10}, 0)
	pole := add_entity(&world.entities, content.machines, test_machine(content.machines, "belt_pole"), {2, 1, 6}, 0)
	testing.expect_value(t, table.kind, Entity_Kind.Foundation)
	testing.expect(t, entity_has_panel(&world.entities, content.machines, table))
	testing.expect(t, !entity_has_panel(&world.entities, content.machines, foundation))
	testing.expect(t, !entity_has_panel(&world.entities, content.machines, pod))
	testing.expect(t, !entity_has_panel(&world.entities, content.machines, pole))
	// The pod's bench and oxygen generator have one, its hatch none (0198).
	bench := add_entity(&world.entities, content.machines, test_machine(content.machines, "crafting_bench"), {2, 1, 20}, 0)
	generator := add_entity(&world.entities, content.machines, test_machine(content.machines, "oxygen_generator"), {4, 1, 20}, 0)
	hatch := add_entity(&world.entities, content.machines, test_machine(content.machines, "pod_hatch"), {6, 1, 20}, 0)
	testing.expect(t, entity_has_panel(&world.entities, content.machines, bench))
	testing.expect(t, entity_has_panel(&world.entities, content.machines, generator))
	testing.expect(t, !entity_has_panel(&world.entities, content.machines, hatch))
}
