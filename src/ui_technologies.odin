package game

import "core:fmt"

// The technology screen (doc/fluids.md, Assembler, lab and research): the
// queued technology and its progress on the left with the filter toggle,
// the technologies sorted by name in the middle with the letter wheel,
// and the focused one's status, cost, description, prerequisites and
// unlocks on the right. Confirm queues the focused technology when it is available,
// replacing the queued one. It does not pause.

TECHNOLOGY_STATUS_COLUMN_WIDTH :: 380
TECHNOLOGY_LIST_COLUMN_WIDTH :: 560

// focused is the technology whose detail shows, NO_TECHNOLOGY before the
// first focus.
Technology_Browser :: struct {
	filter:        Technology_Filter,
	focused:       int,
	letter_radial: Radial_State,
}

make_technology_browser :: proc() -> Technology_Browser {
	return Technology_Browser{focused = NO_TECHNOLOGY}
}

technology_row_id :: proc(list_id: Ui_Id, technology: int) -> Ui_Id {
	return ui_hash(list_id, "row", technology)
}

status_color :: proc(status: Technology_Status) -> Ui_Color {
	switch status {
	case .Available:
		return UI_ACCENT_COLOR
	case .Researched, .Locked:
	}
	return UI_DIM_TEXT_COLOR
}

draw_technology_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context, names: []string, technology: int) {
	research := screen_context.world.research
	if research.queued && research.technology == technology {
		draw_fill(state, {row.x, row.y, RECIPE_CRAFTABLE_MARK_WIDTH, row.height}, UI_ACCENT_COLOR)
	}
	status := technology_status(screen_context.technologies, screen_context.unlocks^, technology)
	content := Ui_Rectangle{row.x + UI_PADDING, row.y, max(row.width - 2 * UI_PADDING, 0), row.height}
	level := technology_level_text(screen_context.technologies.technologies[technology], research.levels[technology])
	status_text := fit_text(state, level != "" ? level : text(technology_status_keys[status]), UI_BODY_TEXT_SIZE, content.width / 2)
	draw_text(state, content, status_text, UI_BODY_TEXT_SIZE, .Right, status_color(status))
	content.width = max(content.width - ui_text_width(state, status_text, UI_BODY_TEXT_SIZE) - UI_GAP, 0)
	draw_text_fitted(state, content, names[technology], UI_BODY_TEXT_SIZE, .Left, status == .Locked ? UI_DIM_TEXT_COLOR : UI_TEXT_COLOR)
}

// What each level of an infinite technology does, for the detail panel.
@(rodata)
technology_effect_keys := [Technology_Effect]string {
	.None                = "",
	.Mining_Productivity = "technologies_effect_mining_productivity",
	.Research_Speed      = "technologies_effect_research_speed",
}

// Returns the activated technology or NO_TECHNOLOGY.
technology_list :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, names: []string, visible: []int) -> int {
	activated := NO_TECHNOLOGY
	if len(visible) == 0 {
		ui_label(state, {area.x, area.y, area.width, UI_ROW_HEIGHT}, text("technologies_none"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	list := scroll_list_begin(state, "technology_list", area, len(visible))
	for technology, position in visible {
		row := scroll_list_row(list, position)
		id := ui_id(state, "row", technology)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, position)
			screen_context.technology_browser.focused = technology
		}
		if interaction.activated {
			activated = technology
		}
		widget_background(state, row, id, interaction)
		draw_technology_row(state, row, screen_context, names, technology)
	}
	scroll_list_end(state, &list)
	return activated
}

// The filter toggle, then the queued technology, its progress bar and
// units.
technology_status_column :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	content := area
	browser := screen_context.technology_browser
	ui_toggle(state, settings_row(&content), text("technologies_hide_researched"), &browser.filter.hide_researched)
	detail_line(state, &content, text("technologies_queued"), UI_DIM_TEXT_COLOR)
	research := screen_context.world.research
	if !research.queued {
		detail_line(state, &content, text("technologies_none_queued"))
		return
	}
	detail_line(state, &content, technology_name(screen_context.technologies, research.technology), UI_ACCENT_COLOR)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), research_progress_fraction(research, screen_context.technologies))
	units := fmt.tprintf("%s %s", text("technologies_units"), research_progress_text(research, screen_context.technologies))
	draw_wrapped(state, &content, units)
}

technology_names_text :: proc(technologies: Technology_Registry, indices: []int) -> string {
	if len(indices) == 0 {
		return text("recipes_link_none")
	}
	result := ""
	for technology, index in indices {
		name := technology_name(technologies, technology)
		result = index == 0 ? name : fmt.tprintf("%s, %s", result, name)
	}
	return result
}

// The focused technology: status, cost, its description, prerequisites
// and the recipes it unlocks.
technology_detail_panel :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, names: []string) {
	technology := screen_context.technology_browser.focused
	if technology == NO_TECHNOLOGY {
		return
	}
	content := area
	definition := screen_context.technologies.technologies[technology]
	status := technology_status(screen_context.technologies, screen_context.unlocks^, technology)
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), names[technology], UI_HEADING_TEXT_SIZE, .Left)
	detail_line(state, &content, text(technology_status_keys[status]), status_color(status))
	levels := screen_context.world.research.levels
	if definition.infinite {
		detail_line(state, &content, fmt.tprintf("%s %d", text("technologies_level"), levels[technology]), UI_ACCENT_COLOR)
	}
	units := technology_next_cost(definition, levels, technology)
	cost := fmt.tprintf("%s %s", text(definition.infinite ? "technologies_next_level_cost" : "technologies_cost"), technology_cost_text(definition, units, screen_context.items))
	draw_wrapped(state, &content, cost)
	if description := technology_description(screen_context.technologies, technology); description != "" {
		cut_top(&content, UI_GAP)
		draw_wrapped(state, &content, description, UI_DIM_TEXT_COLOR)
	}
	cut_top(&content, UI_GAP)
	prerequisites := fmt.tprintf("%s %s", text("technologies_prerequisites"), technology_names_text(screen_context.technologies, definition.prerequisites))
	draw_wrapped(state, &content, prerequisites)
	cut_top(&content, UI_GAP)
	detail_line(state, &content, text("technologies_unlocks"), UI_DIM_TEXT_COLOR)
	if len(definition.unlocks) == 0 {
		draw_wrapped(state, &content, text(definition.infinite ? technology_effect_keys[definition.effect] : "technologies_unlocks_later"))
	}
	for recipe in definition.unlocks {
		if content.height >= UI_ROW_HEIGHT {
			draw_recipe_row(state, cut_top(&content, UI_ROW_HEIGHT), screen_context, recipe, false)
		}
	}
}

focus_technology_row :: proc(state: ^Ui_State, browser: ^Technology_Browser, list_id: Ui_Id, technology: int) -> bool {
	id := technology_row_id(list_id, technology)
	if widget_index(state.widgets[:], id) < 0 {
		return false
	}
	state.requested_focus = id
	browser.focused = technology
	return true
}

// A focus that belongs to no widget of this screen (just opened, or the
// filter hid the row) goes to the focused technology or the first row.
settle_technology_focus :: proc(state: ^Ui_State, browser: ^Technology_Browser, list_id: Ui_Id, visible: []int) {
	if state.requested_focus != 0 || widget_index(state.widgets[:], state.focus) >= 0 || len(visible) == 0 {
		return
	}
	if !focus_technology_row(state, browser, list_id, browser.focused) {
		focus_technology_row(state, browser, list_id, visible[0])
	}
}

queue_focused_research :: proc(state: ^Ui_State, screen_context: Screen_Context, technology: int) {
	refusal := queue_research(&screen_context.world.research, screen_context.technologies, screen_context.unlocks^, technology)
	if refusal != .None {
		ui_toast(state, text(research_refusal_keys[refusal]))
	}
}

technology_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	browser := screen_context.technology_browser
	names := technology_display_names(screen_context.technologies, context.temp_allocator)
	order := recipe_name_order(names, context.temp_allocator)
	visible := filter_technologies(screen_context.technologies, screen_context.unlocks^, order, browser.filter, context.temp_allocator)
	ui_backdrop(state)
	panel := ui_panel_area(state)
	ui_panel_begin(state, "technologies", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("technologies_title"), UI_HEADING_TEXT_SIZE, .Centre)
	cut_top(&content, UI_GAP)
	status_width, list_width := three_column_widths(content, TECHNOLOGY_STATUS_COLUMN_WIDTH, TECHNOLOGY_LIST_COLUMN_WIDTH)
	technology_status_column(state, cut_left(&content, status_width), screen_context)
	cut_left(&content, 2 * UI_PADDING)
	list_area := cut_left(&content, list_width)
	cut_left(&content, 2 * UI_PADDING)
	list_id := ui_id(state, "technology_list")
	letter := letter_input(state, &browser.letter_radial)
	activated := technology_list(state, list_area, screen_context, names, visible)
	technology_detail_panel(state, content, screen_context, names)
	ui_panel_end(state)
	settle_technology_focus(state, browser, list_id, visible)
	if position := recipe_position_for_letter(names, visible, letter); letter != 0 && position >= 0 {
		focus_technology_row(state, browser, list_id, visible[position])
	}
	if activated != NO_TECHNOLOGY {
		queue_focused_research(state, screen_context, activated)
	}
	draw_letter_wheel(state, browser.letter_radial)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_queue_research")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}
