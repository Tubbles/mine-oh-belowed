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
	// The first quad is the negative x face, a side face: x along z, y
	// down from the chunk's top.
	testing.expect_value(t, part.texcoords[0], [2]f32{0, CHUNK_SIZE})
	testing.expect_value(t, part.texcoords[2], [2]f32{CHUNK_SIZE, 0})
	expected_origin := atlas_tile_origin(input.atlas, atlas_tile_index(TEST_STONE, .Side))
	testing.expect_value(t, part.tile_origins[0], expected_origin)
}

fill_chunk_light_levels :: proc(chunk: ^Chunk, sky: u8, block: Light_Color) {
	for &value in chunk.light {
		value = pack_light(sky, block)
	}
}

// block is the expected block light in the normals, 0 to 1 per channel.
expect_all_colours :: proc(t: ^testing.T, data: Chunk_Mesh_Data, expected: [4]u8, block: [3]f32 = {}) {
	for part in data.parts {
		testing.expect_value(t, len(part.normals), len(part.colors))
		for colour in part.colors {
			testing.expect_value(t, colour, expected)
		}
		for normal in part.normals {
			testing.expect_value(t, normal, block)
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
	expect_all_colours(t, dark, {0, 0, 255, 255}, f32(9 * LIGHT_COLOUR_SCALE) / 255)
}

// Coloured block light (work item 0072): each vertex carries the red,
// green and blue levels in its normal, averaged per channel like the sky
// light, and the vertex colour does not change with it.
@(test)
test_mesh_writes_block_light_channels :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {10, 10, 10}, TEST_STONE)
	fill_chunk_light_levels(chunk, 0, {15, 11, 6})
	data := mesh_chunk(test_mesh_input(chunk), context.temp_allocator)
	expect_all_colours(t, data, {0, 0, 255, 255}, {1, f32(11 * LIGHT_COLOUR_SCALE) / 255, f32(6 * LIGHT_COLOUR_SCALE) / 255})

	// Only the cell in front of the top face holds red light: each corner
	// averages it with three dark cells, the other channels stay dark.
	fill_chunk_light_levels(chunk, 0, 0)
	chunk.light[local_to_index({10, 11, 10})] = pack_light(0, {MAXIMUM_LIGHT, 0, 0})
	key := face_key(test_mesh_input(chunk), {10, 10, 10}, .Positive_Y)
	for corner in key.corners {
		testing.expect_value(t, corner, Vertex_Light{color = {0, 0, 255, 255}, block = {64, 0, 0}})
		testing.expect_value(t, block_light_normal(corner), [3]f32{64.0 / 255, 0, 0})
	}
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
		testing.expect_value(t, corner, Vertex_Light{color = {64, 0, 255, 255}})
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
	testing.expect_value(t, key.corners[0], Vertex_Light{color = {255, 0, 255, 255}})
	testing.expect_value(t, key.corners[2], Vertex_Light{color = {255, 0, 2 * OCCLUSION_COLOUR_SCALE, 255}})
	testing.expect_value(t, key.corners[3], Vertex_Light{color = {255, 0, 2 * OCCLUSION_COLOUR_SCALE, 255}})
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
	for position in data.water_parts[0].positions {
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

water_test_mesh_input :: proc(chunk: ^Chunk) -> Mesh_Input {
	registry := make_test_registry()
	return Mesh_Input{chunk = chunk, registry = registry, atlas = atlas_layout_for_block_count(len(registry.definitions))}
}

// Water on stone (work item 0065): the water's five faces go to the water
// parts with a tangent per vertex, the stone's six to the opaque parts,
// its top face against the water included.
@(test)
test_mesh_water_faces_go_to_the_water_parts :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	input := water_test_mesh_input(chunk)
	water := test_block(input.registry, "water")
	stone := test_block(input.registry, "stone")
	chunk_set_block(chunk, {4, 3, 4}, stone)
	chunk_set_block(chunk, {4, 4, 4}, water)
	data := mesh_chunk(input, context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6 + 5)
	testing.expect_value(t, len(data.parts), 1)
	testing.expect_value(t, len(data.water_parts), 1)
	opaque := data.parts[0]
	testing.expect_value(t, len(opaque.positions), 6 * QUAD_VERTEX_COUNT)
	testing.expect_value(t, len(opaque.tangents), 0)
	water_tile := atlas_tile_origin(input.atlas, atlas_tile_index(water, .Side))
	for origin in opaque.tile_origins {
		testing.expect(t, origin != water_tile)
	}
	stone_top := atlas_tile_origin(input.atlas, atlas_tile_index(stone, .Top))
	testing.expect(t, slice_contains(opaque.tile_origins[:], stone_top))
	surface := data.water_parts[0]
	testing.expect_value(t, len(surface.positions), 5 * QUAD_VERTEX_COUNT)
	testing.expect_value(t, len(surface.tangents), len(surface.positions))
	for position in surface.positions {
		testing.expect(t, position.y >= 4)
	}
}

slice_contains :: proc(values: [][2]f32, wanted: [2]f32) -> bool {
	for value in values {
		if value == wanted {
			return true
		}
	}
	return false
}

// A cell between a higher and a lower neighbour flows towards the lower
// one; a source and a cell level with its neighbours do not flow.
@(test)
test_mesh_water_flow_points_downhill :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	input := water_test_mesh_input(chunk)
	chunk_set_block(chunk, {3, 4, 4}, test_block(input.registry, "flowing_water_6"))
	chunk_set_block(chunk, {4, 4, 4}, test_block(input.registry, "flowing_water_5"))
	chunk_set_block(chunk, {5, 4, 4}, test_block(input.registry, "flowing_water_4"))
	sum := water_flow_sum(input, {4, 4, 4}, 5)
	testing.expect_value(t, sum, [2]i8{2, 0})
	testing.expect_value(t, water_flow_vector(sum), [2]f32{1, 0})
	// Across z the lower neighbour lies on the negative side.
	chunk_set_block(chunk, {4, 4, 3}, test_block(input.registry, "flowing_water_4"))
	diagonal := water_flow_vector(water_flow_sum(input, {4, 4, 4}, 5))
	testing.expect(t, diagonal.x > 0 && diagonal.y < 0)
	testing.expect(t, abs(diagonal.x * diagonal.x + diagonal.y * diagonal.y - 1) < 1e-5)
	testing.expect_value(t, water_flow_sum(input, {3, 4, 4}, WATER_SOURCE_LEVEL), [2]i8{})
	chunk_set_block(chunk, {3, 4, 4}, test_block(input.registry, "flowing_water_5"))
	chunk_set_block(chunk, {5, 4, 4}, test_block(input.registry, "flowing_water_5"))
	chunk_set_block(chunk, {4, 4, 3}, test_block(input.registry, "flowing_water_5"))
	testing.expect_value(t, water_flow_vector(water_flow_sum(input, {4, 4, 4}, 5)), [2]f32{})
	// Every vertex of the flowing cell's faces carries its flow.
	chunk_set_block(chunk, {5, 4, 4}, test_block(input.registry, "flowing_water_4"))
	data := mesh_chunk(input, context.temp_allocator)
	flowing := 0
	for part in data.water_parts {
		for tangent in part.tangents {
			if tangent.x == 1 && tangent.y == 0 {
				flowing += 1
			}
		}
	}
	testing.expect(t, flowing >= QUAD_VERTEX_COUNT)
}

// A vertex next to stone is at the shore, a vertex in open water is not,
// and the mesher writes it into the tangent's third component.
@(test)
test_mesh_water_shore_next_to_stone :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	input := water_test_mesh_input(chunk)
	water := test_block(input.registry, "water")
	chunk_set_block(chunk, {4, 4, 4}, water)
	chunk_set_block(chunk, {5, 4, 4}, test_block(input.registry, "stone"))
	testing.expect(t, water_vertex_shore(input, {4, 4, 4}, {1, 1}))
	testing.expect(t, water_vertex_shore(input, {4, 4, 4}, {1, -1}))
	testing.expect(t, !water_vertex_shore(input, {4, 4, 4}, {-1, 1}))
	data := mesh_chunk(input, context.temp_allocator)
	for position, index in data.water_parts[0].positions {
		expected: f32 = position.x == 5 ? 1 : 0
		testing.expectf(t, data.water_parts[0].tangents[index].z == expected, "vertex %v has shore %v", position, data.water_parts[0].tangents[index].z)
	}
	// Open water: a pond of three by three sources, its middle far from
	// the stone.
	open := new(Chunk, context.temp_allocator)
	for z in i32(10) ..= 12 {
		for x in i32(10) ..= 12 {
			chunk_set_block(open, {x, 10, z}, water)
		}
	}
	open_input := water_test_mesh_input(open)
	for signs in corner_signs {
		testing.expect(t, !water_vertex_shore(open_input, {11, 10, 11}, signs))
	}
}

// The corners of a face in quad_corners order point from the cell's
// centre the way face_corner_horizontal_signs says.
@(test)
test_mesh_face_corner_horizontal_signs :: proc(t: ^testing.T) {
	rectangle := Face_Rectangle{u = 4, v = 4, width = 1, height = 1}
	for direction in Direction {
		for corner, index in quad_corners(direction, 4, rectangle) {
			signs := face_corner_horizontal_signs(direction, index)
			testing.expect_value(t, [2]i32{corner.x > 4.5 ? 1 : -1, corner.z > 4.5 ? 1 : -1}, signs)
		}
	}
}

// A 2 by 3 rectangle at the chunk corner, texcoords in quad_corners
// order by face axis. Side faces (x and z) have y 0 at the top of the
// face and the face's height at the bottom, x along the horizontal axis
// (z for faces along x, x for faces along z); top and bottom faces x
// along x and y along z. Both directions of an axis map alike.
@(test)
test_face_texcoord_per_direction :: proc(t: ^testing.T) {
	expected := [3][4][2]f32 {
		{{0, 2}, {0, 0}, {3, 0}, {3, 2}},
		{{0, 0}, {0, 2}, {3, 2}, {3, 0}},
		{{0, 3}, {2, 3}, {2, 0}, {0, 0}},
	}
	rectangle := Face_Rectangle{width = 2, height = 3}
	for direction in Direction {
		corners := quad_corners(direction, 0, rectangle)
		for corner, index in corners {
			texcoord := face_texcoord(direction, corner, corners[0], corners[2])
			testing.expectf(t, texcoord == expected[direction_axis(direction)][index], "%v corner %d: %v", direction, index, texcoord)
		}
	}
}

// A slab's side shows the lower half of its tile (y 0.5 at its top, 1 at
// the bottom) and a cross quad stands upright, y 0 at its top.
@(test)
test_shaped_quad_texcoords_upright :: proc(t: ^testing.T) {
	slab := Box{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}}
	for direction in ([4]Direction{.Negative_X, .Positive_X, .Negative_Z, .Positive_Z}) {
		corners := box_face_corners(slab, direction)
		texcoords := shaped_quad_texcoords(corners)
		for corner, index in corners {
			testing.expect_value(t, texcoords[index].y, corner.y == 0.5 ? f32(0.5) : f32(1))
		}
	}
	cross := cross_quads()
	for quad in cross.quads[:cross.count] {
		texcoords := shaped_quad_texcoords(quad.corners)
		for corner, index in quad.corners {
			testing.expect_value(t, texcoords[index], [2]f32{corner.z, 1 - corner.y})
		}
	}
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
	// texcoord y down the block like a cube face, over the lower half.
	part := data.parts[0]
	lowest_texcoord, highest_texcoord: f32 = 1, 0
	for quad := 6 * QUAD_VERTEX_COUNT; quad < len(part.positions); quad += QUAD_VERTEX_COUNT {
		if part.positions[quad].z != 5 || part.positions[quad + 2].z != 5 {
			continue
		}
		for index in quad ..< quad + QUAD_VERTEX_COUNT {
			lowest_texcoord = min(lowest_texcoord, part.texcoords[index].y)
			highest_texcoord = max(highest_texcoord, part.texcoords[index].y)
		}
	}
	testing.expect_value(t, lowest_texcoord, f32(0.5))
	testing.expect_value(t, highest_texcoord, f32(1))
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

// The orientation flag (work item 0088): the side faces of a block with
// keep_orientation carry KEEP_ORIENTATION_GREEN in every vertex, its top
// and bottom and every face of other blocks 0; a post's sides alike.
@(test)
test_mesh_marks_the_faces_that_keep_orientation :: proc(t: ^testing.T) {
	file, error := parse_blocks_file(transmute([]byte)string(`blocks = [{id = "air"} {id = "stone", solid = true} {id = "log", solid = true, keep_orientation = true} {id = "torch", shape = "post", keep_orientation = true}]`), context.temp_allocator)
	testing.expect_value(t, error, nil)
	registry := Block_Registry{definitions = file.blocks}
	chunk := new(Chunk, context.temp_allocator)
	fill_chunk_light_levels(chunk, MAXIMUM_LIGHT, 0)
	chunk_set_block(chunk, {2, 2, 2}, Block_Id(1))
	chunk_set_block(chunk, {10, 10, 10}, Block_Id(2))
	chunk_set_block(chunk, {6, 6, 6}, Block_Id(3))
	data := mesh_chunk(Mesh_Input{chunk = chunk, registry = registry, atlas = atlas_layout_for_block_count(len(registry.definitions))}, context.temp_allocator)
	testing.expect_value(t, data.quad_count, 6 + 6 + 6)
	kept := 0
	for part in data.parts {
		for quad := 0; quad < len(part.positions); quad += QUAD_VERTEX_COUNT {
			corners := part.positions[quad:quad + QUAD_VERTEX_COUNT]
			flat := corners[0].y == corners[1].y && corners[0].y == corners[2].y
			flagged := corners[0].x >= 6 && !flat
			expected := u8(flagged ? KEEP_ORIENTATION_GREEN : 0)
			for colour in part.colors[quad:quad + QUAD_VERTEX_COUNT] {
				testing.expectf(t, colour.g == expected, "quad at %v has green %d", corners[0], colour.g)
			}
			kept += int(flagged)
		}
	}
	// Four sides of the log and four of the post.
	testing.expect_value(t, kept, 8)
}
