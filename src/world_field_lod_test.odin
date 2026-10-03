package game

import "core:math"
import "core:testing"

// Skirts on every face, as a node alone in the selection hangs them.
EVERY_FIELD_FACE :: Field_Faces{.Negative_X, .Positive_X, .Negative_Y, .Positive_Y, .Negative_Z, .Positive_Z}

TEST_LEVEL_DISTANCES_METRES :: [FIELD_LEVEL_COUNT]int{64, 160, 384, 1024}

test_level_distances :: proc() -> [FIELD_LEVEL_COUNT]i64 {
	distances: [FIELD_LEVEL_COUNT]i64
	for distance, level in TEST_LEVEL_DISTANCES_METRES {
		distances[level] = metres_to_position_units(i64(distance))
	}
	return distances
}

@(test)
test_the_level_follows_the_distance :: proc(t: ^testing.T) {
	cases := [?]struct {
		metres:  i64,
		level:   i32,
		visible: bool,
	}{{0, 0, true}, {63, 0, true}, {64, 1, true}, {159, 1, true}, {160, 2, true}, {383, 2, true}, {384, 3, true}, {1023, 3, true}, {1024, 0, false}, {5000, 0, false}}
	for entry in cases {
		distance := metres_to_position_units(entry.metres)
		level, visible := field_level_for_distance(distance * distance, test_level_distances())
		testing.expectf(t, level == entry.level && visible == entry.visible, "%d m picked level %d (visible %v)", entry.metres, level, visible)
	}
}

// Above the pole of the test planet at 40 m: the node under the camera is
// the finest, nothing lies beyond the last distance, and the nearest come
// first.
@(test)
test_the_selection_refines_towards_the_camera :: proc(t: ^testing.T) {
	planet := make_test_planet()
	camera := World_Position{0, metres_to_position_units(i64(planet.radius_metres + 40)), 0}
	view := make_field_view(camera, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, TEST_LEVEL_DISTANCES_METRES)
	selection := select_field_nodes(view, context.temp_allocator)
	testing.expect(t, len(selection) > 0)
	testing.expect_value(t, selection[0].level, 0)
	levels_seen: [FIELD_LEVEL_COUNT]bool
	previous: i64 = 0
	for node in selection {
		distance_squared := box_distance_squared(field_node_box(node, DEFAULT_SAMPLE_SPACING_MILLIMETRES), camera)
		level, visible := field_level_for_distance(distance_squared, view.level_distances)
		testing.expect(t, visible && level >= node.level)
		testing.expect(t, distance_squared >= previous)
		previous = distance_squared
		levels_seen[node.level] = true
	}
	testing.expect_value(t, levels_seen, [FIELD_LEVEL_COUNT]bool{true, true, true, true})
}

@(test)
test_far_from_the_planet_nothing_is_selected :: proc(t: ^testing.T) {
	planet := make_test_planet()
	camera := World_Position{0, metres_to_position_units(i64(planet.radius_metres + 5000)), 0}
	view := make_field_view(camera, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, TEST_LEVEL_DISTANCES_METRES)
	testing.expect_value(t, len(select_field_nodes(view, context.temp_allocator)), 0)
}

// The skirt hangs from the plane's open border: its outer vertices one
// cell (half a coarse cell) below the surface, its lower ones three.
@(test)
test_the_skirt_lies_inside_the_surface :: proc(t: ^testing.T) {
	grid := fill_test_field_grid({0, 0, 0}, 1, test_plane_density)
	surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	surface_vertex_count := len(surface.vertices)
	border_edges := len(field_border_edges(&surface, context.temp_allocator))
	append_field_skirts(&surface, EVERY_FIELD_FACE)
	testing.expect(t, border_edges > 0)
	testing.expect_value(t, len(surface.indices) - surface.skirt_index_start, 12 * border_edges)
	testing.expect(t, len(surface.vertices) > surface_vertex_count)
	plane_length := 46.9 // |(10, 40, 20)|
	for vertex, index in surface.vertices[surface_vertex_count:] {
		depth := test_plane_value(test_vertex_samples(vertex)) / plane_length
		expected := index % 2 == 0 ? 1.0 : 3.0
		testing.expectf(t, abs(depth - expected) < 0.2, "skirt vertex %v lies %v samples deep, not %v", test_vertex_samples(vertex), depth, expected)
	}
}

// The plane y = (2600 + slope.x x + slope.y z) / 128 samples, ground below,
// with its density in units of the grid's spacing, as generate_field_grid
// makes it.
fill_test_plane_grid :: proc(origin: Sample_Coordinate, step: i32, slope: [2]i64) -> ^Field_Grid {
	grid := new(Field_Grid, context.temp_allocator)
	grid.origin, grid.step = origin, step
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := ([3]i32)(origin) + [3]i32{x, y, z} * step
				depth := 2600 + slope.x * i64(sample.x) + slope.y * i64(sample.z) - DENSITY_STEPS_PER_SAMPLE * i64(sample.y)
				density := i8(clamp(floor_divide_i64(depth, i64(step)), -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
				index := field_grid_index({x, y, z})
				grid.density[index], grid.material[index] = density, density > 0 ? .Stone : .Air
			}
		}
	}
	return grid
}

// In samples from the world's origin.
test_grid_vertex_samples :: proc(grid: ^Field_Grid, vertex: Field_Surface_Vertex) -> [3]f64 {
	return {f64(grid.origin.x), f64(grid.origin.y), f64(grid.origin.z)} + test_vertex_samples(vertex) * f64(grid.step)
}

@(test)
test_a_sloped_plane_meshes_without_terraces_at_every_level :: proc(t: ^testing.T) {
	slope := [2]i64{38, 14}
	for level in i32(0) ..< FIELD_LEVEL_COUNT {
		grid := fill_test_plane_grid({0, 0, 0}, 1 << uint(level), slope)
		surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
		testing.expect(t, len(surface.vertices) > 100)
		worst := 0.0
		for vertex in surface.vertices {
			position := test_grid_vertex_samples(grid, vertex)
			height := (2600 + f64(slope.x) * position.x + f64(slope.y) * position.z) / DENSITY_STEPS_PER_SAMPLE
			worst = max(worst, abs(position.y - height))
		}
		testing.expectf(t, worst < 0.1, "level %d: a vertex lies %v samples off the plane", level, worst)
	}
}

// generate_field_grid's densities are the planet's in the grid's spacing.
@(test)
test_a_coarse_grid_holds_densities_in_its_own_spacing :: proc(t: ^testing.T) {
	planet := make_test_planet()
	generation := make_planet_generation(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	node := Field_Node{2, {0, 62, 0}}
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	coarse := make_planet_generation(TEST_PLANET_SEED, planet, 4 * DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	partial := 0
	for local in ([?][3]i32{{0, 0, 0}, {5, 9, 3}, {16, 16, 16}, {31, 20, 7}, {-1, 32, 12}}) {
		sample := grid.origin + Sample_Coordinate(local * 4)
		expected := planet_sample(coarse, sample_to_world_position(sample, DEFAULT_SAMPLE_SPACING_MILLIMETRES))
		testing.expect_value(t, grid.density[field_grid_index(local)], expected.density)
	}
	for density in grid.density {
		partial += abs(density) < MAXIMUM_DENSITY ? 1 : 0
	}
	testing.expect(t, partial > 0, "the node holds the surface")
}

// The points of the strip around x = 0, a twentieth of a sample apart
// across the seam, that no triangle covers seen from above (along y).
open_strip_points :: proc(triangles: [][3][2]f64) -> int {
	open := 0
	for z := 6.0; z <= 26.0; z += 0.5 {
		for x := -3.0; x <= 3.0; x += 0.05 {
			covered := false
			for triangle in triangles {
				if point_in_triangle({x, z}, triangle) {
					covered = true
					break
				}
			}
			open += covered ? 0 : 1
		}
	}
	return open
}

point_in_triangle :: proc(point: [2]f64, triangle: [3][2]f64) -> bool {
	side :: proc(a, b, p: [2]f64) -> f64 {return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)}
	first, second, third := side(triangle[0], triangle[1], point), side(triangle[1], triangle[2], point), side(triangle[2], triangle[0], point)
	epsilon :: 1e-9
	return (first >= -epsilon && second >= -epsilon && third >= -epsilon) || (first <= epsilon && second <= epsilon && third <= epsilon)
}

// The xz projections of a node's surface and skirts near the strip.
append_strip_triangles :: proc(triangles: ^[dynamic][3][2]f64, grid: ^Field_Grid, faces: Field_Faces) {
	surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	append_field_skirts(&surface, faces)
	for triangle := 0; triangle < len(surface.indices); triangle += 3 {
		projected: [3][2]f64
		near := false
		for corner in 0 ..< 3 {
			position := test_grid_vertex_samples(grid, surface.vertices[surface.indices[triangle + corner]])
			projected[corner] = {position.x, position.z}
			near ||= abs(position.x) < 6
		}
		if near {
			append(triangles, projected)
		}
	}
}

// A finest node beside a half resolution one on flat ground, the coarse
// one on either side: no strip of the seam is open from above, with the
// skirt on the fine node's face towards the coarse one only, as
// field_node_skirt_faces gives them. Without the skirts the coarse node
// on the negative side leaves one open.
@(test)
test_a_level_seam_on_flat_ground_is_closed_from_above :: proc(t: ^testing.T) {
	sides := [2][2]Sample_Coordinate{{{0, 0, 0}, {-64, 0, 0}}, {{-32, 0, 0}, {0, 0, 0}}}
	towards_coarse := [2]Field_Face{.Negative_X, .Positive_X}
	for side, index in sides {
		triangles := make([dynamic][3][2]f64, context.temp_allocator)
		append_strip_triangles(&triangles, fill_test_plane_grid(side[0], 1, {0, 0}), {towards_coarse[index]})
		append_strip_triangles(&triangles, fill_test_plane_grid(side[1], 2, {0, 0}), {})
		testing.expectf(t, open_strip_points(triangles[:]) == 0, "the seam with the fine node at %v is open from above", side[0])
	}
	bare := make([dynamic][3][2]f64, context.temp_allocator)
	append_strip_triangles(&bare, fill_test_plane_grid(sides[0][0], 1, {0, 0}), {})
	append_strip_triangles(&bare, fill_test_plane_grid(sides[0][1], 2, {0, 0}), {})
	testing.expect(t, open_strip_points(bare[:]) > 0, "the check finds the seam's gap without skirts")
}

// A coarse node's grid comes from the generation; at step 1 it holds the
// chunk the workers generate.
@(test)
test_a_generated_grid_matches_the_generated_chunk :: proc(t: ^testing.T) {
	planet := make_test_planet()
	coordinate := Field_Chunk_Coordinate{0, 249, 0}
	chunk := generate_test_field_chunk(coordinate)
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(make_planet_generation(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES), field_chunk_node(coordinate), grid)
	testing.expect_value(t, grid.origin, field_chunk_origin(coordinate))
	mismatches := 0
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		grid_index := field_grid_index(field_index_to_local(index))
		if grid.density[grid_index] != chunk.density[index] || grid.material[grid_index] != chunk.material[index] || grid.tint[grid_index] != chunk.tint[index] || grid.sky_light[grid_index] != chunk.sky_light[index] || grid.block_light[grid_index] != 0 {
			mismatches += 1
		}
	}
	testing.expect_value(t, mismatches, 0)
	testing.expect(t, !field_grid_is_uniform(grid), "the test chunk holds the surface")
}

// A coarse grid takes a loaded sample's light and gives a generated one
// full sky in air (0173).
@(test)
test_a_coarse_grid_reads_the_light_of_the_loaded_chunks :: proc(t: ^testing.T) {
	planet := make_test_planet()
	generation := make_planet_generation(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	world: Field_World
	defer destroy_field_world(&world)
	coordinate := Field_Chunk_Coordinate{0, 249, 0}
	chunk := new(Field_Chunk)
	generate_field_chunk(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, coordinate, chunk)
	for &level, index in chunk.block_light {
		level = chunk.density[index] > 0 ? 0 : 150
	}
	field_world_insert_chunk(&world, chunk)
	node := Field_Node{1, {0, 124, 0}}
	grid := gather_coarse_field_grid(&world, node, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	loaded_air, generated_air := 0, 0
	for index in 0 ..< FIELD_GRID_SAMPLE_COUNT {
		switch {
		case field_sample_is_ground(grid.density[index]):
			testing.expect_value(t, grid.block_light[index], 0)
		case grid.loaded[index]:
			testing.expect_value(t, grid.block_light[index], 150)
			loaded_air += 1
		case:
			testing.expect_value(t, grid.sky_light[index], FIELD_LIGHT_FULL)
			generated_air += 1
		}
	}
	testing.expect(t, loaded_air > 0 && generated_air > 0)
}

// Flat ground below y = 20.5 with a pit dug across the border x = 32 of
// two finest nodes, as the brush of the preview's screenshot digs it (a
// sphere of 2.5 samples 1.5 below the ground): every sample within it is
// air, every other keeps the ground's density, so the rim is a sharp
// convex edge.
TEST_PIT_CENTRE :: [3]f64{31.5, 19, 16.3}
TEST_PIT_RADIUS :: 2.5

test_pit_density :: proc(sample: [3]i64) -> i8 {
	offset := [3]f64{f64(sample.x), f64(sample.y), f64(sample.z)} - TEST_PIT_CENTRE
	if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= TEST_PIT_RADIUS * TEST_PIT_RADIUS {
		return -MAXIMUM_DENSITY
	}
	return i8(clamp((41 - 2 * sample.y) * DENSITY_STEPS_PER_SAMPLE / 2, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
}

// The field's trilinear density at a point in samples.
test_pit_trilinear :: proc(point: [3]f64) -> f64 {
	low := [3]i64{i64(math.floor(point.x)), i64(math.floor(point.y)), i64(math.floor(point.z))}
	fraction := point - {f64(low.x), f64(low.y), f64(low.z)}
	total := 0.0
	for corner in 0 ..< 8 {
		offset := field_corner_offset(corner)
		weight := 1.0
		for axis in 0 ..< 3 {
			weight *= offset[axis] == 1 ? fraction[axis] : 1 - fraction[axis]
		}
		total += weight * f64(test_pit_density(low + {i64(offset.x), i64(offset.y), i64(offset.z)}))
	}
	return total
}

// The skirt vertices of a node's grid with the faces, and the least
// trilinear density among them (negative in the air).
test_pit_skirt_depth :: proc(origin: Sample_Coordinate, faces: Field_Faces) -> (count: int, shallowest: f64) {
	grid := fill_test_field_grid(origin, 1, test_pit_density)
	surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	first_skirt := len(surface.vertices)
	append_field_skirts(&surface, faces)
	shallowest = max(f64)
	for vertex in surface.vertices[first_skirt:] {
		shallowest = min(shallowest, test_pit_trilinear(test_grid_vertex_samples(grid, vertex)))
	}
	return len(surface.vertices) - first_skirt, shallowest
}

// Two finest nodes share the border a dug pit crosses: neither hangs a
// skirt there, so no skirt stands in the pit's air; with skirts on every
// face the straight leg leaves the rim's curve and does.
@(test)
test_nodes_of_one_level_hang_no_skirt_between_them :: proc(t: ^testing.T) {
	nodes := [2]struct {
		origin: Sample_Coordinate,
		shared: Field_Face,
	}{{{0, 0, 0}, .Positive_X}, {{32, 0, 0}, .Negative_X}}
	in_air := false
	for node in nodes {
		count, shallowest := test_pit_skirt_depth(node.origin, EVERY_FIELD_FACE - {node.shared})
		testing.expectf(t, count > 0 && shallowest >= 0, "the node at %v has %d skirt vertices, the shallowest at density %v", node.origin, count, shallowest)
		_, every_face := test_pit_skirt_depth(node.origin, EVERY_FIELD_FACE)
		in_air ||= every_face < 0
	}
	testing.expect(t, in_air, "skirts on the shared face stand in the pit's air")
}

// The faces towards a coarser node or none hang skirts, those towards a
// node of the same level or finer ones do not.
@(test)
test_the_skirt_faces_follow_the_neighbours_levels :: proc(t: ^testing.T) {
	fine := Field_Node{0, {0, 0, 0}}
	same := Field_Node{0, {0, 0, 1}}
	coarse := Field_Node{1, {-1, 0, 0}}
	selection := []Field_Node{fine, same, coarse, {0, {1, 0, 0}}, {0, {1, 1, 0}}, {0, {1, 0, 1}}, {0, {1, 1, 1}}}
	index := make_field_selection_index(selection, context.temp_allocator)
	testing.expect_value(t, field_node_skirt_faces(index, fine), Field_Faces{.Negative_X, .Negative_Y, .Positive_Y, .Negative_Z})
	// The coarse node's +x face borders the finer nodes.
	testing.expect(t, .Positive_X not_in field_node_skirt_faces(index, coarse))
}
