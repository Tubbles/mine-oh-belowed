package game

import "core:testing"

// Work item 0028: the statistics list, the machine counts of the detail
// row, the overlay marker colours and the consumed and output rate hooks
// in a running line.

@(test)
test_statistics_rows_sort_by_produced :: proc(t: ^testing.T) {
	statistics := make_test_statistics(5)
	record_produced(&statistics, Item_Id(1), 5)
	record_produced(&statistics, Item_Id(2), 9)
	record_consumed(&statistics, Item_Id(3), 4)
	record_produced(&statistics, Item_Id(4), 5)
	record_consumed(&statistics, Item_Id(4), 1)
	rows := statistics_rows(statistics, .One_Minute, context.temp_allocator)
	// Item 0 never moved and is left out; the tie between 1 and 4 goes to
	// the one that was also consumed.
	expected := [?]Item_Rate_Row{{Item_Id(2), 9, 0}, {Item_Id(4), 5, 1}, {Item_Id(1), 5, 0}, {Item_Id(3), 0, 4}}
	testing.expect_value(t, len(rows), len(expected))
	for row, index in rows {
		testing.expect_value(t, row, expected[index])
	}
	// A line that stopped long ago keeps its row, at zero.
	advance_statistics_clock(&statistics, 100_000, 1)
	later := statistics_rows(statistics, .Sixty_Minutes, context.temp_allocator)
	testing.expect_value(t, len(later), 4)
	testing.expect_value(t, later[0], Item_Rate_Row{Item_Id(1), 0, 0})
}

@(test)
test_statistics_letter_jump_follows_list_order :: proc(t: ^testing.T) {
	names := []string{"Coal", "Iron plate", "Copper plate", "iron gear"}
	rows := []Item_Rate_Row{{item = Item_Id(2)}, {item = Item_Id(3)}, {item = Item_Id(1)}, {item = Item_Id(0)}}
	testing.expect_value(t, row_position_for_letter(names, rows, 'i'), 1)
	testing.expect_value(t, row_position_for_letter(names, rows, 'C'), 0)
	testing.expect_value(t, row_position_for_letter(names, rows, 'z'), -1)
}

@(test)
test_count_item_machines :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	items, recipes := content.items, content.recipes
	hematite, plate, gear, coal := test_item(items, "hematite"), test_item(items, "iron_plate"), test_item(items, "iron_gear"), test_item(items, "coal")
	pack := test_item(items, "science_pack_1")
	smelting := place_test_entity(&world, content, "stone_furnace", {10, 1, 10})
	furnace := pool_get(&world.entities.furnaces, smelting)
	furnace.recipe = furnace_recipe_for(recipes, hematite)
	furnace.slots[FURNACE_FUEL_SLOT] = {coal, 3}
	place_test_entity(&world, content, "stone_furnace", {10, 1, 12})
	assembler := place_test_entity(&world, content, "assembler_1", {14, 1, 10})
	set_assembler_recipe(test_assembler(&world, assembler), recipes, test_recipe(recipes, "iron_gear"))
	vein := add_test_vein(&world, content, "iron", {-19, 21}, 1, IRON_TEST_VEIN, 1000)
	place_test_drill(&world, content, {-20, 1, 20}, 0, vein)
	place_test_entity(&world, content, "lab", {4, 1, -10})
	simulation_content := content
	counts := count_item_machines(&world, simulation_content, hematite)
	testing.expect_value(t, counts, Item_Machine_Counts{producers = 1, consumers = 1})
	testing.expect_value(t, count_item_machines(&world, simulation_content, test_item(items, "hematite_low_grade")).producers, 1)
	testing.expect_value(t, count_item_machines(&world, simulation_content, plate), Item_Machine_Counts{producers = 1, consumers = 1})
	testing.expect_value(t, count_item_machines(&world, simulation_content, gear), Item_Machine_Counts{producers = 1, consumers = 0})
	// The furnace and the drill burn coal.
	testing.expect_value(t, count_item_machines(&world, simulation_content, coal), Item_Machine_Counts{producers = 0, consumers = 2})
	// Labs use packs only while research is queued.
	testing.expect_value(t, count_item_machines(&world, simulation_content, pack).consumers, 0)
	world.research = Research_State{queued = true, technology = test_technology(content.technologies, "automation")}
	testing.expect_value(t, count_item_machines(&world, simulation_content, pack).consumers, 1)
}

@(test)
test_marker_colour_of_every_state :: proc(t: ^testing.T) {
	Case :: struct($State: typeid) {
		state:  State,
		flag:   bool,
		colour: Marker_Colour,
	}
	furnace_cases := [?]Case(Furnace_State) {
		{.Burning, true, .Green},
		{.Output_Full, true, .Yellow},
		{.No_Fuel, false, .Red},
		{.Idle, true, .Red},
		{.Idle, false, .Grey},
	}
	for entry in furnace_cases {
		testing.expectf(t, machine_marker_colour(entry.state, entry.flag) == entry.colour, "furnace %v %v", entry.state, entry.flag)
	}
	crafting_cases := [?]Case(Assembler_State) {
		{.Working, true, .Green},
		{.Output_Full, true, .Yellow},
		{.No_Recipe, true, .Red},
		{.Missing_Ingredients, true, .Red},
		{.No_Fuel, false, .Red},
		{.No_Fluid, true, .Red},
		{.No_Power, true, .Red},
		{.No_Power, false, .Grey},
	}
	for entry in crafting_cases {
		testing.expectf(t, machine_marker_colour(entry.state, entry.flag) == entry.colour, "crafting %v %v", entry.state, entry.flag)
	}
	drill_cases := [?]Case(Drill_State) {
		{.Mining, false, .Green},
		{.Waiting_For_Room, false, .Yellow},
		{.No_Fuel, false, .Red},
		{.Vein_Exhausted, false, .Red},
		{.Unpowered, true, .Red},
		{.Unpowered, false, .Grey},
	}
	for entry in drill_cases {
		testing.expectf(t, machine_marker_colour(entry.state, entry.flag) == entry.colour, "drill %v %v", entry.state, entry.flag)
	}
	lab_cases := [?]Case(Lab_State) {
		{.Researching, true, .Green},
		{.No_Packs, true, .Red},
		{.No_Research, true, .Grey},
		{.No_Power, true, .Red},
		{.No_Power, false, .Grey},
	}
	for entry in lab_cases {
		testing.expectf(t, machine_marker_colour(entry.state, entry.flag) == entry.colour, "lab %v %v", entry.state, entry.flag)
	}
	fluid_cases := [?]Case(Fluid_Machine_State) {
		{.Producing, false, .Green},
		{.Pumping, true, .Green},
		{.Output_Full, false, .Yellow},
		{.No_Water, false, .Red},
		{.No_Fuel, false, .Red},
		{.No_Steam, false, .Red},
		{.Unpowered, true, .Red},
		{.Unpowered, false, .Grey},
		{.Idle, false, .Grey},
	}
	for entry in fluid_cases {
		testing.expectf(t, machine_marker_colour(entry.state, entry.flag) == entry.colour, "fluid machine %v %v", entry.state, entry.flag)
	}
	testing.expect(t, !fluid_machine_has_marker(.Storage_Tank))
	testing.expect(t, fluid_machine_has_marker(.Boiler))
}

@(test)
test_marker_size_grows_with_distance :: proc(t: ^testing.T) {
	testing.expect_value(t, marker_size(2), MARKER_MINIMUM_SIZE)
	testing.expect_value(t, marker_size(100), 100 * MARKER_SIZE_PER_DISTANCE)
	common := Entity_Common{origin = {0, 1, 0}, size = {2, 2, 2}}
	testing.expect_value(t, marker_position(common, 0.5), [3]f32{1, 3 + MARKER_GAP + 0.25, 1})
}

// The gear line of the assembler tests: the plates the assembler took,
// the coal the burner inserters lit, and the assembler's own output rate.
@(test)
test_running_line_counts_consumption_and_output_rate :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	world.statistics = make_statistics(len(content.items.items), len(content.machines.machines), len(content.blocks.definitions), context.temp_allocator)
	_, handle, _ := lay_gear_line_at(&world, content, {})
	tick_test_entities(&world, content, 1200)
	gear, plate := test_item(content.items, "iron_gear"), test_item(content.items, "iron_plate")
	// Six crafts started (the sixth at tick 1151), two plates each.
	testing.expect_value(t, item_counter(world.statistics.consumed, plate), 12)
	testing.expect(t, item_counter(world.statistics.consumed, test_item(content.items, "coal")) > 0)
	assembler := test_assembler(&world, handle)
	testing.expect_value(t, machine_output_per_minute(assembler.output_rate, world.statistics.current_second), item_counter(world.statistics.produced, gear))
}
