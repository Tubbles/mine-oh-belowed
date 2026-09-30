package game

import "base:runtime"
import "core:slice"

// Fluid networks (doc/fluids.md): the connected sets of segments, where
// a segment is one pipe block or one port buffer of a machine. Networks
// are rebuilt from the entities whenever a pipe or a machine with ports is
// placed or removed; the litres live on the entities, so a rebuild keeps
// them.
//
// Per tick each network walks its connections outwards from its output
// ports (breadth first by source_distance, ties and networks without an
// output port in coordinate order). Along a connection that leads away
// from the output ports, the fuller segment (by fill fraction) pushes as
// much as the flow limit, its level and the room allow, so fluid crosses a
// whole run of connections in one tick whichever way the run points and
// a pump's rate reaches the far end of a run intact. Every other
// connection moves litres towards equal fill fractions, rounded down;
// between two segments of one capacity that is half the level difference.
// Rounding down keeps a litre from moving back and forth between two
// segments once a run is full.
//
// A liquid moves to a higher segment only while that segment is at or
// below the network's head line: the highest outlet height plus head of
// the running pumps whose output port is in the network (0139). Without a
// running pump a liquid moves only to the same height or lower. Gases
// ignore height. A network holds one fluid: the first that enters it, kept
// until it is empty. A port holding or only taking another fluid, or whose
// phase filter refuses the network's fluid, is closed and moves nothing;
// each time a port closes counts as a mixing refusal in the statistics.

Fluid_Segment :: struct {
	owner:        Entity_Handle,
	// -1 for a pipe, otherwise the port index on the machine.
	port:         int,
	height:       i32,
	capacity:     i32,
	direction:    Fluid_Port_Direction,
	filter:       Fluid_Id,
	phase_filter: Fluid_Phase_Filter,
	// The output port of a pump (offshore, tar pit or electric), the
	// height its head reaches, whether it runs only with power, and its
	// pump's input port, or -1 for a pump standing at its source.
	pressurising:    bool,
	head_line:       i32,
	needs_power:     bool,
	input_port:      int,
	network:         int,
	// Connections to the nearest output port of the network, or
	// UNREACHABLE_DISTANCE.
	source_distance: i32,
}

UNREACHABLE_DISTANCE :: max(i32)

// cell is the lower of the two cells along a positive face, which breaks
// ties in the connection order by coordinate.
Fluid_Connection :: struct {
	first:  int,
	second: int,
	cell:   World_Coordinate,
	face:   Direction,
}

// members and connections are ranges into Fluid_Networks.
Fluid_Network :: struct {
	fluid:            Fluid_Id,
	first_member:     int,
	member_count:     int,
	first_connection: int,
	connection_count: int,
}

Fluid_Networks :: struct {
	segments:    [dynamic]Fluid_Segment,
	// Segment indices grouped by network, in segment order.
	members:     [dynamic]int,
	// Grouped by network, each group outwards from the output ports
	// (connection_before).
	connections: [dynamic]Fluid_Connection,
	networks:    [dynamic]Fluid_Network,
	// Zero means context.allocator; tests use the temp allocator.
	allocator:   runtime.Allocator,
}

destroy_fluid_networks :: proc(networks: ^Fluid_Networks) {
	delete(networks.segments)
	delete(networks.members)
	delete(networks.connections)
	delete(networks.networks)
}

clear_fluid_networks :: proc(networks: ^Fluid_Networks) {
	if networks.segments.allocator.procedure == nil {
		allocator := networks.allocator.procedure != nil ? networks.allocator : context.allocator
		networks.segments.allocator, networks.members.allocator = allocator, allocator
		networks.connections.allocator, networks.networks.allocator = allocator, allocator
	}
	clear(&networks.segments)
	clear(&networks.members)
	clear(&networks.connections)
	clear(&networks.networks)
}

// Pipes in pool order, then every port of every fluid machine, then of
// every crafting machine with ports (a washer), then of every drill with a
// revival port, then of every launch pad, in pool and port order.
collect_fluid_segments :: proc(entities: ^Entities, machines: Machine_Registry) {
	segments := &entities.fluid_networks.segments
	for pipe in entities.pipes.entries {
		if pipe.alive {
			machine := machines.machines[pipe.machine]
			append(segments, Fluid_Segment{owner = pipe.handle, port = -1, height = pipe.origin.y, capacity = machine.buffer_litres, direction = .Both, filter = NO_FLUID})
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		if fluid_machine.alive {
			append_port_segments(segments, fluid_machine.common, machines.machines[fluid_machine.machine])
		}
	}
	for assembler in entities.assemblers.entries {
		if assembler.alive {
			append_port_segments(segments, assembler.common, machines.machines[assembler.machine])
		}
	}
	for drill in entities.drills.entries {
		if drill.alive {
			append_port_segments(segments, drill.common, machines.machines[drill.machine])
		}
	}
	for pad in entities.launch_pads.entries {
		if pad.alive {
			append_port_segments(segments, pad.common, machines.machines[pad.machine])
		}
	}
}

append_port_segments :: proc(segments: ^[dynamic]Fluid_Segment, common: Entity_Common, machine: Machine) {
	for port, index in fluid_ports_of(machine) {
		height := placed_port_height(common, machine, port)
		segment := Fluid_Segment {
			owner        = common.handle,
			port         = index,
			height       = height,
			capacity     = port.capacity,
			direction    = port.direction,
			filter       = port.filter,
			phase_filter = port.phase_filter,
			pressurising = machine_kind_is_pump(machine.kind) && port.direction == .Output,
			head_line    = height + machine.head_metres,
			needs_power  = machine.electric_power_watts > 0,
			input_port   = port_index_of_direction(machine, .Input),
		}
		append(segments, segment)
	}
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

// Where each pipe cell's segment and each fluid machine's first port
// segment are, in the temp allocator.
Fluid_Segment_Lookup :: struct {
	pipes:    map[World_Coordinate]int,
	machines: map[Entity_Handle]int,
}

make_fluid_segment_lookup :: proc(entities: ^Entities) -> Fluid_Segment_Lookup {
	lookup := Fluid_Segment_Lookup {
		pipes    = make(map[World_Coordinate]int, context.temp_allocator),
		machines = make(map[Entity_Handle]int, context.temp_allocator),
	}
	for segment, index in entities.fluid_networks.segments {
		if segment.port < 0 {
			lookup.pipes[entity_common(entities, segment.owner).origin] = index
		} else if segment.port == 0 {
			lookup.machines[segment.owner] = index
		}
	}
	return lookup
}

// The segment that connects through face of cell from outside, or -1: a
// pipe takes any face, a machine only a port facing that way.
segment_at_face :: proc(entities: ^Entities, machines: Machine_Registry, lookup: Fluid_Segment_Lookup, cell: World_Coordinate, face: Direction) -> int {
	if segment, found := lookup.pipes[cell]; found {
		return segment
	}
	handle := entity_at(entities, cell)
	first, found := lookup.machines[handle]
	if !found {
		return -1
	}
	common := entity_common(entities, handle)
	port := port_at_face(common^, machines.machines[common.machine], cell, face)
	return port < 0 ? -1 : first + port
}

is_positive_direction :: proc(direction: Direction) -> bool {
	return direction == .Positive_X || direction == .Positive_Y || direction == .Positive_Z
}

// The faces a segment connects through, in the temp allocator.
segment_faces :: proc(entities: ^Entities, machines: Machine_Registry, segment: Fluid_Segment) -> []Cell_Face {
	if segment.port < 0 {
		faces := make([]Cell_Face, len(Direction), context.temp_allocator)
		origin := entity_common(entities, segment.owner).origin
		for face, index in Direction {
			faces[index] = {origin, face}
		}
		return faces
	}
	common := entity_common(entities, segment.owner)
	machine := machines.machines[common.machine]
	return placed_port_faces(common^, machine, machine.fluid_ports[segment.port])
}

// Every connection once: only through positive faces, since the partner
// sees the same connection through a negative one.
find_fluid_connections :: proc(entities: ^Entities, machines: Machine_Registry) -> []Fluid_Connection {
	lookup := make_fluid_segment_lookup(entities)
	connections := make([dynamic]Fluid_Connection, context.temp_allocator)
	for segment, index in entities.fluid_networks.segments {
		for face in segment_faces(entities, machines, segment) {
			if !is_positive_direction(face.face) {
				continue
			}
			neighbour := face.cell + World_Coordinate(direction_offsets[face.face])
			partner := segment_at_face(entities, machines, lookup, neighbour, opposite_directions[face.face])
			if partner >= 0 && partner != index {
				append(&connections, Fluid_Connection{first = index, second = partner, cell = face.cell, face = face.face})
			}
		}
	}
	return connections[:]
}

union_find_root :: proc(parents: []int, index: int) -> int {
	root := index
	for parents[root] != root {
		root = parents[root]
	}
	return root
}

// Network ids in order of each network's first segment.
assign_fluid_networks :: proc(segments: []Fluid_Segment, connections: []Fluid_Connection) -> int {
	parents := make([]int, len(segments), context.temp_allocator)
	for &parent, index in parents {
		parent = index
	}
	for connection in connections {
		first, second := union_find_root(parents, connection.first), union_find_root(parents, connection.second)
		parents[max(first, second)] = min(first, second)
	}
	network_of_root := make([]int, len(segments), context.temp_allocator)
	count := 0
	for &segment, index in segments {
		root := union_find_root(parents, index)
		if root == index {
			network_of_root[index] = count
			count += 1
		}
		segment.network = network_of_root[root]
	}
	return count
}

coordinate_before :: proc(first, second: World_Coordinate) -> bool {
	if first.y != second.y {
		return first.y < second.y
	}
	if first.z != second.z {
		return first.z < second.z
	}
	return first.x < second.x
}

// The nearer end's distance from an output port: running connections in
// this order is a breadth first walk from the output ports.
connection_source_distance :: proc(segments: []Fluid_Segment, connection: Fluid_Connection) -> i32 {
	return min(segments[connection.first].source_distance, segments[connection.second].source_distance)
}

// By network, then outwards from the output ports, then by coordinate.
connection_before :: proc(segments: []Fluid_Segment, first, second: Fluid_Connection) -> bool {
	first_network, second_network := segments[first.first].network, segments[second.first].network
	if first_network != second_network {
		return first_network < second_network
	}
	first_distance, second_distance := connection_source_distance(segments, first), connection_source_distance(segments, second)
	if first_distance != second_distance {
		return first_distance < second_distance
	}
	if first.cell != second.cell {
		return coordinate_before(first.cell, second.cell)
	}
	return first.face < second.face
}

// Needs the source distances measured.
group_fluid_connections :: proc(networks: ^Fluid_Networks, connections: []Fluid_Connection) {
	Sort_Context :: struct {
		segments: []Fluid_Segment,
	}
	sort_context := Sort_Context{networks.segments[:]}
	slice.sort_by_with_data(connections, proc(first, second: Fluid_Connection, data: rawptr) -> bool {
		return connection_before((^Sort_Context)(data).segments, first, second)
	}, &sort_context)
	for connection in connections {
		network := &networks.networks[networks.segments[connection.first].network]
		if network.connection_count == 0 {
			network.first_connection = len(networks.connections)
		}
		network.connection_count += 1
		append(&networks.connections, connection)
	}
}

group_fluid_members :: proc(networks: ^Fluid_Networks) {
	counts := make([]int, len(networks.networks), context.temp_allocator)
	for segment in networks.segments {
		counts[segment.network] += 1
	}
	start := 0
	for &network, index in networks.networks {
		network.first_member = start
		start += counts[index]
	}
	resize(&networks.members, len(networks.segments))
	for segment, index in networks.segments {
		network := &networks.networks[segment.network]
		networks.members[network.first_member + network.member_count] = index
		network.member_count += 1
	}
}

segment_buffer :: proc(entities: ^Entities, segment: Fluid_Segment) -> ^Fluid_Buffer {
	if segment.port < 0 {
		return &pool_get(&entities.pipes, segment.owner).buffer
	}
	buffers, _ := entity_port_buffers(entities, segment.owner)
	return &buffers[segment.port]
}

// A rebuilt network takes the fluid of its first pipe holding any. Pipes
// holding another fluid, from a network it was joined to, lose it.
settle_rebuilt_network_fluid :: proc(entities: ^Entities, networks: ^Fluid_Networks, network: ^Fluid_Network) {
	network.fluid = NO_FLUID
	for member in networks.members[network.first_member:][:network.member_count] {
		segment := networks.segments[member]
		buffer := segment_buffer(entities, segment)
		if segment.port >= 0 || buffer.level == 0 {
			continue
		}
		if network.fluid == NO_FLUID {
			network.fluid = buffer.fluid
		} else if buffer.fluid != network.fluid {
			buffer^ = EMPTY_FLUID_BUFFER
		}
	}
}

// Breadth first from every output port over the connections.
measure_source_distances :: proc(segments: []Fluid_Segment, connections: []Fluid_Connection) {
	neighbours := make([][dynamic]int, len(segments), context.temp_allocator)
	for &list in neighbours {
		list = make([dynamic]int, context.temp_allocator)
	}
	for connection in connections {
		append(&neighbours[connection.first], connection.second)
		append(&neighbours[connection.second], connection.first)
	}
	queue := make([dynamic]int, context.temp_allocator)
	for &segment, index in segments {
		segment.source_distance = UNREACHABLE_DISTANCE
		if segment.direction == .Output {
			segment.source_distance = 0
			append(&queue, index)
		}
	}
	for head := 0; head < len(queue); head += 1 {
		current := queue[head]
		for neighbour in neighbours[current] {
			if segments[neighbour].source_distance == UNREACHABLE_DISTANCE {
				segments[neighbour].source_distance = segments[current].source_distance + 1
				append(&queue, neighbour)
			}
		}
	}
}

rebuild_fluid_networks :: proc(entities: ^Entities, machines: Machine_Registry) {
	networks := &entities.fluid_networks
	clear_fluid_networks(networks)
	collect_fluid_segments(entities, machines)
	connections := find_fluid_connections(entities, machines)
	count := assign_fluid_networks(networks.segments[:], connections)
	resize(&networks.networks, count)
	for &network in networks.networks {
		network = Fluid_Network{fluid = NO_FLUID}
	}
	group_fluid_members(networks)
	measure_source_distances(networks.segments[:], connections)
	group_fluid_connections(networks, connections)
	for &network in networks.networks {
		settle_rebuilt_network_fluid(entities, networks, &network)
	}
}

// Ticking.

segment_gives :: proc(segment: Fluid_Segment) -> bool {
	return segment.direction != .Input
}

segment_takes :: proc(segment: Fluid_Segment) -> bool {
	return segment.direction != .Output
}

// A port holding another fluid, or empty but only taking another fluid
// or refusing it by phase (or fuel value), would mix. Pipes always hold the network's fluid.
segment_is_closed :: proc(segment: Fluid_Segment, buffer: Fluid_Buffer, fluid: Fluid_Id, fluids: Fluid_Registry) -> bool {
	if segment.port < 0 {
		return false
	}
	if !phase_filter_admits(segment.phase_filter, fluids, fluid) {
		return true
	}
	if buffer.level > 0 {
		return buffer.fluid != fluid
	}
	return segment.filter != NO_FLUID && segment.filter != fluid
}

// The fluid of the first member that holds some and can give it.
first_giving_fluid :: proc(entities: ^Entities, networks: ^Fluid_Networks, members: []int) -> Fluid_Id {
	for member in members {
		segment := networks.segments[member]
		buffer := segment_buffer(entities, segment)
		if buffer.level > 0 && segment_gives(segment) {
			return buffer.fluid
		}
	}
	return NO_FLUID
}

// A pump outlet sets a head line while it can push: its port is open
// (not closed for mixing this tick), it has power or needs none, and its
// input side holds fluid. A pump at its source (offshore, tar pit) always
// does; the electric pump did when it moved fluid this tick (it may have
// drained its input to zero doing so) or while its input holds a litre.
// A pump against a full output keeps its head.
outlet_is_running :: proc(entities: ^Entities, segment: Fluid_Segment) -> bool {
	if !segment.pressurising {
		return false
	}
	pump := pool_get(&entities.fluid_machines, segment.owner)
	if pump.closed[segment.port] || segment.needs_power && !power_is_on(pump.power) {
		return false
	}
	return segment.input_port < 0 || pump.state == .Pumping || pump.buffers[segment.input_port].level > 0
}

// The highest head line of the network's running pump outlets.
network_head_line :: proc(entities: ^Entities, networks: ^Fluid_Networks, members: []int) -> (line: i32, found: bool) {
	for member in members {
		segment := networks.segments[member]
		if outlet_is_running(entities, segment) && (!found || segment.head_line > line) {
			line, found = segment.head_line, true
		}
	}
	return
}

// No running pump: a liquid never climbs. A gas climbs anywhere.
NO_HEAD_LINE :: min(i32)
HEIGHTS_IGNORED :: max(i32)

// The height a liquid may climb to in the network this tick.
tick_head_line :: proc(entities: ^Entities, networks: ^Fluid_Networks, members: []int, fluids: Fluid_Registry, fluid: Fluid_Id) -> i32 {
	if fluid_is_gas(fluids, fluid) {
		return HEIGHTS_IGNORED
	}
	line, found := network_head_line(entities, networks, members)
	return found ? line : NO_HEAD_LINE
}

// How much fuller `from` is than `to` by fill fraction, scaled by both
// capacities; positive when `from` is the fuller one.
fill_fraction_difference :: proc(from_level, from_capacity, to_level, to_capacity: i32) -> i64 {
	return i64(from_level) * i64(to_capacity) - i64(to_level) * i64(from_capacity)
}

// Litres that bring the two fill fractions together, rounded down,
// capped by the limit and by the room in `to`. Zero when `from` is not
// the fuller one.
fluid_transfer_amount :: proc(from_level, from_capacity, to_level, to_capacity, limit: i32) -> i32 {
	numerator := fill_fraction_difference(from_level, from_capacity, to_level, to_capacity)
	if numerator <= 0 {
		return 0
	}
	amount := numerator / (i64(from_capacity) + i64(to_capacity))
	return i32(min(amount, i64(limit), i64(to_capacity - to_level)))
}

// Away from the output ports: all `from` holds, capped by the limit and
// by the room in `to`. Zero when `from` is not the fuller one.
fluid_push_amount :: proc(from_level, from_capacity, to_level, to_capacity, limit: i32) -> i32 {
	if fill_fraction_difference(from_level, from_capacity, to_level, to_capacity) <= 0 {
		return 0
	}
	return min(from_level, limit, to_capacity - to_level)
}

// The fuller of the two by fill fraction first.
order_by_fullness :: proc(first, second: Fluid_Segment, first_buffer, second_buffer: Fluid_Buffer) -> (from, to: int) {
	if i64(second_buffer.level) * i64(first.capacity) > i64(first_buffer.level) * i64(second.capacity) {
		return 1, 0
	}
	return 0, 1
}

// head_line: a move into a higher segment needs that segment at or below
// it (tick_head_line).
Fluid_Tick_Rules :: struct {
	fluid:     Fluid_Id,
	head_line: i32,
	limit:     i32,
}

move_along_connection :: proc(entities: ^Entities, networks: ^Fluid_Networks, connection: Fluid_Connection, closed: []bool, rules: Fluid_Tick_Rules) {
	if closed[connection.first] || closed[connection.second] {
		return
	}
	pair := [2]Fluid_Segment{networks.segments[connection.first], networks.segments[connection.second]}
	buffers := [2]^Fluid_Buffer{segment_buffer(entities, pair[0]), segment_buffer(entities, pair[1])}
	from, to := order_by_fullness(pair[0], pair[1], buffers[0]^, buffers[1]^)
	if !segment_gives(pair[from]) || !segment_takes(pair[to]) {
		return
	}
	if pair[from].height < pair[to].height && pair[to].height > rules.head_line {
		return
	}
	amount: i32
	if pair[to].source_distance > pair[from].source_distance {
		amount = fluid_push_amount(buffers[from].level, pair[from].capacity, buffers[to].level, pair[to].capacity, rules.limit)
	} else {
		amount = fluid_transfer_amount(buffers[from].level, pair[from].capacity, buffers[to].level, pair[to].capacity, rules.limit)
	}
	if amount <= 0 {
		return
	}
	buffers[from].level -= amount
	buffers[from].flow_out += amount
	add_to_buffer(buffers[to], rules.fluid, amount)
	buffers[to].flow_in += amount
}

// Closes the ports that would mix, and tells their machines for the panel.
// Returns how many ports closed that were open in the previous tick.
mark_closed_ports :: proc(entities: ^Entities, networks: ^Fluid_Networks, members: []int, fluid: Fluid_Id, fluids: Fluid_Registry, closed: []bool) -> (refusals: u64) {
	for member in members {
		segment := networks.segments[member]
		closed[member] = fluid != NO_FLUID && segment_is_closed(segment, segment_buffer(entities, segment)^, fluid, fluids)
		if segment.port >= 0 {
			_, port_closed := entity_port_buffers(entities, segment.owner)
			refusals += closed[member] && !port_closed[segment.port] ? 1 : 0
			port_closed[segment.port] = closed[member]
		}
	}
	return refusals
}

network_litres :: proc(entities: ^Entities, networks: ^Fluid_Networks, members: []int, closed: []bool) -> i64 {
	total: i64
	for member in members {
		if !closed[member] {
			total += i64(segment_buffer(entities, networks.segments[member]).level)
		}
	}
	return total
}

// Returns the mixing refusals of the tick.
tick_fluid_network :: proc(entities: ^Entities, networks: ^Fluid_Networks, network: ^Fluid_Network, fluids: Fluid_Registry, limit: i32, closed: []bool) -> (refusals: u64) {
	members := networks.members[network.first_member:][:network.member_count]
	if network.fluid == NO_FLUID {
		network.fluid = first_giving_fluid(entities, networks, members)
	}
	refusals = mark_closed_ports(entities, networks, members, network.fluid, fluids, closed)
	if network.fluid == NO_FLUID {
		return
	}
	rules := Fluid_Tick_Rules {
		fluid     = network.fluid,
		head_line = tick_head_line(entities, networks, members, fluids, network.fluid),
		limit     = limit,
	}
	for connection in networks.connections[network.first_connection:][:network.connection_count] {
		move_along_connection(entities, networks, connection, closed, rules)
	}
	if network_litres(entities, networks, members, closed) == 0 {
		network.fluid = NO_FLUID
	}
	return
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

// A nil statistics (tests) records no mixing refusals.
tick_fluid_networks :: proc(entities: ^Entities, fluids: Fluid_Registry, limit: i32, statistics: ^Statistics = nil) {
	reset_fluid_flows(entities)
	networks := &entities.fluid_networks
	closed := make([]bool, len(networks.segments), context.temp_allocator)
	for &network in networks.networks {
		refusals := tick_fluid_network(entities, networks, &network, fluids, limit, closed)
		if statistics != nil {
			statistics.mixing_refusals += refusals
		}
	}
}

// The network a pipe or a machine port belongs to, or -1.
fluid_network_of :: proc(networks: ^Fluid_Networks, owner: Entity_Handle, port: int) -> int {
	for segment in networks.segments {
		if segment.owner == owner && segment.port == port {
			return segment.network
		}
	}
	return -1
}

// The segment of a pipe or a machine port, or -1.
find_fluid_segment :: proc(networks: ^Fluid_Networks, owner: Entity_Handle, port: int) -> int {
	for segment, index in networks.segments {
		if segment.owner == owner && segment.port == port {
			return index
		}
	}
	return -1
}

// Whether a pipe or port stands above the head line of its liquid
// network, so no pump lifts anything into it (the panels, 0139). False
// without a running pump and for a gas.
segment_is_above_head_line :: proc(entities: ^Entities, fluids: Fluid_Registry, owner: Entity_Handle, port: int) -> bool {
	networks := &entities.fluid_networks
	index := find_fluid_segment(networks, owner, port)
	if index < 0 {
		return false
	}
	segment := networks.segments[index]
	network := networks.networks[segment.network]
	if fluid_is_gas(fluids, network.fluid) {
		return false
	}
	line, found := network_head_line(entities, networks, networks.members[network.first_member:][:network.member_count])
	return found && segment.height > line
}
