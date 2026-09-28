package game

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

// Watcher tests write only under a temporary directory they create and
// remove.

@(test)
test_data_files_fall_into_their_categories :: proc(t: ^testing.T) {
	cases := [?]struct {
		path:     string,
		category: Data_File_Category,
	} {
		{"strings/en.sjson", .Strings},
		{"strings/.en.sjson.swp", .Ignored},
		{"bindings.sjson", .Bindings},
		{"dev_kits.sjson", .Developer_Kits},
		{"shaders/chunk.fs", .Shaders},
		{"shaders/chunk.vs", .Shaders},
		{"shaders/water.fs", .Shaders},
		{"shaders/water.vs", .Shaders},
		{"shaders/sky.fs", .Ignored},
		{"fonts/fonts.sjson", .Fonts},
		{"fonts/exo_2/Exo2[wght].ttf", .Fonts},
		{"fonts/play/Play-Bold.ttf", .Fonts},
		{"fonts/exo_2/OFL.txt", .Ignored},
		{"fonts/exo_2/.Exo2[wght].ttf.swp", .Ignored},
		{"fonts/Loose.ttf", .Ignored},
		{"models/wooden_chest.vox", .Models},
		{"models/.wooden_chest.vox.swp", .Ignored},
		{"models/notes.txt", .Ignored},
		{"textures/blocks/grass_top.png", .Textures},
		{"textures/items/iron_plate.png", .Textures},
		{"textures/items/.iron_plate.png.swp", .Ignored},
		{"textures/blocks/notes.txt", .Ignored},
		{"textures/stone.png", .Ignored},
		{"sounds/sounds.sjson", .Sounds},
		{"sounds/footstep_stone.wav", .Sounds},
		{"sounds/.footstep_stone.wav.swp", .Ignored},
		{"sounds/notes.txt", .Ignored},
		{"game.sjson", .Restart},
		{"items.sjson", .Content},
		{"recipes.sjson", .Content},
		{"veins.sjson", .Content},
		{"biomes.sjson", .Content},
		{"quests/chapter_03.sjson", .Content},
		{"quests/chapter_03.sjson~", .Ignored},
		{"blueprints/tier1_factory.sjson", .Ignored},
		{"items.sjson.orig", .Ignored},
	}
	for entry in cases {
		testing.expectf(t, data_file_category(entry.path) == entry.category, "%s is %v", entry.path, data_file_category(entry.path))
	}
}

@(test)
test_watch_data_mode_follows_the_command_line_then_the_setting :: proc(t: ^testing.T) {
	testing.expect_value(t, effective_watch_data_mode(.Default, .Default, false), Watch_Data_Mode.Off)
	testing.expect_value(t, effective_watch_data_mode(.Default, .Default, true), Watch_Data_Mode.Presentation)
	testing.expect_value(t, effective_watch_data_mode(.Default, .All, false), Watch_Data_Mode.All)
	testing.expect_value(t, effective_watch_data_mode(.Off, .All, true), Watch_Data_Mode.Off)
	mode, ok := parse_watch_data_mode("presentation")
	testing.expect(t, ok && mode == .Presentation)
	_, ok = parse_watch_data_mode("sometimes")
	testing.expect(t, !ok)
}

@(test)
test_watch_data_setting_reads_and_writes_by_name :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	loaded, problem := load_configuration(test_environment(root), {"settings.watch_data=all"})
	testing.expect_value(t, problem, "")
	testing.expect_value(t, loaded.configuration.settings.watch_data, Watch_Data_Mode.All)
	_, problem = load_configuration(test_environment(root), {"settings.watch_data=sometimes"})
	testing.expect_value(t, problem, `command line: settings.watch_data is "sometimes", not one of default, off, presentation, all`)
	testing.expect(t, strings.contains(settings_file_text(loaded.configuration.settings), "\twatch_data = \"all\"\n"))
}

@(test)
test_watcher_notices_changed_files :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-watch-test-*", context.temp_allocator)
	assert(error == nil)
	defer os.remove_all(directory)
	strings_path := join_save_path(directory, STRINGS_DIRECTORY, STRINGS_FILE_NAME)
	items_path := join_save_path(directory, ITEMS_FILE_NAME)
	write_test_file(strings_path, `hello = "Hi"`)
	write_test_file(items_path, "items = []")
	write_test_file(join_save_path(directory, "blueprints", "base.sjson"), "commands = []")
	watch: Data_Watch
	defer destroy_data_watch(&watch)
	now := time.unix(1_700_000_000, 0)
	testing.expect_value(t, poll_data_watch(&watch, directory, now), Data_File_Categories{})
	testing.expect_value(t, len(watch.stamps), 3)
	testing.expect(t, !data_watch_poll_due(watch, time.time_add(now, DATA_WATCH_INTERVAL / 2)))
	testing.expect(t, data_watch_poll_due(watch, time.time_add(now, DATA_WATCH_INTERVAL)))

	// Same size, only the modification time moves.
	testing.expect_value(t, os.change_times(strings_path, now, now), nil)
	testing.expect_value(t, poll_data_watch(&watch, directory, now), Data_File_Categories{.Strings})
	testing.expect_value(t, poll_data_watch(&watch, directory, now), Data_File_Categories{})

	write_test_file(items_path, "items = [ ]")
	write_test_file(join_save_path(directory, "blueprints", "base.sjson"), "commands = [ ]")
	testing.expect_value(t, poll_data_watch(&watch, directory, now), Data_File_Categories{.Content})
	testing.expect(t, watch.content_changed && watch.content_settling)
	testing.expect_value(t, poll_data_watch(&watch, directory, now), Data_File_Categories{})
	testing.expect(t, watch.content_changed && !watch.content_settling)

	testing.expect_value(t, os.remove(strings_path), nil)
	testing.expect_value(t, poll_data_watch(&watch, directory, now), Data_File_Categories{.Strings})
}
