package netlist

// The rounding top-up (0356, doc/fluids.md, Fluid netlists), for the
// fluids only: levels are per mille and the litres a tick are few, so 21
// consumers of 20 L on one 20 L offer each get 20 * 47 / 1000 = 0 and a
// line would stall for good. After a phase's levels and dispatch the
// litres they left go out in one pass per dispatch order, lowest first,
// within the phase's bounds as they stand (the direction rule's on the
// slow path): bottom-up each subtree matches its own spare with its own
// shortfall and passes the rest across its edge; top-down each node serves
// its own shortfall, then its children's in pre-order, drawing on its own
// spare, then on its children's. On a tree that is the most that can move;
// what is left over goes to the first nodes of the walk. Levels do not
// change.

// Every dispatch order among the positions with an offer, ascending.
top_up_phase :: proc(phase: ^Phase) {
	present: [256]bool
	for offer, position in phase.offer {
		if offer > 0 {
			present[phase.order[position]] = true
		}
	}
	offsets, children := phase_children(phase.parent)
	for order in 0 ..< len(present) {
		if present[order] {
			top_up_order(phase, u8(order), offsets, children)
		}
	}
}

// One order's pass: spare is what the order's offers have left, short what
// every node still asks; sent what each subtree passes up its edge
// (negative: takes in), cross what the walk down moves across it.
top_up_order :: proc(phase: ^Phase, order: u8, offsets, children: []i32) {
	count := len(phase.nodes)
	spare := make([]i64, count, context.temp_allocator)
	short := make([]i64, count, context.temp_allocator)
	spare_total, short_total: i64
	for position in 0 ..< count {
		if phase.order[position] == order {
			spare[position] = phase.offer[position] - phase.supplied[position]
		}
		short[position] = phase.demand[position] - phase.delivered[position]
		spare_total += spare[position]
		short_total += short[position]
	}
	if spare_total == 0 || short_total == 0 {
		return
	}
	sent := top_up_sent(phase^, spare, short)
	cross := make([]i64, count, context.temp_allocator)
	for position in 0 ..< count {
		own_children := children[offsets[position]:offsets[position + 1]]
		top_up_node(phase, i32(position), own_children, spare[position], short[position], sent, cross)
	}
	for position in 1 ..< count {
		phase.flow[position] += cross[position]
	}
}

// Bottom-up: a node's spare less its shortfall plus what its children
// pass, clamped to the room its edge leaves either way.
top_up_sent :: proc(phase: Phase, spare, short: []i64) -> []i64 {
	count := len(phase.nodes)
	sent := make([]i64, count, context.temp_allocator)
	for position := count - 1; position >= 0; position -= 1 {
		sent[position] += spare[position] - short[position]
		if position == 0 {
			break
		}
		sent[position] = clamp(sent[position], phase.lower[position] - phase.flow[position], phase.upper[position] - phase.flow[position])
		sent[phase.parent[position]] += sent[position]
	}
	return sent
}

// One node top-down, its cross from its parent already set: when what
// comes to it covers what is asked of it, every taker is served in full
// and the takers' sum, less what the parent gives, is drawn from its own
// spare first, then from its exporting children in order; otherwise every
// giver gives in full and their sum, less what the parent draws, goes to
// its own shortfall first, then to its importing children in order.
top_up_node :: proc(phase: ^Phase, position: i32, own_children: []i32, spare, short: i64, sent, cross: []i64) {
	from_parent, to_parent := max(-cross[position], 0), max(cross[position], 0)
	give, take := spare + from_parent, short + to_parent
	for child in own_children {
		give += max(sent[child], 0)
		take += max(-sent[child], 0)
	}
	if give >= take {
		phase.delivered[position] += short
		drawn := min(take - from_parent, spare)
		phase.supplied[position] += drawn
		left := take - from_parent - drawn
		for child in own_children {
			if sent[child] < 0 {
				cross[child] = sent[child]
			} else if sent[child] > 0 {
				cross[child] = min(left, sent[child])
				left -= cross[child]
			}
		}
		return
	}
	phase.supplied[position] += spare
	given := min(give - to_parent, short)
	phase.delivered[position] += given
	left := give - to_parent - given
	for child in own_children {
		if sent[child] > 0 {
			cross[child] = sent[child]
		} else if sent[child] < 0 {
			cross[child] = -min(left, -sent[child])
			left += cross[child]
		}
	}
}
