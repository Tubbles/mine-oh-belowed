package render_frustum

import "core:math"
import "core:math/linalg"
import "core:testing"

// Camera at the origin looking down -z, 90 degrees vertical field of view.
test_view_projection :: proc() -> matrix[4, 4]f32 {
	projection := linalg.matrix4_perspective_f32(90 * math.RAD_PER_DEG, 1, 0.1, 100)
	view := linalg.matrix4_look_at_f32({0, 0, 0}, {0, 0, -1}, {0, 1, 0})
	return projection * view
}

@(test)
test_frustum_box_in_front_is_inside :: proc(t: ^testing.T) {
	frustum := frustum_from_matrix(test_view_projection())
	testing.expect(t, frustum_contains_box(frustum, {-1, -1, -10}, {1, 1, -8}))
}

@(test)
test_frustum_box_behind_is_outside :: proc(t: ^testing.T) {
	frustum := frustum_from_matrix(test_view_projection())
	testing.expect(t, !frustum_contains_box(frustum, {-1, -1, 5}, {1, 1, 8}))
}

@(test)
test_frustum_box_to_the_side_and_beyond_far :: proc(t: ^testing.T) {
	frustum := frustum_from_matrix(test_view_projection())
	// At depth 10 the view is 20 wide, so x from 30 is outside.
	testing.expect(t, !frustum_contains_box(frustum, {30, -1, -11}, {32, 1, -9}))
	testing.expect(t, !frustum_contains_box(frustum, {-1, -1, -300}, {1, 1, -200}))
}

@(test)
test_frustum_box_straddling_a_plane_is_inside :: proc(t: ^testing.T) {
	frustum := frustum_from_matrix(test_view_projection())
	testing.expect(t, frustum_contains_box(frustum, {5, -1, -11}, {40, 1, -9}))
	// A chunk the camera sits in.
	testing.expect(t, frustum_contains_box(frustum, {-16, -16, -16}, {16, 16, 16}))
}
