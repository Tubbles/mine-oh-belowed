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
		position     = pointer_to_render_pixels(raylib_pointer_position(), cursor_window_size(), render_size()),
		delta        = rl.GetMouseDelta(),
		wheel        = rl.GetMouseWheelMoveV(),
		button_count = min(len(rl.MouseButton), RAW_MOUSE_BUTTON_CAPACITY),
	}
	for button_index in 0 ..< mouse.button_count {
		mouse.button_down[button_index] = rl.IsMouseButtonDown(rl.MouseButton(button_index))
	}
	return mouse
}

// On Android (work item 0114) the first touch is the pointer: its
// position while a finger is down, the last one after it lifts, so a tap
// lands where the finger was. The first touch also holds the left mouse
// button down (raylib's rcore.c), which is the click.
when ODIN_PLATFORM_SUBTARGET == .Android {
	@(private = "file")
	last_touch_position: [2]f32

	raylib_pointer_position :: proc() -> [2]f32 {
		last_touch_position = touch_pointer_position(int(rl.GetTouchPointCount()), rl.GetTouchPosition(0), last_touch_position)
		return last_touch_position
	}

	// A second main in the same process (work item 0116) runs without the
	// global initialisers, so the backend's start clears the previous
	// run's position.
	reset_raylib_pointer_position :: proc() {
		last_touch_position = {}
	}
} else {
	raylib_pointer_position :: proc() -> [2]f32 {
		return rl.GetMousePosition()
	}

	reset_raylib_pointer_position :: proc() {}
}

touch_pointer_position :: proc(touch_count: int, first_touch, last_position: [2]f32) -> [2]f32 {
	return first_touch if touch_count > 0 else last_position
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

// Keyboard and mouse come from raylib on both backends. While the touch
// overlay drives the world the mouse buttons are its touches and read
// nothing here (touch_overlay_drives_world); over a screen the left
// button reads nothing while the overlay claims the pointer's touch.
keyboard_mouse_actions :: proc(bindings: Input_Bindings, overlay: Touch_Overlay_Frame) -> Action_Set {
	actions: Action_Set
	for key_actions, code in bindings.keys {
		if key_actions != {} && rl.IsKeyDown(rl.KeyboardKey(code)) {
			actions += key_actions
		}
	}
	if touch_overlay_drives_world(overlay) {
		return actions
	}
	for button_actions, button in bindings.mouse_buttons {
		if overlay.pointer_claimed && rl.MouseButton(button) == .LEFT {
			continue
		}
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

// The touch overlay's gamepad joins the physical one (touch_overlay.odin).
read_raylib_input_frame :: proc(previous_pressed: Action_Set, bindings: Input_Bindings, overlay: Touch_Overlay_Frame) -> Input_Frame {
	raw := read_raylib_raw_input()
	raw.gamepad = touch_overlay_gamepad(raw.gamepad, overlay, .Raylib)
	raw.mouse = touch_overlay_mouse(raw.mouse, overlay)
	move := clamp_to_unit_length(gamepad_stick(raw.gamepad, .LEFT_X, .LEFT_Y) + keyboard_move())
	look := gamepad_stick(raw.gamepad, .RIGHT_X, .RIGHT_Y)
	look_delta := pointer_look_delta(raw.mouse.delta, overlay)
	wheel_actions := mouse_wheel_actions(raw.mouse.wheel, bindings)
	pressed := gamepad_button_actions(raw.gamepad, bindings) + keyboard_mouse_actions(bindings, overlay) + analog_actions(move, look, look_delta) + wheel_actions
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
