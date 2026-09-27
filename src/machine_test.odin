package game

import "core:testing"

make_test_machines :: proc() -> Machine_Registry {
	file, error := parse_machines_file(#load("../data/machines.sjson"), context.temp_allocator)
	assert(error == nil)
	registry, problem := resolve_machine_registry(file, make_test_items(), make_test_fluids(), context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_test_fluids :: proc() -> Fluid_Registry {
	file, error := parse_fluids_file(#load("../data/fluids.sjson"), context.temp_allocator)
	assert(error == nil)
	registry, problem := resolve_fluid_registry(file, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_test_content :: proc() -> Simulation_Content {
	items := make_test_items()
	recipes, _ := make_test_recipes(items)
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	veins, problem := resolve_vein_content(generator.veins, items, context.temp_allocator)
	assert(problem == "", problem)
	return Simulation_Content{blocks = make_test_registry(), items = items, machines = make_test_machines(), fluids = make_test_fluids(), recipes = recipes, veins = veins}
}

test_machine :: proc(machines: Machine_Registry, id: string) -> Machine_Id {
	for machine, index in machines.machines {
		if machine.id == id {
			return Machine_Id(index)
		}
	}
	panic(id)
}

@(test)
test_machine_data_loads :: proc(t: ^testing.T) {
	items := make_test_items()
	machines := make_test_machines()
	testing.expect_value(t, len(machines.machines), 22)
	wooden := machines.machines[test_machine(machines, "wooden_chest")]
	testing.expect_value(t, wooden.kind, Machine_Kind.Chest)
	testing.expect_value(t, wooden.slot_count, 16)
	testing.expect_value(t, wooden.footprint, [3]i32{1, 1, 1})
	testing.expect_value(t, machines.machines[test_machine(machines, "iron_chest")].slot_count, 32)
	furnace := machines.machines[test_machine(machines, "stone_furnace")]
	testing.expect_value(t, furnace.kind, Machine_Kind.Furnace)
	testing.expect_value(t, furnace.footprint, [3]i32{2, 2, 2})
	testing.expect_value(t, furnace.speed_percent, 100)
	testing.expect_value(t, furnace.fuel_power_watts, 90_000)
	testing.expect_value(t, furnace.item, test_item(items, "stone_furnace"))
	testing.expect_value(t, item_places_machine(machines, test_item(items, "stone_furnace")), test_machine(machines, "stone_furnace"))
	testing.expect_value(t, item_places_machine(machines, test_item(items, "stone")), NO_MACHINE)
	testing.expect_value(t, item_places_machine(machines, NO_ITEM), NO_MACHINE)
	burner := machines.machines[test_machine(machines, "burner_inserter")]
	testing.expect_value(t, burner.kind, Machine_Kind.Inserter)
	testing.expect_value(t, burner.slot_count, 1)
	testing.expect_value(t, burner.items_per_minute, 36)
	testing.expect_value(t, burner.fuel_power_watts, 94_000)
	electric := machines.machines[test_machine(machines, "inserter")]
	testing.expect_value(t, electric.slot_count, 0)
	testing.expect_value(t, electric.electric_power_watts, 13_000)
	testing.expect_value(t, electric.filter_slot_count, 0)
	testing.expect_value(t, machines.machines[test_machine(machines, "filter_inserter")].filter_slot_count, 1)
	drill := machines.machines[test_machine(machines, "burner_mining_drill")]
	testing.expect_value(t, drill.kind, Machine_Kind.Drill)
	testing.expect_value(t, drill.footprint, [3]i32{2, 2, 2})
	testing.expect_value(t, drill.slot_count, 1)
	testing.expect_value(t, drill.items_per_minute, 15)
	testing.expect_value(t, drill.rate_reference_ore_percent, 80)
	testing.expect_value(t, drill.fuel_power_watts, 150_000)
	testing.expect_value(t, drill.item, test_item(items, "burner_mining_drill"))
	splitter := machines.machines[test_machine(machines, "splitter")]
	testing.expect_value(t, splitter.kind, Machine_Kind.Splitter)
	testing.expect_value(t, splitter.footprint, [3]i32{1, 1, 2})
	testing.expect_value(t, splitter.belt_speed_units_per_second, 480)
	testing.expect_value(t, splitter.item, test_item(items, "splitter"))
}

@(test)
test_machine_strings_exist :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect(t, error == nil)
	for machine in make_test_machines().machines {
		testing.expectf(t, machine.name_key in table.entries, "missing string %q", machine.name_key)
	}
	for key in furnace_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in inserter_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in drill_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for vein_type in make_test_content().veins.types {
		testing.expectf(t, vein_type.name_key in table.entries, "missing string %q", vein_type.name_key)
	}
	for key in ([?]string{"inserter_filter", "hint_set_filter", "hint_clear_filter", "drill_remaining", "drill_infinite", "drill_rate"}) {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in ([?]string{"splitter_input_priority", "splitter_output_priority", "splitter_filter_side"}) {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in splitter_priority_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in splitter_side_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in fluid_machine_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for fluid in make_test_fluids().fluids {
		testing.expectf(t, fluid.name_key in table.entries, "missing string %q", fluid.name_key)
	}
	for key in ([?]string{"fluid_none", "fluid_of", "fluid_flow_in", "fluid_flow_out", "fluid_mixing_refused"}) {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
}

resolve_test_machines :: proc(definitions: []Machine_Definition) -> string {
	registry, problem := resolve_machine_registry(Machines_File{machines = definitions}, make_test_items(), make_test_fluids(), context.temp_allocator)
	if problem == "" {
		destroy_machine_registry(registry, context.temp_allocator)
	}
	return problem
}

@(test)
test_machine_data_rejects_bad_definitions :: proc(t: ^testing.T) {
	chest := Machine_Definition {
		id = "chest",
		name_key = "machine_wooden_chest",
		item = "wooden_chest",
		kind = "chest",
		footprint = {1, 1, 1},
		slots = 16,
	}
	testing.expect_value(t, resolve_test_machines({chest}), "")
	unknown_item := chest
	unknown_item.item = "no_such_item"
	testing.expect(t, resolve_test_machines({unknown_item}) != "")
	block_item := chest
	block_item.item = "stone"
	testing.expect(t, resolve_test_machines({block_item}) != "")
	second := chest
	second.id = "second"
	testing.expect(t, resolve_test_machines({chest, second}) != "")
	no_slots := chest
	no_slots.slots = 0
	testing.expect(t, resolve_test_machines({no_slots}) != "")
	flat := chest
	flat.footprint.height = 0
	testing.expect(t, resolve_test_machines({flat}) != "")
	unknown_kind := chest
	unknown_kind.kind = "assembler"
	testing.expect(t, resolve_test_machines({unknown_kind}) != "")
	furnace := Machine_Definition {
		id = "furnace",
		name_key = "machine_stone_furnace",
		item = "stone_furnace",
		kind = "furnace",
		footprint = {2, 2, 2},
		fuel_slots = 1,
		input_slots = 1,
		output_slots = 1,
		speed = 1,
		fuel_power_kilowatts = 90,
	}
	testing.expect_value(t, resolve_test_machines({furnace}), "")
	unpowered := furnace
	unpowered.fuel_power_kilowatts = 0
	testing.expect(t, resolve_test_machines({unpowered}) != "")
	two_inputs := furnace
	two_inputs.input_slots = 2
	testing.expect(t, resolve_test_machines({two_inputs}) != "")
	inserter := Machine_Definition {
		id = "inserter",
		name_key = "machine_burner_inserter",
		item = "burner_inserter",
		kind = "inserter",
		footprint = {1, 1, 1},
		items_per_minute = 36,
		fuel_slots = 1,
		fuel_power_kilowatts = 94,
	}
	testing.expect_value(t, resolve_test_machines({inserter}), "")
	no_rate := inserter
	no_rate.items_per_minute = 0
	testing.expect(t, resolve_test_machines({no_rate}) != "")
	no_power := inserter
	no_power.fuel_slots = 0
	testing.expect(t, resolve_test_machines({no_power}) != "")
	wide := inserter
	wide.footprint.width = 2
	testing.expect(t, resolve_test_machines({wide}) != "")
	two_filters := inserter
	two_filters.filter_slots = 2
	testing.expect(t, resolve_test_machines({two_filters}) != "")
}
