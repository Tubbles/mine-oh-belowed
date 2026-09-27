package game

import "core:slice"
import "core:testing"

// The combustion generator (work item 0032). Worlds stand on the stone
// floor of make_floor_world (top at y 1) with fluid statistics
// (make_oil_world). A small pole at the origin powers x and z from -2 to
// 2; the generator stands at (1, 1, 1) with its gas port facing -z.

COMBUSTION_TEST_POLE :: World_Coordinate{0, 1, 0}
COMBUSTION_TEST_ORIGIN :: World_Coordinate{1, 1, 1}

// A generator, its pole and two lamps asking 166 J a tick together.
make_combustion_world :: proc(content: Simulation_Content) -> (world: World, generator: Entity_Handle) {
	world = make_oil_world(content)
	generator = place_test_entity(&world, content, "combustion_generator", COMBUSTION_TEST_ORIGIN)
	place_test_entity(&world, content, "small_pole", COMBUSTION_TEST_POLE)
	place_test_entity(&world, content, "lamp", {0, 1, -2})
	place_test_entity(&world, content, "lamp", {2, 1, -1})
	return
}

set_generator_gas :: proc(world: ^World, content: Simulation_Content, generator: Entity_Handle, fluid: string, litres: i32) {
	test_fluid_machine(world, generator).buffers[0] = {fluid = test_fluid(content, fluid), level = litres}
}

@(test)
test_combustion_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := content.machines.machines[test_machine(content.machines, "combustion_generator")]
	testing.expect_value(t, machine.kind, Machine_Kind.Combustion_Generator)
	testing.expect_value(t, machine.footprint, [3]i32{3, 2, 2})
	testing.expect_value(t, machine.slot_count, 1)
	testing.expect(t, machine_is_generator(machine))
	testing.expect_value(t, electric_joules_per_tick(machine.electric_output_watts, TEST_TICK_RATE), 10_000)
	testing.expect_value(t, machine.fluid_port_count, 1)
	testing.expect_value(t, machine.fluid_ports[0].phase_filter, Fluid_Phase_Filter.Burnable_Gas)
	testing.expect_value(t, machine.fluid_ports[0].direction, Fluid_Port_Direction.Input)
	testing.expect_value(t, content.fluids.fluids[test_fluid(content, "petroleum_gas")].fuel_kilojoules_per_litre, 200)
	testing.expect_value(t, content.fluids.fluids[test_fluid(content, "wood_gas")].fuel_kilojoules_per_litre, 100)
	recipe := content.recipes.recipes[test_recipe(content.recipes, "combustion_generator")]
	testing.expect_value(t, len(recipe.inputs), 4)
	// Inserters feed its fuel slot and nothing else.
	world, generator := make_combustion_world(content)
	coal := test_item(content.items, "coal")
	slot, accepted := entity_accepts(&world.entities, content, generator, coal)
	testing.expect(t, accepted && slot == COMBUSTION_FUEL_SLOT)
	_, accepted = entity_accepts(&world.entities, content, generator, test_item(content.items, "iron_plate"))
	testing.expect(t, !accepted)
}

// Petroleum gas: whole litres of 200 kJ, drawn only as the lamps need
// them, and nothing produced that was not consumed.
@(test)
test_combustion_generator_burns_gas_for_delivered_energy :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	gas := test_fluid(content, "petroleum_gas")
	set_generator_gas(&world, content, generator, "petroleum_gas", 50)
	tick_test_entities(&world, content, 3000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, world.statistics.energy_produced_joules, 166 * 3000)
	testing.expect_value(t, world.statistics.energy_consumed_joules, world.statistics.energy_produced_joules)
	testing.expect_value(t, machine.buffers[0].level, 47)
	testing.expect_value(t, fluid_counter(world.statistics.fluids.consumed, gas), 3)
	testing.expect_value(t, world.statistics.generator_gas_litres, 3)
	testing.expect_value(t, hint_counter_value(world.statistics, Hint{counter = .Generator_Gas_Litres}), 3)
	testing.expect_value(t, world.statistics.energy_produced_joules + u64(machine.fuel_joules), 3 * 200_000)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Generating)
	testing.expect_value(t, machine.generated_joules, 166)
	testing.expect_value(t, world.statistics.fuel_burned, 0)
}

// Wood gas is worth half as much: 1 MJ per 10 litres.
@(test)
test_combustion_generator_burns_wood_gas :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	set_generator_gas(&world, content, generator, "wood_gas", 50)
	tick_test_entities(&world, content, 3000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.buffers[0].level, 45)
	testing.expect_value(t, fluid_counter(world.statistics.fluids.consumed, test_fluid(content, "wood_gas")), 5)
	testing.expect_value(t, world.statistics.energy_produced_joules + u64(machine.fuel_joules), 5 * 100_000)
}

// Solid fuel: a coal is lit whole (4 MJ) and counted burned once.
@(test)
test_combustion_generator_burns_solid_fuel :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	coal := test_item(content.items, "coal")
	test_fluid_machine(&world, generator).slots[COMBUSTION_FUEL_SLOT] = {coal, 3}
	tick_test_entities(&world, content, 1000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT], Item_Stack{coal, 2})
	testing.expect_value(t, world.statistics.fuel_burned, 1)
	testing.expect_value(t, item_counter(world.statistics.consumed, coal), 1)
	testing.expect_value(t, u64(machine.fuel_joules), 4_000_000 - world.statistics.energy_produced_joules)
	testing.expect_value(t, world.statistics.energy_produced_joules, 166 * 1000)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Generating)
}

// With gas in the port the coal waits; once the gas is gone the coal
// takes over without a gap.
@(test)
test_combustion_generator_prefers_gas :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	coal := test_item(content.items, "coal")
	test_fluid_machine(&world, generator).slots[COMBUSTION_FUEL_SLOT] = {coal, 5}
	set_generator_gas(&world, content, generator, "petroleum_gas", 2)
	tick_test_entities(&world, content, 2000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT].count, 5)
	testing.expect_value(t, machine.buffers[0].level, 0)
	testing.expect_value(t, world.statistics.brownout_ticks, 0)
	tick_test_entities(&world, content, 1000)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT].count, 4)
	testing.expect_value(t, world.statistics.brownout_ticks, 0)
	testing.expect_value(t, world.statistics.energy_produced_joules, 166 * 3000)
	testing.expect_value(t, world.statistics.energy_produced_joules + u64(machine.fuel_joules), 2 * 200_000 + 4_000_000)
	// Nothing left to burn: no fuel while the lamps ask.
	machine.slots[COMBUSTION_FUEL_SLOT] = EMPTY_STACK
	machine.fuel_joules = 0
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, machine.state, Fluid_Machine_State.No_Fuel)
}

// The gas port admits only gases with a fuel value: steam in a pipe at
// the port closes it (one mixing refusal) and stays in the pipe, while
// petroleum gas flows in.
@(test)
test_combustion_generator_port_refuses_steam :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	pipe := lay_pipes(&world, content, {2, 1, 0})[0]
	test_pipe(&world, pipe).buffer = {fluid = test_fluid(content, "steam"), level = 100}
	tick_test_fluids_with_statistics(&world, content, 30)
	testing.expect_value(t, test_fluid_machine(&world, generator).buffers[0].level, 0)
	testing.expect(t, test_fluid_machine(&world, generator).closed[0])
	testing.expect_value(t, test_pipe(&world, pipe).buffer.level, 100)
	testing.expect_value(t, world.statistics.mixing_refusals, 1)
	// Emptied, the network forgets the steam and takes the wood gas.
	test_pipe(&world, pipe).buffer = EMPTY_FLUID_BUFFER
	tick_test_fluids_with_statistics(&world, content, 1)
	test_pipe(&world, pipe).buffer = {fluid = test_fluid(content, "wood_gas"), level = 100}
	tick_test_fluids_with_statistics(&world, content, 30)
	testing.expect(t, !test_fluid_machine(&world, generator).closed[0])
	testing.expect(t, test_fluid_machine(&world, generator).buffers[0].level > 0)
	testing.expect_value(t, world.statistics.mixing_refusals, 1)
}

// A gas that does not burn offers nothing, and the slot still works, even
// when it was put straight into the buffer past the port filter.
@(test)
test_combustion_generator_ignores_gas_without_fuel_value :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	set_generator_gas(&world, content, generator, "steam", 100)
	tick_test_entities(&world, content, 1)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.state, Fluid_Machine_State.No_Fuel)
	testing.expect_value(t, machine.buffers[0].level, 100)
	machine.slots[COMBUSTION_FUEL_SLOT] = {test_item(content.items, "plank"), 1}
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Generating)
	testing.expect_value(t, machine.buffers[0].level, 100)
}

// A steam engine offering 60 J and a combustion generator offering 40 J
// against two lamps asking 166 J: 602 per mille, 98 J delivered, shared
// 60 to 40 rounded down, and the joule left over goes to the generator,
// first in pool order.
@(test)
test_brownout_is_shared_between_steam_and_combustion :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	engine := place_test_entity(&world, content, "steam_engine", {-3, 1, -2})
	networks := &world.entities.electric_networks
	testing.expect_value(t, entity_network(networks, engine), entity_network(networks, generator))
	for _ in 0 ..< 10 {
		test_fluid_machine(&world, engine).fuel_joules = 60
		test_fluid_machine(&world, generator).fuel_joules = 40
		tick_test_entities(&world, content, 1)
	}
	network := networks.networks[0]
	testing.expect_value(t, network.supply, 100)
	testing.expect_value(t, network.demand, 166)
	testing.expect_value(t, network.satisfaction, 602)
	testing.expect_value(t, network.delivered, 98)
	testing.expect_value(t, test_fluid_machine(&world, engine).generated_joules, 58)
	testing.expect_value(t, test_fluid_machine(&world, generator).generated_joules, 40)
	testing.expect_value(t, test_fluid_machine(&world, generator).state, Fluid_Machine_State.Generating)
	testing.expect_value(t, world.statistics.energy_produced_joules, 98 * 10)
	testing.expect_value(t, world.statistics.energy_consumed_joules, 98 * 10)
	testing.expect_value(t, world.statistics.brownout_ticks, 10)
	// The overview groups the generators by type with their output.
	groups := largest_participant_groups(networks.participants[:], 0, true, POWER_GENERATOR_TYPE_COUNT)
	testing.expect_value(t, len(groups), 2)
	testing.expect_value(t, groups[0], Participant_Group{machine = test_machine(content.machines, "steam_engine"), count = 1, joules = 58})
	testing.expect_value(t, groups[1], Participant_Group{machine = test_machine(content.machines, "combustion_generator"), count = 1, joules = 40})
}

// combustion_power waits for oil processing; logistics science (science
// pack 2 is made from plastic) waits for plastics.
@(test)
test_combustion_and_logistics_science_are_gated :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	combustion := test_technology(technologies, "combustion_power")
	logistics_science := test_technology(technologies, "logistics_science")
	testing.expect_value(t, technologies.technologies[combustion].pack_count, 75)
	testing.expect_value(t, technologies.technologies[combustion].milliseconds_per_pack, 30_000)
	for id in ([?]string{"automation", "logistics", "steel_processing", "ore_processing"}) {
		mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, id))
	}
	testing.expect_value(t, technology_status(technologies, test.unlocks, combustion), Technology_Status.Locked)
	testing.expect_value(t, technology_status(technologies, test.unlocks, logistics_science), Technology_Status.Locked)
	mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, "oil_processing"))
	testing.expect_value(t, technology_status(technologies, test.unlocks, combustion), Technology_Status.Available)
	testing.expect_value(t, technology_status(technologies, test.unlocks, logistics_science), Technology_Status.Locked)
	recipe := test_recipe(test.recipes, "combustion_generator")
	testing.expect(t, !recipe_is_available(test.unlocks, recipe))
	research: Research_State
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, combustion), Research_Refusal.None)
	mark_technology_researched(&test.unlocks, test.recipes, combustion)
	testing.expect(t, recipe_is_available(test.unlocks, recipe))
	mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, "plastics"))
	testing.expect_value(t, technology_status(technologies, test.unlocks, logistics_science), Technology_Status.Available)
	testing.expect(t, slice.contains(technologies.technologies[logistics_science].prerequisites, test_technology(technologies, "plastics")))
}

// An electric drill on an iron vein dropping into a chest, and a wood
// gasifier whose gas runs through one pipe into a combustion generator
// that powers both. 10 L of wood gas in the generator bridge the
// gasifier's first craft.
build_combustion_plant :: proc(world: ^World, content: Simulation_Content) -> (generator, chest: Entity_Handle) {
	vein := add_test_vein(world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	drill := place_test_entity(world, content, "electric_mining_drill", {0, 1, 0})
	test_drill(world, drill).vein = vein
	chest = place_test_entity(world, content, "iron_chest", {3, 1, 1})
	place_test_entity(world, content, "small_pole", {4, 1, 3})
	gasifier := place_test_entity(world, content, "wood_gasifier", {6, 1, 1})
	pool_get(&world.entities.assemblers, gasifier).slots[0] = {test_item(content.items, "log"), 40}
	lay_pipes(world, content, {6, 1, 3})
	generator = place_test_entity(world, content, "combustion_generator", {5, 1, 4})
	set_generator_gas(world, content, generator, "wood_gas", 10)
	return
}

@(test)
test_combustion_simulation_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_oil_world(content), make_oil_world(content)}
	generator, chest: Entity_Handle
	for &world in worlds {
		generator, chest = build_combustion_plant(&world, content)
		tick_test_entities(&world, content, 1200)
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	for machine, index in first.fluid_machines.entries {
		testing.expect_value(t, machine, second.fluid_machines.entries[index])
	}
	for machine, index in first.assemblers.entries {
		other := second.assemblers.entries[index]
		testing.expect_value(t, machine.buffers, other.buffers)
		testing.expect_value(t, machine.slots, other.slots)
		testing.expect_value(t, machine.progress_ticks, other.progress_ticks)
	}
	for drill, index in first.drills.entries {
		testing.expect_value(t, drill, second.drills.entries[index])
	}
	for pipe, index in first.pipes.entries {
		testing.expect_value(t, pipe.buffer, second.pipes.entries[index].buffer)
	}
	testing.expect_value(t, worlds[0].statistics.energy_produced_joules, worlds[1].statistics.energy_produced_joules)
	// The plant runs on its own gas: more burned than the 10 L seed, the
	// energy all accounted for, ore mined.
	world := &worlds[0]
	statistics := world.statistics
	wood_gas := test_fluid(content, "wood_gas")
	burned := fluid_counter(statistics.fluids.consumed, wood_gas)
	testing.expectf(t, burned > 10, "wood gas burned %d", burned)
	testing.expect(t, fluid_counter(statistics.fluids.produced, wood_gas) > 0)
	testing.expect_value(t, statistics.energy_produced_joules, statistics.energy_consumed_joules)
	testing.expect_value(t, burned * 100_000, statistics.energy_produced_joules + u64(test_fluid_machine(world, generator).fuel_joules))
	testing.expect_value(t, len(first.electric_networks.networks), 1)
	testing.expect_value(t, statistics.unpowered_machines, 0)
	testing.expect(t, chest_total(world, chest) > 0)
}
