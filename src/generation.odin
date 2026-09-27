package game

import "core:encoding/json"
import "core:fmt"
import "core:os"

// Blocks the generator places by itself, independent of the biome table.
Generation_Blocks :: struct {
	stone:       Block_Id,
	deep_stone:  Block_Id,
	water:       Block_Id,
	log:         Block_Id,
	leaves:      Block_Id,
	sand:        Block_Id,
	landing_pad: Block_Id,
}

// Read only after creation, so worker threads share it without locking.
Generator :: struct {
	seed:                    u64,
	seeds:                   Purpose_Seeds,
	// For the opacity of blocks when generation computes sky light.
	registry:                Block_Registry,
	blocks:                  Generation_Blocks,
	biomes:                  []Biome,
	veins:                   Vein_Tables,
	// The largest densities over all biomes, so that a feature cell whose
	// roll exceeds them is rejected before any noise is sampled.
	maximum_tree_density:    f64,
	maximum_boulder_density: f64,
	// Set once the spawn is known, before any chunk is generated.
	landing_pad:             Landing_Pad_Site,
}

resolve_generation_blocks :: proc(registry: Block_Registry) -> (blocks: Generation_Blocks, problem: string) {
	names := [7]string{"stone", "deep_stone", "water", "log", "leaves", "sand", "landing_pad"}
	targets := [7]^Block_Id{&blocks.stone, &blocks.deep_stone, &blocks.water, &blocks.log, &blocks.leaves, &blocks.sand, &blocks.landing_pad}
	for name, index in names {
		found: bool
		if targets[index]^, found = find_block_id(registry, name); !found {
			return {}, fmt.tprintf("world generation needs block %q in %s", name, BLOCKS_FILE_NAME)
		}
	}
	return blocks, ""
}

maximum_densities :: proc(biomes: []Biome) -> (tree, boulder: f64) {
	for biome in biomes {
		tree = max(tree, f64(biome.definition.tree_density))
		boulder = max(boulder, f64(biome.definition.boulder_density))
	}
	return
}

make_generator :: proc(
	seed: u64,
	registry: Block_Registry,
	biomes_file: Biomes_File,
	veins_file: Veins_File,
	allocator := context.allocator,
) -> (
	generator: Generator,
	problem: string,
) {
	generator.seed = seed
	generator.seeds = derive_purpose_seeds(seed)
	generator.registry = registry
	if generator.blocks, problem = resolve_generation_blocks(registry); problem != "" {
		return {}, problem
	}
	if generator.biomes, problem = resolve_biomes(biomes_file, registry, allocator); problem != "" {
		return {}, problem
	}
	if generator.veins, problem = resolve_vein_tables(veins_file, registry, generator.biomes, allocator); problem != "" {
		return {}, problem
	}
	generator.maximum_tree_density, generator.maximum_boulder_density = maximum_densities(generator.biomes)
	return generator, ""
}

read_data_file :: proc(data_directory, file_name: string) -> (data: []byte, path: string, ok: bool) {
	join_error: os.Error
	path, join_error = os.join_path({data_directory, file_name}, context.temp_allocator)
	if join_error != nil {
		return nil, file_name, false
	}
	read_error: os.Error
	data, read_error = os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, read_error)
		return nil, path, false
	}
	return data, path, true
}

load_biomes_file :: proc(data_directory: string, allocator := context.allocator) -> (file: Biomes_File, ok: bool) {
	data, path := read_data_file(data_directory, BIOMES_FILE_NAME) or_return
	parse_error: json.Unmarshal_Error
	file, parse_error = parse_biomes_file(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	return file, true
}

load_veins_file :: proc(data_directory: string, allocator := context.allocator) -> (file: Veins_File, ok: bool) {
	data, path := read_data_file(data_directory, VEINS_FILE_NAME) or_return
	parse_error: json.Unmarshal_Error
	file, parse_error = parse_veins_file(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	return file, true
}

load_generator :: proc(data_directory: string, registry: Block_Registry, seed: u64, allocator := context.allocator) -> (generator: Generator, ok: bool) {
	biomes_file := load_biomes_file(data_directory, allocator) or_return
	veins_file := load_veins_file(data_directory, allocator) or_return
	problem: string
	generator, problem = make_generator(seed, registry, biomes_file, veins_file, allocator)
	if problem != "" {
		fmt.eprintfln("error: invalid world generation data in %s: %s", data_directory, problem)
		return {}, false
	}
	return generator, true
}
