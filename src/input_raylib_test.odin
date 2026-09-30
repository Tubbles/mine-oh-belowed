package game

import "core:testing"
import rl "shared:raylib"

@(test)
test_touch_pointer_position_follows_the_first_touch_and_stays_after_it_lifts :: proc(t: ^testing.T) {
	testing.expect_value(t, touch_pointer_position(1, {300, 200}, {10, 20}), [2]f32{300, 200})
	testing.expect_value(t, touch_pointer_position(2, {300, 200}, {10, 20}), [2]f32{300, 200})
	// raylib leaves the lifted touch's position behind, or -1, -1.
	testing.expect_value(t, touch_pointer_position(0, {-1, -1}, {300, 200}), [2]f32{300, 200})
}

// Work item 0133: the phone's typed text from raylib's pressed keys.
@(test)
test_character_for_key :: proc(t: ^testing.T) {
	testing.expect_value(t, character_for_key(.A, false), 'a')
	testing.expect_value(t, character_for_key(.Q, true), 'Q')
	testing.expect_value(t, character_for_key(.SEVEN, false), '7')
	testing.expect_value(t, character_for_key(.SPACE, false), ' ')
	testing.expect_value(t, character_for_key(.MINUS, false), '-')
	testing.expect_value(t, character_for_key(.MINUS, true), '_')
	testing.expect_value(t, character_for_key(.SLASH, false), '/')
	testing.expect_value(t, character_for_key(.GRAVE, false), '`')
	testing.expect_value(t, character_for_key(.GRAVE, true), '~')
	testing.expect_value(t, character_for_key(.BACKSLASH, false), '\\')
	testing.expect_value(t, character_for_key(.BACKSLASH, true), '|')
	testing.expect_value(t, character_for_key(.ENTER, false), 0)
	testing.expect_value(t, character_for_key(.LEFT_SHIFT, true), 0)
}

@(test)
test_a_queued_shift_capitalises_the_next_letter_and_backspaces_stay_in_place :: proc(t: ^testing.T) {
	keyboard: Raw_Keyboard
	keys := [?]rl.KeyboardKey{.LEFT_SHIFT, .H, .I, .BACKSPACE, .ENTER, .RIGHT_SHIFT, .ONE}
	testing.expect(t, !append_characters_for_keys(&keyboard, keys[:], false, false))
	testing.expect_value(t, string(keyboard.text[:keyboard.text_length]), "Hi\b!")
	held: Raw_Keyboard
	append_characters_for_keys(&held, keys[1:3], true, false)
	testing.expect_value(t, string(held.text[:held.text_length]), "HI")
	add_pressed_keys(&keyboard, keys[:])
	testing.expect(t, keyboard_holds_key(keyboard, KEY_CODE_BACKSPACE))
	testing.expect(t, keyboard_holds_key(keyboard, KEY_CODE_ENTER))
	add_pressed_keys(&keyboard, keys[3:4])
	testing.expect_value(t, keyboard.key_count, len(keys))
}

// A Shift and its letter in two polls still give the upper case letter;
// a frame without any key after the Shift drops it.
@(test)
test_a_pending_shift_carries_to_the_next_frame_until_an_empty_frame :: proc(t: ^testing.T) {
	keyboard: Raw_Keyboard
	shift := [?]rl.KeyboardKey{.LEFT_SHIFT}
	letter := [?]rl.KeyboardKey{.K}
	pending := append_characters_for_keys(&keyboard, shift[:], false, false)
	testing.expect(t, pending)
	pending = append_characters_for_keys(&keyboard, letter[:], false, pending)
	testing.expect(t, !pending)
	testing.expect_value(t, string(keyboard.text[:keyboard.text_length]), "K")
	later: Raw_Keyboard
	pending = append_characters_for_keys(&later, shift[:], false, false)
	pending = append_characters_for_keys(&later, {}, false, pending)
	testing.expect(t, !pending, "a frame with no key drops the Shift")
	pending = append_characters_for_keys(&later, letter[:], false, pending)
	testing.expect_value(t, string(later.text[:later.text_length]), "k")
}

// On the desktop too a key pressed and released within one poll (Steam's
// virtual keyboard) is down for its frame, so the text field's Backspace
// and Enter edges and the letter jump see it.
@(test)
test_a_key_pressed_and_released_in_one_poll_reads_as_newly_pressed :: proc(t: ^testing.T) {
	previous: Raw_Keyboard
	current: Raw_Keyboard
	keys := [?]rl.KeyboardKey{.BACKSPACE, .ENTER, .J}
	add_pressed_keys(&current, keys[:])
	testing.expect(t, key_newly_pressed(previous, current, KEY_CODE_BACKSPACE))
	testing.expect(t, key_newly_pressed(previous, current, KEY_CODE_ENTER))
	testing.expect_value(t, newly_pressed_letter(previous, current), 'j')
	// Held from the last frame, a queued press adds no second entry.
	held := current
	add_pressed_keys(&held, keys[:1])
	testing.expect_value(t, held.key_count, len(keys))
	testing.expect(t, !key_newly_pressed(current, held, KEY_CODE_BACKSPACE))
}

@(test)
test_the_steam_keyboard_rectangle_is_in_window_coordinates :: proc(t: ^testing.T) {
	field := Ui_Rectangle{100, 50, 400, 56}
	// X11: the window and the framebuffer are both pixels.
	testing.expect_value(t, units_to_window_rectangle(field, 1.5, {1920, 1080}, {1920, 1080}), Ui_Rectangle{150, 75, 600, 84})
	// A Wayland desktop at scale 1.5: logical coordinates are smaller.
	testing.expect_value(t, units_to_window_rectangle(field, 1.5, {1280, 720}, {1920, 1080}), field)
	// A minimised window leaves the render pixels.
	testing.expect_value(t, units_to_window_rectangle(field, 2, {0, 0}, {1920, 1080}), Ui_Rectangle{200, 100, 800, 112})
}
