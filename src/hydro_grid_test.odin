package game

import "core:slice"
import "core:testing"

// Hydro turbines, big poles and substations, fast belts, fast and long
// inserters (work item 0037). Worlds stand on the stone floor of
// make_floor_world (top at y 1).

test_hydro_turbine_machine :: proc(content: Simulation_Content) -> Machine {
	return content.machines.machines[test_machine(content.machines, "hydro_turbine")]
}

// A water source on the floor at cell, settled: the water around it falls
// one level per block of walking distance.
add_settled_source :: proc(t: ^testing.T, world: ^World, content: Simulation_Content, cell: World_Coordinate) -> u64 {
	world_set_block(world, cell, test_block(content.blocks, "water"))
	return settle_world(t, world, content.blocks, 0)
}

hydro_placement_valid :: proc(world: ^World, content: Simulation_Content, origin: World_Coordinate) -> bool {
	return placement_at(world, content, nil, test_machine(content.machines, "hydro_turbine"), origin, 0).valid
}

// The supply of the only network after one electric tick.
network_supply_after_tick :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content) -> u64 {
	tick_electric_networks(world, records, content, TEST_TICK_RATE)
	return world.entities.electric_networks.networks[0].supply
}

set_water_level :: proc(world: ^World, content: Simulation_Content, cells: []World_Coordinate, level: int) {
	block := AIR_BLOCK
	if level > 0 {
		found: bool
		block, found = water_block_for_level(content.blocks, level)
		assert(found)
	}
	for cell in cells {
		world_set_block(world, cell, block)
	}
}

@(test)
test_hydro_turbine_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	turbine := test_hydro_turbine_machine(content)
	testing.expect_value(t, turbine.kind, Machine_Kind.Hydro_Turbine)
	testing.expect_value(t, turbine.footprint, [3]i32{2, 2, 2})
	testing.expect_value(t, turbine.electric_output_watts, 400_000)
	testing.expect_value(t, turbine.hydro_watts_per_water_level, 10_000)
	testing.expect_value(t, turbine.hydro_minimum_water_level, 3)
	testing.expect_value(t, turbine.fluid_port_count, 0)
	testing.expect(t, machine_is_generator(turbine))
	testing.expect_value(t, hydro_turbine_watts(turbine, 24), 240_000)
	testing.expect_value(t, hydro_turbine_watts(turbine, 56), 400_000)
}

// Valid where one footprint cell holds flowing water of level 3 or more;
// source water is still and counts nothing.
@(test)
test_hydro_turbine_placement_needs_flowing_water :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	add_settled_source(t, &world, content, {0, 1, 0})
	// Levels 7, 6, 6 and 5 next to the source.
	testing.expect(t, hydro_placement_valid(&world, content, {1, 1, 0}))
	// Levels 3, 2, 2 and 1 still have one cell at the minimum.
	testing.expect(t, hydro_placement_valid(&world, content, {5, 1, 0}))
	// Levels 2, 1, 1 and none do not.
	testing.expect(t, !hydro_placement_valid(&world, content, {6, 1, 0}))
	// Dry ground.
	testing.expect(t, !hydro_placement_valid(&world, content, {20, 1, 20}))
	// A pool of four sources and nothing else in the footprint.
	pool := []World_Coordinate{{-20, 1, -20}, {-19, 1, -20}, {-20, 1, -19}, {-19, 1, -19}}
	set_blocks(&world, test_block(content.blocks, "water"), ..pool)
	settle_world(t, &world, content.blocks, 10_000)
	testing.expect_value(t, flowing_water_level_sum(&world, content.blocks, pool), 0)
	testing.expect(t, !hydro_placement_valid(&world, content, {-20, 1, -20}))
	// Another entity in the footprint.
	place_test_entity(&world, content, "wooden_chest", {2, 1, 1})
	testing.expect(t, !hydro_placement_valid(&world, content, {1, 1, 0}))
}

// The offer follows the water in the footprint every tick, up to 400 kW,
// with no fuel.
@(test)
test_hydro_turbine_output_follows_the_water_level :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	add_settled_source(t, &world, content, {0, 1, 0})
	turbine := place_test_entity(&world, content, "hydro_turbine", {1, 1, 0})
	place_test_entity(&world, content, "small_pole", {1, 1, 3})
	place_test_entity(&world, content, "lamp", {2, 1, 3})
	// 7 + 6 + 6 + 5 = 24 levels, 240 kW, 4000 J a tick.
	testing.expect_value(t, network_supply_after_tick(&world, &records, content), 4000)
	testing.expect_value(t, test_fluid_machine(&world, turbine).state, Fluid_Machine_State.Generating)
	testing.expect_value(t, test_fluid_machine(&world, turbine).generated_joules, 83)
	// Draining one cell takes its 7 levels away at once.
	world_set_block(&world, {1, 1, 0}, AIR_BLOCK)
	testing.expect_value(t, network_supply_after_tick(&world, &records, content), 2833)
	// Deep water in all eight cells is 56 levels, capped at 400 kW.
	cells := common_cells(test_fluid_machine(&world, turbine).common, content.machines)
	set_water_level(&world, content, cells, WATER_FALLING_LEVEL)
	testing.expect_value(t, network_supply_after_tick(&world, &records, content), 6666)
	// Dry: nothing to give while the lamp asks.
	set_water_level(&world, content, cells, 0)
	testing.expect_value(t, network_supply_after_tick(&world, &records, content), 0)
	testing.expect_value(t, test_fluid_machine(&world, turbine).state, Fluid_Machine_State.No_Water)
}

// Water flows into and on through a turbine's cells as if it were not
// there, while a chest in the same place stops it.
@(test)
test_water_flows_through_a_hydro_turbine :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	place_test_entity(&world, content, "hydro_turbine", {1, 1, 0})
	place_test_entity(&world, content, "wooden_chest", {-1, 1, 0})
	add_settled_source(t, &world, content, {0, 1, 0})
	testing.expect_value(t, world_water_level(&world, content.blocks, {1, 1, 0}), 7)
	testing.expect_value(t, world_water_level(&world, content.blocks, {2, 1, 1}), 5)
	testing.expect_value(t, world_water_level(&world, content.blocks, {4, 1, 0}), 4)
	testing.expect_value(t, world_water_level(&world, content.blocks, {-1, 1, 0}), 0)
	// Picking the turbine up leaves the water where it is.
	testing.expect(t, remove_entity(&world.entities, content.machines, entity_at(&world.entities, {1, 1, 0})))
	testing.expect_value(t, world_water_level(&world, content.blocks, {1, 1, 0}), 7)
}

@(test)
test_big_pole_and_substation_data :: proc(t: ^testing.T) {
	content := make_test_content()
	big := content.machines.machines[test_machine(content.machines, "big_pole")]
	testing.expect_value(t, big.kind, Machine_Kind.Pole)
	testing.expect_value(t, big.footprint, [3]i32{1, 6, 1})
	testing.expect_value(t, big.supply_volume, [3]i32{3, 6, 3})
	testing.expect_value(t, big.wire_reach, 24)
	substation := content.machines.machines[test_machine(content.machines, "substation")]
	testing.expect_value(t, substation.footprint, [3]i32{2, 3, 2})
	testing.expect_value(t, substation.supply_volume, [3]i32{18, 6, 18})
	testing.expect_value(t, substation.wire_reach, 18)
	// The volume must centre on the footprint.
	definition := Machine_Definition{id = "odd", footprint = {width = 2, depth = 2, height = 3}, supply_volume = {width = 17, depth = 18, height = 6}, wire_reach = 18}
	testing.expect(t, validate_power_machine_definition(definition, .Pole) != "")
	definition.supply_volume.width = 18
	testing.expect_value(t, validate_power_machine_definition(definition, .Pole), "")
	definition.footprint.depth = 1
	testing.expect(t, validate_power_machine_definition(definition, .Pole) != "")
}

@(test)
test_big_poles_and_substations_connect_by_reach :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	networks := &world.entities.electric_networks
	first := place_test_entity(&world, content, "big_pole", {-24, 1, 0})
	second := place_test_entity(&world, content, "big_pole", {0, 1, 0})
	third := place_test_entity(&world, content, "big_pole", {25, 1, 0})
	// 24 apart connects, 25 does not.
	testing.expect_value(t, entity_network(networks, first), entity_network(networks, second))
	testing.expect(t, entity_network(networks, third) != entity_network(networks, second))
	// With a small pole the shorter reach (7) counts.
	near_small := place_test_entity(&world, content, "small_pole", {7, 1, 0})
	far_small := place_test_entity(&world, content, "small_pole", {0, 1, 8})
	testing.expect_value(t, entity_network(networks, near_small), entity_network(networks, second))
	testing.expect(t, entity_network(networks, far_small) != entity_network(networks, second))
	// Substations 18 apart connect, 19 do not.
	world = make_floor_world(content.blocks, 32)
	networks = &world.entities.electric_networks
	near := place_test_entity(&world, content, "substation", {-9, 1, -20})
	middle := place_test_entity(&world, content, "substation", {9, 1, -20})
	far := place_test_entity(&world, content, "substation", {9, 1, -1})
	testing.expect_value(t, entity_network(networks, near), entity_network(networks, middle))
	testing.expect(t, entity_network(networks, far) != entity_network(networks, middle))
}

// Wire reach measures between footprint centres: a substation's centre
// sits one block in from its origin corner on x and z.
@(test)
test_substation_wire_reach_measures_from_the_footprint_centre :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	networks := &world.entities.electric_networks
	substation := place_test_entity(&world, content, "substation", {0, 1, 0})
	// Corner to corner 7.07, centre to centre 6.52: connects.
	east := place_test_entity(&world, content, "small_pole", {7, 1, 1})
	// Corner to corner 7, centre to centre 7.5: does not.
	west := place_test_entity(&world, content, "small_pole", {-7, 1, 0})
	testing.expect_value(t, entity_network(networks, east), entity_network(networks, substation))
	testing.expect(t, entity_network(networks, west) != entity_network(networks, substation))
}

@(test)
test_supply_volumes_of_big_poles_and_substations :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	networks := &world.entities.electric_networks
	place_test_entity(&world, content, "substation", {0, 1, 0})
	// Centred on the 2 by 2 footprint: x and z from -8 to 9, y 1 to 6.
	testing.expect_value(t, supply_volume_origin({0, 1, 0}, {2, 3, 2}, {18, 6, 18}), World_Coordinate{-8, 1, -8})
	for cell in ([?]World_Coordinate{{9, 1, 9}, {-8, 1, -8}, {9, 6, -8}}) {
		lamp := place_test_entity(&world, content, "lamp", cell)
		testing.expectf(t, entity_network(networks, lamp) == 0, "lamp at %v outside", cell)
	}
	for cell in ([?]World_Coordinate{{10, 1, 0}, {-9, 1, 0}, {0, 1, -9}, {0, 7, 0}}) {
		lamp := place_test_entity(&world, content, "lamp", cell)
		testing.expectf(t, entity_network(networks, lamp) == -1, "lamp at %v inside", cell)
	}
	// A big pole covers 3 by 3, 6 high.
	world = make_floor_world(content.blocks, 32)
	networks = &world.entities.electric_networks
	place_test_entity(&world, content, "big_pole", {0, 1, 0})
	inside := place_test_entity(&world, content, "lamp", {1, 6, -1})
	outside := place_test_entity(&world, content, "lamp", {2, 1, 0})
	testing.expect_value(t, entity_network(networks, inside), 0)
	testing.expect_value(t, entity_network(networks, outside), -1)
}

// Belt 2 in the data and in the drawing order.
@(test)
test_fast_belt_data :: proc(t: ^testing.T) {
	content := make_test_content()
	for id in ([?]string{"belt_2", "belt_ramp_2", "belt_lift_2"}) {
		machine := content.machines.machines[test_machine(content.machines, id)]
		// 3.75 blocks per second is 960 units, 16 a tick: 1800 items a
		// minute over two lanes at four items a block.
		testing.expect_value(t, machine.belt_speed_units_per_second, 960)
	}
	testing.expect(t, slice.equal(belt_speeds(content.machines), []u32{480, 960}))
	fast := test_machine(content.machines, "belt_2")
	testing.expect_value(t, find_belt_machine_of_speed(content.machines, .Ramp, 960), test_machine(content.machines, "belt_ramp_2"))
	testing.expect_value(t, find_belt_machine_of_speed(content.machines, .Lift, 960), test_machine(content.machines, "belt_lift_2"))
	testing.expect_value(t, find_belt_machine_of_speed(content.machines, .Ramp, 480), test_machine(content.machines, "belt_ramp"))
	belt := Belt{common = Entity_Common{machine = fast}}
	testing.expect_value(t, belt_carry_offset(belt, content.machines, TEST_TICK_RATE), [3]f32{16.0 / 256, 0, 0})
}

lay_belt_of :: proc(world: ^World, content: Simulation_Content, machine: string, cell: World_Coordinate, direction: u8) -> Entity_Handle {
	return add_belt(&world.entities, content.machines, test_machine(content.machines, machine), cell, direction, .Flat)
}

// Two fast belts into three yellow ones: two lines, split where the speed
// changes. An item crosses keeping its exact position, and an item behind
// one on the slower line waits a spacing back.
@(test)
test_mixed_speed_belts_hand_off_exactly :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	fast := [2]Entity_Handle{lay_belt_of(&world, content, "belt_2", {0, 1, 0}, 0), lay_belt_of(&world, content, "belt_2", {1, 1, 0}, 0)}
	slow := lay_belt_of(&world, content, "belt", {2, 1, 0}, 0)
	lay_belt_of(&world, content, "belt", {3, 1, 0}, 0)
	lay_belt_of(&world, content, "belt", {4, 1, 0}, 0)
	testing.expect_value(t, len(world.entities.belt_network.lines), 2)
	fast_line, slow_line := line_of(&world, fast[0]), line_of(&world, slow)
	testing.expect(t, fast_line == line_of(&world, fast[1]))
	testing.expect_value(t, fast_line.speed_units_per_second, 960)
	testing.expect_value(t, slow_line.speed_units_per_second, 480)
	testing.expect_value(t, fast_line.end.kind, Belt_Line_End_Kind.Straight)
	iron := test_item(content.items, "iron_plate")
	// 500 moves 16 to 516, which is 4 into the slow line, then 8 a tick.
	append(&fast_line.lanes[.Right], Lane_Item{item = iron, position = 500})
	tick_belts(&world, 1)
	testing.expect_value(t, len(fast_line.lanes[.Right]), 0)
	expect_positions(t, lane_positions(slow_line^, .Right), {4})
	tick_belts(&world, 1)
	expect_positions(t, lane_positions(slow_line^, .Right), {12})
	// On the left lane the fast item catches up with the slow one and
	// then follows exactly a spacing behind it, across the seam.
	append(&slow_line.lanes[.Left], Lane_Item{item = iron, position = 10})
	append(&fast_line.lanes[.Left], Lane_Item{item = iron, position = 450})
	length := belt_line_length(fast_line^)
	for tick in 0 ..< 60 {
		tick_belts(&world, 1)
		ahead := slow_line.lanes[.Left][len(slow_line.lanes[.Left]) - 1].position + length
		behind := len(fast_line.lanes[.Left]) > 0 ? fast_line.lanes[.Left][0].position : slow_line.lanes[.Left][0].position + length
		if len(fast_line.lanes[.Left]) == 0 && len(slow_line.lanes[.Left]) < 2 {
			testing.fail_now(t, "an item was lost")
		}
		testing.expectf(t, ahead - behind >= BELT_ITEM_SPACING, "tick %d: gap %d", tick, ahead - behind)
	}
	positions := lane_positions(slow_line^, .Left)
	testing.expect_value(t, len(positions), 2)
	testing.expect_value(t, positions[1] - positions[0], BELT_ITEM_SPACING)
	testing.expect_value(t, positions[1], 10 + 60 * 8)
	// Caught up after one tick: 450 + 16 is exactly a spacing behind 18
	// on the next line, so the hand off happened at the slow line's pace.
	testing.expect_value(t, positions[0], 10 + 60 * 8 - BELT_ITEM_SPACING)
}

// Dragging fast belts up a step takes a fast ramp, never a yellow one.
@(test)
test_fast_belt_drag_uses_fast_ramps :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	set_blocks(&world, test_block(content.blocks, "stone"), {3, 1, 0})
	players := []Player{make_test_player(content.blocks, {-3.5, 1, 0.5})}
	player := &players[0]
	give_test_items(player, content.items, "belt_2", 10)
	give_test_items(player, content.items, "belt_ramp", 2)
	give_test_items(player, content.items, "belt_ramp_2", 2)
	player.target = Raycast_Hit{hit = true, block = {0, 0, 0}, face = .Positive_Y, adjacent = {0, 1, 0}}
	place_with_player(&world, &records.statistics, content, players, 0, {.Place}, {.Place})
	for column in ([?][2]i32{{2, 0}, {3, 1}}) {
		player.target = Raycast_Hit{hit = true, block = {column.x, 0, column.y}, face = .Positive_Y, adjacent = {column.x, 1, column.y}}
		place_with_player(&world, &records.statistics, content, players, 0, {}, {.Place})
	}
	Expected_Belt :: struct {
		cell: World_Coordinate,
		id:   string,
	}
	expected := []Expected_Belt{{{0, 1, 0}, "belt_2"}, {{1, 1, 0}, "belt_2"}, {{2, 1, 0}, "belt_ramp_2"}, {{3, 2, 0}, "belt_2"}, {{3, 1, 1}, "belt_ramp_2"}}
	for entry in expected {
		belt := belt_at(&world.entities, entry.cell)
		testing.expectf(t, belt != nil && belt.machine == test_machine(content.machines, entry.id), "%v is not %s", entry.cell, entry.id)
	}
	testing.expect_value(t, len(world.entities.belt_network.lines), 1)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "belt_ramp")), 2)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "belt_ramp_2")), 0)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "belt_2")), 7)
}

@(test)
test_fast_and_long_inserter_data :: proc(t: ^testing.T) {
	content := make_test_content()
	fast := content.machines.machines[test_machine(content.machines, "fast_inserter")]
	testing.expect_value(t, fast.kind, Machine_Kind.Inserter)
	// 3600 / 138 rounds down to 26 ticks: 138.5 items a minute.
	testing.expect_value(t, inserter_cycle_ticks(fast, TEST_TICK_RATE), 26)
	testing.expect_value(t, electric_joules_per_tick(fast.electric_power_watts, TEST_TICK_RATE), 766)
	testing.expect_value(t, fast.inserter_reach, 1)
	long := content.machines.machines[test_machine(content.machines, "long_inserter")]
	testing.expect_value(t, inserter_cycle_ticks(long, TEST_TICK_RATE), 72)
	testing.expect_value(t, long.inserter_reach, 2)
	definition := Machine_Definition{id = "far", footprint = {width = 1, depth = 1, height = 1}, items_per_minute = 50, electric_power_kilowatts = 13, inserter_reach = 3}
	testing.expect(t, validate_inserter_definition(definition) != "")
}

// A long inserter takes from two cells behind and drops two cells ahead,
// leaving the chests next to it alone.
@(test)
test_long_inserter_reaches_two_cells :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	source := place_test_entity(&world, content, "wooden_chest", {0, 1, 0})
	near_behind := place_test_entity(&world, content, "wooden_chest", {1, 1, 0})
	inserter := place_test_entity(&world, content, "long_inserter", {2, 1, 0}, 0)
	near_ahead := place_test_entity(&world, content, "wooden_chest", {3, 1, 0})
	target := place_test_entity(&world, content, "wooden_chest", {4, 1, 0})
	add_test_power_plant(&world, content, {2, 1, 2}, {0, 1, 3})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	entity_insert(&world.entities, content, source, Item_Stack{plate, 5})
	entity_insert(&world.entities, content, near_behind, Item_Stack{coal, 5})
	testing.expect_value(t, inserter_pickup_cell(test_inserter(&world, inserter)^), World_Coordinate{0, 1, 0})
	testing.expect_value(t, inserter_drop_cell(test_inserter(&world, inserter)^), World_Coordinate{4, 1, 0})
	tick_test_entities(&world, &records, content, 6 * 72)
	testing.expect_value(t, chest_count_of(&world, target, plate), 5)
	testing.expect_value(t, chest_count_of(&world, source, plate), 0)
	testing.expect_value(t, chest_count_of(&world, near_behind, coal), 5)
	testing.expect_value(t, chest_count_of(&world, near_ahead, plate), 0)
}

@(test)
test_grid_technologies_gate_their_recipes :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	first, second := test_item(test.items, "science_pack_1"), test_item(test.items, "science_pack_2")
	Gate :: struct {
		technology:   string,
		prerequisite: string,
		packs:        int,
		recipes:      []string,
	}
	gates := []Gate {
		{"hydro_power", "fluid_handling", 100, {"hydro_turbine"}},
		{"electric_grid", "electric_mining", 100, {"big_pole", "substation"}},
		{"fast_inserters", "logistics", 75, {"fast_inserter", "long_inserter"}},
		{"fast_belts", "logistics_science", 100, {"belt_2", "belt_ramp_2", "belt_lift_2"}},
	}
	for gate in gates {
		index := test_technology(technologies, gate.technology)
		technology := technologies.technologies[index]
		testing.expect_value(t, technology.pack_count, gate.packs)
		testing.expect_value(t, technology.milliseconds_per_pack, 30_000)
		testing.expect(t, slice.equal(technology.science_packs, []Item_Id{first, second}))
		testing.expect(t, slice.contains(technology.prerequisites, test_technology(technologies, gate.prerequisite)))
		testing.expect(t, !technology.placeholder)
		for id in gate.recipes {
			testing.expectf(t, !test_available(test, id), "%s open before research", id)
		}
		mark_technology_researched(&test.unlocks, test.recipes, index)
		for id in gate.recipes {
			testing.expectf(t, test_available(test, id), "%s locked after research", id)
		}
	}
	belt := test_recipe(test.recipes, "belt_2")
	testing.expect_value(t, len(test.recipes.recipes[belt].inputs), 3)
}

// Water source, turbine, substation, a chest of plates, a long inserter
// onto three fast belts into three yellow ones, an inserter into a chest.
lay_hydro_factory :: proc(t: ^testing.T, world: ^World, content: Simulation_Content) -> (plates: Entity_Handle, tick: u64) {
	tick = add_settled_source(t, world, content, {-10, 1, -10})
	place_test_entity(world, content, "hydro_turbine", {-9, 1, -10})
	place_test_entity(world, content, "substation", {-4, 1, -4})
	source := place_test_entity(world, content, "wooden_chest", {-7, 1, 3})
	entity_insert(&world.entities, content, source, Item_Stack{test_item(content.items, "iron_plate"), 40})
	place_test_entity(world, content, "long_inserter", {-5, 1, 3}, 0)
	for x in i32(-3) ..= -1 {
		lay_belt_of(world, content, "belt_2", {x, 1, 3}, 0)
	}
	for x in i32(0) ..= 2 {
		lay_belt_of(world, content, "belt", {x, 1, 3}, 0)
	}
	place_test_entity(world, content, "inserter", {3, 1, 3}, 0)
	plates = place_test_entity(world, content, "wooden_chest", {4, 1, 3})
	return
}

@(test)
test_hydro_factory_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_floor_world(content.blocks, 32), make_floor_world(content.blocks, 32)}
	all_records: [2]Game_Records
	plate_chests: [2]Entity_Handle
	for &world, index in worlds {
		tick: u64
		plate_chests[index], tick = lay_hydro_factory(t, &world, content)
		for _ in 0 ..< 1200 {
			tick += 1
			tick_world(&world, &all_records[index].leaf_decay, content.blocks, tick)
			tick_entities(&world, &all_records[index], content, TEST_TICK_RATE)
		}
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	for inserter, index in first.inserters.entries {
		testing.expect(t, inserter == second.inserters.entries[index])
	}
	for chest, index in first.chests.entries {
		testing.expect(t, chest == second.chests.entries[index])
	}
	testing.expect(t, first.fluid_machines.entries[0] == second.fluid_machines.entries[0])
	testing.expect_value(t, len(first.belt_network.lines), 2)
	for line, line_index in first.belt_network.lines {
		for lane in Belt_Lane {
			testing.expect(t, slice.equal(line.lanes[lane][:], second.belt_network.lines[line_index].lanes[lane][:]))
		}
	}
	plate := test_item(content.items, "iron_plate")
	delivered := chest_count_of(&worlds[0], plate_chests[0], plate)
	testing.expectf(t, delivered >= 10, "only %d plates delivered", delivered)
	testing.expect_value(t, delivered, chest_count_of(&worlds[1], plate_chests[1], plate))
	testing.expect(t, all_records[0].statistics.energy_produced_joules > 0)
	testing.expect_value(t, all_records[0].statistics.energy_produced_joules, all_records[1].statistics.energy_produced_joules)
	testing.expect_value(t, all_records[0].statistics.brownout_ticks, 0)
}
