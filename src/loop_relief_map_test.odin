package game

import "core:os"
import "core:slice"
import "core:testing"
import "platform"

// Work item 0306: the relief map workbench mode.

@(test)
test_the_relief_map_argument_is_checked :: proc(t: ^testing.T) {
	request, problem := parse_relief_map_argument("83,132,4000")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, request, Relief_Map_Request{83, 132, 4000, 0, false})
	request, problem = parse_relief_map_argument("-12.5,-179.5,100,16000")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, request, Relief_Map_Request{-12.5, -179.5, 100, 16000, false})
	request, problem = parse_relief_map_argument("planet")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, request, Relief_Map_Request{radius_metres = 0, whole_planet = true})
	request, problem = parse_relief_map_argument("planet,16000")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, request, Relief_Map_Request{radius_metres = 16000, whole_planet = true})
	for refused in ([?]string{"83,132", "83,132,4000,8000,1", "north,132,4000", "83,,4000", "91,132,4000", "83,-181,4000", "83,132,99", "83,132,20001", "83,132,4000,-1", "83,132,4000.5", "83,132,99999999999999999999", "nan,132,4000", "83,inf,4000", "planet,16000,1", "planets", "planet,-1"}) {
		_, problem = parse_relief_map_argument(refused)
		testing.expectf(t, problem != "", "%q is accepted", refused)
	}
}

// The shipped planet at 8 km round the home, 64 pixels over 4000 m: the
// home's white at the centre, the sea blue, and the PNG written.
@(test)
test_the_relief_map_marks_the_home_and_the_sea :: proc(t: ^testing.T) {
	planet, problem := relief_map_planet(shipped_test_planets(), DEFAULT_WORLD_SEED, 8000)
	testing.expect_value(t, problem, "")
	_, problem = relief_map_planet(shipped_test_planets(), DEFAULT_WORLD_SEED, 5000)
	testing.expect(t, problem != "", "a radius that is no preset is refused")
	generation := baked_planet_generation(make_planet_generation(DEFAULT_WORLD_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES))
	request := Relief_Map_Request{f64(planet.home.latitude_degrees), f64(planet.home.longitude_degrees), 4000, 8000, false}
	pixels := 64
	metres_per_pixel := f64(request.size_metres) / f64(pixels)
	sea := generation.sea_radius - generation.radius
	heights := relief_map_heights(generation, request, pixels, context.temp_allocator)
	colours := relief_map_colours(heights, sea, metres_per_pixel, pixels, context.temp_allocator)
	relief_map_mark(colours, pixels, request, planet.radius_metres, metres_per_pixel, planet_home_direction(planet.home), RELIEF_MAP_HOME_COLOUR, 3)
	testing.expect_value(t, colours[pixels / 2 * pixels + pixels / 2], RELIEF_MAP_HOME_COLOUR)
	sea_found := false
	for height, index in heights {
		if height < sea - metres_to_position_units(1) {
			colour := colours[index]
			sea_found = true
			testing.expectf(t, colour.b > colour.r, "the sea at pixel %d is %v", index, colour)
		}
	}
	testing.expect(t, sea_found, "the map holds sea")
	directory, error := os.make_directory_temp("", "mine-oh-belowed-relief-map-test-*", context.temp_allocator)
	testing.expect(t, error == nil)
	defer os.remove_all(directory)
	path := platform.join_path(directory, "map.png")
	testing.expect_value(t, write_relief_map_png(colours, pixels, pixels, path), "")
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_error == nil && len(data) > 8)
	testing.expect_value(t, string(data[:8]), "\x89PNG\r\n\x1a\n")
}

// The default seed's springs run downhill (the item's spring start): the
// first at 8 km stands at least 20 m over the sea and runs at least 300 m
// and drops 50 m, at 16 km at least 100 m; the second at 8 km at least
// 150 m.
@(test)
test_the_default_springs_stream_runs_downhill :: proc(t: ^testing.T) {
	stream_at :: proc(radius_metres, spring: int) -> (stream: Relief_Map_Stream, ground: i64) {
		planet := shipped_test_home_at(radius_metres)
		generation := baked_planet_generation(make_planet_generation(DEFAULT_WORLD_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES))
		direction := planet_spring_direction(planet.springs[spring])
		ground = surface_relief(generation, fixed_scale(direction, generation.radius)) - (generation.sea_radius - generation.radius)
		return relief_map_stream(generation, direction, context.temp_allocator), ground
	}
	first, ground := stream_at(8000, 0)
	testing.expectf(t, ground >= metres_to_position_units(20), "the first spring's ground stands %d units over the sea", ground)
	testing.expectf(t, first.length_metres >= 300 && first.drop >= metres_to_position_units(50), "the first spring's stream runs %d m and drops %d units", first.length_metres, first.drop)
	testing.expect(t, len(first.trail) <= RELIEF_MAP_STREAM_STEPS, "the trail is capped")
	large, _ := stream_at(16000, 0)
	testing.expectf(t, large.length_metres >= 100, "the first spring's stream runs %d m at 16 km", large.length_metres)
	second, _ := stream_at(8000, 1)
	testing.expectf(t, second.length_metres >= 150, "the second spring's stream runs %d m", second.length_metres)
}

// Work item 0312: the shipped planet at 8 km, 128 pixels over 2000 m round
// the largest lake's refined pit of the tiles' finals round the home
// (0326): its centre pixel is the lake's blue.
@(test) // slow
test_the_relief_map_draws_the_lakes :: proc(t: ^testing.T) {
	planet, problem := relief_map_planet(shipped_test_planets(), DEFAULT_WORLD_SEED, 8000)
	testing.expect_value(t, problem, "")
	cache := make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(cache)
	keys := water_home_tile_keys(cache)
	lakes, _ := take_water_tile_finals(cache, keys[:])
	testing.expect(t, len(lakes) > 0, "the planet has lakes round the home")
	if len(lakes) == 0 {
		return
	}
	slice.sort_by(lakes, water_lake_before)
	largest := lakes[0]
	direction, _ := normalize_fixed(largest.origin)
	latitude, longitude := relief_map_degrees(direction)
	request := Relief_Map_Request{latitude, longitude, 2000, 8000, false}
	pixels := 128
	generation := baked_planet_generation(make_planet_generation(DEFAULT_WORLD_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES))
	heights := relief_map_heights(generation, request, pixels, context.temp_allocator)
	colours := relief_map_colours(heights, generation.sea_radius - generation.radius, f64(request.size_metres) / f64(pixels), pixels, context.temp_allocator)
	relief_map_mark_lakes(colours, heights, generation, request, pixels, lakes)
	testing.expect_value(t, colours[pixels / 2 * pixels + pixels / 2], RELIEF_MAP_LAKE_COLOUR)
}

// Pixels the lake holds and pixels relief_map_mark_lakes paints of a map
// at the radius: a full mask of half 96 round the direction, its level
// over every height of the zero map.
relief_map_test_lake_pixels :: proc(radius_metres: int, request: Relief_Map_Request, pixels: int, direction: [3]i64) -> (held, painted: int) {
	planet, problem := relief_map_planet(shipped_test_planets(), DEFAULT_WORLD_SEED, radius_metres)
	assert(problem == "")
	planet.waters.tile_metres = 0
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	centre, _ := normalize_fixed(direction)
	east, north := planet_tangents(centre)
	half := i64(96)
	side := 2 * half + 1
	lake := Planet_Lake {
		centre = centre,
		east   = east,
		north  = north,
		origin = fixed_scale(centre, generation.radius),
		level  = max(i64) / 4,
		half   = half,
		cells  = i32(side * side),
		mask   = make([]u64, (side * side + 63) / 64, context.temp_allocator),
	}
	for &word in lake.mask {
		word = max(u64)
	}
	heights := make([]i64, pixels * pixels, context.temp_allocator)
	colours := make([][4]u8, pixels * pixels, context.temp_allocator)
	relief_map_mark_lakes(colours, heights, generation, request, pixels, []Planet_Lake{lake})
	metres_per_pixel := f64(request.size_metres) / f64(pixels)
	for row in 0 ..< pixels {
		for column in 0 ..< pixels {
			east_metres := (f64(column) + 0.5 - f64(pixels) / 2) * metres_per_pixel
			north_metres := (f64(pixels) / 2 - f64(row) - 0.5) * metres_per_pixel
			held += planet_lake_holds(lake, relief_map_point(request, radius_metres, east_metres, north_metres), generation.radius) ? 1 : 0
			painted += colours[row * pixels + column] == RELIEF_MAP_LAKE_COLOUR ? 1 : 0
		}
	}
	return
}

// Work item 0326: a lake far from the map's centre, where the gnomonic map
// stretches the ground, is painted whole: at 51.8 degrees from the +x
// face's centre on the net's face map (2 R at 8 km, 3 times stretched)
// and at 70.5 degrees on the largest square map at 4 km (9 times).
@(test)
test_the_relief_map_paints_a_lake_far_from_its_centre :: proc(t: ^testing.T) {
	one :: UNIT_VECTOR_ONE
	held, painted := relief_map_test_lake_pixels(8000, {0, 0, 16000, 8000, false}, 400, {one, one * 9 / 10, one * 9 / 10})
	testing.expectf(t, held > 0 && painted == held, "the net's face: %d pixels held, %d painted", held, painted)
	held, painted = relief_map_test_lake_pixels(4000, {0, 0, RELIEF_MAP_MAXIMUM_METRES, 4000, false}, 400, {one, 2 * one, 2 * one})
	testing.expectf(t, held > 0 && painted == held, "the square: %d pixels held, %d painted", held, painted)
}

// Work item 0326: the planet's net with the waters off at 8 km, 16 pixels
// a face: 64 by 48, the squares (1, 0) to (3, 0) black, the +x square's
// centre pixel the square map's at latitude 0, longitude 0 over 16 km.
@(test)
test_the_planet_relief_map_lays_out_the_faces :: proc(t: ^testing.T) {
	planet, problem := relief_map_planet(shipped_test_planets(), DEFAULT_WORLD_SEED, 8000)
	testing.expect_value(t, problem, "")
	planet.waters = {}
	generation := baked_planet_generation(make_planet_generation(DEFAULT_WORLD_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES))
	face_pixels := 16
	net := relief_map_planet_net(generation, planet, nil, nil, face_pixels, context.temp_allocator)
	testing.expect_value(t, len(net), 64 * 48)
	black := 0
	for row in 0 ..< face_pixels {
		for column in face_pixels ..< 4 * face_pixels {
			black += net[row * 64 + column] == {0, 0, 0, 255} ? 1 : 0
		}
	}
	testing.expect_value(t, black, 3 * face_pixels * face_pixels)
	request := Relief_Map_Request{0, 0, 16000, 8000, false}
	heights := relief_map_heights(generation, request, face_pixels, context.temp_allocator)
	sea := generation.sea_radius - generation.radius
	colours := relief_map_colours(heights, sea, f64(request.size_metres) / f64(face_pixels), face_pixels, context.temp_allocator)
	centre := face_pixels / 2
	testing.expect_value(t, net[(face_pixels + centre) * 64 + centre], colours[centre * face_pixels + centre])
}
