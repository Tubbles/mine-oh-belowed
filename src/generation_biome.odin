package game

import "core:encoding/json"
import "core:fmt"

BIOMES_FILE_NAME :: "biomes.sjson"

// Heights are relative to sea level, see data/biomes.sjson. pit_block
// (optional) replaces the top block in low spots: columns no higher than
// pit_maximum_height and no higher than any face neighbour (tar pits).
// minimum_temperature and maximum_temperature are each optional (work item
// 0058); a missing bound accepts every temperature on its side.
// layer_block (optional) alternates with filler_block every
// layer_thickness blocks of absolute height (badlands). map_color tints
// the biome on the map, name_key names it in data/strings/en.sjson.
Biome_Definition :: struct {
	id:               string,
	name_key:         string,
	minimum_height:   i32,
	maximum_height:   i32,
	minimum_moisture: f32,
	maximum_moisture: f32,
	minimum_temperature: Maybe(f32),
	maximum_temperature: Maybe(f32),
	top_block:        string,
	filler_block:     string,
	layer_block:      string,
	layer_thickness:  i32,
	tree_density:     f32,
	boulder_density:  f32,
	pit_block:          string,
	pit_maximum_height: i32,
	map_color:        [3]u8,
}

// What a column offers the biome table.
Climate :: struct {
	relative_height: i32,
	moisture:        f32,
	temperature:     f32,
}

Biomes_File :: struct {
	biomes: []Biome_Definition,
}

// pit_block and layer_block are AIR_BLOCK for a biome without pits or
// layers.
Biome :: struct {
	definition:   Biome_Definition,
	top_block:    Block_Id,
	filler_block: Block_Id,
	pit_block:    Block_Id,
	layer_block:  Block_Id,
}

parse_biomes_file :: proc(data: []byte, allocator := context.allocator) -> (file: Biomes_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

density_in_range :: proc(density: f32) -> bool {
	return density >= 0 && density <= 1
}

// The temperature bounds with the missing ones filled in: temperatures
// lie between -1 and 1.
temperature_range :: proc(definition: Biome_Definition) -> (minimum, maximum: f32) {
	return definition.minimum_temperature.? or_else -1, definition.maximum_temperature.? or_else 1
}

// Returns an empty string when the definition is valid, otherwise the problem.
validate_biome_definition :: proc(definition: Biome_Definition) -> string {
	minimum_temperature, maximum_temperature := temperature_range(definition)
	switch {
	case definition.id == "":
		return "a biome has no id"
	case definition.name_key == "":
		return fmt.tprintf("biome %q has no name_key", definition.id)
	case definition.minimum_height > definition.maximum_height:
		return fmt.tprintf("biome %q has minimum_height above maximum_height", definition.id)
	case definition.minimum_moisture > definition.maximum_moisture:
		return fmt.tprintf("biome %q has minimum_moisture above maximum_moisture", definition.id)
	case minimum_temperature > maximum_temperature:
		return fmt.tprintf("biome %q has minimum_temperature above maximum_temperature", definition.id)
	case definition.layer_block != "" && definition.layer_thickness < 1:
		return fmt.tprintf("biome %q has a layer_thickness below 1", definition.id)
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
	if definition.pit_block != "" {
		pit_found: bool
		if biome.pit_block, pit_found = find_block_id(registry, definition.pit_block); !pit_found {
			return {}, fmt.tprintf("biome %q names an unknown pit_block", definition.id)
		}
	}
	if definition.layer_block != "" {
		layer_found: bool
		if biome.layer_block, layer_found = find_block_id(registry, definition.layer_block); !layer_found {
			return {}, fmt.tprintf("biome %q names an unknown layer_block", definition.id)
		}
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

biome_accepts :: proc(definition: Biome_Definition, climate: Climate) -> bool {
	height_fits := climate.relative_height >= definition.minimum_height && climate.relative_height <= definition.maximum_height
	moisture_fits := climate.moisture >= definition.minimum_moisture && climate.moisture <= definition.maximum_moisture
	minimum_temperature, maximum_temperature := temperature_range(definition)
	temperature_fits := climate.temperature >= minimum_temperature && climate.temperature <= maximum_temperature
	return height_fits && moisture_fits && temperature_fits
}

// The first biome that accepts the column, or the last one as a fallback.
select_biome :: proc(biomes: []Biome, climate: Climate) -> int {
	for biome, index in biomes {
		if biome_accepts(biome.definition, climate) {
			return index
		}
	}
	return len(biomes) - 1
}
