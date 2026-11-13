package game

// The window carousel (0385, after Techtonica): the windows the world
// opens, in the order LT and RT (Q and E, the title row's arrows) step
// through them, wrapping. A step replaces the top screen
// (handle_screen_keys, replace_top_screen), so the stack never grows and
// Back returns to what lies under the window: the world, or the lab's
// panel that opened Research. 0277 folds the first two into the crafting
// view.
@(rodata)
window_carousel := [?]Screen{.Inventory, .Recipes, .Journal, .Technologies, .Map, .Statistics, .Power}

// The screen's place in the carousel, -1 outside it.
window_carousel_index :: proc(screen: Screen) -> int {
	for window, index in window_carousel {
		if window == screen {
			return index
		}
	}
	return -1
}

// steps along the carousel, wrapping both ways; a screen outside it comes
// back unchanged.
step_window_carousel :: proc(screen: Screen, steps: int) -> Screen {
	index := window_carousel_index(screen)
	if index < 0 {
		return screen
	}
	return window_carousel[(index + steps) %% len(window_carousel)]
}

// The recipe browser is a window only outside its picker and station
// modes, which belong to a machine's panel (views nil: outside them).
window_in_carousel :: proc(screen: Screen, views: ^Session_Views) -> bool {
	if window_carousel_index(screen) < 0 {
		return false
	}
	if screen != .Recipes || views == nil {
		return true
	}
	return views.recipe_browser.selecting_for == NO_ENTITY && views.recipe_browser.station == NO_ENTITY
}

// The string key of a window's title, "" outside the carousel.
window_title_key :: proc(screen: Screen) -> string {
	#partial switch screen {
	case .Inventory:
		return "inventory_title"
	case .Recipes:
		return "recipes_title"
	case .Journal:
		return "journal_title"
	case .Technologies:
		return "technologies_title"
	case .Map:
		return "map_title"
	case .Statistics:
		return "statistics_title"
	case .Power:
		return "power_overview_title"
	}
	return ""
}

// The row at the top of every window: the top screen's title, centred
// and fitted, between a left and a right arrow. A press on an arrow sets
// the frame's window step, which handle_screen_keys takes after the
// screen as it takes LT and RT. Off touch the window step's glyphs sit
// at the row's ends, outside the arrows, so no glyph bar names them. No
// focus target, as a stepped tab strip.
ui_window_title_row :: proc(state: ^Ui_State, rectangle: Ui_Rectangle) {
	row := rectangle
	if !touch_row_shows(state) {
		draw_window_step_glyph(state, cut_left(&row, glyph_box_width(state, .Window_Previous)), .Window_Previous)
		cut_left(&row, UI_GAP)
		draw_window_step_glyph(state, cut_right(&row, glyph_box_width(state, .Window_Next)), .Window_Next)
		cut_right(&row, UI_GAP)
	}
	if window_title_arrow(state, cut_left(&row, UI_ROW_HEIGHT), .Arrow_Left) {
		state.input.window_previous = true
	}
	if window_title_arrow(state, cut_right(&row, UI_ROW_HEIGHT), .Arrow_Right) {
		state.input.window_next = true
	}
	cut_left(&row, UI_GAP)
	cut_right(&row, UI_GAP)
	draw_text_fitted(state, row, text(window_title_key(top_screen(state.screens))), UI_HEADING_TEXT_SIZE, .Centre)
}

// A glyph box as the glyph bar draws one, a bar's height centred in the
// column.
draw_window_step_glyph :: proc(state: ^Ui_State, column: Ui_Rectangle, button: Glyph_Button) {
	height := min(f32(UI_GLYPH_BAR_HEIGHT), column.height)
	box := Ui_Rectangle{column.x, column.y + (column.height - height) / 2, column.width, height}
	shown := glyph(state, button)
	draw_ui_icon(state, box, shown.icon)
	if shown.icon == .Key {
		draw_text(state, box, shown.label, UI_GLYPH_TEXT_SIZE, .Centre, UI_GLYPH_COLOR)
	}
}

// An arrow square with the tab's hover fill; true on a press on it.
window_title_arrow :: proc(state: ^Ui_State, square: Ui_Rectangle, icon: Ui_Icon) -> bool {
	hovered := ui_pointer_over(state, square)
	draw_fill(state, square, widget_fill_color(ui_theme(state), hovered, hovered && state.pointer_held))
	draw_ui_icon(state, inset(square, UI_GAP), icon)
	return state.click && hovered
}
