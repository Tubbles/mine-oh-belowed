package game

import "core:fmt"
import "core:log"
import "core:math"
import "core:slice"
import "core:strings"
import "core:testing"
@(require) import "core:time"

// Work item 0312: the springs and the lakes round the shipped home.

// The shipped home at a preset with the home a new world of the seed
// takes.
waters_test_planet :: proc(radius_metres: int, seed := DEFAULT_WORLD_SEED) -> Planet {
	planet := shipped_test_home_at(radius_metres)
	planet.home = new_world_home(seed, planet)
	return planet
}

// The seal's condition on the lake's final level: a point of the 1 m
// lattice in the mask under the level beside one outside it lower than
// the level leaks; the leaks counted.
lake_leaks :: proc(generation: Planet_Generation, lake: Planet_Lake) -> int {
	plane := planet_lake_plane(lake, generation.radius, metres_to_position_units(1))
	heights := make(map[[2]i64]i64, context.temp_allocator)
	reach := 2 * lake.half
	leaks := 0
	for y in -reach ..= reach {
		for x in -reach ..= reach {
			if !planet_lake_lattice_holds(lake, x, y) {
				continue
			}
			for offset in WATERS_FACES {
				if planet_lake_lattice_holds(lake, x + offset[0], y + offset[1]) {
					continue
				}
				if lake_lattice_height(generation, plane, &heights, x, y) < lake.level && lake_lattice_height(generation, plane, &heights, x + offset[0], y + offset[1]) < lake.level {
					leaks += 1
				}
			}
		}
	}
	return leaks
}

// The lake with the most water cells, the first on a tie.
largest_test_lake :: proc(lakes: []Planet_Lake) -> (largest: Planet_Lake, index: int) {
	for lake, lake_index in lakes {
		if lake_index == 0 || lake.cells > largest.cells {
			largest, index = lake, lake_index
		}
	}
	return
}

@(test) // slow
test_the_waters_round_the_shipped_home :: proc(t: ^testing.T) {
	planet := waters_test_planet(8000)
	planet.water_features = make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	defer destroy_planet_water_features(&planet.water_features)
	features := planet.water_features
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	sea := generation.sea_radius - generation.radius
	largest, largest_index := largest_test_lake(features.lakes)
	log.infof("0312: at 8 km %d lakes and %d derived springs; the largest lake %d: %d m2, %.1f m deep, %.1f m over the sea", len(features.lakes), len(features.springs), largest_index, int(largest.cells) * 4, f64(largest.level - largest.floor) / POSITION_UNITS_PER_METRE, f64(largest.level - sea) / POSITION_UNITS_PER_METRE)
	// The design's prototype found 20 lakes on 0322's relief; 0323's gorges, mesas
	// and sinkholes make 31 on this one (34 before a lake within a sample of
	// the sea was refused).
	testing.expectf(t, len(features.lakes) >= 24 && len(features.lakes) <= 48, "%d lakes", len(features.lakes))
	testing.expectf(t, len(features.springs) >= 12 && len(features.springs) <= 32, "%d derived springs", len(features.springs))
	home := fixed_scale(planet_home_direction(planet.home), generation.radius)
	clearing := metres_to_position_units(i64(planet.waters.clearing_metres))
	for lake, index in features.lakes {
		testing.expectf(t, lake.level - lake.floor >= millimetres_to_position_units(planet.waters.lake_minimum_depth_millimetres), "lake %d is %d deep", index, lake.level - lake.floor)
		testing.expectf(t, int(lake.cells) * 4 >= planet.waters.lake_minimum_area_square_metres, "lake %d holds %d cells", index, lake.cells)
		testing.expectf(t, lake.level > sea, "lake %d lies over the sea", index)
		testing.expectf(t, squared_chord(lake.origin, home) >= clearing * clearing, "lake %d lies outside the clearing", index)
		testing.expectf(t, lake_leaks(generation, lake) == 0, "lake %d leaks", index)
	}
	spacing := metres_to_position_units(i64(planet.waters.spring_spacing_metres))
	for spring, index in features.springs {
		point := fixed_scale(spring.direction, generation.radius)
		testing.expectf(t, spring.height - sea >= metres_to_position_units(i64(planet.waters.spring_minimum_metres)), "spring %d stands %d over the sea", index, spring.height - sea)
		testing.expectf(t, squared_chord(point, home) >= clearing * clearing, "spring %d lies outside the clearing", index)
		for record in planet.springs {
			testing.expectf(t, squared_chord(point, fixed_scale(planet_spring_direction(record), generation.radius)) >= spacing * spacing, "spring %d keeps from the record's", index)
		}
		for other, other_index in features.springs {
			if other_index != index {
				testing.expectf(t, squared_chord(point, fixed_scale(other.direction, generation.radius)) >= spacing * spacing, "springs %d and %d keep apart", index, other_index)
			}
		}
	}
	testing.expect(t, features.has_start && features.start == planet_spring_direction(planet.springs[0]), "the tech demo starts at the record's first spring")
	if len(features.lakes) == 0 || len(features.springs) == 0 {
		return
	}
	// The largest lake's chunk holds its water, asleep and no one's.
	lake_point := World_Position(fixed_scale(largest.centre, generation.radius + largest.level - metres_to_position_units(1)))
	chunk := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, sample_to_field_chunk_coordinate(world_position_to_sample(lake_point, 1000)), chunk)
	origin := field_chunk_origin(chunk.coordinate)
	fill_level := planet_lake_fill_level(generation, largest)
	filled := 0
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if chunk.density[index] > 0 {
			continue
		}
		sample := origin + Sample_Coordinate(field_index_to_local(index))
		position := sample_to_world_position(sample, 1000)
		distance := vector_length(cast([3]i64)position)
		on_sphere := project_onto_sphere(position, distance, generation.radius)
		fill := field_sea_fill(fill_level, field_water_span(sample))
		level, found := planet_lake_level_at(features.lakes, on_sphere, generation.radius)
		if !found || level != largest.level || !planet_lake_holds(largest, on_sphere, generation.radius) || fill == 0 || column_carves(surface_column(generation, on_sphere), distance - generation.radius, 1000) {
			continue
		}
		filled += 1
		testing.expect_value(t, i32(chunk.water[index]), fill)
		testing.expect_value(t, chunk.water_owner[index], WATER_OWNER_NONE)
		testing.expect(t, !field_sample_bit(&chunk.water_awake, index) && !field_sample_bit(&chunk.water_source, index), "the lake's water is still")
	}
	testing.expectf(t, filled > 0, "the largest lake's chunk %v holds its water", chunk.coordinate)
	// The first derived spring is a source.
	spring_sample, spring_found := planet_spring_sample_at(generation, features.springs[0].direction)
	testing.expect(t, spring_found, "the first derived spring finds air")
	if spring_found {
		spring_chunk := new(Field_Chunk, context.temp_allocator)
		generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, sample_to_field_chunk_coordinate(spring_sample), spring_chunk)
		testing.expect(t, field_sample_bit(&spring_chunk.water_source, sample_to_field_index(spring_sample)), "the first derived spring is a source")
	}
	// No tree stands in a lake. The box goes in quarters along each axis,
	// within PLANET_TREE_BOX_CELL_LIMIT at the forest's 2 m spacing (0310).
	tree_generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	half := min(largest.bound_radius, metres_to_position_units(120))
	quarter := half / 2
	margin := metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES)
	seen := make(map[Tree_Key]struct{}, context.temp_allocator)
	for x in i64(0) ..< 4 {
		for y in i64(0) ..< 4 {
			for z in i64(0) ..< 4 {
				minimum := largest.origin - half + [3]i64{x, y, z} * quarter
				for tree in planet_trees_in_box(&tree_generation, minimum, minimum + quarter - 1) {
					seen[tree.key] = {}
					on_sphere := tree_test_on_sphere(tree_generation, tree)
					if level, found := planet_lake_level_at(features.lakes, on_sphere, generation.radius); found {
						testing.expectf(t, surface_column(tree_generation, on_sphere).relief >= level + margin, "the tree %v stands in a lake", tree.key)
					}
				}
			}
		}
	}
	// The coarse grid shows the lake where no chunk is loaded.
	node := test_surface_node(lake_point, 1000, 1)
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	coarse := field_grid_generation(generation, grid.step)
	lake_water := 0
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				index := field_grid_index({x, y, z})
				position := sample_to_world_position(grid.origin + Sample_Coordinate([3]i32{x, y, z} * grid.step), 1000)
				if grid.water[index] > planet_sea_density(coarse, position, grid.density[index]) {
					lake_water += 1
				}
			}
		}
	}
	testing.expectf(t, lake_water > 0, "the level 1 grid %v shows the lake", node)
	log.infof("0312: the largest lake's chunk holds %d lake samples, %d trees round it, the level 1 grid %d lake samples", filled, len(seen), lake_water)
}

@(test) // slow
test_the_waters_are_deterministic :: proc(t: ^testing.T) {
	planet := waters_test_planet(8000)
	first := make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	defer destroy_planet_water_features(&first)
	second := make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	defer destroy_planet_water_features(&second)
	testing.expect(t, waters_features_equal(first, second), "two makes of one seed agree")
	other_planet := waters_test_planet(8000, 7)
	other := make_planet_water_features(7, other_planet)
	defer destroy_planet_water_features(&other)
	testing.expect(t, !waters_features_equal(first, other), "seed 7 finds other waters")
}

// Field by field and mask by mask.
waters_features_equal :: proc(first, second: Planet_Water_Features) -> bool {
	if first.start != second.start || first.has_start != second.has_start || !slice.equal(first.springs, second.springs) || len(first.lakes) != len(second.lakes) {
		return false
	}
	for lake, index in first.lakes {
		other := second.lakes[index]
		same := lake.centre == other.centre && lake.east == other.east && lake.north == other.north && lake.origin == other.origin && lake.bound_centre == other.bound_centre && lake.level == other.level && lake.floor == other.floor && lake.bound_radius == other.bound_radius && lake.half == other.half && lake.cells == other.cells
		if !same || !slice.equal(lake.mask, other.mask) {
			return false
		}
	}
	return true
}

// Work item 0312: the generation gives the sea every air sample whose
// span reaches under its level (fill_field_chunk_sea), so at no preset
// does a lake's floor lie within the widest sample spacing of the sea.
@(test) // slow
test_no_lake_lies_within_a_sample_of_the_sea :: proc(t: ^testing.T) {
	clearance := millimetres_to_position_units(WIDEST_SAMPLE_SPACING_MILLIMETRES)
	for radius in ([3]int{4000, 8000, 16000}) {
		planet := waters_test_planet(radius)
		features := make_planet_water_features(DEFAULT_WORLD_SEED, planet)
		defer destroy_planet_water_features(&features)
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		sea := generation.sea_radius - generation.radius
		for lake, index in features.lakes {
			testing.expectf(t, lake.floor - sea >= clearance, "at %d m lake %d's floor stands %d units over the sea", radius, index, lake.floor - sea)
		}
		log.infof("0312: at %d m %d lakes and %d derived springs", radius, len(features.lakes), len(features.springs))
	}
}

// Work item 0312: the lake whose pit lies nearest the latitude and
// longitude in degrees, within a tenth of a degree of latitude; -1 for
// none.
waters_test_lake_near :: proc(lakes: []Planet_Lake, latitude, longitude: f64) -> int {
	nearest, nearest_distance := -1, 0.1
	for lake, index in lakes {
		direction, _ := normalize_fixed(lake.origin)
		lake_latitude, lake_longitude := relief_map_degrees(direction)
		across := (lake_longitude - longitude) * math.cos(math.to_radians(latitude))
		if distance := math.sqrt((lake_latitude - latitude) * (lake_latitude - latitude) + across * across); distance < nearest_distance {
			nearest, nearest_distance = index, distance
		}
	}
	return nearest
}

// The chunk at 1 m spacing holding the point 1 m over the lake's floor
// under its origin, the centre of the 27 the lake tests insert.
shipped_lake_centre_chunk :: proc(generation: Planet_Generation, lake: Planet_Lake) -> Field_Chunk_Coordinate {
	direction, _ := normalize_fixed(lake.origin)
	point := World_Position(fixed_scale(direction, generation.radius + lake.floor + metres_to_position_units(1)))
	return sample_to_field_chunk_coordinate(world_position_to_sample(point, 1000))
}

// Work item 0312: the 27 chunks round a shipped lake's pit at 8 km and
// 1 m, under bodies with the shipped tuning, settle with nothing awake and
// no still water no one owns. The lake at 72.02, 143.04 never settled
// while claimed still water joined a body asleep (a second body's flood
// released it as front at its spill); the one at 71.69, 136.82 kept a
// pocket no flood reached while an arriving chunk woke only its lowest
// sample.
@(test) // slow
test_shipped_lakes_settle_under_bodies :: proc(t: ^testing.T) {
	planet := waters_test_planet(8000)
	planet.water_features = make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	defer destroy_planet_water_features(&planet.water_features)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	tuning := make_field_water_tuning(test_field_game_config().field_water)
	for place in ([2][2]f64{{72.02, 143.04}, {71.69, 136.82}}) {
		index := waters_test_lake_near(planet.water_features.lakes, place[0], place[1])
		testing.expectf(t, index >= 0, "a lake lies at %v", place)
		if index < 0 {
			continue
		}
		centre := shipped_lake_centre_chunk(generation, planet.water_features.lakes[index])
		world: Field_World
		world.water_model = .Bodies
		world.water_planet = make_field_water_planet(DEFAULT_WORLD_SEED, planet, 1000)
		make_sea_water_body(&world)
		for dz in i32(-1) ..= 1 {
			for dy in i32(-1) ..= 1 {
				for dx in i32(-1) ..= 1 {
					chunk := new(Field_Chunk)
					generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, centre + Field_Chunk_Coordinate{dx, dy, dz}, chunk)
					field_world_insert_chunk(&world, chunk)
				}
			}
		}
		tick: u64 = 0
		ticks := settle_body_test_water(&world, tuning, &tick, 600)
		testing.expectf(t, ticks < 600, "the lake at %v settles", place)
		testing.expectf(t, still_unowned_water_samples(&world) == 0, "the lake at %v keeps %d samples of still water no one owns", place, still_unowned_water_samples(&world))
		log.infof("0312: the lake at %v settled after %d ticks into %d bodies", place, ticks, alive_water_body_count(&world))
		destroy_field_world(&world)
	}
}

// Work item 0334: three shipped lakes at 8 km and 1 m whose chunks arrive
// one by one, as they do while the player walks: the centre settled, its
// 26 neighbours 30 ticks apart, then settled with nothing awake and no
// still water no one owns. Two bodies spilling at one saddle released
// each other in turn while the chunks streamed in (234, 893 and 1,758
// samples awake after 2000 ticks before 0334).
@(test) // slow
test_shipped_lakes_settle_under_bodies_streamed :: proc(t: ^testing.T) {
	planet := waters_test_planet(8000)
	planet.water_features = make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	defer destroy_planet_water_features(&planet.water_features)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	tuning := make_field_water_tuning(test_field_game_config().field_water)
	for place in ([3][2]f64{{65.17, 151.40}, {72.02, 143.04}, {71.69, 136.82}}) {
		index := waters_test_lake_near(planet.water_features.lakes, place[0], place[1])
		testing.expectf(t, index >= 0, "a lake lies at %v", place)
		if index < 0 {
			continue
		}
		centre := shipped_lake_centre_chunk(generation, planet.water_features.lakes[index])
		world: Field_World
		world.water_model = .Bodies
		world.water_planet = make_field_water_planet(DEFAULT_WORLD_SEED, planet, 1000)
		make_sea_water_body(&world)
		chunk := new(Field_Chunk)
		generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, centre, chunk)
		field_world_insert_chunk(&world, chunk)
		tick: u64 = 0
		first := settle_body_test_water(&world, tuning, &tick, 600)
		testing.expectf(t, first < 600, "the centre of the lake at %v settles", place)
		for dz in i32(-1) ..= 1 {
			for dy in i32(-1) ..= 1 {
				for dx in i32(-1) ..= 1 {
					if dx == 0 && dy == 0 && dz == 0 {
						continue
					}
					neighbour := new(Field_Chunk)
					generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, centre + Field_Chunk_Coordinate{dx, dy, dz}, neighbour)
					field_world_insert_chunk(&world, neighbour)
					for _ in 0 ..< 30 {
						tick += 1
						step_field_water(&world, tuning, tick)
					}
				}
			}
		}
		ticks := settle_body_test_water(&world, tuning, &tick, 600)
		testing.expectf(t, ticks < 600, "the lake at %v settles streamed", place)
		testing.expectf(t, !any_water_awake(&world), "the lake at %v keeps nothing awake", place)
		testing.expectf(t, still_unowned_water_samples(&world) == 0, "the lake at %v keeps %d samples of still water no one owns", place, still_unowned_water_samples(&world))
		log.infof("0334: the lake at %v settled %d ticks after the last arrival into %d bodies", place, ticks, alive_water_body_count(&world))
		destroy_field_world(&world)
	}
}

@(test) // slow
test_the_tech_demo_start_follows_the_longest_fall :: proc(t: ^testing.T) {
	small := waters_test_planet(4000)
	small_features := make_planet_water_features(DEFAULT_WORLD_SEED, small)
	defer destroy_planet_water_features(&small_features)
	derived := false
	for spring in small_features.springs {
		derived ||= small_features.has_start && spring.direction == small_features.start
	}
	testing.expect(t, derived, "at 4 km the start is a derived spring")
	large := waters_test_planet(16000)
	large_features := make_planet_water_features(DEFAULT_WORLD_SEED, large)
	defer destroy_planet_water_features(&large_features)
	testing.expect(t, large_features.has_start && large_features.start == planet_spring_direction(large.springs[1]), "at 16 km the start is the record's second spring")

	config := test_field_game_config()
	content := make_field_test_game_content()
	content.planets = shipped_test_planets()
	session, problem := start_tech_demo_session(config, content, make_test_generator(DEFAULT_WORLD_SEED), DEFAULT_WORLD_SEED, {water_model = .Bodies, planet_radius_metres = 4000, start = .Spring})
	testing.expect_value(t, problem, "")
	if session == nil {
		return
	}
	defer end_session(session)
	start := session.planet.water_features.start
	testing.expect(t, session.planet.water_features.has_start && start == small_features.start, "the session finds the same start")
	generation := make_planet_generation(DEFAULT_WORLD_SEED, session.planet, session.simulation.field.spacing_millimetres)
	surface := field_surface_under(generation, World_Position(fixed_scale(start, generation.radius)), 0)
	feet := session.simulation.players[0].field.position
	testing.expectf(t, vector_length(cast([3]i64)(feet - surface)) <= 2 * POSITION_UNITS_PER_METRE, "the feet stand %d units from the start's surface", vector_length(cast([3]i64)(feet - surface)))
	radial, _ := normalize_fixed(cast([3]i64)feet)
	testing.expectf(t, fixed_dot(radial, start) >= UNIT_VECTOR_ONE - 2, "the feet lie on the start's radial (dot %d)", fixed_dot(radial, start))
}

@(test)
test_the_waters_are_off_without_their_keys :: proc(t: ^testing.T) {
	planet := design_landform_test_planet(8000)
	features := make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	testing.expect(t, features.springs == nil && features.lakes == nil && !features.has_start, "no waters without the keys")
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	sample, found := planet_spring_sample(generation, planet.springs[0])
	testing.expect(t, found, "the spring finds air")
	chunk := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, sample_to_field_chunk_coordinate(sample), chunk)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if chunk.water[index] > 0 && chunk.water_owner[index] == WATER_OWNER_NONE {
			testing.expectf(t, field_sample_bit(&chunk.water_source, index), "sample %d holds water no one owns", index)
		}
	}
}

@(test)
test_waters_problems :: proc(t: ^testing.T) {
	testing.expect_value(t, waters_problem({}), "")
	shipped := default_planet(shipped_test_planets()).waters
	testing.expect_value(t, waters_problem(shipped), "")
	Case :: struct {
		key:   string,
		value: int,
	}
	cases := [?]Case {
		{"reach_metres", 255},
		{"reach_metres", 8193},
		{"grid_metres", 3},
		{"grid_metres", 65},
		{"clearing_metres", -1},
		{"clearing_metres", 2501},
		{"spring_catchment_square_metres", 4_000_001},
		{"spring_minimum_metres", -1},
		{"spring_minimum_metres", MAXIMUM_RELIEF_HEIGHT_METRES + 1},
		{"spring_spacing_metres", 399},
		{"spring_spacing_metres", 10_001},
		{"lake_minimum_depth_millimetres", 99},
		{"lake_minimum_depth_millimetres", 64_001},
		{"lake_minimum_area_square_metres", 3},
		{"lake_minimum_area_square_metres", 1_000_001},
		{"lake_maximum_metres", 15},
		{"lake_maximum_metres", 1025},
		{"lake_margin_millimetres", -1},
		{"lake_margin_millimetres", 4001},
	}
	for entry in cases {
		waters := shipped
		switch entry.key {
		case "reach_metres":
			waters.reach_metres = entry.value
		case "grid_metres":
			waters.grid_metres = entry.value
		case "clearing_metres":
			waters.clearing_metres = entry.value
		case "spring_catchment_square_metres":
			waters.spring_catchment_square_metres = entry.value
		case "spring_minimum_metres":
			waters.spring_minimum_metres = entry.value
		case "spring_spacing_metres":
			waters.spring_spacing_metres = entry.value
		case "lake_minimum_depth_millimetres":
			waters.lake_minimum_depth_millimetres = entry.value
		case "lake_minimum_area_square_metres":
			waters.lake_minimum_area_square_metres = entry.value
		case "lake_maximum_metres":
			waters.lake_maximum_metres = entry.value
		case "lake_margin_millimetres":
			waters.lake_margin_millimetres = entry.value
		}
		problem := waters_problem(waters)
		testing.expectf(t, strings.has_prefix(problem, fmt.tprintf("waters.%s %d is outside", entry.key, entry.value)), "%s %d: %q", entry.key, entry.value, problem)
	}
	testing.expect_value(t, waters_problem({}), "")
	wide := shipped
	wide.reach_metres, wide.grid_metres = 8192, 8
	testing.expect_value(t, waters_problem(wide), "waters.reach_metres 8192 is 1024 cells of grid_metres 8, more than 512")
	fine := shipped
	fine.spring_catchment_square_metres = shipped.grid_metres * shipped.grid_metres - 1
	testing.expect_value(t, waters_problem(fine), "waters.spring_catchment_square_metres 255 is outside 256 to 4000000")
	text := string(#load("../data/planets.sjson"))
	missing, _ := strings.replace(text, "lake_margin_millimetres = 500", "", 1, context.temp_allocator)
	expect_planets_problem(t, missing, "planets[0].waters is missing lake_margin_millimetres")
}

// A world file written before the waters keeps its springs and has no
// lakes, with one log line.
@(test)
test_an_old_world_file_keeps_its_springs_and_has_no_lakes :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	planet := default_planet(planets)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = planet.id},
		planet_generation = planet_generation_record(planet),
	}
	text := string(encode_world_file(file, context.temp_allocator))
	start := strings.index(text, "waters")
	testing.expect(t, start >= 0, "the world file records the waters")
	if start < 0 {
		return
	}
	end := start + strings.index_byte(text[start:], '}') + 1
	older := strings.concatenate({text[:start], text[end:]}, context.temp_allocator)
	testing.expect(t, !strings.contains(older, "waters"), "the old text holds no waters")
	parsed, problem := parse_world_file(transmute([]byte)older, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.waters, Planet_Waters{})
	testing.expect(t, strings.contains(recorded_waters_note(parsed.planet_generation, planet), "records no waters"), "the old file's note")
	testing.expect_value(t, recorded_waters_note(planet_generation_record(planet), planet), "")
	_, resolved_planet, record := resolve_world_planet(parsed.settings, parsed.planet_generation, planets, true)
	recorded := make_recorded_planet(resolved_planet, record, context.temp_allocator)
	testing.expect_value(t, recorded.waters, Planet_Waters{})
	features := make_planet_water_features(DEFAULT_WORLD_SEED, recorded)
	testing.expect(t, features.springs == nil && features.lakes == nil && !features.has_start, "the old world has no waters")
	testing.expect_value(t, len(recorded.springs), len(planet.springs))
	direction, found := planet_spring_start(recorded)
	testing.expect(t, found && direction == planet_spring_direction(planet.springs[0]), "the old world's tech demo starts at its first spring")
}

@(test)
test_a_new_world_records_its_waters :: proc(t: ^testing.T) {
	planet := default_planet(shipped_test_planets())
	record := planet_generation_record(planet)
	testing.expect(t, planet.waters != {}, "the shipped home has waters")
	testing.expect_value(t, record.waters, planet.waters)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = planet.id},
		planet_generation = record,
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.waters, planet.waters)
	testing.expect_value(t, make_recorded_planet(planet, parsed.planet_generation, context.temp_allocator).waters, planet.waters)
}

// Measured, not asserted (0312), so it runs only with the define: per
// preset the finder's wall time and counts, a lake chunk's generation
// against the home's surface chunk, and a tech demo session at 8 km per
// water model at the start for 600 ticks. Run alone with
// ./build.sh test quick game.test_report_the_waters_cost -o:speed -define:WATERS_COST=true
// or in ./build.sh nightly.
WATERS_COST :: #config(WATERS_COST, false)

when WATERS_COST {
	@(test)
	test_report_the_waters_cost :: proc(t: ^testing.T) {
		for radius in ([3]int{4000, 8000, 16000}) {
			planet := waters_test_planet(radius)
			begin := time.tick_now()
			features := make_planet_water_features(DEFAULT_WORLD_SEED, planet)
			elapsed := time.tick_since(begin)
			largest, _ := largest_test_lake(features.lakes)
			log.infof("waters cost at %d m: the finder %.0f ms, %d lakes, %d derived springs, the largest lake %d m2", radius, time.duration_milliseconds(elapsed), len(features.lakes), len(features.springs), int(largest.cells) * 4)
			if radius == 8000 && len(features.lakes) > 0 {
				planet.water_features = features
				generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
				lake_point := World_Position(fixed_scale(largest.centre, generation.radius + largest.level - metres_to_position_units(1)))
				site, _ := field_home_site(generation, planet)
				for coordinate, index in ([2]Field_Chunk_Coordinate{sample_to_field_chunk_coordinate(world_position_to_sample(lake_point, 1000)), sample_to_field_chunk_coordinate(world_position_to_sample(site, 1000))}) {
					best := max(f64)
					for _ in 0 ..< 5 {
						chunk := new(Field_Chunk, context.temp_allocator)
						chunk_begin := time.tick_now()
						generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, chunk)
						best = min(best, time.duration_milliseconds(time.tick_since(chunk_begin)))
					}
					log.infof("waters cost: generate_field_chunk of %s %.2f ms (best of 5)", index == 0 ? "the largest lake's chunk" : "the home's surface chunk", best)
				}
			}
			destroy_planet_water_features(&features)
		}
		config := test_field_game_config()
		content := make_field_test_game_content()
		content.planets = shipped_test_planets()
		for model in ([2]Water_Model{.Teleport, .Bodies}) {
			session, problem := start_tech_demo_session(config, content, make_test_generator(DEFAULT_WORLD_SEED), DEFAULT_WORLD_SEED, {water_model = model, planet_radius_metres = 8000, start = .Spring})
			testing.expect_value(t, problem, "")
			if session == nil {
				continue
			}
			simulation_content := session_simulation_content(content, session.technologies, session.field_content)
			worst, total: f64
			for _ in 0 ..< 600 {
				tick_begin := time.tick_now()
				tick_field_test_simulation(&session.simulation, simulation_content, {})
				spent := time.duration_milliseconds(time.tick_since(tick_begin))
				worst, total = max(worst, spent), total + spent
			}
			census := field_water_census(&session.simulation.field.world)
			log.infof("waters cost: the tech demo at 8 km under %v, 600 ticks: worst %.2f ms, mean %.3f ms, %d awake samples at the end", model, worst, total / 600, census.awake_samples)
			end_session(session)
		}
	}
}
