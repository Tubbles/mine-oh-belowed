package game

import "core:encoding/json"
import "core:fmt"
import "core:os"

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

Block_Texture_Definition :: struct {
	top:    [3]u8,
	side:   [3]u8,
	bottom: [3]u8,
}

// hardness_seconds is the hand mining time, 0 for blocks that cannot be
// mined. light_level is the block light emitted (0 to MAXIMUM_LIGHT).
// water_level is 0 for everything but water, WATER_SOURCE_LEVEL for a
// source and 1 to WATER_SOURCE_LEVEL - 1 for flowing water.
Block_Definition :: struct {
	id:               string,
	name:             string,
	solid:            bool,
	hardness_seconds: f32,
	light_level:      int,
	water_level:      int,
	texture:          Block_Texture_Definition,
}

Blocks_File :: struct {
	blocks: []Block_Definition,
}

Block_Registry :: struct {
	definitions: []Block_Definition,
}

parse_blocks_file :: proc(data: []byte, allocator := context.allocator) -> (file: Blocks_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
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
		if definition.light_level < 0 || definition.light_level > MAXIMUM_LIGHT {
			return fmt.tprintf("block %q has light_level %d outside 0 to %d", definition.id, definition.light_level, MAXIMUM_LIGHT)
		}
		if definition.water_level < 0 || definition.water_level > WATER_SOURCE_LEVEL {
			return fmt.tprintf("block %q has water_level %d outside 0 to %d", definition.id, definition.water_level, WATER_SOURCE_LEVEL)
		}
	}
	return validate_water_levels(definitions)
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

find_definition_index :: proc(definitions: []Block_Definition, id: string) -> int {
	for definition, index in definitions {
		if definition.id == id {
			return index
		}
	}
	return -1
}

find_block_id :: proc(registry: Block_Registry, id: string) -> (block: Block_Id, found: bool) {
	index := find_definition_index(registry.definitions, id)
	if index < 0 {
		return AIR_BLOCK, false
	}
	return Block_Id(index), true
}

// Ids outside the registry count as not solid, so a malformed chunk cannot
// index past the table.
block_is_solid :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	if int(block) >= len(registry.definitions) {
		return false
	}
	return registry.definitions[block].solid
}

// Light passes through every block that is not solid.
block_is_opaque :: proc(registry: Block_Registry, block: Block_Id) -> bool {
	return block_is_solid(registry, block)
}

block_light_emission :: proc(registry: Block_Registry, block: Block_Id) -> u8 {
	if int(block) >= len(registry.definitions) {
		return 0
	}
	return u8(registry.definitions[block].light_level)
}

block_water_level :: proc(registry: Block_Registry, block: Block_Id) -> int {
	if int(block) >= len(registry.definitions) {
		return 0
	}
	return registry.definitions[block].water_level
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

load_block_registry :: proc(data_directory: string, allocator := context.allocator) -> (registry: Block_Registry, ok: bool) {
	path, join_error := os.join_path({data_directory, BLOCKS_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_blocks_file(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	if problem := validate_block_definitions(file.blocks); problem != "" {
		fmt.eprintfln("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return Block_Registry{definitions = file.blocks}, true
}
