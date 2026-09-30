package game

import "core:testing"

TEST_SCREEN_PIXELS :: [2]f32{1920, 1080}

test_ui_frame :: proc(state: ^Ui_State, input: Ui_Input, seconds: f32 = 1.0 / 60) {
	ui_begin(state, input, TEST_SCREEN_PIXELS, seconds, 1, 1)
}

test_widget :: proc(id: Ui_Id, x, y: f32, panel: Ui_Id = 1) -> Ui_Widget {
	return Ui_Widget{id = id, panel = panel, rectangle = {x, y, 100, 40}}
}

@(test)
test_focus_moves_to_nearest_in_direction :: proc(t: ^testing.T) {
	widgets := [?]Ui_Widget {
		test_widget(1, 0, 0),
		test_widget(2, 200, 0),
		test_widget(3, 400, 0),
		test_widget(4, 0, 100),
		test_widget(5, 200, 100),
	}
	index, found := find_focus_neighbour(widgets[:], 0, .Right)
	testing.expect(t, found)
	testing.expect_value(t, widgets[index].id, 2)
	index, found = find_focus_neighbour(widgets[:], 0, .Down)
	testing.expect_value(t, widgets[index].id, 4)
	index, found = find_focus_neighbour(widgets[:], 4, .Up)
	testing.expect_value(t, widgets[index].id, 2)
}

@(test)
test_focus_penalises_sideways_offset :: proc(t: ^testing.T) {
	// Straight ahead at 300 beats one at 120 ahead but 100 to the side.
	widgets := [?]Ui_Widget{test_widget(1, 0, 0), test_widget(2, 300, 0), test_widget(3, 120, 100)}
	index, found := find_focus_neighbour(widgets[:], 0, .Right)
	testing.expect(t, found)
	testing.expect_value(t, widgets[index].id, 2)
}

@(test)
test_focus_wraps_inside_the_panel :: proc(t: ^testing.T) {
	widgets := [?]Ui_Widget {
		test_widget(1, 0, 0),
		test_widget(2, 0, 100),
		test_widget(3, 0, 200),
		// Another panel above everything must not catch the wrap.
		test_widget(9, 0, -300, 2),
	}
	index, found := find_focus_neighbour(widgets[:], 2, .Down)
	testing.expect(t, found)
	testing.expect_value(t, widgets[index].id, 1)
	index, found = find_focus_neighbour(widgets[:], 0, .Up)
	testing.expect_value(t, widgets[index].id, 3)
}

// The id of the widget a step lands on, 0 for none.
focus_step :: proc(widgets: []Ui_Widget, from_id: Ui_Id, direction: Ui_Direction) -> Ui_Id {
	index, found := find_focus_neighbour(widgets, widget_index(widgets, from_id), direction)
	return found ? widgets[index].id : 0
}

// A row of count columns across width at y, ids from first_id.
append_focus_row :: proc(widgets: ^[dynamic]Ui_Widget, first_id: Ui_Id, count: int, y: f32) {
	row := Ui_Rectangle{0, y, 960, UI_ROW_HEIGHT}
	for index in 0 ..< count {
		append(widgets, Ui_Widget{id = first_id + Ui_Id(index), panel = 1, rectangle = column(row, count, index, UI_GAP)})
	}
}

// The Developer screen's toggles (couch report 2026-09-28): fly mode and
// cheat speed on a row of two over a row of three. Right from fly mode
// went to the middle of the row below, whose centre is nearer.
@(test)
test_focus_stays_in_the_developer_rows :: proc(t: ^testing.T) {
	widgets: [dynamic]Ui_Widget
	defer delete(widgets)
	append_focus_row(&widgets, 1, 2, 0)
	append_focus_row(&widgets, 11, 3, UI_ROW_HEIGHT + UI_GAP)
	testing.expect_value(t, focus_step(widgets[:], 1, .Right), 2)
	testing.expect_value(t, focus_step(widgets[:], 2, .Left), 1)
	testing.expect_value(t, focus_step(widgets[:], 1, .Down), 11)
	testing.expect_value(t, focus_step(widgets[:], 11, .Right), 12)
	testing.expect_value(t, focus_step(widgets[:], 12, .Up), 1)
	// The last of a row wraps to the first of its row, as before.
	testing.expect_value(t, focus_step(widgets[:], 13, .Right), 11)
}

// Two rows of three buttons with a gap: rows and columns.
@(test)
test_focus_follows_two_rows_of_three :: proc(t: ^testing.T) {
	widgets: [dynamic]Ui_Widget
	defer delete(widgets)
	append_focus_row(&widgets, 1, 3, 0)
	append_focus_row(&widgets, 11, 3, UI_ROW_HEIGHT + UI_GAP)
	testing.expect_value(t, focus_step(widgets[:], 1, .Right), 2)
	testing.expect_value(t, focus_step(widgets[:], 2, .Right), 3)
	testing.expect_value(t, focus_step(widgets[:], 1, .Down), 11)
	testing.expect_value(t, focus_step(widgets[:], 2, .Down), 12)
	testing.expect_value(t, focus_step(widgets[:], 13, .Up), 3)
	testing.expect_value(t, focus_step(widgets[:], 3, .Right), 1)
}

// A settings column of full width rows steps row by row and wraps.
@(test)
test_focus_walks_a_column_of_full_rows :: proc(t: ^testing.T) {
	widgets: [dynamic]Ui_Widget
	defer delete(widgets)
	for index in 0 ..< 4 {
		append_focus_row(&widgets, Ui_Id(index + 1), 1, f32(index) * (UI_ROW_HEIGHT + UI_GAP))
	}
	testing.expect_value(t, focus_step(widgets[:], 1, .Down), 2)
	testing.expect_value(t, focus_step(widgets[:], 3, .Up), 2)
	testing.expect_value(t, focus_step(widgets[:], 4, .Down), 1)
}

// A grid of slots, 4 by 3, ids row * 10 + column.
@(test)
test_focus_walks_a_grid_of_slots :: proc(t: ^testing.T) {
	widgets: [dynamic]Ui_Widget
	defer delete(widgets)
	for row in 0 ..< 3 {
		for column_index in 0 ..< 4 {
			rectangle := Ui_Rectangle{f32(column_index) * 68, f32(row) * 68, 64, 64}
			append(&widgets, Ui_Widget{id = Ui_Id(row * 10 + column_index + 1), panel = 1, rectangle = rectangle})
		}
	}
	testing.expect_value(t, focus_step(widgets[:], 1, .Right), 2)
	testing.expect_value(t, focus_step(widgets[:], 2, .Down), 12)
	testing.expect_value(t, focus_step(widgets[:], 23, .Up), 13)
	testing.expect_value(t, focus_step(widgets[:], 14, .Left), 13)
	testing.expect_value(t, focus_step(widgets[:], 4, .Right), 1)
}

// A taller neighbour whose centre sits off the focused widget's row
// still counts as the row.
@(test)
test_focus_reaches_a_taller_neighbour_in_the_row :: proc(t: ^testing.T) {
	widgets := [?]Ui_Widget {
		{id = 1, panel = 1, rectangle = {0, 0, 100, 40}},
		{id = 2, panel = 1, rectangle = {300, 20, 100, 200}},
		// Nearer, but below the row.
		{id = 3, panel = 1, rectangle = {150, 60, 100, 40}},
	}
	testing.expect_value(t, focus_step(widgets[:], 1, .Right), 2)
}

// Nothing in the widget's column below: the weighted score picks the
// nearest widget below.
@(test)
test_focus_without_a_line_falls_back_to_the_nearest :: proc(t: ^testing.T) {
	widgets := [?]Ui_Widget{test_widget(1, 0, 0), test_widget(2, 500, 100), test_widget(3, 150, 100)}
	testing.expect_value(t, focus_step(widgets[:], 1, .Down), 3)
}

@(test)
test_focus_without_candidate_stays :: proc(t: ^testing.T) {
	widgets := [?]Ui_Widget{test_widget(1, 0, 0), test_widget(2, 200, 0, 2)}
	_, found := find_focus_neighbour(widgets[:], 0, .Right)
	testing.expect(t, !found)
	state: Ui_State
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {navigation = .Right})
	append(&state.widgets, widgets[0])
	state.focus = 1
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 1)
}

@(test)
test_resolve_steps_focus_and_falls_back :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	// No focus yet: the first widget takes it.
	test_ui_frame(&state, {})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 1)
	test_ui_frame(&state, {navigation = .Down})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 2)
	// Held: no second step before the repeat delay.
	test_ui_frame(&state, {navigation = .Down})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 2)
}

@(test)
test_slider_keeps_horizontal_steps :: proc(t: ^testing.T) {
	widgets := [?]Ui_Widget{test_widget(1, 0, 0), test_widget(2, 200, 0)}
	widgets[0].flags = {.Adjusts_Horizontally}
	testing.expect(t, !focus_step_allowed(widgets[0], .Right))
	testing.expect(t, focus_step_allowed(widgets[0], .Down))
	testing.expect(t, focus_step_allowed(widgets[1], .Left))
	testing.expect(t, !focus_step_allowed(widgets[1], .None))
}

@(test)
test_ui_unit_scaling :: proc(t: ^testing.T) {
	testing.expect_value(t, ui_pixels_per_unit(1080, 1), 1)
	testing.expect_value(t, ui_pixels_per_unit(2160, 1), 2)
	testing.expect(t, abs(ui_pixels_per_unit(720, 1) - 2.0 / 3) < TEST_TOLERANCE)
	testing.expect_value(t, ui_pixels_per_unit(1080, 1.5), 1.5)
	// A larger UI scale leaves fewer units on screen.
	testing.expect_value(t, ui_screen_units({1920, 1080}, 1), [2]f32{1920, 1080})
	testing.expect_value(t, ui_screen_units({1920, 1080}, 1.5), [2]f32{1280, 720})
	state: Ui_State
	defer destroy_ui_state(&state)
	ui_begin(&state, {}, {1280, 720}, 0, 1, 1)
	testing.expect(t, abs(state.screen_units.y - UI_UNITS_PER_SCREEN_HEIGHT) < TEST_TOLERANCE)
	safe := ui_safe_area(&state)
	testing.expect(t, abs(safe.y - 54) < TEST_TOLERANCE)
	testing.expect(t, abs(safe.height - 972) < TEST_TOLERANCE)
}

@(test)
test_stick_repeat_timing :: proc(t: ^testing.T) {
	repeat: Repeat_State
	step: bool
	repeat, step = advance_repeat(repeat, .Down, 0.016)
	testing.expect(t, step)
	repeat, step = advance_repeat(repeat, .Down, 0.3)
	testing.expect(t, !step)
	repeat, step = advance_repeat(repeat, .Down, 0.06)
	testing.expect(t, step)
	repeat, step = advance_repeat(repeat, .Down, 0.05)
	testing.expect(t, !step)
	repeat, step = advance_repeat(repeat, .Down, 0.04)
	testing.expect(t, step)
	// A new direction steps at once and restarts the delay.
	repeat, step = advance_repeat(repeat, .Left, 0.016)
	testing.expect(t, step)
	repeat, step = advance_repeat(repeat, .Left, 0.2)
	testing.expect(t, !step)
	repeat, step = advance_repeat(repeat, .None, 0.016)
	testing.expect(t, !step)
	testing.expect_value(t, repeat, Repeat_State{})
}

@(test)
test_ui_ids_are_stable_and_scoped :: proc(t: ^testing.T) {
	state: Ui_State
	first := ui_id(&state, "resume")
	testing.expect_value(t, ui_id(&state, "resume"), first)
	testing.expect(t, ui_id(&state, "quit") != first)
	testing.expect(t, ui_id(&state, "item", 0) != ui_id(&state, "item", 1))
	ui_push_id(&state, "list_a")
	in_a := ui_id(&state, "item", 0)
	ui_pop_id(&state)
	ui_push_id(&state, "list_b")
	in_b := ui_id(&state, "item", 0)
	ui_pop_id(&state)
	testing.expect(t, in_a != in_b)
	testing.expect_value(t, state.id_depth, 0)
}

@(test)
test_button_activates_by_confirm_and_click :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	button := Ui_Rectangle{100, 100, 200, 50}
	test_ui_frame(&state, {})
	testing.expect(t, !ui_button(&state, button, "resume"))
	ui_resolve(&state)
	testing.expect_value(t, state.focus, ui_id(&state, "resume"))
	test_ui_frame(&state, {confirm = true})
	testing.expect(t, ui_button(&state, button, "resume"))
	ui_resolve(&state)
	// A tap hits by position, with no focus needed, on the release (0132).
	other := Ui_Rectangle{100, 300, 200, 50}
	test_ui_frame(&state, {mouse_position = {150, 320}, mouse_moved = true, mouse_pressed = true, mouse_down = true})
	testing.expect(t, !ui_button(&state, button, "resume"))
	testing.expect(t, !ui_button(&state, other, "quit"))
	ui_resolve(&state)
	testing.expect_value(t, state.focus, ui_id(&state, "quit"))
	test_ui_frame(&state, {mouse_position = {150, 320}})
	testing.expect(t, !ui_button(&state, button, "resume"))
	testing.expect(t, ui_button(&state, other, "quit"))
	ui_resolve(&state)
}

@(test)
test_trackpad_moves_pointer_and_hover_sets_focus :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	target := Ui_Rectangle{500, 500, 200, 100}
	// Pointer speed 1: a whole pad width crosses one screen height.
	test_ui_frame(&state, {trackpad_delta = {0.5, 0.5}})
	ui_button(&state, {0, 0, 100, 40}, "first")
	ui_button(&state, target, "target")
	ui_resolve(&state)
	testing.expect_value(t, state.pointer_source, Pointer_Source.Trackpad)
	testing.expect(t, abs(state.pointer.x - 540) < TEST_TOLERANCE)
	testing.expect_value(t, state.focus, ui_id(&state, "target"))
	// A d-pad step hides the pointer and a pad click then confirms the focus.
	test_ui_frame(&state, {navigation = .Up})
	testing.expect_value(t, state.pointer_source, Pointer_Source.None)
	test_ui_frame(&state, {pad_pressed = true, pad_down = true})
	testing.expect(t, state.confirm)
	testing.expect(t, !state.click)
}

@(test)
test_slider_steps_and_drags :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	row := Ui_Rectangle{0, 0, 1000, 56}
	value := f32(1)
	test_ui_frame(&state, {})
	ui_slider(&state, row, "scale", &value, UI_SCALE_RANGE, "")
	ui_resolve(&state)
	test_ui_frame(&state, {navigation = .Right})
	testing.expect(t, ui_slider(&state, row, "scale", &value, UI_SCALE_RANGE, ""))
	testing.expect(t, abs(value - 1.05) < TEST_TOLERANCE)
	ui_resolve(&state)
	testing.expect_value(t, state.focus, ui_id(&state, "scale"))
	// A tap at the far right of the track sets the maximum, on the release
	// (0132).
	far_right := [2]f32{990 - UI_BODY_TEXT_SIZE * 4 - 2 * UI_PADDING, 28}
	test_ui_frame(&state, {mouse_position = far_right, mouse_moved = true, mouse_pressed = true, mouse_down = true})
	ui_slider(&state, row, "scale", &value, UI_SCALE_RANGE, "")
	testing.expect(t, abs(value - 1.05) < TEST_TOLERANCE)
	ui_resolve(&state)
	test_ui_frame(&state, {mouse_position = far_right})
	ui_slider(&state, row, "scale", &value, UI_SCALE_RANGE, "")
	testing.expect(t, abs(value - UI_SCALE_RANGE.maximum) < TEST_TOLERANCE)
}

@(test)
test_tabs_follow_bumpers :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	labels := [?]string{"a", "b", "c"}
	strip := Ui_Rectangle{0, 0, 600, 56}
	test_ui_frame(&state, {tab_previous = true})
	testing.expect_value(t, ui_tabs(&state, strip, "tabs", labels[:]), 2)
	test_ui_frame(&state, {tab_next = true})
	testing.expect_value(t, ui_tabs(&state, strip, "tabs", labels[:]), 0)
	test_ui_frame(&state, {})
	testing.expect_value(t, ui_tabs(&state, strip, "tabs", labels[:]), 0)
}

@(test)
test_list_scrolls_the_focus_into_view :: proc(t: ^testing.T) {
	items := [?]string{"Coal", "copper ore", "Iron ore", "Limestone"}
	state: Ui_State
	defer destroy_ui_state(&state)
	area := Ui_Rectangle{0, 0, 400, UI_ROW_HEIGHT * 2}
	test_ui_frame(&state, {})
	ui_list(&state, area, "ores", items[:])
	ui_resolve(&state)
	ui_push_id(&state, "ores")
	state.requested_focus = ui_id(&state, "item", 3)
	ui_pop_id(&state)
	test_ui_frame(&state, {})
	ui_list(&state, area, "ores", items[:])
	ui_resolve(&state)
	ui_push_id(&state, "ores")
	testing.expect_value(t, state.focus, ui_id(&state, "item", 3))
	ui_pop_id(&state)
	// The next frame scrolls the focused row into view.
	test_ui_frame(&state, {})
	ui_list(&state, area, "ores", items[:])
	testing.expect_value(t, state.scroll_offsets[ui_id(&state, "ores")], UI_ROW_HEIGHT * 2)
}

@(test)
test_radial_selects_and_cancels :: proc(t: ^testing.T) {
	// A four slot wheel: up, right, down, left.
	step :: proc(state: ^Ui_State, source: Radial_Source) -> Radial_Result {
		touching, position := radial_input(state.input, source)
		result: Radial_Result
		state.radial, result = advance_radial(state.radial, touching, position, source, 4)
		return result
	}
	state: Ui_State
	defer destroy_ui_state(&state)
	// Touch at the top, slide right, release: the right slot.
	test_ui_frame(&state, {left_touchpad = {down = true, position = {0.5, 0.1}}})
	result := step(&state, .Touchpad)
	testing.expect(t, !result.closed)
	testing.expect_value(t, state.radial.highlight, 0)
	test_ui_frame(&state, {left_touchpad = {down = true, position = {0.9, 0.5}}})
	step(&state, .Touchpad)
	test_ui_frame(&state, {left_touchpad = {down = false, position = {0.9, 0.5}}})
	result = step(&state, .Touchpad)
	testing.expect(t, result.closed)
	testing.expect_value(t, result.selected, 1)
	testing.expect(t, !state.radial.open)
	// Sliding back to the dead centre and releasing cancels.
	test_ui_frame(&state, {left_touchpad = {down = true, position = {0.5, 0.9}}})
	step(&state, .Touchpad)
	test_ui_frame(&state, {left_touchpad = {down = true, position = {0.5, 0.5}}})
	step(&state, .Touchpad)
	test_ui_frame(&state, {})
	result = step(&state, .Touchpad)
	testing.expect(t, result.closed)
	testing.expect_value(t, result.selected, -1)
	// Stick: letting go keeps the last highlight.
	test_ui_frame(&state, {right_stick = {0, -1}})
	step(&state, .Stick)
	test_ui_frame(&state, {})
	result = step(&state, .Stick)
	testing.expect(t, result.closed)
	testing.expect_value(t, result.selected, 2)
	// Nothing touched: nothing happens.
	test_ui_frame(&state, {})
	result = step(&state, .Touchpad)
	testing.expect(t, !result.closed)
}

@(test)
test_toasts_expire_and_cap :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	for index in 0 ..< UI_TOAST_CAPACITY + 1 {
		ui_toast(&state, index == 0 ? "first" : "later")
	}
	testing.expect_value(t, len(state.toasts), UI_TOAST_CAPACITY)
	testing.expect_value(t, state.toasts[0].text, "later")
	test_ui_frame(&state, {}, UI_TOAST_SECONDS + 0.1)
	testing.expect_value(t, len(state.toasts), 0)
}

@(test)
test_screen_stack_and_back :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {pause = true})
	handle_screen_keys(&state)
	testing.expect_value(t, top_screen(state.screens), Screen.Pause)
	testing.expect(t, ui_pauses_simulation(state.screens))
	push_screen(&state.screens, .Settings)
	// Back first closes an open tooltip, then pops.
	state.tooltip_open = true
	test_ui_frame(&state, {back = true})
	handle_screen_keys(&state)
	testing.expect_value(t, top_screen(state.screens), Screen.Settings)
	test_ui_frame(&state, {back = true})
	handle_screen_keys(&state)
	testing.expect_value(t, top_screen(state.screens), Screen.Pause)
	test_ui_frame(&state, {pause = true})
	handle_screen_keys(&state)
	testing.expect_value(t, top_screen(state.screens), Screen.None)
	testing.expect(t, !ui_blocks_world(state.screens))
}

@(test)
test_navigation_direction :: proc(t: ^testing.T) {
	testing.expect_value(t, navigation_direction({.Navigate_Left}, {0, 1}), Ui_Direction.Left)
	testing.expect_value(t, navigation_direction({}, {0, 0.4}), Ui_Direction.None)
	testing.expect_value(t, navigation_direction({}, {0.2, 0.8}), Ui_Direction.Up)
	testing.expect_value(t, navigation_direction({}, {0.2, -0.8}), Ui_Direction.Down)
	testing.expect_value(t, navigation_direction({}, {0.9, 0.3}), Ui_Direction.Right)
}

@(test)
test_detect_input_device :: proc(t: ^testing.T) {
	idle := Raw_Input {
		gamepad = {connected = true, button_count = 4, axis_count = 6},
	}
	_, seen := detect_input_device(idle, idle)
	testing.expect(t, !seen)
	pressed := idle
	pressed.gamepad.button_down[0] = true
	device, _ := detect_input_device(idle, pressed)
	testing.expect_value(t, device, Input_Device.Gamepad)
	// A held button (grip sense) is not new input.
	_, seen = detect_input_device(pressed, pressed)
	testing.expect(t, !seen)
	typing := idle
	typing.keyboard.key_count = 1
	device, _ = detect_input_device(idle, typing)
	testing.expect_value(t, device, Input_Device.Keyboard_Mouse)
}

@(test)
test_preferred_focus_wins_the_fallback :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Inventory)
	test_ui_frame(&state, {})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_prefer_focus(&state, 2)
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 2)
	// A preference the frame does not show falls back to the first widget.
	state.focus = 99
	test_ui_frame(&state, {})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_prefer_focus(&state, 5)
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 1)
	// A focus among the widgets keeps it.
	state.focus = 1
	test_ui_frame(&state, {})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_prefer_focus(&state, 2)
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 1)
}

// Frames with an item slot like widget (1), a second one below it (2)
// and a plain widget with a tooltip (3) below that.
tooltip_test_frame :: proc(state: ^Ui_State, input: Ui_Input, seconds: f32) {
	test_ui_frame(state, input, seconds)
	ui_interact(state, 1, {0, 0, 80, 80}, {.Tooltip_Shows_Itself}, "first")
	ui_interact(state, 2, {0, 100, 80, 80}, {.Tooltip_Shows_Itself}, "second")
	ui_interact(state, 3, {0, 200, 80, 80}, {}, "plain")
}

focused_tooltip_shows :: proc(state: Ui_State) -> bool {
	index := widget_index(state.widgets[:], state.focus)
	return index >= 0 && tooltip_shows(state, state.widgets[index])
}

@(test)
test_item_tooltip_shows_itself_after_the_delay :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Inventory)
	tooltip_test_frame(&state, {}, 0.25)
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 1)
	tooltip_test_frame(&state, {}, 0.25)
	ui_resolve(&state)
	testing.expect(t, !focused_tooltip_shows(state))
	tooltip_test_frame(&state, {}, 0.25)
	ui_resolve(&state)
	testing.expect(t, !focused_tooltip_shows(state))
	tooltip_test_frame(&state, {}, 0.25)
	ui_resolve(&state)
	testing.expect(t, focused_tooltip_shows(state))
	testing.expect_value(t, state.focused_tooltip, "first")
	// A focus move hides it in the frame of the move, and it waits again.
	tooltip_test_frame(&state, {navigation = .Down}, 0.25)
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 2)
	testing.expect(t, !focused_tooltip_shows(state))
	tooltip_test_frame(&state, {}, 0.25)
	ui_resolve(&state)
	testing.expect(t, !focused_tooltip_shows(state))
	for _ in 0 ..< 2 {
		tooltip_test_frame(&state, {}, 0.25)
		ui_resolve(&state)
	}
	testing.expect(t, focused_tooltip_shows(state))
	testing.expect_value(t, state.focused_tooltip, "second")
	// A widget without the flag still needs the Info toggle.
	tooltip_test_frame(&state, {navigation = .Down}, 0.25)
	ui_resolve(&state)
	testing.expect_value(t, state.focus, 3)
	for _ in 0 ..< 4 {
		tooltip_test_frame(&state, {}, 0.25)
		ui_resolve(&state)
	}
	testing.expect(t, !focused_tooltip_shows(state))
	tooltip_test_frame(&state, {info = true}, 0.25)
	ui_resolve(&state)
	testing.expect(t, focused_tooltip_shows(state))
}

@(test)
test_focus_tabs_step_on_left_and_right :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Recipes)
	labels := [?]string{"a", "b", "c"}
	strip := Ui_Rectangle{0, 0, 600, 56}
	frame :: proc(state: ^Ui_State, input: Ui_Input, labels: []string, strip: Ui_Rectangle) -> int {
		test_ui_frame(state, input)
		selected := ui_tabs(state, strip, "tabs", labels, nil, .Focus)
		ui_interact(state, 2, {0, 100, 100, 40})
		ui_resolve(state)
		return selected
	}
	// Not focused yet: left and right do nothing to it.
	testing.expect_value(t, frame(&state, {navigation = .Right}, labels[:], strip), 0)
	tabs_id := ui_hash(0, "tabs", -1)
	testing.expect_value(t, state.focus, tabs_id)
	frame(&state, {}, labels[:], strip)
	testing.expect_value(t, frame(&state, {navigation = .Right}, labels[:], strip), 1)
	testing.expect_value(t, state.focus, tabs_id)
	frame(&state, {}, labels[:], strip)
	testing.expect_value(t, frame(&state, {navigation = .Left}, labels[:], strip), 0)
	frame(&state, {}, labels[:], strip)
	testing.expect_value(t, frame(&state, {navigation = .Left}, labels[:], strip), 2)
	// The bumpers are not the row's.
	testing.expect_value(t, frame(&state, {tab_next = true}, labels[:], strip), 2)
	testing.expect_value(t, frame(&state, {tab_previous = true}, labels[:], strip), 2)
	// Down leaves the row.
	frame(&state, {navigation = .Down}, labels[:], strip)
	testing.expect_value(t, state.focus, 2)
}

// Work item 0085: the UI lays out in render pixels. The laptop's panel
// under a 1.7 desktop scale on Wayland has a 1694 by 1129 window and a
// 2880 by 1920 framebuffer: the layout in units is the same, a unit is
// 1.7 times the pixels, so text rasterises at the panel's size, and the
// cursor mapped to render pixels lands on the same unit (within one, as
// the window's size is rounded to whole units of the desktop).
@(test)
test_ui_layout_in_render_pixels :: proc(t: ^testing.T) {
	window, render: Ui_State
	defer destroy_ui_state(&window)
	defer destroy_ui_state(&render)
	cursor := [2]f32{847, 564.5}
	ui_begin(&window, {mouse_position = cursor, mouse_moved = true}, {1694, 1129}, 0, 1, 1)
	ui_begin(&render, {mouse_position = pointer_to_render_pixels(cursor, {1694, 1129}, {2880, 1920}), mouse_moved = true}, {2880, 1920}, 0, 1, 1)
	testing.expect(t, abs(render.pixels_per_unit / window.pixels_per_unit - 1920.0 / 1129) < TEST_TOLERANCE)
	testing.expect(t, abs(render.screen_units.x - window.screen_units.x) < 1)
	testing.expect(t, abs(render.screen_units.y - UI_UNITS_PER_SCREEN_HEIGHT) < TEST_TOLERANCE)
	testing.expect(t, abs(render.pointer.x - window.pointer.x) < 1)
	testing.expect(t, abs(render.pointer.y - window.pointer.y) < 1)
}
