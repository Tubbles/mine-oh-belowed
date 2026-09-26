package game

import "core:testing"

TEST_DAY_LENGTH :: 1000

// The tick at which a given fraction of the day since sunrise has passed.
day_tick :: proc(fraction: f64) -> u64 {
	return u64((fraction - DAY_START_FRACTION + 1) * TEST_DAY_LENGTH) % TEST_DAY_LENGTH
}

@(test)
test_daylight_follows_the_sun :: proc(t: ^testing.T) {
	testing.expect_value(t, daylight_blend(day_tick(0.25), TEST_DAY_LENGTH), 1)
	testing.expect_value(t, daylight_blend(day_tick(0.75), TEST_DAY_LENGTH), 0)
	dawn := daylight_blend(day_tick(0), TEST_DAY_LENGTH)
	testing.expect(t, dawn > 0 && dawn < 1)
	testing.expect_value(t, daylight_blend(day_tick(0.25) + TEST_DAY_LENGTH, TEST_DAY_LENGTH), 1)
	testing.expect_value(t, day_factor(0), NIGHT_DAY_FACTOR)
	testing.expect_value(t, day_factor(1), 1)
	testing.expect_value(t, sky_color(1), DAY_SKY_COLOR)
	testing.expect_value(t, sky_color(0), NIGHT_SKY_COLOR)
}

// No jumps between ticks, so the sky never flickers.
@(test)
test_daylight_changes_smoothly :: proc(t: ^testing.T) {
	previous := daylight_blend(0, TEST_DAY_LENGTH)
	for tick in u64(1) ..= 2 * TEST_DAY_LENGTH {
		blend := daylight_blend(tick, TEST_DAY_LENGTH)
		testing.expectf(t, abs(blend - previous) < 0.05, "tick %d jumps from %v to %v", tick, previous, blend)
		previous = blend
	}
}
