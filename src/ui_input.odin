package game

// Builds the UI's view of a frame from two consecutive input frames.

// The first four axes are the sticks on both backends (raylib LEFT_X to
// RIGHT_Y, SDL LEFTX to RIGHTY). Triggers are left out: raylib reports a
// resting trigger as -1.
STICK_AXIS_COUNT :: 4

// D-pad or arrow keys first, then the dominant axis of the left stick.
navigation_direction :: proc(pressed: Action_Set, move: [2]f32) -> Ui_Direction {
	switch {
	case .Navigate_Up in pressed:
		return .Up
	case .Navigate_Down in pressed:
		return .Down
	case .Navigate_Left in pressed:
		return .Left
	case .Navigate_Right in pressed:
		return .Right
	}
	if max(abs(move.x), abs(move.y)) < UI_STICK_NAVIGATION_THRESHOLD {
		return .None
	}
	if abs(move.x) > abs(move.y) {
		return move.x > 0 ? .Right : .Left
	}
	// Move y is positive forward, which is up on screen.
	return move.y > 0 ? .Up : .Down
}

gamepad_button_newly_down :: proc(previous, current: Raw_Gamepad) -> bool {
	for index in 0 ..< current.button_count {
		if current.button_down[index] && !previous.button_down[index] {
			return true
		}
	}
	return false
}

gamepad_stick_moved :: proc(gamepad: Raw_Gamepad) -> bool {
	for index in 0 ..< min(gamepad.axis_count, STICK_AXIS_COUNT) {
		if abs(gamepad.axis_values[index]) > STICK_DEADZONE {
			return true
		}
	}
	return false
}

// Which device produced input this frame. Button edges rather than levels,
// because the Steam Controller's grip sense holds buttons down while the
// player merely holds the controller.
detect_input_device :: proc(previous, current: Raw_Input) -> (device: Input_Device, seen: bool) {
	gamepad := current.gamepad
	right_pad := touchpad_delta(touchpad_finger(previous.gamepad, RIGHT_TOUCHPAD_INDEX), touchpad_finger(gamepad, RIGHT_TOUCHPAD_INDEX))
	if gamepad.connected && (gamepad_button_newly_down(previous.gamepad, gamepad) || gamepad_stick_moved(gamepad) || right_pad != {}) {
		return .Gamepad, true
	}
	mouse_clicked := current.mouse.button_down[0] && !previous.mouse.button_down[0]
	if current.keyboard.key_count > 0 || current.mouse.delta != {} || mouse_clicked {
		return .Keyboard_Mouse, true
	}
	return .Keyboard_Mouse, false
}

keyboard_holds_key :: proc(keyboard: Raw_Keyboard, key: i32) -> bool {
	for index in 0 ..< keyboard.key_count {
		if keyboard.keys_down[index] == key {
			return true
		}
	}
	return false
}

// Keyboard key codes are raylib's on both backends, where the letter keys
// are their upper case ASCII codes.
newly_pressed_letter :: proc(previous, current: Raw_Keyboard) -> rune {
	for index in 0 ..< current.key_count {
		key := current.keys_down[index]
		if key >= 'A' && key <= 'Z' && !keyboard_holds_key(previous, key) {
			return rune(key - 'A' + 'a')
		}
	}
	return 0
}

// raylib's key codes, which both backends report.
KEY_CODE_ENTER :: 257
KEY_CODE_BACKSPACE :: 259
KEY_CODE_KEYPAD_ENTER :: 335

key_newly_pressed :: proc(previous, current: Raw_Keyboard, key: i32) -> bool {
	return keyboard_holds_key(current, key) && !keyboard_holds_key(previous, key)
}

make_ui_input :: proc(previous, current: Input_Frame) -> Ui_Input {
	just := current.just_pressed
	pad_down := right_pad_click_down(current.raw)
	pad_pressed := pad_down && !right_pad_click_down(previous.raw)
	mouse_down := current.raw.mouse.button_down[0]
	device, seen := detect_input_device(previous.raw, current.raw)
	return Ui_Input {
		navigation = navigation_direction(current.pressed, current.move),
		// The pad click is bound to Confirm too; here it is a pointer click.
		confirm = .Confirm in just && !pad_pressed,
		back = .Back in just,
		pause = .Pause in just,
		tab_previous = .Tab_Previous in just,
		tab_next = .Tab_Next in just,
		info = .Info_Panel in just,
		context_action = .Context_Action in just,
		secondary = .Menu_Secondary in just,
		confirm_down = .Confirm in current.pressed && !pad_down,
		open_inventory = .Open_Inventory in just,
		open_recipes = .Open_Recipes in just,
		open_journal = .Open_Journal in just,
		open_power = .Open_Power_Overview in just,
		open_technologies = .Open_Technologies in just,
		typed_letter = newly_pressed_letter(previous.raw.keyboard, current.raw.keyboard),
		typed_text = current.raw.keyboard.text,
		typed_text_length = current.raw.keyboard.text_length,
		backspace_key = key_newly_pressed(previous.raw.keyboard, current.raw.keyboard, KEY_CODE_BACKSPACE),
		enter_key = key_newly_pressed(previous.raw.keyboard, current.raw.keyboard, KEY_CODE_ENTER) || key_newly_pressed(previous.raw.keyboard, current.raw.keyboard, KEY_CODE_KEYPAD_ENTER),
		hotbar_radial_down = .Hotbar_Radial in current.pressed,
		mouse_position = current.raw.mouse.position,
		mouse_moved = current.raw.mouse.delta != {},
		mouse_pressed = mouse_down && !previous.raw.mouse.button_down[0],
		mouse_down = mouse_down,
		trackpad_delta = touchpad_delta(touchpad_finger(previous.raw.gamepad, RIGHT_TOUCHPAD_INDEX), touchpad_finger(current.raw.gamepad, RIGHT_TOUCHPAD_INDEX)),
		pad_pressed = pad_pressed,
		pad_down = pad_down,
		scroll_stick = current.look.y,
		scroll_wheel = current.raw.mouse.wheel.y,
		left_touchpad = touchpad_finger(current.raw.gamepad, LEFT_TOUCHPAD_INDEX),
		right_stick = current.look,
		device = device,
		device_seen = seen,
	}
}
