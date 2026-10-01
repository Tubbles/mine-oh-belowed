package game

// The simulation's state, the part the tick advances and a save holds
// except its per tick queues (save_state.odin), and its set-up and
// teardown. The tick is simulation_tick
// (simulation_world.odin).

// The simulation owns the world and the players. players[index] reads
// inputs[index] in simulation_tick; the alpha has one player.
Simulation_State :: struct {
	tick:             u64,
	tick_rate:        int,
	day_length_ticks: u64,
	// Added to the tick for the day cycle, so the developer menu can set
	// the time of day without moving the tick every counter reads. Saved
	// through world.sjson's day_time_ticks.
	day_offset_ticks: u64,
	world:            World,
	players:          [dynamic]Player,
	// Items obtained, technologies researched and the recipes they unlock.
	unlocks:          Recipe_Unlocks,
	quests:           Quest_State,
	// Filled by ticks, emptied by the UI each frame (toasts). The
	// simulation never calls the UI itself.
	events:           [dynamic]Simulation_Event,
	// Filled by the developer menu and the command line, served and
	// emptied at the start of the next tick (developer.odin).
	developer_requests: [dynamic]Developer_Request,
	// Developer cheat speed (0044): faster movement and hand mining. Not
	// saved.
	cheat_speed:        bool,
	// The pad the world was created with, written to world.sjson so a loaded
	// world keeps it whatever the spawn rules do later (0049).
	landing_pad:        Landing_Pad_Site,
}

Simulation_Event :: struct {
	player: int,
	kind:   Player_Event,
}

// The config's starting items must have passed validate_starting_items.
// unlock_all makes every recipe available (--unlock-all or the setting).
// The capsule stands on the landing pad from the start, and the first
// quest is active at tick 0.
make_simulation :: proc(config: Game_Config, start: Player_Start, content: Simulation_Content, technologies: Technology_Registry, unlock_all: bool, landing_pad: Landing_Pad_Site) -> Simulation_State {
	state := Simulation_State {
		tick_rate        = config.tick_rate,
		day_length_ticks = u64(config.day_length_seconds) * u64(config.tick_rate),
		unlocks          = make_recipe_unlocks(len(content.items.items), content.recipes, technologies, unlock_all),
		landing_pad      = landing_pad,
	}
	state.world.statistics = make_statistics(len(content.items.items), len(content.machines.machines), len(content.blocks.definitions))
	state.world.statistics.fluids = make_fluid_statistics(len(content.fluids.fluids))
	state.world.entities.loose_items.despawn_ticks = loose_item_despawn_ticks(config.loose_item_despawn_minutes, config.tick_rate)
	capsule := place_capsule(&state.world.entities, content.machines, landing_pad)
	state.quests = make_quest_state(content.quests, capsule)
	player := make_player(start)
	give_starting_items(&player, content.items, config.starting_items)
	append(&state.players, player)
	update_recipe_unlocks(&state.unlocks, content.recipes, state.players[:])
	observe_player_holdings(&state.world.statistics, state.players[:], false)
	start_quests(&state.quests, content.quests, state.world.statistics, 0)
	return state
}

destroy_simulation :: proc(state: ^Simulation_State) {
	for player in state.players {
		destroy_player(player)
	}
	delete(state.players)
	delete(state.events)
	delete(state.developer_requests)
	destroy_recipe_unlocks(state.unlocks)
	destroy_quest_state(state.quests)
	destroy_world(&state.world)
}

// The capsule on the pad, or NO_ENTITY without a site or a capsule machine.
place_capsule :: proc(entities: ^Entities, machines: Machine_Registry, site: Landing_Pad_Site) -> Entity_Handle {
	machine := find_machine_of_kind(machines, .Capsule)
	if !site.present || machine == NO_MACHINE {
		return NO_ENTITY
	}
	return add_entity(entities, machines, machine, site.centre + CAPSULE_OFFSET, 0)
}

// The tick the day cycle shows.
simulation_day_ticks :: proc(state: Simulation_State) -> u64 {
	return state.tick + state.day_offset_ticks
}
