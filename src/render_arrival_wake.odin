package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// The entry's wake (work item 0304, doc/presentation.md, The arrival):
// the plasma streaming straight aft from the heat shield's rim as a tube
// about the pod's axis, and the shield's glow as a disc under its base,
// both in the pod's model frame (cells, y up from the base, so +y is aft
// during the descent) and drawn after the scene for every viewer, the
// chair through its portholes as a camera outside. Everything here is a
// pure function of the arrival's view, the seed and the record, so a
// joiner or a load sees the same flames. Nothing here is simulation
// state.

// The wake's shaders (arrival_wake.vs, arrival_wake.fs).
ARRIVAL_WAKE_VERTEX_SHADER_PATH :: "shaders/arrival_wake.vs"
ARRIVAL_WAKE_FRAGMENT_SHADER_PATH :: "shaders/arrival_wake.fs"
// The tube's flat sides round the axis, and the disc's triangles.
ARRIVAL_WAKE_SIDES :: 32
// The tube's flats stand this far outside the rim, in cells.
ARRIVAL_WAKE_RIM_CLEARANCE_CELLS :: 0.05
// The tube's length in shield diameters (the reference's 1 to 2, the far
// quarter faded out).
ARRIVAL_WAKE_LENGTH_DIAMETERS :: 2.0
// The light along the flow halves every this many shield diameters at
// the peak, half as many at heat 0 (the KSP measurement of 0303).
ARRIVAL_WAKE_HALF_LIGHT_DIAMETERS :: 0.25
// The disc lies this far under the base, in cells.
ARRIVAL_WAKE_SHIELD_DROP_CELLS :: 0.03
// The mean intensity 0288's sheath showed on the chair's glass at the
// peak, so wake_opacity_percent is the mean opacity there.
ARRIVAL_WAKE_REFERENCE_INTENSITY :: 0.8
// The hot stop's share of the way from the ablator to the core colour:
// the gold where KSP's trail leaves the rim (0305).
ARRIVAL_WAKE_HOT_SHARE :: 0.3
// The colours the wake's shader mixes: the haze, the ablator and the hot
// gold (the ramp's three), then the core (the disc and the sparks).
ARRIVAL_WAKE_RAMP_STOPS :: 4

// The wake's shape in cells: the tube's vertex radius (its flats
// ARRIVAL_WAKE_RIM_CLEARANCE_CELLS outside the rim), its length and the
// disc's radius (the rim's). All 0 without a heat shield.
Arrival_Wake_Shape :: struct {
	radius, length, shield_radius: f32,
}

// The wake of a heat shield; {} without one.
arrival_wake_shape :: proc(heat_shield: Pod_Heat_Shield_Definition) -> Arrival_Wake_Shape {
	if heat_shield.radius <= 0 {
		return {}
	}
	return {
		radius = (heat_shield.radius + ARRIVAL_WAKE_RIM_CLEARANCE_CELLS) / math.cos(f32(math.PI) / ARRIVAL_WAKE_SIDES),
		length = ARRIVAL_WAKE_LENGTH_DIAMETERS * 2 * heat_shield.radius,
		shield_radius = heat_shield.radius,
	}
}

// The azimuth of corner step round the axis, a step 0 for the last
// corner, so the seam's corners come out bit equal.
arrival_wake_azimuth :: proc(step: int) -> f32 {
	return f32(step % ARRIVAL_WAKE_SIDES) / ARRIVAL_WAKE_SIDES * math.TAU
}

// The point at azimuth, radius from the axis and height y.
arrival_wake_point :: proc(azimuth, radius, y: f32) -> [3]f32 {
	return {radius * math.cos(azimuth), y, radius * math.sin(azimuth)}
}

// Quad index of the tube: its corners at the rim's two azimuths and the
// end's, and their texture coordinates, x the share of the turn (the
// last quad reaching 1, never running back) and y the cells along the
// flow.
arrival_wake_quad :: proc(shape: Arrival_Wake_Shape, index: int) -> (corners: [4][3]f32, coordinates: [4][2]f32) {
	first, second := arrival_wake_azimuth(index), arrival_wake_azimuth(index + 1)
	corners = {
		arrival_wake_point(first, shape.radius, 0),
		arrival_wake_point(second, shape.radius, 0),
		arrival_wake_point(second, shape.radius, shape.length),
		arrival_wake_point(first, shape.radius, shape.length),
	}
	left, right := f32(index) / ARRIVAL_WAKE_SIDES, f32(index + 1) / ARRIVAL_WAKE_SIDES
	coordinates = {{left, 0}, {right, 0}, {right, shape.length}, {left, shape.length}}
	return
}

// The outward normal of quad index, unit.
arrival_wake_quad_normal :: proc(index: int) -> [3]f32 {
	azimuth := (f32(index) + 0.5) / ARRIVAL_WAKE_SIDES * math.TAU
	return {math.cos(azimuth), 0, math.sin(azimuth)}
}

// Triangle index of the disc: its centre and the rim's two azimuths,
// ARRIVAL_WAKE_SHIELD_DROP_CELLS under the base, and their texture
// coordinates, x the share of the turn and y the share of the radius.
arrival_wake_shield_triangle :: proc(shape: Arrival_Wake_Shape, index: int) -> (corners: [3][3]f32, coordinates: [3][2]f32) {
	drop := -f32(ARRIVAL_WAKE_SHIELD_DROP_CELLS)
	corners = {
		{0, drop, 0},
		arrival_wake_point(arrival_wake_azimuth(index), shape.shield_radius, drop),
		arrival_wake_point(arrival_wake_azimuth(index + 1), shape.shield_radius, drop),
	}
	coordinates = {{(f32(index) + 0.5) / ARRIVAL_WAKE_SIDES, 0}, {f32(index) / ARRIVAL_WAKE_SIDES, 1}, {f32(index + 1) / ARRIVAL_WAKE_SIDES, 1}}
	return
}

// The cells along the flow over which the light halves: a quarter
// diameter at the peak, half that at heat 0, so the wake is short and
// dim at the onset.
arrival_wake_half_light_cells :: proc(shape: Arrival_Wake_Shape, heat: f32) -> f32 {
	return ARRIVAL_WAKE_HALF_LIGHT_DIAMETERS * 2 * shape.shield_radius * (0.5 + 0.5 * heat)
}

// Whether an eye in cells of the model's frame lies inside the tube:
// inside its flats and between the rim and the end. Never without a
// wake.
arrival_eye_inside_wake :: proc(shape: Arrival_Wake_Shape, eye_cells: [3]f32) -> bool {
	if shape.radius <= 0 {
		return false
	}
	flats := shape.radius * math.cos(f32(math.PI) / ARRIVAL_WAKE_SIDES)
	return linalg.length(eye_cells.xz) < flats && eye_cells.y >= 0 && eye_cells.y <= shape.length
}

// The tube's quads in drawing order from an eye in cells of the model's
// frame: those facing away from it first, in index order, then those
// facing it, and how many face away. Exact for the planar quads of a
// convex tube, so the far walls composite under the near ones.
arrival_wake_quad_order :: proc(shape: Arrival_Wake_Shape, eye_cells: [3]f32) -> (order: [ARRIVAL_WAKE_SIDES]int, far_count: int) {
	facing: [ARRIVAL_WAKE_SIDES]bool
	for index in 0 ..< ARRIVAL_WAKE_SIDES {
		corners, _ := arrival_wake_quad(shape, index)
		facing[index] = linalg.dot(arrival_wake_quad_normal(index), eye_cells - corners[0]) > 0
		if !facing[index] {
			order[far_count] = index
			far_count += 1
		}
	}
	count := far_count
	for index in 0 ..< ARRIVAL_WAKE_SIDES {
		if facing[index] {
			order[count] = index
			count += 1
		}
	}
	return
}

// The wake's one flicker at seconds (0286's fire_flicker), the mean
// under reduced motion.
arrival_wake_flicker :: proc(seconds: f32, salt: u64, reduced_motion: bool) -> f32 {
	return fire_flicker(f64(seconds), salt + 60, reduced_motion)
}

// The wake's colours from the data (0305): the haze, the ablator, the
// hot gold (the ablator ARRIVAL_WAKE_HOT_SHARE of the way to the core
// colour) and the core, each 0 to 1. The single source of what the
// shader mixes.
arrival_wake_ramp_stops :: proc(plasma: Arrival_Plasma_Config) -> [ARRIVAL_WAKE_RAMP_STOPS][3]f32 {
	ablator, core := arrival_plasma_color(plasma.ablator_color), arrival_plasma_color(plasma.core_color)
	return {arrival_plasma_color(plasma.haze_color), ablator, ablator + (core - ablator) * ARRIVAL_WAKE_HOT_SHARE, core}
}

// The shell's opacity scale for wake_opacity_percent: that opacity at
// ARRIVAL_WAKE_REFERENCE_INTENSITY (2.01 at 80).
arrival_wake_opacity_scale :: proc(percent: int) -> f32 {
	return -math.ln(1 - f32(percent) / 100) / ARRIVAL_WAKE_REFERENCE_INTENSITY
}

// The eye, the wake's origin (the base centre) and its axis (the model's
// +y, unit) in the moved space, from the eye in the frame's unmoved
// space, the pod's body and the pod's transform. rlgl 6.0 moves each
// immediate mode vertex by the pushed matrix on the CPU (rlVertex3f,
// transformRequired), so vertexPosition reaches the shader moved and mvp
// holds only the camera: the shader's uniforms are therefore in the
// moved space.
arrival_wake_frame :: proc(body, transform: matrix[4, 4]f32, eye: [3]f32) -> (eye_position, origin, axis: [3]f32) {
	eye_position = transform_point(transform, eye)
	origin = transform_point(transform, transform_point(body, {}))
	axis = linalg.normalize(cast(matrix[3, 3]f32)(transform * body) * [3]f32{0, 1, 0})
	return
}

// The quads of indices in one batch, each corner's texture coordinates
// then its point under body, flushed at the end so the uniforms set
// before it hold for it.
draw_arrival_wake_quads :: proc(shape: Arrival_Wake_Shape, indices: []int, body: matrix[4, 4]f32, texture: u32) {
	rlgl.SetTexture(texture)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(255, 255, 255, 255)
	for index in indices {
		corners, coordinates := arrival_wake_quad(shape, index)
		for corner, corner_index in corners {
			point := transform_point(body, corner)
			rlgl.TexCoord2f(coordinates[corner_index].x, coordinates[corner_index].y)
			rlgl.Vertex3f(point.x, point.y, point.z)
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rlgl.DrawRenderBatchActive()
}

// The disc's triangles in one batch, as draw_arrival_wake_quads.
draw_arrival_wake_shield :: proc(shape: Arrival_Wake_Shape, body: matrix[4, 4]f32, texture: u32) {
	rlgl.SetTexture(texture)
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(255, 255, 255, 255)
	for index in 0 ..< ARRIVAL_WAKE_SIDES {
		corners, coordinates := arrival_wake_shield_triangle(shape, index)
		for corner, corner_index in corners {
			point := transform_point(body, corner)
			rlgl.TexCoord2f(coordinates[corner_index].x, coordinates[corner_index].y)
			rlgl.Vertex3f(point.x, point.y, point.z)
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rlgl.DrawRenderBatchActive()
}

// Inside BeginMode3D under the pod's transform, after the scene
// (draw_arrival_entry): the tube's far walls, the shield's disc, then
// the near walls, premultiplied, depth tested against the hull without
// writing depth, both sides drawn. A uniform applies at the flush, so
// each layer change follows one. The shader has no discard, so early
// depth rejects the walls behind the cabin from the chair. eye_cells is
// the eye in cells of the model's frame, eye in the frame's unmoved
// space. Nothing outside the descent, at heat 0, without the shader or
// without a wake.
draw_arrival_wake :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, body, transform: matrix[4, 4]f32, shape: Arrival_Wake_Shape, eye_cells: [3]f32, eye: [3]f32, plasma: Arrival_Plasma_Config, flicker: f32, salt: u64, reduced_motion: bool) {
	if view.phase != .Descent || view.heat <= 0 || !presentation.wake_ready || shape.radius <= 0 {
		return
	}
	shader := presentation.wake_shader
	texture := rlgl.GetTextureIdDefault()
	eye_position, origin, axis := arrival_wake_frame(body, transform, eye)
	order, far_count := arrival_wake_quad_order(shape, eye_cells)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rl.BeginShaderMode(shader)
	set_shader_float(shader, "heat", view.heat)
	set_shader_float(shader, "seconds", view.seconds)
	set_shader_float(shader, "flicker", flicker)
	set_shader_float(shader, "calm", reduced_motion ? 1 : 0)
	set_shader_float(shader, "flame_seed", f32(salt % 1000) / 1000)
	set_shader_float(shader, "opacity_scale", arrival_wake_opacity_scale(plasma.wake_opacity_percent))
	set_shader_float(shader, "circumference_cells", math.TAU * shape.radius)
	set_shader_float(shader, "half_light_cells", arrival_wake_half_light_cells(shape, view.heat))
	set_shader_float(shader, "length_cells", shape.length)
	set_shader_vector3(shader, "eye_position", eye_position)
	set_shader_vector3(shader, "wake_origin", origin)
	set_shader_vector3(shader, "wake_axis", axis)
	stops := arrival_wake_ramp_stops(plasma)
	set_shader_vector3(shader, "haze_color", stops[0])
	set_shader_vector3(shader, "ablator_color", stops[1])
	set_shader_vector3(shader, "hot_color", stops[2])
	set_shader_vector3(shader, "core_color", stops[3])
	set_shader_float(shader, "layer", 0)
	draw_arrival_wake_quads(shape, order[:far_count], body, texture)
	set_shader_float(shader, "layer", 1)
	draw_arrival_wake_shield(shape, body, texture)
	set_shader_float(shader, "layer", 0)
	draw_arrival_wake_quads(shape, order[far_count:], body, texture)
	rl.EndShaderMode()
	rl.EndBlendMode()
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthMask()
}
