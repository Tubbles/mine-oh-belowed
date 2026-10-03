package game

import "core:testing"

// Machines on bare ground (work item 0201): the placement on flat ground
// and its refusal on a slope, the founded flag, the wear through the
// entity tick, the breakdown, the salvage and the save.

WEAR_TEST_LIFE_MINUTES :: 1
WEAR_TEST_LIFE_TICKS :: WEAR_TEST_LIFE_MINUTES * 60 * 60

// The pick up test's site on the terrain, with the recipes and the bare
// ground values of data/game.sjson but a life of one minute.
make_wear_test :: proc(terrain := Test_Terrain{kind = .Flat}) -> (simulation: Simulation_State, content: Simulation_Content, items: Item_Registry) {
	items = make_test_items()
	content = test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.recipes, content.technologies = make_test_recipes(items)
	content.field.pad_foundation = find_foundation_machine(content.machines)
	content.field.foundation_pitch_millimetres = 500
	shipped := test_field_game_config()
	content.field.bare_ground = make_bare_ground_tuning(shipped)
	content.field.bare_ground.life_minutes = WEAR_TEST_LIFE_MINUTES
	simulation = make_test_field_state(make_test_field(terrain, 1000), 1000)
	return
}

// The machine queued on the bare ground at the site's origin by a far
// player holding one, drained; the player's refusal and the entity.
place_test_machine_on_bare_ground :: proc(simulation: ^Simulation_State, content: Simulation_Content, items: Item_Registry, id: string, x: i64 = 0) -> (refusal: Field_Edit_Refusal, handle: Entity_Handle) {
	add_test_miner(simulation, items, FAR_FEET, {id, 1})
	player := len(simulation.players) - 1
	machine := test_machine(content.machines, id)
	placement := Field_Placement{machine = machine, new_frame = true, hit = test_site_point(x, 0, 0), heading = {UNIT_VECTOR_ONE, 0, 0}}
	frames_before := len(simulation.world.entities.frames.frames)
	append(&simulation.field.placements, Queued_Field_Placement{player = player, placement = placement})
	drain_field_placements(simulation, content)
	refusal = simulation.players[player].field_refusal
	if len(simulation.world.entities.frames.frames) > frames_before {
		frame := simulation.world.entities.frames.frames[frames_before]
		handle = entity_at(&simulation.world.entities, {}, frame.id)
	}
	return
}

// Fuel and ore for the ticks.
load_test_furnace :: proc(furnace: ^Furnace, items: Item_Registry, coal, ore: u16) {
	furnace.slots[FURNACE_FUEL_SLOT] = Item_Stack{test_item(items, "coal"), coal}
	if ore > 0 {
		furnace.slots[FURNACE_INPUT_SLOT] = Item_Stack{test_item(items, "hematite"), ore}
	}
}

run_test_entities :: proc(simulation: ^Simulation_State, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		simulation.tick += 1
		tick_entities_on_world(&simulation.world, &simulation.records, content, simulation.tick_rate)
		log_machine_breakdowns(simulation, content)
	}
}

// A stone furnace on flat bare ground stands on a new frame of its own
// with no foundation, unfounded, and smelts; on a ten degree slope (176 mm
// across its metre) it stands too, on a thirty degree one (577 mm) it is
// refused Too_Steep and nothing is placed or paid.
@(test)
test_a_furnace_stands_on_flat_bare_ground_and_is_refused_on_a_slope :: proc(t: ^testing.T) {
	{
		simulation, content, items := make_wear_test()
		defer destroy_simulation(&simulation)
		refusal, handle := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace")
		testing.expect_value(t, refusal, Field_Edit_Refusal.None)
		furnace := pool_get(&simulation.world.entities.furnaces, handle)
		testing.expect(t, furnace != nil, "the furnace stands at cell (0, 0, 0) of its frame")
		if furnace == nil {
			return
		}
		testing.expect(t, !furnace.founded)
		testing.expect_value(t, len(simulation.world.entities.foundations.entries), 0)
		testing.expect_value(t, inventory_count(simulation.players[0].inventory, test_item(items, "stone_furnace")), 0)
		load_test_furnace(furnace, items, 2, 3)
		run_test_entities(&simulation, content, 200)
		furnace = pool_get(&simulation.world.entities.furnaces, handle)
		testing.expect_value(t, furnace.slots[FURNACE_OUTPUT_SLOT].count, 1)
		testing.expect_value(t, furnace.wear_ticks, 200)
	}
	for entry in ([?]struct {
			degrees: int,
			refusal: Field_Edit_Refusal,
		}{{10, .None}, {30, .Too_Steep}}) {
		simulation, content, items := make_wear_test(Test_Terrain{kind = .Slope, slope_degrees = entry.degrees})
		defer destroy_simulation(&simulation)
		refusal, handle := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace")
		testing.expectf(t, refusal == entry.refusal, "%d degrees: %v", entry.degrees, refusal)
		testing.expect_value(t, handle != NO_ENTITY, entry.refusal == .None)
		held := inventory_count(simulation.players[0].inventory, test_item(items, "stone_furnace"))
		testing.expect_value(t, held, entry.refusal == .None ? 0 : 1)
	}
}

// A small pole stands on the thirty degree slope (stands_on_ground), and
// a belt pole, a pipe and the stone cutting table (0196) never count wear
// however they are ticked.
@(test)
test_poles_and_pipes_stand_on_any_slope_and_never_wear :: proc(t: ^testing.T) {
	simulation, content, items := make_wear_test(Test_Terrain{kind = .Slope, slope_degrees = 30})
	defer destroy_simulation(&simulation)
	refusal, handle := place_test_machine_on_bare_ground(&simulation, content, items, "small_pole")
	testing.expect_value(t, refusal, Field_Edit_Refusal.None)
	testing.expect(t, handle != NO_ENTITY)
	for id in ([?]string{"belt_pole", "pipe", "small_pole", "stone_cutting_table"}) {
		machine := content.machines.machines[test_machine(content.machines, id)]
		testing.expectf(t, machine.stands_on_ground, "%s stands on the ground", id)
		common := Entity_Common{machine = test_machine(content.machines, id), frame = Frame_Id(1)}
		for _ in 0 ..< 10 {
			record_operation(&simulation.world.entities, &common, machine, content.field.bare_ground, simulation.tick_rate)
		}
		testing.expect_value(t, common.wear_ticks, 0)
		testing.expect(t, !common.broken)
	}
	testing.expect_value(t, len(simulation.world.entities.breakdowns), 0)
}

// On bare ground a furnace with fuel and no ore counts nothing; with ore
// it breaks down at its minute of operation, not a tick before: it stops
// smelting, its marker is red, and the toast names it once. On a pad of
// foundations a furnace runs past the same minute and never wears.
@(test)
test_a_furnace_on_bare_ground_breaks_after_its_operation_and_one_on_foundations_never :: proc(t: ^testing.T) {
	simulation, content, items := make_wear_test()
	defer destroy_simulation(&simulation)
	_, handle := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace")
	entities := &simulation.world.entities
	pad := lay_test_pad(entities, content.machines, metres_to_position_units(20), 0, {0, 0, 0}, {1, 0, 1})
	founded, pad_refusal := place_on_frame(entities, content.machines, test_machine(content.machines, "stone_furnace"), pad.id, {0, 1, 0}, 0)
	testing.expect_value(t, pad_refusal, Frame_Placement_Refusal.None)
	testing.expect(t, pool_get(&entities.furnaces, founded).founded)
	load_test_furnace(pool_get(&entities.furnaces, handle), items, 10, 0)
	load_test_furnace(pool_get(&entities.furnaces, founded), items, 10, 40)
	run_test_entities(&simulation, content, WEAR_TEST_LIFE_TICKS + 10)
	idle := pool_get(&entities.furnaces, handle)
	testing.expect_value(t, idle.state, Furnace_State.Idle)
	testing.expect_value(t, idle.wear_ticks, 0)
	testing.expect(t, !idle.broken)
	on_pad := pool_get(&entities.furnaces, founded)
	testing.expect(t, on_pad.slots[FURNACE_OUTPUT_SLOT].count >= 18, "the founded furnace smelts past the minute")
	testing.expect_value(t, on_pad.wear_ticks, 0)
	testing.expect(t, !on_pad.broken)

	load_test_furnace(idle, items, 10, 40)
	run_test_entities(&simulation, content, WEAR_TEST_LIFE_TICKS - 1)
	worn := pool_get(&entities.furnaces, handle)
	testing.expect(t, !worn.broken)
	testing.expect_value(t, len(simulation.quests.notices), 0)
	run_test_entities(&simulation, content, 1)
	worn = pool_get(&entities.furnaces, handle)
	testing.expect(t, worn.broken)
	testing.expect_value(t, worn.wear_ticks, u32(WEAR_TEST_LIFE_TICKS))
	testing.expect_value(t, entity_marker_colour(worn.common, machine_marker_colour(worn.state, furnace_has_fuel(worn^))), Marker_Colour.Red)
	output, progress := worn.slots[FURNACE_OUTPUT_SLOT], worn.progress_ticks
	run_test_entities(&simulation, content, 600)
	worn = pool_get(&entities.furnaces, handle)
	testing.expect_value(t, worn.slots[FURNACE_OUTPUT_SLOT], output)
	testing.expect_value(t, worn.progress_ticks, progress)
	testing.expect_value(t, len(simulation.quests.notices), 1)
	if len(simulation.quests.notices) == 1 {
		notice := simulation.quests.notices[0]
		testing.expect_value(t, notice.text_key, MACHINE_BROKE_DOWN_KEY)
		testing.expect_value(t, notice.argument_key, "machine_stone_furnace")
	}
}

// A worn furnace torn down returns four of the recipe's five stone (80
// percent, rounded down) and its contents, not itself; an unworn one on
// foundations returns itself. Placed again it starts at zero.
@(test)
test_tearing_a_worn_furnace_down_returns_its_salvage_and_contents :: proc(t: ^testing.T) {
	simulation, content, items := make_wear_test()
	defer destroy_simulation(&simulation)
	_, handle := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace")
	entities := &simulation.world.entities
	furnace := pool_get(&entities.furnaces, handle)
	load_test_furnace(furnace, items, 3, 7)
	run_test_entities(&simulation, content, 10)
	furnace = pool_get(&entities.furnaces, handle)
	testing.expect_value(t, furnace.wear_ticks, 10)
	frame := furnace.frame
	stone, coal, ore := test_item(items, "stone"), test_item(items, "coal"), test_item(items, "hematite")
	player := &simulation.players[0]
	stone_before := inventory_count(player.inventory, stone)
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = Field_Placement{kind = .Pick_Up, frame = frame, cell = {}}})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, pool_get(&entities.furnaces, handle) == nil, "the furnace is torn down")
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "stone_furnace")), 0)
	testing.expect_value(t, inventory_count(player.inventory, stone) - stone_before, 4)
	testing.expect_value(t, inventory_count(player.inventory, coal), 2)
	testing.expect_value(t, inventory_count(player.inventory, ore), 7)
	testing.expect_value(t, len(entities.frames.frames), 0)

	pad := lay_test_pad(entities, content.machines, metres_to_position_units(20), 0, {0, 0, 0}, {1, 0, 1})
	founded, _ := place_on_frame(entities, content.machines, test_machine(content.machines, "stone_furnace"), pad.id, {0, 1, 0}, 0)
	load_test_furnace(pool_get(&entities.furnaces, founded), items, 3, 7)
	run_test_entities(&simulation, content, 10)
	testing.expect_value(t, slice_of_stacks(entity_pickup_stacks(&simulation.world, content, founded)), Item_Stack{test_item(items, "stone_furnace"), 1})

	_, again := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace")
	testing.expect_value(t, pool_get(&entities.furnaces, again).wear_ticks, 0)
}

// The last of the stacks, the machine's own return.
slice_of_stacks :: proc(stacks: []Item_Stack) -> Item_Stack {
	return len(stacks) > 0 ? stacks[len(stacks) - 1] : EMPTY_STACK
}

// The salvage's arithmetic: rounded down per item made, never negative.
@(test)
test_salvage_rounds_down_per_item_made :: proc(t: ^testing.T) {
	testing.expect_value(t, salvaged_count(5, 1, 80), 4)
	testing.expect_value(t, salvaged_count(1, 1, 80), 0)
	testing.expect_value(t, salvaged_count(10, 2, 80), 4)
	testing.expect_value(t, salvaged_count(3, 1, 100), 3)
}

// The founded flag follows the cells under the bottom row: a furnace with
// one bottom cell on a chest is unfounded, and becomes founded once the
// chest gives way to a foundation.
@(test)
test_the_founded_flag_follows_the_foundations_under_a_machine :: proc(t: ^testing.T) {
	simulation, content, _ := make_wear_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	pad := lay_test_pad(entities, content.machines, 0, 0, {0, 0, 0}, {1, 0, 1})
	for cell in ([?]World_Coordinate{{0, 1, 0}, {1, 1, 0}, {0, 1, 1}}) {
		place_on_frame(entities, content.machines, content.field.pad_foundation, pad.id, cell, 0)
	}
	chest, chest_refusal := place_on_frame(entities, content.machines, test_machine(content.machines, "wooden_chest"), pad.id, {1, 1, 1}, 0)
	testing.expect_value(t, chest_refusal, Frame_Placement_Refusal.None)
	furnace, refusal := place_on_frame(entities, content.machines, test_machine(content.machines, "stone_furnace"), pad.id, {0, 2, 0}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	testing.expect(t, !pool_get(&entities.furnaces, furnace).founded)
	remove_entity(entities, content.machines, chest)
	place_on_frame(entities, content.machines, content.field.pad_foundation, pad.id, {1, 1, 1}, 0)
	testing.expect(t, pool_get(&entities.furnaces, furnace).founded)
	remove_entity(entities, content.machines, entity_at(entities, {1, 1, 1}, pad.id))
	testing.expect(t, !pool_get(&entities.furnaces, furnace).founded)
}

// Two simulations running a furnace on bare ground to its breakdown hash
// the same, and the wear is in the hash.
@(test)
test_two_sessions_breaking_a_furnace_down_hash_the_same :: proc(t: ^testing.T) {
	hashes: [2]u64
	for index in 0 ..< 2 {
		simulation, content, items := make_wear_test()
		defer destroy_simulation(&simulation)
		_, handle := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace")
		load_test_furnace(pool_get(&simulation.world.entities.furnaces, handle), items, 10, 40)
		run_test_entities(&simulation, content, WEAR_TEST_LIFE_TICKS + 5)
		testing.expect(t, pool_get(&simulation.world.entities.furnaces, handle).broken)
		hashes[index] = simulation_state_hash(&simulation)
		pool_get(&simulation.world.entities.furnaces, handle).wear_ticks -= 1
		testing.expect(t, simulation_state_hash(&simulation) != hashes[index], "the wear is hashed")
	}
	testing.expect_value(t, hashes[0], hashes[1])
}

// A field world's save carries a furnace's wear and breakdown; the same
// save cut before the wear table (one written before 0201) loads with the
// furnace unworn and its founded flag derived again.
@(test)
test_the_wear_round_trips_a_save_and_an_older_save_loads_unworn :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	feet := state.players[0].field.position
	frame := add_frame(&state.world.entities.frames, feet + {0, 0, 5 * POSITION_UNITS_PER_METRE}, frame_axes({0, UNIT_VECTOR_ONE, 0}, 0), 500)
	handle := add_entity(&state.world.entities, simulation_content.machines, test_machine(simulation_content.machines, "stone_furnace"), {}, 0, frame)
	furnace := pool_get(&state.world.entities.furnaces, handle)
	testing.expect(t, !furnace.founded)
	furnace.wear_ticks, furnace.broken = 4321, true
	hash := simulation_state_hash(state)
	files := encode_save_files(state, simulation_content, "wear", 0)
	table := make([dynamic]byte, context.temp_allocator)
	write_machine_wear_table(&table, &state.world.entities)
	// The felled trees' table (0197) follows the wear's; an older save
	// ends before both.
	write_felled_tree_table(&table, &state.field)
	end_session(session)

	for older in ([2]bool{false, true}) {
		cut := files
		if older {
			cut.entities = files.entities[:len(files.entities) - len(table)]
		}
		loaded := load_test_field_save(config, content, &cut)
		defer end_session(loaded)
		restored := &loaded.simulation
		stage_generated_field_set(restored)
		testing.expect(t, restore_arrived_field_set(&restored.field), "the staged set restores")
		loaded_furnace := pool_get(&restored.world.entities.furnaces, handle)
		testing.expect(t, loaded_furnace != nil, "the furnace loads")
		if loaded_furnace == nil {
			continue
		}
		testing.expect(t, !loaded_furnace.founded)
		if older {
			testing.expect_value(t, loaded_furnace.wear_ticks, 0)
			testing.expect(t, !loaded_furnace.broken)
		} else {
			testing.expect_value(t, loaded_furnace.wear_ticks, 4321)
			testing.expect(t, loaded_furnace.broken)
			testing.expect_value(t, simulation_state_hash(restored), hash)
		}
	}
}

// A new frame never stands inside another's entities: a furnace on bare
// ground half a metre from another is refused Frame_Cell_Taken, one two
// metres away stands, and a free foundation on the first furnace's spot
// is refused the same way.
@(test)
test_a_new_frame_is_refused_inside_another_frames_entities :: proc(t: ^testing.T) {
	simulation, content, items := make_wear_test()
	defer destroy_simulation(&simulation)
	_, first := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace")
	testing.expect(t, first != NO_ENTITY)
	half := i64(POSITION_UNITS_PER_METRE / 2)
	refusal, overlapping := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace", half)
	testing.expect_value(t, refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	testing.expect_value(t, overlapping, NO_ENTITY)
	apart_refusal, apart := place_test_machine_on_bare_ground(&simulation, content, items, "stone_furnace", i64(2 * POSITION_UNITS_PER_METRE))
	testing.expect_value(t, apart_refusal, Field_Edit_Refusal.None)
	testing.expect(t, apart != NO_ENTITY)
	add_test_miner(&simulation, items, FAR_FEET, {"wooden_foundation", 1})
	player := len(simulation.players) - 1
	free := Field_Placement{machine = content.field.pad_foundation, new_frame = true, hit = test_site_point(0, 0, 0), heading = {UNIT_VECTOR_ONE, 0, 0}}
	frames_before := len(simulation.world.entities.frames.frames)
	append(&simulation.field.placements, Queued_Field_Placement{player = player, placement = free})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[player].field_refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	testing.expect_value(t, len(simulation.world.entities.frames.frames), frames_before)
}

// The block world's test content with a life of one minute on bare
// ground, for machines marked unfounded by hand.
make_block_wear_test :: proc() -> (content: Simulation_Content, world: World) {
	content = make_test_content()
	content.field.bare_ground = Bare_Ground_Tuning{flatness_millimetres = 250, life_minutes = WEAR_TEST_LIFE_MINUTES, salvage_percent = 80}
	world = make_floor_world(content.blocks, 32)
	return
}

// A steam engine powering a lamp, unfounded, counts one tick of
// operation per tick it delivers energy and breaks on exactly the tick of
// its minute, not at half of it.
@(test)
test_a_steam_engine_breaks_on_the_tick_of_its_minutes :: proc(t: ^testing.T) {
	content, world := make_block_wear_test()
	records: Game_Records
	_, engine := add_test_power_plant(&world, content, {0, 1, 0}, {-3, 1, -2})
	place_test_entity(&world, content, "lamp", {2, 1, 2})
	test_fluid_machine(&world, engine).founded = false
	tick_test_entities(&world, &records, content, WEAR_TEST_LIFE_TICKS - 1)
	testing.expect_value(t, test_fluid_machine(&world, engine).wear_ticks, u32(WEAR_TEST_LIFE_TICKS - 1))
	testing.expect(t, !test_fluid_machine(&world, engine).broken)
	tick_test_entities(&world, &records, content, 1)
	testing.expect(t, test_fluid_machine(&world, engine).broken)
	testing.expect_value(t, len(world.entities.breakdowns), 1)
}

// A burner inserter between two chests, unfounded: idle with nothing to
// pick it counts nothing; moving plates it breaks after its minute of
// moving and then moves nothing more.
@(test)
test_an_inserter_breaks_after_its_minutes_of_moving_and_not_while_idle :: proc(t: ^testing.T) {
	content, world := make_block_wear_test()
	records: Game_Records
	pair := make_chest_pair(&world, content)
	test_inserter(&world, pair.inserter).founded = false
	tick_test_entities(&world, &records, content, WEAR_TEST_LIFE_TICKS + 10)
	testing.expect_value(t, test_inserter(&world, pair.inserter).wear_ticks, 0)
	plate := test_item(content.items, "iron_plate")
	entity_insert(&world.entities, content, pair.source, Item_Stack{plate, 100})
	tick_test_entities(&world, &records, content, WEAR_TEST_LIFE_TICKS + 400)
	inserter := test_inserter(&world, pair.inserter)
	testing.expect(t, inserter.broken)
	testing.expect_value(t, inserter.wear_ticks, u32(WEAR_TEST_LIFE_TICKS))
	moved := chest_count_of(&world, pair.target, plate)
	testing.expect(t, moved > 0 && moved < 100, "some plates moved before the breakdown")
	tick_test_entities(&world, &records, content, 500)
	testing.expect_value(t, chest_count_of(&world, pair.target, plate), moved)
}

// Work item 0196: a worn stone cutter returns 80 percent of its recipe's
// inputs rounded down: 2 iron gears and 4 stone bricks, no furnace.
@(test)
test_a_worn_stone_cutter_returns_its_inputs_share :: proc(t: ^testing.T) {
	simulation, content, items := make_wear_test()
	defer destroy_simulation(&simulation)
	common := Entity_Common{machine = test_machine(content.machines, "stone_cutter"), wear_ticks = 1}
	returned := machine_return_stacks(content, common)
	testing.expect_value(t, len(returned), 2)
	testing.expect_value(t, returned[0], Item_Stack{test_item(items, "iron_gear"), 2})
	testing.expect_value(t, returned[1], Item_Stack{test_item(items, "stone_brick"), 4})
}
