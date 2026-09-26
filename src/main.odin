package game

import "core:fmt"
import "core:os"

GAME_VERSION :: "0.0.0"

Command_Line :: struct {
	show_version:     bool,
	unknown_argument: string,
}

parse_command_line :: proc(arguments: []string) -> Command_Line {
	command_line: Command_Line
	for argument in arguments {
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

main :: proc() {
	command_line := parse_command_line(os.args[1:])
	if command_line.unknown_argument != "" {
		fmt.eprintfln("error: unknown argument %q (supported: --version)", command_line.unknown_argument)
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
	run_game(config)
}
