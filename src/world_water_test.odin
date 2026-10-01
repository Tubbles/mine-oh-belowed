package game

import "core:container/queue"
import "core:slice"
import "core:testing"

// One chunk with a stone floor filling y 0 up to floor_top.
make_water_world :: proc(registry: Block_Registry, floor_top: i32) -> World {
	world := make_test_world({{0, 0, 0}})
	stone := test_block(registry, "stone")
	chunk := world.chunks[{0, 0, 0}]
	for y in i32(0) ..= floor_top {
		for z in i32(0) ..< CHUNK_SIZE {
			for x in i32(0) ..< CHUNK_SIZE {
				chunk_set_block(chunk, {x, y, z}, stone)
			}
		}
	}
	return world
}

water_level_at :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate) -> int {
	return world_water_level(world, registry, position)
}

@(test)
test_water_spreads_seven_blocks_from_source :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_water_world(registry, 0)
	world_set_block(&world, {10, 1, 10}, test_block(registry, "water"))
	settle_world(t, &world, registry, 0)
	for step in i32(1) ..= 7 {
		testing.expect_value(t, water_level_at(&world, registry, {10 + step, 1, 10}), WATER_SOURCE_LEVEL - int(step))
	}
	testing.expect_value(t, world_get_block(&world, {18, 1, 10}), AIR_BLOCK)
	testing.expect_value(t, water_level_at(&world, registry, {12, 1, 12}), 4)
	testing.expect_value(t, world_get_block(&world, {10, 2, 10}), AIR_BLOCK)
}

// A machine's cells are air in the chunk, but water must not flow into them.
@(test)
test_water_stays_out_of_entity_cells :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_water_world(registry, 0)
	world.entities.cells[{11, 1, 10}] = Entity_Handle{kind = .Chest, index = 0, generation = 1}
	world_set_block(&world, {10, 1, 10}, test_block(registry, "water"))
	settle_world(t, &world, registry, 0)
	testing.expect_value(t, water_level_at(&world, registry, {11, 1, 10}), 0)
	testing.expect_value(t, water_level_at(&world, registry, {9, 1, 10}), WATER_SOURCE_LEVEL - 1)
}

// Picking up a chest standing beside a source lets the water into its
// cell.
@(test)
test_water_flows_into_the_cell_a_machine_leaves :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_water_world(content.blocks, 0)
	player := make_test_player(content.blocks, {2.5, 1, 2.5})
	chest := place_test_entity(&world, content, "wooden_chest", {11, 1, 10})
	world_set_block(&world, {10, 1, 10}, test_block(content.blocks, "water"))
	tick := settle_world(t, &world, content.blocks, 0)
	testing.expect_value(t, water_level_at(&world, content.blocks, {11, 1, 10}), 0)
	testing.expect(t, pick_up_entity(&world, content, &player, chest, tick))
	settle_world(t, &world, content.blocks, tick)
	testing.expect_value(t, water_level_at(&world, content.blocks, {11, 1, 10}), WATER_SOURCE_LEVEL - 1)
}

@(test)
test_water_drains_when_source_is_removed :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_water_world(registry, 0)
	world_set_block(&world, {10, 1, 10}, test_block(registry, "water"))
	tick := settle_world(t, &world, registry, 0)
	world_set_block(&world, {10, 1, 10}, AIR_BLOCK)
	settle_world(t, &world, registry, tick)
	chunk := world.chunks[{0, 0, 0}]
	for block in chunk.blocks {
		if block_water_level(registry, block) > 0 {
			testing.fail_now(t, "water left after the source was removed")
		}
	}
}

// Water falls first: a source in the air spreads one block to each side,
// every column falls to the floor, and the water spreads again there.
@(test)
test_water_falls_before_spreading :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_water_world(registry, 0)
	world_set_block(&world, {10, 6, 10}, test_block(registry, "water"))
	settle_world(t, &world, registry, 0)
	testing.expect_value(t, water_level_at(&world, registry, {11, 6, 10}), WATER_FALLING_LEVEL)
	testing.expect_value(t, world_get_block(&world, {12, 6, 10}), AIR_BLOCK)
	for y in i32(1) ..= 5 {
		testing.expect_value(t, water_level_at(&world, registry, {10, y, 10}), WATER_FALLING_LEVEL)
	}
	testing.expect_value(t, water_level_at(&world, registry, {12, 1, 10}), WATER_FALLING_LEVEL - 1)
	testing.expect_value(t, world_get_block(&world, {12, 2, 10}), AIR_BLOCK)
}

// Digging out the floor under a lake floods the hole.
@(test)
test_water_floods_hole_under_lake :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_water_world(registry, 4)
	water := test_block(registry, "water")
	chunk := world.chunks[{0, 0, 0}]
	for z in i32(8) ..< 16 {
		for x in i32(8) ..< 16 {
			chunk_set_block(chunk, {x, 5, z}, water)
		}
	}
	world_set_block(&world, {10, 4, 10}, AIR_BLOCK)
	world_set_block(&world, {10, 3, 10}, AIR_BLOCK)
	world_set_block(&world, {11, 3, 10}, AIR_BLOCK)
	settle_world(t, &world, registry, 0)
	testing.expect_value(t, water_level_at(&world, registry, {10, 4, 10}), WATER_FALLING_LEVEL)
	testing.expect_value(t, water_level_at(&world, registry, {10, 3, 10}), WATER_FALLING_LEVEL)
	testing.expect_value(t, water_level_at(&world, registry, {11, 3, 10}), WATER_FALLING_LEVEL - 1)
	testing.expect_value(t, water_level_at(&world, registry, {10, 5, 10}), WATER_SOURCE_LEVEL)
}

Water_Run :: struct {
	world:          World,
	most_per_tick:  int,
	changed_blocks: int,
}

// Two sources, one removed half way, run for a fixed number of ticks.
run_water_scene :: proc(registry: Block_Registry) -> Water_Run {
	run := Water_Run {
		world = make_water_world(registry, 0),
	}
	water := test_block(registry, "water")
	world_set_block(&run.world, {8, 1, 8}, water)
	world_set_block(&run.world, {20, 1, 14}, water)
	for tick in u64(1) ..= 400 {
		if tick == 150 {
			world_set_block(&run.world, {8, 1, 8}, AIR_BLOCK)
		}
		run.changed_blocks += len(run.world.block_changes)
		apply_block_changes(&run.world, registry, tick)
		updates := run_water_updates(&run.world, registry, tick, MAXIMUM_WATER_UPDATES_PER_TICK)
		run.most_per_tick = max(run.most_per_tick, updates)
		propagate_light(&run.world, registry, MAXIMUM_LIGHT_STEPS_PER_TICK)
	}
	return run
}

@(test)
test_water_updates_are_deterministic_and_bounded :: proc(t: ^testing.T) {
	registry := make_test_registry()
	first := run_water_scene(registry)
	second := run_water_scene(registry)
	testing.expect(t, slice.equal(first.world.chunks[{0, 0, 0}].blocks[:], second.world.chunks[{0, 0, 0}].blocks[:]))
	testing.expect_value(t, first.changed_blocks, second.changed_blocks)
	testing.expect(t, first.changed_blocks > 100)
	testing.expect(t, first.most_per_tick <= MAXIMUM_WATER_UPDATES_PER_TICK)
	testing.expect_value(t, queue.len(first.world.water.updates), queue.len(second.world.water.updates))
	// The removed source's water is gone, the other source still stands.
	testing.expect_value(t, world_get_block(&first.world, {9, 1, 8}), AIR_BLOCK)
	testing.expect_value(t, water_level_at(&first.world, registry, {21, 1, 14}), WATER_SOURCE_LEVEL - 1)
}

// More scheduled updates than the bound are spread over several ticks.
@(test)
test_water_updates_respect_the_bound :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_water_world(registry, 0)
	for x in i32(0) ..< CHUNK_SIZE {
		for z in i32(0) ..< 20 {
			schedule_water_update(&world.water, {x, 1, z}, 1)
		}
	}
	testing.expect_value(t, run_water_updates(&world, registry, 1, MAXIMUM_WATER_UPDATES_PER_TICK), MAXIMUM_WATER_UPDATES_PER_TICK)
	testing.expect_value(t, queue.len(world.water.updates), CHUNK_SIZE * 20 - MAXIMUM_WATER_UPDATES_PER_TICK)
	testing.expect_value(t, run_water_updates(&world, registry, 0, MAXIMUM_WATER_UPDATES_PER_TICK), 0)
}
