package game

// Entities (doc/architecture.md, Simulation): typed pools with generational
// handles, one pool per type and no general component system. Entities are
// not blocks. The cells they occupy stay air in the chunk data, and the
// World's cell map holds the handle of the entity in each occupied cell, so
// the raycast, collision and placement checks are cell lookups. Light and
// water still treat those cells as air.
//
// Entity data is plain values (no pointers into chunks or other entities),
// so it can be serialised per chunk later (M5).

MAXIMUM_CHEST_SLOTS :: 48

Entity_Kind :: enum u8 {
	None,
	Chest,
	Furnace,
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

// Freed entries stay in place with alive false and go on the free list;
// reuse bumps the generation, so old handles stop resolving.
Entity_Pool :: struct($T: typeid) {
	entries: [dynamic]T,
	free:    [dynamic]u32,
}

Entities :: struct {
	chests:   Entity_Pool(Chest),
	furnaces: Entity_Pool(Furnace),
	cells:    map[World_Coordinate]Entity_Handle,
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
	}
	return nil
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

// The caller has checked that the footprint is free.
add_entity :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, origin: World_Coordinate, rotation: u8) -> Entity_Handle {
	common := make_entity_common(machines, machine, origin, rotation)
	handle: Entity_Handle
	switch machines.machines[machine].kind {
	case .Chest:
		chest := Chest{common = common, slot_count = machines.machines[machine].slot_count}
		for &slot in chest.slots {
			slot = EMPTY_STACK
		}
		handle = pool_add(&entities.chests, .Chest, chest)
	case .Furnace:
		handle = pool_add(&entities.furnaces, .Furnace, make_furnace(common))
	}
	for cell in footprint_cells(origin, machines.machines[machine].footprint, rotation) {
		entities.cells[cell] = handle
	}
	return handle
}

remove_entity :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	common := entity_common(entities, handle)
	if common == nil {
		return false
	}
	for cell in common_cells(common^, machines) {
		delete_key(&entities.cells, cell)
	}
	switch handle.kind {
	case .None:
		return false
	case .Chest:
		return pool_remove(&entities.chests, handle)
	case .Furnace:
		return pool_remove(&entities.furnaces, handle)
	}
	return false
}

// A solid block or an entity: what the player collides with and the ray stops at.
cell_is_solid_or_entity :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	return block_is_solid(registry, world_get_block(world, cell)) || cell in world.entities.cells
}

tick_entities :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	for &furnace in world.entities.furnaces.entries {
		if furnace.alive {
			furnace = advance_furnace(furnace, content.machines.machines[furnace.machine], content.items, content.recipes, tick_rate)
		}
	}
}
