package game

// Point lights of working parts (work item 0175, DESIGN.md: point lights
// come on top for working parts and never replace the field's light).
// Each frame the renderer gathers the lights of the parts that work, keeps
// the MAXIMUM_POINT_LIGHTS nearest the camera and hands them to the field
// shader (set_field_point_lights), which adds a soft term falling off to
// zero at each light's radius. Positions and radii are in the world's
// metres. Pure; the shader upload is in render_field.odin.

// Matches the array size in data/shaders/field.fs.
MAXIMUM_POINT_LIGHTS :: 8
// The arm's work lamp: a warm light that reaches a few cells round the
// gripper.
ARM_LIGHT_COLOR :: [3]f32{1.0, 0.72, 0.38}
ARM_LIGHT_RADIUS_METRES :: 3.0

Point_Light :: struct {
	position: [3]f32,
	color:    [3]f32,
	radius:   f32,
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
