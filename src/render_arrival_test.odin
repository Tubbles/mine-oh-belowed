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
