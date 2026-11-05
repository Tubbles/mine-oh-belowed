package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"

// Point lights of working parts (work item 0175, DESIGN.md: point lights
// come on top for working parts and never replace the field's light).
// Each frame the renderer gathers the lights of the parts that work (the
// arms' lamps, since work item 0224 the lamps a machine's record names
// and, since 0284, the field torches near the camera), keeps the
// MAXIMUM_POINT_LIGHTS nearest the camera and hands them
// to the field shader and the model shader (set_field_point_lights,
// set_model_point_lights), which add a soft term falling off to zero at
// each light's radius. Positions and radii are in the world's metres.
// A machine's lamp is clipped to its machine's box (0229,
// machine_light_clip_box), and a clipped light gives nothing to a face
// turned away from it, so the hull of a machine with a lamp inside stays
// dark outside; the arm's lamp has no box.
// The torchlight (0297, Spot_Light, torchlight_spot): a cone from the
// viewer's eye along its view, and the sun's direction and shares
// (Field_Frame_Lights, field_frame_lights), set per draw on both shaders.
// Pure; the shader uploads are in render_field.odin and render_models.odin.

// Matches the array size in data/shaders/field.fs and model.fs.
MAXIMUM_POINT_LIGHTS :: 8
// The arm's work lamp: a warm light that reaches a few cells round the
// gripper.
ARM_LIGHT_COLOR :: [3]f32{1.0, 0.72, 0.38}
ARM_LIGHT_RADIUS_METRES :: 3.0
// The rows of a light's clip box in point_light_boxes (model.fs), whose
// size is MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS.
POINT_LIGHT_BOX_ROWS :: 3
// The box is this much larger than the footprint on every side, so a
// model's faces on the footprint's faces count as inside: above
// MODEL_FOOTPRINT_TOLERANCE_CELLS (how far a model may leave its
// footprint) plus the f32 error of a world position 16 km from the
// planet's centre (about 0.006 cells on a 500 mm frame).
MACHINE_LIGHT_CLIP_PADDING_CELLS :: 0.05

// The torchlight's colour at a strength of 100 percent: a warm white.
TORCHLIGHT_COLOR :: [3]f32{1.0, 0.93, 0.8}

// The torchlight's cone as the shaders' spot_ uniforms take it: the eye,
// the unit view direction, the cosines of the full and the outer half
// angles, the reach in metres and the colour. A range of 0 is off, and
// every field is zero then.
Spot_Light :: struct {
	position:  [3]f32,
	direction: [3]f32,
	cos_inner: f32,
	cos_outer: f32,
	range:     f32,
	color:     [3]f32,
}

// What draw_field sets on the field shader each frame beside the
// daylight (set_field_frame_lights): the sun's unit direction in the
// world's frame, the sky light's share without the sun and the sun's,
// and the torchlight.
Field_Frame_Lights :: struct {
	sun_direction: [3]f32,
	sky_ambient:   f32,
	sun_strength:  f32,
	spot:          Spot_Light,
}

// The torchlight from the camera: off, the zero spot; on, the eye along
// the view with the config's cone, reach and strength.
torchlight_spot :: proc(camera: rl.Camera3D, config: Sun_And_Torchlight_Config, on: bool) -> Spot_Light {
	if !on {
		return {}
	}
	return Spot_Light {
		position  = camera.position,
		direction = linalg.normalize0(camera.target - camera.position),
		cos_inner = f32(math.cos(f64(config.torchlight_inner_cone_degrees) * math.RAD_PER_DEG)),
		cos_outer = f32(math.cos(f64(config.torchlight_outer_cone_degrees) * math.RAD_PER_DEG)),
		range     = f32(config.torchlight_range_metres),
		color     = TORCHLIGHT_COLOR * (f32(config.torchlight_strength_percent) / 100),
	}
}

// The frame's lights for a viewer with the camera: the sun of the day
// fraction turned into the world's frame for the camera's up, the
// config's shares and the torchlight when on.
field_frame_lights :: proc(fraction: f64, camera: rl.Camera3D, torchlight: bool, config: Sun_And_Torchlight_Config) -> Field_Frame_Lights {
	return Field_Frame_Lights {
		sun_direction = field_sun_world_direction(fraction, camera.up),
		sky_ambient   = f32(config.sky_ambient_percent) / 100,
		sun_strength  = f32(config.sun_strength_percent) / 100,
		spot          = torchlight_spot(camera, config, torchlight),
	}
}

Point_Light :: struct {
	position: [3]f32,
	color:    [3]f32,
	radius:   f32,
	// The world's metres to the light's machine box, -1 to 1 inside
	// (machine_light_clip_box); nil for a light that shines everywhere
	// (the arm's lamp, a record lamp with clip = false).
	clip_box: Maybe(matrix[4, 4]f32),
}

// The nearest lights to the camera, nearest first; the rest of the array
// has radius 0, which the shader skips. Ties keep the order of lights.
nearest_point_lights :: proc(lights: []Point_Light, camera: [3]f32) -> (nearest: [MAXIMUM_POINT_LIGHTS]Point_Light, count: int) {
	distances: [MAXIMUM_POINT_LIGHTS]f32
	for light in lights {
		offset := light.position - camera
		distance := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
		slot := count
		for slot > 0 && distances[slot - 1] > distance {
			slot -= 1
		}
		if slot >= MAXIMUM_POINT_LIGHTS {
			continue
		}
		last := min(count, MAXIMUM_POINT_LIGHTS - 1)
		for index := last; index > slot; index -= 1 {
			nearest[index], distances[index] = nearest[index - 1], distances[index - 1]
		}
		nearest[slot], distances[slot] = light, distance
		count = min(count + 1, MAXIMUM_POINT_LIGHTS)
	}
	return nearest, count
}

// The lights packed for the shaders' uniforms: the position with the
// radius in w; the colour with alpha 0 for a clipped light (the shaders
// give it nothing on a face turned away from it, and the field shader
// skips it) and 1 for the others; a clipped light's box as the first
// three rows of its matrix at index * POINT_LIGHT_BOX_ROWS, every other
// row zero, which the shader's box test passes.
point_light_uniform_values :: proc(lights: [MAXIMUM_POINT_LIGHTS]Point_Light) -> (positions, colors: [MAXIMUM_POINT_LIGHTS][4]f32, boxes: [MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS][4]f32) {
	for light, index in lights {
		positions[index] = {light.position.x, light.position.y, light.position.z, light.radius}
		colors[index] = {light.color.r, light.color.g, light.color.b, 1}
		box, clipped := light.clip_box.?
		if !clipped {
			continue
		}
		colors[index].a = 0
		for row in 0 ..< POINT_LIGHT_BOX_ROWS {
			boxes[index * POINT_LIGHT_BOX_ROWS + row] = {box[row, 0], box[row, 1], box[row, 2], box[row, 3]}
		}
	}
	return positions, colors, boxes
}

// The inverse of an affine matrix (last row 0, 0, 0, 1): the inverse of
// its upper left 3 by 3 and the translation moved back through it. Exact
// for any invertible affine matrix and steadier than the 4 by 4 cofactor
// inverse with translations of thousands of metres.
affine_inverse :: proc(transform: matrix[4, 4]f32) -> matrix[4, 4]f32 {
	inverse_linear := linalg.inverse(cast(matrix[3, 3]f32)transform)
	moved := -(inverse_linear * [3]f32{transform[0, 3], transform[1, 3], transform[2, 3]})
	result: matrix[4, 4]f32 = 1
	for row in 0 ..< 3 {
		for column in 0 ..< 3 {
			result[row, column] = inverse_linear[row, column]
		}
		result[row, 3] = moved[row]
	}
	return result
}

// The matrix from the world's metres to a machine's box, -1 to 1 inside
// on every axis (0229): the unrotated footprint in the model's frame (x
// and z centred, y from the bottom) up to the model's top when it rises
// higher, padded by MACHINE_LIGHT_CLIP_PADDING_CELLS on every side. body
// (entity_body_matrix) turns the model's frame, so footprint is the
// record's unrotated one.
machine_light_clip_box :: proc(body: matrix[4, 4]f32, footprint: [3]i32, top_cells: f32) -> matrix[4, 4]f32 {
	height := max(f32(footprint.y), top_cells)
	box_to_model := matrix[4, 4]f32{
		f32(footprint.x) / 2 + MACHINE_LIGHT_CLIP_PADDING_CELLS, 0, 0, 0,
		0, height / 2 + MACHINE_LIGHT_CLIP_PADDING_CELLS, 0, height / 2,
		0, 0, f32(footprint.z) / 2 + MACHINE_LIGHT_CLIP_PADDING_CELLS, 0,
		0, 0, 0, 1,
	}
	return affine_inverse(body * box_to_model)
}

// A machine's lamp (0224) in the world: the body matrix (entity_body_matrix)
// scales cells to metres and turns the model with its machine, so the
// position turns with it; the radius is a length and takes the pitch alone.
// A lamp that clips (0229) keeps clip_box, its machine's box
// (machine_light_clip_box), computed once per machine by the caller.
machine_point_light :: proc(light: Machine_Light, body: matrix[4, 4]f32, pitch_millimetres: int, clip_box: matrix[4, 4]f32) -> Point_Light {
	point := Point_Light {
		position = transform_point(body, light.position),
		color    = light.color,
		radius   = light.radius_cells * f32(f64(pitch_millimetres) / MILLIMETRES_PER_METRE),
	}
	if light.clip {
		point.clip_box = clip_box
	}
	return point
}
