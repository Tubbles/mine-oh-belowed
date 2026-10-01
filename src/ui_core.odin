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
	// Up and down do likewise (the touch layout editor's selected element,
	// which the d-pad moves, 0121).
	Adjusts_Vertically,
	// The tooltip shows once the focus has rested on the widget for
	// UI_TOOLTIP_DELAY, without the Info toggle (item slots, work item 0094).
	Tooltip_Shows_Itself,
	// An item slot: the pointer moves its stack by drag and drop, and a
	// press on it is no click (Slot_Drag, 0124).
	Item_Slot,
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
	// The mouse's pointer when it is a finger (Ui_Input.pointer_is_touch):
	// a dragged stack sits above it (held_stack_rectangle, 0124).
	Touch,
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
	// R2 or Q: quick move the focused stack in a machine panel (0078).
	quick_move:     bool,
	// Right stick click or X in the inventory: drop the held or focused
	// stack on the ground (Menu_Drop, 0062).
	drop:           bool,
	// Held, not an edge: holding the quick move moves every stack.
	quick_move_down: bool,
	// Held, not an edge: Left Control, which makes a click a quick move.
	quick_move_modifier: bool,
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
	// Printable characters a physical keyboard typed this frame (on
	// Android with TEXT_BACKSPACE among them), and the Backspace and Enter
	// keys, for text fields.
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
	// The mouse's pointer is a finger: on Android, and while the touch
	// overlay is on (run_ui_frame, 0124).
	pointer_is_touch: bool,
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
	// The item atlas tile `tile` (render_icons.odin), stretched over the
	// rectangle.
	Item_Tile,
	// An RGBA image of image_size pixels, stretched over the rectangle;
	// the draw layer uploads it again whenever image_revision changes.
	Image,
	// The UI icon atlas tile `tile` (a Ui_Icon, ui_theme.odin), stretched
	// over the rectangle.
	Ui_Icon,
	// A filled circle, and a circle's outline of thickness, inside the
	// rectangle (the touch overlay, touch_overlay.odin).
	Circle,
	Ring,
	// A ring's arc of thickness, the share sweep of the circle clockwise
	// from the top (the HUD's mining ring, hud.odin).
	Arc,
}

Text_Alignment :: enum u8 {
	Left,
	Centre,
	Right,
}

// Headings and emphasised lines use the family's bold file (ui_font.odin).
Font_Weight :: enum u8 {
	Regular,
	Bold,
}

Draw_Command :: struct {
	kind:      Draw_Command_Kind,
	rectangle: Ui_Rectangle,
	color:     Ui_Color,
	thickness: f32,
	text:      string,
	text_size: f32,
	weight:    Font_Weight,
	alignment: Text_Alignment,
	widget:    Ui_Id,
	// The panel open when the command was pushed (0 outside panels), so
	// the bounds audit can check that a panel's content stays inside it.
	panel:     Ui_Id,
	tile:      int,
	pixels:         []Ui_Color,
	image_size:     [2]i32,
	image_revision: u64,
	sweep:          f32,
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
	// The texture editor (ui_texture_editor.odin), above the Developer
	// screen.
	Textures,
	// The data file browser (ui_data_browser.odin, work item 0129), above
	// the Developer screen.
	Data_Files,
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
	// The touch layout editor (ui_touch_layout_editor.odin, 0121), above
	// the settings.
	Touch_Layout,
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

// UI units the pointer may move from where it pressed before the press
// is a drag rather than a tap (0124): a finger wobbles a little in a tap.
UI_SLOT_DRAG_SLOP :: 16

Slot_Drag_Phase :: enum u8 {
	None,
	// Down, neither moved past the slop nor rested TOUCH_HOLD_SECONDS on
	// a stack yet.
	Pressed,
	// A stack follows the pointer until it lifts.
	Dragging,
}

// The pointer moves item stacks by drag and drop (0124). ui_begin starts
// and steps it (advance_slot_drag), ui_item_slot names the pressed slot
// and takes the drop, finish_slot_drag (ui_inventory.odin) returns what
// is still held when it ends.
Slot_Drag :: struct {
	phase:          Slot_Drag_Phase,
	// The pressed slot and its stack's count, 0 for a press off the slots.
	slot:           Ui_Id,
	count:          u16,
	press_position: [2]f32,
	held_seconds:   f32,
	// The pointer left the slop since the press, so it is no tap.
	moved:          bool,
	// The press landed off the screen's content (pointer_outside_screen).
	outside:        bool,
	// This frame only: the pointer lifted from a drag, and the slot under
	// it takes the drop.
	released:       bool,
	// Written by finish_slot_drag on every frame of a slot screen: a stack
	// is held, and where the dragged stack came from.
	holding:        bool,
	origin_slot:    int,
}

// A pointer press (0132). ui_begin starts and steps it
// (advance_pointer_press), ui_interact names the widget it landed on.
// Releasing over that widget without having left UI_SLOT_DRAG_SLOP is a
// tap, which activates it (pointer_tapped); a press in a scroll region
// that leaves the slop scrolls the region instead (pointer_drag_scroll).
Pointer_Press :: struct {
	down:          bool,
	widget:        Ui_Id,
	// The pressed widget is an item slot, whose drag moves the stack
	// (Slot_Drag, 0124) rather than scrolling.
	on_slot:       bool,
	// The press landed on a slider's track (slider_begin), and whether the
	// first movement past the slop ran more along x than y: a slider takes
	// such a drag, a scroll region the others (slider_pointer_value).
	on_track:      bool,
	horizontal:    bool,
	position:      [2]f32,
	// The pointer at the end of the last frame of the drag.
	last_position: [2]f32,
	moved:         bool,
	// A scroll region follows this press's drag: the focus stays where it
	// was meanwhile.
	scrolling:     bool,
}

// A toggle's knob and the frame it was last drawn in (frame_count). A
// knob not drawn last frame starts at its value instead of sliding from
// where its screen left it (0132): a value changed while the screen was
// closed would otherwise slide into place as the screen opens, which
// reads as the toggle flipping on entry.
Knob_Position :: struct {
	position: f32,
	frame:    u64,
}

Radial_Source :: enum u8 {
	Touchpad,
	Stick,
	// Shown while a button is held, the right stick moves the highlight,
	// releasing the button selects.
	Held_Button,
}

// Width in UI units of a text at a size in UI units, measured with the
// fonts (measure_font_text in the game).
Measure_Text_Proc :: #type proc(fonts: ^Font_Cache, text: string, size: f32, weight: Font_Weight, pixels_per_unit: f32) -> f32

Radial_State :: struct {
	open:      bool,
	highlight: int,
}

// What the UI asks the mixer to play (work item 0068): a focus move, an
// activation, a back press on a screen, and the chimes of a Mission
// Control line starting and of a discovery card (work item 0069).
// Recorded here, drained by the frame loop (play_ui_sounds), so the UI
// never calls audio itself.
Ui_Sound_Event :: enum u8 {
	Move,
	Confirm,
	Back,
	Mission_Control,
	Discovery,
}

// The accessibility settings the UI reads (work item 0074), handed to
// ui_begin each frame. text_scale multiplies every text size, measured
// and drawn, on top of the UI scale: the layout keeps its sizes, so large
// text fills more of each row and fit_text shortens more. reduced_motion
// holds the focus outline's pulse still and shows Mission Control's lines
// whole. palette picks the map's marker colours (ui_map.odin).
Ui_Accessibility :: struct {
	text_scale:     f32,
	reduced_motion: bool,
	palette:        Marker_Palette,
}

DEFAULT_UI_ACCESSIBILITY :: Ui_Accessibility {
	text_scale = 1,
}

ui_accessibility :: proc(settings: Settings) -> Ui_Accessibility {
	return Ui_Accessibility{text_scale = settings.text_scale, reduced_motion = settings.reduced_motion, palette = settings.palette}
}

Ui_State :: struct {
	// The theme (ui_theme.odin, apply_ui_theme); read through ui_theme,
	// which gives the defaults while none is set.
	theme:            Maybe(Ui_Theme),
	input:            Ui_Input,
	frame_seconds:    f32,
	pixels_per_unit:  f32,
	accessibility:    Ui_Accessibility,
	screen_units:     [2]f32,
	// The fonts text is measured and drawn with (ui_font.odin). Both are
	// nil in headless tests, which measure with approximate_text_width
	// and so never link raylib.
	fonts:            ^Font_Cache,
	measure_text:     Measure_Text_Proc,
	// Screen heights the pointer crosses per trackpad width.
	pointer_speed:    f32,
	// Focus and pointer, persistent across frames.
	focus:            Ui_Id,
	requested_focus:  Ui_Id,
	// How long the focus has stayed on focus_rest_id, for the tooltips
	// that show by themselves (Tooltip_Shows_Itself).
	focus_rest_id:      Ui_Id,
	focus_rest_seconds: f32,
	hovered:          Ui_Id,
	dragging:         Ui_Id,
	slot_drag:        Slot_Drag,
	pointer_press:    Pointer_Press,
	// A pointer drag scrolled since the focus last moved, so the scroll
	// regions leave the focused widget where the drag put it instead of
	// keeping it in view.
	focus_scrolled_away: bool,
	// The value a layout slider shows during its drag (ui_layout_slider).
	slider_drag_value: f32,
	repeat:           Repeat_State,
	pointer:          [2]f32,
	pointer_source:   Pointer_Source,
	pointer_moved:    bool,
	active_device:    Input_Device,
	// The effective bindings and the input backend, whose controls the
	// glyphs show (glyph). Set by the frame loop.
	bindings:         []Binding,
	input_backend:    Input_Backend,
	tooltip_open:     bool,
	screens:          Screen_Stack,
	radial:           Radial_State,
	// The on-screen keyboard. While it is open, B, X and Y belong to it.
	keyboard:         Keyboard_State,
	// A text field opens the system keyboard (open_keyboard, work item
	// 0133): one is available and settings.on_screen_keyboard is system.
	// Set by the frame loop.
	system_keyboard:  bool,
	distribute:       Distribute_Gesture,
	quick_move:       Quick_Move_State,
	// The slot screens' active grid (0125), forgotten with the focus.
	active_slot:      Active_Slot,
	toasts:           [dynamic]Toast,
	// Mission Control's panel and the discovery card (ui_mission_control.odin).
	mission_control:  Mission_Control_State,
	// Set by the HUD while the Mission Control panel shows, so the toasts
	// start below it; cleared by ui_begin.
	toast_top_offset: f32,
	// Filled by ui_begin and ui_resolve, emptied by the frame loop.
	sound_events:     bit_set[Ui_Sound_Event],
	// This frame only: the touch row's Back was tapped (ui_touch_row), so
	// the tap sounds as Back, not as Confirm.
	back_tapped:      bool,
	scroll_offsets:   map[Ui_Id]f32,
	selections:       map[Ui_Id]int,
	// Where each toggle's knob is, 0 off to 1 on, sliding towards its value.
	knob_positions:   map[Ui_Id]Knob_Position,
	// Counts ui_begin calls, so a knob knows whether it was drawn last frame.
	frame_count:      u64,
	// The focus outline's pulse: the seconds into the current pulse, and
	// its phase for this frame (focus_pulse_phase), 0 thinnest to 1 thickest.
	focus_pulse_seconds: f32,
	focus_pulse:      f32,
	// Derived in ui_begin for this frame.
	navigation_step:  Ui_Direction,
	confirm:          bool,
	click:            bool,
	pointer_held:     bool,
	// The pointer press ended this frame (pointer_tapped reads it).
	pointer_released: bool,
	// The pointer's movement this frame while its press is a drag.
	pointer_drag:     [2]f32,
	// Collected by widget calls this frame.
	id_stack:         [UI_ID_STACK_CAPACITY]Ui_Id,
	id_depth:         int,
	current_panel:    Ui_Id,
	focused_tooltip:  string,
	// The widget the fallback focuses when the focus belongs to no widget
	// of the frame (ui_prefer_focus), cleared by ui_begin.
	preferred_focus:  Ui_Id,
	widgets:          [dynamic]Ui_Widget,
	panels:           [dynamic]Ui_Panel,
	draw_list:        [dynamic]Draw_Command,
}

destroy_ui_state :: proc(state: ^Ui_State) {
	for toast in state.toasts {
		delete(toast.text)
	}
	delete(state.toasts)
	destroy_mission_control(&state.mission_control)
	delete(state.scroll_offsets)
	delete(state.selections)
	delete(state.knob_positions)
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

// Whether the two rectangles share some of their extent across the
// direction: a row for left and right, a column for up and down.
focus_extents_overlap :: proc(from, to: Ui_Rectangle, direction: Ui_Direction) -> bool {
	if direction == .Left || direction == .Right {
		return to.y < from.y + from.height && from.y < to.y + to.height
	}
	return to.x < from.x + from.width && from.x < to.x + to.width
}

// The first pass of the focus step: among the widgets of the focused
// widget's panel ahead in the direction and in its row or column
// (focus_extents_overlap), the nearest along the direction, ties to the
// smallest sideways offset.
find_focus_in_line :: proc(widgets: []Ui_Widget, focus_index: int, direction: Ui_Direction) -> (index: int, found: bool) {
	from := widgets[focus_index]
	best_along, best_perpendicular := max(f32), max(f32)
	index = -1
	for widget, candidate in widgets {
		if candidate == focus_index || widget.panel != from.panel || !focus_extents_overlap(from.rectangle, widget.rectangle, direction) {
			continue
		}
		along, perpendicular := focus_score(from.rectangle, widget.rectangle, direction)
		if along > 0 && (along < best_along || (along == best_along && perpendicular < best_perpendicular)) {
			best_along, best_perpendicular, index = along, perpendicular, candidate
		}
	}
	return index, index >= 0
}

// The second pass: the nearest widget of the panel in the direction by
// the weighted score, or, when there is none, the one farthest behind
// (wrapping to the far side).
find_focus_by_score :: proc(widgets: []Ui_Widget, focus_index: int, direction: Ui_Direction) -> (index: int, found: bool) {
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

// The next widget in the direction (work item 0093): the nearest in the
// focused widget's row or column when one lies ahead there, so a step
// right stays in the row even when the row below holds a nearer centre,
// otherwise the weighted score across the panel with its wrap.
find_focus_neighbour :: proc(widgets: []Ui_Widget, focus_index: int, direction: Ui_Direction) -> (index: int, found: bool) {
	if index, found = find_focus_in_line(widgets, focus_index, direction); found {
		return index, found
	}
	return find_focus_by_score(widgets, focus_index, direction)
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
		state.pointer_source = input.pointer_is_touch ? .Touch : .Mouse
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

// A UI scale change moves the pointer's unit position under a pointer
// that stays put, and update_pointer reads the mouse only when it moves
// or presses, so the stored positions follow the new scale (0132).
rescale_pointer :: proc(state: ^Ui_State, pixels_per_unit: f32) {
	if state.pixels_per_unit <= 0 || pixels_per_unit == state.pixels_per_unit {
		return
	}
	factor := state.pixels_per_unit / pixels_per_unit
	state.pointer *= factor
	state.pointer_press.position *= factor
	state.pointer_press.last_position *= factor
	state.slot_drag.press_position *= factor
}

// Steps the pointer press (0132) before the widgets run: a click starts
// it, leaving the slop makes it a drag whose movement this frame is
// pointer_drag, and lifting ends it, which is pointer_released for this
// frame.
advance_pointer_press :: proc(state: ^Ui_State) {
	press := &state.pointer_press
	state.pointer_released, state.pointer_drag = false, {}
	if state.click {
		press^ = Pointer_Press{down = true, position = state.pointer, last_position = state.pointer}
		return
	}
	if !press.down {
		return
	}
	if !press.moved && slot_drag_moved(press.position, state.pointer) {
		offset := state.pointer - press.position
		press.moved, press.horizontal = true, abs(offset.x) > abs(offset.y)
	}
	if press.moved {
		state.pointer_drag = state.pointer - press.last_position
		press.last_position = state.pointer
	}
	if !state.pointer_held {
		press.down, state.pointer_released = false, true
	}
}

// The pointer lifted this frame from a press on the widget that never
// left the slop: a tap, the pointer's activation (0132).
pointer_tapped :: proc(state: Ui_State, id: Ui_Id) -> bool {
	press := state.pointer_press
	return state.pointer_released && !press.moved && press.widget == id
}

// A scroll region's drag this frame (0132): the pointer's vertical
// movement while a press that landed in the area is a drag, 0 otherwise.
// Not for a press on an item slot, whose drag moves the stack, nor one a
// slider (a drag along its track) or an editor element holds (dragging).
pointer_drag_scroll :: proc(state: ^Ui_State, area: Ui_Rectangle) -> f32 {
	press := state.pointer_press
	slider_drag := press.on_track && press.horizontal
	if !press.down || !press.moved || press.on_slot || slider_drag || state.dragging != 0 || !rectangle_contains(area, press.position) {
		return 0
	}
	state.pointer_press.scrolling, state.focus_scrolled_away = true, true
	return state.pointer_drag.y
}

// A scroll drag is under way, its release frame included.
pointer_scrolling :: proc(state: Ui_State) -> bool {
	return state.pointer_press.scrolling && (state.pointer_press.down || state.pointer_released)
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

ui_begin :: proc(state: ^Ui_State, input: Ui_Input, screen_pixels: [2]f32, frame_seconds, ui_scale, pointer_speed: f32, accessibility := DEFAULT_UI_ACCESSIBILITY) {
	state.input = input
	state.frame_count += 1
	state.frame_seconds = frame_seconds
	state.pointer_speed = pointer_speed
	state.accessibility = accessibility
	pixels_per_unit := ui_pixels_per_unit(screen_pixels.y, ui_scale)
	rescale_pointer(state, pixels_per_unit)
	state.pixels_per_unit = pixels_per_unit
	state.screen_units = ui_screen_units(screen_pixels, state.pixels_per_unit)
	state.id_depth = 0
	state.current_panel = 0
	state.focused_tooltip = ""
	state.preferred_focus = 0
	state.focus_rest_id, state.focus_rest_seconds = advance_focus_rest(state.focus_rest_id, state.focus_rest_seconds, state.focus, frame_seconds)
	if input.device_seen {
		state.active_device = input.device
	}
	step: bool
	state.repeat, step = advance_repeat(state.repeat, input.navigation, frame_seconds)
	state.navigation_step = step ? input.navigation : .None
	// A step keeps the focused widget in view again, also one that keeps
	// the focus (a slider, a stepper).
	if state.navigation_step != .None {
		state.focus_scrolled_away = false
	}
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
	advance_pointer_press(state)
	// Before the clear: it reads the last frame's panels and widgets.
	advance_slot_drag(state)
	clear(&state.widgets)
	clear(&state.panels)
	clear(&state.draw_list)
	// Y rotates the held building in the world, so it opens the info panel
	// only on a screen.
	if state.screens.count == 0 {
		state.tooltip_open = false
	} else if input.info && state.keyboard.field == 0 {
		state.tooltip_open = !state.tooltip_open
	}
	// The state's input: a tap off the screen sets Back (end_slot_drag).
	if state.input.back && state.screens.count > 0 && top_screen(state.screens) != .Title {
		state.sound_events += {.Back}
	}
	advance_toasts(state, frame_seconds)
	state.focus_pulse_seconds = math.mod(state.focus_pulse_seconds + frame_seconds, UI_FOCUS_PULSE_SECONDS)
	state.focus_pulse = still_focus_pulse(focus_pulse_phase(state.focus_pulse_seconds), accessibility.reduced_motion)
	state.toast_top_offset = 0
	state.back_tapped = false
	state.sound_events += advance_mission_control(&state.mission_control, frame_seconds, accessibility.reduced_motion)
}

// Steps the slot drag (0124) before the widgets run. A press starts it,
// a drag at once when a stack is held already (the gamepad picked it
// up); while it is down, moving past the slop picks the pressed stack up
// and resting on a stack of two or more splits it; lifting ends it.
// A click with Left Control is a quick move of the slot under the
// pointer, which it focuses, and starts no drag.
advance_slot_drag :: proc(state: ^Ui_State) {
	holding := state.slot_drag.holding
	state.slot_drag.holding, state.slot_drag.released = false, false
	switch {
	case state.click && state.input.quick_move_modifier:
		state.slot_drag = {}
		if pressed := widget_under(state.widgets[:], state.pointer); pressed != 0 {
			state.focus = pressed
		}
	case state.click:
		state.slot_drag = start_slot_drag(state^, holding)
	case state.slot_drag.phase == .None:
	case !state.pointer_held:
		end_slot_drag(state, holding)
	case:
		step_slot_drag(state)
	}
}

start_slot_drag :: proc(state: Ui_State, holding: bool) -> Slot_Drag {
	return Slot_Drag {
		phase = holding ? .Dragging : .Pressed,
		press_position = state.pointer,
		outside = pointer_outside_screen(state),
		origin_slot = state.slot_drag.origin_slot,
	}
}

slot_drag_moved :: proc(press_position, pointer: [2]f32) -> bool {
	offset := pointer - press_position
	return offset.x * offset.x + offset.y * offset.y > UI_SLOT_DRAG_SLOP * UI_SLOT_DRAG_SLOP
}

// The pick up is Confirm on the pressed slot, the split Menu_Secondary
// on it, so every slot screen applies them as it applies the gamepad's.
step_slot_drag :: proc(state: ^Ui_State) {
	drag := &state.slot_drag
	drag.held_seconds += state.frame_seconds
	drag.moved = drag.moved || slot_drag_moved(drag.press_position, state.pointer)
	if drag.phase != .Pressed || drag.slot == 0 {
		return
	}
	switch {
	case drag.moved && drag.count > 0:
		state.focus, state.confirm = drag.slot, true
		drag.phase = .Dragging
	case drag.held_seconds >= TOUCH_HOLD_SECONDS && drag.count >= 2:
		state.focus, state.input.secondary = drag.slot, true
		state.sound_events += {.Confirm}
		drag.phase = .Dragging
	}
}

// A drag ends in a drop (released) while a stack is held, a tap on a
// slot focuses it, and a tap off the screen's content closes the screen
// as Back does.
end_slot_drag :: proc(state: ^Ui_State, holding: bool) {
	drag := state.slot_drag
	state.slot_drag.phase = .None
	switch {
	case drag.phase == .Dragging:
		state.slot_drag.released = holding
	case drag.moved:
	case drag.slot != 0:
		state.focus = drag.slot
	case drag.outside && pointer_outside_screen(state^) && outside_tap_closes_screen(state^):
		state.input.back = true
	}
}

// Every screen with a panel (0137): the pause menu resumes, the settings
// return to what opened them, the confirm dialog says No. Not while the
// keyboard is open: with the system keyboard the tap ends the entry
// (ui_on_screen_keyboard) and the next one closes the screen.
outside_tap_closes_screen :: proc(state: Ui_State) -> bool {
	return screen_closes_on_outside_tap(top_screen(state.screens)) && state.keyboard.field == 0
}

// The title has nothing to close, and the touch layout editor's elements
// cover the whole screen, so a tap beside its panel edits the layout.
screen_closes_on_outside_tap :: proc(screen: Screen) -> bool {
	#partial switch screen {
	case .None, .Title, .Touch_Layout:
		return false
	}
	return true
}

// Whether the pointer lies off the screen's content: outside every panel
// (but the glyph bar's, which spans the safe area for the focus only),
// every widget, and the bottom strip of the glyph bar and the HUD's
// hotbar. Reads the last frame's panels and widgets; false before a
// screen drew any.
pointer_outside_screen :: proc(state: Ui_State) -> bool {
	if len(state.panels) == 0 || widget_under(state.widgets[:], state.pointer) != 0 {
		return false
	}
	for panel in state.panels {
		if panel.id != UI_GLYPH_BAR_PANEL && rectangle_contains(panel.rectangle, state.pointer) {
			return false
		}
	}
	return state.pointer.y < bottom_strip_top(state.screen_units)
}

// The top of the strip along the bottom of the safe area and below it
// where the glyph bar and the HUD's hotbar sit.
bottom_strip_top :: proc(screen_units: [2]f32) -> f32 {
	safe_bottom := screen_units.y * (1 - UI_SAFE_AREA_FRACTION)
	return safe_bottom - max(f32(UI_GLYPH_BAR_HEIGHT + 2 * UI_GAP), UI_SLOT_SIZE * HUD_SELECTED_SLOT_SCALE)
}

// The seconds the focus has rested on one widget: counting while it
// stays, from zero when it moved.
advance_focus_rest :: proc(rest_id: Ui_Id, rest_seconds: f32, focus: Ui_Id, frame_seconds: f32) -> (Ui_Id, f32) {
	if focus != rest_id {
		return focus, 0
	}
	return rest_id, rest_seconds + frame_seconds
}

// The widget a screen wants focused when it opens (the selected hotbar
// slot in the inventory and the machine panels). Called during the
// frame; the fallback in ui_resolve takes it.
ui_prefer_focus :: proc(state: ^Ui_State, id: Ui_Id) {
	state.preferred_focus = id
}

// The fallback focus: the preferred widget when the frame has it, else
// the first widget, 0 without widgets.
fallback_focus :: proc(widgets: []Ui_Widget, preferred: Ui_Id) -> Ui_Id {
	if preferred != 0 && widget_index(widgets, preferred) >= 0 {
		return preferred
	}
	return len(widgets) > 0 ? widgets[0].id : 0
}

// Focus fallback, hover, then the focus step. Pure: tests run it instead of ui_end.
ui_resolve :: proc(state: ^Ui_State) {
	widgets := state.widgets[:]
	state.sound_events += ui_frame_sound_events(state^)
	focus_before := state.focus
	defer if focus_before != state.focus && widget_index(widgets, focus_before) >= 0 {
		state.sound_events += {.Move}
	}
	// A focus move keeps itself in view again (focus_scrolled_away).
	defer if focus_before != state.focus {
		state.focus_scrolled_away = false
	}
	state.hovered = state.pointer_source == .None ? 0 : widget_under(widgets, state.pointer)
	if state.pointer_moved && state.hovered != 0 && !pointer_scrolling(state^) {
		state.focus = state.hovered
	}
	if state.requested_focus != 0 {
		state.focus_scrolled_away = false
	}
	if state.requested_focus != 0 && widget_index(widgets, state.requested_focus) >= 0 {
		state.focus = state.requested_focus
	}
	state.requested_focus = 0
	focus_index := widget_index(widgets, state.focus)
	if focus_index < 0 {
		state.focus = fallback_focus(widgets, state.preferred_focus)
		return
	}
	if !focus_step_allowed(widgets[focus_index], state.navigation_step) {
		return
	}
	if neighbour, found := find_focus_neighbour(widgets, focus_index, state.navigation_step); found {
		state.focus = widgets[neighbour].id
	}
}

// An activation this frame, as ui_interact grants it: confirm on the
// focused widget, or a tap on one under the pointer, which sounds on the
// release (0132). A tap on an item slot is no activation, a press with
// Left Control is (the quick move), and so is its drop (0124). The touch
// row's Back sounds as B (0137).
ui_frame_sound_events :: proc(state: Ui_State) -> bit_set[Ui_Sound_Event] {
	if state.back_tapped {
		return {.Back}
	}
	widgets := state.widgets[:]
	confirmed := state.confirm && widget_index(widgets, state.focus) >= 0
	under := state.pointer_source != .None ? widget_index(widgets, widget_under(widgets, state.pointer)) : -1
	on_slot := under >= 0 && .Item_Slot in widgets[under].flags
	tapped := under >= 0 && !on_slot && pointer_tapped(state, widgets[under].id)
	quick_moved := state.click && on_slot && state.input.quick_move_modifier
	dropped := state.slot_drag.released && on_slot
	return confirmed || tapped || quick_moved || dropped ? {.Confirm} : {}
}

focus_step_allowed :: proc(focused: Ui_Widget, step: Ui_Direction) -> bool {
	switch step {
	case .None:
		return false
	case .Left, .Right:
		return .Adjusts_Horizontally not_in focused.flags
	case .Up, .Down:
		return .Adjusts_Vertically not_in focused.flags
	}
	return false
}

// Reduced motion holds the focus outline at its thickest, where the
// focused control is easiest to find.
still_focus_pulse :: proc(phase: f32, reduced_motion: bool) -> f32 {
	return reduced_motion ? 1 : phase
}

ui_end :: proc(state: ^Ui_State, atlas: Icon_Atlas, images: ^Ui_Image_Cache) {
	ui_resolve(state)
	ui_append_overlays(state)
	scale_text_commands(state.draw_list[:], ui_text_scale(state^))
	execute_draw_list(state^, atlas, images)
}

// The text scale, 1 for a state ui_begin has not run on (tests).
ui_text_scale :: proc(state: Ui_State) -> f32 {
	return state.accessibility.text_scale > 0 ? state.accessibility.text_scale : 1
}

// Widgets lay text out at the sizes they name, measured at the scaled
// size (ui_text_width_in_weight); the draw layer gets the scaled size.
scale_text_commands :: proc(commands: []Draw_Command, text_scale: f32) {
	for &command in commands {
		if command.kind == .Text {
			command.text_size *= text_scale
		}
	}
}

// Layout helpers.

ui_safe_area :: proc(state: ^Ui_State) -> Ui_Rectangle {
	margin := state.screen_units * UI_SAFE_AREA_FRACTION
	return {margin.x, margin.y, state.screen_units.x - 2 * margin.x, state.screen_units.y - 2 * margin.y}
}

centred_rectangle :: proc(area: Ui_Rectangle, width, height: f32) -> Ui_Rectangle {
	return {area.x + (area.width - width) / 2, area.y + (area.height - height) / 2, width, height}
}

// A panel of the wanted size centred in the area and no larger than it;
// what does not fit then scrolls (Scroll_Region) or shrinks.
fitted_panel :: proc(area: Ui_Rectangle, width, height: f32) -> Ui_Rectangle {
	return centred_rectangle(area, min(width, area.width), min(height, area.height))
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

// Takes a strip off the right of the area and returns it.
cut_right :: proc(area: ^Ui_Rectangle, width: f32) -> Ui_Rectangle {
	strip_width := min(width, area.width)
	area.width -= strip_width
	return {area.x + area.width, area.y, strip_width, area.height}
}

inset :: proc(rectangle: Ui_Rectangle, margin: f32) -> Ui_Rectangle {
	return {rectangle.x + margin, rectangle.y + margin, max(rectangle.width - 2 * margin, 0), max(rectangle.height - 2 * margin, 0)}
}

column_rectangle :: proc(rectangle: Ui_Rectangle, count, index: int, gap: f32) -> Ui_Rectangle {
	width := (rectangle.width - gap * f32(count - 1)) / f32(count)
	return {rectangle.x + f32(index) * (width + gap), rectangle.y, width, rectangle.height}
}

// Average advance of the default family (Exo 2, one variable file for
// both weights) as a fraction of the text size: 0.362 over a sample
// sentence (test_approximate_width_follows_the_default_font). Michroma,
// Orbitron and Oxanium run up to 0.44, so the headless audit does not
// cover the widest choices; the game measures with the real font.
APPROXIMATE_ADVANCE_FACTOR :: 0.37

// Rough width of the default family, for tests and before a window exists.
approximate_text_width :: proc(text: string, size: f32) -> f32 {
	return f32(strings.rune_count(text)) * size * APPROXIMATE_ADVANCE_FACTOR
}

// Headings (UI_HEADING_TEXT_SIZE and larger) and emphasised lines are bold.
text_weight :: proc(size: f32, emphasis := false) -> Font_Weight {
	return emphasis || size >= UI_HEADING_TEXT_SIZE ? .Bold : .Regular
}

ui_text_width :: proc(state: ^Ui_State, text: string, size: f32, emphasis := false) -> f32 {
	return ui_text_width_in_weight(state, text, size, text_weight(size, emphasis))
}

// Measured with the font the text is drawn with, so layout matches it.
ui_text_width_in_weight :: proc(state: ^Ui_State, text: string, unscaled_size: f32, weight: Font_Weight) -> f32 {
	size := unscaled_size * ui_text_scale(state^)
	if state.measure_text == nil || state.fonts == nil || len(state.fonts.families) == 0 {
		return approximate_text_width(text, size)
	}
	return state.measure_text(state.fonts, text, size, weight, state.pixels_per_unit)
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

// Swaps the top screen for another (the inventory tab strip), so Back
// still returns to what was under it.
replace_top_screen :: proc(stack: ^Screen_Stack, screen: Screen) {
	pop_screen(stack)
	push_screen(stack, screen)
}

top_screen :: proc(stack: Screen_Stack) -> Screen {
	return stack.count > 0 ? stack.screens[stack.count - 1] : .None
}

screen_pauses_simulation :: proc(screen: Screen) -> bool {
	switch screen {
	case .None, .Inventory, .Machine, .Recipes, .Journal, .Power, .Statistics, .Technologies, .Map:
		return false
	case .Pause, .Settings, .Developer, .Textures, .Data_Files, .Touch_Layout, .Title, .New_World, .Load_World, .Confirm_Delete:
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
