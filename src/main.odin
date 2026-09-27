package game

import "core:fmt"
import "core:os"
import "core:strings"

GAME_VERSION :: "0.0.0"

INPUT_ARGUMENT_PREFIX :: "--input="
SEED_ARGUMENT_PREFIX :: "--seed="
LOAD_ARGUMENT_PREFIX :: "--load="
NAME_ARGUMENT_PREFIX :: "--name="
SUPPORTED_ARGUMENTS :: "--version, --input=sdl3, --input=raylib, --seed=<number>, --name=<world name>, --load=<world name>, --debug-terrain, --unlock-all"

Input_Backend_Request :: enum u8 {
	Automatic,
	Sdl3,
	Raylib,
}

Command_Line :: struct {
	show_version:        bool,
	input_request:       Input_Backend_Request,
	seed:                u64,
	seed_given:          bool,
	// The saved world to load (--load), or empty for a new world.
	load_name:           string,
	// The name of a new world (--name), DEFAULT_WORLD_NAME when empty.
	world_name:          string,
	debug_terrain:       bool,
	// Developer flag: every technology researched and every item discovered.
	unlock_all:          bool,
	unknown_argument:    string,
	unknown_input_value: string,
	invalid_seed_value:  string,
}

parse_input_request :: proc(value: string) -> (request: Input_Backend_Request, ok: bool) {
	switch value {
	case "sdl3":
		return .Sdl3, true
	case "raylib":
		return .Raylib, true
	}
	return .Automatic, false
}

// Decimal digits only. strconv would accept separators and silently wrap
// values past the u64 range.
parse_seed :: proc(value: string) -> (seed: u64, ok: bool) {
	if value == "" {
		return 0, false
	}
	for character in transmute([]u8)value {
		if character < '0' || character > '9' {
			return 0, false
		}
		digit := u64(character - '0')
		if seed > (max(u64) - digit) / 10 {
			return 0, false
		}
		seed = seed * 10 + digit
	}
	return seed, true
}

parse_command_line :: proc(arguments: []string) -> Command_Line {
	command_line := Command_Line {
		seed = DEFAULT_WORLD_SEED,
	}
	for argument in arguments {
		if strings.has_prefix(argument, SEED_ARGUMENT_PREFIX) {
			value := argument[len(SEED_ARGUMENT_PREFIX):]
			seed, ok := parse_seed(value)
			if !ok {
				command_line.invalid_seed_value = value
				return command_line
			}
			command_line.seed = seed
			command_line.seed_given = true
			continue
		}
		if strings.has_prefix(argument, LOAD_ARGUMENT_PREFIX) {
			command_line.load_name = argument[len(LOAD_ARGUMENT_PREFIX):]
			continue
		}
		if strings.has_prefix(argument, NAME_ARGUMENT_PREFIX) {
			command_line.world_name = argument[len(NAME_ARGUMENT_PREFIX):]
			continue
		}
		if strings.has_prefix(argument, INPUT_ARGUMENT_PREFIX) {
			value := argument[len(INPUT_ARGUMENT_PREFIX):]
			request, ok := parse_input_request(value)
			if !ok {
				command_line.unknown_input_value = value
				return command_line
			}
			command_line.input_request = request
			continue
		}
		switch argument {
		case "--version":
			command_line.show_version = true
		case "--debug-terrain":
			command_line.debug_terrain = true
		case "--unlock-all":
			command_line.unlock_all = true
		case:
			command_line.unknown_argument = argument
			return command_line
		}
	}
	return command_line
}

// Prints which backend is active and why. Fails only when SDL3 was asked for
// explicitly, so that a broken SDL setup cannot hide behind the fallback.
start_input_backend :: proc(request: Input_Backend_Request) -> (backend: Input_Backend, ok: bool) {
	if request == .Raylib {
		fmt.eprintln("input: raylib backend (requested with --input=raylib)")
		return .Raylib, true
	}
	sdl3_ready, error_message := init_sdl3_input()
	switch {
	case sdl3_ready:
		fmt.eprintfln("input: sdl3 backend (%s)", request == .Sdl3 ? "requested with --input=sdl3" : "default")
		return .Sdl3, true
	case request == .Sdl3:
		fmt.eprintfln("error: --input=sdl3 but SDL failed to initialise: %s", error_message)
		return .Raylib, false
	}
	fmt.eprintfln("input: raylib backend (SDL3 failed to initialise: %s)", error_message)
	return .Raylib, true
}

main :: proc() {
	command_line := parse_command_line(os.args[1:])
	if command_line.unknown_argument != "" {
		fmt.eprintfln("error: unknown argument %q (supported: %s)", command_line.unknown_argument, SUPPORTED_ARGUMENTS)
		os.exit(2)
	}
	if command_line.invalid_seed_value != "" {
		fmt.eprintfln("error: invalid seed %q (expected an unsigned 64 bit integer, for example --seed=12345)", command_line.invalid_seed_value)
		os.exit(2)
	}
	if command_line.unknown_input_value != "" {
		fmt.eprintfln("error: unknown input backend %q (supported: --input=sdl3, --input=raylib)", command_line.unknown_input_value)
		os.exit(2)
	}
	if command_line.show_version {
		fmt.printfln("Mine oh Belowed %s", GAME_VERSION)
		return
	}
	if problem := command_line_conflict(command_line); problem != "" {
		fmt.eprintfln("error: %s", problem)
		os.exit(2)
	}
	data_directory, found := resolve_data_directory()
	if !found {
		fmt.eprintfln(
			"error: no data directory found. Set %s, run from the repository root (./%s), or install to <executable directory>/%s",
			DATA_DIRECTORY_ENVIRONMENT_VARIABLE,
			WORKING_DIRECTORY_DATA,
			INSTALLED_DATA_RELATIVE_TO_EXECUTABLE,
		)
		os.exit(1)
	}
	config, loaded := load_game_config(data_directory)
	if !loaded {
		os.exit(1)
	}
	string_table, strings_loaded := load_string_table(data_directory)
	if !strings_loaded {
		os.exit(1)
	}
	global_string_table = string_table
	registry, registry_loaded := load_block_registry(data_directory)
	if !registry_loaded {
		os.exit(1)
	}
	items, items_loaded := load_item_registry(data_directory, registry)
	if !items_loaded {
		os.exit(1)
	}
	fluids, fluids_loaded := load_fluid_registry(data_directory)
	if !fluids_loaded {
		os.exit(1)
	}
	machines, machines_loaded := load_machine_registry(data_directory, items, fluids)
	if !machines_loaded {
		os.exit(1)
	}
	recipes, recipes_loaded := load_recipe_registry(data_directory, items)
	if !recipes_loaded {
		os.exit(1)
	}
	technologies, technologies_loaded := load_technology_registry(data_directory, items, recipes)
	if !technologies_loaded {
		os.exit(1)
	}
	machines.lab_packs = technologies.science_packs
	quest_references := Quest_References {
		blocks       = registry,
		items        = items,
		machines     = machines,
		recipes      = recipes,
		technologies = technologies,
		strings      = global_string_table.entries,
	}
	quests, quests_loaded := load_quest_registry(data_directory, quest_references)
	if !quests_loaded {
		os.exit(1)
	}
	if problem := validate_starting_items(config.starting_items, items); problem != "" {
		fmt.eprintfln("error: invalid %s: %s", GAME_CONFIG_FILE_NAME, problem)
		os.exit(1)
	}
	recipe_names := recipe_display_names(recipes)
	content := Game_Content {
		blocks          = registry,
		items           = items,
		machines        = machines,
		fluids          = fluids,
		recipes         = recipes,
		technologies    = technologies,
		quests          = quests,
		item_sort_ranks = item_sort_ranks(items, item_display_names(items, context.temp_allocator)),
		recipe_names    = recipe_names,
		recipe_order    = recipe_name_order(recipe_names),
		unlock_all      = command_line.unlock_all || config.all_recipes_unlocked,
	}
	world, world_ok := choose_world(command_line)
	if !world_ok {
		os.exit(1)
	}
	if world.loading {
		config.veins_infinite = world.file.settings.veins_infinite
		config.day_length_seconds = world.file.settings.day_length_seconds
		content.unlock_all = world.file.settings.all_recipes_unlocked
	}
	generator, generator_loaded := load_generator(data_directory, registry, world.seed)
	if !generator_loaded {
		os.exit(1)
	}
	veins, problem := resolve_vein_content(generator.veins, items)
	if problem != "" {
		fmt.eprintfln("error: invalid %s: %s", VEINS_FILE_NAME, problem)
		os.exit(1)
	}
	content.veins = veins
	start := choose_world_start(&generator, command_line.debug_terrain)
	simulation, simulation_ok := make_game_simulation(config, content, start, world)
	if !simulation_ok {
		os.exit(1)
	}
	input_backend, input_started := start_input_backend(command_line.input_request)
	if !input_started {
		os.exit(1)
	}
	run_game(config, input_backend, content, generator, start, data_directory, simulation, world.save)
}

command_line_conflict :: proc(command_line: Command_Line) -> string {
	if command_line.load_name == "" {
		return ""
	}
	switch {
	case command_line.seed_given:
		return "--load and --seed cannot be combined (a saved world keeps its seed)"
	case command_line.world_name != "":
		return "--load and --name cannot be combined"
	case command_line.debug_terrain:
		return "--load and --debug-terrain cannot be combined"
	}
	return ""
}

// The world a run plays: a save to load (--load) or a new one, and where
// it saves.
Chosen_World :: struct {
	loading:   bool,
	seed:      u64,
	file:      World_File,
	directory: string,
	save:      Save_Setup,
}

// A new world saves under its name, or the name with a number when a save
// of that name exists. Without a saves directory, or on the debug terrain,
// it does not save.
choose_world :: proc(command_line: Command_Line) -> (world: Chosen_World, ok: bool) {
	saves_directory, saves_found := resolve_saves_directory()
	if command_line.load_name != "" {
		return choose_saved_world(command_line.load_name, saves_directory, saves_found)
	}
	world.seed = command_line.seed
	display_name := command_line.world_name != "" ? command_line.world_name : DEFAULT_WORLD_NAME
	switch {
	case command_line.debug_terrain:
		fmt.eprintln("world: saving is off for the debug terrain")
	case !saves_found:
		fmt.eprintfln("world: saving is off (set %s, XDG_DATA_HOME or HOME)", SAVES_DIRECTORY_ENVIRONMENT_VARIABLE)
	case:
		directory_name := unused_world_directory_name(saves_directory, sanitize_world_name(display_name, context.temp_allocator))
		world.save = Save_Setup{location = Save_Location{saves_directory = saves_directory, directory_name = directory_name, display_name = display_name}, enabled = true}
		fmt.eprintfln("world: new world %q, saves to %s", display_name, join_save_path(saves_directory, directory_name))
	}
	return world, true
}

choose_saved_world :: proc(name, saves_directory: string, saves_found: bool) -> (world: Chosen_World, ok: bool) {
	if !saves_found {
		fmt.eprintfln("error: no saves directory (set %s, XDG_DATA_HOME or HOME)", SAVES_DIRECTORY_ENVIRONMENT_VARIABLE)
		return {}, false
	}
	location := Save_Location{saves_directory = saves_directory, directory_name = sanitize_world_name(name)}
	directory, found := existing_save_directory(location)
	if !found {
		fmt.eprintfln("error: no saved world %q in %s", name, saves_directory)
		return {}, false
	}
	file, problem := read_world_file(directory)
	if problem != "" {
		fmt.eprintfln("error: cannot load %q: %s", name, problem)
		return {}, false
	}
	location.display_name = file.name
	world = Chosen_World{loading = true, seed = file.seed, file = file, directory = strings.clone(directory), save = Save_Setup{location = location, enabled = true}}
	return world, true
}

// A new world as make_simulation makes it, or a loaded save.
make_game_simulation :: proc(config: Game_Config, content: Game_Content, start: World_Start, world: Chosen_World) -> (simulation: Simulation_State, ok: bool) {
	simulation_content := game_simulation_content(content)
	if !world.loading {
		simulation = make_simulation(config, start.player, simulation_content, content.technologies, content.unlock_all, start.landing_pad)
		simulation.world.settings = World_Settings{seed = world.seed, veins_infinite = config.veins_infinite}
		return simulation, true
	}
	problem: string
	simulation, problem = make_simulation_from_save(config, start.player, simulation_content, start.landing_pad, world.directory, world.file)
	if problem != "" {
		fmt.eprintfln("error: cannot load %q: %s", world.file.name, problem)
		return simulation, false
	}
	fmt.eprintfln("world: loaded %q at tick %d from %s", world.file.name, world.file.tick, world.directory)
	return simulation, true
}

World_Start :: struct {
	debug_terrain: bool,
	player:        Player_Start,
	landing_pad:   Landing_Pad_Site,
}

// The debug terrain has no spawn search, so the player starts flying from
// the old fly camera start.
debug_terrain_player_start :: proc() -> Player_Start {
	camera := INITIAL_FLY_CAMERA
	return Player_Start{position = camera.position - {0, PLAYER_EYE_HEIGHT, 0}, yaw = camera.yaw, pitch = camera.pitch, flying = true}
}

// The debug terrain has no pad blocks; the capsule stands on the terrain
// near the origin.
debug_terrain_landing_pad :: proc() -> Landing_Pad_Site {
	capsule_column := CAPSULE_OFFSET.xz
	return Landing_Pad_Site{present = true, centre = {0, debug_terrain_height(capsule_column.x, capsule_column.y), 0}}
}

// Runs the spawn search before the window opens, so its result (or failure)
// shows on stderr even without a display. The landing pad goes where the
// player spawns; the generator stamps it, so it is set before streaming.
choose_world_start :: proc(generator: ^Generator, debug_terrain: bool) -> World_Start {
	if debug_terrain {
		fmt.eprintfln("world: debug terrain (seed %d unused)", generator.seed)
		return World_Start{debug_terrain = true, player = debug_terrain_player_start(), landing_pad = debug_terrain_landing_pad()}
	}
	spawn, found := find_spawn(generator)
	if found {
		fmt.eprintfln("world: seed %d, spawn at %d %d %d", generator.seed, spawn.x, spawn.y, spawn.z)
	} else {
		fmt.eprintfln("world: seed %d, no spawn meets the requirements, starting at the origin", generator.seed)
		spawn = {0, terrain_height(generator.seeds, 0, 0), 0}
	}
	generator.landing_pad = Landing_Pad_Site{present = true, centre = spawn}
	return World_Start{player = player_start_on(spawn), landing_pad = generator.landing_pad}
}
