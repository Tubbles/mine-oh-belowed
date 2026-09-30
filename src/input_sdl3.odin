#+build !linux:android
package game

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

// Reads the Steam Controller (2026) through SDL3's HIDAPI driver
// (SDL_hidapi_steam_triton.c). SDL runs without video: raylib owns the window,
// keyboard and mouse. What the driver reports and how is in doc/input.md,
// "How SDL3 exposes the controller".

VALVE_VENDOR_ID :: 0x28de
SDL3_AXIS_COUNT :: int(sdl.GamepadAxis.RIGHT_TRIGGER) + 1
SDL3_BUTTON_COUNT :: int(sdl.GamepadButton.MISC6) + 1

// Which SDL gamepad button the Triton mapping puts each extra input on,
// from the mapping string in SDL_gamepad.c (SDL_IsJoystickSteamTriton).
STEAM_CONTROLLER_LEFT_STICK_TOUCH :: sdl.GamepadButton.MISC3
STEAM_CONTROLLER_RIGHT_STICK_TOUCH :: sdl.GamepadButton.MISC4
STEAM_CONTROLLER_LEFT_GRIP_TOUCH :: sdl.GamepadButton.MISC5
STEAM_CONTROLLER_RIGHT_GRIP_TOUCH :: sdl.GamepadButton.MISC6
STEAM_CONTROLLER_RIGHT_PAD_CLICK :: sdl.GamepadButton.MISC2

// A rumble lasts this long unless the next frame renews it, so it stops
// by itself when frames stop.
HAPTIC_RUMBLE_MILLISECONDS :: 100

Sdl3_Input_State :: struct {
	gamepad:          ^sdl.Gamepad,
	// A rumble was started and not yet stopped.
	rumbling:         bool,
	gyro_calibration: Gyro_Calibration,
	// Steam Input runs beside the game (Game Mode): Steam and SDL both set
	// the controller's IMU mode with no arbitration, so SDL's gyro reads
	// whatever layout Steam left. The view then takes the gyro from Steam's
	// layout as mouse movement and ignores SDL's (couch test 1).
	steam_layer:      bool,
}

// Returns an SDL error message when initialisation fails.
init_sdl3_input :: proc() -> (ok: bool, error_message: string) {
	// The Triton driver defaults to on, but the hint's documented default
	// is off (written for the first Steam Controller), so set it explicitly.
	sdl.SetHint(sdl.HINT_JOYSTICK_HIDAPI_STEAM, "1")
	if !sdl.Init({.JOYSTICK, .GAMEPAD}) {
		return false, string(sdl.GetError())
	}
	log_printf("input: %s", steam_input_environment_text(os.get_env(sdl.HINT_GAMECONTROLLER_IGNORE_DEVICES, context.temp_allocator), os.get_env("SteamVirtualGamepadInfo", context.temp_allocator)))
	log_printf("input: SDL sees %d joysticks at start", sdl3_joystick_count())
	return true, ""
}

sdl3_joystick_count :: proc() -> int {
	count: i32
	joysticks := sdl.GetJoysticks(&count)
	sdl.free(joysticks)
	return int(count)
}

// One log line per joystick SDL adds, gamepad or not, so a device SDL sees
// but has no gamepad mapping for is told apart from one it never sees.
sdl3_joystick_line :: proc(id: u32, name: string, vendor, product: u16, guid: string, is_gamepad: bool) -> string {
	kind := is_gamepad ? "gamepad" : "no gamepad mapping"
	return fmt.tprintf("input: joystick %d \"%s\" vendor %04x product %04x guid %s %s", id, name, vendor, product, guid, kind)
}

log_sdl3_joystick_added :: proc(id: sdl.JoystickID) {
	guid_text: [33]u8
	sdl.GUIDToString(sdl.GetJoystickGUIDForID(id), raw_data(guid_text[:]), len(guid_text))
	log_printf(
		"%s",
		sdl3_joystick_line(
			u32(id),
			string(sdl.GetJoystickNameForID(id)),
			sdl.GetJoystickVendorForID(id),
			sdl.GetJoystickProductForID(id),
			string(cstring(raw_data(guid_text[:]))),
			sdl.IsGamepad(id),
		),
	)
}

// What Steam's environment says about Steam Input for this launch. With
// Steam Input on, Steam lists the physical controller in SDL's ignore
// list and points SDL at its virtual gamepad info file, which relabels
// the virtual pad with the real controller's name and ids; the log line
// after this one then shows a pad without touchpads or sensors.
steam_input_environment_text :: proc(ignore_devices, virtual_gamepad_info: string) -> string {
	ignores_valve := strings.contains(strings.to_lower(ignore_devices, context.temp_allocator), "0x28de/")
	switch {
	case ignores_valve && virtual_gamepad_info != "":
		return "Steam Input is on for this launch: SDL is told to ignore Valve controllers and given Steam's virtual gamepad"
	case ignores_valve:
		return "SDL is told to ignore Valve controllers (SDL_GAMECONTROLLER_IGNORE_DEVICES)"
	case virtual_gamepad_info != "":
		return "Steam's virtual gamepad info is set, Valve controllers are not ignored"
	}
	return "Steam Input is off for this launch (no ignore list, no virtual gamepad info)"
}

shutdown_sdl3_input :: proc(state: ^Sdl3_Input_State) {
	close_sdl3_gamepad(state)
	sdl.Quit()
}

open_sdl3_gamepad :: proc(state: ^Sdl3_Input_State, id: sdl.JoystickID) {
	gamepad := sdl.OpenGamepad(id)
	if gamepad == nil {
		log_printf("input: cannot open gamepad %d: %s", id, sdl.GetError())
		return
	}
	state.gamepad = gamepad
	state.steam_layer = os.get_env("SteamVirtualGamepadInfo", context.temp_allocator) != ""
	if state.steam_layer {
		log_printf("input: Steam's layer runs beside the game, the gyro comes from its layout as mouse movement, SDL's gyro is ignored")
	}
	// The path tells the device apart: /dev/hidraw* is the controller read
	// through HIDAPI, /dev/input/event* an evdev device such as Steam's
	// virtual pad. The controller itself has two touchpads.
	log_printf(
		"input: opened gamepad %d %q vendor %04x product %04x path %s touchpads %d",
		id,
		sdl.GetGamepadName(gamepad),
		sdl.GetGamepadVendor(gamepad),
		sdl.GetGamepadProduct(gamepad),
		sdl.GetGamepadPath(gamepad),
		sdl.GetNumGamepadTouchpads(gamepad),
	)
	enable_sdl3_sensor(gamepad, .GYRO)
	enable_sdl3_sensor(gamepad, .ACCEL)
}

enable_sdl3_sensor :: proc(gamepad: ^sdl.Gamepad, type: sdl.SensorType) {
	if !sdl.GamepadHasSensor(gamepad, type) {
		log_printf("input: gamepad has no %v sensor", type)
		return
	}
	if !sdl.SetGamepadSensorEnabled(gamepad, type, true) {
		log_printf("input: cannot enable %v sensor: %s", type, sdl.GetError())
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
		case .JOYSTICK_ADDED:
			log_sdl3_joystick_added(event.jdevice.which)
		case .JOYSTICK_REMOVED:
			log_printf("input: joystick %d removed", event.jdevice.which)
		case .GAMEPAD_ADDED:
			if state.gamepad == nil {
				open_sdl3_gamepad(state, event.gdevice.which)
			}
		case .GAMEPAD_REMOVED:
			if state.gamepad != nil && sdl.GetGamepadID(state.gamepad) == event.gdevice.which {
				log_printf("input: gamepad %d removed", event.gdevice.which)
				close_sdl3_gamepad(state)
			}
		}
	}
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

sdl3_stick :: proc(gamepad: Raw_Gamepad, x_axis, y_axis: sdl.GamepadAxis) -> [2]f32 {
	// SDL reports stick up as negative y, the action layer uses up as positive.
	stick := [2]f32{gamepad.axis_values[int(x_axis)], -gamepad.axis_values[int(y_axis)]}
	return apply_radial_deadzone(stick, STICK_DEADZONE)
}

// Runs the gyro sample of the frame through the calibration and leaves the
// corrected rate, the bias and whether it settled on the sensor.
calibrate_frame_gyro :: proc(calibration: ^Gyro_Calibration, gamepad: ^Raw_Gamepad) {
	gyro := &gamepad.motion.gyro
	if !gyro.enabled {
		return
	}
	aiming := gyro_look_active(gamepad.touch_sense, touchpad_finger(gamepad^, RIGHT_TOUCHPAD_INDEX))
	gyro.corrected = calibrate_gyro(calibration, gyro.values, aiming)
	gyro.bias, gyro.settled = calibration.bias, calibration.settled
}

read_sdl3_input_frame :: proc(state: ^Sdl3_Input_State, previous: Input_Frame, frame_seconds: f32, settings: Settings, bindings: Input_Bindings) -> Input_Frame {
	poll_sdl3_events(state)
	raw := Raw_Input {
		backend  = .Sdl3,
		gamepad  = read_sdl3_gamepad(state.gamepad),
		mouse    = read_raylib_mouse(),
		keyboard = read_raylib_keyboard(),
	}
	calibrate_frame_gyro(&state.gyro_calibration, &raw.gamepad)
	raw.gamepad.motion.gyro_source = state.steam_layer ? .Steam : .Sdl
	move := clamp_to_unit_length(sdl3_stick(raw.gamepad, .LEFTX, .LEFTY) + keyboard_move())
	look := sdl3_stick(raw.gamepad, .RIGHTX, .RIGHTY)
	look_delta := raw.mouse.delta + sdl3_look_delta(previous.raw.gamepad, raw.gamepad, frame_seconds, settings, !state.steam_layer)
	wheel_actions := mouse_wheel_actions(raw.mouse.wheel, bindings)
	pressed :=
		gamepad_button_actions(raw.gamepad, bindings) +
		gamepad_trigger_actions(raw.gamepad, bindings) +
		trackpad_actions(raw.gamepad, bindings) +
		keyboard_mouse_actions(bindings) +
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

// Both motors at the requested strength, renewed every frame; a request
// of 0 stops a running rumble once.
apply_sdl3_haptics :: proc(state: ^Sdl3_Input_State, request: Haptic_Request) {
	if state.gamepad == nil {
		state.rumbling = false
		return
	}
	if request.strength <= 0 {
		if state.rumbling {
			sdl.RumbleGamepad(state.gamepad, 0, 0, 0)
			state.rumbling = false
		}
		return
	}
	level := rumble_level(request.strength)
	sdl.RumbleGamepad(state.gamepad, level, level, HAPTIC_RUMBLE_MILLISECONDS)
	state.rumbling = true
}

// The right pad click as a pointer click, separate from the actions it is
// bound to.
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
