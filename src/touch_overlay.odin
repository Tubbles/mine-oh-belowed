package game

import "core:encoding/json"
import "core:fmt"
import "core:math/linalg"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import rl "shared:raylib"
import sdl "vendor:sdl3"
import "platform"

// The touch overlay (work item 0115, doc/touch_overlay.md): a virtual
// gamepad the game draws on a touch screen. It fills a Raw_Gamepad
// like a physical one and adds its drags to the look delta like the
// mouse, so the
// bindings, the diagnostics and everything downstream see a gamepad.
// The layout is data/touch_overlay.sjson, whose Default has only the
// stick and the look (0134); a user layout may add buttons. A touch that
// begins on a button holds that button until it lifts. Every other touch
// on free screen, on either half, is undecided at first: moving
// past the slop makes it a drag (the floating stick, centred where it
// landed, when it landed on the stick's half and the stick is free, else
// the look drag), resting makes it a hold (Mine) and a lift before either
// a tap (Interact or Place through gamepad controls like every other
// touch, or in the jump zone at the right edge the Jump action itself). The tap scheme
// (0118, settings.touch_interaction) aims the hold and the tap at the
// finger, the crosshair scheme at the view's centre. While a screen is
// open the overlay draws and reads Start and Back alone; every other
// touch is the pointer then (0114). A touch on a hotbar slot (0119)
// selects it when tapped, one of the two places the overlay presses an
// action (apply_touch_overlay_hotbar; the jump tap is the other), since
// selecting a given slot has no gamepad control; held on the selected slot it presses
// hotbar_drop_control (Drop_Stack). A touch on one of the HUD's touch
// buttons beside the hotbar (hud.odin: inventory, pause, rotate)
// presses the gamepad control bound to its action. A static stick (0120)
// sits at a fixed place and reads only a touch that begins inside its
// base; a button with double_tap_toggles latches down on a double tap
// until the next tap.

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
// A touch on free screen (0118, 0134) that moves further than this
// (pixels of a reference_height high screen, scaled like the layout) is a
// drag, one that rests this long is a hold.
TOUCH_TAP_SLOP :: 12.0
TOUCH_HOLD_SECONDS :: 0.25
// A button with double_tap_toggles (0120) latches when a touch lands on it
// this soon after the previous touch on it lifted.
TOUCH_DOUBLE_TAP_SECONDS :: 0.3
// The latched buttons are a bit set over the element index, so a layout
// holds at most this many elements.
TOUCH_OVERLAY_ELEMENT_CAPACITY :: 64
// An element's opacity (0121) runs from this to 1. The loader cannot tell
// opacity = 0 from no opacity, which is 1.
TOUCH_OVERLAY_OPACITY_MINIMUM :: 0.1

// The settings value (settings.touch_overlay): auto is on for the Android
// build and off elsewhere.
Touch_Overlay_Mode :: enum u8 {
	Auto,
	On,
	Off,
}

// The settings value (settings.touch_interaction, 0118): tap aims Mine,
// Place and Interact at the touched point; crosshair aims them at the
// view's centre. Both read the same gestures (0134).
Touch_Interaction :: enum u8 {
	Tap,
	Crosshair,
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
	// The look's controls (0118) and its jump zone (0134).
	hold_control:         string,
	tap_interact_control: string,
	tap_place_control:    string,
	jump_zone_share:      f32,
	// 0120: a stick with anchor and position, a button that latches on a
	// double tap.
	static:               bool,
	double_tap_toggles:   bool,
	// 0121: 0.1 to 1, left out (0) for 1.
	opacity:              f32,
}

Touch_Overlay_File :: struct {
	reference_height:    f32,
	hotbar_drop_control: string,
	elements:            []Touch_Overlay_Element_Entry,
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
	// A look's controls (0118): the hold presses hold_control, a tap
	// tap_interact_control on a target that takes Interact, else
	// tap_place_control. A tap in the rightmost jump_zone_share of the
	// screen's width presses the Jump action instead (0134,
	// apply_touch_overlay_jump; 0 for no zone).
	hold_control:         Touch_Overlay_Control,
	tap_interact_control: Touch_Overlay_Control,
	tap_place_control:    Touch_Overlay_Control,
	jump_zone_share:      f32,
	// A static stick's base is centred at anchor and position (0120).
	static:               bool,
	double_tap_toggles:   bool,
	// The drawing's alpha over the overlay's own (0121), 0.1 to 1.
	opacity:              f32,
}

// hotbar_drop_control: held by a long press on the selected hotbar slot
// (0119).
Touch_Overlay_Layout :: struct {
	reference_height:    f32,
	hotbar_drop_control: Touch_Overlay_Control,
	elements:            []Touch_Overlay_Element,
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
	// A touch on free screen before it moved or rested
	// (advance_pending_touch), and one that rested: Mine.
	Pending,
	Hold,
	// Began on a hotbar slot in the world (0119): Touch_Slot.hotbar_slot.
	Hotbar,
	// Began on one of the HUD's touch buttons in the world (0134):
	// Touch_Slot.hud_control.
	Hud_Button,
}

// One finger from the frame it lands to the frame it lifts. element is
// the layout element it began on (the button, the stick or the look; a
// Pending finger's is the look, whose controls it presses).
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
	// How long a Pending, Hotbar or Button touch has been down.
	held_seconds:   f32,
	// A Hotbar touch's slot. spent: its long press fired or it moved past
	// the slop, so it fires nothing more. drops: its long press was on
	// the selected slot, so it holds hotbar_drop_control until it lifts.
	hotbar_slot:    int,
	hotbar_spent:   bool,
	hotbar_drops:   bool,
	// A Button touch that latched or released its double_tap_toggles
	// button, so its lift starts no double tap.
	toggle_spent:   bool,
	// A Hud_Button touch's control, the one bound to its button's action
	// when it landed.
	hud_control:    Touch_Overlay_Control,
}

// The last lift of a double_tap_toggles button and the frame time since.
Touch_Double_Tap :: struct {
	armed:   bool,
	element: int,
	seconds: f32,
}

// A tap after its finger lifted: first it aims at the point until a tick
// has run with that aim, so the target is the tapped one, then it presses
// control (Interact's SOUTH or Place's LEFT_TRIGGER, chosen by that
// target) until a tick has run with the press. A tap in the jump zone
// (0134, jumps) presses the Jump action at once, until a tick has run with
// it, and aims nowhere (apply_touch_overlay_jump); fresh marks its first
// frame, the edge.
Touch_Tap_Phase :: enum u8 {
	None,
	Aiming,
	Pressing,
}

// element is the look element the finger began on, whose controls the
// tap presses. waited_seconds: frame time since the tap last saw a tick;
// past TOUCH_HOLD_SECONDS (a developer pause holds the ticks) it is
// dropped instead of firing late.
Touch_Tap :: struct {
	phase:          Touch_Tap_Phase,
	point:          [2]f32,
	element:        int,
	control:        Touch_Overlay_Control,
	waited_seconds: f32,
	aims:           bool,
	jumps:          bool,
	fresh:          bool,
}

Touch_Overlay_State :: struct {
	slots: [TOUCH_POINT_CAPACITY]Touch_Slot,
	tap:   Touch_Tap,
	// The double_tap_toggles buttons latched down, by element index.
	latched:    bit_set[0 ..< TOUCH_OVERLAY_ELEMENT_CAPACITY],
	double_tap: Touch_Double_Tap,
}

// What the frame hands the overlay besides the fingers. ticked: the
// previous frame ran a simulation tick, so the world saw the aim and the
// press that frame sent. target_takes_interaction: the first player's
// target after that tick takes Interact (entity_takes_interact).
// hotbar_slots: the HUD's hotbar slots in render pixels
// (hud_hotbar_pixel_rectangles), and the slot the first player selected.
Touch_Interaction_Frame :: struct {
	interaction:              Touch_Interaction,
	frame_seconds:            f32,
	ticked:                   bool,
	target_takes_interaction: bool,
	hotbar_slots:             [HOTBAR_SLOT_COUNT]Ui_Rectangle,
	selected_hotbar_slot:     int,
	// A double_tap_toggles button may latch (0120): the sneak setting is
	// Hold. False releases every latch.
	double_tap_latches:       bool,
	// The HUD's touch buttons beside the hotbar (0134), in render pixels.
	hud_buttons:              [Hud_Touch_Button]Touch_Hud_Button,
}

// A HUD touch button as the overlay hit tests it: shown while the HUD
// draws it and a gamepad control is bound to its action.
Touch_Hud_Button :: struct {
	shown:     bool,
	rectangle: Ui_Rectangle,
	control:   Touch_Overlay_Control,
}

// What the fingers hold this frame. buttons by SDL button index; stick in
// the raw axis convention (x right, y down, -1 to 1); look_delta in mouse
// pixels. aim_point (render pixels) is where Mine, Place and Interact aim
// while aims is set, instead of the view's centre. jump_tap: a jump zone
// tap holds the Jump action (0134), jump_tap_edge on its first frame.
Touch_Overlay_Output :: struct {
	buttons:    [RAW_GAMEPAD_BUTTON_CAPACITY]bool,
	triggers:   [Gamepad_Trigger]bool,
	stick:      [2]f32,
	look_delta: [2]f32,
	aims:       bool,
	aim_point:  [2]f32,
	jump_tap:      bool,
	jump_tap_edge: bool,
}

// What the input backends merge into their frame. active while the
// overlay is on in a world; world_shown while no screen is open, when its
// drags turn the view instead of the pointer's.
// pointer_claimed: the first touch, which holds raylib's left mouse
// button, is a finger on one of the overlay's buttons, on a hotbar slot
// or on a HUD touch button, so the frame reads that button up
// (touch_overlay_mouse) and a Back tap never also clicks the widget under
// the pill.
// aim_direction: the render camera's ray through output.aim_point, set
// by the frame (read_touch_overlay_frame) while output.aims.
Touch_Overlay_Frame :: struct {
	active:          bool,
	world_shown:     bool,
	output:          Touch_Overlay_Output,
	pointer_claimed: bool,
	aim_direction:   [3]f32,
	// The slot a hotbar tap or a long press on another slot selects this
	// frame, -1 for none (0119); apply_touch_overlay_hotbar presses it.
	hotbar_tap:      int,
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

// Every control touch_overlay_control_from_name knows, the editor's rebind
// cycle (0121): the buttons in SDL's order, then the triggers.
touch_overlay_controls :: proc(allocator := context.temp_allocator) -> []Touch_Overlay_Control {
	controls := make([dynamic]Touch_Overlay_Control, allocator)
	for button in sdl.GamepadButton {
		if _, mapped := raylib_gamepad_button(button); mapped {
			append(&controls, Touch_Overlay_Control{button = button})
		}
	}
	for trigger in Gamepad_Trigger {
		append(&controls, Touch_Overlay_Control{is_trigger = true, trigger = trigger})
	}
	return controls[:]
}

// The control after this one in touch_overlay_controls, wrapping.
next_touch_overlay_control :: proc(control: Touch_Overlay_Control) -> Touch_Overlay_Control {
	controls := touch_overlay_controls()
	for candidate, index in controls {
		if candidate == control {
			return controls[(index + 1) % len(controls)]
		}
	}
	return controls[0]
}

// The strings key of a button's label for a control, which a rebind
// gives the button.
touch_overlay_control_label_key :: proc(control: Touch_Overlay_Control) -> string {
	if control.is_trigger {
		return control.trigger == .Left ? "touch_label_left_trigger" : "touch_label_right_trigger"
	}
	#partial switch control.button {
	case .SOUTH:
		return "touch_label_south"
	case .EAST:
		return "touch_label_east"
	case .WEST:
		return "touch_label_west"
	case .NORTH:
		return "touch_label_north"
	case .BACK:
		return "touch_label_back"
	case .GUIDE:
		return "touch_label_guide"
	case .START:
		return "touch_label_start"
	case .LEFT_STICK:
		return "touch_label_left_stick"
	case .RIGHT_STICK:
		return "touch_label_right_stick"
	case .LEFT_SHOULDER:
		return "touch_label_left_shoulder"
	case .RIGHT_SHOULDER:
		return "touch_label_right_shoulder"
	case .DPAD_UP:
		return "touch_label_dpad_up"
	case .DPAD_DOWN:
		return "touch_label_dpad_down"
	case .DPAD_LEFT:
		return "touch_label_dpad_left"
	case .DPAD_RIGHT:
		return "touch_label_dpad_right"
	}
	return "touch_label_south"
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
	if !entry.static {
		return entry.anchor != "" || entry.position != {} ? "a floating stick takes no anchor or position (static = true fixes it in place)" : ""
	}
	if entry.position == {} {
		return "a static stick needs an anchor and a position"
	}
	anchor, anchor_ok := name_to_enum(touch_overlay_anchor_names, entry.anchor)
	if !anchor_ok {
		return fmt.tprintf("unknown anchor %q (top_left, top_right, bottom_left, bottom_right, bottom_center, top_center)", entry.anchor)
	}
	element.anchor = anchor
	return ""
}

resolve_touch_overlay_look :: proc(entry: Touch_Overlay_Element_Entry, element: ^Touch_Overlay_Element) -> string {
	if problem := resolve_touch_overlay_side(entry, element); problem != "" {
		return problem
	}
	if entry.sensitivity <= 0 {
		return "the sensitivity must be positive"
	}
	controls := [?]struct {
		key:    string,
		name:   string,
		target: ^Touch_Overlay_Control,
	} {
		{"hold_control", entry.hold_control, &element.hold_control},
		{"tap_interact_control", entry.tap_interact_control, &element.tap_interact_control},
		{"tap_place_control", entry.tap_place_control, &element.tap_place_control},
	}
	for control in controls {
		ok: bool
		if control.target^, ok = touch_overlay_control_from_name(control.name); !ok {
			return fmt.tprintf("unknown %s %q (a gamepad button bindings.sjson names, or LEFT_TRIGGER, RIGHT_TRIGGER)", control.key, control.name)
		}
	}
	if entry.jump_zone_share < 0 || entry.jump_zone_share >= 1 {
		return "the jump_zone_share must be from 0 to below 1"
	}
	return ""
}

resolve_touch_overlay_element :: proc(entry: Touch_Overlay_Element_Entry) -> (element: Touch_Overlay_Element, problem: string) {
	kind, kind_ok := name_to_enum(touch_overlay_kind_names, entry.kind)
	if !kind_ok {
		return {}, fmt.tprintf("unknown kind %q (button, stick, look)", entry.kind)
	}
	element = Touch_Overlay_Element {
		kind               = kind,
		position           = entry.position,
		size               = entry.size,
		label              = entry.label,
		radius             = entry.radius,
		sprint_rim         = entry.sprint_rim,
		sensitivity        = entry.sensitivity,
		jump_zone_share    = entry.jump_zone_share,
		static             = entry.static,
		double_tap_toggles = entry.double_tap_toggles,
	}
	switch kind {
	case .Button:
		problem = resolve_touch_overlay_button(entry, &element)
	case .Stick:
		problem = resolve_touch_overlay_stick(entry, &element)
	case .Look:
		problem = resolve_touch_overlay_look(entry, &element)
	}
	if problem == "" && entry.opacity != 0 && (entry.opacity < TOUCH_OVERLAY_OPACITY_MINIMUM || entry.opacity > 1) {
		problem = "the opacity must be from 0.1 to 1"
	}
	element.opacity = entry.opacity == 0 ? 1 : entry.opacity
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
	if len(file.elements) > TOUCH_OVERLAY_ELEMENT_CAPACITY {
		return {}, fmt.tprintf("more than %d elements", TOUCH_OVERLAY_ELEMENT_CAPACITY)
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
	hotbar_drop_control, hotbar_drop_ok := touch_overlay_control_from_name(file.hotbar_drop_control)
	if !hotbar_drop_ok {
		delete(elements, allocator)
		return {}, fmt.tprintf("unknown hotbar_drop_control %q (a gamepad button bindings.sjson names, or LEFT_TRIGGER, RIGHT_TRIGGER)", file.hotbar_drop_control)
	}
	return Touch_Overlay_Layout{reference_height = file.reference_height, hotbar_drop_control = hotbar_drop_control, elements = elements}, ""
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
	data, path, read_error := read_data_file(data_directory, TOUCH_OVERLAY_FILE_NAME, context.temp_allocator)
	if read_error != nil {
		platform.log_printf("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	problem: string
	if layout, problem = parse_touch_overlay_file(data, path, allocator); problem != "" {
		platform.log_printf("error: invalid %s", problem)
		return {}, false
	}
	return layout, true
}

// User layouts (0121): touch_overlay.sjson in the user configuration
// directory holds the layouts the editor saved (ui_touch_layout_editor.odin)
// and the one selected. The data file's layout is "Default", which the
// user file never holds: it stays in Game_Content, so a data reload keeps
// applying to it.

DEFAULT_TOUCH_LAYOUT_NAME :: "Default"

// A layout of the user file: a name and the data file's keys.
Touch_Overlay_Named_Entry :: struct {
	name:                string,
	reference_height:    f32,
	hotbar_drop_control: string,
	elements:            []Touch_Overlay_Element_Entry,
}

Touch_Overlay_User_File :: struct {
	selected: string,
	layouts:  []Touch_Overlay_Named_Entry,
}

Named_Touch_Layout :: struct {
	name:   string,
	layout: Touch_Overlay_Layout,
}

// The user file's layouts, in arena. selection 0 is Default, n the layout
// layouts[n - 1]. changed: the active layout changed, so the frame loop
// releases the latches, which index its elements (serve_touch_layouts;
// the file's write is the frame request Write_Touch_Layouts). locked_path
// (owned): the file at start was broken, so nothing may overwrite it
// until the user fixed or removed it and started again.
Touch_Layouts :: struct {
	layouts:     []Named_Touch_Layout,
	selection:   int,
	arena:       ^virtual.Arena,
	changed:     bool,
	locked_path: string,
}

destroy_touch_layouts :: proc(layouts: ^Touch_Layouts) {
	destroy_arena(layouts.arena)
	delete(layouts.locked_path)
	layouts^ = {}
}

// The toast while the broken file stands, in the temp allocator.
touch_layouts_locked_text :: proc(layouts: Touch_Layouts) -> string {
	return fmt.tprintf("%s %s", text("touch_layout_file_locked"), layouts.locked_path)
}

// Empty for a name the editor may save under, else why not.
touch_layout_name_problem :: proc(name: string) -> string {
	switch {
	case strings.trim_space(name) == "":
		return "a layout needs a name"
	case strings.equal_fold(strings.trim_space(name), DEFAULT_TOUCH_LAYOUT_NAME):
		return "the name Default belongs to the data file's layout"
	}
	return ""
}

// "" and Default are Default (0); found is false for an unknown name.
touch_layout_selection :: proc(layouts: []Named_Touch_Layout, name: string) -> (selection: int, found: bool) {
	if name == "" || name == DEFAULT_TOUCH_LAYOUT_NAME {
		return 0, true
	}
	for layout, index in layouts {
		if layout.name == name {
			return index + 1, true
		}
	}
	return 0, false
}

touch_layout_name_taken :: proc(entries: []Touch_Overlay_Named_Entry, name: string) -> bool {
	for entry in entries {
		if entry.name == name {
			return true
		}
	}
	return false
}

resolve_touch_overlay_named_entry :: proc(entry: Touch_Overlay_Named_Entry, earlier: []Touch_Overlay_Named_Entry, allocator := context.allocator) -> (layout: Named_Touch_Layout, problem: string) {
	if problem = touch_layout_name_problem(entry.name); problem != "" {
		return {}, problem
	}
	if touch_layout_name_taken(earlier, entry.name) {
		return {}, fmt.tprintf("two layouts named %q", entry.name)
	}
	file := Touch_Overlay_File{reference_height = entry.reference_height, hotbar_drop_control = entry.hotbar_drop_control, elements = entry.elements}
	resolved: Touch_Overlay_Layout
	if resolved, problem = resolve_touch_overlay(file, allocator); problem != "" {
		return {}, fmt.tprintf("(%q): %s", entry.name, problem)
	}
	return Named_Touch_Layout{name = entry.name, layout = resolved}, ""
}

// Held to the configuration's strict keys like the data file. Every
// string is cloned into allocator.
parse_touch_layouts_file :: proc(data: []byte, source: string, allocator := context.allocator) -> (layouts: []Named_Touch_Layout, selection: int, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return nil, 0, parse_problem
	}
	provenance := make(Configuration_Provenance, context.temp_allocator)
	provenance[""] = source
	file: Touch_Overlay_User_File
	if problem = assign_configuration_value(any{&file, typeid_of(Touch_Overlay_User_File)}, json.Value(tree), "", provenance, allocator); problem != "" {
		return nil, 0, problem
	}
	layouts = make([]Named_Touch_Layout, len(file.layouts), allocator)
	for entry, index in file.layouts {
		if layouts[index], problem = resolve_touch_overlay_named_entry(entry, file.layouts[:index], allocator); problem != "" {
			return nil, 0, fmt.tprintf("%s: layouts[%d] %s", source, index, problem)
		}
	}
	found: bool
	if selection, found = touch_layout_selection(layouts, file.selected); !found {
		return nil, 0, fmt.tprintf("%s: selected %q names no layout", source, file.selected)
	}
	return layouts, selection, ""
}

// The user directory's file in the temp allocator, "" without a user
// directory.
touch_layouts_path :: proc(environment: Configuration_Environment) -> string {
	directory, found := user_configuration_directory(environment)
	return found ? platform.join_path(directory, TOUCH_OVERLAY_FILE_NAME) : ""
}

// No file is no user layouts. A file that cannot be read or is refused is
// logged like a broken data file and Default is used; problem says so,
// and the result is locked (locked_path) so no write replaces the file.
load_touch_layouts :: proc(environment: Configuration_Environment) -> (layouts: Touch_Layouts, problem: string) {
	path := touch_layouts_path(environment)
	if path == "" || !os.is_file(path) {
		return {}, ""
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		problem = fmt.tprintf("cannot read %s: %v", path, read_error)
		platform.log_printf("error: %s, the default touch layout is used", problem)
		return Touch_Layouts{locked_path = strings.clone(path)}, problem
	}
	arena := new_growing_arena()
	named: []Named_Touch_Layout
	selection: int
	named, selection, problem = parse_touch_layouts_file(data, path, virtual.arena_allocator(arena))
	if problem != "" {
		destroy_arena(arena)
		platform.log_printf("error: invalid %s, the default touch layout is used", problem)
		return Touch_Layouts{locked_path = strings.clone(path)}, problem
	}
	return Touch_Layouts{layouts = named, selection = selection, arena = arena}, ""
}

// The layout the overlay reads: the selected user layout, else Default.
active_touch_layout :: proc(layouts: Touch_Layouts, default_layout: Touch_Overlay_Layout) -> Touch_Overlay_Layout {
	if layouts.selection > 0 && layouts.selection <= len(layouts.layouts) {
		return layouts.layouts[layouts.selection - 1].layout
	}
	return default_layout
}

selected_touch_layout_name :: proc(layouts: Touch_Layouts) -> string {
	if layouts.selection > 0 && layouts.selection <= len(layouts.layouts) {
		return layouts.layouts[layouts.selection - 1].name
	}
	return DEFAULT_TOUCH_LAYOUT_NAME
}

// Default, then the user layouts in the file's order, wrapping.
next_touch_layout_selection :: proc(layouts: Touch_Layouts) -> int {
	return (layouts.selection + 1) % (len(layouts.layouts) + 1)
}

clone_touch_overlay_layout :: proc(layout: Touch_Overlay_Layout, allocator := context.allocator) -> Touch_Overlay_Layout {
	result := layout
	result.elements = make([]Touch_Overlay_Element, len(layout.elements), allocator)
	for element, index in layout.elements {
		result.elements[index] = element
		result.elements[index].label = strings.clone(element.label, allocator)
	}
	return result
}

// Cloned into a new arena before the old one goes, so named may point
// into it.
replace_touch_layouts :: proc(layouts: ^Touch_Layouts, named: []Named_Touch_Layout, selection: int) {
	arena := new_growing_arena()
	allocator := virtual.arena_allocator(arena)
	cloned := make([]Named_Touch_Layout, len(named), allocator)
	for layout, index in named {
		cloned[index] = Named_Touch_Layout{name = strings.clone(layout.name, allocator), layout = clone_touch_overlay_layout(layout.layout, allocator)}
	}
	destroy_arena(layouts.arena)
	layouts.layouts, layouts.selection, layouts.arena = cloned, selection, arena
}

// The layouts with name's replaced by layout, or layout added at the end,
// in the temp allocator (pointing into the originals).
touch_layouts_with :: proc(layouts: []Named_Touch_Layout, name: string, layout: Touch_Overlay_Layout) -> (result: []Named_Touch_Layout, selection: int) {
	named := make([dynamic]Named_Touch_Layout, 0, len(layouts) + 1, context.temp_allocator)
	append(&named, ..layouts)
	for &existing, index in named {
		if existing.name == name {
			existing.layout = layout
			return named[:], index + 1
		}
	}
	append(&named, Named_Touch_Layout{name = name, layout = layout})
	return named[:], len(named)
}

// The layouts without the one at selection, in the temp allocator.
touch_layouts_without :: proc(layouts: []Named_Touch_Layout, selection: int) -> []Named_Touch_Layout {
	named := make([dynamic]Named_Touch_Layout, 0, len(layouts), context.temp_allocator)
	for layout, index in layouts {
		if index + 1 != selection {
			append(&named, layout)
		}
	}
	return named[:]
}

touch_overlay_control_name :: proc(control: Touch_Overlay_Control) -> string {
	if control.is_trigger {
		return control.trigger == .Left ? GAMEPAD_LEFT_TRIGGER_NAME : GAMEPAD_RIGHT_TRIGGER_NAME
	}
	return fmt.tprint(control.button)
}

// One element in the data file's form, the keys its kind reads; opacity
// only when below 1. In the temp allocator.
touch_overlay_element_text :: proc(element: Touch_Overlay_Element) -> string {
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "{{kind = %q", touch_overlay_kind_names[element.kind])
	switch element.kind {
	case .Button:
		fmt.sbprintf(&builder, " control = %q shape = %q", touch_overlay_control_name(element.control), touch_overlay_shape_names[element.shape])
		fmt.sbprintf(&builder, " anchor = %q position = %v size = %v label = %q", touch_overlay_anchor_names[element.anchor], element.position, element.size, element.label)
		if element.double_tap_toggles {
			strings.write_string(&builder, " double_tap_toggles = true")
		}
	case .Stick:
		fmt.sbprintf(&builder, " side = %q radius = %v sprint_rim = %v", touch_overlay_side_names[element.side], element.radius, element.sprint_rim)
		if element.static {
			fmt.sbprintf(&builder, " static = true anchor = %q position = %v", touch_overlay_anchor_names[element.anchor], element.position)
		}
	case .Look:
		fmt.sbprintf(&builder, " side = %q sensitivity = %v", touch_overlay_side_names[element.side], element.sensitivity)
		fmt.sbprintf(&builder, " hold_control = %q", touch_overlay_control_name(element.hold_control))
		fmt.sbprintf(&builder, " tap_interact_control = %q", touch_overlay_control_name(element.tap_interact_control))
		fmt.sbprintf(&builder, " tap_place_control = %q", touch_overlay_control_name(element.tap_place_control))
		if element.jump_zone_share > 0 {
			fmt.sbprintf(&builder, " jump_zone_share = %v", element.jump_zone_share)
		}
	}
	if element.opacity < 1 {
		fmt.sbprintf(&builder, " opacity = %v", element.opacity)
	}
	strings.write_byte(&builder, '}')
	return strings.to_string(builder)
}

// The whole user file, in the temp allocator: written whole, since the
// layers' arrays replace wholesale.
touch_layouts_file_text :: proc(layouts: Touch_Layouts) -> string {
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "// Written by the touch layout editor (doc/touch_overlay.md, User layouts and the editor).\n")
	fmt.sbprintf(&builder, "selected = %q\n", selected_touch_layout_name(layouts))
	strings.write_string(&builder, "layouts = [\n")
	for named in layouts.layouts {
		layout := named.layout
		fmt.sbprintf(&builder, "\t{{name = %q reference_height = %v hotbar_drop_control = %q elements = [\n", named.name, layout.reference_height, touch_overlay_control_name(layout.hotbar_drop_control))
		for element in layout.elements {
			fmt.sbprintf(&builder, "\t\t%s\n", touch_overlay_element_text(element))
		}
		strings.write_string(&builder, "\t]}\n")
	}
	strings.write_string(&builder, "]\n")
	return strings.to_string(builder)
}

// Returns the problem, or an empty string.
write_touch_layouts_file :: proc(environment: Configuration_Environment, layouts: Touch_Layouts) -> string {
	directory, found := user_configuration_directory(environment)
	if !found {
		return "no configuration directory (set " + platform.CONFIG_HOME_VARIABLES + ")"
	}
	path := platform.join_path(directory, TOUCH_OVERLAY_FILE_NAME)
	return platform.write_file_replacing(path, transmute([]byte)touch_layouts_file_text(layouts))
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

// The offset from the anchor that puts an element's centre at point, the
// inverse of anchored_position (the editor's move, 0121).
anchored_offset :: proc(anchor: Touch_Overlay_Anchor, point, screen_size: [2]f32) -> [2]f32 {
	switch anchor {
	case .Top_Left:
		return point
	case .Top_Right:
		return {screen_size.x - point.x, point.y}
	case .Bottom_Left:
		return {point.x, screen_size.y - point.y}
	case .Bottom_Right:
		return screen_size - point
	case .Bottom_Center:
		return {point.x - screen_size.x / 2, screen_size.y - point.y}
	case .Top_Center:
		return {point.x - screen_size.x / 2, point.y}
	}
	return point
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

// The first element of the kind on either side, -1 for none.
layout_element :: proc(layout: Touch_Overlay_Layout, kind: Touch_Overlay_Kind) -> int {
	for element, index in layout.elements {
		if element.kind == kind {
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
// Start or Back is that button and every other finger the pointer's. In
// the world a finger on a HUD touch button or a hotbar slot is that one's,
// before the free screen reaches under them, and one inside a free static
// stick's base is the stick. Every other finger is undecided (Pending,
// reading the look element's controls) on either half (0134); a layout
// without a look keeps the floating stick on its half. hotbar_slot is -1
// but for Hotbar, hud_control set only for Hud_Button.
classify_touch :: proc(state: Touch_Overlay_State, layout: Touch_Overlay_Layout, placed: []Placed_Element, point, screen_size: [2]f32, world_shown: bool, inputs: Touch_Interaction_Frame) -> (role: Touch_Role, element: int, hotbar_slot: int, hud_control: Touch_Overlay_Control) {
	if button := button_at(placed_for_screen(layout, placed, world_shown, context.temp_allocator), point); button >= 0 {
		return .Button, button, -1, {}
	}
	if !world_shown {
		return .Ignored, -1, -1, {}
	}
	if control, found := hud_touch_button_at(inputs.hud_buttons, point); found {
		return .Hud_Button, -1, -1, control
	}
	if slot := hotbar_slot_at(inputs.hotbar_slots, point); slot >= 0 {
		return .Hotbar, -1, slot, {}
	}
	stick := zone_element(layout, .Stick, screen_side(point, screen_size))
	stick_free := stick >= 0 && !stick_held(state)
	if stick_free && layout.elements[stick].static && stick_reaches(layout, layout.elements[stick], point, screen_size) {
		return .Stick, stick, -1, {}
	}
	if look := layout_element(layout, .Look); look >= 0 {
		return .Pending, look, -1, {}
	}
	if stick_free && !layout.elements[stick].static {
		return .Stick, stick, -1, {}
	}
	return .Ignored, -1, -1, {}
}

// The control of the shown HUD touch button under the point.
hud_touch_button_at :: proc(buttons: [Hud_Touch_Button]Touch_Hud_Button, point: [2]f32) -> (control: Touch_Overlay_Control, found: bool) {
	for button in buttons {
		if button.shown && rectangle_contains(button.rectangle, point) {
			return button.control, true
		}
	}
	return {}, false
}

// What a Pending finger's drag becomes: the floating stick of the half it
// landed on while no finger holds the stick, else -1 for the look drag.
pending_drag_stick :: proc(state: Touch_Overlay_State, layout: Touch_Overlay_Layout, origin, screen_size: [2]f32) -> int {
	stick := zone_element(layout, .Stick, screen_side(origin, screen_size))
	if stick < 0 || layout.elements[stick].static || stick_held(state) {
		return -1
	}
	return stick
}

// A static stick's base centre in render pixels, anchored like a button.
static_stick_centre :: proc(layout: Touch_Overlay_Layout, stick: Touch_Overlay_Element, screen_size: [2]f32) -> [2]f32 {
	return anchored_position(stick.anchor, stick.position * touch_overlay_scale(layout, screen_size), screen_size)
}

// A floating stick takes a touch anywhere on its half, a static one only
// inside its base circle.
stick_reaches :: proc(layout: Touch_Overlay_Layout, stick: Touch_Overlay_Element, point, screen_size: [2]f32) -> bool {
	if !stick.static {
		return true
	}
	return linalg.length(point - static_stick_centre(layout, stick, screen_size)) <= stick.radius * touch_overlay_scale(layout, screen_size)
}

// Where a new finger's drag counts from: a static stick's base centre,
// else where it landed.
touch_origin :: proc(layout: Touch_Overlay_Layout, role: Touch_Role, element: int, point, screen_size: [2]f32) -> [2]f32 {
	if role == .Stick && layout.elements[element].static {
		return static_stick_centre(layout, layout.elements[element], screen_size)
	}
	return point
}

// The hotbar slot under the point, -1 for none.
hotbar_slot_at :: proc(slots: [HOTBAR_SLOT_COUNT]Ui_Rectangle, point: [2]f32) -> int {
	for rectangle, index in slots {
		if rectangle_contains(rectangle, point) {
			return index
		}
	}
	return -1
}

// A Hotbar finger that moves past the slop (a drag or a flick that began
// on the hotbar) is spent and fires nothing. One that rests
// TOUCH_HOLD_SECONDS is the long press, which fires once: on the selected
// slot it holds the drop control from then on, on another slot it selects
// that slot (tap) and nothing more.
advance_hotbar_touch :: proc(slot: Touch_Slot, slop, frame_seconds: f32, selected: int) -> (result: Touch_Slot, tap: int) {
	result, tap = slot, -1
	if result.role != .Hotbar || result.hotbar_spent {
		return
	}
	if linalg.length(result.position - result.origin) > slop {
		result.hotbar_spent = true
		return
	}
	result.held_seconds += frame_seconds
	if result.held_seconds < TOUCH_HOLD_SECONDS {
		return
	}
	result.hotbar_spent = true
	if result.hotbar_slot == selected {
		result.hotbar_drops = true
	} else {
		tap = result.hotbar_slot
	}
	return
}

// A lift before the long press and within the slop is a tap on the slot,
// in the world only.
lifted_hotbar_taps :: proc(slot: Touch_Slot, world_shown: bool) -> bool {
	return world_shown && slot.role == .Hotbar && !slot.hotbar_spent
}

// The time since the last lift, forgotten past TOUCH_DOUBLE_TAP_SECONDS.
advance_double_tap :: proc(double_tap: Touch_Double_Tap, frame_seconds: f32) -> Touch_Double_Tap {
	result := double_tap
	result.seconds += frame_seconds
	return result.armed && result.seconds <= TOUCH_DOUBLE_TAP_SECONDS ? result : {}
}

// A tap's lift (down shorter than TOUCH_HOLD_SECONDS) on a
// double_tap_toggles button that neither latched nor released it starts
// the wait for the second tap; a longer press does not.
lifted_button_arms_double_tap :: proc(slot: Touch_Slot, layout: Touch_Overlay_Layout) -> bool {
	return slot.role == .Button && !slot.toggle_spent && slot.held_seconds < TOUCH_HOLD_SECONDS && touch_slot_reads(slot, layout) && layout.elements[slot.element].double_tap_toggles
}

// The latches index the layout's elements, so a data reload that installs
// a new layout (replace_frame_content) releases them and forgets the
// double tap, rather than leaving a latch on an element that moved.
release_touch_latches :: proc(state: Touch_Overlay_State) -> Touch_Overlay_State {
	result := state
	result.latched, result.double_tap = {}, {}
	return result
}

// A finger landing on a double_tap_toggles button: on a latched one it
// releases the latch (the finger still holds the button until it lifts),
// within TOUCH_DOUBLE_TAP_SECONDS of the last lift of the same button it
// latches it. spent: either happened.
touch_down_toggles :: proc(state: Touch_Overlay_State, layout: Touch_Overlay_Layout, element: int) -> (latched: bit_set[0 ..< TOUCH_OVERLAY_ELEMENT_CAPACITY], spent: bool) {
	latched = state.latched
	if !layout.elements[element].double_tap_toggles {
		return latched, false
	}
	switch {
	case element in latched:
		return latched - {element}, true
	case state.double_tap.armed && state.double_tap.element == element:
		return latched + {element}, true
	}
	return latched, false
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

// A tap past its aim once a tick has run with it presses the control the
// target calls for, and ends once a tick has run with the press. A screen
// opening, a data reload that removed its look element, or a wait for a
// tick longer than TOUCH_HOLD_SECONDS drops it.
advance_touch_tap :: proc(tap: Touch_Tap, layout: Touch_Overlay_Layout, world_shown: bool, inputs: Touch_Interaction_Frame) -> Touch_Tap {
	if !world_shown || tap.phase == .None || !look_element_valid(layout, tap.element) {
		return {}
	}
	if !inputs.ticked {
		waiting := tap
		waiting.fresh = false
		waiting.waited_seconds += inputs.frame_seconds
		return waiting.waited_seconds > TOUCH_HOLD_SECONDS ? {} : waiting
	}
	if tap.phase == .Pressing {
		return {}
	}
	control := tap_control(layout.elements[tap.element], inputs.target_takes_interaction)
	return Touch_Tap{phase = .Pressing, point = tap.point, element = tap.element, control = control, aims = tap.aims}
}

// A tap in the look's jump zone presses Jump at once and aims nowhere;
// any other tap aims at the point first.
lifted_touch_tap :: proc(layout: Touch_Overlay_Layout, slot: Touch_Slot, screen_size: [2]f32) -> Touch_Tap {
	if jump_zone_contains(layout.elements[slot.element], slot.position, screen_size) {
		return Touch_Tap{phase = .Pressing, point = slot.position, element = slot.element, jumps = true, fresh = true}
	}
	return Touch_Tap{phase = .Aiming, point = slot.position, element = slot.element, aims = true}
}

// The rightmost jump_zone_share of the screen's width; none at 0.
jump_zone_contains :: proc(look: Touch_Overlay_Element, point, screen_size: [2]f32) -> bool {
	return look.jump_zone_share > 0 && point.x >= screen_size.x * (1 - look.jump_zone_share)
}

look_element_valid :: proc(layout: Touch_Overlay_Layout, element: int) -> bool {
	return element >= 0 && element < len(layout.elements) && layout.elements[element].kind == .Look
}

// Interact's control on a target that takes it, else Place's, through the
// bindings like the buttons.
tap_control :: proc(look: Touch_Overlay_Element, target_takes_interaction: bool) -> Touch_Overlay_Control {
	return target_takes_interaction ? look.tap_interact_control : look.tap_place_control
}

// An undecided finger becomes a drag once it moves past the slop, taking
// the drag so far on this frame: the stick element stick (centred where
// the finger landed) unless it is -1, else the look drag. One that rests
// TOUCH_HOLD_SECONDS inside the slop becomes a hold. A hold that moves
// past the slop becomes the stick the same way when stick is not -1 (a
// thumb that rested before it pushed), which ends its Mine and its aim; a
// hold with no stick to become keeps mining where the finger goes.
advance_pending_touch :: proc(slot: Touch_Slot, slop, frame_seconds: f32, stick: int) -> Touch_Slot {
	result := slot
	if result.role == .Hold && stick >= 0 && linalg.length(result.position - result.origin) > slop {
		result.role, result.element = .Stick, stick
		return result
	}
	if result.role != .Pending {
		return result
	}
	result.held_seconds += frame_seconds
	switch {
	case linalg.length(result.position - result.origin) > slop && stick >= 0:
		result.role, result.element = .Stick, stick
	case linalg.length(result.position - result.origin) > slop:
		result.role = .Look
		result.previous = result.origin
	case result.held_seconds >= TOUCH_HOLD_SECONDS:
		result.role = .Hold
	}
	return result
}

// A finger lifting while still undecided in the world is a tap, unless a
// tap is still in flight (a second one would move its aim before its press
// was read) or another finger holds (the hold owns the aim and the dig).
lifted_touch_taps :: proc(state: Touch_Overlay_State, slot: Touch_Slot, layout: Touch_Overlay_Layout, world_shown: bool) -> bool {
	return world_shown && slot.role == .Pending && touch_slot_reads(slot, layout) && state.tap.phase == .None && !touch_hold_held(state)
}

touch_hold_held :: proc(state: Touch_Overlay_State) -> bool {
	for slot in state.slots {
		if slot.active && slot.role == .Hold {
			return true
		}
	}
	return false
}

// Moves the fingers still down, forgets the lifted ones and gives each
// new finger its role from where it landed. Returns the hotbar slot a
// finger selected this frame, -1 for none.
update_touch_overlay :: proc(state: ^Touch_Overlay_State, points: []Touch_Point, layout: Touch_Overlay_Layout, placed: []Placed_Element, screen_size: [2]f32, world_shown: bool, inputs: Touch_Interaction_Frame) -> (hotbar_tap: int) {
	hotbar_tap = -1
	state.tap = advance_touch_tap(state.tap, layout, world_shown, inputs)
	state.double_tap = advance_double_tap(state.double_tap, inputs.frame_seconds)
	// Only while the sneak setting is Hold: in Toggle a tap already
	// toggles, and a latch would swallow the next toggle's edge.
	if !inputs.double_tap_latches {
		state^ = release_touch_latches(state^)
	}
	slop := TOUCH_TAP_SLOP * touch_overlay_scale(layout, screen_size)
	for &slot in state.slots {
		if !slot.active {
			continue
		}
		point, found := find_touch_point(points, slot.id)
		if !found {
			if lifted_touch_taps(state^, slot, layout, world_shown) {
				state.tap = lifted_touch_tap(layout, slot, screen_size)
			}
			if lifted_hotbar_taps(slot, world_shown) {
				hotbar_tap = slot.hotbar_slot
			}
			if inputs.double_tap_latches && lifted_button_arms_double_tap(slot, layout) {
				state.double_tap = Touch_Double_Tap{armed = true, element = slot.element}
			}
			slot = {}
			continue
		}
		slot.previous, slot.position = slot.position, point.position
		if slot.role == .Button {
			slot.held_seconds += inputs.frame_seconds
		}
		// Not under a screen, where the held stick reads nothing: a rim
		// crossing there would be a fresh press the frame it closes.
		if world_shown {
			slot = advance_pending_touch(slot, slop, inputs.frame_seconds, pending_drag_stick(state^, layout, slot.origin, screen_size))
			slot.sprint_latched = stick_sprint_latched(slot, layout, screen_size)
			long_press_tap: int
			if slot, long_press_tap = advance_hotbar_touch(slot, slop, inputs.frame_seconds, inputs.selected_hotbar_slot); long_press_tap >= 0 {
				hotbar_tap = long_press_tap
			}
		}
	}
	// A hold that begins while a tap is still in flight owns the aim: the
	// tap is dropped rather than firing at the held block.
	if touch_hold_held(state^) {
		state.tap = {}
	}
	for point in points {
		if touch_slot_tracks(state^, point.id) {
			continue
		}
		free_index := free_touch_slot(state^)
		if free_index < 0 {
			return hotbar_tap
		}
		role, element, hotbar_slot, hud_control := classify_touch(state^, layout, placed, point.position, screen_size, world_shown, inputs)
		origin := touch_origin(layout, role, element, point.position, screen_size)
		toggle_spent: bool
		if role == .Button && inputs.double_tap_latches {
			state.latched, toggle_spent = touch_down_toggles(state^, layout, element)
		}
		if toggle_spent {
			state.double_tap = {}
		}
		state.slots[free_index] = Touch_Slot{active = true, id = point.id, role = role, element = element, hotbar_slot = hotbar_slot, origin = origin, position = point.position, previous = point.position, toggle_spent = toggle_spent, hud_control = hud_control}
	}
	return hotbar_tap
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
	case .Ignored, .Hotbar, .Hud_Button:
	case .Button:
		press_touch_control(output, element.control)
	case .Stick:
		output.stick = touch_stick_value(slot.position - slot.origin, element.radius * scale)
		if slot.sprint_latched {
			output.buttons[int(sdl.GamepadButton.LEFT_STICK)] = true
		}
	case .Look:
		output.look_delta += (slot.position - slot.previous) * element.sensitivity
	case .Pending:
	case .Hold:
		press_touch_control(output, element.hold_control)
		output.aims, output.aim_point = true, slot.position
	}
}

add_touch_tap_output :: proc(output: ^Touch_Overlay_Output, tap: Touch_Tap) {
	switch tap.phase {
	case .None:
		return
	case .Aiming:
	case .Pressing:
		if tap.jumps {
			output.jump_tap, output.jump_tap_edge = true, tap.fresh
		} else {
			press_touch_control(output, tap.control)
		}
	}
	if tap.aims {
		output.aims, output.aim_point = true, tap.point
	}
}

// False for an ignored finger, a hotbar or HUD button finger (it reads no
// layout element), and for one whose element a data reload removed or
// replaced with another kind.
touch_slot_reads :: proc(slot: Touch_Slot, layout: Touch_Overlay_Layout) -> bool {
	if !slot.active || slot.element < 0 || slot.element >= len(layout.elements) {
		return false
	}
	kind := layout.elements[slot.element].kind
	switch slot.role {
	case .Ignored, .Hotbar, .Hud_Button:
		return false
	case .Button:
		return kind == .Button
	case .Stick:
		return kind == .Stick
	case .Look, .Pending, .Hold:
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
		if world_shown && slot.active && slot.role == .Hotbar && slot.hotbar_drops {
			press_touch_control(&output, layout.hotbar_drop_control)
		}
		if world_shown && slot.active && slot.role == .Hud_Button {
			press_touch_control(&output, slot.hud_control)
		}
	}
	for element in state.latched {
		if latched_button_reads(layout, element, world_shown) {
			press_touch_control(&output, layout.elements[element].control)
		}
	}
	if world_shown {
		add_touch_tap_output(&output, state.tap)
	}
	return output
}

// A latched button presses like a held one, Start and Back alone under a
// screen; after a data reload only while its element still toggles.
latched_button_reads :: proc(layout: Touch_Overlay_Layout, element: int, world_shown: bool) -> bool {
	if element >= len(layout.elements) {
		return false
	}
	button := layout.elements[element]
	return button.kind == .Button && button.double_tap_toggles && (world_shown || control_serves_screens(button.control))
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

// The tap scheme's aim into the input frame, where the player's target
// takes it instead of the look direction (tick_player). The simulation
// gets the direction like the look delta and never calls raylib.
apply_touch_overlay_aim :: proc(frame: Input_Frame, overlay: Touch_Overlay_Frame) -> Input_Frame {
	result := frame
	if touch_overlay_drives_world(overlay) && overlay.output.aims {
		result.aim_direction, result.aim_overrides = overlay.aim_direction, true
	}
	return result
}

// The hotbar's slot selection into the input frame (0119), one of the two
// places the overlay presses an action rather than a gamepad control (the
// jump tap is the other): selecting a
// given slot has no gamepad control to press (the drop has, d-pad down).
// An edge only: the tick accumulator carries just_pressed to the next
// tick over frames that run none, and the simulation reads it as an edge.
apply_touch_overlay_hotbar :: proc(frame: Input_Frame, overlay: Touch_Overlay_Frame) -> Input_Frame {
	result := frame
	if !touch_overlay_drives_world(overlay) {
		return result
	}
	slot_actions := HOTBAR_SLOT_ACTIONS
	if overlay.hotbar_tap >= 0 && overlay.hotbar_tap < HOTBAR_SLOT_COUNT {
		result.just_pressed += {slot_actions[overlay.hotbar_tap]}
	}
	return result
}

// A jump zone tap into the input frame as the Jump action (0134), the
// other place the overlay presses an action: SOUTH is Interact too, and
// Interact wins over Jump on an entity with a panel (resolve_interact), so
// a jump tap through the gamepad would open a machine under the view's
// centre. Held until a tick has run with it, like the tap's press, and
// just_pressed on its first frame, which the tick accumulator carries.
apply_touch_overlay_jump :: proc(frame: Input_Frame, overlay: Touch_Overlay_Frame) -> Input_Frame {
	result := frame
	if !touch_overlay_drives_world(overlay) {
		return result
	}
	if overlay.output.jump_tap {
		result.pressed += {.Jump}
	}
	if overlay.output.jump_tap_edge {
		result.just_pressed += {.Jump}
	}
	return result
}

// What the overlay reads of the frame, built by the loop at each use
// (touch_overlay_context): the input group, whose touch_overlay it
// writes, and the session, content, settings, the camera the world was
// last drawn with and the tick count, which live outside that group.
Touch_Overlay_Context :: struct {
	interaction:      ^Frame_Interaction,
	session:          ^Session,
	content:          ^Game_Content,
	settings:         ^Settings,
	render_camera:    rl.Camera3D,
	frame_seconds:    f32,
	frame_tick_count: int,
}

// The tap scheme hides the crosshair and rings the mined block instead
// (draw_hud), whenever the overlay is on in a world.
touch_overlay_aims :: proc(touch_context: Touch_Overlay_Context) -> bool {
	return touch_context.session != nil && touch_overlay_on(touch_context) && touch_context.settings.touch_interaction == .Tap
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

touch_overlay_on :: proc(touch_context: Touch_Overlay_Context) -> bool {
	return touch_overlay_enabled(touch_context.settings.touch_overlay, touch_context.interaction.touch_overlay_forced, ODIN_PLATFORM_SUBTARGET == .Android)
}

// The tap scheme's inputs: frame_tick_count is still the previous frame's
// here (update_session sets it after the input is read), and the target is
// the one that frame's last tick found.
touch_interaction_frame :: proc(touch_context: Touch_Overlay_Context) -> Touch_Interaction_Frame {
	simulation := &touch_context.session.simulation
	selected := simulation.players[0].selected_hotbar_slot
	return Touch_Interaction_Frame {
		interaction = touch_context.settings.touch_interaction,
		frame_seconds = touch_context.frame_seconds,
		ticked = touch_context.frame_tick_count > 0,
		target_takes_interaction = entity_takes_interact(&simulation.world.entities, simulation.players[0].target.entity),
		hotbar_slots = hud_hotbar_pixel_rectangles(&touch_context.interaction.ui, selected),
		selected_hotbar_slot = selected,
		double_tap_latches = touch_context.settings.sneak_hold == .Hold,
		hud_buttons = frame_hud_touch_buttons(touch_context),
	}
}

// The first gamepad control bound to the action outside the menus on
// this backend that the overlay can press (0134), so a rebound action
// keeps its HUD touch button.
touch_control_for_action :: proc(bindings: []Binding, action: Action, backend: Input_Backend) -> (control: Touch_Overlay_Control, found: bool) {
	for binding in bindings {
		if binding.action != action || binding.device != .Gamepad || binding.binding_context == .Menu || backend not_in binding.backends {
			continue
		}
		if control, found = touch_overlay_control_from_name(binding.control); found {
			return control, true
		}
	}
	return {}, false
}

// The HUD touch buttons drawn and read this frame: none unless the
// overlay is on in a world without the layout editor, else those whose
// action has a control to press, Rotate only while the selection rotates.
frame_hud_touch_buttons_shown :: proc(touch_context: Touch_Overlay_Context) -> bit_set[Hud_Touch_Button] {
	if touch_context.session == nil || !touch_overlay_on(touch_context) || touch_layout_editor_shown(touch_context.interaction.ui.screens) {
		return {}
	}
	content := touch_context.content
	simulation := &touch_context.session.simulation
	player := simulation.players[0]
	rotates := selected_placement_rotates(player, content.machines, content.blocks, content.items) || entity_rotates(&simulation.world.entities, player.target.entity)
	shown: bit_set[Hud_Touch_Button]
	for button in hud_touch_buttons_shown(rotates) {
		if _, bound := touch_control_for_action(touch_context.interaction.bindings, hud_touch_button_actions[button], touch_context.interaction.input_backend); bound {
			shown += {button}
		}
	}
	return shown
}

// The shown buttons in render pixels, where the overlay hit tests them,
// as the HUD last laid them out (like hud_hotbar_pixel_rectangles).
frame_hud_touch_buttons :: proc(touch_context: Touch_Overlay_Context) -> (buttons: [Hud_Touch_Button]Touch_Hud_Button) {
	rectangles := hud_touch_button_rectangles(ui_safe_area(&touch_context.interaction.ui))
	for button in frame_hud_touch_buttons_shown(touch_context) {
		control, _ := touch_control_for_action(touch_context.interaction.bindings, hud_touch_button_actions[button], touch_context.interaction.input_backend)
		buttons[button] = Touch_Hud_Button{shown = true, rectangle = units_to_pixels_rectangle(rectangles[button], touch_context.interaction.ui.pixels_per_unit), control = control}
	}
	return buttons
}

units_to_pixels_rectangle :: proc(rectangle: Ui_Rectangle, pixels_per_unit: f32) -> Ui_Rectangle {
	return Ui_Rectangle{rectangle.x * pixels_per_unit, rectangle.y * pixels_per_unit, rectangle.width * pixels_per_unit, rectangle.height * pixels_per_unit}
}

// The render camera's ray through a point in render pixels, as a
// direction from the eye the simulation casts the target from. The camera
// is the last frame's (Frame_Presentation.render_camera); before the first world
// frame it is empty and the aim stays off.
touch_aim_direction :: proc(point: [2]f32, camera: rl.Camera3D, screen_size: [2]int, world: ^World, registry: Block_Registry, eye: [3]f32) -> (direction: [3]f32, ok: bool) {
	if camera.fovy <= 0 {
		return {}, false
	}
	ray := rl.GetScreenToWorldRayEx(point, camera, i32(screen_size.x), i32(screen_size.y))
	return eye_aim_direction(world, registry, eye, ray.position, linalg.normalize0(ray.direction)), true
}

// A little into the hit block, so the eye's ray to the point enters it
// rather than stopping on its face.
TOUCH_AIM_INSET :: 0.01

// The direction from the eye to what the camera ray hits, or to its far
// end when it hits nothing. In third person the camera sits behind and
// beside the eye, so its ray's own direction cast from the eye would pick
// another block; in first person the two coincide. The reach counts from
// the eye, so the ray reaches the camera's distance to the eye further.
eye_aim_direction :: proc(world: ^World, registry: Block_Registry, eye, ray_origin, ray_direction: [3]f32) -> [3]f32 {
	reach := PLAYER_REACH + linalg.length(ray_origin - eye)
	hit := raycast_blocks(world, registry, ray_origin, ray_direction, reach)
	distance := hit.hit ? hit.distance + TOUCH_AIM_INSET : reach
	return linalg.normalize0(ray_origin + ray_direction * distance - eye)
}

// The layout the overlay reads: the selected user layout, else Default
// (0121).
frame_touch_layout :: proc(touch_context: Touch_Overlay_Context) -> Touch_Overlay_Layout {
	return active_touch_layout(touch_context.interaction.touch_layouts, touch_context.content.touch_overlay)
}

// The layout editor on top draws the layout itself and takes every touch
// as the pointer, so the overlay neither reads nor draws (0121).
touch_layout_editor_shown :: proc(screens: Screen_Stack) -> bool {
	return top_screen(screens) == .Touch_Layout
}

// Only in a world: the title screens take touch as the pointer alone.
read_touch_overlay_frame :: proc(touch_context: Touch_Overlay_Context) -> Touch_Overlay_Frame {
	if !touch_overlay_on(touch_context) || touch_context.session == nil || touch_layout_editor_shown(touch_context.interaction.ui.screens) {
		touch_context.interaction.touch_overlay = {}
		return {}
	}
	screen_size := render_size()
	screen := [2]f32{f32(screen_size.x), f32(screen_size.y)}
	buffer: [TOUCH_POINT_CAPACITY]Touch_Point
	frame := touch_overlay_frame(&touch_context.interaction.touch_overlay, frame_touch_layout(touch_context), read_touch_points(buffer[:]), screen, !ui_blocks_world(touch_context.interaction.ui.screens), touch_interaction_frame(touch_context))
	frame.output.look_delta = render_pixels_to_window_units(frame.output.look_delta, cursor_window_size(), screen_size)
	if frame.output.aims {
		simulation := &touch_context.session.simulation
		eye := player_eye(simulation.players[0].position)
		frame.aim_direction, frame.output.aims = touch_aim_direction(frame.output.aim_point, touch_context.render_camera, screen_size, &simulation.world, touch_context.content.blocks, eye)
	}
	return frame
}

// One frame of the overlay from this frame's fingers, in touch index
// order, so points[0] is the touch raylib holds the left mouse button for
// (the mouse itself on the desktop).
touch_overlay_frame :: proc(state: ^Touch_Overlay_State, layout: Touch_Overlay_Layout, points: []Touch_Point, screen_size: [2]f32, world_shown: bool, inputs: Touch_Interaction_Frame) -> Touch_Overlay_Frame {
	placed := overlay_layout(layout, screen_size, context.temp_allocator)
	hotbar_tap := update_touch_overlay(state, points, layout, placed, screen_size, world_shown, inputs)
	return Touch_Overlay_Frame {
		active = true,
		world_shown = world_shown,
		output = touch_scheme_output(touch_overlay_output(state^, layout, screen_size, world_shown), inputs.interaction),
		pointer_claimed = len(points) > 0 && touch_claims_pointer(state^, layout, points[0].id),
		hotbar_tap = hotbar_tap,
	}
}

// The crosshair scheme keeps the gestures and aims them at the view's
// centre (0134): the output carries no aim.
touch_scheme_output :: proc(output: Touch_Overlay_Output, interaction: Touch_Interaction) -> Touch_Overlay_Output {
	result := output
	if interaction == .Crosshair {
		result.aims, result.aim_point = false, {}
	}
	return result
}

// A finger on one of the overlay's buttons, in the world or over a screen,
// on a hotbar slot or on a HUD touch button.
touch_claims_pointer :: proc(state: Touch_Overlay_State, layout: Touch_Overlay_Layout, id: i32) -> bool {
	for slot in state.slots {
		if slot.active && slot.id == id {
			return slot.role == .Hotbar || slot.role == .Hud_Button || (slot.role == .Button && touch_slot_reads(slot, layout))
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

// Outlines and labels at a low alpha times the element's opacity, a held
// or latched button filled.
// Nothing moves but with a finger, so nothing pulses (DESIGN.md).
TOUCH_OVERLAY_COLOR :: Ui_Color{255, 255, 255, 140}
TOUCH_OVERLAY_LINE :: 4.0
// The knob's radius over the stick's radius.
TOUCH_OVERLAY_KNOB_FRACTION :: 0.4

pixels_to_units_rectangle :: proc(centre, size: [2]f32, pixels_per_unit: f32) -> Ui_Rectangle {
	corner := (centre - size / 2) / pixels_per_unit
	return Ui_Rectangle{corner.x, corner.y, size.x / pixels_per_unit, size.y / pixels_per_unit}
}

// A UI y a gap below the lowest top_center button, 0 without one: the
// discovery card's top keeps clear of Back and Start (0123).
touch_overlay_top_center_clearance :: proc(layout: Touch_Overlay_Layout, placed: []Placed_Element, pixels_per_unit: f32) -> f32 {
	clearance: f32 = 0
	for element in placed {
		if layout.elements[element.element].anchor == .Top_Center {
			rectangle := pixels_to_units_rectangle(element.centre, element.size, pixels_per_unit)
			clearance = max(clearance, rectangle.y + rectangle.height + UI_GAP)
		}
	}
	return clearance
}

// The clearance of the layout in use while the overlay is drawn (the
// condition run_ui_frame draws it under), else 0.
discovery_card_clearance :: proc(touch_context: Touch_Overlay_Context) -> f32 {
	if touch_context.session == nil || !touch_overlay_on(touch_context) || touch_layout_editor_shown(touch_context.interaction.ui.screens) {
		return 0
	}
	size := render_size()
	screen_pixels := [2]f32{f32(size.x), f32(size.y)}
	layout := frame_touch_layout(touch_context)
	return touch_overlay_top_center_clearance(layout, overlay_layout(layout, screen_pixels, context.temp_allocator), touch_context.interaction.ui.pixels_per_unit)
}

// The overlay's colour with an element's opacity (0121) on its alpha.
touch_overlay_color :: proc(opacity: f32) -> Ui_Color {
	color := TOUCH_OVERLAY_COLOR
	color.a = u8(f32(color.a) * clamp(opacity, 0, 1) + 0.5)
	return color
}

draw_touch_overlay_button :: proc(ui: ^Ui_State, rectangle: Ui_Rectangle, shape: Touch_Overlay_Shape, down: bool, label: string, color: Ui_Color) {
	switch shape {
	case .Rectangle:
		if down {
			draw_fill(ui, rectangle, color)
		}
		draw_outline(ui, rectangle, color, TOUCH_OVERLAY_LINE)
	case .Circle:
		if down {
			draw_circle(ui, rectangle, color)
		}
		draw_ring(ui, rectangle, color, TOUCH_OVERLAY_LINE)
	}
	draw_text(ui, rectangle, label, UI_BODY_TEXT_SIZE, .Centre, color)
}

draw_touch_stick :: proc(ui: ^Ui_State, slot: Touch_Slot, radius: f32, color: Ui_Color) {
	diameter := [2]f32{2 * radius, 2 * radius}
	draw_ring(ui, pixels_to_units_rectangle(slot.origin, diameter, ui.pixels_per_unit), color, TOUCH_OVERLAY_LINE)
	draw_circle(ui, pixels_to_units_rectangle(slot.position, diameter * TOUCH_OVERLAY_KNOB_FRACTION, ui.pixels_per_unit), color)
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
		draw_touch_overlay_button(ui, rectangle, shown.shape, touch_overlay_control_down(output, element.control), element.label, touch_overlay_color(element.opacity))
	}
	if !world_shown {
		return
	}
	scale := touch_overlay_scale(layout, screen_pixels)
	for slot in state.slots {
		if slot.role == .Stick && touch_slot_reads(slot, layout) {
			stick := layout.elements[slot.element]
			draw_touch_stick(ui, slot, stick.radius * scale, touch_overlay_color(stick.opacity))
		}
	}
	// A static stick at rest: its base with the knob centred.
	for element in layout.elements {
		if element.kind == .Stick && element.static && !stick_held(state) {
			centre := static_stick_centre(layout, element, screen_pixels)
			draw_touch_stick(ui, Touch_Slot{origin = centre, position = centre}, element.radius * scale, touch_overlay_color(element.opacity))
		}
	}
}
