package game

import "core:encoding/json"
import "core:fmt"
import "core:math/linalg"
import "core:os"
import rl "shared:raylib"
import sdl "vendor:sdl3"

// The touch overlay (work item 0115, doc/input.md): a virtual gamepad the
// game draws on a touch screen. It fills a Raw_Gamepad like a physical
// one and adds its drags to the look delta like the mouse, so the
// bindings, the diagnostics and everything downstream see a gamepad.
// The layout is data/touch_overlay.sjson. A touch that begins on a button
// holds that button until it lifts, one that begins on the stick's half
// becomes a floating stick centred where it began, one that begins on the
// look half turns the view. While a screen is open the overlay draws and
// reads Start and Back alone, so every screen can be closed by touch (most
// have no close widget and raylib keeps Android's back key); every other
// touch is the pointer then (0114).

TOUCH_OVERLAY_FILE_NAME :: "touch_overlay.sjson"
// raylib's MAX_TOUCH_POINTS (rcore.c).
TOUCH_POINT_CAPACITY :: 8
TOUCH_OVERLAY_GAMEPAD_NAME :: "Touch overlay"
// The SDL gamepad's buttons and axes, as input_sdl3.odin counts them
// (that file is left out on Android).
TOUCH_OVERLAY_SDL_BUTTON_COUNT :: int(sdl.GamepadButton.MISC6) + 1
TOUCH_OVERLAY_AXIS_COUNT :: int(sdl.GamepadAxis.RIGHT_TRIGGER) + 1
// raylib's trigger axes rest at -1, SDL's at 0.
RAYLIB_TRIGGER_REST :: -1

// The settings value (settings.touch_overlay): auto is on for the Android
// build and off elsewhere.
Touch_Overlay_Mode :: enum u8 {
	Auto,
	On,
	Off,
}

Touch_Overlay_Kind :: enum u8 {
	Button,
	Stick,
	Look,
}

Touch_Overlay_Shape :: enum u8 {
	Rectangle,
	Circle,
}

Touch_Overlay_Anchor :: enum u8 {
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
	Bottom_Center,
	Top_Center,
}

Touch_Overlay_Side :: enum u8 {
	Left,
	Right,
}

// A gamepad button by its SDL name, or a trigger.
Touch_Overlay_Control :: struct {
	is_trigger: bool,
	trigger:    Gamepad_Trigger,
	button:     sdl.GamepadButton,
}

// An element as written in the file.
Touch_Overlay_Element_Entry :: struct {
	kind:        string,
	control:     string,
	shape:       string,
	anchor:      string,
	position:    [2]f32,
	size:        [2]f32,
	label:       string,
	side:        string,
	radius:      f32,
	sprint_rim:  f32,
	sensitivity: f32,
}

Touch_Overlay_File :: struct {
	reference_height: f32,
	elements:         []Touch_Overlay_Element_Entry,
}

// Lengths in pixels of a screen reference_height pixels high.
Touch_Overlay_Element :: struct {
	kind:        Touch_Overlay_Kind,
	control:     Touch_Overlay_Control,
	shape:       Touch_Overlay_Shape,
	anchor:      Touch_Overlay_Anchor,
	position:    [2]f32,
	size:        [2]f32,
	label:       string,
	side:        Touch_Overlay_Side,
	radius:      f32,
	sprint_rim:  f32,
	sensitivity: f32,
}

Touch_Overlay_Layout :: struct {
	reference_height: f32,
	elements:         []Touch_Overlay_Element,
}

// A button on the screen, in render pixels.
Placed_Element :: struct {
	element: int,
	shape:   Touch_Overlay_Shape,
	centre:  [2]f32,
	size:    [2]f32,
}

// A finger this frame, in render pixels.
Touch_Point :: struct {
	id:       i32,
	position: [2]f32,
}

Touch_Role :: enum u8 {
	// Began where the overlay reads nothing, or while a screen was open
	// on anything but Start or Back: the pointer's touch.
	Ignored,
	Button,
	Stick,
	Look,
}

// One finger from the frame it lands to the frame it lifts. element is
// the layout element it began on (the button, the stick or the look).
Touch_Slot :: struct {
	active:   bool,
	id:       i32,
	role:     Touch_Role,
	element:  int,
	origin:   [2]f32,
	position: [2]f32,
	previous: [2]f32,
	// A stick's drag crossed the rim upwards (stick_sprint_latched).
	sprint_latched: bool,
}

Touch_Overlay_State :: struct {
	slots: [TOUCH_POINT_CAPACITY]Touch_Slot,
}

// What the fingers hold this frame. buttons by SDL button index; stick in
// the raw axis convention (x right, y down, -1 to 1); look_delta in mouse
// pixels.
Touch_Overlay_Output :: struct {
	buttons:    [RAW_GAMEPAD_BUTTON_CAPACITY]bool,
	triggers:   [Gamepad_Trigger]bool,
	stick:      [2]f32,
	look_delta: [2]f32,
}

// What the input backends merge into their frame. active while the
// overlay is on in a world; world_shown while no screen is open, when its
// drags turn the view instead of the pointer's.
// pointer_claimed: the first touch, which holds raylib's left mouse
// button, is a finger on one of the overlay's buttons, so the frame reads
// that button up (touch_overlay_mouse) and a Back tap never also clicks
// the widget under the pill.
Touch_Overlay_Frame :: struct {
	active:          bool,
	world_shown:     bool,
	output:          Touch_Overlay_Output,
	pointer_claimed: bool,
}

// Loading.

@(rodata)
touch_overlay_kind_names := [Touch_Overlay_Kind]string {
	.Button = "button",
	.Stick  = "stick",
	.Look   = "look",
}

@(rodata)
touch_overlay_shape_names := [Touch_Overlay_Shape]string {
	.Rectangle = "rectangle",
	.Circle    = "circle",
}

@(rodata)
touch_overlay_anchor_names := [Touch_Overlay_Anchor]string {
	.Top_Left      = "top_left",
	.Top_Right     = "top_right",
	.Bottom_Left   = "bottom_left",
	.Bottom_Right  = "bottom_right",
	.Bottom_Center = "bottom_center",
	.Top_Center    = "top_center",
}

@(rodata)
touch_overlay_side_names := [Touch_Overlay_Side]string {
	.Left  = "left",
	.Right = "right",
}

name_to_enum :: proc(names: [$E]string, name: string) -> (value: E, ok: bool) {
	for candidate_name, candidate in names {
		if candidate_name == name {
			return candidate, true
		}
	}
	return {}, false
}

// Controls the raylib backend can express too, so the overlay works on
// both backends.
touch_overlay_control_from_name :: proc(name: string) -> (control: Touch_Overlay_Control, ok: bool) {
	if trigger, is_trigger := gamepad_trigger_from_name(name); is_trigger {
		return {is_trigger = true, trigger = trigger}, true
	}
	button, is_button := sdl_gamepad_button_from_name(name)
	if !is_button {
		return {}, false
	}
	if _, mapped := raylib_gamepad_button(button); !mapped {
		return {}, false
	}
	return {button = button}, true
}

// Buttons by their label, the stick and the look by their kind.
touch_overlay_element_name :: proc(entry: Touch_Overlay_Element_Entry, index: int) -> string {
	if entry.label != "" {
		return fmt.tprintf("elements[%d] (%q)", index, entry.label)
	}
	return fmt.tprintf("elements[%d] (%s)", index, entry.kind)
}

resolve_touch_overlay_button :: proc(entry: Touch_Overlay_Element_Entry, element: ^Touch_Overlay_Element) -> string {
	control, control_ok := touch_overlay_control_from_name(entry.control)
	if !control_ok {
		return fmt.tprintf("unknown control %q (a gamepad button bindings.sjson names, or LEFT_TRIGGER, RIGHT_TRIGGER)", entry.control)
	}
	shape, shape_ok := name_to_enum(touch_overlay_shape_names, entry.shape)
	if !shape_ok {
		return fmt.tprintf("unknown shape %q (rectangle, circle)", entry.shape)
	}
	anchor, anchor_ok := name_to_enum(touch_overlay_anchor_names, entry.anchor)
	if !anchor_ok {
		return fmt.tprintf("unknown anchor %q (top_left, top_right, bottom_left, bottom_right, bottom_center, top_center)", entry.anchor)
	}
	if entry.size.x <= 0 || entry.size.y <= 0 {
		return "the size must be positive"
	}
	element.control, element.shape, element.anchor = control, shape, anchor
	return ""
}

resolve_touch_overlay_side :: proc(entry: Touch_Overlay_Element_Entry, element: ^Touch_Overlay_Element) -> string {
	side, side_ok := name_to_enum(touch_overlay_side_names, entry.side)
	if !side_ok {
		return fmt.tprintf("unknown side %q (left, right)", entry.side)
	}
	element.side = side
	return ""
}

resolve_touch_overlay_stick :: proc(entry: Touch_Overlay_Element_Entry, element: ^Touch_Overlay_Element) -> string {
	if problem := resolve_touch_overlay_side(entry, element); problem != "" {
		return problem
	}
	switch {
	case entry.radius <= 0:
		return "the radius must be positive"
	case entry.sprint_rim < 1:
		return "the sprint_rim must be 1 or more"
	}
	return ""
}

resolve_touch_overlay_look :: proc(entry: Touch_Overlay_Element_Entry, element: ^Touch_Overlay_Element) -> string {
	if problem := resolve_touch_overlay_side(entry, element); problem != "" {
		return problem
	}
	if entry.sensitivity <= 0 {
		return "the sensitivity must be positive"
	}
	return ""
}

resolve_touch_overlay_element :: proc(entry: Touch_Overlay_Element_Entry) -> (element: Touch_Overlay_Element, problem: string) {
	kind, kind_ok := name_to_enum(touch_overlay_kind_names, entry.kind)
	if !kind_ok {
		return {}, fmt.tprintf("unknown kind %q (button, stick, look)", entry.kind)
	}
	element = Touch_Overlay_Element {
		kind        = kind,
		position    = entry.position,
		size        = entry.size,
		label       = entry.label,
		radius      = entry.radius,
		sprint_rim  = entry.sprint_rim,
		sensitivity = entry.sensitivity,
	}
	switch kind {
	case .Button:
		problem = resolve_touch_overlay_button(entry, &element)
	case .Stick:
		problem = resolve_touch_overlay_stick(entry, &element)
	case .Look:
		problem = resolve_touch_overlay_look(entry, &element)
	}
	return element, problem
}

// At most one stick and one look, on different sides.
touch_overlay_zones_problem :: proc(elements: []Touch_Overlay_Element) -> string {
	counts: [Touch_Overlay_Kind]int
	sides: [Touch_Overlay_Kind]Touch_Overlay_Side
	for element in elements {
		counts[element.kind] += 1
		sides[element.kind] = element.side
	}
	switch {
	case counts[.Stick] > 1:
		return "more than one stick"
	case counts[.Look] > 1:
		return "more than one look"
	case counts[.Stick] == 1 && counts[.Look] == 1 && sides[.Stick] == sides[.Look]:
		return "the stick and the look are on the same side"
	}
	return ""
}

resolve_touch_overlay :: proc(file: Touch_Overlay_File, allocator := context.allocator) -> (layout: Touch_Overlay_Layout, problem: string) {
	if file.reference_height <= 0 {
		return {}, "reference_height must be positive"
	}
	elements := make([]Touch_Overlay_Element, len(file.elements), allocator)
	for entry, index in file.elements {
		element_problem: string
		if elements[index], element_problem = resolve_touch_overlay_element(entry); element_problem != "" {
			delete(elements, allocator)
			return {}, fmt.tprintf("%s: %s", touch_overlay_element_name(entry, index), element_problem)
		}
	}
	if problem = touch_overlay_zones_problem(elements); problem != "" {
		delete(elements, allocator)
		return {}, problem
	}
	return Touch_Overlay_Layout{reference_height = file.reference_height, elements = elements}, ""
}

// Held to the configuration's strict keys, so a misspelt key is an error.
// The labels are cloned into allocator.
parse_touch_overlay_file :: proc(data: []byte, source: string, allocator := context.allocator) -> (layout: Touch_Overlay_Layout, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return {}, parse_problem
	}
	provenance := make(Configuration_Provenance, context.temp_allocator)
	provenance[""] = source
	file: Touch_Overlay_File
	if problem = assign_configuration_value(any{&file, typeid_of(Touch_Overlay_File)}, json.Value(tree), "", provenance, allocator); problem != "" {
		return {}, problem
	}
	if layout, problem = resolve_touch_overlay(file, allocator); problem != "" {
		return {}, fmt.tprintf("%s: %s", source, problem)
	}
	return layout, ""
}

load_touch_overlay :: proc(data_directory: string, allocator := context.allocator) -> (layout: Touch_Overlay_Layout, ok: bool) {
	path := join_save_path(data_directory, TOUCH_OVERLAY_FILE_NAME)
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		log_printf("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	problem: string
	if layout, problem = parse_touch_overlay_file(data, path, allocator); problem != "" {
		log_printf("error: invalid %s", problem)
		return {}, false
	}
	return layout, true
}

// When it is on.

touch_overlay_enabled :: proc(mode: Touch_Overlay_Mode, forced, android: bool) -> bool {
	switch mode {
	case .On:
		return true
	case .Off:
		return forced
	case .Auto:
	}
	return forced || android
}

// Layout.

touch_overlay_scale :: proc(layout: Touch_Overlay_Layout, screen_size: [2]f32) -> f32 {
	return screen_size.y / layout.reference_height
}

anchored_position :: proc(anchor: Touch_Overlay_Anchor, offset, screen_size: [2]f32) -> [2]f32 {
	switch anchor {
	case .Top_Left:
		return offset
	case .Top_Right:
		return {screen_size.x - offset.x, offset.y}
	case .Bottom_Left:
		return {offset.x, screen_size.y - offset.y}
	case .Bottom_Right:
		return screen_size - offset
	case .Bottom_Center:
		return {screen_size.x / 2 + offset.x, screen_size.y - offset.y}
	case .Top_Center:
		return {screen_size.x / 2 + offset.x, offset.y}
	}
	return offset
}

// The buttons on a screen of screen_size render pixels, every length
// scaled by the screen's height over the reference height.
overlay_layout :: proc(layout: Touch_Overlay_Layout, screen_size: [2]f32, allocator := context.allocator) -> []Placed_Element {
	scale := touch_overlay_scale(layout, screen_size)
	placed := make([dynamic]Placed_Element, 0, len(layout.elements), allocator)
	for element, index in layout.elements {
		if element.kind != .Button {
			continue
		}
		centre := anchored_position(element.anchor, element.position * scale, screen_size)
		append(&placed, Placed_Element{element = index, shape = element.shape, centre = centre, size = element.size * scale})
	}
	return placed[:]
}

// A circle is the ellipse inside its size, a rectangle the whole size.
placed_element_contains :: proc(placed: Placed_Element, point: [2]f32) -> bool {
	half := placed.size / 2
	offset := point - placed.centre
	switch placed.shape {
	case .Rectangle:
		return abs(offset.x) <= half.x && abs(offset.y) <= half.y
	case .Circle:
		normalised := offset / half
		return linalg.dot(normalised, normalised) <= 1
	}
	return false
}

// The button under the point, -1 for none; the last listed wins where
// buttons overlap, since it is drawn on top.
button_at :: proc(placed: []Placed_Element, point: [2]f32) -> int {
	for index := len(placed) - 1; index >= 0; index -= 1 {
		if placed_element_contains(placed[index], point) {
			return placed[index].element
		}
	}
	return -1
}

// Tracking the fingers.

screen_side :: proc(point, screen_size: [2]f32) -> Touch_Overlay_Side {
	return point.x < screen_size.x / 2 ? .Left : .Right
}

zone_element :: proc(layout: Touch_Overlay_Layout, kind: Touch_Overlay_Kind, side: Touch_Overlay_Side) -> int {
	for element, index in layout.elements {
		if element.kind == kind && element.side == side {
			return index
		}
	}
	return -1
}

stick_held :: proc(state: Touch_Overlay_State) -> bool {
	for slot in state.slots {
		if slot.active && slot.role == .Stick {
			return true
		}
	}
	return false
}

// Start and Back, the buttons that stay drawn and read while a screen is
// open.
control_serves_screens :: proc(control: Touch_Overlay_Control) -> bool {
	return !control.is_trigger && (control.button == .START || control.button == .BACK)
}

// The buttons shown: all in the world, Start and Back over a screen.
placed_for_screen :: proc(layout: Touch_Overlay_Layout, placed: []Placed_Element, world_shown: bool, allocator := context.allocator) -> []Placed_Element {
	shown := make([dynamic]Placed_Element, 0, len(placed), allocator)
	for element in placed {
		if world_shown || control_serves_screens(layout.elements[element.element].control) {
			append(&shown, element)
		}
	}
	return shown[:]
}

// What a finger landing at point becomes. With a screen open a finger on
// Start or Back is that button and every other finger the pointer's. One
// stick at a time: a second finger on the stick's half is ignored.
classify_touch :: proc(state: Touch_Overlay_State, layout: Touch_Overlay_Layout, placed: []Placed_Element, point, screen_size: [2]f32, world_shown: bool) -> (role: Touch_Role, element: int) {
	if button := button_at(placed_for_screen(layout, placed, world_shown, context.temp_allocator), point); button >= 0 {
		return .Button, button
	}
	if !world_shown {
		return .Ignored, -1
	}
	side := screen_side(point, screen_size)
	if stick := zone_element(layout, .Stick, side); stick >= 0 && !stick_held(state) {
		return .Stick, stick
	}
	if look := zone_element(layout, .Look, side); look >= 0 {
		return .Look, look
	}
	return .Ignored, -1
}

find_touch_point :: proc(points: []Touch_Point, id: i32) -> (point: Touch_Point, found: bool) {
	for candidate in points {
		if candidate.id == id {
			return candidate, true
		}
	}
	return {}, false
}

touch_slot_tracks :: proc(state: Touch_Overlay_State, id: i32) -> bool {
	for slot in state.slots {
		if slot.active && slot.id == id {
			return true
		}
	}
	return false
}

free_touch_slot :: proc(state: Touch_Overlay_State) -> int {
	for slot, index in state.slots {
		if !slot.active {
			return index
		}
	}
	return -1
}

// Moves the fingers still down, forgets the lifted ones and gives each
// new finger its role from where it landed.
update_touch_overlay :: proc(state: ^Touch_Overlay_State, points: []Touch_Point, layout: Touch_Overlay_Layout, placed: []Placed_Element, screen_size: [2]f32, world_shown: bool) {
	for &slot in state.slots {
		if !slot.active {
			continue
		}
		point, found := find_touch_point(points, slot.id)
		if !found {
			slot = {}
			continue
		}
		slot.previous, slot.position = slot.position, point.position
		// Not under a screen, where the held stick reads nothing: a rim
		// crossing there would be a fresh press the frame it closes.
		if world_shown {
			slot.sprint_latched = stick_sprint_latched(slot, layout, screen_size)
		}
	}
	for point in points {
		if touch_slot_tracks(state^, point.id) {
			continue
		}
		free_index := free_touch_slot(state^)
		if free_index < 0 {
			return
		}
		role, element := classify_touch(state^, layout, placed, point.position, screen_size, world_shown)
		state.slots[free_index] = Touch_Slot{active = true, id = point.id, role = role, element = element, origin = point.position, position = point.position, previous = point.position}
	}
}

// The drag over the radius, clamped to the unit disc. The backend's stick
// dead zone applies to it as to any stick (gamepad_stick, sdl3_stick).
touch_stick_value :: proc(drag: [2]f32, radius: f32) -> [2]f32 {
	return clamp_to_unit_length(drag / radius)
}

// Past the rim, within 45 degrees of straight up (screen y grows down).
touch_stick_sprints :: proc(drag: [2]f32, radius, sprint_rim: f32) -> bool {
	return linalg.length(drag) >= sprint_rim * radius && -drag.y >= abs(drag.x)
}

// The first crossing of the rim upwards holds the stick click for the rest
// of the drag, until the finger lifts: push to the rim to sprint, keep
// walking, lift to stop. So easing back inside the rim, or wobbling across
// it or its 45 degree edge, makes no new press (a toggled Sprint would
// switch off).
stick_sprint_latched :: proc(slot: Touch_Slot, layout: Touch_Overlay_Layout, screen_size: [2]f32) -> bool {
	if slot.sprint_latched {
		return true
	}
	if slot.role != .Stick || !touch_slot_reads(slot, layout) {
		return false
	}
	element := layout.elements[slot.element]
	return touch_stick_sprints(slot.position - slot.origin, element.radius * touch_overlay_scale(layout, screen_size), element.sprint_rim)
}

press_touch_control :: proc(output: ^Touch_Overlay_Output, control: Touch_Overlay_Control) {
	if control.is_trigger {
		output.triggers[control.trigger] = true
	} else {
		output.buttons[int(control.button)] = true
	}
}

touch_overlay_control_down :: proc(output: Touch_Overlay_Output, control: Touch_Overlay_Control) -> bool {
	return control.is_trigger ? output.triggers[control.trigger] : output.buttons[int(control.button)]
}

add_touch_slot_output :: proc(output: ^Touch_Overlay_Output, slot: Touch_Slot, element: Touch_Overlay_Element, scale: f32, world_shown: bool) {
	if !world_shown && !(slot.role == .Button && control_serves_screens(element.control)) {
		return
	}
	switch slot.role {
	case .Ignored:
	case .Button:
		press_touch_control(output, element.control)
	case .Stick:
		output.stick = touch_stick_value(slot.position - slot.origin, element.radius * scale)
		if slot.sprint_latched {
			output.buttons[int(sdl.GamepadButton.LEFT_STICK)] = true
		}
	case .Look:
		output.look_delta += (slot.position - slot.previous) * element.sensitivity
	}
}

// False for an ignored finger, and for one whose element a data reload
// removed or replaced with another kind.
touch_slot_reads :: proc(slot: Touch_Slot, layout: Touch_Overlay_Layout) -> bool {
	if !slot.active || slot.element < 0 || slot.element >= len(layout.elements) {
		return false
	}
	kind := layout.elements[slot.element].kind
	switch slot.role {
	case .Ignored:
		return false
	case .Button:
		return kind == .Button
	case .Stick:
		return kind == .Stick
	case .Look:
		return kind == .Look
	}
	return false
}

// Start and Back alone while a screen is open, also when held from the
// world (the press that opened the pause menu). look_delta is in the
// render pixels the touches come in; the frame converts it
// (read_touch_overlay_frame).
touch_overlay_output :: proc(state: Touch_Overlay_State, layout: Touch_Overlay_Layout, screen_size: [2]f32, world_shown: bool) -> Touch_Overlay_Output {
	output: Touch_Overlay_Output
	scale := touch_overlay_scale(layout, screen_size)
	for slot in state.slots {
		if touch_slot_reads(slot, layout) {
			add_touch_slot_output(&output, slot, layout.elements[slot.element], scale, world_shown)
		}
	}
	return output
}

// Into the backends.

// The overlay as a gamepad in the backend's numbering. The triggers are
// buttons on the raylib backend (raylib_trigger_buttons) and axes on SDL.
touch_overlay_raw_gamepad :: proc(output: Touch_Overlay_Output, backend: Input_Backend) -> Raw_Gamepad {
	gamepad := Raw_Gamepad {
		connected  = true,
		on_screen  = true,
		name       = TOUCH_OVERLAY_GAMEPAD_NAME,
		axis_count = TOUCH_OVERLAY_AXIS_COUNT,
	}
	gamepad.axis_values[int(sdl.GamepadAxis.LEFTX)] = output.stick.x
	gamepad.axis_values[int(sdl.GamepadAxis.LEFTY)] = output.stick.y
	switch backend {
	case .Raylib:
		gamepad.button_count = len(rl.GamepadButton)
		for down, index in output.buttons {
			if raylib_button, mapped := raylib_gamepad_button(sdl.GamepadButton(index)); down && mapped {
				gamepad.button_down[int(raylib_button)] = true
			}
		}
		for down, trigger in output.triggers {
			gamepad.button_down[int(raylib_trigger_buttons[trigger])] = down
		}
		gamepad.axis_values[int(rl.GamepadAxis.LEFT_TRIGGER)] = output.triggers[.Left] ? 1 : RAYLIB_TRIGGER_REST
		gamepad.axis_values[int(rl.GamepadAxis.RIGHT_TRIGGER)] = output.triggers[.Right] ? 1 : RAYLIB_TRIGGER_REST
	case .Sdl3:
		gamepad.button_count = TOUCH_OVERLAY_SDL_BUTTON_COUNT
		gamepad.button_down = output.buttons
		gamepad.axis_values[int(sdl.GamepadAxis.LEFT_TRIGGER)] = output.triggers[.Left] ? 1 : 0
		gamepad.axis_values[int(sdl.GamepadAxis.RIGHT_TRIGGER)] = output.triggers[.Right] ? 1 : 0
	}
	return gamepad
}

// The physical gamepad keeps its name, touchpads and motion, and on_screen
// stays false, so its presses and the overlay's alike show the gamepad's
// glyphs (detect_input_device); buttons are
// or'ed, the stick axes summed and clamped, the trigger axes the larger.
// Both backends number the first four axes as the sticks and the next two
// as the triggers.
merge_touch_overlay_gamepad :: proc(physical, overlay: Raw_Gamepad) -> Raw_Gamepad {
	if !overlay.connected {
		return physical
	}
	if !physical.connected {
		return overlay
	}
	result := physical
	result.button_count = max(physical.button_count, overlay.button_count)
	result.axis_count = max(physical.axis_count, overlay.axis_count)
	for index in 0 ..< RAW_GAMEPAD_BUTTON_CAPACITY {
		result.button_down[index] = physical.button_down[index] || overlay.button_down[index]
	}
	for index in 0 ..< STICK_AXIS_COUNT {
		result.axis_values[index] = clamp(physical.axis_values[index] + overlay.axis_values[index], -1, 1)
	}
	for index in STICK_AXIS_COUNT ..< TOUCH_OVERLAY_AXIS_COUNT {
		result.axis_values[index] = max(physical.axis_values[index], overlay.axis_values[index])
	}
	return result
}

touch_overlay_gamepad :: proc(physical: Raw_Gamepad, overlay: Touch_Overlay_Frame, backend: Input_Backend) -> Raw_Gamepad {
	if !overlay.active {
		return physical
	}
	return merge_touch_overlay_gamepad(physical, touch_overlay_raw_gamepad(overlay.output, backend))
}

// While the overlay drives the world the touches are its own, so the
// pointer's delta and buttons (the first touch holds the left mouse
// button) do not also look and mine.
touch_overlay_drives_world :: proc(overlay: Touch_Overlay_Frame) -> bool {
	return overlay.active && overlay.world_shown
}

pointer_look_delta :: proc(mouse_delta: [2]f32, overlay: Touch_Overlay_Frame) -> [2]f32 {
	return touch_overlay_drives_world(overlay) ? overlay.output.look_delta : mouse_delta
}

// The frame.

// Every finger on Android. On the desktop raylib has no touch points, so
// the mouse is touch point 0 while its left button is down.
read_touch_points :: proc(buffer: []Touch_Point) -> []Touch_Point {
	window_size, render := cursor_window_size(), render_size()
	when ODIN_PLATFORM_SUBTARGET == .Android {
		count := min(int(rl.GetTouchPointCount()), len(buffer))
		for index in 0 ..< count {
			position := pointer_to_render_pixels(rl.GetTouchPosition(i32(index)), window_size, render)
			buffer[index] = Touch_Point{id = rl.GetTouchPointId(i32(index)), position = position}
		}
		return buffer[:count]
	} else {
		if !rl.IsMouseButtonDown(.LEFT) || len(buffer) == 0 {
			return buffer[:0]
		}
		buffer[0] = Touch_Point{id = 0, position = pointer_to_render_pixels(rl.GetMousePosition(), window_size, render)}
		return buffer[:1]
	}
}

touch_overlay_on :: proc(state: ^Frame_State) -> bool {
	return touch_overlay_enabled(state.settings.touch_overlay, state.touch_overlay_forced, ODIN_PLATFORM_SUBTARGET == .Android)
}

// Only in a world: the title screens take touch as the pointer alone.
read_touch_overlay_frame :: proc(state: ^Frame_State) -> Touch_Overlay_Frame {
	if !touch_overlay_on(state) || state.session == nil {
		state.touch_overlay = {}
		return {}
	}
	screen_size := render_size()
	screen := [2]f32{f32(screen_size.x), f32(screen_size.y)}
	buffer: [TOUCH_POINT_CAPACITY]Touch_Point
	frame := touch_overlay_frame(&state.touch_overlay, state.content.touch_overlay, read_touch_points(buffer[:]), screen, !ui_blocks_world(state.ui.screens))
	frame.output.look_delta = render_pixels_to_window_units(frame.output.look_delta, cursor_window_size(), screen_size)
	return frame
}

// One frame of the overlay from this frame's fingers, in touch index
// order, so points[0] is the touch raylib holds the left mouse button for
// (the mouse itself on the desktop).
touch_overlay_frame :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, points: []Touch_Point, screen_size: [2]f32, world_shown: bool) -> Touch_Overlay_Frame {
	placed := overlay_layout(layout, screen_size, context.temp_allocator)
	update_touch_overlay(state, points, layout, placed, screen_size, world_shown)
	return Touch_Overlay_Frame {
		active = true,
		world_shown = world_shown,
		output = touch_overlay_output(state^, layout, screen_size, world_shown),
		pointer_claimed = len(points) > 0 && touch_claims_pointer(state^, layout, points[0].id),
	}
}

// A finger on one of the overlay's buttons, in the world or over a screen.
touch_claims_pointer :: proc(state: Touch_Overlay_State, layout: Touch_Overlay_Layout, id: i32) -> bool {
	for slot in state.slots {
		if slot.active && slot.id == id {
			return slot.role == .Button && touch_slot_reads(slot, layout)
		}
	}
	return false
}

// The raw mouse as the frame sees it: the left button up while the
// overlay claims the pointer's touch. The position still follows it.
touch_overlay_mouse :: proc(mouse: Raw_Mouse, overlay: Touch_Overlay_Frame) -> Raw_Mouse {
	result := mouse
	if overlay.pointer_claimed {
		result.button_down[int(rl.MouseButton.LEFT)] = false
	}
	return result
}

// The look delta in the mouse delta's coordinates, the window's
// (read_raylib_mouse keeps those on purpose, so the look speed does not
// follow a desktop's scale). The same on the phone, where the window is
// the screen.
render_pixels_to_window_units :: proc(delta: [2]f32, window_size, render_size: [2]int) -> [2]f32 {
	if render_size.x <= 0 || render_size.y <= 0 {
		return delta
	}
	return delta * [2]f32{f32(window_size.x) / f32(render_size.x), f32(window_size.y) / f32(render_size.y)}
}

// Drawing.

// Outlines and labels at a low alpha, a held button filled. Nothing moves
// but with a finger, so nothing pulses (DESIGN.md).
TOUCH_OVERLAY_COLOR :: Ui_Color{255, 255, 255, 89}
TOUCH_OVERLAY_LINE :: 2.0
// The knob's radius over the stick's radius.
TOUCH_OVERLAY_KNOB_FRACTION :: 0.4

pixels_to_units_rectangle :: proc(centre, size: [2]f32, pixels_per_unit: f32) -> Ui_Rectangle {
	corner := (centre - size / 2) / pixels_per_unit
	return Ui_Rectangle{corner.x, corner.y, size.x / pixels_per_unit, size.y / pixels_per_unit}
}

draw_touch_overlay_button :: proc(ui: ^Ui_State, rectangle: Ui_Rectangle, shape: Touch_Overlay_Shape, down: bool, label: string) {
	switch shape {
	case .Rectangle:
		if down {
			draw_fill(ui, rectangle, TOUCH_OVERLAY_COLOR)
		}
		draw_outline(ui, rectangle, TOUCH_OVERLAY_COLOR, TOUCH_OVERLAY_LINE)
	case .Circle:
		if down {
			draw_circle(ui, rectangle, TOUCH_OVERLAY_COLOR)
		}
		draw_ring(ui, rectangle, TOUCH_OVERLAY_COLOR, TOUCH_OVERLAY_LINE)
	}
	draw_text(ui, rectangle, label, UI_BODY_TEXT_SIZE, .Centre, TOUCH_OVERLAY_COLOR)
}

draw_touch_stick :: proc(ui: ^Ui_State, slot: Touch_Slot, radius: f32) {
	diameter := [2]f32{2 * radius, 2 * radius}
	draw_ring(ui, pixels_to_units_rectangle(slot.origin, diameter, ui.pixels_per_unit), TOUCH_OVERLAY_COLOR, TOUCH_OVERLAY_LINE)
	draw_circle(ui, pixels_to_units_rectangle(slot.position, diameter * TOUCH_OVERLAY_KNOB_FRACTION, ui.pixels_per_unit), TOUCH_OVERLAY_COLOR)
}

// Through the UI draw list, after the screens so Start and Back show
// over an open one; with a screen open only they draw. The look zone
// draws nothing.
draw_touch_overlay :: proc(ui: ^Ui_State, state: Touch_Overlay_State, layout: Touch_Overlay_Layout, screen_pixels: [2]f32, world_shown: bool) {
	output := touch_overlay_output(state, layout, screen_pixels, world_shown)
	placed := overlay_layout(layout, screen_pixels, context.temp_allocator)
	for shown in placed_for_screen(layout, placed, world_shown, context.temp_allocator) {
		element := layout.elements[shown.element]
		rectangle := pixels_to_units_rectangle(shown.centre, shown.size, ui.pixels_per_unit)
		draw_touch_overlay_button(ui, rectangle, shown.shape, touch_overlay_control_down(output, element.control), element.label)
	}
	if !world_shown {
		return
	}
	scale := touch_overlay_scale(layout, screen_pixels)
	for slot in state.slots {
		if slot.role == .Stick && touch_slot_reads(slot, layout) {
			draw_touch_stick(ui, slot, layout.elements[slot.element].radius * scale)
		}
	}
}
