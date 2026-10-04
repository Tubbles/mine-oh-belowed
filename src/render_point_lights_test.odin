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
	positions, colors, _ := point_light_uniform_values(lights)
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
			point := machine_point_light(light, body, pitch, 1)
			difference := point.position - expected[rotation] * metres
			testing.expectf(t, abs(difference.x) + abs(difference.y) + abs(difference.z) < 1e-4, "pitch %d rotation %d: %v", pitch, rotation, point.position)
			testing.expectf(t, abs(point.radius - 4 * metres) < 1e-4, "pitch %d: radius %v", pitch, point.radius)
			testing.expect_value(t, point.color, light.color)
			_, clipped := point.clip_box.?
			testing.expect(t, !clipped, "a hand built Machine_Light does not clip")
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

// The largest absolute coordinate of a world point in a light's box.
clip_box_reach :: proc(box: matrix[4, 4]f32, world: [3]f32) -> f32 {
	local := transform_point(box, world)
	return max(abs(local.x), abs(local.y), abs(local.z))
}

// Work item 0229: the clip box maps the padded footprint onto the unit
// box on both pitches, with the frame turned or not and under every
// rotation, a planet's radius from the centre; it rises to the model's
// top when that is higher than the footprint.
@(test)
test_the_clip_box_maps_the_footprint_to_the_unit_box :: proc(t: ^testing.T) {
	footprint := [3]i32{4, 3, 2}
	axes_choices := [2][3][3]i64{{{UNIT_VECTOR_ONE, 0, 0}, {0, UNIT_VECTOR_ONE, 0}, {0, 0, UNIT_VECTOR_ONE}}, {{0, 0, UNIT_VECTOR_ONE}, {0, UNIT_VECTOR_ONE, 0}, {-UNIT_VECTOR_ONE, 0, 0}}}
	for pitch in ([2]int{500, 1000}) {
		for axes in axes_choices {
			frame := Frame{origin = {8000 * POSITION_UNITS_PER_METRE, 0, 0}, axes = axes, pitch_millimetres = pitch}
			for rotation in u8(0) ..< 4 {
				body := frame_render_matrix(frame) * model_transform({5, 1, -3}, rotated_footprint_size(footprint, rotation), rotation)
				box := machine_light_clip_box(body, footprint, 3)
				for corner in 0 ..< 8 {
					signs := [3]f32{corner & 1 != 0 ? 1 : -1, corner & 2 != 0 ? 1 : -1, corner & 4 != 0 ? 1 : -1}
					model_point := [3]f32{2.05 * signs.x, signs.y > 0 ? 3.05 : -0.05, 1.05 * signs.z}
					local := transform_point(box, transform_point(body, model_point))
					difference := local - signs
					testing.expectf(t, max(abs(difference.x), abs(difference.y), abs(difference.z)) < 0.01, "pitch %d rotation %d corner %v: %v", pitch, rotation, model_point, local)
				}
				centre := transform_point(box, transform_point(body, [3]f32{0, 1.5, 0}))
				testing.expectf(t, max(abs(centre.x), abs(centre.y), abs(centre.z)) < 0.01, "pitch %d rotation %d: centre %v", pitch, rotation, centre)
				faces := [6][3]f32{{2, 1.5, 0}, {-2, 1.5, 0}, {0, 3, 0}, {0, 0, 0}, {0, 1.5, 1}, {0, 1.5, -1}}
				outward := [6][3]f32{{0.1, 0, 0}, {-0.1, 0, 0}, {0, 0.1, 0}, {0, -0.1, 0}, {0, 0, 0.1}, {0, 0, -0.1}}
				for face, index in faces {
					testing.expectf(t, clip_box_reach(box, transform_point(body, face)) <= 1, "pitch %d rotation %d: face %v outside", pitch, rotation, face)
					testing.expectf(t, clip_box_reach(box, transform_point(body, face + outward[index])) > 1, "pitch %d rotation %d: beyond face %v inside", pitch, rotation, face)
				}
				taller := machine_light_clip_box(body, footprint, 4.5)
				testing.expect(t, clip_box_reach(taller, transform_point(body, [3]f32{0, 4.4, 0})) <= 1)
				testing.expect(t, clip_box_reach(taller, transform_point(body, [3]f32{0, 4.6, 0})) > 1)
			}
		}
	}
}

// Work item 0229: the arm's lamp has no box, nor a record lamp with
// clip = false; a lamp that clips keeps its machine's box.
@(test)
test_the_arms_lamp_and_an_unclipped_lamp_have_no_box :: proc(t: ^testing.T) {
	arm, found := arm_point_light(Arm_Placement{transform = 1, dimensions = arm_dimensions_on_frame(4, 500), working = true})
	testing.expect(t, found)
	_, arm_clipped := arm.clip_box.?
	testing.expect(t, !arm_clipped, "the arm's lamp has no box")
	box := matrix[4, 4]f32{2, 0, 0, 1, 0, 3, 0, 2, 0, 0, 4, 3, 0, 0, 0, 1}
	unclipped := machine_point_light(Machine_Light{position = {0, 1, 0}, color = {1, 1, 1}, radius_cells = 2, clip = false}, 1, 500, box)
	_, unclipped_has_box := unclipped.clip_box.?
	testing.expect(t, !unclipped_has_box, "a lamp with clip = false has no box")
	clipped := machine_point_light(Machine_Light{position = {0, 1, 0}, color = {1, 1, 1}, radius_cells = 2, clip = true}, 1, 500, box)
	clipped_box, clipped_has_box := clipped.clip_box.?
	testing.expect(t, clipped_has_box, "a lamp that clips keeps the box")
	testing.expect_value(t, clipped_box, box)
}

// Work item 0229: a clipped light's box goes up as its matrix's first
// three rows in its slot's rows with colour alpha 0; every other row is
// zero and every other colour keeps alpha 1.
@(test)
test_point_light_uniform_values_pack_the_clip_boxes :: proc(t: ^testing.T) {
	box: matrix[4, 4]f32
	for row in 0 ..< 4 {
		for column in 0 ..< 4 {
			box[row, column] = f32(row * 4 + column + 1)
		}
	}
	lights: [MAXIMUM_POINT_LIGHTS]Point_Light
	lights[0] = {position = {1, 2, 3}, color = {1, 0.5, 0.25}, radius = 4, clip_box = box}
	lights[1] = {position = {4, 5, 6}, color = {1, 1, 1}, radius = 3}
	_, colors, boxes := point_light_uniform_values(lights)
	testing.expect_value(t, boxes[0], [4]f32{1, 2, 3, 4})
	testing.expect_value(t, boxes[1], [4]f32{5, 6, 7, 8})
	testing.expect_value(t, boxes[2], [4]f32{9, 10, 11, 12})
	for index in 3 ..< MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS {
		testing.expect_value(t, boxes[index], [4]f32{})
	}
	testing.expect_value(t, colors[0].a, 0)
	for index in 1 ..< MAXIMUM_POINT_LIGHTS {
		testing.expect_value(t, colors[index].a, 1)
	}
}
