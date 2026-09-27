package game

import "core:testing"

// Power worlds stand on the stone floor of make_floor_world (top at y 1).

test_pole :: proc(world: ^World, handle: Entity_Handle) -> ^Pole {
	return pool_get(&world.entities.poles, handle)
}

test_lamp :: proc(world: ^World, handle: Entity_Handle) -> ^Lamp {
	return pool_get(&world.entities.lamps, handle)
}

// A small pole and a steam engine with full steam buffers, the engine
// inside the pole's supply volume.
add_test_power_plant :: proc(world: ^World, content: Simulation_Content, pole_cell, engine_origin: World_Coordinate) -> (pole, engine: Entity_Handle) {
	engine = place_test_entity(world, content, "steam_engine", engine_origin)
	steam := test_fluid(content, "steam")
	for &buffer in test_fluid_machine(world, engine).buffers[:2] {
		buffer = {fluid = steam, level = 200}
	}
	pole = place_test_entity(world, content, "small_pole", pole_cell)
	return
}

@(test)
test_power_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	pole := content.machines.machines[test_machine(content.machines, "small_pole")]
	testing.expect_value(t, pole.kind, Machine_Kind.Pole)
	testing.expect_value(t, pole.footprint, [3]i32{1, 3, 1})
	testing.expect_value(t, pole.supply_volume, [3]i32{5, 4, 5})
	testing.expect_value(t, pole.wire_reach, 7)
	testing.expect_value(t, pole.item, test_item(content.items, "small_pole"))
	switch_machine := content.machines.machines[test_machine(content.machines, "power_switch")]
	testing.expect_value(t, switch_machine.kind, Machine_Kind.Power_Switch)
	testing.expect_value(t, switch_machine.supply_volume, [3]i32{0, 0, 0})
	lamp := content.machines.machines[test_machine(content.machines, "lamp")]
	testing.expect_value(t, lamp.light_level, 14)
	testing.expect_value(t, electric_joules_per_tick(lamp.electric_power_watts, TEST_TICK_RATE), 83)
	drill := content.machines.machines[test_machine(content.machines, "electric_mining_drill")]
	testing.expect_value(t, drill.slot_count, 0)
	testing.expect_value(t, drill.footprint, [3]i32{3, 3, 3})
	testing.expect_value(t, drill_cycle_ticks(drill, TEST_TICK_RATE), 96)
	testing.expect_value(t, electric_joules_per_tick(drill.electric_power_watts, TEST_TICK_RATE), 1500)
	engine := content.machines.machines[test_machine(content.machines, "steam_engine")]
	testing.expect_value(t, electric_joules_per_tick(engine.electric_output_watts, TEST_TICK_RATE), 15_000)
	testing.expect_value(t, steam_joules_per_litre(engine), 30_000)
}

@(test)
test_poles_connect_within_reach :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	first := place_test_entity(&world, content, "small_pole", {0, 1, 0})
	// Seven blocks along x is in reach, eight is not.
	second := place_test_entity(&world, content, "small_pole", {7, 1, 0})
	third := place_test_entity(&world, content, "small_pole", {15, 1, 0})
	networks := &world.entities.electric_networks
	testing.expect_value(t, len(networks.networks), 2)
	testing.expect_value(t, len(networks.wires), 1)
	testing.expect_value(t, entity_network(networks, first), entity_network(networks, second))
	testing.expect(t, entity_network(networks, third) != entity_network(networks, first))
	// Straight line distance: 5 and 5 across is 7.07, too far.
	place_test_entity(&world, content, "small_pole", {-5, 1, -5})
	testing.expect_value(t, len(networks.networks), 3)
	// 4 and 4 across and 4 up is 6.93, in reach of the third.
	fourth := place_test_entity(&world, content, "small_pole", {19, 5, 4})
	testing.expect_value(t, entity_network(networks, fourth), entity_network(networks, third))
	// A pole between the second and the third joins them.
	place_test_entity(&world, content, "small_pole", {11, 1, 0})
	testing.expect_value(t, len(networks.networks), 2)
	testing.expect_value(t, entity_network(networks, first), entity_network(networks, third))
	testing.expect(t, remove_entity(&world.entities, content.machines, second))
	testing.expect(t, entity_network(networks, first) != entity_network(networks, third))
}

@(test)
test_supply_volume_decides_membership :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	place_test_entity(&world, content, "small_pole", {0, 1, 0})
	networks := &world.entities.electric_networks
	// The volume is x and z from -2 to 2 and y from 1 to 4.
	inside := place_test_entity(&world, content, "lamp", {2, 1, -2})
	outside := place_test_entity(&world, content, "lamp", {3, 1, 0})
	testing.expect_value(t, entity_network(networks, inside), 0)
	testing.expect_value(t, entity_network(networks, outside), -1)
	// One covered cell is enough: an electric drill reaching into it.
	drill := place_test_entity(&world, content, "electric_mining_drill", {-4, 1, -1})
	testing.expect_value(t, entity_network(networks, drill), 0)
	// Placing a pole later brings machines in.
	place_test_entity(&world, content, "small_pole", {5, 1, 0})
	testing.expect_value(t, entity_network(networks, outside), 0)
	// Machines that do not use power never join.
	chest := place_test_entity(&world, content, "wooden_chest", {1, 1, 1})
	testing.expect_value(t, entity_network(networks, chest), -1)
	testing.expect_value(t, supply_volume_origin({0, 1, 0}, {5, 4, 5}), World_Coordinate{-2, 1, -2})
}

participant :: proc(network: int, generator: bool, offered: u64) -> Electric_Participant {
	return Electric_Participant{network = network, generator = generator, offered = offered}
}

@(test)
test_energy_balance_with_two_generators_and_three_consumers :: proc(t: ^testing.T) {
	networks := make([]Electric_Network, 1, context.temp_allocator)
	// Enough supply: everyone gets their demand, 1799 J shared 15 to 10
	// with the joule left over rounding down going to the first.
	enough := []Electric_Participant{participant(0, true, 15_000), participant(0, false, 1500), participant(0, true, 10_000), participant(0, false, 216), participant(0, false, 83)}
	balance_electric_energy(enough, networks)
	testing.expect_value(t, networks[0].satisfaction, 1000)
	testing.expect_value(t, networks[0].supply, 25_000)
	testing.expect_value(t, networks[0].demand, 1799)
	testing.expect_value(t, networks[0].delivered, 1799)
	testing.expect_value(t, networks[0].generator_count, 2)
	testing.expect_value(t, networks[0].consumer_count, 3)
	delivered := [5]u64{enough[0].delivered, enough[1].delivered, enough[2].delivered, enough[3].delivered, enough[4].delivered}
	testing.expect_value(t, delivered, [5]u64{1080, 1500, 719, 216, 83})
	// Short: 1500 of 1799 is 833 per mille, and every consumer gets that
	// share of its demand.
	short := []Electric_Participant{participant(0, true, 1000), participant(0, false, 1500), participant(0, true, 500), participant(0, false, 216), participant(0, false, 83)}
	balance_electric_energy(short, networks)
	testing.expect_value(t, networks[0].satisfaction, 833)
	testing.expect_value(t, networks[0].delivered, 1497)
	delivered = {short[0].delivered, short[1].delivered, short[2].delivered, short[3].delivered, short[4].delivered}
	testing.expect_value(t, delivered, [5]u64{998, 1249, 499, 179, 69})
	// Nothing asks: full while something could give, none without supply.
	testing.expect_value(t, power_satisfaction(100, 0), 1000)
	testing.expect_value(t, power_satisfaction(0, 0), 0)
	testing.expect_value(t, power_satisfaction(0, 500), 0)
	// Outside every network nothing is delivered.
	alone := []Electric_Participant{participant(-1, false, 500)}
	balance_electric_energy(alone, networks)
	testing.expect_value(t, alone[0].delivered, 0)
}

// An electric drill on an iron vein dropping into a chest, a pole and a
// steam engine whose offer the test sets every tick.
Drill_Power_Test :: struct {
	world:  World,
	drill:  Entity_Handle,
	chest:  Entity_Handle,
	engine: Entity_Handle,
}

make_drill_power_test :: proc(content: Simulation_Content) -> Drill_Power_Test {
	test := Drill_Power_Test {
		world = make_drill_world(content),
	}
	vein := add_test_vein(&test.world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	test.drill = place_test_entity(&test.world, content, "electric_mining_drill", {0, 1, 0})
	test_drill(&test.world, test.drill).vein = vein
	test.chest = place_test_entity(&test.world, content, "iron_chest", {3, 1, 1})
	_, test.engine = add_test_power_plant(&test.world, content, {4, 1, 3}, {5, 1, -2})
	return test
}

// The engine has no steam and exactly `joules` drawn already, so that is
// its offer for the tick.
tick_with_engine_offer :: proc(test: ^Drill_Power_Test, content: Simulation_Content, joules: u32, ticks: int) {
	for _ in 0 ..< ticks {
		engine := test_fluid_machine(&test.world, test.engine)
		engine.buffers[0], engine.buffers[1] = EMPTY_FLUID_BUFFER, EMPTY_FLUID_BUFFER
		engine.fuel_joules = joules
		tick_test_entities(&test.world, content, 1)
	}
}

chest_total :: proc(world: ^World, chest: Entity_Handle) -> int {
	total := 0
	for slot in entity_slots(&world.entities, chest) {
		total += int(slot.count)
	}
	return total
}

@(test)
test_brownout_slows_an_electric_drill :: proc(t: ^testing.T) {
	content := make_test_content()
	full := make_drill_power_test(content)
	networks := &full.world.entities.electric_networks
	testing.expect_value(t, entity_network(networks, full.drill), entity_network(networks, full.engine))
	// 96 ticks a unit at full power: ten units in 960 ticks.
	tick_with_engine_offer(&full, content, 1500, 960)
	testing.expect_value(t, chest_total(&full.world, full.chest), 10)
	testing.expect_value(t, networks.networks[0].satisfaction, 1000)
	testing.expect_value(t, full.world.statistics.brownout_ticks, 0)
	// Half the drill's 1500 J: it mines every other tick, five units.
	half := make_drill_power_test(content)
	tick_with_engine_offer(&half, content, 750, 960)
	testing.expect_value(t, chest_total(&half.world, half.chest), 5)
	testing.expect_value(t, half.world.entities.electric_networks.networks[0].satisfaction, 500)
	testing.expect_value(t, test_drill(&half.world, half.drill).state, Drill_State.Mining)
	testing.expect_value(t, half.world.statistics.brownout_ticks, 960)
	testing.expect_value(t, half.world.statistics.energy_consumed_joules, 960 * 750)
	// No offer at all: unpowered, nothing mined.
	none := make_drill_power_test(content)
	tick_with_engine_offer(&none, content, 0, 200)
	testing.expect_value(t, chest_total(&none.world, none.chest), 0)
	testing.expect_value(t, test_drill(&none.world, none.drill).state, Drill_State.Unpowered)
}

@(test)
test_steam_is_drawn_only_for_delivered_energy :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	_, engine := add_test_power_plant(&world, content, {4, 1, 3}, {5, 1, -2})
	lamps := [2]Entity_Handle{place_test_entity(&world, content, "lamp", {3, 1, 2}), place_test_entity(&world, content, "lamp", {3, 1, 4})}
	// Nothing asks yet except the lamps: 166 J a tick, a litre every
	// 180 ticks and a bit.
	tick_test_entities(&world, content, 1000)
	machine := test_fluid_machine(&world, engine)
	litres_used := 400 - i64(machine.buffers[0].level) - i64(machine.buffers[1].level)
	testing.expect_value(t, world.statistics.energy_produced_joules, 166 * 1000)
	testing.expect_value(t, litres_used * 30_000, i64(world.statistics.energy_produced_joules) + i64(machine.fuel_joules))
	testing.expect_value(t, litres_used, 6)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Producing)
	testing.expect_value(t, machine.generated_joules, 166)
	testing.expect(t, test_lamp(&world, lamps[0]).lit)
	// Out of steam the engine gives nothing and the lamps go dark.
	machine.buffers[0], machine.buffers[1] = EMPTY_FLUID_BUFFER, EMPTY_FLUID_BUFFER
	machine.fuel_joules = 0
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, machine.state, Fluid_Machine_State.No_Steam)
	testing.expect(t, !test_lamp(&world, lamps[0]).lit)
	testing.expect_value(t, world.statistics.brownout_ticks, 1)
}

@(test)
test_power_switch_splits_a_network :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	near, _ := add_test_power_plant(&world, content, {0, 1, 0}, {-3, 1, -2})
	far := place_test_entity(&world, content, "small_pole", {10, 1, 0})
	lamp := place_test_entity(&world, content, "lamp", {11, 1, 0})
	networks := &world.entities.electric_networks
	testing.expect_value(t, len(networks.networks), 2)
	switch_handle := place_test_entity(&world, content, "power_switch", {5, 1, 0})
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect_value(t, entity_network(networks, far), entity_network(networks, near))
	tick_test_entities(&world, content, 2)
	testing.expect(t, test_lamp(&world, lamp).lit)
	testing.expect(t, toggle_power_switch(&world.entities, content.machines, switch_handle))
	testing.expect(t, !test_pole(&world, switch_handle).on)
	testing.expect_value(t, len(networks.networks), 2)
	testing.expect(t, entity_network(networks, far) != entity_network(networks, near))
	testing.expect_value(t, entity_network(networks, switch_handle), -1)
	// The wires stay, they carry nothing while the switch is off.
	testing.expect_value(t, len(networks.wires), 2)
	tick_test_entities(&world, content, 2)
	testing.expect(t, !test_lamp(&world, lamp).lit)
	testing.expect_value(t, test_lamp(&world, lamp).power.satisfaction, 0)
	testing.expect(t, toggle_power_switch(&world.entities, content.machines, switch_handle))
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect(t, !toggle_power_switch(&world.entities, content.machines, far))
}

@(test)
test_lamp_lights_and_darkens_with_power :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pole, _ := add_test_power_plant(&world, content, {0, 1, 0}, {-3, 1, -2})
	lamp := place_test_entity(&world, content, "lamp", {2, 1, 2})
	tick_test_entities(&world, content, 1)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {2, 1, 2}), 14)
	testing.expect_value(t, block_light_at(&world, {2, 2, 2}), 13)
	testing.expect_value(t, block_light_at(&world, {5, 1, 2}), 11)
	// Without its pole the lamp is unpowered, and its light goes out
	// through the removal queue.
	testing.expect(t, remove_entity(&world.entities, content.machines, pole))
	tick_test_entities(&world, content, 1)
	testing.expect(t, !test_lamp(&world, lamp).lit)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {2, 1, 2}), 0)
	testing.expect_value(t, block_light_at(&world, {5, 1, 2}), 0)
	testing.expect_value(t, len(world.entity_lights), 0)
	// Back on, then picked up while lit: the light goes with it.
	place_test_entity(&world, content, "small_pole", {0, 1, 0})
	tick_test_entities(&world, content, 1)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {2, 1, 2}), 14)
	testing.expect(t, remove_entity(&world.entities, content.machines, lamp))
	tick_test_entities(&world, content, 1)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {3, 1, 2}), 0)
}

// Water, a boiler, a steam engine, two poles, an electric drill feeding
// a chest, a lamp and an electric inserter between two chests.
build_power_plant :: proc(world: ^World, content: Simulation_Content) {
	place_test_fluid_entity(world, content, "offshore_pump", {2, 1, -3})
	lay_pipes(world, content, {1, 1, -3}, {1, 1, -2}, {1, 1, -1})
	boiler := place_test_fluid_entity(world, content, "boiler", {0, 1, 0})
	test_fluid_machine(world, boiler).slots[BOILER_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 20}
	lay_pipes(world, content, {1, 1, 2})
	place_test_fluid_entity(world, content, "steam_engine", {0, 1, 3})
	place_test_entity(world, content, "small_pole", {3, 1, 5})
	place_test_entity(world, content, "small_pole", {6, 1, 9})
	vein := add_test_vein(world, content, "iron", {8, 8}, 2, IRON_TEST_VEIN)
	drill := place_test_entity(world, content, "electric_mining_drill", {7, 1, 7})
	test_drill(world, drill).vein = vein
	place_test_entity(world, content, "iron_chest", {10, 1, 8})
	place_test_entity(world, content, "lamp", {5, 1, 8})
	source := place_test_entity(world, content, "wooden_chest", {4, 1, 10})
	place_test_entity(world, content, "inserter", {5, 1, 10}, 0)
	place_test_entity(world, content, "wooden_chest", {6, 1, 10})
	entity_insert(&world.entities, content, source, Item_Stack{test_item(content.items, "iron_plate"), 40})
}

@(test)
test_power_simulation_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_drill_world(content), make_drill_world(content)}
	for &world in worlds {
		build_power_plant(&world, content)
		tick_test_entities(&world, content, 1200)
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	for drill, index in first.drills.entries {
		testing.expect_value(t, drill, second.drills.entries[index])
	}
	for inserter, index in first.inserters.entries {
		testing.expect_value(t, inserter, second.inserters.entries[index])
	}
	for machine, index in first.fluid_machines.entries {
		testing.expect_value(t, machine, second.fluid_machines.entries[index])
	}
	for lamp, index in first.lamps.entries {
		testing.expect_value(t, lamp, second.lamps.entries[index])
	}
	for chest, index in first.chests.entries {
		testing.expect_value(t, chest.slots, second.chests.entries[index].slots)
	}
	testing.expect_value(t, worlds[0].statistics.energy_produced_joules, worlds[1].statistics.energy_produced_joules)
	// The plant runs: one network, power made, ore mined, plates moved.
	world := &worlds[0]
	testing.expect_value(t, len(first.electric_networks.networks), 1)
	testing.expect(t, world.statistics.energy_produced_joules > 0)
	testing.expect_value(t, world.statistics.unpowered_machines, 0)
	testing.expect(t, chest_total(world, entity_at(first, {10, 1, 8})) > 0)
	testing.expect(t, chest_total(world, entity_at(first, {6, 1, 10})) > 0)
	testing.expect(t, first.lamps.entries[0].lit)
}

@(test)
test_largest_consumers_group_by_machine :: proc(t: ^testing.T) {
	participants := []Electric_Participant {
		{machine = 3, network = 0, offered = 216},
		{machine = 5, network = 0, offered = 1500},
		{machine = 3, network = 0, offered = 216},
		{machine = 7, network = 0, generator = true, offered = 15_000},
		{machine = 2, network = 1, offered = 9000},
	}
	groups := largest_consumer_groups(participants, 0, 5)
	testing.expect_value(t, len(groups), 2)
	testing.expect_value(t, groups[0], Consumer_Group{machine = 5, count = 1, demand = 1500})
	testing.expect_value(t, groups[1], Consumer_Group{machine = 3, count = 2, demand = 432})
}
