package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import rl "shared:raylib"
import "platform"

DATA_DIRECTORY_ENVIRONMENT_VARIABLE :: "MINE_OH_BELOWED_DATA"
WORKING_DIRECTORY_DATA :: "data"
INSTALLED_DATA_RELATIVE_TO_EXECUTABLE :: "../share/mine-oh-belowed/data"
GAME_CONFIG_FILE_NAME :: "game.sjson"
MAXIMUM_TICK_RATE :: 1000

MAXIMUM_DAY_LENGTH_SECONDS :: 24 * 60 * 60
// A week, which keeps the age in ticks far inside a u32 at any tick rate.
MAXIMUM_LOOSE_ITEM_DESPAWN_MINUTES :: 7 * 24 * 60
// Bounds the nodes the field's level of detail walks per frame
// (select_field_nodes): the walk descends from nodes as wide as the view
// and visits only those crossing the planet's surface shell: about 40,000
// at 333 mm and 4096 m (and 19,000 nodes selected), 4,000 at 1 m, where a
// walk over every coarsest node in the view's cube would visit about
// 970,000 at 333 mm.
MAXIMUM_FIELD_VIEW_DISTANCE_METRES :: 4096
// The finest node's width at the widest sample spacing, FIELD_CHUNK_SIZE
// samples of 1 m (asserted in world_field_lod.odin); a level's node is
// twice the width of the level below.
FIELD_FINEST_NODE_MAXIMUM_METRES :: 32
// Ten thousand times the square root of three, rounded up.
SQUARE_ROOT_OF_THREE_TEN_THOUSANDTHS :: 17321
// The terrain field's levels of detail: full, half, quarter and eighth
// resolution (world_field_lod.odin).
FIELD_LEVEL_COUNT :: 4

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
	field_view:           Field_View_Config,
}

// The terrain field's level of detail (work item 0169,
// world_field_lod.odin).
Field_View_Config :: struct {
	// A node nearer the camera than entry L is meshed at level L (full,
	// half, quarter, eighth resolution); beyond the last entry only the
	// globe is drawn. The first entry is also how far the planet preview
	// streams field chunks.
	level_distances_metres: [FIELD_LEVEL_COUNT]int,
}

// The index of the first definition with the id, -1 for none.
find_definition_index :: proc(definitions: []$T, id: string) -> int {
	for definition, index in definitions {
		if definition.id == id {
			return index
		}
	}
	return -1
}

// An explicitly set environment variable wins even if the directory is
// missing, so that a typo fails loudly instead of silently falling back.
// Then ./data, data beside the executable (the unzipped Windows build, work
// item 0102, from any working directory) and the installed layout. On
// Android (work item 0114) the copy of the APK's data under the app's
// internal folder, refreshed when the build changed.
resolve_data_directory :: proc(allocator := context.allocator) -> (directory: string, ok: bool) {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		internal, _ := platform.android_data_paths()
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
		platform.log_printf("error: cannot copy %s from the app: not in the APK", ANDROID_ASSET_LIST)
		return false
	}
	for path in android_asset_paths(string(list)) {
		if problem := copy_android_asset(internal, path); problem != "" {
			platform.log_printf("error: cannot copy %s from the app: %s", path, problem)
			return false
		}
	}
	if error := os.write_entire_file(stamp_path, build_info); error != nil {
		platform.log_printf("error: cannot copy %s from the app: %v", stamp_path, error)
		return false
	}
	platform.log_printf("data: copied the app's data to %s", data_directory)
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
	if error := platform.make_directory_path(directory); error != nil {
		return fmt.tprintf("%v", error)
	}
	if error := os.write_entire_file(target, data); error != nil {
		return fmt.tprintf("%v", error)
	}
	return ""
}

// The data edits overlay (work item 0129): a copy of a data file under
// <state>/mine-oh-belowed/data_edits/<relative path> wins over the data
// file. The Data files screen (ui_data_browser.odin) shows which files
// have one, work item 0130 writes them. The overlay is not watched: the
// frame loop applies what the screen changed through
// apply_data_edit_change (hot_reload.odin).
DATA_EDITS_DIRECTORY_NAME :: "data_edits"

// $XDG_STATE_HOME/mine-oh-belowed/data_edits. In the given allocator.
data_edits_directory_from_environment :: proc(state_home, home: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	state_directory := platform.log_directory_from_environment(state_home, home, context.temp_allocator) or_return
	joined, error := os.join_path({state_directory, DATA_EDITS_DIRECTORY_NAME}, allocator)
	return joined, error == nil
}

// The data file at relative_path (/ between names), or its overlay copy
// when data_edits_directory has one, which is logged; path is the file
// read, for the caller's problem lines. The data is in allocator, the path
// in the temp allocator.
read_data_file :: proc(data_directory, relative_path: string, allocator := context.allocator) -> (data: []byte, path: string, error: os.Error) {
	return read_data_file_with_edits(data_directory, reading_data_edits_directory(), relative_path, allocator)
}

// How read_data_file uses the data edits overlay, per thread: the game
// reads its data files on the main thread only, and the tests, which run
// in parallel, give their own thread a directory. After a start-up load
// failed with the overlay on (work item 0130's review), the overlay is off
// for the run; the Data files screen still lists the copies and Discard
// still deletes them, since both use data_edits_directory.
Data_Edits_Reading :: struct {
	// Under odin test, what data_edits_directory returns: a test's own
	// temporary directory, else "".
	directory:   string,
	off:         bool,
	// The failed load's problem, on the heap for the run.
	off_problem: string,
}

@(thread_local)
data_edits_reading: Data_Edits_Reading

// The overlay read_data_file takes, "" for none.
reading_data_edits_directory :: proc() -> string {
	if data_edits_reading.off {
		return ""
	}
	return data_edits_directory()
}

// After a start-up load failed: when the overlay was read, it goes off for
// the run (logged) and the caller loads again. False when it was off
// already or there is no overlay directory, so the caller gives up.
turn_data_edits_off :: proc(problem: string) -> bool {
	directory := reading_data_edits_directory()
	if directory == "" || !os.is_dir(directory) {
		return false
	}
	data_edits_reading.off = true
	data_edits_reading.off_problem = strings.clone(problem)
	platform.log_printf("data: the data edits are off for this run after a failed load: %s", problem)
	return true
}

// The thread's overlay reading back to the default, for the tests.
reset_data_edits_reading :: proc() {
	delete(data_edits_reading.off_problem)
	data_edits_reading = {}
}

// read_data_file with the overlay directory given; "" reads no overlay.
read_data_file_with_edits :: proc(data_directory, edits_directory, relative_path: string, allocator := context.allocator) -> (data: []byte, path: string, error: os.Error) {
	if edits_directory != "" {
		overlay := platform.join_path(edits_directory, relative_path)
		if os.is_file(overlay) {
			platform.log_printf("data: %s from the data edits overlay %s", relative_path, overlay)
			data, error = os.read_entire_file(overlay, allocator)
			return data, overlay, error
		}
	}
	path = platform.join_path(data_directory, relative_path)
	data, error = os.read_entire_file(path, allocator)
	return data, path, error
}

// read_data_file for the loaders that log a file that cannot be read and
// give up.
read_logged_data_file :: proc(data_directory, relative_path: string) -> (data: []byte, path: string, ok: bool) {
	error: os.Error
	data, path, error = read_data_file(data_directory, relative_path, context.temp_allocator)
	if error != nil {
		platform.log_printf("error: cannot read %s: %v", path, error)
		return nil, path, false
	}
	return data, path, true
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
	return field_view_problem(config.field_view)
}

// The least gap between the distances of levels L - 1 and L: the diagonal
// of a level L - 1 node at the widest spacing. Any node touching a level
// L - 1 node lies within that node's diagonal of it, so with this gap a
// node chosen at level L - 1 for its own distance never borders one chosen
// two levels coarser (the 2:1 balance the skirts' reach assumes), and the
// children of a node split at the last but one distance never lie beyond
// the last one (no hole at the far end).
field_level_gap_metres :: proc(level: int) -> int {
	node_metres := FIELD_FINEST_NODE_MAXIMUM_METRES << uint(level - 1)
	return (node_metres * SQUARE_ROOT_OF_THREE_TEN_THOUSANDTHS + 9999) / 10000
}

// Distances from 1 m to MAXIMUM_FIELD_VIEW_DISTANCE_METRES, each above the
// one before by at least field_level_gap_metres.
field_view_problem :: proc(field_view: Field_View_Config) -> string {
	distances := field_view.level_distances_metres
	if distances[0] < 1 {
		return fmt.tprintf("field_view.level_distances_metres[0] %d is below 1", distances[0])
	}
	for level in 1 ..< FIELD_LEVEL_COUNT {
		least := distances[level - 1] + field_level_gap_metres(level)
		if distances[level] < least {
			return fmt.tprintf("field_view.level_distances_metres[%d] %d is below %d, the distance before it plus a level %d node's diagonal", level, distances[level], least, level - 1)
		}
	}
	if distances[FIELD_LEVEL_COUNT - 1] > MAXIMUM_FIELD_VIEW_DISTANCE_METRES {
		return fmt.tprintf("field_view.level_distances_metres[%d] %d is above %d", FIELD_LEVEL_COUNT - 1, distances[FIELD_LEVEL_COUNT - 1], MAXIMUM_FIELD_VIEW_DISTANCE_METRES)
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
	data, path := read_logged_data_file(data_directory, GAME_CONFIG_FILE_NAME) or_return
	parse_error: json.Unmarshal_Error
	config, parse_error = parse_game_config(data, allocator)
	if parse_error != nil {
		platform.log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	if problem := validate_game_config(config); problem != "" {
		platform.log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return config, true
}
