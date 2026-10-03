package game

import "core:flags"
import "core:fmt"
import "core:io"
import "core:mem/virtual"
import "core:os"
import "platform"

GAME_VERSION :: "0.0.0"
// The highest TCP port --port takes.
MAXIMUM_PORT :: 65_535
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
	// Work item 0115, forces the touch_overlay setting on for this run.
	touch_overlay:   bool `usage:"the touch overlay on for this run; on the desktop the mouse is its touch while the left button is held"`,
	// Work item 0050: no window, no controller, the table on stdout.
	benchmark:       int `usage:"run the headless factory benchmark of this size for ten simulated minutes and print the table"`,
	// Work item 0169: the terrain field before the session plays it (0179).
	planet_preview:  bool `usage:"fly over the home planet's terrain field (seed from --seed), drawn with the level of detail; no game"`,
	planet_preview_screenshot: string `usage:"<path>: the planet preview from a fixed camera without input, the frame saved to the path once the field has streamed (120 frames at least), then exit"`,
	planet_preview_walk: bool `usage:"start the planet preview (or its screenshot) in the walk mode, the field player standing on the ground (G switches in the preview)"`,
	planet_preview_daylight: int `usage:"<percent>: the planet preview's daylight, the sky light's share from 0 (night: only torches light) to 100 (the default)"`,
	// Work item 0176: a level shot shows the pads, the arms and the run.
	planet_preview_pitch: int `usage:"<degrees>: the walk screenshot's camera tilt once the pit is dug, from -89 to 89 (default -50, down into the pit)"`,
	// Work item 0207: the model workbench.
	model_check:     string `usage:"<machine|all>: check the machine's model (all: every OBJ model and the arm) in the game's mesher and motion, one line per problem, exit 1 on any; no window"`,
	model_preview:   string `usage:"<machine>[,<machine>]: render each machine's model from five cameras at rest and at three phases into --model-preview-directory, then exit"`,
	model_preview_directory: string `usage:"<path>: where --model-preview writes <machine>_<camera>_<phase>.png"`,
	// Work item 0177: lockstep multiplayer.
	server:          bool `usage:"run the world (--load, or a new one) without a window or a local player and host it for --join (doc/commands.md)"`,
	port:            int `usage:"the one port --server listens on (default: the first free of 47317 to 47326)"`,
	join_address:    string `args:"name=join" usage:"join the session a --server hosts at <address>[:port] (an IP address on the phone)"`,
}

// Unix style keeps the documented spellings: --seed=42, --set=<key>=<value>.
parse_command_line :: proc(arguments: []string) -> (command_line: Command_Line, error: flags.Error) {
	command_line.planet_preview_daylight = 100
	command_line.planet_preview_pitch = PLANET_PREVIEW_PIT_PITCH_DEGREES
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
	if command_line.benchmark < 0 || command_line.benchmark > BENCHMARK_LARGEST_SIZE {
		return fmt.tprintf("invalid --benchmark=%d (expected a size from 1 to %d)", command_line.benchmark, BENCHMARK_LARGEST_SIZE)
	}
	if problem := benchmark_size_problem(command_line.benchmark); problem != "" {
		return fmt.tprintf("--benchmark=%d: %s", command_line.benchmark, problem)
	}
	if command_line.port < 0 || command_line.port > MAXIMUM_PORT {
		return fmt.tprintf("invalid --port=%d (expected a port from 1 to %d)", command_line.port, MAXIMUM_PORT)
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
	reset_raylib_pointer_position()
	reset_raylib_typed_text()
	if request == .Raylib {
		platform.log_printf("input: raylib backend (requested with --input=raylib)")
		return .Raylib, true
	}
	sdl3_ready, error_message := init_sdl3_input()
	switch {
	case sdl3_ready:
		platform.log_printf("input: sdl3 backend (%s)", request == .Sdl3 ? "requested with --input=sdl3" : "default")
		return .Sdl3, true
	case request == .Sdl3:
		platform.log_printf("error: --input=sdl3 but SDL failed to initialise: %s", error_message)
		return .Raylib, false
	}
	platform.log_printf("input: raylib backend (SDL3 failed to initialise: %s)", error_message)
	return .Raylib, true
}

main :: proc() {
	command_line, parse_error := parse_command_line(os.args[1:])
	if _, is_help := parse_error.(flags.Help_Request); is_help {
		write_command_line_usage(os.to_stream(os.stdout))
		return
	}
	if parse_error != nil {
		platform.log_printf("error: %s (see --help)", flags_error_message(parse_error))
		os.exit(2)
	}
	if problem := command_line_value_problem(command_line); problem != "" {
		platform.log_printf("error: %s", problem)
		os.exit(2)
	}
	if command_line.show_version {
		fmt.printfln("Mine oh Belowed %s", BUILD_STAMP)
		return
	}
	if problem := command_line_conflict(command_line); problem != "" {
		platform.log_printf("error: %s", problem)
		os.exit(2)
	}
	if command_line.subcommand == CONFIG_SUBCOMMAND {
		print_configuration(command_line.set_assignments[:])
		return
	}
	platform.open_log_file(BUILD_STAMP)
	defer platform.close_log_file()
	// Crash traces into the log (logging.odin).
	context.assertion_failure_proc = platform.log_assertion_failure
	platform.install_crash_handlers()
	environment := read_configuration_environment()
	loaded_configuration, configuration_problem, settings_problem := load_configuration_at_start(environment, command_line.set_assignments[:])
	if configuration_problem != "" {
		platform.log_printf("error: %s", configuration_problem)
		os.exit(1)
	}
	apply_deck_preset_at_start(environment, &loaded_configuration)
	data_directory := require_data_directory()
	binding_overrides, overrides_problem := resolve_bindings(loaded_configuration.configuration.bindings, loaded_configuration.provenance)
	if overrides_problem != "" {
		platform.log_printf("error: %s", overrides_problem)
		os.exit(1)
	}
	start, start_problem := load_start_data(data_directory, loaded_configuration, binding_overrides)
	if start_problem != "" && turn_data_edits_off(start_problem) {
		start, start_problem = load_start_data(data_directory, loaded_configuration, binding_overrides)
	}
	if start_problem != "" {
		os.exit(1)
	}
	if start.fonts_fell_back {
		loaded_configuration.configuration.settings = settings_with_default_fonts(loaded_configuration.configuration.settings)
	}
	fonts, bindings, config, game_data := start.fonts, start.bindings, start.config, start.game_data
	global_string_table = start.string_table
	game_data.content.unlock_all = command_line.unlock_all
	game_data.content.developer_mode = command_line.developer_mode
	content := game_data.content
	developer_grants, developer_problem := command_line_data_problem(command_line, content.items, content.developer_kits)
	if developer_problem != "" {
		platform.log_printf("error: %s", developer_problem)
		os.exit(2)
	}
	if command_line.model_check != "" {
		os.exit(run_model_check(command_line.model_check, content.machines, config.foundation_pitch_millimetres, data_directory))
	}
	if command_line.model_preview != "" {
		os.exit(run_model_preview(command_line.model_preview, command_line.model_preview_directory, content.machines, config.foundation_pitch_millimetres, data_directory))
	}
	if command_line.benchmark > 0 {
		os.exit(run_command_line_benchmark(command_line.benchmark, data_directory, config, game_data))
	}
	if command_line.planet_preview || command_line.planet_preview_screenshot != "" || command_line.planet_preview_walk {
		seed, _ := command_line_seed(command_line)
		os.exit(run_planet_preview(config, content, game_data.base_generator, bindings, data_directory, seed, command_line.planet_preview_screenshot, command_line.planet_preview_walk, command_line.planet_preview_daylight, command_line.planet_preview_pitch))
	}
	saves_directory, saves_found := resolve_saves_directory(loaded_configuration.configuration.paths.saves)
	if command_line.server {
		os.exit(run_command_line_server(command_line, config, content, game_data.base_generator, saves_directory, saves_found, loaded_configuration.configuration.settings.autosave_minutes))
	}
	session := start_command_line_session(command_line, config, content, game_data.base_generator, saves_directory, saves_found)
	if session != nil {
		requests := make([dynamic]Developer_Request, context.temp_allocator)
		command_line_developer_requests(&requests, command_line.chapter, developer_grants)
		for request in requests {
			queue_player_command(&session.simulation.player_commands, 0, request)
		}
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
		touch_overlay_forced = command_line.touch_overlay,
		settings_set_aside = settings_problem != "",
		fonts_fell_back = start.fonts_fell_back,
		join_address = command_line.join_address,
	}
	run_game(config, input_backend, game_data, data_directory, fonts, session, make_title_state(config, saves_directory, saves_found, make_save_header()), player_configuration)
}

// The data main loads before the window: the fonts, the bindings, the
// game config, the strings and the game data. The config and the bindings
// live in arena, for the run.
Start_Data :: struct {
	arena:        ^virtual.Arena,
	fonts:        Loaded_Fonts,
	bindings:     []Binding,
	config:       Game_Config,
	string_table: String_Table,
	game_data:    Game_Data,
	// A font setting the fonts file does not offer was replaced by the
	// default (load_start_fonts): main applies settings_with_default_fonts.
	fonts_fell_back: bool,
}

// Loads the start data, each problem logged. On a problem nothing stays
// loaded and the problem (the failing loader's error line, which names
// the file read, the overlay's copy when that was taken) is returned, so
// main can load again without the data edits overlay
// (turn_data_edits_off).
load_start_data :: proc(data_directory: string, loaded: Loaded_Configuration, binding_overrides: []Binding) -> (start: Start_Data, problem: string) {
	start.arena = new_growing_arena()
	if start.arena == nil {
		return {}, "cannot reserve memory for the start data"
	}
	problem = load_start_data_into(&start, data_directory, loaded, binding_overrides)
	if problem != "" {
		destroy_start_data(&start)
	}
	return start, problem
}

// In order, stopping at the first problem. The game data's names read
// the strings just loaded (text, through thread_string_table).
load_start_data_into :: proc(start: ^Start_Data, data_directory: string, loaded: Loaded_Configuration, binding_overrides: []Binding) -> (problem: string) {
	allocator := virtual.arena_allocator(start.arena)
	if start.fonts, problem, start.fonts_fell_back = load_start_fonts(data_directory, loaded); problem != "" {
		platform.log_printf("error: %s", problem)
		return problem
	}
	if start.bindings, problem = load_bindings(data_directory, binding_overrides, allocator); problem != "" {
		platform.log_printf("error: %s", problem)
		return problem
	}
	capture: platform.Log_Capture
	platform.begin_log_capture(&capture)
	config_loaded, strings_loaded: bool
	start.config, config_loaded = load_game_config(data_directory, allocator)
	if config_loaded {
		start.string_table, strings_loaded = load_string_table(data_directory)
	}
	problem = platform.end_log_capture(&capture, "")
	if !config_loaded || !strings_loaded {
		return problem != "" ? problem : "the game config or the strings did not load"
	}
	previous_table := thread_string_table
	thread_string_table = &start.string_table
	defer thread_string_table = previous_table
	start.game_data, problem = load_game_data(data_directory, start.config, start.string_table.entries)
	return problem
}

destroy_start_data :: proc(start: ^Start_Data) {
	destroy_game_data(&start.game_data)
	destroy_string_table(&start.string_table)
	destroy_arena(start.fonts.arena)
	destroy_arena(start.arena)
	start^ = {}
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

// load_checked_fonts for the start (work item 0149): a font setting the
// fonts file does not offer (a family a later build dropped, one only the
// data edits had) is logged and replaced by the default instead of
// stopping the start; fell_back tells main to do the same to the
// settings.
load_start_fonts :: proc(data_directory: string, loaded: Loaded_Configuration) -> (fonts: Loaded_Fonts, problem: string, fell_back: bool) {
	if fonts, problem = load_fonts(data_directory); problem != "" {
		return {}, problem, false
	}
	font_problem := font_settings_problem(loaded.configuration.settings, fonts.families, loaded.provenance)
	if font_problem == "" {
		return fonts, "", false
	}
	platform.log_printf("configuration: %s; the default font is used", font_problem)
	if problem = font_settings_problem(settings_with_default_fonts(loaded.configuration.settings), fonts.families, loaded.provenance); problem != "" {
		destroy_arena(fonts.arena)
		return {}, problem, false
	}
	return fonts, "", true
}

// The settings with DEFAULT_SETTINGS's font families.
settings_with_default_fonts :: proc(settings: Settings) -> Settings {
	settings := settings
	settings.font = DEFAULT_SETTINGS.font
	settings.monospace_font = DEFAULT_SETTINGS.monospace_font
	return settings
}

// Builds the backend's tables and reports once what it cannot express.
make_backend_bindings :: proc(bindings: []Binding, backend: Input_Backend) -> Input_Bindings {
	tables, unsupported := build_input_bindings(bindings, backend, context.temp_allocator)
	if len(unsupported) > 0 {
		platform.log_printf("%s", unsupported_bindings_report(unsupported, backend))
	}
	return tables
}

require_data_directory :: proc() -> string {
	data_directory, found := resolve_data_directory()
	if !found && ODIN_PLATFORM_SUBTARGET == .Android {
		platform.log_printf("error: no data directory: the copy from the app failed (see above)")
		os.exit(1)
	}
	if !found {
		platform.log_printf(
			"error: no data directory found. Set %s, run from the repository root (./%s), put %s beside the executable, or install to <executable directory>/%s",
			DATA_DIRECTORY_ENVIRONMENT_VARIABLE,
			WORKING_DIRECTORY_DATA,
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
		platform.log_printf("error: %s", problem)
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
		platform.log_printf("error: %s", problem)
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
		platform.log_printf("error: %s", problem)
		os.exit(1)
	}
	session: ^Session
	session, problem = start_session(plan, config, content, base_generator)
	if problem != "" {
		platform.log_printf("error: cannot start the world: %s", problem)
		os.exit(1)
	}
	if !plan.loading && session.save.enabled {
		save_session(session, content)
	}
	return session
}

// --server: the world of the command line (a new one by default), hosted
// without a window until the process is stopped (session_server.odin).
run_command_line_server :: proc(command_line: Command_Line, config: Game_Config, content: Game_Content, base_generator: Generator, saves_directory: string, saves_found: bool, autosave_minutes: int) -> int {
	plan, problem := command_line_plan(command_line, config, saves_directory, saves_found)
	if problem != "" {
		platform.log_printf("error: %s", problem)
		return 1
	}
	session: ^Session
	if session, problem = start_session(plan, config, content, base_generator); problem != "" {
		platform.log_printf("error: cannot start the world: %s", problem)
		return 1
	}
	defer end_session(session)
	if !plan.loading && session.save.enabled {
		save_session(session, content)
	}
	server: Server_State
	if problem = start_server(&server, session, content, autosave_minutes, server_hosting_plan(command_line.port)); problem != "" {
		platform.log_printf("error: %s", problem)
		return 1
	}
	return run_server(&server)
}

command_line_plan :: proc(command_line: Command_Line, config: Game_Config, saves_directory: string, saves_found: bool) -> (plan: Session_Plan, problem: string) {
	if command_line.load_name != "" {
		if !saves_found {
			return {}, fmt.tprintf("no saves directory (set %s, %s)", SAVES_DIRECTORY_ENVIRONMENT_VARIABLE, platform.DATA_HOME_VARIABLES)
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
	if problem := workbench_conflict(command_line); problem != "" {
		return problem
	}
	if command_line.benchmark > 0 {
		return benchmark_conflict(command_line)
	}
	if problem := network_conflict(command_line); problem != "" {
		return problem
	}
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

// A joining machine gets the host's world; the server hosts the world it
// starts, and only it listens on a port.
network_conflict :: proc(command_line: Command_Line) -> string {
	switch {
	case command_line.server && command_line.join_address != "":
		return "--server and --join cannot be combined (a server hosts, a client joins)"
	case command_line.join_address != "" && command_line_starts_world(command_line):
		return "--join cannot be combined with the flags that start a world (the host's world is joined)"
	case command_line.port != 0 && !command_line.server:
		return "--port needs --server"
	case command_line.server && command_line.debug_terrain:
		return "--server and --debug-terrain cannot be combined"
	case command_line.server && (command_line.chapter > 0 || len(command_line.give_arguments) > 0):
		// Their requests are queued for the local player, which a server
		// does not have.
		return "--server cannot be combined with --chapter or --give"
	}
	return ""
}

// The workbench (0207) runs no world: a check or a preview alone, the
// preview with its directory.
workbench_conflict :: proc(command_line: Command_Line) -> string {
	checking, previewing := command_line.model_check != "", command_line.model_preview != ""
	switch {
	case checking && previewing:
		return "--model-check and --model-preview cannot be combined"
	case previewing && command_line.model_preview_directory == "":
		return "--model-preview needs --model-preview-directory"
	case !previewing && command_line.model_preview_directory != "":
		return "--model-preview-directory needs --model-preview"
	case !checking && !previewing:
		return ""
	}
	planet_preview := command_line.planet_preview || command_line.planet_preview_screenshot != "" || command_line.planet_preview_walk
	planet_preview ||= command_line.planet_preview_daylight != 100 || command_line.planet_preview_pitch != PLANET_PREVIEW_PIT_PITCH_DEGREES
	world := command_line.benchmark > 0 || command_line.server || command_line.join_address != "" || command_line_starts_world(command_line)
	if planet_preview || world {
		return fmt.tprintf("%s runs no world, so it cannot be combined with --benchmark, --planet-preview, --server, --join or a world's flags", checking ? "--model-check" : "--model-preview")
	}
	return ""
}

// The benchmark builds its own world.
benchmark_conflict :: proc(command_line: Command_Line) -> string {
	switch {
	case command_line.load_name != "":
		return "--benchmark and --load cannot be combined (the benchmark builds its own world)"
	case command_line.seed != "":
		return "--benchmark and --seed cannot be combined (the benchmark builds its own world)"
	case command_line.world_name != "":
		return "--benchmark and --name cannot be combined"
	case command_line.chapter > 0:
		return "--benchmark and --chapter cannot be combined"
	case command_line.debug_terrain:
		return "--benchmark and --debug-terrain cannot be combined"
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
// a change to the spawn rules never moves it. A file without a pad (an
// older save) falls back to the search.
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
		platform.log_printf("world: debug terrain (seed %d unused)", generator.seed)
		return World_Start{debug_terrain = true, player = debug_terrain_player_start(), landing_pad = debug_terrain_landing_pad()}
	}
	spawn, found := find_spawn(generator)
	if found {
		platform.log_printf("world: seed %d, spawn at %d %d %d", generator.seed, spawn.x, spawn.y, spawn.z)
	} else {
		platform.log_printf("world: seed %d, no spawn meets the requirements, starting at the origin", generator.seed)
		spawn = {0, terrain_height(generator.seeds, 0, 0), 0}
	}
	generator.landing_pad = Landing_Pad_Site{present = true, centre = spawn}
	return World_Start{player = player_start_on(spawn), landing_pad = generator.landing_pad}
}
