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

// X splits the slot's stack in half onto the cursor.
apply_slot_split :: proc(inventory: Inventory, held: Held_Stack, index: int) -> Held_Stack {
	if !stack_is_empty(held.stack) || stack_is_empty(inventory.slots[index]) {
		return held
	}
	kept, taken := split_stack(inventory.slots[index])
	inventory.slots[index] = kept
	return Held_Stack{stack = taken, origin_slot = index}
}

// X is also the context action. It splits when the focused stack can be
// split, and otherwise sorts the grid (the hotbar keeps its order). Holding
// a stack, it does nothing.
apply_slot_context :: proc(inventory: Inventory, held: Held_Stack, index: int, registry: Item_Registry, ranks: []u16) -> Held_Stack {
	if !stack_is_empty(held.stack) {
		return held
	}
	if index >= 0 && inventory.slots[index].count >= 2 {
		return apply_slot_split(inventory, held, index)
	}
	sort_slots(inventory_grid(inventory), registry, ranks)
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

// The distribute gesture (holding A across machine slots spreads the held
// stack evenly). Machine slots arrive with work item 0011, which completes
// this; until then it leaves the held stack as it is.
distribute_held_stack :: proc(held: Held_Stack, targets: []^Item_Stack, registry: Item_Registry) -> Held_Stack {
	return held
}
