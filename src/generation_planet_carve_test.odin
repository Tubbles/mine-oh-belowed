package game

import "core:strings"
import "core:testing"

// Work item 0324: the arches, grottos and mushroom rocks carved under
// their raise.

// The landmarks' design planet (design_landmark_test_planet) with the
// carving kinds as the design tuned them, so a later data retune leaves
// the tests.
design_carving_test_planet :: proc(radius_metres: int) -> Planet {
	planet := design_landmark_test_planet(radius_metres)
	planet.landmarks.arch_percent = 10
	planet.landmarks.grotto_percent = 10
	planet.landmarks.mushroom_percent = 10
	planet.landmarks.arch_length_metres = {30, 48}
	planet.landmarks.arch_metres = {18, 28}
	planet.landmarks.grotto_radius_metres = {18, 28}
	planet.landmarks.grotto_metres = {12, 20}
	planet.landmarks.mushroom_radius_metres = {7, 12}
	planet.landmarks.mushroom_metres = {9, 16}
	return planet
}

// The nearest site of the kind to the home within 1500 m.
test_nearest_carving_site :: proc(generation: Planet_Generation, kind: Landmark_Kind) -> Landmark_Site {
	sites := test_landmark_sites(generation, kind, 1500)
	assert(len(sites) > 0)
	return sites[0]
}

// The position above the radius by the height along the point's radial.
test_radial_position :: proc(generation: Planet_Generation, point: [3]i64, height: i64) -> World_Position {
	up, _ := normalize_fixed(point)
	return World_Position(fixed_scale(up, generation.radius + height))
}

// The prototype's golden values (tmp/0323/proto, mode carve-goldens,
// with the site outline's wobble and a carving kind's outline roughening
// weighted to vanish at the rim): an arch's fin, an arch's opening and a grotto's
// tunnel, 0323's mesa and spire unchanged by the carving kinds, and the
// carve's distance over the ground.
@(test)
test_the_carve_matches_the_design :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_carving_test_planet(8000), 1000)
	Golden :: struct {
		latitude, longitude: int,
		relief:              i64,
	}
	reliefs := [?]Golden{{77, 144, 214467}, {80, 160, 210923}, {86, 7, 44319}, {86, 8, 34931}, {86, 9, 5}, {85, 155, 26025}, {80, 110, 146011}}
	for golden in reliefs {
		relief := uncratered_relief(generation, test_degree_point(generation, golden.latitude, golden.longitude))
		testing.expectf(t, relief == golden.relief, "(%d, %d): %d", golden.latitude, golden.longitude, relief)
	}
	Column_Golden :: struct {
		latitude, longitude:  int,
		kind:                 Landmark_Kind,
		ground, along, across: i64,
		distances:            [6]i64,
	}
	columns := [?]Column_Golden {
		{86, 7, .Grotto, -3250, -10493, 12001, {-4096, -8192, -7039, 7586, 23301, 39340}},
		{80, 160, .Arch, 197349, 12386, 20295, {-4096, -8192, -14169, -7254, 920, 9132}},
		{77, 144, .Arch, 140031, 26431, 2831, {-2080, -1406, 300, 4931, 10816, 17679}},
	}
	heights := [6]i64{1, 2, 4, 8, 12, 16}
	for golden in columns {
		column := uncratered_column(generation, test_degree_point(generation, golden.latitude, golden.longitude))
		testing.expect_value(t, column.carve.site.kind, golden.kind)
		testing.expect_value(t, column.carve.ground, golden.ground)
		testing.expect_value(t, column.carve.along, golden.along)
		testing.expect_value(t, column.carve.across, golden.across)
		for height, index in heights {
			testing.expectf(t, landmark_carve_distance(column.carve, metres_to_position_units(height)) == golden.distances[index], "(%d, %d) at %d m: %d", golden.latitude, golden.longitude, height, landmark_carve_distance(column.carve, metres_to_position_units(height)))
		}
	}
}

// Carved air under ground a spacing thick is shaded, carved air open
// above is not, and ground stays ground.
@(test)
test_carved_air_is_shaded_under_a_roof :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_carving_test_planet(8000), 1000)
	Probe :: struct {
		latitude, longitude: int,
		ground:              i64,
		height_metres:       i64,
		air, shaded:         bool,
	}
	probes := [?]Probe {
		{86, 7, -3250, 2, true, true},
		{86, 7, -3250, 9, false, false},
		{86, 7, -3250, -1, false, false},
		{80, 160, 197349, 1, true, false},
		{77, 144, 140031, 1, true, true},
		{77, 144, 140031, 8, false, false},
	}
	for probe in probes {
		point := test_degree_point(generation, probe.latitude, probe.longitude)
		sample, shaded := planet_sample_shaded(generation, test_radial_position(generation, point, probe.ground + metres_to_position_units(probe.height_metres)))
		testing.expectf(t, (sample.density <= 0) == probe.air, "(%d, %d) at %d m: density %d", probe.latitude, probe.longitude, probe.height_metres, sample.density)
		testing.expectf(t, shaded == probe.shaded, "(%d, %d) at %d m: shaded %v", probe.latitude, probe.longitude, probe.height_metres, shaded)
	}
}

// Over the three nearest sites of each carving kind, on a 1 m grid and
// by half metres from the ground less 2 m to the relief plus 2 m: the
// depth never exceeds the height map's, the ground under both the ground
// and the top stays ground, the air over the top stays air, and the
// carved heights over the ground are one span from the ground up.
@(test)
test_the_carve_stays_between_the_ground_and_the_surface :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_carving_test_planet(8000), 1000)
	half := metres_to_position_units(1) / 2
	carved_columns := 0
	for kind in ([3]Landmark_Kind{.Arch, .Grotto, .Mushroom}) {
		sites := test_landmark_sites(generation, kind, 1500)
		testing.expectf(t, len(sites) >= 3, "%v: %d sites", kind, len(sites))
		for site in sites[:min(3, len(sites))] {
			direction, _ := normalize_fixed(site.centre)
			forward := tangent_of(direction, {UNIT_VECTOR_ONE, 0, 0})
			right := fixed_cross(forward, direction)
			reach := (landmark_site_outer(site) + POSITION_UNITS_PER_METRE - 1) / POSITION_UNITS_PER_METRE
			for ahead in -reach ..= reach {
				for aside in -reach ..= reach {
					column := uncratered_column(generation, test_sphere_point(generation, direction, forward, right, ahead, aside))
					if column.carve.site.kind not_in CARVING_KINDS {
						continue
					}
					carved_columns += 1
					if !test_column_keeps_the_carve_between(t, column, half) {
						return
					}
				}
			}
		}
	}
	testing.expect(t, carved_columns > 1000, "the sites hold carving columns")
}

// One column's checks; false after the first failure.
test_column_keeps_the_carve_between :: proc(t: ^testing.T, column: Surface_Column, step: i64) -> bool {
	ground := column.carve.ground
	uncarved_below := false
	for height := ground - metres_to_position_units(2); height <= column.relief + metres_to_position_units(2); height += step {
		depth := column_depth(column, height)
		ok := depth <= column.relief - height
		if height < ground && height < column.relief {
			ok &&= depth > 0
		}
		if height >= column.relief {
			ok &&= depth <= 0
		}
		if height >= ground {
			carved := landmark_carve_distance(column.carve, height - ground) <= 0
			ok &&= !(carved && uncarved_below)
			uncarved_below ||= !carved
		}
		if !ok {
			testing.expectf(t, false, "%v at %v: height %d over ground %d under relief %d, depth %d", column.carve.site.kind, column.carve.site.centre, height, ground, column.relief, depth)
			return false
		}
	}
	return true
}

// The sample nearest the height over the site's ground (or over its top)
// at its centre.
test_site_sample :: proc(generation: Planet_Generation, site: Landmark_Site, over_ground: bool, height: i64) -> Sample_Coordinate {
	column := uncratered_column(generation, site.centre)
	base := over_ground ? column.carve.ground : column.relief
	return nearest_field_sample(test_radial_position(generation, site.centre, base + height), generation.spacing_millimetres)
}

// The nearest arch (379 m from the home, 28 m high): the sample 2 m over
// the ground at its centre lies under the roof, so its chunk generates
// it without sky the same way twice; the fill over the chunks round it
// lights it dimmer than the open sky 2 m over the top.
@(test) // slow
test_the_fill_lights_the_air_under_an_arch :: proc(t: ^testing.T) {
	planet := design_carving_test_planet(8000)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	site := test_nearest_carving_site(generation, .Arch)
	under := test_site_sample(generation, site, true, metres_to_position_units(2))
	over := test_site_sample(generation, site, false, metres_to_position_units(2))
	coordinate := sample_to_field_chunk_coordinate(under)
	first := new(Field_Chunk, context.temp_allocator)
	second := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, first)
	generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, second)
	testing.expect(t, first.density == second.density && first.material == second.material && first.tint == second.tint, "the chunk generates the same bytes")
	testing.expect(t, first.sky_light == second.sky_light && first.block_light == second.block_light, "the chunk generates the same light")
	index := sample_to_field_index(under)
	testing.expect(t, first.density[index] <= 0, "the sample under the arch is air")
	testing.expect_value(t, first.sky_light[index], 0)
	testing.expect(t, first.generated_shade, "the chunk holds shade")
	world: Field_World
	defer destroy_field_world(&world)
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				chunk := new(Field_Chunk)
				generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate + {x, y, z}, chunk)
				field_world_insert_chunk(&world, chunk)
			}
		}
	}
	seed_arrived_field_chunks(&world, max(int))
	run_test_light(&world, make_field_light_tuning(test_lighting_file(), 1000))
	sky := field_world_get_light(&world, under, .Sky)
	testing.expectf(t, sky >= 1 && sky < FIELD_LIGHT_FULL, "the sky under the arch is %d", sky)
	testing.expect_value(t, field_world_get_light(&world, over, .Sky), FIELD_LIGHT_FULL)
	for _, chunk in world.chunks {
		testing.expect(t, !chunk.generated_shade, "the arrival cleared the shade")
	}
}

// A coarse grid shades a grotto's roofed air where the design without
// the carving kinds shades nothing.
@(test) // slow
test_a_coarse_grid_shades_a_grotto :: proc(t: ^testing.T) {
	carving := make_planet_generation(DEFAULT_WORLD_SEED, design_carving_test_planet(8000), 1000)
	site := test_nearest_carving_site(carving, .Grotto)
	column := uncratered_column(carving, site.centre)
	node := test_surface_node(test_radial_position(carving, site.centre, column.carve.ground + metres_to_position_units(3)), 1000, 2)
	testing.expect_value(t, test_grid_dark_air(carving, node), true)
	landmarks := make_planet_generation(DEFAULT_WORLD_SEED, design_landmark_test_planet(8000), 1000)
	testing.expect_value(t, test_grid_dark_air(landmarks, node), false)
}

// Whether the node's generated grid holds an air sample without sky.
test_grid_dark_air :: proc(generation: Planet_Generation, node: Field_Node) -> bool {
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	for density, index in grid.density {
		if density <= 0 && grid.sky_light[index] == 0 {
			return true
		}
	}
	return false
}

// No tree stands on the nearest arch's fin, where the plain without the
// carving kinds takes one.
@(test)
test_no_tree_stands_on_a_carving_site :: proc(t: ^testing.T) {
	carving := make_planet_generation(DEFAULT_WORLD_SEED, design_carving_test_planet(8000), 1000)
	site := test_nearest_carving_site(carving, .Arch)
	_, on_fin := planet_tree_from_candidate(carving, {}, site.centre, 1, NOISE_ONE * 100)
	testing.expect(t, !on_fin, "no tree on the arch")
	landmarks := make_planet_generation(DEFAULT_WORLD_SEED, design_landmark_test_planet(8000), 1000)
	_, on_plain := planet_tree_from_candidate(landmarks, {}, site.centre, 1, NOISE_ONE * 100)
	testing.expect(t, on_plain, "a tree on the plain without the arch")
}

// A world.sjson recorded with the landmarks but before the carving kinds
// (its nine keys 0, as a file of before reads them), loaded against data
// that has them: one log line, no carving shares and the ground of
// before at the nearest arch.
@(test) // slow
test_a_world_file_before_the_carving_keeps_its_ground :: proc(t: ^testing.T) {
	old := design_landmark_test_planet(8000)
	carving := design_carving_test_planet(8000)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = old.id},
		planet_generation = planet_generation_record(old),
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect(t, strings.contains(recorded_carving_note(parsed.planet_generation, carving), "records no arches"), "the old file's note")
	testing.expect_value(t, recorded_carving_note(planet_generation_record(carving), carving), "")
	planets := []Planet{carving}
	_, planet, record := resolve_world_planet(parsed.settings, parsed.planet_generation, planets, true)
	recorded := make_recorded_planet(planet, record, context.temp_allocator)
	testing.expect_value(t, recorded.landmarks.arch_percent, 0)
	testing.expect_value(t, recorded.landmarks.grotto_percent, 0)
	testing.expect_value(t, recorded.landmarks.mushroom_percent, 0)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, carving, 1000)
	site := test_nearest_carving_site(generation, .Arch)
	coordinate := sample_to_field_chunk_coordinate(test_site_sample(generation, site, true, metres_to_position_units(2)))
	sources := [3]Planet{recorded, old, carving}
	chunks: [3]^Field_Chunk
	for &chunk, index in chunks {
		chunk = new(Field_Chunk, context.temp_allocator)
		generate_field_chunk(DEFAULT_WORLD_SEED, sources[index], 1000, coordinate, chunk)
	}
	testing.expect(t, chunks[0].density == chunks[1].density && chunks[0].material == chunks[1].material, "the recorded world generates the ground of before")
	testing.expect(t, chunks[0].density != chunks[2].density, "the data's carving kinds would change it")
}
