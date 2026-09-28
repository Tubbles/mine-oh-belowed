package game

import "core:testing"

// The bumpers step the inventory tab strip from each of its screens,
// wrapping, by replacing the top screen (work item 0094).
@(test)
test_bumpers_step_the_inventory_tab_strip :: proc(t: ^testing.T) {
	strip := Ui_Rectangle{0, 0, 600, 56}
	Step :: struct {
		from, next, previous: Screen,
	}
	steps := [?]Step {
		{.Inventory, .Recipes, .Technologies},
		{.Recipes, .Technologies, .Inventory},
		{.Technologies, .Inventory, .Recipes},
	}
	for step in steps {
		for input in ([2]Ui_Input{{tab_next = true}, {tab_previous = true}}) {
			state: Ui_State
			// Opened from a lab's panel: Back returns there.
			push_screen(&state.screens, .Machine)
			push_screen(&state.screens, step.from)
			test_ui_frame(&state, input)
			inventory_tabs(&state, strip)
			testing.expect_value(t, top_screen(state.screens), input.tab_next ? step.next : step.previous)
			testing.expect_value(t, state.screens.count, 2)
			testing.expect_value(t, state.screens.screens[0], Screen.Machine)
			// A frame without a bumper keeps the tab.
			test_ui_frame(&state, {})
			inventory_tabs(&state, strip)
			testing.expect_value(t, top_screen(state.screens), input.tab_next ? step.next : step.previous)
			destroy_ui_state(&state)
		}
	}
}

// On the keyboard E is Open_Inventory and Tab_Next: it closes the strip
// from any of its screens instead of stepping.
@(test)
test_open_inventory_closes_the_strip :: proc(t: ^testing.T) {
	strip := Ui_Rectangle{0, 0, 600, 56}
	for screen in inventory_tab_screens {
		state: Ui_State
		push_screen(&state.screens, screen)
		test_ui_frame(&state, {open_inventory = true, tab_next = true})
		inventory_tabs(&state, strip)
		testing.expect_value(t, top_screen(state.screens), screen)
		handle_screen_keys(&state)
		testing.expect_value(t, state.screens.count, 0)
		destroy_ui_state(&state)
	}
}

// A frame in the world forgets the focus of the last screen; a screen
// open keeps it.
@(test)
test_a_frame_without_a_screen_clears_the_focus :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	state.focus = 7
	push_screen(&state.screens, .None)
	test_ui_frame(&state, {})
	run_screens(&state, {})
	testing.expect_value(t, state.focus, 7)
	pop_screen(&state.screens)
	test_ui_frame(&state, {})
	run_screens(&state, {})
	testing.expect_value(t, state.focus, 0)
}
