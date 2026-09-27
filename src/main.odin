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
		unlock_all      = command_line.unlock_all,
	}
	// Every world copies the generator data; only the seed differs.
	base_generator, generator_loaded := load_generator(data_directory, registry, DEFAULT_WORLD_SEED)
	if !generator_loaded {
		os.exit(1)
	}
	veins, problem := resolve_vein_content(base_generator.veins, items)
	if problem != "" {
		fmt.eprintfln("error: invalid %s: %s", VEINS_FILE_NAME, problem)
		os.exit(1)
	}
	content.veins = veins
	saves_directory, saves_found := resolve_saves_directory()
	session := start_command_line_session(command_line, config, content, base_generator, saves_directory, saves_found)
	input_backend, input_started := start_input_backend(command_line.input_request)
	if !input_started {
		os.exit(1)
	}
	run_game(config, input_backend, content, base_generator, data_directory, session, make_title_state(config, saves_directory, saves_found))
}

// --seed, --name, --load and --debug-terrain start a world directly;
// without them the title shows.
command_line_starts_world :: proc(command_line: Command_Line) -> bool {
	return command_line.seed_given || command_line.world_name != "" || command_line.load_name != "" || command_line.debug_terrain
}

// Runs before the window opens, so the spawn search and load problems show
// on stderr even without a display. Nil when the title should show.
start_command_line_session :: proc(command_line: Command_Line, config: Game_Config, content: Game_Content, base_generator: Generator, saves_directory: string, saves_found: bool) -> ^Session {
	if !command_line_starts_world(command_line) {
		return nil
	}
	plan, problem := command_line_plan(command_line, config, saves_directory, saves_found)
	if problem != "" {
		fmt.eprintfln("error: %s", problem)
		os.exit(1)
	}
	session: ^Session
	session, problem = start_session(plan, config, content, base_generator)
	if problem != "" {
		fmt.eprintfln("error: cannot start the world: %s", problem)
		os.exit(1)
	}
	if !plan.loading && session.save.enabled {
		save_session(session, content)
	}
	return session
}

command_line_plan :: proc(command_line: Command_Line, config: Game_Config, saves_directory: string, saves_found: bool) -> (plan: Session_Plan, problem: string) {
	if command_line.load_name != "" {
		if !saves_found {
			return {}, fmt.tprintf("no saves directory (set %s, XDG_DATA_HOME or HOME)", SAVES_DIRECTORY_ENVIRONMENT_VARIABLE)
		}
		return saved_world_plan(saves_directory, sanitize_world_name(command_line.load_name, context.temp_allocator))
	}
	display_name := command_line.world_name != "" ? command_line.world_name : DEFAULT_WORLD_NAME
	settings := default_world_file_settings(config)
	return new_world_plan(display_name, command_line.seed, settings, saves_directory, saves_found, command_line.debug_terrain), ""
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
