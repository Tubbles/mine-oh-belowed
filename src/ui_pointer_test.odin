package game

import "core:testing"

// Work item 0132: misclicks in the menus. The screen frames run at 1920
// by 1080 pixels and UI scale 1 (screen_test_frame), so a UI unit is a
// pixel, unless a test scales the UI (scaled_settings_frame).

pause_button_id :: proc(key: string) -> Ui_Id {
	return ui_hash(ui_hash(0, "pause", -1), text(key), -1)
}

settings_row_id :: proc(key: string) -> Ui_Id {
	return ui_hash(ui_hash(0, "settings", -1), text(key), -1)
}


// The pause menu open over the audit's site and drawn once, without
// developer requests.
open_pause_menu :: proc(audit: ^Ui_Audit, state: ^Ui_State) {
	clear(&audit.simulation.developer_requests)
	push_screen(&state.screens, .Pause)
	screen_test_frame(audit, state, {})
}

// Report 1 as the item describes it, driven headless: Confirm on the
// pause menu's Developer entry, held and released over the next frames,
// and a finger's tap on it. Neither toggles the first Developer row; the
// report's second edge did not come from these paths (the item's
// Implemented section).
@(test)
test_confirm_on_developer_toggles_nothing :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	open_pause_menu(audit, &state)
	state.requested_focus = pause_button_id("pause_developer")
	screen_test_frame(audit, &state, {device = .Gamepad, device_seen = true})
	testing.expect_value(t, state.focus, pause_button_id("pause_developer"))
	screen_test_frame(audit, &state, {confirm = true, confirm_down = true, device = .Gamepad, device_seen = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Developer)
	for _ in 0 ..< 5 {
		screen_test_frame(audit, &state, {confirm_down = true})
	}
	for _ in 0 ..< 5 {
		screen_test_frame(audit, &state, {})
	}
	testing.expect_value(t, top_screen(state.screens), Screen.Developer)
	testing.expect_value(t, len(audit.simulation.developer_requests), 0)
}

@(test)
test_tap_on_developer_toggles_nothing :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	open_pause_menu(audit, &state)
	at := widget_centre(state, pause_button_id("pause_developer"))
	screen_test_frame(audit, &state, touch_input(at, true, pressed = true))
	testing.expect_value(t, top_screen(state.screens), Screen.Pause)
	for _ in 0 ..< 5 {
		screen_test_frame(audit, &state, touch_input(at, true, moved = false))
	}
	screen_test_frame(audit, &state, touch_input(at, false, moved = false))
	testing.expect_value(t, top_screen(state.screens), Screen.Developer)
	for _ in 0 ..< 5 {
		screen_test_frame(audit, &state, touch_input(at, false, moved = false))
	}
	testing.expect_value(t, top_screen(state.screens), Screen.Developer)
	testing.expect_value(t, len(audit.simulation.developer_requests), 0)
}

// A press on a toggle flips it on the release over it, once, with the
// click sound on the release.
@(test)
test_a_tap_flips_a_toggle_once_on_the_release :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	row := Ui_Rectangle{100, 100, 400, 56}
	value := false
	at := rectangle_centre(row)
	test_ui_frame(&state, touch_input(at, true, pressed = true))
	testing.expect(t, !ui_toggle(&state, row, "vsync", &value))
	ui_resolve(&state)
	testing.expect(t, .Confirm not_in state.sound_events)
	test_ui_frame(&state, touch_input(at, true, moved = false))
	testing.expect(t, !ui_toggle(&state, row, "vsync", &value))
	ui_resolve(&state)
	test_ui_frame(&state, touch_input(at, false, moved = false))
	testing.expect(t, ui_toggle(&state, row, "vsync", &value))
	ui_resolve(&state)
	testing.expect(t, value)
	testing.expect(t, .Confirm in state.sound_events)
	test_ui_frame(&state, touch_input(at, false, moved = false))
	testing.expect(t, !ui_toggle(&state, row, "vsync", &value))
	testing.expect(t, value)
}

// A press on a toggle released off it flips nothing, and so does a press
// elsewhere released on it.
@(test)
test_a_press_released_elsewhere_flips_nothing :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	row := Ui_Rectangle{100, 100, 400, 56}
	other := Ui_Rectangle{100, 300, 400, 56}
	value, other_value := false, false
	frame :: proc(state: ^Ui_State, input: Ui_Input, row, other: Ui_Rectangle, value, other_value: ^bool) {
		test_ui_frame(state, input)
		ui_toggle(state, row, "vsync", value)
		ui_toggle(state, other, "weather", other_value)
		ui_resolve(state)
	}
	frame(&state, touch_input(rectangle_centre(row), true, pressed = true), row, other, &value, &other_value)
	frame(&state, touch_input(rectangle_centre(other), true), row, other, &value, &other_value)
	frame(&state, touch_input(rectangle_centre(other), false, moved = false), row, other, &value, &other_value)
	testing.expect(t, !value)
	testing.expect(t, !other_value)
	// Out and back within the same press is no tap either.
	frame(&state, touch_input(rectangle_centre(row), true, pressed = true), row, other, &value, &other_value)
	frame(&state, touch_input(rectangle_centre(row) + [2]f32{0, 100}, true), row, other, &value, &other_value)
	frame(&state, touch_input(rectangle_centre(row), true), row, other, &value, &other_value)
	frame(&state, touch_input(rectangle_centre(row), false, moved = false), row, other, &value, &other_value)
	testing.expect(t, !value)
}

// Report 2: a drag that starts on Vsync in the Display tab scrolls the
// tab by the finger's movement and flips nothing; the focus stays put
// while it scrolls and stays scrolled away after the release.
@(test)
test_a_drag_on_a_toggle_scrolls_the_region :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Pause)
	push_screen(&state.screens, .Settings)
	screen_test_frame(audit, &state, {})
	vsync := audit.settings.vsync
	region := ui_hash(ui_hash(0, "settings", -1), "display_settings", -1)
	testing.expect_value(t, state.scroll_offsets[region], 0)
	at := widget_centre(state, settings_row_id("settings_vsync"))
	screen_test_frame(audit, &state, touch_input(at, true, pressed = true))
	focus := state.focus
	// Within the slop: no scroll yet.
	screen_test_frame(audit, &state, touch_input(at - [2]f32{0, 10}, true))
	testing.expect_value(t, state.scroll_offsets[region], 0)
	screen_test_frame(audit, &state, touch_input(at - [2]f32{0, 100}, true))
	testing.expect_value(t, state.scroll_offsets[region], 100)
	screen_test_frame(audit, &state, touch_input(at - [2]f32{0, 150}, true))
	testing.expect_value(t, state.scroll_offsets[region], 150)
	testing.expect_value(t, state.focus, focus)
	screen_test_frame(audit, &state, touch_input(at - [2]f32{0, 150}, false, moved = false))
	screen_test_frame(audit, &state, touch_input(at - [2]f32{0, 150}, false, moved = false))
	testing.expect_value(t, audit.settings.vsync, vsync)
	testing.expect_value(t, state.scroll_offsets[region], 150)
	testing.expect_value(t, state.focus, focus)
	testing.expect_value(t, top_screen(state.screens), Screen.Settings)
}

// A frame of the screens at the audit's UI scale, which the UI scale
// slider changes.
scaled_settings_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State, input: Ui_Input) {
	ui_begin(state, input, {1920, 1080}, 1.0 / 60, audit.settings.ui_scale, 1, ui_accessibility(audit.settings))
	run_screens(state, audit_screen_context(audit))
	ui_resolve(state)
}

// The Settings screen over the pause menu at UI scale 1, drawn once, and
// where three quarters along the UI scale slider's track lie, in pixels.
open_ui_scale_slider :: proc(audit: ^Ui_Audit, state: ^Ui_State) -> [2]f32 {
	audit.settings.ui_scale = 1
	push_screen(&state.screens, .Pause)
	push_screen(&state.screens, .Settings)
	scaled_settings_frame(audit, state, {})
	row := state.widgets[widget_index(state.widgets[:], settings_row_id("settings_ui_scale"))].rectangle
	// slider_begin's layout.
	track_x := row.x + row.width * 0.45
	track_width := row.width * 0.55 - SLIDER_VALUE_WIDTH - 2 * UI_PADDING
	return [2]f32{track_x + track_width * 0.75, row.y + row.height / 2} * state.pixels_per_unit
}

// Report 3: a still press on the UI scale slider changes nothing while
// held and sets the value under it once, on the release.
@(test)
test_a_still_press_on_the_ui_scale_slider_sets_it_once :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	at := open_ui_scale_slider(audit, &state)
	scaled_settings_frame(audit, &state, touch_input(at, true, pressed = true))
	for _ in 0 ..< 10 {
		scaled_settings_frame(audit, &state, touch_input(at, true, moved = false))
	}
	testing.expect_value(t, audit.settings.ui_scale, 1)
	scaled_settings_frame(audit, &state, touch_input(at, false, moved = false))
	tapped := audit.settings.ui_scale
	testing.expect(t, tapped > 1)
	for _ in 0 ..< 10 {
		scaled_settings_frame(audit, &state, touch_input(at, false, moved = false))
	}
	testing.expect_value(t, audit.settings.ui_scale, tapped)
}

// A drag along the UI scale track: the shown value follows the finger and
// never falls while it moves right, the layout holds until the release,
// which applies the dragged value.
@(test)
test_a_drag_on_the_ui_scale_slider_applies_on_the_release :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	at := open_ui_scale_slider(audit, &state)
	scaled_settings_frame(audit, &state, touch_input(at, true, pressed = true))
	shown := f32(0)
	for step in 1 ..= 40 {
		scaled_settings_frame(audit, &state, touch_input(at + [2]f32{f32(step), 0}, true))
		testing.expect_value(t, audit.settings.ui_scale, 1)
		testing.expect_value(t, state.pixels_per_unit, 1)
		if state.dragging != 0 {
			testing.expect(t, state.slider_drag_value >= shown)
			shown = state.slider_drag_value
		}
	}
	testing.expect(t, shown > 1)
	scaled_settings_frame(audit, &state, touch_input(at + [2]f32{40, 0}, false, moved = false))
	testing.expect_value(t, audit.settings.ui_scale, shown)
}

// A vertical drag that starts on the UI scale track scrolls the Display
// tab and leaves the scale as it was.
@(test)
test_a_vertical_drag_on_a_slider_scrolls :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	at := open_ui_scale_slider(audit, &state)
	region := ui_hash(ui_hash(0, "settings", -1), "display_settings", -1)
	scaled_settings_frame(audit, &state, touch_input(at, true, pressed = true))
	scaled_settings_frame(audit, &state, touch_input(at - [2]f32{5, 60}, true))
	scaled_settings_frame(audit, &state, touch_input(at - [2]f32{10, 100}, true))
	testing.expect_value(t, state.scroll_offsets[region], 100)
	scaled_settings_frame(audit, &state, touch_input(at - [2]f32{10, 100}, false, moved = false))
	testing.expect_value(t, audit.settings.ui_scale, 1)
	testing.expect_value(t, state.scroll_offsets[region], 100)
}

// Finger scrolling reaches the Scroll_List screens: the recipe list.
@(test)
test_a_drag_scrolls_the_recipe_list :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	audit.browser.filter.available_only = false
	push_screen(&state.screens, .Recipes)
	screen_test_frame(audit, &state, {})
	list := ui_hash(ui_hash(0, "recipes", -1), "recipe_list", -1)
	// The topmost row on screen (the list sorts by name and may open
	// scrolled to the focused recipe).
	at := [2]f32{0, max(f32)}
	for recipe in 0 ..< len(audit.content.recipes.recipes) {
		if index := widget_index(state.widgets[:], recipe_row_id(list, recipe)); index >= 0 {
			centre := rectangle_centre(state.widgets[index].rectangle)
			if centre.y > 0 && centre.y < at.y {
				at = centre
			}
		}
	}
	testing.expect(t, at.y < 1080)
	before := state.scroll_offsets[list]
	// Down the list when it can scroll back, else up.
	finger := before >= 100 ? f32(100) : f32(-100)
	screen_test_frame(audit, &state, touch_input(at, true, pressed = true))
	focus := state.focus
	screen_test_frame(audit, &state, touch_input(at + [2]f32{0, finger}, true))
	screen_test_frame(audit, &state, touch_input(at + [2]f32{0, finger}, false, moved = false))
	testing.expect_value(t, state.scroll_offsets[list], before - finger)
	testing.expect_value(t, state.focus, focus)
	testing.expect_value(t, top_screen(state.screens), Screen.Recipes)
}

// After a scroll drag took the focused slider out of view, a Left or
// Right step on it, which keeps the focus, brings it back; so does a
// focus request.
@(test)
test_a_step_brings_a_scrolled_away_focus_back :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	values: [10]f32
	area := Ui_Rectangle{0, 0, 600, 200}
	frame :: proc(state: ^Ui_State, input: Ui_Input, area: Ui_Rectangle, values: ^[10]f32) {
		test_ui_frame(state, input)
		region, content := scroll_region_begin(state, "rows", area, 10 * 64)
		for &value, index in values {
			ui_push_id(state, "row", index)
			ui_slider(state, {content.x, content.y + f32(index) * 64, 600, 56}, "value", &value, UI_SCALE_RANGE, "")
			ui_pop_id(state)
		}
		scroll_region_end(state, region)
		ui_resolve(state)
	}
	frame(&state, {}, area, &values)
	focus := state.focus
	region := ui_id(&state, "rows")
	// Pressed on a label, left of the track, so the drag scrolls.
	frame(&state, touch_input({50, 150}, true, pressed = true, moved = false), area, &values)
	frame(&state, touch_input({50, 50}, true), area, &values)
	frame(&state, touch_input({50, 50}, false, moved = false), area, &values)
	frame(&state, {}, area, &values)
	testing.expect_value(t, state.scroll_offsets[region], 100)
	testing.expect_value(t, state.focus, focus)
	frame(&state, {navigation = .Right}, area, &values)
	testing.expect_value(t, state.focus, focus)
	testing.expect_value(t, state.scroll_offsets[region], 0)
	state.focus_scrolled_away = true
	state.requested_focus = focus
	ui_resolve(&state)
	testing.expect(t, !state.focus_scrolled_away)
}

// The pointer's unit position follows a UI scale change when the mouse
// does not move.
@(test)
test_the_pointer_follows_a_ui_scale_change :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {mouse_position = {600, 300}, mouse_moved = true})
	testing.expect_value(t, state.pointer, [2]f32{600, 300})
	ui_begin(&state, {mouse_position = {600, 300}}, TEST_SCREEN_PIXELS, 1.0 / 60, 1.5, 1)
	testing.expect_value(t, state.pointer, [2]f32{400, 200})
	testing.expect(t, !state.pointer_moved)
}

// A stepper steps on the tap, by the half it was tapped on.
@(test)
test_a_stepper_steps_on_the_tap :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	row := Ui_Rectangle{0, 0, 400, 56}
	left := [2]f32{50, 28}
	test_ui_frame(&state, pointer_input(left, true, pressed = true))
	testing.expect_value(t, ui_stepper(&state, row, "seed", "1"), Ui_Direction.None)
	test_ui_frame(&state, pointer_input(left, false, moved = false))
	testing.expect_value(t, ui_stepper(&state, row, "seed", "1"), Ui_Direction.Left)
}
