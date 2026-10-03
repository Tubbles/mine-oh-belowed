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
	setup := make_world_setup(World_File_Settings{day_length_seconds = 1200}, nil, "New world", 42)
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

// Work item 0133: the system keyboard.

@(test)
test_the_system_keyboard_shows_once_the_field_is_drawn_and_hides_after :: proc(t: ^testing.T) {
	state := Ui_State{system_keyboard = true}
	defer destroy_ui_state(&state)
	open_keyboard(&state, 7)
	testing.expect(t, state.keyboard.system)
	testing.expect_value(t, system_keyboard_change(state.keyboard, false), System_Keyboard_Change.None)
	state.keyboard.field_rectangle = {100, 100, 400, 56}
	testing.expect_value(t, system_keyboard_change(state.keyboard, false), System_Keyboard_Change.Show)
	testing.expect_value(t, system_keyboard_change(state.keyboard, true), System_Keyboard_Change.None)
	state.keyboard.show_requested = true
	testing.expect_value(t, system_keyboard_change(state.keyboard, true), System_Keyboard_Change.Show)
	testing.expect_value(t, system_keyboard_change(Keyboard_State{return_focus = 7}, true), System_Keyboard_Change.Hide)
	testing.expect_value(t, system_keyboard_change(Keyboard_State{}, false), System_Keyboard_Change.None)
	// The game's keys never involve the system keyboard.
	state.system_keyboard = false
	open_keyboard(&state, 7)
	state.keyboard.field_rectangle = {100, 100, 400, 56}
	testing.expect(t, !state.keyboard.system)
	testing.expect_value(t, system_keyboard_change(state.keyboard, false), System_Keyboard_Change.None)
}

typed_input :: proc(typed: string) -> Ui_Input {
	input: Ui_Input
	copy(input.typed_text[:], typed)
	input.typed_text_length = len(typed)
	return input
}

// The widgets of the frame outside the glyph bar.
panel_widget_count :: proc(state: Ui_State) -> int {
	count := 0
	for widget in state.widgets {
		if widget.panel != UI_GLYPH_BAR_PANEL {
			count += 1
		}
	}
	return count
}

// The new world screen with its name field open, through the system
// keyboard or the game's keys, drawn once.
open_new_world_name_entry :: proc(audit: ^Ui_Audit, state: ^Ui_State, system: bool) {
	text_field_set(&audit.title.setup.name, "")
	push_screen(&state.screens, .Title)
	push_screen(&state.screens, .New_World)
	state.keyboard = Keyboard_State {
		field  = 1,
		system = system,
	}
	screen_test_frame(audit, state, {})
}

@(test)
test_a_field_with_the_system_keyboard_draws_no_keys_and_takes_typed_text :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	game_keys := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&game_keys)
	open_new_world_name_entry(audit, &game_keys, false)
	testing.expect(t, panel_widget_count(game_keys) > 0, "the game's keys are widgets")
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	open_new_world_name_entry(audit, &state, true)
	testing.expect_value(t, panel_widget_count(state), 0)
	testing.expect(t, state.keyboard.field_rectangle != {}, "the field's place is known")
	testing.expect_value(t, system_keyboard_change(state.keyboard, false), System_Keyboard_Change.Show)
	screen_test_frame(audit, &state, typed_input("Deep"))
	screen_test_frame(audit, &state, {backspace_key = true})
	screen_test_frame(audit, &state, typed_input("p mine"))
	testing.expect_value(t, text_field_text(&audit.title.setup.name), "Deep mine")
	testing.expect_value(t, top_screen(state.screens), Screen.New_World)
	screen_test_frame(audit, &state, {enter_key = true})
	testing.expect_value(t, state.keyboard.field, 0)
	testing.expect_value(t, system_keyboard_change(state.keyboard, true), System_Keyboard_Change.Hide)
	testing.expect_value(t, top_screen(state.screens), Screen.New_World)
	testing.expect_value(t, text_field_text(&audit.title.setup.name), "Deep mine")
}

// A tap on the field shows the system keyboard again, a tap elsewhere
// ends the entry like Done; B ends it too.
@(test)
test_taps_and_back_with_the_system_keyboard :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	open_new_world_name_entry(audit, &state, true)
	on_field := rectangle_centre(state.keyboard.field_rectangle)
	screen_test_frame(audit, &state, touch_input(on_field, true, pressed = true))
	screen_test_frame(audit, &state, touch_input(on_field, false, moved = false))
	testing.expect(t, state.keyboard.show_requested)
	testing.expect_value(t, system_keyboard_change(state.keyboard, true), System_Keyboard_Change.Show)
	testing.expect(t, state.keyboard.field != 0)
	// Confirm (A with a gamepad only) asks for the keyboard again too;
	// the frame loop clears the request once it acted (sync_system_keyboard).
	state.keyboard.show_requested = false
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, system_keyboard_change(state.keyboard, true), System_Keyboard_Change.None)
	screen_test_frame(audit, &state, {confirm = true, device = .Gamepad, device_seen = true})
	testing.expect(t, state.keyboard.show_requested)
	testing.expect_value(t, system_keyboard_change(state.keyboard, true), System_Keyboard_Change.Show)
	testing.expect(t, state.keyboard.field != 0)
	state.keyboard.show_requested = false
	// Enter is also Confirm in the bindings: the entry ends, and the frame
	// loop hides the keyboard rather than showing it.
	screen_test_frame(audit, &state, {enter_key = true, confirm = true})
	testing.expect_value(t, state.keyboard.field, 0)
	testing.expect_value(t, system_keyboard_change(state.keyboard, true), System_Keyboard_Change.Hide)
	state.keyboard = Keyboard_State {
		field  = 1,
		system = true,
	}
	screen_test_frame(audit, &state, {})
	elsewhere := on_field + [2]f32{0, 300}
	screen_test_frame(audit, &state, touch_input(elsewhere, true, pressed = true))
	screen_test_frame(audit, &state, touch_input(elsewhere, false, moved = false))
	testing.expect_value(t, state.keyboard.field, 0)
	testing.expect_value(t, top_screen(state.screens), Screen.New_World)
	state.keyboard = Keyboard_State {
		field  = 1,
		system = true,
	}
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, state.keyboard.field, 0)
	testing.expect_value(t, top_screen(state.screens), Screen.New_World)
}

// Each Backspace the phone's IME pressed in a frame deletes one character,
// in its place, and the Backspace key's edge adds none on top.
@(test)
test_backspaces_in_typed_text_each_delete_once :: proc(t: ^testing.T) {
	field := make_text_field("mine", 32)
	keyboard: Keyboard_State
	advance_keyboard(&field, &keyboard, Keyboard_Input{typed_text = "\b\bxy\bz", backspace_key = true})
	testing.expect_value(t, text_field_text(&field), "mixz")
	advance_keyboard(&field, &keyboard, Keyboard_Input{backspace_key = true})
	testing.expect_value(t, text_field_text(&field), "mix")
}

// Work item 0131: the keys type a path for the export directory, so a row
// holds '/', and it types into a printable field.
@(test)
test_keyboard_rows_type_a_slash :: proc(t: ^testing.T) {
	found := false
	for row in keyboard_character_rows {
		for character in transmute([]u8)row {
			found ||= character == '/'
		}
	}
	testing.expect(t, found)
	field := make_text_field("", TEXT_FIELD_CAPACITY)
	keyboard: Keyboard_State
	press_key(&field, &keyboard, character_key('/'))
	press_key(&field, &keyboard, character_key('a'))
	testing.expect_value(t, text_field_text(&field), "/a")
}
