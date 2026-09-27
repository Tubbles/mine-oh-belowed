package game

import "core:testing"

@(test)
test_transfer_into_and_out_of_a_chest :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	chest := add_entity(&world.entities, content.machines, test_machine(content.machines, "wooden_chest"), {4, 1, 4}, 0)
	coal := test_item(content.items, "coal")
	slot, ok := entity_accepts(&world.entities, content, chest, coal)
	testing.expect(t, ok)
	testing.expect_value(t, slot, 0)
	testing.expect_value(t, entity_insert(&world.entities, content, chest, Item_Stack{coal, 60}), EMPTY_STACK)
	slots := entity_slots(&world.entities, chest)
	testing.expect_value(t, slots[0], Item_Stack{coal, 50})
	testing.expect_value(t, slots[1], Item_Stack{coal, 10})
	slot, _ = entity_accepts(&world.entities, content, chest, coal)
	testing.expect_value(t, slot, 1)
	testing.expect_value(t, entity_extract(&world.entities, content, chest, NO_ITEM, 1), Item_Stack{coal, 1})
	testing.expect_value(t, entity_extract(&world.entities, content, chest, test_item(content.items, "stone"), 1), EMPTY_STACK)
	testing.expect_value(t, slots[0], Item_Stack{coal, 49})
}

@(test)
test_transfer_respects_furnace_slots :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	furnace := add_entity(&world.entities, content.machines, test_machine(content.machines, "stone_furnace"), {4, 1, 4}, 0)
	coal, hematite, plate := test_item(content.items, "coal"), test_item(content.items, "hematite"), test_item(content.items, "iron_plate")
	slot, ok := entity_accepts(&world.entities, content, furnace, coal)
	testing.expect(t, ok)
	testing.expect_value(t, slot, FURNACE_FUEL_SLOT)
	slot, ok = entity_accepts(&world.entities, content, furnace, hematite)
	testing.expect_value(t, slot, FURNACE_INPUT_SLOT)
	_, ok = entity_accepts(&world.entities, content, furnace, plate)
	testing.expect(t, !ok)
	testing.expect_value(t, entity_insert(&world.entities, content, furnace, Item_Stack{plate, 3}), Item_Stack{plate, 3})
	testing.expect_value(t, entity_insert(&world.entities, content, furnace, Item_Stack{hematite, 60}), Item_Stack{hematite, 10})
	testing.expect_value(t, entity_insert(&world.entities, content, furnace, Item_Stack{coal, 5}), EMPTY_STACK)
	// A log smelts to charcoal and burns: it goes to the input first.
	slots := entity_slots(&world.entities, furnace)
	slots[FURNACE_INPUT_SLOT] = EMPTY_STACK
	slot, _ = entity_accepts(&world.entities, content, furnace, test_item(content.items, "log"))
	testing.expect_value(t, slot, FURNACE_INPUT_SLOT)
	// Only the output slot gives.
	testing.expect_value(t, entity_extract(&world.entities, content, furnace, NO_ITEM, 10), EMPTY_STACK)
	slots[FURNACE_OUTPUT_SLOT] = Item_Stack{plate, 4}
	testing.expect_value(t, entity_extract(&world.entities, content, furnace, NO_ITEM, 1), Item_Stack{plate, 1})
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], Item_Stack{coal, 5})
}

@(test)
test_transfer_into_the_capsule_and_onto_a_belt :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	world.entities.capsules.entries = make([dynamic]Capsule, context.temp_allocator)
	world.entities.capsules.free = make([dynamic]u32, context.temp_allocator)
	capsule := place_capsule(&world.entities, content.machines, Landing_Pad_Site{present = true, centre = {10, 0, 10}})
	plate := test_item(content.items, "iron_plate")
	testing.expect_value(t, entity_insert(&world.entities, content, capsule, Item_Stack{plate, 7}), EMPTY_STACK)
	testing.expect_value(t, entity_extract(&world.entities, content, capsule, plate, 50), Item_Stack{plate, 7})
	belts := lay_belt_row(&world, content, {0, 1, 0}, 2, 0)
	slot, ok := entity_accepts(&world.entities, content, belts[1], plate, .Right)
	testing.expect(t, ok)
	testing.expect_value(t, slot, int(Belt_Lane.Right))
	// A belt takes one item at a time, mid block, while there is room.
	testing.expect_value(t, entity_insert(&world.entities, content, belts[1], Item_Stack{plate, 5}, .Right), Item_Stack{plate, 4})
	testing.expect_value(t, entity_insert(&world.entities, content, belts[1], Item_Stack{plate, 5}, .Right), Item_Stack{plate, 5})
	_, ok = entity_accepts(&world.entities, content, belts[1], plate, .Right)
	testing.expect(t, !ok)
	coal := test_item(content.items, "coal")
	testing.expect_value(t, entity_insert(&world.entities, content, belts[1], Item_Stack{coal, 1}, .Left), EMPTY_STACK)
	// Extract takes the item nearest the middle, honouring the filter.
	testing.expect_value(t, entity_extract(&world.entities, content, belts[1], coal, 1), Item_Stack{coal, 1})
	testing.expect_value(t, entity_extract(&world.entities, content, belts[0], NO_ITEM, 1), EMPTY_STACK)
	testing.expect_value(t, entity_extract(&world.entities, content, belts[1], NO_ITEM, 1), Item_Stack{plate, 1})
	testing.expect_value(t, len(line_of(&world, belts[1]).lanes[.Right]), 0)
}
