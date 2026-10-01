package game

import "core:math"
import "core:testing"

expect_near_value :: proc(t: ^testing.T, value, expected: f32, loc := #caller_location) {
	testing.expectf(t, abs(value - expected) < 0.001, "%v, expected %v", value, expected, loc = loc)
}

// One cycle per 4.8 metres, wrapping.
@(test)
test_walk_phase_comes_from_the_walked_distance :: proc(t: ^testing.T) {
	expect_near_value(t, walk_phase(0), 0)
	expect_near_value(t, walk_phase(1200), 0.25)
	expect_near_value(t, walk_phase(2400), 0.5)
	expect_near_value(t, walk_phase(4800), 0)
	expect_near_value(t, walk_phase(4800 * 7 + 3600), 0.75)
}

// About two steps a second at the walking speed (work item 0089).
@(test)
test_walk_cycle_gives_about_two_steps_a_second :: proc(t: ^testing.T) {
	testing.expect_value(t, WALK_CYCLE_MILLIMETRES, 4800)
	steps_per_second := PLAYER_WALK_SPEED * 1000 / (WALK_CYCLE_MILLIMETRES / 2)
	testing.expectf(t, steps_per_second > 1.5 && steps_per_second < 2.5, "%v steps a second", steps_per_second)
}

// Level at phase 0 and a half, the full swing at a quarter; sprinting
// swings further, standing still not at all.
@(test)
test_walk_swing_angles_and_sprint_amplitude :: proc(t: ^testing.T) {
	walking := walk_swing_amplitude(true, false)
	expect_near_value(t, walking, WALK_SWING_DEGREES)
	expect_near_value(t, walk_swing_amplitude(true, true), SPRINT_SWING_DEGREES)
	expect_near_value(t, walk_swing_amplitude(false, true), 0)
	expect_near_value(t, walk_swing_angle(0, walking), 0)
	expect_near_value(t, walk_swing_angle(0.25, walking), 35)
	expect_near_value(t, walk_swing_angle(0.5, walking), 0)
	expect_near_value(t, walk_swing_angle(0.75, walking), -35)

	angles := player_limb_angles({walk_phase = 0.25, moving = true, sprinting = true, place_swing_elapsed = -1})
	expect_near_value(t, angles.left_leg, 50)
	expect_near_value(t, angles.right_leg, -50)
	expect_near_value(t, angles.left_arm, -50)
	expect_near_value(t, angles.right_arm, 50)
	still := player_limb_angles({walk_phase = 0.25, place_swing_elapsed = -1})
	testing.expect_value(t, still, Player_Limb_Angles{})
}

// The chop repeats every 0.4 seconds of render time, deepest half way.
@(test)
test_mine_swing_period :: proc(t: ^testing.T) {
	expect_near_value(t, mine_swing_phase(0), 0)
	expect_near_value(t, mine_swing_phase(0.2), 0.5)
	expect_near_value(t, mine_swing_phase(0.4 * 5 + 0.1), 0.25)
	expect_near_value(t, mine_swing_angle(0), 0)
	expect_near_value(t, mine_swing_angle(0.5), -MINE_SWING_DEGREES)
	mining := player_limb_angles({mining = true, render_seconds = 0.2, place_swing_elapsed = -1})
	expect_near_value(t, mining.right_arm, MINE_ARM_RAISE_DEGREES - MINE_SWING_DEGREES)
	expect_near_value(t, mining.left_arm, 0)
	testing.expect(t, mine_swing_phase(0.39) > mine_swing_phase(0.41), "wraps")
}

// The head follows the look up to its limit.
@(test)
test_head_pitch_follows_the_look :: proc(t: ^testing.T) {
	expect_near_value(t, player_limb_angles({pitch = 20, place_swing_elapsed = -1}).head_pitch, 20)
	expect_near_value(t, player_limb_angles({pitch = -89, place_swing_elapsed = -1}).head_pitch, -HEAD_PITCH_LIMIT_DEGREES)
}

// A growth of the placed counters starts one swing of 0.25 seconds; the
// first frame of a session only learns them.
@(test)
test_place_swing_fires_once_per_growth :: proc(t: ^testing.T) {
	cue_memory: Cue_Memory
	memory := advance_player_animation_memory({}, step_cues(&cue_memory, {tick = 1, placed_total = 5}), 10)
	testing.expect(t, !memory.place_swing_active, "the first frame learns the counters")
	memory = advance_player_animation_memory(memory, step_cues(&cue_memory, {tick = 2, placed_total = 5}), 10.1)
	testing.expect(t, !memory.place_swing_active, "unchanged counters")
	memory = advance_player_animation_memory(memory, step_cues(&cue_memory, {tick = 3, placed_total = 6}), 10.2)
	testing.expect(t, memory.place_swing_active, "grown counters")
	expect_near_value(t, place_swing_elapsed(memory, 10.2), 0)
	expect_near_value(t, place_swing_angle(PLACE_SWING_SECONDS / 2), -PLACE_SWING_DEGREES)
	expect_near_value(t, place_swing_angle(-1), 0)
	expect_near_value(t, place_swing_angle(PLACE_SWING_SECONDS), 0)
	memory = advance_player_animation_memory(memory, step_cues(&cue_memory, {tick = 4, placed_total = 6}), 10.3)
	testing.expect(t, memory.place_swing_active, "still swinging")
	testing.expect_value(t, memory.place_swing_start, 10.2)
	memory = advance_player_animation_memory(memory, step_cues(&cue_memory, {tick = 5, placed_total = 6}), 10.5)
	testing.expect(t, !memory.place_swing_active, "one swing only")
	expect_near_value(t, place_swing_elapsed(memory, 10.5), -1)

	statistics := Statistics {
		placed        = []u64{1, 2},
		blocks_placed = []u64{0, 4},
	}
	testing.expect_value(t, placed_total(statistics), 7)
}

// Moving follows the distance per tick: a frame without a new tick keeps
// it.
@(test)
test_moving_follows_the_distance_per_tick :: proc(t: ^testing.T) {
	cue_memory: Cue_Memory
	memory := advance_player_animation_memory({}, step_cues(&cue_memory, {tick = 1, distance_millimetres = 100}), 0)
	memory = advance_player_animation_memory(memory, step_cues(&cue_memory, {tick = 2, distance_millimetres = 170}), 0)
	testing.expect(t, memory.moving, "walked")
	memory = advance_player_animation_memory(memory, step_cues(&cue_memory, {tick = 2, distance_millimetres = 170}), 0)
	testing.expect(t, memory.moving, "same tick")
	memory = advance_player_animation_memory(memory, step_cues(&cue_memory, {tick = 3, distance_millimetres = 170}), 0)
	testing.expect(t, !memory.moving, "stood still")
}

// Twice per cycle, the sprint bob higher, none standing or with the
// setting off.
@(test)
test_head_bob_amplitude_and_setting :: proc(t: ^testing.T) {
	expect_near_value(t, head_bob_amplitude(true, false, true), 0.03)
	expect_near_value(t, head_bob_amplitude(true, true, true), 0.05)
	expect_near_value(t, head_bob_amplitude(false, true, true), 0)
	expect_near_value(t, head_bob_amplitude(true, true, false), 0)
	expect_near_value(t, head_bob_offset(0.125, 0.03), 0.03)
	expect_near_value(t, head_bob_offset(0.625, 0.03), 0.03)
	expect_near_value(t, head_bob_offset(0.375, 0.05), -0.05)
	expect_near_value(t, head_bob_offset(0.3, 0), 0)
	testing.expect(t, DEFAULT_SETTINGS.head_bob, "on by default")
}

// Once per half cycle, also when a frame covers several ticks' walking.
@(test)
test_footstep_fires_once_per_half_cycle :: proc(t: ^testing.T) {
	testing.expect(t, !footstep_due(0, 2399), "before the half")
	testing.expect(t, footstep_due(2399, 2400), "at the half")
	testing.expect(t, !footstep_due(2400, 4799), "after it")
	testing.expect(t, footstep_due(4700, 4900), "at the cycle")

	steps := 0
	memory: Cue_Memory
	step_cues(&memory, {tick = 0})
	for tick in u64(1) ..= 100 {
		// 72 mm per tick, walking speed at 60 Hz, and a second frame per
		// tick.
		steps += int(.Footstep in step_cues(&memory, {tick = tick, distance_millimetres = tick * 72}).fired)
		steps += int(.Footstep in step_cues(&memory, {tick = tick, distance_millimetres = tick * 72}).fired)
	}
	testing.expect_value(t, steps, int(math.floor(f32(7200) / 2400)))
}

// Steps and the final walk phase of ticks of walking, per_tick
// millimetres a tick.
walk_cadence :: proc(per_tick: u64, ticks: int, cheat_speed: bool) -> (steps: int, phase: f32) {
	memory: Cue_Memory
	step_cues(&memory, {tick = 0, cheat_speed = cheat_speed})
	for tick in 1 ..= ticks {
		cues := step_cues(&memory, {tick = u64(tick), distance_millimetres = u64(tick) * per_tick, cheat_speed = cheat_speed})
		steps += int(.Footstep in cues.fired)
	}
	return steps, walk_phase(memory.cadence_millimetres)
}

// 0087: a walk or sprint at the cheat speed steps and bobs at the normal
// rate: the same steps and the same phase over the same ticks.
@(test)
test_cheat_speed_walk_keeps_the_normal_cadence :: proc(t: ^testing.T) {
	// Walking 4.3 and sprinting 5.6 blocks a second at 60 Hz, as the
	// statistics round a tick.
	walk_steps, normal_walk_phase := walk_cadence(72, 600, false)
	cheat_walk_steps, cheat_walk_phase := walk_cadence(215, 600, true)
	testing.expect_value(t, cheat_walk_steps, walk_steps)
	expect_near_value(t, cheat_walk_phase, normal_walk_phase)
	sprint_steps, sprint_phase := walk_cadence(93, 600, false)
	cheat_sprint_steps, cheat_sprint_phase := walk_cadence(280, 600, true)
	testing.expect_value(t, cheat_sprint_steps, sprint_steps)
	expect_near_value(t, cheat_sprint_phase, sprint_phase)
	fast_steps, _ := walk_cadence(215, 600, false)
	testing.expect(t, fast_steps > 2 * walk_steps, "without the cheat flag the fast walk steps faster")
	testing.expect_value(t, advance_cadence_millimetres(100, 500, 500, true), 100)
	testing.expect_value(t, advance_cadence_millimetres(100, 500, 800, false), 400)
	testing.expect_value(t, advance_cadence_millimetres(100, 500, 800, true), 200)
}
