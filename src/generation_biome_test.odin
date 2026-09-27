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
