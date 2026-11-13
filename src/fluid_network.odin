package game

import "base:runtime"
import "core:fmt"
import "netlist"

// Fluid netlists (doc/fluids.md, Fluid netlists, work item 0356): the
// pipes simulated as a netlist like power, with no gravity in a pipe. A
// node is a machine's fluid port (in pool and port order: the fluid
// machines, the crafting machines, the drills, the launch pads), a
// junction of the block world's pipes that touch, one node per group after
// the ports, or a fluid junction (0374), one node each after those in the
// poles' pool order. Pipes and junctions hold nothing. A joint is a face
// where a port meets a pipe or another port facing back, an edge of the
// pipe's flow_litres_per_second; joints between one pair bundle (a tank on
// a pipe by three faces carries three). Joints are looked up on the block
// frame only. On the field a hand run pipe (0374, a record of the cable
// table) is an edge of its litres a second between the nodes its two
// ports meet (pipe_edges). Edge capacities are litres a second; each
// node's capacity a tick is its bundled edge's over the tick rate, floored
// (scale_fluid_capacities). The netlist is rebuilt whenever a pipe, a
// fluid junction or a machine with ports is placed or removed, and when a
// hand run pipe is laid or taken up; the litres live in the port buffers,
// so a rebuild keeps them.
//
// Per tick, in whole litres: an output port offers what it holds at
// FLUID_PRODUCER_ORDER, an input port asks for its room, a storage tank's
// port is a store (it offers at FLUID_STORE_ORDER and takes what the
// producers leave once the consumers are served, never from another tank),
// and a flare stack's port is a store offering nothing, a relief valve
// that takes nothing while a tank on its netlist has room; each capped at
// the litres its joints carry a tick. netlist.solve moves
// litres port buffer to port buffer with the rounding top-up, so what the
// per mille levels leave goes to the first consumers of the walk and no
// line stalls. Height plays no part; a gas moves as a liquid does.
//
// One fluid per netlist, decided each tick from the saved buffers and
// closed flags: the fluid of the first port in node order holding litres
// of the best kind, an open output or tank port, else a closed one, else
// an open input port (fluid_claim_rank). A feeding port holding litres
// outranks every inlet, an inlet names a line only while no feeder holds
// any.
// A port holding another fluid, or whose filter or phase filter refuses
// the netlist's, is closed and moves nothing; each closing counts as a
// mixing refusal.

FLUID_PRODUCER_ORDER :: 0
FLUID_STORE_ORDER :: 1

// port is -1 for a junction, whose owner is its first pipe in pool order,
// or the fluid junction itself (0374). relief marks a flare stack's port.
Fluid_Node :: struct {
	owner:        Entity_Handle,
	port:         i32,
	direction:    Fluid_Port_Direction,
	filter:       Fluid_Id,
	phase_filter: Fluid_Phase_Filter,
	capacity:     i32,
	relief:       bool,
}

// Derived, never saved. The topology's capacities are litres a second;
// capacity is litres a tick on each node's edge to its parent and
// connection on all its tree edges, both at scaled_tick_rate (-1 until
// scaled); netlist_fluids is per tree. junction_of maps a block world pipe
// to its group's node and a fluid junction to its own.
Fluid_Networks :: struct {
	nodes:            [dynamic]Fluid_Node,
	first_port_node:  map[Entity_Handle]u32,
	junction_of:      map[Entity_Handle]u32,
	topology:         netlist.Topology,
	capacity:         [dynamic]i64,
	connection:       [dynamic]i64,
	scaled_tick_rate: i64,
	netlist_fluids:   [dynamic]Fluid_Id,
	inputs:           [dynamic]netlist.Node_Input,
	outputs:          [dynamic]netlist.Node_Output,
	// Presentation only, kept across rebuilds: per pipe pool slot, per
	// hand run pipe by its table index (0374), and the ticks of the running
	// second.
	pipe_seconds:      [dynamic]Pipe_Second,
	pipe_line_seconds: [dynamic]Pipe_Line_Second,
	second_tick:       int,
	// Zero means context.allocator; tests use the temp allocator.
	allocator:        runtime.Allocator,
}

// The litres entering a pipe's junction over the running second and the
// last full one, so its panel reads a steady rate where the per tick flow
// jumps between a slow line's litres and 0. Never saved or hashed.
Pipe_Second :: struct {
	pipe:    Entity_Handle,
	running: i64,
	last:    i64,
}

// The litres through a hand run pipe (0374) over the running second and
// the last full one, by its table index, positive from the record's first
// end towards its second (pipe_record_litres); end is the record's first
// end, so a record moved into a removed one's index starts afresh. Never
// saved or hashed.
Pipe_Line_Second :: struct {
	end:     Port_End,
	running: i64,
	last:    i64,
}

fluid_allocator :: proc(networks: ^Fluid_Networks) -> runtime.Allocator {
	return networks.allocator.procedure != nil ? networks.allocator : context.allocator
}

destroy_fluid_networks :: proc(networks: ^Fluid_Networks) {
	netlist.destroy_topology(&networks.topology, fluid_allocator(networks))
	delete(networks.nodes)
	delete(networks.first_port_node)
	delete(networks.junction_of)
	delete(networks.capacity)
	delete(networks.connection)
	delete(networks.netlist_fluids)
	delete(networks.inputs)
	delete(networks.outputs)
	delete(networks.pipe_seconds)
	delete(networks.pipe_line_seconds)
}

clear_fluid_networks :: proc(networks: ^Fluid_Networks) {
	allocator := fluid_allocator(networks)
	if networks.nodes.allocator.procedure == nil {
		networks.nodes.allocator, networks.capacity.allocator = allocator, allocator
		networks.connection.allocator, networks.netlist_fluids.allocator = allocator, allocator
		networks.inputs.allocator, networks.outputs.allocator = allocator, allocator
		networks.pipe_seconds.allocator, networks.pipe_line_seconds.allocator = allocator, allocator
		networks.first_port_node = make(map[Entity_Handle]u32, allocator)
		networks.junction_of = make(map[Entity_Handle]u32, allocator)
	}
	netlist.destroy_topology(&networks.topology, allocator)
	clear(&networks.nodes)
	clear(&networks.first_port_node)
	clear(&networks.junction_of)
	networks.scaled_tick_rate = -1
}

// The live entries' ports, in pool and port order.
append_port_nodes :: proc(networks: ^Fluid_Networks, pool: ^Entity_Pool($T), machines: Machine_Registry) {
	for &entry in pool.entries {
		machine := machines.machines[entry.machine]
		if !entry.alive || machine.fluid_port_count == 0 {
			continue
		}
		networks.first_port_node[entry.handle] = u32(len(networks.nodes))
		for port, index in fluid_ports_of(machine) {
			node := Fluid_Node {
				owner        = entry.handle,
				port         = i32(index),
				direction    = port.direction,
				filter       = port.filter,
				phase_filter = port.phase_filter,
				capacity     = port.capacity,
				relief       = machine.kind == .Flare_Stack,
			}
			append(&networks.nodes, node)
		}
	}
}

// Every port of every live fluid machine, crafting machine with ports (a
// washer), drill with a revival port and launch pad.
collect_fluid_nodes :: proc(entities: ^Entities, machines: Machine_Registry) {
	networks := &entities.fluid_networks
	append_port_nodes(networks, &entities.fluid_machines, machines)
	append_port_nodes(networks, &entities.assemblers, machines)
	append_port_nodes(networks, &entities.drills, machines)
	append_port_nodes(networks, &entities.launch_pads, machines)
}

is_positive_direction :: proc(direction: Direction) -> bool {
	return direction == .Positive_X || direction == .Positive_Y || direction == .Positive_Z
}

union_find_root :: proc(parents: []int, index: int) -> int {
	root := index
	for parents[root] != root {
		root = parents[root]
	}
	return root
}

// The block frame's pipes joined face to face, one junction node per group
// after the ports, in the order of each group's first pipe; fills
// junction_of. Returns the pipe cells, in the temp allocator.
collect_pipe_junctions :: proc(entities: ^Entities) -> map[World_Coordinate]Entity_Handle {
	networks := &entities.fluid_networks
	pipes := entities.pipes.entries[:]
	pipe_cells := make(map[World_Coordinate]Entity_Handle, context.temp_allocator)
	for pipe in pipes {
		if pipe.alive && pipe.frame == BLOCK_FRAME {
			pipe_cells[pipe.origin] = pipe.handle
		}
	}
	parents := make([]int, len(pipes), context.temp_allocator)
	for &parent, index in parents {
		parent = index
	}
	for pipe, index in pipes {
		if !pipe.alive || pipe.frame != BLOCK_FRAME {
			continue
		}
		for face in Direction {
			if !is_positive_direction(face) {
				continue
			}
			if other, found := pipe_cells[pipe.origin + World_Coordinate(direction_offsets[face])]; found {
				first, second := union_find_root(parents, index), union_find_root(parents, int(other.index))
				parents[max(first, second)] = min(first, second)
			}
		}
	}
	for pipe, index in pipes {
		if !pipe.alive || pipe.frame != BLOCK_FRAME {
			continue
		}
		root := union_find_root(parents, index)
		if root == index {
			networks.junction_of[pipe.handle] = u32(len(networks.nodes))
			append(&networks.nodes, Fluid_Node{owner = pipe.handle, port = -1, direction = .Both, filter = NO_FLUID})
		} else {
			networks.junction_of[pipe.handle] = networks.junction_of[pipes[root].handle]
		}
	}
	return pipe_cells
}

// One node per live fluid junction (0374) in the poles' pool order, after
// the block junctions; it holds nothing.
collect_fluid_junctions :: proc(entities: ^Entities, machines: Machine_Registry) {
	networks := &entities.fluid_networks
	for pole in entities.poles.entries {
		if !pole.alive || machines.machines[pole.machine].kind != .Fluid_Junction {
			continue
		}
		networks.junction_of[pole.handle] = u32(len(networks.nodes))
		append(&networks.nodes, Fluid_Node{owner = pole.handle, port = -1, direction = .Both, filter = NO_FLUID})
	}
}

// Placing or removing it changes the fluid netlist's nodes (0374): a block
// world pipe, a machine with fluid ports or a fluid junction.
machine_touches_fluids :: proc(machine: Machine) -> bool {
	return machine.kind == .Pipe || machine.fluid_port_count > 0 || machine.kind == .Fluid_Junction
}

// The node a hand run pipe's end meets (0374): a fluid junction's own, else
// the node of the buffer the port meets (Machine_Port.fluid_buffer); -1
// for none.
pipe_end_node :: proc(networks: ^Fluid_Networks, entities: ^Entities, machines: Machine_Registry, end: Port_End) -> int {
	if junction, found := networks.junction_of[end.entity]; found && end.entity.kind == .Pole {
		return int(junction)
	}
	common := entity_common(entities, end.entity)
	if common == nil {
		return -1
	}
	machine := machines.machines[common.machine]
	if int(end.port) >= machine.port_count || machine.ports[end.port].fluid_buffer < 0 {
		return -1
	}
	return fluid_node_of(networks, end.entity, int(machine.ports[end.port].fluid_buffer))
}

// One edge of its litres a second per hand run pipe whose two ends have
// nodes (0374), in the table's order (the topology is the same for any
// order). A loop of pipes lays a chord that carries nothing until 0377.
// In the temp allocator.
pipe_edges :: proc(networks: ^Fluid_Networks, entities: ^Entities, machines: Machine_Registry) -> []netlist.Edge {
	table := &entities.cables
	edges := make([dynamic]netlist.Edge, 0, len(table.cables), context.temp_allocator)
	for cable, index in table.cables {
		if table.kinds[index] != .Fluid {
			continue
		}
		first := pipe_end_node(networks, entities, machines, cable.ends[0])
		second := pipe_end_node(networks, entities, machines, cable.ends[1])
		if first >= 0 && second >= 0 && first != second {
			append(&edges, netlist.Edge{u32(first), u32(second), table.capacity[index]})
		}
	}
	return edges[:]
}

// The litres a second one joint of the block world carries: the pipe
// machine's flow_litres_per_second, 0 without one.
block_joint_litres_per_second :: proc(machines: Machine_Registry) -> i64 {
	pipe := find_machine_of_kind(machines, .Pipe)
	if pipe == NO_MACHINE {
		return 0
	}
	return i64(machines.machines[pipe].flow_litres_per_second)
}

// The node that meets face of cell from outside on the block frame, or
// -1: a pipe's junction through any face, a machine's port only facing
// that way.
fluid_node_at_face :: proc(entities: ^Entities, machines: Machine_Registry, networks: ^Fluid_Networks, pipe_cells: map[World_Coordinate]Entity_Handle, cell: World_Coordinate, face: Direction) -> int {
	if pipe, found := pipe_cells[cell]; found {
		return int(networks.junction_of[pipe])
	}
	handle := entity_at(entities, cell)
	first, found := networks.first_port_node[handle]
	if !found {
		return -1
	}
	common := entity_common(entities, handle)
	port := port_at_face(common^, machines.machines[common.machine], cell, face)
	return port < 0 ? -1 : int(first) + port
}

// The faces a port meets others through, in the temp allocator; none off
// the block frame.
fluid_port_faces :: proc(entities: ^Entities, machines: Machine_Registry, node: Fluid_Node) -> []Cell_Face {
	common := entity_common(entities, node.owner)
	if common.frame != BLOCK_FRAME {
		return nil
	}
	machine := machines.machines[common.machine]
	return placed_port_faces(common^, machine, machine.fluid_ports[node.port])
}

// Every joint once, an edge of the block joint's litres a second: through
// the positive faces of each block frame pipe and port only, since the
// partner meets the same joint through a negative one. In the temp
// allocator.
fluid_joint_edges :: proc(entities: ^Entities, machines: Machine_Registry, networks: ^Fluid_Networks, pipe_cells: map[World_Coordinate]Entity_Handle) -> [dynamic]netlist.Edge {
	edges := make([dynamic]netlist.Edge, 0, len(networks.nodes), context.temp_allocator)
	joint := block_joint_litres_per_second(machines)
	for pipe in entities.pipes.entries {
		junction, found := networks.junction_of[pipe.handle]
		if !pipe.alive || !found {
			continue
		}
		for face in Direction {
			append_fluid_joint(&edges, entities, machines, networks, pipe_cells, int(junction), Cell_Face{pipe.origin, face}, joint)
		}
	}
	for node, index in networks.nodes {
		if node.port < 0 {
			continue
		}
		for face in fluid_port_faces(entities, machines, node) {
			append_fluid_joint(&edges, entities, machines, networks, pipe_cells, index, face, joint)
		}
	}
	return edges
}

append_fluid_joint :: proc(edges: ^[dynamic]netlist.Edge, entities: ^Entities, machines: Machine_Registry, networks: ^Fluid_Networks, pipe_cells: map[World_Coordinate]Entity_Handle, node: int, face: Cell_Face, joint: i64) {
	if !is_positive_direction(face.face) {
		return
	}
	neighbour := face.cell + World_Coordinate(direction_offsets[face.face])
	partner := fluid_node_at_face(entities, machines, networks, pipe_cells, neighbour, opposite_directions[face.face])
	if partner >= 0 && partner != node {
		append(edges, netlist.Edge{u32(node), u32(partner), joint})
	}
}

rebuild_fluid_networks :: proc(entities: ^Entities, machines: Machine_Registry) {
	networks := &entities.fluid_networks
	clear_fluid_networks(networks)
	collect_fluid_nodes(entities, machines)
	pipe_cells := collect_pipe_junctions(entities)
	collect_fluid_junctions(entities, machines)
	edges := fluid_joint_edges(entities, machines, networks, pipe_cells)
	append(&edges, ..pipe_edges(networks, entities, machines))
	node_count := len(networks.nodes)
	networks.topology = netlist.build_topology(node_count, edges[:], fluid_allocator(networks))
	resize(&networks.capacity, node_count)
	resize(&networks.connection, node_count)
	resize(&networks.inputs, node_count)
	resize(&networks.outputs, node_count)
	resize(&networks.netlist_fluids, len(networks.topology.trees))
}

// Litres a tick: each bundled edge's litres a second over the tick rate,
// floored after bundling, and each node's connection, its own edge's and
// its children's.
scale_fluid_capacities :: proc(networks: ^Fluid_Networks, tick_rate: int) {
	rate := i64(max(tick_rate, 1))
	if rate == networks.scaled_tick_rate {
		return
	}
	for node in 0 ..< len(networks.nodes) {
		networks.capacity[node] = networks.topology.capacity[node] / rate
		networks.connection[node] = networks.capacity[node]
	}
	for node in 0 ..< len(networks.nodes) {
		if parent := networks.topology.parent[node]; parent != netlist.NO_NODE {
			networks.connection[parent] += networks.capacity[node]
		}
	}
	networks.scaled_tick_rate = rate
}

// A port's buffer and closed flag, nil for a junction or a gone entity.
fluid_node_buffer :: proc(entities: ^Entities, node: Fluid_Node) -> (buffer: ^Fluid_Buffer, closed: ^bool) {
	if node.port < 0 {
		return nil, nil
	}
	buffers, closed_flags := entity_port_buffers(entities, node.owner)
	if buffers == nil {
		return nil, nil
	}
	return &buffers[node.port], &closed_flags[node.port]
}

// A port holding another fluid, or empty but only taking another fluid or
// refusing it by phase (or fuel value), would mix.
fluid_port_is_closed :: proc(node: Fluid_Node, buffer: Fluid_Buffer, fluid: Fluid_Id, fluids: Fluid_Registry) -> bool {
	if !phase_filter_admits(node.phase_filter, fluids, fluid) {
		return true
	}
	if buffer.level > 0 {
		return buffer.fluid != fluid
	}
	return node.filter != NO_FLUID && node.filter != fluid
}

// Which port holding litres decides its netlist's fluid, lowest first: an
// open output or tank port, a closed one, an open input port. A port that
// feeds the line and holds litres so outranks every inlet, and an inlet
// (an unpowered pump's, a flare's, a recipe's unused one) names a line
// only while no feeder holds any. Open is the closed flag from the last
// tick.
fluid_claim_rank :: proc(node: Fluid_Node, closed: bool) -> int {
	switch {
	case node.direction != .Input:
		return closed ? 1 : 0
	case !closed:
		return 2
	}
	return FLUID_CLAIM_NONE
}

FLUID_CLAIM_NONE :: 3

// Per tree, one pass in node order: the fluid of the first port holding
// litres of the lowest claim rank, else none.
decide_netlist_fluids :: proc(entities: ^Entities, networks: ^Fluid_Networks) {
	ranks := make([]int, len(networks.netlist_fluids), context.temp_allocator)
	for &fluid, tree in networks.netlist_fluids {
		fluid, ranks[tree] = NO_FLUID, FLUID_CLAIM_NONE
	}
	for node, index in networks.nodes {
		buffer, closed := fluid_node_buffer(entities, node)
		if buffer == nil || buffer.level <= 0 {
			continue
		}
		tree := networks.topology.tree_of[index]
		if rank := fluid_claim_rank(node, closed^); rank < ranks[tree] {
			networks.netlist_fluids[tree], ranks[tree] = buffer.fluid, rank
		}
	}
}

// Each port's closed flag against its netlist's fluid; returns how many
// closed that were open in the last tick.
close_mixing_ports :: proc(entities: ^Entities, networks: ^Fluid_Networks, fluids: Fluid_Registry) -> (refusals: u64) {
	for node, index in networks.nodes {
		buffer, closed := fluid_node_buffer(entities, node)
		if buffer == nil {
			continue
		}
		fluid := networks.netlist_fluids[networks.topology.tree_of[index]]
		now_closed := fluid != NO_FLUID && fluid_port_is_closed(node, buffer^, fluid, fluids)
		refusals += now_closed && !closed^ ? 1 : 0
		closed^ = now_closed
	}
	return refusals
}

// Per netlist, whether an open storage tank port on it has room, read
// from the buffers before the solve. A flare is a relief valve: it takes
// nothing while one has (relief_room).
netlists_with_tank_room :: proc(entities: ^Entities, networks: ^Fluid_Networks) -> []bool {
	has_room := make([]bool, len(networks.netlist_fluids), context.temp_allocator)
	for node, index in networks.nodes {
		if node.direction != .Both || node.relief {
			continue
		}
		buffer, closed := fluid_node_buffer(entities, node)
		if buffer != nil && !closed^ && buffer.level < node.capacity {
			has_room[networks.topology.tree_of[index]] = true
		}
	}
	return has_room
}

// A flare's charge room: none while a tank on its netlist has room, so the
// leftover a tank cannot take backs up: for a tick when the tanks' last
// room is smaller than it, and for as long as the through flow saturates
// the joint of a tank with room.
relief_room :: proc(input: netlist.Node_Input, tank_has_room: bool) -> netlist.Node_Input {
	relieved := input
	if tank_has_room {
		relieved.charge_room = 0
	}
	return relieved
}

// What a port offers, asks and can store this tick, each capped at its
// connection; nothing for a closed port.
fluid_node_input :: proc(node: Fluid_Node, buffer: Fluid_Buffer, closed: bool, connection: i64) -> netlist.Node_Input {
	if closed {
		return {}
	}
	litres := min(i64(buffer.level), connection)
	room := min(i64(max(node.capacity - buffer.level, 0)), connection)
	switch {
	case node.relief:
		return {charge_room = room, order = FLUID_STORE_ORDER, store = true}
	case node.direction == .Output:
		return {offer = litres, order = FLUID_PRODUCER_ORDER}
	case node.direction == .Input:
		return {demand = room}
	}
	return {offer = litres, charge_room = room, order = FLUID_STORE_ORDER, store = true}
}

// Each port's buffer by what it received, was charged and supplied; a
// port that received takes the netlist's fluid.
apply_fluid_outputs :: proc(entities: ^Entities, networks: ^Fluid_Networks) {
	for node, index in networks.nodes {
		buffer, _ := fluid_node_buffer(entities, node)
		output := networks.outputs[index]
		received := output.delivered + output.charged
		if buffer == nil || received + output.supplied == 0 {
			continue
		}
		buffer.level += i32(received - output.supplied)
		if received > 0 {
			buffer.fluid = networks.netlist_fluids[networks.topology.tree_of[index]]
		}
		buffer.flow_in, buffer.flow_out = i32(received), i32(output.supplied)
	}
}

// Pipes hold nothing: each block frame pipe shows its netlist's fluid and
// the litres entering its junction this tick, in and out, which also count
// towards its second; each hand run pipe's litres this tick
// (pipe_record_litres) count towards its own (0374).
show_pipe_flows :: proc(entities: ^Entities, networks: ^Fluid_Networks, machines: Machine_Registry, tick_rate: int) {
	entering := make([]i64, len(networks.nodes), context.temp_allocator)
	for node in 0 ..< len(networks.nodes) {
		if parent := networks.topology.parent[node]; parent != netlist.NO_NODE {
			flow := networks.outputs[node].flow
			entering[parent] += max(flow, 0)
			entering[node] += max(-flow, 0)
		}
	}
	for &pipe in entities.pipes.entries {
		junction, found := networks.junction_of[pipe.handle]
		if !pipe.alive || !found {
			continue
		}
		litres := i32(entering[junction])
		fluid := networks.netlist_fluids[networks.topology.tree_of[junction]]
		pipe.buffer = Fluid_Buffer{fluid = fluid, level = 0, flow_in = litres, flow_out = litres}
		count_pipe_second(networks, pipe.handle, i64(litres))
	}
	table := &entities.cables
	// A world whose netlists were never rebuilt (cables only) has not set
	// the allocator yet (clear_fluid_networks).
	if networks.pipe_line_seconds.allocator.procedure == nil {
		networks.pipe_line_seconds.allocator = fluid_allocator(networks)
	}
	resize(&networks.pipe_line_seconds, len(table.cables))
	for cable, index in table.cables {
		if table.kinds[index] != .Fluid {
			continue
		}
		second := &networks.pipe_line_seconds[index]
		if second.end != cable.ends[0] {
			second^ = {end = cable.ends[0]}
		}
		second.running += pipe_record_litres(networks, table, entities, machines, index)
	}
	roll_pipe_seconds(networks, tick_rate)
}

// A hand run pipe's share of its bundle's flow this tick, as cable_load
// takes a cable's: the bundle's flow times its capacity over the bundle's,
// positive from the record's first end towards its second and negative
// the other way; 0 for a chord, an end without a node or a record that is
// no pipe.
pipe_record_litres :: proc(networks: ^Fluid_Networks, table: ^Cable_Table, entities: ^Entities, machines: Machine_Registry, index: int) -> i64 {
	if index < 0 || index >= len(table.cables) || table.kinds[index] != .Fluid || len(networks.outputs) != len(networks.nodes) {
		return 0
	}
	cable := table.cables[index]
	first := pipe_end_node(networks, entities, machines, cable.ends[0])
	second := pipe_end_node(networks, entities, machines, cable.ends[1])
	if first < 0 || second < 0 {
		return 0
	}
	child, child_end := cable_tree_child(networks.topology, first, second)
	if child < 0 {
		return 0
	}
	bundled := networks.topology.capacity[child]
	if bundled <= 0 {
		return 0
	}
	flow := networks.outputs[child].flow
	litres := i64(i128(abs(flow)) * i128(table.capacity[index]) / i128(bundled))
	// A positive flow leaves the child for its parent (show_pipe_flows).
	return (flow > 0) == (child_end == 0) ? litres : -litres
}

// The litres through a hand run pipe in the last full second, positive
// from its first end towards its second; 0 before its first roll or for a
// record whose seconds belong to another.
pipe_line_net_litres_last_second :: proc(networks: ^Fluid_Networks, table: ^Cable_Table, index: int) -> i64 {
	if index < 0 || index >= len(table.cables) || index >= len(networks.pipe_line_seconds) {
		return 0
	}
	second := networks.pipe_line_seconds[index]
	return second.end == table.cables[index].ends[0] ? second.last : 0
}

// The litres through a hand run pipe in the last full second, either way.
pipe_line_litres_last_second :: proc(networks: ^Fluid_Networks, table: ^Cable_Table, index: int) -> i64 {
	return abs(pipe_line_net_litres_last_second(networks, table, index))
}

// The netlist fluid of a hand run pipe's tree, NO_FLUID without a node.
pipe_record_fluid :: proc(networks: ^Fluid_Networks, table: ^Cable_Table, entities: ^Entities, machines: Machine_Registry, index: int) -> Fluid_Id {
	if index < 0 || index >= len(table.cables) {
		return NO_FLUID
	}
	node := pipe_end_node(networks, entities, machines, table.cables[index].ends[0])
	if node < 0 || node >= len(networks.topology.tree_of) {
		return NO_FLUID
	}
	tree := networks.topology.tree_of[node]
	if int(tree) >= len(networks.netlist_fluids) {
		return NO_FLUID
	}
	return networks.netlist_fluids[tree]
}

// A slot taken by another pipe starts its seconds afresh.
count_pipe_second :: proc(networks: ^Fluid_Networks, pipe: Entity_Handle, litres: i64) {
	if int(pipe.index) >= len(networks.pipe_seconds) {
		resize(&networks.pipe_seconds, int(pipe.index) + 1)
	}
	second := &networks.pipe_seconds[pipe.index]
	if second.pipe != pipe {
		second^ = {pipe = pipe}
	}
	second.running += litres
}

// At the second's edge, every tick_rate ticks, the running sums become the
// last full second's.
roll_pipe_seconds :: proc(networks: ^Fluid_Networks, tick_rate: int) {
	networks.second_tick += 1
	if networks.second_tick < tick_rate {
		return
	}
	networks.second_tick = 0
	for &second in networks.pipe_seconds {
		second.last, second.running = second.running, 0
	}
	for &second in networks.pipe_line_seconds {
		second.last, second.running = second.running, 0
	}
}

// The litres through a pipe in the last full second, 0 before its first
// roll. The seconds run from the world's load, not from the pipe's
// placing, so a new pipe's first roll counts a partial second.
pipe_litres_last_second :: proc(networks: ^Fluid_Networks, pipe: Entity_Handle) -> i64 {
	if int(pipe.index) >= len(networks.pipe_seconds) || networks.pipe_seconds[pipe.index].pipe != pipe {
		return 0
	}
	return networks.pipe_seconds[pipe.index].last
}

// The port buffers and closed flags of an entity with fluid ports, or nil.
entity_port_buffers :: proc(entities: ^Entities, handle: Entity_Handle) -> (buffers: ^[MAXIMUM_FLUID_PORTS]Fluid_Buffer, closed: ^[MAXIMUM_FLUID_PORTS]bool) {
	#partial switch handle.kind {
	case .Fluid_Machine:
		if fluid_machine := pool_get(&entities.fluid_machines, handle); fluid_machine != nil {
			return &fluid_machine.buffers, &fluid_machine.closed
		}
	case .Assembler:
		if assembler := pool_get(&entities.assemblers, handle); assembler != nil {
			return &assembler.buffers, &assembler.closed
		}
	case .Drill:
		if drill := pool_get(&entities.drills, handle); drill != nil {
			return &drill.buffers, &drill.closed
		}
	case .Launch_Pad:
		if pad := pool_get(&entities.launch_pads, handle); pad != nil {
			return &pad.buffers, &pad.closed
		}
	}
	return nil, nil
}

reset_fluid_flows :: proc(entities: ^Entities) {
	for &pipe in entities.pipes.entries {
		pipe.buffer.flow_in, pipe.buffer.flow_out = 0, 0
	}
	for &fluid_machine in entities.fluid_machines.entries {
		for &buffer in fluid_machine.buffers {
			buffer.flow_in, buffer.flow_out = 0, 0
		}
	}
	for &assembler in entities.assemblers.entries {
		for &buffer in assembler.buffers {
			buffer.flow_in, buffer.flow_out = 0, 0
		}
	}
	for &drill in entities.drills.entries {
		for &buffer in drill.buffers {
			buffer.flow_in, buffer.flow_out = 0, 0
		}
	}
	for &pad in entities.launch_pads.entries {
		for &buffer in pad.buffers {
			buffer.flow_in, buffer.flow_out = 0, 0
		}
	}
}

// Every tick over every port. A nil statistics (tests) records no mixing
// refusals.
tick_fluid_networks :: proc(entities: ^Entities, fluids: Fluid_Registry, machines: Machine_Registry, tick_rate: int, statistics: ^Statistics = nil) {
	reset_fluid_flows(entities)
	networks := &entities.fluid_networks
	scale_fluid_capacities(networks, tick_rate)
	decide_netlist_fluids(entities, networks)
	refusals := close_mixing_ports(entities, networks, fluids)
	if statistics != nil {
		statistics.mixing_refusals += refusals
	}
	tank_room := netlists_with_tank_room(entities, networks)
	for node, index in networks.nodes {
		networks.inputs[index] = {}
		if buffer, closed := fluid_node_buffer(entities, node); buffer != nil {
			input := fluid_node_input(node, buffer^, closed^, networks.connection[index])
			if node.relief {
				input = relief_room(input, tank_room[networks.topology.tree_of[index]])
			}
			networks.inputs[index] = input
		}
	}
	topology := networks.topology
	topology.capacity = networks.capacity[:]
	netlist.solve(topology, networks.inputs[:], networks.outputs[:], top_up = true)
	apply_fluid_outputs(entities, networks)
	show_pipe_flows(entities, networks, machines, tick_rate)
}

// The node of a machine's port, or for port -1 of a block pipe's junction
// or a fluid junction; -1 for none.
fluid_node_of :: proc(networks: ^Fluid_Networks, owner: Entity_Handle, port: int) -> int {
	if port < 0 {
		junction, found := networks.junction_of[owner]
		return found ? int(junction) : -1
	}
	first, found := networks.first_port_node[owner]
	node := int(first) + port
	if !found || node >= len(networks.nodes) || networks.nodes[node].owner != owner {
		return -1
	}
	return node
}

// The netlist (tree) of a pipe, a fluid junction (port -1) or a machine
// port, or -1.
fluid_netlist_of :: proc(networks: ^Fluid_Networks, owner: Entity_Handle, port: int) -> int {
	node := fluid_node_of(networks, owner, port)
	return node < 0 ? -1 : int(networks.topology.tree_of[node])
}

fluid_netlist_count :: proc(networks: ^Fluid_Networks) -> int {
	return len(networks.topology.trees)
}

// Old saves (0356): litres held in pipes, which hold no fluid now, are
// dropped with the fluid, so a lone pipe shows no band before the first
// tick. Returns how many. A pipe holding none is left as saved, so a save
// since 0356 loads to its own hash.
drop_pipe_litres :: proc(entities: ^Entities) -> (litres: i64) {
	for &pipe in entities.pipes.entries {
		if pipe.alive && pipe.buffer.level > 0 {
			litres += i64(pipe.buffer.level)
			pipe.buffer = EMPTY_FLUID_BUFFER
		}
	}
	return
}

pipe_litres_line :: proc(litres: i64) -> string {
	return fmt.tprintf("save: dropped %d litres held in pipes, which hold no fluid since 0356", litres)
}
