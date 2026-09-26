package game

import "core:fmt"
import "core:os"
import "core:strings"

GAME_VERSION :: "0.0.0"

INPUT_ARGUMENT_PREFIX :: "--input="
SEED_ARGUMENT_PREFIX :: "--seed="
SUPPORTED_ARGUMENTS :: "--version, --input=sdl3, --input=raylib, --seed=<number>, --debug-terrain"

Input_Backend_Request :: enum u8 {
	Automatic,
	Sdl3,
	Raylib,
}

Command_Line :: struct {
	show_version:        bool,
	input_request:       Input_Backend_Request,
	seed:                u64,
	debug_terrain:       bool,
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
	registry, registry_loaded := load_block_registry(data_directory)
	if !registry_loaded {
		os.exit(1)
	}
	generator, generator_loaded := load_generator(data_directory, registry, command_line.seed)
	if !generator_loaded {
		os.exit(1)
	}
	start := choose_world_start(&generator, command_line.debug_terrain)
	input_backend, input_started := start_input_backend(command_line.input_request)
	if !input_started {
		os.exit(1)
	}
	run_game(config, input_backend, registry, generator, start, data_directory)
}

World_Start :: struct {
	debug_terrain: bool,
	player:        Player_Start,
}

// The debug terrain has no spawn search, so the player starts flying from
// the old fly camera start.
debug_terrain_player_start :: proc() -> Player_Start {
	camera := INITIAL_FLY_CAMERA
	return Player_Start{position = camera.position - {0, PLAYER_EYE_HEIGHT, 0}, yaw = camera.yaw, pitch = camera.pitch, flying = true}
}

// Runs the spawn search before the window opens, so its result (or failure)
// shows on stderr even without a display.
choose_world_start :: proc(generator: ^Generator, debug_terrain: bool) -> World_Start {
	if debug_terrain {
		fmt.eprintfln("world: debug terrain (seed %d unused)", generator.seed)
		return World_Start{debug_terrain = true, player = debug_terrain_player_start()}
	}
	spawn, found := find_spawn(generator)
	if found {
		fmt.eprintfln("world: seed %d, spawn at %d %d %d", generator.seed, spawn.x, spawn.y, spawn.z)
	} else {
		fmt.eprintfln("world: seed %d, no spawn meets the requirements, starting at the origin", generator.seed)
		spawn = {0, terrain_height(generator.seeds, 0, 0), 0}
	}
	return World_Start{player = player_start_on(spawn)}
}
