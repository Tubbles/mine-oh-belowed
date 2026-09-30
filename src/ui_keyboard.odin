package game

import "core:slice"
import "core:strings"

// The text field widget and the on-screen keyboard drawn under it
// (doc/ui.md, On-screen keyboard). The logic is in text_input.odin.

KEYBOARD_KEY_WIDTH :: 72
KEYBOARD_KEY_HEIGHT :: 64
KEYBOARD_COLUMNS :: 10
KEYBOARD_ROW_COUNT :: len(keyboard_character_rows) + 1
KEYBOARD_WIDTH :: KEYBOARD_COLUMNS * (KEYBOARD_KEY_WIDTH + UI_GAP) - UI_GAP
KEYBOARD_HEIGHT :: KEYBOARD_ROW_COUNT * (KEYBOARD_KEY_HEIGHT + UI_GAP) - UI_GAP
TEXT_FIELD_CARET :: "_"

// Label on the left, the text on the right, with a caret while the
// keyboard types into it. Activating it is the caller's cue to open the
// keyboard (open_keyboard).
ui_text_field :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, field: ^Text_Field, tooltip := "") -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {}, tooltip)
	widget_background(state, rectangle, id, interaction)
	draw_text_field_content(state, rectangle, label, field, state.keyboard.field == id)
	return interaction.activated
}

draw_text_field_content :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, field: ^Text_Field, editing: bool) {
	content := inset(rectangle, UI_PADDING)
	draw_text(state, content, label, UI_BODY_TEXT_SIZE, .Left)
	value := text_field_text(field)
	if editing {
		value = strings.concatenate({value, TEXT_FIELD_CARET}, context.temp_allocator)
	}
	draw_text(state, content, value, UI_BODY_TEXT_SIZE, .Right, editing ? UI_ACCENT_COLOR : UI_TEXT_COLOR)
}

// The field with this id takes the keyboard's input from the next frame,
// through the system keyboard where the frame loop allows it
// (Ui_State.system_keyboard).
open_keyboard :: proc(state: ^Ui_State, field: Ui_Id) {
	state.keyboard = Keyboard_State {
		field  = field,
		system = state.system_keyboard,
	}
}

// The height the keys take below the field, none with the system keyboard.
keyboard_keys_height :: proc(keyboard: Keyboard_State) -> f32 {
	return keyboard.system ? -UI_GAP : KEYBOARD_HEIGHT
}

keyboard_key_label :: proc(key: Keyboard_Key, shift: bool) -> string {
	switch key.kind {
	case .Character:
		label := make([]u8, 1, context.temp_allocator)
		label[0] = keyboard_character(key.character, shift)
		return string(label)
	case .Shift:
		return text("keyboard_shift")
	case .Space:
		return text("keyboard_space")
	case .Backspace:
		return text("keyboard_backspace")
	case .Done:
		return text("keyboard_done")
	}
	return ""
}

// Rows centred in the keyboard's width.
keyboard_row_origin :: proc(origin: [2]f32, row, width_in_keys: int) -> [2]f32 {
	row_width := f32(width_in_keys) * (KEYBOARD_KEY_WIDTH + UI_GAP) - UI_GAP
	return {origin.x + (KEYBOARD_WIDTH - row_width) / 2, origin.y + f32(row) * (KEYBOARD_KEY_HEIGHT + UI_GAP)}
}

key_rectangle :: proc(row_origin: [2]f32, column_in_keys, width_in_keys: int) -> Ui_Rectangle {
	x := row_origin.x + f32(column_in_keys) * (KEYBOARD_KEY_WIDTH + UI_GAP)
	width := f32(width_in_keys) * (KEYBOARD_KEY_WIDTH + UI_GAP) - UI_GAP
	return {x, row_origin.y, width, KEYBOARD_KEY_HEIGHT}
}

// One key; returns true when activated. Shift shows lit while on.
ui_keyboard_key :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, key: Keyboard_Key, index: int) -> bool {
	id := ui_id(state, "key", index)
	interaction := ui_interact(state, id, rectangle)
	lit := key.kind == .Shift && state.keyboard.shift
	draw_fill(state, rectangle, lit ? UI_ACCENT_COLOR : (interaction.hovered ? UI_HOVER_COLOR : UI_WIDGET_COLOR))
	draw_focus_outline(state, rectangle, id)
	draw_text(state, rectangle, keyboard_key_label(key, state.keyboard.shift), UI_BODY_TEXT_SIZE, .Centre, lit ? UI_PANEL_COLOR : UI_TEXT_COLOR)
	return interaction.activated
}

// Declares every key and returns the one activated this frame.
declare_keyboard_keys :: proc(state: ^Ui_State, origin: [2]f32) -> (key: Keyboard_Key, pressed: bool) {
	index := 0
	for characters, row in keyboard_character_rows {
		row_origin := keyboard_row_origin(origin, row, len(characters))
		for character, column in transmute([]u8)characters {
			character_key := Keyboard_Key{kind = .Character, character = character, width = 1}
			if ui_keyboard_key(state, key_rectangle(row_origin, column, 1), character_key, index) {
				key, pressed = character_key, true
			}
			index += 1
		}
	}
	action_width := 0
	for action_key in keyboard_action_row {
		action_width += action_key.width
	}
	row_origin := keyboard_row_origin(origin, len(keyboard_character_rows), action_width)
	column := 0
	for action_key in keyboard_action_row {
		if ui_keyboard_key(state, key_rectangle(row_origin, column, action_key.width), action_key, index) {
			key, pressed = action_key, true
		}
		column += action_key.width
		index += 1
	}
	return
}

// A tap this frame, and whether it landed in the rectangle.
pointer_tap :: proc(state: Ui_State, rectangle: Ui_Rectangle) -> (tapped, inside: bool) {
	tapped = state.pointer_released && !state.pointer_press.moved
	return tapped, tapped && rectangle_contains(rectangle, state.pointer_press.position)
}

// The keys with their top left at the origin, inside the caller's panel,
// so focus moves only between keys. Returns true when the entry is done;
// the caller then closes the keyboard (state.keyboard = {}). With the
// system keyboard no keys are drawn and the field takes the physical
// keyboard's path; a tap on the field or Confirm (the field is all the
// entry shows) shows the system keyboard again (the phone's Back hides
// it and Steam may close it by itself, leaving the entry open), a tap
// elsewhere ends the entry.
ui_on_screen_keyboard :: proc(state: ^Ui_State, field_rectangle: Ui_Rectangle, origin: [2]f32, field: ^Text_Field) -> bool {
	ui_push_id(state, "keyboard")
	defer ui_pop_id(state)
	key: Keyboard_Key
	pressed: bool
	if state.keyboard.system {
		state.keyboard.field_rectangle = field_rectangle
		tapped, on_field := pointer_tap(state^, field_rectangle)
		if tapped && !on_field {
			return true
		}
		state.keyboard.show_requested ||= on_field || state.confirm
	} else {
		key, pressed = declare_keyboard_keys(state, origin)
	}
	input := state.input
	keyboard_input := Keyboard_Input {
		key_pressed      = pressed,
		key              = key,
		backspace_button = input.context_action,
		shift_button     = input.info,
		done_button      = input.back || input.pause,
		typed_text       = string(state.input.typed_text[:input.typed_text_length]),
		backspace_key    = input.backspace_key,
		enter_key        = input.enter_key,
	}
	return advance_keyboard(field, &state.keyboard, keyboard_input)
}

// Without keys, Confirm shows the system keyboard again and Shift has
// nothing to shift.
keyboard_glyph_hints :: proc(keyboard: Keyboard_State) -> []Glyph_Hint {
	if keyboard.system {
		return slice.clone([]Glyph_Hint{{.Confirm, text("keyboard_show")}, {.Context_Action, text("keyboard_backspace")}, {.Back, text("keyboard_done")}}, context.temp_allocator)
	}
	return slice.clone([]Glyph_Hint{{.Confirm, text("hint_type")}, {.Context_Action, text("keyboard_backspace")}, {.Info, text("keyboard_shift")}, {.Back, text("keyboard_done")}}, context.temp_allocator)
}
