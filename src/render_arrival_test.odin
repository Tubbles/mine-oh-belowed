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
	curve := build_arrival_curve(config)
	descent := u64(config.arrival_ticks - config.arrival_settle_ticks)
	falling := Field_Arrival{start_tick = 0, fall_ticks = u64(config.arrival_ticks)}
	landed := falling
	landed.landed_tick = u64(config.arrival_ticks)
	start := arrival_view(falling, 0, 0, config, &curve)
	testing.expect_value(t, start.phase, Arrival_Phase.Descent)
	testing.expect_value(t, start.progress, 0)
	testing.expect_value(t, start.heat, 0)
	peak_tick: u64 = 0
	peak_heat: f32 = 0
	for tick in 0 ..< descent {
		heat := arrival_view(falling, tick, 0, config, &curve).heat
		if heat > peak_heat {
			peak_tick, peak_heat = tick, heat
		}
	}
	testing.expectf(t, peak_heat > 0.95, "the heat peaks at %v", peak_heat)
	testing.expect_value(t, arrival_view(falling, peak_tick - 1, 0, config, &curve).cooling, 0)
	testing.expect_value(t, arrival_view(falling, peak_tick + 1, 0, config, &curve).cooling, 1)
	late := arrival_view(falling, descent - 1, 0, config, &curve)
	testing.expect_value(t, late.phase, Arrival_Phase.Descent)
	testing.expect_value(t, late.heat, 0)
	hit := arrival_view(falling, descent, 0, config, &curve)
	testing.expect_value(t, hit.phase, Arrival_Phase.Settled)
	testing.expect_value(t, hit.seconds_since_hit, 0)
	testing.expect_value(t, arrival_view(landed, u64(config.arrival_ticks), 0, config, &curve).phase, Arrival_Phase.Settled)
	testing.expect_value(t, arrival_view(landed, descent + 240, 0, config, &curve).phase, Arrival_Phase.None)
	skipped := falling
	skipped.landed_tick = 101
	testing.expect_value(t, arrival_view(skipped, 101, 0, config, &curve).phase, Arrival_Phase.None)
	testing.expect_value(t, arrival_view(skipped, descent, 0, config, &curve).phase, Arrival_Phase.None)
	testing.expect_value(t, arrival_view({}, 10, 0, config, &curve).phase, Arrival_Phase.None)
}

@(test)
test_the_fall_ends_at_the_floor_and_never_runs_backwards :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	curve := build_arrival_curve(config)
	up := linalg.normalize([3]f32{0.2, 1, 0.1})
	forward := linalg.normalize(linalg.cross(up, [3]f32{1, 0, 0}))
	falling := Field_Arrival{start_tick = 0, fall_ticks = u64(config.arrival_ticks)}
	descent := u64(config.arrival_ticks - config.arrival_settle_ticks)
	first := arrival_descent_offset(arrival_view(falling, 0, 0, config, &curve), up, forward, &curve)
	testing.expect(t, abs(linalg.dot(first, up) - f32(config.arrival_start_metres)) < 0.01, "the start lies start metres above the eye")
	height, along := linalg.dot(first, up), linalg.dot(first, forward)
	for tick in 1 ..< descent {
		offset := arrival_descent_offset(arrival_view(falling, tick, 0, config, &curve), up, forward, &curve)
		testing.expectf(t, linalg.dot(offset, up) <= height, "the fall rises at tick %d", tick)
		testing.expectf(t, linalg.dot(offset, forward) >= along, "the fall runs back at tick %d", tick)
		height, along = linalg.dot(offset, up), linalg.dot(offset, forward)
	}
	testing.expect_value(t, arrival_descent_offset({phase = .Descent, progress = 1, curve_progress = 1}, up, forward, &curve), [3]f32{})
	testing.expect_value(t, arrival_descent_offset({phase = .Settled}, up, forward, &curve), [3]f32{})
	testing.expect_value(t, arrival_descent_offset({}, up, forward, &curve), [3]f32{})
}

@(test)
test_the_buffet_follows_the_heat :: proc(t: ^testing.T) {
	salt := u64(DEFAULT_WORLD_SEED)
	position, look := arrival_buffet_offset(3, 0, salt)
	testing.expect_value(t, position, [3]f32{})
	testing.expect_value(t, look, [3]f32{})
	samples: [120][3]f32
	for &sample, index in samples {
		sample, _ = arrival_buffet_offset(f32(index) / 60, 1, salt)
		testing.expect(t, linalg.length(sample) <= ARRIVAL_BUFFET_METRES * math.SQRT_THREE + 0.0001, "the buffet stays inside its amplitude")
	}
	all_equal := true
	for sample in samples[1:] {
		all_equal = all_equal && sample == samples[0]
	}
	testing.expect(t, !all_equal, "the buffet moves")
}

@(test)
test_the_sky_is_black_above_the_atmosphere :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	atmosphere := config.atmosphere
	testing.expect_value(t, atmosphere_sky_share(f32(config.arrival_start_metres), atmosphere), 0)
	testing.expect_value(t, atmosphere_sky_share(f32(atmosphere.top_metres), atmosphere), 0)
	testing.expect_value(t, atmosphere_sky_share(0, atmosphere), 1)
	testing.expect_value(t, atmosphere_sky_share(f32(atmosphere.top_metres - 2 * atmosphere.scale_height_metres), atmosphere), 1)
	before: f32 = 1
	for altitude in 0 ..= config.arrival_start_metres {
		share := atmosphere_sky_share(f32(altitude), atmosphere)
		testing.expectf(t, share <= before, "the sky brightens with altitude at %d m", altitude)
		before = share
	}
	sky := Day_Sky{fraction = 0.25, blend = 1, colors = {zenith = {90, 140, 220, 255}, horizon = {170, 200, 235, 255}, fog = {170, 200, 235, 255}, sun_tint = {255, 250, 240, 255}}}
	space := altitude_day_sky(sky, 0)
	testing.expect_value(t, space.colors.zenith, SPACE_SKY_COLOR)
	testing.expect_value(t, space.colors.horizon, SPACE_SKY_COLOR)
	testing.expect_value(t, space.blend, 0)
	testing.expect_value(t, altitude_day_sky(sky, 1), sky)
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
