package game

import "core:math"

// Axis separated swept collision of an axis aligned box against solid
// blocks. A move along one axis visits every block layer the leading face
// crosses, nearest first, and stops flush at the first solid one, so no
// speed can tunnel through a block.

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

// Whether any solid block lies in the cell layer `layer` of `axis`,
// within the cells the box overlaps on the other two axes.
layer_has_solid :: proc(world: ^World, registry: Block_Registry, box: Box, axis: int, layer: i32) -> bool {
	first_axis, second_axis := (axis + 1) % 3, (axis + 2) % 3
	first_start, first_end := overlapped_cells(box, first_axis)
	second_start, second_end := overlapped_cells(box, second_axis)
	for first_cell in first_start ..= first_end {
		for second_cell in second_start ..= second_end {
			cell: World_Coordinate
			cell[axis] = layer
			cell[first_axis] = first_cell
			cell[second_axis] = second_cell
			if block_is_solid(registry, world_get_block(world, cell)) {
				return true
			}
		}
	}
	return false
}

// How far the box can move along one axis, at most `delta`, and whether a
// solid block stopped it.
sweep_box_axis :: proc(world: ^World, registry: Block_Registry, box: Box, axis: int, delta: f32) -> (moved: f32, blocked: bool) {
	if delta > 0 {
		face := box.maximum[axis]
		first := i32(math.ceil(face - COLLISION_EPSILON))
		last := i32(math.ceil(face + delta)) - 1
		for layer in first ..= last {
			if layer_has_solid(world, registry, box, axis, layer) {
				return max(f32(layer) - face, 0), true
			}
		}
	} else if delta < 0 {
		face := box.minimum[axis]
		first := i32(math.floor(face + COLLISION_EPSILON)) - 1
		last := i32(math.floor(face + delta))
		for layer := first; layer >= last; layer -= 1 {
			if layer_has_solid(world, registry, box, axis, layer) {
				return min(f32(layer + 1) - face, 0), true
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

// Solid ground directly under any part of the box footprint. A 0.6 wide
// box overlaps at most the four cells under its corners, so this is the
// "a solid block under any corner" test.
box_has_ground :: proc(world: ^World, registry: Block_Registry, box: Box) -> bool {
	return layer_has_solid(world, registry, box, 1, i32(math.floor(box.minimum.y + COLLISION_EPSILON)) - 1)
}
