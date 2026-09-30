package game

import "core:strings"
import "core:testing"

// Chapter 8 (data/quests/chapter_08.sjson): the ship objective, research
// on an infinite technology, the launch refusal counters, the HUD and
// journal after the last quest, and the chapter 6 permit line.

chapter_08_registry :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[7:8], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_chapter_08_test :: proc() -> Quest_Test {
	references := make_test_quest_references()
	registry := chapter_08_registry(references)
	test := make_quest_test(registry.quests, registry.chapters)
	test.statistics = make_statistics(len(test.items.items), len(test.machines.machines), len(references.blocks.definitions), context.temp_allocator)
	return test
}

// The part counts are one rocket's, from the launch pad's machine data.
@(test)
test_chapter_08_loads :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := chapter_08_registry(references)
	ids := [?]string{"rocketry", "launch_pad", "rocket_parts", "first_launch", "contract", "orbital_survey", "productivity", "self_sufficient"}
	testing.expect_value(t, len(registry.quests), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.quests[index].id, id)
	}
	items, technologies, machines := references.items, references.technologies, references.machines
	testing.expect_value(t, registry.quests[0].objectives[0].technology, test_technology(technologies, "rocketry"))
	testing.expect_value(t, registry.quests[1].objectives[0].machine, test_machine(machines, "launch_pad"))
	pad := machines.machines[test_machine(machines, "launch_pad")]
	parts := registry.quests[2].objectives
	testing.expect_value(t, len(parts), pad.launch_part_count)
	for objective, index in parts {
		testing.expect_value(t, objective.type, Objective_Type.Craft)
		testing.expect_value(t, objective.item, pad.launch_parts[index].item)
		testing.expect_value(t, objective.count, u64(pad.launch_parts[index].count))
	}
	launch := registry.quests[3]
	testing.expect_value(t, launch.objectives[0].counter, Hint_Counter.Rockets_Launched)
	testing.expect_value(t, launch.hints[0], Hint{counter = .Launch_Parts_Missing, threshold = 1, text_key = "mc_hint_launch_parts_missing"})
	testing.expect_value(t, launch.hints[1], Hint{counter = .Launch_Cargo_Empty, threshold = 1, text_key = "mc_hint_launch_cargo_empty"})
	testing.expect_value(t, registry.quests[4].objectives[0].counter, Hint_Counter.Contracts_Completed)
	testing.expect_value(t, registry.quests[5].objectives[0].counter, Hint_Counter.Surveys_Bought)
	productivity := registry.quests[6].objectives[0].technology
	testing.expect_value(t, productivity, test_technology(technologies, "mining_productivity"))
	testing.expect(t, technologies.technologies[productivity].infinite)
	main := registry.quests[7]
	testing.expect(t, main.main)
	testing.expect_value(t, main.objectives[0].type, Objective_Type.Ship)
	testing.expect_value(t, main.objectives[0].item, NO_ITEM)
	testing.expect_value(t, main.objectives[0].count, 1000)
	testing.expect_value(t, main.complete_key, "mc_self_sufficient_done")
	testing.expect_value(t, main.reward_items[0], Item_Stack{test_item(items, "rocket_structure"), 10})
}

// A ship objective with an item and without one, and an unknown item.
@(test)
test_ship_objective_counts_shipped_items :: proc(t: ^testing.T) {
	test := make_quest_test(nil, nil)
	defer destroy_quest_test(&test)
	plate, steel := test_item(test.items, "iron_plate"), test_item(test.items, "steel")
	shipment := Shipment{cargo_count = 2}
	shipment.cargo[0], shipment.cargo[1] = {plate, 80}, {steel, 20}
	record_shipment(&test.statistics, shipment)
	testing.expect_value(t, test.statistics.items_shipped, 100)
	progress: Quest_Progress
	testing.expect_value(t, progress_of(&test, item_objective(.Ship, plate, 100), progress), Objective_Progress{80, 100})
	testing.expect_value(t, progress_of(&test, item_objective(.Ship, NO_ITEM, 100), progress), Objective_Progress{100, 100})
	record_shipment(&test.statistics, shipment)
	testing.expect(t, objective_done(progress_of(&test, item_objective(.Ship, plate, 100), progress)))
	testing.expect_value(t, hint_counter_value(test.statistics, Hint{counter = .Items_Shipped}), 200)
	references := make_test_quest_references()
	objective, problem := resolve_objective(Objective_Definition{type = "ship", count = 5}, references, "quest")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, objective.item, NO_ITEM)
	_, problem = resolve_objective(Objective_Definition{type = "ship", item = "nothing", count = 5}, references, "quest")
	testing.expect(t, problem != "")
	_, problem = resolve_objective(Objective_Definition{type = "ship"}, references, "quest")
	testing.expect(t, problem != "")
}

// The first finished level of an infinite technology completes a research
// objective, although the technology stays available for more levels.
@(test)
test_research_objective_on_an_infinite_technology :: proc(t: ^testing.T) {
	test := make_quest_test(nil, nil)
	defer destroy_quest_test(&test)
	technologies := make_test_quest_references().technologies
	productivity := test_technology(technologies, "mining_productivity")
	research := item_objective(.Research, NO_ITEM, 0)
	research.technology = productivity
	progress: Quest_Progress
	state := Research_State{queued = true, technology = productivity}
	for _ in 0 ..< technologies.technologies[productivity].pack_count - 1 {
		finish_research_unit(&state, technologies)
	}
	_, finished := apply_finished_research(&state, &test.unlocks, test.recipes)
	testing.expect(t, !finished)
	testing.expect(t, !objective_done(progress_of(&test, research, progress)))
	finish_research_unit(&state, technologies)
	_, finished = apply_finished_research(&state, &test.unlocks, test.recipes)
	testing.expect(t, finished)
	testing.expect_value(t, state.levels[productivity], 1)
	// The queue empties after a level (user decision 2026-09-27).
	testing.expect(t, !state.queued)
	testing.expect(t, objective_done(progress_of(&test, research, progress)))
	testing.expect(t, technology_status(technologies, test.unlocks, productivity) != .Researched)
}

// Assemble and Launch refused for parts, or Launch for an empty cargo,
// count; a launch that goes ahead or a rocket in the making does not.
@(test)
test_launch_refusals_are_counted :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	machine := content.machines.machines[test_machine(content.machines, "launch_pad")]
	pad := make_launch_pad({}, machine)
	statistics: Statistics
	testing.expect_value(t, assembly_refusal(pad, machine), Launch_Refusal.Parts_Missing)
	testing.expect_value(t, launch_refusal(&pad, machine), Launch_Refusal.Parts_Missing)
	record_launch_refusal(&statistics, assembly_refusal(pad, machine))
	record_launch_refusal(&statistics, launch_refusal(&pad, machine))
	for index in 0 ..< machine.launch_part_count {
		pad.slots[index] = machine.launch_parts[index]
	}
	pad.buffers[LAUNCH_PAD_FUEL_PORT] = {fluid = test_fluid(content, "rocket_fuel"), level = i32(machine.launch_fuel_litres)}
	testing.expect_value(t, assembly_refusal(pad, machine), Launch_Refusal.None)
	testing.expect_value(t, launch_refusal(&pad, machine), Launch_Refusal.Not_Ready)
	pad.state = .Assembling
	testing.expect_value(t, launch_refusal(&pad, machine), Launch_Refusal.Not_Ready)
	pad.missing_parts = true
	testing.expect_value(t, launch_refusal(&pad, machine), Launch_Refusal.Parts_Missing)
	testing.expect_value(t, assembly_refusal(pad, machine), Launch_Refusal.Not_Ready)
	pad.state = .Rocket_Ready
	testing.expect_value(t, launch_refusal(&pad, machine), Launch_Refusal.Cargo_Empty)
	record_launch_refusal(&statistics, launch_refusal(&pad, machine))
	launch_pad_cargo(&pad)[0] = {test_item(content.items, "iron_plate"), 5}
	testing.expect_value(t, launch_refusal(&pad, machine), Launch_Refusal.None)
	record_launch_refusal(&statistics, launch_refusal(&pad, machine))
	testing.expect_value(t, statistics.launch_parts_missing, 2)
	testing.expect_value(t, statistics.launch_cargo_empty, 1)
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Launch_Parts_Missing}), 2)
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Launch_Cargo_Empty}), 1)
}

complete_rocketry_to_first_launch :: proc(t: ^testing.T, test: ^Quest_Test) {
	testing.expect_value(t, active_quest_id(test), "rocketry")
	research_test_technology(test, "rocketry")
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "launch_pad")
	set_placed(test, "launch_pad", 1)
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "rocket_parts")
	test.statistics.produced[test_item(test.items, "rocket_structure")] = 10
	test.statistics.produced[test_item(test.items, "guidance_unit")] = 2
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "rocket_parts")
	test.statistics.produced[test_item(test.items, "cargo_capsule")] = 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "first_launch")
}

// Every quest in order on synthetic counters; counters from before a
// quest do not count. After the main quest the HUD falls back to the
// oldest open contract, and to nothing without one.
@(test)
test_chapter_08_completes_in_order :: proc(t: ^testing.T) {
	test := make_chapter_08_test()
	defer destroy_quest_test(&test)
	test.statistics.rockets_launched = 3
	test.statistics.contracts_completed = 2
	test.statistics.surveys_bought = 1
	complete_rocketry_to_first_launch(t, &test)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "first_launch")
	test.statistics.rockets_launched += 1
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "contract")
	test.statistics.contracts_completed += 1
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "orbital_survey")
	test.statistics.surveys_bought += 1
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "productivity")
	research_test_technology(&test, "mining_productivity")
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "self_sufficient")
	testing.expect_value(t, hud_objective_source(&test.state, 1), Hud_Objective_Source.Quest)
	testing.expect(t, !journal_shows_contracts_continue(test.state, 0, 1))
	test.statistics.items_shipped = 999
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "self_sufficient")
	test.statistics.items_shipped = 1000
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect(t, chapter_done(test.state, test.registry.chapters[0]))
	testing.expect(t, has_message(&test, "mc_self_sufficient_done"))
	testing.expect_value(t, slots_item_count(capsule_slots(&test), test_item(test.items, "rocket_structure")), 10)
	testing.expect_value(t, hud_objective_source(&test.state, 1), Hud_Objective_Source.Contract)
	testing.expect_value(t, hud_objective_source(&test.state, 0), Hud_Objective_Source.None)
	testing.expect_value(t, hud_objective_source(nil, 1), Hud_Objective_Source.None)
	testing.expect(t, journal_shows_contracts_continue(test.state, 0, 1))
	testing.expect(t, !journal_shows_contracts_continue(test.state, 0, 2))
}

// The HUD's contract line is the oldest open contract's.
@(test)
test_contract_objective_lines_show_the_oldest_contract :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	items := make_test_items()
	registry := make_test_contracts(items)
	world: World
	_, _, found := contract_objective_lines(&world, registry, items, 0, TEST_TICK_RATE)
	testing.expect(t, !found)
	boards, girders := test_contract(registry, "control_boards"), test_contract(registry, "station_girders")
	offer_contract(&world.contracts, boards, 0)
	offer_contract(&world.contracts, girders, 0)
	title, detail, shown := contract_objective_lines(&world, registry, items, 0, TEST_TICK_RATE)
	testing.expect(t, shown)
	testing.expect_value(t, title, text(registry.contracts[boards].name_key))
	testing.expect(t, detail != "")
}

@(test)
test_chapter_08_hints_fire_once :: proc(t: ^testing.T) {
	test := make_chapter_08_test()
	defer destroy_quest_test(&test)
	test.statistics.launch_parts_missing = 4
	test.statistics.launch_cargo_empty = 2
	complete_rocketry_to_first_launch(t, &test)
	run_quest_tick(&test)
	testing.expect_value(t, test.state.hints_fired, 0)
	test.statistics.launch_parts_missing += 1
	run_quest_tick(&test)
	test.statistics.launch_parts_missing += 1
	test.statistics.launch_cargo_empty += 1
	run_quest_tick(&test)
	test.statistics.launch_cargo_empty += 1
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_launch_parts_missing"), 1)
	testing.expect_value(t, message_count(&test, "mc_hint_launch_cargo_empty"), 1)
	testing.expect_value(t, test.state.hints_fired, 2)
}

// Carry over from chapter 7: the bore drill schematics exist (work items
// 0035 and 0036).
@(test)
test_deep_mining_permit_line_is_current :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect(t, error == nil)
	line, found := table.entries["mc_deep_mining_permit_done"]
	testing.expect(t, found)
	testing.expect(t, !strings.contains(line, "pending"), line)
}
