package game

import "core:testing"

// The spent outcrop (work item 0096) on the drill tests' stone floor: an
// iron vein of radius 1 has five outcrop cells at y 0.

SPENT_OUTCROP_TEST_CELLS :: [5]World_Coordinate{{5, 0, 5}, {4, 0, 5}, {6, 0, 5}, {5, 0, 4}, {5, 0, 6}}

// Holds Mine on the cell until it is air, at cheat speed so any pickaxe
// tier works.
mine_test_cell :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, player: ^Player, cell: World_Coordinate) {
	player.target = Raycast_Hit{hit = true, block = cell}
	for _ in 0 ..< 600 {
		mine_with_player(world, records, content, player, true, TEST_TICK_RATE, 0, true)
		if world_get_block(world, cell) == AIR_BLOCK {
			return
		}
	}
	panic("the cell was not mined")
}

@(test)
test_mining_the_last_outcrop_block_spends_the_outcrop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	records := make_test_records(content)
	vein := add_test_vein(&world, content, "iron", {5, 5}, 1, IRON_TEST_VEIN)
	player := make_test_player(content.blocks, {10.5, 1, 10.5})
	cells := SPENT_OUTCROP_TEST_CELLS
	testing.expect_value(t, len(world.outcrop_cells), len(cells))
	for cell in cells[:len(cells) - 1] {
		mine_test_cell(&world, &records, content, &player, cell)
	}
	// Blocks remain: nothing yet.
	testing.expect_value(t, records.statistics.outcrops_spent, 0)
	testing.expect_value(t, known_vein_index(records.assayed_veins[:], vein), -1)
	mine_test_cell(&world, &records, content, &player, cells[len(cells) - 1])
	testing.expect_value(t, records.statistics.outcrops_spent, 1)
	index := known_vein_index(records.assayed_veins[:], vein)
	testing.expect(t, index >= 0)
	testing.expect(t, records.assayed_veins[index].from_spent_outcrop)
	testing.expect(t, !vein_is_assayed(records.assayed_veins[:], vein))
	testing.expect_value(t, records.assayed_veins[index].radius, 1)
	// Once per vein: an outcrop block put back and mined again says
	// nothing more, and neither does the stone beside it.
	world_set_block(&world, cells[0], content.veins.types[test_vein_type(content, "iron")].outcrop_blocks[0])
	mine_test_cell(&world, &records, content, &player, cells[0])
	mine_test_cell(&world, &records, content, &player, {8, 0, 8})
	testing.expect_value(t, records.statistics.outcrops_spent, 1)
	testing.expect_value(t, len(records.assayed_veins), 1)
}

@(test)
test_an_exhausted_vein_has_no_spent_outcrop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	records := make_test_records(content)
	vein := add_test_vein(&world, content, "iron", {5, 5}, 1, {})
	player := make_test_player(content.blocks, {10.5, 1, 10.5})
	for cell in SPENT_OUTCROP_TEST_CELLS {
		mine_test_cell(&world, &records, content, &player, cell)
	}
	testing.expect_value(t, records.statistics.outcrops_spent, 0)
	testing.expect_value(t, known_vein_index(records.assayed_veins[:], vein), -1)
}

// An outcrop cell whose chunk is not loaded counts as holding its block.
@(test)
test_an_unloaded_outcrop_cell_keeps_the_outcrop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {5, 5}, 1, IRON_TEST_VEIN)
	for cell in SPENT_OUTCROP_TEST_CELLS {
		world_set_block(&world, cell, AIR_BLOCK)
	}
	testing.expect(t, outcrop_spent_with_units_left(&world, content.veins, vein))
	world.outcrop_cells[{500, 0, 500}] = vein
	testing.expect(t, !outcrop_spent_with_units_left(&world, content.veins, vein))
}

// A vein assayed with the hammer stays assayed and still gets its one
// spent outcrop line.
@(test)
test_an_assayed_vein_spends_its_outcrop_once :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	records := make_test_records(content)
	vein := add_test_vein(&world, content, "iron", {5, 5}, 1, IRON_TEST_VEIN)
	testing.expect(t, assay_vein(&world, &records, content.veins, {5, 0, 5}))
	testing.expect(t, record_spent_outcrop(&world, &records, vein))
	testing.expect(t, !record_spent_outcrop(&world, &records, vein))
	testing.expect_value(t, records.statistics.outcrops_spent, 1)
	testing.expect_value(t, len(records.assayed_veins), 1)
	testing.expect(t, vein_is_assayed(records.assayed_veins[:], vein))
	testing.expect_value(t, records.statistics.veins_assayed, 1)
}
