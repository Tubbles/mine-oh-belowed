package game

import "core:slice"
import "core:testing"

// Chapter 6 (data/quests/chapter_06.sjson): produce_fluid objectives, the
// mixing_refusals, flared_litres and generator_gas_litres counters as
// hints and objectives, and the deep mining permit. The counters
// themselves are exercised in oil_test.odin and combustion_test.odin.

chapter_06_registry :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[5:6], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_chapter_06_test :: proc() -> Quest_Test {
	references := make_test_quest_references()
	registry := chapter_06_registry(references)
	test := make_quest_test(registry.quests, registry.chapters)
	test.statistics = make_statistics(len(test.items.items), len(test.machines.machines), len(references.blocks.definitions), context.temp_allocator)
	test.statistics.fluids = make_fluid_statistics(len(references.fluids.fluids), context.temp_allocator)
	return test
}

@(test)
test_chapter_06_loads :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := chapter_06_registry(references)
	ids := [?]string{"uphill", "tar", "fractions", "flare", "plastic", "two_routes", "waste_power", "deep_mining_permit"}
	testing.expect_value(t, len(registry.quests), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.quests[index].id, id)
	}
	items, technologies := references.items, references.technologies
	testing.expect_value(t, registry.quests[1].hints[0], Hint{counter = .Mixing_Refusals, threshold = 1, text_key = "mc_hint_mixing"})
	fractions := registry.quests[2].objectives[0]
	testing.expect_value(t, fractions.type, Objective_Type.Produce_Fluid)
	testing.expect_value(t, fractions.fluid, test_fluid(Simulation_Content{fluids = references.fluids}, "petroleum_gas"))
	testing.expect_value(t, fractions.count, 500)
	testing.expect_value(t, registry.quests[3].hints[0], Hint{counter = .Flared_Litres, threshold = 1000, text_key = "mc_hint_flare"})
	waste_power := registry.quests[6].objectives[2]
	testing.expect_value(t, waste_power.counter, Hint_Counter.Generator_Gas_Litres)
	testing.expect_value(t, waste_power.count, 300)
	permit := registry.quests[7]
	testing.expect(t, permit.main)
	deep_mining := test_technology(technologies, "deep_mining")
	testing.expect_value(t, len(permit.reward_technologies), 1)
	testing.expect_value(t, permit.reward_technologies[0], deep_mining)
	testing.expect_value(t, permit.reward_items[0], Item_Stack{test_item(items, "steel"), 100})
	testing.expect_value(t, permit.reward_items[1], Item_Stack{test_item(items, "electronic_circuit"), 50})
}

// deep_mining unlocks the bore drill and the mining fluid since work item
// 0035, and the labs still refuse it.
@(test)
test_deep_mining_is_a_quest_gate :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	deep_mining := test_technology(technologies, "deep_mining")
	technology := technologies.technologies[deep_mining]
	testing.expect(t, !technology.placeholder)
	testing.expect(t, technology.quest_gate)
	testing.expect(t, slice.contains(technology.unlocks, find_recipe(test.recipes, "bore_drill")))
	testing.expect(t, slice.contains(technology.unlocks, find_recipe(test.recipes, "mining_fluid")))
	for id in ([?]string{"automation", "logistics", "steel_processing", "ore_processing", "oil_processing", "plastics"}) {
		mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, id))
	}
	research: Research_State
	testing.expect(t, queue_research(&research, technologies, test.unlocks, deep_mining) != .None)
}

complete_uphill_to_fractions :: proc(t: ^testing.T, test: ^Quest_Test) {
	set_placed(test, "pump", 1)
	set_placed(test, "storage_tank", 1)
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "uphill")
	research_test_technology(test, "fluid_handling")
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "tar")
	set_placed(test, "tar_pit_pump", 1)
	set_placed(test, "refinery", 1)
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "fractions")
}

// Gas produced before the quest does not count.
complete_fractions_to_plastic :: proc(t: ^testing.T, test: ^Quest_Test, gas: Fluid_Id) {
	research_test_technology(test, "cracking")
	test.statistics.fluids.produced[gas] += 499
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "fractions")
	test.statistics.fluids.produced[gas] += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "flare")
	set_placed(test, "flare_stack", 1)
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "plastic")
}

complete_plastic_to_waste_power :: proc(t: ^testing.T, test: ^Quest_Test) {
	plastic := test_item(test.items, "plastic_bar")
	research_test_technology(test, "plastics")
	set_placed(test, "chemical_plant", 1)
	test.statistics.produced[plastic] += 49
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "plastic")
	test.statistics.produced[plastic] += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "two_routes")
	research_test_technology(test, "renewable_plastics")
	set_placed(test, "wood_gasifier", 1)
	test.statistics.produced[plastic] += 19
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "two_routes")
	test.statistics.produced[plastic] += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "waste_power")
}

complete_waste_power :: proc(t: ^testing.T, test: ^Quest_Test) {
	research_test_technology(test, "combustion_power")
	set_placed(test, "combustion_generator", 1)
	test.statistics.generator_gas_litres += 299
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "waste_power")
	test.statistics.generator_gas_litres += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "deep_mining_permit")
}

// Every quest of the chapter in order on synthetic counters, ending with
// the delivery, deep mining researched and the pay in the capsule.
@(test)
test_chapter_06_completes_in_order :: proc(t: ^testing.T) {
	test := make_chapter_06_test()
	defer destroy_quest_test(&test)
	gas, _ := find_fluid_id(make_test_fluids(), "petroleum_gas")
	test.statistics.fluids.produced[gas] = 5000
	test.statistics.produced[test_item(test.items, "plastic_bar")] = 300
	test.statistics.generator_gas_litres = 4000
	testing.expect_value(t, active_quest_id(&test), "uphill")
	complete_uphill_to_fractions(t, &test)
	complete_fractions_to_plastic(t, &test, gas)
	complete_plastic_to_waste_power(t, &test)
	complete_waste_power(t, &test)
	plastic, sulfur := test_item(test.items, "plastic_bar"), test_item(test.items, "sulfur")
	slots := capsule_slots(&test)
	slots[0], slots[1], slots[2] = {plastic, 100}, {plastic, 100}, {sulfur, 49}
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "deep_mining_permit")
	deep_mining := test_technology(make_test_quest_references().technologies, "deep_mining")
	testing.expect(t, !test.unlocks.researched[deep_mining])
	slots[2] = {sulfur, 50}
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect(t, chapter_done(test.state, test.registry.chapters[0]))
	testing.expect(t, has_message(&test, "mc_deep_mining_permit_done"))
	testing.expect(t, test.unlocks.researched[deep_mining])
	testing.expect_value(t, slots_item_count(slots, plastic), 0)
	testing.expect_value(t, slots_item_count(slots, sulfur), 0)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "steel")), 100)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "electronic_circuit")), 50)
}

// Both hints count from activation and fire once.
@(test)
test_chapter_06_hints_fire_once :: proc(t: ^testing.T) {
	test := make_chapter_06_test()
	defer destroy_quest_test(&test)
	test.statistics.mixing_refusals = 7
	test.statistics.flared_litres = 5000
	set_placed(&test, "pump", 1)
	set_placed(&test, "storage_tank", 1)
	research_test_technology(&test, "fluid_handling")
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "tar")
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_mixing"), 0)
	test.statistics.mixing_refusals += 1
	run_quest_tick(&test)
	test.statistics.mixing_refusals += 3
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_mixing"), 1)
	set_placed(&test, "tar_pit_pump", 1)
	set_placed(&test, "refinery", 1)
	run_quest_tick(&test)
	gas, _ := find_fluid_id(make_test_fluids(), "petroleum_gas")
	research_test_technology(&test, "cracking")
	test.statistics.fluids.produced[gas] += 500
	run_quest_tick(&test)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "flare")
	test.statistics.flared_litres += 999
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_flare"), 0)
	test.statistics.flared_litres += 1
	run_quest_tick(&test)
	test.statistics.flared_litres += 1000
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_flare"), 1)
	testing.expect_value(t, test.state.hints_fired, 2)
}
