package game

import "core:slice"

// The explored map (work item 0038). Every chunk column loaded at least
// once is explored and keeps a surface record: per block column the
// topmost block and its height. Chunks carry the blocks while loaded; the
// record keeps what was seen once they unload, so the map can draw
// unloaded ground. Records are refreshed from the loaded chunks when a
// chunk of the column unloads and before a save. A scan only replaces a
// stored cell when it looked at least as high as the stored surface, so
// a player deep underground with the surface chunks unloaded does not
// turn the map into cave floors.

COLUMN_AREA :: CHUNK_SIZE * CHUNK_SIZE
// Chunk rows the surface scan probes, top first: above the tallest
// generated feature with room for building, down to the cave floor.
SURFACE_SCAN_TOP_CHUNK :: 7
SURFACE_SCAN_BOTTOM_CHUNK :: -5
SURFACE_SCAN_CHUNK_COUNT :: SURFACE_SCAN_TOP_CHUNK - SURFACE_SCAN_BOTTOM_CHUNK + 1
UNKNOWN_SURFACE_HEIGHT :: min(i16)

Surface_Cell :: struct {
	block:  Block_Id,
	height: i16,
}

// Indexed x fastest, then z, like a chunk layer.
Column_Surface :: [COLUMN_AREA]Surface_Cell

// One explored column as the save writes it.
Explored_Column :: struct {
	column:  Chunk_Column,
	surface: Column_Surface,
}

unknown_column_surface :: proc() -> Column_Surface {
	surface: Column_Surface
	for &cell in surface {
		cell = {block = AIR_BLOCK, height = UNKNOWN_SURFACE_HEIGHT}
	}
	return surface
}

surface_cell_is_known :: proc(cell: Surface_Cell) -> bool {
	return cell.height != UNKNOWN_SURFACE_HEIGHT
}

// Called for every inserted chunk.
mark_column_explored :: proc(explored: ^map[Chunk_Column]Column_Surface, column: Chunk_Column) {
	if column not_in explored {
		explored[column] = unknown_column_surface()
	}
}

// The loaded chunks of a column from the topmost down, stopping at the
// first gap, since nothing is known of an unloaded chunk in between.
column_chunks_top_down :: proc(world: ^World, column: Chunk_Column) -> (chunks: [SURFACE_SCAN_CHUNK_COUNT]^Chunk, count: int) {
	for y := i32(SURFACE_SCAN_TOP_CHUNK); y >= SURFACE_SCAN_BOTTOM_CHUNK; y -= 1 {
		chunk := world.chunks[Chunk_Coordinate{column.x, y, column.y}] or_else nil
		if chunk != nil {
			chunks[count] = chunk
			count += 1
		} else if count > 0 {
			return
		}
	}
	return
}

// The first block that is not air scanning down one block column.
scan_surface_cell :: proc(chunks: []^Chunk, local_x, local_z: i32) -> (cell: Surface_Cell, found: bool) {
	for chunk in chunks {
		for local_y := i32(CHUNK_SIZE - 1); local_y >= 0; local_y -= 1 {
			block := chunk.blocks[local_to_index({local_x, local_y, local_z})]
			if block != AIR_BLOCK {
				return {block = block, height = i16(chunk.coordinate.y * CHUNK_SIZE + local_y)}, true
			}
		}
	}
	return {}, false
}

// A scan that started below the stored surface cannot see it, so it
// keeps the stored cell.
merge_surface_cell :: proc(stored, scanned: Surface_Cell, found: bool, scan_top: i32) -> Surface_Cell {
	if !found {
		return stored
	}
	if !surface_cell_is_known(stored) || scan_top >= i32(stored.height) {
		return scanned
	}
	return stored
}

// The stored surface merged with what the loaded chunks show now.
scanned_column_surface :: proc(world: ^World, column: Chunk_Column, stored: Column_Surface) -> Column_Surface {
	chunks, count := column_chunks_top_down(world, column)
	if count == 0 {
		return stored
	}
	result := stored
	scan_top := chunks[0].coordinate.y * CHUNK_SIZE + CHUNK_SIZE - 1
	for &cell, index in result {
		scanned, found := scan_surface_cell(chunks[:count], i32(index % CHUNK_SIZE), i32(index / CHUNK_SIZE))
		cell = merge_surface_cell(cell, scanned, found, scan_top)
	}
	return result
}

refresh_column_surface :: proc(world: ^World, explored: ^map[Chunk_Column]Column_Surface, column: Chunk_Column) {
	if stored, found := explored[column]; found {
		explored[column] = scanned_column_surface(world, column, stored)
	}
}

// The distinct columns of the given chunks.
columns_of_chunks :: proc(coordinates: []Chunk_Coordinate) -> []Chunk_Column {
	columns := make([dynamic]Chunk_Column, 0, len(coordinates), context.temp_allocator)
	for coordinate in coordinates {
		column := chunk_column_of(coordinate)
		if !slice.contains(columns[:], column) {
			append(&columns, column)
		}
	}
	return columns[:]
}

// Before chunks unload, while the column's other chunks are still there.
refresh_unloading_surfaces :: proc(world: ^World, explored: ^map[Chunk_Column]Column_Surface, unloading: []Chunk_Coordinate) {
	for column in columns_of_chunks(unloading) {
		refresh_column_surface(world, explored, column)
	}
}

// Before a save, so the record holds what the loaded chunks show.
refresh_loaded_surfaces :: proc(world: ^World, explored: ^map[Chunk_Column]Column_Surface) {
	coordinates := make([dynamic]Chunk_Coordinate, 0, len(world.chunks), context.temp_allocator)
	for coordinate in world.chunks {
		append(&coordinates, coordinate)
	}
	refresh_unloading_surfaces(world, explored, coordinates[:])
}

// The surface of one block column: live for a loaded column (through the
// cache the map builds), else the record; unknown outside the explored set.
surface_at :: proc(surfaces: map[Chunk_Column]Column_Surface, x, z: i32) -> Surface_Cell {
	column := Chunk_Column{floor_divide(x, CHUNK_SIZE), floor_divide(z, CHUNK_SIZE)}
	// A copy of the map header, so the element is addressable without
	// copying the whole column.
	lookup := surfaces
	surface, found := &lookup[column]
	if !found {
		return {height = UNKNOWN_SURFACE_HEIGHT}
	}
	return surface[(z %% CHUNK_SIZE) * CHUNK_SIZE + x %% CHUNK_SIZE]
}

// Every explored column with its surface as the loaded chunks show it
// now, into surfaces (cleared first).
collect_explored_surfaces :: proc(world: ^World, explored: map[Chunk_Column]Column_Surface, surfaces: ^map[Chunk_Column]Column_Surface) {
	clear(surfaces)
	for column, stored in explored {
		surfaces[column] = scanned_column_surface(world, column, stored)
	}
}

explored_column_before :: proc(first, second: Explored_Column) -> bool {
	if first.column.y != second.column.y {
		return first.column.y < second.column.y
	}
	return first.column.x < second.column.x
}

// In column order, since map order is not stable.
sorted_explored_columns :: proc(explored: map[Chunk_Column]Column_Surface) -> []Explored_Column {
	columns := make([dynamic]Explored_Column, 0, len(explored), context.temp_allocator)
	for column, surface in explored {
		append(&columns, Explored_Column{column = column, surface = surface})
	}
	slice.sort_by(columns[:], explored_column_before)
	return columns[:]
}
