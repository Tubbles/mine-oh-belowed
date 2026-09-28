package game

import "core:math"
import "core:testing"

expect_near_value :: proc(t: ^testing.T, value, expected: f32, loc := #caller_location) {
	testing.expectf(t, abs(value - expected) < 0.001, "%v, expected %v", value, expected, loc = loc)
}

// One cycle per 1.6 metres, wrapping.
@(test)
test_walk_phase_comes_from_the_walked_distance :: proc(t: ^testing.T) {
	expect_near_value(t, walk_phase(0), 0)
	expect_near_value(t, walk_phase(400), 0.25)
	expect_near_value(t, walk_phase(800), 0.5)
	expect_near_value(t, walk_phase(1600), 0)
	expect_near_value(t, walk_phase(1600 * 7 + 1200), 0.75)
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
	memory, _ := advance_player_animation_memory({}, 0, 5, 1, 10)
	testing.expect(t, !memory.place_swing_active, "the first frame learns the counters")
	memory, _ = advance_player_animation_memory(memory, 0, 5, 2, 10.1)
	testing.expect(t, !memory.place_swing_active, "unchanged counters")
	memory, _ = advance_player_animation_memory(memory, 0, 6, 3, 10.2)
	testing.expect(t, memory.place_swing_active, "grown counters")
	expect_near_value(t, place_swing_elapsed(memory, 10.2), 0)
	expect_near_value(t, place_swing_angle(PLACE_SWING_SECONDS / 2), -PLACE_SWING_DEGREES)
	expect_near_value(t, place_swing_angle(-1), 0)
	expect_near_value(t, place_swing_angle(PLACE_SWING_SECONDS), 0)
	memory, _ = advance_player_animation_memory(memory, 0, 6, 4, 10.3)
	testing.expect(t, memory.place_swing_active, "still swinging")
	testing.expect_value(t, memory.place_swing_start, 10.2)
	memory, _ = advance_player_animation_memory(memory, 0, 6, 5, 10.5)
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
	memory, _ := advance_player_animation_memory({}, 100, 0, 1, 0)
	memory, _ = advance_player_animation_memory(memory, 170, 0, 2, 0)
	testing.expect(t, memory.moving, "walked")
	memory, _ = advance_player_animation_memory(memory, 170, 0, 2, 0)
	testing.expect(t, memory.moving, "same tick")
	memory, _ = advance_player_animation_memory(memory, 170, 0, 3, 0)
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
	testing.expect(t, !footstep_due(0, 799), "before the half")
	testing.expect(t, footstep_due(799, 800), "at the half")
	testing.expect(t, !footstep_due(800, 1599), "after it")
	testing.expect(t, footstep_due(1500, 1700), "at the cycle")

	steps := 0
	memory, _ := advance_player_animation_memory({}, 0, 0, 0, 0)
	for tick in 1 ..= 100 {
		// 72 mm per tick, walking speed at 60 Hz, and a second frame per
		// tick.
		footstep: bool
		memory, footstep = advance_player_animation_memory(memory, u64(tick) * 72, 0, u64(tick), 0)
		steps += int(footstep)
		memory, footstep = advance_player_animation_memory(memory, u64(tick) * 72, 0, u64(tick), 0)
		steps += int(footstep)
	}
	testing.expect_value(t, steps, int(math.floor(f32(7200) / 800)))
}
