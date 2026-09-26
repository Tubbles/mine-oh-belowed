package game

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

DIAGNOSTICS_MARGIN :: 16
DIAGNOSTICS_TEXT_COLOR :: rl.Color{230, 230, 230, 255}
DIAGNOSTICS_ACTIVE_COLOR :: rl.Color{120, 230, 120, 255}

Diagnostics_Line :: struct {
	text:   string,
	active: bool,
}

enum_label :: proc(value: $T) -> string {
	return fmt.tprint(value)
}

// 20 pixels at 720 lines, 30 at 1080, so the text stays readable from the couch.
diagnostics_font_size :: proc(screen_height: i32) -> i32 {
	return max(20, screen_height / 36)
}

append_line :: proc(lines: ^[dynamic]Diagnostics_Line, active: bool, format: string, arguments: ..any) {
	append(lines, Diagnostics_Line{text = fmt.tprintf(format, ..arguments), active = active})
}

mapped_lines :: proc(state: Frame_State, config: Game_Config) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	input := state.input
	append_line(&lines, false, "%s  controller diagnostics", config.name)
	append_line(&lines, false, "tick %d  fps %d  alpha %.2f", state.simulation.tick, rl.GetFPS(), interpolation_alpha(state.accumulator))
	append_line(&lines, false, "backend %v", input.raw.backend)
	append_line(&lines, false, "")
	append_line(&lines, input.move != {}, "move        % .3f % .3f", input.move.x, input.move.y)
	append_line(&lines, input.look != {}, "look        % .3f % .3f", input.look.x, input.look.y)
	append_line(&lines, input.look_delta != {}, "look delta  % .1f % .1f", input.look_delta.x, input.look_delta.y)
	append_line(&lines, false, "")
	for action in Action {
		append_line(&lines, action in input.pressed, "%-16v %s", action, action_state_label(action, input))
	}
	return lines[:]
}

action_state_label :: proc(action: Action, input: Input_Frame) -> string {
	if action in input.just_pressed {
		return "just pressed"
	}
	if action in input.pressed {
		return "down"
	}
	return "-"
}

gamepad_axis_label :: proc(backend: Input_Backend, index: int) -> string {
	switch backend {
	case .Raylib:
		return raylib_gamepad_axis_label(index)
	}
	return ""
}

gamepad_button_label :: proc(backend: Input_Backend, index: int) -> string {
	switch backend {
	case .Raylib:
		return raylib_gamepad_button_label(index)
	}
	return ""
}

mouse_button_label :: proc(backend: Input_Backend, index: int) -> string {
	switch backend {
	case .Raylib:
		return raylib_mouse_button_label(index)
	}
	return ""
}

key_label :: proc(backend: Input_Backend, code: i32) -> string {
	switch backend {
	case .Raylib:
		return raylib_key_label(code)
	}
	return ""
}

gamepad_lines :: proc(raw: Raw_Input) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	gamepad := raw.gamepad
	if !gamepad.connected {
		append_line(&lines, false, "gamepad: none connected")
		return lines[:]
	}
	append_line(&lines, false, "gamepad %d: %s", gamepad.index, gamepad.name)
	for index in 0 ..< gamepad.axis_count {
		value := gamepad.axis_values[index]
		append_line(&lines, value != 0, "%-16s % .3f", gamepad_axis_label(raw.backend, index), value)
	}
	for index in 0 ..< gamepad.button_count {
		down := gamepad.button_down[index]
		append_line(&lines, down, "%-16s %s", gamepad_button_label(raw.backend, index), down ? "down" : "-")
	}
	return lines[:]
}

keyboard_mouse_lines :: proc(raw: Raw_Input) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	mouse := raw.mouse
	append_line(&lines, false, "mouse position % .0f % .0f", mouse.position.x, mouse.position.y)
	append_line(&lines, mouse.delta != {}, "mouse delta    % .1f % .1f", mouse.delta.x, mouse.delta.y)
	append_line(&lines, mouse.wheel != {}, "mouse wheel    % .1f % .1f", mouse.wheel.x, mouse.wheel.y)
	for index in 0 ..< mouse.button_count {
		if mouse.button_down[index] {
			append_line(&lines, true, "mouse %s down", mouse_button_label(raw.backend, index))
		}
	}
	append_line(&lines, raw.keyboard.key_count > 0, "keys down: %s", keys_down_text(raw))
	return lines[:]
}

keys_down_text :: proc(raw: Raw_Input) -> string {
	keyboard := raw.keyboard
	labels := make([]string, keyboard.key_count, context.temp_allocator)
	for index in 0 ..< keyboard.key_count {
		labels[index] = key_label(raw.backend, keyboard.keys_down[index])
	}
	text := strings.join(labels, " ", context.temp_allocator)
	if keyboard.keys_truncated {
		return fmt.tprintf("%s ...", text)
	}
	return text
}

draw_lines :: proc(lines: []Diagnostics_Line, x, y, font_size: i32) -> i32 {
	line_y := y
	for line in lines {
		color := line.active ? DIAGNOSTICS_ACTIVE_COLOR : DIAGNOSTICS_TEXT_COLOR
		rl.DrawText(strings.clone_to_cstring(line.text, context.temp_allocator), x, line_y, font_size, color)
		line_y += font_size + font_size / 5
	}
	return line_y
}

draw_diagnostics :: proc(state: Frame_State, config: Game_Config) {
	font_size := diagnostics_font_size(rl.GetScreenHeight())
	right_column_x := rl.GetScreenWidth() / 2
	left_bottom := draw_lines(mapped_lines(state, config), DIAGNOSTICS_MARGIN, DIAGNOSTICS_MARGIN, font_size)
	draw_lines(keyboard_mouse_lines(state.input.raw), DIAGNOSTICS_MARGIN, left_bottom + font_size, font_size)
	draw_lines(gamepad_lines(state.input.raw), right_column_x, DIAGNOSTICS_MARGIN, font_size)
}
