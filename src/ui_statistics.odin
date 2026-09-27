package game

import "core:fmt"

// The production statistics screen (work item 0028), opened with
// Open_Statistics or from the pause menu; it does not pause. Three tabs:
// Production (the window choice and the item list sorted by produced over
// the window on the left, the fluids below the items in litres per minute,
// the focused row's detail on the right), Power (the power overview's
// body) and Shipments (ui_launch_pad.odin). The pure parts are in
// production_statistics.odin.

STATISTICS_LIST_COLUMN_WIDTH :: 900
STATISTICS_RATE_COLUMN_WIDTH :: 200

// window is the chosen rate window; focused the item whose detail shows,
// valid while has_focus, or focused_fluid the fluid's, valid while
// fluid_has_focus.
Statistics_View :: struct {
	window:          Rate_Window,
	focused:         Item_Id,
	has_focus:       bool,
	focused_fluid:   Fluid_Id,
	fluid_has_focus: bool,
	letter_radial:   Radial_State,
}

statistics_row_id :: proc(list_id: Ui_Id, item: Item_Id) -> Ui_Id {
	return ui_hash(list_id, "row", int(item))
}

format_window_rate :: proc(total: u64, window: Rate_Window) -> string {
	return format_per_minute(f32(window_rate_tenths_per_minute(total, window)) / 10)
}

@(rodata)
rate_window_keys := [Rate_Window]string {
	.One_Minute    = "statistics_window_1",
	.Ten_Minutes   = "statistics_window_10",
	.Sixty_Minutes = "statistics_window_60",
}

format_fluid_window_rate :: proc(total: u64, window: Rate_Window) -> string {
	return fmt.tprintf("%s/min", format_volume(f32(total) / f32(rate_window_minutes[window])))
}

next_rate_window :: proc(window: Rate_Window) -> Rate_Window {
	return Rate_Window((int(window) + 1) % len(Rate_Window))
}

// Produced then consumed, right aligned in two columns.
draw_rate_columns :: proc(state: ^Ui_State, row: Ui_Rectangle, produced, consumed: string, color: Ui_Color) {
	content := inset(row, UI_PADDING)
	consumed_column := content
	consumed_column.x = content.x + content.width - STATISTICS_RATE_COLUMN_WIDTH
	consumed_column.width = STATISTICS_RATE_COLUMN_WIDTH
	produced_column := consumed_column
	produced_column.x -= STATISTICS_RATE_COLUMN_WIDTH + UI_GAP
	draw_text(state, produced_column, produced, UI_BODY_TEXT_SIZE, .Right, color)
	draw_text(state, consumed_column, consumed, UI_BODY_TEXT_SIZE, .Right, color)
}

draw_statistics_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context, names: []string, rate: Item_Rate_Row, window: Rate_Window) {
	draw_item_icon(state, icon_rectangle(row), item_icon(screen_context.items, rate.item))
	draw_text(state, text_after_icon(row), names[rate.item], UI_BODY_TEXT_SIZE, .Left)
	draw_rate_columns(state, row, format_window_rate(rate.produced, window), format_window_rate(rate.consumed, window), UI_TEXT_COLOR)
}

draw_fluid_statistics_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context, rate: Fluid_Rate_Row, window: Rate_Window) {
	fluid := screen_context.fluids.fluids[rate.fluid]
	icon := Item_Icon{kind = .Lettered, color = {fluid.color.r, fluid.color.g, fluid.color.b, 255}, letters = item_letters(fluid.id)}
	draw_item_icon(state, icon_rectangle(row), icon)
	draw_text(state, text_after_icon(row), fluid_name(screen_context.fluids, rate.fluid), UI_BODY_TEXT_SIZE, .Left)
	draw_rate_columns(state, row, format_fluid_window_rate(rate.produced, window), format_fluid_window_rate(rate.consumed, window), UI_TEXT_COLOR)
}

// Item rows, then fluid rows, in one scrolled list.
statistics_item_list :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, names: []string, rows: []Item_Rate_Row, fluid_rows: []Fluid_Rate_Row) {
	view := screen_context.statistics_view
	if len(rows) + len(fluid_rows) == 0 {
		ui_label(state, {area.x, area.y, area.width, UI_ROW_HEIGHT}, text("statistics_nothing_yet"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	list := scroll_list_begin(state, "statistics_list", area, len(rows) + len(fluid_rows))
	for rate, position in rows {
		row := scroll_list_row(list, position)
		id := ui_id(state, "row", int(rate.item))
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, position)
			view.focused, view.has_focus, view.fluid_has_focus = rate.item, true, false
		}
		widget_background(state, row, id, interaction)
		draw_statistics_row(state, row, screen_context, names, rate, view.window)
	}
	for rate, index in fluid_rows {
		position := len(rows) + index
		row := scroll_list_row(list, position)
		id := ui_id(state, "fluid_row", int(rate.fluid))
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, position)
			view.focused_fluid, view.fluid_has_focus, view.has_focus = rate.fluid, true, false
		}
		widget_background(state, row, id, interaction)
		draw_fluid_statistics_row(state, row, screen_context, rate, view.window)
	}
	scroll_list_end(state, &list)
}

// The focused fluid's litres per minute over the window, voided included.
statistics_fluid_detail :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	view := screen_context.statistics_view
	content := area
	rate := fluid_rate_row(screen_context.world.statistics, view.focused_fluid, view.window)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), fluid_name(screen_context.fluids, view.focused_fluid), UI_HEADING_TEXT_SIZE, .Left)
	detail_line(state, &content, fmt.tprintf("%s: %s", text("statistics_produced"), format_fluid_window_rate(rate.produced, view.window)))
	detail_line(state, &content, fmt.tprintf("%s: %s", text("statistics_consumed"), format_fluid_window_rate(rate.consumed, view.window)))
	detail_line(state, &content, fmt.tprintf("%s: %s", text("statistics_voided_rate"), format_fluid_window_rate(rate.voided, view.window)), UI_DIM_TEXT_COLOR)
}

statistics_simulation_content :: proc(screen_context: Screen_Context) -> Simulation_Content {
	return Simulation_Content {
		items = screen_context.items,
		machines = screen_context.machines,
		recipes = screen_context.recipes,
		technologies = screen_context.technologies,
		veins = screen_context.veins,
	}
}

// The focused item's rates, the machines making and using it now, and
// what a lenient world voided of it.
statistics_detail :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, names: []string) {
	view := screen_context.statistics_view
	if view.fluid_has_focus {
		statistics_fluid_detail(state, area, screen_context)
		return
	}
	if !view.has_focus {
		return
	}
	content := area
	statistics := screen_context.world.statistics
	rate := item_rate_row(statistics, view.focused, view.window)
	counts := count_item_machines(screen_context.world, statistics_simulation_content(screen_context), view.focused)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), names[view.focused], UI_HEADING_TEXT_SIZE, .Left)
	detail_line(state, &content, fmt.tprintf("%s: %s", text("statistics_produced"), format_window_rate(rate.produced, view.window)))
	detail_line(state, &content, fmt.tprintf("%s: %s", text("statistics_consumed"), format_window_rate(rate.consumed, view.window)))
	detail_line(state, &content, fmt.tprintf("%s: %d", text("statistics_producers"), counts.producers))
	detail_line(state, &content, fmt.tprintf("%s: %d", text("statistics_consumers"), counts.consumers))
	detail_line(state, &content, fmt.tprintf("%s: %d", text("statistics_voided"), item_counter(statistics.voided, view.focused)), UI_DIM_TEXT_COLOR)
}

focus_statistics_row :: proc(state: ^Ui_State, view: ^Statistics_View, list_id: Ui_Id, item: Item_Id) -> bool {
	id := statistics_row_id(list_id, item)
	if widget_index(state.widgets[:], id) < 0 {
		return false
	}
	state.requested_focus = id
	view.focused, view.has_focus, view.fluid_has_focus = item, true, false
	return true
}

// A focus that belongs to no widget of this screen (just opened) goes to
// the focused item's row or the first row.
settle_statistics_focus :: proc(state: ^Ui_State, view: ^Statistics_View, list_id: Ui_Id, rows: []Item_Rate_Row) {
	if state.requested_focus != 0 || widget_index(state.widgets[:], state.focus) >= 0 || len(rows) == 0 {
		return
	}
	if !view.has_focus || !focus_statistics_row(state, view, list_id, view.focused) {
		focus_statistics_row(state, view, list_id, rows[0].item)
	}
}

production_tab :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	view := screen_context.statistics_view
	content := area
	names := item_display_names(screen_context.items, context.temp_allocator)
	rows := statistics_rows(screen_context.world.statistics, view.window, context.temp_allocator)
	fluid_rows := fluid_statistics_rows(screen_context.world.statistics, view.window, context.temp_allocator)
	list_area := cut_left(&content, STATISTICS_LIST_COLUMN_WIDTH)
	cut_left(&content, 2 * UI_PADDING)
	if ui_choice(state, settings_row(&list_area), text("statistics_window"), text(rate_window_keys[view.window])) {
		view.window = next_rate_window(view.window)
	}
	header := cut_top(&list_area, UI_ROW_HEIGHT)
	draw_text(state, inset(header, UI_PADDING), text("statistics_item"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	draw_rate_columns(state, header, text("statistics_produced"), text("statistics_consumed"), UI_DIM_TEXT_COLOR)
	list_id := ui_id(state, "statistics_list")
	letter := letter_input(state, &view.letter_radial)
	statistics_item_list(state, list_area, screen_context, names, rows, fluid_rows)
	statistics_detail(state, content, screen_context, names)
	settle_statistics_focus(state, view, list_id, rows)
	if position := row_position_for_letter(names, rows, letter); letter != 0 && position >= 0 {
		focus_statistics_row(state, view, list_id, rows[position].item)
	}
	draw_letter_wheel(state, view.letter_radial)
}

statistics_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	panel := ui_safe_area(state)
	cut_bottom(&panel, UI_GLYPH_TEXT_SIZE + 4 * UI_GAP)
	ui_panel_begin(state, "statistics", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("statistics_title"), UI_HEADING_TEXT_SIZE, .Centre)
	cut_top(&content, UI_GAP)
	tab_labels := [?]string{text("statistics_tab_production"), text("statistics_tab_power"), text("statistics_tab_shipments")}
	tab := ui_tabs(state, cut_top(&content, UI_ROW_HEIGHT), "statistics_tabs", tab_labels[:])
	cut_top(&content, UI_GAP)
	switch tab {
	case 0:
		production_tab(state, content, screen_context)
	case 1:
		power_overview_body(state, content, screen_context)
	case:
		shipments_tab(state, content, screen_context)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Tab_Previous, ""}, {.Tab_Next, text("hint_tabs")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}
