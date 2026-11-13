package netlist

// The balance of a netlist (0355, doc/fluids.md, Power), per tree and in
// integers: joules a tick in i64, levels in per mille, products in i128,
// every loop in node or pre-order.
//
// Phase 1 serves the consumers. Fast path: every consumer gets the pooled
// level of the tree's offers and demands and the offers share what was
// delivered by dispatch order; when the slow path would give the same
// levels (pooled_level_holds) and every edge's flow is within its
// capacity, that is the answer. Otherwise each consumer gets a max-min fair
// level, a saturated edge splitting its tree into regions: the side short
// of power gets the lower level and the side with spare power keeps its
// higher one (region_levels), and where an edge blocks the dispatch the
// generation moves inside the limit, every order at its offers or its
// edges' limits before a later one gives (repair_dispatch, 0389). A
// region fed across a saturated edge charges the region feeding it only
// the whole joules it takes (0373). Every spare joule, a region's slack at
// its level or the room a fed region leaves on its edge, goes a level at a
// time to the poorest region that can reach it (the pool: fed_fill,
// settle_levels). Each fed region's run is recorded once, uncapped, and
// replayed up to its parent's level by every walk that meets it (0390).
//
// Phase 2 charges the stores that supplied nothing from what phase 1 left
// of the other offers and of every edge, by the same solve.
//
// With top_up (the fluids', 0356, top_up.odin) each phase then hands out
// what the per mille levels left undelivered, within the phase's bounds,
// one dispatch order at a time. Power never sets it.

import "base:runtime"
import "core:math"
import "core:slice"

// Joules this tick: what a consumer asks, what an offer gives at its
// dispatch order, what a store can take. A store's offer is its discharge.
Node_Input :: struct {
	demand, offer, charge_room: i64,
	order:                      u8,
	store:                      bool,
}

// The consumer's level; joules delivered to it, taken from its offer, put
// into the store; the flow on the edge to the parent, positive towards
// it (0 at a root).
Node_Output :: struct {
	level:                              u32,
	delivered, supplied, charged, flow: i64,
}

// One phase of one tree, every slice by position in the tree's pre-order,
// the root at 0. lower and upper bound the flow on the edge to the
// parent; delivered is what the phase's consumers receive.
Phase :: struct {
	nodes:     []u32,
	parent:    []i32,
	demand:    []i64,
	offer:     []i64,
	order:     []u8,
	lower:     []i64,
	upper:     []i64,
	level:     []u32,
	delivered: []i64,
	supplied:  []i64,
	flow:      []i64,
}

// R(level) = a - b * level while table is nil (region_levels).
Response :: struct {
	a, b:  i64,
	table: []i64,
}

// The largest levels from 0 to LEVEL_FULL at which a subtree's response
// reaches the edge's upper bound and its lower one; -1 for none.
Level_Thresholds :: struct {
	rich_level, poor_level: i32,
}

// A child against its parent region's level: in the region, feeding it
// across its saturated edge (a candidate of the pool), or fed by it.
Child_State :: enum u8 {
	Joined,
	Feeder,
	Fed,
}

// The slow path's scratch by position, in whole joules: net what a region
// node's part sends up its edge (a fed region's top: minus its take),
// passed what draws sent down that edge, source a domain root's or a fed
// top's spare not yet drawn, export what a feeder sends up its edge; ends
// one past each position's subtree in pre-order; domain and candidates
// the lists of the last walk_domain. steps holds every fed region's
// uncapped run as fed_fill recorded it, back to back, a position's at
// steps[record_first[position]:record_end[position]]. reach is a
// position's value in the current pass of a greedy, valid while
// reach_pass equals pass, and path the scratch of reachable.
Pools :: struct {
	state:                       []Child_State,
	level:                       []u32,
	export, net, passed, source: []i64,
	reach, reach_pass:           []i64,
	ends:                        []i32,
	record_first, record_end:    []i32,
	done:                        []bool,
	domain, candidates, path:    [dynamic]i32,
	steps:                       [dynamic]Greedy_Step,
	pass:                        i64,
}

// One step of a fed region's uncapped run: the candidate, the level it
// then sits at and the joules it cost.
Greedy_Step :: struct {
	candidate: i32,
	level:     u32,
	need:      i64,
}

// Per position and class, flat at position * class_count + class: what
// the dispatch gave of the class in the position's subtree, the least of
// it the subtree gives with its edge at its floor (forced, the floor met
// by the cheapest classes), and what more of it the subtree can give
// under its edge's ceiling (length, the ceiling cut from the dearest);
// class_of an order's class, -1 for an order nobody offers at (0389).
Class_Ranges :: struct {
	class_of:                   [256]i32,
	class_count:                int,
	dispatched, forced, length: []i64,
}

// The positions the pool visited on this thread and the replays a cap cut
// short, for the tests (0390). Declared in every build, since odin check
// reads the tests without ODIN_TEST, and counted only under odin test.
@(thread_local)
pool_visits: int
@(thread_local)
pool_partial_replays: int

count_pool_visits :: proc(count: int) {
	when ODIN_TEST {
		pool_visits += count
	}
}

Node_Position :: struct {
	node:     u32,
	position: i32,
}

// Called once a tick by the game.
solve :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, top_up := false) {
	for tree in 0 ..< len(topology.trees) {
		solve_tree(topology, tree, inputs, outputs, top_up = top_up)
	}
}

// Writes the outputs of the tree's nodes. fast_path false skips the fast
// path (tests). took_fast_path: every phase it ran ended on the fast path.
solve_tree :: proc(topology: Topology, tree: int, inputs: []Node_Input, outputs: []Node_Output, fast_path := true, top_up := false) -> (took_fast_path: bool) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	range := topology.trees[tree]
	phase := make_phase(topology, topology.order[range.first:][:range.count])
	by_node := positions_by_node(phase.nodes)
	set_supply_phase(&phase, topology, inputs)
	took_fast_path = solve_phase(&phase, by_node, fast_path, top_up)
	for node, position in phase.nodes {
		outputs[node] = Node_Output {
			level     = phase.level[position],
			delivered = phase.delivered[position],
			supplied  = phase.supplied[position],
			flow      = phase.flow[position],
		}
	}
	if !set_charge_phase(&phase, topology, inputs, outputs) {
		return
	}
	took_fast_path = solve_phase(&phase, by_node, fast_path, top_up) && took_fast_path
	for node, position in phase.nodes {
		outputs[node].charged = phase.delivered[position]
		outputs[node].supplied += phase.supplied[position]
		outputs[node].flow += phase.flow[position]
	}
	return
}

// The scratch of a phase in the temp allocator, each node's parent found
// as the nearest of its ancestors on the pre-order's path.
make_phase :: proc(topology: Topology, nodes: []u32) -> Phase {
	count := len(nodes)
	phase := Phase {
		nodes     = nodes,
		parent    = make([]i32, count, context.temp_allocator),
		demand    = make([]i64, count, context.temp_allocator),
		offer     = make([]i64, count, context.temp_allocator),
		order     = make([]u8, count, context.temp_allocator),
		lower     = make([]i64, count, context.temp_allocator),
		upper     = make([]i64, count, context.temp_allocator),
		level     = make([]u32, count, context.temp_allocator),
		delivered = make([]i64, count, context.temp_allocator),
		supplied  = make([]i64, count, context.temp_allocator),
		flow      = make([]i64, count, context.temp_allocator),
	}
	path := make([dynamic]i32, 0, 16, context.temp_allocator)
	for node, position in nodes {
		for len(path) > 0 && nodes[path[len(path) - 1]] != topology.parent[node] {
			pop(&path)
		}
		phase.parent[position] = len(path) > 0 ? path[len(path) - 1] : -1
		append(&path, i32(position))
	}
	return phase
}

// The positions in node order, the order leftover joules go in.
positions_by_node :: proc(nodes: []u32) -> []i32 {
	pairs := make([]Node_Position, len(nodes), context.temp_allocator)
	for node, position in nodes {
		pairs[position] = {node, i32(position)}
	}
	slice.sort_by(pairs, proc(first, second: Node_Position) -> bool {return first.node < second.node})
	positions := make([]i32, len(nodes), context.temp_allocator)
	for pair, index in pairs {
		positions[index] = pair.position
	}
	return positions
}

// Phase 1: the demands, the offers, each edge within its capacity.
set_supply_phase :: proc(phase: ^Phase, topology: Topology, inputs: []Node_Input) {
	for node, position in phase.nodes {
		input := inputs[node]
		phase.demand[position], phase.offer[position], phase.order[position] = input.demand, input.offer, input.order
		phase.lower[position], phase.upper[position] = -topology.capacity[node], topology.capacity[node]
	}
}

// Phase 2: the charge room of each store that supplied nothing, what
// phase 1 left of each offer that is no store's, and what phase 1's flow
// left of each edge. False when nothing would charge.
set_charge_phase :: proc(phase: ^Phase, topology: Topology, inputs: []Node_Input, outputs: []Node_Output) -> bool {
	demand_total, offer_total: i64
	for node, position in phase.nodes {
		input, output := inputs[node], outputs[node]
		phase.demand[position] = input.store && output.supplied == 0 ? input.charge_room : 0
		phase.offer[position] = input.store ? 0 : input.offer - output.supplied
		capacity := topology.capacity[node]
		phase.lower[position], phase.upper[position] = -capacity - output.flow, capacity - output.flow
		demand_total += phase.demand[position]
		offer_total += phase.offer[position]
	}
	return demand_total > 0 && offer_total > 0
}

solve_phase :: proc(phase: ^Phase, by_node: []i32, fast_path, top_up: bool) -> (took_fast_path: bool) {
	offering := offering_positions(phase^, by_node)
	if fast_path {
		uniform_levels(phase)
		if pooled_level_holds(phase^) {
			dispatch_by_order(phase, offering)
			tree_flows(phase)
			if flows_within_bounds(phase^) {
				if top_up {
					top_up_phase(phase)
					tree_flows(phase)
				}
				return true
			}
		}
	}
	region_levels(phase)
	bound_flows_by_levels(phase)
	dispatch_by_order(phase, offering)
	tree_flows(phase)
	if !flows_within_bounds(phase^) {
		repair_dispatch(phase)
		tree_flows(phase)
	}
	if top_up {
		top_up_phase(phase)
		tree_flows(phase)
	}
	return false
}

offering_positions :: proc(phase: Phase, by_node: []i32) -> []i32 {
	offering := make([dynamic]i32, 0, len(by_node), context.temp_allocator)
	for position in by_node {
		if phase.offer[position] > 0 {
			append(&offering, position)
		}
	}
	return offering[:]
}

delivered_at :: proc(demand: i64, level: u32) -> i64 {
	return i64(i128(demand) * i128(level) / LEVEL_FULL)
}

// The fast path's level: the pooled level of the tree's sums everywhere.
uniform_levels :: proc(phase: ^Phase) {
	supply, demand: i64
	for position in 0 ..< len(phase.nodes) {
		supply += phase.offer[position]
		demand += phase.demand[position]
	}
	level := pooled_level(supply, demand)
	for position in 0 ..< len(phase.nodes) {
		phase.level[position] = level
		phase.delivered[position] = delivered_at(phase.demand[position], level)
	}
}

// Whether region_levels would give every node the pooled level, from the
// responses at 0, at the pooled level and one above it (made
// non-increasing): the root's level is the pooled one and no child
// saturates its edge there, poorer or richer. A child poor one level
// above is charged there the whole joules its subtree then takes (whole,
// the whole joule net at the pooled level), as the slow path charges it.
// Rounding can keep the dispatch's flows inside an edge whose subtree, at
// its full offer, would exceed it, and a child reaching its edge outwards
// below full is a candidate the pool may raise: the slow path then
// answers, so the fast path never gives what the slow path would not.
pooled_level_holds :: proc(phase: Phase) -> bool {
	count := len(phase.nodes)
	level := i64(phase.level[0])
	levels := [3]i64{0, level, min(level + 1, LEVEL_FULL)}
	responses := make([][3]i64, count, context.temp_allocator)
	whole := make([]i64, count, context.temp_allocator)
	for position := count - 1; position >= 0; position -= 1 {
		for &value, index in responses[position] {
			value += LEVEL_FULL * phase.offer[position] - phase.demand[position] * levels[index]
		}
		whole[position] += LEVEL_FULL * (phase.offer[position] - delivered_at(phase.demand[position], u32(level)))
		responses[position][2] = min(responses[position][1], responses[position][2])
		if position == 0 {
			break
		}
		low, high := LEVEL_FULL * phase.lower[position], LEVEL_FULL * phase.upper[position]
		response := responses[position]
		if !child_keeps_level(response, low, high, level) {
			return false
		}
		parent := phase.parent[position]
		responses[parent][0] += clamp(response[0], low, high)
		responses[parent][1] += clamp(response[1], low, high)
		responses[parent][2] += response[2] < low ? min(whole[position], 0) : clamp(response[2], low, high)
		whole[parent] += clamp(whole[position], low, high)
	}
	root := responses[0]
	if root[0] == 0 {
		return level == 0
	}
	return root[1] >= 0 && (level == LEVEL_FULL || root[2] < 0)
}

// At its parent's level (response[1]) the child is not poorer and, below
// full, does not reach its edge outwards.
child_keeps_level :: proc(response: [3]i64, low, high, level: i64) -> bool {
	return response[1] >= low && (response[1] < high || level == LEVEL_FULL)
}

// The tree's total delivered shared over the offers by order ascending,
// each order up to its offers: in proportion, rounded down, the rest a
// joule at a time in node order.
dispatch_by_order :: proc(phase: ^Phase, offering: []i32) {
	remaining: i64
	for delivered in phase.delivered {
		remaining += delivered
	}
	slice.zero(phase.supplied)
	highest := 0
	for position in offering {
		highest = max(highest, int(phase.order[position]))
	}
	for order in 0 ..= highest {
		remaining -= dispatch_order(phase, offering, u8(order), remaining)
	}
}

// One order's share of what is left; returns what it took.
dispatch_order :: proc(phase: ^Phase, offering: []i32, order: u8, remaining: i64) -> i64 {
	order_supply: i64
	for position in offering {
		if phase.order[position] == order {
			order_supply += phase.offer[position]
		}
	}
	if order_supply == 0 {
		return 0
	}
	share := min(order_supply, remaining)
	assigned: i64
	for position in offering {
		if phase.order[position] == order {
			phase.supplied[position] = i64(i128(phase.offer[position]) * i128(share) / i128(order_supply))
			assigned += phase.supplied[position]
		}
	}
	for position in offering {
		if phase.order[position] == order {
			extra := min(share - assigned, phase.offer[position] - phase.supplied[position])
			phase.supplied[position] += extra
			assigned += extra
		}
	}
	return share
}

// In reverse pre-order: a node's flow is what it supplied minus what it
// received plus its children's flows.
tree_flows :: proc(phase: ^Phase) {
	for position in 0 ..< len(phase.nodes) {
		phase.flow[position] = phase.supplied[position] - phase.delivered[position]
	}
	for position := len(phase.nodes) - 1; position > 0; position -= 1 {
		phase.flow[phase.parent[position]] += phase.flow[position]
	}
}

flows_within_bounds :: proc(phase: Phase) -> bool {
	for position in 1 ..< len(phase.nodes) {
		if phase.flow[position] < phase.lower[position] || phase.flow[position] > phase.upper[position] {
			return false
		}
	}
	return true
}

response_at :: proc(response: Response, level: int) -> i64 {
	if response.table != nil {
		return response.table[level]
	}
	return response.a - response.b * i64(level)
}

// The largest level from 0 to LEVEL_FULL whose response is at least
// value, -1 for none; a response never rises with the level.
largest_level_at_least :: proc(response: Response, value: i64) -> i32 {
	if response_at(response, 0) < value {
		return -1
	}
	if response.table == nil {
		return response.b == 0 ? LEVEL_FULL : i32(min((response.a - value) / response.b, LEVEL_FULL))
	}
	low, high := 0, LEVEL_FULL
	for low < high {
		middle := (low + high + 1) / 2
		if response.table[middle] >= value {
			low = middle
		} else {
			high = middle - 1
		}
	}
	return i32(low)
}

take_table :: proc(spare_tables: ^[dynamic][]i64) -> []i64 {
	if len(spare_tables) > 0 {
		return pop(spare_tables)
	}
	return make([]i64, RESPONSE_LEVELS, context.temp_allocator)
}

// Adds a child's response to its parent's: up to its poor level clamped to
// its edge's bounds, above it the whole joules the child then takes, what
// its room spends raising its domain's candidates to one level under the
// parent's (fill, nil for none) beyond its own net. The sum stays a line
// while every child is a line whose clamp does not bite on 0 to LEVEL_FULL
// (poor_level is then LEVEL_FULL), else it becomes a table of every level.
add_child_response :: proc(target: ^Response, child: Response, low, high: i64, poor_level: i32, own_net: i64, fill: []i64, spare_tables: ^[dynamic][]i64) {
	clamp_bites := response_at(child, 0) > high || response_at(child, LEVEL_FULL) < low
	if target.table == nil && child.table == nil && !clamp_bites {
		target.a += child.a
		target.b += child.b
		return
	}
	if target.table == nil {
		target.table = take_table(spare_tables)
		for &value, level in target.table {
			value = target.a - target.b * i64(level)
		}
	}
	for &value, level in target.table {
		if level <= int(poor_level) {
			value += clamp(response_at(child, level), low, high)
			continue
		}
		drawn := fill != nil ? fill[level - 1] : 0
		value -= LEVEL_FULL * max(drawn - own_net, 0)
	}
}

// Each entry from level 1 up becomes the least of itself and the one
// below. A whole joule take can lie above the exact need at a poor level,
// so a parent's table can rise there: a region stops at the first level
// it cannot afford (progressive filling).
make_non_increasing :: proc(table: []i64) {
	for level in 1 ..< len(table) {
		table[level] = min(table[level], table[level - 1])
	}
}

// A child against its parent region's level: a feeder up to its rich
// level, fed above its poor level, else joined.
child_state :: proc(thresholds: Level_Thresholds, region_level: u32) -> Child_State {
	switch {
	case i32(region_level) <= thresholds.rich_level:
		return .Feeder
	case i32(region_level) > thresholds.poor_level:
		return .Fed
	}
	return .Joined
}

// The pools of a phase in the temp allocator, ends from the subtree sizes.
make_pools :: proc(phase: Phase) -> Pools {
	count := len(phase.nodes)
	pools := Pools {
		state        = make([]Child_State, count, context.temp_allocator),
		level        = make([]u32, count, context.temp_allocator),
		export       = make([]i64, count, context.temp_allocator),
		net          = make([]i64, count, context.temp_allocator),
		passed       = make([]i64, count, context.temp_allocator),
		source       = make([]i64, count, context.temp_allocator),
		reach        = make([]i64, count, context.temp_allocator),
		reach_pass   = make([]i64, count, context.temp_allocator),
		ends         = make([]i32, count, context.temp_allocator),
		record_first = make([]i32, count, context.temp_allocator),
		record_end   = make([]i32, count, context.temp_allocator),
		done         = make([]bool, count, context.temp_allocator),
		domain       = make([dynamic]i32, 0, count, context.temp_allocator),
		candidates   = make([dynamic]i32, 0, count, context.temp_allocator),
		path         = make([dynamic]i32, 0, count, context.temp_allocator),
		steps        = make([dynamic]Greedy_Step, 0, count, context.temp_allocator),
	}
	for position := count - 1; position >= 0; position -= 1 {
		pools.ends[position] += 1
		if position > 0 {
			pools.ends[phase.parent[position]] += pools.ends[position]
		}
	}
	for &end, position in pools.ends {
		end += i32(position)
	}
	return pools
}

// The domain of top at level: top's region and the regions fed from it,
// recursively, each node's state and level from its parent's. The feeders
// met are its candidates, each at its rich level with its edge's capacity
// as its export, their subtrees skipped. Both lists come out in pre-order.
walk_domain :: proc(phase: Phase, thresholds: []Level_Thresholds, pools: ^Pools, top: i32, level: u32) {
	clear(&pools.domain)
	clear(&pools.candidates)
	pools.level[top] = level
	append(&pools.domain, top)
	for position := top + 1; position < pools.ends[top]; {
		parent_level := pools.level[phase.parent[position]]
		state := child_state(thresholds[position], parent_level)
		pools.state[position] = state
		pools.source[position] = 0
		if state == .Feeder {
			pools.level[position] = u32(thresholds[position].rich_level)
			pools.export[position] = phase.upper[position]
			append(&pools.candidates, position)
			position = pools.ends[position]
			continue
		}
		pools.level[position] = state == .Joined ? parent_level : u32(max(thresholds[position].poor_level, 0))
		pools.passed[position] = 0
		append(&pools.domain, position)
		position += 1
	}
	count_pool_visits(len(pools.domain) + len(pools.candidates))
}

// The nets of the last walk's domain, bottom-up: each node's offer less
// its delivery, its candidates' exports, its joined children's nets up to
// their edges' capacities. A fed region first spends its room (its net
// plus its capacity) on its candidates below its parent's level, takes
// what that spent beyond its net, and keeps the surplus its parent cannot
// take as a source. Inner fed regions settle first.
settle_domain :: proc(phase: Phase, pools: ^Pools) {
	for position in pools.domain {
		pools.net[position] = 0
	}
	count_pool_visits(len(pools.domain))
	for candidate in pools.candidates {
		pools.net[phase.parent[candidate]] += pools.export[candidate]
	}
	for index := len(pools.domain) - 1; index >= 0; index -= 1 {
		position := pools.domain[index]
		pools.net[position] += phase.offer[position] - delivered_at(phase.demand[position], pools.level[position])
		if index == 0 {
			continue
		}
		parent := phase.parent[position]
		if pools.state[position] != .Fed {
			pools.net[parent] += min(pools.net[position], phase.upper[position])
			continue
		}
		own := pools.net[position]
		room := own - phase.lower[position]
		pools.source[position] = room
		// A fed region replays its recorded run up to one level under its
		// parent's.
		replay_steps(phase, pools, position, i32(pools.level[parent]) - 1)
		drawn := room - pools.source[position]
		pools.source[position] = max(own - drawn, 0)
		pools.net[position] = -max(drawn - own, 0)
		pools.net[parent] += pools.net[position]
	}
}

// The fed region's recorded steps in order while each step's candidate
// stays under cap_level, each setting the candidate's export and level and
// making its draw. The capped run is the uncapped run's prefix (0373's
// rule 6), so this is the capped greedy without its scans.
replay_steps :: proc(phase: Phase, pools: ^Pools, position, cap_level: i32) {
	for step in pools.steps[pools.record_first[position]:pools.record_end[position]] {
		if i32(pools.level[step.candidate]) + 1 > cap_level {
			when ODIN_TEST {
				pool_partial_replays += 1
			}
			return
		}
		count_pool_visits(1)
		pools.export[step.candidate] -= step.need
		pools.level[step.candidate] = step.level
		draw(phase, pools, step.candidate, position, step.need)
	}
}

// The room of a position's edge towards a candidate below it: a feeder's
// export, or down to its lower bound when the feeder sits at its parent's
// level (the edge is open both ways there), else the edge's planned flow
// above its lower bound.
downward_room :: proc(phase: Phase, pools: Pools, position: i32) -> i64 {
	if pools.state[position] != .Feeder {
		return min(pools.net[position], phase.upper[position]) - phase.lower[position] - pools.passed[position]
	}
	if pools.level[position] == pools.level[phase.parent[position]] {
		return pools.export[position] - phase.lower[position]
	}
	return pools.export[position]
}

// What the sources from the candidate's parent up to bound can bring it.
// A source joins below its own edge, so the least, over the edges on the
// path, of the edge's room towards the candidate (downward_room) plus the
// sources below it, as a running value down from bound: each position's
// source added to the least of the value above it and its room, each
// position once a pass of a greedy. No recursion.
reachable :: proc(phase: Phase, pools: ^Pools, candidate, bound: i32) -> i64 {
	clear(&pools.path)
	position := phase.parent[candidate]
	for position != bound && pools.reach_pass[position] != pools.pass {
		append(&pools.path, position)
		position = phase.parent[position]
	}
	reach := position == bound ? pools.source[bound] : pools.reach[position]
	for index := len(pools.path) - 1; index >= 0; index -= 1 {
		on_path := pools.path[index]
		reach = min(reach, downward_room(phase, pools^, on_path)) + pools.source[on_path]
		pools.reach[on_path] = reach
		pools.reach_pass[on_path] = pools.pass
	}
	count_pool_visits(len(pools.path))
	return reach
}

// Takes amount for the candidate from the sources on its path, nearest
// first; what a source does not cover crosses that position's edge
// towards the candidate (a feeder exports less, below 0 at its parent's
// level). The rest comes out of bound's source and is returned.
draw :: proc(phase: Phase, pools: ^Pools, candidate, bound: i32, amount: i64) -> (from_bound: i64) {
	from_bound = amount
	for position := phase.parent[candidate]; position != bound; position = phase.parent[position] {
		count_pool_visits(1)
		taken := min(pools.source[position], from_bound)
		pools.source[position] -= taken
		from_bound -= taken
		if pools.state[position] == .Feeder {
			pools.export[position] -= from_bound
		} else {
			pools.passed[position] += from_bound
		}
	}
	pools.source[bound] -= from_bound
	return
}

// Raises the candidates a level at a time with what the sources up to
// bound can bring them: the least level first, then the cheapest next
// level, then the first in pre-order. A level costs what the candidate's
// export falls by, and the candidate then sits at the highest level its
// export allows. With fill, what each level bought drew from bound's
// source is added at that level and each step is also recorded.
greedy :: proc(phase: Phase, responses: []Response, pools: ^Pools, candidates: []i32, bound: i32, fill: []i64) {
	for candidate in candidates {
		pools.done[candidate] = false
	}
	for {
		pools.pass += 1
		count_pool_visits(len(candidates))
		chosen, chosen_need := i32(-1), i64(0)
		for candidate in candidates {
			level := pools.level[candidate]
			if pools.done[candidate] || level >= LEVEL_FULL {
				continue
			}
			next := response_at(responses[candidate], int(level) + 1)
			need := pools.export[candidate] - next / LEVEL_FULL
			if next < 0 || need > reachable(phase, pools, candidate, bound) {
				pools.done[candidate] = true
				continue
			}
			if chosen < 0 || level < pools.level[chosen] || (level == pools.level[chosen] && need < chosen_need) {
				chosen, chosen_need = candidate, need
			}
		}
		if chosen < 0 {
			return
		}
		bought := pools.level[chosen] + 1
		pools.export[chosen] -= chosen_need
		pools.level[chosen] = u32(largest_level_at_least(responses[chosen], LEVEL_FULL * pools.export[chosen]))
		from_bound := draw(phase, pools, chosen, bound, chosen_need)
		if fill != nil {
			fill[bought] += from_bound
			append(&pools.steps, Greedy_Step{chosen, pools.level[chosen], chosen_need})
		}
	}
}

// A fed child's domain at its poor level, settled, and its own net; with
// candidates, its room (its net plus its capacity) spent on them by the
// greedy without a cap, fill[μ] what that spends with the candidates
// capped at μ (the running sums of what each level bought). Its run is
// recorded for the walks above it (replay_steps).
fed_fill :: proc(phase: Phase, thresholds: []Level_Thresholds, responses: []Response, pools: ^Pools, position: i32, spare_tables: ^[dynamic][]i64) -> (own_net: i64, fill: []i64) {
	walk_domain(phase, thresholds, pools, position, u32(max(thresholds[position].poor_level, 0)))
	settle_domain(phase, pools)
	own_net = pools.net[position]
	pools.record_first[position] = i32(len(pools.steps))
	pools.record_end[position] = i32(len(pools.steps))
	if len(pools.candidates) == 0 {
		return
	}
	pools.source[position] = own_net - phase.lower[position]
	fill = take_table(spare_tables)
	slice.zero(fill)
	greedy(phase, responses, pools, pools.candidates[:], position, fill)
	pools.record_end[position] = i32(len(pools.steps))
	for level in 1 ..< len(fill) {
		fill[level] += fill[level - 1]
	}
	return
}

// The slow path's levels. Bottom-up, each subtree's response for every
// level: R(level) = LEVEL_FULL * offer - demand * level plus its
// children's, each clamped to LEVEL_FULL times its edge's bounds up to its
// poor level and above it charged the whole joules it takes after its
// fill (fed_fill), made non-increasing: what the subtree gives its parent
// with its region at that level. The root takes the largest level its
// region can afford; top-down each domain hands its spare joules to its
// feeders (settle_levels). A response never rises with the level.
region_levels :: proc(phase: ^Phase) {
	count := len(phase.nodes)
	responses := make([]Response, count, context.temp_allocator)
	for position in 0 ..< count {
		responses[position] = {a = LEVEL_FULL * phase.offer[position], b = phase.demand[position]}
	}
	thresholds := make([]Level_Thresholds, count, context.temp_allocator)
	spare_tables := make([dynamic][]i64, 0, 16, context.temp_allocator)
	pools := make_pools(phase^)
	for position := count - 1; position > 0; position -= 1 {
		response := responses[position]
		if response.table != nil {
			make_non_increasing(response.table)
		}
		low, high := LEVEL_FULL * phase.lower[position], LEVEL_FULL * phase.upper[position]
		thresholds[position] = {
			rich_level = largest_level_at_least(response, high),
			poor_level = largest_level_at_least(response, low),
		}
		own_net: i64
		fill: []i64
		if thresholds[position].poor_level < LEVEL_FULL {
			own_net, fill = fed_fill(phase^, thresholds, responses, &pools, i32(position), &spare_tables)
		}
		add_child_response(&responses[phase.parent[position]], response, low, high, thresholds[position].poor_level, own_net, fill, &spare_tables)
		if fill != nil {
			append(&spare_tables, fill)
		}
		// A child that never feeds is never a candidate: no greedy reads its
		// table again.
		if response.table != nil && thresholds[position].rich_level < 0 {
			append(&spare_tables, response.table)
		}
	}
	root := responses[0]
	if root.table != nil {
		make_non_increasing(root.table)
	}
	root_level := response_at(root, 0) == 0 ? 0 : u32(largest_level_at_least(root, 0))
	settle_levels(phase^, thresholds, responses, &pools, root_level)
	copy(phase.level, pools.level)
	for position in 0 ..< count {
		phase.delivered[position] = delivered_at(phase.demand[position], phase.level[position])
	}
}

// Top-down in pre-order, each domain root once its level is final, the
// root and every feeder the walk above it met: its domain walked and
// settled at that level, its slack (its net less its export) a source,
// and the greedy over its candidates with every source up to the root.
// What a source has left stays for the later greedies below it.
settle_levels :: proc(phase: Phase, thresholds: []Level_Thresholds, responses: []Response, pools: ^Pools, root_level: u32) {
	for position in 0 ..< i32(len(phase.nodes)) {
		if position > 0 && pools.state[position] != .Feeder {
			continue
		}
		walk_domain(phase, thresholds, pools, position, position == 0 ? root_level : pools.level[position])
		settle_domain(phase, pools)
		pools.source[position] = pools.net[position] - (position > 0 ? pools.export[position] : 0)
		greedy(phase, responses, pools, pools.candidates[:], 0, nil)
	}
}

// Power flows towards the shortage: across an edge whose levels differ
// the richer side only exports, so the dispatch's repair never keeps a
// poorer region's generation flowing into a richer one.
bound_flows_by_levels :: proc(phase: ^Phase) {
	for position in 1 ..< len(phase.nodes) {
		level, parent_level := phase.level[position], phase.level[phase.parent[position]]
		if level < parent_level {
			phase.upper[position] = min(phase.upper[position], 0)
		} else if level > parent_level {
			phase.lower[position] = max(phase.lower[position], 0)
		}
	}
}

// Each position's children in pre-order (node order among siblings),
// children[offsets[position]:offsets[position + 1]].
phase_children :: proc(parent: []i32) -> (offsets: []i32, children: []i32) {
	count := len(parent)
	offsets = make([]i32, count + 1, context.temp_allocator)
	for position in 1 ..< count {
		offsets[parent[position] + 1] += 1
	}
	for position in 0 ..< count {
		offsets[position + 1] += offsets[position]
	}
	children = make([]i32, max(count - 1, 0), context.temp_allocator)
	cursor := slice.clone(offsets[:count], context.temp_allocator)
	for position in 1 ..< count {
		children[cursor[parent[position]]] = i32(position)
		cursor[parent[position]] += 1
	}
	return
}

// Shares amount over the rooms in proportion, rounded down, the rest a
// joule at a time in order, each within its room.
spread_over_rooms :: proc(amount: i64, rooms, given: []i64) {
	total: i64
	for room in rooms {
		total += room
	}
	assigned: i64
	for room, index in rooms {
		given[index] = total > 0 ? i64(i128(amount) * i128(room) / i128(total)) : 0
		assigned += given[index]
	}
	for room, index in rooms {
		extra := min(amount - assigned, room - given[index])
		given[index] += extra
		assigned += extra
	}
}

// Each order some position offers at gets the next class, from order 0
// up; the others -1.
order_classes :: proc(phase: Phase) -> (class_of: [256]i32, class_count: int) {
	offered: [256]bool
	for offer, position in phase.offer {
		if offer > 0 {
			offered[phase.order[position]] = true
		}
	}
	for is_offered, order in offered {
		class_of[order] = is_offered ? i32(class_count) : -1
		class_count += int(is_offered)
	}
	return
}

// The floor met by the earliest orders: amount moves from length to
// forced, class 0 first.
cut_from_cheapest :: proc(forced, length: []i64, amount: i64) {
	remaining := amount
	for class in 0 ..< len(length) {
		taken := clamp(remaining, 0, length[class])
		forced[class] += taken
		length[class] -= taken
		remaining -= taken
	}
}

// What the ceiling leaves out is the latest orders: amount leaves
// length, the last class first.
cut_from_dearest :: proc(length: []i64, amount: i64) {
	remaining := amount
	for class := len(length) - 1; class >= 0; class -= 1 {
		taken := clamp(remaining, 0, length[class])
		length[class] -= taken
		remaining -= taken
	}
}

// Bottom-up each position's rows: its own offer and supply in its class,
// its children's rows added in, then cut to its edge's floor and ceiling,
// what its subtree receives plus the edge's bounds (the root's both its
// delivered total, where the tree balances).
class_ranges :: proc(phase: Phase) -> (ranges: Class_Ranges) {
	count := len(phase.nodes)
	ranges.class_of, ranges.class_count = order_classes(phase)
	classes := ranges.class_count
	ranges.dispatched = make([]i64, count * classes, context.temp_allocator)
	ranges.forced = make([]i64, count * classes, context.temp_allocator)
	ranges.length = make([]i64, count * classes, context.temp_allocator)
	subtree_delivered := make([]i64, count, context.temp_allocator)
	for position := count - 1; position >= 0; position -= 1 {
		dispatched := ranges.dispatched[position * classes:][:classes]
		forced := ranges.forced[position * classes:][:classes]
		length := ranges.length[position * classes:][:classes]
		subtree_delivered[position] += phase.delivered[position]
		if phase.offer[position] > 0 {
			class := ranges.class_of[phase.order[position]]
			length[class] += phase.offer[position]
			dispatched[class] += phase.supplied[position]
		}
		floor, ceiling := subtree_delivered[position], subtree_delivered[position]
		if position > 0 {
			floor += phase.lower[position]
			ceiling += phase.upper[position]
		}
		cut_from_cheapest(forced, length, floor - math.sum(forced))
		cut_from_dearest(length, math.sum(forced) + math.sum(length) - ceiling)
		if position == 0 {
			break
		}
		parent := int(phase.parent[position])
		subtree_delivered[parent] += subtree_delivered[position]
		for class in 0 ..< classes {
			ranges.dispatched[parent * classes + class] += dispatched[class]
			ranges.forced[parent * classes + class] += forced[class]
			ranges.length[parent * classes + class] += length[class]
		}
	}
	return
}

// One class's target at the position split over the position and its
// children: each child starts from what the dispatch gave of the class in
// its subtree clamped to its range, the position from its own supply when
// it offers at the class, and the difference is spread over the room
// left in them, own first.
split_class_target :: proc(phase: ^Phase, ranges: Class_Ranges, target: []i64, own_children: []i32, position: i32, class: int, rooms, given: []i64) {
	classes := ranges.class_count
	owns := phase.offer[position] > 0 && int(ranges.class_of[phase.order[position]]) == class
	own := owns ? phase.supplied[position] : 0
	sum := own
	for child in own_children {
		at := int(child) * classes + class
		target[at] = clamp(ranges.dispatched[at], ranges.forced[at], ranges.forced[at] + ranges.length[at])
		sum += target[at]
	}
	difference := target[int(position) * classes + class] - sum
	if difference == 0 {
		return
	}
	raising := difference > 0
	rooms[0] = owns ? (raising ? phase.offer[position] - own : own) : 0
	for child, index in own_children {
		at := int(child) * classes + class
		rooms[index + 1] = raising ? ranges.forced[at] + ranges.length[at] - target[at] : target[at] - ranges.forced[at]
	}
	room_count := len(own_children) + 1
	spread_over_rooms(abs(difference), rooms[:room_count], given[:room_count])
	sign := i64(raising ? 1 : -1)
	if owns {
		phase.supplied[position] = own + sign * given[0]
	}
	for child, index in own_children {
		target[int(child) * classes + class] += sign * given[index + 1]
	}
}

// Moves the dispatch inside the edges' bounds in dispatch order (0389):
// each subtree's range per class from the bottom (class_ranges), then
// top-down each class's target split over the position and its children
// from the dispatch, the difference over the room left, own first. The
// root's targets are its forced row, its length 0 after its cuts. With
// one class it is the repair before 0389, joule for joule.
repair_dispatch :: proc(phase: ^Phase) {
	count := len(phase.nodes)
	ranges := class_ranges(phase^)
	classes := ranges.class_count
	offsets, children := phase_children(phase.parent)
	target := make([]i64, count * classes, context.temp_allocator)
	copy(target[:classes], ranges.forced[:classes])
	rooms := make([]i64, count, context.temp_allocator)
	given := make([]i64, count, context.temp_allocator)
	for position in 0 ..< i32(count) {
		own_children := children[offsets[position]:offsets[position + 1]]
		for class in 0 ..< classes {
			split_class_target(phase, ranges, target, own_children, position, class, rooms, given)
		}
	}
}
