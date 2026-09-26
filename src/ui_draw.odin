package game

import "core:strings"
import rl "vendor:raylib"

// The only UI file that calls raylib: it turns the draw list into pixels.
// raylib's default font is a 10 pixel bitmap scaled up; a TTF from
// data/fonts/ replaces it once one is chosen.

DEFAULT_FONT_SPACING_FACTOR :: 0.1

to_pixels :: proc(rectangle: Ui_Rectangle, pixels_per_unit: f32) -> rl.Rectangle {
	return {rectangle.x * pixels_per_unit, rectangle.y * pixels_per_unit, rectangle.width * pixels_per_unit, rectangle.height * pixels_per_unit}
}

to_raylib_color :: proc(color: Ui_Color) -> rl.Color {
	return rl.Color(color)
}

// Text width scales linearly with the size, so measuring at the size in
// units gives the width in units.
raylib_measure_text :: proc(text: string, size: f32) -> f32 {
	text_c := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(rl.GetFontDefault(), text_c, size, size * DEFAULT_FONT_SPACING_FACTOR).x
}

execute_text_command :: proc(command: Draw_Command, pixels_per_unit: f32) {
	box := to_pixels(command.rectangle, pixels_per_unit)
	size := command.text_size * pixels_per_unit
	spacing := size * DEFAULT_FONT_SPACING_FACTOR
	text_c := strings.clone_to_cstring(command.text, context.temp_allocator)
	width := rl.MeasureTextEx(rl.GetFontDefault(), text_c, size, spacing).x
	x := box.x
	switch command.alignment {
	case .Left:
	case .Centre:
		x += (box.width - width) / 2
	case .Right:
		x += box.width - width
	}
	y := box.y + (box.height - size) / 2
	rl.DrawTextEx(rl.GetFontDefault(), text_c, {x, y}, size, spacing, to_raylib_color(command.color))
}

execute_draw_command :: proc(command: Draw_Command, focus: Ui_Id, pixels_per_unit: f32) {
	switch command.kind {
	case .Fill:
		rl.DrawRectangleRec(to_pixels(command.rectangle, pixels_per_unit), to_raylib_color(command.color))
	case .Outline:
		rl.DrawRectangleLinesEx(to_pixels(command.rectangle, pixels_per_unit), command.thickness * pixels_per_unit, to_raylib_color(command.color))
	case .Focus_Outline:
		if command.widget == focus {
			rl.DrawRectangleLinesEx(to_pixels(command.rectangle, pixels_per_unit), command.thickness * pixels_per_unit, to_raylib_color(command.color))
		}
	case .Text:
		execute_text_command(command, pixels_per_unit)
	case .Clip_Begin:
		box := to_pixels(command.rectangle, pixels_per_unit)
		rl.BeginScissorMode(i32(box.x), i32(box.y), i32(box.width), i32(box.height))
	case .Clip_End:
		rl.EndScissorMode()
	}
}

execute_draw_list :: proc(state: Ui_State) {
	for command in state.draw_list {
		execute_draw_command(command, state.focus, state.pixels_per_unit)
	}
}
