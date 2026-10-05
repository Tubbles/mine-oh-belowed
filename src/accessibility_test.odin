package game

import "core:testing"

// Work item 0074: the text scale, the marker palettes and the reduced
// motion rule. The hold and toggle rules are in player_test.odin, the
// settings' configuration in configuration_test.odin.

// The bottleneck colours and the map colours are shown apart, so each
// set only needs to be distinct within itself.
BOTTLENECK_PALETTE_COLORS :: bit_set[Palette_Color]{.Working, .Waiting, .Missing, .Idle}
MAP_PALETTE_COLORS :: bit_set[Palette_Color]{.Map_Player, .Map_Machine, .Map_Assayed, .Map_Magnetometer, .Map_Core_Sample, .Map_Core_Sample_Vein, .Map_Seismic, .Map_Resolved}

@(test)
test_text_scale_multiplies_measured_and_drawn_sizes :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	settings.text_scale = 1.5
	state: Ui_State
	// Before ui_begin (tests) the text measures at 1.
	testing.expect_value(t, ui_text_width_in_weight(&state, "Settings", UI_BODY_TEXT_SIZE, .Regular), approximate_text_width("Settings", UI_BODY_TEXT_SIZE))
	ui_begin(&state, {}, {1920, 1080}, 1.0 / 60, 1, 1, ui_accessibility(settings))
	defer destroy_ui_state(&state)
	testing.expect_value(t, state.accessibility.text_scale, 1.5)
	testing.expect_value(t, ui_text_width_in_weight(&state, "Settings", UI_BODY_TEXT_SIZE, .Regular), approximate_text_width("Settings", 1.5 * UI_BODY_TEXT_SIZE))

	commands := [?]Draw_Command{{kind = .Text, text_size = UI_BODY_TEXT_SIZE}, {kind = .Outline, thickness = 2}}
	scale_text_commands(commands[:], ui_text_scale(state))
	testing.expect_value(t, commands[0].text_size, 1.5 * UI_BODY_TEXT_SIZE)
	testing.expect_value(t, commands[1].thickness, 2)
	// On top of the UI scale: body text at 1080 lines and UI scale 1.2.
	testing.expect_value(t, font_pixel_size(commands[0].text_size, ui_pixels_per_unit(1080, 1.2)), 43)
}

expect_distinct_palette_colors :: proc(t: ^testing.T, colors: [Palette_Color]Ui_Color, set: bit_set[Palette_Color], palette: Marker_Palette) {
	for first in set {
		for second in set {
			if first < second {
				testing.expectf(t, colors[first] != colors[second], "%v: %v and %v share %v", palette, first, second, colors[first])
			}
		}
	}
}

@(test)
test_palettes_colour_every_marker_apart :: proc(t: ^testing.T) {
	shipped, problem := parse_ui_theme(#load("../data/ui/theme.sjson"), "data/ui/theme.sjson")
	testing.expect_value(t, problem, "")
	themes := [?]Ui_Theme{DEFAULT_UI_THEME, shipped}
	for theme in themes {
		for palette in Marker_Palette {
			colors := theme.palettes[palette]
			expect_distinct_palette_colors(t, colors, BOTTLENECK_PALETTE_COLORS, palette)
			expect_distinct_palette_colors(t, colors, MAP_PALETTE_COLORS, palette)
			bottleneck := bottleneck_marker_colors(theme, palette)
			for marker in Marker_Colour {
				testing.expect_value(t, bottleneck[marker], colors[marker_palette_colors[marker]])
			}
			legend: bit_set[Palette_Color]
			for entry in map_legend_entries {
				legend += {entry.color}
			}
			testing.expect_value(t, legend, MAP_PALETTE_COLORS)
		}
	}
}

@(test)
test_palette_colours_the_map_dots :: proc(t: ^testing.T) {
	theme := DEFAULT_UI_THEME
	theme.colors[.Map_Marker_Raw] = {1, 2, 3, 255}
	testing.expect_value(t, map_dot_color(theme, .Default, .Raw), Ui_Color{1, 2, 3, 255})
	for category in Item_Category {
		testing.expect_value(t, map_dot_color(theme, .Colour_Blind, category), theme.palettes[.Colour_Blind][.Map_Machine])
	}
	item_definitions := [?]Item{{id = "drill_item", category = .Machine}}
	items := Item_Registry {
		items = item_definitions[:],
	}
	machine_definitions := [?]Machine{{id = "drill", item = 0}, {id = "capsule", item = NO_ITEM}}
	machines := Machine_Registry {
		machines = machine_definitions[:],
	}
	colors := machine_marker_colors(theme, machines, items, .Colour_Blind)
	testing.expect_value(t, colors[0], theme.palettes[.Colour_Blind][.Map_Machine])
	testing.expect_value(t, colors[1], theme.palettes[.Colour_Blind][.Map_Machine])
}

@(test)
test_theme_palettes_parse_and_refuse :: proc(t: ^testing.T) {
	theme, problem := parse_ui_theme(transmute([]byte)string("palettes = {colour_blind = {working = [1, 2, 3, 255]}}"), "theme.sjson")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, theme.palettes[.Colour_Blind][.Working], Ui_Color{1, 2, 3, 255})
	// A colour left out keeps its default.
	testing.expect_value(t, theme.palettes[.Colour_Blind][.Waiting], DEFAULT_UI_THEME.palettes[.Colour_Blind][.Waiting])
	testing.expect_value(t, theme.palettes[.Default], DEFAULT_UI_THEME.palettes[.Default])

	Invalid :: struct {
		text:    string,
		mention: string,
	}
	invalid := [?]Invalid {
		{"palettes = [1]", "palettes must be an object"},
		{"palettes = {rainbow = {}}", "unknown key palettes.rainbow"},
		{"palettes = {default = 1}", "palettes.default must be an object"},
		{"palettes = {default = {green = [1, 2, 3, 255]}}", "unknown key palettes.default.green"},
		{"palettes = {default = {idle = [1, 2, 3]}}", "palettes.default.idle must be an array of 4"},
		{"palettes = {default = {idle = [1, 2, 3, 256]}}", "palettes.default.idle[3] must be a whole number from 0 to 255"},
	}
	for entry in invalid {
		_, problem = parse_ui_theme(transmute([]byte)entry.text, "theme.sjson")
		expect_problem_mentions(t, problem, "theme.sjson", entry.mention)
	}
}

@(test)
test_reduced_motion_stills_each_motion :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	testing.expect(t, head_bob_enabled(settings))
	testing.expect(t, weather_motion_enabled(settings))
	testing.expect_value(t, sprint_kick_degrees(settings), settings.sprint_field_of_view_kick)
	testing.expect_value(t, flicker_seconds(12.5, false), 12.5)
	testing.expect_value(t, still_focus_pulse(0.25, false), 0.25)

	settings.reduced_motion = true
	testing.expect(t, !head_bob_enabled(settings))
	testing.expect_value(t, head_bob_amplitude(true, true, head_bob_enabled(settings)), 0)
	testing.expect_value(t, sprint_kick_degrees(settings), 0)
	testing.expect_value(t, sprint_field_of_view(70, sprint_kick_degrees(settings), 1), 70)
	// The weather look reads it as the weather setting off.
	testing.expect(t, !weather_motion_enabled(settings))
	look := weather_look(Weather{kind = .Rain, intensity = 1}, weather_motion_enabled(settings), 1)
	testing.expect_value(t, look, Weather_Look{fog_scale = 1})
	// The block light's flicker and the flames' flicker stand still.
	testing.expect_value(t, flicker_seconds(12.5, true), flicker_seconds(99, true))
	testing.expect_value(t, flame_flicker(12.5, 7, true), flame_flicker(99, 7, true))
	testing.expect_value(t, flame_flicker(12.5, 7, true), FLAME_FLICKER_MEAN)
	testing.expect_value(t, still_focus_pulse(0.25, true), 1)

	// Each off on its own stays off with reduced motion off.
	settings.reduced_motion = false
	settings.head_bob, settings.weather = false, false
	testing.expect(t, !head_bob_enabled(settings))
	testing.expect(t, !weather_motion_enabled(settings))
}

@(test)
test_reduced_motion_holds_the_focus_pulse :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	settings.reduced_motion = true
	state: Ui_State
	defer destroy_ui_state(&state)
	for _ in 0 ..< 30 {
		ui_begin(&state, {}, {1920, 1080}, 1.0 / 60, 1, 1, ui_accessibility(settings))
		testing.expect_value(t, state.focus_pulse, 1)
	}
}

@(test)
test_reduced_motion_shows_mission_control_whole :: proc(t: ^testing.T) {
	state: Mission_Control_State
	defer destroy_mission_control(&state)
	push_mission_control_line(&state, "Extraction rights are yours.")
	advance_mission_control(&state, 1.0 / 60, true)
	line := state.lines[0]
	testing.expect(t, !mission_control_line_revealing(line))
	testing.expect(t, revealed_characters(line.seconds) >= line.character_count)
	// The hold and the fade keep their length.
	testing.expect_value(t, instant_reveal(Mission_Control_Line{character_count = 40}).seconds, mission_control_reveal_seconds(40))
	testing.expect_value(t, instant_reveal(Mission_Control_Line{character_count = 40, seconds = 3}).seconds, 3)
	typed: Mission_Control_State
	defer destroy_mission_control(&typed)
	push_mission_control_line(&typed, "Extraction rights are yours.")
	advance_mission_control(&typed, 1.0 / 60)
	testing.expect(t, mission_control_line_revealing(typed.lines[0]))
}
