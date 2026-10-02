package game

import "core:math/linalg"
import "core:testing"

// A field read at a sample: no captures, so each test field is a proc.
Test_Field_Density :: proc(sample: [3]i64) -> i8

TEST_FIELD_PALETTE := [?][3]int{{100, 90, 80}, {120, 100, 80}, {90, 90, 90}}

// The tilted plane 10 x + 40 y + 20 z = 900, ground below. Its slope stays
// under the density's saturation within a cell, so the field is linear
// where the surface is.
TEST_PLANE_GRADIENT :: [3]i64{10, 40, 20}
TEST_PLANE_OFFSET :: 900

test_plane_value :: proc(position: [3]f64) -> f64 {
	return TEST_PLANE_OFFSET - (f64(TEST_PLANE_GRADIENT.x) * position.x + f64(TEST_PLANE_GRADIENT.y) * position.y + f64(TEST_PLANE_GRADIENT.z) * position.z)
}

test_plane_density :: proc(sample: [3]i64) -> i8 {
	value := TEST_PLANE_OFFSET - linalg.dot(TEST_PLANE_GRADIENT, sample)
	return i8(clamp(value, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
}

// A sphere of radius distance_steps / DENSITY_STEPS_PER_SAMPLE samples
// around centre; never exactly 0, so no vertex lands on a corner.
test_sphere_density :: proc(sample, centre: [3]i64, distance_steps: i64) -> i8 {
	offset := sample - centre
	steps := distance_steps - i64(integer_square_root(u64(linalg.dot(offset, offset) * DENSITY_STEPS_PER_SAMPLE * DENSITY_STEPS_PER_SAMPLE)))
	if steps == 0 {
		steps = -1
	}
	return i8(clamp(steps, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
}

// About 20.3 samples around the origin, across the eight chunks there.
test_small_sphere_density :: proc(sample: [3]i64) -> i8 {
	return test_sphere_density(sample, {0, 0, 0}, 2600)
}

// 300 samples around a centre below the origin, so its top crosses the
// chunks above the origin nearly flat.
test_large_sphere_density :: proc(sample: [3]i64) -> i8 {
	return test_sphere_density(sample, {32, -270, 32}, 300 * DENSITY_STEPS_PER_SAMPLE)
}

test_field_sample :: proc(density: Test_Field_Density, sample: [3]i64) -> Field_Sample {
	value := density(sample)
	if value <= 0 {
		return {value, .Air, 0}
	}
	return {value, .Stone, u8(abs(sample.x) % 3)}
}

fill_test_field_grid :: proc(origin: Sample_Coordinate, step: i32, density: Test_Field_Density) -> ^Field_Grid {
	grid := new(Field_Grid, context.temp_allocator)
	grid.origin, grid.step = origin, step
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := ([3]i32)(origin) + [3]i32{x, y, z} * step
				value := test_field_sample(density, {i64(sample.x), i64(sample.y), i64(sample.z)})
				index := field_grid_index({x, y, z})
				grid.density[index], grid.material[index], grid.tint[index] = value.density, value.material, value.tint
			}
		}
	}
	return grid
}

fill_test_field_chunk :: proc(coordinate: Field_Chunk_Coordinate, density: Test_Field_Density) -> ^Field_Chunk {
	chunk := new(Field_Chunk, context.temp_allocator)
	chunk.coordinate = coordinate
	origin := field_chunk_origin(coordinate)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		sample := ([3]i32)(origin) + field_index_to_local(index)
		field_chunk_set_sample(chunk, index, test_field_sample(density, {i64(sample.x), i64(sample.y), i64(sample.z)}))
	}
	return chunk
}

// In samples from the grid's origin.
test_vertex_samples :: proc(vertex: Field_Surface_Vertex) -> [3]f64 {
	return {f64(vertex.position.x), f64(vertex.position.y), f64(vertex.position.z)} / FIELD_MESH_POSITION_UNITS
}

@(test)
test_a_plane_field_meshes_to_the_plane_with_normals_along_the_gradient :: proc(t: ^testing.T) {
	grid := fill_test_field_grid({0, 0, 0}, 1, test_plane_density)
	surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	testing.expect(t, len(surface.vertices) > 100)
	outward := linalg.normalize([3]f32{f32(TEST_PLANE_GRADIENT.x), f32(TEST_PLANE_GRADIENT.y), f32(TEST_PLANE_GRADIENT.z)})
	for vertex in surface.vertices {
		testing.expectf(t, abs(test_plane_value(test_vertex_samples(vertex))) < 1, "vertex at %v lies off the plane", test_vertex_samples(vertex))
		testing.expectf(t, linalg.dot(field_vertex_normal(vertex.gradient), outward) > 0.999, "normal %v", field_vertex_normal(vertex.gradient))
		testing.expect_value(t, vertex.weights, [4]u8{0, 255, 0, 0})
	}
	// Every triangle faces out of the ground.
	for triangle := 0; triangle < surface.skirt_index_start; triangle += 3 {
		corners: [3][3]f64
		for corner in 0 ..< 3 {
			corners[corner] = test_vertex_samples(surface.vertices[surface.indices[triangle + corner]])
		}
		facing := linalg.cross(corners[1] - corners[0], corners[2] - corners[0])
		testing.expect(t, linalg.dot(facing, [3]f64{10, 40, 20}) > 0)
	}
}

@(test)
test_a_field_without_a_crossing_meshes_to_nothing :: proc(t: ^testing.T) {
	air := proc(sample: [3]i64) -> i8 {return -MAXIMUM_DENSITY}
	ground := proc(sample: [3]i64) -> i8 {return MAXIMUM_DENSITY}
	for density in ([2]Test_Field_Density{air, ground}) {
		data := mesh_field_grid(fill_test_field_grid({0, 0, 0}, 1, density), TEST_FIELD_PALETTE[:], DEFAULT_SAMPLE_SPACING_MILLIMETRES, context.temp_allocator)
		testing.expect_value(t, len(data.positions), 0)
		testing.expect_value(t, len(data.indices), 0)
	}
}

// The eight chunks around the origin meshed one by one from the world, as
// the workers do, welded by position: every directed edge has its reverse
// once, so the sphere is closed across every chunk border.
@(test)
test_a_sphere_across_chunks_meshes_watertight :: proc(t: ^testing.T) {
	world := Field_World {
		chunks = make(map[Field_Chunk_Coordinate]^Field_Chunk, context.temp_allocator),
	}
	coordinates := [?]Field_Chunk_Coordinate{{-1, -1, -1}, {0, -1, -1}, {-1, 0, -1}, {0, 0, -1}, {-1, -1, 0}, {0, -1, 0}, {-1, 0, 0}, {0, 0, 0}}
	for coordinate in coordinates {
		world.chunks[coordinate] = fill_test_field_chunk(coordinate, test_small_sphere_density)
	}
	welded := make(map[[3]i32]int, context.temp_allocator)
	edges := make(map[[2]int]int, context.temp_allocator)
	for coordinate in coordinates {
		grid := gather_field_grid(&world, coordinate, context.temp_allocator)
		surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
		testing.expectf(t, len(surface.vertices) > 0, "chunk %v holds part of the sphere", coordinate)
		ids := make([]int, len(surface.vertices), context.temp_allocator)
		for vertex, index in surface.vertices {
			position := ([3]i32)(grid.origin) * FIELD_MESH_POSITION_UNITS + vertex.position
			if position not_in welded {
				welded[position] = len(welded)
			}
			ids[index] = welded[position]
		}
		for triangle := 0; triangle < surface.skirt_index_start; triangle += 3 {
			for corner in 0 ..< 3 {
				edges[{ids[surface.indices[triangle + corner]], ids[surface.indices[triangle + (corner + 1) % 3]]}] += 1
			}
		}
	}
	testing.expect(t, len(edges) > 1000)
	for edge, count in edges {
		testing.expectf(t, count == 1 && edges[{edge[1], edge[0]}] == 1, "edge %v is used %d times, its reverse %d times", edge, count, edges[{edge[1], edge[0]}])
	}
}

// A surface's vertices go with its area, so sampling every second sample
// leaves about a quarter of them (not an eighth: that is the volume's
// share, and only cells the surface crosses carry a vertex).
@(test)
test_the_half_resolution_mesh_has_about_a_quarter_of_the_vertices :: proc(t: ^testing.T) {
	coarse := mesh_field_surface(fill_test_field_grid({0, 0, 0}, 2, test_large_sphere_density), TEST_FIELD_PALETTE[:], context.temp_allocator)
	fine_count := 0
	for child in 0 ..< 8 {
		origin := Sample_Coordinate(field_corner_offset(child) * FIELD_GRID_CELLS)
		fine := mesh_field_surface(fill_test_field_grid(origin, 1, test_large_sphere_density), TEST_FIELD_PALETTE[:], context.temp_allocator)
		fine_count += len(fine.vertices)
	}
	share := f64(len(coarse.vertices)) / f64(fine_count)
	testing.expectf(t, fine_count > 1000 && share > 0.2 && share < 0.3, "%d coarse and %d fine vertices", len(coarse.vertices), fine_count)
}

@(test)
test_the_tint_wraps_around_the_palette :: proc(t: ^testing.T) {
	palette := TEST_FIELD_PALETTE
	testing.expect_value(t, field_palette_color(palette[:], 1), palette[1])
	testing.expect_value(t, field_palette_color(palette[:], 4), palette[1])
	testing.expect_value(t, field_palette_color(palette[:], 255), palette[0])
}

@(test)
test_the_vertex_arrays_are_in_metres :: proc(t: ^testing.T) {
	grid := fill_test_field_grid({0, 0, 0}, 2, test_plane_density)
	surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	data := field_mesh_from_surface(surface, 2, 500, context.temp_allocator)
	testing.expect_value(t, len(data.positions), len(surface.vertices))
	// Two samples a cell, half a metre a sample: a cell is a metre.
	expected := [3]f32{f32(surface.vertices[0].position.x), f32(surface.vertices[0].position.y), f32(surface.vertices[0].position.z)} / FIELD_MESH_POSITION_UNITS
	testing.expect_value(t, data.positions[0], expected)
	testing.expect_value(t, data.colors[0].a, FIELD_FULL_DAYLIGHT)
	testing.expect_value(t, data.weights[0], [4]f32{0, 1, 0, 0})
}
