package game

import "core:slice"
import "core:testing"

// Plastics and chemistry (work item 0031): the chemical plant, the wood
// gasifier, asphalt, science pack 2 and their technologies.

@(test)
test_chemistry_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	plant := test_crafting_machine(content, "chemical_plant")
	testing.expect_value(t, plant.footprint, [3]i32{3, 3, 3})
	testing.expect_value(t, plant.electric_power_watts, 210_000)
	testing.expect_value(t, plant.recipe_maker, Recipe_Maker.Chemistry)
	testing.expect_value(t, plant.recipe_choice, Recipe_Choice.Fixed)
	testing.expect_value(t, plant.fluid_ports[0].phase_filter, Fluid_Phase_Filter.Gas)
	testing.expect_value(t, plant.fluid_ports[1].filter, NO_FLUID)
	gasifier := test_crafting_machine(content, "wood_gasifier")
	testing.expect_value(t, gasifier.footprint, [3]i32{2, 3, 2})
	testing.expect_value(t, gasifier.electric_power_watts, 90_000)
	testing.expect_value(t, gasifier.slot_count, 0)
	testing.expect_value(t, gasifier.recipe_maker, Recipe_Maker.Gasifier)
	wood_gas := test_fluid(content, "wood_gas")
	testing.expect(t, fluid_is_gas(content.fluids, wood_gas))
	testing.expect_value(t, content.fluids.fluids[wood_gas].fuel_kilojoules_per_litre, 100)
	testing.expect_value(t, content.fluids.fluids[test_fluid(content, "water")].fuel_kilojoules_per_litre, 0)
	testing.expect_value(t, gasifier.fluid_ports[0].filter, wood_gas)
	recipes := content.recipes
	plastic := recipes.recipes[test_recipe(recipes, "plastic_bar")]
	testing.expect_value(t, plastic.fluid_inputs[0], Recipe_Fluid{test_fluid(content, "petroleum_gas"), 20})
	testing.expect_value(t, plastic.outputs[0], Item_Stack{test_item(content.items, "plastic_bar"), 2})
	gasification := recipes.recipes[test_recipe(recipes, "wood_gasification")]
	testing.expect_value(t, gasification.byproducts, Recipe_Output_Set{0})
	testing.expect_value(t, gasification.fluid_outputs[0], Recipe_Fluid{wood_gas, 60})
	testing.expect_value(t, recipes.recipes[test_recipe(recipes, "science_pack_2")].made_in, Recipe_Makers{.Assembler})
	testing.expect_value(t, recipes.recipes[test_recipe(recipes, "asphalt")].made_in, Recipe_Makers{.Assembler})
	// Each fixed machine's recipe set fits it and can be told apart.
	for machine in ([?]Machine{plant, gasifier}) {
		testing.expect_value(t, validate_fixed_category(recipes.recipes, machine.recipe_maker), "")
		for recipe in recipes.recipes {
			if machine.recipe_maker in recipe.made_in {
				testing.expect_value(t, validate_crafting_machine_recipe(machine, recipe), "")
			}
		}
	}
	// The browser tags of the two routes.
	testing.expect_value(t, plastic.tags, Recipe_Tag_Set{tag_index(recipes, "oil"), tag_index(recipes, "gas"), tag_index(recipes, "plastic")})
	syngas := recipes.recipes[test_recipe(recipes, "syngas_plastic")]
	testing.expect_value(t, syngas.tags, Recipe_Tag_Set{tag_index(recipes, "wood"), tag_index(recipes, "gas"), tag_index(recipes, "plastic")})
}

// One chemical plant recipe: the item loaded, the fluids in the two input
// ports, and what comes out.
Chemistry_Case :: struct {
	recipe:        string,
	item:          string,
	gas:           string,
	second_fluid:  string,
	ticks:         int,
	product:       string,
	product_count: u16,
	gas_used:      i32,
	second_used:   i32,
}

@(test)
test_chemical_plant_recipes :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := test_crafting_machine(content, "chemical_plant")
	cases := [?]Chemistry_Case {
		{"plastic_bar", "coal", "petroleum_gas", "", 60, "plastic_bar", 2, 20, 0},
		{"sulfur", "", "petroleum_gas", "water", 60, "sulfur", 2, 30, 30},
		{"bitumen", "", "", "heavy_oil", 120, "bitumen", 1, 0, 40},
		{"syngas_plastic", "charcoal", "wood_gas", "", 120, "plastic_bar", 1, 30, 0},
		// Coal decides even with water beside the gas.
		{"plastic_bar", "coal", "petroleum_gas", "water", 60, "plastic_bar", 2, 20, 0},
	}
	for entry in cases {
		plant := make_test_crafting_machine(machine)
		if entry.item != "" {
			plant.slots[0] = {test_item(content.items, entry.item), 5}
		}
		if entry.gas != "" {
			plant.buffers[0] = {fluid = test_fluid(content, entry.gas), level = 200}
		}
		if entry.second_fluid != "" {
			plant.buffers[1] = {fluid = test_fluid(content, entry.second_fluid), level = 200}
		}
		testing.expectf(t, ticks_until_crafted(&plant, machine, content, 1000) == entry.ticks, "%s ticks", entry.recipe)
		testing.expect_value(t, plant.recipe, test_recipe(content.recipes, entry.recipe))
		testing.expect_value(t, plant.slots[1], Item_Stack{test_item(content.items, entry.product), entry.product_count})
		testing.expect_value(t, plant.buffers[0].level, entry.gas == "" ? 0 : 200 - entry.gas_used)
		testing.expect_value(t, plant.buffers[1].level, entry.second_fluid == "" ? 0 : 200 - entry.second_used)
		if entry.item != "" {
			testing.expect_value(t, plant.slots[0].count, 4)
		}
	}
}

// Gas alone is sulfur waiting for water: nothing starts and nothing is
// taken, and the plant asks for no power.
@(test)
test_chemical_plant_waits_for_every_fluid :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := test_crafting_machine(content, "chemical_plant")
	plant := make_test_crafting_machine(machine)
	plant.buffers[0] = {fluid = test_fluid(content, "petroleum_gas"), level = 200}
	testing.expect_value(t, ticks_until_crafted(&plant, machine, content, 100), -1)
	testing.expect_value(t, plant.state, Assembler_State.No_Fluid)
	testing.expect_value(t, plant.buffers[0].level, 200)
	testing.expect(t, !assembler_wants_power(plant, machine, content.recipes, content.items))
	plant.buffers[1] = {fluid = test_fluid(content, "water"), level = 29}
	testing.expect_value(t, ticks_until_crafted(&plant, machine, content, 100), -1)
	plant.buffers[1].level = 30
	testing.expect_value(t, ticks_until_crafted(&plant, machine, content, 100), 60)
	testing.expect_value(t, plant.recipe, test_recipe(content.recipes, "sulfur"))
	testing.expect_value(t, plant.buffers[1].level, 0)
}

// 4 logs give 60 L of wood gas and a charcoal in 5 s. The charcoal is a
// byproduct: a full slot stops a strict gasifier, a lenient one voids it.
@(test)
test_wood_gasifier_and_its_byproduct :: proc(t: ^testing.T) {
	content := make_test_content()
	wood_gas, charcoal := test_fluid(content, "wood_gas"), test_item(content.items, "charcoal")
	world := make_oil_world(content)
	records := make_fluid_test_records(content)
	handle := place_powered_crafting_machine(&world, content, "wood_gasifier", {0, 1, 0})
	gasifier := test_oil_assembler(&world, handle)
	gasifier.slots[0] = {test_item(content.items, "log"), 12}
	tick_test_assemblers(&world, &records, content, 300)
	gasifier = test_oil_assembler(&world, handle)
	testing.expect_value(t, gasifier.recipe, test_recipe(content.recipes, "wood_gasification"))
	testing.expect_value(t, gasifier.slots[0].count, 8)
	testing.expect_value(t, gasifier.slots[1], Item_Stack{charcoal, 1})
	testing.expect_value(t, gasifier.buffers[0], Fluid_Buffer{fluid = wood_gas, level = 60})
	testing.expect_value(t, fluid_counter(records.statistics.fluids.produced, wood_gas), 60)
	testing.expect_value(t, item_counter(records.statistics.produced, charcoal), 1)
	gasifier.slots[1].count = 100
	tick_test_assemblers(&world, &records, content, 10)
	gasifier = test_oil_assembler(&world, handle)
	testing.expect_value(t, gasifier.state, Assembler_State.Output_Full)
	testing.expect_value(t, gasifier.slots[0].count, 8)
	world.settings.byproducts_lenient = true
	tick_test_assemblers(&world, &records, content, 300)
	gasifier = test_oil_assembler(&world, handle)
	testing.expect_value(t, gasifier.slots[0].count, 4)
	testing.expect_value(t, gasifier.buffers[0].level, 120)
	testing.expect_value(t, item_counter(records.statistics.voided, charcoal), 1)
}

// Asphalt and science pack 2 are assembler recipes at speed 0.5.
@(test)
test_asphalt_and_science_pack_2_in_the_assembler :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	machine := test_crafting_machine(content, "assembler_1")
	asphalt := make_powered_assembler(recipes, test_recipe(recipes, "asphalt"))
	asphalt.slots[0] = {test_item(items, "bitumen"), 2}
	asphalt.slots[1] = {test_item(items, "gravel"), 4}
	testing.expect_value(t, ticks_until_crafted(&asphalt, machine, content, 1000), 240)
	testing.expect_value(t, asphalt.slots[2], Item_Stack{test_item(items, "asphalt"), 4})
	pack := make_powered_assembler(recipes, test_recipe(recipes, "science_pack_2"))
	pack.slots[0] = {test_item(items, "plastic_bar"), 1}
	pack.slots[1] = {test_item(items, "copper_wire"), 1}
	pack.slots[2] = {test_item(items, "iron_gear"), 1}
	testing.expect_value(t, ticks_until_crafted(&pack, machine, content, 1000), 720)
	testing.expect_value(t, pack.slots[3], Item_Stack{test_item(items, "science_pack_2"), 1})
	// Science pack 2 is not a hand recipe.
	testing.expect(t, .Hand not_in recipes.recipes[test_recipe(recipes, "science_pack_2")].made_in)
}

// Asphalt places as a paving block of hardness 3 and mines back into
// itself.
@(test)
test_asphalt_places_and_mines :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	block, item := test_block(registry, "asphalt"), test_item(items, "asphalt")
	testing.expect_value(t, registry.definitions[block].hardness_seconds, 3)
	testing.expect(t, registry.definitions[block].solid)
	testing.expect_value(t, item_places_block(items, item), block)
	testing.expect_value(t, block_drop(items, block), item)
	testing.expect(t, items.items[item].cannot_recycle)
}

// plastics waits for oil processing; renewable plastics and bitumen paving
// for plastics. Logistics science unlocks science pack 2, and fast belts
// cost packs 1 and 2, so a lab without pack 2 cannot run them.
@(test)
test_chemistry_technologies_are_gated :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	plastics := test_technology(technologies, "plastics")
	renewable := test_technology(technologies, "renewable_plastics")
	paving := test_technology(technologies, "bitumen_paving")
	for id in ([?]string{"automation", "steel_processing", "ore_processing"}) {
		mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, id))
	}
	research: Research_State
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, plastics), Research_Refusal.Locked)
	mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, "oil_processing"))
	testing.expect_value(t, technology_status(technologies, test.unlocks, plastics), Technology_Status.Available)
	testing.expect_value(t, technology_status(technologies, test.unlocks, renewable), Technology_Status.Locked)
	testing.expect_value(t, technology_status(technologies, test.unlocks, paving), Technology_Status.Locked)
	testing.expect(t, !recipe_is_available(test.unlocks, test_recipe(test.recipes, "chemical_plant")))
	mark_technology_researched(&test.unlocks, test.recipes, plastics)
	for id in ([?]string{"chemical_plant", "plastic_bar", "sulfur"}) {
		testing.expectf(t, recipe_is_available(test.unlocks, test_recipe(test.recipes, id)), "%s", id)
	}
	for id in ([?]string{"wood_gasifier", "syngas_plastic", "bitumen", "asphalt"}) {
		testing.expectf(t, !recipe_is_available(test.unlocks, test_recipe(test.recipes, id)), "%s", id)
	}
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, renewable), Research_Refusal.None)
	mark_technology_researched(&test.unlocks, test.recipes, renewable)
	mark_technology_researched(&test.unlocks, test.recipes, paving)
	for id in ([?]string{"wood_gasifier", "wood_gasification", "syngas_plastic", "bitumen", "asphalt"}) {
		testing.expectf(t, recipe_is_available(test.unlocks, test_recipe(test.recipes, id)), "%s", id)
	}
	logistics_science := technologies.technologies[test_technology(technologies, "logistics_science")]
	testing.expect(t, !logistics_science.placeholder)
	testing.expect(t, slice.contains(logistics_science.unlocks, test_recipe(test.recipes, "science_pack_2")))
}

@(test)
test_science_pack_2_costs_on_fast_belts :: proc(t: ^testing.T) {
	content := make_test_content()
	technologies := content.technologies
	fast_belts := technologies.technologies[test_technology(technologies, "fast_belts")]
	first, second := test_item(content.items, "science_pack_1"), test_item(content.items, "science_pack_2")
	testing.expect(t, slice.equal(fast_belts.science_packs, []Item_Id{first, second}))
	lab := make_lab({}, len(content.machines.lab_packs))
	testing.expect_value(t, lab.slot_count, 2)
	lab.slots[lab_slot_of(content.machines.lab_packs, first)] = {first, 3}
	testing.expect(t, !lab_has_packs(lab, fast_belts, content.machines.lab_packs))
	lab.slots[lab_slot_of(content.machines.lab_packs, second)] = {second, 3}
	testing.expect(t, lab_has_packs(lab, fast_belts, content.machines.lab_packs))
	take_pack_set(&lab, fast_belts, content.machines.lab_packs)
	testing.expect_value(t, lab.slots[0].count + lab.slots[1].count, 4)
	// A science pack 1 technology leaves pack 2 alone.
	automation := technologies.technologies[test_technology(technologies, "automation")]
	take_pack_set(&lab, automation, content.machines.lab_packs)
	testing.expect_value(t, lab.slots[lab_slot_of(content.machines.lab_packs, second)].count, 2)
}

// Beside the power plant: a tar pit pump feeding a refinery (with 200 L
// of crude oil to start) whose gas runs to a chemical plant making plastic
// from coal, and a wood gasifier whose wood gas runs to a second chemical
// plant making syngas plastic from charcoal, on four more poles.
Chemistry_Plant :: struct {
	refinery:        Entity_Handle,
	fossil_plant:    Entity_Handle,
	gasifier:        Entity_Handle,
	renewable_plant: Entity_Handle,
}

build_chemistry_plant :: proc(world: ^World, content: Simulation_Content) -> (plant: Chemistry_Plant) {
	build_power_plant(world, content)
	world_set_block(world, {-4, 0, 0}, test_block(content.blocks, "tar_pit"))
	place_test_fluid_entity(world, content, "tar_pit_pump", {-6, 1, 0})
	lay_pipes(world, content, {-7, 1, 0}, {-8, 1, 0}, {-9, 1, 0})
	plant.refinery = place_test_entity(world, content, "refinery", {-11, 1, 1})
	pool_get(&world.entities.assemblers, plant.refinery).buffers[0] = {fluid = test_fluid(content, "crude_oil"), level = 200}
	lay_pipes(world, content, {-12, 1, 3}, {-13, 1, 3}, {-14, 1, 3})
	plant.fossil_plant = place_test_entity(world, content, "chemical_plant", {-15, 1, 4})
	pool_get(&world.entities.assemblers, plant.fossil_plant).slots[0] = {test_item(content.items, "coal"), 10}
	plant.gasifier = place_test_entity(world, content, "wood_gasifier", {-15, 1, -6})
	pool_get(&world.entities.assemblers, plant.gasifier).slots[0] = {test_item(content.items, "log"), 40}
	lay_pipes(world, content, {-15, 1, -4})
	plant.renewable_plant = place_test_entity(world, content, "chemical_plant", {-16, 1, -3})
	pool_get(&world.entities.assemblers, plant.renewable_plant).slots[0] = {test_item(content.items, "charcoal"), 10}
	place_test_entity(world, content, "small_pole", {-2, 1, 2})
	place_test_entity(world, content, "small_pole", {-7, 1, -1})
	place_test_entity(world, content, "small_pole", {-13, 1, 1})
	place_test_entity(world, content, "small_pole", {-12, 1, 7})
	place_test_entity(world, content, "small_pole", {-13, 1, -5})
	return
}

@(test)
test_chemistry_simulation_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_oil_world(content), make_oil_world(content)}
	all_records := [2]Game_Records{make_fluid_test_records(content), make_fluid_test_records(content)}
	plant: Chemistry_Plant
	for &world, index in worlds {
		plant = build_chemistry_plant(&world, content)
		tick_test_entities(&world, &all_records[index], content, 1200)
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	for machine, index in first.assemblers.entries {
		other := second.assemblers.entries[index]
		testing.expect_value(t, machine.buffers, other.buffers)
		testing.expect_value(t, machine.slots, other.slots)
		testing.expect_value(t, machine.progress_ticks, other.progress_ticks)
		testing.expect_value(t, machine.state, other.state)
	}
	for machine, index in first.fluid_machines.entries {
		testing.expect_value(t, machine.buffers, second.fluid_machines.entries[index].buffers)
	}
	for pipe, index in first.pipes.entries {
		testing.expect_value(t, pipe.buffer, second.pipes.entries[index].buffer)
	}
	world, records := &worlds[0], &all_records[0]
	plastic := test_item(content.items, "plastic_bar")
	fossil := pool_get(&world.entities.assemblers, plant.fossil_plant)
	renewable := pool_get(&world.entities.assemblers, plant.renewable_plant)
	testing.expectf(t, fossil.slots[1].item == plastic && fossil.slots[1].count > 0, "fossil plastic %v", fossil.slots[1])
	testing.expectf(t, renewable.slots[1].item == plastic && renewable.slots[1].count > 0, "renewable plastic %v", renewable.slots[1])
	testing.expect(t, fossil.slots[0].count < 10 && renewable.slots[0].count < 10)
	testing.expect(t, fluid_counter(records.statistics.fluids.consumed, test_fluid(content, "petroleum_gas")) > 0)
	testing.expect(t, fluid_counter(records.statistics.fluids.consumed, test_fluid(content, "wood_gas")) > 0)
	testing.expect(t, fluid_counter(records.statistics.fluids.produced, test_fluid(content, "crude_oil")) > 0)
	testing.expect_value(t, item_counter(records.statistics.produced, plastic), u64(fossil.slots[1].count + renewable.slots[1].count))
}
