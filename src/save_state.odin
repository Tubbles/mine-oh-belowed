package game

import "base:runtime"
import "core:container/queue"
import "core:slice"

// The simulation state of a save (entities.bin): every entity pool as
// plain values, the belt items per cell, the vein records and outcrop
// cells, pending block changes and water updates, statistics, research,
// recipe unlocks, quest state and players. Derived data (belt lines, fluid
// and electric networks, the entity cell map, vein lookups, entity lights)
// is rebuilt after reading. The same bytes feed simulation_state_hash.

SAVE_FORMAT_VERSION :: 1
ENTITIES_FILE_MAGIC :: "MOBE"

Save_Header :: struct {
	version:             u32,
	layout_fingerprint:  u64,
	content_fingerprint: u64,
}

// Every type written through write_value, so that a change to any of them
// changes the layout fingerprint.
save_layout_fingerprint :: proc() -> u64 {
	infos := [?]^runtime.Type_Info {
		type_info_of(Chest),
		type_info_of(Furnace),
		type_info_of(Capsule),
		type_info_of(Belt),
		type_info_of(Inserter),
		type_info_of(Drill),
		type_info_of(Splitter),
		type_info_of(Pipe),
		type_info_of(Fluid_Machine),
		type_info_of(Pole),
		type_info_of(Lamp),
		type_info_of(Assembler),
		type_info_of(Lab),
		type_info_of(Schematic_Crate),
		type_info_of(Core_Sample_Drill),
		type_info_of(Explored_Column),
		type_info_of(Assayed_Vein),
		type_info_of(Magnetometer_Reading),
		type_info_of(Core_Sample),
		type_info_of(Seismic_Shot),
		type_info_of(Seismic_Outline),
		type_info_of(Crate_Site),
		type_info_of(Vein),
		type_info_of(Outcrop_Cell),
		type_info_of(Block_Change),
		type_info_of(Water_Update),
		type_info_of(Belt_Cell_Item),
		type_info_of(Fluid_Id),
		type_info_of(Statistics),
		type_info_of(Research_State),
		type_info_of(Recipe_Unlocks),
		type_info_of(Quest_Progress),
		type_info_of(Item_Stack),
		type_info_of(Entity_Handle),
		type_info_of(Player),
	}
	result := FINGERPRINT_START
	for info in infos {
		result = layout_fingerprint(result, info)
	}
	return result
}

hash_id_list :: proc(state: u64, ids: []string) -> u64 {
	result := fingerprint_u64(state, u64(len(ids)))
	for id in ids {
		result = fingerprint_string(result, id)
	}
	return result
}

// Saved ids are dense indices into the game data (blocks in chunks, items
// in stacks, machines, recipes, technologies, quests), so a save only
// loads with the data it was written with.
content_fingerprint :: proc(content: Simulation_Content) -> u64 {
	ids := make([dynamic]string, context.temp_allocator)
	for definition in content.blocks.definitions {
		append(&ids, definition.id)
	}
	for item in content.items.items {
		append(&ids, item.id)
	}
	for machine in content.machines.machines {
		append(&ids, machine.id)
	}
	for fluid in content.fluids.fluids {
		append(&ids, fluid.id)
	}
	for recipe in content.recipes.recipes {
		append(&ids, recipe.id)
	}
	for technology in content.technologies.technologies {
		append(&ids, technology.id)
	}
	for quest in content.quests.quests {
		append(&ids, quest.id)
	}
	for vein_type in content.veins.types {
		append(&ids, vein_type.name_key)
	}
	return hash_id_list(FINGERPRINT_START, ids[:])
}

make_save_header :: proc(content: Simulation_Content) -> Save_Header {
	return Save_Header{version = SAVE_FORMAT_VERSION, layout_fingerprint = save_layout_fingerprint(), content_fingerprint = content_fingerprint(content)}
}

append_save_header :: proc(bytes: ^[dynamic]byte, magic: string, header: Save_Header) {
	append(bytes, ..transmute([]byte)magic)
	append_u32(bytes, header.version)
	append_u64(bytes, header.layout_fingerprint)
	append_u64(bytes, header.content_fingerprint)
}

read_save_header :: proc(reader: ^Byte_Reader, magic: string) -> (header: Save_Header, ok: bool) {
	if bytes_left(reader^) < len(magic) || string(reader.data[reader.offset:][:len(magic)]) != magic {
		return {}, false
	}
	reader.offset += len(magic)
	header.version = read_u32(reader) or_return
	header.layout_fingerprint = read_u64(reader) or_return
	header.content_fingerprint = read_u64(reader) or_return
	return header, true
}

// Writing.

write_value_of :: proc(bytes: ^[dynamic]byte, value: ^$T) {
	write_value(bytes, value, type_info_of(T))
}

write_pool :: proc(bytes: ^[dynamic]byte, pool: ^Entity_Pool($T)) {
	write_list(bytes, pool.entries[:])
	write_list(bytes, pool.free[:])
}

write_entity_pools :: proc(bytes: ^[dynamic]byte, entities: ^Entities) {
	write_pool(bytes, &entities.chests)
	write_pool(bytes, &entities.furnaces)
	write_pool(bytes, &entities.capsules)
	write_pool(bytes, &entities.belts)
	write_pool(bytes, &entities.inserters)
	write_pool(bytes, &entities.drills)
	write_pool(bytes, &entities.splitters)
	write_pool(bytes, &entities.pipes)
	write_pool(bytes, &entities.fluid_machines)
	write_pool(bytes, &entities.poles)
	write_pool(bytes, &entities.lamps)
	write_pool(bytes, &entities.assemblers)
	write_pool(bytes, &entities.labs)
	write_pool(bytes, &entities.schematic_crates)
	write_pool(bytes, &entities.core_sample_drills)
}

outcrop_before :: proc(first, second: Outcrop_Cell) -> bool {
	return coordinate_before(first.position, second.position)
}

// In coordinate order, since map order is not stable.
sorted_outcrop_cells :: proc(world: ^World) -> []Outcrop_Cell {
	cells := make([dynamic]Outcrop_Cell, 0, len(world.outcrop_cells), context.temp_allocator)
	for position, vein in world.outcrop_cells {
		append(&cells, Outcrop_Cell{position = position, vein = vein})
	}
	slice.sort_by(cells[:], outcrop_before)
	return cells[:]
}

water_update_list :: proc(flow: ^Water_Flow) -> []Water_Update {
	updates := make([]Water_Update, queue.len(flow.updates), context.temp_allocator)
	for &update, index in updates {
		update = queue.get(&flow.updates, index)
	}
	return updates
}

// Networks keep the first fluid that entered them even where only machine
// ports hold it, which a rebuild cannot see, so the fluids are saved.
fluid_network_fluids :: proc(networks: Fluid_Networks) -> []Fluid_Id {
	fluids := make([]Fluid_Id, len(networks.networks), context.temp_allocator)
	for network, index in networks.networks {
		fluids[index] = network.fluid
	}
	return fluids
}

write_world_state :: proc(bytes: ^[dynamic]byte, world: ^World) {
	write_list(bytes, world.veins[:])
	write_list(bytes, sorted_outcrop_cells(world))
	write_list(bytes, world.spent_outcrops[:])
	write_list(bytes, world.crate_sites[:])
	write_prospecting_records(bytes, world)
	write_list(bytes, world.block_changes[:])
	write_list(bytes, water_update_list(&world.water))
	write_entity_pools(bytes, &world.entities)
	write_list(bytes, belt_cell_items(&world.entities))
	write_list(bytes, fluid_network_fluids(world.entities.fluid_networks))
	write_value_of(bytes, &world.statistics)
	write_value_of(bytes, &world.research)
}

// The explored map and the prospecting records (work item 0038).
write_prospecting_records :: proc(bytes: ^[dynamic]byte, world: ^World) {
	write_list(bytes, sorted_explored_columns(world))
	write_list(bytes, world.assayed_veins[:])
	write_list(bytes, world.magnetometer_readings[:])
	write_list(bytes, world.core_samples[:])
	write_list(bytes, world.seismic_shots[:])
	write_list(bytes, world.seismic_outlines[:])
}

write_quest_state :: proc(bytes: ^[dynamic]byte, quests: ^Quest_State) {
	write_value_of(bytes, &quests.progress)
	append_u64(bytes, u64(quests.active))
	write_value_of(bytes, &quests.capsule)
	append_u64(bytes, u64(quests.hints_fired))
	write_list(bytes, quests.pending_rewards[:])
	append_u32(bytes, u32(len(quests.messages)))
	for message in quests.messages {
		append_u64(bytes, message.tick)
		append_string(bytes, message.text_key)
		append_string(bytes, message.argument_key)
	}
}

// The body of entities.bin, without the header.
write_simulation_state :: proc(bytes: ^[dynamic]byte, state: ^Simulation_State) {
	write_world_state(bytes, &state.world)
	write_value_of(bytes, &state.unlocks)
	write_quest_state(bytes, &state.quests)
	append_u32(bytes, u32(len(state.players)))
	for &player in state.players {
		write_value_of(bytes, &player)
	}
}

// Reading.

read_value_of :: proc(reader: ^Byte_Reader, value: ^$T) -> bool {
	return read_value(reader, value, type_info_of(T))
}

// Handles must name their own slot, machines must exist, and freed slots
// must be dead, or later lookups would index out of range.
pool_is_consistent :: proc(pool: Entity_Pool($T), kind: Entity_Kind, machines: Machine_Registry) -> bool {
	for entry, index in pool.entries {
		if entry.handle.kind != kind || int(entry.handle.index) != index || int(entry.machine) >= len(machines.machines) {
			return false
		}
	}
	for index in pool.free {
		if int(index) >= len(pool.entries) || pool.entries[index].alive {
			return false
		}
	}
	return true
}

read_pool :: proc(reader: ^Byte_Reader, pool: ^Entity_Pool($T), kind: Entity_Kind, machines: Machine_Registry) -> bool {
	read_list(reader, &pool.entries) or_return
	read_list(reader, &pool.free) or_return
	return pool_is_consistent(pool^, kind, machines)
}

read_entity_pools :: proc(reader: ^Byte_Reader, entities: ^Entities, machines: Machine_Registry) -> bool {
	read_pool(reader, &entities.chests, .Chest, machines) or_return
	read_pool(reader, &entities.furnaces, .Furnace, machines) or_return
	read_pool(reader, &entities.capsules, .Capsule, machines) or_return
	read_pool(reader, &entities.belts, .Belt, machines) or_return
	read_pool(reader, &entities.inserters, .Inserter, machines) or_return
	read_pool(reader, &entities.drills, .Drill, machines) or_return
	read_pool(reader, &entities.splitters, .Splitter, machines) or_return
	read_pool(reader, &entities.pipes, .Pipe, machines) or_return
	read_pool(reader, &entities.fluid_machines, .Fluid_Machine, machines) or_return
	read_pool(reader, &entities.poles, .Pole, machines) or_return
	read_pool(reader, &entities.lamps, .Lamp, machines) or_return
	read_pool(reader, &entities.assemblers, .Assembler, machines) or_return
	read_pool(reader, &entities.labs, .Lab, machines) or_return
	read_pool(reader, &entities.schematic_crates, .Schematic_Crate, machines) or_return
	read_pool(reader, &entities.core_sample_drills, .Core_Sample_Drill, machines) or_return
	return true
}

// What the rebuild after reading needs besides the pools.
Loaded_Derived_State :: struct {
	belt_items:     [dynamic]Belt_Cell_Item,
	network_fluids: [dynamic]Fluid_Id,
}

read_world_lists :: proc(reader: ^Byte_Reader, world: ^World) -> bool {
	read_list(reader, &world.veins) or_return
	outcrops := make([dynamic]Outcrop_Cell, context.temp_allocator)
	read_list(reader, &outcrops) or_return
	clear(&world.outcrop_cells)
	for cell in outcrops {
		world.outcrop_cells[cell.position] = cell.vein
	}
	read_list(reader, &world.spent_outcrops) or_return
	read_list(reader, &world.crate_sites) or_return
	read_prospecting_records(reader, world) or_return
	read_list(reader, &world.block_changes) or_return
	updates := make([dynamic]Water_Update, context.temp_allocator)
	read_list(reader, &updates) or_return
	queue.clear(&world.water.updates)
	clear(&world.water.scheduled)
	for update in updates {
		schedule_water_update(&world.water, update.position, update.due_tick)
	}
	return true
}

read_prospecting_records :: proc(reader: ^Byte_Reader, world: ^World) -> bool {
	explored := make([dynamic]Explored_Column, context.temp_allocator)
	read_list(reader, &explored) or_return
	clear(&world.explored)
	for column in explored {
		world.explored[column.column] = column.surface
	}
	read_list(reader, &world.assayed_veins) or_return
	read_list(reader, &world.magnetometer_readings) or_return
	read_list(reader, &world.core_samples) or_return
	read_list(reader, &world.seismic_shots) or_return
	read_list(reader, &world.seismic_outlines) or_return
	return true
}

read_world_state :: proc(reader: ^Byte_Reader, world: ^World, machines: Machine_Registry, derived: ^Loaded_Derived_State) -> bool {
	read_world_lists(reader, world) or_return
	read_entity_pools(reader, &world.entities, machines) or_return
	read_list(reader, &derived.belt_items) or_return
	read_list(reader, &derived.network_fluids) or_return
	read_value_of(reader, &world.statistics) or_return
	read_value_of(reader, &world.research) or_return
	return true
}

// The key strings of the message log point into the game data; a key the
// data no longer has is dropped with its message.
known_message_key :: proc(content: Simulation_Content, key: string) -> (known: string, found: bool) {
	switch key {
	case "":
		return "", true
	case CAPSULE_LANDED_KEY:
		return CAPSULE_LANDED_KEY, true
	case RESEARCH_COMPLETE_KEY:
		return RESEARCH_COMPLETE_KEY, true
	case SCHEMATIC_READ_KEY:
		return SCHEMATIC_READ_KEY, true
	}
	for recipe in content.recipes.recipes {
		if recipe.channel == .Schematic && recipe.name_key == key {
			return recipe.name_key, true
		}
	}
	for quest in content.quests.quests {
		for candidate in ([2]string{quest.message_key, quest.complete_key}) {
			if candidate == key {
				return candidate, true
			}
		}
		for hint in quest.hints {
			if hint.text_key == key {
				return hint.text_key, true
			}
		}
	}
	for technology in content.technologies.technologies {
		if technology.name_key == key {
			return technology.name_key, true
		}
	}
	return "", false
}

read_quest_message :: proc(reader: ^Byte_Reader, content: Simulation_Content) -> (message: Quest_Message, known: bool, ok: bool) {
	message.tick = read_u64(reader) or_return
	text_key := read_string(reader) or_return
	argument_key := read_string(reader) or_return
	text_found, argument_found: bool
	message.text_key, text_found = known_message_key(content, text_key)
	message.argument_key, argument_found = known_message_key(content, argument_key)
	return message, text_found && argument_found, true
}

read_quest_state :: proc(reader: ^Byte_Reader, quests: ^Quest_State, content: Simulation_Content) -> bool {
	read_value_of(reader, &quests.progress) or_return
	quests.active = int(i64(read_u64(reader) or_return))
	read_value_of(reader, &quests.capsule) or_return
	quests.hints_fired = int(read_u64(reader) or_return)
	read_list(reader, &quests.pending_rewards) or_return
	if quests.active != NO_QUEST && (quests.active < 0 || quests.active >= len(quests.progress)) {
		return false
	}
	count := int(read_u32(reader) or_return)
	clear(&quests.messages)
	clear(&quests.notices)
	for _ in 0 ..< count {
		message, known := read_quest_message(reader, content) or_return
		if known {
			append(&quests.messages, message)
		}
	}
	return true
}

read_players :: proc(reader: ^Byte_Reader, players: ^[dynamic]Player) -> bool {
	count := int(read_u32(reader) or_return)
	if count == 0 || count > bytes_left(reader^) {
		return false
	}
	for player in players^ {
		destroy_player(player)
	}
	clear(players)
	for _ in 0 ..< count {
		append(players, make_player({}))
		read_value_of(reader, &players[len(players) - 1]) or_return
	}
	return true
}

// Reads the body of entities.bin into a simulation made for the world
// (make_simulation with the saved seed and settings) and rebuilds the
// derived data. False for malformed or truncated bytes.
read_simulation_state :: proc(reader: ^Byte_Reader, state: ^Simulation_State, content: Simulation_Content) -> bool {
	derived := Loaded_Derived_State {
		belt_items     = make([dynamic]Belt_Cell_Item, context.temp_allocator),
		network_fluids = make([dynamic]Fluid_Id, context.temp_allocator),
	}
	read_world_state(reader, &state.world, content.machines, &derived) or_return
	read_value_of(reader, &state.unlocks) or_return
	read_quest_state(reader, &state.quests, content) or_return
	read_players(reader, &state.players) or_return
	if bytes_left(reader^) != 0 {
		return false
	}
	rebuild_loaded_world(&state.world, content.machines, derived)
	clear(&state.events)
	return true
}

rebuild_entity_cells :: proc(entities: ^Entities, machines: Machine_Registry) {
	clear(&entities.cells)
	for kind in Entity_Kind {
		for index in 0 ..< entity_pool_length(entities, kind) {
			common := entity_common_at(entities, kind, index)
			if common != nil && common.alive {
				for cell in common_cells(common^, machines) {
					entities.cells[cell] = common.handle
				}
			}
		}
	}
}

entity_pool_length :: proc(entities: ^Entities, kind: Entity_Kind) -> int {
	switch kind {
	case .None:
		return 0
	case .Chest:
		return len(entities.chests.entries)
	case .Furnace:
		return len(entities.furnaces.entries)
	case .Capsule:
		return len(entities.capsules.entries)
	case .Belt:
		return len(entities.belts.entries)
	case .Inserter:
		return len(entities.inserters.entries)
	case .Drill:
		return len(entities.drills.entries)
	case .Splitter:
		return len(entities.splitters.entries)
	case .Pipe:
		return len(entities.pipes.entries)
	case .Fluid_Machine:
		return len(entities.fluid_machines.entries)
	case .Pole:
		return len(entities.poles.entries)
	case .Lamp:
		return len(entities.lamps.entries)
	case .Assembler:
		return len(entities.assemblers.entries)
	case .Lab:
		return len(entities.labs.entries)
	case .Schematic_Crate:
		return len(entities.schematic_crates.entries)
	case .Core_Sample_Drill:
		return len(entities.core_sample_drills.entries)
	}
	return 0
}

// The common part of any pool entry, alive or not.
entity_common_at :: proc(entities: ^Entities, kind: Entity_Kind, index: int) -> ^Entity_Common {
	switch kind {
	case .None:
		return nil
	case .Chest:
		return &entities.chests.entries[index].common
	case .Furnace:
		return &entities.furnaces.entries[index].common
	case .Capsule:
		return &entities.capsules.entries[index].common
	case .Belt:
		return &entities.belts.entries[index].common
	case .Inserter:
		return &entities.inserters.entries[index].common
	case .Drill:
		return &entities.drills.entries[index].common
	case .Splitter:
		return &entities.splitters.entries[index].common
	case .Pipe:
		return &entities.pipes.entries[index].common
	case .Fluid_Machine:
		return &entities.fluid_machines.entries[index].common
	case .Pole:
		return &entities.poles.entries[index].common
	case .Lamp:
		return &entities.lamps.entries[index].common
	case .Assembler:
		return &entities.assemblers.entries[index].common
	case .Lab:
		return &entities.labs.entries[index].common
	case .Schematic_Crate:
		return &entities.schematic_crates.entries[index].common
	case .Core_Sample_Drill:
		return &entities.core_sample_drills.entries[index].common
	}
	return nil
}

rebuild_vein_indices :: proc(world: ^World) {
	clear(&world.vein_indices)
	for vein, index in world.veins {
		world.vein_indices[vein.id] = index
	}
}

// Lamps lit in the save shine again; the light itself comes back as their
// chunks arrive (seed_entity_lights_in_chunk).
rebuild_entity_lights :: proc(world: ^World, machines: Machine_Registry) {
	clear(&world.entity_lights)
	for cell, level in lit_lamp_lights(&world.entities, machines) {
		world.entity_lights[cell] = level
	}
}

restore_network_fluids :: proc(networks: ^Fluid_Networks, fluids: []Fluid_Id) {
	if len(fluids) != len(networks.networks) {
		return
	}
	for &network, index in networks.networks {
		network.fluid = fluids[index]
	}
}

rebuild_loaded_world :: proc(world: ^World, machines: Machine_Registry, derived: Loaded_Derived_State) {
	rebuild_vein_indices(world)
	entities := &world.entities
	rebuild_entity_cells(entities, machines)
	rebuild_belt_lines(entities, machines, derived.belt_items[:])
	rebuild_fluid_networks(entities, machines)
	restore_network_fluids(&entities.fluid_networks, derived.network_fluids[:])
	rebuild_electric_networks(entities, machines)
	rebuild_entity_lights(world, machines)
}

// The deterministic state as one number: the tick, everything
// entities.bin holds, and the blocks of the loaded chunks in coordinate
// order. Light, meshes and UI state are left out. Two runs from the same
// seed and inputs, or a world and its loaded save, hash the same.
simulation_state_hash :: proc(state: ^Simulation_State) -> u64 {
	bytes := make([dynamic]byte, context.temp_allocator)
	write_simulation_state(&bytes, state)
	result := fingerprint_bytes(fingerprint_u64(FINGERPRINT_START, state.tick), bytes[:])
	coordinates := make([dynamic]Chunk_Coordinate, 0, len(state.world.chunks), context.temp_allocator)
	for coordinate in state.world.chunks {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], chunk_coordinate_before)
	for coordinate in coordinates {
		chunk := state.world.chunks[coordinate]
		result = fingerprint_u64(result, u64(u32(coordinate.x)) | u64(u32(coordinate.z)) << 32)
		result = fingerprint_u64(result, u64(u32(coordinate.y)))
		result = fingerprint_bytes(result, slice.to_bytes(chunk.blocks[:]))
	}
	return result
}

chunk_coordinate_before :: proc(first, second: Chunk_Coordinate) -> bool {
	return coordinate_before(World_Coordinate(first), World_Coordinate(second))
}
