package game

import "core:math"

// Player animation (work item 0066): the phases the body, the first
// person arm and the head bob are posed by, pure and without raylib. The
// walk phase comes from the cadence distance: the distance the statistics
// count (distance_walked_millimetres), each tick's share divided by the
// cheat speed factor while cheat speed is on (work item 0087), so a walk
// at three times the speed bobs and steps at the normal rate. The cue
// detector (cues.odin) follows the cadence and fires the footsteps and
// place swings; Player_Animation_Memory in Frame_State keeps the walk it
// reports and a place swing under way: render state, never read by the
// simulation. The mining chop follows render time, so a faster dig chops
// at the same period.
//
// Angles are degrees about the body's sideways axis, positive swinging a
// limb forward (and the head up, like the pitch).

// One walk cycle, a step with each foot, per this many millimetres: at
// the walking speed about two steps a second (work item 0089).
WALK_CYCLE_MILLIMETRES :: 4800
WALK_SWING_DEGREES :: 35.0
SPRINT_SWING_DEGREES :: 50.0
// The right arm chops down and comes back once per period while mining,
// from the raised angle in third person.
MINE_SWING_SECONDS :: 0.4
MINE_SWING_DEGREES :: 50.0
MINE_ARM_RAISE_DEGREES :: 90.0
// One swing of the right arm when a placed counter grew.
PLACE_SWING_SECONDS :: 0.25
PLACE_SWING_DEGREES :: 40.0
// Blocks up and down, twice per walk cycle.
HEAD_BOB_WALK_BLOCKS :: 0.03
HEAD_BOB_SPRINT_BLOCKS :: 0.05
// The third person head follows the look this far up or down.
HEAD_PITCH_LIMIT_DEGREES :: 60.0

Player_Limb_Angles :: struct {
	left_arm:   f32,
	right_arm:  f32,
	left_leg:   f32,
	right_leg:  f32,
	head_pitch: f32,
}

// The walk is the cue detector's (cues.odin), copied each frame:
// moving follows the walked distance at tick granularity, so a display
// faster than the tick rate does not stop the walk every other frame.
// place_swing_start is render time in seconds, valid while
// place_swing_active.
Player_Animation_Memory :: struct {
	cadence_millimetres: u64,
	moving:              bool,
	place_swing_active:  bool,
	place_swing_start:   f64,
}

// What the pose of a frame is made from.
Player_Animation_State :: struct {
	walk_phase:          f32,
	moving:              bool,
	sprinting:           bool,
	mining:              bool,
	// Seconds since the place swing began, negative without one.
	place_swing_elapsed: f32,
	render_seconds:      f64,
	pitch:               f32,
}

// 0 up to 1 over a cycle.
walk_phase :: proc(distance_millimetres: u64) -> f32 {
	return f32(distance_millimetres % WALK_CYCLE_MILLIMETRES) / WALK_CYCLE_MILLIMETRES
}

walk_swing_amplitude :: proc(moving, sprinting: bool) -> f32 {
	if !moving {
		return 0
	}
	return sprinting ? SPRINT_SWING_DEGREES : WALK_SWING_DEGREES
}

// Forward at a quarter cycle, back at three quarters, level at 0 and a
// half.
walk_swing_angle :: proc(phase, amplitude: f32) -> f32 {
	return amplitude * math.sin(phase * math.TAU)
}

mine_swing_phase :: proc(render_seconds: f64) -> f32 {
	return f32(math.mod(render_seconds, MINE_SWING_SECONDS) / MINE_SWING_SECONDS)
}

// Down (negative) to the full swing at half the period and back.
mine_swing_angle :: proc(phase: f32) -> f32 {
	return -MINE_SWING_DEGREES * math.sin(phase * math.PI)
}

// The same down and back once, zero outside the swing.
place_swing_angle :: proc(elapsed: f32) -> f32 {
	if elapsed < 0 || elapsed >= PLACE_SWING_SECONDS {
		return 0
	}
	return -PLACE_SWING_DEGREES * math.sin(elapsed / PLACE_SWING_SECONDS * math.PI)
}

// The chop or place swing the right arm adds, zero at rest.
right_arm_action_angle :: proc(state: Player_Animation_State) -> f32 {
	if state.mining {
		return mine_swing_angle(mine_swing_phase(state.render_seconds))
	}
	return place_swing_angle(state.place_swing_elapsed)
}

// Arms and legs in opposition; mining raises the right arm and chops.
player_limb_angles :: proc(state: Player_Animation_State) -> Player_Limb_Angles {
	swing := walk_swing_angle(state.walk_phase, walk_swing_amplitude(state.moving, state.sprinting))
	angles := Player_Limb_Angles {
		left_arm   = -swing,
		right_arm  = swing,
		left_leg   = swing,
		right_leg  = -swing,
		head_pitch = clamp(state.pitch, -HEAD_PITCH_LIMIT_DEGREES, HEAD_PITCH_LIMIT_DEGREES),
	}
	if state.mining {
		angles.right_arm = MINE_ARM_RAISE_DEGREES + right_arm_action_angle(state)
	} else {
		angles.right_arm += right_arm_action_angle(state)
	}
	return angles
}

// The head bob setting, off under reduced motion (work item 0074).
head_bob_enabled :: proc(settings: Settings) -> bool {
	return settings.head_bob && !settings.reduced_motion
}

head_bob_amplitude :: proc(moving, sprinting, enabled: bool) -> f32 {
	if !moving || !enabled {
		return 0
	}
	return sprinting ? HEAD_BOB_SPRINT_BLOCKS : HEAD_BOB_WALK_BLOCKS
}

// Blocks added to the first person eye height: one rise and fall per
// step.
head_bob_offset :: proc(phase, amplitude: f32) -> f32 {
	return amplitude * math.sin(phase * 2 * math.TAU)
}

// The frame's memory from the last one and the frame's cues
// (cues.odin): the walk as the detector follows it, and a place swing
// started by a Place cue.
advance_player_animation_memory :: proc(memory: Player_Animation_Memory, cues: Frame_Cues, render_seconds: f64) -> Player_Animation_Memory {
	next := memory
	next.cadence_millimetres, next.moving = cues.cadence_millimetres, cues.moving
	if .Place in cues.fired {
		next.place_swing_active, next.place_swing_start = true, render_seconds
	}
	if next.place_swing_active && render_seconds - next.place_swing_start >= PLACE_SWING_SECONDS {
		next.place_swing_active = false
	}
	return next
}

place_swing_elapsed :: proc(memory: Player_Animation_Memory, render_seconds: f64) -> f32 {
	if !memory.place_swing_active {
		return -1
	}
	return f32(render_seconds - memory.place_swing_start)
}

player_animation_state :: proc(memory: Player_Animation_Memory, player: Player, pitch: f32, render_seconds: f64) -> Player_Animation_State {
	return Player_Animation_State {
		walk_phase = walk_phase(memory.cadence_millimetres),
		moving = memory.moving,
		sprinting = player.sprinting,
		mining = player.mining.active,
		place_swing_elapsed = place_swing_elapsed(memory, render_seconds),
		render_seconds = render_seconds,
		pitch = pitch,
	}
}
