package game

import "core:testing"
import rl "shared:raylib"

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
