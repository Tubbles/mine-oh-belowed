package game

// The simulation's side of the slot transfers (work items 0078, 0079,
// 0090, 0125): the quick move steps, the transfer buttons, the touch
// row's grid transfers and the inserter's hand, applied by the slot
// commands at the start of a tick (player_command_slots.odin). The panel
// state machines that produce them stay in quick_transfer.odin.

Quick_Move_Side :: enum u8 {
	Inventory,
	Machine,
}

// The slot a quick move acts on: an inventory index or a machine slot.
Quick_Move_Target :: struct {
	side: Quick_Move_Side,
	slot: int,
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

slots_hold_item :: proc(slots: []Item_Stack, item: Item_Id) -> bool {
	for slot in slots {
		if !stack_is_empty(slot) && slot.item == item {
			return true
		}
	}
	return false
}

// Every inventory stack of the item into the entity, in slot order.
store_item :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory, item: Item_Id) {
	for &slot in inventory.slots {
		if slot.item == item {
			store_slot(entities, content, handle, &slot)
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
// Partial stacks of the item first, then empty slots; the rest stays in
// the slot.
move_stack_into_slots :: proc(destination: []Item_Stack, items: Item_Registry, slot: ^Item_Stack) {
	if stack_is_empty(slot^) {
		return
	}
	slot.count = u16(add_to_slots(destination, slot.item, int(slot.count), item_stack_size(items, slot.item)))
	if slot.count == 0 {
		slot^ = EMPTY_STACK
	}
}

// Store all: stacks of items the container holds first, then the rest,
// each in slot order. In the temp allocator.
store_all_order :: proc(inventory: Inventory, container: []Item_Stack) -> []int {
	order := make([dynamic]int, 0, len(inventory.slots), context.temp_allocator)
	for held in ([2]bool{true, false}) {
		for slot, index in inventory.slots {
			if !stack_is_empty(slot) && slots_hold_item(container, slot.item) == held {
				append(&order, index)
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

// Fill: from the inventory in slot order into the fill slots up to the
// insertion limit.
fill_from_inventory :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory) {
	targets := fill_slots(entities, handle)
	if len(targets) == 0 {
		return
	}
	for &slot in inventory.slots {
		store_slot(entities, content, handle, &slot, targets)
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
// Every stack of the source, or with of_type only the item's stacks.
Grid_Transfer :: struct {
	source:  Slot_Grid_Kind,
	target:  Slot_Grid_Kind,
	of_type: bool,
	item:    Item_Id,
}

// The grid's slots: the player's whole inventory, or the open entity's.
grid_slots :: proc(inventory: Inventory, machine_slots: []Item_Stack, grid: Slot_Grid_Kind) -> []Item_Stack {
	switch grid {
	case .None:
	case .Main:
		return inventory.slots
	case .Machine:
		return machine_slots
	}
	return nil
}

// Into the machine the way the quick move stores (store_slot), and out
// of the machine into the inventory by partial stacks first, then empty
// slots. What does not fit stays where it was.
apply_grid_transfer :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, inventory: Inventory, transfer: Grid_Transfer) {
	machine_slots: []Item_Stack
	if handle != NO_ENTITY {
		machine_slots = entity_slots(entities, handle)
	}
	if transfer.target == .None || (transfer.target == .Machine && len(machine_slots) == 0) {
		return
	}
	destination := grid_slots(inventory, machine_slots, transfer.target)
	for &slot in grid_slots(inventory, machine_slots, transfer.source) {
		if stack_is_empty(slot) || (transfer.of_type && slot.item != transfer.item) {
			continue
		}
		if transfer.target == .Machine {
			store_slot(entities, content, handle, &slot)
		} else {
			move_stack_into_slots(destination, content.items, &slot)
		}
	}
}

machine_slot_filters :: proc(kind: Machine_Kind, slot_count: int) -> []Slot_Filter {
	filters := make([]Slot_Filter, slot_count, context.temp_allocator)
	#partial switch kind {
	case .Furnace:
		filters[FURNACE_FUEL_SLOT] = {kind = .Fuel}
		filters[FURNACE_INPUT_SLOT] = {kind = .Smeltable}
		filters[FURNACE_OUTPUT_SLOT] = {kind = .Output}
		filters[FURNACE_BYPRODUCT_SLOT] = {kind = .Output}
	case .Inserter, .Drill, .Boiler, .Combustion_Generator:
		for &filter in filters {
			filter = {kind = .Fuel}
		}
	}
	return filters
}

// The slot filters of every machine slot of the entity: the recipe's for
// an assembler, the packs for a lab, the stage's for a launch pad, the
// kind's otherwise. In the temp allocator.
entity_slot_filters :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle) -> []Slot_Filter {
	slot_count := len(entity_slots(entities, handle))
	#partial switch handle.kind {
	case .Assembler:
		assembler := pool_get(&entities.assemblers, handle)
		return assembler_slot_filters(assembler^, content.machines.machines[assembler.machine], content.recipes)
	case .Lab:
		return lab_slot_filters(content.machines.lab_packs, slot_count)
	case .Launch_Pad:
		pad := pool_get(&entities.launch_pads, handle)
		return launch_pad_slot_filters(pad^, content.machines.machines[pad.machine])
	}
	common := entity_common(entities, handle)
	if common == nil {
		return nil
	}
	return machine_slot_filters(content.machines.machines[common.machine].kind, slot_count)
}

// A or a drag with nothing on the cursor lifts the inserter's hand onto
// it. The hand takes nothing in: a stack on the cursor stays there.
inserter_hand_after_input :: proc(hand: Item_Stack, held: Held_Stack, activated: bool) -> (Item_Stack, Held_Stack) {
	if !activated || !stack_is_empty(held.stack) || stack_is_empty(hand) {
		return hand, held
	}
	return EMPTY_STACK, Held_Stack{stack = hand, origin_slot = MACHINE_SLOT_ORIGIN}
}
