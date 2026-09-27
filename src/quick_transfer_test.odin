package game

import "core:testing"

// Work item 0078: quick move, move all, and the transfer buttons.

Quick_Transfer_Test :: struct {
	content:   Simulation_Content,
	world:     ^World,
	inventory: Inventory,
}

make_quick_transfer_test :: proc() -> Quick_Transfer_Test {
	content := make_test_content()
	world := new(World, context.temp_allocator)
	world^ = make_floor_world(content.blocks, 32)
	return {content = content, world = world, inventory = make_inventory(PLAYER_INVENTORY_SLOT_COUNT, context.temp_allocator)}
}

quick_transfer_entity :: proc(test: Quick_Transfer_Test, machine: string) -> Entity_Handle {
	return add_entity(&test.world.entities, test.content.machines, test_machine(test.content.machines, machine), {4, 1, 4}, 0)
}

quick_move_stack :: proc(test: Quick_Transfer_Test, handle: Entity_Handle, side: Quick_Move_Side, slot: int) {
	apply_quick_move(&test.world.entities, test.content, handle, test.inventory, {kind = .Stack, target = {side, slot}})
}

@(test)
test_quick_move_into_a_chest_and_back :: proc(t: ^testing.T) {
	test := make_quick_transfer_test()
	chest := quick_transfer_entity(test, "wooden_chest")
	coal := test_item(test.content.items, "coal")
	test.inventory.slots[10] = {coal, 30}
	quick_move_stack(test, chest, .Inventory, 10)
	slots := entity_slots(&test.world.entities, chest)
	testing.expect_value(t, slots[0], Item_Stack{coal, 30})
	testing.expect_value(t, test.inventory.slots[10], EMPTY_STACK)
	// Out again with inventory_add: the hotbar first.
	quick_move_stack(test, chest, .Machine, 0)
	testing.expect_value(t, slots[0], EMPTY_STACK)
	testing.expect_value(t, test.inventory.slots[0], Item_Stack{coal, 30})
}

@(test)
test_quick_move_sorts_fuel_and_ore_into_a_furnace :: proc(t: ^testing.T) {
	test := make_quick_transfer_test()
	furnace := quick_transfer_entity(test, "stone_furnace")
	coal, hematite, plate := test_item(test.content.items, "coal"), test_item(test.content.items, "hematite"), test_item(test.content.items, "iron_plate")
	test.inventory.slots[8] = {coal, 20}
	test.inventory.slots[9] = {hematite, 40}
	test.inventory.slots[10] = {plate, 5}
	quick_move_stack(test, furnace, .Inventory, 8)
	quick_move_stack(test, furnace, .Inventory, 9)
	quick_move_stack(test, furnace, .Inventory, 10)
	slots := entity_slots(&test.world.entities, furnace)
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], Item_Stack{coal, 20})
	testing.expect_value(t, slots[FURNACE_INPUT_SLOT], Item_Stack{hematite, 40})
	// A furnace does not take plates: the stack stays where it was.
	testing.expect_value(t, test.inventory.slots[10], Item_Stack{plate, 5})
	testing.expect_value(t, slots[FURNACE_OUTPUT_SLOT], EMPTY_STACK)
	// What does not fit stays: the input holds 50.
	test.inventory.slots[11] = {hematite, 30}
	quick_move_stack(test, furnace, .Inventory, 11)
	testing.expect_value(t, slots[FURNACE_INPUT_SLOT], Item_Stack{hematite, 50})
	testing.expect_value(t, test.inventory.slots[11], Item_Stack{hematite, 20})
}

@(test)
test_quick_move_fuels_a_drill_and_feeds_a_lab_up_to_the_limit :: proc(t: ^testing.T) {
	test := make_quick_transfer_test()
	drill := quick_transfer_entity(test, "burner_mining_drill")
	coal, stone := test_item(test.content.items, "coal"), test_item(test.content.items, "stone")
	test.inventory.slots[8] = {coal, 12}
	test.inventory.slots[9] = {stone, 12}
	quick_move_stack(test, drill, .Inventory, 8)
	quick_move_stack(test, drill, .Inventory, 9)
	testing.expect_value(t, entity_slots(&test.world.entities, drill)[DRILL_FUEL_SLOT], Item_Stack{coal, 12})
	testing.expect_value(t, test.inventory.slots[9], Item_Stack{stone, 12})
	lab := add_entity(&test.world.entities, test.content.machines, test_machine(test.content.machines, "lab"), {12, 1, 12}, 0)
	pack := test_item(test.content.items, "science_pack_1")
	test.inventory.slots[10] = {pack, 30}
	quick_move_stack(test, lab, .Inventory, 10)
	pack_slot := lab_slot_of(test.content.machines.lab_packs, pack)
	testing.expect_value(t, entity_slots(&test.world.entities, lab)[pack_slot], Item_Stack{pack, INSERTION_LIMIT_CRAFTS})
	testing.expect_value(t, test.inventory.slots[10], Item_Stack{pack, 30 - INSERTION_LIMIT_CRAFTS})
}

@(test)
test_quick_move_all_of_one_item :: proc(t: ^testing.T) {
	test := make_quick_transfer_test()
	chest := quick_transfer_entity(test, "wooden_chest")
	coal, stone := test_item(test.content.items, "coal"), test_item(test.content.items, "stone")
	test.inventory.slots[1] = {coal, 5}
	test.inventory.slots[12] = {coal, 50}
	test.inventory.slots[20] = {stone, 7}
	apply_quick_move(&test.world.entities, test.content, chest, test.inventory, {kind = .All, target = {.Inventory, -1}, item = coal})
	testing.expect_value(t, inventory_count(test.inventory, coal), 0)
	testing.expect_value(t, test.inventory.slots[20], Item_Stack{stone, 7})
	slots := entity_slots(&test.world.entities, chest)
	testing.expect_value(t, chest_total(test.world, chest), 55)
	// The main grid went first, the hotbar last.
	testing.expect_value(t, slots[0], Item_Stack{coal, 50})
	slots[5] = {stone, 3}
	apply_quick_move(&test.world.entities, test.content, chest, test.inventory, {kind = .All, target = {.Machine, -1}, item = coal})
	testing.expect_value(t, inventory_count(test.inventory, coal), 55)
	testing.expect_value(t, slots[5], Item_Stack{stone, 3})
}

@(test)
test_quick_move_press_hold_and_second_press :: proc(t: ^testing.T) {
	coal := Item_Id(3)
	panel := Entity_Handle {
		kind  = .Chest,
		index = 1,
	}
	press := Quick_Move_Input {
		panel   = panel,
		pressed = true,
		down    = true,
		seconds = 0.1,
		found   = true,
		target  = {.Inventory, 12},
		stack   = {coal, 10},
	}
	quick, step := advance_quick_move({}, press)
	testing.expect_value(t, step, Quick_Move_Step{kind = .Stack, target = {.Inventory, 12}, item = coal})
	// Released, then pressed again on the emptied slot: every stack.
	release := Quick_Move_Input {
		panel   = panel,
		seconds = 0.1,
	}
	quick, step = advance_quick_move(quick, release)
	testing.expect_value(t, step.kind, Quick_Move_Kind.None)
	second := press
	second.stack = EMPTY_STACK
	_, step = advance_quick_move(quick, second)
	testing.expect_value(t, step, Quick_Move_Step{kind = .All, target = {.Inventory, -1}, item = coal})
	// On the other side the second press is a new move.
	other := press
	other.target, other.stack = {.Machine, 0}, Item_Stack{coal, 4}
	_, step = advance_quick_move(quick, other)
	testing.expect_value(t, step.kind, Quick_Move_Kind.Stack)
	// Too late for a second press.
	late := release
	late.seconds = QUICK_MOVE_REPEAT_SECONDS
	late_quick, _ := advance_quick_move(quick, late)
	_, step = advance_quick_move(late_quick, second)
	testing.expect_value(t, step.kind, Quick_Move_Kind.None)
	// Held for half a second: every stack, once.
	hold := Quick_Move_Input {
		panel   = panel,
		down    = true,
		seconds = 0.25,
	}
	quick, step = advance_quick_move({}, press)
	quick, step = advance_quick_move(quick, hold)
	testing.expect_value(t, step.kind, Quick_Move_Kind.None)
	quick, step = advance_quick_move(quick, hold)
	testing.expect_value(t, step, Quick_Move_Step{kind = .All, target = {.Inventory, -1}, item = coal})
	quick, step = advance_quick_move(quick, hold)
	testing.expect_value(t, step.kind, Quick_Move_Kind.None)
}

@(test)
test_quick_move_target_prefers_the_activated_slot :: proc(t: ^testing.T) {
	target, found := quick_move_target({activated = -1, focused = 3}, {activated = 2, focused = -1})
	testing.expect(t, found)
	testing.expect_value(t, target, Quick_Move_Target{.Machine, 2})
	target, found = quick_move_target({activated = -1, focused = 3}, {activated = -1, focused = -1})
	testing.expect_value(t, target, Quick_Move_Target{.Inventory, 3})
	_, found = quick_move_target({activated = -1, focused = -1}, {activated = -1, focused = -1})
	testing.expect(t, !found)
}

@(test)
test_take_all_and_store_all :: proc(t: ^testing.T) {
	test := make_quick_transfer_test()
	chest := quick_transfer_entity(test, "wooden_chest")
	coal, stone, hematite := test_item(test.content.items, "coal"), test_item(test.content.items, "stone"), test_item(test.content.items, "hematite")
	slots := entity_slots(&test.world.entities, chest)
	slots[3] = {hematite, 10}
	test.inventory.slots[0] = {hematite, 4}
	test.inventory.slots[2] = {coal, 6}
	test.inventory.slots[9] = {stone, 8}
	test.inventory.slots[15] = {hematite, 9}
	// Matching items first, the main grid before the hotbar.
	order := store_all_order(test.inventory, slots)
	testing.expect_value(t, len(order), 4)
	testing.expect_value(t, order[0], 15)
	testing.expect_value(t, order[1], 9)
	testing.expect_value(t, order[2], 0)
	testing.expect_value(t, order[3], 2)
	apply_transfer_button(&test.world.entities, test.content, chest, test.inventory, .Store_All)
	testing.expect_value(t, slots[3], Item_Stack{hematite, 23})
	testing.expect_value(t, chest_total(test.world, chest), 37)
	for slot in test.inventory.slots {
		testing.expect(t, stack_is_empty(slot))
	}
	apply_transfer_button(&test.world.entities, test.content, chest, test.inventory, .Take_All)
	testing.expect_value(t, chest_total(test.world, chest), 0)
	testing.expect_value(t, inventory_count(test.inventory, hematite), 23)
	testing.expect_value(t, inventory_count(test.inventory, coal), 6)
	testing.expect_value(t, inventory_count(test.inventory, stone), 8)
	// Take all on a furnace takes only its outputs.
	furnace := quick_transfer_entity(test, "stone_furnace")
	furnace_slots := entity_slots(&test.world.entities, furnace)
	plate := test_item(test.content.items, "iron_plate")
	furnace_slots[FURNACE_OUTPUT_SLOT] = {plate, 12}
	furnace_slots[FURNACE_FUEL_SLOT] = {coal, 3}
	apply_transfer_button(&test.world.entities, test.content, furnace, test.inventory, .Take_All)
	testing.expect_value(t, furnace_slots[FURNACE_OUTPUT_SLOT], EMPTY_STACK)
	testing.expect_value(t, furnace_slots[FURNACE_FUEL_SLOT], Item_Stack{coal, 3})
	testing.expect_value(t, inventory_count(test.inventory, plate), 12)
}

@(test)
test_take_all_leaves_what_does_not_fit :: proc(t: ^testing.T) {
	test := make_quick_transfer_test()
	chest := quick_transfer_entity(test, "wooden_chest")
	stone, coal := test_item(test.content.items, "stone"), test_item(test.content.items, "coal")
	for &slot in test.inventory.slots {
		slot = {stone, 50}
	}
	test.inventory.slots[5] = {coal, 45}
	slots := entity_slots(&test.world.entities, chest)
	slots[0] = {coal, 20}
	apply_transfer_button(&test.world.entities, test.content, chest, test.inventory, .Take_All)
	testing.expect_value(t, test.inventory.slots[5], Item_Stack{coal, 50})
	testing.expect_value(t, slots[0], Item_Stack{coal, 15})
}

@(test)
test_fill_fuel_and_lab_packs :: proc(t: ^testing.T) {
	test := make_quick_transfer_test()
	furnace := quick_transfer_entity(test, "stone_furnace")
	coal, hematite := test_item(test.content.items, "coal"), test_item(test.content.items, "hematite")
	test.inventory.slots[0] = {coal, 40}
	test.inventory.slots[9] = {hematite, 20}
	test.inventory.slots[10] = {coal, 30}
	apply_transfer_button(&test.world.entities, test.content, furnace, test.inventory, .Fill)
	slots := entity_slots(&test.world.entities, furnace)
	// The main grid first, up to the stack size; the ore stays.
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], Item_Stack{coal, 50})
	testing.expect_value(t, slots[FURNACE_INPUT_SLOT], EMPTY_STACK)
	testing.expect_value(t, test.inventory.slots[10], EMPTY_STACK)
	testing.expect_value(t, test.inventory.slots[0], Item_Stack{coal, 20})
	testing.expect_value(t, test.inventory.slots[9], Item_Stack{hematite, 20})
	lab := add_entity(&test.world.entities, test.content.machines, test_machine(test.content.machines, "lab"), {12, 1, 12}, 0)
	first, second := test.content.machines.lab_packs[0], test.content.machines.lab_packs[1]
	test.inventory.slots[11] = {first, 10}
	test.inventory.slots[12] = {second, 1}
	apply_transfer_button(&test.world.entities, test.content, lab, test.inventory, .Fill)
	lab_slots := entity_slots(&test.world.entities, lab)
	testing.expect_value(t, lab_slots[0], Item_Stack{first, INSERTION_LIMIT_CRAFTS})
	testing.expect_value(t, lab_slots[1], Item_Stack{second, 1})
	testing.expect_value(t, test.inventory.slots[11], Item_Stack{first, 10 - INSERTION_LIMIT_CRAFTS})
}

@(test)
test_transfer_buttons_per_machine :: proc(t: ^testing.T) {
	content := make_test_content()
	machine :: proc(content: Simulation_Content, id: string) -> Machine {
		return content.machines.machines[test_machine(content.machines, id)]
	}
	testing.expect_value(t, machine_transfer_buttons(machine(content, "wooden_chest")), Transfer_Buttons{.Take_All, .Store_All})
	testing.expect_value(t, machine_transfer_buttons(machine(content, "stone_furnace")), Transfer_Buttons{.Take_All, .Fill})
	testing.expect_value(t, machine_transfer_buttons(machine(content, "burner_mining_drill")), Transfer_Buttons{.Fill})
	testing.expect_value(t, machine_transfer_buttons(machine(content, "electric_mining_drill")), Transfer_Buttons{})
	testing.expect_value(t, machine_transfer_buttons(machine(content, "lab")), Transfer_Buttons{.Fill})
	testing.expect_value(t, machine_transfer_buttons(machine(content, "recycler")), Transfer_Buttons{.Take_All})
	testing.expect_value(t, machine_transfer_buttons(machine(content, "pipe")), Transfer_Buttons{})
	testing.expect_value(t, transfer_rows_height(machine(content, "wooden_chest"), 400), f32(UI_ROW_HEIGHT + UI_GAP))
	testing.expect_value(t, transfer_rows_height(machine(content, "wooden_chest"), 200), f32(2 * (UI_ROW_HEIGHT + UI_GAP)))
}
