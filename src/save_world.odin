package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

// Saves on disk (doc/architecture.md, Save format). A world lives in
// <saves>/<directory>/: world.sjson (format version, name, seed, world
// settings, tick, day time, last played), entities.bin (save_state.odin)
// and regions/<x>_<z>.bin with the modified chunks of one region of
// REGION_SIZE_IN_CHUNKS by REGION_SIZE_IN_CHUNKS chunk columns. Chunks
// that match generation are not written; they regenerate from the seed.
//
// A save is written into <directory>.saving and then swapped in: the old
// save moves to <directory>.previous, the new one takes its place, and the
// old one is removed. A crash leaves either the old or the new save
// complete; after a crash between the two renames only .previous exists,
// and loading falls back to it.

SAVES_DIRECTORY_ENVIRONMENT_VARIABLE :: "MINE_OH_BELOWED_SAVES"
SAVES_UNDER_DATA_HOME :: "mine-oh-belowed/saves"
DATA_HOME_UNDER_HOME :: ".local/share"
WORLD_FILE_NAME :: "world.sjson"
ENTITIES_FILE_NAME :: "entities.bin"
REGIONS_DIRECTORY_NAME :: "regions"
REGION_FILE_MAGIC :: "MOBR"
REGION_FILE_EXTENSION :: ".bin"
STAGING_DIRECTORY_SUFFIX :: ".saving"
PREVIOUS_DIRECTORY_SUFFIX :: ".previous"
DEFAULT_WORLD_NAME :: "world"
MAXIMUM_WORLD_DIRECTORY_NAME_LENGTH :: 64
MAXIMUM_SETTING_PERCENT :: 1000

World_File_Settings :: struct {
	veins_infinite:        bool,
	all_recipes_unlocked:  bool,
	day_length_seconds:    int,
	// Percent of the size class units every vein holds.
	vein_richness_percent: int,
	// Percent of every technology's pack count.
	research_cost_percent: int,
	byproducts_lenient:    bool,
}

World_File :: struct {
	format_version:           int,
	name:                     string,
	seed:                     u64,
	settings:                 World_File_Settings,
	tick:                     u64,
	// Ticks into the current day (the tick plus the day offset), for a
	// world list to show and to restore the time of day a developer set.
	day_time_ticks:           u64,
	last_played_unix_seconds: i64,
	// The landing pad's centre (0049), so a loaded world keeps its pad when
	// the spawn rules change; a file without one falls back to the search.
	landing_pad_present:      bool,
	landing_pad:              [3]i32,
}

// Where one world's save lives. The display name goes into world.sjson,
// the directory name is its sanitised form.
Save_Location :: struct {
	saves_directory: string,
	directory_name:  string,
	display_name:    string,
}

// Directories.

// MINE_OH_BELOWED_SAVES wins, then $XDG_DATA_HOME (only when absolute, as
// the XDG specification requires), then $HOME/.local/share.
saves_directory_from_environment :: proc(saves, data_home, home: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	switch {
	case saves != "":
		return strings.clone(saves, allocator), true
	case data_home != "" && os.is_absolute_path(data_home):
		joined, error := os.join_path({data_home, SAVES_UNDER_DATA_HOME}, allocator)
		return joined, error == nil
	case home != "":
		joined, error := os.join_path({home, DATA_HOME_UNDER_HOME, SAVES_UNDER_DATA_HOME}, allocator)
		return joined, error == nil
	}
	return "", false
}

// configured is paths.saves from the configuration, which the environment
// variable overrides.
resolve_saves_directory :: proc(configured: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	saves := os.get_env(SAVES_DIRECTORY_ENVIRONMENT_VARIABLE, context.temp_allocator)
	if saves == "" {
		saves = configured
	}
	data_home := os.get_env("XDG_DATA_HOME", context.temp_allocator)
	home := os.get_env("HOME", context.temp_allocator)
	return saves_directory_from_environment(saves, data_home, home, allocator)
}

world_name_character_is_safe :: proc(character: rune) -> bool {
	switch character {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', ' ', '-', '_':
		return true
	}
	return false
}

// Letters, digits, spaces, dashes and underscores stay, every other
// character becomes an underscore, surrounding spaces go and the length
// is capped. An empty result becomes DEFAULT_WORLD_NAME.
sanitize_world_name :: proc(name: string, allocator := context.allocator) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for character in strings.trim_space(name) {
		if strings.builder_len(builder) == MAXIMUM_WORLD_DIRECTORY_NAME_LENGTH {
			break
		}
		strings.write_byte(&builder, world_name_character_is_safe(character) ? byte(character) : '_')
	}
	sanitized := strings.trim_space(strings.to_string(builder))
	return strings.clone(sanitized == "" ? DEFAULT_WORLD_NAME : sanitized, allocator)
}

join_save_path :: proc(elements: ..string) -> string {
	joined, _ := os.join_path(elements, context.temp_allocator)
	return joined
}

world_directory_taken :: proc(saves_directory, directory_name: string) -> bool {
	target := join_save_path(saves_directory, directory_name)
	return os.exists(target) || os.exists(strings.concatenate({target, PREVIOUS_DIRECTORY_SUFFIX}, context.temp_allocator))
}

// A fresh world never takes over an existing save: "world" becomes
// "world 2", "world 3" and so on.
unused_world_directory_name :: proc(saves_directory, base: string, allocator := context.allocator) -> string {
	candidate := base
	for number := 2; world_directory_taken(saves_directory, candidate); number += 1 {
		candidate = fmt.tprintf("%s %d", base, number)
	}
	return strings.clone(candidate, allocator)
}

// The directory to load from, in the temp allocator: the save, or the
// previous one when a crash interrupted the swap.
existing_save_directory :: proc(location: Save_Location) -> (directory: string, found: bool) {
	target := join_save_path(location.saves_directory, location.directory_name)
	if os.exists(join_save_path(target, WORLD_FILE_NAME)) {
		return target, true
	}
	previous := strings.concatenate({target, PREVIOUS_DIRECTORY_SUFFIX}, context.temp_allocator)
	if os.exists(join_save_path(previous, WORLD_FILE_NAME)) {
		return previous, true
	}
	return "", false
}

// world.sjson.

make_world_file :: proc(state: ^Simulation_State, display_name: string, last_played_unix_seconds: i64) -> World_File {
	day_length_ticks := max(state.day_length_ticks, 1)
	return World_File {
		format_version = SAVE_FORMAT_VERSION,
		name = display_name,
		seed = state.world.settings.seed,
		settings = World_File_Settings {
			veins_infinite = state.world.settings.veins_infinite,
			all_recipes_unlocked = state.unlocks.unlock_all,
			day_length_seconds = int(state.day_length_ticks / u64(max(state.tick_rate, 1))),
			vein_richness_percent = state.world.settings.vein_richness_percent,
			research_cost_percent = state.world.settings.research_cost_percent,
			byproducts_lenient = state.world.settings.byproducts_lenient,
		},
		tick = state.tick,
		day_time_ticks = simulation_day_ticks(state^) % day_length_ticks,
		last_played_unix_seconds = last_played_unix_seconds,
		landing_pad_present = state.landing_pad.present,
		landing_pad = cast([3]i32)state.landing_pad.centre,
	}
}

encode_world_file :: proc(file: World_File, allocator := context.allocator) -> []byte {
	data, error := json.marshal(file, json.Marshal_Options{spec = .SJSON, pretty = true}, context.temp_allocator)
	assert(error == nil, "a world file always marshals")
	return slice.concatenate([][]byte{data, {'\n'}}, allocator)
}

// Empty problem when the file is readable and of this build's format.
parse_world_file :: proc(data: []byte, allocator := context.allocator) -> (file: World_File, problem: string) {
	if error := json.unmarshal(data, &file, .SJSON, allocator); error != nil {
		return {}, fmt.tprintf("cannot parse %s: %v", WORLD_FILE_NAME, error)
	}
	file.settings = with_percent_defaults(file.settings)
	switch {
	case file.format_version > SAVE_FORMAT_VERSION:
		return file, fmt.tprintf("the save has format version %d, newer than this build reads (%d); update the game", file.format_version, SAVE_FORMAT_VERSION)
	case file.format_version < SAVE_FORMAT_VERSION:
		return file, fmt.tprintf("the save has format version %d, older than this build reads (%d); older saves are not converted yet", file.format_version, SAVE_FORMAT_VERSION)
	case file.settings.day_length_seconds < 1 || file.settings.day_length_seconds > MAXIMUM_DAY_LENGTH_SECONDS:
		return file, fmt.tprintf("day_length_seconds %d is outside 1 to %d", file.settings.day_length_seconds, MAXIMUM_DAY_LENGTH_SECONDS)
	case !setting_percent_valid(file.settings.vein_richness_percent):
		return file, fmt.tprintf("vein_richness_percent %d is outside 1 to %d", file.settings.vein_richness_percent, MAXIMUM_SETTING_PERCENT)
	case !setting_percent_valid(file.settings.research_cost_percent):
		return file, fmt.tprintf("research_cost_percent %d is outside 1 to %d", file.settings.research_cost_percent, MAXIMUM_SETTING_PERCENT)
	}
	return file, ""
}

// Worlds saved before the percent settings existed, and simulations made
// without them, count as 100 percent.
with_percent_defaults :: proc(settings: World_File_Settings) -> World_File_Settings {
	result := settings
	if result.vein_richness_percent == 0 {
		result.vein_richness_percent = 100
	}
	if result.research_cost_percent == 0 {
		result.research_cost_percent = 100
	}
	return result
}

setting_percent_valid :: proc(percent: int) -> bool {
	return percent >= 1 && percent <= MAXIMUM_SETTING_PERCENT
}

read_world_file :: proc(directory: string, allocator := context.allocator) -> (file: World_File, problem: string) {
	path := join_save_path(directory, WORLD_FILE_NAME)
	data, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		return {}, fmt.tprintf("cannot read %s: %v", path, error)
	}
	return parse_world_file(data, allocator)
}

// Regions.

Saved_Chunk :: struct {
	coordinate: Chunk_Coordinate,
	bytes:      []byte,
}

chunk_region :: proc(coordinate: Chunk_Coordinate) -> Region_Coordinate {
	return {floor_divide(coordinate.x, REGION_SIZE_IN_CHUNKS), floor_divide(coordinate.z, REGION_SIZE_IN_CHUNKS)}
}

region_file_name :: proc(region: Region_Coordinate, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%d_%d%s", region.x, region.y, REGION_FILE_EXTENSION, allocator = allocator)
}

parse_region_file_name :: proc(name: string) -> (region: Region_Coordinate, ok: bool) {
	stem := strings.trim_suffix(name, REGION_FILE_EXTENSION)
	separator := strings.index_byte(stem, '_')
	if stem == name || separator < 0 {
		return {}, false
	}
	x := strconv.parse_int(stem[:separator], 10) or_return
	z := strconv.parse_int(stem[separator + 1:], 10) or_return
	if x < int(min(i32)) || x > int(max(i32)) || z < int(min(i32)) || z > int(max(i32)) {
		return {}, false
	}
	return {i32(x), i32(z)}, true
}

saved_chunk_before :: proc(first, second: Saved_Chunk) -> bool {
	return chunk_coordinate_before(first.coordinate, second.coordinate)
}

// Every chunk a save holds: those World.saved_chunks keeps and every
// loaded modified chunk, serialised, in the temp allocator.
collect_saved_chunks :: proc(world: ^World) -> map[Chunk_Coordinate][]byte {
	chunks := make(map[Chunk_Coordinate][]byte, context.temp_allocator)
	for coordinate, bytes in world.saved_chunks {
		chunks[coordinate] = bytes
	}
	for coordinate, chunk in world.chunks {
		if chunk.modified {
			chunks[coordinate] = serialize_chunk(chunk, context.temp_allocator)
		}
	}
	return chunks
}

// Chunks by region, each region's in coordinate order, in the temp
// allocator.
group_chunks_by_region :: proc(chunks: map[Chunk_Coordinate][]byte) -> map[Region_Coordinate][dynamic]Saved_Chunk {
	regions := make(map[Region_Coordinate][dynamic]Saved_Chunk, context.temp_allocator)
	for coordinate, bytes in chunks {
		region := chunk_region(coordinate)
		if region not_in regions {
			regions[region] = make([dynamic]Saved_Chunk, context.temp_allocator)
		}
		append(&regions[region], Saved_Chunk{coordinate = coordinate, bytes = bytes})
	}
	for _, &list in regions {
		slice.sort_by(list[:], saved_chunk_before)
	}
	return regions
}

// Header, region x and z, a u32 chunk count, then per chunk its x, y and
// z, a u32 byte length and the chunk bytes (world_serialize.odin).
encode_region :: proc(header: Save_Header, region: Region_Coordinate, chunks: []Saved_Chunk, allocator := context.allocator) -> []byte {
	bytes := make([dynamic]byte, allocator)
	append_save_header(&bytes, REGION_FILE_MAGIC, header)
	append_u32(&bytes, u32(region.x))
	append_u32(&bytes, u32(region.y))
	append_u32(&bytes, u32(len(chunks)))
	for chunk in chunks {
		for axis in 0 ..< 3 {
			append_u32(&bytes, u32(chunk.coordinate[axis]))
		}
		append_u32(&bytes, u32(len(chunk.bytes)))
		append(&bytes, ..chunk.bytes)
	}
	return bytes[:]
}

read_saved_chunk :: proc(reader: ^Byte_Reader) -> (chunk: Saved_Chunk, ok: bool) {
	for axis in 0 ..< 3 {
		chunk.coordinate[axis] = i32(read_u32(reader) or_return)
	}
	length := int(read_u32(reader) or_return)
	if length > bytes_left(reader^) {
		return {}, false
	}
	chunk.bytes = reader.data[reader.offset:][:length]
	reader.offset += length
	return chunk, true
}

// Checks every chunk (its region, that it decodes, that it appears once)
// and adds copies of the bytes to chunks, their palettes remapped to this
// build's block ids (nil remap: as written). Header problems are reported
// by the caller, a vanished block through remap.gone_chunk_block.
decode_region :: proc(data: []byte, region: Region_Coordinate, chunks: ^map[Chunk_Coordinate][]byte, remap: ^Content_Remap) -> (header: Save_Header, ok: bool) {
	reader := Byte_Reader {
		data = data,
	}
	header = read_save_header(&reader, REGION_FILE_MAGIC) or_return
	stored_region := Region_Coordinate{i32(read_u32(&reader) or_return), i32(read_u32(&reader) or_return)}
	count := int(read_u32(&reader) or_return)
	if stored_region != region {
		return header, false
	}
	scratch := new([CHUNK_BLOCK_COUNT]Block_Id, context.temp_allocator)
	for _ in 0 ..< count {
		chunk := read_saved_chunk(&reader) or_return
		if chunk_region(chunk.coordinate) != region || chunk.coordinate in chunks || !deserialize_chunk_blocks(chunk.bytes, scratch) {
			return header, false
		}
		bytes := slice.clone(chunk.bytes)
		if !remap_chunk_palette(bytes, remap) {
			delete(bytes)
			return header, false
		}
		chunks[chunk.coordinate] = bytes
	}
	return header, bytes_left(reader) == 0
}

// Writing.

Region_File :: struct {
	name:  string,
	bytes: []byte,
}

// The file contents of a save, in the temp allocator.
Save_Files :: struct {
	world:    []byte,
	entities: []byte,
	regions:  [dynamic]Region_File,
}

encode_save_files :: proc(state: ^Simulation_State, content: Simulation_Content, display_name: string, last_played_unix_seconds: i64) -> Save_Files {
	header := make_save_header()
	entities := make([dynamic]byte, context.temp_allocator)
	append_save_header(&entities, ENTITIES_FILE_MAGIC, header)
	append_content_tables(&entities, content_tables(content))
	write_simulation_state(&entities, state)
	files := Save_Files {
		world    = encode_world_file(make_world_file(state, display_name, last_played_unix_seconds), context.temp_allocator),
		entities = entities[:],
		regions  = make([dynamic]Region_File, context.temp_allocator),
	}
	for region, chunks in group_chunks_by_region(collect_saved_chunks(&state.world)) {
		append(&files.regions, Region_File{name = region_file_name(region), bytes = encode_region(header, region, chunks[:], context.temp_allocator)})
	}
	return files
}

write_save_files :: proc(directory: string, files: Save_Files) -> os.Error {
	if os.exists(directory) {
		os.remove_all(directory) or_return
	}
	regions := join_save_path(directory, REGIONS_DIRECTORY_NAME)
	os.make_directory_all(regions) or_return
	os.write_entire_file(join_save_path(directory, WORLD_FILE_NAME), files.world) or_return
	os.write_entire_file(join_save_path(directory, ENTITIES_FILE_NAME), files.entities) or_return
	for region in files.regions {
		os.write_entire_file(join_save_path(regions, region.name), region.bytes) or_return
	}
	return nil
}

// Moves the staged save into place, keeping the old one aside until the
// new one is there.
swap_in_save :: proc(target, staging, previous: string) -> os.Error {
	if os.exists(previous) {
		os.remove_all(previous) or_return
	}
	if os.exists(target) {
		os.rename(target, previous) or_return
	}
	os.rename(staging, target) or_return
	if os.exists(previous) {
		os.remove_all(previous) or_return
	}
	return nil
}

// Writes the whole world. The caller runs it between ticks, so the
// simulation is paused for the write. Returns an empty string on success,
// otherwise the problem.
save_world :: proc(state: ^Simulation_State, content: Simulation_Content, location: Save_Location, last_played_unix_seconds: i64) -> string {
	refresh_loaded_surfaces(&state.world)
	files := encode_save_files(state, content, location.display_name, last_played_unix_seconds)
	target := join_save_path(location.saves_directory, location.directory_name)
	staging := strings.concatenate({target, STAGING_DIRECTORY_SUFFIX}, context.temp_allocator)
	previous := strings.concatenate({target, PREVIOUS_DIRECTORY_SUFFIX}, context.temp_allocator)
	if error := write_save_files(staging, files); error != nil {
		return fmt.tprintf("cannot write %s: %v", staging, error)
	}
	if error := swap_in_save(target, staging, previous); error != nil {
		return fmt.tprintf("cannot move %s into place: %v", staging, error)
	}
	return ""
}

// Loading.

header_problem :: proc(header, expected: Save_Header, file: string) -> string {
	if header.version != expected.version {
		return fmt.tprintf("%s has format version %d, this build reads %d", file, header.version, expected.version)
	}
	return ""
}

// Reads only the header and the content tables of the entities file, for
// the save list: the problem load_entities_file would report for them, or
// an empty string.
entities_header_problem :: proc(directory: string, expected: Save_Header) -> string {
	path := join_save_path(directory, ENTITIES_FILE_NAME)
	file, open_error := os.open(path)
	if open_error != nil {
		return fmt.tprintf("cannot read %s: %v", path, open_error)
	}
	defer os.close(file)
	buffer: [len(ENTITIES_FILE_MAGIC) + SAVE_HEADER_FIELDS_SIZE + size_of(u32)]byte
	count, _ := os.read_full(file, buffer[:])
	reader := Byte_Reader {
		data = buffer[:count],
	}
	header, header_ok := read_save_header(&reader, ENTITIES_FILE_MAGIC)
	if !header_ok {
		return fmt.tprintf("%s is not an entities file", path)
	}
	if problem := header_problem(header, expected, path); problem != "" {
		return problem
	}
	if !entities_tables_parse(file, buffer[count - bytes_left(reader):count]) {
		return fmt.tprintf("%s is malformed or truncated", path)
	}
	return ""
}

// length_bytes is the tables' u32 length, read already; the file stands
// right after it.
entities_tables_parse :: proc(file: ^os.File, length_bytes: []byte) -> bool {
	length_reader := Byte_Reader {
		data = length_bytes,
	}
	length := int(read_u32(&length_reader) or_return)
	if length > MAXIMUM_CONTENT_TABLES_BYTES {
		return false
	}
	section := make([dynamic]byte, 0, size_of(u32) + length, context.temp_allocator)
	append(&section, ..length_bytes)
	resize(&section, size_of(u32) + length)
	count, _ := os.read_full(file, section[size_of(u32):])
	if count != length {
		return false
	}
	reader := Byte_Reader {
		data = section[:],
	}
	_, ok := read_content_tables(&reader)
	return ok
}

// remap receives the content remap of the file, which the region files
// need.
load_entities_file :: proc(state: ^Simulation_State, content: Simulation_Content, directory: string, expected: Save_Header, remap: ^Content_Remap) -> string {
	path := join_save_path(directory, ENTITIES_FILE_NAME)
	data, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		return fmt.tprintf("cannot read %s: %v", path, error)
	}
	reader := Byte_Reader {
		data = data,
	}
	header, header_ok := read_save_header(&reader, ENTITIES_FILE_MAGIC)
	if !header_ok {
		return fmt.tprintf("%s is not an entities file", path)
	}
	if problem := header_problem(header, expected, path); problem != "" {
		return problem
	}
	saved_tables, tables_ok := read_content_tables(&reader)
	if !tables_ok {
		return fmt.tprintf("%s is malformed or truncated", path)
	}
	remap^ = make_content_remap(saved_tables, content_tables(content))
	reader.remap = remap
	if !read_simulation_state(&reader, state, content) {
		if reader.problem != "" {
			return fmt.tprintf("%s cannot be loaded: %s", path, reader.problem)
		}
		return fmt.tprintf("%s is malformed or truncated", path)
	}
	return ""
}

load_region_file :: proc(world: ^World, path, name: string, expected: Save_Header, remap: ^Content_Remap) -> string {
	region, named := parse_region_file_name(name)
	if !named {
		return fmt.tprintf("unexpected file %s", path)
	}
	data, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		return fmt.tprintf("cannot read %s: %v", path, error)
	}
	header, ok := decode_region(data, region, &world.saved_chunks, remap)
	if problem := header_problem(header, expected, path); problem != "" {
		return problem
	}
	if remap.gone_chunk_block != "" {
		return fmt.tprintf("%s cannot be loaded: a saved chunk holds the block %s, which this build's game data no longer has", path, remap.gone_chunk_block)
	}
	if !ok {
		return fmt.tprintf("%s is malformed or truncated", path)
	}
	return ""
}

load_region_files :: proc(world: ^World, directory: string, expected: Save_Header, remap: ^Content_Remap) -> string {
	regions := join_save_path(directory, REGIONS_DIRECTORY_NAME)
	if !os.exists(regions) {
		return ""
	}
	entries, error := os.read_all_directory_by_path(regions, context.temp_allocator)
	if error != nil {
		return fmt.tprintf("cannot list %s: %v", regions, error)
	}
	for entry in entries {
		if problem := load_region_file(world, entry.fullpath, entry.name, expected, remap); problem != "" {
			return problem
		}
	}
	return ""
}

// Reads a save into a simulation made for it: make_simulation with the
// file's seed and settings, before any chunk is loaded. Saved chunks go
// to World.saved_chunks, where streaming picks them up. Returns an empty
// string on success, otherwise the problem.
load_world :: proc(state: ^Simulation_State, content: Simulation_Content, directory: string, file: World_File) -> string {
	expected := make_save_header()
	state.tick = file.tick
	state.day_length_ticks = u64(file.settings.day_length_seconds) * u64(max(state.tick_rate, 1))
	state.day_offset_ticks = day_offset_for(file.tick, file.day_time_ticks, state.day_length_ticks)
	state.world.settings = world_settings_from_file(file.seed, file.settings)
	remap: Content_Remap
	if problem := load_entities_file(state, content, directory, expected, &remap); problem != "" {
		return problem
	}
	return load_region_files(&state.world, directory, expected, &remap)
}

// A simulation made the way a new world is made (make_simulation with the
// saved seed and settings), then given the saved state. The generator the
// chunks stream from must use file.seed and the landing pad of that seed.
make_simulation_from_save :: proc(config: Game_Config, player: Player_Start, content: Simulation_Content, landing_pad: Landing_Pad_Site, directory: string, file: World_File) -> (state: Simulation_State, problem: string) {
	state = make_simulation(config, player, content, content.technologies, file.settings.all_recipes_unlocked, landing_pad)
	problem = load_world(&state, content, directory, file)
	return state, problem
}
