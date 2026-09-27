package game

import "base:runtime"

// A generated chunk, the veins whose footprint overlaps its chunk column,
// the outcrop cells inside the chunk and the schematic crate site whose
// crate cell it holds (none or one). The main thread registers the veins,
// the outcrop cells and the crate site when it inserts the chunk.
Generated_Chunk :: struct {
	chunk:    ^Chunk,
	veins:    [dynamic]Vein,
	outcrops: [dynamic]Outcrop_Cell,
	crates:   [dynamic]Crate_Site,
}

// The whole generation of one chunk: a pure function of the generator (its
// seed and tables) and the chunk coordinate. Safe on any thread. open, when
// given, receives the columns generation lit from the sky.
generate_chunk_blocks :: proc(generator: ^Generator, chunk: ^Chunk, outcrops: ^[dynamic]Outcrop_Cell, crates: ^[dynamic]Crate_Site, open_columns: ^Open_Columns = nil) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	origin := chunk_origin(chunk.coordinate)
	if origin.y > GENERATION_CEILING {
		fill_chunk_light(chunk, pack_light(MAXIMUM_LIGHT, 0))
		if open_columns != nil {
			fill_open_columns(open_columns, true)
		}
		return
	}
	// Chunks below the terrain stay dark: caves never open to the surface.
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
	apply_crate_site(generator, chunk, crates)
	if underground {
		return
	}
	minimum := [2]i32{origin.x, origin.z} - FEATURE_REACH
	nearby_veins := veins_near_box(generator, minimum, minimum + CHUNK_SIZE - 1 + 2 * FEATURE_REACH, context.temp_allocator)
	trees := chunk_trees(generator, chunk.coordinate, nearby_veins[:], context.temp_allocator)
	boulders := chunk_boulders(generator, chunk.coordinate, nearby_veins[:], context.temp_allocator)
	apply_features(generator, chunk, trees[:], boulders[:])
	apply_outcrops(generator, chunk, columns, nearby_veins[:], outcrops)
	clear_above_outcrops(generator, chunk, columns, nearby_veins[:], trees[:], boulders[:])
	apply_landing_pad(generator.landing_pad, generator.blocks.landing_pad, chunk)
	open := new(Open_Columns, context.temp_allocator)
	find_open_columns(chunk.coordinate, columns, nearby_veins[:], trees[:], boulders[:], open)
	close_landing_pad_columns(generator.landing_pad, chunk.coordinate, open)
	fill_chunk_sky_light(chunk, generator.registry, open)
	if open_columns != nil {
		open_columns^ = open^
	}
}

fill_open_columns :: proc(open: ^Open_Columns, value: bool) {
	for &column in open {
		column = value
	}
}

box_covers_column :: proc(box: Block_Box, x, z: i32) -> bool {
	return x >= box.minimum.x && x <= box.maximum.x && z >= box.minimum.z && z <= box.maximum.z
}

// The highest block of a column that can block light: its surface, or the
// top of a tree or boulder box over it. Boxes are larger than the shapes
// in them, so this may overestimate, which only leaves cells darker until
// the chunk above lights them from the main thread.
column_light_top :: proc(columns: ^Column_Grid, trees: []Tree, boulders: []Boulder, local_x, local_z: i32, x, z: i32) -> i32 {
	top := grid_column(columns, local_x, local_z).height
	for tree in trees {
		if box := tree_box(tree); box_covers_column(box, x, z) {
			top = max(top, box.maximum.y)
		}
	}
	for boulder in boulders {
		if box := boulder_box(boulder); box_covers_column(box, x, z) {
			top = max(top, box.maximum.y)
		}
	}
	return top
}

// Air, except water, in the chunk's part of a column from local height
// first to last inclusive.
clear_column_to_air :: proc(chunk: ^Chunk, water: Block_Id, x, z: i32, first, last: i32) {
	for y in max(first, 0) ..= min(last, CHUNK_SIZE - 1) {
		index := local_to_index({x, y, z})
		if chunk.blocks[index] != water {
			chunk.blocks[index] = AIR_BLOCK
		}
	}
}

// Features never root on a vein footprint, but leaves and boulders rooted
// next to one can reach over it. Every footprint column is cleared of them
// up to the highest feature box over it, so each outcrop is open to the
// sky. Water above an outcrop stays.
clear_above_outcrops :: proc(generator: ^Generator, chunk: ^Chunk, columns: ^Column_Grid, veins: []Vein, trees: []Tree, boulders: []Boulder) {
	origin := chunk_origin(chunk.coordinate)
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			world_x, world_z := origin.x + x, origin.z + z
			if !column_in_vein_footprint(veins, world_x, world_z) {
				continue
			}
			surface := grid_column(columns, x, z).height
			top := column_light_top(columns, trees, boulders, x, z, world_x, world_z)
			clear_column_to_air(chunk, generator.blocks.water, x, z, surface + 1 - origin.y, top - origin.y)
		}
	}
}

// A vein footprint column is open above its surface, since
// clear_above_outcrops removed the features over it.
find_open_columns :: proc(coordinate: Chunk_Coordinate, columns: ^Column_Grid, veins: []Vein, trees: []Tree, boulders: []Boulder, open: ^Open_Columns) {
	origin := chunk_origin(coordinate)
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			world_x, world_z := origin.x + x, origin.z + z
			top := grid_column(columns, x, z).height
			if !column_in_vein_footprint(veins, world_x, world_z) {
				top = column_light_top(columns, trees, boulders, x, z, world_x, world_z)
			}
			open[column_index(x, z)] = top < origin.y + CHUNK_SIZE
		}
	}
}

// New chunks start dirty so that they are meshed once.
generate_chunk :: proc(generator: ^Generator, coordinate: Chunk_Coordinate, allocator := context.allocator) -> Generated_Chunk {
	chunk := new(Chunk, allocator)
	chunk.coordinate = coordinate
	chunk.dirty = true
	outcrops := make([dynamic]Outcrop_Cell, allocator)
	crates := make([dynamic]Crate_Site, allocator)
	generate_chunk_blocks(generator, chunk, &outcrops, &crates)
	return Generated_Chunk{chunk = chunk, veins = column_veins(generator, chunk_column_of(coordinate), allocator), outcrops = outcrops, crates = crates}
}

// A chunk of a save: generated for its veins, outcrop cells and open
// columns, then given the saved blocks. Light is not saved, so the sky
// light is computed again from the saved blocks with the columns
// generation found open (a roof the player built in a chunk above is not
// seen here, as for generated chunks). ok is false for malformed bytes.
generate_saved_chunk :: proc(generator: ^Generator, coordinate: Chunk_Coordinate, saved: []byte, allocator := context.allocator) -> (generated: Generated_Chunk, ok: bool) {
	chunk := new(Chunk, allocator)
	chunk.coordinate = coordinate
	chunk.dirty = true
	outcrops := make([dynamic]Outcrop_Cell, allocator)
	crates := make([dynamic]Crate_Site, allocator)
	open: Open_Columns
	generate_chunk_blocks(generator, chunk, &outcrops, &crates, &open)
	generated = Generated_Chunk{chunk = chunk, veins = column_veins(generator, chunk_column_of(coordinate), allocator), outcrops = outcrops, crates = crates}
	if !deserialize_chunk_blocks(saved, &chunk.blocks) {
		return generated, false
	}
	chunk.modified = true
	fill_chunk_light(chunk, 0)
	fill_chunk_sky_light(chunk, generator.registry, &open)
	return generated, true
}
