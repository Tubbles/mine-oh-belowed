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
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, context.temp_allocator)
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
	testing.expect(t, slice.equal(tools, []string{"geologists_hammer", "iron_pickaxe", "magnetometer", "stone_pickaxe", "thumper_charge", "wooden_pickaxe"}))
	// Tags narrow: every selected tag must be present.
	iron := tag_index(test.recipes, "iron")
	smelting := tag_index(test.recipes, "smelting")
	iron_smelting := visible_ids(test, {category = .Materials, tags = {iron, smelting}})
	testing.expect(t, slice.equal(iron_smelting, []string{"charcoal_steel", "iron_plate", "low_grade_iron_plate", "steel"}))
	testing.expect_value(t, len(visible_ids(test, {category = .Tools, tags = {smelting}})), 0)
	testing.expect(t, iron in category_tags(test.recipes, .Tools))
	testing.expect(t, smelting not_in category_tags(test.recipes, .Tools))
	// Can craft now: available, by hand, ingredients at hand.
	testing.expect_value(t, len(visible_ids(test, {category = .Materials, craftable_only = true})), 0)
	inventory_add(test.inventory, test.items, test_item(test.items, "log"), 1)
	testing.expect(t, slice.equal(visible_ids(test, {category = .Materials, craftable_only = true}), []string{"plank"}))
}

@(test)
test_browser_letter_jump :: proc(t: ^testing.T) {
	test := make_browser_test()
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, context.temp_allocator)
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
	shown := filter_showing_recipe(filter, lab, false)
	testing.expect_value(t, shown.category, Recipe_Category.Machines)
	testing.expect_value(t, shown.tags, Recipe_Tag_Set{})
	testing.expect(t, !shown.craftable_only)
	chest := test.recipes.recipes[test_recipe(test.recipes, "wooden_chest")]
	kept := filter_showing_recipe(filter, chest, true)
	testing.expect_value(t, kept.tags, Recipe_Tag_Set{wood})
	testing.expect(t, kept.craftable_only)
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
	craftable := craftable_recipes(test.recipes, test.unlocks, test.inventory, context.temp_allocator)
	selection := selection_filter({category = .Materials, craftable_only = true}, .Assembler)
	visible := filter_recipes(test.recipes, test.order, selection, craftable, test.unlocks.available, context.temp_allocator)
	ids := make([]string, len(visible), context.temp_allocator)
	for recipe, index in visible {
		ids[index] = test.names[recipe]
	}
	// Plank and stick are start recipes; the furnace recipes are left out.
	testing.expect(t, slice.equal(ids, []string{"plank", "stick"}))
	// Science pack 1 is a discovery recipe: listed once discovered.
	science := selection_filter({category = .Science}, .Assembler)
	testing.expect_value(t, len(filter_recipes(test.recipes, test.order, science, craftable, test.unlocks.available, context.temp_allocator)), 0)
	record_obtained_item(&test.unlocks, test_item(test.items, "copper_plate"))
	record_obtained_item(&test.unlocks, test_item(test.items, "iron_gear"))
	refresh_available_recipes(&test.unlocks, test.recipes)
	testing.expect_value(t, len(filter_recipes(test.recipes, test.order, science, craftable, test.unlocks.available, context.temp_allocator)), 1)
}
