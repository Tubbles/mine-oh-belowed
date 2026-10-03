package game

import "core:fmt"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "platform"

// Loading the game data, at start and again on a content reload (work
// item 0054). The content tables (blocks, items, fluids, machines,
// recipes, technologies, quests, contracts, notes, developer kits,
// the touch overlay, planets, biomes, tree species and veins) load into one arena, so a reload frees the data it replaces in
// one go once nothing points into it any more.
//
// A content reload runs between frames, never during a tick: the new data
// is loaded and validated first (any problem keeps everything as it was),
// then the running world goes through the save codec in memory, the bytes
// save_session writes to entities.bin, and is read back with the content
// remap (save_remap.odin), so added, removed and reordered content behaves
// exactly as a save loaded by a later build. Loaded chunks move over with
// their blocks remapped and keep them: a changed generator affects only
// chunks loaded later.

// The game data and the generator data every session copies
// (session_generator), in arena.
Game_Data :: struct {
	content:        Game_Content,
	base_generator: Generator,
	arena:          ^virtual.Arena,
}

destroy_game_data :: proc(data: ^Game_Data) {
	destroy_arena(data.arena)
	data^ = {}
}

// Every data file main loads at start except the game config, the strings
// and the bindings, validated the same way. string_entries is the string
// table the name keys are checked against. The problem is the loader's
// error line without "error: ", which also went to the log.
load_game_data :: proc(data_directory: string, config: Game_Config, string_entries: map[string]string) -> (data: Game_Data, problem: string) {
	data.arena = new_growing_arena()
	if data.arena == nil {
		return {}, "cannot reserve memory for the game data"
	}
	capture: platform.Log_Capture
	platform.begin_log_capture(&capture)
	loaded: bool
	{
		context.allocator = virtual.arena_allocator(data.arena)
		data.content, data.base_generator, loaded = load_game_tables(data_directory, config, string_entries)
	}
	problem = platform.end_log_capture(&capture, fmt.tprintf("the game data in %s did not load", data_directory))
	if !loaded {
		destroy_game_data(&data)
		return {}, problem
	}
	return data, ""
}

// Each loader logs its problem as it refuses.
load_game_tables :: proc(data_directory: string, config: Game_Config, string_entries: map[string]string) -> (content: Game_Content, base_generator: Generator, ok: bool) {
	content = load_content_registries(data_directory, string_entries) or_return
	if problem := validate_starting_items(config.starting_items, content.items); problem != "" {
		platform.log_printf("error: invalid %s: %s", GAME_CONFIG_FILE_NAME, problem)
		return {}, {}, false
	}
	content.developer_kits = load_developer_kits(data_directory, content.items) or_return
	content.touch_overlay = load_touch_overlay(data_directory) or_return
	content.planets = load_planets(data_directory) or_return
	content.field_materials = load_field_material_table(data_directory, content.items) or_return
	content.lighting = load_lighting_file(data_directory) or_return
	if problem := field_torch_problem(config.field_simulation, content.items, content.lighting); problem != "" {
		platform.log_printf("error: invalid %s: %s", GAME_CONFIG_FILE_NAME, problem)
		return {}, {}, false
	}
	base_generator = load_generator(data_directory, content.blocks, DEFAULT_WORLD_SEED) or_return
	veins, problem := resolve_vein_content(base_generator.veins, content.items)
	if problem != "" {
		platform.log_printf("error: invalid %s: %s", VEINS_FILE_NAME, problem)
		return {}, {}, false
	}
	content.veins = veins
	if _, found := find_item_id(content.items, base_generator.sapling_item); !found {
		platform.log_printf("error: invalid %s: sapling_item %q is not an item", TREES_FILE_NAME, base_generator.sapling_item)
		return {}, {}, false
	}
	refresh_content_names(&content)
	return content, base_generator, true
}

load_content_registries :: proc(data_directory: string, string_entries: map[string]string) -> (content: Game_Content, ok: bool) {
	content.blocks = load_block_registry(data_directory, string_entries) or_return
	content.items = load_item_registry(data_directory, content.blocks) or_return
	content.fluids = load_fluid_registry(data_directory) or_return
	content.machines = load_machine_registry(data_directory, content.items, content.fluids) or_return
	content.recipes = load_recipe_registry(data_directory, content.items, content.fluids) or_return
	if problem := validate_crafting_machine_recipes(content.machines, content.recipes); problem != "" {
		platform.log_printf("error: invalid %s: %s", MACHINES_FILE_NAME, problem)
		return {}, false
	}
	content.technologies = load_technology_registry(data_directory, content.items, content.recipes) or_return
	content.machines.lab_packs = content.technologies.science_packs
	content.quests = load_quest_registry(data_directory, content_quest_references(content, string_entries)) or_return
	content.contracts = load_contract_registry(data_directory, content.items, string_entries) or_return
	validate_content_description_keys(content, string_entries) or_return
	content.notes = load_note_registry(data_directory, content.items, content.technologies, content.quests, string_entries) or_return
	return content, true
}

// The description keys (work item 0070) are checked once every table is
// resolved, since the item, machine and technology loaders know no
// strings.
validate_content_description_keys :: proc(content: Game_Content, string_entries: map[string]string) -> bool {
	checks := [?]struct {
		file:    string,
		problem: string,
	} {
		{ITEMS_FILE_NAME, validate_item_description_keys(content.items, string_entries)},
		{MACHINES_FILE_NAME, validate_machine_description_keys(content.machines, string_entries)},
		{TECHNOLOGIES_FILE_NAME, validate_technology_description_keys(content.technologies, string_entries)},
	}
	for check in checks {
		if check.problem != "" {
			platform.log_printf("error: invalid %s: %s", check.file, check.problem)
			return false
		}
	}
	return true
}

content_quest_references :: proc(content: Game_Content, string_entries: map[string]string) -> Quest_References {
	return Quest_References {
		blocks = content.blocks,
		items = content.items,
		machines = content.machines,
		fluids = content.fluids,
		recipes = content.recipes,
		technologies = content.technologies,
		strings = string_entries,
	}
}

// The item sort and the recipe browser's order go by the names in the
// string table, so a strings reload refreshes them too.
refresh_content_names :: proc(content: ^Game_Content, allocator := context.allocator) {
	content.item_sort_ranks = item_sort_ranks(content.items, item_display_names(content.items, context.temp_allocator), allocator)
	content.recipe_names = recipe_display_names(content.recipes, allocator)
	content.recipe_order = recipe_name_order(content.recipe_names, allocator)
}

// What a reload changed.

Content_Table_Change :: struct {
	added:   int,
	removed: int,
}

// How many of ids other lacks.
count_missing_ids :: proc(ids, other: []string) -> int {
	present := make(map[string]struct{}, len(other), context.temp_allocator)
	for id in other {
		present[id] = {}
	}
	count := 0
	for id in ids {
		count += id in present ? 0 : 1
	}
	return count
}

content_table_changes :: proc(old_tables, new_tables: Content_Tables) -> (changes: [Content_Table]Content_Table_Change) {
	for table in Content_Table {
		changes[table] = {count_missing_ids(new_tables[table], old_tables[table]), count_missing_ids(old_tables[table], new_tables[table])}
	}
	return changes
}

// "items +1, recipes +2 -1", or "no ids added or removed". In the temp
// allocator.
content_changes_text :: proc(changes: [Content_Table]Content_Table_Change) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for change, table in changes {
		switch {
		case change.added > 0 && change.removed > 0:
			append(&parts, fmt.tprintf("%s +%d -%d", content_table_names[table], change.added, change.removed))
		case change.added > 0:
			append(&parts, fmt.tprintf("%s +%d", content_table_names[table], change.added))
		case change.removed > 0:
			append(&parts, fmt.tprintf("%s -%d", content_table_names[table], change.removed))
		}
	}
	if len(parts) == 0 {
		return "no ids added or removed"
	}
	return strings.join(parts[:], ", ", context.temp_allocator)
}

// The simulation.

// The running world under new content. On a problem the old simulation is
// left as it was and nothing is returned. On success the old simulation
// has lost its chunks, its lighting queues and its column veins to the
// new one and is the caller's to destroy.
reload_simulation :: proc(old: ^Simulation_State, old_content, new_content: Simulation_Content, config: Game_Config) -> (reloaded: Simulation_State, problem: string) {
	header := make_save_header()
	snapshot := encode_entities(old, old_content, header)
	reloaded = make_reloaded_simulation(old^, new_content, config)
	remap: Content_Remap
	problem = decode_entities(&reloaded, new_content, snapshot, "the running world", header, &remap)
	if problem == "" {
		problem = move_world_chunks(&reloaded.world, &old.world, &remap)
	}
	if problem == "" {
		move_field_chunks(&reloaded.field, &old.field)
	}
	if problem != "" {
		destroy_simulation(&reloaded)
		return {}, problem
	}
	// The loaded chunks moved, so the set that holds them moves too; the
	// arrived chunks carry the old block ids and go with the old state.
	reloaded.chunk_set, old.chunk_set = old.chunk_set, reloaded.chunk_set
	return reloaded, ""
}

// Made the way a save's simulation is made (make_simulation_from_save),
// with what world.sjson would carry taken from the running one. Pending
// developer requests and events are dropped.
make_reloaded_simulation :: proc(old: Simulation_State, content: Simulation_Content, config: Game_Config) -> Simulation_State {
	state := make_simulation(config, player_start_on({}), content, content.technologies, old.unlocks.unlock_all, old.landing_pad)
	state.tick = old.tick
	state.tick_rate = old.tick_rate
	state.day_length_ticks = old.day_length_ticks
	state.day_offset_ticks = old.day_offset_ticks
	state.cheat_speed = old.cheat_speed
	state.world.settings = old.world.settings
	state.world.planet = old.world.planet
	return state
}

// Loaded chunks keep their blocks and light under the new block ids and
// get remeshed; unloaded modified chunks have their palettes remapped.
// Everything is checked before anything moves, so a refusal leaves both
// worlds as they were.
move_world_chunks :: proc(target, source: ^World, remap: ^Content_Remap) -> string {
	block_indices := remap.new_indices[.Blocks]
	if gone, found := gone_loaded_block(source.chunks, block_indices); found {
		return fmt.tprintf("a loaded chunk holds the block %s, which the new game data no longer has", remap.saved[.Blocks][gone])
	}
	saved_chunks, problem := remapped_saved_chunks(source.saved_chunks, remap)
	if problem != "" {
		return problem
	}
	delete(target.saved_chunks)
	target.saved_chunks = saved_chunks
	for _, chunk in source.chunks {
		remap_chunk_blocks(chunk, block_indices)
		chunk.dirty = true
	}
	target.chunks, source.chunks = source.chunks, target.chunks
	target.lighting, source.lighting = source.lighting, target.lighting
	target.column_veins, source.column_veins = source.column_veins, target.column_veins
	return ""
}

// The field's chunks, the changed ones outside the set, the arrivals and
// the set's restoring flag move to the reloaded field, whose tables decode_entities read; the water
// planet goes with them. The field holds no content ids.
move_field_chunks :: proc(target, source: ^Field_Simulation) {
	target.world.chunks, source.world.chunks = source.world.chunks, target.world.chunks
	target.world.water_awake_chunks, source.world.water_awake_chunks = source.world.water_awake_chunks, target.world.water_awake_chunks
	target.world.edited_chunks, source.world.edited_chunks = source.world.edited_chunks, target.world.edited_chunks
	target.world.water_planet = source.world.water_planet
	target.saved_chunks, source.saved_chunks = source.saved_chunks, target.saved_chunks
	target.arrived_chunks, source.arrived_chunks = source.arrived_chunks, target.arrived_chunks
	// A loaded set still waiting for its chunks (0185) keeps waiting.
	target.chunk_set.restoring = source.chunk_set.restoring
}

block_remap_is_identity :: proc(block_indices: []int) -> bool {
	for new_index, old_index in block_indices {
		if new_index != old_index {
			return false
		}
	}
	return true
}

// The first saved block index a loaded chunk holds that the new data
// lacks.
gone_loaded_block :: proc(chunks: map[Chunk_Coordinate]^Chunk, block_indices: []int) -> (gone: int, found: bool) {
	if block_remap_is_identity(block_indices) {
		return 0, false
	}
	for _, chunk in chunks {
		for block in chunk.blocks {
			if int(block) < len(block_indices) && block_indices[block] == CONTENT_GONE {
				return int(block), true
			}
		}
	}
	return 0, false
}

remap_chunk_blocks :: proc(chunk: ^Chunk, block_indices: []int) {
	if block_remap_is_identity(block_indices) {
		return
	}
	for &block in chunk.blocks {
		if int(block) < len(block_indices) {
			block = Block_Id(block_indices[block])
		}
	}
}

// Copies of the serialised chunks with their palettes remapped, or the
// problem.
remapped_saved_chunks :: proc(saved: map[Chunk_Coordinate][]byte, remap: ^Content_Remap) -> (chunks: map[Chunk_Coordinate][]byte, problem: string) {
	chunks = make(map[Chunk_Coordinate][]byte, len(saved))
	for coordinate, bytes in saved {
		copied := slice.clone(bytes)
		chunks[coordinate] = copied
		if remap_chunk_palette(copied, remap) {
			continue
		}
		problem = "an unloaded chunk is malformed"
		if remap.gone_chunk_block != "" {
			problem = fmt.tprintf("an unloaded chunk holds the block %s, which the new game data no longer has", remap.gone_chunk_block)
		}
		for _, chunk_bytes in chunks {
			delete(chunk_bytes)
		}
		delete(chunks)
		return nil, problem
	}
	return chunks, ""
}

// The session.

// The generator of the new generator data with the world's seed, vein
// richness and landing pad.
reloaded_session_generator :: proc(base, current: Generator) -> Generator {
	generator := session_generator(base, current.seed, current.vein_richness_percent)
	generator.landing_pad = current.landing_pad
	return generator
}

// Rebuilds the session under new data: the technologies with the world's
// research cost, the simulation (reload_simulation), the generator, and
// the streaming workers, which read the generator and the block registry.
// On a problem the session is unchanged. The views beside the session are
// reset by the caller (reload_content).
reload_session :: proc(session: ^Session, old_content: Game_Content, data: Game_Data, config: Game_Config) -> string {
	technologies := scaled_technology_registry(data.content.technologies, session.simulation.world.settings.research_cost_percent)
	field_content: Field_Content
	if session.simulation.field.enabled {
		field_content = make_field_content(config, data.content.items, data.content.machines, data.content.field_materials, data.content.lighting, session.planet, session.simulation.field.spacing_millimetres)
	}
	old_simulation_content := session_simulation_content(old_content, session.technologies, session.field_content)
	new_simulation_content := session_simulation_content(data.content, technologies, field_content)
	reloaded, problem := reload_simulation(&session.simulation, old_simulation_content, new_simulation_content, config)
	if problem != "" {
		delete(technologies.technologies)
		delete(field_content.brushes)
		return problem
	}
	delete(session.field_content.brushes)
	session.field_content = field_content
	load_around_camera := session.streaming.load_around_camera
	stop_chunk_streaming(&session.streaming)
	destroy_simulation(&session.simulation)
	session.simulation = reloaded
	delete(session.technologies.technologies)
	session.technologies = technologies
	session.generator = reloaded_session_generator(data.base_generator, session.generator)
	session.streaming = start_chunk_streaming(&session.generator, data.content.blocks, load_around_camera, default_worker_count())
	return ""
}

new_growing_arena :: proc() -> ^virtual.Arena {
	arena := new(virtual.Arena)
	if virtual.arena_init_growing(arena) != nil {
		free(arena)
		return nil
	}
	return arena
}

destroy_arena :: proc(arena: ^virtual.Arena) {
	if arena != nil {
		virtual.arena_destroy(arena)
		free(arena)
	}
}
