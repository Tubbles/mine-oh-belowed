package game

import "core:testing"
import rl "vendor:raylib"

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
	// Finished: progress stops at the required ticks until the caller clears it.
	state, broken = advance_mining(state, true, target, TEST_STONE, 90)
	testing.expect(t, broken)
	testing.expect_value(t, state.progress_ticks, 90)
	state, broken = advance_mining(state, true, target, TEST_STONE, 90)
	testing.expect(t, broken)
	testing.expect_value(t, state.progress_ticks, 90)
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
test_player_mines_block_into_hotbar :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	world := make_floor_world(registry, 32)
	stone := test_block(registry, "stone")
	player := make_test_player(registry, {0.5, 1, 0.5})
	player.pitch = -89
	player.held.stack = Item_Stack{test_item(items, "wooden_pickaxe"), 1}
	required := int(mining_required_ticks(registry.definitions[stone].hardness_seconds, TEST_TICK_RATE))
	tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Mine}}, required - 1)
	testing.expect_value(t, world_get_block(&world, {0, 0, 0}), stone)
	tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Mine}}, 1)
	testing.expect_value(t, world_get_block(&world, {0, 0, 0}), AIR_BLOCK)
	stone_item := test_item(items, "stone")
	testing.expect_value(t, player.inventory.slots[0], Item_Stack{item = stone_item, count = 1})
	testing.expect_value(t, selected_placed_block(player, items), stone)
}

@(test)
test_mining_drops_the_mapped_item :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	testing.expect_value(t, block_drop(items, test_block(registry, "grass")), test_item(items, "dirt"))
	testing.expect_value(t, block_drop(items, test_block(registry, "hematite_ore")), test_item(items, "hematite"))
	testing.expect_value(t, block_drop(items, test_block(registry, "log")), test_item(items, "log"))
	testing.expect_value(t, block_drop(items, AIR_BLOCK), NO_ITEM)
	testing.expect_value(t, item_places_block(items, test_item(items, "hematite")), AIR_BLOCK)
}

// A block whose item does not fit still breaks: the item spills at the
// block's cell, the toast shows once, and walking over the item with a
// free slot picks it up.
@(test)
test_mining_with_a_full_inventory_spills :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	use_temporary_loose_items(&world)
	player := make_test_player(registry, {0.5, 1, 0.5})
	player.pitch = -89
	for &slot in player.inventory.slots {
		slot = Item_Stack{item = test_item(make_test_items(), "coal"), count = 50}
	}
	player.held.stack = Item_Stack{test_item(make_test_items(), "wooden_pickaxe"), 1}
	stone := test_block(registry, "stone")
	stone_item := test_item(make_test_items(), "stone")
	required := int(mining_required_ticks(registry.definitions[stone].hardness_seconds, TEST_TICK_RATE))
	events := tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Mine}}, required)
	testing.expect_value(t, world_get_block(&world, {0, 0, 0}), AIR_BLOCK)
	testing.expect_value(t, events, Player_Events{.Inventory_Full})
	testing.expect_value(t, player.mining, Mining_State{})
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	testing.expect_value(t, world.entities.loose_items.items[0].item, stone_item)
	testing.expect_value(t, world.entities.loose_items.items[0].count, 1)
	testing.expect_value(t, world.entities.loose_items.items[0].cell, World_Coordinate{0, 0, 0})
	// Still full: the stone stays where the player stands.
	tick_test_player(&world, registry, &player, {}, 1)
	testing.expect_value(t, len(world.entities.loose_items.items), 1)
	player.inventory.slots[5] = EMPTY_STACK
	tick_test_player(&world, registry, &player, {}, 1)
	testing.expect_value(t, len(world.entities.loose_items.items), 0)
	testing.expect_value(t, player.inventory.slots[5], Item_Stack{item = stone_item, count = 1})
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
test_place_uses_selected_hotbar_slot_and_respects_player_box :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	world := make_floor_world(registry, 32)
	dirt := test_block(registry, "dirt")
	players := []Player{make_test_player(registry, {0.5, 1, 0.5})}
	player := &players[0]
	player.inventory.slots[2] = Item_Stack{item = test_item(items, "dirt"), count = 2}
	player.inventory.slots[3] = Item_Stack{item = test_item(items, "hematite"), count = 5}
	player.selected_hotbar_slot = 2
	player.target = Raycast_Hit{hit = true, block = {0, 0, 0}, face = .Positive_Y, adjacent = {0, 1, 0}}
	place_with_player(&world, Simulation_Content{blocks = registry, items = items, machines = make_test_machines()}, players, 0, {.Place})
	testing.expect_value(t, world_get_block(&world, {0, 1, 0}), AIR_BLOCK)
	testing.expect_value(t, player.inventory.slots[2].count, 2)
	player.target = Raycast_Hit{hit = true, block = {2, 0, 0}, face = .Positive_Y, adjacent = {2, 1, 0}}
	place_with_player(&world, Simulation_Content{blocks = registry, items = items, machines = make_test_machines()}, players, 0, {})
	testing.expect_value(t, world_get_block(&world, {2, 1, 0}), AIR_BLOCK)
	place_with_player(&world, Simulation_Content{blocks = registry, items = items, machines = make_test_machines()}, players, 0, {.Place})
	testing.expect_value(t, world_get_block(&world, {2, 1, 0}), dirt)
	testing.expect_value(t, player.inventory.slots[2].count, 1)
	testing.expect(t, world.chunks[{0, 0, 0}].dirty)
	// An item that places nothing is not consumed.
	player.selected_hotbar_slot = 3
	player.target = Raycast_Hit{hit = true, block = {4, 0, 0}, face = .Positive_Y, adjacent = {4, 1, 0}}
	place_with_player(&world, Simulation_Content{blocks = registry, items = items, machines = make_test_machines()}, players, 0, {.Place})
	testing.expect_value(t, world_get_block(&world, {4, 1, 0}), AIR_BLOCK)
	testing.expect_value(t, player.inventory.slots[3].count, 5)
	// The last one empties the slot.
	player.selected_hotbar_slot = 2
	place_with_player(&world, Simulation_Content{blocks = registry, items = items, machines = make_test_machines()}, players, 0, {.Place})
	testing.expect_value(t, player.inventory.slots[2], EMPTY_STACK)
}

@(test)
test_hotbar_cycle_wraps :: proc(t: ^testing.T) {
	testing.expect_value(t, cycle_hotbar_slot(0, {.Hotbar_Previous}), HOTBAR_SLOT_COUNT - 1)
	testing.expect_value(t, cycle_hotbar_slot(HOTBAR_SLOT_COUNT - 1, {.Hotbar_Next}), 0)
	testing.expect_value(t, cycle_hotbar_slot(3, {.Hotbar_Next}), 4)
	testing.expect_value(t, cycle_hotbar_slot(3, {}), 3)
}

// 0078: keyboard 1 to 8 select their hotbar slot directly.
@(test)
test_hotbar_slot_actions_select_the_slot :: proc(t: ^testing.T) {
	testing.expect_value(t, cycle_hotbar_slot(0, {.Hotbar_Slot_3}), 2)
	testing.expect_value(t, cycle_hotbar_slot(5, {.Hotbar_Slot_1}), 0)
	testing.expect_value(t, cycle_hotbar_slot(0, {.Hotbar_Slot_8}), HOTBAR_SLOT_COUNT - 1)
	// A slot key wins over a cycle step in the same tick.
	testing.expect_value(t, cycle_hotbar_slot(4, {.Hotbar_Slot_2, .Hotbar_Next}), 1)
	bindings := shipped_default_bindings(t)
	tables, _ := build_input_bindings(bindings, .Sdl3, context.temp_allocator)
	testing.expect_value(t, tables.keys[int(rl.KeyboardKey.THREE)], Action_Set{.Hotbar_Slot_3})
	testing.expect_value(t, tables.keys[int(rl.KeyboardKey.NINE)], Action_Set{})
}

// 0044: cheat speed digs in a tenth of the ticks, at least one, and a
// block that cannot be mined stays unminable.
@(test)
test_cheat_mining_ticks :: proc(t: ^testing.T) {
	testing.expect_value(t, cheat_mining_ticks(90, false), 90)
	testing.expect_value(t, cheat_mining_ticks(90, true), 9)
	testing.expect_value(t, cheat_mining_ticks(360, true), 36)
	testing.expect_value(t, cheat_mining_ticks(5, true), 1)
	testing.expect_value(t, cheat_mining_ticks(1, true), 1)
	testing.expect_value(t, cheat_mining_ticks(0, true), 0)
}

// Work item 0051: a block above the best pickaxe takes no ticks, so
// digging never starts. Hands are tier 0.
@(test)
test_tool_tier_gates_hand_mining :: proc(t: ^testing.T) {
	registry := make_test_registry()
	cases := [?]struct {
		block:     string,
		tool_tier: int,
		minable:   bool,
	} {
		{"dirt", 0, true},
		{"log", 0, true},
		{"stone", 0, false},
		{"stone", 1, true},
		{"cassiterite_ore", 1, false},
		{"cassiterite_ore", 2, true},
		{"deep_stone", 2, false},
		{"deep_stone", 3, true},
	}
	for entry in cases {
		ticks := required_ticks_for(registry, test_block(registry, entry.block), entry.tool_tier, TEST_TICK_RATE)
		testing.expectf(t, (ticks > 0) == entry.minable, "%s with tier %d took %d ticks", entry.block, entry.tool_tier, ticks)
	}
}

// Any inventory slot or the cursor counts, the best pickaxe wins.
@(test)
test_player_tool_tier_is_the_best_pickaxe_held :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	player := make_test_player(registry, {0.5, 1, 0.5})
	testing.expect_value(t, player_tool_tier(player, items), 0)
	player.inventory.slots[len(player.inventory.slots) - 1] = Item_Stack{test_item(items, "stone_pickaxe"), 1}
	testing.expect_value(t, player_tool_tier(player, items), 2)
	player.inventory.slots[0] = Item_Stack{test_item(items, "wooden_pickaxe"), 1}
	testing.expect_value(t, player_tool_tier(player, items), 2)
	player.held.stack = Item_Stack{test_item(items, "iron_pickaxe"), 1}
	testing.expect_value(t, player_tool_tier(player, items), 3)
}

@(test)
test_bare_hands_make_no_progress_on_stone :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	player := make_test_player(registry, {0.5, 1, 0.5})
	player.pitch = -89
	tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Mine}}, 200)
	testing.expect_value(t, world_get_block(&world, {0, 0, 0}), test_block(registry, "stone"))
	testing.expect_value(t, player.mining, Mining_State{})
}

@(test)
test_hud_names_the_pickaxe_a_block_needs :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	assert(error == nil)
	thread_string_table = &table
	defer thread_string_table = nil
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	target := Raycast_Hit{hit = true, block = {0, 0, 0}}
	_, line, _ := target_status_lines(&world, content.machines, content.fluids, content.veins, content.blocks, content.items, nil, 0, target)
	testing.expect_value(t, line, "Needs a tool: Wooden pickaxe")
	_, line, _ = target_status_lines(&world, content.machines, content.fluids, content.veins, content.blocks, content.items, nil, 1, target)
	testing.expect_value(t, line, "")
	world_set_block(&world, {0, 0, 0}, test_block(content.blocks, "deep_stone"))
	_, line, _ = target_status_lines(&world, content.machines, content.fluids, content.veins, content.blocks, content.items, nil, 1, target)
	testing.expect_value(t, line, "Needs a tool: Iron pickaxe")
}

// The developer cheat speed mines every tier; without it the carried
// pickaxe decides.
@(test)
test_cheat_speed_mines_every_tier :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	items := make_test_items()
	player := make_player(player_start_on({0, 0, 0}))
	testing.expect_value(t, effective_tool_tier(player, items, false), 0)
	testing.expect_value(t, effective_tool_tier(player, items, true), highest_tool_tier(items.items))
	testing.expect(t, highest_tool_tier(items.items) >= 3)
}
