package game

import "core:slice"
import "platform"

// Level of detail of the field (work item 0169, doc/presentation.md, Chunk
// meshes): an octree over field chunks. A node of level L covers 2^L
// chunks a side and meshes FIELD_GRID_CELLS cells a side, so its grid
// samples every 2^L-th sample: level 0 is a chunk at full resolution, 1 to
// 3 are half, quarter and eighth. The level of a node follows its distance
// from the camera, against one distance per level from data/game.sjson
// (field_view.level_distances_metres); beyond the last one nothing is
// drawn but the globe. The coarser levels are generated straight into
// their grid from the planet (generate_field_grid), the finest is meshed
// from the loaded chunks.
//
// Neighbouring nodes of different levels do not meet, so every node's mesh
// hangs a skirt from its open border, an L shaped flap out of the node and
// into the ground (append_field_skirts) that covers the seam seen from
// above. Everything
// here is integer: positions in World_Position units, distances squared.

// FIELD_LEVEL_COUNT is with the data that sets the levels' distances
// (data_load.odin).
FIELD_COARSEST_LEVEL :: FIELD_LEVEL_COUNT - 1
// A skirt reaches one cell of the next coarser level out and down.
FIELD_SKIRT_REACH :: 2 * FIELD_MESH_POSITION_UNITS
// The most vertices a node's mesh can hold: one per cell that can carry a
// vertex, and two more per border cell for the skirt.
FIELD_MESH_VERTEX_BOUND :: FIELD_VERTEX_CELL_COUNT + 2 * (FIELD_VERTEX_CELL_COUNT - (FIELD_GRID_CELLS - 1) * (FIELD_GRID_CELLS - 1) * (FIELD_GRID_CELLS - 1))
#assert(FIELD_MESH_VERTEX_BOUND <= MESH_PART_VERTEX_LIMIT, "a field node's mesh fits the u16 indices")
// The planet check of the view distances (field_view_problem) takes the
// finest node's width at the widest spacing.
#assert(FIELD_FINEST_NODE_MAXIMUM_METRES * MILLIMETRES_PER_METRE == FIELD_CHUNK_SIZE * SAMPLE_SPACING_CHOICES_MILLIMETRES[len(SAMPLE_SPACING_CHOICES_MILLIMETRES) - 1])

// coordinate counts nodes of its level: the node's first chunk is
// coordinate times 2^level.
Field_Node :: struct {
	level:      i32,
	coordinate: [3]i32,
}

Field_Box :: struct {
	minimum, maximum: World_Position,
}

// What choosing the nodes reads, in World_Position units. The shell holds
// every surface the generation can make: the radius plus or minus the
// relief and a node's margin.
Field_View :: struct {
	camera:              World_Position,
	level_distances:     [FIELD_LEVEL_COUNT]i64,
	shell_inner:         i64,
	shell_outer:         i64,
	spacing_millimetres: int,
}

Field_Node_Distance :: struct {
	node:             Field_Node,
	distance_squared: i64,
}

// Samples a node of the level covers on each axis.
field_node_samples :: proc(level: i32) -> i32 {
	return FIELD_CHUNK_SIZE << uint(level)
}

field_node_step :: proc(node: Field_Node) -> i32 {
	return 1 << uint(node.level)
}

field_node_origin :: proc(node: Field_Node) -> Sample_Coordinate {
	return Sample_Coordinate(node.coordinate * field_node_samples(node.level))
}

// The finest level's node of a chunk, and back.
field_chunk_node :: proc(coordinate: Field_Chunk_Coordinate) -> Field_Node {
	return {0, ([3]i32)(coordinate)}
}

field_node_chunk :: proc(node: Field_Node) -> Field_Chunk_Coordinate {
	return Field_Chunk_Coordinate(node.coordinate)
}

field_node_box :: proc(node: Field_Node, spacing_millimetres: int) -> Field_Box {
	origin := field_node_origin(node)
	return {sample_to_world_position(origin, spacing_millimetres), sample_to_world_position(origin + field_node_samples(node.level), spacing_millimetres)}
}

// From the point to the nearest point of the box.
box_distance_squared :: proc(box: Field_Box, point: World_Position) -> i64 {
	total: i64 = 0
	for axis in 0 ..< 3 {
		nearest := clamp(point[axis], box.minimum[axis], box.maximum[axis])
		total += (point[axis] - nearest) * (point[axis] - nearest)
	}
	return total
}

// From the point to the farthest corner of the box.
box_farthest_distance_squared :: proc(box: Field_Box, point: World_Position) -> i64 {
	total: i64 = 0
	for axis in 0 ..< 3 {
		reach := max(abs(point[axis] - box.minimum[axis]), abs(point[axis] - box.maximum[axis]))
		total += reach * reach
	}
	return total
}

// The finest level whose distance the node lies within; none beyond the
// last distance.
field_level_for_distance :: proc(distance_squared: i64, level_distances: [FIELD_LEVEL_COUNT]i64) -> (level: i32, visible: bool) {
	for distance, index in level_distances {
		if distance_squared < distance * distance {
			return i32(index), true
		}
	}
	return 0, false
}

field_box_in_shell :: proc(box: Field_Box, inner, outer: i64) -> bool {
	return box_distance_squared(box, {}) <= outer * outer && box_farthest_distance_squared(box, {}) >= inner * inner
}

make_field_view :: proc(camera: World_Position, planet: Planet, spacing_millimetres: int, level_distances_metres: [FIELD_LEVEL_COUNT]int) -> Field_View {
	radius := metres_to_position_units(i64(planet.radius_metres))
	margin := metres_to_position_units(MAXIMUM_RELIEF_METRES) + 2 * sample_axis_to_position(1, spacing_millimetres)
	view := Field_View {
		camera              = camera,
		shell_inner         = radius - margin,
		shell_outer         = radius + margin,
		spacing_millimetres = spacing_millimetres,
	}
	for distance, level in level_distances_metres {
		view.level_distances[level] = metres_to_position_units(i64(distance))
	}
	return view
}

// The node, or its children where the camera is near enough for a finer
// level. Nodes outside the surface shell or beyond the last distance hold
// nothing to draw. Nodes above the coarsest level only split, so the walk
// visits the nodes crossing the shell near the camera and never the empty
// volume around it.
select_field_node :: proc(view: Field_View, node: Field_Node, selected: ^[dynamic]Field_Node_Distance) {
	box := field_node_box(node, view.spacing_millimetres)
	if !field_box_in_shell(box, view.shell_inner, view.shell_outer) {
		return
	}
	distance_squared := box_distance_squared(box, view.camera)
	level, visible := field_level_for_distance(distance_squared, view.level_distances)
	if !visible {
		return
	}
	if node.level <= FIELD_COARSEST_LEVEL && level >= node.level {
		append(selected, Field_Node_Distance{node, distance_squared})
		return
	}
	for child in 0 ..< 8 {
		select_field_node(view, Field_Node{node.level - 1, node.coordinate * 2 + field_corner_offset(child)}, selected)
	}
}

field_node_distance_before :: proc(first, second: Field_Node_Distance) -> bool {
	return first.distance_squared < second.distance_squared
}

// The first level from the coarsest up whose nodes are as wide as the last
// distance, so the 27 nodes around the camera's hold everything within it.
field_walk_top_level :: proc(view: Field_View) -> i32 {
	level := i32(FIELD_COARSEST_LEVEL)
	for sample_axis_to_position(field_node_samples(level), view.spacing_millimetres) < view.level_distances[FIELD_COARSEST_LEVEL] {
		level += 1
	}
	return level
}

// The nodes to draw, split down the octree from the 27 nodes of the walk's
// top level around the camera; nearest first, so streaming serves the near
// ones first.
select_field_nodes :: proc(view: Field_View, allocator := context.allocator) -> []Field_Node {
	top := field_walk_top_level(view)
	node_size := sample_axis_to_position(field_node_samples(top), view.spacing_millimetres)
	centre: [3]i32
	for axis in 0 ..< 3 {
		centre[axis] = i32(floor_divide_i64(view.camera[axis], node_size))
	}
	selected := make([dynamic]Field_Node_Distance, context.temp_allocator)
	for child in 0 ..< 27 {
		offset := [3]i32{i32(child % 3), i32(child / 3 % 3), i32(child / 9)} - 1
		select_field_node(view, Field_Node{top, centre + offset}, &selected)
	}
	slice.sort_by(selected[:], field_node_distance_before)
	nodes := make([]Field_Node, len(selected), allocator)
	for entry, index in selected {
		nodes[index] = entry.node
	}
	return nodes
}

// The generation a grid of this step reads: positions as given, densities
// in units of the step's spacing. planet_sample saturates a density one
// spacing from the surface, so with the fine spacing a coarse edge would
// read the full density at both ends and its crossing would land in the
// middle, terracing the slopes; in the coarse spacing the densities stay
// linear across every coarse cell the surface crosses.
field_grid_generation :: proc(generation: Planet_Generation, step: i32) -> Planet_Generation {
	coarse := generation
	coarse.spacing_millimetres = generation.spacing_millimetres * int(step)
	coarse.spacing = sample_axis_to_position(1, coarse.spacing_millimetres)
	return coarse
}

// The node's grid straight from the generation, every step-th sample;
// safe on any thread.
generate_field_grid :: proc(generation: Planet_Generation, node: Field_Node, grid: ^Field_Grid) {
	grid.origin = field_node_origin(node)
	grid.step = field_node_step(node)
	density_generation := field_grid_generation(generation, grid.step)
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := grid.origin + Sample_Coordinate([3]i32{x, y, z} * grid.step)
				value := planet_sample(density_generation, sample_to_world_position(sample, generation.spacing_millimetres))
				index := field_grid_index({x, y, z})
				grid.density[index], grid.material[index], grid.tint[index] = value.density, value.material, value.tint
			}
		}
	}
}

// Undirected, the lower index in the high half.
field_edge_key :: proc(first, second: u16) -> u32 {
	return u32(min(first, second)) << 16 | u32(max(first, second))
}

// How many triangles of the surface use each edge.
count_field_edges :: proc(indices: []u16, allocator := context.allocator) -> map[u32]int {
	counts := make(map[u32]int, allocator)
	for triangle := 0; triangle + 2 < len(indices); triangle += 3 {
		for corner in 0 ..< 3 {
			counts[field_edge_key(indices[triangle + corner], indices[triangle + (corner + 1) % 3])] += 1
		}
	}
	return counts
}

// Out of the node from a vertex in a border cell: -1 or 1 on each axis
// whose border it sits in, 0 elsewhere.
field_skirt_outward :: proc(position: [3]i32) -> [3]i32 {
	outward: [3]i32
	for axis in 0 ..< 3 {
		cell := floor_divide(position[axis], FIELD_MESH_POSITION_UNITS)
		outward[axis] = cell < 0 ? -1 : (cell >= FIELD_GRID_CELLS - 1 ? 1 : 0)
	}
	return outward
}

// The vector scaled to length; zero for a zero vector. In i64, since the
// tangent's components reach the cube of a gradient's.
field_scaled_vector :: proc(vector: [3]i64, length: i64) -> [3]i32 {
	magnitude := i64(integer_square_root(u64(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)))
	if magnitude == 0 {
		return {}
	}
	return {i32(vector.x * length / magnitude), i32(vector.y * length / magnitude), i32(vector.z * length / magnitude)}
}

// The outward direction with its part along the gradient removed, so the
// flap's first leg runs along the surface's slope instead of out of it.
field_skirt_tangent :: proc(outward, gradient: [3]i32) -> [3]i64 {
	along := [3]i64{i64(outward.x), i64(outward.y), i64(outward.z)}
	slope := [3]i64{i64(gradient.x), i64(gradient.y), i64(gradient.z)}
	return along * (slope.x * slope.x + slope.y * slope.y + slope.z * slope.z) - slope * (along.x * slope.x + along.y * slope.y + along.z * slope.z)
}

// The flap's two vertices below a border vertex: one coarse cell out of
// the node along the surface and half a coarse cell into the ground, then
// a coarse cell further into the ground.
field_skirt_vertices :: proc(vertex: Field_Surface_Vertex) -> (outer, lower: Field_Surface_Vertex) {
	gradient := [3]i64{i64(vertex.gradient.x), i64(vertex.gradient.y), i64(vertex.gradient.z)}
	outer, lower = vertex, vertex
	outer.position += field_scaled_vector(field_skirt_tangent(field_skirt_outward(vertex.position), vertex.gradient), FIELD_SKIRT_REACH) + field_scaled_vector(gradient, FIELD_SKIRT_REACH / 2)
	lower.position = outer.position + field_scaled_vector(gradient, FIELD_SKIRT_REACH)
	return outer, lower
}

// The flap's first vertex of a border vertex, made the first time an edge
// asks; the second follows it.
field_skirt_vertex_index :: proc(surface: ^Field_Surface, skirt_vertices: []i32, vertex: u16) -> u16 {
	slot := &skirt_vertices[vertex]
	if slot^ < 0 {
		slot^ = i32(len(surface.vertices))
		outer, lower := field_skirt_vertices(surface.vertices[vertex])
		append(&surface.vertices, outer, lower)
	}
	return u16(slot^)
}

// The edges only one triangle uses, which is the node's open border, as
// from and to in the triangle's winding.
field_border_edges :: proc(surface: ^Field_Surface, allocator := context.allocator) -> [dynamic][2]u16 {
	counts := count_field_edges(surface.indices[:], context.temp_allocator)
	edges := make([dynamic][2]u16, allocator)
	for triangle := 0; triangle + 2 < len(surface.indices); triangle += 3 {
		for corner in 0 ..< 3 {
			from, to := surface.indices[triangle + corner], surface.indices[triangle + (corner + 1) % 3]
			if counts[field_edge_key(from, to)] == 1 {
				append(&edges, [2]u16{from, to})
			}
		}
	}
	return edges
}

field_border_vertex_count :: proc(edges: [][2]u16, vertex_count: int) -> int {
	seen := make([]bool, vertex_count, context.temp_allocator)
	count := 0
	for edge in edges {
		for vertex in edge {
			count += seen[vertex] ? 0 : 1
			seen[vertex] = true
		}
	}
	return count
}

// An L shaped flap from every open border edge: out of the node by one
// coarse cell along the surface's slope and half a cell below it, so it
// neither stands above the neighbour's ground nor fights it in depth, then
// down by a coarse cell.
// A node's surface stops half a cell before its border on one side and
// half a cell past it on the other, so between levels the strip between
// the meshes is up to half a coarse cell wide; the outward leg covers it
// from above whichever side the coarser node is on. Each band continues
// the winding over its edge, so its front faces out of the node. A node
// whose skirts would outgrow the u16 indices keeps its surface without
// them and logs a line; FIELD_MESH_VERTEX_BOUND says this cannot happen
// with today's grid.
append_field_skirts :: proc(surface: ^Field_Surface) {
	edges := field_border_edges(surface, context.temp_allocator)
	skirt_vertex_count := 2 * field_border_vertex_count(edges[:], len(surface.vertices))
	if len(surface.vertices) + skirt_vertex_count > MESH_PART_VERTEX_LIMIT {
		platform.log_printf("field: a node's skirts would need %d vertices beyond its %d, drawn without them", skirt_vertex_count, len(surface.vertices))
		return
	}
	skirt_vertices := make([]i32, len(surface.vertices), context.temp_allocator)
	for &slot in skirt_vertices {
		slot = -1
	}
	for edge in edges {
		from, to := edge[0], edge[1]
		from_outer := field_skirt_vertex_index(surface, skirt_vertices, from)
		to_outer := field_skirt_vertex_index(surface, skirt_vertices, to)
		append(&surface.indices, to, from, from_outer, to, from_outer, to_outer)
		append(&surface.indices, to_outer, from_outer, from_outer + 1, to_outer, from_outer + 1, to_outer + 1)
	}
}
