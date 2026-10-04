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
		// The pole, which the zero home read as before 0180.
		home = {latitude_degrees = 90},
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

// The shipped home planet at a radius.
shipped_test_home_at :: proc(radius_metres: int) -> Planet {
	planet := default_planet(shipped_test_planets())
	planet.radius_metres = radius_metres
	return planet
}

// A point on the sphere of the generation's radius, offset in metres
// along two tangents at a direction.
test_sphere_point :: proc(generation: Planet_Generation, direction, forward, right: [3]i64, ahead, aside: i64) -> [3]i64 {
	point := fixed_scale(direction, generation.radius) + fixed_scale(forward, metres_to_position_units(ahead)) + fixed_scale(right, metres_to_position_units(aside))
	return project_onto_sphere(World_Position(point), vector_length(point), generation.radius)
}

// The zero shape (a planet or a world file without it) leaves the relief
// the octaves' sum, as before 0189.
@(test)
test_the_relief_terms_are_off_at_zero :: proc(t: ^testing.T) {
	generation := make_planet_generation(TEST_PLANET_SEED, make_test_planet(), 1000)
	for index in i64(0) ..< 200 {
		point := project_onto_sphere({index * 7919, generation.radius, -index * 4111}, generation.radius, generation.radius)
		sum: i64 = 0
		for octave, octave_index in generation.relief_octaves {
			sum += metres_to_position_units(i64(octave.amplitude_metres)) * relief_octave_noise(generation, octave_index, octave.wavelength_metres, point) / NOISE_ONE
		}
		testing.expect_value(t, surface_relief(generation, point), sum)
	}
}

// The ledges alone, on a chunk's width at the shipped home: a slope
// steeper than the walkable angle of data/game.sjson, where the same
// ground without the ledges stays walkable.
@(test)
test_the_ledges_make_a_slope_above_the_walkable_angle_within_a_chunk :: proc(t: ^testing.T) {
	walkable_cosine := fixed_cosine(degrees_to_angle_units(test_field_game_config().field_player.walkable_angle_degrees))
	planet := shipped_test_home_at(8000)
	testing.expect(t, planet.relief_shape.ledge_amplitude_millimetres > 0, "the shipped home has ledges")
	ledges_only := planet
	for &octave in ledges_only.relief_octaves {
		octave.amplitude_metres = 0
	}
	ledges_only.relief_shape = {ledge_wavelength_metres = planet.relief_shape.ledge_wavelength_metres, ledge_amplitude_millimetres = planet.relief_shape.ledge_amplitude_millimetres, ledge_sharpness = planet.relief_shape.ledge_sharpness}
	flat := ledges_only
	flat.relief_shape.ledge_sharpness = 1
	steepest :: proc(planet: Planet) -> i64 {
		generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
		home := planet_home_direction(planet.home)
		forward := tangent_of(home, {UNIT_VECTOR_ONE, 0, 0})
		right := fixed_cross(forward, home)
		// Steps of a quarter metre across a chunk of 32 m at 1 m spacing.
		run := i64(POSITION_UNITS_PER_METRE / 4)
		lowest_cosine := i64(UNIT_VECTOR_ONE)
		for ahead in i64(0) ..< FIELD_CHUNK_SIZE {
			for quarter in i64(0) ..< 4 * FIELD_CHUNK_SIZE {
				first := test_sphere_point(generation, home, forward, right, ahead, 0) + fixed_scale(right, quarter * run)
				second := first + fixed_scale(right, run)
				rise := surface_relief(generation, second) - surface_relief(generation, first)
				slope, _ := normalize_fixed({run, rise, 0})
				lowest_cosine = min(lowest_cosine, slope.x)
			}
		}
		return lowest_cosine
	}
	testing.expectf(t, steepest(ledges_only) < walkable_cosine, "the ledges' steepest slope has the cosine %d, the walkable angle %d", steepest(ledges_only), walkable_cosine)
	testing.expect(t, steepest(flat) > walkable_cosine, "the unsharpened ledges stay walkable")
}

// At every preset radius with the default seed: a hollow below the sea
// level within 200 m of the home that the basin term made, the pod's site,
// the spawn and the spring above the sea, so the spring's water runs down
// into a pool rather than rising in the sea.
@(test)
test_the_basins_hold_the_sea_near_a_dry_home :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		planet := shipped_test_home_at(radius)
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		home := planet_home_direction(planet.home)
		forward := tangent_of(home, {UNIT_VECTOR_ONE, 0, 0})
		right := fixed_cross(forward, home)
		sea := metres_to_position_units(i64(planet.sea_level_metres))
		found := false
		for ahead := i64(-200); ahead <= 200 && !found; ahead += 4 {
			for aside := i64(-200); aside <= 200 && !found; aside += 4 {
				if ahead * ahead + aside * aside > 200 * 200 {
					continue
				}
				point := test_sphere_point(generation, home, forward, right, ahead, aside)
				long_noise := relief_octave_noise(generation, 0, planet.relief_octaves[0].wavelength_metres, point)
				found = surface_relief(generation, point) < sea && basin_relief(long_noise, planet.relief_shape) < 0
			}
		}
		testing.expectf(t, found, "%d m: no basin below the sea within 200 m of the home", radius)
		site, _ := field_home_site(generation, planet)
		feet := field_home_player(DEFAULT_WORLD_SEED, planet, 1000).position
		testing.expectf(t, vector_length(cast([3]i64)site) > generation.sea_radius, "%d m: the pod's site lies under the sea", radius)
		testing.expectf(t, vector_length(cast([3]i64)feet) > generation.sea_radius, "%d m: the spawn lies under the sea", radius)
		for spring in planet.springs {
			surface := surface_relief(generation, fixed_scale(planet_spring_direction(spring), generation.radius))
			testing.expectf(t, surface > sea, "%d m: the spring's ground lies %d units under the sea", radius, sea - surface)
		}
	}
}

// The relief stays within MAXIMUM_RELIEF_METRES with every term at its
// strongest and the amplitudes using the whole bound.
@(test)
test_the_shaped_relief_stays_within_the_bound :: proc(t: ^testing.T) {
	planet := make_test_planet()
	planet.relief_octaves = {{512, 10}, {128, 5}, {32, 2}}
	planet.relief_shape = {ledge_wavelength_metres = 16, ledge_amplitude_millimetres = 1000, ledge_sharpness = MAXIMUM_LEDGE_SHARPNESS, terrace_rise_millimetres = 1300, terrace_riser_permille = 1, basin_depth_metres = 16, basin_threshold_percent = 100}
	testing.expect_value(t, planet_problem(planet), "")
	bound := metres_to_position_units(MAXIMUM_RELIEF_METRES)
	for shipped in ([2]bool{false, true}) {
		if shipped {
			planet = shipped_test_home_at(8000)
		}
		generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
		lowest, highest := bound, -bound
		for index in i64(0) ..< 20_000 {
			point := project_onto_sphere({index * 977 - 9_000_000, generation.radius, index * 1531 - 15_000_000}, generation.radius, generation.radius)
			relief := surface_relief(generation, point)
			lowest, highest = min(lowest, relief), max(highest, relief)
		}
		testing.expectf(t, lowest >= -bound && highest <= bound, "the relief spans %d to %d, the bound %d", lowest, highest, bound)
	}
}

// The shaped home generates the same bytes twice at every spacing and
// every preset radius, and other bytes than the unshaped one.
@(test)
test_the_shaped_home_generates_identical_bytes_twice :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		planet := shipped_test_home_at(radius)
		unshaped := planet
		unshaped.relief_shape = {}
		for spacing in SAMPLE_SPACING_CHOICES_MILLIMETRES {
			generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, spacing)
			site, _ := field_home_site(generation, planet)
			coordinate := sample_to_field_chunk_coordinate(world_position_to_sample(site, spacing))
			first := new(Field_Chunk, context.temp_allocator)
			second := new(Field_Chunk, context.temp_allocator)
			other := new(Field_Chunk, context.temp_allocator)
			generate_field_chunk(DEFAULT_WORLD_SEED, planet, spacing, coordinate, first)
			generate_field_chunk(DEFAULT_WORLD_SEED, planet, spacing, coordinate, second)
			generate_field_chunk(DEFAULT_WORLD_SEED, unshaped, spacing, coordinate, other)
			testing.expectf(t, field_chunk_equals(first, second), "%d m at %d mm: two generations differ", radius, spacing)
			testing.expectf(t, !field_chunk_equals(first, other), "%d m at %d mm: the shape changed nothing", radius, spacing)
		}
	}
}

// The terms' pure parts: the ledge's profile is odd, bounded and
// steepest at the zero; a terrace keeps whole rises and flattens a tread;
// a basin is zero at its threshold and the depth at the lowest noise.
@(test)
test_the_relief_terms_shape_the_noise :: proc(t: ^testing.T) {
	testing.expect_value(t, ledge_profile(0, 64), 0)
	testing.expect_value(t, ledge_profile(NOISE_ONE, 64), NOISE_ONE)
	testing.expect_value(t, ledge_profile(-NOISE_ONE, 64), -NOISE_ONE)
	testing.expect_value(t, ledge_profile(-NOISE_ONE / 10, 64), -ledge_profile(NOISE_ONE / 10, 64))
	testing.expect(t, ledge_profile(NOISE_ONE / 100, 64) > ledge_profile(NOISE_ONE / 100, 4), "sharper is steeper at the zero")
	testing.expect_value(t, ledge_profile(NOISE_ONE / 2, 1), NOISE_ONE / 2)
	testing.expect_value(t, fixed_power(NOISE_ONE / 2, 3), NOISE_ONE / 8)
	shape := Relief_Shape{terrace_rise_millimetres = 1000, terrace_riser_permille = 100, basin_depth_metres = 10, basin_threshold_percent = -50}
	rise := millimetres_to_position_units(1000)
	testing.expect_value(t, terrace_height(2 * rise, shape), 2 * rise)
	testing.expect_value(t, terrace_height(2 * rise + rise / 2, shape), 2 * rise)
	testing.expect_value(t, terrace_height(-rise / 2, shape), -rise)
	testing.expect_value(t, terrace_height(2 * rise + rise * 95 / 100, shape), 2 * rise + rise / 2)
	testing.expect_value(t, terrace_height(12345, Relief_Shape{}), 12345)
	testing.expect_value(t, basin_relief(-NOISE_ONE / 2, shape), 0)
	testing.expect_value(t, basin_relief(0, shape), 0)
	testing.expect_value(t, basin_relief(-NOISE_ONE, shape), -metres_to_position_units(10))
	testing.expect_value(t, basin_relief(-NOISE_ONE * 3 / 4, shape), -metres_to_position_units(10) / 4)
}

// The crater (work item 0199).

// The shipped crater's term with its floor at the radius.
shipped_test_crater_term :: proc() -> Crater_Term {
	return Crater_Term {
		floor_radius = metres_to_position_units(4),
		radius = metres_to_position_units(12),
		reach = metres_to_position_units(18),
		depth = metres_to_position_units(3),
		rim = metres_to_position_units(1),
	}
}

// The floor's height at any relief out to the floor's radius; from the
// floor's edge a monotonic rise to the rim's crest at the radius for a
// level relief, never steeper than 45 degrees; the relief itself from the
// reach on; the zero term changes nothing.
@(test)
test_the_crater_relief_profile :: proc(t: ^testing.T) {
	term := shipped_test_crater_term()
	for relief in ([3]i64{metres_to_position_units(-20), 0, metres_to_position_units(5)}) {
		testing.expect_value(t, crater_relief(term, 0, relief), 0)
		testing.expect_value(t, crater_relief(term, term.floor_radius, relief), 0)
		testing.expect_value(t, crater_relief(term, term.reach, relief), relief)
		testing.expect_value(t, crater_relief(term, term.reach + 1000, relief), relief)
		testing.expect_value(t, crater_relief({}, term.floor_radius, relief), relief)
	}
	testing.expect_value(t, crater_relief(term, term.radius, 0), term.rim)
	centimetre := millimetres_to_position_units(10)
	previous := crater_relief(term, 0, 0)
	for distance := centimetre; distance <= term.reach; distance += centimetre {
		height := crater_relief(term, distance, 0)
		if distance <= term.radius {
			testing.expectf(t, height >= previous, "the bowl drops at %d", distance)
		}
		testing.expectf(t, abs(height - previous) <= centimetre, "the profile rises %d over a centimetre at %d", height - previous, distance)
		previous = height
	}
}

// The chunks round the shipped home at a radius preset and a spacing,
// reach chunks either side across and one up and down, in a world the
// caller destroys.
make_test_home_field :: proc(planet: Planet, spacing_millimetres: int, reach: i32) -> Field_World {
	world: Field_World
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, spacing_millimetres)
	site, _ := field_home_site(generation, planet)
	centre := sample_to_field_chunk_coordinate(world_position_to_sample(site, spacing_millimetres))
	for z in -reach ..= reach {
		for y in i32(-1) ..= 1 {
			for x in -reach ..= reach {
				chunk := new(Field_Chunk)
				generate_field_chunk(DEFAULT_WORLD_SEED, planet, spacing_millimetres, centre + {x, y, z}, chunk)
				field_world_insert_chunk(&world, chunk)
			}
		}
	}
	return world
}

// The field's surface down the radial at a point on the sphere, from 4 m
// over the expected height, as a distance from the centre.
test_field_surface_distance :: proc(world: ^Field_World, spacing_millimetres: int, point: [3]i64, expected: i64) -> (distance: i64, found: bool) {
	up, _ := normalize_fixed(point)
	rise := metres_to_position_units(4)
	hit := raycast_field(world, spacing_millimetres, World_Position(fixed_scale(up, expected + rise)), -up, 2 * rise)
	return vector_length(cast([3]i64)hit.position), hit.hit
}

// At every preset and at 1000 and 333 mm the generated floor is flat
// enough for a machine on bare ground over 8 by 12 cells centred on the
// home (the room 0198's pod needs), and lies at the floor's height.
@(test)
test_the_crater_floor_is_flat_in_the_generated_field :: proc(t: ^testing.T) {
	flatness := test_field_game_config().bare_ground_flatness_millimetres
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		planet := shipped_test_home_at(radius)
		for spacing in ([2]int{1000, 333}) {
			world := make_test_home_field(planet, spacing, 1)
			defer destroy_field_world(&world)
			generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, spacing)
			site, heading := field_home_site(generation, planet)
			origin, axes := free_frame_at(site, heading, 500)
			pitch := millimetres_to_position_units(500)
			corner := origin - World_Position(fixed_scale(axes[FRAME_RIGHT], 3 * pitch) + fixed_scale(axes[FRAME_FORWARD], 5 * pitch))
			frame := Frame{origin = corner, axes = axes, pitch_millimetres = 500}
			testing.expectf(t, bare_ground_is_flat(&world, spacing, frame, {8, 8, 12}, flatness), "%d m at %d mm: the floor is not flat", radius, spacing)
			expected := generation.radius + generation.crater.floor_height
			surface, found := test_field_surface_distance(&world, spacing, generation.crater.home, expected)
			testing.expectf(t, found && abs(surface - expected) <= generation.spacing / 8, "%d m at %d mm: the floor lies %d units off its height", radius, spacing, surface - expected)
		}
	}
}

// A point on the sphere at a distance from the home along a bearing in
// degrees from the tangent towards +x.
test_crater_point :: proc(generation: Planet_Generation, bearing_degrees: int, distance: i64) -> [3]i64 {
	home := generation.crater.home
	up, _ := normalize_fixed(home)
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	angle := degrees_to_angle_units(bearing_degrees)
	offset := fixed_scale(forward, distance * fixed_cosine(angle) / UNIT_VECTOR_ONE) + fixed_scale(right, distance * fixed_sine(angle) / UNIT_VECTOR_ONE)
	return project_onto_sphere(World_Position(home + offset), vector_length(home + offset), generation.radius)
}

// On eight bearings the field's surface at the crest stands the rim over
// the uncratered relief, and two spacings past the reach the samples
// round the point are the uncratered planet's (the field's surface there
// can lie further than an eighth of a spacing from the relief on a
// ledge's face, crater or not).
@(test)
test_the_rim_stands_above_the_surrounding_surface :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		planet := shipped_test_home_at(radius)
		for spacing in ([2]int{1000, 333}) {
			world := make_test_home_field(planet, spacing, spacing == 1000 ? 1 : 2)
			defer destroy_field_world(&world)
			generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, spacing)
			without := planet
			without.crater = {}
			uncratered := make_planet_generation(DEFAULT_WORLD_SEED, without, spacing)
			term := generation.crater
			for bearing := 0; bearing < 360; bearing += 45 {
				crest := test_crater_point(generation, bearing, term.radius)
				expected := generation.radius + uncratered_relief(generation, crest) + term.rim
				surface, found := test_field_surface_distance(&world, spacing, crest, expected)
				testing.expectf(t, found && abs(surface - expected) <= generation.spacing, "%d m at %d mm, %d degrees: the crest lies %d units off", radius, spacing, bearing, surface - expected)
				outside := test_crater_point(generation, bearing, term.reach + 2 * generation.spacing)
				up, _ := normalize_fixed(outside)
				surface_sample := world_position_to_sample(World_Position(fixed_scale(up, generation.radius + uncratered_relief(generation, outside))), spacing)
				for offset in ([7]Sample_Coordinate{{}, {1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) {
					position := sample_to_world_position(surface_sample + offset, spacing)
					testing.expectf(t, planet_sample(generation, position) == planet_sample(uncratered, position), "%d m at %d mm, %d degrees: the crater reaches past its reach", radius, spacing, bearing)
				}
			}
		}
	}
}

// Every level of detail generates through planet_sample with the crater:
// at the level's spacing (field_grid_generation) a step over the floor is
// air, a step under it ground, and at a quarter of the radius 2 m under
// the uncratered surface is air (the bowl, not the plain relief).
@(test)
test_the_crater_shows_at_every_level :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	term := generation.crater
	up, _ := normalize_fixed(term.home)
	floor := generation.radius + term.floor_height
	quarter := test_crater_point(generation, 90, term.radius / 4)
	quarter_up, _ := normalize_fixed(quarter)
	dug := generation.radius + uncratered_relief(generation, quarter) - metres_to_position_units(2)
	for level in i32(0) ..< FIELD_LEVEL_COUNT {
		step := field_node_step(Field_Node{level = level})
		coarse := field_grid_generation(generation, step)
		height := i64(step) * generation.spacing
		testing.expectf(t, planet_sample(coarse, World_Position(fixed_scale(up, floor + height))).density <= 0, "level %d: ground a step over the floor", level)
		testing.expectf(t, planet_sample(coarse, World_Position(fixed_scale(up, floor - height))).density > 0, "level %d: air a step under the floor", level)
		testing.expectf(t, planet_sample(coarse, World_Position(fixed_scale(quarter_up, dug))).density <= 0, "level %d: the bowl is not dug at a quarter of the radius", level)
	}
}

// With the default seed the shipped floor lies at least 1 m over the sea
// at every preset, and neither of the crater's clamps engages.
@(test)
test_the_shipped_crater_floor_lies_above_the_sea :: proc(t: ^testing.T) {
	bound := metres_to_position_units(MAXIMUM_RELIEF_METRES)
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		planet := shipped_test_home_at(radius)
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		term := generation.crater
		sea := metres_to_position_units(i64(planet.sea_level_metres))
		testing.expectf(t, term.floor_height - sea >= metres_to_position_units(1), "%d m: the floor lies %d units over the sea", radius, term.floor_height - sea)
		testing.expectf(t, uncratered_relief(generation, term.home) - term.depth > -bound, "%d m: the floor's clamp engages", radius)
		for bearing := 0; bearing < 360; bearing += 45 {
			crest := test_crater_point(generation, bearing, term.radius)
			testing.expectf(t, uncratered_relief(generation, crest) + term.rim < bound, "%d m: the rim's clamp engages", radius)
		}
	}
}

// The first seed from 1 to 256 whose home's crater floor lies less than
// the margin above the sea (planet_home_is_dry), from the planet's own
// record and relief, so the tests follow a later relief change (0180).
first_wet_home_seed :: proc(planet: Planet) -> (seed: u64, found: bool) {
	for candidate in u64(1) ..= 256 {
		if !planet_home_is_dry(make_planet_generation(candidate, planet, 1000), planet, planet.home) {
			return candidate, true
		}
	}
	return 0, false
}

@(test)
test_a_wet_home_moves_to_the_nearest_dry_whole_degree :: proc(t: ^testing.T) {
	for radius in ([?]int{4000, 8000, 16000}) {
		planet := shipped_test_home_at(radius)
		seed, wet := first_wet_home_seed(planet)
		testing.expectf(t, wet, "a wet seed at %d m", radius)
		moved, found := find_dry_planet_home(seed, planet)
		testing.expectf(t, found, "dry ground near the home at %d m with seed %d", radius, seed)
		testing.expectf(t, moved != planet.home, "the home moves at %d m with seed %d", radius, seed)
		generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
		testing.expectf(t, planet_home_is_dry(generation, planet, moved), "the moved home %v is dry at %d m", moved, radius)
		origin := planet_home_direction(planet.home)
		chord := squared_chord(planet_home_direction(moved), origin)
		reach := squared_chord(planet_home_direction({}), planet_home_direction({0, HOME_SEARCH_DEGREES}))
		testing.expectf(t, chord <= reach, "the move stays within %d degrees at %d m", HOME_SEARCH_DEGREES, radius)
		for latitude in max(-90, planet.home.latitude_degrees - HOME_SEARCH_DEGREES) ..= min(90, planet.home.latitude_degrees + HOME_SEARCH_DEGREES) {
			for longitude in -179 ..= 180 {
				candidate := Planet_Home{latitude, longitude}
				if squared_chord(planet_home_direction(candidate), origin) < chord {
					testing.expectf(t, !planet_home_is_dry(generation, planet, candidate), "%v is nearer and dry at %d m", candidate, radius)
				}
			}
		}
		moved_planet := planet
		moved_planet.home = moved
		for spacing in ([?]int{333, 500, 1000}) {
			site_generation := make_planet_generation(seed, moved_planet, spacing)
			surface, _ := field_home_site(site_generation, moved_planet)
			above := vector_length(cast([3]i64)(surface)) - site_generation.sea_radius
			testing.expectf(t, above >= millimetres_to_position_units(HOME_DRY_MARGIN_MILLIMETRES) - site_generation.spacing / 8, "the site stands %d units above the sea at %d m, %d mm", above, radius, spacing)
		}
	}
}

@(test)
test_the_shipped_home_stays_dry_with_the_default_seed :: proc(t: ^testing.T) {
	for radius in ([?]int{4000, 8000, 16000}) {
		planet := shipped_test_home_at(radius)
		home, found := find_dry_planet_home(DEFAULT_WORLD_SEED, planet)
		testing.expectf(t, found, "dry at %d m", radius)
		testing.expect_value(t, home, planet.home)
	}
}

@(test)
test_no_dry_ground_keeps_the_records_home :: proc(t: ^testing.T) {
	planet := default_planet(shipped_test_planets())
	planet.sea_level_metres = MAXIMUM_RELIEF_METRES + 1
	_, found := find_dry_planet_home(DEFAULT_WORLD_SEED, planet)
	testing.expect(t, !found, "nothing is dry under a sea above every relief")
	testing.expect_value(t, new_world_home(DEFAULT_WORLD_SEED, planet), planet.home)
}
