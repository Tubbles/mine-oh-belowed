package game

import "core:log"
import "core:slice"
import "core:testing"

// Seeds besides the default that every generation test also runs on.
TEST_SEEDS :: [3]u64{DEFAULT_WORLD_SEED, 1, 987654321}
// The entries of data/biomes.sjson.
SHIPPED_BIOME_COUNT :: 14

// The largest height step allowed between two neighbouring columns.
// Plateau cliffs and terraces (PLATEAU_STEP plus detail) are the steepest
// terrain; river valley walls rise more gently (VALLEY_WALL_RISE).
MAXIMUM_TEST_HEIGHT_STEP :: 16

make_test_registry :: proc() -> Block_Registry {
	file, error := parse_blocks_file(#load("../data/blocks.sjson"), context.temp_allocator)
	assert(error == nil)
	return Block_Registry{definitions = file.blocks}
}

make_test_generator :: proc(seed: u64) -> Generator {
	biomes, biomes_error := parse_biomes_file(#load("../data/biomes.sjson"), context.temp_allocator)
	trees, trees_error := parse_trees_file(#load("../data/trees.sjson"), context.temp_allocator)
	veins, veins_error := parse_veins_file(#load("../data/veins.sjson"), context.temp_allocator)
	assert(biomes_error == nil && trees_error == nil && veins_error == nil)
	generator, problem := make_generator(seed, make_test_registry(), biomes, trees, veins, context.temp_allocator)
	assert(problem == "", problem)
	return generator
}

@(test)
test_shipped_generation_data_resolves :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	testing.expect_value(t, len(generator.biomes), SHIPPED_BIOME_COUNT)
	testing.expect_value(t, len(generator.veins.types), 13)
	testing.expect_value(t, len(generator.veins.size_classes), 3)
	testing.expect_value(t, len(generator.veins.spawn_types), 3)
	testing.expect(t, generator.blocks.water != generator.blocks.stone)
}

// Terrain shape (work item 0057), measured over TERRAIN_SAMPLE_SIZE
// squared columns around the origin.
TERRAIN_SAMPLE_SIZE :: 512
MINIMUM_LAND_FRACTION :: 0.55
MAXIMUM_LAND_FRACTION :: 0.85
// Neighbouring columns at most 1 block apart, and 3 or more (cliffs).
MINIMUM_GENTLE_SHARE :: 0.8
MINIMUM_CLIFF_SHARE :: 0.005

Terrain_Statistics :: struct {
	columns:           int,
	land:              int,
	pairs:             int,
	gentle_pairs:      int,
	cliff_pairs:       int,
	river_bed_reached: bool,
	lowest:            i32,
	highest:           i32,
	biome_columns:     [SHIPPED_BIOME_COUNT]int,
}

record_neighbour_pair :: proc(statistics: ^Terrain_Statistics, height, neighbour: i32) {
	step := abs(height - neighbour)
	statistics.pairs += 1
	statistics.gentle_pairs += step <= 1 ? 1 : 0
	statistics.cliff_pairs += step >= 3 ? 1 : 0
}

record_terrain_column :: proc(statistics: ^Terrain_Statistics, generator: ^Generator, x, z: i32) -> i32 {
	column := sample_column(generator, x, z)
	statistics.columns += 1
	statistics.land += column.height >= SEA_LEVEL ? 1 : 0
	statistics.lowest = min(statistics.lowest, column.height)
	statistics.highest = max(statistics.highest, column.height)
	statistics.biome_columns[column.biome] += 1
	if column.height == RIVER_BED_HEIGHT && !statistics.river_bed_reached {
		statistics.river_bed_reached = river_strength(river_distance(generator.seeds, x, z)) == 1
	}
	return column.height
}

// Each column is compared with its west and north neighbours; row keeps
// the previous row's heights to the right of the current column.
measure_terrain :: proc(generator: ^Generator) -> Terrain_Statistics {
	statistics := Terrain_Statistics{lowest = max(i32), highest = min(i32)}
	row := make([]i32, TERRAIN_SAMPLE_SIZE, context.temp_allocator)
	half := i32(TERRAIN_SAMPLE_SIZE / 2)
	for z in i32(0) ..< TERRAIN_SAMPLE_SIZE {
		for x in i32(0) ..< TERRAIN_SAMPLE_SIZE {
			height := record_terrain_column(&statistics, generator, x - half, z - half)
			if x > 0 {
				record_neighbour_pair(&statistics, height, row[x - 1])
			}
			if z > 0 {
				record_neighbour_pair(&statistics, height, row[x])
			}
			row[x] = height
		}
	}
	return statistics
}

@(test)
test_terrain_has_lowlands_slopes_cliffs_and_rivers :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		generator := make_test_generator(seed)
		statistics := measure_terrain(&generator)
		land := f64(statistics.land) / f64(statistics.columns)
		gentle := f64(statistics.gentle_pairs) / f64(statistics.pairs)
		cliffs := f64(statistics.cliff_pairs) / f64(statistics.pairs)
		log.infof("seed %d: land %.3f, gentle %.3f, cliffs %.4f, heights %d to %d, biome columns %v", seed, land, gentle, cliffs, statistics.lowest, statistics.highest, statistics.biome_columns)
		testing.expectf(t, land >= MINIMUM_LAND_FRACTION && land <= MAXIMUM_LAND_FRACTION, "seed %d land fraction %.3f", seed, land)
		testing.expectf(t, gentle >= MINIMUM_GENTLE_SHARE, "seed %d gentle share %.3f", seed, gentle)
		testing.expectf(t, cliffs >= MINIMUM_CLIFF_SHARE, "seed %d cliff share %.4f", seed, cliffs)
		testing.expectf(t, statistics.river_bed_reached, "seed %d has no river bed", seed)
		testing.expect(t, statistics.lowest >= TERRAIN_MINIMUM_HEIGHT && statistics.highest <= TERRAIN_MAXIMUM_HEIGHT)
	}
}

temperate_climate :: proc(relative_height: i32, moisture: f32) -> Climate {
	return Climate{relative_height = relative_height, moisture = moisture, temperature = ORIGIN_TEMPERATURE}
}

@(test)
test_beach_and_mountain_biomes_cover_their_heights :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	beach := find_biome_index(generator.biomes, "beach")
	mountains := find_biome_index(generator.biomes, "mountains")
	hills := find_biome_index(generator.biomes, "hills")
	highland := find_biome_index(generator.biomes, "highland")
	// Temperate, and short of the wetland's moisture.
	for moisture in ([3]f32{-0.3, 0, 0.5}) {
		testing.expect_value(t, select_biome(generator.biomes, temperate_climate(0, moisture)), beach)
		testing.expect_value(t, select_biome(generator.biomes, temperate_climate(1, moisture)), beach)
		testing.expect(t, select_biome(generator.biomes, temperate_climate(2, moisture)) != beach)
		testing.expect(t, select_biome(generator.biomes, temperate_climate(-1, moisture)) != beach)
		testing.expect_value(t, select_biome(generator.biomes, temperate_climate(47, moisture)), moisture < 0 ? hills : highland)
		testing.expect_value(t, select_biome(generator.biomes, temperate_climate(48, moisture)), mountains)
		testing.expect_value(t, select_biome(generator.biomes, temperate_climate(TERRAIN_MAXIMUM_HEIGHT - SEA_LEVEL, moisture)), mountains)
	}
	testing.expect_value(t, generator.biomes[beach].top_block, generator.blocks.sand)
	testing.expect_value(t, generator.biomes[mountains].top_block, generator.blocks.stone)
	testing.expect_value(t, generator.biomes[beach].definition.tree_density, 0)
	testing.expect_value(t, generator.biomes[mountains].definition.tree_density, 0)
}

@(test)
test_purpose_seeds_differ :: proc(t: ^testing.T) {
	seeds := derive_purpose_seeds(DEFAULT_WORLD_SEED)
	for first in Generation_Purpose {
		for second in Generation_Purpose {
			testing.expect(t, first == second || seeds[first] != seeds[second])
		}
	}
	testing.expect(t, derive_purpose_seeds(1)[.Caves] != seeds[.Caves])
}

// Surface, underground, sky and deep chunks, at negative coordinates too.
@(rodata)
test_chunk_coordinates := [?]Chunk_Coordinate{{0, 1, 0}, {0, 0, 0}, {-3, 1, 5}, {7, 1, -9}, {2, -1, -7}, {0, 3, 0}, {1, -5, 1}, {-20, 1, 13}}

@(test)
test_generation_is_deterministic :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		generator := make_test_generator(seed)
		other_instance := make_test_generator(seed)
		for coordinate in test_chunk_coordinates {
			first := generate_chunk(&generator, coordinate, context.temp_allocator)
			second := generate_chunk(&other_instance, coordinate, context.temp_allocator)
			testing.expectf(t, slice.equal(first.chunk.blocks[:], second.chunk.blocks[:]), "chunk %v differs between runs", coordinate)
			testing.expect(t, slice.equal(first.veins[:], second.veins[:]))
		}
	}
}

@(test)
test_seeds_give_different_worlds :: proc(t: ^testing.T) {
	first := make_test_generator(1)
	second := make_test_generator(2)
	a := generate_chunk(&first, {0, 1, 0}, context.temp_allocator)
	b := generate_chunk(&second, {0, 1, 0}, context.temp_allocator)
	testing.expect(t, !slice.equal(a.chunk.blocks[:], b.chunk.blocks[:]))
}

// Loads the 26 surrounding chunks into a world first, then generates the
// centre, and compares with the centre generated on its own.
@(test)
test_generation_ignores_loaded_neighbours :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	centre := Chunk_Coordinate{-1, 1, 2}
	alone := generate_chunk(&generator, centre, context.temp_allocator)
	world: World
	defer destroy_world(&world)
	for y in i32(-1) ..= 1 {
		for z in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				coordinate := centre + {x, y, z}
				if coordinate != centre {
					generated := generate_chunk(&generator, coordinate)
					world.chunks[coordinate] = generated.chunk
					delete(generated.veins)
					delete(generated.outcrops)
					delete(generated.crates)
				}
			}
		}
	}
	after := generate_chunk(&generator, centre, context.temp_allocator)
	testing.expect(t, slice.equal(alone.chunk.blocks[:], after.chunk.blocks[:]))
}

// The grid of one chunk reaches one column into its neighbour. That column
// must be identical to the neighbour's own sample of it.
@(test)
test_columns_agree_across_chunk_borders :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	west := new(Column_Grid, context.temp_allocator)
	east := new(Column_Grid, context.temp_allocator)
	for chunk_x in i32(-4) ..< 4 {
		sample_column_grid(&generator, {chunk_x, 0, 1}, west)
		sample_column_grid(&generator, {chunk_x + 1, 0, 1}, east)
		for z in i32(0) ..< CHUNK_SIZE {
			testing.expect_value(t, grid_column(west, CHUNK_SIZE, z), grid_column(east, 0, z))
			testing.expect_value(t, grid_column(east, -1, z), grid_column(west, CHUNK_SIZE - 1, z))
			step := abs(grid_column(west, CHUNK_SIZE - 1, z).height - grid_column(east, 0, z).height)
			testing.expectf(t, step <= MAXIMUM_TEST_HEIGHT_STEP, "height step %d across the border at chunk x %d", step, chunk_x)
		}
	}
}

// The generated surface follows the column function on both sides of a border.
@(test)
test_generated_surface_matches_column_function :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	for chunk_z in i32(-2) ..< 2 {
		for chunk_x in i32(-2) ..< 2 {
			coordinate := Chunk_Coordinate{chunk_x, 1, chunk_z}
			generated := generate_chunk(&generator, coordinate, context.temp_allocator)
			for border in ([2]i32{0, CHUNK_SIZE - 1}) {
				for along in i32(0) ..< CHUNK_SIZE {
					expect_column_surface(t, &generator, generated.chunk, {border, 0, along})
					expect_column_surface(t, &generator, generated.chunk, {along, 0, border})
				}
			}
		}
	}
}

// Where the surface lies inside the chunk, the block above it is not solid
// terrain and the surface block itself is not air.
expect_column_surface :: proc(t: ^testing.T, generator: ^Generator, chunk: ^Chunk, local: Local_Coordinate) {
	origin := chunk_origin(chunk.coordinate)
	height := terrain_height(generator.seeds, origin.x + local.x, origin.z + local.z)
	surface_y := height - origin.y
	if surface_y < 0 || surface_y >= CHUNK_SIZE - 1 {
		return
	}
	registry := make_test_registry()
	surface := chunk_get_block(chunk, {local.x, surface_y, local.z})
	above := chunk_get_block(chunk, {local.x, surface_y + 1, local.z})
	testing.expect(t, surface != AIR_BLOCK)
	is_tree := block_is_tree_log(generator.tree_blocks, above) || block_is_tree_leaves(generator.tree_blocks, above)
	is_feature := is_tree || above == generator.blocks.stone
	testing.expectf(t, !block_is_solid(registry, above) || is_feature, "solid block %d above the surface at %v", above, local)
}

// A tree rooted in the last column of a chunk reaches into the next chunk:
// both chunks hold exactly the tree's blocks wherever the tree is.
@(test)
test_tree_across_border_matches_from_both_chunks :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	tree, found := find_border_tree(&generator)
	testing.expect(t, found, "no tree rooted in a border column near the origin")
	if !found {
		return
	}
	box := tree_box(tree)
	cache: map[Chunk_Coordinate]^Chunk
	defer delete(cache)
	leaves_in_neighbour := 0
	for y in box.minimum.y ..= box.maximum.y {
		for z in box.minimum.z ..= box.maximum.z {
			for x in box.minimum.x ..= box.maximum.x {
				position := World_Coordinate{x, y, z}
				block := cached_block_at(&generator, &cache, position)
				species := generator.species[tree.species]
				if tree_trunk_contains(tree, position) {
					testing.expect_value(t, block, species.log_block)
				} else if tree_leaves_contain(tree, position) {
					testing.expectf(t, block != AIR_BLOCK, "air inside the leaves at %v", position)
					if world_to_chunk_coordinate(position).x != world_to_chunk_coordinate(tree.root).x && block == species.leaves_block {
						leaves_in_neighbour += 1
					}
				}
			}
		}
	}
	testing.expect(t, leaves_in_neighbour > 0)
}

generated_block_at :: proc(generator: ^Generator, position: World_Coordinate) -> Block_Id {
	generated := generate_chunk(generator, world_to_chunk_coordinate(position), context.temp_allocator)
	return chunk_get_block(generated.chunk, world_to_local_coordinate(position))
}

// Generates each chunk once, in whatever order positions are asked for.
cached_block_at :: proc(generator: ^Generator, cache: ^map[Chunk_Coordinate]^Chunk, position: World_Coordinate) -> Block_Id {
	coordinate := world_to_chunk_coordinate(position)
	if coordinate not_in cache {
		cache[coordinate] = generate_chunk(generator, coordinate, context.temp_allocator).chunk
	}
	return chunk_get_block(cache[coordinate], world_to_local_coordinate(position))
}

find_border_tree :: proc(generator: ^Generator) -> (tree: Tree, found: bool) {
	for cell_z in i32(-60) ..< 60 {
		for cell_x in i32(-60) ..< 60 {
			veins := veins_near_box(generator, {cell_x, cell_z} * TREE_CELL_SIZE - FEATURE_REACH, ({cell_x, cell_z} + 1) * TREE_CELL_SIZE + FEATURE_REACH, context.temp_allocator)
			candidate, exists := tree_in_cell(generator, {cell_x, cell_z}, veins[:])
			if exists && candidate.crown != .None && candidate.root.x %% CHUNK_SIZE == CHUNK_SIZE - 1 {
				return candidate, true
			}
		}
	}
	return {}, false
}

@(test)
test_vein_lookup_same_from_each_overlapping_chunk :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	checked := 0
	for region_z in i32(-2) ..< 2 {
		for region_x in i32(-2) ..< 2 {
			for vein in region_veins(&generator, {region_x, region_z}, context.temp_allocator) {
				checked += expect_vein_in_every_overlapping_column(t, &generator, vein)
			}
		}
	}
	testing.expect(t, checked > 16)
}

// Returns how many chunk columns the vein overlaps.
expect_vein_in_every_overlapping_column :: proc(t: ^testing.T, generator: ^Generator, vein: Vein) -> int {
	first := world_to_chunk_coordinate(vein.centre - vein.radius)
	last := world_to_chunk_coordinate(vein.centre + vein.radius)
	world: World
	defer destroy_world(&world)
	count := 0
	for column_z in first.z ..= last.z {
		for column_x in first.x ..= last.x {
			column := Chunk_Column{column_x, column_z}
			if !vein_overlaps_column(vein, column) {
				continue
			}
			found := column_veins(generator, column, context.temp_allocator)
			testing.expectf(t, slice.contains(found[:], vein), "vein %v missing from column %v", vein.id, column)
			register_column_veins(&world, column, found[:])
			testing.expect(t, slice.contains(veins_of_column(&world, column, context.temp_allocator), vein))
			count += 1
		}
	}
	registered := 0
	for candidate in world.veins {
		registered += candidate.id == vein.id ? 1 : 0
	}
	testing.expect_value(t, registered, 1)
	return count
}

@(test)
test_region_vein_counts_within_frequency :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		generator := make_test_generator(seed)
		for region_z in i32(-6) ..< 6 {
			for region_x in i32(-6) ..< 6 {
				expect_region_vein_counts(t, &generator, {region_x, region_z})
			}
		}
	}
}

expect_region_vein_counts :: proc(t: ^testing.T, generator: ^Generator, region: Region_Coordinate) {
	veins := region_veins(generator, region, context.temp_allocator)
	for size_class, class_index in generator.veins.size_classes {
		count: i32 = 0
		for vein in veins {
			count += vein.size_class == class_index ? 1 : 0
		}
		minimum := size_class.minimum_per_region
		if region_centre_distance(region) < f64(size_class.minimum_distance) {
			minimum = 0
		}
		maximum := region_centre_distance(region) < f64(size_class.minimum_distance) ? 0 : size_class.maximum_per_region
		testing.expectf(t, count >= minimum && count <= maximum, "region %v has %d %s veins", region, count, size_class.id)
	}
	for vein in veins {
		origin := region_origin(region)
		inside := vein.centre.x - vein.radius > origin.x && vein.centre.x + vein.radius < origin.x + REGION_SIZE - 1
		inside &&= vein.centre.z - vein.radius > origin.y && vein.centre.z + vein.radius < origin.y + REGION_SIZE - 1
		testing.expectf(t, inside, "vein %v leaves its region", vein.id)
		total: i64 = 0
		for amount in vein.remaining {
			total += amount
		}
		testing.expect(t, total >= generator.veins.size_classes[vein.size_class].minimum_units * 99 / 100)
	}
}

// Outcrop blocks on the surface of the vein's centre column.
@(test)
test_vein_outcrop_on_surface :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	veins := region_veins(&generator, {0, 0}, context.temp_allocator)
	testing.expect(t, len(veins) > 0)
	for vein in veins {
		block := generated_block_at(&generator, vein.centre)
		testing.expect_value(t, block, outcrop_block(&generator, vein, vein.centre.x, vein.centre.z))
	}
}

@(test)
test_spawn_finder_meets_requirements :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		generator := make_test_generator(seed)
		spawn, found := find_spawn(&generator)
		testing.expectf(t, found, "no spawn for seed %d", seed)
		if !found {
			continue
		}
		log.infof("seed %d: spawn %v", seed, spawn)
		testing.expect(t, spawn.y > SEA_LEVEL)
		testing.expect_value(t, spawn.y, terrain_height(generator.seeds, spawn.x, spawn.z))
		findings := evaluate_spawn(&generator, {spawn.x, spawn.z})
		testing.expectf(t, spawn_satisfied(findings), "seed %d spawn %v findings %v", seed, spawn, findings)
	}
}

@(test)
test_spawn_ring_candidates_cover_the_ring :: proc(t: ^testing.T) {
	seen: map[[2]i32]bool
	defer delete(seen)
	for index in i32(0) ..< 16 {
		candidate := spawn_ring_candidate(2, index) / SPAWN_SEARCH_STEP
		testing.expect_value(t, max(abs(candidate.x), abs(candidate.y)), 2)
		seen[candidate] = true
	}
	testing.expect_value(t, len(seen), 16)
}
