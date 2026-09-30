package game

import "core:testing"
import rl "shared:raylib"
import sdl "vendor:sdl3"

// A 20:9 phone as in GameNative's screenshot.
PHONE_SCREEN :: [2]f32{2424, 1080}

shipped_touch_overlay :: proc(t: ^testing.T) -> Touch_Overlay_Layout {
	layout, problem := parse_touch_overlay_file(#load("../data/touch_overlay.sjson"), "data/touch_overlay.sjson", context.temp_allocator)
	testing.expect_value(t, problem, "")
	return layout
}

placed_by_label :: proc(layout: Touch_Overlay_Layout, placed: []Placed_Element, label: string) -> Placed_Element {
	for element in placed {
		if layout.elements[element.element].label == label {
			return element
		}
	}
	return {element = -1}
}

expect_near :: proc(t: ^testing.T, value, expected: [2]f32, loc := #caller_location) {
	testing.expectf(t, abs(value.x - expected.x) < 0.01 && abs(value.y - expected.y) < 0.01, "%v, expected %v", value, expected, loc = loc)
}

slot_by_id :: proc(state: Touch_Overlay_State, id: i32) -> Touch_Slot {
	for slot in state.slots {
		if slot.active && slot.id == id {
			return slot
		}
	}
	return {}
}

// One frame of fingers, the output as the backends read it.
touch_frame :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, points: []Touch_Point, world_shown := true, screen := PHONE_SCREEN) -> Touch_Overlay_Output {
	placed := overlay_layout(layout, screen, context.temp_allocator)
	update_touch_overlay(state, points, layout, placed, screen, world_shown)
	return touch_overlay_output(state^, layout, screen, world_shown)
}

@(test)
test_shipped_touch_overlay_loads :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	testing.expect_value(t, layout.reference_height, 1080)
	testing.expect_value(t, len(layout.elements), 13)
	testing.expect_value(t, len(overlay_layout(layout, PHONE_SCREEN, context.temp_allocator)), 11)
	stick := layout.elements[zone_element(layout, .Stick, .Left)]
	testing.expect_value(t, stick.radius, 130)
	testing.expect_value(t, stick.sprint_rim, 1.25)
	testing.expect(t, zone_element(layout, .Look, .Right) >= 0)
}

@(test)
test_overlay_layout_scales_and_anchors_at_two_screen_sizes :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	// 20:9, 1080 high: the reference itself.
	phone := overlay_layout(layout, PHONE_SCREEN, context.temp_allocator)
	expect_near(t, placed_by_label(layout, phone, "A").centre, {2112, 575})
	expect_near(t, placed_by_label(layout, phone, "A").size, {146, 146})
	expect_near(t, placed_by_label(layout, phone, "X").centre, {1967, 431})
	expect_near(t, placed_by_label(layout, phone, "LT").centre, {181.5, 85})
	expect_near(t, placed_by_label(layout, phone, "RT").centre, {2424 - 181.5, 85})
	expect_near(t, placed_by_label(layout, phone, "L3").centre, {121, 790})
	expect_near(t, placed_by_label(layout, phone, "Back").centre, {1113, 60})
	expect_near(t, placed_by_label(layout, phone, "Start").centre, {1304, 60})
	// 16:9, 720 high: two thirds, the corners kept.
	small := overlay_layout(layout, {1280, 720}, context.temp_allocator)
	expect_near(t, placed_by_label(layout, small, "A").centre, {1280 - 208, 575 * 2.0 / 3})
	expect_near(t, placed_by_label(layout, small, "A").size, {146 * 2.0 / 3, 146 * 2.0 / 3})
	expect_near(t, placed_by_label(layout, small, "LB").centre, {85 * 2.0 / 3, 238 * 2.0 / 3})
	expect_near(t, placed_by_label(layout, small, "L3").centre, {121 * 2.0 / 3, 720 - 290 * 2.0 / 3})
	expect_near(t, placed_by_label(layout, small, "Start").centre, {640 + 92 * 2.0 / 3, 40})
	// 16:9 at 1080: the same sizes, the right side follows the edge.
	wide := overlay_layout(layout, {1920, 1080}, context.temp_allocator)
	expect_near(t, placed_by_label(layout, wide, "A").centre, {1920 - 312, 575})
	expect_near(t, placed_by_label(layout, wide, "Back").centre, {960 - 99, 60})
}

@(test)
test_touch_overlay_hit_tests_per_shape :: proc(t: ^testing.T) {
	rectangle := Placed_Element{shape = .Rectangle, centre = {100, 100}, size = {40, 20}}
	testing.expect(t, placed_element_contains(rectangle, {100, 100}))
	testing.expect(t, placed_element_contains(rectangle, {119, 109}))
	testing.expect(t, !placed_element_contains(rectangle, {121, 100}))
	testing.expect(t, !placed_element_contains(rectangle, {100, 111}))
	circle := Placed_Element{shape = .Circle, centre = {100, 100}, size = {40, 40}}
	testing.expect(t, placed_element_contains(circle, {119, 100}))
	testing.expect(t, placed_element_contains(circle, {100, 81}))
	// The bounding box's corner lies outside the circle.
	testing.expect(t, !placed_element_contains(circle, {118, 118}))
	testing.expect(t, !placed_element_contains(circle, {121, 100}))
	layout := shipped_touch_overlay(t)
	placed := overlay_layout(layout, PHONE_SCREEN, context.temp_allocator)
	testing.expect_value(t, layout.elements[button_at(placed, {2112, 575})].label, "A")
	testing.expect_value(t, button_at(placed, {1600, 850}), -1)
}

@(test)
test_touch_on_a_button_latches_it_until_the_finger_lifts :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	output := touch_frame(&state, layout, {{id = 3, position = {2112, 575}}})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.SOUTH)])
	// Slid off onto the free right half: still A, and no look.
	output = touch_frame(&state, layout, {{id = 3, position = {1700, 800}}})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.SOUTH)])
	testing.expect_value(t, output.look_delta, [2]f32{})
	output = touch_frame(&state, layout, {})
	testing.expect_value(t, output, Touch_Overlay_Output{})
	// A trigger.
	output = touch_frame(&state, layout, {{id = 4, position = {100, 50}}})
	testing.expect(t, output.triggers[.Left])
	testing.expect(t, !output.triggers[.Right])
}

@(test)
test_left_drag_is_the_stick_and_past_the_rim_up_it_sprints :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	origin := [2]f32{600, 700}
	output := touch_frame(&state, layout, {{id = 0, position = origin}})
	testing.expect_value(t, output.stick, [2]f32{})
	// Half the radius to the right.
	output = touch_frame(&state, layout, {{id = 0, position = origin + {65, 0}}})
	expect_near(t, output.stick, {0.5, 0})
	// A small drag goes on raw; the backend's stick dead zone takes it.
	output = touch_frame(&state, layout, {{id = 0, position = origin + {10, 5}}})
	expect_near(t, output.stick, {10.0 / 130, 5.0 / 130})
	testing.expect_value(t, gamepad_stick(touch_overlay_raw_gamepad(output, .Raylib), .LEFT_X, .LEFT_Y), [2]f32{})
	// Past the radius but inside the rim: full stick up, no sprint.
	output = touch_frame(&state, layout, {{id = 0, position = origin + {0, -150}}})
	expect_near(t, output.stick, {0, -1})
	testing.expect(t, !output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
	// Past the rim to the side or down: no sprint.
	output = touch_frame(&state, layout, {{id = 0, position = origin + {170, 0}}})
	expect_near(t, output.stick, {1, 0})
	testing.expect(t, !output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
	output = touch_frame(&state, layout, {{id = 0, position = origin + {0, 170}}})
	testing.expect(t, !output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
	// Past the rim (1.25 times 130) within 45 degrees of up: the stick
	// click holds from here on, back inside the rim and to the side too.
	output = touch_frame(&state, layout, {{id = 0, position = origin + {110, -130}}})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
	output = touch_frame(&state, layout, {{id = 0, position = origin + {0, -60}}})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
	output = touch_frame(&state, layout, {{id = 0, position = origin + {170, 0}}})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
	// The finger lifts: nothing held, and the next drag starts unlatched.
	output = touch_frame(&state, layout, {})
	testing.expect_value(t, output, Touch_Overlay_Output{})
	touch_frame(&state, layout, {{id = 2, position = origin}})
	output = touch_frame(&state, layout, {{id = 2, position = origin + {0, -100}}})
	testing.expect(t, !output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
	touch_frame(&state, layout, {})
	// On a 720 high screen the radius scales with it: 65 pixels is three
	// quarters of the stick.
	small := [2]f32{1280, 720}
	touch_frame(&state, layout, {{id = 1, position = {400, 500}}}, true, small)
	output = touch_frame(&state, layout, {{id = 1, position = {465, 500}}}, true, small)
	expect_near(t, output.stick, {0.75, 0})
}

// A frame through the raylib backend's path: the overlay's gamepad, the
// shipped bindings, the hold settings.
rim_sprint_frame :: proc(output: Touch_Overlay_Output, tables: Input_Bindings, previous: Action_Set, settings: Settings) -> Input_Frame {
	gamepad := touch_overlay_raw_gamepad(output, .Raylib)
	move := gamepad_stick(gamepad, .LEFT_X, .LEFT_Y)
	pressed := gamepad_button_actions(gamepad, tables) + analog_actions(move, {}, {})
	frame := Input_Frame{move = move, pressed = pressed, just_pressed = actions_just_pressed(previous, pressed)}
	return apply_hold_settings(frame, settings)
}

// Drags up past the rim, eases back inside it, pushes out and back
// again, then lifts. Returns whether the player sprints after each step.
rim_sprint_steps :: proc(t: ^testing.T, settings: Settings) -> [6]bool {
	layout := shipped_touch_overlay(t)
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Raylib, context.temp_allocator)
	origin := [2]f32{600, 700}
	drags := [6][]Touch_Point {
		{{id = 0, position = origin}},
		{{id = 0, position = origin + {0, -170}}},
		{{id = 0, position = origin + {0, -100}}},
		{{id = 0, position = origin + {10, -170}}},
		{{id = 0, position = origin + {-100, -100}}},
		{},
	}
	state: Touch_Overlay_State
	previous: Action_Set
	sprinting := false
	result: [6]bool
	for points, index in drags {
		frame := rim_sprint_frame(touch_frame(&state, layout, points), tables, previous, settings)
		sprinting = update_sprinting(sprinting, frame)
		previous = frame.pressed
		result[index] = sprinting
	}
	return result
}

@(test)
test_rim_sprint_lasts_the_drag_in_both_sprint_settings :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	testing.expect_value(t, settings.sprint_hold, Hold_Mode.Toggle)
	// Toggle: the one edge switches sprint on, it ends when movement stops.
	testing.expect_value(t, rim_sprint_steps(t, settings), [6]bool{false, true, true, true, true, false})
	settings.sprint_hold = .Hold
	testing.expect_value(t, rim_sprint_steps(t, settings), [6]bool{false, true, true, true, true, false})
}
@(test)
test_right_drag_gives_the_look_delta :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	output := touch_frame(&state, layout, {{id = 5, position = {1600, 850}}})
	testing.expect_value(t, output.look_delta, [2]f32{})
	output = touch_frame(&state, layout, {{id = 5, position = {1630, 840}}})
	expect_near(t, output.look_delta, {30, -10})
	testing.expect_value(t, output.stick, [2]f32{})
	output = touch_frame(&state, layout, {{id = 5, position = {1630, 840}}})
	testing.expect_value(t, output.look_delta, [2]f32{})
}

@(test)
test_a_finger_on_the_stick_the_look_and_a_button_at_once :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	touch_frame(&state, layout, {{id = 0, position = {500, 700}}, {id = 1, position = {1600, 850}}, {id = 2, position = {2252, 431}}})
	output := touch_frame(&state, layout, {{id = 0, position = {500, 570}}, {id = 1, position = {1620, 850}}, {id = 2, position = {2252, 431}}})
	expect_near(t, output.stick, {0, -1})
	expect_near(t, output.look_delta, {20, 0})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.EAST)])
	// A second finger on the left half while the stick is held reads nothing.
	output = touch_frame(&state, layout, {{id = 0, position = {500, 570}}, {id = 3, position = {800, 800}}})
	expect_near(t, output.stick, {0, -1})
	testing.expect_value(t, slot_by_id(state, 3).role, Touch_Role.Ignored)
	// The stick's finger lifts; the other stays ignored.
	output = touch_frame(&state, layout, {{id = 3, position = {900, 800}}})
	testing.expect_value(t, output, Touch_Overlay_Output{})
}

@(test)
test_with_a_screen_open_only_start_and_back_read_and_are_drawn :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	// A and the stick's and look's halves are the pointer's; Start reads.
	points := [?]Touch_Point{{id = 0, position = {2112, 575}}, {id = 1, position = {600, 700}}, {id = 2, position = {1304, 60}}, {id = 3, position = {1600, 850}}}
	output := touch_frame(&state, layout, points[:], false)
	expected: Touch_Overlay_Output
	expected.buttons[int(sdl.GamepadButton.START)] = true
	testing.expect_value(t, output, expected)
	points[1].position, points[3].position = {600, 500}, {1650, 800}
	output = touch_frame(&state, layout, points[:], false)
	testing.expect_value(t, output, expected)
	// The screen closes with the fingers down: they began as the pointer
	// and stay the pointer's; Start stays held.
	points[1].position = {600, 400}
	output = touch_frame(&state, layout, points[:], true)
	testing.expect_value(t, output, expected)
	touch_frame(&state, layout, {})
	// Back also reads over a screen.
	output = touch_frame(&state, layout, {{id = 6, position = {1113, 60}}}, false)
	testing.expect(t, output.buttons[int(sdl.GamepadButton.BACK)])
	touch_frame(&state, layout, {})
	// A stick and A held from the world read nothing while a screen is
	// open, and again once it closes. A rim crossing under the screen does
	// not latch the sprint, so closing it makes no fresh Sprint press.
	touch_frame(&state, layout, {{id = 4, position = {600, 700}}, {id = 5, position = {2112, 575}}})
	output = touch_frame(&state, layout, {{id = 4, position = {600, 520}}, {id = 5, position = {2112, 575}}}, false)
	testing.expect_value(t, output, Touch_Overlay_Output{})
	testing.expect(t, !slot_by_id(state, 4).sprint_latched)
	output = touch_frame(&state, layout, {{id = 4, position = {600, 600}}, {id = 5, position = {2112, 575}}}, true)
	testing.expect(t, output.buttons[int(sdl.GamepadButton.SOUTH)])
	testing.expect(t, output.stick.y < 0)
	testing.expect(t, !output.buttons[int(sdl.GamepadButton.LEFT_STICK)])
}

touch_overlay_drawn_labels :: proc(ui: ^Ui_State) -> [dynamic]string {
	labels := make([dynamic]string, context.temp_allocator)
	for command in ui.draw_list {
		if command.kind == .Text {
			append(&labels, command.text)
		}
	}
	return labels
}

@(test)
test_touch_overlay_draws_start_and_back_alone_over_a_screen :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	touch_frame(&state, layout, {{id = 0, position = {600, 700}}})
	touch_frame(&state, layout, {{id = 0, position = {650, 700}}})
	ui: Ui_State
	defer delete(ui.draw_list)
	ui.pixels_per_unit = ui_pixels_per_unit(PHONE_SCREEN.y, 1)
	draw_touch_overlay(&ui, state, layout, PHONE_SCREEN, false)
	labels := touch_overlay_drawn_labels(&ui)
	testing.expect_value(t, len(labels), 2)
	testing.expect_value(t, labels[0], "Back")
	testing.expect_value(t, labels[1], "Start")
	for command in ui.draw_list {
		testing.expect(t, command.kind != .Circle && command.kind != .Ring, "no stick or face button over a screen")
	}
	clear(&ui.draw_list)
	draw_touch_overlay(&ui, state, layout, PHONE_SCREEN, true)
	testing.expect_value(t, len(touch_overlay_drawn_labels(&ui)), 11)
	rings := 0
	for command in ui.draw_list {
		if command.kind == .Ring {
			rings += 1
		}
	}
	// A, B, X, Y, L3 and the stick's base.
	testing.expect_value(t, rings, 6)
}

@(test)
test_touch_overlay_gamepad_reaches_the_bindings_on_both_backends :: proc(t: ^testing.T) {
	bindings := shipped_default_bindings(t)
	output: Touch_Overlay_Output
	output.buttons[int(sdl.GamepadButton.SOUTH)] = true
	output.buttons[int(sdl.GamepadButton.EAST)] = true
	output.triggers[.Right] = true
	output.stick = {0.5, -1}
	raylib_tables, _ := build_input_bindings(bindings, .Raylib, context.temp_allocator)
	raylib_gamepad := touch_overlay_raw_gamepad(output, .Raylib)
	testing.expect(t, raylib_gamepad.connected)
	testing.expect_value(t, raylib_gamepad.name, TOUCH_OVERLAY_GAMEPAD_NAME)
	testing.expect(t, raylib_gamepad.button_down[int(rl.GamepadButton.RIGHT_FACE_DOWN)])
	testing.expect(t, raylib_gamepad.button_down[int(rl.GamepadButton.RIGHT_TRIGGER_2)])
	testing.expect_value(t, raylib_gamepad.axis_values[int(rl.GamepadAxis.LEFT_TRIGGER)], RAYLIB_TRIGGER_REST)
	raylib_actions := gamepad_button_actions(raylib_gamepad, raylib_tables)
	testing.expect(t, raylib_actions >= {.Jump, .Sneak, .Mine})
	expect_near(t, gamepad_stick(raylib_gamepad, .LEFT_X, .LEFT_Y), {0.5, 1})
	sdl3_tables, _ := build_input_bindings(bindings, .Sdl3, context.temp_allocator)
	sdl3_gamepad := touch_overlay_raw_gamepad(output, .Sdl3)
	testing.expect(t, sdl3_gamepad.button_down[int(sdl.GamepadButton.SOUTH)])
	sdl3_actions := gamepad_button_actions(sdl3_gamepad, sdl3_tables) + gamepad_trigger_actions(sdl3_gamepad, sdl3_tables)
	testing.expect(t, sdl3_actions >= {.Jump, .Sneak, .Mine})
}

@(test)
test_touch_overlay_merges_into_a_physical_gamepad :: proc(t: ^testing.T) {
	physical := Raw_Gamepad {
		connected    = true,
		name         = "Pad",
		axis_count   = 6,
		button_count = 18,
	}
	physical.axis_values[int(rl.GamepadAxis.LEFT_X)] = 0.75
	physical.axis_values[int(rl.GamepadAxis.RIGHT_TRIGGER)] = RAYLIB_TRIGGER_REST
	physical.button_down[int(rl.GamepadButton.MIDDLE_RIGHT)] = true
	output: Touch_Overlay_Output
	output.buttons[int(sdl.GamepadButton.SOUTH)] = true
	output.triggers[.Right] = true
	output.stick = {0.5, 0}
	overlay := Touch_Overlay_Frame{active = true, world_shown = true, output = output}
	merged := touch_overlay_gamepad(physical, overlay, .Raylib)
	testing.expect_value(t, merged.name, cstring("Pad"))
	testing.expect(t, merged.button_down[int(rl.GamepadButton.MIDDLE_RIGHT)])
	testing.expect(t, merged.button_down[int(rl.GamepadButton.RIGHT_FACE_DOWN)])
	testing.expect_value(t, merged.axis_values[int(rl.GamepadAxis.LEFT_X)], 1)
	testing.expect_value(t, merged.axis_values[int(rl.GamepadAxis.RIGHT_TRIGGER)], 1)
	// No physical pad: the overlay's alone; overlay off: the physical alone.
	testing.expect_value(t, touch_overlay_gamepad({}, overlay, .Raylib).name, cstring(TOUCH_OVERLAY_GAMEPAD_NAME))
	testing.expect_value(t, touch_overlay_gamepad(physical, {}, .Raylib), physical)
	// The drags look instead of the pointer only while the world shows.
	overlay.output.look_delta = {4, 2}
	testing.expect_value(t, pointer_look_delta({9, 9}, overlay), [2]f32{4, 2})
	overlay.world_shown = false
	testing.expect_value(t, pointer_look_delta({9, 9}, overlay), [2]f32{9, 9})
}

@(test)
test_touch_overlay_setting_decides_when_it_is_on :: proc(t: ^testing.T) {
	testing.expect(t, touch_overlay_enabled(.Auto, false, true))
	testing.expect(t, !touch_overlay_enabled(.Auto, false, false))
	testing.expect(t, touch_overlay_enabled(.Auto, true, false))
	testing.expect(t, touch_overlay_enabled(.On, false, false))
	testing.expect(t, !touch_overlay_enabled(.Off, false, true))
	testing.expect(t, touch_overlay_enabled(.Off, true, true))
	testing.expect_value(t, next_touch_overlay_mode(.Auto), Touch_Overlay_Mode.On)
	testing.expect_value(t, next_touch_overlay_mode(.Off), Touch_Overlay_Mode.Auto)
}

@(test)
test_touch_overlay_errors_name_the_element :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	Case :: struct {
		text:    string,
		mention: string,
	}
	cases := [?]Case {
		{`reference_height = 1080 elements = [{kind = "button" control = "SOUTHH" shape = "circle" anchor = "top_right" position = [10, 10] size = [20, 20] label = "A"}]`, `elements[0] ("A"): unknown control "SOUTHH"`},
		{`reference_height = 1080 elements = [{kind = "button" control = "LEFT_PADDLE1" shape = "circle" anchor = "top_right" position = [10, 10] size = [20, 20] label = "L4"}]`, `elements[0] ("L4"): unknown control "LEFT_PADDLE1"`},
		{`reference_height = 1080 elements = [{kind = "button" control = "SOUTH" shape = "oval" anchor = "top_right" position = [10, 10] size = [20, 20] label = "A"}]`, `elements[0] ("A"): unknown shape "oval"`},
		{`reference_height = 1080 elements = [{kind = "button" control = "SOUTH" shape = "circle" anchor = "middle" position = [10, 10] size = [20, 20] label = "A"}]`, `elements[0] ("A"): unknown anchor "middle"`},
		{`reference_height = 1080 elements = [{kind = "stick" side = "left" radius = 130 sprint_rim = 1.25} {kind = "dpad" label = "D"}]`, `elements[1] ("D"): unknown kind "dpad"`},
		{`reference_height = 1080 elements = [{kind = "stick" side = "up" radius = 130 sprint_rim = 1.25}]`, `elements[0] (stick): unknown side "up"`},
		{`reference_height = 1080 elements = [{kind = "stick" side = "left" radius = 130 sprint_rim = 1.25} {kind = "look" side = "left" sensitivity = 1}]`, "the stick and the look are on the same side"},
		{`reference_height = 1080 elements = [{kind = "look" side = "right" sensitivity = 1 colour = "red"}]`, "unknown key elements[0].colour"},
		{`reference_height = 0 elements = []`, "reference_height must be positive"},
	}
	for test_case in cases {
		_, problem := parse_touch_overlay_file(transmute([]byte)test_case.text, "data/touch_overlay.sjson")
		expect_problem_mentions(t, problem, "data/touch_overlay.sjson", test_case.mention)
	}
}

@(test)
test_a_finger_whose_element_a_reload_replaced_reads_nothing :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	touch_frame(&state, layout, {{id = 0, position = {600, 700}}})
	stick := slot_by_id(state, 0)
	testing.expect_value(t, stick.role, Touch_Role.Stick)
	// The reloaded file has only the buttons: the stick's index is a
	// button now, or past the end.
	reloaded := Touch_Overlay_Layout{reference_height = layout.reference_height, elements = layout.elements[:stick.element]}
	testing.expect(t, !touch_slot_reads(stick, reloaded))
	shifted := Touch_Overlay_Layout{reference_height = layout.reference_height, elements = layout.elements[1:]}
	testing.expect_value(t, shifted.elements[stick.element].kind, Touch_Overlay_Kind.Look)
	testing.expect(t, !touch_slot_reads(stick, shifted))
	output := touch_frame(&state, reloaded, {{id = 0, position = {600, 500}}})
	testing.expect_value(t, output, Touch_Overlay_Output{})
}

@(test)
test_touch_overlay_merges_in_sdl_numbering :: proc(t: ^testing.T) {
	physical := Raw_Gamepad {
		connected    = true,
		name         = "Pad",
		axis_count   = TOUCH_OVERLAY_AXIS_COUNT,
		button_count = TOUCH_OVERLAY_SDL_BUTTON_COUNT,
	}
	physical.axis_values[int(sdl.GamepadAxis.LEFTY)] = -0.5
	physical.button_down[int(sdl.GamepadButton.MISC2)] = true
	output: Touch_Overlay_Output
	output.triggers[.Left] = true
	output.stick = {0, -1}
	output.buttons[int(sdl.GamepadButton.NORTH)] = true
	overlay := touch_overlay_raw_gamepad(output, .Sdl3)
	testing.expect(t, overlay.on_screen)
	testing.expect_value(t, overlay.axis_values[int(sdl.GamepadAxis.RIGHT_TRIGGER)], 0)
	merged := merge_touch_overlay_gamepad(physical, overlay)
	testing.expect(t, !merged.on_screen)
	testing.expect_value(t, merged.axis_values[int(sdl.GamepadAxis.LEFT_TRIGGER)], 1)
	testing.expect_value(t, merged.axis_values[int(sdl.GamepadAxis.RIGHT_TRIGGER)], 0)
	testing.expect_value(t, merged.axis_values[int(sdl.GamepadAxis.LEFTY)], -1)
	testing.expect(t, merged.button_down[int(sdl.GamepadButton.MISC2)])
	testing.expect(t, merged.button_down[int(sdl.GamepadButton.NORTH)])
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Sdl3, context.temp_allocator)
	testing.expect(t, .Place in gamepad_trigger_actions(merged, tables))
	testing.expect(t, .Mine not_in gamepad_trigger_actions(merged, tables))
}

@(test)
test_touch_overlay_look_is_in_the_mouse_units :: proc(t: ^testing.T) {
	// A desktop scaled 1.5 times: render pixels are 1.5 window units.
	testing.expect_value(t, render_pixels_to_window_units({30, -15}, {1280, 720}, {1920, 1080}), [2]f32{20, -10})
	// The phone: window and render are the screen.
	testing.expect_value(t, render_pixels_to_window_units({30, -15}, {2424, 1080}, {2424, 1080}), [2]f32{30, -15})
	testing.expect_value(t, render_pixels_to_window_units({30, -15}, {1280, 720}, {0, 0}), [2]f32{30, -15})
}

@(test)
test_touch_overlay_presses_keep_touch_the_active_device :: proc(t: ^testing.T) {
	output: Touch_Overlay_Output
	previous := Raw_Input{gamepad = touch_overlay_raw_gamepad(output, .Raylib)}
	output.buttons[int(sdl.GamepadButton.WEST)] = true
	output.stick = {0.8, 0}
	current := Raw_Input{gamepad = touch_overlay_raw_gamepad(output, .Raylib)}
	_, seen := detect_input_device(previous, current)
	testing.expect(t, !seen)
	// The touch that pressed X is a mouse click to the UI.
	current.mouse.button_down[0] = true
	device, touch_seen := detect_input_device(previous, current)
	testing.expect(t, touch_seen)
	testing.expect_value(t, device, Input_Device.Keyboard_Mouse)
	// A physical gamepad's press still counts.
	current.gamepad.on_screen = false
	device, _ = detect_input_device(previous, current)
	testing.expect_value(t, device, Input_Device.Gamepad)
}

// The overlay's buttons in UI units at ui scale 1, as the HUD lays out.
@(test)
test_no_touch_overlay_element_covers_a_hotbar_slot :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	for screen in ([?][2]f32{PHONE_SCREEN, {1280, 720}}) {
		ui: Ui_State
		ui.pixels_per_unit = ui_pixels_per_unit(screen.y, 1)
		ui.screen_units = ui_screen_units(screen, ui.pixels_per_unit)
		for selected in 0 ..< HOTBAR_SLOT_COUNT {
			for slot in hud_hotbar_rectangles(ui_safe_area(&ui), selected) {
				slot_pixels := Ui_Rectangle{slot.x * ui.pixels_per_unit, slot.y * ui.pixels_per_unit, slot.width * ui.pixels_per_unit, slot.height * ui.pixels_per_unit}
				for placed in overlay_layout(layout, screen, context.temp_allocator) {
					corner := placed.centre - placed.size / 2
					element := Ui_Rectangle{corner.x, corner.y, placed.size.x, placed.size.y}
					testing.expectf(t, !rectangles_overlap(element, slot_pixels), "%v at %v covers a hotbar slot at %v", layout.elements[placed.element].label, screen, slot_pixels)
				}
			}
		}
	}
}

@(test)
test_a_touch_the_overlay_claims_is_no_pointer_click :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	pressed_mouse: Raw_Mouse
	pressed_mouse.position = {1304, 60}
	pressed_mouse.button_down[int(rl.MouseButton.LEFT)] = true
	// A Start tap over a screen: the pill reads, the mouse button does not.
	frame := touch_overlay_frame(&state, layout, {{id = 7, position = {1304, 60}}}, PHONE_SCREEN, false)
	testing.expect(t, frame.output.buttons[int(sdl.GamepadButton.START)])
	testing.expect(t, frame.pointer_claimed)
	mouse := touch_overlay_mouse(pressed_mouse, frame)
	testing.expect(t, !mouse.button_down[int(rl.MouseButton.LEFT)])
	expect_near(t, mouse.position, {1304, 60})
	// Still claimed while the finger stays down.
	frame = touch_overlay_frame(&state, layout, {{id = 7, position = {1320, 400}}}, PHONE_SCREEN, false)
	testing.expect(t, frame.pointer_claimed)
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, false)
	// A plain pointer tap elsewhere over the screen keeps the button down.
	frame = touch_overlay_frame(&state, layout, {{id = 8, position = {900, 500}}}, PHONE_SCREEN, false)
	testing.expect(t, !frame.pointer_claimed)
	testing.expect(t, touch_overlay_mouse(pressed_mouse, frame).button_down[int(rl.MouseButton.LEFT)])
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, false)
	// In the world a button claims it too, the stick does not.
	frame = touch_overlay_frame(&state, layout, {{id = 9, position = {2112, 575}}}, PHONE_SCREEN, true)
	testing.expect(t, frame.pointer_claimed)
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, true)
	frame = touch_overlay_frame(&state, layout, {{id = 10, position = {600, 700}}}, PHONE_SCREEN, true)
	testing.expect(t, !frame.pointer_claimed)
	// Only the first touch holds the mouse button: a second finger on
	// Start leaves a pointer finger's click alone.
	frame = touch_overlay_frame(&state, layout, {{id = 10, position = {600, 700}}, {id = 11, position = {1304, 60}}}, PHONE_SCREEN, true)
	testing.expect(t, !frame.pointer_claimed)
	// The overlay off: nothing claimed.
	testing.expect(t, touch_overlay_mouse(pressed_mouse, {}).button_down[int(rl.MouseButton.LEFT)])
}
