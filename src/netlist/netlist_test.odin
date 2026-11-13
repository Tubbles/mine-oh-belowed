package netlist

@(require) import "core:log"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:testing"
@(require) import "core:time"

// Work item 0355 (A): the netlist core.

// A netlist of a test: the edges and inputs a seed gives.
Test_Netlist :: struct {
	node_count: int,
	edges:      []Edge,
	inputs:     []Node_Input,
}

BRUTE_FORCE_NETLISTS :: 3000
FEASIBILITY_NETLISTS :: 500

seeded_generator :: proc(state: ^rand.Default_Random_State, seed: int) -> rand.Generator {
	state^ = rand.create(u64(seed))
	return rand.default_random_generator(state)
}

// From low to high, both included.
pick :: proc(generator: rand.Generator, low, high: i64) -> i64 {
	return low + rand.int63_max(high - low + 1, generator)
}

// A random tree over count nodes, capacities 0: node k of the build is
// joined to an earlier one, then every node is renamed by a permutation,
// so the node order is not the walk's. In the temp allocator.
random_tree :: proc(generator: rand.Generator, count: int) -> []Edge {
	labels := rand.perm(count, context.temp_allocator, generator)
	edges := make([]Edge, count - 1, context.temp_allocator)
	for node in 1 ..< count {
		earlier := rand.int_max(node, generator)
		edges[node - 1] = {u32(labels[node]), u32(labels[earlier]), 0}
	}
	return edges
}

// The capacities around a whole level's need and an unlimited edge (0373).
BRUTE_FORCE_CORNER_CAPACITIES :: [10]i64{0, 1, 999, 1000, 1001, 1999, 2000, 3000, 4500, UNLIMITED_CAPACITY}

// 2 to 6 nodes, no stores. Demands from 0 to 4000 J in steps of 1000, so
// a level's delivery is exact; half the nodes offer 0 to 6000 J at orders
// 0 to 2; half the capacities from BRUTE_FORCE_CORNER_CAPACITIES, half
// from 0 to 6000 J.
brute_force_netlist :: proc(seed: int) -> Test_Netlist {
	state: rand.Default_Random_State
	generator := seeded_generator(&state, seed)
	count := int(pick(generator, 2, 6))
	edges := random_tree(generator, count)
	corners := BRUTE_FORCE_CORNER_CAPACITIES
	for &edge in edges {
		if rand.int_max(2, generator) == 0 {
			edge.capacity = corners[rand.int_max(len(corners), generator)]
		} else {
			edge.capacity = pick(generator, 0, 6000)
		}
	}
	inputs := make([]Node_Input, count, context.temp_allocator)
	for &input in inputs {
		input.demand = 1000 * pick(generator, 0, 4)
		if rand.int_max(2, generator) == 0 {
			input.offer, input.order = pick(generator, 0, 6000), u8(pick(generator, 0, 2))
		}
	}
	return {count, edges, inputs}
}

// Up to 300 nodes, a few edges dropped so some are forests. Demands 0 or
// 1 to 5000 J, half the nodes offer 0 to 6000 J, every eighth node a
// store, orders 0 to 10; half the capacities from 0 to 2000 J, half from
// 0 to above the totals.
feasibility_netlist :: proc(seed: int) -> Test_Netlist {
	state: rand.Default_Random_State
	generator := seeded_generator(&state, seed)
	count := int(pick(generator, 1, 300))
	inputs := make([]Node_Input, count, context.temp_allocator)
	total: i64
	for &input in inputs {
		input.order = u8(pick(generator, 0, 10))
		switch rand.int_max(8, generator) {
		case 0:
			input.store, input.offer, input.charge_room = true, pick(generator, 0, 3000), pick(generator, 0, 3000)
		case 1, 2, 3:
			input.offer = pick(generator, 0, 6000)
		case:
			input.demand = rand.int_max(2, generator) == 0 ? 0 : pick(generator, 1, 5000)
		}
		total += input.demand + input.offer
	}
	tree := random_tree(generator, count)
	edges := make([dynamic]Edge, 0, len(tree), context.temp_allocator)
	for edge in tree {
		if rand.int_max(20, generator) == 0 {
			continue
		}
		capacity := rand.int_max(2, generator) == 0 ? pick(generator, 0, 2000) : pick(generator, 0, total + 1000)
		append(&edges, Edge{edge.first, edge.second, capacity})
	}
	return {count, edges[:], inputs}
}

solve_test_netlist :: proc(netlist: Test_Netlist) -> (topology: Topology, outputs: []Node_Output) {
	topology = build_topology(netlist.node_count, netlist.edges, context.temp_allocator)
	outputs = make([]Node_Output, netlist.node_count, context.temp_allocator)
	solve(topology, netlist.inputs, outputs)
	return
}

topologies_equal :: proc(first, second: Topology) -> bool {
	return(
		slice.equal(first.parent, second.parent) &&
		slice.equal(first.capacity, second.capacity) &&
		slice.equal(first.order, second.order) &&
		slice.equal(first.tree_of, second.tree_of) &&
		slice.equal(first.trees, second.trees) &&
		slice.equal(first.chords, second.chords) \
	)
}

// Every node once in order, each tree's range holding its nodes with the
// root first and lowest, each parent before its child in the tree.
topology_is_well_formed :: proc(topology: Topology) -> bool {
	seen := make([]bool, len(topology.parent), context.temp_allocator)
	walked := 0
	for tree, index in topology.trees {
		if tree.first != u32(walked) || tree.count == 0 {
			return false
		}
		nodes := topology.order[tree.first:][:tree.count]
		root := nodes[0]
		if topology.parent[root] != NO_NODE || topology.capacity[root] != 0 || slice.min(nodes) != root {
			return false
		}
		if index > 0 && topology.order[topology.trees[index - 1].first] >= root {
			return false
		}
		for node in nodes {
			parent := topology.parent[node]
			if seen[node] || topology.tree_of[node] != u32(index) || (node != root && (parent == NO_NODE || !seen[parent])) {
				return false
			}
			seen[node] = true
		}
		walked += int(tree.count)
	}
	return walked == len(topology.order)
}

// Up to twice as many edges as nodes, self edges and repeated pairs
// among them.
random_edge_list :: proc(generator: rand.Generator, node_count: int) -> []Edge {
	edges := make([]Edge, rand.int_max(2 * node_count + 1, generator), context.temp_allocator)
	for &edge in edges {
		edge = {u32(rand.int_max(node_count, generator)), u32(rand.int_max(node_count, generator)), pick(generator, 0, 1000)}
	}
	return edges
}

@(test)
test_build_topology_is_order_independent :: proc(t: ^testing.T) {
	for seed in 0 ..< 200 {
		state: rand.Default_Random_State
		generator := seeded_generator(&state, seed)
		node_count := int(pick(generator, 1, 40))
		edges := random_edge_list(generator, node_count)
		reference := build_topology(node_count, edges, context.temp_allocator)
		testing.expectf(t, topology_is_well_formed(reference), "seed %d: the topology is malformed", seed)
		for _ in 0 ..< 10 {
			shuffled := slice.clone(edges, context.temp_allocator)
			rand.shuffle(shuffled, generator)
			for &edge in shuffled {
				if rand.int_max(2, generator) == 0 {
					edge.first, edge.second = edge.second, edge.first
				}
			}
			again := build_topology(node_count, shuffled, context.temp_allocator)
			testing.expectf(t, topologies_equal(reference, again), "seed %d: a shuffled edge list gives another topology", seed)
		}
		free_all(context.temp_allocator)
	}
	// A parallel pair's capacities add, up to the cap.
	parallel := build_topology(2, {{0, 1, 100}, {1, 0, 50}}, context.temp_allocator)
	testing.expect_value(t, parallel.capacity[1], 150)
	testing.expect_value(t, len(parallel.chords), 0)
	capped := build_topology(2, {{0, 1, UNLIMITED_CAPACITY}, {1, 0, UNLIMITED_CAPACITY}}, context.temp_allocator)
	testing.expect_value(t, capped.capacity[1], UNLIMITED_CAPACITY)
	// The later edge of a loop in sorted order is the chord.
	loop := build_topology(3, {{1, 2, 7}, {2, 0, 5}, {0, 1, 3}}, context.temp_allocator)
	testing.expect(t, slice.equal(loop.chords, []Edge{{1, 2, 7}}))
	testing.expect(t, slice.equal(loop.parent, []u32{NO_NODE, 0, 0}))
	// A node without edges is a tree of its own.
	alone := build_topology(3, {{0, 2, 1}}, context.temp_allocator)
	testing.expect(t, slice.equal(alone.trees, []Tree{{0, 2}, {2, 1}}))
	testing.expect(t, slice.equal(alone.tree_of, []u32{0, 1, 0}))
	testing.expect_value(t, alone.parent[1], NO_NODE)
	// Depth first, neighbours ascending, from the lowest node.
	walk := build_topology(5, {{4, 1, 1}, {0, 3, 1}, {1, 3, 1}, {2, 3, 1}}, context.temp_allocator)
	testing.expect(t, slice.equal(walk.order, []u32{0, 3, 1, 4, 2}))
	testing.expect(t, slice.equal(walk.parent, []u32{NO_NODE, 3, 3, 0, 1}))
	free_all(context.temp_allocator)
}

// Today's dispatch on one netlist: the orders ascending, each up to its
// offers, in proportion, rounded down, the rest a joule at a time in node
// order.
reference_dispatch :: proc(inputs: []Node_Input, delivered: i64) -> []i64 {
	supplied := make([]i64, len(inputs), context.temp_allocator)
	remaining := delivered
	for order in 0 ..= 255 {
		order_supply: i64
		for input in inputs {
			order_supply += int(input.order) == order ? input.offer : 0
		}
		if order_supply == 0 {
			continue
		}
		share := min(order_supply, remaining)
		assigned: i64
		for input, node in inputs {
			if int(input.order) == order {
				supplied[node] = i64(i128(input.offer) * i128(share) / i128(order_supply))
				assigned += supplied[node]
			}
		}
		for input, node in inputs {
			if int(input.order) == order {
				extra := min(share - assigned, input.offer - supplied[node])
				supplied[node] += extra
				assigned += extra
			}
		}
		remaining -= share
	}
	return supplied
}

@(test)
test_uniform_netlists_match_the_pooled_balance :: proc(t: ^testing.T) {
	for seed in 0 ..< 500 {
		state: rand.Default_Random_State
		generator := seeded_generator(&state, seed)
		count := int(pick(generator, 1, 60))
		edges := random_tree(generator, count)
		inputs := make([]Node_Input, count, context.temp_allocator)
		supply, demand: i64
		for &edge in edges {
			edge.capacity = UNLIMITED_CAPACITY
		}
		for &input in inputs {
			if rand.int_max(2, generator) == 0 {
				input.offer, input.order = pick(generator, 0, 6000), u8(pick(generator, 0, 3))
			} else {
				input.demand = pick(generator, 0, 5000)
			}
			supply += input.offer
			demand += input.demand
		}
		_, outputs := solve_test_netlist({count, edges, inputs})
		level := pooled_level(supply, demand)
		delivered: i64
		for output, node in outputs {
			testing.expectf(t, output.level == level, "seed %d: node %d at %d, pooled %d", seed, node, output.level, level)
			testing.expectf(t, output.delivered == inputs[node].demand * i64(level) / LEVEL_FULL, "seed %d: node %d received %d", seed, node, output.delivered)
			delivered += output.delivered
		}
		expected := reference_dispatch(inputs, delivered)
		for output, node in outputs {
			testing.expectf(t, output.supplied == expected[node], "seed %d: node %d supplied %d, the dispatch %d", seed, node, output.supplied, expected[node])
		}
		free_all(context.temp_allocator)
	}
}

Edge_Status :: enum u8 {
	Open,
	Saturated_Up,
	Saturated_Down,
}

lexicographically_before :: proc(first, second: []u32) -> bool {
	for value, index in first {
		if value != second[index] {
			return value < second[index]
		}
	}
	return false
}

consumer_levels_sorted :: proc(inputs: []Node_Input, levels: []u32) -> []u32 {
	sorted := make([dynamic]u32, 0, len(inputs), context.temp_allocator)
	for input, node in inputs {
		if input.demand > 0 {
			append(&sorted, levels[node])
		}
	}
	slice.sort(sorted[:])
	return sorted[:]
}

// The responses of one assignment of the edges' states (by position) under
// the rule. Per region top in reverse pre-order a table of its region's
// exact lines, plus each Saturated_Up child's capacity and at every level
// each Saturated_Down child's charge from its fed_fill, every level above
// the lowest its Saturated_Up children start at cut off (a region never
// sits above a feeder still at its capacity), made non-increasing. The
// states become the thresholds the solver's walks read: an open child
// always joined, a Saturated_Up child a feeder from the level its table
// reaches its capacity at, a Saturated_Down child fed at the level its
// table reaches its lower bound at. A child behind an edge of capacity 0
// joins nothing: it is a tree of its own for the levels, at the level its
// table affords alone (as a feeder of nothing or fed with nothing, as the
// solver's thresholds put it), and adds nothing to its parent's table, no
// ceiling either. False when one of those levels or the root's is -1. The
// region tables are left in responses.
brute_force_responses :: proc(phase: Phase, status: []Edge_Status, thresholds: []Level_Thresholds, responses: []Response, pools: ^Pools, spare_tables: ^[dynamic][]i64) -> (root_level: u32, valid: bool) {
	count := len(phase.nodes)
	clear(&pools.steps)
	slice.zero(pools.record_first)
	slice.zero(pools.record_end)
	top := make([]i32, count, context.temp_allocator)
	ceiling := make([]i32, count, context.temp_allocator)
	lines := make([]Response, count, context.temp_allocator)
	for position in 0 ..< count {
		separate := position == 0 || status[position] != .Open || phase.upper[position] == 0
		top[position] = separate ? i32(position) : top[phase.parent[position]]
		ceiling[position] = LEVEL_FULL
		lines[top[position]].a += LEVEL_FULL * phase.offer[position]
		lines[top[position]].b += phase.demand[position]
		thresholds[position] = {-1, LEVEL_FULL}
		responses[position] = {}
	}
	for position in 0 ..< count {
		if top[position] == i32(position) {
			responses[position].table = take_table(spare_tables)
			for &value, level in responses[position].table {
				value = response_at(lines[position], level)
			}
		}
	}
	for position := count - 1; position >= 0; position -= 1 {
		if top[position] != i32(position) {
			continue
		}
		table := responses[position].table
		for level in ceiling[position] + 1 ..= LEVEL_FULL {
			table[level] = min(i64)
		}
		make_non_increasing(table)
		if position == 0 {
			break
		}
		parent_top := top[phase.parent[position]]
		parent_table := responses[parent_top].table
		low, high := LEVEL_FULL * phase.lower[position], LEVEL_FULL * phase.upper[position]
		if phase.upper[position] == 0 {
			alone := largest_level_at_least(responses[position], 0)
			if alone < 0 {
				return
			}
			thresholds[position] = {alone, alone}
			// Fed whenever its parent sits above alone: the walks replay its
			// run, so fed_fill records it (0390). Its net adds nothing.
			if alone < LEVEL_FULL {
				_, fill := fed_fill(phase, thresholds, responses, pools, i32(position), spare_tables)
				if fill != nil {
					append(spare_tables, fill)
				}
			}
			continue
		}
		if status[position] == .Saturated_Up {
			base := largest_level_at_least(responses[position], high)
			if base < 0 {
				return
			}
			thresholds[position] = {base, LEVEL_FULL}
			ceiling[parent_top] = min(ceiling[parent_top], base)
			for &value in parent_table {
				value += high
			}
			continue
		}
		fed_level := largest_level_at_least(responses[position], low)
		if fed_level < 0 {
			return
		}
		thresholds[position] = {-1, fed_level}
		own_net, fill := fed_fill(phase, thresholds, responses, pools, i32(position), spare_tables)
		for &value, level in parent_table {
			drawn := level > 0 && fill != nil ? fill[level - 1] : 0
			value -= LEVEL_FULL * max(drawn - own_net, 0)
		}
		if fill != nil {
			append(spare_tables, fill)
		}
	}
	root := responses[0]
	if response_at(root, 0) == 0 {
		return 0, true
	}
	level := largest_level_at_least(root, 0)
	return u32(max(level, 0)), level >= 0
}

// A flow exists with every open edge within its capacity, every
// saturated edge between 0 and its capacity in its direction (a
// Saturated_Up edge at equal levels open), every offer between 0 and
// itself and every node balanced: per node, bottom-up, the range its
// edge's flow can take. Every tree of a forest.
brute_force_flow_exists :: proc(topology: Topology, inputs: []Node_Input, status: []Edge_Status, levels: []u32) -> bool {
	low := make([]i64, len(inputs), context.temp_allocator)
	high := make([]i64, len(inputs), context.temp_allocator)
	for index := len(topology.order) - 1; index >= 0; index -= 1 {
		node := topology.order[index]
		delivered := inputs[node].demand * i64(levels[node]) / LEVEL_FULL
		low[node] -= delivered
		high[node] += inputs[node].offer - delivered
		parent := topology.parent[node]
		if parent == NO_NODE {
			if low[node] > 0 || high[node] < 0 {
				return false
			}
			continue
		}
		capacity := topology.capacity[node]
		switch status[node] {
		case .Open:
			low[node], high[node] = max(low[node], -capacity), min(high[node], capacity)
		case .Saturated_Up:
			// At its parent's level a feeder's edge is open both ways, as the
			// solver's pool uses it.
			inwards := levels[node] == levels[parent] ? capacity : 0
			low[node], high[node] = max(low[node], -inwards), min(high[node], capacity)
		case .Saturated_Down:
			low[node], high[node] = max(low[node], -capacity), min(high[node], 0)
		}
		if low[node] > high[node] {
			return false
		}
		low[parent] += low[node]
		high[parent] += high[node]
	}
	return true
}

// The model's definition (0355): levels are equal across an edge with room
// to spare; across an edge whose levels differ, power flows from the richer
// side to the poorer. A Saturated_Down child sits strictly below its
// parent, as the solver's fed region does: a down edge at equal levels
// would be a second answer, not a better one.
brute_force_levels_follow_the_flow :: proc(topology: Topology, status: []Edge_Status, levels: []u32) -> bool {
	for node in topology.order[1:] {
		parent := topology.parent[node]
		if (status[node] == .Saturated_Up && levels[node] < levels[parent]) || (status[node] == .Saturated_Down && levels[node] >= levels[parent]) {
			return false
		}
	}
	return true
}

// Every edge above 0 and below UNLIMITED_CAPACITY open, saturated up or
// saturated down, an unlimited edge open (a down edge of unlimited
// capacity puts its region at full, so at its feeder's level, where open
// is as good; an up one leaves a negative supply), an edge of capacity 0
// open for the flow checks, carrying nothing, its child a tree of its own
// (brute_force_responses): the lexicographically largest of the
// sorted levels of the consumers with a demand over the assignments whose
// levels by the rule (brute_force_responses, then the solver's
// settle_levels) follow the flow and whose flows exist. One tree. found
// false when no assignment counts.
// A saturated edge carries between 0 and its capacity in its direction:
// exactly its capacity leaves 1 in 6 netlists with no assignment, since a
// consumer delivered at a whole per mille rarely takes a capacity exactly.
// The direction rule is the model's definition, not a fit: without it a
// saturated edge may import into the richer side to soak up a rounding
// leftover, as in seed 2169, where a 1000 J consumer behind a 901 J edge
// takes 901 J at 901 while the root's 4000 J stay at 900.
// It shares fed_fill, the walks, the greedy, the replay, the draws and
// settle_levels with the solver, so it checks the edges' states, the
// clamps, the charge and the envelope, not the pool's split: the
// definition test and the hand cases guard that.
brute_force_levels :: proc(topology: Topology, inputs: []Node_Input) -> (best: []u32, found: bool) {
	count := len(inputs)
	phase := make_phase(topology, topology.order[topology.trees[0].first:][:topology.trees[0].count])
	set_supply_phase(&phase, topology, inputs)
	pools := make_pools(phase)
	thresholds := make([]Level_Thresholds, count, context.temp_allocator)
	responses := make([]Response, count, context.temp_allocator)
	spare_tables := make([dynamic][]i64, 0, 16, context.temp_allocator)
	position_status := make([]Edge_Status, count, context.temp_allocator)
	status := make([]Edge_Status, count, context.temp_allocator)
	levels := make([]u32, count, context.temp_allocator)
	limited := make([dynamic]int, 0, count, context.temp_allocator)
	for position in 1 ..< count {
		if 0 < phase.upper[position] && phase.upper[position] < UNLIMITED_CAPACITY {
			append(&limited, position)
		}
	}
	assignments := 1
	for _ in limited {
		assignments *= 3
	}
	for assignment in 0 ..< assignments {
		rest := assignment
		for position in limited {
			position_status[position] = Edge_Status(rest % 3)
			rest /= 3
		}
		root_level, valid := brute_force_responses(phase, position_status, thresholds, responses, &pools, &spare_tables)
		if valid {
			settle_levels(phase, thresholds, responses, &pools, root_level)
			for node, position in phase.nodes {
				status[node], levels[node] = position_status[position], pools.level[position]
			}
			if brute_force_levels_follow_the_flow(topology, status, levels) && brute_force_flow_exists(topology, inputs, status, levels) {
				sorted := consumer_levels_sorted(inputs, levels)
				if !found || lexicographically_before(best, sorted) {
					best, found = sorted, true
				}
			}
		}
		for &response in responses {
			if response.table != nil {
				append(&spare_tables, response.table)
				response.table = nil
			}
		}
	}
	return
}

// The checks of test_solve_output_is_feasible; false and one message at
// the first that fails.
expect_feasible_output :: proc(t: ^testing.T, topology: Topology, inputs: []Node_Input, outputs: []Node_Output, seed: int) -> bool {
	for output, node in outputs {
		input := inputs[node]
		node_holds :=
			output.level <= LEVEL_FULL &&
			0 <= output.delivered &&
			output.delivered <= input.demand &&
			0 <= output.supplied &&
			output.supplied <= input.offer &&
			0 <= output.charged &&
			output.charged <= (input.store ? input.charge_room : 0) &&
			(output.charged == 0 || output.supplied == 0)
		if !node_holds {
			testing.expectf(t, false, "seed %d: node %d: %v for %v", seed, node, output, input)
			return false
		}
	}
	net := make([]i64, len(outputs), context.temp_allocator)
	for index := len(topology.order) - 1; index >= 0; index -= 1 {
		node := topology.order[index]
		output := outputs[node]
		net[node] += output.supplied - output.delivered - output.charged
		parent := topology.parent[node]
		if parent == NO_NODE {
			continue
		}
		if abs(output.flow) > topology.capacity[node] || output.flow != net[node] {
			testing.expectf(t, false, "seed %d: node %d carries %d on %d, its subtree's net %d", seed, node, output.flow, topology.capacity[node], net[node])
			return false
		}
		net[parent] += net[node]
	}
	for tree in topology.trees {
		root := topology.order[tree.first]
		if net[root] != 0 {
			testing.expectf(t, false, "seed %d: the tree at %d supplies %d more than it delivers and charges", seed, root, net[root])
			return false
		}
	}
	return true
}

@(test) // slow
test_solve_matches_brute_force_on_small_netlists :: proc(t: ^testing.T) {
	differing := make([dynamic]int, context.allocator)
	defer delete(differing)
	for seed in 0 ..< BRUTE_FORCE_NETLISTS {
		netlist := brute_force_netlist(seed)
		topology, outputs := solve_test_netlist(netlist)
		expect_feasible_output(t, topology, netlist.inputs, outputs, seed)
		levels := make([]u32, netlist.node_count, context.temp_allocator)
		for output, node in outputs {
			levels[node] = output.level
		}
		best, found := brute_force_levels(topology, netlist.inputs)
		if !found || !slice.equal(consumer_levels_sorted(netlist.inputs, levels), best) {
			append(&differing, seed)
		}
		free_all(context.temp_allocator)
	}
	testing.expectf(t, len(differing) == 0, "%d of %d netlists differ from the brute force, seeds %v", len(differing), BRUTE_FORCE_NETLISTS, differing[:])
}

@(test) // slow
test_solve_output_is_feasible :: proc(t: ^testing.T) {
	saturated := 0
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		netlist := feasibility_netlist(seed)
		topology, outputs := solve_test_netlist(netlist)
		expect_feasible_output(t, topology, netlist.inputs, outputs, seed)
		for output, node in outputs {
			if topology.parent[node] != NO_NODE && abs(output.flow) == topology.capacity[node] && output.flow != 0 {
				saturated += 1
			}
		}
		free_all(context.temp_allocator)
	}
	testing.expect(t, saturated > 0, "some edge saturates")
}

// The feasibility set without stores and with demands in whole thousands,
// so a level's delivery is exact.
definition_netlist :: proc(seed: int) -> Test_Netlist {
	netlist := feasibility_netlist(seed)
	for &input in netlist.inputs {
		input.demand = input.demand / 1000 * 1000
		input.store, input.charge_room = false, 0
	}
	return netlist
}

LIGHT_CABLE_NETLISTS :: 3000

// 0373's review: 7 to 9 nodes on cables of 0 to 20 J, so most cables
// saturate. Twins are a root with two or more identical chains below it,
// so regions tie at one level; else one chain in a shuffled order.
// Demands 0 to 5000 J in steps of 1000; half the nodes offer, a quarter of
// those 0 to 20 J, the rest 0 to 6000 J, at orders 0 to 2.
light_cable_netlist :: proc(seed: int, twins: bool) -> Test_Netlist {
	state: rand.Default_Random_State
	generator := seeded_generator(&state, seed)
	chain := twins ? int(pick(generator, 1, 4)) : int(pick(generator, 7, 9)) - 1
	copies := twins ? int(pick(generator, i64(6 + chain - 1) / i64(chain), 8 / i64(chain))) : 1
	count := 1 + copies * chain
	template := make([]Node_Input, 1 + chain, context.temp_allocator)
	capacities := make([]i64, chain, context.temp_allocator)
	for &input in template {
		input.demand = 1000 * pick(generator, 0, 5)
		if rand.int_max(2, generator) == 0 {
			input.offer = rand.int_max(4, generator) == 0 ? pick(generator, 0, 20) : pick(generator, 0, 6000)
			input.order = u8(pick(generator, 0, 2))
		}
	}
	for &capacity in capacities {
		capacity = pick(generator, 0, 20)
	}
	labels := rand.perm(count, context.temp_allocator, generator)
	if twins {
		for &label, index in labels {
			label = index
		}
	}
	inputs := make([]Node_Input, count, context.temp_allocator)
	edges := make([]Edge, count - 1, context.temp_allocator)
	inputs[labels[0]] = template[0]
	for copy_index in 0 ..< copies {
		for index in 0 ..< chain {
			node := 1 + copy_index * chain + index
			parent := index == 0 ? 0 : node - 1
			inputs[labels[node]] = template[1 + index]
			edges[node - 1] = {u32(labels[node]), u32(labels[parent]), capacities[index]}
		}
	}
	return {count, edges, inputs}
}

// Each node's children in the topology, children[offsets[node]:offsets[node + 1]].
node_children :: proc(topology: Topology) -> (offsets: []u32, children: []u32) {
	count := len(topology.parent)
	offsets = make([]u32, count + 1, context.temp_allocator)
	for parent in topology.parent {
		if parent != NO_NODE {
			offsets[parent + 1] += 1
		}
	}
	for node in 0 ..< count {
		offsets[node + 1] += offsets[node]
	}
	children = make([]u32, offsets[count], context.temp_allocator)
	cursor := slice.clone(offsets[:count], context.temp_allocator)
	for parent, node in topology.parent {
		if parent != NO_NODE {
			children[cursor[parent]] = u32(node)
			cursor[parent] += 1
		}
	}
	return
}

// A node's tree neighbours: its parent, if any, then its children.
node_neighbours :: proc(topology: Topology, offsets, children: []u32, node: u32) -> []u32 {
	own := children[offsets[node]:offsets[node + 1]]
	neighbours := make([]u32, len(own) + 1, context.temp_allocator)
	count := 0
	if topology.parent[node] != NO_NODE {
		neighbours[0] = topology.parent[node]
		count = 1
	}
	copy(neighbours[count:], own)
	return neighbours[:count + len(own)]
}

// The joules running from first to its neighbour second over their edge.
flow_between :: proc(topology: Topology, outputs: []Node_Output, first, second: u32) -> i64 {
	return topology.parent[first] == second ? outputs[first].flow : -outputs[second].flow
}

// The edge's capacity between two neighbours.
capacity_between :: proc(topology: Topology, first, second: u32) -> i64 {
	return topology.capacity[topology.parent[first] == second ? first : second]
}

// The nodes reached from start over tree edges whose two levels are equal,
// marking seen, start first.
equal_level_component :: proc(topology: Topology, outputs: []Node_Output, start: u32, seen: []bool) -> []u32 {
	offsets, children := node_children(topology)
	component := make([dynamic]u32, 0, 16, context.temp_allocator)
	seen[start] = true
	append(&component, start)
	for index := 0; index < len(component); index += 1 {
		node := component[index]
		for other in node_neighbours(topology, offsets, children, node) {
			if !seen[other] && outputs[other].level == outputs[node].level {
				seen[other] = true
				append(&component, other)
			}
		}
	}
	return component[:]
}

// The most the unsupplied offers of start's equal-level component, not
// crossing to across, can deliver to start: from the far ends inwards,
// each node's unsupplied offer plus what each node beyond it can send,
// up to the room the edge between them leaves towards it.
spare_toward :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, start, across: u32) -> i64 {
	seen := make([]bool, len(inputs), context.temp_allocator)
	seen[across] = true
	component := equal_level_component(topology, outputs, start, seen)
	offsets, children := node_children(topology)
	spare := make([]i64, len(inputs), context.temp_allocator)
	nearer := make([]u32, len(inputs), context.temp_allocator)
	nearer[start] = NO_NODE
	for node in component {
		for other in node_neighbours(topology, offsets, children, node) {
			if other != nearer[node] && other != across && outputs[other].level == outputs[node].level {
				nearer[other] = node
			}
		}
	}
	for index := len(component) - 1; index >= 0; index -= 1 {
		node := component[index]
		spare[node] += inputs[node].offer - outputs[node].supplied
		if index > 0 {
			towards := nearer[node]
			room := capacity_between(topology, node, towards) - flow_between(topology, outputs, node, towards)
			spare[towards] += min(spare[node], room)
		}
	}
	return spare[start]
}

// From start over the tree edges whose two levels are equal, marking seen:
// the component's demand and its idle reachable supply, its unsupplied
// offers plus, on each edge to a richer neighbour, the least of the edge's
// room towards it and the neighbour's spare, and on each edge to a poorer
// neighbour it feeds, the least of that flow and the neighbour's spare.
component_idle_supply :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, start: u32, seen: []bool) -> (demand, idle: i64) {
	offsets, children := node_children(topology)
	for node in equal_level_component(topology, outputs, start, seen) {
		demand += inputs[node].demand
		idle += inputs[node].offer - outputs[node].supplied
		for other in node_neighbours(topology, offsets, children, node) {
			switch {
			case outputs[other].level > outputs[node].level:
				room := capacity_between(topology, node, other) - flow_between(topology, outputs, other, node)
				idle += min(room, spare_toward(topology, inputs, outputs, other, node))
			case outputs[other].level < outputs[node].level:
				if sent := flow_between(topology, outputs, node, other); sent > 0 {
					idle += min(sent, spare_toward(topology, inputs, outputs, other, node))
				}
			}
		}
	}
	return
}

// Whether a flow exists with the component one level higher and every
// other node at its level, each edge open where its levels are equal and
// saturated towards the poorer side where they differ.
component_can_rise :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, component: []u32) -> bool {
	levels := make([]u32, len(inputs), context.temp_allocator)
	for output, node in outputs {
		levels[node] = output.level
	}
	for node in component {
		levels[node] += 1
	}
	status := make([]Edge_Status, len(inputs), context.temp_allocator)
	for node in topology.order {
		parent := topology.parent[node]
		switch {
		case parent == NO_NODE || levels[node] == levels[parent]:
			status[node] = .Open
		case levels[node] > levels[parent]:
			status[node] = .Saturated_Up
		case:
			status[node] = .Saturated_Down
		}
	}
	return brute_force_flow_exists(topology, inputs, status, levels)
}

// The demand of start's equal level component.
component_demand :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, start: u32) -> (demand: i64) {
	for member in equal_level_component(topology, outputs, start, make([]bool, len(inputs), context.temp_allocator)) {
		demand += inputs[member].demand
	}
	return
}

// The model's definition (0355, 0373): levels are equal across an edge
// with room to spare; across an edge whose levels differ, power flows from
// the richer side to the poorer. A side whose equal level component has no
// demand is exempt: nobody receives at its level, so the level it reports
// breaches nothing (a fed region or a root of junctions and generators
// only sits at its threshold). No component below full with a demand
// holds idle reachable supply worth a level of its demand
// (component_idle_supply) or can rise a level alone (component_can_rise).
// The bound is 0, derived: a candidate stops only when no source that
// reaches it covers its next level, and a source only falls after that,
// the candidate's own subtree being in its response already; a region
// that is no candidate (the root, a domain root, a fed region) sits at the
// highest level its response allows, the response counting every source
// that can reach it; with whole thousand demands a level costs exactly a
// thousandth of the need. Returns what breaks it and the largest idle
// supply in per mille of its component's demand.
levels_follow_the_flow :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) -> (broken: int, largest_idle_per_mille: i64) {
	topology, outputs := solve_test_netlist(netlist)
	for node in topology.order {
		parent := topology.parent[node]
		if parent == NO_NODE || outputs[node].level == outputs[parent].level {
			continue
		}
		inflow := outputs[node].level > outputs[parent].level ? outputs[node].flow : -outputs[node].flow
		if component_demand(topology, netlist.inputs, outputs, node) == 0 || component_demand(topology, netlist.inputs, outputs, parent) == 0 {
			continue
		}
		if inflow < 0 {
			testing.expectf(t, false, "seed %d: node %d at %d, its parent %d at %d, flow %d of %d", seed, node, outputs[node].level, parent, outputs[parent].level, outputs[node].flow, topology.capacity[node])
			broken += 1
		}
	}
	seen := make([]bool, netlist.node_count, context.temp_allocator)
	for node in topology.order {
		if seen[node] {
			continue
		}
		demand, idle := component_idle_supply(topology, netlist.inputs, outputs, node, seen)
		if outputs[node].level == LEVEL_FULL || demand == 0 {
			continue
		}
		largest_idle_per_mille = max(largest_idle_per_mille, idle * LEVEL_FULL / demand)
		component := equal_level_component(topology, outputs, node, make([]bool, netlist.node_count, context.temp_allocator))
		if idle * LEVEL_FULL >= demand || component_can_rise(topology, netlist.inputs, outputs, component) {
			testing.expectf(t, false, "seed %d: the component of node %d at %d, demand %d, holds %d J idle or can rise", seed, node, outputs[node].level, demand, idle)
			broken += 1
		}
	}
	return
}

@(test) // slow
test_levels_differ_only_across_saturated_edges :: proc(t: ^testing.T) {
	broken, differing: int
	largest_idle_per_mille: i64
	for seed in 0 ..< BRUTE_FORCE_NETLISTS {
		netlist_broken, idle_per_mille := levels_follow_the_flow(t, brute_force_netlist(seed), seed)
		broken, largest_idle_per_mille = broken + netlist_broken, max(largest_idle_per_mille, idle_per_mille)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		netlist := definition_netlist(seed)
		netlist_broken, idle_per_mille := levels_follow_the_flow(t, netlist, seed)
		broken, largest_idle_per_mille = broken + netlist_broken, max(largest_idle_per_mille, idle_per_mille)
		topology, outputs := solve_test_netlist(netlist)
		for node in topology.order {
			parent := topology.parent[node]
			differing += int(parent != NO_NODE && outputs[node].level != outputs[parent].level)
		}
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< LIGHT_CABLE_NETLISTS {
		for twins in ([2]bool{true, false}) {
			netlist_broken, idle_per_mille := levels_follow_the_flow(t, light_cable_netlist(seed, twins), seed)
			broken, largest_idle_per_mille = broken + netlist_broken, max(largest_idle_per_mille, idle_per_mille)
			free_all(context.temp_allocator)
		}
	}
	testing.expectf(t, broken == 0, "%d edges or components break the definition, the largest idle supply %d per mille", broken, largest_idle_per_mille)
	testing.expect(t, differing > 0, "some levels differ across an edge")
}

// The fast path's outputs when it holds, else the slow path's, against
// the slow path alone, per tree. Returns how many trees took the fast
// path.
expect_slow_path_agrees :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) -> int {
	topology := build_topology(netlist.node_count, netlist.edges, context.temp_allocator)
	fast := make([]Node_Output, netlist.node_count, context.temp_allocator)
	slow := make([]Node_Output, netlist.node_count, context.temp_allocator)
	took := 0
	for tree, index in topology.trees {
		if !solve_tree(topology, index, netlist.inputs, fast) {
			continue
		}
		took += 1
		solve_tree(topology, index, netlist.inputs, slow, fast_path = false)
		for node in topology.order[tree.first:][:tree.count] {
			testing.expectf(t, fast[node] == slow[node], "seed %d: node %d, fast %v, slow %v", seed, node, fast[node], slow[node])
		}
	}
	return took
}

@(test) // slow
test_slow_path_agrees_with_the_fast_path :: proc(t: ^testing.T) {
	took := 0
	for seed in 0 ..< BRUTE_FORCE_NETLISTS {
		took += expect_slow_path_agrees(t, brute_force_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		took += expect_slow_path_agrees(t, feasibility_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	testing.expect(t, took > 0, "some tree takes the fast path")
}

// Nodes joined in the test's words: edges (child, parent, capacity).
hand_netlist :: proc(inputs: []Node_Input, edges: []Edge) -> (topology: Topology, outputs: []Node_Output) {
	return solve_test_netlist({len(inputs), edges, inputs})
}

@(test)
test_a_saturated_cable_browns_out_only_its_side :: proc(t: ^testing.T) {
	// A 1000 J offer at the root with a 200 J consumer beside it, a 500 J
	// edge to a junction with two 400 J consumers.
	inputs := []Node_Input{{offer = 1000}, {demand = 200}, {}, {demand = 400}, {demand = 400}}
	edges := []Edge{{1, 0, UNLIMITED_CAPACITY}, {2, 0, 500}, {3, 2, UNLIMITED_CAPACITY}, {4, 2, UNLIMITED_CAPACITY}}
	_, outputs := hand_netlist(inputs, edges)
	testing.expect_value(t, outputs[3].level, 625)
	testing.expect_value(t, outputs[4].level, 625)
	testing.expect_value(t, outputs[1].level, 1000)
	testing.expect_value(t, outputs[2].flow, -500)
	testing.expect_value(t, outputs[0].supplied, 700)
	free_all(context.temp_allocator)
}

@(test)
test_a_rich_branch_exports_at_capacity :: proc(t: ^testing.T) {
	// A 2000 J offer behind a 300 J edge with a 500 J consumer, 1000 J of
	// consumers at the root.
	inputs := []Node_Input{{demand = 600}, {offer = 2000}, {demand = 500}, {demand = 400}}
	edges := []Edge{{1, 0, 300}, {2, 1, UNLIMITED_CAPACITY}, {3, 0, UNLIMITED_CAPACITY}}
	_, outputs := hand_netlist(inputs, edges)
	testing.expect_value(t, outputs[2].level, 1000)
	testing.expect_value(t, outputs[0].level, 300)
	testing.expect_value(t, outputs[3].level, 300)
	testing.expect_value(t, outputs[1].flow, 300)
	testing.expect_value(t, outputs[1].supplied, 800)
	free_all(context.temp_allocator)
}

@(test)
test_dispatch_follows_the_order_where_cables_allow :: proc(t: ^testing.T) {
	// A 900 J offer at order 0 behind a 300 J edge, a 900 J offer at order
	// 1 at the root, 1000 J demanded at the root.
	inputs := []Node_Input{{demand = 1000, offer = 900, order = 1}, {offer = 900, order = 0}}
	_, outputs := hand_netlist(inputs, {{1, 0, 300}})
	testing.expect_value(t, outputs[0].level, 1000)
	testing.expect_value(t, outputs[1].supplied, 300)
	testing.expect_value(t, outputs[0].supplied, 700)
	testing.expect_value(t, outputs[1].flow, 300)
	free_all(context.temp_allocator)
}

@(test)
test_stores_discharge_last_and_charge_from_what_is_left :: proc(t: ^testing.T) {
	generator := Node_Input {
		offer = 1000,
	}
	store := Node_Input {
		offer       = 500,
		charge_room = 500,
		order       = 10,
		store       = true,
	}
	beside := []Edge{{1, 0, UNLIMITED_CAPACITY}, {2, 0, UNLIMITED_CAPACITY}}
	// Demand below the generator's offer: the store charges the 400 J
	// left, below its room, and supplies nothing.
	_, below := hand_netlist({generator, {demand = 600}, store}, beside)
	testing.expect_value(t, below[1].delivered, 600)
	testing.expect_value(t, below[2].supplied, 0)
	testing.expect_value(t, below[2].charged, 400)
	testing.expect_value(t, below[0].supplied, 1000)
	// Demand above it: the store supplies the shortfall and charges
	// nothing.
	_, above := hand_netlist({generator, {demand = 1300}, store}, beside)
	testing.expect_value(t, above[1].delivered, 1300)
	testing.expect_value(t, above[2].supplied, 300)
	testing.expect_value(t, above[2].charged, 0)
	// A 100 J edge to the store, already carrying the consumer's 60 J
	// behind it: 40 J left for the charge.
	_, behind := hand_netlist({generator, store, {demand = 60}}, {{1, 0, 100}, {2, 1, UNLIMITED_CAPACITY}})
	testing.expect_value(t, behind[2].delivered, 60)
	testing.expect_value(t, behind[1].supplied, 0)
	testing.expect_value(t, behind[1].charged, 40)
	testing.expect_value(t, behind[1].flow, -100)
	testing.expect_value(t, behind[0].supplied, 100)
	free_all(context.temp_allocator)
}

// The output feasible and the solver's sorted consumer levels equal to the
// brute force reference's; returns the reference's.
expect_feasible_and_as_the_reference :: proc(t: ^testing.T, topology: Topology, inputs: []Node_Input, outputs: []Node_Output, loc := #caller_location) -> []u32 {
	expect_feasible_output(t, topology, inputs, outputs, 0)
	levels := make([]u32, len(outputs), context.temp_allocator)
	for output, node in outputs {
		levels[node] = output.level
	}
	solved := consumer_levels_sorted(inputs, levels)
	best, found := brute_force_levels(topology, inputs)
	testing.expectf(t, found && slice.equal(best, solved), "the solver's levels %v, the reference's %v", solved, best, loc = loc)
	return best
}

// 0373's review: node 0 offers 1,000,000 J, node 1 is the middle, node 2 a
// junction, nodes 3 on the consumers; edges (1, 0, 5000), (2, 1, 5000),
// (k, 2, unlimited).
feeder_netlist :: proc(middle_offer, middle_demand: i64, consumer_count: int, consumer_demand: i64) -> Test_Netlist {
	count := 3 + consumer_count
	inputs := make([]Node_Input, count, context.temp_allocator)
	inputs[0].offer = 1_000_000
	inputs[1] = {offer = middle_offer, demand = middle_demand}
	edges := make([]Edge, count - 1, context.temp_allocator)
	edges[0], edges[1] = {1, 0, 5000}, {2, 1, 5000}
	for consumer in 3 ..< count {
		inputs[consumer].demand = consumer_demand
		edges[consumer - 1] = {u32(consumer), 2, UNLIMITED_CAPACITY}
	}
	return {count, edges, inputs}
}

@(test)
test_a_poorer_branch_charges_its_feeder_what_it_takes :: proc(t: ^testing.T) {
	netlist := feeder_netlist(90, 100, 7, 1001)
	topology, outputs := solve_test_netlist(netlist)
	testing.expect_value(t, outputs[1].level, 990)
	testing.expect_value(t, outputs[1].delivered, 99)
	testing.expect_value(t, outputs[1].supplied, 90)
	testing.expect_value(t, outputs[1].flow, -5000)
	for consumer in 3 ..< netlist.node_count {
		testing.expect_value(t, outputs[consumer].level, 713)
		testing.expect_value(t, outputs[consumer].delivered, 713)
	}
	testing.expect_value(t, outputs[2].flow, -4991)
	testing.expect_value(t, outputs[0].supplied, 5000)
	best := expect_feasible_and_as_the_reference(t, topology, netlist.inputs, outputs)
	testing.expect_value(t, best[len(best) - 1], 990)
	free_all(context.temp_allocator)
}

@(test)
test_a_small_feeder_reaches_full_power_beside_an_overloaded_branch :: proc(t: ^testing.T) {
	// The item's 13 kW machine and 12 kW generator on a light cable.
	netlist := feeder_netlist(200, 216, 40, 216)
	topology, outputs := solve_test_netlist(netlist)
	testing.expect_value(t, outputs[1].level, 1000)
	testing.expect_value(t, outputs[1].delivered, 216)
	for consumer in 3 ..< netlist.node_count {
		testing.expect_value(t, outputs[consumer].level, 578)
		testing.expect_value(t, outputs[consumer].delivered, 124)
	}
	testing.expect_value(t, outputs[2].flow, -4960)
	testing.expect_value(t, outputs[1].supplied, 176)
	testing.expect_value(t, outputs[0].supplied, 5000)
	testing.expect_value(t, outputs[1].flow, -5000)
	best := expect_feasible_and_as_the_reference(t, topology, netlist.inputs, outputs)
	testing.expect_value(t, best[len(best) - 1], 1000)
	free_all(context.temp_allocator)
}

@(test)
test_a_poorer_branch_keeps_a_surplus_it_cannot_send :: proc(t: ^testing.T) {
	inputs := []Node_Input{{offer = 9, demand = 10}, {offer = 2, demand = 4000}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 1}})
	testing.expect_value(t, outputs[1].level, 0)
	testing.expect_value(t, outputs[1].supplied, 0)
	testing.expect_value(t, outputs[1].flow, 0)
	testing.expect_value(t, outputs[0].level, 900)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_richer_branch_keeps_what_its_poorer_parent_leaves :: proc(t: ^testing.T) {
	// Step 0's seed 6: the region of nodes 0, 1 and 3 takes 4011 of 4013 J.
	inputs := []Node_Input{{demand = 3000}, {demand = 2000, offer = 1427}, {demand = 3000, offer = 5093, order = 1}, {demand = 2000}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 5838}, {2, 1, 2586}, {3, 0, 1887}})
	for node in ([]int{0, 1, 3}) {
		testing.expect_value(t, outputs[node].level, 573)
	}
	testing.expect_value(t, outputs[2].level, 836)
	testing.expect_value(t, outputs[2].delivered, 2508)
	testing.expect_value(t, outputs[2].supplied, 5092)
	testing.expect_value(t, outputs[2].flow, 2584)
	testing.expect_value(t, outputs[1].supplied, 1427)
	testing.expect_value(t, outputs[1].flow, 2865)
	testing.expect_value(t, outputs[3].flow, -1146)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_feeder_behind_two_cables_keeps_the_slack :: proc(t: ^testing.T) {
	// Step 0's seed 153: the region of nodes 0, 1 and 3 leaves 7 J.
	inputs := []Node_Input{{demand = 3000, offer = 2501}, {demand = 3000}, {demand = 1000, offer = 2908, order = 2}, {demand = 4000, offer = 2617}}
	topology, outputs := hand_netlist(inputs, {{3, 0, 1001}, {1, 3, 1001}, {2, 1, 1999}})
	for node in ([]int{0, 1, 3}) {
		testing.expect_value(t, outputs[node].level, 711)
	}
	testing.expect_value(t, outputs[2].level, 916)
	testing.expect_value(t, outputs[2].delivered, 916)
	testing.expect_value(t, outputs[2].supplied, 2908)
	testing.expect_value(t, outputs[2].flow, 1992)
	testing.expect_value(t, outputs[1].flow, -141)
	testing.expect_value(t, outputs[3].flow, -368)
	testing.expect_value(t, outputs[0].supplied, 2501)
	testing.expect_value(t, outputs[3].supplied, 2617)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_feeder_keeps_what_its_parent_cannot_use :: proc(t: ^testing.T) {
	// Step 0's seed 488: 1 J reaches node 0, whose level costs 4 J.
	inputs := []Node_Input{{demand = 4000}, {demand = 4000, offer = 2567, order = 2}, {demand = 2000, offer = 3502, order = 2}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 1}, {2, 1, 1397}})
	testing.expect_value(t, outputs[0].level, 0)
	testing.expect_value(t, outputs[1].level, 991)
	testing.expect_value(t, outputs[1].delivered, 3964)
	testing.expect_value(t, outputs[1].supplied, 2567)
	testing.expect_value(t, outputs[1].flow, 0)
	testing.expect_value(t, outputs[2].level, 1000)
	testing.expect_value(t, outputs[2].delivered, 2000)
	testing.expect_value(t, outputs[2].supplied, 3397)
	testing.expect_value(t, outputs[2].flow, 1397)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_the_slack_raises_the_poorest_feeder_first :: proc(t: ^testing.T) {
	// Node 0 at 400 keeps 8 J; both feeders start at 800, their levels
	// costing 1 J and 2 J: node 1, node 2, node 1, node 2, node 1, then
	// node 2's 2 J no longer fit and node 1 takes the last joule.
	inputs := []Node_Input{{demand = 10000}, {demand = 1000, offer = 2805}, {demand = 2000, offer = 3603}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 2005}, {2, 0, 2003}})
	testing.expect_value(t, outputs[0].level, 400)
	testing.expect_value(t, outputs[1].level, 804)
	testing.expect_value(t, outputs[1].flow, 2001)
	testing.expect_value(t, outputs[2].level, 802)
	testing.expect_value(t, outputs[2].flow, 1999)
	testing.expect_value(t, outputs[1].supplied, 2805)
	testing.expect_value(t, outputs[2].supplied, 3603)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_return_passes_only_cables_with_room :: proc(t: ^testing.T) {
	// The root's region, nodes 0 and 1, at 400 with 5 J of slack; node 2's
	// level 501 costs 1 J and node 1's cable has 1 J of room, so node 2
	// rises once.
	inputs := []Node_Input{{demand = 6000, offer = 3005}, {demand = 4000}, {demand = 1000, offer = 1500}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 601}, {2, 1, 1000}})
	testing.expect_value(t, outputs[0].level, 400)
	testing.expect_value(t, outputs[1].level, 400)
	testing.expect_value(t, outputs[2].level, 501)
	testing.expect_value(t, outputs[2].delivered, 501)
	testing.expect_value(t, outputs[2].supplied, 1500)
	testing.expect_value(t, outputs[2].flow, 999)
	testing.expect_value(t, outputs[1].flow, -601)
	testing.expect_value(t, outputs[0].supplied, 3001)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_fed_region_leaves_its_room_to_a_poorer_feeder :: proc(t: ^testing.T) {
	// Node 1's room, 1 J, buys node 2's level 501 before node 0 climbs from
	// 501 to 502.
	inputs := []Node_Input{{demand = 1000, offer = 1003}, {demand = 2000}, {demand = 1000, offer = 1000}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 501}, {2, 1, 500}})
	testing.expect_value(t, outputs[0].level, 502)
	testing.expect_value(t, outputs[1].level, 500)
	testing.expect_value(t, outputs[2].level, 501)
	testing.expect_value(t, outputs[0].supplied, 1003)
	testing.expect_value(t, outputs[2].supplied, 1000)
	testing.expect_value(t, outputs[1].flow, -501)
	testing.expect_value(t, outputs[2].flow, 499)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_fed_region_leaves_its_room_to_a_poorer_parent :: proc(t: ^testing.T) {
	// Node 1's room buys node 2's level 701 only from node 0's 701 on;
	// node 0 stops at 600, so node 2 stays at 700.
	inputs := []Node_Input{{demand = 1000, offer = 1100}, {demand = 2000}, {demand = 1000, offer = 1200}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 501}, {2, 1, 500}})
	testing.expect_value(t, outputs[0].level, 600)
	testing.expect_value(t, outputs[1].level, 500)
	testing.expect_value(t, outputs[2].level, 700)
	testing.expect_value(t, outputs[0].supplied, 1100)
	testing.expect_value(t, outputs[2].supplied, 1200)
	testing.expect_value(t, outputs[1].flow, -500)
	testing.expect_value(t, outputs[2].flow, 500)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_the_pool_reaches_a_feeder_behind_a_feeder :: proc(t: ^testing.T) {
	// Node 1's 1 J surplus and 1 J of its cable's room reach node 3 through
	// node 2, which cannot use 2 J for its 3 J level.
	inputs := []Node_Input{{demand = 1000, offer = 2000}, {demand = 4000, offer = 2001}, {demand = 3000, offer = 2099}, {demand = 1000, offer = 1000}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 1}, {2, 1, 100}, {3, 2, 50}})
	testing.expect_value(t, outputs[3].level, 952)
	testing.expect_value(t, outputs[3].flow, 48)
	testing.expect_value(t, outputs[2].level, 683)
	testing.expect_value(t, outputs[2].flow, 98)
	testing.expect_value(t, outputs[1].level, 525)
	testing.expect_value(t, outputs[1].flow, -1)
	testing.expect_value(t, outputs[0].level, 1000)
	testing.expect_value(t, outputs[0].supplied, 1001)
	testing.expect_value(t, outputs[1].supplied, 2001)
	testing.expect_value(t, outputs[2].supplied, 2099)
	testing.expect_value(t, outputs[3].supplied, 1000)
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_cable_of_no_capacity_gives_no_ceiling :: proc(t: ^testing.T) {
	// Brute force seed 1822: nodes 4 and 2 share a 4162 J cable that never
	// limits, so one level, and the root's 1 J is level 0 for their 4000 J.
	// Node 1's 0 J cable joins nothing, so it pins node 2 at no level.
	inputs := []Node_Input{{demand = 2000, offer = 2579}, {demand = 3000}, {demand = 3000}, {demand = 2000, offer = 3304, order = 1}, {demand = 1000}}
	topology, outputs := hand_netlist(inputs, {{3, 0, 0}, {4, 0, 1}, {2, 4, 4162}, {1, 2, 0}})
	for level, node in ([5]u32{1000, 0, 0, 1000, 0}) {
		testing.expect_value(t, outputs[node].level, level)
	}
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

@(test)
test_a_feeder_at_its_parents_level_takes_power_in :: proc(t: ^testing.T) {
	// 0373's review: three twins below the root, each a feeder (nodes 1, 3,
	// 5) at the root's level 4 with a richer region behind it, from 309. Each
	// feeder's 2 J and 1 J less export buy its region level 310; the root's
	// 6 J left then buy nodes 2 and 4 level 311, their feeders taking 2 J
	// in, which the feeders' export alone could not carry.
	inputs := []Node_Input{{demand = 2000, offer = 11, order = 1}, {demand = 5000, offer = 17, order = 1}, {demand = 3000, offer = 934}, {demand = 5000, offer = 17, order = 1}, {demand = 3000, offer = 934}, {demand = 5000, offer = 17, order = 1}, {demand = 3000, offer = 934}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 2}, {2, 1, 7}, {3, 0, 2}, {4, 3, 7}, {5, 0, 2}, {6, 5, 7}})
	for level, node in ([7]u32{4, 4, 311, 4, 311, 4, 310}) {
		testing.expect_value(t, outputs[node].level, level)
	}
	for flow, node in ([7]i64{0, -2, 1, -2, 1, 1, 4}) {
		testing.expect_value(t, outputs[node].flow, flow)
	}
	for input, node in inputs {
		testing.expect_value(t, outputs[node].supplied, input.offer)
	}
	expect_feasible_and_as_the_reference(t, topology, inputs, outputs)
	free_all(context.temp_allocator)
}

// A store that discharges and charges 50 J (0389).
STORE_50 :: Node_Input {
	offer       = 50,
	charge_room = 50,
	order       = 10,
	store       = true,
}

@(test)
test_a_held_back_generator_leaves_the_store_its_charge :: proc(t: ^testing.T) {
	// 0383's review: node 1's 100 J behind a 10 J cable, node 2's 200 J and
	// a store beside the 120 J consumer. Node 2 gives the 110 J node 1
	// cannot and then the store's charge; the store gives nothing.
	inputs := []Node_Input{{}, {offer = 100}, {offer = 200}, STORE_50, {demand = 120}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 10}, {2, 0, UNLIMITED_CAPACITY}, {3, 0, UNLIMITED_CAPACITY}, {4, 0, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, topology, inputs, outputs, 0)
	testing.expect_value(t, outputs[4].delivered, 120)
	testing.expect_value(t, outputs[1].supplied, 10)
	testing.expect_value(t, outputs[1].flow, 10)
	testing.expect_value(t, outputs[2].supplied, 160)
	testing.expect_value(t, outputs[2].flow, 160)
	testing.expect_value(t, outputs[3].supplied, 0)
	testing.expect_value(t, outputs[3].charged, 50)
	testing.expect_value(t, outputs[3].flow, -50)
	// The 10 J cable as two of 5 J, bundled: the same outputs.
	bundled_topology, bundled := hand_netlist(inputs, {{1, 0, 5}, {0, 1, 5}, {2, 0, UNLIMITED_CAPACITY}, {3, 0, UNLIMITED_CAPACITY}, {4, 0, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, bundled_topology, inputs, bundled, 0)
	testing.expect(t, mem.compare(slice.to_bytes(outputs), slice.to_bytes(bundled)) == 0, "the bundled cable's outputs differ")
	// The item's: an engine on a light cable, a fuel generator and a lead
	// battery beside 5500 J asked.
	engine_inputs := []Node_Input{{}, {offer = 15000, order = 1}, {offer = 1000, order = 3}, {offer = 33, charge_room = 33, order = 10, store = true}, {demand = 5500}}
	engine_topology, engine := hand_netlist(engine_inputs, {{1, 0, 5000}, {2, 0, UNLIMITED_CAPACITY}, {3, 0, UNLIMITED_CAPACITY}, {4, 0, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, engine_topology, engine_inputs, engine, 0)
	testing.expect_value(t, engine[1].supplied, 5000)
	testing.expect_value(t, engine[2].supplied, 533)
	testing.expect_value(t, engine[3].supplied, 0)
	testing.expect_value(t, engine[3].charged, 33)
	free_all(context.temp_allocator)
}

@(test)
test_the_repair_serves_an_earlier_order_first :: proc(t: ^testing.T) {
	// Node 1's 100 J at order 0 behind a 10 J cable, 200 J at orders 1 and
	// 2 beside the 120 J consumer: order 1 gives what order 0 cannot.
	inputs := []Node_Input{{}, {offer = 100}, {offer = 200, order = 1}, {offer = 200, order = 2}, {demand = 120}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 10}, {2, 0, UNLIMITED_CAPACITY}, {3, 0, UNLIMITED_CAPACITY}, {4, 0, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, topology, inputs, outputs, 0)
	for supplied, node in ([3]i64{10, 110, 0}) {
		testing.expect_value(t, outputs[node + 1].supplied, supplied)
	}
	// Limited further up: junction 1 behind 40 J holds node 2's order 0
	// behind 30 J and node 3's order 1; node 4's order 2 and a store at the
	// root, which asks 120 J.
	further_inputs := []Node_Input{{demand = 120}, {}, {offer = 100}, {offer = 100, order = 1}, {offer = 200, order = 2}, STORE_50}
	further_topology, further := hand_netlist(further_inputs, {{1, 0, 40}, {2, 1, 30}, {3, 1, UNLIMITED_CAPACITY}, {4, 0, UNLIMITED_CAPACITY}, {5, 0, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, further_topology, further_inputs, further, 0)
	testing.expect_value(t, further[2].supplied, 30)
	testing.expect_value(t, further[3].supplied, 10)
	testing.expect_value(t, further[1].flow, 40)
	testing.expect_value(t, further[4].supplied, 130)
	testing.expect_value(t, further[5].supplied, 0)
	testing.expect_value(t, further[5].charged, 50)
	// Inside a subtree: junction 1 holds node 2's order 0 behind 10 J and
	// node 3's order 2, node 4's order 1 is at the root. The root's share
	// of junction 1 stays, its composition moves to the earlier order.
	inside_inputs := []Node_Input{{demand = 100}, {}, {offer = 100}, {offer = 100, order = 2}, {offer = 100, order = 1}}
	inside_topology, inside := hand_netlist(inside_inputs, {{1, 0, UNLIMITED_CAPACITY}, {2, 1, 10}, {3, 1, UNLIMITED_CAPACITY}, {4, 0, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, inside_topology, inside_inputs, inside, 0)
	testing.expect_value(t, inside[2].supplied, 10)
	testing.expect_value(t, inside[3].supplied, 0)
	testing.expect_value(t, inside[4].supplied, 90)
	testing.expect_value(t, inside[1].flow, 10)
	// Two trees: the store's case as nodes 0 to 4, the orders' as 5 to 9.
	two_inputs := []Node_Input{{}, {offer = 100}, {offer = 200}, STORE_50, {demand = 120}, {}, {offer = 100}, {offer = 200, order = 1}, {offer = 200, order = 2}, {demand = 120}}
	two_edges := []Edge {
		{1, 0, 10},
		{2, 0, UNLIMITED_CAPACITY},
		{3, 0, UNLIMITED_CAPACITY},
		{4, 0, UNLIMITED_CAPACITY},
		{6, 5, 10},
		{7, 5, UNLIMITED_CAPACITY},
		{8, 5, UNLIMITED_CAPACITY},
		{9, 5, UNLIMITED_CAPACITY},
	}
	two_topology, two := hand_netlist(two_inputs, two_edges)
	expect_feasible_output(t, two_topology, two_inputs, two, 0)
	testing.expect_value(t, two[2].supplied, 160)
	testing.expect_value(t, two[3].charged, 50)
	testing.expect_value(t, two[7].supplied, 110)
	testing.expect_value(t, two[8].supplied, 0)
	free_all(context.temp_allocator)
}

@(test)
test_a_store_gives_only_what_no_generator_can :: proc(t: ^testing.T) {
	// Junction 1 behind 10 J holds a store, node 3's 20 J at order 1 and a
	// 40 J consumer; the root offers 1000 J and asks 100 J. Node 3 gives
	// its 20 J, the store the 10 J the cable leaves short.
	inputs := []Node_Input{{demand = 100, offer = 1000}, {}, STORE_50, {offer = 20, order = 1}, {demand = 40}}
	topology, outputs := hand_netlist(inputs, {{1, 0, 10}, {2, 1, UNLIMITED_CAPACITY}, {3, 1, UNLIMITED_CAPACITY}, {4, 1, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, topology, inputs, outputs, 0)
	testing.expect_value(t, outputs[3].supplied, 20)
	testing.expect_value(t, outputs[2].supplied, 10)
	testing.expect_value(t, outputs[2].charged, 0)
	testing.expect_value(t, outputs[0].supplied, 110)
	testing.expect_value(t, outputs[1].flow, -10)
	// Without node 3 the store gives its forced 30 J.
	alone_inputs := []Node_Input{{demand = 100, offer = 1000}, {}, STORE_50, {demand = 40}}
	alone_topology, alone := hand_netlist(alone_inputs, {{1, 0, 10}, {2, 1, UNLIMITED_CAPACITY}, {3, 1, UNLIMITED_CAPACITY}})
	expect_feasible_output(t, alone_topology, alone_inputs, alone, 0)
	testing.expect_value(t, alone[2].supplied, 30)
	// Phase 2: node 1's order 0 behind 70 J, orders 1 and 2 at the root, a
	// store with 100 J of room and a 50 J consumer. The charge comes from
	// what order 0 has left first.
	charge_inputs := []Node_Input{{}, {offer = 100}, {offer = 200, order = 1}, {offer = 200, order = 2}, {charge_room = 100, order = 10, store = true}, {demand = 50}}
	charge_edges := []Edge{{1, 0, 70}, {2, 0, UNLIMITED_CAPACITY}, {3, 0, UNLIMITED_CAPACITY}, {4, 0, UNLIMITED_CAPACITY}, {5, 0, UNLIMITED_CAPACITY}}
	charge_topology, charge := hand_netlist(charge_inputs, charge_edges)
	expect_feasible_output(t, charge_topology, charge_inputs, charge, 0)
	testing.expect_value(t, charge[4].charged, 100)
	testing.expect_value(t, charge[1].supplied, 70)
	testing.expect_value(t, charge[2].supplied, 80)
	testing.expect_value(t, charge[3].supplied, 0)
	free_all(context.temp_allocator)
}

// The rule from a phase's results (0389): with the bounds given and,
// across an edge whose levels differ, flow only towards the poorer side
// (as bound_flows_by_levels), a giving position is misordered when a
// position of an earlier order with offer left reaches it over edges with
// room towards it. guarded counts the giving positions of an order above
// the least order with offer left, where the rule has something to say.
count_misordered :: proc(phase: Phase, lower, upper: []i64) -> (misordered, guarded: int) {
	count := len(phase.nodes)
	towards_lower, towards_upper := slice.clone(lower, context.temp_allocator), slice.clone(upper, context.temp_allocator)
	for position in 1 ..< count {
		level, parent_level := phase.level[position], phase.level[phase.parent[position]]
		if level < parent_level {
			towards_upper[position] = min(towards_upper[position], 0)
		} else if level > parent_level {
			towards_lower[position] = max(towards_lower[position], 0)
		}
	}
	giving: [256]bool
	least_with_offer_left := 256
	for position in 0 ..< count {
		if phase.supplied[position] > 0 {
			giving[phase.order[position]] = true
		}
		if phase.offer[position] > phase.supplied[position] {
			least_with_offer_left = min(least_with_offer_left, int(phase.order[position]))
		}
	}
	for position in 0 ..< count {
		guarded += int(phase.supplied[position] > 0 && int(phase.order[position]) > least_with_offer_left)
	}
	offsets, children := phase_children(phase.parent)
	reached := make([]bool, count, context.temp_allocator)
	for order in 0 ..< len(giving) {
		if !giving[order] {
			continue
		}
		reach_from_earlier_orders(phase, towards_lower, towards_upper, offsets, children, order, reached)
		for position in 0 ..< count {
			misordered += int(reached[position] && int(phase.order[position]) == order && phase.supplied[position] > 0)
		}
	}
	return
}

// The positions a position of an order below order with offer left
// reaches: to the parent while the edge walked from has room up, to a
// child while its edge has room down.
reach_from_earlier_orders :: proc(phase: Phase, lower, upper: []i64, offsets, children: []i32, order: int, reached: []bool) {
	stack := make([dynamic]i32, 0, len(reached), context.temp_allocator)
	for position in 0 ..< len(reached) {
		reached[position] = int(phase.order[position]) < order && phase.offer[position] > phase.supplied[position]
		if reached[position] {
			append(&stack, i32(position))
		}
	}
	for len(stack) > 0 {
		position := pop(&stack)
		parent := phase.parent[position]
		if position > 0 && !reached[parent] && upper[position] - phase.flow[position] > 0 {
			reached[parent] = true
			append(&stack, parent)
		}
		for child in children[offsets[position]:offsets[position + 1]] {
			if !reached[child] && phase.flow[child] - lower[child] > 0 {
				reached[child] = true
				append(&stack, child)
			}
		}
	}
}

// Solves the phase and counts its misorders against its bounds before
// the solve narrowed them.
phase_misorders :: proc(phase: ^Phase, by_node: []i32) -> (misordered, guarded: int) {
	lower, upper := slice.clone(phase.lower, context.temp_allocator), slice.clone(phase.upper, context.temp_allocator)
	solve_phase(phase, by_node, true, false)
	return count_misordered(phase^, lower, upper)
}

// Every tree's phases as solve_tree runs them, each counted
// (count_misordered): the outputs carry no level of phase 2, which the
// direction rule needs.
dispatch_misorders :: proc(netlist: Test_Netlist) -> (misordered, guarded: int) {
	topology := build_topology(netlist.node_count, netlist.edges, context.temp_allocator)
	outputs := make([]Node_Output, netlist.node_count, context.temp_allocator)
	for range in topology.trees {
		phase := make_phase(topology, topology.order[range.first:][:range.count])
		by_node := positions_by_node(phase.nodes)
		set_supply_phase(&phase, topology, netlist.inputs)
		supply_misordered, supply_guarded := phase_misorders(&phase, by_node)
		misordered, guarded = misordered + supply_misordered, guarded + supply_guarded
		for node, position in phase.nodes {
			outputs[node].supplied, outputs[node].flow = phase.supplied[position], phase.flow[position]
		}
		if set_charge_phase(&phase, topology, netlist.inputs, outputs) {
			charge_misordered, charge_guarded := phase_misorders(&phase, by_node)
			misordered, guarded = misordered + charge_misordered, guarded + charge_guarded
		}
	}
	return
}

// One set's totals for test_the_repair_follows_the_dispatch_order.
Misorder_Totals :: struct {
	set:                                    string,
	misordered, guarded, netlists_affected: int,
	first_seed:                             int,
}

add_netlist_misorders :: proc(totals: ^Misorder_Totals, netlist: Test_Netlist, seed: int) {
	misordered, guarded := dispatch_misorders(netlist)
	if misordered > 0 && totals.netlists_affected == 0 {
		totals.first_seed = seed
	}
	totals.netlists_affected += int(misordered > 0)
	totals.misordered += misordered
	totals.guarded += guarded
}

// The repair's rule (count_misordered) on every phase of the brute force,
// light cable and feasibility sets (0389).
@(test) // slow
test_the_repair_follows_the_dispatch_order :: proc(t: ^testing.T) {
	totals := [4]Misorder_Totals{{set = "brute force"}, {set = "light cable chains"}, {set = "light cable twins"}, {set = "feasibility"}}
	for seed in 0 ..< BRUTE_FORCE_NETLISTS {
		add_netlist_misorders(&totals[0], brute_force_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< LIGHT_CABLE_NETLISTS {
		add_netlist_misorders(&totals[1], light_cable_netlist(seed, false), seed)
		free_all(context.temp_allocator)
		add_netlist_misorders(&totals[2], light_cable_netlist(seed, true), seed)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		add_netlist_misorders(&totals[3], feasibility_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for set in totals {
		log.infof("%s: %d giving positions misordered in %d netlists, %d guarded", set.set, set.misordered, set.netlists_affected, set.guarded)
		testing.expectf(t, set.misordered == 0, "%s: %d giving positions misordered, the first at seed %d", set.set, set.misordered, set.first_seed)
		testing.expectf(t, set.guarded > 0, "%s: no phase where the rule has something to say", set.set)
	}
}

expect_solved_twice_alike :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) {
	_, first := solve_test_netlist(netlist)
	_, second := solve_test_netlist(netlist)
	testing.expectf(t, mem.compare(slice.to_bytes(first), slice.to_bytes(second)) == 0, "seed %d: two solves differ", seed)
}

@(test) // slow
test_solve_is_deterministic :: proc(t: ^testing.T) {
	for seed in 0 ..< BRUTE_FORCE_NETLISTS {
		expect_solved_twice_alike(t, brute_force_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		expect_solved_twice_alike(t, feasibility_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
}

// 2,000 consumers of 5000 J on 700 junction nodes in chains of 30 below
// one generator: node 0 the generator, 1 to 700 the junctions, the rest
// the consumers, each on junction (index mod 700) by a 5000 J edge. The
// chain edges carry 1,000,000 J but one, or 2000 J each. With generators,
// every tenth junction also has a node asking 1000 J and offering 1500 J
// behind a 600 J edge, after the consumers: feeders inside fed regions,
// so the greedies run (0373).
cost_netlist :: proc(saturated_everywhere, generators: bool) -> Test_Netlist {
	JUNCTIONS :: 700
	CONSUMERS :: 2000
	CHAIN :: 30
	GENERATOR_EVERY :: 10
	count := 1 + JUNCTIONS + CONSUMERS + (generators ? JUNCTIONS / GENERATOR_EVERY : 0)
	inputs := make([]Node_Input, count, context.temp_allocator)
	inputs[0].offer = 5000 * CONSUMERS
	edges := make([]Edge, count - 1, context.temp_allocator)
	for junction in 1 ..= JUNCTIONS {
		parent := (junction - 1) % CHAIN == 0 ? 0 : junction - 1
		capacity := saturated_everywhere ? 2000 : (junction == CHAIN / 2 ? 5000 : 1_000_000)
		edges[junction - 1] = {u32(junction), u32(parent), i64(capacity)}
	}
	for consumer in 0 ..< CONSUMERS {
		node := 1 + JUNCTIONS + consumer
		inputs[node].demand = 5000
		edges[JUNCTIONS + consumer] = {u32(node), u32(1 + consumer % JUNCTIONS), 5000}
	}
	for node in 1 + JUNCTIONS + CONSUMERS ..< count {
		junction := (node - JUNCTIONS - CONSUMERS) * GENERATOR_EVERY
		inputs[node] = {demand = 1000, offer = 1500}
		edges[node - 1] = {u32(node), u32(junction), 600}
	}
	return {count, edges, inputs}
}

// 0373's review, the solve's worst case: fed regions nested depth deep.
// Chain node 2i - 1 asks 1,000,000 J behind a cable from chain node
// 2i - 3 (node 0, offering 100,000,000,000 J, for the first) that carries
// its level 998 - i, every cable below it and 1 J; feeder node 2i asks
// 1000 J and offers 1999 - i J behind a 1000 J cable.
nested_chain_netlist :: proc(depth: int) -> Test_Netlist {
	count := 1 + 2 * depth
	inputs := make([]Node_Input, count, context.temp_allocator)
	inputs[0].offer = 100_000_000_000
	edges := make([]Edge, count - 1, context.temp_allocator)
	below: i64
	for step := depth; step >= 1; step -= 1 {
		level := i64(999 - step)
		chain, feeder := 2 * step - 1, 2 * step
		capacity := 1000 * (level - 1) + below + 1
		below = capacity
		inputs[chain].demand = 1_000_000
		inputs[feeder] = {demand = 1000, offer = 1000 + level}
		edges[chain - 1] = {u32(chain), u32(step == 1 ? 0 : chain - 2), capacity}
		edges[feeder - 1] = {u32(feeder), u32(chain), 1000}
	}
	return {count, edges, inputs}
}

// The pool as before 0390, each fed region's capped greedy rerun in every
// walk and every path walked: the reference of the replay and the memo.
plain_candidates_below :: proc(candidates: []i32, first, end: i32) -> []i32 {
	start, _ := slice.binary_search(candidates, first)
	stop, _ := slice.binary_search(candidates, end)
	return candidates[start:stop]
}

plain_settle_domain :: proc(phase: Phase, responses: []Response, pools: ^Pools) {
	for position in pools.domain {
		pools.net[position] = 0
	}
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
		below := plain_candidates_below(pools.candidates[:], position, pools.ends[position])
		plain_greedy(phase, responses, pools, below, i32(pools.level[parent]) - 1, position, nil)
		drawn := room - pools.source[position]
		pools.source[position] = max(own - drawn, 0)
		pools.net[position] = -max(drawn - own, 0)
		pools.net[parent] += pools.net[position]
	}
}

plain_reachable :: proc(phase: Phase, pools: Pools, candidate, bound: i32) -> i64 {
	sources: i64
	least := max(i64)
	for position := phase.parent[candidate]; position != bound; position = phase.parent[position] {
		sources += pools.source[position]
		room := pools.export[position]
		if pools.state[position] != .Feeder {
			room = min(pools.net[position], phase.upper[position]) - phase.lower[position] - pools.passed[position]
		} else if pools.level[position] == pools.level[phase.parent[position]] {
			room = pools.export[position] - phase.lower[position]
		}
		least = min(least, room + sources)
	}
	return min(least, pools.source[bound] + sources)
}

plain_greedy :: proc(phase: Phase, responses: []Response, pools: ^Pools, candidates: []i32, cap_level, bound: i32, fill: []i64) {
	for candidate in candidates {
		pools.done[candidate] = false
	}
	for {
		chosen, chosen_need := i32(-1), i64(0)
		for candidate in candidates {
			level := pools.level[candidate]
			if pools.done[candidate] || i32(level) + 1 > cap_level {
				continue
			}
			next := response_at(responses[candidate], int(level) + 1)
			need := pools.export[candidate] - next / LEVEL_FULL
			if next < 0 || need > plain_reachable(phase, pools^, candidate, bound) {
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
		}
	}
}

plain_fed_fill :: proc(phase: Phase, thresholds: []Level_Thresholds, responses: []Response, pools: ^Pools, position: i32, spare_tables: ^[dynamic][]i64) -> (own_net: i64, fill: []i64) {
	walk_domain(phase, thresholds, pools, position, u32(max(thresholds[position].poor_level, 0)))
	plain_settle_domain(phase, responses, pools)
	own_net = pools.net[position]
	if len(pools.candidates) == 0 {
		return
	}
	pools.source[position] = own_net - phase.lower[position]
	fill = take_table(spare_tables)
	slice.zero(fill)
	plain_greedy(phase, responses, pools, pools.candidates[:], LEVEL_FULL, position, fill)
	for level in 1 ..< len(fill) {
		fill[level] += fill[level - 1]
	}
	return
}

plain_region_levels :: proc(phase: ^Phase) {
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
			own_net, fill = plain_fed_fill(phase^, thresholds, responses, &pools, i32(position), &spare_tables)
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
	plain_settle_levels(phase^, thresholds, responses, &pools, root_level)
	copy(phase.level, pools.level)
	for position in 0 ..< count {
		phase.delivered[position] = delivered_at(phase.demand[position], phase.level[position])
	}
}

plain_settle_levels :: proc(phase: Phase, thresholds: []Level_Thresholds, responses: []Response, pools: ^Pools, root_level: u32) {
	for position in 0 ..< i32(len(phase.nodes)) {
		if position > 0 && pools.state[position] != .Feeder {
			continue
		}
		walk_domain(phase, thresholds, pools, position, position == 0 ? root_level : pools.level[position])
		plain_settle_domain(phase, responses, pools)
		pools.source[position] = pools.net[position] - (position > 0 ? pools.export[position] : 0)
		plain_greedy(phase, responses, pools, pools.candidates[:], LEVEL_FULL, 0, nil)
	}
}

NESTED_FED_NETLISTS :: 500

// Fed regions nested deep with feeders of several joules a level and
// rooms of many, so the recorded runs are long and the caps cut them
// (0390): below node 0, rich or not, a chain of 2 to 25 nodes asking 1000
// to 100,000 J, each behind a cable carrying some level of it give or take
// a few joules, with up to three feeders of 1000 to 9000 J on it. In the
// temp allocator.
nested_fed_netlist :: proc(seed: int) -> Test_Netlist {
	state: rand.Default_Random_State
	generator := seeded_generator(&state, seed)
	depth := int(pick(generator, 2, 25))
	inputs := make([dynamic]Node_Input, 1, 1 + 4 * depth, context.temp_allocator)
	edges := make([dynamic]Edge, 0, 4 * depth, context.temp_allocator)
	inputs[0].offer = rand.int_max(2, generator) == 0 ? 1_000_000_000 : pick(generator, 0, 50_000)
	previous := u32(0)
	for _ in 0 ..< depth {
		chain := u32(len(inputs))
		demand := 1000 * pick(generator, 1, 100)
		append(&inputs, Node_Input{demand = demand})
		capacity := max(demand * pick(generator, 1, 999) / 1000 + pick(generator, -30, 60), 0)
		append(&edges, Edge{chain, previous, capacity})
		for _ in 0 ..< pick(generator, 0, 3) {
			feeder_demand := 1000 * pick(generator, 1, 9)
			offer := feeder_demand * pick(generator, 100, 1500) / 1000 + pick(generator, 0, 50)
			append(&edges, Edge{u32(len(inputs)), chain, pick(generator, 0, offer + 10)})
			append(&inputs, Node_Input{demand = feeder_demand, offer = offer})
		}
		previous = chain
	}
	return {len(inputs), edges[:], inputs[:]}
}

// region_levels and plain_region_levels on the phase: 1 when their levels
// differ, named by seed, tree and phase.
replayed_levels_differ :: proc(t: ^testing.T, phase: ^Phase, seed, tree, phase_number: int) -> int {
	region_levels(phase)
	replayed := slice.clone(phase.level, context.temp_allocator)
	plain_region_levels(phase)
	same := slice.equal(replayed, phase.level)
	testing.expectf(t, same, "seed %d, tree %d, phase %d: the replayed pool's levels differ from the plain pool's", seed, tree, phase_number)
	return same ? 0 : 1
}

// Every tree of the netlist in phase 1 and, when the solve charges, in
// phase 2 with its uneven bounds: how many differ.
pools_differ :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) -> (differing: int) {
	topology, outputs := solve_test_netlist(netlist)
	for range, tree in topology.trees {
		phase := make_phase(topology, topology.order[range.first:][:range.count])
		set_supply_phase(&phase, topology, netlist.inputs)
		differing += replayed_levels_differ(t, &phase, seed, tree, 1)
		if set_charge_phase(&phase, topology, netlist.inputs, outputs) {
			differing += replayed_levels_differ(t, &phase, seed, tree, 2)
		}
	}
	return
}

@(test) // slow
test_replayed_pool_matches_the_plain_pool :: proc(t: ^testing.T) {
	pool_partial_replays = 0
	differing := 0
	for seed in 0 ..< BRUTE_FORCE_NETLISTS {
		differing += pools_differ(t, brute_force_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< LIGHT_CABLE_NETLISTS {
		for twins in ([2]bool{true, false}) {
			differing += pools_differ(t, light_cable_netlist(seed, twins), seed)
			free_all(context.temp_allocator)
		}
	}
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		differing += pools_differ(t, feasibility_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< NESTED_FED_NETLISTS {
		differing += pools_differ(t, nested_fed_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for depth in 1 ..= 40 {
		differing += pools_differ(t, nested_chain_netlist(depth), depth)
		free_all(context.temp_allocator)
	}
	for index in 0 ..< 3 {
		differing += pools_differ(t, cost_netlist(index > 0, index > 1), index)
		free_all(context.temp_allocator)
	}
	netlists := BRUTE_FORCE_NETLISTS + 2 * LIGHT_CABLE_NETLISTS + FEASIBILITY_NETLISTS + NESTED_FED_NETLISTS + 40 + 3
	log.infof("the replayed pool against the plain pool: %d netlists, %d differ, %d replays cut short", netlists, differing, pool_partial_replays)
	testing.expectf(t, differing == 0, "%d trees and phases differ", differing)
	testing.expect(t, pool_partial_replays > 0, "some replay is cut short")
}

// The design's bound for this shape, 5 n² / 4 visits over n nodes, and
// the model's counts: 7,620, 29,640, 116,880 and 464,160 at 81, 161, 321
// and 641 nodes. Before the replay 152,390, 2,037,980 and 29,824,760, and
// 445,146,000 visits of reachable alone at 641 (0390).
@(test)
test_nested_fed_regions_stay_within_the_visit_bound :: proc(t: ^testing.T) {
	for depth in ([4]int{40, 80, 160, 320}) {
		netlist := nested_chain_netlist(depth)
		pool_visits = 0
		solve_test_netlist(netlist)
		node_count := netlist.node_count
		log.infof("fed regions nested %d deep: %d pool visits over %d nodes", depth, pool_visits, node_count)
		testing.expectf(t, 4 * pool_visits <= 5 * node_count * node_count, "nested %d deep: %d visits over %d nodes", depth, pool_visits, node_count)
		free_all(context.temp_allocator)
	}
}

// Measured, not asserted (0355, question 3; 0373): microseconds per solve
// of cost_netlist with one saturated edge, with every chain edge
// saturated, and with generators behind cables as well, and of
// nested_chain_netlist at depths 80 and 160 (161 and 321 nodes). Run alone with
// ./build.sh test quick netlist.test_netlist_solve_cost -o:speed -define:NETLIST_SOLVE_COST=true
// or in ./build.sh nightly.
NETLIST_SOLVE_COST :: #config(NETLIST_SOLVE_COST, false)

when NETLIST_SOLVE_COST {
	@(test)
	test_netlist_solve_cost :: proc(t: ^testing.T) {
		REPEATS :: 20
		labels := [5]string{"one saturated edge", "every chain edge saturated", "every chain edge saturated, generators behind cables", "fed regions nested 80 deep", "fed regions nested 160 deep"}
		for label, index in labels {
			netlist := index < 3 ? cost_netlist(index > 0, index > 1) : nested_chain_netlist(index == 3 ? 80 : 160)
			topology := build_topology(netlist.node_count, netlist.edges, context.temp_allocator)
			outputs := make([]Node_Output, netlist.node_count, context.temp_allocator)
			begin := time.tick_now()
			for _ in 0 ..< REPEATS {
				solve(topology, netlist.inputs, outputs)
			}
			elapsed := time.tick_since(begin)
			browned_out := 0
			for output in outputs {
				browned_out += int(output.level < LEVEL_FULL)
			}
			testing.expect(t, browned_out > 0, "a cable saturates")
			log.infof("netlist solve cost, %s: %.0f microseconds a solve over %d nodes, %d below full", label, time.duration_microseconds(elapsed) / REPEATS, netlist.node_count, browned_out)
			free_all(context.temp_allocator)
		}
	}
}
