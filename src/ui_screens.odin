package game

import "core:fmt"
import "core:math"

// The screens on the stack over the world and its HUD. Only the top screen
// is drawn and interactive.

PAUSE_PANEL_WIDTH :: 560
SETTINGS_PANEL_WIDTH :: 960
// Title, tabs, the longest tab's rows and the back button. The tabs
// scroll where the panel is shorter (UI scale 1.5).
SETTINGS_ROW_COUNT :: 14
DISPLAY_SETTINGS_ROW_COUNT :: 13
CONTROL_SETTINGS_ROW_COUNT :: 5

Screen_Context :: struct {
	settings:        ^Settings,
	// The monitor's size (display.odin): the Resolution choices up to it,
	// and the Resolution row's value in borderless.
	monitor_size:    [2]int,
	// The Font choices cycle through them (data/fonts/fonts.sjson).
	font_families:   []Font_Family,
	// The effective bindings, shown read only.
	bindings:        []Binding,
	quit_requested:  ^bool,
	// Nil without a world.
	save_requested:  ^bool,
	// The title screens' state and the requests to start or leave a world.
	title:           ^Title_State,
	player:          ^Player,
	items:           Item_Registry,
	blocks:          Block_Registry,
	item_sort_ranks: []u16,
	world:           ^World,
	machines:        Machine_Registry,
	fluids:          Fluid_Registry,
	veins:           Vein_Content,
	tick_rate:       int,
	recipes:         Recipe_Registry,
	technologies:    Technology_Registry,
	unlocks:         ^Recipe_Unlocks,
	quests:          Quest_Registry,
	quest_state:     ^Quest_State,
	contracts:       Contract_Registry,
	// The simulation's tick, for the contracts' time left.
	tick:            u64,
	recipe_names:    []string,
	recipe_order:    []int,
	browser:         ^Recipe_Browser,
	technology_browser: ^Technology_Browser,
	statistics_view:    ^Statistics_View,
	map_view:           ^Map_View,
	// The session's generator, for the biomes on the map and the HUD
	// banner. Nil without a world.
	generator:          ^Generator,
	// Kept by the frame loop across frames (biome_banner.odin). Nil in
	// tests that draw no HUD.
	biome_banner:       ^Biome_Banner,
	// --dev: the pause menu shows the Developer entry (ui_developer.odin);
	// the developer_mode setting shows it too.
	developer_mode:     bool,
	show_diagnostics:   ^bool,
	show_world_overlay: ^bool,
	// The simulation's developer cheat speed, before pending requests.
	cheat_speed:        bool,
	// Nil without a world.
	developer_requests: ^[dynamic]Developer_Request,
	// The chapters the developer screen offers: one per kit.
	developer_chapter_count: int,
	landing_pad:        Landing_Pad_Site,
	// The Developer screen's Screenshot button sets it; the frame loop
	// takes the picture (work item 0053).
	screenshot_requested: ^bool,
	// The Developer screen's Reload data button sets it; the frame loop
	// reloads the content tables (hot_reload.odin, work item 0054). Nil
	// without a world.
	reload_requested:     ^bool,
	// Content files changed since the content was loaded.
	data_changed:         bool,
}

// Pause opens the pause menu from the world, Open_Inventory the inventory,
// Open_Recipes the recipe browser, Open_Journal the journal (which it also
// closes), Open_Power_Overview the power overview, Open_Statistics the
// production statistics, Open_Technologies the technology screen and
// Open_Map the map (likewise). With a
// screen open, Back and Pause both
// step back one screen (the first press closes an open tooltip).
// Open_Inventory closes the inventory and a machine panel too, except on
// the gamepad, where the same X press is the context action; Open_Recipes
// closes the recipe browser.
handle_screen_keys :: proc(state: ^Ui_State) {
	input := state.input
	if state.screens.count == 0 {
		switch {
		case input.pause:
			push_screen(&state.screens, .Pause)
		case input.open_inventory:
			push_screen(&state.screens, .Inventory)
		case input.open_recipes:
			push_screen(&state.screens, .Recipes)
		case input.open_journal:
			push_screen(&state.screens, .Journal)
		case input.open_power:
			push_screen(&state.screens, .Power)
		case input.open_statistics:
			push_screen(&state.screens, .Statistics)
		case input.open_technologies:
			push_screen(&state.screens, .Technologies)
		case input.open_map:
			push_screen(&state.screens, .Map)
		}
		return
	}
	top := top_screen(state.screens)
	// The title is the bottom screen while no world is played.
	if top == .Title {
		return
	}
	closes_inventory := (top == .Inventory || top == .Machine) && input.open_inventory && !input.context_action
	closes_recipes := top == .Recipes && input.open_recipes
	closes_journal := top == .Journal && input.open_journal
	closes_power := top == .Power && input.open_power
	closes_technologies := top == .Technologies && input.open_technologies
	closes_statistics := top == .Statistics && input.open_statistics
	closes_map := top == .Map && input.open_map
	closes_screen := closes_inventory || closes_recipes || closes_journal || closes_power || closes_technologies || closes_statistics || closes_map
	if !input.back && !input.pause && !closes_screen {
		return
	}
	if state.tooltip_open {
		state.tooltip_open = false
		return
	}
	pop_screen(&state.screens)
}

run_screens :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	screen := top_screen(state.screens)
	// Read before the screen runs: the B press that closes the keyboard
	// must not also close the screen.
	typing := state.keyboard.field != 0
	switch screen {
	case .None:
	case .Pause:
		pause_screen(state, screen_context)
	case .Settings:
		settings_screen(state, screen_context)
	case .Developer:
		developer_screen(state, screen_context)
	case .Inventory:
		inventory_screen(state, screen_context)
	case .Machine:
		machine_screen(state, screen_context)
	case .Recipes:
		recipe_screen(state, screen_context)
	case .Journal:
		journal_screen(state, screen_context)
	case .Power:
		power_overview_screen(state, screen_context)
	case .Statistics:
		statistics_screen(state, screen_context)
	case .Technologies:
		technology_screen(state, screen_context)
	case .Map:
		map_screen(state, screen_context)
	case .Title:
		title_screen(state, screen_context)
	case .New_World:
		new_world_screen(state, screen_context)
	case .Load_World:
		load_world_screen(state, screen_context)
	case .Confirm_Delete:
		confirm_delete_screen(state, screen_context)
	}
	// After the screen, so that the Back press a screen consumed this frame
	// and the screen change land in the same frame. While the keyboard is
	// open, Back and Pause belong to it.
	if !typing {
		handle_screen_keys(state)
	}
	if screen_context.player != nil {
		close_slot_screens(state, screen_context.player, screen_context.items)
	}
	if screen_context.browser != nil && top_screen(state.screens) != .Recipes {
		screen_context.browser.selecting_for = NO_ENTITY
	}
	// The next opening centres on the player and reads the surfaces anew.
	if screen_context.map_view != nil && top_screen(state.screens) != .Map {
		screen_context.map_view.active = false
	}
}

screen_stack_contains :: proc(stack: Screen_Stack, screen: Screen) -> bool {
	for index in 0 ..< stack.count {
		if stack.screens[index] == screen {
			return true
		}
	}
	return false
}

// A stack still on the cursor goes back once the inventory or machine panel
// is closed or covered, and a closed machine panel forgets its entity. A
// panel under the recipe browser (choosing an assembler's recipe) or the
// technology screen stays open.
close_slot_screens :: proc(state: ^Ui_State, player: ^Player, items: Item_Registry) {
	top := top_screen(state.screens)
	if top != .Inventory && top != .Machine {
		player.held = return_held_stack(player.inventory, player.held, items)
	}
	if !screen_stack_contains(state.screens, .Machine) {
		player.open_machine = NO_ENTITY
		state.distribute = {}
	}
}

panel_height :: proc(row_count: int, extra: f32) -> f32 {
	return f32(row_count) * (UI_ROW_HEIGHT + UI_GAP) + extra + 2 * UI_PADDING
}

pause_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	area := ui_panel_area(state)
	developer := screen_context.developer_mode || (screen_context.settings != nil && screen_context.settings.developer_mode)
	button_count := developer ? 11 : 10
	// The title row and the build stamp row besides the buttons; below the
	// title the rows scroll when the panel is clamped to the safe area.
	panel := fitted_panel(area, PAUSE_PANEL_WIDTH, panel_height(button_count, 2 * (UI_ROW_HEIGHT + UI_GAP)))
	ui_panel_begin(state, "pause", panel)
	title_area := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&title_area, UI_ROW_HEIGHT), text("pause_title"), UI_HEADING_TEXT_SIZE, .Centre)
	cut_top(&title_area, UI_GAP)
	region, content := scroll_region_begin(state, "pause_rows", title_area, f32(button_count) * (UI_ROW_HEIGHT + UI_GAP) + UI_ROW_HEIGHT)
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_resume")) {
		state.screens.count = 0
	}
	cut_top(&content, UI_GAP)
	// The browser replaces the pause menu, so the factory keeps running.
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_recipes")) {
		state.screens.count = 0
		push_screen(&state.screens, .Recipes)
	}
	cut_top(&content, UI_GAP)
	// Like the browser, the journal does not pause.
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_journal")) {
		state.screens.count = 0
		push_screen(&state.screens, .Journal)
	}
	cut_top(&content, UI_GAP)
	// Nor does the power overview.
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_power")) {
		state.screens.count = 0
		push_screen(&state.screens, .Power)
	}
	cut_top(&content, UI_GAP)
	// Nor do the production statistics.
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_statistics")) {
		state.screens.count = 0
		push_screen(&state.screens, .Statistics)
	}
	cut_top(&content, UI_GAP)
	// Nor does the technology screen.
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_technologies")) {
		state.screens.count = 0
		push_screen(&state.screens, .Technologies)
	}
	cut_top(&content, UI_GAP)
	// The frame loop writes the save after this frame's ticks and toasts.
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_save")) && screen_context.save_requested != nil {
		screen_context.save_requested^ = true
	}
	cut_top(&content, UI_GAP)
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_settings")) {
		push_screen(&state.screens, .Settings)
	}
	cut_top(&content, UI_GAP)
	if developer {
		if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_developer")) {
			push_screen(&state.screens, .Developer)
		}
		cut_top(&content, UI_GAP)
	}
	// Both quits save first: the frame loop after this frame, the exit
	// path in run_game.
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_quit_title")) {
		screen_context.title.request = {kind = .Quit_To_Title}
	}
	cut_top(&content, UI_GAP)
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_quit")) {
		screen_context.quit_requested^ = true
	}
	cut_top(&content, UI_GAP)
	// Which build this is, for bug reports from the couch.
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), BUILD_STAMP, UI_BODY_TEXT_SIZE, .Centre, UI_DIM_TEXT_COLOR)
	scroll_region_end(state, region)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_resume")}}
	ui_glyph_bar(state, hints[:])
}

multiplier_text :: proc(value: f32) -> string {
	return fmt.tprintf("%.2f", value)
}

settings_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	settings := screen_context.settings
	ui_backdrop(state)
	area := ui_panel_area(state)
	panel := fitted_panel(area, SETTINGS_PANEL_WIDTH, panel_height(SETTINGS_ROW_COUNT, 0))
	ui_panel_begin(state, "settings", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("settings_title"), UI_HEADING_TEXT_SIZE, .Centre)
	cut_top(&content, UI_GAP)
	tab_labels := [?]string{text("settings_tab_display"), text("settings_tab_controls"), text("settings_tab_bindings")}
	tab := ui_tabs(state, cut_top(&content, UI_ROW_HEIGHT), "settings_tabs", tab_labels[:])
	cut_top(&content, UI_GAP)
	back_row := cut_bottom(&content, UI_ROW_HEIGHT)
	switch tab {
	case 0:
		region, rows := scroll_region_begin(state, "display_settings", content, settings_rows_height(DISPLAY_SETTINGS_ROW_COUNT))
		display_settings(state, &rows, settings, screen_context.monitor_size, screen_context.font_families)
		scroll_region_end(state, region)
	case 1:
		region, rows := scroll_region_begin(state, "control_settings", content, settings_rows_height(CONTROL_SETTINGS_ROW_COUNT))
		control_settings(state, &rows, settings)
		scroll_region_end(state, region)
	case:
		// Read only for now; activating a row does nothing.
		ui_list(state, content, "bindings", binding_rows(screen_context.bindings, context.temp_allocator), text("settings_bindings_tooltip"))
	}
	if ui_button(state, back_row, text("settings_back")) {
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint {
		{.Confirm, text("hint_select")},
		{.Back, text("hint_back")},
		{.Tab_Previous, ""},
		{.Tab_Next, text("hint_tabs")},
		{.Info, text("hint_info")},
	}
	ui_glyph_bar(state, hints[:])
}

settings_rows_height :: proc(row_count: int) -> f32 {
	return f32(row_count) * (UI_ROW_HEIGHT + UI_GAP)
}

settings_row :: proc(content: ^Ui_Rectangle) -> Ui_Rectangle {
	row := cut_top(content, UI_ROW_HEIGHT)
	cut_top(content, UI_GAP)
	return row
}

display_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings, monitor_size: [2]int, font_families: []Font_Family) {
	window_settings(state, content, settings, monitor_size)
	ui_toggle(state, settings_row(content), text("settings_weather"), &settings.weather, text("settings_weather_tooltip"))
	ui_toggle(state, settings_row(content), text("settings_head_bob"), &settings.head_bob, text("settings_head_bob_tooltip"))
	ui_slider(
		state,
		settings_row(content),
		text("settings_ui_scale"),
		&settings.ui_scale,
		UI_SCALE_RANGE,
		multiplier_text(settings.ui_scale),
		text("settings_ui_scale_tooltip"),
	)
	ui_slider(
		state,
		settings_row(content),
		text("settings_pointer_speed"),
		&settings.pointer_speed,
		POINTER_SPEED_RANGE,
		multiplier_text(settings.pointer_speed),
		text("settings_pointer_speed_tooltip"),
	)
	ui_toggle(state, settings_row(content), text("settings_bottleneck_overlay"), &settings.bottleneck_overlay, text("settings_bottleneck_overlay_tooltip"))
	autosave := f32(settings.autosave_minutes)
	if ui_slider(state, settings_row(content), text("settings_autosave"), &autosave, AUTOSAVE_MINUTES_RANGE, autosave_minutes_text(settings.autosave_minutes), text("settings_autosave_tooltip")) {
		settings.autosave_minutes = int(math.round(autosave))
	}
	ui_toggle(state, settings_row(content), text("settings_developer_mode"), &settings.developer_mode, text("settings_developer_mode_tooltip"))
	font_choice(state, settings_row(content), "settings_font", &settings.font, font_families, false)
	font_choice(state, settings_row(content), "settings_monospace_font", &settings.monospace_font, font_families, true)
}

// Applied at once: the frame loop applies them to the window
// (update_display) after this frame.
window_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings, monitor_size: [2]int) {
	mode_text := text(window_mode_keys[settings.window_mode])
	if ui_choice(state, settings_row(content), text("settings_window_mode"), mode_text, text("settings_window_mode_tooltip")) {
		settings.window_mode = next_window_mode(settings.window_mode)
	}
	resolution_choice(state, settings_row(content), settings, monitor_size)
	ui_toggle(state, settings_row(content), text("settings_vsync"), &settings.vsync, text("settings_vsync_tooltip"))
	cap_text := frame_rate_cap_text(settings.frame_rate_cap)
	if ui_choice(state, settings_row(content), text("settings_frame_rate_cap"), cap_text, text("settings_frame_rate_cap_tooltip")) {
		settings.frame_rate_cap = next_frame_rate_cap(settings.frame_rate_cap)
	}
}

@(rodata)
window_mode_keys := [Window_Mode]string {
	.Windowed   = "settings_window_mode_windowed",
	.Borderless = "settings_window_mode_borderless",
	.Fullscreen = "settings_window_mode_fullscreen",
}

// Borderless covers the monitor: the row is dimmed, shows the monitor's
// size and does not step, but keeps its focus and tooltip.
resolution_choice :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, settings: ^Settings, monitor_size: [2]int) {
	if settings.window_mode == .Borderless {
		dimmed_choice(state, rectangle, text("settings_resolution"), resolution_text(monitor_size), text("settings_resolution_tooltip"))
		return
	}
	if ui_choice(state, rectangle, text("settings_resolution"), resolution_text(settings.resolution), text("settings_resolution_tooltip")) {
		settings.resolution = next_resolution(settings.resolution, resolution_choices(monitor_size, context.temp_allocator))
	}
}

// ui_choice's layout in the dimmed text colour, never activated.
dimmed_choice :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label, value, tooltip: string) {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle, {}, tooltip)
	widget_background(state, rectangle, id, interaction)
	content := inset(rectangle, UI_PADDING)
	value_text := fit_text(state, value, UI_BODY_TEXT_SIZE, content.width / 2)
	draw_text(state, content, value_text, UI_BODY_TEXT_SIZE, .Right, UI_DIM_TEXT_COLOR)
	content.width = max(content.width - ui_text_width(state, value_text, UI_BODY_TEXT_SIZE) - UI_GAP, 0)
	draw_text_fitted(state, content, label, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
}

// A configured size not in the choices shows as its numbers too.
resolution_text :: proc(resolution: [2]int) -> string {
	if resolution == NATIVE_RESOLUTION {
		return text("settings_resolution_native")
	}
	return fmt.tprintf("%d x %d", resolution.x, resolution.y)
}

frame_rate_cap_text :: proc(cap: int) -> string {
	return cap == 0 ? text("settings_frame_rate_cap_off") : fmt.tprintf("%d", cap)
}

// Applied at once: the font cache follows the setting from the next frame.
font_choice :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, key: string, font: ^string, families: []Font_Family, monospace: bool) {
	if len(families) == 0 {
		return
	}
	family := families[font_family_index(families, font^, monospace)]
	if ui_choice(state, rectangle, text(key), text(family.name_key), text(fmt.tprintf("%s_tooltip", key))) {
		font^ = next_font_family(families, family.id, monospace)
	}
}

autosave_minutes_text :: proc(minutes: int) -> string {
	return minutes == 0 ? text("settings_autosave_off") : fmt.tprintf("%d", minutes)
}

control_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings) {
	ui_toggle(state, settings_row(content), text("settings_gyro"), &settings.gyro_enabled, text("settings_gyro_tooltip"))
	sensitivity_slider(state, content, "settings_stick_sensitivity", &settings.stick_look_sensitivity)
	sensitivity_slider(state, content, "settings_gyro_sensitivity", &settings.gyro_look_sensitivity)
	sensitivity_slider(state, content, "settings_trackpad_sensitivity", &settings.trackpad_look_sensitivity)
	ui_toggle(state, settings_row(content), text("settings_invert_pitch"), &settings.invert_pitch, text("settings_invert_pitch_tooltip"))
}

sensitivity_slider :: proc(state: ^Ui_State, content: ^Ui_Rectangle, key: string, value: ^f32) {
	ui_slider(state, settings_row(content), text(key), value, LOOK_SENSITIVITY_RANGE, multiplier_text(value^), text("settings_sensitivity_tooltip"))
}
