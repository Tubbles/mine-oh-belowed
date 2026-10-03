package game

import "core:testing"

TEST_PLANET_SEED :: u64(42)

make_test_planet :: proc() -> Planet {
	palette := make([][3]int, 3, context.temp_allocator)
	palette[0], palette[1], palette[2] = {100, 90, 80}, {120, 100, 80}, {90, 90, 90}
	return Planet {
		id = "home",
		radius_metres = 8000,
		surface_gravity_centimetres_per_second_squared = 981,
		bedrock_depth_metres = 256,
		sea_level_metres = 0,
		rotation_period_seconds = 1200,
		relief_octaves = {{512, 24}, {128, 8}, {32, 2}},
		palette = palette,
	}
}

generate_test_field_chunk :: proc(coordinate: Field_Chunk_Coordinate, spacing_millimetres := 1000) -> ^Field_Chunk {
	chunk := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(TEST_PLANET_SEED, make_test_planet(), spacing_millimetres, coordinate, chunk)
	return chunk
}

@(test)
test_integer_square_root_edges :: proc(t: ^testing.T) {
	cases := [?][2]u64 {
		{0, 0},
		{1, 1},
		{2, 1},
		{3, 1},
		{4, 2},
		{15, 3},
		{16, 4},
		{17, 4},
		{(1 << 32 - 1) * (1 << 32 - 1) - 1, 1 << 32 - 2},
		{(1 << 32 - 1) * (1 << 32 - 1), 1 << 32 - 1},
		{max(u64), 1 << 32 - 1},
	}
	for entry in cases {
		testing.expect_value(t, integer_square_root(entry[0]), entry[1])
	}
	// Every root is the floor: root squared fits, root plus one squared does not.
	for value in u64(0) ..< 100_000 {
		root := integer_square_root(value * 7919)
		testing.expect(t, root * root <= value * 7919 && (root + 1) * (root + 1) > value * 7919)
	}
}

@(test)
test_value_noise_stays_in_range :: proc(t: ^testing.T) {
	wavelength := metres_to_position_units(32)
	for index in i64(-500) ..< 500 {
		point := [3]i64{index * 977, -index * 1531, index * 2741}
		noise := value_noise(7, point, wavelength)
		testing.expect(t, noise >= -NOISE_ONE && noise <= NOISE_ONE)
	}
	// On a lattice point the noise is the lattice value.
	testing.expect_value(t, value_noise(7, {wavelength, 0, -wavelength}, wavelength), lattice_value(7, {1, 0, -1}))
}

@(test)
test_generating_a_field_chunk_twice_gives_identical_bytes :: proc(t: ^testing.T) {
	for spacing in SAMPLE_SPACING_CHOICES_MILLIMETRES {
		radius_samples := i32(8000 * MILLIMETRES_PER_METRE / spacing)
		coordinate := Field_Chunk_Coordinate{radius_samples / FIELD_CHUNK_SIZE, 3, -2}
		first := generate_test_field_chunk(coordinate, spacing)
		second := generate_test_field_chunk(coordinate, spacing)
		testing.expect(t, field_chunk_equals(first, second))
		testing.expect_value(t, first.coordinate, coordinate)
	}
	other := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(TEST_PLANET_SEED + 1, make_test_planet(), 1000, {250, 3, -2}, other)
	testing.expect(t, !field_chunk_equals(other, generate_test_field_chunk({250, 3, -2})))
}

// Along the +x axis the local surface is one height, so the density
// falls with the distance; beyond the relief band is air, below it ground.
@(test)
test_a_surface_chunk_has_air_outside_the_radius_band_and_ground_inside :: proc(t: ^testing.T) {
	world: Field_World
	defer destroy_field_world(&world)
	for x in i32(247) ..= 252 {
		chunk := new(Field_Chunk)
		generate_field_chunk(TEST_PLANET_SEED, make_test_planet(), 1000, {x, 0, 0}, chunk)
		field_world_insert_chunk(&world, chunk)
	}
	previous_density := i8(MAXIMUM_DENSITY)
	air_count, ground_count := 0, 0
	outermost_ground := Field_Material.Air
	for x in i32(247 * FIELD_CHUNK_SIZE) ..< 253 * FIELD_CHUNK_SIZE {
		sample := field_world_get_sample(&world, {x, 0, 0})
		testing.expect(t, sample.density <= previous_density)
		previous_density = sample.density
		testing.expect_value(t, sample.material == .Air, sample.density <= 0)
		if x > 8000 + i32(MAXIMUM_RELIEF_METRES) {
			testing.expect_value(t, sample.material, Field_Material.Air)
		}
		if x < 8000 - i32(MAXIMUM_RELIEF_METRES) {
			testing.expect(t, sample.material != .Air && sample.density == MAXIMUM_DENSITY)
		}
		air_count += sample.material == .Air ? 1 : 0
		ground_count += sample.material == .Air ? 0 : 1
		if sample.material != .Air {
			outermost_ground = sample.material
		}
	}
	testing.expect(t, air_count > 0 && ground_count > 0)
	testing.expect_value(t, outermost_ground, Field_Material.Topsoil)
}

@(test)
test_a_sample_at_the_bedrock_depth_is_bedrock :: proc(t: ^testing.T) {
	planet := make_test_planet()
	for spacing in ([2]int{500, 1000}) {
		bedrock_sample := i32((planet.radius_metres - planet.bedrock_depth_metres) * MILLIMETRES_PER_METRE / spacing)
		world: Field_World
		for offset in ([2]i32{-1, 1}) {
			chunk := new(Field_Chunk)
			generate_field_chunk(TEST_PLANET_SEED, planet, spacing, sample_to_field_chunk_coordinate({bedrock_sample + offset, 0, 0}), chunk)
			field_world_insert_chunk(&world, chunk)
		}
		testing.expect_value(t, field_world_get_sample(&world, {bedrock_sample, 0, 0}).material, Field_Material.Bedrock)
		testing.expect_value(t, field_world_get_sample(&world, {bedrock_sample + 1, 0, 0}).material, Field_Material.Deep_Stone)
		testing.expect_value(t, field_world_get_sample(&world, {bedrock_sample - 1, 0, 0}).material, Field_Material.Bedrock)
		destroy_field_world(&world)
	}
}

@(test)
test_strata_follow_the_depth_below_the_local_surface :: proc(t: ^testing.T) {
	bedrock_radius := metres_to_position_units(7744)
	distance := metres_to_position_units(8000)
	testing.expect_value(t, planet_stratum(1, distance, bedrock_radius), Field_Material.Topsoil)
	testing.expect_value(t, planet_stratum(metres_to_position_units(TOPSOIL_DEPTH_METRES), distance, bedrock_radius), Field_Material.Stone)
	testing.expect_value(t, planet_stratum(metres_to_position_units(DEEP_STONE_DEPTH_METRES), distance, bedrock_radius), Field_Material.Deep_Stone)
	testing.expect_value(t, planet_stratum(1, bedrock_radius, bedrock_radius), Field_Material.Bedrock)
}

@(test)
test_density_is_the_depth_in_steps_of_the_spacing :: proc(t: ^testing.T) {
	testing.expect_value(t, depth_to_density(0, 1000), 0)
	testing.expect_value(t, depth_to_density(POSITION_UNITS_PER_METRE / 2, 1000), 64)
	testing.expect_value(t, depth_to_density(-POSITION_UNITS_PER_METRE / 2, 1000), -64)
	testing.expect_value(t, depth_to_density(POSITION_UNITS_PER_METRE / 2, 500), MAXIMUM_DENSITY)
	testing.expect_value(t, depth_to_density(-metres_to_position_units(10_000), 333), -MAXIMUM_DENSITY)
	// Far beyond any planet is air without touching the squared distance's range.
	far := World_Position{max(i64) / 2, 0, 0}
	testing.expect_value(t, planet_sample(make_planet_generation(1, make_test_planet(), 1000), far), FIELD_AIR_SAMPLE)
}

// With the shallowest bedrock the planet allows, the bedrock radius lies
// inside the relief band, so the sample goes through the noise and the
// strata instead of the deep path.
@(test)
test_bedrock_at_the_minimum_depth_comes_from_the_full_computation :: proc(t: ^testing.T) {
	planet := make_test_planet()
	planet.bedrock_depth_metres = MINIMUM_BEDROCK_DEPTH_METRES
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	bedrock_metres := i64(planet.radius_metres - planet.bedrock_depth_metres)
	deep_path_below := generation.radius - metres_to_position_units(MAXIMUM_RELIEF_METRES + DEEP_STONE_DEPTH_METRES) - generation.spacing
	position := World_Position{metres_to_position_units(bedrock_metres), 0, 0}
	testing.expect(t, position.x >= deep_path_below)
	testing.expect_value(t, planet_sample(generation, position).material, Field_Material.Bedrock)
	testing.expect_value(t, planet_sample(generation, position + {1, 0, 0}).material, Field_Material.Deep_Stone)
}

// Every sample below sea level that is not ground holds the sea's fill,
// nothing else holds water, and a spring's sample is a full, awake source
// in air.
@(test)
test_generation_fills_the_sea_and_marks_the_springs :: proc(t: ^testing.T) {
	planet := make_test_planet()
	sea_level := field_sea_level(planet, 1000)
	seen_sea := false
	for y in i32(248) ..= 251 {
		chunk := generate_test_field_chunk({0, y, 0})
		origin := field_chunk_origin(chunk.coordinate)
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			sea := field_sea_fill(sea_level, field_water_span(origin + Sample_Coordinate(field_index_to_local(index))))
			if chunk.density[index] > 0 {
				sea = 0
			}
			testing.expect_value(t, i32(chunk.water[index]), sea)
			seen_sea ||= sea > 0
		}
		testing.expect(t, !field_sample_bits_any(&chunk.water_awake), "the sea sleeps")
	}
	testing.expect(t, seen_sea, "the chunks reach the sea")

	springs := []Planet_Spring{{latitude_degrees = 89, longitude_degrees = 45}}
	planet.springs = springs
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	sample, found := planet_spring_sample(generation, springs[0])
	testing.expect(t, found, "the spring finds air above its surface")
	chunk := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(TEST_PLANET_SEED, planet, 1000, sample_to_field_chunk_coordinate(sample), chunk)
	index := sample_to_field_index(sample)
	testing.expect(t, chunk.density[index] <= 0, "the spring is in air")
	testing.expect_value(t, chunk.water[index], FIELD_WATER_FULL)
	testing.expect(t, field_sample_bit(&chunk.water_source, index) && field_sample_bit(&chunk.water_awake, index))
	// Latitude 89 lies about 140 m from the pole, longitude 45 between +x
	// and +z.
	testing.expect(t, sample.x > 90 && sample.x < 110 && sample.z > 90 && sample.z < 110, "the spring lies where its latitude and longitude say")
}
