package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "generation_seed"
import "platform"
import "sjson_text"

// Procedural block textures (work item 0099). A block listed in
// data/textures/procedural.sjson gets its tile from a generator and its
// parameters instead of a file: the ores so far. Everything here is pure:
// the same parameters and colours give the same pixels, with no clock and
// no global state. The generator works on the torus (every neighbour
// lookup wraps at the tile's edge), so every texel sees the same
// statistics and no blob prefers the edge.
//
// An ore tile: white noise from a hash of the seed and the texel (constant
// over crystal_size by crystal_size cells), blurred by a round Gaussian of
// blob_width texels; the share of texels with the highest values are the
// blobs, in the ore's colour with its own grain, the rest is stone with a
// grain and a mottle; stone texels next to a blob are darkened by
// rim_strength, an outline that gives the blobs depth.

TEXTURES_DIRECTORY :: "textures"
PROCEDURAL_TEXTURES_FILE_NAME :: "procedural.sjson"
// Under the state directory (logging.odin); the editor (work item 0100)
// writes it, the loader reads it over the data file.
TEXTURE_EDITS_FILE_NAME :: "texture_edits.sjson"
// The block whose side colour is the ground of every ore tile.
ORE_GROUND_BLOCK :: "stone"

TEXTURE_TEXEL_COUNT :: ATLAS_TILE_SIZE * ATLAS_TILE_SIZE
// The standard deviation, in texels, of the stone's mottle.
STONE_MOTTLE_WIDTH :: 1.5
// A Gaussian reaches three standard deviations; this caps the kernel.
BLUR_REACH_LIMIT :: 12
BLUR_KERNEL_LENGTH :: 2 * BLUR_REACH_LIMIT + 1

Tile_Field :: [TEXTURE_TEXEL_COUNT]f32
Tile_Mask :: [TEXTURE_TEXEL_COUNT]bool

Ore_Texture_Parameters :: struct {
	seed:         int,
	// The fraction of texels in blobs.
	share:        f32,
	// The blur's standard deviation in texels: wider is fewer, larger blobs.
	blob_width:   f32,
	// The white noise is constant over cells of this many texels a side:
	// 1 gives round blobs, 2 and more blocky ones.
	crystal_size: int,
	// Per texel brightness offsets, up to this much either way.
	stone_grain:  int,
	// A smooth brightness offset over the stone, up to this much either way.
	stone_mottle: int,
	ore_grain:    int,
	// The fraction by which stone next to a blob is darkened.
	rim_strength: f32,
}

// The parameters in file order; the schema the parser checks and the
// editor's sliders follow.
Ore_Texture_Parameter :: enum u8 {
	Seed,
	Share,
	Blob_Width,
	Crystal_Size,
	Stone_Grain,
	Stone_Mottle,
	Ore_Grain,
	Rim_Strength,
}

Texture_Parameter_Range :: struct {
	key:     string,
	minimum: f64,
	maximum: f64,
	step:    f64,
	// Whole numbers only.
	whole:   bool,
}

@(rodata)
ore_texture_parameter_ranges := [Ore_Texture_Parameter]Texture_Parameter_Range {
	.Seed         = {"seed", 0, 2147483647, 1, true},
	.Share        = {"share", 0.05, 0.5, 0.01, false},
	.Blob_Width   = {"blob_width", 0.3, 3, 0.05, false},
	.Crystal_Size = {"crystal_size", 1, 4, 1, true},
	.Stone_Grain  = {"stone_grain", 0, 32, 1, true},
	.Stone_Mottle = {"stone_mottle", 0, 48, 1, true},
	.Ore_Grain    = {"ore_grain", 0, 48, 1, true},
	.Rim_Strength = {"rim_strength", 0, 0.8, 0.05, false},
}

ore_texture_parameter :: proc(parameters: Ore_Texture_Parameters, parameter: Ore_Texture_Parameter) -> f64 {
	switch parameter {
	case .Seed:
		return f64(parameters.seed)
	case .Share:
		return f64(parameters.share)
	case .Blob_Width:
		return f64(parameters.blob_width)
	case .Crystal_Size:
		return f64(parameters.crystal_size)
	case .Stone_Grain:
		return f64(parameters.stone_grain)
	case .Stone_Mottle:
		return f64(parameters.stone_mottle)
	case .Ore_Grain:
		return f64(parameters.ore_grain)
	case .Rim_Strength:
		return f64(parameters.rim_strength)
	}
	return 0
}

set_ore_texture_parameter :: proc(parameters: ^Ore_Texture_Parameters, parameter: Ore_Texture_Parameter, value: f64) {
	switch parameter {
	case .Seed:
		parameters.seed = int(value)
	case .Share:
		parameters.share = f32(value)
	case .Blob_Width:
		parameters.blob_width = f32(value)
	case .Crystal_Size:
		parameters.crystal_size = int(value)
	case .Stone_Grain:
		parameters.stone_grain = int(value)
	case .Stone_Mottle:
		parameters.stone_mottle = int(value)
	case .Ore_Grain:
		parameters.ore_grain = int(value)
	case .Rim_Strength:
		parameters.rim_strength = f32(value)
	}
}

// Independent noises drawn from one seed.
Texture_Noise_Stream :: enum u64 {
	Blob,
	Stone_Grain,
	Stone_Mottle,
	Ore_Grain,
}

// In [0, 1), fixed by the seed, the stream and the texel.
texture_noise_unit :: proc(seed: int, stream: Texture_Noise_Stream, x, y: int) -> f32 {
	stream_key := generation_seed.hash_u64(u64(seed) ~ (u64(stream) << 48))
	return f32(generation_seed.hash_u64(stream_key ~ (u64(y) << 16) ~ u64(x)) >> 40) / (1 << 24)
}

// In [-1, 1).
texture_noise_signed :: proc(seed: int, stream: Texture_Noise_Stream, x, y: int) -> f32 {
	return texture_noise_unit(seed, stream, x, y) * 2 - 1
}

texel_index :: proc(x, y: int) -> int {
	return y * ATLAS_TILE_SIZE + x
}

// A coordinate brought back onto the tile, as on a torus.
wrap_texel :: proc(coordinate: int) -> int {
	return (coordinate % ATLAS_TILE_SIZE + ATLAS_TILE_SIZE) % ATLAS_TILE_SIZE
}

// Constant over cells of cell_size texels; a size that does not divide
// the tile leaves one narrower row and column of cells.
white_noise_field :: proc(seed: int, stream: Texture_Noise_Stream, cell_size: int) -> (field: Tile_Field) {
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			field[texel_index(x, y)] = texture_noise_unit(seed, stream, x / cell_size, y / cell_size)
		}
	}
	return field
}

Blur_Kernel :: struct {
	// Normalised, weights[reach] is the centre.
	weights: [BLUR_KERNEL_LENGTH]f32,
	reach:   int,
}

gaussian_kernel :: proc(width: f32) -> (kernel: Blur_Kernel) {
	kernel.reach = min(int(math.ceil(3 * width)), BLUR_REACH_LIMIT)
	total: f32
	for offset in -kernel.reach ..= kernel.reach {
		weight := math.exp(-f32(offset * offset) / (2 * width * width))
		kernel.weights[offset + kernel.reach] = weight
		total += weight
	}
	for &weight in kernel.weights[:2 * kernel.reach + 1] {
		weight /= total
	}
	return kernel
}

// One pass of the separable blur along x or y, wrapping at the edge.
blur_axis_on_torus :: proc(field: Tile_Field, kernel: Blur_Kernel, along_x: bool) -> (blurred: Tile_Field) {
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			total: f32
			for offset in -kernel.reach ..= kernel.reach {
				source := along_x ? texel_index(wrap_texel(x + offset), y) : texel_index(x, wrap_texel(y + offset))
				total += kernel.weights[offset + kernel.reach] * field[source]
			}
			blurred[texel_index(x, y)] = total
		}
	}
	return blurred
}

// A round Gaussian blur of width texels (its standard deviation) on the
// torus: the tile's left neighbour of x 0 is x 15.
blur_on_torus :: proc(field: Tile_Field, width: f32) -> Tile_Field {
	kernel := gaussian_kernel(width)
	return blur_axis_on_torus(blur_axis_on_torus(field, kernel, true), kernel, false)
}

Ranked_Texel :: struct {
	value: f32,
	index: int,
}

// Highest value first, ties by index, so the order is total.
ranked_texel_before :: proc(first, second: Ranked_Texel) -> bool {
	if first.value != second.value {
		return first.value > second.value
	}
	return first.index < second.index
}

// The share of texels with the highest values, exactly share times the
// texel count, rounded.
blob_mask :: proc(field: Tile_Field, share: f32) -> (mask: Tile_Mask) {
	ranked: [TEXTURE_TEXEL_COUNT]Ranked_Texel
	for value, index in field {
		ranked[index] = {value, index}
	}
	slice.sort_by(ranked[:], ranked_texel_before)
	count := clamp(int(math.round(share * TEXTURE_TEXEL_COUNT)), 0, TEXTURE_TEXEL_COUNT)
	for texel in ranked[:count] {
		mask[texel.index] = true
	}
	return mask
}

// Texels outside the blobs with a blob among their four neighbours on
// the torus.
rim_mask :: proc(blobs: Tile_Mask) -> (rim: Tile_Mask) {
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			index := texel_index(x, y)
			rim[index] = !blobs[index] && (blobs[texel_index(wrap_texel(x - 1), y)] || blobs[texel_index(wrap_texel(x + 1), y)] || blobs[texel_index(x, wrap_texel(y - 1))] || blobs[texel_index(x, wrap_texel(y + 1))])
		}
	}
	return rim
}

// Stretched to [-1, 1]; a flat field stays 0.
centered_field :: proc(field: Tile_Field) -> (centered: Tile_Field) {
	field := field
	lowest, highest := slice.min(field[:]), slice.max(field[:])
	if highest <= lowest {
		return centered
	}
	for value, index in field {
		centered[index] = (value - lowest) / (highest - lowest) * 2 - 1
	}
	return centered
}

// The colour shifted by offset, then scaled by factor, opaque.
shaded_texel :: proc(color: [3]u8, offset, factor: f32) -> [4]u8 {
	texel: [4]u8 = 255
	for channel in 0 ..< 3 {
		texel[channel] = u8(clamp(math.round((f32(color[channel]) + offset) * factor), 0, 255))
	}
	return texel
}

stone_texel :: proc(parameters: Ore_Texture_Parameters, stone: [3]u8, mottle: f32, on_rim: bool, x, y: int) -> [4]u8 {
	offset := texture_noise_signed(parameters.seed, .Stone_Grain, x, y) * f32(parameters.stone_grain) + mottle * f32(parameters.stone_mottle)
	return shaded_texel(stone, offset, on_rim ? 1 - parameters.rim_strength : 1)
}

ore_texel :: proc(parameters: Ore_Texture_Parameters, ore: [3]u8, x, y: int) -> [4]u8 {
	return shaded_texel(ore, texture_noise_signed(parameters.seed, .Ore_Grain, x, y) * f32(parameters.ore_grain), 1)
}

generate_ore_tile :: proc(parameters: Ore_Texture_Parameters, stone, ore: [3]u8) -> (tile: Tile_Pixels) {
	blob_field := blur_on_torus(white_noise_field(parameters.seed, .Blob, max(parameters.crystal_size, 1)), parameters.blob_width)
	blobs := blob_mask(blob_field, parameters.share)
	rim := rim_mask(blobs)
	mottle := centered_field(blur_on_torus(white_noise_field(parameters.seed, .Stone_Mottle, 1), STONE_MOTTLE_WIDTH))
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			index := texel_index(x, y)
			tile[index] = blobs[index] ? ore_texel(parameters, ore, x, y) : stone_texel(parameters, stone, mottle[index], rim[index], x, y)
		}
	}
	return tile
}

// The data file.

Procedural_Texture_Kind :: enum u8 {
	Ore,
}

@(rodata)
procedural_texture_kind_names := [Procedural_Texture_Kind]string {
	.Ore = "ore",
}

Procedural_Texture :: struct {
	block:      Block_Id,
	kind:       Procedural_Texture_Kind,
	parameters: Ore_Texture_Parameters,
}

find_procedural_texture_kind :: proc(name: string) -> (kind: Procedural_Texture_Kind, found: bool) {
	for candidate_name, candidate in procedural_texture_kind_names {
		if candidate_name == name {
			return candidate, true
		}
	}
	return {}, false
}

is_procedural_texture_key :: proc(key: string) -> bool {
	if key == "block" || key == "kind" {
		return true
	}
	for range in ore_texture_parameter_ranges {
		if range.key == key {
			return true
		}
	}
	return false
}

parse_texture_parameter :: proc(object: json.Object, range: Texture_Parameter_Range) -> (value: f64, problem: string) {
	raw, present := object[range.key]
	if !present {
		return 0, fmt.tprintf("has no %s", range.key)
	}
	if range.whole {
		integer, is_integer := raw.(json.Integer)
		if !is_integer {
			return 0, fmt.tprintf("%s must be a whole number, not %s", range.key, json_type_name(raw))
		}
		value = f64(integer)
	} else {
		is_number: bool
		value, is_number = json_number(raw)
		if !is_number {
			return 0, fmt.tprintf("%s must be a number, not %s", range.key, json_type_name(raw))
		}
	}
	if value < range.minimum || value > range.maximum {
		return 0, fmt.tprintf("%s is %v, outside %v to %v", range.key, value, range.minimum, range.maximum)
	}
	return value, ""
}

parse_procedural_block :: proc(object: json.Object, registry: Block_Registry) -> (block: Block_Id, problem: string) {
	name, is_string := object["block"].(json.String)
	if !is_string {
		return AIR_BLOCK, "block must be a block id"
	}
	found: bool
	if block, found = find_block_id(registry, name); !found {
		return AIR_BLOCK, fmt.tprintf("unknown block %s", name)
	}
	return block, ""
}

parse_procedural_kind :: proc(object: json.Object) -> (kind: Procedural_Texture_Kind, problem: string) {
	name, is_string := object["kind"].(json.String)
	if !is_string {
		return {}, "kind must be a string"
	}
	found: bool
	if kind, found = find_procedural_texture_kind(name); !found {
		return {}, fmt.tprintf("unknown kind %s (expected ore)", name)
	}
	return kind, ""
}

parse_procedural_texture :: proc(value: json.Value, registry: Block_Registry) -> (entry: Procedural_Texture, problem: string) {
	object, is_object := value.(json.Object)
	if !is_object {
		return {}, fmt.tprintf("must be an object, not %s", json_type_name(value))
	}
	for key in sjson_text.sorted_object_keys(object) {
		if !is_procedural_texture_key(key) {
			return {}, fmt.tprintf("unknown key %s", key)
		}
	}
	if entry.block, problem = parse_procedural_block(object, registry); problem != "" {
		return {}, problem
	}
	if entry.kind, problem = parse_procedural_kind(object); problem != "" {
		return {}, problem
	}
	for parameter in Ore_Texture_Parameter {
		parameter_value: f64
		if parameter_value, problem = parse_texture_parameter(object, ore_texture_parameter_ranges[parameter]); problem != "" {
			return {}, problem
		}
		set_ore_texture_parameter(&entry.parameters, parameter, parameter_value)
	}
	return entry, ""
}

// " (<block>)" when the entry names one, for the problem line.
procedural_entry_label :: proc(value: json.Value) -> string {
	object, is_object := value.(json.Object)
	if !is_object {
		return ""
	}
	if name, is_string := object["block"].(json.String); is_string {
		return fmt.tprintf(" (%s)", name)
	}
	return ""
}

find_procedural_texture :: proc(entries: []Procedural_Texture, block: Block_Id) -> (entry: Procedural_Texture, found: bool) {
	for candidate in entries {
		if candidate.block == block {
			return candidate, true
		}
	}
	return {}, false
}

// textures = [{block = "<id>", kind = "ore", seed = <int>, ...}, ...].
// The problem names the source and the entry.
parse_procedural_textures :: proc(data: []byte, source: string, registry: Block_Registry, allocator := context.allocator) -> (entries: []Procedural_Texture, problem: string) {
	tree: json.Object
	if tree, problem = parse_configuration_layer(data, source, context.temp_allocator); problem != "" {
		return nil, problem
	}
	for key in sjson_text.sorted_object_keys(tree) {
		if key != "textures" {
			return nil, fmt.tprintf("%s: unknown key %s", source, key)
		}
	}
	if _, found := find_block_id(registry, ORE_GROUND_BLOCK); !found {
		return nil, fmt.tprintf("%s: the blocks have no %s for the ore tiles' ground", source, ORE_GROUND_BLOCK)
	}
	list, is_array := tree["textures"].(json.Array)
	if !is_array {
		return nil, fmt.tprintf("%s: textures must be an array", source)
	}
	parsed := make([dynamic]Procedural_Texture, 0, len(list), allocator)
	for value, index in list {
		entry, entry_problem := parse_procedural_texture(value, registry)
		if entry_problem == "" {
			if _, duplicate := find_procedural_texture(parsed[:], entry.block); duplicate {
				entry_problem = "the block is listed twice"
			}
		}
		if entry_problem != "" {
			delete(parsed)
			return nil, fmt.tprintf("%s: entry %d%s: %s", source, index + 1, procedural_entry_label(value), entry_problem)
		}
		append(&parsed, entry)
	}
	return parsed[:], ""
}

// The overrides replace the base's entry for their block, or add one.
merge_procedural_textures :: proc(base, overrides: []Procedural_Texture, allocator := context.allocator) -> []Procedural_Texture {
	merged := make([dynamic]Procedural_Texture, 0, len(base) + len(overrides), allocator)
	for entry in base {
		override, found := find_procedural_texture(overrides, entry.block)
		append(&merged, found ? override : entry)
	}
	for override in overrides {
		if _, found := find_procedural_texture(base, override.block); !found {
			append(&merged, override)
		}
	}
	return merged[:]
}

// found is false for a missing file. In the temp allocator.
read_procedural_textures_file :: proc(path: string, registry: Block_Registry) -> (entries: []Procedural_Texture, found: bool, problem: string) {
	if !os.exists(path) {
		return nil, false, ""
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		return nil, true, fmt.tprintf("%s: cannot read: %v", path, read_error)
	}
	entries, problem = parse_procedural_textures(data, path, registry, context.temp_allocator)
	return entries, true, problem
}

// The data file, through the data edits overlay (read_data_file). found
// is false for a missing file. In the temp allocator.
read_procedural_textures_data_file :: proc(data_directory: string, registry: Block_Registry) -> (entries: []Procedural_Texture, path: string, found: bool, problem: string) {
	data: []byte
	read_error: os.Error
	data, path, read_error = read_data_file(data_directory, TEXTURES_DIRECTORY + "/" + PROCEDURAL_TEXTURES_FILE_NAME, context.temp_allocator)
	if read_error == .Not_Exist {
		return nil, path, false, ""
	}
	if read_error != nil {
		return nil, path, true, fmt.tprintf("%s: cannot read: %v", path, read_error)
	}
	entries, problem = parse_procedural_textures(data, path, registry, context.temp_allocator)
	return entries, path, true, problem
}

// $XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson. In the given
// allocator.
texture_edits_path_from_environment :: proc(state_home, home: string, allocator := context.allocator) -> (path: string, ok: bool) {
	state_directory := platform.log_directory_from_environment(state_home, home, context.temp_allocator) or_return
	joined, error := os.join_path({state_directory, TEXTURE_EDITS_FILE_NAME}, allocator)
	return joined, error == nil
}

// The data file's entries with the edits file's over them, in the temp
// allocator. A file that does not load is logged and left out: without
// the data file the ores fall back to files or their colour, without the
// edits file the data file's entries stand. edits_path "" reads no edits.
load_procedural_textures :: proc(data_directory, edits_path: string, registry: Block_Registry) -> []Procedural_Texture {
	base, data_path, base_found, base_problem := read_procedural_textures_data_file(data_directory, registry)
	if base_problem != "" {
		platform.log_printf("error: %s, the procedural textures are left out", base_problem)
	} else if !base_found {
		platform.log_printf("error: %s is missing, the procedural textures are left out", data_path)
	}
	if edits_path == "" {
		return base
	}
	edits, _, edits_problem := read_procedural_textures_file(edits_path, registry)
	if edits_problem != "" {
		platform.log_printf("error: %s, the texture edits are ignored", edits_problem)
		return base
	}
	return merge_procedural_textures(base, edits, context.temp_allocator)
}

// The tile of the block's entry, nil for a block without one.
generate_procedural_tile :: proc(entries: []Procedural_Texture, registry: Block_Registry, block: Block_Id) -> Maybe(Tile_Pixels) {
	entry, found := find_procedural_texture(entries, block)
	if !found {
		return nil
	}
	ground, _ := find_block_id(registry, ORE_GROUND_BLOCK)
	switch entry.kind {
	case .Ore:
		return generate_ore_tile(entry.parameters, registry.definitions[ground].texture.side, registry.definitions[block].texture.side)
	}
	return nil
}

// The overrides writer (the texture editor, work item 0100): entries in
// the data file's form, so a line copies into
// data/textures/procedural.sjson as it is.

// Whole numbers 0, else the decimals of the step: 2 for 0.01 and 0.05.
texture_parameter_decimals :: proc(range: Texture_Parameter_Range) -> int {
	if range.whole {
		return 0
	}
	decimals := 0
	for scaled := range.step; decimals < 6 && abs(scaled - math.round(scaled)) > 1e-9; scaled *= 10 {
		decimals += 1
	}
	return decimals
}

// On the step's grid inside the range, rounded to the step's decimals, so
// the value prints and parses back to the same f32.
snapped_texture_parameter :: proc(range: Texture_Parameter_Range, value: f64) -> f64 {
	steps := math.round((value - range.minimum) / range.step)
	snapped := clamp(range.minimum + steps * range.step, range.minimum, range.maximum)
	scale := math.pow(10, f64(texture_parameter_decimals(range)))
	return math.round(snapped * scale) / scale
}

// "1101", "0.2", "0.65": the step's decimals without trailing zeros. In
// the temp allocator.
format_texture_parameter_value :: proc(range: Texture_Parameter_Range, value: f64) -> string {
	if range.whole {
		return fmt.tprintf("%d", i64(math.round(value)))
	}
	text := fmt.tprintf(fmt.tprintf("%%.%df", texture_parameter_decimals(range)), value)
	if strings.contains_rune(text, '.') {
		text = strings.trim_right(text, "0")
		text = strings.trim_right(text, ".")
	}
	return text
}

// {block = "<id>", kind = "ore", seed = <int>, ...} in file order. In the
// temp allocator.
format_procedural_texture_entry :: proc(block_name: string, kind: Procedural_Texture_Kind, parameters: Ore_Texture_Parameters) -> string {
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "{{block = %q, kind = %q", block_name, procedural_texture_kind_names[kind])
	for parameter in Ore_Texture_Parameter {
		range := ore_texture_parameter_ranges[parameter]
		fmt.sbprintf(&builder, ", %s = %s", range.key, format_texture_parameter_value(range, ore_texture_parameter(parameters, parameter)))
	}
	strings.write_string(&builder, "}")
	return strings.to_string(builder)
}

// The overrides file around entry lines. In the temp allocator.
format_texture_edits_file :: proc(entry_lines: []string) -> string {
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "// Written by the texture editor (work item 0100). Each entry replaces\n")
	strings.write_string(&builder, "// data/textures/procedural.sjson's entry for its block; copy an entry\n")
	strings.write_string(&builder, "// there to make it the default, then delete this file.\n")
	strings.write_string(&builder, "textures = [\n")
	for line in entry_lines {
		fmt.sbprintf(&builder, "\t%s\n", line)
	}
	strings.write_string(&builder, "]\n")
	return strings.to_string(builder)
}

// Returns the problem, or an empty string. Makes the state directory.
write_texture_edits_file :: proc(path, text: string) -> string {
	return platform.write_file_replacing(path, transmute([]byte)text)
}
