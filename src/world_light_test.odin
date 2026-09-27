package game

import "core:container/queue"
import "core:log"
import "core:testing"
import "core:time"

// Enough ticks for every test scene to settle.
TEST_SETTLE_TICKS :: 2000

world_is_idle :: proc(world: ^World) -> bool {
	return len(world.block_changes) == 0 && queue.len(world.water.updates) == 0 && pending_light_nodes(world.lighting) == 0 && queue.len(world.lighting.arrived_chunks) == 0
}

// Ticks the world until nothing is pending. Returns the last tick run.
settle_world :: proc(t: ^testing.T, world: ^World, registry: Block_Registry, first_tick: u64) -> u64 {
	tick := first_tick
	for _ in 0 ..< TEST_SETTLE_TICKS {
		tick += 1
		tick_world(world, registry, tick)
		if world_is_idle(world) {
			return tick
		}
	}
	testing.fail_now(t, "the world did not settle")
}

sky_at :: proc(world: ^World, position: World_Coordinate) -> u8 {
	return light_level(world_get_light(world, position), .Sky)
}

block_light_at :: proc(world: ^World, position: World_Coordinate) -> u8 {
	return light_level(world_get_light(world, position), .Block)
}

every_column_open :: proc() -> ^Open_Columns {
	open := new(Open_Columns, context.temp_allocator)
	for &column in open {
		column = true
	}
	return open
}

// A stone roof over the whole chunk at y 20, with one opening at x 10 z 10
// when opening is set.
make_roofed_chunk :: proc(registry: Block_Registry, opening: bool) -> ^Chunk {
	chunk := make_test_chunk({0, 0, 0})
	stone := test_block(registry, "stone")
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			chunk_set_block(chunk, {x, 20, z}, stone)
		}
	}
	if opening {
		chunk_set_block(chunk, {10, 20, 10}, AIR_BLOCK)
	}
	fill_chunk_sky_light(chunk, registry, every_column_open())
	return chunk
}

chunk_sky :: proc(chunk: ^Chunk, local: Local_Coordinate) -> u8 {
	return light_level(chunk.light[local_to_index(local)], .Sky)
}

@(test)
test_sky_light_roof_leaves_darkness :: proc(t: ^testing.T) {
	registry := make_test_registry()
	chunk := make_roofed_chunk(registry, false)
	testing.expect_value(t, chunk_sky(chunk, {10, 21, 10}), MAXIMUM_LIGHT)
	testing.expect_value(t, chunk_sky(chunk, {10, 20, 10}), 0)
	testing.expect_value(t, chunk_sky(chunk, {10, 19, 10}), 0)
	testing.expect_value(t, chunk_sky(chunk, {0, 0, 0}), 0)
}

// Full light falls straight through the opening to the bottom, and spreads
// sideways under the roof losing one level per block.
@(test)
test_sky_light_opening_lights_first_cells :: proc(t: ^testing.T) {
	registry := make_test_registry()
	chunk := make_roofed_chunk(registry, true)
	testing.expect_value(t, chunk_sky(chunk, {10, 20, 10}), MAXIMUM_LIGHT)
	testing.expect_value(t, chunk_sky(chunk, {10, 19, 10}), MAXIMUM_LIGHT)
	testing.expect_value(t, chunk_sky(chunk, {10, 0, 10}), MAXIMUM_LIGHT)
	testing.expect_value(t, chunk_sky(chunk, {11, 19, 10}), 14)
	testing.expect_value(t, chunk_sky(chunk, {13, 19, 11}), 11)
	testing.expect_value(t, chunk_sky(chunk, {30, 19, 30}), 0)
}

@(test)
test_sky_light_closed_column_stays_dark :: proc(t: ^testing.T) {
	registry := make_test_registry()
	chunk := make_test_chunk({0, 0, 0})
	open: Open_Columns
	fill_chunk_sky_light(chunk, registry, &open)
	testing.expect_value(t, chunk_sky(chunk, {5, 31, 5}), 0)
}

// Covering the opening from the main thread removes the light it let in.
@(test)
test_sky_light_removed_when_opening_closes :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_test_world({})
	chunk := make_roofed_chunk(registry, true)
	world.chunks[chunk.coordinate] = chunk
	world_set_block(&world, {10, 20, 10}, test_block(registry, "stone"))
	settle_world(t, &world, registry, 0)
	testing.expect_value(t, sky_at(&world, {10, 19, 10}), 0)
	testing.expect_value(t, sky_at(&world, {12, 5, 10}), 0)
	testing.expect_value(t, sky_at(&world, {10, 21, 10}), MAXIMUM_LIGHT)
	world_set_block(&world, {10, 20, 10}, AIR_BLOCK)
	settle_world(t, &world, registry, 100)
	testing.expect_value(t, sky_at(&world, {10, 0, 10}), MAXIMUM_LIGHT)
	testing.expect_value(t, sky_at(&world, {11, 19, 10}), 14)
}

@(test)
test_block_light_add_and_remove :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_test_world({{0, 0, 0}})
	torch := test_block(registry, "torch")
	world_set_block(&world, {10, 10, 10}, torch)
	tick := settle_world(t, &world, registry, 0)
	testing.expect_value(t, block_light_at(&world, {10, 10, 10}), 14)
	testing.expect_value(t, block_light_at(&world, {12, 10, 10}), 12)
	testing.expect_value(t, block_light_at(&world, {10, 12, 13}), 9)
	testing.expect_value(t, block_light_at(&world, {23, 10, 10}), 1)
	testing.expect_value(t, block_light_at(&world, {24, 10, 10}), 0)

	// A wall between torch and cell makes the light go round it.
	world_set_block(&world, {11, 10, 10}, test_block(registry, "stone"))
	tick = settle_world(t, &world, registry, tick)
	testing.expect_value(t, block_light_at(&world, {11, 10, 10}), 0)
	testing.expect_value(t, block_light_at(&world, {12, 10, 10}), 10)

	world_set_block(&world, {10, 10, 10}, AIR_BLOCK)
	settle_world(t, &world, registry, tick)
	for index in 0 ..< CHUNK_BLOCK_COUNT {
		if light_level(world.chunks[{0, 0, 0}].light[index], .Block) != 0 {
			testing.fail_now(t, "block light left after the torch was removed")
		}
	}
}

// Two torches: removing one leaves the other's light intact.
@(test)
test_block_light_removal_keeps_other_source :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_test_world({{0, 0, 0}})
	torch := test_block(registry, "torch")
	world_set_block(&world, {5, 10, 10}, torch)
	world_set_block(&world, {15, 10, 10}, torch)
	tick := settle_world(t, &world, registry, 0)
	testing.expect_value(t, block_light_at(&world, {10, 10, 10}), 9)
	world_set_block(&world, {5, 10, 10}, AIR_BLOCK)
	settle_world(t, &world, registry, tick)
	testing.expect_value(t, block_light_at(&world, {10, 10, 10}), 9)
	testing.expect_value(t, block_light_at(&world, {5, 10, 10}), 4)
	testing.expect_value(t, block_light_at(&world, {1, 10, 10}), 0)
}

@(test)
test_block_light_crosses_chunk_border :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_test_world({{0, 0, 0}, {1, 0, 0}})
	world.chunks[{1, 0, 0}].dirty = false
	world_set_block(&world, {30, 10, 10}, test_block(registry, "torch"))
	settle_world(t, &world, registry, 0)
	testing.expect_value(t, block_light_at(&world, {32, 10, 10}), 12)
	testing.expect_value(t, block_light_at(&world, {35, 10, 10}), 9)
	testing.expect(t, world.chunks[{1, 0, 0}].dirty)
}

// A chunk arriving next to a lit one gets the light that flows across the
// border: an open sky chunk lights the tunnel of a solid neighbour.
@(test)
test_sky_light_flows_into_arriving_chunk :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_test_world({})
	sky := make_test_chunk({0, 0, 0})
	fill_chunk_sky_light(sky, registry, every_column_open())
	world.chunks[sky.coordinate] = sky
	rock := make_test_chunk({1, 0, 0})
	fill_chunk(rock, test_block(registry, "stone"))
	for x in i32(0) ..< CHUNK_SIZE {
		chunk_set_block(rock, {x, 10, 10}, AIR_BLOCK)
	}
	world.chunks[rock.coordinate] = rock
	queue.push_back(&world.lighting.arrived_chunks, rock.coordinate)
	settle_world(t, &world, registry, 0)
	testing.expect_value(t, sky_at(&world, {32, 10, 10}), 14)
	testing.expect_value(t, sky_at(&world, {40, 10, 10}), 6)
	testing.expect_value(t, sky_at(&world, {46, 10, 10}), 0)
}

@(test)
test_generated_chunks_carry_sky_light :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	high := generate_chunk(&generator, {0, 5, 0}, context.temp_allocator)
	testing.expect(t, chunk_is_open_sky(high.chunk))
	deep := generate_chunk(&generator, {0, -8, 0}, context.temp_allocator)
	testing.expect_value(t, deep.chunk.light[0], 0)
	// Surface column: full sky light just above the surface block when the
	// surface lies in the chunk and nothing grows over it.
	surface := generate_chunk(&generator, {0, 1, 0}, context.temp_allocator)
	lit_columns := 0
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			if chunk_sky(surface.chunk, {x, CHUNK_SIZE - 1, z}) == MAXIMUM_LIGHT {
				lit_columns += 1
			}
		}
	}
	testing.expect(t, lit_columns > 0)
}

// Main thread light work after generated chunks arrive, for the notes: how
// many ticks and queue nodes the border seeding needs on real terrain.
@(test)
test_report_light_settling_on_generated_terrain :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	world: World
	defer destroy_world(&world)
	for z in i32(-2) ..= 2 {
		for x in i32(-2) ..= 2 {
			for y in i32(-1) ..= 2 {
				generated := generate_chunk(&generator, {x, y, z})
				insert_generated_chunk(&world, Chunk_Job_Result{kind = .Generate, coordinate = {x, y, z}, chunk = generated.chunk, veins = generated.veins, outcrops = generated.outcrops})
				delete(generated.veins)
				delete(generated.outcrops)
			}
		}
	}
	start := time.tick_now()
	ticks, steps, busiest := 0, 0, time.Duration(0)
	for !world_is_idle(&world) && ticks < TEST_SETTLE_TICKS {
		tick_start := time.tick_now()
		seed_arrived_chunks(&world, registry, MAXIMUM_LIGHT_CHUNK_SEEDS_PER_TICK)
		steps += propagate_light(&world, registry, MAXIMUM_LIGHT_STEPS_PER_TICK)
		busiest = max(busiest, time.tick_since(tick_start))
		ticks += 1
	}
	testing.expect(t, world_is_idle(&world))
	log.infof("light settled over %d chunks in %d ticks, %d queue nodes, %v in total, slowest tick %v", len(world.chunks), ticks, steps, time.tick_since(start), busiest)
}
