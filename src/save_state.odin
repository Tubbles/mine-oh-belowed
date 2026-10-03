package game

import "core:container/queue"
import "core:slice"
import "platform"

// The simulation state of a save (entities.bin): every entity pool as
// plain values, the belt items per cell, the loose items, the vein records and outcrop
// cells, pending block changes, water updates and leaf decay, statistics, research,
// shipments, recipe unlocks, quest state and players. Derived data (belt
// lines, fluid and electric networks, the occupant index, vein lookups,
// entity lights) is rebuilt after reading. The same bytes feed simulation_state_hash.
//
// The file is the magic, the header, the content tables of the game data
// it was written with (save_remap.odin) and the state. Loading remaps the
// state's content ids to this build's game data.

SAVE_FORMAT_VERSION :: 2
ENTITIES_FILE_MAGIC :: "MOBE"

// Structs describe their fields (save_binary.odin) and content ids are
// remapped by the tables, so the version only changes when the framing
// changes.
Save_Header :: struct {
	version: u32,
}

// The version after the magic.
SAVE_HEADER_FIELDS_SIZE :: size_of(u32)

make_save_header :: proc() -> Save_Header {
	return Save_Header{version = SAVE_FORMAT_VERSION}
}

append_save_header :: proc(bytes: ^[dynamic]byte, magic: string, header: Save_Header) {
	append(bytes, ..transmute([]byte)magic)
	append_u32(bytes, header.version)
}

read_save_header :: proc(reader: ^Byte_Reader, magic: string) -> (header: Save_Header, ok: bool) {
	if bytes_left(reader^) < len(magic) || string(reader.data[reader.offset:][:len(magic)]) != magic {
		return {}, false
	}
	reader.offset += len(magic)
	header.version = read_u32(reader) or_return
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
	write_pool(bytes, &entities.launch_pads)
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

// The world's lists and the records interleave in the order of the
// format, which predates Game_Records.
write_world_state :: proc(bytes: ^[dynamic]byte, world: ^World, records: ^Game_Records) {
	write_list(bytes, world.veins[:])
	write_list(bytes, sorted_outcrop_cells(world))
	write_list(bytes, world.spent_outcrops[:])
	write_list(bytes, records.crate_sites[:])
	write_prospecting_records(bytes, records)
	write_list(bytes, world.block_changes[:])
	write_list(bytes, water_update_list(&world.water))
	write_entity_pools(bytes, &world.entities)
	write_list(bytes, belt_cell_items(&world.entities))
	write_list(bytes, fluid_network_fluids(world.entities.fluid_networks))
	write_value_of(bytes, &records.statistics)
	write_value_of(bytes, &records.research)
	write_list(bytes, records.shipments[:])
	write_value_of(bytes, &records.contracts)
	append_u64(bytes, records.venture_credit)
	write_list(bytes, records.catalogue_orders[:])
}

// The explored map and the prospecting records (work item 0038).
write_prospecting_records :: proc(bytes: ^[dynamic]byte, records: ^Game_Records) {
	write_list(bytes, sorted_explored_columns(records.explored))
	write_list(bytes, records.assayed_veins[:])
	write_list(bytes, records.magnetometer_readings[:])
	write_list(bytes, records.core_samples[:])
	write_list(bytes, records.seismic_shots[:])
	write_list(bytes, records.seismic_outlines[:])
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
		append_u64(bytes, message.value)
		append_u32(bytes, message.shipment)
	}
}

// The body of entities.bin, without the header. Tables added since
// format version 2 follow the players (write_later_tables); a field world
// then writes its field tables, the machines' wear (0201,
// write_machine_wear_table), the felled trees (0197,
// write_felled_tree_table) and the arrival (0200,
// write_field_arrival_table).
write_simulation_state :: proc(bytes: ^[dynamic]byte, state: ^Simulation_State) {
	write_world_state(bytes, &state.world, &state.records)
	write_value_of(bytes, &state.unlocks)
	write_quest_state(bytes, &state.quests)
	append_u32(bytes, u32(len(state.players)))
	for &player in state.players {
		write_value_of(bytes, &player)
	}
	write_later_tables(bytes, &state.world, &state.records, state.field.enabled)
	if state.field.enabled {
		write_field_tables(bytes, &state.field)
		write_machine_wear_table(bytes, &state.world.entities)
		write_felled_tree_table(bytes, &state.field)
		write_field_arrival_table(bytes, &state.field)
	}
}

// Tables added after format version 2, in the order they were added. A
// file ends where its build's tables ended, so each is read only while
// bytes are left (read_later_tables) and an older save loads with the
// newer tables empty, without a format version step. The loose items
// (work item 0062) are the first, the leaf decay queue (work item 0059)
// the second; its felled list is always empty between ticks. The frame
// tables (work item 0174, write_frame_tables) follow, ending with the
// belt poles and runs (work item 0176, write_belt_run_tables). A field
// world (0179) writes them even empty, since its field tables follow
// (write_field_tables).
write_later_tables :: proc(bytes: ^[dynamic]byte, world: ^World, records: ^Game_Records, field_follows: bool) {
	write_list(bytes, world.entities.loose_items.items[:])
	write_list(bytes, records.leaf_decay.updates[:])
	write_frame_tables(bytes, &world.entities, field_follows)
}

// Reading.

// Fields the file lacks keep what value held.
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
	settle_gone_machines(pool, reader) or_return
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
	read_pool(reader, &entities.launch_pads, .Launch_Pad, machines) or_return
	return true
}

// What the rebuild after reading needs besides the pools.
Loaded_Derived_State :: struct {
	belt_items:     [dynamic]Belt_Cell_Item,
	network_fluids: [dynamic]Fluid_Id,
}

read_world_lists :: proc(reader: ^Byte_Reader, world: ^World, records: ^Game_Records) -> bool {
	read_list(reader, &world.veins) or_return
	outcrops := make([dynamic]Outcrop_Cell, context.temp_allocator)
	read_list(reader, &outcrops) or_return
	clear(&world.outcrop_cells)
	for cell in outcrops {
		world.outcrop_cells[cell.position] = cell.vein
	}
	read_list(reader, &world.spent_outcrops) or_return
	read_list(reader, &records.crate_sites) or_return
	read_prospecting_records(reader, records) or_return
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

read_prospecting_records :: proc(reader: ^Byte_Reader, records: ^Game_Records) -> bool {
	explored := make([dynamic]Explored_Column, context.temp_allocator)
	read_list(reader, &explored) or_return
	clear(&records.explored)
	for column in explored {
		records.explored[column.column] = column.surface
	}
	read_list(reader, &records.assayed_veins) or_return
	read_list(reader, &records.magnetometer_readings) or_return
	read_list(reader, &records.core_samples) or_return
	read_list(reader, &records.seismic_shots) or_return
	read_list(reader, &records.seismic_outlines) or_return
	return true
}

read_world_state :: proc(reader: ^Byte_Reader, world: ^World, records: ^Game_Records, content: Simulation_Content, derived: ^Loaded_Derived_State) -> bool {
	remap := reader.remap
	read_world_lists(reader, world, records) or_return
	if problem, ok := remap_vein_types(world, records, remap^); !ok {
		reader.problem = problem
		return false
	}
	read_entity_pools(reader, &world.entities, content.machines) or_return
	remap_machine_recipes(&world.entities, remap^, content.recipes) or_return
	read_list(reader, &derived.belt_items) or_return
	drop_gone_belt_items(&derived.belt_items)
	read_list(reader, &derived.network_fluids) or_return
	statistics := saved_statistics(remap^)
	read_value_of(reader, &statistics) or_return
	remap_statistics(&records.statistics, statistics, remap^)
	research: Research_State
	read_value_of(reader, &research) or_return
	records.research = remapped_research(research, remap^)
	read_list(reader, &records.shipments) or_return
	remap_shipments(records.shipments[:])
	contracts: Contract_State
	read_value_of(reader, &contracts) or_return
	records.contracts = remapped_contracts(contracts, remap^) or_return
	records.venture_credit = read_u64(reader) or_return
	read_list(reader, &records.catalogue_orders) or_return
	return remap_catalogue_orders(&records.catalogue_orders, remap^)
}

// The key strings of the message log point into the game data; a key the
// data no longer has is dropped with its message.
known_message_key :: proc(content: Simulation_Content, key: string) -> (known: string, found: bool) {
	switch key {
	case "":
		return "", true
	case CAPSULE_LANDED_KEY:
		return CAPSULE_LANDED_KEY, true
	case LOCKER_STOCKED_KEY:
		return LOCKER_STOCKED_KEY, true
	case RESEARCH_COMPLETE_KEY:
		return RESEARCH_COMPLETE_KEY, true
	case SCHEMATIC_READ_KEY:
		return SCHEMATIC_READ_KEY, true
	case MACHINE_BROKE_DOWN_KEY:
		return MACHINE_BROKE_DOWN_KEY, true
	}
	if venture_key, venture_found := known_venture_message_key(content, key); venture_found {
		return venture_key, true
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
	for machine in content.machines.machines {
		if machine.name_key == key {
			return machine.name_key, true
		}
	}
	return "", false
}

read_quest_message :: proc(reader: ^Byte_Reader, content: Simulation_Content) -> (message: Quest_Message, known: bool, ok: bool) {
	message.tick = read_u64(reader) or_return
	text_key := read_string(reader) or_return
	argument_key := read_string(reader) or_return
	message.value = read_u64(reader) or_return
	message.shipment = read_u32(reader) or_return
	text_found, argument_found: bool
	message.text_key, text_found = known_message_key(content, text_key)
	message.argument_key, argument_found = known_message_key(content, argument_key)
	return message, text_found && argument_found, true
}

// Progress is read into a copy sized by the file's quest table and
// remapped; the active quest settles once the messages are in, since
// activating one logs its message.
read_quest_state :: proc(reader: ^Byte_Reader, state: ^Simulation_State, content: Simulation_Content) -> bool {
	quests, remap := &state.quests, reader.remap
	progress := make([]Quest_Progress, len(remap.saved[.Quests]), context.temp_allocator)
	read_value_of(reader, &progress) or_return
	reindexed(quests.progress, progress, remap.new_indices[.Quests], 1)
	saved_active := int(i64(read_u64(reader) or_return))
	quests.capsule = {}
	read_value_of(reader, &quests.capsule) or_return
	quests.reward_target = quests.capsule
	quests.hints_fired = int(read_u64(reader) or_return)
	read_list(reader, &quests.pending_rewards) or_return
	drop_gone_item_stacks(&quests.pending_rewards)
	count := int(read_u32(reader) or_return)
	clear(&quests.messages)
	clear(&quests.notices)
	for _ in 0 ..< count {
		message, known := read_quest_message(reader, content) or_return
		if known {
			append(&quests.messages, message)
		}
	}
	return settle_active_quest(quests, saved_active, remap^, content.quests, state.records.statistics, state.tick)
}

// See write_later_tables. A table the file ends before stays empty.
read_later_tables :: proc(reader: ^Byte_Reader, world: ^World, records: ^Game_Records, machines: Machine_Registry) -> bool {
	clear(&world.entities.loose_items.items)
	if bytes_left(reader^) > 0 {
		read_list(reader, &world.entities.loose_items.items) or_return
		drop_gone_loose_items(&world.entities.loose_items.items)
	}
	clear_leaf_decay(&records.leaf_decay)
	if bytes_left(reader^) > 0 {
		updates := make([dynamic]Leaf_Decay_Update, context.temp_allocator)
		read_list(reader, &updates) or_return
		for update in updates {
			schedule_leaf_decay(&records.leaf_decay, update.position, update.due_tick)
		}
	}
	return read_frame_tables(reader, &world.entities, machines)
}

// Players read into fresh ones (make_player), so fields the file lacks
// take a new player's values.
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
// (make_simulation with the saved seed and settings), remapping content
// ids through reader.remap, and rebuilds the derived data. False for
// malformed or truncated bytes, or with reader.problem set for a file
// this build cannot load.
read_simulation_state :: proc(reader: ^Byte_Reader, state: ^Simulation_State, content: Simulation_Content) -> bool {
	assert(reader.remap != nil, "save: reading the state needs the content remap")
	derived := Loaded_Derived_State {
		belt_items     = make([dynamic]Belt_Cell_Item, context.temp_allocator),
		network_fluids = make([dynamic]Fluid_Id, context.temp_allocator),
	}
	read_world_state(reader, &state.world, &state.records, content, &derived) or_return
	unlocks := saved_recipe_unlocks(reader.remap^)
	read_value_of(reader, &unlocks) or_return
	remap_recipe_unlocks(&state.unlocks, unlocks, reader.remap^, content.recipes)
	read_quest_state(reader, state, content) or_return
	read_players(reader, &state.players) or_return
	for &player in state.players {
		remap_craft_queue(&player.crafting, reader.remap^) or_return
	}
	read_later_tables(reader, &state.world, &state.records, content.machines) or_return
	if bytes_left(reader^) > 0 {
		read_field_tables(reader, &state.field) or_return
		state.field.enabled = true
		read_machine_wear_table(reader, &state.world.entities) or_return
		read_felled_tree_table(reader, &state.field) or_return
		read_field_arrival_table(reader, &state.field) or_return
	}
	if bytes_left(reader^) != 0 || !venture_state_is_consistent(&state.records, content.contracts) {
		return false
	}
	// An older build's pod is replaced before the occupancy is built
	// (work item 0198), so the rebuild sees only the new pod.
	upgraded := upgrade_resized_pods(&state.world.entities, content.machines)
	rebuild_loaded_world(&state.world, content.machines, derived)
	if kept := count_entities_keeping_saved_size(&state.world.entities, content.machines); kept > 0 {
		platform.log_printf("save: %d machines keep the footprint they were saved with; pick them up and place them again for the new size", kept)
	}
	finish_pod_upgrades(state, content.machines, upgraded)
	// The reward target is derived from the restored pools (0210).
	settle_quest_reward_target(&state.quests, &state.records.statistics, &state.world.entities, content.machines, state.field.enabled)
	clear(&state.events)
	return true
}

// The occupant index from the pools; the frame records stay.
rebuild_entity_cells :: proc(entities: ^Entities, machines: Machine_Registry) {
	clear_frame_occupants(&entities.frames)
	for kind in Entity_Kind {
		for index in 0 ..< entity_pool_length(entities, kind) {
			common := entity_common_at(entities, kind, index)
			if common != nil && common.alive {
				occupy_entity_cells(entities, machines, common^)
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
	case .Launch_Pad:
		return len(entities.launch_pads.entries)
	case .Foundation:
		return len(entities.foundations.entries)
	case .Belt_Pole:
		return len(entities.belt_poles.entries)
	case .Belt_Run:
		return len(entities.belt_runs.entries)
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
	case .Launch_Pad:
		return &entities.launch_pads.entries[index].common
	case .Foundation:
		return &entities.foundations.entries[index].common
	case .Belt_Pole:
		return &entities.belt_poles.entries[index].common
	case .Belt_Run:
		// A run has no Entity_Common: it occupies no cell.
		return nil
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
	rebuild_sealed_rooms(entities, machines)
	refresh_all_founded(entities, machines)
	rebuild_belt_lines(entities, machines, derived.belt_items[:])
	rebuild_fluid_networks(entities, machines)
	restore_network_fluids(&entities.fluid_networks, derived.network_fluids[:])
	rebuild_electric_networks(entities, machines)
	rebuild_entity_lights(world, machines)
}

// The deterministic state as one number: the tick, everything
// entities.bin holds, and the blocks of the loaded chunks in coordinate
// order; in a field world the field's chunks too (field_state_hash), and
// the field light's emitters and pending queues with the field tables.
// The light planes, meshes and UI state are left out. Two runs from the same seed
// and inputs, or a world and its loaded save, hash the same.
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
	if state.field.enabled {
		result = field_state_hash(&state.field, result)
	}
	return result
}

chunk_coordinate_before :: proc(first, second: Chunk_Coordinate) -> bool {
	return coordinate_before(World_Coordinate(first), World_Coordinate(second))
}
