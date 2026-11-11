package game

import "base:runtime"
import "core:slice"
import "core:sync"

// The waters over the whole planet (work item 0326, doc/architecture.md,
// World generation): the six faces of a cube, each the gnomonic grid of
// 0312's finder (Waters_Plane) on its axis with cells of grid_metres, cut
// into tiles of tile_metres found as they are asked by whichever thread
// asks (a chunk, a grid, a tree tile, the start). Every feature is a
// function of its own cell's neighbourhood: a lake of its pit's escape
// flood and 0312's refine, a head of its capped catchment, a spring of
// the heads within its spacing and the lakes over it, so a tile only
// decides which thread computes a feature, and the tiles are a cache and
// not a rule: neither the order of asking, the threads nor an eviction
// changes a byte. Integers and fixed point. A reader gets copies, but the
// caves' fade of a sample read alone, which reads the kept lakes in place
// while it holds the lock an eviction takes (water_tile_cave_lake_fade,
// 0339).

WATER_FACE_COUNT :: 6
// The escape flood reaches this many cells past the refine's half window.
WATER_ESCAPE_EXTRA_CELLS :: 4

// A cell's place in the order every rule breaks ties by: its height, then
// its face, row and column on the cube's grid.
Water_Cell_Order :: struct {
	height:      i64,
	face:        i32,
	row, column: i64,
}

// A tile's cells with its margin, row major from (first_column,
// first_row) on the tile's face's grid, each cell's relief.
Water_Tile_Window :: struct {
	key:                     Water_Tile_Key,
	first_column, first_row: i64,
	side:                    i64,
	heights:                 []i64,
}

// A window cell with its place in the order, for the catchment's sort.
Water_Window_Entry :: struct {
	order: Water_Cell_Order,
	index: i32,
}

// The lower height first, then the face, the row and the column.
water_cell_before :: proc(first, second: Water_Cell_Order) -> bool {
	if first.height != second.height {
		return first.height < second.height
	}
	if first.face != second.face {
		return first.face < second.face
	}
	if first.row != second.row {
		return first.row < second.row
	}
	return first.column < second.column
}

// The face a direction belongs to: the axis of its largest absolute
// component, ties to the lower axis, times 2, plus 1 when it is negative.
water_face_of :: proc(direction: [3]i64) -> i32 {
	axis := 0
	for candidate in 1 ..< 3 {
		if abs(direction[candidate]) > abs(direction[axis]) {
			axis = candidate
		}
	}
	return i32(2 * axis + (direction[axis] < 0 ? 1 : 0))
}

// The face's grid: its centre, east and north at the radius and the cell.
water_face_plane :: proc(cache: ^Water_Tile_Cache, face: i32) -> Waters_Plane {
	return Waters_Plane{cache.faces[face][0], cache.faces[face][1], cache.faces[face][2], cache.radius, cache.step}
}

// The tiles of the planet's waters, nil when the record has no tiles:
// the geometry from the seed and the record, no tile found yet. Called by
// resolve_session_planet, run_relief_map and the tests.
make_water_tile_cache :: proc(seed: u64, planet: Planet, maximum_tiles := MAXIMUM_WATER_TILES, allocator := context.allocator) -> ^Water_Tile_Cache {
	waters := planet.waters
	if waters.tile_metres == 0 {
		return nil
	}
	generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	cache := new(Water_Tile_Cache, allocator)
	cache.seed = seed
	cache.planet = planet
	cache.planet.water_tiles = nil
	cache.radius = generation.radius
	cache.sea = generation.sea_radius - generation.radius
	cache.step = metres_to_position_units(i64(waters.grid_metres))
	cache.face_cells = cache.radius / cache.step
	cache.tile_cells = i64(waters.tile_metres / waters.grid_metres)
	cache.escape_reach = i64(waters.lake_maximum_metres / 2 / waters.grid_metres + WATER_ESCAPE_EXTRA_CELLS)
	cache.catchment_cells = i32(waters.spring_catchment_square_metres / (waters.grid_metres * waters.grid_metres))
	cache.margin = max(cache.escape_reach, i64(cache.catchment_cells) + 2)
	cache.lake_reach = metres_to_position_units(i64(water_lake_reach_metres(waters)))
	cache.home = planet_home_direction(planet.home)
	for face in 0 ..< WATER_FACE_COUNT {
		centre: [3]i64
		centre[face / 2] = face % 2 == 0 ? UNIT_VECTOR_ONE : -UNIT_VECTOR_ONE
		east, north := planet_tangents(centre)
		cache.faces[face] = {centre, east, north}
	}
	cache.maximum_tiles = maximum_tiles
	cache.tiles = make(map[Water_Tile_Key]^Water_Tile, allocator)
	cache.allocator = allocator
	return cache
}

// Frees every tile, the map and the cache; nil does nothing. Only after
// every reader has stopped (end_session stops the workers first).
destroy_water_tile_cache :: proc(cache: ^Water_Tile_Cache) {
	if cache == nil {
		return
	}
	for _, tile in cache.tiles {
		free_water_tile(cache, tile)
	}
	delete(cache.tiles)
	allocator := cache.allocator
	free(cache, allocator)
}

// Each mask, the four slices and the tile, in the cache's allocator.
free_water_tile :: proc(cache: ^Water_Tile_Cache, tile: ^Water_Tile) {
	for lake in tile.lakes {
		delete(lake.mask, cache.allocator)
	}
	delete(tile.lakes, cache.allocator)
	delete(tile.candidates, cache.allocator)
	delete(tile.kept, cache.allocator)
	delete(tile.springs, cache.allocator)
	free(tile, cache.allocator)
}

// Adds every tile holding a cell whose point lies within reach (position
// units, 21 percent of the radius at most) of the direction's point, the
// border tiles' cells past the face's edge too. The square of half side
// reach * 9 / 8 + step on the direction's tangent plane holds the disc's
// central projection (R tan theta is under 1.03 r for r up to R / 4); a
// face where a corner of it lies behind is skipped: at the shipped
// reaches (803 m at 4 km, the largest against the radius) the whole disc
// then lies more than 60 degrees from that face's axis, past its tiles'
// cells (55.4 degrees at most); else the corners' bounding box in cells
// (the square's image is their convex hull), one cell wider each way.
water_tiles_near :: proc(cache: ^Water_Tile_Cache, direction: [3]i64, reach: i64, keys: ^map[Water_Tile_Key]struct{}) {
	east, north := planet_tangents(direction)
	half := reach * 9 / 8 + cache.step
	centre := fixed_scale(direction, cache.radius)
	across, up := fixed_scale(east, half), fixed_scale(north, half)
	corners := [4][3]i64{centre + across + up, centre + across - up, centre - across + up, centre - across - up}
	first_tile := floor_divide_i64(-cache.face_cells, cache.tile_cells)
	last_tile := floor_divide_i64(cache.face_cells, cache.tile_cells)
	for face in i32(0) ..< WATER_FACE_COUNT {
		plane := water_face_plane(cache, face)
		low := [2]i64{max(i64), max(i64)}
		high := [2]i64{min(i64), min(i64)}
		behind := false
		for corner in corners {
			corner_east, corner_north, ok := waters_plane_coordinates(plane, corner)
			if !ok {
				behind = true
				break
			}
			low = {min(low[0], corner_east), min(low[1], corner_north)}
			high = {max(high[0], corner_east), max(high[1], corner_north)}
		}
		if behind {
			continue
		}
		first_column := floor_divide_i64(low[0] + cache.step / 2, cache.step) - 1
		last_column := floor_divide_i64(high[0] + cache.step / 2, cache.step) + 1
		first_row := floor_divide_i64(low[1] + cache.step / 2, cache.step) - 1
		last_row := floor_divide_i64(high[1] + cache.step / 2, cache.step) + 1
		for row in max(floor_divide_i64(first_row, cache.tile_cells), first_tile) ..= min(floor_divide_i64(last_row, cache.tile_cells), last_tile) {
			for column in max(floor_divide_i64(first_column, cache.tile_cells), first_tile) ..= min(floor_divide_i64(last_column, cache.tile_cells), last_tile) {
				keys^[Water_Tile_Key{face, i32(column), i32(row)}] = {}
			}
		}
	}
}

// water_tiles_near at every point (i s, j s) of the centre's tangent
// plane with |i s| and |j s| at most half + s, s 256 m, reach s: every
// tile holding a cell of the square of half side half round the centre.
// For the relief map's square.
water_tiles_over_square :: proc(cache: ^Water_Tile_Cache, centre: [3]i64, half: i64, keys: ^map[Water_Tile_Key]struct{}) {
	spacing := metres_to_position_units(256)
	east, north := planet_tangents(centre)
	count := (half + spacing) / spacing
	for j in -count ..= count {
		for i in -count ..= count {
			direction, _ := normalize_fixed(fixed_scale(centre, cache.radius) + fixed_scale(east, i * spacing) + fixed_scale(north, j * spacing))
			water_tiles_near(cache, direction, spacing, keys)
		}
	}
}

// The tile holding the direction's nearest cell on its face.
water_tile_key_of :: proc(cache: ^Water_Tile_Cache, direction: [3]i64) -> Water_Tile_Key {
	face := water_face_of(direction)
	east, north, _ := waters_plane_coordinates(water_face_plane(cache, face), fixed_scale(direction, cache.radius))
	column := clamp(floor_divide_i64(east + cache.step / 2, cache.step), -cache.face_cells, cache.face_cells)
	row := clamp(floor_divide_i64(north + cache.step / 2, cache.step), -cache.face_cells, cache.face_cells)
	return {face, i32(floor_divide_i64(column, cache.tile_cells)), i32(floor_divide_i64(row, cache.tile_cells))}
}

// The home's tile and the eight round it on its face, those meeting the
// face's cells (the tech demo's start, 0326).
water_home_tile_keys :: proc(cache: ^Water_Tile_Cache, allocator := context.temp_allocator) -> [dynamic]Water_Tile_Key {
	home := water_tile_key_of(cache, cache.home)
	first := i32(floor_divide_i64(-cache.face_cells, cache.tile_cells))
	last := i32(floor_divide_i64(cache.face_cells, cache.tile_cells))
	keys := make([dynamic]Water_Tile_Key, 0, 9, allocator)
	for row in home.row - 1 ..= home.row + 1 {
		for column in home.column - 1 ..= home.column + 1 {
			if row >= first && row <= last && column >= first && column <= last {
				append(&keys, Water_Tile_Key{home.face, column, row})
			}
		}
	}
	return keys
}

// Every tile of every face meeting its cells, -face_cells to face_cells.
water_planet_tile_keys :: proc(cache: ^Water_Tile_Cache, allocator := context.allocator) -> [dynamic]Water_Tile_Key {
	first := i32(floor_divide_i64(-cache.face_cells, cache.tile_cells))
	last := i32(floor_divide_i64(cache.face_cells, cache.tile_cells))
	keys := make([dynamic]Water_Tile_Key, allocator)
	for face in i32(0) ..< WATER_FACE_COUNT {
		for row in first ..= last {
			for column in first ..= last {
				append(&keys, Water_Tile_Key{face, column, row})
			}
		}
	}
	return keys
}

// The keys of a set in (face, row, column) order, so a set's map order
// never shows.
water_tile_keys_sorted :: proc(keys: map[Water_Tile_Key]struct{}, allocator := context.temp_allocator) -> []Water_Tile_Key {
	sorted := make([dynamic]Water_Tile_Key, 0, len(keys), allocator)
	for key in keys {
		append(&sorted, key)
	}
	slice.sort_by(sorted[:], proc(first, second: Water_Tile_Key) -> bool {
		if first.face != second.face {
			return first.face < second.face
		}
		if first.row != second.row {
			return first.row < second.row
		}
		return first.column < second.column
	})
	return sorted[:]
}

// The tile's cells and its margin, each height the relief without the
// crater on the tile's face's grid, past the face's edge where the tile
// lies there.
water_tile_window :: proc(cache: ^Water_Tile_Cache, generation: Planet_Generation, key: Water_Tile_Key, allocator := context.temp_allocator) -> Water_Tile_Window {
	side := cache.tile_cells + 2 * cache.margin
	window := Water_Tile_Window {
		key          = key,
		first_column = i64(key.column) * cache.tile_cells - cache.margin,
		first_row    = i64(key.row) * cache.tile_cells - cache.margin,
		side         = side,
		heights      = make([]i64, side * side, allocator),
	}
	plane := water_face_plane(cache, key.face)
	for row in 0 ..< side {
		for column in 0 ..< side {
			window.heights[row * side + column] = waters_plane_height(generation, plane, window.first_column + column, window.first_row + row)
		}
	}
	return window
}

// The window cell's place in the order, its row and column the grid's.
water_window_order :: proc(window: ^Water_Tile_Window, column, row: i64) -> Water_Cell_Order {
	return {window.heights[row * window.side + column], window.key.face, window.first_row + row, window.first_column + column}
}

// Whether the window cell comes before all 8 neighbours in the order.
water_window_cell_is_pit :: proc(window: ^Water_Tile_Window, column, row: i64) -> bool {
	cell := water_window_order(window, column, row)
	for offset in WATERS_NEIGHBOURS {
		if water_cell_before(water_window_order(window, column + offset[0], row + offset[1]), cell) {
			return false
		}
	}
	return true
}

// The escape flood from a window cell (temp allocator): a priority flood
// over the cells within Chebyshev reach of it, whose pops raise a running
// sill; the first pop on the reach's ring or under the sea sets level to
// the sill (the minimax path out, 0312's filled height wherever the reach
// holds the basin and its spill) and stops. basin holds the window indices
// of the pops before the sill last rose, all under the level (0312's
// depression); wide when one lies on the reach's last two rings (0312's
// border rule).
water_escape_flood :: proc(window: ^Water_Tile_Window, column, row, reach, sea: i64) -> (level: i64, basin: [dynamic]i64, wide: bool) {
	square := 2 * reach + 1
	pushed := make([]bool, square * square, context.temp_allocator)
	heap := make([dynamic]Waters_Entry, 0, 4 * square, context.temp_allocator)
	pops := make([dynamic]i64, context.temp_allocator)
	rings := make([dynamic]i64, context.temp_allocator)
	start := reach * square + reach
	push_waters_entry(&heap, {window.heights[row * window.side + column], i32(start)})
	pushed[start] = true
	sill := min(i64)
	raised_at := 0
	for len(heap) > 0 {
		entry := pop_waters_entry(&heap)
		offset_column, offset_row := i64(entry.index) % square - reach, i64(entry.index) / square - reach
		ring := max(abs(offset_column), abs(offset_row))
		if entry.height > sill {
			sill = entry.height
			raised_at = len(pops)
		}
		append(&pops, (row + offset_row) * window.side + column + offset_column)
		append(&rings, ring)
		level = sill
		if ring == reach || entry.height < sea {
			break
		}
		for neighbour in WATERS_NEIGHBOURS {
			next_column, next_row := offset_column + neighbour[0], offset_row + neighbour[1]
			next := (next_row + reach) * square + next_column + reach
			if pushed[next] {
				continue
			}
			pushed[next] = true
			push_waters_entry(&heap, {window.heights[(row + next_row) * window.side + column + next_column], i32(next)})
		}
	}
	basin = make([dynamic]i64, 0, raised_at, context.temp_allocator)
	for index in 0 ..< raised_at {
		append(&basin, pops[index])
		wide ||= rings[index] >= reach - 1
	}
	return
}

// The lakes of the tile's pits: the core cells row major before all 8
// neighbours, past the face's edge too, where a border tile's cells lie
// over the next face's ground (a basin over a seam is found from every
// face whose tiles hold its first cell, and the final keeps one); per pit
// the escape flood, skipped when a basin cell comes before the pit (one
// lake per depression, its first cell), the basin is wide, shallower than
// the minimum depth, smaller than half the minimum area, or the pit lies
// in the clearing; then 0312's refine at the pit to the flood's level,
// kept when its refined pit lies outside the clearing, its cell set; at
// most MAXIMUM_PLANET_LAKES.
find_water_tile_lakes :: proc(cache: ^Water_Tile_Cache, generation: Planet_Generation, window: ^Water_Tile_Window, allocator := context.allocator) -> []Planet_Lake {
	waters := cache.planet.waters
	lakes := make([dynamic]Planet_Lake, allocator)
	clearing := metres_to_position_units(i64(waters.clearing_metres))
	home_point := fixed_scale(cache.home, cache.radius)
	minimum_depth := millimetres_to_position_units(waters.lake_minimum_depth_millimetres)
	cell_area := waters.grid_metres * waters.grid_metres
	plane := water_face_plane(cache, window.key.face)
	core: for row in cache.margin ..< cache.margin + cache.tile_cells {
		for column in cache.margin ..< cache.margin + cache.tile_cells {
			if len(lakes) >= MAXIMUM_PLANET_LAKES {
				break core
			}
			global_column, global_row := window.first_column + column, window.first_row + row
			if !water_window_cell_is_pit(window, column, row) {
				continue
			}
			level, basin, wide := water_escape_flood(window, column, row, cache.escape_reach, cache.sea)
			pit := water_window_order(window, column, row)
			if wide || level - pit.height < minimum_depth || len(basin) * cell_area < waters.lake_minimum_area_square_metres / 2 {
				continue
			}
			first := true
			for index in basin {
				if water_cell_before(water_window_order(window, index % window.side, index / window.side), pit) {
					first = false
					break
				}
			}
			if !first {
				continue
			}
			direction := waters_plane_direction(plane, global_column, global_row)
			if squared_chord(fixed_scale(direction, cache.radius), home_point) < clearing * clearing {
				continue
			}
			lake, ok := refine_planet_lake(generation, waters, direction, level, allocator)
			if !ok {
				continue
			}
			if squared_chord(lake.origin, home_point) < clearing * clearing {
				delete(lake.mask, allocator)
				continue
			}
			lake.cell = {window.key.face, i32(global_column), i32(global_row)}
			append(&lakes, lake)
		}
	}
	return lakes[:]
}

// The heads of the tile's drainage: each window cell off its outer ring
// drains to its first neighbour in the order when that one comes before
// it; the cells taken latest first add their area to the cell they drain
// to, capped at the catchment, exact for every cell the catchment and one
// more inside the window. A head is a core cell, row major, past the
// face's edge too (as the pits), draining the catchment with no donor
// that does, draining somewhere, at least spring_minimum_metres over the
// sea, outside the clearing and the spacing from every record spring: its
// spring, drop its height over the sea.
find_water_tile_candidates :: proc(cache: ^Water_Tile_Cache, window: ^Water_Tile_Window, allocator := context.allocator) -> []Water_Spring_Candidate {
	waters := cache.planet.waters
	side := window.side
	count := side * side
	parent := make([]i32, count, context.temp_allocator)
	area := make([]i32, count, context.temp_allocator)
	entries := make([]Water_Window_Entry, count, context.temp_allocator)
	for row in 0 ..< side {
		for column in 0 ..< side {
			index := row * side + column
			parent[index], area[index] = -1, 1
			entries[index] = {water_window_order(window, column, row), i32(index)}
			if row == 0 || column == 0 || row == side - 1 || column == side - 1 {
				continue
			}
			best := entries[index].order
			for offset in WATERS_NEIGHBOURS {
				next := water_window_order(window, column + offset[0], row + offset[1])
				if water_cell_before(next, best) {
					best = next
					parent[index] = i32((row + offset[1]) * side + column + offset[0])
				}
			}
		}
	}
	slice.sort_by(entries, proc(first, second: Water_Window_Entry) -> bool {
		return water_cell_before(second.order, first.order)
	})
	catchment := cache.catchment_cells
	for entry in entries {
		if next := parent[entry.index]; next >= 0 {
			area[next] = min(area[next] + area[entry.index], catchment)
		}
	}
	draining := make([]bool, count, context.temp_allocator)
	for index in 0 ..< count {
		if parent[index] >= 0 && area[index] >= catchment {
			draining[parent[index]] = true
		}
	}
	minimum := cache.sea + metres_to_position_units(i64(waters.spring_minimum_metres))
	clearing := metres_to_position_units(i64(waters.clearing_metres))
	spacing := metres_to_position_units(i64(waters.spring_spacing_metres))
	home_point := fixed_scale(cache.home, cache.radius)
	plane := water_face_plane(cache, window.key.face)
	candidates := make([dynamic]Water_Spring_Candidate, allocator)
	for row in cache.margin ..< cache.margin + cache.tile_cells {
		for column in cache.margin ..< cache.margin + cache.tile_cells {
			index := row * side + column
			height := window.heights[index]
			if area[index] < catchment || draining[index] || parent[index] < 0 || height < minimum {
				continue
			}
			global_column, global_row := window.first_column + column, window.first_row + row
			direction := waters_plane_direction(plane, global_column, global_row)
			point := fixed_scale(direction, cache.radius)
			if squared_chord(point, home_point) < clearing * clearing {
				continue
			}
			near := false
			for record in cache.planet.springs {
				near ||= squared_chord(point, fixed_scale(planet_spring_direction(record), cache.radius)) < spacing * spacing
			}
			if near {
				continue
			}
			spring := Planet_Water_Spring {
				direction = direction,
				height    = height,
				drop      = height - cache.sea,
			}
			append(&candidates, Water_Spring_Candidate{spring, {window.key.face, i32(global_column), i32(global_row)}})
		}
	}
	return candidates[:]
}

// A tile's analysis, a function of the seed, the record and the key that
// reads only the relief: its lakes and its heads.
find_water_tile_analysis :: proc(cache: ^Water_Tile_Cache, key: Water_Tile_Key, allocator := context.allocator) -> (lakes: []Planet_Lake, candidates: []Water_Spring_Candidate) {
	generation := make_planet_generation(cache.seed, cache.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	window := water_tile_window(cache, generation, key)
	lakes = find_water_tile_lakes(cache, generation, &window, allocator)
	candidates = find_water_tile_candidates(cache, &window, allocator)
	return
}

// A cell's order of the cube's grid: the face, the row, the column.
water_grid_cell_before :: proc(first, second: [3]i32) -> bool {
	if first[0] != second[0] {
		return first[0] < second[0]
	}
	if first[2] != second[2] {
		return first[2] < second[2]
	}
	return first[1] < second[1]
}

// More water cells first, then the pit's cell.
water_lake_before :: proc(first, second: Planet_Lake) -> bool {
	if first.cells != second.cells {
		return first.cells > second.cells
	}
	return water_grid_cell_before(first.cell, second.cell)
}

// Higher first, then the cell.
water_candidate_before :: proc(first, second: Water_Spring_Candidate) -> bool {
	if first.spring.height != second.spring.height {
		return first.spring.height > second.spring.height
	}
	return water_grid_cell_before(first.cell, second.cell)
}

// Whether no lake holds the head's point with the head under its level.
water_head_is_dry :: proc(candidate: Water_Spring_Candidate, lakes: []Planet_Lake, radius: i64) -> bool {
	point := fixed_scale(candidate.spring.direction, radius)
	for lake in lakes {
		if candidate.spring.height < lake.level && planet_lake_holds(lake, point, radius) {
			return false
		}
	}
	return true
}

// A tile's final from its analysis and the analyses near it: a lake is
// kept unless a near lake from another pit and before it holds its refined
// pit or is held at its own by it; a head is a spring when no near lake
// holds it under its level and no such dry near head from another cell and
// before it lies within the spacing; at most MAXIMUM_DERIVED_SPRINGS, in
// the heads' order. Each answer reads only what lies within a lake's or
// a spring's reach, so it is local.
find_water_tile_final :: proc(cache: ^Water_Tile_Cache, lakes: []Planet_Lake, candidates: []Water_Spring_Candidate, near_lakes: []Planet_Lake, near_candidates: []Water_Spring_Candidate, allocator := context.allocator) -> (kept: []i32, springs: []Planet_Water_Spring) {
	radius := cache.radius
	kept_lakes := make([dynamic]i32, allocator)
	for lake, index in lakes {
		dropped := false
		for other in near_lakes {
			if other.cell == lake.cell || !water_lake_before(other, lake) {
				continue
			}
			if planet_lake_holds(other, lake.origin, radius) || planet_lake_holds(lake, other.origin, radius) {
				dropped = true
				break
			}
		}
		if !dropped {
			append(&kept_lakes, i32(index))
		}
	}
	spacing := metres_to_position_units(i64(cache.planet.waters.spring_spacing_metres))
	derived := make([dynamic]Planet_Water_Spring, allocator)
	for candidate in candidates {
		if len(derived) >= MAXIMUM_DERIVED_SPRINGS {
			break
		}
		if !water_head_is_dry(candidate, near_lakes, radius) {
			continue
		}
		point := fixed_scale(candidate.spring.direction, radius)
		outranked := false
		for other in near_candidates {
			if other.cell == candidate.cell || !water_candidate_before(other, candidate) {
				continue
			}
			if squared_chord(point, fixed_scale(other.spring.direction, radius)) < spacing * spacing && water_head_is_dry(other, near_lakes, radius) {
				outranked = true
				break
			}
		}
		if !outranked {
			append(&derived, candidate.spring)
		}
	}
	return kept_lakes[:], derived[:]
}

// The lakes with their masks cloned.
clone_planet_lakes :: proc(lakes: []Planet_Lake, allocator := context.allocator) -> []Planet_Lake {
	cloned := slice.clone(lakes, allocator)
	for &lake in cloned {
		lake.mask = slice.clone(lake.mask, allocator)
	}
	return cloned
}

// The key's tile, made Absent when missing; the lock held.
water_tile_of :: proc(cache: ^Water_Tile_Cache, key: Water_Tile_Key) -> ^Water_Tile {
	if tile, found := cache.tiles[key]; found {
		return tile
	}
	tile := new(Water_Tile, cache.allocator)
	cache.tiles[key] = tile
	return tile
}

// Whether any key's state is Finding; the lock held.
water_tiles_finding :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key, finals: bool) -> bool {
	for key in keys {
		if tile, found := cache.tiles[key]; found && (finals ? tile.final : tile.analysis) == .Finding {
			return true
		}
	}
	return false
}

// A state just found: used the next clock, the cache evicted down to its
// bound (but this key) and every waiter woken; the lock held.
publish_water_tile :: proc(cache: ^Water_Tile_Cache, key: Water_Tile_Key, tile: ^Water_Tile) {
	cache.clock += 1
	tile.used = cache.clock
	evict_water_tiles(cache, key)
	sync.cond_broadcast(&cache.changed)
}

// Finds the key's analysis on this thread, its temp memory released, and
// publishes it in the cache's allocator.
find_and_publish_water_tile_analysis :: proc(cache: ^Water_Tile_Cache, key: Water_Tile_Key) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	lakes, candidates := find_water_tile_analysis(cache, key, context.temp_allocator)
	sync.mutex_lock(&cache.mutex)
	defer sync.mutex_unlock(&cache.mutex)
	tile := cache.tiles[key]
	tile.lakes = clone_planet_lakes(lakes, cache.allocator)
	tile.candidates = slice.clone(candidates, cache.allocator)
	tile.analysis = .Found
	publish_water_tile(cache, key, tile)
}

// Finds the key's final on this thread from its analysis and the analyses
// of the tiles its lakes' pits (within two lakes' reach) and its heads
// (within a spring's spacing and a lake's reach) reach, and publishes it.
find_and_publish_water_tile_final :: proc(cache: ^Water_Tile_Cache, key: Water_Tile_Key) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	own := []Water_Tile_Key{key}
	lakes, candidates := take_water_tile_analyses(cache, own)
	near := make(map[Water_Tile_Key]struct{}, context.temp_allocator)
	near[key] = {}
	for lake in lakes {
		water_tiles_near(cache, lake.centre, 2 * cache.lake_reach, &near)
	}
	spacing := metres_to_position_units(i64(cache.planet.waters.spring_spacing_metres))
	for candidate in candidates {
		water_tiles_near(cache, candidate.spring.direction, spacing + cache.lake_reach, &near)
	}
	near_lakes, near_candidates := take_water_tile_analyses(cache, water_tile_keys_sorted(near))
	kept, springs := find_water_tile_final(cache, lakes, candidates, near_lakes, near_candidates, context.temp_allocator)
	sync.mutex_lock(&cache.mutex)
	defer sync.mutex_unlock(&cache.mutex)
	tile := cache.tiles[key]
	tile.kept = slice.clone(kept, cache.allocator)
	tile.springs = slice.clone(springs, cache.allocator)
	tile.final = .Found
	publish_water_tile(cache, key, tile)
}

// The analyses or the finals of the keys found: under the lock each Absent
// state is claimed as Finding, each claim is found outside it on this
// thread and published, then the states other threads are finding are
// waited for. An analysis asks nothing and a final only analyses, so no
// wait closes a cycle. A state may be evicted again before its reader
// copies it (take_water_tile_analyses, take_water_tile_finals).
ensure_water_tiles :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key, finals: bool) {
	claims := make([dynamic]Water_Tile_Key, context.temp_allocator)
	sync.mutex_lock(&cache.mutex)
	for key in keys {
		tile := water_tile_of(cache, key)
		state := finals ? &tile.final : &tile.analysis
		if state^ == .Absent {
			state^ = .Finding
			append(&claims, key)
		}
	}
	sync.mutex_unlock(&cache.mutex)
	for key in claims {
		if finals {
			find_and_publish_water_tile_final(cache, key)
		} else {
			find_and_publish_water_tile_analysis(cache, key)
		}
	}
	sync.mutex_lock(&cache.mutex)
	for water_tiles_finding(cache, keys, finals) {
		sync.cond_wait(&cache.changed, &cache.mutex)
	}
	sync.mutex_unlock(&cache.mutex)
}

// The analyses of the keys, copied in the allocator (masks cloned) in the
// keys' order: ensure_water_tiles, then each key copied under the lock
// while its state is Found and its clock stamped; a key evicted in between
// is found again.
take_water_tile_analyses :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key, allocator := context.temp_allocator) -> (lakes: []Planet_Lake, candidates: []Water_Spring_Candidate) {
	ensure_water_tiles(cache, keys, false)
	listed_lakes := make([dynamic]Planet_Lake, allocator)
	listed_candidates := make([dynamic]Water_Spring_Candidate, allocator)
	for key in keys {
		for {
			sync.mutex_lock(&cache.mutex)
			tile, found := cache.tiles[key]
			if found && tile.analysis == .Found {
				append(&listed_lakes, ..clone_planet_lakes(tile.lakes, allocator))
				append(&listed_candidates, ..tile.candidates)
				cache.clock += 1
				tile.used = cache.clock
				sync.mutex_unlock(&cache.mutex)
				break
			}
			sync.mutex_unlock(&cache.mutex)
			ensure_water_tiles(cache, []Water_Tile_Key{key}, false)
		}
	}
	return listed_lakes[:], listed_candidates[:]
}

// The finals of the keys, copied in the allocator: each key's kept lakes
// (masks cloned) and its springs, in the keys' order, as
// take_water_tile_analyses copies.
take_water_tile_finals :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key, allocator := context.temp_allocator) -> (lakes: []Planet_Lake, springs: []Planet_Water_Spring) {
	ensure_water_tiles(cache, keys, true)
	listed_lakes := make([dynamic]Planet_Lake, allocator)
	listed_springs := make([dynamic]Planet_Water_Spring, allocator)
	for key in keys {
		for {
			sync.mutex_lock(&cache.mutex)
			tile, found := cache.tiles[key]
			if found && tile.final == .Found {
				for index in tile.kept {
					lake := tile.lakes[index]
					lake.mask = slice.clone(lake.mask, allocator)
					append(&listed_lakes, lake)
				}
				append(&listed_springs, ..tile.springs)
				cache.clock += 1
				tile.used = cache.clock
				sync.mutex_unlock(&cache.mutex)
				break
			}
			sync.mutex_unlock(&cache.mutex)
			ensure_water_tiles(cache, []Water_Tile_Key{key}, true)
		}
	}
	return listed_lakes[:], listed_springs[:]
}

// The caves' fade at a sample read alone (cave_lake_fade): the least of
// cave_lake_fade_of over the kept lakes of the tiles near the position,
// those generation_lakes_meeting_box lists for the position's box widened
// by CAVE_LAKE_LIST_METRES. It copies no lake or mask (0339): the copies of
// take_water_tile_finals are there so an eviction can free a tile while a
// reader holds its lakes, which the lock prevents here, since each tile's
// lakes are read while it is held. It allocates the keys alone (temp
// allocator; ensure_water_tiles its claims, and a tile not yet found),
// and nothing is allocated or locked inside the mutex.
water_tile_cave_lake_fade :: proc(cache: ^Water_Tile_Cache, generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64) -> i64 {
	widen := metres_to_position_units(CAVE_LAKE_LIST_METRES)
	point := cast([3]i64)position
	direction, half := water_query_box(point - widen, point + widen)
	near := make(map[Water_Tile_Key]struct{}, context.temp_allocator)
	water_tiles_near(cache, direction, cache.lake_reach + 2 * half, &near)
	keys := water_tile_keys_sorted(near)
	ensure_water_tiles(cache, keys, true)
	fade: i64 = NOISE_ONE
	for key in keys {
		for {
			sync.mutex_lock(&cache.mutex)
			tile, found := cache.tiles[key]
			if found && tile.final == .Found {
				for index in tile.kept {
					fade = min(fade, cave_lake_fade_of(generation, tile.lakes[index], position, distance, on_sphere))
				}
				cache.clock += 1
				tile.used = cache.clock
				sync.mutex_unlock(&cache.mutex)
				break
			}
			sync.mutex_unlock(&cache.mutex)
			ensure_water_tiles(cache, []Water_Tile_Key{key}, true)
		}
	}
	return fade
}

// While more than maximum_tiles tiles hold a state Found, frees the least
// recently asked with neither state Finding, never the key just published;
// the lock held. A freed tile is found again alike, so an eviction changes
// only who computes when.
evict_water_tiles :: proc(cache: ^Water_Tile_Cache, keep: Water_Tile_Key) {
	for {
		found := 0
		least: ^Water_Tile = nil
		least_key: Water_Tile_Key
		for key, tile in cache.tiles {
			if tile.analysis != .Found && tile.final != .Found {
				continue
			}
			found += 1
			if key == keep || tile.analysis == .Finding || tile.final == .Finding {
				continue
			}
			if least == nil || tile.used < least.used {
				least, least_key = tile, key
			}
		}
		if found <= cache.maximum_tiles || least == nil {
			return
		}
		delete_key(&cache.tiles, least_key)
		free_water_tile(cache, least)
	}
}

// The kept lakes of the tiles within reach of the direction
// (water_tiles_near), sorted by water_lake_before.
water_tile_lakes_near :: proc(cache: ^Water_Tile_Cache, direction: [3]i64, reach: i64, allocator := context.temp_allocator) -> []Planet_Lake {
	near := make(map[Water_Tile_Key]struct{}, context.temp_allocator)
	water_tiles_near(cache, direction, reach, &near)
	lakes, _ := take_water_tile_finals(cache, water_tile_keys_sorted(near), allocator)
	slice.sort_by(lakes, water_lake_before)
	return lakes
}

// The springs of the tiles within reach of the direction, sorted by
// direction (x, then y, then z).
water_tile_springs_near :: proc(cache: ^Water_Tile_Cache, direction: [3]i64, reach: i64, allocator := context.temp_allocator) -> []Planet_Water_Spring {
	near := make(map[Water_Tile_Key]struct{}, context.temp_allocator)
	water_tiles_near(cache, direction, reach, &near)
	_, springs := take_water_tile_finals(cache, water_tile_keys_sorted(near), allocator)
	slice.sort_by(springs, water_spring_direction_before)
	return springs
}

// x, then y, then z.
water_spring_direction_before :: proc(first, second: Planet_Water_Spring) -> bool {
	if first.direction.x != second.direction.x {
		return first.direction.x < second.direction.x
	}
	if first.direction.y != second.direction.y {
		return first.direction.y < second.direction.y
	}
	return first.direction.z < second.direction.z
}

// The tech demo's start with tiles (0326): 0312's grid round the home and
// its flood, the springs of the home's 3 by 3 tiles' finals (the grid's
// plane is the lattice's tangent plane at the home), each whose grid cell
// is inside rewritten with that cell's height, its outlet's fall and
// to_sea (0312's rule), sorted by direction, then planet_water_start: the
// record's springs and those, the largest fall to the sea. The session's
// cache when the planet has one, else one of its own.
planet_tile_water_start :: proc(seed: u64, planet: Planet) -> (start: [3]i64, found: bool) {
	if planet.water_tiles != nil {
		return planet_tile_water_start_in(seed, planet, planet.water_tiles)
	}
	cache := make_water_tile_cache(seed, planet)
	if cache == nil {
		return {}, false
	}
	defer destroy_water_tile_cache(cache)
	return planet_tile_water_start_in(seed, planet, cache)
}

// planet_tile_water_start with the cache.
planet_tile_water_start_in :: proc(seed: u64, planet: Planet, cache: ^Water_Tile_Cache) -> (start: [3]i64, found: bool) {
	generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	sea := generation.sea_radius - generation.radius
	grid := make_waters_grid(generation, cache.home, planet.waters, planet.radius_metres)
	defer destroy_waters_grid(&grid)
	flood_waters_grid(&grid, sea)
	keys := water_home_tile_keys(cache)
	_, tile_springs := take_water_tile_finals(cache, keys[:])
	springs := make([dynamic]Planet_Water_Spring, context.temp_allocator)
	for spring in tile_springs {
		cell, inside := waters_grid_cell(&grid, spring.direction)
		if !inside {
			continue
		}
		height := grid.heights[cell]
		outlet := grid.heights[grid.outlet[cell]]
		to_sea := outlet < sea
		append(&springs, Planet_Water_Spring{direction = spring.direction, height = height, drop = height - (to_sea ? sea : outlet), to_sea = to_sea})
	}
	slice.sort_by(springs[:], water_spring_direction_before)
	return planet_water_start(&grid, planet.springs, springs[:], sea)
}
