package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
import sdl "vendor:sdl3"

// Input bindings (doc/input.md). The defaults live in data/bindings.sjson,
// the configuration may override them. A binding names an action, a device
// and a control from that device's vocabulary:
//   gamepad   SDL gamepad button names (SOUTH, DPAD_UP, LEFT_PADDLE1, ...)
//             and the trigger axes LEFT_TRIGGER and RIGHT_TRIGGER
//   keyboard  raylib key names (SPACE, LEFT_SHIFT, F3, ...)
//   mouse     raylib mouse button names (LEFT, RIGHT, MIDDLE, ...) and
//             WHEEL_UP, WHEEL_DOWN
//   trackpad  LEFT, RIGHT (a finger on the pad)
// The context (world, menu, both) says where the binding is meant to act.
// It does not gate anything: which actions reach the world while a screen
// is open is still WORLD_ACTIONS. An optional backend (sdl3, raylib) limits
// a binding to one input backend.

BINDINGS_FILE_NAME :: "bindings.sjson"
KEYBOARD_KEY_CAPACITY :: 512
GAMEPAD_LEFT_TRIGGER_NAME :: "LEFT_TRIGGER"
GAMEPAD_RIGHT_TRIGGER_NAME :: "RIGHT_TRIGGER"
MOUSE_WHEEL_UP_NAME :: "WHEEL_UP"
MOUSE_WHEEL_DOWN_NAME :: "WHEEL_DOWN"

Binding_Device :: enum u8 {
	Gamepad,
	Keyboard,
	Mouse,
	Trackpad,
}

Binding_Context :: enum u8 {
	World,
	Menu,
	Both,
}

Input_Backends :: bit_set[Input_Backend]

// A binding as written in a file.
Binding_Entry :: struct {
	action:          string,
	device:          string,
	control:         string,
	// context is an Odin keyword, hence the tag.
	binding_context: string `json:"context"`,
	// Empty for both backends.
	backend:         string,
}

Bindings_File :: struct {
	bindings: []Binding_Entry,
}

Binding :: struct {
	action:          Action,
	device:          Binding_Device,
	control:         string,
	binding_context: Binding_Context,
	backends:        Input_Backends,
	// The file it came from.
	source:          string,
}

Gamepad_Trigger :: enum u8 {
	Left,
	Right,
}

Mouse_Wheel_Direction :: enum u8 {
	Up,
	Down,
}

// What each control produces on one backend, built once at start.
// Gamepad buttons are indexed by the backend's button numbering; on the
// raylib backend the triggers are buttons and gamepad_triggers stays empty.
Input_Bindings :: struct {
	gamepad_buttons:  [RAW_GAMEPAD_BUTTON_CAPACITY]Action_Set,
	gamepad_triggers: [Gamepad_Trigger]Action_Set,
	keys:             [KEYBOARD_KEY_CAPACITY]Action_Set,
	mouse_buttons:    [RAW_MOUSE_BUTTON_CAPACITY]Action_Set,
	mouse_wheel:      [Mouse_Wheel_Direction]Action_Set,
	trackpads:        [RAW_TOUCHPAD_CAPACITY]Action_Set,
}

// Names.

@(rodata)
device_names := [Binding_Device]string {
	.Gamepad  = "gamepad",
	.Keyboard = "keyboard",
	.Mouse    = "mouse",
	.Trackpad = "trackpad",
}

@(rodata)
context_names := [Binding_Context]string {
	.World = "world",
	.Menu  = "menu",
	.Both  = "both",
}

@(rodata)
backend_names := [Input_Backend]string {
	.Raylib = "raylib",
	.Sdl3   = "sdl3",
}

device_from_name :: proc(name: string) -> (device: Binding_Device, ok: bool) {
	for device_name, candidate in device_names {
		if device_name == name {
			return candidate, true
		}
	}
	return {}, false
}

context_from_name :: proc(name: string) -> (binding_context: Binding_Context, ok: bool) {
	for context_name, candidate in context_names {
		if context_name == name {
			return candidate, true
		}
	}
	return {}, false
}

backends_from_name :: proc(name: string) -> (backends: Input_Backends, ok: bool) {
	if name == "" {
		return {.Raylib, .Sdl3}, true
	}
	for backend_name, candidate in backend_names {
		if backend_name == name {
			return {candidate}, true
		}
	}
	return {}, false
}

// Vocabulary.

sdl_gamepad_button_from_name :: proc(name: string) -> (button: sdl.GamepadButton, ok: bool) {
	button, ok = reflect.enum_from_name(sdl.GamepadButton, name)
	return button, ok && button != .INVALID
}

gamepad_trigger_from_name :: proc(name: string) -> (trigger: Gamepad_Trigger, ok: bool) {
	switch name {
	case GAMEPAD_LEFT_TRIGGER_NAME:
		return .Left, true
	case GAMEPAD_RIGHT_TRIGGER_NAME:
		return .Right, true
	}
	return {}, false
}

keyboard_key_from_name :: proc(name: string) -> (key: rl.KeyboardKey, ok: bool) {
	key, ok = reflect.enum_from_name(rl.KeyboardKey, name)
	return key, ok && key != .KEY_NULL && int(key) < KEYBOARD_KEY_CAPACITY
}

mouse_wheel_from_name :: proc(name: string) -> (direction: Mouse_Wheel_Direction, ok: bool) {
	switch name {
	case MOUSE_WHEEL_UP_NAME:
		return .Up, true
	case MOUSE_WHEEL_DOWN_NAME:
		return .Down, true
	}
	return {}, false
}

trackpad_index_from_name :: proc(name: string) -> (index: int, ok: bool) {
	switch name {
	case "LEFT":
		return LEFT_TOUCHPAD_INDEX, true
	case "RIGHT":
		return RIGHT_TOUCHPAD_INDEX, true
	}
	return 0, false
}

control_is_known :: proc(device: Binding_Device, name: string) -> bool {
	switch device {
	case .Gamepad:
		_, is_button := sdl_gamepad_button_from_name(name)
		_, is_trigger := gamepad_trigger_from_name(name)
		return is_button || is_trigger
	case .Keyboard:
		_, is_key := keyboard_key_from_name(name)
		return is_key
	case .Mouse:
		_, is_button := reflect.enum_from_name(rl.MouseButton, name)
		_, is_wheel := mouse_wheel_from_name(name)
		return is_button || is_wheel
	case .Trackpad:
		_, is_pad := trackpad_index_from_name(name)
		return is_pad
	}
	return false
}

// Resolving entries.

resolve_binding :: proc(entry: Binding_Entry, key_path, source: string) -> (binding: Binding, problem: string) {
	action, action_ok := reflect.enum_from_name(Action, entry.action)
	if !action_ok {
		return {}, fmt.tprintf("%s: %s.action: unknown action %q", source, key_path, entry.action)
	}
	device, device_ok := device_from_name(entry.device)
	if !device_ok {
		return {}, fmt.tprintf("%s: %s.device: unknown device %q (gamepad, keyboard, mouse, trackpad)", source, key_path, entry.device)
	}
	if !control_is_known(device, entry.control) {
		return {}, fmt.tprintf("%s: %s.control: %q is not a %s control", source, key_path, entry.control, entry.device)
	}
	binding_context, context_ok := context_from_name(entry.binding_context)
	if !context_ok {
		return {}, fmt.tprintf("%s: %s.context: unknown context %q (world, menu, both)", source, key_path, entry.binding_context)
	}
	backends, backends_ok := backends_from_name(entry.backend)
	if !backends_ok {
		return {}, fmt.tprintf("%s: %s.backend: unknown backend %q (sdl3, raylib)", source, key_path, entry.backend)
	}
	return Binding{action = action, device = device, control = entry.control, binding_context = binding_context, backends = backends, source = source}, ""
}

// The source of each entry comes from the provenance of its key path.
resolve_bindings :: proc(entries: []Binding_Entry, provenance: Configuration_Provenance, allocator := context.allocator) -> (bindings: []Binding, problem: string) {
	resolved := make([dynamic]Binding, 0, len(entries), allocator)
	for entry, index in entries {
		key_path := fmt.tprintf("bindings[%d]", index)
		binding, binding_problem := resolve_binding(entry, key_path, source_of_key_path(provenance, key_path))
		if binding_problem != "" {
			return nil, binding_problem
		}
		append(&resolved, binding)
	}
	return resolved[:], ""
}

// data/bindings.sjson, held to the same strict keys as the configuration.
parse_bindings_file :: proc(data: []byte, source: string, allocator := context.allocator) -> (bindings: []Binding, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, allocator)
	if parse_problem != "" {
		return nil, parse_problem
	}
	provenance := make(Configuration_Provenance, context.temp_allocator)
	provenance[""] = source
	file: Bindings_File
	if problem = assign_configuration_value(any{&file, typeid_of(Bindings_File)}, json.Value(tree), "", provenance, allocator); problem != "" {
		return nil, problem
	}
	return resolve_bindings(file.bindings, provenance, allocator)
}

load_default_bindings :: proc(data_directory: string, allocator := context.allocator) -> (bindings: []Binding, problem: string) {
	path := join_save_path(data_directory, BINDINGS_FILE_NAME)
	data, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		return nil, fmt.tprintf("%s: cannot read: %v", path, error)
	}
	return parse_bindings_file(data, strings.clone(path, allocator), allocator)
}

// Every action the overrides mention loses all of its defaults.
effective_bindings :: proc(defaults, overrides: []Binding, allocator := context.allocator) -> []Binding {
	overridden: Action_Set
	for binding in overrides {
		overridden += {binding.action}
	}
	result := make([dynamic]Binding, 0, len(defaults) + len(overrides), allocator)
	for binding in defaults {
		if binding.action not_in overridden {
			append(&result, binding)
		}
	}
	append(&result, ..overrides)
	return result[:]
}

// Backend tables.

// The raylib name for each SDL gamepad button name, following the SDL
// standard layout: face buttons by position, the d-pad as the left face,
// the bumpers as the first triggers. Paddles, MISC1 to MISC6 and TOUCHPAD
// have no raylib equivalent.
raylib_gamepad_button :: proc(button: sdl.GamepadButton) -> (raylib_button: rl.GamepadButton, ok: bool) {
	#partial switch button {
	case .SOUTH:
		return .RIGHT_FACE_DOWN, true
	case .EAST:
		return .RIGHT_FACE_RIGHT, true
	case .WEST:
		return .RIGHT_FACE_LEFT, true
	case .NORTH:
		return .RIGHT_FACE_UP, true
	case .BACK:
		return .MIDDLE_LEFT, true
	case .GUIDE:
		return .MIDDLE, true
	case .START:
		return .MIDDLE_RIGHT, true
	case .LEFT_STICK:
		return .LEFT_THUMB, true
	case .RIGHT_STICK:
		return .RIGHT_THUMB, true
	case .LEFT_SHOULDER:
		return .LEFT_TRIGGER_1, true
	case .RIGHT_SHOULDER:
		return .RIGHT_TRIGGER_1, true
	case .DPAD_UP:
		return .LEFT_FACE_UP, true
	case .DPAD_DOWN:
		return .LEFT_FACE_DOWN, true
	case .DPAD_LEFT:
		return .LEFT_FACE_LEFT, true
	case .DPAD_RIGHT:
		return .LEFT_FACE_RIGHT, true
	}
	return .UNKNOWN, false
}

@(rodata)
raylib_trigger_buttons := [Gamepad_Trigger]rl.GamepadButton {
	.Left  = .LEFT_TRIGGER_2,
	.Right = .RIGHT_TRIGGER_2,
}

bind_gamepad_control :: proc(tables: ^Input_Bindings, binding: Binding, backend: Input_Backend) -> bool {
	if trigger, is_trigger := gamepad_trigger_from_name(binding.control); is_trigger {
		switch backend {
		case .Sdl3:
			tables.gamepad_triggers[trigger] += {binding.action}
		case .Raylib:
			tables.gamepad_buttons[int(raylib_trigger_buttons[trigger])] += {binding.action}
		}
		return true
	}
	button, _ := sdl_gamepad_button_from_name(binding.control)
	index := int(button)
	if backend == .Raylib {
		raylib_button, mapped := raylib_gamepad_button(button)
		if !mapped {
			return false
		}
		index = int(raylib_button)
	}
	tables.gamepad_buttons[index] += {binding.action}
	return true
}

bind_mouse_control :: proc(tables: ^Input_Bindings, binding: Binding) {
	if direction, is_wheel := mouse_wheel_from_name(binding.control); is_wheel {
		tables.mouse_wheel[direction] += {binding.action}
		return
	}
	button, _ := reflect.enum_from_name(rl.MouseButton, binding.control)
	tables.mouse_buttons[int(button)] += {binding.action}
}

// False when the backend cannot express the binding.
bind_control :: proc(tables: ^Input_Bindings, binding: Binding, backend: Input_Backend) -> bool {
	switch binding.device {
	case .Gamepad:
		return bind_gamepad_control(tables, binding, backend)
	case .Keyboard:
		key, _ := keyboard_key_from_name(binding.control)
		tables.keys[int(key)] += {binding.action}
	case .Mouse:
		bind_mouse_control(tables, binding)
	case .Trackpad:
		if backend != .Sdl3 {
			return false
		}
		index, _ := trackpad_index_from_name(binding.control)
		tables.trackpads[index] += {binding.action}
	}
	return true
}

// Bindings limited to the other backend are skipped silently; the ones this
// backend cannot express come back for a report.
build_input_bindings :: proc(bindings: []Binding, backend: Input_Backend, allocator := context.allocator) -> (tables: Input_Bindings, unsupported: []Binding) {
	skipped := make([dynamic]Binding, allocator)
	for binding in bindings {
		if backend not_in binding.backends {
			continue
		}
		if !bind_control(&tables, binding, backend) {
			append(&skipped, binding)
		}
	}
	return tables, skipped[:]
}

binding_text :: proc(binding: Binding) -> string {
	return fmt.tprintf("%s %s", device_names[binding.device], binding.control)
}

unsupported_bindings_report :: proc(unsupported: []Binding, backend: Input_Backend) -> string {
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "input: the %s backend cannot express %d bindings:", backend_names[backend], len(unsupported))
	for binding, index in unsupported {
		fmt.sbprintf(&builder, "%s %v %s", index == 0 ? "" : ",", binding.action, binding_text(binding))
	}
	return strings.to_string(builder)
}

// Controls list.

action_display_name :: proc(action: Action) -> string {
	name, _ := strings.replace_all(fmt.tprint(action), "_", " ", context.temp_allocator)
	return name
}

// One row per bound action, in Action order, for the settings screen.
binding_rows :: proc(bindings: []Binding, allocator := context.allocator) -> []string {
	rows := make([dynamic]string, allocator)
	for action in Action {
		builder := strings.builder_make(context.temp_allocator)
		for binding in bindings {
			if binding.action != action {
				continue
			}
			fmt.sbprintf(&builder, "%s%s", strings.builder_len(builder) == 0 ? "" : ", ", binding_text(binding))
			if binding.backends != {.Raylib, .Sdl3} {
				fmt.sbprintf(&builder, " (%s only)", backends_text(binding.backends))
			}
		}
		if strings.builder_len(builder) > 0 {
			append(&rows, fmt.aprintf("%s: %s", action_display_name(action), strings.to_string(builder), allocator = allocator))
		}
	}
	return rows[:]
}

backends_text :: proc(backends: Input_Backends) -> string {
	for backend in backends {
		return backend_names[backend]
	}
	return ""
}

// Frame reading.

gamepad_trigger_actions :: proc(gamepad: Raw_Gamepad, bindings: Input_Bindings) -> Action_Set {
	actions: Action_Set
	if gamepad.axis_values[int(sdl.GamepadAxis.RIGHT_TRIGGER)] > TRIGGER_PRESS_THRESHOLD {
		actions += bindings.gamepad_triggers[.Right]
	}
	if gamepad.axis_values[int(sdl.GamepadAxis.LEFT_TRIGGER)] > TRIGGER_PRESS_THRESHOLD {
		actions += bindings.gamepad_triggers[.Left]
	}
	return actions
}

gamepad_button_actions :: proc(gamepad: Raw_Gamepad, bindings: Input_Bindings) -> Action_Set {
	actions: Action_Set
	for button_index in 0 ..< gamepad.button_count {
		if gamepad.button_down[button_index] {
			actions += bindings.gamepad_buttons[button_index]
		}
	}
	return actions
}

trackpad_actions :: proc(gamepad: Raw_Gamepad, bindings: Input_Bindings) -> Action_Set {
	actions: Action_Set
	for touchpad_index in 0 ..< RAW_TOUCHPAD_CAPACITY {
		if touchpad_finger(gamepad, touchpad_index).down {
			actions += bindings.trackpads[touchpad_index]
		}
	}
	return actions
}

// A wheel notch is an event, not a held button, so it goes straight into
// just_pressed as well.
mouse_wheel_actions :: proc(wheel: [2]f32, bindings: Input_Bindings) -> Action_Set {
	switch {
	case wheel.y > 0:
		return bindings.mouse_wheel[.Up]
	case wheel.y < 0:
		return bindings.mouse_wheel[.Down]
	}
	return {}
}
