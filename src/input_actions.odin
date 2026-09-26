package game

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
}

Action_Set :: bit_set[Action]

Input_Backend :: enum u8 {
	Raylib,
}

RAW_GAMEPAD_AXIS_CAPACITY :: 16
RAW_GAMEPAD_BUTTON_CAPACITY :: 32
RAW_MOUSE_BUTTON_CAPACITY :: 8
RAW_KEYS_DOWN_CAPACITY :: 16

Raw_Gamepad :: struct {
	connected:    bool,
	index:        int,
	name:         cstring,
	axis_count:   int,
	axis_values:  [RAW_GAMEPAD_AXIS_CAPACITY]f32,
	button_count: int,
	button_down:  [RAW_GAMEPAD_BUTTON_CAPACITY]bool,
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
	// Pointer style look in pixels this frame (mouse, later trackpad and gyro).
	look_delta:   [2]f32,
	pressed:      Action_Set,
	just_pressed: Action_Set,
	raw:          Raw_Input,
}

STICK_DEADZONE :: 0.15

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
