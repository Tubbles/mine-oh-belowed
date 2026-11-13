package netlist

import "core:log"
import "core:math/rand"
import "core:slice"
import "core:testing"

// Work item 0369: each edge's limit after a solve.

LIMIT_NETLISTS :: 2000

// The record of the tree edge between two nodes: its child's.
edge_limit_between :: proc(topology: Topology, limits: []Edge_Limit, first, second: u32) -> Edge_Limit {
	if topology.parent[first] == second { return limits[first] }
	if topology.parent[second] == first { return limits[second] }
	return {}
}

Limit_Case :: struct {
	name:     string,
	inputs:   []Node_Input,
	edges:    []Edge,
	limiting: [][2]u32,
}

// Solves a hand case, measures its limits and expects exactly the listed
// edges to limit.
expect_limiting_edges :: proc(t: ^testing.T, limit_case: Limit_Case) -> (topology: Topology, outputs: []Node_Output, limits: []Edge_Limit) {
	topology, outputs = hand_netlist(limit_case.inputs, limit_case.edges)
	count := len(limit_case.inputs)
	reach := make([]Limit_Reach, count, context.temp_allocator)
	limits = make([]Edge_Limit, count, context.temp_allocator)
	measure_edge_limits(topology, limit_case.inputs, outputs, reach, limits)
	expected := make([]bool, count, context.temp_allocator)
	for pair in limit_case.limiting {
		child := topology.parent[pair[0]] == pair[1] ? pair[0] : pair[1]
		expected[child] = true
	}
	for node in 0 ..< u32(count) {
		testing.expectf(t, limits[node].limits == expected[node], "%s: the edge of node %d limits %v, expected %v (%v, flow %d)", limit_case.name, node, limits[node].limits, expected[node], limits[node], outputs[node].flow)
	}
	return
}

@(test)
test_edge_limits_on_hand_netlists :: proc(t: ^testing.T) {
	// Two short regions: raising 0-3 moves power from 2 to 3.
	for offer in ([]i64{3000, 3001, 2999}) {
		inputs := []Node_Input{{}, {offer = offer}, {demand = 3000}, {demand = 3000}}
		edges := []Edge{{0, 1, UNLIMITED_CAPACITY}, {0, 2, UNLIMITED_CAPACITY}, {0, 3, 1000}}
		topology, outputs, limits := expect_limiting_edges(t, {"two short regions", inputs, edges, {{0, 3}}})
		testing.expect_value(t, edge_limit_between(topology, limits, 0, 3).shortfall, 3000 - outputs[3].delivered)
	}
	// Generation shortage: an engine fills its own light cable.
	expect_limiting_edges(t, {"generation shortage", []Node_Input{{}, {offer = 5000}, {demand = 1666}, {demand = 1666}, {demand = 1666}, {demand = 1666}}, []Edge{{0, 1, 5000}, {0, 2, 1666}, {0, 3, 1666}, {0, 4, 1666}, {0, 5, 1666}}, {}})
	// Dispatch filled: the second generator's cable is full, the box's is
	// what holds the consumers back.
	dispatch_inputs := []Node_Input{{}, {offer = 15000}, {offer = 15000}, {}, {demand = 2500}, {demand = 2500}, {demand = 2500}, {demand = 2500}}
	dispatch_edges := []Edge{{0, 1, 15000}, {0, 2, 5000}, {0, 3, 5000}, {3, 4, 2500}, {3, 5, 2500}, {3, 6, 2500}, {3, 7, 2500}}
	expect_limiting_edges(t, {"dispatch filled", dispatch_inputs, dispatch_edges, {{0, 3}}})
	// A charging battery's intake is spare on the feeding side.
	battery_inputs := []Node_Input{{}, {offer = 10000}, {offer = 2000, charge_room = 5000, store = true, order = 10}, {demand = 500}}
	expect_limiting_edges(t, {"charging battery", battery_inputs, []Edge{{0, 1, 1000}, {0, 2, UNLIMITED_CAPACITY}, {0, 3, 100}}, {{0, 3}}})
	expect_limiting_edges(t, {"charging battery alone", battery_inputs, []Edge{{0, 1, 1000}, {0, 2, UNLIMITED_CAPACITY}, {0, 3, UNLIMITED_CAPACITY}}, {}})
	// Four recyclers behind a light cable, then a lamp more.
	recycler_inputs := []Node_Input{{}, {offer = 15000}, {}, {demand = 1666}, {demand = 1666}, {demand = 1666}, {demand = 1666}, {demand = 83}}
	recycler_edges := []Edge{{0, 1, UNLIMITED_CAPACITY}, {0, 2, 5000}, {2, 3, 1666}, {2, 4, 1666}, {2, 5, 1666}, {2, 6, 1666}, {2, 7, 83}}
	for count in ([]int{7, 8}) {
		topology, _, limits := expect_limiting_edges(t, {"four recyclers", recycler_inputs[:count], recycler_edges[:count - 1], {{0, 2}}})
		testing.expect(t, edge_limit_between(topology, limits, 0, 2).at_capacity, "the light cable to the recyclers is at capacity")
	}
	expect_limiting_edges(t, {"no demand box between", []Node_Input{{}, {offer = 10000}, {}, {demand = 5000}, {demand = 5000}}, []Edge{{0, 1, 4000}, {0, 2, 3000}, {2, 3, 1000}, {2, 4, 1000}}, {{2, 3}, {2, 4}}})
	// Rated cables in a brownout: every cable carries what it may, none
	// holds a consumer back.
	brownout_inputs := []Node_Input{{}, {demand = 99999}, {offer = 59990}, {offer = 50, store = true, order = 10}}
	topology, outputs, limits := expect_limiting_edges(t, {"rated cables in a brownout", brownout_inputs, []Edge{{0, 1, UNLIMITED_CAPACITY}, {0, 2, 59990}, {0, 3, 50}}, {}})
	testing.expect_value(t, abs(outputs[3].flow), 9)
	testing.expect(t, edge_limit_between(topology, limits, 0, 3).at_capacity, "the battery's cable is under a level of the brownout's region")
	expect_limiting_edges(t, {"a thicker cable in a brownout", brownout_inputs, []Edge{{0, 1, UNLIMITED_CAPACITY}, {0, 2, 59990}, {0, 3, 60}}, {}})
	// Full cables in series: an engine on a light cable into an empty box,
	// a light cable on to five assemblers (at 800, then a level's step under
	// the cable at 769), and three light links from the engine's box. Every
	// full cable of the series limits, the engine's own cable of 15000 J
	// does not.
	for demand in ([]i64{1250, 1300}) {
		series_inputs := []Node_Input{{}, {offer = 15000}, {}, {demand = demand}, {demand = demand}, {demand = demand}, {demand = demand}, {demand = demand}}
		series_edges := []Edge{{0, 1, 5000}, {0, 2, 5000}, {2, 3, demand}, {2, 4, demand}, {2, 5, demand}, {2, 6, demand}, {2, 7, demand}}
		expect_limiting_edges(t, {"two light cables in series", series_inputs, series_edges, {{0, 1}, {0, 2}}})
	}
	expect_limiting_edges(t, {"three light links", []Node_Input{{}, {offer = 15000}, {}, {}, {demand = 6666}}, []Edge{{0, 1, 15000}, {0, 2, 5000}, {2, 3, 5000}, {3, 4, 6666}}, {{0, 2}, {2, 3}}})
	// A generator filling its light cable first beside one with all its
	// offer left on an unlimited cable: raising the box's cable alone serves
	// the consumers, so the full generator cable does not limit.
	beside_inputs := []Node_Input{{}, {offer = 15000}, {offer = 15000, order = 1}, {}, {demand = 2500}, {demand = 2500}, {demand = 2500}, {demand = 2500}}
	beside_edges := []Edge{{0, 1, 5000}, {0, 2, UNLIMITED_CAPACITY}, {0, 3, 5000}, {3, 4, 2500}, {3, 5, 2500}, {3, 6, 2500}, {3, 7, 2500}}
	beside_topology, beside_outputs, beside_limits := expect_limiting_edges(t, {"a full generator cable beside a free one", beside_inputs, beside_edges, {{0, 3}}})
	testing.expect_value(t, beside_outputs[1].flow, 5000)
	testing.expect(t, edge_limit_between(beside_topology, beside_limits, 0, 1).at_capacity, "the first generator's cable is at capacity")
	// The known limit of doc/fluids.md: generator A (order 0) fills its light
	// cable 0-1 into box 0, a light link 0-3 reaches box 3, where generator B
	// (order 1) has 22,000 J left, and a full light cable 3-5 feeds 15,000 J
	// of consumers. 3-5 limits. 0-1 is marked too, wrongly: B's spare sits
	// inside what 0-1 feeds, beyond the fed end where it is measured. Nothing
	// is asserted about 0-1.
	known_inputs := []Node_Input{{}, {offer = 15000}, {demand = 3000}, {}, {offer = 25000, order = 1}, {}, {demand = 5000}, {demand = 5000}, {demand = 5000}}
	known_edges := []Edge{{0, 1, 5000}, {0, 2, 3000}, {0, 3, 5000}, {3, 4, 400000}, {3, 5, 5000}, {5, 6, 5000}, {5, 7, 5000}, {5, 8, 5000}}
	known_topology, known_outputs := hand_netlist(known_inputs, known_edges)
	known_reach := make([]Limit_Reach, len(known_inputs), context.temp_allocator)
	known_limits := make([]Edge_Limit, len(known_inputs), context.temp_allocator)
	measure_edge_limits(known_topology, known_inputs, known_outputs, known_reach, known_limits)
	testing.expect(t, edge_limit_between(known_topology, known_limits, 3, 5).limits, "the consumers' light cable does not limit")
	free_all(context.temp_allocator)
}

// Game shaped: boxes numbered first (the root is a box), box to box
// cables of light, heavy or trunk, sometimes doubled; machines on a box by
// a cable of their rating; consumers at their rating or idle; generators
// at their rating or less; now and then a battery.
game_shaped_netlist :: proc(seed: int) -> Test_Netlist {
	state: rand.Default_Random_State
	generator := seeded_generator(&state, seed)
	box_count := int(pick(generator, 1, 6))
	machine_count := int(pick(generator, 1, 16))
	count := box_count + machine_count
	edges := make([dynamic]Edge, 0, count * 2, context.temp_allocator)
	cable_items := [3]i64{5000, 50000, 400000}
	if box_count > 1 {
		for edge in random_tree(generator, box_count) {
			item := cable_items[rand.int_max(rand.int_max(3, generator) == 0 ? 3 : 2, generator)]
			append(&edges, Edge{edge.first, edge.second, item})
			if rand.int_max(6, generator) == 0 {
				append(&edges, Edge{edge.first, edge.second, cable_items[rand.int_max(2, generator)]})
			}
		}
	}
	inputs := make([]Node_Input, count, context.temp_allocator)
	consumer_ratings := [10]i64{83, 216, 766, 1000, 1250, 1500, 1666, 3333, 6666, 8333}
	generator_ratings := [4]i64{5000, 6666, 10000, 15000}
	for machine in 0 ..< machine_count {
		node := u32(box_count + machine)
		box := u32(rand.int_max(box_count, generator))
		rating: i64
		switch rand.int_max(10, generator) {
		case 0, 1, 2:
			rating = generator_ratings[rand.int_max(len(generator_ratings), generator)]
			inputs[node].offer = rand.int_max(2, generator) == 0 ? rating : pick(generator, 0, rating)
			inputs[node].order = u8(pick(generator, 0, 3))
		case 3:
			rating = rand.int_max(2, generator) == 0 ? 33 : 50
			inputs[node] = {offer = pick(generator, 0, rating), charge_room = pick(generator, 0, rating), store = true, order = 10}
		case:
			rating = consumer_ratings[rand.int_max(len(consumer_ratings), generator)]
			inputs[node].demand = rand.int_max(5, generator) == 0 ? 0 : rating
		}
		append(&edges, Edge{node, box, min(rating, cable_items[rand.int_max(2, generator)])})
	}
	return {count, edges[:], inputs}
}

// Chain shaped: 3 to 30 boxes, each joined to the one before by a light or
// a heavy cable, a third of the joins bundled with one or two cables more,
// one in twenty 0 J and one in twenty unlimited, one in twenty-five left
// out (a forest); up to two cables more close loops. Machines as in
// game_shaped_netlist, the generators on the first third of the boxes, and
// one netlist in ten without generators.
chain_shaped_netlist :: proc(seed: int) -> Test_Netlist {
	state: rand.Default_Random_State
	generator := seeded_generator(&state, seed)
	box_count := int(pick(generator, 3, 30))
	machine_count := int(pick(generator, 2, 40))
	count := box_count + machine_count
	edges := make([dynamic]Edge, 0, count * 3, context.temp_allocator)
	cable_items := [2]i64{5000, 50000}
	for box in 1 ..< box_count {
		if rand.int_max(25, generator) == 0 { continue }
		capacity := cable_items[rand.int_max(2, generator)]
		switch rand.int_max(20, generator) {
		case 0:
			capacity = 0
		case 1:
			capacity = UNLIMITED_CAPACITY
		}
		append(&edges, Edge{u32(box), u32(box - 1), capacity})
		bundled := rand.int_max(3, generator) == 0 ? int(pick(generator, 1, 2)) : 0
		for _ in 0 ..< bundled {
			append(&edges, Edge{u32(box), u32(box - 1), cable_items[rand.int_max(2, generator)]})
		}
	}
	for _ in 0 ..< int(pick(generator, 0, 2)) {
		append(&edges, Edge{u32(rand.int_max(box_count, generator)), u32(rand.int_max(box_count, generator)), cable_items[rand.int_max(2, generator)]})
	}
	inputs := make([]Node_Input, count, context.temp_allocator)
	consumer_ratings := [10]i64{83, 216, 766, 1000, 1250, 1500, 1666, 3333, 6666, 8333}
	generator_ratings := [4]i64{5000, 6666, 10000, 15000}
	without_generators := rand.int_max(10, generator) == 0
	for machine in 0 ..< machine_count {
		node := u32(box_count + machine)
		box := u32(rand.int_max(box_count, generator))
		kind := rand.int_max(10, generator)
		if without_generators && kind < 3 { kind = 5 }
		rating: i64
		switch kind {
		case 0, 1, 2:
			rating = generator_ratings[rand.int_max(len(generator_ratings), generator)]
			inputs[node].offer = rand.int_max(2, generator) == 0 ? rating : pick(generator, 0, rating)
			inputs[node].order = u8(pick(generator, 0, 3))
			box = u32(rand.int_max(max(box_count / 3, 1), generator))
		case 3:
			rating = rand.int_max(2, generator) == 0 ? 33 : 50
			inputs[node] = {offer = pick(generator, 0, rating), charge_room = pick(generator, 0, rating), store = true, order = 10}
		case:
			rating = consumer_ratings[rand.int_max(len(consumer_ratings), generator)]
			inputs[node].demand = rand.int_max(5, generator) == 0 ? 0 : rating
		}
		append(&edges, Edge{node, box, min(rating, cable_items[rand.int_max(2, generator)])})
	}
	return {count, edges[:], inputs}
}

// Solved again with the tree edges with capacity that raise says
// unlimited. In the temp allocator.
solve_with_edges_raised :: proc(topology: Topology, inputs: []Node_Input, raise: []bool) -> []Node_Output {
	open := topology
	open.capacity = slice.clone(topology.capacity, context.temp_allocator)
	for &capacity, node in open.capacity {
		if topology.parent[node] != NO_NODE && capacity > 0 && raise[node] {
			capacity = UNLIMITED_CAPACITY
		}
	}
	raised := make([]Node_Output, len(inputs), context.temp_allocator)
	solve(open, inputs, raised)
	return raised
}

// The nodes on the side the child's edge feeds: its subtree when the flow
// enters the child, else the rest of its tree. In the temp allocator.
fed_side_nodes :: proc(topology: Topology, outputs: []Node_Output, child: u32) -> []bool {
	inside := make([]bool, len(outputs), context.temp_allocator)
	for node in topology.order {
		parent := topology.parent[node]
		inside[node] = node == child || (parent != NO_NODE && inside[parent])
	}
	fed_is_child := outputs[child].flow < 0
	for &fed, node in inside {
		fed = topology.tree_of[node] == topology.tree_of[child] && fed == fed_is_child
	}
	return inside
}

// What the nodes of a side gain between two solves.
side_gain :: proc(side: []bool, outputs, raised: []Node_Output) -> (gain: i64) {
	for fed, node in side {
		if fed { gain += raised[node].delivered - outputs[node].delivered }
	}
	return
}

// The edges carrying power in series with the child's: on its fed side
// with the child's edge on their feeding side, or the other way round; an
// edge beside it, each on the other's fed side, competes for the same power
// and is left out. Edges not full yet are in, since raising the full ones
// fills them (a consumer's cable below its demand caps what a raised
// generator cable gains). The child's own edge is in. In the temp allocator.
edges_in_series :: proc(topology: Topology, outputs: []Node_Output, child: u32) -> []bool {
	series := make([]bool, len(outputs), context.temp_allocator)
	series[child] = true
	fed := fed_side_nodes(topology, outputs, child)
	for other in 0 ..< u32(len(outputs)) {
		if other == child || topology.parent[other] == NO_NODE || outputs[other].flow == 0 || topology.tree_of[other] != topology.tree_of[child] { continue }
		other_fed := fed_side_nodes(topology, outputs, other)
		other_on_fed := fed[other] && fed[topology.parent[other]]
		child_on_other_fed := other_fed[child] && other_fed[topology.parent[child]]
		child_on_other_feeding := !other_fed[child] && !other_fed[topology.parent[child]]
		other_on_feeding := !fed[other] && !fed[topology.parent[other]]
		series[other] = (other_on_fed && child_on_other_feeding) || (other_on_feeding && child_on_other_fed)
	}
	return series
}

// Per set of netlists: the edges with capacity and flow, the marks, the
// wrong marks (raising the mark's power path, the edges carrying power in
// series with it, gains its fed side 2 J or less more with the mark than
// without it), the trees with a consumer short that gain 10 J or more with
// every edge unlimited (starved), those without a mark (silent) and those
// whose marks are all wrong (misleading).
Limit_Counts :: struct {
	edges, marks, wrong, starved, silent, misleading: int,
}

// What raising the child's power path gains its fed side with the child's
// edge less what it gains without it.
path_gain_of_edge :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, child: u32) -> i64 {
	fed := fed_side_nodes(topology, outputs, child)
	path := edges_in_series(topology, outputs, child)
	with_edge := side_gain(fed, outputs, solve_with_edges_raised(topology, inputs, path))
	path[child] = false
	return with_edge - side_gain(fed, outputs, solve_with_edges_raised(topology, inputs, path))
}

count_edge_limits :: proc(netlist: Test_Netlist, label: string, seed: int, counts: ^Limit_Counts) {
	topology, outputs := solve_test_netlist(netlist)
	reach := make([]Limit_Reach, netlist.node_count, context.temp_allocator)
	limits := make([]Edge_Limit, netlist.node_count, context.temp_allocator)
	measure_edge_limits(topology, netlist.inputs, outputs, reach, limits)
	every_edge := make([]bool, netlist.node_count, context.temp_allocator)
	for &raise in every_edge { raise = true }
	opened := solve_with_edges_raised(topology, netlist.inputs, every_edge)
	marks_in_tree := make([]int, len(topology.trees), context.temp_allocator)
	right_in_tree := make([]int, len(topology.trees), context.temp_allocator)
	for node in topology.order {
		if topology.parent[node] == NO_NODE || topology.capacity[node] <= 0 || outputs[node].flow == 0 { continue }
		counts.edges += 1
		if !limits[node].limits { continue }
		counts.marks += 1
		tree := topology.tree_of[node]
		marks_in_tree[tree] += 1
		gain := path_gain_of_edge(topology, netlist.inputs, outputs, node)
		if gain > 2 {
			right_in_tree[tree] += 1
			continue
		}
		counts.wrong += 1
		if counts.wrong <= 5 { log.infof("edge limits, %s, wrong: seed %d, child %d, flow %d, capacity %d, %v, gain %d", label, seed, node, outputs[node].flow, topology.capacity[node], limits[node], gain) }
	}
	for tree, index in topology.trees {
		short, gain: i64
		for position in tree.first ..< tree.first + tree.count {
			node := topology.order[position]
			short += netlist.inputs[node].demand - outputs[node].delivered
			gain += opened[node].delivered - outputs[node].delivered
		}
		if short <= 0 || gain < 10 { continue }
		counts.starved += 1
		counts.silent += marks_in_tree[index] == 0 ? 1 : 0
		if marks_in_tree[index] > 0 && right_in_tree[index] == 0 {
			counts.misleading += 1
			log.infof("edge limits, %s, misleading: seed %d, tree of node %d", label, seed, topology.order[tree.first])
		}
	}
}

@(test) // slow
test_edge_limits_match_raising_the_cables :: proc(t: ^testing.T) {
	Limit_Set :: struct {
		label:                    string,
		netlist:                  proc(seed: int) -> Test_Netlist,
		wrong_per_mille_of_marks: int,
	}
	sets := [2]Limit_Set{{"game", game_shaped_netlist, 10}, {"chain", chain_shaped_netlist, 25}}
	for set in sets {
		counts: Limit_Counts
		for seed in 0 ..< LIMIT_NETLISTS {
			count_edge_limits(set.netlist(seed), set.label, seed, &counts)
			free_all(context.temp_allocator)
		}
		log.infof("edge limits, %s, %d netlists: %d edges, %d marks, %d wrong; %d starved trees, %d silent, %d misleading", set.label, LIMIT_NETLISTS, counts.edges, counts.marks, counts.wrong, counts.starved, counts.silent, counts.misleading)
		testing.expectf(t, counts.wrong * 1000 <= counts.marks * set.wrong_per_mille_of_marks, "%s: %d wrong of %d marks", set.label, counts.wrong, counts.marks)
		testing.expectf(t, counts.silent == 0, "%s: %d silent of %d starved trees", set.label, counts.silent, counts.starved)
		testing.expectf(t, counts.misleading == 0, "%s: %d starved trees whose marks are all wrong", set.label, counts.misleading)
		testing.expectf(t, counts.marks * 100 >= counts.edges, "%s: %d marks of %d edges", set.label, counts.marks, counts.edges)
	}
}
