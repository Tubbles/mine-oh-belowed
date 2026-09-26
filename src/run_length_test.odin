package game

import "core:math/rand"
import "core:slice"
import "core:testing"

@(test)
test_run_length_empty_input :: proc(t: ^testing.T) {
	runs := run_length_encode(nil, context.temp_allocator)
	testing.expect_value(t, len(runs), 0)
	values := run_length_decode(runs, context.temp_allocator)
	testing.expect_value(t, len(values), 0)
}

@(test)
test_run_length_single_value :: proc(t: ^testing.T) {
	runs := run_length_encode([]u16{7}, context.temp_allocator)
	testing.expect(t, slice.equal(runs, []Run{{value = 7, count = 1}}))
}

@(test)
test_run_length_alternating_values :: proc(t: ^testing.T) {
	runs := run_length_encode([]u16{1, 2, 1, 2}, context.temp_allocator)
	expected := []Run{{1, 1}, {2, 1}, {1, 1}, {2, 1}}
	testing.expect(t, slice.equal(runs, expected))
}

@(test)
test_run_length_long_runs :: proc(t: ^testing.T) {
	CHUNK_VOLUME :: 32 * 32 * 32
	values := make([]u16, CHUNK_VOLUME, context.temp_allocator)
	for index in CHUNK_VOLUME / 2 ..< CHUNK_VOLUME {
		values[index] = 3
	}
	runs := run_length_encode(values, context.temp_allocator)
	expected := []Run{{0, CHUNK_VOLUME / 2}, {3, CHUNK_VOLUME / 2}}
	testing.expect(t, slice.equal(runs, expected))
}

@(test)
test_run_length_round_trip_pseudo_random :: proc(t: ^testing.T) {
	random_state := rand.create(u64(0x5eed))
	generator := rand.default_random_generator(&random_state)
	values := make([]u16, 10_000, context.temp_allocator)
	for &value in values {
		// Few distinct values so that runs of more than one element occur.
		value = u16(rand.int_max(4, generator))
	}
	runs := run_length_encode(values, context.temp_allocator)
	decoded := run_length_decode(runs, context.temp_allocator)
	testing.expect(t, len(runs) < len(values))
	testing.expect(t, slice.equal(decoded, values))
}
