package game

import "core:testing"

// Chapter 5 (data/quests/chapter_05.sjson), the blocks_placed and recycled
// counters, activation hints and the technology reward.

chapter_05_registry :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[4:5], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_chapter_05_test :: proc() -> Quest_Test {
	references := make_test_quest_references()
	registry := chapter_05_registry(references)
	test := make_quest_test(registry.quests, registry.chapters)
	test.statistics = make_statistics(len(test.items.items), len(test.machines.machines), len(references.blocks.definitions), context.temp_allocator)
	return test
}

research_test_technology :: proc(test: ^Quest_Test, id: string) {
	technologies := make_test_quest_references().technologies
	mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, id))
}

@(test)
test_chapter_05_loads :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := chapter_05_registry(references)
	ids := [?]string{"low_grade", "processing_line", "slag", "alloys", "recycling", "statistics", "extraction_rights"}
	testing.expect_value(t, len(registry.quests), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.quests[index].id, id)
	}
	items, technologies := references.items, references.technologies
	low_grade := registry.quests[0]
	testing.expect_value(t, low_grade.objectives[0].technology, test_technology(technologies, "steel_processing"))
	testing.expect_value(t, low_grade.objectives[1].technology, test_technology(technologies, "ore_processing"))
	slag := registry.quests[2]
	testing.expect_value(t, slag.objectives[0].machine, NO_MACHINE)
	testing.expect_value(t, slag.objectives[0].item, test_item(items, "slag"))
	testing.expect_value(t, slag.objectives[1].item, test_item(items, "concrete"))
	testing.expect_value(t, slag.hints[0], Hint{counter = .Furnace_Output_Full, threshold = 3, text_key = "mc_hint_slag"})
	testing.expect_value(t, registry.quests[4].objectives[2].counter, Hint_Counter.Recycled)
	statistics := registry.quests[5]
	testing.expect_value(t, statistics.objectives[0].rate_per_minute, 30)
	testing.expect_value(t, statistics.objectives[0].seconds, 30)
	testing.expect_value(t, statistics.hints[0].threshold, 0)
	rights := registry.quests[6]
	testing.expect(t, rights.main)
	testing.expect_value(t, len(rights.reward_technologies), 1)
	testing.expect_value(t, rights.reward_technologies[0], test_technology(technologies, "oil_processing"))
	testing.expect(t, technologies.technologies[rights.reward_technologies[0]].quest_gate)
	testing.expect_value(t, rights.reward_items[0], Item_Stack{test_item(items, "steel"), 50})
	testing.expect_value(t, rights.reward_items[1], Item_Stack{test_item(items, "electronic_circuit"), 100})
}

// Completes low_grade with crushed hematite made before processing_line.
reach_processing_line :: proc(test: ^Quest_Test) {
	test.statistics.obtained[test_item(test.items, "hematite_low_grade")] = 20
	test.statistics.produced[test_item(test.items, "crushed_hematite")] = 30
	research_test_technology(test, "steel_processing")
	research_test_technology(test, "ore_processing")
	run_quest_tick(test)
}

complete_processing_line_to_alloys :: proc(t: ^testing.T, test: ^Quest_Test) {
	crushed := test_item(test.items, "crushed_hematite")
	set_placed(test, "crusher", 1)
	set_placed(test, "washer", 1)
	test.statistics.produced[crushed] = 79
	run_quest_tick(test)
	// Crushed hematite from before the quest does not count.
	testing.expect_value(t, active_quest_id(test), "processing_line")
	test.statistics.produced[crushed] = 80
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "slag")
	test.statistics.blocks_placed[test_item(test.items, "slag")] = 20
	test.statistics.blocks_placed[test_item(test.items, "concrete")] = 9
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "slag")
	test.statistics.blocks_placed[test_item(test.items, "concrete")] = 10
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "alloys")
}

complete_alloys_to_statistics :: proc(t: ^testing.T, test: ^Quest_Test) {
	test.statistics.produced[test_item(test.items, "bronze_plate")] = 40
	test.statistics.produced[test_item(test.items, "steel")] = 19
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "alloys")
	test.statistics.produced[test_item(test.items, "steel")] = 20
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "recycling")
	set_placed(test, "recycler", 1)
	test.statistics.recycled = 20
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "recycling")
	research_test_technology(test, "recycling")
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "statistics")
}

complete_statistics :: proc(t: ^testing.T, test: ^Quest_Test) {
	progress := &test.state.progress[test.state.active]
	progress.sustained_ticks[0] = 100
	// Nothing produced: the streak starts over.
	run_quest_tick(test)
	testing.expect_value(t, progress.sustained_ticks[0], 0)
	record_produced(&test.statistics, test_item(test.items, "iron_plate"), 30)
	progress.sustained_ticks[0] = 30 * TEST_TICK_RATE - 2
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "statistics")
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "extraction_rights")
}

// Every quest of the chapter in order on synthetic counters, ending with
// the delivery, oil processing researched and the pay in the capsule.
@(test)
test_chapter_05_completes_in_order :: proc(t: ^testing.T) {
	test := make_chapter_05_test()
	defer destroy_quest_test(&test)
	testing.expect_value(t, active_quest_id(&test), "low_grade")
	test.statistics.obtained[test_item(test.items, "hematite_low_grade")] = 20
	research_test_technology(&test, "steel_processing")
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "low_grade")
	reach_processing_line(&test)
	testing.expect_value(t, active_quest_id(&test), "processing_line")
	complete_processing_line_to_alloys(t, &test)
	complete_alloys_to_statistics(t, &test)
	complete_statistics(t, &test)
	concrete, brass := test_item(test.items, "concrete"), test_item(test.items, "brass_plate")
	slots := capsule_slots(&test)
	slots[0], slots[1], slots[2], slots[3] = {concrete, 50}, {concrete, 50}, {concrete, 50}, {concrete, 49}
	slots[4], slots[5] = {brass, 50}, {brass, 50}
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "extraction_rights")
	oil := test_technology(make_test_quest_references().technologies, "oil_processing")
	testing.expect(t, !test.unlocks.researched[oil])
	slots[3] = {concrete, 50}
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect(t, chapter_done(test.state, test.registry.chapters[0]))
	testing.expect(t, has_message(&test, "mc_extraction_rights_done"))
	testing.expect(t, test.unlocks.researched[oil])
	testing.expect_value(t, slots_item_count(slots, concrete), 0)
	testing.expect_value(t, slots_item_count(slots, brass), 0)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "steel")), 50)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "electronic_circuit")), 100)
}

// Hints count from activation: stalls and full inventories from before
// the quest do not fire them.
@(test)
test_chapter_05_hints_fire_once :: proc(t: ^testing.T) {
	test := make_chapter_05_test()
	defer destroy_quest_test(&test)
	test.statistics.stalls[.Output_Full] = 40
	test.statistics.inventory_full_ticks = 9000
	reach_processing_line(&test)
	set_placed(&test, "crusher", 1)
	set_placed(&test, "washer", 1)
	test.statistics.produced[test_item(test.items, "crushed_hematite")] = 80
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "slag")
	test.statistics.stalls[.Output_Full] += 2
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_slag"), 0)
	test.statistics.stalls[.Output_Full] += 1
	run_quest_tick(&test)
	test.statistics.stalls[.Output_Full] += 10
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_slag"), 1)
	test.statistics.blocks_placed[test_item(test.items, "slag")] = 20
	test.statistics.blocks_placed[test_item(test.items, "concrete")] = 10
	run_quest_tick(&test)
	complete_alloys_to_statistics_with_recycler_hint(t, &test)
	// The statistics hint fires in the tick the quest becomes active, once.
	testing.expect_value(t, message_count(&test, "mc_hint_statistics"), 1)
	run_quest_tick(&test)
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_statistics"), 1)
	testing.expect_value(t, test.state.hints_fired, 3)
}

complete_alloys_to_statistics_with_recycler_hint :: proc(t: ^testing.T, test: ^Quest_Test) {
	test.statistics.produced[test_item(test.items, "bronze_plate")] = 40
	test.statistics.produced[test_item(test.items, "steel")] = 20
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "recycling")
	test.statistics.inventory_full_ticks += 1799
	run_quest_tick(test)
	testing.expect_value(t, message_count(test, "mc_hint_recycler"), 0)
	test.statistics.inventory_full_ticks += 1
	run_quest_tick(test)
	testing.expect_value(t, message_count(test, "mc_hint_recycler"), 1)
	set_placed(test, "recycler", 1)
	test.statistics.recycled = 20
	research_test_technology(test, "recycling")
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "statistics")
}

// Placing a block counts it under the item that placed it; a finished
// recycling craft counts the items it took.
@(test)
test_blocks_placed_and_recycled_counters :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	concrete := test_item(items, "concrete")
	world := make_floor_world(registry, 32)
	world.statistics = make_statistics(len(items.items), 1, len(registry.definitions), context.temp_allocator)
	players := []Player{make_test_player(registry, {0.5, 1, 0.5})}
	player := &players[0]
	player.inventory.slots[0] = Item_Stack{concrete, 2}
	player.selected_hotbar_slot = 0
	player.target = Raycast_Hit{hit = true, block = {2, 0, 0}, face = .Positive_Y, adjacent = {2, 1, 0}}
	place_with_player(&world, Simulation_Content{blocks = registry, items = items, machines = make_test_machines()}, players, 0, {.Place})
	testing.expect_value(t, world.statistics.blocks_placed[concrete], 1)
	testing.expect_value(t, world.statistics.world_actions, 1)
	statistics := make_statistics(len(items.items), 1, 1, context.temp_allocator)
	assembler, gear := test_item(items, "assembler_1"), test_item(items, "iron_gear")
	inputs := []Item_Stack{{assembler, 1}}
	returns := []Item_Stack{{gear, 1}}
	record_craft_outputs(&statistics, Craft{inputs = inputs, outputs = returns, returns = true}, {}, {})
	record_craft_outputs(&statistics, Craft{inputs = inputs, outputs = returns, returns = true}, {}, {})
	testing.expect_value(t, statistics.recycled, 2)
	testing.expect_value(t, statistics.produced[gear], 2)
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Recycled}), 2)
}
