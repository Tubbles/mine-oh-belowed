package game

import "core:encoding/json"
import "core:fmt"

VEINS_FILE_NAME :: "veins.sjson"
// A vein stores its remaining amounts in a fixed array, one per output.
MAXIMUM_VEIN_OUTPUTS :: 4
// Spawn search findings keep vein types in a u64 mask.
MAXIMUM_VEIN_TYPES :: 64

Vein_Size_Class :: struct {
	id:                 string,
	minimum_units:      i64,
	maximum_units:      i64,
	minimum_radius:     i32,
	maximum_radius:     i32,
	minimum_per_region: i32,
	maximum_per_region: i32,
	minimum_distance:   i32,
}

Vein_Output :: struct {
	ore:     string,
	percent: i64,
}

Vein_Type_Definition :: struct {
	id:             string,
	weight:         i32,
	biomes:         []string,
	outcrop_blocks: []string,
	outputs:        []Vein_Output,
}

Veins_File :: struct {
	richness_distance:     i32,
	maximum_radius_growth: i32,
	size_classes:          []Vein_Size_Class,
	vein_types:            []Vein_Type_Definition,
	spawn_vein_types:      []string,
}

Vein_Type :: struct {
	definition:     Vein_Type_Definition,
	outcrop_blocks: []Block_Id,
	// Biome indices the type may appear in, empty for everywhere.
	biomes:         []int,
}

Vein_Tables :: struct {
	richness_distance:     i32,
	maximum_radius_growth: i32,
	size_classes:          []Vein_Size_Class,
	types:                 []Vein_Type,
	spawn_types:           []int,
}

parse_veins_file :: proc(data: []byte, allocator := context.allocator) -> (file: Veins_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

// Footprints must stay inside their region with a block to spare.
largest_possible_radius :: proc(file: Veins_File) -> i32 {
	largest: i32 = 0
	for size_class in file.size_classes {
		largest = max(largest, size_class.maximum_radius)
	}
	return largest + file.maximum_radius_growth
}

validate_size_class :: proc(size_class: Vein_Size_Class) -> string {
	switch {
	case size_class.minimum_units < 1 || size_class.minimum_units > size_class.maximum_units:
		return fmt.tprintf("size class %q has invalid units", size_class.id)
	case size_class.minimum_radius < 1 || size_class.minimum_radius > size_class.maximum_radius:
		return fmt.tprintf("size class %q has an invalid radius", size_class.id)
	case size_class.minimum_per_region < 0 || size_class.minimum_per_region > size_class.maximum_per_region:
		return fmt.tprintf("size class %q has an invalid count per region", size_class.id)
	}
	return ""
}

validate_vein_type_definition :: proc(definition: Vein_Type_Definition) -> string {
	total_percent: i64 = 0
	for output in definition.outputs {
		total_percent += output.percent
	}
	switch {
	case definition.id == "":
		return "a vein type has no id"
	case definition.weight < 1:
		return fmt.tprintf("vein type %q needs a positive weight", definition.id)
	case len(definition.outcrop_blocks) == 0:
		return fmt.tprintf("vein type %q has no outcrop block", definition.id)
	case len(definition.outputs) == 0 || len(definition.outputs) > MAXIMUM_VEIN_OUTPUTS:
		return fmt.tprintf("vein type %q needs 1 to %d outputs", definition.id, MAXIMUM_VEIN_OUTPUTS)
	case total_percent != 100:
		return fmt.tprintf("the outputs of vein type %q add up to %d percent", definition.id, total_percent)
	}
	return ""
}

validate_veins_file :: proc(file: Veins_File) -> string {
	switch {
	case file.richness_distance < 1:
		return "richness_distance must be positive"
	case file.maximum_radius_growth < 0:
		return "maximum_radius_growth must not be negative"
	case len(file.vein_types) == 0 || len(file.vein_types) > MAXIMUM_VEIN_TYPES:
		return fmt.tprintf("need 1 to %d vein types", MAXIMUM_VEIN_TYPES)
	case largest_possible_radius(file) * 2 + 2 >= REGION_SIZE:
		return "a vein footprint could exceed its region"
	}
	for size_class in file.size_classes {
		if problem := validate_size_class(size_class); problem != "" {
			return problem
		}
	}
	return ""
}

resolve_block_names :: proc(names: []string, registry: Block_Registry, allocator := context.allocator) -> (blocks: []Block_Id, ok: bool) {
	blocks = make([]Block_Id, len(names), allocator)
	for name, index in names {
		blocks[index] = find_block_id(registry, name) or_return
	}
	return blocks, true
}

resolve_biome_names :: proc(names: []string, biomes: []Biome, allocator := context.allocator) -> (indices: []int, ok: bool) {
	indices = make([]int, len(names), allocator)
	for name, index in names {
		indices[index] = find_biome_index(biomes, name)
		if indices[index] < 0 {
			return nil, false
		}
	}
	return indices, true
}

resolve_vein_type :: proc(definition: Vein_Type_Definition, registry: Block_Registry, biomes: []Biome, allocator := context.allocator) -> (vein_type: Vein_Type, problem: string) {
	if problem = validate_vein_type_definition(definition); problem != "" {
		return {}, problem
	}
	blocks_ok, biomes_ok: bool
	vein_type.definition = definition
	vein_type.outcrop_blocks, blocks_ok = resolve_block_names(definition.outcrop_blocks, registry, allocator)
	vein_type.biomes, biomes_ok = resolve_biome_names(definition.biomes, biomes, allocator)
	if !blocks_ok || !biomes_ok {
		return {}, fmt.tprintf("vein type %q names an unknown block or biome", definition.id)
	}
	return vein_type, ""
}

find_vein_type_index :: proc(types: []Vein_Type, id: string) -> int {
	for vein_type, index in types {
		if vein_type.definition.id == id {
			return index
		}
	}
	return -1
}

resolve_spawn_types :: proc(names: []string, types: []Vein_Type, allocator := context.allocator) -> (indices: []int, problem: string) {
	indices = make([]int, len(names), allocator)
	for name, index in names {
		indices[index] = find_vein_type_index(types, name)
		if indices[index] < 0 {
			return nil, fmt.tprintf("spawn_vein_types names unknown vein type %q", name)
		}
	}
	return indices, ""
}

resolve_vein_tables :: proc(file: Veins_File, registry: Block_Registry, biomes: []Biome, allocator := context.allocator) -> (tables: Vein_Tables, problem: string) {
	if problem = validate_veins_file(file); problem != "" {
		return {}, problem
	}
	tables = Vein_Tables {
		richness_distance     = file.richness_distance,
		maximum_radius_growth = file.maximum_radius_growth,
		size_classes          = file.size_classes,
		types                 = make([]Vein_Type, len(file.vein_types), allocator),
	}
	for definition, index in file.vein_types {
		if tables.types[index], problem = resolve_vein_type(definition, registry, biomes, allocator); problem != "" {
			return {}, problem
		}
	}
	tables.spawn_types, problem = resolve_spawn_types(file.spawn_vein_types, tables.types, allocator)
	return tables, problem
}
