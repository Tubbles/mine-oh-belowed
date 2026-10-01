package game

import "core:strings"
import "core:testing"

// Work item 0027: slag and the byproduct uses, the byproduct strictness
// setting, the recycler, and concrete and brick blocks.

@(test)
test_smelting_and_alloys_give_slag :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	slag := test_item(items, "slag")
	testing.expect_value(t, item_stack_size(items, slag), 100)
	with_slag := [?]string{"iron_plate", "copper_plate", "tin_plate", "lead_plate", "zinc_plate", "nickel_plate", "bronze_plate", "brass_plate", "steel"}
	for id in with_slag {
		recipe := recipes.recipes[test_recipe(recipes, id)]
		testing.expectf(t, len(recipe.outputs) == 2 && recipe.outputs[1] == Item_Stack{slag, 1}, "%s gives %v", id, recipe.outputs)
		testing.expectf(t, recipe.byproducts == {1}, "%s byproducts %v", id, recipe.byproducts)
	}
	for recipe in recipes.recipes {
		if .Alloy_Furnace in recipe.made_in {
			testing.expectf(t, stacks_contain_item(recipe.outputs, slag), "alloy %s gives no slag", recipe.id)
		}
	}
	slag_free := [?]string{"stone_brick", "charcoal", "glass", "clay", "brick"}
	for id in slag_free {
		recipe := recipes.recipes[test_recipe(recipes, id)]
		testing.expectf(t, len(recipe.outputs) == 1 && recipe.byproducts == {}, "%s gives %v", id, recipe.outputs)
	}
	// Gravel from crushing and mud from washing are byproducts too.
	for id in ([?]string{"crush_hematite", "wash_hematite"}) {
		testing.expect_value(t, recipes.recipes[test_recipe(recipes, id)].byproducts, Recipe_Output_Set{1})
	}
	// Crushing and washing recover the ore: 2 low grade give 2 crushed,
	// 1 crushed gives 1 ore.
	crush := recipes.recipes[test_recipe(recipes, "crush_hematite")]
	testing.expect_value(t, crush.outputs[0], Item_Stack{test_item(items, "crushed_hematite"), 2})
	testing.expect_value(t, crush.outputs[1], Item_Stack{test_item(items, "gravel"), 1})
}

@(test)
test_byproduct_flags_are_validated :: proc(t: ^testing.T) {
	flagged_input := test_recipe_definition()
	flagged_input.inputs = {{item = "log", count = 1, byproduct = true}}
	testing.expect(t, strings.contains(resolve_test_recipes({flagged_input}), "input as a byproduct"))
	only_byproducts := test_recipe_definition()
	only_byproducts.outputs = {{item = "plank", count = 4, byproduct = true}}
	testing.expect(t, strings.contains(resolve_test_recipes({only_byproducts}), "only byproduct"))
	// A furnace recipe: one main output, at most one byproduct after it.
	smelt := test_recipe_definition()
	smelt.inputs = {{item = "hematite", count = 1}}
	smelt.outputs = {{item = "iron_plate", count = 1}, {item = "slag", count = 1, byproduct = true}}
	smelt.made_in = {"furnace"}
	testing.expect_value(t, resolve_test_recipes({smelt}), "")
	two_main := smelt
	two_main.outputs = {{item = "iron_plate", count = 1}, {item = "slag", count = 1}}
	testing.expect(t, strings.contains(resolve_test_recipes({two_main}), "exactly one input"))
	byproduct_first := smelt
	byproduct_first.outputs = {{item = "slag", count = 1, byproduct = true}, {item = "iron_plate", count = 1}}
	testing.expect(t, resolve_test_recipes({byproduct_first}) != "")
	// No recipe is made in the recycler.
	recycled := test_recipe_definition()
	recycled.made_in = {"recycler"}
	testing.expect(t, resolve_test_recipes({recycled}) != "")
}

// A furnace smelting hematite at speed 1 with fuel and an outlet for its
// plates but none for its slag.
Slag_Line :: struct {
	content:    Simulation_Content,
	machine:    Machine,
	furnace:    Furnace,
	statistics: Statistics,
}

make_slag_line :: proc() -> Slag_Line {
	content := make_test_content()
	machine := test_machine(content.machines, "stone_furnace")
	return Slag_Line {
		content = content,
		machine = content.machines.machines[machine],
		furnace = make_furnace(Entity_Common{machine = machine}),
		statistics = make_statistics(len(content.items.items), len(content.machines.machines), 4, context.temp_allocator),
	}
}

run_slag_line :: proc(line: ^Slag_Line, ticks: int, lenient: bool) {
	items := line.content.items
	for _ in 0 ..< ticks {
		line.furnace.slots[FURNACE_FUEL_SLOT] = {test_item(items, "coal"), 10}
		line.furnace.slots[FURNACE_INPUT_SLOT] = {test_item(items, "hematite"), 10}
		line.furnace.slots[FURNACE_OUTPUT_SLOT] = EMPTY_STACK
		before := line.furnace
		line.furnace = advance_furnace(line.furnace, line.machine, items, line.content.recipes, TEST_TICK_RATE, lenient)
		record_furnace_tick(&line.statistics, before, line.furnace, line.content.recipes)
	}
}

// Strict: slag fills its slot after 100 plates (5.3 minutes at speed 1)
// and the furnace stalls with the plate outlet still free.
@(test)
test_strict_furnace_stalls_on_slag :: proc(t: ^testing.T) {
	line := make_slag_line()
	slag, plate := test_item(line.content.items, "slag"), test_item(line.content.items, "iron_plate")
	crafts_to_fill := 100
	run_slag_line(&line, crafts_to_fill * 192, false)
	testing.expect_value(t, line.furnace.slots[FURNACE_BYPRODUCT_SLOT], Item_Stack{slag, 100})
	testing.expect_value(t, line.furnace.state, Furnace_State.Burning)
	run_slag_line(&line, 1, false)
	testing.expect_value(t, line.furnace.state, Furnace_State.Output_Full)
	testing.expect(t, crafts_to_fill * 192 <= 6 * 60 * TEST_TICK_RATE)
	run_slag_line(&line, 600, false)
	testing.expect_value(t, line.furnace.progress_ticks, 0)
	testing.expect_value(t, line.statistics.produced[plate], 100)
	testing.expect_value(t, line.statistics.produced[slag], 100)
	testing.expect_value(t, line.statistics.voided[slag], 0)
	testing.expect_value(t, line.statistics.stalls[.Output_Full], 1)
	// Taking the slag out lets it go on.
	line.furnace.slots[FURNACE_BYPRODUCT_SLOT] = EMPTY_STACK
	run_slag_line(&line, 192, false)
	testing.expect_value(t, line.furnace.slots[FURNACE_BYPRODUCT_SLOT], Item_Stack{slag, 1})
}

// Lenient: the furnace smelts on and voids the slag that has no room.
@(test)
test_lenient_furnace_voids_slag :: proc(t: ^testing.T) {
	line := make_slag_line()
	slag, plate := test_item(line.content.items, "slag"), test_item(line.content.items, "iron_plate")
	run_slag_line(&line, 110 * 192, true)
	testing.expect_value(t, line.furnace.state, Furnace_State.Burning)
	testing.expect_value(t, line.furnace.slots[FURNACE_BYPRODUCT_SLOT], Item_Stack{slag, 100})
	testing.expect_value(t, line.statistics.produced[plate], 110)
	testing.expect_value(t, line.statistics.produced[slag], 100)
	testing.expect_value(t, line.statistics.voided[slag], 10)
	testing.expect_value(t, line.statistics.stalls[.Output_Full], 0)
	// The main output still waits for room.
	line.furnace.slots[FURNACE_OUTPUT_SLOT] = {plate, 50}
	line.furnace = advance_furnace(line.furnace, line.machine, line.content.items, line.content.recipes, TEST_TICK_RATE, true)
	testing.expect_value(t, line.furnace.state, Furnace_State.Output_Full)
}

// An alloy furnace in a world whose slag slot is full: strict stalls,
// lenient reads the world setting and voids the slag at completion.
alloy_furnace_with_full_slag :: proc(content: Simulation_Content, lenient: bool) -> (world: World, records: Game_Records, furnace: ^Assembler) {
	world = make_floor_world(content.blocks, 32)
	records = make_test_records(content)
	world.settings.byproducts_lenient = lenient
	handle := place_test_entity(&world, content, "alloy_furnace", {1, 1, 0})
	furnace = pool_get(&world.entities.assemblers, handle)
	items := content.items
	furnace.slots[0] = {test_item(items, "coal"), 5}
	furnace.slots[1] = {test_item(items, "copper_plate"), 3}
	furnace.slots[2] = {test_item(items, "tin_plate"), 1}
	furnace.slots[4] = {test_item(items, "slag"), 100}
	return
}

@(test)
test_crafting_machine_byproduct_strictness :: proc(t: ^testing.T) {
	content := make_test_content()
	bronze, slag := test_item(content.items, "bronze_plate"), test_item(content.items, "slag")
	strict_world, strict_records, strict := alloy_furnace_with_full_slag(content, false)
	tick_test_entities(&strict_world, &strict_records, content, 400)
	testing.expect_value(t, strict.state, Assembler_State.Output_Full)
	testing.expect_value(t, strict.slots[3], EMPTY_STACK)
	testing.expect_value(t, strict_records.statistics.stalls[.Crafting_Output_Full], 1)
	lenient_world, lenient_records, lenient := alloy_furnace_with_full_slag(content, true)
	tick_test_entities(&lenient_world, &lenient_records, content, 400)
	testing.expect_value(t, lenient.slots[3], Item_Stack{bronze, 4})
	testing.expect_value(t, lenient.slots[4], Item_Stack{slag, 100})
	testing.expect_value(t, lenient_records.statistics.produced[bronze], 4)
	testing.expect_value(t, lenient_records.statistics.produced[slag], 0)
	testing.expect_value(t, lenient_records.statistics.voided[slag], 1)
	// It lit coal, and ran out of ingredients after the craft.
	testing.expect_value(t, lenient_records.statistics.fuel_burned, 1)
	testing.expect_value(t, lenient_records.statistics.stalls[.Crafting_Missing_Input], 1)
	// The main output still waits under lenient.
	lenient.slots[1] = {test_item(content.items, "copper_plate"), 3}
	lenient.slots[2] = {test_item(content.items, "tin_plate"), 1}
	lenient.slots[3] = {bronze, 48}
	tick_test_entities(&lenient_world, &lenient_records, content, 1)
	testing.expect_value(t, lenient.state, Assembler_State.Output_Full)
	testing.expect_value(t, lenient_records.statistics.stalls[.Crafting_Output_Full], 1)
}

@(test)
test_crafting_machine_stalls_are_counted :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	records.statistics = make_statistics(len(content.items.items), len(content.machines.machines), len(content.blocks.definitions), context.temp_allocator)
	handle := place_test_entity(&world, content, "crusher", {1, 1, 0})
	crusher := pool_get(&world.entities.assemblers, handle)
	crusher.slots[0] = {test_item(content.items, "hematite_low_grade"), 2}
	// No pole: the crusher has no power.
	tick_test_entities(&world, &records, content, 10)
	testing.expect_value(t, crusher.state, Assembler_State.No_Power)
	testing.expect_value(t, records.statistics.stalls[.Crafting_No_Power], 1)
	furnace := place_test_entity(&world, content, "alloy_furnace", {5, 1, 0})
	alloy := pool_get(&world.entities.assemblers, furnace)
	alloy.slots[1] = {test_item(content.items, "copper_plate"), 3}
	alloy.slots[2] = {test_item(content.items, "tin_plate"), 1}
	tick_test_entities(&world, &records, content, 1)
	testing.expect_value(t, alloy.state, Assembler_State.No_Fuel)
	testing.expect_value(t, records.statistics.stalls[.Crafting_No_Fuel], 1)
}

// The byproduct uses: slag to gravel in the crusher, gravel and water to
// concrete in the washer, mud to clay and clay to brick in the furnace.
@(test)
test_byproducts_have_uses :: proc(t: ^testing.T) {
	content := make_test_content()
	items := content.items
	crusher_machine := test_crafting_machine(content, "crusher")
	crusher := make_test_crafting_machine(crusher_machine)
	crusher.slots[0] = {test_item(items, "slag"), 3}
	testing.expect_value(t, ticks_until_crafted(&crusher, crusher_machine, content, 200), 60)
	testing.expect_value(t, crusher.slots[1], Item_Stack{test_item(items, "gravel"), 1})
	washer_machine := test_crafting_machine(content, "washer")
	washer := make_test_crafting_machine(washer_machine)
	washer.slots[0] = {test_item(items, "gravel"), 2}
	washer.buffers[0] = {fluid = test_fluid(content, "water"), level = 100}
	testing.expect_value(t, ticks_until_crafted(&washer, washer_machine, content, 200), 60)
	testing.expect_value(t, washer.slots[1], Item_Stack{test_item(items, "concrete"), 1})
	testing.expect_value(t, washer.buffers[0].level, 70)
	testing.expect_value(t, content.recipes.recipes[furnace_recipe_for(content.recipes, test_item(items, "mud"))].outputs[0], Item_Stack{test_item(items, "clay"), 1})
	testing.expect_value(t, content.recipes.recipes[furnace_recipe_for(content.recipes, test_item(items, "clay"))].outputs[0], Item_Stack{test_item(items, "brick"), 1})
}

@(test)
test_recycler_arithmetic :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	gear, plate := test_item(items, "iron_gear"), test_item(items, "iron_plate")
	// 3 circuits, 5 gears and 9 plates give back 0, 1 and 2.
	assembler_recipe := recipes.recipes[test_recipe(recipes, "assembler_1")]
	returns := recycling_returns(assembler_recipe)
	testing.expect_value(t, len(returns), 2)
	testing.expect_value(t, returns[0], Item_Stack{gear, 1})
	testing.expect_value(t, returns[1], Item_Stack{plate, 2})
	// Rounding down: a gear (2 plates) gives nothing back.
	testing.expect_value(t, len(recycling_returns(recipes.recipes[test_recipe(recipes, "iron_gear")])), 0)
	testing.expect_value(t, recycled_count(4), 1)
	testing.expect_value(t, recycled_count(3), 0)
	testing.expect_value(t, recycled_count(20), 5)
	// The first recipe making the item, in data order.
	testing.expect_value(t, recycle_recipe_of(recipes, plate), test_recipe(recipes, "iron_plate"))
	testing.expect_value(t, recycled_stack(recipes, test_recipe(recipes, "plank")), Item_Stack{test_item(items, "plank"), 4})
	// The cannot_recycle flag wins over a recipe making the item.
	for id in ([?]string{"hematite", "gravel", "mud", "slag", "clay", "concrete", "brick", "stone_brick", "crushed_hematite", "log"}) {
		testing.expectf(t, !item_is_recyclable(recipes, test_item(items, id)), "%s is recyclable", id)
	}
	for id in ([?]string{"assembler_1", "iron_gear", "iron_plate", "belt", "bronze_plate"}) {
		testing.expectf(t, item_is_recyclable(recipes, test_item(items, id)), "%s is not recyclable", id)
	}
}

@(test)
test_recycler_crafts_returns :: proc(t: ^testing.T) {
	content := make_test_content()
	items := content.items
	machine := test_crafting_machine(content, "recycler")
	testing.expect_value(t, machine.recipe_maker, Recipe_Maker.Recycler)
	testing.expect_value(t, machine.electric_power_watts, 100_000)
	testing.expect_value(t, machine.footprint, [3]i32{2, 2, 2})
	recycler := make_test_crafting_machine(machine)
	assembler, gear, plate := test_item(items, "assembler_1"), test_item(items, "iron_gear"), test_item(items, "iron_plate")
	recycler.slots[0] = {assembler, 2}
	// The recipe's time, 2 s at speed 1.
	testing.expect_value(t, ticks_until_crafted(&recycler, machine, content, 500), 120)
	testing.expect_value(t, recycler.slots[0], Item_Stack{assembler, 1})
	testing.expect_value(t, recycler.slots[1], Item_Stack{gear, 1})
	testing.expect_value(t, recycler.slots[2], Item_Stack{plate, 2})
	// Picking it up mid craft returns the item taken, not its ingredients.
	advance_assembler(&recycler, machine, items, content.recipes, TEST_TICK_RATE)
	testing.expect(t, recycler.working)
	held := assembler_held_stacks(recycler, machine, content.recipes)
	testing.expect_value(t, len(held), 1)
	testing.expect_value(t, held[0], Item_Stack{assembler, 1})
	testing.expect_value(t, ticks_until_crafted(&recycler, machine, content, 500), 119)
	// Returns join their stacks.
	testing.expect_value(t, recycler.slots[1], Item_Stack{gear, 2})
	testing.expect_value(t, recycler.slots[2], Item_Stack{plate, 4})
	// Gears are eaten whole.
	recycler.slots[0] = {gear, 3}
	testing.expect_value(t, ticks_until_crafted(&recycler, machine, content, 500), 30)
	testing.expect_value(t, recycler.slots[0], Item_Stack{gear, 2})
	testing.expect_value(t, recycler.slots[1], Item_Stack{gear, 2})
	// No room for the returns: the craft waits.
	stone := test_item(items, "stone")
	recycler.slots[3], recycler.slots[4] = {stone, 1}, {stone, 1}
	recycler.slots[1], recycler.slots[2] = {stone, 1}, {stone, 1}
	recycler.slots[0] = {assembler, 1}
	advance_assembler(&recycler, machine, items, content.recipes, TEST_TICK_RATE)
	testing.expect_value(t, recycler.state, Assembler_State.Output_Full)
	// A flagged item is never taken.
	filters := assembler_slot_filters(recycler, machine, content.recipes)
	testing.expect(t, slot_accepts(filters[0], assembler, items, content.recipes))
	testing.expect(t, !slot_accepts(filters[0], test_item(items, "hematite"), items, content.recipes))
	recycler.slots[0] = {test_item(items, "slag"), 10}
	recycler.slots[1] = EMPTY_STACK
	advance_assembler(&recycler, machine, items, content.recipes, TEST_TICK_RATE)
	testing.expect_value(t, recycler.state, Assembler_State.Missing_Ingredients)
	testing.expect_value(t, recycler.recipe, NO_RECIPE)
}

// An inserter feeds the recycler anything recyclable, fuel items too, and
// nothing flagged.
@(test)
test_recycler_takes_recyclable_items_from_inserters :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	handle := place_test_entity(&world, content, "recycler", {1, 1, 0})
	items := content.items
	plank, assembler := test_item(items, "plank"), test_item(items, "assembler_1")
	testing.expect(t, entity_takes_item_kind(&world.entities, content, handle, plank))
	testing.expect(t, entity_takes_item_kind(&world.entities, content, handle, assembler))
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, handle, test_item(items, "hematite")))
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, handle, test_item(items, "slag")))
	// Planks are fuel, and still go into the input slot, until it holds two
	// crafts' worth (4 a craft).
	for _ in 0 ..< 8 {
		testing.expect_value(t, entity_insert(&world.entities, content, handle, {plank, 1}), EMPTY_STACK)
	}
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {plank, 1}), Item_Stack{plank, 1})
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {assembler, 1}), Item_Stack{assembler, 1})
	testing.expect_value(t, pool_get(&world.entities.assemblers, handle).slots[0], Item_Stack{plank, 8})
}

@(test)
test_recycler_is_validated :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := test_crafting_machine(content, "recycler")
	testing.expect_value(t, validate_recycler_returns(machine, content.recipes), "")
	narrow := machine
	narrow.output_slot_count = 1
	testing.expect(t, validate_recycler_returns(narrow, content.recipes) != "")
	file, error := parse_machines_file(#load("../data/machines.sjson"), context.temp_allocator)
	assert(error == nil)
	index := find_definition_index(file.machines, "recycler")
	chosen := file.machines[index]
	chosen.recipe_choice = "chosen"
	chosen.input_slots, chosen.output_slots = 0, 0
	testing.expect(t, validate_crafting_machine_definition(chosen) != "")
	testing.expect_value(t, validate_crafting_machine_definition(file.machines[index]), "")
}

// Concrete, brick and slag (as slag heaps, work item 0028) place as
// blocks and mine back into their items. Slag stays out of the recycler.
@(test)
test_concrete_brick_and_slag_place_and_mine :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	hardness := [?]f32{3, 2, 1.5}
	block_ids := [?]string{"concrete", "brick", "slag_heap"}
	testing.expect(t, items.items[test_item(items, "slag")].cannot_recycle)
	for id, index in ([?]string{"concrete", "brick", "slag"}) {
		block, item := test_block(registry, block_ids[index]), test_item(items, id)
		testing.expect_value(t, registry.definitions[block].hardness_seconds, hardness[index])
		testing.expect_value(t, item_places_block(items, item), block)
		testing.expect_value(t, block_drop(items, block), item)
		world := make_floor_world(registry, 32)
		records: Game_Records
		players := []Player{make_test_player(registry, {0.5, 1, 0.5})}
		player := &players[0]
		player.inventory.slots[0] = Item_Stack{item, 1}
		player.selected_hotbar_slot = 0
		player.target = Raycast_Hit{hit = true, block = {2, 0, 0}, face = .Positive_Y, adjacent = {2, 1, 0}}
		place_with_player(&world, &records.statistics, Simulation_Content{blocks = registry, items = items, machines = make_test_machines()}, players, 0, {.Place})
		testing.expect_value(t, world_get_block(&world, {2, 1, 0}), block)
		testing.expect_value(t, player.inventory.slots[0], EMPTY_STACK)
		// Mined from above, it takes its hardness and comes back. The
		// pickaxe on the cursor reaches concrete and brick.
		world_set_block(&world, {0, 0, 0}, block)
		player.held.stack = Item_Stack{test_item(items, "wooden_pickaxe"), 1}
		player.pitch = -89
		required := int(mining_required_ticks(hardness[index], TEST_TICK_RATE))
		tick_test_player(&world, &records, registry, player, Input_Frame{pressed = {.Mine}}, required - 1)
		testing.expect_value(t, world_get_block(&world, {0, 0, 0}), block)
		tick_test_player(&world, &records, registry, player, Input_Frame{pressed = {.Mine}}, 1)
		testing.expect_value(t, world_get_block(&world, {0, 0, 0}), AIR_BLOCK)
		// A block item without a stack on the hotbar goes to the main grid.
		testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{item, 1})
	}
}
