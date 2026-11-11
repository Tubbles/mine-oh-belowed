package game

import "core:reflect"
import rl "shared:raylib"
import sdl "vendor:sdl3"

// The command socket's virtual devices (work item 0341, doc/input.md, The
// none backend): a gamepad in SDL3's numbering, a keyboard and a mouse.
// The input commands (command_input.odin) set them, and under
// --input=none the first viewport's frame is read from them alone
// (read_input_frame) the way read_sdl3_input_frame reads a pad, the
// keyboard and the mouse. raylib and SDL appear only for their enums;
// nothing here calls either.

MAXIMUM_TYPED_TEXT_LENGTH :: TEXT_FIELD_CAPACITY
// The most frames one press holds its control down: ten seconds at 60.
MAXIMUM_PRESS_FRAMES :: 600
// The virtual gamepad's name, which the F3 Input page shows.
INJECTED_GAMEPAD_NAME :: "Command socket"

Injected_Stick :: enum u8 {
	Left,
	Right,
}

Injected_Control_Kind :: enum u8 {
	Gamepad_Button,
	Gamepad_Trigger,
	Key,
	Mouse_Button,
}

// code is an sdl.GamepadButton, a Gamepad_Trigger, a raylib key code or
// an rl.MouseButton, by kind.
Injected_Control :: struct {
	kind: Injected_Control_Kind,
	code: i32,
}

// The devices as the input commands leave them, kept on
// Frame_Interaction.
Injected_Input :: struct {
	buttons:       [RAW_GAMEPAD_BUTTON_CAPACITY]bool,
	// Each -1 to 1, x right and y up.
	sticks:        [Injected_Stick][2]f32,
	triggers:      [Gamepad_Trigger]f32,
	// raylib key codes, in the order they went down.
	keys:          [RAW_KEYS_DOWN_CAPACITY]i32,
	key_count:     int,
	mouse_buttons: [RAW_MOUSE_BUTTON_CAPACITY]bool,
	// The mouse in render pixels, and the move the next read takes.
	pointer:       [2]f32,
	pointer_delta: [2]f32,
	// Characters still to type, RAW_TEXT_CAPACITY a read.
	text:          [MAXIMUM_TYPED_TEXT_LENGTH]u8,
	text_length:   int,
	// A press's control, down for press_frames more reads (0 for none).
	press_control: Injected_Control,
	press_frames:  int,
	// A change no read has taken yet.
	unread:        bool,
	// The last read found no change.
	quiet_read:    bool,
}

// The control of a binding's device and name, false for the mouse wheel,
// a trackpad and an unknown name.
injected_control_of :: proc(device: Binding_Device, name: string) -> (control: Injected_Control, ok: bool) {
	switch device {
	case .Gamepad:
		if trigger, is_trigger := gamepad_trigger_from_name(name); is_trigger {
			return Injected_Control{kind = .Gamepad_Trigger, code = i32(trigger)}, true
		}
		if button, is_button := sdl_gamepad_button_from_name(name); is_button {
			return Injected_Control{kind = .Gamepad_Button, code = i32(button)}, true
		}
	case .Keyboard:
		if key, is_key := keyboard_key_from_name(name); is_key {
			return Injected_Control{kind = .Key, code = i32(key)}, true
		}
	case .Mouse:
		if button, is_button := reflect.enum_from_name(rl.MouseButton, name); is_button {
			return Injected_Control{kind = .Mouse_Button, code = i32(button)}, true
		}
	case .Trackpad:
	}
	return {}, false
}

injected_key_index :: proc(injected: Injected_Input, code: i32) -> int {
	for index in 0 ..< injected.key_count {
		if injected.keys[index] == code {
			return index
		}
	}
	return -1
}

// A trigger is down at any value above rest.
injected_control_down :: proc(injected: Injected_Input, control: Injected_Control) -> bool {
	switch control.kind {
	case .Gamepad_Button:
		return injected.buttons[control.code]
	case .Gamepad_Trigger:
		return injected.triggers[Gamepad_Trigger(control.code)] > 0
	case .Key:
		return injected_key_index(injected, control.code) >= 0
	case .Mouse_Button:
		return injected.mouse_buttons[control.code]
	}
	return false
}

// A trigger goes to 1 or 0; a key is added once, or removed with the
// order of the others kept. False, and nothing changed, when a key would
// be the 17th held.
set_injected_control :: proc(injected: ^Injected_Input, control: Injected_Control, down: bool) -> (ok: bool) {
	switch control.kind {
	case .Gamepad_Button:
		injected.buttons[control.code] = down
	case .Gamepad_Trigger:
		injected.triggers[Gamepad_Trigger(control.code)] = down ? 1 : 0
	case .Key:
		return set_injected_key(injected, control.code, down)
	case .Mouse_Button:
		injected.mouse_buttons[control.code] = down
	}
	return true
}

set_injected_key :: proc(injected: ^Injected_Input, code: i32, down: bool) -> bool {
	index := injected_key_index(injected^, code)
	switch {
	case down && index >= 0:
	case down:
		if injected.key_count == RAW_KEYS_DOWN_CAPACITY {
			return false
		}
		injected.keys[injected.key_count] = code
		injected.key_count += 1
	case index >= 0:
		copy(injected.keys[index:injected.key_count], injected.keys[index + 1:injected.key_count])
		injected.key_count -= 1
		injected.keys[injected.key_count] = 0
	}
	return true
}

// Every control up, the sticks and the triggers at rest, the text and
// the press dropped; the pointer stays where it is.
release_injected_input :: proc(injected: ^Injected_Input) {
	injected^ = Injected_Input {
		pointer    = injected.pointer,
		unread     = injected.unread,
		quiet_read = injected.quiet_read,
	}
}

note_injected_change :: proc(injected: ^Injected_Input) {
	injected.unread = true
}

// The devices as one frame's raw input on the sdl3 numbering: the
// gamepad has the touch overlay's axes and buttons, SDL's y axes point
// down.
injected_raw_input :: proc(injected: Injected_Input) -> Raw_Input {
	injected := injected
	raw := Raw_Input {
		backend = .Sdl3,
		gamepad = Raw_Gamepad {
			connected = true,
			name = INJECTED_GAMEPAD_NAME,
			axis_count = TOUCH_OVERLAY_AXIS_COUNT,
			button_count = TOUCH_OVERLAY_SDL_BUTTON_COUNT,
			button_down = injected.buttons,
		},
		mouse = Raw_Mouse {
			position = injected.pointer,
			delta = injected.pointer_delta,
			button_count = len(rl.MouseButton),
			button_down = injected.mouse_buttons,
		},
		keyboard = Raw_Keyboard{keys_down = injected.keys, key_count = injected.key_count},
	}
	axes := &raw.gamepad.axis_values
	axes[int(sdl.GamepadAxis.LEFTX)] = injected.sticks[.Left].x
	axes[int(sdl.GamepadAxis.LEFTY)] = -injected.sticks[.Left].y
	axes[int(sdl.GamepadAxis.RIGHTX)] = injected.sticks[.Right].x
	axes[int(sdl.GamepadAxis.RIGHTY)] = -injected.sticks[.Right].y
	axes[int(sdl.GamepadAxis.LEFT_TRIGGER)] = injected.triggers[.Left]
	axes[int(sdl.GamepadAxis.RIGHT_TRIGGER)] = injected.triggers[.Right]
	raw.keyboard.text_length = min(injected.text_length, RAW_TEXT_CAPACITY)
	copy(raw.keyboard.text[:], injected.text[:raw.keyboard.text_length])
	return raw
}

held_key_axis :: proc(keyboard: Raw_Keyboard, negative_key, positive_key: rl.KeyboardKey) -> f32 {
	value: f32
	if keyboard_holds_key(keyboard, i32(negative_key)) {
		value -= 1
	}
	if keyboard_holds_key(keyboard, i32(positive_key)) {
		value += 1
	}
	return value
}

// W, A, S and D as keyboard_move reads them, from the keys held.
held_key_move :: proc(keyboard: Raw_Keyboard) -> [2]f32 {
	return {held_key_axis(keyboard, .A, .D), held_key_axis(keyboard, .S, .W)}
}

// keyboard_mouse_actions without raylib: the held keys' actions, and the
// held mouse buttons' unless the touch overlay drives the world. A left
// button the overlay claims is up already (touch_overlay_mouse).
held_keyboard_mouse_actions :: proc(keyboard: Raw_Keyboard, mouse: Raw_Mouse, bindings: Input_Bindings, overlay: Touch_Overlay_Frame) -> Action_Set {
	actions: Action_Set
	for index in 0 ..< keyboard.key_count {
		code := keyboard.keys_down[index]
		if code > 0 && int(code) < KEYBOARD_KEY_CAPACITY {
			actions += bindings.keys[code]
		}
	}
	if touch_overlay_drives_world(overlay) {
		return actions
	}
	for index in 0 ..< mouse.button_count {
		if mouse.button_down[index] {
			actions += bindings.mouse_buttons[index]
		}
	}
	return actions
}

// read_sdl3_input_frame's steps over the virtual devices: the touch
// overlay merged in, the sticks through the deadzone (raylib's first four
// axes are SDL's), the bindings' tables and the edges.
read_injected_input_frame :: proc(injected: Injected_Input, previous_pressed: Action_Set, bindings: Input_Bindings, overlay: Touch_Overlay_Frame) -> Input_Frame {
	raw := injected_raw_input(injected)
	raw.gamepad = touch_overlay_gamepad(raw.gamepad, overlay, .Sdl3)
	raw.mouse = touch_overlay_mouse(raw.mouse, overlay)
	move := clamp_to_unit_length(gamepad_stick(raw.gamepad, .LEFT_X, .LEFT_Y) + held_key_move(raw.keyboard))
	look := gamepad_stick(raw.gamepad, .RIGHT_X, .RIGHT_Y)
	look_delta := pointer_look_delta(raw.mouse.delta, overlay)
	pressed :=
		gamepad_button_actions(raw.gamepad, bindings) +
		gamepad_trigger_actions(raw.gamepad, bindings) +
		held_keyboard_mouse_actions(raw.keyboard, raw.mouse, bindings, overlay) +
		analog_actions(move, look, look_delta)
	return Input_Frame {
		move = move,
		look = look,
		look_delta = look_delta,
		pressed = pressed,
		just_pressed = actions_just_pressed(previous_pressed, pressed),
		raw = raw,
	}
}

// After each read: the pointer's move and the characters read are taken,
// a press counts down and lets its control go at 0. unread is set again
// while characters are left and when the press's control goes up, so
// the next read is no quiet one.
advance_injected_input :: proc(injected: ^Injected_Input) {
	injected.quiet_read = !injected.unread
	injected.unread = false
	injected.pointer_delta = {}
	read := min(injected.text_length, RAW_TEXT_CAPACITY)
	copy(injected.text[:], injected.text[read:injected.text_length])
	injected.text_length -= read
	if injected.text_length > 0 {
		injected.unread = true
	}
	if injected.press_frames > 0 {
		injected.press_frames -= 1
		if injected.press_frames == 0 {
			set_injected_control(injected, injected.press_control, false)
			injected.unread = true
		}
	}
}

// A frame's read took the last change and the UI pass after it ran: the
// read after it found nothing new, and no press or text is left.
injected_input_settled :: proc(injected: Injected_Input) -> bool {
	return !injected.unread && injected.quiet_read && injected.press_frames == 0 && injected.text_length == 0
}

// read_touch_points' desktop rule over the virtual mouse: the pointer is
// touch point 0 while the left button is held.
injected_touch_points :: proc(injected: Injected_Input, buffer: []Touch_Point) -> []Touch_Point {
	if !injected.mouse_buttons[int(rl.MouseButton.LEFT)] || len(buffer) == 0 {
		return buffer[:0]
	}
	buffer[0] = Touch_Point{id = 0, position = injected.pointer}
	return buffer[:1]
}
