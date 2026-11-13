package game

import "base:runtime"
import "netlist"

// Electric networks (doc/fluids.md, Power, work item 0368): the netlist
// of the cables. A node is a thing's terminal: one per live entity whose
// machine has a power port, its ports joined inside it, but a power switch
// that is off, which is two (port 0, port 1). Nodes are numbered in pool
// order: the poles' pool (junction boxes and switches), then the
// participants' pools in collection order, then the vessel parts, so the
// leftover joules go in that order. One edge per cable between the nodes
// of its two ends, carrying its watts (cable.odin); parallel cables
// bundle, a cable that closes a loop is a chord that carries nothing
// until 0377 (netlist.build_topology). A network is a tree of two or more
// nodes, in tree order; a consumer with no cable is a tree alone, in no
// network. The netlist is rebuilt whenever an entity with a power port is
// placed or removed, a cable is laid or taken up, or a switch turns.
//
// Per tick, integers in joules: every consumer asks for its power over
// the tick while it has work, every generator offers what it can give,
// and the netlist's solve (src/netlist/) balances each tree with each
// edge's capacity a tick: a consumer gets its node's level, so a thin
// cable starves only what is behind it, and works at that fraction
// (power_machine.odin); the generators share what was delivered in their
// dispatch order (0140), within one order in proportion to their offers,
// and burn fuel or steam only for their share.

// The last tick's balance of one network, joules per tick. satisfaction
// is the lowest level of its consumers with a demand, in per mille, or
// full when nothing asks and something could give.
Electric_Network :: struct {
	supply:          u64,
	demand:          u64,
	delivered:       u64,
	satisfaction:    u32,
	generator_count: int,
	consumer_count:  int,
	// The batteries (0383); 0 until then.
	store_count:     int,
}

// offered is a consumer's demand or a generator's supply for the tick,
// delivered what it received or gave. node is its node in the netlist, -1
// for an entity without a power port; network is -1 outside every network.
Electric_Participant :: struct {
	handle:    Entity_Handle,
	machine:   Machine_Id,
	network:   int,
	node:      int,
	generator: bool,
	offered:   u64,
	delivered: u64,
	// Generators: lower serves first (the netlist's dispatch_by_order).
	dispatch_order: u8,
}

Electric_Networks :: struct {
	networks:            [dynamic]Electric_Network,
	// Every electric machine and generator in the last tick, in pool
	// order, for the overview.
	participants:        [dynamic]Electric_Participant,
	// Zero means context.allocator; tests use the temp allocator.
	allocator:           runtime.Allocator,
	// Per node its entity (an off switch names its entity twice), and
	// each entity's first node.
	node_entities:       [dynamic]Entity_Handle,
	node_of_entity:      map[Entity_Handle]u32,
	// The forest of the cables, in the networks' allocator, made again at
	// each rebuild.
	topology:            netlist.Topology,
	// Per tree its network, -1 for a tree of one node.
	network_of_tree:     [dynamic]i32,
	// The tick's scratch, per node: each edge's capacity in whole joules a
	// tick, the solve's inputs and outputs, and the participant on the node
	// (-1 for none).
	capacity_per_tick:   [dynamic]i64,
	inputs:              [dynamic]netlist.Node_Input,
	outputs:             [dynamic]netlist.Node_Output,
	participant_of_node: [dynamic]i32,
}

electric_allocator :: proc(networks: ^Electric_Networks) -> runtime.Allocator {
	return networks.allocator.procedure != nil ? networks.allocator : context.allocator
}

destroy_electric_networks :: proc(networks: ^Electric_Networks) {
	netlist.destroy_topology(&networks.topology, electric_allocator(networks))
	delete(networks.networks)
	delete(networks.participants)
	delete(networks.node_entities)
	delete(networks.node_of_entity)
	delete(networks.network_of_tree)
	delete(networks.capacity_per_tick)
	delete(networks.inputs)
	delete(networks.outputs)
	delete(networks.participant_of_node)
}

set_electric_allocators :: proc(networks: ^Electric_Networks) {
	if networks.networks.allocator.procedure != nil {
		return
	}
	allocator := electric_allocator(networks)
	networks.networks.allocator, networks.participants.allocator = allocator, allocator
	networks.node_entities.allocator, networks.network_of_tree.allocator = allocator, allocator
	networks.capacity_per_tick.allocator, networks.inputs.allocator = allocator, allocator
	networks.outputs.allocator, networks.participant_of_node.allocator = allocator, allocator
	networks.node_of_entity = make(map[Entity_Handle]u32, allocator)
}

clear_electric_networks :: proc(networks: ^Electric_Networks) {
	set_electric_allocators(networks)
	netlist.destroy_topology(&networks.topology, electric_allocator(networks))
	clear(&networks.networks)
	clear(&networks.participants)
	clear(&networks.node_entities)
	clear(&networks.node_of_entity)
	clear(&networks.network_of_tree)
}

// The pool's live entries with a power port, one node each, an off
// switch two.
append_power_nodes :: proc(networks: ^Electric_Networks, pool: ^Entity_Pool($T), machines: Machine_Registry) {
	for &entry in pool.entries {
		if !entry.alive || !machine_touches_power(machines.machines[entry.machine]) {
			continue
		}
		networks.node_of_entity[entry.handle] = u32(len(networks.node_entities))
		append(&networks.node_entities, entry.handle)
		when T == Pole {
			if !entry.on {
				append(&networks.node_entities, entry.handle)
			}
		}
	}
}

// The edges of the cables between the nodes of their ends, in the temp
// allocator.
cable_edges :: proc(networks: ^Electric_Networks, entities: ^Entities) -> []netlist.Edge {
	edges := make([dynamic]netlist.Edge, 0, len(entities.cables.cables), context.temp_allocator)
	for cable, index in entities.cables.cables {
		first, second := power_port_node(networks, cable.ends[0]), power_port_node(networks, cable.ends[1])
		if first >= 0 && second >= 0 {
			append(&edges, netlist.Edge{u32(first), u32(second), entities.cables.watts[index]})
		}
	}
	return edges[:]
}

rebuild_electric_networks :: proc(entities: ^Entities, machines: Machine_Registry) {
	networks := &entities.electric_networks
	clear_electric_networks(networks)
	append_power_nodes(networks, &entities.poles, machines)
	append_power_nodes(networks, &entities.inserters, machines)
	append_power_nodes(networks, &entities.drills, machines)
	append_power_nodes(networks, &entities.fluid_machines, machines)
	append_power_nodes(networks, &entities.lamps, machines)
	append_power_nodes(networks, &entities.assemblers, machines)
	append_power_nodes(networks, &entities.labs, machines)
	append_power_nodes(networks, &entities.core_sample_drills, machines)
	append_power_nodes(networks, &entities.launch_pads, machines)
	append_power_nodes(networks, &entities.vessel_parts, machines)
	networks.topology = netlist.build_topology(len(networks.node_entities), cable_edges(networks, entities), electric_allocator(networks))
	count := i32(0)
	for tree in networks.topology.trees {
		append(&networks.network_of_tree, tree.count >= 2 ? count : -1)
		count += tree.count >= 2 ? 1 : 0
	}
	resize(&networks.networks, int(count))
	for &network in networks.networks {
		network = {}
	}
}

// The node a port end joins: the entity's, the second of an off switch
// for its port 1; -1 for none.
power_port_node :: proc(networks: ^Electric_Networks, end: Port_End) -> int {
	node, found := networks.node_of_entity[end.entity]
	if !found {
		return -1
	}
	next := int(node) + 1
	if end.port == 1 && next < len(networks.node_entities) && networks.node_entities[next] == end.entity {
		return next
	}
	return int(node)
}

// The network of an entity's first node, -1 without one.
entity_network :: proc(networks: ^Electric_Networks, handle: Entity_Handle) -> int {
	node, found := networks.node_of_entity[handle]
	if !found || int(node) >= len(networks.topology.tree_of) {
		return -1
	}
	return int(networks.network_of_tree[networks.topology.tree_of[node]])
}

// The energy balance.

power_satisfaction :: proc(supply, demand: u64) -> u32 {
	return netlist.pooled_level(i64(supply), i64(demand))
}

// Through the netlist: each participant's input on its node, each edge's
// capacity in whole joules a tick (floored after bundling: a limit, no
// energy is lost), the solve, and each participant's delivered (supplied
// for a generator). The networks' figures are summed from the
// participants; a network's satisfaction is the lowest level among its
// consumers with a demand.
balance_electric_energy :: proc(networks: ^Electric_Networks, tick_rate: int) {
	node_count := len(networks.node_entities)
	resize(&networks.capacity_per_tick, node_count)
	resize(&networks.inputs, node_count)
	resize(&networks.outputs, node_count)
	resize(&networks.participant_of_node, node_count)
	for node in 0 ..< node_count {
		networks.capacity_per_tick[node] = networks.topology.capacity[node] / i64(max(tick_rate, 1))
		networks.inputs[node], networks.outputs[node], networks.participant_of_node[node] = {}, {}, -1
	}
	for participant, index in networks.participants {
		if participant.node >= 0 {
			networks.inputs[participant.node] = participant_node_input(participant)
			networks.participant_of_node[participant.node] = i32(index)
		}
	}
	topology := networks.topology
	topology.capacity = networks.capacity_per_tick[:]
	netlist.solve(topology, networks.inputs[:], networks.outputs[:])
	for &network in networks.networks {
		network = {}
		network.satisfaction = POWER_FULL + 1
	}
	for &participant in networks.participants {
		participant.delivered = 0
		if participant.node < 0 {
			continue
		}
		output := networks.outputs[participant.node]
		participant.delivered = u64(participant.generator ? output.supplied : output.delivered)
		if participant.network >= 0 {
			network := &networks.networks[participant.network]
			add_participant_offer(network, participant)
			if !participant.generator {
				network.delivered += participant.delivered
				if participant.offered > 0 {
					network.satisfaction = min(network.satisfaction, output.level)
				}
			}
		}
	}
	for &network in networks.networks {
		if network.satisfaction > POWER_FULL {
			network.satisfaction = power_satisfaction(network.supply, 0)
		}
	}
}

participant_node_input :: proc(participant: Electric_Participant) -> netlist.Node_Input {
	if participant.generator {
		return {offer = i64(participant.offered), order = participant.dispatch_order}
	}
	return {demand = i64(participant.offered)}
}

add_participant_offer :: proc(network: ^Electric_Network, participant: Electric_Participant) {
	if participant.generator {
		network.supply += participant.offered
		network.generator_count += 1
	} else {
		network.demand += participant.offered
		network.consumer_count += 1
	}
}

// The tick.

// While it has room and something to do: bore, mine, or mine a revived vein.
drill_wants_power :: proc(tick_context: Entity_Tick_Context, drill: Drill, machine: Machine) -> bool {
	vein := tick_vein(tick_context, drill.vein)
	return stack_is_empty(drill.held) && drill_activity(drill, machine, vein, tick_context.settings.veins_infinite, tick_context.tick_rate) != .Vein_Exhausted
}

// Only while the arm swings, like a burner burns fuel.
inserter_wants_power :: proc(inserter: Inserter) -> bool {
	return inserter.phase == .Swinging_To_Drop || inserter.phase == .Swinging_Back
}

pump_wants_power :: proc(pump: Fluid_Machine, machine: Machine) -> bool {
	input := pump.buffers[port_index_of_direction(machine, .Input)]
	output_index := port_index_of_direction(machine, .Output)
	return input.level > 0 && buffer_room(pump.buffers[output_index], machine.fluid_ports[output_index].capacity) > 0
}

// Pumps while they can move fluid, offshore and tar pit pumps while
// there is room, flare stacks while they relieve gas.
fluid_machine_wants_power :: proc(fluid_machine: Fluid_Machine, machine: Machine, fluids: Fluid_Registry) -> bool {
	#partial switch machine.kind {
	case .Pump:
		return pump_wants_power(fluid_machine, machine)
	case .Offshore_Pump, .Tar_Pit_Pump:
		return source_pump_has_room(fluid_machine, machine)
	case .Flare_Stack:
		return flare_stack_is_relieving(fluid_machine, machine, fluids)
	}
	return false
}

// A broken machine (0201) asks for and offers nothing, so it takes no
// share of its network. Its node is its entity's first, -1 without a
// power port.
make_participant :: proc(networks: ^Electric_Networks, common: Entity_Common, generator: bool, offered: u64) -> Electric_Participant {
	node, found := networks.node_of_entity[common.handle]
	return Electric_Participant {
		handle = common.handle,
		machine = common.machine,
		network = entity_network(networks, common.handle),
		node = found ? int(node) : -1,
		generator = generator,
		offered = common.broken ? 0 : offered,
	}
}

// What every electric entity asks for or offers this tick, in pool order.
collect_electric_participants :: proc(tick_context: Entity_Tick_Context) {
	content, tick_rate := tick_context.content, tick_context.tick_rate
	machines := content.machines
	entities := tick_context.entities
	networks := &entities.electric_networks
	clear(&networks.participants)
	for inserter in entities.inserters.entries {
		machine := machines.machines[inserter.machine]
		if inserter.alive && machine_is_electric_consumer(machine) {
			demand := inserter_wants_power(inserter) ? electric_joules_per_tick(machine.electric_power_watts, tick_rate) : 0
			append(&networks.participants, make_participant(networks, inserter.common, false, demand))
		}
	}
	for drill in entities.drills.entries {
		machine := machines.machines[drill.machine]
		if drill.alive && machine_is_electric_consumer(machine) {
			demand := drill_wants_power(tick_context, drill, machine) ? electric_joules_per_tick(machine.electric_power_watts, tick_rate) : 0
			append(&networks.participants, make_participant(networks, drill.common, false, demand))
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		machine := machines.machines[fluid_machine.machine]
		switch {
		case !fluid_machine.alive:
		case machine_is_generator(machine):
			offer := generator_available_joules(tick_context, fluid_machine, machine)
			participant := make_participant(networks, fluid_machine.common, true, offer)
			participant.dispatch_order = machine.dispatch_order
			append(&networks.participants, participant)
		case machine_is_electric_consumer(machine):
			demand := fluid_machine_wants_power(fluid_machine, machine, content.fluids) ? electric_joules_per_tick(machine.electric_power_watts, tick_rate) : 0
			append(&networks.participants, make_participant(networks, fluid_machine.common, false, demand))
		}
	}
	for lamp in entities.lamps.entries {
		if lamp.alive {
			demand := electric_joules_per_tick(machines.machines[lamp.machine].electric_power_watts, tick_rate)
			append(&networks.participants, make_participant(networks, lamp.common, false, demand))
		}
	}
	collect_crafting_participants(tick_context)
}

// Electric crafting machines, labs, core sample drills and launch pads,
// while they have work.
collect_crafting_participants :: proc(tick_context: Entity_Tick_Context) {
	content, tick_rate := tick_context.content, tick_context.tick_rate
	entities := tick_context.entities
	networks := &entities.electric_networks
	for assembler in entities.assemblers.entries {
		machine := content.machines.machines[assembler.machine]
		if assembler.alive && crafting_machine_is_electric(machine) {
			watts := machine.electric_power_watts
			wants := assembler_wants_power(assembler, machine, content.recipes, content.items, tick_context.settings.byproducts_lenient)
			demand := wants ? electric_joules_per_tick(watts, tick_rate) : 0
			append(&networks.participants, make_participant(networks, assembler.common, false, demand))
		}
	}
	for lab in entities.labs.entries {
		if lab.alive {
			watts := content.machines.machines[lab.machine].electric_power_watts
			wants := lab_wants_power(lab, tick_context.records.research, content.technologies, content.machines.lab_packs)
			append(&networks.participants, make_participant(networks, lab.common, false, wants ? electric_joules_per_tick(watts, tick_rate) : 0))
		}
	}
	for drill in entities.core_sample_drills.entries {
		if drill.alive {
			watts := content.machines.machines[drill.machine].electric_power_watts
			wants := core_sample_drill_wants_power(drill)
			append(&networks.participants, make_participant(networks, drill.common, false, wants ? electric_joules_per_tick(watts, tick_rate) : 0))
		}
	}
	for pad in entities.launch_pads.entries {
		if pad.alive {
			machine := content.machines.machines[pad.machine]
			wants := launch_pad_wants_power(pad, machine, tick_rate)
			append(&networks.participants, make_participant(networks, pad.common, false, wants ? electric_joules_per_tick(machine.electric_power_watts, tick_rate) : 0))
		}
	}
}

// Sets a consumer's satisfaction for the tick: the one seam every
// consumer's share of the balance goes through.
deliver_power_satisfaction :: proc(entities: ^Entities, handle: Entity_Handle, satisfaction: u32) {
	participant_power(entities, handle).satisfaction = satisfaction
}

// The consumer's Power_State, or nil for a generator.
participant_power :: proc(entities: ^Entities, handle: Entity_Handle) -> ^Power_State {
	#partial switch handle.kind {
	case .Inserter:
		return &pool_get(&entities.inserters, handle).power
	case .Drill:
		return &pool_get(&entities.drills, handle).power
	case .Fluid_Machine:
		return &pool_get(&entities.fluid_machines, handle).power
	case .Lamp:
		return &pool_get(&entities.lamps, handle).power
	case .Assembler:
		return &pool_get(&entities.assemblers, handle).power
	case .Lab:
		return &pool_get(&entities.labs, handle).power
	case .Core_Sample_Drill:
		return &pool_get(&entities.core_sample_drills, handle).power
	case .Launch_Pad:
		return &pool_get(&entities.launch_pads, handle).power
	}
	return nil
}

// A consumer gets its node's level. Generators draw their steam, gas and
// fuel items here, so they are counted consumed here.
apply_electric_balance :: proc(entities: ^Entities, content: Simulation_Content, statistics: ^Statistics, tick_rate: int) {
	networks := &entities.electric_networks
	for participant in networks.participants {
		network := participant.network >= 0 ? networks.networks[participant.network] : Electric_Network{}
		if !participant.generator {
			level := participant.node >= 0 ? networks.outputs[participant.node].level : 0
			deliver_power_satisfaction(entities, participant.handle, level)
			continue
		}
		generator := pool_get(&entities.fluid_machines, participant.handle)
		machine := content.machines.machines[generator.machine]
		before := generator^
		deliver_generator_energy(generator, machine, content, participant.delivered)
		record_generator_tick(statistics, machine.kind, before, generator^)
		generator.state = generator_state(machine.kind, participant.delivered, participant.offered, network.demand)
		if participant.delivered > 0 {
			record_operation(entities, &generator.common, machine, content.field.bare_ground, tick_rate)
		}
		if machine.kind == .Hydro_Turbine {
			record_turbine_still_water(statistics, generator, tick_rate)
		}
	}
}

// A streak of No_Water ticks counts once when it reaches
// TURBINE_STILL_WATER_SECONDS, so a turbine left in still water counts
// once until water flows again.
record_turbine_still_water :: proc(statistics: ^Statistics, turbine: ^Fluid_Machine, tick_rate: int) {
	turbine.still_water_ticks = turbine.state == .No_Water ? turbine.still_water_ticks + 1 : 0
	if turbine.still_water_ticks == u32(TURBINE_STILL_WATER_SECONDS * tick_rate) {
		statistics.turbine_still_water_ticks += 1
	}
}

// Fluids drawn, the gas of combustion generators, the energy of hydro
// turbines, and fuel items lit from the slot as burned and consumed.
record_generator_tick :: proc(statistics: ^Statistics, kind: Machine_Kind, before, after: Fluid_Machine) {
	buffers_before, buffers_after := before.buffers, after.buffers
	record_buffer_changes(statistics, buffers_before[:], buffers_after[:])
	#partial switch kind {
	case .Combustion_Generator:
		statistics.generator_gas_litres += u64(max(before.buffers[0].level - after.buffers[0].level, 0))
	case .Hydro_Turbine:
		statistics.turbine_joules += u64(after.generated_joules)
	}
	slots_before, slots_after := before.slots, after.slots
	for slot, index in slots_before[:before.slot_count] {
		statistics.fuel_burned += u64(stack_shrink(slot, slots_after[index]))
	}
	record_slot_consumption(statistics, slots_before[:before.slot_count], slots_after[:after.slot_count])
}

// Energy and brownouts for the overview and the quest hints. A consumer
// is unpowered outside every network or in one with no generator and no
// store.
record_electric_tick :: proc(statistics: ^Statistics, networks: ^Electric_Networks) {
	unpowered := 0
	for participant in networks.participants {
		if !participant.generator && (participant.network < 0 || network_has_no_source(networks.networks[participant.network])) {
			unpowered += 1
		}
	}
	brownout := false
	for network in networks.networks {
		statistics.energy_produced_joules += network.delivered
		statistics.energy_consumed_joules += network.delivered
		brownout = brownout || network_is_in_brownout(network)
	}
	if brownout {
		statistics.brownout_ticks += 1
	}
	statistics.unpowered_machines = u64(unpowered)
	statistics.unpowered_machine_ticks += u64(unpowered)
}

network_has_no_source :: proc(network: Electric_Network) -> bool {
	return network.generator_count == 0 && network.store_count == 0
}

network_is_in_brownout :: proc(network: Electric_Network) -> bool {
	return network.demand > 0 && network.satisfaction < POWER_FULL
}

any_network_in_brownout :: proc(networks: ^Electric_Networks) -> bool {
	for network in networks.networks {
		if network_is_in_brownout(network) {
			return true
		}
	}
	return false
}

// Before the machines tick, so they work at this tick's satisfaction.
tick_electric_networks :: proc(tick_context: Entity_Tick_Context) {
	records := tick_context.records
	networks := &tick_context.entities.electric_networks
	set_electric_allocators(networks)
	collect_electric_participants(tick_context)
	balance_electric_energy(networks, tick_context.tick_rate)
	apply_electric_balance(tick_context.entities, tick_context.content, &records.statistics, tick_context.tick_rate)
	record_electric_tick(&records.statistics, networks)
}
