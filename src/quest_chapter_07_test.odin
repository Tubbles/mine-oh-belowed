package game

import "core:testing"

// Chapter 7 (data/quests/chapter_07.sjson), its counters (bore drill
// units, refused bore drill placements, turbine energy and turbines in
// still water) and the launch pad permit.

chapter_07_registry :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[6:7], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_chapter_07_test :: proc() -> Quest_Test {
	references := make_test_quest_references()
	registry := chapter_07_registry(references)
	test := make_quest_test(registry.quests, registry.chapters)
	test.statistics = make_statistics(len(test.items.items), len(test.machines.machines), len(references.blocks.definitions), context.temp_allocator)
	return test
}

@(test)
test_chapter_07_loads :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := chapter_07_registry(references)
	ids := [?]string{"second_vein", "deep_permit", "aluminium", "two_floors", "hydro", "grid", "schematic", "sixty", "launch_pad_permit"}
	testing.expect_value(t, len(registry.quests), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.quests[index].id, id)
	}
	items, technologies := references.items, references.technologies
	testing.expect_value(t, registry.quests[0].objectives[1].counter, Hint_Counter.Veins_Assayed)
	deep_permit := registry.quests[1]
	testing.expect_value(t, deep_permit.objectives[1].technology, test_technology(technologies, "logistics_science"))
	testing.expect_value(t, deep_permit.objectives[5].counter, Hint_Counter.Bore_Drill_Units)
	testing.expect_value(t, deep_permit.objectives[5].count, 200)
	testing.expect_value(t, deep_permit.hints[0], Hint{counter = .Bore_Drill_No_Vein_Attempts, threshold = 3, text_key = "mc_hint_bore_drill_no_vein"})
	two_floors := registry.quests[3]
	testing.expect_value(t, two_floors.objectives[1].machine, NO_MACHINE)
	testing.expect_value(t, two_floors.objectives[1].item, test_item(items, "concrete"))
	hydro := registry.quests[4]
	testing.expect_value(t, hydro.objectives[2].counter, Hint_Counter.Turbine_Kilojoules)
	testing.expect_value(t, hydro.objectives[2].count, 10_000)
	testing.expect_value(t, hydro.hints[0], Hint{counter = .Turbine_Still_Water_Ticks, threshold = 1, text_key = "mc_hint_turbine_still_water"})
	testing.expect_value(t, registry.quests[6].hints[0], Hint{counter = .Seismic_Shots, threshold = 1, text_key = "mc_hint_seismic"})
	sixty := registry.quests[7].objectives[0]
	testing.expect_value(t, sixty.rate_per_minute, 60)
	testing.expect_value(t, sixty.seconds, 30)
	permit := registry.quests[8]
	testing.expect(t, permit.main)
	testing.expect_value(t, len(permit.reward_technologies), 1)
	testing.expect_value(t, permit.reward_technologies[0], test_technology(technologies, "rocket_program"))
	testing.expect_value(t, permit.reward_items[0], Item_Stack{test_item(items, "steel"), 200})
	testing.expect_value(t, permit.reward_items[1], Item_Stack{test_item(items, "plastic_bar"), 100})
}

// A quest gate: it unlocks the launch pad and two rocket parts (work item
// 0040), and the labs refuse it even with its prerequisites researched.
@(test)
test_rocket_program_is_a_quest_gate :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	rocket_program := test_technology(technologies, "rocket_program")
	technology := technologies.technologies[rocket_program]
	testing.expect(t, !technology.placeholder)
	testing.expect(t, technology.quest_gate)
	testing.expect_value(t, len(technology.unlocks), 3)
	for id in ([?]string{"automation", "logistics", "steel_processing", "ore_processing", "oil_processing", "plastics", "logistics_science", "deep_mining", "electrolysis"}) {
		mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, id))
	}
	research: Research_State
	testing.expect(t, queue_research(&research, technologies, test.unlocks, rocket_program) != .None)
	testing.expect(t, !research.queued)
}

// Units leaving a bore drill count; boring counts nothing.
@(test)
test_bore_drill_units_are_counted :: proc(t: ^testing.T) {
	content := make_test_content()
	test := make_bore_drill_test(content)
	machine := test_crafting_machine(content, "bore_drill")
	test_drill(&test.world, test.drill).bored_ticks = drill_boring_ticks(machine, TEST_TICK_RATE) - 60
	tick_with_engine_offer(&test, content, 15_000, 60)
	testing.expect_value(t, test.records.statistics.bore_drill_units, 0)
	tick_with_engine_offer(&test, content, 15_000, 600)
	testing.expect_value(t, test.records.statistics.bore_drill_units, 10)
	testing.expect_value(t, chest_total(&test.world, test.chest), 10)
}

press_place :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, players: []Player) {
	place_entity_with_player(world, &records.statistics, content, players, 0, {.Place}, {.Place})
}

// Place with a bore drill over no deep vein counts; a footprint that is
// refused for another reason, or a valid one, does not.
@(test)
test_bore_drill_no_vein_attempts_are_counted :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_deep_mining_world(content)
	records := make_fluid_test_records(content)
	add_test_deep_vein(&world, content, "bauxite", {2, 2}, 2, {100, 20, 0, 0})
	players := []Player{make_test_player(content.blocks, {10, 1, 10})}
	player := &players[0]
	inventory_add(player.inventory, content.items, test_item(content.items, "bore_drill"), 1)
	player.target = Raycast_Hit{hit = true, block = {20, 0, 20}, face = .Positive_Y, adjacent = {20, 1, 20}}
	press_place(&world, &records, content, players)
	press_place(&world, &records, content, players)
	testing.expect_value(t, records.statistics.bore_drill_no_vein_attempts, 2)
	// Holding Place without a new press counts nothing.
	place_entity_with_player(&world, &records.statistics, content, players, 0, {}, {.Place})
	// No ground under the footprint: refused, but not for the vein.
	world_set_block(&world, {20, 0, 20}, AIR_BLOCK)
	press_place(&world, &records, content, players)
	testing.expect_value(t, records.statistics.bore_drill_no_vein_attempts, 2)
	// Over the vein the drill is placed and nothing more is counted.
	player.target = Raycast_Hit{hit = true, block = {1, 0, 1}, face = .Positive_Y, adjacent = {1, 1, 1}}
	press_place(&world, &records, content, players)
	testing.expect_value(t, len(world.entities.drills.entries), 1)
	testing.expect_value(t, records.statistics.bore_drill_no_vein_attempts, 2)
}

// Energy a turbine gives its network is counted, and a turbine standing
// in no flowing water counts once when it reaches ten seconds.
@(test)
test_turbine_counters :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	add_settled_source(t, &world, content, {0, 1, 0})
	turbine := place_test_entity(&world, content, "hydro_turbine", {1, 1, 0})
	place_test_entity(&world, content, "small_pole", {1, 1, 3})
	place_test_entity(&world, content, "lamp", {2, 1, 3})
	tick_electric_networks(&world, &records, content, TEST_TICK_RATE)
	testing.expect_value(t, records.statistics.turbine_joules, 83)
	tick_electric_networks(&world, &records, content, TEST_TICK_RATE)
	testing.expect_value(t, records.statistics.turbine_joules, 166)
	cells := common_cells(test_fluid_machine(&world, turbine).common, content.machines)
	set_water_level(&world, content, cells, 0)
	still_ticks := TURBINE_STILL_WATER_SECONDS * TEST_TICK_RATE
	for _ in 0 ..< still_ticks - 1 {
		tick_electric_networks(&world, &records, content, TEST_TICK_RATE)
	}
	testing.expect_value(t, records.statistics.turbine_still_water_ticks, 0)
	testing.expect_value(t, records.statistics.turbine_joules, 166)
	for _ in 0 ..< still_ticks + 1 {
		tick_electric_networks(&world, &records, content, TEST_TICK_RATE)
	}
	testing.expect_value(t, records.statistics.turbine_still_water_ticks, 1)
	// Water back breaks the streak; a new one counts again.
	set_water_level(&world, content, cells, WATER_FALLING_LEVEL)
	tick_electric_networks(&world, &records, content, TEST_TICK_RATE)
	testing.expect_value(t, test_fluid_machine(&world, turbine).still_water_ticks, 0)
	set_water_level(&world, content, cells, 0)
	for _ in 0 ..< still_ticks {
		tick_electric_networks(&world, &records, content, TEST_TICK_RATE)
	}
	testing.expect_value(t, records.statistics.turbine_still_water_ticks, 2)
}

complete_second_vein_to_aluminium :: proc(t: ^testing.T, test: ^Quest_Test) {
	research_test_technology(test, "prospecting")
	set_placed(test, "electric_mining_drill", 4)
	test.statistics.veins_assayed += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "second_vein")
	test.statistics.veins_assayed += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "deep_permit")
	research_test_technology(test, "logistics")
	research_test_technology(test, "logistics_science")
	research_test_technology(test, "electrolysis")
	test.statistics.core_samples_taken += 1
	set_placed(test, "bore_drill", 1)
	test.statistics.bore_drill_units += 199
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "deep_permit")
	test.statistics.bore_drill_units += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "aluminium")
}

complete_aluminium_to_hydro :: proc(t: ^testing.T, test: ^Quest_Test) {
	aluminium, silicon := test_item(test.items, "aluminium_plate"), test_item(test.items, "silicon")
	test.statistics.produced[aluminium] += 50
	test.statistics.produced[silicon] += 19
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "aluminium")
	test.statistics.produced[silicon] += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "two_floors")
	set_placed(test, "belt_lift", 10)
	test.statistics.blocks_placed[test_item(test.items, "concrete")] = 19
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "two_floors")
	test.statistics.blocks_placed[test_item(test.items, "concrete")] = 20
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "hydro")
}

complete_hydro_to_sixty :: proc(t: ^testing.T, test: ^Quest_Test) {
	research_test_technology(test, "hydro_power")
	set_placed(test, "hydro_turbine", 1)
	test.statistics.turbine_joules += 9_999_999
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "hydro")
	test.statistics.turbine_joules += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "grid")
	research_test_technology(test, "electric_grid")
	set_placed(test, "substation", 1)
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "schematic")
	test.statistics.schematics_found += 1
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "sixty")
}

complete_sixty :: proc(t: ^testing.T, test: ^Quest_Test) {
	progress := &test.state.progress[test.state.active]
	record_produced(&test.statistics, test_item(test.items, "iron_plate"), 59)
	progress.sustained_ticks[0] = 100
	run_quest_tick(test)
	testing.expect_value(t, progress.sustained_ticks[0], 0)
	record_produced(&test.statistics, test_item(test.items, "iron_plate"), 1)
	progress.sustained_ticks[0] = 30 * TEST_TICK_RATE - 2
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "sixty")
	run_quest_tick(test)
	testing.expect_value(t, active_quest_id(test), "launch_pad_permit")
}

// Every quest of the chapter in order on synthetic counters, ending with
// the delivery, the rocket program researched and the pay in the capsule.
// Counters and production from before a quest do not count.
@(test)
test_chapter_07_completes_in_order :: proc(t: ^testing.T) {
	test := make_chapter_07_test()
	defer destroy_quest_test(&test)
	test.statistics.bore_drill_units = 1000
	test.statistics.turbine_joules = 50_000_000
	test.statistics.produced[test_item(test.items, "aluminium_plate")] = 400
	testing.expect_value(t, active_quest_id(&test), "second_vein")
	complete_second_vein_to_aluminium(t, &test)
	complete_aluminium_to_hydro(t, &test)
	complete_hydro_to_sixty(t, &test)
	complete_sixty(t, &test)
	aluminium, silicon := test_item(test.items, "aluminium_plate"), test_item(test.items, "silicon")
	slots := capsule_slots(&test)
	slots[0], slots[1], slots[2] = {aluminium, 50}, {aluminium, 50}, {silicon, 49}
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "launch_pad_permit")
	rocket_program := test_technology(make_test_quest_references().technologies, "rocket_program")
	testing.expect(t, !test.unlocks.researched[rocket_program])
	slots[2] = {silicon, 50}
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect(t, chapter_done(test.state, test.registry.chapters[0]))
	testing.expect(t, has_message(&test, "mc_launch_pad_permit_done"))
	testing.expect(t, test.unlocks.researched[rocket_program])
	testing.expect_value(t, slots_item_count(slots, aluminium), 0)
	testing.expect_value(t, slots_item_count(slots, silicon), 0)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "steel")), 200)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "plastic_bar")), 100)
}

// The three hints count from activation and fire once.
@(test)
test_chapter_07_hints_fire_once :: proc(t: ^testing.T) {
	test := make_chapter_07_test()
	defer destroy_quest_test(&test)
	test.statistics.bore_drill_no_vein_attempts = 10
	test.statistics.turbine_still_water_ticks = 4
	test.statistics.seismic_shots = 6
	research_test_technology(&test, "prospecting")
	set_placed(&test, "electric_mining_drill", 4)
	test.statistics.veins_assayed += 2
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "deep_permit")
	test.statistics.bore_drill_no_vein_attempts += 2
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_bore_drill_no_vein"), 0)
	test.statistics.bore_drill_no_vein_attempts += 1
	run_quest_tick(&test)
	test.statistics.bore_drill_no_vein_attempts += 3
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_bore_drill_no_vein"), 1)
	complete_deep_permit(&test)
	complete_aluminium_to_hydro(t, &test)
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_turbine_still_water"), 0)
	test.statistics.turbine_still_water_ticks += 1
	run_quest_tick(&test)
	test.statistics.turbine_still_water_ticks += 1
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_turbine_still_water"), 1)
	research_test_technology(&test, "hydro_power")
	set_placed(&test, "hydro_turbine", 1)
	test.statistics.turbine_joules += 10_000_000
	research_test_technology(&test, "electric_grid")
	set_placed(&test, "substation", 1)
	run_quest_tick(&test)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "schematic")
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_seismic"), 0)
	test.statistics.seismic_shots += 1
	run_quest_tick(&test)
	test.statistics.seismic_shots += 1
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_seismic"), 1)
	testing.expect_value(t, test.state.hints_fired, 3)
}

complete_deep_permit :: proc(test: ^Quest_Test) {
	research_test_technology(test, "logistics")
	research_test_technology(test, "logistics_science")
	research_test_technology(test, "electrolysis")
	test.statistics.core_samples_taken += 1
	set_placed(test, "bore_drill", 1)
	test.statistics.bore_drill_units += 200
	run_quest_tick(test)
}
