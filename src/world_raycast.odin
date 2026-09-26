package game

import "core:math"

// Voxel raycast after Amanatides and Woo, "A Fast Voxel Traversal
// Algorithm for Ray Tracing" (1987): step from cell to cell across the
// nearest cell boundary, so no solid block along the ray is skipped.

Raycast_Hit :: struct {
	hit:      bool,
	block:    World_Coordinate,
	// The face of the hit block the ray entered through.
	face:     Direction,
	// The cell in front of that face, where a placed block goes.
	adjacent: World_Coordinate,
	distance: f32,
}

Raycast_Axis :: struct {
	step:               i32,
	// Ray distance to the next cell boundary on this axis, and between two.
	distance_to_border: f32,
	distance_per_cell:  f32,
}

raycast_axis :: proc(origin, direction: f32, cell: i32) -> Raycast_Axis {
	switch {
	case direction > 0:
		return {step = 1, distance_to_border = (f32(cell + 1) - origin) / direction, distance_per_cell = 1 / direction}
	case direction < 0:
		return {step = -1, distance_to_border = (origin - f32(cell)) / -direction, distance_per_cell = 1 / -direction}
	}
	return {step = 0, distance_to_border = math.INF_F32, distance_per_cell = math.INF_F32}
}

nearest_border_axis :: proc(axes: [3]Raycast_Axis) -> int {
	axis := 0
	for candidate in 1 ..< 3 {
		if axes[candidate].distance_to_border < axes[axis].distance_to_border {
			axis = candidate
		}
	}
	return axis
}

// Stepping +x enters the next block through its -x face.
entered_face :: proc(axis: int, step: i32) -> Direction {
	faces := [3][2]Direction{{.Positive_X, .Negative_X}, {.Positive_Y, .Negative_Y}, {.Positive_Z, .Negative_Z}}
	return faces[axis][step > 0 ? 1 : 0]
}

// Finds the first targetable block (solid or minable) along a normalised
// direction within reach.
// The cell holding the origin is never reported. Missing chunks read as
// air, so rays pass through unloaded space.
raycast_blocks :: proc(world: ^World, registry: Block_Registry, origin, direction: [3]f32, reach: f32) -> Raycast_Hit {
	cell := camera_world_coordinate(origin)
	axes: [3]Raycast_Axis
	for axis in 0 ..< 3 {
		axes[axis] = raycast_axis(origin[axis], direction[axis], cell[axis])
	}
	for {
		axis := nearest_border_axis(axes)
		distance := axes[axis].distance_to_border
		if distance > reach {
			return {}
		}
		previous := cell
		cell[axis] += axes[axis].step
		axes[axis].distance_to_border += axes[axis].distance_per_cell
		if block_is_targetable(registry, world_get_block(world, cell)) {
			return Raycast_Hit{hit = true, block = cell, face = entered_face(axis, axes[axis].step), adjacent = previous, distance = distance}
		}
	}
}
