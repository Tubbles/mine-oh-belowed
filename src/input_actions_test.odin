package game

import "core:math"
import "core:testing"

TEST_TOLERANCE :: 1e-4

nearly_equal :: proc(a, b: [2]f32) -> bool {
	return abs(a.x - b.x) < TEST_TOLERANCE && abs(a.y - b.y) < TEST_TOLERANCE
}

// Point on a circle around the pad centre, clockwise degrees from straight up.
pad_point :: proc(degrees_from_up: f32, radius: f32) -> [2]f32 {
	radians := degrees_from_up * math.RAD_PER_DEG
	return {0.5 + radius * math.sin(radians), 0.5 - radius * math.cos(radians)}
}

@(test)
test_gyro_to_look_delta_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, gyro_to_look_delta({0, 0, 0}, 1.0 / 60), [2]f32{0, 0})
}

@(test)
test_gyro_to_look_delta_signs :: proc(t: ^testing.T) {
	// One radian per second of yaw (controller turned left) for one second.
	turn_left := gyro_to_look_delta({0, 1, 0}, 1)
	testing.expect(t, nearly_equal(turn_left, {-math.DEG_PER_RAD, 0}))
	// Far end tilted up: look up, which is negative y like the mouse.
	tilt_up := gyro_to_look_delta({1, 0, 0}, 1)
	testing.expect(t, nearly_equal(tilt_up, {0, -math.DEG_PER_RAD}))
	// Roll does not move the view.
	testing.expect_value(t, gyro_to_look_delta({0, 0, 5}, 1), [2]f32{0, 0})
}

@(test)
test_gyro_to_look_delta_scales_with_seconds :: proc(t: ^testing.T) {
	angular_velocity := [3]f32{0.3, -0.7, 0.2}
	single := gyro_to_look_delta(angular_velocity, 0.01)
	triple := gyro_to_look_delta(angular_velocity, 0.03)
	testing.expect(t, nearly_equal(single * 3, triple))
}

@(test)
test_touchpad_delta :: proc(t: ^testing.T) {
	up := Touchpad_Finger{down = false, position = {0.2, 0.2}}
	first := Touchpad_Finger{down = true, position = {0.25, 0.5}}
	second := Touchpad_Finger{down = true, position = {0.5, 0.25}}
	testing.expect_value(t, touchpad_delta(up, first), [2]f32{0, 0})
	testing.expect_value(t, touchpad_delta(first, up), [2]f32{0, 0})
	testing.expect_value(t, touchpad_delta(up, up), [2]f32{0, 0})
	testing.expect(t, nearly_equal(touchpad_delta(first, second), {0.25, -0.25}))
}

@(test)
test_radial_slot_center :: proc(t: ^testing.T) {
	slot, touched_center := radial_slot_from_touchpad(0.5, 0.5, 8)
	testing.expect_value(t, slot, -1)
	testing.expect_value(t, touched_center, true)
	just_inside := pad_point(90, RADIAL_CENTER_RADIUS - 0.01)
	slot, touched_center = radial_slot_from_touchpad(just_inside.x, just_inside.y, 8)
	testing.expect_value(t, touched_center, true)
	just_outside := pad_point(90, RADIAL_CENTER_RADIUS + 0.01)
	slot, touched_center = radial_slot_from_touchpad(just_outside.x, just_outside.y, 8)
	testing.expect_value(t, touched_center, false)
	testing.expect_value(t, slot, 2)
}

@(test)
test_radial_slot_cardinal_directions :: proc(t: ^testing.T) {
	expected := [4][2]f32{{0.5, 0.0}, {1.0, 0.5}, {0.5, 1.0}, {0.0, 0.5}}
	for position, index in expected {
		slot, touched_center := radial_slot_from_touchpad(position.x, position.y, 4)
		testing.expect_value(t, slot, index)
		testing.expect_value(t, touched_center, false)
	}
}

@(test)
test_radial_slot_boundaries :: proc(t: ^testing.T) {
	// With four slots the boundaries sit at 45, 135, 225 and 315 degrees.
	Boundary_Case :: struct {
		degrees:     f32,
		slot_before: int,
		slot_after:  int,
	}
	cases := [?]Boundary_Case{{45, 0, 1}, {135, 1, 2}, {225, 2, 3}, {315, 3, 0}}
	for boundary in cases {
		before := pad_point(boundary.degrees - 1, 0.4)
		after := pad_point(boundary.degrees + 1, 0.4)
		slot_before, _ := radial_slot_from_touchpad(before.x, before.y, 4)
		slot_after, _ := radial_slot_from_touchpad(after.x, after.y, 4)
		testing.expect_value(t, slot_before, boundary.slot_before)
		testing.expect_value(t, slot_after, boundary.slot_after)
	}
}

@(test)
test_radial_slot_invalid_count :: proc(t: ^testing.T) {
	slot, touched_center := radial_slot_from_touchpad(0.5, 0.0, 0)
	testing.expect_value(t, slot, -1)
	testing.expect_value(t, touched_center, false)
}

@(test)
test_gyro_look_active :: proc(t: ^testing.T) {
	no_sense := Raw_Touch_Sense{}
	idle := Raw_Touch_Sense{available = true}
	stick := Raw_Touch_Sense{available = true, right_stick_touched = true}
	testing.expect(t, gyro_look_active(no_sense, {}))
	testing.expect(t, !gyro_look_active(idle, {}))
	testing.expect(t, gyro_look_active(idle, {down = true}))
	testing.expect(t, gyro_look_active(stick, {}))
}

@(test)
test_normalize_sdl_axis :: proc(t: ^testing.T) {
	testing.expect_value(t, normalize_sdl_axis(0), 0)
	testing.expect_value(t, normalize_sdl_axis(32767), 1)
	testing.expect_value(t, normalize_sdl_axis(-32768), -1)
}

@(test)
test_tick_input_sums_look_delta_of_frames_between_ticks :: proc(t: ^testing.T) {
	accumulator: Tick_Input_Accumulator
	first := Input_Frame {
		look_delta   = {3, 0},
		just_pressed = {.Place},
		pressed      = {.Place},
	}
	second := Input_Frame {
		look_delta = {4, 1},
		move       = {0, 1},
	}
	accumulator = accumulate_frame_input(accumulator, first)
	accumulator = accumulate_frame_input(accumulator, second)
	tick_input: Input_Frame
	tick_input, accumulator = take_tick_input(accumulator, second)
	testing.expect_value(t, tick_input.look_delta, [2]f32{7, 1})
	testing.expect_value(t, tick_input.just_pressed, Action_Set{.Place})
	testing.expect_value(t, tick_input.pressed, Action_Set{})
	testing.expect_value(t, tick_input.move, [2]f32{0, 1})
	// A second tick in the same frame gets no look delta and no edges again,
	// but still the held state.
	tick_input, accumulator = take_tick_input(accumulator, second)
	testing.expect_value(t, tick_input.look_delta, [2]f32{0, 0})
	testing.expect_value(t, tick_input.just_pressed, Action_Set{})
	testing.expect_value(t, tick_input.move, [2]f32{0, 1})
}

@(test)
test_mouse_wheel_actions :: proc(t: ^testing.T) {
	testing.expect_value(t, mouse_wheel_actions({0, -1}), Action_Set{.Hotbar_Next})
	testing.expect_value(t, mouse_wheel_actions({0, 2}), Action_Set{.Hotbar_Previous})
	testing.expect_value(t, mouse_wheel_actions({0, 0}), Action_Set{})
}
