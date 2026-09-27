package game

import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode"

// Sizes in UI units (1080 per screen height). Text sizes follow doc/ui.md.
UI_BODY_TEXT_SIZE :: 24
UI_HEADING_TEXT_SIZE :: 32
UI_GLYPH_TEXT_SIZE :: 28
UI_ROW_HEIGHT :: 56
UI_PADDING :: 16
UI_GAP :: 8
UI_BORDER :: 2
UI_FOCUS_BORDER :: 4
UI_CHECKBOX_SIZE :: 32
UI_SLOT_SIZE :: 80
UI_SLOT_ICON_INSET :: 12
UI_SLOT_COUNT_TEXT_SIZE :: 24
UI_TOOLTIP_WIDTH :: 420
// Lines of wrapped text (tooltips, toasts, quest text) sit this far apart.
UI_LINE_HEIGHT :: UI_ROW_HEIGHT * 0.6
// A toast is at most this share of the safe area wide, which leaves the
// HUD objective its room, and wraps to at most UI_TOAST_MAXIMUM_LINES.
UI_TOAST_WIDTH_FRACTION :: 0.55
UI_TOAST_MAXIMUM_LINES :: 3
UI_ELLIPSIS :: "..."
UI_POINTER_SIZE :: 14
// The panel id the glyph bar's commands carry.
UI_GLYPH_BAR_PANEL :: Ui_Id(0xffff_ffff_ffff_ffff)
// Rows per second at full right stick deflection.
UI_LIST_STICK_ROWS_PER_SECOND :: 12

UI_PANEL_COLOR :: Ui_Color{24, 26, 34, 230}
UI_PANEL_BORDER_COLOR :: Ui_Color{90, 96, 120, 255}
UI_WIDGET_COLOR :: Ui_Color{44, 48, 62, 255}
UI_HOVER_COLOR :: Ui_Color{60, 66, 86, 255}
UI_ACCENT_COLOR :: Ui_Color{236, 176, 64, 255}
UI_TEXT_COLOR :: Ui_Color{235, 235, 240, 255}
UI_DIM_TEXT_COLOR :: Ui_Color{160, 164, 180, 255}
UI_BACKDROP_COLOR :: Ui_Color{0, 0, 0, 120}
UI_GLYPH_COLOR :: Ui_Color{235, 235, 240, 255}

Ui_Interaction :: struct {
	focused:   bool,
	hovered:   bool,
	activated: bool,
}

Slider_Range :: struct {
	minimum: f32,
	maximum: f32,
	step:    f32,
}

// Logical buttons the glyph bar can show; glyph_key maps them per device.
Glyph_Button :: enum u8 {
	Confirm,
	Back,
	Tab_Previous,
	Tab_Next,
	Info,
	Context_Action,
	Pause,
	Inventory,
	Secondary,
	Interact,
	// The world's Place control, which reads a selected schematic.
	Use_Item,
	// The stick click that toggles sprinting (0044).
	Sprint,
	// R2 or Q in a machine panel (0078).
	Quick_Move,
}

Glyph_Hint :: struct {
	button: Glyph_Button,
	label:  string,
}

Radial_Result :: struct {
	closed:   bool,
	// Slot chosen on release, -1 when released in the dead centre.
	selected: int,
}

push_command :: proc(state: ^Ui_State, command: Draw_Command) {
	tagged := command
	tagged.panel = state.current_panel
	append(&state.draw_list, tagged)
}

draw_fill :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, color: Ui_Color) {
	push_command(state, {kind = .Fill, rectangle = rectangle, color = color})
}

draw_outline :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, color: Ui_Color, thickness: f32 = UI_BORDER) {
	push_command(state, {kind = .Outline, rectangle = rectangle, color = color, thickness = thickness})
}

// emphasis draws body sized text bold, like a heading (text_weight).
draw_text :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, text: string, size: f32, alignment: Text_Alignment, color := UI_TEXT_COLOR, emphasis := false) {
	push_command(state, {kind = .Text, rectangle = rectangle, text = text, text_size = size, weight = text_weight(size, emphasis), alignment = alignment, color = color})
}

// The text, or its longest start that fits the width followed by an
// ellipsis ("" when not even the ellipsis fits). In the temp allocator.
fit_text :: proc(state: ^Ui_State, value: string, size, width: f32, emphasis := false) -> string {
	if ui_text_width(state, value, size, emphasis) <= width {
		return value
	}
	// Byte offsets of the rune starts; the longest fitting start is found
	// by bisection, since a longer start is never narrower.
	starts := make([dynamic]int, 0, len(value), context.temp_allocator)
	for _, offset in value {
		append(&starts, offset)
	}
	fitting := ""
	low, high := 0, len(starts) - 1
	for low <= high {
		middle := (low + high) / 2
		candidate := strings.concatenate({strings.trim_right_space(value[:starts[middle]]), UI_ELLIPSIS}, context.temp_allocator)
		if ui_text_width(state, candidate, size, emphasis) <= width {
			fitting, low = candidate, middle + 1
		} else {
			high = middle - 1
		}
	}
	return fitting
}

// Single line text that ends with an ellipsis where it does not fit.
draw_text_fitted :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, value: string, size: f32, alignment: Text_Alignment, color := UI_TEXT_COLOR, emphasis := false) {
	draw_text(state, rectangle, fit_text(state, value, size, rectangle.width, emphasis), size, alignment, color, emphasis)
}

// Wrapped to at most maximum_lines lines; the last line ends with an
// ellipsis when the text goes on. In the temp allocator.
wrap_text_lines :: proc(state: ^Ui_State, value: string, size, width: f32, maximum_lines: int) -> []string {
	lines := wrap_text(state, value, size, width)
	if len(lines) <= maximum_lines {
		return lines
	}
	last := strings.join(lines[maximum_lines - 1:], " ", context.temp_allocator)
	lines[maximum_lines - 1] = fit_text(state, last, size, width)
	return lines[:maximum_lines]
}

// The pixels must stay valid until the frame is drawn.
draw_image :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, pixels: []Ui_Color, size: [2]i32, revision: u64) {
	push_command(state, {kind = .Image, rectangle = rectangle, pixels = pixels, image_size = size, image_revision = revision})
}

draw_focus_outline :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id) {
	push_command(state, {kind = .Focus_Outline, rectangle = rectangle, color = UI_ACCENT_COLOR, thickness = UI_FOCUS_BORDER, widget = id})
}

ui_pointer_over :: proc(state: ^Ui_State, rectangle: Ui_Rectangle) -> bool {
	return state.pointer_source != .None && rectangle_contains(rectangle, state.pointer)
}

// Registers a focusable widget and reports how it is used this frame.
ui_interact :: proc(state: ^Ui_State, id: Ui_Id, rectangle: Ui_Rectangle, flags: Ui_Widget_Flags = {}, tooltip := "") -> Ui_Interaction {
	append(&state.widgets, Ui_Widget{id = id, panel = state.current_panel, rectangle = rectangle, flags = flags})
	focused := state.focus == id
	hovered := ui_pointer_over(state, rectangle)
	if focused && tooltip != "" {
		state.focused_tooltip = tooltip
	}
	return Ui_Interaction{focused = focused, hovered = hovered, activated = (focused && state.confirm) || (hovered && state.click)}
}

// Widgets inside a panel move focus among each other; the tooltip docks to it.
ui_panel_begin :: proc(state: ^Ui_State, label: string, rectangle: Ui_Rectangle) {
	id := ui_push_id(state, label)
	state.current_panel = id
	append(&state.panels, Ui_Panel{id = id, rectangle = rectangle})
	draw_fill(state, rectangle, UI_PANEL_COLOR)
	draw_outline(state, rectangle, UI_PANEL_BORDER_COLOR)
}

ui_panel_end :: proc(state: ^Ui_State) {
	ui_pop_id(state)
	state.current_panel = 0
}

ui_backdrop :: proc(state: ^Ui_State) {
	draw_fill(state, {0, 0, state.screen_units.x, state.screen_units.y}, UI_BACKDROP_COLOR)
}

ui_label :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, text: string, size: f32 = UI_BODY_TEXT_SIZE, alignment := Text_Alignment.Left, color := UI_TEXT_COLOR) {
	draw_text(state, rectangle, text, size, alignment, color)
}

widget_background :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id, interaction: Ui_Interaction) {
	draw_fill(state, rectangle, interaction.hovered ? UI_HOVER_COLOR : UI_WIDGET_COLOR)
	draw_focus_outline(state, rectangle, id)
}

ui_button :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, tooltip := "") -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {}, tooltip)
	widget_background(state, rectangle, id, interaction)
	draw_text_fitted(state, inset(rectangle, UI_GAP), label, UI_BODY_TEXT_SIZE, .Centre)
	return interaction.activated
}

// Label on the left, a check box on the right. Returns true when flipped.
ui_toggle :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, value: ^bool, tooltip := "") -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {}, tooltip)
	if interaction.activated {
		value^ = !value^
	}
	widget_background(state, rectangle, id, interaction)
	label_area := inset(rectangle, UI_PADDING)
	label_area.width = max(label_area.width - UI_CHECKBOX_SIZE - UI_GAP, 0)
	draw_text_fitted(state, label_area, label, UI_BODY_TEXT_SIZE, .Left)
	box := Ui_Rectangle {
		rectangle.x + rectangle.width - UI_PADDING - UI_CHECKBOX_SIZE,
		rectangle.y + (rectangle.height - UI_CHECKBOX_SIZE) / 2,
		UI_CHECKBOX_SIZE,
		UI_CHECKBOX_SIZE,
	}
	draw_outline(state, box, UI_TEXT_COLOR)
	if value^ {
		draw_fill(state, inset(box, 6), UI_ACCENT_COLOR)
	}
	return interaction.activated
}

// Label on the left, the current value on the right. Returns true when
// activated; the caller steps the value, so the id stays with the label.
ui_choice :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label, value: string, tooltip := "") -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {}, tooltip)
	widget_background(state, rectangle, id, interaction)
	content := inset(rectangle, UI_PADDING)
	value_text := fit_text(state, value, UI_BODY_TEXT_SIZE, content.width / 2)
	draw_text(state, content, value_text, UI_BODY_TEXT_SIZE, .Right)
	content.width = max(content.width - ui_text_width(state, value_text, UI_BODY_TEXT_SIZE) - UI_GAP, 0)
	draw_text_fitted(state, content, label, UI_BODY_TEXT_SIZE, .Left)
	return interaction.activated
}

slider_fraction :: proc(value: f32, range: Slider_Range) -> f32 {
	if range.maximum <= range.minimum {
		return 0
	}
	return clamp((value - range.minimum) / (range.maximum - range.minimum), 0, 1)
}

slider_value_at :: proc(track: Ui_Rectangle, x: f32, range: Slider_Range) -> f32 {
	fraction := track.width > 0 ? clamp((x - track.x) / track.width, 0, 1) : 0
	value := range.minimum + fraction * (range.maximum - range.minimum)
	return clamp(snap_to_step(value, range.minimum, range.step), range.minimum, range.maximum)
}

step_slider_value :: proc(value: f32, range: Slider_Range, direction: Ui_Direction) -> f32 {
	#partial switch direction {
	case .Left:
		return clamp(snap_to_step(value - range.step, range.minimum, range.step), range.minimum, range.maximum)
	case .Right:
		return clamp(snap_to_step(value + range.step, range.minimum, range.step), range.minimum, range.maximum)
	}
	return value
}

// Label on the left, the track and the value text on the right. Left and
// right step the value while focused; a click or drag on the track sets it.
ui_slider :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, value: ^f32, range: Slider_Range, value_text: string, tooltip := "") -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {.Adjusts_Horizontally}, tooltip)
	value_width := f32(UI_BODY_TEXT_SIZE * 4)
	track := Ui_Rectangle{rectangle.x + rectangle.width * 0.45, rectangle.y + rectangle.height / 2 - 6, rectangle.width * 0.55 - value_width - 2 * UI_PADDING, 12}
	before := value^
	if interaction.focused {
		value^ = step_slider_value(value^, range, state.navigation_step)
	}
	grab := Ui_Rectangle{track.x - UI_PADDING, rectangle.y, track.width + 2 * UI_PADDING, rectangle.height}
	if state.click && ui_pointer_over(state, grab) {
		state.dragging = id
	}
	if state.dragging == id && state.pointer_held {
		value^ = slider_value_at(track, state.pointer.x, range)
	}
	widget_background(state, rectangle, id, interaction)
	label_area := inset(rectangle, UI_PADDING)
	label_area.width = max(track.x - UI_PADDING - label_area.x, 0)
	draw_text_fitted(state, label_area, label, UI_BODY_TEXT_SIZE, .Left)
	draw_fill(state, track, UI_PANEL_COLOR)
	filled := track
	filled.width *= slider_fraction(value^, range)
	draw_fill(state, filled, UI_ACCENT_COLOR)
	value_area := Ui_Rectangle{rectangle.x + rectangle.width - UI_PADDING - value_width, rectangle.y, value_width, rectangle.height}
	draw_text(state, value_area, value_text, UI_BODY_TEXT_SIZE, .Right)
	return value^ != before
}

// Bumpers cycle the tabs, the pointer picks one. Tabs are not focus
// targets, so the stick moves only between the widgets of the open tab.
// The selection lives in the UI state under the tab strip's id.
ui_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, labels: []string) -> int {
	id := ui_id(state, label)
	count := len(labels)
	if count == 0 {
		return 0
	}
	selected := clamp(state.selections[id], 0, count - 1)
	if state.input.tab_previous {
		selected = (selected + count - 1) % count
	}
	if state.input.tab_next {
		selected = (selected + 1) % count
	}
	for tab_label, index in labels {
		tab := column(rectangle, count, index, UI_GAP)
		if state.click && ui_pointer_over(state, tab) {
			selected = index
		}
		draw_fill(state, tab, ui_pointer_over(state, tab) ? UI_HOVER_COLOR : UI_WIDGET_COLOR)
		draw_text_fitted(state, inset(tab, UI_GAP), tab_label, UI_BODY_TEXT_SIZE, .Centre, index == selected ? UI_ACCENT_COLOR : UI_DIM_TEXT_COLOR)
	}
	underline := column(rectangle, count, selected, UI_GAP)
	draw_fill(state, cut_bottom(&underline, 4), UI_ACCENT_COLOR)
	state.selections[id] = selected
	return selected
}

// Index of the first item whose text starts with the letter, ignoring case.
list_index_for_letter :: proc(items: []string, letter: rune) -> int {
	wanted := unicode.to_lower(letter)
	for item, index in items {
		for first in item {
			if unicode.to_lower(first) == wanted {
				return index
			}
			break
		}
	}
	return -1
}

// The scroll offset that keeps the row visible.
scroll_to_show :: proc(scroll, row_top, row_height, view_height: f32) -> f32 {
	if row_top < scroll {
		return row_top
	}
	if row_top + row_height > scroll + view_height {
		return row_top + row_height - view_height
	}
	return scroll
}

// A scrolling vertical list. The right stick and the wheel scroll it, the
// focus keeps itself in view, and ui_request_letter_jump (the letter wheel)
// moves the focus to the first item starting with a letter. Returns the
// activated item or -1.
ui_list :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, items: []string, tooltip := "") -> int {
	list_id := ui_push_id(state, label)
	defer ui_pop_id(state)
	content_height := f32(len(items)) * UI_ROW_HEIGHT
	maximum_scroll := max(content_height - rectangle.height, 0)
	scroll := state.scroll_offsets[list_id]
	focus_inside := false
	activated := -1
	push_command(state, {kind = .Clip_Begin, rectangle = rectangle})
	for item, index in items {
		item_id := ui_id(state, "item", index)
		row_top := f32(index) * UI_ROW_HEIGHT
		row := Ui_Rectangle{rectangle.x, rectangle.y + row_top - scroll, rectangle.width, UI_ROW_HEIGHT}
		interaction := ui_interact(state, item_id, row, {}, tooltip)
		if interaction.focused {
			focus_inside = true
			scroll = scroll_to_show(scroll, row_top, UI_ROW_HEIGHT, rectangle.height)
		}
		if interaction.activated {
			activated = index
		}
		widget_background(state, row, item_id, interaction)
		draw_text_fitted(state, inset(row, UI_PADDING), item, UI_BODY_TEXT_SIZE, .Left)
	}
	push_command(state, {kind = .Clip_End})
	if focus_inside || ui_pointer_over(state, rectangle) {
		scroll -= state.input.scroll_stick * UI_LIST_STICK_ROWS_PER_SECOND * UI_ROW_HEIGHT * state.frame_seconds
		scroll -= state.input.scroll_wheel * UI_ROW_HEIGHT
	}
	if focus_inside && state.letter_jump != 0 {
		if jump := list_index_for_letter(items, state.letter_jump); jump >= 0 {
			state.requested_focus = ui_id(state, "item", jump)
		}
	}
	state.scroll_offsets[list_id] = clamp(scroll, 0, maximum_scroll)
	return activated
}

// A clipped area over content that may be taller: the content moves under
// it by the scroll offset. The right stick and the wheel scroll it while
// the focus or the pointer is inside, and a focused widget inside keeps
// itself in view, so panels clamped to the safe area stay usable with
// focus navigation alone. Must not hold a list, since clips do not nest.
Scroll_Region :: struct {
	id:             Ui_Id,
	area:           Ui_Rectangle,
	scroll:         f32,
	content_height: f32,
	first_widget:   int,
	first_command:  int,
}

// Returns the region and the content rectangle to lay out in: the area's
// width and content_height tall (at least the area's), moved up by the
// scroll. Content drawn below content_height still scrolls into view.
scroll_region_begin :: proc(state: ^Ui_State, label: string, area: Ui_Rectangle, content_height: f32) -> (region: Scroll_Region, content: Ui_Rectangle) {
	id := ui_id(state, label)
	maximum_scroll := max(content_height - area.height, 0)
	region = Scroll_Region {
		id             = id,
		area           = area,
		scroll         = clamp(state.scroll_offsets[id], 0, maximum_scroll),
		content_height = max(content_height, area.height),
		first_widget   = len(state.widgets),
		first_command  = len(state.draw_list) + 1,
	}
	push_command(state, {kind = .Clip_Begin, rectangle = area})
	return region, {area.x, area.y - region.scroll, area.width, region.content_height}
}

scroll_region_end :: proc(state: ^Ui_State, region: Scroll_Region) {
	content_top := region.area.y - region.scroll
	// The content may reach below the height given; what was drawn counts.
	content_height := region.content_height
	for command in state.draw_list[region.first_command:] {
		content_height = max(content_height, command.rectangle.y + command.rectangle.height - content_top)
	}
	push_command(state, {kind = .Clip_End})
	scroll := region.scroll
	focus_inside := false
	for widget in state.widgets[region.first_widget:] {
		if widget.id == state.focus {
			focus_inside = true
			scroll = scroll_to_show(scroll, widget.rectangle.y - content_top, widget.rectangle.height, region.area.height)
		}
	}
	if focus_inside || ui_pointer_over(state, region.area) {
		scroll -= state.input.scroll_stick * UI_LIST_STICK_ROWS_PER_SECOND * UI_ROW_HEIGHT * state.frame_seconds
		scroll -= state.input.scroll_wheel * UI_ROW_HEIGHT
	}
	state.scroll_offsets[region.id] = clamp(scroll, 0, content_height - region.area.height)
}

ui_request_letter_jump :: proc(state: ^Ui_State, letter: rune) {
	state.letter_jump = letter
}

// Placeholder icon: the atlas tile, or a coloured square with two letters.
draw_item_icon :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, icon: Item_Icon) {
	switch icon.kind {
	case .Block_Tile:
		push_command(state, {kind = .Atlas_Tile, rectangle = rectangle, tile = icon.tile})
	case .Lettered:
		letters := icon.letters
		draw_fill(state, rectangle, icon.color)
		draw_outline(state, rectangle, UI_PANEL_COLOR)
		draw_text(state, rectangle, strings.clone_from_bytes(letters[:], context.temp_allocator), rectangle.height * 0.45, .Centre)
	}
}

// Icon with the count in the bottom right corner; nothing for an empty stack.
draw_item_stack :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, stack: Item_Stack, items: Item_Registry) {
	if stack_is_empty(stack) {
		return
	}
	draw_item_icon(state, inset(rectangle, UI_SLOT_ICON_INSET * rectangle.height / UI_SLOT_SIZE), item_icon(items, stack.item))
	if stack.count > 1 {
		count_area := inset(rectangle, 4)
		count_area = cut_bottom(&count_area, UI_SLOT_COUNT_TEXT_SIZE)
		draw_text(state, count_area, fmt.tprint(stack.count), UI_SLOT_COUNT_TEXT_SIZE, .Right)
	}
}

// Info panel text of a stack: name, category and how full it is.
item_stack_tooltip :: proc(stack: Item_Stack, items: Item_Registry) -> string {
	if stack_is_empty(stack) {
		return ""
	}
	category := text(item_category_key(items.items[stack.item].category))
	return fmt.tprintf("%s  %s  %d / %d", item_name(items, stack.item), category, stack.count, item_stack_size(items, stack.item))
}

ui_item_slot :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id, stack: Item_Stack, items: Item_Registry) -> Ui_Interaction {
	interaction := ui_interact(state, id, rectangle, {}, item_stack_tooltip(stack, items))
	widget_background(state, rectangle, id, interaction)
	draw_outline(state, rectangle, UI_PANEL_BORDER_COLOR)
	draw_item_stack(state, rectangle, stack, items)
	return interaction
}

slot_grid_width :: proc(columns: int) -> f32 {
	return f32(columns) * (UI_SLOT_SIZE + UI_GAP) - UI_GAP
}

slot_grid_height :: proc(rows: int) -> f32 {
	return slot_grid_width(rows)
}

// Slots per row that fit a width, at least one.
slot_columns :: proc(width: f32) -> int {
	return max(int((width + UI_GAP) / (UI_SLOT_SIZE + UI_GAP)), 1)
}

// Height of count slots in rows of columns, with the gap under each row.
slot_rows_height :: proc(count, columns: int) -> f32 {
	rows := (count + columns - 1) / max(columns, 1)
	return f32(rows) * (UI_SLOT_SIZE + UI_GAP)
}

slot_grid_rectangle :: proc(origin: [2]f32, columns, index: int) -> Ui_Rectangle {
	return {
		origin.x + f32(index % columns) * (UI_SLOT_SIZE + UI_GAP),
		origin.y + f32(index / columns) * (UI_SLOT_SIZE + UI_GAP),
		UI_SLOT_SIZE,
		UI_SLOT_SIZE,
	}
}

// Indices into the grid's slots, -1 for none.
Slot_Grid_Result :: struct {
	activated: int,
	focused:   int,
}

// A grid of item slots, row by row from the origin.
ui_slot_grid :: proc(state: ^Ui_State, origin: [2]f32, label: string, columns: int, slots: []Item_Stack, items: Item_Registry) -> Slot_Grid_Result {
	ui_push_id(state, label)
	defer ui_pop_id(state)
	result := Slot_Grid_Result{activated = -1, focused = -1}
	for stack, index in slots {
		interaction := ui_item_slot(state, slot_grid_rectangle(origin, columns, index), ui_id(state, "slot", index), stack, items)
		if interaction.activated {
			result.activated = index
		}
		if interaction.focused {
			result.focused = index
		}
	}
	return result
}

ui_progress_bar :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, fraction: f32) {
	draw_fill(state, rectangle, UI_WIDGET_COLOR)
	filled := rectangle
	filled.width *= clamp(fraction, 0, 1)
	draw_fill(state, filled, UI_ACCENT_COLOR)
	draw_outline(state, rectangle, UI_PANEL_BORDER_COLOR)
}

// String key of a button's glyph on the active device.
glyph_key :: proc(device: Input_Device, button: Glyph_Button) -> string {
	switch device {
	case .Gamepad:
		switch button {
		case .Confirm:
			return "glyph_gamepad_confirm"
		case .Back:
			return "glyph_gamepad_back"
		case .Tab_Previous:
			return "glyph_gamepad_tab_previous"
		case .Tab_Next:
			return "glyph_gamepad_tab_next"
		case .Info:
			return "glyph_gamepad_info"
		case .Context_Action:
			return "glyph_gamepad_context_action"
		case .Pause:
			return "glyph_gamepad_pause"
		case .Inventory:
			return "glyph_gamepad_inventory"
		case .Secondary:
			return "glyph_gamepad_secondary"
		case .Interact:
			return "glyph_gamepad_interact"
		case .Use_Item:
			return "glyph_gamepad_use_item"
		case .Sprint:
			return "glyph_gamepad_sprint"
		case .Quick_Move:
			return "glyph_gamepad_quick_move"
		}
	case .Keyboard_Mouse:
		switch button {
		case .Confirm:
			return "glyph_keyboard_confirm"
		case .Back:
			return "glyph_keyboard_back"
		case .Tab_Previous:
			return "glyph_keyboard_tab_previous"
		case .Tab_Next:
			return "glyph_keyboard_tab_next"
		case .Info:
			return "glyph_keyboard_info"
		case .Context_Action:
			return "glyph_keyboard_context_action"
		case .Pause:
			return "glyph_keyboard_pause"
		case .Inventory:
			return "glyph_keyboard_inventory"
		case .Secondary:
			return "glyph_keyboard_secondary"
		case .Interact:
			return "glyph_keyboard_interact"
		case .Use_Item:
			return "glyph_keyboard_use_item"
		case .Sprint:
			return "glyph_keyboard_sprint"
		case .Quick_Move:
			return "glyph_keyboard_quick_move"
		}
	}
	return ""
}

UI_GLYPH_BAR_HEIGHT :: UI_GLYPH_TEXT_SIZE + 2 * UI_GAP

// The safe area above the glyph bar, where screens put their panels.
ui_panel_area :: proc(state: ^Ui_State) -> Ui_Rectangle {
	area := ui_safe_area(state)
	cut_bottom(&area, UI_GLYPH_BAR_HEIGHT + 2 * UI_GAP)
	return area
}

// Width of a hint's glyph box: the glyph with a margin, at least square.
glyph_box_width :: proc(state: ^Ui_State, glyph: string) -> f32 {
	return max(ui_text_width(state, glyph, UI_GLYPH_TEXT_SIZE) + 2 * UI_GAP, UI_GLYPH_BAR_HEIGHT)
}

glyph_bar_width :: proc(state: ^Ui_State, hints: []Glyph_Hint) -> f32 {
	width := f32(0)
	for hint, index in hints {
		glyph := text(glyph_key(state.active_device, hint.button))
		width += glyph_box_width(state, glyph) + UI_GAP + ui_text_width(state, hint.label, UI_GLYPH_TEXT_SIZE)
		width += index > 0 ? 3 * UI_GAP : 0
	}
	return width
}

// The hints that fit the width. Hints go from the end of the list, but
// the last one (Back by convention) stays; an unlabelled hint paired with
// a dropped one (the left bumper of a bumper pair) goes with it. In the
// temp allocator.
glyph_hints_that_fit :: proc(state: ^Ui_State, hints: []Glyph_Hint, width: f32) -> []Glyph_Hint {
	kept := make([dynamic]Glyph_Hint, 0, len(hints), context.temp_allocator)
	append(&kept, ..hints)
	for len(kept) > 1 && glyph_bar_width(state, kept[:]) > width {
		dropped := len(kept) - 2
		ordered_remove(&kept, dropped)
		if dropped > 0 && kept[dropped - 1].label == "" {
			ordered_remove(&kept, dropped - 1)
		}
	}
	return kept[:]
}

// Glyph and label pairs, right aligned along the bottom of the safe area,
// as many as fit its width (glyph_hints_that_fit). The bar registers the
// safe area as its panel, so the bounds audit holds its commands to it.
ui_glyph_bar :: proc(state: ^Ui_State, hints: []Glyph_Hint) {
	area := ui_safe_area(state)
	outer_panel := state.current_panel
	append(&state.panels, Ui_Panel{id = UI_GLYPH_BAR_PANEL, rectangle = area})
	state.current_panel = UI_GLYPH_BAR_PANEL
	defer state.current_panel = outer_panel
	height := f32(UI_GLYPH_BAR_HEIGHT)
	x := area.x + area.width
	y := area.y + area.height - height
	#reverse for hint in glyph_hints_that_fit(state, hints, area.width) {
		label_width := ui_text_width(state, hint.label, UI_GLYPH_TEXT_SIZE)
		x -= label_width
		draw_text(state, {x, y, label_width, height}, hint.label, UI_GLYPH_TEXT_SIZE, .Left)
		glyph := text(glyph_key(state.active_device, hint.button))
		box_width := glyph_box_width(state, glyph)
		x -= box_width + UI_GAP
		box := Ui_Rectangle{x, y, box_width, height}
		draw_fill(state, box, UI_WIDGET_COLOR)
		draw_outline(state, box, UI_GLYPH_COLOR)
		draw_text(state, box, glyph, UI_GLYPH_TEXT_SIZE, .Centre, UI_GLYPH_COLOR)
		x -= 3 * UI_GAP
	}
}

// Dock the tooltip to the right of the panel, or to its left, whichever
// has room in the safe area. With room on neither side (a panel as wide
// as the screen) it covers the panel under the focused widget, or above
// it near the bottom. Never outside the safe area.
tooltip_rectangle :: proc(panel, widget, safe: Ui_Rectangle, height: f32) -> Ui_Rectangle {
	width := min(f32(UI_TOOLTIP_WIDTH), safe.width)
	box_height := min(height, safe.height)
	right := panel.x + panel.width + UI_GAP
	left := panel.x - UI_GAP - width
	x, y := right, panel.y
	if right + width > safe.x + safe.width {
		x = left
		if left < safe.x {
			x = widget.x
			y = widget.y + widget.height + UI_GAP
			if y + box_height > safe.y + safe.height {
				y = widget.y - UI_GAP - box_height
			}
		}
	}
	return {clamp(x, safe.x, safe.x + safe.width - width), clamp(y, safe.y, safe.y + safe.height - box_height), width, box_height}
}

// Lines drawn from the top of the area, as many as fit.
draw_text_lines :: proc(state: ^Ui_State, area: Ui_Rectangle, lines: []string, color := UI_TEXT_COLOR) {
	content := area
	for line in lines {
		if content.height < UI_LINE_HEIGHT {
			return
		}
		draw_text(state, cut_top(&content, UI_LINE_HEIGHT), line, UI_BODY_TEXT_SIZE, .Left, color)
	}
}

// The focused widget's tooltip while the info panel is open (Y), wrapped
// to the tooltip's width.
append_tooltip :: proc(state: ^Ui_State) {
	if !state.tooltip_open || state.focused_tooltip == "" {
		return
	}
	focus_index := widget_index(state.widgets[:], state.focus)
	if focus_index < 0 {
		return
	}
	widget := state.widgets[focus_index]
	panel_rectangle := widget.rectangle
	for panel in state.panels {
		if panel.id == widget.panel {
			panel_rectangle = panel.rectangle
		}
	}
	safe := ui_safe_area(state)
	text_width := min(f32(UI_TOOLTIP_WIDTH), safe.width) - 2 * UI_PADDING
	lines := wrap_text(state, state.focused_tooltip, UI_BODY_TEXT_SIZE, text_width)
	box := tooltip_rectangle(panel_rectangle, widget.rectangle, safe, f32(len(lines)) * UI_LINE_HEIGHT + 2 * UI_PADDING)
	draw_fill(state, box, UI_PANEL_COLOR)
	draw_outline(state, box, UI_ACCENT_COLOR)
	draw_text_lines(state, inset(box, UI_PADDING), lines)
}

// Top left, one under the other, each wrapped to at most
// UI_TOAST_MAXIMUM_LINES lines.
append_toasts :: proc(state: ^Ui_State) {
	area := ui_safe_area(state)
	text_width := area.width * UI_TOAST_WIDTH_FRACTION - 2 * UI_PADDING
	vertical_padding := f32(UI_ROW_HEIGHT - UI_LINE_HEIGHT) / 2
	for toast in state.toasts {
		lines := wrap_text_lines(state, toast.text, UI_BODY_TEXT_SIZE, text_width, UI_TOAST_MAXIMUM_LINES)
		if area.height < f32(len(lines)) * UI_LINE_HEIGHT + 2 * vertical_padding {
			return
		}
		widest := f32(0)
		for line in lines {
			widest = max(widest, ui_text_width(state, line, UI_BODY_TEXT_SIZE))
		}
		box := cut_top(&area, f32(len(lines)) * UI_LINE_HEIGHT + 2 * vertical_padding)
		box.width = widest + 2 * UI_PADDING
		draw_fill(state, box, UI_PANEL_COLOR)
		draw_text_lines(state, {box.x + UI_PADDING, box.y + vertical_padding, widest, box.height - 2 * vertical_padding}, lines)
		cut_top(&area, UI_GAP)
	}
}

append_pointer :: proc(state: ^Ui_State) {
	// In the world the right pad turns the camera, so no pointer shows there.
	if state.pointer_source != .Trackpad || state.screens.count == 0 {
		return
	}
	half := f32(UI_POINTER_SIZE / 2)
	box := Ui_Rectangle{state.pointer.x - half, state.pointer.y - half, UI_POINTER_SIZE, UI_POINTER_SIZE}
	draw_fill(state, box, UI_ACCENT_COLOR)
	draw_outline(state, box, UI_PANEL_COLOR)
}

// Drawn last, over every screen.
ui_append_overlays :: proc(state: ^Ui_State) {
	append_tooltip(state)
	append_toasts(state)
	append_pointer(state)
}

// Maps a stick to pad coordinates (0 to 1, y down) so both sources share
// radial_slot_from_touchpad.
stick_to_pad_position :: proc(stick: [2]f32) -> [2]f32 {
	return {0.5 + stick.x * 0.5, 0.5 - stick.y * 0.5}
}

// Touchpad: the highlight follows the finger, the dead centre clears it,
// release selects. Stick: deflection past the dead centre opens the wheel
// and moves the highlight, letting go selects the last highlight.
advance_radial :: proc(radial: Radial_State, touching: bool, position: [2]f32, source: Radial_Source, slot_count: int) -> (Radial_State, Radial_Result) {
	if !touching {
		if radial.open {
			return {}, Radial_Result{closed = true, selected = radial.highlight}
		}
		return {}, Radial_Result{selected = -1}
	}
	result := radial
	if !result.open {
		result = Radial_State{open = true, highlight = -1}
	}
	slot, in_centre := radial_slot_from_touchpad(position.x, position.y, slot_count)
	if source == .Touchpad || !in_centre {
		result.highlight = slot
	}
	return result, Radial_Result{selected = -1}
}

radial_input :: proc(input: Ui_Input, source: Radial_Source) -> (touching: bool, position: [2]f32) {
	switch source {
	case .Touchpad:
		return input.left_touchpad.down, input.left_touchpad.position
	case .Stick:
		position = stick_to_pad_position(input.right_stick)
		offset := position - 0.5
		return offset.x * offset.x + offset.y * offset.y > RADIAL_CENTER_RADIUS * RADIAL_CENTER_RADIUS, position
	case .Held_Button:
		return input.hotbar_radial_down, stick_to_pad_position(input.right_stick)
	}
	return false, {}
}

// A wheel of slots around the screen centre while the pad is touched (or
// the stick deflected). One radial is open at a time.
ui_radial :: proc(state: ^Ui_State, labels: []string, source: Radial_Source) -> Radial_Result {
	touching, position := radial_input(state.input, source)
	result: Radial_Result
	state.radial, result = advance_radial(state.radial, touching, position, source, len(labels))
	if state.radial.open {
		draw_radial(state, labels)
	}
	return result
}

draw_radial :: proc(state: ^Ui_State, labels: []string) {
	centre := state.screen_units / 2
	radius := f32(UI_SLOT_SIZE * 2.5)
	count := len(labels)
	for label, index in labels {
		point := radial_slot_offset(index, count) * radius + centre
		box := Ui_Rectangle{point.x - UI_SLOT_SIZE, point.y - UI_ROW_HEIGHT / 2, UI_SLOT_SIZE * 2, UI_ROW_HEIGHT}
		highlighted := index == state.radial.highlight
		draw_fill(state, box, highlighted ? UI_ACCENT_COLOR : UI_PANEL_COLOR)
		draw_text(state, box, label, UI_BODY_TEXT_SIZE, .Centre, highlighted ? UI_PANEL_COLOR : UI_TEXT_COLOR)
	}
}

// Unit offset of a slot's centre, slot 0 at the top, clockwise, y down.
radial_slot_offset :: proc(index, count: int) -> [2]f32 {
	angle := f32(index) * math.TAU / f32(max(count, 1))
	return {math.sin(angle), -math.cos(angle)}
}
