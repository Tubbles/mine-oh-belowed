package game

import "core:flags"
import "core:fmt"
import "core:io"
import "core:os"

GAME_VERSION :: "0.0.0"
// From build.sh or the flake through -define: the short commit ("+dirty"
// with uncommitted changes) and the UTC build time in one string, since a
// define holding only digits (a date, or an unlucky hash) would arrive as
// a number. The stamp is what the title screen, the pause menu, the log
// header and --version show, so a bug report can name the build.
BUILD_INFO :: #config(BUILD_INFO, "unknown build")
BUILD_STAMP :: GAME_VERSION + " " + BUILD_INFO

// The name the usage page shows, whatever the binary is called.
PROGRAM_NAME :: "mine-oh-belowed"
// The subcommand that prints the configuration files and effective values.
CONFIG_SUBCOMMAND :: "config"

Input_Backend_Request :: enum u8 {
	Automatic,
	Sdl3,
	Raylib,
}

// Every field is a flag. core:flags turns underscores into dashes; the name
// subtag keeps the documented spelling where the field name differs. The seed
// and the input backend stay strings so the game, not strconv or the enum
// names, decides what is valid.
Command_Line :: struct {
	subcommand:      string `args:"pos=0" usage:"config: print the configuration files found and the effective values, then exit"`,
	show_version:    bool `args:"name=version" usage:"print the version and exit"`,
	set_assignments: [dynamic]string `args:"name=set" usage:"<key>=<value>, the last configuration layer, repeatable (--set=settings.ui_scale=1.25)"`,
	input:           string `usage:"input backend: sdl3 or raylib (default: SDL3 with raylib fallback)"`,
	seed:            string `usage:"seed of a new world, an unsigned 64 bit decimal"`,
	load_name:       string `args:"name=load" usage:"load the saved world with this name"`,
	world_name:      string `args:"name=name" usage:"name of a new world"`,
	debug_terrain:   bool `usage:"the fixed 8 by 2 by 8 chunk test terrain instead of the generated world"`,
	// Developer flags (work item 0043).
	unlock_all:      bool `usage:"every technology researched and every item discovered"`,
	developer_mode:  bool `args:"name=dev" usage:"developer mode: a Developer entry in the pause menu"`,
	chapter:         int `usage:"start a new world at chapter n: the earlier chapters' quests completed with their rewards, and chapter n's kit from data/dev_kits.sjson"`,
	give_arguments:  [dynamic]string `args:"name=give" usage:"<item>:<count>, items into the inventory on the first tick (the rest into the drop capsule), repeatable (--give=iron_plate:50)"`,
	// Work item 0054, overrides the watch_data setting for this run.
	watch_data:      string `usage:"reload changed data files while the game runs: off, presentation or all (default: the watch_data setting)"`,
}

// Unix style keeps the documented spellings: --seed=42, --set=<key>=<value>.
parse_command_line :: proc(arguments: []string) -> (command_line: Command_Line, error: flags.Error) {
	error = flags.parse(&command_line, arguments, .Unix)
	return
}

write_command_line_usage :: proc(writer: io.Writer) {
	flags.write_usage(writer, Command_Line, PROGRAM_NAME, .Unix)
}

flags_error_message :: proc(error: flags.Error) -> string {
	#partial switch specific_error in error {
	case flags.Parse_Error:
		return specific_error.message
	case flags.Validation_Error:
		return specific_error.message
	}
	return fmt.tprint(error)
}

parse_input_request :: proc(value: string) -> (request: Input_Backend_Request, ok: bool) {
	switch value {
	case "":
		return .Automatic, true
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

command_line_seed :: proc(command_line: Command_Line) -> (seed: u64, ok: bool) {
	if command_line.seed == "" {
		return DEFAULT_WORLD_SEED, true
	}
	return parse_seed(command_line.seed)
}

// The values core:flags accepts as plain strings but the game does not.
command_line_value_problem :: proc(command_line: Command_Line) -> string {
	if _, ok := command_line_seed(command_line); !ok {
		return fmt.tprintf("invalid seed %q (expected an unsigned 64 bit integer, for example --seed=12345)", command_line.seed)
	}
	if _, ok := parse_input_request(command_line.input); !ok {
		return fmt.tprintf("unknown input backend %q (supported: --input=sdl3, --input=raylib)", command_line.input)
	}
	if command_line.subcommand != "" && command_line.subcommand != CONFIG_SUBCOMMAND {
		return fmt.tprintf("unknown command %q (supported: %s)", command_line.subcommand, CONFIG_SUBCOMMAND)
	}
	if _, ok := parse_watch_data_mode(command_line.watch_data); !ok {
		return fmt.tprintf("invalid --watch-data=%s (expected off, presentation or all)", command_line.watch_data)
	}
	if command_line.chapter < 0 {
		return fmt.tprintf("invalid --chapter=%d (expected a chapter from 1)", command_line.chapter)
	}
	return give_arguments_problem(command_line.give_arguments[:])
}

// The developer flags checked against the loaded data: --chapter needs a
// kit, --give known items. The grants are in the temp allocator.
command_line_data_problem :: proc(command_line: Command_Line, items: Item_Registry, kits: Developer_Kits) -> (grants: []Developer_Grant, problem: string) {
	if command_line.chapter > len(kits.kits) {
		return nil, fmt.tprintf("invalid --chapter=%d (%s has kits for chapters 1 to %d)", command_line.chapter, DEVELOPER_KITS_FILE_NAME, len(kits.kits))
	}
	return resolve_give_arguments(command_line.give_arguments[:], items)
}

// --chapter first, so its rewards come before the --give items.
command_line_developer_requests :: proc(requests: ^[dynamic]Developer_Request, chapter: int, grants: []Developer_Grant) {
	if chapter > 0 {
		chapter_requests(requests, chapter)
	}
	give_requests(requests, grants)
}


// Prints which backend is active and why. Fails only when SDL3 was asked for
// explicitly, so that a broken SDL setup cannot hide behind the fallback.
start_input_backend :: proc(request: Input_Backend_Request) -> (backend: Input_Backend, ok: bool) {
	if request == .Raylib {
		log_printf("input: raylib backend (requested with --input=raylib)")
		return .Raylib, true
	}
	sdl3_ready, error_message := init_sdl3_input()
	switch {
	case sdl3_ready:
		log_printf("input: sdl3 backend (%s)", request == .Sdl3 ? "requested with --input=sdl3" : "default")
		return .Sdl3, true
	case request == .Sdl3:
		log_printf("error: --input=sdl3 but SDL failed to initialise: %s", error_message)
		return .Raylib, false
	}
	log_printf("input: raylib backend (SDL3 failed to initialise: %s)", error_message)
	return .Raylib, true
}

main :: proc() {
	command_line, parse_error := parse_command_line(os.args[1:])
	if _, is_help := parse_error.(flags.Help_Request); is_help {
		write_command_line_usage(os.to_stream(os.stdout))
		return
	}
	if parse_error != nil {
		log_printf("error: %s (see --help)", flags_error_message(parse_error))
		os.exit(2)
	}
	if problem := command_line_value_problem(command_line); problem != "" {
		log_printf("error: %s", problem)
		os.exit(2)
	}
	if command_line.show_version {
		fmt.printfln("Mine oh Belowed %s", BUILD_STAMP)
		return
	}
	if problem := command_line_conflict(command_line); problem != "" {
		log_printf("error: %s", problem)
		os.exit(2)
	}
	if command_line.subcommand == CONFIG_SUBCOMMAND {
		print_configuration(command_line.set_assignments[:])
		return
	}
	open_log_file()
	defer close_log_file()
	// Crash traces into the log (logging.odin).
	context.assertion_failure_proc = log_assertion_failure
	install_crash_handlers()
	environment := read_configuration_environment()
	loaded_configuration, configuration_problem := load_configuration(environment, command_line.set_assignments[:])
	if configuration_problem != "" {
		log_printf("error: %s", configuration_problem)
		os.exit(1)
	}
	data_directory := require_data_directory()
	fonts, fonts_problem := load_checked_fonts(data_directory, loaded_configuration)
	if fonts_problem != "" {
		log_printf("error: %s", fonts_problem)
		os.exit(1)
	}
	binding_overrides, overrides_problem := resolve_bindings(loaded_configuration.configuration.bindings, loaded_configuration.provenance)
	if overrides_problem != "" {
		log_printf("error: %s", overrides_problem)
		os.exit(1)
	}
	bindings, bindings_problem := load_bindings(data_directory, binding_overrides)
	if bindings_problem != "" {
		log_printf("error: %s", bindings_problem)
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
	game_data, data_problem := load_game_data(data_directory, config, global_string_table.entries)
	if data_problem != "" {
		os.exit(1)
	}
	game_data.content.unlock_all = command_line.unlock_all
	game_data.content.developer_mode = command_line.developer_mode
	content := game_data.content
	developer_grants, developer_problem := command_line_data_problem(command_line, content.items, content.developer_kits)
	if developer_problem != "" {
		log_printf("error: %s", developer_problem)
		os.exit(2)
	}
	saves_directory, saves_found := resolve_saves_directory(loaded_configuration.configuration.paths.saves)
	session := start_command_line_session(command_line, config, content, game_data.base_generator, saves_directory, saves_found)
	if session != nil {
		command_line_developer_requests(&session.simulation.developer_requests, command_line.chapter, developer_grants)
	}
	input_request, _ := parse_input_request(command_line.input)
	input_backend, input_started := start_input_backend(input_request)
	if !input_started {
		os.exit(1)
	}
	watch_data, _ := parse_watch_data_mode(command_line.watch_data)
	player_configuration := Player_Configuration {
		environment       = environment,
		settings          = loaded_configuration.configuration.settings,
		bindings          = bindings,
		binding_overrides = binding_overrides,
		// Before the window opens, so the report shows without a display.
		input_bindings    = make_backend_bindings(bindings, input_backend),
		watch_data        = watch_data,
	}
	run_game(config, input_backend, game_data, data_directory, fonts, session, make_title_state(config, saves_directory, saves_found, make_save_header()), player_configuration)
}

// data/fonts/fonts.sjson, and the font settings checked against it.
load_checked_fonts :: proc(data_directory: string, loaded: Loaded_Configuration) -> (fonts: Loaded_Fonts, problem: string) {
	if fonts, problem = load_fonts(data_directory); problem != "" {
		return {}, problem
	}
	if problem = font_settings_problem(loaded.configuration.settings, fonts.families, loaded.provenance); problem != "" {
		destroy_arena(fonts.arena)
		return {}, problem
	}
	return fonts, ""
}

// Builds the backend's tables and reports once what it cannot express.
make_backend_bindings :: proc(bindings: []Binding, backend: Input_Backend) -> Input_Bindings {
	tables, unsupported := build_input_bindings(bindings, backend, context.temp_allocator)
	if len(unsupported) > 0 {
		log_printf("%s", unsupported_bindings_report(unsupported, backend))
	}
	return tables
}

require_data_directory :: proc() -> string {
	data_directory, found := resolve_data_directory()
	if !found {
		log_printf(
			"error: no data directory found. Set %s, run from the repository root (./%s), or install to <executable directory>/%s",
			DATA_DIRECTORY_ENVIRONMENT_VARIABLE,
			WORKING_DIRECTORY_DATA,
			INSTALLED_DATA_RELATIVE_TO_EXECUTABLE,
		)
		os.exit(1)
	}
	return data_directory
}

// The defaults from data/bindings.sjson with the configuration's overrides
// (resolve_bindings), also when data/bindings.sjson changes while the game
// runs (hot_reload.odin).
load_bindings :: proc(data_directory: string, overrides: []Binding, allocator := context.allocator) -> (bindings: []Binding, problem: string) {
	defaults: []Binding
	defaults, problem = load_default_bindings(data_directory, allocator)
	if problem != "" {
		return nil, problem
	}
	return effective_bindings(defaults, overrides, allocator), ""
}

// The config subcommand: no window, no log, exit 1 on a configuration error.
print_configuration :: proc(assignments: []string) {
	loaded, problem := load_configuration(read_configuration_environment(), assignments)
	if problem != "" {
		log_printf("error: %s", problem)
		os.exit(1)
	}
	overrides, bindings: []Binding
	fonts: Loaded_Fonts
	data_directory := require_data_directory()
	fonts, problem = load_checked_fonts(data_directory, loaded)
	defer destroy_arena(fonts.arena)
	if problem == "" {
		overrides, problem = resolve_bindings(loaded.configuration.bindings, loaded.provenance)
	}
	if problem == "" {
		bindings, problem = load_bindings(data_directory, overrides)
	}
	if problem != "" {
		log_printf("error: %s", problem)
		os.exit(1)
	}
	fmt.print(configuration_dump(loaded, bindings))
}

// --seed, --name, --load, --debug-terrain, --chapter and --give start a
// world directly; without them the title shows.
command_line_starts_world :: proc(command_line: Command_Line) -> bool {
	starts := command_line.seed != "" || command_line.world_name != "" || command_line.load_name != "" || command_line.debug_terrain
	return starts || command_line.chapter > 0 || len(command_line.give_arguments) > 0
}

// Runs before the window opens, so the spawn search and load problems show
// on stderr even without a display. Nil when the title should show.
start_command_line_session :: proc(command_line: Command_Line, config: Game_Config, content: Game_Content, base_generator: Generator, saves_directory: string, saves_found: bool) -> ^Session {
	if !command_line_starts_world(command_line) {
		return nil
	}
	plan, problem := command_line_plan(command_line, config, saves_directory, saves_found)
	if problem != "" {
		log_printf("error: %s", problem)
		os.exit(1)
	}
	session: ^Session
	session, problem = start_session(plan, config, content, base_generator)
	if problem != "" {
		log_printf("error: cannot start the world: %s", problem)
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
	// Validated before any data loads.
	seed, _ := command_line_seed(command_line)
	return new_world_plan(display_name, seed, settings, saves_directory, saves_found, command_line.debug_terrain), ""
}

command_line_conflict :: proc(command_line: Command_Line) -> string {
	if command_line.load_name == "" {
		return ""
	}
	switch {
	case command_line.seed != "":
		return "--load and --seed cannot be combined (a saved world keeps its seed)"
	case command_line.world_name != "":
		return "--load and --name cannot be combined"
	case command_line.debug_terrain:
		return "--load and --debug-terrain cannot be combined"
	case command_line.chapter > 0:
		return "--load and --chapter cannot be combined (--chapter starts a new world)"
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

// A loaded world keeps the pad it was created with (world.sjson, 0049), so
// a change to the spawn rules never moves it. A file without a pad (saved
// before 0049) falls back to the search.
saved_world_start :: proc(generator: ^Generator, loading: bool, file: World_File) -> (start: World_Start, found: bool) {
	if !loading || !file.landing_pad_present {
		return {}, false
	}
	centre := World_Coordinate(file.landing_pad)
	generator.landing_pad = Landing_Pad_Site{present = true, centre = centre}
	return World_Start{player = player_start_on(centre), landing_pad = generator.landing_pad}, true
}

// Runs the spawn search before the window opens, so its result (or failure)
// shows on stderr even without a display. The landing pad goes where the
// player spawns; the generator stamps it, so it is set before streaming.
choose_world_start :: proc(generator: ^Generator, debug_terrain: bool) -> World_Start {
	if debug_terrain {
		log_printf("world: debug terrain (seed %d unused)", generator.seed)
		return World_Start{debug_terrain = true, player = debug_terrain_player_start(), landing_pad = debug_terrain_landing_pad()}
	}
	spawn, found := find_spawn(generator)
	if found {
		log_printf("world: seed %d, spawn at %d %d %d", generator.seed, spawn.x, spawn.y, spawn.z)
	} else {
		log_printf("world: seed %d, no spawn meets the requirements, starting at the origin", generator.seed)
		spawn = {0, terrain_height(generator.seeds, 0, 0), 0}
	}
	generator.landing_pad = Landing_Pad_Site{present = true, centre = spawn}
	return World_Start{player = player_start_on(spawn), landing_pad = generator.landing_pad}
}
