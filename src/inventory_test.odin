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
	order := sorted_slot_order(slots, ranks)
	testing.expect(t, sort_order_matches(slots, order))
	arrange_slots(slots, items, order)
	expected := []Item_Stack{{TEST_ORE, 50}, {TEST_ORE, 10}, {TEST_GEAR, 5}, {TEST_MACHINE, 5}, EMPTY_STACK, EMPTY_STACK}
	for slot, index in slots {
		testing.expect_value(t, slot, expected[index])
	}
	// An order that misses a stack, names an empty slot or names one twice
	// does not match.
	testing.expect(t, !sort_order_matches(slots, []int{0, 1, 2}))
	testing.expect(t, !sort_order_matches(slots, []int{0, 1, 2, 3, 4}))
	testing.expect(t, !sort_order_matches(slots, []int{0, 1, 2, 2}))
}
