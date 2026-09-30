package game

// Text fields and the on-screen keyboard's logic (doc/ui.md, On-screen
// keyboard), free of the UI so tests drive it directly. The widget that
// draws the keys is in ui_keyboard.odin.

// Long enough for the longest string of data/strings/en.sjson, which the
// Data files screen edits (work item 0130); a field's maximum_length is
// what limits a world name or a seed.
TEXT_FIELD_CAPACITY :: 512
// In typed text, one Backspace in its place among the characters: the
// phone's IME can press Backspace more than once in a frame (0133).
TEXT_BACKSPACE :: '\b'

// What a field takes. Printable is printable ASCII: the default font
// draws nothing else, and world names become directory names. Number is
// the digits, '-', '+', '.', 'e' and 'E' (a value in the Data files
// screen, 0130, where a float may print as 1e-05).
Text_Field_Characters :: enum u8 {
	Printable,
	Digits,
	Number,
}

Text_Field :: struct {
	buffer:         [TEXT_FIELD_CAPACITY]u8,
	length:         int,
	maximum_length: int,
	characters:     Text_Field_Characters,
}

Keyboard_Key_Kind :: enum u8 {
	Character,
	Shift,
	Space,
	Backspace,
	Done,
}

Keyboard_Key :: struct {
	kind:      Keyboard_Key_Kind,
	// Lower case for letters; shift makes them upper case.
	character: u8,
	// In key widths.
	width:     int,
}

// Rows of single width character keys, then the row of large keys.
@(rodata)
keyboard_character_rows := [?]string{"1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm", "-_."}

@(rodata)
keyboard_action_row := [?]Keyboard_Key{{kind = .Shift, width = 2}, {kind = .Space, character = ' ', width = 4}, {kind = .Backspace, width = 2}, {kind = .Done, width = 2}}

// The field the keyboard types into (0 while closed) and the shift state.
// return_focus is the field to focus once the screen shows it again after
// the keyboard closed. With system set the entry types through the system
// keyboard (work item 0133, system_keyboard_*.odin) and the screens draw
// no keys: field_rectangle is where the field was drawn, in UI units, for
// the system keyboard's position, and show_requested asks the frame loop
// to show it again (sync_system_keyboard).
Keyboard_State :: struct {
	field:           Ui_Id,
	shift:           bool,
	return_focus:    Ui_Id,
	system:          bool,
	field_rectangle: Ui_Rectangle,
	show_requested:  bool,
}

System_Keyboard_Change :: enum u8 {
	None,
	Show,
	Hide,
}

// What the frame loop does with the system keyboard, shown or not, for
// this frame's keyboard state. It shows once the field has been drawn,
// so the keyboard knows where the field is.
system_keyboard_change :: proc(keyboard: Keyboard_State, shown: bool) -> System_Keyboard_Change {
	open := keyboard.field != 0 && keyboard.system
	switch {
	case open && keyboard.field_rectangle != {} && (!shown || keyboard.show_requested):
		return .Show
	case !open && shown:
		return .Hide
	}
	return .None
}

// What one frame asks of the keyboard. The buttons: X backspace, Y shift,
// B (or Pause) done. Physical keys: the characters typed, Backspace and
// Enter.
Keyboard_Input :: struct {
	key_pressed:      bool,
	key:              Keyboard_Key,
	backspace_button: bool,
	shift_button:     bool,
	done_button:      bool,
	typed_text:       string,
	backspace_key:    bool,
	enter_key:        bool,
}

make_text_field :: proc(value: string, maximum_length: int, characters := Text_Field_Characters.Printable) -> Text_Field {
	field := Text_Field {
		maximum_length = min(maximum_length, TEXT_FIELD_CAPACITY),
		characters     = characters,
	}
	text_field_set(&field, value)
	return field
}

// Valid while the field is.
text_field_text :: proc(field: ^Text_Field) -> string {
	return string(field.buffer[:field.length])
}

// Keeps the characters the field accepts, up to its maximum length.
text_field_set :: proc(field: ^Text_Field, value: string) {
	field.length = 0
	for character in transmute([]u8)value {
		text_field_type(field, character)
	}
}

text_field_accepts :: proc(field: Text_Field, character: u8) -> bool {
	if field.length >= field.maximum_length {
		return false
	}
	return text_field_character_accepted(field.characters, character)
}

text_field_character_accepted :: proc(characters: Text_Field_Characters, character: u8) -> bool {
	digit := character >= '0' && character <= '9'
	switch characters {
	case .Digits:
		return digit
	case .Number:
		return digit || character == '-' || character == '+' || character == '.' || character == 'e' || character == 'E'
	case .Printable:
	}
	return character >= ' ' && character <= '~'
}

// Whether a field of these characters holds the value unchanged: every
// character accepted and no longer than the capacity.
text_field_holds :: proc(characters: Text_Field_Characters, value: string) -> bool {
	if len(value) > TEXT_FIELD_CAPACITY {
		return false
	}
	for character in transmute([]u8)value {
		if !text_field_character_accepted(characters, character) {
			return false
		}
	}
	return true
}

text_field_type :: proc(field: ^Text_Field, character: u8) -> bool {
	if !text_field_accepts(field^, character) {
		return false
	}
	field.buffer[field.length] = character
	field.length += 1
	return true
}

text_field_backspace :: proc(field: ^Text_Field) {
	field.length = max(field.length - 1, 0)
}

keyboard_character :: proc(character: u8, shift: bool) -> u8 {
	if shift && character >= 'a' && character <= 'z' {
		return character - 'a' + 'A'
	}
	return character
}

// Returns true for Done.
apply_keyboard_key :: proc(field: ^Text_Field, keyboard: ^Keyboard_State, key: Keyboard_Key) -> bool {
	switch key.kind {
	case .Character:
		text_field_type(field, keyboard_character(key.character, keyboard.shift))
	case .Space:
		text_field_type(field, ' ')
	case .Shift:
		keyboard.shift = !keyboard.shift
	case .Backspace:
		text_field_backspace(field)
	case .Done:
		return true
	}
	return false
}

// Returns true when the entry is done. Physical keys also trigger the
// actions bound to them (F is the context action, R the info panel,
// Backspace is Back, Enter is Confirm), so in a frame with physical
// typing the button meanings are ignored. Typed text that carries its
// Backspaces (TEXT_BACKSPACE) counts those instead of the Backspace key.
advance_keyboard :: proc(field: ^Text_Field, keyboard: ^Keyboard_State, input: Keyboard_Input) -> bool {
	if input.typed_text != "" || input.backspace_key || input.enter_key {
		backspaces_in_text := false
		for character in transmute([]u8)input.typed_text {
			if character == TEXT_BACKSPACE {
				text_field_backspace(field)
				backspaces_in_text = true
			} else {
				text_field_type(field, character)
			}
		}
		if input.backspace_key && !backspaces_in_text {
			text_field_backspace(field)
		}
		return input.enter_key
	}
	if input.key_pressed && apply_keyboard_key(field, keyboard, input.key) {
		return true
	}
	if input.backspace_button {
		text_field_backspace(field)
	}
	if input.shift_button {
		keyboard.shift = !keyboard.shift
	}
	return input.done_button
}
