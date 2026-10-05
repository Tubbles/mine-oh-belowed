package game

import "core:math"
import "core:math/linalg"
import "core:testing"

// The arrival's presentation (work item 0200), pure: the timeline, the
// path and the shake.

// The shipped arrival on a 60 Hz config.
shipped_arrival_config :: proc() -> Game_Config {
	shipped, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	return shipped
}

@(test)
test_the_arrival_view_follows_the_timeline :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	testing.expect_value(t, config.tick_rate, 60)
	falling := Field_Arrival{start_tick = 0, fall_ticks = u64(config.arrival_ticks)}
	landed := falling
	landed.landed_tick = u64(config.arrival_ticks)
	start := arrival_view(falling, 0, 0, config)
	testing.expect_value(t, start.phase, Arrival_Phase.Descent)
	testing.expect_value(t, start.progress, 0)
	early := arrival_view(falling, 299, 0, config)
	testing.expect_value(t, early.phase, Arrival_Phase.Descent)
	testing.expect_value(t, early.flame_strength, 0)
	middle := arrival_view(falling, 420, 0, config)
	testing.expect(t, middle.flame_strength > 0 && middle.flame_strength < 1, "the flames rise")
	late := arrival_view(falling, 539, 0, config)
	testing.expect_value(t, late.phase, Arrival_Phase.Descent)
	testing.expect(t, late.flame_strength > 0.95, "the flames near their height")
	hit := arrival_view(falling, 540, 0, config)
	testing.expect_value(t, hit.phase, Arrival_Phase.Settled)
	testing.expect_value(t, hit.seconds_since_hit, 0)
	testing.expect_value(t, arrival_view(landed, 600, 0, config).phase, Arrival_Phase.Settled)
	testing.expect_value(t, arrival_view(landed, 780, 0, config).phase, Arrival_Phase.None)
	skipped := falling
	skipped.landed_tick = 101
	testing.expect_value(t, arrival_view(skipped, 101, 0, config).phase, Arrival_Phase.None)
	testing.expect_value(t, arrival_view(skipped, 600, 0, config).phase, Arrival_Phase.None)
	testing.expect_value(t, arrival_view({}, 10, 0, config).phase, Arrival_Phase.None)
}

@(test)
test_the_fall_ends_at_the_eye_and_its_last_second_is_fastest :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	up := linalg.normalize([3]f32{0.2, 1, 0.1})
	forward := linalg.normalize(linalg.cross(up, [3]f32{1, 0, 0}))
	angle := f32(config.arrival_angle_degrees) * math.RAD_PER_DEG
	offset := arrival_descent_offset({phase = .Descent, progress = 0}, up, forward, config)
	testing.expect(t, abs(linalg.length(offset) - f32(config.arrival_start_metres) / math.cos(angle)) < 0.01, "the start lies the path's length from the eye")
	testing.expect(t, abs(linalg.dot(offset, up) - f32(config.arrival_start_metres)) < 0.01, "the start lies start metres above the eye")
	last := arrival_descent_offset({phase = .Descent, progress = 1}, up, forward, config)
	testing.expect(t, linalg.length(last) < 0.01, "the fall ends on the eye")
	testing.expect_value(t, arrival_descent_offset({phase = .Settled}, up, forward, config), [3]f32{})
	testing.expect_value(t, arrival_descent_offset({}, up, forward, config), [3]f32{})
	descent := f32(config.arrival_ticks - config.arrival_settle_ticks)
	before: f32 = 0
	for second in 1 ..= 9 {
		covered := arrival_eased_share(f32(second) * 60 / descent) - arrival_eased_share(f32(second - 1) * 60 / descent)
		testing.expectf(t, covered > before, "second %d covers no more than the one before", second)
		before = covered
	}
}

@(test)
test_the_shake_fades_and_never_repeats :: proc(t: ^testing.T) {
	salt := u64(DEFAULT_WORLD_SEED)
	position, look := arrival_shake_offset(ARRIVAL_SHAKE_SECONDS, salt)
	testing.expect_value(t, position, [3]f32{})
	testing.expect_value(t, look, [3]f32{})
	samples: [120][3]f32
	for &sample, index in samples {
		sample, _ = arrival_shake_offset(f32(index) / 120, salt)
	}
	all_equal := true
	for sample in samples[1:] {
		all_equal = all_equal && sample == samples[0]
	}
	testing.expect(t, !all_equal, "the shake moves")
	for period in 1 ..= 60 {
		repeats := true
		for index in 0 ..< len(samples) - period {
			if linalg.length(samples[index] - samples[index + period]) > 0.0001 {
				repeats = false
				break
			}
		}
		testing.expectf(t, !repeats, "the shake repeats every %d samples", period)
	}
}

// A window's quad (0223): its corners in the glass's plane, each the
// radius times the root of two from the centre, the texture's y edge (the
// midpoint of corners 2 and 3) along the travel laid on the plane, and a
// travel along the normal using the fallback.
@(test)
test_the_window_quad_leads_along_the_travel :: proc(t: ^testing.T) {
	centre := [3]f32{3, 4, -2}
	normal := linalg.normalize([3]f32{-0.755, -0.490, 0.436})
	travel := linalg.normalize([3]f32{0.1, -1, 0.3})
	radius: f32 = 0.2
	corners := arrival_window_corners(centre, normal, travel, {0, 1, 0}, radius)
	for corner, index in corners {
		testing.expectf(t, abs(linalg.dot(corner - centre, normal)) < 0.0001, "corner %d leaves the plane", index)
		testing.expectf(t, abs(linalg.length(corner - centre) - radius * math.SQRT_TWO) < 0.0001, "corner %d is %v from the centre", index, linalg.length(corner - centre))
	}
	along := linalg.normalize(travel - normal * linalg.dot(travel, normal))
	leading := (corners[2] + corners[3]) / 2 - centre
	testing.expect(t, linalg.length(leading - along * radius) < 0.0001, "the leading edge lies along the travel")
	fallback := [3]f32{0, 1, 0}
	head_on := arrival_window_corners(centre, normal, normal, fallback, radius)
	laid := linalg.normalize(fallback - normal * linalg.dot(fallback, normal))
	testing.expect(t, linalg.length((head_on[2] + head_on[3]) / 2 - centre - laid * radius) < 0.0001, "a travel along the normal leads along the fallback")
}
