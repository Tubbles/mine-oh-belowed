package game

import "core:testing"

@(test)
test_world_input_is_empty_while_a_screen_is_open :: proc(t: ^testing.T) {
	frame := Input_Frame {
		move         = {0, 1},
		look         = {1, 0},
		look_delta   = {5, 5},
		pressed      = {.Move, .Look, .Jump, .Confirm, .Mine},
		just_pressed = {.Jump, .Confirm},
	}
	blocked := world_input(frame, true, {}, DEFAULT_SETTINGS)
	testing.expect_value(t, blocked.move, [2]f32{})
	testing.expect_value(t, blocked.look_delta, [2]f32{})
	testing.expect_value(t, blocked.pressed, Action_Set{.Confirm})
	testing.expect_value(t, blocked.just_pressed, Action_Set{.Confirm})
	open := world_input(frame, false, {}, DEFAULT_SETTINGS)
	testing.expect_value(t, open.pressed, frame.pressed)
}

@(test)
test_world_action_guard_holds_until_release :: proc(t: ^testing.T) {
	// A pressed on Resume: the screen is open this frame.
	guard := update_world_action_guard({}, true, {.Jump, .Confirm})
	testing.expect_value(t, guard, Action_Set{.Jump})
	// Screen closed, A still held: no jump.
	guard = update_world_action_guard(guard, false, {.Jump, .Confirm})
	held := world_input(Input_Frame{pressed = {.Jump, .Confirm}}, false, guard, DEFAULT_SETTINGS)
	testing.expect(t, .Jump not_in held.pressed)
	// Released once: the guard is gone and the next press jumps.
	guard = update_world_action_guard(guard, false, {})
	testing.expect_value(t, guard, Action_Set{})
	pressed_again := world_input(Input_Frame{pressed = {.Jump}, just_pressed = {.Jump}}, false, guard, DEFAULT_SETTINGS)
	testing.expect(t, .Jump in pressed_again.just_pressed)
}

@(test)
test_paused_clock_runs_no_catch_up_ticks :: proc(t: ^testing.T) {
	accumulator := make_tick_accumulator(60)
	ticks: int
	for _ in 0 ..< 600 {
		accumulator, ticks = advance_simulation_clock(accumulator, 0.1, true)
		testing.expect_value(t, ticks, 0)
	}
	accumulator, ticks = advance_simulation_clock(accumulator, 1.0 / 60, false)
	testing.expect_value(t, ticks, 1)
}

@(test)
test_look_settings :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	settings.stick_look_sensitivity = 2
	settings.invert_pitch = true
	result := apply_look_settings(Input_Frame{look = {0.5, 0.25}, look_delta = {3, 4}}, settings)
	testing.expect_value(t, result.look, [2]f32{1, -0.5})
	testing.expect_value(t, result.look_delta, [2]f32{3, -4})
}

@(test)
test_gyro_setting_and_sensitivities :: proc(t: ^testing.T) {
	gamepad := Raw_Gamepad {
		connected = true,
		// The look reads the calibrated rate (calibrate_frame_gyro).
		motion = {gyro = {available = true, enabled = true, values = {0, 1, 0}, corrected = {0, 1, 0}}},
	}
	settings := DEFAULT_SETTINGS
	base := sdl3_look_delta(gamepad, gamepad, 1.0 / 60, settings)
	testing.expect(t, base.x != 0)
	settings.gyro_look_sensitivity = 2
	doubled := sdl3_look_delta(gamepad, gamepad, 1.0 / 60, settings)
	testing.expect(t, nearly_equal(doubled, base * 2))
	settings.gyro_enabled = false
	testing.expect_value(t, sdl3_look_delta(gamepad, gamepad, 1.0 / 60, settings), [2]f32{})
	// Under Steam's layer SDL's gyro never turns the view.
	settings.gyro_enabled = true
	testing.expect_value(t, sdl3_look_delta(gamepad, gamepad, 1.0 / 60, settings, false), [2]f32{})
}
