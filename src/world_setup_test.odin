package game

import "core:os"
import "core:strings"
import "core:testing"

non_default_world_setup :: proc() -> World_Setup {
	setup := make_world_setup(World_File_Settings{day_length_seconds = 1200}, "Settings", 7)
	setup.veins_infinite = true
	setup.vein_richness_choice = 3
	setup.research_cost_choice = 0
	setup.byproducts_lenient = true
	setup.all_recipes_unlocked = true
	setup.day_length_choice = 0
	return setup
}

@(test)
test_world_setup_defaults_follow_the_config :: proc(t: ^testing.T) {
	config := Game_Config{name = "test", tick_rate = TEST_TICK_RATE, day_length_seconds = 600, veins_infinite = true}
	setup := make_world_setup(default_world_file_settings(config), "Name", 1)
	settings := world_file_settings_from_setup(setup)
	testing.expect_value(t, settings.day_length_seconds, 600)
	testing.expect(t, settings.veins_infinite)
	testing.expect_value(t, settings.vein_richness_percent, 100)
	testing.expect_value(t, settings.research_cost_percent, 100)
	testing.expect_value(t, percent_multiplier_text(50), "0.5x")
	testing.expect_value(t, percent_multiplier_text(400), "4x")
}

// The setup's settings go into world.sjson through the simulation and come
// back out of it unchanged.
@(test)
test_world_settings_round_trip_through_world_file :: proc(t: ^testing.T) {
	setup := non_default_world_setup()
	settings := world_file_settings_from_setup(setup)
	testing.expect_value(t, settings.vein_richness_percent, 400)
	testing.expect_value(t, settings.research_cost_percent, 50)
	testing.expect_value(t, settings.day_length_seconds, 300)

	content := make_save_test_content()
	config := test_game_config()
	config.day_length_seconds = settings.day_length_seconds
	simulation := make_simulation(config, player_start_on(SAVE_TEST_PLAYER_SURFACE), content, content.technologies, settings.all_recipes_unlocked, SAVE_TEST_LANDING_PAD)
	defer destroy_simulation(&simulation)
	simulation.world.settings = world_settings_from_file(99, settings)
	file := make_world_file(&simulation, "Settings", 1)
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.seed, 99)
	testing.expect_value(t, parsed.settings, settings)
	testing.expect_value(t, world_settings_from_file(parsed.seed, parsed.settings), simulation.world.settings)
}

// A world.sjson written before the percent settings existed loads at 100
// percent; a percent out of range is refused.
@(test)
test_world_file_percent_settings_default_and_validate :: proc(t: ^testing.T) {
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		name = "old",
		settings = {day_length_seconds = 1200},
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.settings.vein_richness_percent, 100)
	testing.expect_value(t, parsed.settings.research_cost_percent, 100)
	file.settings.research_cost_percent = MAXIMUM_SETTING_PERCENT + 1
	_, problem = parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect(t, problem != "")
}

@(test)
test_research_cost_scales_pack_counts_rounding_up :: proc(t: ^testing.T) {
	testing.expect_value(t, scaled_pack_count(10, 50), 5)
	testing.expect_value(t, scaled_pack_count(3, 50), 2)
	testing.expect_value(t, scaled_pack_count(1, 50), 1)
	testing.expect_value(t, scaled_pack_count(10, 400), 40)
	content := make_test_content()
	scaled := scaled_technology_registry(content.technologies, 200, context.temp_allocator)
	testing.expect_value(t, len(scaled.technologies), len(content.technologies.technologies))
	for technology, index in scaled.technologies {
		testing.expect_value(t, technology.pack_count, content.technologies.technologies[index].pack_count * 2)
	}
}

// Richness multiplies the units of every vein and changes nothing else.
@(test)
test_vein_richness_multiplies_vein_units :: proc(t: ^testing.T) {
	base := make_test_generator(DEFAULT_WORLD_SEED)
	rich := session_generator(base, DEFAULT_WORLD_SEED, 200)
	region := Region_Coordinate{1, 0}
	normal_veins := region_veins(&base, region, context.temp_allocator)
	rich_veins := region_veins(&rich, region, context.temp_allocator)
	testing.expect(t, len(normal_veins) > 0, "the test region has veins")
	testing.expect_value(t, len(rich_veins), len(normal_veins))
	for vein, index in normal_veins {
		testing.expect_value(t, rich_veins[index].centre, vein.centre)
		for amount, output in vein.remaining {
			testing.expect(t, abs(rich_veins[index].remaining[output] - 2 * amount) <= 1)
		}
	}
}

@(test)
test_default_new_world_name_is_unique :: proc(t: ^testing.T) {
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	testing.expect_value(t, default_new_world_name("New world", directory, true), "New world")
	os.make_directory(join_save_path(directory, "New world"))
	testing.expect_value(t, default_new_world_name("New world", directory, true), "New world 2")
	os.make_directory(join_save_path(directory, "New world 2.previous"))
	testing.expect_value(t, default_new_world_name("New world", directory, true), "New world 3")
	testing.expect_value(t, default_new_world_name("New world", "", false), "New world")
}

write_test_world_file :: proc(saves_directory, directory_name, name: string, last_played: i64, format_version := SAVE_FORMAT_VERSION) {
	path := join_save_path(saves_directory, directory_name)
	os.make_directory_all(path)
	file := World_File {
		format_version = format_version,
		name = name,
		seed = u64(last_played),
		settings = {day_length_seconds = 1200},
		tick = 60 * 60 * 90,
		last_played_unix_seconds = last_played,
	}
	error := os.write_entire_file(join_save_path(path, WORLD_FILE_NAME), encode_world_file(file, context.temp_allocator))
	assert(error == nil)
}

@(test)
test_save_listing_is_newest_first :: proc(t: ^testing.T) {
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	write_test_world_file(directory, "middle", "Middle", 2000)
	write_test_world_file(directory, "oldest", "Oldest", 1000)
	write_test_world_file(directory, "newest", "Newest", 3000)
	// Only the previous directory of a save survived a crash mid swap.
	write_test_world_file(directory, "crashed.previous", "Crashed", 1500)
	// A staging directory is no save.
	write_test_world_file(directory, "half.saving", "Half", 9000)
	os.make_directory(join_save_path(directory, "not a save"))
	saves: [dynamic]Save_Summary
	defer delete(saves)
	defer destroy_save_summaries(&saves)
	list_saves(&saves, directory, {})
	names := [?]string{"Newest", "Middle", "Crashed", "Oldest"}
	testing.expect_value(t, len(saves), len(names))
	for name, index in names {
		if index < len(saves) {
			testing.expect_value(t, saves[index].name, name)
		}
	}
	if len(saves) == len(names) {
		testing.expect_value(t, saves[2].directory_name, "crashed")
		testing.expect_value(t, play_time_text(saves[0].tick, 60), "1:30")
	}
	testing.expect(t, delete_save(directory, "newest") == nil)
	list_saves(&saves, directory, {})
	testing.expect_value(t, len(saves), len(names) - 1)
}

write_test_entities_header :: proc(saves_directory, directory_name: string, header: Save_Header) {
	bytes := make([dynamic]byte, context.temp_allocator)
	append_save_header(&bytes, ENTITIES_FILE_MAGIC, header)
	append_content_tables(&bytes, {})
	error := os.write_entire_file(join_save_path(saves_directory, directory_name, ENTITIES_FILE_NAME), bytes[:])
	assert(error == nil)
}

// 0044: a save of another format version, or without an entities file,
// is listed but marked, and can be deleted. 0047: the version is all the
// header holds; a version 1 save is such a save.
@(test)
test_save_listing_marks_saves_this_build_cannot_load :: proc(t: ^testing.T) {
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	expected := Save_Header {
		version = SAVE_FORMAT_VERSION,
	}
	write_test_world_file(directory, "current", "Current", 3000)
	write_test_entities_header(directory, "current", expected)
	write_test_world_file(directory, "older", "Older", 2000, 1)
	write_test_entities_header(directory, "older", Save_Header{version = 1})
	write_test_world_file(directory, "stale", "Stale", 1500)
	write_test_entities_header(directory, "stale", Save_Header{version = 1})
	write_test_world_file(directory, "empty", "Empty", 1000)
	saves: [dynamic]Save_Summary
	defer delete(saves)
	defer destroy_save_summaries(&saves)
	list_saves(&saves, directory, expected)
	testing.expect_value(t, len(saves), 4)
	if len(saves) != 4 {
		return
	}
	testing.expect(t, saves[0].loadable)
	testing.expect_value(t, saves[0].load_problem, "")
	for index in 1 ..< 3 {
		testing.expect(t, !saves[index].loadable)
		testing.expect(t, strings.contains(saves[index].load_problem, "format version 1"), saves[index].load_problem)
	}
	testing.expect(t, !saves[3].loadable)
	testing.expect_value(t, save_row_cells(saves[1], nil, 60).marker, text("load_incompatible"))
	testing.expect_value(t, save_row_cells(saves[0], nil, 60).marker, "")
	testing.expect(t, delete_save(directory, "older") == nil)
	list_saves(&saves, directory, expected)
	testing.expect_value(t, len(saves), 3)
}

@(test)
test_continue_picks_the_newest_save :: proc(t: ^testing.T) {
	_, found := newest_save(nil)
	testing.expect(t, !found)
	saves := [?]Save_Summary {
		{directory_name = "a", last_played_unix_seconds = 5},
		{directory_name = "b", last_played_unix_seconds = 9},
		{directory_name = "c", last_played_unix_seconds = 7},
	}
	index: int
	index, found = newest_save(saves[:])
	testing.expect(t, found)
	testing.expect_value(t, index, 1)
	testing.expect_value(t, date_text(0, nil), "1970-01-01 00:00")
}
