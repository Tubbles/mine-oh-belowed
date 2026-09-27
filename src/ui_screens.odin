package game

import "core:fmt"

// The screens on the stack over the world and its HUD. Only the top screen
// is drawn and interactive.

PAUSE_PANEL_WIDTH :: 560
SETTINGS_PANEL_WIDTH :: 960
// Title, tabs, the longest tab's rows and the back button.
SETTINGS_ROW_COUNT :: 8

Screen_Context :: struct {
	settings:        ^Settings,
	quit_requested:  ^bool,
	player:          ^Player,
	items:           Item_Registry,
	item_sort_ranks: []u16,
}

// Pause opens the pause menu from the world, Open_Inventory the inventory.
// With a screen open, Back and Pause both step back one screen (the first
// press closes an open tooltip). Open_Inventory closes the inventory too,
// except on the gamepad, where the same X press is the context action.
handle_screen_keys :: proc(state: ^Ui_State) {
	input := state.input
	if state.screens.count == 0 {
		if input.pause {
			push_screen(&state.screens, .Pause)
		} else if input.open_inventory {
			push_screen(&state.screens, .Inventory)
		}
		return
	}
	closes_inventory := top_screen(state.screens) == .Inventory && input.open_inventory && !input.context_action
	if !input.back && !input.pause && !closes_inventory {
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
	switch screen {
	case .None:
	case .Pause:
		pause_screen(state, screen_context)
	case .Settings:
		settings_screen(state, screen_context)
	case .Inventory:
		inventory_screen(state, screen_context)
	}
	// After the screen, so that the Back press a screen consumed this frame
	// and the screen change land in the same frame.
	handle_screen_keys(state)
	// A stack still on the cursor goes back once the inventory is closed.
	if top_screen(state.screens) != .Inventory && screen_context.player != nil {
		player := screen_context.player
		player.held = return_held_stack(player.inventory, player.held, screen_context.items)
	}
}

panel_height :: proc(row_count: int, extra: f32) -> f32 {
	return f32(row_count) * (UI_ROW_HEIGHT + UI_GAP) + extra + 2 * UI_PADDING
}

pause_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	area := ui_safe_area(state)
	panel := centred_rectangle(area, PAUSE_PANEL_WIDTH, panel_height(3, UI_ROW_HEIGHT + UI_GAP))
	ui_panel_begin(state, "pause", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_title"), UI_HEADING_TEXT_SIZE, .Centre)
	cut_top(&content, UI_GAP)
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_resume")) {
		state.screens.count = 0
	}
	cut_top(&content, UI_GAP)
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_settings")) {
		push_screen(&state.screens, .Settings)
	}
	cut_top(&content, UI_GAP)
	if ui_button(state, cut_top(&content, UI_ROW_HEIGHT), text("pause_quit")) {
		screen_context.quit_requested^ = true
	}
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
	area := ui_safe_area(state)
	panel := centred_rectangle(area, SETTINGS_PANEL_WIDTH, panel_height(SETTINGS_ROW_COUNT, 0))
	ui_panel_begin(state, "settings", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("settings_title"), UI_HEADING_TEXT_SIZE, .Centre)
	cut_top(&content, UI_GAP)
	tab_labels := [?]string{text("settings_tab_display"), text("settings_tab_controls")}
	tab := ui_tabs(state, cut_top(&content, UI_ROW_HEIGHT), "settings_tabs", tab_labels[:])
	cut_top(&content, UI_GAP)
	back_row := cut_bottom(&content, UI_ROW_HEIGHT)
	switch tab {
	case 0:
		display_settings(state, &content, settings)
	case:
		control_settings(state, &content, settings)
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

settings_row :: proc(content: ^Ui_Rectangle) -> Ui_Rectangle {
	row := cut_top(content, UI_ROW_HEIGHT)
	cut_top(content, UI_GAP)
	return row
}

display_settings :: proc(state: ^Ui_State, content: ^Ui_Rectangle, settings: ^Settings) {
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
