package game

import "core:testing"

// Chapter 3 (data/quests/chapter_03.sjson) and the hint counters it
// added: belt_dead_end_ticks, inserter_idle_a_minute, drill_fuel_burned.

chapter_03_registry :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[2:3], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

// A quest test on chapter 3 alone, with statistics sized for every machine.
make_chapter_03_test :: proc() -> Quest_Test {
	references := make_test_quest_references()
	registry := chapter_03_registry(references)
	test := make_quest_test(registry.quests, registry.chapters)
	test.statistics = make_statistics(len(test.items.items), len(test.machines.machines), 4, context.temp_allocator)
	return test
}

active_quest_id :: proc(test: ^Quest_Test) -> string {
	return test.state.active == NO_QUEST ? "" : test.registry.quests[test.state.active].id
}

has_message :: proc(test: ^Quest_Test, key: string) -> bool {
	for message in test.state.messages {
		if message.text_key == key {
			return true
		}
	}
	return false
}

message_count :: proc(test: ^Quest_Test, key: string) -> int {
	count := 0
	for message in test.state.messages {
		count += message.text_key == key ? 1 : 0
	}
	return count
}

set_placed :: proc(test: ^Quest_Test, machine: string, count: u64) {
	test.statistics.placed[test_machine(test.machines, machine)] = count
}

@(test)
test_chapter_03_loads :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := chapter_03_registry(references)
	ids := [?]string{"belt_parts", "connect", "coal_loop", "plate_line", "four_drills", "prove"}
	testing.expect_value(t, len(registry.quests), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.quests[index].id, id)
	}
	connect := registry.quests[1]
	testing.expect(t, connect.objectives[3].produced_since_active)
	testing.expect_value(t, connect.hints[0].counter, Hint_Counter.Belt_Dead_End_Ticks)
	testing.expect_value(t, connect.hints[1].counter, Hint_Counter.Inserter_Idle_A_Minute)
	coal_loop := registry.quests[2]
	testing.expect_value(t, coal_loop.objectives[0].type, Objective_Type.Counter)
	testing.expect_value(t, coal_loop.objectives[0].counter, Hint_Counter.Drill_Fuel_Burned)
	testing.expect_value(t, coal_loop.hints[0].counter, Hint_Counter.Drill_Out_Of_Fuel)
	prove := registry.quests[5]
	testing.expect(t, prove.main)
	// No hands off and a five second window (user, 2026-09-27): a quest that
	// makes the player wait is not fun.
	testing.expect(t, !prove.objectives[0].hands_off)
	testing.expect_value(t, prove.objectives[0].rate_per_minute, 40)
	testing.expect_value(t, sustain_required_ticks(prove.objectives[0], TEST_TICK_RATE), 5 * TEST_TICK_RATE)
	testing.expect_value(t, prove.reward_recipes[0], test_recipe(references.recipes, "steam_engine"))
	testing.expect_value(t, len(prove.reward_items), 3)
	testing.expect_value(t, references.recipes.recipes[prove.reward_recipes[0]].channel, Recipe_Channel.Quest)
}

// Two belts along +x with one plate; the plate stops at the dead end on
// tick 44 (128 + 8 * 44 = 480, the end less the margin).
@(test)
test_belt_dead_end_counts_held_ticks :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {0, 1, 0}, 2, 0)
	plate := test_item(content.items, "iron_plate")
	testing.expect(t, belt_insert_item(&world.entities, belts[0], .Left, plate))
	tick_test_entities(&world, content, 43)
	testing.expect_value(t, world.statistics.belt_dead_end_ticks, 0)
	tick_test_entities(&world, content, 57)
	testing.expect_value(t, world.statistics.belt_dead_end_ticks, 57)
	// An inserter over the last block (unfuelled, so it leaves the plate)
	// makes the end a feed.
	place_test_entity(&world, content, "burner_inserter", {1, 1, 1}, 1)
	tick_test_entities(&world, content, 100)
	testing.expect_value(t, world.statistics.belt_dead_end_ticks, 57)
}

@(test)
test_inserter_idle_minute_counts_uninterrupted_idling :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pair := make_chest_pair(&world, content)
	tick_test_entities(&world, content, 3599)
	testing.expect_value(t, world.statistics.inserters_idle_a_minute, 0)
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, world.statistics.inserters_idle_a_minute, 1)
	tick_test_entities(&world, content, 3600)
	testing.expect_value(t, world.statistics.inserters_idle_a_minute, 1)
	// Work breaks the streak; the next full minute counts again.
	entity_insert(&world.entities, content, pair.source, Item_Stack{test_item(content.items, "iron_plate"), 1})
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, test_inserter(&world, pair.inserter).idle_streak, 0)
	tick_test_entities(&world, content, 100 + 3600)
	testing.expect_value(t, world.statistics.inserters_idle_a_minute, 2)
}

@(test)
test_chapter_03_hints_fire_once :: proc(t: ^testing.T) {
	test := make_chapter_03_test()
	defer destroy_quest_test(&test)
	test.statistics.produced[test_item(test.items, "belt")] = 4
	test.statistics.produced[test_item(test.items, "burner_inserter")] = 1
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "connect")
	test.statistics.belt_dead_end_ticks = 3599
	run_quest_tick(&test)
	testing.expect_value(t, test.state.hints_fired, 0)
	test.statistics.belt_dead_end_ticks = 3600
	test.statistics.inserters_idle_a_minute = 1
	run_quest_tick(&test)
	test.statistics.belt_dead_end_ticks = 20_000
	test.statistics.inserters_idle_a_minute = 5
	run_quest_tick(&test)
	testing.expect_value(t, test.state.hints_fired, 2)
	testing.expect_value(t, message_count(&test, "mc_hint_dead_end"), 1)
	testing.expect_value(t, message_count(&test, "mc_hint_idle_inserter"), 1)
}

// Every quest of the chapter in order on synthetic counters, ending with
// the unattended run that unlocks the steam engine.
@(test)
test_chapter_03_completes_in_order :: proc(t: ^testing.T) {
	test := make_chapter_03_test()
	defer destroy_quest_test(&test)
	plate := test_item(test.items, "iron_plate")
	steam_engine := test_recipe(test.recipes, "steam_engine")
	test.statistics.produced[plate] = 100
	testing.expect_value(t, active_quest_id(&test), "belt_parts")
	test.statistics.produced[test_item(test.items, "belt")] = 4
	test.statistics.produced[test_item(test.items, "burner_inserter")] = 1
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "connect")
	set_placed(&test, "burner_mining_drill", 1)
	set_placed(&test, "belt", 2)
	set_placed(&test, "burner_inserter", 1)
	// Plates from before the quest do not count.
	test.statistics.produced[plate] = 109
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "connect")
	test.statistics.produced[plate] = 110
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "coal_loop")
	test.statistics.stalls[.Drill_Out_Of_Fuel] = 2
	test.statistics.drill_fuel_burned = 9
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_drill_fuel"), 1)
	testing.expect_value(t, active_quest_id(&test), "coal_loop")
	test.statistics.drill_fuel_burned = 10
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "plate_line")
	set_placed(&test, "wooden_chest", 1)
	test.statistics.produced[plate] = 159
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "plate_line")
	test.statistics.produced[plate] = 160
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "four_drills")
	set_placed(&test, "burner_mining_drill", 4)
	set_placed(&test, "stone_furnace", 3)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "prove")
	testing.expect(t, !recipe_is_available(test.unlocks, steam_engine))
	ticks := run_plate_line_until_done(&test, plate)
	// Up to a minute to reach the rate, then five seconds at it.
	testing.expectf(t, ticks > 5 * TEST_TICK_RATE && ticks <= 66 * TEST_TICK_RATE, "took %d ticks", ticks)
	testing.expect(t, chapter_done(test.state, test.registry.chapters[0]))
	testing.expect(t, recipe_is_available(test.unlocks, steam_engine))
	testing.expect(t, has_message(&test, "mc_prove_done"))
	slots := capsule_slots(&test)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "offshore_pump")), 1)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "boiler")), 1)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "pipe")), 10)
}

// Four plates every 6 seconds (40 per minute) until the quests run out;
// returns the ticks it took. Batches on the six second mark keep the
// minute window at 40 once it is full; a plate every 90 ticks would let
// it dip to 39 around second boundaries.
run_plate_line_until_done :: proc(test: ^Quest_Test, plate: Item_Id) -> int {
	start := test.tick
	for _ in 0 ..< 12 * 60 * TEST_TICK_RATE {
		if test.state.active == NO_QUEST {
			break
		}
		advance_statistics_clock(&test.statistics, test.tick + 1, TEST_TICK_RATE)
		if (test.tick + 1) % (6 * TEST_TICK_RATE) == 0 {
			record_produced(&test.statistics, plate, 4)
		}
		run_quest_tick(test)
	}
	return int(test.tick - start)
}
