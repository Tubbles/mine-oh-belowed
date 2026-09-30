package game

import "core:testing"
import sdl "vendor:sdl3"

// The touch layout editor (work item 0121).

touch_element_index :: proc(layout: Touch_Overlay_Layout, label: string) -> int {
	for element, index in layout.elements {
		if element.label == label {
			return index
		}
	}
	return -1
}

@(test)
test_a_move_keeps_the_anchor_and_recomputes_the_position :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	a := layout.elements[touch_element_index(layout, "A")]
	for screen in ([?][2]f32{PHONE_SCREEN, {1280, 720}}) {
		target := [2]f32{screen.x * 0.7, screen.y * 0.4}
		moved := move_touch_element(layout, a, target, screen)
		testing.expect_value(t, moved.anchor, Touch_Overlay_Anchor.Top_Right)
		scale := touch_overlay_scale(layout, screen)
		// Whole reference pixels, so within half a reference pixel.
		centre := touch_element_centre(layout, moved, screen)
		testing.expectf(t, abs(centre.x - target.x) <= 0.5 * scale && abs(centre.y - target.y) <= 0.5 * scale, "%v moved to %v", target, centre)
	}
	// On the phone the scale is 1: the offset from the top right corner.
	moved := move_touch_element(layout, a, {1800, 400}, PHONE_SCREEN)
	testing.expect_value(t, moved.position, [2]f32{624, 400})
	// A d-pad step right is 10 reference pixels nearer the right edge.
	stepped := step_touch_element(layout, moved, .Right, PHONE_SCREEN)
	testing.expect_value(t, stepped.position, [2]f32{614, 400})
	// Past the edge it stays on the screen.
	clamped := move_touch_element(layout, a, {5000, -300}, PHONE_SCREEN)
	testing.expect_value(t, clamped.position, a.size / 2)
	// A floating stick has no place; a static one stays on its half.
	stick := layout.elements[zone_element(layout, .Stick, .Left)]
	testing.expect_value(t, move_touch_element(layout, stick, {100, 100}, PHONE_SCREEN), stick)
	static := toggle_touch_stick_static(stick)
	testing.expect(t, static.static)
	testing.expect_value(t, static.anchor, Touch_Overlay_Anchor.Bottom_Left)
	moved_stick := move_touch_element(layout, static, {2000, 500}, PHONE_SCREEN)
	testing.expect_value(t, touch_element_centre(layout, moved_stick, PHONE_SCREEN).x, PHONE_SCREEN.x / 2 - stick.radius)
	floating := toggle_touch_stick_static(static)
	testing.expect(t, !floating.static)
	testing.expect_value(t, floating.position, [2]f32{})
}

@(test)
test_a_rebind_changes_the_control_the_button_presses :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	layout := clone_touch_overlay_layout(shipped_touch_overlay(t))
	index := touch_element_index(layout, "A")
	control := next_touch_overlay_control(layout.elements[index].control)
	testing.expect_value(t, control, Touch_Overlay_Control{button = .EAST})
	layout.elements[index] = rebind_touch_element(layout.elements[index], control, "B")
	testing.expect_value(t, layout.elements[index].label, "B")
	placed := placed_by_label(layout, overlay_layout(layout, PHONE_SCREEN, context.temp_allocator), "B")
	state: Touch_Overlay_State
	output := touch_frame(&state, layout, {{id = 0, position = placed.centre}})
	testing.expect(t, output.buttons[int(sdl.GamepadButton.EAST)])
	testing.expect(t, !output.buttons[int(sdl.GamepadButton.SOUTH)])
	// The cycle holds every control the loader knows and wraps.
	controls := touch_overlay_controls()
	for candidate in controls {
		name := touch_overlay_control_name(candidate)
		resolved, ok := touch_overlay_control_from_name(name)
		testing.expectf(t, ok && resolved == candidate, "%s", name)
	}
	testing.expect_value(t, next_touch_overlay_control(controls[len(controls) - 1]), controls[0])
}

@(test)
test_resize_keeps_a_circle_round_and_opacity_steps_by_a_tenth :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	a := layout.elements[touch_element_index(layout, "A")]
	larger := resize_touch_element(a, 1)
	testing.expect_value(t, larger.size, a.size + 10)
	testing.expect_value(t, larger.size.x, larger.size.y)
	testing.expect_value(t, resize_touch_element(a, -100).size, [2]f32{TOUCH_LAYOUT_SIZE_MINIMUM, TOUCH_LAYOUT_SIZE_MINIMUM})
	lt := layout.elements[touch_element_index(layout, "LT")]
	testing.expect_value(t, resize_touch_element(lt, -1).size, lt.size - 10)
	stick := layout.elements[zone_element(layout, .Stick, .Left)]
	testing.expect_value(t, resize_touch_element(stick, 1).radius, stick.radius + 10)
	faded := a
	for _ in 0 ..< 3 {
		faded = step_touch_element_opacity(faded, -1)
	}
	testing.expect_value(t, faded.opacity, f32(0.7))
	for _ in 0 ..< 20 {
		faded = step_touch_element_opacity(faded, -1)
	}
	testing.expect_value(t, faded.opacity, f32(TOUCH_OVERLAY_OPACITY_MINIMUM))
	testing.expect_value(t, step_touch_element_opacity(a, 1).opacity, f32(1))
}

// The screen with the gamepad: select A, move it with the d-pad, grow it
// with R1, Save on Default refuses, Save as stores and selects it, Delete
// selects Default again.
@(test)
test_the_touch_layout_editor_with_the_gamepad :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	editor, layouts := &audit.touch_layout_editor, &audit.touch_layouts
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Pause)
	push_screen(&state.screens, .Settings)
	push_screen(&state.screens, .Touch_Layout)
	screen_test_frame(audit, &state, {})
	scope := ui_hash(0, "touch_layout_editor", -1)
	index := touch_element_index(editor.draft, "A")
	before := editor.draft.elements[index]
	state.focus = ui_hash(scope, "touch_element", index)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect_value(t, editor.selected, index)
	screen_test_frame(audit, &state, {navigation = .Right})
	testing.expect_value(t, editor.draft.elements[index].position, before.position - {10, 0})
	testing.expect_value(t, state.focus, ui_hash(scope, "touch_element", index))
	screen_test_frame(audit, &state, {tab_next = true})
	testing.expect_value(t, editor.draft.elements[index].size, before.size + 10)
	// Default does not change.
	state.focus = ui_hash(scope, text("touch_layout_save"), -1)
	screen_test_frame(audit, &state, {confirm = true})
	apply_touch_layout_request(&state, editor, layouts, audit.default_touch_layout)
	testing.expect_value(t, len(layouts.layouts), 0)
	testing.expect(t, !layouts.write_requested)
	text_field_set(&editor.name_field, "Mine")
	state.focus = ui_hash(scope, text("touch_layout_save_as"), -1)
	screen_test_frame(audit, &state, {confirm = true})
	// Only requested: the frame loop serves it after the draw.
	testing.expect_value(t, len(layouts.layouts), 0)
	apply_touch_layout_request(&state, editor, layouts, audit.default_touch_layout)
	testing.expect_value(t, selected_touch_layout_name(layouts^), "Mine")
	testing.expect(t, layouts.write_requested && layouts.changed)
	testing.expect_value(t, editor.name, "Mine")
	testing.expect_value(t, active_touch_layout(layouts^, audit.default_touch_layout).elements[index].size, before.size + 10)
	testing.expect_value(t, audit.default_touch_layout.elements[index].size, before.size)
	layouts.write_requested = false
	state.focus = ui_hash(scope, text("touch_layout_delete"), -1)
	screen_test_frame(audit, &state, {confirm = true})
	apply_touch_layout_request(&state, editor, layouts, audit.default_touch_layout)
	testing.expect_value(t, len(layouts.layouts), 0)
	testing.expect_value(t, selected_touch_layout_name(layouts^), DEFAULT_TOUCH_LAYOUT_NAME)
	testing.expect(t, layouts.write_requested)
	testing.expect_value(t, editor.name, DEFAULT_TOUCH_LAYOUT_NAME)
	testing.expect_value(t, top_screen(state.screens), Screen.Touch_Layout)
}

// The Accessibility tab's Touch layout row steps the selection and asks
// for the file to be written; Edit touch layout opens the editor on the
// selected layout.
@(test)
test_the_touch_layout_row_cycles_the_selection_and_opens_the_editor :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	layouts := &audit.touch_layouts
	named, _ := touch_layouts_with(nil, "Mine", audit.default_touch_layout)
	replace_touch_layouts(layouts, named, 0)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Pause)
	push_screen(&state.screens, .Settings)
	screen_test_frame(audit, &state, {})
	for _ in 0 ..< 3 {
		screen_test_frame(audit, &state, {tab_next = true})
	}
	panel := ui_hash(0, "settings", -1)
	state.focus = ui_hash(panel, text("settings_touch_layout"), -1)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect_value(t, selected_touch_layout_name(layouts^), "Mine")
	testing.expect(t, layouts.write_requested && layouts.changed)
	state.focus = ui_hash(panel, text("settings_edit_touch_layout"), -1)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Touch_Layout)
	testing.expect_value(t, audit.touch_layout_editor.name, "Mine")
	testing.expect_value(t, text_field_text(&audit.touch_layout_editor.name_field), "Mine")
}

// A tap selects an element and a drag moves it (1920 by 1080, scale 1).
@(test)
test_the_touch_layout_editor_drags_an_element :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	editor := &audit.touch_layout_editor
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Touch_Layout)
	screen_test_frame(audit, &state, {})
	index := touch_element_index(editor.draft, "A")
	centre := touch_element_centre(editor.draft, editor.draft.elements[index], {1920, 1080})
	screen_test_frame(audit, &state, {mouse_position = centre, mouse_moved = true, mouse_pressed = true, mouse_down = true})
	testing.expect_value(t, editor.selected, index)
	screen_test_frame(audit, &state, {mouse_position = centre - {100, 50}, mouse_moved = true, mouse_down = true})
	moved := editor.draft.elements[index]
	testing.expect_value(t, moved.anchor, Touch_Overlay_Anchor.Top_Right)
	testing.expect_value(t, moved.position, audit.default_touch_layout.elements[index].position + {100, -50})
	// Released, the pointer moves nothing.
	screen_test_frame(audit, &state, {mouse_position = centre, mouse_moved = true})
	testing.expect_value(t, editor.draft.elements[index].position, moved.position)
}

// Every text command's string, as execute_draw_list reads them: a Save as
// that freed the draft's arena mid frame left them pointing into unmapped
// memory.
draw_list_text_checksum :: proc(state: Ui_State) -> int {
	checksum := 0
	for command in state.draw_list {
		if command.kind == .Text {
			for character in transmute([]u8)command.text {
				checksum += int(character)
			}
		}
	}
	return checksum
}

@(test)
test_a_save_as_leaves_the_frames_text_readable :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	editor, layouts := &audit.touch_layout_editor, &audit.touch_layouts
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Touch_Layout)
	scope := ui_hash(0, "touch_layout_editor", -1)
	editor.selected = touch_element_index(editor.draft, "A")
	text_field_set(&editor.name_field, "Mine")
	state.focus = ui_hash(scope, text("touch_layout_save_as"), -1)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, draw_list_text_checksum(state) > 0)
	apply_touch_layout_request(&state, editor, layouts, audit.default_touch_layout)
	testing.expect_value(t, selected_touch_layout_name(layouts^), "Mine")
}

// A layout without START is refused, since the phone could not reach the
// pause menu; while the broken file from the start stands, neither the
// row nor the editor changes anything.
@(test)
test_the_editor_refuses_a_layout_without_start_and_a_locked_file :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	editor, layouts := &audit.touch_layout_editor, &audit.touch_layouts
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	start := touch_element_index(editor.draft, "Start")
	editor.draft.elements[start] = rebind_touch_element(editor.draft.elements[start], {button = .GUIDE}, "Guide")
	text_field_set(&editor.name_field, "Mine")
	editor.request = .Save_As
	apply_touch_layout_request(&state, editor, layouts, audit.default_touch_layout)
	testing.expect_value(t, len(layouts.layouts), 0)
	testing.expect(t, !layouts.write_requested)
	reset_touch_layout(editor, audit.default_touch_layout)
	layouts.locked_path = "touch_overlay.sjson"
	defer layouts.locked_path = ""
	text_field_set(&editor.name_field, "Mine")
	editor.request = .Save_As
	apply_touch_layout_request(&state, editor, layouts, audit.default_touch_layout)
	testing.expect_value(t, len(layouts.layouts), 0)
	step_touch_layout_selection(&state, layouts)
	testing.expect_value(t, layouts.selection, 0)
	testing.expect(t, !layouts.write_requested)
}

// The panel's Double tap latches row turns the flag off, so a rebound B
// need not latch.
@(test)
test_the_double_tap_row_turns_the_latch_off :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	editor := &audit.touch_layout_editor
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Touch_Layout)
	index := touch_element_index(editor.draft, "B")
	testing.expect(t, editor.draft.elements[index].double_tap_toggles)
	editor.selected = index
	screen_test_frame(audit, &state, {})
	state.focus = ui_hash(ui_hash(0, "touch_layout_editor", -1), text("touch_layout_double_tap"), -1)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, !editor.draft.elements[index].double_tap_toggles)
}

// A resize is held to the screen like a move.
@(test)
test_a_resize_keeps_the_element_on_the_screen :: proc(t: ^testing.T) {
	layout := shipped_touch_overlay(t)
	lt := layout.elements[touch_element_index(layout, "LT")]
	larger := constrain_touch_element(layout, resize_touch_element(lt, 10), PHONE_SCREEN)
	// Against the corner, in whole reference pixels (463 wide: 232 in).
	testing.expect_value(t, larger.position, [2]f32{232, 135})
	stick := toggle_touch_stick_static(layout.elements[zone_element(layout, .Stick, .Left)])
	stick.position = {1080, 300}
	wide := constrain_touch_element(layout, resize_touch_element(stick, 5), PHONE_SCREEN)
	testing.expect_value(t, touch_element_centre(layout, wide, PHONE_SCREEN).x, PHONE_SCREEN.x / 2 - wide.radius)
}
