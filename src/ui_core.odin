package game

import "core:hash"
import "core:math"
import "core:strings"

// The immediate mode UI from doc/ui.md. A frame is ui_begin, widget calls
// that append widgets and draw commands, then ui_end, which resolves focus
// and hover (ui_resolve, pure) and executes the draw list (ui_draw.odin, the
// only part that calls raylib).
//
// Widgets read the focus resolved in the previous frame, so a focus move
// shows up in widget results one frame late. Draw commands that depend on
// focus carry the widget id and are styled at execution time, so the
// highlight itself is drawn in the frame the move is resolved.

// Layout happens in UI units: 1080 of them span the screen height at UI
// scale 1. The draw layer converts to pixels.
UI_UNITS_PER_SCREEN_HEIGHT :: 1080
UI_SAFE_AREA_FRACTION :: 0.05
UI_REPEAT_INITIAL_SECONDS :: 0.35
UI_REPEAT_STEP_SECONDS :: 0.08
UI_STICK_NAVIGATION_THRESHOLD :: 0.5
// Weight of the sideways offset against the distance along the pressed
// direction, so a widget straight ahead beats a nearer one off to the side.
UI_FOCUS_PERPENDICULAR_PENALTY :: 2.0
UI_ID_STACK_CAPACITY :: 16
UI_TOAST_CAPACITY :: 4
UI_TOAST_SECONDS :: 4.0
UI_SCREEN_STACK_CAPACITY :: 8

Ui_Id :: distinct u64

Ui_Rectangle :: struct {
	x, y, width, height: f32,
}

Ui_Color :: [4]u8

Ui_Direction :: enum u8 {
	None,
	Up,
	Down,
	Left,
	Right,
}

Ui_Widget_Flag :: enum u8 {
	// Left and right change the widget's value instead of moving the focus.
	Adjusts_Horizontally,
}

Ui_Widget_Flags :: bit_set[Ui_Widget_Flag]

Ui_Widget :: struct {
	id:        Ui_Id,
	panel:     Ui_Id,
	rectangle: Ui_Rectangle,
	flags:     Ui_Widget_Flags,
}

Ui_Panel :: struct {
	id:        Ui_Id,
	rectangle: Ui_Rectangle,
}

Input_Device :: enum u8 {
	Keyboard_Mouse,
	Gamepad,
}

Pointer_Source :: enum u8 {
	// The sticks or the d-pad moved last, the pointer is hidden.
	None,
	Mouse,
	Trackpad,
}

// What the UI reads from one frame of input, built by make_ui_input.
// Booleans without _down are edges.
Ui_Input :: struct {
	navigation:     Ui_Direction,
	confirm:        bool,
	back:           bool,
	pause:          bool,
	tab_previous:   bool,
	tab_next:       bool,
	info:           bool,
	context_action: bool,
	// L2 or Left Shift: split the focused stack.
	secondary:      bool,
	open_inventory: bool,
	open_recipes:   bool,
	open_journal:   bool,
	open_power:     bool,
	open_statistics: bool,
	open_technologies: bool,
	open_map:       bool,
	// The left stick (or the movement keys), for panning the map.
	move:           [2]f32,
	// A letter key pressed this frame (lower case), 0 for none.
	typed_letter:   rune,
	// Printable characters a physical keyboard typed this frame, and the
	// Backspace and Enter keys, for text fields.
	typed_text:        [RAW_TEXT_CAPACITY]u8,
	typed_text_length: int,
	backspace_key:     bool,
	enter_key:         bool,
	// Held, not an edge: Confirm without the pad click, for the distribute gesture.
	confirm_down:   bool,
	// Held, not an edge: the keyboard radial shows while Tab is down.
	hotbar_radial_down: bool,
	mouse_position: [2]f32,
	mouse_moved:    bool,
	mouse_pressed:  bool,
	mouse_down:     bool,
	// Right trackpad movement in pad widths.
	trackpad_delta: [2]f32,
	pad_pressed:    bool,
	pad_down:       bool,
	// List scrolling: the right stick as a rate (up positive), the wheel in notches.
	scroll_stick:   f32,
	scroll_wheel:   f32,
	left_touchpad:  Touchpad_Finger,
	right_stick:    [2]f32,
	device:         Input_Device,
	device_seen:    bool,
}

Draw_Command_Kind :: enum u8 {
	Fill,
	Outline,
	Text,
	// Drawn only when the widget holds the focus at execution time.
	Focus_Outline,
	Clip_Begin,
	Clip_End,
	// The block atlas tile `tile`, stretched over the rectangle.
	Atlas_Tile,
	// An RGBA image of image_size pixels, stretched over the rectangle;
	// the draw layer uploads it again whenever image_revision changes.
	Image,
}

Text_Alignment :: enum u8 {
	Left,
	Centre,
	Right,
}

Draw_Command :: struct {
	kind:      Draw_Command_Kind,
	rectangle: Ui_Rectangle,
	color:     Ui_Color,
	thickness: f32,
	text:      string,
	text_size: f32,
	alignment: Text_Alignment,
	widget:    Ui_Id,
	tile:      int,
	pixels:         []Ui_Color,
	image_size:     [2]i32,
	image_revision: u64,
}

Repeat_State :: struct {
	direction:         Ui_Direction,
	held_seconds:      f32,
	next_step_seconds: f32,
}

Toast :: struct {
	text:              string,
	remaining_seconds: f32,
}

Screen :: enum u8 {
	None,
	Pause,
	Settings,
	// Developer mode's shortcuts (ui_developer.odin), above the pause menu.
	Developer,
	Inventory,
	// The panel of the player's open_machine.
	Machine,
	Recipes,
	Journal,
	Power,
	Statistics,
	Technologies,
	// The top down map (ui_map.odin).
	Map,
	// The title and its screens, shown while no world is played.
	Title,
	New_World,
	Load_World,
	Confirm_Delete,
}

Screen_Stack :: struct {
	screens: [UI_SCREEN_STACK_CAPACITY]Screen,
	count:   int,
}

Radial_Source :: enum u8 {
	Touchpad,
	Stick,
	// Shown while a button is held, the right stick moves the highlight,
	// releasing the button selects.
	Held_Button,
}

Radial_State :: struct {
	open:      bool,
	highlight: int,
}

// Width of a text in UI units at a size in UI units.
Measure_Text_Proc :: #type proc(text: string, size: f32) -> f32

Ui_State :: struct {
	input:            Ui_Input,
	frame_seconds:    f32,
	pixels_per_unit:  f32,
	screen_units:     [2]f32,
	measure_text:     Measure_Text_Proc,
	// Screen heights the pointer crosses per trackpad width.
	pointer_speed:    f32,
	// Focus and pointer, persistent across frames.
	focus:            Ui_Id,
	requested_focus:  Ui_Id,
	hovered:          Ui_Id,
	dragging:         Ui_Id,
	repeat:           Repeat_State,
	pointer:          [2]f32,
	pointer_source:   Pointer_Source,
	pointer_moved:    bool,
	active_device:    Input_Device,
	tooltip_open:     bool,
	letter_jump:      rune,
	screens:          Screen_Stack,
	radial:           Radial_State,
	// The on-screen keyboard. While it is open, B, X and Y belong to it.
	keyboard:         Keyboard_State,
	distribute:       Distribute_Gesture,
	toasts:           [dynamic]Toast,
	scroll_offsets:   map[Ui_Id]f32,
	selections:       map[Ui_Id]int,
	// Derived in ui_begin for this frame.
	navigation_step:  Ui_Direction,
	confirm:          bool,
	click:            bool,
	pointer_held:     bool,
	// Collected by widget calls this frame.
	id_stack:         [UI_ID_STACK_CAPACITY]Ui_Id,
	id_depth:         int,
	current_panel:    Ui_Id,
	focused_tooltip:  string,
	widgets:          [dynamic]Ui_Widget,
	panels:           [dynamic]Ui_Panel,
	draw_list:        [dynamic]Draw_Command,
}

destroy_ui_state :: proc(state: ^Ui_State) {
	for toast in state.toasts {
		delete(toast.text)
	}
	delete(state.toasts)
	delete(state.scroll_offsets)
	delete(state.selections)
	delete(state.widgets)
	delete(state.panels)
	delete(state.draw_list)
}

ui_pixels_per_unit :: proc(screen_height_pixels, ui_scale: f32) -> f32 {
	return max(screen_height_pixels, 1) * ui_scale / UI_UNITS_PER_SCREEN_HEIGHT
}

ui_screen_units :: proc(screen_pixels: [2]f32, pixels_per_unit: f32) -> [2]f32 {
	return screen_pixels / pixels_per_unit
}

// Id 0 means no widget, so a hash that lands on it moves to 1.
ui_hash :: proc(parent: Ui_Id, label: string, index: int) -> Ui_Id {
	seed := hash.fnv64a(transmute([]byte)label, u64(parent) ~ 0xcbf29ce484222325)
	index_bytes := transmute([8]byte)i64(index)
	id := Ui_Id(hash.fnv64a(index_bytes[:], seed))
	return id == 0 ? 1 : id
}

ui_id :: proc(state: ^Ui_State, label: string, index := -1) -> Ui_Id {
	parent := state.id_depth > 0 ? state.id_stack[state.id_depth - 1] : Ui_Id(0)
	return ui_hash(parent, label, index)
}

// Scopes widget ids, so that the rows of two lists with equal labels differ.
ui_push_id :: proc(state: ^Ui_State, label: string, index := -1) -> Ui_Id {
	id := ui_id(state, label, index)
	assert(state.id_depth < UI_ID_STACK_CAPACITY, "ui id stack overflow")
	state.id_stack[state.id_depth] = id
	state.id_depth += 1
	return id
}

ui_pop_id :: proc(state: ^Ui_State) {
	assert(state.id_depth > 0, "ui id stack underflow")
	state.id_depth -= 1
}

rectangle_contains :: proc(rectangle: Ui_Rectangle, point: [2]f32) -> bool {
	return(
		point.x >= rectangle.x &&
		point.x < rectangle.x + rectangle.width &&
		point.y >= rectangle.y &&
		point.y < rectangle.y + rectangle.height \
	)
}

rectangle_centre :: proc(rectangle: Ui_Rectangle) -> [2]f32 {
	return {rectangle.x + rectangle.width / 2, rectangle.y + rectangle.height / 2}
}

direction_vector :: proc(direction: Ui_Direction) -> [2]f32 {
	switch direction {
	case .None:
		return {}
	case .Up:
		return {0, -1}
	case .Down:
		return {0, 1}
	case .Left:
		return {-1, 0}
	case .Right:
		return {1, 0}
	}
	return {}
}

// Returns the new repeat state and whether the held direction steps this
// frame: at once on a new direction, after the initial delay, then every
// step interval.
advance_repeat :: proc(repeat: Repeat_State, direction: Ui_Direction, seconds: f32) -> (Repeat_State, bool) {
	if direction == .None {
		return {}, false
	}
	if direction != repeat.direction {
		return Repeat_State{direction = direction, next_step_seconds = UI_REPEAT_INITIAL_SECONDS}, true
	}
	result := repeat
	result.held_seconds += seconds
	if result.held_seconds < result.next_step_seconds {
		return result, false
	}
	result.next_step_seconds += UI_REPEAT_STEP_SECONDS
	return result, true
}

// Score of moving the focus from `from` to `to`: distance along the
// direction plus the penalised sideways offset. `along` is negative for
// widgets behind.
focus_score :: proc(from, to: Ui_Rectangle, direction: Ui_Direction) -> (along: f32, perpendicular: f32) {
	offset := rectangle_centre(to) - rectangle_centre(from)
	vector := direction_vector(direction)
	along = offset.x * vector.x + offset.y * vector.y
	perpendicular = abs(offset.x * vector.y - offset.y * vector.x)
	return
}

// The nearest widget of the focused widget's panel in the direction, or,
// when there is none, the one farthest behind (wrapping to the far side).
find_focus_neighbour :: proc(widgets: []Ui_Widget, focus_index: int, direction: Ui_Direction) -> (index: int, found: bool) {
	from := widgets[focus_index]
	best_ahead, best_behind := max(f32), max(f32)
	index_ahead, index_behind := -1, -1
	for widget, candidate in widgets {
		if candidate == focus_index || widget.panel != from.panel {
			continue
		}
		along, perpendicular := focus_score(from.rectangle, widget.rectangle, direction)
		penalty := perpendicular * UI_FOCUS_PERPENDICULAR_PENALTY
		if along > 0 && along + penalty < best_ahead {
			best_ahead, index_ahead = along + penalty, candidate
		} else if along <= 0 && along + penalty < best_behind {
			best_behind, index_behind = along + penalty, candidate
		}
	}
	if index_ahead >= 0 {
		return index_ahead, true
	}
	return index_behind, index_behind >= 0
}

widget_index :: proc(widgets: []Ui_Widget, id: Ui_Id) -> int {
	for widget, index in widgets {
		if widget.id == id {
			return index
		}
	}
	return -1
}

// The last widget registered under the point, since later widgets draw on top.
widget_under :: proc(widgets: []Ui_Widget, point: [2]f32) -> Ui_Id {
	#reverse for widget in widgets {
		if rectangle_contains(widget.rectangle, point) {
			return widget.id
		}
	}
	return 0
}

// Mouse sets the pointer directly, the trackpad moves it relatively, and a
// focus step with the sticks or d-pad hides it again.
update_pointer :: proc(state: ^Ui_State) {
	input := state.input
	state.pointer_moved = false
	if input.mouse_moved || input.mouse_pressed {
		state.pointer = input.mouse_position / state.pixels_per_unit
		state.pointer_source = .Mouse
		state.pointer_moved = input.mouse_moved
	} else if input.trackpad_delta != {} {
		moved := state.pointer + input.trackpad_delta * state.pointer_speed * state.screen_units.y
		state.pointer = {clamp(moved.x, 0, state.screen_units.x), clamp(moved.y, 0, state.screen_units.y)}
		state.pointer_source = .Trackpad
		state.pointer_moved = true
	}
	if state.navigation_step != .None {
		state.pointer_source = .None
	}
}

advance_toasts :: proc(state: ^Ui_State, seconds: f32) {
	index := 0
	for index < len(state.toasts) {
		state.toasts[index].remaining_seconds -= seconds
		if state.toasts[index].remaining_seconds > 0 {
			index += 1
			continue
		}
		delete(state.toasts[index].text)
		ordered_remove(&state.toasts, index)
	}
}

// Shown top left for a few seconds. The text is copied.
ui_toast :: proc(state: ^Ui_State, text: string) {
	if len(state.toasts) == UI_TOAST_CAPACITY {
		delete(state.toasts[0].text)
		ordered_remove(&state.toasts, 0)
	}
	append(&state.toasts, Toast{text = strings.clone(text), remaining_seconds = UI_TOAST_SECONDS})
}

ui_begin :: proc(state: ^Ui_State, input: Ui_Input, screen_pixels: [2]f32, frame_seconds, ui_scale, pointer_speed: f32) {
	state.input = input
	state.frame_seconds = frame_seconds
	state.pointer_speed = pointer_speed
	state.pixels_per_unit = ui_pixels_per_unit(screen_pixels.y, ui_scale)
	state.screen_units = ui_screen_units(screen_pixels, state.pixels_per_unit)
	clear(&state.widgets)
	clear(&state.panels)
	clear(&state.draw_list)
	state.id_depth = 0
	state.current_panel = 0
	state.focused_tooltip = ""
	if input.device_seen {
		state.active_device = input.device
	}
	step: bool
	state.repeat, step = advance_repeat(state.repeat, input.navigation, frame_seconds)
	state.navigation_step = step ? input.navigation : .None
	pointer_was_hidden := state.pointer_source == .None
	update_pointer(state)
	// A pad click with the pointer hidden confirms the focused widget
	// instead of clicking at a stale pointer position.
	pad_confirms := input.pad_pressed && pointer_was_hidden && state.pointer_source == .None
	state.confirm = input.confirm || pad_confirms
	state.click = input.mouse_pressed || (input.pad_pressed && !pad_confirms)
	state.pointer_held = input.mouse_down || input.pad_down
	if !state.pointer_held {
		state.dragging = 0
	}
	// Y rotates the held building in the world, so it opens the info panel
	// only on a screen.
	if state.screens.count == 0 {
		state.tooltip_open = false
	} else if input.info && state.keyboard.field == 0 {
		state.tooltip_open = !state.tooltip_open
	}
	advance_toasts(state, frame_seconds)
}

// Focus fallback, hover, then the focus step. Pure: tests run it instead of ui_end.
ui_resolve :: proc(state: ^Ui_State) {
	widgets := state.widgets[:]
	state.hovered = state.pointer_source == .None ? 0 : widget_under(widgets, state.pointer)
	if state.pointer_moved && state.hovered != 0 {
		state.focus = state.hovered
	}
	if state.requested_focus != 0 && widget_index(widgets, state.requested_focus) >= 0 {
		state.focus = state.requested_focus
	}
	state.requested_focus = 0
	state.letter_jump = 0
	focus_index := widget_index(widgets, state.focus)
	if focus_index < 0 {
		state.focus = len(widgets) > 0 ? widgets[0].id : 0
		return
	}
	if !focus_step_allowed(widgets[focus_index], state.navigation_step) {
		return
	}
	if neighbour, found := find_focus_neighbour(widgets, focus_index, state.navigation_step); found {
		state.focus = widgets[neighbour].id
	}
}

focus_step_allowed :: proc(focused: Ui_Widget, step: Ui_Direction) -> bool {
	switch step {
	case .None:
		return false
	case .Left, .Right:
		return .Adjusts_Horizontally not_in focused.flags
	case .Up, .Down:
		return true
	}
	return false
}

ui_end :: proc(state: ^Ui_State, atlas: Icon_Atlas, images: ^Ui_Image_Cache) {
	ui_resolve(state)
	ui_append_overlays(state)
	execute_draw_list(state^, atlas, images)
}

// Layout helpers.

ui_safe_area :: proc(state: ^Ui_State) -> Ui_Rectangle {
	margin := state.screen_units * UI_SAFE_AREA_FRACTION
	return {margin.x, margin.y, state.screen_units.x - 2 * margin.x, state.screen_units.y - 2 * margin.y}
}

centred_rectangle :: proc(area: Ui_Rectangle, width, height: f32) -> Ui_Rectangle {
	return {area.x + (area.width - width) / 2, area.y + (area.height - height) / 2, width, height}
}

// Takes a strip off the top of the area and returns it.
cut_top :: proc(area: ^Ui_Rectangle, height: f32) -> Ui_Rectangle {
	strip := Ui_Rectangle{area.x, area.y, area.width, min(height, area.height)}
	area.y += strip.height
	area.height -= strip.height
	return strip
}

cut_bottom :: proc(area: ^Ui_Rectangle, height: f32) -> Ui_Rectangle {
	strip_height := min(height, area.height)
	area.height -= strip_height
	return {area.x, area.y + area.height, area.width, strip_height}
}

// Takes a strip off the left of the area and returns it.
cut_left :: proc(area: ^Ui_Rectangle, width: f32) -> Ui_Rectangle {
	strip := Ui_Rectangle{area.x, area.y, min(width, area.width), area.height}
	area.x += strip.width
	area.width -= strip.width
	return strip
}

inset :: proc(rectangle: Ui_Rectangle, margin: f32) -> Ui_Rectangle {
	return {rectangle.x + margin, rectangle.y + margin, max(rectangle.width - 2 * margin, 0), max(rectangle.height - 2 * margin, 0)}
}

column :: proc(rectangle: Ui_Rectangle, count, index: int, gap: f32) -> Ui_Rectangle {
	width := (rectangle.width - gap * f32(count - 1)) / f32(count)
	return {rectangle.x + f32(index) * (width + gap), rectangle.y, width, rectangle.height}
}

// Rough width of the default font, for tests and before a window exists.
approximate_text_width :: proc(text: string, size: f32) -> f32 {
	return f32(strings.rune_count(text)) * size * 0.55
}

ui_text_width :: proc(state: ^Ui_State, text: string, size: f32) -> f32 {
	if state.measure_text == nil {
		return approximate_text_width(text, size)
	}
	return state.measure_text(text, size)
}

// Screen stack.

push_screen :: proc(stack: ^Screen_Stack, screen: Screen) {
	if stack.count < UI_SCREEN_STACK_CAPACITY {
		stack.screens[stack.count] = screen
		stack.count += 1
	}
}

pop_screen :: proc(stack: ^Screen_Stack) {
	stack.count = max(stack.count - 1, 0)
}

top_screen :: proc(stack: Screen_Stack) -> Screen {
	return stack.count > 0 ? stack.screens[stack.count - 1] : .None
}

screen_pauses_simulation :: proc(screen: Screen) -> bool {
	switch screen {
	case .None, .Inventory, .Machine, .Recipes, .Journal, .Power, .Statistics, .Technologies, .Map:
		return false
	case .Pause, .Settings, .Developer, .Title, .New_World, .Load_World, .Confirm_Delete:
		return true
	}
	return false
}

// Panels that do not pause (inventory, machines) still keep the world
// from reading movement, mining and placing.
ui_blocks_world :: proc(stack: Screen_Stack) -> bool {
	return stack.count > 0
}

ui_pauses_simulation :: proc(stack: Screen_Stack) -> bool {
	for index in 0 ..< stack.count {
		if screen_pauses_simulation(stack.screens[index]) {
			return true
		}
	}
	return false
}

// Keeps a value on the slider's step grid.
snap_to_step :: proc(value, minimum, step: f32) -> f32 {
	if step <= 0 {
		return value
	}
	return minimum + math.round((value - minimum) / step) * step
}
