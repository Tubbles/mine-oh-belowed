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
// trees (work item 0059) lists the species its trees are drawn from, by
// weight; clearing_share is about the share of the biome left without
// trees (column_in_clearing). ground_cover (work item 0082) lists the
// cover blocks set on the top block of dry land (apply_ground_cover).
// ambience (optional, work item 0068) names the loop that plays while the
// player stands in the biome, ambience_<name> in the sound table
// (audio.odin); empty for none. bird_density (optional, work item 0075)
// is the chance, 0 to 1, that a flock cell whose centre lies in the biome
// holds a flock of birds (ambient_life.odin).
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
	trees:            []Biome_Tree_Definition,
	clearing_share:   f32,
	ground_cover:     []Biome_Cover_Definition,
	pit_block:          string,
	pit_maximum_height: i32,
	map_color:        [3]u8,
	ambience:         string,
	bird_density:     f32,
}

// One entry of a biome's ground_cover list: a cross shaped block, its
// chance per column (0 to 1) and the top block ids it stands on. insects
// (optional, work item 0075) marks the block as a flower that insect
// motes circle wherever it stands (render_life.odin).
Biome_Cover_Definition :: struct {
	block:   string,
	chance:  f32,
	on:      []string,
	insects: bool,
}

// A resolved ground_cover entry.
Biome_Cover :: struct {
	block:   Block_Id,
	chance:  f32,
	on:      []Block_Id,
	insects: bool,
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
	trees:        []Biome_Tree,
	ground_cover: []Biome_Cover,
}

parse_biomes_file :: proc(data: []byte, allocator := context.allocator) -> (file: Biomes_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

density_in_range :: proc(density: f32) -> bool {
	return density >= 0 && density <= 1
}

// Each chance lies in 0 to 1 and together they reach at most 1, since one
// roll per column picks an entry by the running sum.
ground_cover_chances_valid :: proc(cover: []Biome_Cover_Definition) -> bool {
	total: f32 = 0
	for entry in cover {
		if !density_in_range(entry.chance) {
			return false
		}
		total += entry.chance
	}
	return total <= 1
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
	case !density_in_range(definition.tree_density) || !density_in_range(definition.boulder_density) || !density_in_range(definition.bird_density):
		return fmt.tprintf("biome %q has a density outside 0 to 1", definition.id)
	case definition.tree_density > 0 && len(definition.trees) == 0:
		return fmt.tprintf("biome %q has trees but no trees list", definition.id)
	case !density_in_range(definition.clearing_share):
		return fmt.tprintf("biome %q has a clearing_share outside 0 to 1", definition.id)
	case !ground_cover_chances_valid(definition.ground_cover):
		return fmt.tprintf("biome %q has ground_cover chances outside 0 to 1", definition.id)
	}
	return ""
}

resolve_biome :: proc(definition: Biome_Definition, registry: Block_Registry, species: []Tree_Species, allocator := context.allocator) -> (biome: Biome, problem: string) {
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
	if biome.trees, problem = resolve_biome_trees(definition, species, allocator); problem != "" {
		return {}, problem
	}
	if biome.ground_cover, problem = resolve_biome_ground_cover(definition, registry, allocator); problem != "" {
		return {}, problem
	}
	return biome, ""
}

// Every cover block exists and is a cross, every on block exists.
resolve_biome_ground_cover :: proc(definition: Biome_Definition, registry: Block_Registry, allocator := context.allocator) -> (cover: []Biome_Cover, problem: string) {
	cover = make([]Biome_Cover, len(definition.ground_cover), allocator)
	for entry, index in definition.ground_cover {
		block, found := find_block_id(registry, entry.block)
		if !found {
			return nil, fmt.tprintf("biome %q names an unknown ground_cover block %q", definition.id, entry.block)
		}
		if block_shape(registry, block) != .Cross {
			return nil, fmt.tprintf("biome %q has ground_cover block %q that is not a cross", definition.id, entry.block)
		}
		on := make([]Block_Id, len(entry.on), allocator)
		for name, on_index in entry.on {
			if on[on_index], found = find_block_id(registry, name); !found {
				return nil, fmt.tprintf("biome %q sets ground_cover on an unknown block %q", definition.id, name)
			}
		}
		cover[index] = Biome_Cover{block = block, chance = entry.chance, on = on, insects = entry.insects}
	}
	return cover, ""
}

resolve_biomes :: proc(file: Biomes_File, registry: Block_Registry, species: []Tree_Species, allocator := context.allocator) -> (biomes: []Biome, problem: string) {
	if len(file.biomes) == 0 {
		return nil, "no biomes defined"
	}
	biomes = make([]Biome, len(file.biomes), allocator)
	for definition, index in file.biomes {
		if biomes[index], problem = resolve_biome(definition, registry, species, allocator); problem != "" {
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

// Whether any biome's ground_cover marks the block as a flower that draws
// insects (Biome_Cover_Definition.insects).
block_draws_insects :: proc(biomes: []Biome, block: Block_Id) -> bool {
	for biome in biomes {
		for entry in biome.ground_cover {
			if entry.block == block && entry.insects {
				return true
			}
		}
	}
	return false
}

// The largest bird_density over all biomes, so a flock cell whose roll
// exceeds it is rejected before its column is sampled.
maximum_bird_density :: proc(biomes: []Biome) -> f32 {
	maximum: f32 = 0
	for biome in biomes {
		maximum = max(maximum, biome.definition.bird_density)
	}
	return maximum
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
