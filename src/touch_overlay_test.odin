package game

import "core:fmt"
import "core:math/linalg"
import "core:os"
import "core:strings"
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

// The shipped layout before 0134, GameNative's buttons with the stick and
// the look (no jump zone), for the tests of the buttons a user layout may
// still carry.
GAMENATIVE_TOUCH_LAYOUT :: `reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [
	{kind = "button" control = "LEFT_TRIGGER" shape = "rectangle" anchor = "top_left" position = [181.5, 85] size = [363, 170] label = "LT"}
	{kind = "button" control = "RIGHT_TRIGGER" shape = "rectangle" anchor = "top_right" position = [181.5, 85] size = [363, 170] label = "RT"}
	{kind = "button" control = "LEFT_SHOULDER" shape = "rectangle" anchor = "top_left" position = [85, 238] size = [170, 100] label = "LB"}
	{kind = "button" control = "RIGHT_SHOULDER" shape = "rectangle" anchor = "top_right" position = [85, 238] size = [170, 100] label = "RB"}
	{kind = "button" control = "NORTH" shape = "circle" anchor = "top_right" position = [312, 287] size = [146, 146] label = "Y"}
	{kind = "button" control = "WEST" shape = "circle" anchor = "top_right" position = [457, 431] size = [146, 146] label = "X"}
	{kind = "button" control = "EAST" shape = "circle" anchor = "top_right" position = [172, 431] size = [146, 146] label = "B" double_tap_toggles = true}
	{kind = "button" control = "SOUTH" shape = "circle" anchor = "top_right" position = [312, 575] size = [146, 146] label = "A"}
	{kind = "button" control = "LEFT_STICK" shape = "circle" anchor = "bottom_left" position = [121, 290] size = [120, 120] label = "L3"}
	{kind = "button" control = "BACK" shape = "rectangle" anchor = "top_center" position = [-99, 60] size = [163, 79] label = "Back"}
	{kind = "button" control = "START" shape = "rectangle" anchor = "top_center" position = [92, 60] size = [163, 79] label = "Start"}
	{kind = "stick" side = "left" radius = 130 sprint_rim = 1.25}
	{kind = "look" side = "right" sensitivity = 1.0 hold_control = "RIGHT_TRIGGER" tap_interact_control = "SOUTH" tap_place_control = "LEFT_TRIGGER"}
]`

gamenative_touch_layout :: proc(allocator := context.temp_allocator) -> Touch_Overlay_Layout {
	layout, problem := parse_touch_overlay_file(transmute([]byte)string(GAMENATIVE_TOUCH_LAYOUT), "gamenative.sjson", allocator)
	assert(problem == "", problem)
	return layout
}

button_touch_overlay :: proc(t: ^testing.T) -> Touch_Overlay_Layout {
	return gamenative_touch_layout()
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

// 0115's scheme, where the look half is the look drag from the start; a
// 60 Hz frame with a tick in the one before.
// The sneak setting at its default, Hold, so double taps latch.
CROSSHAIR_TOUCH :: Touch_Interaction_Frame{interaction = .Crosshair, frame_seconds = 1.0 / 60, ticked = true, double_tap_latches = true}
TAP_TOUCH :: Touch_Interaction_Frame{interaction = .Tap, frame_seconds = 1.0 / 60, ticked = true, double_tap_latches = true}

// One frame of fingers, the output as the backends read it.
touch_frame :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, points: []Touch_Point, world_shown := true, screen := PHONE_SCREEN, inputs := CROSSHAIR_TOUCH) -> Touch_Overlay_Output {
	placed := overlay_layout(layout, screen, context.temp_allocator)
	update_touch_overlay(state, points, layout, placed, screen, world_shown, inputs)
	return touch_overlay_output(state^, layout, screen, world_shown)
}

// Default has the stick, the look and one button, B (0134, 0227).
@(test)
test_shipped_touch_overlay_loads :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	testing.expect_value(t, layout.reference_height, 1080)
	testing.expect_value(t, len(layout.elements), 3)
	testing.expect_value(t, len(overlay_layout(layout, PHONE_SCREEN, context.temp_allocator)), 1)
	b := layout.elements[2]
	testing.expect_value(t, b.label, "B")
	testing.expect_value(t, b.kind, Touch_Overlay_Kind.Button)
	testing.expect_value(t, b.control, Touch_Overlay_Control{button = .EAST})
	testing.expect_value(t, b.shape, Touch_Overlay_Shape.Circle)
	testing.expect_value(t, b.anchor, Touch_Overlay_Anchor.Bottom_Right)
	testing.expect_value(t, b.position, [2]f32{60, 320})
	testing.expect_value(t, b.size, [2]f32{100, 100})
	testing.expect(t, b.double_tap_toggles)
	stick := layout.elements[zone_element(layout, .Stick, .Left)]
	testing.expect_value(t, stick.radius, 130)
	testing.expect_value(t, stick.sprint_rim, 1.25)
	look := zone_element(layout, .Look, .Right)
	testing.expect(t, look >= 0)
	testing.expect_value(t, layout.elements[look].jump_zone_share, 0.2)
}

@(test)
test_overlay_layout_scales_and_anchors_at_two_screen_sizes :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
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
	layout := button_touch_overlay(t)
	placed := overlay_layout(layout, PHONE_SCREEN, context.temp_allocator)
	testing.expect_value(t, layout.elements[button_at(placed, {2112, 575})].label, "A")
	testing.expect_value(t, button_at(placed, {1600, 850}), -1)
}

@(test)
test_touch_on_a_button_latches_it_until_the_finger_lifts :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
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
	layout := button_touch_overlay(t)
	state: Touch_Overlay_State
	touch_frame(&state, layout, {{id = 0, position = {500, 700}}, {id = 1, position = {1600, 850}}, {id = 2, position = {2252, 431}}})
	output := touch_frame(&state, layout, {{id = 0, position = {500, 570}}, {id = 1, position = {1620, 850}}, {id = 2, position = {2252, 431}}})
	expect_near(t, output.stick, {0, -1})
	expect_near(t, output.look_delta, {20, 0})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.EAST)])
	// A second finger on the left half while the stick is held is
	// undecided, then its drag turns the view (0134).
	output = touch_frame(&state, layout, {{id = 0, position = {500, 570}}, {id = 3, position = {800, 800}}})
	expect_near(t, output.stick, {0, -1})
	testing.expect_value(t, slot_by_id(state, 3).role, Touch_Role.Pending)
	output = touch_frame(&state, layout, {{id = 0, position = {500, 570}}, {id = 3, position = {830, 800}}})
	testing.expect_value(t, slot_by_id(state, 3).role, Touch_Role.Look)
	expect_near(t, output.look_delta, {30, 0})
	expect_near(t, output.stick, {0, -1})
	// The stick's finger lifts; the other stays the look drag.
	output = touch_frame(&state, layout, {{id = 3, position = {850, 800}}})
	expect_near(t, output.look_delta, {20, 0})
	testing.expect_value(t, output.stick, [2]f32{})
}

@(test)
test_with_a_screen_open_only_start_and_back_read_and_are_drawn :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
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
	layout := button_touch_overlay(t)
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
		{`reference_height = 1080 elements = [{kind = "stick" side = "left" radius = 130 sprint_rim = 1.25} {kind = "look" side = "left" sensitivity = 1 hold_control = "RIGHT_TRIGGER" tap_interact_control = "SOUTH" tap_place_control = "LEFT_TRIGGER"}]`, "the stick and the look are on the same side"},
		{`reference_height = 1080 elements = [{kind = "look" side = "right" sensitivity = 1 hold_control = "MINE" tap_interact_control = "SOUTH" tap_place_control = "LEFT_TRIGGER"}]`, `elements[0] (look): unknown hold_control "MINE"`},
		{`reference_height = 1080 elements = [{kind = "look" side = "right" sensitivity = 1 hold_control = "RIGHT_TRIGGER" tap_interact_control = "SOUTH"}]`, `elements[0] (look): unknown tap_place_control ""`},
		{`reference_height = 1080 elements = [{kind = "look" side = "right" sensitivity = 1 colour = "red"}]`, "unknown key elements[0].colour"},
		{`reference_height = 1080 elements = [{kind = "look" side = "right" sensitivity = 1 hold_control = "RIGHT_TRIGGER" tap_interact_control = "SOUTH" tap_place_control = "LEFT_TRIGGER" jump_zone_share = 1}]`, "elements[0] (look): the jump_zone_share must be from 0 to below 1"},
		{`reference_height = 0 elements = []`, "reference_height must be positive"},
		{`reference_height = 1080 elements = []`, `unknown hotbar_drop_control ""`},
		{`reference_height = 1080 hotbar_drop_control = "DROP" elements = []`, `unknown hotbar_drop_control "DROP"`},
		{`reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [{kind = "stick" side = "left" radius = 130 sprint_rim = 1.25 position = [300, 300]}]`, "elements[0] (stick): a floating stick takes no anchor or position"},
		{`reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [{kind = "stick" side = "left" radius = 130 sprint_rim = 1.25 static = true}]`, "elements[0] (stick): a static stick needs an anchor and a position"},
		{`reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [{kind = "stick" side = "left" radius = 130 sprint_rim = 1.25 static = true position = [300, 300]}]`, `elements[0] (stick): unknown anchor ""`},
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
	touch_frame(&state, layout, {{id = 0, position = {600, 600}}})
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

// The overlay's buttons and the HUD's touch buttons (0134) in UI units
// at ui scale 1, as the HUD lays out. The shipped layout, Default, only: a
// user layout (0121) may cover the hotbar.
@(test)
test_no_touch_overlay_element_covers_a_hotbar_slot :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	for screen in ([?][2]f32{PHONE_SCREEN, {1280, 720}}) {
		ui: Ui_State
		ui.pixels_per_unit = ui_pixels_per_unit(screen.y, 1)
		ui.screen_units = ui_screen_units(screen, ui.pixels_per_unit)
		for selected in 0 ..< HOTBAR_SLOT_COUNT {
			for slot in hud_hotbar_rectangles(ui_safe_area(&ui), selected) {
				slot_pixels := units_to_pixels_rectangle(slot, ui.pixels_per_unit)
				for placed in overlay_layout(layout, screen, context.temp_allocator) {
					corner := placed.centre - placed.size / 2
					element := Ui_Rectangle{corner.x, corner.y, placed.size.x, placed.size.y}
					testing.expectf(t, !rectangles_overlap(element, slot_pixels), "%v at %v covers a hotbar slot at %v", layout.elements[placed.element].label, screen, slot_pixels)
				}
				for button, kind in hud_touch_button_rectangles(ui_safe_area(&ui)) {
					testing.expectf(t, !rectangles_overlap(button, slot), "the %v touch button at %v covers a hotbar slot at %v", kind, screen, slot)
					testing.expectf(t, rectangle_contains(ui_safe_area(&ui), {button.x + button.width, button.y}), "the %v touch button at %v leaves the safe area", kind, screen)
				}
			}
		}
	}
	// The placement editor's grid (0215) at every audited size: clear of
	// the hotbar, the row and each other, wholly in the safe area.
	for size in UI_AUDIT_SIZES {
		ui: Ui_State
		ui.pixels_per_unit = ui_pixels_per_unit(size.pixels.y, size.scale)
		ui.screen_units = ui_screen_units(size.pixels, ui.pixels_per_unit)
		safe := ui_safe_area(&ui)
		rectangles := hud_touch_button_rectangles(safe)
		for button in Hud_Touch_Button {
			if button in HUD_TOUCH_ROW_BUTTONS {
				continue
			}
			rectangle := rectangles[button]
			testing.expectf(t, rectangle_inside(rectangle, safe, 0), "the %v touch button at %v leaves the safe area: %v", button, size, rectangle)
			for selected in 0 ..< HOTBAR_SLOT_COUNT {
				for slot in hud_hotbar_rectangles(safe, selected) {
					testing.expectf(t, !rectangles_overlap(rectangle, slot), "the %v touch button at %v covers a hotbar slot", button, size)
				}
			}
			for other in Hud_Touch_Button {
				if other != button {
					testing.expectf(t, !rectangles_overlap(rectangle, rectangles[other]), "the %v touch button at %v covers the %v one", button, size, other)
				}
			}
		}
	}
}

// Default's buttons (0227) clear the hotbar, the HUD's row and the
// placement editor's grid at every audited size and on the phone at the
// UI scale range's ends, since a layout button takes a finger before a
// HUD button.
@(test)
test_no_touch_overlay_element_covers_a_hud_touch_button :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	sizes := make([dynamic]Ui_Audit_Size, context.temp_allocator)
	audit_sizes := UI_AUDIT_SIZES
	append(&sizes, ..audit_sizes[:])
	append(&sizes, Ui_Audit_Size{PHONE_SCREEN, UI_SCALE_RANGE.minimum}, Ui_Audit_Size{PHONE_SCREEN, 1}, Ui_Audit_Size{PHONE_SCREEN, UI_SCALE_RANGE.maximum}, Ui_Audit_Size{{1280, 720}, 1})
	for size in sizes {
		ui: Ui_State
		ui.pixels_per_unit = ui_pixels_per_unit(size.pixels.y, size.scale)
		ui.screen_units = ui_screen_units(size.pixels, ui.pixels_per_unit)
		safe := ui_safe_area(&ui)
		placed := overlay_layout(layout, size.pixels, context.temp_allocator)
		testing.expectf(t, len(placed) > 0, "no button placed at %v", size)
		for element_placed in placed {
			label := layout.elements[element_placed.element].label
			element := pixels_to_units_rectangle(element_placed.centre, element_placed.size, ui.pixels_per_unit)
			for rectangle, button in hud_touch_button_rectangles(safe) {
				testing.expectf(t, !rectangles_overlap(element, rectangle), "%v at %v covers the %v touch button at %v", label, size, button, rectangle)
			}
			for selected in 0 ..< HOTBAR_SLOT_COUNT {
				for slot in hud_hotbar_rectangles(safe, selected) {
					testing.expectf(t, !rectangles_overlap(element, slot), "%v at %v covers a hotbar slot at %v", label, size, slot)
				}
			}
			testing.expectf(t, rectangle_inside(element, {0, 0, ui.screen_units.x, ui.screen_units.y}, 0), "%v at %v leaves the screen: %v", label, size, element)
		}
	}
}

@(test)
test_a_touch_the_overlay_claims_is_no_pointer_click :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
	state: Touch_Overlay_State
	pressed_mouse: Raw_Mouse
	pressed_mouse.position = {1304, 60}
	pressed_mouse.button_down[int(rl.MouseButton.LEFT)] = true
	// A Start tap over a screen: the pill reads, the mouse button does not.
	frame := touch_overlay_frame(&state, layout, {{id = 7, position = {1304, 60}}}, PHONE_SCREEN, false, CROSSHAIR_TOUCH)
	testing.expect(t, frame.output.buttons[int(sdl.GamepadButton.START)])
	testing.expect(t, frame.pointer_claimed)
	mouse := touch_overlay_mouse(pressed_mouse, frame)
	testing.expect(t, !mouse.button_down[int(rl.MouseButton.LEFT)])
	expect_near(t, mouse.position, {1304, 60})
	// Still claimed while the finger stays down.
	frame = touch_overlay_frame(&state, layout, {{id = 7, position = {1320, 400}}}, PHONE_SCREEN, false, CROSSHAIR_TOUCH)
	testing.expect(t, frame.pointer_claimed)
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, false, CROSSHAIR_TOUCH)
	// A plain pointer tap elsewhere over the screen keeps the button down.
	frame = touch_overlay_frame(&state, layout, {{id = 8, position = {900, 500}}}, PHONE_SCREEN, false, CROSSHAIR_TOUCH)
	testing.expect(t, !frame.pointer_claimed)
	testing.expect(t, touch_overlay_mouse(pressed_mouse, frame).button_down[int(rl.MouseButton.LEFT)])
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, false, CROSSHAIR_TOUCH)
	// In the world a button claims it too, the stick does not.
	frame = touch_overlay_frame(&state, layout, {{id = 9, position = {2112, 575}}}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	testing.expect(t, frame.pointer_claimed)
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	frame = touch_overlay_frame(&state, layout, {{id = 10, position = {600, 700}}}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	testing.expect(t, !frame.pointer_claimed)
	// Only the first touch holds the mouse button: a second finger on
	// Start leaves a pointer finger's click alone.
	frame = touch_overlay_frame(&state, layout, {{id = 10, position = {600, 700}}, {id = 11, position = {1304, 60}}}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	testing.expect(t, !frame.pointer_claimed)
	// The overlay off: nothing claimed.
	testing.expect(t, touch_overlay_mouse(pressed_mouse, {}).button_down[int(rl.MouseButton.LEFT)])
}

// The tap scheme (0118). A free spot on the look half.
TAP_POINT :: [2]f32{1600, 850}

@(test)
test_a_resting_touch_becomes_a_hold_that_mines_at_the_point :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := TAP_TOUCH
	inputs.frame_seconds = 0.1
	// Undecided while it rests less than TOUCH_HOLD_SECONDS, also when it
	// wobbles inside the slop.
	for position in ([?][2]f32{TAP_POINT, TAP_POINT + {5, 0}, TAP_POINT + {0, 6}}) {
		output := touch_frame(&state, layout, {{id = 0, position = position}}, inputs = inputs)
		testing.expect_value(t, output, Touch_Overlay_Output{})
	}
	output := touch_frame(&state, layout, {{id = 0, position = TAP_POINT + {0, 6}}}, inputs = inputs)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hold)
	testing.expect(t, output.triggers[.Right])
	testing.expect(t, output.aims)
	expect_near(t, output.aim_point, TAP_POINT + {0, 6})
	testing.expect_value(t, output.look_delta, [2]f32{})
	// Mine through the bindings, and the aim follows the finger.
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Raylib, context.temp_allocator)
	testing.expect(t, .Mine in gamepad_button_actions(touch_overlay_raw_gamepad(output, .Raylib), tables))
	output = touch_frame(&state, layout, {{id = 0, position = TAP_POINT + {80, 0}}}, inputs = inputs)
	testing.expect(t, output.triggers[.Right])
	expect_near(t, output.aim_point, TAP_POINT + {80, 0})
	// A hold's lift is no tap.
	output = touch_frame(&state, layout, {}, inputs = inputs)
	testing.expect_value(t, output, Touch_Overlay_Output{})
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
}

@(test)
test_a_touch_that_moves_before_the_hold_is_the_look_drag :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = TAP_TOUCH)
	// Past the slop (12 pixels at 1080 high): the drag so far turns the view.
	output := touch_frame(&state, layout, {{id = 0, position = TAP_POINT + {20, 0}}}, inputs = TAP_TOUCH)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Look)
	expect_near(t, output.look_delta, {20, 0})
	testing.expect(t, !output.aims)
	testing.expect_value(t, output.triggers, [Gamepad_Trigger]bool{})
	// Resting afterwards stays the look drag, and the lift taps nothing.
	for _ in 0 ..< 30 {
		output = touch_frame(&state, layout, {{id = 0, position = TAP_POINT + {20, 0}}}, inputs = TAP_TOUCH)
	}
	testing.expect_value(t, output, Touch_Overlay_Output{})
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect_value(t, output, Touch_Overlay_Output{})
	// On a 720 high screen the slop scales: 10 pixels is past it.
	small := [2]f32{1280, 720}
	touch_frame(&state, layout, {{id = 1, position = {1000, 500}}}, true, small, TAP_TOUCH)
	touch_frame(&state, layout, {{id = 1, position = {1010, 500}}}, true, small, TAP_TOUCH)
	testing.expect_value(t, slot_by_id(state, 1).role, Touch_Role.Look)
}

// The frames of a tap from its lift: the aim alone until a tick has run
// with it, then the control until a tick has run with the press.
@(test)
test_a_tap_presses_x_on_a_machine_and_place_elsewhere :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	for takes_interaction in ([?]bool{true, false}) {
		state: Touch_Overlay_State
		inputs := TAP_TOUCH
		inputs.target_takes_interaction = takes_interaction
		touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = inputs)
		output := touch_frame(&state, layout, {}, inputs = inputs)
		expected_aim: Touch_Overlay_Output
		expected_aim.aims, expected_aim.aim_point = true, TAP_POINT
		testing.expect_value(t, output, expected_aim)
		// No tick ran with the aim yet (a fast display): keep aiming.
		waiting := inputs
		waiting.ticked = false
		output = touch_frame(&state, layout, {}, inputs = waiting)
		testing.expect_value(t, output, expected_aim)
		output = touch_frame(&state, layout, {}, inputs = inputs)
		testing.expect(t, output.aims)
		expect_near(t, output.aim_point, TAP_POINT)
		testing.expect_value(t, output.buttons[int(sdl.GamepadButton.WEST)], takes_interaction)
		testing.expect_value(t, output.triggers[.Left], !takes_interaction)
		testing.expect(t, !output.triggers[.Right])
		// Held until a tick has run with the press, then gone.
		pressed := output
		output = touch_frame(&state, layout, {}, inputs = waiting)
		testing.expect_value(t, output, pressed)
		output = touch_frame(&state, layout, {}, inputs = inputs)
		testing.expect_value(t, output, Touch_Overlay_Output{})
		// Through the bindings: X (Interact and Open_Inventory, which the
		// frame routes), or Place.
		tables, _ := build_input_bindings(shipped_default_bindings(t), .Sdl3, context.temp_allocator)
		gamepad := touch_overlay_raw_gamepad(pressed, .Sdl3)
		actions := gamepad_button_actions(gamepad, tables) + gamepad_trigger_actions(gamepad, tables)
		testing.expect_value(t, .Interact in actions, takes_interaction)
		testing.expect_value(t, .Open_Inventory in actions, takes_interaction)
		testing.expect_value(t, .Place in actions, !takes_interaction)
	}
	// A screen opening drops a pending tap.
	state: Touch_Overlay_State
	touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = TAP_TOUCH)
	touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect_value(t, touch_frame(&state, layout, {}, false, inputs = TAP_TOUCH), Touch_Overlay_Output{})
	testing.expect_value(t, touch_frame(&state, layout, {}, inputs = TAP_TOUCH), Touch_Overlay_Output{})
}

// The crosshair scheme keeps the gestures and aims them at the view's
// centre (0134): the frame carries no aim.
@(test)
test_crosshair_mode_holds_and_taps_at_the_views_centre :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := CROSSHAIR_TOUCH
	inputs.frame_seconds = 0.1
	frame: Touch_Overlay_Frame
	for _ in 0 ..< 4 {
		frame = touch_overlay_frame(&state, layout, {{id = 0, position = TAP_POINT}}, PHONE_SCREEN, true, inputs)
	}
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hold)
	testing.expect(t, frame.output.triggers[.Right])
	testing.expect(t, !frame.output.aims)
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, true, inputs)
	// A tap places at the centre: the press without an aim.
	touch_overlay_frame(&state, layout, {{id = 1, position = TAP_POINT}}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	frame = touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	testing.expect(t, !frame.output.aims)
	frame = touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	testing.expect(t, frame.output.triggers[.Left])
	testing.expect(t, !frame.output.aims)
	// The drag still turns the view.
	touch_overlay_frame(&state, layout, {}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	touch_overlay_frame(&state, layout, {{id = 2, position = TAP_POINT}}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	frame = touch_overlay_frame(&state, layout, {{id = 2, position = TAP_POINT + {30, 0}}}, PHONE_SCREEN, true, CROSSHAIR_TOUCH)
	expect_near(t, frame.output.look_delta, {30, 0})
}

@(test)
test_the_touch_aim_reaches_the_input_frame_while_the_overlay_drives_the_world :: proc(t: ^testing.T) {
	overlay := Touch_Overlay_Frame{active = true, world_shown = true, aim_direction = {0, -1, 0}}
	overlay.output.aims = true
	frame := apply_touch_overlay_aim({move = {0, 1}}, overlay)
	testing.expect(t, frame.aim_overrides)
	testing.expect_value(t, frame.aim_direction, [3]f32{0, -1, 0})
	testing.expect_value(t, frame.move, [2]f32{0, 1})
	overlay.world_shown = false
	testing.expect(t, !apply_touch_overlay_aim({}, overlay).aim_overrides)
	overlay.world_shown, overlay.output.aims = true, false
	testing.expect(t, !apply_touch_overlay_aim({}, overlay).aim_overrides)
}

// The player's target follows the aim instead of the view, and the tap's
// predicate agrees with what Interact acts on.
@(test)
test_the_touch_aim_picks_the_players_target :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "power_switch"), {4, 1, 4}, 0)
	players := []Player{make_test_player(content.blocks, {4.5, 1, 1.5})}
	// Looking up at the sky: no target.
	players[0].pitch, players[0].yaw = 60, 90
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect(t, !players[0].target.hit)
	// Aimed at the chest.
	eye := player_eye(players[0].position)
	aimed := Input_Frame{aim_direction = linalg.normalize(block_centre({4, 1, 4}) - eye), aim_overrides = true}
	tick_player(&world, &records, content, players, 0, aimed, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].target.entity, handle)
	testing.expect(t, entity_takes_interact(&world.entities, content.machines, players[0].target.entity))
	// The press that follows turns it.
	players[0].on_ground = true
	aimed.pressed, aimed.just_pressed = {.Jump, .Interact}, {.Jump, .Interact}
	events := tick_player(&world, &records, content, players, 0, aimed, TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{.Toggled_Switch})
	// Aimed at the floor: a block, no interaction.
	floor := Input_Frame{aim_direction = linalg.normalize(block_centre({4, 0, 2}) - eye), aim_overrides = true}
	tick_player(&world, &records, content, players, 0, floor, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].target.block, World_Coordinate{4, 0, 2})
	testing.expect(t, !entity_takes_interact(&world.entities, content.machines, players[0].target.entity))
}

// A tap aims then presses: land, lift, the frames of the aim.
tap_at :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, id: i32, point: [2]f32, inputs: Touch_Interaction_Frame) -> Touch_Overlay_Output {
	touch_frame(state, layout, {{id = id, position = point}}, inputs = inputs)
	return touch_frame(state, layout, {}, inputs = inputs)
}

@(test)
test_a_second_tap_while_one_is_in_flight_is_ignored :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	waiting := TAP_TOUCH
	waiting.ticked = false
	tap_at(&state, layout, 0, TAP_POINT, waiting)
	second := TAP_POINT + {200, -100}
	output := tap_at(&state, layout, 1, second, waiting)
	expect_near(t, output.aim_point, TAP_POINT)
	// The press goes to the first tap's point, and nothing follows it.
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect(t, output.triggers[.Left])
	expect_near(t, output.aim_point, TAP_POINT)
	touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
	// While it presses a lift is ignored too.
	tap_at(&state, layout, 2, TAP_POINT, TAP_TOUCH)
	touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.Pressing)
	tap_at(&state, layout, 3, second, waiting)
	expect_near(t, state.tap.point, TAP_POINT)
}

@(test)
test_a_tap_while_a_finger_holds_leaves_the_hold_alone :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := TAP_TOUCH
	inputs.frame_seconds = 0.1
	for _ in 0 ..< 4 {
		touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = inputs)
	}
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hold)
	other := TAP_POINT + {300, -200}
	touch_frame(&state, layout, {{id = 0, position = TAP_POINT}, {id = 1, position = other}}, inputs = inputs)
	output := touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = inputs)
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
	testing.expect(t, output.triggers[.Right])
	testing.expect(t, !output.triggers[.Left])
	expect_near(t, output.aim_point, TAP_POINT)
}

@(test)
test_a_hold_that_begins_while_a_tap_is_in_flight_drops_the_tap :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	waiting := TAP_TOUCH
	waiting.frame_seconds = 0.1
	waiting.ticked = false
	other := TAP_POINT + {300, -200}
	// Finger 0 rests; finger 1 taps while it does, so the tap waits for a
	// tick when finger 0 turns into a hold.
	touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = waiting)
	touch_frame(&state, layout, {{id = 0, position = TAP_POINT}, {id = 1, position = other}}, inputs = waiting)
	touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = waiting)
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.Aiming)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Pending)
	output := touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = waiting)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hold)
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
	testing.expect(t, output.triggers[.Right])
	testing.expect(t, !output.triggers[.Left])
	expect_near(t, output.aim_point, TAP_POINT)
}

@(test)
test_a_tap_waiting_too_long_for_a_tick_is_dropped :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	waiting := TAP_TOUCH
	waiting.ticked = false
	tap_at(&state, layout, 0, TAP_POINT, waiting)
	// A developer pause: frames run, ticks do not. Under TOUCH_HOLD_SECONDS
	// it still aims.
	for _ in 0 ..< 14 {
		testing.expect(t, touch_frame(&state, layout, {}, inputs = waiting).aims)
	}
	for _ in 0 ..< 2 {
		touch_frame(&state, layout, {}, inputs = waiting)
	}
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
	// The pause ends: nothing fires late.
	testing.expect_value(t, touch_frame(&state, layout, {}, inputs = TAP_TOUCH), Touch_Overlay_Output{})
}

// The look element's controls come from the layout file.
@(test)
test_the_tap_and_hold_controls_come_from_the_layout :: proc(t: ^testing.T) {
	shipped := shipped_touch_overlay(t)
	look := zone_element(shipped, .Look, .Right)
	testing.expect_value(t, shipped.elements[look].hold_control, Touch_Overlay_Control{is_trigger = true, trigger = .Right})
	testing.expect_value(t, shipped.elements[look].tap_open_control, Touch_Overlay_Control{button = .WEST})
	testing.expect_value(t, shipped.elements[look].tap_place_control, Touch_Overlay_Control{is_trigger = true, trigger = .Left})
	elements := make([]Touch_Overlay_Element, len(shipped.elements), context.temp_allocator)
	copy(elements, shipped.elements)
	elements[look].hold_control = {button = .WEST}
	elements[look].tap_place_control = {button = .NORTH}
	layout := Touch_Overlay_Layout{reference_height = shipped.reference_height, elements = elements}
	state: Touch_Overlay_State
	inputs := TAP_TOUCH
	inputs.frame_seconds = 0.1
	output: Touch_Overlay_Output
	for _ in 0 ..< 4 {
		output = touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs = inputs)
	}
	testing.expect(t, output.buttons[int(sdl.GamepadButton.WEST)])
	testing.expect(t, !output.triggers[.Right])
	touch_frame(&state, layout, {}, inputs = inputs)
	tap_at(&state, layout, 1, TAP_POINT, TAP_TOUCH)
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect(t, output.buttons[int(sdl.GamepadButton.NORTH)])
	testing.expect(t, !output.triggers[.Left])
}

// In third person the camera sits behind and beside the eye; the aim is
// the direction from the eye to the block the camera ray hits.
@(test)
test_the_third_person_aim_points_from_the_eye_at_the_camera_rays_block :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	eye := player_eye({0.5, 1, 0.5})
	camera := eye + {-3, 1, 0.6}
	face_point := [3]f32{3.5, 1, 0.5}
	ray_direction := linalg.normalize(face_point - camera)
	testing.expect_value(t, raycast_blocks(&world, content.blocks, camera, ray_direction, 10).block, World_Coordinate{3, 0, 0})
	direction := eye_aim_direction(&world, content.blocks, eye, camera, ray_direction)
	from_eye := raycast_blocks(&world, content.blocks, eye, direction, PLAYER_REACH)
	testing.expect(t, from_eye.hit)
	testing.expect_value(t, from_eye.block, World_Coordinate{3, 0, 0})
	// The camera ray's own direction cast from the eye lands elsewhere.
	testing.expect(t, raycast_blocks(&world, content.blocks, eye, ray_direction, PLAYER_REACH).block != World_Coordinate{3, 0, 0})
	// In first person the camera is the eye: the direction is the ray's.
	first_person_error := linalg.length(eye_aim_direction(&world, content.blocks, eye, eye, ray_direction) - ray_direction)
	testing.expect(t, first_person_error < 0.001)
	// Nothing hit: towards the far end of the ray.
	up := linalg.normalize([3]f32{0.2, 1, 0})
	testing.expect(t, linalg.length(eye_aim_direction(&world, content.blocks, eye, eye, up) - up) < 0.001)
}

// Player.target_direction exists for this: a slab placed on a side face
// takes its half from where the aim hit, not from the look direction.
@(test)
test_a_touch_aimed_slab_takes_its_half_from_the_aim :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	set_blocks(&world, test_block(content.blocks, "stone"), {3, 2, 0})
	players := []Player{make_test_player(content.blocks, {0.5, 1, 0.5})}
	players[0].inventory.slots[0] = Item_Stack{item = test_item(content.items, "stone_slab"), count = 4}
	// The view looks down at the floor, where a slab would go low.
	players[0].pitch = -60
	eye := player_eye(players[0].position)
	aimed := Input_Frame{aim_direction = linalg.normalize([3]f32{3, 2.8, 0.5} - eye), aim_overrides = true, pressed = {.Place}, just_pressed = {.Place}}
	tick_player(&world, &records, content, players, 0, aimed, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].target.face, Direction.Negative_X)
	testing.expect_value(t, world_get_block(&world, {2, 2, 0}), test_block(content.blocks, "stone_slab_upper"))
}

// The hotbar (0119): the phone's slots as the HUD draws them at UI scale
// 1, in the tap scheme, with the given slot selected.
phone_hotbar_inputs :: proc(selected: int) -> Touch_Interaction_Frame {
	ui: Ui_State
	ui.pixels_per_unit = ui_pixels_per_unit(PHONE_SCREEN.y, 1)
	ui.screen_units = ui_screen_units(PHONE_SCREEN, ui.pixels_per_unit)
	inputs := TAP_TOUCH
	inputs.hotbar_slots = hud_hotbar_pixel_rectangles(&ui, selected)
	inputs.selected_hotbar_slot = selected
	return inputs
}

hotbar_frame :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, points: []Touch_Point, inputs: Touch_Interaction_Frame, world_shown := true) -> Touch_Overlay_Frame {
	return touch_overlay_frame(state, layout, points, PHONE_SCREEN, world_shown, inputs)
}

@(test)
test_a_tap_on_a_hotbar_slot_selects_it_once_and_claims_the_pointer :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := phone_hotbar_inputs(0)
	slot_point := rectangle_centre(inputs.hotbar_slots[2])
	frame := hotbar_frame(&state, layout, {{id = 3, position = slot_point}}, inputs)
	testing.expect_value(t, slot_by_id(state, 3).role, Touch_Role.Hotbar)
	testing.expect(t, frame.pointer_claimed)
	testing.expect_value(t, frame.hotbar_tap, -1)
	testing.expect_value(t, frame.output, Touch_Overlay_Output{})
	frame = hotbar_frame(&state, layout, {}, inputs)
	testing.expect_value(t, frame.hotbar_tap, 2)
	testing.expect_value(t, frame.output, Touch_Overlay_Output{})
	input := apply_touch_overlay_hotbar({}, frame)
	testing.expect_value(t, input.just_pressed, Action_Set{.Hotbar_Slot_3})
	frame = hotbar_frame(&state, layout, {}, inputs)
	testing.expect_value(t, frame.hotbar_tap, -1)
	testing.expect_value(t, apply_touch_overlay_hotbar({}, frame).just_pressed, Action_Set{})
	// The simulation selects the slot from the edge.
	testing.expect_value(t, cycle_hotbar_slot(0, input.just_pressed), 2)
}

@(test)
test_a_long_press_on_the_selected_slot_drops_its_stack :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := phone_hotbar_inputs(5)
	inputs.frame_seconds = 0.1
	points := []Touch_Point{{id = 0, position = rectangle_centre(inputs.hotbar_slots[5])}}
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Raylib, context.temp_allocator)
	// hotbar_drop_control (d-pad down) is held from the long press until
	// the lift: one Drop_Stack edge through the bindings.
	previous: Action_Set
	edges := 0
	for step in 0 ..< 10 {
		frame := hotbar_frame(&state, layout, points, inputs)
		testing.expect_value(t, frame.hotbar_tap, -1)
		testing.expect_value(t, frame.output.buttons[int(sdl.GamepadButton.DPAD_DOWN)], step >= 3)
		actions := gamepad_button_actions(touch_overlay_raw_gamepad(frame.output, .Raylib), tables)
		if .Drop_Stack in actions_just_pressed(previous, actions) {
			edges += 1
		}
		previous = actions
		testing.expect_value(t, apply_touch_overlay_hotbar({}, frame).just_pressed, Action_Set{})
	}
	testing.expect_value(t, edges, 1)
	// The lift after a long press is no tap and releases the control.
	frame := hotbar_frame(&state, layout, {}, inputs)
	testing.expect_value(t, frame.hotbar_tap, -1)
	testing.expect_value(t, frame.output, Touch_Overlay_Output{})
}

@(test)
test_a_finger_that_slides_off_the_selected_slot_fires_nothing :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	inputs := phone_hotbar_inputs(5)
	inputs.frame_seconds = 0.1
	origin := rectangle_centre(inputs.hotbar_slots[5])
	// Slid a little or far away and held there past the long press time,
	// then lifted: neither the drop nor a tap.
	for path in ([?][]Touch_Point{{{id = 0, position = origin + {0, -40}}}, {{id = 0, position = origin + {-300, -200}}}}) {
		state: Touch_Overlay_State
		frame := hotbar_frame(&state, layout, {{id = 0, position = origin}}, inputs)
		for _ in 0 ..< 10 {
			frame = hotbar_frame(&state, layout, path, inputs)
			testing.expect_value(t, frame.hotbar_tap, -1)
			testing.expect_value(t, frame.output, Touch_Overlay_Output{})
			testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hotbar)
			testing.expect(t, frame.pointer_claimed)
		}
		testing.expect_value(t, hotbar_frame(&state, layout, {}, inputs).hotbar_tap, -1)
	}
	// A quick flick, lifted before the long press time: no tap.
	state: Touch_Overlay_State
	hotbar_frame(&state, layout, {{id = 0, position = origin}}, inputs)
	hotbar_frame(&state, layout, {{id = 0, position = origin + {200, -100}}}, inputs)
	testing.expect_value(t, hotbar_frame(&state, layout, {}, inputs).hotbar_tap, -1)
}

@(test)
test_a_long_press_on_another_slot_only_selects_it :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := phone_hotbar_inputs(0)
	inputs.frame_seconds = 0.1
	points := []Touch_Point{{id = 0, position = rectangle_centre(inputs.hotbar_slots[6])}}
	taps: [dynamic]int
	taps.allocator = context.temp_allocator
	for _ in 0 ..< 10 {
		frame := hotbar_frame(&state, layout, points, inputs)
		testing.expect_value(t, frame.output, Touch_Overlay_Output{})
		if frame.hotbar_tap >= 0 {
			append(&taps, frame.hotbar_tap)
		}
	}
	frame := hotbar_frame(&state, layout, {}, inputs)
	testing.expect_value(t, frame.hotbar_tap, -1)
	testing.expect_value(t, len(taps), 1)
	testing.expect_value(t, taps[0], 6)
}

@(test)
test_a_hotbar_tap_leaves_a_held_stick_alone :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := phone_hotbar_inputs(0)
	stick_origin := [2]f32{400, 600}
	hotbar_frame(&state, layout, {{id = 0, position = stick_origin}}, inputs)
	stick_points := []Touch_Point{{id = 0, position = stick_origin + {60, 0}}}
	before := hotbar_frame(&state, layout, stick_points, inputs)
	// Slot 0 lies on the stick's half: the hotbar comes first.
	slot_point := rectangle_centre(inputs.hotbar_slots[0])
	testing.expect_value(t, screen_side(slot_point, PHONE_SCREEN), Touch_Overlay_Side.Left)
	during := hotbar_frame(&state, layout, {stick_points[0], {id = 1, position = slot_point}}, inputs)
	testing.expect_value(t, slot_by_id(state, 1).role, Touch_Role.Hotbar)
	testing.expect_value(t, during.output, before.output)
	// The stick finger is the pointer's touch (points[0]), so nothing claims it.
	testing.expect(t, !during.pointer_claimed)
	after := hotbar_frame(&state, layout, stick_points, inputs)
	testing.expect_value(t, after.hotbar_tap, 0)
	testing.expect_value(t, after.output, before.output)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Stick)
}

@(test)
test_over_a_screen_a_hotbar_touch_is_the_pointers :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := phone_hotbar_inputs(0)
	slot_point := rectangle_centre(inputs.hotbar_slots[3])
	frame := hotbar_frame(&state, layout, {{id = 0, position = slot_point}}, inputs, false)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Ignored)
	testing.expect(t, !frame.pointer_claimed)
	testing.expect_value(t, hotbar_frame(&state, layout, {}, inputs, false).hotbar_tap, -1)
	// And a frame from a screen presses no action even if it carried one.
	frame.hotbar_tap = 3
	testing.expect_value(t, apply_touch_overlay_hotbar({}, frame).just_pressed, Action_Set{})
}

// A static stick at the bottom left, its base centred at 300, 780 on the
// phone, and the look on the right.
STATIC_STICK_LAYOUT :: `reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [
	{kind = "stick" static = true anchor = "bottom_left" position = [300, 300] side = "left" radius = 130 sprint_rim = 1.25}
	{kind = "look" side = "right" sensitivity = 1 hold_control = "RIGHT_TRIGGER" tap_interact_control = "SOUTH" tap_place_control = "LEFT_TRIGGER"}
]`

@(test)
test_a_static_stick_reads_a_touch_inside_its_base_and_ignores_one_outside :: proc(t: ^testing.T) {
	layout, problem := parse_touch_overlay_file(transmute([]byte)string(STATIC_STICK_LAYOUT), "static.sjson", context.temp_allocator)
	testing.expect_value(t, problem, "")
	state: Touch_Overlay_State
	// Inside the base, off its centre: the drag counts from the centre.
	output := touch_frame(&state, layout, {{id = 0, position = {330, 780}}})
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Stick)
	expect_near(t, output.stick, {30.0 / 130, 0})
	output = touch_frame(&state, layout, {{id = 0, position = {300, 715}}})
	expect_near(t, output.stick, {0, -0.5})
	touch_frame(&state, layout, {})
	// Outside the base on its half is free screen (0134): a tap places
	// there, and a drag turns the view instead of moving the stick.
	outside := [2]f32{700, 400}
	output = tap_at(&state, layout, 1, outside, TAP_TOUCH)
	expect_near(t, output.aim_point, outside)
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect(t, output.triggers[.Left])
	touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	touch_frame(&state, layout, {{id = 2, position = outside}}, inputs = TAP_TOUCH)
	output = touch_frame(&state, layout, {{id = 2, position = outside + {60, 0}}}, inputs = TAP_TOUCH)
	testing.expect_value(t, slot_by_id(state, 2).role, Touch_Role.Look)
	testing.expect_value(t, output.stick, [2]f32{})
}

B_BUTTON_POINT :: [2]f32{2424 - 172, 431}
// Default's B (0227), its centre on PHONE_SCREEN.
DEFAULT_B_POINT :: [2]f32{2424 - 60, 1080 - 320}

// A tap on B: one frame down, one frame up.
tap_b :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, id: i32, inputs := CROSSHAIR_TOUCH, point := B_BUTTON_POINT) -> (while_down, after_lift: bool) {
	while_down = touch_frame(state, layout, {{id = id, position = point}}, inputs = inputs).buttons[int(sdl.GamepadButton.EAST)]
	after_lift = touch_frame(state, layout, {}, inputs = inputs).buttons[int(sdl.GamepadButton.EAST)]
	return
}

@(test)
test_a_double_tap_latches_b_and_the_next_tap_releases_it :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
	state: Touch_Overlay_State
	down, lifted := tap_b(&state, layout, 0)
	testing.expect(t, down && !lifted)
	down, lifted = tap_b(&state, layout, 1)
	testing.expect(t, down && lifted)
	// Latched well past the double tap time.
	for _ in 0 ..< 60 {
		testing.expect(t, touch_frame(&state, layout, {}).buttons[int(sdl.GamepadButton.EAST)])
	}
	// The next tap holds it while down and releases it on the lift.
	down, lifted = tap_b(&state, layout, 2)
	testing.expect(t, down && !lifted)
	// A quick tap after the release is a first tap again, not a latch.
	down, lifted = tap_b(&state, layout, 3)
	testing.expect(t, down && !lifted)
}

@(test)
test_single_taps_on_b_press_and_release :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
	state: Touch_Overlay_State
	for id in i32(0) ..< 3 {
		down, lifted := tap_b(&state, layout, id)
		testing.expect(t, down && !lifted)
		// Longer than TOUCH_DOUBLE_TAP_SECONDS apart: 20 frames at 60 Hz.
		for _ in 0 ..< 20 {
			touch_frame(&state, layout, {})
		}
	}
	// A double tap on A, which does not toggle, latches nothing.
	touch_frame(&state, layout, {{id = 5, position = {2112, 575}}})
	touch_frame(&state, layout, {})
	touch_frame(&state, layout, {{id = 6, position = {2112, 575}}})
	testing.expect_value(t, touch_frame(&state, layout, {}), Touch_Overlay_Output{})
}

@(test)
test_double_taps_latch_only_while_the_sneak_setting_is_hold :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
	toggle_sneak := CROSSHAIR_TOUCH
	toggle_sneak.double_tap_latches = false
	state: Touch_Overlay_State
	// In Toggle a double tap is two taps.
	down, lifted := tap_b(&state, layout, 0, toggle_sneak)
	testing.expect(t, down && !lifted)
	down, lifted = tap_b(&state, layout, 1, toggle_sneak)
	testing.expect(t, down && !lifted)
	// A latch made in Hold is released once the setting is Toggle.
	tap_b(&state, layout, 2)
	_, lifted = tap_b(&state, layout, 3)
	testing.expect(t, lifted)
	testing.expect_value(t, touch_frame(&state, layout, {}, inputs = toggle_sneak), Touch_Overlay_Output{})
	testing.expect_value(t, state.latched, bit_set[0 ..< TOUCH_OVERLAY_ELEMENT_CAPACITY]{})
}

// Default's B (0227) presses Sneak through EAST in the world and is
// neither read nor drawn over a screen.
@(test)
test_defaults_b_presses_sneak_in_the_world_and_nothing_over_a_screen :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Raylib, context.temp_allocator)
	east := int(sdl.GamepadButton.EAST)
	state: Touch_Overlay_State
	output := touch_frame(&state, layout, {{id = 0, position = DEFAULT_B_POINT}}, inputs = TAP_TOUCH)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Button)
	testing.expect(t, output.buttons[east])
	testing.expect(t, .Sneak in gamepad_button_actions(touch_overlay_raw_gamepad(output, .Raylib), tables))
	testing.expect(t, !output.aims)
	testing.expect(t, !output.jump_tap)
	frame := touch_overlay_frame(&state, layout, {{id = 0, position = DEFAULT_B_POINT}}, PHONE_SCREEN, true, TAP_TOUCH)
	testing.expect(t, frame.pointer_claimed)
	// The lift in the jump zone neither jumps nor places.
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect(t, !output.buttons[east])
	testing.expect(t, !output.jump_tap)
	testing.expect_value(t, output.triggers, [Gamepad_Trigger]bool{})
	// A drag starting on B does not look.
	dragged: Touch_Overlay_State
	touch_frame(&dragged, layout, {{id = 1, position = DEFAULT_B_POINT}}, inputs = TAP_TOUCH)
	output = touch_frame(&dragged, layout, {{id = 1, position = DEFAULT_B_POINT + {-60, 0}}}, inputs = TAP_TOUCH)
	testing.expect_value(t, output.look_delta, [2]f32{})
	// Over a screen the same finger presses nothing.
	screen_state: Touch_Overlay_State
	output = touch_frame(&screen_state, layout, {{id = 2, position = DEFAULT_B_POINT}}, false, inputs = TAP_TOUCH)
	testing.expect_value(t, output, Touch_Overlay_Output{})
	touch_frame(&screen_state, layout, {}, false, inputs = TAP_TOUCH)
	ui: Ui_State
	defer delete(ui.draw_list)
	ui.pixels_per_unit = ui_pixels_per_unit(PHONE_SCREEN.y, 1)
	draw_touch_overlay(&ui, screen_state, layout, PHONE_SCREEN, false)
	testing.expect_value(t, len(touch_overlay_drawn_labels(&ui)), 0)
	clear(&ui.draw_list)
	draw_touch_overlay(&ui, screen_state, layout, PHONE_SCREEN, true)
	labels := touch_overlay_drawn_labels(&ui)
	testing.expect_value(t, len(labels), 1)
	if len(labels) == 1 {
		testing.expect_value(t, labels[0], "B")
	}
}

// Default's B (0227) latches on a double tap in Hold and not in Toggle,
// as GameNative's B does in the tests above.
@(test)
test_defaults_b_latches_while_the_sneak_setting_is_hold :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	down, lifted := tap_b(&state, layout, 0, TAP_TOUCH, DEFAULT_B_POINT)
	testing.expect(t, down && !lifted)
	down, lifted = tap_b(&state, layout, 1, TAP_TOUCH, DEFAULT_B_POINT)
	testing.expect(t, down && lifted)
	for _ in 0 ..< 60 {
		testing.expect(t, touch_frame(&state, layout, {}, inputs = TAP_TOUCH).buttons[int(sdl.GamepadButton.EAST)])
	}
	// The next tap releases it on its lift.
	down, lifted = tap_b(&state, layout, 2, TAP_TOUCH, DEFAULT_B_POINT)
	testing.expect(t, down && !lifted)
	// In Toggle two quick taps each press and release.
	toggle_sneak := TAP_TOUCH
	toggle_sneak.double_tap_latches = false
	toggled: Touch_Overlay_State
	down, lifted = tap_b(&toggled, layout, 3, toggle_sneak, DEFAULT_B_POINT)
	testing.expect(t, down && !lifted)
	down, lifted = tap_b(&toggled, layout, 4, toggle_sneak, DEFAULT_B_POINT)
	testing.expect(t, down && !lifted)
	// A latch made in Hold is released by the first Toggle frame.
	latched: Touch_Overlay_State
	tap_b(&latched, layout, 5, TAP_TOUCH, DEFAULT_B_POINT)
	_, lifted = tap_b(&latched, layout, 6, TAP_TOUCH, DEFAULT_B_POINT)
	testing.expect(t, lifted)
	testing.expect_value(t, touch_frame(&latched, layout, {}, inputs = toggle_sneak), Touch_Overlay_Output{})
	testing.expect_value(t, latched.latched, bit_set[0 ..< TOUCH_OVERLAY_ELEMENT_CAPACITY]{})
}

@(test)
test_a_data_reload_releases_the_latches :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
	state: Touch_Overlay_State
	tap_b(&state, layout, 0)
	_, lifted := tap_b(&state, layout, 1)
	testing.expect(t, lifted)
	// The reloaded layout has a toggling button inserted before B, so B's
	// old index is now that button.
	b_index := button_at(overlay_layout(layout, PHONE_SCREEN, context.temp_allocator), B_BUTTON_POINT)
	inserted := Touch_Overlay_Element{kind = .Button, control = {button = .NORTH}, shape = .Circle, anchor = .Top_Left, position = {500, 500}, size = {50, 50}, label = "N", double_tap_toggles = true}
	elements := make([dynamic]Touch_Overlay_Element, context.temp_allocator)
	append(&elements, ..layout.elements[:b_index])
	append(&elements, inserted)
	append(&elements, ..layout.elements[b_index:])
	reloaded := Touch_Overlay_Layout{reference_height = layout.reference_height, hotbar_drop_control = layout.hotbar_drop_control, elements = elements[:]}
	state = release_touch_latches(state)
	testing.expect_value(t, touch_frame(&state, reloaded, {}), Touch_Overlay_Output{})
}

@(test)
test_a_long_press_on_b_then_a_quick_press_does_not_latch :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
	state: Touch_Overlay_State
	// Half a second down, longer than TOUCH_HOLD_SECONDS.
	for _ in 0 ..< 30 {
		touch_frame(&state, layout, {{id = 0, position = B_BUTTON_POINT}})
	}
	touch_frame(&state, layout, {})
	down, lifted := tap_b(&state, layout, 1)
	testing.expect(t, down && !lifted)
}

// User layouts (0121).

expect_same_touch_layout :: proc(t: ^testing.T, value, expected: Touch_Overlay_Layout, loc := #caller_location) {
	testing.expect_value(t, value.reference_height, expected.reference_height, loc = loc)
	testing.expect_value(t, value.hotbar_drop_control, expected.hotbar_drop_control, loc = loc)
	testing.expect_value(t, len(value.elements), len(expected.elements), loc = loc)
	for element, index in value.elements {
		if index < len(expected.elements) {
			testing.expect_value(t, element, expected.elements[index], loc = loc)
		}
	}
}

// The shipped layout with every key the editor changes set away from
// the data file: a moved, larger, fainter and rebound A, and a static
// stick.
edited_touch_layout :: proc(t: ^testing.T) -> Touch_Overlay_Layout {
	layout := clone_touch_overlay_layout(button_touch_overlay(t), context.temp_allocator)
	for &element in layout.elements {
		switch {
		case element.label == "A":
			element.position, element.size, element.opacity = {300.5, 590}, {166, 166}, 0.4
			element.control, element.label = {button = .NORTH}, "Y"
		case element.kind == .Stick:
			element.static, element.anchor, element.position, element.opacity = true, .Bottom_Left, {260, 260}, 0.7
		}
	}
	return layout
}

@(test)
test_the_user_touch_layouts_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	named := [?]Named_Touch_Layout{{name = "Mine", layout = edited_touch_layout(t)}, {name = "Shipped", layout = shipped_touch_overlay(t)}}
	written := Touch_Layouts{layouts = named[:], selection = 1}
	text := touch_layouts_file_text(written)
	layouts, selection, problem := parse_touch_layouts_file(transmute([]byte)text, "touch_overlay.sjson")
	testing.expectf(t, problem == "", "%s in\n%s", problem, text)
	testing.expect_value(t, selection, 1)
	testing.expect_value(t, len(layouts), 2)
	if len(layouts) == 2 {
		testing.expect_value(t, layouts[0].name, "Mine")
		expect_same_touch_layout(t, layouts[0].layout, named[0].layout)
		expect_same_touch_layout(t, layouts[1].layout, named[1].layout)
	}
}

@(test)
test_the_selected_user_layout_wins_over_default :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	default_layout := shipped_touch_overlay(t)
	named := [?]Named_Touch_Layout{{name = "Mine", layout = edited_touch_layout(t)}}
	text := touch_layouts_file_text(Touch_Layouts{layouts = named[:], selection = 1})
	layouts, selection, problem := parse_touch_layouts_file(transmute([]byte)text, "touch_overlay.sjson")
	testing.expect_value(t, problem, "")
	loaded := Touch_Layouts{layouts = layouts, selection = selection}
	testing.expect_value(t, selected_touch_layout_name(loaded), "Mine")
	expect_same_touch_layout(t, active_touch_layout(loaded, default_layout), named[0].layout)
	// Stepping the selection reaches Default and wraps back.
	loaded.selection = next_touch_layout_selection(loaded)
	testing.expect_value(t, selected_touch_layout_name(loaded), DEFAULT_TOUCH_LAYOUT_NAME)
	expect_same_touch_layout(t, active_touch_layout(loaded, default_layout), default_layout)
	testing.expect_value(t, next_touch_layout_selection(loaded), 1)
}

START_BUTTON :: `{kind = "button" control = "START" shape = "rectangle" anchor = "top_center" position = [92, 60] size = [163, 79] label = "Start"}`

@(test)
test_a_broken_user_touch_layout_file_reports_and_default_loads :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	Case :: struct {
		text:    string,
		mention: string,
	}
	cases := [?]Case {
		{`selected = "Mine" layouts = [{name = "Mine" reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [{kind = "button" control = "SOUTHH" shape = "circle" anchor = "top_right" position = [10, 10] size = [20, 20] label = "A"}]}]`, `layouts[0] ("Mine"): elements[0] ("A"): unknown control "SOUTHH"`},
		{`selected = "Mine" layouts = [{name = "Mine" reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [{kind = "button" control = "SOUTH" shape = "circle" anchor = "top_right" position = [10, 10] size = [20, 20] label = "A" opacity = 1.5}]}]`, `elements[0] ("A"): the opacity must be from 0.1 to 1`},
		{`selected = "Other" layouts = []`, `selected "Other" names no layout`},
		{`layouts = [{name = "Default" reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = []}]`, "the name Default belongs to the data file's layout"},
		{`layouts = [{name = "A" reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [` + START_BUTTON + `]} {name = "A" reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [` + START_BUTTON + `]}]`, `layouts[1] two layouts named "A"`},
		{`layouts = [{name = "default " reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [` + START_BUTTON + `]}]`, "the name Default belongs to the data file's layout"},
		{`selected = "Mine" colour = "red"`, "unknown key colour"},
	}
	for test_case in cases {
		_, _, problem := parse_touch_layouts_file(transmute([]byte)test_case.text, "touch_overlay.sjson")
		expect_problem_mentions(t, problem, "touch_overlay.sjson", test_case.mention)
	}
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	environment := test_environment(root)
	write_test_file(touch_layouts_path(environment), cases[0].text)
	layouts, problem := load_touch_layouts(environment)
	defer destroy_touch_layouts(&layouts)
	expect_problem_mentions(t, problem, `unknown control "SOUTHH"`)
	testing.expect_value(t, layouts.selection, 0)
	// Locked, so nothing overwrites the broken file.
	testing.expect_value(t, layouts.locked_path, touch_layouts_path(environment))
	expect_same_touch_layout(t, active_touch_layout(layouts, shipped_touch_overlay(t)), shipped_touch_overlay(t))
}

@(test)
test_the_user_touch_layouts_file_is_written_and_read_back :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	environment := test_environment(root)
	// No file: Default and no problem.
	missing, missing_problem := load_touch_layouts(environment)
	testing.expect_value(t, missing_problem, "")
	testing.expect_value(t, missing.selection, 0)
	written: Touch_Layouts
	defer destroy_touch_layouts(&written)
	named, selection := touch_layouts_with(nil, "Mine", edited_touch_layout(t))
	replace_touch_layouts(&written, named, selection)
	testing.expect_value(t, write_touch_layouts_file(environment, written), "")
	read, problem := load_touch_layouts(environment)
	defer destroy_touch_layouts(&read)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, selected_touch_layout_name(read), "Mine")
	expect_same_touch_layout(t, active_touch_layout(read, {}), edited_touch_layout(t))
	// Deleting it leaves Default selected.
	replace_touch_layouts(&read, touch_layouts_without(read.layouts, read.selection), 0)
	testing.expect_value(t, len(read.layouts), 0)
	testing.expect_value(t, selected_touch_layout_name(read), DEFAULT_TOUCH_LAYOUT_NAME)
}

@(test)
test_the_touch_layouts_file_is_written_whole :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	environment := test_environment(root)
	written: Touch_Layouts
	defer destroy_touch_layouts(&written)
	named, selection := touch_layouts_with(nil, "Mine", edited_touch_layout(t))
	replace_touch_layouts(&written, named, selection)
	testing.expect_value(t, write_touch_layouts_file(environment, written), "")
	expect_written_whole(t, touch_layouts_path(environment), touch_layouts_file_text(written))
}

@(test)
test_anchored_offset_inverts_anchored_position :: proc(t: ^testing.T) {
	for anchor in Touch_Overlay_Anchor {
		for screen in ([?][2]f32{PHONE_SCREEN, {1280, 720}}) {
			point := [2]f32{900, 300}
			expect_near(t, anchored_position(anchor, anchored_offset(anchor, point, screen), screen), point)
		}
	}
}

@(test)
test_opacity_scales_the_overlays_alpha :: proc(t: ^testing.T) {
	testing.expect_value(t, touch_overlay_color(1), TOUCH_OVERLAY_COLOR)
	testing.expect_value(t, touch_overlay_color(0.5).a, u8(70))
	testing.expect_value(t, touch_overlay_color(0.5).rgb, TOUCH_OVERLAY_COLOR.rgb)
	// Left out, it is 1.
	for element in shipped_touch_overlay(t).elements {
		testing.expect_value(t, element.opacity, 1)
	}
}

// 0123: Back and Start end 99.5 pixels down at 1080 high, the card a gap
// below; a layout without top_center buttons moves nothing.
@(test)
test_the_top_center_clearance_follows_back_and_start :: proc(t: ^testing.T) {
	layout := button_touch_overlay(t)
	screen := [2]f32{2272, 1080}
	pixels_per_unit := ui_pixels_per_unit(screen.y, 1)
	placed := overlay_layout(layout, screen, context.temp_allocator)
	testing.expect_value(t, touch_overlay_top_center_clearance(layout, placed, pixels_per_unit), 99.5 + UI_GAP)
	testing.expect_value(t, touch_overlay_top_center_clearance(layout, placed, ui_pixels_per_unit(screen.y, 2)), 99.5 / 2 + UI_GAP)
	corners := make([dynamic]Touch_Overlay_Element, 0, len(layout.elements), context.temp_allocator)
	for element in layout.elements {
		if element.anchor != .Top_Center {
			append(&corners, element)
		}
	}
	without := Touch_Overlay_Layout{reference_height = layout.reference_height, elements = corners[:]}
	testing.expect_value(t, touch_overlay_top_center_clearance(without, overlay_layout(without, screen, context.temp_allocator), pixels_per_unit), 0)
}

// The whole screen's gestures (0134). A free spot on the stick's half.
LEFT_POINT :: [2]f32{600, 700}

@(test)
test_a_tap_on_the_left_half_places :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	output := tap_at(&state, layout, 0, LEFT_POINT, TAP_TOUCH)
	testing.expect(t, output.aims)
	expect_near(t, output.aim_point, LEFT_POINT)
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect(t, output.triggers[.Left])
	testing.expect_value(t, output.stick, [2]f32{})
}

@(test)
test_a_hold_on_the_left_half_mines_at_the_finger :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := TAP_TOUCH
	inputs.frame_seconds = 0.1
	output: Touch_Overlay_Output
	for _ in 0 ..< 4 {
		output = touch_frame(&state, layout, {{id = 0, position = LEFT_POINT}}, inputs = inputs)
	}
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hold)
	testing.expect(t, output.triggers[.Right])
	testing.expect(t, output.aims)
	expect_near(t, output.aim_point, LEFT_POINT)
	testing.expect_value(t, output.stick, [2]f32{})
}

@(test)
test_a_drag_on_the_left_half_is_the_stick_with_the_whole_drag_and_never_taps :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	output := touch_frame(&state, layout, {{id = 0, position = LEFT_POINT}}, inputs = TAP_TOUCH)
	testing.expect_value(t, output, Touch_Overlay_Output{})
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Pending)
	// Past the slop on one frame: the stick counts from where it landed.
	output = touch_frame(&state, layout, {{id = 0, position = LEFT_POINT + {0, -20}}}, inputs = TAP_TOUCH)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Stick)
	expect_near(t, output.stick, {0, -20.0 / 130})
	testing.expect(t, !output.aims)
	testing.expect_value(t, output.look_delta, [2]f32{})
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect_value(t, output, Touch_Overlay_Output{})
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
}

@(test)
test_a_second_finger_on_the_left_half_while_the_stick_is_held_turns_the_view :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	touch_frame(&state, layout, {{id = 0, position = LEFT_POINT}}, inputs = TAP_TOUCH)
	stick := []Touch_Point{{id = 0, position = LEFT_POINT + {65, 0}}}
	touch_frame(&state, layout, stick, inputs = TAP_TOUCH)
	second := [2]f32{300, 400}
	touch_frame(&state, layout, {stick[0], {id = 1, position = second}}, inputs = TAP_TOUCH)
	output := touch_frame(&state, layout, {stick[0], {id = 1, position = second + {-25, 0}}}, inputs = TAP_TOUCH)
	testing.expect_value(t, slot_by_id(state, 1).role, Touch_Role.Look)
	expect_near(t, output.look_delta, {-25, 0})
	expect_near(t, output.stick, {0.5, 0})
}

@(test)
test_a_tap_in_the_jump_zone_jumps_without_an_aim :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Raylib, context.temp_allocator)
	state: Touch_Overlay_State
	// The rightmost 20 percent: the Jump action at once, no gamepad control
	// (SOUTH is Interact too) and no aim.
	jump_point := [2]f32{PHONE_SCREEN.x * 0.85, 500}
	output := tap_at(&state, layout, 0, jump_point, TAP_TOUCH)
	testing.expect(t, output.jump_tap && output.jump_tap_edge)
	testing.expect(t, !output.aims)
	testing.expect_value(t, output.buttons, [RAW_GAMEPAD_BUTTON_CAPACITY]bool{})
	testing.expect_value(t, output.triggers, [Gamepad_Trigger]bool{})
	testing.expect_value(t, gamepad_button_actions(touch_overlay_raw_gamepad(output, .Raylib), tables), Action_Set{})
	overlay := Touch_Overlay_Frame{active = true, world_shown = true, output = output}
	input := apply_touch_overlay_jump({}, overlay)
	testing.expect_value(t, input.pressed, Action_Set{.Jump})
	testing.expect_value(t, input.just_pressed, Action_Set{.Jump})
	// Held until a tick has run with the press, the edge on the first
	// frame only, then gone.
	waiting := TAP_TOUCH
	waiting.ticked = false
	output = touch_frame(&state, layout, {}, inputs = waiting)
	testing.expect(t, output.jump_tap && !output.jump_tap_edge)
	testing.expect_value(t, touch_frame(&state, layout, {}, inputs = TAP_TOUCH), Touch_Overlay_Output{})
	// Under a screen the frame presses nothing.
	overlay.world_shown = false
	testing.expect_value(t, apply_touch_overlay_jump({}, overlay).pressed, Action_Set{})
	// At 79 percent a tap places as anywhere else.
	place_point := [2]f32{PHONE_SCREEN.x * 0.79, 500}
	output = tap_at(&state, layout, 1, place_point, TAP_TOUCH)
	testing.expect(t, output.aims)
	testing.expect(t, !output.buttons[int(sdl.GamepadButton.SOUTH)])
	output = touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	testing.expect(t, output.triggers[.Left])
	// A drag and a hold in the zone are the look drag and Mine as elsewhere.
	touch_frame(&state, layout, {}, inputs = TAP_TOUCH)
	touch_frame(&state, layout, {{id = 2, position = jump_point}}, inputs = TAP_TOUCH)
	output = touch_frame(&state, layout, {{id = 2, position = jump_point + {-30, 0}}}, inputs = TAP_TOUCH)
	expect_near(t, output.look_delta, {-30, 0})
}

// A jump zone tap with an entity that takes Interact under the view's
// centre jumps and turns nothing, as A does since 0233.
@(test)
test_a_jump_tap_jumps_with_a_machine_under_the_views_centre :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	add_entity(&world.entities, content.machines, test_machine(content.machines, "power_switch"), {4, 1, 4}, 0)
	players := []Player{make_test_player(content.blocks, {4.5, 1, 1.5})}
	eye := player_eye(players[0].position)
	// The view's aim at the switch, standing in for looking at it.
	view := Input_Frame{aim_direction = linalg.normalize(block_centre({4, 1, 4}) - eye), aim_overrides = true}
	tick_player(&world, &records, content, players, 0, view, TEST_TICK_RATE, 0)
	testing.expect(t, entity_takes_interact(&world.entities, content.machines, players[0].target.entity))
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	output := tap_at(&state, layout, 0, {PHONE_SCREEN.x * 0.9, 500}, TAP_TOUCH)
	jump := apply_touch_overlay_jump(view, Touch_Overlay_Frame{active = true, world_shown = true, output = output})
	players[0].on_ground = true
	events := tick_player(&world, &records, content, players, 0, jump, TEST_TICK_RATE, 0)
	testing.expect_value(t, events, Player_Events{})
	testing.expect(t, players[0].velocity.y > 0)
}

// Work item 0233: a user layout saved before it names
// tap_interact_control (the editor wrote it into every layout); the key
// is read and ignored, so the layout loads, its tap presses X where
// Interact acts or a panel opens, and the next save drops the key.
@(test)
test_a_layout_saved_with_tap_interact_control_loads_and_taps_x :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for value in ([]string{"SOUTH", "NONSENSE"}) {
		text := fmt.tprintf(`selected = "Mine" layouts = [{{name = "Mine" reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [{{kind = "look" side = "right" sensitivity = 1 hold_control = "RIGHT_TRIGGER" tap_interact_control = %q tap_place_control = "LEFT_TRIGGER"}]}]`, value)
		layouts, _, problem := parse_touch_layouts_file(transmute([]byte)text, "touch_overlay.sjson")
		testing.expectf(t, problem == "", "%q: %s", value, problem)
		if len(layouts) != 1 || len(layouts[0].layout.elements) != 1 {
			testing.fail(t)
			continue
		}
		look := layouts[0].layout.elements[0]
		testing.expect_value(t, tap_control(look, true, false), Touch_Overlay_Control{button = .WEST})
		testing.expect_value(t, tap_control(look, false, true), Touch_Overlay_Control{button = .WEST})
		testing.expect_value(t, tap_control(look, false, false), look.tap_place_control)
		testing.expect_value(t, look.tap_place_control, Touch_Overlay_Control{is_trigger = true, trigger = .Left})
		testing.expect(t, !strings.contains(touch_overlay_element_text(look), "tap_interact_control"))
	}
}

@(test)
test_a_user_layout_with_a_button_and_without_start_loads :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	text := `selected = "Mine" layouts = [{name = "Mine" reference_height = 1080 hotbar_drop_control = "DPAD_DOWN" elements = [{kind = "button" control = "LEFT_TRIGGER" shape = "rectangle" anchor = "top_left" position = [181.5, 85] size = [363, 170] label = "LT"}]}]`
	layouts, selection, problem := parse_touch_layouts_file(transmute([]byte)text, "touch_overlay.sjson")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, selection, 1)
	if len(layouts) != 1 {
		testing.fail(t)
		return
	}
	state: Touch_Overlay_State
	output := touch_frame(&state, layouts[0].layout, {{id = 0, position = {181.5, 85}}})
	testing.expect(t, output.triggers[.Left])
}

// The HUD's touch buttons (0134) on the phone at UI scale 1, as the frame
// hands them over: shown ones with the control the shipped bindings give
// their action.
phone_hud_inputs :: proc(t: ^testing.T, shown: bit_set[Hud_Touch_Button]) -> Touch_Interaction_Frame {
	ui: Ui_State
	ui.pixels_per_unit = ui_pixels_per_unit(PHONE_SCREEN.y, 1)
	ui.screen_units = ui_screen_units(PHONE_SCREEN, ui.pixels_per_unit)
	inputs := phone_hotbar_inputs(0)
	rectangles := hud_touch_button_rectangles(ui_safe_area(&ui))
	bindings := shipped_default_bindings(t)
	for button in shown {
		control, found := touch_control_for_action(bindings, hud_touch_button_actions[button], .Raylib)
		testing.expect(t, found)
		inputs.hud_buttons[button] = Touch_Hud_Button{shown = true, rectangle = units_to_pixels_rectangle(rectangles[button], ui.pixels_per_unit), control = control}
	}
	return inputs
}

@(test)
test_the_hud_touch_buttons_press_their_controls_and_claim_the_pointer :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	inputs := phone_hud_inputs(t, {.Inventory, .Map, .Pause, .Rotate})
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Raylib, context.temp_allocator)
	Case :: struct {
		button:  Hud_Touch_Button,
		control: sdl.GamepadButton,
		action:  Action,
	}
	cases := [?]Case{{.Inventory, .WEST, .Open_Inventory}, {.Map, .BACK, .Open_Map}, {.Pause, .START, .Pause}, {.Rotate, .NORTH, .Rotate_Building}}
	for test_case in cases {
		state: Touch_Overlay_State
		point := rectangle_centre(inputs.hud_buttons[test_case.button].rectangle)
		frame := hotbar_frame(&state, layout, {{id = 0, position = point}}, inputs)
		testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hud_Button)
		testing.expect(t, frame.pointer_claimed)
		testing.expect(t, frame.output.buttons[int(test_case.control)])
		testing.expect(t, !frame.output.aims)
		testing.expect(t, test_case.action in gamepad_button_actions(touch_overlay_raw_gamepad(frame.output, .Raylib), tables))
		// Held past the hold time it stays the button's and mines nothing.
		held := inputs
		held.frame_seconds = 0.5
		frame = hotbar_frame(&state, layout, {{id = 0, position = point + {40, -40}}}, held)
		testing.expect(t, frame.output.buttons[int(test_case.control)])
		testing.expect_value(t, frame.output.triggers, [Gamepad_Trigger]bool{})
		// The lift is no tap; a screen opening releases it.
		frame = hotbar_frame(&state, layout, {}, inputs)
		testing.expect_value(t, frame.output, Touch_Overlay_Output{})
		testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
		hotbar_frame(&state, layout, {{id = 1, position = point}}, inputs)
		frame = hotbar_frame(&state, layout, {{id = 1, position = point}}, inputs, false)
		testing.expect_value(t, frame.output, Touch_Overlay_Output{})
	}
	// Over a screen a finger on one is the pointer's.
	state: Touch_Overlay_State
	frame := hotbar_frame(&state, layout, {{id = 0, position = rectangle_centre(inputs.hud_buttons[.Pause].rectangle)}}, inputs, false)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Ignored)
	testing.expect(t, !frame.pointer_claimed)
}

@(test)
test_the_rotate_button_shows_only_while_the_selection_rotates :: proc(t: ^testing.T) {
	testing.expect_value(t, hud_touch_buttons_shown(false, false), bit_set[Hud_Touch_Button]{.Inventory, .Map, .Pause, .Tools})
	testing.expect_value(t, hud_touch_buttons_shown(true, false), bit_set[Hud_Touch_Button]{.Inventory, .Map, .Pause, .Tools, .Rotate})
	content := make_test_content()
	player := make_test_player(content.blocks, {0.5, 1, 0.5})
	Case :: struct {
		item:    string,
		rotates: bool,
	}
	cases := [?]Case{{"wooden_chest", true}, {"stone_stairs", true}, {"stone", false}, {"", false}}
	for test_case in cases {
		player.inventory.slots[0] = test_case.item == "" ? {} : Item_Stack{item = test_item(content.items, test_case.item), count = 1}
		testing.expectf(t, selected_placement_rotates(player, content.machines, content.blocks, content.items) == test_case.rotates, "%q", test_case.item)
	}
	// Hidden, its place is free screen: a finger there is undecided.
	layout := shipped_touch_overlay(t)
	inputs := phone_hud_inputs(t, {.Inventory, .Map, .Pause})
	testing.expect(t, !inputs.hud_buttons[.Rotate].shown)
	state: Touch_Overlay_State
	shown_inputs := phone_hud_inputs(t, {.Inventory, .Map, .Pause, .Rotate})
	point := rectangle_centre(shown_inputs.hud_buttons[.Rotate].rectangle)
	frame := hotbar_frame(&state, layout, {{id = 0, position = point}}, inputs)
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Pending)
	testing.expect(t, !frame.output.buttons[int(sdl.GamepadButton.NORTH)])
}

// A thumb on the stick's side that rests into a hold and then pushes
// drives the stick: the hold ends (Mine and the aim released) and the
// stick takes the drag so far, and taps are accepted again.
@(test)
test_a_hold_on_the_stick_side_that_pushes_becomes_the_stick :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	resting := TAP_TOUCH
	resting.frame_seconds = 0.1
	output: Touch_Overlay_Output
	// Landed, then 0.3 seconds at rest.
	for _ in 0 ..< 4 {
		output = touch_frame(&state, layout, {{id = 0, position = LEFT_POINT}}, inputs = resting)
	}
	testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Hold)
	testing.expect(t, output.triggers[.Right])
	for step in 1 ..= 5 {
		output = touch_frame(&state, layout, {{id = 0, position = LEFT_POINT + {0, -30 * f32(step)}}}, inputs = TAP_TOUCH)
		testing.expect_value(t, slot_by_id(state, 0).role, Touch_Role.Stick)
		testing.expect(t, !output.triggers[.Right])
		testing.expect(t, !output.aims)
		expect_near(t, output.stick, {0, max(-30 * f32(step) / 130, -1)})
	}
	// A tap with another finger is accepted while the stick is held.
	touch_frame(&state, layout, {{id = 0, position = LEFT_POINT + {0, -150}}, {id = 1, position = TAP_POINT}}, inputs = TAP_TOUCH)
	touch_frame(&state, layout, {{id = 0, position = LEFT_POINT + {0, -150}}}, inputs = TAP_TOUCH)
	testing.expect(t, state.tap.phase != .None)
	expect_near(t, state.tap.point, TAP_POINT)
	// A hold on the look side keeps mining where it moves.
	look_state: Touch_Overlay_State
	for _ in 0 ..< 4 {
		touch_frame(&look_state, layout, {{id = 0, position = TAP_POINT}}, inputs = resting)
	}
	output = touch_frame(&look_state, layout, {{id = 0, position = TAP_POINT + {0, -150}}}, inputs = TAP_TOUCH)
	testing.expect_value(t, slot_by_id(look_state, 0).role, Touch_Role.Hold)
	testing.expect(t, output.triggers[.Right])
}

@(test)
test_a_jump_tap_at_exactly_the_zones_edge_jumps :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	output := tap_at(&state, layout, 0, {PHONE_SCREEN.x * 0.8, 500}, TAP_TOUCH)
	testing.expect(t, output.jump_tap)
	testing.expect(t, !output.aims)
}

@(test)
test_a_jump_tap_waiting_too_long_for_a_tick_is_dropped :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	waiting := TAP_TOUCH
	waiting.ticked = false
	testing.expect(t, tap_at(&state, layout, 0, {PHONE_SCREEN.x * 0.9, 500}, waiting).jump_tap)
	for _ in 0 ..< 14 {
		testing.expect(t, touch_frame(&state, layout, {}, inputs = waiting).jump_tap)
	}
	for _ in 0 ..< 2 {
		touch_frame(&state, layout, {}, inputs = waiting)
	}
	testing.expect_value(t, state.tap.phase, Touch_Tap_Phase.None)
	testing.expect_value(t, touch_frame(&state, layout, {}, inputs = TAP_TOUCH), Touch_Overlay_Output{})
}

@(test)
test_a_jump_tap_is_ignored_while_a_tap_or_a_hold_is_in_flight :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	jump_point := [2]f32{PHONE_SCREEN.x * 0.9, 500}
	waiting := TAP_TOUCH
	waiting.ticked = false
	// A place tap still aiming.
	state: Touch_Overlay_State
	tap_at(&state, layout, 0, TAP_POINT, waiting)
	output := tap_at(&state, layout, 1, jump_point, waiting)
	testing.expect(t, !output.jump_tap)
	expect_near(t, state.tap.point, TAP_POINT)
	// A finger holding.
	held: Touch_Overlay_State
	resting := TAP_TOUCH
	resting.frame_seconds = 0.1
	for _ in 0 ..< 4 {
		touch_frame(&held, layout, {{id = 0, position = TAP_POINT}}, inputs = resting)
	}
	touch_frame(&held, layout, {{id = 0, position = TAP_POINT}, {id = 1, position = jump_point}}, inputs = TAP_TOUCH)
	output = touch_frame(&held, layout, {{id = 0, position = TAP_POINT}}, inputs = TAP_TOUCH)
	testing.expect(t, !output.jump_tap)
	testing.expect(t, output.triggers[.Right])
}

// The lookup behind every HUD touch button: the shipped bindings give
// each its control, the map BACK; an action without a gamepad binding
// outside the menus, or bound only on the other backend, has none, and
// its button is not shown.
@(test)
test_a_hud_button_without_a_gamepad_binding_is_hidden :: proc(t: ^testing.T) {
	bindings := shipped_default_bindings(t)
	control, found := touch_control_for_action(bindings, .Open_Map, .Raylib)
	testing.expect(t, found)
	testing.expect_value(t, control, Touch_Overlay_Control{button = .BACK})
	for button in Hud_Touch_Button {
		_, bound := touch_control_for_action(bindings, hud_touch_button_actions[button], .Raylib)
		testing.expectf(t, bound, "%v", button)
	}
	unbound := []Binding {
		{action = .Open_Map, device = .Keyboard, control = "M", binding_context = .Both, backends = {.Raylib, .Sdl3}},
		{action = .Open_Map, device = .Gamepad, control = "BACK", binding_context = .Menu, backends = {.Raylib, .Sdl3}},
		{action = .Open_Map, device = .Gamepad, control = "BACK", binding_context = .World, backends = {.Sdl3}},
	}
	_, found = touch_control_for_action(unbound, .Open_Map, .Raylib)
	testing.expect(t, !found)
}

@(test)
test_the_jump_zone_share_survives_the_layout_writer :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	layout := clone_touch_overlay_layout(shipped_touch_overlay(t))
	look := zone_element(layout, .Look, .Right)
	layout.elements[look].jump_zone_share = 0.35
	named := [?]Named_Touch_Layout{{name = "Mine", layout = layout}}
	text := touch_layouts_file_text(Touch_Layouts{layouts = named[:], selection = 1})
	layouts, _, problem := parse_touch_layouts_file(transmute([]byte)text, "touch_overlay.sjson")
	testing.expect_value(t, problem, "")
	if len(layouts) == 1 {
		testing.expect_value(t, layouts[0].layout.elements[look].jump_zone_share, 0.35)
	}
	// No zone writes no key.
	layout.elements[look].jump_zone_share = 0
	testing.expect(t, !strings.contains(touch_overlay_element_text(layout.elements[look]), "jump_zone_share"))
}

// The rotate button also shows while the target is a belt or an inserter,
// which Rotate_Building turns with an empty hand.
@(test)
test_the_rotate_predicate_covers_a_targeted_belt_and_inserter :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belt := add_entity(&world.entities, content.machines, test_machine(content.machines, "belt"), {4, 1, 4}, 0)
	inserter := add_entity(&world.entities, content.machines, test_machine(content.machines, "inserter"), {6, 1, 4}, 0)
	chest := add_entity(&world.entities, content.machines, test_machine(content.machines, "wooden_chest"), {8, 1, 4}, 0)
	testing.expect(t, entity_rotates(&world.entities, belt))
	testing.expect(t, entity_rotates(&world.entities, inserter))
	testing.expect(t, !entity_rotates(&world.entities, chest))
	testing.expect(t, !entity_rotates(&world.entities, NO_ENTITY))
}

// Work item 0194: a tap's press, from the overlay through the shipped
// bindings, the frame's routing of the inventory binding and the player
// tick, with the player aimed at target the way the tap's aim tick left
// it. Returns the actions the frame pressed after the routing and the
// tick's events.
touch_tap_into_tick :: proc(t: ^testing.T, world: ^World, content: Simulation_Content, players: []Player, interaction: Touch_Interaction) -> (pressed: Action_Set, events: Player_Events) {
	layout := shipped_touch_overlay(t)
	state: Touch_Overlay_State
	inputs := interaction == .Tap ? TAP_TOUCH : CROSSHAIR_TOUCH
	target := players[0].target.entity
	inputs.target_takes_interaction, inputs.target_has_panel = aimed_target_calls_for(&world.entities, content.machines, target, {})
	tap_at(&state, layout, 0, TAP_POINT, inputs)
	output := touch_frame(&state, layout, {}, inputs = inputs)
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Sdl3, context.temp_allocator)
	gamepad := touch_overlay_raw_gamepad(output, .Sdl3)
	actions := gamepad_button_actions(gamepad, tables) + gamepad_trigger_actions(gamepad, tables)
	frame := route_open_inventory_press(Input_Frame{pressed = actions, just_pressed = actions}, false, inputs.target_has_panel, inputs.target_takes_interaction)
	records: Game_Records
	players[0].on_ground = true
	events = tick_player(world, &records, content, players, 0, frame, TEST_TICK_RATE, 0)
	return frame.just_pressed, events
}

// A tap on a furnace opens its panel (no Place, no inventory), on a
// switch turns it, on the ground places; in both schemes, the crosshair
// one aimed by the view.
@(test)
test_a_tap_opens_a_machine_turns_a_switch_and_places_on_the_ground :: proc(t: ^testing.T) {
	content := make_test_content()
	for interaction in ([2]Touch_Interaction{.Tap, .Crosshair}) {
		world := make_floor_world(content.blocks, 32)
		furnace := add_entity(&world.entities, content.machines, test_machine(content.machines, "steel_furnace"), {4, 1, 4}, 0)
		power_switch := add_entity(&world.entities, content.machines, test_machine(content.machines, "power_switch"), {6, 1, 4}, 0)
		players := []Player{make_test_player(content.blocks, {4.5, 1, 1.5})}
		records: Game_Records
		eye := player_eye(players[0].position)
		cases := [?]struct {
			cell:   World_Coordinate,
			entity: Entity_Handle,
		}{{{4, 1, 4}, furnace}, {{6, 1, 4}, power_switch}, {{4, 0, 2}, NO_ENTITY}}
		for target in cases {
			direction := linalg.normalize(block_centre(target.cell) - eye)
			// The tap's aim tick, or the view turned there for the crosshair.
			aim := Input_Frame{aim_direction = direction, aim_overrides = true}
			tick_player(&world, &records, content, players, 0, aim, TEST_TICK_RATE, 0)
			testing.expect_value(t, players[0].target.entity, target.entity)
			pressed, events := touch_tap_into_tick(t, &world, content, players, interaction)
			testing.expectf(t, .Open_Inventory not_in pressed, "%v %v: the inventory opens", interaction, target.entity.kind)
			switch target.entity {
			case furnace:
				testing.expect_value(t, events, Player_Events{.Open_Machine})
				testing.expect_value(t, players[0].open_machine, furnace)
				// X is Interact too since 0233, which a furnace ignores.
				testing.expect(t, .Place not_in pressed && .Open_Aimed in pressed)
				players[0].open_machine = NO_ENTITY
			case power_switch:
				testing.expect_value(t, events, Player_Events{.Toggled_Switch})
				testing.expect(t, .Place not_in pressed)
			case:
				testing.expect_value(t, events, Player_Events{})
				testing.expect(t, .Place in pressed)
			}
		}
	}
}

// Work item 0194 on the field: the tap reads the aimed frame cell, so a
// tap on a switch turns it and a tap on a furnace opens its panel,
// through the overlay, the bindings, the routing and the field tick.
@(test)
test_a_tap_on_the_field_turns_a_switch_and_opens_a_furnace :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	simulation := &session.simulation
	tick_field_test_simulation(simulation, simulation_content, {})
	feet := simulation.players[0].field.position
	frame := add_frame(&simulation.world.entities.frames, feet + {0, 0, 5 * POSITION_UNITS_PER_METRE}, frame_axes({0, UNIT_VECTOR_ONE, 0}, 0), 500)
	entities := &simulation.world.entities
	furnace := add_entity(entities, simulation_content.machines, test_machine(simulation_content.machines, "steel_furnace"), {}, 0, frame)
	power_switch := add_entity(entities, simulation_content.machines, test_machine(simulation_content.machines, "power_switch"), {3, 0, 0}, 0, frame)
	layout := shipped_touch_overlay(t)
	tables, _ := build_input_bindings(shipped_default_bindings(t), .Sdl3, context.temp_allocator)
	for target in ([2]Entity_Handle{power_switch, furnace}) {
		simulation.players[0].field.frame_target = Frame_Raycast_Hit{hit = true, frame = frame, occupant = {handle = entity_occupant_handle(target)}}
		block_target := simulation.players[0].target.entity
		field_target := simulation.players[0].field.frame_target
		inputs := TAP_TOUCH
		inputs.target_takes_interaction, inputs.target_has_panel = aimed_target_calls_for(entities, simulation_content.machines, block_target, field_target)
		state: Touch_Overlay_State
		tap_at(&state, layout, 0, TAP_POINT, inputs)
		output := touch_frame(&state, layout, {}, inputs = inputs)
		gamepad := touch_overlay_raw_gamepad(output, .Sdl3)
		actions := gamepad_button_actions(gamepad, tables) + gamepad_trigger_actions(gamepad, tables)
		pressed := route_open_inventory_press(Input_Frame{pressed = actions, just_pressed = actions}, false, inputs.target_has_panel, inputs.target_takes_interaction)
		was_on := pool_get(&entities.poles, power_switch).on
		clear(&simulation.events)
		tick_field_test_simulation(simulation, simulation_content, pressed)
		events: Player_Events
		for event in simulation.events {
			events += {event.kind}
		}
		testing.expect(t, .Open_Inventory not_in pressed.just_pressed)
		if target == power_switch {
			testing.expect(t, .Toggled_Switch in events)
			testing.expect(t, .Open_Machine not_in events)
			testing.expect_value(t, pool_get(&entities.poles, power_switch).on, !was_on)
		} else {
			testing.expect(t, .Open_Machine in events)
			testing.expect_value(t, simulation.players[0].open_machine, furnace)
		}
	}
}

// The placement editor's touch buttons (0215): the Tools button outside
// the mode, the grid in it, each pressing the gamepad control the shipped
// bindings give its action.
@(test)
test_the_placement_touch_buttons_press_the_editor_actions :: proc(t: ^testing.T) {
	testing.expect_value(t, hud_touch_buttons_shown(false, false), bit_set[Hud_Touch_Button]{.Inventory, .Map, .Pause, .Tools})
	testing.expect_value(t, hud_touch_buttons_shown(true, false), bit_set[Hud_Touch_Button]{.Inventory, .Map, .Pause, .Tools, .Rotate})
	testing.expect_value(t, hud_touch_buttons_shown(true, true), bit_set[Hud_Touch_Button]{.Inventory, .Map, .Pause, .Rotate, .Nudge_Away, .Nudge_Towards, .Nudge_Left, .Nudge_Right, .Commit, .Cancel})
	bindings := shipped_default_bindings(t)
	buttons := [?]Hud_Touch_Button{.Nudge_Away, .Nudge_Towards, .Nudge_Left, .Nudge_Right, .Tools}
	expected := [?]sdl.GamepadButton{.DPAD_UP, .DPAD_DOWN, .DPAD_LEFT, .DPAD_RIGHT, .DPAD_UP}
	for button, index in buttons {
		control, found := touch_control_for_action(bindings, hud_touch_button_actions[button], .Raylib)
		testing.expectf(t, found && !control.is_trigger && control.button == expected[index], "%v: %v", button, control)
	}
	commit, commit_found := touch_control_for_action(bindings, hud_touch_button_actions[.Commit], .Raylib)
	testing.expect(t, commit_found && commit.is_trigger && commit.trigger == .Left)
	cancel, cancel_found := touch_control_for_action(bindings, hud_touch_button_actions[.Cancel], .Raylib)
	testing.expect(t, cancel_found && cancel.is_trigger && cancel.trigger == .Right)
}

@(test)
test_the_tools_button_drag_steers_the_radial :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	inputs := phone_hud_inputs(t, {.Inventory, .Map, .Pause, .Tools})
	inputs.hud_buttons[.Tools].steers = true
	tools := rectangle_centre(inputs.hud_buttons[.Tools].rectangle)
	state: Touch_Overlay_State
	hotbar_frame(&state, layout, {{id = 0, position = tools}}, inputs)
	frame := hotbar_frame(&state, layout, {{id = 0, position = tools + {60, 0}}}, inputs)
	testing.expect(t, frame.output.buttons[int(sdl.GamepadButton.DPAD_UP)])
	expect_near(t, frame.output.look_delta, {60, 0})
	hotbar_frame(&state, layout, {}, inputs)
	map_point := rectangle_centre(inputs.hud_buttons[.Map].rectangle)
	other: Touch_Overlay_State
	hotbar_frame(&other, layout, {{id = 1, position = map_point}}, inputs)
	frame = hotbar_frame(&other, layout, {{id = 1, position = map_point + {60, 0}}}, inputs)
	testing.expect(t, frame.output.buttons[int(sdl.GamepadButton.BACK)])
	testing.expect_value(t, frame.output.look_delta, [2]f32{})
}

// A frame of fingers through the whole overlay frame, which reads the
// interaction frame's placement_editing.
editing_touch_frame :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, points: []Touch_Point, inputs: Touch_Interaction_Frame) -> Touch_Overlay_Output {
	return touch_overlay_frame(state, layout, points, PHONE_SCREEN, true, inputs).output
}

@(test)
test_taps_and_holds_press_nothing_while_the_placement_editor_runs :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	for editing in ([?]bool{true, false}) {
		inputs := TAP_TOUCH
		inputs.placement_editing = editing
		// A tap on the free screen: its aim and its press.
		state: Touch_Overlay_State
		editing_touch_frame(&state, layout, {{id = 0, position = TAP_POINT}}, inputs)
		pressed, aimed := false, false
		for _ in 0 ..< 3 {
			output := editing_touch_frame(&state, layout, {}, inputs)
			pressed = pressed || output.triggers[.Left] || output.buttons[int(sdl.GamepadButton.SOUTH)]
			aimed = aimed || output.aims
		}
		testing.expectf(t, pressed == !editing && aimed == !editing, "editing %v: the tap pressed %v, aimed %v", editing, pressed, aimed)
		// A hold.
		resting := inputs
		resting.frame_seconds = 0.1
		hold: Touch_Overlay_State
		output: Touch_Overlay_Output
		for _ in 0 ..< 4 {
			output = editing_touch_frame(&hold, layout, {{id = 0, position = TAP_POINT}}, resting)
		}
		testing.expect_value(t, slot_by_id(hold, 0).role, Touch_Role.Hold)
		testing.expectf(t, output.triggers[.Right] == !editing, "editing %v: the hold mines %v", editing, output.triggers[.Right])
		// A tap in the jump zone still jumps.
		jump: Touch_Overlay_State
		editing_touch_frame(&jump, layout, {{id = 0, position = {PHONE_SCREEN.x * 0.8, 500}}}, inputs)
		jumped := false
		for _ in 0 ..< 3 {
			jumped = jumped || editing_touch_frame(&jump, layout, {}, inputs).jump_tap
		}
		testing.expectf(t, jumped, "editing %v: the jump tap jumps", editing)
	}
}
