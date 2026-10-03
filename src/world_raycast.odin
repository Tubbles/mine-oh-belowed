package game

import "core:math"

// Voxel raycast after Amanatides and Woo, "A Fast Voxel Traversal
// Algorithm for Ray Tracing" (1987): step from cell to cell across the
// nearest cell boundary, so no solid block along the ray is skipped.

// The simulation's Raycast_Hit (player_interaction.odin) is this with the
// occupant unpacked into an entity handle.
Cell_Raycast_Hit :: struct {
	hit:      bool,
	block:    World_Coordinate,
	// The face of the hit block the ray entered through.
	face:     Direction,
	// The cell in front of that face, where a placed block goes.
	adjacent: World_Coordinate,
	distance: f32,
	// What occupies the hit cell in the occupant index of the block
	// frame, or NO_OCCUPANT for a block.
	occupant: Occupant_Handle,
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

// Finds the first targetable block (solid or minable) or entity cell along
// a normalised direction within reach. A block that is not a cube is hit
// only where the ray meets its shape, else the ray goes on through it.
// The cell holding the origin is never reported. Missing chunks read as
// air, so rays pass through unloaded space.
raycast_cells :: proc(world: ^World, registry: Block_Registry, origin, direction: [3]f32, reach: f32) -> Cell_Raycast_Hit {
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
		occupant, occupied := frame_occupant(&world.entities.frames, BLOCK_FRAME, cell)
		block := world_get_block(world, cell)
		if occupied || (block_is_targetable(registry, block) && block_shape(registry, block) == .Cube) {
			return Cell_Raycast_Hit{hit = true, block = cell, face = entered_face(axis, axes[axis].step), adjacent = previous, distance = distance, occupant = occupant.handle}
		}
		if block_is_targetable(registry, block) {
			if hit := shaped_block_hit(registry, block, cell, origin, direction); hit.hit && hit.distance <= reach {
				return hit
			}
		}
	}
}

// Where the ray enters the box and through which face, after Kay and
// Kajiya's slab test: the latest entry over the three axes, if it comes
// before the earliest exit. A ray starting inside enters at distance 0.
ray_box_entry :: proc(origin, direction: [3]f32, box: Box) -> (distance: f32, face: Direction, hit: bool) {
	near, far := -math.INF_F32, math.INF_F32
	near_axis := 0
	for axis in 0 ..< 3 {
		if direction[axis] == 0 {
			if origin[axis] < box.minimum[axis] || origin[axis] > box.maximum[axis] {
				return 0, {}, false
			}
			continue
		}
		first := (box.minimum[axis] - origin[axis]) / direction[axis]
		second := (box.maximum[axis] - origin[axis]) / direction[axis]
		if min(first, second) > near {
			near, near_axis = min(first, second), axis
		}
		far = min(far, max(first, second))
	}
	if near > far || far < 0 {
		return 0, {}, false
	}
	return max(near, 0), entered_face(near_axis, direction[near_axis] > 0 ? 1 : -1), true
}

// A slab, stairs, a torch: the ray hits the block only where it meets one
// of its target boxes (block_target_boxes), the nearest, and a block
// placed against the hit face goes into the cell in front of it.
shaped_block_hit :: proc(registry: Block_Registry, block: Block_Id, cell: World_Coordinate, origin, direction: [3]f32) -> Cell_Raycast_Hit {
	cell_origin := [3]f32{f32(cell.x), f32(cell.y), f32(cell.z)}
	targets := block_target_boxes(registry, block)
	nearest := Cell_Raycast_Hit{distance = math.INF_F32}
	for box in targets.boxes[:targets.count] {
		distance, face, hit := ray_box_entry(origin, direction, Box{minimum = cell_origin + box.minimum, maximum = cell_origin + box.maximum})
		if hit && distance < nearest.distance {
			nearest = Cell_Raycast_Hit{hit = true, block = cell, face = face, adjacent = cell + World_Coordinate(direction_offsets[face]), distance = distance}
		}
	}
	return nearest
}
