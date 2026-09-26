package game

import "core:fmt"
import "core:os"
import "core:strings"

GAME_VERSION :: "0.0.0"

INPUT_ARGUMENT_PREFIX :: "--input="

Input_Backend_Request :: enum u8 {
	Automatic,
	Sdl3,
	Raylib,
}

Command_Line :: struct {
	show_version:        bool,
	input_request:       Input_Backend_Request,
	unknown_argument:    string,
	unknown_input_value: string,
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

parse_command_line :: proc(arguments: []string) -> Command_Line {
	command_line: Command_Line
	for argument in arguments {
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
		fmt.eprintfln("error: unknown argument %q (supported: --version, --input=sdl3, --input=raylib)", command_line.unknown_argument)
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
	input_backend, input_started := start_input_backend(command_line.input_request)
	if !input_started {
		os.exit(1)
	}
	run_game(config, input_backend)
}
