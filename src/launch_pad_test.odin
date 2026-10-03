package game

import "core:slice"
import "core:strings"
import "core:testing"

// Launch pad worlds stand on the stone floor of make_floor_world (top at
// y 1): the pad covers x 3 to 11 and z -8 to 0, powered by a steam engine
// whose steam is topped up every tick.

LAUNCH_PAD_TEST_ORIGIN :: World_Coordinate{3, 1, -8}

Launch_Pad_Test :: struct {
	content: Simulation_Content,
	world:   World,
	records: Game_Records,
	pad:     Entity_Handle,
	engine:  Entity_Handle,
}

make_launch_pad_test :: proc() -> Launch_Pad_Test {
	test := Launch_Pad_Test {
		content = make_test_content(),
	}
	test.world = make_drill_world(test.content)
	test.records = make_fluid_test_records(test.content)
	_, test.engine = add_test_power_plant(&test.world, test.content, {2, 1, 2}, {0, 1, 3})
	test.pad = place_test_entity(&test.world, test.content, "launch_pad", LAUNCH_PAD_TEST_ORIGIN)
	return test
}

test_launch_pad :: proc(test: ^Launch_Pad_Test) -> ^Launch_Pad {
	return pool_get(&test.world.entities.launch_pads, test.pad)
}

launch_pad_machine :: proc(test: ^Launch_Pad_Test) -> Machine {
	return test.content.machines.machines[test_launch_pad(test).machine]
}

// A whole rocket's parts and fuel, put in directly.
fill_launch_parts :: proc(test: ^Launch_Pad_Test) {
	items := test.content.items
	for id in ([?]string{"rocket_structure", "guidance_unit", "cargo_capsule"}) {
		entity_insert(&test.world.entities, test.content, test.pad, {test_item(items, id), 10})
	}
	test_launch_pad(test).buffers[LAUNCH_PAD_FUEL_PORT] = {fluid = test_fluid(test.content, "rocket_fuel"), level = 200}
}

tick_launch_pad_test :: proc(test: ^Launch_Pad_Test, ticks: int) {
	steam := test_fluid(test.content, "steam")
	for _ in 0 ..< ticks {
		for &buffer in test_fluid_machine(&test.world, test.engine).buffers[:2] {
			buffer = {fluid = steam, level = 200}
		}
		tick_entities_on_world(&test.world, &test.records, test.content, TEST_TICK_RATE)
	}
}

@(test)
test_launch_pad_data_loads :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	items := content.items
	pad := content.machines.machines[test_machine(content.machines, "launch_pad")]
	testing.expect_value(t, pad.kind, Machine_Kind.Launch_Pad)
	testing.expect_value(t, pad.footprint, [3]i32{9, 2, 9})
	testing.expect_value(t, pad.electric_power_watts, 200_000)
	testing.expect_value(t, pad.slot_count, LAUNCH_PAD_CARGO_SLOTS)
	testing.expect_value(t, pad.launch_part_count, 3)
	testing.expect_value(t, pad.launch_parts[0], Item_Stack{test_item(items, "rocket_structure"), 10})
	testing.expect_value(t, pad.launch_parts[1], Item_Stack{test_item(items, "guidance_unit"), 2})
	testing.expect_value(t, pad.launch_parts[2], Item_Stack{test_item(items, "cargo_capsule"), 1})
	testing.expect_value(t, pad.launch_fuel_litres, 200)
	testing.expect_value(t, pad.fluid_ports[LAUNCH_PAD_FUEL_PORT].filter, test_fluid(content, "rocket_fuel"))
	testing.expect_value(t, pad.fluid_ports[LAUNCH_PAD_FUEL_PORT].capacity, 400)
	testing.expect_value(t, assembly_ticks(pad, TEST_TICK_RATE), 3600)
	testing.expect_value(t, pad.launch_seconds, 5)
	fuel := content.recipes.recipes[test_recipe(content.recipes, "rocket_fuel")]
	testing.expect_value(t, fuel.fluid_inputs[0], Recipe_Fluid{fluid = test_fluid(content, "light_oil"), litres = 30})
	testing.expect_value(t, fuel.fluid_outputs[0].fluid, test_fluid(content, "rocket_fuel"))
	testing.expect_value(t, fuel.inputs[0], Item_Stack{test_item(items, "sulfur"), 1})
	wood := content.recipes.recipes[test_recipe(content.recipes, "wood_gas_rocket_fuel")]
	testing.expect_value(t, wood.channel, Recipe_Channel.Schematic)
	testing.expect_value(t, wood.fluid_inputs[0].litres, 60)
	// A part listed twice, and parts on another kind, are refused.
	machine := Machine{id = "pad", kind = .Launch_Pad}
	twice := Machine_Definition{id = "pad", launch_parts = []Launch_Part_Definition{{item = "steel", count = 1}, {item = "steel", count = 2}}}
	testing.expect(t, resolve_launch_parts(&machine, twice, items) != "")
	chest := Machine{id = "chest", kind = .Chest}
	testing.expect(t, resolve_launch_parts(&chest, twice, items) != "")
}

// Parts go only to their slots and up to what a rocket takes, anything
// else to the cargo, and inserters never take anything out.
@(test)
test_launch_pad_slot_rules :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_launch_pad_test()
	entities, content := &test.world.entities, test.content
	structure := test_item(content.items, "rocket_structure")
	guidance := test_item(content.items, "guidance_unit")
	capsule := test_item(content.items, "cargo_capsule")
	plate := test_item(content.items, "iron_plate")
	slot, ok := entity_accepts(entities, content, test.pad, structure)
	testing.expect(t, ok && slot == 0)
	slot, ok = entity_accepts(entities, content, test.pad, plate)
	testing.expect(t, ok && slot == 3)
	testing.expect_value(t, entity_insert(entities, content, test.pad, {guidance, 5}), Item_Stack{guidance, 3})
	testing.expect_value(t, entity_insert(entities, content, test.pad, {capsule, 2}), Item_Stack{capsule, 1})
	testing.expect_value(t, entity_insert(entities, content, test.pad, {structure, 10}), EMPTY_STACK)
	// Full part slots take no more, and parts never go to the cargo.
	_, ok = entity_accepts(entities, content, test.pad, guidance)
	testing.expect(t, !ok)
	testing.expect(t, entity_takes_item_kind(entities, content, test.pad, guidance))
	testing.expect(t, entity_takes_item_kind(entities, content, test.pad, plate))
	pad := test_launch_pad(&test)
	testing.expect_value(t, pad.slots[1], Item_Stack{guidance, 2})
	testing.expect_value(t, pad.slots[2], Item_Stack{capsule, 1})
	testing.expect(t, cargo_is_empty(pad))
	for _ in 0 ..< LAUNCH_PAD_CARGO_SLOTS {
		entity_insert(entities, content, test.pad, {plate, 50})
	}
	_, ok = entity_accepts(entities, content, test.pad, plate)
	testing.expect(t, !ok)
	testing.expect_value(t, entity_extract(entities, content, test.pad, NO_ITEM, 10), EMPTY_STACK)
	testing.expect_value(t, len(entity_offered_items(entities, test.pad, NO_ITEM)), 0)
	// The player's panel: parts to their slot, cargo anything.
	filters := launch_pad_slot_filters(pad^, launch_pad_machine(&test))
	testing.expect_value(t, len(filters), 3 + LAUNCH_PAD_CARGO_SLOTS)
	testing.expect_value(t, filters[1], Slot_Filter{kind = .Item, item = guidance})
	testing.expect_value(t, filters[4].kind, Slot_Filter_Kind.Any)
}

// Assemble takes 60 seconds at full power and a tenth of the parts and
// fuel at the start of each tenth.
@(test)
test_launch_pad_assembly_timing :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_launch_pad_test()
	pad := test_launch_pad(&test)
	machine := launch_pad_machine(&test)
	testing.expect(t, entity_network(&test.world.entities.electric_networks, test.pad) >= 0)
	testing.expect(t, !start_assembly(pad, machine))
	fill_launch_parts(&test)
	tick_launch_pad_test(&test, 1)
	testing.expect_value(t, pad.state, Launch_Pad_State.Ready_To_Assemble)
	testing.expect(t, start_assembly(pad, machine))
	tick_launch_pad_test(&test, 1)
	testing.expect_value(t, pad.slots[0].count, 9)
	testing.expect_value(t, pad.slots[1].count, 2)
	testing.expect_value(t, pad.buffers[LAUNCH_PAD_FUEL_PORT].level, 180)
	tick_launch_pad_test(&test, 1799)
	testing.expect_value(t, pad.work_ticks, 1800)
	testing.expect_value(t, pad.slots[0].count, 5)
	testing.expect_value(t, pad.slots[1].count, 1)
	testing.expect_value(t, pad.slots[2].count, 1)
	testing.expect_value(t, pad.buffers[LAUNCH_PAD_FUEL_PORT].level, 100)
	tick_launch_pad_test(&test, 1799)
	testing.expect_value(t, pad.state, Launch_Pad_State.Assembling)
	tick_launch_pad_test(&test, 1)
	testing.expect_value(t, pad.state, Launch_Pad_State.Rocket_Ready)
	for slot in pad.slots[:pad.part_count] {
		testing.expect(t, stack_is_empty(slot))
	}
	testing.expect_value(t, pad.buffers[LAUNCH_PAD_FUEL_PORT], Fluid_Buffer{fluid = NO_FLUID})
	statistics := test.records.statistics
	testing.expect_value(t, statistics.consumed[test_item(test.content.items, "rocket_structure")], 10)
	testing.expect_value(t, statistics.consumed[test_item(test.content.items, "cargo_capsule")], 1)
	testing.expect_value(t, statistics.fluids.consumed[test_fluid(test.content, "rocket_fuel")], 200)
	// A ready rocket asks for no power and waits.
	testing.expect(t, !launch_pad_wants_power(pad^, machine, TEST_TICK_RATE))
	tick_launch_pad_test(&test, 100)
	testing.expect_value(t, pad.state, Launch_Pad_State.Rocket_Ready)
}

// Parts taken out during the assembly pause it where the next share is
// missing, without power; put back, it goes on. Picking the pad up gives
// back the parts built in.
@(test)
test_launch_pad_assembly_waits_for_missing_parts :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_launch_pad_test()
	pad := test_launch_pad(&test)
	machine := launch_pad_machine(&test)
	fill_launch_parts(&test)
	testing.expect(t, start_assembly(pad, machine))
	tick_launch_pad_test(&test, 1)
	pad.slots[0] = EMPTY_STACK
	tick_launch_pad_test(&test, 500)
	testing.expect_value(t, pad.work_ticks, 360)
	testing.expect(t, pad.missing_parts)
	testing.expect(t, !launch_pad_wants_power(pad^, machine, TEST_TICK_RATE))
	testing.expect_value(t, launch_pad_held_stacks(pad^, machine)[0], Item_Stack{test_item(test.content.items, "rocket_structure"), 1})
	entity_insert(&test.world.entities, test.content, test.pad, {test_item(test.content.items, "rocket_structure"), 9})
	tick_launch_pad_test(&test, 1)
	testing.expect(t, !pad.missing_parts)
	testing.expect_value(t, pad.work_ticks, 361)
	testing.expect_value(t, pad.slots[0].count, 8)
}

// Launching needs cargo, takes it and the rocket, records the shipment
// and the statistics, and the ascent lasts five seconds.
@(test)
test_launch_consumes_rocket_and_cargo :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_launch_pad_test()
	pad := test_launch_pad(&test)
	items := test.content.items
	plate, steel := test_item(items, "iron_plate"), test_item(items, "steel")
	testing.expect(t, !launch_rocket(&test.records, pad, 10))
	pad.state = .Rocket_Ready
	testing.expect(t, !launch_rocket(&test.records, pad, 10))
	entity_insert(&test.world.entities, test.content, test.pad, {plate, 50})
	entity_insert(&test.world.entities, test.content, test.pad, {steel, 20})
	entity_insert(&test.world.entities, test.content, test.pad, {plate, 30})
	testing.expect(t, launch_rocket(&test.records, pad, 1234))
	testing.expect_value(t, pad.state, Launch_Pad_State.Launching)
	testing.expect(t, cargo_is_empty(pad))
	testing.expect_value(t, len(test.records.shipments), 1)
	shipment := test.records.shipments[0]
	testing.expect_value(t, shipment.tick, 1234)
	testing.expect_value(t, shipment.cargo_count, 2)
	testing.expect_value(t, shipment.cargo[0], Shipped_Item{plate, 80})
	testing.expect_value(t, shipment.cargo[1], Shipped_Item{steel, 20})
	statistics := test.records.statistics
	testing.expect_value(t, statistics.rockets_launched, 1)
	testing.expect_value(t, statistics.shipped[plate], 80)
	testing.expect_value(t, statistics.shipped[steel], 20)
	// Shipped cargo counts as consumed (work item 0041).
	testing.expect_value(t, statistics.consumed[plate], 80)
	testing.expect_value(t, statistics.consumed[steel], 20)
	testing.expect_value(t, shipment.pad_centre, LAUNCH_PAD_TEST_ORIGIN + {4, 0, 4})
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Rockets_Launched}), 1)
	tick_launch_pad_test(&test, 5 * TEST_TICK_RATE - 1)
	testing.expect_value(t, pad.state, Launch_Pad_State.Launching)
	tick_launch_pad_test(&test, 1)
	testing.expect_value(t, pad.state, Launch_Pad_State.Waiting_For_Parts)
}

// Interact on a ready pad with cargo requests the launch, served after
// the entity tick with the tick; on a pad that cannot launch it does
// nothing, and Open_Aimed opens the panel (0194).
@(test)
test_interact_launches_a_ready_rocket :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_launch_pad_test()
	pad := test_launch_pad(&test)
	player := make_test_player(test.content.blocks, {1, 1, -10})
	player.target = Raycast_Hit{hit = true, entity = test.pad}
	_, events := resolve_interact(&player, &test.world.entities, test.content.machines, press({.Interact}))
	testing.expect_value(t, events, Player_Events{})
	pad.state = .Rocket_Ready
	entity_insert(&test.world.entities, test.content, test.pad, {test_item(test.content.items, "iron_plate"), 5})
	_, events = resolve_interact(&player, &test.world.entities, test.content.machines, press({.Open_Aimed}))
	testing.expect_value(t, events, Player_Events{.Open_Machine})
	testing.expect(t, !pad.launch_requested)
	_, events = resolve_interact(&player, &test.world.entities, test.content.machines, press({.Interact}))
	testing.expect_value(t, events, Player_Events{.Launch_Requested})
	testing.expect(t, pad.launch_requested)
	apply_launch_requests(&test.world, &test.records, 99)
	testing.expect(t, !pad.launch_requested)
	testing.expect_value(t, pad.state, Launch_Pad_State.Launching)
	testing.expect_value(t, test.records.shipments[0].tick, 99)
}

@(test)
test_shipment_statistics_rows :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	shipped := []u64{0, 5, 0, 80, 5}
	totals := shipped_totals(shipped)
	testing.expect(t, slice.equal(totals, []Shipped_Total{{3, 80}, {1, 5}, {4, 5}}))
	shipment := make_shipment([]Item_Stack{{2, 10}, EMPTY_STACK, {3, 4}, {2, 1}}, 20 * TEST_TICK_RATE)
	testing.expect_value(t, shipment.cargo_count, 2)
	testing.expect_value(t, shipment.cargo[0], Shipped_Item{2, 11})
	testing.expect(t, strings.has_prefix(shipment_line(shipment, {}, TEST_TICK_RATE), "0:20  "))
}

// rocket_program's recipes wait for the quest reward, rocketry for
// rocket_program, and the wood gas fuel for its schematic.
@(test)
test_rocket_technology_gating :: proc(t: ^testing.T) {
	test := make_crafting_test()
	technologies, recipes := test.technologies, test.recipes
	rocket_program := test_technology(technologies, "rocket_program")
	rocketry := test_technology(technologies, "rocketry")
	program_recipes := [?]string{"launch_pad", "rocket_structure", "guidance_unit"}
	rocketry_recipes := [?]string{"rocket_fuel", "cargo_capsule"}
	for id in program_recipes {
		testing.expectf(t, !recipe_is_available(test.unlocks, test_recipe(recipes, id)), "%s", id)
	}
	for id in ([?]string{"automation", "logistics", "steel_processing", "ore_processing", "oil_processing", "plastics", "logistics_science", "deep_mining", "electrolysis"}) {
		mark_technology_researched(&test.unlocks, recipes, test_technology(technologies, id))
	}
	research: Research_State
	testing.expect(t, queue_research(&research, technologies, test.unlocks, rocket_program) != .None)
	testing.expect(t, queue_research(&research, technologies, test.unlocks, rocketry) != .None)
	mark_technology_researched(&test.unlocks, recipes, rocket_program)
	for id in program_recipes {
		testing.expectf(t, recipe_is_available(test.unlocks, test_recipe(recipes, id)), "%s", id)
	}
	for id in rocketry_recipes {
		testing.expectf(t, !recipe_is_available(test.unlocks, test_recipe(recipes, id)), "%s", id)
	}
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, rocketry), Research_Refusal.None)
	testing.expect_value(t, technologies.technologies[rocketry].pack_count, 200)
	mark_technology_researched(&test.unlocks, recipes, rocketry)
	for id in rocketry_recipes {
		testing.expectf(t, recipe_is_available(test.unlocks, test_recipe(recipes, id)), "%s", id)
	}
	testing.expect(t, !recipe_is_available(test.unlocks, test_recipe(recipes, "wood_gas_rocket_fuel")))
}

// A burner inserter feeds the pad from a chest; assembly starts as soon
// as the parts are in. Two runs over 1200 ticks end in the same state.
lay_inserter_fed_pad :: proc(test: ^Launch_Pad_Test) -> (chest: Entity_Handle) {
	items := test.content.items
	chest = place_test_entity(&test.world, test.content, "wooden_chest", {1, 1, -4})
	place_fuelled_inserter(&test.world, test.content, {2, 1, -4}, 0)
	entity_insert(&test.world.entities, test.content, test.pad, {test_item(items, "rocket_structure"), 7})
	for stack in ([?]Item_Stack{{test_item(items, "rocket_structure"), 3}, {test_item(items, "guidance_unit"), 2}, {test_item(items, "cargo_capsule"), 1}, {test_item(items, "iron_plate"), 2}}) {
		entity_insert(&test.world.entities, test.content, chest, stack)
	}
	test_launch_pad(test).buffers[LAUNCH_PAD_FUEL_PORT] = {fluid = test_fluid(test.content, "rocket_fuel"), level = 400}
	return
}

@(test)
test_inserter_fed_pad_is_deterministic :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	tests := [2]Launch_Pad_Test{make_launch_pad_test(), make_launch_pad_test()}
	for &test in tests {
		lay_inserter_fed_pad(&test)
		for _ in 0 ..< 1200 {
			pad := test_launch_pad(&test)
			if pad.state == .Ready_To_Assemble {
				start_assembly(pad, launch_pad_machine(&test))
			}
			tick_launch_pad_test(&test, 1)
		}
	}
	first, second := test_launch_pad(&tests[0]), test_launch_pad(&tests[1])
	testing.expect_value(t, first^, second^)
	testing.expect_value(t, first.state, Launch_Pad_State.Assembling)
	testing.expect(t, first.work_ticks > 0)
	testing.expect_value(t, first.slots[first.part_count], Item_Stack{test_item(tests[0].content.items, "iron_plate"), 2})
}
