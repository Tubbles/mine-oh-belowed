package game

import "core:math"
import "core:testing"
import rl "shared:raylib"

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

// The shipped sun_and_torchlight table of data/game.sjson.
shipped_sun_and_torchlight :: proc(t: ^testing.T) -> Sun_And_Torchlight_Config {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	return config.sun_and_torchlight
}

// Work item 0297: the torchlight's spot is the eye along the view with
// the config's cone, reach and strength; off it is the zero spot.
@(test)
test_the_torchlight_spot_follows_the_camera :: proc(t: ^testing.T) {
	config := shipped_sun_and_torchlight(t)
	camera := rl.Camera3D{position = {10, 20, 30}, target = {14, 20, 30}, up = {0, 1, 0}}
	spot := torchlight_spot(camera, config, true)
	testing.expect_value(t, spot.position, [3]f32{10, 20, 30})
	testing.expect_value(t, spot.direction, [3]f32{1, 0, 0})
	testing.expect(t, abs(f64(spot.cos_inner) - math.cos(28 * math.RAD_PER_DEG)) < 1e-5, "the inner cone's cosine")
	testing.expect(t, abs(f64(spot.cos_outer) - math.cos(36 * math.RAD_PER_DEG)) < 1e-5, "the outer cone's cosine")
	testing.expect_value(t, spot.range, 40)
	testing.expect_value(t, spot.color, TORCHLIGHT_COLOR)
	testing.expect_value(t, torchlight_spot(camera, config, false), Spot_Light{})
	half := config
	half.torchlight_strength_percent = 50
	testing.expect_value(t, torchlight_spot(camera, half, true).color, TORCHLIGHT_COLOR / 2)
}

// Field_Light_Inputs on a planet of 8 km with the shipped light, haze
// and atmosphere, a last distance of 1024 m and a ground colour.
test_field_light_inputs :: proc(t: ^testing.T, fraction: f64) -> Field_Light_Inputs {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	return Field_Light_Inputs {
		sky = day_sky_at(fraction, 0),
		daylight = 1,
		ground_color = {0.3, 0.5, 0.2},
		planet_radius_metres = 8000,
		last_distance_metres = 1024,
		light = config.sun_and_torchlight,
		haze = config.haze,
		atmosphere = config.atmosphere,
	}
}

// Work items 0297 and 0313: the frame's sun follows the clock, up at
// noon and down at midnight for an up on +y, with its light, the sky's
// and the ground's bounce from the clock, all scaled by the daylight.
@(test)
test_field_frame_lights_follow_the_clock :: proc(t: ^testing.T) {
	camera := rl.Camera3D{position = {0, 8002, 0}, target = {1, 8002, 0}, up = {0, 1, 0}}
	noon_inputs := test_field_light_inputs(t, NOON_FRACTION)
	noon := field_frame_lights(noon_inputs, camera, false)
	testing.expect(t, noon.sun_direction.y > 0.9, "noon up")
	testing.expect_value(t, noon.sun_color, sun_light_color(NOON_FRACTION, noon_inputs.light))
	testing.expect_value(t, noon.sky_color, sky_light_color(noon_inputs.sky.colors, noon_inputs.light))
	testing.expect_value(t, noon.flat_light, [3]f32{1, 1, 1})
	testing.expect_value(t, noon.spot, Spot_Light{})
	midnight := field_frame_lights(test_field_light_inputs(t, 0.75), camera, true)
	testing.expect(t, midnight.sun_direction.y < -0.9, "midnight down")
	testing.expect_value(t, midnight.sun_color, [3]f32{})
	testing.expect_value(t, midnight.flat_light, midnight.sky_color)
	testing.expect_value(t, midnight.spot.range, 40)
	dim_inputs := noon_inputs
	dim_inputs.daylight = 0.5
	dim := field_frame_lights(dim_inputs, camera, false)
	expect_near_color(t, dim.sun_color, noon.sun_color / 2, 1e-6, "half the sun")
	expect_near_color(t, dim.sky_color, noon.sky_color / 2, 1e-6, "half the sky")
	expect_near_color(t, dim.bounce_color, noon.bounce_color / 2, 1e-6, "half the bounce")
}

// Work item 0313: in the air the haze takes the ground's horizon colour,
// the full end fade and at dusk the glow; above the atmosphere's top the
// end fade's sky share and the glow are gone and the colour is space's.
@(test)
test_field_haze_follows_the_altitude :: proc(t: ^testing.T) {
	low := rl.Camera3D{position = {0, 8002, 0}, target = {1, 8002, 0}, up = {0, 1, 0}}
	noon_inputs := test_field_light_inputs(t, NOON_FRACTION)
	noon := field_frame_lights(noon_inputs, low, false).haze
	testing.expect_value(t, noon.end_share, 1)
	testing.expect_value(t, noon.color, color_to_vector3(noon_inputs.sky.colors.horizon))
	testing.expect_value(t, noon.globe_color, noon_inputs.ground_color)
	testing.expect_value(t, noon.density, f32(1) / 1500)
	testing.expect(t, abs(noon.fog_start - 614.4) < 1e-3, "the end fade starts at 0.6 of the last distance")
	testing.expect_value(t, noon.fog_end, 1024)
	testing.expect_value(t, noon.planet_radius, 8000)
	testing.expect_value(t, noon.eye_height, 2)
	testing.expect_value(t, noon.scale_height, f32(noon_inputs.atmosphere.scale_height_metres))
	dusk_inputs := test_field_light_inputs(t, 0.5)
	dusk := field_frame_lights(dusk_inputs, low, false).haze
	testing.expect_value(t, dusk.sun_color, haze_sun_glow_color(0.5, dusk_inputs.light, dusk_inputs.haze))
	high := rl.Camera3D{position = {0, 8800, 0}, target = {1, 8800, 0}, up = {0, 1, 0}}
	above := field_frame_lights(dusk_inputs, high, false).haze
	testing.expect_value(t, above.end_share, 0)
	testing.expect_value(t, above.sun_color, [3]f32{})
	testing.expect_value(t, above.color, color_to_vector3(SPACE_SKY_COLOR))
}
