package game

import "core:strings"
import "core:testing"
import rl "shared:raylib"
import sdl "vendor:sdl3"

// The binding tables as they were hardcoded in input_raylib.odin and
// input_sdl3.odin before work item 0025. data/bindings.sjson must produce
// exactly these.

Reference_Raylib_Button :: struct {
	button: rl.GamepadButton,
	action: Action,
}

Reference_Sdl3_Button :: struct {
	button: sdl.GamepadButton,
	action: Action,
}

Reference_Key :: struct {
	key:    rl.KeyboardKey,
	action: Action,
}

Reference_Mouse_Button :: struct {
	button: rl.MouseButton,
	action: Action,
}

@(rodata)
reference_raylib_buttons := [?]Reference_Raylib_Button {
	{.RIGHT_FACE_DOWN, .Jump},
	{.RIGHT_FACE_DOWN, .Interact},
	{.RIGHT_FACE_DOWN, .Confirm},
	{.RIGHT_FACE_RIGHT, .Back},
	// Sneak on B and Sprint on the stick click reach the raylib backend
	// since the touch overlay (0115), which presses them on Android.
	{.RIGHT_FACE_RIGHT, .Sneak},
	{.LEFT_THUMB, .Sprint},
	{.RIGHT_FACE_LEFT, .Open_Inventory},
	{.RIGHT_FACE_UP, .Rotate_Building},
	{.LEFT_FACE_UP, .Pipette},
	{.LEFT_FACE_DOWN, .Drop_Stack},
	{.LEFT_FACE_LEFT, .Hotbar_Previous},
	{.LEFT_FACE_RIGHT, .Hotbar_Next},
	{.LEFT_TRIGGER_1, .Hotbar_Previous},
	{.RIGHT_TRIGGER_1, .Hotbar_Next},
	{.RIGHT_TRIGGER_2, .Mine},
	{.LEFT_TRIGGER_2, .Place},
	{.LEFT_TRIGGER_2, .Use_Item},
	{.LEFT_TRIGGER_2, .Menu_Secondary},
	{.MIDDLE_LEFT, .Open_Map},
	{.MIDDLE_RIGHT, .Pause},
	{.RIGHT_TRIGGER_2, .Confirm},
	{.RIGHT_TRIGGER_2, .Menu_Quick_Move},
	{.LEFT_FACE_UP, .Navigate_Up},
	{.LEFT_FACE_DOWN, .Navigate_Down},
	{.LEFT_FACE_LEFT, .Navigate_Left},
	{.LEFT_FACE_RIGHT, .Navigate_Right},
	{.LEFT_TRIGGER_1, .Tab_Previous},
	{.RIGHT_TRIGGER_1, .Tab_Next},
	{.RIGHT_FACE_UP, .Info_Panel},
	{.RIGHT_FACE_LEFT, .Context_Action},
	{.RIGHT_THUMB, .Menu_Drop},
}

@(rodata)
reference_keys := [?]Reference_Key {
	{.SPACE, .Jump},
	{.R, .Rotate_Building},
	{.Q, .Pipette},
	{.TAB, .Hotbar_Radial},
	{.E, .Open_Inventory},
	{.C, .Open_Recipes},
	{.J, .Open_Journal},
	{.P, .Open_Power_Overview},
	{.N, .Open_Statistics},
	{.T, .Open_Technologies},
	{.M, .Open_Map},
	{.ESCAPE, .Pause},
	{.ENTER, .Confirm},
	{.BACKSPACE, .Back},
	{.LEFT_SHIFT, .Sneak},
	{.LEFT_SHIFT, .Menu_Secondary},
	{.F, .Interact},
	{.LEFT_CONTROL, .Sprint_Hold},
	{.LEFT_BRACKET, .Hotbar_Previous},
	{.RIGHT_BRACKET, .Hotbar_Next},
	{.ONE, .Hotbar_Slot_1},
	{.TWO, .Hotbar_Slot_2},
	{.THREE, .Hotbar_Slot_3},
	{.FOUR, .Hotbar_Slot_4},
	{.FIVE, .Hotbar_Slot_5},
	{.SIX, .Hotbar_Slot_6},
	{.SEVEN, .Hotbar_Slot_7},
	{.EIGHT, .Hotbar_Slot_8},
	{.X, .Drop_Stack},
	{.V, .Toggle_Camera_Mode},
	{.O, .Toggle_Bottleneck_Overlay},
	{.F3, .Toggle_Diagnostics},
	{.F4, .Toggle_World_Overlay},
	{.F5, .Debug_Remove_Block},
	{.F7, .Debug_Drop_Item},
	{.F6, .Toggle_Fly_Mode},
	{.F9, .Toggle_No_Clip},
	{.F8, .Reload_Data},
	{.UP, .Navigate_Up},
	{.DOWN, .Navigate_Down},
	{.LEFT, .Navigate_Left},
	{.RIGHT, .Navigate_Right},
	{.Q, .Tab_Previous},
	{.E, .Tab_Next},
	{.R, .Info_Panel},
	{.F, .Context_Action},
	{.Q, .Menu_Quick_Move},
	{.LEFT_CONTROL, .Menu_Quick_Move_Modifier},
	{.X, .Menu_Drop},
}

@(rodata)
reference_mouse_buttons := [?]Reference_Mouse_Button{{.LEFT, .Mine}, {.RIGHT, .Place}, {.RIGHT, .Use_Item}, {.MIDDLE, .Pipette}}

@(rodata)
reference_sdl3_buttons := [?]Reference_Sdl3_Button {
	{.SOUTH, .Jump},
	{.SOUTH, .Interact},
	{.SOUTH, .Confirm},
	{.EAST, .Sneak},
	{.EAST, .Back},
	{.WEST, .Open_Inventory},
	{.NORTH, .Rotate_Building},
	{.DPAD_UP, .Pipette},
	{.DPAD_DOWN, .Drop_Stack},
	{.DPAD_LEFT, .Hotbar_Previous},
	{.DPAD_RIGHT, .Hotbar_Next},
	{.LEFT_SHOULDER, .Hotbar_Previous},
	{.RIGHT_SHOULDER, .Hotbar_Next},
	{.LEFT_STICK, .Sprint},
	{.BACK, .Open_Map},
	{.START, .Pause},
	{.LEFT_PADDLE1, .Jump},
	{.LEFT_PADDLE1, .Interact},
	{.LEFT_PADDLE1, .Confirm},
	{.RIGHT_PADDLE1, .Sneak},
	{.RIGHT_PADDLE1, .Back},
	{.LEFT_PADDLE2, .Rotate_Building},
	{.RIGHT_PADDLE2, .Pipette},
	{.MISC2, .Confirm},
	{.MISC2, .Interact},
	{.DPAD_UP, .Navigate_Up},
	{.DPAD_DOWN, .Navigate_Down},
	{.DPAD_LEFT, .Navigate_Left},
	{.DPAD_RIGHT, .Navigate_Right},
	{.LEFT_SHOULDER, .Tab_Previous},
	{.RIGHT_SHOULDER, .Tab_Next},
	{.NORTH, .Info_Panel},
	{.WEST, .Context_Action},
	{.LEFT_PADDLE2, .Info_Panel},
	{.RIGHT_PADDLE2, .Navigate_Up},
	{.RIGHT_STICK, .Menu_Drop},
}

// Keyboard, mouse and wheel were shared by both backends.
reference_keyboard_and_mouse :: proc() -> Input_Bindings {
	tables: Input_Bindings
	for binding in reference_keys {
		tables.keys[int(binding.key)] += {binding.action}
	}
	for binding in reference_mouse_buttons {
		tables.mouse_buttons[int(binding.button)] += {binding.action}
	}
	tables.mouse_wheel = {.Up = {.Hotbar_Previous}, .Down = {.Hotbar_Next}}
	return tables
}

reference_raylib_bindings :: proc() -> Input_Bindings {
	tables := reference_keyboard_and_mouse()
	for binding in reference_raylib_buttons {
		tables.gamepad_buttons[int(binding.button)] += {binding.action}
	}
	return tables
}

// The triggers and the left pad were read by sdl3_trigger_actions and
// sdl3_touchpad_actions.
reference_sdl3_bindings :: proc() -> Input_Bindings {
	tables := reference_keyboard_and_mouse()
	for binding in reference_sdl3_buttons {
		tables.gamepad_buttons[int(binding.button)] += {binding.action}
	}
	tables.gamepad_triggers = {.Right = {.Mine, .Confirm, .Menu_Quick_Move}, .Left = {.Place, .Use_Item, .Menu_Secondary}}
	tables.trackpads[LEFT_TOUCHPAD_INDEX] = {.Hotbar_Radial}
	return tables
}

shipped_default_bindings :: proc(t: ^testing.T) -> []Binding {
	bindings, problem := parse_bindings_file(#load("../data/bindings.sjson"), "data/bindings.sjson", context.temp_allocator)
	testing.expect_value(t, problem, "")
	return bindings
}

expect_same_tables :: proc(t: ^testing.T, built, expected: Input_Bindings) {
	for index in 0 ..< RAW_GAMEPAD_BUTTON_CAPACITY {
		testing.expectf(t, built.gamepad_buttons[index] == expected.gamepad_buttons[index], "gamepad button %d: %v, expected %v", index, built.gamepad_buttons[index], expected.gamepad_buttons[index])
	}
	for index in 0 ..< KEYBOARD_KEY_CAPACITY {
		testing.expectf(t, built.keys[index] == expected.keys[index], "key %v: %v, expected %v", rl.KeyboardKey(index), built.keys[index], expected.keys[index])
	}
	testing.expect_value(t, built.gamepad_triggers, expected.gamepad_triggers)
	testing.expect_value(t, built.mouse_buttons, expected.mouse_buttons)
	testing.expect_value(t, built.mouse_wheel, expected.mouse_wheel)
	testing.expect_value(t, built.trackpads, expected.trackpads)
}

@(test)
test_default_bindings_equal_the_former_tables :: proc(t: ^testing.T) {
	bindings := shipped_default_bindings(t)
	sdl3_tables, sdl3_unsupported := build_input_bindings(bindings, .Sdl3, context.temp_allocator)
	expect_same_tables(t, sdl3_tables, reference_sdl3_bindings())
	testing.expect_value(t, len(sdl3_unsupported), 0)
	raylib_tables, raylib_unsupported := build_input_bindings(bindings, .Raylib, context.temp_allocator)
	expect_same_tables(t, raylib_tables, reference_raylib_bindings())
	// Paddles (9), the right pad click (2) and the left pad.
	testing.expect_value(t, len(raylib_unsupported), 12)
	for binding in raylib_unsupported {
		testing.expect(t, binding.device == .Trackpad || strings.contains(binding.control, "PADDLE") || binding.control == "MISC2")
	}
}

@(test)
test_binding_override_replaces_an_action :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defaults := shipped_default_bindings(t)
	provenance := make(Configuration_Provenance)
	provenance["bindings"] = "/config/50-bindings.sjson"
	entries := [?]Binding_Entry {
		{action = "Jump", device = "keyboard", control = "J", binding_context = "world"},
		{action = "Jump", device = "gamepad", control = "EAST", binding_context = "world", backend = "sdl3"},
	}
	overrides, problem := resolve_bindings(entries[:], provenance)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, overrides[0].source, "/config/50-bindings.sjson")
	effective := effective_bindings(defaults, overrides)
	jump_count := 0
	for binding in effective {
		if binding.action == .Jump {
			jump_count += 1
		}
	}
	testing.expect_value(t, jump_count, 2)
	testing.expect_value(t, len(effective), len(defaults) - 3 + 2)
	tables, _ := build_input_bindings(effective, .Sdl3)
	testing.expect(t, .Jump in tables.keys[int(rl.KeyboardKey.J)])
	testing.expect(t, .Open_Journal in tables.keys[int(rl.KeyboardKey.J)])
	testing.expect(t, .Jump not_in tables.keys[int(rl.KeyboardKey.SPACE)])
	testing.expect(t, .Jump in tables.gamepad_buttons[int(sdl.GamepadButton.EAST)])
	testing.expect(t, .Jump not_in tables.gamepad_buttons[int(sdl.GamepadButton.SOUTH)])
	testing.expect(t, .Interact in tables.gamepad_buttons[int(sdl.GamepadButton.SOUTH)])
	raylib_tables, _ := build_input_bindings(effective, .Raylib)
	testing.expect(t, .Jump not_in raylib_tables.gamepad_buttons[int(rl.GamepadButton.RIGHT_FACE_RIGHT)])
}

@(test)
test_binding_errors_name_the_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	provenance := make(Configuration_Provenance)
	provenance["bindings"] = "/config/config.sjson"
	cases := [?]struct {
		entry:   Binding_Entry,
		mention: string,
	} {
		{{action = "Jmp", device = "keyboard", control = "J", binding_context = "world"}, `unknown action "Jmp"`},
		{{action = "Jump", device = "joystick", control = "J", binding_context = "world"}, `unknown device "joystick"`},
		{{action = "Jump", device = "keyboard", control = "SOUTH", binding_context = "world"}, `"SOUTH" is not a keyboard control`},
		{{action = "Jump", device = "gamepad", control = "LEFTX", binding_context = "world"}, `"LEFTX" is not a gamepad control`},
		{{action = "Jump", device = "trackpad", control = "MIDDLE", binding_context = "world"}, `"MIDDLE" is not a trackpad control`},
		{{action = "Jump", device = "mouse", control = "LEFT", binding_context = "sky"}, `unknown context "sky"`},
		{{action = "Jump", device = "mouse", control = "LEFT", binding_context = "world", backend = "glfw"}, `unknown backend "glfw"`},
	}
	for test_case in cases {
		entries := [?]Binding_Entry{test_case.entry}
		_, problem := resolve_bindings(entries[:], provenance)
		expect_problem_mentions(t, problem, "/config/config.sjson", "bindings[0]", test_case.mention)
	}
	_, problem := parse_bindings_file(transmute([]byte)string(`bindings = [{action = "Jump" key = "J"}]`), "data/bindings.sjson")
	expect_problem_mentions(t, problem, "data/bindings.sjson", "unknown key bindings[0].key")
}

@(test)
test_binding_rows :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	rows := binding_rows(shipped_default_bindings(t))
	testing.expect_value(t, rows[0], "Jump: gamepad SOUTH, gamepad LEFT_PADDLE1, keyboard SPACE")
	found_sprint, found_sprint_hold := false, false
	for row in rows {
		if strings.has_prefix(row, "Sprint:") {
			found_sprint = true
			testing.expect_value(t, row, "Sprint: gamepad LEFT_STICK")
		}
		if strings.has_prefix(row, "Sprint Hold:") {
			found_sprint_hold = true
			testing.expect_value(t, row, "Sprint Hold: keyboard LEFT_CONTROL")
		}
	}
	testing.expect(t, found_sprint)
	testing.expect(t, found_sprint_hold)
	testing.expect_value(t, unsupported_bindings_report({}, .Raylib), "input: the raylib backend cannot express 0 bindings:")
}
