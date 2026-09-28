package game

import "core:testing"

// Chapter 2 (data/quests/chapter_02.sjson): the burner drill comes before
// the fifty plates (work item 0096), and the drill_no_vein_attempts hint
// counter it added.

chapter_02_registry :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[1:2], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

// A quest test on chapter 2 alone, with statistics sized for every machine.
make_chapter_02_test :: proc() -> Quest_Test {
	references := make_test_quest_references()
	registry := chapter_02_registry(references)
	test := make_quest_test(registry.quests, registry.chapters)
	test.statistics = make_statistics(len(test.items.items), len(test.machines.machines), 4, context.temp_allocator)
	return test
}

@(test)
test_chapter_02_loads_with_the_drill_before_the_plates :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := chapter_02_registry(references)
	ids := [?]string{"furnaces", "copper", "gears", "drill", "plates", "storage", "survey", "invoice"}
	testing.expect_value(t, len(registry.quests), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.quests[index].id, id)
	}
	drill := registry.quests[3]
	testing.expect_value(t, drill.objectives[0].type, Objective_Type.Place)
	testing.expect_value(t, drill.objectives[0].machine, test_machine(references.machines, "burner_mining_drill"))
	testing.expect_value(t, drill.hints[0].counter, Hint_Counter.Drill_No_Vein_Attempts)
	plates := registry.quests[4]
	testing.expect_value(t, plates.objectives[0].type, Objective_Type.Craft)
	testing.expect_value(t, plates.objectives[0].item, test_item(references.items, "iron_plate"))
	testing.expect_value(t, plates.objectives[0].count, 50)
	testing.expect(t, plates.objectives[0].produced_since_active)
	testing.expect(t, registry.quests[7].main)
}

// Plates made before the plates quest do not count, and no number of
// plates passes the drill quest without a drill placed.
@(test)
test_chapter_02_drill_gates_the_plates :: proc(t: ^testing.T) {
	test := make_chapter_02_test()
	defer destroy_quest_test(&test)
	plate := test_item(test.items, "iron_plate")
	set_placed(&test, "stone_furnace", 3)
	test.statistics.produced[test_item(test.items, "copper_plate")] = 10
	test.statistics.produced[test_item(test.items, "iron_gear")] = 10
	test.statistics.produced[plate] = 200
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "drill")
	// Place refused twice for want of a vein brings the hint once.
	test.statistics.drill_no_vein_attempts = 1
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_drill_no_vein"), 0)
	test.statistics.drill_no_vein_attempts = 5
	run_quest_tick(&test)
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_drill_no_vein"), 1)
	testing.expect_value(t, active_quest_id(&test), "drill")
	set_placed(&test, "burner_mining_drill", 1)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "plates")
	test.statistics.produced[plate] = 249
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "plates")
	test.statistics.produced[plate] = 250
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "storage")
}

// Every quest of the chapter in order on synthetic counters, ending with
// the invoice and the logistics parts landing in the capsule.
@(test)
test_chapter_02_completes_in_order :: proc(t: ^testing.T) {
	test := make_chapter_02_test()
	defer destroy_quest_test(&test)
	plate := test_item(test.items, "iron_plate")
	testing.expect_value(t, active_quest_id(&test), "furnaces")
	set_placed(&test, "stone_furnace", 3)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "copper")
	test.statistics.produced[test_item(test.items, "copper_plate")] = 10
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "gears")
	test.statistics.produced[test_item(test.items, "iron_gear")] = 10
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "drill")
	set_placed(&test, "burner_mining_drill", 1)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "plates")
	testing.expect(t, has_message(&test, "mc_plates"))
	test.statistics.produced[plate] = 50
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "storage")
	test.statistics.produced[test_item(test.items, "iron_chest")] = 1
	set_placed(&test, "iron_chest", 1)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "survey")
	for id in ([?]string{"charcoal", "glass", "electronic_circuit"}) {
		test.unlocks.available[test_recipe(test.recipes, id)] = true
	}
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "invoice")
	slots := capsule_slots(&test)
	slots[0] = {plate, 100}
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect(t, chapter_done(test.state, test.registry.chapters[0]))
	testing.expect(t, has_message(&test, "mc_invoice_done"))
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "belt")), 20)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "burner_inserter")), 4)
}

// The spent outcrop line is logged whatever quest is active, one line per
// counted outcrop, and never again for the same count.
@(test)
test_spent_outcrops_are_announced_once :: proc(t: ^testing.T) {
	test := make_chapter_02_test()
	defer destroy_quest_test(&test)
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, OUTCROP_SPENT_KEY), 0)
	test.statistics.outcrops_spent = 1
	run_quest_tick(&test)
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, OUTCROP_SPENT_KEY), 1)
	testing.expect_value(t, test.statistics.outcrops_spent_announced, 1)
	test.statistics.outcrops_spent = 3
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, OUTCROP_SPENT_KEY), 3)
}
