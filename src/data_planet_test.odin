package game

import "core:slice"
import "core:strings"
import "core:testing"

TEST_PLANET_RECORD :: `planets = [{
	id = "home"
	radius_metres = 8000
	radius_presets_metres = [4000, 8000]
	surface_gravity_centimetres_per_second_squared = 981
	bedrock_depth_metres = 256
	sea_level_metres = 0
	springs = [{latitude_degrees = 88, longitude_degrees = -120}]
	rain_fill_per_minute = 2
	rotation_period_seconds = 1200
	relief_octaves = [{wavelength_metres = 512, amplitude_metres = 24}, {wavelength_metres = 128, amplitude_metres = 8}, {wavelength_metres = 32, amplitude_metres = 2}]
	palette = [[1, 2, 3], [4, 5, 6]]
}]`

// The shipped planets, in the temp allocator.
shipped_test_planets :: proc() -> []Planet {
	planets, problem := parse_planets_file(#load("../data/planets.sjson"), PLANETS_FILE_NAME, context.temp_allocator)
	assert(problem == "", problem)
	return planets
}

expect_planets_problem :: proc(t: ^testing.T, text, expected: string, location := #caller_location) {
	_, problem := parse_planets_file(transmute([]byte)text, PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect(t, strings.contains(problem, expected), problem, loc = location)
}

@(test)
test_the_shipped_planets_file_loads :: proc(t: ^testing.T) {
	planets, problem := parse_planets_file(#load("../data/planets.sjson"), PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect_value(t, problem, "")
	home, found := find_planet(planets, "home")
	testing.expect(t, found)
	testing.expect_value(t, home.radius_metres, 8000)
	testing.expect_value(t, home.bedrock_depth_metres, 256)
	testing.expect(t, slice.equal(home.radius_presets_metres, []int{4000, 8000, 16000}))
	testing.expect_value(t, home.relief_octaves[0], Relief_Octave{512, 24})
}

@(test)
test_a_planet_record_parses :: proc(t: ^testing.T) {
	planets, problem := parse_planets_file(transmute([]byte)string(TEST_PLANET_RECORD), PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(planets), 1)
	testing.expect_value(t, planets[0].surface_gravity_centimetres_per_second_squared, 981)
	testing.expect_value(t, planets[0].rotation_period_seconds, 1200)
	testing.expect_value(t, planets[0].palette[1], [3]int{4, 5, 6})
}

@(test)
test_a_planet_record_with_a_missing_field_is_refused_naming_it :: proc(t: ^testing.T) {
	record := string(TEST_PLANET_RECORD)
	for key in ([?]string{"id", "radius_metres", "radius_presets_metres", "surface_gravity_centimetres_per_second_squared", "bedrock_depth_metres", "sea_level_metres", "springs", "rain_fill_per_minute", "rotation_period_seconds", "relief_octaves", "palette"}) {
		line_start := strings.index(record, strings.concatenate({"\t", key, " ="}, context.temp_allocator))
		line_end := line_start + strings.index_byte(record[line_start:], '\n')
		without := strings.concatenate({record[:line_start], record[line_end + 1:]}, context.temp_allocator)
		expect_planets_problem(t, without, strings.concatenate({"planets[0] is missing ", key}, context.temp_allocator))
	}
	expect_planets_problem(t, "{}", "missing key planets")
}

@(test)
test_planet_records_refuse_unknown_keys_wrong_types_and_ranges :: proc(t: ^testing.T) {
	record := string(TEST_PLANET_RECORD)
	replace :: proc(record, old, new: string) -> string {
		replaced, _ := strings.replace(record, old, new, 1, context.temp_allocator)
		return replaced
	}
	expect_planets_problem(t, replace(record, "id = ", "colour = 1 id = "), "unknown key planets[0].colour")
	expect_planets_problem(t, replace(record, "radius_metres = 8000", `radius_metres = "far"`), "planets[0].radius_metres must be a whole number")
	expect_planets_problem(t, replace(record, "radius_metres = 8000", "radius_metres = 8000.5"), "planets[0].radius_metres must be a whole number")
	expect_planets_problem(t, replace(record, "radius_metres = 8000", "radius_metres = 9999999999"), "radius_metres 9999999999 is outside")
	expect_planets_problem(t, replace(record, "bedrock_depth_metres = 256", "bedrock_depth_metres = 8000"), "bedrock_depth_metres 8000 is outside")
	expect_planets_problem(t, replace(record, "rotation_period_seconds = 1200", "rotation_period_seconds = 59"), "rotation_period_seconds 59 is outside 60 to 86400")
	expect_planets_problem(t, replace(record, "rotation_period_seconds = 1200", "rotation_period_seconds = 86401"), "rotation_period_seconds 86401 is outside")
	expect_planets_problem(t, replace(record, "= 981", "= 0"), "surface_gravity_centimetres_per_second_squared 0 is outside 1 to 5000")
	expect_planets_problem(t, replace(record, "= 981", "= 5001"), "surface_gravity_centimetres_per_second_squared 5001 is outside")
	expect_planets_problem(t, replace(record, "bedrock_depth_metres = 256", "bedrock_depth_metres = 73"), "bedrock_depth_metres 73 is outside 74 to 7999")
	_, problem := parse_planets_file(transmute([]byte)replace(record, "bedrock_depth_metres = 256", "bedrock_depth_metres = 74"), PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect_value(t, problem, "")
	expect_planets_problem(t, replace(record, "[4, 5, 6]", "[4, 5, 256]"), "palette[1] has 256")
	expect_planets_problem(t, replace(record, "[[1, 2, 3], [4, 5, 6]]", "[]"), "palette has 0 colours")
	expect_planets_problem(t, replace(record, "[4, 5, 6]", "[4, 5]"), "planets[0].palette[1] must be an array of 3")
	expect_planets_problem(t, "planets = []", "planets is empty")
	expect_planets_problem(t, replace(record, "latitude_degrees = 88", "latitude_degrees = 91"), "springs[0].latitude_degrees 91 is outside -90 to 90")
	expect_planets_problem(t, replace(record, "longitude_degrees = -120", "longitude_degrees = -181"), "springs[0].longitude_degrees -181 is outside -180 to 180")
	expect_planets_problem(t, replace(record, "latitude_degrees = 88, ", ""), "planets[0].springs[0] is missing latitude_degrees")
	expect_planets_problem(t, replace(record, "rain_fill_per_minute = 2", "rain_fill_per_minute = 255"), "rain_fill_per_minute 255 is outside 0 to 254")
	expect_planets_problem(t, replace(record, "rain_fill_per_minute = 2", "rain_fill_per_minute = -1"), "rain_fill_per_minute -1 is outside")
	// The radius presets (0179): 1 to 8 valid radii with the default
	// among them.
	expect_planets_problem(t, replace(record, "[4000, 8000]", "[4000]"), "radius_metres 8000 is not among radius_presets_metres")
	expect_planets_problem(t, replace(record, "[4000, 8000]", "[]"), "radius_presets_metres has 0 entries, not 1 to 8")
	expect_planets_problem(t, replace(record, "[4000, 8000]", "[1, 2, 3, 4, 5, 6, 7, 8, 8000]"), "radius_presets_metres has 9 entries")
	expect_planets_problem(t, replace(record, "[4000, 8000]", "[8000, 200000]"), "radius_presets_metres[1]: radius_metres 200000 is outside 1 to 100000")
	expect_planets_problem(t, replace(record, "[4000, 8000]", "[200, 8000]"), "radius_presets_metres[0]: bedrock_depth_metres 256 is outside 74 to 199")
	// The relief's octaves.
	expect_planets_problem(t, replace(record, "amplitude_metres = 24", "amplitude_metres = 25"), "relief_octaves add up to 35 m, more than 34")
	expect_planets_problem(t, replace(record, "wavelength_metres = 32", "wavelength_metres = 0"), "relief_octaves[2].wavelength_metres 0 is outside 1 to 100000")
	expect_planets_problem(t, replace(record, "amplitude_metres = 2}", "amplitude_metres = -1}"), "relief_octaves[2].amplitude_metres -1 is outside 0 to 34")
	expect_planets_problem(t, replace(record, "wavelength_metres = 32, ", ""), "planets[0].relief_octaves[2] is missing wavelength_metres")
	twice := strings.concatenate({record[:len(record) - 1], ", ", record[len("planets = ["):]}, context.temp_allocator)
	expect_planets_problem(t, twice, `id "home" is used twice`)
}
