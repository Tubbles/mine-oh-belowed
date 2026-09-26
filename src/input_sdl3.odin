package game

import "core:fmt"
import sdl "vendor:sdl3"

// Reads the Steam Controller (2026) through SDL3's HIDAPI driver
// (SDL_hidapi_steam_triton.c). SDL runs without video: raylib owns the window,
// keyboard and mouse. What the driver reports and how is in doc/input.md,
// "How SDL3 exposes the controller".

VALVE_VENDOR_ID :: 0x28de
SDL3_AXIS_COUNT :: int(sdl.GamepadAxis.RIGHT_TRIGGER) + 1
SDL3_BUTTON_COUNT :: int(sdl.GamepadButton.MISC6) + 1

// The Triton driver adds the left pad first, then the right pad.
LEFT_TOUCHPAD_INDEX :: 0
RIGHT_TOUCHPAD_INDEX :: 1

TRIGGER_PRESS_THRESHOLD :: 0.5
// Base look rates, scaled by the sensitivities in Settings.
TOUCHPAD_LOOK_PIXELS_PER_PAD_WIDTH :: 1200
GYRO_LOOK_PIXELS_PER_DEGREE :: 20

// Which SDL gamepad button the Triton mapping puts each extra input on,
// from the mapping string in SDL_gamepad.c (SDL_IsJoystickSteamTriton).
STEAM_CONTROLLER_LEFT_STICK_TOUCH :: sdl.GamepadButton.MISC3
STEAM_CONTROLLER_RIGHT_STICK_TOUCH :: sdl.GamepadButton.MISC4
STEAM_CONTROLLER_LEFT_GRIP_TOUCH :: sdl.GamepadButton.MISC5
STEAM_CONTROLLER_RIGHT_GRIP_TOUCH :: sdl.GamepadButton.MISC6
STEAM_CONTROLLER_RIGHT_PAD_CLICK :: sdl.GamepadButton.MISC2

Sdl3_Input_State :: struct {
	gamepad: ^sdl.Gamepad,
}

Sdl3_Button_Binding :: struct {
	button: sdl.GamepadButton,
	action: Action,
}

// Hardcoded until bindings move to configuration, following doc/input.md.
// B and R4 carry both the world meaning (Sneak) and the menu meaning (Back),
// the same way A carries Jump and Confirm.
@(rodata)
sdl3_button_bindings := [?]Sdl3_Button_Binding {
	{.SOUTH, .Jump},
	{.SOUTH, .Confirm},
	{.EAST, .Sneak},
	{.EAST, .Back},
	{.WEST, .Open_Inventory},
	{.NORTH, .Rotate_Building},
	{.DPAD_UP, .Pipette},
	{.DPAD_LEFT, .Hotbar_Previous},
	{.DPAD_RIGHT, .Hotbar_Next},
	{.LEFT_SHOULDER, .Hotbar_Previous},
	{.RIGHT_SHOULDER, .Hotbar_Next},
	{.LEFT_STICK, .Sprint},
	{.BACK, .Open_Map},
	{.START, .Pause},
	{.LEFT_PADDLE1, .Jump},
	{.LEFT_PADDLE1, .Confirm},
	{.RIGHT_PADDLE1, .Sneak},
	{.RIGHT_PADDLE1, .Back},
	{.LEFT_PADDLE2, .Rotate_Building},
	{.RIGHT_PADDLE2, .Pipette},
	{STEAM_CONTROLLER_RIGHT_PAD_CLICK, .Confirm},
	{.DPAD_UP, .Navigate_Up},
	{.DPAD_DOWN, .Navigate_Down},
	{.DPAD_LEFT, .Navigate_Left},
	{.DPAD_RIGHT, .Navigate_Right},
	{.LEFT_SHOULDER, .Tab_Previous},
	{.RIGHT_SHOULDER, .Tab_Next},
	{.NORTH, .Info_Panel},
	{.WEST, .Context_Action},
	{.LEFT_PADDLE2, .Info_Panel},
	{.RIGHT_PADDLE2, .Navigate_Up},
}

// Returns an SDL error message when initialisation fails.
init_sdl3_input :: proc() -> (ok: bool, error_message: string) {
	// The Triton driver defaults to on, but the hint's documented default
	// is off (written for the first Steam Controller), so set it explicitly.
	sdl.SetHint(sdl.HINT_JOYSTICK_HIDAPI_STEAM, "1")
	if !sdl.Init({.JOYSTICK, .GAMEPAD}) {
		return false, string(sdl.GetError())
	}
	return true, ""
}

shutdown_sdl3_input :: proc(state: ^Sdl3_Input_State) {
	close_sdl3_gamepad(state)
	sdl.Quit()
}

open_sdl3_gamepad :: proc(state: ^Sdl3_Input_State, id: sdl.JoystickID) {
	gamepad := sdl.OpenGamepad(id)
	if gamepad == nil {
		fmt.eprintfln("input: cannot open gamepad %d: %s", id, sdl.GetError())
		return
	}
	state.gamepad = gamepad
	fmt.eprintfln(
		"input: opened gamepad %d %q vendor %04x product %04x",
		id,
		sdl.GetGamepadName(gamepad),
		sdl.GetGamepadVendor(gamepad),
		sdl.GetGamepadProduct(gamepad),
	)
	enable_sdl3_sensor(gamepad, .GYRO)
	enable_sdl3_sensor(gamepad, .ACCEL)
}

enable_sdl3_sensor :: proc(gamepad: ^sdl.Gamepad, type: sdl.SensorType) {
	if !sdl.GamepadHasSensor(gamepad, type) {
		fmt.eprintfln("input: gamepad has no %v sensor", type)
		return
	}
	if !sdl.SetGamepadSensorEnabled(gamepad, type, true) {
		fmt.eprintfln("input: cannot enable %v sensor: %s", type, sdl.GetError())
	}
}

close_sdl3_gamepad :: proc(state: ^Sdl3_Input_State) {
	if state.gamepad != nil {
		sdl.CloseGamepad(state.gamepad)
		state.gamepad = nil
	}
}

// SDL reports gamepads present at start up as added events too.
poll_sdl3_events :: proc(state: ^Sdl3_Input_State) {
	event: sdl.Event
	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .GAMEPAD_ADDED:
			if state.gamepad == nil {
				open_sdl3_gamepad(state, event.gdevice.which)
			}
		case .GAMEPAD_REMOVED:
			if state.gamepad != nil && sdl.GetGamepadID(state.gamepad) == event.gdevice.which {
				fmt.eprintfln("input: gamepad %d removed", event.gdevice.which)
				close_sdl3_gamepad(state)
			}
		}
	}
}

// Maps -32768..32767 to -1..1; triggers only use 0..32767.
normalize_sdl_axis :: proc(value: i16) -> f32 {
	return max(f32(value) / 32767, -1)
}

read_sdl3_sensor :: proc(gamepad: ^sdl.Gamepad, type: sdl.SensorType) -> Raw_Sensor {
	sensor := Raw_Sensor {
		available = sdl.GamepadHasSensor(gamepad, type),
		enabled   = sdl.GamepadSensorEnabled(gamepad, type),
	}
	if sensor.enabled {
		sensor.data_rate = sdl.GetGamepadSensorDataRate(gamepad, type)
		sdl.GetGamepadSensorData(gamepad, type, raw_data(sensor.values[:]), len(sensor.values))
	}
	return sensor
}

read_sdl3_touchpad :: proc(gamepad: ^sdl.Gamepad, touchpad_index: int) -> Raw_Touchpad {
	touchpad := Raw_Touchpad {
		finger_count = min(int(sdl.GetNumGamepadTouchpadFingers(gamepad, i32(touchpad_index))), RAW_TOUCHPAD_FINGER_CAPACITY),
	}
	for finger_index in 0 ..< touchpad.finger_count {
		finger := &touchpad.fingers[finger_index]
		sdl.GetGamepadTouchpadFinger(
			gamepad,
			i32(touchpad_index),
			i32(finger_index),
			&finger.down,
			&finger.position.x,
			&finger.position.y,
			&finger.pressure,
		)
	}
	return touchpad
}

touch_sense_from_buttons :: proc(button_down: [RAW_GAMEPAD_BUTTON_CAPACITY]bool, available: bool) -> Raw_Touch_Sense {
	if !available {
		return {}
	}
	return Raw_Touch_Sense {
		available = true,
		left_stick_touched = button_down[int(STEAM_CONTROLLER_LEFT_STICK_TOUCH)],
		right_stick_touched = button_down[int(STEAM_CONTROLLER_RIGHT_STICK_TOUCH)],
		left_grip_touched = button_down[int(STEAM_CONTROLLER_LEFT_GRIP_TOUCH)],
		right_grip_touched = button_down[int(STEAM_CONTROLLER_RIGHT_GRIP_TOUCH)],
	}
}

// MISC3 to MISC6 only mean stick and grip touch on the Triton mapping, the
// only Valve mapping that reaches MISC6.
has_steam_controller_touch_sense :: proc(gamepad: ^sdl.Gamepad) -> bool {
	return sdl.GetGamepadVendor(gamepad) == VALVE_VENDOR_ID && sdl.GamepadHasButton(gamepad, .MISC6)
}

read_sdl3_gamepad :: proc(gamepad: ^sdl.Gamepad) -> Raw_Gamepad {
	if gamepad == nil {
		return {}
	}
	raw := Raw_Gamepad {
		connected      = true,
		index          = int(sdl.GetGamepadID(gamepad)),
		name           = sdl.GetGamepadName(gamepad),
		axis_count     = SDL3_AXIS_COUNT,
		button_count   = SDL3_BUTTON_COUNT,
		touchpad_count = min(int(sdl.GetNumGamepadTouchpads(gamepad)), RAW_TOUCHPAD_CAPACITY),
		motion         = {gyro = read_sdl3_sensor(gamepad, .GYRO), accelerometer = read_sdl3_sensor(gamepad, .ACCEL)},
	}
	for axis_index in 0 ..< raw.axis_count {
		raw.axis_values[axis_index] = normalize_sdl_axis(sdl.GetGamepadAxis(gamepad, sdl.GamepadAxis(axis_index)))
	}
	for button_index in 0 ..< raw.button_count {
		raw.button_down[button_index] = sdl.GetGamepadButton(gamepad, sdl.GamepadButton(button_index))
	}
	for touchpad_index in 0 ..< raw.touchpad_count {
		raw.touchpads[touchpad_index] = read_sdl3_touchpad(gamepad, touchpad_index)
	}
	raw.touch_sense = touch_sense_from_buttons(raw.button_down, has_steam_controller_touch_sense(gamepad))
	return raw
}

sdl3_button_actions :: proc(gamepad: Raw_Gamepad) -> Action_Set {
	actions: Action_Set
	for binding in sdl3_button_bindings {
		button_index := int(binding.button)
		if button_index < gamepad.button_count && gamepad.button_down[button_index] {
			actions += {binding.action}
		}
	}
	return actions
}

sdl3_trigger_actions :: proc(gamepad: Raw_Gamepad) -> Action_Set {
	actions: Action_Set
	if gamepad.axis_values[int(sdl.GamepadAxis.RIGHT_TRIGGER)] > TRIGGER_PRESS_THRESHOLD {
		actions += {.Mine, .Confirm}
	}
	if gamepad.axis_values[int(sdl.GamepadAxis.LEFT_TRIGGER)] > TRIGGER_PRESS_THRESHOLD {
		actions += {.Place}
	}
	return actions
}

touchpad_finger :: proc(gamepad: Raw_Gamepad, touchpad_index: int) -> Touchpad_Finger {
	if touchpad_index >= gamepad.touchpad_count {
		return {}
	}
	return gamepad.touchpads[touchpad_index].fingers[0]
}

sdl3_touchpad_actions :: proc(gamepad: Raw_Gamepad) -> Action_Set {
	if touchpad_finger(gamepad, LEFT_TOUCHPAD_INDEX).down {
		return {.Hotbar_Radial}
	}
	return {}
}

sdl3_stick :: proc(gamepad: Raw_Gamepad, x_axis, y_axis: sdl.GamepadAxis) -> [2]f32 {
	// SDL reports stick up as negative y, the action layer uses up as positive.
	stick := [2]f32{gamepad.axis_values[int(x_axis)], -gamepad.axis_values[int(y_axis)]}
	return apply_radial_deadzone(stick, STICK_DEADZONE)
}

// doc/input.md: the gyro aims while the right stick or right pad is touched.
// Pads without touch sense keep it always on.
gyro_look_active :: proc(touch_sense: Raw_Touch_Sense, right_finger: Touchpad_Finger) -> bool {
	if !touch_sense.available {
		return true
	}
	return touch_sense.right_stick_touched || right_finger.down
}

// The gyro setting only stops the gyro from aiming; the sensor stays on so
// the diagnostics screen still shows it.
sdl3_look_delta :: proc(previous, current: Raw_Gamepad, frame_seconds: f32, settings: Settings) -> [2]f32 {
	right_finger := touchpad_finger(current, RIGHT_TOUCHPAD_INDEX)
	pad_delta := touchpad_delta(touchpad_finger(previous, RIGHT_TOUCHPAD_INDEX), right_finger)
	look_delta := pad_delta * TOUCHPAD_LOOK_PIXELS_PER_PAD_WIDTH * settings.trackpad_look_sensitivity
	gyro := current.motion.gyro
	if settings.gyro_enabled && gyro.enabled && gyro_look_active(current.touch_sense, right_finger) {
		look_delta += gyro_to_look_delta(gyro.values, frame_seconds) * GYRO_LOOK_PIXELS_PER_DEGREE * settings.gyro_look_sensitivity
	}
	return look_delta
}

read_sdl3_input_frame :: proc(state: ^Sdl3_Input_State, previous: Input_Frame, frame_seconds: f32, settings: Settings) -> Input_Frame {
	poll_sdl3_events(state)
	raw := Raw_Input {
		backend  = .Sdl3,
		gamepad  = read_sdl3_gamepad(state.gamepad),
		mouse    = read_raylib_mouse(),
		keyboard = read_raylib_keyboard(),
	}
	move := clamp_to_unit_length(sdl3_stick(raw.gamepad, .LEFTX, .LEFTY) + keyboard_move())
	look := sdl3_stick(raw.gamepad, .RIGHTX, .RIGHTY)
	look_delta := raw.mouse.delta + sdl3_look_delta(previous.raw.gamepad, raw.gamepad, frame_seconds, settings)
	wheel_actions := mouse_wheel_actions(raw.mouse.wheel)
	pressed :=
		sdl3_button_actions(raw.gamepad) +
		sdl3_trigger_actions(raw.gamepad) +
		sdl3_touchpad_actions(raw.gamepad) +
		keyboard_mouse_actions() +
		analog_actions(move, look, look_delta) +
		wheel_actions
	return Input_Frame {
		move = move,
		look = look,
		look_delta = look_delta,
		pressed = pressed,
		just_pressed = actions_just_pressed(previous.pressed, pressed) + wheel_actions,
		raw = raw,
	}
}

// The right pad click as a pointer click, separate from the Confirm it is
// also bound to.
right_pad_click_down :: proc(raw: Raw_Input) -> bool {
	return raw.backend == .Sdl3 && raw.gamepad.button_down[int(STEAM_CONTROLLER_RIGHT_PAD_CLICK)]
}

// Physical names on the Steam Controller (2026) for the buttons SDL only
// numbers, from the Triton mapping string in SDL_gamepad.c.
steam_controller_button_name :: proc(button: sdl.GamepadButton) -> string {
	#partial switch button {
	case .MISC1:
		return "QAM"
	case .RIGHT_PADDLE1:
		return "R4"
	case .LEFT_PADDLE1:
		return "L4"
	case .RIGHT_PADDLE2:
		return "R5"
	case .LEFT_PADDLE2:
		return "L5"
	case .TOUCHPAD:
		return "L pad click"
	case .MISC2:
		return "R pad click"
	case .MISC3:
		return "L stick touch"
	case .MISC4:
		return "R stick touch"
	case .MISC5:
		return "L grip touch"
	case .MISC6:
		return "R grip touch"
	}
	return ""
}

sdl3_gamepad_axis_label :: proc(index: int) -> string {
	return enum_label(sdl.GamepadAxis(index))
}

sdl3_gamepad_button_label :: proc(index: int) -> string {
	button := sdl.GamepadButton(index)
	physical_name := steam_controller_button_name(button)
	if physical_name == "" {
		return enum_label(button)
	}
	return fmt.tprintf("%v (%s)", button, physical_name)
}
