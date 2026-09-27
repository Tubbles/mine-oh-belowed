package game

// The item transfer interface of doc/logistics.md: the one door into an
// entity's contents for inserters and drills, besides the machine panel.
// Callers never switch on the entity kind themselves.
//
// Chests and the capsule take anything into any slot. A furnace takes
// smeltable items into its input slot first and fuel into its fuel slot,
// and only gives from its output slot. A belt works on one lane of its
// block: it takes one item at a time mid block and gives the item nearest
// the middle of the block from either lane; `slot` is the lane. A burner
// inserter and a burner drill take fuel into their fuel slot and give nothing
// (a drill drops its output itself, drill.odin). A boiler takes fuel into
// its fuel slot and gives nothing. A splitter, a pipe, the other fluid
// machines, an electric drill, poles, switches and lamps have no item
// slots and neither take nor give. An assembler takes each ingredient of
// its recipe into that ingredient's slot only and gives from its output
// slots; a lab takes each science pack into its slot and gives nothing.
//
// Inserters peek with entity_offered_items and entity_takes_item_kind
// before they pick, so they never pick an item the target can never take.

// The slot (or lane) an item would go to.
entity_accepts :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, item: Item_Id, lane := Belt_Lane.Left) -> (slot: int, ok: bool) {
	if item == NO_ITEM {
		return -1, false
	}
	if handle.kind == .Belt {
		return int(lane), belt_has_room(entities, handle, lane)
	}
	slots := entity_slots(entities, handle)
	#partial switch handle.kind {
	case .Furnace:
		return furnace_accepting_slot(slots, item, content)
	case .Inserter, .Drill, .Fluid_Machine:
		return fuel_accepting_slot(slots, item, content.items)
	case .Assembler:
		return fixed_accepting_slot(slots, entity_slot_for_item(entities, content, handle, item), item, content.items)
	case .Lab:
		return fixed_accepting_slot(slots, lab_slot_of(content.machines.lab_packs, item), item, content.items)
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
	if handle.kind != .Chest && handle.kind != .Capsule {
		slot, ok := entity_accepts(entities, content, handle, stack.item)
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
	slots := giving_slots(entities, handle)
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
	if slot_accepts({kind = .Smeltable}, item, content.items, content.recipes) && slot_has_room_for(slots[FURNACE_INPUT_SLOT], item, stack_size) {
		return FURNACE_INPUT_SLOT, true
	}
	if slot_accepts({kind = .Fuel}, item, content.items, content.recipes) && slot_has_room_for(slots[FURNACE_FUEL_SLOT], item, stack_size) {
		return FURNACE_FUEL_SLOT, true
	}
	return -1, false
}

// The slots entity_extract may take from: a furnace's or an assembler's
// outputs, nothing of an inserter, a drill, a boiler or a lab, every slot
// of a chest or the capsule.
giving_slots :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack {
	slots := entity_slots(entities, handle)
	#partial switch handle.kind {
	case .Furnace:
		return slots[FURNACE_OUTPUT_SLOT:FURNACE_OUTPUT_SLOT + 1]
	case .Assembler:
		return assembler_output_slots(pool_get(&entities.assemblers, handle))
	case .Inserter, .Drill, .Fluid_Machine, .Lab:
		return nil
	}
	return slots
}

// The one slot an item may go to (-1 for none), when it has room.
fixed_accepting_slot :: proc(slots: []Item_Stack, slot: int, item: Item_Id, items: Item_Registry) -> (index: int, ok: bool) {
	if slot < 0 || slot >= len(slots) || !slot_has_room_for(slots[slot], item, item_stack_size(items, item)) {
		return -1, false
	}
	return slot, true
}

// An assembler's input slot for the item, or -1.
entity_slot_for_item :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, item: Item_Id) -> int {
	assembler := pool_get(&entities.assemblers, handle)
	if assembler == nil {
		return -1
	}
	return assembler_input_slot_of(assembler^, content.recipes, item)
}

// The single fuel slot of a burner inserter, a drill or a boiler.
fuel_accepting_slot :: proc(slots: []Item_Stack, item: Item_Id, items: Item_Registry) -> (slot: int, ok: bool) {
	if len(slots) != 1 || !item_is_fuel(items, item) || !slot_has_room_for(slots[0], item, item_stack_size(items, item)) {
		return -1, false
	}
	return 0, true
}

// The distinct items entity_extract would give, in the order it takes
// them, matching the filter unless the filter is NO_ITEM. In the temp
// allocator.
entity_offered_items :: proc(entities: ^Entities, handle: Entity_Handle, filter: Item_Id) -> []Item_Id {
	if handle.kind == .Belt {
		return belt_offered_items(entities, handle, filter)
	}
	offered := make([dynamic]Item_Id, context.temp_allocator)
	for slot in giving_slots(entities, handle) {
		if !stack_is_empty(slot) && (filter == NO_ITEM || slot.item == filter) && !slice_contains_item(offered[:], slot.item) {
			append(&offered, slot.item)
		}
	}
	return offered[:]
}

slice_contains_item :: proc(items: []Item_Id, item: Item_Id) -> bool {
	for candidate in items {
		if candidate == item {
			return true
		}
	}
	return false
}

// Whether the entity ever takes the item, full or not: an inserter picks
// an item up only for a target like this and then waits for room.
entity_takes_item_kind :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle, item: Item_Id) -> bool {
	if item == NO_ITEM || !entity_is_alive(entities, handle) {
		return false
	}
	switch handle.kind {
	case .None:
		return false
	case .Chest, .Capsule, .Belt:
		return true
	case .Furnace:
		return slot_accepts({kind = .Smeltable}, item, content.items, content.recipes) || slot_accepts({kind = .Fuel}, item, content.items, content.recipes)
	case .Inserter, .Drill, .Fluid_Machine:
		return len(entity_slots(entities, handle)) == 1 && item_is_fuel(content.items, item)
	case .Assembler:
		return entity_slot_for_item(entities, content, handle, item) >= 0
	case .Lab:
		slot := lab_slot_of(content.machines.lab_packs, item)
		return slot >= 0 && slot < len(entity_slots(entities, handle))
	case .Splitter, .Pipe, .Pole, .Lamp:
		return false
	}
	return false
}
