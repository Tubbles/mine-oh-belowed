package game

@(require) import "core:log"
import "core:strings"
import "core:testing"
@(require) import "core:time"
import "generation_seed"

// Work item 0306: the landforms.

// The shipped landforms as the design tuned them, at a radius, on the
// home planet of before (pre_0306_test_home_at) with the detail octaves,
// the ledges alone and the springs of 0306, so a later data retune leaves
// the parity tests.
design_landform_test_planet :: proc(radius_metres: int) -> Planet {
	planet := pre_0306_test_home_at(radius_metres)
	springs := make([]Planet_Spring, 2, context.temp_allocator)
	springs[0], springs[1] = {latitude_degrees = 79, longitude_degrees = 151}, {latitude_degrees = 81, longitude_degrees = 139}
	planet.springs = springs
	planet.relief_octaves = {{96, 4}, {32, 2}, {12, 1}}
	planet.relief_shape = {32, 700, 128, 0, 10, 0, -30}
	planet.landforms = Planet_Landforms {
		warp_wavelength_metres   = 1200,
		warp_metres              = 300,
		region_wavelength_metres = 2400,
		region_heights_metres    = {-60, -46, -26, -9, -5, -1, 5, 16, 30},
		region_ranges_percent    = {0, 0, 0, 0, 15, 45, 80, 100, 100},
		region_hills_percent     = {0, 10, 30, 60, 80, 100, 100, 100, 100},
		range_wavelength_metres  = 800,
		range_metres             = 80,
		spur_wavelength_metres   = 300,
		spur_percent             = 35,
		hill_wavelength_metres   = 180,
		hill_metres              = 8,
		home_metres              = 2,
		calm_metres              = 120,
		wild_metres              = 600,
	}
	return planet
}

// The point on the sphere of the generation's radius at whole degrees.
test_degree_point :: proc(generation: Planet_Generation, latitude, longitude: int) -> [3]i64 {
	return fixed_scale(planet_direction_at(degrees_to_angle_units(latitude), degrees_to_angle_units(longitude)), generation.radius)
}

// A point on the sphere offset along the tangents at the direction, the
// offsets of index walking a square of half metres either way.
test_scattered_point :: proc(generation: Planet_Generation, direction: [3]i64, index, half: i64) -> [3]i64 {
	forward := tangent_of(direction, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, direction)
	ahead := index * 7919 % (2 * half + 1) - half
	aside := index * 104_729 % (2 * half + 1) - half
	return test_sphere_point(generation, direction, forward, right, ahead, aside)
}

// The points of the bound tests on a line over the sphere, projected
// onto it.
test_line_point :: proc(generation: Planet_Generation, index: i64) -> [3]i64 {
	position := World_Position{index * 977 - 9_000_000, generation.radius, index * 1531 - 15_000_000}
	return project_onto_sphere(position, vector_length(cast([3]i64)position), generation.radius)
}

// The prototype's golden values (tmp/0306/proto, mode golden): the
// implementation that matches them generates the ground the springs were
// chosen on.
@(test)
test_gradient_noise_matches_the_design :: proc(t: ^testing.T) {
	wavelength := metres_to_position_units(100)
	testing.expect_value(t, gradient_noise(77, {0, 0, 0}, wavelength), 0)
	testing.expect_value(t, gradient_noise(77, {1, 2, 3}, wavelength), 0)
	testing.expect_value(t, gradient_noise(77, {123456, -654321, 98765}, wavelength), -9185)
	testing.expect_value(t, gradient_noise(77, {-4096000, 32768000, 777777}, wavelength), 6569)
	for index in i64(0) ..< 10_000 {
		point := [3]i64{index * 977 - 5_000_000, -index * 1531 + 3_000_000, index * 2741 - 13_000_000}
		noise := gradient_noise(77, point, wavelength)
		testing.expect(t, noise >= -NOISE_ONE && noise <= NOISE_ONE)
		cell := [3]i64{index % 97 - 48, index / 97 % 89 - 44, index % 13 - 6}
		testing.expect_value(t, gradient_noise(77, cell * wavelength, wavelength), 0)
	}
}

@(test)
test_landform_relief_matches_the_design :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_landform_test_planet(8000), 1000)
	testing.expect_value(t, landform_relief(generation, test_degree_point(generation, 83, 132)), 8192)
	testing.expect_value(t, landform_relief(generation, test_degree_point(generation, 81, 139)), 108078)
	testing.expect_value(t, landform_relief(generation, test_degree_point(generation, 79, 151)), 305724)
	testing.expect_value(t, landform_relief(generation, test_degree_point(generation, -30, 10)), -14393)
	testing.expect_value(t, uncratered_relief(generation, test_degree_point(generation, 83, 132)), 2697)
	testing.expect_value(t, uncratered_relief(generation, test_degree_point(generation, 81, 139)), 113668)
	small := make_planet_generation(DEFAULT_WORLD_SEED, design_landform_test_planet(4000), 1000)
	testing.expect_value(t, landform_relief(small, test_degree_point(small, 81, 139)), 9743)
	large := make_planet_generation(DEFAULT_WORLD_SEED, design_landform_test_planet(16000), 1000)
	testing.expect_value(t, landform_relief(large, test_degree_point(large, 81, 139)), 211207)
}

// Without landforms the bound is the octaves' limit both ways; with them
// the knots' extremes, the strongest ranges and hills and the detail.
@(test)
test_the_relief_bounds_follow_the_record :: proc(t: ^testing.T) {
	limit := metres_to_position_units(OCTAVE_RELIEF_LIMIT_METRES)
	testing.expect_value(t, planet_relief_bounds(make_test_planet()), Relief_Bounds{-limit, limit})
	design := design_landform_test_planet(8000)
	testing.expect_value(t, planet_relief_bounds(design), Relief_Bounds{-310067, 514867})
	testing.expect_value(t, relief_depth_metres(planet_relief_bounds(design)), 76)
	testing.expect_value(t, minimum_bedrock_depth_metres(design), 116)
	testing.expect_value(t, minimum_bedrock_depth_metres(make_test_planet()), 74)
	full := design
	full.landforms.region_ranges_percent = 100
	full.landforms.region_hills_percent = 100
	full.landforms.spur_percent = 0
	detail := relief_detail_above(full.relief_octaves, full.relief_shape)
	bounds := planet_relief_bounds(full)
	testing.expect_value(t, bounds.highest, metres_to_position_units(30 + 80 + 8) + detail)
	testing.expect_value(t, bounds.lowest, metres_to_position_units(-60 - 8) - detail)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, full, 1000)
	for index in i64(0) ..< 20_000 {
		relief := surface_relief(generation, test_line_point(generation, index))
		testing.expect(t, relief >= bounds.lowest && relief <= bounds.highest)
	}
}

// At every preset, on a line over the sphere and round the first spring's
// range, the surface stays within the planet's bound.
@(test)
test_the_landform_relief_stays_within_the_bound :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		planet := shipped_test_home_at(radius)
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		testing.expect(t, generation.landforms != {}, "the shipped home has landforms")
		spring := planet_direction_at(degrees_to_angle_units(79), degrees_to_angle_units(151))
		lowest, highest := generation.relief_highest, generation.relief_lowest
		for index in i64(0) ..< 20_000 {
			for point in ([2][3]i64{test_line_point(generation, index), test_scattered_point(generation, spring, index, 1000)}) {
				relief := surface_relief(generation, point)
				lowest, highest = min(lowest, relief), max(highest, relief)
			}
		}
		testing.expectf(t, lowest >= generation.relief_lowest && highest <= generation.relief_highest, "%d m: the relief spans %d to %d, the bound %d to %d", radius, lowest, highest, generation.relief_lowest, generation.relief_highest)
	}
}

// The home's plain: within calm_metres the landforms are home_metres
// high, beyond wild_metres fully wild.
@(test)
test_the_home_is_calm :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		planet := shipped_test_home_at(radius)
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		home := planet_home_direction(planet.home)
		calm := i64(planet.landforms.calm_metres)
		for index in i64(0) ..< 1000 {
			point := test_scattered_point(generation, home, index, calm * 7 / 10)
			testing.expectf(t, landform_relief(generation, point) == metres_to_position_units(i64(planet.landforms.home_metres)), "%d m: the landforms are not the home's plain %d", radius, index)
			far := test_scattered_point(generation, home, index, 4 * i64(planet.landforms.wild_metres))
			if vector_length(far - generation.landform_home) >= metres_to_position_units(i64(planet.landforms.wild_metres)) {
				testing.expect_value(t, home_wildness(generation, far), NOISE_ONE)
			}
		}
	}
}

@(test)
test_the_landform_relief_is_deterministic :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	first := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	second := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	other := make_planet_generation(DEFAULT_WORLD_SEED + 1, planet, 1000)
	differs := 0
	for index in i64(0) ..< 1000 {
		point := test_line_point(first, index * 20)
		testing.expect_value(t, landform_relief(first, point), landform_relief(second, point))
		differs += landform_relief(first, point) != landform_relief(other, point) ? 1 : 0
	}
	testing.expect(t, differs > 0, "another seed makes other landforms")
	coordinate := test_surface_chunk(first, planet_spring_direction(planet.springs[0]), 0)
	chunks: [2]^Field_Chunk
	for &chunk in chunks {
		chunk = new(Field_Chunk, context.temp_allocator)
		generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, chunk)
	}
	testing.expect(t, field_chunk_equals(chunks[0], chunks[1]), "two generations of the spring's chunk differ")
}

// The chunk holding the surface under a direction, offset along the
// radial by below metres downwards.
test_surface_chunk :: proc(generation: Planet_Generation, direction: [3]i64, below: i64) -> Field_Chunk_Coordinate {
	surface := generation.radius + surface_relief(generation, fixed_scale(direction, generation.radius)) - metres_to_position_units(below)
	return sample_to_field_chunk_coordinate(world_position_to_sample(World_Position(fixed_scale(direction, surface)), generation.spacing_millimetres))
}

// The relief of a world record from before 0306 is the relief of before,
// byte for byte: the constants were taken on main before the landforms.
@(test)
test_a_record_without_landforms_generates_as_before :: proc(t: ^testing.T) {
	planet := pre_0306_test_home_at(8000)
	spacing := 1000
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, spacing)
	home := planet_home_direction(planet.home)
	spring := planet_direction_at(degrees_to_angle_units(83), degrees_to_angle_units(144))
	chunks := [3]Field_Chunk_Coordinate{test_surface_chunk(generation, home, 0), test_surface_chunk(generation, spring, 0), test_surface_chunk(generation, home, FIELD_CHUNK_SIZE)}
	folded: u64 = 0
	for coordinate in chunks {
		chunk := new(Field_Chunk, context.temp_allocator)
		generate_field_chunk(DEFAULT_WORLD_SEED, planet, spacing, coordinate, chunk)
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			folded = generation_seed.hash_combine(folded, u64(u8(chunk.density[index])) << 16 | u64(u8(chunk.material[index])) << 8 | u64(chunk.tint[index]))
		}
	}
	sum: i64 = 0
	for index in i64(0) ..< 1000 {
		position := World_Position{index * 39_079 - 19_000_000, generation.radius, index * 61_231 - 30_000_000}
		sum += uncratered_relief(generation, project_onto_sphere(position, vector_length(cast([3]i64)position), generation.radius))
	}
	testing.expect_value(t, chunks, [3]Field_Chunk_Coordinate{{-21, 247, 22}, {-25, 247, 17}, {-21, 246, 22}})
	testing.expect_value(t, folded, 12701360373801337529)
	testing.expect_value(t, sum, -7112781)
}

// A world.sjson recorded before the landforms, loaded against data that
// has them: one log line, no landforms on the planet and the relief of
// before.
@(test)
test_an_old_world_file_keeps_its_relief :: proc(t: ^testing.T) {
	old := pre_0306_test_home_at(8000)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = old.id},
		planet_generation = planet_generation_record(old),
	}
	text := string(encode_world_file(file, context.temp_allocator))
	start := strings.index(text, "landforms")
	end := start + strings.index_byte(text[start:], '}') + 1
	older := strings.concatenate({text[:start], text[end:]}, context.temp_allocator)
	testing.expect(t, !strings.contains(older, "landforms"), "the old text holds no landforms")
	parsed, problem := parse_world_file(transmute([]byte)older, context.temp_allocator)
	testing.expect_value(t, problem, "")
	planets := shipped_test_planets()
	testing.expect(t, strings.contains(recorded_landforms_note(parsed.planet_generation, default_planet(planets)), "records no landforms"), "the old file's note")
	testing.expect_value(t, recorded_landforms_note(planet_generation_record(default_planet(planets)), default_planet(planets)), "")
	_, planet, record := resolve_world_planet(parsed.settings, parsed.planet_generation, planets, true)
	testing.expect_value(t, record.landforms, Planet_Landforms{})
	recorded := make_recorded_planet(planet, record, context.temp_allocator)
	testing.expect_value(t, recorded.landforms, Planet_Landforms{})
	generation := make_planet_generation(DEFAULT_WORLD_SEED, recorded, 1000)
	legacy := make_planet_generation(DEFAULT_WORLD_SEED, old, 1000)
	for index in i64(0) ..< 100 {
		point := test_line_point(generation, index * 200)
		testing.expect_value(t, surface_relief(generation, point), surface_relief(legacy, point))
	}
}

@(test)
test_a_new_world_records_its_landforms :: proc(t: ^testing.T) {
	planet := default_planet(shipped_test_planets())
	record := planet_generation_record(planet)
	testing.expect_value(t, record.landforms, planet.landforms)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = planet.id},
		planet_generation = record,
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.landforms, planet.landforms)
	testing.expect_value(t, make_recorded_planet(planet, parsed.planet_generation, context.temp_allocator).landforms, planet.landforms)
}

@(test)
test_landforms_problems :: proc(t: ^testing.T) {
	testing.expect_value(t, landforms_problem({}), "")
	design := design_landform_test_planet(8000)
	testing.expect_value(t, planet_problem(design), "")
	cases := [?]struct {
		change:   proc(landforms: ^Planet_Landforms),
		expected: string,
	} {
		{proc(landforms: ^Planet_Landforms) {landforms.warp_wavelength_metres = 0}, "landforms.warp_wavelength_metres 0 is outside 1 to 100000"},
		{proc(landforms: ^Planet_Landforms) {landforms.warp_metres = -1}, "landforms.warp_metres -1 is outside 0 to 10000"},
		{proc(landforms: ^Planet_Landforms) {landforms.warp_metres = 10_001}, "landforms.warp_metres 10001 is outside 0 to 10000"},
		{proc(landforms: ^Planet_Landforms) {landforms.region_wavelength_metres = 100_001}, "landforms.region_wavelength_metres 100001 is outside 1 to 100000"},
		{proc(landforms: ^Planet_Landforms) {landforms.range_wavelength_metres = 0}, "landforms.range_wavelength_metres 0 is outside 1 to 100000"},
		{proc(landforms: ^Planet_Landforms) {landforms.range_metres = 257}, "landforms.range_metres 257 is outside 0 to 256"},
		{proc(landforms: ^Planet_Landforms) {landforms.spur_wavelength_metres = 0}, "landforms.spur_wavelength_metres 0 is outside 1 to 100000"},
		{proc(landforms: ^Planet_Landforms) {landforms.spur_percent = 101}, "landforms.spur_percent 101 is outside 0 to 100"},
		{proc(landforms: ^Planet_Landforms) {landforms.hill_wavelength_metres = 0}, "landforms.hill_wavelength_metres 0 is outside 1 to 100000"},
		{proc(landforms: ^Planet_Landforms) {landforms.hill_metres = -1}, "landforms.hill_metres -1 is outside 0 to 256"},
		{proc(landforms: ^Planet_Landforms) {landforms.home_metres = -129}, "landforms.home_metres -129 is outside -128 to 256"},
		{proc(landforms: ^Planet_Landforms) {landforms.wild_metres = 8193}, "landforms.wild_metres 8193 is outside 1 to 8192"},
		{proc(landforms: ^Planet_Landforms) {landforms.calm_metres = -1}, "landforms.calm_metres -1 is outside 0 to 599"},
		{proc(landforms: ^Planet_Landforms) {landforms.calm_metres = 600}, "landforms.calm_metres 600 is outside 0 to 599"},
		{proc(landforms: ^Planet_Landforms) {landforms.region_heights_metres[0] = -129}, "landforms.region_heights_metres[0] -129 is outside -128 to 256"},
		{proc(landforms: ^Planet_Landforms) {landforms.region_heights_metres[8] = 257}, "landforms.region_heights_metres[8] 257 is outside -128 to 256"},
		{proc(landforms: ^Planet_Landforms) {landforms.region_ranges_percent[3] = 101}, "landforms.region_ranges_percent[3] 101 is outside 0 to 100"},
		{proc(landforms: ^Planet_Landforms) {landforms.region_hills_percent[5] = -1}, "landforms.region_hills_percent[5] -1 is outside 0 to 100"},
	}
	for entry in cases {
		landforms := design.landforms
		entry.change(&landforms)
		testing.expect_value(t, landforms_problem(landforms), entry.expected)
		changed := design
		changed.landforms = landforms
		testing.expect(t, strings.contains(planet_problem(changed), entry.expected), entry.expected)
	}
	planet_cases := [?]struct {
		change:   proc(planet: ^Planet),
		expected: string,
	} {
		{proc(planet: ^Planet) {planet.landforms.region_heights_metres[0] = -128}, "the relief with the landforms reaches 144 m below the radius, more than 128"},
		{proc(planet: ^Planet) {planet.landforms.range_metres = 256}, "the relief with the landforms reaches 302 m above the radius, more than 256"},
		{proc(planet: ^Planet) {planet.landforms.calm_metres = 17}, "landforms.calm_metres 17 is inside the crater's reach of 18 m"},
		{proc(planet: ^Planet) {planet.landforms.home_metres = -5}, "landforms.home_metres -5 can put the crater's floor 5699 mm under the sea level's dry margin"},
		{proc(planet: ^Planet) {planet.bedrock_depth_metres = 115}, "bedrock_depth_metres 115 is outside 116 to 7999"},
	}
	for entry in planet_cases {
		changed := design
		entry.change(&changed)
		testing.expect_value(t, planet_problem(changed), entry.expected)
	}
	at_minimum := design
	at_minimum.bedrock_depth_metres = 116
	testing.expect_value(t, planet_problem(at_minimum), "")
	shipped := string(#load("../data/planets.sjson"))
	missing, _ := strings.replace(shipped, "hill_metres = 8", "", 1, context.temp_allocator)
	expect_planets_problem(t, missing, "planets[0].landforms is missing hill_metres")
}

// Measured, not asserted (0306), so it runs only with the define (log
// and time are required imports for it): the relief's cost per point and the
// coarse grids' and the simulated set's samples that need it, before and
// after the landforms. Run alone with
// ./build.sh test -o:speed -define:RELIEF_COST=true -define:ODIN_TEST_NAMES=game.test_report_the_relief_cost
RELIEF_COST :: #config(RELIEF_COST, false)

when RELIEF_COST {
	@(test)
	test_report_the_relief_cost :: proc(t: ^testing.T) {
		levels := test_field_game_config().field_view.level_distances_metres
		for planet, planet_index in ([2]Planet{pre_0306_test_home_at(8000), shipped_test_home_at(8000)}) {
			label := planet_index == 0 ? "before" : "after"
			generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
			report_relief_cost_per_point(generation, label)
			home_camera := World_Position(fixed_scale(planet_home_direction(planet.home), generation.radius + generation.crater.floor_height + metres_to_position_units(2)))
			spring := planet_direction_at(degrees_to_angle_units(79), degrees_to_angle_units(151))
			spring_camera := World_Position(fixed_scale(spring, generation.radius + surface_relief(generation, fixed_scale(spring, generation.radius)) + metres_to_position_units(2)))
			for camera, camera_index in ([2]World_Position{home_camera, spring_camera}) {
				place := fmt_place(label, camera_index)
				nodes := select_field_nodes(make_field_view(camera, planet, 1000, levels), context.temp_allocator)
				testing.expect(t, len(nodes) > 0, "a view selects nodes")
				report_relief_cost_of_view(generation, nodes, camera, place)
			}
		}
	}

	fmt_place :: proc(label: string, camera_index: int) -> string {
		return strings.concatenate({label, camera_index == 0 ? " at the home" : " at (79, 151)"}, context.temp_allocator)
	}

	report_relief_cost_per_point :: proc(generation: Planet_Generation, label: string) {
		sum: i64 = 0
		begin := time.tick_now()
		for index in i64(0) ..< 200_000 {
			sum += surface_relief(generation, test_line_point(generation, index))
		}
		line := time.duration_nanoseconds(time.tick_since(begin))
		home := planet_home_direction({83, 132})
		begin = time.tick_now()
		for index in i64(0) ..< 200_000 {
			sum += surface_relief(generation, test_scattered_point(generation, home, index, 35))
		}
		near := time.duration_nanoseconds(time.tick_since(begin))
		log.infof("relief cost %s: %.0f ns a surface_relief on a line, %.0f ns within 50 m of the home (%d)", label, f64(line) / 200_000, f64(near) / 200_000, sum)
	}

	// Per level the nodes and the grid positions whose shortcut needs the
	// relief, the same over the 7 by 7 by 7 chunks round the camera's
	// chunk, and the wall time of the first 16 coarsest nodes' grids.
	report_relief_cost_of_view :: proc(generation: Planet_Generation, nodes: []Field_Node, camera: World_Position, place: string) {
		counts, samples: [FIELD_LEVEL_COUNT]int
		coarse := make([dynamic]Field_Node, context.temp_allocator)
		for node in nodes {
			counts[node.level] += 1
			step := field_node_step(node)
			grid_generation := field_grid_generation(generation, step)
			origin := field_node_origin(node)
			for z in i32(-1) ..= FIELD_GRID_CELLS {
				for y in i32(-1) ..= FIELD_GRID_CELLS {
					for x in i32(-1) ..= FIELD_GRID_CELLS {
						position := sample_to_world_position(origin + Sample_Coordinate([3]i32{x, y, z} * step), generation.spacing_millimetres)
						_, _, _, needs_relief := planet_sample_shortcut(grid_generation, position)
						samples[node.level] += needs_relief ? 1 : 0
					}
				}
			}
			if node.level == FIELD_COARSEST_LEVEL && len(coarse) < 16 {
				append(&coarse, node)
			}
		}
		log.infof("relief cost %s: nodes per level %v, grid samples needing the relief per level %v", place, counts, samples)
		centre := sample_to_field_chunk_coordinate(world_position_to_sample(camera, generation.spacing_millimetres))
		chunk_samples := 0
		for chunk_z in i32(-3) ..= 3 {
			for chunk_y in i32(-3) ..= 3 {
				for chunk_x in i32(-3) ..= 3 {
					origin := field_chunk_origin(centre + {chunk_x, chunk_y, chunk_z})
					for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
						position := sample_to_world_position(origin + Sample_Coordinate(field_index_to_local(index)), generation.spacing_millimetres)
						_, _, _, needs_relief := planet_sample_shortcut(generation, position)
						chunk_samples += needs_relief ? 1 : 0
					}
				}
			}
		}
		log.infof("relief cost %s: samples needing the relief in the 7 by 7 by 7 chunks round the camera %d", place, chunk_samples)
		grid := new(Field_Grid)
		defer free(grid)
		begin := time.tick_now()
		for node in coarse {
			grid^ = {}
			generate_field_grid(generation, node, grid)
		}
		log.infof("relief cost %s: generate_field_grid of %d coarsest nodes %.1f ms", place, len(coarse), f64(time.duration_nanoseconds(time.tick_since(begin))) / 1e6)
	}
}
