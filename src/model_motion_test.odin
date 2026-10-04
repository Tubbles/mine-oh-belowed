package game

import "core:fmt"
import "core:math"
import "core:strings"
import "core:testing"

// Motion and model light tests (work item 0056): pure procedures, no window.

MOTION_TEST_TOLERANCE :: 1e-5

expect_near_point :: proc(t: ^testing.T, got, expected: [3]f32, message: string, location := #caller_location) {
	for axis in 0 ..< 3 {
		if abs(got[axis] - expected[axis]) > MOTION_TEST_TOLERANCE {
			testing.expectf(t, false, "%s: got %v, expected %v", message, got, expected, loc = location)
			return
		}
	}
}

// A point of the model's frame through the part's pose.
posed_point :: proc(motion: Machine_Motion, footprint: [3]i32, phase: f32, point: [3]f32) -> [3]f32 {
	return (motion_transform(motion, footprint, phase) * [4]f32{point.x, point.y, point.z, 1}).xyz
}

@(test)
test_a_pump_strokes_along_its_axis_and_back :: proc(t: ^testing.T) {
	motion := Machine_Motion{kind = .Pump, axis = 1, amplitude = -0.25, period_seconds = 1}
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 0, {0, 1, 0}), {0, 1, 0}, "phase 0")
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 0.5, {0, 1, 0}), {0, 0.75, 0}, "phase 0.5")
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 1, {0, 1, 0}), {0, 1, 0}, "phase 1")
}

// Work item 0198: a slide moves its part by the open fraction, which a
// hatch's state and its last toggle give, eased over the period.
@(test)
test_a_slide_moves_its_part_by_the_open_fraction :: proc(t: ^testing.T) {
	motion := Machine_Motion{kind = .Slide, axis = 1, amplitude = 3.95, period_seconds = 0.8}
	expect_near_point(t, posed_point(motion, {1, 4, 2}, 0, {0, 1, 0}), {0, 1, 0}, "shut")
	expect_near_point(t, posed_point(motion, {1, 4, 2}, 0.5, {0, 1, 0}), {0, 2.975, 0}, "half open")
	expect_near_point(t, posed_point(motion, {1, 4, 2}, 1, {0, 1, 0}), {0, 4.95, 0}, "open")
	testing.expect_value(t, hatch_open_fraction(true, 0, 500, 0.5, 60, 0.8), 1)
	testing.expect_value(t, hatch_open_fraction(false, 0, 500, 0.5, 60, 0.8), 0)
	// Opened at tick 100 (stored 101): 0.8 s at 60 Hz is 48 ticks.
	testing.expect(t, math.abs(hatch_open_fraction(true, 101, 100, 0, 60, 0.8)) < MOTION_TEST_TOLERANCE)
	testing.expect(t, math.abs(hatch_open_fraction(true, 101, 124, 0, 60, 0.8) - 0.5) < MOTION_TEST_TOLERANCE)
	testing.expect_value(t, hatch_open_fraction(true, 101, 148, 0, 60, 0.8), 1)
	testing.expect_value(t, hatch_open_fraction(true, 101, 1000, 0.3, 60, 0.8), 1)
	previous := f32(-1)
	for tick in u64(100) ..= 150 {
		opening := hatch_open_fraction(true, 101, tick, 0, 60, 0.8)
		testing.expectf(t, opening >= previous, "tick %d: %f after %f", tick, opening, previous)
		testing.expect(t, math.abs(hatch_open_fraction(false, 101, tick, 0, 60, 0.8) - (1 - opening)) < MOTION_TEST_TOLERANCE)
		previous = opening
	}
}

@(test)
test_a_bob_moves_both_ways :: proc(t: ^testing.T) {
	motion := Machine_Motion{kind = .Bob, axis = 1, amplitude = 0.1, period_seconds = 1}
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 0, {}), {}, "phase 0")
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 0.25, {}), {0, 0.1, 0}, "phase 0.25")
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 0.5, {}), {}, "phase 0.5")
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 0.75, {}), {0, -0.1, 0}, "phase 0.75")
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 1, {}), {}, "phase 1")
}

@(test)
test_a_spin_turns_about_its_pivot :: proc(t: ^testing.T) {
	// A wheel about z through (1, 1.5) of a 2 by 2 by 2 footprint, which
	// is (0, 1.5) in the model's frame. A point one block right of it.
	motion := Machine_Motion{kind = .Spin, axis = 2, amplitude = 1, period_seconds = 1, pivot = {1, 1.5, 1}}
	point := [3]f32{1, 1.5, 0}
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 0, point), point, "phase 0")
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 0.25, point), {0, 2.5, 0}, "a quarter turn")
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 0.5, point), {-1, 1.5, 0}, "phase 0.5")
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 1, point), point, "phase 1")
	// The pivot stays put.
	expect_near_point(t, posed_point(motion, {2, 2, 2}, 0.3, {0, 1.5, 0.4}), {0, 1.5, 0.4}, "on the axis")
}

@(test)
test_a_swing_turns_there_and_back :: proc(t: ^testing.T) {
	// An inserter's arm about y through the block's centre, pointing at
	// the pickup side (-x) at rest: half a turn takes it over the right
	// side (+z) to the drop side (+x).
	motion := Machine_Motion{kind = .Swing, axis = 1, amplitude = 0.5, period_seconds = 1, pivot = {0.5, 0, 0.5}}
	tip := [3]f32{-0.4, 0.5, 0}
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 0, tip), tip, "phase 0")
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 0.25, tip), {0, 0.5, 0.4}, "half way over the right side")
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 0.5, tip), {0.4, 0.5, 0}, "phase 0.5")
	expect_near_point(t, posed_point(motion, {1, 1, 1}, 1, tip), tip, "phase 1")
}

@(test)
test_a_glow_moves_nothing_and_pulses :: proc(t: ^testing.T) {
	motion := Machine_Motion{kind = .Glow, period_seconds = 1}
	for phase in ([3]f32{0, 0.5, 1}) {
		expect_near_point(t, posed_point(motion, {2, 2, 2}, phase, {0.5, 1, 0.5}), {0.5, 1, 0.5}, "glow")
	}
	light := [3]f32{0.3, 0.25, 0.2}
	expect_near_point(t, emissive_brightness(.Glow, 0, true, light), 1, "glow at phase 0")
	expect_near_point(t, emissive_brightness(.Glow, 0.5, true, light), GLOW_MINIMUM_BRIGHTNESS, "glow at phase 0.5")
	expect_near_point(t, emissive_brightness(.Glow, 1, true, light), 1, "glow at phase 1")
	// Without a glow motion a working machine's glow is full.
	testing.expect_value(t, emissive_brightness(.Spin, 0.5, true, light), 1)
	testing.expect_value(t, emissive_brightness(.None, 0.5, true, light), 1)
	// An idle machine's glow is lit like the rest of it.
	testing.expect_value(t, emissive_brightness(.Glow, 0.5, false, light), light)
}

@(test)
test_an_idle_machine_rests :: proc(t: ^testing.T) {
	testing.expect_value(t, motion_phase(12345, 0.5, 60, 2, false), 0)
	for kind in Motion_Kind {
		motion := Machine_Motion{kind = kind, axis = 1, amplitude = 0.5, period_seconds = 1, pivot = {1, 1, 1}}
		expect_near_point(t, posed_point(motion, {2, 2, 2}, 0, {0.3, 0.7, -0.2}), {0.3, 0.7, -0.2}, "resting pose")
	}
}

@(test)
test_the_phase_follows_the_render_time :: proc(t: ^testing.T) {
	// A 2 second period at 60 ticks per second is 120 ticks.
	testing.expect_value(t, motion_phase(0, 0, 60, 2, true), 0)
	testing.expect_value(t, motion_phase(60, 0, 60, 2, true), 0.5)
	testing.expect_value(t, motion_phase(90, 0, 60, 2, true), 0.75)
	testing.expect_value(t, motion_phase(120, 0, 60, 2, true), 0)
	testing.expect(t, math.abs(motion_phase(59, 0.5, 60, 2, true) - 59.5 / 120) < MOTION_TEST_TOLERANCE)
	// A hundred days of play in, the phase stays exact enough.
	testing.expect(t, math.abs(motion_phase(518_400_030, 0.5, 60, 2, true) - 30.5 / 120) < 1e-4)
	testing.expect_value(t, motion_phase(60, 0, 60, 0, true), 0)
	// The entity's offset shifts a working machine only.
	testing.expect(t, math.abs(motion_phase(60, 0, 60, 2, true, 0.75) - 0.25) < MOTION_TEST_TOLERANCE)
	testing.expect_value(t, motion_phase(60, 0, 60, 2, false, 0.75), 0)
}

@(test)
test_each_origin_has_its_own_phase_offset :: proc(t: ^testing.T) {
	origins := [?]World_Coordinate{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {-5, 40, 12}, {-6, 40, 12}, {1000, -20, -3000}}
	for origin, index in origins {
		offset := motion_phase_offset(origin)
		testing.expectf(t, offset >= 0 && offset < 1, "%v: offset %v", origin, offset)
		testing.expect_value(t, motion_phase_offset(origin), offset)
		for other in origins[index + 1:] {
			testing.expectf(t, motion_phase_offset(other) != offset, "%v and %v share offset %v", origin, other, offset)
		}
	}
}

@(test)
test_the_light_tint_combines_sky_and_block_light :: proc(t: ^testing.T) {
	white := [3]f32{1, 1, 1}
	testing.expect_value(t, model_light_tint(pack_light(15, 0), 1, white), 1)
	testing.expect_value(t, model_light_tint(pack_light(15, 0), 0.2, white), 0.2)
	// Block light is not scaled by the day.
	testing.expect_value(t, model_light_tint(pack_light(0, 15), 0.2, white), 1)
	// A dark cave never goes below the minimum.
	testing.expect_value(t, model_light_tint(pack_light(0, 0), 1, white), MINIMUM_MODEL_BRIGHTNESS)
	// Level 12 of 15 is 0.8 / (4 - 2.4) = 0.5, like chunk.fs.
	expect_near_point(t, model_light_tint(pack_light(12, 0), 1, white), 0.5, "sky level 12")
	expect_near_point(t, model_light_tint(pack_light(12, 12), 0.5, white), 0.75, "sky and block level 12")
	// Sky and block light together stop at full brightness.
	testing.expect_value(t, model_light_tint(pack_light(15, 15), 1, white), 1)
}

// The sky tint colours the sky share only; block light stays white.
@(test)
test_the_sky_tint_colours_only_sky_light :: proc(t: ^testing.T) {
	tint := [3]f32{1, 0.5, 0.25}
	expect_near_point(t, model_light_tint(pack_light(15, 0), 1, tint), tint, "sky light only")
	expect_near_point(t, model_light_tint(pack_light(0, 12), 1, tint), 0.5, "block light only")
	expect_near_point(t, model_light_tint(pack_light(12, 12), 1, tint), {1, 0.75, 0.625}, "both")
}

// Coloured block light (work item 0072) tints a model per colour channel.
@(test)
test_the_light_tint_takes_the_block_light_colour :: proc(t: ^testing.T) {
	white := [3]f32{1, 1, 1}
	expect_near_point(t, model_light_tint(pack_light(0, {15, 0, 0}), 1, white), {1, MINIMUM_MODEL_BRIGHTNESS, MINIMUM_MODEL_BRIGHTNESS}, "red light")
	expect_near_point(t, model_light_tint(pack_light(12, {0, 12, 0}), 1, white), {0.5, 1, 0.5}, "sky and green light")
}

@(test)
test_the_light_comes_from_above_or_in_front :: proc(t: ^testing.T) {
	// Above the centre of a 3 by 2 by 3 machine.
	testing.expect_value(t, model_light_cell({origin = {10, 5, 20}, size = {3, 2, 3}}), World_Coordinate{11, 7, 21})
	// In front of a 1 by 1 machine at its base, even a tall one.
	testing.expect_value(t, model_light_cell({origin = {10, 5, 20}, size = {1, 3, 1}, rotation = 0}), World_Coordinate{11, 5, 20})
	testing.expect_value(t, model_light_cell({origin = {10, 5, 20}, size = {1, 1, 1}, rotation = 3}), World_Coordinate{10, 5, 19})
}

// Work item 0231: an iris draws its part once per blade, the k-th turned
// k / blades of a turn about the pivot, and opens every blade about its
// own pin by the amplitude times the fraction.
@(test)
test_an_iris_turns_each_blade_into_its_slot_and_opens_it_about_its_pin :: proc(t: ^testing.T) {
	motion := Machine_Motion{kind = .Iris, axis = 0, blades = 6, pivot = {0.5, 1, 1}, hinge = {0.5, 1.8, 1}, amplitude = 0.25, period_seconds = 0.15}
	footprint := [3]i32{1, 2, 2}
	blade_point :: proc(poses: Motion_Part_Transforms, blade: int, point: [3]f32) -> [3]f32 {
		return (poses.transforms[blade] * [4]f32{point.x, point.y, point.z, 1}).xyz
	}
	for fraction in ([3]f32{0, 0.5, 1}) {
		poses := motion_part_transforms(motion, footprint, fraction)
		testing.expect_value(t, poses.count, 6)
		expect_near_point(t, blade_point(poses, 3, {0, 1.8, 0}), {0, 0.2, 0}, fmt.tprintf("blade 3's pin at fraction %v", fraction))
	}
	shut := motion_part_transforms(motion, footprint, 0)
	expect_near_point(t, blade_point(shut, 0, {0.3, 1.5, -0.2}), {0.3, 1.5, -0.2}, "blade 0 shut is the part as modelled")
	expect_near_point(t, blade_point(shut, 1, {0, 1.8, 0}), {0, 1.4, 0.69282}, "blade 1's pin shut")
	open := motion_part_transforms(motion, footprint, 1)
	expect_near_point(t, blade_point(open, 0, {0, 1, 0}), {0, 1.8, -0.8}, "the centre through blade 0 open")
	if open.transforms[0] != motion_transform(motion, footprint, 1) {
		testing.expect(t, false, "blade 0 is motion_transform's pose")
	}
	slide := Machine_Motion{kind = .Slide, axis = 1, amplitude = 2, period_seconds = 1}
	single := motion_part_transforms(slide, footprint, 0.5)
	testing.expect_value(t, single.count, 1)
	testing.expect(t, single.transforms[0] == motion_transform(slide, footprint, 0.5), "a slide is posed once, as motion_transform")
}

motion_test_definition :: proc(motion: Motion_Definition) -> Machine_Definition {
	return {id = "test_machine", model = "test_machine", footprint = {width = 2, depth = 2, height = 2}, motion = motion}
}

@(test)
test_motion_definitions_are_validated :: proc(t: ^testing.T) {
	testing.expect_value(t, validate_motion_definition(motion_test_definition({})), "")
	testing.expect_value(t, validate_motion_definition(motion_test_definition({kind = "spin", axis = "z", amplitude = 1, period_seconds = 1, pivot = {1, 1, 1}})), "")
	testing.expect_value(t, validate_motion_definition(motion_test_definition({kind = "glow", period_seconds = 1})), "")
	problems := [?]struct {
		motion:   Motion_Definition,
		contains: string,
	} {
		{{kind = "wobble", period_seconds = 1}, "unknown motion kind"},
		{{kind = "pump", axis = "y"}, "period_seconds"},
		{{kind = "pump", axis = "w", period_seconds = 1}, "axis"},
		{{kind = "spin", axis = "y", period_seconds = 1, pivot = {3, 0, 0}}, "outside its footprint"},
		{{kind = "arm"}, "no inserter"},
	}
	for entry in problems {
		problem := validate_motion_definition(motion_test_definition(entry.motion))
		testing.expectf(t, strings.contains(problem, entry.contains), "%v: %q", entry.motion, problem)
	}
	arm := motion_test_definition({kind = "arm"})
	arm.kind = "inserter"
	testing.expect_value(t, validate_motion_definition(arm), "")
	without_model := motion_test_definition({kind = "glow", period_seconds = 1})
	without_model.model = ""
	testing.expect(t, strings.contains(validate_motion_definition(without_model), "no model"))

	// Work item 0231: an iris on a hatch, within its bounds.
	iris := Motion_Definition{kind = "iris", axis = "x", blades = 8, pivot = {0.5, 1, 1}, hinge = {0.5, 1.85, 1}, amplitude = 0.15, period_seconds = 0.15}
	iris_hatch :: proc(motion: Motion_Definition) -> Machine_Definition {
		return {id = "test_hatch", kind = "hatch", model = "test_hatch", footprint = {width = 1, depth = 2, height = 2}, motion = motion}
	}
	testing.expect_value(t, validate_motion_definition(iris_hatch(iris)), "")
	testing.expect_value(t, validate_hatch_definition(iris_hatch(iris)), "")
	testing.expect(t, strings.contains(validate_motion_definition(motion_test_definition(iris)), "is no hatch"))
	iris_problems := [?]struct {
		change:   proc(motion: ^Motion_Definition),
		contains: string,
	} {
		{proc(motion: ^Motion_Definition) {motion.blades = 2}, "iris blades"},
		{proc(motion: ^Motion_Definition) {motion.blades = 17}, "iris blades"},
		{proc(motion: ^Motion_Definition) {motion.amplitude = 0}, "iris amplitude"},
		{proc(motion: ^Motion_Definition) {motion.amplitude = 0.51}, "iris amplitude"},
		{proc(motion: ^Motion_Definition) {motion.hinge = {0.5, 2.5, 1}}, "iris hinge outside"},
		{proc(motion: ^Motion_Definition) {motion.pivot = {0.5, 1, 3}}, "pivot outside"},
	}
	for entry in iris_problems {
		changed := iris
		entry.change(&changed)
		problem := validate_motion_definition(iris_hatch(changed))
		testing.expectf(t, strings.contains(problem, entry.contains), "%v: %q", changed, problem)
	}
	swing := iris
	swing.kind = "swing"
	testing.expect(t, strings.contains(validate_hatch_definition(iris_hatch(swing)), "a slide, a spin or an iris"))
}

@(test)
test_a_motion_parses_from_the_machines_file :: proc(t: ^testing.T) {
	text := `machines = [{id = "wheel", motion = {kind = "spin", axis = "x", amplitude = 1, period_seconds = 1.5, pivot = [2.5, 1, 0.5]}}]`
	file, error := parse_machines_file(transmute([]byte)text, context.temp_allocator)
	testing.expect_value(t, error, nil)
	motion := resolve_machine_motion(file.machines[0].motion)
	testing.expect_value(t, motion, Machine_Motion{kind = .Spin, axis = 0, amplitude = 1, period_seconds = 1.5, pivot = {2.5, 1, 0.5}})
	testing.expect(t, motion_has_part(.Spin) && motion_has_part(.Swing) && motion_has_part(.Iris) && !motion_has_part(.Glow) && !motion_has_part(.None))
	iris_text := `machines = [{id = "door", kind = "hatch", motion = {kind = "iris", axis = "x", blades = 6, pivot = [0.5, 1, 1], hinge = [0.5, 1.8, 1.3], amplitude = 0.2, period_seconds = 0.15}}]`
	iris_file, iris_error := parse_machines_file(transmute([]byte)iris_text, context.temp_allocator)
	testing.expect_value(t, iris_error, nil)
	iris := resolve_machine_motion(iris_file.machines[0].motion)
	testing.expect_value(t, iris, Machine_Motion{kind = .Iris, axis = 0, amplitude = 0.2, period_seconds = 0.15, pivot = {0.5, 1, 1}, blades = 6, hinge = {0.5, 1.8, 1.3}})
}

// Work item 0225: the interior share scales the tint, never below the
// models' floor, and share 1 leaves it as it is.
@(test)
test_the_interior_light_tint_never_goes_below_the_floor :: proc(t: ^testing.T) {
	expect_tint :: proc(t: ^testing.T, got, want: [3]f32) {
		for channel in 0 ..< 3 {
			testing.expectf(t, abs(got[channel] - want[channel]) < 1e-6, "%v, not %v", got, want)
		}
	}
	expect_tint(t, interior_light_tint({1, 0.5, 0.2}, 0.25), {0.25, 0.125, MINIMUM_MODEL_BRIGHTNESS})
	expect_tint(t, interior_light_tint({1, 0.5, 0.2}, 1), {1, 0.5, 0.2})
	expect_tint(t, interior_light_tint({1, 0.5, 0.2}, 0), MINIMUM_MODEL_BRIGHTNESS)
}
