package game

import "core:math"
import "core:math/linalg"
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

@(test)
test_the_sun_crosses_the_sky_from_east_to_west :: proc(t: ^testing.T) {
	tilt := f32(SUN_PATH_TILT_DEGREES * math.RAD_PER_DEG)
	expect_near_point(t, sun_direction(0), {1, 0, 0}, "sunrise in the east")
	expect_near_point(t, sun_direction(0.25), {0, math.cos(tilt), math.sin(tilt)}, "noon up")
	expect_near_point(t, sun_direction(0.5), {-1, 0, 0}, "sunset in the west")
	expect_near_point(t, sun_direction(0.75), {0, -math.cos(tilt), -math.sin(tilt)}, "midnight down")
	for fraction in ([4]f64{0, 0.25, 0.5, 0.75}) {
		expect_near_point(t, moon_direction(fraction), -sun_direction(fraction), "moon opposite")
		testing.expect(t, abs(linalg.length(sun_direction(fraction)) - 1) < MOTION_TEST_TOLERANCE)
	}
	// The tilt keeps the noon sun off vertical: it leans towards +z.
	noon := sun_direction(0.25)
	testing.expect(t, noon.y < 0.95 && noon.z > 0.3)
}

@(test)
test_the_day_fraction_counts_from_sunrise :: proc(t: ^testing.T) {
	testing.expect(t, abs(day_fraction(day_tick(0.25), TEST_DAY_LENGTH) - 0.25) < 0.002)
	testing.expect(t, abs(day_fraction(0, TEST_DAY_LENGTH) - DAY_START_FRACTION) < 0.002)
	testing.expect_value(t, day_sky(2 * TEST_DAY_LENGTH + 500, TEST_DAY_LENGTH).day_number, 2)
}

@(test)
test_sky_colors_follow_the_day :: proc(t: ^testing.T) {
	noon := sky_colors(0.25)
	testing.expect_value(t, noon.zenith, DAY_SKY_COLOR)
	testing.expect_value(t, noon.horizon, DAY_HORIZON_COLOR)
	testing.expect_value(t, noon.fog, noon.horizon)
	testing.expect_value(t, noon.sun_tint, DAY_SUN_TINT)
	midnight := sky_colors(0.75)
	testing.expect_value(t, midnight.zenith, NIGHT_SKY_COLOR)
	testing.expect_value(t, midnight.horizon, NIGHT_HORIZON_COLOR)
	testing.expect_value(t, midnight.fog, midnight.horizon)
	testing.expect_value(t, midnight.sun_tint, NIGHT_SUN_TINT)
	// Mid dusk: the sun on the horizon.
	dusk := sky_colors(0.5)
	testing.expect_value(t, dusk.horizon, DUSK_HORIZON_COLOR)
	testing.expect_value(t, dusk.sun_tint, DUSK_SUN_TINT)
	testing.expect_value(t, dusk.fog, dusk.horizon)
	// The horizon glows warm while the zenith stays blue.
	testing.expect(t, int(dusk.horizon.r) - int(dusk.horizon.b) > 0)
	testing.expect(t, int(dusk.zenith.b) - int(dusk.zenith.r) > 0)
	// Dawn mirrors dusk.
	testing.expect_value(t, sky_colors(0).horizon, DUSK_HORIZON_COLOR)
}
