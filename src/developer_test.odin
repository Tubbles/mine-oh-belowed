package game

import "base:runtime"
import "core:strings"
import "core:testing"

// Developer mode (work item 0043): the kits data, the command line, the
// requests the simulation serves, and the crash text for the log.

make_test_developer_kits :: proc(items: Item_Registry) -> Developer_Kits {
	file, error := parse_developer_kits_file(#load("../data/dev_kits.sjson"), context.temp_allocator)
	assert(error == nil)
	kits, problem := resolve_developer_kits(file, items, context.temp_allocator)
	assert(problem == "", problem)
	return kits
}

// The shipped quest content with the kits, and a simulation standing on
// the save test's landing pad. No chunks are loaded.
make_developer_test_simulation :: proc() -> (Simulation_State, Simulation_Content) {
	content := make_save_test_content()
	content.developer_kits = make_test_developer_kits(content.items)
	simulation := make_simulation(test_game_config(), player_start_on({0, 10, 0}), content, content.technologies, false, TEST_LANDING_PAD)
	return simulation, content
}

pending_count :: proc(pending: []Item_Stack, item: Item_Id) -> u64 {
	return slots_item_count(pending, item)
}

@(test)
test_shipped_developer_kits_resolve :: proc(t: ^testing.T) {
	items := make_test_items()
	kits := make_test_developer_kits(items)
	testing.expect_value(t, len(kits.kits), 8)
	for kit, index in kits.kits {
		testing.expectf(t, len(kit) > 0, "the kit of chapter %d is empty", index + 1)
	}
	chapter_files, found := quest_file_names("data/quests", context.temp_allocator)
	testing.expect(t, found)
	testing.expectf(t, len(kits.kits) >= len(chapter_files), "%d chapters in data/quests but %d kits", len(chapter_files), len(kits.kits))
	testing.expect_value(t, kits.kits[3][0], Developer_Grant{test_item(items, "iron_pickaxe"), 1})
}

@(test)
test_developer_kits_reject_unknown_items_and_gaps :: proc(t: ^testing.T) {
	items := make_test_items()
	unknown := [?]Developer_Kit_Item_Definition{{item = "no_such_item", count = 1}}
	file := Developer_Kits_File{kits = {{chapter = 1, items = unknown[:]}}}
	_, problem := resolve_developer_kits(file, items, context.temp_allocator)
	testing.expect(t, strings.contains(problem, "no_such_item"), problem)

	zero := [?]Developer_Kit_Item_Definition{{item = "log", count = 0}}
	file = Developer_Kits_File{kits = {{chapter = 1, items = zero[:]}}}
	_, problem = resolve_developer_kits(file, items, context.temp_allocator)
	testing.expect(t, problem != "")

	logs := [?]Developer_Kit_Item_Definition{{item = "log", count = 5}}
	file = Developer_Kits_File{kits = {{chapter = 2, items = logs[:]}}}
	_, problem = resolve_developer_kits(file, items, context.temp_allocator)
	testing.expect(t, strings.contains(problem, "expected chapter 1"), problem)
}

@(test)
test_give_argument_parsing :: proc(t: ^testing.T) {
	item, count, ok := parse_give_argument("iron_plate:50")
	testing.expect(t, ok)
	testing.expect_value(t, item, "iron_plate")
	testing.expect_value(t, count, 50)
	bad := [?]string{"iron_plate", ":5", "iron_plate:", "iron_plate:0", "iron_plate:-1", "iron_plate:+5", "iron_plate:5a", "iron_plate:10001", "iron_plate:1_0"}
	for value in bad {
		_, _, bad_ok := parse_give_argument(value)
		testing.expectf(t, !bad_ok, "%q parsed", value)
	}
	testing.expect_value(t, give_arguments_problem({"iron_plate:5", "coal:1"}), "")
	testing.expect(t, give_arguments_problem({"iron_plate:5", "coal"}) != "")

	items := make_test_items()
	grants, problem := resolve_give_arguments({"iron_plate:5", "coal:7"}, items)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, grants[1], Developer_Grant{test_item(items, "coal"), 7})
	_, problem = resolve_give_arguments({"nonsense:5"}, items)
	testing.expect(t, strings.contains(problem, "nonsense"), problem)
}

@(test)
test_chapter_flag_checks_the_kits :: proc(t: ^testing.T) {
	items := make_test_items()
	kits := make_test_developer_kits(items)
	_, problem := command_line_data_problem(Command_Line{chapter = 9}, items, kits)
	testing.expect(t, problem != "")
	command_line := Command_Line{chapter = 8}
	append(&command_line.give_arguments, "iron_plate:3")
	defer delete(command_line.give_arguments)
	grants: []Developer_Grant
	grants, problem = command_line_data_problem(command_line, items, kits)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(grants), 1)
	testing.expect_value(t, command_line_value_problem(Command_Line{chapter = -1}) != "", true)
	testing.expect(t, command_line_starts_world(Command_Line{chapter = 2}))
	testing.expect(t, command_line_conflict(Command_Line{load_name = "x", chapter = 2}) != "")

	requests := make([dynamic]Developer_Request, context.temp_allocator)
	command_line_developer_requests(&requests, 4, grants)
	testing.expect_value(t, len(requests), 3)
	testing.expect_value(t, requests[0], Developer_Request{action = .Complete_Quests_To_Chapter, chapter = 4})
	testing.expect_value(t, requests[1], Developer_Request{action = .Give_Kit, chapter = 4})
	testing.expect_value(t, requests[2].action, Developer_Action.Give_Item)
}

@(test)
test_give_overflows_to_the_capsule :: proc(t: ^testing.T) {
	items := make_test_items()
	player := make_player({}, context.temp_allocator)
	stone, plate := test_item(items, "stone"), test_item(items, "iron_plate")
	// Every slot but one full of stone.
	testing.expect_value(t, inventory_add(player.inventory, items, stone, (PLAYER_INVENTORY_SLOT_COUNT - 1) * 50), 0)
	pending := make([dynamic]Item_Stack, context.temp_allocator)
	give_to_player(&player, &pending, items, Developer_Grant{plate, 130})
	testing.expect_value(t, inventory_count(player.inventory, plate), 50)
	testing.expect_value(t, len(pending), 2)
	testing.expect_value(t, pending[0], Item_Stack{plate, 50})
	testing.expect_value(t, pending[1], Item_Stack{plate, 30})
}

// Chapter 4: chapters 1 to 3 done with their rewards queued and the
// steam engine recipe unlocked, the first quest of chapter 4 active, one
// message in the log for it.
@(test)
test_complete_quests_to_chapter_delivers_rewards :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := make_test_quests(references)
	test := make_quest_test(registry.quests, registry.chapters)
	defer destroy_quest_test(&test)
	messages_before := len(test.state.messages)
	complete_quests_to_chapter(&test.state, test.registry, &test.unlocks, test.recipes, test.statistics, 5, 4)
	first := registry.chapters[3].first_quest
	for index in 0 ..< first {
		testing.expect_value(t, test.state.progress[index].status, Quest_Status.Done)
	}
	testing.expect_value(t, test.state.active, first)
	testing.expect_value(t, test.state.progress[first].status, Quest_Status.Active)
	testing.expect_value(t, test.state.progress[first].activated_tick, 5)
	testing.expect_value(t, test.state.progress[first + 1].status, Quest_Status.Locked)
	items := test.items
	pending := test.state.pending_rewards[:]
	testing.expect_value(t, pending_count(pending, test_item(items, "coal")), 50)
	testing.expect_value(t, pending_count(pending, test_item(items, "belt")), 20)
	testing.expect_value(t, pending_count(pending, test_item(items, "offshore_pump")), 1)
	testing.expect(t, recipe_is_available(test.unlocks, test_recipe(test.recipes, "steam_engine")))
	testing.expect_value(t, len(test.state.messages), messages_before + 1)
	testing.expect_value(t, test.state.messages[len(test.state.messages) - 1].text_key, registry.quests[first].message_key)

	// An earlier chapter changes nothing.
	complete_quests_to_chapter(&test.state, test.registry, &test.unlocks, test.recipes, test.statistics, 6, 2)
	testing.expect_value(t, test.state.active, first)
	testing.expect_value(t, test.state.progress[first].activated_tick, 5)
}

// Chapter 9 is past the last (chapter 8): every quest is done, the quest
// gate technologies of the rewards are researched.
@(test)
test_complete_quests_past_the_last_chapter :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := make_test_quests(references)
	test := make_quest_test(registry.quests, registry.chapters)
	defer destroy_quest_test(&test)
	complete_quests_to_chapter(&test.state, test.registry, &test.unlocks, test.recipes, test.statistics, 1, 9)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect(t, chapter_done(test.state, registry.chapters[len(registry.chapters) - 1]))
	technologies := references.technologies
	for id in ([?]string{"oil_processing", "deep_mining", "rocket_program"}) {
		testing.expectf(t, test.unlocks.researched[test_technology(technologies, id)], "%s not researched", id)
	}
}

// --chapter=4 --give=iron_plate:3 served on the first tick.
@(test)
test_chapter_requests_served_by_the_tick :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	grants := [?]Developer_Grant{{test_item(content.items, "iron_plate"), 3}}
	command_line_developer_requests(&simulation.developer_requests, 4, grants[:])
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, len(simulation.developer_requests), 0)
	testing.expect_value(t, simulation.quests.active, content.quests.chapters[3].first_quest)
	player := simulation.players[0]
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "steam_engine")), 2)
	// 200 from the kit and 3 from --give; the chapter rewards wait for
	// the capsule.
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "iron_plate")), 203)
	testing.expect(t, simulation.unlocks.obtained[test_item(content.items, "boiler")])
}

@(test)
test_developer_toggles_teleport_and_unlock :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	requests := [?]Developer_Request{{action = .Toggle_Fly_Mode}}
	testing.expect(t, pending_toggle(false, requests[:], .Toggle_Fly_Mode))
	testing.expect(t, !pending_toggle(true, requests[:], .Toggle_Fly_Mode))

	position := landing_pad_standing_position(TEST_LANDING_PAD)
	testing.expect_value(t, position, [3]f32{0.5, 11, 0.5})
	append(&simulation.developer_requests, Developer_Request{action = .Toggle_Fly_Mode})
	append(&simulation.developer_requests, Developer_Request{action = .Teleport, position = position})
	append(&simulation.developer_requests, Developer_Request{action = .Unlock_All})
	serve_developer_requests(&simulation, content)
	player := simulation.players[0]
	testing.expect(t, player.flying)
	testing.expect_value(t, player.position, position)
	testing.expect_value(t, player.previous_position, position)
	testing.expect(t, simulation.unlocks.unlock_all)
	testing.expect_value(t, available_recipe_count(simulation.unlocks), len(content.recipes.recipes))
	testing.expect(t, make_world_file(&simulation, "test", 0).settings.all_recipes_unlocked)
}

@(test)
test_time_of_day_sets_the_day_cycle :: proc(t: ^testing.T) {
	day_length := u64(1200 * TEST_TICK_RATE)
	tick := u64(12_345)
	blends: [Time_Of_Day]f32
	for time_of_day in Time_Of_Day {
		offset := day_offset_for(tick, time_of_day_day_ticks(time_of_day, day_length), day_length)
		blends[time_of_day] = daylight_blend(tick + offset, day_length)
	}
	testing.expect_value(t, blends[.Noon], 1)
	testing.expect_value(t, blends[.Midnight], 0)
	testing.expectf(t, blends[.Dawn] > 0 && blends[.Dawn] < 1, "dawn %f", blends[.Dawn])
	testing.expectf(t, blends[.Dusk] > 0 && blends[.Dusk] < 1, "dusk %f", blends[.Dusk])

	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	simulation.tick = tick
	append(&simulation.developer_requests, Developer_Request{action = .Set_Time_Of_Day, time_of_day = .Midnight})
	serve_developer_requests(&simulation, content)
	testing.expect_value(t, simulation.tick, tick)
	testing.expect_value(t, daylight_blend(simulation_day_ticks(simulation), simulation.day_length_ticks), 0)
	// world.sjson keeps the day time, and loading turns it back into the
	// offset.
	file := make_world_file(&simulation, "test", 0)
	testing.expect_value(t, day_offset_for(file.tick, file.day_time_ticks, simulation.day_length_ticks), simulation.day_offset_ticks)
	testing.expect_value(t, day_offset_for(file.tick, file.tick % day_length, day_length), 0)
}

@(test)
test_assertion_failure_text :: proc(t: ^testing.T) {
	location := runtime.Source_Code_Location{file_path = "/src/game/belt.odin", line = 12, column = 3, procedure = "move_items"}
	testing.expect_value(t, assertion_failure_text("Assertion failure", "index in range", location), "crash: /src/game/belt.odin(12:3) in move_items: Assertion failure: index in range")
	testing.expect_value(t, assertion_failure_text("Panic", "", location), "crash: /src/game/belt.odin(12:3) in move_items: Panic")
	frames := [?]runtime.Source_Code_Location{{procedure = "game.move_items", file_path = "/src/game/belt.odin", line = 12}, {procedure = "0x1234", file_path = "/bin/game"}}
	testing.expect_value(t, back_trace_text(frames[:]), "back trace:\n\t#0 game.move_items at /src/game/belt.odin(12)\n\t#1 0x1234 at /bin/game\n")
}

// 0044: the statistics overlay is off in a fresh frame state and its key
// toggles it.
@(test)
test_world_overlay_starts_off_and_toggles :: proc(t: ^testing.T) {
	state: Frame_State
	testing.expect(t, !state.show_world_overlay)
	state.show_world_overlay = toggle_on_press(state.show_world_overlay, {.Toggle_World_Overlay}, .Toggle_World_Overlay)
	testing.expect(t, state.show_world_overlay)
	testing.expect(t, toggle_on_press(true, {.Toggle_Diagnostics}, .Toggle_World_Overlay))
	testing.expect(t, !toggle_on_press(true, {.Toggle_World_Overlay}, .Toggle_World_Overlay))
}

@(test)
test_developer_toggles_cheat_speed :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	testing.expect(t, !simulation.cheat_speed)
	requests := [?]Developer_Request{{action = .Toggle_Cheat_Speed}}
	testing.expect(t, pending_toggle(false, requests[:], .Toggle_Cheat_Speed))
	testing.expect(t, !pending_toggle(false, requests[:], .Toggle_Fly_Mode))
	append(&simulation.developer_requests, Developer_Request{action = .Toggle_Cheat_Speed})
	serve_developer_requests(&simulation, content)
	testing.expect(t, simulation.cheat_speed)
	append(&simulation.developer_requests, Developer_Request{action = .Toggle_Cheat_Speed})
	serve_developer_requests(&simulation, content)
	testing.expect(t, !simulation.cheat_speed)
}
