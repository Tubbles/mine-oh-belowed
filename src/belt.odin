package game

import "base:runtime"
import "core:math"
import "core:slice"

// Belts and transport lines (doc/logistics.md). A belt is a 1 by 1 by 1
// entity with a direction (Entity_Common.rotation, 0 is +x, each step
// turns right: +z, -x, -z) and a shape. Consecutive belts that feed each
// other form a Belt_Line, and items are fixed point positions along the
// line's two lanes (1/256 block), never entities. Lines are derived data:
// they are rebuilt from the belts plus the items per belt cell whenever a
// belt is placed, removed or reshaped, so a save only needs the belts and
// Belt_Cell_Item records.

// A quarter block, so four items per lane per block.
BELT_ITEM_SPACING :: 64
// Items at a dead end stop half a spacing before the end, so the last
// block holds exactly four per lane.
BELT_END_MARGIN :: BELT_ITEM_SPACING / 2
// Side loaded, inserted and debug dropped items land mid block.
BELT_INSERT_OFFSET :: BELT_UNITS_PER_BLOCK / 2
MAXIMUM_BELT_ITEMS_DRAWN_PER_BLOCK :: 8

UP :: World_Coordinate{0, 1, 0}

// Ramps rise (or fall) one block over their one block of run; lifts carry
// items straight up (or down) through their cell. Ramp_Up and Lift_Up
// leave at the top of the cell, the others at the bottom.
Belt_Shape :: enum u8 {
	Flat,
	Ramp_Up,
	Ramp_Down,
	Lift_Up,
	Lift_Down,
}

// Left and right of the belt's direction.
Belt_Lane :: enum u8 {
	Left,
	Right,
}

Belt :: struct {
	using common:    Entity_Common,
	shape:           Belt_Shape,
	// The horizontal direction items arrive in. It differs from the
	// belt's direction only on a curve (a flat belt fed from one side).
	entry_direction: u8,
	// Set by rebuild_belt_lines: the line and the belt's index in it.
	line:            i32,
	line_index:      i32,
}

// Ascending position within a lane, so the front item is last.
Lane_Item :: struct {
	item:     Item_Id,
	position: i32,
}

Belt_Line_End_Kind :: enum u8 {
	Dead_End,
	// Items continue at `position` of the same lane of `line` (a loop
	// continues into itself, a speed change into the next line).
	Straight,
	// The last belt faces the side of another belt: items go onto `lane`
	// (the near lane) of `line` at `position`.
	Side_Load,
}

Belt_Line_End :: struct {
	kind:     Belt_Line_End_Kind,
	line:     i32,
	lane:     Belt_Lane,
	position: i32,
}

Belt_Line :: struct {
	// From the first belt to the last.
	belts:                  [dynamic]Entity_Handle,
	lanes:                  [Belt_Lane][dynamic]Lane_Item,
	speed_units_per_second: u32,
	end:                    Belt_Line_End,
}

Belt_Network :: struct {
	lines:     [dynamic]Belt_Line,
	// Downstream lines first, so an item handed on is not moved a second
	// time in the same tick.
	order:     [dynamic]i32,
	// Zero means context.allocator; tests use the temp allocator.
	allocator: runtime.Allocator,
}

// The items of one belt block, the form a save stores and the rebuild
// restores. offset is 0 to 255 within the block.
Belt_Cell_Item :: struct {
	belt:   Entity_Handle,
	lane:   Belt_Lane,
	offset: i32,
	item:   Item_Id,
}

// Directions.

belt_direction_offset :: proc(direction: u8) -> World_Coordinate {
	switch direction % 4 {
	case 0:
		return {1, 0, 0}
	case 1:
		return {0, 0, 1}
	case 2:
		return {-1, 0, 0}
	}
	return {0, 0, -1}
}

turn_right :: proc(direction: u8, steps: u8 = 1) -> u8 {
	return (direction + steps) % 4
}

// The direction of a horizontal unit step, or ok false for anything else.
horizontal_step_direction :: proc(from, to: World_Coordinate) -> (direction: u8, ok: bool) {
	offset := to - from
	for candidate in u8(0) ..< 4 {
		step := belt_direction_offset(candidate)
		if offset.x == step.x && offset.z == step.z {
			return candidate, true
		}
	}
	return 0, false
}

// The quarter the yaw points into: 0 for +x, 1 for +z (yaw 90).
yaw_direction :: proc(yaw: f32) -> u8 {
	quarter := i32(math.floor((yaw + 45) / 90))
	return u8(((quarter % 4) + 4) % 4)
}

belt_shape_is_lift :: proc(shape: Belt_Shape) -> bool {
	return shape == .Lift_Up || shape == .Lift_Down
}

// Where items leave the belt to.
belt_output_cell :: proc(belt: Belt) -> World_Coordinate {
	forward := belt_direction_offset(belt.rotation)
	if belt.shape == .Ramp_Up || belt.shape == .Lift_Up {
		return belt.origin + forward + UP
	}
	return belt.origin + forward
}

belt_at :: proc(entities: ^Entities, cell: World_Coordinate) -> ^Belt {
	handle := entity_at(entities, cell)
	if handle.kind != .Belt {
		return nil
	}
	return pool_get(&entities.belts, handle)
}

// The next block of a lift column in its travel direction, or nil.
lift_column_next :: proc(entities: ^Entities, belt: Belt) -> ^Belt {
	step := belt.shape == .Lift_Up ? UP : -UP
	return matching_lift(entities, belt, belt.origin + step)
}

// The previous block of a lift column, or nil at the column's entry.
lift_column_previous :: proc(entities: ^Entities, belt: Belt) -> ^Belt {
	step := belt.shape == .Lift_Up ? -UP : UP
	return matching_lift(entities, belt, belt.origin + step)
}

matching_lift :: proc(entities: ^Entities, belt: Belt, cell: World_Coordinate) -> ^Belt {
	other := belt_at(entities, cell)
	if other == nil || other.shape != belt.shape || other.rotation != belt.rotation {
		return nil
	}
	return other
}

// Graph.

Belt_Arrival :: enum u8 {
	// Into the output cell itself.
	Direct,
	// The output cell is empty and the belt below it starts high: a ramp
	// down or the top of a down lift.
	Descending,
	// Up or down a lift column.
	Vertical,
}

Belt_Target :: struct {
	belt:    Entity_Handle,
	arrival: Belt_Arrival,
}

belt_target :: proc(entities: ^Entities, belt: Belt) -> Belt_Target {
	if belt_shape_is_lift(belt.shape) {
		if next := lift_column_next(entities, belt); next != nil {
			return {next.handle, .Vertical}
		}
	}
	output := belt_output_cell(belt)
	if next := belt_at(entities, output); next != nil {
		return {next.handle, .Direct}
	}
	below := belt_at(entities, output - UP)
	if below != nil && (below.shape == .Ramp_Down || below.shape == .Lift_Down) {
		return {below.handle, .Descending}
	}
	return {}
}

Belt_Connection :: enum u8 {
	None,
	// Continues the target's line (straight on, or into a curve).
	Straight,
	// Side loads onto the target's left or right lane.
	Side_Left,
	Side_Right,
}

// A flat belt fed from behind continues, from a side side loads onto the
// near lane, head on does not connect.
flat_connection :: proc(feeder_direction, belt_direction: u8) -> Belt_Connection {
	switch (feeder_direction + 4 - belt_direction) % 4 {
	case 0:
		return .Straight
	case 2:
		return .None
	}
	arrives_from := turn_right(feeder_direction, 2)
	return arrives_from == turn_right(belt_direction) ? .Side_Right : .Side_Left
}

// Ramps and lifts only take items straight on, lifts only at the entry
// end of the column.
belt_connection :: proc(entities: ^Entities, feeder, target: Belt, arrival: Belt_Arrival) -> Belt_Connection {
	aligned := feeder.rotation == target.rotation
	switch target.shape {
	case .Flat:
		return arrival == .Direct ? flat_connection(feeder.rotation, target.rotation) : .None
	case .Ramp_Up:
		return arrival == .Direct && aligned ? .Straight : .None
	case .Ramp_Down:
		return arrival == .Descending && aligned ? .Straight : .None
	case .Lift_Up, .Lift_Down:
		if arrival == .Vertical {
			return .Straight
		}
		entry_arrival := target.shape == .Lift_Up ? Belt_Arrival.Direct : Belt_Arrival.Descending
		entry := lift_column_previous(entities, target) == nil
		return arrival == entry_arrival && aligned && entry ? .Straight : .None
	}
	return .None
}

// Per pool index of the belts.
Belt_Link :: struct {
	target:     Entity_Handle,
	connection: Belt_Connection,
	previous:   Entity_Handle,
}

// Every belt's target and connection. Where two belts would continue into
// the same belt, the first in pool order wins and the other ends there.
// A flat belt that nothing continues into and that exactly one belt side
// loads onto becomes a curve: that belt continues into it.
compute_belt_links :: proc(entities: ^Entities) -> []Belt_Link {
	belts := entities.belts.entries[:]
	links := make([]Belt_Link, len(belts), context.temp_allocator)
	side_feeders := make([]int, len(belts), context.temp_allocator)
	side_feeder := make([]u32, len(belts), context.temp_allocator)
	for &belt, index in belts {
		if !belt.alive {
			continue
		}
		belt.entry_direction = belt.rotation
		target := belt_target(entities, belt)
		if target.belt == NO_ENTITY {
			continue
		}
		links[index].target = target.belt
		links[index].connection = belt_connection(entities, belt, belts[target.belt.index], target.arrival)
	}
	for &link, index in links {
		target := link.target.index
		switch link.connection {
		case .None:
		case .Straight:
			if links[target].previous == NO_ENTITY {
				links[target].previous = belts[index].handle
			} else {
				link.connection = .None
			}
		case .Side_Left, .Side_Right:
			side_feeders[target] += 1
			side_feeder[target] = u32(index)
		}
	}
	for &belt, index in belts {
		if !belt.alive || belt.shape != .Flat || links[index].previous != NO_ENTITY || side_feeders[index] != 1 {
			continue
		}
		feeder := side_feeder[index]
		links[feeder].connection = .Straight
		links[index].previous = belts[feeder].handle
		belt.entry_direction = belts[feeder].rotation
	}
	return links
}

// Lines.

network_allocator :: proc(network: ^Belt_Network) -> runtime.Allocator {
	return network.allocator.procedure != nil ? network.allocator : context.allocator
}

destroy_belt_lines :: proc(network: ^Belt_Network) {
	for &line in network.lines {
		delete(line.belts)
		for lane in Belt_Lane {
			delete(line.lanes[lane])
		}
	}
	clear(&network.lines)
	clear(&network.order)
}

destroy_belt_network :: proc(network: ^Belt_Network) {
	destroy_belt_lines(network)
	delete(network.lines)
	delete(network.order)
}

make_belt_line :: proc(network: ^Belt_Network, speed: u32) -> Belt_Line {
	allocator := network_allocator(network)
	line := Belt_Line {
		belts                  = make([dynamic]Entity_Handle, allocator),
		speed_units_per_second = speed,
	}
	for lane in Belt_Lane {
		line.lanes[lane] = make([dynamic]Lane_Item, allocator)
	}
	return line
}

belt_speed :: proc(machines: Machine_Registry, belt: Belt) -> u32 {
	return machines.machines[belt.machine].belt_speed_units_per_second
}

// A line starts where nothing continues into the belt or the speed changes.
belt_starts_line :: proc(entities: ^Entities, machines: Machine_Registry, links: []Belt_Link, index: int) -> bool {
	previous := links[index].previous
	if previous == NO_ENTITY {
		return true
	}
	belts := entities.belts.entries[:]
	return belt_speed(machines, belts[previous.index]) != belt_speed(machines, belts[index])
}

// Appends the belts from start along the links. A walk that comes back to
// its start is a loop and continues into itself.
walk_belt_line :: proc(entities: ^Entities, machines: Machine_Registry, links: []Belt_Link, visited: []bool, start: int) {
	network := &entities.belt_network
	belts := entities.belts.entries[:]
	line_number := i32(len(network.lines))
	line := make_belt_line(network, belt_speed(machines, belts[start]))
	index := start
	for {
		belts[index].line, belts[index].line_index = line_number, i32(len(line.belts))
		visited[index] = true
		append(&line.belts, belts[index].handle)
		if links[index].connection != .Straight {
			break
		}
		next := int(links[index].target.index)
		if belt_starts_line(entities, machines, links, next) {
			break
		}
		if visited[next] {
			line.end = Belt_Line_End{kind = .Straight, line = line_number}
			break
		}
		index = next
	}
	append(&network.lines, line)
}

// Where the last belt's items go, once every belt knows its line.
resolve_line_end :: proc(entities: ^Entities, links: []Belt_Link, line: ^Belt_Line) {
	if line.end.kind == .Straight {
		return
	}
	last := line.belts[len(line.belts) - 1]
	link := links[last.index]
	if link.target == NO_ENTITY {
		return
	}
	target := entities.belts.entries[link.target.index]
	block_start := target.line_index * BELT_UNITS_PER_BLOCK
	switch link.connection {
	case .None:
	case .Straight:
		line.end = Belt_Line_End{kind = .Straight, line = target.line, position = block_start}
	case .Side_Left:
		line.end = Belt_Line_End{kind = .Side_Load, line = target.line, lane = .Left, position = block_start + BELT_INSERT_OFFSET}
	case .Side_Right:
		line.end = Belt_Line_End{kind = .Side_Load, line = target.line, lane = .Right, position = block_start + BELT_INSERT_OFFSET}
	}
}

// Downstream first: each line is followed along its end until a line
// already placed, and the path is appended in reverse.
compute_belt_line_order :: proc(network: ^Belt_Network) {
	state := make([]u8, len(network.lines), context.temp_allocator)
	path := make([dynamic]i32, context.temp_allocator)
	for start in 0 ..< len(network.lines) {
		clear(&path)
		line := i32(start)
		for line >= 0 && state[line] == 0 {
			state[line] = 1
			append(&path, line)
			end := network.lines[line].end
			line = end.kind == .Dead_End ? -1 : end.line
		}
		#reverse for entry in path {
			append(&network.order, entry)
		}
	}
}

// Every item on the belts as a belt, lane and offset within the block.
belt_cell_items :: proc(entities: ^Entities, allocator := context.temp_allocator) -> []Belt_Cell_Item {
	records := make([dynamic]Belt_Cell_Item, allocator)
	for line in entities.belt_network.lines {
		for lane in Belt_Lane {
			for entry in line.lanes[lane] {
				block := entry.position / BELT_UNITS_PER_BLOCK
				append(&records, Belt_Cell_Item{belt = line.belts[block], lane = lane, offset = entry.position % BELT_UNITS_PER_BLOCK, item = entry.item})
			}
		}
	}
	return records[:]
}

restore_belt_items :: proc(entities: ^Entities, records: []Belt_Cell_Item) {
	for record in records {
		belt := pool_get(&entities.belts, record.belt)
		if belt == nil {
			continue
		}
		line := &entities.belt_network.lines[belt.line]
		position := belt.line_index * BELT_UNITS_PER_BLOCK + record.offset
		append(&line.lanes[record.lane], Lane_Item{item = record.item, position = position})
	}
	for &line in entities.belt_network.lines {
		for lane in Belt_Lane {
			slice.stable_sort_by(line.lanes[lane][:], proc(first, second: Lane_Item) -> bool {
				return first.position < second.position
			})
		}
	}
}

// Rebuilds every line from the belt graph and puts the recorded items
// back. Items of belts that no longer exist are dropped.
rebuild_belt_lines :: proc(entities: ^Entities, machines: Machine_Registry, records: []Belt_Cell_Item) {
	network := &entities.belt_network
	destroy_belt_lines(network)
	if network.lines.allocator.procedure == nil {
		allocator := network_allocator(network)
		network.lines.allocator, network.order.allocator = allocator, allocator
	}
	links := compute_belt_links(entities)
	visited := make([]bool, len(links), context.temp_allocator)
	for belt, index in entities.belts.entries {
		if belt.alive && belt_starts_line(entities, machines, links, index) {
			walk_belt_line(entities, machines, links, visited, index)
		}
	}
	for belt, index in entities.belts.entries {
		if belt.alive && !visited[index] {
			walk_belt_line(entities, machines, links, visited, index)
		}
	}
	for &line in network.lines {
		resolve_line_end(entities, links, &line)
	}
	compute_belt_line_order(network)
	restore_belt_items(entities, records)
}

refresh_belt_lines :: proc(entities: ^Entities, machines: Machine_Registry) {
	rebuild_belt_lines(entities, machines, belt_cell_items(entities))
}

// Adding, changing and removing belts.

make_belt :: proc(common: Entity_Common, shape: Belt_Shape) -> Belt {
	return Belt{common = common, shape = shape, entry_direction = common.rotation}
}

default_belt_shape :: proc(item_shape: Belt_Item_Shape) -> Belt_Shape {
	switch item_shape {
	case .Flat:
		return .Flat
	case .Ramp:
		return .Ramp_Up
	case .Lift:
		return .Lift_Up
	}
	return .Flat
}

// The caller has checked that the cell is free.
add_belt :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, cell: World_Coordinate, direction: u8, shape: Belt_Shape) -> Entity_Handle {
	records := belt_cell_items(entities)
	common := make_entity_common(machines, machine, cell, direction)
	handle := pool_add(&entities.belts, .Belt, make_belt(common, shape))
	entities.cells[cell] = handle
	rebuild_belt_lines(entities, machines, records)
	return handle
}

// Turns or reshapes a belt, keeping the items on it.
reshape_belt :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, machine: Machine_Id, direction: u8, shape: Belt_Shape) {
	belt := pool_get(&entities.belts, handle)
	if belt == nil {
		return
	}
	records := belt_cell_items(entities)
	belt.machine, belt.rotation, belt.shape = machine, direction % 4, shape
	rebuild_belt_lines(entities, machines, records)
}

remove_belt :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	belt := pool_get(&entities.belts, handle)
	if belt == nil {
		return false
	}
	records := belt_cell_items(entities)
	delete_key(&entities.cells, belt.origin)
	pool_remove(&entities.belts, handle)
	rebuild_belt_lines(entities, machines, records)
	return true
}

belt_line_of :: proc(entities: ^Entities, handle: Entity_Handle) -> (line: ^Belt_Line, belt: ^Belt) {
	belt = pool_get(&entities.belts, handle)
	if belt == nil || int(belt.line) >= len(entities.belt_network.lines) {
		return nil, nil
	}
	return &entities.belt_network.lines[belt.line], belt
}

// The items on one belt block, both lanes, as stacks of one.
belt_block_stacks :: proc(entities: ^Entities, handle: Entity_Handle, allocator := context.temp_allocator) -> []Item_Stack {
	stacks := make([dynamic]Item_Stack, allocator)
	line, belt := belt_line_of(entities, handle)
	if line == nil {
		return stacks[:]
	}
	for lane in Belt_Lane {
		for entry in line.lanes[lane] {
			if entry.position / BELT_UNITS_PER_BLOCK == belt.line_index {
				append(&stacks, Item_Stack{item = entry.item, count = 1})
			}
		}
	}
	return stacks[:]
}

// Player carrying: the horizontal velocity of a flat belt or a ramp in
// blocks per tick, zero elsewhere. Lifts do not carry the player.
belt_carry_offset :: proc(belt: Belt, machines: Machine_Registry, tick_rate: int) -> [3]f32 {
	if belt_shape_is_lift(belt.shape) {
		return {}
	}
	units_per_tick := f32(belt_speed(machines, belt) / u32(max(tick_rate, 1)))
	forward := belt_direction_offset(belt.rotation)
	return [3]f32{f32(forward.x), 0, f32(forward.z)} * units_per_tick / BELT_UNITS_PER_BLOCK
}
