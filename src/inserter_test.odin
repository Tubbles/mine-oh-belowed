package game

import "core:testing"

// Inserter worlds stand on the stone floor of make_floor_world (top at y 1).

place_test_entity :: proc(world: ^World, content: Simulation_Content, machine: string, cell: World_Coordinate, rotation: u8 = 0) -> Entity_Handle {
	return add_entity(&world.entities, content.machines, test_machine(content.machines, machine), cell, rotation)
}

// A burner inserter with a coal in its fuel slot.
place_fuelled_inserter :: proc(world: ^World, content: Simulation_Content, cell: World_Coordinate, direction: u8) -> Entity_Handle {
	handle := place_test_entity(world, content, "burner_inserter", cell, direction)
	pool_get(&world.entities.inserters, handle).slots[INSERTER_FUEL_SLOT] = Item_Stack{test_item(content.items, "coal"), 5}
	return handle
}

test_inserter :: proc(world: ^World, handle: Entity_Handle) -> ^Inserter {
	return pool_get(&world.entities.inserters, handle)
}

tick_test_entities :: proc(world: ^World, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		tick_entities(world, content, TEST_TICK_RATE)
	}
}

slots_count_of :: proc(slots: []Item_Stack, item: Item_Id) -> int {
	total := 0
	for slot in slots {
		if !stack_is_empty(slot) && slot.item == item {
			total += int(slot.count)
		}
	}
	return total
}

chest_count_of :: proc(world: ^World, chest: Entity_Handle, item: Item_Id) -> int {
	return slots_count_of(entity_slots(&world.entities, chest), item)
}

// Chest at x 0, inserter at x 1 facing +x, chest at x 2.
Chest_Pair :: struct {
	source:   Entity_Handle,
	inserter: Entity_Handle,
	target:   Entity_Handle,
}

make_chest_pair :: proc(world: ^World, content: Simulation_Content, inserter_machine := "burner_inserter") -> Chest_Pair {
	pair := Chest_Pair {
		source   = place_test_entity(world, content, "wooden_chest", {0, 1, 0}),
		inserter = place_test_entity(world, content, inserter_machine, {1, 1, 0}, 0),
		target   = place_test_entity(world, content, "wooden_chest", {2, 1, 0}),
	}
	test_inserter(world, pair.inserter).slots[INSERTER_FUEL_SLOT] = Item_Stack{test_item(content.items, "coal"), 5}
	return pair
}

@(test)
test_inserter_cycle_matches_the_rate :: proc(t: ^testing.T) {
	content := make_test_content()
	burner := content.machines.machines[test_machine(content.machines, "burner_inserter")]
	testing.expect_value(t, inserter_cycle_ticks(burner, TEST_TICK_RATE), 100)
	testing.expect_value(t, inserter_cycle_ticks(content.machines.machines[test_machine(content.machines, "inserter")], TEST_TICK_RATE), 72)
	testing.expect_value(t, fuel_joules_per_tick(burner, TEST_TICK_RATE), 1566)
	world := make_floor_world(content.blocks, 32)
	pair := make_chest_pair(&world, content)
	plate := test_item(content.items, "iron_plate")
	entity_insert(&world.entities, content, pair.source, Item_Stack{plate, 50})
	// Pick on tick 1, 50 ticks of swing, drop on arrival at tick 51.
	tick_test_entities(&world, content, 1)
	inserter := test_inserter(&world, pair.inserter)
	testing.expect_value(t, inserter.held, Item_Stack{plate, 1})
	testing.expect_value(t, inserter.state, Inserter_State.Moving)
	tick_test_entities(&world, content, 49)
	testing.expect_value(t, chest_count_of(&world, pair.target, plate), 0)
	testing.expect_value(t, inserter_arm_fraction(inserter^, burner, TEST_TICK_RATE), f32(49) / 50)
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, chest_count_of(&world, pair.target, plate), 1)
	testing.expect_value(t, inserter.phase, Inserter_Phase.Swinging_Back)
	// Back at tick 101 with the next pick; one minute moves 36.
	tick_test_entities(&world, content, 50)
	testing.expect_value(t, inserter.held, Item_Stack{plate, 1})
	tick_test_entities(&world, content, 3600 - 101)
	testing.expect_value(t, chest_count_of(&world, pair.target, plate), 36)
	testing.expect_value(t, chest_count_of(&world, pair.source, plate) + chest_count_of(&world, pair.target, plate) + int(inserter.held.count), 50)
}

@(test)
test_inserter_moves_from_a_belt_to_a_chest :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {0, 1, 0}, 2, 0)
	inserter := place_fuelled_inserter(&world, content, {1, 1, 1}, 1)
	chest := place_test_entity(&world, content, "wooden_chest", {1, 1, 2})
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	testing.expect(t, belt_insert_item(&world.entities, belts[1], .Left, plate))
	testing.expect(t, belt_insert_item(&world.entities, belts[0], .Right, coal))
	tick_test_entities(&world, content, 51)
	testing.expect_value(t, chest_count_of(&world, chest, plate), 1)
	// The coal rolls on to the second belt and is picked there next.
	tick_test_entities(&world, content, 100)
	testing.expect_value(t, chest_count_of(&world, chest, coal), 1)
	testing.expect_value(t, len(line_of(&world, belts[0]).lanes[.Left]) + len(line_of(&world, belts[0]).lanes[.Right]), 0)
	tick_test_entities(&world, content, 60)
	testing.expect_value(t, test_inserter(&world, inserter).state, Inserter_State.Idle)
	testing.expect(t, world.statistics.inserter_idle_ticks > 0)
}

@(test)
test_far_belt_lane :: proc(t: ^testing.T) {
	// The lanes of a belt: right is the side turn_right of its direction.
	testing.expect_value(t, far_belt_lane(1, 0), Belt_Lane.Right)
	testing.expect_value(t, far_belt_lane(3, 0), Belt_Lane.Left)
	testing.expect_value(t, far_belt_lane(1, 2), Belt_Lane.Left)
	testing.expect_value(t, far_belt_lane(3, 2), Belt_Lane.Right)
	testing.expect_value(t, far_belt_lane(0, 0), Belt_Lane.Right)
	testing.expect_value(t, far_belt_lane(2, 0), Belt_Lane.Right)
}

// Chest, inserter and belt in a row along the inserter's direction.
expect_drop_lane :: proc(t: ^testing.T, inserter_direction, belt_direction: u8, expected: Belt_Lane, location := #caller_location) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belt_cell := World_Coordinate{5, 1, 5}
	step := belt_direction_offset(inserter_direction)
	belt := lay_belt(&world, content, belt_cell, belt_direction)
	place_fuelled_inserter(&world, content, belt_cell - step, inserter_direction)
	chest := place_test_entity(&world, content, "wooden_chest", belt_cell - step * 2)
	plate := test_item(content.items, "iron_plate")
	entity_insert(&world.entities, content, chest, Item_Stack{plate, 1})
	tick_test_entities(&world, content, 51)
	line := line_of(&world, belt)
	other := expected == .Left ? Belt_Lane.Right : Belt_Lane.Left
	testing.expect_value(t, len(line.lanes[expected]), 1, location)
	testing.expect_value(t, len(line.lanes[other]), 0, location)
}

@(test)
test_inserter_drops_onto_the_far_lane :: proc(t: ^testing.T) {
	// From the -z side of an eastbound belt (its left) onto the right lane.
	expect_drop_lane(t, 1, 0, .Right)
	// From the +z side (its right) onto the left lane.
	expect_drop_lane(t, 3, 0, .Left)
	// A westbound belt swaps the lanes.
	expect_drop_lane(t, 1, 2, .Left)
	expect_drop_lane(t, 3, 2, .Right)
	// Belts running away from and towards the inserter take the right lane.
	expect_drop_lane(t, 0, 0, .Right)
	expect_drop_lane(t, 0, 2, .Right)
}

@(test)
test_inserter_feeds_a_furnace_by_its_slot_rules :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	belts := lay_belt_row(&world, content, {0, 1, 0}, 2, 0)
	inserter := place_fuelled_inserter(&world, content, {1, 1, 1}, 1)
	furnace := place_test_entity(&world, content, "stone_furnace", {1, 1, 2})
	plate, hematite, coal := test_item(content.items, "iron_plate"), test_item(content.items, "hematite"), test_item(content.items, "coal")
	// The plate is nearer the pickup point on a tie, but no furnace slot takes it.
	belt_insert_item(&world.entities, belts[1], .Left, plate)
	belt_insert_item(&world.entities, belts[1], .Right, hematite)
	tick_test_entities(&world, content, 51)
	slots := entity_slots(&world.entities, furnace)
	testing.expect_value(t, slots[FURNACE_INPUT_SLOT], Item_Stack{hematite, 1})
	testing.expect_value(t, len(line_of(&world, belts[1]).lanes[.Left]), 1)
	belt_insert_item(&world.entities, belts[1], .Right, coal)
	tick_test_entities(&world, content, 100)
	// The coal went into the fuel slot and the furnace lit it at once.
	testing.expect_value(t, pool_get(&world.entities.furnaces, furnace).fuel_item_joules, 4_000_000)
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], EMPTY_STACK)
	tick_test_entities(&world, content, 100)
	testing.expect_value(t, test_inserter(&world, inserter).state, Inserter_State.Idle)
	testing.expect_value(t, test_inserter(&world, inserter).held, EMPTY_STACK)
	testing.expect_value(t, len(line_of(&world, belts[1]).lanes[.Left]), 1)
}

@(test)
test_inserter_takes_only_from_the_furnace_output :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	furnace := place_test_entity(&world, content, "stone_furnace", {2, 1, 0})
	stone, coal, plate := test_item(content.items, "stone"), test_item(content.items, "coal"), test_item(content.items, "iron_plate")
	slots := entity_slots(&world.entities, furnace)
	// One stone is too little to smelt, so the furnace stays idle.
	slots[FURNACE_FUEL_SLOT] = Item_Stack{coal, 5}
	slots[FURNACE_INPUT_SLOT] = Item_Stack{stone, 1}
	slots[FURNACE_OUTPUT_SLOT] = Item_Stack{plate, 2}
	// Feeding in from an empty chest: never touches the output.
	place_test_entity(&world, content, "wooden_chest", {0, 1, 0})
	feeding := place_fuelled_inserter(&world, content, {1, 1, 0}, 0)
	// Taking out into a chest: only the output.
	taking := place_fuelled_inserter(&world, content, {4, 1, 0}, 0)
	chest := place_test_entity(&world, content, "wooden_chest", {5, 1, 0})
	tick_test_entities(&world, content, 600)
	testing.expect_value(t, slots[FURNACE_OUTPUT_SLOT], EMPTY_STACK)
	testing.expect_value(t, chest_count_of(&world, chest, plate), 2)
	testing.expect_value(t, slots[FURNACE_INPUT_SLOT], Item_Stack{stone, 1})
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], Item_Stack{coal, 5})
	testing.expect_value(t, test_inserter(&world, feeding).state, Inserter_State.Idle)
	testing.expect_value(t, test_inserter(&world, taking).state, Inserter_State.Idle)
	// A furnace behind a furnace: nothing the output holds goes in.
	slots[FURNACE_OUTPUT_SLOT] = Item_Stack{plate, 2}
	remove_entity(&world.entities, content.machines, chest)
	place_test_entity(&world, content, "stone_furnace", {5, 1, 0})
	tick_test_entities(&world, content, 200)
	testing.expect_value(t, slots[FURNACE_OUTPUT_SLOT], Item_Stack{plate, 2})
}

@(test)
test_filter_inserter_moves_only_its_filter_item :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pair := make_chest_pair(&world, content, "filter_inserter")
	coal, plate := test_item(content.items, "coal"), test_item(content.items, "iron_plate")
	entity_insert(&world.entities, content, pair.source, Item_Stack{coal, 3})
	entity_insert(&world.entities, content, pair.source, Item_Stack{plate, 3})
	inserter := test_inserter(&world, pair.inserter)
	// Electric inserters are unpowered until M4.
	tick_test_entities(&world, content, 100)
	testing.expect_value(t, inserter.state, Inserter_State.Unpowered)
	inserter.powered = true
	tick_test_entities(&world, content, 100)
	testing.expect_value(t, inserter.state, Inserter_State.No_Filter)
	testing.expect_value(t, inserter.held, EMPTY_STACK)
	inserter.filter = inserter_filter_after_input(inserter.filter, Item_Stack{plate, 7}, true, false)
	testing.expect_value(t, inserter.filter, plate)
	// 72 ticks a cycle: three plates in 3 * 72, then nothing more.
	tick_test_entities(&world, content, 4 * 72)
	testing.expect_value(t, chest_count_of(&world, pair.target, plate), 3)
	testing.expect_value(t, chest_count_of(&world, pair.target, coal), 0)
	testing.expect_value(t, chest_count_of(&world, pair.source, coal), 3)
	testing.expect_value(t, inserter.state, Inserter_State.Idle)
	testing.expect_value(t, inserter_filter_after_input(plate, EMPTY_STACK, false, true), NO_ITEM)
}

@(test)
test_burner_inserter_stalls_when_fuel_runs_out :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pair := make_chest_pair(&world, content)
	plate, coal := test_item(content.items, "iron_plate"), test_item(content.items, "coal")
	inserter := test_inserter(&world, pair.inserter)
	inserter.slots[INSERTER_FUEL_SLOT] = EMPTY_STACK
	inserter.fuel_joules = 1566 * 10
	// Idle burns nothing.
	tick_test_entities(&world, content, 20)
	testing.expect_value(t, inserter.state, Inserter_State.Idle)
	testing.expect_value(t, inserter.fuel_joules, 1566 * 10)
	testing.expect_value(t, world.statistics.inserter_idle_ticks, 20)
	entity_insert(&world.entities, content, pair.source, Item_Stack{plate, 5})
	// Pick, then ten ticks of swing, then it stops in place.
	tick_test_entities(&world, content, 11)
	testing.expect_value(t, inserter.state, Inserter_State.Moving)
	testing.expect_value(t, inserter.phase_ticks, 10)
	tick_test_entities(&world, content, 30)
	testing.expect_value(t, inserter.state, Inserter_State.No_Fuel)
	testing.expect_value(t, inserter.phase, Inserter_Phase.Swinging_To_Drop)
	testing.expect_value(t, inserter.phase_ticks, 10)
	testing.expect_value(t, inserter.held, Item_Stack{plate, 1})
	testing.expect_value(t, world.statistics.stalls[.Inserter_Out_Of_Fuel], 1)
	// Refuelled, it carries on from where it stopped.
	entity_insert(&world.entities, content, pair.inserter, Item_Stack{coal, 1})
	tick_test_entities(&world, content, 40)
	testing.expect_value(t, chest_count_of(&world, pair.target, plate), 1)
	testing.expect_value(t, world.statistics.fuel_burned, 1)
}

@(test)
test_inserter_waits_for_room_with_the_item_in_hand :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pair := make_chest_pair(&world, content)
	plate, stone := test_item(content.items, "iron_plate"), test_item(content.items, "stone")
	entity_insert(&world.entities, content, pair.source, Item_Stack{plate, 5})
	target := entity_slots(&world.entities, pair.target)
	for &slot in target {
		slot = Item_Stack{stone, item_stack_size(content.items, stone)}
	}
	tick_test_entities(&world, content, 80)
	inserter := test_inserter(&world, pair.inserter)
	testing.expect_value(t, inserter.state, Inserter_State.Waiting_For_Room)
	testing.expect_value(t, inserter.phase, Inserter_Phase.At_Drop)
	testing.expect_value(t, inserter.held, Item_Stack{plate, 1})
	testing.expect_value(t, world.statistics.stalls[.Inserter_Waiting_For_Room], 1)
	target[3] = EMPTY_STACK
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, target[3], Item_Stack{plate, 1})
	testing.expect_value(t, inserter.state, Inserter_State.Moving)
}

@(test)
test_picking_up_an_inserter_returns_its_fuel_and_held_item :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	pair := make_chest_pair(&world, content)
	plate := test_item(content.items, "iron_plate")
	entity_insert(&world.entities, content, pair.source, Item_Stack{plate, 5})
	tick_test_entities(&world, content, 10)
	player := make_test_player(content.blocks, {10, 1, 10})
	testing.expect(t, pick_up_entity(&world, content, &player, pair.inserter))
	testing.expect_value(t, inventory_count(player.inventory, plate), 1)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "coal")), 4)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "burner_inserter")), 1)
}

@(test)
test_inserter_hint_counters :: proc(t: ^testing.T) {
	counter, found := parse_named_enum(hint_counter_names, "inserter_idle_ticks")
	testing.expect(t, found)
	statistics := Statistics{inserter_idle_ticks = 7}
	statistics.stalls[.Inserter_Out_Of_Fuel] = 2
	statistics.stalls[.Inserter_Waiting_For_Room] = 3
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = counter}), 7)
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Inserter_Out_Of_Fuel}), 2)
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Inserter_Waiting_For_Room}), 3)
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Furnace_Out_Of_Fuel}), 0)
}

// Chest of ore, inserter, furnace, inserter, belt, inserter, chest:
// two worlds run 1200 ticks and end in the same state with plates in the
// last chest.
lay_smelting_line :: proc(world: ^World, content: Simulation_Content) -> (ore_chest, plate_chest: Entity_Handle) {
	ore_chest = place_test_entity(world, content, "wooden_chest", {0, 1, 0})
	entity_insert(&world.entities, content, ore_chest, Item_Stack{test_item(content.items, "hematite"), 16 * 50})
	place_fuelled_inserter(world, content, {1, 1, 0}, 0)
	furnace := place_test_entity(world, content, "stone_furnace", {2, 1, 0})
	entity_slots(&world.entities, furnace)[FURNACE_FUEL_SLOT] = Item_Stack{test_item(content.items, "coal"), 10}
	place_fuelled_inserter(world, content, {4, 1, 0}, 0)
	lay_belt_row(world, content, {5, 1, 0}, 3, 0)
	place_fuelled_inserter(world, content, {8, 1, 0}, 0)
	plate_chest = place_test_entity(world, content, "wooden_chest", {9, 1, 0})
	return
}

@(test)
test_inserter_smelting_line_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_floor_world(content.blocks, 32), make_floor_world(content.blocks, 32)}
	plate_chests: [2]Entity_Handle
	for &world, index in worlds {
		_, plate_chests[index] = lay_smelting_line(&world, content)
		tick_test_entities(&world, content, 1200)
	}
	first, second := &worlds[0].entities, &worlds[1].entities
	testing.expect_value(t, len(first.inserters.entries), len(second.inserters.entries))
	for inserter, index in first.inserters.entries {
		testing.expect(t, inserter == second.inserters.entries[index])
	}
	testing.expect(t, first.furnaces.entries[0] == second.furnaces.entries[0])
	for chest, index in first.chests.entries {
		testing.expect(t, chest == second.chests.entries[index])
	}
	for line, line_index in first.belt_network.lines {
		for lane in Belt_Lane {
			other := second.belt_network.lines[line_index].lanes[lane][:]
			testing.expect_value(t, len(line.lanes[lane]), len(other))
			for entry, index in line.lanes[lane] {
				testing.expect_value(t, entry, other[index])
			}
		}
	}
	plate := test_item(content.items, "iron_plate")
	delivered := chest_count_of(&worlds[0], plate_chests[0], plate)
	testing.expect(t, delivered >= 3)
	testing.expect_value(t, delivered, chest_count_of(&worlds[1], plate_chests[1], plate))
	testing.expect_value(t, worlds[0].statistics.stalls, worlds[1].statistics.stalls)
	testing.expect_value(t, worlds[0].statistics.inserter_idle_ticks, worlds[1].statistics.inserter_idle_ticks)
}
