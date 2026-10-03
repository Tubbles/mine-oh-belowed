package game

import "core:math/linalg"

// The field mesher (work item 0169, doc/presentation.md, Chunk meshes):
// naive surface nets over a grid of samples. A cell is the cube between
// eight neighbouring samples; every cell the surface crosses gets one
// vertex at the mean of its edge crossings, found by linear interpolation
// of the densities, and every grid edge the surface crosses becomes a quad
// between the vertices of the four cells around it, wound outward (against
// the density gradient). The geometry is integer and fixed point; floats
// appear only in field_mesh_from_surface, which turns the surface into the
// GPU's vertex arrays. No raylib here, render_field.odin uploads.
//
// A node meshes FIELD_GRID_CELLS cells a side from a Field_Grid that holds
// one more sample on every side: the quads of the grid edges a node owns
// (those starting inside it) reach the cells one step below its origin,
// which its neighbour computes from the same samples, so the meshes of
// neighbouring nodes of one level meet without a gap.

FIELD_GRID_CELLS :: FIELD_CHUNK_SIZE
// Samples -1 to FIELD_GRID_CELLS on every axis.
FIELD_GRID_SIZE :: FIELD_GRID_CELLS + 2
FIELD_GRID_SAMPLE_COUNT :: FIELD_GRID_SIZE * FIELD_GRID_SIZE * FIELD_GRID_SIZE
// Cells -1 to FIELD_GRID_CELLS - 1 can carry a vertex.
FIELD_VERTEX_CELL_SIZE :: FIELD_GRID_CELLS + 1
FIELD_VERTEX_CELL_COUNT :: FIELD_VERTEX_CELL_SIZE * FIELD_VERTEX_CELL_SIZE * FIELD_VERTEX_CELL_SIZE
// A vertex position is in this fraction of a grid cell; a power of two,
// so the positions convert to floats exactly.
FIELD_MESH_POSITION_UNITS :: 256
// Every material but air has a texture and a weight per vertex.
FIELD_TEXTURED_MATERIAL_COUNT :: len(Field_Material) - 1
// The vertex light until the field light (0173) provides it.
FIELD_FULL_DAYLIGHT :: 255

// The samples a node meshes from: index 0 is the sample at origin, a grid
// step is step samples. Filled from the loaded chunks for the finest level
// (gather_field_grid) and from the generation for the coarser ones
// (generate_field_grid), which keeps the samples a coarser grid took from
// loaded chunks (gather_coarse_field_grid, loaded set). water is the water
// field as a density (field_water_density), meshed as a second surface
// (0172, mesh_field_water_grid).
Field_Grid :: struct {
	origin:   Sample_Coordinate,
	step:     i32,
	density:  [FIELD_GRID_SAMPLE_COUNT]i8,
	material: [FIELD_GRID_SAMPLE_COUNT]Field_Material,
	tint:     [FIELD_GRID_SAMPLE_COUNT]u8,
	water:    [FIELD_GRID_SAMPLE_COUNT]i8,
	loaded:   [FIELD_GRID_SAMPLE_COUNT]bool,
}

// position is in 1/FIELD_MESH_POSITION_UNITS of a grid cell from the
// grid's origin. gradient is the density's change across the cell, the
// central difference at the cell's centre; the surface faces against it.
// weights is the share of the cell's ground corners per material, Topsoil
// first (field_material_slot), summing to about 255; color is the mean
// palette colour of the ground corners.
Field_Surface_Vertex :: struct {
	position: [3]i32,
	gradient: [3]i32,
	weights:  [FIELD_TEXTURED_MATERIAL_COUNT]u8,
	color:    [3]u8,
}

// Triangles as index triples. The skirts (world_field_lod.odin) come after
// skirt_index_start.
Field_Surface :: struct {
	vertices:          [dynamic]Field_Surface_Vertex,
	indices:           [dynamic]u16,
	skirt_index_start: int,
}

// What render_field.odin uploads: positions in metres from the node's
// origin; colors carry the tint in red, green and blue and the vertex
// light in alpha; weights are the material weights from 0 to 1, uploaded
// as the tangent attribute, since raylib has no other four float one.
Field_Mesh_Data :: struct {
	positions: [dynamic][3]f32,
	normals:   [dynamic][3]f32,
	colors:    [dynamic][4]u8,
	weights:   [dynamic][4]f32,
	indices:   [dynamic]u16,
}

#assert(FIELD_TEXTURED_MATERIAL_COUNT == 4, "the material weights travel in one four float attribute")

// Local from -1 to FIELD_GRID_CELLS on every axis.
field_grid_index :: proc(local: [3]i32) -> int {
	return int(local.x + 1) + FIELD_GRID_SIZE * (int(local.y + 1) + FIELD_GRID_SIZE * int(local.z + 1))
}

// Cell from -1 to FIELD_GRID_CELLS - 1 on every axis.
field_vertex_cell_index :: proc(cell: [3]i32) -> int {
	return int(cell.x + 1) + FIELD_VERTEX_CELL_SIZE * (int(cell.y + 1) + FIELD_VERTEX_CELL_SIZE * int(cell.z + 1))
}

field_sample_is_ground :: proc(density: i8) -> bool {
	return density > 0
}

field_material_slot :: proc(material: Field_Material) -> int {
	return int(material) - 1
}

// The range of grid indices on one axis that the chunk at this offset from
// the meshed one covers.
field_shell_range :: proc(offset: i32) -> (first, last: i32) {
	switch offset {
	case -1:
		return -1, -1
	case 1:
		return FIELD_GRID_CELLS, FIELD_GRID_CELLS
	}
	return 0, FIELD_GRID_CELLS - 1
}

// One chunk's part of the grid; a missing chunk reads as air, as
// field_world_get_sample does.
copy_field_grid_part :: proc(grid: ^Field_Grid, chunk: ^Field_Chunk, offset: [3]i32) {
	first, last: [3]i32
	for axis in 0 ..< 3 {
		first[axis], last[axis] = field_shell_range(offset[axis])
	}
	for z in first.z ..= last.z {
		for y in first.y ..= last.y {
			for x in first.x ..= last.x {
				index := field_grid_index({x, y, z})
				if chunk == nil {
					grid.density[index], grid.material[index], grid.tint[index] = FIELD_AIR_SAMPLE.density, FIELD_AIR_SAMPLE.material, FIELD_AIR_SAMPLE.tint
					grid.water[index] = -MAXIMUM_DENSITY
					continue
				}
				source := field_local_to_index({x %% FIELD_CHUNK_SIZE, y %% FIELD_CHUNK_SIZE, z %% FIELD_CHUNK_SIZE})
				grid.density[index], grid.material[index], grid.tint[index] = chunk.density[source], chunk.material[source], chunk.tint[source]
				grid.water[index] = field_water_density(chunk.density[source], chunk.water[source], grid.origin + Sample_Coordinate([3]i32{x, y, z}))
			}
		}
	}
}

// The chunk and a one sample shell from its 26 neighbours, copied on the
// main thread as the block mesher's border is (world_mesh_border.odin), so
// a worker never reads the Field_World.
gather_field_grid :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, allocator := context.allocator) -> ^Field_Grid {
	grid := new(Field_Grid, allocator)
	grid.origin = field_chunk_origin(coordinate)
	grid.step = 1
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				copy_field_grid_part(grid, world.chunks[coordinate + {x, y, z}] or_else nil, {x, y, z})
			}
		}
	}
	return grid
}

// Nothing to mesh when every sample is on one side of the surface.
field_grid_is_uniform :: proc(grid: ^Field_Grid) -> bool {
	first := field_sample_is_ground(grid.density[0])
	for density in grid.density {
		if field_sample_is_ground(density) != first {
			return false
		}
	}
	return true
}

field_corner_offset :: proc(corner: int) -> [3]i32 {
	return {i32(corner & 1), i32(corner >> 1 & 1), i32(corner >> 2 & 1)}
}

// Where the surface crosses from the first density to the second, in
// FIELD_MESH_POSITION_UNITS along the edge, rounded to the nearest unit.
// The two lie on either side, so the quotient is not negative.
field_edge_crossing :: proc(first, second: i8) -> i32 {
	numerator := i32(first) * FIELD_MESH_POSITION_UNITS
	denominator := i32(first) - i32(second)
	return (2 * numerator + denominator) / (2 * denominator)
}

// The mean of the crossings of the cell's twelve edges, in
// FIELD_MESH_POSITION_UNITS from the cell's lowest corner.
field_cell_offset :: proc(densities: [8]i8) -> [3]i32 {
	sum: [3]i32
	count: i32 = 0
	for corner in 0 ..< 8 {
		for axis in 0 ..< 3 {
			bit := 1 << uint(axis)
			if corner & bit != 0 || field_sample_is_ground(densities[corner]) == field_sample_is_ground(densities[corner | bit]) {
				continue
			}
			crossing := field_corner_offset(corner) * FIELD_MESH_POSITION_UNITS
			crossing[axis] += field_edge_crossing(densities[corner], densities[corner | bit])
			sum += crossing
			count += 1
		}
	}
	count = max(count, 1)
	return (sum + count / 2) / count
}

// The density's change along each axis, summed over the cell's four
// edges along it.
field_cell_gradient :: proc(densities: [8]i8) -> [3]i32 {
	gradient: [3]i32
	for corner in 0 ..< 8 {
		for axis in 0 ..< 3 {
			bit := 1 << uint(axis)
			if corner & bit == 0 {
				gradient[axis] += i32(densities[corner | bit]) - i32(densities[corner])
			}
		}
	}
	return gradient
}

// A saved tint is not checked against the palette (0168), so it wraps.
field_palette_color :: proc(palette: [][3]int, tint: u8) -> [3]int {
	return palette[int(tint) % len(palette)]
}

// Material weights and the mean colour over the ground corners.
field_cell_look :: proc(grid: ^Field_Grid, corners: [8]int, palette: [][3]int) -> (weights: [FIELD_TEXTURED_MATERIAL_COUNT]u8, color: [3]u8) {
	counts: [FIELD_TEXTURED_MATERIAL_COUNT]int
	weighed := 0
	color_sum: [3]int
	ground := 0
	for index in corners {
		if !field_sample_is_ground(grid.density[index]) {
			continue
		}
		ground += 1
		color_sum += field_palette_color(palette, grid.tint[index])
		if grid.material[index] != .Air {
			counts[field_material_slot(grid.material[index])] += 1
			weighed += 1
		}
	}
	for count, slot in counts {
		weights[slot] = u8(count * 255 / max(weighed, 1))
	}
	for channel in 0 ..< 3 {
		color[channel] = u8(color_sum[channel] / max(ground, 1))
	}
	return weights, color
}

field_cell_vertex :: proc(grid: ^Field_Grid, cell: [3]i32, palette: [][3]int) -> Field_Surface_Vertex {
	densities: [8]i8
	corners: [8]int
	for corner in 0 ..< 8 {
		corners[corner] = field_grid_index(cell + field_corner_offset(corner))
		densities[corner] = grid.density[corners[corner]]
	}
	vertex := Field_Surface_Vertex {
		position = cell * FIELD_MESH_POSITION_UNITS + field_cell_offset(densities),
		gradient = field_cell_gradient(densities),
	}
	vertex.weights, vertex.color = field_cell_look(grid, corners, palette)
	return vertex
}

// The cell's vertex index, made the first time a quad asks for it.
field_vertex_for_cell :: proc(surface: ^Field_Surface, cell_vertices: []i32, grid: ^Field_Grid, cell: [3]i32, palette: [][3]int) -> u16 {
	slot := &cell_vertices[field_vertex_cell_index(cell)]
	if slot^ < 0 {
		slot^ = i32(len(surface.vertices))
		append(&surface.vertices, field_cell_vertex(grid, cell, palette))
	}
	return u16(slot^)
}

// The quad of the grid edge from sample along axis, if the surface crosses
// it. The four cells around the edge, in counter clockwise order seen from
// the positive axis (axis + 1 and axis + 2 form a right handed frame), face
// that way when the ground lies at the edge's start.
append_field_edge_quad :: proc(surface: ^Field_Surface, cell_vertices: []i32, grid: ^Field_Grid, sample: [3]i32, axis: int, palette: [][3]int) {
	step: [3]i32
	step[axis] = 1
	start_ground := field_sample_is_ground(grid.density[field_grid_index(sample)])
	if start_ground == field_sample_is_ground(grid.density[field_grid_index(sample + step)]) {
		return
	}
	u_step, v_step: [3]i32
	u_step[(axis + 1) % 3] = 1
	v_step[(axis + 2) % 3] = 1
	cells := [4][3]i32{sample - u_step - v_step, sample - v_step, sample, sample - u_step}
	quad: [4]u16
	for cell, index in cells {
		quad[index] = field_vertex_for_cell(surface, cell_vertices, grid, cell, palette)
	}
	order := start_ground ? [6]int{0, 1, 2, 0, 2, 3} : [6]int{0, 2, 1, 0, 3, 2}
	for corner in order {
		append(&surface.indices, quad[corner])
	}
}

// The surface without skirts. A node owns the grid edges that start at
// samples 0 to FIELD_GRID_CELLS - 1.
mesh_field_surface :: proc(grid: ^Field_Grid, palette: [][3]int, allocator := context.allocator) -> Field_Surface {
	surface := Field_Surface {
		vertices = make([dynamic]Field_Surface_Vertex, allocator),
		indices  = make([dynamic]u16, allocator),
	}
	if field_grid_is_uniform(grid) {
		return surface
	}
	cell_vertices := make([]i32, FIELD_VERTEX_CELL_COUNT, context.temp_allocator)
	for &slot in cell_vertices {
		slot = -1
	}
	for z in i32(0) ..< FIELD_GRID_CELLS {
		for y in i32(0) ..< FIELD_GRID_CELLS {
			for x in i32(0) ..< FIELD_GRID_CELLS {
				for axis in 0 ..< 3 {
					append_field_edge_quad(&surface, cell_vertices, grid, {x, y, z}, axis, palette)
				}
			}
		}
	}
	surface.skirt_index_start = len(surface.indices)
	return surface
}

// Outward is against the gradient; a cell whose differences cancel faces
// up the grid's y.
field_vertex_normal :: proc(gradient: [3]i32) -> [3]f32 {
	outward := -[3]f32{f32(gradient.x), f32(gradient.y), f32(gradient.z)}
	length := linalg.length(outward)
	return length > 0 ? outward / length : {0, 1, 0}
}

// The GPU's vertex arrays: positions in metres from the grid's origin,
// a grid cell being step samples of spacing_millimetres.
field_mesh_from_surface :: proc(surface: Field_Surface, step: i32, spacing_millimetres: int, allocator := context.allocator) -> Field_Mesh_Data {
	data := make_field_mesh_data(allocator)
	metres_per_unit := f32(step) * f32(spacing_millimetres) / f32(FIELD_MESH_POSITION_UNITS * MILLIMETRES_PER_METRE)
	for vertex in surface.vertices {
		append(&data.positions, [3]f32{f32(vertex.position.x), f32(vertex.position.y), f32(vertex.position.z)} * metres_per_unit)
		append(&data.normals, field_vertex_normal(vertex.gradient))
		append(&data.colors, [4]u8{vertex.color.r, vertex.color.g, vertex.color.b, FIELD_FULL_DAYLIGHT})
		append(&data.weights, [4]f32{f32(vertex.weights[0]), f32(vertex.weights[1]), f32(vertex.weights[2]), f32(vertex.weights[3])} / 255)
	}
	append(&data.indices, ..surface.indices[:])
	return data
}

make_field_mesh_data :: proc(allocator := context.allocator) -> Field_Mesh_Data {
	return Field_Mesh_Data {
		positions = make([dynamic][3]f32, allocator),
		normals = make([dynamic][3]f32, allocator),
		colors = make([dynamic][4]u8, allocator),
		weights = make([dynamic][4]f32, allocator),
		indices = make([dynamic]u16, allocator),
	}
}

// The worker's job for one node's terrain: the surface, its skirts, the
// vertex arrays. The surface is temporary.
mesh_field_grid :: proc(grid: ^Field_Grid, palette: [][3]int, spacing_millimetres: int, allocator := context.allocator) -> Field_Mesh_Data {
	surface := mesh_field_surface(grid, palette, context.temp_allocator)
	append_field_skirts(&surface)
	return field_mesh_from_surface(surface, grid.step, spacing_millimetres, allocator)
}

// The water's surface of the same grid (0172): the mesher over the water
// densities, without material or tint, since the field shader colours the
// water pass by a uniform. No skirts: the water's open border also runs
// along its faces against the ground, whose gradient points out of the
// ground, so a skirt there would stand up out of the water as a fin; the
// strip between two levels of detail stays open instead.
mesh_field_water_grid :: proc(grid: ^Field_Grid, palette: [][3]int, spacing_millimetres: int, allocator := context.allocator) -> Field_Mesh_Data {
	water := new(Field_Grid, context.temp_allocator)
	water.origin, water.step = grid.origin, grid.step
	water.density = grid.water
	surface := mesh_field_surface(water, palette, context.temp_allocator)
	return field_mesh_from_surface(surface, grid.step, spacing_millimetres, allocator)
}

destroy_field_mesh_data :: proc(data: Field_Mesh_Data) {
	delete(data.positions)
	delete(data.normals)
	delete(data.colors)
	delete(data.weights)
	delete(data.indices)
}
