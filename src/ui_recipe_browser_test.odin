package game

import "core:slice"
import "core:testing"

Browser_Test :: struct {
	using crafting: Crafting_Test,
	names:          []string,
	order:          []int,
}

// Names from the recipe ids, so the tests need no string table.
make_browser_test :: proc(unlock_all := false) -> Browser_Test {
	test := Browser_Test {
		crafting = make_crafting_test(unlock_all),
	}
	test.names = make([]string, len(test.recipes.recipes), context.temp_allocator)
	for recipe, index in test.recipes.recipes {
		test.names[index] = recipe.id
	}
	test.order = recipe_name_order(test.names, context.temp_allocator)
	return test
}

visible_ids :: proc(test: Browser_Test, filter: Recipe_Filter) -> []string {
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, test.queue, context.temp_allocator)
	visible := filter_recipes(test.recipes, test.order, filter, craftable, nil, context.temp_allocator)
	ids := make([]string, len(visible), context.temp_allocator)
	for recipe, index in visible {
		ids[index] = test.names[recipe]
	}
	return ids
}

tag_index :: proc(recipes: Recipe_Registry, tag: string) -> int {
	index, found := slice.linear_search(recipes.tag_names, tag)
	assert(found, tag)
	return index
}

@(test)
test_browser_filters_by_tab_tag_and_craftable :: proc(t: ^testing.T) {
	test := make_browser_test()
	science := visible_ids(test, {category = .Science})
	testing.expect(t, slice.equal(science, []string{"science_pack_1", "science_pack_2"}))
	tools := visible_ids(test, {category = .Tools})
	testing.expect(t, slice.equal(tools, []string{"geologists_hammer", "iron_axe", "iron_pickaxe", "iron_shovel", "magnetometer", "stone_axe", "stone_pickaxe", "stone_shovel", "thumper_charge", "wooden_axe", "wooden_pickaxe", "wooden_shovel"}))
	// Tags narrow: every selected tag must be present.
	iron := tag_index(test.recipes, "iron")
	smelting := tag_index(test.recipes, "smelting")
	iron_smelting := visible_ids(test, {category = .Materials, tags = {iron, smelting}})
	testing.expect(t, slice.equal(iron_smelting, []string{"charcoal_steel", "iron_plate", "low_grade_iron_plate", "steel"}))
	testing.expect_value(t, len(visible_ids(test, {category = .Tools, tags = {smelting}})), 0)
	testing.expect(t, iron in category_tags(test.recipes, .Tools))
	testing.expect(t, smelting not_in category_tags(test.recipes, .Tools))
	// Can craft now: the queue accepts a craft, intermediates included
	// (0156): a log makes the planks the stick and the plank shapes need.
	testing.expect_value(t, len(visible_ids(test, {category = .Materials, craftable_only = true})), 0)
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 1)
	craftable := visible_ids(test, {category = .Materials, craftable_only = true})
	testing.expectf(t, slice.equal(craftable, []string{"plank", "plank_slab", "plank_stairs", "stick"}), "%v", craftable)
}

@(test)
test_browser_letter_jump :: proc(t: ^testing.T) {
	test := make_browser_test()
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, test.queue, context.temp_allocator)
	visible := filter_recipes(test.recipes, test.order, {category = .Logistics}, craftable, nil, context.temp_allocator)
	// belt, belt_2, belt_lift, ..., burner_inserter, fast_inserter, filter_inserter, inserter, iron_chest, ...
	testing.expect_value(t, test.names[visible[recipe_position_for_letter(test.names, visible, 'f')]], "fast_inserter")
	testing.expect_value(t, test.names[visible[recipe_position_for_letter(test.names, visible, 'I')]], "inserter")
	// No logistics recipe starts with g or h: the next letter is taken.
	testing.expect_value(t, test.names[visible[recipe_position_for_letter(test.names, visible, 'g')]], "inserter")
	testing.expect_value(t, recipe_position_for_letter(test.names, visible, 'z'), -1)
	testing.expect_value(t, recipe_position_for_letter(test.names, visible, 'a'), 0)
	testing.expect_value(t, letter_for_wheel_slot(0), 'a')
	testing.expect_value(t, letter_for_wheel_slot(25), 'z')
	testing.expect(t, letter_jumps_on_keyboard('b'))
	testing.expect(t, letter_jumps_on_keyboard('Z'))
	testing.expect(t, !letter_jumps_on_keyboard('w'))
	testing.expect(t, !letter_jumps_on_keyboard(0))
}

@(test)
test_silhouettes_hide_ingredients :: proc(t: ^testing.T) {
	test := make_browser_test()
	circuit := test_recipe(test.recipes, "electronic_circuit")
	hidden := recipe_detail(test.recipes, test.unlocks, circuit, context.temp_allocator)
	testing.expect(t, !hidden.revealed)
	testing.expect_value(t, len(hidden.inputs), 0)
	testing.expect_value(t, len(hidden.outputs), 0)
	testing.expect_value(t, len(hidden.used_in), 0)
	gear := recipe_detail(test.recipes, test.unlocks, test_recipe(test.recipes, "iron_gear"), context.temp_allocator)
	testing.expect(t, gear.revealed)
	testing.expect_value(t, gear.inputs[0], Item_Stack{test_item(test.items, "iron_plate"), 2})
	testing.expect_value(t, len(gear.made_by), 1)
	testing.expect(t, len(gear.used_in) >= 10)
	all := make_browser_test(unlock_all = true)
	testing.expect(t, recipe_detail(all.recipes, all.unlocks, circuit, context.temp_allocator).revealed)
}

@(test)
test_graph_step_adjusts_the_filter :: proc(t: ^testing.T) {
	test := make_browser_test()
	wood := tag_index(test.recipes, "wood")
	filter := Recipe_Filter{category = .Materials, tags = {wood}, craftable_only = true}
	lab := test.recipes.recipes[test_recipe(test.recipes, "lab")]
	shown := filter_showing_recipe(filter, lab, false, true)
	testing.expect_value(t, shown.category, Recipe_Category.Machines)
	testing.expect_value(t, shown.tags, Recipe_Tag_Set{})
	testing.expect(t, !shown.craftable_only)
	chest := test.recipes.recipes[test_recipe(test.recipes, "wooden_chest")]
	kept := filter_showing_recipe(filter, chest, true, true)
	testing.expect_value(t, kept.tags, Recipe_Tag_Set{wood})
	testing.expect(t, kept.craftable_only)
}

// Work item 0091: a locked recipe reached through the graph drops the
// unlocked only filter, an available one keeps it.
@(test)
test_graph_step_to_a_locked_recipe_drops_unlocked_only :: proc(t: ^testing.T) {
	test := make_browser_test()
	filter := make_recipe_browser().filter
	circuit := test_recipe(test.recipes, "electronic_circuit")
	locked := filter_showing_recipe(filter, test.recipes.recipes[circuit], false, recipe_is_available(test.unlocks, circuit))
	testing.expect(t, !locked.available_only)
	plank := test_recipe(test.recipes, "plank")
	kept := filter_showing_recipe(filter, test.recipes.recipes[plank], false, recipe_is_available(test.unlocks, plank))
	testing.expect(t, kept.available_only)
}

// Work item 0091: the browser opens with unlocked only on, which hides the
// locked recipes; turning the toggle off shows them as silhouettes.
@(test)
test_default_filter_hides_locked_recipes :: proc(t: ^testing.T) {
	test := make_browser_test()
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, test.queue, context.temp_allocator)
	filter := make_recipe_browser().filter
	testing.expect(t, filter.available_only)
	filter.category = .Science
	testing.expect_value(t, len(filter_recipes(test.recipes, test.order, filter, craftable, test.unlocks.available, context.temp_allocator)), 0)
	filter.available_only = false
	testing.expect_value(t, len(filter_recipes(test.recipes, test.order, filter, craftable, test.unlocks.available, context.temp_allocator)), 2)
	filter.category = .Materials
	filter.available_only = true
	for recipe in filter_recipes(test.recipes, test.order, filter, craftable, test.unlocks.available, context.temp_allocator) {
		testing.expectf(t, recipe_is_available(test.unlocks, recipe), "%s is locked", test.names[recipe])
	}
}

// Work item 0156: the kept plans follow the inventory, the queue and the
// focused recipe, and not the front craft's progress.
@(test)
test_recipe_plans_follow_what_the_planner_reads :: proc(t: ^testing.T) {
	test := make_browser_test()
	plans := make_recipe_browser().plans
	defer destroy_recipe_plans(&plans)
	plank := test_recipe(test.recipes, "plank")
	pickaxe := test_recipe(test.recipes, "wooden_pickaxe")
	refresh_craftable_recipes(&plans, test.recipes, test.unlocks, test.inventory, test.queue)
	testing.expect_value(t, len(plans.craftable), len(test.recipes.recipes))
	testing.expect(t, !plans.craftable[pickaxe])
	refresh_recipe_detail_plan(&plans, test.recipes, test.unlocks, test.inventory, test.queue, pickaxe)
	testing.expect_value(t, plans.detail_count, 0)
	testing.expect(t, slice.equal(plans.detail_inputs[:], []Planned_Input{{.Missing, 0}, {.Missing, 0}}))
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 2)
	refresh_craftable_recipes(&plans, test.recipes, test.unlocks, test.inventory, test.queue)
	testing.expect(t, plans.craftable[pickaxe])
	refresh_recipe_detail_plan(&plans, test.recipes, test.unlocks, test.inventory, test.queue, pickaxe)
	testing.expect_value(t, plans.detail_count, 2)
	testing.expect(t, slice.equal(plans.detail_inputs[:], []Planned_Input{{.Craftable, 0}, {.Craftable, 0}}))
	refresh_recipe_detail_plan(&plans, test.recipes, test.unlocks, test.inventory, test.queue, plank)
	testing.expect_value(t, plans.detail_count, 2)
	testing.expect(t, slice.equal(plans.detail_inputs[:], []Planned_Input{{.Held, 2}}))
	// A queued pickaxe leaves one log: one more pickaxe. Its progress
	// keeps the key.
	testing.expect_value(t, queue_test_craft(&test.crafting, pickaxe), Craft_Refusal.None)
	refresh_recipe_detail_plan(&plans, test.recipes, test.unlocks, test.inventory, test.queue, pickaxe)
	testing.expect_value(t, plans.detail_count, 1)
	// The plank row shows the log the queue leaves, not the two held.
	refresh_recipe_detail_plan(&plans, test.recipes, test.unlocks, test.inventory, test.queue, plank)
	testing.expect_value(t, inventory_count(test.inventory, test_item(test.items, "log")), 2)
	testing.expect(t, slice.equal(plans.detail_inputs[:], []Planned_Input{{.Held, 1}}))
	key := recipe_plan_key(test.queue, test.inventory, test.unlocks.available)
	test.queue.progress_ticks += 5
	testing.expect_value(t, recipe_plan_key(test.queue, test.inventory, test.unlocks.available), key)
}

@(test)
test_newly_pressed_letter :: proc(t: ^testing.T) {
	previous := Raw_Keyboard{key_count = 1}
	previous.keys_down[0] = 'B'
	current := previous
	current.key_count = 3
	current.keys_down[1] = 256
	current.keys_down[2] = 'K'
	testing.expect_value(t, newly_pressed_letter(previous, current), 'k')
	testing.expect_value(t, newly_pressed_letter(current, current), 0)
}

// Choosing an assembler's recipe: available assembler recipes only,
// whatever the craftable toggle says.
@(test)
test_browser_selection_mode_lists_assembler_recipes :: proc(t: ^testing.T) {
	test := make_browser_test()
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, test.queue, context.temp_allocator)
	selection := selection_filter({category = .Materials, craftable_only = true}, .Assembler)
	visible := filter_recipes(test.recipes, test.order, selection, craftable, test.unlocks.available, context.temp_allocator)
	ids := make([]string, len(visible), context.temp_allocator)
	for recipe, index in visible {
		ids[index] = test.names[recipe]
	}
	// Plank, stick, the slabs and the stairs are start recipes; the furnace
	// recipes are left out.
	testing.expectf(t, slice.equal(ids, []string{"concrete_slab", "concrete_stairs", "plank", "plank_slab", "plank_stairs", "stick", "stone_slab", "stone_stairs"}), "%v", ids)
	// Science pack 1 is a discovery recipe: listed once discovered.
	science := selection_filter({category = .Science}, .Assembler)
	testing.expect_value(t, len(filter_recipes(test.recipes, test.order, science, craftable, test.unlocks.available, context.temp_allocator)), 0)
	record_obtained_item(&test.unlocks, test_item(test.items, "copper_plate"))
	record_obtained_item(&test.unlocks, test_item(test.items, "iron_gear"))
	refresh_available_recipes(&test.unlocks, test.recipes)
	testing.expect_value(t, len(filter_recipes(test.recipes, test.order, science, craftable, test.unlocks.available, context.temp_allocator)), 1)
}

// Work item 0091: the ingredient, stack and craft count lines from the
// shipped string table.
@(test)
test_recipe_detail_lines :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	test := make_browser_test()
	stone := test_item(test.items, "stone")
	testing.expect_value(t, ingredient_line(5, item_name(test.items, stone), {.Held, 13}), "13 / 5 Stone")
	testing.expect_value(t, ingredient_line(5, item_name(test.items, stone), {.Craftable, 0}), "0 / 5 Stone, craftable")
	testing.expect_value(t, ingredient_line(5, item_name(test.items, stone), {.Missing, 2}), "2 / 5 Stone")
	testing.expect_value(t, stack_line(Item_Stack{stone, 5}, test.items), "5 × Stone")
	testing.expect_value(t, can_craft_text(2), "Can craft 2")
	testing.expect_value(t, can_craft_text(0), "Can craft 0")
}

// Work item 0276: one press crafts one, five with R1 held, the planner's
// most with L1 held, and at least one so a refusal toasts.
@(test)
test_craft_count_follows_the_modifier :: proc(t: ^testing.T) {
	testing.expect_value(t, craft_count(.None, 40), 1)
	testing.expect_value(t, craft_count(.Five, 40), RECIPE_CRAFT_MANY_COUNT)
	testing.expect_value(t, craft_count(.Most, 40), 40)
	testing.expect_value(t, craft_count(.Most, 0), 1)
}

// The audit's pod crafting bench, a station with the hand maker.
audit_crafting_bench :: proc(audit: ^Ui_Audit) -> Entity_Handle {
	for foundation in audit.simulation.world.entities.foundations.entries {
		if foundation.alive && audit.content.machines.machines[foundation.machine].kind == .Crafting_Bench {
			return foundation.handle
		}
	}
	return NO_ENTITY
}

// The recipe browser open on the plank recipe's focused row, from the
// inventory's strip or (station) a crafting station's panel, with the
// inventory holding logs and nothing queued. Returns the row's id.
open_recipe_browser_on_plank :: proc(audit: ^Ui_Audit, state: ^Ui_State, station: Entity_Handle, logs: u16) -> Ui_Id {
	player := &audit.simulation.players[0]
	plank := test_recipe(audit.content.recipes, "plank")
	player.crafting = {}
	slice.fill(player.inventory.slots, EMPTY_STACK)
	player.inventory.slots[3] = {test_item(audit.content.items, "log"), logs}
	player.open_machine = station
	clear(&audit.simulation.player_commands)
	browser := &audit.views.recipe_browser
	browser.station = station
	browser.filter.category = audit.content.recipes.recipes[plank].category
	browser.focused_recipe = plank
	if station != NO_ENTITY {
		push_screen(&state.screens, .Machine)
	}
	push_screen(&state.screens, .Recipes)
	screen_test_frame(audit, state, {})
	return recipe_row_id(ui_hash(ui_hash(0, "recipes", -1), "recipe_list", -1), plank)
}

// Work item 0276: A on a focused recipe queues one craft, with R1 held
// five, with L1 held the most the planner accepts. With nothing to craft
// from L1 with A queues nothing and toasts. X cancels the newest craft.
// The same in the station browser (the pod's crafting bench).
@(test)
test_modifiers_with_a_on_a_recipe :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	bench := audit_crafting_bench(audit)
	if !testing.expect(t, bench != NO_ENTITY) {
		return
	}
	plank := test_recipe(audit.content.recipes, "plank")
	player := &audit.simulation.players[0]
	for station in ([2]Entity_Handle{NO_ENTITY, bench}) {
		state := Ui_State{theme = audit.theme}
		defer destroy_ui_state(&state)
		row := open_recipe_browser_on_plank(audit, &state, station, 20)
		testing.expect_value(t, state.focus, row)
		screen_context := audit_screen_context(audit)
		most := planned_craft_count(player.crafting, player.inventory, audit.content.recipes, screen_context.unlocks^, plank, screen_craft_makers(screen_context), screen_context.free_crafting)
		testing.expectf(t, most > RECIPE_CRAFT_MANY_COUNT, "the planner accepts %d", most)
		presses := [?]struct {
			input: Ui_Input,
			count: int,
		}{{{confirm = true}, 1}, {{confirm = true, modifier_five = true}, RECIPE_CRAFT_MANY_COUNT}, {{confirm = true, modifier_most = true}, most}}
		for press in presses {
			screen_test_frame(audit, &state, press.input)
			testing.expectf(t, len(audit.simulation.player_commands) == 1, "count %d: %d commands", press.count, len(audit.simulation.player_commands))
			craft, crafts := last_queued_command(audit).(Craft_Command)
			testing.expectf(t, crafts && craft == Craft_Command{recipe = plank, count = press.count}, "station %v: %v", station, last_queued_command(audit))
			clear(&audit.simulation.player_commands)
		}
		// One craft queued, X cancels it.
		screen_test_frame(audit, &state, {confirm = true})
		apply_player_commands(&audit.simulation, audit.content)
		testing.expect_value(t, player.crafting.count, 1)
		screen_test_frame(audit, &state, {context_action = true})
		_, cancels := last_queued_command(audit).(Cancel_Craft_Command)
		testing.expect(t, cancels)
		// Nothing to craft from: L1 with A queues nothing and toasts.
		player.crafting = {}
		slice.fill(player.inventory.slots, EMPTY_STACK)
		clear(&audit.simulation.player_commands)
		toasts := len(state.toasts)
		screen_test_frame(audit, &state, {confirm = true, modifier_most = true})
		testing.expect_value(t, len(audit.simulation.player_commands), 0)
		testing.expect_value(t, len(state.toasts), toasts + 1)
	}
	audit.views.recipe_browser.station = NO_ENTITY
}

// Work item 0276: where a screen gives the modifiers no meaning, A with one
// held acts as A alone: a technology row queues its research, the
// picker's row chooses its recipe, the pause menu's Resume closes it.
@(test)
test_modifiers_where_five_and_most_mean_nothing :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	simulation.records.research.queued = false
	available := NO_TECHNOLOGY
	for _, index in audit.content.technologies.technologies {
		if technology_status(audit.content.technologies, simulation.unlocks, index) == .Available {
			available = index
			break
		}
	}
	if !testing.expect(t, available != NO_TECHNOLOGY) {
		return
	}
	audit.views.technology_browser.focused = available
	technologies := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&technologies)
	push_screen(&technologies.screens, .Technologies)
	screen_test_frame(audit, &technologies, {})
	screen_test_frame(audit, &technologies, {})
	testing.expect_value(t, technologies.focus, technology_row_id(ui_hash(ui_hash(0, "technologies", -1), "technology_list", -1), available))
	screen_test_frame(audit, &technologies, {confirm = true, modifier_five = true})
	testing.expect_value(t, last_queued_command(audit).(Research_Command), Research_Command{technology = available})
	clear(&simulation.player_commands)
	// The picker.
	picker := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&picker)
	for &assembler in simulation.world.entities.assemblers.entries {
		if !assembler.alive || audit.content.machines.machines[assembler.machine].recipe_choice == .Fixed {
			continue
		}
		push_screen(&picker.screens, .Machine)
		push_screen(&picker.screens, .Recipes)
		audit.views.recipe_browser.selecting_for = assembler.handle
		audit.views.recipe_browser.focused_recipe = NO_RECIPE
		simulation.players[0].open_machine = assembler.handle
		screen_test_frame(audit, &picker, {})
		screen_test_frame(audit, &picker, {})
		focused := audit.views.recipe_browser.focused_recipe
		screen_test_frame(audit, &picker, {confirm = true, modifier_most = true})
		chosen, chooses := last_queued_command(audit).(Assembler_Recipe_Command)
		testing.expectf(t, chooses && chosen == Assembler_Recipe_Command{assembler = assembler.handle, recipe = focused}, "%v", last_queued_command(audit))
		testing.expect_value(t, top_screen(picker.screens), Screen.Machine)
		break
	}
	audit.views.recipe_browser.selecting_for = NO_ENTITY
	// The pause menu: the focus starts on Resume.
	pause := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&pause)
	push_screen(&pause.screens, .Pause)
	screen_test_frame(audit, &pause, {})
	screen_test_frame(audit, &pause, {confirm = true, modifier_five = true})
	testing.expect_value(t, pause.screens.count, 0)
}

// Work item 0276: the tab step (the right stick's flick, `[` and `]`)
// steps the recipe categories wherever the focus is and drops the tags,
// with the inventory's strip and in the picker. The window step leaves
// the picker's screen and category alone.
@(test)
test_recipe_categories_follow_the_tab_step :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.views.recipe_browser
	strip := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&strip)
	push_screen(&strip.screens, .Recipes)
	browser.filter.category, browser.filter.tags = .Materials, {0}
	screen_test_frame(audit, &strip, {})
	screen_test_frame(audit, &strip, {tab_next = true})
	testing.expect_value(t, browser.filter.category, Recipe_Category.Components)
	testing.expect_value(t, browser.filter.tags, Recipe_Tag_Set{})
	testing.expect_value(t, top_screen(strip.screens), Screen.Recipes)
	screen_test_frame(audit, &strip, {tab_previous = true})
	testing.expect_value(t, browser.filter.category, Recipe_Category.Materials)
	testing.expect_value(t, top_screen(strip.screens), Screen.Recipes)
	simulation := &audit.simulation
	for &assembler in simulation.world.entities.assemblers.entries {
		if !assembler.alive || audit.content.machines.machines[assembler.machine].recipe_choice == .Fixed {
			continue
		}
		picker := Ui_State{theme = audit.theme}
		defer destroy_ui_state(&picker)
		push_screen(&picker.screens, .Machine)
		push_screen(&picker.screens, .Recipes)
		browser.selecting_for = assembler.handle
		simulation.players[0].open_machine = assembler.handle
		browser.filter.tags = {0}
		screen_test_frame(audit, &picker, {})
		screen_test_frame(audit, &picker, {tab_next = true})
		testing.expect_value(t, browser.filter.category, Recipe_Category.Components)
		testing.expect_value(t, browser.filter.tags, Recipe_Tag_Set{})
		screen_test_frame(audit, &picker, {window_next = true})
		testing.expect_value(t, browser.filter.category, Recipe_Category.Components)
		testing.expect_value(t, top_screen(picker.screens), Screen.Recipes)
		testing.expect_value(t, picker.screens.count, 2)
		screen_test_frame(audit, &picker, {tab_previous = true})
		testing.expect_value(t, browser.filter.category, Recipe_Category.Materials)
		break
	}
	browser.selecting_for = NO_ENTITY
}

// Free crafting (0234): every unlocked hand recipe is craftable from an
// empty inventory, every ingredient shows as held.
@(test)
test_free_crafting_marks_every_unlocked_recipe_craftable :: proc(t: ^testing.T) {
	test := make_browser_test()
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, test.queue, context.temp_allocator, HAND_MAKERS, true)
	for recipe, index in test.recipes.recipes {
		testing.expectf(t, craftable[index] == (test.unlocks.available[index] && .Hand in recipe.made_in), "%s", recipe.id)
	}
	drill := test_recipe(test.recipes, "burner_mining_drill")
	paid := craftable_recipes(test.recipes, test.unlocks, test.inventory, test.queue, context.temp_allocator)
	testing.expect(t, !paid[drill])
	testing.expect(t, recipe_plan_key(test.queue, test.inventory, test.unlocks.available, HAND_MAKERS, false) != recipe_plan_key(test.queue, test.inventory, test.unlocks.available, HAND_MAKERS, true))
	planned := planned_crafts(test.queue, test.inventory, test.recipes, test.unlocks, drill, HAND_MAKERS, context.temp_allocator, true)
	testing.expect_value(t, planned.count, PLANNED_CRAFT_COUNT_LIMIT)
	for input in planned.inputs {
		testing.expect_value(t, input.state, Planned_Input_State.Held)
	}
}
