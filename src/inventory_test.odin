package game

import "core:testing"

// Item 0 stacks to 50 (raw), item 1 to 10 (machine), item 2 to 100 (intermediate).
TEST_ORE :: Item_Id(0)
TEST_MACHINE :: Item_Id(1)
TEST_GEAR :: Item_Id(2)

make_small_items :: proc() -> Item_Registry {
	items := make([]Item, 3, context.temp_allocator)
	items[TEST_ORE] = Item{id = "ore", category = .Raw, stack_size = 50}
	items[TEST_MACHINE] = Item{id = "machine", category = .Machine, stack_size = 10}
	items[TEST_GEAR] = Item{id = "gear", category = .Intermediate, stack_size = 100}
	return Item_Registry{items = items}
}

make_test_inventory :: proc(slot_count: int) -> Inventory {
	return make_inventory(slot_count, context.temp_allocator)
}

@(test)
test_add_stacks_to_the_limit_then_uses_empty_slots :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(4)
	inventory.slots[2] = Item_Stack{item = TEST_ORE, count = 45}
	testing.expect_value(t, inventory_add(inventory, items, TEST_ORE, 60), 0)
	// The partial stack fills first, the rest goes to the first empty slot.
	testing.expect_value(t, inventory.slots[2], Item_Stack{item = TEST_ORE, count = 50})
	testing.expect_value(t, inventory.slots[0], Item_Stack{item = TEST_ORE, count = 50})
	testing.expect_value(t, inventory.slots[1], Item_Stack{item = TEST_ORE, count = 5})
	testing.expect_value(t, inventory_count(inventory, TEST_ORE), 105)
}

@(test)
test_add_reports_overflow :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(2)
	inventory.slots[0] = Item_Stack{item = TEST_GEAR, count = 1}
	testing.expect_value(t, inventory_add(inventory, items, TEST_MACHINE, 25), 15)
	testing.expect_value(t, inventory.slots[1], Item_Stack{item = TEST_MACHINE, count = 10})
	testing.expect_value(t, inventory_add(inventory, items, TEST_MACHINE, 3), 3)
	testing.expect_value(t, inventory_add(inventory, items, NO_ITEM, 3), 3)
}

@(test)
test_hotbar_is_a_window_onto_the_slots :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	testing.expect_value(t, len(inventory_hotbar(inventory)), HOTBAR_SLOT_COUNT)
	testing.expect_value(t, len(inventory_grid(inventory)), PLAYER_GRID_SLOT_COUNT)
	inventory_add(inventory, items, TEST_GEAR, 1)
	testing.expect_value(t, inventory_hotbar(inventory)[0].item, TEST_GEAR)
	inventory_hotbar(inventory)[1] = Item_Stack{item = TEST_ORE, count = 2}
	testing.expect_value(t, inventory.slots[1].count, 2)
}

@(test)
test_remove_takes_from_the_back_first :: proc(t: ^testing.T) {
	inventory := make_test_inventory(3)
	inventory.slots[0] = Item_Stack{item = TEST_ORE, count = 5}
	inventory.slots[2] = Item_Stack{item = TEST_ORE, count = 3}
	testing.expect_value(t, inventory_remove(inventory, TEST_ORE, 4), 4)
	testing.expect_value(t, inventory.slots[2], EMPTY_STACK)
	testing.expect_value(t, inventory.slots[0].count, 4)
	testing.expect_value(t, inventory_remove(inventory, TEST_ORE, 10), 4)
	testing.expect_value(t, inventory_count(inventory, TEST_ORE), 0)
}

@(test)
test_split_takes_the_larger_half :: proc(t: ^testing.T) {
	kept, taken := split_stack(Item_Stack{TEST_ORE, 7})
	testing.expect_value(t, kept, Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, taken, Item_Stack{TEST_ORE, 4})
	kept, taken = split_stack(Item_Stack{TEST_ORE, 1})
	testing.expect_value(t, kept, EMPTY_STACK)
	testing.expect_value(t, taken, Item_Stack{TEST_ORE, 1})
	kept, taken = split_stack(EMPTY_STACK)
	testing.expect_value(t, taken, EMPTY_STACK)
}

@(test)
test_sort_merges_and_orders_by_rank :: proc(t: ^testing.T) {
	items := make_small_items()
	ranks := item_sort_ranks(items, []string{"Ore", "Machine", "Gear"}, context.temp_allocator)
	slots := []Item_Stack{EMPTY_STACK, {TEST_MACHINE, 2}, {TEST_ORE, 30}, {TEST_GEAR, 5}, {TEST_ORE, 30}, {TEST_MACHINE, 3}}
	sort_slots(slots, items, ranks)
	expected := []Item_Stack{{TEST_ORE, 50}, {TEST_ORE, 10}, {TEST_GEAR, 5}, {TEST_MACHINE, 5}, EMPTY_STACK, EMPTY_STACK}
	for slot, index in slots {
		testing.expect_value(t, slot, expected[index])
	}
}

@(test)
test_picked_up_raw_items_go_to_the_main_grid :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	testing.expect_value(t, inventory_add_picked_up(inventory, items, TEST_ORE, 3), 0)
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, inventory.slots[0], EMPTY_STACK)
}

@(test)
test_picked_up_tools_and_machines_go_to_the_hotbar :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	inventory.slots[0] = Item_Stack{TEST_GEAR, 1}
	testing.expect_value(t, inventory_add_picked_up(inventory, items, TEST_MACHINE, 2), 0)
	testing.expect_value(t, inventory.slots[1], Item_Stack{TEST_MACHINE, 2})
	tools := Item_Registry{items = []Item{{id = "pickaxe", category = .Tool, stack_size = 1}}}
	testing.expect(t, item_takes_empty_hotbar_slot(tools, Item_Id(0)))
	testing.expect(t, !item_takes_empty_hotbar_slot(items, TEST_GEAR))
	testing.expect(t, !item_takes_empty_hotbar_slot(items, NO_ITEM))
}

// A partial stack on the hotbar comes first for every item, then the
// grid's partial stacks, then its empty slots.
@(test)
test_picked_up_items_fill_a_partial_hotbar_stack_first :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	inventory.slots[2] = Item_Stack{TEST_ORE, 45}
	inventory.slots[HOTBAR_SLOT_COUNT + 3] = Item_Stack{TEST_ORE, 48}
	testing.expect_value(t, inventory_add_picked_up(inventory, items, TEST_ORE, 10), 0)
	testing.expect_value(t, inventory.slots[2], Item_Stack{TEST_ORE, 50})
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT + 3], Item_Stack{TEST_ORE, 50})
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{TEST_ORE, 3})
}

@(test)
test_picked_up_raw_items_take_an_empty_hotbar_slot_only_with_the_grid_full :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	for &slot in inventory_grid(inventory) {
		slot = Item_Stack{TEST_GEAR, 1}
	}
	inventory.slots[HOTBAR_SLOT_COUNT + 5] = Item_Stack{TEST_ORE, 49}
	testing.expect_value(t, inventory_add_picked_up(inventory, items, TEST_ORE, 3), 0)
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT + 5], Item_Stack{TEST_ORE, 50})
	testing.expect_value(t, inventory.slots[0], Item_Stack{TEST_ORE, 2})
	for &slot in inventory_hotbar(inventory) {
		slot = Item_Stack{TEST_GEAR, 1}
	}
	testing.expect_value(t, inventory_add_picked_up(inventory, items, TEST_ORE, 4), 4)
}

// The fits check of a machine pick up follows the pick up routing: the
// machine takes the one empty hotbar slot, so the ore finds no room,
// though the plain slot order would have fitted both.
@(test)
test_picked_up_fits_check_follows_the_routing :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	for &slot in inventory.slots[1:] {
		slot = Item_Stack{TEST_GEAR, 1}
	}
	inventory.slots[HOTBAR_SLOT_COUNT] = Item_Stack{TEST_MACHINE, 8}
	stacks := []Item_Stack{{TEST_MACHINE, 2}, {TEST_ORE, 1}}
	testing.expect(t, inventory_fits_all(inventory, items, stacks))
	testing.expect(t, !inventory_fits_all_picked_up(inventory, items, stacks))
	testing.expect_value(t, inventory_add_picked_up(inventory, items, TEST_MACHINE, 2), 0)
	testing.expect_value(t, inventory_add_picked_up(inventory, items, TEST_ORE, 1), 1)
}
