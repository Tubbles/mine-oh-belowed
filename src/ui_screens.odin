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
DISPLAY_SETTINGS_ROW_COUNT :: 18
AUDIO_SETTINGS_ROW_COUNT :: 3
CONTROL_SETTINGS_ROW_COUNT :: 5
ACCESSIBILITY_SETTINGS_ROW_COUNT :: 10

// What a screen asks of the frame loop, which takes each member between
// frames (Take_Screenshot inside render_frame, after the UI pass), in the
// order doc/architecture.md (Frame and tick) gives. Each viewport has its
// own set (split screen, 0178): Reload_Data and Quit belong to the game
// and serve once, the rest serve the viewport that asked.
// Declared beside Screen_Context, which hands the set to the screens: the
// clusters below the loop may not name the loop's types.
Frame_Request :: enum u8 {
	Refresh_Texture_Editor,
	Save_Texture_Edits,
	Close_Data_File,
	Discard_Data_Edit,
	Save_Data_Edit,
	Export_Data_Files,
	Refresh_Data_Tree,
	Open_Data_File,
	Write_Touch_Layouts,
	Take_Screenshot,
	// A split screen guest's pause menu: its viewport and local player
	// leave, after the frame's draw.
	Remove_Viewport,
	Reload_Data,
	Quit,
}

Frame_Requests :: bit_set[Frame_Request; u16]

// What the screens read, grouped by owner: the process, the content (the
// session's view of it: its technologies, its found schematics, its
// generator), the simulation, the session views (0159), the developer
// tools and the touch layouts. The HUD's own derivations are Hud_Context
// (hud.odin), which draw_hud takes beside it.
Screen_Context :: struct {
	settings:        ^Settings,
	// The monitor's size (display.odin): the Resolution choices up to it,
	// and the Resolution row's value in borderless.
	monitor_size:    [2]int,
	// The windowing platform GLFW took: under XWayland the Resolution row
	// notes a desktop scaled screen (display.odin).
	platform:        Window_Platform,
	// The Font choices cycle through them (data/fonts/fonts.sjson).
	font_families:   []Font_Family,
	// The effective bindings, shown read only.
	bindings:        []Binding,
	// The viewport's request set (Frame_Request).
	requests:        ^Frame_Requests,
	// The screens run in a split screen viewport other than the first
	// (0178): the pause menu leaves split screen instead of quitting.
	split_screen_guest: bool,
	// A world is played but the viewport's player has no entry yet (its
	// join tick has not run): player, world and records are nil, so only
	// the pause menu (Resume, Settings, Leave split screen) and the settings
	// run (WAITING_PLAYER_SCREENS).
	waiting_for_player: bool,
	// Nil without a world. On the session, not in requests: the frame's
	// ticks take it (save_when_due).
	save_requested:  ^bool,
	// The title screens' state and the requests to start or leave a world.
	title:           ^Title_State,
	// The New world screen's planet choices (data/planets.sjson).
	planets:         []Planet,
	// With a world: technologies is the session's copy with the research
	// cost applied, recipes carries the found schematics and generator is
	// the session's. Without one generator is nil.
	using content:   Simulation_Content,
	// The content's presentation tables beside it (Game_Content). The
	// journal's Notes tab (notes.odin).
	notes:           Note_Registry,
	item_sort_ranks: []u16,
	recipe_names:    []string,
	recipe_order:    []int,
	player:          ^Player,
	// The player's index in the simulation's players.
	player_index:    int,
	world:           ^World,
	// The simulation's records beside the world.
	records:         ^Game_Records,
	tick_rate:       int,
	unlocks:         ^Recipe_Unlocks,
	quest_state:     ^Quest_State,
	// The simulation's tick, for the contracts' time left.
	tick:            u64,
	// The simulation's developer cheat speed, before pending requests.
	cheat_speed:        bool,
	// The simulation's command list (player_command.odin): the screens
	// queue every change of the simulation here for the next tick instead
	// of writing it. Nil without a world.
	player_commands:    ^[dynamic]Queued_Player_Command,
	// The local player's commands already taken from that list and not
	// applied yet (lockstep_unconfirmed_commands), for the pending state
	// a screen shows.
	unconfirmed_commands: []Player_Command,
	landing_pad:        Landing_Pad_Site,
	// The recipe browser, the technology browser, the statistics and the
	// map (ui_session_views.odin). Nil without a world.
	views:              ^Session_Views,
	developer:          Developer_Context,
	// The frame loop's particle memory (render_particles.odin), read only:
	// the map draws the capsule descent and the satellite pass from it.
	// Nil without a world and in tests.
	particle_memory:    ^Particle_Memory,
	// The user touch layouts and the editor's draft (0121,
	// ui_touch_layout_editor.odin), kept by the frame loop, and the data
	// file's layout, Default. Nil in tests that edit no layout.
	touch_layouts:        ^Touch_Layouts,
	touch_layout_editor:  ^Touch_Layout_Editor,
	default_touch_layout: Touch_Overlay_Layout,
}

// What the Developer screen and the two editors read besides the
// simulation (ui_developer.odin), built by make_screen_context from the
// content and the loop's developer tools.
Developer_Context :: struct {
	// --dev: the pause menu shows the Developer entry; the developer_mode
	// setting shows it too.
	enabled:            bool,
	// The chapters the developer screen offers: one per kit.
	chapter_count:      int,
	// The F3 pages (diagnostics.odin), stepped by the Developer screen.
	diagnostics_page:   ^Diagnostics_Page,
	show_world_overlay: ^bool,
	// Content files changed since the content was loaded.
	data_changed:       bool,
	// The texture editor's entries (ui_texture_editor.odin), kept by the
	// frame loop. Nil in tests that open no editor.
	texture_editor:     ^Texture_Editor,
	// The Data files screen's tree and open file (ui_data_browser.odin),
	// kept by the frame loop. Nil in tests that open no browser.
	data_browser:       ^Data_Browser,
}

// Pause opens the pause menu from the world, Open_Inventory the inventory,
// Open_Recipes the recipe browser, Open_Journal the journal (which it also
// closes), Open_Power_Overview the power overview, Open_Statistics the
// production statistics, Open_Technologies the technology screen and
// Open_Map the map (likewise). With a
// screen open, Back and Pause both
// step back one screen (the first press closes an open tooltip).
// Open_Inventory closes the inventory tab strip's screens (the inventory,
// the recipe browser, the technology screen) and a machine panel too,
// except on the gamepad, where the same X press is the context action;
// Open_Recipes closes the recipe browser. The pause menu opens neither
// the recipe browser nor the technology screen: the inventory's tab strip
// reaches them (work item 0094).
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
	closes_inventory := (top == .Inventory || top == .Machine || top == .Recipes || top == .Technologies) && input.open_inventory && !input.context_action
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
	// The world has no focusable widgets, so a focus kept from the last
	// screen is stale: every screen opened from the world starts at its
	// preferred widget (ui_prefer_focus) or its first one. A screen pushed
	// over another keeps the focus.
	if state.screens.count == 0 {
		state.focus = 0
		state.active_slot = {}
		state.configure = {}
	}
	if screen_context.waiting_for_player {
		keep_waiting_player_screens(&state.screens)
	}
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
	case .Textures:
		texture_editor_screen(state, screen_context)
	case .Data_Files:
		data_browser_screen(state, screen_context)
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
	case .Configure:
		configure_screen(state, screen_context)
	case .Touch_Layout:
		touch_layout_editor_screen(state, screen_context)
	case .Title:
		title_screen(state, screen_context)
	case .New_World:
		new_world_screen(state, screen_context)
	case .Load_World:
		load_world_screen(state, screen_context)
	case .Confirm_Delete:
		confirm_delete_screen(state, screen_context)
	case .Multiplayer:
		multiplayer_screen(state, screen_context)
	}
	// After the screen, so that the Back press a screen consumed this frame
	// and the screen change land in the same frame. While the keyboard is
	// open, Back and Pause belong to it.
	if !typing {
		handle_screen_keys(state)
	}
	if screen_context.waiting_for_player {
		keep_waiting_player_screens(&state.screens)
	}
	if screen_context.player != nil {
		close_slot_screens(state, screen_context)
	}
	if screen_context.views != nil && top_screen(state.screens) != .Recipes {
		screen_context.views.recipe_browser.selecting_for = NO_ENTITY
	}
	// The next opening centres on the player and reads the surfaces anew.
	if screen_context.views != nil && top_screen(state.screens) != .Map {
		screen_context.views.map_view.active = false
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

// A stack still on the cursor goes back once the inventory or machine
// panel is closed or covered (Return_Held_Command, queued once and only
// when the inventory has room for some of it), and a closed machine panel
// forgets its entity through a command for the next tick
// (Player.open_machine is simulation state). A panel under the recipe
// browser (choosing an assembler's recipe) or the technology screen stays
// open.
close_slot_screens :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player := screen_context.player
	top := top_screen(state.screens)
	if top != .Inventory && top != .Machine && return_changes_hand(player.inventory, player.held, screen_context.items) && screen_context.player_commands != nil && !slot_command_pending(screen_context.player_commands[:], screen_context.unconfirmed_commands, screen_context.player_index, returns_hand) {
		queue_slot_command(state, screen_context, Return_Held_Command{})
	}
	if screen_stack_contains(state.screens, .Machine) {
		return
	}
	state.distribute = {}
	if player.open_machine != NO_ENTITY && screen_context.player_commands != nil && !close_machine_pending(screen_context.player_commands[:], screen_context.unconfirmed_commands, screen_context.player_index) {
		queue_player_command(screen_context.player_commands, screen_context.player_index, Close_Machine_Command{machine = player.open_machine})
	}
}

pause_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	area := ui_panel_area(state)
	waiting := screen_context.waiting_for_player
	developer := !waiting && (screen_context.developer.enabled || (screen_context.settings != nil && screen_context.settings.developer_mode))
	guest := screen_context.split_screen_guest
	button_count := (developer ? 9 : 8) - (guest ? 1 : 0) - (waiting ? 4 : 0)
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
	if !waiting {
		pause_world_buttons(state, &content, screen_context)
	}
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
	if guest {
		// The guest's player stays in the world for a later join.
		if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_leave_split_screen"), text("pause_leave_split_screen_tooltip")) {
			screen_context.requests^ += {.Remove_Viewport}
		}
		cut_top(&content, UI_GAP)
	} else {
		// Both quits save first: the frame loop after this frame, the exit
		// path in run_game.
		if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_quit_title")) {
			screen_context.title.request = {kind = .Quit_To_Title}
		}
		cut_top(&content, UI_GAP)
		if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_quit")) {
			screen_context.requests^ += {.Quit}
		}
		cut_top(&content, UI_GAP)
	}
	// Which build this is, for bug reports from the couch.
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), BUILD_STAMP, UI_BODY_TEXT_SIZE, .Centre, UI_DIM_TEXT_COLOR)
	scroll_region_end(state, region)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_resume")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}

// The pause menu's rows that read the player's world: the journal, the
// power overview, the statistics and the save.
pause_world_buttons :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context) {
	// The journal replaces the pause menu, so the factory keeps running.
	if ui_button(state, cut_top(content, UI_ROW_HEIGHT), text("pause_journal")) {
		state.screens.count = 0
		push_screen(&state.screens, .Journal)
	}
	cut_top(content, UI_GAP)
	// Nor does the power overview.
	if ui_button(state, cut_top(content, UI_ROW_HEIGHT), text("pause_power")) {
		state.screens.count = 0
		push_screen(&state.screens, .Power)
	}
	cut_top(content, UI_GAP)
	// Nor do the production statistics.
	if ui_button(state, cut_top(content, UI_ROW_HEIGHT), text("pause_statistics")) {
		state.screens.count = 0
		push_screen(&state.screens, .Statistics)
	}
	cut_top(content, UI_GAP)
	// The frame loop writes the save after this frame's ticks and toasts.
	if ui_button(state, cut_top(content, UI_ROW_HEIGHT), text("pause_save")) && screen_context.save_requested != nil {
		screen_context.save_requested^ = true
	}
	cut_top(content, UI_GAP)
}

// The screens a viewport waiting for its player's entry may show.
WAITING_PLAYER_SCREENS :: bit_set[Screen]{.Pause, .Settings}

// A waiting viewport's stack keeps only WAITING_PLAYER_SCREENS: any other
// screen (a key opened it, or it was open when the wait began) needs the
// player and goes, with everything above it.
keep_waiting_player_screens :: proc(screens: ^Screen_Stack) {
	for index in 0 ..< screens.count {
		if screens.screens[index] not_in WAITING_PLAYER_SCREENS {
			screens.count = index
			return
		}
	}
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
	tab_labels := [?]string{text("settings_tab_display"), text("settings_tab_audio"), text("settings_tab_controls"), text("settings_tab_accessibility"), text("settings_tab_bindings")}
	tab := ui_tabs(state, cut_top(&content, UI_ROW_HEIGHT), "settings_tabs", tab_labels[:])
	cut_top(&content, UI_GAP)
	back_row := cut_bottom(&content, UI_ROW_HEIGHT)
	switch tab {
	case 0:
		region, rows := scroll_region_begin(state, "display_settings", content, settings_rows_height(DISPLAY_SETTINGS_ROW_COUNT))
		desktop_scaled := display_is_desktop_scaled(screen_context.platform)
		display_settings(state, &rows, settings, screen_context.monitor_size, desktop_scaled, screen_context.font_families)
		scroll_region_end(state, region)
	case 1:
		region, rows := scroll_region_begin(state, "audio_settings", content, settings_rows_height(AUDIO_SETTINGS_ROW_COUNT))
		audio_settings(state, &rows, settings)
		scroll_region_end(state, region)
	case 2:
		region, rows := scroll_region_begin(state, "control_settings", content, settings_rows_height(CONTROL_SETTINGS_ROW_COUNT))
		control_settings(state, &rows, settings)
		scroll_region_end(state, region)
	case 3:
		region, rows := scroll_region_begin(state, "accessibility_settings", content, settings_rows_height(ACCESSIBILITY_SETTINGS_ROW_COUNT))
		accessibility_settings(state, &rows, settings, screen_context)
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
	ui_glyph_bar_or_back_row(state, hints[:])
}

settings_rows_height :: proc(row_count: int) -> f32 {
	return f32(row_count) * (UI_ROW_HEIGHT + UI_GAP)
}

display_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings, monitor_size: [2]int, desktop_scaled: bool, font_families: []Font_Family) {
	window_settings(state, content, settings, monitor_size, desktop_scaled)
	camera_settings(state, content, settings)
	ui_toggle(state, cut_row(content), text("settings_weather"), &settings.weather, text("settings_weather_tooltip"))
	ui_toggle(state, cut_row(content), text("settings_head_bob"), &settings.head_bob, text("settings_head_bob_tooltip"))
	// Applied on the release of a drag (ui_layout_slider), since it
	// changes the layout under the finger.
	ui_layout_slider(state, cut_row(content), text("settings_ui_scale"), &settings.ui_scale, UI_SCALE_RANGE, multiplier_text, text("settings_ui_scale_tooltip"))
	ui_slider(
		state,
		cut_row(content),
		text("settings_pointer_speed"),
		&settings.pointer_speed,
		POINTER_SPEED_RANGE,
		multiplier_text(settings.pointer_speed),
		text("settings_pointer_speed_tooltip"),
	)
	ui_toggle(state, cut_row(content), text("settings_bottleneck_overlay"), &settings.bottleneck_overlay, text("settings_bottleneck_overlay_tooltip"))
	autosave := f32(settings.autosave_minutes)
	if ui_slider(state, cut_row(content), text("settings_autosave"), &autosave, AUTOSAVE_MINUTES_RANGE, autosave_minutes_text(settings.autosave_minutes), text("settings_autosave_tooltip")) {
		settings.autosave_minutes = int(math.round(autosave))
	}
	ui_toggle(state, cut_row(content), text("settings_developer_mode"), &settings.developer_mode, text("settings_developer_mode_tooltip"))
	font_choice(state, cut_row(content), "settings_font", &settings.font, font_families, false)
	font_choice(state, cut_row(content), "settings_monospace_font", &settings.monospace_font, font_families, true)
	if ui_choice(state, cut_row(content), text("settings_split_screen"), text(split_screen_layout_keys[settings.split_screen]), text("settings_split_screen_tooltip")) {
		settings.split_screen = settings.split_screen == .Stacked ? .Side_By_Side : .Stacked
	}
}

// Applied at once: the mixer reads the volumes every frame (update_audio).
audio_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings) {
	ui_slider(state, cut_row(content), text("settings_master_volume"), &settings.master_volume, VOLUME_RANGE, volume_text(settings.master_volume), text("settings_master_volume_tooltip"))
	ui_slider(state, cut_row(content), text("settings_effects_volume"), &settings.effects_volume, VOLUME_RANGE, volume_text(settings.effects_volume), text("settings_effects_volume_tooltip"))
	ui_slider(state, cut_row(content), text("settings_ambience_volume"), &settings.ambience_volume, VOLUME_RANGE, volume_text(settings.ambience_volume), text("settings_ambience_volume_tooltip"))
}

// A volume as a whole percentage.
volume_text :: proc(volume: f32) -> string {
	return fmt.tprintf("%d%%", int(math.round(volume * 100)))
}

// Applied at once: the frame loop applies them to the window
// (update_display) after this frame.
window_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings, monitor_size: [2]int, desktop_scaled: bool) {
	mode_text := text(window_mode_keys[settings.window_mode])
	if ui_choice(state, cut_row(content), text("settings_window_mode"), mode_text, text("settings_window_mode_tooltip")) {
		settings.window_mode = next_window_mode(settings.window_mode)
	}
	resolution_choice(state, cut_row(content), settings, monitor_size, desktop_scaled)
	ui_toggle(state, cut_row(content), text("settings_vsync"), &settings.vsync, text("settings_vsync_tooltip"))
	cap_text := frame_rate_cap_text(settings.frame_rate_cap)
	if ui_choice(state, cut_row(content), text("settings_frame_rate_cap"), cap_text, text("settings_frame_rate_cap_tooltip")) {
		settings.frame_rate_cap = next_frame_rate_cap(settings.frame_rate_cap)
	}
}

// Applied at once: the frame loop reads them for each frame's camera
// (draw_session_world, work item 0073).
camera_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings) {
	ui_slider(
		state,
		cut_row(content),
		text("settings_field_of_view"),
		&settings.field_of_view,
		FIELD_OF_VIEW_RANGE,
		whole_number_text(settings.field_of_view),
		text("settings_field_of_view_tooltip"),
	)
	ui_slider(
		state,
		cut_row(content),
		text("settings_sprint_field_of_view_kick"),
		&settings.sprint_field_of_view_kick,
		SPRINT_FIELD_OF_VIEW_KICK_RANGE,
		whole_number_text(settings.sprint_field_of_view_kick),
		text("settings_sprint_field_of_view_kick_tooltip"),
	)
	ui_slider(
		state,
		cut_row(content),
		text("settings_third_person_distance"),
		&settings.third_person_distance,
		THIRD_PERSON_DISTANCE_RANGE,
		blocks_text(settings.third_person_distance),
		text("settings_third_person_distance_tooltip"),
	)
	ui_slider(
		state,
		cut_row(content),
		text("settings_third_person_shoulder"),
		&settings.third_person_shoulder,
		THIRD_PERSON_SHOULDER_RANGE,
		blocks_text(settings.third_person_shoulder),
		text("settings_third_person_shoulder_tooltip"),
	)
}

whole_number_text :: proc(value: f32) -> string {
	return fmt.tprintf("%d", int(math.round(value)))
}

// Blocks to one decimal.
blocks_text :: proc(value: f32) -> string {
	return fmt.tprintf("%.1f", value)
}

@(rodata)
window_mode_keys := [Window_Mode]string {
	.Windowed   = "settings_window_mode_windowed",
	.Borderless = "settings_window_mode_borderless",
	.Fullscreen = "settings_window_mode_fullscreen",
}

// Borderless covers the monitor: the row is dimmed, shows the monitor's
// size and does not step, but keeps its focus and tooltip. Under XWayland
// on a desktop scaled screen (work item 0084) the size is the scaled one:
// the value says so and the tooltip names the ways to the panel's full
// size. A native Wayland window reaches the panel (work item 0085).
resolution_choice :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, settings: ^Settings, monitor_size: [2]int, desktop_scaled: bool) {
	if settings.window_mode == .Borderless && desktop_scaled {
		value := fmt.tprintf("%s (%s)", resolution_text(monitor_size), text("settings_resolution_desktop_scaled"))
		dimmed_choice(state, rectangle, text("settings_resolution"), value, text("settings_resolution_desktop_scaled_tooltip"))
		return
	}
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
	ui_toggle(state, cut_row(content), text("settings_gyro"), &settings.gyro_enabled, text("settings_gyro_tooltip"))
	sensitivity_slider(state, content, "settings_stick_sensitivity", &settings.stick_look_sensitivity)
	sensitivity_slider(state, content, "settings_gyro_sensitivity", &settings.gyro_look_sensitivity)
	sensitivity_slider(state, content, "settings_trackpad_sensitivity", &settings.trackpad_look_sensitivity)
	ui_toggle(state, cut_row(content), text("settings_invert_pitch"), &settings.invert_pitch, text("settings_invert_pitch_tooltip"))
}

sensitivity_slider :: proc(state: ^Ui_State, content: ^Ui_Rectangle, key: string, value: ^f32) {
	ui_slider(state, cut_row(content), text(key), value, LOOK_SENSITIVITY_RANGE, multiplier_text(value^), text("settings_sensitivity_tooltip"))
}

// Applied at once: the frame loop reads them each frame (ui_begin, the
// camera, the weather, the markers) and the input layer each tick
// (apply_hold_settings).
accessibility_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings, screen_context: Screen_Context) {
	// Applied on the release of a drag, like the UI scale.
	ui_layout_slider(state, cut_row(content), text("settings_text_scale"), &settings.text_scale, TEXT_SCALE_RANGE, multiplier_text, text("settings_text_scale_tooltip"))
	if ui_choice(state, cut_row(content), text("settings_palette"), text(palette_keys[settings.palette]), text("settings_palette_tooltip")) {
		settings.palette = settings.palette == .Default ? .Colour_Blind : .Default
	}
	ui_toggle(state, cut_row(content), text("settings_reduced_motion"), &settings.reduced_motion, text("settings_reduced_motion_tooltip"))
	hold_mode_choice(state, cut_row(content), "settings_sneak_hold", &settings.sneak_hold)
	hold_mode_choice(state, cut_row(content), "settings_sprint_hold", &settings.sprint_hold)
	if ui_choice(state, cut_row(content), text("settings_touch_overlay"), text(touch_overlay_mode_keys[settings.touch_overlay]), text("settings_touch_overlay_tooltip")) {
		settings.touch_overlay = next_touch_overlay_mode(settings.touch_overlay)
	}
	if ui_choice(state, cut_row(content), text("settings_touch_interaction"), text(touch_interaction_keys[settings.touch_interaction]), text("settings_touch_interaction_tooltip")) {
		settings.touch_interaction = settings.touch_interaction == .Tap ? .Crosshair : .Tap
	}
	if ui_choice(state, cut_row(content), text("settings_on_screen_keyboard"), text(on_screen_keyboard_keys[settings.on_screen_keyboard]), text("settings_on_screen_keyboard_tooltip")) {
		settings.on_screen_keyboard = settings.on_screen_keyboard == .System ? .Game : .System
	}
	touch_layout_rows(state, content, screen_context)
}

// The next layout, unless the broken file from the start stands: then it
// says so and changes nothing.
step_touch_layout_selection :: proc(state: ^Ui_State, layouts: ^Touch_Layouts, requests: ^Frame_Requests) {
	if layouts.locked_path != "" {
		ui_toast(state, touch_layouts_locked_text(layouts^))
		return
	}
	layouts.selection = next_touch_layout_selection(layouts^)
	layouts.changed = true
	requests^ += {.Write_Touch_Layouts}
}

// The touch layout (0121): the row steps the selection through Default and
// the user layouts, which the frame loop writes to the user file at once;
// the button opens the editor on the selected layout.
touch_layout_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context) {
	layouts := screen_context.touch_layouts
	name := layouts != nil ? selected_touch_layout_name(layouts^) : DEFAULT_TOUCH_LAYOUT_NAME
	if ui_choice(state, cut_row(content), text("settings_touch_layout"), touch_layout_display_name(name), text("settings_touch_layout_tooltip")) && layouts != nil {
		step_touch_layout_selection(state, layouts, screen_context.requests)
	}
	if ui_button(state, cut_row(content), text("settings_edit_touch_layout"), text("settings_edit_touch_layout_tooltip")) && layouts != nil && screen_context.touch_layout_editor != nil {
		open_touch_layout_editor(state, screen_context.touch_layout_editor, layouts^, screen_context.default_touch_layout)
	}
}

@(rodata)
split_screen_layout_keys := [Split_Screen_Layout]string {
	.Stacked      = "settings_split_screen_stacked",
	.Side_By_Side = "settings_split_screen_side_by_side",
}

@(rodata)
touch_interaction_keys := [Touch_Interaction]string {
	.Tap       = "settings_touch_interaction_tap",
	.Crosshair = "settings_touch_interaction_crosshair",
}

@(rodata)
on_screen_keyboard_keys := [On_Screen_Keyboard]string {
	.System = "settings_on_screen_keyboard_system",
	.Game   = "settings_on_screen_keyboard_game",
}

@(rodata)
touch_overlay_mode_keys := [Touch_Overlay_Mode]string {
	.Auto = "settings_touch_overlay_auto",
	.On   = "settings_touch_overlay_on",
	.Off  = "settings_touch_overlay_off",
}

next_touch_overlay_mode :: proc(mode: Touch_Overlay_Mode) -> Touch_Overlay_Mode {
	return mode == max(Touch_Overlay_Mode) ? min(Touch_Overlay_Mode) : Touch_Overlay_Mode(int(mode) + 1)
}

@(rodata)
palette_keys := [Marker_Palette]string {
	.Default      = "settings_palette_default",
	.Colour_Blind = "settings_palette_colour_blind",
}

@(rodata)
hold_mode_keys := [Hold_Mode]string {
	.Toggle = "settings_hold_mode_toggle",
	.Hold   = "settings_hold_mode_hold",
}

hold_mode_choice :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, key: string, mode: ^Hold_Mode) {
	if ui_choice(state, rectangle, text(key), text(hold_mode_keys[mode^]), text(fmt.tprintf("%s_tooltip", key))) {
		mode^ = mode^ == .Hold ? .Toggle : .Hold
	}
}
