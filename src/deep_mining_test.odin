package game

import "core:fmt"
import "core:slice"
import "core:testing"

// Deep veins, bore drills, vein revival and the deep ores (work item 0035).

// Registered like a loaded chunk column registers a deep vein: the record
// and the column entries, no outcrop.
add_test_deep_vein :: proc(world: ^World, content: Simulation_Content, type_id: string, centre: [2]i32, radius: i32, remaining: [MAXIMUM_VEIN_OUTPUTS]i64, index: i32 = 0) -> Vein_Id {
	vein := Vein {
		id        = {region = {0, 0}, index = index, layer = .Deep},
		type      = test_vein_type(content, type_id),
		centre    = {centre.x, -60, centre.y},
		radius    = radius,
		depth     = 61,
		remaining = remaining,
	}
	register_vein(world, vein)
	chunks := TEST_WORLD_CHUNKS
	for chunk in chunks {
		column := chunk_column_of(chunk)
		ids := world.column_veins[column] or_else make([dynamic]Vein_Id, context.temp_allocator)
		if vein_overlaps_column(vein, column) && !slice.contains(ids[:], vein.id) {
			append(&ids, vein.id)
		}
		world.column_veins[column] = ids
	}
	return vein.id
}

// A drill world with fluid statistics, so fluid use is counted.
make_deep_mining_world :: proc(content: Simulation_Content) -> World {
	world := make_drill_world(content)
	world.statistics.fluids = make_fluid_statistics(len(content.fluids.fluids), context.temp_allocator)
	return world
}

// A bore drill over a bauxite vein at (1, 1), dropping into a chest at
// (3, 1, 0), with a pole and a steam engine whose offer the test sets
// every tick (tick_with_engine_offer).
make_bore_drill_test :: proc(content: Simulation_Content) -> Drill_Power_Test {
	test := Drill_Power_Test {
		world = make_deep_mining_world(content),
	}
	test.world.settings.seed = 4242
	vein := add_test_deep_vein(&test.world, content, "bauxite", {1, 1}, 3, {85_000, 15_000, 0, 0})
	test.drill = place_test_entity(&test.world, content, "bore_drill", {-1, 1, -1})
	test_drill(&test.world, test.drill).vein = vein
	test.chest = place_test_entity(&test.world, content, "iron_chest", {3, 1, 0})
	_, test.engine = add_test_power_plant(&test.world, content, {4, 1, 3}, {5, 1, -2})
	return test
}

@(test)
test_deep_veins_are_placed_below_the_surface :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	tables := generator.veins
	found_types: map[string]bool
	defer delete(found_types)
	count := 0
	for region_z in i32(-4) ..< 4 {
		for region_x in i32(-4) ..< 4 {
			region := Region_Coordinate{region_x, region_z}
			for vein, index in layer_veins(&generator, region, .Deep, context.temp_allocator) {
				definition := tables.types[vein.type].definition
				testing.expect(t, definition.deep)
				testing.expect(t, vein_is_deep(vein))
				testing.expect_value(t, vein.id, Vein_Id{region = region, index = i32(index), layer = .Deep})
				testing.expect(t, vein.depth >= tables.deep_minimum_depth && vein.depth <= tables.deep_maximum_depth)
				surface := sample_column(&generator, vein.centre.x, vein.centre.z).height
				testing.expect_value(t, vein.centre.y, surface - vein.depth)
				minimum := tables.size_classes[vein.size_class].minimum_units * tables.deep_units_factor
				testing.expect(t, vein_remaining_total(vein) >= minimum * 99 / 100)
				found_types[definition.id] = true
				count += 1
			}
			for vein in region_veins(&generator, region, context.temp_allocator) {
				testing.expect(t, !vein_is_deep(vein))
				testing.expect_value(t, vein.depth, 0)
				testing.expect(t, !tables.types[vein.type].definition.deep)
			}
		}
	}
	testing.expect(t, count > 50)
	for id in ([?]string{"deep_iron", "deep_copper", "bauxite", "gold_quartz", "deep_pentlandite"}) {
		testing.expectf(t, found_types[id], "no %s vein in 64 regions", id)
	}
}

// Every deep vein is listed by the columns its disc reaches, next to the
// surface veins, and the column lookup finds it under its centre.
@(test)
test_deep_vein_column_lookup :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	veins := layer_veins(&generator, {1, -1}, .Deep, context.temp_allocator)
	testing.expect(t, len(veins) > 0)
	for vein in veins {
		testing.expect(t, expect_vein_in_every_overlapping_column(t, &generator, vein) > 0)
		world: World
		defer destroy_world(&world)
		column := chunk_column_of(world_to_chunk_coordinate(vein.centre))
		found := column_veins(&generator, column, context.temp_allocator)
		register_column_veins(&world, column, found[:])
		id, deep_found := deep_vein_at_column(&world, vein.centre.x, vein.centre.z)
		testing.expect(t, deep_found)
		testing.expect_value(t, id, vein.id)
		// Just past the disc: no deep vein of the region reaches there.
		_, outside := deep_vein_at_column(&world, vein.centre.x + vein.radius + 1, vein.centre.z)
		testing.expect(t, !outside)
	}
}

// Two veins with the same region and index draw different streams when
// their layers differ.
@(test)
test_deep_vein_draw_stream_is_its_own :: proc(t: ^testing.T) {
	surface := Vein {
		id = {region = {3, -2}, index = 1},
	}
	deep := surface
	deep.id.layer = .Deep
	testing.expect(t, vein_draw_hash(99, surface) != vein_draw_hash(99, deep))
	testing.expect(t, surface.id != deep.id)
}

@(test)
test_bore_drill_placement_needs_a_deep_vein :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_deep_mining_world(content)
	vein := add_test_deep_vein(&world, content, "bauxite", {1, 1}, 2, {100, 0, 0, 0})
	bore := test_machine(content.machines, "bore_drill")
	// The centre column of a 4 by 4 footprint at (-1, -1) is (1, 1).
	over := placement_at(&world, content, nil, bore, {-1, 1, -1}, 0)
	testing.expect(t, over.valid)
	testing.expect(t, over.drill)
	testing.expect_value(t, over.vein, vein)
	// Footprint cells over the disc are not enough: the centre must be.
	testing.expect(t, !placement_at(&world, content, nil, bore, {2, 1, 2}, 0).valid)
	testing.expect(t, !placement_at(&world, content, nil, bore, {10, 1, 10}, 0).valid)
	// Solid ground under every cell, like any machine.
	world_set_block(&world, {0, 0, 0}, AIR_BLOCK)
	testing.expect(t, !placement_at(&world, content, nil, bore, {-1, 1, -1}, 0).valid)
	// Surface drills need an outcrop, which a deep vein does not have.
	burner := test_machine(content.machines, "burner_mining_drill")
	testing.expect(t, !placement_at(&world, content, nil, burner, {1, 1, 1}, 0).valid)
}

@(test)
test_bore_drill_data :: proc(t: ^testing.T) {
	content := make_test_content()
	bore := test_crafting_machine(content, "bore_drill")
	testing.expect_value(t, bore.kind, Machine_Kind.Drill)
	testing.expect_value(t, bore.footprint, [3]i32{4, 4, 4})
	testing.expect_value(t, bore.electric_power_watts, 300_000)
	testing.expect(t, drill_is_bore(bore))
	testing.expect_value(t, drill_boring_ticks(bore, TEST_TICK_RATE), 180 * 60)
	// 60 units per minute at the surface drill's rule: one a second.
	testing.expect_value(t, drill_cycle_ticks(bore, TEST_TICK_RATE), 60)
	testing.expect_value(t, drill_units_per_minute(bore, TEST_TICK_RATE), f32(60))
	testing.expect_value(t, drill_units_per_minute(bore, TEST_TICK_RATE, true), f32(30))
	mining_fluid := test_fluid(content, "mining_fluid")
	for id in ([?]string{"bore_drill", "electric_mining_drill"}) {
		machine := test_crafting_machine(content, id)
		testing.expect(t, machine.revival_port)
		testing.expect_value(t, machine.fluid_port_count, 1)
		testing.expect_value(t, machine.fluid_ports[REVIVAL_PORT].filter, mining_fluid)
	}
	burner := test_crafting_machine(content, "burner_mining_drill")
	testing.expect(t, !burner.revival_port)
	testing.expect(t, !drill_is_bore(burner))
}

@(test)
test_bore_drill_bores_then_draws_from_the_deep_vein :: proc(t: ^testing.T) {
	content := make_test_content()
	test := make_bore_drill_test(content)
	machine := test_crafting_machine(content, "bore_drill")
	boring := int(drill_boring_ticks(machine, TEST_TICK_RATE))
	// Nothing is bored without power.
	tick_with_engine_offer(&test, content, 0, 100)
	drill := test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.bored_ticks, 0)
	testing.expect_value(t, drill.state, Drill_State.Unpowered)
	tick_with_engine_offer(&test, content, 15_000, boring - 1)
	drill = test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.state, Drill_State.Boring)
	testing.expect_value(t, int(drill.bored_ticks), boring - 1)
	testing.expect(t, drill_progress_fraction(drill^, machine, TEST_TICK_RATE) > 0.99)
	testing.expect_value(t, chest_total(&test.world, test.chest), 0)
	// The last tick of boring, then one unit a second.
	tick_with_engine_offer(&test, content, 15_000, 1 + 600)
	drill = test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.state, Drill_State.Mining)
	testing.expect_value(t, chest_total(&test.world, test.chest), 10)
	vein := registered_vein(&test.world, drill.vein)
	testing.expect_value(t, vein.draws, 10)
	testing.expect_value(t, vein_remaining_total(vein^), 100_000 - 10)
	bauxite := test_item(content.items, "bauxite")
	low_grade := test_item(content.items, "bauxite_low_grade")
	gravel := test_item(content.items, "gravel")
	delivered := chest_count_of(&test.world, test.chest, bauxite) + chest_count_of(&test.world, test.chest, low_grade) + chest_count_of(&test.world, test.chest, gravel)
	testing.expect_value(t, delivered, 10)
}

// A bore drill feeding a chest through the boring's end: two worlds, the
// same state after 1200 ticks.
@(test)
test_bore_drill_line_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := test_crafting_machine(content, "bore_drill")
	tests := [2]Drill_Power_Test{make_bore_drill_test(content), make_bore_drill_test(content)}
	for &test in tests {
		test_drill(&test.world, test.drill).bored_ticks = drill_boring_ticks(machine, TEST_TICK_RATE) - 300
		tick_with_engine_offer(&test, content, 15_000, 1200)
	}
	first, second := &tests[0].world, &tests[1].world
	testing.expect(t, first.entities.drills.entries[0] == second.entities.drills.entries[0])
	testing.expect(t, first.entities.chests.entries[0] == second.entities.chests.entries[0])
	testing.expect(t, first.veins[0] == second.veins[0])
	testing.expect_value(t, chest_total(first, tests[0].chest), 15)
	testing.expect(t, slice.equal(first.statistics.produced, second.statistics.produced))
}

// An electric drill on a nearly empty iron vein: exhausted, then revived
// at half rate by mining fluid in its port, 10 L a unit, the vein left
// empty.
@(test)
test_vein_revival_with_mining_fluid :: proc(t: ^testing.T) {
	content := make_test_content()
	test := make_drill_power_test(content)
	test.world.statistics.fluids = make_fluid_statistics(len(content.fluids.fluids), context.temp_allocator)
	drill := test_drill(&test.world, test.drill)
	vein := registered_vein(&test.world, drill.vein)
	vein.remaining = {1, 0, 0, 0}
	tick_with_engine_offer(&test, content, 1500, 200)
	drill = test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.state, Drill_State.Vein_Exhausted)
	testing.expect_value(t, chest_total(&test.world, test.chest), 1)
	// Less than a unit's worth does not revive it.
	mining_fluid := test_fluid(content, "mining_fluid")
	drill.buffers[REVIVAL_PORT] = {fluid = mining_fluid, level = REVIVAL_LITRES_PER_UNIT - 1}
	tick_with_engine_offer(&test, content, 1500, 200)
	drill = test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.state, Drill_State.Vein_Exhausted)
	drill.buffers[REVIVAL_PORT].level = 200
	// 96 ticks a unit on a full vein, 192 revived: five units in 960.
	tick_with_engine_offer(&test, content, 1500, 960)
	drill = test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.state, Drill_State.Revived)
	testing.expect_value(t, chest_total(&test.world, test.chest), 1 + 5)
	testing.expect_value(t, drill.buffers[REVIVAL_PORT].level, 200 - 5 * REVIVAL_LITRES_PER_UNIT)
	testing.expect_value(t, test.world.statistics.fluids.consumed[mining_fluid], 5 * REVIVAL_LITRES_PER_UNIT)
	vein = registered_vein(&test.world, drill.vein)
	testing.expect_value(t, vein_remaining_total(vein^), 0)
	testing.expect(t, vein.exhausted)
	testing.expect_value(t, vein.draws, 6)
	// Drained: exhausted again, and no power asked for.
	drill.buffers[REVIVAL_PORT].level = 5
	tick_with_engine_offer(&test, content, 1500, 10)
	drill = test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.state, Drill_State.Vein_Exhausted)
	testing.expect(t, !drill_wants_power(&test.world, drill^, test_crafting_machine(content, "electric_mining_drill"), TEST_TICK_RATE))
}

// With infinite veins nothing is exhausted, so the port is never used.
@(test)
test_vein_revival_ignored_on_infinite_veins :: proc(t: ^testing.T) {
	content := make_test_content()
	test := make_drill_power_test(content)
	test.world.settings.veins_infinite = true
	drill := test_drill(&test.world, test.drill)
	registered_vein(&test.world, drill.vein).remaining = {0, 0, 0, 0}
	drill.buffers[REVIVAL_PORT] = {fluid = test_fluid(content, "mining_fluid"), level = 200}
	tick_with_engine_offer(&test, content, 1500, 960)
	drill = test_drill(&test.world, test.drill)
	testing.expect_value(t, drill.state, Drill_State.Mining)
	testing.expect_value(t, chest_total(&test.world, test.chest), 10)
	testing.expect_value(t, drill.buffers[REVIVAL_PORT].level, 200)
}

// The revival port joins a pipe network like any machine port.
@(test)
test_revival_port_takes_mining_fluid_from_a_pipe :: proc(t: ^testing.T) {
	content := make_test_content()
	test := make_drill_power_test(content)
	// The port faces -x from the drill's cell (0, 1, 1).
	pipes := lay_pipes(&test.world, content, {-1, 1, 1})
	mining_fluid := test_fluid(content, "mining_fluid")
	test_pipe(&test.world, pipes[0]).buffer = {fluid = mining_fluid, level = 100}
	rebuild_fluid_networks(&test.world.entities, content.machines)
	tick_fluids(&test.world.entities, content, TEST_TICK_RATE)
	drill := test_drill(&test.world, test.drill)
	testing.expect(t, drill.buffers[REVIVAL_PORT].level > 0)
	testing.expect_value(t, drill.buffers[REVIVAL_PORT].fluid, mining_fluid)
	// Water is refused: the port is filtered to mining fluid.
	other := make_drill_power_test(content)
	water_pipes := lay_pipes(&other.world, content, {-1, 1, 1})
	test_pipe(&other.world, water_pipes[0]).buffer = {fluid = test_fluid(content, "water"), level = 100}
	rebuild_fluid_networks(&other.world.entities, content.machines)
	tick_fluids(&other.world.entities, content, TEST_TICK_RATE)
	testing.expect_value(t, test_drill(&other.world, other.drill).buffers[REVIVAL_PORT].level, 0)
}

@(test)
test_deep_ore_recipes :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	water := test_fluid(content, "water")
	// Washer: bauxite and 30 L of water to alumina and mud.
	washer_machine := test_crafting_machine(content, "washer")
	washer := make_test_crafting_machine(washer_machine)
	washer.slots[0] = {test_item(items, "bauxite"), 3}
	washer.buffers[0] = {fluid = water, level = 200}
	testing.expect_value(t, ticks_until_crafted(&washer, washer_machine, content, 1000), 120)
	testing.expect_value(t, washer.recipe, test_recipe(recipes, "alumina"))
	testing.expect_value(t, washer.slots[1], Item_Stack{test_item(items, "alumina"), 1})
	testing.expect_value(t, washer.buffers[0].level, 170)
	// Electrolyser: alumina to aluminium plate, quartz to silicon.
	electrolyser_machine := test_crafting_machine(content, "electrolyser")
	testing.expect_value(t, electrolyser_machine.recipe_maker, Recipe_Maker.Electrolysis)
	testing.expect_value(t, electrolyser_machine.electric_power_watts, 500_000)
	testing.expect_value(t, electrolyser_machine.footprint, [3]i32{3, 3, 3})
	Electrolysis_Case :: struct {
		input:   string,
		recipe:  string,
		product: string,
	}
	for entry in ([?]Electrolysis_Case{{"alumina", "aluminium_plate", "aluminium_plate"}, {"quartz", "silicon", "silicon"}}) {
		electrolyser := make_test_crafting_machine(electrolyser_machine)
		electrolyser.slots[0] = {test_item(items, entry.input), 4}
		testing.expect_value(t, ticks_until_crafted(&electrolyser, electrolyser_machine, content, 1000), 192)
		testing.expect_value(t, electrolyser.recipe, test_recipe(recipes, entry.recipe))
		testing.expect_value(t, electrolyser.slots[1], Item_Stack{test_item(items, entry.product), 1})
		testing.expect_value(t, electrolyser.slots[0].count, 2)
	}
	// Chemical plant: sulfur and 50 L of water to 50 L of mining fluid in
	// its output port.
	plant_machine := test_crafting_machine(content, "chemical_plant")
	plant := make_test_crafting_machine(plant_machine)
	plant.slots[0] = {test_item(items, "sulfur"), 2}
	plant.buffers[1] = {fluid = water, level = 200}
	testing.expect_value(t, ticks_until_crafted(&plant, plant_machine, content, 1000), 120)
	testing.expect_value(t, plant.recipe, test_recipe(recipes, "mining_fluid"))
	output := output_port_index(plant_machine, 0)
	testing.expect_value(t, plant.buffers[output], Fluid_Buffer{fluid = test_fluid(content, "mining_fluid"), level = 50})
	testing.expect_value(t, plant.buffers[1].level, 150)
	// Furnace: gold ore to gold plate with slag, quartz to glass.
	testing.expect_value(t, furnace_recipe_for(recipes, test_item(items, "gold_ore")), test_recipe(recipes, "gold_plate"))
	testing.expect_value(t, furnace_recipe_for(recipes, test_item(items, "quartz")), test_recipe(recipes, "quartz_glass"))
	world := make_drill_world(content)
	furnace := place_test_entity(&world, content, "stone_furnace", {0, 1, 0})
	slots := entity_slots(&world.entities, furnace)
	slots[FURNACE_FUEL_SLOT] = {test_item(items, "coal"), 5}
	slots[FURNACE_INPUT_SLOT] = {test_item(items, "gold_ore"), 1}
	tick_test_entities(&world, content, 200)
	slots = entity_slots(&world.entities, furnace)
	testing.expect_value(t, slots[FURNACE_OUTPUT_SLOT], Item_Stack{test_item(items, "gold_plate"), 1})
	testing.expect_value(t, slots[FURNACE_BYPRODUCT_SLOT], Item_Stack{test_item(items, "slag"), 1})
}

@(test)
test_deep_mining_technologies :: proc(t: ^testing.T) {
	content := make_test_content()
	technologies, recipes := content.technologies, content.recipes
	deep_mining := test_technology(technologies, "deep_mining")
	electrolysis := technologies.technologies[test_technology(technologies, "electrolysis")]
	testing.expect_value(t, electrolysis.pack_count, 150)
	testing.expect_value(t, len(electrolysis.science_packs), 2)
	testing.expect(t, slice.contains(electrolysis.prerequisites, deep_mining))
	testing.expect(t, !electrolysis.quest_gate)
	for id in ([?]string{"electrolyser", "alumina", "aluminium_plate", "silicon"}) {
		testing.expectf(t, slice.contains(electrolysis.unlocks, test_recipe(recipes, id)), "electrolysis does not unlock %s", id)
	}
}

// While a bore drill is placed, the HUD's vein line names the deep vein
// its ghost would tap, the same one the placement taps, or says there is
// none (0035).
@(test)
test_bore_drill_ghost_names_the_deep_vein :: proc(t: ^testing.T) {
	// No string table is loaded in tests, so text() records missing keys.
	defer clear_missing_reports(&global_string_table)
	content := make_test_content()
	world := make_deep_mining_world(content)
	vein := add_test_deep_vein(&world, content, "bauxite", {2, 2}, 2, {100, 20, 0, 0})
	players := []Player{make_test_player(content.blocks, {10, 1, 10})}
	player := &players[0]
	inventory_add(player.inventory, content.items, test_item(content.items, "bore_drill"), 1)
	// On the top face at (1, 0, 1): the 4 by 4 footprint starts at (0, 1, 0), centre column (2, 2).
	player.target = Raycast_Hit{hit = true, block = {1, 0, 1}, face = .Positive_Y, adjacent = {1, 1, 1}}
	placement := placement_for_player(&world, content, players, 0)
	ghost_vein, found, selected := bore_drill_ghost_vein(&world, content.machines, player^)
	testing.expect(t, selected && found && placement.valid)
	testing.expect_value(t, ghost_vein, vein)
	testing.expect_value(t, placement.vein, vein)
	line, shown := bore_drill_ghost_line(&world, content.machines, content.veins, content.blocks, content.items, nil, player^)
	testing.expect(t, shown)
	testing.expect_value(t, line, vein_status_text(&world, content.veins, content.blocks, content.items, nil, vein))
	testing.expect_value(t, line, fmt.tprintf("%s  120 %s", text("vein_type_bauxite"), text("drill_remaining")))
	player.target = Raycast_Hit{hit = true, block = {20, 0, 20}, face = .Positive_Y, adjacent = {20, 1, 20}}
	line, shown = bore_drill_ghost_line(&world, content.machines, content.veins, content.blocks, content.items, nil, player^)
	testing.expect(t, shown)
	testing.expect_value(t, line, text("bore_drill_no_deep_vein"))
	testing.expect(t, !placement_for_player(&world, content, players, 0).valid)
	// Any other selection leaves the line alone.
	player.selected_hotbar_slot = 1
	_, shown = bore_drill_ghost_line(&world, content.machines, content.veins, content.blocks, content.items, nil, player^)
	testing.expect(t, !shown)
}

// A revived vein is spent, so its draws keep the depleted end share of
// low grade ore (60 percent), not the full vein's (0035).
@(test)
test_revived_draws_keep_the_depleted_low_grade_share :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	world.settings.seed = 777
	id := add_test_vein(&world, content, "iron", {1, 1}, 2, {0, 0, 0, 0})
	hematite, low_grade := test_item(content.items, "hematite"), test_item(content.items, "hematite_low_grade")
	port := Fluid_Buffer{level = 1_000_000}
	high, low := 0, 0
	for _ in 0 ..< 4000 {
		switch draw_revived_unit(&world, content.veins, registered_vein(&world, id), &port) {
		case hematite:
			high += 1
		case low_grade:
			low += 1
		}
	}
	share := f64(low) * 100 / f64(high + low)
	testing.expectf(t, abs(share - 60) < 2.5, "revived vein: %.2f percent low grade", share)
	testing.expect_value(t, port.level, 1_000_000 - 4000 * REVIVAL_LITRES_PER_UNIT)
	testing.expect_value(t, vein_remaining_total(registered_vein(&world, id)^), 0)
}
