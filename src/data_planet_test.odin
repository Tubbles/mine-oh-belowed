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
	trees = {grove_spacing_metres = 40, grove_share_percent = 50, grove_radius_metres = 14, tree_spacing_metres = 4, density_percent = 80, clearing_metres = 24, maximum_slope_percent = 70, species = [{id = "pine", machine = "pine_tree", tint = [236, 232, 214], item = "log", count = 4, hand_felling_scale_percent = 100, hand_felling_milliseconds = 10000, axe_felling_milliseconds = [6000, 4000, 2500], trunk_radius_millimetres = 180, trunk_height_millimetres = 2500}]}
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
	for key in ([?]string{"id", "radius_metres", "radius_presets_metres", "surface_gravity_centimetres_per_second_squared", "bedrock_depth_metres", "sea_level_metres", "springs", "home", "crater", "trees", "rain_fill_per_minute", "rotation_period_seconds", "relief_octaves", "palette"}) {
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
	// The world records it (0271), the data cannot set it.
	expect_planets_problem(t, replace(record, "id = ", "crater_at_impact = true id = "), "unknown key planets[0].crater_at_impact")
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

// Work item 0197: each trees key one past each bound is refused with its
// message; no trees (a share of 0, no species) passes; a clearing inside
// the crater's reach is refused; the shipped record passes.
@(test)
test_a_tree_record_out_of_bounds_is_refused :: proc(t: ^testing.T) {
	planet := default_planet(shipped_test_planets())
	shipped := planet.trees
	testing.expect_value(t, trees_problem(shipped, planet.crater), "")
	testing.expect_value(t, trees_problem(Planet_Trees{}, planet.crater), "")
	species := shipped.species[0]
	cases := [?]struct {
		change:   proc(trees: ^Planet_Trees),
		expected: string,
	} {
		{proc(trees: ^Planet_Trees) {trees.grove_share_percent = 101}, "trees.grove_share_percent 101 is outside 0 to 100"},
		{proc(trees: ^Planet_Trees) {trees.grove_share_percent = -1}, "trees.grove_share_percent -1 is outside 0 to 100"},
		{proc(trees: ^Planet_Trees) {trees.tree_spacing_metres = 1}, "trees.tree_spacing_metres 1 is outside 2 to 16"},
		{proc(trees: ^Planet_Trees) {trees.tree_spacing_metres = 17}, "trees.tree_spacing_metres 17 is outside 2 to 16"},
		{proc(trees: ^Planet_Trees) {trees.grove_spacing_metres = 7}, "trees.grove_spacing_metres 7 is outside 8 to 256"},
		{proc(trees: ^Planet_Trees) {trees.grove_spacing_metres = 257}, "trees.grove_spacing_metres 257 is outside 8 to 256"},
		{proc(trees: ^Planet_Trees) {trees.grove_radius_metres = 3}, "trees.grove_radius_metres 3 is outside 4 to 40"},
		{proc(trees: ^Planet_Trees) {trees.grove_radius_metres = 41}, "trees.grove_radius_metres 41 is outside 4 to 40"},
		{proc(trees: ^Planet_Trees) {trees.density_percent = 0}, "trees.density_percent 0 is outside 1 to 100"},
		{proc(trees: ^Planet_Trees) {trees.density_percent = 101}, "trees.density_percent 101 is outside 1 to 100"},
		{proc(trees: ^Planet_Trees) {trees.clearing_metres = -1}, "trees.clearing_metres -1 is outside 0 to 64"},
		{proc(trees: ^Planet_Trees) {trees.clearing_metres = 65}, "trees.clearing_metres 65 is outside 0 to 64"},
		{proc(trees: ^Planet_Trees) {trees.clearing_metres = 17}, "trees.clearing_metres 17 is inside the crater's reach of 18 m"},
		{proc(trees: ^Planet_Trees) {trees.maximum_slope_percent = 0}, "trees.maximum_slope_percent 0 is outside 1 to 173"},
		{proc(trees: ^Planet_Trees) {trees.maximum_slope_percent = 174}, "trees.maximum_slope_percent 174 is outside 1 to 173"},
		{proc(trees: ^Planet_Trees) {trees.species = nil}, "trees.species has 0 entries, not 1 to 8"},
		{proc(trees: ^Planet_Trees) {trees.species = make([]Planet_Tree_Species, 9, context.temp_allocator)}, "trees.species has 9 entries, not 1 to 8"},
	}
	for entry in cases {
		trees := shipped
		entry.change(&trees)
		testing.expect_value(t, trees_problem(trees, planet.crater), entry.expected)
	}
	inside := shipped
	inside.clearing_metres = 0
	testing.expect_value(t, trees_problem(inside, {}), "")
	species_cases := [?]struct {
		change:   proc(species: ^Planet_Tree_Species),
		expected: string,
	} {
		{proc(species: ^Planet_Tree_Species) {species.id = "Pine"}, `trees.species[0].id "Pine" is not 1 to 32 bytes of a to z, 0 to 9 and _`},
		{proc(species: ^Planet_Tree_Species) {species.id = ""}, `trees.species[0].id "" is not 1 to 32 bytes of a to z, 0 to 9 and _`},
		{proc(species: ^Planet_Tree_Species) {species.machine = ""}, "trees.species[0].machine is empty"},
		{proc(species: ^Planet_Tree_Species) {species.item = ""}, "trees.species[0].item is empty"},
		{proc(species: ^Planet_Tree_Species) {species.count = 0}, "trees.species[0].count 0 is outside 1 to 16"},
		{proc(species: ^Planet_Tree_Species) {species.count = 17}, "trees.species[0].count 17 is outside 1 to 16"},
		{proc(species: ^Planet_Tree_Species) {species.hand_felling_milliseconds = 99}, "trees.species[0].hand_felling_milliseconds 99 is outside 100 to 60000"},
		{proc(species: ^Planet_Tree_Species) {species.hand_felling_milliseconds = 60_001}, "trees.species[0].hand_felling_milliseconds 60001 is outside 100 to 60000"},
		{proc(species: ^Planet_Tree_Species) {species.axe_felling_milliseconds[1] = 99}, "trees.species[0].axe_felling_milliseconds[1] 99 is outside 100 to 60000"},
		{proc(species: ^Planet_Tree_Species) {species.axe_felling_milliseconds[1] = 60_001}, "trees.species[0].axe_felling_milliseconds[1] 60001 is outside 100 to 60000"},
		{proc(species: ^Planet_Tree_Species) {species.hand_felling_scale_percent = -1}, "trees.species[0].hand_felling_scale_percent -1 is outside 0 to 115"},
		{proc(species: ^Planet_Tree_Species) {species.hand_felling_scale_percent = 116}, "trees.species[0].hand_felling_scale_percent 116 is outside 0 to 115"},
		{proc(species: ^Planet_Tree_Species) {species.trunk_radius_millimetres = 49}, "trees.species[0].trunk_radius_millimetres 49 is outside 50 to 1000"},
		{proc(species: ^Planet_Tree_Species) {species.trunk_radius_millimetres = 1001}, "trees.species[0].trunk_radius_millimetres 1001 is outside 50 to 1000"},
		{proc(species: ^Planet_Tree_Species) {species.trunk_height_millimetres = 499}, "trees.species[0].trunk_height_millimetres 499 is outside 500 to 20000"},
		{proc(species: ^Planet_Tree_Species) {species.trunk_height_millimetres = 20_001}, "trees.species[0].trunk_height_millimetres 20001 is outside 500 to 20000"},
		{proc(species: ^Planet_Tree_Species) {species.tint = {0, 256, 0}}, "trees.species[0].tint has 256, outside 0 to 255"},
		{proc(species: ^Planet_Tree_Species) {species.tint = {-1, 0, 0}}, "trees.species[0].tint has -1, outside 0 to 255"},
	}
	for entry in species_cases {
		changed := species
		entry.change(&changed)
		trees := shipped
		trees.species = []Planet_Tree_Species{changed}
		testing.expect_value(t, trees_problem(trees, planet.crater), entry.expected)
	}
	twice := shipped
	twice.species = []Planet_Tree_Species{species, species}
	testing.expect_value(t, tree_species_ids_problem(twice), `trees.species[1].id "pine" is used twice`)
	doubled, _ := strings.replace(string(TEST_PLANET_RECORD), "species = [{id = \"pine\"", "species = [{id = \"pine\", machine = \"pine_tree\", tint = [1, 2, 3], item = \"log\", count = 1, hand_felling_scale_percent = 100, hand_felling_milliseconds = 1000, axe_felling_milliseconds = [1000, 1000, 1000], trunk_radius_millimetres = 100, trunk_height_millimetres = 1000}, {id = \"pine\"", 1, context.temp_allocator)
	expect_planets_problem(t, doubled, `trees.species[1].id "pine" is used twice`)
	record := string(TEST_PLANET_RECORD)
	missing, _ := strings.replace(record, "density_percent = 80, ", "", 1, context.temp_allocator)
	expect_planets_problem(t, missing, "planets[0].trees is missing density_percent")
	species_missing, _ := strings.replace(record, "count = 4, ", "", 1, context.temp_allocator)
	expect_planets_problem(t, species_missing, "planets[0].trees.species[0] is missing count")
}

// Work item 0197: each species names a machine of kind tree and an item.
@(test)
test_a_tree_species_must_name_a_tree_model_and_an_item :: proc(t: ^testing.T) {
	items := make_test_items()
	machines := make_test_machines()
	planets := shipped_test_planets()
	testing.expect_value(t, planet_tree_species_problem(planets, items, machines), "")
	changed := slice.clone(planets, context.temp_allocator)
	species := slice.clone(changed[0].trees.species, context.temp_allocator)
	changed[0].trees.species = species
	species[0].machine = "no_such_machine"
	testing.expect_value(t, planet_tree_species_problem(changed, items, machines), `planets[0].trees.species[0].machine "no_such_machine" is not a machine of kind tree`)
	species[0].machine = "stone_furnace"
	testing.expect_value(t, planet_tree_species_problem(changed, items, machines), `planets[0].trees.species[0].machine "stone_furnace" is not a machine of kind tree`)
	species[0].machine = "pine_tree"
	species[0].item = "no_such_item"
	testing.expect_value(t, planet_tree_species_problem(changed, items, machines), `planets[0].trees.species[0].item "no_such_item" is not an item`)
}
