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

// Work item 0297: the sun the field lights by is the sky's sun turned
// back into the world's frame for the viewer's up. With the up on +y the
// sky's frame is the world's; with the up on +x the noon sun stands
// cos(tilt) above that up and leans towards +z as it did.
@(test)
test_the_field_sun_turns_with_the_viewers_up :: proc(t: ^testing.T) {
	tilt := f32(SUN_PATH_TILT_DEGREES * math.RAD_PER_DEG)
	for fraction in ([4]f64{0, 0.25, 0.5, 0.75}) {
		expect_near_point(t, field_sun_world_direction(fraction, {0, 1, 0}), sun_direction(fraction), "the up on +y keeps the sky's sun")
		testing.expect(t, abs(linalg.length(field_sun_world_direction(fraction, {0, 1, 0})) - 1) < MOTION_TEST_TOLERANCE)
	}
	up := [3]f32{1, 0, 0}
	noon := field_sun_world_direction(0.25, up)
	expect_near_point(t, noon, {math.cos(tilt), 0, math.sin(tilt)}, "noon stands over the up on +x")
	testing.expect(t, abs(linalg.dot(noon, up) - math.cos(tilt)) < MOTION_TEST_TOLERANCE)
	midnight := field_sun_world_direction(0.75, up)
	testing.expect(t, abs(linalg.dot(midnight, up) + math.cos(tilt)) < MOTION_TEST_TOLERANCE)
	for fraction in ([4]f64{0, 0.25, 0.5, 0.75}) {
		testing.expect(t, abs(linalg.length(field_sun_world_direction(fraction, up)) - 1) < MOTION_TEST_TOLERANCE)
	}
}

// Work item 0328: the sun path's axis the shadow map's basis takes stays
// unit and square to the field's sun for every up and time of day, so the
// basis never degenerates.
@(test)
test_the_sun_path_axis_is_square_to_the_sun :: proc(t: ^testing.T) {
	for up in ([3][3]f32{{0, 1, 0}, {1, 0, 0}, linalg.normalize([3]f32{1, 2, 3})}) {
		axis := field_sun_path_world_axis(up)
		testing.expectf(t, abs(linalg.length(axis) - 1) < MOTION_TEST_TOLERANCE, "the axis for up %v has length %v", up, linalg.length(axis))
		for step in 0 ..= 20 {
			fraction := f64(step) * 0.05
			square := linalg.dot(axis, field_sun_world_direction(fraction, up))
			testing.expectf(t, abs(square) < MOTION_TEST_TOLERANCE, "up %v fraction %v: the axis meets the sun at %v", up, fraction, square)
		}
	}
}

// Work item 0313: the sun's light is the high colour at noon, half the
// low colour on the horizon as it sets, none at midnight, and scales by
// the strength.
@(test)
test_the_sun_light_warms_low_and_sets :: proc(t: ^testing.T) {
	light := shipped_sun_and_torchlight(t)
	high := field_color_float(light.sun_high_color) / 255
	low := field_color_float(light.sun_low_color) / 255
	expect_near_color(t, sun_light_color(NOON_FRACTION, light), high, 1e-6, "noon")
	expect_near_color(t, sun_light_color(0, light), low / 2, 1e-6, "sunrise")
	testing.expect_value(t, sun_light_color(0.75, light), [3]f32{})
	doubled := light
	doubled.sun_strength_percent = 200
	expect_near_color(t, sun_light_color(NOON_FRACTION, doubled), 2 * high, 1e-6, "doubled")
}

// Work item 0313: the sky's light is the dome's horizon and zenith mixed
// two thirds towards the zenith, at sky_light_percent; at midnight it is
// dim and blue.
@(test)
test_the_sky_light_takes_the_zenith_two_thirds :: proc(t: ^testing.T) {
	light := shipped_sun_and_torchlight(t)
	noon := sky_colors(NOON_FRACTION)
	expected := (color_to_vector3(noon.horizon) + 2 * color_to_vector3(noon.zenith)) / 3 * 0.6
	expect_near_color(t, sky_light_color(noon, light), expected, 1e-5, "noon")
	midnight := sky_light_color(sky_colors(0.75), light)
	for channel in midnight {
		testing.expectf(t, channel > 0 && channel < 0.1, "midnight's sky light %v", midnight)
	}
	testing.expectf(t, midnight.b > midnight.r && midnight.b > midnight.g, "midnight's sky light %v is not blue", midnight)
}

// Work item 0313: the bounce is the ground's colour lit by the sun above
// the horizon and by the sky, at ground_bounce_percent.
@(test)
test_the_bounce_is_the_ground_lit_from_above :: proc(t: ^testing.T) {
	light := shipped_sun_and_torchlight(t)
	testing.expect_value(t, light.ground_bounce_percent, 60)
	expect_near_color(t, ground_bounce_color(0.5, 1, 0.2, 0.5, light), 0.21, 1e-6, "sun up")
	expect_near_color(t, ground_bounce_color(0.5, 1, 0.2, -0.3, light), 0.06, 1e-6, "sun down")
}

// Work item 0313: the haze's glow is half the sun's low colour at
// sunrise and sunset, none at noon and midnight.
@(test)
test_the_haze_glows_towards_a_low_sun_only :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	low := field_color_float(config.sun_and_torchlight.sun_low_color) / 255
	expect_near_color(t, haze_sun_glow_color(0, config.sun_and_torchlight, config.haze), low / 2, 1e-6, "sunrise")
	expect_near_color(t, haze_sun_glow_color(0.5, config.sun_and_torchlight, config.haze), low / 2, 1e-6, "sunset")
	testing.expect_value(t, haze_sun_glow_color(NOON_FRACTION, config.sun_and_torchlight, config.haze), [3]f32{})
	testing.expect_value(t, haze_sun_glow_color(0.75, config.sun_and_torchlight, config.haze), [3]f32{})
}

expect_near_color :: proc(t: ^testing.T, got, expected: [3]f32, tolerance: f32, message: string, location := #caller_location) {
	for channel in 0 ..< 3 {
		if abs(got[channel] - expected[channel]) > tolerance {
			testing.expectf(t, false, "%s: got %v, expected %v", message, got, expected, loc = location)
			return
		}
	}
}
