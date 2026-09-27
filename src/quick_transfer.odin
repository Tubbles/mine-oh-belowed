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
// does not fit stays where it was. The panel edits the world's slots
// directly between ticks, like every other slot edit of the panel.

QUICK_MOVE_REPEAT_SECONDS :: 0.5
// Narrower than this, the transfer buttons stack in rows.
TRANSFER_BUTTON_MINIMUM_WIDTH :: 150

Quick_Move_Side :: enum u8 {
	Inventory,
	Machine,
}

// The slot a quick move acts on: an inventory index or a machine slot.
Quick_Move_Target :: struct {
	side: Quick_Move_Side,
	slot: int,
}

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

Quick_Move_Kind :: enum u8 {
	None,
	Stack,
	All,
}

Quick_Move_Step :: struct {
	kind:   Quick_Move_Kind,
	target: Quick_Move_Target,
	item:   Item_Id,
}

Transfer_Button :: enum u8 {
	None,
	Take_All,
	Store_All,
	Fill,
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

// The inserter's hand into the inventory; what does not fit stays in the
// hand.
take_inserter_hand :: proc(entities: ^Entities, items: Item_Registry, handle: Entity_Handle, inventory: Inventory) {
	if inserter := pool_get(&entities.inserters, handle); inserter != nil {
		take_slot(inventory, items, &inserter.held)
	}
}

slot_indices_contain :: proc(indices: []int, index: int) -> bool {
	for candidate in indices {
		if candidate == index {
			return true
		}
	}
	return false
}

// Into the entity the way an inserter puts it: a chest or the capsule
// takes the stack at once, any other entity one item at a time while
// entity_accepts routes the item to a slot (one of allowed_slots when
// given), so the insertion limits hold. What did not fit comes back.
insert_as_inserter :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, stack: Item_Stack, allowed_slots: []int = nil) -> Item_Stack {
	if allowed_slots == nil && (handle.kind == .Chest || handle.kind == .Capsule) {
		return entity_insert(entities, content, handle, stack)
	}
	leftover := stack
	for !stack_is_empty(leftover) {
		slot, ok := entity_accepts(entities, content, handle, leftover.item)
		if !ok || (allowed_slots != nil && !slot_indices_contain(allowed_slots, slot)) {
			break
		}
		if !stack_is_empty(entity_insert(entities, content, handle, Item_Stack{leftover.item, 1})) {
			break
		}
		take_from_slot(&leftover, 1)
	}
	return leftover
}

// An inventory slot's stack into the entity; the rest stays in the slot.
store_slot :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, slot: ^Item_Stack, allowed_slots: []int = nil) {
	if !stack_is_empty(slot^) {
		slot^ = insert_as_inserter(entities, content, handle, slot^, allowed_slots)
	}
}

// A machine slot's stack into the inventory; the rest stays in the slot.
take_slot :: proc(inventory: Inventory, items: Item_Registry, slot: ^Item_Stack) {
	if stack_is_empty(slot^) {
		return
	}
	slot.count = u16(inventory_add(inventory, items, slot.item, int(slot.count)))
	if slot.count == 0 {
		slot^ = EMPTY_STACK
	}
}

// Inventory indices, the main grid before the hotbar, so the hotbar is
// the last to empty. In the temp allocator.
inventory_order_hotbar_last :: proc(inventory: Inventory) -> []int {
	order := make([dynamic]int, 0, len(inventory.slots), context.temp_allocator)
	hotbar := len(inventory_hotbar(inventory))
	for index in hotbar ..< len(inventory.slots) {
		append(&order, index)
	}
	for index in 0 ..< hotbar {
		append(&order, index)
	}
	return order[:]
}

slots_hold_item :: proc(slots: []Item_Stack, item: Item_Id) -> bool {
	for slot in slots {
		if !stack_is_empty(slot) && slot.item == item {
			return true
		}
	}
	return false
}

// Every inventory stack of the item into the entity, the hotbar last.
store_item :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory, item: Item_Id) {
	for index in inventory_order_hotbar_last(inventory) {
		if inventory.slots[index].item == item {
			store_slot(entities, content, handle, &inventory.slots[index])
		}
	}
}

// Every stack of the item in the slots into the inventory.
take_item :: proc(inventory: Inventory, items: Item_Registry, slots: []Item_Stack, item: Item_Id) {
	for &slot in slots {
		if slot.item == item {
			take_slot(inventory, items, &slot)
		}
	}
}

apply_quick_move :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory, step: Quick_Move_Step) {
	slots := entity_slots(entities, handle)
	switch step.kind {
	case .None:
	case .Stack:
		if step.target.side == .Machine {
			take_slot(inventory, content.items, &slots[step.target.slot])
		} else if len(slots) > 0 {
			store_slot(entities, content, handle, &inventory.slots[step.target.slot])
		}
	case .All:
		if step.target.side == .Machine {
			take_item(inventory, content.items, slots, step.item)
		} else if len(slots) > 0 {
			store_item(entities, content, handle, inventory, step.item)
		}
	}
}

// Store all: stacks of items the container holds first, then the rest,
// the main grid before the hotbar. In the temp allocator.
store_all_order :: proc(inventory: Inventory, container: []Item_Stack) -> []int {
	order := make([dynamic]int, 0, len(inventory.slots), context.temp_allocator)
	hotbar := len(inventory_hotbar(inventory))
	parts := [2][2]int{{hotbar, len(inventory.slots)}, {0, hotbar}}
	held_first := [2]bool{true, false}
	for part in parts {
		for held in held_first {
			for index in part[0] ..< part[1] {
				slot := inventory.slots[index]
				if !stack_is_empty(slot) && slots_hold_item(container, slot.item) == held {
					append(&order, index)
				}
			}
		}
	}
	return order[:]
}

store_all :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory) {
	for index in store_all_order(inventory, entity_slots(entities, handle)) {
		store_slot(entities, content, handle, &inventory.slots[index])
	}
}

// Take all: every slot entity_extract may take from (all of a chest's).
take_all :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory) {
	for &slot in giving_slots(entities, handle) {
		take_slot(inventory, content.items, &slot)
	}
}

// The slots Fill fills: the fuel slot, or a lab's pack slots. In the
// temp allocator.
fill_slots :: proc(entities: ^Entities, handle: Entity_Handle) -> []int {
	result := make([dynamic]int, context.temp_allocator)
	slot_count := len(entity_slots(entities, handle))
	#partial switch handle.kind {
	case .Furnace:
		append(&result, FURNACE_FUEL_SLOT)
	case .Drill, .Inserter, .Fluid_Machine:
		// A burner's single slot is its fuel slot (fuel_accepting_slot).
		if slot_count == 1 {
			append(&result, 0)
		}
	case .Assembler:
		if pool_get(&entities.assemblers, handle).fuel_count > 0 {
			append(&result, 0)
		}
	case .Lab:
		for index in 0 ..< slot_count {
			append(&result, index)
		}
	}
	return result[:]
}

// Fill: from the inventory, the hotbar last, into the fill slots up to
// the insertion limit.
fill_from_inventory :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory) {
	targets := fill_slots(entities, handle)
	if len(targets) == 0 {
		return
	}
	for index in inventory_order_hotbar_last(inventory) {
		store_slot(entities, content, handle, &inventory.slots[index], targets)
	}
}

apply_transfer_button :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory, button: Transfer_Button) {
	switch button {
	case .None:
	case .Take_All:
		take_all(entities, content, handle, inventory)
	case .Store_All:
		store_all(entities, content, handle, inventory)
	case .Fill:
		fill_from_inventory(entities, content, handle, inventory)
	}
}

// The transfer buttons a machine's panel shows.
machine_transfer_buttons :: proc(machine: Machine) -> Transfer_Buttons {
	#partial switch machine.kind {
	case .Chest, .Capsule:
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
			row = choice_row(content)
		}
		if ui_button(state, column(row, columns, index % columns, UI_GAP), text(transfer_button_keys[button])) {
			pressed = button
		}
		index += 1
	}
	return pressed
}
