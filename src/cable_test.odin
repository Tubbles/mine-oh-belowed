package game

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
// the vessel kinds lists a port.
@(test)
test_shipped_power_ports_resolve :: proc(t: ^testing.T) {
	machines := make_test_machines()
	for &machine in machines.machines {
		watts := i64(max(machine.electric_power_watts, machine.electric_output_watts))
		switch {
		case watts > 0:
			if !testing.expectf(t, machine.port_count == 1 && machine_port_is_power(machine, 0), "%s has %d ports", machine.id, machine.port_count) {
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
			testing.expectf(t, machine.port_count == 0, "%s lists %d ports", machine.id, machine.port_count)
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
Hand_Run_Factory :: struct {
	engine:       Entity_Handle,
	first_box:    Entity_Handle,
	second_box:   Entity_Handle,
	lamp:         Entity_Handle,
	power_switch: Entity_Handle,
	assemblers:   [5]Entity_Handle,
}

lay_hand_run_factory :: proc(world: ^World, content: Simulation_Content, with_switch: bool) -> (factory: Hand_Run_Factory) {
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
	aimed := aimed_glyph_hints(screen_context, hud)
	testing.expectf(t, slice.equal(hint_labels_on(aimed, .Interact), []string{"Turn"}), "Interact %v", hint_labels_on(aimed, .Interact))
	testing.expectf(t, slice.equal(hint_labels_on(aimed, .Mine), []string{"Take up"}), "Mine %v", hint_labels_on(aimed, .Mine))

	begin_test_run(&simulation, content, frame, {3, 1, 2})
	testing.expect(t, player.field.cable_run, "Place on the box begins a run")
	aim_at_switch(&simulation, content, switch_point)
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
	item := content.items.items[cable.item]
	color := cable_draw_color(item, cable, {1, 1, 1})
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

	minimum, maximum := cable_draw_box(look.points, look.thickness_metres)
	view := Model_View{eye = look.points[CABLE_CURVE_STEPS / 2], transform = 1}
	testing.expect(t, cable_box_is_near(&view, minimum, maximum))
	view.eye = maximum + {0, 40, 0}
	testing.expect(t, !cable_box_is_near(&view, minimum, maximum))
	view.eye = maximum + {0, CABLE_BOX_METRES - 1, 0}
	testing.expect(t, cable_box_is_near(&view, minimum, maximum))
	testing.expect(t, !cable_box_is_near(nil, minimum, maximum))
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
