package game

import "core:slice"
import "core:testing"

test_lab :: proc(world: ^World, handle: Entity_Handle) -> ^Lab {
	return pool_get(&world.entities.labs, handle)
}

test_technology :: proc(technologies: Technology_Registry, id: string) -> int {
	for technology, index in technologies.technologies {
		if technology.id == id {
			return index
		}
	}
	panic(id)
}

make_powered_lab :: proc(content: Simulation_Content, packs: u16) -> Lab {
	lab := make_lab({}, len(content.machines.lab_packs))
	if packs > 0 {
		lab.slots[0] = {test_item(content.items, "science_pack_1"), packs}
	}
	lab.power.satisfaction = POWER_FULL
	lab.alive = true
	return lab
}

// Ticks the labs outside any world, as tick_labs does.
advance_test_labs :: proc(labs: []Lab, content: Simulation_Content, research: ^Research_State, ticks: int) {
	machine := content.machines.machines[test_machine(content.machines, "lab")]
	for _ in 0 ..< ticks {
		in_progress := units_in_progress(labs, research^)
		for &lab in labs {
			advance_lab(&lab, machine, research, &in_progress, content.technologies, content.machines.lab_packs, TEST_TICK_RATE)
		}
	}
}

@(test)
test_lab_and_technology_data_load :: proc(t: ^testing.T) {
	content := make_test_content()
	lab := content.machines.machines[test_machine(content.machines, "lab")]
	testing.expect_value(t, lab.kind, Machine_Kind.Lab)
	testing.expect_value(t, lab.footprint, [3]i32{3, 2, 3})
	testing.expect_value(t, lab.speed_percent, 100)
	testing.expect_value(t, lab.electric_power_watts, 60_000)
	pack := test_item(content.items, "science_pack_1")
	second_pack := test_item(content.items, "science_pack_2")
	testing.expect(t, slice.equal(content.technologies.science_packs, []Item_Id{pack, second_pack}))
	testing.expect(t, slice.equal(content.machines.lab_packs, []Item_Id{pack, second_pack}))
	technologies := content.technologies
	automation := technologies.technologies[test_technology(technologies, "automation")]
	testing.expect_value(t, automation.pack_count, 10)
	testing.expect_value(t, technology_unit_ticks(automation, lab.speed_percent, TEST_TICK_RATE), 600)
	testing.expect_value(t, len(automation.prerequisites), 0)
	optics := technologies.technologies[test_technology(technologies, "optics")]
	testing.expect(t, slice.equal(optics.prerequisites, []int{test_technology(technologies, "electric_mining")}))
	// Every technology with recipes in the data unlocks them; only the
	// phase 5 ones are placeholders.
	for technology in technologies.technologies {
		testing.expectf(t, technology.placeholder == (len(technology.unlocks) == 0), "%s", technology.id)
	}
	testing.expect(t, technologies.technologies[test_technology(technologies, "fast_belts")].placeholder)
}

@(test)
test_technology_data_rejects_bad_prerequisites_and_empty_unlocks :: proc(t: ^testing.T) {
	items := make_test_items()
	recipes, _ := make_test_recipes(items)
	resolve :: proc(technologies: []Technology_Definition, items: Item_Registry, recipes: Recipe_Registry) -> string {
		_, problem := resolve_technology_registry(Technologies_File{technologies = technologies}, items, recipes, context.temp_allocator)
		return problem
	}
	file, error := parse_technologies_file(#load("../data/technologies.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, resolve(file.technologies, items, recipes), "")
	definitions := slice.clone(file.technologies, context.temp_allocator)
	// A prerequisite listed later (which would allow cycles), unknown, or
	// itself.
	definitions[0].prerequisites = {"logistics"}
	testing.expect(t, resolve(definitions, items, recipes) != "")
	definitions[0].prerequisites = {"no_such_technology"}
	testing.expect(t, resolve(definitions, items, recipes) != "")
	definitions[0].prerequisites = {"automation"}
	testing.expect(t, resolve(definitions, items, recipes) != "")
	definitions[0].prerequisites = nil
	// A technology unlocking nothing needs placeholder = true.
	last := find_technology_definition_index(definitions, "fast_belts")
	definitions[last].placeholder = false
	testing.expect(t, resolve(definitions, items, recipes) != "")
	definitions[last].placeholder = true
	// Science packs must be known items, named once.
	definitions[last].science_packs = {"no_such_item"}
	testing.expect(t, resolve(definitions, items, recipes) != "")
	definitions[last].science_packs = {"science_pack_1", "science_pack_1"}
	testing.expect(t, resolve(definitions, items, recipes) != "")
	definitions[last].science_packs = nil
	testing.expect(t, resolve(definitions, items, recipes) != "")
}

@(test)
test_technology_status_follows_prerequisites :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	automation, logistics := test_technology(technologies, "automation"), test_technology(technologies, "logistics")
	testing.expect_value(t, technology_status(technologies, test.unlocks, automation), Technology_Status.Available)
	testing.expect_value(t, technology_status(technologies, test.unlocks, logistics), Technology_Status.Locked)
	research: Research_State
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, logistics), Research_Refusal.Locked)
	testing.expect(t, !research.queued)
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, automation), Research_Refusal.None)
	testing.expect(t, research.queued)
	mark_technology_researched(&test.unlocks, test.recipes, automation)
	testing.expect_value(t, technology_status(technologies, test.unlocks, automation), Technology_Status.Researched)
	testing.expect_value(t, technology_status(technologies, test.unlocks, logistics), Technology_Status.Available)
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, automation), Research_Refusal.Researched)
}

@(test)
test_lab_consumes_packs_and_completes_research :: proc(t: ^testing.T) {
	content := make_test_content()
	labs := []Lab{make_powered_lab(content, 12)}
	research: Research_State
	advance_test_labs(labs, content, &research, 1)
	testing.expect_value(t, labs[0].state, Lab_State.No_Research)
	testing.expect_value(t, labs[0].slots[0].count, 12)
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator)
	automation := test_technology(content.technologies, "automation")
	queue_research(&research, content.technologies, unlocks, automation)
	// A pack per 600 ticks, taken when the unit starts.
	advance_test_labs(labs, content, &research, 1)
	testing.expect_value(t, labs[0].state, Lab_State.Researching)
	testing.expect_value(t, labs[0].slots[0].count, 11)
	advance_test_labs(labs, content, &research, 599)
	testing.expect_value(t, research.units_done, 1)
	advance_test_labs(labs, content, &research, 9 * 600 - 1)
	testing.expect_value(t, research.units_done, 9)
	testing.expect(t, !research.finished)
	advance_test_labs(labs, content, &research, 1)
	testing.expect(t, research.finished)
	testing.expect(t, !research.queued)
	testing.expect_value(t, research.finished_technology, automation)
	testing.expect_value(t, labs[0].slots[0].count, 2)
	// Nothing queued: the rest of the packs stay.
	advance_test_labs(labs, content, &research, 700)
	testing.expect_value(t, labs[0].slots[0].count, 2)
	testing.expect_value(t, labs[0].state, Lab_State.No_Research)
}

@(test)
test_lab_states_without_packs_or_power :: proc(t: ^testing.T) {
	content := make_test_content()
	labs := []Lab{make_powered_lab(content, 0)}
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator)
	research: Research_State
	queue_research(&research, content.technologies, unlocks, test_technology(content.technologies, "automation"))
	advance_test_labs(labs, content, &research, 1)
	testing.expect_value(t, labs[0].state, Lab_State.No_Packs)
	testing.expect(t, !lab_wants_power(labs[0], research, content.technologies, content.machines.lab_packs))
	labs[0].slots[0] = {test_item(content.items, "science_pack_1"), 1}
	labs[0].power.satisfaction = 0
	advance_test_labs(labs, content, &research, 1)
	testing.expect_value(t, labs[0].state, Lab_State.No_Power)
	testing.expect_value(t, labs[0].slots[0].count, 1)
	testing.expect(t, lab_wants_power(labs[0], research, content.technologies, content.machines.lab_packs))
}

@(test)
test_two_labs_share_progress :: proc(t: ^testing.T) {
	content := make_test_content()
	labs := []Lab{make_powered_lab(content, 20), make_powered_lab(content, 20)}
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator)
	research: Research_State
	queue_research(&research, content.technologies, unlocks, test_technology(content.technologies, "automation"))
	// Ten units of 600 ticks over two labs: 3000 ticks, five packs each.
	advance_test_labs(labs, content, &research, 2999)
	testing.expect_value(t, research.units_done, 8)
	advance_test_labs(labs, content, &research, 1)
	testing.expect(t, research.finished)
	testing.expect_value(t, labs[0].slots[0].count, 15)
	testing.expect_value(t, labs[1].slots[0].count, 15)
	// An odd count never overshoots: optics is 10 units too, three labs
	// take four, three and three.
	three := []Lab{make_powered_lab(content, 20), make_powered_lab(content, 20), make_powered_lab(content, 20)}
	research = {}
	mark_technology_researched(&unlocks, content.recipes, test_technology(content.technologies, "automation"))
	mark_technology_researched(&unlocks, content.recipes, test_technology(content.technologies, "electric_mining"))
	queue_research(&research, content.technologies, unlocks, test_technology(content.technologies, "optics"))
	advance_test_labs(three, content, &research, 4 * 900)
	testing.expect(t, research.finished)
	used := 60 - int(three[0].slots[0].count) - int(three[1].slots[0].count) - int(three[2].slots[0].count)
	testing.expect_value(t, used, 10)
	testing.expect_value(t, three[0].slots[0].count, 16)
}

@(test)
test_requeueing_drops_the_unit_in_progress :: proc(t: ^testing.T) {
	content := make_test_content()
	labs := []Lab{make_powered_lab(content, 5)}
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator)
	automation := test_technology(content.technologies, "automation")
	research: Research_State
	queue_research(&research, content.technologies, unlocks, automation)
	advance_test_labs(labs, content, &research, 700)
	testing.expect_value(t, research.units_done, 1)
	// The same technology again keeps its progress.
	queue_research(&research, content.technologies, unlocks, automation)
	testing.expect_value(t, research.units_done, 1)
	mark_technology_researched(&unlocks, content.recipes, automation)
	queue_research(&research, content.technologies, unlocks, test_technology(content.technologies, "logistics"))
	testing.expect_value(t, research.units_done, 0)
	testing.expect_value(t, units_in_progress(labs, research), 0)
	advance_test_labs(labs, content, &research, 1)
	testing.expect_value(t, labs[0].slots[0].count, 2)
	testing.expect_value(t, labs[0].progress_ticks, 1)
}

// Two powered labs in a world, fed by the transfer interface; completion
// opens the assembler recipe.
lay_research_site :: proc(world: ^World, content: Simulation_Content) -> (first, second: Entity_Handle) {
	first = place_test_entity(world, content, "lab", {1, 1, -1})
	second = place_test_entity(world, content, "lab", {-4, 1, -1})
	add_test_power_plant(world, content, {-1, 1, 0}, {-2, 1, 2})
	pack := test_item(content.items, "science_pack_1")
	entity_insert(&world.entities, content, first, {pack, 6})
	entity_insert(&world.entities, content, second, {pack, 6})
	return
}

@(test)
test_research_in_the_world_unlocks_recipes :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	first, second := lay_research_site(&world, content)
	networks := &world.entities.electric_networks
	testing.expect(t, entity_network(networks, first) >= 0 && entity_network(networks, second) >= 0)
	pack := test_item(content.items, "science_pack_1")
	testing.expect(t, entity_takes_item_kind(&world.entities, content, first, pack))
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, first, test_item(content.items, "iron_plate")))
	testing.expect_value(t, len(entity_offered_items(&world.entities, first, NO_ITEM)), 0)
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator)
	assembler_recipe := test_recipe(content.recipes, "assembler_1")
	testing.expect(t, !recipe_is_available(unlocks, assembler_recipe))
	queue_research(&world.research, content.technologies, unlocks, test_technology(content.technologies, "automation"))
	// Five units of 600 ticks in each lab, and one tick to settle.
	for _ in 0 ..< 3001 {
		tick_entities(&world, content, TEST_TICK_RATE)
		apply_finished_research(&world.research, &unlocks, content.recipes)
	}
	testing.expect(t, unlocks.researched[test_technology(content.technologies, "automation")])
	testing.expect(t, recipe_is_available(unlocks, assembler_recipe))
	testing.expect_value(t, test_lab(&world, first).slots[0].count + test_lab(&world, second).slots[0].count, 2)
	testing.expect_value(t, test_lab(&world, first).state, Lab_State.No_Research)
}

@(test)
test_technology_screen_filters_and_orders :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	names := make([]string, len(technologies.technologies), context.temp_allocator)
	for technology, index in technologies.technologies {
		names[index] = technology.id
	}
	order := recipe_name_order(names, context.temp_allocator)
	visible := filter_technologies(technologies, test.unlocks, order, {}, context.temp_allocator)
	ids := make([]string, len(visible), context.temp_allocator)
	for technology, index in visible {
		ids[index] = names[technology]
	}
	expected := []string{"automation", "bitumen_paving", "combustion_power", "cracking", "deep_mining", "electric_mining", "electrolysis", "fast_belts", "fluid_handling", "logistics", "logistics_science", "oil_processing", "optics", "ore_processing", "plastics", "prospecting", "recycling", "renewable_plastics", "steel_processing"}
	testing.expect(t, slice.equal(ids, expected))
	testing.expect_value(t, names[visible[recipe_position_for_letter(names, visible, 'l')]], "logistics")
	testing.expect_value(t, names[visible[recipe_position_for_letter(names, visible, 'g')]], "logistics")
	automation := test_technology(technologies, "automation")
	mark_technology_researched(&test.unlocks, test.recipes, automation)
	hidden := filter_technologies(technologies, test.unlocks, order, {hide_researched = true}, context.temp_allocator)
	testing.expect_value(t, len(hidden), len(expected) - 1)
	testing.expect(t, !slice.contains(hidden, automation))
	testing.expect_value(t, technology_total_seconds(technologies.technologies[automation]), 100)
}

// Assemblers and labs over 1200 ticks give the same state twice.
@(test)
test_assemblers_and_labs_are_deterministic :: proc(t: ^testing.T) {
	run :: proc(content: Simulation_Content) -> (gears: int, units: int, labs: [2]Lab, produced: u64) {
		world := make_floor_world(content.blocks, 32)
		first, second := lay_research_site(&world, content)
		unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator)
		queue_research(&world.research, content.technologies, unlocks, test_technology(content.technologies, "automation"))
		_, assembler, target := lay_gear_line_at(&world, content, {8, 0, 8})
		for _ in 0 ..< 1200 {
			tick_entities(&world, content, TEST_TICK_RATE)
		}
		gears = chest_count_of(&world, target, test_item(content.items, "iron_gear"))
		gears += slots_count_of(test_assembler(&world, assembler).slots[:], test_item(content.items, "iron_gear"))
		return gears, world.research.units_done, {test_lab(&world, first)^, test_lab(&world, second)^}, item_counter(world.statistics.produced, test_item(content.items, "iron_gear"))
	}
	content := make_test_content()
	first_gears, first_units, first_labs, first_produced := run(content)
	second_gears, second_units, second_labs, second_produced := run(content)
	testing.expect_value(t, first_gears, second_gears)
	testing.expect_value(t, first_units, second_units)
	testing.expect_value(t, first_labs, second_labs)
	testing.expect_value(t, first_produced, second_produced)
	testing.expect(t, first_units >= 2)
	testing.expect(t, first_gears >= 4)
}

// Switching research keeps the old technology's units, and switching back
// resumes them.
@(test)
test_switching_research_keeps_progress_per_technology :: proc(t: ^testing.T) {
	content := make_test_content()
	labs := []Lab{make_powered_lab(content, 50)}
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator)
	mark_technology_researched(&unlocks, content.recipes, test_technology(content.technologies, "automation"))
	logistics, electric_mining := test_technology(content.technologies, "logistics"), test_technology(content.technologies, "electric_mining")
	research: Research_State
	queue_research(&research, content.technologies, unlocks, logistics)
	advance_test_labs(labs, content, &research, 2 * 900)
	testing.expect_value(t, research.units_done, 2)
	queue_research(&research, content.technologies, unlocks, electric_mining)
	testing.expect_value(t, research.units_done, 0)
	advance_test_labs(labs, content, &research, 900)
	testing.expect_value(t, research.units_done, 1)
	queue_research(&research, content.technologies, unlocks, logistics)
	testing.expect_value(t, research.units_done, 2)
	queue_research(&research, content.technologies, unlocks, electric_mining)
	testing.expect_value(t, research.units_done, 1)
}

@(test)
test_placeholder_technologies_are_locked :: proc(t: ^testing.T) {
	content := make_test_content()
	technologies := content.technologies
	unlocks := make_recipe_unlocks(len(content.items.items), content.recipes, technologies, false, context.temp_allocator)
	mark_technology_researched(&unlocks, content.recipes, test_technology(technologies, "automation"))
	mark_technology_researched(&unlocks, content.recipes, test_technology(technologies, "logistics"))
	mark_technology_researched(&unlocks, content.recipes, test_technology(technologies, "logistics_science"))
	placeholder := test_technology(technologies, "fast_belts")
	testing.expect_value(t, technology_status(technologies, unlocks, placeholder), Technology_Status.Locked)
	research: Research_State
	testing.expect_value(t, queue_research(&research, technologies, unlocks, placeholder), Research_Refusal.Placeholder)
	testing.expect(t, !research.queued)
	testing.expect(t, research_refusal_keys[.Placeholder] != "")
}

// Inserters and drills fill a lab slot only up to two pack sets.
@(test)
test_lab_refuses_a_third_pack_set :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	lab := place_test_entity(&world, content, "lab", {1, 1, -1})
	pack := test_item(content.items, "science_pack_1")
	testing.expect_value(t, entity_insert(&world.entities, content, lab, {pack, 1}), EMPTY_STACK)
	testing.expect_value(t, entity_insert(&world.entities, content, lab, {pack, 1}), EMPTY_STACK)
	testing.expect_value(t, entity_insert(&world.entities, content, lab, {pack, 1}), Item_Stack{pack, 1})
	_, accepted := entity_accepts(&world.entities, content, lab, pack)
	testing.expect(t, !accepted)
	testing.expect(t, entity_takes_item_kind(&world.entities, content, lab, pack))
	testing.expect_value(t, test_lab(&world, lab).slots[0], Item_Stack{pack, 2})
}
