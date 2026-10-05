package game

import "core:log"
import "core:math/linalg"
import "core:testing"

// The arrival's entry curve (work item 0269), pure: the end at the floor,
// the heat's single peak and the shipped timeline.

@(test)
test_the_arrival_curve_reaches_the_floor :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	curve := build_arrival_curve(config)
	testing.expect(t, curve.reached_floor)
	last := curve.samples[ARRIVAL_CURVE_INTERVALS]
	testing.expect_value(t, last.altitude_metres, 0)
	testing.expect_value(t, last.along_metres, curve.range_metres)
	for index in 1 ..= ARRIVAL_CURVE_INTERVALS {
		testing.expectf(t, curve.samples[index].along_metres >= curve.samples[index - 1].along_metres, "the curve runs back at sample %d", index)
		testing.expectf(t, curve.samples[index].altitude_metres <= curve.samples[index - 1].altitude_metres, "the curve rises at sample %d", index)
	}
	first := curve.samples[0]
	testing.expect(t, last.velocity.y / arrival_curve_speed(last) < first.velocity.y / arrival_curve_speed(first), "the end is no steeper than the start")
}

@(test)
test_the_heat_peaks_once_between_the_start_and_the_hit :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	curve := build_arrival_curve(config)
	testing.expect_value(t, curve.samples[0].heat, 0)
	testing.expect_value(t, curve.samples[ARRIVAL_CURVE_INTERVALS].heat, 0)
	peak := int(curve.peak_progress * ARRIVAL_CURVE_INTERVALS)
	testing.expect_value(t, curve.samples[peak].heat, 1)
	for sample, index in curve.samples {
		testing.expectf(t, sample.heat <= 1, "sample %d is above the peak", index)
		if sample.altitude_metres >= f32(config.atmosphere.top_metres) {
			testing.expectf(t, sample.heat == 0, "sample %d glows above the atmosphere", index)
		}
		if index > 0 && index <= peak {
			testing.expectf(t, sample.heat >= curve.samples[index - 1].heat, "the heat falls before the peak at sample %d", index)
		}
		if index > peak {
			testing.expectf(t, sample.heat <= curve.samples[index - 1].heat, "the heat rises after the peak at sample %d", index)
		}
	}
}

// The shipped timeline, logged for the item's numbers: the tick the top
// is crossed, the heat's first tick above zero, its peak, its last tick
// above zero, and the speed as seen at the hit.
@(test)
test_the_shipped_arrival_timeline :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	curve := build_arrival_curve(config)
	falling := Field_Arrival{start_tick = 0, fall_ticks = u64(config.arrival_ticks)}
	descent := u64(config.arrival_ticks - config.arrival_settle_ticks)
	top_tick, heat_on_tick, peak_tick, heat_off_tick: u64
	top_found, heat_on_found := false, false
	peak_heat: f32 = 0
	for tick in 0 ..< descent {
		view := arrival_view(falling, tick, 0, config, &curve)
		sample := arrival_curve_at(&curve, view.curve_progress)
		if !top_found && sample.altitude_metres < f32(config.atmosphere.top_metres) {
			top_tick, top_found = tick, true
		}
		if view.heat > 0 {
			if !heat_on_found {
				heat_on_tick, heat_on_found = tick, true
			}
			heat_off_tick = tick
		}
		if view.heat > peak_heat {
			peak_tick, peak_heat = tick, view.heat
		}
	}
	before := arrival_curve_at(&curve, arrival_view(falling, descent - 1, 0, config, &curve).curve_progress)
	last := curve.samples[ARRIVAL_CURVE_INTERVALS]
	seen_speed := linalg.length([2]f32{last.along_metres - before.along_metres, last.altitude_metres - before.altitude_metres}) * f32(config.tick_rate)
	testing.expect(t, top_found && heat_on_found)
	testing.expect(t, top_tick < heat_on_tick && heat_on_tick < peak_tick && peak_tick < heat_off_tick)
	log.infof("arrival: natural %.2f s, range %.1f m, hit heat share %.3f, peak progress %.3f", curve.natural_seconds, curve.range_metres, curve.hit_heat_share, curve.peak_progress)
	log.infof("arrival: top crossed at tick %d, heat on at %d, peak at %d, heat out after %d, of %d; speed as seen at the hit %.1f m/s, the curve's %.1f m/s", top_tick, heat_on_tick, peak_tick, heat_off_tick, descent, seen_speed, arrival_curve_speed(last))
}

arrival_curve_speed :: proc(sample: Arrival_Curve_Sample) -> f32 {
	return linalg.length(sample.velocity)
}
