package game

import "core:testing"

// A synthetic chapter setup: statistics, unlocks and a capsule in its own
// entity pools, with the shipped items, recipes and machines.
Quest_Test :: struct {
	items:      Item_Registry,
	recipes:    Recipe_Registry,
	machines:   Machine_Registry,
	registry:   Quest_Registry,
	state:      Quest_State,
	statistics: Statistics,
	unlocks:    Recipe_Unlocks,
	entities:   Entities,
	tick:       u64,
}

TEST_LANDING_PAD :: Landing_Pad_Site {
	present = true,
	centre  = {0, 10, 0},
}

make_quest_test :: proc(quests: []Quest, chapters: []Chapter) -> Quest_Test {
	items := make_test_items()
	recipes, technologies := make_test_recipes(items)
	test := Quest_Test {
		items = items,
		recipes = recipes,
		machines = make_test_machines(),
		registry = Quest_Registry{chapters = chapters, quests = quests},
		statistics = make_statistics(len(items.items), 4, 4, context.temp_allocator),
		unlocks = make_recipe_unlocks(len(items.items), recipes, technologies, false, context.temp_allocator),
	}
	capsule := place_capsule(&test.entities, test.machines, TEST_LANDING_PAD)
	test.state = make_quest_state(test.registry, capsule, context.temp_allocator)
	start_quests(&test.state, test.registry, test.statistics, 0)
	return test
}

destroy_quest_test :: proc(test: ^Quest_Test) {
	destroy_entities(&test.entities)
	delete(test.state.pending_rewards)
	delete(test.state.messages)
	delete(test.state.notices)
}

run_quest_tick :: proc(test: ^Quest_Test) {
	test.tick += 1
	tick_context := Quest_Tick_Context {
		registry   = test.registry,
		recipes    = test.recipes,
		items      = test.items,
		statistics = &test.statistics,
		unlocks    = &test.unlocks,
		tick       = test.tick,
		tick_rate  = TEST_TICK_RATE,
	}
	tick_quests(&test.state, tick_context, &test.entities)
}

capsule_slots :: proc(test: ^Quest_Test) -> []Item_Stack {
	return entity_slots(&test.entities, test.state.capsule)
}

one_chapter :: proc(count: int) -> []Chapter {
	chapters := make([]Chapter, 1, context.temp_allocator)
	chapters[0] = Chapter{id = "chapter", title_key = "chapter", quest_count = count}
	return chapters
}

objective_quest :: proc(objectives: ..Objective) -> Quest {
	return Quest{id = "quest", objectives = slice_clone_temp(objectives)}
}

slice_clone_temp :: proc(values: []$T) -> []T {
	result := make([]T, len(values), context.temp_allocator)
	copy(result, values)
	return result
}

item_objective :: proc(type: Objective_Type, item: Item_Id, count: u64) -> Objective {
	return Objective{type = type, item = item, machine = NO_MACHINE, recipe = NO_RECIPE, technology = NO_TECHNOLOGY, count = count}
}

progress_of :: proc(test: ^Quest_Test, objective: Objective, progress: Quest_Progress) -> Objective_Progress {
	view := Quest_View{statistics = test.statistics, unlocks = test.unlocks, capsule_slots = capsule_slots(test), tick_rate = TEST_TICK_RATE}
	return objective_progress(objective, 0, progress, view)
}

@(test)
test_every_objective_type_against_counters :: proc(t: ^testing.T) {
	test := make_quest_test(nil, nil)
	defer destroy_quest_test(&test)
	log := test_item(test.items, "log")
	progress: Quest_Progress
	test.statistics.obtained[log] = 9
	testing.expect_value(t, progress_of(&test, item_objective(.Obtain, log, 10), progress), Objective_Progress{9, 10})
	test.statistics.produced[log] = 10
	testing.expect(t, objective_done(progress_of(&test, item_objective(.Craft, log, 10), progress)))
	place := item_objective(.Place, NO_ITEM, 3)
	place.machine = Machine_Id(1)
	test.statistics.placed[1] = 2
	testing.expect_value(t, progress_of(&test, place, progress), Objective_Progress{2, 3})
	test.statistics.distance_walked_millimetres = 10_400
	testing.expect_value(t, progress_of(&test, item_objective(.Walk, NO_ITEM, 10), progress), Objective_Progress{10, 10})
	research := item_objective(.Research, NO_ITEM, 0)
	research.technology = 2
	testing.expect_value(t, progress_of(&test, research, progress), Objective_Progress{0, 1})
	test.unlocks.researched[2] = true
	testing.expect(t, objective_done(progress_of(&test, research, progress)))
	discover := item_objective(.Discover, NO_ITEM, 0)
	discover.recipe = test_recipe(test.recipes, "glass")
	testing.expect(t, !objective_done(progress_of(&test, discover, progress)))
	test.unlocks.available[discover.recipe] = true
	testing.expect(t, objective_done(progress_of(&test, discover, progress)))
	sustain := item_objective(.Sustain, log, 0)
	sustain.minutes, sustain.rate_per_minute = 2, 10
	progress.sustained_ticks[0] = 5
	testing.expect_value(t, progress_of(&test, sustain, progress), Objective_Progress{5, 2 * 60 * TEST_TICK_RATE})
	// Deliver: what was put in since activation and is still in the capsule.
	progress.delivered_baselines[0] = 4
	test.statistics.delivered[log] = 10
	capsule_slots(&test)[0] = {log, 3}
	testing.expect_value(t, progress_of(&test, item_objective(.Deliver, log, 5), progress), Objective_Progress{3, 5})
	capsule_slots(&test)[1] = {log, 30}
	testing.expect_value(t, progress_of(&test, item_objective(.Deliver, log, 5), progress), Objective_Progress{6, 5})
}

@(test)
test_sustain_follows_the_rate_ring_and_breaks_hands_on :: proc(t: ^testing.T) {
	test := make_quest_test(nil, nil)
	defer destroy_quest_test(&test)
	plate := test_item(test.items, "iron_plate")
	objective := item_objective(.Sustain, plate, 0)
	objective.rate_per_minute, objective.minutes, objective.hands_off = 10, 1, true
	progress: Quest_Progress
	// Tick rate 1, one plate every 6 seconds: the rate reaches 10 at 60 s.
	for tick in u64(1) ..= 59 {
		advance_statistics_clock(&test.statistics, tick, 1)
		if tick % 6 == 0 {
			record_produced(&test.statistics, plate, 1)
		}
		advance_sustain(&progress, 0, objective, test.statistics)
	}
	testing.expect_value(t, progress.sustained_ticks[0], 0)
	for tick in u64(60) ..= 100 {
		advance_statistics_clock(&test.statistics, tick, 1)
		if tick % 6 == 0 {
			record_produced(&test.statistics, plate, 1)
		}
		advance_sustain(&progress, 0, objective, test.statistics)
	}
	testing.expect_value(t, progress.sustained_ticks[0], 41)
	// A world action breaks a hands off streak; the next tick starts over.
	record_world_action(&test.statistics)
	advance_sustain(&progress, 0, objective, test.statistics)
	testing.expect_value(t, progress.sustained_ticks[0], 0)
	advance_sustain(&progress, 0, objective, test.statistics)
	testing.expect_value(t, progress.sustained_ticks[0], 1)
	// Production stops: the rate drops below the target within seconds.
	advance_statistics_clock(&test.statistics, 110, 1)
	advance_sustain(&progress, 0, objective, test.statistics)
	testing.expect_value(t, progress.sustained_ticks[0], 0)
	// Without hands_off, world actions do not matter.
	objective.hands_off = false
	advance_statistics_clock(&test.statistics, 111, 1)
	record_produced(&test.statistics, plate, 20)
	record_world_action(&test.statistics)
	advance_sustain(&progress, 0, objective, test.statistics)
	testing.expect_value(t, progress.sustained_ticks[0], 1)
}

@(test)
test_hint_fires_once_after_its_threshold :: proc(t: ^testing.T) {
	quest := objective_quest(item_objective(.Obtain, Item_Id(0), 1000))
	hints := make([]Hint, 1, context.temp_allocator)
	hints[0] = Hint{counter = .Blocks_Mined, threshold = 3, text_key = "hint"}
	quest.hints = hints
	test := make_quest_test({quest}, one_chapter(1))
	defer destroy_quest_test(&test)
	test.statistics.blocks_mined = 5
	// The baseline was taken at activation, with nothing mined.
	test.state.progress[0].hint_baselines[0] = 5
	test.statistics.blocks_mined = 7
	run_quest_tick(&test)
	testing.expect_value(t, test.state.hints_fired, 0)
	test.statistics.blocks_mined = 8
	run_quest_tick(&test)
	test.statistics.blocks_mined = 20
	run_quest_tick(&test)
	testing.expect_value(t, test.state.hints_fired, 1)
	testing.expect_value(t, len(test.state.messages), 1)
	testing.expect_value(t, test.state.messages[0], Quest_Message{tick = 2, text_key = "hint"})
	testing.expect_value(t, test.state.notices[0], "hint")
}

@(test)
test_chapters_complete_in_order_and_deliver_rewards :: proc(t: ^testing.T) {
	items := make_test_items()
	recipes, _ := make_test_recipes(items)
	log, coal := test_item(items, "log"), test_item(items, "coal")
	first := objective_quest(item_objective(.Obtain, log, 1))
	first.id, first.message_key, first.complete_key = "first", "first_message", "first_done"
	main_quest := objective_quest(item_objective(.Obtain, log, 2))
	main_quest.id, main_quest.main, main_quest.message_key = "main", true, "main_message"
	main_quest.reward_items = slice_clone_temp([]Item_Stack{{coal, 50}, {log, 5}})
	main_quest.reward_recipes = slice_clone_temp([]int{test_recipe(recipes, "steam_engine")})
	second_chapter := objective_quest(item_objective(.Obtain, log, 100))
	second_chapter.id, second_chapter.message_key = "next", "next_message"
	chapters := []Chapter{{id = "one", quest_count = 2}, {id = "two", first_quest = 2, quest_count = 1}}
	test := make_quest_test({first, main_quest, second_chapter}, chapters)
	defer destroy_quest_test(&test)
	testing.expect_value(t, test.state.active, 0)
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, 0)
	test.statistics.obtained[log] = 1
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, 1)
	testing.expect_value(t, quest_status(test.state, 0), Quest_Status.Done)
	testing.expect(t, !chapter_done(test.state, chapters[0]))
	testing.expect(t, !recipe_is_available(test.unlocks, test_recipe(recipes, "steam_engine")))
	test.statistics.obtained[log] = 2
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, 2)
	testing.expect(t, chapter_done(test.state, chapters[0]))
	testing.expect_value(t, quest_status(test.state, 2), Quest_Status.Active)
	testing.expect(t, recipe_is_available(test.unlocks, test_recipe(recipes, "steam_engine")))
	slots := capsule_slots(&test)
	testing.expect_value(t, slots[0], Item_Stack{coal, 50})
	testing.expect_value(t, slots[1], Item_Stack{log, 5})
	testing.expect_value(t, len(test.state.pending_rewards), 0)
	keys := [?]string{"first_message", "first_done", "main_message", "next_message"}
	testing.expect_value(t, len(test.state.messages), len(keys))
	for key, index in keys {
		testing.expect_value(t, test.state.messages[index].text_key, key)
	}
	testing.expect_value(t, test.state.notices[len(test.state.notices) - 1], CAPSULE_LANDED_KEY)
	// Landing is not a delivery.
	testing.expect_value(t, test.statistics.delivered[log], 0)
	test.statistics.obtained[log] = 100
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	run_quest_tick(&test)
}

@(test)
test_rewards_wait_for_room_in_the_capsule :: proc(t: ^testing.T) {
	test := make_quest_test(nil, nil)
	defer destroy_quest_test(&test)
	stone, coal := test_item(test.items, "stone"), test_item(test.items, "coal")
	slots := capsule_slots(&test)
	for &slot in slots {
		slot = {stone, 50}
	}
	append(&test.state.pending_rewards, Item_Stack{coal, 60})
	run_quest_tick(&test)
	testing.expect_value(t, test.state.pending_rewards[0], Item_Stack{coal, 60})
	testing.expect_value(t, len(test.state.notices), 0)
	slots[3] = EMPTY_STACK
	run_quest_tick(&test)
	testing.expect_value(t, slots[3], Item_Stack{coal, 50})
	testing.expect_value(t, test.state.pending_rewards[0], Item_Stack{coal, 10})
	testing.expect_value(t, test.state.notices[0], CAPSULE_LANDED_KEY)
	slots[5] = EMPTY_STACK
	run_quest_tick(&test)
	testing.expect_value(t, slots[5], Item_Stack{coal, 10})
	testing.expect_value(t, len(test.state.pending_rewards), 0)
	testing.expect_value(t, test.statistics.delivered[coal], 0)
}

@(test)
test_deliver_counts_items_put_into_the_capsule :: proc(t: ^testing.T) {
	items := make_test_items()
	plate := test_item(items, "iron_plate")
	quest := objective_quest(item_objective(.Deliver, plate, 5))
	test := make_quest_test({quest}, one_chapter(1))
	defer destroy_quest_test(&test)
	slots := capsule_slots(&test)
	// Plates that landed as a reward do not count.
	append(&test.state.pending_rewards, Item_Stack{plate, 10})
	run_quest_tick(&test)
	testing.expect_value(t, slots[0], Item_Stack{plate, 10})
	slots[1] = {plate, 3}
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, 0)
	slots[1] = {plate, 1}
	run_quest_tick(&test)
	slots[2] = {plate, 4}
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect_value(t, slots_item_count(slots, plate), 10)
}

@(test)
test_capsule_is_not_picked_up :: proc(t: ^testing.T) {
	content := make_test_content()
	world: World
	defer destroy_world(&world)
	handle := place_capsule(&world.entities, content.machines, TEST_LANDING_PAD)
	testing.expect(t, entity_is_alive(&world.entities, handle))
	testing.expect_value(t, len(entity_slots(&world.entities, handle)), CAPSULE_SLOT_COUNT)
	player := make_test_player(content.blocks, {})
	testing.expect(t, !pick_up_entity(&world, content, &player, handle))
	testing.expect(t, entity_is_alive(&world.entities, handle))
}

make_quest_simulation :: proc(generator: ^Generator, content: Simulation_Content) -> Simulation_State {
	surface := World_Coordinate{8, terrain_height(generator.seeds, 8, 8), 8}
	generator.landing_pad = Landing_Pad_Site{present = true, centre = surface}
	_, technologies := make_test_recipes(content.items)
	simulation := make_simulation(test_game_config(), player_start_on(surface), content, technologies, false, generator.landing_pad)
	generated := make_generated_world(generator, world_to_chunk_coordinate(surface))
	generated.statistics = simulation.world.statistics
	generated.entities = simulation.world.entities
	simulation.world = generated
	return simulation
}

// Walks sideways (away from the capsule) with jumps, then the recorded
// input of the player determinism test.
quest_test_input :: proc(tick: int) -> Input_Frame {
	if tick < 300 {
		return Input_Frame{move = {1, 0}, pressed = {.Jump}}
	}
	return recorded_input(tick)
}

expect_same_quest_state :: proc(t: ^testing.T, a, b: Simulation_State) {
	testing.expect_value(t, a.quests.active, b.quests.active)
	testing.expect_value(t, len(a.quests.messages), len(b.quests.messages))
	for message, index in a.quests.messages {
		testing.expect_value(t, message, b.quests.messages[index])
	}
	for progress, index in a.quests.progress {
		testing.expect_value(t, progress, b.quests.progress[index])
	}
	for value, index in a.world.statistics.obtained {
		testing.expect_value(t, value, b.world.statistics.obtained[index])
	}
	for value, index in a.world.statistics.mining_ticks {
		testing.expect_value(t, value, b.world.statistics.mining_ticks[index])
	}
	testing.expect_value(t, a.world.statistics.distance_walked_millimetres, b.world.statistics.distance_walked_millimetres)
	testing.expect_value(t, a.world.statistics.world_actions, b.world.statistics.world_actions)
}

@(test)
test_quest_simulation_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	content.quests = make_test_quests(make_test_quest_references())
	first_generator := make_test_generator(DEFAULT_WORLD_SEED)
	second_generator := make_test_generator(DEFAULT_WORLD_SEED)
	first := make_quest_simulation(&first_generator, content)
	defer destroy_simulation(&first)
	second := make_quest_simulation(&second_generator, content)
	defer destroy_simulation(&second)
	centre := first_generator.landing_pad.centre
	testing.expect_value(t, world_get_block(&first.world, centre), test_block(content.blocks, "landing_pad"))
	testing.expect_value(t, world_get_block(&first.world, centre + {0, 1, 0}), AIR_BLOCK)
	testing.expect_value(t, entity_at(&first.world.entities, centre + CAPSULE_OFFSET), first.quests.capsule)
	testing.expect_value(t, first.quests.messages[0], Quest_Message{tick = 0, text_key = "mc_arrival"})
	for tick in 0 ..< 1200 {
		input := quest_test_input(tick)
		simulation_tick(&first, content, {input})
		simulation_tick(&second, content, {input})
	}
	expect_same_quest_state(t, first, second)
	bearings := test_quest_index(content.quests, "bearings")
	testing.expect_value(t, quest_status(first.quests, 0), Quest_Status.Done)
	testing.expectf(t, quest_status(first.quests, bearings) == .Done, "walked %d mm", first.world.statistics.distance_walked_millimetres)
	testing.expect(t, first.quests.active > bearings)
}
