package game

import "core:fmt"
import "core:strings"
import "core:testing"
import rl "shared:raylib"
import sdl "vendor:sdl3"

// The command socket's input commands (work item 0341): resolved, timed
// and refused as doc/commands.md (Input) says, driving the screens of the
// UI audit and the world through the input record with injected input
// alone. Every test runs in memory: no socket, no screenshot.

// The loop's input state under --input=none with the shipped bindings
// and their SDL3 tables.
set_injected_test_devices :: proc(t: ^testing.T, state: ^Frame_State) {
	turn_input_devices_off(state)
	state.interaction.input_backend = .Sdl3
	state.interaction.bindings = shipped_default_bindings(t)
	state.interaction.input_bindings, _ = build_input_bindings(state.interaction.bindings, .Sdl3, context.temp_allocator)
}

// A frame state without a session, for the screens and the devices alone.
make_injected_screen_state :: proc(t: ^testing.T) -> ^Frame_State {
	state := new(Frame_State)
	set_injected_test_devices(t, state)
	return state
}

destroy_injected_screen_state :: proc(state: ^Frame_State) {
	delete(state.developer.command_control.input_answer)
	free(state)
}

// The viewport test frame (the debug terrain, offline) under
// --input=none.
make_injected_world_frame :: proc(t: ^testing.T) -> ^Frame_State {
	state := make_viewport_test_frame()
	set_injected_test_devices(t, state)
	return state
}

destroy_injected_world_frame :: proc(state: ^Frame_State) {
	delete(state.developer.command_control.input_answer)
	destroy_viewport_test_frame(state)
}

// The loop's command context over the frame state's devices and the UI,
// at 1920 by 1080.
injected_command_context :: proc(state: ^Frame_State, ui: ^Ui_State) -> Command_Context {
	command_context := Command_Context {
		control = &state.developer.command_control,
		input   = {&state.interaction.injected, ui, state.interaction.bindings, .Sdl3, state.interaction.input_devices_off, {1920, 1080}},
	}
	if state.session != nil {
		command_context.simulation = &state.session.simulation
		command_context.player = session_local_player_index(state.session)
		command_context.content = frame_simulation_content(state)
	}
	return command_context
}

// The first viewport's read and the world after it, as update_frame runs
// them.
run_injected_test_frame :: proc(state: ^Frame_State) {
	viewport := &state.viewports[0]
	viewport.interaction.previous_input = viewport.interaction.input
	viewport.interaction.input = read_input_frame(state, 0, state.frame_seconds)
	update_frame_world(state)
}

// A read of the devices and, with a UI audit, a frame of the screens
// from it (the first viewport's input holds the last read).
run_injected_screen_frame :: proc(state: ^Frame_State, audit: ^Ui_Audit, ui: ^Ui_State) {
	viewport := &state.viewports[0]
	viewport.interaction.previous_input = viewport.interaction.input
	viewport.interaction.input = read_injected_input_frame(state.interaction.injected, viewport.interaction.previous_input.pressed, state.interaction.input_bindings, {})
	advance_injected_input(&state.interaction.injected)
	if audit != nil {
		input: Ui_Input
		input, viewport.interaction.tab_flick_armed = make_ui_input(viewport.interaction.previous_input, viewport.interaction.input, viewport.interaction.tab_flick_armed)
		screen_test_frame(audit, ui, input)
	}
}

// Runs the line as the loop does. An input command's answer waits: the
// frames run (the world's with a session, else the screens') until the
// devices settled, at most 64, and the answer is taken as the loop's
// answer_input_command takes it. deferred: the answer waited.
run_injected_line :: proc(state: ^Frame_State, line: string, audit: ^Ui_Audit = nil, ui: ^Ui_State = nil) -> (answer: Command_Response, deferred: bool, reads: int) {
	control := &state.developer.command_control
	answer, _ = execute_command_line(injected_command_context(state, ui != nil ? ui : primary_ui(state)), line)
	if !answer.deferred || !control.input_waiting {
		return answer, false, 0
	}
	for !injected_input_settled(state.interaction.injected) && reads < 64 {
		if state.session != nil {
			run_injected_test_frame(state)
		} else {
			run_injected_screen_frame(state, audit, ui)
		}
		reads += 1
	}
	answer = command_ok("%s", control.input_answer)
	delete(control.input_answer)
	control.input_waiting, control.input_answer = false, ""
	return answer, true, reads
}

expect_injected_answer :: proc(t: ^testing.T, state: ^Frame_State, line, wanted: string, audit: ^Ui_Audit = nil, ui: ^Ui_State = nil, location := #caller_location) -> (reads: int) {
	answer: Command_Response
	deferred: bool
	answer, deferred, reads = run_injected_line(state, line, audit, ui)
	testing.expectf(t, answer.ok && deferred, "%q: %v", line, answer, loc = location)
	testing.expect_value(t, answer.text, wanted, loc = location)
	return reads
}

@(test)
test_an_action_presses_its_first_gamepad_control_else_its_key :: proc(t: ^testing.T) {
	bindings := shipped_default_bindings(t)
	control, binding, found := resolve_action_control(bindings, .Confirm, .Sdl3)
	testing.expect(t, found)
	testing.expect_value(t, control, Injected_Control{kind = .Gamepad_Button, code = i32(sdl.GamepadButton.SOUTH)})
	testing.expect_value(t, binding_text(binding), "gamepad SOUTH")
	control, _, found = resolve_action_control(bindings, .Mine, .Sdl3)
	testing.expect(t, found)
	testing.expect_value(t, control, Injected_Control{kind = .Gamepad_Trigger, code = i32(Gamepad_Trigger.Right)})
	control, binding, found = resolve_action_control(bindings, .Open_Recipes, .Sdl3)
	testing.expect(t, found)
	testing.expect_value(t, control, Injected_Control{kind = .Key, code = i32(rl.KeyboardKey.C)})
	testing.expect_value(t, binding_text(binding), "keyboard C")
	_, _, found = resolve_action_control(bindings, .Open_Aimed, .Sdl3)
	testing.expect(t, !found)
	overrides := []Binding{{action = .Confirm, device = .Keyboard, control = "ENTER", binding_context = .Menu, backends = {.Raylib, .Sdl3}}}
	control, _, found = resolve_action_control(effective_bindings(bindings, overrides, context.temp_allocator), .Confirm, .Sdl3)
	testing.expect(t, found)
	testing.expect_value(t, control, Injected_Control{kind = .Key, code = i32(rl.KeyboardKey.ENTER)})
}

@(test)
test_input_commands_answer_once_a_frame_saw_their_last_change :: proc(t: ^testing.T) {
	state := make_injected_screen_state(t)
	defer destroy_injected_screen_state(state)
	testing.expect_value(t, expect_injected_answer(t, state, "press Confirm", "pressed gamepad SOUTH (Confirm) for 1 frame"), 3)
	testing.expect_value(t, expect_injected_answer(t, state, "press Confirm 2", "pressed gamepad SOUTH (Confirm) for 2 frames"), 4)
	testing.expect_value(t, expect_injected_answer(t, state, "hold Jump", "holding gamepad SOUTH (Jump)"), 2)
	testing.expect_value(t, expect_injected_answer(t, state, "release Jump", "released gamepad SOUTH (Jump)"), 2)
	testing.expect_value(t, expect_injected_answer(t, state, "stick left 0.5 -1", "stick left at 0.500 -1"), 2)
	testing.expect_value(t, expect_injected_answer(t, state, "trigger right 1", "trigger right at 1"), 2)
	testing.expect_value(t, expect_injected_answer(t, state, "pointer 960 540", "pointer at 960 540"), 2)
	testing.expect_value(t, expect_injected_answer(t, state, `type "Deep mine"`, "typed 9 characters"), 2)
	testing.expect_value(t, expect_injected_answer(t, state, "release all", "released all"), 2)
	injected := state.interaction.injected
	testing.expect_value(t, injected.sticks[.Left], [2]f32{0, 0})
	testing.expect_value(t, injected.triggers[.Right], 0)
	testing.expect_value(t, injected.pointer, [2]f32{960, 540})
}

expect_injected_refusal :: proc(t: ^testing.T, state: ^Frame_State, line, wanted: string, location := #caller_location) {
	before := state.interaction.injected
	answer, deferred, _ := run_injected_line(state, line)
	testing.expectf(t, !answer.ok && !deferred, "%q: %v", line, answer, loc = location)
	testing.expect_value(t, answer.text, wanted, loc = location)
	testing.expectf(t, !state.developer.command_control.input_waiting, "%q waits", line, loc = location)
	testing.expectf(t, state.interaction.injected == before, "%q changed the devices", line, loc = location)
}

@(test)
test_input_commands_refuse_what_the_virtual_devices_cannot_do :: proc(t: ^testing.T) {
	state := make_injected_screen_state(t)
	defer destroy_injected_screen_state(state)
	state.interaction.input_devices_off = false
	for line in ([?]string{"press Confirm", "hold Jump", "release all", "stick left 0 0", "trigger left 0", "pointer 0 0", "type a"}) {
		expect_injected_refusal(t, state, line, INPUT_NEEDS_NONE_PROBLEM)
	}
	state.interaction.input_devices_off = true
	expect_injected_refusal(t, state, "press", "usage: " + PRESS_USAGE)
	expect_injected_refusal(t, state, "hold gamepad", "usage: " + HOLD_USAGE)
	expect_injected_refusal(t, state, "press Confirm 0", "the frames must be a number from 1 to 600")
	expect_injected_refusal(t, state, "press Confirm 601", "the frames must be a number from 1 to 600")
	expect_injected_refusal(t, state, "stick left 1.001 0", "x must be a number from -1 to 1 with up to three decimals")
	expect_injected_refusal(t, state, "stick up 0 0", "usage: " + STICK_USAGE)
	expect_injected_refusal(t, state, "trigger right -0.1", "the trigger must be a number from 0 to 1 with up to three decimals")
	expect_injected_refusal(t, state, "pointer 1920 0", "x must be a number from 0 to 1919")
	expect_injected_refusal(t, state, "pointer 0 -1", "y must be a number from 0 to 1079")
	text_problem := "the text holds 1 to 512 printable ASCII characters"
	expect_injected_refusal(t, state, `type ""`, text_problem)
	expect_injected_refusal(t, state, fmt.tprintf("type %s", strings.repeat("a", 513, context.temp_allocator)), text_problem)
	expect_injected_refusal(t, state, `type "café"`, text_problem)
	expect_injected_refusal(t, state, "type a b", "usage: " + TYPE_USAGE)
	expect_injected_refusal(t, state, "release Confirm", "gamepad SOUTH (Confirm) is not held")
	expect_injected_refusal(t, state, "release all extra", "usage: " + RELEASE_USAGE)
	expect_injected_refusal(t, state, "press Jumpp", `unknown action or device "Jumpp"`)
	expect_injected_refusal(t, state, "press gamepad MISC9", "gamepad MISC9 is no control of the virtual devices")
	expect_injected_refusal(t, state, "press mouse WHEEL_UP", "mouse WHEEL_UP is no control of the virtual devices")
	expect_injected_refusal(t, state, "press trackpad LEFT", "trackpad LEFT is no control of the virtual devices")
	expect_injected_refusal(t, state, "press Open_Aimed", "Open_Aimed is bound to no gamepad control, key or mouse button")
	set_injected_control(&state.interaction.injected, test_injected_control(.Gamepad, "SOUTH"), true)
	expect_injected_refusal(t, state, "press Confirm", "gamepad SOUTH (Confirm) is held; release it first")
	for code in i32(rl.KeyboardKey.A) ..= i32(rl.KeyboardKey.P) {
		set_injected_control(&state.interaction.injected, Injected_Control{kind = .Key, code = code}, true)
	}
	testing.expect_value(t, state.interaction.injected.key_count, RAW_KEYS_DOWN_CAPACITY)
	expect_injected_refusal(t, state, "hold keyboard Q", "16 keys are held already")
	expect_injected_refusal(t, state, "press keyboard Q", "16 keys are held already")
}

@(test)
test_query_ui_names_the_screens_focus_pointer_and_device :: proc(t: ^testing.T) {
	ui: Ui_State
	defer destroy_ui_state(&ui)
	push_screen(&ui.screens, .Pause)
	push_screen(&ui.screens, .Settings)
	ui.pixels_per_unit = 2
	append(&ui.widgets, Ui_Widget{id = 9, rectangle = {10, 20, 100, 40}})
	ui.focus, ui.active_device = 9, .Gamepad
	ui.pointer, ui.pointer_source = {100, 50}, .Mouse
	response := query_ui(Command_Input_Context{ui = &ui, backend = .Sdl3, devices_off = true}, nil)
	testing.expect(t, response.ok)
	testing.expect_value(t, response.text, "ui\nscreens pause settings\ntop settings\ndevice gamepad\npointer 200.0 100.0 mouse\nfocus 20 40 200 80\ntext_field closed\nbackend none")
	// Through the command line, without a world, on a device backend.
	empty: Ui_State
	control: Command_Control
	response, _ = execute_command_line(Command_Context{control = &control, input = {ui = &empty, backend = .Raylib}}, "query ui")
	testing.expect(t, response.ok)
	testing.expect_value(t, response.text, "ui\nscreens none\ntop none\ndevice keyboard_mouse\npointer 0.0 0.0 none\nfocus none\ntext_field closed\nbackend raylib")
	response, _ = execute_command_line(Command_Context{control = &control, input = {ui = &empty}}, "query ui now")
	testing.expect_value(t, response.text, "usage: query ui")
}

// A record's line runs inside the tick (run_tick_lines) in a context with
// no input, on every machine of the session: every input command and
// query ui answer an error there instead of reading a frame's devices.
@(test)
test_input_lines_inside_a_tick_answer_without_input :: proc(t: ^testing.T) {
	session := new(Session)
	defer free(session)
	control: Command_Control
	command_context := session_command_context(session, {}, &control, 0, "")
	for line in ([?]string{"press Confirm", "hold Jump", "release all", "release Jump", "stick left 0 0", "trigger left 0", "pointer 0 0", "type a", "query ui"}) {
		response, _ := execute_command_line(command_context, line)
		testing.expectf(t, !response.ok && !response.deferred, "%q: %v", line, response)
		testing.expect_value(t, response.text, NO_INPUT_HERE_PROBLEM)
	}
	testing.expect(t, !control.input_waiting)
}

// UI audit: the pause menu by injected navigation alone.
@(test)
test_injected_navigation_drives_the_pause_menu :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	ui := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&ui)
	state := make_injected_screen_state(t)
	defer destroy_injected_screen_state(state)
	open_pause_menu(audit, &ui)
	resume, settings := pause_button_id("pause_resume"), pause_button_id("pause_settings")
	testing.expect_value(t, ui.focus, resume)
	expect_injected_answer(t, state, "press Navigate_Down", "pressed gamepad DPAD_DOWN (Navigate_Down) for 1 frame", audit, &ui)
	testing.expect(t, ui.focus != resume)
	for _ in 0 ..< 10 {
		if ui.focus == settings {
			break
		}
		run_injected_line(state, "press Navigate_Down", audit, &ui)
	}
	testing.expect_value(t, ui.focus, settings)
	expect_injected_answer(t, state, "press Confirm", "pressed gamepad SOUTH (Confirm) for 1 frame", audit, &ui)
	testing.expect_value(t, top_screen(ui.screens), Screen.Settings)
	expect_injected_answer(t, state, "press Back", "pressed gamepad EAST (Back) for 1 frame", audit, &ui)
	testing.expect_value(t, top_screen(ui.screens), Screen.Pause)
	testing.expect_value(t, ui.active_device, Input_Device.Gamepad)
}

// UI audit: a click where the pointer was put.
@(test)
test_an_injected_click_on_a_widget_activates_it :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	ui := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&ui)
	state := make_injected_screen_state(t)
	defer destroy_injected_screen_state(state)
	open_pause_menu(audit, &ui)
	at := widget_centre(ui, pause_button_id("pause_developer"))
	pointer_line := fmt.tprintf("pointer %d %d", int(at.x), int(at.y))
	expect_injected_answer(t, state, pointer_line, fmt.tprintf("pointer at %d %d", int(at.x), int(at.y)), audit, &ui)
	expect_injected_answer(t, state, "press mouse LEFT", "pressed mouse LEFT for 1 frame", audit, &ui)
	testing.expect_value(t, top_screen(ui.screens), Screen.Developer)
	testing.expect_value(t, ui.active_device, Input_Device.Keyboard_Mouse)
}

// UI audit: typed text into the new world's name, Enter ends the entry.
@(test)
test_injected_text_types_into_the_new_world_name :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	ui := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&ui)
	state := make_injected_screen_state(t)
	defer destroy_injected_screen_state(state)
	open_new_world_name_entry(audit, &ui, false)
	expect_injected_answer(t, state, `type "Deep mine"`, "typed 9 characters", audit, &ui)
	testing.expect_value(t, text_field_text(&audit.title.setup.name), "Deep mine")
	expect_injected_answer(t, state, "press keyboard ENTER", "pressed keyboard ENTER for 1 frame", audit, &ui)
	testing.expect_value(t, ui.keyboard.field, 0)
	testing.expect_value(t, text_field_text(&audit.title.setup.name), "Deep mine")
	testing.expect_value(t, top_screen(ui.screens), Screen.New_World)
}

local_player_height :: proc(state: ^Frame_State) -> f32 {
	return session_local_player(state.session).position.y
}

@(test) // slow
test_an_injected_jump_lifts_the_player_through_the_input_record :: proc(t: ^testing.T) {
	state := make_injected_world_frame(t)
	defer destroy_injected_world_frame(state)
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 0)) {
		return
	}
	testing.expect(t, session_local_player(state.session).flying, "the debug terrain's player flies")
	expect_injected_answer(t, state, "hold Jump", "holding gamepad SOUTH (Jump)")
	height, tick := local_player_height(state), state.session.simulation.tick
	for _ in 0 ..< 10 {
		run_injected_test_frame(state)
	}
	testing.expect_value(t, state.session.simulation.tick - tick, 10)
	testing.expectf(t, local_player_height(state) > height, "%v rose to %v", height, local_player_height(state))
}

// The tick command's ticks wait for no frame: until pending_ticks is 0, at
// most five frames, then the loop's answer.
run_injected_tick_line :: proc(t: ^testing.T, state: ^Frame_State, line: string) {
	control := &state.developer.command_control
	answer, _, _ := run_injected_line(state, line)
	testing.expect(t, answer.ok && control.ticks_waiting)
	for frame := 0; frame < 5 && control.pending_ticks > 0; frame += 1 {
		run_injected_test_frame(state)
	}
	testing.expect_value(t, control.pending_ticks, 0)
	_, finished := finish_command_ticks(control, state.session.simulation.tick)
	testing.expect(t, finished)
}

@(test) // slow
test_a_tick_command_runs_with_the_held_input_under_the_none_backend :: proc(t: ^testing.T) {
	state := make_injected_world_frame(t)
	defer destroy_injected_world_frame(state)
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 0)) {
		return
	}
	simulation := &state.session.simulation
	answer, _, _ := run_injected_line(state, "pause")
	testing.expect(t, answer.ok)
	height, tick := local_player_height(state), simulation.tick
	expect_injected_answer(t, state, "hold Jump", "holding gamepad SOUTH (Jump)")
	testing.expect_value(t, simulation.tick, tick)
	testing.expect_value(t, local_player_height(state), height)
	run_injected_tick_line(t, state, "tick 10")
	testing.expect_value(t, simulation.tick, tick + 10)
	testing.expectf(t, local_player_height(state) > height, "%v rose to %v", height, local_player_height(state))
	expect_injected_answer(t, state, "release Jump", "released gamepad SOUTH (Jump)")
	risen := local_player_height(state)
	run_injected_tick_line(t, state, "tick 10")
	testing.expect_value(t, simulation.tick, tick + 20)
	testing.expect_value(t, local_player_height(state), risen)
}

@(test)
test_frame_events_wait_for_the_tick_only_under_the_none_backend :: proc(t: ^testing.T) {
	testing.expect(t, !frame_events_dropped(false, false, true))
	testing.expect(t, !frame_events_dropped(false, false, false))
	testing.expect(t, frame_events_dropped(true, true, true))
	testing.expect(t, frame_events_dropped(true, false, false))
	testing.expect(t, !frame_events_dropped(true, false, true))
}

// The item's "a key pressed in raylib's state is ignored" cannot be set up
// headless (raylib presses no key without a window); the frame read here
// is the virtual devices' alone.
@(test) // slow
test_the_none_backend_reads_the_virtual_devices_alone :: proc(t: ^testing.T) {
	state := make_injected_world_frame(t)
	defer destroy_injected_world_frame(state)
	set_injected_control(&state.interaction.injected, test_injected_control(.Gamepad, "SOUTH"), true)
	note_injected_change(&state.interaction.injected)
	frame := read_input_frame(state, 0, state.frame_seconds)
	testing.expect_value(t, string(frame.raw.gamepad.name), INJECTED_GAMEPAD_NAME)
	testing.expect(t, .Confirm in frame.pressed)
	testing.expect(t, !state.interaction.injected.unread)
}

// Decision 1 of the item: --input=none starts on the gamepad's glyphs,
// and frames without injected input keep them.
@(test)
test_the_none_backend_starts_on_the_gamepads_glyphs :: proc(t: ^testing.T) {
	state := make_injected_screen_state(t)
	defer destroy_injected_screen_state(state)
	state.viewport_count = 1
	ui := primary_ui(state)
	defer destroy_ui_state(ui)
	testing.expect_value(t, ui.active_device, Input_Device.Gamepad)
	viewport := &state.viewports[0]
	for _ in 0 ..< 3 {
		viewport.interaction.previous_input = viewport.interaction.input
		viewport.interaction.input = read_input_frame(state, 0, 1.0 / 60)
		input: Ui_Input
		input, viewport.interaction.tab_flick_armed = make_ui_input(viewport.interaction.previous_input, viewport.interaction.input, viewport.interaction.tab_flick_armed)
		ui_begin(ui, input, {1920, 1080}, 1.0 / 60, 1, 1)
		ui_resolve(ui)
		testing.expect_value(t, ui.active_device, Input_Device.Gamepad)
	}
}
