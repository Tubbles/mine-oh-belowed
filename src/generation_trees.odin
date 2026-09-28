package game

import "core:encoding/json"
import "core:fmt"

// Tree species (work item 0059), data/trees.sjson. Biomes draw their trees
// from weighted species lists (Biome_Definition.trees); the crown shapes
// are in generation_features.odin, felling in tree_felling.odin.

TREES_FILE_NAME :: "trees.sjson"
// Every species stays within these, so FEATURE_REACH and
// FEATURE_MAXIMUM_HEIGHT cover every tree.
MAXIMUM_CROWN_RADIUS :: 4
MAXIMUM_TRUNK_HEIGHT :: 16

Tree_Crown :: enum u8 {
	None,
	Round,
	Conical,
	Flat,
}

// crown is a Tree_Crown name in lower case. leaves_block is empty for a
// species without a crown.
Tree_Species_Definition :: struct {
	id:                   string,
	name_key:             string,
	log_block:            string,
	leaves_block:         string,
	minimum_trunk_height: i32,
	maximum_trunk_height: i32,
	crown:                string,
	crown_radius:         i32,
}

Trees_File :: struct {
	sapling_item: string,
	species:      []Tree_Species_Definition,
}

// leaves_block is AIR_BLOCK for a species without a crown.
Tree_Species :: struct {
	definition:   Tree_Species_Definition,
	log_block:    Block_Id,
	leaves_block: Block_Id,
	crown:        Tree_Crown,
}

// The blocks felling and leaf decay recognise, over every species. A
// block shared by two species appears twice, which is harmless.
Tree_Blocks :: struct {
	logs:   []Block_Id,
	leaves: []Block_Id,
}

// One entry of a biome's trees list.
Biome_Tree_Definition :: struct {
	species: string,
	weight:  i32,
}

// species indexes the generator's species table.
Biome_Tree :: struct {
	species: int,
	weight:  i32,
}

parse_trees_file :: proc(data: []byte, allocator := context.allocator) -> (file: Trees_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

load_trees_file :: proc(data_directory: string, allocator := context.allocator) -> (file: Trees_File, ok: bool) {
	data, path := read_data_file(data_directory, TREES_FILE_NAME) or_return
	parse_error: json.Unmarshal_Error
	file, parse_error = parse_trees_file(data, allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	return file, true
}

parse_tree_crown :: proc(name: string) -> (crown: Tree_Crown, found: bool) {
	switch name {
	case "none":
		return .None, true
	case "round":
		return .Round, true
	case "conical":
		return .Conical, true
	case "flat":
		return .Flat, true
	}
	return .None, false
}

// Returns an empty string when the definition is valid, otherwise the problem.
validate_tree_species_definition :: proc(definition: Tree_Species_Definition) -> string {
	crown, crown_found := parse_tree_crown(definition.crown)
	switch {
	case definition.id == "":
		return "a tree species has no id"
	case definition.name_key == "":
		return fmt.tprintf("tree species %q has no name_key", definition.id)
	case !crown_found:
		return fmt.tprintf("tree species %q has an unknown crown %q", definition.id, definition.crown)
	case definition.minimum_trunk_height < 1 || definition.maximum_trunk_height > MAXIMUM_TRUNK_HEIGHT:
		return fmt.tprintf("tree species %q has a trunk height outside 1 to %d", definition.id, MAXIMUM_TRUNK_HEIGHT)
	case definition.minimum_trunk_height > definition.maximum_trunk_height:
		return fmt.tprintf("tree species %q has minimum_trunk_height above maximum_trunk_height", definition.id)
	case crown != .None && (definition.crown_radius < 1 || definition.crown_radius > MAXIMUM_CROWN_RADIUS):
		return fmt.tprintf("tree species %q has a crown_radius outside 1 to %d", definition.id, MAXIMUM_CROWN_RADIUS)
	case crown != .None && definition.leaves_block == "":
		return fmt.tprintf("tree species %q has a crown but no leaves_block", definition.id)
	}
	return ""
}

resolve_tree_species :: proc(definition: Tree_Species_Definition, registry: Block_Registry) -> (species: Tree_Species, problem: string) {
	if problem = validate_tree_species_definition(definition); problem != "" {
		return {}, problem
	}
	species.definition = definition
	species.crown, _ = parse_tree_crown(definition.crown)
	log_found: bool
	if species.log_block, log_found = find_block_id(registry, definition.log_block); !log_found {
		return {}, fmt.tprintf("tree species %q names an unknown log_block", definition.id)
	}
	if species.crown != .None {
		leaves_found: bool
		if species.leaves_block, leaves_found = find_block_id(registry, definition.leaves_block); !leaves_found {
			return {}, fmt.tprintf("tree species %q names an unknown leaves_block", definition.id)
		}
	}
	return species, ""
}

resolve_tree_species_table :: proc(file: Trees_File, registry: Block_Registry, allocator := context.allocator) -> (table: []Tree_Species, problem: string) {
	if file.sapling_item == "" {
		return nil, "no sapling_item"
	}
	table = make([]Tree_Species, len(file.species), allocator)
	for definition, index in file.species {
		if table[index], problem = resolve_tree_species(definition, registry); problem != "" {
			return nil, problem
		}
		if find_tree_species_index(table[:index], definition.id) >= 0 {
			return nil, fmt.tprintf("tree species %q is defined twice", definition.id)
		}
	}
	return table, ""
}

find_tree_species_index :: proc(table: []Tree_Species, id: string) -> int {
	for species, index in table {
		if species.definition.id == id {
			return index
		}
	}
	return -1
}

make_tree_blocks :: proc(table: []Tree_Species, allocator := context.allocator) -> Tree_Blocks {
	logs := make([dynamic]Block_Id, 0, len(table), allocator)
	leaves := make([dynamic]Block_Id, 0, len(table), allocator)
	for species in table {
		append(&logs, species.log_block)
		if species.crown != .None {
			append(&leaves, species.leaves_block)
		}
	}
	return Tree_Blocks{logs = logs[:], leaves = leaves[:]}
}

resolve_biome_trees :: proc(definition: Biome_Definition, table: []Tree_Species, allocator := context.allocator) -> (trees: []Biome_Tree, problem: string) {
	trees = make([]Biome_Tree, len(definition.trees), allocator)
	for entry, index in definition.trees {
		species := find_tree_species_index(table, entry.species)
		if species < 0 {
			return nil, fmt.tprintf("biome %q names an unknown tree species %q", definition.id, entry.species)
		}
		if entry.weight < 1 {
			return nil, fmt.tprintf("biome %q has a tree weight below 1", definition.id)
		}
		trees[index] = Biome_Tree{species = species, weight = entry.weight}
	}
	return trees, ""
}

// The species a tree grows as, drawn by weight from the hash.
choose_tree_species :: proc(trees: []Biome_Tree, hash: u64) -> int {
	total: i32 = 0
	for tree in trees {
		total += tree.weight
	}
	pick := i32(hash % u64(total))
	for tree in trees {
		if pick < tree.weight {
			return tree.species
		}
		pick -= tree.weight
	}
	return trees[len(trees) - 1].species
}

block_is_tree_log :: proc(blocks: Tree_Blocks, block: Block_Id) -> bool {
	return block_in_list(blocks.logs, block)
}

block_is_tree_leaves :: proc(blocks: Tree_Blocks, block: Block_Id) -> bool {
	return block_in_list(blocks.leaves, block)
}

block_in_list :: proc(list: []Block_Id, block: Block_Id) -> bool {
	for entry in list {
		if entry == block {
			return true
		}
	}
	return false
}
