package game

import "core:slice"
import "core:strings"
import "core:testing"

// The shipped planets with home's radius and presets changed, as a later
// edit of data/planets.sjson would change them.
edited_test_planets :: proc(radius_metres: int) -> []Planet {
	planets := slice.clone(shipped_test_planets(), context.temp_allocator)
	presets := make([]int, 1, context.temp_allocator)
	presets[0] = radius_metres
	planets[0].radius_metres = radius_metres
	planets[0].radius_presets_metres = presets
	planets[0].sea_level_metres = 0
	return planets
}

expect_records_equal :: proc(t: ^testing.T, first, second: Planet_Generation_Record, location := #caller_location) {
	scalars :: proc(record: Planet_Generation_Record) -> [6]int {
		return {record.radius_metres, record.surface_gravity_centimetres_per_second_squared, record.bedrock_depth_metres, record.sea_level_metres, record.rotation_period_seconds, record.palette_length}
	}
	testing.expect_value(t, scalars(first), scalars(second), loc = location)
	testing.expect_value(t, first.relief_octaves, second.relief_octaves, loc = location)
	testing.expect_value(t, first.relief_shape, second.relief_shape, loc = location)
	testing.expect_value(t, first.crater, second.crater, loc = location)
	testing.expect(t, slice.equal(first.springs, second.springs), "the springs differ", loc = location)
}

// The defaults of a new world and of a world.sjson written before the
// planet settings: home at its default radius, peaceful, keep inventory.
@(test)
test_the_planet_settings_default :: proc(t: ^testing.T) {
	defaults := default_world_file_settings(test_game_config())
	testing.expect_value(t, defaults.planet_id, "home")
	testing.expect_value(t, defaults.mode, World_Mode.Peaceful)
	testing.expect(t, defaults.keep_inventory)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200},
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.settings.planet_id, "home")
	testing.expect_value(t, parsed.settings.mode, World_Mode.Peaceful)
	testing.expect(t, parsed.settings.keep_inventory)
	testing.expect(t, !planet_generation_is_recorded(parsed.planet_generation))
	resolved, planet, record := resolve_world_planet(parsed.settings, parsed.planet_generation, shipped_test_planets(), false)
	testing.expect_value(t, planet.id, "home")
	testing.expect_value(t, resolved.planet_radius_metres, 8000)
	testing.expect_value(t, record.radius_metres, 8000)
	// A stored mode and keep inventory come back as written.
	file.settings.planet_id, file.settings.mode, file.settings.keep_inventory = "home", .Creative, false
	parsed, problem = parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.settings.mode, World_Mode.Creative)
	testing.expect(t, !parsed.settings.keep_inventory)
}

// A planet the data does not have falls back to home, and a radius that
// is not a preset to the planet's default, each with a log line; a new
// world at each preset generates a planet of that radius.
@(test)
test_an_unknown_planet_or_radius_falls_back_to_the_defaults :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	settings := default_world_file_settings(test_game_config())
	settings.planet_id, settings.planet_radius_metres = "gone", 16000
	resolved, planet, record := resolve_world_planet(settings, {}, planets, false)
	testing.expect_value(t, planet.id, "home")
	testing.expect_value(t, resolved.planet_id, "home")
	testing.expect_value(t, record.radius_metres, 16000)
	// A loaded world keeps the id the data lost, so its save does too,
	// and takes the default planet's palette and rain.
	resolved, planet, record = resolve_world_planet(settings, {}, planets, true)
	testing.expect_value(t, resolved.planet_id, "gone")
	testing.expect_value(t, planet.id, "home")
	session: Session
	plan := resolve_session_planet(Session_Plan{loading = true, settings = settings, file = {settings = settings}}, planets, &session)
	testing.expect_value(t, plan.file.settings.planet_id, "gone")
	testing.expect_value(t, session.planet.id, "gone")
	testing.expect_value(t, len(session.planet.palette), len(planets[0].palette))
	testing.expect_value(t, session.planet.rain_fill_per_minute, planets[0].rain_fill_per_minute)
	destroy_recorded_planet(&session.planet)
	settings.planet_id, settings.planet_radius_metres = "home", 5000
	resolved, _, record = resolve_world_planet(settings, {}, planets, false)
	testing.expect_value(t, resolved.planet_radius_metres, 8000)
	testing.expect_value(t, record.radius_metres, 8000)
	for preset in ([?]int{4000, 8000, 16000}) {
		settings.planet_radius_metres = preset
		_, planet, record = resolve_world_planet(settings, {}, planets, false)
		recorded := make_recorded_planet(planet, record, context.temp_allocator)
		generation := make_planet_generation(TEST_PLANET_SEED, recorded, 1000)
		testing.expect_value(t, generation.radius, metres_to_position_units(i64(preset)))
		testing.expect_value(t, generation.bedrock_radius, metres_to_position_units(i64(preset - 256)))
	}
}

// The world file carries the generation record, and a load generates
// from it rather than from the data: the data's radius changed since, yet
// the loaded planet keeps its own. The palette follows the recorded
// length.
@(test)
test_the_world_file_records_the_planet_generation :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	settings := default_world_file_settings(test_game_config())
	settings.planet_radius_metres = 16000
	_, planet, record := resolve_world_planet(settings, {}, planets, false)
	recorded := make_recorded_planet(planet, record, context.temp_allocator)
	content := make_save_test_content()
	simulation := make_simulation(test_game_config(), player_start_on(SAVE_TEST_PLAYER_SURFACE), content, content.technologies, false, SAVE_TEST_LANDING_PAD)
	defer destroy_simulation(&simulation)
	simulation.world.planet = recorded
	file := make_world_file(&simulation, "Planet", 1)
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	expect_records_equal(t, parsed.planet_generation, record)
	testing.expect_value(t, parsed.planet_generation.relief_octaves, planet.relief_octaves)
	testing.expect_value(t, len(parsed.planet_generation.springs), 1)
	edited := edited_test_planets(4000)
	palette := make([][3]int, 2, context.temp_allocator)
	palette[0], palette[1] = {1, 2, 3}, {4, 5, 6}
	edited[0].palette = palette
	edited[0].relief_octaves[0].amplitude_metres = 1
	edited[0].relief_octaves[1].wavelength_metres = 100
	edited[0].surface_gravity_centimetres_per_second_squared = 500
	edited[0].bedrock_depth_metres = 300
	edited[0].rotation_period_seconds = 600
	edited[0].springs = nil
	_, loaded_planet, loaded_record := resolve_world_planet(parsed.settings, parsed.planet_generation, edited, true)
	loaded := make_recorded_planet(loaded_planet, loaded_record, context.temp_allocator)
	testing.expect_value(t, loaded.radius_metres, 16000)
	testing.expect_value(t, loaded.sea_level_metres, planet.sea_level_metres)
	testing.expect_value(t, loaded.surface_gravity_centimetres_per_second_squared, planet.surface_gravity_centimetres_per_second_squared)
	testing.expect_value(t, loaded.bedrock_depth_metres, planet.bedrock_depth_metres)
	testing.expect_value(t, loaded.rotation_period_seconds, planet.rotation_period_seconds)
	expect_records_equal(t, planet_generation_record(loaded), record)
	testing.expect_value(t, loaded.relief_octaves, planet.relief_octaves)
	testing.expect_value(t, len(loaded.springs), 1)
	testing.expect_value(t, len(loaded.palette), len(planet.palette))
	testing.expect_value(t, loaded.palette[2], [3]int{1, 2, 3})
	original := make_planet_generation(TEST_PLANET_SEED, recorded, 1000)
	testing.expect_value(t, make_planet_generation(TEST_PLANET_SEED, loaded, 1000), original)
	// A malformed record refuses the file instead of generating from it.
	file.planet_generation.bedrock_depth_metres = 20000
	_, problem = parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect(t, problem != "", "a bedrock below the centre is refused")
	file.planet_generation.bedrock_depth_metres = 256
	file.planet_generation.palette_length = 0
	_, problem = parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect(t, problem != "", "an empty palette is refused")
}

// A world.sjson written before the record loads with the data's values
// (and a log line).
@(test)
test_an_older_world_file_takes_the_planet_from_the_data :: proc(t: ^testing.T) {
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200},
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	edited := edited_test_planets(4000)
	resolved, planet, record := resolve_world_planet(parsed.settings, parsed.planet_generation, edited, true)
	testing.expect_value(t, planet.id, "home")
	testing.expect_value(t, resolved.planet_radius_metres, 4000)
	expect_records_equal(t, record, planet_generation_record(edited[0]))
}

// The session resolves the planet: a new world at a preset saves its
// record, and the save loaded against data whose radius changed keeps the
// radius it was made with.
@(test)
test_a_session_generates_from_the_recorded_planet :: proc(t: ^testing.T) {
	config := test_game_config()
	content := Game_Content {
		simulation_content = make_save_test_content(),
		planets = shipped_test_planets(),
	}
	settings := default_world_file_settings(config)
	settings.planet_radius_metres = 4000
	plan := Session_Plan {
		debug_terrain = true,
		seed = DEFAULT_WORLD_SEED,
		settings = settings,
	}
	session, problem := start_session(plan, config, content, make_test_generator(DEFAULT_WORLD_SEED))
	testing.expect_value(t, problem, "")
	if session == nil {
		return
	}
	testing.expect_value(t, session.planet.radius_metres, 4000)
	testing.expect_value(t, session.simulation.world.planet.radius_metres, 4000)
	testing.expect_value(t, session.simulation.world.settings.planet_radius_metres, 4000)
	files := encode_save_files(&session.simulation, content.simulation_content, "planet", 0)
	end_session(session)
	file: World_File
	file, problem = parse_world_file(files.world, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, file.planet_generation.radius_metres, 4000)
	content.planets = edited_test_planets(16000)
	loaded_plan := Session_Plan {
		loading = true,
		debug_terrain = true,
		seed = file.seed,
		settings = file.settings,
		file = file,
		files = &files,
	}
	session, problem = start_session(loaded_plan, config, content, make_test_generator(DEFAULT_WORLD_SEED))
	testing.expect_value(t, problem, "")
	if session == nil {
		return
	}
	defer end_session(session)
	testing.expect_value(t, session.planet.radius_metres, 4000)
	testing.expect_value(t, session.simulation.world.settings.planet_radius_metres, 4000)
	testing.expect_value(t, session.simulation.world.settings.planet_id, "home")
}

// The mode is written by name: a number (which the unmarshal would assign
// unchecked) is refused, an unknown name reads as peaceful with a log
// line.
@(test)
test_the_world_file_mode_is_a_known_name :: proc(t: ^testing.T) {
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = "home", mode = .Creative},
	}
	text := string(encode_world_file(file, context.temp_allocator))
	testing.expect(t, strings.contains(text, `"Creative"`), text)
	numbered, _ := strings.replace(text, `"Creative"`, "7", 1, context.temp_allocator)
	_, problem := parse_world_file(transmute([]byte)numbered, context.temp_allocator)
	testing.expect(t, strings.contains(problem, "mode must be one of"), problem)
	in_range, _ := strings.replace(text, `"Creative"`, "1", 1, context.temp_allocator)
	_, problem = parse_world_file(transmute([]byte)in_range, context.temp_allocator)
	testing.expect(t, strings.contains(problem, "mode must be one of"), problem)
	misspelt, _ := strings.replace(text, `"Creative"`, `"Survivl"`, 1, context.temp_allocator)
	parsed: World_File
	parsed, problem = parse_world_file(transmute([]byte)misspelt, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.settings.mode, World_Mode.Peaceful)
}

// A world file written before the relief's shape (0189) loads with every
// term off, so the unedited ground round its saved chunks generates as it
// did; a file written now keeps the shape it was made with.
@(test)
test_a_world_file_before_the_relief_shape_keeps_the_plain_relief :: proc(t: ^testing.T) {
	planet := default_planet(shipped_test_planets())
	record := planet_generation_record(planet)
	testing.expect(t, record.relief_shape != {}, "the shipped home shapes its relief")
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200},
		planet_generation = record,
	}
	text := string(encode_world_file(file, context.temp_allocator))
	parsed, problem := parse_world_file(transmute([]byte)text, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.relief_shape, record.relief_shape)
	start := strings.index(text, "relief_shape")
	end := start + strings.index_byte(text[start:], '}') + 1
	older := strings.concatenate({text[:start], text[end:]}, context.temp_allocator)
	parsed, problem = parse_world_file(transmute([]byte)older, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.relief_shape, Relief_Shape{})
	testing.expect_value(t, parsed.planet_generation.relief_octaves, record.relief_octaves)
	loaded := make_recorded_planet(planet, parsed.planet_generation, context.temp_allocator)
	testing.expect_value(t, make_planet_generation(TEST_PLANET_SEED, loaded, 1000).relief_shape, Relief_Shape{})
}

// Work item 0199: a world file recorded without the crater resolves to
// the data's crater; a recorded crater survives make_recorded_planet when
// the data's differs, so a data edit never moves a saved pod's crater.
@(test)
test_a_world_file_without_a_crater_takes_the_datas :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	planet := default_planet(planets)
	testing.expect(t, planet.crater != {}, "the shipped home has a crater")
	record := planet_generation_record(planet)
	record.crater, record.crater_recorded = {}, false
	settings := World_File_Settings{planet_id = planet.id}
	_, _, resolved := resolve_world_planet(settings, record, planets, true)
	testing.expect(t, resolved.crater_recorded)
	testing.expect_value(t, resolved.crater, planet.crater)
	recorded := planet_generation_record(planet)
	recorded.crater = {radius_metres = 10, depth_metres = 2, floor_radius_metres = 3, rim_metres = 0}
	testing.expect_value(t, planet_generation_record_problem(recorded), "")
	_, _, kept := resolve_world_planet(settings, recorded, planets, true)
	testing.expect_value(t, make_recorded_planet(planet, kept, context.temp_allocator).crater, recorded.crater)
	recorded.crater.depth_metres = MAXIMUM_CRATER_DEPTH_METRES + 1
	testing.expect(t, strings.contains(planet_generation_record_problem(recorded), "crater.depth_metres"), "a recorded crater out of bounds is refused")
}

// Work item 0197: a world file recorded without the trees resolves to
// the data's placement; a recorded placement survives
// make_recorded_planet when the data's differs; a recorded species count
// repeats or cuts the data's species, and a count of 0 grows no trees.
@(test)
test_a_world_file_without_trees_takes_the_datas :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	planet := default_planet(planets)
	record := planet_generation_record(planet)
	testing.expect(t, record.trees_recorded)
	record.trees, record.trees_recorded = {}, false
	settings := World_File_Settings{planet_id = planet.id}
	_, _, resolved := resolve_world_planet(settings, record, planets, true)
	testing.expect(t, resolved.trees_recorded)
	testing.expect_value(t, resolved.trees, planet_tree_placement(planet.trees))
	recorded := planet_generation_record(planet)
	recorded.trees.density_percent = 40
	recorded.trees.species_count = 3
	testing.expect_value(t, planet_generation_record_problem(recorded), "")
	_, _, kept := resolve_world_planet(settings, recorded, planets, true)
	loaded := make_recorded_planet(planet, kept)
	defer destroy_recorded_planet(&loaded)
	testing.expect_value(t, loaded.trees.density_percent, 40)
	testing.expect_value(t, len(loaded.trees.species), 3)
	for species in loaded.trees.species {
		testing.expect_value(t, species.id, planet.trees.species[0].id)
		testing.expect_value(t, species.machine, planet.trees.species[0].machine)
	}
	none := planet_generation_record(planet)
	none.trees.species_count = 0
	bare := make_recorded_planet(planet, none, context.temp_allocator)
	testing.expect_value(t, len(bare.trees.species), 0)
	testing.expect_value(t, make_planet_generation(TEST_PLANET_SEED, bare, 1000).trees, Planet_Tree_Term{})
	none.trees.species_count = MAXIMUM_TREE_SPECIES + 1
	testing.expect(t, strings.contains(planet_generation_record_problem(none), "trees.species_count"), "a recorded species count out of bounds is refused")
}

// Work item 0271: a new world records crater_at_impact; a world file
// without the key, and one written before the record, bake the crater;
// make_recorded_planet carries the flag to the planet.
@(test)
test_a_world_file_without_the_impact_key_bakes_its_crater :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	planet := default_planet(planets)
	settings := World_File_Settings{planet_id = planet.id}
	_, _, fresh := resolve_world_planet(settings, {}, planets, false)
	testing.expect(t, fresh.crater_at_impact, "a new world's hit digs its crater")
	testing.expect(t, make_recorded_planet(planet, fresh, context.temp_allocator).crater_at_impact)
	_, _, before_record := resolve_world_planet(settings, {}, planets, true)
	testing.expect(t, !before_record.crater_at_impact, "a file from before the record bakes its crater")
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = planet.id},
		planet_generation = fresh,
	}
	text := string(encode_world_file(file, context.temp_allocator))
	testing.expect(t, strings.contains(text, "crater_at_impact"), "the world file writes the key")
	lines := strings.split_lines(text, context.temp_allocator)
	kept_lines := make([dynamic]string, context.temp_allocator)
	for line in lines {
		if !strings.contains(line, "crater_at_impact") {
			append(&kept_lines, line)
		}
	}
	without := strings.join(kept_lines[:], "\n", context.temp_allocator)
	parsed, problem := parse_world_file(transmute([]byte)without, context.temp_allocator)
	testing.expect_value(t, problem, "")
	_, _, loaded := resolve_world_planet(parsed.settings, parsed.planet_generation, planets, true)
	testing.expect(t, !loaded.crater_at_impact, "a recorded world without the key bakes its crater")
	testing.expect(t, !make_recorded_planet(planet, loaded, context.temp_allocator).crater_at_impact)
	kept, _ := parse_world_file(transmute([]byte)text, context.temp_allocator)
	_, _, reloaded := resolve_world_planet(kept.settings, kept.planet_generation, planets, true)
	testing.expect(t, reloaded.crater_at_impact, "a loaded new world keeps its flag")
}
