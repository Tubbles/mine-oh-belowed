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
	// The last belt faces into the `side` half of `splitter` from behind:
	// the splitter moves the front items on (splitter.odin).
	Splitter,
}

Belt_Line_End :: struct {
	kind:     Belt_Line_End_Kind,
	line:     i32,
	lane:     Belt_Lane,
	position: i32,
	splitter: Entity_Handle,
	side:     Splitter_Side,
}

Belt_Line :: struct {
	// From the first belt to the last.
	belts:                  [dynamic]Entity_Handle,
	lanes:                  [Belt_Lane][dynamic]Lane_Item,
	speed_units_per_second: u32,
	end:                    Belt_Line_End,
	// A splitter's output line holds just the splitter; side is its half.
	side:                   Splitter_Side,
	// Set by each tick: a lane's front item stands at the dead end.
	front_held_at_dead_end: bool,
}

Belt_Network :: struct {
	lines:     [dynamic]Belt_Line,
	// Downstream first, so an item handed on is not moved a second time
	// in the same tick. An entry is a line index, or -(index + 1) for the
	// splitter at that pool index, which runs after its output lines and
	// before its input lines.
	order:     [dynamic]i32,
	// Zero means context.allocator; tests use the temp allocator.
	allocator: runtime.Allocator,
}

// The items of one belt block, the form a save stores and the rebuild
// restores. offset is 0 to 255 within the block. belt may be a splitter,
// for the items inside its `side` half.
Belt_Cell_Item :: struct {
	belt:   Entity_Handle,
	lane:   Belt_Lane,
	offset: i32,
	item:   Item_Id,
	side:   Splitter_Side,
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

belt_at :: proc(entities: ^Entities, cell: World_Coordinate, frame := BLOCK_FRAME) -> ^Belt {
	handle := entity_at(entities, cell, frame)
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
	other := belt_at(entities, cell, belt.frame)
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
	if next := belt_at(entities, output, belt.frame); next != nil {
		return {next.handle, .Direct}
	}
	below := belt_at(entities, output - UP, belt.frame)
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
	// Feeds the `side` half of the target splitter.
	Into_Splitter,
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

Belt_Link :: struct {
	target:     Entity_Handle,
	connection: Belt_Connection,
	// What continues into this belt: a belt, a splitter, or nothing.
	previous:   Entity_Handle,
	// Into_Splitter: the half of the target splitter.
	side:       Splitter_Side,
}

Belt_Links :: struct {
	// Per belt pool index.
	belts:     []Belt_Link,
	// Per splitter pool index, where each half's items go.
	splitters: [][Splitter_Side]Belt_Link,
}

// The belts or splitter halves that side load onto a belt.
Side_Feeders :: struct {
	count:    int,
	link:     ^Belt_Link,
	handle:   Entity_Handle,
	rotation: u8,
}

// Where a belt's (or a splitter half's) items go and how.
belt_link :: proc(entities: ^Entities, belt: Belt) -> Belt_Link {
	if link, found := splitter_input_link(entities, belt); found {
		return link
	}
	target := belt_target(entities, belt)
	if target.belt == NO_ENTITY {
		return {}
	}
	return Belt_Link{target = target.belt, connection = belt_connection(entities, belt, entities.belts.entries[target.belt.index], target.arrival)}
}

// Every belt's and splitter half's target and connection. Where two
// feeders would continue into the same belt or splitter half, the first
// wins (splitters, then belts, each in pool order) and the other ends
// there. A flat belt that nothing continues into and that exactly one
// feeder side loads onto becomes a curve: that feeder continues into it.
compute_belt_links :: proc(entities: ^Entities) -> Belt_Links {
	belts := entities.belts.entries[:]
	splitters := entities.splitters.entries[:]
	links := Belt_Links {
		belts     = make([]Belt_Link, len(belts), context.temp_allocator),
		splitters = make([][Splitter_Side]Belt_Link, len(splitters), context.temp_allocator),
	}
	for &belt, index in belts {
		if belt.alive {
			belt.entry_direction = belt.rotation
			links.belts[index] = belt_link(entities, belt)
		}
	}
	for splitter, index in splitters {
		for side in Splitter_Side {
			if splitter.alive {
				links.splitters[index][side] = belt_link(entities, splitter_half_belt(splitter, side))
			}
		}
	}
	side_feeders := make([]Side_Feeders, len(belts), context.temp_allocator)
	claimed_halves := make([][Splitter_Side]bool, len(splitters), context.temp_allocator)
	for &halves, index in links.splitters {
		for &link in halves {
			claim_belt_link(links, side_feeders, claimed_halves, &link, splitters[index].handle, splitters[index].rotation)
		}
	}
	for &link, index in links.belts {
		claim_belt_link(links, side_feeders, claimed_halves, &link, belts[index].handle, belts[index].rotation)
	}
	for &belt, index in belts {
		feeders := side_feeders[index]
		if !belt.alive || belt.shape != .Flat || links.belts[index].previous != NO_ENTITY || feeders.count != 1 {
			continue
		}
		feeders.link.connection = .Straight
		links.belts[index].previous = feeders.handle
		belt.entry_direction = feeders.rotation
	}
	return links
}

claim_belt_link :: proc(links: Belt_Links, side_feeders: []Side_Feeders, claimed_halves: [][Splitter_Side]bool, link: ^Belt_Link, feeder: Entity_Handle, rotation: u8) {
	target := link.target.index
	switch link.connection {
	case .None:
	case .Straight:
		if links.belts[target].previous == NO_ENTITY {
			links.belts[target].previous = feeder
		} else {
			link.connection = .None
		}
	case .Side_Left, .Side_Right:
		side_feeders[target] = Side_Feeders{count = side_feeders[target].count + 1, link = link, handle = feeder, rotation = rotation}
	case .Into_Splitter:
		if claimed_halves[target][link.side] {
			link.connection = .None
		} else {
			claimed_halves[target][link.side] = true
		}
	}
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

// A line starts where no belt continues into the belt (nothing or a
// splitter does) or the speed changes.
belt_starts_line :: proc(entities: ^Entities, machines: Machine_Registry, links: []Belt_Link, index: int) -> bool {
	previous := links[index].previous
	if previous.kind != .Belt {
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

// Where the items of a line whose last block has this link go, once
// every belt knows its line.
link_line_end :: proc(entities: ^Entities, link: Belt_Link) -> Belt_Line_End {
	if link.connection == .Into_Splitter {
		return Belt_Line_End{kind = .Splitter, splitter = link.target, side = link.side}
	}
	if link.connection == .None {
		return {}
	}
	target := entities.belts.entries[link.target.index]
	block_start := target.line_index * BELT_UNITS_PER_BLOCK
	switch link.connection {
	case .None, .Into_Splitter:
	case .Straight:
		return Belt_Line_End{kind = .Straight, line = target.line, position = block_start}
	case .Side_Left:
		return Belt_Line_End{kind = .Side_Load, line = target.line, lane = .Left, position = block_start + BELT_INSERT_OFFSET}
	case .Side_Right:
		return Belt_Line_End{kind = .Side_Load, line = target.line, lane = .Right, position = block_start + BELT_INSERT_OFFSET}
	}
	return {}
}

// A line into a splitter is also recorded as that splitter's input.
resolve_line_end :: proc(entities: ^Entities, links: Belt_Links, line_index: int) {
	line := &entities.belt_network.lines[line_index]
	if line.end.kind == .Straight {
		return
	}
	last := line.belts[len(line.belts) - 1]
	link := last.kind == .Splitter ? links.splitters[last.index][line.side] : links.belts[last.index]
	line.end = link_line_end(entities, link)
	if line.end.kind == .Splitter {
		entities.splitters.entries[line.end.splitter.index].input_lines[line.end.side] = i32(line_index)
	}
}

// One output line per splitter half, after the belt lines.
add_splitter_output_lines :: proc(entities: ^Entities, machines: Machine_Registry) {
	network := &entities.belt_network
	for &splitter in entities.splitters.entries {
		if !splitter.alive {
			continue
		}
		splitter.input_lines = {.Left = -1, .Right = -1}
		for side in Splitter_Side {
			line := make_belt_line(network, machines.machines[splitter.machine].belt_speed_units_per_second)
			line.side = side
			append(&line.belts, splitter.handle)
			splitter.output_lines[side] = i32(len(network.lines))
			append(&network.lines, line)
		}
	}
}

// The nodes a line or splitter node hands items to: a line's end line or
// splitter, a splitter's two output lines.
downstream_belt_nodes :: proc(network: Belt_Network, splitters: []Splitter, node: i32) -> (nodes: [2]i32, count: int) {
	if node < 0 {
		lines := splitters[-node - 1].output_lines
		return {lines[.Left], lines[.Right]}, 2
	}
	end := network.lines[node].end
	switch end.kind {
	case .Dead_End:
		return {}, 0
	case .Straight, .Side_Load:
		return {end.line, 0}, 1
	case .Splitter:
		return {-i32(end.splitter.index) - 1, 0}, 1
	}
	return {}, 0
}

Belt_Order_Frame :: struct {
	node:  i32,
	child: int,
}

// Downstream first: a depth first walk from every line appends a node
// after everything downstream of it. A loop is cut where the walk comes
// back to a node already on the path.
compute_belt_line_order :: proc(network: ^Belt_Network, splitters: []Splitter = nil) {
	visited_lines := make([]bool, len(network.lines), context.temp_allocator)
	visited_splitters := make([]bool, len(splitters), context.temp_allocator)
	stack := make([dynamic]Belt_Order_Frame, context.temp_allocator)
	for start in 0 ..< len(network.lines) {
		if visited_lines[start] {
			continue
		}
		visited_lines[start] = true
		append(&stack, Belt_Order_Frame{node = i32(start)})
		for len(stack) > 0 {
			frame := &stack[len(stack) - 1]
			nodes, count := downstream_belt_nodes(network^, splitters, frame.node)
			if frame.child == count {
				append(&network.order, frame.node)
				pop(&stack)
				continue
			}
			next := nodes[frame.child]
			frame.child += 1
			visited := next < 0 ? &visited_splitters[-next - 1] : &visited_lines[next]
			if !visited^ {
				visited^ = true
				append(&stack, Belt_Order_Frame{node = next})
			}
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
				append(&records, Belt_Cell_Item{belt = line.belts[block], lane = lane, offset = entry.position % BELT_UNITS_PER_BLOCK, item = entry.item, side = line.side})
			}
		}
	}
	return records[:]
}

// The line and position a record's item goes back to, or found false
// when its belt or splitter is gone.
record_line_position :: proc(entities: ^Entities, record: Belt_Cell_Item) -> (line: ^Belt_Line, position: i32, found: bool) {
	lines := entities.belt_network.lines[:]
	if record.belt.kind == .Splitter {
		splitter := pool_get(&entities.splitters, record.belt)
		if splitter == nil {
			return nil, 0, false
		}
		return &lines[splitter.output_lines[record.side]], record.offset, true
	}
	belt := pool_get(&entities.belts, record.belt)
	if belt == nil {
		return nil, 0, false
	}
	return &lines[belt.line], belt.line_index * BELT_UNITS_PER_BLOCK + record.offset, true
}

restore_belt_items :: proc(entities: ^Entities, records: []Belt_Cell_Item) {
	for record in records {
		if line, position, found := record_line_position(entities, record); found {
			append(&line.lanes[record.lane], Lane_Item{item = record.item, position = position})
		}
	}
	for &line in entities.belt_network.lines {
		for lane in Belt_Lane {
			slice.stable_sort_by(line.lanes[lane][:], proc(first, second: Lane_Item) -> bool {
				return first.position < second.position
			})
		}
	}
}

// Rebuilds every line from the belt graph, the splitters' lines included,
// and puts the recorded items back. Items of belts and splitters that no
// longer exist are dropped.
rebuild_belt_lines :: proc(entities: ^Entities, machines: Machine_Registry, records: []Belt_Cell_Item) {
	network := &entities.belt_network
	destroy_belt_lines(network)
	if network.lines.allocator.procedure == nil {
		allocator := network_allocator(network)
		network.lines.allocator, network.order.allocator = allocator, allocator
	}
	links := compute_belt_links(entities)
	visited := make([]bool, len(links.belts), context.temp_allocator)
	for belt, index in entities.belts.entries {
		if belt.alive && belt_starts_line(entities, machines, links.belts, index) {
			walk_belt_line(entities, machines, links.belts, visited, index)
		}
	}
	for belt, index in entities.belts.entries {
		if belt.alive && !visited[index] {
			walk_belt_line(entities, machines, links.belts, visited, index)
		}
	}
	add_splitter_output_lines(entities, machines)
	for index in 0 ..< len(network.lines) {
		resolve_line_end(entities, links, index)
	}
	compute_belt_line_order(network, entities.splitters.entries[:])
	restore_belt_items(entities, records)
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
add_belt :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, cell: World_Coordinate, direction: u8, shape: Belt_Shape, frame := BLOCK_FRAME) -> Entity_Handle {
	records := belt_cell_items(entities)
	common := make_entity_common(machines, machine, cell, direction, frame)
	common.handle = pool_add(&entities.belts, .Belt, make_belt(common, shape))
	handle := common.handle
	occupy_entity_cells(entities, machines, common)
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
	vacate_entity_cells(entities, machines, belt.common)
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
