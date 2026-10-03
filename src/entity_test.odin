package game

import "core:slice"
import "core:testing"

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
	furnace := test_machine(content.machines, "stone_furnace")
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

@(test)
test_player_places_rotates_and_picks_up_a_machine :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	players := []Player{make_test_player(content.blocks, {0.5, 1, 0.5})}
	player := &players[0]
	furnace_item := test_item(content.items, "stone_furnace")
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

@(test)
test_interact_opens_an_entity_instead_of_jumping :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "wooden_chest"), {4, 1, 4}, 0)
	players := []Player{make_test_player(content.blocks, {4.5, 1, 1.5})}
	players[0].pitch, players[0].yaw = -30, 90
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].target.entity, handle)
	players[0].on_ground = true
	press := Input_Frame{pressed = {.Jump, .Interact}, just_pressed = {.Jump, .Interact}}
	events := tick_player(&world, &records, content, players, 0, press, TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{.Open_Machine})
	testing.expect_value(t, players[0].open_machine, handle)
	testing.expect(t, players[0].velocity.y <= 0)
	// Looking away, the same press jumps.
	players[0].pitch = 60
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	players[0].on_ground = true
	events = tick_player(&world, &records, content, players, 0, press, TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{})
	testing.expect(t, players[0].velocity.y > 0)
}
