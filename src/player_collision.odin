package game

import "core:math"

// Axis separated swept collision of an axis aligned box against the
// collision boxes of blocks (block_shape.odin: a cube's cell, a slab's
// half, the two boxes of stairs) and entities. A move along one axis
// visits every block layer the leading face crosses, nearest first, and
// stops flush at the nearest box, so no speed can tunnel through a block.

// Slack for comparing box faces with block borders. Clamped positions
// like 4.7 + 0.3 do not land exactly on the integer in f32, and a box
// resting flush against a block must not count as overlapping it.
COLLISION_EPSILON :: 1e-3

Box :: struct {
	minimum: [3]f32,
	maximum: [3]f32,
}

// The position is the centre of the bottom face (the feet).
player_box :: proc(position: [3]f32) -> Box {
	half_width := f32(PLAYER_WIDTH / 2)
	return Box {
		minimum = position - {half_width, 0, half_width},
		maximum = position + {half_width, PLAYER_HEIGHT, half_width},
	}
}

block_box :: proc(position: World_Coordinate) -> Box {
	minimum := [3]f32{f32(position.x), f32(position.y), f32(position.z)}
	return Box{minimum = minimum, maximum = minimum + 1}
}

boxes_overlap :: proc(first, second: Box) -> bool {
	for axis in 0 ..< 3 {
		if first.minimum[axis] >= second.maximum[axis] - COLLISION_EPSILON || second.minimum[axis] >= first.maximum[axis] - COLLISION_EPSILON {
			return false
		}
	}
	return true
}

// Block cells the box overlaps on one axis, ignoring flush contact.
overlapped_cells :: proc(box: Box, axis: int) -> (first, last: i32) {
	first = i32(math.floor(box.minimum[axis] + COLLISION_EPSILON))
	last = i32(math.ceil(box.maximum[axis] - COLLISION_EPSILON)) - 1
	return
}

// Whether the boxes overlap on the two axes other than `axis`.
boxes_overlap_across :: proc(first, second: Box, axis: int) -> bool {
	for other in ([2]int{(axis + 1) % 3, (axis + 2) % 3}) {
		if first.minimum[other] >= second.maximum[other] - COLLISION_EPSILON || second.minimum[other] >= first.maximum[other] - COLLISION_EPSILON {
			return false
		}
	}
	return true
}

// The world space boxes the player collides with in a cell: the block's
// shape boxes (a slab's half, block_shape.odin), or the whole cell for an
// entity in the way (cell_blocks_movement: belts and splitters are walked
// over).
cell_collision_boxes :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> Shape_Boxes {
	result: Shape_Boxes
	origin := [3]f32{f32(cell.x), f32(cell.y), f32(cell.z)}
	for box in block_collision_boxes(registry, world_get_block(world, cell)) {
		result.boxes[result.count] = Box{minimum = origin + box.minimum, maximum = origin + box.maximum}
		result.count += 1
	}
	if result.count == 0 && cell_blocks_movement(world, registry, cell) {
		result.boxes[0] = block_box(cell)
		result.count = 1
	}
	return result
}

layer_cell :: proc(axis: int, layer, first_cell, second_cell: i32) -> World_Coordinate {
	cell: World_Coordinate
	cell[axis] = layer
	cell[(axis + 1) % 3] = first_cell
	cell[(axis + 2) % 3] = second_cell
	return cell
}

// Whether a collision box in the cell layer `layer` of `axis`, within the
// cells the box overlaps on the other two axes, overlaps the box.
layer_has_solid :: proc(world: ^World, registry: Block_Registry, box: Box, axis: int, layer: i32) -> bool {
	first_start, first_end := overlapped_cells(box, (axis + 1) % 3)
	second_start, second_end := overlapped_cells(box, (axis + 2) % 3)
	for first_cell in first_start ..= first_end {
		for second_cell in second_start ..= second_end {
			boxes := cell_collision_boxes(world, registry, layer_cell(axis, layer, first_cell, second_cell))
			for obstacle in boxes.boxes[:boxes.count] {
				if boxes_overlap(box, obstacle) {
					return true
				}
			}
		}
	}
	return false
}

// How far the box moves along axis before it touches the obstacle, when
// the obstacle lies ahead within delta: 0 for one already flush.
obstacle_gap :: proc(box, obstacle: Box, axis: int, delta: f32) -> (gap: f32, ahead: bool) {
	if delta > 0 {
		gap = obstacle.minimum[axis] - box.maximum[axis]
		return max(gap, 0), gap >= -COLLISION_EPSILON && gap < delta
	}
	gap = obstacle.maximum[axis] - box.minimum[axis]
	return min(gap, 0), gap <= COLLISION_EPSILON && gap > delta
}

// The nearest stop among the collision boxes of one cell layer.
layer_stop :: proc(world: ^World, registry: Block_Registry, box: Box, axis: int, layer: i32, delta: f32) -> (moved: f32, blocked: bool) {
	moved = delta
	first_start, first_end := overlapped_cells(box, (axis + 1) % 3)
	second_start, second_end := overlapped_cells(box, (axis + 2) % 3)
	for first_cell in first_start ..= first_end {
		for second_cell in second_start ..= second_end {
			boxes := cell_collision_boxes(world, registry, layer_cell(axis, layer, first_cell, second_cell))
			for obstacle in boxes.boxes[:boxes.count] {
				if !boxes_overlap_across(box, obstacle, axis) {
					continue
				}
				if gap, ahead := obstacle_gap(box, obstacle, axis, delta); ahead && abs(gap) <= abs(moved) {
					moved, blocked = gap, true
				}
			}
		}
	}
	return
}

// How far the box can move along one axis, at most `delta`, and whether a
// collision box stopped it. The layers are visited nearest first from the
// one holding the leading face, since a slab's top or an upper slab's
// underside lies inside a cell.
sweep_box_axis :: proc(world: ^World, registry: Block_Registry, box: Box, axis: int, delta: f32) -> (moved: f32, blocked: bool) {
	if delta > 0 {
		face := box.maximum[axis]
		last := i32(math.ceil(face + delta)) - 1
		for layer in i32(math.floor(face - COLLISION_EPSILON)) ..= last {
			if moved, blocked = layer_stop(world, registry, box, axis, layer, delta); blocked {
				return
			}
		}
	} else if delta < 0 {
		face := box.minimum[axis]
		last := i32(math.floor(face + delta))
		for layer := i32(math.ceil(face + COLLISION_EPSILON)) - 1; layer >= last; layer -= 1 {
			if moved, blocked = layer_stop(world, registry, box, axis, layer, delta); blocked {
				return
			}
		}
	}
	return delta, false
}

box_intersects_solid :: proc(world: ^World, registry: Block_Registry, box: Box) -> bool {
	start, end := overlapped_cells(box, 1)
	for layer in start ..= end {
		if layer_has_solid(world, registry, box, 1, layer) {
			return true
		}
	}
	return false
}

// Water counts in whole cells, whatever its level.
box_touches_water :: proc(world: ^World, registry: Block_Registry, box: Box) -> bool {
	first, last: [3]i32
	for axis in 0 ..< 3 {
		first[axis], last[axis] = overlapped_cells(box, axis)
	}
	for y in first.y ..= last.y {
		for z in first.z ..= last.z {
			for x in first.x ..= last.x {
				if block_water_level(registry, world_get_block(world, {x, y, z})) > 0 {
					return true
				}
			}
		}
	}
	return false
}

// How far below the feet box_has_ground looks for a collision box.
GROUND_PROBE_DISTANCE :: 0.01

// A collision box right under any part of the box footprint: a block, or
// a slab's top half way up its cell.
box_has_ground :: proc(world: ^World, registry: Block_Registry, box: Box) -> bool {
	_, blocked := sweep_box_axis(world, registry, box, 1, -GROUND_PROBE_DISTANCE)
	return blocked
}
