package game

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"

// Configuration tests write only under a temporary directory they create
// and remove, and pass the XDG directories in; the real configuration is
// never read or written.

make_configuration_test_directory :: proc() -> string {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-config-test-*", context.temp_allocator)
	assert(error == nil)
	return directory
}

write_test_file :: proc(path, text: string) {
	os.make_directory_all(path[:strings.last_index_byte(path, '/')])
	assert(os.write_entire_file(path, text) == nil)
}

test_environment :: proc(root: string) -> Configuration_Environment {
	return Configuration_Environment {
		config_home = join_save_path(root, "home"),
		config_dirs = strings.concatenate({join_save_path(root, "first"), ":", join_save_path(root, "second")}, context.temp_allocator),
		home = "/home/player",
	}
}

@(test)
test_configuration_layer_precedence :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	first := join_save_path(root, "first", GAME_DIRECTORY_NAME, CONFIGURATION_FILE_NAME)
	second := join_save_path(root, "second", GAME_DIRECTORY_NAME, CONFIGURATION_FILE_NAME)
	user := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_FILE_NAME)
	drop_in := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_DROP_IN_DIRECTORY)
	write_test_file(second, "settings = {ui_scale = 0.8, pointer_speed = 0.5, gyro_look_sensitivity = 0.5}")
	write_test_file(first, "settings = {ui_scale = 0.9, pointer_speed = 0.6}")
	write_test_file(user, "settings = {ui_scale = 1.0, stick_look_sensitivity = 2}")
	write_test_file(join_save_path(drop_in, "20-late.sjson"), "settings = {ui_scale = 1.2}")
	write_test_file(join_save_path(drop_in, "10-early.sjson"), "settings = {ui_scale = 1.1, invert_pitch = true}")
	write_test_file(join_save_path(drop_in, "notes.txt"), "not configuration")

	loaded, problem := load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")
	settings := loaded.configuration.settings
	testing.expect_value(t, settings.ui_scale, 1.2)
	testing.expect_value(t, settings.pointer_speed, 0.6)
	testing.expect_value(t, settings.gyro_look_sensitivity, 0.5)
	testing.expect_value(t, settings.stick_look_sensitivity, 2)
	testing.expect(t, settings.invert_pitch)
	testing.expect_value(t, settings.autosave_minutes, DEFAULT_SETTINGS.autosave_minutes)
	testing.expect_value(t, source_of_key_path(loaded.provenance, "settings.ui_scale"), join_save_path(drop_in, "20-late.sjson"))
	testing.expect_value(t, source_of_key_path(loaded.provenance, "settings.pointer_speed"), first)
	testing.expect_value(t, source_of_key_path(loaded.provenance, "settings.autosave_minutes"), DEFAULT_SOURCE)

	expected_files := [?]string{second, first, user, join_save_path(drop_in, "10-early.sjson"), join_save_path(drop_in, "20-late.sjson")}
	testing.expect_value(t, len(loaded.files), len(expected_files))
	for path, index in expected_files {
		if index < len(loaded.files) {
			testing.expect_value(t, loaded.files[index].path, path)
			testing.expect(t, loaded.files[index].found)
		}
	}

	overridden, command_line_problem := load_configuration(test_environment(root), {"settings.ui_scale=1.3"})
	testing.expect_value(t, command_line_problem, "")
	testing.expect_value(t, overridden.configuration.settings.ui_scale, 1.3)
	testing.expect_value(t, source_of_key_path(overridden.provenance, "settings.ui_scale"), COMMAND_LINE_SOURCE)
}

@(test)
test_configuration_missing_files_and_defaults :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	loaded, problem := load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")
	testing.expect_value(t, loaded.configuration.settings, DEFAULT_SETTINGS)
	// Two system files, the user file and config.d, all missing.
	testing.expect_value(t, len(loaded.files), 4)
	for file in loaded.files {
		testing.expect(t, !file.found)
	}
	testing.expect(t, strings.has_suffix(loaded.files[3].path, "config.d/"))
}

@(test)
test_configuration_directories_from_environment :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defaults := Configuration_Environment {
		home = "/home/player",
	}
	directory, found := user_configuration_directory(defaults)
	testing.expect(t, found)
	testing.expect_value(t, directory, "/home/player/.config/mine-oh-belowed")
	system := system_configuration_directories(defaults)
	testing.expect_value(t, len(system), 1)
	testing.expect_value(t, system[0], "/etc/xdg/mine-oh-belowed")
	relative := Configuration_Environment {
		config_home = "relative",
		config_dirs = "/a:relative::/b",
		home        = "/home/player",
	}
	directory, _ = user_configuration_directory(relative)
	testing.expect_value(t, directory, "/home/player/.config/mine-oh-belowed")
	system = system_configuration_directories(relative)
	testing.expect_value(t, len(system), 2)
	testing.expect_value(t, system[0], "/b/mine-oh-belowed")
	testing.expect_value(t, system[1], "/a/mine-oh-belowed")
}

merge_test_layers :: proc(layers: []string) -> (json.Object, Configuration_Provenance) {
	tree := make(json.Object)
	provenance := make(Configuration_Provenance)
	for text, index in layers {
		source := index == 0 ? "lower" : "upper"
		layer, problem := parse_configuration_layer(transmute([]byte)text, source)
		assert(problem == "")
		merge_configuration_object(&tree, layer, "", source, &provenance)
	}
	return tree, provenance
}

@(test)
test_configuration_merge_rules :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	layers := [?]string {
		`settings = {ui_scale = 0.9, pointer_speed = 2} bindings = [{action = "Jump"}, {action = "Mine"}] paths = {saves = "/a"}`,
		`settings = {pointer_speed = 1} bindings = [{action = "Place"}] paths = "replaced"`,
	}
	tree, provenance := merge_test_layers(layers[:])
	settings := tree["settings"].(json.Object)
	// Objects merge key by key.
	testing.expect_value(t, settings["ui_scale"].(json.Float), 0.9)
	testing.expect_value(t, settings["pointer_speed"].(json.Integer), 1)
	testing.expect_value(t, source_of_key_path(provenance, "settings.ui_scale"), "lower")
	testing.expect_value(t, source_of_key_path(provenance, "settings.pointer_speed"), "upper")
	// Arrays replace wholesale.
	bindings := tree["bindings"].(json.Array)
	testing.expect_value(t, len(bindings), 1)
	testing.expect_value(t, bindings[0].(json.Object)["action"].(json.String), "Place")
	testing.expect_value(t, source_of_key_path(provenance, "bindings[0].action"), "upper")
	// A scalar replaces an object too.
	testing.expect_value(t, tree["paths"].(json.String), "replaced")
}

expect_problem_mentions :: proc(t: ^testing.T, problem: string, parts: ..string) {
	testing.expect(t, problem != "", "expected a problem")
	for part in parts {
		testing.expectf(t, strings.contains(problem, part), "problem %q does not mention %q", problem, part)
	}
}

@(test)
test_configuration_unknown_key_and_wrong_type :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	user := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_FILE_NAME)
	drop_in := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_DROP_IN_DIRECTORY, "50-typo.sjson")

	write_test_file(user, "settings = {ui_scale = 1.1}")
	write_test_file(drop_in, "settings = {ui_scael = 1.2}")
	_, problem := load_configuration(test_environment(root), {})
	expect_problem_mentions(t, problem, drop_in, "unknown key settings.ui_scael")

	write_test_file(drop_in, `settings = {ui_scale = "large"}`)
	_, problem = load_configuration(test_environment(root), {})
	expect_problem_mentions(t, problem, drop_in, "settings.ui_scale must be a number, not a string")

	write_test_file(drop_in, "settings = {autosave_minutes = 2.5}")
	_, problem = load_configuration(test_environment(root), {})
	expect_problem_mentions(t, problem, drop_in, "settings.autosave_minutes must be a whole number")

	write_test_file(drop_in, "settings = true")
	_, problem = load_configuration(test_environment(root), {})
	expect_problem_mentions(t, problem, drop_in, "settings must be an object")

	write_test_file(drop_in, `bindings = [{action = "Jump" device = "keyboard" control = "J" context = "world" colour = "red"}]`)
	_, problem = load_configuration(test_environment(root), {})
	expect_problem_mentions(t, problem, drop_in, "unknown key bindings[0].colour")

	write_test_file(drop_in, "settings = {ui_scale = 40}")
	_, problem = load_configuration(test_environment(root), {})
	expect_problem_mentions(t, problem, drop_in, "settings.ui_scale is 40")

	os.remove(drop_in)
	_, problem = load_configuration(test_environment(root), {"settings.gyro_enabled=maybe"})
	expect_problem_mentions(t, problem, COMMAND_LINE_SOURCE, "settings.gyro_enabled must be a boolean")
	_, problem = load_configuration(test_environment(root), {"settings.ui_scale"})
	expect_problem_mentions(t, problem, COMMAND_LINE_SOURCE, "--set=<key>=<value>")
}

@(test)
test_configuration_home_expansion :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, expand_home("~/saves", "/home/player"), "/home/player/saves")
	testing.expect_value(t, expand_home("~/saves", "/home/player/"), "/home/player/saves")
	testing.expect_value(t, expand_home("/srv/saves", "/home/player"), "/srv/saves")
	testing.expect_value(t, expand_home("~other/saves", "/home/player"), "~other/saves")
	testing.expect_value(t, expand_home("~/saves", ""), "~/saves")

	root := make_configuration_test_directory()
	defer os.remove_all(root)
	write_test_file(join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_FILE_NAME), `paths = {saves = "~/games/saves"}`)
	loaded, problem := load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")
	testing.expect_value(t, loaded.configuration.paths.saves, "/home/player/games/saves")
	// Unquoted on the command line.
	loaded, problem = load_configuration(test_environment(root), {"paths.saves=~/elsewhere"})
	testing.expect_value(t, problem, "")
	testing.expect_value(t, loaded.configuration.paths.saves, "/home/player/elsewhere")
}

@(test)
test_settings_file_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	environment := test_environment(root)
	other := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_DROP_IN_DIRECTORY, "95-mine.sjson")
	other_text := "// mine\nsettings = {autosave_minutes = 10}\n"
	write_test_file(other, other_text)

	settings := DEFAULT_SETTINGS
	settings.ui_scale = 1.15
	settings.pointer_speed = 0.7
	settings.gyro_enabled = false
	settings.font = "rajdhani"
	settings.monospace_font = "share_tech_mono"
	settings.window_mode = .Fullscreen
	settings.resolution = {1920, 1080}
	settings.vsync = false
	settings.frame_rate_cap = 144
	settings.weather = false
	settings.shadows = true
	settings.head_bob = false
	settings.field_of_view = 95
	settings.sprint_field_of_view_kick = 0
	settings.third_person_distance = 6.5
	settings.third_person_shoulder = -0.4
	settings.master_volume = 0.55
	settings.effects_volume = 0.25
	settings.ambience_volume = 0
	testing.expect_value(t, write_settings_file(environment, settings), "")

	loaded, problem := load_configuration(environment, {})
	testing.expect_value(t, problem, "")
	settings.autosave_minutes = 10
	testing.expect_value(t, loaded.configuration.settings, settings)
	written := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_DROP_IN_DIRECTORY, SETTINGS_FILE_NAME)
	testing.expect_value(t, source_of_key_path(loaded.provenance, "settings.ui_scale"), written)
	testing.expect_value(t, source_of_key_path(loaded.provenance, "settings.autosave_minutes"), other)
	data, error := os.read_entire_file(other, context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, string(data), other_text)
	// Only the settings object is written.
	written_data, _ := os.read_entire_file(written, context.temp_allocator)
	tree, parse_problem := parse_configuration_layer(written_data, written)
	testing.expect_value(t, parse_problem, "")
	testing.expect_value(t, len(tree), 1)
	testing.expect(t, "settings" in tree)
	testing.expect(t, strings.contains(string(written_data), "\tui_scale = 1.15\n"), string(written_data))
	testing.expect(t, strings.contains(string(written_data), "\twindow_mode = \"fullscreen\"\n"), string(written_data))
	testing.expect(t, strings.contains(string(written_data), "\tresolution = [1920, 1080]\n"), string(written_data))
	testing.expect(t, strings.contains(string(written_data), "\tmaster_volume = 0.55\n"), string(written_data))
	testing.expect(t, strings.contains(string(written_data), "\tfield_of_view = 95\n"), string(written_data))
}

@(test)
test_configuration_dump :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	user := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_FILE_NAME)
	write_test_file(user, `settings = {ui_scale = 1.25} bindings = [{action = "Jump" device = "keyboard" control = "J" context = "world"}]`)
	loaded, problem := load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")
	defaults, defaults_problem := parse_bindings_file(#load("../data/bindings.sjson"), "data/bindings.sjson")
	testing.expect_value(t, defaults_problem, "")
	overrides, overrides_problem := resolve_bindings(loaded.configuration.bindings, loaded.provenance)
	testing.expect_value(t, overrides_problem, "")
	dump := configuration_dump(loaded, effective_bindings(defaults, overrides))

	system := join_save_path(root, "first", GAME_DIRECTORY_NAME, CONFIGURATION_FILE_NAME)
	expected_lines := [?]string {
		strings.concatenate({"//   ", system, " (missing)"}),
		strings.concatenate({"//   ", user}),
		strings.concatenate({"\tui_scale = 1.25 // ", user}),
		"\tpointer_speed = 1.5 // default",
		"\twindow_mode = \"borderless\" // default",
		"\tresolution = [0, 0] // default",
		"\tframe_rate_cap = 0 // default",
		"\tsaves = \"\" // default",
		strings.concatenate({`{action = "Jump" device = "keyboard" control = "J" context = "world"} // `, user}),
		`{action = "Mine" device = "mouse" control = "LEFT" context = "world"} // data/bindings.sjson`,
		`{action = "Sprint" device = "gamepad" control = "LEFT_STICK" context = "world" backend = "sdl3"} // data/bindings.sjson`,
	}
	for line in expected_lines {
		testing.expectf(t, strings.contains(dump, line), "dump lacks %q:\n%s", line, dump)
	}
	testing.expect(t, !strings.contains(dump, `control = "SPACE"`), "the override replaces every Jump default")
	// The dump is SJSON itself.
	tree, parse_problem := parse_configuration_layer(transmute([]byte)dump, "dump")
	testing.expect_value(t, parse_problem, "")
	testing.expect_value(t, len(tree), 3)
}

@(test)
test_configuration_display_settings :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	drop_in := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_DROP_IN_DIRECTORY, "50-display.sjson")

	write_test_file(drop_in, `settings = {window_mode = "windowed" resolution = [1600, 900] vsync = false frame_rate_cap = 60}`)
	loaded, problem := load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")
	settings := loaded.configuration.settings
	testing.expect_value(t, settings.window_mode, Window_Mode.Windowed)
	testing.expect_value(t, settings.resolution, [2]int{1600, 900})
	testing.expect(t, !settings.vsync)
	testing.expect_value(t, settings.frame_rate_cap, 60)
	// Both ends of each range.
	write_test_file(drop_in, "settings = {resolution = [320, 7680] frame_rate_cap = 480}")
	_, problem = load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")
	write_test_file(drop_in, "settings = {field_of_view = 60 sprint_field_of_view_kick = 15 third_person_distance = 2 third_person_shoulder = -1}")
	_, problem = load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")
	write_test_file(drop_in, "settings = {field_of_view = 110 sprint_field_of_view_kick = 0 third_person_distance = 8 third_person_shoulder = 1}")
	_, problem = load_configuration(test_environment(root), {})
	testing.expect_value(t, problem, "")

	Invalid :: struct {
		text:    string,
		mention: string,
	}
	invalid := [?]Invalid {
		{`settings = {window_mode = "maximised"}`, `settings.window_mode is "maximised", not one of windowed, borderless, fullscreen`},
		{"settings = {window_mode = 1}", "settings.window_mode must be one of"},
		{"settings = {resolution = [319, 720]}", "settings.resolution[0] is 319, outside 320 to 7680"},
		{"settings = {resolution = [1280, 7681]}", "settings.resolution[1] is 7681, outside 320 to 7680"},
		{"settings = {resolution = [0, 720]}", "settings.resolution[0] is 0"},
		{"settings = {resolution = [1280]}", "settings.resolution must be an array of 2, not an array"},
		{"settings = {resolution = 1280}", "settings.resolution must be an array of 2, not a number"},
		{"settings = {resolution = [1280.5, 720]}", "settings.resolution[0] must be a whole number"},
		{"settings = {frame_rate_cap = -1}", "settings.frame_rate_cap is -1, outside 0 to 480"},
		{"settings = {frame_rate_cap = 481}", "settings.frame_rate_cap is 481, outside 0 to 480"},
		{"settings = {frame_rate_cap = 59.94}", "settings.frame_rate_cap must be a whole number"},
		{`settings = {vsync = "on"}`, "settings.vsync must be a boolean"},
		{`settings = {weather = "on"}`, "settings.weather must be a boolean"},
		{`settings = {shadows = "on"}`, "settings.shadows must be a boolean"},
		{`settings = {head_bob = "on"}`, "settings.head_bob must be a boolean"},
		{"settings = {field_of_view = 59}", "settings.field_of_view is 59, outside 60 to 110"},
		{"settings = {field_of_view = 111}", "settings.field_of_view is 111, outside 60 to 110"},
		{"settings = {sprint_field_of_view_kick = -1}", "settings.sprint_field_of_view_kick is -1, outside 0 to 15"},
		{"settings = {sprint_field_of_view_kick = 16}", "settings.sprint_field_of_view_kick is 16, outside 0 to 15"},
		{"settings = {third_person_distance = 1.5}", "settings.third_person_distance is 1.5, outside 2 to 8"},
		{"settings = {third_person_distance = 9}", "settings.third_person_distance is 9, outside 2 to 8"},
		{"settings = {third_person_shoulder = -1.5}", "settings.third_person_shoulder is -1.5, outside -1 to 1"},
		{"settings = {third_person_shoulder = 2}", "settings.third_person_shoulder is 2, outside -1 to 1"},
		{`settings = {field_of_view = "wide"}`, "settings.field_of_view must be a number"},
	}
	for case_value in invalid {
		write_test_file(drop_in, case_value.text)
		_, problem = load_configuration(test_environment(root), {})
		expect_problem_mentions(t, problem, drop_in, case_value.mention)
	}

	os.remove(drop_in)
	loaded, problem = load_configuration(test_environment(root), {"settings.window_mode=windowed", "settings.resolution=[1280, 720]"})
	testing.expect_value(t, problem, "")
	testing.expect_value(t, loaded.configuration.settings.window_mode, Window_Mode.Windowed)
	testing.expect_value(t, loaded.configuration.settings.resolution, [2]int{1280, 720})
	testing.expect_value(t, source_of_key_path(loaded.provenance, "settings.window_mode"), COMMAND_LINE_SOURCE)
}
