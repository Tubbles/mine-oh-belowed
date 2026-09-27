package game

import "core:slice"
import "core:testing"

make_test_recipes :: proc(items: Item_Registry) -> (Recipe_Registry, Technology_Registry) {
	file, error := parse_recipes_file(#load("../data/recipes.sjson"), context.temp_allocator)
	assert(error == nil)
	recipes, problem := resolve_recipe_registry(file, items, make_test_fluids(), context.temp_allocator)
	assert(problem == "", problem)
	technology_file, technology_error := parse_technologies_file(#load("../data/technologies.sjson"), context.temp_allocator)
	assert(technology_error == nil)
	technologies, technology_problem := resolve_technology_registry(technology_file, items, recipes, context.temp_allocator)
	assert(technology_problem == "", technology_problem)
	return recipes, technologies
}

test_recipe :: proc(recipes: Recipe_Registry, id: string) -> int {
	recipe := find_recipe(recipes, id)
	assert(recipe != NO_RECIPE, id)
	return recipe
}

@(test)
test_shipped_recipes_resolve :: proc(t: ^testing.T) {
	items := make_test_items()
	recipes, technologies := make_test_recipes(items)
	testing.expect_value(t, len(recipes.recipes), 69)
	testing.expect_value(t, len(technologies.technologies), 12)
	plank := recipes.recipes[test_recipe(recipes, "plank")]
	testing.expect_value(t, plank.outputs[0], Item_Stack{test_item(items, "plank"), 4})
	testing.expect_value(t, plank.milliseconds, 500)
	testing.expect_value(t, plank.made_in, Recipe_Makers{.Hand, .Assembler})
	testing.expect_value(t, plank.name_key, "item_plank")
	testing.expect_value(t, plank.channel, Recipe_Channel.Start)
	steel := recipes.recipes[test_recipe(recipes, "steel")]
	testing.expect_value(t, steel.channel, Recipe_Channel.Research)
	testing.expect_value(t, technologies.technologies[steel.technology].id, "steel_processing")
	testing.expect_value(t, recipes.recipes[test_recipe(recipes, "iron_gear")].technology, NO_TECHNOLOGY)
	// Furnace lookup replaces the old hardcoded smelting table.
	testing.expect_value(t, furnace_recipe_for(recipes, test_item(items, "hematite")), test_recipe(recipes, "iron_plate"))
	testing.expect_value(t, furnace_recipe_for(recipes, test_item(items, "log")), test_recipe(recipes, "charcoal"))
	testing.expect_value(t, furnace_recipe_for(recipes, test_item(items, "copper_plate")), NO_RECIPE)
	testing.expect(t, !item_is_smeltable(recipes, test_item(items, "coal")))
}

@(test)
test_recipe_and_technology_strings_exist :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect(t, error == nil)
	recipes, technologies := make_test_recipes(make_test_items())
	keys := make([dynamic]string, context.temp_allocator)
	for recipe in recipes.recipes {
		append(&keys, recipe.name_key)
	}
	for tag in recipes.tag_names {
		append(&keys, recipe_tag_key(tag))
	}
	for technology in technologies.technologies {
		append(&keys, technology.name_key)
	}
	for category in Recipe_Category {
		append(&keys, recipe_category_key(category))
	}
	for maker in Recipe_Maker {
		append(&keys, recipe_maker_key(maker))
	}
	for key in craft_refusal_keys {
		if key != "" {
			append(&keys, key)
		}
	}
	for key in keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
}

@(test)
test_graph_queries_on_shipped_data :: proc(t: ^testing.T) {
	items := make_test_items()
	recipes, _ := make_test_recipes(items)
	gear := test_item(items, "iron_gear")
	made_by := recipes_making(recipes, gear, context.temp_allocator)
	testing.expect_value(t, len(made_by), 1)
	testing.expect_value(t, made_by[0], test_recipe(recipes, "iron_gear"))
	used_in := recipes_using(recipes, gear, context.temp_allocator)
	testing.expect(t, len(used_in) >= 10)
	for id in ([?]string{"burner_mining_drill", "belt", "science_pack_1", "lab", "steam_engine"}) {
		testing.expectf(t, slice.contains(used_in, test_recipe(recipes, id)), "iron gear not used in %s", id)
	}
	testing.expect(t, !slice.contains(used_in, test_recipe(recipes, "iron_gear")))
	testing.expect_value(t, len(recipes_using(recipes, test_item(items, "iron_rod"), context.temp_allocator)), 0)
}

test_recipe_definition :: proc() -> Recipe_Definition {
	inputs := make([]Recipe_Ingredient_Definition, 1, context.temp_allocator)
	inputs[0] = {item = "log", count = 1}
	outputs := make([]Recipe_Ingredient_Definition, 1, context.temp_allocator)
	outputs[0] = {item = "plank", count = 4}
	made_in := make([]string, 1, context.temp_allocator)
	made_in[0] = "hand"
	return Recipe_Definition {
		id = "test",
		inputs = inputs,
		outputs = outputs,
		seconds = 0.5,
		made_in = made_in,
		category = "materials",
		channel = "start",
	}
}

resolve_test_recipes :: proc(definitions: []Recipe_Definition) -> string {
	registry, problem := resolve_recipe_registry(Recipes_File{recipes = definitions}, make_test_items(), make_test_fluids(), context.temp_allocator)
	if problem == "" {
		destroy_recipe_registry(registry, context.temp_allocator)
	}
	return problem
}

@(test)
test_recipe_data_rejects_bad_definitions :: proc(t: ^testing.T) {
	base := test_recipe_definition()
	testing.expect_value(t, resolve_test_recipes({base}), "")
	unknown_item := base
	unknown_item.inputs = {{item = "no_such_item", count = 1}}
	testing.expect(t, resolve_test_recipes({unknown_item}) != "")
	no_outputs := base
	no_outputs.outputs = {}
	testing.expect(t, resolve_test_recipes({no_outputs}) != "")
	no_makers := base
	no_makers.made_in = {}
	testing.expect(t, resolve_test_recipes({no_makers}) != "")
	unknown_maker := base
	unknown_maker.made_in = {"oven"}
	testing.expect(t, resolve_test_recipes({unknown_maker}) != "")
	fluid := base
	fluid.inputs = {{fluid = "water", count = 100}}
	testing.expect(t, resolve_test_recipes({fluid}) != "")
	zero_count := base
	zero_count.outputs = {{item = "plank", count = 0}}
	testing.expect(t, resolve_test_recipes({zero_count}) != "")
	twice := base
	twice.inputs = {{item = "log", count = 1}, {item = "log", count = 2}}
	testing.expect(t, resolve_test_recipes({twice}) != "")
	research := base
	research.channel = "research"
	testing.expect(t, resolve_test_recipes({research}) != "")
	unknown_category := base
	unknown_category.category = "misc"
	testing.expect(t, resolve_test_recipes({unknown_category}) != "")
	testing.expect(t, resolve_test_recipes({base, base}) != "")
	// Two furnace recipes may not share an input.
	smelt := base
	smelt.made_in = {"furnace"}
	other := smelt
	other.id = "other"
	other.outputs = {{item = "charcoal", count = 1}}
	testing.expect(t, resolve_test_recipes({smelt, other}) != "")
}

@(test)
test_technology_data_rejects_bad_links :: proc(t: ^testing.T) {
	items := make_test_items()
	base := test_recipe_definition()
	research := base
	research.channel = "research"
	research.technology = "tech"
	definitions := []Recipe_Definition{research, base}
	definitions[1].id = "plain"
	recipes, problem := resolve_recipe_registry(Recipes_File{recipes = definitions}, items, make_test_fluids(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	resolve :: proc(technologies: []Technology_Definition, recipes: Recipe_Registry) -> string {
		_, problem := resolve_technology_registry(Technologies_File{technologies = technologies}, make_test_items(), recipes, context.temp_allocator)
		return problem
	}
	good := Technology_Definition{id = "tech", name_key = "technology_optics", unlocks = {"test"}, packs = 10, seconds = 10, science_packs = {"science_pack_1"}}
	testing.expect_value(t, resolve({good}, recipes), "")
	testing.expect_value(t, recipes.recipes[0].technology, 0)
	unknown := good
	unknown.unlocks = {"no_such_recipe"}
	testing.expect(t, resolve({unknown}, recipes) != "")
	not_research := good
	not_research.unlocks = {"test", "plain"}
	testing.expect(t, resolve({not_research}, recipes) != "")
	unlisted := good
	unlisted.unlocks = {}
	testing.expect(t, resolve({unlisted}, recipes) != "")
	free := good
	free.packs = 0
	testing.expect(t, resolve({free}, recipes) != "")
}

@(test)
test_recipe_name_order :: proc(t: ^testing.T) {
	names := []string{"Iron gear", "Belt", "Iron gear", "Anvil"}
	order := recipe_name_order(names, context.temp_allocator)
	testing.expect(t, slice.equal(order, []int{3, 1, 0, 2}))
}
