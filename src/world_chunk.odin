package game

CHUNK_SIZE :: 32
CHUNK_BLOCK_COUNT :: CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

// Chunk position in chunk units: world block position floor divided by CHUNK_SIZE.
Chunk_Coordinate :: distinct [3]i32
// Block position in the world, one unit per block.
World_Coordinate :: distinct [3]i32
// Block position inside a chunk, each component 0 to CHUNK_SIZE - 1.
Local_Coordinate :: distinct [3]i32

// light holds sky light in the high nibble and block light in the low
// nibble, 0 to MAXIMUM_LIGHT each (world_light.odin).
Chunk :: struct {
	coordinate: Chunk_Coordinate,
	blocks:     [CHUNK_BLOCK_COUNT]Block_Id,
	light:      [CHUNK_BLOCK_COUNT]u8,
	dirty:      bool,
	// Differs from what generation makes, so a save stores it (save_world.odin).
	modified:   bool,
}

// Chunks are heap allocated and referenced by pointer, so growing the map
// never moves a 96 KiB chunk and pointers held across a frame stay valid.
// Veins are entities registered once, when the first chunk of a chunk
// column they overlap is loaded, and they stay when chunks unload.
// Every world_set_block is recorded in block_changes, and the next
// simulation tick turns the changes into light and water updates.
// Entities keep their cells in entities.cells; those cells stay air here.
World :: struct {
	chunks:         map[Chunk_Coordinate]^Chunk,
	settings:       World_Settings,
	veins:          [dynamic]Vein,
	vein_indices:   map[Vein_Id]int,
	column_veins:   map[Chunk_Column][dynamic]Vein_Id,
	// Every outcrop cell of every loaded chunk so far (world_vein.odin).
	outcrop_cells:  map[World_Coordinate]Vein_Id,
	// Outcrop cells of exhausted veins still to turn into spent rock.
	spent_outcrops: [dynamic]World_Coordinate,
	// The schematic crate site of every region whose crate chunk loaded,
	// placed or not yet (schematic.odin). Kept after the crate is emptied,
	// so a reloaded chunk never places it again.
	crate_sites:    [dynamic]Crate_Site,
	block_changes:  [dynamic]Block_Change,
	lighting:       Lighting,
	// Block light sources that are entities, by cell (world_light.odin).
	entity_lights:  map[World_Coordinate]u8,
	water:          Water_Flow,
	// Leaves waiting to decay after a felling (tree_felling.odin).
	leaf_decay:     Leaf_Decay,
	entities:       Entities,
	// Modified chunks that are not loaded, serialised (world_serialize.odin):
	// unloaded ones and those read from a save. Streaming inserts these
	// blocks instead of generated ones (world_streaming.odin).
	saved_chunks:   map[Chunk_Coordinate][]byte,
	// Production statistics (statistics.odin), here like the entities so
	// that the player and entity ticks reach them through the world.
	statistics:     Statistics,
	// The queued technology and its progress (lab.odin), here so the lab
	// tick reaches it through the world.
	research:       Research_State,
	// Every chunk column loaded at least once, with the surface seen there
	// (world_explored.odin), and the prospecting records drawn on the map
	// (prospecting.odin). All saved.
	explored:              map[Chunk_Column]Column_Surface,
	assayed_veins:         [dynamic]Assayed_Vein,
	magnetometer_readings: [dynamic]Magnetometer_Reading,
	core_samples:          [dynamic]Core_Sample,
	seismic_shots:         [dynamic]Seismic_Shot,
	seismic_outlines:      [dynamic]Seismic_Outline,
	// Every rocket launched, oldest first (launch_pad.odin). Saved.
	shipments:             [dynamic]Shipment,
	// The open contracts, the venture credit and the catalogue orders
	// waiting for the next tick (venture.odin). Saved.
	contracts:             Contract_State,
	venture_credit:        u64,
	catalogue_orders:      [dynamic]Catalogue_Order,
}

Block_Change :: struct {
	position: World_Coordinate,
	previous: Block_Id,
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

// Sets a block in a loaded chunk, records the change for the next tick and
// marks every chunk whose mesh can see the change dirty. Returns false
// when the chunk is not loaded.
world_set_block :: proc(world: ^World, position: World_Coordinate, block: Block_Id) -> bool {
	chunk := world.chunks[world_to_chunk_coordinate(position)] or_else nil
	if chunk == nil {
		return false
	}
	local := world_to_local_coordinate(position)
	append(&world.block_changes, Block_Change{position = position, previous = chunk_get_block(chunk, local)})
	chunk_set_block(chunk, local, block)
	chunk.modified = true
	mark_chunks_around_cell_dirty(world, chunk, position)
	return true
}

// The neighbour chunk offset a local component reaches at the border: -1
// at 0, +1 at CHUNK_SIZE - 1, none inside.
border_reach :: proc(value: i32) -> (low, high: i32) {
	return value == 0 ? -1 : 0, value == CHUNK_SIZE - 1 ? 1 : 0
}

// Smooth lighting and ambient occlusion read the 26 cells around a face's
// front cell, so a change at a border cell also changes the meshes of the
// face, edge and corner neighbour chunks next to it.
mark_chunks_around_cell_dirty :: proc(world: ^World, chunk: ^Chunk, position: World_Coordinate) {
	chunk.dirty = true
	local := world_to_local_coordinate(position)
	low, high: [3]i32
	for axis in 0 ..< 3 {
		low[axis], high[axis] = border_reach(local[axis])
	}
	if low == {} && high == {} {
		return
	}
	for y in low.y ..= high.y {
		for z in low.z ..= high.z {
			for x in low.x ..= high.x {
				if x != 0 || y != 0 || z != 0 {
					mark_chunk_dirty(world, chunk.coordinate + {x, y, z})
				}
			}
		}
	}
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
	for _, bytes in world.saved_chunks {
		delete(bytes)
	}
	delete(world.saved_chunks)
	for _, ids in world.column_veins {
		delete(ids)
	}
	delete(world.column_veins)
	delete(world.vein_indices)
	delete(world.veins)
	delete(world.outcrop_cells)
	delete(world.spent_outcrops)
	delete(world.crate_sites)
	delete(world.explored)
	delete(world.assayed_veins)
	delete(world.magnetometer_readings)
	delete(world.core_samples)
	delete(world.seismic_shots)
	delete(world.seismic_outlines)
	delete(world.shipments)
	delete(world.catalogue_orders)
	delete(world.block_changes)
	destroy_lighting(&world.lighting)
	delete(world.entity_lights)
	destroy_water_flow(&world.water)
	destroy_leaf_decay(&world.leaf_decay)
	destroy_entities(&world.entities)
	destroy_statistics(world.statistics)
}

chunk_is_all_air :: proc(chunk: ^Chunk) -> bool {
	for block in chunk.blocks {
		if block != AIR_BLOCK {
			return false
		}
	}
	return true
}

// The six face adjacent chunks, nil where not loaded.
chunk_neighbours :: proc(world: ^World, coordinate: Chunk_Coordinate) -> [Direction]^Chunk {
	neighbours: [Direction]^Chunk
	for direction in Direction {
		neighbours[direction] = world.chunks[coordinate + Chunk_Coordinate(direction_offsets[direction])] or_else nil
	}
	return neighbours
}
