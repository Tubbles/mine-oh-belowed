package game

// The item transfer interface of doc/logistics.md: the one door into an
// entity's contents for inserters and drills, besides the machine panel.
// Callers never switch on the entity kind themselves.
//
// Chests and the capsule take anything into any slot. A furnace takes
// smeltable items into its input slot first and fuel into its fuel slot,
// and only gives from its output slot. A belt works on one lane of its
// block: it takes one item at a time mid block and gives the item nearest
// the middle of the block from either lane; `slot` is the lane.

// The slot (or lane) an item would go to.
entity_accepts :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, item: Item_Id, lane := Belt_Lane.Left) -> (slot: int, ok: bool) {
	if item == NO_ITEM {
		return -1, false
	}
	if handle.kind == .Belt {
		return int(lane), belt_has_room(entities, handle, lane)
	}
	slots := entity_slots(entities, handle)
	if handle.kind == .Furnace {
		return furnace_accepting_slot(slots, item, content)
	}
	return first_accepting_slot(slots, item, item_stack_size(content.items, item))
}

// What did not fit comes back.
entity_insert :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, stack: Item_Stack, lane := Belt_Lane.Left) -> (leftover: Item_Stack) {
	if stack_is_empty(stack) {
		return stack
	}
	leftover = stack
	if handle.kind == .Belt {
		if belt_insert_item(entities, handle, lane, stack.item) {
			take_from_slot(&leftover, 1)
		}
		return leftover
	}
	slots := entity_slots(entities, handle)
	stack_size := item_stack_size(content.items, stack.item)
	if handle.kind == .Furnace {
		slot, ok := furnace_accepting_slot(slots, stack.item, content)
		if ok {
			leftover.count = u16(fill_slot(&slots[slot], stack.item, int(stack.count), stack_size))
		}
	} else {
		leftover.count = u16(add_to_slots(slots, stack.item, int(stack.count), stack_size))
	}
	if leftover.count == 0 {
		leftover = EMPTY_STACK
	}
	return leftover
}

// Up to maximum_count of one item; filter NO_ITEM takes any item.
entity_extract :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, filter: Item_Id, maximum_count: int) -> Item_Stack {
	if maximum_count <= 0 {
		return EMPTY_STACK
	}
	if handle.kind == .Belt {
		item := belt_extract_item(entities, handle, filter)
		return item == NO_ITEM ? EMPTY_STACK : Item_Stack{item = item, count = 1}
	}
	slots := entity_slots(entities, handle)
	if handle.kind == .Furnace {
		slots = slots[FURNACE_OUTPUT_SLOT:FURNACE_OUTPUT_SLOT + 1]
	}
	for &slot in slots {
		if !stack_is_empty(slot) && (filter == NO_ITEM || slot.item == filter) {
			item := slot.item
			return Item_Stack{item = item, count = u16(take_from_slot(&slot, maximum_count))}
		}
	}
	return EMPTY_STACK
}

slot_has_room_for :: proc(slot: Item_Stack, item: Item_Id, stack_size: u16) -> bool {
	if stack_is_empty(slot) {
		return true
	}
	return slot.item == item && slot.count < stack_size
}

// A partial stack of the item first, then an empty slot, like add_to_slots.
first_accepting_slot :: proc(slots: []Item_Stack, item: Item_Id, stack_size: u16) -> (slot: int, ok: bool) {
	for candidate, index in slots {
		if !stack_is_empty(candidate) && slot_has_room_for(candidate, item, stack_size) {
			return index, true
		}
	}
	for candidate, index in slots {
		if stack_is_empty(candidate) {
			return index, true
		}
	}
	return -1, false
}

furnace_accepting_slot :: proc(slots: []Item_Stack, item: Item_Id, content: Simulation_Content) -> (slot: int, ok: bool) {
	if len(slots) != FURNACE_SLOT_COUNT {
		return -1, false
	}
	stack_size := item_stack_size(content.items, item)
	if slot_accepts(.Smeltable, item, content.items, content.recipes) && slot_has_room_for(slots[FURNACE_INPUT_SLOT], item, stack_size) {
		return FURNACE_INPUT_SLOT, true
	}
	if slot_accepts(.Fuel, item, content.items, content.recipes) && slot_has_room_for(slots[FURNACE_FUEL_SLOT], item, stack_size) {
		return FURNACE_FUEL_SLOT, true
	}
	return -1, false
}
