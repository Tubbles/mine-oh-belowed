package game

import "core:slice"
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

queue_test_craft :: proc(test: ^Crafting_Test, recipe: int) -> Craft_Refusal {
	refusal, _ := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, recipe, 1)
	return refusal
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

advance_crafting_ticks :: proc(test: ^Crafting_Test, ticks: int) {
	for _ in 0 ..< ticks {
		advance_crafting(&test.queue, test.inventory, test.recipes, test.items, TEST_TICK_RATE)
	}
}

@(test)
test_crafting_takes_ingredients_when_a_craft_starts :: proc(t: ^testing.T) {
	test := make_crafting_test()
	plate := test_item(test.items, "iron_plate")
	gear := test_item(test.items, "iron_gear")
	gear_recipe := test_recipe(test.recipes, "iron_gear")
	inventory_add(test.inventory, test.items, plate, 5)
	testing.expect_value(t, queue_test_craft(&test, gear_recipe), Craft_Refusal.None)
	testing.expect_value(t, queue_test_craft(&test, gear_recipe), Craft_Refusal.None)
	// Queuing takes nothing, but plans against the two gears queued.
	testing.expect_value(t, inventory_count(test.inventory, plate), 5)
	refusal, shortage := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, gear_recipe, 1)
	testing.expect_value(t, refusal, Craft_Refusal.Missing_Ingredients)
	testing.expect_value(t, shortage, Craft_Shortage{plate, 1})
	testing.expect_value(t, test.queue.count, 1)
	testing.expect_value(t, test.queue.runs[0], Craft_Run{gear_recipe, 2})
	// 0.5 s at 60 ticks per second is 30 ticks per gear; the first tick
	// starts the craft and takes its plates.
	advance_crafting_ticks(&test, 29)
	testing.expect_value(t, inventory_count(test.inventory, plate), 3)
	testing.expect_value(t, inventory_count(test.inventory, gear), 0)
	testing.expect_value(t, test.queue.progress_ticks, 29)
	advance_crafting_ticks(&test, 1)
	testing.expect_value(t, inventory_count(test.inventory, gear), 1)
	testing.expect_value(t, test.queue.runs[0].count, 1)
	testing.expect_value(t, test.queue.progress_ticks, 0)
	testing.expect(t, !test.queue.started)
	advance_crafting_ticks(&test, 30)
	testing.expect_value(t, inventory_count(test.inventory, gear), 2)
	testing.expect_value(t, inventory_count(test.inventory, plate), 1)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect(t, !cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
}

@(test)
test_crafting_queue_refusals :: proc(t: ^testing.T) {
	test := make_crafting_test()
	inventory_add(test.inventory, test.items, test_item(test.items, "hematite"), 5)
	testing.expect_value(t, queue_test_craft(&test, test_recipe(test.recipes, "iron_plate")), Craft_Refusal.Not_Hand_Craftable)
	testing.expect_value(t, queue_test_craft(&test, test_recipe(test.recipes, "electronic_circuit")), Craft_Refusal.Locked)
	// A full queue refuses a new run but grows its last one.
	plank := test_recipe(test.recipes, "plank")
	stick := test_recipe(test.recipes, "stick")
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 50)
	for index in 0 ..< HAND_CRAFT_QUEUE_RUNS {
		testing.expect_value(t, queue_test_craft(&test, index % 2 == 0 ? plank : stick), Craft_Refusal.None)
	}
	testing.expect_value(t, test.queue.count, HAND_CRAFT_QUEUE_RUNS)
	testing.expect_value(t, queue_test_craft(&test, plank), Craft_Refusal.Queue_Full)
	testing.expect_value(t, queue_test_craft(&test, stick), Craft_Refusal.None)
	testing.expect_value(t, test.queue.runs[HAND_CRAFT_QUEUE_RUNS - 1], Craft_Run{stick, 2})
}

// Work item 0138: twenty planks are one run, and Craft five twice on the
// same recipe makes one run of ten.
@(test)
test_crafts_of_one_recipe_grow_one_run :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	test := make_crafting_test()
	plank := test_recipe(test.recipes, "plank")
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 20)
	refusal, _ := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, plank, 20)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	testing.expect_value(t, test.queue.count, 1)
	testing.expect_value(t, test.queue.runs[0], Craft_Run{plank, 20})
	testing.expect_value(t, queue_summary_text(test.queue), "Crafting  20")
	test.queue = make_craft_queue()
	stone_slab := test_recipe(test.recipes, "stone_slab")
	inventory_add(test.inventory, test.items, test_item(test.items, "stone"), 10)
	for _ in 0 ..< 2 {
		refusal, _ = queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, stone_slab, 5)
		testing.expect_value(t, refusal, Craft_Refusal.None)
	}
	testing.expect_value(t, test.queue.count, 1)
	testing.expect_value(t, test.queue.runs[0], Craft_Run{stone_slab, 10})
	// The ten are all the stone planned for.
	refusal, _ = queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, stone_slab, 1)
	testing.expect_value(t, refusal, Craft_Refusal.Missing_Ingredients)
}

// A wooden pickaxe from logs alone: a plank run and a stick run go ahead
// of it, the stick run using the planks the pickaxe leaves over.
@(test)
test_intermediates_are_queued_ahead :: proc(t: ^testing.T) {
	test := make_crafting_test()
	log := test_item(test.items, "log")
	plank := test_recipe(test.recipes, "plank")
	stick := test_recipe(test.recipes, "stick")
	pickaxe := test_recipe(test.recipes, "wooden_pickaxe")
	inventory_add(test.inventory, test.items, log, 2)
	refusal, _ := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, pickaxe, 1)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	testing.expect_value(t, test.queue.count, 3)
	testing.expect_value(t, test.queue.runs[0], Craft_Run{plank, 1})
	testing.expect_value(t, test.queue.runs[1], Craft_Run{stick, 1})
	testing.expect_value(t, test.queue.runs[2], Craft_Run{pickaxe, 1})
	// A second pickaxe plans against the queued runs: the two sticks the
	// first leaves over cover it, the last log makes its planks.
	ahead, runs, plan_refusal, _ := plan_crafts(test.queue, test.inventory, test.recipes, test.unlocks.available, pickaxe, 1)
	testing.expect_value(t, plan_refusal, Craft_Refusal.None)
	testing.expect_value(t, len(ahead), 0)
	testing.expectf(t, slice.equal(runs, []Craft_Run{{plank, 1}, {pickaxe, 1}}), "%v", runs)
	// Planks, sticks and a pickaxe take 0.5 + 0.5 + 1 seconds.
	advance_crafting_ticks(&test, 120)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "wooden_pickaxe")), 1)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "stick")), 2)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "plank")), 0)
	testing.expect_value(t, inventory_count(test.inventory, log), 1)
}

// Short of a raw item, nothing is queued and the toast names it.
@(test)
test_a_plan_short_of_a_raw_item_queues_nothing :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	test := make_crafting_test()
	plate := test_item(test.items, "iron_plate")
	inventory_add(test.inventory, test.items, plate, 1)
	refusal, shortage := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "iron_gear"), 3)
	testing.expect_value(t, refusal, Craft_Refusal.Missing_Ingredients)
	testing.expect_value(t, shortage, Craft_Shortage{plate, 5})
	testing.expect_value(t, craft_refusal_text(refusal, shortage, test.items), "Missing 5 Iron plate")
	testing.expect_value(t, test.queue.count, 0)
	// A log short two levels down refuses the whole pickaxe.
	refusal, shortage = queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "wooden_pickaxe"), 1)
	testing.expect_value(t, refusal, Craft_Refusal.Missing_Ingredients)
	testing.expect_value(t, shortage, Craft_Shortage{test_item(test.items, "log"), 1})
	testing.expect_value(t, test.queue.count, 0)
}

// A chain of hand recipes: recipe index makes item index from item
// index + 1; the last one, when cyclic, from item 0.
make_chain_recipes :: proc(length: int, cyclic: bool) -> (recipes: Recipe_Registry, available: []bool) {
	list := make([]Recipe, length, context.temp_allocator)
	available = make([]bool, length, context.temp_allocator)
	for index in 0 ..< length {
		input := Item_Id(index + 1)
		if cyclic && index == length - 1 {
			input = 0
		}
		list[index] = Recipe {
			inputs       = slice.clone([]Item_Stack{{input, 1}}, context.temp_allocator),
			outputs      = slice.clone([]Item_Stack{{Item_Id(index), 1}}, context.temp_allocator),
			milliseconds = 500,
			made_in      = {.Hand},
		}
		available[index] = true
	}
	return Recipe_Registry{recipes = list}, available
}

@(test)
test_a_recipe_cycle_refuses :: proc(t: ^testing.T) {
	inventory := make_inventory(4, context.temp_allocator)
	recipes, available := make_chain_recipes(2, cyclic = true)
	_, runs, refusal, shortage := plan_crafts(make_craft_queue(), inventory, recipes, available, 0, 1)
	testing.expect_value(t, len(runs), 0)
	testing.expect_value(t, refusal, Craft_Refusal.Recipe_Cycle)
	testing.expect_value(t, shortage.item, Item_Id(0))
	// A chain deeper than the bound refuses with its own reason, a shorter
	// one plans down to the raw item at its end.
	recipes, available = make_chain_recipes(HAND_CRAFT_PLAN_DEPTH + 2, cyclic = false)
	_, _, refusal, _ = plan_crafts(make_craft_queue(), inventory, recipes, available, 0, 1)
	testing.expect_value(t, refusal, Craft_Refusal.Plan_Too_Deep)
	recipes, available = make_chain_recipes(4, cyclic = false)
	_, _, refusal, shortage = plan_crafts(make_craft_queue(), inventory, recipes, available, 0, 1)
	testing.expect_value(t, refusal, Craft_Refusal.Missing_Ingredients)
	testing.expect_value(t, shortage, Craft_Shortage{Item_Id(4), 1})
}

// A front run whose log was dropped waits and names it; Cancel frees it
// and gives nothing back.
@(test)
test_a_front_run_waits_for_a_spent_input :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	test := make_crafting_test()
	log := test_item(test.items, "log")
	inventory_add(test.inventory, test.items, log, 2)
	refusal, _ := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "plank"), 2)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	inventory_remove(test.inventory, log, 2)
	advance_crafting_ticks(&test, 5)
	testing.expect(t, craft_queue_waits_for_input(test.queue))
	testing.expect_value(t, test.queue.waiting_for, log)
	testing.expect_value(t, test.queue.progress_ticks, 0)
	testing.expect_value(t, craft_queue_waiting_text(test.queue, test.items), "Waiting for Log")
	testing.expect(t, cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
	testing.expect(t, cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
	testing.expect_value(t, test.queue.count, 0)
	testing.expect(t, !craft_queue_waits_for_input(test.queue))
	testing.expect_value(t, craft_queue_waiting_text(test.queue, test.items), "")
	testing.expect_value(t, inventory_count(test.inventory, log), 0)
}

// A front stick run whose plank was dropped: a log added and the next
// queue action puts a plank run ahead of it, and the queue finishes.
@(test)
test_a_waiting_front_is_repaired_by_the_next_queue_action :: proc(t: ^testing.T) {
	test := make_crafting_test()
	plank_item := test_item(test.items, "plank")
	log := test_item(test.items, "log")
	plank := test_recipe(test.recipes, "plank")
	stick := test_recipe(test.recipes, "stick")
	inventory_add(test.inventory, test.items, plank_item, 1)
	testing.expect_value(t, queue_test_craft(&test, stick), Craft_Refusal.None)
	inventory_remove(test.inventory, plank_item, 1)
	advance_crafting_ticks(&test, 1)
	testing.expect_value(t, test.queue.waiting_for, plank_item)
	inventory_add(test.inventory, test.items, log, 1)
	ahead, runs, refusal, _ := plan_crafts(test.queue, test.inventory, test.recipes, test.unlocks.available, stick, 1)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	testing.expectf(t, slice.equal(ahead, []Craft_Run{{plank, 1}}), "%v", ahead)
	testing.expectf(t, slice.equal(runs, []Craft_Run{{stick, 1}}), "%v", runs)
	testing.expect_value(t, queue_test_craft(&test, stick), Craft_Refusal.None)
	testing.expect_value(t, test.queue.count, 2)
	testing.expect_value(t, test.queue.runs[0], Craft_Run{plank, 1})
	testing.expect_value(t, test.queue.runs[1], Craft_Run{stick, 2})
	testing.expect(t, !craft_queue_waits_for_input(test.queue))
	advance_crafting_ticks(&test, 600)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "stick")), 8)
	testing.expect_value(t, inventory_count(test.inventory, plank_item), 2)
	testing.expect_value(t, inventory_count(test.inventory, log), 0)
}

// With nothing to make the missing plank from, the front keeps waiting
// and an unrelated recipe still queues, without a plank run behind it.
@(test)
test_a_front_deficit_without_a_maker_keeps_waiting :: proc(t: ^testing.T) {
	test := make_crafting_test()
	plank_item := test_item(test.items, "plank")
	stick := test_recipe(test.recipes, "stick")
	stone_slab := test_recipe(test.recipes, "stone_slab")
	inventory_add(test.inventory, test.items, plank_item, 1)
	queue_test_craft(&test, stick)
	inventory_remove(test.inventory, plank_item, 1)
	advance_crafting_ticks(&test, 1)
	inventory_add(test.inventory, test.items, test_item(test.items, "stone"), 1)
	ahead, runs, refusal, _ := plan_crafts(test.queue, test.inventory, test.recipes, test.unlocks.available, stone_slab, 1)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	testing.expect_value(t, len(ahead), 0)
	testing.expectf(t, slice.equal(runs, []Craft_Run{{stone_slab, 1}}), "%v", runs)
	testing.expect_value(t, queue_test_craft(&test, stone_slab), Craft_Refusal.None)
	testing.expect_value(t, test.queue.count, 2)
	testing.expect(t, craft_queue_waits_for_input(test.queue))
	testing.expect_value(t, test.queue.waiting_for, plank_item)
}

// The repair covers every craft of the waiting run, not only the first.
@(test)
test_the_repair_covers_the_whole_front_run :: proc(t: ^testing.T) {
	test := make_crafting_test()
	plank_item := test_item(test.items, "plank")
	plank := test_recipe(test.recipes, "plank")
	stick := test_recipe(test.recipes, "stick")
	stone_slab := test_recipe(test.recipes, "stone_slab")
	inventory_add(test.inventory, test.items, plank_item, 6)
	refusal, _ := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, stick, 6)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	inventory_remove(test.inventory, plank_item, 6)
	advance_crafting_ticks(&test, 1)
	testing.expect(t, craft_queue_waits_for_input(test.queue))
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 2)
	inventory_add(test.inventory, test.items, test_item(test.items, "stone"), 1)
	testing.expect_value(t, queue_test_craft(&test, stone_slab), Craft_Refusal.None)
	testing.expect_value(t, test.queue.runs[0], Craft_Run{plank, 2})
	testing.expect_value(t, test.queue.runs[1], Craft_Run{stick, 6})
	advance_crafting_ticks(&test, 900)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "stick")), 24)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "stone_slab")), 2)
}

@(test)
test_a_count_below_one_queues_nothing :: proc(t: ^testing.T) {
	test := make_crafting_test()
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 4)
	for count in ([?]int{0, -3}) {
		refusal, _ := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "plank"), count)
		testing.expect_value(t, refusal, Craft_Refusal.None)
		testing.expect_value(t, test.queue.count, 0)
	}
}

// The HUD's boxes: all runs when they fit, else the front and the newest.
@(test)
test_craft_queue_shown_runs :: proc(t: ^testing.T) {
	testing.expect(t, slice.equal(craft_queue_shown_runs(3, 8), []int{0, 1, 2}))
	testing.expect(t, slice.equal(craft_queue_shown_runs(10, 4), []int{0, 7, 8, 9}))
	testing.expect_value(t, len(craft_queue_shown_runs(HAND_CRAFT_QUEUE_RUNS, 16)), 16)
}

// Cancelling a queued craft returns nothing, the craft in progress its
// ingredients.
@(test)
test_cancel_returns_only_the_craft_in_progress :: proc(t: ^testing.T) {
	test := make_crafting_test()
	log := test_item(test.items, "log")
	inventory_add(test.inventory, test.items, log, 2)
	refusal, _ := queue_crafts(&test.queue, test.inventory, test.recipes, test.unlocks, test_recipe(test.recipes, "plank"), 2)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	advance_crafting_ticks(&test, 1)
	testing.expect(t, test.queue.started)
	testing.expect_value(t, inventory_count(test.inventory, log), 1)
	testing.expect(t, cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
	testing.expect_value(t, inventory_count(test.inventory, log), 1)
	testing.expect_value(t, test.queue.runs[0].count, 1)
	testing.expect(t, cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
	testing.expect_value(t, inventory_count(test.inventory, log), 2)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect(t, !test.queue.started)
}

@(test)
test_crafting_waits_on_a_full_inventory :: proc(t: ^testing.T) {
	test := make_crafting_test()
	test.inventory = make_inventory(1, context.temp_allocator)
	log := test_item(test.items, "log")
	plank := test_item(test.items, "plank")
	inventory_add(test.inventory, test.items, log, 2)
	queue_test_craft(&test, test_recipe(test.recipes, "plank"))
	// The one slot still holds a log, so the planks cannot go anywhere.
	advance_crafting_ticks(&test, 40)
	testing.expect(t, test.queue.waiting)
	testing.expect_value(t, test.queue.count, 1)
	testing.expect_value(t, test.queue.progress_ticks, 30)
	testing.expect_value(t, inventory_count(test.inventory, log), 1)
	// Cancelling would need room for the log, which merges; instead free the slot.
	inventory_remove(test.inventory, log, 1)
	advance_crafting_ticks(&test, 1)
	testing.expect(t, !test.queue.waiting)
	testing.expect_value(t, test.queue.count, 0)
	testing.expect_value(t, inventory_count(test.inventory, plank), 4)
}

@(test)
test_cancel_refused_when_ingredients_do_not_fit :: proc(t: ^testing.T) {
	test := make_crafting_test()
	test.inventory = make_inventory(1, context.temp_allocator)
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 1)
	queue_test_craft(&test, test_recipe(test.recipes, "plank"))
	advance_crafting_ticks(&test, 1)
	inventory_add(test.inventory, test.items, test_item(test.items, "stone"), 1)
	testing.expect(t, !cancel_last_craft(&test.queue, test.inventory, test.recipes, test.items))
	testing.expect_value(t, test.queue.count, 1)
}

// The held count of a product counts the hotbar and the main grid.
@(test)
test_held_count_counts_both_grids :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	test := make_crafting_test()
	plank := test_item(test.items, "plank")
	test.inventory.slots[0] = {plank, 5}
	test.inventory.slots[HOTBAR_SLOT_COUNT + 3] = {plank, 7}
	recipe := test.recipes.recipes[test_recipe(test.recipes, "plank")]
	held, has_product := recipe_held_count(test.inventory, recipe)
	testing.expect(t, has_product)
	testing.expect_value(t, held, 12)
	testing.expect_value(t, product_held_line(recipe.outputs[0], held, test.items), "4 × Plank, 12 held")
	_, has_product = recipe_held_count(test.inventory, Recipe{})
	testing.expect(t, !has_product)
}

// The queue layout before 0138, as a save of that time holds it.
Craft_Queue_Before_Runs :: struct {
	recipes:        [8]int,
	count:          int,
	progress_ticks: u32,
	waiting:        bool,
}

identity_recipe_remap :: proc(recipes: Recipe_Registry) -> Content_Remap {
	remap: Content_Remap
	remap.new_indices[.Recipes] = make([]int, len(recipes.recipes), context.temp_allocator)
	for &index, position in remap.new_indices[.Recipes] {
		index = position
	}
	return remap
}

@(test)
test_craft_queue_saves_runs_and_reads_the_old_layout :: proc(t: ^testing.T) {
	test := make_crafting_test()
	remap := identity_recipe_remap(test.recipes)
	queue := make_craft_queue()
	queue.runs[0] = {test_recipe(test.recipes, "plank"), 20}
	queue.runs[1] = {test_recipe(test.recipes, "stick"), 3}
	queue.count, queue.progress_ticks, queue.waiting_for = 2, 0, test_item(test.items, "log")
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, &queue)
	read := make_craft_queue()
	reader := Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect(t, remap_craft_queue(&read, remap))
	testing.expect_value(t, read, queue)
	// Three single crafts of the old layout come back as an empty queue.
	old := Craft_Queue_Before_Runs{recipes = {0, 1, 2, 0, 0, 0, 0, 0}, count = 3, progress_ticks = 12, waiting = true}
	clear(&bytes)
	write_value_of(&bytes, &old)
	read = make_craft_queue()
	reader = Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect(t, remap_craft_queue(&read, remap))
	testing.expect_value(t, read, make_craft_queue())
}

@(test)
test_hand_crafting_runs_in_the_player_tick :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	players := []Player{make_player(player_start_on({4, 0, 4}), context.temp_allocator)}
	player := &players[0]
	_, technologies := make_test_recipes(content.items)
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, technologies, false, context.temp_allocator)
	inventory_add(player.inventory, content.items, test_item(content.items, "stone"), 5)
	refusal, _ := queue_crafts(&player.crafting, player.inventory, content.recipes, unlocks, test_recipe(content.recipes, "stone_furnace"), 1)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	for _ in 0 ..< 2 * TEST_TICK_RATE {
		tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	}
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "stone_furnace")), 1)
	testing.expect_value(t, player.crafting.count, 0)
}

// Work item 0156: the browser's count and ingredient states follow the
// planner. Three planks and a log: the planks are held, the sticks come
// from the log's planks, and the log covers a second pickaxe.
@(test)
test_planned_crafts_count_the_intermediates :: proc(t: ^testing.T) {
	test := make_crafting_test()
	pickaxe := test_recipe(test.recipes, "wooden_pickaxe")
	inventory_add(test.inventory, test.items, test_item(test.items, "plank"), 3)
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 1)
	planned := planned_crafts(test.queue, test.inventory, test.recipes, test.unlocks, pickaxe, HAND_MAKERS, context.temp_allocator)
	testing.expect_value(t, planned.count, 2)
	testing.expect(t, slice.equal(planned.inputs, []Planned_Input{{.Held, 3}, {.Craftable, 0}}))
	testing.expect(t, queue_accepts_crafts(test.queue, test.inventory, test.recipes, test.unlocks, pickaxe, 2))
	testing.expect(t, !queue_accepts_crafts(test.queue, test.inventory, test.recipes, test.unlocks, pickaxe, 3))
}

// Without the log the sticks lack a raw item: nothing is craftable.
@(test)
test_planned_crafts_without_a_raw_item :: proc(t: ^testing.T) {
	test := make_crafting_test()
	pickaxe := test_recipe(test.recipes, "wooden_pickaxe")
	inventory_add(test.inventory, test.items, test_item(test.items, "plank"), 3)
	planned := planned_crafts(test.queue, test.inventory, test.recipes, test.unlocks, pickaxe, HAND_MAKERS, context.temp_allocator)
	testing.expect_value(t, planned.count, 0)
	testing.expect(t, slice.equal(planned.inputs, []Planned_Input{{.Held, 3}, {.Missing, 0}}))
}

// A chain past HAND_CRAFT_PLAN_DEPTH counts 0 as the queue refuses it;
// a short one counts what its raw item covers.
@(test)
test_planned_crafts_honour_the_plan_depth :: proc(t: ^testing.T) {
	inventory := make_inventory(4, context.temp_allocator)
	length := HAND_CRAFT_PLAN_DEPTH + 2
	recipes, available := make_chain_recipes(length, cyclic = false)
	inventory.slots[0] = Item_Stack{Item_Id(length), 5}
	unlocks := Recipe_Unlocks{available = available}
	planned := planned_crafts(make_craft_queue(), inventory, recipes, unlocks, 0, HAND_MAKERS, context.temp_allocator)
	testing.expect_value(t, planned.count, 0)
	testing.expect(t, slice.equal(planned.inputs, []Planned_Input{{.Missing, 0}}))
	_, _, refusal, _ := plan_queue_crafts(make_craft_queue(), inventory, recipes, unlocks, 0, 1)
	testing.expect_value(t, refusal, Craft_Refusal.Plan_Too_Deep)
	recipes, available = make_chain_recipes(4, cyclic = false)
	inventory.slots[0] = Item_Stack{Item_Id(4), 5}
	unlocks = Recipe_Unlocks{available = available}
	planned = planned_crafts(make_craft_queue(), inventory, recipes, unlocks, 0, HAND_MAKERS, context.temp_allocator)
	testing.expect_value(t, planned.count, 5)
	testing.expect(t, slice.equal(planned.inputs, []Planned_Input{{.Craftable, 0}}))
}

// Queued runs use what they will take, and a full queue accepts nothing.
@(test)
test_planned_crafts_count_after_the_queue :: proc(t: ^testing.T) {
	test := make_crafting_test()
	pickaxe := test_recipe(test.recipes, "wooden_pickaxe")
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 2)
	testing.expect_value(t, planned_craft_count(test.queue, test.inventory, test.recipes, test.unlocks, pickaxe), 2)
	testing.expect_value(t, queue_test_craft(&test, pickaxe), Craft_Refusal.None)
	testing.expect_value(t, planned_craft_count(test.queue, test.inventory, test.recipes, test.unlocks, pickaxe), 1)
	full := make_craft_queue()
	for index in 0 ..< HAND_CRAFT_QUEUE_RUNS {
		full.runs[index] = Craft_Run{test_recipe(test.recipes, index % 2 == 0 ? "plank" : "stick"), 0}
	}
	full.count = HAND_CRAFT_QUEUE_RUNS
	testing.expect_value(t, planned_craft_count(full, test.inventory, test.recipes, test.unlocks, pickaxe), 0)
}

// Every count up to the limit the queue accepts is counted, no more.
@(test)
test_planned_craft_count_stops_at_the_limit :: proc(t: ^testing.T) {
	test := make_crafting_test()
	plank := test_recipe(test.recipes, "plank")
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 37)
	testing.expect_value(t, planned_craft_count(test.queue, test.inventory, test.recipes, test.unlocks, plank), 37)
	recipes, available := make_chain_recipes(1, cyclic = false)
	inventory := make_inventory(4, context.temp_allocator)
	for &slot in inventory.slots {
		slot = Item_Stack{Item_Id(1), max(u16)}
	}
	planned := planned_craft_count(make_craft_queue(), inventory, recipes, Recipe_Unlocks{available = available}, 0)
	testing.expect_value(t, planned, PLANNED_CRAFT_COUNT_LIMIT)
}

// Work item 0196: the stone cutting table's maker joins the hand queue's
// while its panel is open. Without it stone_brick is refused; at the
// table two bricks are cut in two runs of 96 ticks; a stone brick
// foundation queued at the table plans its bricks ahead of it, and the
// inventory view's makers refuse it for want of bricks.
@(test)
test_a_crafting_station_lets_the_hand_queue_cut_stone :: proc(t: ^testing.T) {
	content := make_test_content()
	simulation := make_simulation(test_game_config(), player_start_on({4, 0, 4}), content, content.technologies, false, {})
	defer destroy_simulation(&simulation)
	player := &simulation.players[0]
	stone, brick := test_item(content.items, "stone"), test_item(content.items, "stone_brick")
	brick_recipe := test_recipe(content.recipes, "stone_brick")
	inventory_add(player.inventory, content.items, stone, 4)
	craft := Queued_Player_Command{player = 0, command = Craft_Command{recipe = brick_recipe, count = 2}}
	apply_player_command(&simulation, content, craft)
	testing.expect_value(t, player.crafting.count, 0)
	table := add_entity(&simulation.world.entities, content.machines, test_machine(content.machines, "stone_cutting_table"), {8, 1, 8}, 0)
	player.open_machine = table
	testing.expect_value(t, player_craft_makers(&simulation.world.entities, content.machines, player^), Recipe_Makers{.Hand, .Stone_Cutting})
	apply_player_command(&simulation, content, craft)
	testing.expect_value(t, player.crafting.count, 1)
	for _ in 0 ..< 2 * 96 {
		advance_crafting(&player.crafting, player.inventory, content.recipes, content.items, TEST_TICK_RATE)
	}
	testing.expect_value(t, inventory_count(player.inventory, brick), 2)
	testing.expect_value(t, inventory_count(player.inventory, stone), 0)

	clear_inventory(player.inventory)
	inventory_add(player.inventory, content.items, stone, 4)
	record_obtained_item(&simulation.unlocks, brick)
	refresh_available_recipes(&simulation.unlocks, content.recipes)
	foundation := test_recipe(content.recipes, "stone_brick_foundation")
	_, _, refusal, shortage := plan_queue_crafts(player.crafting, player.inventory, content.recipes, simulation.unlocks, foundation, 1)
	testing.expect_value(t, refusal, Craft_Refusal.Missing_Ingredients)
	testing.expect_value(t, shortage.item, brick)
	makers := player_craft_makers(&simulation.world.entities, content.machines, player^)
	refusal, _ = queue_crafts(&player.crafting, player.inventory, content.recipes, simulation.unlocks, foundation, 1, makers)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	testing.expect_value(t, player.crafting.count, 2)
	testing.expect_value(t, player.crafting.runs[0], Craft_Run{brick_recipe, 2})
	testing.expect_value(t, player.crafting.runs[1], Craft_Run{foundation, 1})

	// The station's browser keeps the inventory browser's filter: opened,
	// then closed with Back or by the pause menu's Resume, the filter is
	// what it was.
	state: Ui_State
	browser := make_recipe_browser()
	defer destroy_recipe_browser(&browser)
	browser.filter.category, browser.filter.tags = .Logistics, {1}
	before := browser.filter
	maker_category := station_recipe_category(content.recipes, .Stone_Cutting, browser.filter.category)
	testing.expect_value(t, station_categories(content.recipes, .Stone_Cutting), Recipe_Categories{.Materials})
	push_screen(&state.screens, .Machine)
	open_station_recipes(&state, &browser, table, maker_category)
	testing.expect_value(t, top_screen(state.screens), Screen.Recipes)
	testing.expect_value(t, browser.filter.category, Recipe_Category.Materials)
	testing.expect_value(t, browser.filter.tags, Recipe_Tag_Set{})
	pop_screen(&state.screens)
	open_station_recipes(&state, &browser, table, maker_category)
	testing.expect_value(t, state.screens.count, 0)
	testing.expect_value(t, browser.station, NO_ENTITY)
	testing.expect_value(t, browser.filter, before)
	push_screen(&state.screens, .Machine)
	open_station_recipes(&state, &browser, table, maker_category)
	close_station_recipes(&browser)
	testing.expect_value(t, browser.filter, before)
}
