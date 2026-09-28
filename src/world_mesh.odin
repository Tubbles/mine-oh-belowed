package game

import "core:math/linalg"

// Greedy mesher: turns a chunk and the shell of cells around it into plain
// vertex and index arrays. No raylib here, render_chunks.odin uploads the
// result. The vertex colour carries light (packing in world_mesh_light.odin).
// Cubes merge into greedy rectangles; every other shape (slabs, stairs,
// torches) is meshed cell by cell from its quads (block_shape.odin) in a
// second pass, mesh_shaped_cells. Every face of a water block goes to
// the water parts, drawn by a transparent pass of their own (work item
// 0065, render_water.odin).

// u16 indices address at most this many vertices, so a mesh part is closed
// and a new one started before it would exceed the limit.
MESH_PART_VERTEX_LIMIT :: 65536
QUAD_VERTEX_COUNT :: 4
QUAD_INDEX_COUNT :: 6

// Texcoords run in blocks across a merged quad (0 to width, 0 to height) so
// the shader can repeat the tile with fract(). tile_origins holds the atlas
// UV of the tile's corner, the same for all four vertices of a quad.
// tangents is filled in water parts only: the cell's flow direction in x
// and z, the vertex's shore value, and 0 (water_tangent).
Mesh_Part :: struct {
	positions:    [dynamic][3]f32,
	texcoords:    [dynamic][2]f32,
	tile_origins: [dynamic][2]f32,
	colors:       [dynamic][4]u8,
	indices:      [dynamic]u16,
	tangents:     [dynamic][4]f32,
}

// flames holds the cells of light emitting posts (torches), where the
// renderer draws a flame. water_parts holds the faces of water blocks,
// parts everything else.
Chunk_Mesh_Data :: struct {
	parts:       [dynamic]Mesh_Part,
	water_parts: [dynamic]Mesh_Part,
	quad_count:  int,
	flames:      [dynamic]Local_Coordinate,
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
	// Water faces only: the cell's flow (water_flow_sum) and each corner's
	// shore value (water_vertex_shore).
	flow:    [2]i8,
	shore:   [4]bool,
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

// A cube's face shows against any different block that is not opaque, so
// solid cubes show against air, water, torches and the open part of a
// slab. Water shows against other water only sideways and only where the
// other surface is lower, so the step between two levels is closed.
// Blocks of other shapes have no greedy faces (mesh_shaped_cells).
face_is_visible :: proc(input: Mesh_Input, local: Local_Coordinate, direction: Direction) -> bool {
	block := chunk_get_block(input.chunk, local)
	if block == AIR_BLOCK || block_shape(input.registry, block) != .Cube {
		return false
	}
	neighbour_local := local + Local_Coordinate(direction_offsets[direction])
	neighbour := neighbourhood_block(input, neighbour_local)
	if neighbour == block || block_is_opaque(input.registry, neighbour) {
		return false
	}
	if block_water_level(input.registry, block) > 0 && block_water_level(input.registry, neighbour) > 0 {
		// Vertical faces are answered before any surface height is read: the
		// surface of a neighbour above the chunk's top layer would need the
		// cell above that, two steps out, past the shell.
		if direction_axis(direction) == 1 {
			return false
		}
		return water_surface_eighths(input, neighbour_local, neighbour) < water_surface_eighths(input, local, block)
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

// The flow of a water cell in x and z: over its four horizontal water
// neighbours, the level difference times the direction away from the
// higher of the two, which is the cell's level minus the neighbour's
// times the step towards the neighbour. It points downhill. Zero for a
// source, which only ripples, and for a cell level with its neighbours.
water_flow_sum :: proc(input: Mesh_Input, local: Local_Coordinate, level: int) -> [2]i8 {
	if level == WATER_SOURCE_LEVEL {
		return {}
	}
	sum: [2]int
	for direction in horizontal_directions {
		offset := direction_offsets[direction]
		neighbour_level := block_water_level(input.registry, neighbourhood_block(input, local + Local_Coordinate(offset)))
		if neighbour_level > 0 {
			sum += (level - neighbour_level) * [2]int{int(offset.x), int(offset.z)}
		}
	}
	return {i8(sum.x), i8(sum.y)}
}

// The flow sum as a unit vector, or zero.
water_flow_vector :: proc(sum: [2]i8) -> [2]f32 {
	vector := [2]f32{f32(sum.x), f32(sum.y)}
	length := linalg.length(vector)
	return length > 0 ? vector / length : {}
}

// Whether a water vertex lies at the shore: any of the four cells around
// its vertical edge in the water cell's layer is solid. signs point from
// the cell towards the vertex along x and z; the cell itself is water.
water_vertex_shore :: proc(input: Mesh_Input, local: Local_Coordinate, signs: [2]i32) -> bool {
	cells := [3]Local_Coordinate{local + {signs.x, 0, 0}, local + {0, 0, signs.y}, local + {signs.x, 0, signs.y}}
	for cell in cells {
		if block_is_solid(input.registry, neighbourhood_block(input, cell)) {
			return true
		}
	}
	return false
}

// The x and z signs from a cell's centre towards a corner of its face,
// corners in the order of quad_corners.
face_corner_horizontal_signs :: proc(direction: Direction, corner: int) -> [2]i32 {
	axis := direction_axis(direction)
	signs: [3]i32
	signs[axis] = direction_is_positive(direction) ? 1 : -1
	signs[(axis + 1) % 3] = corner_signs[corner][0]
	signs[(axis + 2) % 3] = corner_signs[corner][1]
	return {signs.x, signs.z}
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
	if level := block_water_level(input.registry, block); level > 0 {
		key.flow = water_flow_sum(input, local, level)
		for &shore, corner in key.shore {
			shore = water_vertex_shore(input, local, face_corner_horizontal_signs(direction, corner))
		}
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

// The shore values count as corners too: a merged water quad carries one.
corners_uniform :: proc(key: Face_Key) -> bool {
	return key.corners[0] == key.corners[1] && key.corners[0] == key.corners[2] && key.corners[0] == key.corners[3] && key.shore[0] == key.shore[1] && key.shore[0] == key.shore[2] && key.shore[0] == key.shore[3]
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

current_part :: proc(parts: ^[dynamic]Mesh_Part, allocator := context.allocator) -> ^Mesh_Part {
	last := len(parts) - 1
	if last < 0 || len(parts[last].positions) + QUAD_VERTEX_COUNT > MESH_PART_VERTEX_LIMIT {
		append(parts, make_mesh_part(allocator))
		last += 1
	}
	return &parts[last]
}

make_mesh_part :: proc(allocator := context.allocator) -> Mesh_Part {
	return Mesh_Part {
		positions = make([dynamic][3]f32, allocator),
		texcoords = make([dynamic][2]f32, allocator),
		tile_origins = make([dynamic][2]f32, allocator),
		colors = make([dynamic][4]u8, allocator),
		indices = make([dynamic]u16, allocator),
		tangents = make([dynamic][4]f32, allocator),
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

// What a water vertex tells the water shader (data/shaders/water.vs).
water_tangent :: proc(flow: [2]i8, shore: bool) -> [4]f32 {
	vector := water_flow_vector(flow)
	return {vector.x, vector.y, shore ? 1 : 0, 0}
}

// After append_quad, for the quad's four vertices.
append_water_tangents :: proc(part: ^Mesh_Part, key: Face_Key) {
	for shore in key.shore {
		append(&part.tangents, water_tangent(key.flow, shore))
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
		water := block_water_level(input.registry, rectangle.key.block) > 0
		part := current_part(water ? &data.water_parts : &data.parts, allocator)
		append_quad(part, corners, rectangle, tile_origin, direction_is_positive(direction))
		if water {
			append_water_tangents(part, rectangle.key)
		}
		data.quad_count += 1
	}
}

// The axis a shaped quad faces most along; a cross's diagonal quad takes x.
quad_facing_axis :: proc(corners: [4][3]f32) -> int {
	normal := linalg.cross(corners[1] - corners[0], corners[3] - corners[0])
	axis := 0
	for candidate in 1 ..< 3 {
		if abs(normal[candidate]) > abs(normal[axis]) {
			axis = candidate
		}
	}
	return axis
}

// The light of each corner of a shaped quad, smooth like a cube face: a
// quad on the cell's border reads the layer in front of it, a quad inside
// the cell the cell's own layer, towards the side of the cell the corner
// lies on.
shaped_quad_light :: proc(input: Mesh_Input, local: Local_Coordinate, quad: Shape_Quad) -> [4]Vertex_Light {
	axis := quad_facing_axis(quad.corners)
	front := local
	if border, found := quad.border.?; found {
		front += Local_Coordinate(direction_offsets[border])
	}
	u_axis, v_axis := (axis + 1) % 3, (axis + 2) % 3
	light: [4]Vertex_Light
	for corner, index in quad.corners {
		signs := [2]i32{corner[u_axis] >= 0.5 ? 1 : -1, corner[v_axis] >= 0.5 ? 1 : -1}
		light[index] = vertex_light(input, front, u_axis, v_axis, signs)
	}
	return light
}

// Texcoords as a cube face of the same axis has them, so a partial quad
// shows the part of the tile it covers (a slab side the lower half).
shaped_quad_texcoords :: proc(corners: [4][3]f32) -> [4][2]f32 {
	axis := quad_facing_axis(corners)
	u_axis, v_axis := (axis + 1) % 3, (axis + 2) % 3
	texcoords: [4][2]f32
	for corner, index in corners {
		texcoords[index] = {corner[u_axis], corner[v_axis]}
	}
	return texcoords
}

// Shape quads are counter clockwise seen from outside, so every one takes
// the positive order. sways marks the upper vertices for the wind.
append_shaped_quad :: proc(part: ^Mesh_Part, input: Mesh_Input, local: Local_Coordinate, quad: Shape_Quad, tile_origin: [2]f32, sways: bool) {
	base := u16(len(part.positions))
	origin := [3]f32{f32(local.x), f32(local.y), f32(local.z)}
	texcoords := shaped_quad_texcoords(quad.corners)
	light := shaped_quad_light(input, local, quad)
	for corner, index in quad.corners {
		append(&part.positions, origin + corner)
		append(&part.texcoords, texcoords[index])
		append(&part.tile_origins, tile_origin)
		append(&part.colors, sway_vertex_light(light[index], corner, sways))
	}
	for index in positive_quad_indices {
		append(&part.indices, base + index)
	}
}

// A border quad is hidden by an opaque neighbour.
shaped_quad_visible :: proc(input: Mesh_Input, local: Local_Coordinate, quad: Shape_Quad) -> bool {
	border, found := quad.border.?
	return !found || !block_is_opaque(input.registry, neighbourhood_block(input, local + Local_Coordinate(direction_offsets[border])))
}

// Variants draw their base block's tiles, which the texture files name.
mesh_shaped_cell :: proc(data: ^Chunk_Mesh_Data, input: Mesh_Input, local: Local_Coordinate, block: Block_Id, shape: Block_Shape, allocator := context.allocator) {
	quads := shape_quads(shape, block_orientation(input.registry, block))
	base := block_shape_base(input.registry, block)
	sways := block_sways(input.registry, block)
	for quad in quads.quads[:quads.count] {
		if !shaped_quad_visible(input, local, quad) {
			continue
		}
		tile_origin := atlas_tile_origin(input.atlas, atlas_tile_index(base, quad.group))
		append_shaped_quad(current_part(&data.parts, allocator), input, local, quad, tile_origin, sways)
		data.quad_count += 1
	}
	if shape == .Post && block_light_emission(input.registry, block) > 0 {
		append(&data.flames, local)
	}
}

// The second pass: every cell whose block is not a cube.
mesh_shaped_cells :: proc(data: ^Chunk_Mesh_Data, input: Mesh_Input, allocator := context.allocator) {
	for block, index in input.chunk.blocks {
		if shape := block_shape(input.registry, block); shape != .Cube {
			mesh_shaped_cell(data, input, index_to_local(index), block, shape, allocator)
		}
	}
}

// Positions are relative to the chunk origin.
mesh_chunk :: proc(input: Mesh_Input, allocator := context.allocator) -> Chunk_Mesh_Data {
	data := Chunk_Mesh_Data {
		parts       = make([dynamic]Mesh_Part, allocator),
		water_parts = make([dynamic]Mesh_Part, allocator),
		flames      = make([dynamic]Local_Coordinate, allocator),
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
	mesh_shaped_cells(&data, input, allocator)
	return data
}

chunk_mesh_vertex_count :: proc(data: Chunk_Mesh_Data) -> int {
	total := 0
	for part in data.parts {
		total += len(part.positions)
	}
	for part in data.water_parts {
		total += len(part.positions)
	}
	return total
}

destroy_mesh_parts :: proc(parts: [dynamic]Mesh_Part) {
	for part in parts {
		delete(part.positions)
		delete(part.texcoords)
		delete(part.tile_origins)
		delete(part.colors)
		delete(part.indices)
		delete(part.tangents)
	}
	delete(parts)
}

destroy_chunk_mesh_data :: proc(data: Chunk_Mesh_Data) {
	destroy_mesh_parts(data.parts)
	destroy_mesh_parts(data.water_parts)
	delete(data.flames)
}
