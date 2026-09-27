package game

// Entities (doc/architecture.md, Simulation): typed pools with generational
// handles, one pool per type and no general component system. Entities are
// not blocks. The cells they occupy stay air in the chunk data, and the
// World's cell map holds the handle of the entity in each occupied cell, so
// the raycast, collision and placement checks are cell lookups. Light and
// water still treat those cells as air.
//
// Entity data is plain values (no pointers into chunks or other entities),
// so the pools are saved as they are (save_state.odin).

MAXIMUM_CHEST_SLOTS :: 48
CAPSULE_SLOT_COUNT :: 8

Entity_Kind :: enum u8 {
	None,
	Chest,
	Furnace,
	Capsule,
	Belt,
	Inserter,
	Drill,
	Splitter,
	Pipe,
	// Offshore pumps, boilers, steam engines, storage tanks and pumps
	// (fluid_machine.odin).
	Fluid_Machine,
	// Small poles and power switches (power_machine.odin).
	Pole,
	Lamp,
	// Crafting machines (assembler.odin) and labs (lab.odin).
	Assembler,
	Lab,
}

// index is into the pool of `kind`. Generations start at 1, so the zero
// handle (NO_ENTITY) never names a live entity.
Entity_Handle :: struct {
	kind:       Entity_Kind,
	index:      u32,
	generation: u32,
}

NO_ENTITY :: Entity_Handle{}

// Shared by every entity type. origin is the minimum corner of the
// footprint, size is the footprint after rotation (x, y, z), rotation
// counts quarter turns.
Entity_Common :: struct {
	handle:   Entity_Handle,
	machine:  Machine_Id,
	origin:   World_Coordinate,
	rotation: u8,
	size:     [3]i32,
	alive:    bool,
}

Chest :: struct {
	using common: Entity_Common,
	slot_count:   int,
	slots:        [MAXIMUM_CHEST_SLOTS]Item_Stack,
}

// The drop capsule on the landing pad (landing_pad.odin).
Capsule :: struct {
	using common: Entity_Common,
	slots:        [CAPSULE_SLOT_COUNT]Item_Stack,
}

// Freed entries stay in place with alive false and go on the free list;
// reuse bumps the generation, so old handles stop resolving.
Entity_Pool :: struct($T: typeid) {
	entries: [dynamic]T,
	free:    [dynamic]u32,
}

Entities :: struct {
	chests:         Entity_Pool(Chest),
	furnaces:       Entity_Pool(Furnace),
	capsules:       Entity_Pool(Capsule),
	belts:          Entity_Pool(Belt),
	inserters:      Entity_Pool(Inserter),
	drills:         Entity_Pool(Drill),
	splitters:      Entity_Pool(Splitter),
	pipes:          Entity_Pool(Pipe),
	fluid_machines: Entity_Pool(Fluid_Machine),
	poles:          Entity_Pool(Pole),
	lamps:          Entity_Pool(Lamp),
	assemblers:     Entity_Pool(Assembler),
	labs:           Entity_Pool(Lab),
	// Transport lines derived from the belts and splitters (belt.odin).
	belt_network:   Belt_Network,
	// Derived from the pipes and fluid ports (fluid_network.odin).
	fluid_networks: Fluid_Networks,
	// Derived from the poles and electric machines (power_network.odin).
	electric_networks: Electric_Networks,
	cells:          map[World_Coordinate]Entity_Handle,
}

pool_add :: proc(pool: ^Entity_Pool($T), kind: Entity_Kind, value: T) -> Entity_Handle {
	entry := value
	index := u32(len(pool.entries))
	generation := u32(1)
	if len(pool.free) > 0 {
		index = pop(&pool.free)
		generation = pool.entries[index].handle.generation + 1
	} else {
		append(&pool.entries, T{})
	}
	entry.handle = Entity_Handle{kind = kind, index = index, generation = generation}
	entry.alive = true
	pool.entries[index] = entry
	return entry.handle
}

// Nil for a stale or foreign handle.
pool_get :: proc(pool: ^Entity_Pool($T), handle: Entity_Handle) -> ^T {
	if int(handle.index) >= len(pool.entries) {
		return nil
	}
	entry := &pool.entries[handle.index]
	if !entry.alive || entry.handle != handle {
		return nil
	}
	return entry
}

pool_remove :: proc(pool: ^Entity_Pool($T), handle: Entity_Handle) -> bool {
	entry := pool_get(pool, handle)
	if entry == nil {
		return false
	}
	entry.alive = false
	append(&pool.free, handle.index)
	return true
}

destroy_pool :: proc(pool: ^Entity_Pool($T)) {
	delete(pool.entries)
	delete(pool.free)
}

destroy_entities :: proc(entities: ^Entities) {
	destroy_pool(&entities.chests)
	destroy_pool(&entities.furnaces)
	destroy_pool(&entities.capsules)
	destroy_pool(&entities.belts)
	destroy_pool(&entities.inserters)
	destroy_pool(&entities.drills)
	destroy_pool(&entities.splitters)
	destroy_pool(&entities.pipes)
	destroy_pool(&entities.fluid_machines)
	destroy_pool(&entities.poles)
	destroy_pool(&entities.lamps)
	destroy_pool(&entities.assemblers)
	destroy_pool(&entities.labs)
	destroy_belt_network(&entities.belt_network)
	destroy_fluid_networks(&entities.fluid_networks)
	destroy_electric_networks(&entities.electric_networks)
	delete(entities.cells)
}

entity_common :: proc(entities: ^Entities, handle: Entity_Handle) -> ^Entity_Common {
	switch handle.kind {
	case .None:
		return nil
	case .Chest:
		if chest := pool_get(&entities.chests, handle); chest != nil {
			return &chest.common
		}
	case .Furnace:
		if furnace := pool_get(&entities.furnaces, handle); furnace != nil {
			return &furnace.common
		}
	case .Capsule:
		if capsule := pool_get(&entities.capsules, handle); capsule != nil {
			return &capsule.common
		}
	case .Belt:
		if belt := pool_get(&entities.belts, handle); belt != nil {
			return &belt.common
		}
	case .Inserter:
		if inserter := pool_get(&entities.inserters, handle); inserter != nil {
			return &inserter.common
		}
	case .Drill:
		if drill := pool_get(&entities.drills, handle); drill != nil {
			return &drill.common
		}
	case .Splitter:
		if splitter := pool_get(&entities.splitters, handle); splitter != nil {
			return &splitter.common
		}
	case .Pipe:
		if pipe := pool_get(&entities.pipes, handle); pipe != nil {
			return &pipe.common
		}
	case .Fluid_Machine:
		if fluid_machine := pool_get(&entities.fluid_machines, handle); fluid_machine != nil {
			return &fluid_machine.common
		}
	case .Pole:
		if pole := pool_get(&entities.poles, handle); pole != nil {
			return &pole.common
		}
	case .Lamp:
		if lamp := pool_get(&entities.lamps, handle); lamp != nil {
			return &lamp.common
		}
	case .Assembler:
		if assembler := pool_get(&entities.assemblers, handle); assembler != nil {
			return &assembler.common
		}
	case .Lab:
		if lab := pool_get(&entities.labs, handle); lab != nil {
			return &lab.common
		}
	}
	return nil
}

// Belts have no panel: Interact does nothing on them.
entity_has_panel :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	return handle.kind != .Belt && entity_is_alive(entities, handle)
}

entity_is_alive :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	return entity_common(entities, handle) != nil
}

// The item slots of an entity, as a view into its pool entry. Valid until
// the pool grows.
entity_slots :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack {
	#partial switch handle.kind {
	case .Chest:
		if chest := pool_get(&entities.chests, handle); chest != nil {
			return chest.slots[:chest.slot_count]
		}
	case .Furnace:
		if furnace := pool_get(&entities.furnaces, handle); furnace != nil {
			return furnace.slots[:]
		}
	case .Capsule:
		if capsule := pool_get(&entities.capsules, handle); capsule != nil {
			return capsule.slots[:]
		}
	case .Inserter:
		if inserter := pool_get(&entities.inserters, handle); inserter != nil {
			return inserter.slots[:inserter.slot_count]
		}
	case .Drill:
		if drill := pool_get(&entities.drills, handle); drill != nil {
			return drill.slots[:drill.slot_count]
		}
	case .Fluid_Machine:
		if fluid_machine := pool_get(&entities.fluid_machines, handle); fluid_machine != nil {
			return fluid_machine.slots[:fluid_machine.slot_count]
		}
	case .Assembler:
		if assembler := pool_get(&entities.assemblers, handle); assembler != nil {
			return assembler.slots[:assembler_slot_count(assembler^)]
		}
	case .Lab:
		if lab := pool_get(&entities.labs, handle); lab != nil {
			return lab.slots[:lab.slot_count]
		}
	}
	return nil
}

entity_at :: proc(entities: ^Entities, cell: World_Coordinate) -> Entity_Handle {
	return entities.cells[cell] or_else NO_ENTITY
}

// Footprint rotation.

rotated_footprint_size :: proc(size: [3]i32, rotation: u8) -> [3]i32 {
	if rotation % 2 == 1 {
		return {size.z, size.y, size.x}
	}
	return size
}

// Where cell (x, z) of the unrotated width by depth footprint lands after
// `rotation` quarter turns, as an offset inside the rotated footprint.
rotate_footprint_cell :: proc(cell: [2]i32, width, depth: i32, rotation: u8) -> [2]i32 {
	switch rotation % 4 {
	case 1:
		return {depth - 1 - cell.y, cell.x}
	case 2:
		return {width - 1 - cell.x, depth - 1 - cell.y}
	case 3:
		return {cell.y, width - 1 - cell.x}
	}
	return cell
}

// Every cell of a footprint placed with its rotated minimum corner at
// origin, in the temp allocator.
footprint_cells :: proc(origin: World_Coordinate, footprint: [3]i32, rotation: u8) -> []World_Coordinate {
	cells := make([dynamic]World_Coordinate, 0, footprint.x * footprint.y * footprint.z, context.temp_allocator)
	for y in 0 ..< footprint.y {
		for z in 0 ..< footprint.z {
			for x in 0 ..< footprint.x {
				offset := rotate_footprint_cell({x, z}, footprint.x, footprint.z, rotation)
				append(&cells, origin + {offset.x, y, offset.y})
			}
		}
	}
	return cells[:]
}

common_cells :: proc(common: Entity_Common, machines: Machine_Registry) -> []World_Coordinate {
	return footprint_cells(common.origin, machines.machines[common.machine].footprint, common.rotation)
}

// Adding and removing.

make_entity_common :: proc(machines: Machine_Registry, machine: Machine_Id, origin: World_Coordinate, rotation: u8) -> Entity_Common {
	return Entity_Common {
		machine = machine,
		origin = origin,
		rotation = rotation % 4,
		size = rotated_footprint_size(machines.machines[machine].footprint, rotation),
	}
}

// The caller has checked that the footprint is free. A belt gets the
// default shape of its item (belt_placement.odin picks others), a drill
// no vein (place_entity_with_player sets the one under it).
add_entity :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, origin: World_Coordinate, rotation: u8) -> Entity_Handle {
	common := make_entity_common(machines, machine, origin, rotation)
	handle: Entity_Handle
	switch machines.machines[machine].kind {
	case .Belt:
		return add_belt(entities, machines, machine, origin, rotation, default_belt_shape(machines.machines[machine].belt_shape))
	case .Chest:
		chest := Chest{common = common, slot_count = machines.machines[machine].slot_count}
		for &slot in chest.slots {
			slot = EMPTY_STACK
		}
		handle = pool_add(&entities.chests, .Chest, chest)
	case .Furnace:
		handle = pool_add(&entities.furnaces, .Furnace, make_furnace(common))
	case .Capsule:
		capsule := Capsule{common = common}
		for &slot in capsule.slots {
			slot = EMPTY_STACK
		}
		handle = pool_add(&entities.capsules, .Capsule, capsule)
	case .Inserter:
		handle = pool_add(&entities.inserters, .Inserter, make_inserter(common, machines.machines[machine]))
	case .Drill:
		handle = pool_add(&entities.drills, .Drill, make_drill(common, {}, machines.machines[machine].slot_count))
	case .Splitter:
		return add_splitter(entities, machines, machine, origin, rotation)
	case .Pipe:
		handle = pool_add(&entities.pipes, .Pipe, make_pipe(common))
	case .Offshore_Pump, .Boiler, .Steam_Engine, .Storage_Tank, .Pump:
		handle = pool_add(&entities.fluid_machines, .Fluid_Machine, make_fluid_machine(common, machines.machines[machine]))
	case .Pole, .Power_Switch:
		handle = pool_add(&entities.poles, .Pole, make_pole(common))
	case .Lamp:
		handle = pool_add(&entities.lamps, .Lamp, make_lamp(common))
	case .Crafting_Machine:
		handle = pool_add(&entities.assemblers, .Assembler, make_assembler(common, machines.machines[machine]))
	case .Lab:
		handle = pool_add(&entities.labs, .Lab, make_lab(common, len(machines.lab_packs)))
	}
	for cell in footprint_cells(origin, machines.machines[machine].footprint, rotation) {
		entities.cells[cell] = handle
	}
	if handle.kind == .Pipe || machines.machines[machine].fluid_port_count > 0 {
		rebuild_fluid_networks(entities, machines)
	}
	if machine_touches_power(machines.machines[machine]) {
		rebuild_electric_networks(entities, machines)
	}
	return handle
}

remove_entity :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	if handle.kind == .Belt {
		return remove_belt(entities, machines, handle)
	}
	if handle.kind == .Splitter {
		return remove_splitter(entities, machines, handle)
	}
	common := entity_common(entities, handle)
	if common == nil {
		return false
	}
	for cell in common_cells(common^, machines) {
		delete_key(&entities.cells, cell)
	}
	touches_power := machine_touches_power(machines.machines[common.machine])
	defer if touches_power {
		rebuild_electric_networks(entities, machines)
	}
	switch handle.kind {
	case .None:
		return false
	case .Chest:
		return pool_remove(&entities.chests, handle)
	case .Furnace:
		return pool_remove(&entities.furnaces, handle)
	case .Capsule:
		return pool_remove(&entities.capsules, handle)
	case .Inserter:
		return pool_remove(&entities.inserters, handle)
	case .Drill:
		return pool_remove(&entities.drills, handle)
	case .Pipe:
		pool_remove(&entities.pipes, handle)
		rebuild_fluid_networks(entities, machines)
		return true
	case .Fluid_Machine:
		pool_remove(&entities.fluid_machines, handle)
		rebuild_fluid_networks(entities, machines)
		return true
	case .Pole:
		return pool_remove(&entities.poles, handle)
	case .Lamp:
		return pool_remove(&entities.lamps, handle)
	case .Assembler:
		pool_remove(&entities.assemblers, handle)
		if machines.machines[common.machine].fluid_port_count > 0 {
			rebuild_fluid_networks(entities, machines)
		}
		return true
	case .Lab:
		return pool_remove(&entities.labs, handle)
	case .Belt, .Splitter:
		// Handled by remove_belt and remove_splitter above.
		return false
	}
	return false
}

// A solid block or an entity: what the ray stops at and blocks cannot go into.
cell_is_solid_or_entity :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	return block_is_solid(registry, world_get_block(world, cell)) || cell in world.entities.cells
}

// What the player collides with: belts and splitters are walked over,
// not into.
cell_blocks_movement :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	if block_is_solid(registry, world_get_block(world, cell)) {
		return true
	}
	handle, occupied := world.entities.cells[cell]
	return occupied && handle.kind != .Belt && handle.kind != .Splitter
}

// Belts and splitters, then the power balance, then drills, then
// inserters, then furnaces, assemblers and labs, so a furnace sees an item
// an inserter took off a belt in the same tick, and every electric machine
// works at this tick's satisfaction. Fluids come after, so a boiler burns fuel an
// inserter put in this tick, then lamps follow their power. Drills and inserters
// run in pool order, which keeps two of them sharing a vein or a chest
// deterministic. Outcrops of veins exhausted in this tick turn to spent
// rock at the end.
tick_entities :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	tick_belt_network(&world.entities.belt_network, tick_rate, world.entities.splitters.entries[:])
	record_belt_dead_ends(&world.statistics, &world.entities)
	tick_electric_networks(world, content, tick_rate)
	for &drill in world.entities.drills.entries {
		if drill.alive {
			before := drill
			advance_drill(world, content, &drill, tick_rate)
			record_drill_tick(&world.statistics, before, drill)
		}
	}
	for &inserter in world.entities.inserters.entries {
		if inserter.alive {
			before := inserter
			advance_inserter(&world.entities, content, &inserter, tick_rate)
			inserter.idle_streak = next_idle_streak(before.idle_streak, inserter.state)
			record_inserter_tick(&world.statistics, before, inserter, tick_rate)
		}
	}
	for &furnace in world.entities.furnaces.entries {
		if furnace.alive {
			before := furnace
			furnace = advance_furnace(furnace, content.machines.machines[furnace.machine], content.items, content.recipes, tick_rate)
			record_furnace_tick(&world.statistics, before, furnace)
		}
	}
	tick_assemblers(world, content, tick_rate)
	tick_labs(world, content, tick_rate)
	tick_fluids(&world.entities, content, tick_rate)
	tick_lamps(world, content.machines)
	apply_spent_outcrops(world, content.veins)
}
