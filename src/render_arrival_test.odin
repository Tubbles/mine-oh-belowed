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
	eye := [3]f32{100, 2000, -50}
	up := linalg.normalize([3]f32{0.2, 1, 0.1})
	forward := linalg.normalize(linalg.cross(up, [3]f32{1, 0, 0}))
	angle := f32(config.arrival_angle_degrees) * math.RAD_PER_DEG
	first := arrival_descent_camera(eye, {phase = .Descent, progress = 0}, up, forward, config, 70)
	offset := first.position - eye
	testing.expect(t, abs(linalg.length(offset) - f32(config.arrival_start_metres) / math.cos(angle)) < 0.01, "the start lies the path's length from the eye")
	testing.expect(t, abs(linalg.dot(offset, up) - f32(config.arrival_start_metres)) < 0.01, "the start lies start metres above the eye")
	last := arrival_descent_camera(eye, {phase = .Descent, progress = 1}, up, forward, config, 70)
	testing.expect(t, linalg.length(last.position - eye) < 0.01, "the fall ends on the eye")
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

// The window's look: along the path at pitch 0, pitched up by the
// shipped angle from it otherwise, unit, its up perpendicular to it.
@(test)
test_the_window_looks_up_from_the_path :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	testing.expect_value(t, config.arrival_window_pitch_degrees, 20)
	eye := [3]f32{100, 2000, -50}
	up := linalg.normalize([3]f32{0.2, 1, 0.1})
	forward := linalg.normalize(linalg.cross(up, [3]f32{1, 0, 0}))
	direction := arrival_path_direction(up, forward, config.arrival_angle_degrees)
	level := config
	level.arrival_window_pitch_degrees = 0
	flat := arrival_descent_camera(eye, {phase = .Descent, progress = 0.3}, up, forward, level, 70)
	testing.expect(t, linalg.length((flat.target - flat.position) + direction) < 0.0001, "pitch 0 looks along the path")
	pitched := arrival_descent_camera(eye, {phase = .Descent, progress = 0.3}, up, forward, config, 70)
	look := pitched.target - pitched.position
	testing.expect(t, abs(linalg.length(look) - 1) < 0.0001, "the look is unit")
	angle := math.acos(clamp(linalg.dot(look, -direction), -1, 1)) * math.DEG_PER_RAD
	testing.expect(t, abs(angle - 20) < 0.01, "the look is 20 degrees from the path")
	testing.expect(t, abs(linalg.dot(look, pitched.up)) < 0.0001, "the up is perpendicular to the look")
	testing.expect(t, linalg.dot(look, up) > linalg.dot(-direction, up), "the look is pitched up, towards the horizon")
}
