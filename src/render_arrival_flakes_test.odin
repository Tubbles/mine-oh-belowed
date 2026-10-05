package game

import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:testing"

// The heat shield's flakes (work item 0290), pure: the path, the
// births, the cap and the crossing of the chair's porthole.

FLAKE_TEST_SALT :: 1234

// The shipped fall: its config, its curve, the falling arrival and the
// descent's ticks.
Flake_Test_Fall :: struct {
	config:  Game_Config,
	curve:   Arrival_Curve,
	falling: Field_Arrival,
	descent: u64,
}

flake_test_fall :: proc() -> Flake_Test_Fall {
	config := shipped_arrival_config()
	return {
		config = config,
		curve = build_arrival_curve(config),
		falling = {start_tick = 0, fall_ticks = u64(config.arrival_ticks)},
		descent = u64(config.arrival_ticks - config.arrival_settle_ticks),
	}
}

// The flakes' source of the shipped pod on the fall.
flake_test_source :: proc(fall: ^Flake_Test_Fall, pod: Machine) -> Arrival_Flake_Source {
	view := arrival_view(fall.falling, 0, 0, fall.config, &fall.curve)
	return arrival_flake_source(&fall.curve, view, fall.config, pod, FLAKE_TEST_SALT)
}

// The view's seconds at the heat's peak tick.
flake_test_peak_seconds :: proc(fall: ^Flake_Test_Fall) -> f32 {
	peak_tick: u64 = 0
	peak_heat: f32 = 0
	for tick in 0 ..< fall.descent {
		if heat := arrival_view(fall.falling, tick, 0, fall.config, &fall.curve).heat; heat > peak_heat {
			peak_tick, peak_heat = tick, heat
		}
	}
	return arrival_view(fall.falling, peak_tick, 0, fall.config, &fall.curve).seconds
}

// A flake's slot at seconds.
flake_test_slot :: proc(seconds: f32) -> int {
	return int(math.floor(seconds / ARRIVAL_FLAKE_SLOT_SECONDS))
}

// The indices of every candidate of slots first to last that is alive
// at age seconds after its birth, in the temp allocator.
flake_test_alive_at_age :: proc(first, last: int, age: f32, source: Arrival_Flake_Source) -> []int {
	indices := make([dynamic]int, context.temp_allocator)
	for index in first * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT ..< (last + 1) * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT {
		if arrival_flake(index, arrival_flake_birth_seconds(index, source.salt) + age, source).alive {
			append(&indices, index)
		}
	}
	return indices[:]
}

// A flake's velocity relative to the pod at age, by central difference.
flake_test_velocity :: proc(index: int, age: f32, source: Arrival_Flake_Source) -> [3]f32 {
	step: f32 = 0.001
	birth := arrival_flake_birth_seconds(index, source.salt)
	before := arrival_flake(index, birth + age - step, source).position
	after := arrival_flake(index, birth + age + step, source).position
	return (after - before) / (2 * step)
}

FLAKE_TEST_AIR :: [3]f32{0, ARRIVAL_FLAKE_AIR_CELLS_PER_SECOND, 0}

@(test)
test_a_flake_is_a_pure_function_of_its_index_and_the_seed :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	other := source
	other.salt = FLAKE_TEST_SALT + 1
	peak := flake_test_peak_seconds(&fall)
	last := flake_test_slot(peak)
	alive, differ := 0, 0
	for index in (last - ARRIVAL_FLAKE_SLOTS_BACK) * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT ..< (last + 1) * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT {
		first := arrival_flake(index, peak, source)
		testing.expect_value(t, arrival_flake(index, peak, source), first)
		if !first.alive {
			continue
		}
		alive += 1
		changed := arrival_flake(index, peak, other)
		if !changed.alive || changed.position != first.position {
			differ += 1
		}
	}
	testing.expectf(t, alive > 0, "no flake lives at the peak")
	testing.expectf(t, differ * 2 >= alive, "%d of %d flakes differ with another salt", differ, alive)
}

@(test)
test_a_flake_leaves_the_rim_with_the_pods_velocity :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	middle := flake_test_slot(flake_test_peak_seconds(&fall))
	indices := flake_test_alive_at_age(middle - 100, middle + 99, 0.001, source)
	testing.expectf(t, len(indices) > 20, "%d flakes born round the peak", len(indices))
	for index in indices {
		birth := arrival_flake_birth_seconds(index, source.salt)
		start := arrival_flake(index, birth + 0.001, source).position
		testing.expectf(t, abs(linalg.length(start.xz) - 5.45) < 0.01, "flake %d starts %v from the axis", index, linalg.length(start.xz))
		testing.expectf(t, start.y >= 0 && start.y <= 0.2, "flake %d starts at y %v", index, start.y)
		velocity := (arrival_flake(index, birth + 0.011, source).position - start) / 0.01
		testing.expectf(t, velocity.y < 0.1 && linalg.length(velocity) < 1.8, "flake %d leaves at %v", index, velocity)
	}
}

@(test)
test_a_flake_bleeds_its_speed_over_about_a_second :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	middle := flake_test_slot(flake_test_peak_seconds(&fall))
	indices := flake_test_alive_at_age(middle - 100, middle + 99, 1.0, source)
	testing.expectf(t, len(indices) > 20, "%d flakes live a second round the peak", len(indices))
	air := FLAKE_TEST_AIR
	for index in indices {
		at_birth := linalg.length(flake_test_velocity(index, 0.002, source) - air)
		relative := flake_test_velocity(index, 1.0, source)
		share := linalg.length(relative - air) / at_birth
		testing.expectf(t, share >= 0.25 && share <= 0.5, "flake %d keeps %v of its speed against the air after a second", index, share)
		testing.expectf(t, relative.y >= 0.5 * air.y && relative.y <= 0.75 * air.y, "flake %d drifts aft at %v", index, relative.y)
		birth := arrival_flake_birth_seconds(index, source.salt)
		previous := arrival_flake(index, birth, source).position.y
		for step := 1; ; step += 1 {
			flake := arrival_flake(index, birth + f32(step) / 60, source)
			if !flake.alive {
				break
			}
			testing.expectf(t, flake.position.y > previous, "flake %d sinks at step %d", index, step)
			previous = flake.position.y
		}
	}
}

@(test)
test_the_streak_trails_against_the_air :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	middle := flake_test_slot(flake_test_peak_seconds(&fall))
	indices := flake_test_alive_at_age(middle - 100, middle + 99, 1.0, source)
	testing.expect(t, len(indices) > 20)
	for index in indices {
		birth := arrival_flake_birth_seconds(index, source.salt)
		for age in ([3]f32{0.1, 0.5, 1.0}) {
			flake := arrival_flake(index, birth + age, source)
			against_air := flake_test_velocity(index, age, source) - FLAKE_TEST_AIR
			speed := linalg.length(against_air)
			testing.expectf(t, linalg.dot(flake.streak, against_air) / speed < -0.99, "flake %d at %v: the streak %v runs with %v", index, age, flake.streak, against_air)
			testing.expectf(t, flake.streak.y > 0.9, "flake %d at %v: the streak %v leans", index, age, flake.streak)
			expected := ARRIVAL_FLAKE_STREAK_SECONDS * speed
			testing.expectf(t, abs(flake.streak_cells - expected) <= 0.02 * expected, "flake %d at %v: the streak is %v, not %v", index, age, flake.streak_cells, expected)
		}
	}
}

@(test)
test_no_flake_outside_the_heating :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	first_heated, last_heated: u64 = 0, 0
	found := false
	for tick in 0 ..< fall.descent {
		if arrival_view(fall.falling, tick, 0, fall.config, &fall.curve).heat > 0 {
			if !found {
				first_heated = tick
			}
			last_heated, found = tick, true
		}
	}
	testing.expect(t, found)
	cleared := last_heated + 2 * u64(fall.config.tick_rate)
	for tick in 0 ..< fall.descent {
		if tick >= first_heated && tick < cleared {
			continue
		}
		_, count := arrival_flakes(arrival_view(fall.falling, tick, 0, fall.config, &fall.curve), source, false)
		testing.expectf(t, count == 0, "%d flakes at tick %d", count, tick)
	}
	peak := flake_test_peak_seconds(&fall)
	peak_view := Arrival_View{phase = .Descent, seconds = peak, descent_seconds = source.descent_seconds}
	_, at_peak := arrival_flakes(peak_view, source, false)
	testing.expectf(t, at_peak > 0, "no flakes at the peak")
	_, settled := arrival_flakes({phase = .Settled, seconds = peak}, source, false)
	_, none := arrival_flakes({}, source, false)
	_, calm := arrival_flakes(peak_view, source, true)
	no_rate := source
	no_rate.flakes_per_second = 0
	_, rateless := arrival_flakes(peak_view, no_rate, false)
	no_shield := source
	no_shield.shield_radius = 0
	_, shieldless := arrival_flakes(peak_view, no_shield, false)
	testing.expect_value(t, settled, 0)
	testing.expect_value(t, none, 0)
	testing.expect_value(t, calm, 0)
	testing.expect_value(t, rateless, 0)
	testing.expect_value(t, shieldless, 0)
}

// Also the cost: a frame evaluates exactly MAXIMUM_ARRIVAL_FLAKES
// candidates and draws at most that many quads.
@(test)
test_the_live_flakes_stay_under_the_cap :: proc(t: ^testing.T) {
	testing.expect_value(t, MAXIMUM_ARRIVAL_FLAKES, 205)
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	largest := 0
	for tick in 0 ..< fall.descent {
		_, count := arrival_flakes(arrival_view(fall.falling, tick, 0, fall.config, &fall.curve), source, false)
		testing.expectf(t, count <= MAXIMUM_ARRIVAL_FLAKES, "%d flakes at tick %d", count, tick)
		largest = max(largest, count)
	}
	testing.expectf(t, largest >= 40 && largest <= 160, "at most %d flakes live at once", largest)
}

@(test)
test_a_flake_never_enters_the_hull :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	for tick in 0 ..< fall.descent {
		flakes, count := arrival_flakes(arrival_view(fall.falling, tick, 0, fall.config, &fall.curve), source, false)
		for flake in flakes[:count] {
			testing.expectf(t, linalg.length(flake.position.xz) >= 5.45 - 1e-4, "tick %d: a flake lies %v from the axis", tick, linalg.length(flake.position.xz))
		}
	}
}

@(test)
test_the_heat_at_seconds_is_the_views :: proc(t: ^testing.T) {
	fall := flake_test_fall()
	descent_seconds: f32 = 0
	for tick := u64(0); tick < fall.descent; tick += 10 {
		view := arrival_view(fall.falling, tick, 0, fall.config, &fall.curve)
		descent_seconds = view.descent_seconds
		heat := arrival_heat_at_seconds(&fall.curve, view.seconds, view.descent_seconds)
		testing.expectf(t, abs(heat - view.heat) < 1e-4, "tick %d: the heat is %v, the view's %v", tick, heat, view.heat)
	}
	testing.expectf(t, abs(descent_seconds - 30) < 1e-4, "the descent lasts %v s", descent_seconds)
	testing.expect_value(t, arrival_heat_at_seconds(&fall.curve, -1, descent_seconds), 0)
	testing.expect_value(t, arrival_heat_at_seconds(&fall.curve, descent_seconds, descent_seconds), 0)
}

@(test)
test_the_flake_quad_faces_the_eye :: proc(t: ^testing.T) {
	axis := [3]f32{0, 1, 0}
	eye := [3]f32{3, 1, 0}
	corners := arrival_flake_corners({}, axis, eye, 0.1, 0.5)
	testing.expect(t, linalg.length((corners[0] + corners[1]) / 2 - (-axis * 0.1)) < 1e-6)
	testing.expect(t, linalg.length((corners[2] + corners[3]) / 2 - axis * 0.5) < 1e-6)
	edge := corners[1] - corners[0]
	testing.expect(t, abs(linalg.dot(edge, axis)) < 1e-6)
	testing.expect(t, abs(linalg.dot(edge, eye)) < 1e-6)
	testing.expect(t, abs(linalg.length(edge) - 0.2) < 1e-6)
	on_axis := arrival_flake_corners({}, axis, {0, 3, 0}, 0.1, 0.5)
	for corner in on_axis {
		testing.expectf(t, !math.is_nan(corner.x) && !math.is_nan(corner.y) && !math.is_nan(corner.z), "a corner is %v with the eye on the axis", corner)
	}
	short := arrival_flake_corners({}, axis, eye, 0.1, 0.02)
	testing.expect(t, linalg.length((short[2] + short[3]) / 2 - axis * 0.1) < 1e-6)
}

@(test)
test_the_flake_vertex_color_carries_its_values :: proc(t: ^testing.T) {
	flake := Arrival_Flake {
		brightness   = 1.2,
		flicker      = 1.5,
		size_cells   = 0.05,
		streak_cells = 0.15,
		whiteness    = 0.8,
		dark_core    = 1,
	}
	color := arrival_flake_vertex_color(flake)
	testing.expect_value(t, color.r, 230)
	testing.expect_value(t, color.g, 128)
	testing.expect_value(t, color.b, 204)
	testing.expect_value(t, color.a, 255)
	flake.dark_core = 0
	testing.expect_value(t, arrival_flake_vertex_color(flake).a, 0)
}

// Work item 0290, decision 2: only a head at or above
// ARRIVAL_FLAKE_DARK_CORE_CELLS shows a dark core, faded in and out with
// the flake, and some flakes at the peak are each.
@(test)
test_only_the_larger_flakes_show_a_dark_core :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	fall := flake_test_fall()
	source := flake_test_source(&fall, pod)
	middle := flake_test_slot(flake_test_peak_seconds(&fall))
	dark, bright := 0, 0
	for index in flake_test_alive_at_age(middle - 100, middle + 99, 0.5, source) {
		flake := arrival_flake(index, arrival_flake_birth_seconds(index, source.salt) + 0.5, source)
		if flake.size_cells >= ARRIVAL_FLAKE_DARK_CORE_CELLS {
			testing.expect_value(t, flake.dark_core, 1)
			dark += 1
		} else {
			testing.expect_value(t, flake.dark_core, 0)
			bright += 1
		}
		born := arrival_flake(index, arrival_flake_birth_seconds(index, source.salt), source)
		testing.expect_value(t, born.dark_core, 0)
	}
	testing.expectf(t, dark > 0 && bright > dark, "%d dark cored and %d bright flakes", dark, bright)
}

// Whether an eye sees a flake's head through a window: the segment
// crosses the pane's plane within 0.5 cells of its centre, the head lies
// beyond the pane, and nothing of the body stands between.
flake_test_seen_through :: proc(eye, head: [3]f32, window: Pod_Window, triangles: []Check_Triangle) -> bool {
	if linalg.dot(head - window.centre, window.normal) >= 0 {
		return false
	}
	towards := head - eye
	along := linalg.dot(window.centre - eye, window.normal) / linalg.dot(towards, window.normal)
	if !(along > 0 && along < 1) || linalg.length(eye + towards * along - window.centre) >= 0.5 {
		return false
	}
	return !segment_crosses_any_triangle(eye, head, triangles)
}

// Appends to runs the length in ticks of every run of consecutive ticks
// a flake of the source is seen from eye through window over the fall.
flake_test_porthole_runs :: proc(fall: ^Flake_Test_Fall, source: Arrival_Flake_Source, eye: [3]f32, window: Pod_Window, triangles: []Check_Triangle, runs: ^[dynamic]int) {
	running := make(map[int]int, context.temp_allocator)
	seen := make(map[int]bool, context.temp_allocator)
	for tick in 0 ..= fall.descent {
		seconds := arrival_view(fall.falling, tick, 0, fall.config, &fall.curve).seconds
		last := flake_test_slot(seconds)
		clear(&seen)
		if tick < fall.descent {
			for index in max(last - ARRIVAL_FLAKE_SLOTS_BACK, 0) * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT ..< (last + 1) * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT {
				flake := arrival_flake(index, seconds, source)
				if flake.alive && flake_test_seen_through(eye, flake.position, window, triangles) {
					seen[index] = true
				}
			}
		}
		for index, length in running {
			if !seen[index] {
				append(runs, length)
				delete_key(&running, index)
			}
		}
		for index in seen {
			running[index] = running[index] + 1
		}
	}
}

FLAKE_TEST_CROSSING_SALTS :: 8

// The footage's pieces cross the window in 4 to 6 frames at 30 fps, 8 to
// 12 ticks. A flake seen from the chair through its porthole (window 2,
// 0288) crosses in a median of 6 to 14 ticks, grazing passes shorter,
// pooled over FLAKE_TEST_CROSSING_SALTS worlds so one world's few
// crossings do not decide it.
@(test)
test_the_flakes_cross_the_chairs_porthole_as_in_the_footage :: proc(t: ^testing.T) {
	pod, triangles := shipped_pod_body()
	fall := flake_test_fall()
	eye := cabin_eyes(pod)[0]
	window := pod.windows[2]
	runs := make([dynamic]int, context.temp_allocator)
	for salt in 0 ..< FLAKE_TEST_CROSSING_SALTS {
		source := flake_test_source(&fall, pod)
		source.salt = FLAKE_TEST_SALT + u64(salt)
		flake_test_porthole_runs(&fall, source, eye, window, triangles[:], &runs)
	}
	testing.expectf(t, len(runs) >= 5, "%d flakes cross the chair's porthole", len(runs))
	if len(runs) == 0 {
		return
	}
	slice.sort(runs[:])
	median := runs[len(runs) / 2]
	testing.expectf(t, median >= 6 && median <= 14, "the median crossing lasts %d ticks (%v)", median, runs[:])
}

// The record's heat_shield radius is the body's widest corner at or
// under the rim's height.
@(test)
test_the_heat_shield_matches_the_model :: proc(t: ^testing.T) {
	pod, triangles := shipped_pod_body()
	testing.expect_value(t, pod.heat_shield, Pod_Heat_Shield_Definition{radius = 5.45, rim_height = 0.2})
	widest: f32 = 0
	for triangle in triangles {
		for corner in triangle.corners {
			if corner.y <= pod.heat_shield.rim_height + 0.01 {
				widest = max(widest, linalg.length(corner.xz))
			}
		}
	}
	testing.expectf(t, abs(widest - pod.heat_shield.radius) <= 0.01, "the body's rim reaches %v", widest)
}
