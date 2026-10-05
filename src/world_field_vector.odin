package game

// Fixed point vectors and angles of the terrain field (work item 0170,
// doc/architecture.md, The player on the field): directions are vectors of
// length UNIT_VECTOR_ONE in i64, angles are integers in 1/ANGLE_UNITS_PER_TURN
// of a turn, and the sine is a Taylor series in integers, so the player's
// up, heading and slope agree on every machine (lockstep, 0177).

// The length of a unit vector. 2^24 keeps the heading of a walk round a
// planet within a few millimetres, and a world position times it inside an
// i64 (FAR_LIMIT_METRES at 1/POSITION_UNITS_PER_METRE is below 2^28).
UNIT_VECTOR_ONE :: 1 << 24
ANGLE_UNITS_PER_TURN :: 65536
ANGLE_UNITS_PER_QUARTER :: ANGLE_UNITS_PER_TURN / 4
// The Taylor series runs in 1/2^30; HALF_PI_TAYLOR_ONE is pi/2 in it.
TAYLOR_ONE_SHIFT :: 30
HALF_PI_TAYLOR_ONE :: 1686629713
// Terms after x: x^13/13! at pi/2 is below 2^-24.
TAYLOR_TERM_COUNT :: 6

degrees_to_angle_units :: proc(degrees: int) -> i32 {
	return i32(degrees * ANGLE_UNITS_PER_TURN / 360)
}

fixed_dot :: proc(first, second: [3]i64) -> i64 {
	return (first.x * second.x + first.y * second.y + first.z * second.z) / UNIT_VECTOR_ONE
}

fixed_cross :: proc(first, second: [3]i64) -> [3]i64 {
	return {
		(first.y * second.z - first.z * second.y) / UNIT_VECTOR_ONE,
		(first.z * second.x - first.x * second.z) / UNIT_VECTOR_ONE,
		(first.x * second.y - first.y * second.x) / UNIT_VECTOR_ONE,
	}
}

// vector times a fraction in UNIT_VECTOR_ONE.
fixed_scale :: proc(vector: [3]i64, fraction: i64) -> [3]i64 {
	return vector * fraction / UNIT_VECTOR_ONE
}

// Components above 2^30 are shifted down before squaring and the length
// shifted back up, so the squares stay inside an i64 for any position or
// sum of speeds (validate_game_config bounds each speed per tick).
VECTOR_LENGTH_EXACT_LIMIT :: i64(1) << 30

vector_length :: proc(vector: [3]i64) -> i64 {
	largest := max(abs(vector.x), abs(vector.y), abs(vector.z))
	shift: uint = 0
	for largest >> shift >= VECTOR_LENGTH_EXACT_LIMIT {
		shift += 1
	}
	scaled := [3]i64{vector.x >> shift, vector.y >> shift, vector.z >> shift}
	return i64(integer_square_root(u64(scaled.x * scaled.x + scaled.y * scaled.y + scaled.z * scaled.z))) << shift
}

// The unit vector along vector; ok is false for the zero vector.
normalize_fixed :: proc(vector: [3]i64) -> (unit: [3]i64, ok: bool) {
	length := vector_length(vector)
	if length == 0 {
		return {}, false
	}
	return vector * UNIT_VECTOR_ONE / length, true
}

// vector less its part along the unit normal.
project_onto_plane :: proc(vector, normal: [3]i64) -> [3]i64 {
	return vector - fixed_scale(normal, fixed_dot(vector, normal))
}

// sin(x) and cos(x) for x from 0 to pi/2 in 1/2^TAYLOR_ONE_SHIFT.
taylor_sine_cosine :: proc(x: i64) -> (sine, cosine: i64) {
	squared := x * x >> TAYLOR_ONE_SHIFT
	sine_term, cosine_term := x, i64(1) << TAYLOR_ONE_SHIFT
	sine, cosine = sine_term, cosine_term
	for index in 1 ..= TAYLOR_TERM_COUNT {
		n := i64(index)
		sine_term = -(sine_term * squared >> TAYLOR_ONE_SHIFT) / ((2 * n) * (2 * n + 1))
		cosine_term = -(cosine_term * squared >> TAYLOR_ONE_SHIFT) / ((2 * n - 1) * (2 * n))
		sine += sine_term
		cosine += cosine_term
	}
	return
}

// The sine of an angle in ANGLE_UNITS_PER_TURN, in UNIT_VECTOR_ONE.
fixed_sine :: proc(angle: i32) -> i64 {
	turn := int(angle) %% ANGLE_UNITS_PER_TURN
	quadrant := turn / ANGLE_UNITS_PER_QUARTER
	within := i64(turn % ANGLE_UNITS_PER_QUARTER)
	sine, cosine := taylor_sine_cosine(within * HALF_PI_TAYLOR_ONE / ANGLE_UNITS_PER_QUARTER)
	value := sine
	switch quadrant {
	case 1:
		value = cosine
	case 2:
		value = -sine
	case 3:
		value = -cosine
	}
	return value >> (TAYLOR_ONE_SHIFT - 24)
}

fixed_cosine :: proc(angle: i32) -> i64 {
	return fixed_sine(angle + ANGLE_UNITS_PER_QUARTER)
}

#assert(UNIT_VECTOR_ONE == 1 << 24, "fixed_sine shifts the series down to 2^24")

// The angle from minus to plus a quarter turn whose fixed_sine is sine
// (clamped to plus or minus UNIT_VECTOR_ONE), integer only: for a sine
// not below zero the largest angle of the quarter whose fixed_sine is not
// above it, found by a binary search over the quarter's 16385 angles; a
// negative sine is the mirror of its magnitude's, so the inverse is odd
// as the sine is (0183, look_field_player_at).
angle_of_sine :: proc(sine: i64) -> i32 {
	magnitude := min(abs(sine), UNIT_VECTOR_ONE)
	low, high := i32(0), i32(ANGLE_UNITS_PER_QUARTER)
	for low < high {
		middle := (low + high + 1) / 2
		if fixed_sine(middle) <= magnitude {
			low = middle
		} else {
			high = middle - 1
		}
	}
	return sine < 0 ? -low : low
}

// The vector turned in the plane of the orthonormal units first and
// second, first towards second, by the angle of cosine and sine (in
// UNIT_VECTOR_ONE); its part off the plane is kept. Not normalised, so
// an offset keeps its length (the pod's rest, 0270).
rotate_in_plane :: proc(vector, first, second: [3]i64, cosine, sine: i64) -> [3]i64 {
	along_first, along_second := fixed_dot(vector, first), fixed_dot(vector, second)
	in_plane := fixed_scale(first, along_first) + fixed_scale(second, along_second)
	turned := fixed_scale(second, along_first) - fixed_scale(first, along_second)
	return vector + fixed_scale(in_plane, cosine - UNIT_VECTOR_ONE) + fixed_scale(turned, sine)
}
