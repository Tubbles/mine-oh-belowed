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
	testing.expect_value(t, len(recipes.recipes), 129)
	testing.expect_value(t, len(technologies.technologies), 27)
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

// A recipe the slice's player makes from the held items: by hand, in a
// stone furnace once one is held, or at a crafting station once its item
// is held (work item 0196), unlocked from the start or by discovery,
// without fluids.
slice_recipe_is_makeable :: proc(recipe: Recipe, held: []bool, furnace: Item_Id, machines: Machine_Registry) -> bool {
	if recipe.channel != .Start && recipe.channel != .Discovery || len(recipe.fluid_inputs) > 0 {
		return false
	}
	if !slice_recipe_has_maker(recipe, held, furnace, machines) {
		return false
	}
	for input in recipe.inputs {
		if !held[input.item] {
			return false
		}
	}
	return true
}

slice_recipe_has_maker :: proc(recipe: Recipe, held: []bool, furnace: Item_Id, machines: Machine_Registry) -> bool {
	if .Hand in recipe.made_in || .Furnace in recipe.made_in && held[furnace] {
		return true
	}
	for machine in machines.machines {
		if machine.kind == .Crafting_Station && machine.recipe_maker in recipe.made_in && held[machine.item] {
			return true
		}
	}
	return false
}

// Every item made from the start set until nothing new comes.
slice_reachable_items :: proc(recipes: Recipe_Registry, start: []bool, furnace: Item_Id, machines: Machine_Registry) -> []bool {
	held := slice.clone(start, context.temp_allocator)
	for grew := true; grew; {
		grew = false
		for recipe in recipes.recipes {
			if !slice_recipe_is_makeable(recipe, held, furnace, machines) {
				continue
			}
			for output in recipe.outputs {
				grew = grew || !held[output.item]
				held[output.item] = true
			}
		}
	}
	return held
}

// The slice's recipe chain (work item 0179): from the items the field's
// materials yield (data/materials.sjson), the logs the shipped planet's
// trees yield (0197) and the starting items of data/game.sjson, by hand,
// in the stone furnace and at the stone cutting table (0196), to every
// building chapter 1 and the first line need, and the three foundations;
// the trees' logs make the planks.
@(test)
test_the_slice_recipe_chain_is_reachable_from_the_fields_yield :: proc(t: ^testing.T) {
	items := make_test_items()
	recipes, _ := make_test_recipes(items)
	machines := make_test_machines()
	table, problem := parse_field_material_table(#load("../data/materials.sjson"), FIELD_MATERIALS_FILE_NAME, items)
	testing.expect_value(t, problem, "")
	start := make([]bool, len(items.items), context.temp_allocator)
	for record in table {
		if record.item != NO_ITEM {
			start[record.item] = true
		}
	}
	for species in default_planet(shipped_test_planets()).trees.species {
		start[test_item(items, species.item)] = true
	}
	testing.expect(t, start[test_item(items, "log")], "the trees yield wood")
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect(t, error == nil)
	for stack in config.starting_items {
		start[test_item(items, stack.item)] = true
	}
	held := slice_reachable_items(recipes, start, test_item(items, "stone_furnace"), machines)
	reachable := [?]string{"stone_furnace", "wooden_foundation", "stone_cutting_table", "stone_brick", "stone_brick_foundation", "torch", "belt_pole", "burner_mining_drill", "burner_inserter", "belt", "iron_chest", "iron_foundation", "stone_cutter"}
	for id in reachable {
		testing.expectf(t, held[test_item(items, id)], "%s is out of reach", id)
	}
	for id in ([?]string{"plank", "wooden_foundation", "stone_cutting_table"}) {
		testing.expectf(t, held[test_item(items, id)], "%s is out of reach of the logs", id)
	}
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

// Work item 0196: the foundations are discovered, each by its own
// ingredient: planks the wooden one, a stone brick the stone brick one,
// an iron plate the iron one.
@(test)
test_foundation_recipes_are_discovered_by_their_ingredients :: proc(t: ^testing.T) {
	test := make_crafting_test()
	ids := [3]string{"wooden_foundation", "stone_brick_foundation", "iron_foundation"}
	ingredients := [3]string{"plank", "stone_brick", "iron_plate"}
	for id in ids {
		testing.expectf(t, !test_available(test, id), "%s is undiscovered", id)
	}
	for ingredient, index in ingredients {
		record_obtained_item(&test.unlocks, test_item(test.items, ingredient))
		refresh_available_recipes(&test.unlocks, test.recipes)
		for id, other in ids {
			testing.expectf(t, test_available(test, id) == (other <= index), "%s after %s", id, ingredient)
		}
	}
}

// Work item 0196: stone is cut, not smelted, at the stone cutting table
// (a crafting station) and the stone cutter (a crafting machine).
@(test)
test_stone_bricks_are_cut_not_smelted :: proc(t: ^testing.T) {
	items := make_test_items()
	recipes, _ := make_test_recipes(items)
	machines := make_test_machines()
	testing.expect_value(t, furnace_recipe_for(recipes, test_item(items, "stone")), NO_RECIPE)
	testing.expect_value(t, recipes.recipes[test_recipe(recipes, "stone_brick")].made_in, Recipe_Makers{.Stone_Cutting})
	table := machines.machines[test_machine(machines, "stone_cutting_table")]
	cutter := machines.machines[test_machine(machines, "stone_cutter")]
	testing.expect_value(t, table.kind, Machine_Kind.Crafting_Station)
	testing.expect_value(t, cutter.kind, Machine_Kind.Crafting_Machine)
	testing.expect_value(t, table.recipe_maker, Recipe_Maker.Stone_Cutting)
	testing.expect_value(t, cutter.recipe_maker, Recipe_Maker.Stone_Cutting)
}
