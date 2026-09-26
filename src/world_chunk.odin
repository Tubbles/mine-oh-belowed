package game

CHUNK_SIZE :: 32
CHUNK_BLOCK_COUNT :: CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

// Chunk position in chunk units: world block position floor divided by CHUNK_SIZE.
Chunk_Coordinate :: distinct [3]i32
// Block position in the world, one unit per block.
World_Coordinate :: distinct [3]i32
// Block position inside a chunk, each component 0 to CHUNK_SIZE - 1.
Local_Coordinate :: distinct [3]i32

// Light is unused until work item 0008 but lives here now so that the
// layout does not change when it arrives.
Chunk :: struct {
	coordinate: Chunk_Coordinate,
	blocks:     [CHUNK_BLOCK_COUNT]Block_Id,
	light:      [CHUNK_BLOCK_COUNT]u8,
	dirty:      bool,
}

// Chunks are heap allocated and referenced by pointer, so growing the map
// never moves a 96 KiB chunk and pointers held across a frame stay valid.
World :: struct {
	chunks: map[Chunk_Coordinate]^Chunk,
}

Direction :: enum u8 {
	Negative_X,
	Positive_X,
	Negative_Y,
	Positive_Y,
	Negative_Z,
	Positive_Z,
}

@(rodata)
direction_offsets := [Direction][3]i32 {
	.Negative_X = {-1, 0, 0},
	.Positive_X = {1, 0, 0},
	.Negative_Y = {0, -1, 0},
	.Positive_Y = {0, 1, 0},
	.Negative_Z = {0, 0, -1},
	.Positive_Z = {0, 0, 1},
}

floor_divide :: proc(value, divisor: i32) -> i32 {
	return (value - value %% divisor) / divisor
}

world_to_chunk_coordinate :: proc(position: World_Coordinate) -> Chunk_Coordinate {
	return {floor_divide(position.x, CHUNK_SIZE), floor_divide(position.y, CHUNK_SIZE), floor_divide(position.z, CHUNK_SIZE)}
}

world_to_local_coordinate :: proc(position: World_Coordinate) -> Local_Coordinate {
	return {position.x %% CHUNK_SIZE, position.y %% CHUNK_SIZE, position.z %% CHUNK_SIZE}
}

chunk_origin :: proc(coordinate: Chunk_Coordinate) -> World_Coordinate {
	return World_Coordinate(coordinate * CHUNK_SIZE)
}

local_to_world_coordinate :: proc(coordinate: Chunk_Coordinate, local: Local_Coordinate) -> World_Coordinate {
	return chunk_origin(coordinate) + World_Coordinate(local)
}

local_in_bounds :: proc(local: Local_Coordinate) -> bool {
	return local.x >= 0 && local.x < CHUNK_SIZE && local.y >= 0 && local.y < CHUNK_SIZE && local.z >= 0 && local.z < CHUNK_SIZE
}

// Layout is x fastest, then z, then y, so a horizontal layer is contiguous.
local_to_index :: proc(local: Local_Coordinate) -> int {
	return int(local.x) + CHUNK_SIZE * (int(local.z) + CHUNK_SIZE * int(local.y))
}

index_to_local :: proc(index: int) -> Local_Coordinate {
	return {i32(index % CHUNK_SIZE), i32(index / (CHUNK_SIZE * CHUNK_SIZE)), i32(index / CHUNK_SIZE % CHUNK_SIZE)}
}

chunk_get_block :: proc(chunk: ^Chunk, local: Local_Coordinate) -> Block_Id {
	return chunk.blocks[local_to_index(local)]
}

chunk_set_block :: proc(chunk: ^Chunk, local: Local_Coordinate, block: Block_Id) {
	chunk.blocks[local_to_index(local)] = block
	chunk.dirty = true
}

// Missing chunks read as air.
world_get_block :: proc(world: ^World, position: World_Coordinate) -> Block_Id {
	chunk := world.chunks[world_to_chunk_coordinate(position)] or_else nil
	if chunk == nil {
		return AIR_BLOCK
	}
	return chunk_get_block(chunk, world_to_local_coordinate(position))
}

// Sets a block in a loaded chunk and marks every chunk whose mesh can see
// the change dirty: the owner, and the neighbour across each border the
// block touches. Returns false when the chunk is not loaded.
world_set_block :: proc(world: ^World, position: World_Coordinate, block: Block_Id) -> bool {
	coordinate := world_to_chunk_coordinate(position)
	chunk := world.chunks[coordinate] or_else nil
	if chunk == nil {
		return false
	}
	local := world_to_local_coordinate(position)
	chunk_set_block(chunk, local, block)
	for direction in Direction {
		if !local_in_bounds(local + Local_Coordinate(direction_offsets[direction])) {
			mark_chunk_dirty(world, coordinate + Chunk_Coordinate(direction_offsets[direction]))
		}
	}
	return true
}

mark_chunk_dirty :: proc(world: ^World, coordinate: Chunk_Coordinate) {
	if chunk := world.chunks[coordinate] or_else nil; chunk != nil {
		chunk.dirty = true
	}
}

// New chunks start dirty so that the renderer meshes them once.
world_create_chunk :: proc(world: ^World, coordinate: Chunk_Coordinate) -> ^Chunk {
	chunk := new(Chunk)
	chunk.coordinate = coordinate
	chunk.dirty = true
	world.chunks[coordinate] = chunk
	return chunk
}

destroy_world :: proc(world: ^World) {
	for _, chunk in world.chunks {
		free(chunk)
	}
	delete(world.chunks)
}

// The six face adjacent chunks, nil where not loaded.
chunk_neighbours :: proc(world: ^World, coordinate: Chunk_Coordinate) -> [Direction]^Chunk {
	neighbours: [Direction]^Chunk
	for direction in Direction {
		neighbours[direction] = world.chunks[coordinate + Chunk_Coordinate(direction_offsets[direction])] or_else nil
	}
	return neighbours
}
