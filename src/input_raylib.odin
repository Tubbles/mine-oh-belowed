package game

import rl "shared:raylib"

// Bindings come from data/bindings.sjson and the configuration
// (bindings.odin). The left trackpad is not readable here, so Hotbar_Radial
// has no gamepad control on this backend; holding Tab shows the hotbar
// radial instead, driven by the right stick.

RAYLIB_GAMEPAD_SLOTS :: 4

first_available_gamepad :: proc() -> (index: int, found: bool) {
	for slot in 0 ..< RAYLIB_GAMEPAD_SLOTS {
		if rl.IsGamepadAvailable(i32(slot)) {
			return slot, true
		}
	}
	return 0, false
}

read_raylib_gamepad :: proc() -> Raw_Gamepad {
	index, found := first_available_gamepad()
	if !found {
		return {}
	}
	gamepad := Raw_Gamepad {
		connected    = true,
		index        = index,
		name         = rl.GetGamepadName(i32(index)),
		axis_count   = min(len(rl.GamepadAxis), RAW_GAMEPAD_AXIS_CAPACITY),
		button_count = min(len(rl.GamepadButton), RAW_GAMEPAD_BUTTON_CAPACITY),
	}
	for axis_index in 0 ..< gamepad.axis_count {
		gamepad.axis_values[axis_index] = rl.GetGamepadAxisMovement(i32(index), rl.GamepadAxis(axis_index))
	}
	for button_index in 0 ..< gamepad.button_count {
		gamepad.button_down[button_index] = rl.IsGamepadButtonDown(i32(index), rl.GamepadButton(button_index))
	}
	return gamepad
}

// The position is in render pixels, where the UI lays out (work item
// 0085). raylib 6.0 scales the cursor by its guess of the DPI scale, and
// guesses wrong on Wayland (its window callbacks are compiled without
// GLFW's Wayland define and set 1 over the scale, although GLFW reports
// the cursor in logical units there). The scale is reset to 1 so the
// position and the delta are GLFW's window coordinates, mapped to the
// framebuffer by GLFW's window size. The delta stays in window
// coordinates, so mouse look keeps its speed.
read_raylib_mouse :: proc() -> Raw_Mouse {
	rl.SetMouseScale(1, 1)
	mouse := Raw_Mouse {
		position     = pointer_to_render_pixels(rl.GetMousePosition(), cursor_window_size(), render_size()),
		delta        = rl.GetMouseDelta(),
		wheel        = rl.GetMouseWheelMoveV(),
		button_count = min(len(rl.MouseButton), RAW_MOUSE_BUTTON_CAPACITY),
	}
	for button_index in 0 ..< mouse.button_count {
		mouse.button_down[button_index] = rl.IsMouseButtonDown(rl.MouseButton(button_index))
	}
	return mouse
}

read_raylib_keyboard :: proc() -> Raw_Keyboard {
	keyboard: Raw_Keyboard
	for key in rl.KeyboardKey {
		if key == .KEY_NULL || !rl.IsKeyDown(key) {
			continue
		}
		if keyboard.key_count == RAW_KEYS_DOWN_CAPACITY {
			keyboard.keys_truncated = true
			break
		}
		keyboard.keys_down[keyboard.key_count] = i32(key)
		keyboard.key_count += 1
	}
	read_raylib_typed_text(&keyboard)
	return keyboard
}

// Drains raylib's character queue every frame, so no stale characters
// reach a text field opened later.
read_raylib_typed_text :: proc(keyboard: ^Raw_Keyboard) {
	for character := rl.GetCharPressed(); character != 0; character = rl.GetCharPressed() {
		if character >= ' ' && character <= '~' && keyboard.text_length < RAW_TEXT_CAPACITY {
			keyboard.text[keyboard.text_length] = u8(character)
			keyboard.text_length += 1
		}
	}
}

read_raylib_raw_input :: proc() -> Raw_Input {
	return Raw_Input {
		backend = .Raylib,
		gamepad = read_raylib_gamepad(),
		mouse = read_raylib_mouse(),
		keyboard = read_raylib_keyboard(),
	}
}

// Keyboard and mouse come from raylib on both backends.
keyboard_mouse_actions :: proc(bindings: Input_Bindings) -> Action_Set {
	actions: Action_Set
	for key_actions, code in bindings.keys {
		if key_actions != {} && rl.IsKeyDown(rl.KeyboardKey(code)) {
			actions += key_actions
		}
	}
	for button_actions, button in bindings.mouse_buttons {
		if button_actions != {} && rl.IsMouseButtonDown(rl.MouseButton(button)) {
			actions += button_actions
		}
	}
	return actions
}

gamepad_stick :: proc(gamepad: Raw_Gamepad, x_axis, y_axis: rl.GamepadAxis) -> [2]f32 {
	if !gamepad.connected {
		return {}
	}
	// raylib reports stick up as negative y, the action layer uses up as positive.
	stick := [2]f32{gamepad.axis_values[int(x_axis)], -gamepad.axis_values[int(y_axis)]}
	return apply_radial_deadzone(stick, STICK_DEADZONE)
}

key_axis :: proc(negative_key, positive_key: rl.KeyboardKey) -> f32 {
	value: f32
	if rl.IsKeyDown(negative_key) {
		value -= 1
	}
	if rl.IsKeyDown(positive_key) {
		value += 1
	}
	return value
}

keyboard_move :: proc() -> [2]f32 {
	return {key_axis(.A, .D), key_axis(.S, .W)}
}

read_raylib_input_frame :: proc(previous_pressed: Action_Set, bindings: Input_Bindings) -> Input_Frame {
	raw := read_raylib_raw_input()
	move := clamp_to_unit_length(gamepad_stick(raw.gamepad, .LEFT_X, .LEFT_Y) + keyboard_move())
	look := gamepad_stick(raw.gamepad, .RIGHT_X, .RIGHT_Y)
	look_delta := raw.mouse.delta
	wheel_actions := mouse_wheel_actions(raw.mouse.wheel, bindings)
	pressed := gamepad_button_actions(raw.gamepad, bindings) + keyboard_mouse_actions(bindings) + analog_actions(move, look, look_delta) + wheel_actions
	return Input_Frame {
		move = move,
		look = look,
		look_delta = look_delta,
		pressed = pressed,
		just_pressed = actions_just_pressed(previous_pressed, pressed) + wheel_actions,
		raw = raw,
	}
}

raylib_gamepad_axis_label :: proc(index: int) -> string {
	return enum_label(rl.GamepadAxis(index))
}

raylib_gamepad_button_label :: proc(index: int) -> string {
	return enum_label(rl.GamepadButton(index))
}

raylib_mouse_button_label :: proc(index: int) -> string {
	return enum_label(rl.MouseButton(index))
}

raylib_key_label :: proc(code: i32) -> string {
	return enum_label(rl.KeyboardKey(code))
}
