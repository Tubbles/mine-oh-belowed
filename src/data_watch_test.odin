package game

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import fsw "shared:fsw"

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
		{"touch_overlay.sjson", .Content},
		{"shaders/chunk.fs", .Shaders},
		{"shaders/chunk.vs", .Shaders},
		{"shaders/water.fs", .Shaders},
		{"shaders/water.vs", .Shaders},
		{"shaders/shadow.fs", .Ignored},
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
		{"textures/procedural.sjson", .Textures},
		{"textures/.procedural.sjson.swp", .Ignored},
		{"sounds/sounds.sjson", .Sounds},
		{"sounds/footstep_stone.wav", .Sounds},
		{"sounds/.footstep_stone.wav.swp", .Ignored},
		{"sounds/notes.txt", .Ignored},
		{"ui/theme.sjson", .Theme},
		{"ui/.theme.sjson.swp", .Ignored},
		{"ui/notes.txt", .Ignored},
		{"ui/icons/button_south.png", .Theme},
		{"ui/icons/.button_south.png.swp", .Ignored},
		{"ui/icons/notes.txt", .Ignored},
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
test_data_events_fall_into_the_categories_of_their_files :: proc(t: ^testing.T) {
	directory := join_save_path("/games", "mine-oh-belowed", "data")
	cases := [?]struct {
		event:    fsw.Event,
		category: Data_File_Category,
	} {
		{{.Modified, join_save_path(directory, STRINGS_DIRECTORY, STRINGS_FILE_NAME), false}, .Strings},
		{{.Renamed, join_save_path(directory, CHUNK_SHADER_DIRECTORY, "chunk.fs"), false}, .Shaders},
		{{.Added, join_save_path(directory, "textures", "blocks", "grass_top.png"), false}, .Textures},
		{{.Removed, join_save_path(directory, ITEMS_FILE_NAME), false}, .Content},
		{{.Added, join_save_path(directory, "textures", "blocks"), true}, .Ignored},
		{{.Modified, join_save_path(directory, "blueprints", "base.sjson"), false}, .Ignored},
		{{.Modified, join_save_path("/games", "mine-oh-belowed", "data2", ITEMS_FILE_NAME), false}, .Ignored},
		{{.Overflow, "", false}, .Ignored},
	}
	events: [len(cases)]fsw.Event
	for entry, index in cases {
		category := data_event_category(directory, entry.event)
		testing.expectf(t, category == entry.category, "%s is %v", entry.event.path, category)
		events[index] = entry.event
	}
	testing.expect_value(t, data_event_categories(directory, events[:]), Data_File_Categories{.Strings, .Shaders, .Textures, .Content})
}

// Polls every 10 ms until the categories include expected or two seconds
// passed, so the test does not depend on how fast the events arrive.
wait_for_data_events :: proc(watch: ^Data_Watch, expected: Data_File_Categories, now: time.Time) -> (changed: Data_File_Categories) {
	start := time.tick_now()
	for time.tick_since(start) < 2 * time.Second {
		changed += poll_data_watch(watch, now)
		if expected <= changed {
			return changed
		}
		time.sleep(10 * time.Millisecond)
	}
	return changed
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
	testing.expect(t, open_data_watch(&watch, directory))
	now := time.unix(1_700_000_000, 0)
	testing.expect_value(t, poll_data_watch(&watch, now), Data_File_Categories{})

	write_test_file(strings_path, `hello = "Hello"`)
	testing.expect_value(t, wait_for_data_events(&watch, {.Strings}, now), Data_File_Categories{.Strings})

	write_test_file(items_path, "items = [ ]")
	write_test_file(join_save_path(directory, "blueprints", "base.sjson"), "commands = [ ]")
	testing.expect_value(t, wait_for_data_events(&watch, {.Content}, now), Data_File_Categories{.Content})
	testing.expect(t, watch.content_changed && watch.content_settling)
	testing.expect_value(t, watch.last_content_event, now)

	// Saved through a rename, as many editors do.
	temporary_path := join_save_path(directory, STRINGS_DIRECTORY, "en.sjson.tmp")
	write_test_file(temporary_path, `hello = "Hey"`)
	testing.expect_value(t, os.rename(temporary_path, strings_path), nil)
	testing.expect_value(t, wait_for_data_events(&watch, {.Strings}, now), Data_File_Categories{.Strings})

	testing.expect_value(t, os.remove(strings_path), nil)
	testing.expect_value(t, wait_for_data_events(&watch, {.Strings}, now), Data_File_Categories{.Strings})
	testing.expect_value(t, poll_data_watch(&watch, now), Data_File_Categories{})
}

@(test)
test_content_settles_a_second_after_its_last_event :: proc(t: ^testing.T) {
	now := time.unix(1_700_000_000, 0)
	watch := Data_Watch {
		content_changed    = true,
		content_settling   = true,
		last_content_event = now,
	}
	testing.expect(t, !data_watch_content_settled(watch, time.time_add(now, DATA_WATCH_CONTENT_SETTLE - time.Millisecond)))
	testing.expect(t, data_watch_content_settled(watch, time.time_add(now, DATA_WATCH_CONTENT_SETTLE)))
	watch.content_settling = false
	testing.expect(t, !data_watch_content_settled(watch, time.time_add(now, 2 * DATA_WATCH_CONTENT_SETTLE)))
}
