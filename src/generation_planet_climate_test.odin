package game

import "core:slice"
import "core:testing"

// Work item 0307: the planet's climate.

// The shipped home planet's generation at 8 km with the default seed.
shipped_climate_test_generation :: proc() -> Planet_Generation {
	return make_planet_generation(DEFAULT_WORLD_SEED, shipped_test_home_at(8000), 1000)
}

// A point on the sphere offset in metres along the tangents at the home.
climate_test_point :: proc(generation: Planet_Generation, ahead, aside: i64) -> [3]i64 {
	home := planet_home_direction(Planet_Home{83, 132})
	forward := tangent_of(home, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, home)
	return test_sphere_point(generation, home, forward, right, ahead, aside)
}

@(test)
test_the_climate_is_off_without_a_climate :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, make_test_planet(), 1000)
	testing.expect_value(t, generation.climate, Planet_Climate_Field{})
	for index in i64(0) ..< 16 {
		testing.expect_value(t, planet_climate(generation, test_line_point(generation, index * 1000), index * 4096), Planet_Climate_Sample{})
	}
}

@(test)
test_the_climate_is_a_pure_function_of_the_seed_and_the_point :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	first := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	again := make_planet_generation(DEFAULT_WORLD_SEED, planet, 500)
	other := make_planet_generation(DEFAULT_WORLD_SEED + 1, planet, 1000)
	differ := 0
	for index in i64(0) ..< 64 {
		point := test_line_point(first, index * 3000)
		height := (index % 9 - 4) * metres_to_position_units(10)
		sample := planet_climate(first, point, height)
		testing.expect_value(t, planet_climate(again, point, height), sample)
		differ += planet_climate(other, point, height) != sample ? 1 : 0
	}
	testing.expectf(t, differ > 32, "another seed changes the climate at %d of 64 points", differ)
}

@(test)
test_the_climate_stays_within_its_spread :: proc(t: ^testing.T) {
	generation := shipped_climate_test_generation()
	field := generation.climate
	temperatures := make([dynamic]i64, context.temp_allocator)
	for row in i64(-32) ..< 32 {
		for column in i64(-32) ..< 32 {
			sample := planet_climate(generation, climate_test_point(generation, row * 200, column * 200), 0)
			append(&temperatures, sample.temperature_millicelsius)
			testing.expect(t, sample.moisture_permille >= 0 && sample.moisture_permille <= 1000)
		}
	}
	slice.sort(temperatures[:])
	lowest := i64(field.sea_level_celsius - field.temperature_spread_celsius) * 1000
	highest := i64(field.sea_level_celsius + field.temperature_spread_celsius) * 1000
	testing.expectf(t, temperatures[0] >= lowest && temperatures[len(temperatures) - 1] <= highest, "the temperature spans %d to %d", temperatures[0], temperatures[len(temperatures) - 1])
	span := temperatures[len(temperatures) * 95 / 100] - temperatures[len(temperatures) * 5 / 100]
	testing.expectf(t, span >= 7000, "the 5th to the 95th percentile span %d millicelsius", span)
}

@(test)
test_the_lapse_cools_the_heights :: proc(t: ^testing.T) {
	generation := shipped_climate_test_generation()
	point := climate_test_point(generation, 300, -200)
	sea := planet_climate(generation, point, 0)
	testing.expect_value(t, planet_climate(generation, point, metres_to_position_units(100)).temperature_millicelsius, sea.temperature_millicelsius - 12000)
	testing.expect_value(t, planet_climate(generation, point, -metres_to_position_units(10)).temperature_millicelsius, sea.temperature_millicelsius + 1200)
	testing.expect_value(t, planet_climate(generation, point, metres_to_position_units(100)).moisture_permille, sea.moisture_permille)
}

@(test)
test_the_climate_varies_smoothly :: proc(t: ^testing.T) {
	generation := shipped_climate_test_generation()
	previous := planet_climate(generation, climate_test_point(generation, -1000, 0), 0)
	for metre in i64(-999) ..= 1000 {
		sample := planet_climate(generation, climate_test_point(generation, metre, 0), 0)
		testing.expectf(t, abs(sample.temperature_millicelsius - previous.temperature_millicelsius) <= 100, "the temperature jumps from %d to %d at %d m", previous.temperature_millicelsius, sample.temperature_millicelsius, metre)
		testing.expectf(t, abs(sample.moisture_permille - previous.moisture_permille) <= 10, "the moisture jumps from %d to %d at %d m", previous.moisture_permille, sample.moisture_permille, metre)
		previous = sample
	}
}
