package game

// Greedy mesher: turns a chunk and its six neighbours into plain vertex and
// index arrays. No raylib here, render_chunks.odin uploads the result.

// u16 indices address at most this many vertices, so a mesh part is closed
// and a new one started before it would exceed the limit.
MESH_PART_VERTEX_LIMIT :: 65536
QUAD_VERTEX_COUNT :: 4
QUAD_INDEX_COUNT :: 6
MESH_WHITE :: [4]u8{255, 255, 255, 255}

// Texcoords run in blocks across a merged quad (0 to width, 0 to height) so
// the shader can repeat the tile with fract(). tile_origins holds the atlas
// UV of the tile's corner, the same for all four vertices of a quad.
Mesh_Part :: struct {
	positions:    [dynamic][3]f32,
	texcoords:    [dynamic][2]f32,
	tile_origins: [dynamic][2]f32,
	colors:       [dynamic][4]u8,
	indices:      [dynamic]u16,
}

Chunk_Mesh_Data :: struct {
	parts:      [dynamic]Mesh_Part,
	quad_count: int,
}

Mesh_Input :: struct {
	chunk:      ^Chunk,
	neighbours: [Direction]^Chunk,
	registry:   Block_Registry,
	atlas:      Atlas_Layout,
}

Face_Rectangle :: struct {
	u, v:          int,
	width, height: int,
	block:         Block_Id,
}

Face_Mask :: [CHUNK_SIZE * CHUNK_SIZE]Block_Id

direction_axis :: proc(direction: Direction) -> int {
	return int(direction) / 2
}

direction_is_positive :: proc(direction: Direction) -> bool {
	return int(direction) % 2 == 1
}

direction_face_group :: proc(direction: Direction) -> Face_Group {
	#partial switch direction {
	case .Positive_Y:
		return .Top
	case .Negative_Y:
		return .Bottom
	}
	return .Side
}

// The direction of the chunk a just out of range local coordinate falls into.
out_of_range_direction :: proc(local: Local_Coordinate) -> Direction {
	switch {
	case local.x < 0:
		return .Negative_X
	case local.x >= CHUNK_SIZE:
		return .Positive_X
	case local.y < 0:
		return .Negative_Y
	case local.y >= CHUNK_SIZE:
		return .Positive_Y
	case local.z < 0:
		return .Negative_Z
	}
	return .Positive_Z
}

// Reads a block of the chunk or, one step past its border, of the
// neighbour. Missing neighbours read as air.
neighbourhood_block :: proc(input: Mesh_Input, local: Local_Coordinate) -> Block_Id {
	if local_in_bounds(local) {
		return chunk_get_block(input.chunk, local)
	}
	neighbour := input.neighbours[out_of_range_direction(local)]
	if neighbour == nil {
		return AIR_BLOCK
	}
	wrapped := Local_Coordinate{local.x %% CHUNK_SIZE, local.y %% CHUNK_SIZE, local.z %% CHUNK_SIZE}
	return chunk_get_block(neighbour, wrapped)
}

slice_local :: proc(axis, slice, u, v: int) -> Local_Coordinate {
	local: Local_Coordinate
	local[axis] = i32(slice)
	local[(axis + 1) % 3] = i32(u)
	local[(axis + 2) % 3] = i32(v)
	return local
}

// The block whose face is visible at this cell, or air when there is none.
visible_face :: proc(input: Mesh_Input, local: Local_Coordinate, direction: Direction) -> Block_Id {
	block := chunk_get_block(input.chunk, local)
	if !block_is_solid(input.registry, block) {
		return AIR_BLOCK
	}
	neighbour := neighbourhood_block(input, local + Local_Coordinate(direction_offsets[direction]))
	if block_is_solid(input.registry, neighbour) {
		return AIR_BLOCK
	}
	return block
}

build_face_mask :: proc(input: Mesh_Input, direction: Direction, slice: int) -> Face_Mask {
	mask: Face_Mask
	axis := direction_axis(direction)
	for v in 0 ..< CHUNK_SIZE {
		for u in 0 ..< CHUNK_SIZE {
			mask[u + v * CHUNK_SIZE] = visible_face(input, slice_local(axis, slice, u, v), direction)
		}
	}
	return mask
}

run_width :: proc(mask: ^Face_Mask, u, v: int, block: Block_Id) -> int {
	width := 1
	for u + width < CHUNK_SIZE && mask[u + width + v * CHUNK_SIZE] == block {
		width += 1
	}
	return width
}

row_matches :: proc(mask: ^Face_Mask, u, v, width: int, block: Block_Id) -> bool {
	for offset in 0 ..< width {
		if mask[u + offset + v * CHUNK_SIZE] != block {
			return false
		}
	}
	return true
}

clear_rectangle :: proc(mask: ^Face_Mask, rectangle: Face_Rectangle) {
	for v in rectangle.v ..< rectangle.v + rectangle.height {
		for u in rectangle.u ..< rectangle.u + rectangle.width {
			mask[u + v * CHUNK_SIZE] = AIR_BLOCK
		}
	}
}

// Grows each rectangle along u first, then along v while whole rows match.
// Consumes the mask.
greedy_rectangles :: proc(mask: ^Face_Mask, allocator := context.allocator) -> [dynamic]Face_Rectangle {
	rectangles := make([dynamic]Face_Rectangle, allocator)
	for v in 0 ..< CHUNK_SIZE {
		for u in 0 ..< CHUNK_SIZE {
			block := mask[u + v * CHUNK_SIZE]
			if block == AIR_BLOCK {
				continue
			}
			rectangle := Face_Rectangle{u = u, v = v, width = run_width(mask, u, v, block), height = 1, block = block}
			for v + rectangle.height < CHUNK_SIZE && row_matches(mask, u, v + rectangle.height, rectangle.width, block) {
				rectangle.height += 1
			}
			clear_rectangle(mask, rectangle)
			append(&rectangles, rectangle)
		}
	}
	return rectangles
}

// Corners in counter clockwise order seen from the side the face points to:
// u, v and the face axis form a right handed frame (axis + 1, axis + 2).
quad_corners :: proc(direction: Direction, slice: int, rectangle: Face_Rectangle) -> [4][3]f32 {
	axis := direction_axis(direction)
	u_axis := (axis + 1) % 3
	v_axis := (axis + 2) % 3
	corner: [3]f32
	corner[axis] = f32(slice + (direction_is_positive(direction) ? 1 : 0))
	corner[u_axis] = f32(rectangle.u)
	corner[v_axis] = f32(rectangle.v)
	u_step, v_step: [3]f32
	u_step[u_axis] = f32(rectangle.width)
	v_step[v_axis] = f32(rectangle.height)
	return {corner, corner + u_step, corner + u_step + v_step, corner + v_step}
}

current_part :: proc(data: ^Chunk_Mesh_Data, allocator := context.allocator) -> ^Mesh_Part {
	last := len(data.parts) - 1
	if last < 0 || len(data.parts[last].positions) + QUAD_VERTEX_COUNT > MESH_PART_VERTEX_LIMIT {
		append(&data.parts, make_mesh_part(allocator))
		last += 1
	}
	return &data.parts[last]
}

make_mesh_part :: proc(allocator := context.allocator) -> Mesh_Part {
	return Mesh_Part {
		positions = make([dynamic][3]f32, allocator),
		texcoords = make([dynamic][2]f32, allocator),
		tile_origins = make([dynamic][2]f32, allocator),
		colors = make([dynamic][4]u8, allocator),
		indices = make([dynamic]u16, allocator),
	}
}

@(rodata)
positive_quad_indices := [QUAD_INDEX_COUNT]u16{0, 1, 2, 0, 2, 3}
@(rodata)
negative_quad_indices := [QUAD_INDEX_COUNT]u16{0, 2, 1, 0, 3, 2}

append_quad :: proc(part: ^Mesh_Part, corners: [4][3]f32, rectangle: Face_Rectangle, tile_origin: [2]f32, positive: bool) {
	base := u16(len(part.positions))
	width, height := f32(rectangle.width), f32(rectangle.height)
	texcoords := [4][2]f32{{0, 0}, {width, 0}, {width, height}, {0, height}}
	for corner, index in corners {
		append(&part.positions, corner)
		append(&part.texcoords, texcoords[index])
		append(&part.tile_origins, tile_origin)
		append(&part.colors, MESH_WHITE)
	}
	order := positive ? positive_quad_indices : negative_quad_indices
	for index in order {
		append(&part.indices, base + index)
	}
}

mesh_slice :: proc(data: ^Chunk_Mesh_Data, input: Mesh_Input, direction: Direction, slice: int, allocator := context.allocator) {
	mask := build_face_mask(input, direction, slice)
	rectangles := greedy_rectangles(&mask, context.temp_allocator)
	group := direction_face_group(direction)
	for rectangle in rectangles {
		tile_origin := atlas_tile_origin(input.atlas, atlas_tile_index(rectangle.block, group))
		corners := quad_corners(direction, slice, rectangle)
		append_quad(current_part(data, allocator), corners, rectangle, tile_origin, direction_is_positive(direction))
		data.quad_count += 1
	}
}

// Positions are relative to the chunk origin.
mesh_chunk :: proc(input: Mesh_Input, allocator := context.allocator) -> Chunk_Mesh_Data {
	data := Chunk_Mesh_Data {
		parts = make([dynamic]Mesh_Part, allocator),
	}
	for direction in Direction {
		for slice in 0 ..< CHUNK_SIZE {
			mesh_slice(&data, input, direction, slice, allocator)
		}
	}
	return data
}

chunk_mesh_vertex_count :: proc(data: Chunk_Mesh_Data) -> int {
	total := 0
	for part in data.parts {
		total += len(part.positions)
	}
	return total
}

destroy_chunk_mesh_data :: proc(data: Chunk_Mesh_Data) {
	for part in data.parts {
		delete(part.positions)
		delete(part.texcoords)
		delete(part.tile_origins)
		delete(part.colors)
		delete(part.indices)
	}
	delete(data.parts)
}
