package game

import "core:math/rand"
import "core:testing"
import "netlist"

// Power worlds stand on the stone floor of make_floor_world (top at y 1).

test_pole :: proc(world: ^World, handle: Entity_Handle) -> ^Pole {
	return pool_get(&world.entities.poles, handle)
}

test_lamp :: proc(world: ^World, handle: Entity_Handle) -> ^Lamp {
	return pool_get(&world.entities.lamps, handle)
}

// A junction box at the cell and a steam engine with full steam buffers,
// joined by a trunk cable (0368).
add_test_power_plant :: proc(world: ^World, content: Simulation_Content, box_cell, engine_origin: World_Coordinate) -> (box, engine: Entity_Handle) {
	engine = place_test_entity(world, content, "steam_engine", engine_origin)
	steam := test_fluid(content, "steam")
	for &buffer in test_fluid_machine(world, engine).buffers[:2] {
		buffer = {fluid = steam, level = 200}
	}
	box = place_test_entity(world, content, "junction_box", box_cell)
	cable_test_machines(world, content, box, engine)
	return
}

// One power port of the capacity on the minimum cell's -z face, for a
// hand made electric definition (0368).
test_power_ports :: proc(watts: int) -> []Machine_Port_Definition {
	ports := make([]Machine_Port_Definition, 1, context.temp_allocator)
	ports[0] = {id = "power", kind = "power", face = "negative_z", capacity_watts = watts}
	return ports
}

// The entity's lowest free power port, -1 for none.
first_free_power_port :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> int {
	for port in 0 ..< MAXIMUM_MACHINE_PORTS {
		if port_end_is_free(entities, machines, Port_End{entity = handle, port = u8(port)}) {
			return port
		}
	}
	return -1
}

// A cable of the item between the two ends through add_cable, with its
// measured metres; no span or hold is checked.
lay_test_cable :: proc(world: ^World, content: Simulation_Content, item: string, first, second: Port_End) {
	metres := port_span_metres(&world.entities, content.machines, first, second)
	add_cable(&world.entities, content, Cable{ends = {first, second}, item = test_item(content.items, item), metres = u16(metres)})
}

// A trunk cable from each handle's lowest free power port to the box's;
// when the box has one free port left, a junction box placed on the cell
// above, joined to it by trunk cable, takes the rest.
cable_test_machines :: proc(world: ^World, content: Simulation_Content, box: Entity_Handle, handles: ..Entity_Handle) {
	entities := &world.entities
	box := box
	for handle in handles {
		if free_power_port_count(entities, content.machines, box) == 1 {
			above := place_test_entity(world, content, "junction_box", entity_common(entities, box).origin + {0, 1, 0})
			lay_test_cable(world, content, "trunk_cable", {box, u8(first_free_power_port(entities, content.machines, box))}, {above, 0})
			box = above
		}
		first := Port_End{handle, u8(first_free_power_port(entities, content.machines, handle))}
		lay_test_cable(world, content, "trunk_cable", first, {box, u8(first_free_power_port(entities, content.machines, box))})
	}
}

free_power_port_count :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> int {
	count := 0
	for port in 0 ..< MAXIMUM_MACHINE_PORTS {
		if port_end_is_free(entities, machines, Port_End{entity = handle, port = u8(port)}) {
			count += 1
		}
	}
	return count
}

@(test)
test_power_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	box := content.machines.machines[test_machine(content.machines, "junction_box")]
	testing.expect_value(t, box.kind, Machine_Kind.Junction_Box)
	testing.expect_value(t, box.footprint, [3]i32{1, 1, 1})
	testing.expect_value(t, box.port_count, 4)
	testing.expect_value(t, box.item, test_item(content.items, "junction_box"))
	switch_machine := content.machines.machines[test_machine(content.machines, "power_switch")]
	testing.expect_value(t, switch_machine.kind, Machine_Kind.Power_Switch)
	testing.expect_value(t, switch_machine.port_count, 2)
	trunk := content.items.items[test_item(content.items, "trunk_cable")]
	testing.expect_value(t, i64(trunk.cable_kilowatts) * 1000, TRUNK_CABLE_TEST_WATTS)
	lamp := content.machines.machines[test_machine(content.machines, "lamp")]
	testing.expect_value(t, lamp.light_level, 15)
	testing.expect_value(t, lamp.light_color, Light_Color{14, 14, 15})
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

// Two boxes cabled are one network; a box alone is in none, and gains
// one with a cable to a lamp; a box removed takes its cables with it.
@(test)
test_cables_make_networks :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	first := place_test_entity(&world, content, "junction_box", {0, 1, 0})
	second := place_test_entity(&world, content, "junction_box", {7, 1, 0})
	third := place_test_entity(&world, content, "junction_box", {15, 1, 0})
	networks := &world.entities.electric_networks
	testing.expect_value(t, len(networks.networks), 0)
	lay_test_cable(&world, content, "light_cable", {first, 1}, {second, 0})
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect_value(t, entity_network(networks, first), entity_network(networks, second))
	testing.expect_value(t, entity_network(networks, third), -1)
	lamp := place_test_entity(&world, content, "lamp", {16, 1, 2})
	lay_test_cable(&world, content, "light_cable", {lamp, 0}, {third, 3})
	testing.expect_value(t, len(networks.networks), 2)
	testing.expect_value(t, entity_network(networks, lamp), entity_network(networks, third))
	// A cable between the second and the third joins them.
	lay_test_cable(&world, content, "light_cable", {second, 1}, {third, 0})
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect_value(t, entity_network(networks, first), entity_network(networks, lamp))
	testing.expect(t, remove_entity(&world.entities, content.machines, second))
	testing.expect_value(t, len(world.entities.cables.cables), 1)
	testing.expect_value(t, entity_network(networks, first), -1)
	testing.expect_value(t, entity_network(networks, lamp), 0)
}

// Only a cable puts a machine in a network, the drill's on its one port
// too; a chest has no power port and no node.
@(test)
test_a_cable_decides_membership :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	box := place_test_entity(&world, content, "junction_box", {0, 1, 0})
	networks := &world.entities.electric_networks
	cabled := place_test_entity(&world, content, "lamp", {2, 1, -2})
	near := place_test_entity(&world, content, "lamp", {1, 1, 0})
	cable_test_machines(&world, content, box, cabled)
	testing.expect_value(t, entity_network(networks, cabled), 0)
	testing.expect_value(t, entity_network(networks, near), -1)
	drill := place_test_entity(&world, content, "electric_mining_drill", {-4, 1, -1})
	cable_test_machines(&world, content, box, drill)
	testing.expect_value(t, entity_network(networks, drill), 0)
	chest := place_test_entity(&world, content, "wooden_chest", {1, 1, 1})
	testing.expect_value(t, entity_network(networks, chest), -1)
	testing.expect_value(t, first_free_power_port(&world.entities, content.machines, chest), -1)
}

participant :: proc(network: int, generator: bool, offered: u64) -> Electric_Participant {
	return Electric_Participant{network = network, generator = generator, offered = offered}
}

// The shipped trunk cable's capacity (test_power_data_loads holds it).
TRUNK_CABLE_TEST_WATTS :: 24_000_000

// The participants on a star of trunk cables round one box per network
// (0368): node k below network_count is network k's box, then a node per
// participant in a network, cabled to its box; one outside every network
// has no node. Balanced at TEST_TICK_RATE; the networks in the temp
// allocator.
balance_on_trunk_stars :: proc(participants: []Electric_Participant, network_count: int) -> ^Electric_Networks {
	networks := new(Electric_Networks, context.temp_allocator)
	networks.allocator = context.temp_allocator
	set_electric_allocators(networks)
	edges := make([dynamic]netlist.Edge, context.temp_allocator)
	node_count := network_count
	for participant in participants {
		entry := participant
		entry.node = -1
		if participant.network >= 0 {
			entry.node = node_count
			append(&edges, netlist.Edge{u32(participant.network), u32(node_count), TRUNK_CABLE_TEST_WATTS})
			node_count += 1
		}
		append(&networks.participants, entry)
	}
	resize(&networks.node_entities, node_count)
	networks.topology = netlist.build_topology(node_count, edges[:], context.temp_allocator)
	resize(&networks.network_of_tree, len(networks.topology.trees))
	for &network in networks.network_of_tree {
		network = -1
	}
	for box in 0 ..< network_count {
		networks.network_of_tree[networks.topology.tree_of[box]] = i32(box)
	}
	resize(&networks.networks, network_count)
	balance_electric_energy(networks, TEST_TICK_RATE)
	return networks
}

delivered_of :: proc(networks: ^Electric_Networks, $N: int) -> (delivered: [N]u64) {
	for &value, index in delivered {
		value = networks.participants[index].delivered
	}
	return
}

@(test)
test_energy_balance_with_two_generators_and_three_consumers :: proc(t: ^testing.T) {
	// Enough supply: everyone gets their demand, 1799 J shared 15 to 10
	// with the joule left over rounding down going to the first.
	enough := balance_on_trunk_stars({participant(0, true, 15_000), participant(0, false, 1500), participant(0, true, 10_000), participant(0, false, 216), participant(0, false, 83)}, 1)
	testing.expect_value(t, enough.networks[0].satisfaction, 1000)
	testing.expect_value(t, enough.networks[0].supply, 25_000)
	testing.expect_value(t, enough.networks[0].demand, 1799)
	testing.expect_value(t, enough.networks[0].delivered, 1799)
	testing.expect_value(t, enough.networks[0].generator_count, 2)
	testing.expect_value(t, enough.networks[0].consumer_count, 3)
	testing.expect_value(t, delivered_of(enough, 5), [5]u64{1080, 1500, 719, 216, 83})
	// Short: 1500 of 1799 is 833 per mille, and every consumer gets that
	// share of its demand.
	short := balance_on_trunk_stars({participant(0, true, 1000), participant(0, false, 1500), participant(0, true, 500), participant(0, false, 216), participant(0, false, 83)}, 1)
	testing.expect_value(t, short.networks[0].satisfaction, 833)
	testing.expect_value(t, short.networks[0].delivered, 1497)
	testing.expect_value(t, delivered_of(short, 5), [5]u64{998, 1249, 499, 179, 69})
	// Nothing asks: full while something could give, none without supply.
	testing.expect_value(t, power_satisfaction(100, 0), 1000)
	testing.expect_value(t, power_satisfaction(0, 0), 0)
	testing.expect_value(t, power_satisfaction(0, 500), 0)
	// Outside every network nothing is delivered.
	alone := balance_on_trunk_stars({participant(-1, false, 500)}, 1)
	testing.expect_value(t, alone.participants[0].delivered, 0)
}

generator_participant :: proc(offered: u64, order: u8) -> Electric_Participant {
	result := participant(0, true, offered)
	result.dispatch_order = order
	return result
}

// Work item 0140: two engines of order 1 serve before a fuel generator of
// order 3, split 600 to 400 between them; the generator gives only what
// they cannot.
@(test)
test_generators_serve_in_dispatch_order :: proc(t: ^testing.T) {
	covered := balance_on_trunk_stars({generator_participant(500, 3), generator_participant(600, 1), generator_participant(400, 1), participant(0, false, 801)}, 1)
	testing.expect_value(t, covered.networks[0].delivered, 801)
	testing.expect_value(t, delivered_of(covered, 3), [3]u64{0, 481, 320})
	short := balance_on_trunk_stars({generator_participant(500, 3), generator_participant(600, 1), generator_participant(400, 1), participant(0, false, 1300)}, 1)
	testing.expect_value(t, delivered_of(short, 3), [3]u64{300, 600, 400})
}

// Work item 0140: once the engine runs, the fuel generator that started
// the plant burns nothing for 100 s; with the steam cut it carries the
// offshore pump again.
@(test)
test_fuel_generator_only_covers_what_the_engines_cannot :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	records := make_test_records(content)
	build_power_plant(&world, content)
	generator := entity_at(&world.entities, {4, 1, -2})
	pump := entity_at(&world.entities, {2, 1, -3})
	prototype := content.machines.machines[test_machine(content.machines, "fuel_generator")]
	tick_test_entities(&world, &records, content, 1200)
	stored := combustion_generator_stored_joules(test_fluid_machine(&world, generator)^, prototype, content.fluids, content.items)
	testing.expect(t, stored < 5 * 1_000_000)
	tick_test_entities(&world, &records, content, 6000)
	testing.expect_value(t, combustion_generator_stored_joules(test_fluid_machine(&world, generator)^, prototype, content.fluids, content.items), stored)
	testing.expect_value(t, test_fluid_machine(&world, generator).generated_joules, 0)
	// Cut the steam: no coal in the boiler and none of its steam left.
	boiler := test_fluid_machine(&world, entity_at(&world.entities, {0, 1, 0}))
	boiler.slots[BOILER_FUEL_SLOT] = EMPTY_STACK
	boiler.fuel_joules = 0
	boiler.buffers[1] = EMPTY_FLUID_BUFFER
	engine := test_fluid_machine(&world, entity_at(&world.entities, {0, 1, 3}))
	engine.buffers = {}
	engine.fuel_joules = 0
	test_pipe(&world, entity_at(&world.entities, {1, 1, 2})).buffer = EMPTY_FLUID_BUFFER
	tick_test_entities(&world, &records, content, 60)
	testing.expect(t, test_fluid_machine(&world, generator).generated_joules > 0)
	testing.expect(t, combustion_generator_stored_joules(test_fluid_machine(&world, generator)^, prototype, content.fluids, content.items) < stored)
	testing.expect(t, power_is_on(test_fluid_machine(&world, pump).power))
}

// An electric drill on an iron vein dropping into a chest, a pole and a
// steam engine whose offer the test sets every tick.
Drill_Power_Test :: struct {
	world:   World,
	records: Game_Records,
	drill:   Entity_Handle,
	chest:   Entity_Handle,
	engine:  Entity_Handle,
}

make_drill_power_test :: proc(content: Simulation_Content) -> Drill_Power_Test {
	test := Drill_Power_Test {
		world   = make_drill_world(content),
		records = make_test_records(content),
	}
	vein := add_test_vein(&test.world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	test.drill = place_test_entity(&test.world, content, "electric_mining_drill", {0, 1, 0})
	test_drill(&test.world, test.drill).vein = vein
	test.chest = place_test_entity(&test.world, content, "iron_chest", {3, 1, 1})
	box: Entity_Handle
	box, test.engine = add_test_power_plant(&test.world, content, {4, 1, 3}, {5, 1, -2})
	cable_test_machines(&test.world, content, box, test.drill)
	return test
}

// The engine has no steam and exactly `joules` drawn already, so that is
// its offer for the tick.
tick_with_engine_offer :: proc(test: ^Drill_Power_Test, content: Simulation_Content, joules: u32, ticks: int) {
	for _ in 0 ..< ticks {
		engine := test_fluid_machine(&test.world, test.engine)
		engine.buffers[0], engine.buffers[1] = EMPTY_FLUID_BUFFER, EMPTY_FLUID_BUFFER
		engine.fuel_joules = joules
		tick_test_entities(&test.world, &test.records, content, 1)
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
	testing.expect_value(t, full.records.statistics.brownout_ticks, 0)
	// Half the drill's 1500 J: it mines every other tick, five units.
	half := make_drill_power_test(content)
	tick_with_engine_offer(&half, content, 750, 960)
	testing.expect_value(t, chest_total(&half.world, half.chest), 5)
	testing.expect_value(t, half.world.entities.electric_networks.networks[0].satisfaction, 500)
	testing.expect_value(t, test_drill(&half.world, half.drill).state, Drill_State.Mining)
	testing.expect_value(t, half.records.statistics.brownout_ticks, 960)
	testing.expect_value(t, half.records.statistics.energy_consumed_joules, 960 * 750)
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
	records := make_test_records(content)
	box, engine := add_test_power_plant(&world, content, {4, 1, 3}, {5, 1, -2})
	lamps := [2]Entity_Handle{place_test_entity(&world, content, "lamp", {3, 1, 2}), place_test_entity(&world, content, "lamp", {3, 1, 4})}
	cable_test_machines(&world, content, box, ..lamps[:])
	// Nothing asks yet except the lamps: 166 J a tick, a litre every
	// 180 ticks and a bit.
	tick_test_entities(&world, &records, content, 1000)
	machine := test_fluid_machine(&world, engine)
	litres_used := 400 - i64(machine.buffers[0].level) - i64(machine.buffers[1].level)
	testing.expect_value(t, records.statistics.energy_produced_joules, 166 * 1000)
	testing.expect_value(t, litres_used * 30_000, i64(records.statistics.energy_produced_joules) + i64(machine.fuel_joules))
	testing.expect_value(t, litres_used, 6)
	testing.expect_value(t, machine.state, Fluid_Machine_State.Producing)
	testing.expect_value(t, machine.generated_joules, 166)
	testing.expect(t, test_lamp(&world, lamps[0]).lit)
	// Out of steam the engine gives nothing and the lamps go dark.
	machine.buffers[0], machine.buffers[1] = EMPTY_FLUID_BUFFER, EMPTY_FLUID_BUFFER
	machine.fuel_joules = 0
	tick_test_entities(&world, &records, content, 1)
	testing.expect_value(t, machine.state, Fluid_Machine_State.No_Steam)
	testing.expect(t, !test_lamp(&world, lamps[0]).lit)
	testing.expect_value(t, records.statistics.brownout_ticks, 1)
}

@(test)
test_power_switch_splits_a_network :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	near, _ := add_test_power_plant(&world, content, {0, 1, 0}, {-3, 1, -2})
	far := place_test_entity(&world, content, "junction_box", {10, 1, 0})
	lamp := place_test_entity(&world, content, "lamp", {11, 1, 0})
	cable_test_machines(&world, content, far, lamp)
	networks := &world.entities.electric_networks
	testing.expect_value(t, len(networks.networks), 2)
	switch_handle := place_test_entity(&world, content, "power_switch", {5, 1, 0})
	lay_test_cable(&world, content, "light_cable", {near, 1}, {switch_handle, 0})
	lay_test_cable(&world, content, "light_cable", {switch_handle, 1}, {far, 1})
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect_value(t, entity_network(networks, far), entity_network(networks, near))
	tick_test_entities(&world, &records, content, 2)
	testing.expect(t, test_lamp(&world, lamp).lit)
	testing.expect(t, toggle_power_switch(&world.entities, content.machines, switch_handle))
	testing.expect(t, !test_pole(&world, switch_handle).on)
	testing.expect_value(t, len(networks.networks), 2)
	testing.expect(t, entity_network(networks, far) != entity_network(networks, near))
	// Its port a stays on the near side.
	testing.expect_value(t, entity_network(networks, switch_handle), entity_network(networks, near))
	// The cables stay, the switch's second node carries nothing on.
	testing.expect_value(t, len(world.entities.cables.cables), 4)
	tick_test_entities(&world, &records, content, 2)
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
	records: Game_Records
	box, engine := add_test_power_plant(&world, content, {0, 1, 0}, {-3, 1, -2})
	lamp := place_test_entity(&world, content, "lamp", {2, 1, 2})
	cable_test_machines(&world, content, box, lamp)
	tick_test_entities(&world, &records, content, 1)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {2, 1, 2}), 15)
	testing.expect_value(t, block_light_at(&world, {2, 2, 2}), 14)
	testing.expect_value(t, block_light_at(&world, {5, 1, 2}), 12)
	// Without its box the lamp is unpowered, and its light goes out
	// through the removal queue.
	testing.expect(t, remove_entity(&world.entities, content.machines, box))
	tick_test_entities(&world, &records, content, 1)
	testing.expect(t, !test_lamp(&world, lamp).lit)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {2, 1, 2}), 0)
	testing.expect_value(t, block_light_at(&world, {5, 1, 2}), 0)
	testing.expect_value(t, len(world.entity_lights), 0)
	// Back on, then picked up while lit: the light goes with it.
	cable_test_machines(&world, content, place_test_entity(&world, content, "junction_box", {0, 1, 0}), engine, lamp)
	tick_test_entities(&world, &records, content, 1)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {2, 1, 2}), 15)
	testing.expect(t, remove_entity(&world.entities, content.machines, lamp))
	tick_test_entities(&world, &records, content, 1)
	propagate_light(&world, content.blocks, 100_000)
	testing.expect_value(t, block_light_at(&world, {3, 1, 2}), 0)
}

// Water, a boiler, a steam engine, three junction boxes, an electric
// drill feeding a chest, a lamp and an electric inserter between two
// chests, every machine cabled to a box and the boxes in a chain (0368).
// The offshore pump draws power (0140): a fuel generator with coal on the
// pump's box starts the plant.
build_power_plant :: proc(world: ^World, content: Simulation_Content) {
	pump := place_test_fluid_entity(world, content, "offshore_pump", {2, 1, -3})
	first := place_test_entity(world, content, "junction_box", {3, 1, -1})
	generator := place_test_entity(world, content, "fuel_generator", {4, 1, -2})
	test_fluid_machine(world, generator).slots[COMBUSTION_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 5}
	lay_pipes(world, content, {1, 1, -3}, {1, 1, -2}, {1, 1, -1})
	boiler := place_test_fluid_entity(world, content, "boiler", {0, 1, 0})
	test_fluid_machine(world, boiler).slots[BOILER_FUEL_SLOT] = Item_Stack{item = test_item(content.items, "coal"), count = 20}
	lay_pipes(world, content, {1, 1, 2})
	engine := place_test_fluid_entity(world, content, "steam_engine", {0, 1, 3})
	second := place_test_entity(world, content, "junction_box", {3, 1, 5})
	third := place_test_entity(world, content, "junction_box", {6, 1, 9})
	vein := add_test_vein(world, content, "iron", {8, 8}, 2, IRON_TEST_VEIN)
	drill := place_test_entity(world, content, "electric_mining_drill", {7, 1, 7})
	test_drill(world, drill).vein = vein
	place_test_entity(world, content, "iron_chest", {10, 1, 8})
	lamp := place_test_entity(world, content, "lamp", {5, 1, 8})
	source := place_test_entity(world, content, "wooden_chest", {4, 1, 10})
	inserter := place_test_entity(world, content, "inserter", {5, 1, 10}, 0)
	place_test_entity(world, content, "wooden_chest", {6, 1, 10})
	entity_insert(&world.entities, content, source, Item_Stack{test_item(content.items, "iron_plate"), 40})
	cable_test_machines(world, content, first, pump, generator, second)
	cable_test_machines(world, content, second, engine, third)
	cable_test_machines(world, content, third, drill, lamp, inserter)
}

@(test)
test_power_simulation_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_drill_world(content), make_drill_world(content)}
	all_records := [2]Game_Records{make_test_records(content), make_test_records(content)}
	for &world, index in worlds {
		build_power_plant(&world, content)
		tick_test_entities(&world, &all_records[index], content, 1200)
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
	testing.expect_value(t, all_records[0].statistics.energy_produced_joules, all_records[1].statistics.energy_produced_joules)
	// The plant runs: one network, power made, ore mined, plates moved.
	world, records := &worlds[0], &all_records[0]
	testing.expect_value(t, len(first.electric_networks.networks), 1)
	testing.expect(t, records.statistics.energy_produced_joules > 0)
	testing.expect_value(t, records.statistics.unpowered_machines, 0)
	testing.expect(t, chest_total(world, entity_at(first, {10, 1, 8})) > 0)
	testing.expect(t, chest_total(world, entity_at(first, {6, 1, 10})) > 0)
	testing.expect(t, first.lamps.entries[0].lit)
}

// The balance before the netlist (0355), to hold its hub adapter to it:
// pooled per network, every consumer its demand times the network's
// satisfaction, and what the consumers received shared over the
// generators by dispatch order, in proportion to their offers, rounded
// down, the rest a joule at a time in participant order.
pooled_balance_before_the_netlist :: proc(participants: []Electric_Participant, networks: []Electric_Network) -> []u64 {
	delivered := make([]u64, len(participants), context.temp_allocator)
	for &network in networks {
		network = {}
	}
	for participant in participants {
		if participant.network >= 0 {
			add_participant_offer(&networks[participant.network], participant)
		}
	}
	for &network in networks {
		network.satisfaction = network.demand == 0 ? (network.supply > 0 ? POWER_FULL : 0) : u32(min(network.supply, network.demand) * POWER_FULL / network.demand)
	}
	remaining := make([]u64, len(networks), context.temp_allocator)
	for participant, index in participants {
		if participant.network >= 0 && !participant.generator {
			delivered[index] = participant.offered * u64(networks[participant.network].satisfaction) / POWER_FULL
			networks[participant.network].delivered += delivered[index]
			remaining[participant.network] += delivered[index]
		}
	}
	for order in 0 ..= u8(MAXIMUM_DISPATCH_ORDER) {
		share_order_before_the_netlist(participants, delivered, remaining, order)
	}
	return delivered
}

share_order_before_the_netlist :: proc(participants: []Electric_Participant, delivered, remaining: []u64, order: u8) {
	order_supply := make([]u64, len(remaining), context.temp_allocator)
	assigned := make([]u64, len(remaining), context.temp_allocator)
	for participant in participants {
		if participant.network >= 0 && participant.generator && participant.dispatch_order == order {
			order_supply[participant.network] += participant.offered
		}
	}
	for participant, index in participants {
		if participant.network >= 0 && participant.generator && participant.dispatch_order == order && order_supply[participant.network] > 0 {
			delivered[index] = participant.offered * min(order_supply[participant.network], remaining[participant.network]) / order_supply[participant.network]
			assigned[participant.network] += delivered[index]
		}
	}
	for participant, index in participants {
		if participant.network >= 0 && participant.generator && participant.dispatch_order == order {
			share := min(order_supply[participant.network], remaining[participant.network])
			extra := min(share - assigned[participant.network], participant.offered - delivered[index])
			delivered[index] += extra
			assigned[participant.network] += extra
		}
	}
	for supply, network in order_supply {
		remaining[network] -= min(supply, remaining[network])
	}
}

// Work item 0355: the balance through the netlist gives what the pooled
// balance gave, participant for participant and network for network, on
// seeded factories of up to 6 networks with participants outside every
// network, generators of every dispatch order and leftover joules; since
// 0368 each network a star of trunk cables (balance_on_trunk_stars),
// whose capacity no participant reaches.
@(test)
test_balance_through_the_netlist_matches_the_pooled_balance :: proc(t: ^testing.T) {
	for seed in 0 ..< 400 {
		state := rand.create(u64(seed))
		generator := rand.default_random_generator(&state)
		network_count := rand.int_max(7, generator)
		participants := make([]Electric_Participant, rand.int_max(41, generator), context.temp_allocator)
		for &participant in participants {
			participant.network = rand.int_max(network_count + 1, generator) - 1
			participant.generator = rand.int_max(3, generator) == 0
			participant.offered = u64(rand.int_max(20_001, generator))
			if participant.generator {
				participant.dispatch_order = u8(rand.int_max(MAXIMUM_DISPATCH_ORDER + 1, generator))
			}
		}
		before := make([]Electric_Network, network_count, context.temp_allocator)
		expected := pooled_balance_before_the_netlist(participants, before)
		networks := balance_on_trunk_stars(participants, network_count)
		for participant, index in networks.participants {
			testing.expectf(t, participant.delivered == expected[index], "seed %d: participant %d %d, before %d", seed, index, participant.delivered, expected[index])
		}
		for network, index in networks.networks {
			testing.expectf(t, network == before[index], "seed %d: network %d %v, before %v", seed, index, network, before[index])
		}
		free_all(context.temp_allocator)
	}
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
	groups := largest_participant_groups(participants, 0, .Consumers, 5)
	testing.expect_value(t, len(groups), 2)
	testing.expect_value(t, groups[0], Participant_Group{machine = 5, count = 1, joules = 1500})
	testing.expect_value(t, groups[1], Participant_Group{machine = 3, count = 2, joules = 432})
}
