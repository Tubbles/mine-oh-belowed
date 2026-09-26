package game

import "base:runtime"

// A generated chunk and the veins whose footprint overlaps its chunk
// column. The main thread registers the veins when it inserts the chunk.
Generated_Chunk :: struct {
	chunk: ^Chunk,
	veins: [dynamic]Vein,
}

// The whole generation of one chunk: a pure function of the generator (its
// seed and tables) and the chunk coordinate. Safe on any thread.
generate_chunk_blocks :: proc(generator: ^Generator, chunk: ^Chunk) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	origin := chunk_origin(chunk.coordinate)
	if origin.y > GENERATION_CEILING {
		return
	}
	if origin.y + CHUNK_SIZE <= CAVE_FLOOR {
		fill_chunk_with(chunk, generator.blocks.deep_stone)
		return
	}
	columns := new(Column_Grid, context.temp_allocator)
	caves := new(Cave_Grid, context.temp_allocator)
	underground := chunk_is_underground(chunk.coordinate)
	if underground {
		fill_underground_column_grid(columns)
	} else {
		sample_column_grid(generator, chunk.coordinate, columns)
	}
	has_caves := chunk_needs_caves(chunk.coordinate)
	if has_caves {
		sample_cave_grid(generator.seeds[.Caves], chunk.coordinate, caves)
	}
	fill_terrain(chunk, Terrain_Input{generator = generator, columns = columns, caves = caves, has_caves = has_caves})
	if underground {
		return
	}
	minimum := [2]i32{origin.x, origin.z} - FEATURE_REACH
	nearby_veins := veins_near_box(generator, minimum, minimum + CHUNK_SIZE - 1 + 2 * FEATURE_REACH, context.temp_allocator)
	apply_outcrops(generator, chunk, columns, nearby_veins[:])
	apply_features(generator, chunk, nearby_veins[:])
}

// New chunks start dirty so that they are meshed once.
generate_chunk :: proc(generator: ^Generator, coordinate: Chunk_Coordinate, allocator := context.allocator) -> Generated_Chunk {
	chunk := new(Chunk, allocator)
	chunk.coordinate = coordinate
	chunk.dirty = true
	generate_chunk_blocks(generator, chunk)
	return Generated_Chunk{chunk = chunk, veins = column_veins(generator, chunk_column_of(coordinate), allocator)}
}
