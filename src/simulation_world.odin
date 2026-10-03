package game

// The content tables the simulation reads, the entity tick's context and
// the tick order: players, unlocks, entities, launches, the venture,
// research, statistics, quests, then the world's part (world_tick.odin).

// The prototype tables the simulation reads, loaded once at startup.
// generator, when set, is the session's world generator, which the
// orbital survey asks for veins in chunks never loaded (venture.odin); it
// is only read.
Simulation_Content :: struct {
	blocks:       Block_Registry,
	items:        Item_Registry,
	machines:     Machine_Registry,
	fluids:       Fluid_Registry,
	recipes:      Recipe_Registry,
	technologies: Technology_Registry,
	quests:       Quest_Registry,
	veins:        Vein_Content,
	contracts:    Contract_Registry,
	// Chapter kits for the developer menu and --chapter.
	developer_kits: Developer_Kits,
	generator:    ^Generator,
	// The terrain field's tables for the session's planet, spacing and
	// tick rate (field_mining.odin, make_field_content); zero outside a
	// field session.
	field:        Field_Content,
}

// The content as a simulation sees it: the recipe registry carries the
// simulation's found schematics (with_schematics_found). The tick, the
// command socket's developer requests and the screens read the recipes
// through it.
content_with_found_schematics :: proc(content: Simulation_Content, unlocks: Recipe_Unlocks) -> Simulation_Content {
	result := content
	result.recipes = with_schematics_found(content.recipes, unlocks.schematics_found)
	return result
}

// The block query and the block write are the two procedures the plugin
// boundary will carry: procedure values with the data pointer they take,
// so the caller never holds ^World.
// Reads the block at position; an unloaded cell reads as air with loaded
// false.
Block_Query :: proc(data: rawptr, position: World_Coordinate) -> (block: Block_Id, loaded: bool)
// Sets the block at a loaded position; false when it is not loaded.
Block_Write :: proc(data: rawptr, position: World_Coordinate, block: Block_Id) -> bool

// What tick_entities and the kind ticks under it work on, built once per
// tick (world_tick_context). The blocks go through Block_Query and
// Block_Write with block_data, never through ^World: the entity tick does
// not see the chunk store. settings holds the world's rules the machines
// read (the draw seed, infinite veins, lenient byproducts). The vein
// registry still lives on World, so its fields come in as they are; the
// tick changes only the vein values and the spent outcrop queue, and
// registers no vein.
Entity_Tick_Context :: struct {
	entities:       ^Entities,
	records:        ^Game_Records,
	content:        Simulation_Content,
	tick_rate:      int,
	settings:       World_Settings,
	veins:          []Vein,
	vein_indices:   map[Vein_Id]int,
	column_veins:   map[Chunk_Column][dynamic]Vein_Id,
	outcrop_cells:  map[World_Coordinate]Vein_Id,
	spent_outcrops: ^[dynamic]World_Coordinate,
	block_data:     rawptr,
	query_block:    Block_Query,
	write_block:    Block_Write,
}

// The context over a world's entities, veins and blocks. spill_stack,
// outside the tick, passes no records.
world_tick_context :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, tick_rate: int) -> Entity_Tick_Context {
	return Entity_Tick_Context {
		entities = &world.entities,
		records = records,
		content = content,
		tick_rate = tick_rate,
		settings = world.settings,
		veins = world.veins[:],
		vein_indices = world.vein_indices,
		column_veins = world.column_veins,
		outcrop_cells = world.outcrop_cells,
		spent_outcrops = &world.spent_outcrops,
		block_data = world,
		query_block = world_query_block,
		write_block = world_write_block,
	}
}

world_query_block :: proc(data: rawptr, position: World_Coordinate) -> (block: Block_Id, loaded: bool) {
	cell, loaded_cell := world_cell((^World)(data), position)
	if !loaded_cell {
		return AIR_BLOCK, false
	}
	return cell_block(cell), true
}

world_write_block :: proc(data: rawptr, position: World_Coordinate, block: Block_Id) -> bool {
	return world_set_block((^World)(data), position, block)
}

tick_get_block :: proc(tick_context: Entity_Tick_Context, position: World_Coordinate) -> (block: Block_Id, loaded: bool) {
	return tick_context.query_block(tick_context.block_data, position)
}

tick_set_block :: proc(tick_context: Entity_Tick_Context, position: World_Coordinate, block: Block_Id) -> bool {
	return tick_context.write_block(tick_context.block_data, position, block)
}

// registered_vein on the context's vein registry.
tick_vein :: proc(tick_context: Entity_Tick_Context, id: Vein_Id) -> ^Vein {
	return vein_of_id(tick_context.veins, tick_context.vein_indices, id)
}

// The tick's outcrop step: the queued cells (veins exhausted by drills
// this tick, register_outcrop_cells on chunk load) turn to spent rock
// through the block write (world_set_block), so light and remeshing
// follow. A cell the player mined or built over keeps its block.
apply_spent_outcrops :: proc(tick_context: Entity_Tick_Context) {
	veins := tick_context.content.veins
	for position in tick_context.spent_outcrops^ {
		vein := tick_vein(tick_context, tick_context.outcrop_cells[position])
		block, _ := tick_get_block(tick_context, position)
		if vein != nil && vein_block_is_outcrop(veins, vein^, block) {
			tick_set_block(tick_context, position, veins.spent_block)
		}
	}
	clear(tick_context.spent_outcrops)
}

// The entity tick on the world's blocks, then the lit lamps' lights into
// the world's light queues, which tick_world spreads.
tick_entities_on_world :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, tick_rate: int, profile: ^Tick_Profile = nil) {
	tick_entities(world_tick_context(world, records, content, tick_rate), profile)
	clock := profile_now(profile)
	sync_entity_lights(world, lit_lamp_lights(&world.entities, content.machines))
	profile_section(profile, .Lamps, clock)
}

// A player without an input entry gets an empty one. The simulated chunk
// set and the queued commands come first (simulation_chunk_set.odin,
// player_command.odin). Entities tick after
// the players, so a stack dropped into a furnace this tick is seen at once.
// Machines see the found schematics through the recipe registry
// (recipe_runs_in_machines). A profile (tick_profile.odin) gets the wall
// time of each step. A field session's players walk the terrain field
// instead (tick_field_session_players, simulation_field.odin), whose
// edits, placements, water and light finish before the entities tick.
// Code outside the simulation run inside the tick, after the simulated
// chunk set is derived and before the player commands apply: the lockstep
// driver's socket lines (lockstep.odin).
Tick_Hook :: struct {
	procedure: proc(data: rawptr),
	data:      rawptr,
}

simulation_tick :: proc(state: ^Simulation_State, content_tables: Simulation_Content, inputs: []Input_Frame, profile: ^Tick_Profile = nil, hook := Tick_Hook{}) {
	clock := profile_now(profile)
	content := content_with_found_schematics(content_tables, state.unlocks)
	clock = profile_section(profile, .Unlocks, clock)
	state.tick += 1
	advance_statistics_clock(&state.records.statistics, state.tick, state.tick_rate)
	clock = profile_section(profile, .Statistics, clock)
	update_simulated_chunks(state, content)
	if hook.procedure != nil {
		hook.procedure(hook.data)
	}
	apply_player_commands(state, content)
	if state.field.enabled {
		tick_field_session_players(state, content, inputs)
	}
	for index in 0 ..< len(state.players) {
		if state.field.enabled {
			break
		}
		input, used := resolve_use_item(&state.players[index], &state.world.entities, content.items, index < len(inputs) ? inputs[index] : Input_Frame{})
		if used != NO_ITEM {
			if event, happened := apply_item_use(state, content, index, used); happened {
				append(&state.events, Simulation_Event{player = index, kind = event})
			}
		}
		before := movement_toggles(state.players[index])
		events := tick_player(&state.world, &state.records, content, state.players[:], index, input, state.tick_rate, state.tick, state.cheat_speed)
		log_movement_toggles(before, state.players[index], player_tick_toggle_cause(input.just_pressed), state.tick)
		update_magnetometer(&state.world, content, &state.players[index])
		for kind in events {
			append(&state.events, Simulation_Event{player = index, kind = kind})
		}
	}
	clock = profile_section(profile, .Players, clock)
	newly_obtained := update_recipe_unlocks(&state.unlocks, content.recipes, state.players[:])
	log_discoveries(&state.quests, content.blocks, content.items, newly_obtained, state.tick)
	clock = profile_section(profile, .Unlocks, clock)
	tick_entities_on_world(&state.world, &state.records, content, state.tick_rate, profile)
	clock = profile_now(profile)
	shipments_before := len(state.records.shipments)
	apply_launch_requests(&state.world, &state.records, state.tick)
	clock = profile_section(profile, .Launch_Pads, clock)
	tick_venture(state, content, shipments_before)
	clock = profile_section(profile, .Venture, clock)
	apply_research_result(state, content)
	clock = profile_section(profile, .Research, clock)
	observe_player_holdings(&state.records.statistics, state.players[:], true)
	observe_full_inventories(&state.records.statistics, state.players[:])
	clock = profile_section(profile, .Statistics, clock)
	tick_quests(&state.quests, simulation_quest_context(state, content), &state.world.entities)
	clock = profile_section(profile, .Quests, clock)
	tick_world(&state.world, &state.records.leaf_decay, content.blocks, state.tick, simulation_tree_felling(content))
	profile_section(profile, .World, clock)
	if profile != nil {
		profile.ticks += 1
	}
}

// Opens the recipes of a technology the labs finished this tick and says
// so in the message log.
apply_research_result :: proc(state: ^Simulation_State, content: Simulation_Content) {
	if technology, finished := apply_finished_research(&state.records.research, &state.unlocks, content.recipes); finished {
		log_research_complete(&state.quests, state.tick, content.technologies.technologies[technology].name_key)
	}
}

simulation_quest_context :: proc(state: ^Simulation_State, content: Simulation_Content) -> Quest_Tick_Context {
	return Quest_Tick_Context {
		registry = content.quests,
		recipes = content.recipes,
		items = content.items,
		statistics = &state.records.statistics,
		unlocks = &state.unlocks,
		tick = state.tick,
		tick_rate = state.tick_rate,
	}
}
