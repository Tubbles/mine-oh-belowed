package netlist

// The power netlist (0355, doc/fluids.md, Power): nodes joined by edges
// that each carry at most a capacity of joules a tick. A netlist is a
// forest: an edge that would close a loop is a chord and carries nothing.
// This file builds the forest; solve.odin balances it. A leaf package: it
// knows no entity, machine or position, only node indices.

import "core:slice"

// A level is per mille of a consumer's demand (the game's POWER_FULL).
LEVEL_FULL :: 1000
RESPONSE_LEVELS :: LEVEL_FULL + 1
NO_NODE :: max(u32)
// Joules a tick; times LEVEL_FULL it stays far inside i64.
UNLIMITED_CAPACITY :: i64(1) << 40

Edge :: struct {
	first, second: u32,
	capacity:      i64,
}

// A range of Topology.order.
Tree :: struct {
	first, count: u32,
}

// Per node its parent (NO_NODE for a root) and the bundled capacity of
// the edge to it (0 for a root); order holds every node in pre-order,
// each tree contiguous, the trees by root ascending, every root its
// tree's lowest node; trees[k] is tree k's range of order. chords are
// the bundled edges that would close a loop, in sorted order.
Topology :: struct {
	parent:   []u32,
	capacity: []i64,
	order:    []u32,
	tree_of:  []u32,
	trees:    []Tree,
	chords:   []Edge,
}

// A node's tree neighbour and the capacity between them.
Neighbour :: struct {
	node:     u32,
	capacity: i64,
}

// The forest of the edges, the same for any order of the edges or of
// their ends: the edges are sorted by their ends, equal pairs bundled
// with their capacities added, and a union find in that order makes each
// a tree edge or a chord. Each tree is walked depth first from its lowest
// node, neighbours ascending.
build_topology :: proc(node_count: int, edges: []Edge, allocator := context.allocator) -> Topology {
	bundled := bundle_edges(edges)
	is_chord := find_chords(node_count, bundled)
	chord_count := 0
	for chord in is_chord {
		chord_count += int(chord)
	}
	topology := Topology {
		parent   = make([]u32, node_count, allocator),
		capacity = make([]i64, node_count, allocator),
		order    = make([]u32, node_count, allocator),
		tree_of  = make([]u32, node_count, allocator),
		trees    = make([]Tree, node_count - (len(bundled) - chord_count), allocator),
		chords   = make([]Edge, chord_count, allocator),
	}
	chord_index := 0
	for edge, index in bundled {
		if is_chord[index] {
			topology.chords[chord_index] = edge
			chord_index += 1
		}
	}
	offsets, neighbours := tree_neighbours(node_count, bundled, is_chord)
	walk_forest(&topology, offsets, neighbours)
	return topology
}

destroy_topology :: proc(topology: ^Topology, allocator := context.allocator) {
	delete(topology.parent, allocator)
	delete(topology.capacity, allocator)
	delete(topology.order, allocator)
	delete(topology.tree_of, allocator)
	delete(topology.trees, allocator)
	delete(topology.chords, allocator)
	topology^ = {}
}

edge_before :: proc(first, second: Edge) -> bool {
	if first.first != second.first {
		return first.first < second.first
	}
	return first.second < second.second
}

// Each edge with first below second and its capacity within 0 and
// UNLIMITED_CAPACITY, self edges dropped, sorted by the pair, equal pairs
// bundled. In the temp allocator.
bundle_edges :: proc(edges: []Edge) -> []Edge {
	normal := make([dynamic]Edge, 0, len(edges), context.temp_allocator)
	for edge in edges {
		if edge.first != edge.second {
			capacity := clamp(edge.capacity, 0, UNLIMITED_CAPACITY)
			append(&normal, Edge{min(edge.first, edge.second), max(edge.first, edge.second), capacity})
		}
	}
	slice.sort_by(normal[:], edge_before)
	bundled := make([dynamic]Edge, 0, len(normal), context.temp_allocator)
	for edge in normal {
		last := len(bundled) - 1
		if last >= 0 && bundled[last].first == edge.first && bundled[last].second == edge.second {
			bundled[last].capacity = min(bundled[last].capacity + edge.capacity, UNLIMITED_CAPACITY)
		} else {
			append(&bundled, edge)
		}
	}
	return bundled[:]
}

union_find_root :: proc(roots: []u32, node: u32) -> u32 {
	node := node
	for roots[node] != node {
		roots[node] = roots[roots[node]]
		node = roots[node]
	}
	return node
}

// Whether each bundled edge, in order, joins two nodes already joined.
find_chords :: proc(node_count: int, bundled: []Edge) -> []bool {
	roots := make([]u32, node_count, context.temp_allocator)
	for &root, index in roots {
		root = u32(index)
	}
	is_chord := make([]bool, len(bundled), context.temp_allocator)
	for edge, index in bundled {
		first, second := union_find_root(roots, edge.first), union_find_root(roots, edge.second)
		is_chord[index] = first == second
		roots[max(first, second)] = min(first, second)
	}
	return is_chord
}

// The tree edges as adjacency lists, neighbours[offsets[node]:offsets[node + 1]],
// each ascending: the sorted edges give a node first its lower neighbours
// (the edges where it is second) and then its higher ones.
tree_neighbours :: proc(node_count: int, bundled: []Edge, is_chord: []bool) -> (offsets: []u32, neighbours: []Neighbour) {
	offsets = make([]u32, node_count + 1, context.temp_allocator)
	for edge, index in bundled {
		if !is_chord[index] {
			offsets[edge.first + 1] += 1
			offsets[edge.second + 1] += 1
		}
	}
	for node in 0 ..< node_count {
		offsets[node + 1] += offsets[node]
	}
	neighbours = make([]Neighbour, offsets[node_count], context.temp_allocator)
	cursor := slice.clone(offsets[:node_count], context.temp_allocator)
	for edge, index in bundled {
		if !is_chord[index] {
			neighbours[cursor[edge.first]] = {edge.second, edge.capacity}
			cursor[edge.first] += 1
			neighbours[cursor[edge.second]] = {edge.first, edge.capacity}
			cursor[edge.second] += 1
		}
	}
	return
}

// Pre-order from each unvisited node ascending, the neighbours pushed
// descending so the lowest is walked first.
walk_forest :: proc(topology: ^Topology, offsets: []u32, neighbours: []Neighbour) {
	visited := make([]bool, len(topology.parent), context.temp_allocator)
	stack := make([dynamic]u32, 0, 64, context.temp_allocator)
	position, tree_count := u32(0), 0
	for root in 0 ..< u32(len(topology.parent)) {
		if visited[root] {
			continue
		}
		visited[root] = true
		topology.parent[root], topology.capacity[root] = NO_NODE, 0
		first := position
		append(&stack, root)
		for len(stack) > 0 {
			node := pop(&stack)
			topology.order[position] = node
			topology.tree_of[node] = u32(tree_count)
			position += 1
			for index := offsets[node + 1]; index > offsets[node]; index -= 1 {
				next := neighbours[index - 1]
				if !visited[next.node] {
					visited[next.node] = true
					topology.parent[next.node], topology.capacity[next.node] = node, next.capacity
					append(&stack, next.node)
				}
			}
		}
		topology.trees[tree_count] = Tree{first, position - first}
		tree_count += 1
	}
}

// Today's pooled satisfaction: what share of the demand the supply
// covers, in per mille; with no demand, full while anything is offered.
pooled_level :: proc(supply, demand: i64) -> u32 {
	if demand <= 0 {
		return supply > 0 ? LEVEL_FULL : 0
	}
	return u32(i128(clamp(supply, 0, demand)) * LEVEL_FULL / i128(demand))
}
