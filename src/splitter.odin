package game

// Splitters (doc/logistics.md): an entity one block along its flow and two
// across it, with a direction like belts (Entity_Common.rotation). Each
// half stands where a belt block would. A belt facing into a half from
// behind ends its line there (a Splitter line end), and each half is a one
// block line of its own, the half's output line, that continues into
// whatever stands in front of it like a belt would.
//
// Per tick the splitter runs after its output lines and before its input
// lines (compute_belt_line_order). It moves the front item of each input
// lane that reaches the entry edge this tick into an output half on the
// same lane, chosen by the filter, the output priority or round robin per
// item and lane, skipping a half with nothing in front of it or no room at
// its back. Inputs take turns (or the priority input goes first). An item
// that arrives n units past the edge lands n units into the half, so
// crossing costs no distance and the half counts as one block of line.

Splitter_Side :: enum u8 {
	Left,
	Right,
}

Splitter_Priority :: enum u8 {
	None,
	Left,
	Right,
}

Splitter :: struct {
	using common:    Entity_Common,
	input_priority:  Splitter_Priority,
	output_priority: Splitter_Priority,
	// NO_ITEM for none. The filter item only goes to filter_side, every
	// other item only to the other side.
	filter:          Item_Id,
	filter_side:     Splitter_Side,
	// Round robin, per lane: the output tried first and the input served
	// first.
	next_output:     [Belt_Lane]Splitter_Side,
	next_input:      [Belt_Lane]Splitter_Side,
	// Set by rebuild_belt_lines: the line feeding each half (-1 for none)
	// and each half's own output line.
	input_lines:     [Splitter_Side]i32,
	output_lines:    [Splitter_Side]i32,
}

make_splitter :: proc(common: Entity_Common) -> Splitter {
	return Splitter{common = common, filter = NO_ITEM, input_lines = {.Left = -1, .Right = -1}, output_lines = {.Left = -1, .Right = -1}}
}

other_side :: proc(side: Splitter_Side) -> Splitter_Side {
	return side == .Left ? .Right : .Left
}

priority_side :: proc(priority: Splitter_Priority) -> Splitter_Side {
	return priority == .Right ? .Right : .Left
}

// The unrotated footprint has the flow along x and the halves along z,
// left (z 0) and right (z 1) of the direction.
splitter_half_cell :: proc(origin: World_Coordinate, rotation: u8, side: Splitter_Side) -> World_Coordinate {
	offset := rotate_footprint_cell({0, side == .Right ? 1 : 0}, 1, 2, rotation)
	return origin + {offset.x, 0, offset.y}
}

// The minimum corner of a splitter whose left half is at left_cell.
splitter_origin :: proc(left_cell: World_Coordinate, direction: u8) -> World_Coordinate {
	right_cell := left_cell + belt_direction_offset(turn_right(direction))
	return {min(left_cell.x, right_cell.x), left_cell.y, min(left_cell.z, right_cell.z)}
}

splitter_side_at :: proc(splitter: Splitter, cell: World_Coordinate) -> Splitter_Side {
	return splitter_half_cell(splitter.origin, splitter.rotation, .Right) == cell ? .Right : .Left
}

splitter_at :: proc(entities: ^Entities, cell: World_Coordinate, frame := BLOCK_FRAME) -> ^Splitter {
	handle := entity_at(entities, cell, frame)
	if handle.kind != .Splitter {
		return nil
	}
	return pool_get(&entities.splitters, handle)
}

// A flat belt standing in for one half, so the belt graph procedures work
// out where the half's items go and where its items are drawn.
splitter_half_belt :: proc(splitter: Splitter, side: Splitter_Side) -> Belt {
	common := splitter.common
	common.origin = splitter_half_cell(splitter.origin, splitter.rotation, side)
	common.size = {1, 1, 1}
	return make_belt(common, .Flat)
}

// A belt whose items come out into a splitter half: from behind it feeds
// that half, from anywhere else it ends there. found is false when no
// splitter stands at the belt's output cell.
splitter_input_link :: proc(entities: ^Entities, belt: Belt) -> (link: Belt_Link, found: bool) {
	if belt_shape_is_lift(belt.shape) && lift_column_next(entities, belt) != nil {
		return {}, false
	}
	cell := belt_output_cell(belt)
	splitter := splitter_at(entities, cell, belt.frame)
	if splitter == nil {
		return {}, false
	}
	if splitter.rotation != belt.rotation {
		return {target = splitter.handle}, true
	}
	return {target = splitter.handle, connection = .Into_Splitter, side = splitter_side_at(splitter^, cell)}, true
}

// Routing.

// The outputs an item may take, in the order they are tried.
splitter_candidates :: proc(splitter: Splitter, item: Item_Id, lane: Belt_Lane) -> (candidates: [2]Splitter_Side, count: int) {
	if splitter.filter != NO_ITEM {
		side := item == splitter.filter ? splitter.filter_side : other_side(splitter.filter_side)
		return {side, side}, 1
	}
	first := splitter.next_output[lane]
	if splitter.output_priority != .None {
		first = priority_side(splitter.output_priority)
	}
	return {first, other_side(first)}, 2
}

// A half with nothing in front of it takes no items.
splitter_output_connected :: proc(network: Belt_Network, splitter: Splitter, side: Splitter_Side) -> bool {
	line := splitter.output_lines[side]
	return line >= 0 && int(line) < len(network.lines) && network.lines[line].end.kind != .Dead_End
}

// Where an item arriving `arrival` units into an output lane lands: a
// spacing behind the lane's back item at most, like a straight hand off.
// room is false when not even the start of the lane is free.
output_landing :: proc(items: []Lane_Item, arrival: i32) -> (position: i32, room: bool) {
	if len(items) == 0 {
		return arrival, true
	}
	limit := items[0].position - BELT_ITEM_SPACING
	return min(arrival, limit), limit >= 0
}

splitter_choose_output :: proc(network: Belt_Network, splitter: Splitter, item: Item_Id, lane: Belt_Lane, arrival: i32) -> (side: Splitter_Side, position: i32, found: bool) {
	candidates, count := splitter_candidates(splitter, item, lane)
	for candidate in candidates[:count] {
		if !splitter_output_connected(network, splitter, candidate) {
			continue
		}
		landing, room := output_landing(network.lines[splitter.output_lines[candidate]].lanes[lane][:], arrival)
		if room {
			return candidate, landing, true
		}
	}
	return .Left, 0, false
}

// How far the front item of an input lane may go when it did not cross:
// up to the edge, or a spacing behind the back item of the output it
// waits for (the one that frees first), or like a dead end when no output
// it may take is connected.
splitter_input_front_limit :: proc(network: Belt_Network, splitter: Splitter, item: Item_Id, lane: Belt_Lane, length: i32) -> i32 {
	candidates, count := splitter_candidates(splitter, item, lane)
	limit := length - BELT_END_MARGIN
	connected := false
	for candidate in candidates[:count] {
		if !splitter_output_connected(network, splitter, candidate) {
			continue
		}
		items := network.lines[splitter.output_lines[candidate]].lanes[lane][:]
		reach := length - 1
		if len(items) > 0 {
			reach = min(reach, length + items[0].position - BELT_ITEM_SPACING)
		}
		limit = connected ? max(limit, reach) : reach
		connected = true
	}
	return limit
}

// Moves the front item of one input lane into an output when it reaches
// the entry edge this tick and an output it may take has room.
splitter_pass_front_item :: proc(network: ^Belt_Network, splitter: ^Splitter, input: Splitter_Side, lane: Belt_Lane, tick_rate: int) -> bool {
	line_index := splitter.input_lines[input]
	if line_index < 0 || int(line_index) >= len(network.lines) {
		return false
	}
	line := &network.lines[line_index]
	items := &line.lanes[lane]
	if len(items) == 0 {
		return false
	}
	front := items[len(items) - 1]
	arrival := front.position + belt_units_per_tick(line^, tick_rate) - belt_line_length(line^)
	if arrival < 0 {
		return false
	}
	output, position, found := splitter_choose_output(network^, splitter^, front.item, lane, arrival)
	if !found {
		return false
	}
	pop(items)
	inject_at(&network.lines[splitter.output_lines[output]].lanes[lane], 0, Lane_Item{item = front.item, position = position})
	if splitter.filter == NO_ITEM && splitter.output_priority == .None {
		splitter.next_output[lane] = other_side(output)
	}
	return true
}

// Both lanes, the input whose turn it is (or the priority input) first.
advance_splitter :: proc(network: ^Belt_Network, splitter: ^Splitter, tick_rate: int) {
	for lane in Belt_Lane {
		first := splitter.next_input[lane]
		if splitter.input_priority != .None {
			first = priority_side(splitter.input_priority)
		}
		for input in ([2]Splitter_Side{first, other_side(first)}) {
			if splitter_pass_front_item(network, splitter, input, lane, tick_rate) && splitter.input_priority == .None {
				splitter.next_input[lane] = other_side(input)
			}
		}
	}
}

// Adding, turning and removing.

// The caller has checked that the footprint is free.
add_splitter :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, origin: World_Coordinate, direction: u8, frame := BLOCK_FRAME) -> Entity_Handle {
	records := belt_cell_items(entities)
	common := make_entity_common(machines, machine, origin, direction, frame)
	common.handle = pool_add(&entities.splitters, .Splitter, make_splitter(common))
	handle := common.handle
	occupy_entity_cells(entities, machines, common)
	rebuild_belt_lines(entities, machines, records)
	return handle
}

remove_splitter :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	splitter := pool_get(&entities.splitters, handle)
	if splitter == nil {
		return false
	}
	records := belt_cell_items(entities)
	vacate_entity_cells(entities, machines, splitter.common)
	pool_remove(&entities.splitters, handle)
	rebuild_belt_lines(entities, machines, records)
	return true
}

// A half turn, so the footprint keeps its cells; the items inside stay in
// their cells, which swap sides.
rotate_splitter :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	splitter := pool_get(&entities.splitters, handle)
	if splitter == nil {
		return false
	}
	records := belt_cell_items(entities)
	for &record in records {
		if record.belt == handle {
			record.side = other_side(record.side)
		}
	}
	splitter.rotation = turn_right(splitter.rotation, 2)
	rebuild_belt_lines(entities, machines, records)
	return true
}

// The items inside both halves, as stacks of one.
splitter_held_stacks :: proc(entities: ^Entities, handle: Entity_Handle, allocator := context.temp_allocator) -> []Item_Stack {
	stacks := make([dynamic]Item_Stack, allocator)
	splitter := pool_get(&entities.splitters, handle)
	if splitter == nil {
		return stacks[:]
	}
	for line_index in splitter.output_lines {
		if line_index < 0 || int(line_index) >= len(entities.belt_network.lines) {
			continue
		}
		for lane in Belt_Lane {
			for entry in entities.belt_network.lines[line_index].lanes[lane] {
				append(&stacks, Item_Stack{item = entry.item, count = 1})
			}
		}
	}
	return stacks[:]
}

// Panel toggles: none, left, right, none.
next_splitter_priority :: proc(priority: Splitter_Priority) -> Splitter_Priority {
	return Splitter_Priority((u8(priority) + 1) % len(Splitter_Priority))
}
