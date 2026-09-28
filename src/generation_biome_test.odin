package game

import "core:log"
import "core:slice"
import "core:testing"

// The climate biomes of work item 0058.

// Every biome must show up on each test seed within this square around the
// origin, sampled every BIOME_SAMPLE_STRIDE blocks.
BIOME_SAMPLE_SIZE :: 4096
BIOME_SAMPLE_STRIDE :: 32

@(test)
test_temperature_is_temperate_at_the_origin :: proc(t: ^testing.T) {
	testing.expect(t, abs(latitude_temperature(0) - ORIGIN_TEMPERATURE) < 1e-9)
	for seed in TEST_SEEDS {
		seeds := derive_purpose_seeds(seed)
		origin := terrain_temperature(seeds, 0, 0, SEA_LEVEL)
		testing.expectf(t, abs(origin - ORIGIN_TEMPERATURE) <= TEMPERATURE_NOISE_AMPLITUDE, "seed %d origin temperature %v", seed, origin)
		north := terrain_temperature(seeds, 0, -1500, SEA_LEVEL)
		south := terrain_temperature(seeds, 0, 1500, SEA_LEVEL)
		testing.expectf(t, north < origin && north < -0.45, "seed %d north temperature %v", seed, north)
		testing.expectf(t, south > origin && south > 0.3, "seed %d south temperature %v", seed, south)
	}
}

@(test)
test_temperature_falls_with_height :: proc(t: ^testing.T) {
	seeds := derive_purpose_seeds(DEFAULT_WORLD_SEED)
	for x in ([3]i32{0, 700, -1300}) {
		sea := terrain_temperature(seeds, x, 200, SEA_LEVEL)
		mountain := terrain_temperature(seeds, x, 200, SEA_LEVEL + 60)
		below_sea := terrain_temperature(seeds, x, 200, SEA_LEVEL - 10)
		testing.expectf(t, mountain < sea, "mountain %v not colder than sea level %v", mountain, sea)
		testing.expect_value(t, below_sea, sea)
	}
}

biome_climate :: proc(relative_height: i32, moisture, temperature: f32) -> Climate {
	return Climate{relative_height = relative_height, moisture = moisture, temperature = temperature}
}

expect_biome :: proc(t: ^testing.T, generator: ^Generator, climate: Climate, id: string, location := #caller_location) {
	selected := select_biome(generator.biomes, climate)
	testing.expectf(t, generator.biomes[selected].definition.id == id, "climate %v gives %s, not %s", climate, generator.biomes[selected].definition.id, id, loc = location)
}

@(test)
test_climate_chooses_biomes :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	expect_biome(t, &generator, biome_climate(-5, 0, -0.9), "lake")
	expect_biome(t, &generator, biome_climate(60, 0, 0.9), "mountains")
	expect_biome(t, &generator, biome_climate(10, 0, -0.6), "cold_barrens")
	expect_biome(t, &generator, biome_climate(30, 0.4, 0), "highland")
	expect_biome(t, &generator, biome_climate(30, -0.4, 0), "hills")
	expect_biome(t, &generator, biome_climate(12, -0.5, 0.6), "badlands")
	expect_biome(t, &generator, biome_climate(10, -0.1, 0.5), "steppe")
	expect_biome(t, &generator, biome_climate(2, 0.8, 0.1), "wetland")
	expect_biome(t, &generator, biome_climate(1, -0.6, 0.5), "tar_flats")
	expect_biome(t, &generator, biome_climate(10, -0.6, 0.2), "desert")
	expect_biome(t, &generator, biome_climate(0, 0, 0.1), "beach")
	expect_biome(t, &generator, biome_climate(3, 0, 0.1), "coastal_dunes")
	expect_biome(t, &generator, biome_climate(10, 0.5, 0.1), "forest")
	expect_biome(t, &generator, biome_climate(10, 0, 0.1), "plains")
	// Too hot for the forest, too wet for the steppe.
	expect_biome(t, &generator, biome_climate(10, 0.5, 0.8), "plains")
}

@(test)
test_every_biome_is_reachable :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		generator := make_test_generator(seed)
		counts: [SHIPPED_BIOME_COUNT]int
		half := i32(BIOME_SAMPLE_SIZE / 2)
		for z := -half; z < half; z += BIOME_SAMPLE_STRIDE {
			for x := -half; x < half; x += BIOME_SAMPLE_STRIDE {
				counts[sample_column(&generator, x, z).biome] += 1
			}
		}
		log.infof("seed %d: biome columns %v", seed, counts)
		for count, index in counts {
			testing.expectf(t, count > 0, "seed %d has no %s", seed, generator.biomes[index].definition.id)
		}
	}
}

@(test)
test_badlands_filler_alternates :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	badlands := generator.biomes[find_biome_index(generator.biomes, "badlands")]
	red_rock := test_block(make_test_registry(), "red_rock")
	pale_rock := test_block(make_test_registry(), "pale_rock")
	testing.expect_value(t, badlands.filler_block, red_rock)
	testing.expect_value(t, badlands.layer_block, pale_rock)
	testing.expect_value(t, badlands.definition.layer_thickness, 4)
	column := Column_Sample{height = 9, topsoil_depth = 5, biome = find_biome_index(generator.biomes, "badlands")}
	testing.expect_value(t, terrain_block(&generator, column, 9), red_rock)
	testing.expect_value(t, terrain_block(&generator, column, 8), red_rock)
	for y in i32(5) ..= 7 {
		testing.expect_value(t, terrain_block(&generator, column, y), pale_rock)
	}
	testing.expect_value(t, terrain_block(&generator, column, 4), generator.blocks.stone)
	testing.expect_value(t, filler_block_at(badlands, -1), pale_rock)
	testing.expect_value(t, filler_block_at(badlands, -4), pale_rock)
	testing.expect_value(t, filler_block_at(badlands, -5), red_rock)
	plains := generator.biomes[find_biome_index(generator.biomes, "plains")]
	for y in i32(-8) ..= 8 {
		testing.expect_value(t, filler_block_at(plains, y), plains.filler_block)
	}
}

@(test)
test_biome_validation_rejects_bad_climate_fields :: proc(t: ^testing.T) {
	valid := Biome_Definition {
		id                  = "test",
		name_key            = "biome_test",
		minimum_height      = 0,
		maximum_height      = 10,
		minimum_moisture    = -1,
		maximum_moisture    = 1,
		minimum_temperature = 0.2,
		maximum_temperature = 0.5,
		layer_block         = "stone",
		layer_thickness     = 1,
	}
	testing.expect_value(t, validate_biome_definition(valid), "")
	upside_down := valid
	upside_down.minimum_temperature = 0.6
	testing.expect(t, validate_biome_definition(upside_down) != "")
	zero_layer := valid
	zero_layer.layer_thickness = 0
	testing.expect(t, validate_biome_definition(zero_layer) != "")
	no_layer := zero_layer
	no_layer.layer_block = ""
	testing.expect_value(t, validate_biome_definition(no_layer), "")
	// One bound alone leaves the other side open.
	only_maximum := valid
	only_maximum.minimum_temperature = nil
	only_maximum.maximum_temperature = -0.9
	testing.expect_value(t, validate_biome_definition(only_maximum), "")
	testing.expect(t, biome_accepts(only_maximum, biome_climate(5, 0, -1)))
	testing.expect(t, !biome_accepts(only_maximum, biome_climate(5, 0, -0.8)))
}

@(test)
test_biomes_file_reads_optional_temperatures :: proc(t: ^testing.T) {
	data := `biomes = [{id = "a", name_key = "biome_a", maximum_temperature = -0.5, map_color = [1, 2, 3]} {id = "b", name_key = "biome_b"}]`
	file, error := parse_biomes_file(transmute([]byte)data, context.temp_allocator)
	testing.expect_value(t, error, nil)
	if len(file.biomes) != 2 {
		testing.fail(t)
		return
	}
	testing.expect_value(t, file.biomes[0].minimum_temperature, nil)
	testing.expect_value(t, file.biomes[0].maximum_temperature.? or_else 0, -0.5)
	testing.expect_value(t, file.biomes[0].map_color, [3]u8{1, 2, 3})
	minimum, maximum := temperature_range(file.biomes[1])
	testing.expect_value(t, minimum, -1)
	testing.expect_value(t, maximum, 1)
}

// The map tints the block colour with the biome's, half and half, before
// the height shading.
@(test)
test_map_biome_tint :: proc(t: ^testing.T) {
	colors := []Ui_Color{{0, 0, 0, 255}, {100, 100, 100, 255}}
	tint := Ui_Color{200, 0, 50, 255}
	unknown := Surface_Cell{height = UNKNOWN_SURFACE_HEIGHT}
	testing.expect_value(t, tinted_surface_color(unknown, colors, tint, MAP_BIOME_BLEND), MAP_UNEXPLORED_COLOR)
	cell := Surface_Cell{block = 1, height = SEA_LEVEL}
	testing.expect_value(t, tinted_surface_color(cell, colors, tint, MAP_BIOME_BLEND), shade_by_height({150, 50, 75, 255}, SEA_LEVEL))
	testing.expect_value(t, tinted_surface_color(cell, colors, tint, 0), surface_color(cell, colors))
	testing.expect_value(t, tinted_surface_color(cell, colors, tint, MAP_BIOME_BLEND), tinted_surface_color(cell, colors, tint, MAP_BIOME_BLEND))
}

// A pan keeps the biomes of the pixels both frames cover, and the result
// equals sampling the new frame afresh.
@(test)
test_map_biomes_survive_a_pan :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	view: Map_View
	defer destroy_map_view(&view)
	first := Map_Frame{origin = {-512, -512}, blocks_per_pixel = 16, size = 64}
	update_map_biomes(&view, first, &generator)
	panned := first
	panned.origin += {16 * 3, -16}
	update_map_biomes(&view, panned, &generator)
	fresh: Map_View
	defer destroy_map_view(&fresh)
	update_map_biomes(&fresh, panned, &generator)
	testing.expect_value(t, view.biome_frame, panned)
	testing.expect(t, slice.equal(view.biomes[:], fresh.biomes[:]))
	distinct_biomes: map[int]bool
	defer delete(distinct_biomes)
	for biome in view.biomes {
		distinct_biomes[biome] = true
	}
	testing.expect(t, len(distinct_biomes) > 1)
}

// Only explored pixels mark their biome as shown.
@(test)
test_map_marks_biomes_on_explored_pixels :: proc(t: ^testing.T) {
	frame := Map_Frame{origin = {0, 0}, blocks_per_pixel = 1, size = 2}
	pixels := make([]Ui_Color, 4, context.temp_allocator)
	surfaces: map[Chunk_Column]Column_Surface
	defer delete(surfaces)
	column: Column_Surface
	for &cell in column {
		cell = {height = UNKNOWN_SURFACE_HEIGHT}
	}
	column[0] = {block = 1, height = SEA_LEVEL}
	surfaces[{0, 0}] = column
	shown := make([]bool, 3, context.temp_allocator)
	layer := Map_Biome_Layer {
		biomes = []int{2, 1, 1, 1},
		colors = []Ui_Color{{}, {10, 10, 10, 255}, {20, 20, 20, 255}},
		shown  = shown,
	}
	paint_map_surface(pixels, frame, surfaces, []Ui_Color{{}, {100, 100, 100, 255}}, layer)
	testing.expect_value(t, shown[2], true)
	testing.expect_value(t, shown[1], false)
	testing.expect_value(t, pixels[1], MAP_UNEXPLORED_COLOR)
}

// Ground cover (work item 0082).

// Surface chunks around the origin, two chunks high so that cover cells
// just above a chunk's top layer are seen in the chunk above.
GROUND_COVER_CHUNK_REACH :: 3
// Columns sampled every GROUND_COVER_SAMPLE_STRIDE blocks over a square
// of GROUND_COVER_SAMPLE_SIZE for the share per biome, and the fewest
// samples a biome needs to be checked.
GROUND_COVER_SAMPLE_SIZE :: 2048
GROUND_COVER_SAMPLE_STRIDE :: 8
GROUND_COVER_MINIMUM_SAMPLES :: 1000
GROUND_COVER_SHARE_TOLERANCE :: 0.03

// The share of a biome's columns its cover list covers on its top block.
expected_cover_share :: proc(biome: Biome) -> f64 {
	share: f64 = 0
	for entry in biome.ground_cover {
		if slice.contains(entry.on, biome.top_block) {
			share += f64(entry.chance)
		}
	}
	return share
}

column_cover_pick :: proc(generator: ^Generator, column: Column_Sample, x, z: i32) -> Block_Id {
	biome := column_biome(generator, column)
	return ground_cover_at(biome.ground_cover, biome.top_block, generator.seeds[.Ground_Cover], x, z)
}

// Every cross in a generated chunk stands in the cell above its column's
// surface, on a listed top block of dry land outside vein footprints, and
// is the block the column function picks; where the pick is cover and the
// cell is air, the column lies in a vein footprint. Chunks on both sides
// of every border agree with the column function, so they agree with
// each other.
@(test)
test_ground_cover_stands_on_listed_top_blocks :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	cache: map[Chunk_Coordinate]^Chunk
	defer delete(cache)
	covered := 0
	for chunk_z in i32(-GROUND_COVER_CHUNK_REACH) ..< GROUND_COVER_CHUNK_REACH {
		for chunk_x in i32(-GROUND_COVER_CHUNK_REACH) ..< GROUND_COVER_CHUNK_REACH {
			for chunk_y in i32(1) ..= 2 {
				coordinate := Chunk_Coordinate{chunk_x, chunk_y, chunk_z}
				generated := generate_chunk(&generator, coordinate, context.temp_allocator)
				cache[coordinate] = generated.chunk
				covered += expect_chunk_cover(t, &generator, registry, &cache, generated)
			}
		}
	}
	testing.expectf(t, covered > 1000, "only %d covered columns", covered)
}

expect_chunk_cover :: proc(t: ^testing.T, generator: ^Generator, registry: Block_Registry, cache: ^map[Chunk_Coordinate]^Chunk, generated: Generated_Chunk) -> int {
	origin := chunk_origin(generated.chunk.coordinate)
	covered := 0
	for index in 0 ..< CHUNK_BLOCK_COUNT {
		block := generated.chunk.blocks[index]
		local := index_to_local(index)
		position := origin + World_Coordinate(local)
		column := sample_column(generator, position.x, position.z)
		pick := column_cover_pick(generator, column, position.x, position.z)
		in_footprint := column_in_surface_vein_footprint(generated.veins[:], position.x, position.z)
		if block_shape(registry, block) == .Cross {
			covered += 1
			testing.expectf(t, position.y == column.height + 1, "cover at %v above surface %d", position, column.height)
			testing.expectf(t, block == pick, "cover %d at %v, the column picks %d", block, position, pick)
			testing.expectf(t, column.height >= SEA_LEVEL, "cover at %v under sea level", position)
			testing.expectf(t, !in_footprint, "cover at %v in a vein footprint", position)
			below := cached_block_at(generator, cache, position - {0, 1, 0})
			testing.expectf(t, below == column_biome(generator, column).top_block, "cover at %v stands on %d", position, below)
		} else if block == AIR_BLOCK && position.y == column.height + 1 && pick != AIR_BLOCK {
			testing.expectf(t, in_footprint, "no cover at %v, the column picks %d", position, pick)
		}
	}
	return covered
}

// A generated chunk lists deep veins too, whose discs lie underground.
column_in_surface_vein_footprint :: proc(veins: []Vein, x, z: i32) -> bool {
	for vein in veins {
		if vein.id.layer == .Surface && column_in_disc(vein.centre, vein.radius, x, z) {
			return true
		}
	}
	return false
}

// No cover on any footprint column of the veins near the origin, where
// the outcrops show.
@(test)
test_no_ground_cover_in_a_vein_footprint :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	cache: map[Chunk_Coordinate]^Chunk
	defer delete(cache)
	veins := region_veins(&generator, {0, 0}, context.temp_allocator)
	testing.expect(t, len(veins) > 0)
	picked := 0
	for vein in veins {
		for z in vein.centre.z - vein.radius ..= vein.centre.z + vein.radius {
			for x in vein.centre.x - vein.radius ..= vein.centre.x + vein.radius {
				if !column_in_disc(vein.centre, vein.radius, x, z) {
					continue
				}
				column := sample_column(&generator, x, z)
				picked += column_cover_pick(&generator, column, x, z) != AIR_BLOCK ? 1 : 0
				above := cached_block_at(&generator, &cache, {x, column.height + 1, z})
				testing.expectf(t, block_shape(registry, above) != .Cross, "cover over the vein at %d %d", x, z)
			}
		}
	}
	// The footprints would have held cover without the rule.
	testing.expect(t, picked > 0)
}

// Over a sample of columns, each biome's covered share is the sum of the
// chances of its entries that stand on its top block.
@(test)
test_ground_cover_share_per_biome :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	samples, covered: [SHIPPED_BIOME_COUNT]int
	half := i32(GROUND_COVER_SAMPLE_SIZE / 2)
	for z := -half; z < half; z += GROUND_COVER_SAMPLE_STRIDE {
		for x := -half; x < half; x += GROUND_COVER_SAMPLE_STRIDE {
			column := sample_column(&generator, x, z)
			samples[column.biome] += 1
			covered[column.biome] += column_cover_pick(&generator, column, x, z) != AIR_BLOCK ? 1 : 0
		}
	}
	plains := find_biome_index(generator.biomes, "plains")
	testing.expect(t, samples[plains] >= GROUND_COVER_MINIMUM_SAMPLES)
	testing.expect(t, abs(expected_cover_share(generator.biomes[plains]) - 0.34) < 1e-6)
	testing.expect_value(t, len(generator.biomes[find_biome_index(generator.biomes, "cold_barrens")].ground_cover), 0)
	for biome, index in generator.biomes {
		if samples[index] < GROUND_COVER_MINIMUM_SAMPLES {
			continue
		}
		share := f64(covered[index]) / f64(samples[index])
		expected := expected_cover_share(biome)
		testing.expectf(t, abs(share - expected) <= GROUND_COVER_SHARE_TOLERANCE, "%s covers %v of %d columns, expected %v", biome.definition.id, share, samples[index], expected)
	}
}

// The landing pad stamp runs after the cover and clears its cells.
@(test)
test_no_ground_cover_on_the_landing_pad :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	surface, found := find_covered_surface(&generator, registry)
	testing.expect(t, found, "no covered column near the origin")
	if !found {
		return
	}
	generator.landing_pad = Landing_Pad_Site{present = true, centre = surface}
	for z in i32(-LANDING_PAD_HALF_WIDTH) ..= LANDING_PAD_HALF_WIDTH {
		for x in i32(-LANDING_PAD_HALF_WIDTH) ..= LANDING_PAD_HALF_WIDTH {
			testing.expect_value(t, generated_block_at(&generator, surface + {x, 1, z}), AIR_BLOCK)
		}
	}
}

// The surface block of a column along the x axis that generation covers.
find_covered_surface :: proc(generator: ^Generator, registry: Block_Registry) -> (surface: World_Coordinate, found: bool) {
	for x in i32(0) ..< 256 {
		column := sample_column(generator, x, 0)
		above := generated_block_at(generator, {x, column.height + 1, 0})
		if block_shape(registry, above) == .Cross {
			return {x, column.height, 0}, true
		}
	}
	return {}, false
}

@(test)
test_ground_cover_validation :: proc(t: ^testing.T) {
	registry := make_test_registry()
	biome := Biome_Definition {
		id           = "test",
		ground_cover = []Biome_Cover_Definition{{block = "grass_tuft", chance = 0.5, on = []string{"grass", "mud"}}},
	}
	cover, problem := resolve_biome_ground_cover(biome, registry, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, cover[0].block, test_block(registry, "grass_tuft"))
	testing.expect_value(t, cover[0].on[1], test_block(registry, "mud"))
	not_a_cross := biome
	not_a_cross.ground_cover = []Biome_Cover_Definition{{block = "stone", chance = 0.5, on = []string{"grass"}}}
	_, problem = resolve_biome_ground_cover(not_a_cross, registry, context.temp_allocator)
	testing.expect(t, problem != "")
	unknown_on := biome
	unknown_on.ground_cover = []Biome_Cover_Definition{{block = "grass_tuft", chance = 0.5, on = []string{"lawn"}}}
	_, problem = resolve_biome_ground_cover(unknown_on, registry, context.temp_allocator)
	testing.expect(t, problem != "")
	unknown_block := biome
	unknown_block.ground_cover = []Biome_Cover_Definition{{block = "moss", chance = 0.5, on = []string{"grass"}}}
	_, problem = resolve_biome_ground_cover(unknown_block, registry, context.temp_allocator)
	testing.expect(t, problem != "")
	testing.expect(t, ground_cover_chances_valid(biome.ground_cover))
	testing.expect(t, !ground_cover_chances_valid([]Biome_Cover_Definition{{chance = 1.5}}))
	testing.expect(t, !ground_cover_chances_valid([]Biome_Cover_Definition{{chance = 0.6}, {chance = 0.6}}))
}

// Entries in order against the running sum of their chances.
@(test)
test_choose_ground_cover_by_running_sum :: proc(t: ^testing.T) {
	cover := []Biome_Cover{{block = 7, chance = 0.25}, {block = 9, chance = 0.05}}
	first, found := choose_ground_cover(cover, 0.1)
	testing.expect(t, found)
	testing.expect_value(t, first.block, 7)
	second, _ := choose_ground_cover(cover, 0.27)
	testing.expect_value(t, second.block, 9)
	_, found = choose_ground_cover(cover, 0.31)
	testing.expect(t, !found)
	// The pick must stand on the top block.
	on := []Block_Id{3}
	listed := []Biome_Cover{{block = 7, chance = 1, on = on}}
	testing.expect_value(t, ground_cover_at(listed, 3, 1, 0, 0), 7)
	testing.expect_value(t, ground_cover_at(listed, 4, 1, 0, 0), AIR_BLOCK)
}
