package game

// Entities (doc/architecture.md, Simulation): typed pools with generational
// handles, one pool per type and no general component system. Entities are
// not blocks. An entity stands on a frame (world_frame.odin, work item
// 0174): its origin is a cell of its frame, frame 0 being the block world.
// The cells they occupy stay air in the chunk data, and the frame table's
// occupant index holds the packed handle of the entity in each occupied
// cell with the flags the world reads, so the raycast, collision, water and
// placement checks are cell lookups. Light still treats those cells as air.
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
	// Cave crates holding a schematic (schematic.odin).
	Schematic_Crate,
	// Core sample drills (prospecting.odin).
	Core_Sample_Drill,
	// Launch pads (launch_pad.odin).
	Launch_Pad,
	// Foundations (entity_frames.odin): the solid cells of a frame that
	// machines stand on.
	Foundation,
	// Belt poles and the runs between them (belt_run.odin, work item
	// 0176). A run is no entity: its pool entries have a handle, a
	// machine and no Entity_Common, and it occupies no cell; the kind
	// lets a run stand in a belt line beside the belts.
	Belt_Pole,
	Belt_Run,
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
// footprint, a cell of frame, size is the footprint after rotation (x, y,
// z), rotation counts quarter turns round the frame's up. The frame is
// left out of the pools' bytes and saved as a list of the entities off
// frame 0 (save_state.odin, write_later_tables), so a world on frame 0
// alone keeps its bytes and its state hash, and a save written before
// frames loads with every entity on frame 0.
Entity_Common :: struct {
	handle:   Entity_Handle,
	machine:  Machine_Id,
	frame:    Frame_Id `save:"-"`,
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

Foundation :: struct {
	using common: Entity_Common,
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
	schematic_crates: Entity_Pool(Schematic_Crate),
	core_sample_drills: Entity_Pool(Core_Sample_Drill),
	launch_pads:    Entity_Pool(Launch_Pad),
	foundations:    Entity_Pool(Foundation),
	// Saved in a later table (write_belt_run_tables), so a world without
	// them keeps its bytes.
	belt_poles:     Entity_Pool(Belt_Pole),
	belt_runs:      Entity_Pool(Belt_Run),
	// Transport lines derived from the belts and splitters (belt.odin).
	belt_network:   Belt_Network,
	// Derived from the pipes and fluid ports (fluid_network.odin).
	fluid_networks: Fluid_Networks,
	// Derived from the poles and electric machines (power_network.odin).
	electric_networks: Electric_Networks,
	// The frames and their occupant index (world_frame.odin): the frame
	// records are saved, the index is derived from the pools. It rides on
	// Entities, which sits on World, so entity_at and add_entity keep
	// their parameters.
	frames:         Frame_Table,
	// Stacks lying in the world (loose_item.odin). Not machines: never in
	// the occupant index, so they block nothing.
	loose_items:    Loose_Items,
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
	destroy_pool(&entities.schematic_crates)
	destroy_pool(&entities.core_sample_drills)
	destroy_pool(&entities.launch_pads)
	destroy_pool(&entities.foundations)
	destroy_pool(&entities.belt_poles)
	destroy_pool(&entities.belt_runs)
	destroy_belt_network(&entities.belt_network)
	destroy_fluid_networks(&entities.fluid_networks)
	destroy_electric_networks(&entities.electric_networks)
	destroy_frame_table(&entities.frames)
	delete(entities.loose_items.items)
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
	case .Schematic_Crate:
		if crate := pool_get(&entities.schematic_crates, handle); crate != nil {
			return &crate.common
		}
	case .Core_Sample_Drill:
		if drill := pool_get(&entities.core_sample_drills, handle); drill != nil {
			return &drill.common
		}
	case .Launch_Pad:
		if pad := pool_get(&entities.launch_pads, handle); pad != nil {
			return &pad.common
		}
	case .Foundation:
		if foundation := pool_get(&entities.foundations, handle); foundation != nil {
			return &foundation.common
		}
	case .Belt_Pole:
		if pole := pool_get(&entities.belt_poles, handle); pole != nil {
			return &pole.common
		}
	case .Belt_Run:
		return nil
	}
	return nil
}

// Belts, foundations and belt poles have no panel: Interact does nothing
// on them. Interact on a schematic crate takes its schematic instead
// (schematic.odin).
entity_has_panel :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	return handle.kind != .Belt && handle.kind != .Foundation && handle.kind != .Belt_Pole && handle.kind != .Schematic_Crate && entity_is_alive(entities, handle)
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
	case .Schematic_Crate:
		if crate := pool_get(&entities.schematic_crates, handle); crate != nil {
			return crate.slots[:]
		}
	case .Launch_Pad:
		if pad := pool_get(&entities.launch_pads, handle); pad != nil {
			return pad.slots[:launch_pad_slot_count(pad^)]
		}
	}
	return nil
}

// The entity in a cell of a frame, the block world's by default.
entity_at :: proc(entities: ^Entities, cell: World_Coordinate, frame := BLOCK_FRAME) -> Entity_Handle {
	occupant, found := frame_occupant(&entities.frames, frame, cell)
	if !found {
		return NO_ENTITY
	}
	return entity_from_occupant(occupant.handle)
}

// The handle packed for the occupant index: the kind in the top byte, the
// index in the next three, the generation in the low four. A live handle's
// generation is at least 1, so it never packs to NO_OCCUPANT.
OCCUPANT_INDEX_LIMIT :: 1 << 24

entity_occupant_handle :: proc(handle: Entity_Handle) -> Occupant_Handle {
	assert(handle.index < OCCUPANT_INDEX_LIMIT, "entity pools stay below 2^24 entries")
	return Occupant_Handle(u64(handle.kind) << 56 | u64(handle.index) << 32 | u64(handle.generation))
}

entity_from_occupant :: proc(occupant: Occupant_Handle) -> Entity_Handle {
	value := u64(occupant)
	return Entity_Handle{kind = Entity_Kind(value >> 56), index = u32(value >> 32) & (OCCUPANT_INDEX_LIMIT - 1), generation = u32(value)}
}

// What the world reads of a machine in a cell: belts and splitters are
// walked over, a hydro turbine lets water through, a foundation is what
// the field light will stop at.
machine_occupant_flags :: proc(machine: Machine) -> Occupant_Flags {
	flags: Occupant_Flags
	if machine.kind != .Belt && machine.kind != .Splitter {
		flags += {.Solid}
	}
	if machine.kind != .Hydro_Turbine {
		flags += {.Blocks_Water}
	}
	if machine.kind == .Foundation {
		flags += {.Blocks_Light}
	}
	return flags
}

// The occupant index through the two world procedures.
occupy_entity_cells :: proc(entities: ^Entities, machines: Machine_Registry, common: Entity_Common) {
	occupant := Occupant{handle = entity_occupant_handle(common.handle), flags = machine_occupant_flags(machines.machines[common.machine])}
	for cell in common_cells(common, machines) {
		occupy_frame_cell(&entities.frames, common.frame, cell, occupant)
	}
}

vacate_entity_cells :: proc(entities: ^Entities, machines: Machine_Registry, common: Entity_Common) {
	for cell in common_cells(common, machines) {
		vacate_frame_cell(&entities.frames, common.frame, cell)
	}
	release_empty_frame(entities, common.frame)
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

make_entity_common :: proc(machines: Machine_Registry, machine: Machine_Id, origin: World_Coordinate, rotation: u8, frame := BLOCK_FRAME) -> Entity_Common {
	return Entity_Common {
		machine = machine,
		frame = frame,
		origin = origin,
		rotation = rotation % 4,
		size = rotated_footprint_size(machines.machines[machine].footprint, rotation),
	}
}

// The caller has checked that the footprint is free. A belt gets the
// default shape of its item (belt_placement.odin picks others), a drill
// no vein (place_entity_with_player sets the one under it). origin is a
// cell of frame, the block world's by default.
add_entity :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, origin: World_Coordinate, rotation: u8, frame := BLOCK_FRAME) -> Entity_Handle {
	common := make_entity_common(machines, machine, origin, rotation, frame)
	handle: Entity_Handle
	switch machines.machines[machine].kind {
	case .Belt:
		return add_belt(entities, machines, machine, origin, rotation, default_belt_shape(machines.machines[machine].belt_shape), frame)
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
		frame_record, _ := find_frame(&entities.frames, frame)
		handle = pool_add(&entities.inserters, .Inserter, make_inserter(common, machines.machines[machine], frame_record))
	case .Drill:
		handle = pool_add(&entities.drills, .Drill, make_drill(common, {}, machines.machines[machine].slot_count))
	case .Splitter:
		return add_splitter(entities, machines, machine, origin, rotation, frame)
	case .Pipe:
		handle = pool_add(&entities.pipes, .Pipe, make_pipe(common))
	case .Offshore_Pump, .Boiler, .Steam_Engine, .Storage_Tank, .Pump, .Tar_Pit_Pump, .Flare_Stack, .Combustion_Generator, .Hydro_Turbine:
		handle = pool_add(&entities.fluid_machines, .Fluid_Machine, make_fluid_machine(common, machines.machines[machine]))
	case .Pole, .Power_Switch:
		handle = pool_add(&entities.poles, .Pole, make_pole(common))
	case .Lamp:
		handle = pool_add(&entities.lamps, .Lamp, make_lamp(common))
	case .Crafting_Machine:
		handle = pool_add(&entities.assemblers, .Assembler, make_assembler(common, machines.machines[machine]))
	case .Lab:
		handle = pool_add(&entities.labs, .Lab, make_lab(common, len(machines.lab_packs)))
	case .Schematic_Crate:
		handle = pool_add(&entities.schematic_crates, .Schematic_Crate, Schematic_Crate{common = common, slots = {EMPTY_STACK}})
	case .Core_Sample_Drill:
		handle = pool_add(&entities.core_sample_drills, .Core_Sample_Drill, make_core_sample_drill(common))
	case .Launch_Pad:
		handle = pool_add(&entities.launch_pads, .Launch_Pad, make_launch_pad(common, machines.machines[machine]))
	case .Foundation:
		handle = pool_add(&entities.foundations, .Foundation, Foundation{common = common})
	case .Belt_Pole:
		handle = pool_add(&entities.belt_poles, .Belt_Pole, Belt_Pole{common = common})
	}
	common.handle = handle
	occupy_entity_cells(entities, machines, common)
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
	if handle.kind == .Belt_Run {
		return remove_belt_run(entities, machines, handle)
	}
	if handle.kind == .Belt_Pole {
		remove_belt_runs_on_pole(entities, machines, handle)
	}
	common := entity_common(entities, handle)
	if common == nil {
		return false
	}
	vacate_entity_cells(entities, machines, common^)
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
		pool_remove(&entities.drills, handle)
		if machines.machines[common.machine].fluid_port_count > 0 {
			rebuild_fluid_networks(entities, machines)
		}
		return true
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
	case .Schematic_Crate:
		return pool_remove(&entities.schematic_crates, handle)
	case .Core_Sample_Drill:
		return pool_remove(&entities.core_sample_drills, handle)
	case .Launch_Pad:
		pool_remove(&entities.launch_pads, handle)
		rebuild_fluid_networks(entities, machines)
		return true
	case .Foundation:
		return pool_remove(&entities.foundations, handle)
	case .Belt_Pole:
		return pool_remove(&entities.belt_poles, handle)
	case .Belt, .Splitter, .Belt_Run:
		// Handled by remove_belt, remove_splitter and remove_belt_run above.
		return false
	}
	return false
}

// A solid block or an entity: what the ray stops at and blocks cannot go into.
cell_is_solid_or_entity :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	return block_is_solid(registry, world_get_block(world, cell)) || frame_cell_is_occupied(&world.entities.frames, BLOCK_FRAME, cell)
}

// What the player collides with: belts and splitters are walked over,
// not into.
cell_blocks_movement :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	if block_is_solid(registry, world_get_block(world, cell)) {
		return true
	}
	occupant, occupied := frame_occupant(&world.entities.frames, BLOCK_FRAME, cell)
	return occupied && .Solid in occupant.flags
}

// Belts and splitters, then items falling off belt ends over a drop and
// the loose items, then the power balance, then drills, then
// inserters, then furnaces, assemblers and labs, so a furnace sees an item
// an inserter took off a belt in the same tick, and every electric machine
// works at this tick's satisfaction. Fluids come after, so a boiler burns fuel an
// inserter put in this tick, then lamps follow their power. Launch pads
// assemble after the inserters fed them. Drills and inserters
// run in pool order, which keeps two of them sharing a vein or a chest
// deterministic. Outcrops of veins exhausted in this tick turn to spent
// rock at the end, and crates of newly loaded cave sites appear. The
// blocks go through the context's block procedures, and the lit lamps
// reach the world's light after the tick (tick_entities_on_world). A
// profile (tick_profile.odin) gets the wall time of each step.
tick_entities :: proc(tick_context: Entity_Tick_Context, profile: ^Tick_Profile = nil) {
	entities, records, content, tick_rate := tick_context.entities, tick_context.records, tick_context.content, tick_context.tick_rate
	clock := profile_now(profile)
	tick_belt_network(&entities.belt_network, tick_rate, entities.splitters.entries[:])
	drop_items_off_belt_ends(tick_context)
	clock = profile_section(profile, .Belts, clock)
	tick_loose_items(tick_context)
	clock = profile_section(profile, .Loose_Items, clock)
	record_belt_dead_ends(&records.statistics, entities)
	clock = profile_section(profile, .Statistics, clock)
	tick_electric_networks(tick_context)
	clock = profile_section(profile, .Power, clock)
	for &drill in entities.drills.entries {
		if drill.alive {
			before := drill
			advance_drill(tick_context, &drill)
			record_drill_tick(&records.statistics, before, drill)
		}
	}
	clock = profile_section(profile, .Drills, clock)
	for &inserter in entities.inserters.entries {
		if inserter.alive {
			before := inserter
			advance_inserter(entities, content, &inserter, tick_rate)
			inserter.idle_streak = next_idle_streak(before.idle_streak, inserter.state)
			record_inserter_tick(&records.statistics, before, inserter, tick_rate)
		}
	}
	clock = profile_section(profile, .Inserters, clock)
	for &furnace in entities.furnaces.entries {
		if furnace.alive {
			before := furnace
			furnace = advance_furnace(furnace, content.machines.machines[furnace.machine], content.items, content.recipes, tick_rate, tick_context.settings.byproducts_lenient)
			record_furnace_tick(&records.statistics, before, furnace, content.recipes)
			grown := stack_growth(before.slots[FURNACE_OUTPUT_SLOT], furnace.slots[FURNACE_OUTPUT_SLOT])
			record_machine_output(&furnace.output_rate, records.statistics.current_second, grown)
		}
	}
	clock = profile_section(profile, .Furnaces, clock)
	tick_assemblers(tick_context)
	clock = profile_section(profile, .Assemblers, clock)
	tick_labs(tick_context)
	clock = profile_section(profile, .Labs, clock)
	tick_core_sample_drills(tick_context)
	clock = profile_section(profile, .Core_Sample_Drills, clock)
	tick_launch_pads(tick_context)
	clock = profile_section(profile, .Launch_Pads, clock)
	tick_fluids(entities, content, tick_rate, &records.statistics)
	clock = profile_section(profile, .Fluids, clock)
	tick_lamps(entities)
	clock = profile_section(profile, .Lamps, clock)
	apply_spent_outcrops(tick_context)
	place_pending_crates(tick_context)
	profile_section(profile, .Outcrops_And_Crates, clock)
}
