package game

import "core:testing"

@(test)
test_the_nearest_point_lights_are_kept_nearest_first :: proc(t: ^testing.T) {
	lights: [12]Point_Light
	for &light, index in lights {
		light = Point_Light{position = {f32(12 - index), 0, 0}, radius = 1}
	}
	nearest, count := nearest_point_lights(lights[:], {0, 0, 0})
	testing.expect_value(t, count, MAXIMUM_POINT_LIGHTS)
	for light, index in nearest {
		testing.expect_value(t, light.position.x, f32(index + 1))
	}
	few, few_count := nearest_point_lights(lights[:3], {10, 0, 0})
	testing.expect_value(t, few_count, 3)
	testing.expect_value(t, few[0].position.x, 10)
	testing.expect_value(t, few[3].radius, 0)
}

// Work item 0224: the packing the field and model shaders' uniforms take.
@(test)
test_point_light_uniform_values_pack_radius_and_colour :: proc(t: ^testing.T) {
	lights: [MAXIMUM_POINT_LIGHTS]Point_Light
	lights[0] = {position = {1, 2, 3}, color = {0.5, 0.25, 1}, radius = 4}
	lights[1] = {position = {-1, 0, 7}, color = {1, 1, 0}, radius = 2.5}
	positions, colors := point_light_uniform_values(lights)
	testing.expect_value(t, positions[0], [4]f32{1, 2, 3, 4})
	testing.expect_value(t, colors[0], [4]f32{0.5, 0.25, 1, 1})
	testing.expect_value(t, positions[1], [4]f32{-1, 0, 7, 2.5})
	testing.expect_value(t, colors[1], [4]f32{1, 1, 0, 1})
	// An unused slot goes up with radius 0, which the shaders skip; its
	// colour keeps alpha 1 as every slot's.
	for index in 2 ..< MAXIMUM_POINT_LIGHTS {
		testing.expect_value(t, positions[index], [4]f32{})
		testing.expect_value(t, colors[index], [4]f32{0, 0, 0, 1})
	}
}

// Work item 0224: a lamp at the front of a machine turned twice lies at
// its back, and its radius follows the frame's pitch.
@(test)
test_a_machine_light_turns_with_its_machine_and_scales_with_the_pitch :: proc(t: ^testing.T) {
	light := Machine_Light{position = {1.5, 2, 0}, color = {1, 0.5, 0.25}, radius_cells = 4}
	for pitch in ([2]int{500, 1000}) {
		frame := Frame{axes = {{UNIT_VECTOR_ONE, 0, 0}, {0, UNIT_VECTOR_ONE, 0}, {0, 0, UNIT_VECTOR_ONE}}, pitch_millimetres = pitch}
		metres := f32(pitch) / 1000
		expected := [4][3]f32{0 = {3.5, 2, 1}, 2 = {0.5, 2, 1}}
		for rotation in ([2]u8{0, 2}) {
			body := frame_render_matrix(frame) * model_transform({0, 0, 0}, {4, 3, 2}, rotation)
			point := machine_point_light(light, body, pitch)
			difference := point.position - expected[rotation] * metres
			testing.expectf(t, abs(difference.x) + abs(difference.y) + abs(difference.z) < 1e-4, "pitch %d rotation %d: %v", pitch, rotation, point.position)
			testing.expectf(t, abs(point.radius - 4 * metres) < 1e-4, "pitch %d: radius %v", pitch, point.radius)
			testing.expect_value(t, point.color, light.color)
		}
	}
}

// Work item 0224: the machines' lamps and the arms' share the eight
// slots by distance to the camera.
@(test)
test_nearest_point_lights_keep_machine_lights_and_arms_together :: proc(t: ^testing.T) {
	lights := make([dynamic]Point_Light, context.temp_allocator)
	for index in 1 ..= 6 {
		append(&lights, Point_Light{position = {f32(index), 0, 0}, color = {1, 0.6, 0.15}, radius = 3})
	}
	for x in ([3]f32{1.5, 2.5, 9}) {
		append(&lights, Point_Light{position = {x, 0, 0}, color = ARM_LIGHT_COLOR, radius = ARM_LIGHT_RADIUS_METRES})
	}
	nearest, count := nearest_point_lights(lights[:], {0, 0, 0})
	testing.expect_value(t, count, MAXIMUM_POINT_LIGHTS)
	expected := [MAXIMUM_POINT_LIGHTS]f32{1, 1.5, 2, 2.5, 3, 4, 5, 6}
	for light, index in nearest {
		testing.expect_value(t, light.position.x, expected[index])
		testing.expect(t, light.position.x != 9)
	}
}

// Work item 0224: the lit layer takes the model shader, the emissive one
// raylib's default material, so it never takes the point lights.
@(test)
test_the_emissive_layer_draws_with_the_default_material :: proc(t: ^testing.T) {
	renderer: Model_Renderer
	renderer.material.shader.id = 7
	renderer.emissive_material.shader.id = 3
	testing.expect_value(t, model_layer_material(renderer, .Lit).shader.id, 7)
	testing.expect_value(t, model_layer_material(renderer, .Emissive).shader.id, 3)
}
