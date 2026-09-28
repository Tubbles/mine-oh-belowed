package game

import "core:testing"

display_test_settings :: proc(mode: Window_Mode) -> Settings {
	settings := DEFAULT_SETTINGS
	settings.window_mode = mode
	settings.resolution = {1920, 1080}
	return settings
}

@(test)
test_display_changes_for_every_mode_pair :: proc(t: ^testing.T) {
	Case :: struct {
		from, to: Window_Mode,
		expected: Display_Changes,
	}
	cases := [?]Case {
		{.Windowed, .Windowed, {}},
		{.Windowed, .Borderless, {enter_borderless = true}},
		{.Windowed, .Fullscreen, {enter_fullscreen = true, resize = true, resolution = {1920, 1080}}},
		{.Borderless, .Windowed, {leave_borderless = true, resize = true, resolution = {1920, 1080}, centre = true}},
		{.Borderless, .Borderless, {}},
		{.Borderless, .Fullscreen, {leave_borderless = true, enter_fullscreen = true, resize = true, resolution = {1920, 1080}}},
		{.Fullscreen, .Windowed, {leave_fullscreen = true, resize = true, resolution = {1920, 1080}, centre = true}},
		{.Fullscreen, .Borderless, {leave_fullscreen = true, enter_borderless = true}},
		{.Fullscreen, .Fullscreen, {}},
	}
	for test_case in cases {
		changes := display_changes(display_test_settings(test_case.from), display_test_settings(test_case.to))
		expected := test_case.expected
		// Vsync and the cap are equal, so they only carry the values.
		expected.vsync = DEFAULT_SETTINGS.vsync
		expected.frame_rate_cap = DEFAULT_SETTINGS.frame_rate_cap
		testing.expectf(t, changes == expected, "%v to %v: %v, expected %v", test_case.from, test_case.to, changes, expected)
	}
}

@(test)
test_display_changes_for_each_field :: proc(t: ^testing.T) {
	previous := display_test_settings(.Windowed)
	next := previous
	testing.expect(t, !display_changes(previous, next).resize)
	testing.expect(t, !display_changes(previous, next).change_vsync)
	testing.expect(t, !display_changes(previous, next).change_frame_rate)

	// A setting the window does not use changes nothing.
	next.ui_scale = 1.25
	no_change := display_changes(previous, next)
	testing.expect(t, !no_change.resize && !no_change.change_vsync && !no_change.change_frame_rate)
	testing.expect(t, !no_change.enter_borderless && !no_change.enter_fullscreen)

	next = previous
	next.resolution = NATIVE_RESOLUTION
	resized := display_changes(previous, next)
	testing.expect_value(t, resized, Display_Changes{resize = true, resolution = NATIVE_RESOLUTION, centre = true, vsync = true})

	// Borderless ignores the resolution; fullscreen changes its video mode.
	borderless := display_test_settings(.Borderless)
	borderless_next := borderless
	borderless_next.resolution = {1280, 720}
	testing.expect(t, !display_changes(borderless, borderless_next).resize)
	fullscreen := display_test_settings(.Fullscreen)
	fullscreen_next := fullscreen
	fullscreen_next.resolution = {1280, 720}
	testing.expect_value(t, display_changes(fullscreen, fullscreen_next), Display_Changes{resize = true, resolution = {1280, 720}, vsync = true})

	next = previous
	next.vsync = false
	testing.expect_value(t, display_changes(previous, next), Display_Changes{change_vsync = true, vsync = false})

	next = previous
	next.frame_rate_cap = 60
	testing.expect_value(t, display_changes(previous, next), Display_Changes{vsync = true, change_frame_rate = true, frame_rate_cap = 60})
}

@(test)
test_initial_window_applies_the_settings :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	settings.frame_rate_cap = 60
	window := initial_window_settings(settings)
	testing.expect_value(t, window.window_mode, Window_Mode.Windowed)
	testing.expect_value(t, window.resolution, INITIAL_WINDOW_SIZE)
	testing.expect_value(t, window.frame_rate_cap, 0)
	testing.expect_value(t, display_changes(window, settings), Display_Changes{enter_borderless = true, vsync = true, change_frame_rate = true, frame_rate_cap = 60})
	testing.expect(t, .VSYNC_HINT in window_config_flags(window))
	settings.vsync = false
	settings.resolution = {1600, 900}
	window = initial_window_settings(settings)
	testing.expect_value(t, window.resolution, [2]int{1600, 900})
	testing.expect(t, .VSYNC_HINT not_in window_config_flags(window))
	testing.expect(t, .WINDOW_RESIZABLE in window_config_flags(window))
}

@(test)
test_resolution_choices_follow_the_monitor :: proc(t: ^testing.T) {
	choices := resolution_choices({1920, 1080}, context.temp_allocator)
	expected := [?][2]int{NATIVE_RESOLUTION, {1280, 720}, {1280, 800}, {1600, 900}, {1920, 1080}}
	testing.expect_value(t, len(choices), len(expected))
	for choice, index in expected {
		if index < len(choices) {
			testing.expect_value(t, choices[index], choice)
		}
	}
	// A 16:10 monitor keeps 1920 by 1200 and drops 2560 by 1440.
	deck := resolution_choices({1280, 800}, context.temp_allocator)
	testing.expect_value(t, len(deck), 3)
	testing.expect_value(t, len(resolution_choices(NATIVE_RESOLUTION, context.temp_allocator)), len(RESOLUTION_CHOICES) + 1)
	testing.expect_value(t, len(resolution_choices({800, 600}, context.temp_allocator)), 1)

	testing.expect_value(t, next_resolution(NATIVE_RESOLUTION, choices), [2]int{1280, 720})
	testing.expect_value(t, next_resolution({1920, 1080}, choices), NATIVE_RESOLUTION)
	// A configured size not in the list steps to Native.
	testing.expect_value(t, next_resolution({1366, 768}, choices), NATIVE_RESOLUTION)
	testing.expect_value(t, resolved_resolution(NATIVE_RESOLUTION, {2560, 1440}), [2]int{2560, 1440})
	testing.expect_value(t, resolved_resolution({1280, 720}, {2560, 1440}), [2]int{1280, 720})
}

@(test)
test_frame_rate_cap_and_window_mode_steps :: proc(t: ^testing.T) {
	testing.expect_value(t, next_frame_rate_cap(0), 30)
	testing.expect_value(t, next_frame_rate_cap(144), 165)
	testing.expect_value(t, next_frame_rate_cap(240), 0)
	testing.expect_value(t, next_frame_rate_cap(100), 120)
	testing.expect_value(t, next_frame_rate_cap(480), 0)
	testing.expect_value(t, next_window_mode(.Windowed), Window_Mode.Borderless)
	testing.expect_value(t, next_window_mode(.Borderless), Window_Mode.Fullscreen)
	testing.expect_value(t, next_window_mode(.Fullscreen), Window_Mode.Windowed)
}

@(test)
test_centred_window_position :: proc(t: ^testing.T) {
	testing.expect_value(t, centred_window_position({1920, 0}, {2560, 1440}, {1280, 720}), [2]int{2560, 360})
	// Larger than the monitor: its top left corner.
	testing.expect_value(t, centred_window_position({0, 0}, {1280, 800}, {1920, 1080}), [2]int{0, 0})
}

@(test)
test_display_diagnostics_text :: proc(t: ^testing.T) {
	scaled := display_diagnostics_text({1694, 1129}, {1694, 1129}, {1694, 1129}, {1, 1}, true)
	testing.expect_value(t, scaled, "display: monitor 1694 x 1129, window 1694 x 1129, render 1694 x 1129, scale 1.00 x 1.00, session xwayland")
	x11 := display_diagnostics_text({2880, 1920}, {1280, 720}, {2176, 1224}, {1.7, 1.7}, false)
	testing.expect_value(t, x11, "display: monitor 2880 x 1920, window 1280 x 720, render 2176 x 1224, scale 1.70 x 1.70, session x11")
}

@(test)
test_display_is_desktop_scaled :: proc(t: ^testing.T) {
	testing.expect(t, !display_is_desktop_scaled({1, 1}, false))
	testing.expect(t, display_is_desktop_scaled({1, 1}, true))
	testing.expect(t, display_is_desktop_scaled({1.7, 1.7}, false))
	testing.expect(t, display_is_desktop_scaled({1, 1.25}, false))
}
