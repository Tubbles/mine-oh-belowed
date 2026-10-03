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

// Fills the partial stacks of the item in slot order. Returns the count
// that did not fit.
fill_partial_stacks :: proc(slots: []Item_Stack, item: Item_Id, count: int, stack_size: u16) -> int {
	remaining := count
	for &slot in slots {
		if remaining > 0 && !stack_is_empty(slot) && slot.item == item {
			remaining = fill_slot(&slot, item, remaining, stack_size)
		}
	}
	return remaining
}

// Fills the empty slots in slot order. Returns the count that did not fit.
fill_empty_slots :: proc(slots: []Item_Stack, item: Item_Id, count: int, stack_size: u16) -> int {
	remaining := count
	for &slot in slots {
		if remaining > 0 && stack_is_empty(slot) {
			remaining = fill_slot(&slot, item, remaining, stack_size)
		}
	}
	return remaining
}

// Fills partial stacks of the item first, then empty slots, both in slot
// order. Returns the count that did not fit.
add_to_slots :: proc(slots: []Item_Stack, item: Item_Id, count: int, stack_size: u16) -> int {
	return fill_empty_slots(slots, item, fill_partial_stacks(slots, item, count, stack_size), stack_size)
}

// Hotbar first, since it is the front of the slot array.
inventory_add :: proc(inventory: Inventory, registry: Item_Registry, item: Item_Id, count: int) -> (leftover: int) {
	stack_size := item_stack_size(registry, item)
	if stack_size == 0 {
		return count
	}
	return add_to_slots(inventory.slots, item, count, stack_size)
}

// Tools and machines take an empty hotbar slot on pick up; every other
// item goes to the main grid.
item_takes_empty_hotbar_slot :: proc(registry: Item_Registry, item: Item_Id) -> bool {
	return int(item) < len(registry.items) && registry.items[item].category in bit_set[Item_Category]{.Tool, .Machine}
}

// Items picked up, mined, or returned by a machine pick up (work item
// 0128): the item's partial stacks on the hotbar first, whatever the
// item; then a tool or a machine takes empty hotbar slots before the main
// grid, while every other item fills the main grid (partial stacks, then
// empty slots) and takes empty hotbar slots only when the grid is full.
inventory_add_picked_up :: proc(inventory: Inventory, registry: Item_Registry, item: Item_Id, count: int) -> (leftover: int) {
	stack_size := item_stack_size(registry, item)
	if stack_size == 0 {
		return count
	}
	hotbar, grid := inventory_hotbar(inventory), inventory_grid(inventory)
	remaining := fill_partial_stacks(hotbar, item, count, stack_size)
	if item_takes_empty_hotbar_slot(registry, item) {
		return add_to_slots(grid, item, fill_empty_slots(hotbar, item, remaining, stack_size), stack_size)
	}
	return fill_empty_slots(hotbar, item, add_to_slots(grid, item, remaining, stack_size), stack_size)
}

// Whether all the stacks fit at once, tried on a copy of the slots.
inventory_fits_all :: proc(inventory: Inventory, registry: Item_Registry, stacks: []Item_Stack) -> bool {
	trial := make([]Item_Stack, len(inventory.slots), context.temp_allocator)
	copy(trial, inventory.slots)
	for stack in stacks {
		if !stack_is_empty(stack) && add_to_slots(trial, stack.item, int(stack.count), item_stack_size(registry, stack.item)) > 0 {
			return false
		}
	}
	return true
}

// inventory_fits_all for stacks that go in by inventory_add_picked_up.
inventory_fits_all_picked_up :: proc(inventory: Inventory, registry: Item_Registry, stacks: []Item_Stack) -> bool {
	trial := Inventory{slots = make([]Item_Stack, len(inventory.slots), context.temp_allocator)}
	copy(trial.slots, inventory.slots)
	for stack in stacks {
		if !stack_is_empty(stack) && inventory_add_picked_up(trial, registry, stack.item, int(stack.count)) > 0 {
			return false
		}
	}
	return true
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

Slot_Order_Context :: struct {
	slots: []Item_Stack,
	ranks: []u16,
}

slot_sorts_before :: proc(first, second: int, data: rawptr) -> bool {
	order_context := (^Slot_Order_Context)(data)
	return order_context.ranks[order_context.slots[first].item] < order_context.ranks[order_context.slots[second].item]
}

// The Sort order: the indices of the non-empty slots by rank (category,
// then name; item_sort_ranks). The ranks follow the display names, which
// differ between languages, so the screen takes the order and the sort
// command carries it to every machine (Slot_Sort_Command). In the temp
// allocator.
sorted_slot_order :: proc(slots: []Item_Stack, ranks: []u16) -> []int {
	order := make([dynamic]int, 0, len(slots), context.temp_allocator)
	for slot, index in slots {
		if !stack_is_empty(slot) {
			append(&order, index)
		}
	}
	order_context := Slot_Order_Context{slots, ranks}
	slice.sort_by_with_data(order[:], slot_sorts_before, &order_context)
	return order[:]
}

// Puts the stacks of the slots the order names into that order, merging
// stacks of the same item, empty slots last. The order names every
// non-empty slot once (sort_order_matches).
arrange_slots :: proc(slots: []Item_Stack, registry: Item_Registry, order: []int) {
	stacks := make([dynamic]Item_Stack, 0, len(order), context.temp_allocator)
	for index in order {
		append(&stacks, slots[index])
	}
	slice.fill(slots, EMPTY_STACK)
	// Merging never needs more slots than the stacks had, so nothing is left over.
	for stack in stacks {
		add_to_slots(slots, stack.item, int(stack.count), item_stack_size(registry, stack.item))
	}
}

// The order names exactly the non-empty slots, each once: anything else
// (the slots changed since the screen took the order) would lose or
// double a stack.
sort_order_matches :: proc(slots: []Item_Stack, order: []int) -> bool {
	named := make([]bool, len(slots), context.temp_allocator)
	for index in order {
		if index < 0 || index >= len(slots) || named[index] || stack_is_empty(slots[index]) {
			return false
		}
		named[index] = true
	}
	for slot, index in slots {
		if !stack_is_empty(slot) && !named[index] {
			return false
		}
	}
	return true
}
