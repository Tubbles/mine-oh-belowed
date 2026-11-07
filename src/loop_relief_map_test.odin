package game

import "core:os"
import "core:testing"
import "platform"

// Work item 0306: the relief map workbench mode.

@(test)
test_the_relief_map_argument_is_checked :: proc(t: ^testing.T) {
	request, problem := parse_relief_map_argument("83,132,4000")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, request, Relief_Map_Request{83, 132, 4000, 0})
	request, problem = parse_relief_map_argument("-12.5,-179.5,100,16000")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, request, Relief_Map_Request{-12.5, -179.5, 100, 16000})
	for refused in ([?]string{"83,132", "83,132,4000,8000,1", "north,132,4000", "83,,4000", "91,132,4000", "83,-181,4000", "83,132,99", "83,132,20001", "83,132,4000,-1", "83,132,4000.5", "83,132,99999999999999999999", "nan,132,4000", "83,inf,4000"}) {
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
	request := Relief_Map_Request{f64(planet.home.latitude_degrees), f64(planet.home.longitude_degrees), 4000, 8000}
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
	testing.expect_value(t, write_relief_map_png(colours, pixels, path), "")
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
// the largest lake's refined pit: its centre pixel is the lake's blue.
@(test) // slow
test_the_relief_map_draws_the_lakes :: proc(t: ^testing.T) {
	planet, problem := relief_map_planet(shipped_test_planets(), DEFAULT_WORLD_SEED, 8000)
	testing.expect_value(t, problem, "")
	planet.water_features = make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	defer destroy_planet_water_features(&planet.water_features)
	testing.expect(t, len(planet.water_features.lakes) > 0, "the planet has lakes")
	if len(planet.water_features.lakes) == 0 {
		return
	}
	largest, _ := largest_test_lake(planet.water_features.lakes)
	direction, _ := normalize_fixed(largest.origin)
	latitude, longitude := relief_map_degrees(direction)
	request := Relief_Map_Request{latitude, longitude, 2000, 8000}
	pixels := 128
	generation := baked_planet_generation(make_planet_generation(DEFAULT_WORLD_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES))
	heights := relief_map_heights(generation, request, pixels, context.temp_allocator)
	colours := relief_map_colours(heights, generation.sea_radius - generation.radius, f64(request.size_metres) / f64(pixels), pixels, context.temp_allocator)
	relief_map_mark_lakes(colours, heights, generation, request, pixels)
	testing.expect_value(t, colours[pixels / 2 * pixels + pixels / 2], RELIEF_MAP_LAKE_COLOUR)
}
