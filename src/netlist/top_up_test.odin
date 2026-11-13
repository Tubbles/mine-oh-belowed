package netlist

@(require) import "core:log"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:testing"
@(require) import "core:time"

// Work item 0356: the rounding top-up (top_up.odin).

TOP_UP_NETLISTS :: 3000

// 2 to 7 nodes, no stores, the litres of a fluid line: demands 0 to 9,
// half the nodes offering 0 to 9 at orders 0 to 2, capacities 0 to 9.
top_up_netlist :: proc(seed: int) -> Test_Netlist {
	state: rand.Default_Random_State
	generator := seeded_generator(&state, seed)
	count := int(pick(generator, 2, 7))
	edges := random_tree(generator, count)
	for &edge in edges {
		edge.capacity = pick(generator, 0, 9)
	}
	inputs := make([]Node_Input, count, context.temp_allocator)
	for &input in inputs {
		input.demand = pick(generator, 0, 9)
		if rand.int_max(2, generator) == 0 {
			input.offer, input.order = pick(generator, 0, 9), u8(pick(generator, 0, 2))
		}
	}
	return {count, edges, inputs}
}

solve_test_netlist_twice :: proc(netlist: Test_Netlist) -> (topology: Topology, without, with: []Node_Output) {
	topology = build_topology(netlist.node_count, netlist.edges, context.temp_allocator)
	without = make([]Node_Output, netlist.node_count, context.temp_allocator)
	with = make([]Node_Output, netlist.node_count, context.temp_allocator)
	solve(topology, netlist.inputs, without)
	solve(topology, netlist.inputs, with, top_up = true)
	return
}

Residual_Arc :: struct {
	to:   int,
	room: i64,
}

// The most the unsupplied offers can still deliver to the unmet demands,
// by augmenting paths from a super source over each offer less its supply
// to a super sink over each demand less its delivery, along each edge's
// room: its capacity less the flow up, its capacity plus the flow down,
// the capacity taken as 0 up from a child at a lower level than its parent
// and down into a child at a higher one (the direction rule). For
// netlists without stores.
reference_residual_flow :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output) -> i64 {
	count := len(inputs)
	source, sink := count, count + 1
	arcs := make([dynamic]Residual_Arc, 0, 6 * count, context.temp_allocator)
	arcs_of := make([][dynamic]int, count + 2, context.temp_allocator)
	for &list in arcs_of {
		list = make([dynamic]int, 0, 4, context.temp_allocator)
	}
	add_pair :: proc(arcs: ^[dynamic]Residual_Arc, arcs_of: [][dynamic]int, from, to: int, forward, back: i64) {
		append(&arcs_of[from], len(arcs))
		append(arcs, Residual_Arc{to, max(forward, 0)})
		append(&arcs_of[to], len(arcs))
		append(arcs, Residual_Arc{from, max(back, 0)})
	}
	for node in 0 ..< count {
		add_pair(&arcs, arcs_of, source, node, inputs[node].offer - outputs[node].supplied, 0)
		add_pair(&arcs, arcs_of, node, sink, inputs[node].demand - outputs[node].delivered, 0)
		parent := topology.parent[node]
		if parent == NO_NODE {
			continue
		}
		capacity := topology.capacity[node]
		upper := outputs[node].level < outputs[parent].level ? 0 : capacity
		lower := outputs[node].level > outputs[parent].level ? 0 : -capacity
		add_pair(&arcs, arcs_of, node, int(parent), upper - outputs[node].flow, outputs[node].flow - lower)
	}
	total: i64
	for {
		reached_by := augmenting_path(arcs[:], arcs_of, source, sink)
		if reached_by[sink] < 0 {
			return total
		}
		bottleneck := max(i64)
		for node := sink; node != source; node = arcs[reached_by[node] ~ 1].to {
			bottleneck = min(bottleneck, arcs[reached_by[node]].room)
		}
		for node := sink; node != source; node = arcs[reached_by[node] ~ 1].to {
			arcs[reached_by[node]].room -= bottleneck
			arcs[reached_by[node] ~ 1].room += bottleneck
		}
		total += bottleneck
	}
}

// Breadth first over the arcs with room: per node the arc that reached it,
// -1 for none.
augmenting_path :: proc(arcs: []Residual_Arc, arcs_of: [][dynamic]int, source, sink: int) -> []int {
	reached_by := make([]int, len(arcs_of), context.temp_allocator)
	slice.fill(reached_by, -1)
	queue := make([dynamic]int, 0, len(arcs_of), context.temp_allocator)
	append(&queue, source)
	for head := 0; head < len(queue) && reached_by[sink] < 0; head += 1 {
		for arc in arcs_of[queue[head]] {
			next := arcs[arc].to
			if arcs[arc].room > 0 && next != source && reached_by[next] < 0 {
				reached_by[next] = arc
				append(&queue, next)
			}
		}
	}
	return reached_by
}

output_totals :: proc(outputs: []Node_Output) -> (delivered, supplied: i64) {
	for output in outputs {
		delivered += output.delivered
		supplied += output.supplied
	}
	return
}

// The run with the top-up against the run without: equal levels, no node
// served or supplying less, the totals higher by the reference's residual
// flow, the output feasible.
top_up_reaches_the_reference :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) -> (holds: bool, residual: i64) {
	topology, without, with := solve_test_netlist_twice(netlist)
	residual = reference_residual_flow(topology, netlist.inputs, without)
	for output, node in with {
		if output.level != without[node].level || output.delivered < without[node].delivered || output.supplied < without[node].supplied {
			return false, residual
		}
	}
	delivered_without, supplied_without := output_totals(without)
	delivered_with, supplied_with := output_totals(with)
	if delivered_with - delivered_without != residual || supplied_with - supplied_without != residual {
		return false, residual
	}
	return expect_feasible_output(t, topology, netlist.inputs, with, seed), residual
}

@(test)
test_top_up_reaches_the_maximum_flow :: proc(t: ^testing.T) {
	differing := make([dynamic]int, context.allocator)
	defer delete(differing)
	moved := 0
	for seed in 0 ..< TOP_UP_NETLISTS {
		holds, residual := top_up_reaches_the_reference(t, top_up_netlist(seed), seed)
		if !holds {
			append(&differing, seed)
		}
		moved += int(residual > 0)
		free_all(context.temp_allocator)
	}
	testing.expectf(t, len(differing) == 0, "%d of %d netlists miss the maximum flow, seeds %v", len(differing), TOP_UP_NETLISTS, differing[:])
	testing.expect(t, moved > 0, "the rounding leaves litres to move")
}

// The paired run: where the run without leaves nothing that could move,
// the run with is the same byte for byte. Returns how many netlists left
// nothing.
expect_top_up_changes_nothing :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) -> int {
	topology, without, with := solve_test_netlist_twice(netlist)
	if reference_residual_flow(topology, netlist.inputs, without) != 0 {
		return 0
	}
	testing.expectf(t, mem.compare(slice.to_bytes(without), slice.to_bytes(with)) == 0, "seed %d: the top-up changed a netlist with nothing left", seed)
	return 1
}

@(test) // slow
test_top_up_changes_nothing_when_nothing_is_left :: proc(t: ^testing.T) {
	unchanged := 0
	for seed in 0 ..< BRUTE_FORCE_NETLISTS {
		unchanged += expect_top_up_changes_nothing(t, brute_force_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		unchanged += expect_top_up_changes_nothing(t, definition_netlist(seed), seed)
		free_all(context.temp_allocator)
	}
	testing.expect(t, unchanged > 0, "some netlist leaves nothing to move")
}

@(test) // slow
test_top_up_output_is_feasible :: proc(t: ^testing.T) {
	for seed in 0 ..< FEASIBILITY_NETLISTS {
		netlist := feasibility_netlist(seed)
		topology, without, with := solve_test_netlist_twice(netlist)
		expect_feasible_output(t, topology, netlist.inputs, with, seed)
		for output, node in with {
			testing.expectf(t, output.level == without[node].level, "seed %d: node %d's level %d, without the top-up %d", seed, node, output.level, without[node].level)
		}
		free_all(context.temp_allocator)
	}
}

@(test) // slow
test_top_up_is_deterministic :: proc(t: ^testing.T) {
	for seed in 0 ..< BRUTE_FORCE_NETLISTS + FEASIBILITY_NETLISTS {
		netlist := seed < BRUTE_FORCE_NETLISTS ? brute_force_netlist(seed) : feasibility_netlist(seed - BRUTE_FORCE_NETLISTS)
		_, _, first := solve_test_netlist_twice(netlist)
		_, _, second := solve_test_netlist_twice(netlist)
		testing.expectf(t, mem.compare(slice.to_bytes(first), slice.to_bytes(second)) == 0, "seed %d: two solves with the top-up differ", seed)
		free_all(context.temp_allocator)
	}
}

// Node 0 offers 20 on an edge of 20 to the junction, node 1; consumers of
// 20 each hang on the junction by edges of 20.
junction_line_netlist :: proc(consumer_count: int) -> Test_Netlist {
	count := 2 + consumer_count
	inputs := make([]Node_Input, count, context.temp_allocator)
	inputs[0].offer = 20
	edges := make([]Edge, count - 1, context.temp_allocator)
	edges[0] = {1, 0, 20}
	for consumer in 2 ..< count {
		inputs[consumer].demand = 20
		edges[consumer - 1] = {u32(consumer), 1, 20}
	}
	return {count, edges, inputs}
}

@(test)
test_top_up_feeds_more_consumers_than_litres :: proc(t: ^testing.T) {
	// 40 consumers: 20 * 25 / 1000 rounds to 0 for each.
	_, without, with := solve_test_netlist_twice(junction_line_netlist(40))
	for node in 2 ..< 42 {
		testing.expect_value(t, without[node].delivered, 0)
		testing.expect_value(t, with[node].delivered, node == 2 ? 20 : 0)
	}
	testing.expect_value(t, without[0].supplied, 0)
	testing.expect_value(t, with[0].supplied, 20)
	// Three: 6 each at 333, the 2 left to the first.
	_, _, three := solve_test_netlist_twice(junction_line_netlist(3))
	for delivered, index in ([3]i64{8, 6, 6}) {
		testing.expect_value(t, three[2 + index].delivered, delivered)
	}
	free_all(context.temp_allocator)
}

@(test)
test_top_up_fills_a_large_store :: proc(t: ^testing.T) {
	// 20 offered, a store with room for 25,000 behind an edge of 60.
	large := Test_Netlist{2, []Edge{{1, 0, 60}}, []Node_Input{{offer = 20}, {charge_room = 25_000, store = true}}}
	_, without, with := solve_test_netlist_twice(large)
	testing.expect_value(t, without[1].charged, 0)
	testing.expect_value(t, with[1].charged, 20)
	testing.expect_value(t, with[0].supplied, 20)
	// A store offering 0 beside a consumer asking 15: the store takes the 5
	// the consumer leaves.
	beside := Test_Netlist{3, []Edge{{1, 0, 60}, {2, 0, 60}}, []Node_Input{{offer = 20}, {demand = 15}, {charge_room = 25_000, store = true}}}
	_, _, shared := solve_test_netlist_twice(beside)
	testing.expect_value(t, shared[1].delivered, 15)
	testing.expect_value(t, shared[2].charged, 5)
	testing.expect_value(t, shared[0].supplied, 20)
	free_all(context.temp_allocator)
}

// 250 junctions, each with a producer offering 20 and eight consumers
// asking 20 on edges of 20, chained by edges of 20 through a store after
// every fifth: 50 stores offering 20 at order 1 with 40 of room.
fluid_cost_netlist :: proc() -> Test_Netlist {
	JUNCTIONS :: 250
	CONSUMERS :: 8
	STORE_EVERY :: 5
	count := JUNCTIONS * (2 + CONSUMERS) + JUNCTIONS / STORE_EVERY
	inputs := make([]Node_Input, count, context.temp_allocator)
	edges := make([dynamic]Edge, 0, count, context.temp_allocator)
	previous := -1
	next := 0
	for junction in 0 ..< JUNCTIONS {
		node := next
		next += 1
		if previous >= 0 {
			append(&edges, Edge{u32(node), u32(previous), 20})
		}
		inputs[next].offer = 20
		append(&edges, Edge{u32(next), u32(node), 20})
		next += 1
		for _ in 0 ..< CONSUMERS {
			inputs[next].demand = 20
			append(&edges, Edge{u32(next), u32(node), 20})
			next += 1
		}
		previous = node
		if junction % STORE_EVERY == STORE_EVERY - 1 {
			inputs[next] = {offer = 20, charge_room = 40, order = 1, store = true}
			append(&edges, Edge{u32(next), u32(node), 20})
			previous = next
			next += 1
		}
	}
	return {count, edges[:], inputs}
}

// Measured, not asserted (0356, decision 11): microseconds per solve with
// the top-up of fluid_cost_netlist. Run alone with
// ./build.sh test quick netlist.test_fluid_shaped_solve_cost -o:speed -define:NETLIST_FLUID_COST=true
// or in ./build.sh nightly.
NETLIST_FLUID_COST :: #config(NETLIST_FLUID_COST, false)

when NETLIST_FLUID_COST {
	@(test)
	test_fluid_shaped_solve_cost :: proc(t: ^testing.T) {
		REPEATS :: 20
		netlist := fluid_cost_netlist()
		topology := build_topology(netlist.node_count, netlist.edges, context.temp_allocator)
		outputs := make([]Node_Output, netlist.node_count, context.temp_allocator)
		begin := time.tick_now()
		for _ in 0 ..< REPEATS {
			solve(topology, netlist.inputs, outputs, top_up = true)
		}
		elapsed := time.tick_since(begin)
		delivered, _ := output_totals(outputs)
		testing.expect(t, delivered > 0, "litres move")
		log.infof("netlist solve cost, fluid shaped with the top-up: %.0f microseconds a solve over %d nodes, %d L delivered", time.duration_microseconds(elapsed) / REPEATS, netlist.node_count, delivered)
		free_all(context.temp_allocator)
	}
}
