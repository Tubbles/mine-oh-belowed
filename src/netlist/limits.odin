package netlist

// Each tree edge's limit after a solve (0369, doc/fluids.md, Power): whether
// its bundle has room for another level of what it feeds, and whether
// raising it, together with the other cables at capacity on the power's
// path, would give a consumer it feeds more. Four passes over the
// pre-order, integers only, read from the solve's outputs and kept nowhere.

// Per node, the edge to its parent after a solve (0369).
Edge_Limit :: struct {
	at_capacity, limits: bool,
	shortfall:           i64,
}

// What an edge feeds, seen from one of its ends going away from it: the
// nodes joined at equal levels and, through edges at capacity that carry
// the power on, the nodes beyond them (consumers_beyond counts those).
Fed_Reach :: struct {
	demand, consumers, consumers_beyond, short: i64,
}

// Per node, measure_edge_limits' sums: its equal level region's demand,
// the fed reach of its subtree and of the rest beyond its parent, the spare
// and the donors that reach it from either side, and the spare that reaches
// it through the edges' rooms alone, none passing an edge at capacity whole.
Limit_Reach :: struct {
	region_demand:                                        i64,
	fed_below, fed_above:                                 Fed_Reach,
	spare_below, spare_above, donors_below, donors_above: i64,
	room_spare_below, room_spare_above:                   i64,
}

// Writes every non root node's Edge_Limit for the edge to its parent;
// reach is the scratch of the passes, both arrays a node each. The fed
// reaches come first, since whether an edge is at capacity decides what
// passes it in the spare's passes.
measure_edge_limits :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, reach: []Limit_Reach, limits: []Edge_Limit) {
	for &record in reach { record = {} }
	for &record in limits { record = {} }
	sum_fed_reach_below(topology, inputs, outputs, reach)
	for node in topology.order {
		if topology.parent[node] == NO_NODE { continue }
		spread_fed_reach_above(topology, outputs, reach, node)
		limits[node].at_capacity = edge_at_capacity(topology, outputs, reach, node)
	}
	sum_limit_reach_below(topology, inputs, outputs, reach, limits)
	for node in topology.order {
		if topology.parent[node] == NO_NODE { continue }
		spread_limit_reach_above(topology, outputs, reach, limits, node)
		limits[node] = edge_limit(topology, outputs, reach, limits, node)
	}
}

// In reverse pre-order: each node's own demand, consumer and short, then
// into its parent its region's demand across equal levels and the part of
// its fed reach the parent reaches through the edge.
sum_fed_reach_below :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, reach: []Limit_Reach) {
	#reverse for node in topology.order {
		own := &reach[node]
		input := inputs[node]
		own.region_demand += input.demand
		own.fed_below.demand += input.demand
		own.fed_below.consumers += input.demand > 0 ? 1 : 0
		own.fed_below.short += input.demand - outputs[node].delivered
		parent := topology.parent[node]
		if parent == NO_NODE { continue }
		if outputs[node].level == outputs[parent].level {
			reach[parent].region_demand += own.region_demand
		}
		reach[parent].fed_below = add_fed_reach(reach[parent].fed_below, fed_reach_into_child(topology, outputs, node, own.fed_below))
	}
}

// The node's region demand from its parent when their levels are equal,
// and the fed reach of the rest of its tree through the edge to its parent;
// called in pre-order, so the parent is already done.
spread_fed_reach_above :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, node: u32) {
	parent := topology.parent[node]
	if outputs[node].level == outputs[parent].level {
		reach[node].region_demand = reach[parent].region_demand
	}
	reach[node].fed_above = fed_reach_into_parent(topology, outputs, node, fed_reach_beyond_parent(topology, outputs, reach, node))
}

// From the parent's end, going away from the node's edge: the parent's
// subtree less the node's part, and the rest beyond the parent's own edge.
fed_reach_beyond_parent :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, node: u32) -> Fed_Reach {
	above := reach[topology.parent[node]]
	rest := subtract_fed_reach(above.fed_below, fed_reach_into_child(topology, outputs, node, reach[node].fed_below))
	return add_fed_reach(rest, above.fed_above)
}

// What of a child's subtree reach its parent reaches through the child's
// edge: all of it at equal levels, all of it as beyond when the edge
// carries power into the child at capacity, else nothing.
fed_reach_into_child :: proc(topology: Topology, outputs: []Node_Output, child: u32, below: Fed_Reach) -> Fed_Reach {
	if outputs[child].level == outputs[topology.parent[child]].level { return below }
	if outputs[child].flow < 0 && room_towards_child(topology, outputs, child) < region_level_cost(below.demand, below.consumers) {
		return fed_reach_as_beyond(below)
	}
	return {}
}

// The same for the reach beyond a parent, through the child's edge upwards.
fed_reach_into_parent :: proc(topology: Topology, outputs: []Node_Output, child: u32, rest: Fed_Reach) -> Fed_Reach {
	if outputs[child].level == outputs[topology.parent[child]].level { return rest }
	if outputs[child].flow > 0 && room_towards_parent(topology, outputs, child) < region_level_cost(rest.demand, rest.consumers) {
		return fed_reach_as_beyond(rest)
	}
	return {}
}

// What the node's edge feeds: its subtree when the flow enters the node,
// else what lies beyond its parent.
edge_fed_reach :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, node: u32) -> Fed_Reach {
	if outputs[node].flow < 0 { return reach[node].fed_below }
	return fed_reach_beyond_parent(topology, outputs, reach, node)
}

// The edge's room in its flow's direction is under a level of what it
// feeds; never without flow.
edge_at_capacity :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, node: u32) -> bool {
	flow := outputs[node].flow
	if flow == 0 { return false }
	fed := edge_fed_reach(topology, outputs, reach, node)
	room := flow < 0 ? room_towards_child(topology, outputs, node) : room_towards_parent(topology, outputs, node)
	return room < region_level_cost(fed.demand, fed.consumers)
}

// In reverse pre-order: each node's own spare and delivery, then into its
// parent what passes the edge towards the parent (the donors only between
// equal levels).
sum_limit_reach_below :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, reach: []Limit_Reach, limits: []Edge_Limit) {
	#reverse for node in topology.order {
		own := &reach[node]
		output := outputs[node]
		own.spare_below += inputs[node].offer - output.supplied + output.charged
		own.room_spare_below += inputs[node].offer - output.supplied + output.charged
		own.donors_below += output.delivered
		parent := topology.parent[node]
		if parent == NO_NODE { continue }
		spare, donors := passed_towards_parent(topology, outputs, limits, node, own.spare_below, own.donors_below)
		reach[parent].spare_below += spare
		reach[parent].room_spare_below += min(max(0, room_towards_parent(topology, outputs, node)), own.room_spare_below)
		if output.level == outputs[parent].level {
			reach[parent].donors_below += donors
		}
	}
}

// The spare and the donors of the rest of the node's tree that reach it
// through its edge; called in pre-order, so the parent is already done.
spread_limit_reach_above :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, limits: []Edge_Limit, node: u32) {
	parent := topology.parent[node]
	own, above := &reach[node], reach[parent]
	spare, donors := passed_towards_parent(topology, outputs, limits, node, own.spare_below, own.donors_below)
	own.spare_above = above.spare_below - spare
	own.room_spare_above = above.room_spare_below - min(max(0, room_towards_parent(topology, outputs, node)), own.room_spare_below)
	own.donors_above = above.donors_below - (outputs[node].level == outputs[parent].level ? donors : 0)
	grandparent := topology.parent[parent]
	if grandparent == NO_NODE { return }
	spare_down, donors_down := passed_towards_child(topology, outputs, limits, parent, above.spare_above, above.donors_above)
	own.spare_above += spare_down
	own.room_spare_above += min(max(0, room_towards_child(topology, outputs, parent)), above.room_spare_above)
	if outputs[parent].level == outputs[grandparent].level {
		own.donors_above += donors_down
	}
}

// What passes the child's edge towards its parent: all of it when the edge
// carries power that way at capacity, else one room shared, the spare
// first and the donors what is left.
passed_towards_parent :: proc(topology: Topology, outputs: []Node_Output, limits: []Edge_Limit, child: u32, spare, donors: i64) -> (spare_passed, donors_passed: i64) {
	if outputs[child].flow > 0 && limits[child].at_capacity { return spare, donors }
	return share_room(room_towards_parent(topology, outputs, child), spare, donors)
}

passed_towards_child :: proc(topology: Topology, outputs: []Node_Output, limits: []Edge_Limit, child: u32, spare, donors: i64) -> (spare_passed, donors_passed: i64) {
	if outputs[child].flow < 0 && limits[child].at_capacity { return spare, donors }
	return share_room(room_towards_child(topology, outputs, child), spare, donors)
}

share_room :: proc(room, spare, donors: i64) -> (spare_passed, donors_passed: i64) {
	usable := max(0, room)
	spare_passed = min(usable, spare)
	return spare_passed, min(usable - spare_passed, donors)
}

// The rule of doc/fluids.md, Power: at capacity while the room is under a
// level of what the edge feeds; limiting while that is below the feeding
// end and its short, less the spare reaching the fed end through rooms
// from its own side, and the spare and the share given up on the feeding
// side all cover that level.
edge_limit :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, limits: []Edge_Limit, node: u32) -> Edge_Limit {
	flow := outputs[node].flow
	if flow == 0 { return {} }
	parent := topology.parent[node]
	fed, feeding := parent, node
	spare, other_spare, donors := reach[node].spare_below, reach[node].room_spare_above, reach[node].donors_below
	if flow < 0 {
		fed, feeding = node, parent
		spare, other_spare, donors = reach[node].spare_above, reach[node].room_spare_below, reach[node].donors_above
	}
	reached := edge_fed_reach(topology, outputs, reach, node)
	cost := region_level_cost(reached.demand, reached.consumers)
	fed_level, feeding_level := outputs[fed].level, outputs[feeding].level
	ceded := ceded_joules(reach[fed].region_demand, reach[feeding].region_demand, fed_level, feeding_level, donors)
	at_capacity := limits[node].at_capacity
	lower := fed_level < feeding_level || reached.consumers_beyond > 0
	limiting := at_capacity && lower && min(reached.short - other_spare, spare + ceded) >= cost
	return {at_capacity = at_capacity, limits = limiting, shortfall = reached.short}
}

room_towards_parent :: proc(topology: Topology, outputs: []Node_Output, node: u32) -> i64 {
	return topology.capacity[node] - outputs[node].flow
}

room_towards_child :: proc(topology: Topology, outputs: []Node_Output, node: u32) -> i64 {
	return topology.capacity[node] + outputs[node].flow
}

// A level of a region and a joule per consumer: what the solve may leave
// unspent under a cable that bounds the region (0373).
region_level_cost :: proc(demand, consumers: i64) -> i64 {
	return max(1, (demand + LEVEL_FULL - 1) / LEVEL_FULL) + consumers
}

// What the feeding region would give up for the two to meet at a common
// level, at most the donors' delivery that reaches the cable.
ceded_joules :: proc(fed_demand, feeding_demand: i64, fed_level, feeding_level: u32, donors: i64) -> i64 {
	if feeding_level <= fed_level || fed_demand <= 0 || feeding_demand <= 0 { return 0 }
	gap := i128(feeding_level - fed_level)
	share := i128(fed_demand) * i128(feeding_demand) * gap / (LEVEL_FULL * i128(fed_demand + feeding_demand))
	return i64(min(i128(donors), share))
}

add_fed_reach :: proc(first, second: Fed_Reach) -> Fed_Reach {
	return {first.demand + second.demand, first.consumers + second.consumers, first.consumers_beyond + second.consumers_beyond, first.short + second.short}
}

subtract_fed_reach :: proc(first, second: Fed_Reach) -> Fed_Reach {
	return {first.demand - second.demand, first.consumers - second.consumers, first.consumers_beyond - second.consumers_beyond, first.short - second.short}
}

fed_reach_as_beyond :: proc(reached: Fed_Reach) -> Fed_Reach {
	return {reached.demand, reached.consumers, reached.consumers, reached.short}
}
