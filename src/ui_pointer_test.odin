package game

import "core:strings"
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
// queued commands.
open_pause_menu :: proc(audit: ^Ui_Audit, state: ^Ui_State) {
	clear(&audit.simulation.player_commands)
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
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
}

// The free crafting toggle (0234) is reached by focus and queues its
// request with the toast the other developer toggles show.
@(test)
test_the_free_crafting_toggle_queues_its_request :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	open_pause_menu(audit, &state)
	push_screen(&state.screens, .Developer)
	screen_test_frame(audit, &state, {})
	toggle := ui_hash(ui_hash(0, "developer", -1), text("developer_free_crafting"), -1)
	state.requested_focus = toggle
	screen_test_frame(audit, &state, {device = .Gamepad, device_seen = true})
	testing.expect_value(t, state.focus, toggle)
	screen_test_frame(audit, &state, {confirm = true, confirm_down = true, device = .Gamepad, device_seen = true})
	if !testing.expect_value(t, len(audit.simulation.player_commands), 1) {
		return
	}
	request, is_request := audit.simulation.player_commands[0].command.(Developer_Request)
	testing.expect(t, is_request)
	testing.expect_value(t, request.action, Developer_Action.Toggle_Free_Crafting)
	if testing.expect(t, len(state.toasts) > 0) {
		testing.expect_value(t, state.toasts[len(state.toasts) - 1].text, text("developer_applies_on_resume"))
	}
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
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
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
	audit.views.recipe_browser.filter.available_only = false
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

// Work item 0137: the touch row on every screen.

touch_screen_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State) {
	screen_test_frame(audit, state, {pointer_is_touch = true})
}

// A finger's press and release at a point, off every widget.
tap_screen_at :: proc(audit: ^Ui_Audit, state: ^Ui_State, at: [2]f32) {
	screen_test_frame(audit, state, touch_input(at, true, pressed = true))
	screen_test_frame(audit, state, touch_input(at, false, moved = false))
}

Touch_Row_Case :: struct {
	screens:   []Screen,
	machine:   bool,
	selecting: bool,
}

// On touch no screen draws glyphs, every screen with a panel draws Back,
// and Back pops the top screen as B does, with B's sound; the pause
// menu's pop resumes. A tap off the panels, left of the safe area, pops
// it too.
@(test)
test_every_screen_has_a_back_button_on_touch :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	assembler := NO_ENTITY
	for &entry in simulation.world.entities.assemblers.entries {
		if entry.alive && audit.content.machines.machines[entry.machine].recipe_choice != .Fixed {
			assembler = entry.handle
			break
		}
	}
	testing.expect(t, assembler != NO_ENTITY)
	cases := [?]Touch_Row_Case {
		{screens = {.Pause}},
		{screens = {.Pause, .Settings}},
		{screens = {.Pause, .Developer}},
		{screens = {.Pause, .Developer, .Textures}},
		{screens = {.Pause, .Developer, .Data_Files}},
		{screens = {.Inventory}},
		{screens = {.Machine}, machine = true},
		{screens = {.Recipes}},
		{screens = {.Machine, .Recipes}, machine = true, selecting = true},
		{screens = {.Technologies}},
		{screens = {.Journal}},
		{screens = {.Power}},
		{screens = {.Statistics}},
		{screens = {.Map}},
		{screens = {.Title, .Settings}},
		{screens = {.Title, .New_World}},
		{screens = {.Title, .Load_World}},
		{screens = {.Title, .Load_World, .Confirm_Delete}},
	}
	for touch_case in cases {
		state := Ui_State{theme = audit.theme}
		simulation.players[0].open_machine = touch_case.machine ? assembler : NO_ENTITY
		audit.views.recipe_browser.selecting_for = touch_case.selecting ? assembler : NO_ENTITY
		for screen in touch_case.screens {
			push_screen(&state.screens, screen)
		}
		touch_screen_frame(audit, &state)
		touch_screen_frame(audit, &state)
		top := top_screen(state.screens)
		testing.expectf(t, !glyph_bar_draws_glyphs(state.draw_list[:]), "%v draws glyphs on touch", top)
		back := slot_button_id("touch_button_back")
		if !testing.expectf(t, widget_index(state.widgets[:], back) >= 0, "%v has no Back", top) {
			destroy_ui_state(&state)
			continue
		}
		count := state.screens.count
		expected := top == .Pause ? 0 : count - 1
		state.sound_events = {}
		tap_widget(audit, &state, back)
		testing.expectf(t, state.screens.count == expected, "Back on %v left %d screens", top, state.screens.count)
		testing.expectf(t, .Back in state.sound_events && .Confirm not_in state.sound_events, "Back on %v sounds %v", top, state.sound_events)
		destroy_ui_state(&state)
		// run_screens forgot the machine and the picker once they closed.
		simulation.players[0].open_machine = touch_case.machine ? assembler : NO_ENTITY
		audit.views.recipe_browser.selecting_for = touch_case.selecting ? assembler : NO_ENTITY
		outside := Ui_State{theme = audit.theme}
		for screen in touch_case.screens {
			push_screen(&outside.screens, screen)
		}
		touch_screen_frame(audit, &outside)
		testing.expectf(t, top_screen(outside.screens) == top, "%v closed before the tap", top)
		tap_screen_at(audit, &outside, {40, 400})
		testing.expectf(t, outside.screens.count == expected, "a tap outside %v left %d screens", top, outside.screens.count)
		destroy_ui_state(&outside)
	}
	simulation.players[0].open_machine = NO_ENTITY
	audit.views.recipe_browser.selecting_for = NO_ENTITY
}

// The title and the touch layout editor draw neither glyphs nor a row:
// the title has nothing to close, the editor has its own Close.
@(test)
test_the_title_and_the_layout_editor_draw_no_row_on_touch :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	stacks := [?][]Screen{{.Title}, {.Pause, .Settings, .Touch_Layout}}
	for stack in stacks {
		state := Ui_State{theme = audit.theme}
		for screen in stack {
			push_screen(&state.screens, screen)
		}
		touch_screen_frame(audit, &state)
		testing.expect(t, !glyph_bar_draws_glyphs(state.draw_list[:]))
		testing.expect(t, widget_index(state.widgets[:], slot_button_id("touch_button_back")) < 0)
		destroy_ui_state(&state)
	}
}

// A tap off the panel closes the pause menu (the game resumes), the
// settings (back to the pause menu), new world (back to the title) and
// the confirm dialog (No); never the title or the layout editor.
@(test)
test_a_tap_outside_closes_every_screen_with_a_panel :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	outside := [2]f32{100, 400}
	Outside_Case :: struct {
		screens:  []Screen,
		expected: Screen,
	}
	cases := [?]Outside_Case {
		{{.Pause}, .None},
		{{.Pause, .Settings}, .Pause},
		{{.Title, .New_World}, .Title},
		{{.Title, .Load_World, .Confirm_Delete}, .Load_World},
		{{.Title}, .Title},
	}
	for outside_case in cases {
		state := Ui_State{theme = audit.theme}
		for screen in outside_case.screens {
			push_screen(&state.screens, screen)
		}
		touch_screen_frame(audit, &state)
		tap_screen_at(audit, &state, outside)
		testing.expectf(t, top_screen(state.screens) == outside_case.expected, "a tap outside %v left %v", outside_case.screens, top_screen(state.screens))
		destroy_ui_state(&state)
	}
	testing.expect(t, !screen_closes_on_outside_tap(.Touch_Layout))
	testing.expect(t, !screen_closes_on_outside_tap(.Title))
	testing.expect(t, screen_closes_on_outside_tap(.Textures))
}

// With the system keyboard the first tap outside ends the entry, the
// next one closes the screen; the game's keyboard keeps the screen.
@(test)
test_a_tap_outside_ends_a_system_keyboard_entry_first :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	outside := [2]f32{100, 400}
	for system in ([2]bool{true, false}) {
		state := Ui_State{theme = audit.theme}
		push_screen(&state.screens, .Title)
		push_screen(&state.screens, .New_World)
		state.keyboard = {field = 1, system = system}
		touch_screen_frame(audit, &state)
		tap_screen_at(audit, &state, outside)
		testing.expect_value(t, top_screen(state.screens), Screen.New_World)
		testing.expect_value(t, state.keyboard.field == 0, system)
		if system {
			touch_screen_frame(audit, &state)
			tap_screen_at(audit, &state, outside)
			testing.expect_value(t, top_screen(state.screens), Screen.Title)
		}
		destroy_ui_state(&state)
	}
}

// A tap on a recipe selects it and queues nothing; Craft, Craft 5 and
// Cancel last act on the selected recipe.
@(test)
test_a_tap_on_a_recipe_selects_it_and_the_row_crafts :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	player.crafting = {}
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.inventory.slots[3] = {test_item(audit.content.items, "log"), 20}
	plank := test_recipe(audit.content.recipes, "plank")
	audit.views.recipe_browser.filter.category = audit.content.recipes.recipes[plank].category
	audit.views.recipe_browser.focused_recipe = NO_RECIPE
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Recipes)
	for _ in 0 ..< 3 {
		touch_screen_frame(audit, &state)
	}
	list_id := ui_hash(ui_hash(0, "recipes", -1), "recipe_list", -1)
	row := recipe_row_id(list_id, plank)
	if !testing.expect(t, widget_index(state.widgets[:], row) >= 0) {
		return
	}
	tap_widget(audit, &state, row)
	testing.expect_value(t, player.crafting.count, 0)
	testing.expect_value(t, audit.views.recipe_browser.focused_recipe, plank)
	testing.expect_value(t, top_screen(state.screens), Screen.Recipes)
	tap_widget(audit, &state, slot_button_id("touch_button_craft"))
	testing.expect_value(t, queued_craft_count(player.crafting), 0)
	run_audit_tick(audit)
	testing.expect_value(t, queued_craft_count(player.crafting), 1)
	testing.expect_value(t, player.crafting.runs[0].recipe, plank)
	tap_widget(audit, &state, slot_button_id("touch_button_craft_five"))
	run_audit_tick(audit)
	testing.expect_value(t, queued_craft_count(player.crafting), 1 + RECIPE_CRAFT_MANY_COUNT)
	testing.expect_value(t, player.crafting.count, 1)
	tap_widget(audit, &state, slot_button_id("touch_button_cancel_craft"))
	run_audit_tick(audit)
	testing.expect_value(t, queued_craft_count(player.crafting), RECIPE_CRAFT_MANY_COUNT)
	// The gamepad's Confirm still crafts the focused recipe.
	state.requested_focus = row
	touch_screen_frame(audit, &state)
	screen_test_frame(audit, &state, {confirm = true, pointer_is_touch = true})
	run_audit_tick(audit)
	testing.expect_value(t, queued_craft_count(player.crafting), RECIPE_CRAFT_MANY_COUNT + 1)
}

// A tap on a technology selects it and starts nothing; Research starts it.
@(test)
test_a_tap_on_a_technology_selects_it_and_research_starts_it :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	research := &audit.simulation.records.research
	research.queued = false
	available := NO_TECHNOLOGY
	for _, index in audit.content.technologies.technologies {
		if technology_status(audit.content.technologies, audit.simulation.unlocks, index) == .Available {
			available = index
			break
		}
	}
	if !testing.expect(t, available != NO_TECHNOLOGY) {
		return
	}
	audit.views.technology_browser.focused = available
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Technologies)
	for _ in 0 ..< 3 {
		touch_screen_frame(audit, &state)
	}
	list_id := ui_hash(ui_hash(0, "technologies", -1), "technology_list", -1)
	row := technology_row_id(list_id, available)
	if !testing.expect(t, widget_index(state.widgets[:], row) >= 0) {
		return
	}
	tap_widget(audit, &state, row)
	testing.expect(t, !research.queued)
	testing.expect_value(t, audit.views.technology_browser.focused, available)
	tap_widget(audit, &state, slot_button_id("touch_button_research"))
	testing.expect(t, !research.queued)
	run_audit_tick(audit)
	testing.expect(t, research.queued)
	testing.expect_value(t, research.technology, available)
}

// The rows' buttons by screen state.
@(test)
test_touch_row_buttons_by_screen :: proc(t: ^testing.T) {
	testing.expect(t, .Clear_Filter in machine_touch_buttons(true))
	testing.expect(t, .Clear_Filter not_in machine_touch_buttons(false))
	testing.expect(t, .Back in machine_touch_buttons(false))
	testing.expect_value(t, recipe_touch_buttons(true), Touch_Buttons{.Choose_Recipe, .Back})
	testing.expect_value(t, recipe_touch_buttons(false), Touch_Buttons{.Craft, .Craft_Five, .Cancel_Craft, .Back})
	testing.expect(t, .Drop in INVENTORY_TOUCH_BUTTONS)
	testing.expect(t, .Research in TECHNOLOGY_TOUCH_BUTTONS)
	testing.expect_value(t, map_touch_zoom_step(.Zoom_In), -1)
	testing.expect_value(t, map_touch_zoom_step(.Zoom_Out), 1)
	testing.expect_value(t, map_touch_zoom_step(.Back), 0)
	testing.expect_value(t, player_slot_index({.Hotbar, 3}), 3)
	testing.expect_value(t, player_slot_index({.Machine, 3}), -1)
}

// Craft, Craft 5 and Research do nothing while the list hides the
// selected entry.
@(test)
test_the_row_ignores_a_hidden_selection :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	player.crafting = {}
	player.inventory.slots[3] = {test_item(audit.content.items, "log"), 20}
	plank := test_recipe(audit.content.recipes, "plank")
	audit.views.recipe_browser.filter.category = audit.content.recipes.recipes[plank].category
	audit.views.recipe_browser.filter.tags = ~Recipe_Tag_Set{}
	audit.views.recipe_browser.focused_recipe = plank
	state := Ui_State{theme = audit.theme}
	push_screen(&state.screens, .Recipes)
	touch_screen_frame(audit, &state)
	touch_screen_frame(audit, &state)
	tap_widget(audit, &state, slot_button_id("touch_button_craft"))
	tap_widget(audit, &state, slot_button_id("touch_button_craft_five"))
	testing.expect_value(t, player.crafting.count, 0)
	destroy_ui_state(&state)
	// A researched technology, hidden by Hide researched.
	researched := -1
	for technology, index in audit.content.technologies.technologies {
		if !technology.infinite {
			researched = index
			break
		}
	}
	audit.simulation.unlocks.researched[researched] = true
	audit.views.technology_browser.focused = researched
	audit.views.technology_browser.filter.hide_researched = true
	audit.simulation.records.research.queued = false
	technologies := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&technologies)
	push_screen(&technologies.screens, .Technologies)
	touch_screen_frame(audit, &technologies)
	testing.expect(t, widget_index(technologies.widgets[:], technology_row_id(ui_hash(ui_hash(0, "technologies", -1), "technology_list", -1), researched)) < 0)
	// Selected before the filter hid it, with the focus off the list (the
	// toggle that hid it).
	audit.views.technology_browser.focused = researched
	technologies.focus = slot_button_id("touch_button_research")
	tap_widget(audit, &technologies, slot_button_id("touch_button_research"))
	testing.expect(t, !audit.simulation.records.research.queued)
	testing.expect_value(t, len(technologies.toasts), 0)
}

// In the recipe picker a tap selects and sets nothing; Choose sets the
// selected recipe and returns to the assembler's panel.
@(test)
test_a_tap_in_the_recipe_picker_selects_and_choose_sets_it :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	assembler: ^Assembler
	for &entry in simulation.world.entities.assemblers.entries {
		if entry.alive && audit.content.machines.machines[entry.machine].recipe_choice != .Fixed {
			assembler = &entry
			break
		}
	}
	if !testing.expect(t, assembler != nil) {
		return
	}
	simulation.players[0].open_machine = assembler.handle
	audit.views.recipe_browser.selecting_for = assembler.handle
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Machine)
	push_screen(&state.screens, .Recipes)
	for _ in 0 ..< 3 {
		touch_screen_frame(audit, &state)
	}
	list_id := ui_hash(ui_hash(0, "recipes", -1), "recipe_list", -1)
	chosen := NO_RECIPE
	for widget in state.widgets {
		for recipe in 0 ..< len(audit.content.recipes.recipes) {
			if recipe != assembler.recipe && widget.id == recipe_row_id(list_id, recipe) {
				chosen = recipe
			}
		}
		if chosen != NO_RECIPE {
			break
		}
	}
	if !testing.expect(t, chosen != NO_RECIPE) {
		return
	}
	before := assembler.recipe
	tap_widget(audit, &state, recipe_row_id(list_id, chosen))
	testing.expect_value(t, top_screen(state.screens), Screen.Recipes)
	testing.expect_value(t, assembler.recipe, before)
	testing.expect_value(t, audit.views.recipe_browser.focused_recipe, chosen)
	tap_widget(audit, &state, slot_button_id("touch_button_choose_recipe"))
	testing.expect_value(t, top_screen(state.screens), Screen.Machine)
	testing.expect_value(t, assembler.recipe, before)
	run_audit_tick(audit)
	testing.expect_value(t, assembler.recipe, chosen)
	simulation.players[0].open_machine = NO_ENTITY
}

// The map's zoom buttons step the zoom and stop at its ends.
@(test)
test_the_map_zoom_buttons_step_within_bounds :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Map)
	touch_screen_frame(audit, &state)
	audit.views.map_view.zoom = 1
	tap_widget(audit, &state, slot_button_id("touch_button_zoom_in"))
	testing.expect_value(t, audit.views.map_view.zoom, 0)
	tap_widget(audit, &state, slot_button_id("touch_button_zoom_in"))
	testing.expect_value(t, audit.views.map_view.zoom, 0)
	tap_widget(audit, &state, slot_button_id("touch_button_zoom_out"))
	testing.expect_value(t, audit.views.map_view.zoom, 1)
	audit.views.map_view.zoom = MAP_ZOOM_LEVEL_COUNT - 1
	tap_widget(audit, &state, slot_button_id("touch_button_zoom_out"))
	testing.expect_value(t, audit.views.map_view.zoom, MAP_ZOOM_LEVEL_COUNT - 1)
}

// At 1280 by 800 (the Deck) the machine panels' row keeps Sort in one
// place with and without Clear filter, and no label is cut.
@(test)
test_the_machine_row_keeps_its_places_at_the_deck_size :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	sort_x: [2]f32
	for kind, index in ([2]Machine_Kind{.Chest, .Splitter}) {
		handle := audit_machine_of_kind(audit, kind)
		if !testing.expect(t, handle != NO_ENTITY) {
			return
		}
		audit.simulation.players[0].open_machine = handle
		state := Ui_State{theme = audit.theme}
		push_screen(&state.screens, .Machine)
		ui_begin(&state, {pointer_is_touch = true}, {1280, 800}, 1.0 / 60, 1, 1, ui_accessibility(audit.settings))
		run_screens(&state, audit_screen_context(audit))
		ui_resolve(&state)
		sort := widget_index(state.widgets[:], slot_button_id("slot_button_sort"))
		if testing.expect(t, sort >= 0) {
			sort_x[index] = state.widgets[sort].rectangle.x
		}
		testing.expect_value(t, widget_index(state.widgets[:], slot_button_id("touch_button_clear_filter")) >= 0, kind == .Splitter)
		for command in state.draw_list {
			if command.panel == UI_GLYPH_BAR_PANEL && command.kind == .Text {
				testing.expectf(t, !strings.has_suffix(command.text, UI_ELLIPSIS), "%v cuts %q", kind, command.text)
			}
		}
		destroy_ui_state(&state)
	}
	testing.expect_value(t, sort_x[0], sort_x[1])
	audit.simulation.players[0].open_machine = NO_ENTITY
}

// A screen frame of the audit's site with the world falling or not and
// the fall skippable or not (Screen_Context.arrival_falling and
// arrival_skippable, 0200).
arrival_screen_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State, input: Ui_Input, falling: bool, skippable := false) {
	ui_begin(state, input, {1920, 1080}, 1.0 / 60, 1, 1, ui_accessibility(audit.settings))
	screen_context := audit_screen_context(audit)
	screen_context.arrival_falling = falling
	screen_context.arrival_skippable = skippable
	run_screens(state, screen_context)
	ui_resolve(state)
}

// Before the hit the pause menu has Skip arrival and no Journal: Confirm
// on Skip queues one Skip_Arrival_Command for the viewport's player and
// closes the menu. In the settle second there is no Skip row;
// without the fall there is none and the Journal is back.
@(test)
test_the_pause_menu_offers_skip_during_the_fall :: proc(t: ^testing.T) {
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	arrival := Field_Arrival{fall_ticks = u64(config.arrival_ticks)}
	testing.expect(t, field_arrival_skippable(arrival, 300, config.arrival_settle_ticks), "skippable at tick 300")
	settling := u64(config.arrival_ticks - config.arrival_settle_ticks / 3)
	testing.expectf(t, !field_arrival_skippable(arrival, settling, config.arrival_settle_ticks), "not skippable at tick %d", settling)
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	clear(&audit.simulation.player_commands)
	skip := pause_button_id("pause_skip_arrival")
	journal := pause_button_id("pause_journal")
	push_screen(&state.screens, .Pause)
	arrival_screen_frame(audit, &state, {}, false)
	testing.expect(t, widget_index(state.widgets[:], skip) < 0, "no Skip arrival without a fall")
	testing.expect(t, widget_index(state.widgets[:], journal) >= 0, "the Journal without a fall")
	arrival_screen_frame(audit, &state, {}, true, false)
	testing.expect(t, widget_index(state.widgets[:], skip) < 0, "no Skip arrival in the settle second")
	testing.expect(t, widget_index(state.widgets[:], journal) < 0, "no Journal during the fall")
	arrival_screen_frame(audit, &state, {}, true, true)
	testing.expect(t, widget_index(state.widgets[:], skip) >= 0, "Skip arrival before the hit")
	testing.expect(t, widget_index(state.widgets[:], journal) < 0, "no Journal during the fall")
	state.requested_focus = skip
	arrival_screen_frame(audit, &state, {device = .Gamepad, device_seen = true}, true, true)
	testing.expect_value(t, state.focus, skip)
	arrival_screen_frame(audit, &state, {confirm = true, confirm_down = true, device = .Gamepad, device_seen = true}, true, true)
	testing.expect_value(t, state.screens.count, 0)
	testing.expect_value(t, len(audit.simulation.player_commands), 1)
	if len(audit.simulation.player_commands) == 1 {
		queued := audit.simulation.player_commands[0]
		_, is_skip := queued.command.(Skip_Arrival_Command)
		testing.expect(t, is_skip)
		testing.expect_value(t, queued.player, 0)
	}
}

// During the fall the inventory binding opens nothing and Pause still
// opens the menu; after the landing the inventory binding opens the
// inventory (the approval of 0200).
@(test)
test_the_screens_are_held_during_the_fall :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	arrival_screen_frame(audit, &state, {open_inventory = true}, true)
	testing.expect_value(t, top_screen(state.screens), Screen.None)
	arrival_screen_frame(audit, &state, {open_map = true}, true)
	testing.expect_value(t, top_screen(state.screens), Screen.None)
	arrival_screen_frame(audit, &state, {pause = true}, true)
	testing.expect_value(t, top_screen(state.screens), Screen.Pause)
	state.screens.count = 0
	arrival_screen_frame(audit, &state, {}, false)
	arrival_screen_frame(audit, &state, {open_inventory = true}, false)
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}

// A pause menu frame of the audit's site with the viewport's placement
// editor (0215).
placement_pause_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State, input: Ui_Input, editor: ^Placement_Editor) {
	ui_begin(state, input, {1920, 1080}, 1.0 / 60, 1, 1, ui_accessibility(audit.settings))
	screen_context := audit_screen_context(audit)
	screen_context.placement_editor = editor
	run_screens(state, screen_context)
	ui_resolve(state)
}

// While the placement editor is anchored the pause menu offers Cancel
// placement, which cancels it and closes the menu; not otherwise.
@(test)
test_the_pause_menu_offers_cancel_placement_while_the_editor_runs :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	cancel := pause_button_id("pause_cancel_placement")
	push_screen(&state.screens, .Pause)
	placement_pause_frame(audit, &state, {}, nil)
	testing.expect(t, widget_index(state.widgets[:], cancel) < 0, "no Cancel placement without an editor")
	editor := Placement_Editor{on = true}
	placement_pause_frame(audit, &state, {}, &editor)
	testing.expect(t, widget_index(state.widgets[:], cancel) < 0, "no Cancel placement unanchored")
	editor.anchored = true
	placement_pause_frame(audit, &state, {}, &editor)
	testing.expect(t, widget_index(state.widgets[:], cancel) >= 0, "Cancel placement while anchored")
	state.requested_focus = cancel
	placement_pause_frame(audit, &state, {device = .Gamepad, device_seen = true}, &editor)
	testing.expect_value(t, state.focus, cancel)
	placement_pause_frame(audit, &state, {confirm = true, confirm_down = true, device = .Gamepad, device_seen = true}, &editor)
	testing.expect_value(t, state.screens.count, 0)
	testing.expect(t, !editor.anchored)
	testing.expect(t, editor.on)
}
