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

// The shell around chunk from the given neighbour chunks, by coordinate.
border_from_chunks :: proc(chunk: ^Chunk, neighbours: ..^Chunk) -> ^Chunk_Border {
	world: World
	world.chunks = make(map[Chunk_Coordinate]^Chunk, context.temp_allocator)
	world.chunks[chunk.coordinate] = chunk
	for neighbour in neighbours {
		world.chunks[neighbour.coordinate] = neighbour
	}
	return gather_chunk_border(&world, chunk.coordinate, context.temp_allocator)
}

make_test_chunk :: proc(coordinate: Chunk_Coordinate) -> ^Chunk {
	chunk := new(Chunk, context.temp_allocator)
	chunk.coordinate = coordinate
	return chunk
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
	chunk := make_test_chunk({0, 0, 0})
	fill_chunk(chunk, TEST_STONE)
	neighbours: [len(Direction)]^Chunk
	for direction in Direction {
		neighbours[direction] = make_test_chunk(Chunk_Coordinate(direction_offsets[direction]))
		fill_chunk(neighbours[direction], TEST_DIRT)
	}
	input := test_mesh_input(chunk)
	input.border = border_from_chunks(chunk, ..neighbours[:])
	testing.expect_value(t, mesh_quad_count(input), 0)
}

@(test)
test_mesh_culls_against_neighbour_chunk_block :: proc(t: ^testing.T) {
	chunk := make_test_chunk({0, 0, 0})
	chunk_set_block(chunk, {31, 0, 5}, TEST_STONE)
	neighbour := make_test_chunk({1, 0, 0})
	input := test_mesh_input(chunk)
	input.border = border_from_chunks(chunk, neighbour)
	testing.expect_value(t, mesh_quad_count(input), 6)
	chunk_set_block(neighbour, {0, 0, 5}, TEST_DIRT)
	input.border = border_from_chunks(chunk, neighbour)
	testing.expect_value(t, mesh_quad_count(input), 5)
	// The block below across the lower border is not adjacent to this one.
	below := make_test_chunk({0, -1, 0})
	chunk_set_block(below, {30, 31, 5}, TEST_DIRT)
	input.border = border_from_chunks(chunk, neighbour, below)
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

fill_chunk_light_levels :: proc(chunk: ^Chunk, sky, block: u8) {
	for &value in chunk.light {
		value = pack_light(sky, block)
	}
}

expect_all_colours :: proc(t: ^testing.T, data: Chunk_Mesh_Data, expected: Vertex_Light) {
	for part in data.parts {
		for colour in part.colors {
			testing.expect_value(t, colour, expected)
		}
	}
}

// Nothing solid around the block: every vertex carries the light of the
// cells in front of it and no occlusion.
@(test)
test_mesh_writes_light_of_lit_and_unlit_faces :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {10, 10, 10}, TEST_STONE)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	lit := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	testing.expect_value(t, lit.quad_count, 6)
	expect_all_colours(t, lit, {255, 0, 255, 255})

	fill_chunk_light_levels(chunk, 0, 9)
	dark := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	expect_all_colours(t, dark, {0, 9 * LIGHT_COLOUR_SCALE, 255, 255})
}

// Only the cell in front of the top face is lit: each corner averages it
// with three dark cells.
@(test)
test_mesh_vertex_light_averages_cells :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {10, 10, 10}, TEST_STONE)
	chunk.light[local_to_index({10, 11, 10})] = pack_light(MAXIMUM_LIGHT, 0)
	key := face_key(test_mesh_input(chunk), {10, 10, 10}, .Positive_Y)
	for corner in key.corners {
		testing.expect_value(t, corner, Vertex_Light{64, 0, 255, 255})
	}
}

// A solid block beside the front cell darkens the two corners next to it,
// and the face no longer merges with its neighbour.
@(test)
test_mesh_ambient_occlusion_darkens_corners :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	chunk_set_block(chunk, {10, 10, 10}, TEST_STONE)
	chunk_set_block(chunk, {10, 10, 11}, TEST_STONE)
	chunk_set_block(chunk, {11, 11, 10}, TEST_STONE)
	key := face_key(test_mesh_input(chunk), {10, 10, 10}, .Positive_Y)
	// The top face's u axis is z and its v axis is x, so corners 2 and 3
	// lie towards +x.
	testing.expect_value(t, key.corners[0], Vertex_Light{255, 0, 255, 255})
	testing.expect_value(t, key.corners[2], Vertex_Light{255, 0, 2 * OCCLUSION_COLOUR_SCALE, 255})
	testing.expect_value(t, key.corners[3], Vertex_Light{255, 0, 2 * OCCLUSION_COLOUR_SCALE, 255})
	testing.expect(t, !corners_uniform(key))
	// The block at z 11 alone would merge with this one into one top quad.
	data := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	top_faces := 0
	for part in data.parts {
		for index := 0; index < len(part.positions); index += QUAD_VERTEX_COUNT {
			if part.positions[index].y == 11 && part.positions[index + 2].y == 11 && part.positions[index].x == 10 && part.positions[index].z >= 10 {
				top_faces += 1
			}
		}
	}
	testing.expect_value(t, top_faces, 2)
}

// Flowing water with air above shows its level as a lower surface, and its
// side faces end at that surface.
@(test)
test_mesh_water_surface_follows_level :: proc(t: ^testing.T) {
	registry := make_test_registry()
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {4, 4, 4}, test_block(registry, "flowing_water_4"))
	input := Mesh_Input {
		chunk    = chunk,
		registry = registry,
		atlas    = atlas_layout_for_block_count(len(registry.definitions)),
	}
	data := mesh_chunk(input, context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6)
	highest: f32 = 0
	for position in data.parts[0].positions {
		highest = max(highest, position.y)
	}
	testing.expect_value(t, highest, f32(4.5))
}

// A higher water level next to a lower one closes the step with a side
// face, water of the same surface height does not.
@(test)
test_mesh_water_step_between_levels :: proc(t: ^testing.T) {
	registry := make_test_registry()
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {4, 4, 4}, test_block(registry, "flowing_water_6"))
	chunk_set_block(chunk, {5, 4, 4}, test_block(registry, "flowing_water_3"))
	input := Mesh_Input {
		chunk    = chunk,
		registry = registry,
	}
	testing.expect(t, face_is_visible(input, {4, 4, 4}, .Positive_X))
	testing.expect(t, !face_is_visible(input, {5, 4, 4}, .Negative_X))
	chunk_set_block(chunk, {4, 5, 4}, test_block(registry, "water"))
	chunk_set_block(chunk, {5, 5, 4}, test_block(registry, "water"))
	testing.expect(t, !face_is_visible(input, {4, 4, 4}, .Positive_X))
}

// Water on a chunk's top layer under different water in the chunk above:
// the top face is hidden without reading past the shell (a bounds check
// on a mesh worker once crashed the game here, mining under a lake).
@(test)
test_mesh_water_under_water_across_chunk_top :: proc(t: ^testing.T) {
	registry := make_test_registry()
	chunk := make_test_chunk({0, 0, 0})
	above := make_test_chunk({0, 1, 0})
	chunk_set_block(chunk, {4, CHUNK_SIZE - 1, 4}, test_block(registry, "flowing_water_4"))
	chunk_set_block(above, {4, 0, 4}, test_block(registry, "water"))
	input := Mesh_Input {
		chunk    = chunk,
		border   = border_from_chunks(chunk, above),
		registry = registry,
		atlas    = atlas_layout_for_block_count(len(registry.definitions)),
	}
	testing.expect(t, !face_is_visible(input, {4, CHUNK_SIZE - 1, 4}, .Positive_Y))
	data := mesh_chunk(input, context.temp_allocator)
	testing.expect_value(t, data.quad_count, 5)
}

shape_test_mesh_input :: proc(chunk: ^Chunk) -> Mesh_Input {
	registry := make_shape_test_registry()
	return Mesh_Input{chunk = chunk, registry = registry, atlas = atlas_layout_for_block_count(len(registry.definitions))}
}

// A slab against a stone block: the stone's face behind the slab shows
// (the slab covers half of it), the slab's face against the stone does
// not, and the slab's top lies half way up.
@(test)
test_mesh_slab_quads_and_the_cube_face_behind :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	chunk_set_block(chunk, {4, 4, 4}, SHAPE_TEST_STONE)
	chunk_set_block(chunk, {5, 4, 4}, SHAPE_TEST_SLAB)
	input := shape_test_mesh_input(chunk)
	testing.expect(t, face_is_visible(input, {4, 4, 4}, .Positive_X))
	testing.expect(t, !face_is_visible(input, {5, 4, 4}, .Positive_Y))
	data := mesh_chunk(input, context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6 + 5)
	highest_slab: f32 = 0
	for position in data.parts[0].positions {
		if position.x > 5 {
			highest_slab = max(highest_slab, position.y)
		}
	}
	testing.expect_value(t, highest_slab, f32(4.5))
	// The slab's quads come after the greedy ones. Its +z side runs its
	// texcoord y along the block's y like a cube face, over the lower half.
	part := data.parts[0]
	highest_texcoord: f32 = 0
	for quad := 6 * QUAD_VERTEX_COUNT; quad < len(part.positions); quad += QUAD_VERTEX_COUNT {
		if part.positions[quad].z != 5 || part.positions[quad + 2].z != 5 {
			continue
		}
		for index in quad ..< quad + QUAD_VERTEX_COUNT {
			highest_texcoord = max(highest_texcoord, part.texcoords[index].y)
		}
	}
	testing.expect_value(t, highest_texcoord, f32(0.5))
}

// Stairs of every rotation draw their ten quads in open air, the upper
// slab its six, with the base block's tiles.
@(test)
test_mesh_oriented_variants_use_the_base_tiles :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	chunk_set_block(chunk, {10, 10, 10}, SHAPE_TEST_STAIRS + 3)
	input := shape_test_mesh_input(chunk)
	data := mesh_chunk(input, context.temp_allocator)
	testing.expect_value(t, data.quad_count, 10)
	side := atlas_tile_origin(input.atlas, atlas_tile_index(SHAPE_TEST_STAIRS, .Side))
	top := atlas_tile_origin(input.atlas, atlas_tile_index(SHAPE_TEST_STAIRS, .Top))
	bottom := atlas_tile_origin(input.atlas, atlas_tile_index(SHAPE_TEST_STAIRS, .Bottom))
	for origin in data.parts[0].tile_origins {
		testing.expect(t, origin == side || origin == top || origin == bottom)
	}
	chunk_set_block(chunk, {10, 10, 10}, SHAPE_TEST_UPPER_SLAB)
	testing.expect_value(t, mesh_quad_count(input), 6)
}

// A torch is a post: six quads and a flame at its cell; a cross has four
// quads and no flame.
@(test)
test_mesh_torch_post_and_flame :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	chunk_set_block(chunk, {3, 2, 1}, SHAPE_TEST_TORCH)
	input := shape_test_mesh_input(chunk)
	data := mesh_chunk(input, context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6)
	testing.expect_value(t, len(data.flames), 1)
	testing.expect_value(t, data.flames[0], Local_Coordinate{3, 2, 1})
	chunk_set_block(chunk, {3, 2, 1}, SHAPE_TEST_TUFT)
	crossed := mesh_chunk(input, context.temp_allocator)
	testing.expect_value(t, crossed.quad_count, 4)
	testing.expect_value(t, len(crossed.flames), 0)
}

// A slab's bottom on stone is hidden like a cube face, while the stone's
// top under the slab still shows, since a slab is not opaque. The lit
// slab's quads carry the light of the open cells around them.
@(test)
test_mesh_slab_on_stone_hides_its_bottom_and_is_lit :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	chunk_set_block(chunk, {4, 3, 4}, SHAPE_TEST_STONE)
	chunk_set_block(chunk, {4, 4, 4}, SHAPE_TEST_SLAB)
	data := mesh_chunk(shape_test_mesh_input(chunk), context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6 + 5)
	part := data.parts[0]
	for index in 6 * QUAD_VERTEX_COUNT ..< len(part.positions) {
		testing.expect_value(t, part.colors[index].r, 255)
	}
}

// The wind sways the upper vertices of a cross and nothing else: the
// cross's feet, the stone's faces and the slab keep alpha 255 (work item
// 0063).
@(test)
test_mesh_marks_the_swaying_vertices :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	chunk_set_block(chunk, {4, 3, 4}, SHAPE_TEST_STONE)
	chunk_set_block(chunk, {4, 4, 4}, SHAPE_TEST_TUFT)
	chunk_set_block(chunk, {8, 4, 8}, SHAPE_TEST_SLAB)
	data := mesh_chunk(shape_test_mesh_input(chunk), context.temp_allocator)
	swaying := 0
	for part in data.parts {
		for position, index in part.positions {
			upper_tuft := position.x >= 4 && position.x <= 5 && position.z >= 4 && position.z <= 5 && position.y == 5
			alpha := part.colors[index].a
			if upper_tuft && alpha == SWAY_VERTEX_ALPHA {
				swaying += 1
				continue
			}
			testing.expectf(t, alpha == 255, "vertex %v has alpha %d", position, alpha)
		}
	}
	// Four quads with two upper vertices each.
	testing.expect_value(t, swaying, 8)
}
