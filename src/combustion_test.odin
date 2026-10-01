package game

import "core:fmt"
import "core:slice"
import "core:strings"
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
	testing.expect_value(t, machine.fuel_efficiency_percent, 100)
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
	records := make_fluid_test_records(content)
	gas := test_fluid(content, "petroleum_gas")
	set_generator_gas(&world, content, generator, "petroleum_gas", 50)
	tick_test_entities(&world, &records, content, 3000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, records.statistics.energy_produced_joules, 166 * 3000)
	testing.expect_value(t, records.statistics.energy_consumed_joules, records.statistics.energy_produced_joules)
	testing.expect_value(t, machine.buffers[0].level, 47)
	testing.expect_value(t, fluid_counter(records.statistics.fluids.consumed, gas), 3)
	testing.expect_value(t, records.statistics.generator_gas_litres, 3)
	testing.expect_value(t, hint_counter_value(records.statistics, Hint{counter = .Generator_Gas_Litres}), 3)
	testing.expect_value(t, records.statistics.energy_produced_joules + u64(machine.fuel_joules), 3 * 200_000)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Generating)
	testing.expect_value(t, machine.generated_joules, 166)
	testing.expect_value(t, records.statistics.fuel_burned, 0)
}

// Wood gas is worth half as much: 1 MJ per 10 litres.
@(test)
test_combustion_generator_burns_wood_gas :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	records := make_fluid_test_records(content)
	set_generator_gas(&world, content, generator, "wood_gas", 50)
	tick_test_entities(&world, &records, content, 3000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.buffers[0].level, 45)
	testing.expect_value(t, fluid_counter(records.statistics.fluids.consumed, test_fluid(content, "wood_gas")), 5)
	testing.expect_value(t, records.statistics.energy_produced_joules + u64(machine.fuel_joules), 5 * 100_000)
}

// Solid fuel: a coal is lit whole (4 MJ) and counted burned once.
@(test)
test_combustion_generator_burns_solid_fuel :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	records := make_fluid_test_records(content)
	coal := test_item(content.items, "coal")
	test_fluid_machine(&world, generator).slots[COMBUSTION_FUEL_SLOT] = {coal, 3}
	tick_test_entities(&world, &records, content, 1000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT], Item_Stack{coal, 2})
	testing.expect_value(t, records.statistics.fuel_burned, 1)
	testing.expect_value(t, item_counter(records.statistics.consumed, coal), 1)
	testing.expect_value(t, u64(machine.fuel_joules), 4_000_000 - records.statistics.energy_produced_joules)
	testing.expect_value(t, records.statistics.energy_produced_joules, 166 * 1000)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Generating)
}

// With gas in the port the coal waits; once the gas is gone the coal
// takes over without a gap.
@(test)
test_combustion_generator_prefers_gas :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	records := make_fluid_test_records(content)
	coal := test_item(content.items, "coal")
	test_fluid_machine(&world, generator).slots[COMBUSTION_FUEL_SLOT] = {coal, 5}
	set_generator_gas(&world, content, generator, "petroleum_gas", 2)
	tick_test_entities(&world, &records, content, 2000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT].count, 5)
	testing.expect_value(t, machine.buffers[0].level, 0)
	testing.expect_value(t, records.statistics.brownout_ticks, 0)
	tick_test_entities(&world, &records, content, 1000)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT].count, 4)
	testing.expect_value(t, records.statistics.brownout_ticks, 0)
	testing.expect_value(t, records.statistics.energy_produced_joules, 166 * 3000)
	testing.expect_value(t, records.statistics.energy_produced_joules + u64(machine.fuel_joules), 2 * 200_000 + 4_000_000)
	// Nothing left to burn: no fuel while the lamps ask.
	machine.slots[COMBUSTION_FUEL_SLOT] = EMPTY_STACK
	machine.fuel_joules = 0
	tick_test_entities(&world, &records, content, 1)
	testing.expect_value(t, machine.state, Fluid_Machine_State.No_Fuel)
}

// The gas port admits only gases with a fuel value: steam in a pipe at
// the port closes it (one mixing refusal) and stays in the pipe, while
// petroleum gas flows in.
@(test)
test_combustion_generator_port_refuses_steam :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	records := make_fluid_test_records(content)
	pipe := lay_pipes(&world, content, {2, 1, 0})[0]
	test_pipe(&world, pipe).buffer = {fluid = test_fluid(content, "steam"), level = 100}
	tick_test_fluids_with_statistics(&world, &records, content, 30)
	testing.expect_value(t, test_fluid_machine(&world, generator).buffers[0].level, 0)
	testing.expect(t, test_fluid_machine(&world, generator).closed[0])
	testing.expect_value(t, test_pipe(&world, pipe).buffer.level, 100)
	testing.expect_value(t, records.statistics.mixing_refusals, 1)
	// Emptied, the network forgets the steam and takes the wood gas.
	test_pipe(&world, pipe).buffer = EMPTY_FLUID_BUFFER
	tick_test_fluids_with_statistics(&world, &records, content, 1)
	test_pipe(&world, pipe).buffer = {fluid = test_fluid(content, "wood_gas"), level = 100}
	tick_test_fluids_with_statistics(&world, &records, content, 30)
	testing.expect(t, !test_fluid_machine(&world, generator).closed[0])
	testing.expect(t, test_fluid_machine(&world, generator).buffers[0].level > 0)
	testing.expect_value(t, records.statistics.mixing_refusals, 1)
}

// A gas that does not burn offers nothing, and the slot still works, even
// when it was put straight into the buffer past the port filter.
@(test)
test_combustion_generator_ignores_gas_without_fuel_value :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	records := make_fluid_test_records(content)
	set_generator_gas(&world, content, generator, "steam", 100)
	tick_test_entities(&world, &records, content, 1)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.state, Fluid_Machine_State.No_Fuel)
	testing.expect_value(t, machine.buffers[0].level, 100)
	machine.slots[COMBUSTION_FUEL_SLOT] = {test_item(content.items, "plank"), 1}
	tick_test_entities(&world, &records, content, 1)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Generating)
	testing.expect_value(t, machine.buffers[0].level, 100)
}

// A steam engine offering 60 J and a combustion generator offering 40 J
// against two lamps asking 166 J: 602 per mille, 98 J delivered. The
// engine serves first (dispatch order 1 before 2, 0140) and gives all
// its 60 J, the generator the remaining 38.
@(test)
test_brownout_is_shared_between_steam_and_combustion :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_combustion_world(content)
	records := make_fluid_test_records(content)
	engine := place_test_entity(&world, content, "steam_engine", {-3, 1, -2})
	networks := &world.entities.electric_networks
	testing.expect_value(t, entity_network(networks, engine), entity_network(networks, generator))
	for _ in 0 ..< 10 {
		test_fluid_machine(&world, engine).fuel_joules = 60
		test_fluid_machine(&world, generator).fuel_joules = 40
		tick_test_entities(&world, &records, content, 1)
	}
	network := networks.networks[0]
	testing.expect_value(t, network.supply, 100)
	testing.expect_value(t, network.demand, 166)
	testing.expect_value(t, network.satisfaction, 602)
	testing.expect_value(t, network.delivered, 98)
	testing.expect_value(t, test_fluid_machine(&world, engine).generated_joules, 60)
	testing.expect_value(t, test_fluid_machine(&world, generator).generated_joules, 38)
	testing.expect_value(t, test_fluid_machine(&world, generator).state, Fluid_Machine_State.Generating)
	testing.expect_value(t, records.statistics.energy_produced_joules, 98 * 10)
	testing.expect_value(t, records.statistics.energy_consumed_joules, 98 * 10)
	testing.expect_value(t, records.statistics.brownout_ticks, 10)
	// The overview groups the generators by type with their output.
	groups := largest_participant_groups(networks.participants[:], 0, true, POWER_GENERATOR_TYPE_COUNT)
	testing.expect_value(t, len(groups), 2)
	testing.expect_value(t, groups[0], Participant_Group{machine = test_machine(content.machines, "steam_engine"), count = 1, joules = 60})
	testing.expect_value(t, groups[1], Participant_Group{machine = test_machine(content.machines, "combustion_generator"), count = 1, joules = 38})
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
	records := [2]Game_Records{make_fluid_test_records(content), make_fluid_test_records(content)}
	generator, chest: Entity_Handle
	for &world, index in worlds {
		generator, chest = build_combustion_plant(&world, content)
		tick_test_entities(&world, &records[index], content, 1200)
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
	testing.expect_value(t, records[0].statistics.energy_produced_joules, records[1].statistics.energy_produced_joules)
	// The plant runs on its own gas: more burned than the 10 L seed, the
	// energy all accounted for, ore mined.
	world := &worlds[0]
	statistics := records[0].statistics
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

// The fuel generator (work item 0140): a combustion generator without a
// port. Its world is the combustion world's with the fuel generator
// standing where the combustion generator would, its cells x and z 1 to 2.
make_fuel_generator_world :: proc(content: Simulation_Content) -> (world: World, generator: Entity_Handle) {
	world = make_oil_world(content)
	generator = place_test_entity(&world, content, "fuel_generator", COMBUSTION_TEST_ORIGIN)
	place_test_entity(&world, content, "small_pole", COMBUSTION_TEST_POLE)
	place_test_entity(&world, content, "lamp", {0, 1, -2})
	place_test_entity(&world, content, "lamp", {2, 1, -1})
	return
}

@(test)
test_fuel_generator_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := content.machines.machines[test_machine(content.machines, "fuel_generator")]
	testing.expect_value(t, machine.kind, Machine_Kind.Combustion_Generator)
	testing.expect_value(t, machine.footprint, [3]i32{2, 2, 2})
	testing.expect_value(t, machine.slot_count, 1)
	testing.expect_value(t, machine.fluid_port_count, 0)
	testing.expect_value(t, machine.fuel_efficiency_percent, 25)
	testing.expect_value(t, machine.item, test_item(content.items, "fuel_generator"))
	testing.expect_value(t, electric_joules_per_tick(machine.electric_output_watts, TEST_TICK_RATE), 1250)
	// Hand craftable on the start channel, before the steam engine.
	recipe := content.recipes.recipes[test_recipe(content.recipes, "fuel_generator")]
	testing.expect_value(t, recipe.channel, Recipe_Channel.Start)
	testing.expect_value(t, len(recipe.inputs), 4)
	// Inserters feed its fuel slot.
	world, generator := make_fuel_generator_world(content)
	slot, accepted := entity_accepts(&world.entities, content, generator, test_item(content.items, "log"))
	testing.expect(t, accepted && slot == COMBUSTION_FUEL_SLOT)
}

// A coal delivers a quarter of its 4 MJ: 1 MJ, burned only for what the
// lamps receive. It offers its full 75 kW while it holds fuel.
@(test)
test_fuel_generator_burns_coal_at_a_quarter :: proc(t: ^testing.T) {
	content := make_test_content()
	world, generator := make_fuel_generator_world(content)
	records := make_fluid_test_records(content)
	coal := test_item(content.items, "coal")
	test_fluid_machine(&world, generator).slots[COMBUSTION_FUEL_SLOT] = {coal, 3}
	prototype := content.machines.machines[test_machine(content.machines, "fuel_generator")]
	testing.expect_value(t, combustion_slot_joules(test_fluid_machine(&world, generator)^, prototype, content.items), 3_000_000)
	testing.expect_value(t, generator_available_joules(&world, test_fluid_machine(&world, generator)^, prototype, content, TEST_TICK_RATE), 1250)
	tick_test_entities(&world, &records, content, 1000)
	machine := test_fluid_machine(&world, generator)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT], Item_Stack{coal, 2})
	testing.expect_value(t, machine.fuel_item_joules, 1_000_000)
	testing.expect_value(t, records.statistics.energy_produced_joules, 166 * 1000)
	testing.expect_value(t, records.statistics.energy_consumed_joules, records.statistics.energy_produced_joules)
	testing.expect_value(t, u64(machine.fuel_joules), 1_000_000 - records.statistics.energy_produced_joules)
	testing.expect_value(t, records.statistics.fuel_burned, 1)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Generating)
	// The first coal runs out after 6024 ticks and the second is lit.
	tick_test_entities(&world, &records, content, 6000)
	testing.expect_value(t, machine.slots[COMBUSTION_FUEL_SLOT], Item_Stack{coal, 1})
	testing.expect_value(t, records.statistics.energy_produced_joules + u64(machine.fuel_joules), 2 * 1_000_000)
}

// An offshore pump filling a tank and an electric drill ask 1000 and
// 1500 J a tick of a fuel generator offering 1250: half each, so the pump
// pushes 10 litres a tick instead of 20.
@(test)
test_fuel_generator_browns_out_under_a_pump_and_a_drill :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_oil_world(content)
	records := make_fluid_test_records(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	drill := place_test_entity(&world, content, "electric_mining_drill", {0, 1, 0})
	test_drill(&world, drill).vein = vein
	place_test_entity(&world, content, "iron_chest", {3, 1, 1})
	place_test_entity(&world, content, "small_pole", {4, 1, 3})
	generator := place_test_entity(&world, content, "fuel_generator", {5, 1, 4})
	test_fluid_machine(&world, generator).slots[COMBUSTION_FUEL_SLOT] = {test_item(content.items, "coal"), 10}
	pump := place_test_entity(&world, content, "offshore_pump", {3, 1, 5})
	lay_pipes(&world, content, {2, 1, 5})
	place_test_entity(&world, content, "storage_tank", {-1, 1, 4})
	tick_test_entities(&world, &records, content, 60)
	network := world.entities.electric_networks.networks[0]
	testing.expect_value(t, len(world.entities.electric_networks.networks), 1)
	testing.expect_value(t, network.supply, 1250)
	testing.expect_value(t, network.demand, 2500)
	testing.expect_value(t, network.satisfaction, 500)
	testing.expect_value(t, records.statistics.brownout_ticks, 60)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Producing)
	testing.expect_value(t, records.statistics.energy_produced_joules, 1250 * 60)
	testing.expect_value(t, records.statistics.energy_consumed_joules, records.statistics.energy_produced_joules)
	water := test_fluid(content, "water")
	testing.expect_value(t, fluid_counter(records.statistics.fluids.produced, water), 10 * 60)
}

// fuel_efficiency_percent: 1 to 100 on a combustion generator, which may
// go without a port, and on no other kind.
@(test)
test_fuel_efficiency_is_validated :: proc(t: ^testing.T) {
	generator := Machine_Definition {
		id                        = "fuel_generator",
		name_key                  = "machine_fuel_generator",
		item                      = "wooden_chest",
		kind                      = "combustion_generator",
		footprint                 = {2, 2, 2},
		fuel_slots                = 1,
		electric_output_kilowatts = 75,
		fuel_efficiency_percent   = 25,
		dispatch_order            = 3,
	}
	testing.expect_value(t, resolve_test_machines({generator}), "")
	for percent in ([?]int{0, 101}) {
		refused := generator
		refused.fuel_efficiency_percent = percent
		testing.expect(t, strings.contains(resolve_test_machines({refused}), "fuel_efficiency_percent"))
	}
	chest := Machine_Definition {
		id                      = "chest",
		name_key                = "machine_wooden_chest",
		item                    = "wooden_chest",
		kind                    = "chest",
		footprint               = {1, 1, 1},
		slots                   = 16,
		fuel_efficiency_percent = 50,
	}
	testing.expect(t, strings.contains(resolve_test_machines({chest}), "fuel_efficiency_percent"))
}

// Every generator kind needs a dispatch order and nothing else has one.
@(test)
test_dispatch_order_is_validated :: proc(t: ^testing.T) {
	generator := Machine_Definition {
		id                        = "fuel_generator",
		name_key                  = "machine_fuel_generator",
		item                      = "wooden_chest",
		kind                      = "combustion_generator",
		footprint                 = {2, 2, 2},
		fuel_slots                = 1,
		electric_output_kilowatts = 75,
		fuel_efficiency_percent   = 25,
		dispatch_order            = 0,
	}
	testing.expect_value(t, resolve_test_machines({generator}), "")
	missing := generator
	missing.dispatch_order = nil
	testing.expect(t, strings.contains(resolve_test_machines({missing}), "dispatch_order"))
	for order in ([?]int{-1, MAXIMUM_DISPATCH_ORDER + 1}) {
		refused := generator
		refused.dispatch_order = order
		testing.expect(t, strings.contains(resolve_test_machines({refused}), "dispatch_order"))
	}
	chest := Machine_Definition {
		id             = "chest",
		name_key       = "machine_wooden_chest",
		item           = "wooden_chest",
		kind           = "chest",
		footprint      = {1, 1, 1},
		slots          = 16,
		dispatch_order = 1,
	}
	testing.expect(t, strings.contains(resolve_test_machines({chest}), "dispatch_order"))
	content := make_test_content()
	orders := [?]struct {
		id:    string,
		order: u8,
	}{{"hydro_turbine", 0}, {"steam_engine", 1}, {"combustion_generator", 2}, {"fuel_generator", 3}}
	for entry in orders {
		testing.expect_value(t, content.machines.machines[test_machine(content.machines, entry.id)].dispatch_order, entry.order)
	}
}

// The panel line: 1 MJ at 1250 J a tick is 800 ticks, 13 s; three rows
// (output, fuel line, power network) on every combustion generator.
@(test)
test_combustion_fuel_line :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := content.machines.machines[test_machine(content.machines, "fuel_generator")]
	expected := fmt.tprintf("%s 25 %%  %s 0:13", text("fuel_efficiency"), text("fuel_burn_time"))
	testing.expect_value(t, combustion_fuel_line(machine, 1_000_000, TEST_TICK_RATE), expected)
	expected = fmt.tprintf("%s 25 %%  %s 0:00", text("fuel_efficiency"), text("fuel_burn_time"))
	testing.expect_value(t, combustion_fuel_line(machine, 0, TEST_TICK_RATE), expected)
	testing.expect_value(t, fluid_machine_power_rows(.Combustion_Generator), 3)
	testing.expect_value(t, fluid_machine_power_rows(.Steam_Engine), 2)
	testing.expect_value(t, fluid_machine_power_rows(.Offshore_Pump), 1)
}
