package game

import "core:testing"

character_key :: proc(character: u8) -> Keyboard_Key {
	return Keyboard_Key{kind = .Character, character = character, width = 1}
}

press_key :: proc(field: ^Text_Field, keyboard: ^Keyboard_State, key: Keyboard_Key) -> bool {
	return advance_keyboard(field, keyboard, Keyboard_Input{key_pressed = true, key = key})
}

@(test)
test_keyboard_types_with_shift_and_space :: proc(t: ^testing.T) {
	field := make_text_field("", 16)
	keyboard: Keyboard_State
	press_key(&field, &keyboard, character_key('a'))
	press_key(&field, &keyboard, Keyboard_Key{kind = .Shift})
	testing.expect(t, keyboard.shift)
	press_key(&field, &keyboard, character_key('b'))
	press_key(&field, &keyboard, character_key('1'))
	advance_keyboard(&field, &keyboard, Keyboard_Input{shift_button = true})
	testing.expect(t, !keyboard.shift, "Y toggles shift off again")
	press_key(&field, &keyboard, Keyboard_Key{kind = .Space, character = ' '})
	press_key(&field, &keyboard, character_key('-'))
	testing.expect_value(t, text_field_text(&field), "aB1 -")
}

@(test)
test_keyboard_backspace_and_done :: proc(t: ^testing.T) {
	field := make_text_field("abc", 16)
	keyboard: Keyboard_State
	testing.expect(t, !press_key(&field, &keyboard, Keyboard_Key{kind = .Backspace}))
	testing.expect(t, !advance_keyboard(&field, &keyboard, Keyboard_Input{backspace_button = true}), "X deletes")
	testing.expect_value(t, text_field_text(&field), "a")
	advance_keyboard(&field, &keyboard, Keyboard_Input{backspace_button = true})
	advance_keyboard(&field, &keyboard, Keyboard_Input{backspace_button = true})
	testing.expect_value(t, text_field_text(&field), "")
	testing.expect(t, press_key(&field, &keyboard, Keyboard_Key{kind = .Done}))
	testing.expect(t, advance_keyboard(&field, &keyboard, Keyboard_Input{done_button = true}), "B is done")
	testing.expect(t, !advance_keyboard(&field, &keyboard, Keyboard_Input{}))
}

@(test)
test_text_field_maximum_length :: proc(t: ^testing.T) {
	field := make_text_field("abcdefgh", 4)
	testing.expect_value(t, text_field_text(&field), "abcd")
	keyboard: Keyboard_State
	press_key(&field, &keyboard, character_key('z'))
	testing.expect_value(t, text_field_text(&field), "abcd")
	advance_keyboard(&field, &keyboard, Keyboard_Input{typed_text = "xyz"})
	testing.expect_value(t, text_field_text(&field), "abcd")
	testing.expect_value(t, make_text_field("", TEXT_FIELD_CAPACITY + 10).maximum_length, TEXT_FIELD_CAPACITY)
}

// A physical key also fires the action bound to it (F is the context
// action, Backspace is Back), so in a frame with typing the buttons count
// for nothing.
@(test)
test_physical_typing_ignores_the_button_meanings :: proc(t: ^testing.T) {
	field := make_text_field("ab", 16)
	keyboard: Keyboard_State
	done := advance_keyboard(&field, &keyboard, Keyboard_Input{typed_text = "fR", backspace_button = true, shift_button = true})
	testing.expect(t, !done)
	testing.expect(t, !keyboard.shift)
	testing.expect_value(t, text_field_text(&field), "abfR")
	done = advance_keyboard(&field, &keyboard, Keyboard_Input{backspace_key = true, done_button = true})
	testing.expect(t, !done, "the Backspace key deletes instead of finishing")
	testing.expect_value(t, text_field_text(&field), "abf")
	testing.expect(t, advance_keyboard(&field, &keyboard, Keyboard_Input{enter_key = true, key_pressed = true, key = character_key('q')}), "Enter is done")
	testing.expect_value(t, text_field_text(&field), "abf")
}

@(test)
test_seed_field_takes_digits_only :: proc(t: ^testing.T) {
	setup := make_world_setup(World_File_Settings{day_length_seconds = 1200}, "New world", 42)
	keyboard: Keyboard_State
	testing.expect_value(t, text_field_text(&setup.seed), "42")
	press_key(&setup.seed, &keyboard, character_key('a'))
	press_key(&setup.seed, &keyboard, character_key('-'))
	press_key(&setup.seed, &keyboard, character_key('7'))
	testing.expect_value(t, text_field_text(&setup.seed), "427")
	seed, ok := world_setup_seed(&setup)
	testing.expect(t, ok)
	testing.expect_value(t, seed, 427)
	text_field_set(&setup.seed, "")
	_, ok = world_setup_seed(&setup)
	testing.expect(t, !ok, "an empty seed is invalid")
	text_field_set(&setup.seed, "18446744073709551616")
	_, ok = world_setup_seed(&setup)
	testing.expect(t, !ok, "a seed past the u64 range is invalid")
	text_field_set(&setup.seed, "18446744073709551615")
	seed, ok = world_setup_seed(&setup)
	testing.expect(t, ok)
	testing.expect_value(t, seed, max(u64))
	text_field_set(&setup.seed, "123456789012345678901234")
	testing.expect_value(t, setup.seed.length, SEED_MAXIMUM_LENGTH)
}
