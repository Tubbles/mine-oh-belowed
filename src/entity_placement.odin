package game

// Placing machines from the hotbar with a rotated footprint, and picking
// them up again. The ghost the renderer shows is the same Placement the
// place action checks, so what is shown valid is what places.

Placement :: struct {
	// A machine is selected and the ray hit something to place it against.
	shown:        bool,
	valid:        bool,
	machine:      Machine_Id,
	origin:       World_Coordinate,
	rotation:     u8,
	// Rotated footprint, x y z.
	size:         [3]i32,
	// A belt: rotation is its direction (belt_placement.odin).
	belt:         bool,
	belt_shape:   Belt_Shape,
	// An inserter: rotation is its drop direction.
	inserter:     bool,
	// A drill: rotation is its output direction, vein the vein it taps.
	// no_deep_vein marks a bore drill refused only for the missing vein.
	drill:        bool,
	vein:         Vein_Id,
	no_deep_vein: bool,
	// A splitter: rotation is its direction.
	splitter:     bool,
	// Ground cover stands in the footprint (work item 0082), which
	// commit_placement clears.
	clears_cover: bool,
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
	return world_get_block(world, cell) == AIR_BLOCK && !frame_cell_is_occupied(&world.entities.frames, BLOCK_FRAME, cell)
}

// Free, or ground cover with no entity in it, which a machine replaces
// (work item 0082).
cell_takes_machine :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	return cell_is_free(world, cell) || (cell_holds_cover(world, registry, cell) && !frame_cell_is_occupied(&world.entities.frames, BLOCK_FRAME, cell))
}

cell_holds_cover :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	return block_shape(registry, world_get_block(world, cell)) == .Cross
}

footprint_holds_cover :: proc(world: ^World, registry: Block_Registry, cells: []World_Coordinate) -> bool {
	for cell in cells {
		if cell_holds_cover(world, registry, cell) {
			return true
		}
	}
	return false
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
		if !cell_takes_machine(world, registry, cell) {
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
	if kind == .Inserter || kind == .Drill || kind == .Splitter || kind == .Offshore_Pump || kind == .Pump || kind == .Tar_Pit_Pump {
		rotation = inserter_placement_direction(player.yaw, player.placement_rotation)
	}
	if kind == .Splitter {
		// Walked over like belts, so the player may stand in the way.
		target := placement_target(content.blocks, world_get_block(world, player.target.block), player.target)
		return placement_at(world, content, players[:0], machine, splitter_origin(target.adjacent, rotation), rotation)
	}
	target := placement_target(content.blocks, world_get_block(world, player.target.block), player.target)
	size := rotated_footprint_size(content.machines.machines[machine].footprint, rotation)
	origin := footprint_origin(target.adjacent, target.face, size)
	return placement_at(world, content, players, machine, origin, rotation)
}

// The placement of a machine with its rotated minimum corner at origin.
// A drill is valid only over a surface vein's footprint (a bore drill over a deep
// vein's disc, work item 0035), an offshore pump only with
// water in front of its intake, a tar pit pump only with a tar pit there,
// a hydro turbine only in flowing water (work item 0037).
// A pipe may also stand on a pipe.
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
		clears_cover = footprint_holds_cover(world, content.blocks, cells),
	}
	if placement.drill {
		vein_found: bool
		if drill_is_bore(content.machines.machines[machine]) {
			placement.vein, vein_found = bore_drill_vein_under(world, origin, placement.size)
		} else {
			placement.vein, vein_found = drill_vein_under(world, cells, origin.y)
		}
		placement.no_deep_vein = placement.valid && !vein_found && drill_is_bore(content.machines.machines[machine])
		placement.valid = placement.valid && vein_found
	}
	if kind == .Pipe {
		placement.valid = pipe_cell_is_placeable(world, content.blocks, players, origin)
	}
	if kind == .Offshore_Pump {
		placement.valid = placement.valid && offshore_pump_has_water(world, content.blocks, origin, content.machines.machines[machine], rotation)
	}
	if kind == .Tar_Pit_Pump {
		placement.valid = placement.valid && tar_pit_pump_has_source(world, content.blocks, content.fluids, origin, content.machines.machines[machine], rotation)
	}
	if kind == .Hydro_Turbine {
		placement.valid = hydro_turbine_is_placeable(world, content.blocks, players, cells, origin.y, content.machines.machines[machine])
	}
	return placement
}

// Loaded, no entity, and air or water: a turbine stands in the stream.
cell_takes_hydro_turbine :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	if world_to_chunk_coordinate(cell) not_in world.chunks || frame_cell_is_occupied(&world.entities.frames, BLOCK_FRAME, cell) {
		return false
	}
	block := world_get_block(world, cell)
	return block == AIR_BLOCK || block_water_level(registry, block) > 0
}

// On solid ground like any machine, clear of the players, with flowing
// water of the minimum level in one of its cells.
hydro_turbine_is_placeable :: proc(world: ^World, registry: Block_Registry, players: []Player, cells: []World_Coordinate, bottom: i32, machine: Machine) -> bool {
	for cell in cells {
		if !cell_takes_hydro_turbine(world, registry, cell) {
			return false
		}
	}
	supported := footprint_is_supported(world, registry, cells, bottom) && !footprint_hits_player(players, cells)
	return supported && cells_hold_flowing_water(world, registry, cells, machine.hydro_minimum_water_level)
}

// Like belts: the player's facing turned by the rotation, so rotation 0
// drops away from the player and picks up from the player's side. Drills
// use it for their output arrow, splitters, pumps and offshore pumps for
// their direction too.
inserter_placement_direction :: proc(yaw: f32, rotation: u8) -> u8 {
	return turn_right(yaw_direction(yaw), rotation % 4)
}

// The deep vein the ghost of a selected bore drill would tap, found the
// way placement_for_player places the footprint. selected is false unless
// a bore drill is selected and the ray hit something.
bore_drill_ghost_vein :: proc(world: ^World, machines: Machine_Registry, player: Player) -> (vein: Vein_Id, found, selected: bool) {
	machine := selected_placed_machine(player, machines)
	if machine == NO_MACHINE || !player.target.hit || !drill_is_bore(machines.machines[machine]) {
		return {}, false, false
	}
	rotation := inserter_placement_direction(player.yaw, player.placement_rotation)
	size := rotated_footprint_size(machines.machines[machine].footprint, rotation)
	origin := footprint_origin(player.target.adjacent, player.target.face, size)
	vein, found = bore_drill_vein_under(world, origin, size)
	return vein, found, true
}

// Rotate_Building turns the ghost a quarter turn; Place puts the machine
// down and uses up one item. Belts also follow the held Place.
place_entity_with_player :: proc(world: ^World, statistics: ^Statistics, content: Simulation_Content, players: []Player, index: int, just_pressed, pressed: Action_Set) {
	player := &players[index]
	if machine := selected_placed_machine(player^, content.machines); content.machines.machines[machine].kind == .Belt {
		place_belt_with_player(world, statistics, content, players, index, machine, just_pressed, pressed)
		return
	}
	if .Rotate_Building in just_pressed {
		player.placement_rotation = (player.placement_rotation + 1) % 4
	}
	if .Place not_in just_pressed {
		return
	}
	placement := placement_for_player(world, content, players, index)
	if placement.no_deep_vein {
		statistics.bore_drill_no_vein_attempts += 1
	}
	if !placement.valid {
		return
	}
	commit_placement(world, content.machines, placement)
	take_from_slot(&inventory_hotbar(player.inventory)[player.selected_hotbar_slot], 1)
	record_placed(statistics, placement.machine)
}

// Puts a valid placement's machine down: a belt with its planned shape
// (loose items in its cell go onto it), a drill tapping the vein under
// it, any other machine lifting loose items in its cells onto its top. The player's Place and the developer
// command `place` (work item 0053) both end here.
commit_placement :: proc(world: ^World, machines: Machine_Registry, placement: Placement) -> Entity_Handle {
	cells := footprint_cells(placement.origin, machines.machines[placement.machine].footprint, placement.rotation)
	if placement.clears_cover {
		clear_cover_from(world, cells)
	}
	if placement.belt {
		return add_belt(&world.entities, machines, placement.machine, placement.origin, placement.rotation, placement.belt_shape)
	}
	handle := add_entity(&world.entities, machines, placement.machine, placement.origin, placement.rotation)
	lift_loose_items_out_of(&world.entities.loose_items, cells, placement.origin.y + placement.size.y)
	if drill := pool_get(&world.entities.drills, handle); drill != nil {
		drill.vein = placement.vein
	}
	return handle
}

// A drill on a frame (work item 0179) taps the vein on the sphere under
// its footprint: the first bottom cell, in footprint order, whose centre
// (the frame's transform of the cell) lies on a vein's disc
// (vein_under_world_position). A bore drill finds none, since the sphere
// has no deep veins yet.
frame_drill_vein_under :: proc(frame: Frame, veins: []Vein, machine: Machine, origin: World_Coordinate, rotation: u8) -> (vein: Vein_Id, found: bool) {
	if drill_is_bore(machine) {
		return {}, false
	}
	for cell in footprint_cells(origin, machine.footprint, rotation) {
		if cell.y != origin.y {
			continue
		}
		if vein, found = vein_under_world_position(veins, frame_cell_centre(frame, cell)); found {
			return
		}
	}
	return {}, false
}

// A drill placed on a frame as place_on_frame places a machine, tapping
// the vein under it. With no vein under any bottom cell it is refused, as
// a block world drill off a vein is: vein_found is false and nothing is
// placed.
place_drill_on_frame :: proc(entities: ^Entities, machines: Machine_Registry, veins: []Vein, machine: Machine_Id, frame: Frame_Id, origin: World_Coordinate, rotation: u8) -> (handle: Entity_Handle, refusal: Frame_Placement_Refusal, vein_found: bool) {
	record, frame_found := find_frame(&entities.frames, frame)
	if !frame_found {
		return NO_ENTITY, .Unknown_Frame, false
	}
	vein: Vein_Id
	if vein, vein_found = frame_drill_vein_under(record, veins, machines.machines[machine], origin, rotation); !vein_found {
		return NO_ENTITY, .None, false
	}
	if handle, refusal = place_on_frame(entities, machines, machine, frame, origin, rotation); refusal == .None {
		pool_get(&entities.drills, handle).vein = vein
	}
	return handle, refusal, true
}

// A valid placement's footprint holds only air and ground cover
// (cell_takes_machine; hydro turbines refuse cover), so every block left
// in it is cover.
clear_cover_from :: proc(world: ^World, cells: []World_Coordinate) {
	for cell in cells {
		if world_get_block(world, cell) != AIR_BLOCK {
			world_set_block(world, cell, AIR_BLOCK)
		}
	}
}

// The placement of a machine given by its minimum corner and rotation,
// as the developer command `place` asks for it: the rules of the
// player's ghost, with the rotation as the direction where the player's
// facing would set it (belts, inserters, drills, splitters, pumps).
command_placement :: proc(world: ^World, content: Simulation_Content, players: []Player, machine: Machine_Id, origin: World_Coordinate, rotation: u8) -> Placement {
	definition := content.machines.machines[machine]
	#partial switch definition.kind {
	case .Belt:
		return command_belt_placement(world, content, machine, origin, rotation)
	case .Splitter:
		// Walked over like belts, so the player may stand in the way.
		return placement_at(world, content, players[:0], machine, origin, rotation)
	}
	return placement_at(world, content, players, machine, origin, rotation)
}

// A belt of the machine's shape family pointing in the rotation; a lift
// with a rotation from 4 goes down, a ramp descends away from a block
// behind it like a placed one.
command_belt_placement :: proc(world: ^World, content: Simulation_Content, machine: Machine_Id, cell: World_Coordinate, rotation: u8) -> Placement {
	item_shape := content.machines.machines[machine].belt_shape
	shape := default_belt_shape(item_shape)
	direction := rotation % 4
	switch item_shape {
	case .Flat:
	case .Ramp:
		shape = single_ramp_shape(world, content.blocks, cell, direction)
	case .Lift:
		if rotation >= 4 {
			shape = .Lift_Down
		}
	}
	return Placement {
		shown = true,
		valid = cell_takes_machine(world, content.blocks, cell) && belt_cell_supported(world, content.blocks, cell, shape),
		machine = machine,
		origin = cell,
		rotation = direction,
		size = {1, 1, 1},
		belt = true,
		belt_shape = shape,
		clears_cover = cell_holds_cover(world, content.blocks, cell),
	}
}

// The entities rotate_targeted_entity turns (the touch overlay's rotate
// button shows for them, 0134).
entity_rotates :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	#partial switch handle.kind {
	case .Belt, .Splitter:
		return true
	case .Inserter, .Drill:
		return entity_common(entities, handle) != nil
	}
	return false
}

// Rotate with no machine item selected turns the targeted belt, inserter
// or drill a quarter turn. A drill's footprint is square, so no cell moves,
// but its revival port does, so its fluid networks are rebuilt.
// A splitter turns half way round on its two cells.
rotate_targeted_entity :: proc(world: ^World, statistics: ^Statistics, content: Simulation_Content, player: ^Player) -> bool {
	if !entity_rotates(&world.entities, player.target.entity) {
		return false
	}
	#partial switch player.target.entity.kind {
	case .Belt:
		rotate_targeted_belt(world, statistics, content, player)
		return true
	case .Splitter:
		rotate_splitter(&world.entities, content.machines, player.target.entity)
		record_world_action(statistics)
		return true
	case .Inserter, .Drill:
		common := entity_common(&world.entities, player.target.entity)
		if common == nil {
			return false
		}
		common.rotation = turn_right(common.rotation)
		if content.machines.machines[common.machine].fluid_port_count > 0 {
			rebuild_fluid_networks(&world.entities, content.machines)
		}
		record_world_action(statistics)
		return true
	}
	return false
}

// Only entities placed by an item can be picked up (not the capsule).
entity_can_be_picked_up :: proc(world: ^World, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	common := entity_common(&world.entities, handle)
	return common != nil && machines.machines[common.machine].item != NO_ITEM
}

// The entity's contents and then its item, in the temp allocator.
entity_pickup_stacks :: proc(world: ^World, content: Simulation_Content, handle: Entity_Handle) -> []Item_Stack {
	returned := make([dynamic]Item_Stack, context.temp_allocator)
	common := entity_common(&world.entities, handle)
	if common == nil {
		return returned[:]
	}
	machine_item := content.machines.machines[common.machine].item
	append(&returned, ..entity_slots(&world.entities, handle))
	append(&returned, ..belt_block_stacks(&world.entities, handle))
	append(&returned, ..inserter_held_stacks(&world.entities, handle))
	append(&returned, ..drill_held_stacks(&world.entities, handle))
	append(&returned, ..splitter_held_stacks(&world.entities, handle))
	if assembler := pool_get(&world.entities.assemblers, handle); assembler != nil {
		append(&returned, ..assembler_held_stacks(assembler^, content.machines.machines[assembler.machine], content.recipes))
	}
	if pad := pool_get(&world.entities.launch_pads, handle); pad != nil {
		append(&returned, ..launch_pad_held_stacks(pad^, content.machines.machines[pad.machine]))
	}
	append(&returned, Item_Stack{item = machine_item, count = 1})
	return returned[:]
}

// The entity's contents and then its item go into the inventory as far
// as they fit; the rest spills at the entity's origin once it is gone
// (loose_item.odin), so a full inventory never keeps an entity in place.
// Water is checked again in the cells the entity leaves.
pick_up_entity :: proc(world: ^World, statistics: ^Statistics, content: Simulation_Content, player: ^Player, handle: Entity_Handle, tick: u64) -> bool {
	if !entity_can_be_picked_up(world, content.machines, handle) {
		return false
	}
	common := entity_common(&world.entities, handle)^
	returned := entity_pickup_stacks(world, content, handle)
	if !remove_entity(&world.entities, content.machines, handle) {
		return false
	}
	schedule_water_around_freed_cells(world, content.blocks, common_cells(common, content.machines), tick)
	record_world_action(statistics)
	for stack in returned {
		if stack_is_empty(stack) {
			continue
		}
		if leftover := inventory_add_picked_up(player.inventory, content.items, stack.item, int(stack.count)); leftover > 0 {
			spill_stack(world, content.blocks, common.origin, Item_Stack{item = stack.item, count = u16(leftover)})
		}
	}
	return true
}
