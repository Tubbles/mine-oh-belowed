package game

import "core:fmt"
import "core:slice"
import "core:testing"

// Drill worlds stand on the stone floor of make_floor_world (top at y 1).
// Test veins lie in region (0, 0) with their outcrop in the floor.

// With statistics, so produced counts can be checked.
make_drill_world :: proc(content: Simulation_Content) -> World {
	world := make_floor_world(content.blocks, 32)
	world.statistics = make_statistics(len(content.items.items), len(content.machines.machines), len(content.blocks.definitions), context.temp_allocator)
	return world
}

test_vein_type :: proc(content: Simulation_Content, id: string) -> int {
	key := fmt.tprintf("vein_type_%s", id)
	for vein_type, index in content.veins.types {
		if vein_type.name_key == key {
			return index
		}
	}
	panic(id)
}

// Registered the way a chunk load registers it: the vein record, the
// column entries and the outcrop cells, with the outcrop blocks in the
// floor inside its disc.
add_test_vein :: proc(world: ^World, content: Simulation_Content, type_id: string, centre: [2]i32, radius: i32, remaining: [MAXIMUM_VEIN_OUTPUTS]i64, index: i32 = 0) -> Vein_Id {
	vein := Vein {
		id        = {region = {0, 0}, index = index},
		type      = test_vein_type(content, type_id),
		centre    = {centre.x, 0, centre.y},
		radius    = radius,
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
	outcrops := make([dynamic]Outcrop_Cell, context.temp_allocator)
	block := content.veins.types[vein.type].outcrop_blocks[0]
	for z in centre.y - radius ..= centre.y + radius {
		for x in centre.x - radius ..= centre.x + radius {
			if column_in_disc(vein.centre, radius, x, z) {
				world_set_block(world, {x, 0, z}, block)
				append(&outcrops, Outcrop_Cell{position = {x, 0, z}, vein = vein.id})
			}
		}
	}
	register_outcrop_cells(world, outcrops[:])
	return vein.id
}

// A drill with five coal in its fuel slot, tapping the vein.
place_test_drill :: proc(world: ^World, content: Simulation_Content, origin: World_Coordinate, rotation: u8, vein: Vein_Id) -> Entity_Handle {
	handle := place_test_entity(world, content, "burner_mining_drill", origin, rotation)
	drill := test_drill(world, handle)
	drill.vein = vein
	drill.slots[DRILL_FUEL_SLOT] = Item_Stack{test_item(content.items, "coal"), 5}
	return handle
}

test_drill :: proc(world: ^World, handle: Entity_Handle) -> ^Drill {
	return pool_get(&world.entities.drills, handle)
}

test_drill_machine :: proc(content: Simulation_Content) -> Machine {
	return content.machines.machines[test_machine(content.machines, "burner_mining_drill")]
}

IRON_TEST_VEIN :: [MAXIMUM_VEIN_OUTPUTS]i64{8000, 2000, 0, 0}

@(test)
test_drill_cycle_and_drop_cell :: proc(t: ^testing.T) {
	content := make_test_content()
	machine := test_drill_machine(content)
	// 18.75 units per minute: 15 hematite on an 80 percent iron vein.
	testing.expect_value(t, drill_cycle_ticks(machine, TEST_TICK_RATE), 192)
	testing.expect_value(t, drill_units_per_minute(machine, TEST_TICK_RATE), f32(18.75))
	testing.expect_value(t, fuel_joules_per_tick(machine, TEST_TICK_RATE), 2500)
	// In front of the side the arrow points to, at ground level, on the
	// arrow's left of the two cells.
	origin := World_Coordinate{4, 1, 4}
	expected := [4]World_Coordinate{{6, 1, 4}, {5, 1, 6}, {3, 1, 5}, {4, 1, 3}}
	for cell, rotation in expected {
		drill := Drill {
			common = make_entity_common(content.machines, test_machine(content.machines, "burner_mining_drill"), origin, u8(rotation)),
		}
		testing.expect_value(t, drill_drop_cell(drill, machine), cell)
	}
}

@(test)
test_drill_placement_needs_a_vein_outcrop :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	machine := test_machine(content.machines, "burner_mining_drill")
	on := placement_at(&world, content, nil, machine, {0, 1, 0}, 0)
	testing.expect(t, on.valid)
	testing.expect(t, on.drill)
	testing.expect_value(t, on.vein, vein)
	// One ground cell on the outcrop is enough.
	edge := placement_at(&world, content, nil, machine, {-2, 1, 1}, 0)
	testing.expect(t, edge.valid)
	testing.expect_value(t, edge.vein, vein)
	testing.expect(t, !placement_at(&world, content, nil, machine, {10, 1, 10}, 0).valid)
	// Inside the disc with no outcrop block left under the footprint: the
	// footprint decides, not the blocks (work item 0048).
	stone := test_block(content.blocks, "stone")
	set_blocks(&world, stone, {0, 0, 0}, {1, 0, 0}, {0, 0, 1}, {1, 0, 1})
	testing.expect(t, placement_at(&world, content, nil, machine, {0, 1, 0}, 0).valid)
	// The ordinary rules still hold: the footprint must be free.
	place_test_entity(&world, content, "wooden_chest", {-1, 2, 2})
	testing.expect(t, !placement_at(&world, content, nil, machine, {-2, 1, 1}, 0).valid)
}

// Draws from a big vein many times and compares the shares with the
// vein type's percents.
expect_draw_mix :: proc(t: ^testing.T, type_id: string, location := #caller_location) {
	content := make_test_content()
	world := make_drill_world(content)
	world.settings.seed = 12345
	id := add_test_vein(&world, content, type_id, {1, 1}, 2, {1_000_000, 1_000_000, 1_000_000, 1_000_000})
	vein_type := content.veins.types[registered_vein(&world, id).type]
	draws :: 20_000
	counts: [MAXIMUM_VEIN_OUTPUTS]int
	for _ in 0 ..< draws {
		item := draw_from_vein(&world, content.veins, registered_vein(&world, id))
		for index in 0 ..< vein_type.output_count {
			if vein_type.outputs[index] == item || vein_type.low_grades[index] == item {
				counts[index] += 1
			}
		}
	}
	for index in 0 ..< vein_type.output_count {
		share := f64(counts[index]) * 100 / draws
		testing.expectf(t, abs(share - f64(vein_type.percents[index])) < 1.5, "output %d: %.2f percent, expected %d", index, share, vein_type.percents[index], loc = location)
		testing.expect_value(t, registered_vein(&world, id).remaining[index], 1_000_000 - i64(counts[index]), location)
	}
	testing.expect_value(t, registered_vein(&world, id).draws, draws, location)
}

@(test)
test_vein_draws_follow_the_output_mix :: proc(t: ^testing.T) {
	expect_draw_mix(t, "iron")
	expect_draw_mix(t, "copper")
	expect_draw_mix(t, "quarry")
}

@(test)
test_drill_mines_into_a_chest_at_its_rate :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	drill := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 0})
	hematite, gravel := test_item(content.items, "hematite"), test_item(content.items, "gravel")
	tick_test_entities(&world, content, 191)
	testing.expect_value(t, chest_count_of(&world, chest, hematite) + chest_count_of(&world, chest, gravel), 0)
	testing.expect_value(t, test_drill(&world, drill).state, Drill_State.Mining)
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, chest_count_of(&world, chest, hematite) + chest_count_of(&world, chest, gravel), 1)
	// A minute holds 18 whole cycles and burns 9 MJ, three coal.
	tick_test_entities(&world, content, 3600 - 192)
	mined := chest_count_of(&world, chest, hematite) + chest_count_of(&world, chest, gravel)
	testing.expect_value(t, mined, 18)
	testing.expect_value(t, vein_remaining_total(registered_vein(&world, vein)^), 10_000 - 18)
	testing.expect_value(t, int(world.statistics.produced[hematite] + world.statistics.produced[gravel]), 18)
	testing.expect_value(t, production_rate_per_minute(world.statistics, hematite), world.statistics.produced[hematite])
	testing.expect_value(t, world.statistics.obtained[hematite], 0)
	testing.expect_value(t, world.statistics.fuel_burned, 3)
	testing.expect_value(t, test_drill(&world, drill).slots[DRILL_FUEL_SLOT].count, 2)
}

@(test)
test_drill_outputs_into_belts_and_furnaces :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 5}, 6, {1000, 0, 0, 0})
	// Belts across the arrow take the lane nearest the drill.
	northbound := lay_belt(&world, content, {2, 1, 0}, 1)
	place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	southbound := lay_belt(&world, content, {2, 1, 3}, 3)
	place_test_drill(&world, content, {0, 1, 3}, 0, vein)
	// A furnace takes the ore into its input slot.
	furnace := place_test_entity(&world, content, "stone_furnace", {2, 1, 6})
	place_test_drill(&world, content, {0, 1, 6}, 0, vein)
	tick_test_entities(&world, content, 192)
	testing.expect_value(t, len(line_of(&world, northbound).lanes[.Right]), 1)
	testing.expect_value(t, len(line_of(&world, northbound).lanes[.Left]), 0)
	testing.expect_value(t, len(line_of(&world, southbound).lanes[.Left]), 1)
	testing.expect_value(t, len(line_of(&world, southbound).lanes[.Right]), 0)
	testing.expect_value(t, entity_slots(&world.entities, furnace)[FURNACE_INPUT_SLOT], Item_Stack{test_item(content.items, "hematite"), 1})
}

@(test)
test_drill_exhausts_a_finite_vein_into_spent_rock :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, {3, 2, 0, 0})
	drill := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 0})
	tick_test_entities(&world, content, 5 * 192)
	testing.expect_value(t, chest_count_of(&world, chest, test_item(content.items, "hematite")), 3)
	testing.expect_value(t, chest_count_of(&world, chest, test_item(content.items, "gravel")), 2)
	testing.expect(t, registered_vein(&world, vein).exhausted)
	testing.expect_value(t, world.statistics.veins_exhausted, 1)
	spent, ore := test_block(content.blocks, "spent_rock"), test_block(content.blocks, "hematite_ore")
	for position, id in world.outcrop_cells {
		testing.expect_value(t, id, vein)
		testing.expect_value(t, world_get_block(&world, position), spent)
	}
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, test_drill(&world, drill).state, Drill_State.Vein_Exhausted)
	fuel := test_drill(&world, drill).fuel_joules
	tick_test_entities(&world, content, 100)
	testing.expect_value(t, test_drill(&world, drill).fuel_joules, fuel)
	// A chunk loaded after the exhaustion comes out as spent rock too.
	world_set_block(&world, {-20, 0, -20}, ore)
	register_outcrop_cells(&world, {Outcrop_Cell{position = {-20, 0, -20}, vein = vein}})
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, world_get_block(&world, {-20, 0, -20}), spent)
	testing.expect_value(t, world.statistics.veins_exhausted, 1)
}

@(test)
test_infinite_veins_never_run_dry :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	world.settings.veins_infinite = true
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, {1, 1, 0, 0})
	drill := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 0})
	tick_test_entities(&world, content, 10 * 192)
	testing.expect_value(t, chest_count_of(&world, chest, test_item(content.items, "hematite")) + chest_count_of(&world, chest, test_item(content.items, "gravel")), 10)
	testing.expect_value(t, registered_vein(&world, vein).remaining, [MAXIMUM_VEIN_OUTPUTS]i64{1, 1, 0, 0})
	testing.expect_value(t, test_drill(&world, drill).state, Drill_State.Mining)
	testing.expect(t, !registered_vein(&world, vein).exhausted)
}

@(test)
test_drill_stalls_on_blocked_output_and_on_fuel :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, {1000, 0, 0, 0})
	handle := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	drill := test_drill(&world, handle)
	hematite := test_item(content.items, "hematite")
	// Air in front: the unit stays in the drill, which stops burning and
	// says it has no output.
	tick_test_entities(&world, content, 192)
	testing.expect_value(t, drill.state, Drill_State.No_Output)
	testing.expect_value(t, drill.held, Item_Stack{hematite, 1})
	fuel := drill.fuel_joules
	tick_test_entities(&world, content, 300)
	testing.expect_value(t, drill.fuel_joules, fuel)
	testing.expect_value(t, drill.progress_ticks, 0)
	testing.expect_value(t, world.statistics.stalls[.Drill_Waiting_For_Room], 1)
	testing.expect_value(t, registered_vein(&world, vein).remaining[0], 999)
	// A full chest blocks it the same way.
	chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 0})
	stone := test_item(content.items, "stone")
	slots := entity_slots(&world.entities, chest)
	for &slot in slots {
		slot = Item_Stack{stone, item_stack_size(content.items, stone)}
	}
	tick_test_entities(&world, content, 10)
	testing.expect_value(t, drill.state, Drill_State.Waiting_For_Room)
	slots[0] = EMPTY_STACK
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, slots[0], Item_Stack{hematite, 1})
	testing.expect_value(t, drill.state, Drill_State.Mining)
	// Out of fuel: ten ticks of buffer, then a stall.
	drill.slots[DRILL_FUEL_SLOT] = EMPTY_STACK
	drill.fuel_joules = 2500 * 10
	tick_test_entities(&world, content, 11)
	testing.expect_value(t, drill.state, Drill_State.No_Fuel)
	testing.expect_value(t, world.statistics.stalls[.Drill_Out_Of_Fuel], 1)
	progress := drill.progress_ticks
	tick_test_entities(&world, content, 50)
	testing.expect_value(t, drill.progress_ticks, progress)
	// An inserter can refuel it through the transfer interface.
	testing.expect(t, entity_takes_item_kind(&world.entities, content, handle, test_item(content.items, "coal")))
	testing.expect(t, !entity_takes_item_kind(&world.entities, content, handle, hematite))
	entity_insert(&world.entities, content, handle, Item_Stack{test_item(content.items, "coal"), 1})
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, drill.state, Drill_State.Mining)
}

@(test)
test_two_drills_share_one_vein :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 2}, 3, {6, 2, 0, 0})
	first := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	second := place_test_drill(&world, content, {0, 1, 3}, 0, vein)
	first_chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 0})
	second_chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 3})
	hematite, gravel := test_item(content.items, "hematite"), test_item(content.items, "gravel")
	low_grade := test_item(content.items, "hematite_low_grade")
	// Both draw on the same tick, so four cycles drain eight units.
	tick_test_entities(&world, content, 4 * 192 + 1)
	ore_in :: proc(world: ^World, chest: Entity_Handle, hematite, low_grade: Item_Id) -> int {
		return chest_count_of(world, chest, hematite) + chest_count_of(world, chest, low_grade)
	}
	testing.expect_value(t, ore_in(&world, first_chest, hematite, low_grade) + ore_in(&world, second_chest, hematite, low_grade), 6)
	testing.expect_value(t, chest_count_of(&world, first_chest, gravel) + chest_count_of(&world, second_chest, gravel), 2)
	testing.expect_value(t, ore_in(&world, first_chest, hematite, low_grade) + chest_count_of(&world, first_chest, gravel), 4)
	testing.expect_value(t, test_drill(&world, first).state, Drill_State.Vein_Exhausted)
	testing.expect_value(t, test_drill(&world, second).state, Drill_State.Vein_Exhausted)
	testing.expect_value(t, registered_vein(&world, vein).draws, 8)
}

@(test)
test_picking_up_a_drill_returns_its_fuel_and_held_unit :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, {1000, 0, 0, 0})
	handle := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	tick_test_entities(&world, content, 192)
	player := make_test_player(content.blocks, {10, 1, 10})
	testing.expect(t, pick_up_entity(&world, content, &player, handle))
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "hematite")), 1)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "coal")), 4)
	testing.expect_value(t, inventory_count(player.inventory, test_item(content.items, "burner_mining_drill")), 1)
	testing.expect_value(t, len(world.entities.cells), 0)
}

@(test)
test_rotate_turns_a_placed_inserter_and_drill :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	drill := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	inserter := place_fuelled_inserter(&world, content, {5, 1, 5}, 0)
	players := []Player{make_test_player(content.blocks, {10, 1, 10})}
	for handle in ([2]Entity_Handle{drill, inserter}) {
		players[0].target = Raycast_Hit{hit = true, entity = handle}
		place_with_player(&world, content, players, 0, {.Rotate_Building})
		testing.expect_value(t, entity_common(&world.entities, handle).rotation, 1)
	}
	testing.expect_value(t, len(world.entities.cells), 9)
	for cell in footprint_cells({0, 1, 0}, {2, 2, 2}, 0) {
		testing.expect_value(t, entity_at(&world.entities, cell), drill)
	}
	machine := test_drill_machine(content)
	testing.expect_value(t, drill_drop_cell(test_drill(&world, drill)^, machine), World_Coordinate{1, 1, 2})
	testing.expect_value(t, inserter_drop_cell(test_inserter(&world, inserter)^), World_Coordinate{5, 1, 6})
}

@(test)
test_burner_inserter_feeds_itself_from_its_pickup :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	pair := make_chest_pair(&world, content)
	coal, plate := test_item(content.items, "coal"), test_item(content.items, "iron_plate")
	inserter := test_inserter(&world, pair.inserter)
	inserter.slots[INSERTER_FUEL_SLOT] = EMPTY_STACK
	// Plates alone cannot fuel it.
	entity_insert(&world.entities, content, pair.source, Item_Stack{plate, 1})
	tick_test_entities(&world, content, 5)
	testing.expect_value(t, inserter.state, Inserter_State.No_Fuel)
	testing.expect_value(t, chest_count_of(&world, pair.source, plate), 1)
	// Coal behind it: the first one becomes its fuel.
	entity_extract(&world.entities, content, pair.source, plate, 1)
	entity_insert(&world.entities, content, pair.source, Item_Stack{coal, 3})
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, inserter.held, Item_Stack{coal, 1})
	testing.expect_value(t, inserter.state, Inserter_State.Moving)
	testing.expect_value(t, inserter.slots[INSERTER_FUEL_SLOT], Item_Stack{coal, 1})
	// The first swing tick lights it.
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, inserter.slots[INSERTER_FUEL_SLOT], EMPTY_STACK)
	testing.expect_value(t, inserter.fuel_item_joules, 4_000_000)
	tick_test_entities(&world, content, 300)
	testing.expect_value(t, chest_count_of(&world, pair.target, coal), 2)
	testing.expect_value(t, chest_count_of(&world, pair.source, coal), 0)
	testing.expect_value(t, world.statistics.fuel_burned, 1)
}

@(test)
test_burner_inserter_feeds_itself_from_its_hand :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	pair := make_chest_pair(&world, content)
	coal := test_item(content.items, "coal")
	inserter := test_inserter(&world, pair.inserter)
	inserter.slots[INSERTER_FUEL_SLOT] = EMPTY_STACK
	inserter.held = Item_Stack{coal, 1}
	inserter.phase, inserter.phase_ticks = .Swinging_To_Drop, 10
	tick_test_entities(&world, content, 1)
	testing.expect_value(t, inserter.held, EMPTY_STACK)
	testing.expect_value(t, inserter.state, Inserter_State.Moving)
	testing.expect_value(t, inserter.phase_ticks, 11)
	testing.expect_value(t, world.statistics.fuel_burned, 1)
	tick_test_entities(&world, content, 100)
	testing.expect_value(t, chest_count_of(&world, pair.target, coal), 0)
	testing.expect_value(t, inserter.state, Inserter_State.Idle)
}

@(test)
test_drill_hint_counters :: proc(t: ^testing.T) {
	statistics := Statistics{veins_exhausted = 4}
	statistics.stalls[.Drill_Out_Of_Fuel] = 2
	statistics.stalls[.Drill_Waiting_For_Room] = 3
	expected := [3]struct {
		name:  string,
		value: u64,
	}{{"drill_out_of_fuel", 2}, {"drill_waiting_for_room", 3}, {"vein_exhausted", 4}}
	for entry in expected {
		counter, found := parse_named_enum(hint_counter_names, entry.name)
		testing.expect(t, found)
		testing.expect_value(t, hint_counter_value(statistics, Hint{counter = counter}), entry.value)
	}
	testing.expect_value(t, hint_counter_value(statistics, Hint{counter = .Inserter_Out_Of_Fuel}), 0)
}

@(test)
test_hud_names_the_vein_of_a_drill_or_outcrop :: proc(t: ^testing.T) {
	// No string table is loaded in tests, so text() records missing keys.
	defer clear_missing_reports(&global_string_table)
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, {300, 50, 0, 0})
	drill := place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	entity_line, vein_line := target_status_lines(&world, content.machines, content.fluids, content.veins, Raycast_Hit{hit = true, block = {-1, 0, 1}})
	testing.expect_value(t, entity_line, "")
	testing.expect_value(t, vein_line, fmt.tprintf("%s  350 %s", text("vein_type_iron"), text("drill_remaining")))
	entity_line, vein_line = target_status_lines(&world, content.machines, content.fluids, content.veins, Raycast_Hit{hit = true, block = {0, 1, 0}, entity = drill})
	testing.expect(t, entity_line != "")
	testing.expect(t, vein_line != "")
	_, vein_line = target_status_lines(&world, content.machines, content.fluids, content.veins, Raycast_Hit{hit = true, block = {10, 0, 10}})
	testing.expect_value(t, vein_line, "")
	lines := drill_vein_lines(&world, content.veins, content.items, test_drill(&world, drill)^)
	testing.expect_value(t, len(lines), 3)
	world.settings.veins_infinite = true
	testing.expect_value(t, len(drill_vein_lines(&world, content.veins, content.items, test_drill(&world, drill)^)), 2)
}

// Drill on an iron vein, belt, inserter, chest: two worlds run 1200 ticks
// and end in the same state with ore in the chest.
lay_mining_line :: proc(world: ^World, content: Simulation_Content) -> (drill, chest: Entity_Handle) {
	world.settings.seed = 99
	vein := add_test_vein(world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	drill = place_test_drill(world, content, {0, 1, 0}, 0, vein)
	lay_belt_row(world, content, {2, 1, 0}, 4, 0)
	place_fuelled_inserter(world, content, {6, 1, 0}, 0)
	chest = place_test_entity(world, content, "wooden_chest", {7, 1, 0})
	return
}

@(test)
test_drill_mining_line_is_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	worlds := [2]World{make_drill_world(content), make_drill_world(content)}
	chests: [2]Entity_Handle
	for &world, index in worlds {
		_, chests[index] = lay_mining_line(&world, content)
		tick_test_entities(&world, content, 1200)
	}
	first, second := &worlds[0], &worlds[1]
	testing.expect(t, first.entities.drills.entries[0] == second.entities.drills.entries[0])
	testing.expect(t, first.entities.inserters.entries[0] == second.entities.inserters.entries[0])
	testing.expect(t, first.veins[0] == second.veins[0])
	testing.expect(t, first.entities.chests.entries[0] == second.entities.chests.entries[0])
	for line, line_index in first.entities.belt_network.lines {
		for lane in Belt_Lane {
			other := second.entities.belt_network.lines[line_index].lanes[lane][:]
			testing.expect_value(t, len(line.lanes[lane]), len(other))
			for entry, index in line.lanes[lane] {
				testing.expect_value(t, entry, other[index])
			}
		}
	}
	hematite, gravel := test_item(content.items, "hematite"), test_item(content.items, "gravel")
	delivered := chest_count_of(first, chests[0], hematite) + chest_count_of(first, chests[0], gravel)
	testing.expect(t, delivered >= 3)
	testing.expect_value(t, first.veins[0].draws, 6)
	testing.expect_value(t, first.statistics.produced[hematite], second.statistics.produced[hematite])
	testing.expect_value(t, first.statistics.stalls, second.statistics.stalls)
}

// Couch test 1 (work item 0048): the outcrop blocks were mined by hand,
// yet a drill placed on the same spot is valid and mines.
@(test)
test_drill_mines_a_footprint_whose_outcrop_was_mined :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	stone := test_block(content.blocks, "stone")
	set_blocks(&world, stone, {0, 0, 0}, {1, 0, 0}, {0, 0, 1}, {1, 0, 1})
	placement := placement_at(&world, content, nil, test_machine(content.machines, "burner_mining_drill"), {0, 1, 0}, 0)
	testing.expect(t, placement.valid)
	testing.expect_value(t, placement.vein, vein)
	place_test_drill(&world, content, {0, 1, 0}, 0, placement.vein)
	chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 0})
	tick_test_entities(&world, content, 192)
	testing.expect_value(t, chest_total(&world, chest), 1)
}

@(test)
test_hud_names_the_vein_under_a_plain_block_in_its_footprint :: proc(t: ^testing.T) {
	defer clear_missing_reports(&global_string_table)
	content := make_test_content()
	world := make_drill_world(content)
	add_test_vein(&world, content, "iron", {1, 1}, 2, {300, 50, 0, 0})
	world_set_block(&world, {1, 0, 1}, test_block(content.blocks, "stone"))
	_, vein_line := target_status_lines(&world, content.machines, content.fluids, content.veins, Raycast_Hit{hit = true, block = {1, 0, 1}})
	testing.expect_value(t, vein_line, fmt.tprintf("%s  350 %s", text("vein_type_iron"), text("drill_remaining")))
	_, vein_line = target_status_lines(&world, content.machines, content.fluids, content.veins, Raycast_Hit{hit = true, block = {4, 0, 4}})
	testing.expect_value(t, vein_line, "")
}

// Footprints are discs, so two veins may reach into one chunk and each
// takes a drill on its own disc.
@(test)
test_two_veins_in_one_chunk_both_take_a_drill :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	iron := add_test_vein(&world, content, "iron", {4, 4}, 2, IRON_TEST_VEIN)
	lead := add_test_vein(&world, content, "lead", {20, 20}, 3, {1000, 1000, 1000, 1000}, 1)
	testing.expect_value(t, len(veins_of_column(&world, {0, 0}, context.temp_allocator)), 2)
	machine := test_machine(content.machines, "burner_mining_drill")
	expected := [2]struct {
		origin: World_Coordinate,
		vein:   Vein_Id,
	}{{{3, 1, 3}, iron}, {{19, 1, 19}, lead}}
	chests: [2]Entity_Handle
	for entry, index in expected {
		placement := placement_at(&world, content, nil, machine, entry.origin, 0)
		testing.expect(t, placement.valid)
		testing.expect_value(t, placement.vein, entry.vein)
		place_test_drill(&world, content, entry.origin, 0, placement.vein)
		chests[index] = place_test_entity(&world, content, "wooden_chest", entry.origin + {2, 0, 0})
	}
	tick_test_entities(&world, content, 192)
	for chest in chests {
		testing.expect_value(t, chest_total(&world, chest), 1)
	}
}
