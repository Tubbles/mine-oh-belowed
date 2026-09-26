package game

import "core:math"
import "core:math/linalg"

Action :: enum u8 {
	Move,
	Look,
	Jump,
	Mine,
	Place,
	Rotate_Building,
	Pipette,
	Hotbar_Radial,
	Open_Inventory,
	Open_Map,
	Pause,
	Confirm,
	Back,
	Sneak,
	Sprint,
	Hotbar_Previous,
	Hotbar_Next,
	// Keyboard only: the gamepad View button is taken by the map.
	Toggle_Camera_Mode,
	// Developer actions, keyboard only.
	Toggle_Diagnostics,
	Debug_Remove_Block,
	Toggle_Fly_Mode,
}

Action_Set :: bit_set[Action]

Input_Backend :: enum u8 {
	Raylib,
	Sdl3,
}

RAW_GAMEPAD_AXIS_CAPACITY :: 16
RAW_GAMEPAD_BUTTON_CAPACITY :: 32
RAW_MOUSE_BUTTON_CAPACITY :: 8
RAW_KEYS_DOWN_CAPACITY :: 16
RAW_TOUCHPAD_CAPACITY :: 2
RAW_TOUCHPAD_FINGER_CAPACITY :: 2

// Position is 0 to 1 on both axes, origin at the top left of the pad.
Touchpad_Finger :: struct {
	down:     bool,
	position: [2]f32,
	pressure: f32,
}

Raw_Touchpad :: struct {
	finger_count: int,
	fingers:      [RAW_TOUCHPAD_FINGER_CAPACITY]Touchpad_Finger,
}

// Values use the SDL sensor frame: x right, y up, z toward the player.
// Gyro in radians per second, accelerometer in metres per second squared.
Raw_Sensor :: struct {
	available: bool,
	enabled:   bool,
	data_rate: f32,
	values:    [3]f32,
}

Raw_Motion :: struct {
	gyro:          Raw_Sensor,
	accelerometer: Raw_Sensor,
}

// Capacitive sensing on the Steam Controller (2026) sticks and handles.
Raw_Touch_Sense :: struct {
	available:           bool,
	left_stick_touched:  bool,
	right_stick_touched: bool,
	left_grip_touched:   bool,
	right_grip_touched:  bool,
}

Raw_Gamepad :: struct {
	connected:      bool,
	index:          int,
	name:           cstring,
	axis_count:     int,
	axis_values:    [RAW_GAMEPAD_AXIS_CAPACITY]f32,
	button_count:   int,
	button_down:    [RAW_GAMEPAD_BUTTON_CAPACITY]bool,
	touchpad_count: int,
	touchpads:      [RAW_TOUCHPAD_CAPACITY]Raw_Touchpad,
	motion:         Raw_Motion,
	touch_sense:    Raw_Touch_Sense,
}

Raw_Mouse :: struct {
	position:     [2]f32,
	delta:        [2]f32,
	wheel:        [2]f32,
	button_count: int,
	button_down:  [RAW_MOUSE_BUTTON_CAPACITY]bool,
}

// Backend key codes of the keys held this frame, capped at the capacity.
Raw_Keyboard :: struct {
	key_count:      int,
	keys_down:      [RAW_KEYS_DOWN_CAPACITY]i32,
	keys_truncated: bool,
}

Raw_Input :: struct {
	backend:  Input_Backend,
	gamepad:  Raw_Gamepad,
	mouse:    Raw_Mouse,
	keyboard: Raw_Keyboard,
}

Input_Frame :: struct {
	// Positive x is right, positive y is forward (away from the player).
	move:         [2]f32,
	// Rate style look from a stick, positive x is right, positive y is up.
	look:         [2]f32,
	// Pointer style look this frame in mouse pixels, positive x is right,
	// positive y is down. Mouse, right trackpad and gyro add into it.
	look_delta:   [2]f32,
	pressed:      Action_Set,
	just_pressed: Action_Set,
	raw:          Raw_Input,
}

STICK_DEADZONE :: 0.15

// A wheel notch is an event, not a held button, so it goes straight into
// just_pressed as well. Scrolling down selects the next slot.
mouse_wheel_actions :: proc(wheel: [2]f32) -> Action_Set {
	switch {
	case wheel.y < 0:
		return {.Hotbar_Next}
	case wheel.y > 0:
		return {.Hotbar_Previous}
	}
	return {}
}

// What frames collect between two simulation ticks. Frames and ticks run
// at different rates: a 144 Hz display sees two or three frames per tick,
// and a slow frame runs two ticks. look_delta (pixels) and just_pressed
// (edges) are events, so each frame adds to the pending sum and the first
// tick after them takes it all. Held state (move, look, pressed) is a level
// and every tick reads the latest frame.
Tick_Input_Accumulator :: struct {
	look_delta:   [2]f32,
	just_pressed: Action_Set,
}

accumulate_frame_input :: proc(accumulator: Tick_Input_Accumulator, frame: Input_Frame) -> Tick_Input_Accumulator {
	return Tick_Input_Accumulator {
		look_delta = accumulator.look_delta + frame.look_delta,
		just_pressed = accumulator.just_pressed + frame.just_pressed,
	}
}

// The input one tick sees, and the emptied accumulator for the next tick.
take_tick_input :: proc(accumulator: Tick_Input_Accumulator, frame: Input_Frame) -> (Input_Frame, Tick_Input_Accumulator) {
	tick_input := frame
	tick_input.look_delta = accumulator.look_delta
	tick_input.just_pressed = accumulator.just_pressed
	return tick_input, {}
}

apply_radial_deadzone :: proc(vector: [2]f32, deadzone: f32) -> [2]f32 {
	if linalg.length(vector) < deadzone {
		return {}
	}
	return vector
}

clamp_to_unit_length :: proc(vector: [2]f32) -> [2]f32 {
	length := linalg.length(vector)
	if length > 1 {
		return vector / length
	}
	return vector
}

actions_just_pressed :: proc(previous, current: Action_Set) -> Action_Set {
	return current - previous
}

analog_actions :: proc(move, look, look_delta: [2]f32) -> Action_Set {
	actions: Action_Set
	if move != {} {
		actions += {.Move}
	}
	if look != {} || look_delta != {} {
		actions += {.Look}
	}
	return actions
}

// Degrees the view turns this frame, in the look_delta convention: positive
// x turns right, positive y turns down. SDL reports rotation counter
// clockwise positive, so turning the controller left is positive yaw
// (values[1]) and tilting its far end up is positive pitch (values[0]).
// Both map to negative look_delta. Roll (values[2]) is ignored.
gyro_to_look_delta :: proc(angular_velocity: [3]f32, seconds: f32) -> [2]f32 {
	yaw_degrees := angular_velocity[1] * math.DEG_PER_RAD * seconds
	pitch_degrees := angular_velocity[0] * math.DEG_PER_RAD * seconds
	return {-yaw_degrees, -pitch_degrees}
}

// Movement of a finger across a pad since the previous frame, in pad widths.
// Zero on the frame a finger lands or lifts, so the view does not jump.
touchpad_delta :: proc(previous, current: Touchpad_Finger) -> [2]f32 {
	if !previous.down || !current.down {
		return {}
	}
	return current.position - previous.position
}

// Distance from the pad centre, in pad widths, below which no slot is chosen.
RADIAL_CENTER_RADIUS :: 0.15

// Slot 0 is centred on the top of the pad and slots count clockwise. Returns
// slot -1 when the position is inside the dead centre or slot_count is below 1.
radial_slot_from_touchpad :: proc(x, y: f32, slot_count: int) -> (slot: int, touched_center: bool) {
	offset := [2]f32{x - 0.5, y - 0.5}
	if linalg.length(offset) < RADIAL_CENTER_RADIUS {
		return -1, true
	}
	if slot_count < 1 {
		return -1, false
	}
	// Clockwise angle from straight up; pad y grows downward.
	angle := math.atan2(offset.x, -offset.y)
	if angle < 0 {
		angle += math.TAU
	}
	slot_angle := f32(math.TAU) / f32(slot_count)
	slot = int(math.floor((angle + slot_angle / 2) / slot_angle)) % slot_count
	return slot, false
}
