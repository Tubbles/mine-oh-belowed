package game

// The content tables the simulation reads and the tick order: players,
// unlocks, entities, launches, the venture, research, statistics, quests,
// then the world's part (world_tick.odin).

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
}

// A player without an input entry gets an empty one. Entities tick after
// the players, so a stack dropped into a furnace this tick is seen at once.
// Machines see the found schematics through the recipe registry
// (recipe_runs_in_machines). A profile (tick_profile.odin) gets the wall
// time of each step.
simulation_tick :: proc(state: ^Simulation_State, content_tables: Simulation_Content, inputs: []Input_Frame, profile: ^Tick_Profile = nil) {
	clock := profile_now(profile)
	content := content_tables
	content.recipes = with_schematics_found(content.recipes, state.unlocks.schematics_found)
	clock = profile_section(profile, .Unlocks, clock)
	state.tick += 1
	advance_statistics_clock(&state.world.statistics, state.tick, state.tick_rate)
	clock = profile_section(profile, .Statistics, clock)
	serve_developer_requests(state, content)
	for index in 0 ..< len(state.players) {
		input, used := resolve_use_item(&state.players[index], &state.world.entities, content.items, index < len(inputs) ? inputs[index] : Input_Frame{})
		if used != NO_ITEM {
			if event, happened := apply_item_use(state, content, index, used); happened {
				append(&state.events, Simulation_Event{player = index, kind = event})
			}
		}
		before := movement_toggles(state.players[index])
		events := tick_player(&state.world, content, state.players[:], index, input, state.tick_rate, state.tick, state.cheat_speed)
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
	tick_entities(&state.world, content, state.tick_rate, profile)
	clock = profile_now(profile)
	shipments_before := len(state.world.shipments)
	apply_launch_requests(&state.world, state.tick)
	clock = profile_section(profile, .Launch_Pads, clock)
	tick_venture(state, content, shipments_before)
	clock = profile_section(profile, .Venture, clock)
	apply_research_result(state, content)
	clock = profile_section(profile, .Research, clock)
	observe_player_holdings(&state.world.statistics, state.players[:], true)
	observe_full_inventories(&state.world.statistics, state.players[:])
	clock = profile_section(profile, .Statistics, clock)
	tick_quests(&state.quests, simulation_quest_context(state, content), &state.world.entities)
	clock = profile_section(profile, .Quests, clock)
	tick_world(&state.world, content.blocks, state.tick, simulation_tree_felling(content))
	profile_section(profile, .World, clock)
	if profile != nil {
		profile.ticks += 1
	}
}

// Opens the recipes of a technology the labs finished this tick and says
// so in the message log.
apply_research_result :: proc(state: ^Simulation_State, content: Simulation_Content) {
	if technology, finished := apply_finished_research(&state.world.research, &state.unlocks, content.recipes); finished {
		log_research_complete(&state.quests, state.tick, content.technologies.technologies[technology].name_key)
	}
}

simulation_quest_context :: proc(state: ^Simulation_State, content: Simulation_Content) -> Quest_Tick_Context {
	return Quest_Tick_Context {
		registry = content.quests,
		recipes = content.recipes,
		items = content.items,
		statistics = &state.world.statistics,
		unlocks = &state.unlocks,
		tick = state.tick,
		tick_rate = state.tick_rate,
	}
}
