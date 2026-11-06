package game

// The tech demos' list (work item 0302): one button per demo, today the
// water one, then Back.
//
// The water tech demo's menu (work item 0291): three choices (the water
// model, the planet radius, the start point) and Start, over the title's
// backdrop with no world behind it. Start asks the frame loop for the
// demo session (Session_Request_Kind.Tech_Demo), which
// start_tech_demo_session builds from Title_State.tech_demo.

// Heading, Water, Back.
TECH_DEMOS_ROW_COUNT :: 3
TECH_DEMO_PANEL_WIDTH :: 720
// Heading, three rows, the button row.
TECH_DEMO_ROW_COUNT :: 5

Tech_Demo_Start :: enum u8 {
	Home,
	Spring,
}

// The menu's values; the command line's --tech-demo words fill the same.
Tech_Demo_Setup :: struct {
	water_model:          Water_Model,
	// 0 is the planet's default (Planet.radius_metres).
	planet_radius_metres: int,
	start:                Tech_Demo_Start,
}

DEFAULT_TECH_DEMO_SETUP :: Tech_Demo_Setup {
	start = .Spring,
}

// The setup's radius, or the default planet's when 0 (0 without planets).
tech_demo_radius_metres :: proc(setup: Tech_Demo_Setup, planets: []Planet) -> int {
	if setup.planet_radius_metres != 0 {
		return setup.planet_radius_metres
	}
	if len(planets) == 0 {
		return 0
	}
	return default_planet(planets).radius_metres
}

// The next preset of the default planet, as step_world_setup_radius;
// nothing without planets.
step_tech_demo_radius :: proc(setup: ^Tech_Demo_Setup, planets: []Planet) {
	if len(planets) == 0 {
		return
	}
	presets := default_planet(planets).radius_presets_metres
	current := choice_index(presets, tech_demo_radius_metres(setup^, planets), len(presets) - 1)
	setup.planet_radius_metres = presets[next_choice(current, len(presets))]
}

step_tech_demo_model :: proc(setup: ^Tech_Demo_Setup) {
	setup.water_model = Water_Model(next_choice(int(setup.water_model), len(Water_Model)))
}

step_tech_demo_start :: proc(setup: ^Tech_Demo_Setup) {
	setup.start = Tech_Demo_Start(next_choice(int(setup.start), len(Tech_Demo_Start)))
}

tech_demo_model_text :: proc(model: Water_Model) -> string {
	switch model {
	case .Teleport:
		return text("tech_demo_model_teleport")
	case .Bodies:
		return text("tech_demo_model_bodies")
	}
	return ""
}

tech_demo_start_text :: proc(start: Tech_Demo_Start) -> string {
	switch start {
	case .Home:
		return text("tech_demo_start_home")
	case .Spring:
		return text("tech_demo_start_spring")
	}
	return ""
}

// Start asks the frame loop for the demo world of the title's setup.
start_tech_demo :: proc(title: ^Title_State) {
	title.request = {kind = .Tech_Demo}
}

// The bare --tech-demo's screens over the title, pushed as the title's
// buttons push them, so Back walks the same way.
push_tech_demo_menu :: proc(screens: ^Screen_Stack) {
	push_screen(screens, .Tech_Demos)
	push_screen(screens, .Tech_Demo)
}

tech_demos_screen :: proc(state: ^Ui_State) {
	panel := fitted_panel(ui_panel_area(state), TITLE_PANEL_WIDTH, panel_height(TECH_DEMOS_ROW_COUNT, -UI_GAP))
	ui_panel_begin(state, "tech_demos", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_row(&content), text("tech_demos_title"), UI_HEADING_TEXT_SIZE, .Centre)
	if ui_button(state, cut_row(&content), text("tech_demos_water")) {
		push_screen(&state.screens, .Tech_Demo)
	}
	if ui_button(state, cut_row(&content), text("new_world_back")) {
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}

tech_demo_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	setup := &screen_context.title.tech_demo
	planets := screen_context.planets
	panel := fitted_panel(ui_panel_area(state), TECH_DEMO_PANEL_WIDTH, panel_height(TECH_DEMO_ROW_COUNT, -UI_GAP))
	ui_panel_begin(state, "tech_demo", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_row(&content), text("tech_demo_title"), UI_HEADING_TEXT_SIZE, .Centre)
	if ui_choice(state, cut_row(&content), text("tech_demo_model"), tech_demo_model_text(setup.water_model), text("tech_demo_model_tooltip")) {
		step_tech_demo_model(setup)
	}
	radius := format_message_text(text("new_world_kilometres"), kilometres_number_text(tech_demo_radius_metres(setup^, planets)))
	if ui_choice(state, cut_row(&content), text("new_world_radius"), radius, text("new_world_radius_tooltip")) {
		step_tech_demo_radius(setup, planets)
	}
	if ui_choice(state, cut_row(&content), text("tech_demo_start"), tech_demo_start_text(setup.start), text("tech_demo_start_tooltip")) {
		step_tech_demo_start(setup)
	}
	button_row := cut_row(&content)
	if ui_button(state, column_rectangle(button_row, 2, 0, UI_GAP), text("tech_demo_start_button")) {
		start_tech_demo(screen_context.title)
	}
	if ui_button(state, column_rectangle(button_row, 2, 1, UI_GAP), text("new_world_back")) {
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}
