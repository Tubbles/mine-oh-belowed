package game

import "core:os"
import "core:strings"
import "core:testing"

// The preset's decision per environment and settings state, and its marker
// through the settings file (work item 0076). Files only under a temporary
// directory, as in configuration_test.odin.

deck_preset_test_provenance :: proc(assignments: []string) -> Configuration_Provenance {
	_, provenance, problem := merge_configuration_layers({}, assignments, context.temp_allocator)
	assert(problem == "")
	return provenance
}

@(test)
test_deck_preset_decision :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	fresh := DEFAULT_SETTINGS
	applied := DEFAULT_SETTINGS
	applied.deck_preset_applied = true
	none := deck_preset_test_provenance({})
	testing.expect(t, deck_preset_active("1", fresh, none))
	testing.expect(t, !deck_preset_active("", fresh, none))
	testing.expect(t, !deck_preset_active("0", fresh, none))
	testing.expect(t, !deck_preset_active("1", applied, none))
	// A --set of another key leaves it on, one of its keys holds it off.
	testing.expect(t, deck_preset_active("1", fresh, deck_preset_test_provenance({"settings.pointer_speed=2"})))
	keys := DECK_PRESET_KEYS
	for key in keys {
		provenance := deck_preset_test_provenance({key_with_value(key)})
		testing.expectf(t, !deck_preset_active("1", fresh, provenance), "--set=%s", key)
	}
}

// A value of the key's type, so the assignment names the key.
key_with_value :: proc(key: string) -> string {
	switch key {
	case "settings.window_mode":
		return "settings.window_mode=windowed"
	case "settings.weather", "settings.deck_preset_applied":
		return strings.concatenate({key, "=false"}, context.temp_allocator)
	}
	return strings.concatenate({key, "=1"}, context.temp_allocator)
}

@(test)
test_deck_preset_values :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	settings.window_mode = .Windowed
	settings.weather = false
	settings.pointer_speed = 2
	preset := apply_deck_preset(settings)
	testing.expect_value(t, preset.frame_rate_cap, DECK_PRESET_FRAME_RATE_CAP)
	testing.expect(t, preset.weather)
	testing.expect_value(t, preset.ui_scale, DECK_PRESET_UI_SCALE)
	testing.expect_value(t, preset.text_scale, DECK_PRESET_TEXT_SCALE)
	testing.expect_value(t, preset.window_mode, Window_Mode.Borderless)
	testing.expect(t, preset.deck_preset_applied)
	testing.expect_value(t, preset.pointer_speed, 2)
	// The preset's values pass the configuration's own checks.
	testing.expect_value(t, validate_settings(preset, nil), "")
}

// First start, the marker on disk, a later choice of the player kept, and
// a settings file from before the preset (no marker) taking it.
@(test)
test_deck_preset_marker_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	environment := test_environment(root)

	first, problem := load_configuration(environment, {})
	testing.expect_value(t, problem, "")
	testing.expect(t, deck_preset_active("1", first.configuration.settings, first.provenance))
	testing.expect_value(t, write_settings_file(environment, apply_deck_preset(first.configuration.settings)), "")

	second, second_problem := load_configuration(environment, {})
	testing.expect_value(t, second_problem, "")
	testing.expect_value(t, second.configuration.settings, apply_deck_preset(DEFAULT_SETTINGS))
	testing.expect(t, !deck_preset_active("1", second.configuration.settings, second.provenance))

	chosen := second.configuration.settings
	chosen.ui_scale = 1.3
	chosen.frame_rate_cap = 60
	testing.expect_value(t, write_settings_file(environment, chosen), "")
	third, third_problem := load_configuration(environment, {})
	testing.expect_value(t, third_problem, "")
	testing.expect(t, !deck_preset_active("1", third.configuration.settings, third.provenance))
	testing.expect_value(t, third.configuration.settings, chosen)

	settings_file := join_save_path(root, "home", GAME_DIRECTORY_NAME, CONFIGURATION_DROP_IN_DIRECTORY, SETTINGS_FILE_NAME)
	write_test_file(settings_file, "settings = {ui_scale = 1.3}\n")
	fourth, fourth_problem := load_configuration(environment, {})
	testing.expect_value(t, fourth_problem, "")
	testing.expect(t, deck_preset_active("1", fourth.configuration.settings, fourth.provenance))
	testing.expect_value(t, fourth.configuration.settings.ui_scale, 1.3)
}
