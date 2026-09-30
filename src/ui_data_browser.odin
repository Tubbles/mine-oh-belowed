package game

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
// returns from a file to the tree, then closes the screen. Viewing only;
// saving comes with work item 0130.
//
// The screen changes only the browser's expansion, selection and
// requests; the frame loop reads the directory and the files
// (serve_data_browser in loop.odin).

DATA_BROWSER_PANEL_WIDTH :: 1100
DATA_BROWSER_INDENT :: 28
DATA_BROWSER_CHEVRON_WIDTH :: 24
DATA_BROWSER_SELECTED_MARKER_WIDTH :: 6
// The size and the edited tag on a file row.
DATA_BROWSER_DETAIL_WIDTH :: 220

data_browser_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	browser := screen_context.data_browser
	if browser == nil {
		pop_screen(&state.screens)
		return
	}
	ui_backdrop(state)
	area := ui_panel_area(state)
	panel := fitted_panel(area, DATA_BROWSER_PANEL_WIDTH, area.height)
	ui_panel_begin(state, "data_files", panel)
	content := inset(panel, UI_PADDING)
	data_browser_title_row(state, cut_top(&content, UI_ROW_HEIGHT), browser^)
	cut_top(&content, UI_GAP)
	buttons := cut_bottom(&content, UI_ROW_HEIGHT)
	cut_bottom(&content, UI_GAP)
	if browser.open {
		data_file_view(state, content, browser)
	} else {
		data_tree_view(state, content, browser)
	}
	data_browser_buttons(state, buttons, browser)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}}
	ui_glyph_bar_or_back_row(state, hints[:])
	// After the touch row, whose Back lands in the frame's input:
	// handle_screen_keys pops the screen after this, so a Back with a
	// file open is taken here and only asks for the file to close. The
	// frame loop closes it between frames: this frame's draw list points
	// into the file's memory.
	if browser.open && (state.input.back || state.input.pause) && !state.tooltip_open {
		browser.close_requested = true
		state.input.back, state.input.pause = false, false
	}
}

// The heading, and the edited tag in the accent when the open file is the
// data edits overlay's copy.
data_browser_title_row :: proc(state: ^Ui_State, row: Ui_Rectangle, browser: Data_Browser) {
	title := row
	if browser.open && browser.shows_overlay {
		tag := cut_right(&title, DATA_BROWSER_DETAIL_WIDTH / 2)
		draw_text_fitted(state, tag, text("data_files_edited"), UI_BODY_TEXT_SIZE, .Right, ui_theme(state).colors[.Accent])
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
data_tree_view :: proc(state: ^Ui_State, area: Ui_Rectangle, browser: ^Data_Browser) {
	if len(browser.rows) == 0 {
		ui_label(state, {area.x, area.y, area.width, UI_ROW_HEIGHT}, text("data_files_none"))
		return
	}
	visible := visible_row_indices(browser.rows, browser.expanded)
	region, rows := scroll_region_begin(state, "data_tree", area, data_browser_rows_height(len(visible)))
	for index in visible {
		data_tree_row_widget(state, cut_top(&rows, UI_ROW_HEIGHT), region.area, browser, index)
	}
	scroll_region_end(state, region)
}

data_tree_row_widget :: proc(state: ^Ui_State, row, view: Ui_Rectangle, browser: ^Data_Browser, index: int) {
	entry := browser.rows[index]
	id := ui_id(state, "data_row", index)
	if index == browser.selected {
		ui_prefer_focus(state, id)
	}
	interaction := ui_interact(state, id, row)
	if interaction.activated {
		activate_data_tree_row(state, browser, index)
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
	draw_text_fitted(state, column(area, 2, 1, UI_GAP), data_file_size_text(entry.size), UI_BODY_TEXT_SIZE, .Right, UI_DIM_TEXT_COLOR)
	if entry.edited {
		draw_text_fitted(state, column(area, 2, 0, UI_GAP), text("data_files_edited"), UI_BODY_TEXT_SIZE, .Right, ui_theme(state).colors[.Accent])
	}
}

// A directory expands or collapses; a text file opens (the frame loop
// reads it before the next frame); a binary file says it cannot.
activate_data_tree_row :: proc(state: ^Ui_State, browser: ^Data_Browser, index: int) {
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
	browser.open_requested = true
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
	entry := browser.value_rows[index]
	id := ui_id(state, "value_row", index)
	interaction := ui_interact(state, id, row)
	if interaction.activated && entry.expandable {
		browser.value_expanded[index] = !browser.value_expanded[index]
	}
	if !row_in_view(row, view) {
		return
	}
	widget_background(state, row, id, interaction)
	content := inset(row, UI_PADDING)
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

// Discard edit, live while the selected file has an overlay copy, and
// Back, which closes the file first.
data_browser_buttons :: proc(state: ^Ui_State, row: Ui_Rectangle, browser: ^Data_Browser) {
	edited := browser.selected >= 0 && browser.selected < len(browser.rows) && browser.rows[browser.selected].edited
	if data_browser_discard_button(state, column(row, 2, 0, UI_GAP), edited) {
		browser.discard_requested = true
	}
	if ui_button(state, column(row, 2, 1, UI_GAP), text("data_files_back")) {
		if browser.open {
			browser.close_requested = true
		} else {
			pop_screen(&state.screens)
		}
	}
}

// ui_button, dimmed and inert while disabled; the focus reaches it either
// way, under the same id.
data_browser_discard_button :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, enabled: bool) -> bool {
	label := text("data_files_discard")
	if enabled {
		return ui_button(state, rectangle, label)
	}
	id := ui_id(state, label)
	interaction := ui_interact(state, id, rectangle)
	widget_background(state, rectangle, id, interaction)
	draw_text_fitted(state, inset(rectangle, UI_GAP), label, UI_BODY_TEXT_SIZE, .Centre, UI_DIM_TEXT_COLOR)
	return false
}
