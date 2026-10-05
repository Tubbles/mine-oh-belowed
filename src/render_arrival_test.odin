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
	late := arrival_view(falling, descent - 1, 0, config, &curve)
	testing.expect_value(t, late.phase, Arrival_Phase.Descent)
	testing.expect_value(t, late.heat, 0)
	hit := arrival_view(falling, descent, 0, config, &curve)
	testing.expect_value(t, hit.phase, Arrival_Phase.Settled)
	testing.expect_value(t, hit.seconds_since_hit, 0)
	testing.expect_value(t, arrival_view(landed, u64(config.arrival_ticks), 0, config, &curve).phase, Arrival_Phase.Settled)
	testing.expect_value(t, arrival_view(landed, descent + 240, 0, config, &curve).phase, Arrival_Phase.Settled)
	settled_ticks := u64(arrival_settled_seconds(config) * f32(config.tick_rate))
	testing.expect_value(t, arrival_view(landed, descent + settled_ticks - 1, 0, config, &curve).phase, Arrival_Phase.Settled)
	testing.expect_value(t, arrival_view(landed, descent + settled_ticks, 0, config, &curve).phase, Arrival_Phase.None)
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

// Work item 0270: rest_share stays 0 up to the descent's last real
// seconds, never falls and reaches 1 at its end; at progress 0 the pod's
// up runs against the travel, the travel heading onto the travel's
// normal and the door's axis kept; at the descent's last moment the
// transform takes the frame's axes to the rest pose's and the base
// centre to itself; identity in Settled and None.
@(test)
test_the_drawn_attitude_follows_the_tangent_then_rests :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	curve := build_arrival_curve(config)
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	place_test_pod(&entities, machines)
	pod, frame, _ := find_pod(&entities, machines)
	machine := machines.machines[pod.machine]
	tilt := 15
	falling := Field_Arrival{start_tick = 0, fall_ticks = u64(config.arrival_ticks)}
	descent := u64(config.arrival_ticks - config.arrival_settle_ticks)
	easing := descent - u64(config.arrival_real_seconds * config.tick_rate)
	before: f32 = 0
	for tick in 0 ..< descent {
		share := arrival_view(falling, tick, 0, config, &curve).rest_share
		if tick <= easing {
			testing.expectf(t, share == 0, "tick %d: the rest's share is %v before the last real seconds", tick, share)
		}
		testing.expectf(t, share >= before, "tick %d: the rest's share falls to %v", tick, share)
		before = share
	}
	last := arrival_view(falling, descent - 1, 0.9999, config, &curve)
	testing.expectf(t, last.rest_share > 0.9999, "the rest's share ends at %v", last.rest_share)

	up := unit_vector_to_f32(frame.axes[FRAME_UP])
	heading := unit_vector_to_f32(pod_travel_heading(frame, pod, machine))
	forward := unit_vector_to_f32(frame.axes[FRAME_FORWARD])
	start := arrival_view(falling, 0, 0, config, &curve)
	_, rotation, travel := arrival_pod_transform(start, frame, pod, machine, tilt, &curve)
	normal := linalg.normalize(heading - travel * linalg.dot(heading, travel))
	testing.expectf(t, linalg.length(rotation * up + travel) < 1e-4, "the up turns to %v, not against the travel %v", rotation * up, travel)
	testing.expectf(t, linalg.length(rotation * heading - normal) < 1e-4, "the travel heading turns to %v, not %v", rotation * heading, normal)
	testing.expectf(t, linalg.length(rotation * forward - forward) < 1e-4, "the door's axis turns to %v", rotation * forward)

	transform, _, _ := arrival_pod_transform(last, frame, pod, machine, tilt, &curve)
	_, rest_axes := pod_rest_pose(frame, pod, machine, tilt)
	turn := cast(matrix[3, 3]f32)transform
	for axis in 0 ..< 3 {
		turned := turn * unit_vector_to_f32(frame.axes[axis])
		testing.expectf(t, linalg.length(turned - unit_vector_to_f32(rest_axes[axis])) < 1e-3, "axis %d turns to %v, not the rest's %v", axis, turned, unit_vector_to_f32(rest_axes[axis]))
	}
	base := world_position_to_metres(pod_base_centre(frame, pod))
	testing.expectf(t, linalg.length(transform_point(transform, base) - base) < 0.001, "the base centre moves %v", transform_point(transform, base) - base)

	identity := linalg.MATRIX4F32_IDENTITY
	for view in ([2]Arrival_View{{phase = .Settled}, {}}) {
		still, still_rotation, still_travel := arrival_pod_transform(view, frame, pod, machine, tilt, &curve)
		testing.expect(t, still == identity && still_rotation == linalg.MATRIX3F32_IDENTITY && still_travel == {}, "not the identity outside the descent")
	}
}

// Work item 0270: a light moved by a rotation and a translation moves its
// position, and a point inside its old clip box, moved alike, lies inside
// the new box as far as before.
@(test)
test_a_moved_light_keeps_its_clip_box :: proc(t: ^testing.T) {
	box := linalg.matrix4_scale_f32({0.5, 0.25, 1}) * linalg.matrix4_translate_f32({-3, -40, 2})
	light := Point_Light{position = {3, 41, -2}, color = {1, 1, 1}, radius = 4, clip_box = box}
	transform := linalg.matrix4_translate_f32({10, -200, 7}) * linalg.matrix4_rotate_f32(0.4, linalg.normalize([3]f32{0.3, 1, -0.2}))
	moved := moved_point_light(light, transform)
	testing.expect(t, linalg.length(moved.position - transform_point(transform, light.position)) < 1e-4, "the light's position moves")
	moved_box, clipped := moved.clip_box.?
	testing.expect(t, clipped)
	inside := [3]f32{3.8, 42.5, -2.6}
	testing.expect(t, clip_box_reach(box, inside) <= 1, "the point lies in the old box")
	testing.expectf(t, abs(clip_box_reach(moved_box, transform_point(transform, inside)) - clip_box_reach(box, inside)) < 1e-3, "the moved point reaches %v in the new box", clip_box_reach(moved_box, transform_point(transform, inside)))
}

// Work items 0273 and 0286: each porthole's light follows the heat (none
// at heat 0 or once settled), in the haze mixed with the ablator's share
// times the flicker and the gain, inset into the cabin along the normal
// and clipped to the pod. At the flicker's mean its hue is that mix, at
// the highest half way to white.
@(test)
test_the_window_light_follows_the_heat :: proc(t: ^testing.T) {
	machine: Machine
	machine.windows[0] = {centre = {1, 2, 0.5}, normal = {1, 0, 0}, radius = 0.3}
	machine.windows[1] = {centre = {-1, 2, 0.5}, normal = {0, 0, -1}, radius = 0.3}
	machine.window_count = 2
	plasma := shipped_arrival_config().arrival_plasma
	body: matrix[4, 4]f32 = 1
	clip_box := linalg.matrix4_scale_f32({0.5, 0.5, 0.5})
	flickers: [MAXIMUM_POD_WINDOWS]f32
	for &flicker in flickers {
		flicker = FIRE_FLICKER_MEAN
	}
	_, dark := arrival_window_lights({phase = .Descent, heat = 0}, body, 1000, machine, clip_box, plasma, flickers)
	testing.expect_value(t, dark, 0)
	_, settled := arrival_window_lights({phase = .Settled, heat = 1}, body, 1000, machine, clip_box, plasma, flickers)
	testing.expect_value(t, settled, 0)
	haze, ablator := arrival_plasma_color(plasma.haze_color), arrival_plasma_color(plasma.ablator_color)
	mixed := haze * (1 - ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE) + ablator * ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE
	half, half_count := arrival_window_lights({phase = .Descent, heat = 0.5}, body, 1000, machine, clip_box, plasma, flickers)
	full, full_count := arrival_window_lights({phase = .Descent, heat = 1}, body, 1000, machine, clip_box, plasma, flickers)
	testing.expect_value(t, half_count, 2)
	testing.expect_value(t, full_count, 2)
	for index in 0 ..< 2 {
		window := machine.windows[index]
		testing.expectf(t, linalg.length(half[index].color - mixed * 0.5 * FIRE_FLICKER_MEAN * ARRIVAL_WINDOW_LIGHT_GAIN) < 1e-5, "window %d at heat 0.5 is %v", index, half[index].color)
		testing.expectf(t, linalg.length(full[index].color - mixed * FIRE_FLICKER_MEAN * ARRIVAL_WINDOW_LIGHT_GAIN) < 1e-5, "window %d at heat 1 is %v", index, full[index].color)
		testing.expectf(t, linalg.length(full[index].color - 2 * half[index].color) < 1e-5, "window %d is not twice as bright at heat 1", index)
		inset := window.centre + window.normal * ARRIVAL_WINDOW_LIGHT_INSET_CELLS
		testing.expectf(t, linalg.length(full[index].position - inset) < 1e-5, "window %d's light lies at %v", index, full[index].position)
		_, clipped := full[index].clip_box.?
		testing.expectf(t, clipped, "window %d's light is not clipped", index)
	}
	for &flicker in flickers {
		flicker = FIRE_FLICKER_HIGHEST
	}
	flare, _ := arrival_window_lights({phase = .Descent, heat = 1}, body, 1000, machine, clip_box, plasma, flickers)
	whitened := (mixed + ARRIVAL_WINDOW_WHITE_LIGHT) * 0.5
	testing.expectf(t, linalg.length(flare[0].color - whitened * FIRE_FLICKER_HIGHEST * ARRIVAL_WINDOW_LIGHT_GAIN) < 1e-5, "the flare's light is %v", flare[0].color)
}

// Work items 0273 and 0286: each porthole's flicker is the shared fire
// flicker at its own salt (its statistics are render_flames_test's),
// holds its mean under reduced motion, and the windows flicker apart.
@(test)
test_the_window_flicker_has_no_period :: proc(t: ^testing.T) {
	ticks := shipped_arrival_config().arrival_ticks
	salt := u64(DEFAULT_WORLD_SEED)
	series: [5][]f32
	for window in 0 ..< 5 {
		series[window] = make([]f32, ticks, context.temp_allocator)
		for tick in 0 ..< ticks {
			seconds := f32(tick) / 60
			series[window][tick] = arrival_window_flicker(seconds, window, salt, false)
			if tick % 60 == 0 {
				testing.expectf(t, series[window][tick] == fire_flicker(f64(seconds), salt + 20 + 2 * u64(window), false), "window %d at tick %d is not the fire flicker", window, tick)
				testing.expectf(t, arrival_window_flicker(seconds, window, salt, true) == FIRE_FLICKER_MEAN, "window %d at tick %d is not the mean under reduced motion", window, tick)
			}
		}
	}
	for first in 0 ..< 5 {
		pairs := mean_pair_difference(series[first])
		for second in first + 1 ..< 5 {
			apart: f64
			for tick in 0 ..< ticks {
				apart += f64(abs(series[first][tick] - series[second][tick]))
			}
			apart /= f64(ticks)
			testing.expectf(t, f32(apart) >= 0.6 * pairs, "windows %d and %d differ by %v, the first's pairs by %v", first, second, apart, pairs)
		}
	}
	flickers := arrival_window_flickers(2, 5, salt, false)
	for window in 0 ..< 5 {
		testing.expect_value(t, flickers[window], arrival_window_flicker(2, window, salt, false))
	}
}

// Work item 0273: the soot is 0 up to the heat's peak, never falls, is 1
// from the heat's end, through the settle and for good after it; a skip
// keeps what its fall had reached; no fall has none.
@(test)
test_the_soot_grows_after_the_peak_and_stays :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	curve := build_arrival_curve(config)
	testing.expect(t, curve.heat_out_progress > curve.peak_progress)
	descent := u64(config.arrival_ticks - config.arrival_settle_ticks)
	falling := Field_Arrival{start_tick = 0, fall_ticks = u64(config.arrival_ticks)}
	before: f32 = 0
	out_tick: u64 = 0
	for tick in 0 ..< descent {
		view := arrival_view(falling, tick, 0, config, &curve)
		if view.curve_progress <= curve.peak_progress {
			testing.expectf(t, view.soot == 0, "tick %d before the peak has soot %v", tick, view.soot)
		}
		if view.curve_progress >= curve.heat_out_progress {
			testing.expectf(t, view.soot == 1, "tick %d after the heat's end has soot %v", tick, view.soot)
			if out_tick == 0 {
				out_tick = tick
			}
		}
		testing.expectf(t, view.soot >= before, "tick %d: the soot falls to %v", tick, view.soot)
		before = view.soot
	}
	testing.expect(t, out_tick > 0, "the heat is out before the hit")
	landed := falling
	landed.landed_tick = u64(config.arrival_ticks)
	for tick in ([3]u64{descent, descent + 240, 100000}) {
		testing.expectf(t, arrival_view(landed, tick, 0, config, &curve).soot == 1, "tick %d has soot %v", tick, arrival_view(landed, tick, 0, config, &curve).soot)
	}
	testing.expect_value(t, arrival_view(landed, descent + 240, 0, config, &curve).phase, Arrival_Phase.Settled)
	early := falling
	early.landed_tick = 101
	testing.expect_value(t, arrival_view(early, 101, 0, config, &curve).soot, 0)
	testing.expect_value(t, arrival_view(early, 100000, 0, config, &curve).soot, 0)
	late := falling
	late.landed_tick = out_tick + 1
	late_view := arrival_view(late, 100000, 0, config, &curve)
	testing.expect_value(t, late_view.phase, Arrival_Phase.None)
	testing.expect_value(t, late_view.soot, 1)
	testing.expect_value(t, arrival_view({}, 100000, 0, config, &curve).soot, 0)
}

// Work item 0273: the travel laid on the glass is unit, {0, 1} along the
// fallback's own direction and for a travel along the normal.
@(test)
test_the_travel_lies_on_the_glass :: proc(t: ^testing.T) {
	normal := linalg.normalize([3]f32{-0.755, -0.490, 0.436})
	fallback := [3]f32{0, 1, 0}
	slanted := arrival_travel_on_glass(normal, linalg.normalize([3]f32{0.1, -1, 0.3}), fallback)
	testing.expectf(t, abs(linalg.length(slanted) - 1) < 1e-5, "the laid travel %v is not unit", slanted)
	own := arrival_travel_on_glass(normal, fallback, fallback)
	testing.expectf(t, linalg.length(own - [2]f32{0, 1}) < 1e-5, "the fallback's own direction lies at %v", own)
	head_on := arrival_travel_on_glass(normal, normal, fallback)
	testing.expect_value(t, head_on, [2]f32{0, 1})
	across := linalg.cross(normal, linalg.normalize(fallback - normal * linalg.dot(fallback, normal)))
	sideways := arrival_travel_on_glass(normal, across, fallback)
	testing.expectf(t, linalg.length(sideways - [2]f32{1, 0}) < 1e-5, "the quad's across lies at %v", sideways)
}

// Work item 0273: a porthole facing along the pod's up lays its quad and
// flow along the pod's forward, finite and in the glass's plane, where
// the up alone would normalise a zero vector.
@(test)
test_a_porthole_facing_up_lays_along_the_forward :: proc(t: ^testing.T) {
	up, forward := [3]f32{0, 1, 0}, [3]f32{0, 0, 1}
	axis := arrival_glass_axis(up, up, forward)
	testing.expectf(t, linalg.length(axis - forward) < 1e-5, "the axis is %v", axis)
	slanted := linalg.normalize([3]f32{0.3, 1, 0.2})
	testing.expectf(t, abs(linalg.dot(arrival_glass_axis(slanted, up, forward), slanted)) < 1e-5, "the axis leaves the glass")
	corners := arrival_window_corners({1, 2, 3}, up, axis, axis, 0.4)
	for corner, index in corners {
		finite := !math.is_nan(corner.x) && !math.is_nan(corner.y) && !math.is_nan(corner.z)
		testing.expectf(t, finite, "corner %d is %v", index, corner)
		testing.expectf(t, abs(corner.y - 2) < 1e-5, "corner %d leaves the glass", index)
	}
	flow := arrival_travel_on_glass(up, linalg.normalize([3]f32{1, -1, 0}), axis)
	testing.expectf(t, !math.is_nan(flow.x) && !math.is_nan(flow.y) && abs(linalg.length(flow) - 1) < 1e-5, "the flow is %v", flow)
}
