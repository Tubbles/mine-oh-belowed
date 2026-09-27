package game

import "core:fmt"

// The machine panel: the player's slots on the left, the machine's on the
// right, in one UI panel so the focus moves across both. The slot
// interaction is the inventory's, plus the slot filters of the machine and
// the distribute gesture.

MACHINE_CHEST_COLUMNS :: 8
MACHINE_BAR_WIDTH :: 160
MACHINE_BAR_HEIGHT :: 20
FURNACE_AREA_WIDTH :: 2 * UI_SLOT_SIZE + MACHINE_BAR_WIDTH + 2 * UI_GAP

// Indices into the machine's slots, -1 for none.
Machine_Slot_Input :: struct {
	activated:      int,
	focused:        int,
	confirm_down:   bool,
	secondary:      bool,
	context_action: bool,
}

machine_slot_filters :: proc(kind: Machine_Kind, slot_count: int) -> []Slot_Filter {
	filters := make([]Slot_Filter, slot_count, context.temp_allocator)
	if kind == .Furnace {
		filters[FURNACE_FUEL_SLOT] = .Fuel
		filters[FURNACE_INPUT_SLOT] = .Smeltable
		filters[FURNACE_OUTPUT_SLOT] = .Output
	}
	return filters
}

// A slot joins the gesture when it takes the held item and has it or nothing.
slot_takes_distribution :: proc(slot: Item_Stack, filter: Slot_Filter, held: Held_Stack, items: Item_Registry, recipes: Recipe_Registry) -> bool {
	if stack_is_empty(held.stack) || !slot_accepts(filter, held.stack.item, items, recipes) {
		return false
	}
	return stack_is_empty(slot) || slot.item == held.stack.item
}

// A with a stack held starts the gesture instead of dropping at once; the
// drop or the spread happens on release (finish_distribute).
apply_machine_slot_input :: proc(gesture: ^Distribute_Gesture, slots: []Item_Stack, filters: []Slot_Filter, held: Held_Stack, input: Machine_Slot_Input, items: Item_Registry, recipes: Recipe_Registry) -> Held_Stack {
	result := held
	if gesture.active {
		if !input.confirm_down {
			result = finish_distribute(gesture^, slots, filters, result, items, recipes)
			gesture^ = {}
		} else if input.focused >= 0 && slot_takes_distribution(slots[input.focused], filters[input.focused], result, items, recipes) {
			gesture^ = gesture_visit(gesture^, input.focused)
		}
		return result
	}
	if input.activated < 0 {
		return result
	}
	if input.confirm_down && slot_takes_distribution(slots[input.activated], filters[input.activated], result, items, recipes) {
		gesture^ = gesture_visit({}, input.activated)
		return result
	}
	return apply_machine_slot_primary(slots, input.activated, filters[input.activated], result, items, recipes)
}

// L2 splits a machine slot's stack onto the cursor, X sorts a chest.
apply_machine_slot_secondary :: proc(slots: []Item_Stack, kind: Machine_Kind, held: Held_Stack, input: Machine_Slot_Input, items: Item_Registry, ranks: []u16) -> Held_Stack {
	result := held
	if input.secondary && input.focused >= 0 && stack_is_empty(result.stack) {
		result = apply_slot_split(Inventory{slots = slots}, result, input.focused)
		if !stack_is_empty(result.stack) {
			result.origin_slot = MACHINE_SLOT_ORIGIN
		}
	}
	if input.context_action && kind == .Chest && stack_is_empty(result.stack) {
		sort_slots(slots, items, ranks)
	}
	return result
}

chest_rows :: proc(slot_count: int) -> int {
	return (slot_count + MACHINE_CHEST_COLUMNS - 1) / MACHINE_CHEST_COLUMNS
}

machine_area_size :: proc(kind: Machine_Kind, slot_count: int) -> [2]f32 {
	switch kind {
	case .Chest, .Capsule:
		return {slot_grid_width(MACHINE_CHEST_COLUMNS), UI_ROW_HEIGHT + slot_grid_height(chest_rows(slot_count))}
	case .Furnace:
		return {FURNACE_AREA_WIDTH, UI_ROW_HEIGHT + 2 * (UI_SLOT_SIZE + UI_GAP) + UI_ROW_HEIGHT}
	}
	return {}
}

// A bar with its label to the right, vertically centred on the row.
machine_bar :: proc(state: ^Ui_State, row: Ui_Rectangle, fraction: f32) {
	bar := Ui_Rectangle{row.x, row.y + (row.height - MACHINE_BAR_HEIGHT) / 2, MACHINE_BAR_WIDTH, MACHINE_BAR_HEIGHT}
	ui_progress_bar(state, bar, fraction)
}

machine_slot :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, index: int, slots: []Item_Stack, items: Item_Registry, result: ^Slot_Grid_Result) {
	interaction := ui_item_slot(state, rectangle, ui_id(state, "slot", index), slots[index], items)
	if interaction.activated {
		result.activated = index
	}
	if interaction.focused {
		result.focused = index
	}
}

// Input, progress, output on the first row; fuel and the burn bar on the
// second; the state below.
furnace_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, furnace: Furnace, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	slots, items := furnace.slots, screen_context.items
	machine := screen_context.machines.machines[furnace.machine]
	recipes := screen_context.recipes
	content := area
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_INPUT_SLOT, slots[:], items, &result)
	progress_row := Ui_Rectangle{first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}
	machine_bar(state, progress_row, furnace_progress_fraction(furnace, machine, recipes, screen_context.tick_rate))
	output := Ui_Rectangle{progress_row.x + MACHINE_BAR_WIDTH + UI_GAP, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}
	machine_slot(state, output, FURNACE_OUTPUT_SLOT, slots[:], items, &result)
	second := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	machine_slot(state, {second.x, second.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_FUEL_SLOT, slots[:], items, &result)
	machine_bar(state, {second.x + UI_SLOT_SIZE + UI_GAP, second.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, furnace_burn_fraction(furnace))
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(furnace_state_keys[furnace.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	return result
}

// The machine's name and slots. Results are indices into the machine's slots.
machine_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, handle: Entity_Handle, slots: []Item_Stack, screen_context: Screen_Context) -> Slot_Grid_Result {
	content := area
	common := entity_common(&screen_context.world.entities, handle)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), machine_name(screen_context.machines, common.machine), UI_HEADING_TEXT_SIZE, .Left)
	ui_push_id(state, "machine_slots")
	defer ui_pop_id(state)
	if handle.kind == .Furnace {
		return furnace_slot_region(state, content, pool_get(&screen_context.world.entities.furnaces, handle)^, screen_context)
	}
	return ui_slot_grid(state, {content.x, content.y}, "chest", MACHINE_CHEST_COLUMNS, slots, screen_context.items)
}

machine_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player, items := screen_context.player, screen_context.items
	handle := player.open_machine
	common := entity_common(&screen_context.world.entities, handle)
	if common == nil {
		pop_screen(&state.screens)
		return
	}
	machine := screen_context.machines.machines[common.machine]
	slots := entity_slots(&screen_context.world.entities, handle)
	ui_backdrop(state)
	machine_size := machine_area_size(machine.kind, len(slots))
	player_width := slot_grid_width(INVENTORY_COLUMNS)
	height := max(inventory_panel_height(), machine_size.y + 2 * UI_PADDING)
	panel := centred_rectangle(ui_safe_area(state), player_width + machine_size.x + 4 * UI_PADDING, height)
	ui_panel_begin(state, "machine", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_title"), UI_HEADING_TEXT_SIZE, .Left)
	player_slots := player_slot_region(state, {content.x, content.y, player_width, content.height}, player, items)
	machine_area := Ui_Rectangle{panel.x + UI_PADDING + player_width + 2 * UI_PADDING, panel.y + UI_PADDING, machine_size.x, machine_size.y}
	machine_slots := machine_slot_region(state, machine_area, handle, slots, screen_context)
	ui_panel_end(state)
	apply_machine_screen_input(state, screen_context, machine.kind, slots, player_slots, machine_slots)
	draw_held_stack(state, player.held.stack, items)
	machine_glyph_bar(state, player.held.stack, focused_stack(player.inventory.slots, player_slots.focused, slots, machine_slots.focused))
}

apply_machine_screen_input :: proc(state: ^Ui_State, screen_context: Screen_Context, kind: Machine_Kind, slots: []Item_Stack, player_slots, machine_slots: Slot_Grid_Result) {
	player, items := screen_context.player, screen_context.items
	recipes := screen_context.recipes
	input := state.input
	if !state.distribute.active {
		player_input := Inventory_Slot_Input {
			activated      = player_slots.activated,
			focused        = player_slots.focused,
			secondary      = input.secondary,
			context_action = input.context_action && machine_slots.focused < 0,
		}
		player.held = apply_inventory_slot_input(player.inventory, player.held, player_input, items, screen_context.item_sort_ranks)
	}
	machine_input := Machine_Slot_Input {
		activated      = machine_slots.activated,
		focused        = machine_slots.focused,
		confirm_down   = input.confirm_down || state.pointer_held,
		secondary      = input.secondary,
		context_action = input.context_action,
	}
	filters := machine_slot_filters(kind, len(slots))
	player.held = apply_machine_slot_input(&state.distribute, slots, filters, player.held, machine_input, items, recipes)
	player.held = apply_machine_slot_secondary(slots, kind, player.held, machine_input, items, screen_context.item_sort_ranks)
}

focused_stack :: proc(player_slots: []Item_Stack, player_focused: int, machine_slots: []Item_Stack, machine_focused: int) -> Item_Stack {
	switch {
	case player_focused >= 0:
		return player_slots[player_focused]
	case machine_focused >= 0:
		return machine_slots[machine_focused]
	}
	return EMPTY_STACK
}

machine_glyph_bar :: proc(state: ^Ui_State, held, focused: Item_Stack) {
	if !stack_is_empty(held) {
		hints := [?]Glyph_Hint{{.Confirm, text("hint_place_or_spread")}, {.Back, text("hint_close")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	inventory_glyph_bar(state, held, focused)
}

// The name and state of an entity for the HUD, "" when it has none.
entity_status_text :: proc(world: ^World, machines: Machine_Registry, handle: Entity_Handle) -> string {
	common := entity_common(&world.entities, handle)
	if common == nil {
		return ""
	}
	name := machine_name(machines, common.machine)
	if handle.kind != .Furnace {
		return name
	}
	furnace := pool_get(&world.entities.furnaces, handle)
	return fmt.tprintf("%s  %s", name, text(furnace_state_keys[furnace.state]))
}
