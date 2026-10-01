package game

import "core:fmt"
import "core:strings"
import "core:time"
import "generation_seed"
import "platform"

// A played world: the simulation, the generator its chunks stream from,
// the streaming workers and where it saves. The title screen runs without
// one; starting or loading a world makes one and quitting to the title
// destroys it. Heap allocated, since the streaming workers keep a pointer
// to its generator.
Session :: struct {
	simulation:         Simulation_State,
	generator:          Generator,
	streaming:          Chunk_Streaming,
	start:              World_Start,
	// The content's technologies with this world's research cost applied.
	technologies:       Technology_Registry,
	// Saving is off for the debug terrain and without a saves directory.
	// The location's names are owned by the session.
	save:               Save_Setup,
	// Set by the pause menu's Save button, handled after the ticks.
	save_requested:     bool,
	ticks_since_save:   u64,
	accumulator:        Tick_Accumulator,
	tick_input:         Tick_Input_Accumulator,
	debug_edit_counter: u64,
	// The weather command's forced kind (work item 0063), nil for the
	// schedule. Not saved.
	weather_override:   Maybe(Weather_Kind),
}

// What a session starts from: a new world's seed and settings, or a save.
// Strings need to live only until start_session returns.
Session_Plan :: struct {
	loading:       bool,
	debug_terrain: bool,
	seed:          u64,
	settings:      World_File_Settings,
	file:          World_File,
	directory:     string,
	save:          Save_Setup,
}

// The content with the world's technologies.
session_simulation_content :: proc(content: Game_Content, technologies: Technology_Registry) -> Simulation_Content {
	simulation_content := content.simulation_content
	simulation_content.technologies = technologies
	return simulation_content
}

// The generator's data is the same for every world; the seed, the vein
// richness and the landing pad are the world's.
session_generator :: proc(base: Generator, seed: u64, vein_richness_percent: int) -> Generator {
	generator := base
	generator.seed = seed
	generator.seeds = generation_seed.derive_purpose_seeds(seed)
	generator.vein_richness_percent = vein_richness_percent
	generator.landing_pad = {}
	return generator
}

// A save setup whose location names the session owns.
clone_save_setup :: proc(save: Save_Setup) -> Save_Setup {
	result := save
	result.location.directory_name = strings.clone(save.location.directory_name)
	result.location.display_name = strings.clone(save.location.display_name)
	return result
}

make_session_simulation :: proc(plan: Session_Plan, config: Game_Config, content: Game_Content, session: ^Session) -> (simulation: Simulation_State, problem: string) {
	world_config := config
	world_config.day_length_seconds = plan.settings.day_length_seconds
	simulation_content := session_simulation_content(content, session.technologies)
	start := session.start
	if plan.loading {
		simulation, problem = make_simulation_from_save(world_config, start.player, simulation_content, start.landing_pad, plan.directory, plan.file)
		if problem == "" {
			platform.log_printf("world: loaded %q at tick %d from %s", plan.file.name, plan.file.tick, plan.directory)
		}
		return simulation, problem
	}
	unlock_all := plan.settings.all_recipes_unlocked || content.unlock_all
	simulation = make_simulation(world_config, start.player, simulation_content, session.technologies, unlock_all, start.landing_pad)
	simulation.world.settings = world_settings_from_file(plan.seed, plan.settings)
	return simulation, ""
}

// Returns nil and the problem when the world cannot be made or loaded.
start_session :: proc(plan: Session_Plan, config: Game_Config, content: Game_Content, base_generator: Generator) -> (session: ^Session, problem: string) {
	session = new(Session)
	session.generator = session_generator(base_generator, plan.seed, plan.settings.vein_richness_percent)
	session.technologies = scaled_technology_registry(content.technologies, plan.settings.research_cost_percent)
	if start, saved := saved_world_start(&session.generator, plan.loading, plan.file); saved {
		session.start = start
	} else {
		session.start = choose_world_start(&session.generator, plan.debug_terrain)
	}
	session.simulation, problem = make_session_simulation(plan, config, content, session)
	if problem == "" && plan.debug_terrain {
		problem = build_session_debug_terrain(&session.simulation.world, content.blocks)
	}
	if problem != "" {
		destroy_simulation(&session.simulation)
		delete(session.technologies.technologies)
		free(session)
		return nil, problem
	}
	session.save = clone_save_setup(plan.save)
	session.accumulator = make_tick_accumulator(config.tick_rate)
	session.streaming = start_chunk_streaming(&session.generator, content.blocks, !plan.debug_terrain, default_worker_count())
	return session, ""
}

build_session_debug_terrain :: proc(world: ^World, registry: Block_Registry) -> string {
	terrain_blocks, ok := resolve_debug_terrain_blocks(registry)
	if !ok {
		return "the debug terrain blocks are missing"
	}
	build_debug_terrain(world, registry, terrain_blocks)
	return ""
}

// Workers read the session's generator, so they stop first.
end_session :: proc(session: ^Session) {
	stop_chunk_streaming(&session.streaming)
	destroy_simulation(&session.simulation)
	delete(session.technologies.technologies)
	delete(session.save.location.directory_name)
	delete(session.save.location.display_name)
	free(session)
}

// Between ticks, so the simulation stands still while the save is written.
// Returns the problem, empty on success.
save_session :: proc(session: ^Session, content: Game_Content) -> string {
	if !session.save.enabled {
		return "saving is off for this world"
	}
	simulation_content := session_simulation_content(content, session.technologies)
	problem := save_world(&session.simulation, simulation_content, session.save.location, time.to_unix_seconds(time.now()))
	if problem == "" {
		session.ticks_since_save = 0
	} else {
		platform.log_printf("error: saving %q failed: %s", session.save.location.display_name, problem)
	}
	return problem
}

// A new world saves under its name, or the name with a number when a save
// of that name exists. Without a saves directory, or on the debug terrain,
// it does not save. Strings in the temp allocator.
new_world_save_setup :: proc(display_name, saves_directory: string, saves_found, debug_terrain: bool) -> Save_Setup {
	switch {
	case debug_terrain:
		platform.log_printf("world: saving is off for the debug terrain")
		return {}
	case !saves_found:
		platform.log_printf("world: saving is off (set %s, %s)", SAVES_DIRECTORY_ENVIRONMENT_VARIABLE, platform.DATA_HOME_VARIABLES)
		return {}
	}
	directory_name := unused_world_directory_name(saves_directory, sanitize_world_name(display_name, context.temp_allocator), context.temp_allocator)
	platform.log_printf("world: new world %q, saves to %s", display_name, platform.join_path(saves_directory, directory_name))
	location := Save_Location {
		saves_directory = saves_directory,
		directory_name  = directory_name,
		display_name    = display_name,
	}
	return Save_Setup{location = location, enabled = true}
}

new_world_plan :: proc(display_name: string, seed: u64, settings: World_File_Settings, saves_directory: string, saves_found, debug_terrain: bool) -> Session_Plan {
	return Session_Plan {
		debug_terrain = debug_terrain,
		seed = seed,
		settings = settings,
		save = new_world_save_setup(display_name, saves_directory, saves_found, debug_terrain),
	}
}

// The save in <saves>/<directory_name>, or the problem. In the temp
// allocator.
saved_world_plan :: proc(saves_directory, directory_name: string) -> (plan: Session_Plan, problem: string) {
	location := Save_Location {
		saves_directory = saves_directory,
		directory_name  = directory_name,
	}
	directory, found := existing_save_directory(location)
	if !found {
		return {}, fmt.tprintf("no saved world %q in %s", directory_name, saves_directory)
	}
	file: World_File
	file, problem = read_world_file(directory, context.temp_allocator)
	if problem != "" {
		return {}, problem
	}
	location.display_name = file.name
	plan = Session_Plan {
		loading   = true,
		seed      = file.seed,
		settings  = file.settings,
		file      = file,
		directory = directory,
		save      = Save_Setup{location = location, enabled = true},
	}
	return plan, ""
}
