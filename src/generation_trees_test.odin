package game

import "core:log"
import "core:testing"
import "generation_seed"

// The entries of data/trees.sjson.
SHIPPED_TREE_SPECIES_COUNT :: 6

test_tree_species :: proc(generator: ^Generator, id: string) -> int {
	index := find_tree_species_index(generator.species, id)
	assert(index >= 0, id)
	return index
}

// A tree of the species at the origin.
make_test_tree :: proc(generator: ^Generator, id: string, trunk_height: i32) -> Tree {
	species := test_tree_species(generator, id)
	tree := make_tree(generator.species[species], species, Feature_Root{})
	tree.trunk_height = trunk_height
	return tree
}

count_crown_layer :: proc(tree: Tree, layer: i32) -> int {
	count := 0
	y := tree.root.y + tree.trunk_height + layer
	for dz in i32(-LEAF_REACH - 1) ..= LEAF_REACH + 1 {
		for dx in i32(-LEAF_REACH - 1) ..= LEAF_REACH + 1 {
			count += tree_leaves_contain(tree, tree.root + {dx, y - tree.root.y, dz}) ? 1 : 0
		}
	}
	return count
}

@(test)
test_shipped_tree_species_resolve :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	testing.expect_value(t, len(generator.species), SHIPPED_TREE_SPECIES_COUNT)
	registry := make_test_registry()
	oak := generator.species[test_tree_species(&generator, "oak")]
	testing.expect_value(t, oak.log_block, test_block(registry, "log"))
	testing.expect_value(t, oak.leaves_block, test_block(registry, "leaves"))
	testing.expect_value(t, oak.crown, Tree_Crown.Round)
	dead := generator.species[test_tree_species(&generator, "dead_tree")]
	testing.expect_value(t, dead.crown, Tree_Crown.None)
	testing.expect_value(t, dead.leaves_block, AIR_BLOCK)
	testing.expect(t, block_is_tree_log(generator.tree_blocks, test_block(registry, "pine_log")))
	testing.expect(t, block_is_tree_leaves(generator.tree_blocks, test_block(registry, "palm_leaves")))
	testing.expect(t, !block_is_tree_leaves(generator.tree_blocks, test_block(registry, "log")))
	testing.expect(t, !block_is_tree_log(generator.tree_blocks, test_block(registry, "stone")))
	// Every biome with trees has a list, and the forest draws oak and birch.
	for biome in generator.biomes {
		testing.expectf(t, biome.definition.tree_density == 0 || len(biome.trees) > 0, "biome %q has trees but no species", biome.definition.id)
	}
	forest := generator.biomes[find_biome_index(generator.biomes, "forest")]
	testing.expect_value(t, len(forest.trees), 2)
	testing.expect_value(t, forest.trees[0], Biome_Tree{species = test_tree_species(&generator, "oak"), weight = 3})
	testing.expect_value(t, forest.definition.clearing_share, 0.35)
	// Every log drops the log item and every leaves block the leaves item.
	items := make_test_items()
	for species in generator.species {
		testing.expect_value(t, block_drop(items, species.log_block), test_item(items, "log"))
		if species.crown != .None {
			testing.expect_value(t, block_drop(items, species.leaves_block), test_item(items, "leaves"))
		}
	}
	_, sapling_found := find_item_id(items, generator.sapling_item)
	testing.expect(t, sapling_found)
}

@(test)
test_tree_species_validation :: proc(t: ^testing.T) {
	registry := make_test_registry()
	valid := Tree_Species_Definition {
		id                   = "test",
		name_key             = "tree_test",
		log_block            = "log",
		leaves_block         = "leaves",
		minimum_trunk_height = 4,
		maximum_trunk_height = 8,
		crown                = "round",
		crown_radius         = 2,
	}
	_, problem := resolve_tree_species(valid, registry)
	testing.expect_value(t, problem, "")
	upside_down := valid
	upside_down.minimum_trunk_height = 9
	_, problem = resolve_tree_species(upside_down, registry)
	testing.expect(t, problem != "")
	too_tall := valid
	too_tall.maximum_trunk_height = MAXIMUM_TRUNK_HEIGHT + 1
	_, problem = resolve_tree_species(too_tall, registry)
	testing.expect(t, problem != "")
	wide := valid
	wide.crown_radius = MAXIMUM_CROWN_RADIUS + 1
	_, problem = resolve_tree_species(wide, registry)
	testing.expect(t, problem != "")
	missing_block := valid
	missing_block.leaves_block = "maple_leaves"
	_, problem = resolve_tree_species(missing_block, registry)
	testing.expect(t, problem != "")
	unknown_crown := valid
	unknown_crown.crown = "weeping"
	_, problem = resolve_tree_species(unknown_crown, registry)
	testing.expect(t, problem != "")
	// A dead tree needs neither leaves nor a radius.
	dead := valid
	dead.crown = "none"
	dead.leaves_block = ""
	dead.crown_radius = 0
	_, problem = resolve_tree_species(dead, registry)
	testing.expect_value(t, problem, "")
}

@(test)
test_trees_file_reads_and_biomes_need_species :: proc(t: ^testing.T) {
	data := `sapling_item = "sapling"
species = [{id = "fir", name_key = "tree_fir", log_block = "log", leaves_block = "leaves", minimum_trunk_height = 5, maximum_trunk_height = 6, crown = "conical", crown_radius = 2}]`
	file, error := parse_trees_file(transmute([]byte)data, context.temp_allocator)
	testing.expect_value(t, error, nil)
	table, problem := resolve_tree_species_table(file, make_test_registry(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(table), 1)
	testing.expect_value(t, table[0].crown, Tree_Crown.Conical)
	biome := Biome_Definition {
		id             = "grove",
		name_key       = "biome_grove",
		maximum_height = 10,
		tree_density   = 0.5,
	}
	testing.expect(t, validate_biome_definition(biome) != "")
	biome.trees = []Biome_Tree_Definition{{species = "fir", weight = 1}}
	testing.expect_value(t, validate_biome_definition(biome), "")
	trees, trees_problem := resolve_biome_trees(biome, table, context.temp_allocator)
	testing.expect_value(t, trees_problem, "")
	testing.expect_value(t, trees[0], Biome_Tree{species = 0, weight = 1})
	biome.trees = []Biome_Tree_Definition{{species = "maple", weight = 1}}
	_, trees_problem = resolve_biome_trees(biome, table, context.temp_allocator)
	testing.expect(t, trees_problem != "")
	biome.clearing_share = 1.5
	testing.expect(t, validate_biome_definition(biome) != "")
}

@(test)
test_choose_tree_species_by_weight :: proc(t: ^testing.T) {
	trees := []Biome_Tree{{species = 4, weight = 3}, {species = 7, weight = 1}}
	counts: [2]int
	for hash in u64(0) ..< 400 {
		species := choose_tree_species(trees, generation_seed.hash_u64(hash))
		counts[species == 4 ? 0 : 1] += 1
	}
	testing.expect(t, counts[0] > 250 && counts[0] < 350, "weight 3 of 4 should take about three quarters")
	testing.expect_value(t, choose_tree_species(trees, 2), 4)
	testing.expect_value(t, choose_tree_species(trees, 3), 7)
}

@(test)
test_crown_disc :: proc(t: ^testing.T) {
	disc_size :: proc(radius: i32) -> int {
		count := 0
		for dz in i32(-5) ..= 5 {
			for dx in i32(-5) ..= 5 {
				count += crown_disc_contains(radius, dx, dz) ? 1 : 0
			}
		}
		return count
	}
	testing.expect_value(t, disc_size(0), 1)
	testing.expect_value(t, disc_size(1), 5)
	testing.expect_value(t, disc_size(2), 21)
	testing.expect_value(t, disc_size(3), 37)
	testing.expect_value(t, disc_size(4), 61)
	testing.expect(t, crown_disc_contains(4, 4, 0))
	testing.expect(t, !crown_disc_contains(4, 4, 2))
}

@(test)
test_round_crown_layers :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	oak := make_test_tree(&generator, "oak", 8)
	expected := [5]int{21, 37, 37, 21, 5}
	for count, index in expected {
		testing.expectf(t, count_crown_layer(oak, i32(index) - 2) == count, "oak layer %d", index - 2)
	}
	testing.expect_value(t, count_crown_layer(oak, -3), 0)
	testing.expect_value(t, count_crown_layer(oak, 3), 0)
	// Symmetric about the trunk.
	for layer in i32(-2) ..= 2 {
		for dz in i32(-3) ..= 3 {
			for dx in i32(-3) ..= 3 {
				position := oak.root + {dx, oak.trunk_height + layer, dz}
				mirrored := oak.root + {-dz, oak.trunk_height + layer, dx}
				testing.expect_value(t, tree_leaves_contain(oak, position), tree_leaves_contain(oak, mirrored))
			}
		}
	}
	// Birch, radius 2, ends in a single block on top.
	birch := make_test_tree(&generator, "birch", 10)
	testing.expect_value(t, count_crown_layer(birch, 0), 21)
	testing.expect_value(t, count_crown_layer(birch, 2), 1)
}

@(test)
test_conical_crown_layers :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	pine := make_test_tree(&generator, "pine", 10)
	bottom := conical_crown_bottom(pine)
	testing.expect_value(t, bottom, i32(10 / 3 - 10))
	// Widest at the bottom, a plus at the top, one tip block above.
	testing.expect_value(t, count_crown_layer(pine, bottom), 37)
	testing.expect_value(t, count_crown_layer(pine, bottom - 1), 0)
	testing.expect_value(t, count_crown_layer(pine, 0), 5)
	testing.expect_value(t, count_crown_layer(pine, 1), 1)
	testing.expect(t, tree_leaves_contain(pine, pine.root + {0, pine.trunk_height + 1, 0}))
	testing.expect_value(t, count_crown_layer(pine, 2), 0)
	// Alternating: each layer is narrower than the one below it or the
	// same, and a narrower layer follows every full one.
	previous := count_crown_layer(pine, bottom)
	for layer in bottom + 1 ..= 0 {
		count := count_crown_layer(pine, layer)
		testing.expectf(t, count <= previous || (layer - bottom) % 2 == 0, "pine layer %d grows", layer)
		previous = count
	}
	testing.expect(t, count_crown_layer(pine, bottom + 1) < count_crown_layer(pine, bottom))
	tall := make_test_tree(&generator, "pine", 16)
	testing.expect_value(t, count_crown_layer(tall, conical_crown_bottom(tall)), 37)
	testing.expect_value(t, count_crown_layer(tall, 0), 5)
}

@(test)
test_flat_and_bare_crowns :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	acacia := make_test_tree(&generator, "acacia", 6)
	testing.expect_value(t, count_crown_layer(acacia, 0), 61)
	testing.expect_value(t, count_crown_layer(acacia, 1), 5)
	testing.expect_value(t, count_crown_layer(acacia, -1), 0)
	testing.expect_value(t, count_crown_layer(acacia, 2), 0)
	palm := make_test_tree(&generator, "palm", 10)
	testing.expect_value(t, count_crown_layer(palm, 0), 21)
	dead := make_test_tree(&generator, "dead_tree", 6)
	for layer in i32(-6) ..= 4 {
		testing.expect_value(t, count_crown_layer(dead, layer), 0)
	}
	testing.expect(t, tree_trunk_contains(dead, dead.root + {0, 6, 0}))
	testing.expect(t, !tree_trunk_contains(dead, dead.root + {0, 7, 0}))
}

// The logs are the trunk alone: nothing beside its foot.
@(test)
test_tree_logs_are_the_trunk :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	for species in generator.species {
		tree := make_test_tree(&generator, species.definition.id, species.definition.maximum_trunk_height)
		for dz in i32(-1) ..= 1 {
			for dx in i32(-1) ..= 1 {
				testing.expect_value(t, tree_log_contains(tree, tree.root + {dx, 1, dz}), dx == 0 && dz == 0)
			}
		}
		box := tree_log_box(tree)
		testing.expect_value(t, box, Block_Box{minimum = tree.root + {0, 1, 0}, maximum = tree.root + {0, tree.trunk_height, 0}})
	}
}

// No leaf lies farther than LEAF_REACH from its trunk or outside the
// tree's box, for every species and trunk height.
@(test)
test_crowns_stay_within_reach :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	for species in generator.species {
		definition := species.definition
		for trunk in definition.minimum_trunk_height ..= definition.maximum_trunk_height {
			tree := make_test_tree(&generator, definition.id, trunk)
			expect_crown_within_reach(t, tree)
		}
	}
}

expect_crown_within_reach :: proc(t: ^testing.T, tree: Tree) {
	box := tree_box(tree)
	for y in i32(0) ..= tree.trunk_height + 6 {
		for dz in i32(-LEAF_REACH - 2) ..= LEAF_REACH + 2 {
			for dx in i32(-LEAF_REACH - 2) ..= LEAF_REACH + 2 {
				position := tree.root + {dx, y, dz}
				if !tree_leaves_contain(tree, position) {
					continue
				}
				testing.expectf(t, abs(dx) <= LEAF_REACH && abs(dz) <= LEAF_REACH, "leaf at %v beyond LEAF_REACH", position)
				testing.expectf(t, box.minimum.y <= position.y && position.y <= box.maximum.y && box_covers_column(box, position.x, position.z), "leaf at %v outside the tree box", position)
				testing.expect(t, y <= FEATURE_MAXIMUM_HEIGHT)
			}
		}
	}
}

// Species per biome on the default seed: a forest chunk holds oak and
// birch logs, a highland chunk pine logs.
@(test)
test_species_placement_by_biome :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	forest, forest_found := find_chunk_with_species(&generator, "forest", {"oak", "birch"})
	testing.expect(t, forest_found, "no forest chunk with oak and birch near the origin")
	if forest_found {
		logs := count_generated_logs(&generator, forest)
		testing.expect(t, logs[test_block(registry, "log")] > 0, "no oak log in the forest chunk")
		testing.expect(t, logs[test_block(registry, "birch_log")] > 0, "no birch log in the forest chunk")
	}
	highland, highland_found := find_chunk_with_species(&generator, "highland", {"pine"})
	testing.expect(t, highland_found, "no highland chunk with pine near the origin")
	if highland_found {
		logs := count_generated_logs(&generator, highland)
		testing.expect(t, logs[test_block(registry, "pine_log")] > 0, "no pine log in the highland chunk")
	}
}

// The surface chunk of the first chunk column near the origin with a
// tree of every species named rooted inside it in the biome.
find_chunk_with_species :: proc(generator: ^Generator, biome_id: string, species_ids: []string) -> (coordinate: Chunk_Coordinate, found: bool) {
	biome := find_biome_index(generator.biomes, biome_id)
	wanted: bit_set[0 ..< 16]
	for id in species_ids {
		wanted += {test_tree_species(generator, id)}
	}
	for chunk_z in i32(-32) ..< 32 {
		for chunk_x in i32(-32) ..< 32 {
			column := Chunk_Coordinate{chunk_x, 0, chunk_z}
			if root_y, present := chunk_holds_species(generator, column, biome, wanted); present {
				return {chunk_x, floor_divide(root_y + 1, CHUNK_SIZE), chunk_z}, true
			}
		}
	}
	return {}, false
}

// Whether trees of every wanted species root inside the chunk column in
// the biome, and the height of one of their roots.
chunk_holds_species :: proc(generator: ^Generator, coordinate: Chunk_Coordinate, biome: int, wanted: bit_set[0 ..< 16]) -> (root_y: i32, present: bool) {
	origin := chunk_origin(coordinate)
	bounds := chunk_box(coordinate)
	seen: bit_set[0 ..< 16]
	for cell_z in floor_divide(origin.z, TREE_CELL_SIZE) ..= floor_divide(origin.z + CHUNK_SIZE - 1, TREE_CELL_SIZE) {
		for cell_x in floor_divide(origin.x, TREE_CELL_SIZE) ..= floor_divide(origin.x + CHUNK_SIZE - 1, TREE_CELL_SIZE) {
			root, found := feature_root(generator, .Tree, {cell_x, cell_z}, nil)
			if !found || root.biome != biome || !box_covers_column(bounds, root.position.x, root.position.z) {
				continue
			}
			tree, _ := tree_in_cell(generator, {cell_x, cell_z}, nil)
			seen += {tree.species}
			root_y = root.position.y
		}
	}
	return root_y, wanted <= seen
}

// Every log block of the chunk and the one above it, by block id.
count_generated_logs :: proc(generator: ^Generator, coordinate: Chunk_Coordinate) -> map[Block_Id]int {
	counts := make(map[Block_Id]int, context.temp_allocator)
	for layer in i32(0) ..= 1 {
		generated := generate_chunk(generator, coordinate + {0, layer, 0}, context.temp_allocator)
		for block in generated.chunk.blocks {
			if block_is_tree_log(generator.tree_blocks, block) {
				counts[block] += 1
			}
		}
	}
	return counts
}

// Over the forest columns of a sample, the clearing noise covers about
// the forest's clearing_share, and the forest's tree count drops by about
// that share against the same generator without clearings.
@(test)
test_clearings_thin_the_forest :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	forest := find_biome_index(generator.biomes, "forest")
	share := generator.biomes[forest].definition.clearing_share
	without := generator
	without.biomes = make([]Biome, len(generator.biomes), context.temp_allocator)
	copy(without.biomes, generator.biomes)
	without.biomes[forest].definition.clearing_share = 0
	with_clearings, without_clearings := 0, 0
	for cell_z in i32(-80) ..< 80 {
		for cell_x in i32(-80) ..< 80 {
			if root, found := feature_root(&without, .Tree, {cell_x, cell_z}, nil); found && root.biome == forest {
				without_clearings += 1
				_, kept := feature_root(&generator, .Tree, {cell_x, cell_z}, nil)
				with_clearings += kept ? 1 : 0
			}
		}
	}
	testing.expect(t, without_clearings > 500, "too few forest trees in the sample")
	removed := 1 - f64(with_clearings) / f64(max(without_clearings, 1))
	log.infof("forest trees %d without clearings, %d with: %.2f removed, share %.2f", without_clearings, with_clearings, removed, share)
	testing.expect(t, abs(removed - f64(share)) < 0.1)
	testing.expect(t, !column_in_clearing(generator.seeds, 0, 5, 5))
}

// No tree roots beside the landing pad, so nothing of a tree stands on it
// or hangs over it above its clearance, on every landing site seed.
@(test)
test_no_tree_over_the_landing_pad :: proc(t: ^testing.T) {
	for seed in LANDING_SITE_TEST_SEEDS {
		generator, found := make_landed_test_generator(t, seed)
		if !found {
			continue
		}
		centre := generator.landing_pad.centre
		reach := i32(LANDING_PAD_HALF_WIDTH + LEAF_REACH)
		for cell_z in floor_divide(centre.z - reach - FEATURE_REACH, TREE_CELL_SIZE) ..= floor_divide(centre.z + reach + FEATURE_REACH, TREE_CELL_SIZE) {
			for cell_x in floor_divide(centre.x - reach - FEATURE_REACH, TREE_CELL_SIZE) ..= floor_divide(centre.x + reach + FEATURE_REACH, TREE_CELL_SIZE) {
				tree, exists := tree_in_cell(&generator, {cell_x, cell_z}, nil)
				if exists {
					box := tree_box(tree)
					over_x := box.maximum.x >= centre.x - LANDING_PAD_HALF_WIDTH && box.minimum.x <= centre.x + LANDING_PAD_HALF_WIDTH
					over_z := box.maximum.z >= centre.z - LANDING_PAD_HALF_WIDTH && box.minimum.z <= centre.z + LANDING_PAD_HALF_WIDTH
					testing.expectf(t, !(over_x && over_z), "seed %d: tree at %v reaches over the pad at %v", seed, tree.root, centre)
				}
			}
		}
	}
}
