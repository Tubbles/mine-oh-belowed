package game

import "core:fmt"
import "core:math"
import "core:math/linalg"

Action :: enum u8 {
	Move,
	Look,
	Jump,
	Mine,
	Place,
	// Reads the selected usable item (a schematic). Bound with Place, which
	// it replaces while such an item is selected (resolve_use_item).
	Use_Item,
	Rotate_Building,
	Pipette,
	Hotbar_Radial,
	Open_Inventory,
	// The recipe browser: keyboard C, and from the inventory and pause menu.
	Open_Recipes,
	// The quest journal: keyboard J, and from the pause menu.
	Open_Journal,
	// The power overview: keyboard P, and from the pause menu.
	Open_Power_Overview,
	// The production statistics: keyboard N, and from the pause menu.
	Open_Statistics,
	// The technology screen: keyboard T, and from the pause menu, the
	// inventory tabs and the lab panel.
	Open_Technologies,
	Open_Map,
	Pause,
	Confirm,
	Back,
	Sneak,
	// Toggles sprinting (the stick click, 0044); a tick without movement
	// ends it (update_sprinting).
	Sprint,
	// Sprints while held: Left Shift on the keyboard.
	Sprint_Hold,
	Hotbar_Previous,
	Hotbar_Next,
	// Select a hotbar slot directly: keyboard 1 to 8 (0078).
	Hotbar_Slot_1,
	Hotbar_Slot_2,
	Hotbar_Slot_3,
	Hotbar_Slot_4,
	Hotbar_Slot_5,
	Hotbar_Slot_6,
	Hotbar_Slot_7,
	Hotbar_Slot_8,
	// Drops the selected hotbar slot's stack in front of the player (0119):
	// d-pad down (which the touch overlay's long press on the selected slot
	// presses) and keyboard X.
	Drop_Stack,
	// Turns the targeted power switch or launches from the targeted
	// launch pad. A on a gamepad, which is Jump unless one of those is
	// targeted (resolve_interact, interact_on_field).
	Interact,
	// Opens the targeted entity's panel (0194). Bound to no control: an
	// Open_Inventory press aimed at a machine with a panel becomes this
	// on the presentation side (route_open_inventory_press), and the
	// inventory does not open.
	Open_Aimed,
	// Menu actions, bound next to the world actions on the same buttons.
	Navigate_Up,
	Navigate_Down,
	Navigate_Left,
	Navigate_Right,
	Tab_Previous,
	Tab_Next,
	Info_Panel,
	Context_Action,
	// L2 (or Left Shift) in menus: split the focused stack.
	Menu_Secondary,
	// R2 (or Q) in a machine panel: move the focused stack to the other
	// side (quick_transfer.odin, 0078).
	Menu_Quick_Move,
	// Held with a click, a quick move with the mouse: Left Control.
	Menu_Quick_Move_Modifier,
	// The right stick click (or X) in the inventory: drop the held or
	// focused stack on the ground (0062).
	Menu_Drop,
	// Keyboard only: the gamepad View button is taken by the map.
	Toggle_Camera_Mode,
	// Keyboard O, and the Display settings: machine state markers in the
	// world. No gamepad button yet.
	Toggle_Bottleneck_Overlay,
	// Developer actions, keyboard only.
	Toggle_Diagnostics,
	// The world statistics overlay (draw_world_overlay).
	Toggle_World_Overlay,
	Debug_Remove_Block,
	// F7: one iron plate onto the targeted belt.
	Debug_Drop_Item,
	Toggle_Fly_Mode,
	// F9: flying passes through blocks (Player.no_clip).
	Toggle_No_Clip,
	// F8, in developer mode: reload the content tables (work item 0054).
	Reload_Data,
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
RAW_TEXT_CAPACITY :: 16
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
// values are what the sensor reported this frame; for the gyro, bias and
// corrected come from calibrate_gyro (bias learned at rest, corrected the
// rate the look uses).
Raw_Sensor :: struct {
	available: bool,
	enabled:   bool,
	data_rate: f32,
	values:    [3]f32,
	bias:      [3]f32,
	corrected: [3]f32,
	settled:   bool,
}

// Where the view's gyro rotation comes from: SDL's sensor, or Steam's layer
// as mouse movement when Steam Input runs beside the game (input_sdl3.odin).
Gyro_Source :: enum u8 {
	Sdl,
	Steam,
}

Raw_Motion :: struct {
	gyro:          Raw_Sensor,
	accelerometer: Raw_Sensor,
	gyro_source:   Gyro_Source,
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
	// The touch overlay's gamepad alone (touch_overlay.odin): its presses
	// are touches, so they do not make the gamepad the active device.
	on_screen:      bool,
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
	// Printable ASCII characters typed this frame, with shift and layout
	// applied, for text fields. On Android also TEXT_BACKSPACE for each
	// Backspace of the key queue, in order (read_raylib_typed_text).
	text:           [RAW_TEXT_CAPACITY]u8,
	text_length:    int,
}

Raw_Input :: struct {
	backend:  Input_Backend,
	gamepad:  Raw_Gamepad,
	mouse:    Raw_Mouse,
	keyboard: Raw_Keyboard,
}

Input_Frame :: struct {
	// Positive x is right, positive y is forward (away from the player).
	move:          [2]f32,
	// Rate style look from a stick, positive x is right, positive y is up.
	look:          [2]f32,
	// Pointer style look this frame in mouse pixels, positive x is right,
	// positive y is down. Mouse, right trackpad and gyro add into it.
	look_delta:    [2]f32,
	pressed:       Action_Set,
	just_pressed:  Action_Set,
	raw:           Raw_Input,
	// The sneak_hold and sprint_hold settings (apply_hold_settings). The
	// zero value is the default: Sneak acts while held, Sprint toggles.
	sneak_toggles: bool,
	sprint_holds:  bool,
	// Developer mode (world_input), for the Jump double tap that toggles
	// flying (update_jump_double_tap).
	developer:     bool,
	// A screen blocked the world on a frame since the last tick the world
	// ran (world_input, Tick_Input_Accumulator), paused ticks included:
	// the Jump double tap's window closes (update_jump_double_tap, 0132),
	// so a Jump before a pause and one after it are no double tap.
	world_blocked: bool,
	// The touch overlay's tap scheme (0118): the unit direction through
	// the touched point, from the render camera, which the player's target
	// takes instead of the look direction while aim_overrides is set.
	aim_direction: [3]f32,
	aim_overrides: bool,
}

STICK_DEADZONE :: 0.15

// The SDL-free parts of the SDL3 backend (input_sdl3.odin), here so the
// bindings and the tests compile on Android, where that file is left out.

// The Triton driver adds the left pad first, then the right pad.
LEFT_TOUCHPAD_INDEX :: 0
RIGHT_TOUCHPAD_INDEX :: 1

TRIGGER_PRESS_THRESHOLD :: 0.5

// Base look rates, scaled by the sensitivities in Settings.
TOUCHPAD_LOOK_PIXELS_PER_PAD_WIDTH :: 1200
GYRO_LOOK_PIXELS_PER_DEGREE :: 20

// Maps -32768..32767 to -1..1; triggers only use 0..32767.
normalize_sdl_axis :: proc(value: i16) -> f32 {
	return max(f32(value) / 32767, -1)
}

touchpad_finger :: proc(gamepad: Raw_Gamepad, touchpad_index: int) -> Touchpad_Finger {
	if touchpad_index >= gamepad.touchpad_count {
		return {}
	}
	return gamepad.touchpads[touchpad_index].fingers[0]
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
// the diagnostics screen still shows it. With gyro_from_sdl false (Steam's
// layer present) SDL's gyro never turns the view; Steam's mouse movement,
// added by the caller, carries the gyro instead.
sdl3_look_delta :: proc(previous, current: Raw_Gamepad, frame_seconds: f32, settings: Settings, gyro_from_sdl := true) -> [2]f32 {
	right_finger := touchpad_finger(current, RIGHT_TOUCHPAD_INDEX)
	pad_delta := touchpad_delta(touchpad_finger(previous, RIGHT_TOUCHPAD_INDEX), right_finger)
	look_delta := pad_delta * TOUCHPAD_LOOK_PIXELS_PER_PAD_WIDTH * settings.trackpad_look_sensitivity
	gyro := current.motion.gyro
	if gyro_from_sdl && settings.gyro_enabled && gyro.enabled && gyro_look_active(current.touch_sense, right_finger) {
		look_delta += gyro_to_look_delta(gyro.corrected, frame_seconds) * GYRO_LOOK_PIXELS_PER_DEGREE * settings.gyro_look_sensitivity
	}
	return look_delta
}

// What the player's body and hands react to. While a screen is open the
// world gets none of these; the menu meanings of the same buttons belong to
// the UI.
WORLD_ACTIONS :: Action_Set {
	.Move,
	.Look,
	.Jump,
	.Mine,
	.Place,
	.Use_Item,
	.Rotate_Building,
	.Pipette,
	.Hotbar_Radial,
	.Open_Inventory,
	.Open_Recipes,
	.Open_Journal,
	.Open_Power_Overview,
	.Open_Statistics,
	.Open_Technologies,
	.Open_Map,
	.Sneak,
	.Sprint,
	.Sprint_Hold,
	.Hotbar_Previous,
	.Hotbar_Next,
	.Hotbar_Slot_1,
	.Hotbar_Slot_2,
	.Hotbar_Slot_3,
	.Hotbar_Slot_4,
	.Hotbar_Slot_5,
	.Hotbar_Slot_6,
	.Hotbar_Slot_7,
	.Hotbar_Slot_8,
	.Drop_Stack,
	.Interact,
	.Open_Aimed,
	.Toggle_Camera_Mode,
	.Toggle_Fly_Mode,
	.Toggle_No_Clip,
}

without_actions :: proc(frame: Input_Frame, removed: Action_Set) -> Input_Frame {
	result := frame
	result.pressed -= removed
	result.just_pressed -= removed
	if .Move in removed {
		result.move = {}
	}
	if .Look in removed {
		result.look, result.look_delta = {}, {}
	}
	return result
}

// Open_Inventory means "open" (0194): a press while no screen is open and
// a machine with a panel is aimed (aims_at_panel, decided from the target
// the HUD shows) becomes the simulation's Open_Aimed instead, so the UI
// opens no inventory; any other press stays Open_Inventory and the
// simulation opens nothing.
route_open_inventory_press :: proc(frame: Input_Frame, world_blocked, aims_at_panel: bool) -> Input_Frame {
	result := frame
	if world_blocked || !aims_at_panel || .Open_Inventory not_in frame.just_pressed {
		return result
	}
	result.just_pressed -= {.Open_Inventory}
	result.just_pressed += {.Open_Aimed}
	return result
}

// While a screen is open, every held world action joins the guard. After it
// closes, a guarded action stays hidden from the world until released, so
// the A press that picked Resume does not also jump.
update_world_action_guard :: proc(guard: Action_Set, world_blocked: bool, pressed: Action_Set) -> Action_Set {
	if world_blocked {
		return pressed & WORLD_ACTIONS
	}
	return guard & pressed
}

// The frame the simulation sees. developer rides in the frame, so the
// simulation never reads the setting itself.
world_input :: proc(frame: Input_Frame, world_blocked: bool, guard: Action_Set, settings: Settings, developer: bool) -> Input_Frame {
	result: Input_Frame
	if world_blocked {
		result = apply_hold_settings(without_actions(frame, WORLD_ACTIONS), settings)
	} else {
		result = apply_hold_settings(apply_look_settings(without_actions(frame, guard), settings), settings)
	}
	result.developer, result.world_blocked = developer, world_blocked
	return result
}

// What frames collect between two simulation ticks. Frames and ticks run
// at different rates: a 144 Hz display sees two or three frames per tick,
// and a slow frame runs two ticks. look_delta (pixels) and just_pressed
// (edges) are events, so each frame adds to the pending sum and the first
// tick after them takes it all. Held state (move, look, pressed) is a level
// and every tick reads the latest frame.
// world_blocked is an event too: any blocked frame since the last tick.
Tick_Input_Accumulator :: struct {
	look_delta:    [2]f32,
	just_pressed:  Action_Set,
	world_blocked: bool,
}

accumulate_frame_input :: proc(accumulator: Tick_Input_Accumulator, frame: Input_Frame) -> Tick_Input_Accumulator {
	return Tick_Input_Accumulator {
		look_delta = accumulator.look_delta + frame.look_delta,
		just_pressed = accumulator.just_pressed + frame.just_pressed,
		world_blocked = accumulator.world_blocked || frame.world_blocked,
	}
}

// While the simulation is paused the frames' events are dropped, but a
// blocked frame is remembered for the first tick after the pause.
paused_frame_input :: proc(accumulator: Tick_Input_Accumulator, frame: Input_Frame) -> Tick_Input_Accumulator {
	return Tick_Input_Accumulator{world_blocked = accumulator.world_blocked || frame.world_blocked}
}

// The input one tick sees, and the emptied accumulator for the next tick.
take_tick_input :: proc(accumulator: Tick_Input_Accumulator, frame: Input_Frame) -> (Input_Frame, Tick_Input_Accumulator) {
	tick_input := frame
	tick_input.look_delta = accumulator.look_delta
	tick_input.just_pressed = accumulator.just_pressed
	tick_input.world_blocked = accumulator.world_blocked
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
// Gyro bias (couch test 1, 2026-09-27): the controller reported a constant
// rate at rest that turned the view on its own while a thumb rested on the
// right stick. The bias is learned while the gyro is not aiming and the
// controller is still (consecutive samples within GYRO_STILL_TOLERANCE of
// each other for GYRO_STILL_SAMPLES samples) and subtracted from every
// reading; what is left under GYRO_DEADZONE counts as rest. A sample past
// the sensor's full scale is a misread and reads as zero. Until the first
// still period the raw rate is used as it is.
GYRO_STILL_TOLERANCE :: 0.02
GYRO_STILL_SAMPLES :: 90
GYRO_DEADZONE :: 0.01
// 2000 degrees per second, the gyro's full scale (doc/input.md).
GYRO_FULL_SCALE :: 35.0

Gyro_Calibration :: struct {
	bias:        [3]f32,
	settled:     bool,
	previous:    [3]f32,
	still_count: int,
	still_sum:   [3]f32,
}

gyro_sample_plausible :: proc(sample: [3]f32) -> bool {
	return abs(sample.x) <= GYRO_FULL_SCALE && abs(sample.y) <= GYRO_FULL_SCALE && abs(sample.z) <= GYRO_FULL_SCALE
}

gyro_samples_agree :: proc(first, second: [3]f32) -> bool {
	difference := first - second
	return abs(difference.x) <= GYRO_STILL_TOLERANCE && abs(difference.y) <= GYRO_STILL_TOLERANCE && abs(difference.z) <= GYRO_STILL_TOLERANCE
}

apply_gyro_deadzone :: proc(rate: [3]f32) -> [3]f32 {
	result := rate
	for &axis in result {
		if abs(axis) < GYRO_DEADZONE {
			axis = 0
		}
	}
	return result
}

reset_gyro_stillness :: proc(calibration: ^Gyro_Calibration) {
	calibration.still_count, calibration.still_sum = 0, {}
}

// One raw sample per frame. aiming is true while the gyro steers the view,
// when a steady turn must not be learned as bias.
calibrate_gyro :: proc(calibration: ^Gyro_Calibration, sample: [3]f32, aiming: bool) -> (corrected: [3]f32) {
	if !gyro_sample_plausible(sample) {
		reset_gyro_stillness(calibration)
		return {}
	}
	if aiming || !gyro_samples_agree(calibration.previous, sample) {
		reset_gyro_stillness(calibration)
	} else {
		calibration.still_count += 1
		calibration.still_sum += sample
		if calibration.still_count >= GYRO_STILL_SAMPLES {
			calibration.bias = calibration.still_sum / f32(calibration.still_count)
			calibration.settled = true
			reset_gyro_stillness(calibration)
		}
	}
	calibration.previous = sample
	return apply_gyro_deadzone(sample - calibration.bias)
}

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

enum_label :: proc(value: $T) -> string {
	return fmt.tprint(value)
}
