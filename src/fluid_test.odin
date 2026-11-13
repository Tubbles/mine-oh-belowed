package game

import "core:testing"

// Fluid worlds stand on the stone floor of make_floor_world (top at y 1).

place_test_fluid_entity :: proc(world: ^World, content: Simulation_Content, id: string, origin: World_Coordinate, rotation: u8 = 0) -> Entity_Handle {
	return add_entity(&world.entities, content.machines, test_machine(content.machines, id), origin, rotation)
}

// An offshore pump with full power, which tick_test_fluids leaves as it
// is (the offshore pump draws electricity, 0140).
place_powered_offshore_pump :: proc(world: ^World, content: Simulation_Content, origin: World_Coordinate, rotation: u8 = 0) -> Entity_Handle {
	pump := place_test_fluid_entity(world, content, "offshore_pump", origin, rotation)
	test_fluid_machine(world, pump).power.satisfaction = POWER_FULL
	return pump
}

// A storage tank holding litres of the fluid. Pipes hold nothing (0356),
// so a test that needs fluid waiting on a netlist puts it in a tank.
place_test_tank :: proc(world: ^World, content: Simulation_Content, origin: World_Coordinate, fluid: string, litres: i32) -> Entity_Handle {
	tank := place_test_fluid_entity(world, content, "storage_tank", origin)
	test_fluid_machine(world, tank).buffers[0] = {fluid = test_fluid(content, fluid), level = litres}
	return tank
}

lay_pipes :: proc(world: ^World, content: Simulation_Content, cells: ..World_Coordinate) -> []Entity_Handle {
	handles := make([]Entity_Handle, len(cells), context.temp_allocator)
	for cell, index in cells {
		handles[index] = place_test_fluid_entity(world, content, "pipe", cell)
	}
	return handles
}

// Pipes stacked in a column at x z, from y bottom to y top.
lay_pipe_column :: proc(world: ^World, content: Simulation_Content, x, z, bottom, top: i32) -> []Entity_Handle {
	cells := make([]World_Coordinate, top - bottom + 1, context.temp_allocator)
	for &cell, index in cells {
		cell = {x, bottom + i32(index), z}
	}
	return lay_pipes(world, content, ..cells)
}

test_pipe :: proc(world: ^World, handle: Entity_Handle) -> ^Pipe {
	return pool_get(&world.entities.pipes, handle)
}

test_fluid_machine :: proc(world: ^World, handle: Entity_Handle) -> ^Fluid_Machine {
	return pool_get(&world.entities.fluid_machines, handle)
}

test_fluid :: proc(content: Simulation_Content, id: string) -> Fluid_Id {
	fluid, found := find_fluid_id(content.fluids, id)
	assert(found, id)
	return fluid
}

tick_test_fluids :: proc(world: ^World, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		tick_fluids(&world.entities, content, TEST_TICK_RATE)
	}
}

@(test)
test_fluid_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	water, steam := test_fluid(content, "water"), test_fluid(content, "steam")
	testing.expect(t, !fluid_is_gas(content.fluids, water))
	testing.expect(t, fluid_is_gas(content.fluids, steam))
	pipe := content.machines.machines[test_machine(content.machines, "pipe")]
	testing.expect_value(t, pipe.kind, Machine_Kind.Pipe)
	testing.expect_value(t, pipe_flow_per_tick(content.machines, TEST_TICK_RATE), 20)
	testing.expect_value(t, pipe.item, test_item(content.items, "pipe"))
	boiler := content.machines.machines[test_machine(content.machines, "boiler")]
	testing.expect_value(t, boiler.footprint, [3]i32{3, 2, 2})
	testing.expect_value(t, boiler.slot_count, 1)
	testing.expect_value(t, boiler.fuel_power_watts, 1_800_000)
	testing.expect_value(t, boiler.fluid_port_count, 2)
	testing.expect_value(t, boiler.fluid_ports[0], Fluid_Port{cell = {1, 0, 0}, face = .Negative_Z, direction = .Input, filter = water, capacity = 200})
	testing.expect_value(t, boiler.fluid_ports[1].filter, steam)
	tank := content.machines.machines[test_machine(content.machines, "storage_tank")]
	testing.expect(t, tank.fluid_ports[0].every_face)
	testing.expect_value(t, tank.fluid_ports[0].capacity, 25_000)
	testing.expect_value(t, content.machines.machines[test_machine(content.machines, "steam_engine")].fluid_port_count, 2)
	testing.expect_value(t, content.machines.machines[test_machine(content.machines, "offshore_pump")].fluid_litres_per_second, 1200)
	testing.expect_value(t, content.machines.machines[test_machine(content.machines, "pump")].electric_power_watts, 30_000)
	testing.expect_value(t, content.machines.machines[test_machine(content.machines, "offshore_pump")].electric_power_watts, 60_000)
}

@(test)
test_fluid_data_rejects_bad_ports :: proc(t: ^testing.T) {
	boiler := Machine_Definition {
		id                      = "boiler",
		name_key                = "machine_boiler",
		item                    = "boiler",
		kind                    = "boiler",
		footprint               = {3, 2, 2},
		fuel_slots              = 1,
		fuel_power_kilowatts    = 1800,
		fluid_litres_per_second = 60,
		fluid_ports             = {
			{cell = {1, 0, 0}, face = "negative_z", direction = "input", fluid = "water", buffer_litres = 200},
			{cell = {1, 0, 1}, face = "positive_z", direction = "output", fluid = "steam", buffer_litres = 200},
		},
	}
	testing.expect_value(t, resolve_test_machines({boiler}), "")
	inward := boiler
	inward.fluid_ports = {{cell = {1, 0, 0}, face = "positive_z", direction = "input", fluid = "water", buffer_litres = 200}, boiler.fluid_ports[1]}
	testing.expect(t, resolve_test_machines({inward}) != "")
	outside := boiler
	outside.fluid_ports = {{cell = {5, 0, 0}, face = "negative_z", direction = "input", fluid = "water", buffer_litres = 200}, boiler.fluid_ports[1]}
	testing.expect(t, resolve_test_machines({outside}) != "")
	unknown_fluid := boiler
	unknown_fluid.fluid_ports = {{cell = {1, 0, 0}, face = "negative_z", direction = "input", fluid = "lava", buffer_litres = 200}, boiler.fluid_ports[1]}
	testing.expect(t, resolve_test_machines({unknown_fluid}) != "")
	one_port := boiler
	one_port.fluid_ports = boiler.fluid_ports[:1]
	testing.expect(t, resolve_test_machines({one_port}) != "")
}

@(test)
test_fluid_ports_turn_with_the_footprint :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := content.machines.machines[test_machine(content.machines, "boiler")]
	for rotation in u8(0) ..< 4 {
		common := make_entity_common(content.machines, test_machine(content.machines, "boiler"), {10, 1, 10}, rotation)
		face := placed_port_face(common, machine, machine.fluid_ports[0])
		testing.expect_value(t, face.face, rotate_direction(.Negative_Z, rotation))
		testing.expect(t, cell_in_box(face.cell, common.origin, common.size))
		testing.expect(t, !cell_in_box(face.cell + World_Coordinate(direction_offsets[face.face]), common.origin, common.size))
	}
	testing.expect_value(t, rotate_direction(.Positive_X, 1), Direction.Positive_Z)
	testing.expect_value(t, rotate_direction(.Negative_Z, 1), Direction.Positive_X)
	testing.expect_value(t, rotate_direction(.Positive_Y, 3), Direction.Positive_Y)
}

// An L of four pipes between a tank and a boiler's inlet is one junction:
// one netlist of three nodes, and the boiler's outlet alone another.
@(test)
test_touching_pipes_are_one_junction :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	tank := place_test_fluid_entity(&world, content, "storage_tank", {4, 1, -3})
	pipes := lay_pipes(&world, content, {1, 1, -1}, {1, 1, -2}, {2, 1, -2}, {3, 1, -2})
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	networks := &world.entities.fluid_networks
	testing.expect_value(t, fluid_netlist_count(networks), 2)
	testing.expect_value(t, len(networks.nodes), 4)
	line := fluid_netlist_of(networks, tank, 0)
	for pipe in pipes {
		testing.expect_value(t, fluid_node_of(networks, pipe, -1), fluid_node_of(networks, pipes[0], -1))
		testing.expect_value(t, fluid_netlist_of(networks, pipe, -1), line)
	}
	testing.expect_value(t, fluid_netlist_of(networks, boiler, 0), line)
	testing.expect_value(t, networks.topology.trees[line].count, 3)
	testing.expect(t, fluid_netlist_of(networks, boiler, 1) != line)
}

// A full water tank piped to a boiler's inlet: 20 L a tick through the
// joint until the inlet holds 200, the tank losing exactly that and each
// pipe showing the water passing.
@(test)
test_a_joint_carries_twenty_litres_a_tick :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	water := test_fluid(content, "water")
	tank := place_test_tank(&world, content, {0, 1, -6}, "water", 25_000)
	pipes := lay_pipes(&world, content, {1, 1, -3}, {1, 1, -2}, {1, 1, -1})
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	for tick in 1 ..= 10 {
		tick_test_fluids(&world, content, 1)
		testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[0].level, i32(20 * tick))
		testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 25_000 - i32(20 * tick))
	}
	for pipe in pipes {
		testing.expect_value(t, test_pipe(&world, pipe).buffer, Fluid_Buffer{fluid = water, flow_in = 20, flow_out = 20})
	}
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 24_800)
	testing.expect_value(t, test_pipe(&world, pipes[0]).buffer, Fluid_Buffer{fluid = water})
}

// No gravity in a pipe: a boiler eight blocks above its tank fills as one
// on the floor does, and a full tank above an empty one on one column
// keeps its litres.
@(test)
test_height_moves_nothing_by_itself :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	place_test_tank(&world, content, {0, 1, -6}, "water", 1000)
	lay_pipe_column(&world, content, 1, -3, 1, 9)
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 9, -2})
	tick_test_fluids(&world, content, 5)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[0].level, 100)
	tick_test_fluids(&world, content, 5)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[0].level, 200)

	stacked := make_floor_world(content.blocks, 32)
	lay_pipe_column(&stacked, content, 1, -3, 1, 11)
	low := place_test_fluid_entity(&stacked, content, "storage_tank", {0, 1, -6})
	high := place_test_tank(&stacked, content, {0, 9, -6}, "water", 25_000)
	tick_test_fluids(&stacked, content, 100)
	testing.expect_value(t, test_fluid_machine(&stacked, high).buffers[0].level, 25_000)
	testing.expect_value(t, test_fluid_machine(&stacked, low).buffers[0].level, 0)
}

// A powered offshore pump, a tank and a boiler's inlet on one junction:
// the inlet fills first and the tank takes the rest; with the pump off and
// the inlet half drained, the tank refills it.
@(test)
test_a_tank_fills_from_what_is_left_and_empties_last :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pump := place_powered_offshore_pump(&world, content, {0, 1, 0})
	lay_pipes(&world, content, {-1, 1, 0}, {-2, 1, 0}, {-3, 1, 0})
	boiler := place_test_fluid_entity(&world, content, "boiler", {-3, 1, 1})
	tank := place_test_fluid_entity(&world, content, "storage_tank", {-6, 1, -1})
	tick_test_fluids(&world, content, 10)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[0].level, 200)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 0)
	tick_test_fluids(&world, content, 10)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 200)
	test_fluid_machine(&world, pump).power.satisfaction = 0
	test_fluid_machine(&world, boiler).buffers[0].level = 100
	tick_test_fluids(&world, content, 5)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[0].level, 200)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 100)
}

// Two tanks on one netlist never even out. A pump between two netlists is
// a consumer on the first and a producer on the second: powered it
// empties one tank into the other at 20 L a tick, unpowered it passes
// nothing.
@(test)
test_a_pump_moves_one_tank_into_another :: proc(t: ^testing.T) {
	content := make_test_content()
	side_by_side := make_floor_world(content.blocks, 32)
	full := place_test_tank(&side_by_side, content, {-4, 1, -1}, "water", 25_000)
	lay_pipes(&side_by_side, content, {-1, 1, 0}, {0, 1, 0}, {1, 1, 0})
	empty := place_test_fluid_entity(&side_by_side, content, "storage_tank", {2, 1, -1})
	testing.expect_value(t, fluid_netlist_count(&side_by_side.entities.fluid_networks), 1)
	tick_test_fluids(&side_by_side, content, 100)
	testing.expect_value(t, test_fluid_machine(&side_by_side, full).buffers[0].level, 25_000)
	testing.expect_value(t, test_fluid_machine(&side_by_side, empty).buffers[0].level, 0)

	world := make_floor_world(content.blocks, 32)
	source := place_test_tank(&world, content, {-4, 1, -1}, "water", 25_000)
	lay_pipes(&world, content, {-1, 1, 0}, {2, 1, 0})
	pump := place_test_fluid_entity(&world, content, "pump", {0, 1, 0})
	target := place_test_fluid_entity(&world, content, "storage_tank", {3, 1, -1})
	testing.expect_value(t, fluid_netlist_count(&world.entities.fluid_networks), 2)
	tick_test_fluids(&world, content, 100)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Unpowered)
	testing.expect_value(t, test_fluid_machine(&world, target).buffers[0].level, 0)
	// The pump's inlet filled from the source and waits.
	testing.expect_value(t, test_fluid_machine(&world, source).buffers[0].level, 24_800)
	test_fluid_machine(&world, pump).power.satisfaction = POWER_FULL
	tick_test_fluids(&world, content, 100)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Pumping)
	testing.expect_value(t, test_fluid_machine(&world, target).buffers[0].level, 2000)
	testing.expect_value(t, test_fluid_machine(&world, source).buffers[0].level, 22_800)
}

// Steam into a steam engine's inlet moves as water into a boiler's: the
// same 20 L a tick from a tank on the same pipes.
@(test)
test_gas_and_liquid_move_alike :: proc(t: ^testing.T) {
	content := make_test_content()
	pairs := [2][2]string{{"boiler", "water"}, {"steam_engine", "steam"}}
	for pair in pairs {
		world := make_floor_world(content.blocks, 32)
		machine := place_test_fluid_entity(&world, content, pair[0], {0, 1, 0})
		lay_pipes(&world, content, {1, 1, -2}, {1, 1, -1})
		place_test_tank(&world, content, {0, 1, -5}, pair[1], 1000)
		for tick in 1 ..= 10 {
			tick_test_fluids(&world, content, 1)
			testing.expect_value(t, test_fluid_machine(&world, machine).buffers[0].level, i32(20 * tick))
		}
	}
}

// A water tank placed before a boiler and piped to its steam outlet: the
// netlist is water, so the outlet closes (one refusal) and the tank keeps
// its water. Emptied, the netlist takes the steam and the tank fills with
// it.
@(test)
test_a_port_refuses_to_mix_fluids :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_fluid_test_records(content)
	water, steam := test_fluid(content, "water"), test_fluid(content, "steam")
	tank := place_test_tank(&world, content, {0, 1, 4}, "water", 1000)
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	// The steam outlet faces +z from cell (1, 1, 1).
	lay_pipes(&world, content, {1, 1, 2}, {1, 1, 3})
	test_fluid_machine(&world, boiler).buffers[1] = {fluid = steam, level = 200}
	tick_test_fluids_with_statistics(&world, &records, content, 5)
	testing.expect(t, test_fluid_machine(&world, boiler).closed[1])
	testing.expect_value(t, records.statistics.mixing_refusals, 1)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[1].level, 200)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].fluid, water)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 1000)
	// Once the water is gone the netlist takes the steam.
	test_fluid_machine(&world, tank).buffers[0] = EMPTY_FLUID_BUFFER
	tick_test_fluids_with_statistics(&world, &records, content, 1)
	testing.expect(t, !test_fluid_machine(&world, boiler).closed[1])
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].fluid, steam)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 20)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[1].level, 180)
}

// A water line (a tank, a boiler's inlet) joined by new pipes to a later
// boiler's steam outlet stays water and closes the outlet. With the tank
// emptied no water feeder holds litres, so the steam outlet, a feeder
// holding litres though closed, outranks the inlet still holding water:
// the netlist takes the steam, the inlet closes and the tank fills with
// steam. Two feeders of different fluids on one line is the player's
// mistake, which the mixing hint reports, and neither side stops for good:
// with the steam outlet taken away and the tank of steam replaced by one
// of water, the water line runs again. Saved and loaded midway, both run
// on to the same hash.
@(test)
test_a_netlist_keeps_its_fluid_while_an_open_port_holds_it :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	header := make_save_header()
	simulation := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&simulation)
	world := &simulation.world
	water, steam := test_fluid(content, "water"), test_fluid(content, "steam")
	tank := place_test_tank(world, content, {0, 1, -5}, "water", 1000)
	lay_pipes(world, content, {1, 1, -2}, {1, 1, -1})
	drinker := place_test_fluid_entity(world, content, "boiler", {0, 1, 0})
	tick_test_fluids(world, content, 10)
	testing.expect_value(t, test_fluid_machine(world, drinker).buffers[0].level, 200)
	// The later boiler's outlet faces +z from cell (4, 1, -3).
	steamer := place_test_fluid_entity(world, content, "boiler", {3, 1, -4})
	test_fluid_machine(world, steamer).buffers[1] = {fluid = steam, level = 200}
	joining := lay_pipes(world, content, {2, 1, -2}, {3, 1, -2}, {4, 1, -2})
	records := make_fluid_test_records(content)
	tick_test_fluids_with_statistics(world, &records, content, 5)
	testing.expect(t, test_fluid_machine(world, steamer).closed[1])
	testing.expect_value(t, records.statistics.mixing_refusals, 1)
	testing.expect_value(t, test_pipe(world, joining[2]).buffer.fluid, water)
	testing.expect_value(t, test_fluid_machine(world, steamer).buffers[1].level, 200)

	test_fluid_machine(world, tank).buffers[0] = EMPTY_FLUID_BUFFER
	test_fluid_machine(world, drinker).slots[BOILER_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 5}
	tick_test_fluids_with_statistics(world, &records, content, 100)
	// The boiler burns its own inlet's water, closed or not.
	testing.expect_value(t, test_fluid_machine(world, drinker).buffers[0].level, 100)
	testing.expect(t, test_fluid_machine(world, drinker).closed[0])
	testing.expect(t, !test_fluid_machine(world, steamer).closed[1])
	testing.expect_value(t, records.statistics.mixing_refusals, 2)
	testing.expect_value(t, test_pipe(world, joining[2]).buffer.fluid, steam)
	testing.expect_value(t, test_fluid_machine(world, tank).buffers[0].fluid, steam)
	testing.expect_value(t, test_fluid_machine(world, tank).buffers[0].level, 200)

	remap: Content_Remap
	loaded := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&loaded)
	testing.expect_value(t, decode_entities(&loaded, content, encode_entities(&simulation, content, header), "entities.bin", header, &remap), "")
	testing.expect_value(t, simulation_state_hash(&loaded), simulation_state_hash(&simulation))
	tick_test_fluids(world, content, 200)
	tick_test_fluids(&loaded.world, content, 200)
	testing.expect_value(t, simulation_state_hash(&loaded), simulation_state_hash(&simulation))
	testing.expect(t, test_fluid_machine(world, drinker).closed[0])
	testing.expect(t, !test_fluid_machine(world, steamer).closed[1])
	testing.expect_value(t, test_fluid_machine(world, tank).buffers[0].fluid, steam)
	testing.expect_value(t, test_fluid_machine(world, tank).buffers[0].level, 200)
	testing.expect_value(t, test_pipe(world, joining[2]).buffer.fluid, steam)

	// The steam outlet taken away, and the tank of steam picked up (its
	// steam lost) and placed again full of water.
	testing.expect(t, remove_entity(&world.entities, content.machines, steamer))
	testing.expect(t, remove_entity(&world.entities, content.machines, tank))
	place_test_tank(world, content, {0, 1, -5}, "water", 1000)
	tick_test_fluids(world, content, 20)
	testing.expect(t, !test_fluid_machine(world, drinker).closed[0])
	testing.expect_value(t, test_fluid_machine(world, drinker).buffers[0].fluid, water)
	testing.expect_value(t, test_fluid_machine(world, drinker).buffers[0].level, 200)
	testing.expect_value(t, test_pipe(world, joining[2]).buffer.fluid, water)
}

// An unpowered pump whose inlet holds 5 L of water, piped onto a gas line
// of a tank and a combustion generator, closes, and the tank goes on
// feeding the generator, whether the pump comes before the tank in node
// order or after it.
@(test)
test_an_inlet_holding_another_fluid_does_not_decide_its_netlist :: proc(t: ^testing.T) {
	content := make_test_content()
	water, gas := test_fluid(content, "water"), test_fluid(content, "petroleum_gas")
	for pump_first in ([2]bool{true, false}) {
		world := make_oil_world(content)
		pump: Entity_Handle
		if pump_first {
			pump = place_test_fluid_entity(&world, content, "pump", {-10, 1, 0})
		}
		tank := place_test_tank(&world, content, {-15, 1, -1}, "petroleum_gas", 10_000)
		generator := place_test_fluid_entity(&world, content, "combustion_generator", {-13, 1, 2})
		if !pump_first {
			pump = place_test_fluid_entity(&world, content, "pump", {-10, 1, 0})
		}
		test_fluid_machine(&world, pump).buffers[0] = {fluid = water, level = 5}
		lay_pipes(&world, content, {-12, 1, 0}, {-12, 1, 1})
		tick_test_fluids(&world, content, 5)
		// The pump's inlet faces -x from (-10, 1, 0).
		joining := lay_pipes(&world, content, {-11, 1, 0})[0]
		held := test_fluid_machine(&world, tank).buffers[0].level + test_fluid_machine(&world, generator).buffers[0].level
		burned: i32
		for _ in 0 ..< 300 {
			// The generator burns 10 L a tick.
			inlet := &test_fluid_machine(&world, generator).buffers[0]
			burned += min(inlet.level, 10)
			inlet.level -= min(inlet.level, 10)
			tick_test_fluids(&world, content, 1)
		}
		testing.expectf(t, burned == 3000, "pump first %v: the generator burned %d L", pump_first, burned)
		testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level + test_fluid_machine(&world, generator).buffers[0].level + burned, held)
		testing.expect_value(t, test_fluid_machine(&world, generator).buffers[0].fluid, gas)
		testing.expect_value(t, test_fluid_machine(&world, pump).buffers[0], Fluid_Buffer{fluid = water, level = 5})
		testing.expect(t, test_fluid_machine(&world, pump).closed[0])
		testing.expect_value(t, test_pipe(&world, joining).buffer.fluid, gas)
	}
}

// A powered tar pit pump's crude line of three pipes into a refinery's
// inlet, drained 100 L a craft. After 120 + phase ticks a pipe joins it to
// an unpowered pump whose inlet holds 5 L of water (to nothing in the
// control). Returns the crude the refinery received over the next 1200
// ticks.
crude_received_after_a_join :: proc(content: Simulation_Content, phase: int, with_pump: bool) -> (received: i32) {
	world := make_oil_world(content)
	world_set_block(&world, {-4, 0, 0}, test_block(content.blocks, "tar_pit"))
	tar := place_test_fluid_entity(&world, content, "tar_pit_pump", {-6, 1, 0})
	test_fluid_machine(&world, tar).power.satisfaction = POWER_FULL
	lay_pipes(&world, content, {-7, 1, 0}, {-8, 1, 0}, {-9, 1, 0})
	refinery := place_test_entity(&world, content, "refinery", {-11, 1, 1})
	if with_pump {
		pump := place_test_fluid_entity(&world, content, "pump", {-8, 1, -2})
		test_fluid_machine(&world, pump).buffers[0] = {fluid = test_fluid(content, "water"), level = 5}
	}
	// The pump's inlet faces -x from (-8, 1, -2).
	lay_pipes(&world, content, {-9, 1, -2})
	join := 120 + phase
	for tick in 0 ..< join + 1200 {
		if tick == join {
			lay_pipes(&world, content, {-9, 1, -1})
		}
		inlet := &pool_get(&world.entities.assemblers, refinery).buffers[0]
		if inlet.level >= 100 {
			inlet.level -= 100
		}
		tick_test_fluids(&world, content, 1)
		if tick >= join {
			received += pool_get(&world.entities.assemblers, refinery).buffers[0].flow_in
		}
	}
	return
}

// A held inlet joined to a line with no tank, at each of the 6 phases of
// the tar pit pump's cadence (a litre every sixth tick, so on most ticks
// no feeder holds litres and the inlet names the line): the crude still
// reaches the refinery as in the control, within one craft.
@(test)
test_a_held_inlet_never_stops_a_tankless_line :: proc(t: ^testing.T) {
	content := make_test_content()
	control := crude_received_after_a_join(content, 0, false)
	testing.expect_value(t, control, 200)
	for phase in 0 ..< 6 {
		received := crude_received_after_a_join(content, phase, true)
		testing.expectf(t, abs(received - control) <= 100, "phase %d: the refinery received %d L, the control %d", phase, received, control)
	}
}

// A powered tar pit pump's line into a tank, 600 L a minute, one litre
// every sixth tick: the pipe's band is drawn on every tick, and its panel
// reads the last full second's 10 L, 600 L/min, on every tick.
@(test)
test_a_slow_line_shows_a_steady_pipe :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_oil_world(content)
	pump := place_test_fluid_entity(&world, content, "tar_pit_pump", {6, 1, -1})
	test_fluid_machine(&world, pump).power.satisfaction = POWER_FULL
	pipe := lay_pipes(&world, content, {5, 1, -1}, {4, 1, -1})[0]
	place_test_fluid_entity(&world, content, "storage_tank", {1, 1, -2})
	tick_test_fluids(&world, content, TEST_TICK_RATE)
	banded, steady := 0, 0
	for _ in 0 ..< 2 * TEST_TICK_RATE {
		tick_test_fluids(&world, content, 1)
		banded += pipe_shows_band(test_pipe(&world, pipe)^) ? 1 : 0
		steady += pipe_litres_last_second(&world.entities.fluid_networks, pipe) * 60 == 600 ? 1 : 0
	}
	testing.expect_value(t, banded, 2 * TEST_TICK_RATE)
	testing.expect_value(t, steady, 2 * TEST_TICK_RATE)
	testing.expect_value(t, format_second_litres_per_minute(pipe_litres_last_second(&world.entities.fluid_networks, pipe)), "600 L/min")
}

// A refinery's gas outlet holding 200 L, a combustion generator's inlet
// holding 100 and an unpowered flare stack on one netlist: the flare gets
// nothing until the generator's inlet is full, then the rest.
@(test)
test_a_flare_takes_only_what_is_left :: proc(t: ^testing.T) {
	content := make_test_content()
	gas := test_fluid(content, "petroleum_gas")
	world, refinery := make_refinery_world(content)
	test_oil_assembler(&world, refinery).buffers[1] = {fluid = gas, level = 200}
	lay_pipes(&world, content, {-1, 1, 2}, {-2, 1, 2}, {-3, 1, 2})
	generator := place_test_fluid_entity(&world, content, "combustion_generator", {-4, 1, 3})
	test_fluid_machine(&world, generator).buffers[0] = {fluid = gas, level = 100}
	flare := place_test_fluid_entity(&world, content, "flare_stack", {-4, 1, 2})
	tick_test_fluids(&world, content, 5)
	testing.expect_value(t, test_fluid_machine(&world, generator).buffers[0].level, 200)
	testing.expect_value(t, test_fluid_machine(&world, flare).buffers[0].level, 0)
	tick_test_fluids(&world, content, 5)
	testing.expect_value(t, test_fluid_machine(&world, flare).buffers[0].level, 100)
	testing.expect_value(t, test_oil_assembler(&world, refinery).buffers[1].level, 0)
}

// A refinery's gas outlet holding 200 L and a powered flare stack on one
// netlist, the gas outlet's pipes running past the flare to x -4.
make_relief_world :: proc(content: Simulation_Content) -> (world: World, refinery, flare: Entity_Handle) {
	world, refinery = make_refinery_world(content)
	test_oil_assembler(&world, refinery).buffers[1] = {fluid = test_fluid(content, "petroleum_gas"), level = 200}
	lay_pipes(&world, content, {-1, 1, 2}, {-2, 1, 2}, {-3, 1, 2}, {-4, 1, 2})
	flare = place_test_fluid_entity(&world, content, "flare_stack", {-2, 1, 3})
	test_fluid_machine(&world, flare).power.satisfaction = POWER_FULL
	return
}

// The flare is a relief valve: beside a tank with 50 L of room it takes
// nothing while the tank has room, the 10 L the tank had no room for back
// up for a tick, and then it takes the leftover. Without a tank it takes
// the leftover at once, and burns only from FLARE_RELIEF_PERCENT full.
@(test)
test_a_flare_opens_only_when_the_tanks_are_full :: proc(t: ^testing.T) {
	content := make_test_content()
	world, refinery, flare := make_relief_world(content)
	tank := place_test_tank(&world, content, {-7, 1, 1}, "petroleum_gas", 24_950)
	tick_test_fluids(&world, content, 3)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 25_000)
	testing.expect_value(t, test_fluid_machine(&world, flare).buffers[0].level, 0)
	testing.expect_value(t, test_oil_assembler(&world, refinery).buffers[1].level, 150)
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, test_fluid_machine(&world, flare).buffers[0].level, 20)
	testing.expect_value(t, test_oil_assembler(&world, refinery).buffers[1].level, 130)

	alone, _, alone_flare := make_relief_world(content)
	records := make_fluid_test_records(content)
	tick_test_fluids_with_statistics(&alone, &records, content, 1)
	testing.expect_value(t, test_fluid_machine(&alone, alone_flare).buffers[0].level, 20)
	tick_test_fluids_with_statistics(&alone, &records, content, 8)
	testing.expect_value(t, test_fluid_machine(&alone, alone_flare).buffers[0].level, 180)
	testing.expect_value(t, test_fluid_machine(&alone, alone_flare).state, Fluid_Machine_State.Idle)
	testing.expect_value(t, records.statistics.flared_litres, 0)
	tick_test_fluids_with_statistics(&alone, &records, content, 1)
	testing.expect_value(t, test_fluid_machine(&alone, alone_flare).state, Fluid_Machine_State.Flaring)
	testing.expect_value(t, records.statistics.flared_litres, 1)
	testing.expect_value(t, test_fluid_machine(&alone, alone_flare).buffers[0].level, 199)
}

// 24 boilers' inlets on one line from a powered offshore pump: 20 L a
// tick shared over 480 L a tick asked rounds to nothing per inlet, and the
// top-up still moves all 20 every tick until every inlet holds 200.
@(test)
test_rounding_never_stalls_a_water_line :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	place_powered_offshore_pump(&world, content, {0, 1, 0})
	boilers: [24]Entity_Handle
	for &boiler, index in boilers {
		x := -3 * i32(index + 1)
		boiler = place_test_fluid_entity(&world, content, "boiler", {x, 1, 1})
		lay_pipes(&world, content, {x, 1, 0}, {x + 1, 1, 0}, {x + 2, 1, 0})
	}
	stalled := 0
	for tick in 1 ..= 240 {
		tick_test_fluids(&world, content, 1)
		held: i32
		for boiler in boilers {
			held += test_fluid_machine(&world, boiler).buffers[0].level
		}
		stalled += held == i32(20 * tick) ? 0 : 1
	}
	testing.expect_value(t, stalled, 0)
	for boiler in boilers {
		testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[0].level, 200)
	}
}

// Chapter 4's line: a powered offshore pump, a boiler with 20 coal and its
// steam piped into a tank. Once running the boiler produces every tick and
// the tank gains its litre a tick.
@(test)
test_a_boiler_line_runs_at_its_rate :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	place_powered_offshore_pump(&world, content, {2, 1, -3})
	lay_pipes(&world, content, {1, 1, -3}, {1, 1, -2}, {1, 1, -1})
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	test_fluid_machine(&world, boiler).slots[BOILER_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 20}
	lay_pipes(&world, content, {1, 1, 2})
	tank := place_test_fluid_entity(&world, content, "storage_tank", {0, 1, 3})
	tick_test_fluids(&world, content, 120)
	before := test_fluid_machine(&world, tank).buffers[0].level
	producing := 0
	for _ in 0 ..< 600 {
		tick_test_fluids(&world, content, 1)
		producing += test_fluid_machine(&world, boiler).state == .Producing ? 1 : 0
	}
	testing.expect_value(t, producing, 600)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level - before, 600)
}

// Assemblers first, then the fluids, as the world ticks them.
tick_oil_line :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		tick_assemblers(world_tick_context(world, records, content, TEST_TICK_RATE))
		tick_fluids(&world.entities, content, TEST_TICK_RATE, &records.statistics)
	}
}

// Chapter 6's line: two powered tar pit pumps piped to a powered refinery,
// its three outlets piped to a tank each. Once running the pumps never
// back up, 2,000 L of crude come in 6,000 ticks and become 20 crafts
// (one either way where the window cuts one), and every litre of each
// fraction is in its tank or its outlet.
@(test)
test_an_oil_line_runs_at_its_pumps_rate :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_oil_world(content)
	records := make_fluid_test_records(content)
	refinery := place_powered_crafting_machine(&world, content, "refinery", {0, 1, 0})
	pumps := [2]Entity_Handle{place_test_fluid_entity(&world, content, "tar_pit_pump", {6, 1, -1}), place_test_fluid_entity(&world, content, "tar_pit_pump", {5, 1, -2})}
	for pump in pumps {
		test_fluid_machine(&world, pump).power.satisfaction = POWER_FULL
	}
	// The crude inlet faces -z from cell (2, 1, 0).
	lay_pipes(&world, content, {2, 1, -1}, {3, 1, -1}, {4, 1, -1}, {5, 1, -1}, {4, 1, -2})
	lay_pipes(&world, content, {-1, 1, 2}, {2, 1, 5}, {5, 1, 2})
	tanks: [3]Entity_Handle
	for origin, index in REFINERY_FRACTION_TANKS {
		tanks[index] = place_test_fluid_entity(&world, content, "storage_tank", origin)
	}
	crude, gas := test_fluid(content, "crude_oil"), test_fluid(content, "petroleum_gas")
	tick_oil_line(&world, &records, content, 600)
	crude_before := fluid_counter(records.statistics.fluids.produced, crude)
	gas_before := fluid_counter(records.statistics.fluids.produced, gas)
	backed_up := 0
	for _ in 0 ..< 6000 {
		tick_oil_line(&world, &records, content, 1)
		for pump in pumps {
			backed_up += test_fluid_machine(&world, pump).state == .Output_Full ? 1 : 0
		}
	}
	testing.expect_value(t, backed_up, 0)
	testing.expect_value(t, fluid_counter(records.statistics.fluids.produced, crude) - crude_before, 2000)
	crafts := (fluid_counter(records.statistics.fluids.produced, gas) - gas_before) / 45
	testing.expectf(t, crafts >= 19 && crafts <= 21, "%d crafts in the window", crafts)
	finished := i32(fluid_counter(records.statistics.fluids.produced, gas) / 45)
	per_craft := [3]i32{45, 30, 25}
	outlets := test_oil_assembler(&world, refinery).buffers
	for tank, index in tanks {
		held := test_fluid_machine(&world, tank).buffers[0].level + outlets[index + 1].level
		testing.expect_value(t, held, finished * per_craft[index])
	}
}

// Two tanks touching each other and one pipe to a boiler's inlet close a
// loop, cut at one chord; every litre stays.
@(test)
test_touching_tanks_close_a_loop_that_carries_nothing :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	first := place_test_tank(&world, content, {0, 1, 0}, "water", 10_000)
	second := place_test_tank(&world, content, {3, 1, 1}, "water", 5000)
	lay_pipes(&world, content, {2, 1, 3})
	// The inlet faces -z from cell (2, 1, 4), onto the pipe.
	boiler := place_test_fluid_entity(&world, content, "boiler", {1, 1, 4})
	networks := &world.entities.fluid_networks
	testing.expect_value(t, len(networks.topology.chords), 1)
	testing.expect_value(t, fluid_netlist_count(networks), 2)
	tick_test_fluids(&world, content, 100)
	inlet := test_fluid_machine(&world, boiler).buffers[0].level
	testing.expect_value(t, inlet, 200)
	testing.expect_value(t, test_fluid_machine(&world, first).buffers[0].level + test_fluid_machine(&world, second).buffers[0].level + inlet, 15_000)
}

@(test)
test_boiler_burns_fuel_and_turns_water_into_steam :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	coal := test_item(content.items, "coal")
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	machine := test_fluid_machine(&world, boiler)
	testing.expect_value(t, machine.slot_count, 1)
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, test_fluid_machine(&world, boiler).state, Fluid_Machine_State.Idle)
	test_fluid_machine(&world, boiler).slots[BOILER_FUEL_SLOT] = Item_Stack{item = coal, count = 2}
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, test_fluid_machine(&world, boiler).state, Fluid_Machine_State.No_Water)
	testing.expect_value(t, test_fluid_machine(&world, boiler).slots[BOILER_FUEL_SLOT].count, 2)
	test_fluid_machine(&world, boiler).buffers[0] = {fluid = test_fluid(content, "water"), level = 200}
	// One second: 60 litres of water become 60 of steam, 1.8 MJ burn.
	tick_test_fluids(&world, content, 60)
	machine = test_fluid_machine(&world, boiler)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Producing)
	testing.expect_value(t, machine.buffers[0].level, 140)
	testing.expect_value(t, machine.buffers[1], Fluid_Buffer{fluid = test_fluid(content, "steam"), level = 60})
	testing.expect_value(t, machine.slots[BOILER_FUEL_SLOT].count, 1)
	testing.expect_value(t, machine.fuel_joules, 4_000_000 - 1_800_000)
	machine.buffers[1].level = 200
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, test_fluid_machine(&world, boiler).state, Fluid_Machine_State.Output_Full)
	testing.expect_value(t, test_fluid_machine(&world, boiler).fuel_joules, 4_000_000 - 1_800_000)
	test_fluid_machine(&world, boiler).buffers[1].level = 0
	test_fluid_machine(&world, boiler).slots[BOILER_FUEL_SLOT] = EMPTY_STACK
	test_fluid_machine(&world, boiler).fuel_joules = 0
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, test_fluid_machine(&world, boiler).state, Fluid_Machine_State.No_Fuel)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[0].level, 140)
}

@(test)
test_boiler_takes_fuel_through_the_transfer_interface :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	coal, plate := test_item(content.items, "coal"), test_item(content.items, "iron_plate")
	testing.expect(t, entity_takes_item_kind(&world.entities, content, boiler, coal))
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, boiler, plate))
	testing.expect_value(t, entity_insert(&world.entities, content, boiler, Item_Stack{item = coal, count = 3}), EMPTY_STACK)
	testing.expect_value(t, test_fluid_machine(&world, boiler).slots[BOILER_FUEL_SLOT].count, 3)
	testing.expect_value(t, entity_extract(&world.entities, content, boiler, NO_ITEM, 1), EMPTY_STACK)
	pipe := lay_pipes(&world, content, {5, 1, 5})[0]
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, pipe, coal))
}

@(test)
test_offshore_pump_fills_a_tank_to_its_capacity :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pump := place_powered_offshore_pump(&world, content, {0, 1, 0})
	pipes := lay_pipes(&world, content, {-1, 1, 0}, {-2, 1, 0}, {-3, 1, 0})
	tank := place_test_fluid_entity(&world, content, "storage_tank", {-6, 1, -1})
	testing.expect_value(t, fluid_netlist_count(&world.entities.fluid_networks), 1)
	for _ in 0 ..< 6000 {
		tick_test_fluids(&world, content, 1)
		testing.expect(t, test_fluid_machine(&world, tank).buffers[0].level <= 25_000)
	}
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 25_000)
	testing.expect_value(t, test_pipe(&world, pipes[2]).buffer.level, 0)
	testing.expect_value(t, test_fluid_machine(&world, pump).buffers[0].level, 200)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Output_Full)
}

// Work item 0140: unpowered, the offshore pump pushes nothing and says
// so; powered, 1200 litres a second (20 a tick); at half satisfaction
// half as much.
@(test)
test_offshore_pump_pumps_only_with_power :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pump := place_test_fluid_entity(&world, content, "offshore_pump", {0, 1, 0})
	lay_pipes(&world, content, {-1, 1, 0}, {-2, 1, 0}, {-3, 1, 0})
	tank := place_test_fluid_entity(&world, content, "storage_tank", {-6, 1, -1})
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Unpowered)
	tick_test_fluids(&world, content, 60)
	testing.expect_value(t, water_litres(&world), 0)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Unpowered)
	test_fluid_machine(&world, pump).power.satisfaction = POWER_FULL
	tick_test_fluids(&world, content, 60)
	testing.expect_value(t, water_litres(&world), 1200)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Producing)
	test_fluid_machine(&world, pump).power.satisfaction = POWER_FULL / 2
	tick_test_fluids(&world, content, 60)
	testing.expect_value(t, water_litres(&world), 1800)
	testing.expect(t, test_fluid_machine(&world, tank).buffers[0].level > 0)
}

// At 990 per mille the pump yields 99 of 100 ticks' litres, at 40 per
// mille 4: the rate times the satisfaction, nothing lost to rounding.
@(test)
test_offshore_pump_yields_its_rate_times_the_satisfaction :: proc(t: ^testing.T) {
	content := make_test_content()
	for sample in ([?][2]i32{{990, 1980}, {40, 80}}) {
		world := make_floor_world(content.blocks, 32)
		pump := place_test_fluid_entity(&world, content, "offshore_pump", {0, 1, 0})
		lay_pipes(&world, content, {-1, 1, 0}, {-2, 1, 0}, {-3, 1, 0})
		place_test_fluid_entity(&world, content, "storage_tank", {-6, 1, -1})
		test_fluid_machine(&world, pump).power.satisfaction = u32(sample[0])
		tick_test_fluids(&world, content, 100)
		testing.expect_value(t, water_litres(&world), sample[1])
		testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Producing)
	}
}

// Every litre of water in pipes and machines.
water_litres :: proc(world: ^World) -> i32 {
	total: i32
	for pipe in world.entities.pipes.entries {
		if pipe.alive && pipe.buffer.level > 0 {
			total += pipe.buffer.level
		}
	}
	for machine in world.entities.fluid_machines.entries {
		for buffer in machine.buffers {
			if machine.alive && buffer.level > 0 {
				total += buffer.level
			}
		}
	}
	return total
}

@(test)
test_offshore_pump_needs_water_in_front :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 2)
	machine := test_machine(content.machines, "offshore_pump")
	testing.expect(t, !placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	world_set_block(&world, {2, 0, 0}, test_block(content.blocks, "water"))
	testing.expect(t, placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	// Turned round, the intake looks at the dry floor.
	testing.expect(t, !placement_at(&world, content, nil, machine, {0, 1, 0}, 2).valid)
	testing.expect_value(t, offshore_pump_intake_cell({0, 1, 0}, content.machines.machines[machine], 1), World_Coordinate{0, 1, 2})
}

@(test)
test_pipes_stand_on_the_ground_or_on_pipes :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	machine := test_machine(content.machines, "pipe")
	testing.expect(t, placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	testing.expect(t, !placement_at(&world, content, nil, machine, {0, 2, 0}, 0).valid)
	lay_pipes(&world, content, {0, 1, 0})
	testing.expect(t, placement_at(&world, content, nil, machine, {0, 2, 0}, 0).valid)
	testing.expect(t, !placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
}

@(test)
test_fluid_networks_rebuild_after_removing_a_middle_pipe :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pipes := lay_pipes(&world, content, {0, 1, 0}, {1, 1, 0}, {2, 1, 0}, {3, 1, 0}, {4, 1, 0})
	networks := &world.entities.fluid_networks
	testing.expect_value(t, fluid_netlist_count(networks), 1)
	testing.expect(t, remove_entity(&world.entities, content.machines, pipes[2]))
	testing.expect_value(t, fluid_netlist_count(networks), 2)
	testing.expect(t, fluid_netlist_of(networks, pipes[0], -1) != fluid_netlist_of(networks, pipes[4], -1))
	testing.expect_value(t, fluid_netlist_of(networks, pipes[2], -1), -1)
	lay_pipes(&world, content, {2, 1, 0})
	testing.expect_value(t, fluid_netlist_count(networks), 1)
}

@(test)
test_picking_up_a_boiler_returns_its_fuel :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	test_fluid_machine(&world, boiler).slots[BOILER_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 5}
	test_fluid_machine(&world, boiler).buffers[0] = {fluid = test_fluid(content, "water"), level = 100}
	player := make_test_player(content.blocks, {10, 1, 10})
	testing.expect(t, pick_up_entity(&world, &records.statistics, content, &player, boiler, 0))
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "coal")), 5)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "boiler")), 1)
	testing.expect_value(t, len(world.entities.frames.occupants), 0)
	testing.expect_value(t, len(world.entities.fluid_networks.nodes), 0)
}

// Offshore pump, three pipes, the boiler, a steam column and a tank on a
// ledge above.
build_steam_plant :: proc(world: ^World, content: Simulation_Content) -> (boiler, tank: Entity_Handle) {
	place_powered_offshore_pump(world, content, {2, 1, -3})
	lay_pipes(world, content, {1, 1, -3}, {1, 1, -2}, {1, 1, -1})
	boiler = place_test_fluid_entity(world, content, "boiler", {0, 1, 0})
	lay_pipes(world, content, {1, 1, 2}, {1, 2, 2}, {1, 3, 2})
	tank = place_test_fluid_entity(world, content, "storage_tank", {0, 4, 1})
	test_fluid_machine(world, boiler).slots[BOILER_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 20}
	return
}

steam_litres :: proc(world: ^World, content: Simulation_Content) -> i32 {
	steam := test_fluid(content, "steam")
	total: i32
	for pipe in world.entities.pipes.entries {
		if pipe.alive && pipe.buffer.fluid == steam {
			total += pipe.buffer.level
		}
	}
	for machine in world.entities.fluid_machines.entries {
		for buffer in machine.buffers {
			if machine.alive && buffer.fluid == steam {
				total += buffer.level
			}
		}
	}
	return total
}

// Two identical plants run 1200 ticks into the same state, and every litre
// of steam is paid for with exactly one tick of fuel.
@(test)
test_fluid_simulation_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_floor_world(content.blocks, 32), make_floor_world(content.blocks, 32)}
	boiler, tank: Entity_Handle
	for &world in worlds {
		boiler, tank = build_steam_plant(&world, content)
		tick_test_fluids(&world, content, 1200)
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	testing.expect_value(t, len(first.pipes.entries), len(second.pipes.entries))
	for pipe, index in first.pipes.entries {
		testing.expect_value(t, pipe.buffer, second.pipes.entries[index].buffer)
	}
	for machine, index in first.fluid_machines.entries {
		other := second.fluid_machines.entries[index]
		testing.expect_value(t, machine.buffers, other.buffers)
		testing.expect_value(t, machine.fuel_joules, other.fuel_joules)
		testing.expect_value(t, machine.state, other.state)
	}
	world := &worlds[0]
	testing.expect(t, test_fluid_machine(world, tank).buffers[0].level > 0)
	testing.expect_value(t, test_fluid_machine(world, tank).buffers[0].fluid, test_fluid(content, "steam"))
	burner := test_fluid_machine(world, boiler)
	burned := i64(20 - burner.slots[BOILER_FUEL_SLOT].count) * 4_000_000 - i64(burner.fuel_joules)
	testing.expect_value(t, i64(steam_litres(world, content)), burned / 30_000)
	testing.expect_value(t, burned % 30_000, 0)
}

// Ticks until the tank holds at least 99 percent, or -1.
ticks_to_fill_tank :: proc(world: ^World, content: Simulation_Content, tank: Entity_Handle, maximum_ticks: int) -> int {
	for tick in 1 ..= maximum_ticks {
		tick_test_fluids(world, content, 1)
		if test_fluid_machine(world, tank).buffers[0].level >= 24_750 {
			return tick
		}
	}
	return -1
}

// An offshore pump, three pipes and a tank towards -x, and the mirror
// image towards +x, fill in the same number of ticks at the pump's 20
// litres per tick.
@(test)
test_fluid_throughput_does_not_depend_on_direction :: proc(t: ^testing.T) {
	content := make_test_content()
	towards_negative := make_floor_world(content.blocks, 32)
	place_powered_offshore_pump(&towards_negative, content, {0, 1, 0})
	lay_pipes(&towards_negative, content, {-1, 1, 0}, {-2, 1, 0}, {-3, 1, 0})
	negative_tank := place_test_fluid_entity(&towards_negative, content, "storage_tank", {-6, 1, -1})
	towards_positive := make_floor_world(content.blocks, 32)
	place_powered_offshore_pump(&towards_positive, content, {0, 1, 0}, 2)
	lay_pipes(&towards_positive, content, {2, 1, 0}, {3, 1, 0}, {4, 1, 0})
	positive_tank := place_test_fluid_entity(&towards_positive, content, "storage_tank", {5, 1, -1})
	negative_ticks := ticks_to_fill_tank(&towards_negative, content, negative_tank, 3000)
	positive_ticks := ticks_to_fill_tank(&towards_positive, content, positive_tank, 3000)
	testing.expect_value(t, negative_ticks, positive_ticks)
	// 24,750 L at 20 L per tick from the first tick, since the pipes hold
	// nothing (0356).
	testing.expect_value(t, negative_ticks, 1238)
}

// Work item 0082: a pipe placed over ground cover replaces it.
@(test)
test_pipe_placed_over_ground_cover_replaces_it :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	set_blocks(&world, test_block(content.blocks, "grass_tuft"), {0, 1, 0})
	placement := placement_at(&world, content, nil, test_machine(content.machines, "pipe"), {0, 1, 0}, 0)
	testing.expect(t, placement.valid)
	testing.expect(t, placement.clears_cover)
	commit_placement(&world, content.machines, placement)
	testing.expect_value(t, world_get_block(&world, {0, 1, 0}), AIR_BLOCK)
	testing.expect_value(t, entity_at(&world.entities, {0, 1, 0}).kind, Entity_Kind.Pipe)
}
