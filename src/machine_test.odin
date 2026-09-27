package game

import "core:testing"

make_test_machines :: proc() -> Machine_Registry {
	file, error := parse_machines_file(#load("../data/machines.sjson"), context.temp_allocator)
	assert(error == nil)
	registry, problem := resolve_machine_registry(file, make_test_items(), context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_test_content :: proc() -> Simulation_Content {
	return Simulation_Content{blocks = make_test_registry(), items = make_test_items(), machines = make_test_machines()}
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
	testing.expect_value(t, len(machines.machines), 3)
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
	testing.expect_value(t, len(machines.smelting), len(HARDCODED_SMELTING_TABLE))
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
}

resolve_test_machines :: proc(definitions: []Machine_Definition) -> string {
	registry, problem := resolve_machine_registry(Machines_File{machines = definitions}, make_test_items(), context.temp_allocator)
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
}
