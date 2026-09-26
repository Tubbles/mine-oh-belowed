package game

// Initial sky light of one chunk from its own blocks, safe on a worker
// thread. A column open to the sky above the chunk gets full sky light down
// to its first opaque block, and the light then floods sideways and down
// inside the chunk. Light from neighbour chunks comes later on the main
// thread (seed_chunk_border_light), so the values here are never brighter
// than the final ones, only possibly darker near the borders.

COLUMN_COUNT :: CHUNK_SIZE * CHUNK_SIZE

// Per column (x + z * CHUNK_SIZE): whether nothing opaque lies above the
// chunk, so that the column receives full sky light at its top.
Open_Columns :: [COLUMN_COUNT]bool

column_index :: proc(x, z: i32) -> int {
	return int(x) + int(z) * CHUNK_SIZE
}

fill_chunk_light :: proc(chunk: ^Chunk, light: u8) {
	for &value in chunk.light {
		value = light
	}
}

chunk_is_open_sky :: proc(chunk: ^Chunk) -> bool {
	for light in chunk.light {
		if light != MISSING_CHUNK_LIGHT {
			return false
		}
	}
	return true
}

// Full sky light from the top of every open column down to its first
// opaque block.
light_open_columns :: proc(chunk: ^Chunk, registry: Block_Registry, open: ^Open_Columns) {
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			if !open[column_index(x, z)] {
				continue
			}
			for y := i32(CHUNK_SIZE - 1); y >= 0; y -= 1 {
				index := local_to_index({x, y, z})
				if block_is_opaque(registry, chunk.blocks[index]) {
					break
				}
				chunk.light[index] = with_light_level(chunk.light[index], .Sky, MAXIMUM_LIGHT)
			}
		}
	}
}

// Raises the chunk local neighbours of index from its light. Appends the
// raised ones to pending.
spread_sky_in_chunk :: proc(chunk: ^Chunk, registry: Block_Registry, index: int, pending: ^[dynamic]int) {
	local := index_to_local(index)
	level := light_level(chunk.light[index], .Sky)
	for direction in Direction {
		neighbour := local + Local_Coordinate(direction_offsets[direction])
		if !local_in_bounds(neighbour) {
			continue
		}
		neighbour_index := local_to_index(neighbour)
		spread := spread_level(.Sky, direction, level)
		if spread > light_level(chunk.light[neighbour_index], .Sky) && !block_is_opaque(registry, chunk.blocks[neighbour_index]) {
			chunk.light[neighbour_index] = with_light_level(chunk.light[neighbour_index], .Sky, spread)
			append(pending, neighbour_index)
		}
	}
}

// Only lit cells next to a darker cell that light can enter start the
// flood, which keeps open sky chunks cheap.
sky_light_can_spread :: proc(chunk: ^Chunk, registry: Block_Registry, index: int) -> bool {
	level := light_level(chunk.light[index], .Sky)
	if level <= 1 {
		return false
	}
	local := index_to_local(index)
	for direction in Direction {
		neighbour := local + Local_Coordinate(direction_offsets[direction])
		if !local_in_bounds(neighbour) {
			continue
		}
		neighbour_index := local_to_index(neighbour)
		if light_level(chunk.light[neighbour_index], .Sky) < spread_level(.Sky, direction, level) && !block_is_opaque(registry, chunk.blocks[neighbour_index]) {
			return true
		}
	}
	return false
}

fill_chunk_sky_light :: proc(chunk: ^Chunk, registry: Block_Registry, open: ^Open_Columns) {
	light_open_columns(chunk, registry, open)
	pending := make([dynamic]int, context.temp_allocator)
	for index in 0 ..< CHUNK_BLOCK_COUNT {
		if sky_light_can_spread(chunk, registry, index) {
			append(&pending, index)
		}
	}
	for len(pending) > 0 {
		spread_sky_in_chunk(chunk, registry, pop(&pending), &pending)
	}
}
