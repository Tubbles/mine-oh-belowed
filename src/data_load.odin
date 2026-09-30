package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import rl "shared:raylib"

DATA_DIRECTORY_ENVIRONMENT_VARIABLE :: "MINE_OH_BELOWED_DATA"
WORKING_DIRECTORY_DATA :: "data"
INSTALLED_DATA_RELATIVE_TO_EXECUTABLE :: "../share/mine-oh-belowed/data"
GAME_CONFIG_FILE_NAME :: "game.sjson"
MAXIMUM_TICK_RATE :: 1000

MAXIMUM_DAY_LENGTH_SECONDS :: 24 * 60 * 60
// A week, which keeps the age in ticks far inside a u32 at any tick rate.
MAXIMUM_LOOSE_ITEM_DESPAWN_MINUTES :: 7 * 24 * 60

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
	// Loose items vanish after lying this long, 0 for never
	// (loose_item.odin).
	loose_item_despawn_minutes: int,
}

// An explicitly set environment variable wins even if the directory is
// missing, so that a typo fails loudly instead of silently falling back.
// Then ./data, data beside the executable (the unzipped Windows build, work
// item 0102, from any working directory) and the installed layout. On
// Android (work item 0114) the copy of the APK's data under the app's
// internal folder, refreshed when the build changed.
resolve_data_directory :: proc(allocator := context.allocator) -> (directory: string, ok: bool) {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		internal, _ := android_data_paths()
		if !sync_android_assets(internal, BUILD_INFO) {
			return "", false
		}
		joined, error := os.join_path({internal, WORKING_DIRECTORY_DATA}, allocator)
		return joined, error == nil
	}
	if value, found := os.lookup_env(DATA_DIRECTORY_ENVIRONMENT_VARIABLE, allocator); found && value != "" {
		return value, true
	}
	if os.is_dir(WORKING_DIRECTORY_DATA) {
		return WORKING_DIRECTORY_DATA, true
	}
	if beside, found := data_directory_relative_to_executable(WORKING_DIRECTORY_DATA, allocator); found {
		return beside, true
	}
	return data_directory_relative_to_executable(INSTALLED_DATA_RELATIVE_TO_EXECUTABLE, allocator)
}

data_directory_relative_to_executable :: proc(relative: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	executable_directory, error := os.get_executable_directory(context.temp_allocator)
	if error != nil {
		return "", false
	}
	joined, join_error := os.join_path({executable_directory, relative}, allocator)
	if join_error != nil || !os.is_dir(joined) {
		return "", false
	}
	return joined, true
}

// The APK carries data/ as assets and the list of its files, since the
// asset manager cannot list directories (build.sh android). core:os reads
// the real file system only, so the files are copied under the internal
// folder once per build; raylib's fopen wrapper reads a relative name from
// the assets first.
ANDROID_ASSET_LIST :: "data_files.txt"
ANDROID_BUILD_STAMP_FILE :: ".build_stamp"

// One path per line, relative to the repository (data/strings/en.sjson).
// Blank lines are skipped. In the temp allocator.
android_asset_paths :: proc(list: string) -> []string {
	paths := make([dynamic]string, context.temp_allocator)
	for line in strings.split_lines(list, context.temp_allocator) {
		path := strings.trim_space(line)
		if path != "" {
			append(&paths, path)
		}
	}
	return paths[:]
}

// The copy is current when its stamp holds this build's info.
android_assets_current :: proc(stamp, build_info: string) -> bool {
	return strings.trim_space(stamp) == build_info
}

// Copies the listed assets under internal and writes the stamp last, so an
// interrupted copy is redone on the next start. False after logging the
// problem.
sync_android_assets :: proc(internal, build_info: string) -> bool {
	data_directory, _ := os.join_path({internal, WORKING_DIRECTORY_DATA}, context.temp_allocator)
	stamp_path, _ := os.join_path({data_directory, ANDROID_BUILD_STAMP_FILE}, context.temp_allocator)
	if stamp, error := os.read_entire_file(stamp_path, context.temp_allocator); error == nil && android_assets_current(string(stamp), build_info) {
		return true
	}
	// Files a newer build dropped must not linger in the copy.
	os.remove_all(data_directory)
	list, list_ok := read_android_asset(ANDROID_ASSET_LIST)
	if !list_ok {
		log_printf("error: cannot copy %s from the app: not in the APK", ANDROID_ASSET_LIST)
		return false
	}
	for path in android_asset_paths(string(list)) {
		if problem := copy_android_asset(internal, path); problem != "" {
			log_printf("error: cannot copy %s from the app: %s", path, problem)
			return false
		}
	}
	if error := os.write_entire_file(stamp_path, build_info); error != nil {
		log_printf("error: cannot copy %s from the app: %v", stamp_path, error)
		return false
	}
	log_printf("data: copied the app's data to %s", data_directory)
	return true
}

// Through raylib's fopen wrapper, which reads the asset. In the temp
// allocator.
read_android_asset :: proc(path: string) -> (data: []byte, ok: bool) {
	size: i32
	loaded := rl.LoadFileData(strings.clone_to_cstring(path, context.temp_allocator), &size)
	if loaded == nil {
		return nil, false
	}
	defer rl.UnloadFileData(loaded)
	return slice.clone(loaded[:size], context.temp_allocator), true
}

// An empty string, or the problem.
copy_android_asset :: proc(internal, path: string) -> string {
	data, ok := read_android_asset(path)
	if !ok {
		return "not in the APK"
	}
	target, _ := os.join_path({internal, path}, context.temp_allocator)
	directory, _ := os.split_path(target)
	if error := make_directory_path(directory); error != nil {
		return fmt.tprintf("%v", error)
	}
	if error := os.write_entire_file(target, data); error != nil {
		return fmt.tprintf("%v", error)
	}
	return ""
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
	if config.loose_item_despawn_minutes < 0 || config.loose_item_despawn_minutes > MAXIMUM_LOOSE_ITEM_DESPAWN_MINUTES {
		return fmt.tprintf("loose_item_despawn_minutes %d is outside 0 to %d", config.loose_item_despawn_minutes, MAXIMUM_LOOSE_ITEM_DESPAWN_MINUTES)
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
		log_printf("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	parse_error: json.Unmarshal_Error
	config, parse_error = parse_game_config(data, allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	if problem := validate_game_config(config); problem != "" {
		log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return config, true
}
