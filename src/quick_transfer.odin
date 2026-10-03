package game

// Quick transfer in the machine panel (work item 0078). A quick move (R2,
// Q, or Left Control with a click) moves the focused stack to the other
// side: from the inventory into the machine the way an inserter would put
// it (entity_accepts routes fuel to the fuel slot, ore to the input, and
// the insertion limits hold), from a machine slot into the inventory with
// inventory_add, and from an inserter's hand slot into the inventory
// (work item 0079). A second press on the same side within
// QUICK_MOVE_REPEAT_SECONDS, or holding the action that long, moves every
// stack of that item on that side. The transfer buttons: Take all (a
// chest's or the capsule's slots, the output slots of a furnace or a
// crafting machine), Store all (every inventory stack a chest or the
// capsule takes, stacks of items it already holds first, the hotbar last)
// and Fill (the fuel slot or a lab's pack slots from the inventory). What
// does not fit stays where it was. This file holds the panel's side: the
// state machine and the buttons queue slot commands
// (player_command_slots.odin) that the next tick applies through the
// verbs of inventory_transfer.odin.

QUICK_MOVE_REPEAT_SECONDS :: 0.5
// Narrower than this, the transfer buttons stack in rows.
TRANSFER_BUTTON_MINIMUM_WIDTH :: 150

// The last quick move, for the second press and the hold.
Quick_Move_State :: struct {
	active:    bool,
	panel:     Entity_Handle,
	item:      Item_Id,
	side:      Quick_Move_Side,
	// Since the press.
	seconds:   f32,
	// The action has been held since the press.
	holding:   bool,
	moved_all: bool,
}

// One frame of quick move input in a panel.
Quick_Move_Input :: struct {
	panel:   Entity_Handle,
	pressed: bool,
	down:    bool,
	seconds: f32,
	found:   bool,
	target:  Quick_Move_Target,
	// The stack in the target slot.
	stack:   Item_Stack,
}

Transfer_Buttons :: bit_set[Transfer_Button]

@(rodata)
transfer_button_keys := [Transfer_Button]string {
	.None      = "",
	.Take_All  = "transfer_take_all",
	.Store_All = "transfer_store_all",
	.Fill      = "transfer_fill",
}

// The second press or the hold continues the last move while the panel
// and the side are the same.
quick_move_continues :: proc(quick: Quick_Move_State, panel: Entity_Handle) -> bool {
	return quick.active && !quick.moved_all && quick.panel == panel && quick.seconds <= QUICK_MOVE_REPEAT_SECONDS
}

advance_quick_move :: proc(quick: Quick_Move_State, input: Quick_Move_Input) -> (Quick_Move_State, Quick_Move_Step) {
	result := quick
	result.seconds += input.seconds
	result.holding = result.holding && input.down
	if input.pressed && input.found {
		if quick_move_continues(result, input.panel) && input.target.side == result.side {
			result.moved_all, result.holding = true, false
			return result, {kind = .All, target = {side = result.side, slot = -1}, item = result.item}
		}
		if stack_is_empty(input.stack) {
			return result, {}
		}
		result = {active = true, panel = input.panel, item = input.stack.item, side = input.target.side, holding = true}
		return result, {kind = .Stack, target = input.target, item = input.stack.item}
	}
	if result.holding && result.active && !result.moved_all && result.panel == input.panel && result.seconds >= QUICK_MOVE_REPEAT_SECONDS {
		result.moved_all = true
		return result, {kind = .All, target = {side = result.side, slot = -1}, item = result.item}
	}
	return result, {}
}

// The clicked or confirmed slot first, else the focused one.
quick_move_target :: proc(player_slots, machine_slots: Slot_Grid_Result) -> (target: Quick_Move_Target, found: bool) {
	switch {
	case player_slots.activated >= 0:
		return {.Inventory, player_slots.activated}, true
	case machine_slots.activated >= 0:
		return {.Machine, machine_slots.activated}, true
	case player_slots.focused >= 0:
		return {.Inventory, player_slots.focused}, true
	case machine_slots.focused >= 0:
		return {.Machine, machine_slots.focused}, true
	}
	return {}, false
}

// The hand slot of an inserter (work item 0079) is not one of the
// machine's slots: the quick move aims at it when it was clicked or
// confirmed, or when it holds the focus and no slot was found.
quick_move_targets_hand :: proc(machine_slots: Machine_Slot_Result, slot_found: bool) -> bool {
	return machine_slots.hand_activated || (machine_slots.hand_focused && !slot_found)
}

// The inventory screen's quick move (work item 0090) runs the same state
// machine with NO_ENTITY as its panel: a stack goes from the hotbar to
// the backpack or back, partial stacks of the item first, then empty
// slots; what does not fit stays in the slot.

// The focused inventory index as a quick move target, -1 for none.
inventory_quick_move_target :: proc(focused: int) -> (target: Quick_Move_Target, found: bool) {
	if focused < 0 {
		return {}, false
	}
	return {focused < HOTBAR_SLOT_COUNT ? .Hotbar : .Backpack, focused}, true
}

// The transfer buttons a machine's panel shows.
machine_transfer_buttons :: proc(machine: Machine) -> Transfer_Buttons {
	#partial switch machine.kind {
	case .Chest, .Capsule, .Locker:
		return {.Take_All, .Store_All}
	case .Furnace:
		return {.Take_All, .Fill}
	case .Crafting_Machine:
		return machine.slot_count > 0 ? {.Take_All, .Fill} : {.Take_All}
	case .Lab, .Boiler, .Combustion_Generator:
		return {.Fill}
	case .Drill, .Inserter:
		return machine.slot_count > 0 ? {.Fill} : {}
	}
	return {}
}

transfer_button_columns :: proc(buttons: Transfer_Buttons, width: f32) -> int {
	return clamp(int(width / TRANSFER_BUTTON_MINIMUM_WIDTH), 1, max(card(buttons), 1))
}

// The height of the transfer rows at a width, 0 without buttons.
transfer_rows_height :: proc(machine: Machine, width: f32) -> f32 {
	buttons := machine_transfer_buttons(machine)
	if buttons == {} {
		return 0
	}
	columns := transfer_button_columns(buttons, width)
	rows := (card(buttons) + columns - 1) / columns
	return f32(rows) * (UI_ROW_HEIGHT + UI_GAP)
}

// The machine's transfer buttons, side by side in rows taken off the top
// of the content; the one activated this frame, .None otherwise.
transfer_button_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, machine: Machine) -> Transfer_Button {
	buttons := machine_transfer_buttons(machine)
	if buttons == {} {
		return .None
	}
	columns := transfer_button_columns(buttons, content.width)
	pressed := Transfer_Button.None
	row: Ui_Rectangle
	index := 0
	for button in buttons {
		if index % columns == 0 {
			row = cut_row(content)
		}
		if ui_button(state, column_rectangle(row, columns, index % columns, UI_GAP), text(transfer_button_keys[button])) {
			pressed = button
		}
		index += 1
	}
	return pressed
}

// The touch row's transfers (0125) move stacks from the active grid to
// the grid the screen pairs it with: in the inventory screen the hotbar
// and the main grid into each other, in a machine panel the hotbar and
// the main grid into the machine and the machine into the main grid,
// never into the hotbar.
Slot_Screen_Kind :: enum u8 {
	Inventory,
	Machine,
}

transfer_target_grid :: proc(screen: Slot_Screen_Kind, source: Slot_Grid_Kind) -> Slot_Grid_Kind {
	switch screen {
	case .Inventory:
		#partial switch source {
		case .Hotbar:
			return .Main
		case .Main:
			return .Hotbar
		}
	case .Machine:
		#partial switch source {
		case .Hotbar, .Main:
			return .Machine
		case .Machine:
			return .Main
		}
	}
	return .None
}
