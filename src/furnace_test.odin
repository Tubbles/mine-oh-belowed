package game

import "core:testing"

Furnace_Test :: struct {
	items:    Item_Registry,
	machines: Machine_Registry,
	recipes:  Recipe_Registry,
	machine:  Machine,
	furnace:  Furnace,
}

make_furnace_test :: proc() -> Furnace_Test {
	machines := make_test_machines()
	machine := test_machine(machines, "stone_furnace")
	items := make_test_items()
	recipes, _ := make_test_recipes(items)
	return Furnace_Test {
		items = items,
		machines = machines,
		recipes = recipes,
		machine = machines.machines[machine],
		furnace = make_furnace(Entity_Common{machine = machine}),
	}
}

run_furnace :: proc(test: ^Furnace_Test, ticks: int) {
	for _ in 0 ..< ticks {
		test.furnace = advance_furnace(test.furnace, test.machine, test.items, test.recipes, TEST_TICK_RATE)
	}
}

@(test)
test_furnace_smelts_and_burns_fuel_per_tick :: proc(t: ^testing.T) {
	test := make_furnace_test()
	coal := test_item(test.items, "coal")
	plate := test_item(test.items, "iron_plate")
	test.furnace.slots[FURNACE_FUEL_SLOT] = Item_Stack{coal, 2}
	test.furnace.slots[FURNACE_INPUT_SLOT] = Item_Stack{test_item(test.items, "hematite"), 3}
	// 90 kW at 60 ticks per second is 1500 J per tick; 3.2 s is 192 ticks.
	testing.expect_value(t, fuel_joules_per_tick(test.machine, TEST_TICK_RATE), 1500)
	testing.expect_value(t, recipe_ticks(test.recipes.recipes[test_recipe(test.recipes, "iron_plate")], 100, TEST_TICK_RATE), 192)
	run_furnace(&test, 1)
	testing.expect_value(t, test.furnace.state, Furnace_State.Burning)
	testing.expect_value(t, test.furnace.slots[FURNACE_FUEL_SLOT].count, 1)
	testing.expect_value(t, test.furnace.fuel_joules, 4_000_000 - 1500)
	testing.expect_value(t, test.furnace.progress_ticks, 1)
	run_furnace(&test, 190)
	testing.expect_value(t, test.furnace.slots[FURNACE_OUTPUT_SLOT], EMPTY_STACK)
	testing.expect_value(t, test.furnace.progress_ticks, 191)
	run_furnace(&test, 1)
	testing.expect_value(t, test.furnace.slots[FURNACE_OUTPUT_SLOT], Item_Stack{plate, 1})
	testing.expect_value(t, test.furnace.slots[FURNACE_INPUT_SLOT].count, 2)
	testing.expect_value(t, test.furnace.progress_ticks, 0)
	testing.expect_value(t, test.furnace.fuel_joules, 4_000_000 - 192 * 1500)
	// The output stacks; with the input used up the furnace idles and stops burning.
	run_furnace(&test, 2 * 192)
	testing.expect_value(t, test.furnace.slots[FURNACE_OUTPUT_SLOT], Item_Stack{plate, 3})
	testing.expect_value(t, test.furnace.slots[FURNACE_INPUT_SLOT], EMPTY_STACK)
	fuel_left := test.furnace.fuel_joules
	run_furnace(&test, 100)
	testing.expect_value(t, test.furnace.state, Furnace_State.Idle)
	testing.expect_value(t, test.furnace.fuel_joules, fuel_left)
	testing.expect_value(t, test.furnace.slots[FURNACE_FUEL_SLOT].count, 1)
}

@(test)
test_furnace_idle_burns_nothing :: proc(t: ^testing.T) {
	test := make_furnace_test()
	test.furnace.slots[FURNACE_FUEL_SLOT] = Item_Stack{test_item(test.items, "coal"), 5}
	run_furnace(&test, 60)
	testing.expect_value(t, test.furnace.state, Furnace_State.Idle)
	testing.expect_value(t, test.furnace.slots[FURNACE_FUEL_SLOT].count, 5)
	testing.expect_value(t, test.furnace.fuel_joules, 0)
	// One stone is not enough for a 2 to 1 recipe.
	test.furnace.slots[FURNACE_INPUT_SLOT] = Item_Stack{test_item(test.items, "stone"), 1}
	run_furnace(&test, 60)
	testing.expect_value(t, test.furnace.state, Furnace_State.Idle)
	testing.expect_value(t, test.furnace.slots[FURNACE_FUEL_SLOT].count, 5)
}

@(test)
test_furnace_needs_fuel :: proc(t: ^testing.T) {
	test := make_furnace_test()
	test.furnace.slots[FURNACE_INPUT_SLOT] = Item_Stack{test_item(test.items, "sand"), 4}
	run_furnace(&test, 10)
	testing.expect_value(t, test.furnace.state, Furnace_State.No_Fuel)
	testing.expect_value(t, test.furnace.progress_ticks, 0)
	// A stick is 500 kJ: 333 ticks of burning at 1500 J, then it runs dry.
	test.furnace.slots[FURNACE_FUEL_SLOT] = Item_Stack{test_item(test.items, "stick"), 1}
	run_furnace(&test, 333)
	testing.expect_value(t, test.furnace.state, Furnace_State.Burning)
	testing.expect_value(t, test.furnace.slots[FURNACE_OUTPUT_SLOT], Item_Stack{test_item(test.items, "glass"), 1})
	testing.expect_value(t, test.furnace.slots[FURNACE_INPUT_SLOT].count, 2)
	testing.expect_value(t, test.furnace.fuel_joules, 500)
	run_furnace(&test, 1)
	testing.expect_value(t, test.furnace.state, Furnace_State.No_Fuel)
	testing.expect_value(t, test.furnace.progress_ticks, 333 - 192)
}

@(test)
test_furnace_stalls_on_a_full_output :: proc(t: ^testing.T) {
	test := make_furnace_test()
	plate := test_item(test.items, "iron_plate")
	test.furnace.slots[FURNACE_FUEL_SLOT] = Item_Stack{test_item(test.items, "coal"), 1}
	test.furnace.slots[FURNACE_INPUT_SLOT] = Item_Stack{test_item(test.items, "hematite"), 5}
	test.furnace.slots[FURNACE_OUTPUT_SLOT] = Item_Stack{plate, 49}
	run_furnace(&test, 192)
	testing.expect_value(t, test.furnace.slots[FURNACE_OUTPUT_SLOT], Item_Stack{plate, 50})
	fuel_left := test.furnace.fuel_joules
	run_furnace(&test, 50)
	testing.expect_value(t, test.furnace.state, Furnace_State.Output_Full)
	testing.expect_value(t, test.furnace.slots[FURNACE_INPUT_SLOT].count, 4)
	testing.expect_value(t, test.furnace.fuel_joules, fuel_left)
	// Another item in the output blocks too.
	test.furnace.slots[FURNACE_OUTPUT_SLOT] = Item_Stack{test_item(test.items, "glass"), 1}
	run_furnace(&test, 1)
	testing.expect_value(t, test.furnace.state, Furnace_State.Output_Full)
	// Emptied, it resumes.
	test.furnace.slots[FURNACE_OUTPUT_SLOT] = EMPTY_STACK
	run_furnace(&test, 1)
	testing.expect_value(t, test.furnace.state, Furnace_State.Burning)
}

@(test)
test_furnaces_tick_in_the_simulation :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "stone_furnace"), {4, 1, 4}, 0)
	furnace := pool_get(&world.entities.furnaces, handle)
	furnace.slots[FURNACE_FUEL_SLOT] = Item_Stack{test_item(content.items, "log"), 1}
	furnace.slots[FURNACE_INPUT_SLOT] = Item_Stack{test_item(content.items, "log"), 4}
	for _ in 0 ..< 2 * 192 {
		tick_entities(&world, &records, content, TEST_TICK_RATE)
	}
	furnace = pool_get(&world.entities.furnaces, handle)
	testing.expect_value(t, furnace.slots[FURNACE_OUTPUT_SLOT], Item_Stack{test_item(content.items, "charcoal"), 2})
	testing.expect_value(t, furnace.slots[FURNACE_INPUT_SLOT], EMPTY_STACK)
}
