package game

// Greedy mesher: turns a chunk and the shell of cells around it into plain
// vertex and index arrays. No raylib here, render_chunks.odin uploads the
// result. The vertex colour carries light (packing in world_mesh_light.odin).

// u16 indices address at most this many vertices, so a mesh part is closed
// and a new one started before it would exceed the limit.
MESH_PART_VERTEX_LIMIT :: 65536
QUAD_VERTEX_COUNT :: 4
QUAD_INDEX_COUNT :: 6

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

// A nil border reads every cell outside the chunk as a missing chunk.
Mesh_Input :: struct {
	chunk:    ^Chunk,
	border:   ^Chunk_Border,
	registry: Block_Registry,
	atlas:    Atlas_Layout,
}

Mesh_Cell :: struct {
	block: Block_Id,
	light: u8,
}

// What a visible face looks like. Faces merge only when their keys are
// equal and the four corners of each are equal, so a merged quad never
// stretches a light gradient. The zero key (air) means no face.
Face_Key :: struct {
	block:   Block_Id,
	// Height of the face's top edge in eighths of a block, below
	// FULL_HEIGHT_EIGHTHS only for the surface of flowing water.
	height:  u8,
	corners: [4]Vertex_Light,
}

Face_Rectangle :: struct {
	u, v:          int,
	width, height: int,
	key:           Face_Key,
}

Face_Mask :: [CHUNK_SIZE * CHUNK_SIZE]Face_Key

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

// Reads a cell of the chunk or, one step past its border, of the shell.
neighbourhood_cell :: proc(input: Mesh_Input, local: Local_Coordinate) -> Mesh_Cell {
	if local_in_bounds(local) {
		index := local_to_index(local)
		return Mesh_Cell{block = input.chunk.blocks[index], light = input.chunk.light[index]}
	}
	if input.border == nil {
		return Mesh_Cell{block = AIR_BLOCK, light = MISSING_CHUNK_LIGHT}
	}
	index := border_index(local)
	return Mesh_Cell{block = input.border.blocks[index], light = input.border.light[index]}
}

neighbourhood_block :: proc(input: Mesh_Input, local: Local_Coordinate) -> Block_Id {
	return neighbourhood_cell(input, local).block
}

slice_local :: proc(axis, slice, u, v: int) -> Local_Coordinate {
	local: Local_Coordinate
	local[axis] = i32(slice)
	local[(axis + 1) % 3] = i32(u)
	local[(axis + 2) % 3] = i32(v)
	return local
}

// A face shows against any different block that is not solid, so solid
// blocks show against air, water and torches. Water shows against other
// water only sideways and only where the other surface is lower, so the
// step between two levels is closed.
face_is_visible :: proc(input: Mesh_Input, local: Local_Coordinate, direction: Direction) -> bool {
	block := chunk_get_block(input.chunk, local)
	if block == AIR_BLOCK {
		return false
	}
	neighbour_local := local + Local_Coordinate(direction_offsets[direction])
	neighbour := neighbourhood_block(input, neighbour_local)
	if neighbour == block || block_is_solid(input.registry, neighbour) {
		return false
	}
	if block_water_level(input.registry, block) > 0 && block_water_level(input.registry, neighbour) > 0 {
		lower := water_surface_eighths(input, neighbour_local, neighbour) < water_surface_eighths(input, local, block)
		return direction_axis(direction) != 1 && lower
	}
	return true
}

// Surface height of a cell in eighths of a block: a water level where no
// water lies above it, full for everything else.
water_surface_eighths :: proc(input: Mesh_Input, local: Local_Coordinate, block: Block_Id) -> u8 {
	level := block_water_level(input.registry, block)
	if level == 0 || block_water_level(input.registry, neighbourhood_block(input, local + {0, 1, 0})) > 0 {
		return FULL_HEIGHT_EIGHTHS
	}
	return u8(level)
}

face_key :: proc(input: Mesh_Input, local: Local_Coordinate, direction: Direction) -> Face_Key {
	if !face_is_visible(input, local, direction) {
		return {}
	}
	block := chunk_get_block(input.chunk, local)
	key := Face_Key {
		block  = block,
		height = direction == .Negative_Y ? FULL_HEIGHT_EIGHTHS : water_surface_eighths(input, local, block),
	}
	axis := direction_axis(direction)
	front := local + Local_Coordinate(direction_offsets[direction])
	for signs, corner in corner_signs {
		key.corners[corner] = vertex_light(input, front, (axis + 1) % 3, (axis + 2) % 3, signs)
	}
	return key
}

build_face_mask :: proc(input: Mesh_Input, direction: Direction, slice: int) -> Face_Mask {
	mask: Face_Mask
	axis := direction_axis(direction)
	for v in 0 ..< CHUNK_SIZE {
		for u in 0 ..< CHUNK_SIZE {
			mask[u + v * CHUNK_SIZE] = face_key(input, slice_local(axis, slice, u, v), direction)
		}
	}
	return mask
}

corners_uniform :: proc(key: Face_Key) -> bool {
	return key.corners[0] == key.corners[1] && key.corners[0] == key.corners[2] && key.corners[0] == key.corners[3]
}

run_width :: proc(mask: ^Face_Mask, u, v: int, key: Face_Key) -> int {
	if !corners_uniform(key) {
		return 1
	}
	width := 1
	for u + width < CHUNK_SIZE && mask[u + width + v * CHUNK_SIZE] == key {
		width += 1
	}
	return width
}

row_matches :: proc(mask: ^Face_Mask, u, v, width: int, key: Face_Key) -> bool {
	for offset in 0 ..< width {
		if mask[u + offset + v * CHUNK_SIZE] != key {
			return false
		}
	}
	return true
}

clear_rectangle :: proc(mask: ^Face_Mask, rectangle: Face_Rectangle) {
	for v in rectangle.v ..< rectangle.v + rectangle.height {
		for u in rectangle.u ..< rectangle.u + rectangle.width {
			mask[u + v * CHUNK_SIZE] = {}
		}
	}
}

// Grows each rectangle along u first, then along v while whole rows match.
// Consumes the mask.
greedy_rectangles :: proc(mask: ^Face_Mask, allocator := context.allocator) -> [dynamic]Face_Rectangle {
	rectangles := make([dynamic]Face_Rectangle, allocator)
	for v in 0 ..< CHUNK_SIZE {
		for u in 0 ..< CHUNK_SIZE {
			key := mask[u + v * CHUNK_SIZE]
			if key.block == AIR_BLOCK {
				continue
			}
			rectangle := Face_Rectangle{u = u, v = v, width = run_width(mask, u, v, key), height = 1, key = key}
			for corners_uniform(key) && v + rectangle.height < CHUNK_SIZE && row_matches(mask, u, v + rectangle.height, rectangle.width, key) {
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

// Moves the top edge of a face down to a water surface.
lower_top_edge :: proc(corners: ^[4][3]f32, height: u8) {
	top := max(corners[0].y, corners[1].y, corners[2].y, corners[3].y)
	for &corner in corners {
		if corner.y == top {
			corner.y = top - 1 + f32(height) / FULL_HEIGHT_EIGHTHS
		}
	}
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
		append(&part.colors, rectangle.key.corners[index])
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
		tile_origin := atlas_tile_origin(input.atlas, atlas_tile_index(rectangle.key.block, group))
		corners := quad_corners(direction, slice, rectangle)
		if rectangle.key.height < FULL_HEIGHT_EIGHTHS {
			lower_top_edge(&corners, rectangle.key.height)
		}
		append_quad(current_part(data, allocator), corners, rectangle, tile_origin, direction_is_positive(direction))
		data.quad_count += 1
	}
}

// Positions are relative to the chunk origin.
mesh_chunk :: proc(input: Mesh_Input, allocator := context.allocator) -> Chunk_Mesh_Data {
	data := Chunk_Mesh_Data {
		parts = make([dynamic]Mesh_Part, allocator),
	}
	// About half of the streamed chunks are sky.
	if chunk_is_all_air(input.chunk) {
		return data
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
