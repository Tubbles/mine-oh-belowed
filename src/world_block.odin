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

Block_Definition :: struct {
	id:      string,
	name:    string,
	solid:   bool,
	texture: Block_Texture_Definition,
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
