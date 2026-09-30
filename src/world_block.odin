package game

import "core:encoding/json"
import "core:fmt"
import "platform"

BLOCKS_FILE_NAME :: "blocks.sjson"
AIR_BLOCK_NAME :: "air"

// Dense index into Block_Registry.definitions, resolved once at load.
Block_Id :: distinct u16

AIR_BLOCK :: Block_Id(0)

Face_Group :: enum u8 {
	Top,
	Side,
	Bottom,
}

FACE_GROUP_COUNT :: len(Face_Group)

// The geometry of a block (block_shape.odin). A cube is meshed greedily,
// every other shape from its own quads. Slabs and stairs are oriented:
// the loader expands them into one block per orientation
// (expand_block_shapes).
Block_Shape :: enum u8 {
	Cube,
	Slab,
	Stairs,
	Post,
	Cross,
}

@(rodata)
block_shape_names := [Block_Shape]string {
	.Cube   = "cube",
	.Slab   = "slab",
	.Stairs = "stairs",
	.Post   = "post",
	.Cross  = "cross",
}

// rotation is in quarter turns like every rotation in the game
// (belt_direction_offset): stairs of rotation 0 rise towards +x. upper
// is a slab filling the upper half of its cell.
Block_Orientation :: struct {
	rotation: u8,
	upper:    bool,
}

Block_Texture_Definition :: struct {
	top:    [3]u8,
	side:   [3]u8,
	bottom: [3]u8,
}

// hardness_seconds is the hand mining time, 0 for blocks that cannot be
// mined. light_level is the block light emitted (0 to MAXIMUM_LIGHT);
// light_color, optional, gives its colour as red, green and blue levels
// (0 to MAXIMUM_LIGHT each, the largest equal to light_level), white at
// light_level when left out (work item 0072).
// water_level is 0 for everything but water, WATER_SOURCE_LEVEL for a
// source and 1 to WATER_SOURCE_LEVEL - 1 for flowing water. fluid_source
// names the fluid a source pump draws from the block (a tar pit gives
// crude oil), as a fluids.sjson id, or is empty. tool_tier is the
// pickaxe tier hand mining needs, 0 for hands (work item 0051).
// name_key is the display name in data/strings/en.sjson, required on
// every block but air. A discoverable block (the ores) reads "Unknown ore"
// until its drop item was obtained once (work item 0052); it must have a
// drop, which item_registry validation checks. shape names a Block_Shape,
// cube when empty; resolved_shape and orientation are set by
// expand_block_shapes, not read from the file. keep_orientation (work
// item 0088) keeps the tile of the block's side faces upright where the
// chunk shader would turn and mirror it per block (texture_variation.odin).
// framed (work item 0101) marks varying faces that are a picture rather
// than a periodic tile (the log ends): turned and mirrored, never slid.
Block_Definition :: struct {
	id:               string,
	name_key:         string,
	discoverable:     bool,
	solid:            bool,
	hardness_seconds: f32,
	light_level:      int,
	light_color:      [3]int,
	water_level:      int,
	fluid_source:     string,
	tool_tier:        int,
	texture:          Block_Texture_Definition,
	shape:            string,
	sound_material:   string,
	keep_orientation: bool,
	framed:           bool,
	resolved_shape:   Block_Shape,
	orientation:      Block_Orientation,
}

Blocks_File :: struct {
	blocks: []Block_Definition,
}

Block_Registry :: struct {
	definitions: []Block_Definition,
}

// The file's blocks with every oriented shape expanded into its variants.
parse_blocks_file :: proc(data: []byte, allocator := context.allocator) -> (file: Blocks_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	if error != nil {
		return
	}
	listed := file.blocks
	file.blocks = expand_block_shapes(listed, allocator)
	delete(listed, allocator)
	return
}

// An empty name is a cube.
parse_block_shape :: proc(name: string) -> (shape: Block_Shape, found: bool) {
	if name == "" {
		return .Cube, true
	}
	return parse_named_enum(block_shape_names, name)
}

// A slab has a bottom and an upper half, stairs four quarter turns.
shape_variant_count :: proc(shape: Block_Shape) -> int {
	#partial switch shape {
	case .Slab:
		return 2
	case .Stairs:
		return 4
	}
	return 1
}

variant_orientation :: proc(shape: Block_Shape, variant: int) -> Block_Orientation {
	#partial switch shape {
	case .Slab:
		return Block_Orientation{upper = variant == 1}
	case .Stairs:
		return Block_Orientation{rotation = u8(variant)}
	}
	return {}
}

// The inverse of variant_orientation: how far the variant follows its
// base block in the table.
variant_index :: proc(shape: Block_Shape, orientation: Block_Orientation) -> int {
	#partial switch shape {
	case .Slab:
		return int(orientation.upper)
	case .Stairs:
		return int(orientation.rotation % 4)
	}
	return 0
}

// "<id>_upper" for a slab's upper half, "<id>_r1" to "<id>_r3" for the
// stairs' quarter turns.
variant_block_id :: proc(base_id: string, shape: Block_Shape, variant: int, allocator := context.allocator) -> string {
	if shape == .Slab {
		return fmt.aprintf("%s_upper", base_id, allocator = allocator)
	}
	return fmt.aprintf("%s_r%d", base_id, variant, allocator = allocator)
}

// Each block followed by its variants: copies with the orientation set, an
// id of their own, the base block's name_key and never discoverable on
// their own. An unknown shape stays a cube here and fails validation.
expand_block_shapes :: proc(definitions: []Block_Definition, allocator := context.allocator) -> []Block_Definition {
	expanded := make([dynamic]Block_Definition, 0, len(definitions), allocator)
	for definition in definitions {
		shape, _ := parse_block_shape(definition.shape)
		for variant in 0 ..< shape_variant_count(shape) {
			copied := definition
			copied.resolved_shape = shape
			copied.orientation = variant_orientation(shape, variant)
			if variant > 0 {
				copied.id = variant_block_id(definition.id, shape, variant, allocator)
				copied.discoverable = false
			}
			append(&expanded, copied)
		}
	}
	return expanded[:]
}

// Returns an empty string when the definitions are valid, otherwise the problem.
validate_block_definitions :: proc(definitions: []Block_Definition) -> string {
	if len(definitions) == 0 || definitions[0].id != AIR_BLOCK_NAME {
		return fmt.tprintf("the first block must be %q", AIR_BLOCK_NAME)
	}
	if definitions[0].solid {
		return "air must not be solid"
	}
	if len(definitions) > int(max(Block_Id)) {
		return fmt.tprintf("%d blocks exceed the limit of %d", len(definitions), max(Block_Id))
	}
	for definition, index in definitions {
		if definition.id == "" {
			return fmt.tprintf("block %d has no id", index)
		}
		if first := find_definition_index(definitions, definition.id); first != index {
			return fmt.tprintf("block id %q is defined twice", definition.id)
		}
		if definition.hardness_seconds < 0 {
			return fmt.tprintf("block %q has a negative hardness_seconds", definition.id)
		}
		if definition.tool_tier < 0 {
			return fmt.tprintf("block %q has a negative tool_tier", definition.id)
		}
		if definition.light_level < 0 || definition.light_level > MAXIMUM_LIGHT {
			return fmt.tprintf("block %q has light_level %d outside 0 to %d", definition.id, definition.light_level, MAXIMUM_LIGHT)
		}
		if problem := validate_light_color(definition.light_color, definition.light_level); problem != "" {
			return fmt.tprintf("block %q %s", definition.id, problem)
		}
		if definition.water_level < 0 || definition.water_level > WATER_SOURCE_LEVEL {
			return fmt.tprintf("block %q has water_level %d outside 0 to %d", definition.id, definition.water_level, WATER_SOURCE_LEVEL)
		}
		if problem := validate_block_shape(definition); problem != "" {
			return problem
		}
	}
	return validate_water_levels(definitions)
}

// Slabs and stairs stop movement and water, posts and crosses do not.
validate_block_shape :: proc(definition: Block_Definition) -> string {
	shape, found := parse_block_shape(definition.shape)
	if !found {
		return fmt.tprintf("block %q has unknown shape %q", definition.id, definition.shape)
	}
	switch shape {
	case .Cube:
	case .Slab, .Stairs:
		if !definition.solid {
			return fmt.tprintf("block %q of shape %q must be solid", definition.id, definition.shape)
		}
	case .Post, .Cross:
		if definition.solid {
			return fmt.tprintf("block %q of shape %q must not be solid", definition.id, definition.shape)
		}
	}
	return ""
}

// Flow turns water of one level into another, so either every level has
// exactly one block or there is no water at all.
validate_water_levels :: proc(definitions: []Block_Definition) -> string {
	counts: [WATER_SOURCE_LEVEL + 1]int
	for definition in definitions {
		counts[definition.water_level] += 1
	}
	if counts[0] == len(definitions) {
		return ""
	}
	for level in 1 ..= WATER_SOURCE_LEVEL {
		if counts[level] != 1 {
			return fmt.tprintf("water_level %d needs exactly one block, found %d", level, counts[level])
		}
	}
	return ""
}

// Every block but air names itself through a key of the string table.
validate_block_name_keys :: proc(definitions: []Block_Definition, strings: map[string]string) -> string {
	for definition in definitions[1:] {
		if definition.name_key == "" {
			return fmt.tprintf("block %q has no name_key", definition.id)
		}
		if definition.name_key not_in strings {
			return fmt.tprintf("block %q: name_key %q is not in the string table", definition.id, definition.name_key)
		}
	}
	return ""
}

find_block_id :: proc(registry: Block_Registry, id: string) -> (block: Block_Id, found: bool) {
	index := find_definition_index(registry.definitions, id)
	if index < 0 {
		return AIR_BLOCK, false
	}
	return Block_Id(index), true
}

// The display name, "" for air and ids outside the registry. (The
// diagnostics overlay's block_name shows the id.)
block_display_name :: proc(registry: Block_Registry, block: Block_Id) -> string {
	if int(block) >= len(registry.definitions) || registry.definitions[block].name_key == "" {
		return ""
	}
	return text(registry.definitions[block].name_key)
}

block_is_discoverable :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	return int(block) < len(registry.definitions) && registry.definitions[block].discoverable
}

// Ids outside the registry count as not solid, so a malformed chunk cannot
// index past the table.
block_is_solid :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	if int(block) >= len(registry.definitions) {
		return false
	}
	return registry.definitions[block].solid
}

// Light passes through every block but solid cubes, so slabs, stairs,
// posts and crosses let it through.
block_is_opaque :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	if int(block) >= len(registry.definitions) {
		return false
	}
	return registry.definitions[block].solid && registry.definitions[block].resolved_shape == .Cube
}

// Cube outside the registry.
block_shape :: proc(registry: Block_Registry, block: Block_Id) -> Block_Shape {
	if int(block) >= len(registry.definitions) {
		return .Cube
	}
	return registry.definitions[block].resolved_shape
}

block_orientation :: proc(registry: Block_Registry, block: Block_Id) -> Block_Orientation {
	if int(block) >= len(registry.definitions) {
		return {}
	}
	return registry.definitions[block].orientation
}

// The block a variant was expanded from, the block itself for every other.
block_shape_base :: proc(registry: Block_Registry, block: Block_Id) -> Block_Id {
	return block - Block_Id(variant_index(block_shape(registry, block), block_orientation(registry, block)))
}

// The variant of block's base in the given orientation; a block without
// variants stays itself.
oriented_block :: proc(registry: Block_Registry, block: Block_Id, orientation: Block_Orientation) -> Block_Id {
	return block_shape_base(registry, block) + Block_Id(variant_index(block_shape(registry, block), orientation))
}

// False outside the registry.
block_keeps_orientation :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	if int(block) >= len(registry.definitions) {
		return false
	}
	return registry.definitions[block].keep_orientation
}

// False outside the registry.
block_is_framed :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	if int(block) >= len(registry.definitions) {
		return false
	}
	return registry.definitions[block].framed
}

block_light_emission :: proc(registry: Block_Registry, block: Block_Id) -> u8 {
	if int(block) >= len(registry.definitions) {
		return 0
	}
	return u8(registry.definitions[block].light_level)
}

// An unset light_color (all zero) is white at the level.
resolve_light_color :: proc(color: [3]int, level: int) -> Light_Color {
	if color == {} {
		return u8(level)
	}
	return {u8(color.r), u8(color.g), u8(color.b)}
}

// A light_color, when set, has every channel within 0 to MAXIMUM_LIGHT and
// its largest channel at light_level. Returns the problem, "" for none.
validate_light_color :: proc(color: [3]int, level: int) -> string {
	if color == {} {
		return ""
	}
	if min(color.r, color.g, color.b) < 0 || max(color.r, color.g, color.b) > MAXIMUM_LIGHT {
		return fmt.tprintf("has a light_color channel outside 0 to %d", MAXIMUM_LIGHT)
	}
	if max(color.r, color.g, color.b) != level {
		return fmt.tprintf("has a light_color whose largest channel %d is not its light_level %d", max(color.r, color.g, color.b), level)
	}
	return ""
}

// The colour of the block light a block emits, black for none.
block_light_color :: proc(registry: Block_Registry, block: Block_Id) -> Light_Color {
	if int(block) >= len(registry.definitions) {
		return {}
	}
	definition := registry.definitions[block]
	return resolve_light_color(definition.light_color, definition.light_level)
}

block_water_level :: proc(registry: Block_Registry, block: Block_Id) -> int {
	if int(block) >= len(registry.definitions) {
		return 0
	}
	return registry.definitions[block].water_level
}

block_fluid_source :: proc(registry: Block_Registry, block: Block_Id) -> string {
	if int(block) >= len(registry.definitions) {
		return ""
	}
	return registry.definitions[block].fluid_source
}

// The block holding water of this level, 1 to WATER_SOURCE_LEVEL.
water_block_for_level :: proc(registry: Block_Registry, level: int) -> (block: Block_Id, found: bool) {
	for definition, index in registry.definitions {
		if definition.water_level == level {
			return Block_Id(index), true
		}
	}
	return AIR_BLOCK, false
}

// The raycast stops at solid blocks and at blocks that can be mined, so a
// torch can be targeted and water cannot.
block_is_targetable :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	return block_is_solid(registry, block) || block_is_minable(registry, block)
}

// Air and blocks without a hardness (water) cannot be mined.
block_is_minable :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	if int(block) >= len(registry.definitions) {
		return false
	}
	return registry.definitions[block].hardness_seconds > 0
}

DEFAULT_SOUND_MATERIAL :: "stone"

// The block's sound_material, DEFAULT_SOUND_MATERIAL when it names none or
// the id is out of range.
block_sound_material :: proc(registry: Block_Registry, block: Block_Id) -> string {
	if int(block) >= len(registry.definitions) || registry.definitions[block].sound_material == "" {
		return DEFAULT_SOUND_MATERIAL
	}
	return registry.definitions[block].sound_material
}

// The pickaxe tier hand mining the block needs, 0 outside the registry.
block_tool_tier :: proc(registry: Block_Registry, block: Block_Id) -> int {
	if int(block) >= len(registry.definitions) {
		return 0
	}
	return registry.definitions[block].tool_tier
}

face_group_color :: proc(texture: Block_Texture_Definition, group: Face_Group) -> [3]u8 {
	switch group {
	case .Top:
		return texture.top
	case .Side:
		return texture.side
	case .Bottom:
		return texture.bottom
	}
	return {}
}

// strings is the loaded string table the name keys are checked against.
load_block_registry :: proc(data_directory: string, strings: map[string]string, allocator := context.allocator) -> (registry: Block_Registry, ok: bool) {
	data, path := read_logged_data_file(data_directory, BLOCKS_FILE_NAME) or_return
	file, parse_error := parse_blocks_file(data, allocator)
	if parse_error != nil {
		platform.log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	if problem := validate_block_definitions(file.blocks); problem != "" {
		platform.log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	if problem := validate_block_name_keys(file.blocks, strings); problem != "" {
		platform.log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return Block_Registry{definitions = file.blocks}, true
}
