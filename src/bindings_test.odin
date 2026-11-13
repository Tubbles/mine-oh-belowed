package game

import "core:reflect"
import "core:strings"
import "core:testing"
import rl "shared:raylib"
import sdl "vendor:sdl3"

// The reference binding tables (work item 0025). data/bindings.sjson must
// produce exactly these.

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
	{.RIGHT_FACE_DOWN, .Confirm},
	{.RIGHT_FACE_RIGHT, .Back},
	// Sneak on B and Sprint on the stick click reach the raylib backend:
	// the touch overlay (0115) presses them on Android.
	{.RIGHT_FACE_RIGHT, .Sneak},
	{.LEFT_THUMB, .Sprint},
	{.RIGHT_THUMB, .Toggle_Cheat_Movement},
	{.RIGHT_FACE_LEFT, .Open_Inventory},
	{.RIGHT_FACE_LEFT, .Interact},
	{.RIGHT_FACE_UP, .Rotate_Building},
	{.LEFT_FACE_UP, .Pipette},
	{.LEFT_FACE_DOWN, .Drop_Stack},
	// The tech demo's D-pad (0297): the torchlight and the clock step.
	{.LEFT_FACE_UP, .Toggle_Torchlight},
	{.LEFT_FACE_DOWN, .Step_Time_Of_Day},
	{.LEFT_FACE_LEFT, .Hotbar_Previous},
	{.LEFT_FACE_RIGHT, .Hotbar_Next},
	{.LEFT_TRIGGER_1, .Hotbar_Previous},
	{.RIGHT_TRIGGER_1, .Hotbar_Next},
	{.LEFT_FACE_UP, .Placement_Nudge_Away},
	{.LEFT_FACE_DOWN, .Placement_Nudge_Towards},
	{.LEFT_FACE_LEFT, .Placement_Nudge_Left},
	{.LEFT_FACE_RIGHT, .Placement_Nudge_Right},
	{.RIGHT_TRIGGER_2, .Mine},
	{.LEFT_TRIGGER_2, .Place},
	{.LEFT_TRIGGER_2, .Use_Item},
	{.MIDDLE_LEFT, .Open_Map},
	{.MIDDLE_RIGHT, .Pause},
	{.LEFT_FACE_UP, .Navigate_Up},
	{.LEFT_FACE_DOWN, .Navigate_Down},
	{.LEFT_FACE_LEFT, .Navigate_Left},
	{.LEFT_FACE_RIGHT, .Navigate_Right},
	// The window step and the confirm modifiers (0276).
	{.LEFT_TRIGGER_2, .Window_Previous},
	{.RIGHT_TRIGGER_2, .Window_Next},
	{.LEFT_TRIGGER_1, .Modifier_Most},
	{.RIGHT_TRIGGER_1, .Modifier_Five},
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
	{.LEFT_CONTROL, .Sneak},
	{.LEFT_SHIFT, .Modifier_Most},
	{.F, .Interact},
	{.LEFT_SHIFT, .Sprint_Hold},
	{.LEFT_BRACKET, .Hotbar_Previous},
	{.RIGHT_BRACKET, .Hotbar_Next},
	{.UP, .Placement_Nudge_Away},
	{.DOWN, .Placement_Nudge_Towards},
	{.LEFT, .Placement_Nudge_Left},
	{.RIGHT, .Placement_Nudge_Right},
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
	{.Q, .Window_Previous},
	{.E, .Window_Next},
	{.LEFT_BRACKET, .Tab_Previous},
	{.RIGHT_BRACKET, .Tab_Next},
	{.R, .Info_Panel},
	{.F, .Context_Action},
	{.LEFT_CONTROL, .Modifier_Five},
	{.X, .Menu_Drop},
}

@(rodata)
reference_mouse_buttons := [?]Reference_Mouse_Button{{.LEFT, .Mine}, {.RIGHT, .Place}, {.RIGHT, .Use_Item}, {.MIDDLE, .Pipette}}

@(rodata)
reference_sdl3_buttons := [?]Reference_Sdl3_Button {
	{.SOUTH, .Jump},
	{.SOUTH, .Confirm},
	{.EAST, .Sneak},
	{.EAST, .Back},
	{.WEST, .Open_Inventory},
	{.WEST, .Interact},
	{.NORTH, .Rotate_Building},
	{.DPAD_UP, .Pipette},
	{.DPAD_DOWN, .Drop_Stack},
	{.DPAD_UP, .Toggle_Torchlight},
	{.DPAD_DOWN, .Step_Time_Of_Day},
	{.DPAD_LEFT, .Hotbar_Previous},
	{.DPAD_RIGHT, .Hotbar_Next},
	{.LEFT_SHOULDER, .Hotbar_Previous},
	{.RIGHT_SHOULDER, .Hotbar_Next},
	{.DPAD_UP, .Placement_Nudge_Away},
	{.DPAD_DOWN, .Placement_Nudge_Towards},
	{.DPAD_LEFT, .Placement_Nudge_Left},
	{.DPAD_RIGHT, .Placement_Nudge_Right},
	{.LEFT_STICK, .Sprint},
	{.RIGHT_STICK, .Toggle_Cheat_Movement},
	{.BACK, .Open_Map},
	{.START, .Pause},
	{.LEFT_PADDLE1, .Jump},
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
	{.LEFT_SHOULDER, .Modifier_Most},
	{.RIGHT_SHOULDER, .Modifier_Five},
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
	tables.gamepad_triggers = {.Right = {.Mine, .Window_Next}, .Left = {.Place, .Use_Item, .Window_Previous}}
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
	// Paddles (8), the right pad click (2) and the left pad.
	testing.expect_value(t, len(raylib_unsupported), 11)
	for binding in raylib_unsupported {
		testing.expect(t, binding.device == .Trackpad || strings.contains(binding.control, "PADDLE") || binding.control == "MISC2")
	}
}

// Work item 0233: A jumps and confirms, X carries Open_Inventory and
// Interact in the world and the context action in menus, the right pad's
// click Interact and Confirm; Interact's glyph is X.
@(test)
test_the_shipped_bindings_put_interact_on_x_and_leave_a_to_jump :: proc(t: ^testing.T) {
	bindings := shipped_default_bindings(t)
	sdl3_tables, _ := build_input_bindings(bindings, .Sdl3, context.temp_allocator)
	testing.expect_value(t, sdl3_tables.gamepad_buttons[int(sdl.GamepadButton.SOUTH)], Action_Set{.Jump, .Confirm})
	testing.expect_value(t, sdl3_tables.gamepad_buttons[int(sdl.GamepadButton.LEFT_PADDLE1)], Action_Set{.Jump, .Confirm})
	testing.expect_value(t, sdl3_tables.gamepad_buttons[int(sdl.GamepadButton.WEST)], Action_Set{.Open_Inventory, .Interact, .Context_Action})
	testing.expect_value(t, sdl3_tables.gamepad_buttons[int(sdl.GamepadButton.MISC2)], Action_Set{.Interact, .Confirm})
	raylib_tables, _ := build_input_bindings(bindings, .Raylib, context.temp_allocator)
	testing.expect_value(t, raylib_tables.gamepad_buttons[int(rl.GamepadButton.RIGHT_FACE_DOWN)], Action_Set{.Jump, .Confirm})
	testing.expect_value(t, raylib_tables.gamepad_buttons[int(rl.GamepadButton.RIGHT_FACE_LEFT)], Action_Set{.Open_Inventory, .Interact, .Context_Action})
	for backend in ([]Input_Backend{.Sdl3, .Raylib}) {
		binding, found := first_binding_on_device(bindings, .Interact, .Gamepad, backend)
		testing.expect(t, found)
		testing.expect_value(t, binding.control, "WEST")
	}
}

// A gamepad press of one button through the shipped bindings' SDL3
// tables, pressed and just pressed (0233).
shipped_gamepad_press :: proc(t: ^testing.T, button: sdl.GamepadButton) -> Input_Frame {
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Sdl3, context.temp_allocator)
	gamepad := Raw_Gamepad{connected = true, button_count = RAW_GAMEPAD_BUTTON_CAPACITY}
	gamepad.button_down[int(button)] = true
	actions := gamepad_button_actions(gamepad, tables)
	return Input_Frame{pressed = actions, just_pressed = actions}
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
	testing.expect(t, .Confirm in tables.gamepad_buttons[int(sdl.GamepadButton.SOUTH)])
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

// Work item 0276: a configuration of an older build that names a removed
// action loads: the entry is skipped with a log line, and a typo still
// fails.
@(test)
test_a_retired_action_in_a_configuration_is_ignored :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	provenance := make(Configuration_Provenance)
	provenance["bindings"] = "/config/config.sjson"
	entries := [?]Binding_Entry {
		{action = "Menu_Secondary", device = "gamepad", control = "LEFT_TRIGGER", binding_context = "menu"},
		{action = "Menu_Quick_Move", device = "gamepad", control = "RIGHT_TRIGGER", binding_context = "menu"},
		{action = "Menu_Quick_Move_Modifier", device = "keyboard", control = "LEFT_CONTROL", binding_context = "menu"},
		{action = "Jump", device = "keyboard", control = "J", binding_context = "world"},
	}
	bindings, problem := resolve_bindings(entries[:], provenance)
	testing.expect_value(t, problem, "")
	if testing.expect_value(t, len(bindings), 1) {
		testing.expect_value(t, bindings[0].action, Action.Jump)
	}
	expected := [?]Retired_Action{{"Menu_Secondary", "Modifier_Most"}, {"Menu_Quick_Move", "Modifier_Five"}, {"Menu_Quick_Move_Modifier", "Modifier_Five"}}
	for pair in expected {
		replacement, retired := retired_action_replacement(pair.name)
		testing.expectf(t, retired && replacement == pair.replacement, "%s: %q %v", pair.name, replacement, retired)
		_, is_action := reflect.enum_from_name(Action, replacement)
		testing.expectf(t, is_action, "%s is no action", replacement)
	}
	_, jump_retired := retired_action_replacement("Jump")
	testing.expect(t, !jump_retired)
	typo := [?]Binding_Entry{{action = "Menu_Secondar", device = "gamepad", control = "LEFT_TRIGGER", binding_context = "menu"}}
	_, typo_problem := resolve_bindings(typo[:], provenance)
	expect_problem_mentions(t, typo_problem, "/config/config.sjson", "bindings[0]", `unknown action "Menu_Secondar"`)
}

// The actions a device's control carries in menus: those of the menu and
// both contexts.
menu_actions_of :: proc(bindings: []Binding, device: Binding_Device, control: string) -> Action_Set {
	actions: Action_Set
	for binding in bindings {
		if binding.binding_context != .World && binding.device == device && binding.control == control {
			actions += {binding.action}
		}
	}
	return actions
}

// Work item 0276: no control carries two meanings in menus, but X (the
// gamepad's Open_Inventory and Context_Action, handle_screen_keys) and
// the keyboard's E (Open_Inventory and Window_Next, handle_screen_keys),
// whose screens decide between the two. No control of the window step
// or a confirm modifier is Confirm too.
@(test)
test_no_menu_control_carries_two_menu_meanings :: proc(t: ^testing.T) {
	bindings := shipped_default_bindings(t)
	without_confirm := Action_Set{.Window_Previous, .Window_Next, .Modifier_Five, .Modifier_Most}
	for binding in bindings {
		actions := menu_actions_of(bindings, binding.device, binding.control)
		switch {
		case binding.device == .Gamepad && binding.control == "WEST":
			testing.expect_value(t, actions, Action_Set{.Open_Inventory, .Context_Action})
		case binding.device == .Keyboard && binding.control == "E":
			testing.expect_value(t, actions, Action_Set{.Open_Inventory, .Window_Next})
		case:
			testing.expectf(t, card(actions) <= 1, "%v %s carries %v in menus", binding.device, binding.control, actions)
		}
		if binding.action in without_confirm {
			testing.expectf(t, .Confirm not_in actions, "%v %s carries %v and Confirm", binding.device, binding.control, binding.action)
		}
	}
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
			testing.expect_value(t, row, "Sprint Hold: keyboard LEFT_SHIFT")
		}
	}
	testing.expect(t, found_sprint)
	testing.expect(t, found_sprint_hold)
	testing.expect_value(t, unsupported_bindings_report({}, .Raylib), "input: the raylib backend cannot express 0 bindings:")
}

// Work item 0297: the torchlight rides on Pipette's D-pad up and the clock
// step on Drop_Stack's D-pad down, both in the world, and the two keep
// their lines.
@(test)
test_the_shipped_bindings_put_the_torchlight_and_the_clock_on_the_d_pad :: proc(t: ^testing.T) {
	bindings := shipped_default_bindings(t)
	lines := [?]struct {
		action:  Action,
		control: string,
	}{{.Toggle_Torchlight, "DPAD_UP"}, {.Pipette, "DPAD_UP"}, {.Step_Time_Of_Day, "DPAD_DOWN"}, {.Drop_Stack, "DPAD_DOWN"}}
	for line in lines {
		found := false
		for binding in bindings {
			found ||= binding.action == line.action && binding.device == .Gamepad && binding.control == line.control && binding.binding_context == .World
		}
		testing.expectf(t, found, "%v on the gamepad's %s in the world", line.action, line.control)
	}
	tables, _ := build_input_bindings(bindings, .Sdl3, context.temp_allocator)
	testing.expect(t, .Toggle_Torchlight in tables.gamepad_buttons[int(sdl.GamepadButton.DPAD_UP)])
	testing.expect(t, .Step_Time_Of_Day in tables.gamepad_buttons[int(sdl.GamepadButton.DPAD_DOWN)])
}
