package game

import "core:fmt"
import "core:slice"

// The crafting view (0277, after Techtonica): the window the inventory
// binding and C open, one panel with the inventory half on the left and
// the schematics half on the right. The schematics half shows the
// crafting tabs (crafting_tab_list, from the data's categories table),
// the "Unlocked only" toggle and the queue summary, a grid of the tab's
// recipes in data order and the focused recipe's detail with its graph
// lists. The halves are panels without art inside the view's panel, so
// the focus wraps inside each, and Left and Right cross the seam between
// them (crafting_seam_target). A on a schematic crafts one, with R1 held
// five, with L1 held the most. The context action clears the crafting
// queue on the schematics half and sorts or configures on the inventory
// half. Y assigns the focused slot's or schematic's item to the active
// toolbar's selected slot (0278, toolbar_assignment), and held opens the
// toolbar edit mode (0279, ui_toolbar_edit.odin). The
// recipe browser (ui_recipes.odin) keeps the picker and the station modes.

Crafting_Half :: enum u8 {
	Inventory,
	Schematics,
}

// The view's state for the session (Session_Views): the tab's position in
// the tab list, clamped each frame, and Unlocked only. The focused recipe
// and the plans are the recipe browser's.
Crafting_View :: struct {
	tab:            int,
	available_only: bool,
}

// Unlocked only is on, as the browser's was (0091).
make_crafting_view :: proc() -> Crafting_View {
	return Crafting_View{available_only = true}
}

// The inventory half (784, its slot grid), the seam (2 × 16), the
// schematics half (864 at 1080p) and the padding (2 × 16).
CRAFTING_VIEW_WIDTH :: 1712
CRAFTING_GRID_COLUMNS :: 5
CRAFTING_DETAIL_MINIMUM_WIDTH :: 300
// The narrowest schematics half that holds the detail beside a two column
// grid: slot_grid_width(2), the gap and the detail.
CRAFTING_SIDE_BY_SIDE_WIDTH :: 500
CRAFTING_STACKED_GRID_ROWS :: 2

// The schematics half's touch row: the recipe row of the station browser,
// Clear queue, which the context action does on the gamepad and the
// keyboard, and Assign, Y's place (0278).
CRAFTING_VIEW_TOUCH_BUTTONS :: Touch_Buttons{.Assign_Toolbar, .Craft, .Craft_Five, .Craft_Most, .Cancel_Craft, .Clear_Craft_Queue, .Back}

Crafting_View_Layout :: struct {
	title, inventory, seam, schematics, tabs, toggle, summary, grid, detail: Ui_Rectangle,
	columns:                                                                 int,
	// The schematics half is narrower than CRAFTING_SIDE_BY_SIDE_WIDTH:
	// the grid sits over the detail and the summary under the toggle.
	stacked:                                                                 bool,
}

// The view's rectangles in its panel's content (the panel inset by
// UI_PADDING): the title row and a gap across it, the inventory half as
// wide as its slot grid, the seam, and the schematics half with its tabs,
// a gap, its header, a gap and the body. The header is a row with the
// toggle and the queue summary side by side, or in the stacked layout a
// row for each (0277).
crafting_view_layout :: proc(content: Ui_Rectangle) -> Crafting_View_Layout {
	rest := content
	layout: Crafting_View_Layout
	layout.title = cut_top(&rest, UI_ROW_HEIGHT)
	cut_top(&rest, UI_GAP)
	layout.inventory = cut_left(&rest, slot_grid_width(INVENTORY_COLUMNS))
	layout.seam = cut_left(&rest, 2 * UI_PADDING)
	layout.schematics = rest
	layout.stacked = rest.width < CRAFTING_SIDE_BY_SIDE_WIDTH
	layout.tabs = cut_top(&rest, UI_ROW_HEIGHT)
	cut_top(&rest, UI_GAP)
	header := cut_top(&rest, UI_ROW_HEIGHT)
	cut_top(&rest, UI_GAP)
	if layout.stacked {
		layout.toggle = header
		layout.summary = cut_top(&rest, UI_ROW_HEIGHT)
		cut_top(&rest, UI_GAP)
	} else {
		layout.toggle = column_rectangle(header, 2, 0, UI_GAP)
		layout.summary = inset(column_rectangle(header, 2, 1, UI_GAP), UI_GAP)
	}
	layout.grid, layout.detail, layout.columns = crafting_body_layout(rest)
	return layout
}

// The grid beside the detail while the body holds both, the detail at
// least CRAFTING_DETAIL_MINIMUM_WIDTH wide, else a grid of
// CRAFTING_STACKED_GRID_ROWS rows over the detail.
crafting_body_layout :: proc(body: Ui_Rectangle) -> (grid, detail: Ui_Rectangle, columns: int) {
	rest := body
	if body.width >= CRAFTING_SIDE_BY_SIDE_WIDTH {
		columns = min(CRAFTING_GRID_COLUMNS, slot_columns(body.width - 2 * UI_PADDING - CRAFTING_DETAIL_MINIMUM_WIDTH))
		grid = cut_left(&rest, slot_grid_width(columns))
		cut_left(&rest, 2 * UI_PADDING)
		return grid, rest, columns
	}
	columns = min(CRAFTING_GRID_COLUMNS, slot_columns(body.width))
	grid = cut_top(&rest, slot_grid_height(CRAFTING_STACKED_GRID_ROWS))
	cut_top(&rest, UI_PADDING)
	return grid, rest, columns
}

// The recipes of a tab: those whose category the categories table maps to
// it, the unlocked ones only when asked, in index order.
crafting_view_recipes :: proc(recipes: Recipe_Registry, tab: Recipe_Category, available_only: bool, available: []bool, allocator := context.allocator) -> []int {
	shown := make([dynamic]int, 0, len(recipes.recipes), allocator)
	for recipe, index in recipes.recipes {
		unlocked := index < len(available) && available[index]
		if recipes.crafting_tabs[recipe.category] == tab && (unlocked || !available_only) {
			append(&shown, index)
		}
	}
	return shown[:]
}

// The view's panel: its art, the window's title row and the line down the
// seam's middle.
crafting_view_frame :: proc(state: ^Ui_State, panel: Ui_Rectangle, layout: Crafting_View_Layout) {
	ui_panel_begin(state, "crafting_view", panel)
	ui_window_title_row(state, layout.title)
	border := ui_theme(state).border
	seam := layout.seam
	draw_fill(state, {seam.x + (seam.width - border) / 2, seam.y, border, seam.height}, theme_color(state, .Panel_Edge))
	ui_panel_end(state)
}

// What the schematics half drew: its panel, the grid's id (its cells are
// recipe_row_id of it), the toggle's id, the grid's recipes, the recipe
// activated in the grid and the one reached through the graph lists
// (NO_RECIPE for none).
Schematics_Half :: struct {
	panel, grid, toggle: Ui_Id,
	visible:             []int,
	activated, reached:  int,
}

// The schematics half's panel: the tabs, the header, the grid and the
// detail. A tab changed this frame starts the grid at its top and makes
// its first recipe the focused one, so the detail follows the tab
// wherever the focus is. Unlocked only turned on moves the detail off a
// recipe the grid now hides to the first shown (0277).
schematics_half :: proc(state: ^Ui_State, screen_context: Screen_Context, layout: Crafting_View_Layout) -> Schematics_Half {
	view := &screen_context.views.crafting_view
	browser := &screen_context.views.recipe_browser
	player := screen_context.player
	refresh_craftable_recipes(&browser.plans, screen_context.recipes, screen_context.unlocks^, player.inventory, player.crafting, screen_craft_makers(screen_context), screen_context.free_crafting)
	craftable := browser.plans.craftable[:]
	half := Schematics_Half{activated = NO_RECIPE, reached = NO_RECIPE}
	ui_panel_begin(state, "schematics", layout.schematics, art = false)
	half.panel = state.current_panel
	tab, changed := crafting_view_tabs(state, layout.tabs, view, screen_context.recipes)
	toggled: bool
	half.toggle, toggled = crafting_view_header(state, layout, view, player.crafting)
	half.visible = crafting_view_recipes(screen_context.recipes, tab, view.available_only, screen_context.unlocks.available, context.temp_allocator)
	half.grid = ui_id(state, "schematics_grid")
	if changed {
		state.scroll_offsets[half.grid] = 0
	}
	if changed || (toggled && !slice.contains(half.visible, browser.focused_recipe)) {
		browser.focused_recipe = len(half.visible) > 0 ? half.visible[0] : NO_RECIPE
	}
	half.activated = schematic_grid(state, layout.grid, layout.columns, screen_context, half.visible, craftable)
	half.reached = recipe_detail_panel(state, layout.detail, screen_context, craftable)
	ui_panel_end(state)
	return half
}

// The tab strip, no focus target: the tab step (the right stick's flick,
// `[` and `]`) steps it from either half, the pointer picks a tab. Returns
// the tab's category after the frame and whether it changed.
crafting_view_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, view: ^Crafting_View, recipes: Recipe_Registry) -> (tab: Recipe_Category, changed: bool) {
	tabs, count := crafting_tab_list(recipes)
	labels: [len(Recipe_Category)]string
	icons: [len(Recipe_Category)]Ui_Icon
	for category, position in tabs[:count] {
		labels[position], icons[position] = text(recipe_category_key(category)), recipe_category_icons[category]
	}
	before := clamp(view.tab, 0, count - 1)
	state.selections[ui_id(state, "crafting_tabs")] = before
	view.tab = ui_tabs(state, rectangle, "crafting_tabs", labels[:count], icons[:count], .Stepped, icons_alone_when_cut = true)
	return tabs[view.tab], view.tab != before
}

// The "Unlocked only" toggle, which the focus reaches, and the queue
// summary, in the accent while the queue waits. In the stacked layout the
// toggle reads "Unlocked" where the whole label does not fit
// (crafting_view_toggle_label). Returns the toggle's id and whether it
// flipped.
crafting_view_header :: proc(state: ^Ui_State, layout: Crafting_View_Layout, view: ^Crafting_View, queue: Craft_Queue) -> (toggle: Ui_Id, toggled: bool) {
	label := crafting_view_toggle_label(state, layout)
	toggled = ui_toggle(state, layout.toggle, label, &view.available_only)
	waits := queue.waiting || craft_queue_waits_for_input(queue)
	draw_text_fitted(state, layout.summary, queue_summary_text(queue), UI_BODY_TEXT_SIZE, .Right, waits ? UI_ACCENT_COLOR : UI_DIM_TEXT_COLOR)
	return ui_id(state, label), toggled
}

// "Unlocked only", or in the stacked layout "Unlocked" where the whole
// label is wider than the toggle leaves it.
crafting_view_toggle_label :: proc(state: ^Ui_State, layout: Crafting_View_Layout) -> string {
	label := text("recipes_unlocked_only")
	if layout.stacked && ui_text_width(state, label, UI_BODY_TEXT_SIZE) > toggle_label_width(layout.toggle) {
		return text("crafting_view_unlocked_short")
	}
	return label
}

// The tab's recipes as icon cells in rows of columns, scrolling inside
// the area: the craftable mark at a cell's left edge and the recipe's
// icon (a silhouette while locked), its name on the detail panel, no count.
// A focused cell is the browser's focused recipe. Returns the activated
// recipe or NO_RECIPE.
schematic_grid :: proc(state: ^Ui_State, area: Ui_Rectangle, columns: int, screen_context: Screen_Context, visible: []int, craftable: []bool) -> (activated: int) {
	activated = NO_RECIPE
	if len(visible) == 0 {
		draw_text_fitted(state, {area.x, area.y, area.width, UI_ROW_HEIGHT}, text("recipes_none"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	region, content := scroll_region_begin(state, "schematics_grid", area, slot_rows_height(len(visible), columns) - UI_GAP)
	ui_push_id(state, "schematics_grid")
	for recipe, position in visible {
		cell := slot_grid_rectangle({content.x, content.y}, columns, position)
		id := ui_id(state, "row", recipe)
		interaction := ui_interact(state, id, cell, {}, screen_context.recipe_names[recipe])
		if interaction.focused {
			screen_context.views.recipe_browser.focused_recipe = recipe
		}
		if interaction.activated {
			activated = recipe
		}
		widget_background(state, cell, id, interaction)
		if craftable[recipe] {
			draw_fill(state, {cell.x, cell.y, RECIPE_CRAFTABLE_MARK_WIDTH, cell.height}, UI_ACCENT_COLOR)
		}
		draw_item_icon(state, inset(cell, UI_SLOT_ICON_INSET), recipe_icon(screen_context, recipe))
	}
	ui_pop_id(state)
	scroll_region_end(state, region)
	return activated
}

// A graph step: the tab of the recipe's category, Unlocked only off for a
// locked recipe, and the recipe focused once the grid shows it
// (settle_recipe_focus).
navigate_crafting_view :: proc(view: ^Crafting_View, browser: ^Recipe_Browser, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe: int) {
	view.tab = crafting_tab_index(recipes, recipes.crafting_tabs[recipes.recipes[recipe].category])
	if !recipe_is_available(unlocks, recipe) {
		view.available_only = false
	}
	browser.pending_focus, browser.focused_recipe = recipe, recipe
}

// The tab's position in the view's tab list, 0 for a category that is no
// tab.
crafting_tab_index :: proc(recipes: Recipe_Registry, tab: Recipe_Category) -> int {
	tabs, count := crafting_tab_list(recipes)
	for category, position in tabs[:count] {
		if category == tab {
			return position
		}
	}
	return 0
}

// The half of the focused widget's panel, current while the focus is on
// neither (the touch row, an id of the last screen).
crafting_half_of_focus :: proc(widgets: []Ui_Widget, focus: Ui_Id, inventory_panel, schematics_panel: Ui_Id, current: Crafting_Half) -> Crafting_Half {
	index := widget_index(widgets, focus)
	switch {
	case index < 0:
		return current
	case widgets[index].panel == inventory_panel:
		return .Inventory
	case widgets[index].panel == schematics_panel:
		return .Schematics
	}
	return current
}

// The seam: Right on an inventory widget and Left on a schematics widget,
// when nothing lies ahead in the widget's row or column of its own half,
// go to the other half's widget ahead with the best weighted score
// (focus_score), so they cross instead of wrapping. 0 when the step is
// the default one.
crafting_seam_target :: proc(widgets: []Ui_Widget, focus: Ui_Id, step: Ui_Direction, inventory_panel, schematics_panel: Ui_Id) -> Ui_Id {
	index := widget_index(widgets, focus)
	if index < 0 || !focus_step_allowed(widgets[index], step) {
		return 0
	}
	other: Ui_Id
	switch {
	case step == .Right && widgets[index].panel == inventory_panel:
		other = schematics_panel
	case step == .Left && widgets[index].panel == schematics_panel:
		other = inventory_panel
	case:
		return 0
	}
	if _, found := find_focus_in_line(widgets, index, step); found {
		return 0
	}
	return nearest_widget_ahead(widgets, widgets[index].rectangle, step, other)
}

// The widget of the panel ahead of the rectangle with the least distance
// along the step plus the penalised sideways offset, 0 for none.
nearest_widget_ahead :: proc(widgets: []Ui_Widget, from: Ui_Rectangle, step: Ui_Direction, panel: Ui_Id) -> Ui_Id {
	best, target := max(f32), Ui_Id(0)
	for widget in widgets {
		if widget.panel != panel {
			continue
		}
		along, perpendicular := focus_score(from, widget.rectangle, step)
		if score := along + UI_FOCUS_PERPENDICULAR_PENALTY * perpendicular; along > 0 && score < best {
			best, target = score, widget.id
		}
	}
	return target
}

// The context action clears the queue (on the schematics half, where the
// caller passes it), as Clear queue on the touch row. Cancel last is the
// touch row's alone in the view.
crafting_view_queue_act :: proc(context_action: bool, button: Touch_Button) -> Craft_Queue_Act {
	switch {
	case context_action || button == .Clear_Craft_Queue:
		return .Clear
	case button == .Cancel_Craft:
		return .Cancel_Last
	}
	return .None
}

// The schematics half's glyph bar: on a cell A crafts with its modifier
// pairs, which the bar drops together, and on the toggle and the graph
// rows A selects. Y assigns while the cell's recipe has an item to name
// (assigns, toolbar_assignment), and held opens the toolbar edit mode
// (0279); its hint stands last before Close, so the bar drops it first.
// The context action clears the queue.
crafting_view_glyph_bar :: proc(state: ^Ui_State, on_cell, assigns: bool) {
	hints := make([dynamic]Glyph_Hint, context.temp_allocator)
	if on_cell {
		append(&hints, Glyph_Hint{.Confirm, text("hint_craft")})
		append(&hints, Glyph_Hint{.Five, ""}, Glyph_Hint{.Confirm, text("hint_craft_five")})
		append(&hints, Glyph_Hint{.Most, ""}, Glyph_Hint{.Confirm, text("hint_craft_most")})
	} else {
		append(&hints, Glyph_Hint{.Confirm, text("hint_select")})
	}
	append(&hints, Glyph_Hint{.Context_Action, text("hint_clear_craft_queue")})
	append(&hints, Glyph_Hint{.Tabs, text("hint_tabs")})
	append(&hints, Glyph_Hint{.Info, text(toolbar_hint_key(assigns))})
	append(&hints, Glyph_Hint{.Back, text("hint_close")})
	ui_glyph_bar(state, hints[:])
}

// Y's hint in the crafting view: the assign and the hold where Y names
// something, else the hold alone (0279).
toolbar_hint_key :: proc(assigns: bool) -> string {
	return assigns ? "hint_assign_or_edit_toolbars" : "hint_edit_toolbars"
}

// What Y assigns to the active toolbar's selected slot (0278): on the
// inventory half the slot's item, whatever the hand holds; on the
// schematics half on a cell the recipe's first item output while the
// recipe is available. NO_ITEM for an empty slot, the toggle, a graph
// row, a locked recipe and a recipe without an item output.
toolbar_assignment :: proc(half: Crafting_Half, slot_stack: Item_Stack, on_cell: bool, recipe: int, recipes: Recipe_Registry, available: []bool) -> Item_Id {
	switch half {
	case .Inventory:
		return shown_item(slot_stack)
	case .Schematics:
		if !on_cell || !index_in_range(recipe, len(recipes.recipes)) || recipe >= len(available) || !available[recipe] {
			return NO_ITEM
		}
		outputs := recipes.recipes[recipe].outputs
		return len(outputs) > 0 ? outputs[0].item : NO_ITEM
	}
	return NO_ITEM
}

// The assignment as a Toolbar_Assign_Command on the active toolbar's
// selected slot, and a toast naming the item and the slot (1 to 8).
// Nothing without a command list.
queue_toolbar_assign :: proc(state: ^Ui_State, screen_context: Screen_Context, item: Item_Id) {
	if screen_context.player_commands == nil {
		return
	}
	player := screen_context.player
	queue_player_command(screen_context.player_commands, screen_context.player_index, Toolbar_Assign_Command{player.active_toolbar, player.selected_hotbar_slot, item})
	toast := replace_message_mark(text("toast_toolbar_assigned"), "{name}", item_name(screen_context.items, item))
	ui_toast(state, replace_message_mark(toast, "{value}", fmt.tprint(player.selected_hotbar_slot + 1)))
}
