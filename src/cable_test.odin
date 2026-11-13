package game

import "core:fmt"
import "core:math/linalg"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:testing"
import "netlist"

// Cables (work item 0368): the shipped ports, the malformed data, the
// hand run factory on the netlist, the refusals, the run and the take up
// on the field, the pick up, the curve and the benchmark modules' cables;
// the boxes a cable draws near the eye (0384).

// The shipped definition of an item, as parsed.
shipped_item_definition :: proc(id: string) -> Item_Definition {
	file, error := parse_items_file(#load("../data/items.sjson"), context.temp_allocator)
	assert(error == nil)
	for definition in file.items {
		if definition.id == id {
			return definition
		}
	}
	panic(id)
}

// Every electric machine and generator has one power port, first, of at
// least its rating, on its footprint's surface and off its explicit fluid
// ports' faces, an inserter's on neither its pickup nor its drop face;
// the junction box has 4, the cabinet 8, the switch 2; no other kind but
// the vessel kinds lists a power port.
@(test)
test_shipped_power_ports_resolve :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for &machine in machines.machines {
		watts := i64(max(machine.electric_power_watts, machine.electric_output_watts))
		switch {
		case watts > 0:
			if !testing.expectf(t, machine_power_port_count(machine) == 1 && machine_port_is_power(machine, 0), "%s has %d power ports", machine.id, machine_power_port_count(machine)) {
				continue
			}
			port := machine.ports[0]
			testing.expectf(t, port.capacity >= watts, "%s: %d W on a %d W port", machine.id, watts, port.capacity)
			testing.expectf(t, port_cell_is_on_the_surface(port.cell, port.face, machine.footprint), "%s: the port is off the surface", machine.id)
			for fluid in machine.fluid_ports[:machine.fluid_port_count] {
				testing.expectf(t, fluid.every_face || fluid.cell != port.cell || fluid.face != port.face, "%s: the power port takes a fluid port's face", machine.id)
			}
			if machine.kind == .Inserter {
				testing.expectf(t, port.face != .Negative_X && port.face != .Positive_X, "%s: the power port is on the arm's face", machine.id)
			}
		case machine.kind == .Junction_Box || machine.kind == .Power_Switch:
			testing.expectf(t, machine_power_port_count(machine) == machine.port_count, "%s lists a port that is no power port", machine.id)
		case !machine_kind_is_vessel(machine.kind):
			testing.expectf(t, machine_power_port_count(machine) == 0, "%s lists %d power ports", machine.id, machine_power_port_count(machine))
		}
	}
	expected := [?]struct {
		id:    string,
		ports: int,
	}{{"junction_box", 4}, {"junction_cabinet", 8}, {"power_switch", 2}}
	for entry in expected {
		testing.expect_value(t, machine_power_port_count(machines.machines[test_machine(machines, entry.id)]), entry.ports)
	}
}

// A cable item missing a key, at 0 kW, with a span of 0 or 101 or above
// its stack; an electric machine without its port, with it second or
// below its rating; a junction box with 1 or 9 ports, a switch with 1, a
// furnace with one; deleted_ids naming a current id, a former id, or one
// twice: each refused, naming it.
@(test)
test_malformed_cable_items_and_power_ports_are_refused :: proc(t: ^testing.T) {
	light := shipped_item_definition("light_cable")
	testing.expect_value(t, validate_item_definition({light}, 0), "")
	missing, no_kilowatts, no_span, long_span, short_stack := light, light, light, light, light
	missing.cable_color = {}
	no_kilowatts.cable_kilowatts = 0
	no_span.cable_span_metres = 0
	long_span.cable_span_metres = 101
	short_stack.stack_size = 19
	item_cases := [?]struct {
		definition: Item_Definition,
		words:      string,
	} {
		{missing, `cable "light_cable" needs all of`},
		{no_kilowatts, `cable "light_cable" needs all of`},
		{no_span, `cable "light_cable" needs all of`},
		{long_span, `cable "light_cable" has cable_span_metres 101 outside 1 to 100`},
		{short_stack, `cable "light_cable" has cable_span_metres 20 outside 1 to 100 or above its stack_size`},
	}
	for entry in item_cases {
		problem := validate_item_definition({entry.definition}, 0)
		testing.expectf(t, strings.contains(problem, entry.words), "%q lacks %q", problem, entry.words)
	}

	lamp := shipped_machine_definition("lamp")
	box := shipped_machine_definition("junction_box")
	cabinet := shipped_machine_definition("junction_cabinet")
	power_switch := shipped_machine_definition("power_switch")
	furnace := shipped_machine_definition("stone_furnace")
	testing.expect_value(t, validate_machine_definition({lamp}, 0), "")
	spare := Machine_Port_Definition{id = "spare", kind = "power", face = "positive_x", capacity_watts = 5000}
	weak := lamp.ports[0]
	weak.capacity_watts = 4999
	ninth := Machine_Port_Definition{id = "i", kind = "power", cell = {y = 1}, face = "positive_y", capacity_watts = 1}
	nine_ports := make([dynamic]Machine_Port_Definition, context.temp_allocator)
	append(&nine_ports, ..cabinet.ports)
	append(&nine_ports, ninth)
	unpowered, second, below, lone_box, crowded, lone_switch, ported_furnace := lamp, lamp, lamp, box, cabinet, power_switch, furnace
	unpowered.ports = nil
	second.ports = {spare, lamp.ports[0]}
	below.ports = {weak}
	lone_box.ports = box.ports[:1]
	crowded.ports = nine_ports[:]
	lone_switch.ports = power_switch.ports[:1]
	ported_furnace.ports = test_power_ports(1000)
	machine_cases := [?]struct {
		definition: Machine_Definition,
		words:      string,
	} {
		{unpowered, `electric machine "lamp" needs one power port, first, with capacity_watts of at least 5000`},
		{second, `electric machine "lamp" needs one power port, first`},
		{below, `electric machine "lamp" needs one power port, first`},
		{lone_box, `junction box "junction_box" needs 2 to 8 power ports`},
		{crowded, `junction box "junction_cabinet" needs 2 to 8 power ports`},
		{lone_switch, `power switch "power_switch" needs exactly 2 power ports`},
		{ported_furnace, `machine "stone_furnace" lists ports`},
	}
	for entry in machine_cases {
		problem := validate_machine_definition({entry.definition}, 0)
		testing.expectf(t, strings.contains(problem, entry.words), "%q lacks %q", problem, entry.words)
	}

	content := make_test_content()
	testing.expect_value(t, content_former_id_problem(content), "")
	deleted_cases := [?]struct {
		ids:   []string,
		words: string,
	} {
		{{"stone_furnace"}, `machines.sjson: deleted_ids lists "stone_furnace", which is also an id`},
		{{"oxygen_generator"}, `the former or deleted id "oxygen_generator" twice`},
		{{"small_pole", "small_pole"}, `the former or deleted id "small_pole" twice`},
	}
	for entry in deleted_cases {
		changed := content
		changed.machines.deleted_ids = entry.ids
		problem := content_former_id_problem(changed)
		testing.expectf(t, strings.contains(problem, entry.words), "%q lacks %q", problem, entry.words)
	}
}

// The hand run factory (0368): a steam engine with full steam buffers, a
// heavy cable to a junction box with a lamp, and a light cable from it
// (through a power switch when asked) to a second box whose trunk cables
// feed five assemblers making gears, 375 kW behind 300 kW of light cable.
// Bundled (0369), a heavy cable from the first box's port c to the second
// box's b beside the light cable.
Hand_Run_Factory :: struct {
	engine:       Entity_Handle,
	first_box:    Entity_Handle,
	second_box:   Entity_Handle,
	lamp:         Entity_Handle,
	power_switch: Entity_Handle,
	assemblers:   [5]Entity_Handle,
}

lay_hand_run_factory :: proc(world: ^World, content: Simulation_Content, with_switch: bool, bundled := false) -> (factory: Hand_Run_Factory) {
	factory.engine = place_test_entity(world, content, "steam_engine", {-3, 1, -2})
	steam := test_fluid(content, "steam")
	for &buffer in test_fluid_machine(world, factory.engine).buffers[:2] {
		buffer = {fluid = steam, level = 200}
	}
	factory.first_box = place_test_entity(world, content, "junction_box", {0, 1, 0})
	lay_test_cable(world, content, "heavy_cable", {factory.engine, 0}, {factory.first_box, 0})
	factory.lamp = place_test_entity(world, content, "lamp", {1, 1, 2})
	lay_test_cable(world, content, "light_cable", {factory.lamp, 0}, {factory.first_box, 3})
	factory.second_box = place_test_entity(world, content, "junction_box", {8, 1, 0})
	if with_switch {
		factory.power_switch = place_test_entity(world, content, "power_switch", {4, 1, 0})
		lay_test_cable(world, content, "light_cable", {factory.first_box, 1}, {factory.power_switch, 0})
		lay_test_cable(world, content, "light_cable", {factory.power_switch, 1}, {factory.second_box, 0})
	} else {
		lay_test_cable(world, content, "light_cable", {factory.first_box, 1}, {factory.second_box, 0})
	}
	if bundled {
		lay_test_cable(world, content, "heavy_cable", {factory.first_box, 2}, {factory.second_box, 1})
	}
	origins := [5]World_Coordinate{{10, 1, -6}, {10, 1, -2}, {10, 1, 2}, {14, 1, -6}, {14, 1, -2}}
	gear := test_recipe(content.recipes, "iron_gear")
	plate := test_item(content.items, "iron_plate")
	for origin, index in origins {
		handle := place_test_entity(world, content, "assembler_1", origin)
		set_assembler_recipe(test_assembler(world, handle), content.recipes, gear)
		entity_insert(&world.entities, content, handle, {plate, 40})
		factory.assemblers[index] = handle
	}
	cable_test_machines(world, content, factory.second_box, ..factory.assemblers[:])
	return
}

// One tick with the engine's offer set to joules, as tick_with_engine_offer
// sets it.
tick_with_hand_run_offer :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, engine: Entity_Handle, joules: u32) {
	machine := test_fluid_machine(world, engine)
	machine.buffers[0], machine.buffers[1] = EMPTY_FLUID_BUFFER, EMPTY_FLUID_BUFFER
	machine.fuel_joules = joules
	tick_test_entities(world, records, content, 1)
}

// 900 kW offered: the light cable carries its 5000 J a tick to the five
// assemblers' 6250, each at 800; the lamp before it at 1000; the engine
// delivers what the consumers got. Without the light cable the five have
// no generator: at 0 and counted unpowered.
@(test)
test_a_hand_run_factory_is_powered :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	factory := lay_hand_run_factory(&world, content, false)
	networks := &world.entities.electric_networks
	testing.expect_value(t, len(networks.networks), 1)
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
	for assembler in factory.assemblers {
		testing.expect_value(t, test_assembler(&world, assembler).power.satisfaction, 800)
	}
	testing.expect_value(t, test_lamp(&world, factory.lamp).power.satisfaction, 1000)
	testing.expect(t, test_lamp(&world, factory.lamp).lit)
	supplied, delivered: u64
	for participant in networks.participants {
		if participant.generator {
			supplied += participant.delivered
		} else {
			delivered += participant.delivered
		}
	}
	testing.expect_value(t, delivered, 5 * 1000 + 83)
	testing.expect_value(t, supplied, delivered)
	testing.expect_value(t, u64(test_fluid_machine(&world, factory.engine).generated_joules), delivered)

	light := port_end_cable(&world.entities.cables, {factory.first_box, 1})
	testing.expect(t, light >= 0)
	remove_cable(&world.entities, content.machines, light)
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
	for assembler in factory.assemblers {
		testing.expect_value(t, test_assembler(&world, assembler).power.satisfaction, 0)
	}
	testing.expect_value(t, records.statistics.unpowered_machines, 5)
	testing.expect_value(t, test_lamp(&world, factory.lamp).power.satisfaction, 1000)
}

// Off, the switch splits the netlist: one more network, the assemblers
// past it unpowered, the lamp before it lit. On, one network again; a
// cable closing a loop through it is laid and is the topology's chord.
@(test)
test_a_power_switch_splits_its_netlist :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	factory := lay_hand_run_factory(&world, content, true)
	entities := &world.entities
	networks := &entities.electric_networks
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect(t, toggle_power_switch(entities, content.machines, factory.power_switch))
	testing.expect_value(t, len(networks.networks), 2)
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
	for assembler in factory.assemblers {
		testing.expect_value(t, test_assembler(&world, assembler).power.satisfaction, 0)
	}
	testing.expect_value(t, records.statistics.unpowered_machines, 5)
	testing.expect_value(t, test_lamp(&world, factory.lamp).power.satisfaction, 1000)
	testing.expect(t, toggle_power_switch(entities, content.machines, factory.power_switch))
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect_value(t, len(networks.topology.chords), 0)
	// The last box of the second box's chain.
	last := entity_at(entities, {8, 3, 0})
	testing.expect_value(t, last.kind, Entity_Kind.Pole)
	loop := Cable_Placement {
		ends = {{factory.first_box, 2}, {last, u8(first_free_power_port(entities, content.machines, last))}},
		item = test_item(content.items, "light_cable"),
	}
	testing.expect_value(t, cable_placement_refusal(entities, content, loop, max(i64)), Field_Edit_Refusal.None)
	add_cable(entities, content, Cable{ends = loop.ends, item = loop.item, metres = u16(port_span_metres(entities, content.machines, loop.ends[0], loop.ends[1]))})
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect_value(t, len(networks.topology.chords), 1)
}

// The hand run factory ticked once with the engine offering 15,000 J.
ticked_hand_run_factory :: proc(content: Simulation_Content, bundled := false) -> (world: World, factory: Hand_Run_Factory) {
	world = make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	factory = lay_hand_run_factory(&world, content, false, bundled)
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
	return
}

// The cable whose nodes are the chord's, -1 for none.
chord_cable :: proc(networks: ^Electric_Networks, table: ^Cable_Table, chord: netlist.Edge) -> int {
	for cable, index in table.cables {
		first, second := power_port_node(networks, cable.ends[0]), power_port_node(networks, cable.ends[1])
		if u32(min(first, second)) == chord.first && u32(max(first, second)) == chord.second {
			return index
		}
	}
	return -1
}

// Each cable's load from the last balance (0369): none before the first
// tick; with 900 kW offered the light cable carries its 5000 J to the
// assemblers' 6250 J and limits them, the heavy cable carries the engine's
// 5083 J, the lamp's cable its 83 J at capacity without limiting; bundled
// with a heavy cable the two share the assemblers' 6250 J by their watts;
// with a lamp more past it the light cable runs a level's step under its
// capacity and still limits; a cable whose nodes are the chord's reads 0.
@(test)
test_cable_loads_follow_the_tree_flow :: proc(t: ^testing.T) {
	content := make_test_content()
	{
		world := make_floor_world(content.blocks, 32)
		factory := lay_hand_run_factory(&world, content, false)
		entities := &world.entities
		_, found := cable_load(&entities.electric_networks, &entities.cables, port_end_cable(&entities.cables, {factory.first_box, 1}))
		testing.expect(t, !found, "a load before the first balance")
	}
	{
		world, factory := ticked_hand_run_factory(content)
		entities := &world.entities
		networks := &entities.electric_networks
		light, light_found := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.first_box, 1}))
		testing.expect(t, light_found)
		testing.expect_value(t, light, Cable_Load{joules_per_tick = 5000, watts = 300_000, at_capacity = true, limits = true, shortfall = 1250, source_end = 0, network = 0})
		second := networks.node_of_entity[factory.second_box]
		testing.expect_value(t, networks.edge_limits[second].shortfall, 1250)
		heavy, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.engine, 0}))
		testing.expect_value(t, heavy.joules_per_tick, 5083)
		testing.expect_value(t, heavy.watts, 900_000)
		testing.expect(t, !heavy.at_capacity && !heavy.limits, "the heavy cable neither at capacity nor limiting")
		lamp, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.lamp, 0}))
		testing.expect_value(t, lamp.joules_per_tick, 83)
		testing.expect_value(t, lamp.watts, 5000)
		testing.expect(t, lamp.at_capacity && !lamp.limits, "the lamp's cable at capacity and not limiting")
		testing.expect_value(t, lamp.source_end, 1)
	}
	{
		world, factory := ticked_hand_run_factory(content, bundled = true)
		entities := &world.entities
		networks := &entities.electric_networks
		for assembler in factory.assemblers {
			testing.expect_value(t, test_assembler(&world, assembler).power.satisfaction, 1000)
		}
		second := networks.node_of_entity[factory.second_box]
		testing.expect_value(t, abs(networks.outputs[second].flow), 6250)
		testing.expect_value(t, networks.topology.capacity[second], 3_300_000)
		light, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.first_box, 1}))
		heavy, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.first_box, 2}))
		testing.expect_value(t, light.joules_per_tick, 568)
		testing.expect_value(t, heavy.joules_per_tick, 5681)
		testing.expect(t, !light.at_capacity && !heavy.at_capacity, "the bundle is not at capacity")
	}
	{
		// A lamp more past the light cable: 6333 J asked, whole per mille
		// levels deliver 4995 J, so the cable runs 5 J under its capacity,
		// under a level of the region it feeds, and is at capacity.
		world := make_floor_world(content.blocks, 32)
		records := make_test_records(content)
		factory := lay_hand_run_factory(&world, content, false)
		entities := &world.entities
		networks := &entities.electric_networks
		last := entity_at(entities, {8, 3, 0})
		lamp := place_test_entity(&world, content, "lamp", {9, 3, 2})
		lay_test_cable(&world, content, "light_cable", {lamp, 0}, {last, u8(first_free_power_port(entities, content.machines, last))})
		tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
		light, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.first_box, 1}))
		testing.expect_value(t, light.joules_per_tick, 4995)
		testing.expect(t, light.at_capacity && light.limits, "the light cable under its capacity by a level's step is full and limits")
		testing.expect_value(t, light.shortfall, 6333 - 4995)
	}
	{
		world := make_floor_world(content.blocks, 32)
		records := make_test_records(content)
		factory := lay_hand_run_factory(&world, content, false)
		entities := &world.entities
		networks := &entities.electric_networks
		// The loop of test_a_power_switch_splits_its_netlist.
		last := entity_at(entities, {8, 3, 0})
		lay_test_cable(&world, content, "light_cable", {factory.first_box, 2}, {last, u8(first_free_power_port(entities, content.machines, last))})
		tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
		if !testing.expect_value(t, len(networks.topology.chords), 1) {
			return
		}
		load, found := cable_load(networks, &entities.cables, chord_cable(networks, &entities.cables, networks.topology.chords[0]))
		testing.expect(t, found, "the chord's cable reads a load")
		testing.expect_value(t, load.joules_per_tick, 0)
		testing.expect(t, !load.at_capacity, "the chord's cable at capacity")
	}
}

// A second steam engine on a light cable beside the first, at the same
// dispatch order: the solve fills its cable before the first engine covers
// the rest. The first engine offers 200 J and has 117 J left, so the
// assemblers' shortfall behind the boxes' full light cable needs the second
// engine's spare through its full cable: both limit (the series of
// doc/fluids.md, Power).
@(test)
test_a_generator_cable_filled_by_the_dispatch_limits_in_series :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	factory := lay_hand_run_factory(&world, content, false)
	entities := &world.entities
	networks := &entities.electric_networks
	engine := place_test_entity(&world, content, "steam_engine", {-3, 1, 4})
	lay_test_cable(&world, content, "light_cable", {engine, 0}, {factory.first_box, 2})
	second := test_fluid_machine(&world, engine)
	second.buffers[0], second.buffers[1] = EMPTY_FLUID_BUFFER, EMPTY_FLUID_BUFFER
	second.fuel_joules = 15_000
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 200)
	engine_load, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {engine, 0}))
	testing.expect(t, engine_load.limits, "the second engine's light cable does not limit")
	boxes_load, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.first_box, 1}))
	testing.expect(t, boxes_load.limits, "the boxes' light cable does not limit")
}

// The engine on a light cable into the first box with nothing else on it,
// the boxes' light cable on to the assemblers at 800, the engine with
// 10,000 J left: both full cables limit, and the overview counts both.
@(test)
test_two_full_cables_in_series_both_limit :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	factory := lay_hand_run_factory(&world, content, false)
	entities := &world.entities
	networks := &entities.electric_networks
	remove_entity(entities, content.machines, factory.lamp)
	remove_cable(entities, content.machines, port_end_cable(&entities.cables, {factory.engine, 0}))
	lay_test_cable(&world, content, "light_cable", {factory.engine, 0}, {factory.first_box, 0})
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
	testing.expect_value(t, test_assembler(&world, factory.assemblers[0]).power.satisfaction, 800)
	for port in ([2]u8{0, 1}) {
		line, _, limits := power_port_text(entities, content.machines, content.items, {factory.first_box, port}, TEST_TICK_RATE)
		testing.expectf(t, limits, "port %d does not limit: %q", port, line)
	}
	_, count, _ := network_limiting_cables(networks, &entities.cables, entity_network(networks, factory.first_box), POWER_CABLE_ROWS)
	testing.expect_value(t, count, 2)
}

// The engine on a light cable offering exactly the cable's 5000 J: every
// consumer is short because the engine has no more, and no cable limits.
@(test)
test_a_generation_shortage_blames_no_cable :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	factory := lay_hand_run_factory(&world, content, false)
	entities := &world.entities
	networks := &entities.electric_networks
	remove_cable(entities, content.machines, port_end_cable(&entities.cables, {factory.engine, 0}))
	lay_test_cable(&world, content, "light_cable", {factory.engine, 0}, {factory.first_box, 0})
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 5000)
	load, _ := cable_load(networks, &entities.cables, port_end_cable(&entities.cables, {factory.engine, 0}))
	testing.expect(t, !load.limits, "the engine's cable limits in a generation shortage")
	_, count, found := network_limiting_cables(networks, &entities.cables, entity_network(networks, factory.first_box), POWER_CABLE_ROWS)
	testing.expect(t, found, "the network's limiting cables after the tick")
	testing.expect_value(t, count, 0)
}

// insert_ranked_cable keeps the larger shortfalls, ties by the lower
// index, whatever order they come in; network_limiting_cables finds none
// before the first tick and the light cable after it.
@(test)
test_limiting_cables_rank_by_shortfall :: proc(t: ^testing.T) {
	shortfalls := [6]i64{400, 1250, 1250, 90, 1250, 7}
	for reverse in ([2]bool{false, true}) {
		top := make([dynamic]Network_Cable, context.temp_allocator)
		for step in 0 ..< len(shortfalls) {
			index := reverse ? len(shortfalls) - 1 - step : step
			insert_ranked_cable(&top, {index = index, load = {shortfall = shortfalls[index]}}, 3)
		}
		kept := make([dynamic]int, context.temp_allocator)
		for cable in top {
			append(&kept, cable.index)
		}
		testing.expectf(t, slice.equal(kept[:], []int{1, 2, 4}), "reverse %v keeps %v", reverse, kept[:])
	}

	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	factory := lay_hand_run_factory(&world, content, false)
	entities := &world.entities
	_, _, found := network_limiting_cables(&entities.electric_networks, &entities.cables, 0, POWER_CABLE_ROWS)
	testing.expect(t, !found, "limiting cables before the first balance")
	tick_with_hand_run_offer(&world, &records, content, factory.engine, 15_000)
	top, count, after := network_limiting_cables(&entities.electric_networks, &entities.cables, 0, POWER_CABLE_ROWS)
	testing.expect(t, after)
	testing.expect_value(t, count, 1)
	if testing.expect_value(t, len(top), 1) {
		testing.expect_value(t, top[0].index, port_end_cable(&entities.cables, {factory.first_box, 1}))
	}
}

// The first box's port lines, the light cable's overview row and its HUD
// line (0369), before the first tick and after it.
@(test)
test_cable_load_texts :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	content := make_test_content()
	{
		world := make_floor_world(content.blocks, 32)
		factory := lay_hand_run_factory(&world, content, false)
		entities := &world.entities
		line, cabled, limits := power_port_text(entities, content.machines, content.items, {factory.first_box, 1}, TEST_TICK_RATE)
		testing.expect_value(t, line, "Port b: Light cable to Junction box")
		testing.expect(t, cabled && !limits, "port b before the tick")
		hud, _ := cable_status_text(entities, content.items, port_end_cable(&entities.cables, {factory.first_box, 1}), TEST_TICK_RATE)
		testing.expect_value(t, hud, "Light cable")
	}
	world, factory := ticked_hand_run_factory(content)
	entities := &world.entities
	expected := [4]struct {
		line:           string,
		cabled, limits: bool,
	} {
		{"Port a: 305.0 kW of 900.0 kW, Heavy cable from Steam engine", true, false},
		{"Port b, limiting: 300.0 kW of 300.0 kW, Light cable to Junction box", true, true},
		{"Port c: free", false, false},
		{"Port d: 5.0 kW of 5.0 kW, Light cable to Lamp", true, false},
	}
	for entry, port in expected {
		line, cabled, limits := power_port_text(entities, content.machines, content.items, {factory.first_box, u8(port)}, TEST_TICK_RATE)
		testing.expectf(t, line == entry.line && cabled == entry.cabled && limits == entry.limits, "port %d: %q cabled %v limits %v", port, line, cabled, limits)
	}
	top, _, _ := network_limiting_cables(&entities.electric_networks, &entities.cables, 0, POWER_CABLE_ROWS)
	if testing.expect_value(t, len(top), 1) {
		testing.expect_value(t, power_cable_text(entities, content.machines, content.items, top[0], TEST_TICK_RATE), "Light cable, Junction box to Junction box: 300.0 kW of 300.0 kW")
	}
	hud, limits := cable_status_text(entities, content.items, port_end_cable(&entities.cables, {factory.first_box, 1}), TEST_TICK_RATE)
	testing.expect_value(t, hud, "Light cable: 300.0 kW of 300.0 kW, limiting")
	testing.expect(t, limits, "the light cable's HUD line limits")
}

// Each refusal of cable_placement_refusal once, in the block world, and
// Not_A_Connector between a vessel and the ground; a second cable between
// the same two boxes is laid and their bundled edge carries the sum.
@(test)
test_cable_placement_refusals :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	entities := &world.entities
	first := place_test_entity(&world, content, "junction_box", {0, 1, 0})
	second := place_test_entity(&world, content, "junction_box", {5, 1, 0})
	far := place_test_entity(&world, content, "junction_box", {27, 1, 0})
	chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 2})
	light, heavy := test_item(content.items, "light_cable"), test_item(content.items, "heavy_cable")
	cases := [?]struct {
		first, second: Port_End,
		held:          i64,
		refusal:       Field_Edit_Refusal,
	} {
		{{chest, 0}, {second, 0}, 100, .Cable_End_Gone},
		{{first, 1}, {chest, 0}, 100, .No_Free_Port},
		{{first, 1}, {first, 0}, 100, .Same_Thing},
		// From x 6 to x 27: 21 m on a 20 m span.
		{{second, 1}, {far, 0}, 100, .Cable_Too_Short},
		// From x 1 to x 5.
		{{first, 1}, {second, 0}, 3, .Not_Enough_Cable},
		{{first, 1}, {second, 0}, 4, .None},
	}
	for entry in cases {
		placement := Cable_Placement{ends = {entry.first, entry.second}, item = light}
		testing.expectf(t, cable_placement_refusal(entities, content, placement, entry.held) == entry.refusal, "%v to %v: %v", entry.first, entry.second, cable_placement_refusal(entities, content, placement, entry.held))
	}
	testing.expect_value(t, port_span_metres(entities, content.machines, {first, 1}, {second, 0}), 4)
	lay_test_cable(&world, content, "light_cable", {first, 1}, {second, 0})
	testing.expect_value(t, cable_placement_refusal(entities, content, {ends = {{first, 1}, {second, 2}}, item = light}, 100), Field_Edit_Refusal.Cable_End_Gone)
	testing.expect_value(t, cable_placement_refusal(entities, content, {ends = {{first, 2}, {second, 0}}, item = light}, 100), Field_Edit_Refusal.No_Free_Port)

	bundled := Cable_Placement{ends = {{first, 3}, {second, 3}}, item = heavy}
	testing.expect_value(t, cable_placement_refusal(entities, content, bundled, 100), Field_Edit_Refusal.None)
	add_cable(entities, content, Cable{ends = bundled.ends, item = heavy, metres = u16(port_span_metres(entities, content.machines, bundled.ends[0], bundled.ends[1]))})
	networks := &entities.electric_networks
	child := networks.node_of_entity[second]
	if networks.topology.parent[child] == netlist.NO_NODE {
		child = networks.node_of_entity[first]
	}
	testing.expect_value(t, networks.topology.capacity[child], 300_000 + 3_000_000)
	testing.expect_value(t, len(networks.topology.chords), 0)

	// A vessel takes a cable from the ground on its connector only; within
	// the vessel any part's port.
	simulation, field_content, items := make_vessel_test()
	defer destroy_simulation(&simulation)
	vessel_entities := &simulation.world.entities
	pad := lay_test_pad(vessel_entities, field_content.machines, 0, 0, {0, 0, 0}, {1, 0, 1})
	ground, _ := place_on_frame(vessel_entities, field_content.machines, test_machine(field_content.machines, "junction_box"), pad.id, {0, 1, 0}, 0)
	_, vessel := start_test_vessel(&simulation, field_content, "iron_truss", 4 * POSITION_UNITS_PER_METRE, 0)
	battery := add_test_vessel_part(&simulation, field_content, "lead_battery", vessel.id, {0, 1, 0})
	connector := add_test_vessel_part(&simulation, field_content, "docking_connector", vessel.id, {0, 2, 0})
	field_light := test_item(items, "light_cable")
	vessel_cases := [?]struct {
		first, second: Port_End,
		refusal:       Field_Edit_Refusal,
	} {
		{{ground, 0}, {battery, 0}, .Not_A_Connector},
		{{battery, 1}, {ground, 1}, .Not_A_Connector},
		{{ground, 0}, {connector, 0}, .None},
		{{battery, 0}, {connector, 0}, .None},
	}
	for entry in vessel_cases {
		placement := Cable_Placement{ends = {entry.first, entry.second}, item = field_light}
		testing.expectf(t, cable_placement_refusal(vessel_entities, field_content, placement, 100) == entry.refusal, "%v to %v", entry.first, entry.second)
	}
}

// The field cable tests' pad on the flat site: frame cells -4 to 16 along
// x and -4 to 4 along z at 500 mm.
lay_cable_test_pad :: proc(simulation: ^Simulation_State, content: Simulation_Content) -> Frame {
	return lay_test_pad(&simulation.world.entities, content.machines, 0, 0, {-4, 0, -4}, {16, 0, 4})
}

place_on_test_pad :: proc(simulation: ^Simulation_State, content: Simulation_Content, frame: Frame, id: string, cell: World_Coordinate) -> Entity_Handle {
	handle, refusal := place_on_frame(&simulation.world.entities, content.machines, test_machine(content.machines, id), frame.id, cell, 0)
	assert(refusal == .None, id)
	return handle
}

// Player 0 looks at the point; the next tick aims there.
look_test_player_at :: proc(simulation: ^Simulation_State, content: Simulation_Content, point: World_Position) {
	look_field_player_at(&simulation.players[0].field, content.field.tuning, point)
}

// One tick with player 0's input.
press_test_input :: proc(simulation: ^Simulation_State, content: Simulation_Content, input: Field_Player_Input) {
	inputs := [1]Field_Player_Input{input}
	tick_field_simulation(simulation, content, inputs[:])
}

TEST_PRESS_PLACE :: Field_Player_Input {
	held         = {.Place},
	just_pressed = {.Place},
}
TEST_PRESS_DIG :: Field_Player_Input {
	held         = {.Dig},
	just_pressed = {.Dig},
}

// Place on the box's positive_x face begins a run there.
begin_test_run :: proc(simulation: ^Simulation_State, content: Simulation_Content, frame: Frame, box: World_Coordinate) {
	look_test_player_at(simulation, content, frame_face_centre(frame, box, .Positive_X))
	press_test_input(simulation, content, TEST_PRESS_PLACE)
}

// The middle of the cable's curve.
test_cable_middle :: proc(entities: ^Entities, machines: Machine_Registry, index: int) -> World_Position {
	first, second, down, sag, _ := cable_curve(entities, machines, entities.cables.cables[index])
	return cable_curve_point(first, second, down, sag, 1, 2)
}

// The run on a pad with a junction box, a fuel generator and a chest:
// Place on the box's positive_x face begins it on port b and the tool line
// shows the span left; a refused Place keeps it; Place on the generator
// lays the cable; Mine takes a run back and nothing else, Sneak and Back
// keep it; another slot ends it; the box picked up by another player ends
// it with Cable_End_Gone; a torch aimed during a run stays under the take
// back.
@(test)
test_field_cable_run_controls :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	use_shipped_strings()
	defer thread_string_table = nil
	content.field.torch_item = test_item(items, "torch")
	entities := &simulation.world.entities
	frame := lay_cable_test_pad(&simulation, content)
	box_cell := World_Coordinate{2, 1, 0}
	box := place_on_test_pad(&simulation, content, frame, "junction_box", box_cell)
	generator := place_on_test_pad(&simulation, content, frame, "fuel_generator", {2, 1, -4})
	place_on_test_pad(&simulation, content, frame, "wooden_chest", {2, 1, 3})
	stand_test_player_on_cell(&simulation, content, items, frame, {5, 0, 0}, {"light_cable", 100})
	add_test_miner(&simulation, items, FAR_FEET)
	player := &simulation.players[0]
	hold_test_item(player, content, "light_cable")
	testing.expect_value(t, player.field.tool, Field_Held_Tool.Cable)
	light := test_item(items, "light_cable")

	begin_test_run(&simulation, content, frame, box_cell)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, player.field.cable_run, "Place on the box begins a run")
	testing.expect_value(t, player.field.cable_start, Port_End{box, 1})
	line, shown := field_tool_line(player.field, content, .None, 1000, entities, light)
	testing.expectf(t, shown && strings.has_prefix(line, "Light cable: ") && strings.has_suffix(line, " m of the span left"), "the tool line %q", line)

	look_test_player_at(&simulation, content, frame_cell_centre(frame, {2, 1, 3}))
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.No_Free_Port)
	testing.expect(t, player.field.cable_run, "a refused Place keeps the run")

	look_test_player_at(&simulation, content, frame_face_centre(frame, {3, 1, -3}, .Positive_X))
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, !player.field.cable_run, "the cable laid ends the run")
	testing.expect_value(t, len(entities.cables.cables), 1)
	testing.expect_value(t, port_end_cable(&entities.cables, {generator, 0}), 0)
	testing.expect_value(t, port_end_cable(&entities.cables, {box, 1}), 0)
	metres := int(entities.cables.cables[0].metres)
	testing.expect_value(t, i64(metres), port_span_metres(entities, content.machines, {box, 1}, {generator, 0}))
	testing.expect_value(t, inventory_count(player.inventory, light), 100 - metres)
	testing.expect_value(t, simulation.records.statistics.cables_run, 1)

	// Mine takes a run back: the pad cell it aims at gets no pick up and
	// the field no dig.
	begin_test_run(&simulation, content, frame, box_cell)
	testing.expect(t, player.field.cable_run, "a second run begins on a free port")
	cells := frame_cell_count(&entities.frames, frame.id)
	field_before := field_state_hash(&simulation.field, 0)
	look_test_player_at(&simulation, content, frame_cell_centre(frame, {4, 0, 0}))
	press_test_input(&simulation, content, TEST_PRESS_DIG)
	testing.expect(t, !player.field.cable_run, "Mine takes the run back")
	testing.expect(t, !player.mining.active, "the Mine went to the run")
	testing.expect_value(t, frame_cell_count(&entities.frames, frame.id), cells)
	testing.expect_value(t, field_state_hash(&simulation.field, 0), field_before)
	testing.expect_value(t, len(entities.cables.cables), 1)

	// Back's control carries Sneak, so a crouch keeps the run.
	begin_test_run(&simulation, content, frame, box_cell)
	press_test_input(&simulation, content, {held = {.Sneak, .Back}, just_pressed = {.Sneak, .Back}})
	testing.expect(t, player.field.cable_run, "Sneak and Back keep the run")
	press_test_input(&simulation, content, TEST_PRESS_DIG)
	testing.expect(t, !player.field.cable_run)

	begin_test_run(&simulation, content, frame, box_cell)
	player.selected_hotbar_slot = 1
	press_test_input(&simulation, content, {})
	testing.expect(t, !player.field.cable_run, "another slot ends the run")
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	player.selected_hotbar_slot = 0

	begin_test_run(&simulation, content, frame, box_cell)
	testing.expect(t, player.field.cable_run)
	append(&simulation.field.placements, Queued_Field_Placement{player = 1, placement = Field_Placement{kind = .Pick_Up, frame = frame.id, cell = box_cell}})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, entity_at(entities, box_cell, frame.id), NO_ENTITY)
	press_test_input(&simulation, content, {})
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Cable_End_Gone)
	testing.expect(t, !player.field.cable_run, "the first end gone ends the run")

	// A torch a metre and a half ahead: the run's Mine takes the run back
	// and leaves the torch; with no run the same press takes the torch.
	place_on_test_pad(&simulation, content, frame, "junction_box", box_cell)
	begin_test_run(&simulation, content, frame, box_cell)
	testing.expect(t, player.field.cable_run)
	player.field.pitch = 0
	tuning := content.field.tuning
	ahead := field_player_eye(player.field, tuning) + World_Position(fixed_scale(field_look_direction(player.field.forward, player.field.up, player.field.yaw, 0), 3 * POSITION_UNITS_PER_METRE / 2))
	torch := world_position_to_sample(ahead, simulation.field.spacing_millimetres)
	append(&simulation.field.torches, Field_Torch{sample = torch})
	look_test_player_at(&simulation, content, sample_to_world_position(torch, simulation.field.spacing_millimetres))
	mine := Input_Frame {
		pressed      = {.Mine},
		just_pressed = {.Mine},
	}
	simulation.tick += 1
	tick_field_session_player(&simulation, content, 0, mine)
	finish_field_tick(&simulation, content)
	testing.expect(t, !player.field.cable_run, "the run's Mine takes it back")
	testing.expect_value(t, len(simulation.field.torches), 1)
	simulation.tick += 1
	tick_field_session_player(&simulation, content, 0, mine)
	finish_field_tick(&simulation, content)
	testing.expect_value(t, len(simulation.field.torches), 0)
}

// Mine held on a cable for PICK_UP_SECONDS takes it up and adds its metres,
// with a shovel held as with a cable, and nothing else digs; with no room
// Inventory_Full and the cable stays; beyond the reach or behind a frame
// cell nothing happens.
@(test)
test_taking_up_a_cable_returns_its_metres :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	frame := lay_cable_test_pad(&simulation, content)
	south := place_on_test_pad(&simulation, content, frame, "junction_box", {2, 1, -3})
	north := place_on_test_pad(&simulation, content, frame, "junction_box", {2, 1, 3})
	ends := [2]Port_End{{south, 3}, {north, 2}}
	lay_test_cable(&simulation.world, content, "light_cable", ends[0], ends[1])
	metres := int(entities.cables.cables[0].metres)
	middle := test_cable_middle(entities, content.machines, 0)
	stand_test_player_on_cell(&simulation, content, items, frame, {6, 0, 0}, {"wooden_shovel", 1})
	player := &simulation.players[0]
	light := test_item(items, "light_cable")
	cells := frame_cell_count(&entities.frames, frame.id)
	for tool, round in ([?]string{"wooden_shovel", "light_cable"}) {
		hold_test_item(player, content, tool)
		look_test_player_at(&simulation, content, middle)
		tick_field_simulation(&simulation, content, {})
		testing.expectf(t, field_aimed_cable(entities, content.machines, player.field, content.field.tuning) == 0, "%s: the reticle meets the cable", tool)
		field_before := field_state_hash(&simulation.field, 0)
		hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS - 1)
		testing.expectf(t, len(entities.cables.cables) == 1, "%s: the cable stays a tick short", tool)
		testing.expect_value(t, player.field.cable_take_up_ticks, u32(PICK_UP_TEST_TICKS - 1))
		testing.expect(t, mining_fraction(cable_take_up_mining_state(player.field, simulation.tick_rate)) > 0.9, "the ring the HUD draws")
		hold_test_mine(&simulation, content, 1)
		testing.expectf(t, len(entities.cables.cables) == 0, "%s: the cable is taken up", tool)
		testing.expect_value(t, inventory_count(player.inventory, light), (round + 1) * metres)
		testing.expect_value(t, field_state_hash(&simulation.field, 0), field_before)
		testing.expect_value(t, frame_cell_count(&entities.frames, frame.id), cells)
		lay_test_cable(&simulation.world, content, "light_cable", ends[0], ends[1])
	}

	// A run begun, then carried, with Mine held: the take up's count is
	// zero on both ticks, so the ring does not stand still.
	look_test_player_at(&simulation, content, middle)
	hold_test_mine(&simulation, content, 5)
	testing.expect_value(t, player.field.cable_take_up_ticks, 5)
	look_test_player_at(&simulation, content, frame_face_centre(frame, {2, 1, 3}, .Positive_X))
	press_test_input(&simulation, content, {held = {.Dig, .Place}, just_pressed = {.Place}})
	testing.expect(t, player.field.cable_run, "Place on the box begins a run")
	testing.expect_value(t, player.field.cable_take_up_ticks, 0)
	look_test_player_at(&simulation, content, middle)
	player.field.cable_take_up_ticks = 7
	press_test_input(&simulation, content, {held = {.Dig}})
	testing.expect(t, player.field.cable_run)
	testing.expect_value(t, player.field.cable_take_up_ticks, 0)
	press_test_input(&simulation, content, TEST_PRESS_DIG)
	testing.expect(t, !player.field.cable_run)
	testing.expect_value(t, len(entities.cables.cables), 1)

	stone := test_item(items, "stone")
	saved := make([]Item_Stack, len(player.inventory.slots), context.temp_allocator)
	copy(saved, player.inventory.slots)
	for &slot in player.inventory.slots {
		slot = Item_Stack{item = stone, count = item_stack_size(items, stone)}
	}
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS + 4)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Inventory_Full)
	testing.expect_value(t, len(entities.cables.cables), 1)
	copy(player.inventory.slots, saved)

	// Seven metres away, past the 4 m reach; a few ticks short of picking
	// up the pad cell the reticle meets instead.
	up := World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2))
	player.field.position = frame_cell_centre(frame, {16, 0, 0}) + up
	look_test_player_at(&simulation, content, middle)
	tick_field_simulation(&simulation, content, {})
	testing.expect_value(t, field_aimed_cable(entities, content.machines, player.field, content.field.tuning), -1)
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS - 6)
	testing.expect_value(t, len(entities.cables.cables), 1)
	testing.expect_value(t, player.field.cable_take_up_ticks, 0)

	// A column of foundations between the player and the cable.
	tick_field_simulation(&simulation, content, {})
	player.field.position = frame_cell_centre(frame, {6, 0, 0}) + up
	for y in i32(1) ..= 3 {
		place_on_test_pad(&simulation, content, frame, "wooden_foundation", {3, y, 0})
	}
	look_test_player_at(&simulation, content, middle)
	tick_field_simulation(&simulation, content, {})
	testing.expect(t, player.field.frame_target.hit && player.field.frame_target.cell.x == 3, "the reticle meets the column")
	testing.expect_value(t, field_aimed_cable(entities, content.machines, player.field, content.field.tuning), -1)
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS - 6)
	testing.expect_value(t, len(entities.cables.cables), 1)
	testing.expect_value(t, player.field.cable_take_up_ticks, 0)
}

// The labels of the hints on the button, in order.
hint_labels_on :: proc(hints: []Glyph_Hint, button: Glyph_Button) -> []string {
	labels := make([dynamic]string, context.temp_allocator)
	for hint in hints {
		if hint.button == button {
			append(&labels, hint.label)
		}
	}
	return labels[:]
}

// A power switch with a cable crossing in front of it inside the aim
// radius shows Turn beside Take up; during a run Mine shows only Take
// back, aimed at the switch, a junction box or a trunk, and the switch
// keeps its Turn.
@(test)
test_the_glyph_bar_during_a_run_and_on_a_switch_behind_a_cable :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	use_shipped_strings()
	defer thread_string_table = nil
	entities := &simulation.world.entities
	frame := lay_cable_test_pad(&simulation, content)
	place_on_test_pad(&simulation, content, frame, "power_switch", {2, 1, 0})
	south := place_on_test_pad(&simulation, content, frame, "junction_box", {3, 1, -2})
	north := place_on_test_pad(&simulation, content, frame, "junction_box", {3, 1, 2})
	lay_test_cable(&simulation.world, content, "light_cable", {south, 3}, {north, 2})
	stand_test_player_on_cell(&simulation, content, items, frame, {6, 0, 0}, {"light_cable", 100})
	player := &simulation.players[0]
	hold_test_item(player, content, "light_cable")
	screen_context := Screen_Context{content = content, world = &simulation.world, player = player}
	hud := Hud_Context{field_session = true}
	// The switch's +x face 150 mm under its centre: the look passes the
	// cable a cell before it.
	below := World_Position(fixed_scale(frame.axes[FRAME_UP], -millimetres_to_position_units(150)))
	switch_point := frame_face_centre(frame, {2, 1, 0}, .Positive_X) + below
	aim_at_switch :: proc(simulation: ^Simulation_State, content: Simulation_Content, point: World_Position) {
		look_test_player_at(simulation, content, point)
		tick_field_simulation(simulation, content, {})
	}
	aim_at_switch(&simulation, content, switch_point)
	testing.expect(t, field_target_is_power_switch(screen_context, hud), "the reticle meets the switch")
	testing.expect_value(t, field_aimed_cable(entities, content.machines, player.field, content.field.tuning), 0)
	// The cable the HUD's name line reads (0369), and the take up hint from
	// draw_hud's one scan or from its own.
	testing.expect_value(t, hud_aimed_cable(screen_context, hud), 0)
	none_aimed := hud
	none_aimed.aimed_cable = -1
	testing.expect(t, !field_take_up_hint_shown(screen_context, none_aimed), "the take up hint reads the HUD's -1")
	testing.expect(t, field_take_up_hint_shown(screen_context, hud), "the take up hint looks the cable up")
	aimed := aimed_glyph_hints(screen_context, hud)
	testing.expectf(t, slice.equal(hint_labels_on(aimed, .Interact), []string{"Turn"}), "Interact %v", hint_labels_on(aimed, .Interact))
	testing.expectf(t, slice.equal(hint_labels_on(aimed, .Mine), []string{"Take up"}), "Mine %v", hint_labels_on(aimed, .Mine))

	begin_test_run(&simulation, content, frame, {3, 1, 2})
	testing.expect(t, player.field.cable_run, "Place on the box begins a run")
	aim_at_switch(&simulation, content, switch_point)
	testing.expect_value(t, hud_aimed_cable(screen_context, hud), -1)
	all, _ := world_glyph_hints(screen_context, hud)
	testing.expectf(t, slice.equal(hint_labels_on(all, .Interact), []string{"Turn"}), "the run's Interact %v", hint_labels_on(all, .Interact))
	testing.expectf(t, slice.equal(hint_labels_on(all, .Mine), []string{"Take back"}), "the run's Mine on the switch %v", hint_labels_on(all, .Mine))
	look_test_player_at(&simulation, content, frame_face_centre(frame, {3, 1, -2}, .Positive_X))
	tick_field_simulation(&simulation, content, {})
	testing.expect(t, field_pick_up_hint_shown(screen_context, hud), "the reticle meets the box")
	all, _ = world_glyph_hints(screen_context, hud)
	testing.expectf(t, slice.equal(hint_labels_on(all, .Mine), []string{"Take back"}), "the run's Mine on the box %v", hint_labels_on(all, .Mine))
	trunk := Hud_Context{field_session = true, field_view_set = true, field_view = player.field}
	trunk.field_view.tree_target.hit = true
	all, _ = world_glyph_hints(screen_context, trunk)
	testing.expectf(t, slice.equal(hint_labels_on(all, .Mine), []string{"Take back"}), "the run's Mine on a trunk %v", hint_labels_on(all, .Mine))
}

// On the field a junction box comes up with its cable's metres, and is
// refused Inventory_Full when they do not fit; in the block world they
// spill with it.
@(test)
test_picking_up_a_machine_returns_its_cables :: proc(t: ^testing.T) {
	{
		simulation, content, items := make_pick_up_test()
		defer destroy_simulation(&simulation)
		entities := &simulation.world.entities
		frame := lay_cable_test_pad(&simulation, content)
		south := place_on_test_pad(&simulation, content, frame, "junction_box", {2, 1, -3})
		north := place_on_test_pad(&simulation, content, frame, "junction_box", {2, 1, 3})
		lay_test_cable(&simulation.world, content, "light_cable", {south, 3}, {north, 2})
		metres := int(entities.cables.cables[0].metres)
		add_test_miner(&simulation, items, FAR_FEET)
		player := &simulation.players[0]
		stone := test_item(items, "stone")
		// Room for the box, none for the metres.
		for &slot in player.inventory.slots[1:] {
			slot = Item_Stack{item = stone, count = item_stack_size(items, stone)}
		}
		pick_up := Queued_Field_Placement{player = 0, placement = Field_Placement{kind = .Pick_Up, frame = frame.id, cell = {2, 1, -3}}}
		append(&simulation.field.placements, pick_up)
		drain_field_placements(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Inventory_Full)
		testing.expect_value(t, entity_at(entities, {2, 1, -3}, frame.id), south)
		testing.expect_value(t, len(entities.cables.cables), 1)
		for &slot in player.inventory.slots {
			slot = {}
		}
		// The tick resets the refusal before its queue (queue_field_player_edit).
		player.field_refusal = .None
		append(&simulation.field.placements, pick_up)
		drain_field_placements(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
		testing.expect_value(t, entity_at(entities, {2, 1, -3}, frame.id), NO_ENTITY)
		testing.expect_value(t, inventory_count(player.inventory, test_item(items, "junction_box")), 1)
		testing.expect_value(t, inventory_count(player.inventory, test_item(items, "light_cable")), metres)
		testing.expect_value(t, len(entities.cables.cables), 0)
		testing.expect(t, port_end_is_free(entities, content.machines, {north, 2}), "the other end's port is free")
	}
	{
		content := make_test_content()
		world := make_floor_world(content.blocks, 32)
		records := make_test_records(content)
		first := place_test_entity(&world, content, "junction_box", {0, 1, 0})
		second := place_test_entity(&world, content, "junction_box", {5, 1, 0})
		lay_test_cable(&world, content, "light_cable", {first, 1}, {second, 0})
		player := make_player(Player_Start{})
		defer destroy_player(player)
		stone := test_item(content.items, "stone")
		for &slot in player.inventory.slots {
			slot = Item_Stack{item = stone, count = item_stack_size(content.items, stone)}
		}
		testing.expect(t, pick_up_entity(&world, &records.statistics, content, &player, first, 0))
		testing.expect_value(t, len(world.entities.cables.cables), 0)
		spilled: [2]int
		for loose in world.entities.loose_items.items {
			switch loose.item {
			case test_item(content.items, "light_cable"):
				spilled[0] += int(loose.count)
			case test_item(content.items, "junction_box"):
				spilled[1] += int(loose.count)
			}
		}
		testing.expect_value(t, spilled, [2]int{4, 1})
	}
}

// port_span_metres rounds up; the sag never reaches below the lower
// port's cell bottom at any pitch; cables of one span sag differently;
// field_aimed_cable finds a cable's middle and not a point 300 mm beside
// it.
@(test)
test_cable_spans_and_sag :: proc(t: ^testing.T) {
	content := make_test_content()
	machines := content.machines
	{
		entities: Entities
		defer destroy_entities(&entities)
		box := test_machine(machines, "junction_box")
		first := add_entity(&entities, machines, box, {0, 1, 0}, 0)
		level := add_entity(&entities, machines, box, {6, 1, 0}, 0)
		aside := add_entity(&entities, machines, box, {6, 1, 1}, 0)
		testing.expect_value(t, port_span_metres(&entities, machines, {first, 1}, {level, 0}), 5)
		testing.expect_value(t, port_span_metres(&entities, machines, {first, 1}, {aside, 0}), 6)
		testing.expect_value(t, chord_metres({}, {}), 1)
	}
	sags := make(map[i64]bool, context.temp_allocator)
	for index in 0 ..< 16 {
		cable := Cable {
			ends = {{{kind = .Pole, index = u32(index)}, 0}, {{kind = .Pole, index = u32(index + 100)}, 1}},
		}
		for pitch in ([?]int{333, 500, 1000}) {
			for span in ([?]i64{1000, 20_000, 100_000}) {
				sag := cable_sag_millimetres(cable, span, pitch)
				testing.expectf(t, sag >= 0 && 2 * sag <= i64(pitch), "cable %d at %d mm over %d mm sags %d mm", index, pitch, span, sag)
			}
		}
		sags[cable_sag_millimetres(cable, 10_000, 1000)] = true
	}
	testing.expect(t, len(sags) > 1, "cables of one span sag alike")

	entities: Entities
	defer destroy_entities(&entities)
	frame := lay_test_pad(&entities, machines, 0, 0, {-4, 0, -4}, {6, 0, 4})
	box := test_machine(machines, "junction_box")
	south, _ := place_on_frame(&entities, machines, box, frame.id, {0, 1, -3}, 0)
	north, _ := place_on_frame(&entities, machines, box, frame.id, {0, 1, 3}, 0)
	add_cable(&entities, content, Cable{ends = {{south, 3}, {north, 2}}, item = test_item(content.items, "light_cable"), metres = 3})
	tuning := test_field_tuning(1000)
	feet := frame_cell_centre(frame, {4, 0, 0}) + World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2))
	player := make_field_player(feet, {UNIT_VECTOR_ONE, 0, 0})
	middle := test_cable_middle(&entities, machines, 0)
	testing.expect(t, look_field_player_at(&player, tuning, middle))
	testing.expect_value(t, field_aimed_cable(&entities, machines, player, tuning), 0)
	// Across both the cable and the look, on the side away from the frame's
	// up, so the curve rising towards its ends only moves away.
	first, second, _, _, _ := cable_curve(&entities, machines, entities.cables.cables[0])
	along, _ := normalize_fixed(cast([3]i64)(second - first))
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	beside, _ := normalize_fixed(fixed_cross(look, along))
	if fixed_dot(beside, frame.axes[FRAME_UP]) > 0 {
		beside = -beside
	}
	testing.expect(t, look_field_player_at(&player, tuning, middle + World_Position(fixed_scale(beside, millimetres_to_position_units(300)))))
	testing.expect_value(t, field_aimed_cable(&entities, machines, player, tuning), -1)
}

// The 12 boxes of a cable (0384) join end to end at its curve's points,
// each the item's thickness across, and carry its varied colour; the
// cable is near an eye at its middle, not 40 m from its box, never
// without a view.
@(test)
test_cable_instances_follow_the_curve :: proc(t: ^testing.T) {
	content := make_test_content()
	machines := content.machines
	entities: Entities
	defer destroy_entities(&entities)
	frame := lay_test_pad(&entities, machines, 0, 0, {-4, 0, -4}, {6, 0, 4})
	box := test_machine(machines, "junction_box")
	south, _ := place_on_frame(&entities, machines, box, frame.id, {0, 1, -3}, 0)
	north, _ := place_on_frame(&entities, machines, box, frame.id, {0, 1, 3}, 0)
	cable := Cable{ends = {{south, 3}, {north, 2}}, item = test_item(content.items, "heavy_cable"), metres = 3}
	add_cable(&entities, content, cable)
	look, found := cable_look(&entities, machines, content.items, Cable_Draw{daylight_tint = {1, 1, 1}}, cable)
	if !testing.expect(t, found) {
		return
	}
	color := cable_draw_color(content.items.items[cable.item].cable_color, cable, {1, 1, 1})
	testing.expect_value(t, look.color, color)
	testing.expect_value(t, look.thickness_metres, f32(0.024))
	segments := make([dynamic]matrix[4, 4]f32, context.temp_allocator)
	append_cable_segment_instances(&segments, look)
	if !testing.expect_value(t, len(segments), CABLE_CURVE_STEPS) {
		return
	}
	// The points lie 8 km from the planet's centre, where an f32 steps by
	// half a millimetre.
	near :: proc(first, second: [3]f32) -> bool {
		return linalg.length(first - second) < 1e-3
	}
	for instance, step in segments {
		start := (instance * [4]f32{0, 0, -0.5, 1}).xyz
		end := (instance * [4]f32{0, 0, 0.5, 1}).xyz
		testing.expectf(t, near(start, look.points[step]) && near(end, look.points[step + 1]), "segment %d runs %v to %v, not %v to %v", step, start, end, look.points[step], look.points[step + 1])
		across := [3]f32{instance[0, 0], instance[1, 0], instance[2, 0]}
		beside := [3]f32{instance[0, 1], instance[1, 1], instance[2, 1]}
		along := [3]f32{instance[0, 2], instance[1, 2], instance[2, 2]}
		testing.expectf(t, along == look.points[step + 1] - look.points[step], "segment %d is not its points' difference along", step)
		testing.expectf(t, abs(linalg.length(across) - look.thickness_metres) < 1e-6 && abs(linalg.length(beside) - look.thickness_metres) < 1e-6, "segment %d is not the thickness across", step)
		testing.expectf(t, abs(linalg.dot(across, along)) < 1e-6 && abs(linalg.dot(beside, along)) < 1e-6 && abs(linalg.dot(across, beside)) < 1e-8, "segment %d is skewed", step)
		testing.expectf(t, linalg.dot(linalg.cross(across, beside), along) > 0, "segment %d turns the cube inside out", step)
		bottom := [4]f32{instance[3, 0], instance[3, 1], instance[3, 2], instance[3, 3]}
		testing.expect_value(t, bottom, [4]f32{f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, 1})
	}
	testing.expect(t, look.points[CABLE_CURVE_STEPS / 2] != (look.points[0] + look.points[CABLE_CURVE_STEPS]) / 2, "the cable does not sag")

	testing.expect_value(t, look.box_metres, f32(CABLE_BOX_METRES))
	minimum, maximum := cable_draw_box(look.points, look.thickness_metres)
	view := Model_View{eye = look.points[CABLE_CURVE_STEPS / 2], transform = 1}
	testing.expect(t, cable_box_is_near(&view, minimum, maximum, look.box_metres))
	view.eye = maximum + {0, 40, 0}
	testing.expect(t, !cable_box_is_near(&view, minimum, maximum, look.box_metres))
	view.eye = maximum + {0, CABLE_BOX_METRES - 1, 0}
	testing.expect(t, cable_box_is_near(&view, minimum, maximum, look.box_metres))
	testing.expect(t, !cable_box_is_near(nil, minimum, maximum, look.box_metres))
}

// The box distance follows the line's thickness (0374): every shipped
// cable keeps CABLE_BOX_METRES, the 150 mm pipe draws its boxes until they
// are a pixel wide at 1080 lines under 70 degrees (115.7 m), and the
// thickest pipe stops at CABLE_BOX_MAXIMUM_METRES.
@(test)
test_a_lines_box_distance_follows_its_thickness :: proc(t: ^testing.T) {
	content := make_test_content()
	for id in ([]string{"light_cable", "heavy_cable", "trunk_cable"}) {
		figures, found := item_line_figures(content.items, test_item(content.items, id))
		testing.expect(t, found, id)
		testing.expectf(t, cable_box_metres(cable_thickness_metres(figures)) == CABLE_BOX_METRES, "%s draws its boxes to %v m", id, cable_box_metres(cable_thickness_metres(figures)))
	}
	pipe, found := item_line_figures(content.items, test_item(content.items, "pipe"))
	testing.expect(t, found)
	pipe_metres := cable_box_metres(cable_thickness_metres(pipe))
	testing.expectf(t, abs(pipe_metres - 115.7) < 0.1, "the pipe draws its boxes to %v m", pipe_metres)
	testing.expect_value(t, cable_box_metres(f32(MAXIMUM_PIPE_THICKNESS_MILLIMETRES) / MILLIMETRES_PER_METRE), f32(CABLE_BOX_MAXIMUM_METRES))
	// A pipe's box seen from 100 m is near, from 120 m not.
	points: Cable_Draw_Points
	for &point, step in points {
		point = {f32(step), 0, 0}
	}
	minimum, maximum := cable_draw_box(points, 0.15)
	view := Model_View{eye = maximum + {0, 100, 0}, transform = 1}
	testing.expect(t, cable_box_is_near(&view, minimum, maximum, pipe_metres))
	view.eye = maximum + {0, 120, 0}
	testing.expect(t, !cable_box_is_near(&view, minimum, maximum, pipe_metres))
}

// A box corner's offset from the centre of the box's end face.
cable_box_corner_offset :: proc(instance: matrix[4, 4]f32, corner: [2]f32) -> [3]f32 {
	return (instance * [4]f32{corner.x, corner.y, 0, 0}).xyz
}

// The look's segments lean across a world y of 0.9, where a side axis per
// segment would turn the boxes; at every joint each corner's offset from
// the joint is the same on both boxes within 1 mm (the joints themselves
// are test_cable_instances_follow_the_curve's).
expect_cable_joints_meet :: proc(t: ^testing.T, look: Cable_Look, name: string) {
	lowest, highest := f32(1), f32(0)
	for step in 0 ..< CABLE_CURVE_STEPS {
		height := abs(linalg.normalize(look.points[step + 1] - look.points[step]).y)
		lowest, highest = min(lowest, height), max(highest, height)
	}
	testing.expectf(t, lowest < 0.9 && highest >= 0.9, "%s: the segments' world y runs %v to %v, not across 0.9", name, lowest, highest)
	segments := make([dynamic]matrix[4, 4]f32, context.temp_allocator)
	append_cable_segment_instances(&segments, look)
	for step in 0 ..< CABLE_CURVE_STEPS - 1 {
		for corner in ([4][2]f32{{-0.5, -0.5}, {0.5, -0.5}, {0.5, 0.5}, {-0.5, 0.5}}) {
			moved := linalg.length(cable_box_corner_offset(segments[step], corner) - cable_box_corner_offset(segments[step + 1], corner))
			testing.expectf(t, moved < 1e-3, "%s: joint %d's corner %v moves %v m", name, step, corner, moved)
		}
	}
}

// A trunk cable's boxes meet at every joint (0384): steep and diagonal in
// the block world, and level on a frame leaning 64 degrees from world y
// along its forward.
@(test)
test_cable_boxes_meet_at_every_joint :: proc(t: ^testing.T) {
	content := make_test_content()
	machines := content.machines
	box := test_machine(machines, "junction_box")
	trunk := test_item(content.items, "trunk_cable")
	draw := Cable_Draw{daylight_tint = {1, 1, 1}}
	{
		entities: Entities
		defer destroy_entities(&entities)
		low := add_entity(&entities, machines, box, {0, 1, 0}, 0)
		high := add_entity(&entities, machines, box, {4, 10, 3}, 0)
		look, found := cable_look(&entities, machines, content.items, draw, Cable{ends = {{low, 1}, {high, 0}}, item = trunk})
		if testing.expect(t, found) {
			expect_cable_joints_meet(t, look, "steep")
		}
	}
	entities: Entities
	defer destroy_entities(&entities)
	radius := f64(metres_to_position_units(8_000))
	hit := World_Position{0, i64(radius * 0.4359), i64(radius * 0.9)}
	origin, axes := free_frame_at(hit, {0, UNIT_VECTOR_ONE, 0}, 500)
	frame := add_frame(&entities.frames, origin, axes, 500)
	first := add_entity(&entities, machines, box, {0, 0, 0}, 0, frame)
	second := add_entity(&entities, machines, box, {0, 0, 8}, 0, frame)
	look, found := cable_look(&entities, machines, content.items, draw, Cable{ends = {{first, 3}, {second, 2}}, item = trunk})
	if testing.expect(t, found) {
		expect_cable_joints_meet(t, look, "level")
	}
}

// Two block worlds with the hand run factory and its switch, 600 ticks
// with the switch turned at 200 and the lamp's cable taken up at 400,
// hash alike every tick.
@(test) // slow
test_power_netlist_is_deterministic :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	states := [2]Simulation_State{make_save_test_simulation(&generator, content), make_save_test_simulation(&generator, content)}
	defer {
		for &state in states {
			destroy_simulation(&state)
		}
	}
	factories: [2]Hand_Run_Factory
	for &state, index in states {
		factories[index] = lay_hand_run_factory(&state.world, content, true)
	}
	for tick in 0 ..< 600 {
		for &state, index in states {
			entities := &state.world.entities
			switch tick {
			case 200:
				toggle_power_switch(entities, content.machines, factories[index].power_switch)
			case 400:
				remove_cable(entities, content.machines, port_end_cable(&entities.cables, {factories[index].lamp, 0}))
			}
			tick_test_entities(&state.world, &state.records, content, 1)
			state.tick += 1
		}
		if !testing.expectf(t, simulation_state_hash(&states[0]) == simulation_state_hash(&states[1]), "tick %d hashes apart", tick) {
			return
		}
	}
	// The five assemblers past the switch and the lamp off its cable.
	testing.expect_value(t, states[0].records.statistics.unpowered_machines, 6)
}

// Every benchmark module built: each electric machine and generator has a
// cable on its power port, and every consumer's network holds a
// generator.
@(test)
test_benchmark_modules_cable_every_electric_machine :: proc(t: ^testing.T) {
	plan := load_test_benchmark_plan(t)
	defer destroy_benchmark_plan(&plan)
	content := make_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content.generator = &generator
	placements := benchmark_layout(plan.manifest, 1)
	floor := benchmark_floor(placements)
	simulation := make_benchmark_simulation(test_game_config(), content, floor)
	defer destroy_simulation(&simulation)
	build_benchmark_world(&simulation.world, content.blocks, floor)
	scratch: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&scratch) == nil)
	defer virtual.arena_destroy(&scratch)
	problem := build_benchmark_factory(&simulation, content, plan, placements, &scratch)
	defer delete(problem)
	if !testing.expect_value(t, problem, "") {
		return
	}
	entities := &simulation.world.entities
	networks := &entities.electric_networks
	powered := make([]bool, len(networks.networks), context.temp_allocator)
	electric := 0
	for handle in networks.node_entities {
		machine := content.machines.machines[entity_common(entities, handle).machine]
		if machine_is_generator(machine) && entity_network(networks, handle) >= 0 {
			powered[entity_network(networks, handle)] = true
		}
	}
	for handle, node in networks.node_entities {
		if node > 0 && networks.node_entities[node - 1] == handle {
			continue
		}
		common := entity_common(entities, handle)
		machine := content.machines.machines[common.machine]
		if !machine_is_generator(machine) && !machine_is_electric_consumer(machine) {
			continue
		}
		electric += 1
		testing.expectf(t, port_end_cable(&entities.cables, {handle, 0}) >= 0, "the %s at %v has no cable", machine.id, common.origin)
		if machine_is_electric_consumer(machine) {
			network := entity_network(networks, handle)
			testing.expectf(t, network >= 0 && powered[network], "the %s at %v has no generator on its network", machine.id, common.origin)
		}
	}
	testing.expect(t, electric > 20, "the modules hold electric machines")
}

// One tick with the fuel generator's offer set to joules, as
// tick_with_hand_run_offer sets the engine's.
tick_with_generator_offer :: proc(simulation: ^Simulation_State, content: Simulation_Content, generator: Entity_Handle, joules: u32) {
	test_fluid_machine(&simulation.world, generator).fuel_joules = joules
	tick_test_entities(&simulation.world, &simulation.records, content, 1)
}

// Step 2 of 0368 (0383). A lead battery charged to 1000 J and cabled to a
// control unit holds the unit at 1000 while its charge falls by the
// unit's 1 J a tick, a store of the unit's network. A fuel generator on
// the ground cabled to the vessel's connector then serves the unit and
// charges the battery from what is left: at most the 32 J its 33 J cable
// has beside the unit's joule (less a joule of the solve's whole per mille
// level), the generator giving both; then the 20 J of room left to its
// capacity, and nothing once full. With the generator's fuel cut every
// other tick the battery gives in one tick and takes in the next, never
// both in one.
@(test)
test_vessel_battery_charges_and_discharges :: proc(t: ^testing.T) {
	simulation, content, _ := make_vessel_test()
	defer destroy_simulation(&simulation)
	world, entities := &simulation.world, &simulation.world.entities
	networks := &entities.electric_networks
	_, vessel := start_test_vessel(&simulation, content, "iron_truss", 4 * POSITION_UNITS_PER_METRE, 0)
	battery := add_test_vessel_part(&simulation, content, "lead_battery", vessel.id, {0, 1, 0})
	connector := add_test_vessel_part(&simulation, content, "docking_connector", vessel.id, {0, 2, 0})
	control := add_test_vessel_part(&simulation, content, "control_unit", vessel.id, {0, 3, 0})
	lay_test_cable(world, content, "light_cable", {battery, 1}, {control, 0})
	lay_test_cable(world, content, "light_cable", {connector, 2}, {battery, 0})
	pool_get(&entities.vessel_parts, battery).stored_joules = 1000
	tick_test_entities(world, &simulation.records, content, 10)
	testing.expect_value(t, pool_get(&entities.vessel_parts, control).power.satisfaction, 1000)
	testing.expect_value(t, pool_get(&entities.vessel_parts, battery).stored_joules, 990)
	testing.expect_value(t, len(networks.networks), 1)
	testing.expect_value(t, networks.networks[0].store_count, 1)
	testing.expect_value(t, networks.networks[0].generator_count, 0)
	testing.expect_value(t, simulation.records.statistics.unpowered_machines, 0)
	// The overview lists the battery under the batteries, not the generators.
	testing.expect_value(t, len(largest_participant_groups(networks.participants[:], 0, .Generators, POWER_GENERATOR_TYPE_COUNT)), 0)
	batteries := largest_participant_groups(networks.participants[:], 0, .Batteries, POWER_BATTERY_TYPE_COUNT)
	lead_battery := test_machine(content.machines, "lead_battery")
	testing.expect_value(t, len(batteries), 1)
	if len(batteries) == 1 {
		testing.expect_value(t, batteries[0], Participant_Group{machine = lead_battery, count = 1, joules = 1})
	}

	pad := lay_test_pad(entities, content.machines, 0, 0, {-2, 0, -2}, {1, 0, 1})
	generator := place_on_test_pad(&simulation, content, pad, "fuel_generator", {-2, 1, -2})
	lay_test_cable(world, content, "light_cable", {generator, 0}, {connector, 0})
	tick_with_generator_offer(&simulation, content, generator, 10_000)
	charge, _ := entity_participant(networks, battery)
	supply, _ := entity_participant(networks, generator)
	testing.expectf(t, charge.charged >= 31 && charge.charged <= 32, "charged %d", charge.charged)
	testing.expect_value(t, charge.delivered, 0)
	testing.expect_value(t, supply.delivered, 1 + charge.charged)
	testing.expect_value(t, pool_get(&entities.vessel_parts, battery).stored_joules, 990 + charge.charged)
	testing.expect_value(t, pool_get(&entities.vessel_parts, control).power.satisfaction, 1000)
	taking := largest_participant_groups(networks.participants[:], 0, .Batteries, POWER_BATTERY_TYPE_COUNT)
	testing.expect_value(t, len(taking), 1)
	if len(taking) == 1 {
		testing.expect_value(t, taking[0], Participant_Group{machine = lead_battery, count = 1, taken = charge.charged})
		testing.expect_value(t, participant_group_power_text(taking[0], TEST_TICK_RATE), fmt.tprintf("+%s", format_joules_per_tick(charge.charged, TEST_TICK_RATE)))
	}

	record, _ := vessel_part_record(content.vessel_parts, test_machine(content.machines, "lead_battery"))
	capacity := battery_capacity_joules(record)
	testing.expect_value(t, capacity, 2000 * 3600)
	pool_get(&entities.vessel_parts, battery).stored_joules = capacity - 20
	tick_with_generator_offer(&simulation, content, generator, 10_000)
	testing.expect_value(t, pool_get(&entities.vessel_parts, battery).stored_joules, capacity)
	tick_with_generator_offer(&simulation, content, generator, 10_000)
	testing.expect_value(t, pool_get(&entities.vessel_parts, battery).stored_joules, capacity)

	for tick in 0 ..< 6 {
		before := pool_get(&entities.vessel_parts, battery).stored_joules
		tick_with_generator_offer(&simulation, content, generator, tick % 2 == 0 ? 0 : 10_000)
		participant, _ := entity_participant(networks, battery)
		testing.expectf(t, (tick % 2 == 0) == (participant.delivered == 1) && (tick % 2 == 0) == (participant.charged == 0), "tick %d: gave %d, took %d", tick, participant.delivered, participant.charged)
		testing.expect_value(t, pool_get(&entities.vessel_parts, battery).stored_joules, before + participant.charged - participant.delivered)
		testing.expect_value(t, pool_get(&entities.vessel_parts, control).power.satisfaction, 1000)
	}
}

// A vessel 4 m from the flat site with an empty lead battery, a docking
// connector and a control unit, none cabled (0383).
Battery_Test_Vessel :: struct {
	battery, connector, control: Entity_Handle,
}

add_battery_test_vessel :: proc(simulation: ^Simulation_State, content: Simulation_Content) -> (vessel: Battery_Test_Vessel) {
	_, frame := start_test_vessel(simulation, content, "iron_truss", 4 * POSITION_UNITS_PER_METRE, 0)
	vessel.battery = add_test_vessel_part(simulation, content, "lead_battery", frame.id, {0, 1, 0})
	vessel.connector = add_test_vessel_part(simulation, content, "docking_connector", frame.id, {0, 2, 0})
	vessel.control = add_test_vessel_part(simulation, content, "control_unit", frame.id, {0, 3, 0})
	return
}

// A vessel's own network raises no warning (0383): an uncabled control
// unit, and one on an empty battery, count neither unpowered nor in a
// brownout and the HUD warns of none, while the unit itself gets nothing.
// Cabled through the connector to a lamp on the ground with no generator,
// the network counts as any network does: in a brownout every tick, and
// with the battery left out (no store), the unit and the lamp unpowered.
@(test)
test_a_vessels_own_network_raises_no_warning :: proc(t: ^testing.T) {
	simulation, content, _ := make_vessel_test()
	defer destroy_simulation(&simulation)
	world, entities := &simulation.world, &simulation.world.entities
	networks := &entities.electric_networks
	statistics := &simulation.records.statistics
	vessel := add_battery_test_vessel(&simulation, content)
	tick_test_entities(world, &simulation.records, content, 1)
	testing.expect_value(t, statistics.unpowered_machine_ticks, 0)
	testing.expect_value(t, statistics.brownout_ticks, 0)
	testing.expect_value(t, pool_get(&entities.vessel_parts, vessel.control).power.satisfaction, 0)

	lay_test_cable(world, content, "light_cable", {vessel.battery, 1}, {vessel.control, 0})
	tick_test_entities(world, &simulation.records, content, 1)
	testing.expect(t, network_is_in_brownout(networks.networks[0]))
	testing.expect(t, !any_network_in_brownout(networks))
	testing.expect_value(t, statistics.unpowered_machine_ticks, 0)
	testing.expect_value(t, statistics.brownout_ticks, 0)
	testing.expect_value(t, pool_get(&entities.vessel_parts, vessel.control).power.satisfaction, 0)

	pad := lay_test_pad(entities, content.machines, 0, 0, {-2, 0, -2}, {1, 0, 1})
	lamp := place_on_test_pad(&simulation, content, pad, "lamp", {0, 1, 0})
	lay_test_cable(world, content, "light_cable", {vessel.connector, 2}, {vessel.battery, 0})
	lay_test_cable(world, content, "light_cable", {lamp, 0}, {vessel.connector, 0})
	tick_test_entities(world, &simulation.records, content, 2)
	testing.expect(t, any_network_in_brownout(networks))
	testing.expect_value(t, statistics.brownout_ticks, 2)
	// The empty battery is a store (0368's rule), so nothing is unpowered.
	testing.expect_value(t, statistics.unpowered_machine_ticks, 0)

	remove_cable(entities, content.machines, port_end_cable(&entities.cables, {vessel.battery, 1}))
	remove_cable(entities, content.machines, port_end_cable(&entities.cables, {vessel.battery, 0}))
	lay_test_cable(world, content, "light_cable", {vessel.connector, 2}, {vessel.control, 0})
	tick_test_entities(world, &simulation.records, content, 1)
	testing.expect_value(t, statistics.unpowered_machines, 2)
	testing.expect_value(t, statistics.brownout_ticks, 3)
}

// Produced is what the generators gave, the battery's charge included
// (0383): with the battery charging, produced and the fuel left make the
// one coal lit, as the combustion tests count it without a battery, and
// produced is the unit's joules and the battery's charge. With the
// generator's cable taken up the battery gives alone and produced stays.
@(test)
test_energy_produced_counts_the_charge_and_no_discharge :: proc(t: ^testing.T) {
	simulation, content, _ := make_vessel_test()
	defer destroy_simulation(&simulation)
	world, entities := &simulation.world, &simulation.world.entities
	statistics := &simulation.records.statistics
	vessel := add_battery_test_vessel(&simulation, content)
	lay_test_cable(world, content, "light_cable", {vessel.battery, 1}, {vessel.control, 0})
	lay_test_cable(world, content, "light_cable", {vessel.connector, 2}, {vessel.battery, 0})
	pad := lay_test_pad(entities, content.machines, 0, 0, {-2, 0, -2}, {1, 0, 1})
	generator := place_on_test_pad(&simulation, content, pad, "fuel_generator", {-2, 1, -2})
	test_fluid_machine(world, generator).slots[COMBUSTION_FUEL_SLOT] = {test_item(content.items, "coal"), 3}
	lay_test_cable(world, content, "light_cable", {generator, 0}, {vessel.connector, 0})
	tick_test_entities(world, &simulation.records, content, 100)
	charge := pool_get(&entities.vessel_parts, vessel.battery).stored_joules
	testing.expect(t, charge > 0)
	testing.expect_value(t, statistics.fuel_burned, 1)
	testing.expect_value(t, statistics.energy_produced_joules + u64(test_fluid_machine(world, generator).fuel_joules), 1_000_000)
	testing.expect_value(t, statistics.energy_consumed_joules, 100)
	testing.expect_value(t, statistics.energy_produced_joules, statistics.energy_consumed_joules + charge)

	produced := statistics.energy_produced_joules
	remove_cable(entities, content.machines, port_end_cable(&entities.cables, {generator, 0}))
	tick_test_entities(world, &simulation.records, content, 10)
	testing.expect_value(t, statistics.energy_produced_joules, produced)
	testing.expect_value(t, statistics.energy_consumed_joules, 110)
	testing.expect_value(t, pool_get(&entities.vessel_parts, vessel.battery).stored_joules, charge - 10)
}

// Pipes (0374): records of the same table, told by their item.

// Every record with fluid_ports outside the vessel kinds meets each buffer
// with a fluid port of its ports: the boiler's out is port 1 on buffer 1,
// the tank's four ports meet its one buffer; the fluid junction lists four
// fluid ports and no power port.
@(test)
test_shipped_fluid_ports_resolve :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for &machine in machines.machines {
		if machine.fluid_port_count == 0 || machine_kind_is_vessel(machine.kind) {
			continue
		}
		met: [MAXIMUM_FLUID_PORTS]bool
		for port in machine.ports[:machine.port_count] {
			if port.kind == .Fluid && port.fluid_buffer >= 0 {
				met[port.fluid_buffer] = true
			}
		}
		for buffer in 0 ..< machine.fluid_port_count {
			testing.expectf(t, met[buffer], "%s: no fluid port meets buffer %d", machine.id, buffer)
		}
	}
	boiler := machines.machines[test_machine(machines, "boiler")]
	testing.expect_value(t, boiler.ports[1].id, "out")
	testing.expect_value(t, boiler.ports[1].fluid_buffer, 1)
	tank := machines.machines[test_machine(machines, "storage_tank")]
	testing.expect_value(t, tank.port_count, 4)
	for port in tank.ports[:tank.port_count] {
		testing.expectf(t, port.kind == .Fluid && port.fluid_buffer == 0, "the tank's port %s meets buffer %d", port.id, port.fluid_buffer)
	}
	junction := machines.machines[test_machine(machines, "fluid_junction")]
	testing.expect_value(t, junction.port_count, 4)
	testing.expect_value(t, machine_power_port_count(junction), 0)
	for port, index in junction.ports[:junction.port_count] {
		testing.expectf(t, port.kind == .Fluid && port.fluid_buffer == -1 && machine_port_takes_line(junction, index), "the junction's port %s", port.id)
	}
}

// A pipe item missing a key, at 59 or 1,000,001 L/s, with a span of 0, 101
// or above its stack, 19 or 401 mm thick, an all zero or an overflowing
// colour, or with cable keys too; a fluid port meeting no buffer, one on a
// lamp or a junction box, a fluid junction with one port or a power port,
// a boiler's port at 59 L/s, under a litre a tick (60 loads): each
// refused, naming it.
@(test)
test_malformed_pipe_items_and_fluid_ports_are_refused :: proc(t: ^testing.T) {
	pipe := shipped_item_definition("pipe")
	testing.expect_value(t, validate_item_definition({pipe}, 0), "")
	light := shipped_item_definition("light_cable")
	missing, slow, fast, no_span, long_span, short_stack, thin, thick, dark, bright, both := pipe, pipe, pipe, pipe, pipe, pipe, pipe, pipe, pipe, pipe, pipe
	missing.pipe_thickness_millimetres = 0
	slow.pipe_litres_per_second = 59
	fast.pipe_litres_per_second = 1_000_001
	no_span.pipe_span_metres = 0
	long_span.pipe_span_metres = 101
	short_stack.stack_size = 19
	thin.pipe_thickness_millimetres = 19
	thick.pipe_thickness_millimetres = 401
	dark.pipe_color = {}
	bright.pipe_color = {256, 0, 0}
	both.cable_kilowatts, both.cable_span_metres = light.cable_kilowatts, light.cable_span_metres
	both.cable_thickness_millimetres, both.cable_color = light.cable_thickness_millimetres, light.cable_color
	item_cases := [?]struct {
		definition: Item_Definition,
		words:      string,
	} {
		{missing, `pipe "pipe" needs all of`},
		{slow, `pipe "pipe" has pipe_litres_per_second 59 outside 60 to 1000000`},
		{fast, `pipe "pipe" has pipe_litres_per_second 1000001 outside 60 to 1000000`},
		{no_span, `pipe "pipe" needs all of`},
		{long_span, `pipe "pipe" has pipe_span_metres 101 outside 1 to 100`},
		{short_stack, `pipe "pipe" has pipe_span_metres 20 outside 1 to 100 or above its stack_size`},
		{thin, `pipe "pipe" has pipe_thickness_millimetres 19 outside 20 to 400`},
		{thick, `pipe "pipe" has pipe_thickness_millimetres 401 outside 20 to 400`},
		{dark, `pipe "pipe" needs all of`},
		{bright, `pipe "pipe" needs a pipe_color of three channels`},
		{both, `item "pipe" cannot be both a cable and a pipe`},
	}
	for entry in item_cases {
		problem := validate_item_definition({entry.definition}, 0)
		testing.expectf(t, strings.contains(problem, entry.words), "%q lacks %q", problem, entry.words)
	}

	boiler := shipped_machine_definition("boiler")
	lamp := shipped_machine_definition("lamp")
	box := shipped_machine_definition("junction_box")
	junction := shipped_machine_definition("fluid_junction")
	testing.expect_value(t, resolve_test_machines({boiler, junction}), "")
	spare := Machine_Port_Definition{id = "spare", kind = "fluid", cell = {y = 1}, face = "positive_y", capacity_litres_per_second = 1200}
	power := Machine_Port_Definition{id = "power", kind = "power", cell = {y = 0}, face = "positive_y", capacity_watts = 1000}
	unmet, fluid_lamp, fluid_box, lone, powered, trickle := boiler, lamp, box, junction, junction, boiler
	unmet.ports = {boiler.ports[0], boiler.ports[1], spare}
	trickle.ports = {boiler.ports[0], boiler.ports[1]}
	trickle.ports[0].capacity_litres_per_second = MINIMUM_PIPE_LITRES_PER_SECOND
	testing.expect_value(t, resolve_test_machines({trickle}), "")
	trickle.ports[0].capacity_litres_per_second = MINIMUM_PIPE_LITRES_PER_SECOND - 1
	fluid_lamp.ports = {lamp.ports[0], {id = "spare", kind = "fluid", face = "positive_y", capacity_litres_per_second = 1200}}
	fluid_box.ports = {box.ports[0], box.ports[1], {id = "spare", kind = "fluid", face = "positive_y", capacity_litres_per_second = 1200}}
	lone.ports = junction.ports[:1]
	powered.ports = {junction.ports[0], junction.ports[1], power}
	machine_cases := [?]struct {
		definition: Machine_Definition,
		words:      string,
	} {
		{unmet, `machine "boiler" fluid port "spare" meets none of its fluid_ports`},
		{fluid_lamp, `machine "lamp" port "spare" is a fluid port, which only a machine with fluid_ports, a fluid junction or a vessel part may list`},
		{fluid_box, `machine "junction_box" port "spare" is a fluid port`},
		{lone, `fluid junction "fluid_junction" needs 2 to 8 fluid ports and no power port`},
		{powered, `fluid junction "fluid_junction" needs 2 to 8 fluid ports and no power port`},
		{trickle, `machine "boiler" port "in" has capacity_litres_per_second 59 outside 60 to 1000000000`},
	}
	for entry in machine_cases {
		problem := resolve_test_machines({entry.definition})
		testing.expectf(t, strings.contains(problem, entry.words), "%q lacks %q", problem, entry.words)
	}
}

// The pipe run on a pad with a boiler, a tank and a lamp: Place on the
// boiler's +x face begins it on the free fluid port nearest the aimed face
// and the tool line shows the span left; Place on the lamp refuses
// No_Free_Port and keeps it; Place on the tank lays the pipe, takes its
// metres and counts no cable; Mine takes a run back; another slot ends
// one; a lamp's power port never starts a pipe run and the boiler's fluid
// ports never a cable run.
@(test)
test_field_pipe_run_controls :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	use_shipped_strings()
	defer thread_string_table = nil
	entities := &simulation.world.entities
	frame := lay_cable_test_pad(&simulation, content)
	boiler := place_on_test_pad(&simulation, content, frame, "boiler", {2, 1, 0})
	tank := place_on_test_pad(&simulation, content, frame, "storage_tank", {2, 1, -4})
	lamp_cell := World_Coordinate{6, 1, 3}
	place_on_test_pad(&simulation, content, frame, "lamp", lamp_cell)
	stand_test_player_on_cell(&simulation, content, items, frame, {7, 0, 0}, {"pipe", 100}, {"light_cable", 100})
	player := &simulation.players[0]
	hold_test_item(player, content, "pipe")
	testing.expect_value(t, player.field.tool, Field_Held_Tool.Pipe)
	pipe := test_item(items, "pipe")
	beside_inlet := frame_face_centre(frame, {4, 1, 0}, .Positive_X)
	beside_outlet := frame_face_centre(frame, {4, 1, 1}, .Positive_X)

	look_test_player_at(&simulation, content, beside_inlet)
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, player.field.cable_run, "Place on the boiler begins a run")
	testing.expect_value(t, player.field.cable_start, Port_End{boiler, 0})
	named := content
	named.fluids = make_test_fluids()
	line, shown := field_tool_line(player.field, named, .None, 1000, entities, pipe)
	testing.expectf(t, shown && strings.has_prefix(line, "Pipe from Boiler, water in: ") && strings.has_suffix(line, " m of the span left"), "the tool line %q", line)
	testing.expect_value(t, pipe_run_port_words(entities, content.machines, named.fluids, {boiler, 1}), "steam out")
	testing.expect_value(t, pipe_run_port_words(entities, content.machines, named.fluids, {tank, 2}), "port c")

	look_test_player_at(&simulation, content, frame_cell_centre(frame, lamp_cell))
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.No_Free_Port)
	testing.expect(t, player.field.cable_run, "a refused Place keeps the run")

	look_test_player_at(&simulation, content, frame_face_centre(frame, {4, 1, -3}, .Positive_X))
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, !player.field.cable_run, "the pipe laid ends the run")
	table := &entities.cables
	if !testing.expect_value(t, len(table.cables), 1) {
		return
	}
	testing.expect_value(t, table.kinds[0], Machine_Port_Kind.Fluid)
	testing.expect_value(t, table.capacity[0], 1200)
	testing.expect_value(t, port_end_cable(table, {boiler, 0}), 0)
	testing.expect_value(t, port_end_cable(table, {tank, 1}), 0)
	metres := int(table.cables[0].metres)
	testing.expect_value(t, i64(metres), port_span_metres(entities, content.machines, {boiler, 0}, {tank, 1}))
	testing.expect_value(t, inventory_count(player.inventory, pipe), 100 - metres)
	testing.expect_value(t, simulation.records.statistics.cables_run, 0)
	networks := &entities.fluid_networks
	testing.expect(t, fluid_netlist_of(networks, boiler, 0) == fluid_netlist_of(networks, tank, 0), "the pipe joins the inlet to the tank")

	look_test_player_at(&simulation, content, beside_outlet)
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field.cable_start, Port_End{boiler, 1})
	press_test_input(&simulation, content, TEST_PRESS_DIG)
	testing.expect(t, !player.field.cable_run, "Mine takes the run back")
	testing.expect_value(t, len(table.cables), 1)

	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect(t, player.field.cable_run)
	player.selected_hotbar_slot = 1
	press_test_input(&simulation, content, {})
	testing.expect(t, !player.field.cable_run, "another slot ends the run")
	player.selected_hotbar_slot = 0

	look_test_player_at(&simulation, content, frame_cell_centre(frame, lamp_cell))
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.No_Free_Port)
	testing.expect(t, !player.field.cable_run, "a power port starts no pipe run")

	player.selected_hotbar_slot = 1
	hold_test_item(player, content, "light_cable")
	look_test_player_at(&simulation, content, beside_outlet)
	press_test_input(&simulation, content, TEST_PRESS_PLACE)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.No_Free_Port)
	testing.expect(t, !player.field.cable_run, "a fluid port starts no cable run")
}

// Mine held for PICK_UP_SECONDS on a pipe between two fluid junctions takes
// it up and adds its metres; a junction picked up comes with its pipe's
// metres and leaves the fluid netlist.
@(test)
test_taking_up_a_pipe_returns_its_metres :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	frame := lay_cable_test_pad(&simulation, content)
	south := place_on_test_pad(&simulation, content, frame, "fluid_junction", {2, 1, -3})
	north := place_on_test_pad(&simulation, content, frame, "fluid_junction", {2, 1, 3})
	ends := [2]Port_End{{south, 3}, {north, 2}}
	lay_test_cable(&simulation.world, content, "pipe", ends[0], ends[1])
	metres := int(entities.cables.cables[0].metres)
	middle := test_cable_middle(entities, content.machines, 0)
	stand_test_player_on_cell(&simulation, content, items, frame, {6, 0, 0}, {"wooden_shovel", 1})
	player := &simulation.players[0]
	hold_test_item(player, content, "wooden_shovel")
	pipe := test_item(items, "pipe")
	networks := &entities.fluid_networks
	testing.expect(t, fluid_netlist_of(networks, south, -1) == fluid_netlist_of(networks, north, -1), "the pipe joins the junctions")
	look_test_player_at(&simulation, content, middle)
	tick_field_simulation(&simulation, content, {})
	testing.expect_value(t, field_aimed_cable(entities, content.machines, player.field, content.field.tuning), 0)
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS - 1)
	testing.expect_value(t, len(entities.cables.cables), 1)
	hold_test_mine(&simulation, content, 1)
	testing.expect_value(t, len(entities.cables.cables), 0)
	testing.expect_value(t, inventory_count(player.inventory, pipe), metres)
	testing.expect(t, fluid_netlist_of(networks, south, -1) != fluid_netlist_of(networks, north, -1), "the junctions part")

	lay_test_cable(&simulation.world, content, "pipe", ends[0], ends[1])
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = Field_Placement{kind = .Pick_Up, frame = frame.id, cell = {2, 1, -3}}})
	drain_field_placements(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, entity_at(entities, {2, 1, -3}, frame.id), NO_ENTITY)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "fluid_junction")), 1)
	testing.expect_value(t, inventory_count(player.inventory, pipe), 2 * metres)
	testing.expect_value(t, len(entities.cables.cables), 0)
	testing.expect_value(t, len(networks.nodes), 1)
	testing.expect_value(t, fluid_node_of(networks, south, -1), -1)
	testing.expect(t, fluid_node_of(networks, north, -1) >= 0, "the north junction keeps its node")
}

// cable_down_and_sag gives a fluid record no sag and a power one its sag
// between the same two points; a laid pipe's curve is its chord.
@(test)
test_a_pipe_is_straight_and_a_cable_sags :: proc(t: ^testing.T) {
	content := make_test_content()
	machines := content.machines
	entities: Entities
	defer destroy_entities(&entities)
	frame := lay_test_pad(&entities, machines, 0, 0, {-4, 0, -4}, {6, 0, 4})
	record := Cable {
		ends = {{{kind = .Pole, index = 1}, 0}, {{kind = .Pole, index = 2}, 1}},
	}
	first, second := frame_cell_centre(frame, {0, 1, -3}), frame_cell_centre(frame, {0, 1, 3})
	cable_down, cable_sag := cable_down_and_sag(record, .Power, frame, frame, first, second)
	pipe_down, pipe_sag := cable_down_and_sag(record, .Fluid, frame, frame, first, second)
	testing.expect(t, cable_sag > 0, "the cable sags")
	testing.expect_value(t, pipe_sag, 0)
	testing.expect_value(t, pipe_down, cable_down)

	junction := test_machine(machines, "fluid_junction")
	south, _ := place_on_frame(&entities, machines, junction, frame.id, {0, 1, -3}, 0)
	north, _ := place_on_frame(&entities, machines, junction, frame.id, {0, 1, 3}, 0)
	add_cable(&entities, content, Cable{ends = {{south, 3}, {north, 2}}, item = test_item(content.items, "pipe"), metres = 3})
	start, end, _, sag, found := cable_curve(&entities, machines, entities.cables.cables[0])
	testing.expect(t, found && sag == 0, "a laid pipe sags none")
	testing.expect_value(t, test_cable_middle(&entities, machines, 0), start + (end - start) / 2)
}

// A pump with a light cable on its power port and a pipe on its outlet:
// one table holds both, told power and fluid; the power netlist takes the
// cable alone and the fluid netlist the pipe alone; the pipe has no cable
// load.
@(test)
test_cables_and_pipes_share_the_table_but_not_the_netlists :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records := make_test_records(content)
	frame := lay_pipe_test_pad(&world, content)
	pump := place_on_pipe_pad(&world, content, frame, "pump", {0, 1, 0})
	box := place_on_pipe_pad(&world, content, frame, "junction_box", {1, 1, 3})
	tank := place_on_pipe_pad(&world, content, frame, "storage_tank", {5, 1, -1})
	lay_test_cable(&world, content, "light_cable", test_port_end(&world, content, pump, "power"), {box, 0})
	lay_test_cable(&world, content, "pipe", test_port_end(&world, content, pump, "out"), test_port_end(&world, content, tank, "d"))
	entities := &world.entities
	table := &entities.cables
	testing.expect_value(t, len(table.cables), 2)
	testing.expect(t, slice.equal(table.kinds[:], []Machine_Port_Kind{.Power, .Fluid}), "the kinds")
	// The cable's the pump's 30 kW port, the pipe's its item's 1200 L/s.
	testing.expect(t, slice.equal(table.capacity[:], []i64{30_000, 1200}), "the capacities")
	testing.expect_value(t, len(cable_edges(&entities.electric_networks, entities)), 1)
	testing.expect_value(t, len(pipe_edges(&entities.fluid_networks, entities, content.machines)), 1)
	tick_test_entities(&world, &records, content, 1)
	_, cable_found := cable_load(&entities.electric_networks, table, 0)
	_, pipe_found := cable_load(&entities.electric_networks, table, 1)
	testing.expect(t, cable_found, "the cable has a load")
	testing.expect(t, !pipe_found, "the pipe has none")
}
