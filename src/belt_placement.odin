package game

// Placing belts. The direction is the player's facing turned by the
// placement rotation, so rotation 0 points away from the player. A belt
// placed where another belt's items come out takes that belt's direction.
// Holding Place with the belt item drags a run along the reticle's path:
// each new cell gets a belt pointing on from the previous one, the
// previous belt turns towards it, and a one block step of the ground
// turns into a ramp (taken from the inventory). Ramp and lift items place
// one at a time; a lift placed on a lift continues the column.

// The drag in progress. Only belts this drag placed are turned or
// reshaped; a run started on an existing belt keeps that belt as it is.
Belt_Drag :: struct {
	active:      bool,
	last:        Entity_Handle,
	last_cell:   World_Coordinate,
	last_placed: bool,
}

Planned_Belt :: struct {
	cell:      World_Coordinate,
	direction: u8,
	shape:     Belt_Shape,
}

MAXIMUM_DRAG_STEPS_PER_TICK :: 16
// Lifts take eight rotations: 0 to 3 up, 4 to 7 down.
LIFT_ROTATION_COUNT :: 8

// One step of a run. A step up turns the previous belt into a ramp up; a
// step down makes the new belt a ramp down. Ramps are not turned.
belt_drag_step :: proc(previous: Planned_Belt, next_cell: World_Coordinate) -> (updated_previous, next: Planned_Belt) {
	direction, _ := horizontal_step_direction(previous.cell, next_cell)
	updated_previous = previous
	if previous.shape == .Flat {
		updated_previous.direction = direction
		if next_cell.y == previous.cell.y + 1 {
			updated_previous.shape = .Ramp_Up
		}
	}
	next = Planned_Belt{cell = next_cell, direction = direction, shape = .Flat}
	if next_cell.y == previous.cell.y - 1 {
		next.shape = .Ramp_Down
	}
	return
}

// The belts a drag along `cells` (each a horizontal step from the one
// before, at most one block up or down) places.
plan_belt_run :: proc(cells: []World_Coordinate, initial_direction: u8, allocator := context.temp_allocator) -> []Planned_Belt {
	plan := make([]Planned_Belt, len(cells), allocator)
	if len(cells) == 0 {
		return plan
	}
	plan[0] = Planned_Belt{cell = cells[0], direction = initial_direction, shape = .Flat}
	for index in 1 ..< len(cells) {
		plan[index - 1], plan[index] = belt_drag_step(plan[index - 1], cells[index])
	}
	return plan
}

// Horizontal columns from `from` (excluded) to `to` (included), one axis
// at a time, the axis of the current direction first so a run keeps going
// straight before it turns.
belt_drag_columns :: proc(from, to: [2]i32, x_first: bool, allocator := context.temp_allocator) -> [][2]i32 {
	columns := make([dynamic][2]i32, allocator)
	current := from
	axes := x_first ? [2]int{0, 1} : [2]int{1, 0}
	for axis in axes {
		for current[axis] != to[axis] {
			current[axis] += to[axis] > current[axis] ? 1 : -1
			append(&columns, current)
		}
	}
	return columns[:]
}

// World side.

// On a solid block, or a lift on a lift.
belt_cell_supported :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate, shape: Belt_Shape) -> bool {
	if block_is_solid(registry, world_get_block(world, cell - UP)) {
		return true
	}
	below := belt_at(&world.entities, cell - UP)
	return belt_shape_is_lift(shape) && below != nil && belt_shape_is_lift(below.shape)
}

// The cell of a drag step into a column: level, one up where a block
// stands in the way, one down where the ground falls away. An existing
// belt at either height is joined.
resolve_drag_cell :: proc(world: ^World, registry: Block_Registry, from: World_Coordinate, column: [2]i32) -> (cell: World_Coordinate, ok: bool) {
	level := World_Coordinate{column.x, from.y, column.y}
	candidates := [3]World_Coordinate{level, level + UP, level - UP}
	for candidate in candidates {
		if belt_at(&world.entities, candidate) != nil {
			return candidate, true
		}
	}
	if cell_is_free(world, level) {
		if belt_cell_supported(world, registry, level, .Flat) {
			return level, true
		}
		down := level - UP
		return down, cell_is_free(world, down) && belt_cell_supported(world, registry, down, .Flat)
	}
	up := level + UP
	return up, cell_is_free(world, up) && belt_cell_supported(world, registry, up, .Flat)
}

// A belt whose items come out into the cell, or nil.
belt_feeding_cell :: proc(entities: ^Entities, cell: World_Coordinate) -> ^Belt {
	for direction in u8(0) ..< 4 {
		behind := cell - belt_direction_offset(direction)
		for candidate in ([2]World_Coordinate{behind, behind - UP}) {
			belt := belt_at(entities, candidate)
			if belt != nil && belt_output_cell(belt^) == cell {
				return belt
			}
		}
	}
	return nil
}

// A ramp with a block behind it and none in front descends away from the
// block; any other ramp rises in its direction.
single_ramp_shape :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate, direction: u8) -> Belt_Shape {
	forward := belt_direction_offset(direction)
	behind_solid := block_is_solid(registry, world_get_block(world, cell - forward))
	ahead_solid := block_is_solid(registry, world_get_block(world, cell + forward))
	return behind_solid && !ahead_solid ? .Ramp_Down : .Ramp_Up
}

belt_rotation_count :: proc(item_shape: Belt_Item_Shape) -> u8 {
	return item_shape == .Lift ? LIFT_ROTATION_COUNT : 4
}

// Direction and shape of a single belt placed at the cell.
single_belt_plan :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate, item_shape: Belt_Item_Shape, yaw: f32, rotation: u8) -> Planned_Belt {
	plan := Planned_Belt{cell = cell, direction = turn_right(yaw_direction(yaw), rotation % 4), shape = default_belt_shape(item_shape)}
	switch item_shape {
	case .Flat:
		if feeder := belt_feeding_cell(&world.entities, cell); feeder != nil {
			plan.direction = feeder.rotation
		}
	case .Ramp:
		plan.shape = single_ramp_shape(world, registry, cell, plan.direction)
	case .Lift:
		below := belt_at(&world.entities, cell - UP)
		if below != nil && belt_shape_is_lift(below.shape) {
			plan.direction, plan.shape = below.rotation, below.shape
		} else if rotation >= 4 {
			plan.shape = .Lift_Down
		}
	}
	return plan
}

// The ghost of a belt: no player check, belts are walked over.
belt_placement_for_player :: proc(world: ^World, content: Simulation_Content, player: Player, machine: Machine_Id) -> Placement {
	cell := player.target.adjacent
	item_shape := content.machines.machines[machine].belt_shape
	plan := single_belt_plan(world, content.blocks, cell, item_shape, player.yaw, player.placement_rotation)
	return Placement {
		shown = true,
		valid = cell_is_free(world, cell) && belt_cell_supported(world, content.blocks, cell, plan.shape),
		machine = machine,
		origin = cell,
		rotation = plan.direction,
		size = {1, 1, 1},
		belt = true,
		belt_shape = plan.shape,
	}
}

// The first belt machine placed by items of a shape family.
find_belt_machine :: proc(machines: Machine_Registry, item_shape: Belt_Item_Shape) -> Machine_Id {
	for machine, index in machines.machines {
		if machine.kind == .Belt && machine.belt_shape == item_shape {
			return Machine_Id(index)
		}
	}
	return NO_MACHINE
}

// The belt machine of a shape family in the tier of the given speed, so a
// fast belt run gets fast ramps.
find_belt_machine_of_speed :: proc(machines: Machine_Registry, item_shape: Belt_Item_Shape, speed: u32) -> Machine_Id {
	for machine, index in machines.machines {
		if machine.kind == .Belt && machine.belt_shape == item_shape && machine.belt_speed_units_per_second == speed {
			return Machine_Id(index)
		}
	}
	return NO_MACHINE
}

belt_shape_item_shape :: proc(shape: Belt_Shape) -> Belt_Item_Shape {
	switch shape {
	case .Flat:
		return .Flat
	case .Ramp_Up, .Ramp_Down:
		return .Ramp
	case .Lift_Up, .Lift_Down:
		return .Lift
	}
	return .Flat
}

// Takes the item of the planned shape in the tier of `speed` from the
// inventory and places the belt. A ramp without a ramp item of that tier
// in the inventory is placed flat.
place_planned_belt :: proc(world: ^World, content: Simulation_Content, player: ^Player, planned: Planned_Belt, speed: u32) -> (handle: Entity_Handle, ok: bool) {
	plan := planned
	machine := find_belt_machine_of_speed(content.machines, belt_shape_item_shape(plan.shape), speed)
	if machine == NO_MACHINE || inventory_count(player.inventory, content.machines.machines[machine].item) == 0 {
		plan.shape = .Flat
		machine = find_belt_machine_of_speed(content.machines, .Flat, speed)
	}
	if machine == NO_MACHINE || !cell_is_free(world, plan.cell) || !belt_cell_supported(world, content.blocks, plan.cell, plan.shape) {
		return NO_ENTITY, false
	}
	if inventory_remove(player.inventory, content.machines.machines[machine].item, 1) != 1 {
		return NO_ENTITY, false
	}
	handle = add_belt(&world.entities, content.machines, machine, plan.cell, plan.direction, plan.shape)
	record_placed(&world.statistics, machine)
	return handle, true
}

// Turns the previous belt of a drag, and makes it a ramp when a ramp item
// is at hand (the flat belt it replaces goes back to the inventory).
update_dragged_belt :: proc(world: ^World, content: Simulation_Content, player: ^Player, handle: Entity_Handle, updated: Planned_Belt) {
	belt := pool_get(&world.entities.belts, handle)
	if belt == nil {
		return
	}
	machine, shape := belt.machine, updated.shape
	if shape != belt.shape && !swap_belt_item(player, content, belt.machine, &machine) {
		shape = belt.shape
	}
	reshape_belt(&world.entities, content.machines, handle, machine, updated.direction, shape)
}

// Exchanges the item of `current` for one of the ramp machine of the same
// tier in the inventory. False when there is no ramp item or no room.
swap_belt_item :: proc(player: ^Player, content: Simulation_Content, current: Machine_Id, replacement: ^Machine_Id) -> bool {
	ramp := find_belt_machine_of_speed(content.machines, .Ramp, content.machines.machines[current].belt_speed_units_per_second)
	if ramp == NO_MACHINE {
		return false
	}
	ramp_item, current_item := content.machines.machines[ramp].item, content.machines.machines[current].item
	if inventory_remove(player.inventory, ramp_item, 1) != 1 {
		return false
	}
	if inventory_add(player.inventory, content.items, current_item, 1) > 0 {
		inventory_add(player.inventory, content.items, ramp_item, 1)
		return false
	}
	replacement^ = ramp
	return true
}

// One step of the drag into the resolved cell, placing belts of the tier
// of `speed`.
apply_drag_step :: proc(world: ^World, content: Simulation_Content, player: ^Player, cell: World_Coordinate, speed: u32) -> bool {
	drag := &player.belt_drag
	previous := pool_get(&world.entities.belts, drag.last)
	if previous == nil {
		return false
	}
	planned := Planned_Belt{cell = previous.origin, direction = previous.rotation, shape = previous.shape}
	updated, next := belt_drag_step(planned, cell)
	if drag.last_placed && updated != planned {
		update_dragged_belt(world, content, player, drag.last, updated)
	}
	if existing := belt_at(&world.entities, cell); existing != nil {
		drag.last, drag.last_cell, drag.last_placed = existing.handle, cell, false
		return true
	}
	handle, placed := place_planned_belt(world, content, player, next, speed)
	if !placed {
		return false
	}
	drag.last, drag.last_cell, drag.last_placed = handle, cell, true
	return true
}

// The column the reticle points at: the targeted belt's, or the cell in
// front of the targeted face.
drag_target_column :: proc(target: Raycast_Hit) -> [2]i32 {
	cell := target.adjacent
	if target.entity.kind == .Belt {
		cell = target.block
	}
	return {cell.x, cell.z}
}

continue_belt_drag :: proc(world: ^World, content: Simulation_Content, player: ^Player, machine: Machine_Id) {
	if !player.target.hit {
		return
	}
	drag := &player.belt_drag
	column := drag_target_column(player.target)
	from := [2]i32{drag.last_cell.x, drag.last_cell.z}
	if column == from {
		return
	}
	last := pool_get(&world.entities.belts, drag.last)
	x_first := last == nil || belt_direction_offset(last.rotation).x != 0
	columns := belt_drag_columns(from, column, x_first)
	for step in columns[:min(len(columns), MAXIMUM_DRAG_STEPS_PER_TICK)] {
		cell, ok := resolve_drag_cell(world, content.blocks, drag.last_cell, step)
		if !ok || !apply_drag_step(world, content, player, cell, content.machines.machines[machine].belt_speed_units_per_second) {
			return
		}
	}
}

// Place pressed: start on the targeted belt, or place the first belt.
start_belt_drag :: proc(world: ^World, content: Simulation_Content, players: []Player, index: int, machine: Machine_Id) {
	player := &players[index]
	item_shape := content.machines.machines[machine].belt_shape
	if player.target.entity.kind == .Belt && item_shape == .Flat {
		player.belt_drag = Belt_Drag{active = true, last = player.target.entity, last_cell = player.target.block}
		return
	}
	placement := belt_placement_for_player(world, content, player^, machine)
	if !placement.valid {
		return
	}
	plan := Planned_Belt{cell = placement.origin, direction = placement.rotation, shape = placement.belt_shape}
	handle, placed := place_planned_belt(world, content, player, plan, content.machines.machines[machine].belt_speed_units_per_second)
	if placed && item_shape == .Flat {
		player.belt_drag = Belt_Drag{active = true, last = handle, last_cell = plan.cell, last_placed = true}
	}
}

place_belt_with_player :: proc(world: ^World, content: Simulation_Content, players: []Player, index: int, machine: Machine_Id, just_pressed, pressed: Action_Set) {
	player := &players[index]
	if .Rotate_Building in just_pressed {
		count := belt_rotation_count(content.machines.machines[machine].belt_shape)
		player.placement_rotation = (player.placement_rotation + 1) % count
	}
	switch {
	case .Place in just_pressed:
		player.belt_drag = {}
		start_belt_drag(world, content, players, index, machine)
	case .Place in pressed && player.belt_drag.active:
		continue_belt_drag(world, content, player, machine)
	case .Place not_in pressed:
		player.belt_drag = {}
	}
}

// Rotate with no machine selected turns the targeted belt a quarter turn,
// a lift together with its column.
rotate_targeted_belt :: proc(world: ^World, content: Simulation_Content, player: ^Player) {
	belt := pool_get(&world.entities.belts, player.target.entity)
	if belt == nil {
		return
	}
	column := make([dynamic]Entity_Handle, context.temp_allocator)
	append(&column, belt.handle)
	if belt_shape_is_lift(belt.shape) {
		for step in ([2]World_Coordinate{UP, -UP}) {
			for next := matching_lift(&world.entities, belt^, belt.origin + step); next != nil; next = matching_lift(&world.entities, next^, next.origin + step) {
				append(&column, next.handle)
			}
		}
	}
	direction := turn_right(belt.rotation)
	for handle in column {
		member := pool_get(&world.entities.belts, handle)
		reshape_belt(&world.entities, content.machines, handle, member.machine, direction, member.shape)
	}
	record_world_action(&world.statistics)
}

// F7: one iron plate onto the targeted belt's lane on the player's side.
debug_drop_item_on_belt :: proc(world: ^World, content: Simulation_Content, player: Player) -> bool {
	belt := pool_get(&world.entities.belts, player.target.entity)
	plate, found := find_item_id(content.items, "iron_plate")
	if belt == nil || !found {
		return false
	}
	return belt_insert_item(&world.entities, belt.handle, belt_near_lane(belt^, player.position), plate)
}

// The lane on the side of the belt the point is on.
belt_near_lane :: proc(belt: Belt, point: [3]f32) -> Belt_Lane {
	right := belt_direction_offset(turn_right(belt.rotation))
	centre := block_centre(belt.origin)
	side := (point.x - centre.x) * f32(right.x) + (point.z - centre.z) * f32(right.z)
	return side > 0 ? .Right : .Left
}
