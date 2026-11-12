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
// bounds from its origin and its cover's box, each when it draws.
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
	minimum, maximum, found := field_node_draw_box(origin, terrain, water, cover)
	testing.expect(t, found, "the three draw")
	testing.expect_value(t, minimum, [3]f32{97.5, 199, 297.5})
	testing.expect_value(t, maximum, [3]f32{104, 205, 304})
	unindexed := draw_box_test_mesh({1, 3, 1}, {2, 5, 2}, false)
	minimum, maximum, found = field_node_draw_box(origin, terrain, unindexed, cover)
	testing.expect(t, found, "the terrain and the cover draw")
	testing.expect_value(t, minimum, [3]f32{97.5, 199, 297.5})
	testing.expect_value(t, maximum, [3]f32{104, 201, 304})
	_, _, found = field_node_draw_box(origin, {}, {}, {})
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
	render.minimum, render.maximum, _ = field_node_draw_box(origin, mesh, {}, {})
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
