package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
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
	append_field_skirts(&surface, {flaps = EVERY_FIELD_FACE})
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
append_strip_triangles :: proc(triangles: ^[dynamic][3][2]f64, grid: ^Field_Grid, faces: Field_Seam_Faces) {
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
// fine node's flap and the coarse node's cut and curtain on their faces
// towards each other, as field_node_skirt_faces gives them. Without the
// skirts the coarse node on the negative side leaves one open.
@(test)
test_a_level_seam_on_flat_ground_is_closed_from_above :: proc(t: ^testing.T) {
	sides := [2][2]Sample_Coordinate{{{0, 0, 0}, {-64, 0, 0}}, {{-32, 0, 0}, {0, 0, 0}}}
	towards_coarse := [2]Field_Face{.Negative_X, .Positive_X}
	towards_fine := [2]Field_Face{.Positive_X, .Negative_X}
	for side, index in sides {
		triangles := make([dynamic][3][2]f64, context.temp_allocator)
		append_strip_triangles(&triangles, fill_test_plane_grid(side[0], 1, {0, 0}), {flaps = {towards_coarse[index]}})
		append_strip_triangles(&triangles, fill_test_plane_grid(side[1], 2, {0, 0}), {curtains = {towards_fine[index]}})
		testing.expectf(t, open_strip_points(triangles[:]) == 0, "the seam with the fine node at %v is open from above", side[0])
	}
	bare := make([dynamic][3][2]f64, context.temp_allocator)
	append_strip_triangles(&bare, fill_test_plane_grid(sides[0][0], 1, {0, 0}), {})
	append_strip_triangles(&bare, fill_test_plane_grid(sides[0][1], 2, {0, 0}), {})
	testing.expect(t, open_strip_points(bare[:]) > 0, "the check finds the seam's gap without skirts")
}

// tan(60 degrees) in density steps a sample: steeper than the steepest
// ground the shipped planets make, 58.5 degrees within 1.2 km of the home
// (measured for 0321).
STEEPEST_SHIPPED_RISE :: 222

// A node's surface and skirts, each triangle with a corner within 10
// samples of the seam x = 0, in samples from the world's origin.
append_seam_triangles :: proc(triangles: ^[dynamic][3][3]f64, grid: ^Field_Grid, faces: Field_Seam_Faces) {
	surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	append_field_skirts(&surface, faces)
	for triangle := 0; triangle < len(surface.indices); triangle += 3 {
		corners: [3][3]f64
		near := false
		for corner in 0 ..< 3 {
			corners[corner] = test_grid_vertex_samples(grid, surface.vertices[surface.indices[triangle + corner]])
			near ||= abs(corners[corner].x) < 10
		}
		if near {
			append(triangles, corners)
		}
	}
}

// Möller and Trumbore's test against the triangles that are counter
// clockwise seen from the origin, the front faces draw_field keeps. The
// barycentric bounds are widened a little, so a ray along an edge two
// triangles share meets one of them.
ray_meets_front_face :: proc(triangles: [][3][3]f64, origin, direction: [3]f64) -> bool {
	epsilon :: 1e-9
	for triangle in triangles {
		first_edge, second_edge := triangle[1] - triangle[0], triangle[2] - triangle[0]
		across := linalg.cross(direction, second_edge)
		determinant := linalg.dot(first_edge, across)
		if determinant <= 1e-12 {
			continue
		}
		offset := origin - triangle[0]
		first_weight := linalg.dot(offset, across) / determinant
		offset_across := linalg.cross(offset, first_edge)
		second_weight := linalg.dot(direction, offset_across) / determinant
		distance := linalg.dot(second_edge, offset_across) / determinant
		if first_weight >= -epsilon && second_weight >= -epsilon && first_weight + second_weight <= 1 + epsilon && distance > 0 {
			return true
		}
	}
	return false
}

// Rays at the plane of fill_test_plane_grid with the slope {rise, 0},
// aimed at x from -4 to 4 on the lines z = 8.25 and 16.75, along x from
// either side at 2, 10 and 20 degrees to the plane, each from 40 samples
// back: how many meet no front face.
open_grazing_rays :: proc(triangles: [][3][3]f64, rise: i64) -> int {
	gradient := f64(rise) / DENSITY_STEPS_PER_SAMPLE
	tangent := linalg.normalize([3]f64{1, gradient, 0})
	normal := linalg.normalize([3]f64{-gradient, 1, 0})
	open := 0
	for z in ([2]f64{8.25, 16.75}) {
		for step in 0 ..= 80 {
			x := -4 + 0.1 * f64(step)
			target := [3]f64{x, (2600 + f64(rise) * x) / DENSITY_STEPS_PER_SAMPLE, z}
			for side in ([2]f64{-1, 1}) {
				for degrees in ([3]f64{2, 10, 20}) {
					angle := math.to_radians(degrees)
					direction := side * math.cos(angle) * tangent - math.sin(angle) * normal
					open += ray_meets_front_face(triangles, target - 40 * direction, direction) ? 0 : 1
				}
			}
		}
	}
	return open
}

// The two sides of the flat seam test as nodes, on flat ground and at the
// steepest slope the shipped planets make (0321): with the flaps and the
// curtains field_node_skirt_faces gives, a ray meeting the ground near
// the seam at a shallow angle from either side meets a front face. With
// the finer node's flap alone (0173's rule), rays from the finer side
// pass over it and under the coarser surface, whose back faces are
// culled.
@(test)
test_a_level_seam_is_closed_at_grazing_views :: proc(t: ^testing.T) {
	sides := [2][2]Field_Node{{{0, {0, 0, 0}}, {1, {-1, 0, 0}}}, {{0, {-1, 0, 0}}, {1, {0, 0, 0}}}}
	for rise in ([2]i64{0, STEEPEST_SHIPPED_RISE}) {
		for &side in sides {
			index := make_field_selection_index(side[:], context.temp_allocator)
			triangles := make([dynamic][3][3]f64, context.temp_allocator)
			for node in side {
				grid := fill_test_plane_grid(field_node_origin(node), field_node_step(node), {rise, 0})
				faces := field_node_skirt_faces(index, node)
				append_seam_triangles(&triangles, grid, {faces.flaps & {.Negative_X, .Positive_X}, faces.curtains & {.Negative_X, .Positive_X}})
			}
			open := open_grazing_rays(triangles[:], rise)
			testing.expectf(t, open == 0, "%d rays pass the seam beside the coarse node %v at the rise %d", open, side[1].coordinate, rise)
		}
	}
	finer_side_only := make([dynamic][3][3]f64, context.temp_allocator)
	append_seam_triangles(&finer_side_only, fill_test_plane_grid({0, 0, 0}, 1, {0, 0}), {flaps = {.Negative_X}})
	append_seam_triangles(&finer_side_only, fill_test_plane_grid({-64, 0, 0}, 2, {0, 0}), {})
	testing.expect(t, open_grazing_rays(finer_side_only[:], 0) > 0, "the check finds the rays the finer node's flap alone leaves open")
}

// The review's scenes at a level seam (0321), in samples of the finest
// level, the finer node on the positive side of x = 0: a dug pit of
// radius 2.5 centred 1.5 samples into the finer node, a placed wall
// filling its first sample column, and a cliff stepping from y 30 on the
// coarser side to 20.5 with its top edge 1.5 samples into the finer node.
Test_Seam_Scene :: enum {
	Pit,
	Wall,
	Cliff,
}

// Flat ground below y = 20.5, in units of the step's spacing.
test_seam_flat_density :: proc(y, step: i64) -> i8 {
	return i8(clamp((41 - 2 * y) * DENSITY_STEPS_PER_SAMPLE / 2 / step, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
}

// A coarse grid's density of the scene at the sample: the pit and the
// wall as edits of the flat ground, which the coarse grid reads through
// coarse_field_density against the flat generation; the cliff as its
// depth over the step.
test_seam_scene_density :: proc(scene: Test_Seam_Scene, sample: [3]i64, step: i64) -> i8 {
	fine := test_seam_flat_density(sample.y, 1)
	switch scene {
	case .Pit:
		offset := [3]f64{f64(sample.x), f64(sample.y), f64(sample.z)} - {1.5, 19, 16.3}
		if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= 2.5 * 2.5 {
			fine = -MAXIMUM_DENSITY
		}
	case .Wall:
		if sample.x >= 0 && sample.x <= 1 && sample.y >= 20 && sample.y <= 26 && sample.z >= 10 && sample.z <= 22 {
			fine = MAXIMUM_DENSITY
		}
	case .Cliff:
		top_twice: i64 = sample.x <= 1 ? 60 : 41
		return i8(clamp((top_twice - 2 * sample.y) * DENSITY_STEPS_PER_SAMPLE / 2 / step, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
	}
	return coarse_field_density(fine, test_seam_flat_density(sample.y, step), i32(step))
}

// A half resolution grid of the scene, mirrored in x when mirrored.
fill_test_seam_scene_grid :: proc(origin: Sample_Coordinate, scene: Test_Seam_Scene, mirrored: bool) -> ^Field_Grid {
	grid := new(Field_Grid, context.temp_allocator)
	grid.origin, grid.step = origin, 2
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := ([3]i32)(origin) + [3]i32{x, y, z} * grid.step
				at := [3]i64{i64(sample.x), i64(sample.y), i64(sample.z)}
				if mirrored {
					at.x = -at.x
				}
				density := test_seam_scene_density(scene, at, i64(grid.step))
				index := field_grid_index({x, y, z})
				grid.density[index], grid.material[index] = density, density > 0 ? .Stone : .Air
			}
		}
	}
	return grid
}

// Whether the vertex lies in a cell the cut moves when the node's other
// faces border nodes of its level: y and z from 0 to under the last cell.
test_vertex_in_cut_rows :: proc(vertex: Field_Surface_Vertex) -> bool {
	cells := test_vertex_samples(vertex)
	return cells.y >= 0 && cells.y < FIELD_GRID_CELLS - 1 && cells.z >= 0 && cells.z < FIELD_GRID_CELLS - 1
}

// The coarser node of a level seam keeps its mesh in its box at the
// review's scenes (0321): with the cut and the curtain on its face
// towards the finer node, on either side, no vertex of its surface, cut
// or curtain lies past the face, outside the cells the cut leaves, and
// the curtain hangs. A vertex where the surface stands shallow to the
// face keeps main's lid and is left out (field_surface_steep_to_face):
// the cliff's face beside the coarse node on +x, parallel to the face
// plane. main's lid (the coarser cells at -1 over the finer node) and the
// first round's flap on that face lie past it.
@(test)
test_a_coarser_node_stays_out_of_the_finer_node :: proc(t: ^testing.T) {
	sides := [2]struct {
		origin:   Sample_Coordinate,
		faces:    Field_Seam_Faces,
		mirrored: bool,
	}{{{-64, 0, 0}, {curtains = {.Positive_X}}, false}, {{0, 0, 0}, {curtains = {.Negative_X}}, true}}
	for scene in Test_Seam_Scene {
		for side in sides {
			grid := fill_test_seam_scene_grid(side.origin, scene, side.mirrored)
			surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
			append_field_skirts(&surface, side.faces)
			past := 0
			for vertex in surface.vertices {
				x := test_grid_vertex_samples(grid, vertex).x
				cut_cell := test_vertex_in_cut_rows(vertex) && field_surface_steep_to_face(vertex.gradient, 0)
				if cut_cell && (side.mirrored ? x < -1e-9 : x > 1e-9) {
					past += 1
				}
			}
			testing.expectf(t, past == 0, "%v beside the coarse node at %v: %d vertices past the face", scene, side.origin, past)
			testing.expectf(t, len(surface.indices) > surface.skirt_index_start, "%v: the coarse node at %v hangs no curtain", scene, side.origin)
		}
	}
}

// The cut slides the coarser surface along itself (0321): on the planes
// of the grazing test, the coarse node's cut vertices at x = 0 lie no
// farther from the plane than the farthest of its other surface
// vertices (a cut that only set x would put them over a sample off at
// the steep rise), and none in the rows the cut moves lies past the face.
@(test)
test_the_cut_follows_the_coarser_surface :: proc(t: ^testing.T) {
	for rise in ([2]i64{0, STEEPEST_SHIPPED_RISE}) {
		grid := fill_test_plane_grid({0, 0, 0}, 2, {rise, 0})
		surface := mesh_field_surface(grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
		surface_vertex_count := len(surface.vertices)
		append_field_skirts(&surface, {curtains = {.Negative_X}})
		cut_farthest, other_farthest := 0.0, 0.0
		cut_count, past := 0, 0
		for vertex in surface.vertices[:surface_vertex_count] {
			position := test_grid_vertex_samples(grid, vertex)
			distance := abs(position.y - (2600 + f64(rise) * position.x) / DENSITY_STEPS_PER_SAMPLE)
			if position.x == 0 {
				cut_farthest = max(cut_farthest, distance)
				cut_count += 1
			} else {
				other_farthest = max(other_farthest, distance)
			}
			past += test_vertex_in_cut_rows(vertex) && position.x < 0 ? 1 : 0
		}
		testing.expectf(t, cut_count > 0 && cut_farthest <= other_farthest, "the rise %d: %d cut vertices up to %v samples off the plane, the others up to %v", rise, cut_count, cut_farthest, other_farthest)
		testing.expectf(t, past == 0, "the rise %d: %d vertices past the face", rise, past)
	}
}

// The cut leaves the cells a node of its level meshes too (0321): beside
// a node of its level on +x, the vertices of the cells at the corner of
// the cut face and the shared face stay where the neighbour's mesh puts
// them, so the two meshes do not part.
@(test)
test_the_cut_keeps_the_cells_a_neighbour_meshes :: proc(t: ^testing.T) {
	first := Field_Node{1, {0, 0, 0}}
	second := Field_Node{1, {1, 0, 0}}
	first_grid := fill_test_plane_grid(field_node_origin(first), field_node_step(first), {64, 222})
	second_grid := fill_test_plane_grid(field_node_origin(second), field_node_step(second), {64, 222})
	first_surface := mesh_field_surface(first_grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	second_surface := mesh_field_surface(second_grid, TEST_FIELD_PALETTE[:], context.temp_allocator)
	append_field_skirts(&first_surface, {curtains = {.Negative_Z}})
	append_field_skirts(&second_surface, {})
	shared, parted := 0, 0
	for y in i32(-1) ..< FIELD_GRID_CELLS {
		first_vertex := first_surface.cell_vertices[field_vertex_cell_index({FIELD_GRID_CELLS - 1, y, -1})]
		second_vertex := second_surface.cell_vertices[field_vertex_cell_index({-1, y, -1})]
		if first_vertex < 0 || second_vertex < 0 {
			continue
		}
		shared += 1
		first_position := test_grid_vertex_samples(first_grid, first_surface.vertices[first_vertex])
		second_position := test_grid_vertex_samples(second_grid, second_surface.vertices[second_vertex])
		parted += first_position == second_position ? 0 : 1
	}
	testing.expect(t, shared > 0, "the two nodes share a cell at the corner")
	testing.expectf(t, parted == 0, "%d of the %d shared vertices parted", parted, shared)
}

// The plane through (0, 20.3, z) with the normal, ground behind it, its
// density the distance in units of the grid's spacing.
fill_test_tilted_plane_grid :: proc(origin: Sample_Coordinate, step: i32, normal: [3]f64) -> ^Field_Grid {
	grid := new(Field_Grid, context.temp_allocator)
	grid.origin, grid.step = origin, step
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := ([3]i32)(origin) + [3]i32{x, y, z} * step
				offset := [3]f64{f64(sample.x), f64(sample.y) - 20.3, f64(sample.z)}
				depth := -linalg.dot(normal, offset) * DENSITY_STEPS_PER_SAMPLE / f64(step)
				density := i8(clamp(math.floor(depth), -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
				index := field_grid_index({x, y, z})
				grid.density[index], grid.material[index] = density, density > 0 ? .Stone : .Air
			}
		}
	}
	return grid
}

// The triangles with a corner within the distance of the point, nearest
// first, so a ray at the point meets its face early.
triangles_near :: proc(triangles: [][3][3]f64, point: [3]f64, distance: f64) -> [][3][3]f64 {
	Near_Triangle :: struct {
		triangle:         [3][3]f64,
		distance_squared: f64,
	}
	near := make([dynamic]Near_Triangle, context.temp_allocator)
	for triangle in triangles {
		nearest := min(linalg.length2(triangle[0] - point), linalg.length2(triangle[1] - point), linalg.length2(triangle[2] - point))
		if nearest < distance * distance {
			append(&near, Near_Triangle{triangle, nearest})
		}
	}
	slice.sort_by(near[:], proc(first, second: Near_Triangle) -> bool {return first.distance_squared < second.distance_squared})
	sorted := make([][3][3]f64, len(near), context.temp_allocator)
	for entry, index in near {
		sorted[index] = entry.triangle
	}
	return sorted
}

// A finest node beside a half resolution one across x = 0, on a plane
// that meets the face plane at the angle and faces the coarse node: rays
// from the air at targets on the ground near the face plane, in 400
// directions spread over the sphere (those from the ground's side left
// out), each from 16 samples back. Counts the rays that meet a front
// face of main's meshes (the coarse node without a cut or a curtain) but
// none of today's. A ray meets only triangles within 24 samples of its
// target: it starts 16 back, and no triangle spans 8.
lost_seam_rays :: proc(degrees: f64, coarse_on_positive: bool) -> (lost, aimed: int) {
	angle := math.to_radians(degrees)
	facing := coarse_on_positive ? 1.0 : -1.0
	normal := [3]f64{facing * math.cos(angle), math.sin(angle), 0}
	along_ground := [3]f64{-facing * math.sin(angle), math.cos(angle), 0}
	fine_origin := coarse_on_positive ? Sample_Coordinate{-32, 0, 0} : {0, 0, 0}
	coarse_origin := coarse_on_positive ? Sample_Coordinate{0, 0, 0} : {-64, 0, 0}
	fine_grid := fill_test_tilted_plane_grid(fine_origin, 1, normal)
	coarse_grid := fill_test_tilted_plane_grid(coarse_origin, 2, normal)
	today := make([dynamic][3][3]f64, context.temp_allocator)
	main_meshes := make([dynamic][3][3]f64, context.temp_allocator)
	append_seam_triangles(&today, fine_grid, {flaps = {field_face(0, coarse_on_positive)}})
	append_seam_triangles(&today, coarse_grid, {curtains = {field_face(0, !coarse_on_positive)}})
	append_seam_triangles(&main_meshes, fine_grid, {flaps = {field_face(0, coarse_on_positive)}})
	append_seam_triangles(&main_meshes, coarse_grid, {})
	DIRECTIONS :: 400
	golden_angle := math.PI * (3 - math.sqrt(5.0))
	for z in ([2]f64{8.3, 12.9}) {
		for distance in ([?]f64{-1, -0.5, -0.25, -0.1, 0, 0.1, 0.25, 0.5, 1}) {
			target := [3]f64{0, 20.3, z} + distance * along_ground
			today_near := triangles_near(today[:], target, 24)
			main_near := triangles_near(main_meshes[:], target, 24)
			for index in 0 ..< DIRECTIONS {
				height := 1 - 2 * (f64(index) + 0.5) / DIRECTIONS
				radius := math.sqrt(1 - height * height)
				turn := f64(index) * golden_angle
				direction := [3]f64{radius * math.cos(turn), height, radius * math.sin(turn)}
				if linalg.dot(direction, normal) > -0.02 {
					continue
				}
				aimed += 1
				origin := target - 16 * direction
				if !ray_meets_front_face(today_near, origin, direction) && ray_meets_front_face(main_near, origin, direction) {
					lost += 1
				}
			}
		}
	}
	return lost, aimed
}

// A level seam stays closed wherever main's was, at every angle between
// the ground and the face plane and from every direction (0321, decision
// 3): with the coarse node on either side and the ground facing it, no
// ray that meets a front face of main's meshes meets none of today's.
// The cut of every cell opened such rays below about 30 degrees, where
// the finer node's flap falls short of the face plane and the curtain
// shows the coarser side its back; the shallow cells keep main's lid.
@(test) // slow
test_a_level_seam_is_closed_at_every_angle_to_the_face :: proc(t: ^testing.T) {
	for degrees in ([?]f64{5, 10, 15, 20, 25, 31.5, 40, 60, 90}) {
		for coarse_on_positive in ([2]bool{true, false}) {
			lost, aimed := lost_seam_rays(degrees, coarse_on_positive)
			testing.expectf(t, aimed > 0 && lost == 0, "at %v degrees, the coarse node on +x %v: %d of %d rays that meet main's meshes meet nothing", degrees, coarse_on_positive, lost, aimed)
		}
	}
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
	append_field_skirts(&surface, {flaps = faces})
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

// The faces towards a coarser node or none hang flaps, those towards finer
// nodes curtains, those towards a node of the same level neither.
@(test)
test_the_skirt_faces_follow_the_neighbours_levels :: proc(t: ^testing.T) {
	fine := Field_Node{0, {0, 0, 0}}
	same := Field_Node{0, {0, 0, 1}}
	coarse := Field_Node{1, {-1, 0, 0}}
	selection := []Field_Node{fine, same, coarse, {0, {1, 0, 0}}, {0, {1, 1, 0}}, {0, {1, 0, 1}}, {0, {1, 1, 1}}}
	index := make_field_selection_index(selection, context.temp_allocator)
	testing.expect_value(t, field_node_skirt_faces(index, fine), Field_Seam_Faces{flaps = {.Negative_X, .Negative_Y, .Positive_Y, .Negative_Z}})
	// The coarse node's +x face borders the finer nodes.
	testing.expect_value(t, field_node_skirt_faces(index, coarse), Field_Seam_Faces{flaps = EVERY_FIELD_FACE - {.Positive_X}, curtains = {.Positive_X}})
}

// The sea's free surface lies at the sea level within 0.05 sample at
// latitude 0, 45 and 90 and at the steps 1, 2 and 4 (0294): the sea's
// samples draw its level as a plane, a signed distance in each grid's
// spacing, so no level of detail draws the staircase.
@(test) // slow
test_the_seas_surface_residual_is_small_at_every_latitude_and_level :: proc(t: ^testing.T) {
	planet := make_test_planet()
	planet.radius_metres = 1000
	planet.sea_level_metres = int(planet_relief_bounds(planet).highest / POSITION_UNITS_PER_METRE) + 8
	spacing := 1000
	generation := make_planet_generation(TEST_PLANET_SEED, planet, spacing)
	sea_level := field_sea_level(planet, spacing)
	sea_radius := f64(sea_level) / FIELD_WATER_FULL
	half := math.SQRT_TWO / 2
	directions := [3][3]f64{{1, 0, 0}, {half, half, 0}, {0, 1, 0}}
	for direction, latitude in directions {
		world: Field_World
		defer destroy_field_world(&world)
		world.water_planet = make_field_water_planet(TEST_PLANET_SEED, planet, spacing)
		// Half a chunk along the two tangents, so the surface crosses the
		// finest chunk's middle rather than its corner.
		tangent := [3]f64{-direction.y, direction.x, 0}
		centre := direction * sea_radius + tangent * FIELD_CHUNK_SIZE / 2 + {0, 0, FIELD_CHUNK_SIZE / 2}
		point := Sample_Coordinate{i32(math.round(centre.x)), i32(math.round(centre.y)), i32(math.round(centre.z))}
		finest := sample_to_field_chunk_coordinate(point)
		load :: proc(world: ^Field_World, planet: Planet, spacing: int, coordinate: Field_Chunk_Coordinate) {
			if coordinate in world.chunks {
				return
			}
			chunk := new(Field_Chunk)
			generate_field_chunk(TEST_PLANET_SEED, planet, spacing, coordinate, chunk)
			field_world_insert_chunk(world, chunk)
		}
		for level in i32(0) ..= 2 {
			grid: ^Field_Grid
			if level == 0 {
				for z in i32(-1) ..= 1 {
					for y in i32(-1) ..= 1 {
						for x in i32(-1) ..= 1 {
							load(&world, planet, spacing, finest + {x, y, z})
						}
					}
				}
				grid = gather_field_grid(&world, finest, nil, context.temp_allocator)
			} else {
				width := i32(1) << uint(level)
				node := Field_Node{level, {floor_divide(finest.x, width), floor_divide(finest.y, width), floor_divide(finest.z, width)}}
				for z in i32(0) ..< width {
					for y in i32(0) ..< width {
						for x in i32(0) ..< width {
							load(&world, planet, spacing, Field_Chunk_Coordinate(node.coordinate * width) + {x, y, z})
						}
					}
				}
				grid = gather_coarse_field_grid(&world, node, context.temp_allocator)
				generate_field_grid(generation, node, grid)
			}
			water := new(Field_Grid, context.temp_allocator)
			water.origin, water.step, water.density = grid.origin, grid.step, grid.water
			surface := mesh_field_surface(water, TEST_FIELD_PALETTE[:], context.temp_allocator)
			worst: f64 = 0
			counted := 0
			vertices: for vertex in surface.vertices {
				cell: [3]i32
				for axis in 0 ..< 3 {
					cell[axis] = floor_divide(vertex.position[axis], FIELD_MESH_POSITION_UNITS)
					if cell[axis] < 0 || cell[axis] >= FIELD_GRID_CELLS - 1 {
						continue vertices
					}
				}
				for corner in 0 ..< 8 {
					if grid.density[field_grid_index(cell + field_corner_offset(corner))] > 0 {
						continue vertices
					}
				}
				point := test_grid_vertex_samples(grid, vertex)
				residual := abs(math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z) - sea_radius)
				worst = max(worst, residual)
				counted += 1
			}
			fmt.printfln("0294: the sea at latitude %d, step %d: %d free surface vertices, the largest residual %v samples", latitude * 45, grid.step, counted, worst)
			testing.expectf(t, counted >= 100, "latitude %d, step %d: %d free surface vertices", latitude * 45, grid.step, counted)
			testing.expectf(t, worst < 0.05, "latitude %d, step %d: the surface lies %v samples off the sea level", latitude * 45, grid.step, worst)
		}
	}
}
