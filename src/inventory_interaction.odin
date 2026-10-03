package game

// The gamepad slot interaction from doc/ui.md as pure procedures over the
// inventory and the stack on the cursor. The pointer drives the same
// procedures by drag and drop (Slot_Drag, 0124). Slot indices are into
// Inventory.slots.

// origin_slot is where the stack was picked up, so closing the screen can
// put it back there.
Held_Stack :: struct {
	stack:       Item_Stack,
	origin_slot: int,
}

EMPTY_HELD_STACK :: Held_Stack {
	stack = EMPTY_STACK,
}

// A (or a pointer drag, Slot_Drag): pick up the slot's stack, drop the
// held stack onto an empty slot, merge it onto the same item (the rest
// stays held), or swap it with a different item.
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

// The grids of a slot screen (0125): the player's hotbar row, the
// player's main grid and the open machine's slots.
Slot_Grid_Kind :: enum u8 {
	None,
	Hotbar,
	Main,
	Machine,
}

// The slot that last held the focus and its grid, the active grid: Sort,
// Split and the transfers of the touch row act on it after the focus
// moved to the row's button. index is an inventory index for the
// player's grids and a machine slot for .Machine.
Active_Slot :: struct {
	grid:  Slot_Grid_Kind,
	index: int,
}

// The grid Sort sorts: the active one, but the hotbar keeps its order,
// so from the hotbar Sort sorts the player's main grid (the screens open
// with the focus on the hotbar).
sort_target_grid :: proc(active: Slot_Grid_Kind) -> Slot_Grid_Kind {
	return active == .Hotbar ? .Main : active
}

// A focused player slot (an inventory index) or machine slot makes its
// grid active; a focus off the slots keeps the last one.
active_slot_after_focus :: proc(previous: Active_Slot, player_focused, machine_focused: int) -> Active_Slot {
	switch {
	case player_focused >= 0:
		return {player_focused < HOTBAR_SLOT_COUNT ? .Hotbar : .Main, player_focused}
	case machine_focused >= 0:
		return {.Machine, machine_focused}
	}
	return previous
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

// Whether return_held_stack would move anything: a hand that stays as it
// is (empty, or no room anywhere) needs no Return_Held_Command, which
// would otherwise go into every tick's record while the inventory stays
// full.
return_changes_hand :: proc(inventory: Inventory, held: Held_Stack, registry: Item_Registry) -> bool {
	if stack_is_empty(held.stack) {
		return false
	}
	copied := Inventory{slots = make([]Item_Stack, len(inventory.slots), context.temp_allocator)}
	copy(copied.slots, inventory.slots)
	return return_held_stack(copied, held, registry) != held
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

// The distribute gesture from doc/ui.md: A on a machine slot while
// holding a stack starts it, moving the focus with A held visits more
// slots (a pointer drag drops on one slot instead, 0124), and releasing
// spreads the stack over them. A single visited slot gets the ordinary
// drop instead.
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
Slot_Filter_Kind :: enum u8 {
	Any,
	Fuel,
	Smeltable,
	// Output slots only give.
	Output,
	// Only Slot_Filter.item (assembler inputs, lab slots).
	Item,
	// Any input of a recipe of Slot_Filter.maker (the inputs of a fixed
	// recipe crafting machine).
	Crafting_Input,
}

Slot_Filter :: struct {
	kind:  Slot_Filter_Kind,
	item:  Item_Id,
	maker: Recipe_Maker,
}

slot_accepts :: proc(filter: Slot_Filter, item: Item_Id, items: Item_Registry, recipes: Recipe_Registry) -> bool {
	switch filter.kind {
	case .Any:
		return true
	case .Fuel:
		return item_is_fuel(items, item)
	case .Smeltable:
		return item_is_smeltable(recipes, item)
	case .Output:
		return false
	case .Item:
		return item == filter.item
	case .Crafting_Input:
		return category_input_count(recipes, filter.maker, item) > 0
	}
	return false
}

// A on a machine slot: a held item the slot does not accept stays held,
// otherwise the ordinary pick up, drop, merge or swap. A stack taken from
// the machine has no player slot to return to.
apply_machine_slot_primary :: proc(slots: []Item_Stack, index: int, filter: Slot_Filter, held: Held_Stack, items: Item_Registry, recipes: Recipe_Registry) -> Held_Stack {
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

// A slot joins the gesture when it takes the held item and has it or nothing.
slot_takes_distribution :: proc(slot: Item_Stack, filter: Slot_Filter, held: Held_Stack, items: Item_Registry, recipes: Recipe_Registry) -> bool {
	if stack_is_empty(held.stack) || !slot_accepts(filter, held.stack.item, items, recipes) {
		return false
	}
	return stack_is_empty(slot) || slot.item == held.stack.item
}

// Ends the gesture: one slot gets the ordinary drop, several share the
// held stack.
finish_distribute :: proc(gesture: Distribute_Gesture, slots: []Item_Stack, filters: []Slot_Filter, held: Held_Stack, items: Item_Registry, recipes: Recipe_Registry) -> Held_Stack {
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
