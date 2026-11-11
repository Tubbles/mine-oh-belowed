package game

import "core:testing"
import rl "shared:raylib"
import sdl "vendor:sdl3"

// The command socket's virtual devices (work item 0341) read as a
// device's frames, through the shipped bindings' SDL3 tables. A read is
// read_injected_input_frame, then advance_injected_input.

shipped_sdl3_tables :: proc(t: ^testing.T) -> Input_Bindings {
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Sdl3, context.temp_allocator)
	return tables
}

read_injected_test_frame :: proc(injected: ^Injected_Input, previous: Input_Frame, tables: Input_Bindings) -> Input_Frame {
	frame := read_injected_input_frame(injected^, previous.pressed, tables, {})
	advance_injected_input(injected)
	return frame
}

// The control of a binding's device and name, which must be one.
test_injected_control :: proc(device: Binding_Device, name: string) -> Injected_Control {
	control, ok := injected_control_of(device, name)
	assert(ok, name)
	return control
}

@(test)
test_a_press_reads_down_for_its_frames_and_settles_after_its_release :: proc(t: ^testing.T) {
	tables := shipped_sdl3_tables(t)
	injected: Injected_Input
	south := test_injected_control(.Gamepad, "SOUTH")
	set_injected_control(&injected, south, true)
	injected.press_control, injected.press_frames = south, 2
	note_injected_change(&injected)
	frame: Input_Frame
	for read in 1 ..= 4 {
		frame = read_injected_test_frame(&injected, frame, tables)
		down := read <= 2
		testing.expectf(t, (.Confirm in frame.pressed) == down && (.Jump in frame.pressed) == down, "read %d pressed %v", read, frame.pressed)
		testing.expectf(t, frame.raw.gamepad.button_down[int(sdl.GamepadButton.SOUTH)] == down, "read %d", read)
		testing.expectf(t, (.Confirm in frame.just_pressed) == (read == 1), "read %d just pressed %v", read, frame.just_pressed)
		testing.expectf(t, injected_input_settled(injected) == (read == 4), "read %d settled %v", read, injected_input_settled(injected))
	}
}

@(test)
test_typed_text_reaches_sixteen_characters_a_frame :: proc(t: ^testing.T) {
	tables := shipped_sdl3_tables(t)
	injected: Injected_Input
	typed := "abcdefghijklmnopqrstuvwxyz 123456789ABCD"
	testing.expect_value(t, len(typed), 40)
	copy(injected.text[:], typed)
	injected.text_length = len(typed)
	note_injected_change(&injected)
	expected := [?]string{typed[:16], typed[16:32], typed[32:], ""}
	frame: Input_Frame
	for wanted, index in expected {
		frame = read_injected_test_frame(&injected, frame, tables)
		keyboard := frame.raw.keyboard
		testing.expect_value(t, string(keyboard.text[:keyboard.text_length]), wanted)
		testing.expect_value(t, keyboard.key_count, 0)
		testing.expectf(t, injected_input_settled(injected) == (index == 3), "read %d", index + 1)
	}
}

// The device detect_input_device sees in the next read against the last.
next_injected_device :: proc(injected: ^Injected_Input, previous: ^Input_Frame, tables: Input_Bindings) -> (device: Input_Device, seen: bool) {
	note_injected_change(injected)
	current := read_injected_test_frame(injected, previous^, tables)
	device, seen = detect_input_device(previous.raw, current.raw)
	previous^ = current
	return
}

@(test)
test_the_virtual_devices_set_the_glyph_device_as_devices_do :: proc(t: ^testing.T) {
	tables := shipped_sdl3_tables(t)
	injected: Injected_Input
	previous := read_injected_test_frame(&injected, {}, tables)
	south := test_injected_control(.Gamepad, "SOUTH")
	set_injected_control(&injected, south, true)
	device, seen := next_injected_device(&injected, &previous, tables)
	testing.expect(t, seen && device == .Gamepad)
	set_injected_control(&injected, south, false)
	_, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, !seen, "a release is seen")
	injected.pointer, injected.pointer_delta = {300, 200}, {300, 200}
	device, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, seen && device == .Keyboard_Mouse)
	copy(injected.text[:], "abc")
	injected.text_length = 3
	_, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, !seen, "typed text is seen")
	key := test_injected_control(.Keyboard, "W")
	set_injected_control(&injected, key, true)
	device, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, seen && device == .Keyboard_Mouse)
	set_injected_control(&injected, key, false)
	injected.sticks[.Left] = {0, 0.1}
	_, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, !seen, "a stick inside the deadzone is seen")
	injected.sticks[.Left] = {0, 1}
	device, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, seen && device == .Gamepad)
	// GUIDE, bound to nothing, turns the gamepad's glyphs on without an
	// action.
	injected.sticks[.Left] = {}
	injected.pointer, injected.pointer_delta = {310, 200}, {10, 0}
	device, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, seen && device == .Keyboard_Mouse)
	set_injected_control(&injected, test_injected_control(.Gamepad, "GUIDE"), true)
	device, seen = next_injected_device(&injected, &previous, tables)
	testing.expect(t, seen && device == .Gamepad)
	testing.expect_value(t, previous.pressed, Action_Set{})
}

// One read of the devices set up by the caller, from rest.
read_injected_alone :: proc(injected: Injected_Input, tables: Input_Bindings) -> Input_Frame {
	return read_injected_input_frame(injected, {}, tables, {})
}

@(test)
test_sticks_triggers_keys_and_buttons_reach_the_frame :: proc(t: ^testing.T) {
	tables := shipped_sdl3_tables(t)
	stick: Injected_Input
	stick.sticks[.Left] = {0, 1}
	testing.expect_value(t, read_injected_alone(stick, tables).move, [2]f32{0, 1})
	stick.sticks[.Left], stick.sticks[.Right] = {}, {0.1, 0}
	testing.expect_value(t, read_injected_alone(stick, tables).look, [2]f32{0, 0})
	trigger: Injected_Input
	trigger.triggers[.Right] = 1
	testing.expect(t, .Mine in read_injected_alone(trigger, tables).pressed)
	trigger.triggers[.Right] = 0.4
	testing.expect(t, .Mine not_in read_injected_alone(trigger, tables).pressed)
	keys: Injected_Input
	set_injected_control(&keys, test_injected_control(.Keyboard, "W"), true)
	testing.expect_value(t, read_injected_alone(keys, tables).move, [2]f32{0, 1})
	keys = {}
	set_injected_control(&keys, test_injected_control(.Keyboard, "C"), true)
	testing.expect(t, .Open_Recipes in read_injected_alone(keys, tables).pressed)
	mouse: Injected_Input
	set_injected_control(&mouse, test_injected_control(.Mouse, "LEFT"), true)
	testing.expect(t, .Mine in read_injected_alone(mouse, tables).pressed)
	pointer: Injected_Input
	pointer.pointer_delta = [2]f32{300, 200} - pointer.pointer
	pointer.pointer = {300, 200}
	moved := read_injected_test_frame(&pointer, {}, tables)
	testing.expect_value(t, moved.look_delta, [2]f32{300, 200})
	testing.expect_value(t, moved.raw.mouse.position, [2]f32{300, 200})
	still := read_injected_test_frame(&pointer, moved, tables)
	testing.expect_value(t, still.look_delta, [2]f32{0, 0})
	testing.expect_value(t, still.raw.mouse.position, [2]f32{300, 200})
}

@(test)
test_the_touch_overlay_takes_the_virtual_pointer_as_its_touch :: proc(t: ^testing.T) {
	injected := Injected_Input{pointer = {640, 360}}
	buffer: [TOUCH_POINT_CAPACITY]Touch_Point
	testing.expect_value(t, len(injected_touch_points(injected, buffer[:])), 0)
	injected.mouse_buttons[int(rl.MouseButton.LEFT)] = true
	points := injected_touch_points(injected, buffer[:])
	if testing.expect_value(t, len(points), 1) {
		testing.expect_value(t, points[0], Touch_Point{id = 0, position = {640, 360}})
	}
}
