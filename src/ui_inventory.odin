package game

// The inventory screen: the 36 slot grid and the hotbar as slot grids, with
// the slot interaction from doc/ui.md and the quick move between the
// hotbar and the backpack (quick_transfer.odin). Menu_Drop (the right
// stick click, X on the keyboard) puts the cursor's stack, or the focused
// one with nothing held, onto the ground in front of the player
// (loose_item.odin). It does not pause the simulation.

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

// The id player_slot_region gives the selected hotbar slot, for a
// screen's preferred focus; called inside the same panel.
selected_hotbar_slot_id :: proc(state: ^Ui_State, player: ^Player) -> Ui_Id {
	return ui_hash(ui_id(state, "hotbar"), "slot", player.selected_hotbar_slot)
}

inventory_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player, items := screen_context.player, screen_context.items
	// Q is also Tab_Previous; while it quick moves it does not step the
	// tab strip.
	if state.input.quick_move {
		state.input.tab_previous = false
	}
	ui_backdrop(state)
	// The heading repeats the first tab's name, so it goes where the panel
	// would not fit the area.
	area := ui_panel_area(state)
	tabs_height := f32(UI_ROW_HEIGHT + UI_GAP)
	panel_height := inventory_panel_height()
	shows_heading := panel_height + tabs_height <= area.height
	panel := fitted_panel(area, slot_grid_width(INVENTORY_COLUMNS) + 2 * UI_PADDING, panel_height + (shows_heading ? tabs_height : tabs_height - UI_ROW_HEIGHT))
	ui_panel_begin(state, "inventory", panel)
	ui_prefer_focus(state, selected_hotbar_slot_id(state, player))
	content := inset(panel, UI_PADDING)
	inventory_tabs(state, cut_top(&content, UI_ROW_HEIGHT))
	cut_top(&content, UI_GAP)
	if shows_heading {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_title"), UI_HEADING_TEXT_SIZE, .Centre)
	}
	slots := player_slot_region(state, content, player, items)
	ui_panel_end(state)
	slots.activated = apply_inventory_quick_move_input(state, screen_context, slots)
	slot_input := Inventory_Slot_Input {
		activated      = slots.activated,
		focused        = slots.focused,
		secondary      = state.input.secondary,
		context_action = state.input.context_action,
	}
	player.held = apply_inventory_slot_input(player.inventory, player.held, slot_input, items, screen_context.item_sort_ranks)
	if state.input.drop && screen_context.world != nil {
		drop_player_stack(screen_context.world, screen_context.blocks, player, slots.focused)
	}
	player.held = finish_slot_drag(state, player.inventory, player.held, items)
	draw_held_stack(state, player.held.stack, items)
	inventory_glyph_bar(state, player.held.stack, slots.focused >= 0 ? player.inventory.slots[slots.focused] : EMPTY_STACK, quick_move = true, drop = true)
}

// The quick move between the hotbar and the backpack: R2 or Q on the
// focused slot, or Left Control with a click on a slot, as
// apply_quick_move_input in the machine panel. Its press takes the
// slot's activation, since R2 is Confirm too; returns the activation
// left for the ordinary slot input.
apply_inventory_quick_move_input :: proc(state: ^Ui_State, screen_context: Screen_Context, slots: Slot_Grid_Result) -> (activated: int) {
	input := state.input
	inventory := screen_context.player.inventory
	target, found := inventory_quick_move_target(slots.activated >= 0 ? slots.activated : slots.focused)
	quick_input := Quick_Move_Input {
		panel   = NO_ENTITY,
		pressed = input.quick_move || (input.quick_move_modifier && state.click),
		down    = input.quick_move_down || (input.quick_move_modifier && state.pointer_held),
		seconds = state.frame_seconds,
		found   = found,
		target  = target,
		stack   = found ? inventory.slots[target.slot] : EMPTY_STACK,
	}
	step: Quick_Move_Step
	state.quick_move, step = advance_quick_move(state.quick_move, quick_input)
	apply_inventory_quick_move(inventory, screen_context.items, step)
	return quick_input.pressed ? -1 : slots.activated
}

// The screens of the inventory tab strip, in its order.
@(rodata)
inventory_tab_screens := [3]Screen{.Inventory, .Recipes, .Technologies}

// The strip's tab of a screen, 0 for one outside it.
inventory_tab_index :: proc(screen: Screen) -> int {
	for tab_screen, index in inventory_tab_screens {
		if tab_screen == screen {
			return index
		}
	}
	return 0
}

// The tab strip over the inventory, the recipe browser and the
// technology screen (work item 0094), drawn by all three: the bumpers
// (or a click) step between them, wrapping, by replacing the top screen,
// so Back from any tab returns to what was under the strip. The
// selection follows the top screen. On the keyboard E is both
// Open_Inventory and Tab_Next, and there it closes the strip instead
// (handle_screen_keys).
inventory_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle) {
	labels := [?]string{text("inventory_tab_inventory"), text("inventory_tab_recipes"), text("inventory_tab_technologies")}
	icons := [?]Ui_Icon{.Inventory, .Recipes, .Technologies}
	current := inventory_tab_index(top_screen(state.screens))
	state.selections[ui_id(state, "inventory_tabs")] = current
	input := state.input
	if input.open_inventory {
		state.input.tab_previous, state.input.tab_next = false, false
	}
	tab := ui_tabs(state, rectangle, "inventory_tabs", labels[:], icons[:])
	state.input = input
	if tab != current {
		replace_top_screen(&state.screens, inventory_tab_screens[tab])
	}
}

// The end of a pointer drag on a slot screen (0124), after the slot
// input: on the release frame what is still held (a stack released off
// the slots, the rest of a merge, a swapped stack) goes back, to where
// the dragged stack came from, so a drag onto another item swaps the two
// slots. A drag that holds nothing (its pick up lifted nothing: a filter
// slot, a slot a machine emptied) ends. Records for the next frame
// whether a stack is held and, while dragging, its origin.
finish_slot_drag :: proc(state: ^Ui_State, inventory: Inventory, held: Held_Stack, items: Item_Registry) -> Held_Stack {
	result := held
	if state.slot_drag.released && !stack_is_empty(result.stack) {
		result.origin_slot = state.slot_drag.origin_slot
		result = return_held_stack(inventory, result, items)
	}
	holding := !stack_is_empty(result.stack)
	if state.slot_drag.phase == .Dragging {
		state.slot_drag.origin_slot = result.origin_slot
		if !holding {
			state.slot_drag.phase = .None
		}
	}
	state.slot_drag.holding = holding
	return result
}

// Follows the pointer while it is shown, a finger's a slot height above
// it so the finger does not cover the stack (0124), otherwise the
// focused widget.
held_stack_rectangle :: proc(state: ^Ui_State) -> (rectangle: Ui_Rectangle, found: bool) {
	if state.pointer_source != .None {
		half := f32(UI_SLOT_SIZE / 2)
		rectangle = {state.pointer.x - half, state.pointer.y - half, UI_SLOT_SIZE, UI_SLOT_SIZE}
		if state.pointer_source == .Touch {
			rectangle.y -= UI_SLOT_SIZE
		}
		return rectangle, true
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

// quick_move: the R2 or Q hint on a focused stack. drop: the Drop hint
// on a focused or held stack (the inventory screen).
inventory_glyph_bar :: proc(state: ^Ui_State, held, focused: Item_Stack, quick_move := false, drop := false) {
	if !stack_is_empty(held) {
		hints := make([dynamic]Glyph_Hint, context.temp_allocator)
		append(&hints, Glyph_Hint{.Confirm, text("hint_place_stack")})
		if drop {
			append(&hints, Glyph_Hint{.Drop, text("hint_drop")})
		}
		append(&hints, Glyph_Hint{.Back, text("hint_close")})
		ui_glyph_bar(state, hints[:])
		return
	}
	hints := make([dynamic]Glyph_Hint, context.temp_allocator)
	append(&hints, Glyph_Hint{.Confirm, text("hint_pick_up")})
	if quick_move && !stack_is_empty(focused) {
		append(&hints, Glyph_Hint{.Quick_Move, text("hint_quick_move")})
	}
	if drop && !stack_is_empty(focused) {
		append(&hints, Glyph_Hint{.Drop, text("hint_drop")})
	}
	if focused.count >= 2 {
		append(&hints, Glyph_Hint{.Secondary, text("hint_split")})
	}
	append(&hints, Glyph_Hint{.Context_Action, text("hint_sort")}, Glyph_Hint{.Back, text("hint_close")})
	ui_glyph_bar(state, hints[:])
}
