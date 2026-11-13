package game

import "core:testing"

// The selected slot holds the stack and the active toolbar's selected
// slot names its item (NO_ITEM for an empty stack): what writing the
// hotbar's slot did before the toolbars (0278).
hold_test_stack :: proc(player: ^Player, stack: Item_Stack) {
	player.inventory.slots[player.selected_hotbar_slot] = stack
	player.toolbars[player.active_toolbar][player.selected_hotbar_slot] = shown_item(stack)
}

// inventory_add, then the kind named on the active toolbar's first empty
// slot (take_toolbar_slot): a test player given an item to hold, as the
// hotbar's routing held a machine or a tool before the toolbars (0278).
give_test_kind :: proc(player: ^Player, items: Item_Registry, item: Item_Id, count: int) {
	inventory_add(player.inventory, items, item, count)
	take_toolbar_slot(player, item)
}

@(test)
test_the_selected_kind_holds_the_first_stack_in_slot_order :: proc(t: ^testing.T) {
	items := make_test_items()
	machines := make_test_machines()
	player := make_player({}, context.temp_allocator)
	dirt := test_item(items, "dirt")
	player.inventory.slots[30] = Item_Stack{dirt, 4}
	player.inventory.slots[7] = Item_Stack{dirt, 9}
	player.selected_hotbar_slot = 2
	player.toolbars[0][2] = dirt
	testing.expect_value(t, selected_kind(player), dirt)
	testing.expect_value(t, selected_stack_index(player), 7)
	testing.expect_value(t, selected_hotbar_stack(player), Item_Stack{dirt, 9})
	// A slot that names nothing, and a kind the inventory lacks.
	player.toolbars[0][2] = NO_ITEM
	testing.expect_value(t, selected_stack_index(player), -1)
	testing.expect_value(t, selected_hotbar_stack(player), EMPTY_STACK)
	furnace := test_item(items, "stone_furnace")
	player.toolbars[0][2] = furnace
	testing.expect_value(t, selected_stack_index(player), -1)
	testing.expect_value(t, selected_hotbar_stack(player), EMPTY_STACK)
	testing.expect_value(t, selected_placed_machine(player, machines), NO_MACHINE)
	player.inventory.slots[40] = Item_Stack{furnace, 1}
	testing.expect(t, selected_placed_machine(player, machines) != NO_MACHINE)
}

@(test)
test_take_toolbar_slot_names_a_kind_once :: proc(t: ^testing.T) {
	player := make_player({}, context.temp_allocator)
	player.toolbars[0][0] = Item_Id(5)
	testing.expect(t, take_toolbar_slot(&player, Item_Id(7)))
	testing.expect_value(t, player.toolbars[0][1], Item_Id(7))
	// Named on another toolbar: not named again.
	player.toolbars[1][4] = Item_Id(9)
	testing.expect(t, take_toolbar_slot(&player, Item_Id(9)))
	testing.expect_value(t, player.toolbars[0][2], NO_ITEM)
	testing.expect(t, take_toolbar_slot(&player, Item_Id(7)))
	testing.expect_value(t, player.toolbars[0][2], NO_ITEM)
	// A full active toolbar names nothing.
	for &slot, index in player.toolbars[0] {
		slot = Item_Id(20 + index)
	}
	testing.expect(t, !take_toolbar_slot(&player, Item_Id(40)))
	testing.expect(t, !toolbars_name(player.toolbars, Item_Id(40)))
}

@(test)
test_toolbar_rows_stack_the_active_one_lowest :: proc(t: ^testing.T) {
	testing.expect_value(t, toolbar_at_row(0, 1, 0), 0)
	expected_two := [2]int{1, 0}
	for row in 0 ..< 2 {
		testing.expectf(t, toolbar_at_row(1, 2, row) == expected_two[row], "row %d of two with the second active", row)
	}
	expected_four := [4]int{2, 3, 0, 1}
	for row in 0 ..< 4 {
		testing.expectf(t, toolbar_at_row(2, 4, row) == expected_four[row], "row %d of four with the third active", row)
	}
}

@(test)
test_the_kits_name_their_kinds :: proc(t: ^testing.T) {
	items := make_test_items()
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	player := make_player({}, context.temp_allocator)
	give_starting_items(&player, items, config.starting_items)
	foundation, torch := test_item(items, "wooden_foundation"), test_item(items, "torch")
	testing.expect_value(t, player.toolbars[0][0], foundation)
	testing.expect_value(t, player.toolbars[0][1], torch)
	testing.expect_value(t, player.toolbars[0][2], NO_ITEM)
	testing.expect_value(t, selected_hotbar_stack(player).item, foundation)
	// give (the command, a chapter kit) names a kind on the first empty slot.
	pending := make([dynamic]Item_Stack, context.temp_allocator)
	furnace := test_item(items, "stone_furnace")
	give_to_player(&player, &pending, items, Developer_Grant{item = furnace, count = 1})
	testing.expect_value(t, player.toolbars[0][2], furnace)
	// The tech demo clears the starter kit and names its six kinds in order.
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.toolbars = empty_toolbars()
	give_starting_items(&player, items, config.tech_demo_items)
	testing.expect_value(t, len(config.tech_demo_items), 6)
	for starting, index in config.tech_demo_items {
		testing.expectf(t, player.toolbars[0][index] == test_item(items, starting.item), "slot %d names %s", index, starting.item)
	}
}

// P1 of 0278: a tool or a machine that arrives by a pick up or a hand
// craft names itself on the first empty slot; a raw item or an
// intermediate does not; a named kind is not named twice.
@(test)
test_arrivals_offer_tools_and_machines_a_toolbar_slot :: proc(t: ^testing.T) {
	items := make_test_items()
	player := make_player({}, context.temp_allocator)
	furnace, log_item := test_item(items, "stone_furnace"), test_item(items, "log")
	shovel, plate := test_item(items, "wooden_shovel"), test_item(items, "iron_plate")
	testing.expect_value(t, add_picked_up(&player, items, furnace, 1), 0)
	testing.expect_value(t, add_picked_up(&player, items, log_item, 3), 0)
	inventory_add(player.inventory, items, shovel, 1)
	inventory_add(player.inventory, items, plate, 2)
	offer_crafted_outputs(&player, items, []Item_Stack{{shovel, 1}, {plate, 2}})
	testing.expect_value(t, player.toolbars[0][0], furnace)
	testing.expect_value(t, player.toolbars[0][1], shovel)
	testing.expect_value(t, player.toolbars[0][2], NO_ITEM)
	testing.expect_value(t, add_picked_up(&player, items, furnace, 1), 0)
	testing.expect_value(t, player.toolbars[0][2], NO_ITEM)
	testing.expect(t, item_takes_toolbar_slot(items, furnace))
	testing.expect(t, !item_takes_toolbar_slot(items, log_item))
	testing.expect(t, !item_takes_toolbar_slot(items, NO_ITEM))
}
