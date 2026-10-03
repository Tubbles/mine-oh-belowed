package game

import "core:testing"

// A frame standing on TEST_FRAME_HIT with cell (0, 0, 0) and (2, 0, 0)
// occupied.
make_test_frame_table :: proc(step: int) -> (table: Frame_Table, frame: Frame) {
	origin, axes := free_frame_at(TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	axes = frame_axes(axes[FRAME_UP], step)
	id := add_frame(&table, origin, axes, 500)
	frame, _ = find_frame(&table, id)
	occupy_frame_cell(&table, id, {0, 0, 0}, Occupant{handle = 1, flags = {.Solid}})
	occupy_frame_cell(&table, id, {2, 0, 0}, Occupant{handle = 2, flags = {.Solid}})
	return
}

// Straight down from three metres over the cell's centre: the ray enters
// its top face two and three quarter metres along, and a foundation
// snapped there goes on top.
@(test)
test_a_ray_down_hits_the_top_of_a_frame_cell :: proc(t: ^testing.T) {
	for step in ([3]int{0, 7, 13}) {
		table, frame := make_test_frame_table(step)
		defer destroy_frame_table(&table)
		up := frame.axes[FRAME_UP]
		eye := frame_cell_centre(frame, {}) + World_Position(fixed_scale(up, metres_to_position_units(3)))
		hit := raycast_frames(&table, eye, -up, metres_to_position_units(5))
		testing.expect(t, hit.hit)
		testing.expect_value(t, hit.frame, frame.id)
		testing.expect_value(t, hit.cell, World_Coordinate{})
		testing.expect_value(t, hit.face, Direction.Positive_Y)
		testing.expect_value(t, hit.adjacent, World_Coordinate{0, 1, 0})
		testing.expect_value(t, hit.occupant.handle, Occupant_Handle(1))
		expected := metres_to_position_units(3) - frame_pitch_units(frame) / 2
		testing.expectf(t, abs(hit.distance - expected) <= 2, "step %d: distance %d, wanted %d", step, hit.distance, expected)
		testing.expect(t, !raycast_frames(&table, eye, -up, metres_to_position_units(2)).hit, "beyond the reach")
	}
}

// Along the frame's right axis from beside cell (0, 0, 0) the ray stops
// at the first occupied cell and passes the empty one, entering its
// negative x face; aimed away it misses.
@(test)
test_a_ray_along_a_frame_stops_at_the_first_occupied_cell :: proc(t: ^testing.T) {
	table, frame := make_test_frame_table(5)
	defer destroy_frame_table(&table)
	right := frame.axes[FRAME_RIGHT]
	start := frame_cell_centre(frame, {-3, 0, 0})
	hit := raycast_frames(&table, start, right, metres_to_position_units(4))
	testing.expect(t, hit.hit)
	testing.expect_value(t, hit.cell, World_Coordinate{})
	testing.expect_value(t, hit.face, Direction.Negative_X)
	testing.expect_value(t, hit.adjacent, World_Coordinate{-1, 0, 0})
	from_between := raycast_frames(&table, frame_cell_centre(frame, {1, 0, 0}), right, metres_to_position_units(4))
	testing.expect_value(t, from_between.cell, World_Coordinate{2, 0, 0})
	testing.expect(t, !raycast_frames(&table, start, -right, metres_to_position_units(4)).hit)
}
