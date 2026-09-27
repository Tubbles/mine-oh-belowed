package game

import rl "vendor:raylib"

// Hardcoded until bindings move to configuration. The layout follows
// doc/input.md. Hotbar_Radial has no gamepad binding here because it needs
// the left trackpad, which only the SDL3 backend (work item 0002) exposes.
// Holding Tab shows the hotbar radial instead, driven by the right stick.

RAYLIB_GAMEPAD_SLOTS :: 4

Gamepad_Button_Binding :: struct {
	button: rl.GamepadButton,
	action: Action,
}

Key_Binding :: struct {
	key:    rl.KeyboardKey,
	action: Action,
}

Mouse_Button_Binding :: struct {
	button: rl.MouseButton,
	action: Action,
}

@(rodata)
gamepad_button_bindings := [?]Gamepad_Button_Binding {
	{.RIGHT_FACE_DOWN, .Jump},
	{.RIGHT_FACE_DOWN, .Interact},
	{.RIGHT_FACE_DOWN, .Confirm},
	{.RIGHT_FACE_RIGHT, .Back},
	{.RIGHT_FACE_LEFT, .Open_Inventory},
	{.RIGHT_FACE_UP, .Rotate_Building},
	{.LEFT_FACE_UP, .Pipette},
	{.LEFT_FACE_LEFT, .Hotbar_Previous},
	{.LEFT_FACE_RIGHT, .Hotbar_Next},
	{.LEFT_TRIGGER_1, .Hotbar_Previous},
	{.RIGHT_TRIGGER_1, .Hotbar_Next},
	{.RIGHT_TRIGGER_2, .Mine},
	{.LEFT_TRIGGER_2, .Place},
	{.LEFT_TRIGGER_2, .Menu_Secondary},
	{.MIDDLE_LEFT, .Open_Map},
	{.MIDDLE_RIGHT, .Pause},
	{.RIGHT_TRIGGER_2, .Confirm},
	{.LEFT_FACE_UP, .Navigate_Up},
	{.LEFT_FACE_DOWN, .Navigate_Down},
	{.LEFT_FACE_LEFT, .Navigate_Left},
	{.LEFT_FACE_RIGHT, .Navigate_Right},
	{.LEFT_TRIGGER_1, .Tab_Previous},
	{.RIGHT_TRIGGER_1, .Tab_Next},
	{.RIGHT_FACE_UP, .Info_Panel},
	{.RIGHT_FACE_LEFT, .Context_Action},
}

@(rodata)
key_bindings := [?]Key_Binding {
	{.SPACE, .Jump},
	{.R, .Rotate_Building},
	{.Q, .Pipette},
	{.TAB, .Hotbar_Radial},
	{.E, .Open_Inventory},
	{.C, .Open_Recipes},
	{.J, .Open_Journal},
	{.P, .Open_Power_Overview},
	{.T, .Open_Technologies},
	{.M, .Open_Map},
	{.ESCAPE, .Pause},
	{.ENTER, .Confirm},
	{.BACKSPACE, .Back},
	{.LEFT_SHIFT, .Sneak},
	{.LEFT_SHIFT, .Menu_Secondary},
	{.F, .Interact},
	{.LEFT_CONTROL, .Sprint},
	{.LEFT_BRACKET, .Hotbar_Previous},
	{.RIGHT_BRACKET, .Hotbar_Next},
	{.V, .Toggle_Camera_Mode},
	{.F3, .Toggle_Diagnostics},
	{.F5, .Debug_Remove_Block},
	{.F7, .Debug_Drop_Item},
	{.F6, .Toggle_Fly_Mode},
	{.UP, .Navigate_Up},
	{.DOWN, .Navigate_Down},
	{.LEFT, .Navigate_Left},
	{.RIGHT, .Navigate_Right},
	{.Q, .Tab_Previous},
	{.E, .Tab_Next},
	{.R, .Info_Panel},
	{.F, .Context_Action},
}

@(rodata)
mouse_button_bindings := [?]Mouse_Button_Binding {
	{.LEFT, .Mine},
	{.RIGHT, .Place},
	{.MIDDLE, .Pipette},
}

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

read_raylib_mouse :: proc() -> Raw_Mouse {
	mouse := Raw_Mouse {
		position     = rl.GetMousePosition(),
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

gamepad_button_actions :: proc(gamepad: Raw_Gamepad) -> Action_Set {
	actions: Action_Set
	for binding in gamepad_button_bindings {
		button_index := int(binding.button)
		if button_index < gamepad.button_count && gamepad.button_down[button_index] {
			actions += {binding.action}
		}
	}
	return actions
}

keyboard_mouse_actions :: proc() -> Action_Set {
	actions: Action_Set
	for binding in key_bindings {
		if rl.IsKeyDown(binding.key) {
			actions += {binding.action}
		}
	}
	for binding in mouse_button_bindings {
		if rl.IsMouseButtonDown(binding.button) {
			actions += {binding.action}
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

read_raylib_input_frame :: proc(previous_pressed: Action_Set) -> Input_Frame {
	raw := read_raylib_raw_input()
	move := clamp_to_unit_length(gamepad_stick(raw.gamepad, .LEFT_X, .LEFT_Y) + keyboard_move())
	look := gamepad_stick(raw.gamepad, .RIGHT_X, .RIGHT_Y)
	look_delta := raw.mouse.delta
	wheel_actions := mouse_wheel_actions(raw.mouse.wheel)
	pressed := gamepad_button_actions(raw.gamepad) + keyboard_mouse_actions() + analog_actions(move, look, look_delta) + wheel_actions
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
