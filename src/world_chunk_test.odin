package game

import "core:container/queue"
import "core:testing"

@(test)
test_floor_divide_negative_values :: proc(t: ^testing.T) {
	testing.expect_value(t, floor_divide(0, CHUNK_SIZE), 0)
	testing.expect_value(t, floor_divide(31, CHUNK_SIZE), 0)
	testing.expect_value(t, floor_divide(32, CHUNK_SIZE), 1)
	testing.expect_value(t, floor_divide(-1, CHUNK_SIZE), -1)
	testing.expect_value(t, floor_divide(-32, CHUNK_SIZE), -1)
	testing.expect_value(t, floor_divide(-33, CHUNK_SIZE), -2)
}

@(test)
test_world_to_chunk_and_local_at_borders :: proc(t: ^testing.T) {
	Conversion_Case :: struct {
		world: World_Coordinate,
		chunk: Chunk_Coordinate,
		local: Local_Coordinate,
	}
	cases := [?]Conversion_Case {
		{{0, 0, 0}, {0, 0, 0}, {0, 0, 0}},
		{{31, 32, 63}, {0, 1, 1}, {31, 0, 31}},
		{{-1, -1, -1}, {-1, -1, -1}, {31, 31, 31}},
		{{-32, -33, -64}, {-1, -2, -2}, {0, 31, 0}},
		{{-65, 64, -31}, {-3, 2, -1}, {31, 0, 1}},
	}
	for conversion in cases {
		testing.expect_value(t, world_to_chunk_coordinate(conversion.world), conversion.chunk)
		testing.expect_value(t, world_to_local_coordinate(conversion.world), conversion.local)
		testing.expect_value(t, local_to_world_coordinate(conversion.chunk, conversion.local), conversion.world)
	}
}

@(test)
test_world_coordinate_round_trip_across_zero :: proc(t: ^testing.T) {
	for value in i32(-100) ..= 100 {
		position := World_Coordinate{value, -value, value * 3}
		chunk := world_to_chunk_coordinate(position)
		local := world_to_local_coordinate(position)
		testing.expect(t, local_in_bounds(local))
		testing.expect_value(t, local_to_world_coordinate(chunk, local), position)
	}
}

@(test)
test_local_index_round_trip :: proc(t: ^testing.T) {
	for index in 0 ..< CHUNK_BLOCK_COUNT {
		if index_to_local(index) != index_to_local(local_to_index(index_to_local(index))) {
			testing.fail_now(t, "index round trip failed")
		}
		if local_to_index(index_to_local(index)) != index {
			testing.fail_now(t, "local round trip failed")
		}
	}
	testing.expect_value(t, local_to_index({31, 31, 31}), CHUNK_BLOCK_COUNT - 1)
}

// Everything the world allocates comes from the temp allocator.
make_test_world :: proc(coordinates: []Chunk_Coordinate) -> World {
	world: World
	world.chunks = make(map[Chunk_Coordinate]^Chunk, context.temp_allocator)
	world.block_changes = make([dynamic]Block_Change, context.temp_allocator)
	world.water.scheduled = make(map[World_Coordinate]struct{}, context.temp_allocator)
	queue.init(&world.water.updates, allocator = context.temp_allocator)
	queue.init(&world.lighting.removals, allocator = context.temp_allocator)
	queue.init(&world.lighting.additions, allocator = context.temp_allocator)
	queue.init(&world.lighting.arrived_chunks, allocator = context.temp_allocator)
	world.entities.cells = make(map[World_Coordinate]Entity_Handle, context.temp_allocator)
	world.entities.chests.entries = make([dynamic]Chest, context.temp_allocator)
	world.entities.chests.free = make([dynamic]u32, context.temp_allocator)
	world.entities.furnaces.entries = make([dynamic]Furnace, context.temp_allocator)
	world.entities.furnaces.free = make([dynamic]u32, context.temp_allocator)
	world.entities.belts.entries = make([dynamic]Belt, context.temp_allocator)
	world.entities.belts.free = make([dynamic]u32, context.temp_allocator)
	world.entities.inserters.entries = make([dynamic]Inserter, context.temp_allocator)
	world.entities.inserters.free = make([dynamic]u32, context.temp_allocator)
	world.entities.drills.entries = make([dynamic]Drill, context.temp_allocator)
	world.entities.drills.free = make([dynamic]u32, context.temp_allocator)
	world.veins = make([dynamic]Vein, context.temp_allocator)
	world.vein_indices = make(map[Vein_Id]int, context.temp_allocator)
	world.column_veins = make(map[Chunk_Column][dynamic]Vein_Id, context.temp_allocator)
	world.outcrop_cells = make(map[World_Coordinate]Vein_Id, context.temp_allocator)
	world.spent_outcrops = make([dynamic]World_Coordinate, context.temp_allocator)
	world.entities.belt_network.allocator = context.temp_allocator
	for coordinate in coordinates {
		chunk := new(Chunk, context.temp_allocator)
		chunk.coordinate = coordinate
		world.chunks[coordinate] = chunk
	}
	return world
}

@(test)
test_world_set_block_marks_border_neighbours_dirty :: proc(t: ^testing.T) {
	world := make_test_world({{0, 0, 0}, {-1, 0, 0}, {1, 0, 0}, {0, 0, -1}})
	testing.expect(t, world_set_block(&world, {5, 5, 5}, Block_Id(1)))
	testing.expect(t, world.chunks[{0, 0, 0}].dirty)
	testing.expect(t, !world.chunks[{-1, 0, 0}].dirty)
	testing.expect_value(t, world_get_block(&world, {5, 5, 5}), Block_Id(1))

	world.chunks[{0, 0, 0}].dirty = false
	testing.expect(t, world_set_block(&world, {0, 7, 0}, Block_Id(2)))
	testing.expect(t, world.chunks[{0, 0, 0}].dirty)
	testing.expect(t, world.chunks[{-1, 0, 0}].dirty)
	testing.expect(t, world.chunks[{0, 0, -1}].dirty)
	testing.expect(t, !world.chunks[{1, 0, 0}].dirty)
}

@(test)
test_world_missing_chunk_reads_air :: proc(t: ^testing.T) {
	world := make_test_world({{0, 0, 0}})
	testing.expect_value(t, world_get_block(&world, {-1, 0, 0}), AIR_BLOCK)
	testing.expect(t, !world_set_block(&world, {-1, 0, 0}, Block_Id(1)))
}

// An edit at a chunk corner changes the meshes of all eight chunks around it.
@(test)
test_world_set_block_marks_corner_neighbours_dirty :: proc(t: ^testing.T) {
	world := make_test_world({{0, 0, 0}, {-1, -1, -1}, {-1, 0, 0}, {1, 1, 1}})
	testing.expect(t, world_set_block(&world, {0, 0, 0}, Block_Id(1)))
	testing.expect(t, world.chunks[{-1, -1, -1}].dirty)
	testing.expect(t, world.chunks[{-1, 0, 0}].dirty)
	testing.expect(t, !world.chunks[{1, 1, 1}].dirty)
	testing.expect_value(t, len(world.block_changes), 1)
	testing.expect_value(t, world.block_changes[0], Block_Change{position = {0, 0, 0}, previous = AIR_BLOCK})
}
