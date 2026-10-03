package game

import "core:testing"

make_test_quest_references :: proc() -> Quest_References {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	assert(error == nil)
	items := make_test_items()
	recipes, technologies := make_test_recipes(items)
	return Quest_References {
		blocks = make_test_registry(),
		items = items,
		machines = make_test_machines(),
		fluids = make_test_fluids(),
		recipes = recipes,
		technologies = technologies,
		strings = table.entries,
	}
}

shipped_chapter_files :: proc() -> [8]Chapter_File {
	first, first_error := parse_chapter_file(#load("../data/quests/chapter_01.sjson"), context.temp_allocator)
	second, second_error := parse_chapter_file(#load("../data/quests/chapter_02.sjson"), context.temp_allocator)
	third, third_error := parse_chapter_file(#load("../data/quests/chapter_03.sjson"), context.temp_allocator)
	fourth, fourth_error := parse_chapter_file(#load("../data/quests/chapter_04.sjson"), context.temp_allocator)
	fifth, fifth_error := parse_chapter_file(#load("../data/quests/chapter_05.sjson"), context.temp_allocator)
	sixth, sixth_error := parse_chapter_file(#load("../data/quests/chapter_06.sjson"), context.temp_allocator)
	seventh, seventh_error := parse_chapter_file(#load("../data/quests/chapter_07.sjson"), context.temp_allocator)
	eighth, eighth_error := parse_chapter_file(#load("../data/quests/chapter_08.sjson"), context.temp_allocator)
	assert(first_error == nil && second_error == nil && third_error == nil && fourth_error == nil && fifth_error == nil && sixth_error == nil && seventh_error == nil)
	assert(eighth_error == nil)
	return {first, second, third, fourth, fifth, sixth, seventh, eighth}
}

make_test_quests :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[:], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

test_quest_index :: proc(registry: Quest_Registry, id: string) -> int {
	for quest, index in registry.quests {
		if quest.id == id {
			return index
		}
	}
	panic(id)
}

@(test)
test_shipped_quest_chapters_load :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := make_test_quests(references)
	testing.expect_value(t, len(registry.chapters), 8)
	testing.expect_value(t, registry.chapters[0].quest_count, 10)
	testing.expect_value(t, registry.chapters[1].first_quest, 10)
	testing.expect_value(t, registry.chapters[1].quest_count, 8)
	line := registry.quests[test_quest_index(registry, "line")]
	testing.expect_value(t, len(line.objectives), 4)
	testing.expect_value(t, line.objectives[0].type, Objective_Type.Place)
	testing.expect_value(t, line.objectives[0].machine, test_machine(references.machines, "burner_mining_drill"))
	coal := registry.quests[test_quest_index(registry, "coal")]
	testing.expect_value(t, coal.objectives[0].item, test_item(references.items, "coal"))
	furnace := registry.quests[test_quest_index(registry, "furnace")]
	testing.expect_value(t, furnace.objectives[1].machine, test_machine(references.machines, "stone_furnace"))
	stock := registry.quests[test_quest_index(registry, "stock")]
	testing.expect(t, stock.main)
	testing.expect_value(t, len(stock.reward_items), 2)
	invoice := registry.quests[test_quest_index(registry, "invoice")]
	testing.expect(t, invoice.main)
	testing.expect_value(t, invoice.chapter, 1)
	testing.expect_value(t, invoice.objectives[0].type, Objective_Type.Deliver)
	testing.expect_value(t, invoice.reward_items[0], Item_Stack{test_item(references.items, "belt"), 20})
	survey := registry.quests[test_quest_index(registry, "survey")]
	testing.expect_value(t, survey.objectives[2].recipe, test_recipe(references.recipes, "electronic_circuit"))
	testing.expect_value(t, registry.chapters[2].first_quest, 18)
	testing.expect_value(t, registry.chapters[2].quest_count, 6)
}

test_chapter :: proc() -> Chapter_File {
	quests := make([]Quest_Definition, 1, context.temp_allocator)
	objectives := make([]Objective_Definition, 1, context.temp_allocator)
	objectives[0] = {type = "obtain", item = "log", count = 10}
	quests[0] = Quest_Definition {
		id         = "timber",
		title_key  = "quest_coal_title",
		text_key   = "quest_coal_text",
		objectives = objectives,
	}
	return Chapter_File{id = "chapter", title_key = "chapter_01_title", quests = quests}
}

resolve_test_chapter :: proc(file: Chapter_File, references: Quest_References) -> string {
	files := []Chapter_File{file}
	_, problem := resolve_quest_registry(files, references, context.temp_allocator)
	return problem
}

// A copy of the test chapter whose one quest is changed by the caller.
chapter_with :: proc(quest: Quest_Definition) -> Chapter_File {
	file := test_chapter()
	quests := make([]Quest_Definition, 1, context.temp_allocator)
	quests[0] = quest
	file.quests = quests
	return file
}

with_objective :: proc(quest: Quest_Definition, objective: Objective_Definition) -> Quest_Definition {
	result := quest
	objectives := make([]Objective_Definition, 1, context.temp_allocator)
	objectives[0] = objective
	result.objectives = objectives
	return result
}

with_reward :: proc(quest: Quest_Definition, reward: Reward_Definition) -> Quest_Definition {
	result := quest
	rewards := make([]Reward_Definition, 1, context.temp_allocator)
	rewards[0] = reward
	result.rewards = rewards
	return result
}

with_hint :: proc(quest: Quest_Definition, hint: Hint_Definition) -> Quest_Definition {
	result := quest
	hints := make([]Hint_Definition, 1, context.temp_allocator)
	hints[0] = hint
	result.hints = hints
	return result
}

@(test)
test_quest_data_rejects_bad_definitions :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	good := test_chapter()
	testing.expect_value(t, resolve_test_chapter(good, references), "")
	quest := good.quests[0]
	cases := [?]Quest_Definition {
		with_objective(quest, {type = "obtain", item = "no_such_item", count = 1}),
		with_objective(quest, {type = "discover", recipe = "no_such_recipe"}),
		with_objective(quest, {type = "place", entity = "no_such_machine", count = 1}),
		with_objective(quest, {type = "research", technology = "no_such_technology"}),
		with_objective(quest, {type = "teleport", count = 1}),
		with_objective(quest, {type = "obtain", item = "log"}),
		with_objective(quest, {type = "sustain", item = "iron_plate", rate_per_minute = 10}),
		with_reward(quest, {item = "no_such_item", count = 1}),
		with_reward(quest, {unlocks_recipe = "no_such_recipe"}),
		// Not a quest channel recipe.
		with_reward(quest, {unlocks_recipe = "plank"}),
		with_reward(quest, {item = "coal", count = 1, unlocks_recipe = "steam_engine"}),
		with_hint(quest, {counter = "no_such_counter", threshold = 1, text_key = "mc_smelting"}),
		with_hint(quest, {counter = "mining_ticks", block = "no_such_block", threshold = 1, text_key = "mc_smelting"}),
		with_hint(quest, {counter = "blocks_mined", threshold = 1, text_key = "no_such_key"}),
		with_objective(quest, {type = "counter", counter = "no_such_counter", label_key = "objective_drill_fuel", count = 1}),
		with_objective(quest, {type = "counter", counter = "mining_ticks", label_key = "objective_drill_fuel", count = 1}),
		with_objective(quest, {type = "counter", counter = "drill_fuel_burned", count = 1}),
		with_objective(quest, {type = "counter", counter = "drill_fuel_burned", label_key = "objective_drill_fuel"}),
		with_objective(quest, {type = "obtain", item = "log", count = 1, produced_since_active = true}),
		// A place objective names exactly one of entity or item, and the
		// item must place a block.
		with_objective(quest, {type = "place", count = 1}),
		with_objective(quest, {type = "place", entity = "stone_furnace", item = "concrete", count = 1}),
		with_objective(quest, {type = "place", item = "iron_plate", count = 1}),
		with_hint(quest, {on_activation = true, counter = "blocks_mined", text_key = "mc_smelting"}),
		with_hint(quest, {on_activation = true, threshold = 1, text_key = "mc_smelting"}),
		with_hint(quest, {on_activation = true, text_key = "no_such_key"}),
		with_hint(quest, {counter = "blocks_mined", text_key = "mc_smelting"}),
		with_reward(quest, {unlocks_technology = "no_such_technology"}),
		with_reward(quest, {unlocks_recipe = "steam_engine", unlocks_technology = "oil_processing"}),
		// produce_fluid names a known fluid and litres, never a count.
		with_objective(quest, {type = "produce_fluid", fluid = "no_such_fluid", litres = 10}),
		with_objective(quest, {type = "produce_fluid", fluid = "petroleum_gas"}),
		with_objective(quest, {type = "produce_fluid", fluid = "petroleum_gas", count = 10}),
		with_objective(quest, {type = "produce_fluid", fluid = "petroleum_gas", litres = 10, count = 10}),
	}
	for bad in cases {
		testing.expectf(t, resolve_test_chapter(chapter_with(bad), references) != "", "accepted %v", bad)
	}
	missing_title := quest
	missing_title.title_key = "no_such_key"
	problem := resolve_test_chapter(chapter_with(missing_title), references)
	testing.expect_value(t, problem, `quest "timber": title_key "no_such_key" is not in the string table`)
	missing_message := quest
	missing_message.message_key = "no_such_key"
	testing.expect(t, resolve_test_chapter(chapter_with(missing_message), references) != "")
	unlocking := with_reward(quest, {unlocks_recipe = "steam_engine"})
	testing.expect_value(t, resolve_test_chapter(chapter_with(unlocking), references), "")
	licensing := with_reward(quest, {unlocks_technology = "oil_processing"})
	testing.expect_value(t, resolve_test_chapter(chapter_with(licensing), references), "")
	paving := with_objective(quest, {type = "place", item = "concrete", count = 1})
	testing.expect_value(t, resolve_test_chapter(chapter_with(paving), references), "")
	gas := with_objective(quest, {type = "produce_fluid", fluid = "petroleum_gas", litres = 10})
	testing.expect_value(t, resolve_test_chapter(chapter_with(gas), references), "")
	announced := with_hint(quest, {on_activation = true, text_key = "mc_smelting"})
	testing.expect_value(t, resolve_test_chapter(chapter_with(announced), references), "")
	twice := []Chapter_File{good, good}
	_, twice_problem := resolve_quest_registry(twice, references, context.temp_allocator)
	testing.expect_value(t, twice_problem, `quest id "timber" is defined twice`)
}
