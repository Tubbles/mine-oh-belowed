package game

import "core:fmt"
import "core:math"
import "core:strings"

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

// Logical buttons the glyph bar can show; glyph shows the control bound
// to each one's action (glyph_action).
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
	// The world's Mine control: a frame cell's pick up (0195).
	Mine,
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

// Registers a focusable widget and reports how it is used this frame:
// activated by Confirm while focused, or by a tap, a press on it released
// over it without leaving the slop (pointer_tapped, 0132). The press
// names the widget; the last one registered under the pointer wins, as in
// widget_under.
ui_interact :: proc(state: ^Ui_State, id: Ui_Id, rectangle: Ui_Rectangle, flags: Ui_Widget_Flags = {}, tooltip := "") -> Ui_Interaction {
	append(&state.widgets, Ui_Widget{id = id, panel = state.current_panel, rectangle = rectangle, flags = flags})
	focused := state.focus == id
	hovered := ui_pointer_over(state, rectangle)
	if focused && tooltip != "" {
		state.focused_tooltip = tooltip
	}
	if hovered && state.click {
		state.pointer_press.widget, state.pointer_press.on_slot = id, .Item_Slot in flags
	}
	tapped := hovered && pointer_tapped(state^, id)
	return Ui_Interaction{focused = focused, hovered = hovered, activated = (focused && state.confirm) || tapped}
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
	knob, known := state.knob_positions[id]
	drawn_last_frame := known && knob.frame + 1 == state.frame_count
	position := drawn_last_frame ? slide_towards(knob.position, target, state.frame_seconds * UI_KNOB_TRAVELS_PER_SECOND) : target
	state.knob_positions[id] = Knob_Position{position, state.frame_count}
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
// focused; a tap on the left half steps down, on the right half up.
// Returns the step's direction, .None for none; the caller steps the
// value, so the id stays with the label.
ui_stepper :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label, value: string, tooltip := "") -> Ui_Direction {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {.Adjusts_Horizontally}, tooltip)
	direction := Ui_Direction.None
	if interaction.focused && (state.navigation_step == .Left || state.navigation_step == .Right) {
		direction = state.navigation_step
	}
	if interaction.hovered && pointer_tapped(state^, id) {
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

// A slider's widget and its geometry for one frame.
Slider :: struct {
	id:          Ui_Id,
	interaction: Ui_Interaction,
	track:       Ui_Rectangle,
	// Where a press takes the value: the track and a padding around it.
	grab:        Ui_Rectangle,
}

SLIDER_VALUE_WIDTH :: UI_BODY_TEXT_SIZE * 4

slider_begin :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label, tooltip: string) -> Slider {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {.Adjusts_Horizontally}, tooltip)
	track := Ui_Rectangle{rectangle.x + rectangle.width * 0.45, rectangle.y + rectangle.height / 2 - 6, rectangle.width * 0.55 - SLIDER_VALUE_WIDTH - 2 * UI_PADDING, 12}
	grab := Ui_Rectangle{track.x - UI_PADDING, rectangle.y, track.width + 2 * UI_PADDING, rectangle.height}
	if state.click && ui_pointer_over(state, grab) {
		state.pointer_press.on_track = true
	}
	return Slider{id, interaction, track, grab}
}

// The value the pointer gives the slider this frame, if any (0132). A
// press on the track decides by its first movement past the slop: along
// the track it is the slider's drag (dragging), whose value follows the
// pointer on the frames it moves, never a still one, so a layout change
// under it changes nothing; across it is the scroll region's drag, and
// the value stays. A release within the slop is a tap, which sets the
// value at the press point.
slider_pointer_value :: proc(state: ^Ui_State, slider: Slider, range: Slider_Range) -> (value: f32, pointed: bool) {
	press := state.pointer_press
	on_track := press.widget == slider.id && press.on_track
	if on_track && press.down && press.moved && press.horizontal {
		state.dragging = slider.id
	}
	switch {
	case on_track && pointer_tapped(state^, slider.id):
		return slider_value_at(slider.track, press.position.x, range), true
	case state.dragging == slider.id && state.pointer_moved:
		return slider_value_at(slider.track, state.pointer.x, range), true
	}
	return 0, false
}

// The release of the slider's drag along the track, this frame.
slider_drag_released :: proc(state: Ui_State, id: Ui_Id) -> bool {
	press := state.pointer_press
	return state.pointer_released && press.widget == id && press.on_track && press.moved && press.horizontal
}

draw_slider :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, slider: Slider, label: string, value: f32, range: Slider_Range, value_text: string) {
	widget_background(state, rectangle, slider.id, slider.interaction)
	label_area := inset(rectangle, UI_PADDING)
	label_area.width = max(slider.track.x - UI_PADDING - label_area.x, 0)
	draw_text_fitted(state, label_area, label, UI_BODY_TEXT_SIZE, .Left)
	draw_fill(state, slider.track, theme_color(state, .Panel))
	filled := slider.track
	filled.width *= slider_fraction(value, range)
	draw_fill(state, filled, theme_color(state, .Accent))
	value_area := Ui_Rectangle{rectangle.x + rectangle.width - UI_PADDING - SLIDER_VALUE_WIDTH, rectangle.y, SLIDER_VALUE_WIDTH, rectangle.height}
	draw_text(state, value_area, value_text, UI_BODY_TEXT_SIZE, .Right)
}

// Label on the left, the track and the value text on the right. Left and
// right step the value while focused; the pointer sets it by a tap or a
// drag along the track (slider_pointer_value).
ui_slider :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, value: ^f32, range: Slider_Range, value_text: string, tooltip := "") -> bool {
	slider := slider_begin(state, rectangle, label, tooltip)
	before := value^
	if slider.interaction.focused {
		value^ = step_slider_value(value^, range, state.navigation_step)
	}
	if pointed, ok := slider_pointer_value(state, slider, range); ok {
		value^ = pointed
	}
	draw_slider(state, rectangle, slider, label, value^, range, value_text)
	return value^ != before
}

// A slider whose value changes the layout (the UI scale, the text scale):
// during a drag along the track the value shown follows the pointer
// (Ui_State.slider_drag_value) but the setting changes only on the
// release, so the layout under the finger holds still and the slider
// tracks it exactly (0132). Steps and a tap apply at once. The value text
// comes from format_value, since it shows the dragged value.
ui_layout_slider :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, value: ^f32, range: Slider_Range, format_value: proc(value: f32) -> string, tooltip := "") -> bool {
	slider := slider_begin(state, rectangle, label, tooltip)
	before := value^
	if slider.interaction.focused {
		value^ = step_slider_value(value^, range, state.navigation_step)
	}
	was_dragging := state.dragging == slider.id
	pointed, ok := slider_pointer_value(state, slider, range)
	// The drag starts with the setting's value, so a drag that begins on a
	// frame without a pointer move (a rescale pushed the press past the
	// slop) never shows or applies an earlier drag's value.
	if state.dragging == slider.id && !was_dragging {
		state.slider_drag_value = value^
	}
	if ok {
		if state.dragging == slider.id {
			state.slider_drag_value = pointed
		} else {
			value^ = pointed
		}
	}
	if slider_drag_released(state^, slider.id) {
		value^ = state.slider_drag_value
	}
	shown := state.dragging == slider.id ? state.slider_drag_value : value^
	draw_slider(state, rectangle, slider, label, shown, range, format_value(shown))
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
		tab := column_rectangle(rectangle, count, index, UI_GAP)
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
	underline := column_rectangle(rectangle, count, selected, UI_GAP)
	draw_fill(state, cut_bottom(&underline, 4), theme.colors[.Accent])
	if mode == .Focus {
		draw_focus_outline(state, rectangle, id)
	}
	state.selections[id] = selected
	return selected
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

// A scrolling vertical list. The right stick, the wheel and a pointer drag
// scroll it like a Scroll_Region and the focus keeps itself in view.
// Returns the activated item or -1.
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
			if !state.focus_scrolled_away {
				scroll = scroll_to_show(scroll, row_top, UI_ROW_HEIGHT, rectangle.height)
			}
		}
		if interaction.activated {
			activated = index
		}
		widget_background(state, row, item_id, interaction)
		draw_text_fitted(state, inset(row, UI_PADDING), item, UI_BODY_TEXT_SIZE, .Left)
	}
	push_command(state, {kind = .Clip_End})
	scroll -= pointer_drag_scroll(state, rectangle)
	if focus_inside || ui_pointer_over(state, rectangle) {
		scroll -= state.input.scroll_stick * UI_LIST_STICK_ROWS_PER_SECOND * UI_ROW_HEIGHT * state.frame_seconds
		scroll -= state.input.scroll_wheel * UI_ROW_HEIGHT
	}
	state.scroll_offsets[list_id] = clamp(scroll, 0, maximum_scroll)
	return activated
}

// A clipped area over content that may be taller: the content moves under
// it by the scroll offset. The right stick and the wheel scroll it while
// the focus or the pointer is inside, a pointer drag that starts inside
// moves it with the pointer (pointer_drag_scroll, 0132), and a focused
// widget inside keeps itself in view, so panels clamped to the safe area
// stay usable with focus navigation alone, until a drag scrolls it away.
// Must not hold a list, since clips do not nest.
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
	scroll := region.scroll - pointer_drag_scroll(state, region.area)
	focus_inside := false
	for widget in state.widgets[region.first_widget:] {
		if widget.id == state.focus {
			focus_inside = true
			if !state.focus_scrolled_away {
				scroll = scroll_to_show(scroll, widget.rectangle.y - content_top, widget.rectangle.height, region.area.height)
			}
		}
	}
	if focus_inside || ui_pointer_over(state, region.area) {
		scroll -= state.input.scroll_stick * UI_LIST_STICK_ROWS_PER_SECOND * UI_ROW_HEIGHT * state.frame_seconds
		scroll -= state.input.scroll_wheel * UI_ROW_HEIGHT
	}
	state.scroll_offsets[region.id] = clamp(scroll, 0, content_height - region.area.height)
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

// A glyph: the pad button's icon, or a key cap (Ui_Icon.Key) with the
// control's label on it.
Glyph :: struct {
	icon:  Ui_Icon,
	label: string,
}

@(rodata)
glyph_button_actions := [Glyph_Button]Action {
	.Confirm        = .Confirm,
	.Back           = .Back,
	.Tab_Previous   = .Tab_Previous,
	.Tab_Next       = .Tab_Next,
	.Info           = .Info_Panel,
	.Context_Action = .Context_Action,
	.Pause          = .Pause,
	.Inventory      = .Open_Inventory,
	.Secondary      = .Menu_Secondary,
	.Interact       = .Interact,
	.Use_Item       = .Use_Item,
	.Sprint         = .Sprint,
	.Quick_Move     = .Menu_Quick_Move,
	.Drop           = .Menu_Drop,
	.Mine           = .Mine,
}

// The action whose control a glyph shows first. On the keyboard Back shows
// Pause's key (Esc), which steps back a screen as Back does
// (handle_screen_keys), and Sprint shows Sprint_Hold, the keyboard's sprint;
// glyph falls back to the button's own action when those have no key.
glyph_action :: proc(device: Input_Device, button: Glyph_Button) -> Action {
	if device == .Keyboard_Mouse && button == .Back {
		return .Pause
	}
	if device == .Keyboard_Mouse && button == .Sprint {
		return .Sprint_Hold
	}
	return glyph_button_actions[button]
}

binding_on_device :: proc(binding: Binding, device: Input_Device) -> bool {
	switch device {
	case .Gamepad:
		return binding.device == .Gamepad
	case .Keyboard_Mouse:
		return binding.device == .Keyboard || binding.device == .Mouse
	}
	return false
}

// The backend reads the binding: it is not limited to the other backend,
// and raylib reads its gamepad control (bind_gamepad_control).
binding_on_backend :: proc(binding: Binding, backend: Input_Backend) -> bool {
	if backend not_in binding.backends {
		return false
	}
	return backend != .Raylib || binding.device != .Gamepad || raylib_reads_gamepad_control(binding.control)
}

// The action's first binding on the device and backend: the glyph bar has
// room for one control per hint.
first_binding_on_device :: proc(bindings: []Binding, action: Action, device: Input_Device, backend: Input_Backend) -> (binding: Binding, found: bool) {
	for candidate in bindings {
		if candidate.action == action && binding_on_backend(candidate, backend) && binding_on_device(candidate, device) {
			return candidate, true
		}
	}
	return {}, false
}

// The icon of a gamepad control that has one.
gamepad_control_icon :: proc(binding: Binding) -> (icon: Ui_Icon, found: bool) {
	if binding.device != .Gamepad {
		return .Key, false
	}
	switch binding.control {
	case "SOUTH":
		return .Button_South, true
	case "EAST":
		return .Button_East, true
	case "WEST":
		return .Button_West, true
	case "NORTH":
		return .Button_North, true
	case "LEFT_SHOULDER":
		return .Bumper_Left, true
	case "RIGHT_SHOULDER":
		return .Bumper_Right, true
	case GAMEPAD_LEFT_TRIGGER_NAME:
		return .Trigger_Left, true
	case GAMEPAD_RIGHT_TRIGGER_NAME:
		return .Trigger_Right, true
	case "LEFT_STICK":
		return .Stick_Left, true
	case "RIGHT_STICK":
		return .Stick_Right, true
	case "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT":
		return .Dpad, true
	case "START":
		return .Menu, true
	case "BACK":
		return .View, true
	}
	return .Key, false
}

Control_Label_Key :: struct {
	device:  Binding_Device,
	control: string,
	key:     string,
}

// The controls whose names read poorly on a key cap, and their labels'
// string keys.
@(rodata)
control_label_keys := [?]Control_Label_Key {
	{.Keyboard, "ENTER", "glyph_keyboard_enter"},
	{.Keyboard, "ESCAPE", "glyph_keyboard_escape"},
	{.Keyboard, "LEFT_SHIFT", "glyph_keyboard_left_shift"},
	{.Keyboard, "LEFT_CONTROL", "glyph_keyboard_left_control"},
	{.Mouse, "LEFT", "glyph_mouse_left"},
	{.Mouse, "RIGHT", "glyph_mouse_right"},
	{.Mouse, "MIDDLE", "glyph_mouse_middle"},
	{.Mouse, "SIDE", "glyph_mouse_side"},
	{.Mouse, "EXTRA", "glyph_mouse_extra"},
	{.Mouse, "FORWARD", "glyph_mouse_forward"},
	{.Mouse, "BACK", "glyph_mouse_back"},
}

// "PAGE_DOWN" as "Page Down" and "LEFT_PADDLE1" as "Left Paddle 1",
// while "F3" stays, in the temp allocator.
readable_control_name :: proc(control: string) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for word, index in strings.split(control, "_", context.temp_allocator) {
		if index > 0 {
			strings.write_byte(&builder, ' ')
		}
		strings.write_string(&builder, readable_control_word(word))
	}
	return strings.to_string(builder)
}

// One word: the first letter kept, the rest lower case, a space before a
// trailing number after more than one letter.
readable_control_word :: proc(word: string) -> string {
	letters_end := len(word)
	for letters_end > 0 && word[letters_end - 1] >= '0' && word[letters_end - 1] <= '9' {
		letters_end -= 1
	}
	first_end := min(1, letters_end)
	letters := strings.concatenate({word[:first_end], strings.to_lower(word[first_end:letters_end], context.temp_allocator)}, context.temp_allocator)
	if letters_end > 1 && letters_end < len(word) {
		return strings.concatenate({letters, " ", word[letters_end:]}, context.temp_allocator)
	}
	return strings.concatenate({letters, word[letters_end:]}, context.temp_allocator)
}

control_label :: proc(binding: Binding) -> string {
	for entry in control_label_keys {
		if entry.device == binding.device && entry.control == binding.control {
			return text(entry.key)
		}
	}
	return readable_control_name(binding.control)
}

// The glyph of the control bound to the button's action on the active
// device (0151): the pad button's icon where it has one, else a key cap
// with the control's label.
glyph :: proc(state: ^Ui_State, button: Glyph_Button) -> Glyph {
	binding, found := first_binding_on_device(state.bindings, glyph_action(state.active_device, button), state.active_device, state.input_backend)
	if !found {
		binding, found = first_binding_on_device(state.bindings, glyph_button_actions[button], state.active_device, state.input_backend)
	}
	if !found {
		return {.Key, text("glyph_unbound")}
	}
	if icon, has_icon := gamepad_control_icon(binding); has_icon {
		return {icon, ""}
	}
	return {.Key, control_label(binding)}
}

UI_GLYPH_BAR_HEIGHT :: UI_GLYPH_TEXT_SIZE + 2 * UI_GAP

// The safe area above the glyph bar, where screens put their panels.
ui_panel_area :: proc(state: ^Ui_State) -> Ui_Rectangle {
	area := ui_safe_area(state)
	cut_bottom(&area, UI_GLYPH_BAR_HEIGHT + 2 * UI_GAP)
	return area
}

// Width of a hint's glyph box: the pad button's square icon, or the key
// cap with the control's label and a margin, at least square.
glyph_box_width :: proc(state: ^Ui_State, button: Glyph_Button) -> f32 {
	shown := glyph(state, button)
	if shown.icon != .Key {
		return UI_GLYPH_BAR_HEIGHT
	}
	return max(ui_text_width(state, shown.label, UI_GLYPH_TEXT_SIZE) + 2 * UI_GAP, UI_GLYPH_BAR_HEIGHT)
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
// the bound pad button's icon on the gamepad, the bound key's name on a
// key cap icon on the keyboard (glyph),
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
		shown := glyph(state, hint.button)
		draw_ui_icon(state, box, shown.icon)
		if shown.icon == .Key {
			draw_text(state, box, shown.label, UI_GLYPH_TEXT_SIZE, .Centre, UI_GLYPH_COLOR)
		}
		x -= 3 * UI_GAP
	}
}

// Buttons without glyphs in the glyph bar's place (the touch row,
// ui_touch_row): right aligned along the bottom of the strip, each
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
		natural[index] = button_natural_width(state, label)
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

// The buttons of the touch row (0125, 0137), in the row's order from the
// left. Back is last, on the right, where the glyph bar's Back sits;
// Clear filter is first, so the panels that have it keep the other
// buttons in the places the other panels have them.
Touch_Button :: enum u8 {
	None,
	Clear_Filter,
	Sort,
	Split,
	Transfer_All,
	Transfer_All_Of_Type,
	Drop,
	Craft,
	Craft_Five,
	Cancel_Craft,
	Choose_Recipe,
	Research,
	Zoom_In,
	Zoom_Out,
	Back,
}

Touch_Buttons :: bit_set[Touch_Button]

// The row of the screens whose only action for a finger is to close.
BACK_TOUCH_BUTTONS :: Touch_Buttons{.Back}

@(rodata)
touch_button_keys := [Touch_Button]string {
	.None                 = "",
	.Clear_Filter         = "touch_button_clear_filter",
	.Sort                 = "slot_button_sort",
	.Split                = "slot_button_split",
	.Transfer_All         = "slot_button_transfer_all",
	.Transfer_All_Of_Type = "slot_button_transfer_all_of_type",
	.Drop                 = "touch_button_drop",
	.Craft                = "touch_button_craft",
	.Craft_Five           = "touch_button_craft_five",
	.Cancel_Craft         = "touch_button_cancel_craft",
	.Choose_Recipe        = "touch_button_choose_recipe",
	.Research             = "touch_button_research",
	.Zoom_In              = "touch_button_zoom_in",
	.Zoom_Out             = "touch_button_zoom_out",
	.Back                 = "touch_button_back",
}

// On Android and with the touch overlay (Ui_Input.pointer_is_touch) the
// screens draw the touch row in the glyph bar's place; the keyboard and
// the gamepad keep the glyph bar.
touch_row_shows :: proc(state: ^Ui_State) -> bool {
	return state.input.pointer_is_touch
}

// The glyph bar, or on touch the row with Back alone: the screens whose
// other glyphs name what a finger does on the screen itself (Select, the
// tabs) or has no use for (Info).
ui_glyph_bar_or_back_row :: proc(state: ^Ui_State, hints: []Glyph_Hint) {
	if touch_row_shows(state) {
		ui_touch_row(state, BACK_TOUCH_BUTTONS)
		return
	}
	ui_glyph_bar(state, hints)
}

// A tap on a list row selects it and commits nothing (0137): on touch,
// an activation without Confirm is a finger's. Confirm (the gamepad's A
// with the touch overlay on) still commits.
tap_selects_only :: proc(state: ^Ui_State) -> bool {
	return touch_row_shows(state) && !state.confirm
}

// The buttons in Touch_Button's order along the bottom of
// touch_row_strip, chosen for the layout's buttons (the widest row the
// screen can show, so a button that comes and goes moves no other); the
// one tapped this frame, .None for none. Back sets the frame's Back,
// which handle_screen_keys takes after the screen as it takes B, so it
// closes every screen as B does, with B's sound (Ui_State.back_tapped).
ui_touch_row :: proc(state: ^Ui_State, buttons: Touch_Buttons, layout: Touch_Buttons = {}) -> Touch_Button {
	shown := make([dynamic]Touch_Button, 0, len(Touch_Button), context.temp_allocator)
	labels := make([dynamic]string, 0, len(Touch_Button), context.temp_allocator)
	for button in buttons - {.None} {
		append(&shown, button)
		append(&labels, text(touch_button_keys[button]))
	}
	layout_width := touch_row_natural_width(state, layout == {} ? buttons : layout)
	pressed := ui_button_bar(state, labels[:], touch_row_strip(ui_safe_area(state), layout_width))
	if pressed < 0 {
		return .None
	}
	if shown[pressed] == .Back {
		state.input.back, state.back_tapped = true, true
	}
	return shown[pressed]
}

// The row's width with every label whole: the natural widths and the gaps.
touch_row_natural_width :: proc(state: ^Ui_State, buttons: Touch_Buttons) -> f32 {
	width := f32(0)
	for button in buttons - {.None} {
		width += button_natural_width(state, text(touch_button_keys[button])) + UI_GAP
	}
	return max(width - UI_GAP, 0)
}

// A bar button as wide as its label and its padding.
button_natural_width :: proc(state: ^Ui_State, label: string) -> f32 {
	return ui_text_width(state, label, UI_BODY_TEXT_SIZE) + 4 * UI_GAP
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

// Unit offset of a slot's centre, slot 0 at the top, clockwise, y down.
radial_slot_offset :: proc(index, count: int) -> [2]f32 {
	angle := f32(index) * math.TAU / f32(max(count, 1))
	return {math.sin(angle), -math.cos(angle)}
}

// A row off the top of the content and the gap below it.
cut_row :: proc(content: ^Ui_Rectangle) -> Ui_Rectangle {
	row := cut_top(content, UI_ROW_HEIGHT)
	cut_top(content, UI_GAP)
	return row
}

panel_height :: proc(row_count: int, extra: f32) -> f32 {
	return f32(row_count) * (UI_ROW_HEIGHT + UI_GAP) + extra + 2 * UI_PADDING
}

// A strip off the top of the content, or false when less is left.
take_line :: proc(content: ^Ui_Rectangle, height: f32) -> (line: Ui_Rectangle, fits: bool) {
	if content.height < height {
		return {}, false
	}
	return cut_top(content, height), true
}

// One line of text, ending with an ellipsis where it does not fit, or
// nothing once the content has no room left.
detail_line :: proc(state: ^Ui_State, content: ^Ui_Rectangle, line: string, color := UI_TEXT_COLOR, height: f32 = UI_ROW_HEIGHT) {
	if row, fits := take_line(content, height); fits {
		draw_text_fitted(state, row, line, UI_BODY_TEXT_SIZE, .Left, color)
	}
}

// Greedy word wrap to a width in UI units, in the temp allocator. A word
// longer than the width gets a line of its own.
wrap_text :: proc(state: ^Ui_State, value: string, size, width: f32) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	line := ""
	for word in strings.fields(value, context.temp_allocator) {
		candidate := line == "" ? word : strings.concatenate({line, " ", word}, context.temp_allocator)
		if line != "" && ui_text_width(state, candidate, size) > width {
			append(&lines, line)
			candidate = word
		}
		line = candidate
	}
	if line != "" {
		append(&lines, line)
	}
	return lines[:]
}

// Wrapped lines from the top of the content, as many as fit.
draw_wrapped :: proc(state: ^Ui_State, content: ^Ui_Rectangle, value: string, color := UI_TEXT_COLOR) {
	for line in wrap_text(state, value, UI_BODY_TEXT_SIZE, content.width) {
		row := take_line(content, UI_LINE_HEIGHT) or_break
		ui_label(state, row, line, UI_BODY_TEXT_SIZE, .Left, color)
	}
}

// A scrolling column of rows. The right stick, the wheel and a pointer
// drag scroll it and a focused row keeps itself in view, until a drag
// scrolls it away, like ui_list.
Scroll_List :: struct {
	id:           Ui_Id,
	area:         Ui_Rectangle,
	scroll:       f32,
	count:        int,
	focus_inside: bool,
	// False after a pointer drag scrolled the focus away (focus_scrolled_away).
	keeps_focus_in_view: bool,
}

scroll_list_begin :: proc(state: ^Ui_State, label: string, area: Ui_Rectangle, count: int) -> Scroll_List {
	id := ui_push_id(state, label)
	push_command(state, {kind = .Clip_Begin, rectangle = area})
	return Scroll_List{id = id, area = area, scroll = state.scroll_offsets[id], count = count, keeps_focus_in_view = !state.focus_scrolled_away}
}

scroll_list_row :: proc(list: Scroll_List, position: int) -> Ui_Rectangle {
	return {list.area.x, list.area.y + f32(position) * UI_ROW_HEIGHT - list.scroll, list.area.width, UI_ROW_HEIGHT}
}

scroll_list_keep_visible :: proc(list: ^Scroll_List, position: int) {
	list.focus_inside = true
	if list.keeps_focus_in_view {
		list.scroll = scroll_to_show(list.scroll, f32(position) * UI_ROW_HEIGHT, UI_ROW_HEIGHT, list.area.height)
	}
}

scroll_list_end :: proc(state: ^Ui_State, list: ^Scroll_List) {
	push_command(state, {kind = .Clip_End})
	list.scroll -= pointer_drag_scroll(state, list.area)
	if list.focus_inside || ui_pointer_over(state, list.area) {
		list.scroll -= state.input.scroll_stick * UI_LIST_STICK_ROWS_PER_SECOND * UI_ROW_HEIGHT * state.frame_seconds
		list.scroll -= state.input.scroll_wheel * UI_ROW_HEIGHT
	}
	maximum_scroll := max(f32(list.count) * UI_ROW_HEIGHT - list.area.height, 0)
	state.scroll_offsets[list.id] = clamp(list.scroll, 0, maximum_scroll)
	ui_pop_id(state)
}
