package game

import "core:encoding/json"
import "core:fmt"

BIOMES_FILE_NAME :: "biomes.sjson"

// Heights are relative to sea level, see data/biomes.sjson.
Biome_Definition :: struct {
	id:               string,
	name:             string,
	minimum_height:   i32,
	maximum_height:   i32,
	minimum_moisture: f32,
	maximum_moisture: f32,
	top_block:        string,
	filler_block:     string,
	tree_density:     f32,
	boulder_density:  f32,
}

Biomes_File :: struct {
	biomes: []Biome_Definition,
}

Biome :: struct {
	definition:   Biome_Definition,
	top_block:    Block_Id,
	filler_block: Block_Id,
}

parse_biomes_file :: proc(data: []byte, allocator := context.allocator) -> (file: Biomes_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

density_in_range :: proc(density: f32) -> bool {
	return density >= 0 && density <= 1
}

// Returns an empty string when the definition is valid, otherwise the problem.
validate_biome_definition :: proc(definition: Biome_Definition) -> string {
	switch {
	case definition.id == "":
		return "a biome has no id"
	case definition.minimum_height > definition.maximum_height:
		return fmt.tprintf("biome %q has minimum_height above maximum_height", definition.id)
	case definition.minimum_moisture > definition.maximum_moisture:
		return fmt.tprintf("biome %q has minimum_moisture above maximum_moisture", definition.id)
	case !density_in_range(definition.tree_density) || !density_in_range(definition.boulder_density):
		return fmt.tprintf("biome %q has a density outside 0 to 1", definition.id)
	}
	return ""
}

resolve_biome :: proc(definition: Biome_Definition, registry: Block_Registry) -> (biome: Biome, problem: string) {
	if problem = validate_biome_definition(definition); problem != "" {
		return {}, problem
	}
	top_found, filler_found: bool
	biome.definition = definition
	biome.top_block, top_found = find_block_id(registry, definition.top_block)
	biome.filler_block, filler_found = find_block_id(registry, definition.filler_block)
	if !top_found || !filler_found {
		return {}, fmt.tprintf("biome %q names an unknown block", definition.id)
	}
	return biome, ""
}

resolve_biomes :: proc(file: Biomes_File, registry: Block_Registry, allocator := context.allocator) -> (biomes: []Biome, problem: string) {
	if len(file.biomes) == 0 {
		return nil, "no biomes defined"
	}
	biomes = make([]Biome, len(file.biomes), allocator)
	for definition, index in file.biomes {
		if biomes[index], problem = resolve_biome(definition, registry); problem != "" {
			return nil, problem
		}
	}
	return biomes, ""
}

find_biome_index :: proc(biomes: []Biome, id: string) -> int {
	for biome, index in biomes {
		if biome.definition.id == id {
			return index
		}
	}
	return -1
}

biome_accepts :: proc(definition: Biome_Definition, relative_height: i32, moisture: f32) -> bool {
	height_fits := relative_height >= definition.minimum_height && relative_height <= definition.maximum_height
	moisture_fits := moisture >= definition.minimum_moisture && moisture <= definition.maximum_moisture
	return height_fits && moisture_fits
}

// The first biome that accepts the column, or the last one as a fallback.
select_biome :: proc(biomes: []Biome, relative_height: i32, moisture: f32) -> int {
	for biome, index in biomes {
		if biome_accepts(biome.definition, relative_height, moisture) {
			return index
		}
	}
	return len(biomes) - 1
}
