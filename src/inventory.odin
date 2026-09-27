package game

import "core:slice"

// Fixed slots of item stacks. A slot is empty when its count is 0. The
// hotbar is a window onto the first eight slots of the same array, so
// moving a stack into the hotbar is an ordinary slot move.

HOTBAR_SLOT_COUNT :: 8
PLAYER_GRID_SLOT_COUNT :: 36
PLAYER_INVENTORY_SLOT_COUNT :: HOTBAR_SLOT_COUNT + PLAYER_GRID_SLOT_COUNT

Item_Stack :: struct {
	item:  Item_Id,
	count: u16,
}

Inventory :: struct {
	slots: []Item_Stack,
}

EMPTY_STACK :: Item_Stack {
	item = NO_ITEM,
}

make_inventory :: proc(slot_count: int, allocator := context.allocator) -> Inventory {
	slots := make([]Item_Stack, slot_count, allocator)
	slice.fill(slots, EMPTY_STACK)
	return Inventory{slots = slots}
}

destroy_inventory :: proc(inventory: Inventory, allocator := context.allocator) {
	delete(inventory.slots, allocator)
}

stack_is_empty :: proc(stack: Item_Stack) -> bool {
	return stack.count == 0
}

inventory_hotbar :: proc(inventory: Inventory) -> []Item_Stack {
	return inventory.slots[:min(HOTBAR_SLOT_COUNT, len(inventory.slots))]
}

inventory_grid :: proc(inventory: Inventory) -> []Item_Stack {
	return inventory.slots[min(HOTBAR_SLOT_COUNT, len(inventory.slots)):]
}

// Takes as much of count as the slot has room for and returns the rest.
fill_slot :: proc(slot: ^Item_Stack, item: Item_Id, count: int, stack_size: u16) -> int {
	if !stack_is_empty(slot^) && slot.item != item {
		return count
	}
	moved := min(count, int(stack_size) - int(slot.count))
	if moved <= 0 {
		return count
	}
	slot.item = item
	slot.count += u16(moved)
	return count - moved
}

// Fills partial stacks of the item first, then empty slots, both in slot
// order. Returns the count that did not fit.
add_to_slots :: proc(slots: []Item_Stack, item: Item_Id, count: int, stack_size: u16) -> int {
	remaining := count
	for &slot in slots {
		if remaining > 0 && !stack_is_empty(slot) && slot.item == item {
			remaining = fill_slot(&slot, item, remaining, stack_size)
		}
	}
	for &slot in slots {
		if remaining > 0 && stack_is_empty(slot) {
			remaining = fill_slot(&slot, item, remaining, stack_size)
		}
	}
	return remaining
}

// Hotbar first, since it is the front of the slot array.
inventory_add :: proc(inventory: Inventory, registry: Item_Registry, item: Item_Id, count: int) -> (leftover: int) {
	stack_size := item_stack_size(registry, item)
	if stack_size == 0 {
		return count
	}
	return add_to_slots(inventory.slots, item, count, stack_size)
}

// Takes up to count from the slot and returns how many were taken.
take_from_slot :: proc(slot: ^Item_Stack, count: int) -> int {
	taken := min(count, int(slot.count))
	slot.count -= u16(taken)
	if slot.count == 0 {
		slot^ = EMPTY_STACK
	}
	return taken
}

// Removes from the last slots first, so the hotbar is the last to empty.
// Returns how many were removed.
inventory_remove :: proc(inventory: Inventory, item: Item_Id, count: int) -> (removed: int) {
	#reverse for &slot in inventory.slots {
		if removed < count && !stack_is_empty(slot) && slot.item == item {
			removed += take_from_slot(&slot, count - removed)
		}
	}
	return removed
}

inventory_count :: proc(inventory: Inventory, item: Item_Id) -> int {
	total := 0
	for slot in inventory.slots {
		if !stack_is_empty(slot) && slot.item == item {
			total += int(slot.count)
		}
	}
	return total
}

// Onto an empty slot the stack moves, onto the same item it merges up to
// the stack size (the rest stays behind), onto a different item the two
// swap.
move_or_swap :: proc(slots: []Item_Stack, from, to: int, registry: Item_Registry) {
	if from == to || stack_is_empty(slots[from]) {
		return
	}
	source, target := &slots[from], &slots[to]
	if !stack_is_empty(target^) && target.item != source.item {
		source^, target^ = target^, source^
		return
	}
	left := fill_slot(target, source.item, int(source.count), item_stack_size(registry, source.item))
	take_from_slot(source, int(source.count) - left)
}

// The larger half is taken, so a stack of one is taken whole.
split_stack :: proc(stack: Item_Stack) -> (kept: Item_Stack, taken: Item_Stack) {
	if stack_is_empty(stack) {
		return EMPTY_STACK, EMPTY_STACK
	}
	taken_count := (stack.count + 1) / 2
	kept = stack
	kept.count -= taken_count
	if kept.count == 0 {
		kept = EMPTY_STACK
	}
	return kept, Item_Stack{item = stack.item, count = taken_count}
}

Stack_Sort_Context :: struct {
	ranks: []u16,
}

stack_sorts_before :: proc(first, second: Item_Stack, data: rawptr) -> bool {
	ranks := (^Stack_Sort_Context)(data).ranks
	return ranks[first.item] < ranks[second.item]
}

// Merges stacks of the same item and orders them by rank (category, then
// name), empty slots last. Ranks come from item_sort_ranks.
sort_slots :: proc(slots: []Item_Stack, registry: Item_Registry, ranks: []u16) {
	stacks := make([dynamic]Item_Stack, 0, len(slots), context.temp_allocator)
	for slot in slots {
		if !stack_is_empty(slot) {
			append(&stacks, slot)
		}
	}
	sort_context := Stack_Sort_Context{ranks}
	slice.sort_by_with_data(stacks[:], stack_sorts_before, &sort_context)
	slice.fill(slots, EMPTY_STACK)
	// Merging never needs more slots than the stacks had, so nothing is left over.
	for stack in stacks {
		add_to_slots(slots, stack.item, int(stack.count), item_stack_size(registry, stack.item))
	}
}
