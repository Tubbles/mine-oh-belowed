package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
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
// The simulated chunk set's largest radius in chunks (data/game.sjson).
MAXIMUM_SIMULATED_CHUNK_RADIUS :: 16
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
// The cell of a foundation frame (world_frame.odin): from a quarter metre
// to two metres, which keeps a cell several position units wide and a
// cell's centre a few thousand cells out inside an i64.
MINIMUM_FOUNDATION_PITCH_MILLIMETRES :: 250
MAXIMUM_FOUNDATION_PITCH_MILLIMETRES :: 2000
// A foundation block's side or height in cells (at most 4096 cells a
// block, which the ghost draws every frame), and the entries of each list
// (work item 0193): the index a player keeps is a u8.
MAXIMUM_FOUNDATION_BLOCK_CELLS :: 16
MAXIMUM_FOUNDATION_BLOCK_CHOICES :: 16
// Each side of the direct placement limit in cells (work item 0215).
MAXIMUM_DIRECT_PLACEMENT_LIMIT_CELLS :: 16

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
	// The simulated chunk set's radius in chunks around every player's
	// chunk (simulation_chunk_set.odin).
	simulated_chunk_radius_horizontal: int,
	simulated_chunk_radius_vertical:   int,
	field_view:           Field_View_Config,
	field_player:         Field_Player_Config,
	field_brushes:        []Field_Brush_Config,
	field_water:          Field_Water_Config,
	// The cell of a foundation frame (work item 0174, world_frame.odin).
	foundation_pitch_millimetres: int,
	// The block sizes and heights a held foundation offers (work item
	// 0193, entity_frames.odin).
	foundation_sizes:     []int,
	foundation_heights:   []int,
	// The largest footprint Place puts down in one press while the
	// placement editor is on (work item 0215, ui_placement_editor.odin).
	direct_placement_limit: Placement_Limit_Config,
	// The constraints of a belt or pipe run between poles (work item
	// 0176, belt_run.odin).
	belt_runs:            Belt_Runs_Config,
	// The field session's simulated chunks and its torch (work item 0179,
	// simulation_field_chunk_set.odin, simulation_field.odin).
	field_simulation:     Field_Simulation_Config,
	// Machines on bare ground (work item 0201, machine_wear.odin): the
	// slope a machine stands on without a foundation, its life in minutes
	// of operation there, and the share of its recipe a worn one returns.
	bare_ground_flatness_millimetres: int,
	bare_ground_life_minutes:         int,
	salvage_percent:                  int,
	// The arrival (work items 0200, 0269, simulation_arrival.odin,
	// data_arrival_curve.odin, render_arrival.odin): a new world's fall in
	// ticks (0 for none), the ticks between the hit and the landing, the
	// fall's start above the crater's floor, the entry's angle and speed,
	// the terminal speed at the planet's radius, the share of the peak
	// heating below which nothing glows, the curve's last seconds played
	// 1:1, and the atmosphere.
	arrival_ticks:                    int,
	arrival_settle_ticks:             int,
	arrival_start_metres:             int,
	arrival_entry_angle_degrees:      int,
	arrival_entry_speed_metres_per_second: int,
	arrival_terminal_speed_metres_per_second: int,
	arrival_heat_threshold_percent:   int,
	arrival_real_seconds:             int,
	atmosphere:                       Atmosphere_Config,
	// The pod's airlock (work items 0222, 0231, entity_pod_airlock.odin):
	// how near a player's capsule keeps a hatch open (0231).
	pod_airlock:                      Pod_Airlock_Config,
}

// A footprint in cells: width along the model's x, depth along its z,
// height (work item 0215). Here rather than Machine_Footprint_Definition,
// since content may not reference the simulation cluster.
Placement_Limit_Config :: struct {
	width, depth, height: int,
}

// The field's simulated chunk set: every chunk within chunk_radius chunks
// of a player's chunk on each axis, and the chunks it held within
// chunk_margin more; the torch item and the emitter of
// data/lighting.sjson it places; the foundation of the benchmark's pad
// (work item 0196, field_pad_foundation_problem).
Field_Simulation_Config :: struct {
	chunk_radius:   int,
	chunk_margin:   int,
	torch_item:     string,
	torch_emitter:  string,
	pad_foundation: string,
}

// The pod's airlock (work items 0222, 0231, pod_airlock_problem): the
// reach in millimetres.
Pod_Airlock_Config :: struct {
	reach_millimetres: int,
}

// The atmosphere the pod falls through (work item 0269,
// data_arrival_curve.odin, render_sky.odin): its top and its scale
// height, in metres above the planet's radius.
Atmosphere_Config :: struct {
	top_metres, scale_height_metres: int,
}

// A field chunk is about 270 KiB with its water and light: radius 3 is
// 343 chunks round one player.
MAXIMUM_FIELD_CHUNK_RADIUS :: 3
MAXIMUM_FIELD_CHUNK_MARGIN :: 2

// A run either inclines (its ends differ in height by more than the
// level tolerance, its facings aligned) or turns (level, its facings
// turning up to the maximum), never both, and spans at most the maximum.
Belt_Runs_Config :: struct {
	maximum_span_millimetres:    int,
	maximum_slope_percent:       int,
	maximum_turn_degrees:        int,
	level_tolerance_millimetres: int,
	// How far an incline's facings and chord may turn.
	aligned_degrees:             int,
}

// A run's polyline and arc length stay far inside an i64 and its length
// in line units inside an i32 at the finest pitch.
MINIMUM_BELT_RUN_SPAN_MILLIMETRES :: 1000
MAXIMUM_BELT_RUN_SPAN_MILLIMETRES :: 100_000
MAXIMUM_BELT_RUN_SLOPE_PERCENT :: 100
MINIMUM_BELT_RUN_TURN_DEGREES :: 15
MAXIMUM_BELT_RUN_TURN_DEGREES :: 135
MAXIMUM_BELT_RUN_LEVEL_TOLERANCE_MILLIMETRES :: 1000
// Half the 15 degree yaw step a free pole faces the chord by, plus one
// (asserted against FRAME_YAW_STEPS in belt_run.odin).
MINIMUM_BELT_RUN_ALIGNED_DEGREES :: 8
MAXIMUM_BELT_RUN_ALIGNED_DEGREES :: 30

// The terrain field's level of detail (work item 0169,
// world_field_lod.odin).
Field_View_Config :: struct {
	// A node nearer the camera than entry L is meshed at level L (full,
	// half, quarter, eighth resolution); beyond the last entry only the
	// globe is drawn. The first entry is also how far the planet preview
	// streams field chunks.
	level_distances_metres: [FIELD_LEVEL_COUNT]int,
}

// The player on the terrain field (work item 0170, player_field.odin):
// lengths in millimetres, speeds in millimetres per second; gravity is the
// planet record's.
Field_Player_Config :: struct {
	capsule_radius_millimetres:              int,
	capsule_height_millimetres:              int,
	eye_height_millimetres:                  int,
	// The capsule while crouched (Sneak on foot, 0218).
	crouch_height_millimetres:               int,
	// The eye while crouched.
	crouch_eye_height_millimetres:           int,
	// Ground steeper than this slows the walk and slides the player down;
	// converted to its cosine in fixed point at load (fixed_cosine).
	walkable_angle_degrees:                  int,
	// The speed a slide down ground past the walkable angle reaches.
	slide_speed_millimetres_per_second:      int,
	// A ledge up to this many samples is walked over without a jump.
	step_height_samples:                     int,
	jump_height_millimetres:                 int,
	// Jump while walking into a ledge up to this high lifts onto it.
	mantle_height_millimetres:               int,
	tool_reach_millimetres:                  int,
	walk_speed_millimetres_per_second:       int,
	sprint_speed_millimetres_per_second:     int,
	sneak_speed_millimetres_per_second:      int,
	fall_speed_limit_millimetres_per_second: int,
	fly_speed_millimetres_per_second:        int,
	fly_sprint_speed_millimetres_per_second: int,
}

// The water field (work item 0172, world_field_water.odin): fill in
// 1/FIELD_WATER_FULL of a sample. Each tick an awake sample moves at most
// the rate to each neighbour; a sample still for the still ticks sleeps;
// fill at or below the minimum stops moving and drops by one every dry
// ticks.
Field_Water_Config :: struct {
	fill_rate_per_tick:   int,
	still_ticks_to_sleep: int,
	minimum_fill:         int,
	dry_ticks_per_step:   int,
}

// A full water sample's fill: FIELD_WATER_FULL - MAXIMUM_DENSITY maps the
// fill onto the mesher's density exactly (127 full, -127 empty). Here so
// the content checks need not reach into the world.
FIELD_WATER_FULL :: 254
// A sample sleeps after at most this many still ticks (a byte per sample).
MAXIMUM_FIELD_WATER_STILL_TICKS :: 255
// An hour at 60 ticks a second.
MAXIMUM_FIELD_WATER_DRY_TICKS :: 216_000

// The shapes of a field brush (work item 0171, world_field_edit.odin): a
// sphere round the hit, or the level mode, which flattens the sphere
// round the hit to the plane through it across the player's up.
Field_Brush_Shape :: enum u8 {
	Sphere,
	Level,
}

// The names of Field_Brush_Shape in data/game.sjson.
FIELD_BRUSH_SHAPE_NAMES :: [Field_Brush_Shape]string {
	.Sphere = "sphere",
	.Level  = "level",
}

// A brush of the hand tool on the terrain field (work item 0171): the
// samples within the radius of the hit change by the rate each tick the
// brush is held, in density steps (DENSITY_STEPS_PER_SAMPLE a spacing).
Field_Brush_Config :: struct {
	id:                          string,
	// A FIELD_BRUSH_SHAPE_NAMES entry.
	shape:                       string,
	radius_millimetres:          int,
	rate_density_steps_per_tick: int,
}

MAXIMUM_FIELD_BRUSH_COUNT :: 8
MINIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES :: 100
MAXIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES :: 4000
// From full ground to air in one tick: twice the saturated density.
MAXIMUM_FIELD_BRUSH_RATE :: 254

// A bound of one Field_Player_Config value, for field_player_problem.
Config_Bound :: struct {
	name:    string,
	value:   int,
	minimum: int,
	maximum: int,
}

MAXIMUM_FIELD_PLAYER_LENGTH_MILLIMETRES :: 20000
MAXIMUM_FIELD_PLAYER_SPEED_MILLIMETRES_PER_SECOND :: 200000
MAXIMUM_STEP_HEIGHT_SAMPLES :: 4
// 8 m a tick: 2^31 velocity units (field_player_speed_problem).
MAXIMUM_FIELD_PLAYER_MILLIMETRES_PER_TICK :: 8000
// The widest of the world setting's sample spacings
// (SAMPLE_SPACING_CHOICES_MILLIMETRES, asserted in world_field.odin), here
// so the content checks need not reach into the world.
WIDEST_SAMPLE_SPACING_MILLIMETRES :: 1000

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
// have one, work item 0130 writes them. The state overlay is not watched:
// the screen's Save and Discard go through apply_data_edit_change
// (hot_reload.odin). The edits directory's overlay (work item 0228,
// <edits_directory>/data_edits) is read after it and watched with the
// data directory (open_data_edits_watch).
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
	directories := reading_data_edits_directories()
	return read_data_file_from_sources(data_directory, directories[:], relative_path, allocator)
}

// How read_data_file uses the data edits overlay, per thread: the game
// reads its data files on the main thread only, and the tests, which run
// in parallel, give their own thread a directory. After a start-up load
// failed with the overlay on (work item 0130's review), the overlay is off
// for the run; the Data files screen still lists the copies and Discard
// still deletes them, since both use data_edits_directory. The edits
// directory's overlay (work item 0228) is resolved once at start on the
// main thread (start_reachable_data_edits); tests set their own through
// use_reachable_data_edits.
Data_Edits_Reading :: struct {
	// Under odin test, what data_edits_directory returns: a test's own
	// temporary directory, else "".
	directory:           string,
	off:                 bool,
	// The failed load's problem, on the heap for the run.
	off_problem:         string,
	// <edits_directory>/data_edits, on the heap for the run, "" for none
	// (use_reachable_data_edits).
	reachable_directory: string,
	// The edits directory went away or failed during the run.
	reachable_off:       bool,
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

// Why the edits directory setting is not read, None when it is.
Reachable_Data_Edits_Refusal :: enum u8 {
	None,
	Not_Set,
	Not_Absolute,
	No_Access,
	Not_A_Directory,
}

// The setting (its ~/ expanded) checked in order: set, absolute, All
// files access granted, a data_edits directory under it.
reachable_data_edits_refusal :: proc(setting: string, access_granted, directory_exists: bool) -> Reachable_Data_Edits_Refusal {
	switch {
	case setting == "":
		return .Not_Set
	case !os.is_absolute_path(setting):
		return .Not_Absolute
	case !access_granted:
		return .No_Access
	case !directory_exists:
		return .Not_A_Directory
	}
	return .None
}

// The log line's reason for a refusal, "" for None and Not_Set.
reachable_data_edits_refusal_text :: proc(refusal: Reachable_Data_Edits_Refusal) -> string {
	switch refusal {
	case .None, .Not_Set:
		return ""
	case .Not_Absolute:
		return "it is not an absolute path"
	case .No_Access:
		return "All files access is not granted"
	case .Not_A_Directory:
		return "it has no data_edits directory"
	}
	return ""
}

// The edits directory's overlay read_data_file takes after the state's,
// "" for none; called at start and by the tests.
use_reachable_data_edits :: proc(directory: string) {
	delete(data_edits_reading.reachable_directory)
	data_edits_reading.reachable_directory = strings.clone(directory)
	data_edits_reading.reachable_off = false
}

// The edits_directory setting resolved once at start (work item 0228):
// read when it is an absolute path with a data_edits directory and All
// files access, otherwise one log line. needs_access when only the access
// is missing, so the title toasts it.
start_reachable_data_edits :: proc(settings: Settings) -> (needs_access: bool) {
	home := platform.platform_directories(context.temp_allocator).home
	setting := expand_home_path(settings.edits_directory, home)
	access_granted, directory_exists: bool
	if setting != "" && os.is_absolute_path(setting) {
		access_granted = platform.all_files_access_granted()
	}
	directory := platform.join_path(setting, DATA_EDITS_DIRECTORY_NAME)
	if access_granted {
		directory_exists = os.is_dir(directory)
	}
	refusal := reachable_data_edits_refusal(setting, access_granted, directory_exists)
	switch refusal {
	case .None:
		use_reachable_data_edits(directory)
		platform.log_printf("data: reading data edits from %s", directory)
	case .Not_Set:
	case .Not_Absolute, .No_Access, .Not_A_Directory:
		platform.log_printf("data: the edits directory %s is not read: %s", setting, reachable_data_edits_refusal_text(refusal))
	}
	return refusal == .No_Access
}

// The edits directory's overlay off for the rest of the run, logged once.
turn_reachable_data_edits_off :: proc(problem: string) {
	if data_edits_reading.reachable_directory == "" || data_edits_reading.reachable_off {
		return
	}
	data_edits_reading.reachable_off = true
	platform.log_printf("data: the edits directory %s is off for this run: %s", data_edits_reading.reachable_directory, problem)
}

// The edits directory's overlay to read, "" for none; a directory that
// went away turns it off (one stat per data file read).
reachable_data_edits_directory :: proc() -> string {
	if data_edits_reading.off || data_edits_reading.reachable_off || data_edits_reading.reachable_directory == "" {
		return ""
	}
	if !os.is_dir(data_edits_reading.reachable_directory) {
		turn_reachable_data_edits_off("the directory is gone")
		return ""
	}
	return data_edits_reading.reachable_directory
}

// The overlays in the order they win: the state copy, then the edits
// directory's copy, both over the data file; "" for one not read.
data_edits_directories :: proc(state_directory, reachable_directory: string, off, reachable_off: bool) -> [2]string {
	if off {
		return {}
	}
	return {state_directory, reachable_off ? "" : reachable_directory}
}

// The overlays read_data_file takes.
reading_data_edits_directories :: proc() -> [2]string {
	return data_edits_directories(data_edits_directory(), reachable_data_edits_directory(), data_edits_reading.off, data_edits_reading.reachable_off)
}

// After a start-up load failed: when an overlay was read, both go off for
// the run (logged) and the caller loads again. False when they were off
// already or there is no overlay directory, so the caller gives up.
turn_data_edits_off :: proc(problem: string) -> bool {
	any_read := false
	for directory in reading_data_edits_directories() {
		if directory != "" && os.is_dir(directory) {
			any_read = true
		}
	}
	if !any_read {
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
	delete(data_edits_reading.reachable_directory)
	data_edits_reading = {}
}

// read_data_file with the overlay directory given; "" reads no overlay.
read_data_file_with_edits :: proc(data_directory, edits_directory, relative_path: string, allocator := context.allocator) -> (data: []byte, path: string, error: os.Error) {
	sources := [1]string{edits_directory}
	return read_data_file_from_sources(data_directory, sources[:], relative_path, allocator)
}

// read_data_file with the overlay directories given in the order they
// win; "" entries are skipped.
read_data_file_from_sources :: proc(data_directory: string, edits_directories: []string, relative_path: string, allocator := context.allocator) -> (data: []byte, path: string, error: os.Error) {
	for edits_directory in edits_directories {
		if edits_directory == "" {
			continue
		}
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
	if config.simulated_chunk_radius_horizontal < 1 || config.simulated_chunk_radius_horizontal > MAXIMUM_SIMULATED_CHUNK_RADIUS {
		return fmt.tprintf("simulated_chunk_radius_horizontal %d is outside 1 to %d", config.simulated_chunk_radius_horizontal, MAXIMUM_SIMULATED_CHUNK_RADIUS)
	}
	if config.simulated_chunk_radius_vertical < 1 || config.simulated_chunk_radius_vertical > MAXIMUM_SIMULATED_CHUNK_RADIUS {
		return fmt.tprintf("simulated_chunk_radius_vertical %d is outside 1 to %d", config.simulated_chunk_radius_vertical, MAXIMUM_SIMULATED_CHUNK_RADIUS)
	}
	if problem := field_view_problem(config.field_view); problem != "" {
		return problem
	}
	if problem := field_player_problem(config.field_player); problem != "" {
		return problem
	}
	if problem := field_brushes_problem(config.field_brushes); problem != "" {
		return problem
	}
	if problem := field_water_problem(config.field_water); problem != "" {
		return problem
	}
	if config.foundation_pitch_millimetres < MINIMUM_FOUNDATION_PITCH_MILLIMETRES || config.foundation_pitch_millimetres > MAXIMUM_FOUNDATION_PITCH_MILLIMETRES {
		return fmt.tprintf("foundation_pitch_millimetres %d is outside %d to %d", config.foundation_pitch_millimetres, MINIMUM_FOUNDATION_PITCH_MILLIMETRES, MAXIMUM_FOUNDATION_PITCH_MILLIMETRES)
	}
	if problem := foundation_block_list_problem("foundation_sizes", config.foundation_sizes); problem != "" {
		return problem
	}
	if problem := foundation_block_list_problem("foundation_heights", config.foundation_heights); problem != "" {
		return problem
	}
	if problem := direct_placement_limit_problem(config.direct_placement_limit); problem != "" {
		return problem
	}
	if problem := belt_runs_problem(config.belt_runs); problem != "" {
		return problem
	}
	if problem := field_simulation_problem(config.field_simulation); problem != "" {
		return problem
	}
	if problem := bare_ground_problem(config); problem != "" {
		return problem
	}
	if problem := arrival_problem(config); problem != "" {
		return problem
	}
	if problem := pod_airlock_problem(config.pod_airlock); problem != "" {
		return problem
	}
	return field_player_speed_problem(config.field_player, config.tick_rate)
}

// Each side of the direct placement limit (0215) from 1 to 16; a missing
// key reads as zero and fails.
direct_placement_limit_problem :: proc(limit: Placement_Limit_Config) -> string {
	bounds := [?]Config_Bound {
		{"direct_placement_limit.width", limit.width, 1, MAXIMUM_DIRECT_PLACEMENT_LIMIT_CELLS},
		{"direct_placement_limit.depth", limit.depth, 1, MAXIMUM_DIRECT_PLACEMENT_LIMIT_CELLS},
		{"direct_placement_limit.height", limit.height, 1, MAXIMUM_DIRECT_PLACEMENT_LIMIT_CELLS},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	return ""
}

// The bounds of data/game.sjson's bare ground values (bare_ground_problem).
MAXIMUM_BARE_GROUND_FLATNESS_MILLIMETRES :: 2000
MAXIMUM_BARE_GROUND_LIFE_MINUTES :: 7 * 24 * 60

// Every value of the bare ground (0201) inside its bound; a missing key
// reads as zero and fails the life's and the salvage's.
bare_ground_problem :: proc(config: Game_Config) -> string {
	bounds := [?]Config_Bound {
		{"bare_ground_flatness_millimetres", config.bare_ground_flatness_millimetres, 0, MAXIMUM_BARE_GROUND_FLATNESS_MILLIMETRES},
		{"bare_ground_life_minutes", config.bare_ground_life_minutes, 1, MAXIMUM_BARE_GROUND_LIFE_MINUTES},
		{"salvage_percent", config.salvage_percent, 1, 100},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	return ""
}

// The bounds of data/game.sjson's arrival values (arrival_problem, work
// items 0200, 0269). MAXIMUM_ARRIVAL_TICKS bounds the saved fall too
// (read_field_arrival_table).
MAXIMUM_ARRIVAL_TICKS :: 3600
MAXIMUM_ARRIVAL_SETTLE_TICKS :: 300
MINIMUM_ARRIVAL_START_METRES :: 20
MAXIMUM_ARRIVAL_START_METRES :: 4096
MINIMUM_ARRIVAL_ENTRY_ANGLE_DEGREES :: 5
MAXIMUM_ARRIVAL_ENTRY_ANGLE_DEGREES :: 85
MAXIMUM_ARRIVAL_SPEED_METRES_PER_SECOND :: 1000
MAXIMUM_ARRIVAL_HEAT_THRESHOLD_PERCENT :: 90
MAXIMUM_ARRIVAL_REAL_SECONDS :: 60
MINIMUM_ATMOSPHERE_TOP_METRES :: 64
MAXIMUM_ATMOSPHERE_METRES :: 4096

// Every arrival value inside its bound; arrival_ticks 0 is no fall, else
// it holds the hit and one tick of descent. Then the atmosphere leaves
// the ground's sky clear and the start lies above its top wherever the
// crater lies; then the curve (build_arrival_curve): it reaches the
// floor, its start stays inside ARRIVAL_START_DISTANCE_SHARE of the
// coarsest level's distance from the crater, its hit is dark, and its
// real seconds are shorter than it and than the descent. In f64, at load.
arrival_problem :: proc(config: Game_Config) -> string {
	least_ticks := config.arrival_settle_ticks + 1
	if config.arrival_ticks != 0 && (config.arrival_ticks < least_ticks || config.arrival_ticks > MAXIMUM_ARRIVAL_TICKS) {
		return fmt.tprintf("arrival_ticks %d is neither 0 nor inside %d to %d", config.arrival_ticks, least_ticks, MAXIMUM_ARRIVAL_TICKS)
	}
	bounds := [?]Config_Bound {
		{"arrival_settle_ticks", config.arrival_settle_ticks, 0, MAXIMUM_ARRIVAL_SETTLE_TICKS},
		{"arrival_start_metres", config.arrival_start_metres, MINIMUM_ARRIVAL_START_METRES, MAXIMUM_ARRIVAL_START_METRES},
		{"arrival_entry_angle_degrees", config.arrival_entry_angle_degrees, MINIMUM_ARRIVAL_ENTRY_ANGLE_DEGREES, MAXIMUM_ARRIVAL_ENTRY_ANGLE_DEGREES},
		{"arrival_entry_speed_metres_per_second", config.arrival_entry_speed_metres_per_second, 1, MAXIMUM_ARRIVAL_SPEED_METRES_PER_SECOND},
		{"arrival_terminal_speed_metres_per_second", config.arrival_terminal_speed_metres_per_second, 1, MAXIMUM_ARRIVAL_SPEED_METRES_PER_SECOND},
		{"arrival_heat_threshold_percent", config.arrival_heat_threshold_percent, 0, MAXIMUM_ARRIVAL_HEAT_THRESHOLD_PERCENT},
		{"arrival_real_seconds", config.arrival_real_seconds, 1, MAXIMUM_ARRIVAL_REAL_SECONDS},
		{"atmosphere.top_metres", config.atmosphere.top_metres, MINIMUM_ATMOSPHERE_TOP_METRES, MAXIMUM_ATMOSPHERE_METRES},
		{"atmosphere.scale_height_metres", config.atmosphere.scale_height_metres, 1, MAXIMUM_ATMOSPHERE_METRES},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	atmosphere := config.atmosphere
	clear := atmosphere.top_metres - 2 * atmosphere.scale_height_metres
	if clear < ATMOSPHERE_CLEAR_GROUND_METRES {
		return fmt.tprintf("atmosphere.top_metres %d less two scale heights of %d m leaves %d m, below %d", atmosphere.top_metres, atmosphere.scale_height_metres, clear, ATMOSPHERE_CLEAR_GROUND_METRES)
	}
	if config.arrival_start_metres < atmosphere.top_metres + MAXIMUM_RELIEF_METRES {
		return fmt.tprintf("arrival_start_metres %d is not %d m above atmosphere.top_metres %d", config.arrival_start_metres, MAXIMUM_RELIEF_METRES, atmosphere.top_metres)
	}
	curve := build_arrival_curve(config)
	if !curve.reached_floor {
		return fmt.tprintf("the arrival's curve does not reach the floor within %d s", ARRIVAL_CURVE_MAXIMUM_SECONDS)
	}
	range_metres, start := f64(curve.range_metres), f64(config.arrival_start_metres)
	distance := math.sqrt(range_metres * range_metres + start * start)
	farthest := ARRIVAL_START_DISTANCE_SHARE * f64(config.field_view.level_distances_metres[FIELD_COARSEST_LEVEL])
	if distance > farthest {
		return fmt.tprintf("arrival_start_metres %d with a range of %d m starts %d m from the crater, beyond %d m", config.arrival_start_metres, int(range_metres), int(distance), int(farthest))
	}
	if f64(curve.hit_heat_share) * 100 >= f64(config.arrival_heat_threshold_percent) {
		return fmt.tprintf("the heat at the hit is %d percent of the peak, not below arrival_heat_threshold_percent %d", int(curve.hit_heat_share * 100), config.arrival_heat_threshold_percent)
	}
	if f32(config.arrival_real_seconds) >= curve.natural_seconds {
		return fmt.tprintf("arrival_real_seconds %d is not below the curve's %.1f natural seconds", config.arrival_real_seconds, curve.natural_seconds)
	}
	descent_ticks := config.arrival_ticks - config.arrival_settle_ticks
	if config.arrival_ticks != 0 && config.arrival_real_seconds * config.tick_rate >= descent_ticks {
		return fmt.tprintf("arrival_real_seconds %d is not below the descent's %d ticks", config.arrival_real_seconds, descent_ticks)
	}
	return ""
}

// The bounds of data/game.sjson's pod_airlock values (pod_airlock_problem,
// work item 0222).
MINIMUM_POD_AIRLOCK_REACH_MILLIMETRES :: 50
MAXIMUM_POD_AIRLOCK_REACH_MILLIMETRES :: 300

// Every pod_airlock value inside its bound; a missing key reads as zero
// and fails.
pod_airlock_problem :: proc(airlock: Pod_Airlock_Config) -> string {
	bounds := [?]Config_Bound {
		{"pod_airlock.reach_millimetres", airlock.reach_millimetres, MINIMUM_POD_AIRLOCK_REACH_MILLIMETRES, MAXIMUM_POD_AIRLOCK_REACH_MILLIMETRES},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	return ""
}

// The torch's item and emitter are checked against the items and the
// lighting file when the content loads (field_torch_problem).
field_simulation_problem :: proc(field: Field_Simulation_Config) -> string {
	switch {
	case field.chunk_radius < 1 || field.chunk_radius > MAXIMUM_FIELD_CHUNK_RADIUS:
		return fmt.tprintf("field_simulation.chunk_radius %d is outside 1 to %d", field.chunk_radius, MAXIMUM_FIELD_CHUNK_RADIUS)
	case field.chunk_margin < 0 || field.chunk_margin > MAXIMUM_FIELD_CHUNK_MARGIN:
		return fmt.tprintf("field_simulation.chunk_margin %d is outside 0 to %d", field.chunk_margin, MAXIMUM_FIELD_CHUNK_MARGIN)
	case field.torch_item == "" || field.torch_emitter == "":
		return "field_simulation.torch_item and torch_emitter must not be empty"
	}
	return ""
}

field_brush_shape_from_name :: proc(name: string) -> (shape: Field_Brush_Shape, found: bool) {
	names := FIELD_BRUSH_SHAPE_NAMES
	for candidate in Field_Brush_Shape {
		if names[candidate] == name {
			return candidate, true
		}
	}
	return .Sphere, false
}

// One to MAXIMUM_FOUNDATION_BLOCK_CHOICES entries (0193), each from 1 to
// MAXIMUM_FOUNDATION_BLOCK_CELLS, so a block and its ghost hold at most
// 16 by 16 by 16 = 4096 cells; a missing list is empty and refused.
foundation_block_list_problem :: proc(name: string, values: []int) -> string {
	if len(values) < 1 || len(values) > MAXIMUM_FOUNDATION_BLOCK_CHOICES {
		return fmt.tprintf("%s has %d entries, not 1 to %d", name, len(values), MAXIMUM_FOUNDATION_BLOCK_CHOICES)
	}
	for value, index in values {
		if value < 1 || value > MAXIMUM_FOUNDATION_BLOCK_CELLS {
			return fmt.tprintf("%s[%d] %d is outside 1 to %d", name, index, value, MAXIMUM_FOUNDATION_BLOCK_CELLS)
		}
	}
	return ""
}

// One to MAXIMUM_FIELD_BRUSH_COUNT brushes, each with a unique id, a known
// shape, and the radius and rate inside their bounds; a missing
// field_brushes list is empty and refused.
field_brushes_problem :: proc(brushes: []Field_Brush_Config) -> string {
	if len(brushes) < 1 || len(brushes) > MAXIMUM_FIELD_BRUSH_COUNT {
		return fmt.tprintf("field_brushes has %d brushes, not 1 to %d", len(brushes), MAXIMUM_FIELD_BRUSH_COUNT)
	}
	for brush, index in brushes {
		switch {
		case brush.id == "":
			return fmt.tprintf("field_brushes[%d] has no id", index)
		case find_definition_index(brushes[:index], brush.id) >= 0:
			return fmt.tprintf("field_brushes[%d]: id %q is used twice", index, brush.id)
		case brush.radius_millimetres < MINIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES || brush.radius_millimetres > MAXIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES:
			return fmt.tprintf("field_brushes[%d].radius_millimetres %d is outside %d to %d", index, brush.radius_millimetres, MINIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES, MAXIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES)
		case brush.rate_density_steps_per_tick < 1 || brush.rate_density_steps_per_tick > MAXIMUM_FIELD_BRUSH_RATE:
			return fmt.tprintf("field_brushes[%d].rate_density_steps_per_tick %d is outside 1 to %d", index, brush.rate_density_steps_per_tick, MAXIMUM_FIELD_BRUSH_RATE)
		}
		if _, found := field_brush_shape_from_name(brush.shape); !found {
			return fmt.tprintf("field_brushes[%d].shape %q is not sphere or level", index, brush.shape)
		}
	}
	return ""
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

// Every value inside its bound, the capsule taller than its two end caps
// and the eye inside it, the crouch below the standing capsule and above
// its caps, its eye inside it; a missing field_player block reads as zeros and
// fails the first bound.
field_player_problem :: proc(player: Field_Player_Config) -> string {
	length := MAXIMUM_FIELD_PLAYER_LENGTH_MILLIMETRES
	speed := MAXIMUM_FIELD_PLAYER_SPEED_MILLIMETRES_PER_SECOND
	bounds := [?]Config_Bound {
		{"capsule_radius_millimetres", player.capsule_radius_millimetres, 100, 1000},
		{"capsule_height_millimetres", player.capsule_height_millimetres, 2 * player.capsule_radius_millimetres + 1, 4000},
		{"eye_height_millimetres", player.eye_height_millimetres, 1, player.capsule_height_millimetres},
		{"crouch_height_millimetres", player.crouch_height_millimetres, 2 * player.capsule_radius_millimetres + 1, player.capsule_height_millimetres - 1},
		{"crouch_eye_height_millimetres", player.crouch_eye_height_millimetres, 1, player.crouch_height_millimetres},
		{"walkable_angle_degrees", player.walkable_angle_degrees, 1, 89},
		{"slide_speed_millimetres_per_second", player.slide_speed_millimetres_per_second, 1, speed},
		{"step_height_samples", player.step_height_samples, 0, MAXIMUM_STEP_HEIGHT_SAMPLES},
		{"jump_height_millimetres", player.jump_height_millimetres, 1, length},
		{"mantle_height_millimetres", player.mantle_height_millimetres, 1, length},
		{"tool_reach_millimetres", player.tool_reach_millimetres, 1, length},
		{"walk_speed_millimetres_per_second", player.walk_speed_millimetres_per_second, 1, speed},
		{"sprint_speed_millimetres_per_second", player.sprint_speed_millimetres_per_second, 1, speed},
		{"sneak_speed_millimetres_per_second", player.sneak_speed_millimetres_per_second, 1, speed},
		{"fall_speed_limit_millimetres_per_second", player.fall_speed_limit_millimetres_per_second, 1, speed},
		{"fly_speed_millimetres_per_second", player.fly_speed_millimetres_per_second, 1, speed},
		{"fly_sprint_speed_millimetres_per_second", player.fly_sprint_speed_millimetres_per_second, 1, speed},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("field_player.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	// The step must stay below the mantle at the widest spacing, or a
	// mantle (a ledge above the step) could never happen.
	widest_step := player.step_height_samples * WIDEST_SAMPLE_SPACING_MILLIMETRES
	if widest_step >= player.mantle_height_millimetres {
		return fmt.tprintf("field_player.step_height_samples %d reaches %d mm at the widest spacing, not below mantle_height_millimetres %d", player.step_height_samples, widest_step, player.mantle_height_millimetres)
	}
	return ""
}

// Every value inside its bound; a missing field_water block reads as zeros
// and fails the first bound.
belt_runs_problem :: proc(runs: Belt_Runs_Config) -> string {
	bounds := [?]Config_Bound {
		{"maximum_span_millimetres", runs.maximum_span_millimetres, MINIMUM_BELT_RUN_SPAN_MILLIMETRES, MAXIMUM_BELT_RUN_SPAN_MILLIMETRES},
		{"maximum_slope_percent", runs.maximum_slope_percent, 1, MAXIMUM_BELT_RUN_SLOPE_PERCENT},
		{"maximum_turn_degrees", runs.maximum_turn_degrees, MINIMUM_BELT_RUN_TURN_DEGREES, MAXIMUM_BELT_RUN_TURN_DEGREES},
		{"level_tolerance_millimetres", runs.level_tolerance_millimetres, 0, MAXIMUM_BELT_RUN_LEVEL_TOLERANCE_MILLIMETRES},
		{"aligned_degrees", runs.aligned_degrees, MINIMUM_BELT_RUN_ALIGNED_DEGREES, MAXIMUM_BELT_RUN_ALIGNED_DEGREES},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("belt_runs.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	return ""
}

field_water_problem :: proc(water: Field_Water_Config) -> string {
	bounds := [?]Config_Bound {
		{"fill_rate_per_tick", water.fill_rate_per_tick, 1, FIELD_WATER_FULL},
		{"still_ticks_to_sleep", water.still_ticks_to_sleep, 1, MAXIMUM_FIELD_WATER_STILL_TICKS},
		{"minimum_fill", water.minimum_fill, 1, FIELD_WATER_FULL - 1},
		{"dry_ticks_per_step", water.dry_ticks_per_step, 1, MAXIMUM_FIELD_WATER_DRY_TICKS},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("field_water.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	return ""
}

// Each speed within MAXIMUM_FIELD_PLAYER_MILLIMETRES_PER_TICK at the tick
// rate: the controller's velocities (1/65536 of a 1/4096 m unit per tick)
// then stay below 2^31, so their products with unit vectors and their
// squares stay inside an i64 (player_field.odin).
field_player_speed_problem :: proc(player: Field_Player_Config, tick_rate: int) -> string {
	speeds := [?]Config_Bound {
		{"slide_speed_millimetres_per_second", player.slide_speed_millimetres_per_second, 0, 0},
		{"walk_speed_millimetres_per_second", player.walk_speed_millimetres_per_second, 0, 0},
		{"sprint_speed_millimetres_per_second", player.sprint_speed_millimetres_per_second, 0, 0},
		{"sneak_speed_millimetres_per_second", player.sneak_speed_millimetres_per_second, 0, 0},
		{"fall_speed_limit_millimetres_per_second", player.fall_speed_limit_millimetres_per_second, 0, 0},
		{"fly_speed_millimetres_per_second", player.fly_speed_millimetres_per_second, 0, 0},
		{"fly_sprint_speed_millimetres_per_second", player.fly_sprint_speed_millimetres_per_second, 0, 0},
	}
	limit := MAXIMUM_FIELD_PLAYER_MILLIMETRES_PER_TICK * tick_rate
	for speed in speeds {
		if speed.value > limit {
			return fmt.tprintf("field_player.%s %d moves more than %d mm a tick at tick_rate %d (at most %d)", speed.name, speed.value, MAXIMUM_FIELD_PLAYER_MILLIMETRES_PER_TICK, tick_rate, limit)
		}
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
