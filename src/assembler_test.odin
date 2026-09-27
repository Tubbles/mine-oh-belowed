package game

import "core:testing"

test_assembler :: proc(world: ^World, handle: Entity_Handle) -> ^Assembler {
	return pool_get(&world.entities.assemblers, handle)
}

// A recipe with a byproduct: two plates and a copper plate make a gear
// and a gravel.
make_byproduct_recipes :: proc() -> Recipe_Registry {
	definition := test_recipe_definition()
	definition.id = "gear_with_scrap"
	definition.inputs = {{item = "iron_plate", count = 2}, {item = "copper_plate", count = 1}}
	definition.outputs = {{item = "iron_gear", count = 1}, {item = "gravel", count = 1}}
	definition.made_in = {"assembler"}
	definition.seconds = 1
	registry, problem := resolve_recipe_registry(Recipes_File{recipes = {definition}}, make_test_items(), context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

// A powered assembler holding the recipe, outside any world.
make_powered_assembler :: proc(recipes: Recipe_Registry, recipe: int) -> Assembler {
	assembler := make_assembler({})
	set_assembler_recipe(&assembler, recipes, recipe)
	assembler.power.satisfaction = POWER_FULL
	return assembler
}

@(test)
test_assembler_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	assembler := content.machines.machines[test_machine(content.machines, "assembler_1")]
	testing.expect_value(t, assembler.kind, Machine_Kind.Assembler)
	testing.expect_value(t, assembler.footprint, [3]i32{3, 2, 3})
	testing.expect_value(t, assembler.speed_percent, 50)
	testing.expect_value(t, assembler.electric_power_watts, 75_000)
	testing.expect_value(t, assembler.item, test_item(content.items, "assembler_1"))
	// Science pack 1 is 5 s: 10 s at speed 0.5, six a minute.
	science := content.recipes.recipes[test_recipe(content.recipes, "science_pack_1")]
	testing.expect(t, recipe_fits_assembler(science))
	testing.expect_value(t, recipe_ticks(science, assembler.speed_percent, TEST_TICK_RATE), 600)
	// Furnace only recipes are not for the assembler.
	testing.expect(t, !recipe_fits_assembler(content.recipes.recipes[test_recipe(content.recipes, "iron_plate")]))
}

@(test)
test_assembler_slots_follow_the_recipe :: proc(t: ^testing.T) {
	recipes := make_byproduct_recipes()
	items := make_test_items()
	assembler := make_assembler({})
	testing.expect_value(t, assembler_slot_count(assembler), 0)
	testing.expect_value(t, assembler.recipe, NO_RECIPE)
	set_assembler_recipe(&assembler, recipes, 0)
	testing.expect_value(t, assembler.input_count, 2)
	testing.expect_value(t, assembler.output_count, 2)
	plate, copper, gravel := test_item(items, "iron_plate"), test_item(items, "copper_plate"), test_item(items, "gravel")
	testing.expect_value(t, assembler_input_slot_of(assembler, recipes, plate), 0)
	testing.expect_value(t, assembler_input_slot_of(assembler, recipes, copper), 1)
	testing.expect_value(t, assembler_input_slot_of(assembler, recipes, gravel), -1)
	filters := assembler_slot_filters(assembler, recipes)
	testing.expect_value(t, len(filters), 4)
	testing.expect_value(t, filters[0], Slot_Filter{kind = .Item, item = plate})
	testing.expect_value(t, filters[1], Slot_Filter{kind = .Item, item = copper})
	testing.expect_value(t, filters[2].kind, Slot_Filter_Kind.Output)
	testing.expect_value(t, filters[3].kind, Slot_Filter_Kind.Output)
	testing.expect(t, slot_accepts(filters[0], plate, items, recipes))
	testing.expect(t, !slot_accepts(filters[0], copper, items, recipes))
	testing.expect(t, !slot_accepts(filters[2], plate, items, recipes))
}

@(test)
test_assembler_crafts_with_byproducts :: proc(t: ^testing.T) {
	recipes := make_byproduct_recipes()
	content := make_test_content()
	items := content.items
	machine := content.machines.machines[test_machine(content.machines, "assembler_1")]
	assembler := make_powered_assembler(recipes, 0)
	plate, copper := test_item(items, "iron_plate"), test_item(items, "copper_plate")
	gear, gravel := test_item(items, "iron_gear"), test_item(items, "gravel")
	testing.expect(t, !advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE))
	testing.expect_value(t, assembler.state, Assembler_State.Missing_Ingredients)
	assembler.slots[0] = {plate, 5}
	assembler.slots[1] = {copper, 2}
	// 1 s at speed 0.5 is 120 ticks; the ingredients go on the first.
	testing.expect(t, !advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE))
	testing.expect_value(t, assembler.state, Assembler_State.Working)
	testing.expect_value(t, assembler.slots[0], Item_Stack{plate, 3})
	testing.expect_value(t, assembler.slots[1], Item_Stack{copper, 1})
	for _ in 1 ..< 119 {
		testing.expect(t, !advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE))
	}
	testing.expect(t, advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE))
	testing.expect_value(t, assembler.slots[2], Item_Stack{gear, 1})
	testing.expect_value(t, assembler.slots[3], Item_Stack{gravel, 1})
	// A second craft, then the copper runs out.
	for _ in 0 ..< 120 {
		advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE)
	}
	testing.expect_value(t, assembler.slots[2], Item_Stack{gear, 2})
	advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE)
	testing.expect_value(t, assembler.state, Assembler_State.Missing_Ingredients)
	testing.expect_value(t, assembler.slots[0], Item_Stack{plate, 1})
}

@(test)
test_assembler_waits_for_power_and_room :: proc(t: ^testing.T) {
	recipes := make_byproduct_recipes()
	content := make_test_content()
	items := content.items
	machine := content.machines.machines[test_machine(content.machines, "assembler_1")]
	assembler := make_powered_assembler(recipes, 0)
	plate, copper, gravel := test_item(items, "iron_plate"), test_item(items, "copper_plate"), test_item(items, "gravel")
	assembler.slots[0] = {plate, 2}
	assembler.slots[1] = {copper, 1}
	// A full byproduct slot stops the start and keeps the ingredients.
	assembler.slots[3] = {gravel, item_stack_size(items, gravel)}
	advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE)
	testing.expect_value(t, assembler.state, Assembler_State.Output_Full)
	testing.expect_value(t, assembler.slots[0], Item_Stack{plate, 2})
	assembler.slots[3] = EMPTY_STACK
	assembler.power.satisfaction = 0
	advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE)
	testing.expect_value(t, assembler.state, Assembler_State.No_Power)
	testing.expect(t, !assembler.working)
	// Half power: the craft takes twice as long.
	assembler.power.satisfaction = POWER_FULL / 2
	ticks := 0
	for !advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE) {
		ticks += 1
	}
	testing.expect_value(t, ticks + 1, 240)
	// No recipe.
	set_assembler_recipe(&assembler, recipes, NO_RECIPE)
	advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE)
	testing.expect_value(t, assembler.state, Assembler_State.No_Recipe)
	testing.expect(t, !assembler_wants_power(assembler, recipes, items))
}

@(test)
test_assembler_recipe_change_returns_contents :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	inventory := make_inventory(PLAYER_INVENTORY_SLOT_COUNT, context.temp_allocator)
	science := test_recipe(recipes, "science_pack_1")
	gear_recipe := test_recipe(recipes, "iron_gear")
	assembler := make_powered_assembler(recipes, science)
	copper, gear, plate := test_item(items, "copper_plate"), test_item(items, "iron_gear"), test_item(items, "iron_plate")
	assembler.slots[0] = {copper, 3}
	assembler.slots[1] = {gear, 2}
	machine := content.machines.machines[test_machine(content.machines, "assembler_1")]
	advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE)
	testing.expect(t, assembler.working)
	// A furnace recipe is refused.
	testing.expect_value(t, change_assembler_recipe(&assembler, inventory, items, recipes, test_recipe(recipes, "iron_plate")), Recipe_Change_Refusal.Not_For_Assembler)
	// The slots and the craft in progress come back.
	testing.expect_value(t, change_assembler_recipe(&assembler, inventory, items, recipes, gear_recipe), Recipe_Change_Refusal.None)
	testing.expect_value(t, inventory_count(inventory, copper), 3)
	testing.expect_value(t, inventory_count(inventory, gear), 2)
	testing.expect_value(t, assembler.recipe, gear_recipe)
	testing.expect_value(t, assembler_slot_count(assembler), 2)
	testing.expect(t, !assembler.working)
	// A full inventory refuses and nothing moves.
	assembler.slots[0] = {plate, 10}
	for &slot in inventory.slots {
		slot = {test_item(items, "stone"), item_stack_size(items, test_item(items, "stone"))}
	}
	testing.expect_value(t, change_assembler_recipe(&assembler, inventory, items, recipes, science), Recipe_Change_Refusal.Contents_Do_Not_Fit)
	testing.expect_value(t, assembler.recipe, gear_recipe)
	testing.expect_value(t, assembler.slots[0], Item_Stack{plate, 10})
}

// The shipped science pack recipe in a powered assembler: six a minute.
@(test)
test_assembler_makes_science_packs :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	machine := content.machines.machines[test_machine(content.machines, "assembler_1")]
	assembler := make_powered_assembler(recipes, test_recipe(recipes, "science_pack_1"))
	assembler.slots[0] = {test_item(items, "copper_plate"), 20}
	assembler.slots[1] = {test_item(items, "iron_gear"), 20}
	made := 0
	for _ in 0 ..< 60 * TEST_TICK_RATE {
		if advance_assembler(&assembler, machine, items, recipes, TEST_TICK_RATE) {
			made += 1
		}
	}
	testing.expect_value(t, made, 6)
	testing.expect_value(t, assembler.slots[2], Item_Stack{test_item(items, "science_pack_1"), 6})
}

// The transfer interface puts each ingredient in its slot and gives only
// from the outputs.
@(test)
test_assembler_routes_ingredients :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	handle := place_test_entity(&world, content, "assembler_1", {1, 1, -1})
	assembler := test_assembler(&world, handle)
	items := content.items
	copper, gear, plate := test_item(items, "copper_plate"), test_item(items, "iron_gear"), test_item(items, "iron_plate")
	// Without a recipe it takes nothing.
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, handle, copper))
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {copper, 1}), Item_Stack{copper, 1})
	set_assembler_recipe(assembler, content.recipes, test_recipe(content.recipes, "science_pack_1"))
	testing.expect(t, entity_takes_item_kind(&world.entities, content, handle, copper))
	testing.expect(t, entity_takes_item_kind(&world.entities, content, handle, gear))
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, handle, plate))
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {gear, 5}), EMPTY_STACK)
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {copper, 4}), EMPTY_STACK)
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {plate, 4}), Item_Stack{plate, 4})
	testing.expect_value(t, assembler.slots[0], Item_Stack{copper, 4})
	testing.expect_value(t, assembler.slots[1], Item_Stack{gear, 5})
	// Inputs are never given back; outputs are.
	testing.expect_value(t, len(entity_offered_items(&world.entities, handle, NO_ITEM)), 0)
	testing.expect_value(t, entity_extract(&world.entities, content, handle, NO_ITEM, 5), EMPTY_STACK)
	pack := test_item(items, "science_pack_1")
	assembler.slots[2] = {pack, 3}
	testing.expect_value(t, entity_extract(&world.entities, content, handle, NO_ITEM, 1), Item_Stack{pack, 1})
	_, accepted := entity_accepts(&world.entities, content, handle, pack)
	testing.expect(t, !accepted)
}

// Inserters feed plates from a chest into an assembler making gears, and
// take the gears out into another chest; everything shifted by offset.
lay_gear_line_at :: proc(world: ^World, content: Simulation_Content, offset: World_Coordinate) -> (source, assembler, target: Entity_Handle) {
	source = place_test_entity(world, content, "wooden_chest", World_Coordinate{-1, 1, 0} + offset)
	place_fuelled_inserter(world, content, World_Coordinate{0, 1, 0} + offset, 0)
	assembler = place_test_entity(world, content, "assembler_1", World_Coordinate{1, 1, -1} + offset)
	place_fuelled_inserter(world, content, World_Coordinate{4, 1, 0} + offset, 0)
	target = place_test_entity(world, content, "wooden_chest", World_Coordinate{5, 1, 0} + offset)
	add_test_power_plant(world, content, World_Coordinate{2, 1, 3} + offset, World_Coordinate{3, 1, 3} + offset)
	set_assembler_recipe(test_assembler(world, assembler), content.recipes, test_recipe(content.recipes, "iron_gear"))
	entity_insert(&world.entities, content, source, {test_item(content.items, "iron_plate"), 40})
	return
}

@(test)
test_inserters_feed_an_assembler :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	world.statistics = make_statistics(len(content.items.items), len(content.machines.machines), len(content.blocks.definitions), context.temp_allocator)
	source, handle, target := lay_gear_line_at(&world, content, {})
	testing.expect(t, entity_network(&world.entities.electric_networks, handle) >= 0)
	tick_test_entities(&world, content, 1200)
	gear := test_item(content.items, "iron_gear")
	plate := test_item(content.items, "iron_plate")
	assembler := test_assembler(&world, handle)
	// A plate every 100 ticks from tick 51, so twelve plates; a gear 60
	// ticks after every second plate, five by tick 1200 (the sixth starts
	// at 1151), and the output inserter a cycle behind.
	testing.expect_value(t, chest_count_of(&world, source, plate), 28)
	testing.expect(t, chest_count_of(&world, target, gear) >= 4)
	testing.expect_value(t, item_counter(world.statistics.produced, gear), 5)
	testing.expect_value(t, chest_count_of(&world, target, gear) + slots_count_of(assembler.slots[:], gear), 5)
	testing.expect(t, assembler.working)
}
