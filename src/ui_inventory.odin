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
	context_action: bool,
}

// A on a slot first, then X on the focused slot.
apply_inventory_slot_input :: proc(inventory: Inventory, held: Held_Stack, input: Inventory_Slot_Input, items: Item_Registry, ranks: []u16) -> Held_Stack {
	result := held
	if input.activated >= 0 {
		result = apply_slot_primary(inventory, result, input.activated, items)
	}
	if input.context_action {
		result = apply_slot_context(inventory, result, input.focused, items, ranks)
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

// Hook for work item 0011: a machine panel's slots (chest, furnace) go
// into this region next to the player's slots and use the same
// interaction. Nothing to show until machines exist.
machine_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
}

inventory_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player, items := screen_context.player, screen_context.items
	ui_backdrop(state)
	panel := centred_rectangle(ui_safe_area(state), slot_grid_width(INVENTORY_COLUMNS) + 2 * UI_PADDING, inventory_panel_height())
	ui_panel_begin(state, "inventory", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_title"), UI_HEADING_TEXT_SIZE, .Centre)
	machine_slot_region(state, {}, screen_context)
	grid_area := cut_top(&content, slot_grid_height(INVENTORY_ROWS) + UI_GAP)
	grid := ui_slot_grid(state, {grid_area.x, grid_area.y}, "grid", INVENTORY_COLUMNS, inventory_grid(player.inventory), items)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_hotbar"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	hotbar := ui_slot_grid(state, {content.x, content.y}, "hotbar", HOTBAR_SLOT_COUNT, inventory_hotbar(player.inventory), items)
	draw_outline(state, slot_grid_rectangle({content.x, content.y}, HOTBAR_SLOT_COUNT, player.selected_hotbar_slot), UI_ACCENT_COLOR)
	ui_panel_end(state)
	slots := merge_grid_results(grid_result_to_inventory(grid, HOTBAR_SLOT_COUNT), grid_result_to_inventory(hotbar, 0))
	slot_input := Inventory_Slot_Input {
		activated      = slots.activated,
		focused        = slots.focused,
		context_action = state.input.context_action,
	}
	player.held = apply_inventory_slot_input(player.inventory, player.held, slot_input, items, screen_context.item_sort_ranks)
	draw_held_stack(state, player.held.stack, items)
	inventory_glyph_bar(state, player.held.stack, slots.focused >= 0 ? player.inventory.slots[slots.focused] : EMPTY_STACK)
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
	confirm := stack_is_empty(held) ? text("hint_pick_up") : text("hint_place_stack")
	context_action := focused.count >= 2 ? text("hint_split") : text("hint_sort")
	if !stack_is_empty(held) {
		hints := [?]Glyph_Hint{{.Confirm, confirm}, {.Back, text("hint_close")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	hints := [?]Glyph_Hint{{.Confirm, confirm}, {.Context_Action, context_action}, {.Info, text("hint_info")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}
