package game

import "core:testing"

// The series is exact to two parts in 2^24 at angles the units hold
// exactly (0, 45, 90, 180, 270 degrees); 30 degrees is 5461 units, a third
// of a unit short, which costs about 470 parts.
@(test)
test_the_fixed_sine_follows_the_circle :: proc(t: ^testing.T) {
	half := i64(UNIT_VECTOR_ONE / 2)
	// sin 45 degrees times 2^24.
	diagonal := i64(11863283)
	cases := [?]struct {
		degrees:   int,
		sine:      i64,
		tolerance: i64,
	}{{0, 0, 2}, {45, diagonal, 2}, {90, UNIT_VECTOR_ONE, 2}, {180, 0, 2}, {270, -UNIT_VECTOR_ONE, 2}, {-45, -diagonal, 2}, {30, half, 1024}, {150, half, 1024}, {-30, -half, 1024}}
	for entry in cases {
		sine := fixed_sine(degrees_to_angle_units(entry.degrees))
		testing.expectf(t, abs(sine - entry.sine) <= entry.tolerance, "sin %d degrees is %d, wanted %d", entry.degrees, sine, entry.sine)
	}
	testing.expect(t, abs(fixed_cosine(degrees_to_angle_units(60)) - half) <= 1024)
}

@(test)
test_fixed_vectors_normalise_and_cross :: proc(t: ^testing.T) {
	unit, ok := normalize_fixed({3, 0, 4})
	testing.expect(t, ok)
	testing.expect_value(t, unit, [3]i64{UNIT_VECTOR_ONE * 3 / 5, 0, UNIT_VECTOR_ONE * 4 / 5})
	_, zero_ok := normalize_fixed({})
	testing.expect(t, !zero_ok)
	x, y := [3]i64{UNIT_VECTOR_ONE, 0, 0}, [3]i64{0, UNIT_VECTOR_ONE, 0}
	testing.expect_value(t, fixed_cross(x, y), [3]i64{0, 0, UNIT_VECTOR_ONE})
	testing.expect_value(t, fixed_dot(x, y), 0)
	testing.expect_value(t, project_onto_plane({5, 7, 9}, y), [3]i64{5, 0, 9})
}
