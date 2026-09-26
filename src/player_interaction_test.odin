package game

import "core:testing"

@(test)
test_mining_required_ticks :: proc(t: ^testing.T) {
	testing.expect_value(t, mining_required_ticks(1.5, 60), 90)
	testing.expect_value(t, mining_required_ticks(0.3, 60), 18)
	testing.expect_value(t, mining_required_ticks(6, 60), 360)
	testing.expect_value(t, mining_required_ticks(0.001, 60), 1)
}

@(test)
test_mining_progress_breaks_after_required_ticks :: proc(t: ^testing.T) {
	target := Raycast_Hit {
		hit   = true,
		block = {1, 2, 3},
	}
	state: Mining_State
	broken: bool
	for tick in 1 ..< 90 {
		state, broken = advance_mining(state, true, target, TEST_STONE, 90)
		testing.expect(t, !broken)
		testing.expect_value(t, state.progress_ticks, u32(tick))
	}
	testing.expect(t, abs(mining_fraction(state) - 89.0 / 90) < 1e-6)
	state, broken = advance_mining(state, true, target, TEST_STONE, 90)
	testing.expect(t, broken)
	testing.expect_value(t, state, Mining_State{})
}

@(test)
test_mining_progress_resets :: proc(t: ^testing.T) {
	target := Raycast_Hit {
		hit   = true,
		block = {1, 2, 3},
	}
	state: Mining_State
	for _ in 0 ..< 10 {
		state, _ = advance_mining(state, true, target, TEST_STONE, 90)
	}
	moved := target
	moved.block = {1, 2, 4}
	changed, _ := advance_mining(state, true, moved, TEST_STONE, 90)
	testing.expect_value(t, changed.progress_ticks, 1)
	replaced, _ := advance_mining(state, true, target, TEST_DIRT, 90)
	testing.expect_value(t, replaced.progress_ticks, 1)
	released, _ := advance_mining(state, false, target, TEST_STONE, 90)
	testing.expect_value(t, released, Mining_State{})
	unminable, _ := advance_mining(state, true, target, TEST_STONE, 0)
	testing.expect_value(t, unminable, Mining_State{})
}

@(test)
test_player_mines_block_into_owned_count :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	stone := test_block(registry, "stone")
	player := make_test_player(registry, {0.5, 1, 0.5})
	player.pitch = -89
	required := int(mining_required_ticks(registry.definitions[stone].hardness_seconds, TEST_TICK_RATE))
	tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Mine}}, required - 1)
	testing.expect_value(t, world_get_block(&world, {0, 0, 0}), stone)
	tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Mine}}, 1)
	testing.expect_value(t, world_get_block(&world, {0, 0, 0}), AIR_BLOCK)
	testing.expect_value(t, player.owned_blocks[stone], 1)
	testing.expect_value(t, player.selected_block, stone)
}

@(test)
test_water_is_not_minable :: proc(t: ^testing.T) {
	registry := make_test_registry()
	testing.expect(t, !block_is_minable(registry, test_block(registry, "water")))
	testing.expect(t, !block_is_minable(registry, AIR_BLOCK))
	testing.expect(t, block_is_minable(registry, test_block(registry, "deep_stone")))
	testing.expect_value(t, registry.definitions[test_block(registry, "deep_stone")].hardness_seconds, 6)
}

@(test)
test_placement_rejects_cells_inside_a_player :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	players := []Player{make_test_player(registry, {0.5, 1, 0.5}), make_test_player(registry, {5.5, 1, 0.5})}
	testing.expect(t, !placement_allowed(&world, registry, players, {0, 1, 0}))
	testing.expect(t, !placement_allowed(&world, registry, players, {0, 2, 0}))
	testing.expect(t, placement_allowed(&world, registry, players, {1, 1, 0}))
	testing.expect(t, placement_allowed(&world, registry, players, {0, 3, 0}))
	testing.expect(t, !placement_allowed(&world, registry, players, {5, 1, 0}))
	testing.expect(t, !placement_allowed(&world, registry, players, {0, 0, 0}))
}

@(test)
test_place_uses_owned_block_and_respects_player_box :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	dirt := test_block(registry, "dirt")
	players := []Player{make_test_player(registry, {0.5, 1, 0.5})}
	player := &players[0]
	player.owned_blocks[dirt] = 2
	player.selected_block = dirt
	player.target = Raycast_Hit{hit = true, block = {0, 0, 0}, face = .Positive_Y, adjacent = {0, 1, 0}}
	place_with_player(&world, registry, players, 0, {.Place})
	testing.expect_value(t, world_get_block(&world, {0, 1, 0}), AIR_BLOCK)
	testing.expect_value(t, player.owned_blocks[dirt], 2)
	player.target = Raycast_Hit{hit = true, block = {2, 0, 0}, face = .Positive_Y, adjacent = {2, 1, 0}}
	place_with_player(&world, registry, players, 0, {})
	testing.expect_value(t, world_get_block(&world, {2, 1, 0}), AIR_BLOCK)
	place_with_player(&world, registry, players, 0, {.Place})
	testing.expect_value(t, world_get_block(&world, {2, 1, 0}), dirt)
	testing.expect_value(t, player.owned_blocks[dirt], 1)
	testing.expect(t, world.chunks[{0, 0, 0}].dirty)
}

@(test)
test_selection_cycles_owned_blocks :: proc(t: ^testing.T) {
	owned := []u32{0, 3, 0, 1, 0, 2}
	testing.expect_value(t, next_owned_block(owned, AIR_BLOCK, 1), Block_Id(1))
	testing.expect_value(t, next_owned_block(owned, Block_Id(1), 1), Block_Id(3))
	testing.expect_value(t, next_owned_block(owned, Block_Id(5), 1), Block_Id(1))
	testing.expect_value(t, next_owned_block(owned, Block_Id(1), -1), Block_Id(5))
	testing.expect_value(t, next_owned_block([]u32{0, 0}, AIR_BLOCK, 1), AIR_BLOCK)
	player := Player {
		owned_blocks   = owned,
		selected_block = Block_Id(3),
	}
	cycle_selected_block(&player, {.Hotbar_Previous})
	testing.expect_value(t, player.selected_block, Block_Id(1))
	cycle_selected_block(&player, {.Hotbar_Next})
	testing.expect_value(t, player.selected_block, Block_Id(3))
}
