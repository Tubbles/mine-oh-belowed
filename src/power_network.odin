package game

import "base:runtime"

// Electric networks (doc/fluids.md, Power). Poles and power switches are
// the nodes. Two nodes are wired when their origins are at most the
// shorter of their two wire reaches apart (straight line). A network is a
// connected set of nodes over the wires, where a power switch that is off
// takes part in no network, so the wires through it carry nothing. An
// electric machine or generator belongs to the network of the first pole
// (pool order) whose supply volume covers one of its cells, and to none
// otherwise. Networks and memberships are rebuilt whenever a pole, a
// switch or an electric machine is placed or removed, or a switch turns.
//
// Per tick, integers in joules: every consumer asks for its power over
// the tick while it has work, every generator offers what it can give,
// satisfaction is min(supply, demand) over demand in per mille, every
// consumer receives its demand times the satisfaction and works at that
// fraction (power_machine.odin), and the generators share the energy
// actually received in proportion to their offers and burn fuel or steam
// only for their share.

Electric_Node :: struct {
	handle:        Entity_Handle,
	origin:        World_Coordinate,
	reach:         i32,
	// The cells the node powers; size zero for a power switch.
	supply_origin: World_Coordinate,
	supply_size:   [3]i32,
	// False for a power switch that is off.
	active:        bool,
	// -1 for an inactive node.
	network:       int,
}

// Indices into Electric_Networks.nodes, first below second.
Electric_Wire :: struct {
	first:  int,
	second: int,
}

// The last tick's balance, joules per tick. satisfaction is in per
// mille: min(supply, demand) over demand, or full when nothing asks and
// something could give.
Electric_Network :: struct {
	supply:          u64,
	demand:          u64,
	delivered:       u64,
	satisfaction:    u32,
	generator_count: int,
	consumer_count:  int,
}

// offered is a consumer's demand or a generator's supply for the tick,
// delivered what it received or gave. network is -1 outside every network.
Electric_Participant :: struct {
	handle:    Entity_Handle,
	machine:   Machine_Id,
	network:   int,
	generator: bool,
	offered:   u64,
	delivered: u64,
}

Electric_Networks :: struct {
	nodes:        [dynamic]Electric_Node,
	wires:        [dynamic]Electric_Wire,
	networks:     [dynamic]Electric_Network,
	// Electric machines and generators inside a network.
	memberships:  map[Entity_Handle]int,
	// Every electric machine and generator in the last tick, in pool
	// order, for the overview.
	participants: [dynamic]Electric_Participant,
	// Zero means context.allocator; tests use the temp allocator.
	allocator:    runtime.Allocator,
}

destroy_electric_networks :: proc(networks: ^Electric_Networks) {
	delete(networks.nodes)
	delete(networks.wires)
	delete(networks.networks)
	delete(networks.memberships)
	delete(networks.participants)
}

set_electric_allocators :: proc(networks: ^Electric_Networks) {
	if networks.nodes.allocator.procedure != nil {
		return
	}
	allocator := networks.allocator.procedure != nil ? networks.allocator : context.allocator
	networks.nodes.allocator, networks.wires.allocator = allocator, allocator
	networks.networks.allocator, networks.participants.allocator = allocator, allocator
	networks.memberships = make(map[Entity_Handle]int, allocator)
}

clear_electric_networks :: proc(networks: ^Electric_Networks) {
	set_electric_allocators(networks)
	clear(&networks.nodes)
	clear(&networks.wires)
	clear(&networks.networks)
	clear(&networks.memberships)
	clear(&networks.participants)
}

// The supply volume box of a pole at origin with the given footprint:
// centred across the footprint, from the pole's bottom up.
supply_volume_origin :: proc(origin: World_Coordinate, footprint, volume: [3]i32) -> World_Coordinate {
	return origin - {(volume.x - footprint.x) / 2, 0, (volume.z - footprint.z) / 2}
}

make_electric_node :: proc(pole: Pole, machine: Machine) -> Electric_Node {
	return Electric_Node {
		handle = pole.handle,
		origin = pole.origin,
		reach = machine.wire_reach,
		supply_origin = supply_volume_origin(pole.origin, pole.size, machine.supply_volume),
		supply_size = machine.kind == .Pole ? machine.supply_volume : {},
		active = machine.kind == .Pole || pole.on,
		network = -1,
	}
}

nodes_are_within_reach :: proc(first, second: Electric_Node) -> bool {
	offset := second.origin - first.origin
	reach := i64(min(first.reach, second.reach))
	return i64(offset.x) * i64(offset.x) + i64(offset.y) * i64(offset.y) + i64(offset.z) * i64(offset.z) <= reach * reach
}

find_electric_wires :: proc(networks: ^Electric_Networks) {
	for first in 0 ..< len(networks.nodes) {
		for second in first + 1 ..< len(networks.nodes) {
			if nodes_are_within_reach(networks.nodes[first], networks.nodes[second]) {
				append(&networks.wires, Electric_Wire{first, second})
			}
		}
	}
}

// Network ids in order of each network's first active node.
assign_electric_networks :: proc(nodes: []Electric_Node, wires: []Electric_Wire) -> int {
	parents := make([]int, len(nodes), context.temp_allocator)
	for &parent, index in parents {
		parent = index
	}
	for wire in wires {
		if nodes[wire.first].active && nodes[wire.second].active {
			first, second := union_find_root(parents, wire.first), union_find_root(parents, wire.second)
			parents[max(first, second)] = min(first, second)
		}
	}
	network_of_root := make([]int, len(nodes), context.temp_allocator)
	count := 0
	for &node, index in nodes {
		if !node.active {
			continue
		}
		root := union_find_root(parents, index)
		if root == index {
			network_of_root[index] = count
			count += 1
		}
		node.network = network_of_root[root]
	}
	return count
}

// The network of the first node whose supply volume covers a cell, or -1.
network_covering_cells :: proc(nodes: []Electric_Node, cells: []World_Coordinate) -> int {
	for node in nodes {
		if node.network < 0 || node.supply_size == {} {
			continue
		}
		for cell in cells {
			if cell_in_box(cell, node.supply_origin, node.supply_size) {
				return node.network
			}
		}
	}
	return -1
}

append_electric_members :: proc(networks: ^Electric_Networks, pool: ^Entity_Pool($T), machines: Machine_Registry) {
	for entry in pool.entries {
		if entry.alive && machine_touches_power(machines.machines[entry.machine]) {
			network := network_covering_cells(networks.nodes[:], common_cells(entry.common, machines))
			if network >= 0 {
				networks.memberships[entry.handle] = network
			}
		}
	}
}

assign_electric_memberships :: proc(entities: ^Entities, machines: Machine_Registry) {
	networks := &entities.electric_networks
	append_electric_members(networks, &entities.inserters, machines)
	append_electric_members(networks, &entities.drills, machines)
	append_electric_members(networks, &entities.fluid_machines, machines)
	append_electric_members(networks, &entities.lamps, machines)
	append_electric_members(networks, &entities.assemblers, machines)
	append_electric_members(networks, &entities.labs, machines)
}

rebuild_electric_networks :: proc(entities: ^Entities, machines: Machine_Registry) {
	networks := &entities.electric_networks
	clear_electric_networks(networks)
	for pole in entities.poles.entries {
		if pole.alive {
			append(&networks.nodes, make_electric_node(pole, machines.machines[pole.machine]))
		}
	}
	find_electric_wires(networks)
	resize(&networks.networks, assign_electric_networks(networks.nodes[:], networks.wires[:]))
	for &network in networks.networks {
		network = {}
	}
	assign_electric_memberships(entities, machines)
}

// The network an electric machine, generator, pole or switch belongs to,
// or -1.
entity_network :: proc(networks: ^Electric_Networks, handle: Entity_Handle) -> int {
	if network, found := networks.memberships[handle]; found {
		return network
	}
	for node in networks.nodes {
		if node.handle == handle {
			return node.network
		}
	}
	return -1
}

// The energy balance, pure.

power_satisfaction :: proc(supply, demand: u64) -> u32 {
	if demand == 0 {
		return supply > 0 ? POWER_FULL : 0
	}
	return u32(min(supply, demand) * POWER_FULL / demand)
}

// Sums the offers per network, sets each network's satisfaction, gives
// every consumer its demand times the satisfaction, and shares what the
// consumers received out over the generators: in proportion to their
// offers, rounded down, the rest a joule at a time in participant order.
balance_electric_energy :: proc(participants: []Electric_Participant, networks: []Electric_Network) {
	for &network in networks {
		network = {}
	}
	for participant in participants {
		if participant.network >= 0 {
			add_participant_offer(&networks[participant.network], participant)
		}
	}
	for &network in networks {
		network.satisfaction = power_satisfaction(network.supply, network.demand)
	}
	for &participant in participants {
		participant.delivered = 0
		if participant.network >= 0 && !participant.generator {
			network := &networks[participant.network]
			participant.delivered = participant.offered * u64(network.satisfaction) / POWER_FULL
			network.delivered += participant.delivered
		}
	}
	share_generator_energy(participants, networks)
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

share_generator_energy :: proc(participants: []Electric_Participant, networks: []Electric_Network) {
	assigned := make([]u64, len(networks), context.temp_allocator)
	for &participant in participants {
		if participant.network >= 0 && participant.generator && networks[participant.network].supply > 0 {
			network := networks[participant.network]
			participant.delivered = participant.offered * network.delivered / network.supply
			assigned[participant.network] += participant.delivered
		}
	}
	for &participant in participants {
		if participant.network >= 0 && participant.generator {
			extra := min(networks[participant.network].delivered - assigned[participant.network], participant.offered - participant.delivered)
			participant.delivered += extra
			assigned[participant.network] += extra
		}
	}
}

// The tick.

// While it has room and something to do: bore, mine, or mine a revived vein.
drill_wants_power :: proc(world: ^World, drill: Drill, machine: Machine, tick_rate: int) -> bool {
	vein := registered_vein(world, drill.vein)
	return stack_is_empty(drill.held) && drill_activity(drill, machine, vein, world.settings.veins_infinite, tick_rate) != .Vein_Exhausted
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

// Pumps while they can move fluid, tar pit pumps while there is room,
// flare stacks while they relieve gas.
fluid_machine_wants_power :: proc(fluid_machine: Fluid_Machine, machine: Machine, fluids: Fluid_Registry) -> bool {
	#partial switch machine.kind {
	case .Pump:
		return pump_wants_power(fluid_machine, machine)
	case .Tar_Pit_Pump:
		return source_pump_has_room(fluid_machine, machine)
	case .Flare_Stack:
		return flare_stack_is_relieving(fluid_machine, machine, fluids)
	}
	return false
}

make_participant :: proc(networks: ^Electric_Networks, common: Entity_Common, generator: bool, offered: u64) -> Electric_Participant {
	return Electric_Participant{handle = common.handle, machine = common.machine, network = entity_network(networks, common.handle), generator = generator, offered = offered}
}

// What every electric entity asks for or offers this tick, in pool order.
collect_electric_participants :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	machines := content.machines
	entities := &world.entities
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
			demand := drill_wants_power(world, drill, machine, tick_rate) ? electric_joules_per_tick(machine.electric_power_watts, tick_rate) : 0
			append(&networks.participants, make_participant(networks, drill.common, false, demand))
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		machine := machines.machines[fluid_machine.machine]
		switch {
		case !fluid_machine.alive:
		case machine_is_generator(machine):
			offer := generator_available_joules(world, fluid_machine, machine, content, tick_rate)
			append(&networks.participants, make_participant(networks, fluid_machine.common, true, offer))
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
	collect_crafting_participants(world, content, tick_rate)
}

// Electric crafting machines and labs, while they have work.
collect_crafting_participants :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	entities := &world.entities
	networks := &entities.electric_networks
	for assembler in entities.assemblers.entries {
		machine := content.machines.machines[assembler.machine]
		if assembler.alive && crafting_machine_is_electric(machine) {
			watts := machine.electric_power_watts
			wants := assembler_wants_power(assembler, machine, content.recipes, content.items, world.settings.byproducts_lenient)
			demand := wants ? electric_joules_per_tick(watts, tick_rate) : 0
			append(&networks.participants, make_participant(networks, assembler.common, false, demand))
		}
	}
	for lab in entities.labs.entries {
		if lab.alive {
			watts := content.machines.machines[lab.machine].electric_power_watts
			wants := lab_wants_power(lab, world.research, content.technologies, content.machines.lab_packs)
			append(&networks.participants, make_participant(networks, lab.common, false, wants ? electric_joules_per_tick(watts, tick_rate) : 0))
		}
	}
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
	}
	return nil
}

// Generators draw their steam, gas and fuel items here, so they are
// counted consumed here.
apply_electric_balance :: proc(entities: ^Entities, content: Simulation_Content, statistics: ^Statistics) {
	networks := &entities.electric_networks
	for participant in networks.participants {
		network := participant.network >= 0 ? networks.networks[participant.network] : Electric_Network{}
		if !participant.generator {
			participant_power(entities, participant.handle).satisfaction = network.satisfaction
			continue
		}
		generator := pool_get(&entities.fluid_machines, participant.handle)
		machine := content.machines.machines[generator.machine]
		before := generator^
		deliver_generator_energy(generator, machine, content, participant.delivered)
		record_generator_tick(statistics, machine.kind, before, generator^)
		generator.state = generator_state(machine.kind, participant.delivered, participant.offered, network.demand)
	}
}

// Fluids drawn, the gas of combustion generators, and fuel items lit from
// the slot as burned and consumed.
record_generator_tick :: proc(statistics: ^Statistics, kind: Machine_Kind, before, after: Fluid_Machine) {
	buffers_before, buffers_after := before.buffers, after.buffers
	record_buffer_changes(statistics, buffers_before[:], buffers_after[:])
	if kind == .Combustion_Generator {
		statistics.generator_gas_litres += u64(max(before.buffers[0].level - after.buffers[0].level, 0))
	}
	slots_before, slots_after := before.slots, after.slots
	for slot, index in slots_before[:before.slot_count] {
		statistics.fuel_burned += u64(stack_shrink(slot, slots_after[index]))
	}
	record_slot_consumption(statistics, slots_before[:before.slot_count], slots_after[:after.slot_count])
}

// Energy and brownouts for the overview and the quest hints.
record_electric_tick :: proc(statistics: ^Statistics, networks: ^Electric_Networks) {
	unpowered := 0
	for participant in networks.participants {
		if participant.network < 0 && !participant.generator {
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
tick_electric_networks :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	networks := &world.entities.electric_networks
	set_electric_allocators(networks)
	collect_electric_participants(world, content, tick_rate)
	balance_electric_energy(networks.participants[:], networks.networks[:])
	apply_electric_balance(&world.entities, content, &world.statistics)
	record_electric_tick(&world.statistics, networks)
}
