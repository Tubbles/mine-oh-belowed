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
UI_FOCUS_BORDER :: 4
UI_CHECKBOX_SIZE :: 32
// A toggle's track is this wide and UI_CHECKBOX_SIZE tall; the knob
// slides across it at UI_KNOB_TRAVELS_PER_SECOND.
UI_TOGGLE_WIDTH :: UI_CHECKBOX_SIZE * 7 / 4
UI_TOGGLE_KNOB_INSET :: 6
UI_KNOB_TRAVELS_PER_SECOND :: 8
// The icon before a tab's label.
UI_TAB_ICON_SIZE :: 32
UI_SLOT_SIZE :: 80
UI_SLOT_ICON_INSET :: 12
UI_SLOT_COUNT_TEXT_SIZE :: 24
UI_TOOLTIP_WIDTH :: 420
// Seconds the focus rests on an item slot before its info tooltip shows
// by itself (work item 0094).
UI_TOOLTIP_DELAY :: 0.4
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

// The theme's colours and border (ui_theme.odin) under the names the
// screens use. Variables, not constants: apply_ui_theme sets them from
// the loaded theme on the main thread, between frames. Tests never set
// them, so they read the defaults; a test that needs a theme sets it on
// its Ui_State, which the widgets here read (ui_theme).
UI_BORDER := DEFAULT_UI_THEME.border
UI_PANEL_COLOR := DEFAULT_UI_THEME.colors[.Panel]
UI_PANEL_BORDER_COLOR := DEFAULT_UI_THEME.colors[.Panel_Edge]
UI_WIDGET_COLOR := DEFAULT_UI_THEME.colors[.Widget]
UI_HOVER_COLOR := DEFAULT_UI_THEME.colors[.Widget_Hover]
UI_ACCENT_COLOR := DEFAULT_UI_THEME.colors[.Accent]
UI_TEXT_COLOR := DEFAULT_UI_THEME.colors[.Text]
UI_DIM_TEXT_COLOR := DEFAULT_UI_THEME.colors[.Text_Dim]
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
	// Menu_Drop in the inventory (0090): the right stick click.
	Drop,
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

draw_circle :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, color: Ui_Color) {
	push_command(state, {kind = .Circle, rectangle = rectangle, color = color})
}

draw_ring :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, color: Ui_Color, thickness: f32 = UI_BORDER) {
	push_command(state, {kind = .Ring, rectangle = rectangle, color = color, thickness = thickness})
}

draw_arc :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, color: Ui_Color, thickness, sweep: f32) {
	push_command(state, {kind = .Arc, rectangle = rectangle, color = color, thickness = thickness, sweep = clamp(sweep, 0, 1)})
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

// The icon atlas tile of a Ui_Icon, stretched over the rectangle.
draw_ui_icon :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, icon: Ui_Icon) {
	push_command(state, {kind = .Ui_Icon, rectangle = rectangle, tile = int(icon)})
}

// The focus outline grows inwards with the pulse, so it never leaves the
// widget's rectangle.
focus_outline_thickness :: proc(theme: Ui_Theme, pulse: f32) -> f32 {
	return UI_FOCUS_BORDER + theme.focus_pulse * clamp(pulse, 0, 1)
}

draw_focus_outline :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id) {
	theme := ui_theme(state)
	push_command(state, {kind = .Focus_Outline, rectangle = rectangle, color = theme.colors[.Focus], thickness = focus_outline_thickness(theme, state.focus_pulse), widget = id})
}

// Panel art (work item 0071). A panel is a fill, an edge line and a
// highlight line one border inside it, with the corners cut by the
// theme's corner: square notches, so the shape is three fills and its
// lines are straight pieces. The pieces never overlap, since the fill and
// the lines may be translucent.

// The corner a rectangle can take with lines of the thickness, 0 when it
// is too small for one.
fitted_corner :: proc(rectangle: Ui_Rectangle, corner, thickness: f32) -> f32 {
	if corner <= 0 {
		return 0
	}
	fitted := min(max(corner, thickness), (min(rectangle.width, rectangle.height) - 2 * thickness) / 2)
	return fitted >= thickness ? fitted : 0
}

// The centre column and the two side strips.
cut_corner_fills :: proc(rectangle: Ui_Rectangle, corner: f32) -> [3]Ui_Rectangle {
	x, y, width, height, c := rectangle.x, rectangle.y, rectangle.width, rectangle.height, corner
	return {{x + c, y, width - 2 * c, height}, {x, y + c, c, height - 2 * c}, {x + width - c, y + c, c, height - 2 * c}}
}

// The outline of cut_corner_fills' shape, thickness wide, inside it:
// the four sides and two pieces per notch.
cut_corner_frame :: proc(rectangle: Ui_Rectangle, corner, thickness: f32) -> [12]Ui_Rectangle {
	x, y, width, height, c, b := rectangle.x, rectangle.y, rectangle.width, rectangle.height, corner, thickness
	right, bottom := x + width, y + height
	return {
		{x + c, y, width - 2 * c, b},
		{x + c, bottom - b, width - 2 * c, b},
		{x, y + c + b, b, height - 2 * c - 2 * b},
		{right - b, y + c + b, b, height - 2 * c - 2 * b},
		{x + c, y + b, b, c - b},
		{x, y + c, c + b, b},
		{x + c, bottom - c, b, c - b},
		{x, bottom - c - b, c + b, b},
		{right - c - b, y + b, b, c - b},
		{right - c - b, y + c, c + b, b},
		{right - c - b, bottom - c, b, c - b},
		{right - c - b, bottom - c - b, c + b, b},
	}
}

draw_cut_corner_frame :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, corner, thickness: f32, color: Ui_Color) {
	if color.a == 0 || thickness <= 0 {
		return
	}
	if corner <= 0 {
		draw_outline(state, rectangle, color, thickness)
		return
	}
	for piece in cut_corner_frame(rectangle, corner, thickness) {
		draw_fill(state, piece, color)
	}
}

// With the default theme (square corners, no highlight) this is the fill
// and the outline panels always had.
draw_panel_art :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, fill, edge: Ui_Color) {
	theme := ui_theme(state)
	corner := fitted_corner(rectangle, theme.corner, theme.border)
	if corner <= 0 {
		draw_fill(state, rectangle, fill)
	} else {
		for part in cut_corner_fills(rectangle, corner) {
			draw_fill(state, part, fill)
		}
	}
	draw_cut_corner_frame(state, rectangle, corner, theme.border, edge)
	highlight := inset(rectangle, theme.border)
	draw_cut_corner_frame(state, highlight, fitted_corner(highlight, corner, theme.border), theme.border, theme.colors[.Panel_Highlight])
}

// A line in the divider colour, nothing when its alpha is 0.
draw_divider :: proc(state: ^Ui_State, line: Ui_Rectangle) {
	if color := theme_color(state, .Divider); color.a > 0 {
		draw_fill(state, line, color)
	}
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
	draw_panel_art(state, rectangle, theme_color(state, .Panel), theme_color(state, .Panel_Edge))
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

// Held down: Confirm on the focused widget, or the pointer on the hovered one.
widget_pressed :: proc(state: ^Ui_State, interaction: Ui_Interaction) -> bool {
	return (interaction.focused && state.input.confirm_down) || (interaction.hovered && state.pointer_held)
}

// Pressed, then hovered, then plain. A pressed colour with alpha 0
// leaves the pressed state out.
widget_fill_color :: proc(theme: Ui_Theme, hovered, pressed: bool) -> Ui_Color {
	if pressed && theme.colors[.Widget_Active].a > 0 {
		return theme.colors[.Widget_Active]
	}
	return hovered ? theme.colors[.Widget_Hover] : theme.colors[.Widget]
}

widget_background :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id, interaction: Ui_Interaction) {
	draw_fill(state, rectangle, widget_fill_color(ui_theme(state), interaction.hovered, widget_pressed(state, interaction)))
	draw_focus_outline(state, rectangle, id)
}

ui_button :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, tooltip := "") -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {}, tooltip)
	widget_background(state, rectangle, id, interaction)
	draw_text_fitted(state, inset(rectangle, UI_GAP), label, UI_BODY_TEXT_SIZE, .Centre)
	return interaction.activated
}

// Moves from current towards target by at most step.
slide_towards :: proc(current, target, step: f32) -> f32 {
	if current < target {
		return min(current + step, target)
	}
	return max(current - step, target)
}

// The knob inside the track at position 0 (left, off) to 1 (right, on).
toggle_knob_rectangle :: proc(track: Ui_Rectangle, position: f32) -> Ui_Rectangle {
	knob := inset(track, UI_TOGGLE_KNOB_INSET)
	knob.width = knob.height
	knob.x += (track.width - 2 * UI_TOGGLE_KNOB_INSET - knob.width) * clamp(position, 0, 1)
	return knob
}

// Label on the left, a switch on the right: a track, filled in the accent
// while on, and a knob that slides to the side of the value. Returns true
// when flipped.
ui_toggle :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, value: ^bool, tooltip := "") -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {}, tooltip)
	if interaction.activated {
		value^ = !value^
	}
	theme := ui_theme(state)
	widget_background(state, rectangle, id, interaction)
	label_area := inset(rectangle, UI_PADDING)
	label_area.width = max(label_area.width - UI_TOGGLE_WIDTH - UI_GAP, 0)
	draw_text_fitted(state, label_area, label, UI_BODY_TEXT_SIZE, .Left)
	track := Ui_Rectangle {
		rectangle.x + rectangle.width - UI_PADDING - UI_TOGGLE_WIDTH,
		rectangle.y + (rectangle.height - UI_CHECKBOX_SIZE) / 2,
		UI_TOGGLE_WIDTH,
		UI_CHECKBOX_SIZE,
	}
	target := f32(value^ ? 1 : 0)
	position, known := state.knob_positions[id]
	position = known ? slide_towards(position, target, state.frame_seconds * UI_KNOB_TRAVELS_PER_SECOND) : target
	state.knob_positions[id] = position
	draw_fill(state, track, value^ ? theme.colors[.Accent] : theme.colors[.Panel])
	draw_outline(state, track, theme.colors[.Text], theme.border)
	draw_fill(state, toggle_knob_rectangle(track, position), theme.colors[.Text])
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

// Label on the left, "<  value  >" on the right (the texture editor's
// seed, the touch layout editor's values). Left and right step while
// focused; a click on the left half steps down, on the right half up.
// Returns the step's direction, .None for none; the caller steps the
// value, so the id stays with the label.
ui_stepper :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label, value: string, tooltip := "") -> Ui_Direction {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {.Adjusts_Horizontally}, tooltip)
	direction := Ui_Direction.None
	if interaction.focused && (state.navigation_step == .Left || state.navigation_step == .Right) {
		direction = state.navigation_step
	}
	if interaction.hovered && state.click {
		direction = state.pointer.x < rectangle_centre(rectangle).x ? .Left : .Right
	}
	widget_background(state, rectangle, id, interaction)
	content := inset(rectangle, UI_PADDING)
	value_text := fit_text(state, strings.concatenate({"<  ", value, "  >"}, context.temp_allocator), UI_BODY_TEXT_SIZE, content.width / 2)
	draw_text(state, content, value_text, UI_BODY_TEXT_SIZE, .Right)
	content.width = max(content.width - ui_text_width(state, value_text, UI_BODY_TEXT_SIZE) - UI_GAP, 0)
	draw_text_fitted(state, content, label, UI_BODY_TEXT_SIZE, .Left)
	return direction
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
	draw_fill(state, track, theme_color(state, .Panel))
	filled := track
	filled.width *= slider_fraction(value^, range)
	draw_fill(state, filled, theme_color(state, .Accent))
	value_area := Ui_Rectangle{rectangle.x + rectangle.width - UI_PADDING - value_width, rectangle.y, value_width, rectangle.height}
	draw_text(state, value_area, value_text, UI_BODY_TEXT_SIZE, .Right)
	return value^ != before
}

// A tab's icon and label, centred together; the label ends with an
// ellipsis where it does not fit.
draw_tab_label :: proc(state: ^Ui_State, tab: Ui_Rectangle, label: string, icon: Maybe(Ui_Icon), color: Ui_Color) {
	content := inset(tab, UI_GAP)
	chosen, has_icon := icon.?
	if !has_icon || content.width < UI_TAB_ICON_SIZE + UI_GAP || content.height < UI_TAB_ICON_SIZE {
		draw_text_fitted(state, content, label, UI_BODY_TEXT_SIZE, .Centre, color)
		return
	}
	fitted := fit_text(state, label, UI_BODY_TEXT_SIZE, content.width - UI_TAB_ICON_SIZE - UI_GAP)
	text_width := fitted == "" ? 0 : ui_text_width(state, fitted, UI_BODY_TEXT_SIZE)
	group_width := UI_TAB_ICON_SIZE + (fitted == "" ? 0 : UI_GAP + text_width)
	x := content.x + (content.width - group_width) / 2
	draw_ui_icon(state, {x, content.y + (content.height - UI_TAB_ICON_SIZE) / 2, UI_TAB_ICON_SIZE, UI_TAB_ICON_SIZE}, chosen)
	if fitted != "" {
		draw_text(state, {x + UI_TAB_ICON_SIZE + UI_GAP, content.y, text_width, content.height}, fitted, UI_BODY_TEXT_SIZE, .Left, color)
	}
}

// How a tab strip is stepped. Bumpers: the bumpers cycle the tabs and the
// strip is not a focus target, so the stick moves only between the
// widgets of the open tab. Focus: the strip is one focusable row, left
// and right step the tabs while it holds the focus, up and down leave it,
// and the bumpers are left to another strip (the recipe categories under
// the inventory tab strip, work item 0094).
Ui_Tabs_Mode :: enum u8 {
	Bumpers,
	Focus,
}

// The selection after one frame's steps, wrapping.
step_tab_selection :: proc(selected, count: int, previous, next: bool) -> int {
	result := selected
	if previous {
		result = (result + count - 1) % count
	}
	if next {
		result = (result + 1) % count
	}
	return result
}

// The pointer picks a tab in either mode. The selection lives in the UI
// state under the tab strip's id. icons, when given, holds one icon per
// tab, drawn before its label.
ui_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, labels: []string, icons: []Ui_Icon = nil, mode := Ui_Tabs_Mode.Bumpers) -> int {
	id := ui_id(state, label)
	count := len(labels)
	if count == 0 {
		return 0
	}
	selected := clamp(state.selections[id], 0, count - 1)
	switch mode {
	case .Bumpers:
		selected = step_tab_selection(selected, count, state.input.tab_previous, state.input.tab_next)
	case .Focus:
		interaction := ui_interact(state, id, rectangle, {.Adjusts_Horizontally})
		step := interaction.focused ? state.navigation_step : .None
		selected = step_tab_selection(selected, count, step == .Left, step == .Right)
	}
	theme := ui_theme(state)
	for tab_label, index in labels {
		tab := column(rectangle, count, index, UI_GAP)
		if state.click && ui_pointer_over(state, tab) {
			selected = index
		}
		hovered := ui_pointer_over(state, tab)
		draw_fill(state, tab, widget_fill_color(theme, hovered, hovered && state.pointer_held))
		icon: Maybe(Ui_Icon)
		if index < len(icons) {
			icon = icons[index]
		}
		draw_tab_label(state, tab, tab_label, icon, index == selected ? theme.colors[.Accent] : theme.colors[.Text_Dim])
	}
	strip := rectangle
	draw_divider(state, cut_bottom(&strip, theme.border))
	underline := column(rectangle, count, selected, UI_GAP)
	draw_fill(state, cut_bottom(&underline, 4), theme.colors[.Accent])
	if mode == .Focus {
		draw_focus_outline(state, rectangle, id)
	}
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

// The item's icon tile, its block's atlas tile, or a coloured square with
// two letters.
draw_item_icon :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, icon: Item_Icon) {
	switch icon.kind {
	case .Item_Tile:
		push_command(state, {kind = .Item_Tile, rectangle = rectangle, tile = icon.tile})
	case .Block_Tile:
		push_command(state, {kind = .Atlas_Tile, rectangle = rectangle, tile = icon.tile})
	case .Lettered:
		letters := icon.letters
		draw_fill(state, rectangle, icon.color)
		draw_outline(state, rectangle, theme_color(state, .Panel))
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

// The pointer moves stacks by drag and drop (Slot_Drag, 0124): a press
// names the slot for the drag and activates nothing, the slot under a
// drag's release takes the drop.
ui_item_slot :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id, stack: Item_Stack, items: Item_Registry) -> Ui_Interaction {
	interaction := ui_interact(state, id, rectangle, {.Tooltip_Shows_Itself, .Item_Slot}, item_stack_tooltip(stack, items))
	if interaction.hovered && state.click {
		state.slot_drag.slot, state.slot_drag.count = id, stack.count
	}
	interaction.activated = (interaction.focused && state.confirm) || (interaction.hovered && state.slot_drag.released)
	widget_background(state, rectangle, id, interaction)
	draw_outline(state, rectangle, theme_color(state, .Panel_Edge), ui_theme(state).border)
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
	theme := ui_theme(state)
	draw_fill(state, rectangle, theme.colors[.Widget])
	filled := rectangle
	filled.width *= clamp(fraction, 0, 1)
	draw_fill(state, filled, theme.colors[.Accent])
	draw_outline(state, rectangle, theme.colors[.Panel_Edge], theme.border)
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
		case .Drop:
			return "glyph_gamepad_drop"
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
		case .Drop:
			return "glyph_keyboard_drop"
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

// The icon of a button's glyph: the pad button on the gamepad, the blank
// key cap the key's name is drawn on for the keyboard and mouse.
glyph_icon :: proc(device: Input_Device, button: Glyph_Button) -> Ui_Icon {
	if device == .Keyboard_Mouse {
		return .Key
	}
	switch button {
	case .Confirm, .Interact:
		return .Button_South
	case .Back:
		return .Button_East
	case .Context_Action, .Inventory:
		return .Button_West
	case .Info:
		return .Button_North
	case .Tab_Previous:
		return .Bumper_Left
	case .Tab_Next:
		return .Bumper_Right
	case .Secondary, .Use_Item:
		return .Trigger_Left
	case .Quick_Move:
		return .Trigger_Right
	case .Sprint:
		return .Stick_Left
	case .Drop:
		return .Stick_Right
	case .Pause:
		return .Menu
	}
	return .Key
}

// Width of a hint's glyph box: the pad button's square icon, or the key
// cap with the key's name and a margin, at least square.
glyph_box_width :: proc(state: ^Ui_State, button: Glyph_Button) -> f32 {
	if state.active_device == .Gamepad {
		return UI_GLYPH_BAR_HEIGHT
	}
	glyph := text(glyph_key(state.active_device, button))
	return max(ui_text_width(state, glyph, UI_GLYPH_TEXT_SIZE) + 2 * UI_GAP, UI_GLYPH_BAR_HEIGHT)
}

glyph_bar_width :: proc(state: ^Ui_State, hints: []Glyph_Hint) -> f32 {
	width := f32(0)
	for hint, index in hints {
		width += glyph_box_width(state, hint.button) + UI_GAP + ui_text_width(state, hint.label, UI_GLYPH_TEXT_SIZE)
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

// Glyph and label pairs, right aligned along the bottom of the safe area:
// the pad button's icon on the gamepad, the key's name on a key cap
// icon on the keyboard,
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
		box_width := glyph_box_width(state, hint.button)
		x -= box_width + UI_GAP
		box := Ui_Rectangle{x, y, box_width, height}
		draw_ui_icon(state, box, glyph_icon(state.active_device, hint.button))
		if state.active_device == .Keyboard_Mouse {
			draw_text(state, box, text(glyph_key(state.active_device, hint.button)), UI_GLYPH_TEXT_SIZE, .Centre, UI_GLYPH_COLOR)
		}
		x -= 3 * UI_GAP
	}
}

// Buttons without glyphs in the glyph bar's place (the touch row of the
// slot screens, 0125): right aligned along the bottom of the strip, each
// as wide as its label while they fit, else narrowed by
// fit_button_widths with the labels cut short (draw_text_fitted), in
// the glyph bar's panel. The index of the one activated this frame, -1
// for none.
ui_button_bar :: proc(state: ^Ui_State, labels: []string, strip: Ui_Rectangle) -> int {
	area := ui_safe_area(state)
	outer_panel := state.current_panel
	append(&state.panels, Ui_Panel{id = UI_GLYPH_BAR_PANEL, rectangle = area})
	state.current_panel = UI_GLYPH_BAR_PANEL
	defer state.current_panel = outer_panel
	natural := make([]f32, len(labels), context.temp_allocator)
	for label, index in labels {
		natural[index] = ui_text_width(state, label, UI_BODY_TEXT_SIZE) + 4 * UI_GAP
	}
	widths := fit_button_widths(natural, strip.width - f32(max(len(labels) - 1, 0)) * UI_GAP)
	height := f32(UI_GLYPH_BAR_HEIGHT)
	x := strip.x + strip.width
	pressed := -1
	#reverse for label, index in labels {
		x -= widths[index]
		if ui_button(state, {x, strip.y + strip.height - height, widths[index], height}, label) {
			pressed = index
		}
		x -= UI_GAP
	}
	return pressed
}

// The natural widths while they fit the available width; otherwise the
// widest are capped first at one common width, so short labels keep
// theirs. In the temp allocator.
fit_button_widths :: proc(natural: []f32, available: f32) -> []f32 {
	widths := make([]f32, len(natural), context.temp_allocator)
	copy(widths, natural)
	if math.sum(natural) <= available || len(natural) == 0 {
		return widths
	}
	cap := available / f32(len(natural))
	// Each pass settles at least one more button under the cap.
	for _ in natural {
		room, uncapped := available, 0
		for width in natural {
			if width <= cap {
				room -= width
			} else {
				uncapped += 1
			}
		}
		cap = room / f32(max(uncapped, 1))
	}
	for &width in widths {
		width = min(width, cap)
	}
	return widths
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

// Whether the focused widget's tooltip shows: while the info panel is
// open (Y), or on a widget whose tooltip shows by itself once the focus
// has rested on it for UI_TOOLTIP_DELAY.
tooltip_shows :: proc(state: Ui_State, widget: Ui_Widget) -> bool {
	if state.focused_tooltip == "" {
		return false
	}
	if state.tooltip_open {
		return true
	}
	rested := state.focus_rest_id == state.focus && state.focus_rest_seconds >= UI_TOOLTIP_DELAY
	return .Tooltip_Shows_Itself in widget.flags && rested
}

// The focused widget's tooltip (tooltip_shows), wrapped to the tooltip's
// width.
append_tooltip :: proc(state: ^Ui_State) {
	focus_index := widget_index(state.widgets[:], state.focus)
	if focus_index < 0 || !tooltip_shows(state^, state.widgets[focus_index]) {
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
	draw_panel_art(state, box, theme_color(state, .Tooltip), theme_color(state, .Accent))
	draw_text_lines(state, inset(box, UI_PADDING), lines)
}

// Top left, one under the other, each wrapped to at most
// UI_TOAST_MAXIMUM_LINES lines, below Mission Control's panel while it
// shows (toast_top_offset).
append_toasts :: proc(state: ^Ui_State) {
	area := ui_safe_area(state)
	cut_top(&area, state.toast_top_offset)
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
		draw_fill(state, box, theme_color(state, .Toast))
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
	draw_fill(state, box, theme_color(state, .Accent))
	draw_outline(state, box, theme_color(state, .Panel))
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
	theme := ui_theme(state)
	for label, index in labels {
		point := radial_slot_offset(index, count) * radius + centre
		box := Ui_Rectangle{point.x - UI_SLOT_SIZE, point.y - UI_ROW_HEIGHT / 2, UI_SLOT_SIZE * 2, UI_ROW_HEIGHT}
		highlighted := index == state.radial.highlight
		draw_fill(state, box, highlighted ? theme.colors[.Accent] : theme.colors[.Panel])
		draw_text(state, box, label, UI_BODY_TEXT_SIZE, .Centre, highlighted ? theme.colors[.Panel] : theme.colors[.Text])
	}
}

// Unit offset of a slot's centre, slot 0 at the top, clockwise, y down.
radial_slot_offset :: proc(index, count: int) -> [2]f32 {
	angle := f32(index) * math.TAU / f32(max(count, 1))
	return {math.sin(angle), -math.cos(angle)}
}
