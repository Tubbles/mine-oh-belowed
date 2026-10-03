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
	home = {latitude_degrees = 86, longitude_degrees = -115}
	crater = {radius_metres = 12, depth_metres = 3, floor_radius_metres = 4, rim_metres = 1}
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
	testing.expect_value(t, home.relief_octaves[0], Relief_Octave{512, 10})
	testing.expect(t, home.relief_shape.ledge_amplitude_millimetres > 0 && home.relief_shape.terrace_rise_millimetres > 0 && home.relief_shape.basin_depth_metres > 0, "the shipped home shapes its relief")
}

// The relief's shape (0189) is optional, off at zero without it; given,
// every key of it is required and bounded while its term is on, and it
// counts towards the relief's bound.
@(test)
test_a_planet_record_takes_an_optional_relief_shape :: proc(t: ^testing.T) {
	record := string(TEST_PLANET_RECORD)
	planets, problem := parse_planets_file(transmute([]byte)record, PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, planets[0].relief_shape, Relief_Shape{})
	shape_line := "\trelief_shape = {ledge_wavelength_metres = 32, ledge_amplitude_millimetres = 700, ledge_sharpness = 64, terrace_rise_millimetres = 1200, terrace_riser_permille = 10, basin_depth_metres = 2, basin_threshold_percent = -30}\n"
	shaped, _ := strings.replace(record, "\tpalette", strings.concatenate({shape_line, "\tpalette"}, context.temp_allocator), 1, context.temp_allocator)
	shaped, _ = strings.replace(shaped, "amplitude_metres = 24", "amplitude_metres = 21", 1, context.temp_allocator)
	planets, problem = parse_planets_file(transmute([]byte)shaped, PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, planets[0].relief_shape, Relief_Shape{32, 700, 64, 1200, 10, 2, -30})
	replace :: proc(record, old, new: string) -> string {
		replaced, _ := strings.replace(record, old, new, 1, context.temp_allocator)
		return replaced
	}
	expect_planets_problem(t, replace(shaped, "ledge_sharpness = 64, ", ""), "planets[0].relief_shape is missing ledge_sharpness")
	expect_planets_problem(t, replace(shaped, "ledge_sharpness = 64", "ledge_sharpness = 0"), "relief_shape.ledge_sharpness 0 is outside 1 to 256")
	expect_planets_problem(t, replace(shaped, "ledge_wavelength_metres = 32", "ledge_wavelength_metres = 0"), "relief_shape.ledge_wavelength_metres 0 is outside 1 to 100000")
	expect_planets_problem(t, replace(shaped, "terrace_riser_permille = 10", "terrace_riser_permille = 1001"), "relief_shape.terrace_riser_permille 1001 is outside 1 to 1000")
	expect_planets_problem(t, replace(shaped, "terrace_rise_millimetres = 1200", "terrace_rise_millimetres = -1"), "relief_shape.terrace_rise_millimetres -1 is outside 0 to 34000")
	expect_planets_problem(t, replace(shaped, "basin_threshold_percent = -30", "basin_threshold_percent = -100"), "relief_shape.basin_threshold_percent -100 is outside -99 to 100")
	expect_planets_problem(t, replace(shaped, "basin_depth_metres = 2", "basin_depth_metres = 3"), "relief_octaves with the ledges and the basins add up to 34700 mm, more than 34000")
	expect_planets_problem(t, replace(shaped, "basin_depth_metres = 2", "basin_depth_metres = 2, height = 1"), "unknown key planets[0].relief_shape.height")
	// A term that is off leaves its other keys unchecked.
	off := replace(replace(shaped, "ledge_amplitude_millimetres = 700", "ledge_amplitude_millimetres = 0"), "ledge_sharpness = 64", "ledge_sharpness = 0")
	_, problem = parse_planets_file(transmute([]byte)off, PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect_value(t, problem, "")
}

@(test)
test_a_planet_record_parses :: proc(t: ^testing.T) {
	planets, problem := parse_planets_file(transmute([]byte)string(TEST_PLANET_RECORD), PLANETS_FILE_NAME, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(planets), 1)
	testing.expect_value(t, planets[0].surface_gravity_centimetres_per_second_squared, 981)
	testing.expect_value(t, planets[0].rotation_period_seconds, 1200)
	testing.expect_value(t, planets[0].home, Planet_Home{86, -115})
	testing.expect_value(t, planets[0].palette[1], [3]int{4, 5, 6})
}

@(test)
test_a_planet_record_with_a_missing_field_is_refused_naming_it :: proc(t: ^testing.T) {
	record := string(TEST_PLANET_RECORD)
	for key in ([?]string{"id", "radius_metres", "radius_presets_metres", "surface_gravity_centimetres_per_second_squared", "bedrock_depth_metres", "sea_level_metres", "springs", "home", "crater", "rain_fill_per_minute", "rotation_period_seconds", "relief_octaves", "palette"}) {
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
	expect_planets_problem(t, replace(record, "latitude_degrees = 86", "latitude_degrees = -91"), "home.latitude_degrees -91 is outside -90 to 90")
	expect_planets_problem(t, replace(record, "longitude_degrees = -115", "longitude_degrees = 181"), "home.longitude_degrees 181 is outside -180 to 180")
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
	expect_planets_problem(t, replace(record, "amplitude_metres = 24", "amplitude_metres = 25"), "relief_octaves with the ledges and the basins add up to 35000 mm, more than 34000")
	expect_planets_problem(t, replace(record, "wavelength_metres = 32", "wavelength_metres = 0"), "relief_octaves[2].wavelength_metres 0 is outside 1 to 100000")
	expect_planets_problem(t, replace(record, "amplitude_metres = 2}", "amplitude_metres = -1}"), "relief_octaves[2].amplitude_metres -1 is outside 0 to 34")
	expect_planets_problem(t, replace(record, "wavelength_metres = 32, ", ""), "planets[0].relief_octaves[2] is missing wavelength_metres")
	twice := strings.concatenate({record[:len(record) - 1], ", ", record[len("planets = ["):]}, context.temp_allocator)
	expect_planets_problem(t, twice, `id "home" is used twice`)
}

// Work item 0199: each crater key just past each bound, the reach and the
// slope rules are refused with their message; the zero crater and the
// shipped one pass, and a crater missing a key is refused naming it.
@(test)
test_a_crater_record_out_of_bounds_is_refused :: proc(t: ^testing.T) {
	shipped := default_planet(shipped_test_planets()).crater
	testing.expect_value(t, shipped, Planet_Crater{radius_metres = 12, depth_metres = 3, floor_radius_metres = 4, rim_metres = 1})
	testing.expect_value(t, crater_problem(shipped), "")
	testing.expect_value(t, crater_problem({}), "")
	cases := [?]struct {
		crater:   Planet_Crater,
		expected: string,
	} {
		{{3, 1, 2, 0}, "crater.radius_metres 3 is outside 4 to 24"},
		{{25, 1, 4, 0}, "crater.radius_metres 25 is outside 4 to 24"},
		{{12, 0, 4, 1}, "crater.depth_metres 0 is outside 1 to 8"},
		{{24, 9, 4, 0}, "crater.depth_metres 9 is outside 1 to 8"},
		{{12, 3, 1, 1}, "crater.floor_radius_metres 1 is outside 2 to 10"},
		{{12, 3, 11, 1}, "crater.floor_radius_metres 11 is outside 2 to 10"},
		{{12, 3, 4, -1}, "crater.rim_metres -1 is outside 0 to 4"},
		{{12, 3, 4, 5}, "crater.rim_metres 5 is outside 0 to 4"},
		{{18, 1, 4, 1}, ""},
		{{19, 1, 4, 2}, "crater reaches 31 m, more than 24"},
		{{12, 4, 4, 2}, "crater bowl of 6 m over 8 m is steeper than 45 degrees"},
		{{12, 4, 4, 1}, ""},
	}
	for entry in cases {
		testing.expect_value(t, crater_problem(entry.crater), entry.expected)
	}
	record := string(TEST_PLANET_RECORD)
	missing, _ := strings.replace(record, "depth_metres = 3, ", "", 1, context.temp_allocator)
	expect_planets_problem(t, missing, "planets[0].crater is missing depth_metres")
	steep, _ := strings.replace(record, "depth_metres = 3", "depth_metres = 6", 1, context.temp_allocator)
	expect_planets_problem(t, steep, "crater bowl of 7 m over 8 m is steeper than 45 degrees")
}
