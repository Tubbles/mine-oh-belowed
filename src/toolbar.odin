package game

// The toolbars (work item 0278, after Techtonica): rows of shortcuts into
// the inventory. A toolbar slot names an item kind (NO_ITEM for none) and
// holds no stack itself: selecting it holds the first stack of that kind
// in slot order (selected_stack_index), which Place, Use_Item, the tools
// and Drop_Stack take from. toolbar_count of them (data/game.sjson) are
// shown, stacked on the HUD with the active one lowest (toolbar_at_row).
// Player.selected_hotbar_slot is the selected slot of the active toolbar.
// Y in the crafting view names a kind on it (Toolbar_Assign_Command), Y
// held there opens the toolbar edit mode (ui_toolbar_edit.odin, 0279); a
// kit and a tool or machine arriving name their kinds on an empty slot
// (take_toolbar_slot).

MAXIMUM_TOOLBAR_COUNT :: 4

Toolbar :: [HOTBAR_SLOT_COUNT]Item_Id

// Every slot names nothing.
empty_toolbars :: proc() -> [MAXIMUM_TOOLBAR_COUNT]Toolbar {
	toolbars: [MAXIMUM_TOOLBAR_COUNT]Toolbar
	for &toolbar in toolbars {
		for &slot in toolbar {
			slot = NO_ITEM
		}
	}
	return toolbars
}

// The content's count clamped to 1 to MAXIMUM_TOOLBAR_COUNT, so a test's
// zero content has one toolbar.
toolbar_count :: proc(content: Simulation_Content) -> int {
	return clamp(content.toolbar_count, 1, MAXIMUM_TOOLBAR_COUNT)
}

// The kind the active toolbar's selected slot names.
selected_kind :: proc(player: Player) -> Item_Id {
	return player.toolbars[player.active_toolbar][player.selected_hotbar_slot]
}

// The inventory index of the first non-empty stack of the selected kind
// in slot order; -1 when the slot names nothing or the inventory lacks it.
selected_stack_index :: proc(player: Player) -> int {
	kind := selected_kind(player)
	if kind == NO_ITEM {
		return -1
	}
	for slot, index in player.inventory.slots {
		if !stack_is_empty(slot) && slot.item == kind {
			return index
		}
	}
	return -1
}

toolbars_name :: proc(toolbars: [MAXIMUM_TOOLBAR_COUNT]Toolbar, item: Item_Id) -> bool {
	for toolbar in toolbars {
		for slot in toolbar {
			if slot == item {
				return true
			}
		}
	}
	return false
}

// When no toolbar names the item, the active toolbar's first empty slot
// names it. True when the item is named afterwards; false with the
// active toolbar full.
take_toolbar_slot :: proc(player: ^Player, item: Item_Id) -> bool {
	if toolbars_name(player.toolbars, item) {
		return true
	}
	for &slot in player.toolbars[player.active_toolbar] {
		if slot == NO_ITEM {
			slot = item
			return true
		}
	}
	return false
}

// The active toolbar within the content's count and the selected slot
// within a toolbar, for a loaded save.
clamp_toolbar_selection :: proc(player: ^Player, count: int) {
	player.active_toolbar = clamp(player.active_toolbar, 0, count - 1)
	player.selected_hotbar_slot = clamp(player.selected_hotbar_slot, 0, HOTBAR_SLOT_COUNT - 1)
}

// A toolbar slot as the HUD and the radial draw it: the kind it names and
// the inventory's count of it.
Toolbar_Entry :: struct {
	item:  Item_Id,
	count: int,
}

toolbar_entries :: proc(player: Player, toolbar: int) -> [HOTBAR_SLOT_COUNT]Toolbar_Entry {
	return toolbar_entries_of(player.toolbars[toolbar], player.inventory)
}

// A toolbar's slots as drawn, of a toolbar the player may not hold yet
// (the toolbar edit mode's, with the commands on their way, 0279).
toolbar_entries_of :: proc(toolbar: Toolbar, inventory: Inventory) -> [HOTBAR_SLOT_COUNT]Toolbar_Entry {
	entries: [HOTBAR_SLOT_COUNT]Toolbar_Entry
	for item, slot in toolbar {
		entries[slot] = {item, item == NO_ITEM ? 0 : inventory_count(inventory, item)}
	}
	return entries
}

// The toolbar drawn on the HUD's row (0 the lowest): the active one
// lowest, the next ones above it in order, wrapping.
toolbar_at_row :: proc(active, count, row: int) -> int {
	return (active + row) % count
}

// Arrivals (0128 carried over): a tool or a machine that arrives by a
// pick up or as a hand craft's output names itself on the first empty
// toolbar slot while the inventory holds it.
item_takes_toolbar_slot :: proc(registry: Item_Registry, item: Item_Id) -> bool {
	return int(item) < len(registry.items) && registry.items[item].category in bit_set[Item_Category]{.Tool, .Machine}
}

offer_toolbar_slot :: proc(player: ^Player, items: Item_Registry, item: Item_Id) {
	if item_takes_toolbar_slot(items, item) && inventory_count(player.inventory, item) > 0 {
		take_toolbar_slot(player, item)
	}
}

// Items picked up, mined, or returned by a machine pick up: inventory_add,
// then the offer when anything went in.
add_picked_up :: proc(player: ^Player, items: Item_Registry, item: Item_Id, count: int) -> (leftover: int) {
	leftover = inventory_add(player.inventory, items, item, count)
	if leftover < count {
		offer_toolbar_slot(player, items, item)
	}
	return leftover
}

// After a hand craft finished.
offer_crafted_outputs :: proc(player: ^Player, items: Item_Registry, outputs: []Item_Stack) {
	for output in outputs {
		offer_toolbar_slot(player, items, output.item)
	}
}
