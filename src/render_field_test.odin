package game

import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:testing"
import rl "shared:raylib"
import "render_frustum"

// Work item 0307: with a climate the globe takes the temperate moderate
// grass as the grass tile shows it, so the far planet reads green;
// without one the palette's first colour, as before.
@(test)
test_the_globe_takes_the_temperate_grass :: proc(t: ^testing.T) {
	planet := make_test_planet()
	gray := [3]f32{0.5, 0.5, 0.5}
	testing.expect_value(t, field_globe_color(planet, gray), opaque_test_color(planet.palette[0]))
	planet.climate = SHIPPED_TEST_CLIMATE
	temperate := planet.climate.grass_colors[4]
	testing.expect_value(t, field_globe_color(planet, gray), opaque_test_color(temperate))
	darker := field_globe_color(planet, {0.25, 0.25, 0.25})
	testing.expectf(t, abs(int(darker.g) * 2 - temperate.g) <= 1, "the grass tile's mean scales the globe: %v", darker)
}

opaque_test_color :: proc(color: [3]int) -> rl.Color {
	return {u8(color.r), u8(color.g), u8(color.b), 255}
}

// Work item 0342: profile settle's count of the selected nodes not yet
// drawable. A node is meshed once it is in the mesh revisions and has its
// meshes up or no job in flight.
@(test)
test_a_view_counts_the_selected_nodes_without_a_mesh :: proc(t: ^testing.T) {
	streaming: Field_Streaming
	renderer: Field_Renderer
	defer delete(streaming.mesh_revisions)
	defer delete(streaming.in_flight)
	defer delete(renderer.meshes)
	never_submitted := Field_Node{level = 0, coordinate = {0, 0, 0}}
	in_flight_bare := Field_Node{level = 0, coordinate = {1, 0, 0}}
	in_flight_drawn := Field_Node{level = 0, coordinate = {2, 0, 0}}
	meshed_empty := Field_Node{level = 0, coordinate = {3, 0, 0}}
	for node in ([?]Field_Node{in_flight_bare, in_flight_drawn, meshed_empty}) {
		streaming.mesh_revisions[node] = 1
	}
	streaming.in_flight[in_flight_bare] = 1
	streaming.in_flight[in_flight_drawn] = 1
	renderer.meshes[in_flight_drawn] = Field_Node_Render{has_mesh = true}
	cases := [?]struct {
		node:     Field_Node,
		unmeshed: int,
	}{{never_submitted, 1}, {in_flight_bare, 1}, {in_flight_drawn, 0}, {meshed_empty, 0}}
	for entry in cases {
		selection := [1]Field_Node{entry.node}
		testing.expectf(t, field_view_unmeshed_nodes(&streaming, &renderer, selection[:]) == entry.unmeshed, "%v", entry.node)
	}
	every := [?]Field_Node{never_submitted, in_flight_bare, in_flight_drawn, meshed_empty}
	testing.expect_value(t, field_view_unmeshed_nodes(&streaming, &renderer, every[:]), 2)
}

// Work item 0348: every change of the renderer's meshes moves its
// revision, which asks the sun's kept shadow maps for the terrain's
// fingerprint.
@(test)
test_mesh_changes_move_the_renderer_revision :: proc(t: ^testing.T) {
	renderer := Field_Renderer{spacing_millimetres = 1000}
	defer delete(renderer.meshes)
	node := Field_Node{level = 0, coordinate = {0, 250, 0}}
	renderer.meshes[node] = Field_Node_Render{}
	unload_field_node(&renderer, node)
	testing.expect_value(t, renderer.mesh_revision, u64(1))
	testing.expect(t, node not_in renderer.meshes, "the node is gone")
	unload_field_node(&renderer, node)
	testing.expect_value(t, renderer.mesh_revision, u64(1))
	apply_field_mesh(&renderer, node, {}, {}, 0)
	testing.expect_value(t, renderer.mesh_revision, u64(2))
	testing.expect(t, node not_in renderer.meshes, "two empty meshes store nothing")
}

// Two positions and a triangle's indices, its bounds set as
// field_mesh_from_surface sets them.
draw_box_test_mesh :: proc(first, second: [3]f32, with_indices := true) -> Field_Mesh_Data {
	data := make_field_mesh_data(context.temp_allocator)
	append(&data.positions, first, second)
	if with_indices {
		append(&data.indices, 0, 1, 1)
	}
	data.minimum, data.maximum = field_positions_bounds(data.positions[:])
	return data
}

// Work item 0349: a node's draw box joins its terrain's and its water's
// bounds from its origin and its cover's box, each when it draws. The
// meshes' bounds are samples, scaled by the metres of a sample; the
// cover's are world metres (0381).
@(test)
test_the_draw_box_joins_the_terrain_the_water_and_the_cover :: proc(t: ^testing.T) {
	origin := [3]f32{100, 200, 300}
	terrain := draw_box_test_mesh({0, 0, 0}, {4, 1, 4})
	water := draw_box_test_mesh({1, 3, 1}, {2, 5, 2})
	cover: Field_Cover_Data
	cover.kinds[0].instances = make([dynamic]matrix[4, 4]f32, context.temp_allocator)
	append(&cover.kinds[0].instances, matrix[4, 4]f32{
		2, 0, 0, 99,
		0, 2, 0, 199,
		0, 0, 2, 299,
		0, 0, 0, 1,
	})
	cover.minimum, cover.maximum, _ = cover_instances_box(cover.kinds[:])
	testing.expect_value(t, cover.minimum, [3]f32{97.5, 199, 297.5})
	testing.expect_value(t, cover.maximum, [3]f32{100.5, 201, 300.5})
	minimum, maximum, found := field_node_draw_box(origin, 1, terrain, water, cover)
	testing.expect(t, found, "the three draw")
	testing.expect_value(t, minimum, [3]f32{97.5, 199, 297.5})
	testing.expect_value(t, maximum, [3]f32{104, 205, 304})
	minimum, maximum, found = field_node_draw_box(origin, 0.5, terrain, water, cover)
	testing.expect(t, found, "the three draw at half a metre a sample")
	testing.expect_value(t, minimum, [3]f32{97.5, 199, 297.5})
	testing.expect_value(t, maximum, [3]f32{102, 202.5, 302})
	unindexed := draw_box_test_mesh({1, 3, 1}, {2, 5, 2}, false)
	minimum, maximum, found = field_node_draw_box(origin, 1, terrain, unindexed, cover)
	testing.expect(t, found, "the terrain and the cover draw")
	testing.expect_value(t, minimum, [3]f32{97.5, 199, 297.5})
	testing.expect_value(t, maximum, [3]f32{104, 201, 304})
	_, _, found = field_node_draw_box(origin, 1, {}, {}, {})
	testing.expect(t, !found, "nothing draws")
}

// A sphere of 3 samples in the node {0, {-2, -1, -2}} at 1000 mm, left of
// the left plane of a camera at the origin looking down -z.
test_culled_sphere_density :: proc(sample: [3]i64) -> i8 {
	return test_sphere_density(sample, {-62, -30, -34}, 3 * DENSITY_STEPS_PER_SAMPLE)
}

// Work item 0349: a node whose mesh lies outside the frustum is culled
// though its cube widened by 4 cells meets it.
@(test)
test_a_node_is_culled_by_its_mesh_not_its_cube :: proc(t: ^testing.T) {
	node := Field_Node{level = 0, coordinate = {-2, -1, -2}}
	origin := field_node_origin_metres(node, 1000)
	testing.expect_value(t, origin, [3]f32{-64, -32, -64})
	mesh := mesh_field_grid(fill_test_field_grid(field_node_origin(node), 1, test_culled_sphere_density), TEST_FIELD_PALETTE[:], 1000, {}, context.temp_allocator)
	testing.expect(t, len(mesh.indices) > 0, "the sphere meshes")
	render := Field_Node_Render{origin = origin, has_mesh = true}
	render.minimum, render.maximum, _ = field_node_draw_box(origin, 1, mesh, {}, {})
	projection := linalg.matrix4_perspective_f32(90 * math.RAD_PER_DEG, 1, 0.1, 200)
	ahead := render_frustum.frustum_from_matrix(projection * linalg.matrix4_look_at_f32({0, 0, 0}, {0, 0, -1}, {0, 1, 0}))
	testing.expect(t, render_frustum.frustum_contains_box(ahead, {-68, -36, -68}, {-28, 4, -28}), "the old cube widened by 4 cells meets the frustum")
	testing.expectf(t, !field_node_in_frustum(ahead, render), "the sphere's box %v to %v lies left of the left plane", render.minimum, render.maximum)
	left := render_frustum.frustum_from_matrix(projection * linalg.matrix4_look_at_f32({0, 0, 0}, {-1, 0, 0}, {0, 1, 0}))
	testing.expect(t, field_node_in_frustum(left, render), "looking down -x the sphere is in view")
}

// Work item 0349: the globe draws after the terrain and the cover, which
// are opaque, and the water draws last over the terrain's visible list.
@(test)
test_the_globe_draws_after_the_opaque_field :: proc(t: ^testing.T) {
	order := FIELD_PASS_ORDER
	testing.expect_value(t, order[0], Field_Pass.Terrain)
	testing.expect_value(t, order[len(order) - 1], Field_Pass.Water)
	passes: bit_set[Field_Pass]
	for pass in order {
		passes += {pass}
	}
	testing.expect_value(t, passes, bit_set[Field_Pass]{.Terrain, .Cover, .Globe, .Water})
	globe, _ := slice.linear_search(order[:], Field_Pass.Globe)
	terrain, _ := slice.linear_search(order[:], Field_Pass.Terrain)
	cover, _ := slice.linear_search(order[:], Field_Pass.Cover)
	testing.expect(t, globe > terrain && globe > cover, "the globe draws after the terrain and the cover")
}

// Work item 0381's places on an 8 km planet: 0380's cave capture, the
// home stand and two more.
ANCHOR_TEST_PLACES :: [4][2]f64{{79.007, 151.054}, {83.171, 130.477}, {0, 0}, {-45, -135}}
ANCHOR_TEST_RADIUS_METRES :: 8000

// The up at a latitude and longitude in degrees, laid out as
// planet_direction_at's.
test_place_up :: proc(latitude, longitude: f64) -> [3]f64 {
	across := math.cos(latitude * math.RAD_PER_DEG)
	return {across * math.cos(longitude * math.RAD_PER_DEG), math.sin(latitude * math.RAD_PER_DEG), across * math.sin(longitude * math.RAD_PER_DEG)}
}

// A place's up, its point on the planet in samples, a tangent and the
// test ground's normal, tilted off the up.
Anchor_Test_Place :: struct {
	up, point, tangent, normal: [3]f64,
}

anchor_test_place :: proc(latitude, longitude: f64, spacing_millimetres: int) -> Anchor_Test_Place {
	up := test_place_up(latitude, longitude)
	return {
		up = up,
		point = up * ANCHOR_TEST_RADIUS_METRES / anchor_test_metres_per_sample(spacing_millimetres),
		tangent = linalg.normalize(linalg.cross(up, [3]f64{0, 0, 1})),
		normal = linalg.normalize(up + {0.3, 0.2, -0.4}),
	}
}

anchor_test_metres_per_sample :: proc(spacing_millimetres: int) -> f64 {
	return f64(spacing_millimetres) / MILLIMETRES_PER_METRE
}

// The node's grid of the plane through point with the normal, both in
// samples: stone below, air above, the density in the grid's own spacing
// (temp allocator).
fill_test_ground_grid :: proc(node: Field_Node, point, normal: [3]f64) -> ^Field_Grid {
	grid := new(Field_Grid, context.temp_allocator)
	grid.origin, grid.step = field_node_origin(node), field_node_step(node)
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := ([3]i32)(grid.origin) + [3]i32{x, y, z} * grid.step
				distance := linalg.dot(point - [3]f64{f64(sample.x), f64(sample.y), f64(sample.z)}, normal)
				density := i8(clamp(math.round(distance * DENSITY_STEPS_PER_SAMPLE / f64(grid.step)), -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
				index := field_grid_index({x, y, z})
				grid.density[index] = density
				grid.material[index] = density > 0 ? Field_Material.Stone : Field_Material.Air
			}
		}
	}
	return grid
}

// The level's node holding a point in samples.
anchor_test_node :: proc(level: i32, point: [3]f64) -> Field_Node {
	samples := f64(field_node_samples(level))
	return {level, {i32(math.floor(point.x / samples)), i32(math.floor(point.y / samples)), i32(math.floor(point.z / samples))}}
}

// The node's terrain from the plane, without skirts.
anchor_test_mesh :: proc(node: Field_Node, point, normal: [3]f64, spacing_millimetres: int) -> Field_Mesh_Data {
	return mesh_field_grid(fill_test_ground_grid(node, point, normal), TEST_FIELD_PALETTE[:], spacing_millimetres, {}, context.temp_allocator)
}

// A vertex's world position in samples, exact in f64.
anchor_test_world_sample :: proc(origin: Sample_Coordinate, position: [3]f32) -> [3]f64 {
	return {f64(origin.x) + f64(position.x), f64(origin.y) + f64(position.y), f64(origin.z) + f64(position.z)}
}

anchor_test_f32 :: proc(vector: [3]f64) -> [3]f32 {
	return {f32(vector.x), f32(vector.y), f32(vector.z)}
}

// The three eyes about a centre in metres: 1.6 m up and 2 m along the
// tangent, 1.6 m up and 40 m along, 20 m up and 300 m along.
anchor_test_eyes :: proc(centre, up, tangent: [3]f64) -> (eyes: [3][3]f32) {
	offsets := [3][2]f64{{1.6, 2}, {1.6, 40}, {20, 300}}
	for offset, index in offsets {
		eyes[index] = anchor_test_f32(centre + up * offset[0] + tangent * offset[1])
	}
	return eyes
}

// An eye's view looking at the centre with the up as its up, and a 16 by
// 9 viewport's projection.
anchor_test_matrices :: proc(eye: [3]f32, centre, up: [3]f64) -> (view, projection: rl.Matrix) {
	view = rl.MatrixLookAt(eye, anchor_test_f32(centre), anchor_test_f32(up))
	projection = rl.MatrixPerspective(70 * math.RAD_PER_DEG, 16.0 / 9.0, FIELD_NEAR_METRES, 32000)
	return view, projection
}

anchor_test_clip :: proc(transform: rl.Matrix, position: [3]f32) -> [4]f32 {
	return transform * [4]f32{position.x, position.y, position.z, 1}
}

// The pairs of the first and the second node's vertex indices at one
// world sample: the second's vertices below its origin along the axis
// (its cells -1, the first's last cells) matched to the first's.
anchor_test_shared_vertices :: proc(first: Field_Node, first_mesh: Field_Mesh_Data, second: Field_Node, second_mesh: Field_Mesh_Data, axis: int) -> [][2]int {
	by_place := make(map[[3]f64]int, context.temp_allocator)
	for position, index in first_mesh.positions {
		by_place[anchor_test_world_sample(field_node_origin(first), position)] = index
	}
	pairs := make([dynamic][2]int, context.temp_allocator)
	for position, index in second_mesh.positions {
		if position[axis] >= 0 {
			continue
		}
		if match, found := by_place[anchor_test_world_sample(field_node_origin(second), position)]; found {
			append(&pairs, [2]int{match, index})
		}
	}
	return pairs[:]
}

// The old path at 1000 mm: the projection times the view times the node's
// translation, multiplied in f32 as raylib's DrawMesh does.
anchor_test_old_transform :: proc(view, projection: rl.Matrix, node: Field_Node) -> rl.Matrix {
	origin := field_node_origin_metres(node, 1000)
	return projection * (view * rl.MatrixTranslate(origin.x, origin.y, origin.z))
}

// Whether the old path puts a pair on different clip positions.
anchor_test_old_path_parts :: proc(view, projection: rl.Matrix, first, second: Field_Node, first_mesh, second_mesh: Field_Mesh_Data, pairs: [][2]int) -> bool {
	first_transform := anchor_test_old_transform(view, projection, first)
	second_transform := anchor_test_old_transform(view, projection, second)
	for pair in pairs {
		if anchor_test_clip(first_transform, first_mesh.positions[pair[0]]) != anchor_test_clip(second_transform, second_mesh.positions[pair[1]]) {
			return true
		}
	}
	return false
}

// Work item 0381: two neighbouring nodes of one level put every vertex
// they share at the same samples from the anchor, bit for bit, and so on
// one clip position, at every spacing, at levels 0 and 1, across each
// axis, from a near and two farther eyes; the old path, a model matrix
// per node, did not.
@(test) // slow
test_neighbouring_nodes_share_their_border_vertices_bit_for_bit :: proc(t: ^testing.T) {
	places := ANCHOR_TEST_PLACES
	old_path_parts := false
	for spacing in ([3]int{1000, 500, 333}) {
		for level in i32(0) ..= 1 {
			for coordinates, place_index in places {
				place := anchor_test_place(coordinates[0], coordinates[1], spacing)
				for axis in 0 ..< 3 {
					first := anchor_test_node(level, place.point)
					second := first
					second.coordinate[axis] += 1
					// The centre of their shared face, in samples.
					half := f64(field_node_samples(level)) / 2
					face := anchor_test_world_sample(field_node_origin(first), {}) + half
					face[axis] += half
					first_mesh := anchor_test_mesh(first, face, place.normal, spacing)
					second_mesh := anchor_test_mesh(second, face, place.normal, spacing)
					pairs := anchor_test_shared_vertices(first, first_mesh, second, second_mesh, axis)
					testing.expectf(t, len(pairs) >= 16, "%d mm, level %d, place %d, axis %d: %d shared vertices", spacing, level, place_index, axis, len(pairs))
					centre := face * anchor_test_metres_per_sample(spacing)
					eyes := anchor_test_eyes(centre, place.up, place.tangent)
					for eye, eye_index in eyes {
						view, projection := anchor_test_matrices(eye, centre, place.up)
						anchor := field_anchor(view, projection, eye, spacing)
						parted := 0
						for pair in pairs {
							first_position := field_node_anchor_offset(field_node_origin(first), anchor.sample) + first_mesh.positions[pair[0]]
							second_position := field_node_anchor_offset(field_node_origin(second), anchor.sample) + second_mesh.positions[pair[1]]
							sums_part := transmute([3]u32)first_position != transmute([3]u32)second_position
							clips_part := transmute([4]u32)anchor_test_clip(anchor.view_projection, first_position) != transmute([4]u32)anchor_test_clip(anchor.view_projection, second_position)
							parted += sums_part || clips_part ? 1 : 0
						}
						testing.expectf(t, parted == 0, "%d mm, level %d, place %d, axis %d, eye %d: %d of %d shared vertices part", spacing, level, place_index, axis, eye_index, parted, len(pairs))
						if spacing == 1000 && level == 0 && place_index == 0 && eye_index == 0 {
							old_path_parts ||= anchor_test_old_path_parts(view, projection, first, second, first_mesh, second_mesh, pairs)
						}
					}
				}
				free_all(context.temp_allocator)
			}
		}
	}
	testing.expect(t, old_path_parts, "the old path put every shared vertex at the capture's place on one clip position, so the test does not see the cracks")
}

// The view applied to a world position in metres, in f64.
anchor_test_exact_eye :: proc(view: rl.Matrix, world: [3]f64) -> (eye: [3]f64) {
	for row in 0 ..< 3 {
		eye[row] = f64(view[row, 3])
		for column in 0 ..< 3 {
			eye[row] += f64(view[row, column]) * world[column]
		}
	}
	return eye
}

anchor_test_eye :: proc(transform: rl.Matrix, position: [3]f32) -> [3]f64 {
	eye := anchor_test_clip(transform, position)
	return {f64(eye.x), f64(eye.y), f64(eye.z)}
}

// Work item 0381: the anchored pass keeps the picture. For a level 0 node
// at the place and a level 2 node 300 m along the tangent, from the near
// and the far eye, a vertex's eye space position under the anchored view
// lies within 3e-7 of its distance plus a micrometre of the view applied
// to its exact world position in f64, and within 2 mm of the old path's
// (the view times the node's translation, positions in metres). The
// anchor lies within half a sample of the eye; at 1000 mm the anchored
// view keeps the view's rotation and the shadow's model matrix is the
// node's translation.
@(test)
test_the_anchored_pass_keeps_the_picture :: proc(t: ^testing.T) {
	places := ANCHOR_TEST_PLACES
	for spacing in ([2]int{1000, 333}) {
		metres_per_sample := anchor_test_metres_per_sample(spacing)
		for place_index in 0 ..< 2 {
			place := anchor_test_place(places[place_index][0], places[place_index][1], spacing)
			along := place.point + place.tangent * 300 / metres_per_sample
			nodes := [2]Field_Node{anchor_test_node(0, place.point), anchor_test_node(2, along)}
			meshes := [2]Field_Mesh_Data{anchor_test_mesh(nodes[0], place.point, place.normal, spacing), anchor_test_mesh(nodes[1], along, place.normal, spacing)}
			centre := place.point * metres_per_sample
			eyes := anchor_test_eyes(centre, place.up, place.tangent)
			near_and_far := [2][3]f32{eyes[0], eyes[2]}
			for eye in near_and_far {
				view, projection := anchor_test_matrices(eye, centre, place.up)
				anchor := field_anchor(view, projection, eye, spacing)
				anchored := field_anchored_view(view, anchor.sample, spacing)
				off_exact, off_old, vertices := 0, 0, 0
				worst_exact, worst_old: f64
				for node, node_index in nodes {
					origin := field_node_origin(node)
					translation := field_node_origin_metres(node, spacing)
					old_model_view := view * rl.MatrixTranslate(translation.x, translation.y, translation.z)
					for position in meshes[node_index].positions {
						anchored_eye := anchor_test_eye(anchored, field_node_anchor_offset(origin, anchor.sample) + position)
						exact_eye := anchor_test_exact_eye(view, anchor_test_world_sample(origin, position) * metres_per_sample)
						old_eye := anchor_test_eye(old_model_view, position * field_metres_per_sample(spacing))
						from_exact := linalg.length(anchored_eye - exact_eye)
						from_old := linalg.length(anchored_eye - old_eye)
						off_exact += from_exact > 3e-7 * linalg.length(exact_eye) + 1e-6 ? 1 : 0
						off_old += from_old > 2e-3 ? 1 : 0
						worst_exact, worst_old = max(worst_exact, from_exact), max(worst_old, from_old)
						vertices += 1
					}
				}
				testing.expectf(t, vertices > 100, "%d mm, place %d: %d vertices", spacing, place_index, vertices)
				testing.expectf(t, off_exact == 0, "%d mm, place %d, eye %v: %d vertices lie off the exact eye position, the worst %v m", spacing, place_index, eye, off_exact, worst_exact)
				testing.expectf(t, off_old == 0, "%d mm, place %d, eye %v: %d vertices moved over 2 mm from the old path, the worst %v m", spacing, place_index, eye, off_old, worst_old)
			}
			free_all(context.temp_allocator)
		}
	}
	for spacing in ([3]int{1000, 500, 333}) {
		metres_per_sample := anchor_test_metres_per_sample(spacing)
		for coordinates in places {
			place := anchor_test_place(coordinates[0], coordinates[1], spacing)
			eyes := anchor_test_eyes(place.point * metres_per_sample, place.up, place.tangent)
			for eye in eyes {
				sample := field_anchor_sample(eye, spacing)
				for axis in 0 ..< 3 {
					testing.expectf(t, abs(f64(eye[axis]) - f64(sample[axis]) * metres_per_sample) <= metres_per_sample / 2 + 1e-9, "%d mm: the anchor %v lies over half a sample from the eye %v", spacing, sample, eye)
				}
			}
		}
	}
	// At 1000 mm a sample is a metre, so the place's point is in metres.
	place := anchor_test_place(places[0][0], places[0][1], 1000)
	eyes := anchor_test_eyes(place.point, place.up, place.tangent)
	view, _ := anchor_test_matrices(eyes[0], place.point, place.up)
	anchored := field_anchored_view(view, field_anchor_sample(eyes[0], 1000), 1000)
	for row in 0 ..< 4 {
		for column in 0 ..< 3 {
			testing.expectf(t, transmute(u32)anchored[row, column] == transmute(u32)view[row, column], "at 1000 mm the anchored view's [%d, %d] %v is not the view's %v", row, column, anchored[row, column], view[row, column])
		}
	}
	origin := field_node_origin_metres(anchor_test_node(0, place.point), 1000)
	testing.expect(t, transmute([16]u32)field_node_transform(origin, 1) == transmute([16]u32)rl.MatrixTranslate(origin.x, origin.y, origin.z), "at 1000 mm the shadow's model matrix is the node's translation")
}
