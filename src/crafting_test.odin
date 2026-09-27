package game

import "core:testing"

Crafting_Test :: struct {
	items:        Item_Registry,
	recipes:      Recipe_Registry,
	technologies: Technology_Registry,
	unlocks:      Recipe_Unlocks,
	inventory:    Inventory,
	queue:        Craft_Queue,
}

make_crafting_test :: proc(unlock_all := false) -> Crafting_Test {
	items := make_test_items()
	recipes, technologies := make_test_recipes(items)
	return Crafting_Test {
		items = items,
		recipes = recipes,
		technologies = technologies,
		unlocks = make_recipe_unlocks(len(items.items), recipes, technologies, unlock_all, context.temp_allocator),
		inventory = make_inventory(PLAYER_INVENTORY_SLOT_COUNT, context.temp_allocator),
	}
}

test_available :: proc(test: Crafting_Test, id: string) -> bool {
	return recipe_is_available(test.unlocks, test_recipe(test.recipes, id))
}

@(test)
test_start_recipes_are_always_available :: proc(t: ^testing.T) {
	test := make_crafting_test()
	for recipe, index in test.recipes.recipes {
		testing.expectf(t, test.unlocks.available[index] == (recipe.channel == .Start), "%s", recipe.id)
	}
	testing.expect_value(t, obtained_item_count(test.unlocks), 0)
}

@(test)
test_discovery_follows_the_obtained_items :: proc(t: ^testing.T) {
	test := make_crafting_test()
	testing.expect(t, !test_available(test, "electronic_circuit"))
	testing.expect(t, record_obtained_item(&test.unlocks, test_item(test.items, "iron_plate")))
	testing.expect(t, !record_obtained_item(&test.unlocks, test_item(test.items, "iron_plate")))
	refresh_available_recipes(&test.unlocks, test.recipes)
	testing.expect(t, !test_available(test, "electronic_circuit"))
	record_obtained_item(&test.unlocks, test_item(test.items, "copper_wire"))
	refresh_available_recipes(&test.unlocks, test.recipes)
	testing.expect(t, test_available(test, "electronic_circuit"))
	// The scan over players picks up the inventory and the cursor.
	player := make_player({}, context.temp_allocator)
	inventory_add(player.inventory, test.items, test_item(test.items, "sand"), 3)
	player.held.stack = Item_Stack{test_item(test.items, "log"), 1}
	players := []Player{player}
	update_recipe_unlocks(&test.unlocks, test.recipes, players)
	testing.expect(t, test_available(test, "glass"))
	testing.expect(t, test_available(test, "charcoal"))
	testing.expect_value(t, obtained_item_count(test.unlocks), 4)
}

@(test)
test_research_and_quest_recipes_wait :: proc(t: ^testing.T) {
	test := make_crafting_test()
	steel := test_recipe(test.recipes, "steel")
	// Having the ingredients does not unlock a research recipe.
	record_obtained_item(&test.unlocks, test_item(test.items, "iron_plate"))
	record_obtained_item(&test.unlocks, test_item(test.items, "coal"))
	refresh_available_recipes(&test.unlocks, test.recipes)
	testing.expect(t, !recipe_is_available(test.unlocks, steel))
	mark_technology_researched(&test.unlocks, test.recipes, test.recipes.recipes[steel].technology)
	testing.expect(t, recipe_is_available(test.unlocks, steel))
	testing.expect(t, test_available(test, "steel_furnace"))
	testing.expect(t, !test_available(test, "lamp"))
	testing.expect(t, !test_available(test, "steam_engine"))
}

@(test)
test_unlock_all_makes_everything_available :: proc(t: ^testing.T) {
	test := make_crafting_test(unlock_all = true)
	testing.expect_value(t, available_recipe_count(test.unlocks), len(test.recipes.recipes))
	testing.expect_value(t, obtained_item_count(test.unlocks), len(test.items.items))
	testing.expect(t, test_available(test, "steam_engine"))
	command_line, command_line_error := parse_command_line({"--unlock-all"})
	testing.expect(t, command_line.unlock_all)
	testing.expect_value(t, command_line_error, nil)
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect(t, !config.all_recipes_unlocked)
}

@(test)
test_crafting_queue_takes_crafts_and_returns :: proc(t: ^testing.T) {
	test := make_crafting_test()
	plate := test_item(test.items, "iron_plate")
	gear := test_item(test.items, "iron_gear")
	gear_recipe := test_recipe(test.recipes, "iron_gear")
	inventory_add(test.inventory, test.items, plate, 5)
	testing.expect_value(t, queue_craft(&test.queue, test.inventory, test.recipes, test.unlocks, gear_recipe), Craft_Refusal.None)
	testing.expect_value(t, queue_craft(&test.queue, test.inventory, test.recipes, test.unlocks, gear_recipe), Craft_Refusal.None)
	testing.expect_value(t, inventory_count(test.inventory, plate), 1)
	testing.expect_value(t, queue_craft(&test.queue, test.inventory, test.recipes, test.unlocks, gear_recipe), Craft_Refusal.Missing_Ingredients)
	testing.expect_value(t, test.queue.count, 2)
	// 0.5 s at 60 ticks per second is 30 ticks per gear.
	for _ in 0 ..< 29 {
		advance_crafting(&test.queue, test.inventory, test.recipes, test.items, TEST_TICK_RATE)
	}
	testing.expect_value(t, inventory_count(test.inventory, gear), 0)
	testing.expect_value(t, test.queue.progress_ticks, 29)
	advance_crafting(&test.queue, test.inventory, test.recipes, test.items, TEST_TICK_RATE)
	testing.expect_value(t, inventory_count(test.inventory, gear), 1)
	testing.expect_value(t, test.queue.count, 1)
	testing.expect_value(t, test.queue.progress_ticks, 0)
	// Cancelling the second gear gives its two plates back.
	testing.expect(t, cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
	testing.expect_value(t, inventory_count(test.inventory, plate), 3)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect(t, !cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
}

@(test)
test_crafting_queue_refusals :: proc(t: ^testing.T) {
	test := make_crafting_test()
	plank := test_recipe(test.recipes, "plank")
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 20)
	queued, refusal := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, plank, 12)
	testing.expect_value(t, queued, HAND_CRAFT_QUEUE_CAPACITY)
	testing.expect_value(t, refusal, Craft_Refusal.Queue_Full)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "log")), 20 - HAND_CRAFT_QUEUE_CAPACITY)
	test.queue = {}
	inventory_add(test.inventory, test.items, test_item(test.items, "hematite"), 5)
	testing.expect_value(t, queue_craft(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "iron_plate")), Craft_Refusal.Not_Hand_Craftable)
	testing.expect_value(t, queue_craft(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "electronic_circuit")), Craft_Refusal.Locked)
}

@(test)
test_crafting_waits_on_a_full_inventory :: proc(t: ^testing.T) {
	test := make_crafting_test()
	test.inventory = make_inventory(1, context.temp_allocator)
	log := test_item(test.items, "log")
	plank := test_item(test.items, "plank")
	inventory_add(test.inventory, test.items, log, 2)
	queue_craft(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "plank"))
	// The one slot still holds a log, so the planks cannot go anywhere.
	for _ in 0 ..< 40 {
		advance_crafting(&test.queue, test.inventory, test.recipes, test.items, TEST_TICK_RATE)
	}
	testing.expect(t, test.queue.waiting)
	testing.expect_value(t, test.queue.count, 1)
	testing.expect_value(t, test.queue.progress_ticks, 30)
	testing.expect_value(t, inventory_count(test.inventory, log), 1)
	// Cancelling would need room for the log, which merges; instead free the slot.
	inventory_remove(test.inventory, log, 1)
	advance_crafting(&test.queue, test.inventory, test.recipes, test.items, TEST_TICK_RATE)
	testing.expect(t, !test.queue.waiting)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect_value(t, inventory_count(test.inventory, plank), 4)
}

@(test)
test_cancel_refused_when_ingredients_do_not_fit :: proc(t: ^testing.T) {
	test := make_crafting_test()
	test.inventory = make_inventory(1, context.temp_allocator)
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 1)
	queue_craft(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "plank"))
	inventory_add(test.inventory, test.items, test_item(test.items, "stone"), 1)
	testing.expect(t, !cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
	testing.expect_value(t, test.queue.count, 1)
}

@(test)
test_hand_crafting_runs_in_the_player_tick :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	players := []Player{make_player(player_start_on({4, 0, 4}), context.temp_allocator)}
	player := &players[0]
	_, technologies := make_test_recipes(content.items)
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, technologies, false, context.temp_allocator)
	inventory_add(player.inventory, content.items, test_item(content.items, "stone"), 5)
	testing.expect_value(t, queue_craft(&player.crafting, player.inventory, content.recipes, unlocks, test_recipe(content.recipes, "stone_furnace")), Craft_Refusal.None)
	for _ in 0 ..< 2 * TEST_TICK_RATE {
		tick_player(&world, content, players, 0, {}, TEST_TICK_RATE)
	}
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "stone_furnace")), 1)
	testing.expect_value(t, player.crafting.count, 0)
}
