package game

import "core:strings"
import "core:testing"

// Work item 0026: ore grades, the crusher, washer and alloy furnace as
// crafting machines, the phase 5 ores and the ore processing technology.

test_crafting_machine :: proc(content: Simulation_Content, id: string) -> Machine {
	return content.machines.machines[test_machine(content.machines, id)]
}

// A machine of the given entry outside any world, fully powered.
make_test_crafting_machine :: proc(machine: Machine) -> Assembler {
	assembler := make_assembler({}, machine)
	assembler.power.satisfaction = POWER_FULL
	return assembler
}

// Runs the machine until a craft finishes, at most limit ticks. Returns
// the ticks taken, or -1.
ticks_until_crafted :: proc(assembler: ^Assembler, machine: Machine, content: Simulation_Content, limit: int) -> int {
	for tick in 1 ..= limit {
		if advance_assembler(assembler, machine, content.items, content.recipes, TEST_TICK_RATE) {
			return tick
		}
	}
	return -1
}

@(test)
test_ore_processing_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	crusher := test_crafting_machine(content, "crusher")
	testing.expect_value(t, crusher.kind, Machine_Kind.Crafting_Machine)
	testing.expect_value(t, crusher.recipe_maker, Recipe_Maker.Crusher)
	testing.expect_value(t, crusher.recipe_choice, Recipe_Choice.Fixed)
	testing.expect_value(t, crusher.footprint, [3]i32{2, 2, 2})
	testing.expect_value(t, crusher.electric_power_watts, 60_000)
	washer := test_crafting_machine(content, "washer")
	testing.expect_value(t, washer.footprint, [3]i32{3, 2, 2})
	testing.expect_value(t, washer.electric_power_watts, 50_000)
	testing.expect_value(t, washer.fluid_port_count, 1)
	testing.expect_value(t, washer.fluid_ports[0].filter, test_fluid(content, "water"))
	alloy := test_crafting_machine(content, "alloy_furnace")
	testing.expect_value(t, alloy.fuel_power_watts, 180_000)
	testing.expect_value(t, alloy.slot_count, 1)
	testing.expect_value(t, alloy.input_slot_count, 2)
	testing.expect_value(t, alloy.output_slot_count, 2)
	testing.expect_value(t, test_crafting_machine(content, "assembler_1").recipe_choice, Recipe_Choice.Chosen)
	// Two input alloys left the stone furnace.
	for id in ([?]string{"bronze_plate", "steel", "brass_plate"}) {
		recipe := content.recipes.recipes[test_recipe(content.recipes, id)]
		testing.expectf(t, recipe.made_in == {.Alloy_Furnace}, "%s is made in %v", id, recipe.made_in)
	}
	wash := content.recipes.recipes[test_recipe(content.recipes, "wash_hematite")]
	testing.expect_value(t, len(wash.fluid_inputs), 1)
	testing.expect_value(t, wash.fluid_inputs[0], Recipe_Fluid{fluid = test_fluid(content, "water"), litres = 30})
	// Low grade ore does not smelt, crushed ore neither.
	testing.expect(t, !item_is_smeltable(content.recipes, test_item(content.items, "hematite_low_grade")))
	testing.expect(t, !item_is_smeltable(content.recipes, test_item(content.items, "crushed_hematite")))
	testing.expect(t, item_is_smeltable(content.recipes, test_item(content.items, "galena")))
}

@(test)
test_furnace_recipes_with_two_inputs_are_refused :: proc(t: ^testing.T) {
	definition := test_recipe_definition()
	definition.inputs = {{item = "copper_plate", count = 3}, {item = "tin_plate", count = 1}}
	definition.made_in = {"furnace"}
	testing.expect(t, strings.contains(resolve_test_recipes({definition}), "exactly one input"))
	// Fluid inputs need a machine with ports.
	washing := test_recipe_definition()
	washing.fluid_inputs = {{fluid = "water", litres = 30}}
	washing.made_in = {"hand"}
	testing.expect(t, strings.contains(resolve_test_recipes({washing}), "made by hand or in a furnace"))
}

@(test)
test_crafting_machine_definitions_are_validated :: proc(t: ^testing.T) {
	file, error := parse_machines_file(#load("../data/machines.sjson"), context.temp_allocator)
	assert(error == nil)
	index := find_machine_definition_index(file.machines, "alloy_furnace")
	expect_refused :: proc(t: ^testing.T, file: Machines_File, index: int, definition: Machine_Definition, location := #caller_location) {
		file.machines[index] = definition
		_, problem := resolve_machine_registry(file, make_test_items(), make_test_fluids(), context.temp_allocator)
		testing.expect(t, problem != "", loc = location)
	}
	original := file.machines[index]
	no_slots := original
	no_slots.input_slots = 0
	expect_refused(t, file, index, no_slots)
	hand := original
	hand.recipe_maker = "hand"
	expect_refused(t, file, index, hand)
	both_powers := original
	both_powers.electric_power_kilowatts = 10
	expect_refused(t, file, index, both_powers)
	no_choice := original
	no_choice.recipe_choice = ""
	expect_refused(t, file, index, no_choice)
}

// Ore grades: 10 percent low grade at a full reservoir, rising linearly
// to 60 percent with 5 percent left, flat below; infinite veins stay at
// 10 percent.
@(test)
test_low_grade_share_follows_the_reservoir :: proc(t: ^testing.T) {
	vein := Vein {
		remaining = {800, 200, 0, 0},
	}
	testing.expect_value(t, low_grade_share_ppm(vein, false), 100_000)
	// Half of 95 percent drawn: halfway up the rise.
	vein.remaining, vein.draws = {400, 125, 0, 0}, 475
	testing.expect_value(t, low_grade_share_ppm(vein, false), 350_000)
	vein.remaining, vein.draws = {40, 10, 0, 0}, 950
	testing.expect_value(t, low_grade_share_ppm(vein, false), 600_000)
	vein.remaining, vein.draws = {1, 0, 0, 0}, 999
	testing.expect_value(t, low_grade_share_ppm(vein, false), 600_000)
	testing.expect_value(t, low_grade_share_ppm(vein, true), 100_000)
}

// Low grade hematite among the hematite draws of an iron vein, and none
// of the gravel graded.
low_grade_draw_share :: proc(content: Simulation_Content, remaining: [MAXIMUM_VEIN_OUTPUTS]i64, draws_before: u64, infinite: bool) -> f64 {
	world := make_drill_world(content)
	world.settings.seed = 777
	world.settings.veins_infinite = infinite
	id := add_test_vein(&world, content, "iron", {1, 1}, 2, remaining)
	registered_vein(&world, id).draws = draws_before
	hematite, low_grade := test_item(content.items, "hematite"), test_item(content.items, "hematite_low_grade")
	high, low := 0, 0
	for _ in 0 ..< 4000 {
		vein := registered_vein(&world, id)
		// Hold the reservoir still, so the share under test barely moves.
		saved := vein.remaining
		switch draw_from_vein(&world, content.veins, vein) {
		case hematite:
			high += 1
		case low_grade:
			low += 1
		}
		vein.remaining = saved
	}
	return f64(low) * 100 / f64(high + low)
}

@(test)
test_vein_draws_come_out_graded :: proc(t: ^testing.T) {
	content := make_test_content()
	full := low_grade_draw_share(content, {800_000, 200_000, 0, 0}, 0, false)
	testing.expectf(t, abs(full - 10) < 1.5, "full vein: %.2f percent low grade", full)
	nearly_empty := low_grade_draw_share(content, {40_000, 10_000, 0, 0}, 950_000, false)
	testing.expectf(t, abs(nearly_empty - 60) < 2.5, "nearly empty vein: %.2f percent low grade", nearly_empty)
	infinite := low_grade_draw_share(content, {40_000, 10_000, 0, 0}, 950_000, true)
	testing.expectf(t, abs(infinite - 10) < 1.5, "infinite vein: %.2f percent low grade", infinite)
	// The grade roll does not change which output is drawn: the output
	// sequence matches the ungraded one of the same seed.
	vein_type := content.veins.types[test_vein_type(content, "iron")]
	vein := Vein {
		remaining = {800_000, 200_000, 0, 0},
	}
	for draw in u64(0) ..< 200 {
		vein.draws = draw
		hash := vein_draw_hash(777, vein)
		output := choose_vein_output(vein, vein_type, false, hash)
		item := graded_output(vein_type, output, low_grade_share_ppm(vein, false), hash)
		testing.expect(t, item == vein_type.outputs[output] || item == vein_type.low_grades[output])
	}
	testing.expect_value(t, vein_type.low_grades[1], NO_ITEM)
}

@(test)
test_new_vein_types_load_and_place :: proc(t: ^testing.T) {
	content := make_test_content()
	for id, index in ([?]string{"lead", "zinc", "nickel"}) {
		vein_type := content.veins.types[test_vein_type(content, id)]
		ores := [?]string{"galena", "sphalerite", "pentlandite"}
		testing.expect_value(t, vein_type.outputs[0], test_item(content.items, ores[index]))
		testing.expect_value(t, vein_type.low_grades[0], test_item(content.items, strings.concatenate({ores[index], "_low_grade"}, context.temp_allocator)))
		testing.expect_value(t, len(vein_type.outcrop_blocks), 1)
		testing.expect_value(t, content.items.drop_for_block[vein_type.outcrop_blocks[0]], vein_type.outputs[0])
	}
	// A drill on a lead outcrop draws galena, sphalerite and gravel.
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "lead", {1, 1}, 2, {700, 100, 200, 0})
	machine := test_machine(content.machines, "burner_mining_drill")
	testing.expect(t, placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	drill := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	chest := place_test_entity(&world, content, "iron_chest", {2, 1, 0})
	tick_test_entities(&world, content, 20 * 192)
	galena := chest_count_of(&world, chest, test_item(content.items, "galena")) + chest_count_of(&world, chest, test_item(content.items, "galena_low_grade"))
	testing.expect(t, galena > 0)
	testing.expect_value(t, test_drill(&world, drill).state, Drill_State.Mining)
	testing.expect_value(t, registered_vein(&world, vein).draws, 20)
	// World generation places every new type somewhere.
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	found: [3]bool
	for x in i32(-6) ..= 6 {
		for z in i32(-6) ..= 6 {
			for placed in region_veins(&generator, {x, z}, context.temp_allocator) {
				id := generator.veins.types[placed.type].definition.id
				found[0] |= id == "lead"
				found[1] |= id == "zinc"
				found[2] |= id == "nickel"
			}
		}
	}
	testing.expect_value(t, found, [3]bool{true, true, true})
}

@(test)
test_crusher_turns_low_grade_into_crushed_ore_and_gravel :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := test_crafting_machine(content, "crusher")
	crusher := make_test_crafting_machine(machine)
	low_grade := test_item(content.items, "chalcopyrite_low_grade")
	crusher.slots[0] = {low_grade, 5}
	// 2 s at speed 1; the recipe comes from the input.
	testing.expect_value(t, ticks_until_crafted(&crusher, machine, content, 1000), 120)
	testing.expect_value(t, crusher.recipe, test_recipe(content.recipes, "crush_chalcopyrite"))
	testing.expect_value(t, crusher.slots[0], Item_Stack{low_grade, 3})
	// Crushing recovers the ore: 2 low grade give 2 crushed.
	testing.expect_value(t, crusher.slots[1], Item_Stack{test_item(content.items, "crushed_chalcopyrite"), 2})
	testing.expect_value(t, crusher.slots[2], Item_Stack{test_item(content.items, "gravel"), 1})
	testing.expect_value(t, ticks_until_crafted(&crusher, machine, content, 1000), 120)
	// One left is not a craft.
	testing.expect_value(t, ticks_until_crafted(&crusher, machine, content, 200), -1)
	testing.expect_value(t, crusher.state, Assembler_State.Missing_Ingredients)
	// Unpowered.
	crusher.slots[0] = {low_grade, 2}
	crusher.power.satisfaction = 0
	advance_assembler(&crusher, machine, content.items, content.recipes, TEST_TICK_RATE)
	testing.expect_value(t, crusher.state, Assembler_State.No_Power)
	// Plain ore is not crushed.
	crusher.slots[0] = {test_item(content.items, "chalcopyrite"), 2}
	crusher.power.satisfaction = POWER_FULL
	advance_assembler(&crusher, machine, content.items, content.recipes, TEST_TICK_RATE)
	testing.expect_value(t, crusher.state, Assembler_State.Missing_Ingredients)
	testing.expect_value(t, crusher.recipe, NO_RECIPE)
}

@(test)
test_washer_takes_water_at_the_start :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := test_crafting_machine(content, "washer")
	washer := make_test_crafting_machine(machine)
	water := test_fluid(content, "water")
	crushed := test_item(content.items, "crushed_hematite")
	washer.slots[0] = {crushed, 3}
	// Without water nothing starts, and the ingredients stay.
	advance_assembler(&washer, machine, content.items, content.recipes, TEST_TICK_RATE)
	testing.expect_value(t, washer.state, Assembler_State.No_Fluid)
	testing.expect(t, !washer.working)
	testing.expect_value(t, washer.slots[0].count, 3)
	testing.expect(t, !assembler_wants_power(washer, machine, content.recipes, content.items))
	// 29 L is short of a craft's 30 L: still nothing starts, nothing is taken.
	washer.buffers[0] = {fluid = water, level = 29}
	for _ in 0 ..< 10 {
		advance_assembler(&washer, machine, content.items, content.recipes, TEST_TICK_RATE)
	}
	testing.expect_value(t, washer.state, Assembler_State.No_Fluid)
	testing.expect_value(t, washer.buffers[0].level, 29)
	testing.expect(t, !assembler_wants_power(washer, machine, content.recipes, content.items))
	// With 30 L the craft takes all of it at the start, with its item, and
	// finishes without more water: 1 s at speed 1.
	washer.buffers[0].level = 30
	testing.expect(t, assembler_wants_power(washer, machine, content.recipes, content.items))
	advance_assembler(&washer, machine, content.items, content.recipes, TEST_TICK_RATE)
	testing.expect(t, washer.working)
	testing.expect_value(t, washer.buffers[0].level, 0)
	testing.expect_value(t, washer.slots[0].count, 2)
	testing.expect(t, assembler_wants_power(washer, machine, content.recipes, content.items))
	testing.expect_value(t, ticks_until_crafted(&washer, machine, content, 100), 59)
	testing.expect_value(t, washer.slots[1], Item_Stack{test_item(content.items, "hematite"), 1})
	testing.expect_value(t, washer.slots[2], Item_Stack{test_item(content.items, "mud"), 1})
	// The next craft waits for its full 30 L again.
	advance_assembler(&washer, machine, content.items, content.recipes, TEST_TICK_RATE)
	testing.expect_value(t, washer.state, Assembler_State.No_Fluid)
	washer.buffers[0] = {fluid = water, level = 200}
	testing.expect_value(t, ticks_until_crafted(&washer, machine, content, 100), 60)
	testing.expect_value(t, washer.buffers[0].level, 170)
}

// The washer's port joins the pipe network like a fluid machine's, and
// water from a tank reaches it.
@(test)
test_washer_port_takes_water_from_pipes :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	washer := place_test_entity(&world, content, "washer", {5, 1, 0})
	pipes := lay_pipes(&world, content, {6, 1, -1})
	tank := place_test_fluid_entity(&world, content, "storage_tank", {5, 1, -4})
	test_fluid_machine(&world, tank).buffers[0] = {fluid = test_fluid(content, "water"), level = 1000}
	networks := &world.entities.fluid_networks
	testing.expect(t, fluid_network_of(networks, washer, 0) >= 0)
	testing.expect_value(t, fluid_network_of(networks, washer, 0), fluid_network_of(networks, pipes[0], -1))
	testing.expect(t, pipe_connects_through(&world.entities, content.machines, {6, 1, -1}, .Positive_Z))
	tick_test_fluids(&world, content, 60)
	testing.expect(t, pool_get(&world.entities.assemblers, washer).buffers[0].level > 0)
	// Picking the washer up rebuilds the networks without it.
	remove_entity(&world.entities, content.machines, washer)
	testing.expect_value(t, fluid_network_of(networks, washer, 0), -1)
}

@(test)
test_alloy_furnace_crafts_from_two_inputs :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	handle := place_test_entity(&world, content, "alloy_furnace", {1, 1, 0})
	furnace := pool_get(&world.entities.assemblers, handle)
	machine := test_crafting_machine(content, "alloy_furnace")
	items := content.items
	coal, copper, tin := test_item(items, "coal"), test_item(items, "copper_plate"), test_item(items, "tin_plate")
	iron, bronze := test_item(items, "iron_plate"), test_item(items, "bronze_plate")
	// Coal with nothing loaded is fuel; the plates find their slots.
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {coal, 2}), EMPTY_STACK)
	testing.expect_value(t, furnace.slots[0], Item_Stack{coal, 2})
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {copper, 6}), EMPTY_STACK)
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {tin, 1}), EMPTY_STACK)
	testing.expect_value(t, furnace.slots[1], Item_Stack{copper, 6})
	testing.expect_value(t, furnace.slots[2], Item_Stack{tin, 1})
	// Coal next to copper and tin completes no recipe: fuel again. Iron
	// has no slot.
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {coal, 1}), EMPTY_STACK)
	testing.expect_value(t, furnace.slots[0], Item_Stack{coal, 3})
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {iron, 1}), Item_Stack{iron, 1})
	testing.expect(t, entity_takes_item_kind(&world.entities, content, handle, iron))
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, handle, test_item(items, "stone")))
	// 6.4 s at speed 1 and 180 kW of coal.
	testing.expect_value(t, ticks_until_crafted(furnace, machine, content, 1000), 384)
	testing.expect_value(t, furnace.slots[3], Item_Stack{bronze, 4})
	testing.expect_value(t, furnace.slots[4], Item_Stack{test_item(items, "slag"), 1})
	testing.expect_value(t, furnace.slots[1], Item_Stack{copper, 3})
	testing.expect_value(t, furnace.slots[2], EMPTY_STACK)
	testing.expect_value(t, len(entity_offered_items(&world.entities, handle, NO_ITEM)), 2)
	// Out of fuel.
	furnace.slots[0], furnace.fuel_joules = EMPTY_STACK, 0
	furnace.slots[2] = {tin, 1}
	advance_assembler(furnace, machine, content.items, content.recipes, TEST_TICK_RATE)
	testing.expect_value(t, furnace.state, Assembler_State.No_Fuel)
}

// Steel: coal goes into an input slot while iron plate is loaded, up to
// two crafts' worth, then into the fuel slot.
@(test)
test_alloy_furnace_routes_coal_for_steel :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	handle := place_test_entity(&world, content, "alloy_furnace", {1, 1, 0})
	furnace := pool_get(&world.entities.assemblers, handle)
	coal, iron := test_item(content.items, "coal"), test_item(content.items, "iron_plate")
	testing.expect_value(t, entity_insert(&world.entities, content, handle, {iron, 5}), EMPTY_STACK)
	for _ in 0 ..< 3 {
		testing.expect_value(t, entity_insert(&world.entities, content, handle, {coal, 1}), EMPTY_STACK)
	}
	testing.expect_value(t, furnace.slots[2], Item_Stack{coal, 2})
	testing.expect_value(t, furnace.slots[0], Item_Stack{coal, 1})
	machine := test_crafting_machine(content, "alloy_furnace")
	testing.expect_value(t, ticks_until_crafted(furnace, machine, content, 2000), 16 * TEST_TICK_RATE)
	testing.expect_value(t, furnace.slots[3], Item_Stack{test_item(content.items, "steel"), 1})
}

@(test)
test_fixed_recipe_choice_picks_by_inputs :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	copper, tin, zinc := test_item(items, "copper_plate"), test_item(items, "tin_plate"), test_item(items, "zinc_plate")
	iron, coal := test_item(items, "iron_plate"), test_item(items, "coal")
	pick :: proc(recipes: Recipe_Registry, loaded: ..Item_Stack) -> int {
		return fixed_recipe_for_inputs(recipes, .Alloy_Furnace, loaded)
	}
	testing.expect_value(t, pick(recipes, {copper, 3}, {tin, 1}), test_recipe(recipes, "bronze_plate"))
	testing.expect_value(t, pick(recipes, {zinc, 1}, {copper, 2}), test_recipe(recipes, "brass_plate"))
	testing.expect_value(t, pick(recipes, {iron, 5}, {coal, 1}), test_recipe(recipes, "steel"))
	testing.expect_value(t, pick(recipes, {copper, 3}, EMPTY_STACK), NO_RECIPE)
	testing.expect_value(t, pick(recipes, {copper, 3}, {coal, 1}), NO_RECIPE)
	// The panel cannot choose a recipe on a fixed machine.
	machine := test_crafting_machine(content, "alloy_furnace")
	furnace := make_assembler({}, machine)
	inventory := make_inventory(PLAYER_INVENTORY_SLOT_COUNT, context.temp_allocator)
	refusal := change_assembler_recipe(&furnace, machine, inventory, items, recipes, test_recipe(recipes, "steel"))
	testing.expect_value(t, refusal, Recipe_Change_Refusal.Not_For_Assembler)
	// The slot filters of a fixed choice take any input of the category.
	filters := assembler_slot_filters(furnace, machine, recipes)
	testing.expect_value(t, len(filters), 5)
	testing.expect_value(t, filters[0].kind, Slot_Filter_Kind.Fuel)
	testing.expect(t, slot_accepts(filters[1], zinc, items, recipes))
	testing.expect(t, !slot_accepts(filters[2], test_item(items, "stone"), items, recipes))
	testing.expect_value(t, filters[3].kind, Slot_Filter_Kind.Output)
	testing.expect_value(t, filters[4].kind, Slot_Filter_Kind.Output)
}

// A fixed category where one recipe's input items are a subset of
// another's cannot pick by inputs, so loading refuses it.
@(test)
test_fixed_recipe_choice_refuses_ambiguity_at_load :: proc(t: ^testing.T) {
	content := make_test_content()
	items := content.items
	copper, tin := test_item(items, "copper_plate"), test_item(items, "tin_plate")
	bronze := Recipe {
		id      = "bronze",
		inputs  = {{copper, 3}, {tin, 1}},
		outputs = {{test_item(items, "bronze_plate"), 4}},
		made_in = {.Alloy_Furnace},
	}
	copper_only := Recipe {
		id      = "copper_only",
		inputs  = {{copper, 2}},
		outputs = {{test_item(items, "brass_plate"), 1}},
		made_in = {.Alloy_Furnace},
	}
	testing.expect_value(t, validate_fixed_category({bronze}, .Alloy_Furnace), "")
	testing.expect(t, validate_fixed_category({bronze, copper_only}, .Alloy_Furnace) != "")
	same_inputs := bronze
	same_inputs.id = "bronze_again"
	testing.expect(t, validate_fixed_category({bronze, same_inputs}, .Alloy_Furnace) != "")
	testing.expect(t, validate_crafting_machine_recipes(content.machines, {recipes = {bronze, copper_only}}) != "")
	// A recipe with more inputs than the machine has slots.
	three := bronze
	three.inputs = {{copper, 1}, {tin, 1}, {test_item(items, "coal"), 1}}
	testing.expect(t, validate_crafting_machine_recipes(content.machines, {recipes = {three}}) != "")
	// A fluid the machine has no port for.
	thirsty := copper_only
	thirsty.made_in = {.Crusher}
	thirsty.fluid_inputs = {{fluid = test_fluid(content, "water"), litres = 10}}
	testing.expect(t, validate_crafting_machine_recipes(content.machines, {recipes = {thirsty}}) != "")
	testing.expect_value(t, validate_crafting_machine_recipes(content.machines, content.recipes), "")
}

@(test)
test_ore_processing_is_researched :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technology := test.technologies.technologies[test_technology(test.technologies, "ore_processing")]
	testing.expect_value(t, technology.pack_count, 50)
	testing.expect_value(t, len(technology.prerequisites), 1)
	testing.expect_value(t, technology.prerequisites[0], test_technology(test.technologies, "steel_processing"))
	gated := [?]string{"crusher", "washer", "crush_hematite", "wash_pentlandite"}
	for id in gated {
		testing.expectf(t, !test_available(test, id), "%s is open before research", id)
	}
	mark_technology_researched(&test.unlocks, test.recipes, test_technology(test.technologies, "ore_processing"))
	for id in gated {
		testing.expectf(t, test_available(test, id), "%s is closed after research", id)
	}
	// Only the crusher, the washer and the six crushing and six washing
	// recipes (work item 0027).
	testing.expect_value(t, len(technology.unlocks), 14)
	for recipe in technology.unlocks {
		made_in := test.recipes.recipes[recipe].made_in
		testing.expect(t, made_in == {.Crusher} || made_in == {.Washer} || made_in == {.Hand, .Assembler})
	}
}

// Carry over from work item 0026: the alloy furnace is a stone and brick
// building on the start channel, so bronze is reachable in phase 2; steel
// stays under steel processing, and the steel furnace has a machine.
@(test)
test_alloy_furnace_is_a_start_recipe :: proc(t: ^testing.T) {
	test := make_crafting_test()
	testing.expect_value(t, test.recipes.recipes[test_recipe(test.recipes, "alloy_furnace")].channel, Recipe_Channel.Start)
	testing.expect(t, test_available(test, "alloy_furnace"))
	bronze := test.recipes.recipes[test_recipe(test.recipes, "bronze_plate")]
	testing.expect_value(t, bronze.channel, Recipe_Channel.Discovery)
	steel := test.recipes.recipes[test_recipe(test.recipes, "steel")]
	testing.expect_value(t, test.technologies.technologies[steel.technology].id, "steel_processing")
	steel_furnace := test.recipes.recipes[test_recipe(test.recipes, "steel_furnace")]
	testing.expect_value(t, test.technologies.technologies[steel_furnace.technology].id, "steel_processing")
	content := make_test_content()
	machine := content.machines.machines[test_machine(content.machines, "steel_furnace")]
	testing.expect_value(t, machine.kind, Machine_Kind.Furnace)
	testing.expect_value(t, machine.speed_percent, 200)
	testing.expect_value(t, machine.fuel_power_watts, 90_000)
	testing.expect_value(t, machine.item, test_item(content.items, "steel_furnace"))
}

// Low grade ore from a chest through a crusher into a washer fed by a
// water tank, the products into a chest: two worlds run 1200 ticks and
// end in the same state, with washed ore made.
lay_ore_processing_line :: proc(world: ^World, content: Simulation_Content) -> (crusher, washer, output: Entity_Handle) {
	source := place_test_entity(world, content, "wooden_chest", {0, 1, 0})
	place_fuelled_inserter(world, content, {1, 1, 0}, 0)
	crusher = place_test_entity(world, content, "crusher", {2, 1, 0})
	place_fuelled_inserter(world, content, {4, 1, 0}, 0)
	washer = place_test_entity(world, content, "washer", {5, 1, 0})
	place_fuelled_inserter(world, content, {8, 1, 0}, 0)
	output = place_test_entity(world, content, "wooden_chest", {9, 1, 0})
	lay_pipes(world, content, {6, 1, -1})
	tank := place_test_fluid_entity(world, content, "storage_tank", {5, 1, -4})
	test_fluid_machine(world, tank).buffers[0] = {fluid = test_fluid(content, "water"), level = 5000}
	add_test_power_plant(world, content, {4, 1, 2}, {2, 1, 3})
	entity_insert(&world.entities, content, source, {test_item(content.items, "hematite_low_grade"), 40})
	return
}

@(test)
test_ore_processing_line_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_drill_world(content), make_drill_world(content)}
	outputs: [2]Entity_Handle
	for &world, index in worlds {
		crusher, washer: Entity_Handle
		crusher, washer, outputs[index] = lay_ore_processing_line(&world, content)
		testing.expect(t, entity_network(&world.entities.electric_networks, crusher) >= 0)
		testing.expect(t, entity_network(&world.entities.electric_networks, washer) >= 0)
		tick_test_entities(&world, content, 1200)
	}
	first, second := &worlds[0], &worlds[1]
	for entry, index in first.entities.assemblers.entries {
		testing.expect(t, entry == second.entities.assemblers.entries[index])
	}
	for entry, index in first.entities.chests.entries {
		testing.expect(t, entry == second.entities.chests.entries[index])
	}
	for entry, index in first.entities.fluid_machines.entries {
		testing.expect(t, entry == second.entities.fluid_machines.entries[index])
	}
	hematite, mud := test_item(content.items, "hematite"), test_item(content.items, "mud")
	made := int(first.statistics.produced[hematite])
	testing.expect(t, made > 0)
	testing.expect_value(t, int(first.statistics.produced[mud]), made)
	testing.expect(t, chest_count_of(first, outputs[0], hematite) > 0)
	testing.expect_value(t, chest_count_of(first, outputs[0], hematite), chest_count_of(second, outputs[1], hematite))
	testing.expect_value(t, first.statistics.produced[hematite], second.statistics.produced[hematite])
	// Every wash drew 30 L from the tank through the pipe.
	tank := first.entities.fluid_machines.entries[0]
	in_pipes := first.entities.pipes.entries[0].buffer.level
	washer := first.entities.assemblers.entries[1]
	drawn := 5000 - tank.buffers[0].level - in_pipes - washer.buffers[0].level
	partial := washer.working ? i32(washer.progress_ticks) / 2 : 0
	testing.expect_value(t, drawn, i32(made) * 30 + partial)
}
