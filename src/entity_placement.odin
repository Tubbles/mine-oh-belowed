package game

// Placing machines from the hotbar with a rotated footprint, and picking
// them up again. The ghost the renderer shows is the same Placement the
// place action checks, so what is shown valid is what places.

Placement :: struct {
	// A machine is selected and the ray hit something to place it against.
	shown:      bool,
	valid:      bool,
	machine:    Machine_Id,
	origin:     World_Coordinate,
	rotation:   u8,
	// Rotated footprint, x y z.
	size:       [3]i32,
	// A belt: rotation is its direction (belt_placement.odin).
	belt:       bool,
	belt_shape: Belt_Shape,
	// An inserter: rotation is its drop direction.
	inserter:   bool,
	// A drill: rotation is its output direction, vein the vein it taps.
	drill:      bool,
	vein:       Vein_Id,
	// A splitter: rotation is its direction.
	splitter:   bool,
}

// The footprint's minimum corner, so that it starts at the cell in front
// of the targeted face and extends away from it. On a top face it stands
// on the face; on a side face its bottom is level with the adjacent cell;
// across the face it is centred on the adjacent cell.
footprint_origin :: proc(adjacent: World_Coordinate, face: Direction, size: [3]i32) -> World_Coordinate {
	normal := direction_offsets[face]
	origin := adjacent
	for axis in 0 ..< 3 {
		switch {
		case normal[axis] < 0:
			origin[axis] = adjacent[axis] - (size[axis] - 1)
		case normal[axis] > 0 || axis == 1:
			origin[axis] = adjacent[axis]
		case:
			origin[axis] = adjacent[axis] - (size[axis] - 1) / 2
		}
	}
	return origin
}

// Air in a loaded chunk, with no entity in it.
cell_is_free :: proc(world: ^World, cell: World_Coordinate) -> bool {
	if world_to_chunk_coordinate(cell) not_in world.chunks {
		return false
	}
	return world_get_block(world, cell) == AIR_BLOCK && cell not_in world.entities.cells
}

// Every cell of the bottom layer rests on a solid block. Entities do not
// count as support, so picking one up never leaves another floating.
footprint_is_supported :: proc(world: ^World, registry: Block_Registry, cells: []World_Coordinate, bottom: i32) -> bool {
	for cell in cells {
		if cell.y == bottom && !block_is_solid(registry, world_get_block(world, cell + {0, -1, 0})) {
			return false
		}
	}
	return true
}

footprint_hits_player :: proc(players: []Player, cells: []World_Coordinate) -> bool {
	for player in players {
		for cell in cells {
			if boxes_overlap(player_box(player.position), block_box(cell)) {
				return true
			}
		}
	}
	return false
}

footprint_is_valid :: proc(world: ^World, registry: Block_Registry, players: []Player, cells: []World_Coordinate, bottom: i32) -> bool {
	for cell in cells {
		if !cell_is_free(world, cell) {
			return false
		}
	}
	return footprint_is_supported(world, registry, cells, bottom) && !footprint_hits_player(players, cells)
}

selected_placed_machine :: proc(player: Player, machines: Machine_Registry) -> Machine_Id {
	stack := selected_hotbar_stack(player)
	if stack_is_empty(stack) {
		return NO_MACHINE
	}
	return item_places_machine(machines, stack.item)
}

// The ghost for the player's selected hotbar item and current target.
placement_for_player :: proc(world: ^World, content: Simulation_Content, players: []Player, index: int) -> Placement {
	player := players[index]
	machine := selected_placed_machine(player, content.machines)
	if machine == NO_MACHINE || !player.target.hit {
		return {}
	}
	if content.machines.machines[machine].kind == .Belt {
		return belt_placement_for_player(world, content, player, machine)
	}
	kind := content.machines.machines[machine].kind
	rotation := player.placement_rotation
	if kind == .Inserter || kind == .Drill || kind == .Splitter || kind == .Offshore_Pump || kind == .Pump {
		rotation = inserter_placement_direction(player.yaw, player.placement_rotation)
	}
	if kind == .Splitter {
		// Walked over like belts, so the player may stand in the way.
		return placement_at(world, content, players[:0], machine, splitter_origin(player.target.adjacent, rotation), rotation)
	}
	size := rotated_footprint_size(content.machines.machines[machine].footprint, rotation)
	origin := footprint_origin(player.target.adjacent, player.target.face, size)
	return placement_at(world, content, players, machine, origin, rotation)
}

// The placement of a machine with its rotated minimum corner at origin.
// A drill is valid only over a vein outcrop, an offshore pump only with
// water in front of its intake. A pipe may also stand on a pipe.
placement_at :: proc(world: ^World, content: Simulation_Content, players: []Player, machine: Machine_Id, origin: World_Coordinate, rotation: u8) -> Placement {
	footprint := content.machines.machines[machine].footprint
	kind := content.machines.machines[machine].kind
	cells := footprint_cells(origin, footprint, rotation)
	placement := Placement {
		shown    = true,
		valid    = footprint_is_valid(world, content.blocks, players, cells, origin.y),
		machine  = machine,
		origin   = origin,
		rotation = rotation,
		size     = rotated_footprint_size(footprint, rotation),
		inserter = kind == .Inserter,
		drill    = kind == .Drill,
		splitter = kind == .Splitter,
	}
	if placement.drill {
		vein_found: bool
		placement.vein, vein_found = drill_vein_under(world, content.veins, cells, origin.y)
		placement.valid = placement.valid && vein_found
	}
	if kind == .Pipe {
		placement.valid = pipe_cell_is_placeable(world, content.blocks, players, origin)
	}
	if kind == .Offshore_Pump {
		placement.valid = placement.valid && offshore_pump_has_water(world, content.blocks, origin, content.machines.machines[machine], rotation)
	}
	return placement
}

// Like belts: the player's facing turned by the rotation, so rotation 0
// drops away from the player and picks up from the player's side. Drills
// use it for their output arrow, splitters, pumps and offshore pumps for
// their direction too.
inserter_placement_direction :: proc(yaw: f32, rotation: u8) -> u8 {
	return turn_right(yaw_direction(yaw), rotation % 4)
}

// Rotate_Building turns the ghost a quarter turn; Place puts the machine
// down and uses up one item. Belts also follow the held Place.
place_entity_with_player :: proc(world: ^World, content: Simulation_Content, players: []Player, index: int, just_pressed, pressed: Action_Set) {
	player := &players[index]
	if machine := selected_placed_machine(player^, content.machines); content.machines.machines[machine].kind == .Belt {
		place_belt_with_player(world, content, players, index, machine, just_pressed, pressed)
		return
	}
	if .Rotate_Building in just_pressed {
		player.placement_rotation = (player.placement_rotation + 1) % 4
	}
	if .Place not_in just_pressed {
		return
	}
	placement := placement_for_player(world, content, players, index)
	if !placement.valid {
		return
	}
	handle := add_entity(&world.entities, content.machines, placement.machine, placement.origin, placement.rotation)
	if drill := pool_get(&world.entities.drills, handle); drill != nil {
		drill.vein = placement.vein
	}
	take_from_slot(&inventory_hotbar(player.inventory)[player.selected_hotbar_slot], 1)
	record_placed(&world.statistics, placement.machine)
}

// Rotate with no machine item selected turns the targeted belt, inserter
// or drill a quarter turn. A drill's footprint is square, so no cell moves.
// A splitter turns half way round on its two cells.
rotate_targeted_entity :: proc(world: ^World, content: Simulation_Content, player: ^Player) -> bool {
	#partial switch player.target.entity.kind {
	case .Belt:
		rotate_targeted_belt(world, content, player)
		return true
	case .Splitter:
		rotate_splitter(&world.entities, content.machines, player.target.entity)
		record_world_action(&world.statistics)
		return true
	case .Inserter, .Drill:
		common := entity_common(&world.entities, player.target.entity)
		if common == nil {
			return false
		}
		common.rotation = turn_right(common.rotation)
		record_world_action(&world.statistics)
		return true
	}
	return false
}

// Only entities placed by an item can be picked up (not the capsule).
entity_can_be_picked_up :: proc(world: ^World, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	common := entity_common(&world.entities, handle)
	return common != nil && machines.machines[common.machine].item != NO_ITEM
}

// The entity's contents and then its item go into the inventory. When not
// everything fits nothing moves and the entity stays.
pick_up_entity :: proc(world: ^World, content: Simulation_Content, player: ^Player, handle: Entity_Handle) -> bool {
	if !entity_can_be_picked_up(world, content.machines, handle) {
		return false
	}
	common := entity_common(&world.entities, handle)
	machine_item := content.machines.machines[common.machine].item
	returned := make([dynamic]Item_Stack, context.temp_allocator)
	append(&returned, ..entity_slots(&world.entities, handle))
	append(&returned, ..belt_block_stacks(&world.entities, handle))
	append(&returned, ..inserter_held_stacks(&world.entities, handle))
	append(&returned, ..drill_held_stacks(&world.entities, handle))
	append(&returned, ..splitter_held_stacks(&world.entities, handle))
	if assembler := pool_get(&world.entities.assemblers, handle); assembler != nil {
		append(&returned, ..assembler_held_stacks(assembler^, content.recipes))
	}
	append(&returned, Item_Stack{item = machine_item, count = 1})
	if !inventory_fits_all(player.inventory, content.items, returned[:]) {
		return false
	}
	for stack in returned {
		if !stack_is_empty(stack) {
			inventory_add(player.inventory, content.items, stack.item, int(stack.count))
		}
	}
	record_world_action(&world.statistics)
	return remove_entity(&world.entities, content.machines, handle)
}
