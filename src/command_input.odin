package game

import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strings"

// The command socket's input commands (work item 0341, doc/commands.md,
// Input): press, hold, release, stick, trigger, pointer and type set the
// virtual devices (input_injected.odin), which the first viewport's
// frames read under --input=none. They change no world themselves: a
// world action rides the local player's input record as a device's does.
// A command answers once a frame's UI has seen its last change
// (answer_input_command in loop.odin); later lines wait behind it.
// query ui reads the first viewport's UI on every backend.

INPUT_NEEDS_NONE_PROBLEM :: "input commands need --input=none"
// A tick's command context (session_command_context) holds no input: a
// record's line runs inside the tick on every machine, where no frame's
// devices or UI are at hand.
NO_INPUT_HERE_PROBLEM :: "no input here"

PRESS_USAGE :: "press <action> [frames] | press <gamepad|keyboard|mouse> <control> [frames]"
HOLD_USAGE :: "hold <action> | hold <gamepad|keyboard|mouse> <control>"
RELEASE_USAGE :: "release <action> | release <gamepad|keyboard|mouse> <control> | release all"
STICK_USAGE :: "stick <left|right> <x> <y>"
TRIGGER_USAGE :: "trigger <left|right> <value>"
POINTER_USAGE :: "pointer <x> <y>"
TYPE_USAGE :: "type <text>"

// The first viewport's virtual devices and UI, the effective bindings
// and their numbering, the render size; zero in a tick's context, where
// the input commands and query ui answer NO_INPUT_HERE_PROBLEM.
Command_Input_Context :: struct {
	injected:    ^Injected_Input,
	ui:          ^Ui_State,
	bindings:    []Binding,
	backend:     Input_Backend,
	devices_off: bool,
	render_size: [2]int,
}

@(rodata)
injected_stick_words := [Injected_Stick]string {
	.Left  = "left",
	.Right = "right",
}

@(rodata)
injected_trigger_words := [Gamepad_Trigger]string {
	.Left  = "left",
	.Right = "right",
}

command_reads_input :: proc(name: string) -> bool {
	switch name {
	case "press", "hold", "release", "stick", "trigger", "pointer", "type":
		return true
	}
	return false
}

// The action's first gamepad control the backend reads (the one its
// glyph shows), else its first key or mouse button.
resolve_action_control :: proc(bindings: []Binding, action: Action, backend: Input_Backend) -> (control: Injected_Control, binding: Binding, found: bool) {
	for device in ([?]Input_Device{.Gamepad, .Keyboard_Mouse}) {
		for candidate in bindings {
			if candidate.action != action || !binding_on_backend(candidate, backend) || !binding_on_device(candidate, device) {
				continue
			}
			if resolved, ok := injected_control_of(candidate.device, candidate.control); ok {
				return resolved, candidate, true
			}
		}
	}
	return {}, {}, false
}

usage_problem :: proc(usage: string) -> string {
	return fmt.tprintf("usage: %s", usage)
}

// The words hold an action, or a device and its control.
input_target_complete :: proc(words: []string) -> bool {
	if len(words) == 0 {
		return false
	}
	_, is_device := device_from_name(words[0])
	return !is_device || len(words) >= 2
}

// The device form (label gamepad SOUTH) or an action (label gamepad SOUTH
// (Confirm)), and the words after it. The words are complete
// (input_target_complete).
parse_input_target :: proc(input: Command_Input_Context, words: []string) -> (control: Injected_Control, label: string, rest: []string, problem: string) {
	if device, is_device := device_from_name(words[0]); is_device {
		label = fmt.tprintf("%s %s", words[0], words[1])
		ok: bool
		if control, ok = injected_control_of(device, words[1]); !ok {
			return {}, "", nil, fmt.tprintf("%s is no control of the virtual devices", label)
		}
		return control, label, words[2:], ""
	}
	action, is_action := reflect.enum_from_name(Action, words[0])
	if !is_action {
		return {}, "", nil, fmt.tprintf("unknown action or device %q", words[0])
	}
	binding: Binding
	found: bool
	if control, binding, found = resolve_action_control(input.bindings, action, input.backend); !found {
		return {}, "", nil, fmt.tprintf("%v is bound to no gamepad control, key or mouse button", action)
	}
	return control, fmt.tprintf("%s (%v)", binding_text(binding), action), words[1:], ""
}

held_keys_problem :: proc() -> string {
	return fmt.tprintf("%d keys are held already", RAW_KEYS_DOWN_CAPACITY)
}

// Down for the frames (1 by default), then up.
command_press :: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string) {
	if !input_target_complete(arguments) {
		return "", usage_problem(PRESS_USAGE)
	}
	control, label, rest, target_problem := parse_input_target(input, arguments)
	switch {
	case target_problem != "":
		return "", target_problem
	case len(rest) > 1:
		return "", usage_problem(PRESS_USAGE)
	}
	frames := 1
	if len(rest) == 1 {
		if frames, problem = parse_ranged_word(rest[0], 1, MAXIMUM_PRESS_FRAMES, "the frames"); problem != "" {
			return "", problem
		}
	}
	if injected_control_down(input.injected^, control) {
		return "", fmt.tprintf("%s is held; release it first", label)
	}
	if !set_injected_control(input.injected, control, true) {
		return "", held_keys_problem()
	}
	input.injected.press_control, input.injected.press_frames = control, frames
	return fmt.tprintf("pressed %s for %d %s", label, frames, frames == 1 ? "frame" : "frames"), ""
}

command_hold :: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string) {
	if !input_target_complete(arguments) {
		return "", usage_problem(HOLD_USAGE)
	}
	control, label, rest, target_problem := parse_input_target(input, arguments)
	switch {
	case target_problem != "":
		return "", target_problem
	case len(rest) > 0:
		return "", usage_problem(HOLD_USAGE)
	case !set_injected_control(input.injected, control, true):
		return "", held_keys_problem()
	}
	return fmt.tprintf("holding %s", label), ""
}

command_release :: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string) {
	if len(arguments) > 0 && arguments[0] == "all" {
		if len(arguments) > 1 {
			return "", usage_problem(RELEASE_USAGE)
		}
		release_injected_input(input.injected)
		return "released all", ""
	}
	if !input_target_complete(arguments) {
		return "", usage_problem(RELEASE_USAGE)
	}
	control, label, rest, target_problem := parse_input_target(input, arguments)
	switch {
	case target_problem != "":
		return "", target_problem
	case len(rest) > 0:
		return "", usage_problem(RELEASE_USAGE)
	case !injected_control_down(input.injected^, control):
		return "", fmt.tprintf("%s is not held", label)
	}
	set_injected_control(input.injected, control, false)
	return fmt.tprintf("released %s", label), ""
}

// Held where it is set until set again.
command_stick :: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string) {
	if len(arguments) != 3 {
		return "", usage_problem(STICK_USAGE)
	}
	stick, found := parse_named_enum(injected_stick_words, arguments[0])
	if !found {
		return "", usage_problem(STICK_USAGE)
	}
	x, y: i64
	if x, problem = parse_ranged_decimal_word(arguments[1], -1000, 1000, "x"); problem != "" {
		return "", problem
	}
	if y, problem = parse_ranged_decimal_word(arguments[2], -1000, 1000, "y"); problem != "" {
		return "", problem
	}
	input.injected.sticks[stick] = {f32(x) / 1000, f32(y) / 1000}
	return fmt.tprintf("stick %s at %s %s", arguments[0], thousandths_text(x), thousandths_text(y)), ""
}

command_trigger :: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string) {
	if len(arguments) != 2 {
		return "", usage_problem(TRIGGER_USAGE)
	}
	trigger, found := parse_named_enum(injected_trigger_words, arguments[0])
	if !found {
		return "", usage_problem(TRIGGER_USAGE)
	}
	value: i64
	if value, problem = parse_ranged_decimal_word(arguments[1], 0, 1000, "the trigger"); problem != "" {
		return "", problem
	}
	input.injected.triggers[trigger] = f32(value) / 1000
	return fmt.tprintf("trigger %s at %s", arguments[0], thousandths_text(value)), ""
}

// The mouse to a render pixel; the move is the next read's mouse delta.
command_pointer :: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string) {
	if len(arguments) != 2 {
		return "", usage_problem(POINTER_USAGE)
	}
	x, y: int
	if x, problem = parse_ranged_word(arguments[0], 0, input.render_size.x - 1, "x"); problem != "" {
		return "", problem
	}
	if y, problem = parse_ranged_word(arguments[1], 0, input.render_size.y - 1, "y"); problem != "" {
		return "", problem
	}
	position := [2]f32{f32(x), f32(y)}
	input.injected.pointer_delta = position - input.injected.pointer
	input.injected.pointer = position
	return fmt.tprintf("pointer at %d %d", x, y), ""
}

// Printable ASCII, one word, typed RAW_TEXT_CAPACITY characters a frame.
command_type :: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string) {
	if len(arguments) != 1 {
		return "", usage_problem(TYPE_USAGE)
	}
	typed := arguments[0]
	if !typed_text_valid(typed) {
		return "", fmt.tprintf("the text holds 1 to %d printable ASCII characters", MAXIMUM_TYPED_TEXT_LENGTH)
	}
	copy(input.injected.text[:], typed)
	input.injected.text_length = len(typed)
	return fmt.tprintf("typed %d %s", len(typed), len(typed) == 1 ? "character" : "characters"), ""
}

typed_text_valid :: proc(typed: string) -> bool {
	if len(typed) == 0 || len(typed) > MAXIMUM_TYPED_TEXT_LENGTH {
		return false
	}
	for character in transmute([]u8)typed {
		if character < ' ' || character > '~' {
			return false
		}
	}
	return true
}

// Runs an input command: refused without --input=none; on success the
// answer waits for answer_input_command.
execute_input_command :: proc(command_context: Command_Context, name: string, arguments: []string) -> Command_Response {
	input := command_context.input
	if input.injected == nil {
		return command_error(NO_INPUT_HERE_PROBLEM)
	}
	if !input.devices_off {
		return command_error(INPUT_NEEDS_NONE_PROBLEM)
	}
	answer, problem: string
	switch name {
	case "press":
		answer, problem = command_press(input, arguments)
	case "hold":
		answer, problem = command_hold(input, arguments)
	case "release":
		answer, problem = command_release(input, arguments)
	case "stick":
		answer, problem = command_stick(input, arguments)
	case "trigger":
		answer, problem = command_trigger(input, arguments)
	case "pointer":
		answer, problem = command_pointer(input, arguments)
	case "type":
		answer, problem = command_type(input, arguments)
	}
	if problem != "" {
		return command_error("%s", problem)
	}
	note_injected_change(input.injected)
	control := command_context.control
	delete(control.input_answer)
	control.input_waiting = true
	control.input_answer = strings.clone(answer)
	return Command_Response{ok = true, deferred = true}
}

lower_name :: proc(value: any) -> string {
	return strings.to_lower(fmt.tprint(value), context.temp_allocator)
}

// The first viewport's UI after its last pass: the screens bottom to
// top, the glyphs' device, the pointer and the focused widget in render
// pixels, the text field and the input backend.
query_ui :: proc(input: Command_Input_Context, arguments: []string) -> Command_Response {
	if input.ui == nil {
		return command_error(NO_INPUT_HERE_PROBLEM)
	}
	if len(arguments) > 0 {
		return usage_error("query ui")
	}
	ui := input.ui
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "ui\nscreens")
	if ui.screens.count == 0 {
		strings.write_string(&builder, " none")
	}
	for screen in ui.screens.screens[:ui.screens.count] {
		fmt.sbprintf(&builder, " %s", lower_name(screen))
	}
	fmt.sbprintf(&builder, "\ntop %s", ui.screens.count > 0 ? lower_name(top_screen(ui.screens)) : "none")
	fmt.sbprintf(&builder, "\ndevice %s", lower_name(ui.active_device))
	scale := ui.pixels_per_unit
	fmt.sbprintf(&builder, "\npointer %.1f %.1f %s", ui.pointer.x * scale, ui.pointer.y * scale, lower_name(ui.pointer_source))
	if index := widget_index(ui.widgets[:], ui.focus); index >= 0 {
		rectangle := ui.widgets[index].rectangle
		fmt.sbprintf(&builder, "\nfocus %d %d %d %d", rounded_pixels(rectangle.x, scale), rounded_pixels(rectangle.y, scale), rounded_pixels(rectangle.width, scale), rounded_pixels(rectangle.height, scale))
	} else {
		strings.write_string(&builder, "\nfocus none")
	}
	fmt.sbprintf(&builder, "\ntext_field %s", ui.keyboard.field != 0 ? "open" : "closed")
	fmt.sbprintf(&builder, "\nbackend %s", input.devices_off ? "none" : backend_names[input.backend])
	return query_response(&builder)
}

rounded_pixels :: proc(units, pixels_per_unit: f32) -> int {
	return int(math.round(units * pixels_per_unit))
}
