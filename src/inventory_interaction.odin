package game

// The gamepad slot interaction from doc/ui.md as pure procedures over the
// inventory and the stack on the cursor. The pointer drives the same
// procedures with clicks. Slot indices are into Inventory.slots.

// origin_slot is where the stack was picked up, so closing the screen can
// put it back there.
Held_Stack :: struct {
	stack:       Item_Stack,
	origin_slot: int,
}

EMPTY_HELD_STACK :: Held_Stack {
	stack = EMPTY_STACK,
}

// A (or a click): pick up the slot's stack, drop the held stack onto an
// empty slot, merge it onto the same item (the rest stays held), or swap
// it with a different item.
apply_slot_primary :: proc(inventory: Inventory, held: Held_Stack, index: int, registry: Item_Registry) -> Held_Stack {
	slot := &inventory.slots[index]
	if stack_is_empty(held.stack) {
		if stack_is_empty(slot^) {
			return held
		}
		picked := Held_Stack{stack = slot^, origin_slot = index}
		slot^ = EMPTY_STACK
		return picked
	}
	if !stack_is_empty(slot^) && slot.item != held.stack.item {
		swapped := Held_Stack{stack = slot^, origin_slot = index}
		slot^ = held.stack
		return swapped
	}
	result := held
	left := fill_slot(slot, held.stack.item, int(held.stack.count), item_stack_size(registry, held.stack.item))
	result.stack.count = u16(left)
	if left == 0 {
		result.stack = EMPTY_STACK
	}
	return result
}

// L2 (Menu_Secondary) splits the slot's stack in half onto the cursor.
apply_slot_split :: proc(inventory: Inventory, held: Held_Stack, index: int) -> Held_Stack {
	if index < 0 || !stack_is_empty(held.stack) || stack_is_empty(inventory.slots[index]) {
		return held
	}
	kept, taken := split_stack(inventory.slots[index])
	inventory.slots[index] = kept
	return Held_Stack{stack = taken, origin_slot = index}
}

// X is the context action: it sorts the grid (the hotbar keeps its order).
// Holding a stack, it does nothing.
apply_slot_context :: proc(inventory: Inventory, held: Held_Stack, registry: Item_Registry, ranks: []u16) -> Held_Stack {
	if stack_is_empty(held.stack) {
		sort_slots(inventory_grid(inventory), registry, ranks)
	}
	return held
}

// Back to the origin slot when it is free or holds the same item, then
// wherever it fits. Whatever does not fit stays held.
return_held_stack :: proc(inventory: Inventory, held: Held_Stack, registry: Item_Registry) -> Held_Stack {
	if stack_is_empty(held.stack) {
		return held
	}
	stack_size := item_stack_size(registry, held.stack.item)
	remaining := int(held.stack.count)
	if held.origin_slot >= 0 && held.origin_slot < len(inventory.slots) {
		remaining = fill_slot(&inventory.slots[held.origin_slot], held.stack.item, remaining, stack_size)
	}
	remaining = add_to_slots(inventory.slots, held.stack.item, remaining, stack_size)
	if remaining == 0 {
		return EMPTY_HELD_STACK
	}
	result := held
	result.stack.count = u16(remaining)
	return result
}

// Spreads the held stack evenly over the targets, in order: each gets
// count / targets, the first count % targets one more. A target that
// holds another item or is full keeps its share on the cursor.
distribute_held_stack :: proc(held: Held_Stack, targets: []^Item_Stack, registry: Item_Registry) -> Held_Stack {
	if stack_is_empty(held.stack) || len(targets) == 0 {
		return held
	}
	total := int(held.stack.count)
	share, extra := total / len(targets), total % len(targets)
	stack_size := item_stack_size(registry, held.stack.item)
	remaining := total
	for target, index in targets {
		wanted := share + (index < extra ? 1 : 0)
		if wanted > 0 {
			remaining -= wanted - fill_slot(target, held.stack.item, wanted, stack_size)
		}
	}
	result := held
	result.stack.count = u16(remaining)
	if remaining == 0 {
		result.stack = EMPTY_STACK
	}
	return result
}

// Where a stack taken from a machine slot goes back to when the panel
// closes: not a player slot, so anywhere in the inventory.
MACHINE_SLOT_ORIGIN :: -1
DISTRIBUTE_MAXIMUM_SLOTS :: MAXIMUM_CHEST_SLOTS

// The distribute gesture from doc/ui.md: A (or a click) on a machine slot
// while holding a stack starts it, moving the focus or the pointer with A
// held visits more slots, and releasing spreads the stack over them. A
// single visited slot gets the ordinary drop instead.
Distribute_Gesture :: struct {
	active:  bool,
	visited: [DISTRIBUTE_MAXIMUM_SLOTS]int,
	count:   int,
}

gesture_has_visited :: proc(gesture: Distribute_Gesture, index: int) -> bool {
	visited := gesture.visited
	for slot in visited[:gesture.count] {
		if slot == index {
			return true
		}
	}
	return false
}

gesture_visit :: proc(gesture: Distribute_Gesture, index: int) -> Distribute_Gesture {
	if index < 0 || gesture.count == DISTRIBUTE_MAXIMUM_SLOTS || gesture_has_visited(gesture, index) {
		return gesture
	}
	result := gesture
	result.active = true
	result.visited[result.count] = index
	result.count += 1
	return result
}

// What a machine slot takes from the player.
Slot_Filter :: enum u8 {
	Any,
	Fuel,
	Smeltable,
	// Output slots only give.
	Output,
}

slot_accepts :: proc(filter: Slot_Filter, item: Item_Id, items: Item_Registry, recipes: []Smelting_Recipe) -> bool {
	switch filter {
	case .Any:
		return true
	case .Fuel:
		return item_is_fuel(items, item)
	case .Smeltable:
		return item_is_smeltable(recipes, item)
	case .Output:
		return false
	}
	return false
}

// A on a machine slot: a held item the slot does not accept stays held,
// otherwise the ordinary pick up, drop, merge or swap. A stack taken from
// the machine has no player slot to return to.
apply_machine_slot_primary :: proc(slots: []Item_Stack, index: int, filter: Slot_Filter, held: Held_Stack, items: Item_Registry, recipes: []Smelting_Recipe) -> Held_Stack {
	if !stack_is_empty(held.stack) && !slot_accepts(filter, held.stack.item, items, recipes) {
		return held
	}
	slot := slots[index]
	takes_from_slot := stack_is_empty(held.stack) || (!stack_is_empty(slot) && slot.item != held.stack.item)
	result := apply_slot_primary(Inventory{slots = slots}, held, index, items)
	if takes_from_slot && !stack_is_empty(result.stack) {
		result.origin_slot = MACHINE_SLOT_ORIGIN
	}
	return result
}

// Ends the gesture: one slot gets the ordinary drop, several share the
// held stack.
finish_distribute :: proc(gesture: Distribute_Gesture, slots: []Item_Stack, filters: []Slot_Filter, held: Held_Stack, items: Item_Registry, recipes: []Smelting_Recipe) -> Held_Stack {
	if gesture.count == 1 {
		index := gesture.visited[0]
		return apply_machine_slot_primary(slots, index, filters[index], held, items, recipes)
	}
	targets := make([dynamic]^Item_Stack, 0, gesture.count, context.temp_allocator)
	visited := gesture.visited
	for index in visited[:gesture.count] {
		append(&targets, &slots[index])
	}
	return distribute_held_stack(held, targets[:], items)
}
