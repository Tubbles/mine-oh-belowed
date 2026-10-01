package game

import "core:encoding/json"
import "core:testing"

// The UI theme and its art (work item 0071). None of these touch raylib.

UI_THEME_METRIC_NAMES :: [?]string{"border", "corner", "focus_pulse"}

@(test)
test_default_theme_is_the_old_look :: proc(t: ^testing.T) {
	colors := DEFAULT_UI_THEME.colors
	testing.expect_value(t, colors[.Panel], Ui_Color{24, 26, 34, 230})
	testing.expect_value(t, colors[.Panel_Edge], Ui_Color{90, 96, 120, 255})
	testing.expect_value(t, colors[.Widget], Ui_Color{44, 48, 62, 255})
	testing.expect_value(t, colors[.Widget_Hover], Ui_Color{60, 66, 86, 255})
	testing.expect_value(t, colors[.Accent], Ui_Color{236, 176, 64, 255})
	testing.expect_value(t, colors[.Text], Ui_Color{235, 235, 240, 255})
	testing.expect_value(t, colors[.Text_Dim], Ui_Color{160, 164, 180, 255})
	// The focus outline was the accent, tooltips and toasts the panel.
	testing.expect_value(t, colors[.Focus], colors[.Accent])
	testing.expect_value(t, colors[.Tooltip], colors[.Panel])
	testing.expect_value(t, colors[.Toast], colors[.Panel])
	// The new elements are off.
	testing.expect_value(t, colors[.Panel_Highlight].a, 0)
	testing.expect_value(t, colors[.Widget_Active].a, 0)
	testing.expect_value(t, colors[.Divider].a, 0)
	testing.expect_value(t, DEFAULT_UI_THEME.border, 2)
	testing.expect_value(t, DEFAULT_UI_THEME.corner, 0)
	testing.expect_value(t, DEFAULT_UI_THEME.focus_pulse, 0)
	// The screens' names start at the defaults.
	testing.expect_value(t, UI_PANEL_COLOR, colors[.Panel])
	testing.expect_value(t, UI_TEXT_COLOR, colors[.Text])
	testing.expect_value(t, UI_BORDER, DEFAULT_UI_THEME.border)
}

@(test)
test_theme_parses_and_keeps_defaults_for_missing_keys :: proc(t: ^testing.T) {
	theme, problem := parse_ui_theme(transmute([]byte)string("panel = [1, 2, 3, 4]\ncorner = 6\nfocus_pulse = 2.5"), "theme.sjson")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, theme.colors[.Panel], Ui_Color{1, 2, 3, 4})
	testing.expect_value(t, theme.corner, 6)
	testing.expect_value(t, theme.focus_pulse, 2.5)
	testing.expect_value(t, theme.colors[.Accent], DEFAULT_UI_THEME.colors[.Accent])
	testing.expect_value(t, theme.border, DEFAULT_UI_THEME.border)
	unchanged, unchanged_problem := parse_ui_theme(transmute([]byte)string("// Only a default.\nborder = 2\n"), "theme.sjson")
	testing.expect_value(t, unchanged_problem, "")
	testing.expect_value(t, unchanged, DEFAULT_UI_THEME)
}

@(test)
test_theme_refuses_wrong_types_naming_the_file :: proc(t: ^testing.T) {
	cases := [?]struct {
		text:    string,
		mention: string,
	} {
		{`panel = "dark"`, "panel must be an array of 4"},
		{`panel = [1, 2, 3]`, "panel must be an array of 4"},
		{`accent = [1, 2, 3, 256]`, "accent[3] must be a whole number"},
		{`accent = [1, 2.5, 3, 4]`, "accent[1] must be a whole number"},
		{`corner = "round"`, "corner must be a number"},
		{`border = 100`, "border is 100"},
		{`panel_colour = [1, 2, 3, 4]`, "unknown key panel_colour"},
		{`panel = [1, 2, 3, 4`, "cannot parse"},
	}
	for entry in cases {
		theme, problem := parse_ui_theme(transmute([]byte)entry.text, "data/ui/theme.sjson")
		expect_problem_mentions(t, problem, "data/ui/theme.sjson", entry.mention)
		testing.expect_value(t, theme, Ui_Theme{})
	}
}

@(test)
test_shipped_theme_has_every_key :: proc(t: ^testing.T) {
	data := #load("../data/ui/theme.sjson")
	theme, problem := parse_ui_theme(data, "data/ui/theme.sjson")
	testing.expect_value(t, problem, "")
	testing.expect(t, theme.corner > 0 && theme.focus_pulse > 0, "the shipped theme cuts corners and pulses the focus")
	tree, parse_problem := parse_configuration_layer(data, "data/ui/theme.sjson", context.temp_allocator)
	testing.expect_value(t, parse_problem, "")
	for name in ui_theme_color_names {
		testing.expectf(t, name in tree, "the shipped theme sets %s", name)
	}
	for name in UI_THEME_METRIC_NAMES {
		testing.expectf(t, name in tree, "the shipped theme sets %s", name)
	}
	// The marker palettes (work item 0074), each with every colour.
	palettes, has_palettes := tree["palettes"].(json.Object)
	testing.expect(t, has_palettes, "the shipped theme sets palettes")
	for palette_name in marker_palette_names {
		colors, has_palette := palettes[palette_name].(json.Object)
		testing.expectf(t, has_palette, "the shipped theme sets palettes.%s", palette_name)
		for color_name in palette_color_names {
			testing.expectf(t, color_name in colors, "the shipped theme sets palettes.%s.%s", palette_name, color_name)
		}
	}
	testing.expect_value(t, len(tree), len(Ui_Theme_Color) + len(UI_THEME_METRIC_NAMES) + 1)
}

@(test)
test_theme_reaches_the_screens_names :: proc(t: ^testing.T) {
	// Only the theme's own copy is set here: the names are shared by
	// every test thread, so this checks the state side alone.
	state: Ui_State
	testing.expect_value(t, ui_theme(&state), DEFAULT_UI_THEME)
	theme := DEFAULT_UI_THEME
	theme.colors[.Panel] = {1, 2, 3, 4}
	state.theme = theme
	testing.expect_value(t, theme_color(&state, .Panel), Ui_Color{1, 2, 3, 4})
}

// The glyphs before 0151 (the old glyph_icon and glyph_keyboard_*
// strings); the shipped bindings must keep showing them, so a reorder of
// data/bindings.sjson that changes a first binding fails here.
@(rodata)
default_gamepad_glyph_icons := [Glyph_Button]Ui_Icon {
	.Confirm        = .Button_South,
	.Back           = .Button_East,
	.Tab_Previous   = .Bumper_Left,
	.Tab_Next       = .Bumper_Right,
	.Info           = .Button_North,
	.Context_Action = .Button_West,
	.Pause          = .Menu,
	.Inventory      = .Button_West,
	.Secondary      = .Trigger_Left,
	.Interact       = .Button_South,
	.Use_Item       = .Trigger_Left,
	.Sprint         = .Stick_Left,
	.Quick_Move     = .Trigger_Right,
	.Drop           = .Stick_Right,
}

@(rodata)
default_keyboard_glyph_labels := [Glyph_Button]string {
	.Confirm        = "Enter",
	.Back           = "Esc",
	.Tab_Previous   = "Q",
	.Tab_Next       = "E",
	.Info           = "R",
	.Context_Action = "F",
	.Pause          = "Esc",
	.Inventory      = "E",
	.Secondary      = "Shift",
	.Interact       = "F",
	.Use_Item       = "Right mouse",
	.Sprint         = "Ctrl",
	.Quick_Move     = "Q",
	.Drop           = "X",
}

@(test)
test_glyph_icon_per_button_and_device :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"))
	defer destroy_string_table(&table)
	testing.expect_value(t, error, nil)
	thread_string_table = &table
	defer thread_string_table = nil
	for backend in Input_Backend {
		keyboard := Ui_State {
			active_device = .Keyboard_Mouse,
			bindings      = shipped_default_bindings(t),
			input_backend = backend,
		}
		gamepad := keyboard
		gamepad.active_device = .Gamepad
		for button in Glyph_Button {
			testing.expectf(t, glyph(&keyboard, button) == Glyph{.Key, default_keyboard_glyph_labels[button]}, "%v %v keyboard: %v", backend, button, glyph(&keyboard, button))
			testing.expectf(t, glyph(&gamepad, button) == Glyph{default_gamepad_glyph_icons[button], ""}, "%v %v gamepad: %v", backend, button, glyph(&gamepad, button))
		}
	}
}

@(test)
test_glyphs_follow_a_rebinding :: proc(t: ^testing.T) {
	defer clear_missing_reports(&global_string_table)
	configuration := `bindings = [
		{action = "Confirm" device = "gamepad" control = "NORTH" context = "menu"}
		{action = "Confirm" device = "keyboard" control = "PAGE_DOWN" context = "menu"}
		{action = "Confirm" device = "keyboard" control = "SPACE" context = "menu"}
		{action = "Info_Panel" device = "gamepad" control = "LEFT_PADDLE1" context = "menu"}
		{action = "Info_Panel" device = "gamepad" control = "WEST" context = "menu"}
		{action = "Pause" device = "gamepad" control = "START" context = "both"}
	]`
	overrides, problem := parse_bindings_file(transmute([]byte)configuration, "configuration", context.temp_allocator)
	testing.expect_value(t, problem, "")
	defaults := shipped_default_bindings(t)
	keyboard := Ui_State {
		active_device = .Keyboard_Mouse,
		bindings      = defaults,
		input_backend = .Sdl3,
	}
	gamepad := keyboard
	gamepad.active_device = .Gamepad
	default_keyboard_confirm := glyph(&keyboard, .Confirm)
	testing.expect_value(t, glyph(&gamepad, .Confirm), Glyph{.Button_South, ""})
	keyboard.bindings = effective_bindings(defaults, overrides, context.temp_allocator)
	gamepad.bindings = keyboard.bindings
	// The first of several bindings.
	testing.expect_value(t, glyph(&keyboard, .Confirm), Glyph{.Key, "Page Down"})
	testing.expect(t, default_keyboard_confirm.label != "Page Down")
	testing.expect_value(t, glyph(&gamepad, .Confirm), Glyph{.Button_North, ""})
	// A control without an icon shows its name on a key cap.
	testing.expect_value(t, glyph(&gamepad, .Info), Glyph{.Key, "Left Paddle 1"})
	// raylib cannot read the paddle, so the next binding shows.
	gamepad.input_backend = .Raylib
	testing.expect_value(t, glyph(&gamepad, .Info), Glyph{.Button_West, ""})
	// An action the configuration leaves alone keeps its default.
	testing.expect_value(t, glyph(&gamepad, .Back), Glyph{.Button_East, ""})
	// Pause lost its Esc, so the keyboard's Back shows Back's own key.
	testing.expect_value(t, glyph(&keyboard, .Back), Glyph{.Key, "Backspace"})
	// An action without a control on the device.
	keyboard.bindings = overrides
	testing.expect_value(t, glyph(&keyboard, .Back), Glyph{.Key, text("glyph_unbound")})
}

@(test)
test_readable_control_names :: proc(t: ^testing.T) {
	testing.expect_value(t, readable_control_name("PAGE_DOWN"), "Page Down")
	testing.expect_value(t, readable_control_name("LEFT_PADDLE1"), "Left Paddle 1")
	testing.expect_value(t, readable_control_name("MISC2"), "Misc 2")
	testing.expect_value(t, readable_control_name("F3"), "F3")
	testing.expect_value(t, readable_control_name("KP_1"), "Kp 1")
}

@(test)
test_glyph_bar_draws_icons_and_key_caps :: proc(t: ^testing.T) {
	defer clear_missing_reports(&global_string_table)
	for device in Input_Device {
		state := Ui_State {
			active_device = device,
			bindings      = shipped_default_bindings(t),
		}
		defer destroy_ui_state(&state)
		test_ui_frame(&state, {})
		hints := [?]Glyph_Hint{{.Confirm, "Select"}, {.Back, "Back"}}
		ui_glyph_bar(&state, hints[:])
		// Drawn from the right, so the last hint comes first.
		icons, texts := 0, 0
		for command in state.draw_list {
			#partial switch command.kind {
			case .Ui_Icon:
				icons += 1
				testing.expect_value(t, Ui_Icon(command.tile), glyph(&state, hints[len(hints) - icons].button).icon)
			case .Text:
				texts += 1
			case .Fill, .Outline:
				testing.expect(t, false, "the glyph bar draws no lettered boxes")
			}
		}
		testing.expect_value(t, icons, 2)
		// The labels, and on the keyboard the key names on the caps.
		testing.expect_value(t, texts, device == .Gamepad ? 2 : 4)
	}
}

@(test)
test_default_panel_art_is_a_fill_and_an_outline :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {})
	rectangle := Ui_Rectangle{100, 100, 400, 300}
	ui_panel_begin(&state, "panel", rectangle)
	ui_panel_end(&state)
	testing.expect_value(t, len(state.draw_list), 2)
	testing.expect_value(t, state.draw_list[0].kind, Draw_Command_Kind.Fill)
	testing.expect_value(t, state.draw_list[0].color, DEFAULT_UI_THEME.colors[.Panel])
	testing.expect_value(t, state.draw_list[0].rectangle, rectangle)
	testing.expect_value(t, state.draw_list[1].kind, Draw_Command_Kind.Outline)
	testing.expect_value(t, state.draw_list[1].color, DEFAULT_UI_THEME.colors[.Panel_Edge])
	testing.expect_value(t, state.draw_list[1].thickness, 2)
}

rectangles_overlap :: proc(first, second: Ui_Rectangle) -> bool {
	_, overlaps := rectangle_intersection(first, second)
	return overlaps
}

area_of :: proc(rectangle: Ui_Rectangle) -> f32 {
	return rectangle.width * rectangle.height
}

@(test)
test_cut_corner_pieces_stay_inside_and_never_overlap :: proc(t: ^testing.T) {
	rectangle := Ui_Rectangle{10, 20, 300, 200}
	corner, thickness := f32(8), f32(2)
	fills := cut_corner_fills(rectangle, corner)
	frame := cut_corner_frame(rectangle, corner, thickness)
	fill_area := f32(0)
	for fill, index in fills {
		testing.expect(t, rectangle_inside(fill, rectangle, 0))
		fill_area += area_of(fill)
		for other in fills[index + 1:] {
			testing.expect(t, !rectangles_overlap(fill, other))
		}
	}
	// The rectangle less the four corner squares.
	testing.expect_value(t, fill_area, area_of(rectangle) - 4 * corner * corner)
	for piece, index in frame {
		testing.expect(t, piece.width > 0 && piece.height > 0)
		inside_a_fill := false
		for fill in fills {
			inside_a_fill ||= rectangle_inside(piece, fill, 0)
		}
		testing.expectf(t, inside_a_fill || rectangle_inside(piece, {rectangle.x, rectangle.y + corner, rectangle.width, rectangle.height - 2 * corner}, 0), "piece %d lies on the shape", index)
		for other in frame[index + 1:] {
			testing.expectf(t, !rectangles_overlap(piece, other), "piece %d overlaps another", index)
		}
	}
	// Too small for the lines: square corners.
	testing.expect_value(t, fitted_corner({0, 0, 6, 6}, 8, 2), 0)
	testing.expect_value(t, fitted_corner(rectangle, 0, 2), 0)
	testing.expect_value(t, fitted_corner(rectangle, 1, 2), 2)
	testing.expect_value(t, fitted_corner({0, 0, 20, 20}, 16, 2), 8)
}

@(test)
test_themed_panel_draws_inside_its_rectangle :: proc(t: ^testing.T) {
	theme, problem := parse_ui_theme(#load("../data/ui/theme.sjson"), "data/ui/theme.sjson")
	testing.expect_value(t, problem, "")
	state := Ui_State {
		theme = theme,
	}
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {})
	rectangle := Ui_Rectangle{100, 100, 400, 300}
	ui_panel_begin(&state, "panel", rectangle)
	ui_panel_end(&state)
	edge_pieces, highlight_pieces := 0, 0
	for command in state.draw_list {
		testing.expect(t, rectangle_inside(command.rectangle, rectangle, 0))
		if command.color == theme.colors[.Panel_Edge] {
			edge_pieces += 1
		} else if command.color == theme.colors[.Panel_Highlight] {
			highlight_pieces += 1
		}
	}
	testing.expect_value(t, edge_pieces, 12)
	testing.expect_value(t, highlight_pieces, 12)
}

@(test)
test_widget_states :: proc(t: ^testing.T) {
	theme := DEFAULT_UI_THEME
	testing.expect_value(t, widget_fill_color(theme, false, false), theme.colors[.Widget])
	testing.expect_value(t, widget_fill_color(theme, true, false), theme.colors[.Widget_Hover])
	// Without a pressed colour, pressed looks like hovered or plain.
	testing.expect_value(t, widget_fill_color(theme, true, true), theme.colors[.Widget_Hover])
	testing.expect_value(t, widget_fill_color(theme, false, true), theme.colors[.Widget])
	theme.colors[.Widget_Active] = {9, 9, 9, 255}
	testing.expect_value(t, widget_fill_color(theme, false, true), Ui_Color{9, 9, 9, 255})
	// Confirm held on the focused button draws it pressed.
	state := Ui_State {
		theme = theme,
	}
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {confirm_down = true})
	state.focus = ui_id(&state, "button")
	ui_button(&state, {0, 0, 200, 56}, "button")
	testing.expect_value(t, state.draw_list[0].color, Ui_Color{9, 9, 9, 255})
}

@(test)
test_focus_outline_pulses_inwards :: proc(t: ^testing.T) {
	testing.expect_value(t, focus_pulse_phase(0), 0)
	testing.expect(t, abs(focus_pulse_phase(UI_FOCUS_PULSE_SECONDS / 2) - 1) < 1e-5)
	theme := DEFAULT_UI_THEME
	testing.expect_value(t, focus_outline_thickness(theme, 1), UI_FOCUS_BORDER)
	theme.focus_pulse = 3
	testing.expect_value(t, focus_outline_thickness(theme, 0), UI_FOCUS_BORDER)
	testing.expect_value(t, focus_outline_thickness(theme, 1), UI_FOCUS_BORDER + 3)
	// The pulse advances with the frames and stays in one period.
	state: Ui_State
	defer destroy_ui_state(&state)
	for _ in 0 ..< 200 {
		test_ui_frame(&state, {})
		testing.expect(t, state.focus_pulse_seconds >= 0 && state.focus_pulse_seconds < UI_FOCUS_PULSE_SECONDS)
		testing.expect(t, state.focus_pulse >= 0 && state.focus_pulse <= 1)
	}
}

@(test)
test_toggle_knob_slides_to_its_side :: proc(t: ^testing.T) {
	testing.expect_value(t, slide_towards(0, 1, 0.25), 0.25)
	testing.expect_value(t, slide_towards(0.9, 1, 0.25), 1)
	testing.expect_value(t, slide_towards(1, 0, 0.25), 0.75)
	track := Ui_Rectangle{0, 0, UI_TOGGLE_WIDTH, UI_CHECKBOX_SIZE}
	off, on := toggle_knob_rectangle(track, 0), toggle_knob_rectangle(track, 1)
	testing.expect(t, rectangle_inside(off, track, 0) && rectangle_inside(on, track, 0))
	testing.expect_value(t, off.x, UI_TOGGLE_KNOB_INSET)
	testing.expect_value(t, on.x + on.width, UI_TOGGLE_WIDTH - UI_TOGGLE_KNOB_INSET)
	// Flipped, the knob moves over the next frames rather than at once.
	state: Ui_State
	defer destroy_ui_state(&state)
	value := false
	row := Ui_Rectangle{0, 0, 400, 56}
	test_ui_frame(&state, {})
	ui_toggle(&state, row, "toggle", &value)
	id := ui_id(&state, "toggle")
	testing.expect_value(t, state.knob_positions[id].position, 0)
	value = true
	test_ui_frame(&state, {})
	ui_toggle(&state, row, "toggle", &value)
	testing.expect(t, state.knob_positions[id].position > 0 && state.knob_positions[id].position < 1)
	for _ in 0 ..< 60 {
		test_ui_frame(&state, {})
		ui_toggle(&state, row, "toggle", &value)
	}
	testing.expect_value(t, state.knob_positions[id].position, 1)
	// Not drawn for a frame (its screen closed), then drawn at the other
	// value: the knob starts there instead of sliding (0132).
	test_ui_frame(&state, {})
	value = false
	test_ui_frame(&state, {})
	ui_toggle(&state, row, "toggle", &value)
	testing.expect_value(t, state.knob_positions[id].position, 0)
}

@(test)
test_tabs_draw_their_icons :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {})
	labels := [?]string{"One", "Two"}
	icons := [?]Ui_Icon{.Inventory, .Recipes}
	strip := Ui_Rectangle{0, 0, 600, 56}
	ui_tabs(&state, strip, "tabs", labels[:], icons[:])
	found: [dynamic]Ui_Icon
	defer delete(found)
	for command in state.draw_list {
		testing.expect(t, rectangle_inside(command.rectangle, strip, 0))
		if command.kind == .Ui_Icon {
			append(&found, Ui_Icon(command.tile))
		}
	}
	testing.expect_value(t, len(found), 2)
	testing.expect_value(t, found[0], Ui_Icon.Inventory)
	testing.expect_value(t, found[1], Ui_Icon.Recipes)
}

@(test)
test_map_dots_take_their_category_colour :: proc(t: ^testing.T) {
	theme := DEFAULT_UI_THEME
	for category in Item_Category {
		theme.colors[Ui_Theme_Color(int(Ui_Theme_Color.Map_Marker_Raw) + int(category))] = {u8(category) * 40, 1, 2, 255}
	}
	for category in Item_Category {
		testing.expect_value(t, map_marker_color(theme, category), Ui_Color{u8(category) * 40, 1, 2, 255})
	}
	item_definitions := [?]Item{{id = "drill_item", category = .Machine}, {id = "loose_block", category = .Block}}
	items := Item_Registry {
		items = item_definitions[:],
	}
	machine_definitions := [?]Machine{{id = "drill", item = 0}, {id = "odd", item = 1}, {id = "capsule", item = NO_ITEM}}
	machines := Machine_Registry {
		machines = machine_definitions[:],
	}
	colors := machine_marker_colors(theme, machines, items)
	testing.expect_value(t, colors[0], map_marker_color(theme, .Machine))
	testing.expect_value(t, colors[1], map_marker_color(theme, .Block))
	testing.expect_value(t, colors[2], map_marker_color(theme, .Machine))
}
