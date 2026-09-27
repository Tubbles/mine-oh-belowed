package game

import "core:encoding/json"
import "core:fmt"
import "core:os"

DATA_DIRECTORY_ENVIRONMENT_VARIABLE :: "MINE_OH_BELOWED_DATA"
WORKING_DIRECTORY_DATA :: "data"
INSTALLED_DATA_RELATIVE_TO_EXECUTABLE :: "../share/mine-oh-belowed/data"
GAME_CONFIG_FILE_NAME :: "game.sjson"
MAXIMUM_TICK_RATE :: 1000

MAXIMUM_DAY_LENGTH_SECONDS :: 24 * 60 * 60

Starting_Item :: struct {
	item:  string,
	count: int,
}

Game_Config :: struct {
	name:                 string,
	tick_rate:            int,
	day_length_seconds:   int,
	starting_items:       []Starting_Item,
	// The world setting "all recipes unlocked at start".
	all_recipes_unlocked: bool,
	// The world setting "vein finiteness": true lets veins never run dry.
	veins_infinite:       bool,
}

// An explicitly set environment variable wins even if the directory is
// missing, so that a typo fails loudly instead of silently falling back.
resolve_data_directory :: proc(allocator := context.allocator) -> (directory: string, ok: bool) {
	if value, found := os.lookup_env(DATA_DIRECTORY_ENVIRONMENT_VARIABLE, allocator); found && value != "" {
		return value, true
	}
	if os.is_dir(WORKING_DIRECTORY_DATA) {
		return WORKING_DIRECTORY_DATA, true
	}
	return installed_data_directory(allocator)
}

installed_data_directory :: proc(allocator := context.allocator) -> (directory: string, ok: bool) {
	executable_directory, error := os.get_executable_directory(context.temp_allocator)
	if error != nil {
		return "", false
	}
	joined, join_error := os.join_path({executable_directory, INSTALLED_DATA_RELATIVE_TO_EXECUTABLE}, allocator)
	if join_error != nil || !os.is_dir(joined) {
		return "", false
	}
	return joined, true
}

parse_game_config :: proc(data: []byte, allocator := context.allocator) -> (config: Game_Config, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &config, .SJSON, allocator)
	return
}

// Returns an empty string when the config is valid, otherwise the problem.
validate_game_config :: proc(config: Game_Config) -> string {
	if config.name == "" {
		return "name is missing or empty"
	}
	if config.tick_rate < 1 || config.tick_rate > MAXIMUM_TICK_RATE {
		return fmt.tprintf("tick_rate %d is outside 1 to %d", config.tick_rate, MAXIMUM_TICK_RATE)
	}
	if config.day_length_seconds < 1 || config.day_length_seconds > MAXIMUM_DAY_LENGTH_SECONDS {
		return fmt.tprintf("day_length_seconds %d is outside 1 to %d", config.day_length_seconds, MAXIMUM_DAY_LENGTH_SECONDS)
	}
	return ""
}

// Needs the item registry, so it runs after both files are loaded.
validate_starting_items :: proc(starting_items: []Starting_Item, items: Item_Registry) -> string {
	for starting in starting_items {
		if _, found := find_item_id(items, starting.item); !found {
			return fmt.tprintf("starting item %q is not in %s", starting.item, ITEMS_FILE_NAME)
		}
		if starting.count < 1 {
			return fmt.tprintf("starting item %q has count %d", starting.item, starting.count)
		}
	}
	return ""
}

load_game_config :: proc(data_directory: string, allocator := context.allocator) -> (config: Game_Config, ok: bool) {
	path, join_error := os.join_path({data_directory, GAME_CONFIG_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	parse_error: json.Unmarshal_Error
	config, parse_error = parse_game_config(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	if problem := validate_game_config(config); problem != "" {
		fmt.eprintfln("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return config, true
}
