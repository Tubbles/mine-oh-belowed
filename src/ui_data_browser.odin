package game

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "platform"

// The Data files screen (work item 0129), opened from the Developer
// screen's editors row: the fallback editor for every data file without
// an editor of its own (DESIGN.md, Editors). A tree of the data
// directory, directories first, each row indented by its depth; Confirm
// or a tap on a directory expands or collapses it, on a text file opens
// it in the tree's place: an SJSON file as a tree of its values, a shader
// or a licence line by line. Only the visible rows are declared, so the
// focus walks the tree in order, and the rows scroll like the Developer
// screen's. A file with a copy in the data edits overlay carries an
// "edited" tag, and Discard edit deletes the selected file's copy. Back
// returns from a file to the tree, then closes the screen.
//
// Editing an SJSON file (work item 0130): Confirm on a boolean flips it,
// on a number or a string opens the keyboard with the value; Done sets
// it. Duplicate and Remove act on the selected array element (the value
// row last activated). Save writes the tree to the data edits overlay;
// Back drops unsaved changes and says so.
//
// The export (work item 0131, data_export.odin): over the tree, a row
// with the export directory (the keyboard types it) and the Export on
// save toggle, both settings, and an Export button in the buttons row.
//
// The screen changes the browser's expansion, selection and the open
// file's tree, and makes requests; the frame loop reads the directory and
// the files and saves (serve_data_browser in loop.odin). An edit frees
// nothing (the tree grows in the file's arena), so it may run in the UI
// pass.

DATA_BROWSER_PANEL_WIDTH :: 1100
DATA_BROWSER_INDENT :: 28
DATA_BROWSER_CHEVRON_WIDTH :: 24
DATA_BROWSER_SELECTED_MARKER_WIDTH :: 6
// The size and the edited tag on a file row.
DATA_BROWSER_DETAIL_WIDTH :: 220
// The keyboard entry's field: two rows tall, as the new world screen's
// two rows, holding the value's place and the value's lines; a longer
// string shows its end, where the caret is.
DATA_BROWSER_ENTRY_ROWS :: 2
DATA_BROWSER_ENTRY_LINE_HEIGHT :: 32
DATA_BROWSER_ENTRY_LINES :: 2

data_browser_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	browser, requests := screen_context.data_browser, screen_context.requests
	if browser == nil {
		pop_screen(&state.screens)
		return
	}
	ui_backdrop(state)
	if state.keyboard.field != 0 && data_browser_editing(browser^) {
		data_value_entry(state, browser)
		return
	}
	settings := screen_context.settings
	if state.keyboard.field != 0 && browser.editing_export_directory && settings != nil {
		data_export_directory_entry(state, browser, settings)
		return
	}
	if state.keyboard.return_focus != 0 {
		state.requested_focus, state.keyboard.return_focus = state.keyboard.return_focus, 0
	}
	area := ui_panel_area(state)
	panel := fitted_panel(area, DATA_BROWSER_PANEL_WIDTH, area.height)
	ui_panel_begin(state, "data_files", panel)
	content := inset(panel, UI_PADDING)
	data_browser_title_row(state, cut_top(&content, UI_ROW_HEIGHT), browser^)
	cut_top(&content, UI_GAP)
	if data_edits_reading.off {
		data_edits_off_notice(state, &content)
	}
	buttons := cut_bottom(&content, UI_ROW_HEIGHT)
	cut_bottom(&content, UI_GAP)
	export_row: Ui_Rectangle
	if !browser.open && settings != nil {
		export_row = cut_bottom(&content, UI_ROW_HEIGHT)
		cut_bottom(&content, UI_GAP)
	}
	if browser.open {
		data_file_view(state, content, browser)
	} else {
		data_tree_view(state, content, browser, requests)
	}
	if export_row != {} {
		data_export_row(state, export_row, browser, settings)
	}
	data_browser_buttons(state, buttons, browser, requests)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}}
	ui_glyph_bar_or_back_row(state, hints[:])
	// After the touch row, whose Back lands in the frame's input:
	// handle_screen_keys pops the screen after this, so a Back with a
	// file open is taken here and only asks for the file to close. The
	// frame loop closes it between frames: this frame's draw list points
	// into the file's memory.
	if browser.open && (state.input.back || state.input.pause) && !state.tooltip_open {
		request_data_file_close(state, browser, requests)
		state.input.back, state.input.pause = false, false
	}
}

// Back to the tree between frames; unsaved changes go, with a toast.
request_data_file_close :: proc(state: ^Ui_State, browser: ^Data_Browser, requests: ^Frame_Requests) {
	if browser.unsaved {
		ui_toast(state, text("data_files_changes_dropped"))
	}
	requests^ += {.Close_Data_File}
}

// The heading, the unsaved tag while the tree differs from the file, and
// the edited tag when the open file is the data edits overlay's copy,
// both in the accent.
data_browser_title_row :: proc(state: ^Ui_State, row: Ui_Rectangle, browser: Data_Browser) {
	title := row
	accent := ui_theme(state).colors[.Accent]
	if browser.open && browser.shows_overlay {
		draw_text_fitted(state, cut_right(&title, DATA_BROWSER_DETAIL_WIDTH / 2), text("data_files_edited"), UI_BODY_TEXT_SIZE, .Right, accent)
	}
	if browser.open && browser.unsaved {
		draw_text_fitted(state, cut_right(&title, DATA_BROWSER_DETAIL_WIDTH / 2), text("data_files_unsaved"), UI_BODY_TEXT_SIZE, .Right, accent)
	}
	draw_text_fitted(state, title, data_browser_title(browser), UI_HEADING_TEXT_SIZE, .Left)
}

// Whether a row shows in the scroll region's area. Rows outside it are
// declared (the focus walks and scrolls to them) but not drawn, so a long
// file costs no text work off screen.
row_in_view :: proc(row, view: Ui_Rectangle) -> bool {
	return row.y + row.height > view.y && row.y < view.y + view.height
}

// The open file's path, else the screen's name.
data_browser_title :: proc(browser: Data_Browser) -> string {
	if browser.open && browser.selected >= 0 && browser.selected < len(browser.rows) {
		return browser.rows[browser.selected].path
	}
	return text("data_files_title")
}

data_browser_rows_height :: proc(count: int) -> f32 {
	return f32(count) * UI_ROW_HEIGHT
}

// The visible rows of the tree. A file row activated becomes the
// selection (not one merely focused, which a passing pointer does); the
// selected file's row is where the focus returns from the file.
data_tree_view :: proc(state: ^Ui_State, area: Ui_Rectangle, browser: ^Data_Browser, requests: ^Frame_Requests) {
	if len(browser.rows) == 0 {
		ui_label(state, {area.x, area.y, area.width, UI_ROW_HEIGHT}, text("data_files_none"))
		return
	}
	visible := visible_row_indices(browser.rows, browser.expanded)
	region, rows := scroll_region_begin(state, "data_tree", area, data_browser_rows_height(len(visible)))
	for index in visible {
		data_tree_row_widget(state, cut_top(&rows, UI_ROW_HEIGHT), region.area, browser, index, requests)
	}
	scroll_region_end(state, region)
}

data_tree_row_widget :: proc(state: ^Ui_State, row, view: Ui_Rectangle, browser: ^Data_Browser, index: int, requests: ^Frame_Requests) {
	entry := browser.rows[index]
	id := ui_id(state, "data_row", index)
	if index == browser.selected {
		ui_prefer_focus(state, id)
	}
	interaction := ui_interact(state, id, row)
	if interaction.activated {
		activate_data_tree_row(state, browser, index, requests)
	}
	if !row_in_view(row, view) {
		return
	}
	widget_background(state, row, id, interaction)
	theme := ui_theme(state)
	content := row
	if index == browser.selected {
		draw_fill(state, cut_left(&content, DATA_BROWSER_SELECTED_MARKER_WIDTH), theme.colors[.Accent])
	}
	content = inset(content, UI_PADDING)
	cut_left(&content, f32(entry.depth) * DATA_BROWSER_INDENT)
	chevron := cut_left(&content, DATA_BROWSER_CHEVRON_WIDTH)
	if entry.expandable {
		draw_text(state, chevron, data_chevron(browser.expanded[index]), UI_BODY_TEXT_SIZE, .Left)
	} else {
		data_tree_row_detail(state, cut_right(&content, DATA_BROWSER_DETAIL_WIDTH), entry)
	}
	draw_text_fitted(state, content, entry.name, UI_BODY_TEXT_SIZE, .Left)
}

// > for collapsed, v for expanded: plain letters every font has.
data_chevron :: proc(expanded: bool) -> string {
	return expanded ? "v" : ">"
}

// The size on the right, the edited tag left of it.
data_tree_row_detail :: proc(state: ^Ui_State, area: Ui_Rectangle, entry: Data_Tree_Row) {
	draw_text_fitted(state, column_rectangle(area, 2, 1, UI_GAP), data_file_size_text(entry.size), UI_BODY_TEXT_SIZE, .Right, UI_DIM_TEXT_COLOR)
	if entry.edited {
		draw_text_fitted(state, column_rectangle(area, 2, 0, UI_GAP), text("data_files_edited"), UI_BODY_TEXT_SIZE, .Right, ui_theme(state).colors[.Accent])
	}
}

// A directory expands or collapses; a text file opens (the frame loop
// reads it before the next frame); a binary file says it cannot.
activate_data_tree_row :: proc(state: ^Ui_State, browser: ^Data_Browser, index: int, requests: ^Frame_Requests) {
	entry := browser.rows[index]
	if entry.expandable {
		browser.expanded[index] = !browser.expanded[index]
		return
	}
	browser.selected = index
	if data_file_kind(entry.name) == .Binary {
		ui_toast(state, text("data_files_binary"))
		return
	}
	requests^ += {.Open_Data_File}
}

// The open file: the problem, the visible values, or the lines.
data_file_view :: proc(state: ^Ui_State, area: Ui_Rectangle, browser: ^Data_Browser) {
	if browser.file_problem != "" {
		data_file_problem(state, area, browser.file_problem)
		return
	}
	if browser.file_kind == .Text {
		data_text_view(state, area, browser.lines)
		return
	}
	visible := visible_row_indices(browser.value_rows, browser.value_expanded)
	region, rows := scroll_region_begin(state, "data_values", area, data_browser_rows_height(len(visible)))
	for index in visible {
		data_value_row_widget(state, cut_top(&rows, UI_ROW_HEIGHT), region.area, browser, index)
	}
	scroll_region_end(state, region)
}

// After a failed load turned the data edits overlay off for the run
// (turn_data_edits_off): the problem and what to do, wrapped over up to
// DATA_BROWSER_PROBLEM_LINES lines in the accent, above the rows.
data_edits_off_notice :: proc(state: ^Ui_State, content: ^Ui_Rectangle) {
	notice := fmt.tprintf("%s %s. %s", text("data_files_edits_off"), data_edits_reading.off_problem, text("data_files_edits_off_hint"))
	accent := ui_theme(state).colors[.Accent]
	for line in wrap_text_lines(state, notice, UI_BODY_TEXT_SIZE, content.width, DATA_BROWSER_PROBLEM_LINES) {
		draw_text_fitted(state, cut_top(content, UI_ROW_HEIGHT), line, UI_BODY_TEXT_SIZE, .Left, accent)
	}
	cut_top(content, UI_GAP)
}

// The problem wrapped, the error before the path, so a long overlay path
// on the phone does not cut the error off; a path too long for its line
// ends with an ellipsis.
DATA_BROWSER_PROBLEM_LINES :: 4

data_file_problem :: proc(state: ^Ui_State, area: Ui_Rectangle, problem: string) {
	content := area
	for line in wrap_text_lines(state, problem, UI_BODY_TEXT_SIZE, area.width, DATA_BROWSER_PROBLEM_LINES) {
		draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), line, UI_BODY_TEXT_SIZE, .Left)
	}
}

data_value_row_widget :: proc(state: ^Ui_State, row, view: Ui_Rectangle, browser: ^Data_Browser, index: int) {
	id := ui_id(state, "value_row", index)
	interaction := ui_interact(state, id, row)
	if interaction.activated {
		activate_data_value_row(state, browser, index, id)
	}
	if !row_in_view(row, view) {
		return
	}
	entry := browser.value_rows[index]
	widget_background(state, row, id, interaction)
	content := row
	if index == browser.value_selected {
		draw_fill(state, cut_left(&content, DATA_BROWSER_SELECTED_MARKER_WIDTH), ui_theme(state).colors[.Accent])
	}
	content = inset(content, UI_PADDING)
	cut_left(&content, f32(entry.depth) * DATA_BROWSER_INDENT)
	chevron := cut_left(&content, DATA_BROWSER_CHEVRON_WIDTH)
	if entry.expandable {
		draw_text(state, chevron, data_chevron(browser.value_expanded[index]), UI_BODY_TEXT_SIZE, .Left)
		count := data_value_row_count_text(entry)
		draw_text(state, content, count, UI_BODY_TEXT_SIZE, .Right, UI_DIM_TEXT_COLOR)
		content.width = max(content.width - ui_text_width(state, count, UI_BODY_TEXT_SIZE) - UI_GAP, 0)
	}
	draw_text_fitted(state, content, data_value_row_text(entry), UI_BODY_TEXT_SIZE, .Left)
}

// The row becomes the selection; an object or an array expands or
// collapses, a boolean flips, a number or a string opens the keyboard
// with its value (the row's id is the field's, so the focus returns to
// the row), anything else toasts that it cannot be edited here.
activate_data_value_row :: proc(state: ^Ui_State, browser: ^Data_Browser, index: int, id: Ui_Id) {
	browser.value_selected = index
	if browser.value_rows[index].expandable {
		browser.value_expanded[index] = !browser.value_expanded[index]
		return
	}
	value := data_value_at_row(browser.value, browser.value_rows, index)
	if _, is_boolean := value.(json.Boolean); is_boolean {
		flip_data_browser_value(browser, index)
		return
	}
	field_text, characters, editable := data_value_field_text(value)
	if !editable {
		ui_toast(state, text("data_files_not_editable"))
		return
	}
	browser.value_field = make_text_field(field_text, TEXT_FIELD_CAPACITY, characters)
	browser.editing_row = index
	open_keyboard(state, id)
}

// A value row is under the keyboard.
data_browser_editing :: proc(browser: Data_Browser) -> bool {
	return browser.open && browser.editing_row >= 0 && browser.editing_row < len(browser.value_rows)
}

// The field (the value's place, then the typed text over
// DATA_BROWSER_ENTRY_LINES lines, the end of a longer one) and the keys
// under it, alone in the panel as the new world screen shows its fields.
// Done sets the value; a number that does not parse keeps the old one
// and toasts.
data_value_entry :: proc(state: ^Ui_State, browser: ^Data_Browser) {
	label := data_value_row_path_text(browser.value_rows, browser.editing_row)
	if data_browser_entry(state, "data_value_entry", label, &browser.value_field) {
		if !set_data_browser_value(browser, browser.editing_row, text_field_text(&browser.value_field)) {
			ui_toast(state, text("data_files_bad_number"))
		}
		browser.editing_row = -1
		state.keyboard = Keyboard_State {
			return_focus = state.keyboard.field,
		}
	}
}

// The export directory under the keyboard, as a value is; Done sets the
// setting (set_export_directory).
data_export_directory_entry :: proc(state: ^Ui_State, browser: ^Data_Browser, settings: ^Settings) {
	if data_browser_entry(state, "data_export_directory_entry", text("data_files_export_directory"), &browser.export_field) {
		set_export_directory(settings, text_field_text(&browser.export_field), platform.platform_directories(context.temp_allocator).home)
		browser.editing_export_directory = false
		state.keyboard = Keyboard_State {
			return_focus = state.keyboard.field,
		}
	}
}

// The panel of an entry: the field, the label dimmed over the typed text,
// and the keys under it. True when the entry is done.
data_browser_entry :: proc(state: ^Ui_State, panel_label, label: string, field: ^Text_Field) -> (done: bool) {
	width := f32(max(DATA_BROWSER_PANEL_WIDTH, KEYBOARD_WIDTH + 2 * UI_PADDING))
	panel := fitted_panel(ui_panel_area(state), width, panel_height(DATA_BROWSER_ENTRY_ROWS, keyboard_keys_height(state.keyboard)))
	ui_panel_begin(state, panel_label, panel)
	content := inset(panel, UI_PADDING)
	field_area := cut_top(&content, f32(DATA_BROWSER_ENTRY_ROWS) * (UI_ROW_HEIGHT + UI_GAP) - UI_GAP)
	cut_top(&content, UI_GAP)
	draw_data_value_field(state, field_area, label, field)
	done = ui_on_screen_keyboard(state, field_area, {content.x + (content.width - KEYBOARD_WIDTH) / 2, content.y}, field)
	ui_panel_end(state)
	keyboard_glyph_bar(state)
	return done
}

// The value's place dimmed, then the typed text with the caret, wrapped,
// its last lines shown.
draw_data_value_field :: proc(state: ^Ui_State, area: Ui_Rectangle, label: string, field: ^Text_Field) {
	draw_fill(state, area, UI_WIDGET_COLOR)
	content := inset(area, UI_GAP)
	cut_left(&content, UI_GAP)
	cut_right(&content, UI_GAP)
	draw_text_fitted(state, cut_top(&content, DATA_BROWSER_ENTRY_LINE_HEIGHT), label, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	value := strings.concatenate({text_field_text(field), TEXT_FIELD_CARET}, context.temp_allocator)
	lines := wrap_text(state, value, UI_BODY_TEXT_SIZE, content.width)
	first := max(len(lines) - DATA_BROWSER_ENTRY_LINES, 0)
	for line in lines[first:] {
		draw_text_fitted(state, cut_top(&content, DATA_BROWSER_ENTRY_LINE_HEIGHT), line, UI_BODY_TEXT_SIZE, .Left, UI_ACCENT_COLOR)
	}
}

// One focusable row per line, so the focus scrolls through the file.
data_text_view :: proc(state: ^Ui_State, area: Ui_Rectangle, lines: []string) {
	region, rows := scroll_region_begin(state, "data_lines", area, data_browser_rows_height(len(lines)))
	for line, index in lines {
		row := cut_top(&rows, UI_ROW_HEIGHT)
		id := ui_id(state, "line_row", index)
		interaction := ui_interact(state, id, row)
		if row_in_view(row, region.area) {
			widget_background(state, row, id, interaction)
			draw_text_fitted(state, inset(row, UI_PADDING), line, UI_BODY_TEXT_SIZE, .Left)
		}
	}
	scroll_region_end(state, region)
}

// With a file open Save (live while unsaved), Duplicate and Remove (live
// while the selection is an array element) first, over the tree Export;
// Discard edit, live while the selected file has an overlay copy; Back,
// which closes the file first.
data_browser_buttons :: proc(state: ^Ui_State, row: Ui_Rectangle, browser: ^Data_Browser, requests: ^Frame_Requests) {
	count := browser.open ? 5 : 3
	next := 0
	if !browser.open {
		if ui_button(state, column_rectangle(row, count, 0, UI_GAP), text("data_files_export")) {
			requests^ += {.Export_Data_Files}
		}
		next = 1
	}
	if browser.open {
		element := data_value_row_is_element(browser.value_rows, browser.value_selected)
		if data_browser_button(state, column_rectangle(row, count, 0, UI_GAP), text("data_files_save"), browser.unsaved) {
			requests^ += {.Save_Data_Edit}
		}
		if data_browser_button(state, column_rectangle(row, count, 1, UI_GAP), text("data_files_duplicate"), element) {
			edit_data_browser_element(browser, .Duplicate)
		}
		if data_browser_button(state, column_rectangle(row, count, 2, UI_GAP), text("data_files_remove"), element) {
			edit_data_browser_element(browser, .Remove)
		}
		next = 3
	}
	edited := browser.selected >= 0 && browser.selected < len(browser.rows) && browser.rows[browser.selected].edited
	if data_browser_button(state, column_rectangle(row, count, next, UI_GAP), text("data_files_discard"), edited) {
		requests^ += {.Discard_Data_Edit}
	}
	if ui_button(state, column_rectangle(row, count, next + 1, UI_GAP), text("data_files_back")) {
		if browser.open {
			request_data_file_close(state, browser, requests)
		} else {
			pop_screen(&state.screens)
		}
	}
}

// ui_button, dimmed and inert while disabled; the focus reaches it either
// way, under the same id.
data_browser_button :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label: string, enabled: bool) -> bool {
	if enabled {
		return ui_button(state, rectangle, label)
	}
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle)
	widget_background(state, rectangle, id, interaction)
	draw_text_fitted(state, inset(rectangle, UI_GAP), label, UI_BODY_TEXT_SIZE, .Centre, UI_DIM_TEXT_COLOR)
	return false
}

// The export directory field and the Export on save toggle (0131), two
// settings. The field's tap or Confirm opens the keyboard with the
// directory.
data_export_row :: proc(state: ^Ui_State, row: Ui_Rectangle, browser: ^Data_Browser, settings: ^Settings) {
	toggle := row
	field := cut_left(&toggle, (row.width - UI_GAP) * 2 / 3)
	cut_left(&toggle, UI_GAP)
	label := text("data_files_export_directory")
	if data_export_directory_field(state, field, label, settings.export_directory) {
		browser.export_field = make_text_field(settings.export_directory, TEXT_FIELD_CAPACITY)
		browser.editing_export_directory = true
		open_keyboard(state, ui_id(state, label))
	}
	ui_toggle(state, toggle, text("data_files_export_on_save"), &settings.export_on_save)
}

// As ui_text_field, but the directory is fitted right of the label (a
// shared storage path is long), dimmed "not set" while empty.
data_export_directory_field :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, label, directory: string) -> bool {
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle)
	widget_background(state, rectangle, id, interaction)
	content := inset(rectangle, UI_PADDING)
	draw_text(state, cut_left(&content, ui_text_width(state, label, UI_BODY_TEXT_SIZE)), label, UI_BODY_TEXT_SIZE, .Left)
	cut_left(&content, UI_GAP)
	if directory == "" {
		draw_text_fitted(state, content, text("data_files_export_directory_none"), UI_BODY_TEXT_SIZE, .Right, UI_DIM_TEXT_COLOR)
	} else {
		draw_text_fitted(state, content, directory, UI_BODY_TEXT_SIZE, .Right)
	}
	return interaction.activated
}
