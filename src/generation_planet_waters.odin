package game

import "core:slice"
@(require) import "core:sync"

// The waters of a planet (work item 0312, doc/architecture.md, World
// generation): springs at the valley heads of the highlands and lakes in
// their basins round the home, in integers and fixed point, a pure
// function of the seed and the recorded planet (the spacing never moves a
// spring or a lake), found once per session (make_planet_water_features).
// This finder round the home is an old world's, recorded before the
// tiles (0326, generation_planet_water_tiles.odin), which find the waters
// over the whole planet by the local forms of its rules and share the
// refine, the seal and the readers below; the tech demo's start still
// ranks its springs on this grid's flood (planet_tile_water_start).
// The finder reads uncratered_relief only, so the crater never makes a
// lake. Heights and levels are position units over the radius, as
// uncratered_relief returns them; sea is generation.sea_radius less
// generation.radius.
//
// A square grid round the home on its tangent plane (the gnomonic
// projection, Waters_Plane) is flooded from its border and its cells under
// the sea (a priority flood), which gives every cell its filled height and
// the cell it drains to. The channel heads of that drainage high over the
// sea are the springs; the depressions are the lakes, each refined round
// its pit on a LAKE_CELL_METRES grid up to its pour point and sealed on
// the 1 m lattice, so no shore column under the level stands beside a
// lower one outside the lake's mask.

// The refine passes saddles lower than the coarse level less this.
WATERS_REFINE_TOLERANCE_METRES :: 2
// The seal lowers a lake's level at most this many times.
LAKE_SEAL_ROUNDS :: 4
// The refine's descent from the coarse pit takes at most this many steps.
LAKE_DESCENT_STEPS :: 64
// A spring, or a record spring's cell for the start, lies at least this
// many cells inside the grid's edge.
WATERS_BORDER_CELLS :: 4
WATERS_NEIGHBOURS :: [8][2]i64{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}
WATERS_FACES :: [4][2]i64{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

// A tangent plane: its centre (a unit direction) and its east and north
// tangents, the sphere's radius and a cell's step, in position units.
Waters_Plane :: struct {
	centre, east, north: [3]i64,
	radius, step:        i64,
}

// A heap entry, ordered by height, then index.
Waters_Entry :: struct {
	height: i64,
	index:  i32,
}

// The grid round the home, row major from (-half, -half): each cell's
// relief and filled height, the cell it drains to (-1 for an outlet), the
// flood's order, the cells draining through it and its outlet.
Waters_Grid :: struct {
	plane:                       Waters_Plane,
	half, side:                  int,
	heights, filled:             []i64,
	parent, order, area, outlet: []i32,
}

// A depression of the grid: its cells, its pit (the lowest height, then
// index), its filled level, its floor and whether it reaches within one
// cell of the grid's edge.
Waters_Depression :: struct {
	cells, pit:   int,
	level, floor: i64,
	border:       bool,
}

// A lake's refine window: heights evaluated once each, on demand.
Lake_Window :: struct {
	generation: Planet_Generation,
	plane:      Waters_Plane,
	half, side: i64,
	heights:    []i64,
	known:      []bool,
}

// The tangent plane at a unit direction: east the cross of +y (+x near
// the poles) with it, north the cross of it with east.
planet_tangents :: proc(direction: [3]i64) -> (east, north: [3]i64) {
	reference := [3]i64{0, UNIT_VECTOR_ONE, 0}
	if abs(direction.y) >= UNIT_VECTOR_ONE * 9 / 10 {
		reference = {UNIT_VECTOR_ONE, 0, 0}
	}
	east, _ = normalize_fixed(fixed_cross(reference, direction))
	north, _ = normalize_fixed(fixed_cross(direction, east))
	return
}

// The unit direction of the plane's point east_cells and north_cells
// steps from its centre, the gnomonic projection's point.
waters_plane_direction :: proc(plane: Waters_Plane, east_cells, north_cells: i64) -> [3]i64 {
	direction, _ := normalize_fixed(fixed_scale(plane.centre, plane.radius) + fixed_scale(plane.east, east_cells * plane.step) + fixed_scale(plane.north, north_cells * plane.step))
	return direction
}

// The plane's coordinates of a point in position units, the projection's
// inverse; false for a point behind the centre.
waters_plane_coordinates :: proc(plane: Waters_Plane, point: [3]i64) -> (east, north: i64, ok: bool) {
	along := fixed_dot(point, plane.centre)
	if along <= 0 {
		return 0, 0, false
	}
	return fixed_dot(point, plane.east) * plane.radius / along, fixed_dot(point, plane.north) * plane.radius / along, true
}

// test_report_the_waters_cost's define (0312, 0326): with it the waters
// count their relief evaluations.
WATERS_COST :: #config(WATERS_COST, false)

when WATERS_COST {
	waters_relief_evaluations: u64
}

// The relief without the crater under the plane's point.
waters_plane_height :: proc(generation: Planet_Generation, plane: Waters_Plane, east_cells, north_cells: i64) -> i64 {
	when WATERS_COST {
		sync.atomic_add(&waters_relief_evaluations, 1)
	}
	return uncratered_relief(generation, fixed_scale(waters_plane_direction(plane, east_cells, north_cells), generation.radius))
}

waters_entry_before :: proc(first, second: Waters_Entry) -> bool {
	return first.height < second.height || (first.height == second.height && first.index < second.index)
}

// A binary min heap by (height, index) of its own, the water bodies'
// pattern, so the order never depends on a library.
push_waters_entry :: proc(heap: ^[dynamic]Waters_Entry, entry: Waters_Entry) {
	append(heap, entry)
	child := len(heap) - 1
	for child > 0 {
		parent := (child - 1) / 2
		if !waters_entry_before(heap[child], heap[parent]) {
			break
		}
		heap[child], heap[parent] = heap[parent], heap[child]
		child = parent
	}
}

// The heap's least entry, taken out.
pop_waters_entry :: proc(heap: ^[dynamic]Waters_Entry) -> Waters_Entry {
	top := heap[0]
	last := pop(heap)
	if len(heap) == 0 {
		return top
	}
	heap[0] = last
	parent := 0
	for {
		smallest := parent
		for child in ([2]int{2 * parent + 1, 2 * parent + 2}) {
			if child < len(heap) && waters_entry_before(heap[child], heap[smallest]) {
				smallest = child
			}
		}
		if smallest == parent {
			break
		}
		heap[smallest], heap[parent] = heap[parent], heap[smallest]
		parent = smallest
	}
	return top
}

// The grid round the home at grid_metres, min(reach_metres, radius / 2)
// either side, every cell's height read; the flood's slices allocated.
make_waters_grid :: proc(generation: Planet_Generation, home: [3]i64, waters: Planet_Waters, radius_metres: int, allocator := context.allocator) -> Waters_Grid {
	east, north := planet_tangents(home)
	grid := Waters_Grid {
		plane = {home, east, north, generation.radius, metres_to_position_units(i64(waters.grid_metres))},
		half  = min(waters.reach_metres, radius_metres / 2) / waters.grid_metres,
	}
	grid.side = 2 * grid.half + 1
	count := grid.side * grid.side
	grid.heights = make([]i64, count, allocator)
	grid.filled = make([]i64, count, allocator)
	grid.parent = make([]i32, count, allocator)
	grid.order = make([]i32, count, allocator)
	grid.area = make([]i32, count, allocator)
	grid.outlet = make([]i32, count, allocator)
	for row in 0 ..< grid.side {
		for column in 0 ..< grid.side {
			grid.heights[row * grid.side + column] = waters_plane_height(generation, grid.plane, i64(column - grid.half), i64(row - grid.half))
		}
	}
	return grid
}

destroy_waters_grid :: proc(grid: ^Waters_Grid, allocator := context.allocator) {
	delete(grid.heights, allocator)
	delete(grid.filled, allocator)
	delete(grid.parent, allocator)
	delete(grid.order, allocator)
	delete(grid.area, allocator)
	delete(grid.outlet, allocator)
	grid^ = {}
}

// The priority flood from the border and the sea (sea the sea level over
// the radius): every border cell and every cell under the sea is an outlet
// (filled its height, parent -1), pushed in index order; each pop takes
// the next place in order and pushes its unvisited 8-neighbours filled to
// at least its own filled height, itself their parent. Then the area (the
// cells draining through each) and the outlet each cell drains to.
flood_waters_grid :: proc(grid: ^Waters_Grid, sea: i64) {
	count := grid.side * grid.side
	visited := make([]bool, count, context.temp_allocator)
	heap := make([dynamic]Waters_Entry, 0, 4 * grid.side, context.temp_allocator)
	for index in 0 ..< count {
		grid.parent[index] = -1
		column, row := index % grid.side, index / grid.side
		border := column == 0 || row == 0 || column == grid.side - 1 || row == grid.side - 1
		if border || grid.heights[index] < sea {
			visited[index] = true
			grid.filled[index] = grid.heights[index]
			push_waters_entry(&heap, {grid.heights[index], i32(index)})
		}
	}
	popped := 0
	for len(heap) > 0 {
		entry := pop_waters_entry(&heap)
		grid.order[popped] = entry.index
		popped += 1
		column, row := int(entry.index) % grid.side, int(entry.index) / grid.side
		for offset in WATERS_NEIGHBOURS {
			next_column, next_row := column + int(offset[0]), row + int(offset[1])
			if next_column < 0 || next_row < 0 || next_column >= grid.side || next_row >= grid.side {
				continue
			}
			next := next_row * grid.side + next_column
			if visited[next] {
				continue
			}
			visited[next] = true
			grid.filled[next] = max(grid.heights[next], entry.height)
			grid.parent[next] = entry.index
			push_waters_entry(&heap, {grid.filled[next], i32(next)})
		}
	}
	for &area in grid.area {
		area = 1
	}
	for position := count - 1; position >= 0; position -= 1 {
		cell := grid.order[position]
		if parent := grid.parent[cell]; parent >= 0 {
			grid.area[parent] += grid.area[cell]
		}
	}
	for cell in grid.order {
		parent := grid.parent[cell]
		grid.outlet[cell] = parent < 0 ? cell : grid.outlet[parent]
	}
}

// The 8-connected components of the cells filled over their height, in
// index order of their first cell.
find_waters_depressions :: proc(grid: ^Waters_Grid, allocator := context.temp_allocator) -> [dynamic]Waters_Depression {
	count := grid.side * grid.side
	depressions := make([dynamic]Waters_Depression, allocator)
	seen := make([]bool, count, context.temp_allocator)
	queue := make([dynamic]int, context.temp_allocator)
	for index in 0 ..< count {
		if seen[index] || grid.filled[index] <= grid.heights[index] {
			continue
		}
		depression := Waters_Depression {
			pit   = index,
			level = grid.filled[index],
			floor = grid.heights[index],
		}
		clear(&queue)
		append(&queue, index)
		seen[index] = true
		for head := 0; head < len(queue); head += 1 {
			cell := queue[head]
			depression.cells += 1
			if grid.heights[cell] < depression.floor || (grid.heights[cell] == depression.floor && cell < depression.pit) {
				depression.floor, depression.pit = grid.heights[cell], cell
			}
			column, row := cell % grid.side, cell / grid.side
			if column <= 1 || row <= 1 || column >= grid.side - 2 || row >= grid.side - 2 {
				depression.border = true
			}
			for offset in WATERS_NEIGHBOURS {
				next_column, next_row := column + int(offset[0]), row + int(offset[1])
				if next_column < 0 || next_row < 0 || next_column >= grid.side || next_row >= grid.side {
					continue
				}
				next := next_row * grid.side + next_column
				if seen[next] || grid.filled[next] <= grid.heights[next] {
					continue
				}
				seen[next] = true
				append(&queue, next)
			}
		}
		append(&depressions, depression)
	}
	return depressions
}

// The lake's plane at a step: its centre and tangents on the sphere of
// the radius.
planet_lake_plane :: proc(lake: Planet_Lake, radius, step: i64) -> Waters_Plane {
	return Waters_Plane{lake.centre, lake.east, lake.north, radius, step}
}

// The mask's bit of the cell; false outside the window.
planet_lake_mask_bit :: proc(lake: Planet_Lake, u, v: i64) -> bool {
	if abs(u) > lake.half || abs(v) > lake.half {
		return false
	}
	index := (v + lake.half) * (2 * lake.half + 1) + u + lake.half
	return lake.mask[index >> 6] & (u64(1) << uint(index & 63)) != 0
}

// Whether the lake's mask holds a point on the sphere of the radius: its
// LAKE_CELL_METRES cell, rounded to the nearest, inside the window and
// set. The generation, the trees, the coarse grids and the relief map
// read the lakes only through it.
planet_lake_holds :: proc(lake: Planet_Lake, on_sphere: [3]i64, radius: i64) -> bool {
	plane := planet_lake_plane(lake, radius, metres_to_position_units(LAKE_CELL_METRES))
	east, north, ok := waters_plane_coordinates(plane, on_sphere)
	if !ok {
		return false
	}
	return planet_lake_mask_bit(lake, floor_divide_i64(east + plane.step / 2, plane.step), floor_divide_i64(north + plane.step / 2, plane.step))
}

// The level of the first lake in order holding the point on the sphere.
planet_lake_level_at :: proc(lakes: []Planet_Lake, on_sphere: [3]i64, radius: i64) -> (level: i64, found: bool) {
	for lake in lakes {
		if planet_lake_holds(lake, on_sphere, radius) {
			return lake.level, true
		}
	}
	return 0, false
}

lake_window_index :: proc(window: ^Lake_Window, u, v: i64) -> i64 {
	return (v + window.half) * window.side + u + window.half
}

// The relief at the window's cell, read once.
lake_window_height :: proc(window: ^Lake_Window, u, v: i64) -> i64 {
	index := lake_window_index(window, u, v)
	if !window.known[index] {
		window.heights[index] = waters_plane_height(window.generation, window.plane, u, v)
		window.known[index] = true
	}
	return window.heights[index]
}

// The lake round a depression's pit (a unit direction), on a
// LAKE_CELL_METRES grid of half lake_maximum_metres either side: a descent
// to the local minimum, then a priority flood from there that passes
// saddles under the coarse level less WATERS_REFINE_TOLERANCE_METRES and
// stops at the first one over it (the pour point) or at the sea. The level
// is that sill less the margin, the water the pit's 4-connected claimed
// cells under it, the mask the water grown by one 8-neighbour cell, then
// sealed (seal_planet_lake). Refused too big (the flood reaching the
// window's edge), too shallow, too small, unsealed, or with a water cell
// less than the widest sample spacing over the sea: the generation gives
// the sea every air sample whose span reaches under its level
// (fill_field_chunk_sea), so such a lake would hold sea and drain into it.
refine_planet_lake :: proc(generation: Planet_Generation, waters: Planet_Waters, pit: [3]i64, coarse_level: i64, allocator := context.allocator) -> (lake: Planet_Lake, ok: bool) {
	east, north := planet_tangents(pit)
	half := i64(waters.lake_maximum_metres / (2 * LAKE_CELL_METRES))
	side := 2 * half + 1
	window := Lake_Window {
		generation = generation,
		plane      = {pit, east, north, generation.radius, metres_to_position_units(LAKE_CELL_METRES)},
		half       = half,
		side       = side,
		heights    = make([]i64, side * side, context.temp_allocator),
		known      = make([]bool, side * side, context.temp_allocator),
	}
	u, v: i64 = 0, 0
	for _ in 0 ..< LAKE_DESCENT_STEPS {
		best_u, best_v, best := u, v, lake_window_height(&window, u, v)
		for offset in WATERS_NEIGHBOURS {
			next_u, next_v := u + offset[0], v + offset[1]
			if abs(next_u) > half || abs(next_v) > half {
				continue
			}
			if height := lake_window_height(&window, next_u, next_v); height < best {
				best_u, best_v, best = next_u, next_v, height
			}
		}
		if best_u == u && best_v == v {
			break
		}
		u, v = best_u, best_v
	}
	start := lake_window_index(&window, u, v)
	floor := lake_window_height(&window, u, v)
	claimed := make([]bool, side * side, context.temp_allocator)
	pushed := make([]bool, side * side, context.temp_allocator)
	heap := make([dynamic]Waters_Entry, context.temp_allocator)
	push_waters_entry(&heap, {floor, i32(start)})
	pushed[start] = true
	sill := floor
	spilled := false
	tolerance := metres_to_position_units(WATERS_REFINE_TOLERANCE_METRES)
	sea := generation.sea_radius - generation.radius
	for len(heap) > 0 {
		entry := pop_waters_entry(&heap)
		if (entry.height < sill && sill >= coarse_level - tolerance) || entry.height < sea {
			spilled = true
			break
		}
		sill = max(sill, entry.height)
		claimed[entry.index] = true
		cell_u, cell_v := i64(entry.index) % side - half, i64(entry.index) / side - half
		for offset in WATERS_NEIGHBOURS {
			next_u, next_v := cell_u + offset[0], cell_v + offset[1]
			if abs(next_u) >= half || abs(next_v) >= half {
				return {}, false
			}
			next := lake_window_index(&window, next_u, next_v)
			if pushed[next] {
				continue
			}
			pushed[next] = true
			push_waters_entry(&heap, {lake_window_height(&window, next_u, next_v), i32(next)})
		}
	}
	if !spilled {
		return {}, false
	}
	minimum_depth := millimetres_to_position_units(waters.lake_minimum_depth_millimetres)
	level := sill - millimetres_to_position_units(waters.lake_margin_millimetres)
	if level - floor < minimum_depth {
		return {}, false
	}
	water := make([]bool, side * side, context.temp_allocator)
	queue := make([dynamic]i64, context.temp_allocator)
	append(&queue, start)
	water[start] = true
	for head := 0; head < len(queue); head += 1 {
		cell := queue[head]
		cell_u, cell_v := cell % side - half, cell / side - half
		for offset in WATERS_FACES {
			next := lake_window_index(&window, cell_u + offset[0], cell_v + offset[1])
			if water[next] || !claimed[next] || window.heights[next] >= level {
				continue
			}
			water[next] = true
			append(&queue, next)
		}
	}
	if i64(len(queue)) * LAKE_CELL_METRES * LAKE_CELL_METRES < i64(waters.lake_minimum_area_square_metres) {
		return {}, false
	}
	clearance := millimetres_to_position_units(WIDEST_SAMPLE_SPACING_MILLIMETRES)
	for cell in queue {
		if window.heights[cell] - sea < clearance {
			return {}, false
		}
	}
	lake = Planet_Lake {
		centre = pit,
		east   = east,
		north  = north,
		origin = fixed_scale(waters_plane_direction(window.plane, u, v), generation.radius),
		level  = level,
		floor  = floor,
		half   = half,
		cells  = i32(len(queue)),
		mask   = make([]u64, (side * side + 63) / 64, allocator),
	}
	for cell in queue {
		cell_u, cell_v := cell % side - half, cell / side - half
		set_planet_lake_mask_bit(&lake, cell_u, cell_v)
		for offset in WATERS_NEIGHBOURS {
			set_planet_lake_mask_bit(&lake, cell_u + offset[0], cell_v + offset[1])
		}
	}
	sealed, sealed_ok := seal_planet_lake(generation, &lake)
	if !sealed_ok || sealed - floor < minimum_depth {
		delete(lake.mask, allocator)
		return {}, false
	}
	lake.level = sealed
	lake.bound_centre = fixed_scale(pit, generation.radius + lake.level)
	lake.bound_radius = (half + 1) * window.plane.step * 3 / 2 + (lake.level - floor) + metres_to_position_units(2)
	return lake, true
}

// Sets the mask's bit of the cell; nothing outside the window.
set_planet_lake_mask_bit :: proc(lake: ^Planet_Lake, u, v: i64) {
	if abs(u) > lake.half || abs(v) > lake.half {
		return
	}
	index := (v + lake.half) * (2 * lake.half + 1) + u + lake.half
	lake.mask[index >> 6] |= u64(1) << uint(index & 63)
}

// Whether the mask holds the 1 m lattice point: its LAKE_CELL_METRES cell.
planet_lake_lattice_holds :: proc(lake: Planet_Lake, x, y: i64) -> bool {
	return planet_lake_mask_bit(lake, floor_divide_i64(x + 1, 2), floor_divide_i64(y + 1, 2))
}

// The relief at the lake plane's 1 m lattice point, read once.
lake_lattice_height :: proc(generation: Planet_Generation, plane: Waters_Plane, heights: ^map[[2]i64]i64, x, y: i64) -> i64 {
	if height, found := heights[{x, y}]; found {
		return height
	}
	height := waters_plane_height(generation, plane, x, y)
	heights[{x, y}] = height
	return height
}

// The shore's check on the lake plane's 1 m lattice: a point in the mask
// under the level beside one outside it lower than the level leaks, and
// the level drops to the lowest such outside point, for at most
// LAKE_SEAL_ROUNDS rounds; ok when a round finds none.
seal_planet_lake :: proc(generation: Planet_Generation, lake: ^Planet_Lake) -> (level: i64, ok: bool) {
	plane := planet_lake_plane(lake^, generation.radius, metres_to_position_units(1))
	reach := 2 * lake.half
	heights := make(map[[2]i64]i64, context.temp_allocator)
	faces := WATERS_FACES
	level = lake.level
	for _ in 0 ..< LAKE_SEAL_ROUNDS {
		lowest := level
		for y in -reach ..= reach {
			for x in -reach ..= reach {
				if !planet_lake_lattice_holds(lake^, x, y) {
					continue
				}
				shore := false
				for offset in faces {
					shore ||= !planet_lake_lattice_holds(lake^, x + offset[0], y + offset[1])
				}
				if !shore || lake_lattice_height(generation, plane, &heights, x, y) >= level {
					continue
				}
				for offset in faces {
					if !planet_lake_lattice_holds(lake^, x + offset[0], y + offset[1]) {
						lowest = min(lowest, lake_lattice_height(generation, plane, &heights, x + offset[0], y + offset[1]))
					}
				}
			}
		}
		if lowest >= level {
			return level, true
		}
		level = lowest
	}
	return level, false
}

// The lakes of the grid's depressions in order: none at the border,
// shallower than the minimum depth, smaller than half the minimum area,
// with its pit in the clearing or in a lake kept before; each refined at
// its pit and kept when its refined pit lies outside the clearing, at most
// MAXIMUM_PLANET_LAKES.
find_planet_lakes :: proc(grid: ^Waters_Grid, generation: Planet_Generation, waters: Planet_Waters, home: [3]i64, allocator := context.allocator) -> []Planet_Lake {
	lakes := make([dynamic]Planet_Lake, allocator)
	clearing := metres_to_position_units(i64(waters.clearing_metres))
	home_point := fixed_scale(home, generation.radius)
	minimum_depth := millimetres_to_position_units(waters.lake_minimum_depth_millimetres)
	cell_area := waters.grid_metres * waters.grid_metres
	for depression in find_waters_depressions(grid) {
		if len(lakes) >= MAXIMUM_PLANET_LAKES {
			break
		}
		if depression.border || depression.level - depression.floor < minimum_depth || depression.cells * cell_area < waters.lake_minimum_area_square_metres / 2 {
			continue
		}
		pit := waters_plane_direction(grid.plane, i64(depression.pit % grid.side - grid.half), i64(depression.pit / grid.side - grid.half))
		pit_point := fixed_scale(pit, generation.radius)
		if squared_chord(pit_point, home_point) < clearing * clearing {
			continue
		}
		if _, inside := planet_lake_level_at(lakes[:], pit_point, generation.radius); inside {
			continue
		}
		lake, ok := refine_planet_lake(generation, waters, pit, depression.level, allocator)
		if !ok {
			continue
		}
		if squared_chord(lake.origin, home_point) < clearing * clearing {
			delete(lake.mask, allocator)
			continue
		}
		append(&lakes, lake)
	}
	return lakes[:]
}

// A spring candidate with its grid cell, the sort's last key.
Waters_Spring_Candidate :: struct {
	spring: Planet_Water_Spring,
	cell:   int,
}

// The channel heads of the drainage: a cell draining the catchment with
// no donor that does, not in a depression, at least spring_minimum_metres
// over the sea, WATERS_BORDER_CELLS inside the edge, outside the clearing
// and in no lake under its level; to_sea when its outlet lies under the
// sea. Sorted by to_sea first, then the larger drop, then the lower cell,
// and kept at least spring_spacing_metres from every record spring and
// every one kept before, at most MAXIMUM_DERIVED_SPRINGS.
find_planet_springs :: proc(grid: ^Waters_Grid, waters: Planet_Waters, lakes: []Planet_Lake, record: []Planet_Spring, home: [3]i64, sea, radius: i64, allocator := context.allocator) -> []Planet_Water_Spring {
	count := grid.side * grid.side
	catchment := i32(waters.spring_catchment_square_metres / (waters.grid_metres * waters.grid_metres))
	draining := make([]bool, count, context.temp_allocator)
	for cell in 0 ..< count {
		if parent := grid.parent[cell]; parent >= 0 && grid.area[cell] >= catchment {
			draining[parent] = true
		}
	}
	minimum := sea + metres_to_position_units(i64(waters.spring_minimum_metres))
	clearing := metres_to_position_units(i64(waters.clearing_metres))
	home_point := fixed_scale(home, radius)
	candidates := make([dynamic]Waters_Spring_Candidate, context.temp_allocator)
	for cell in 0 ..< count {
		height := grid.heights[cell]
		if grid.area[cell] < catchment || draining[cell] || grid.filled[cell] != height || height < minimum {
			continue
		}
		column, row := cell % grid.side, cell / grid.side
		if column < WATERS_BORDER_CELLS || row < WATERS_BORDER_CELLS || column >= grid.side - WATERS_BORDER_CELLS || row >= grid.side - WATERS_BORDER_CELLS {
			continue
		}
		direction := waters_plane_direction(grid.plane, i64(column - grid.half), i64(row - grid.half))
		point := fixed_scale(direction, radius)
		if squared_chord(point, home_point) < clearing * clearing {
			continue
		}
		if level, found := planet_lake_level_at(lakes, point, radius); found && height < level {
			continue
		}
		outlet := grid.heights[grid.outlet[cell]]
		to_sea := outlet < sea
		append(&candidates, Waters_Spring_Candidate{spring = {direction = direction, height = height, drop = height - (to_sea ? sea : outlet), to_sea = to_sea}, cell = cell})
	}
	slice.sort_by(candidates[:], proc(first, second: Waters_Spring_Candidate) -> bool {
		if first.spring.to_sea != second.spring.to_sea {
			return first.spring.to_sea
		}
		if first.spring.drop != second.spring.drop {
			return first.spring.drop > second.spring.drop
		}
		return first.cell < second.cell
	})
	spacing := metres_to_position_units(i64(waters.spring_spacing_metres))
	kept := make([dynamic][3]i64, context.temp_allocator)
	for spring in record {
		append(&kept, fixed_scale(planet_spring_direction(spring), radius))
	}
	springs := make([dynamic]Planet_Water_Spring, allocator)
	for candidate in candidates {
		if len(springs) >= MAXIMUM_DERIVED_SPRINGS {
			break
		}
		point := fixed_scale(candidate.spring.direction, radius)
		near := false
		for other in kept {
			near ||= squared_chord(point, other) < spacing * spacing
		}
		if near {
			continue
		}
		append(&kept, point)
		append(&springs, candidate.spring)
	}
	return springs[:]
}

// The grid cell nearest a unit direction; false outside the grid
// WATERS_BORDER_CELLS from its edge or behind its plane.
waters_grid_cell :: proc(grid: ^Waters_Grid, direction: [3]i64) -> (cell: int, inside: bool) {
	east, north, ok := waters_plane_coordinates(grid.plane, fixed_scale(direction, grid.plane.radius))
	if !ok {
		return 0, false
	}
	step := grid.plane.step
	column := int(floor_divide_i64(east + step / 2, step)) + grid.half
	row := int(floor_divide_i64(north + step / 2, step)) + grid.half
	if column < WATERS_BORDER_CELLS || row < WATERS_BORDER_CELLS || column >= grid.side - WATERS_BORDER_CELLS || row >= grid.side - WATERS_BORDER_CELLS {
		return 0, false
	}
	return row * grid.side + column, true
}

// The tech demo's start: of the springs draining to the sea, the record's
// in order (a cell inside the grid whose outlet lies under the sea, its
// fall the cell's height over the sea, its own direction kept) and then
// the derived ones, the largest fall, the first on a tie.
planet_water_start :: proc(grid: ^Waters_Grid, record: []Planet_Spring, springs: []Planet_Water_Spring, sea: i64) -> (start: [3]i64, found: bool) {
	best: i64
	for spring in record {
		direction := planet_spring_direction(spring)
		cell, inside := waters_grid_cell(grid, direction)
		if !inside || grid.heights[grid.outlet[cell]] >= sea {
			continue
		}
		if fall := grid.heights[cell] - sea; !found || fall > best {
			start, best, found = direction, fall, true
		}
	}
	for spring in springs {
		if spring.to_sea && (!found || spring.drop > best) {
			start, best, found = spring.direction, spring.drop, true
		}
	}
	return
}

// The planet's waters from the seed and the record: nothing when its
// waters are off or found in tiles (0326); else the grid round the home,
// its flood, the lakes, the springs and the start, the grid freed.
make_planet_water_features :: proc(seed: u64, planet: Planet, allocator := context.allocator) -> Planet_Water_Features {
	if planet.waters == {} || planet.waters.tile_metres > 0 {
		return {}
	}
	generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	home := planet_home_direction(planet.home)
	sea := generation.sea_radius - generation.radius
	grid := make_waters_grid(generation, home, planet.waters, planet.radius_metres)
	defer destroy_waters_grid(&grid)
	flood_waters_grid(&grid, sea)
	features: Planet_Water_Features
	features.lakes = find_planet_lakes(&grid, generation, planet.waters, home, allocator)
	features.springs = find_planet_springs(&grid, planet.waters, features.lakes, planet.springs, home, sea, generation.radius, allocator)
	features.start, features.has_start = planet_water_start(&grid, planet.springs, features.springs, sea)
	return features
}

// A lake's level in fill units from the centre at the generation's
// spacing, field_sea_level's formula.
planet_lake_fill_level :: proc(generation: Planet_Generation, lake: Planet_Lake) -> i64 {
	return floor_divide_i64((generation.radius + lake.level) * FIELD_WATER_FULL * MILLIMETRES_PER_METRE, i64(generation.spacing_millimetres) * POSITION_UNITS_PER_METRE)
}

// Whether the lake's bound meets the box: the squared distance from its
// centre to the box at most its radius squared.
planet_lake_meets_box :: proc(lake: Planet_Lake, minimum, maximum: [3]i64) -> bool {
	squared: i64 = 0
	for axis in 0 ..< 3 {
		gap := max(minimum[axis] - lake.bound_centre[axis], lake.bound_centre[axis] - maximum[axis], 0)
		squared += gap * gap
	}
	return squared <= lake.bound_radius * lake.bound_radius
}

// The lakes whose bound meets the box, in order (temp allocator).
planet_lakes_meeting_box :: proc(lakes: []Planet_Lake, minimum, maximum: [3]i64) -> []Planet_Lake {
	listed := make([dynamic]Planet_Lake, context.temp_allocator)
	for lake in lakes {
		if planet_lake_meets_box(lake, minimum, maximum) {
			append(&listed, lake)
		}
	}
	return listed[:]
}

// The box's centre's unit direction and its half diagonal, at most a
// coarsest node's (WATER_QUERY_BOX_METRES, 0326).
water_query_box :: proc(minimum, maximum: [3]i64) -> (direction: [3]i64, half: i64) {
	direction, _ = normalize_fixed((minimum + maximum) / 2)
	half = vector_length(maximum - minimum) / 2
	assert(half <= metres_to_position_units(WATER_QUERY_BOX_METRES) / 2, "a box that asks for lakes is at most a coarsest node's")
	return
}

// The lakes whose bound meets the box: the planet's without tiles; with
// them (0326) the kept lakes of the tiles within a lake's reach and twice
// the box's half diagonal of its centre, which bounds the box's points
// projected onto the sphere, in water_lake_before's order.
generation_lakes_meeting_box :: proc(generation: Planet_Generation, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> []Planet_Lake {
	if generation.water_tiles == nil {
		return planet_lakes_meeting_box(generation.lakes, minimum, maximum)
	}
	direction, half := water_query_box(minimum, maximum)
	listed := make([dynamic]Planet_Lake, allocator)
	for lake in water_tile_lakes_near(generation.water_tiles, direction, generation.water_tiles.lake_reach + 2 * half, allocator) {
		if planet_lake_meets_box(lake, minimum, maximum) {
			append(&listed, lake)
		}
	}
	return listed[:]
}

// The lakes whose mask may hold a point of the sphere of the radius in
// the box, as a tree's key point lies (planet_trees_in_box): the planet's
// without tiles; with them (0326) the tiles' kept lakes whose pit lies
// within a lake's reach of the box. A lake's bound sits at its level, which
// can stand farther over the sphere than the bound's radius, so the bound
// is no test here.
generation_lakes_near_sphere_box :: proc(generation: Planet_Generation, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> []Planet_Lake {
	if generation.water_tiles == nil {
		return generation.lakes
	}
	direction, half := water_query_box(minimum, maximum)
	reach := generation.water_tiles.lake_reach
	listed := make([dynamic]Planet_Lake, allocator)
	for lake in water_tile_lakes_near(generation.water_tiles, direction, reach + 2 * half, allocator) {
		pit := fixed_scale(lake.centre, generation.radius)
		squared: i64 = 0
		for axis in 0 ..< 3 {
			gap := max(minimum[axis] - pit[axis], pit[axis] - maximum[axis], 0)
			squared += gap * gap
		}
		if squared <= reach * reach {
			append(&listed, lake)
		}
	}
	return listed[:]
}

// The derived springs a chunk may hold: the planet's without tiles; with
// them (0326) the tiles' within 32 spacings of the chunk's centre, more than
// planet_spring_may_lie_in_chunk's 29.
planet_derived_springs_near_chunk :: proc(generation: Planet_Generation, planet: Planet, coordinate: Field_Chunk_Coordinate) -> []Planet_Water_Spring {
	if generation.water_tiles == nil {
		return planet.water_features.springs
	}
	origin := field_chunk_origin(coordinate)
	first := cast([3]i64)sample_to_world_position(origin, generation.spacing_millimetres)
	last := cast([3]i64)sample_to_world_position(origin + FIELD_CHUNK_SIZE - 1, generation.spacing_millimetres)
	direction, _ := normalize_fixed((first + last) / 2)
	return water_tile_springs_near(generation.water_tiles, direction, 32 * generation.spacing)
}

// Every air sample of the chunk with no water (the sea's, a spring's) that
// a lake's mask holds takes the first such lake's fill under its level,
// asleep and no one's, as the sea is filled; carved air (column_carves,
// 0324, the bits from generate_field_chunk) stays dry. The lakes are the
// features' or the tiles' (0326, generation_lakes_meeting_box).
fill_field_chunk_lakes :: proc(generation: Planet_Generation, chunk: ^Field_Chunk, carved: ^Field_Sample_Bits) {
	if len(generation.lakes) == 0 && generation.water_tiles == nil {
		return
	}
	origin := field_chunk_origin(chunk.coordinate)
	minimum := cast([3]i64)sample_to_world_position(origin, generation.spacing_millimetres)
	maximum := cast([3]i64)sample_to_world_position(origin + FIELD_CHUNK_SIZE - 1, generation.spacing_millimetres)
	listed := generation_lakes_meeting_box(generation, minimum, maximum)
	if len(listed) == 0 {
		return
	}
	highest := min(i64)
	for lake in listed {
		highest = max(highest, planet_lake_fill_level(generation, lake))
	}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if chunk.density[index] > 0 || chunk.water[index] != 0 || field_sample_bit(carved, index) {
			continue
		}
		sample := origin + Sample_Coordinate(field_index_to_local(index))
		span := field_water_span(sample)
		if field_water_bottom(span) >= highest {
			continue
		}
		position := sample_to_world_position(sample, generation.spacing_millimetres)
		on_sphere := project_onto_sphere(position, vector_length(cast([3]i64)position), generation.radius)
		for lake in listed {
			if !planet_lake_holds(lake, on_sphere, generation.radius) {
				continue
			}
			if fill := field_sea_fill(planet_lake_fill_level(generation, lake), span); fill > 0 {
				chunk.water[index] = u8(fill)
			}
			break
		}
	}
}

// A listed lake's density in the generation's spacing at a position, as
// the sea's (planet_sea_density): positive under its level,
// -MAXIMUM_DENSITY in ground or where no listed lake holds the point.
planet_lake_density :: proc(generation: Planet_Generation, lakes: []Planet_Lake, position: World_Position, terrain: i8) -> i8 {
	if terrain > 0 {
		return -MAXIMUM_DENSITY
	}
	distance := vector_length(cast([3]i64)position)
	on_sphere := project_onto_sphere(position, distance, generation.radius)
	for lake in lakes {
		if planet_lake_holds(lake, on_sphere, generation.radius) {
			return depth_to_density(generation.radius + lake.level - distance, generation.spacing_millimetres)
		}
	}
	return -MAXIMUM_DENSITY
}

// Whether a spring at the direction may have its sample in the chunk: the
// radial passes within 29 spacings (the half diagonal of 32 samples and
// one more) of the chunk's centre, on its side of the planet.
planet_spring_may_lie_in_chunk :: proc(generation: Planet_Generation, direction: [3]i64, coordinate: Field_Chunk_Coordinate) -> bool {
	origin := field_chunk_origin(coordinate)
	first := cast([3]i64)sample_to_world_position(origin, generation.spacing_millimetres)
	last := cast([3]i64)sample_to_world_position(origin + FIELD_CHUNK_SIZE - 1, generation.spacing_millimetres)
	centre := (first + last) / 2
	along := fixed_dot(centre, direction)
	if along <= 0 {
		return false
	}
	return vector_length(centre - fixed_scale(direction, along)) <= 29 * generation.spacing
}
