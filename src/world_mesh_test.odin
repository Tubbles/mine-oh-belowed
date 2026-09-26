package game

import "core:math/linalg"
import "core:testing"

TEST_STONE :: Block_Id(1)
TEST_DIRT :: Block_Id(2)

@(rodata)
test_block_definitions := [?]Block_Definition {
	{id = "air", solid = false},
	{id = "stone", solid = true},
	{id = "dirt", solid = true},
}

test_mesh_input :: proc(chunk: ^Chunk) -> Mesh_Input {
	return Mesh_Input {
		chunk = chunk,
		registry = Block_Registry{definitions = test_block_definitions[:]},
		atlas = atlas_layout_for_block_count(len(test_block_definitions)),
	}
}

fill_chunk :: proc(chunk: ^Chunk, block: Block_Id) {
	for &value in chunk.blocks {
		value = block
	}
}

mesh_quad_count :: proc(input: Mesh_Input) -> int {
	data := mesh_chunk(input, context.temp_allocator)
	return data.quad_count
}

@(test)
test_mesh_empty_chunk_has_no_quads :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	data := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	testing.expect_value(t, data.quad_count, 0)
	testing.expect_value(t, len(data.parts), 0)
}

@(test)
test_mesh_single_block :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {10, 10, 10}, TEST_STONE)
	data := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6)
	testing.expect_value(t, len(data.parts), 1)
	testing.expect_value(t, len(data.parts[0].positions), 24)
	testing.expect_value(t, len(data.parts[0].indices), 36)
}

@(test)
test_mesh_two_adjacent_blocks_of_different_types :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {10, 10, 10}, TEST_STONE)
	chunk_set_block(chunk, {11, 10, 10}, TEST_DIRT)
	testing.expect_value(t, mesh_quad_count(test_mesh_input(chunk)), 10)
}

// Same type: the four long sides merge, leaving 2 ends and 4 sides.
@(test)
test_mesh_two_adjacent_blocks_of_one_type_merge :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {10, 10, 10}, TEST_STONE)
	chunk_set_block(chunk, {11, 10, 10}, TEST_STONE)
	testing.expect_value(t, mesh_quad_count(test_mesh_input(chunk)), 6)
}

@(test)
test_mesh_full_chunk_without_neighbours :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk(chunk, TEST_STONE)
	data := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6)
	testing.expect_value(t, chunk_mesh_vertex_count(data), 24)
}

@(test)
test_mesh_full_chunk_surrounded_by_full_chunks :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk(chunk, TEST_STONE)
	neighbour := new(Chunk, context.temp_allocator)
	fill_chunk(neighbour, TEST_DIRT)
	input := test_mesh_input(chunk)
	for direction in Direction {
		input.neighbours[direction] = neighbour
	}
	testing.expect_value(t, mesh_quad_count(input), 0)
}

@(test)
test_mesh_culls_against_neighbour_chunk_block :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {31, 0, 5}, TEST_STONE)
	neighbour := new(Chunk, context.temp_allocator)
	input := test_mesh_input(chunk)
	input.neighbours[.Positive_X] = neighbour
	testing.expect_value(t, mesh_quad_count(input), 6)
	chunk_set_block(neighbour, {0, 0, 5}, TEST_DIRT)
	testing.expect_value(t, mesh_quad_count(input), 5)
	// The block below across the lower border is not adjacent to this one.
	below := new(Chunk, context.temp_allocator)
	chunk_set_block(below, {30, 31, 5}, TEST_DIRT)
	input.neighbours[.Negative_Y] = below
	testing.expect_value(t, mesh_quad_count(input), 5)
}

// raylib culls back faces with counter clockwise front faces, so every
// triangle's normal must point out of the block.
@(test)
test_mesh_winding_faces_outwards :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {3, 4, 5}, TEST_STONE)
	data := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	part := data.parts[0]
	block_center := [3]f32{3.5, 4.5, 5.5}
	for triangle in 0 ..< len(part.indices) / 3 {
		a := part.positions[part.indices[triangle * 3]]
		b := part.positions[part.indices[triangle * 3 + 1]]
		c := part.positions[part.indices[triangle * 3 + 2]]
		normal := linalg.cross(b - a, c - a)
		outwards := (a + b + c) / 3 - block_center
		testing.expectf(t, linalg.dot(normal, outwards) > 0, "triangle %d faces inwards", triangle)
	}
}

// A 3D checkerboard has no merges and no culling: the worst case, which
// must split into parts that stay inside the u16 index range.
@(test)
test_mesh_checkerboard_splits_into_parts :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	for index in 0 ..< CHUNK_BLOCK_COUNT {
		local := index_to_local(index)
		if (local.x + local.y + local.z) % 2 == 0 {
			chunk.blocks[index] = TEST_STONE
		}
	}
	data := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	testing.expect_value(t, data.quad_count, CHUNK_BLOCK_COUNT / 2 * 6)
	testing.expect_value(t, chunk_mesh_vertex_count(data), CHUNK_BLOCK_COUNT / 2 * 6 * QUAD_VERTEX_COUNT)
	testing.expect_value(t, len(data.parts), 6)
	for part in data.parts {
		testing.expect(t, len(part.positions) <= MESH_PART_VERTEX_LIMIT)
		for index in part.indices {
			if int(index) >= len(part.positions) {
				testing.fail_now(t, "index past the part's vertices")
			}
		}
	}
}

@(test)
test_mesh_texcoords_span_merged_quad :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk(chunk, TEST_STONE)
	input := test_mesh_input(chunk)
	data := mesh_chunk(input, context.temp_allocator)
	part := data.parts[0]
	testing.expect_value(t, part.texcoords[2], [2]f32{CHUNK_SIZE, CHUNK_SIZE})
	// The first quad is the negative x face, a side face.
	expected_origin := atlas_tile_origin(input.atlas, atlas_tile_index(TEST_STONE, .Side))
	testing.expect_value(t, part.tile_origins[0], expected_origin)
}
