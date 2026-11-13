package game

import "core:testing"

// Work item 0276: a flick of the right stick steps the tabs once, when the
// armed stick goes past the threshold mostly sideways. Not while it stays
// out, not mostly up or down (the lists' scroll), and not while the letter
// wheel, which the stick steers, is open.
@(test)
test_the_right_stick_steps_tabs_once_per_flick :: proc(t: ^testing.T) {
	expect_flick :: proc(t: ^testing.T, armed: bool, stick: [2]f32, wheel_open: bool, step: int, armed_after: bool, location := #caller_location) {
		got_step, got_armed := right_stick_tab_step(armed, stick, wheel_open)
		testing.expect_value(t, got_step, step, location)
		testing.expect_value(t, got_armed, armed_after, location)
	}
	expect_flick(t, true, {0.8, 0.1}, false, 1, false)
	expect_flick(t, false, {0.9, 0}, false, 0, false)
	expect_flick(t, true, {-0.8, 0}, false, -1, false)
	expect_flick(t, true, {0.6, 0.7}, false, 0, true)
	expect_flick(t, true, {0.8, 0}, true, 0, false)
	expect_flick(t, false, {0.3, 0}, false, 0, true)
	input, armed := make_ui_input(Input_Frame{look = {0, 0}}, Input_Frame{look = {0.8, 0}}, true)
	testing.expect_value(t, input, Ui_Input{tab_next = true, right_stick = {0.8, 0}})
	testing.expect(t, !armed)
}

// Fix round of 0276: a stick hovering round the step threshold steps once,
// and steps again only after it came back near the centre.
@(test)
test_the_right_stick_flick_rearms_near_the_centre :: proc(t: ^testing.T) {
	armed := true
	steps := 0
	for x in ([]f32{0.49, 0.51, 0.49, 0.51}) {
		step: int
		step, armed = right_stick_tab_step(armed, {x, 0}, false)
		steps += abs(step)
	}
	testing.expect_value(t, steps, 1)
	for x in ([]f32{0.2, 0.8}) {
		step: int
		step, armed = right_stick_tab_step(armed, {x, 0}, false)
		steps += abs(step)
	}
	testing.expect_value(t, steps, 2)
}

// Fix round of 0276: on the flick's frame the stick held diagonally zooms
// the map one level, in the flick's direction (right is in), whether its
// vertical part points the same way or the other.
@(test)
test_a_diagonal_flick_zooms_the_map_one_level :: proc(t: ^testing.T) {
	for stick in ([][2]f32{{0.7, 0.6}, {0.7, -0.6}}) {
		input, _ := make_ui_input(Input_Frame{look = {0, 0}}, Input_Frame{look = stick}, true)
		view: Map_View
		testing.expect_value(t, map_zoom_step(&view, input, 1.0 / 60), -1)
	}
}
