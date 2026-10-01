package game

import "core:math/linalg"

// Block shapes (work item 0061): the collision boxes, the bounds the
// target outline and the raycast use, and the quads the mesher draws for
// every shape but the cube, which the greedy pass meshes. Pure, no
// raylib. Coordinates are local to the cell, 0 to 1 on every axis.

MAXIMUM_SHAPE_QUADS :: 10
MAXIMUM_SHAPE_BOXES :: 2
// A post (a torch) is a column 2 by 2 texels wide from the floor to 10
// texels up, a texel being a sixteenth of a block.
POST_HALF_WIDTH :: 1.0 / 16
POST_HEIGHT :: 10.0 / 16
// The ray targets a post through a box 8 texels wide around it, the drawn
// height, so a torch can be aimed at with a gamepad.
POST_TARGET_HALF_WIDTH :: 4.0 / 16

Box :: struct {
	minimum: [3]f32,
	maximum: [3]f32,
}

@(rodata)
full_cell_boxes := [1]Box{{minimum = {0, 0, 0}, maximum = {1, 1, 1}}}
@(rodata)
bottom_slab_boxes := [1]Box{{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}}}
@(rodata)
upper_slab_boxes := [1]Box{{minimum = {0, 0.5, 0}, maximum = {1, 1, 1}}}

// A bottom slab and a quarter box at the back, the side the stairs rise
// towards: +x, +z, -x, -z for rotations 0 to 3.
@(rodata)
stairs_boxes := [4][2]Box {
	{{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}}, {minimum = {0.5, 0.5, 0}, maximum = {1, 1, 1}}},
	{{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}}, {minimum = {0, 0.5, 0.5}, maximum = {1, 1, 1}}},
	{{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}}, {minimum = {0, 0.5, 0}, maximum = {0.5, 1, 1}}},
	{{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}}, {minimum = {0, 0.5, 0}, maximum = {1, 1, 0.5}}},
}

// A column of the post's height, centred in the cell.
centred_column_box :: proc(half_width: f32) -> Box {
	return Box{minimum = {0.5 - half_width, 0, 0.5 - half_width}, maximum = {0.5 + half_width, POST_HEIGHT, 0.5 + half_width}}
}

// What a post draws.
post_box :: proc() -> Box {
	return centred_column_box(POST_HALF_WIDTH)
}

// The boxes a shape stops movement and the raycast with; posts and
// crosses have none.
shape_collision_boxes :: proc(shape: Block_Shape, orientation: Block_Orientation) -> []Box {
	switch shape {
	case .Cube:
		return full_cell_boxes[:]
	case .Slab:
		return orientation.upper ? upper_slab_boxes[:] : bottom_slab_boxes[:]
	case .Stairs:
		return stairs_boxes[orientation.rotation % 4][:]
	case .Post, .Cross:
	}
	return nil
}

// Local boxes of a block that is solid, none for every other block
// (air, water, torches).
block_collision_boxes :: proc(registry: Block_Registry, block: Block_Id) -> []Box {
	if !block_is_solid(registry, block) {
		return nil
	}
	return shape_collision_boxes(block_shape(registry, block), block_orientation(registry, block))
}

box_union :: proc(first, second: Box) -> Box {
	return Box{minimum = linalg.min(first.minimum, second.minimum), maximum = linalg.max(first.maximum, second.maximum)}
}

// The local box around the whole shape: what the target outline draws
// and what a ray must meet to target a post or a cross. A post's is wider
// than the post drawn (POST_TARGET_HALF_WIDTH).
shape_bounds :: proc(shape: Block_Shape, orientation: Block_Orientation) -> Box {
	switch shape {
	case .Post:
		return centred_column_box(POST_TARGET_HALF_WIDTH)
	case .Cube, .Cross:
		return full_cell_boxes[0]
	case .Slab, .Stairs:
	}
	boxes := shape_collision_boxes(shape, orientation)
	bounds := boxes[0]
	for box in boxes[1:] {
		bounds = box_union(bounds, box)
	}
	return bounds
}

block_bounds :: proc(registry: Block_Registry, block: Block_Id) -> Box {
	return shape_bounds(block_shape(registry, block), block_orientation(registry, block))
}

// The boxes a ray targets the block by: the collision boxes of a solid
// shape, the bounds of any other.
block_target_boxes :: proc(registry: Block_Registry, block: Block_Id) -> Shape_Boxes {
	targets: Shape_Boxes
	boxes := block_collision_boxes(registry, block)
	if len(boxes) == 0 {
		targets.boxes[0] = block_bounds(registry, block)
		targets.count = 1
		return targets
	}
	for box, index in boxes {
		targets.boxes[index] = box
	}
	targets.count = len(boxes)
	return targets
}

Shape_Boxes :: struct {
	boxes: [MAXIMUM_SHAPE_BOXES]Box,
	count: int,
}

// One quad of a shape. corners run counter clockwise seen from the side
// the quad faces. border is the cell face the quad lies on, where an
// opaque neighbour hides it; nil for a quad inside the cell.
Shape_Quad :: struct {
	corners: [4][3]f32,
	group:   Face_Group,
	border:  Maybe(Direction),
}

Shape_Quads :: struct {
	quads: [MAXIMUM_SHAPE_QUADS]Shape_Quad,
	count: int,
}

append_shape_quad :: proc(quads: ^Shape_Quads, quad: Shape_Quad) {
	quads.quads[quads.count] = quad
	quads.count += 1
}

// The face of a box towards direction, wound like quad_corners (u, v and
// the face axis right handed) and reversed on the negative side, so it is
// counter clockwise seen from outside.
box_face_corners :: proc(box: Box, direction: Direction) -> [4][3]f32 {
	axis := direction_axis(direction)
	u_axis := (axis + 1) % 3
	v_axis := (axis + 2) % 3
	corner := box.minimum
	if direction_is_positive(direction) {
		corner[axis] = box.maximum[axis]
	}
	u_step, v_step: [3]f32
	u_step[u_axis] = box.maximum[u_axis] - box.minimum[u_axis]
	v_step[v_axis] = box.maximum[v_axis] - box.minimum[v_axis]
	if direction_is_positive(direction) {
		return {corner, corner + u_step, corner + u_step + v_step, corner + v_step}
	}
	return {corner, corner + v_step, corner + u_step + v_step, corner + u_step}
}

// A face on the cell's own face is a border face.
box_face_border :: proc(box: Box, direction: Direction) -> Maybe(Direction) {
	axis := direction_axis(direction)
	if direction_is_positive(direction) ? box.maximum[axis] == 1 : box.minimum[axis] == 0 {
		return direction
	}
	return nil
}

box_face_quad :: proc(box: Box, direction: Direction) -> Shape_Quad {
	return Shape_Quad{corners = box_face_corners(box, direction), group = direction_face_group(direction), border = box_face_border(box, direction)}
}

append_box_faces :: proc(quads: ^Shape_Quads, box: Box) {
	for direction in Direction {
		append_shape_quad(quads, box_face_quad(box, direction))
	}
}

// Stairs rising towards +x, the faces of the union of the bottom slab and
// the back quarter: the step's tread and riser inside the cell, the sides
// as two quads each.
stairs_quads_rotation_0 :: proc() -> Shape_Quads {
	quads: Shape_Quads
	lower := Box{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}}
	upper := Box{minimum = {0.5, 0.5, 0}, maximum = {1, 1, 1}}
	append_shape_quad(&quads, box_face_quad(lower, .Negative_Y))
	append_shape_quad(&quads, box_face_quad(Box{minimum = {0, 0, 0}, maximum = {0.5, 0.5, 1}}, .Positive_Y))
	append_shape_quad(&quads, box_face_quad(upper, .Positive_Y))
	append_shape_quad(&quads, box_face_quad(upper, .Negative_X))
	append_shape_quad(&quads, box_face_quad(lower, .Negative_X))
	append_shape_quad(&quads, box_face_quad(Box{minimum = {0.5, 0, 0}, maximum = {1, 1, 1}}, .Positive_X))
	for direction in ([2]Direction{.Negative_Z, .Positive_Z}) {
		append_shape_quad(&quads, box_face_quad(lower, direction))
		append_shape_quad(&quads, box_face_quad(upper, direction))
	}
	return quads
}

// A quarter turn about the vertical axis through the cell centre takes
// +x to +z, like belt_direction_offset.
rotate_local_point :: proc(point: [3]f32, rotation: u8) -> [3]f32 {
	result := point
	for _ in 0 ..< rotation % 4 {
		result = {1 - result.z, result.y, result.x}
	}
	return result
}

rotate_shape_quad :: proc(quad: Shape_Quad, rotation: u8) -> Shape_Quad {
	rotated := quad
	for &corner in rotated.corners {
		corner = rotate_local_point(corner, rotation)
	}
	if border, found := quad.border.?; found {
		rotated.border = rotate_direction(border, rotation)
	}
	return rotated
}

// Two diagonal quads through the cell, each drawn from both sides.
cross_quads :: proc() -> Shape_Quads {
	quads: Shape_Quads
	diagonals := [2][2][3]f32{{{0, 0, 0}, {1, 0, 1}}, {{1, 0, 0}, {0, 0, 1}}}
	for diagonal in diagonals {
		start, end := diagonal[0], diagonal[1]
		front := [4][3]f32{start, end, end + {0, 1, 0}, start + {0, 1, 0}}
		append_shape_quad(&quads, Shape_Quad{corners = front, group = .Side})
		append_shape_quad(&quads, Shape_Quad{corners = {front[1], front[0], front[3], front[2]}, group = .Side})
	}
	return quads
}

// The quads of every shape but the cube, which has none here.
shape_quads :: proc(shape: Block_Shape, orientation: Block_Orientation) -> Shape_Quads {
	quads: Shape_Quads
	switch shape {
	case .Cube:
	case .Slab:
		append_box_faces(&quads, shape_collision_boxes(shape, orientation)[0])
	case .Stairs:
		unrotated := stairs_quads_rotation_0()
		quads.count = unrotated.count
		for index in 0 ..< unrotated.count {
			quads.quads[index] = rotate_shape_quad(unrotated.quads[index], orientation.rotation)
		}
	case .Post:
		append_box_faces(&quads, post_box())
	case .Cross:
		quads = cross_quads()
	}
	return quads
}
