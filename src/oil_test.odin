package game

import "core:testing"

// Oil, gases and the refinery (work item 0030). Oil worlds stand on the
// stone floor of make_floor_world (top at y 1) with fluid statistics.

make_oil_world :: proc(content: Simulation_Content) -> World {
	world := make_floor_world(content.blocks, 32)
	world.statistics = make_statistics(len(content.items.items), len(content.machines.machines), len(content.blocks.definitions), context.temp_allocator)
	world.statistics.fluids = make_fluid_statistics(len(content.fluids.fluids), context.temp_allocator)
	return world
}

test_oil_assembler :: proc(world: ^World, handle: Entity_Handle) -> ^Assembler {
	return pool_get(&world.entities.assemblers, handle)
}

// A crafting machine with full power, which tick_assemblers keeps.
place_powered_crafting_machine :: proc(world: ^World, content: Simulation_Content, id: string, origin: World_Coordinate) -> Entity_Handle {
	handle := place_test_entity(world, content, id, origin)
	test_oil_assembler(world, handle).power.satisfaction = POWER_FULL
	return handle
}

tick_test_assemblers :: proc(world: ^World, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		tick_assemblers(world, content, TEST_TICK_RATE)
	}
}

@(test)
test_oil_data_loads :: proc(t: ^testing.T) {
	content := make_test_content()
	crude, gas := test_fluid(content, "crude_oil"), test_fluid(content, "petroleum_gas")
	light, heavy := test_fluid(content, "light_oil"), test_fluid(content, "heavy_oil")
	testing.expect(t, fluid_is_gas(content.fluids, gas))
	testing.expect(t, !fluid_is_gas(content.fluids, crude) && !fluid_is_gas(content.fluids, light) && !fluid_is_gas(content.fluids, heavy))
	refinery := content.machines.machines[test_machine(content.machines, "refinery")]
	testing.expect_value(t, refinery.footprint, [3]i32{5, 3, 5})
	testing.expect_value(t, refinery.electric_power_watts, 400_000)
	testing.expect_value(t, refinery.recipe_maker, Recipe_Maker.Refinery)
	expected := [4]Fluid_Id{crude, gas, light, heavy}
	for fluid, index in expected {
		testing.expect_value(t, refinery.fluid_ports[index].filter, fluid)
	}
	testing.expect_value(t, output_port_index(refinery, 0), 1)
	testing.expect_value(t, output_port_index(refinery, 2), 3)
	testing.expect_value(t, output_port_index(refinery, 3), -1)
	flare := content.machines.machines[test_machine(content.machines, "flare_stack")]
	testing.expect_value(t, flare.kind, Machine_Kind.Flare_Stack)
	testing.expect_value(t, flare.fluid_ports[0].phase_filter, Fluid_Phase_Filter.Gas)
	testing.expect(t, flare.fluid_ports[0].every_face)
	pump := content.machines.machines[test_machine(content.machines, "tar_pit_pump")]
	testing.expect_value(t, pump.fluid_litres_per_minute, 600)
	testing.expect_value(t, pump.electric_power_watts, 60_000)
	testing.expect_value(t, pump.fluid_ports[0].filter, crude)
	testing.expect_value(t, content.machines.machines[test_machine(content.machines, "cracking_unit")].electric_power_watts, 200_000)
	testing.expect_value(t, block_fluid_source(content.blocks, test_block(content.blocks, "tar_pit")), "crude_oil")
	refining := content.recipes.recipes[test_recipe(content.recipes, "refining")]
	testing.expect_value(t, len(refining.inputs) + len(refining.outputs), 0)
	testing.expect_value(t, refining.fluid_outputs[0], Recipe_Fluid{gas, 45})
	testing.expect_value(t, refining.milliseconds, 5000)
}

@(test)
test_recipe_fluid_outputs_are_validated :: proc(t: ^testing.T) {
	content := make_test_content()
	refinery := content.machines.machines[test_machine(content.machines, "refinery")]
	refining := content.recipes.recipes[test_recipe(content.recipes, "refining")]
	testing.expect_value(t, validate_crafting_machine_recipe(refinery, refining), "")
	// Gas into the light oil port.
	swapped := refining
	swapped.fluid_outputs = {refining.fluid_outputs[1], refining.fluid_outputs[0]}
	testing.expect(t, validate_crafting_machine_recipe(refinery, swapped) != "")
	// More fluid outputs than output ports.
	four := refining
	four.fluid_outputs = {refining.fluid_outputs[0], refining.fluid_outputs[1], refining.fluid_outputs[2], {test_fluid(content, "water"), 1}}
	testing.expect(t, validate_crafting_machine_recipe(refinery, four) != "")
	// Fluid outputs need a machine with ports, and a recipe without item
	// outputs needs a name.
	definition := test_recipe_definition()
	definition.fluid_outputs = {{fluid = "water", litres = 10}}
	testing.expect(t, resolve_test_recipes({definition}) != "")
	unnamed := test_recipe_definition()
	unnamed.outputs = nil
	unnamed.made_in = {"refinery"}
	unnamed.fluid_outputs = {{fluid = "water", litres = 10}}
	testing.expect(t, resolve_test_recipes({unnamed}) != "")
	unnamed.name_key = "recipe_refining"
	testing.expect_value(t, resolve_test_recipes({unnamed}), "")
}

// A refinery with 200 L of crude oil and full power.
make_refinery_world :: proc(content: Simulation_Content) -> (world: World, refinery: Entity_Handle) {
	world = make_oil_world(content)
	refinery = place_powered_crafting_machine(&world, content, "refinery", {0, 1, 0})
	test_oil_assembler(&world, refinery).buffers[0] = {fluid = test_fluid(content, "crude_oil"), level = 200}
	return
}

@(test)
test_refinery_splits_crude_oil :: proc(t: ^testing.T) {
	content := make_test_content()
	world, refinery := make_refinery_world(content)
	tick_test_assemblers(&world, content, 299)
	machine := test_oil_assembler(&world, refinery)
	testing.expect_value(t, machine.state, Assembler_State.Working)
	testing.expect_value(t, machine.buffers[1].level, 0)
	tick_test_assemblers(&world, content, 1)
	machine = test_oil_assembler(&world, refinery)
	testing.expect_value(t, machine.buffers[0].level, 100)
	testing.expect_value(t, machine.buffers[1], Fluid_Buffer{fluid = test_fluid(content, "petroleum_gas"), level = 45})
	testing.expect_value(t, machine.buffers[2], Fluid_Buffer{fluid = test_fluid(content, "light_oil"), level = 30})
	testing.expect_value(t, machine.buffers[3], Fluid_Buffer{fluid = test_fluid(content, "heavy_oil"), level = 25})
	fluids := world.statistics.fluids
	testing.expect_value(t, fluid_counter(fluids.consumed, test_fluid(content, "crude_oil")), 100)
	testing.expect_value(t, fluid_counter(fluids.produced, test_fluid(content, "petroleum_gas")), 45)
	testing.expect_value(t, fluid_counter(fluids.produced, test_fluid(content, "heavy_oil")), 25)
	// A second craft, then no crude oil left.
	tick_test_assemblers(&world, content, 301)
	machine = test_oil_assembler(&world, refinery)
	testing.expect_value(t, machine.buffers[1].level, 90)
	testing.expect_value(t, machine.buffers[0].level, 0)
	testing.expect_value(t, machine.state, Assembler_State.No_Fluid)
}

// Each fraction leaves by its own face: pipes on the -x, +z and +x faces
// take gas, light oil and heavy oil.
@(test)
test_refinery_outputs_leave_by_their_faces :: proc(t: ^testing.T) {
	content := make_test_content()
	world, refinery := make_refinery_world(content)
	pipes := lay_pipes(&world, content, {-1, 1, 2}, {2, 1, 5}, {5, 1, 2})
	testing.expect_value(t, len(world.entities.fluid_networks.networks), 4)
	tick_test_assemblers(&world, content, 300)
	tick_test_fluids(&world, content, 10)
	expected := [3]string{"petroleum_gas", "light_oil", "heavy_oil"}
	for id, index in expected {
		testing.expect_value(t, test_pipe(&world, pipes[index]).buffer.fluid, test_fluid(content, id))
		testing.expect(t, test_pipe(&world, pipes[index]).buffer.level > 0)
	}
	testing.expect_value(t, test_oil_assembler(&world, refinery).buffers[0].level, 100)
}

// A pipe holding light oil at the gas face stays light oil, and the gas
// port stays closed and full.
@(test)
test_refinery_refuses_to_mix_on_a_wrong_port :: proc(t: ^testing.T) {
	content := make_test_content()
	world, refinery := make_refinery_world(content)
	pipe := lay_pipes(&world, content, {-1, 1, 2})[0]
	test_pipe(&world, pipe).buffer = {fluid = test_fluid(content, "light_oil"), level = 50}
	rebuild_fluid_networks(&world.entities, content.machines)
	tick_test_assemblers(&world, content, 300)
	tick_test_fluids(&world, content, 10)
	testing.expect_value(t, test_pipe(&world, pipe).buffer, Fluid_Buffer{fluid = test_fluid(content, "light_oil"), level = 50})
	testing.expect_value(t, test_oil_assembler(&world, refinery).buffers[1].level, 45)
	testing.expect(t, test_oil_assembler(&world, refinery).closed[1])
}

// A full gas port stops a strict refinery; with the gas flagged as a
// byproduct a lenient world voids it and counts it.
@(test)
test_fluid_byproducts_follow_the_strictness :: proc(t: ^testing.T) {
	content := make_test_content()
	gas := test_fluid(content, "petroleum_gas")
	world, refinery := make_refinery_world(content)
	test_oil_assembler(&world, refinery).buffers[1] = {fluid = gas, level = 200}
	tick_test_assemblers(&world, content, 10)
	testing.expect_value(t, test_oil_assembler(&world, refinery).state, Assembler_State.Output_Full)
	testing.expect_value(t, test_oil_assembler(&world, refinery).buffers[0].level, 200)
	// Only a flagged byproduct is voided, even in a lenient world.
	world.settings.byproducts_lenient = true
	tick_test_assemblers(&world, content, 10)
	testing.expect_value(t, test_oil_assembler(&world, refinery).state, Assembler_State.Output_Full)
	refining := content.recipes.recipes[test_recipe(content.recipes, "refining")]
	refining.fluid_byproducts = {0}
	lenient_content := content
	lenient_content.recipes = Recipe_Registry{recipes = {refining}}
	tick_test_assemblers(&world, lenient_content, 300)
	machine := test_oil_assembler(&world, refinery)
	testing.expect_value(t, machine.buffers[0].level, 100)
	testing.expect_value(t, machine.buffers[1].level, 200)
	testing.expect_value(t, machine.buffers[2].level, 30)
	testing.expect_value(t, fluid_counter(world.statistics.fluids.voided, gas), 45)
	testing.expect_value(t, fluid_counter(world.statistics.fluids.produced, gas), 0)
}

// A flare stack beside a pipe: gas flows in and burns at 1 L per tick
// while powered, and counts as voided; a liquid never enters.
make_flare_world :: proc(content: Simulation_Content, fluid: string) -> (world: World, flare, pipe: Entity_Handle) {
	world = make_oil_world(content)
	flare = place_test_fluid_entity(&world, content, "flare_stack", {0, 1, 0})
	pipe = lay_pipes(&world, content, {1, 1, 0})[0]
	test_pipe(&world, pipe).buffer = {fluid = test_fluid(content, fluid), level = 100}
	return
}

tick_test_fluids_with_statistics :: proc(world: ^World, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		tick_fluids(&world.entities, content, TEST_TICK_RATE, &world.statistics)
	}
}

@(test)
test_flare_stack_burns_gas_with_power :: proc(t: ^testing.T) {
	content := make_test_content()
	gas := test_fluid(content, "petroleum_gas")
	world, flare, pipe := make_flare_world(content, "petroleum_gas")
	tick_test_fluids_with_statistics(&world, content, 20)
	testing.expect_value(t, test_fluid_machine(&world, flare).state, Fluid_Machine_State.Unpowered)
	testing.expect_value(t, test_pipe(&world, pipe).buffer.level + test_fluid_machine(&world, flare).buffers[0].level, 100)
	test_fluid_machine(&world, flare).power.satisfaction = POWER_FULL
	tick_test_fluids_with_statistics(&world, content, 60)
	testing.expect_value(t, test_fluid_machine(&world, flare).state, Fluid_Machine_State.Flaring)
	testing.expect_value(t, test_pipe(&world, pipe).buffer.level + test_fluid_machine(&world, flare).buffers[0].level, 40)
	testing.expect_value(t, fluid_counter(world.statistics.fluids.voided, gas), 60)
	testing.expect_value(t, fluid_counter(world.statistics.fluids.consumed, gas), 60)
	tick_test_fluids_with_statistics(&world, content, 60)
	testing.expect_value(t, test_fluid_machine(&world, flare).buffers[0].level, 0)
	testing.expect_value(t, test_fluid_machine(&world, flare).state, Fluid_Machine_State.Idle)
	testing.expect(t, fluid_machine_wants_power(test_fluid_machine(&world, flare)^, content.machines.machines[test_machine(content.machines, "flare_stack")], content.fluids) == false)
}

@(test)
test_flare_stack_refuses_liquids :: proc(t: ^testing.T) {
	content := make_test_content()
	world, flare, pipe := make_flare_world(content, "light_oil")
	test_fluid_machine(&world, flare).power.satisfaction = POWER_FULL
	tick_test_fluids_with_statistics(&world, content, 60)
	testing.expect_value(t, test_pipe(&world, pipe).buffer.level, 100)
	testing.expect_value(t, test_fluid_machine(&world, flare).buffers[0].level, 0)
	testing.expect(t, test_fluid_machine(&world, flare).closed[0])
	testing.expect_value(t, test_fluid_machine(&world, flare).state, Fluid_Machine_State.Idle)
}

// Heavy oil 40 and water 30 make 30 light oil, light oil 30 and water 30
// make 20 petroleum gas, 2 s each.
@(test)
test_cracking_ratios :: proc(t: ^testing.T) {
	content := make_test_content()
	water := test_fluid(content, "water")
	cases := [2][2]string{{"heavy_oil", "light_oil"}, {"light_oil", "petroleum_gas"}}
	used := [2]i32{40, 30}
	made := [2]i32{30, 20}
	for pair, index in cases {
		world := make_oil_world(content)
		unit := place_powered_crafting_machine(&world, content, "cracking_unit", {0, 1, 0})
		machine := test_oil_assembler(&world, unit)
		machine.buffers[0] = {fluid = test_fluid(content, pair[0]), level = 200}
		machine.buffers[1] = {fluid = water, level = 200}
		tick_test_assemblers(&world, content, 120)
		machine = test_oil_assembler(&world, unit)
		testing.expect_value(t, machine.recipe, test_recipe(content.recipes, index == 0 ? "heavy_oil_cracking" : "light_oil_cracking"))
		testing.expect_value(t, machine.buffers[0].level, 200 - used[index])
		testing.expect_value(t, machine.buffers[1].level, 170)
		testing.expect_value(t, machine.buffers[2], Fluid_Buffer{fluid = test_fluid(content, pair[1]), level = made[index]})
	}
}

// Light oil made from heavy oil waits in the output port; it is not taken
// back in as the input of light oil cracking.
@(test)
test_cracking_unit_does_not_draw_from_its_output :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_oil_world(content)
	unit := place_powered_crafting_machine(&world, content, "cracking_unit", {0, 1, 0})
	machine := test_oil_assembler(&world, unit)
	machine.buffers[1] = {fluid = test_fluid(content, "water"), level = 200}
	machine.buffers[2] = {fluid = test_fluid(content, "light_oil"), level = 100}
	tick_test_assemblers(&world, content, 200)
	machine = test_oil_assembler(&world, unit)
	testing.expect_value(t, machine.buffers[2].level, 100)
	testing.expect_value(t, machine.state, Assembler_State.No_Fluid)
}

@(test)
test_tar_pit_pump_placement :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	machine := test_machine(content.machines, "tar_pit_pump")
	testing.expect(t, !placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	world_set_block(&world, {2, 0, 0}, test_block(content.blocks, "water"))
	testing.expect(t, !placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	world_set_block(&world, {2, 0, 0}, test_block(content.blocks, "tar_pit"))
	testing.expect(t, placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	// Turned round, the intake looks at the stone floor.
	testing.expect(t, !placement_at(&world, content, nil, machine, {0, 1, 0}, 2).valid)
	// An offshore pump does not take a tar pit for water.
	testing.expect(t, !placement_at(&world, content, nil, test_machine(content.machines, "offshore_pump"), {0, 1, 0}, 0).valid)
}

// 600 L per minute, so two pumps feed one refinery: a litre every 6
// ticks, only with power.
@(test)
test_tar_pit_pump_pumps_crude_oil :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_oil_world(content)
	pump := place_test_fluid_entity(&world, content, "tar_pit_pump", {0, 1, 0})
	tick_test_fluids_with_statistics(&world, content, 100)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Unpowered)
	testing.expect_value(t, test_fluid_machine(&world, pump).buffers[0].level, 0)
	test_fluid_machine(&world, pump).power.satisfaction = POWER_FULL
	tick_test_fluids_with_statistics(&world, content, 600)
	crude := test_fluid(content, "crude_oil")
	testing.expect_value(t, test_fluid_machine(&world, pump).buffers[0], Fluid_Buffer{fluid = crude, level = 100})
	testing.expect_value(t, fluid_counter(world.statistics.fluids.produced, crude), 100)
	// At half power it pumps every other tick.
	test_fluid_machine(&world, pump).power.satisfaction = POWER_FULL / 2
	tick_test_fluids_with_statistics(&world, content, 1200)
	testing.expect_value(t, test_fluid_machine(&world, pump).buffers[0].level, 200)
	tick_test_fluids_with_statistics(&world, content, 100)
	testing.expect_value(t, test_fluid_machine(&world, pump).state, Fluid_Machine_State.Output_Full)
	testing.expect_value(t, test_fluid_machine(&world, pump).buffers[0].level, 200)
}

@(test)
test_accumulated_litres_are_exact :: proc(t: ^testing.T) {
	remainder: u32
	total: i32
	for _ in 0 ..< 3600 {
		total += accumulate_litres(&remainder, 200, TEST_TICK_RATE)
	}
	testing.expect_value(t, total, 200)
	testing.expect_value(t, remainder, 0)
}

// Tar pits sit in the low spots of the tar flats: no higher than the pit
// height above sea level and no face neighbour lower.
@(test)
test_tar_pits_mark_low_spots :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	flats := find_biome_index(generator.biomes, "tar_flats")
	plains := find_biome_index(generator.biomes, "plains")
	testing.expect(t, flats >= 0 && generator.biomes[flats].pit_block == test_block(make_test_registry(), "tar_pit"))
	grid: Column_Grid
	for &column in grid {
		column = Column_Sample{height = SEA_LEVEL + 2, biome = flats}
	}
	grid[column_grid_index(4, 4)].height = SEA_LEVEL + 1
	grid[column_grid_index(5, 4)].height = SEA_LEVEL + 1
	testing.expect(t, column_is_pit(&generator, &grid, 4, 4))
	testing.expect(t, column_is_pit(&generator, &grid, 5, 4))
	testing.expect(t, !column_is_pit(&generator, &grid, 6, 4))
	// A lower neighbour makes it no low spot.
	grid[column_grid_index(4, 5)].height = SEA_LEVEL
	testing.expect(t, !column_is_pit(&generator, &grid, 4, 4))
	testing.expect(t, column_is_pit(&generator, &grid, 4, 5))
	// Other biomes have no pits.
	grid[column_grid_index(4, 5)].biome = plains
	testing.expect(t, !column_is_pit(&generator, &grid, 4, 5))
}

@(test)
test_fluid_rate_rings :: proc(t: ^testing.T) {
	content := make_test_content()
	statistics := make_statistics(len(content.items.items), 2, 2, context.temp_allocator)
	statistics.fluids = make_fluid_statistics(len(content.fluids.fluids), context.temp_allocator)
	gas := test_fluid(content, "petroleum_gas")
	for second in u64(0) ..< 30 {
		advance_statistics_clock(&statistics, second * TEST_TICK_RATE, TEST_TICK_RATE)
		record_fluid_produced(&statistics, gas, 45)
		record_fluid_voided(&statistics, gas, 5)
	}
	testing.expect_value(t, fluid_window_total(statistics.fluids.produced_rates, gas, .One_Minute, statistics.current_second), 30 * 45)
	testing.expect_value(t, fluid_window_total(statistics.fluids.voided_rates, gas, .One_Minute, statistics.current_second), 150)
	// Ninety seconds later the minute window is empty and the ten minute
	// window still holds everything.
	advance_statistics_clock(&statistics, 120 * TEST_TICK_RATE, TEST_TICK_RATE)
	testing.expect_value(t, fluid_window_total(statistics.fluids.produced_rates, gas, .One_Minute, statistics.current_second), 0)
	testing.expect_value(t, fluid_window_total(statistics.fluids.produced_rates, gas, .Ten_Minutes, statistics.current_second), 30 * 45)
	rows := fluid_statistics_rows(statistics, .Ten_Minutes, context.temp_allocator)
	testing.expect_value(t, len(rows), 1)
	testing.expect_value(t, rows[0], Fluid_Rate_Row{fluid = gas, produced = 1350, voided = 150})
	testing.expect_value(t, format_fluid_window_rate(1350, .Ten_Minutes), "135 L/min")
	// Buffer changes: a loss is consumed, a gain produced.
	before := [2]Fluid_Buffer{{fluid = gas, level = 50}, {fluid = gas, level = 0}}
	after := [2]Fluid_Buffer{{fluid = gas, level = 20}, {fluid = gas, level = 10}}
	record_buffer_changes(&statistics, before[:], after[:])
	testing.expect_value(t, fluid_counter(statistics.fluids.consumed, gas), 30)
	testing.expect_value(t, fluid_counter(statistics.fluids.produced, gas), 30 * 45 + 10)
}

// oil_processing waits for its main quest; afterwards the labs may
// research cracking, and the refinery recipes open.
@(test)
test_oil_technologies_are_gated :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies := test.technologies
	oil, cracking := test_technology(technologies, "oil_processing"), test_technology(technologies, "cracking")
	for id in ([?]string{"automation", "steel_processing", "ore_processing"}) {
		mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, id))
	}
	research: Research_State
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, oil), Research_Refusal.Quest_Gate)
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, cracking), Research_Refusal.Locked)
	refining, cracking_unit := test_recipe(test.recipes, "refining"), test_recipe(test.recipes, "cracking_unit")
	testing.expect(t, !recipe_is_available(test.unlocks, refining))
	mark_technology_researched(&test.unlocks, test.recipes, oil)
	testing.expect(t, recipe_is_available(test.unlocks, refining))
	testing.expect(t, recipe_is_available(test.unlocks, test_recipe(test.recipes, "tar_pit_pump")))
	testing.expect(t, !recipe_is_available(test.unlocks, cracking_unit))
	testing.expect_value(t, technology_status(technologies, test.unlocks, cracking), Technology_Status.Available)
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, cracking), Research_Refusal.None)
	mark_technology_researched(&test.unlocks, test.recipes, cracking)
	testing.expect(t, recipe_is_available(test.unlocks, cracking_unit))
	testing.expect(t, recipe_is_available(test.unlocks, test_recipe(test.recipes, "light_oil_cracking")))
}

// The power plant of the power tests, and beside it a tar pit pump on a
// tar pit feeding a refinery (with 200 L of crude oil to start), whose
// heavy oil feeds a cracking unit and whose gas a flare stack, on three
// more poles.
build_oil_plant :: proc(world: ^World, content: Simulation_Content) -> (refinery, unit, flare: Entity_Handle) {
	build_power_plant(world, content)
	world_set_block(world, {-4, 0, 0}, test_block(content.blocks, "tar_pit"))
	place_test_fluid_entity(world, content, "tar_pit_pump", {-6, 1, 0})
	lay_pipes(world, content, {-7, 1, 0}, {-8, 1, 0}, {-9, 1, 0})
	refinery = place_test_entity(world, content, "refinery", {-11, 1, 1})
	pool_get(&world.entities.assemblers, refinery).buffers[0] = {fluid = test_fluid(content, "crude_oil"), level = 200}
	lay_pipes(world, content, {-6, 1, 3}, {-5, 1, 3}, {-4, 1, 3})
	unit = place_test_entity(world, content, "cracking_unit", {-5, 1, 4})
	pool_get(&world.entities.assemblers, unit).buffers[1] = {fluid = test_fluid(content, "water"), level = 200}
	flare = place_test_fluid_entity(world, content, "flare_stack", {-12, 1, 3})
	place_test_entity(world, content, "small_pole", {-2, 1, 2})
	place_test_entity(world, content, "small_pole", {-7, 1, -1})
	place_test_entity(world, content, "small_pole", {-13, 1, 1})
	return
}

@(test)
test_oil_simulation_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_oil_world(content), make_oil_world(content)}
	refinery, unit, flare: Entity_Handle
	for &world in worlds {
		refinery, unit, flare = build_oil_plant(&world, content)
		tick_test_entities(&world, content, 1200)
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	for machine, index in first.fluid_machines.entries {
		other := second.fluid_machines.entries[index]
		testing.expect_value(t, machine.buffers, other.buffers)
		testing.expect_value(t, machine.state, other.state)
		testing.expect_value(t, machine.litre_remainder, other.litre_remainder)
	}
	for machine, index in first.assemblers.entries {
		other := second.assemblers.entries[index]
		testing.expect_value(t, machine.buffers, other.buffers)
		testing.expect_value(t, machine.progress_ticks, other.progress_ticks)
	}
	for pipe, index in first.pipes.entries {
		testing.expect_value(t, pipe.buffer, second.pipes.entries[index].buffer)
	}
	world := &worlds[0]
	fluids := world.statistics.fluids
	testing.expect(t, fluid_counter(fluids.produced, test_fluid(content, "crude_oil")) > 0)
	gas := test_fluid(content, "petroleum_gas")
	testing.expectf(t, fluid_counter(fluids.produced, gas) == 90, "gas produced %d", fluid_counter(fluids.produced, gas))
	testing.expectf(t, fluid_counter(fluids.voided, gas) == 90, "gas voided %d", fluid_counter(fluids.voided, gas))
	// One crack done; the second waits for its full 40 L of heavy oil
	// instead of starting on the 10 L left.
	testing.expectf(t, fluid_counter(fluids.consumed, test_fluid(content, "heavy_oil")) == 40, "heavy consumed %d", fluid_counter(fluids.consumed, test_fluid(content, "heavy_oil")))
	testing.expect(t, fluid_counter(fluids.consumed, test_fluid(content, "steam")) > 0)
	testing.expectf(t, pool_get(&world.entities.assemblers, unit).buffers[2].level == 30, "light oil from cracking %d", pool_get(&world.entities.assemblers, unit).buffers[2].level)
	testing.expectf(t, pool_get(&world.entities.fluid_machines, flare).state == .Idle, "flare %v", pool_get(&world.entities.fluid_machines, flare).state)
	// One pump's 600 L per minute is half of a refinery's 1200.
	testing.expectf(t, pool_get(&world.entities.assemblers, refinery).state == .No_Fluid, "refinery %v", pool_get(&world.entities.assemblers, refinery).state)
}

// The storage tank takes any fluid, gases included, so phase 6 needs no
// separate gas tank.
@(test)
test_storage_tank_holds_gas :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_oil_world(content)
	gas := test_fluid(content, "petroleum_gas")
	tank := place_test_fluid_entity(&world, content, "storage_tank", {0, 1, 0})
	// A pipe on the tank's top layer: gas ignores height.
	pipe := lay_pipes(&world, content, {3, 3, 1})[0]
	test_pipe(&world, pipe).buffer = {fluid = gas, level = 100}
	tick_test_fluids(&world, content, 20)
	testing.expect_value(t, test_fluid_machine(&world, tank).buffers[0].fluid, gas)
	testing.expect(t, test_fluid_machine(&world, tank).buffers[0].level > 90)
	testing.expect(t, !test_fluid_machine(&world, tank).closed[0])
}
