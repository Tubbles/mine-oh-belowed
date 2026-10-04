package game

import "core:fmt"

// The Developer screen (work item 0043), opened from the pause menu when
// the game runs with --dev. Every entry is a button, a toggle or a
// choice, so the focus cursor and the trackpad pointer reach all of them.
// The diagnostics page choice (work item 0086) and the statistics
// overlay and bottleneck overlay toggles are frame state and change at once; everything else (fly mode, cheat
// speed and free crafting among them) queues a Developer_Request as a player command that
// the next simulation tick serves (player_command.odin, developer.odin). The pause menu below keeps the
// simulation paused, so those apply once the game resumes. Screenshot and
// Reload data are frame requests the frame loop serves after the frame.

DEVELOPER_PANEL_WIDTH :: 1000
// Title, three toggle rows, kit label and buttons, quest label (with the
// finish active quest button) and buttons, time label and buttons, unlock, teleport and screenshot, the
// data reload row, the editors row, back.
DEVELOPER_ROW_COUNT :: 14

// Pending toggle requests (fly mode, cheat speed, free crafting) flip the
// shown state, so the check box shows the state once the requests are
// served.
pending_toggle :: proc(value: bool, commands: []Queued_Player_Command, unconfirmed: []Player_Command, player: int, action: Developer_Action) -> bool {
	return pending_developer_toggles(commands, unconfirmed, player, action) % 2 == 1 ? !value : value
}

queue_developer_request :: proc(state: ^Ui_State, screen_context: Screen_Context, request: Developer_Request) {
	if screen_context.player_commands == nil {
		return
	}
	queue_player_command(screen_context.player_commands, screen_context.player_index, request)
	ui_toast(state, text("developer_applies_on_resume"))
}

// The queued toggles on the first two rows, the frame state overlays on
// the third: the diagnostics page steps like F3.
developer_toggles :: proc(state: ^Ui_State, first_row, crafting_row, overlay_row: Ui_Rectangle, screen_context: Screen_Context) {
	commands, unconfirmed, player := screen_context.player_commands[:], screen_context.unconfirmed_commands, screen_context.player_index
	flying := pending_toggle(screen_context.player.flying, commands, unconfirmed, player, .Toggle_Fly_Mode)
	if ui_toggle(state, column_rectangle(first_row, 3, 0, UI_GAP), text("developer_fly_mode"), &flying) {
		queue_developer_request(state, screen_context, Developer_Request{action = .Toggle_Fly_Mode})
	}
	no_clip := pending_toggle(screen_context.player.no_clip, commands, unconfirmed, player, .Toggle_No_Clip)
	if ui_toggle(state, column_rectangle(first_row, 3, 1, UI_GAP), text("developer_no_clip"), &no_clip) {
		queue_developer_request(state, screen_context, Developer_Request{action = .Toggle_No_Clip})
	}
	cheat_speed := pending_toggle(screen_context.cheat_speed, commands, unconfirmed, player, .Toggle_Cheat_Speed)
	if ui_toggle(state, column_rectangle(first_row, 3, 2, UI_GAP), text("developer_cheat_speed"), &cheat_speed) {
		queue_developer_request(state, screen_context, Developer_Request{action = .Toggle_Cheat_Speed})
	}
	free_crafting := pending_toggle(screen_context.free_crafting, commands, unconfirmed, player, .Toggle_Free_Crafting)
	if ui_toggle(state, column_rectangle(crafting_row, 3, 0, UI_GAP), text("developer_free_crafting"), &free_crafting) {
		queue_developer_request(state, screen_context, Developer_Request{action = .Toggle_Free_Crafting})
	}
	page := screen_context.developer.diagnostics_page
	if ui_choice(state, column_rectangle(overlay_row, 3, 0, UI_GAP), text("developer_diagnostics"), text(diagnostics_page_keys[page^])) {
		page^ = next_diagnostics_page(page^)
	}
	ui_toggle(state, column_rectangle(overlay_row, 3, 1, UI_GAP), text("developer_world_overlay"), screen_context.developer.show_world_overlay)
	ui_toggle(state, column_rectangle(overlay_row, 3, 2, UI_GAP), text("developer_bottleneck_overlay"), &screen_context.settings.bottleneck_overlay)
}

// One numbered button per chapter; returns the chapter pressed, or 0.
chapter_buttons :: proc(state: ^Ui_State, row: Ui_Rectangle, label: string, chapter_count: int) -> int {
	pressed := 0
	ui_push_id(state, label)
	for index in 0 ..< chapter_count {
		if ui_button(state, column_rectangle(row, chapter_count, index, UI_GAP), fmt.tprintf("%d", index + 1)) {
			pressed = index + 1
		}
	}
	ui_pop_id(state)
	return pressed
}

@(rodata)
time_of_day_label_keys := [Time_Of_Day]string {
	.Dawn     = "developer_dawn",
	.Noon     = "developer_noon",
	.Dusk     = "developer_dusk",
	.Midnight = "developer_midnight",
}

time_of_day_buttons :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context) {
	for time_of_day in Time_Of_Day {
		if ui_button(state, column_rectangle(row, len(Time_Of_Day), int(time_of_day), UI_GAP), text(time_of_day_label_keys[time_of_day])) {
			queue_developer_request(state, screen_context, Developer_Request{action = .Set_Time_Of_Day, time_of_day = time_of_day})
		}
	}
}

developer_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	area := ui_panel_area(state)
	panel := fitted_panel(area, DEVELOPER_PANEL_WIDTH, panel_height(DEVELOPER_ROW_COUNT, 0))
	ui_panel_begin(state, "developer", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_row(&content), text("developer_title"), UI_HEADING_TEXT_SIZE, .Centre)
	back_row := cut_bottom(&content, UI_ROW_HEIGHT)
	cut_bottom(&content, UI_GAP)
	// The action rows between the title and Back scroll when the panel is
	// clamped to the safe area.
	region, actions := scroll_region_begin(state, "developer_actions", content, f32(DEVELOPER_ROW_COUNT - 2) * (UI_ROW_HEIGHT + UI_GAP))
	if screen_context.player != nil && screen_context.player_commands != nil {
		developer_actions(state, &actions, screen_context)
	}
	scroll_region_end(state, region)
	if ui_button(state, back_row, text("developer_back")) {
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}

developer_actions :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context) {
	developer_toggles(state, cut_row(content), cut_row(content), cut_row(content), screen_context)
	ui_label(state, cut_row(content), text("developer_give_kit"))
	if chapter := chapter_buttons(state, cut_row(content), "kit", screen_context.developer.chapter_count); chapter > 0 {
		queue_developer_request(state, screen_context, Developer_Request{action = .Give_Kit, chapter = chapter})
	}
	developer_quest_label_row(state, cut_row(content), screen_context)
	if chapter := chapter_buttons(state, cut_row(content), "quests", screen_context.developer.chapter_count); chapter > 0 {
		queue_developer_request(state, screen_context, Developer_Request{action = .Complete_Quests_To_Chapter, chapter = chapter})
	}
	ui_label(state, cut_row(content), text("developer_time_of_day"))
	time_of_day_buttons(state, cut_row(content), screen_context)
	last_row := cut_row(content)
	if ui_button(state, column_rectangle(last_row, 3, 0, UI_GAP), text("developer_unlock_all")) {
		queue_developer_request(state, screen_context, Developer_Request{action = .Unlock_All})
	}
	if ui_button(state, column_rectangle(last_row, 3, 1, UI_GAP), text("developer_teleport")) {
		position := landing_pad_standing_position(screen_context.landing_pad)
		queue_developer_request(state, screen_context, Developer_Request{action = .Teleport, position = position})
	}
	// Like the screenshot command: the frame loop writes the PNG to the
	// state directory's screenshots and toasts the path (work item 0053).
	if ui_button(state, column_rectangle(last_row, 3, 2, UI_GAP), text("developer_screenshot")) {
		screen_context.requests^ += {.Take_Screenshot}
	}
	developer_reload_row(state, cut_row(content), screen_context)
	developer_editors_row(state, cut_row(content), screen_context)
}

// The game's editors (DESIGN.md, Editors): the texture editor (work item
// 0100) and the data file browser (0129). Opening either asks the frame
// loop to read the files again: Reset returns to the data file as it is
// now, the tree shows the files and overlay copies there are now.
developer_editors_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context) {
	if ui_button(state, column_rectangle(row, 3, 0, UI_GAP), text("developer_texture_editor")) && screen_context.developer.texture_editor != nil {
		screen_context.requests^ += {.Refresh_Texture_Editor}
		push_screen(&state.screens, .Textures)
	}
	if ui_button(state, column_rectangle(row, 3, 1, UI_GAP), text("developer_data_files")) && screen_context.developer.data_browser != nil {
		screen_context.requests^ += {.Refresh_Data_Tree}
		push_screen(&state.screens, .Data_Files)
	}
}

// The label of the chapter completion buttons, and the button that
// finishes the active quest (work item 0098).
developer_quest_label_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context) {
	area := row
	button := cut_right(&area, column_rectangle(row, 3, 0, UI_GAP).width)
	cut_right(&area, UI_GAP)
	ui_label(state, area, text("developer_complete_quests"))
	if ui_button(state, button, text("developer_finish_active_quest")) {
		queue_developer_request(state, screen_context, Developer_Request{action = .Finish_Active_Quest})
	}
}

// Whether content files changed since they were loaded, and the button
// that reloads them into the running world (work item 0054), like F8 and
// the reload command. The frame loop reloads after the frame.
developer_reload_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context) {
	area := row
	button := cut_right(&area, column_rectangle(row, 3, 0, UI_GAP).width)
	cut_right(&area, UI_GAP)
	ui_label(state, area, text(screen_context.developer.data_changed ? "developer_data_changed" : "developer_data_current"))
	if ui_button(state, button, text("developer_reload_data")) {
		screen_context.requests^ += {.Reload_Data}
	}
}
