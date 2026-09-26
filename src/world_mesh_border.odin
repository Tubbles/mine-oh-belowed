package game

// The one cell thick shell around a chunk, copied from its 26 neighbour
// chunks on the main thread when a mesh job is submitted. Face culling
// reads the face neighbours, smooth lighting and ambient occlusion also
// read the edge and corner neighbours, and the copy is much smaller than
// copying the neighbour chunks themselves.

BORDER_SIZE :: CHUNK_SIZE + 2
BORDER_CELL_COUNT :: BORDER_SIZE * BORDER_SIZE * BORDER_SIZE
// Cells of missing chunks read as air under open sky. Missing chunks only
// remain at the load boundary, which the fog hides.
MISSING_CHUNK_LIGHT :: u8(MAXIMUM_LIGHT << 4)

// Indexed by local coordinates from -1 to CHUNK_SIZE on every axis. Only
// the shell is filled, the inside is the chunk itself.
Chunk_Border :: struct {
	blocks: [BORDER_CELL_COUNT]Block_Id,
	light:  [BORDER_CELL_COUNT]u8,
}

border_index :: proc(local: Local_Coordinate) -> int {
	return int(local.x + 1) + BORDER_SIZE * (int(local.z + 1) + BORDER_SIZE * int(local.y + 1))
}

// The range of local coordinates on one axis that a neighbour at this
// chunk offset covers in the shell.
shell_range :: proc(offset: i32) -> (first, last: i32) {
	switch offset {
	case -1:
		return -1, -1
	case 1:
		return CHUNK_SIZE, CHUNK_SIZE
	}
	return 0, CHUNK_SIZE - 1
}

copy_shell_part :: proc(border: ^Chunk_Border, neighbour: ^Chunk, offset: [3]i32) {
	first, last: [3]i32
	for axis in 0 ..< 3 {
		first[axis], last[axis] = shell_range(offset[axis])
	}
	for y in first.y ..= last.y {
		for z in first.z ..= last.z {
			for x in first.x ..= last.x {
				local := Local_Coordinate{x, y, z}
				index := border_index(local)
				if neighbour == nil {
					border.blocks[index], border.light[index] = AIR_BLOCK, MISSING_CHUNK_LIGHT
					continue
				}
				source := local_to_index({x %% CHUNK_SIZE, y %% CHUNK_SIZE, z %% CHUNK_SIZE})
				border.blocks[index], border.light[index] = neighbour.blocks[source], neighbour.light[source]
			}
		}
	}
}

gather_chunk_border :: proc(world: ^World, coordinate: Chunk_Coordinate, allocator := context.allocator) -> ^Chunk_Border {
	border := new(Chunk_Border, allocator)
	for y in i32(-1) ..= 1 {
		for z in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				if x == 0 && y == 0 && z == 0 {
					continue
				}
				neighbour := world.chunks[coordinate + {x, y, z}] or_else nil
				copy_shell_part(border, neighbour, {x, y, z})
			}
		}
	}
	return border
}
