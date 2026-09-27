package game

// The inventory screen: the 36 slot grid and the hotbar as slot grids, with
// the slot interaction from doc/ui.md. It does not pause the simulation.

INVENTORY_COLUMNS :: 9
INVENTORY_ROWS :: PLAYER_GRID_SLOT_COUNT / INVENTORY_COLUMNS
// The held stack sits this far up and right of the focused slot, so the
// slot under it stays visible.
HELD_STACK_FOCUS_OFFSET :: [2]f32{UI_SLOT_SIZE * 0.4, -UI_SLOT_SIZE * 0.4}

// What one frame of the screen did to the player's slots, as inventory
// indices (-1 for none).
Inventory_Slot_Input :: struct {
	activated:      int,
	focused:        int,
	secondary:      bool,
	context_action: bool,
}

// A on a slot first, then L2 (split) on the focused slot, then X (sort).
apply_inventory_slot_input :: proc(inventory: Inventory, held: Held_Stack, input: Inventory_Slot_Input, items: Item_Registry, ranks: []u16) -> Held_Stack {
	result := held
	if input.activated >= 0 {
		result = apply_slot_primary(inventory, result, input.activated, items)
	}
	if input.secondary {
		result = apply_slot_split(inventory, result, input.focused)
	}
	if input.context_action {
		result = apply_slot_context(inventory, result, items, ranks)
	}
	return result
}

// The hotbar grid shows slots 0 to 7, the main grid the rest.
grid_result_to_inventory :: proc(result: Slot_Grid_Result, first_slot: int) -> Slot_Grid_Result {
	return Slot_Grid_Result {
		activated = result.activated >= 0 ? result.activated + first_slot : -1,
		focused = result.focused >= 0 ? result.focused + first_slot : -1,
	}
}

merge_grid_results :: proc(first, second: Slot_Grid_Result) -> Slot_Grid_Result {
	return Slot_Grid_Result{activated = max(first.activated, second.activated), focused = max(first.focused, second.focused)}
}

inventory_panel_height :: proc() -> f32 {
	return(
		UI_ROW_HEIGHT +
		slot_grid_height(INVENTORY_ROWS) +
		UI_GAP +
		UI_ROW_HEIGHT +
		slot_grid_height(1) +
		2 * UI_PADDING \
	)
}

// The player's grid and hotbar with the hotbar label between them, from
// the top of the area. Results are inventory slot indices.
player_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, player: ^Player, items: Item_Registry) -> Slot_Grid_Result {
	content := area
	grid_area := cut_top(&content, slot_grid_height(INVENTORY_ROWS) + UI_GAP)
	grid := ui_slot_grid(state, {grid_area.x, grid_area.y}, "grid", INVENTORY_COLUMNS, inventory_grid(player.inventory), items)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_hotbar"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	hotbar := ui_slot_grid(state, {content.x, content.y}, "hotbar", HOTBAR_SLOT_COUNT, inventory_hotbar(player.inventory), items)
	draw_outline(state, slot_grid_rectangle({content.x, content.y}, HOTBAR_SLOT_COUNT, player.selected_hotbar_slot), UI_ACCENT_COLOR)
	return merge_grid_results(grid_result_to_inventory(grid, HOTBAR_SLOT_COUNT), grid_result_to_inventory(hotbar, 0))
}

inventory_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player, items := screen_context.player, screen_context.items
	ui_backdrop(state)
	// The heading repeats the first tab's name, so it goes where the panel
	// would not fit the area.
	area := ui_panel_area(state)
	tabs_height := f32(UI_ROW_HEIGHT + UI_GAP)
	shows_heading := inventory_panel_height() + tabs_height <= area.height
	panel := fitted_panel(area, slot_grid_width(INVENTORY_COLUMNS) + 2 * UI_PADDING, inventory_panel_height() + (shows_heading ? tabs_height : tabs_height - UI_ROW_HEIGHT))
	ui_panel_begin(state, "inventory", panel)
	content := inset(panel, UI_PADDING)
	inventory_tabs(state, cut_top(&content, UI_ROW_HEIGHT))
	cut_top(&content, UI_GAP)
	if shows_heading {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_title"), UI_HEADING_TEXT_SIZE, .Centre)
	}
	slots := player_slot_region(state, content, player, items)
	ui_panel_end(state)
	slot_input := Inventory_Slot_Input {
		activated      = slots.activated,
		focused        = slots.focused,
		secondary      = state.input.secondary,
		context_action = state.input.context_action,
	}
	player.held = apply_inventory_slot_input(player.inventory, player.held, slot_input, items, screen_context.item_sort_ranks)
	draw_held_stack(state, player.held.stack, items)
	inventory_glyph_bar(state, player.held.stack, slots.focused >= 0 ? player.inventory.slots[slots.focused] : EMPTY_STACK)
}

// The context tabs: the bumpers (or a click) on the recipes or
// technologies tab open that screen over the inventory, and Back returns
// here. On the
// keyboard E is both Open_Inventory and Tab_Next, and there it closes the
// inventory instead.
inventory_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle) {
	labels := [?]string{text("inventory_tab_inventory"), text("inventory_tab_recipes"), text("inventory_tab_technologies")}
	input := state.input
	if input.open_inventory {
		state.input.tab_previous, state.input.tab_next = false, false
	}
	tab := ui_tabs(state, rectangle, "inventory_tabs", labels[:])
	state.input = input
	if tab != 0 {
		state.selections[ui_id(state, "inventory_tabs")] = 0
		push_screen(&state.screens, tab == 1 ? .Recipes : .Technologies)
	}
}

// Follows the pointer while it is shown, otherwise the focused widget.
held_stack_rectangle :: proc(state: ^Ui_State) -> (rectangle: Ui_Rectangle, found: bool) {
	if state.pointer_source != .None {
		half := f32(UI_SLOT_SIZE / 2)
		return {state.pointer.x - half, state.pointer.y - half, UI_SLOT_SIZE, UI_SLOT_SIZE}, true
	}
	index := widget_index(state.widgets[:], state.focus)
	if index < 0 {
		return {}, false
	}
	rectangle = state.widgets[index].rectangle
	rectangle.x += HELD_STACK_FOCUS_OFFSET.x
	rectangle.y += HELD_STACK_FOCUS_OFFSET.y
	return rectangle, true
}

draw_held_stack :: proc(state: ^Ui_State, stack: Item_Stack, items: Item_Registry) {
	if stack_is_empty(stack) {
		return
	}
	if rectangle, found := held_stack_rectangle(state); found {
		draw_item_stack(state, rectangle, stack, items)
	}
}

inventory_glyph_bar :: proc(state: ^Ui_State, held, focused: Item_Stack) {
	if !stack_is_empty(held) {
		hints := [?]Glyph_Hint{{.Confirm, text("hint_place_stack")}, {.Back, text("hint_close")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	hints := make([dynamic]Glyph_Hint, context.temp_allocator)
	append(&hints, Glyph_Hint{.Confirm, text("hint_pick_up")})
	if focused.count >= 2 {
		append(&hints, Glyph_Hint{.Secondary, text("hint_split")})
	}
	append(&hints, Glyph_Hint{.Context_Action, text("hint_sort")}, Glyph_Hint{.Info, text("hint_info")}, Glyph_Hint{.Back, text("hint_close")})
	ui_glyph_bar(state, hints[:])
}
