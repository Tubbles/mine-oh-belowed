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
//
// New World and Load start a field session (work item 0179): the players
// walk the terrain field of the world's planet (Simulation_State.field),
// whose chunks the field streaming's workers generate and mesh
// (field_streaming); the block world's set and its streaming stay idle.
// A world made without planet data (the tests' block worlds) and the debug
// terrain are block sessions.
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
	debug_edit_counter: u64,
	// The weather command's forced kind (work item 0063), nil for the
	// schedule. Not saved.
	weather_override:   Maybe(Weather_Kind),
	// Who drives the simulation and when a tick runs (lockstep.odin), and
	// the other machines of the session (session_network.odin).
	lockstep:           Lockstep,
	network:            Session_Network,
	// The last ready check stopped on a missing chunk of the simulated set
	// (run_ready_ticks), and the frames in a row no tick ran because of it:
	// the frame shows the loading notice after a few.
	chunk_stalled:      bool,
	stalled_frames:     int,
	// The planet the world generates on, the data's record with the values
	// the world was made with (resolve_world_planet); the world's planet
	// and its settings' planet id borrow it.
	planet:             Planet,
	// A field session's workers (generating the simulated set's chunks and
	// meshing the level of detail's nodes) and its field tables
	// (Simulation_Content.field, its brushes owned); zero in a block
	// session.
	field_streaming:    Field_Streaming,
	field_content:      Field_Content,
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
	// A host's world joined over the network (session_network.odin): the
	// save's bytes instead of directory.
	files:         ^Save_Files,
}

// The content with the world's technologies and field tables.
session_simulation_content :: proc(content: Game_Content, technologies: Technology_Registry, field: Field_Content) -> Simulation_Content {
	simulation_content := content.simulation_content
	simulation_content.technologies = technologies
	simulation_content.field = field
	return simulation_content
}

// A loaded world plays the field when its file says so; a new one when
// the data has planets and it is not the debug terrain.
session_plays_field :: proc(plan: Session_Plan, content: Game_Content) -> bool {
	if plan.loading {
		return plan.file.field_world
	}
	return len(content.planets) > 0 && !plan.debug_terrain
}

// The field of a field session, once its simulation and planet are set:
// its tables, a new world's field with the pod and its first player at
// the home, a loaded world's set left restoring for the workers to
// generate (Field_Chunk_Set.restoring, 0185), the
// planet's veins registered (register_planet_veins: a new world's
// reservoirs, a loaded world's discs again), the water's planet, an old
// save's trees in its frames cleared (clear_trees_of_an_old_save, 0197)
// and the workers.
start_field_world :: proc(session: ^Session, plan: Session_Plan, config: Game_Config, content: Game_Content) -> string {
	simulation := &session.simulation
	field := &simulation.field
	seed := simulation.world.settings.seed
	spacing := plan.loading ? field.spacing_millimetres : plan.settings.sample_spacing_millimetres
	session.field_content = make_field_content(config, content.items, content.machines, content.field_materials, content.lighting, session.planet, spacing)
	if !plan.loading {
		enable_new_field_world(simulation, config, content.machines, session.field_content, session.planet, spacing)
		begin_field_arrival(field, simulation.tick, config.arrival_ticks)
		if field_arrival_falling(field.arrival) {
			strap_players_for_the_fall(simulation, content.machines, session.field_content.tuning)
		}
	}
	field.world.water_planet = make_field_water_planet(seed, session.planet, field.spacing_millimetres)
	field.chunk_set.restoring = plan.loading && len(field.chunk_set.chunks) > 0
	world := &simulation.world
	generation := make_planet_generation(seed, session.planet, field.spacing_millimetres)
	if problem := register_planet_veins(&world.veins, &world.vein_indices, generation, session.generator.veins); problem != "" {
		return problem
	}
	if plan.loading {
		clear_trees_of_an_old_save(simulation, content.machines, session.field_content)
	}
	session.field_streaming = start_field_streaming(seed, session.planet, field.spacing_millimetres, default_worker_count())
	return ""
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
	simulation_content := session_simulation_content(content, session.technologies, {})
	start := session.start
	if plan.loading && plan.files != nil {
		simulation = make_simulation(world_config, start.player, simulation_content, simulation_content.technologies, plan.file.settings.all_recipes_unlocked, start.landing_pad)
		problem = load_world_from_files(&simulation, simulation_content, plan.files^, plan.file, "the host's world")
		return simulation, problem
	}
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

// The plan's settings, in the file too when loading, with the planet
// resolved against the data (resolve_world_planet); the planet goes to the
// session. A new world's home is the nearest dry whole degree point
// (new_world_home, 0180); a loaded world keeps its recorded home.
resolve_session_planet :: proc(plan: Session_Plan, planets: []Planet, session: ^Session) -> Session_Plan {
	resolved := plan
	settings, planet, record := resolve_world_planet(plan.settings, plan.file.planet_generation, planets, plan.loading)
	if len(planets) > 0 {
		// A loaded world whose planet the data lost keeps its own id.
		named := planet
		named.id = settings.planet_id
		session.planet = make_recorded_planet(named, record)
		if !plan.loading {
			session.planet.home = new_world_home(plan.seed, session.planet)
		}
		settings.planet_id = session.planet.id
	}
	resolved.settings = settings
	if plan.loading {
		resolved.file.settings = settings
	}
	return resolved
}

// Returns nil and the problem when the world cannot be made or loaded.
start_session :: proc(requested_plan: Session_Plan, config: Game_Config, content: Game_Content, base_generator: Generator) -> (session: ^Session, problem: string) {
	session = new(Session)
	plan := resolve_session_planet(requested_plan, content.planets, session)
	session.generator = session_generator(base_generator, plan.seed, plan.settings.vein_richness_percent)
	session.technologies = scaled_technology_registry(content.technologies, plan.settings.research_cost_percent)
	field := session_plays_field(plan, content)
	if start, saved := saved_world_start(&session.generator, plan.loading, plan.file); saved {
		session.start = start
	} else if field {
		session.start = field_world_start()
	} else {
		session.start = choose_world_start(&session.generator, plan.debug_terrain)
	}
	session.simulation, problem = make_session_simulation(plan, config, content, session)
	session.simulation.world.planet = session.planet
	if problem == "" && plan.debug_terrain {
		problem = build_session_debug_terrain(&session.simulation.world, content.blocks)
	}
	if problem == "" && field {
		problem = start_field_world(session, plan, config, content)
	}
	if problem != "" {
		if session.field_streaming.shared != nil {
			stop_field_streaming(&session.field_streaming)
		}
		destroy_field_content(&session.field_content)
		destroy_simulation(&session.simulation)
		delete(session.technologies.technologies)
		destroy_recorded_planet(&session.planet)
		free(session)
		return nil, problem
	}
	session.save = clone_save_setup(plan.save)
	session.accumulator = make_tick_accumulator(config.tick_rate)
	if !plan.debug_terrain && !field {
		session.simulation.chunk_set = make_simulated_chunk_set(config.simulated_chunk_radius_horizontal, config.simulated_chunk_radius_vertical)
	}
	session.lockstep = make_single_player_lockstep(session.simulation.tick, session.start.player)
	session.streaming = start_chunk_streaming(&session.generator, content.blocks, !plan.debug_terrain && !field, default_worker_count())
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
	if session.field_streaming.shared != nil {
		stop_field_streaming(&session.field_streaming)
	}
	destroy_field_content(&session.field_content)
	destroy_session_network(&session.network)
	destroy_lockstep(&session.lockstep)
	destroy_simulation(&session.simulation)
	delete(session.technologies.technologies)
	destroy_recorded_planet(&session.planet)
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
	simulation_content := session_simulation_content(content, session.technologies, session.field_content)
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
	if !file.field_world {
		return {}, fmt.tprintf("%q is a block world, which this build does not play; the dev kits are not rebuilt here (M14)", file.name)
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
