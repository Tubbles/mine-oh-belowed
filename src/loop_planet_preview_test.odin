package game

import "core:testing"

// A Jump held on one frame between two ticks reaches the tick; turns and
// presses add up, the latest move stands.
@(test)
test_preview_frames_between_ticks_merge :: proc(t: ^testing.T) {
	first := Field_Player_Input {
		move         = {0, FIELD_MOVE_ONE},
		turn         = {3, -1},
		held         = {.Jump},
		just_pressed = {.Jump},
	}
	second := Field_Player_Input {
		turn = {2, 0},
	}
	merged := merge_field_player_input(first, second)
	testing.expect_value(t, merged.move, [2]i32{0, 0})
	testing.expect_value(t, merged.turn, [2]i32{5, -1})
	testing.expect(t, .Jump in merged.held && .Jump in merged.just_pressed)
}

// Ten frames of a third of an angle unit turn three units, not none.
@(test)
test_preview_carries_the_turn_fraction :: proc(t: ^testing.T) {
	remainder: [2]f32
	total: [2]i32
	for _ in 0 ..< 10 {
		whole: [2]i32
		whole, remainder = carry_turn(remainder, {0.34, -0.34})
		total += whole
	}
	testing.expect_value(t, total, [2]i32{3, -3})
}
