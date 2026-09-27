package game

import "core:slice"
import "core:testing"

@(test)
test_primary_picks_up_drops_and_swaps :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(3)
	inventory.slots[0] = Item_Stack{TEST_ORE, 8}
	inventory.slots[1] = Item_Stack{TEST_GEAR, 2}
	held := apply_slot_primary(inventory, EMPTY_HELD_STACK, 0, items)
	testing.expect_value(t, held, Held_Stack{Item_Stack{TEST_ORE, 8}, 0})
	testing.expect_value(t, inventory.slots[0], EMPTY_STACK)
	// Onto a different item: swap, the cursor now holds the gear.
	held = apply_slot_primary(inventory, held, 1, items)
	testing.expect_value(t, inventory.slots[1], Item_Stack{TEST_ORE, 8})
	testing.expect_value(t, held, Held_Stack{Item_Stack{TEST_GEAR, 2}, 1})
	// Onto an empty slot: drop.
	held = apply_slot_primary(inventory, held, 2, items)
	testing.expect_value(t, inventory.slots[2], Item_Stack{TEST_GEAR, 2})
	testing.expect_value(t, held.stack, EMPTY_STACK)
	// An empty slot with nothing held does nothing.
	held = apply_slot_primary(inventory, held, 0, items)
	testing.expect_value(t, held.stack, EMPTY_STACK)
}

@(test)
test_primary_merges_up_to_the_stack_size :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(2)
	inventory.slots[1] = Item_Stack{TEST_ORE, 45}
	held := Held_Stack{Item_Stack{TEST_ORE, 20}, 0}
	held = apply_slot_primary(inventory, held, 1, items)
	testing.expect_value(t, inventory.slots[1], Item_Stack{TEST_ORE, 50})
	testing.expect_value(t, held.stack, Item_Stack{TEST_ORE, 15})
}

@(test)
test_split_and_sort_are_separate :: proc(t: ^testing.T) {
	items := make_small_items()
	ranks := item_sort_ranks(items, []string{"Ore", "Machine", "Gear"}, context.temp_allocator)
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	inventory.slots[3] = Item_Stack{TEST_MACHINE, 1}
	inventory.slots[HOTBAR_SLOT_COUNT + 5] = Item_Stack{TEST_GEAR, 9}
	inventory.slots[HOTBAR_SLOT_COUNT + 2] = Item_Stack{TEST_ORE, 1}
	// L2 splits the larger half onto the cursor.
	held := apply_slot_split(inventory, EMPTY_HELD_STACK, HOTBAR_SLOT_COUNT + 5)
	testing.expect_value(t, held, Held_Stack{Item_Stack{TEST_GEAR, 5}, HOTBAR_SLOT_COUNT + 5})
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT + 5], Item_Stack{TEST_GEAR, 4})
	// Holding a stack, sorting and splitting do nothing.
	testing.expect_value(t, apply_slot_context(inventory, held, items, ranks), held)
	testing.expect_value(t, apply_slot_split(inventory, held, HOTBAR_SLOT_COUNT + 2), held)
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT + 5], Item_Stack{TEST_GEAR, 4})
	held = return_held_stack(inventory, held, items)
	testing.expect_value(t, held.stack, EMPTY_STACK)
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT + 5], Item_Stack{TEST_GEAR, 9})
	// X sorts the grid even on a stack of several; the hotbar keeps its order.
	apply_slot_context(inventory, EMPTY_HELD_STACK, items, ranks)
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{TEST_ORE, 1})
	testing.expect_value(t, inventory.slots[HOTBAR_SLOT_COUNT + 1], Item_Stack{TEST_GEAR, 9})
	testing.expect_value(t, inventory.slots[3], Item_Stack{TEST_MACHINE, 1})
}

@(test)
test_held_stack_returns_to_its_origin :: proc(t: ^testing.T) {
	items := make_small_items()
	inventory := make_test_inventory(3)
	inventory.slots[0] = Item_Stack{TEST_GEAR, 1}
	held := return_held_stack(inventory, Held_Stack{Item_Stack{TEST_ORE, 5}, 2}, items)
	testing.expect_value(t, held.stack, EMPTY_STACK)
	testing.expect_value(t, inventory.slots[2], Item_Stack{TEST_ORE, 5})
	// The origin is taken by another item: the first free slot.
	held = return_held_stack(inventory, Held_Stack{Item_Stack{TEST_MACHINE, 4}, 0}, items)
	testing.expect_value(t, inventory.slots[1], Item_Stack{TEST_MACHINE, 4})
	// No room anywhere: the rest stays held.
	held = return_held_stack(inventory, Held_Stack{Item_Stack{TEST_MACHINE, 9}, 0}, items)
	testing.expect_value(t, inventory.slots[1], Item_Stack{TEST_MACHINE, 10})
	testing.expect_value(t, held.stack, Item_Stack{TEST_MACHINE, 3})
}

@(test)
test_inventory_slot_input_applies_confirm_split_and_sort :: proc(t: ^testing.T) {
	items := make_small_items()
	ranks := item_sort_ranks(items, []string{"Ore", "Machine", "Gear"}, context.temp_allocator)
	inventory := make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT)
	inventory.slots[HOTBAR_SLOT_COUNT] = Item_Stack{TEST_ORE, 6}
	held := apply_inventory_slot_input(inventory, EMPTY_HELD_STACK, {activated = HOTBAR_SLOT_COUNT, focused = HOTBAR_SLOT_COUNT}, items, ranks)
	testing.expect_value(t, held.stack, Item_Stack{TEST_ORE, 6})
	held = apply_inventory_slot_input(inventory, held, {activated = 0, focused = 0}, items, ranks)
	testing.expect_value(t, inventory.slots[0], Item_Stack{TEST_ORE, 6})
	held = apply_inventory_slot_input(inventory, held, {activated = -1, focused = 0, secondary = true}, items, ranks)
	testing.expect_value(t, held.stack, Item_Stack{TEST_ORE, 3})
	held = apply_inventory_slot_input(inventory, held, {activated = 0, focused = 0}, items, ranks)
	held = apply_inventory_slot_input(inventory, held, {activated = -1, focused = 0, context_action = true}, items, ranks)
	testing.expect_value(t, held.stack, EMPTY_STACK)
	testing.expect_value(t, inventory.slots[0], Item_Stack{TEST_ORE, 6})
	testing.expect_value(t, grid_result_to_inventory({activated = 2, focused = -1}, HOTBAR_SLOT_COUNT), Slot_Grid_Result{HOTBAR_SLOT_COUNT + 2, -1})
}

// Radial slots map one to one onto hotbar slots: slot 0 at the top of the
// pad, clockwise.
@(test)
test_radial_selects_hotbar_slot :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	items := make_small_items()
	player := Player {
		inventory = make_test_inventory(PLAYER_INVENTORY_SLOT_COUNT),
	}
	positions := [HOTBAR_SLOT_COUNT][2]f32{{0.5, 0.05}, {0.85, 0.15}, {0.95, 0.5}, {0.85, 0.85}, {0.5, 0.95}, {0.15, 0.85}, {0.05, 0.5}, {0.15, 0.15}}
	for position, slot in positions {
		test_ui_frame(&state, {left_touchpad = {down = true, position = position}})
		hotbar_radial(&state, &player, items)
		testing.expect_value(t, state.radial.highlight, slot)
		test_ui_frame(&state, {left_touchpad = {down = false, position = position}})
		hotbar_radial(&state, &player, items)
		testing.expect_value(t, player.selected_hotbar_slot, slot)
	}
	// Released in the dead centre: the selection stays.
	test_ui_frame(&state, {left_touchpad = {down = true, position = {0.5, 0.5}}})
	hotbar_radial(&state, &player, items)
	test_ui_frame(&state, {})
	hotbar_radial(&state, &player, items)
	testing.expect_value(t, player.selected_hotbar_slot, HOTBAR_SLOT_COUNT - 1)
	// Tab held with the right stick pointing down, then released.
	test_ui_frame(&state, {hotbar_radial_down = true, right_stick = {0, -1}})
	hotbar_radial(&state, &player, items)
	test_ui_frame(&state, {hotbar_radial_down = true})
	hotbar_radial(&state, &player, items)
	testing.expect(t, state.radial.open)
	test_ui_frame(&state, {})
	hotbar_radial(&state, &player, items)
	testing.expect_value(t, player.selected_hotbar_slot, 4)
	// The right stick alone does not open the hotbar radial.
	test_ui_frame(&state, {right_stick = {1, 0}})
	hotbar_radial(&state, &player, items)
	testing.expect(t, !state.radial.open)
}

@(test)
test_distribute_spreads_evenly :: proc(t: ^testing.T) {
	items := make_small_items()
	slots := make([]Item_Stack, 4, context.temp_allocator)
	slice.fill(slots, EMPTY_STACK)
	slots[3] = Item_Stack{TEST_GEAR, 1}
	targets := []^Item_Stack{&slots[0], &slots[1], &slots[2]}
	held := distribute_held_stack(Held_Stack{Item_Stack{TEST_ORE, 10}, 5}, targets, items)
	testing.expect_value(t, slots[0], Item_Stack{TEST_ORE, 4})
	testing.expect_value(t, slots[1], Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, slots[2], Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, held.stack, EMPTY_STACK)
	// Fewer items than targets: one each from the front.
	held = distribute_held_stack(Held_Stack{Item_Stack{TEST_ORE, 2}, 5}, targets, items)
	testing.expect_value(t, slots[0], Item_Stack{TEST_ORE, 5})
	testing.expect_value(t, slots[1], Item_Stack{TEST_ORE, 4})
	testing.expect_value(t, slots[2], Item_Stack{TEST_ORE, 3})
	// A target of another item and a nearly full one keep their shares on the cursor.
	slots[0] = Item_Stack{TEST_ORE, 49}
	mixed := []^Item_Stack{&slots[0], &slots[3]}
	held = distribute_held_stack(Held_Stack{Item_Stack{TEST_ORE, 6}, 5}, mixed, items)
	testing.expect_value(t, slots[0], Item_Stack{TEST_ORE, 50})
	testing.expect_value(t, slots[3], Item_Stack{TEST_GEAR, 1})
	testing.expect_value(t, held.stack, Item_Stack{TEST_ORE, 5})
	testing.expect_value(t, distribute_held_stack(EMPTY_HELD_STACK, targets, items), EMPTY_HELD_STACK)
}

@(test)
test_distribute_gesture_over_machine_slots :: proc(t: ^testing.T) {
	items := make_small_items()
	slots := make([]Item_Stack, 4, context.temp_allocator)
	slice.fill(slots, EMPTY_STACK)
	filters := make([]Slot_Filter, 4, context.temp_allocator)
	gesture: Distribute_Gesture
	held := Held_Stack{Item_Stack{TEST_ORE, 9}, 2}
	// A pressed on slot 0, held while the focus crosses 1 (twice) and 3, released.
	held = apply_machine_slot_input(&gesture, slots, filters, held, {activated = 0, focused = 0, confirm_down = true}, items, nil)
	testing.expect(t, gesture.active)
	testing.expect_value(t, slots[0], EMPTY_STACK)
	for focused in ([?]int{0, 1, 1, 3}) {
		held = apply_machine_slot_input(&gesture, slots, filters, held, {activated = -1, focused = focused, confirm_down = true}, items, nil)
	}
	testing.expect_value(t, gesture.count, 3)
	held = apply_machine_slot_input(&gesture, slots, filters, held, {activated = -1, focused = 3}, items, nil)
	testing.expect(t, !gesture.active)
	testing.expect_value(t, slots[0], Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, slots[1], Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, slots[2], EMPTY_STACK)
	testing.expect_value(t, slots[3], Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, held.stack, EMPTY_STACK)
	// A press and release on one slot is the ordinary pick up and drop.
	held = apply_machine_slot_input(&gesture, slots, filters, EMPTY_HELD_STACK, {activated = 1, focused = 1, confirm_down = true}, items, nil)
	testing.expect_value(t, held, Held_Stack{Item_Stack{TEST_ORE, 3}, MACHINE_SLOT_ORIGIN})
	testing.expect(t, !gesture.active)
	held = apply_machine_slot_input(&gesture, slots, filters, held, {activated = 2, focused = 2, confirm_down = true}, items, nil)
	held = apply_machine_slot_input(&gesture, slots, filters, held, {activated = -1, focused = 2}, items, nil)
	testing.expect_value(t, slots[2], Item_Stack{TEST_ORE, 3})
	testing.expect_value(t, held.stack, EMPTY_STACK)
}

@(test)
test_machine_slots_filter_what_the_player_drops :: proc(t: ^testing.T) {
	items := make_test_items()
	recipes := make_test_machines().smelting
	coal := test_item(items, "coal")
	hematite := test_item(items, "hematite")
	filters := machine_slot_filters(.Furnace, FURNACE_SLOT_COUNT)
	slots := make([]Item_Stack, FURNACE_SLOT_COUNT, context.temp_allocator)
	slice.fill(slots, EMPTY_STACK)
	slots[FURNACE_OUTPUT_SLOT] = Item_Stack{test_item(items, "iron_plate"), 4}
	// Ore into the fuel slot and anything into the output is refused and stays held.
	held := Held_Stack{Item_Stack{hematite, 5}, 0}
	testing.expect_value(t, apply_machine_slot_primary(slots, FURNACE_FUEL_SLOT, filters[FURNACE_FUEL_SLOT], held, items, recipes), held)
	testing.expect_value(t, apply_machine_slot_primary(slots, FURNACE_OUTPUT_SLOT, filters[FURNACE_OUTPUT_SLOT], held, items, recipes), held)
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], EMPTY_STACK)
	held = apply_machine_slot_primary(slots, FURNACE_INPUT_SLOT, filters[FURNACE_INPUT_SLOT], held, items, recipes)
	testing.expect_value(t, slots[FURNACE_INPUT_SLOT], Item_Stack{hematite, 5})
	testing.expect_value(t, held.stack, EMPTY_STACK)
	fuel := Held_Stack{Item_Stack{coal, 3}, 0}
	testing.expect_value(t, apply_machine_slot_primary(slots, FURNACE_INPUT_SLOT, filters[FURNACE_INPUT_SLOT], fuel, items, recipes), fuel)
	fuel = apply_machine_slot_primary(slots, FURNACE_FUEL_SLOT, filters[FURNACE_FUEL_SLOT], fuel, items, recipes)
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], Item_Stack{coal, 3})
	// The output gives with nothing held.
	taken := apply_machine_slot_primary(slots, FURNACE_OUTPUT_SLOT, filters[FURNACE_OUTPUT_SLOT], EMPTY_HELD_STACK, items, recipes)
	testing.expect_value(t, taken, Held_Stack{Item_Stack{test_item(items, "iron_plate"), 4}, MACHINE_SLOT_ORIGIN})
	testing.expect_value(t, slots[FURNACE_OUTPUT_SLOT], EMPTY_STACK)
}
