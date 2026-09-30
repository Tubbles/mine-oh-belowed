package game

import "core:fmt"
import "core:strings"

// The title screen and its screens: New world, Load and the delete
// confirmation. They run without a world behind them, over a plain
// backdrop in the day sky colour (render_frame), since a generated view
// would need a session.

TITLE_PANEL_WIDTH :: 560
TITLE_NAME_TEXT_SIZE :: 72
NEW_WORLD_PANEL_WIDTH :: 960
// Heading, name, seed, six settings and the button row.
NEW_WORLD_ROW_COUNT :: 10
LOAD_PANEL_WIDTH :: 1400
// Rows of the save list below its column headings.
LOAD_LIST_ROWS :: 8
// The most of the name column a marker ("cannot load", "terrain
// changed") takes.
SAVE_MARKER_SHARE :: 0.8
CONFIRM_PANEL_WIDTH :: 720
SEED_FIELD_SHARE :: 0.68

Session_Request_Kind :: enum u8 {
	None,
	// Start the world in Title_State.setup.
	New_World,
	// Load the save in directory_name.
	Load,
	// Save and end the world, then show the title.
	Quit_To_Title,
}

// Handled by the frame loop after the frame that made it
// (apply_session_request).
Session_Request :: struct {
	kind:           Session_Request_Kind,
	// Points into Title_State.saves, which stays until the request is handled.
	directory_name: string,
}

Title_State :: struct {
	saves_directory:  string,
	saves_found:      bool,
	// Newest first.
	saves:            [dynamic]Save_Summary,
	setup:            World_Setup,
	// What the New world screen starts from (game.sjson).
	default_settings: World_File_Settings,
	// Nil shows dates in UTC.
	local_zone:       Local_Zone,
	// The save the delete confirmation is about.
	delete_index:     int,
	// The save row that last held the focus on the Load screen, for its
	// Delete button.
	load_selection:   int,
	// This build's save header, to mark saves it cannot load.
	expected_header:  Save_Header,
	request:          Session_Request,
}

make_title_state :: proc(config: Game_Config, saves_directory: string, saves_found: bool, expected_header: Save_Header) -> Title_State {
	return Title_State {
		saves_directory = saves_directory,
		saves_found = saves_found,
		default_settings = default_world_file_settings(config),
		local_zone = load_local_zone(),
		expected_header = expected_header,
	}
}

destroy_title_state :: proc(title: ^Title_State) {
	destroy_save_summaries(&title.saves)
	delete(title.saves)
	destroy_local_zone(&title.local_zone)
}

refresh_title_saves :: proc(title: ^Title_State) {
	if title.saves_found {
		list_saves(&title.saves, title.saves_directory, title.expected_header)
	}
}

title_row :: proc(content: ^Ui_Rectangle) -> Ui_Rectangle {
	row := cut_top(content, UI_ROW_HEIGHT)
	cut_top(content, UI_GAP)
	return row
}

// Continue shows only when a save exists. Back does nothing here.
title_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	title := screen_context.title
	area := ui_safe_area(state)
	heading := cut_top(&area, area.height * 0.3)
	ui_label(state, cut_top(&heading, heading.height * 0.7), text("title_game_name"), TITLE_NAME_TEXT_SIZE, .Centre)
	ui_label(state, heading, format_message_text(text("title_version"), BUILD_STAMP), UI_BODY_TEXT_SIZE, .Centre, UI_DIM_TEXT_COLOR)
	newest, has_save := newest_save(title.saves[:])
	button_count := has_save ? 5 : 4
	panel := centred_rectangle(area, TITLE_PANEL_WIDTH, panel_height(button_count, -UI_GAP))
	panel.y = area.y
	ui_panel_begin(state, "title", panel)
	content := inset(panel, UI_PADDING)
	if has_save && ui_button(state, title_row(&content), text("title_continue")) {
		title.request = {kind = .Load, directory_name = title.saves[newest].directory_name}
	}
	if ui_button(state, title_row(&content), text("title_new_world")) {
		name := default_new_world_name(text("new_world_default_name"), title.saves_directory, title.saves_found)
		title.setup = make_world_setup(title.default_settings, name, 0)
		randomise_seed(&title.setup)
		push_screen(&state.screens, .New_World)
	}
	if ui_button(state, title_row(&content), text("title_load")) {
		push_screen(&state.screens, .Load_World)
	}
	if ui_button(state, title_row(&content), text("title_settings")) {
		push_screen(&state.screens, .Settings)
	}
	if ui_button(state, title_row(&content), text("title_quit")) {
		screen_context.quit_requested^ = true
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}}
	ui_glyph_bar(state, hints[:])
}

on_off_key :: proc(value: bool, on_key, off_key: string) -> string {
	return text(value ? on_key : off_key)
}

// The rows of the world settings; each choice steps forward on Confirm.
world_setting_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, setup: ^World_Setup) {
	veins := on_off_key(setup.veins_infinite, "new_world_veins_infinite", "new_world_veins_finite")
	if ui_choice(state, title_row(content), text("new_world_veins"), veins, text("new_world_veins_tooltip")) {
		setup.veins_infinite = !setup.veins_infinite
	}
	richness := percent_multiplier_text(setting_percent_choices[setup.vein_richness_choice])
	if ui_choice(state, title_row(content), text("new_world_richness"), richness, text("new_world_richness_tooltip")) {
		setup.vein_richness_choice = next_choice(setup.vein_richness_choice, len(setting_percent_choices))
	}
	cost := percent_multiplier_text(setting_percent_choices[setup.research_cost_choice])
	if ui_choice(state, title_row(content), text("new_world_research_cost"), cost, text("new_world_research_cost_tooltip")) {
		setup.research_cost_choice = next_choice(setup.research_cost_choice, len(setting_percent_choices))
	}
	byproducts := on_off_key(setup.byproducts_lenient, "new_world_byproducts_lenient", "new_world_byproducts_strict")
	if ui_choice(state, title_row(content), text("new_world_byproducts"), byproducts, text("new_world_byproducts_tooltip")) {
		setup.byproducts_lenient = !setup.byproducts_lenient
	}
	ui_toggle(state, title_row(content), text("new_world_all_recipes"), &setup.all_recipes_unlocked, text("new_world_all_recipes_tooltip"))
	day_length := format_message_text(text("new_world_minutes"), fmt.tprint(day_length_minute_choices[setup.day_length_choice]))
	if ui_choice(state, title_row(content), text("new_world_day_length"), day_length, text("new_world_day_length_tooltip")) {
		setup.day_length_choice = next_choice(setup.day_length_choice, len(day_length_minute_choices))
	}
}

// Create asks the frame loop to start the world once the name and seed
// are usable.
create_world :: proc(state: ^Ui_State, title: ^Title_State) {
	if strings.trim_space(text_field_text(&title.setup.name)) == "" {
		ui_toast(state, text("new_world_name_empty"))
		return
	}
	if _, ok := world_setup_seed(&title.setup); !ok {
		ui_toast(state, text("new_world_seed_invalid"))
		return
	}
	title.request = {kind = .New_World}
}

new_world_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	setup := &screen_context.title.setup
	area := ui_panel_area(state)
	typing := state.keyboard.field != 0
	height := typing ? panel_height(2, keyboard_keys_height(state.keyboard)) : panel_height(NEW_WORLD_ROW_COUNT, -UI_GAP)
	panel := fitted_panel(area, NEW_WORLD_PANEL_WIDTH, height)
	ui_panel_begin(state, "new_world", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, title_row(&content), text("new_world_title"), UI_HEADING_TEXT_SIZE, .Centre)
	name_label, seed_label := text("new_world_name"), text("new_world_seed")
	name_id, seed_id := ui_id(state, name_label), ui_id(state, seed_label)
	if typing {
		editing_seed := state.keyboard.field == seed_id
		field := editing_seed ? &setup.seed : &setup.name
		field_row := title_row(&content)
		draw_text_field_content(state, field_row, editing_seed ? seed_label : name_label, field, true)
		if ui_on_screen_keyboard(state, field_row, {content.x + (content.width - KEYBOARD_WIDTH) / 2, content.y}, field) {
			state.keyboard = Keyboard_State {
				return_focus = state.keyboard.field,
			}
		}
		ui_panel_end(state)
		ui_glyph_bar(state, keyboard_glyph_hints(state.keyboard))
		return
	}
	if state.keyboard.return_focus != 0 {
		state.requested_focus, state.keyboard.return_focus = state.keyboard.return_focus, 0
	}
	button_row := cut_bottom(&content, UI_ROW_HEIGHT)
	cut_bottom(&content, UI_GAP)
	// Name, seed and the settings scroll when the panel is clamped to the
	// safe area; the heading and the buttons stay.
	region, rows := scroll_region_begin(state, "new_world_rows", content, f32(NEW_WORLD_ROW_COUNT - 2) * (UI_ROW_HEIGHT + UI_GAP) - UI_GAP)
	if ui_text_field(state, title_row(&rows), name_label, &setup.name) {
		open_keyboard(state, name_id)
	}
	seed_row := title_row(&rows)
	if ui_text_field(state, cut_left(&seed_row, seed_row.width * SEED_FIELD_SHARE), seed_label, &setup.seed) {
		open_keyboard(state, seed_id)
	}
	cut_left(&seed_row, UI_GAP)
	if ui_button(state, seed_row, text("new_world_randomise")) {
		randomise_seed(setup)
	}
	world_setting_rows(state, &rows, setup)
	scroll_region_end(state, region)
	if ui_button(state, column(button_row, 2, 0, UI_GAP), text("new_world_create")) {
		create_world(state, screen_context.title)
	}
	if ui_button(state, column(button_row, 2, 1, UI_GAP), text("new_world_back")) {
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}, {.Info, text("hint_info")}}
	ui_glyph_bar(state, hints[:])
}

// The load list's cells of one save; marker is set for a save this build
// cannot load or one made with older terrain.
Save_Row_Cells :: struct {
	name:   string,
	marker: string,
	seed:   string,
	played: string,
	saved:  string,
}

save_marker :: proc(save: Save_Summary) -> string {
	switch {
	case !save.loadable:
		return text("load_incompatible")
	case save.terrain_changed:
		return text("save_terrain_changed")
	}
	return ""
}

save_row_cells :: proc(save: Save_Summary, zone: Local_Zone, tick_rate: int) -> Save_Row_Cells {
	return Save_Row_Cells {
		name = save.name,
		marker = save_marker(save),
		seed = fmt.tprint(save.seed),
		played = play_time_text(save.tick, tick_rate),
		saved = date_text(save.last_played_unix_seconds, zone),
	}
}

// Widths of the seed, played and saved columns: their widest possible
// value or their heading; the name takes the rest.
Save_Columns :: struct {
	name, seed, played, saved: Ui_Rectangle,
}

save_column_width :: proc(state: ^Ui_State, widest, heading: string) -> f32 {
	return max(ui_text_width(state, widest, UI_BODY_TEXT_SIZE), ui_text_width(state, heading, UI_BODY_TEXT_SIZE)) + 2 * UI_PADDING
}

save_columns :: proc(state: ^Ui_State, row: Ui_Rectangle) -> Save_Columns {
	content := inset(row, UI_PADDING)
	columns: Save_Columns
	columns.saved = cut_right(&content, save_column_width(state, "0000-00-00 00:00", text("load_last_played")))
	columns.played = cut_right(&content, save_column_width(state, "0000:00", text("load_play_time")))
	columns.seed = cut_right(&content, save_column_width(state, "18446744073709551615", text("load_seed")))
	columns.name = content
	return columns
}

// Name (with the marker right aligned in its column), seed, played and
// saved, each ending with an ellipsis where it does not fit.
draw_save_row :: proc(state: ^Ui_State, row: Ui_Rectangle, cells: Save_Row_Cells, color := UI_TEXT_COLOR) {
	columns := save_columns(state, row)
	name := columns.name
	if cells.marker != "" {
		marker := fit_text(state, cells.marker, UI_BODY_TEXT_SIZE, name.width * SAVE_MARKER_SHARE)
		draw_text(state, name, marker, UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
		name.width -= ui_text_width(state, marker, UI_BODY_TEXT_SIZE) + UI_PADDING
	}
	draw_text_fitted(state, name, cells.name, UI_BODY_TEXT_SIZE, .Left, color)
	draw_text_fitted(state, columns.seed, cells.seed, UI_BODY_TEXT_SIZE, .Right, color)
	draw_text_fitted(state, columns.played, cells.played, UI_BODY_TEXT_SIZE, .Right, color)
	draw_text_fitted(state, columns.saved, cells.saved, UI_BODY_TEXT_SIZE, .Right, color)
}

// The saves as rows of columns; ids match ui_list's (focused_list_row).
// Returns the activated save or -1.
save_list :: proc(state: ^Ui_State, area: Ui_Rectangle, title: ^Title_State, tick_rate: int) -> int {
	activated := -1
	list := scroll_list_begin(state, "saves", area, len(title.saves))
	for save, index in title.saves {
		row := scroll_list_row(list, index)
		id := ui_id(state, "item", index)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, index)
		}
		if interaction.activated {
			activated = index
		}
		widget_background(state, row, id, interaction)
		draw_save_row(state, row, save_row_cells(save, title.local_zone, tick_rate))
	}
	scroll_list_end(state, &list)
	return activated
}

// The row of the list whose item holds the focus, or -1. Matches the ids
// ui_list gives its rows.
focused_list_row :: proc(state: ^Ui_State, list_id: Ui_Id, count: int) -> int {
	for index in 0 ..< count {
		if state.focus == ui_hash(list_id, "item", index) {
			return index
		}
	}
	return -1
}

// Opens the delete confirmation for the save at index, if there is one.
confirm_save_deletion :: proc(state: ^Ui_State, title: ^Title_State, index: int) {
	if index < 0 || index >= len(title.saves) {
		return
	}
	title.delete_index = index
	push_screen(&state.screens, .Confirm_Delete)
}

// Confirm loads the focused save, the context action or the Delete button
// asks to delete it. The Delete button acts on the row that held the
// focus last, since pressing it moves the focus off the list.
load_world_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	title := screen_context.title
	ui_backdrop(state)
	area := ui_panel_area(state)
	// The heading, the column headings, the list and the button row.
	panel := fitted_panel(area, LOAD_PANEL_WIDTH, panel_height(LOAD_LIST_ROWS + 3, -UI_GAP))
	ui_panel_begin(state, "load", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, title_row(&content), text("load_title"), UI_HEADING_TEXT_SIZE, .Centre)
	back_row := cut_bottom(&content, UI_ROW_HEIGHT)
	cut_bottom(&content, UI_GAP)
	headings := Save_Row_Cells {
		name   = text("new_world_name"),
		seed   = text("load_seed"),
		played = text("load_play_time"),
		saved  = text("load_last_played"),
	}
	draw_save_row(state, cut_top(&content, UI_ROW_HEIGHT), headings, UI_DIM_TEXT_COLOR)
	if len(title.saves) == 0 {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("load_empty"), UI_BODY_TEXT_SIZE, .Centre, UI_DIM_TEXT_COLOR)
	}
	list_id := ui_id(state, "saves")
	if activated := save_list(state, content, title, screen_context.tick_rate); activated >= 0 {
		title.request = {kind = .Load, directory_name = title.saves[activated].directory_name}
	}
	focused := focused_list_row(state, list_id, len(title.saves))
	if focused >= 0 {
		title.load_selection = focused
	}
	if focused >= 0 && state.input.context_action {
		confirm_save_deletion(state, title, focused)
	}
	if ui_button(state, column(back_row, 2, 0, UI_GAP), text("load_delete")) {
		confirm_save_deletion(state, title, title.load_selection)
	}
	if ui_button(state, column(back_row, 2, 1, UI_GAP), text("load_back")) {
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_load")}, {.Context_Action, text("hint_delete")}, {.Back, text("hint_back")}}
	ui_glyph_bar(state, hints[:])
}

// No is declared first, so it holds the focus when the dialog opens.
confirm_delete_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	title := screen_context.title
	if title.delete_index < 0 || title.delete_index >= len(title.saves) {
		pop_screen(&state.screens)
		return
	}
	save := title.saves[title.delete_index]
	ui_backdrop(state)
	panel := fitted_panel(ui_panel_area(state), CONFIRM_PANEL_WIDTH, panel_height(2, -UI_GAP))
	ui_panel_begin(state, "confirm_delete", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, title_row(&content), format_message_text(text("load_delete_question"), save.name), UI_BODY_TEXT_SIZE, .Centre)
	button_row := title_row(&content)
	if ui_button(state, column(button_row, 2, 1, UI_GAP), text("confirm_no")) {
		pop_screen(&state.screens)
	}
	if ui_button(state, column(button_row, 2, 0, UI_GAP), text("confirm_yes")) {
		delete_title_save(state, title, save.directory_name)
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}}
	ui_glyph_bar(state, hints[:])
}

delete_title_save :: proc(state: ^Ui_State, title: ^Title_State, directory_name: string) {
	if error := delete_save(title.saves_directory, directory_name); error != nil {
		log_printf("error: cannot delete the save %q: %v", directory_name, error)
		ui_toast(state, text("load_delete_failed"))
	}
	refresh_title_saves(title)
}
