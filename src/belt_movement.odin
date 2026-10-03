package game

// Item movement on transport lines, all integer. Per tick every lane moves
// its items from the front backwards: each advances by the speed and stops
// a spacing behind the item ahead. The front item stops at the line end
// (dead end or side load) or, when the line continues straight, a spacing
// behind the back item of the next line. Items past the end are handed on.
// A dead end over a drop lets its front items fall off as loose items
// (drop_items_off_belt_ends).
// A line into a splitter leaves the hand off to the splitter's node, which
// runs just before it (splitter.odin).
// Cost is proportional to the items, not to the belt length.

belt_line_length :: proc(line: Belt_Line) -> i32 {
	return i32(len(line.belts)) * BELT_UNITS_PER_BLOCK
}

belt_units_per_tick :: proc(line: Belt_Line, tick_rate: int) -> i32 {
	return i32(line.speed_units_per_second / u32(max(tick_rate, 1)))
}

// How far the front item of a lane may go this tick. Into a splitter it
// is the limit of an item the splitter did not take (splitter.odin).
lane_front_limit :: proc(network: ^Belt_Network, line: Belt_Line, lane: Belt_Lane, speed: i32, splitters: []Splitter) -> i32 {
	length := belt_line_length(line)
	items := line.lanes[lane]
	if line.end.kind == .Splitter && len(items) > 0 && int(line.end.splitter.index) < len(splitters) {
		return splitter_input_front_limit(network^, splitters[line.end.splitter.index], items[len(items) - 1].item, lane, length)
	}
	if line.end.kind != .Straight {
		return length - BELT_END_MARGIN
	}
	next := network.lines[line.end.line].lanes[lane]
	if len(next) == 0 {
		return length + speed
	}
	return next[0].position - line.end.position + length - BELT_ITEM_SPACING
}

// Front first; an item never moves backwards, so an overlap left by a
// rebuild resolves as the item ahead moves on.
advance_lane_items :: proc(items: []Lane_Item, speed, front_limit: i32) {
	limit := front_limit
	#reverse for &entry in items {
		entry.position = max(entry.position, min(entry.position + speed, limit))
		limit = entry.position - BELT_ITEM_SPACING
	}
}

// The index a new item at `position` goes to, and whether it keeps a
// spacing to both neighbours.
lane_insert_index :: proc(items: []Lane_Item, position: i32) -> (index: int, room: bool) {
	index = len(items)
	for entry, candidate in items {
		if entry.position >= position {
			index = candidate
			break
		}
	}
	room = true
	if index < len(items) && items[index].position - position < BELT_ITEM_SPACING {
		room = false
	}
	if index > 0 && position - items[index - 1].position < BELT_ITEM_SPACING {
		room = false
	}
	return
}

lane_insert :: proc(items: ^[dynamic]Lane_Item, item: Item_Id, position: i32) -> bool {
	index, room := lane_insert_index(items[:], position)
	if !room {
		return false
	}
	inject_at(items, index, Lane_Item{item = item, position = position})
	return true
}

// Straight on: every item past the end continues at the back of the next
// lane; the front limit guaranteed the spacing.
hand_off_straight :: proc(network: ^Belt_Network, line_index: i32, lane: Belt_Lane) {
	line := &network.lines[line_index]
	length := belt_line_length(line^)
	end := line.end
	for len(line.lanes[lane]) > 0 {
		front := line.lanes[lane][len(line.lanes[lane]) - 1]
		if front.position < length {
			return
		}
		pop(&line.lanes[lane])
		front.position += end.position - length
		inject_at(&network.lines[end.line].lanes[lane], 0, front)
	}
}

// Side load: an item waiting at the end goes onto the near lane of the
// target when there is a spacing of room around the landing position.
hand_off_side_load :: proc(network: ^Belt_Network, line_index: i32, lane: Belt_Lane) {
	line := &network.lines[line_index]
	end := line.end
	items := &line.lanes[lane]
	if len(items) == 0 || items[len(items) - 1].position < belt_line_length(line^) - BELT_END_MARGIN {
		return
	}
	target := &network.lines[end.line].lanes[end.lane]
	if _, room := lane_insert_index(target[:], end.position); !room {
		return
	}
	front := pop(items)
	lane_insert(target, front.item, end.position)
}

// Distance from an item to the one ahead of it around a loop.
loop_gap :: proc(items: []Lane_Item, index: int, length: i32) -> i32 {
	if index == len(items) - 1 {
		return items[0].position + length - items[index].position
	}
	return items[index + 1].position - items[index].position
}

// A lane that continues into itself has no front. Processing starts at
// the item with the most room ahead and goes backwards around the loop,
// so a compressed stretch moves as one. A full loop (every gap exactly
// the spacing) moves as a whole.
advance_loop_lane :: proc(items: []Lane_Item, speed, length: i32) {
	count := len(items)
	if count == 0 {
		return
	}
	if i32(count) * BELT_ITEM_SPACING >= length {
		for &entry in items {
			entry.position += speed
		}
		return
	}
	start := 0
	for index in 1 ..< count {
		if loop_gap(items, index, length) > loop_gap(items, start, length) {
			start = index
		}
	}
	limit := items[start].position + loop_gap(items, start, length) - BELT_ITEM_SPACING
	for step in 0 ..< count {
		index := (start - step + count) % count
		entry := &items[index]
		entry.position = max(entry.position, min(entry.position + speed, limit))
		limit = entry.position - BELT_ITEM_SPACING
		if index == 0 {
			limit += length
		}
	}
}

belt_line_is_loop :: proc(line: Belt_Line, line_index: i32) -> bool {
	return line.end.kind == .Straight && line.end.line == line_index
}

// Whether the lane's front item stands at the line's dead end.
lane_front_at_dead_end :: proc(line: Belt_Line, lane: Belt_Lane) -> bool {
	items := line.lanes[lane]
	return line.end.kind == .Dead_End && len(items) > 0 && items[len(items) - 1].position >= belt_line_length(line) - BELT_END_MARGIN
}

advance_belt_line :: proc(network: ^Belt_Network, line_index: i32, tick_rate: int, splitters: []Splitter) {
	speed := belt_units_per_tick(network.lines[line_index], tick_rate)
	network.lines[line_index].front_held_at_dead_end = false
	for lane in Belt_Lane {
		if belt_line_is_loop(network.lines[line_index], line_index) {
			advance_loop_lane(network.lines[line_index].lanes[lane][:], speed, belt_line_length(network.lines[line_index]))
		} else {
			limit := lane_front_limit(network, network.lines[line_index], lane, speed, splitters)
			advance_lane_items(network.lines[line_index].lanes[lane][:], speed, limit)
		}
		switch network.lines[line_index].end.kind {
		case .Dead_End, .Splitter:
		case .Straight:
			hand_off_straight(network, line_index, lane)
		case .Side_Load:
			hand_off_side_load(network, line_index, lane)
		}
		network.lines[line_index].front_held_at_dead_end ||= lane_front_at_dead_end(network.lines[line_index], lane)
	}
}

// The cell a dead end's front items fall into: the cell in front of the
// last belt at its height, when it is loaded, holds no block and no
// entity, and a stack there can fall (loose_item_can_fall). A dead end
// against a wall, a machine or level ground holds its items.
belt_end_drop_cell :: proc(tick_context: Entity_Tick_Context, line: Belt_Line) -> (cell: World_Coordinate, drops: bool) {
	if line.end.kind != .Dead_End || len(line.belts) == 0 {
		return {}, false
	}
	belt, found := line_block_belt(tick_context.entities, line, i32(len(line.belts) - 1))
	if !found {
		return {}, false
	}
	cell = belt_output_cell(belt)
	block, loaded := tick_get_block(tick_context, cell)
	if !loaded || entity_at(tick_context.entities, cell, belt.frame) != NO_ENTITY || block_is_solid(tick_context.content.blocks, block) {
		return cell, false
	}
	return cell, loose_item_can_fall(tick_context, cell)
}

// Quarter blocks from the cell centre towards the lane's side of the belt.
lane_side_offset :: proc(belt: Belt, lane: Belt_Lane) -> [2]i8 {
	right := belt_direction_offset(turn_right(belt.rotation))
	side := lane == .Right ? i8(1) : i8(-1)
	return {i8(right.x) * side, i8(right.z) * side}
}

// Runs after the belt network's tick: a front item standing at a dead end
// over a drop leaves its lane as a loose item in the cell in front,
// which then falls (loose_item.odin). The line no longer holds anything
// at its end.
drop_items_off_belt_ends :: proc(tick_context: Entity_Tick_Context) {
	for &line in tick_context.entities.belt_network.lines {
		if !line.front_held_at_dead_end {
			continue
		}
		cell, drops := belt_end_drop_cell(tick_context, line)
		if !drops {
			continue
		}
		belt, _ := line_block_belt(tick_context.entities, line, i32(len(line.belts) - 1))
		for lane in Belt_Lane {
			if lane_front_at_dead_end(line, lane) {
				front := pop(&line.lanes[lane])
				spill_stack_in_context(tick_context, cell, Item_Stack{item = front.item, count = 1}, lane_side_offset(belt, lane))
			}
		}
		line.front_held_at_dead_end = false
	}
}

// splitters is the splitter pool the network's splitter nodes index.
tick_belt_network :: proc(network: ^Belt_Network, tick_rate: int, splitters: []Splitter = nil) {
	for node in network.order {
		if node < 0 {
			advance_splitter(network, &splitters[-node - 1], tick_rate)
		} else {
			advance_belt_line(network, node, tick_rate, splitters)
		}
	}
}

// Putting one item on a belt block, mid block on the given lane.
belt_insert_item :: proc(entities: ^Entities, handle: Entity_Handle, lane: Belt_Lane, item: Item_Id) -> bool {
	line, belt := belt_line_of(entities, handle)
	if line == nil {
		return false
	}
	return lane_insert(&line.lanes[lane], item, belt.line_index * BELT_UNITS_PER_BLOCK + BELT_INSERT_OFFSET)
}

belt_has_room :: proc(entities: ^Entities, handle: Entity_Handle, lane: Belt_Lane) -> bool {
	line, belt := belt_line_of(entities, handle)
	if line == nil {
		return false
	}
	_, room := lane_insert_index(line.lanes[lane][:], belt.line_index * BELT_UNITS_PER_BLOCK + BELT_INSERT_OFFSET)
	return room
}

Belt_Item_Location :: struct {
	found: bool,
	lane:  Belt_Lane,
	index: int,
}

// The item on the belt block nearest its middle, either lane (left first
// on a tie), matching the filter unless the filter is NO_ITEM.
nearest_belt_item :: proc(line: Belt_Line, block: i32, filter: Item_Id) -> Belt_Item_Location {
	return nearest_belt_item_excluding(line, block, filter, nil)
}

belt_extract_item :: proc(entities: ^Entities, handle: Entity_Handle, filter: Item_Id) -> Item_Id {
	line, belt := belt_line_of(entities, handle)
	if line == nil {
		return NO_ITEM
	}
	location := nearest_belt_item(line^, belt.line_index, filter)
	if !location.found {
		return NO_ITEM
	}
	item := line.lanes[location.lane][location.index].item
	ordered_remove(&line.lanes[location.lane], location.index)
	return item
}

// The distinct items on the belt block in the order belt_extract_item
// takes them: nearest the middle first, left lane first on a tie.
belt_offered_items :: proc(entities: ^Entities, handle: Entity_Handle, filter: Item_Id) -> []Item_Id {
	offered := make([dynamic]Item_Id, context.temp_allocator)
	line, belt := belt_line_of(entities, handle)
	if line == nil {
		return offered[:]
	}
	for {
		location := nearest_belt_item_excluding(line^, belt.line_index, filter, offered[:])
		if !location.found {
			return offered[:]
		}
		append(&offered, line.lanes[location.lane][location.index].item)
	}
}

// nearest_belt_item skipping the items already listed.
nearest_belt_item_excluding :: proc(line: Belt_Line, block: i32, filter: Item_Id, excluded: []Item_Id) -> Belt_Item_Location {
	middle := block * BELT_UNITS_PER_BLOCK + BELT_INSERT_OFFSET
	best: Belt_Item_Location
	best_distance := i32(max(i32))
	for lane in Belt_Lane {
		for entry, index in line.lanes[lane] {
			if entry.position / BELT_UNITS_PER_BLOCK != block || (filter != NO_ITEM && entry.item != filter) || slice_contains_item(excluded, entry.item) {
				continue
			}
			if distance := abs(entry.position - middle); distance < best_distance {
				best, best_distance = Belt_Item_Location{found = true, lane = lane, index = index}, distance
			}
		}
	}
	return best
}
