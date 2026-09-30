package game

import "core:testing"

@(test)
test_touch_pointer_position_follows_the_first_touch_and_stays_after_it_lifts :: proc(t: ^testing.T) {
	testing.expect_value(t, touch_pointer_position(1, {300, 200}, {10, 20}), [2]f32{300, 200})
	testing.expect_value(t, touch_pointer_position(2, {300, 200}, {10, 20}), [2]f32{300, 200})
	// raylib leaves the lifted touch's position behind, or -1, -1.
	testing.expect_value(t, touch_pointer_position(0, {-1, -1}, {300, 200}), [2]f32{300, 200})
}
