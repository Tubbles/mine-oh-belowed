package game

import "core:math"
import "core:math/linalg"

// The arrival's path as an atmospheric entry (work item 0269,
// doc/content.md, The arrival): the pod leaves arrival_start_metres above
// the crater's floor at arrival_entry_speed_metres_per_second,
// arrival_entry_angle_degrees below the horizontal towards its door;
// gravity and a drag of the air's density times the speed squared bend
// it towards vertical. Integrated once in its own (natural) seconds and
// sampled, so the presentation reads it at any share of the descent and
// the load check (arrival_problem) reads its end. Floats only here: the
// landing tick stays arrival_ticks, the simulation's.

ARRIVAL_CURVE_INTERVALS :: 256
ARRIVAL_CURVE_STEP_SECONDS :: 1.0 / 240
ARRIVAL_CURVE_MAXIMUM_SECONDS :: 600
// Earth's: the stretch over the descent absorbs the planet's, which the
// config load does not know.
ARRIVAL_GRAVITY_METRES_PER_SECOND_SQUARED :: 9.81
// The start's distance from the crater stays inside this share of the
// coarsest level's distance, so the crater shows through the fog.
ARRIVAL_START_DISTANCE_SHARE :: 0.9
// The least altitude two scale heights under the atmosphere's top may
// reach, so the day's sky is untouched on the ground.
ATMOSPHERE_CLEAR_GROUND_METRES :: 64

// x along the pod's forward from the start, y the altitude above the
// resting place; velocity y negative falling.
Arrival_Curve_State :: struct {
	seconds:            f64,
	position, velocity: [2]f64,
}

Arrival_Curve_Sample :: struct {
	along_metres, altitude_metres: f32,
	velocity:                      [2]f32,
	heat:                          f32,
}

// Sample i at progress i / ARRIVAL_CURVE_INTERVALS of the natural time;
// the last one the hit, exactly at altitude 0 and range_metres along.
// real_seconds is arrival_real_seconds: the natural seconds before the
// hit that play 1:1 at the end of the descent (arrival_curve_progress).
Arrival_Curve :: struct {
	samples:                                                         [ARRIVAL_CURVE_INTERVALS + 1]Arrival_Curve_Sample,
	range_metres, natural_seconds, real_seconds, peak_progress, hit_heat_share: f32,
	reached_floor:                                                   bool,
}

// 0 at or above the top, else exp(-altitude / scale height).
arrival_atmosphere_density :: proc(altitude_metres: f64, atmosphere: Atmosphere_Config) -> f64 {
	if altitude_metres >= f64(atmosphere.top_metres) {
		return 0
	}
	return math.exp(-max(altitude_metres, 0) / f64(atmosphere.scale_height_metres))
}

arrival_curve_start :: proc(config: Game_Config) -> Arrival_Curve_State {
	angle := f64(config.arrival_entry_angle_degrees) * math.RAD_PER_DEG
	speed := f64(config.arrival_entry_speed_metres_per_second)
	return {position = {0, f64(config.arrival_start_metres)}, velocity = speed * [2]f64{math.cos(angle), -math.sin(angle)}}
}

// One semi-implicit Euler step: the velocity first, then the position.
arrival_curve_step :: proc(state: Arrival_Curve_State, drag_per_metre: f64, atmosphere: Atmosphere_Config) -> Arrival_Curve_State {
	density := arrival_atmosphere_density(state.position.y, atmosphere)
	acceleration := [2]f64{0, -ARRIVAL_GRAVITY_METRES_PER_SECOND_SQUARED} - drag_per_metre * density * linalg.length(state.velocity) * state.velocity
	next := state
	next.velocity += acceleration * ARRIVAL_CURVE_STEP_SECONDS
	next.position += next.velocity * ARRIVAL_CURVE_STEP_SECONDS
	next.seconds += ARRIVAL_CURVE_STEP_SECONDS
	return next
}

arrival_curve_lerp :: proc(before, after: Arrival_Curve_State, share: f64) -> Arrival_Curve_State {
	return {
		seconds  = before.seconds * (1 - share) + after.seconds * share,
		position = before.position * (1 - share) + after.position * share,
		velocity = before.velocity * (1 - share) + after.velocity * share,
	}
}

arrival_curve_sample_of :: proc(state: Arrival_Curve_State) -> Arrival_Curve_Sample {
	return {along_metres = f32(state.position.x), altitude_metres = f32(state.position.y), velocity = {f32(state.velocity.x), f32(state.velocity.y)}}
}

// Pass 1 finds the hit (the step crossing altitude 0, lerped to exactly
// 0); pass 2 repeats the same steps and fills the samples; then the heat,
// the density times the speed cubed over its peak, less the threshold.
build_arrival_curve :: proc(config: Game_Config) -> Arrival_Curve {
	curve := Arrival_Curve{real_seconds = f32(config.arrival_real_seconds)}
	terminal := f64(config.arrival_terminal_speed_metres_per_second)
	drag_per_metre := ARRIVAL_GRAVITY_METRES_PER_SECOND_SQUARED / (terminal * terminal)
	start := arrival_curve_start(config)
	before, after := start, start
	for after.position.y > 0 {
		if after.seconds > ARRIVAL_CURVE_MAXIMUM_SECONDS {
			return curve
		}
		before = after
		after = arrival_curve_step(before, drag_per_metre, config.atmosphere)
	}
	end := arrival_curve_lerp(before, after, before.position.y / (before.position.y - after.position.y))
	end.position.y = 0
	curve.reached_floor = true
	curve.natural_seconds = f32(end.seconds)
	curve.range_metres = f32(end.position.x)
	before, after = start, start
	for index in 0 ..< ARRIVAL_CURVE_INTERVALS {
		at := f64(index) * end.seconds / ARRIVAL_CURVE_INTERVALS
		for after.seconds < at {
			before = after
			after = arrival_curve_step(before, drag_per_metre, config.atmosphere)
		}
		share := after.seconds == before.seconds ? 0 : (at - before.seconds) / (after.seconds - before.seconds)
		curve.samples[index] = arrival_curve_sample_of(arrival_curve_lerp(before, after, share))
	}
	curve.samples[ARRIVAL_CURVE_INTERVALS] = arrival_curve_sample_of(end)
	fill_arrival_curve_heat(&curve, config)
	return curve
}

// raw_i = density * |velocity|^3, normalised to its peak and lifted over
// arrival_heat_threshold_percent; the peak sample is exactly 1.
fill_arrival_curve_heat :: proc(curve: ^Arrival_Curve, config: Game_Config) {
	raw: [ARRIVAL_CURVE_INTERVALS + 1]f64
	peak: f64 = 0
	peak_index := 0
	for sample, index in curve.samples {
		speed := linalg.length([2]f64{f64(sample.velocity.x), f64(sample.velocity.y)})
		raw[index] = arrival_atmosphere_density(f64(sample.altitude_metres), config.atmosphere) * speed * speed * speed
		if raw[index] > peak {
			peak, peak_index = raw[index], index
		}
	}
	if peak <= 0 {
		return
	}
	threshold := f64(config.arrival_heat_threshold_percent) / 100
	curve.peak_progress = f32(peak_index) / ARRIVAL_CURVE_INTERVALS
	curve.hit_heat_share = f32(raw[ARRIVAL_CURVE_INTERVALS] / peak)
	for &sample, index in curve.samples {
		sample.heat = f32(clamp((raw[index] / peak - threshold) / (1 - threshold), 0, 1))
	}
}

// The curve's progress (of its natural time) at progress of a descent of
// descent_seconds: the last real_seconds play 1:1 at its end, the natural
// time before them stretched over the rest. A descent or a curve not
// longer than real_seconds (a saved fall shorter than the config's)
// stretches uniformly.
arrival_curve_progress :: proc(curve: ^Arrival_Curve, progress, descent_seconds: f32) -> f32 {
	descent_progress := clamp(progress, 0, 1)
	real := curve.real_seconds
	if real >= descent_seconds || real >= curve.natural_seconds || curve.natural_seconds <= 0 {
		return descent_progress
	}
	if descent_progress >= 1 {
		return 1
	}
	split := 1 - real / descent_seconds
	stretched := curve.natural_seconds - real
	if descent_progress <= split {
		return descent_progress / split * stretched / curve.natural_seconds
	}
	return min((stretched + (descent_progress - split) * descent_seconds) / curve.natural_seconds, 1)
}

// Every field lerped between the two samples neighbouring progress
// (clamped to 0 to 1); progress 1 is the last sample exactly.
arrival_curve_at :: proc(curve: ^Arrival_Curve, progress: f32) -> Arrival_Curve_Sample {
	at := clamp(progress, 0, 1) * ARRIVAL_CURVE_INTERVALS
	index := min(int(at), ARRIVAL_CURVE_INTERVALS - 1)
	share := at - f32(index)
	before, after := curve.samples[index], curve.samples[index + 1]
	return {
		along_metres    = before.along_metres * (1 - share) + after.along_metres * share,
		altitude_metres = before.altitude_metres * (1 - share) + after.altitude_metres * share,
		velocity        = before.velocity * (1 - share) + after.velocity * share,
		heat            = before.heat * (1 - share) + after.heat * share,
	}
}
