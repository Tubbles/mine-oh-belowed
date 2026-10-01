package game

import "core:fmt"
import "core:math"
import "core:mem/virtual"
import "core:strings"

// The touch layout editor (work item 0121, doc/ui.md), opened from the
// Accessibility tab's Edit touch layout row. It draws the layout being
// edited (the draft) full size at the overlay's real scale over a dimmed
// backdrop, every element a focusable widget with a handle, and a panel
// in the middle for the selected element and the layout.
//
// Pointer: a click or tap selects an element, a drag moves it. Gamepad:
// the left stick moves the focus, Confirm selects the focused element, the
// d-pad moves the selected element while it holds the focus, L1 and R1
// resize it. A move keeps the element's anchor and recomputes its
// position from it. The overlay itself neither draws nor reads while the
// editor is on top (read_touch_overlay_frame), so every touch is the
// pointer's.
//
// The screen changes the draft and the user layouts in memory; the frame
// loop writes the user file (serve_touch_layouts).

TOUCH_LAYOUT_PANEL_WIDTH :: 560
// The heading, the element's name and its four rows, the name field with
// Save as, Save, Delete and Reset, Close.
TOUCH_LAYOUT_PANEL_ROW_COUNT :: 9
// In reference pixels: a d-pad step, a size or radius step, their ranges.
TOUCH_LAYOUT_MOVE_STEP :: 10
TOUCH_LAYOUT_SIZE_STEP :: 10
TOUCH_LAYOUT_SIZE_MINIMUM :: 40
TOUCH_LAYOUT_SIZE_MAXIMUM :: 600
TOUCH_LAYOUT_RADIUS_MINIMUM :: 40
TOUCH_LAYOUT_RADIUS_MAXIMUM :: 400
TOUCH_LAYOUT_OPACITY_STEP :: 0.1
// The handle at each element's top left corner, in UI units.
TOUCH_LAYOUT_HANDLE_SIZE :: 12
TOUCH_LAYOUT_NAME_LENGTH :: 32

// name is the layout the draft was started from, DEFAULT_TOUCH_LAYOUT_NAME
// for the data file's. The name, the draft and the labels a rebind gives
// live in arena. selected is the element index, -1 for none. grab: from
// the pointer to the dragged element's centre, in render pixels.
Touch_Layout_Editor :: struct {
	arena:      ^virtual.Arena,
	name:       string,
	draft:      Touch_Overlay_Layout,
	selected:   int,
	grab:       [2]f32,
	name_field: Text_Field,
	request:    Touch_Layout_Request,
}

destroy_touch_layout_editor :: proc(editor: ^Touch_Layout_Editor) {
	destroy_arena(editor.arena)
	editor^ = {}
}

// A fresh draft of layout under name, cloned before the old arena goes, so
// both may point into it. The name field starts at the name, empty for
// Default.
start_touch_layout_draft :: proc(editor: ^Touch_Layout_Editor, name: string, layout: Touch_Overlay_Layout, selected := -1) {
	arena := new_growing_arena()
	allocator := virtual.arena_allocator(arena)
	name_copy := strings.clone(name, allocator)
	draft := clone_touch_overlay_layout(layout, allocator)
	destroy_arena(editor.arena)
	editor.arena, editor.name, editor.draft, editor.grab, editor.request = arena, name_copy, draft, {}, .None
	editor.selected = selected < len(draft.elements) ? selected : -1
	editor.name_field = make_text_field(name_copy == DEFAULT_TOUCH_LAYOUT_NAME ? "" : name_copy, TOUCH_LAYOUT_NAME_LENGTH)
}

// The selected layout into the draft, and the screen on top.
open_touch_layout_editor :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, layouts: Touch_Layouts, default_layout: Touch_Overlay_Layout) {
	start_touch_layout_draft(editor, selected_touch_layout_name(layouts), active_touch_layout(layouts, default_layout))
	push_screen(&state.screens, .Touch_Layout)
}

touch_layout_display_name :: proc(name: string) -> string {
	return name == DEFAULT_TOUCH_LAYOUT_NAME ? text("touch_layout_default") : name
}

// Elements.

// The look draws nothing and has no place, so the editor leaves it alone.
touch_element_editable :: proc(element: Touch_Overlay_Element) -> bool {
	return element.kind != .Look
}

// A button or a static stick; a floating stick has no place of its own.
touch_element_movable :: proc(element: Touch_Overlay_Element) -> bool {
	return element.kind == .Button || (element.kind == .Stick && element.static)
}

// In render pixels: where the overlay puts a button or a static stick's
// base, a floating stick in the middle of its half.
touch_element_centre :: proc(layout: Touch_Overlay_Layout, element: Touch_Overlay_Element, screen_size: [2]f32) -> [2]f32 {
	if touch_element_movable(element) {
		return anchored_position(element.anchor, element.position * touch_overlay_scale(layout, screen_size), screen_size)
	}
	return {element.side == .Left ? screen_size.x / 4 : screen_size.x * 3 / 4, screen_size.y / 2}
}

// In render pixels: a button's size, a stick's base.
touch_element_extent :: proc(layout: Touch_Overlay_Layout, element: Touch_Overlay_Element, screen_size: [2]f32) -> [2]f32 {
	scale := touch_overlay_scale(layout, screen_size)
	if element.kind == .Stick {
		return {2, 2} * element.radius * scale
	}
	return element.size * scale
}

// The centre kept where the extent stays between low and high.
clamp_centre :: proc(value, half, low, high: f32) -> f32 {
	if high - low <= 2 * half {
		return (low + high) / 2
	}
	return clamp(value, low + half, high - half)
}

// Moved so its centre sits at centre (render pixels), kept on the screen,
// a stick on its own half (the half decides which zone a touch reaches).
// The anchor stays; the position is recomputed from it, in whole
// reference pixels.
move_touch_element :: proc(layout: Touch_Overlay_Layout, element: Touch_Overlay_Element, centre, screen_size: [2]f32) -> Touch_Overlay_Element {
	if !touch_element_movable(element) {
		return element
	}
	half := touch_element_extent(layout, element, screen_size) / 2
	low_x, high_x := f32(0), screen_size.x
	if element.kind == .Stick {
		low_x, high_x = element.side == .Left ? 0 : screen_size.x / 2, element.side == .Left ? screen_size.x / 2 : screen_size.x
	}
	inside := [2]f32{clamp_centre(centre.x, half.x, low_x, high_x), clamp_centre(centre.y, half.y, 0, screen_size.y)}
	offset := anchored_offset(element.anchor, inside, screen_size) / touch_overlay_scale(layout, screen_size)
	result := element
	result.position = {math.round(offset.x), math.round(offset.y)}
	return result
}

// Held to a move's constraints where it is, after a resize or a switch to
// static: on the screen, a stick on its own half.
constrain_touch_element :: proc(layout: Touch_Overlay_Layout, element: Touch_Overlay_Element, screen_size: [2]f32) -> Touch_Overlay_Element {
	return move_touch_element(layout, element, touch_element_centre(layout, element, screen_size), screen_size)
}

// One d-pad step of TOUCH_LAYOUT_MOVE_STEP reference pixels.
step_touch_element :: proc(layout: Touch_Overlay_Layout, element: Touch_Overlay_Element, direction: Ui_Direction, screen_size: [2]f32) -> Touch_Overlay_Element {
	step := direction_vector(direction) * TOUCH_LAYOUT_MOVE_STEP * touch_overlay_scale(layout, screen_size)
	return move_touch_element(layout, element, touch_element_centre(layout, element, screen_size) + step, screen_size)
}

// steps size or radius steps larger (negative: smaller). A circle stays
// round.
resize_touch_element :: proc(element: Touch_Overlay_Element, steps: f32) -> Touch_Overlay_Element {
	result := element
	change := steps * TOUCH_LAYOUT_SIZE_STEP
	switch element.kind {
	case .Button:
		result.size.x = clamp(element.size.x + change, TOUCH_LAYOUT_SIZE_MINIMUM, TOUCH_LAYOUT_SIZE_MAXIMUM)
		result.size.y = element.shape == .Circle ? result.size.x : clamp(element.size.y + change, TOUCH_LAYOUT_SIZE_MINIMUM, TOUCH_LAYOUT_SIZE_MAXIMUM)
	case .Stick:
		result.radius = clamp(element.radius + change, TOUCH_LAYOUT_RADIUS_MINIMUM, TOUCH_LAYOUT_RADIUS_MAXIMUM)
	case .Look:
	}
	return result
}

// In steps of 0.1 from 0.1 to 1.
step_touch_element_opacity :: proc(element: Touch_Overlay_Element, steps: f32) -> Touch_Overlay_Element {
	result := element
	stepped := math.round((element.opacity + steps * TOUCH_LAYOUT_OPACITY_STEP) * 10) / 10
	result.opacity = clamp(stepped, TOUCH_OVERLAY_OPACITY_MINIMUM, 1)
	return result
}

// The button pressing control, labelled label.
rebind_touch_element :: proc(element: Touch_Overlay_Element, control: Touch_Overlay_Control, label: string) -> Touch_Overlay_Element {
	result := element
	result.control, result.label = control, label
	return result
}

// A floating stick becomes static at the bottom corner of its half, two
// radii in; a static one floats again.
toggle_touch_stick_static :: proc(element: Touch_Overlay_Element) -> Touch_Overlay_Element {
	result := element
	result.static = !element.static
	if result.static {
		result.anchor = element.side == .Left ? .Bottom_Left : .Bottom_Right
		result.position = {2 * element.radius, 2 * element.radius}
	} else {
		result.anchor, result.position = {}, {}
	}
	return result
}

// A navigation step from the d-pad or the arrow keys, not the left stick,
// which keeps moving the focus.
touch_layout_dpad_step :: proc(state: Ui_State) -> Ui_Direction {
	move := state.input.move
	if max(abs(move.x), abs(move.y)) >= UI_STICK_NAVIGATION_THRESHOLD {
		return .None
	}
	return state.navigation_step
}

// The layout and the user file.

// What the panel's buttons ask for. The screen only records it: the frame
// loop serves it after the frame's draw list ran (serve_touch_layouts),
// since starting the draft again frees the arena the frame's text
// commands point into.
Touch_Layout_Request :: enum u8 {
	None,
	Save,
	Save_As,
	Delete,
	Reset,
}

// The request the screen made, if any, then none. Toasts through ui.
apply_touch_layout_request :: proc(ui: ^Ui_State, editor: ^Touch_Layout_Editor, layouts: ^Touch_Layouts, default_layout: Touch_Overlay_Layout) {
	request := editor.request
	editor.request = .None
	if request == .None || editor.arena == nil {
		return
	}
	if request != .Reset && layouts.locked_path != "" {
		ui_toast(ui, touch_layouts_locked_text(layouts^))
		return
	}
	switch request {
	case .None:
	case .Save:
		save_touch_layout(ui, editor, layouts)
	case .Save_As:
		save_touch_layout_as(ui, editor, layouts)
	case .Delete:
		delete_touch_layout(ui, editor, layouts, default_layout)
	case .Reset:
		reset_touch_layout(editor, default_layout)
	}
}

// The draft under name: replaced or added, selected, and asked to be
// written. The draft starts again from the stored copy. A layout needs no
// START button (0134): the HUD's pause button opens the pause menu.
store_touch_layout :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, layouts: ^Touch_Layouts, name: string) {
	named, selection := touch_layouts_with(layouts.layouts, name, editor.draft)
	replace_touch_layouts(layouts, named, selection)
	layouts.write_requested, layouts.changed = true, true
	stored := layouts.layouts[selection - 1]
	start_touch_layout_draft(editor, stored.name, stored.layout, editor.selected)
	ui_toast(state, fmt.tprintf("%s %s", text("touch_layout_saved"), stored.name))
}

// Default cannot change, only be copied with Save as.
save_touch_layout :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, layouts: ^Touch_Layouts) {
	if editor.name == DEFAULT_TOUCH_LAYOUT_NAME {
		ui_toast(state, text("touch_layout_default_fixed"))
		return
	}
	store_touch_layout(state, editor, layouts, editor.name)
}

save_touch_layout_as :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, layouts: ^Touch_Layouts) {
	name := strings.trim_space(text_field_text(&editor.name_field))
	if touch_layout_name_problem(name) != "" {
		ui_toast(state, text("touch_layout_name_invalid"))
		return
	}
	store_touch_layout(state, editor, layouts, name)
}

// The edited user layout goes; Default is selected and drafted.
delete_touch_layout :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, layouts: ^Touch_Layouts, default_layout: Touch_Overlay_Layout) {
	selection, found := touch_layout_selection(layouts.layouts, editor.name)
	if !found || selection == 0 {
		ui_toast(state, text("touch_layout_default_fixed"))
		return
	}
	ui_toast(state, fmt.tprintf("%s %s", text("touch_layout_deleted"), editor.name))
	replace_touch_layouts(layouts, touch_layouts_without(layouts.layouts, selection), 0)
	layouts.write_requested, layouts.changed = true, true
	start_touch_layout_draft(editor, DEFAULT_TOUCH_LAYOUT_NAME, default_layout)
}

// Default's whole layout (its elements, reference_height and
// hotbar_drop_control) under the draft's name, with nothing selected;
// saved only by Save.
reset_touch_layout :: proc(editor: ^Touch_Layout_Editor, default_layout: Touch_Overlay_Layout) {
	start_touch_layout_draft(editor, editor.name, default_layout)
}

// The screen.

touch_layout_editor_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	editor, layouts := screen_context.touch_layout_editor, screen_context.touch_layouts
	if editor == nil || layouts == nil || editor.arena == nil {
		pop_screen(&state.screens)
		return
	}
	ui_backdrop(state)
	name_label := text("touch_layout_name")
	if state.keyboard.field != 0 {
		touch_layout_name_entry(state, editor, name_label)
		return
	}
	if state.keyboard.return_focus != 0 {
		state.requested_focus, state.keyboard.return_focus = state.keyboard.return_focus, 0
	}
	screen_size := state.screen_units * state.pixels_per_unit
	panel := fitted_panel(ui_panel_area(state), TOUCH_LAYOUT_PANEL_WIDTH, panel_height(TOUCH_LAYOUT_PANEL_ROW_COUNT, -UI_GAP))
	// One focus scope over the whole screen, so the focus reaches every
	// element and the panel's widgets alike. It is no Ui_Panel: the
	// elements sit outside the safe area, and a tooltip docks beside its
	// widget.
	state.current_panel = ui_push_id(state, "touch_layout_editor")
	touch_layout_elements(state, editor, screen_size, panel)
	resize_selected_touch_element(state, editor, screen_size)
	touch_layout_panel(state, panel, editor, screen_size, name_label)
	ui_panel_end(state)
	// On touch its own buttons (Close among them) are the row.
	if !touch_row_shows(state) {
		hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Tab_Previous, ""}, {.Tab_Next, text("hint_touch_layout_size")}, {.Back, text("hint_back")}}
		ui_glyph_bar(state, hints[:])
	}
}

// The name field and the on-screen keyboard alone, as the new world
// screen shows them.
touch_layout_name_entry :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, label: string) {
	width := f32(max(TOUCH_LAYOUT_PANEL_WIDTH, KEYBOARD_WIDTH + 2 * UI_PADDING))
	panel := fitted_panel(ui_panel_area(state), width, panel_height(1, keyboard_keys_height(state.keyboard)))
	ui_panel_begin(state, "touch_layout_name_entry", panel)
	content := inset(panel, UI_PADDING)
	field_row := cut_row(&content)
	draw_text_field_content(state, field_row, label, &editor.name_field, true)
	if ui_on_screen_keyboard(state, field_row, {content.x + (content.width - KEYBOARD_WIDTH) / 2, content.y}, &editor.name_field) {
		state.keyboard = Keyboard_State {
			return_focus = state.keyboard.field,
		}
	}
	ui_panel_end(state)
	keyboard_glyph_bar(state)
}

// Every editable element as a widget: a click or Confirm selects it, a
// drag moves it, the d-pad moves the selected one while it holds the
// focus. The pointer over the panel reaches no element under it.
touch_layout_elements :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, screen_size: [2]f32, panel: Ui_Rectangle) {
	layout := editor.draft
	pointer := state.pointer * state.pixels_per_unit
	pointer_on_panel := ui_pointer_over(state, panel)
	dpad_step := touch_layout_dpad_step(state^)
	for &element, index in layout.elements {
		if !touch_element_editable(element) {
			continue
		}
		centre := touch_element_centre(layout, element, screen_size)
		rectangle := pixels_to_units_rectangle(centre, touch_element_extent(layout, element, screen_size), state.pixels_per_unit)
		id := ui_id(state, "touch_element", index)
		flags := index == editor.selected && dpad_step != .None ? Ui_Widget_Flags{.Adjusts_Horizontally, .Adjusts_Vertically} : {}
		interaction := ui_interact(state, id, rectangle, flags, text("touch_layout_element_tooltip"))
		if pointer_on_panel {
			interaction.hovered = false
			interaction.activated = interaction.focused && state.confirm
		}
		if interaction.activated {
			editor.selected = index
		}
		// The press selects and grabs the element at once, where other
		// widgets wait for the tap (0132), so the drag moves the selection.
		if interaction.hovered && state.click {
			state.dragging, editor.grab = id, centre - pointer
			editor.selected = index
		}
		switch {
		case state.dragging == id && state.pointer_held && state.pointer_moved:
			element = move_touch_element(layout, element, pointer + editor.grab, screen_size)
		case interaction.focused && index == editor.selected && dpad_step != .None:
			element = step_touch_element(layout, element, dpad_step, screen_size)
		}
		draw_touch_layout_element(state, layout, element, screen_size, id, index == editor.selected)
	}
}

// As the overlay draws it at rest, with the handle at its top left corner
// and the selected one outlined in the accent.
draw_touch_layout_element :: proc(state: ^Ui_State, layout: Touch_Overlay_Layout, element: Touch_Overlay_Element, screen_size: [2]f32, id: Ui_Id, selected: bool) {
	centre := touch_element_centre(layout, element, screen_size)
	rectangle := pixels_to_units_rectangle(centre, touch_element_extent(layout, element, screen_size), state.pixels_per_unit)
	color := touch_overlay_color(element.opacity)
	if element.kind == .Stick {
		draw_touch_stick(state, Touch_Slot{origin = centre, position = centre}, element.radius * touch_overlay_scale(layout, screen_size), color)
	} else {
		draw_touch_overlay_button(state, rectangle, element.shape, false, element.label, color)
	}
	theme := ui_theme(state)
	handle_color := selected ? theme.colors[.Accent] : theme.colors[.Text_Dim]
	draw_fill(state, {rectangle.x, rectangle.y, min(TOUCH_LAYOUT_HANDLE_SIZE, rectangle.width), min(TOUCH_LAYOUT_HANDLE_SIZE, rectangle.height)}, handle_color)
	if selected {
		draw_outline(state, rectangle, theme.colors[.Accent], theme.border)
	}
	draw_focus_outline(state, rectangle, id)
}

// L1 and R1 (Q and E) resize the selected element wherever the focus is.
resize_selected_touch_element :: proc(state: ^Ui_State, editor: ^Touch_Layout_Editor, screen_size: [2]f32) {
	steps := f32(int(state.input.tab_next) - int(state.input.tab_previous))
	if steps != 0 && editor.selected >= 0 && editor.selected < len(editor.draft.elements) {
		element := editor.draft.elements[editor.selected]
		editor.draft.elements[editor.selected] = constrain_touch_element(editor.draft, resize_touch_element(element, steps), screen_size)
	}
}

touch_layout_panel :: proc(state: ^Ui_State, panel: Ui_Rectangle, editor: ^Touch_Layout_Editor, screen_size: [2]f32, name_label: string) {
	draw_panel_art(state, panel, theme_color(state, .Panel), theme_color(state, .Panel_Edge))
	content := inset(panel, UI_PADDING)
	heading := fmt.tprintf("%s: %s", text("touch_layout_editor_title"), touch_layout_display_name(editor.name))
	draw_text_fitted(state, cut_row(&content), heading, UI_HEADING_TEXT_SIZE, .Centre)
	touch_layout_element_rows(state, &content, editor, screen_size)
	name_row := cut_row(&content)
	save_as := cut_right(&name_row, (name_row.width - UI_GAP) / 3)
	cut_right(&name_row, UI_GAP)
	if ui_text_field(state, name_row, name_label, &editor.name_field, text("touch_layout_name_tooltip")) {
		open_keyboard(state, ui_id(state, name_label))
	}
	if ui_button(state, save_as, text("touch_layout_save_as"), text("touch_layout_save_as_tooltip")) {
		editor.request = .Save_As
	}
	row := cut_row(&content)
	if ui_button(state, column_rectangle(row, 3, 0, UI_GAP), text("touch_layout_save"), text("touch_layout_save_tooltip")) {
		editor.request = .Save
	}
	if ui_button(state, column_rectangle(row, 3, 1, UI_GAP), text("touch_layout_delete"), text("touch_layout_delete_tooltip")) {
		editor.request = .Delete
	}
	if ui_button(state, column_rectangle(row, 3, 2, UI_GAP), text("touch_layout_reset"), text("touch_layout_reset_tooltip")) {
		editor.request = .Reset
	}
	if ui_button(state, cut_row(&content), text("touch_layout_close"), text("touch_layout_close_tooltip")) {
		pop_screen(&state.screens)
	}
}

// The selected element's name, then its rows: a button's size, opacity,
// control and double tap latch, a stick's radius, opacity and static
// flag. Five rows whatever is selected, so the buttons below stay put.
// A change of size or place is held to the screen as a move is.
touch_layout_element_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, editor: ^Touch_Layout_Editor, screen_size: [2]f32) {
	name_row := cut_row(content)
	rows := [4]Ui_Rectangle{cut_row(content), cut_row(content), cut_row(content), cut_row(content)}
	if editor.selected < 0 || editor.selected >= len(editor.draft.elements) {
		draw_text_fitted(state, inset(name_row, UI_PADDING), text("touch_layout_nothing_selected"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
		return
	}
	layout := editor.draft
	element := &editor.draft.elements[editor.selected]
	name := element.kind == .Stick ? text("touch_layout_stick") : element.label
	draw_text_fitted(state, inset(name_row, UI_PADDING), name, UI_BODY_TEXT_SIZE, .Left)
	switch element.kind {
	case .Button:
		size_text := fmt.tprintf("%.0f x %.0f", element.size.x, element.size.y)
		if steps := touch_layout_steps(ui_stepper(state, rows[0], text("touch_layout_size"), size_text, text("touch_layout_stepper_tooltip"))); steps != 0 {
			element^ = constrain_touch_element(layout, resize_touch_element(element^, steps), screen_size)
		}
		touch_layout_opacity_row(state, rows[1], element)
		if ui_choice(state, rows[2], text("touch_layout_control"), touch_overlay_control_name(element.control), text("touch_layout_control_tooltip")) {
			control := next_touch_overlay_control(element.control)
			label := strings.clone(text(touch_overlay_control_label_key(control)), virtual.arena_allocator(editor.arena))
			element^ = rebind_touch_element(element^, control, label)
		}
		ui_toggle(state, rows[3], text("touch_layout_double_tap"), &element.double_tap_toggles, text("touch_layout_double_tap_tooltip"))
	case .Stick:
		if steps := touch_layout_steps(ui_stepper(state, rows[0], text("touch_layout_radius"), fmt.tprintf("%.0f", element.radius), text("touch_layout_stepper_tooltip"))); steps != 0 {
			element^ = constrain_touch_element(layout, resize_touch_element(element^, steps), screen_size)
		}
		touch_layout_opacity_row(state, rows[1], element)
		static := element.static
		if ui_toggle(state, rows[2], text("touch_layout_static"), &static, text("touch_layout_static_tooltip")) {
			element^ = constrain_touch_element(layout, toggle_touch_stick_static(element^), screen_size)
		}
	case .Look:
	}
}

// A stepper's direction as steps: -1 left, 1 right.
touch_layout_steps :: proc(direction: Ui_Direction) -> f32 {
	#partial switch direction {
	case .Left:
		return -1
	case .Right:
		return 1
	}
	return 0
}

touch_layout_opacity_row :: proc(state: ^Ui_State, row: Ui_Rectangle, element: ^Touch_Overlay_Element) {
	value := fmt.tprintf("%d%%", int(math.round(element.opacity * 100)))
	if steps := touch_layout_steps(ui_stepper(state, row, text("touch_layout_opacity"), value, text("touch_layout_stepper_tooltip"))); steps != 0 {
		element^ = step_touch_element_opacity(element^, steps)
	}
}
