package game

import "core:testing"

// A point on an 8 km planet off every axis, so no axis of its frame is
// trivial.
TEST_FRAME_HIT :: World_Position{3_000 * POSITION_UNITS_PER_METRE, 7_000 * POSITION_UNITS_PER_METRE, 2_000 * POSITION_UNITS_PER_METRE}
// The rounding of a unit vector's components and lengths, in 2^24.
TEST_FRAME_AXIS_TOLERANCE :: 8

test_frame_at :: proc(hit: World_Position, step: int, pitch_millimetres: int) -> Frame {
	up, _ := normalize_fixed(cast([3]i64)(hit))
	return Frame{id = 1, origin = hit, axes = frame_axes(up, step), pitch_millimetres = pitch_millimetres}
}

// The block frame's cell (x, y, z) spans x to x + 1 metres, as a block.
@(test)
test_the_block_frame_cells_are_block_metres :: proc(t: ^testing.T) {
	frame := block_frame()
	centre := frame_cell_centre(frame, {2, 3, -4})
	testing.expect_value(t, centre, World_Position{2 * POSITION_UNITS_PER_METRE + POSITION_UNITS_PER_METRE / 2, 3 * POSITION_UNITS_PER_METRE + POSITION_UNITS_PER_METRE / 2, -4 * POSITION_UNITS_PER_METRE + POSITION_UNITS_PER_METRE / 2})
	testing.expect_value(t, world_to_frame_cell(frame, centre), World_Coordinate{2, 3, -4})
	testing.expect_value(t, world_to_frame_cell(frame, World_Position{-1, 0, POSITION_UNITS_PER_METRE - 1}), World_Coordinate{-1, 0, 0})
}

// Up along the radial, right and forward across it and each other, every
// one a unit, at every yaw step and at a pole, where the north falls back.
@(test)
test_frame_axes_are_orthonormal_with_the_radial_up :: proc(t: ^testing.T) {
	hits := [?]World_Position{TEST_FRAME_HIT, {0, 8_000 * POSITION_UNITS_PER_METRE, 0}, {0, -8_000 * POSITION_UNITS_PER_METRE, 0}}
	for hit in hits {
		up, _ := normalize_fixed(cast([3]i64)(hit))
		for step in 0 ..< FRAME_YAW_STEPS {
			axes := frame_axes(up, step)
			testing.expect_value(t, axes[FRAME_UP], up)
			for axis in 0 ..< 3 {
				testing.expectf(t, abs(vector_length(axes[axis]) - UNIT_VECTOR_ONE) <= TEST_FRAME_AXIS_TOLERANCE, "%v step %d axis %d has length %d", hit, step, axis, vector_length(axes[axis]))
				for other in axis + 1 ..< 3 {
					testing.expectf(t, abs(fixed_dot(axes[axis], axes[other])) <= TEST_FRAME_AXIS_TOLERANCE, "%v step %d axes %d and %d meet at %d", hit, step, axis, other, fixed_dot(axes[axis], axes[other]))
				}
			}
			cross := fixed_cross(axes[FRAME_UP], axes[FRAME_FORWARD])
			for component in 0 ..< 3 {
				testing.expect(t, abs(cross[component] - axes[FRAME_RIGHT][component]) <= TEST_FRAME_AXIS_TOLERANCE, "right is up cross forward")
			}
		}
	}
}

// A step turns the forward by 15 degrees (within the rounding of a
// step's angle to a whole angle unit, about 400 parts in 2^24 of the
// cosine), and the heading of a step, or one turned a few degrees off it,
// rounds to that step.
@(test)
test_the_nearest_yaw_step_follows_the_heading :: proc(t: ^testing.T) {
	up, _ := normalize_fixed(cast([3]i64)(TEST_FRAME_HIT))
	fifteen_degrees := fixed_cosine(degrees_to_angle_units(15))
	for step in 0 ..< FRAME_YAW_STEPS {
		forward := frame_forward(up, step)
		testing.expectf(t, abs(fixed_dot(forward, frame_forward(up, step + 1)) - fifteen_degrees) <= 600, "step %d to the next is not 15 degrees", step)
		testing.expect_value(t, nearest_frame_yaw_step(up, forward), step)
		right := fixed_cross(up, forward)
		off := fixed_scale(forward, fixed_cosine(degrees_to_angle_units(5))) + fixed_scale(right, fixed_sine(degrees_to_angle_units(5)))
		testing.expect_value(t, nearest_frame_yaw_step(up, off), step)
	}
}

// Cell centre to world to cell is the identity a few thousand cells out at
// both pitches, and a point anywhere in a cell maps to that cell.
@(test)
test_a_cell_round_trips_through_the_world_far_from_the_origin :: proc(t: ^testing.T) {
	cells := [?]World_Coordinate{{0, 0, 0}, {3_000, -2, 2_500}, {-4_000, 5, 1}, {17, 4_000, -3_999}, {-1, -1, -1}}
	for pitch in ([2]int{500, BLOCK_FRAME_PITCH_MILLIMETRES}) {
		for step in ([3]int{0, 5, 23}) {
			frame := test_frame_at(TEST_FRAME_HIT, step, pitch)
			for cell in cells {
				centre := frame_cell_centre(frame, cell)
				testing.expectf(t, world_to_frame_cell(frame, centre) == cell, "pitch %d step %d: %v came back as %v", pitch, step, cell, world_to_frame_cell(frame, centre))
				quarter := frame_pitch_units(frame) / 4
				inside := centre + World_Position(fixed_scale(frame.axes[FRAME_RIGHT], quarter) - fixed_scale(frame.axes[FRAME_UP], quarter))
				testing.expect_value(t, world_to_frame_cell(frame, inside), cell)
			}
		}
	}
}

// A free frame stands on the hit: cell (0, 0, 0)'s centre is half a pitch
// above it along the radial.
@(test)
test_a_free_frame_stands_on_the_hit :: proc(t: ^testing.T) {
	origin, axes := free_frame_at(TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	frame := Frame{origin = origin, axes = axes, pitch_millimetres = 500}
	up, _ := normalize_fixed(cast([3]i64)(TEST_FRAME_HIT))
	testing.expect_value(t, axes[FRAME_UP], up)
	expected := TEST_FRAME_HIT + World_Position(fixed_scale(up, frame_pitch_units(frame) / 2))
	offset := cast([3]i64)(frame_cell_centre(frame, {}) - expected)
	testing.expectf(t, vector_length(offset) <= 2, "the centre is %v off", offset)
	testing.expect_value(t, world_to_frame_cell(frame, TEST_FRAME_HIT + World_Position(fixed_scale(up, 8))), World_Coordinate{})
}

// The index counts a frame's occupied cells; vacating twice or occupying
// a taken cell again does not miscount.
@(test)
test_the_occupant_index_counts_cells_per_frame :: proc(t: ^testing.T) {
	table: Frame_Table
	defer destroy_frame_table(&table)
	first := add_frame(&table, TEST_FRAME_HIT, block_frame().axes, 500)
	second := add_frame(&table, TEST_FRAME_HIT, block_frame().axes, 500)
	testing.expect_value(t, first, Frame_Id(1))
	testing.expect_value(t, second, Frame_Id(2))
	occupant := Occupant{handle = 7, flags = {.Solid}}
	occupy_frame_cell(&table, first, {0, 0, 0}, occupant)
	occupy_frame_cell(&table, first, {0, 0, 0}, occupant)
	occupy_frame_cell(&table, first, {1, 0, 0}, occupant)
	occupy_frame_cell(&table, second, {0, 0, 0}, occupant)
	testing.expect_value(t, frame_cell_count(&table, first), 2)
	testing.expect_value(t, frame_cell_count(&table, second), 1)
	testing.expect(t, !frame_cell_is_occupied(&table, BLOCK_FRAME, {0, 0, 0}))
	vacate_frame_cell(&table, first, {0, 0, 0})
	vacate_frame_cell(&table, first, {0, 0, 0})
	testing.expect_value(t, frame_cell_count(&table, first), 1)
	found, known := frame_occupant(&table, first, {1, 0, 0})
	testing.expect(t, known && found == occupant)
}
