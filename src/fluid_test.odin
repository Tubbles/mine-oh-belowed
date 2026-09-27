package game

import "core:testing"

// Fluid worlds stand on the stone floor of make_floor_world (top at y 1).

place_test_fluid_entity :: proc(world: ^World, content: Simulation_Content, id: string, origin: World_Coordinate, rotation: u8 = 0) -> Entity_Handle {
	return add_entity(&world.entities, content.machines, test_machine(content.machines, id), origin, rotation)
}

lay_pipes :: proc(world: ^World, content: Simulation_Content, cells: ..World_Coordinate) -> []Entity_Handle {
	handles := make([]Entity_Handle, len(cells), context.temp_allocator)
	for cell, index in cells {
		handles[index] = place_test_fluid_entity(world, content, "pipe", cell)
	}
	return handles
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

pipe_levels :: proc(world: ^World, pipes: []Entity_Handle) -> []i32 {
	levels := make([]i32, len(pipes), context.temp_allocator)
	for pipe, index in pipes {
		levels[index] = test_pipe(world, pipe).buffer.level
	}
	return levels
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
	testing.expect_value(t, pipe.buffer_litres, 100)
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

@(test)
test_two_pipes_balance_to_equal_levels :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pipes := lay_pipes(&world, content, {0, 1, 0}, {1, 1, 0})
	testing.expect_value(t, len(world.entities.fluid_networks.networks), 1)
	test_pipe(&world, pipes[0]).buffer = {fluid = test_fluid(content, "water"), level = 100}
	// Half the difference, at most 20 litres per tick: 80 20, 60 40, 50 50.
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, pipe_levels(&world, pipes)[1], 20)
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, pipe_levels(&world, pipes)[1], 40)
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, pipe_levels(&world, pipes)[0], 50)
	testing.expect_value(t, pipe_levels(&world, pipes)[1], 50)
	testing.expect_value(t, test_pipe(&world, pipes[1]).buffer.fluid, test_fluid(content, "water"))
	tick_test_fluids(&world, content, 10)
	testing.expect_value(t, pipe_levels(&world, pipes)[0], 50)
	testing.expect_value(t, test_pipe(&world, pipes[0]).buffer.flow_out, 0)
}

@(test)
test_flow_is_limited_per_connection_and_tick :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	tank := place_test_fluid_entity(&world, content, "storage_tank", {0, 1, 0})
	pipes := lay_pipes(&world, content, {3, 1, 1}, {4, 1, 1})
	test_fluid_machine(&world, tank).buffers[0] = {fluid = test_fluid(content, "water"), level = 25_000}
	tick_test_fluids(&world, content, 1)
	// 20 litres into the first pipe, which then hands half on in the
	// same tick, since connections run in coordinate order.
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 24_980)
	testing.expect_value(t, pipe_levels(&world, pipes)[0], 10)
	testing.expect_value(t, pipe_levels(&world, pipes)[1], 10)
	testing.expect_value(t, test_pipe(&world, pipes[0]).buffer.flow_in, 20)
	testing.expect_value(t, test_pipe(&world, pipes[0]).buffer.flow_out, 10)
	tick_test_fluids(&world, content, 1)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 24_960)
	testing.expect_value(t, pipe_levels(&world, pipes)[0], 20)
	testing.expect_value(t, pipe_levels(&world, pipes)[1], 20)
}

@(test)
test_a_port_refuses_to_mix_fluids :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	water, steam := test_fluid(content, "water"), test_fluid(content, "steam")
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	// The steam output faces +z from cell (1, 1, 1).
	pipes := lay_pipes(&world, content, {1, 1, 2}, {1, 1, 3})
	for pipe in pipes {
		test_pipe(&world, pipe).buffer = {fluid = water, level = 20}
	}
	rebuild_fluid_networks(&world.entities, content.machines)
	testing.expect_value(t, len(world.entities.fluid_networks.networks), 2)
	test_fluid_machine(&world, boiler).buffers[1] = {fluid = steam, level = 200}
	tick_test_fluids(&world, content, 5)
	testing.expect_value(t, pipe_levels(&world, pipes)[0], 20)
	testing.expect_value(t, test_pipe(&world, pipes[0]).buffer.fluid, water)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[1].level, 200)
	testing.expect(t, test_fluid_machine(&world, boiler).closed[1])
	// Once the water is gone the network takes the steam.
	for pipe in pipes {
		test_pipe(&world, pipe).buffer = EMPTY_FLUID_BUFFER
	}
	tick_test_fluids(&world, content, 1)
	testing.expect(t, test_fluid_machine(&world, boiler).closed[1])
	tick_test_fluids(&world, content, 1)
	testing.expect(t, !test_fluid_machine(&world, boiler).closed[1])
	testing.expect_value(t, test_pipe(&world, pipes[0]).buffer.fluid, steam)
	testing.expect_value(t, pipe_levels(&world, pipes)[0] + pipe_levels(&world, pipes)[1], 20)
	testing.expect_value(t, test_fluid_machine(&world, boiler).buffers[1].level, 180)
}

@(test)
test_gravity_holds_water_but_not_steam :: proc(t: ^testing.T) {
	content := make_test_content()
	for id in ([?]string{"water", "steam"}) {
		world := make_floor_world(content.blocks, 32)
		pipes := lay_pipes(&world, content, {0, 1, 0}, {0, 2, 0})
		test_pipe(&world, pipes[0]).buffer = {fluid = test_fluid(content, id), level = 100}
		tick_test_fluids(&world, content, 10)
		upper := id == "water" ? i32(0) : 50
		testing.expect_value(t, pipe_levels(&world, pipes)[1], upper)
		testing.expect_value(t, pipe_levels(&world, pipes)[0], 100 - upper)
	}
	// Down is always fine: the upper pipe drains to half into the lower.
	world := make_floor_world(content.blocks, 32)
	pipes := lay_pipes(&world, content, {0, 1, 0}, {0, 2, 0})
	test_pipe(&world, pipes[1]).buffer = {fluid = test_fluid(content, "water"), level = 100}
	tick_test_fluids(&world, content, 10)
	testing.expect_value(t, pipe_levels(&world, pipes)[0], 50)
}

// Water beside the pump's input, a column of pipes rising from its output.
make_pump_world :: proc(content: Simulation_Content) -> (world: World, pump: Entity_Handle, source: Entity_Handle, column: []Entity_Handle) {
	world = make_floor_world(content.blocks, 32)
	pump = place_test_fluid_entity(&world, content, "pump", {0, 1, 0})
	source = lay_pipes(&world, content, {-1, 1, 0})[0]
	column = lay_pipes(&world, content, {2, 1, 0}, {2, 2, 0}, {2, 3, 0})
	test_pipe(&world, source).buffer = {fluid = test_fluid(content, "water"), level = 100}
	return
}

fluid_machine_litres :: proc(world: ^World, handle: Entity_Handle) -> i32 {
	total: i32
	for buffer in test_fluid_machine(world, handle).buffers {
		total += buffer.level
	}
	return total
}

@(test)
test_pump_moves_water_uphill_only_with_power :: proc(t: ^testing.T) {
	content := make_test_content()
	world, pump, source, column := make_pump_world(content)
	tick_test_fluids(&world, content, 200)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Unpowered)
	testing.expect_value(t, pipe_levels(&world, column)[2], 0)
	testing.expect_value(t, test_fluid_machine(&world, pump).buffers[1].level, 0)
	world, pump, source, column = make_pump_world(content)
	test_fluid_machine(&world, pump).powered = true
	tick_test_fluids(&world, content, 200)
	levels := pipe_levels(&world, column)
	testing.expect(t, levels[2] > 0)
	// Nothing is lost or made on the way.
	testing.expect_value(t, levels[0] + levels[1] + levels[2] + fluid_machine_litres(&world, pump) + test_pipe(&world, source).buffer.level, 100)
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
	pump := place_test_fluid_entity(&world, content, "offshore_pump", {0, 1, 0})
	pipes := lay_pipes(&world, content, {-1, 1, 0}, {-2, 1, 0}, {-3, 1, 0})
	tank := place_test_fluid_entity(&world, content, "storage_tank", {-6, 1, -1})
	testing.expect_value(t, len(world.entities.fluid_networks.networks), 1)
	for _ in 0 ..< 6000 {
		tick_test_fluids(&world, content, 1)
		testing.expect(t, test_fluid_machine(&world, tank).buffers[0].level <= 25_000)
	}
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].level, 25_000)
	testing.expect_value(t, pipe_levels(&world, pipes)[2], 100)
	testing.expect_value(t, test_fluid_machine(&world, pump).buffers[0].level, 200)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Output_Full)
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
	water := test_fluid(content, "water")
	pipes := lay_pipes(&world, content, {0, 1, 0}, {1, 1, 0}, {2, 1, 0}, {3, 1, 0}, {4, 1, 0})
	testing.expect_value(t, len(world.entities.fluid_networks.networks), 1)
	testing.expect_value(t, len(world.entities.fluid_networks.connections), 4)
	for pipe in pipes {
		test_pipe(&world, pipe).buffer = {fluid = water, level = 40}
	}
	testing.expect(t, remove_entity(&world.entities, content.machines, pipes[2]))
	networks := &world.entities.fluid_networks
	testing.expect_value(t, len(networks.networks), 2)
	testing.expect_value(t, len(networks.connections), 2)
	testing.expect(t, fluid_network_of(networks, pipes[0], -1) != fluid_network_of(networks, pipes[4], -1))
	testing.expect_value(t, networks.networks[0].fluid, water)
	testing.expect_value(t, pipe_levels(&world, pipes[3:])[0], 40)
	lay_pipes(&world, content, {2, 1, 0})
	testing.expect_value(t, len(world.entities.fluid_networks.networks), 1)
}

@(test)
test_picking_up_a_boiler_returns_its_fuel :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	boiler := place_test_fluid_entity(&world, content, "boiler", {0, 1, 0})
	test_fluid_machine(&world, boiler).slots[BOILER_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 5}
	test_fluid_machine(&world, boiler).buffers[0] = {fluid = test_fluid(content, "water"), level = 100}
	player := make_test_player(content.blocks, {10, 1, 10})
	testing.expect(t, pick_up_entity(&world, content, &player, boiler))
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "coal")), 5)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "boiler")), 1)
	testing.expect_value(t, len(world.entities.cells), 0)
	testing.expect_value(t, len(world.entities.fluid_networks.segments), 0)
}

// Offshore pump, three pipes, the boiler, a steam column and a tank on a
// ledge above.
build_steam_plant :: proc(world: ^World, content: Simulation_Content) -> (boiler, tank: Entity_Handle) {
	place_test_fluid_entity(world, content, "offshore_pump", {2, 1, -3})
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
