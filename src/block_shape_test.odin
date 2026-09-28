package game

import "core:math/linalg"
import "core:testing"

// air 0, stone 1, slab 2 and slab_upper 3, stairs 4 and stairs_r1 to r3 5
// to 7, torch 8, tuft 9 (a cross, which no shipped block has yet).
SHAPE_TEST_BLOCKS :: `blocks = [
	{id = "air", solid = false}
	{id = "stone", name_key = "block_stone", solid = true, hardness_seconds = 1}
	{id = "slab", name_key = "block_stone", solid = true, hardness_seconds = 1, shape = "slab"}
	{id = "stairs", name_key = "block_stone", solid = true, hardness_seconds = 1, shape = "stairs"}
	{id = "torch", name_key = "block_torch", solid = false, hardness_seconds = 0.1, light_level = 14, shape = "post"}
	{id = "tuft", name_key = "block_torch", solid = false, hardness_seconds = 0.1, shape = "cross"}
]`

SHAPE_TEST_STONE :: Block_Id(1)
SHAPE_TEST_SLAB :: Block_Id(2)
SHAPE_TEST_UPPER_SLAB :: Block_Id(3)
SHAPE_TEST_STAIRS :: Block_Id(4)
SHAPE_TEST_TORCH :: Block_Id(8)
SHAPE_TEST_TUFT :: Block_Id(9)

make_shape_test_registry :: proc() -> Block_Registry {
	file, error := parse_blocks_file(transmute([]byte)string(SHAPE_TEST_BLOCKS), context.temp_allocator)
	assert(error == nil)
	assert(validate_block_definitions(file.blocks) == "")
	return Block_Registry{definitions = file.blocks}
}

rotate_local_box :: proc(box: Box, rotation: u8) -> Box {
	first := rotate_local_point(box.minimum, rotation)
	second := rotate_local_point(box.maximum, rotation)
	return Box{minimum = linalg.min(first, second), maximum = linalg.max(first, second)}
}

// Borders count as inside: a point on the seam of two boxes of a shape
// lies in the solid.
point_in_box :: proc(point: [3]f32, box: Box) -> bool {
	for axis in 0 ..< 3 {
		if point[axis] < box.minimum[axis] || point[axis] > box.maximum[axis] {
			return false
		}
	}
	return true
}

point_in_boxes :: proc(point: [3]f32, boxes: []Box) -> bool {
	for box in boxes {
		if point_in_box(point, box) {
			return true
		}
	}
	return false
}

quad_normal :: proc(quad: Shape_Quad) -> [3]f32 {
	return linalg.normalize(linalg.cross(quad.corners[1] - quad.corners[0], quad.corners[3] - quad.corners[0]))
}

quad_centre :: proc(quad: Shape_Quad) -> [3]f32 {
	return (quad.corners[0] + quad.corners[1] + quad.corners[2] + quad.corners[3]) / 4
}

quad_area :: proc(quad: Shape_Quad) -> f32 {
	return linalg.length(linalg.cross(quad.corners[1] - quad.corners[0], quad.corners[3] - quad.corners[0]))
}

expected_face_group :: proc(normal: [3]f32) -> Face_Group {
	switch {
	case normal.y > 0.5:
		return .Top
	case normal.y < -0.5:
		return .Bottom
	}
	return .Side
}

// Every quad of a solid shape faces out of the solid, with the tile group
// of its direction, and a border quad lies on its cell face.
expect_quads_face_outward :: proc(t: ^testing.T, quads: Shape_Quads, solid: []Box) {
	quads := quads
	for quad in quads.quads[:quads.count] {
		normal := quad_normal(quad)
		centre := quad_centre(quad)
		testing.expectf(t, !point_in_boxes(centre + normal * 0.01, solid), "quad at %v faces into the shape", centre)
		testing.expectf(t, point_in_boxes(centre - normal * 0.01, solid), "quad at %v has no solid behind it", centre)
		testing.expect_value(t, quad.group, expected_face_group(normal))
		if border, found := quad.border.?; found {
			axis := direction_axis(border)
			plane := direction_is_positive(border) ? f32(1) : f32(0)
			for corner in quad.corners {
				testing.expect_value(t, corner[axis], plane)
			}
			testing.expect(t, linalg.dot(normal, linalg.to_f32(direction_offsets[border])) > 0.99)
		}
	}
}

shape_quads_area :: proc(quads: Shape_Quads) -> f32 {
	quads := quads
	total: f32
	for quad in quads.quads[:quads.count] {
		total += quad_area(quad)
	}
	return total
}

@(test)
test_shape_collision_boxes :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	testing.expect_value(t, block_collision_boxes(registry, SHAPE_TEST_STONE)[0], Box{minimum = {0, 0, 0}, maximum = {1, 1, 1}})
	testing.expect_value(t, len(block_collision_boxes(registry, SHAPE_TEST_SLAB)), 1)
	testing.expect_value(t, block_collision_boxes(registry, SHAPE_TEST_SLAB)[0], Box{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}})
	testing.expect_value(t, block_collision_boxes(registry, SHAPE_TEST_UPPER_SLAB)[0], Box{minimum = {0, 0.5, 0}, maximum = {1, 1, 1}})
	unrotated := block_collision_boxes(registry, SHAPE_TEST_STAIRS)
	testing.expect_value(t, len(unrotated), 2)
	testing.expect_value(t, unrotated[1], Box{minimum = {0.5, 0.5, 0}, maximum = {1, 1, 1}})
	for rotation in u8(1) ..< 4 {
		rotated := block_collision_boxes(registry, SHAPE_TEST_STAIRS + Block_Id(rotation))
		testing.expect_value(t, len(rotated), 2)
		for box, index in rotated {
			testing.expect_value(t, box, rotate_local_box(unrotated[index], rotation))
		}
	}
	testing.expect_value(t, len(block_collision_boxes(registry, SHAPE_TEST_TORCH)), 0)
	testing.expect_value(t, len(block_collision_boxes(registry, SHAPE_TEST_TUFT)), 0)
	testing.expect_value(t, len(block_collision_boxes(registry, AIR_BLOCK)), 0)
}

@(test)
test_shape_bounds :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	testing.expect_value(t, block_bounds(registry, SHAPE_TEST_STONE), Box{minimum = {0, 0, 0}, maximum = {1, 1, 1}})
	testing.expect_value(t, block_bounds(registry, SHAPE_TEST_SLAB), Box{minimum = {0, 0, 0}, maximum = {1, 0.5, 1}})
	testing.expect_value(t, block_bounds(registry, SHAPE_TEST_UPPER_SLAB), Box{minimum = {0, 0.5, 0}, maximum = {1, 1, 1}})
	for rotation in u8(0) ..< 4 {
		testing.expect_value(t, block_bounds(registry, SHAPE_TEST_STAIRS + Block_Id(rotation)), Box{minimum = {0, 0, 0}, maximum = {1, 1, 1}})
	}
	torch := block_bounds(registry, SHAPE_TEST_TORCH)
	testing.expect_value(t, torch.minimum.y, 0)
	testing.expect_value(t, torch.maximum.y, f32(POST_HEIGHT))
	testing.expect_value(t, torch.maximum.x - torch.minimum.x, f32(0.5))
	testing.expect_value(t, torch.maximum.z - torch.minimum.z, f32(0.5))
	testing.expect_value(t, (torch.minimum + torch.maximum) / 2, [3]f32{0.5, f32(POST_HEIGHT) / 2, 0.5})
	testing.expect_value(t, block_bounds(registry, SHAPE_TEST_TUFT), Box{minimum = {0, 0, 0}, maximum = {1, 1, 1}})
	// A post has no collision box, so the ray targets its bounds.
	targets := block_target_boxes(registry, SHAPE_TEST_TORCH)
	testing.expect_value(t, targets.count, 1)
	testing.expect_value(t, targets.boxes[0], torch)
	testing.expect_value(t, block_target_boxes(registry, SHAPE_TEST_STAIRS).count, 2)
}

@(test)
test_shape_quads_face_outward :: proc(t: ^testing.T) {
	testing.expect_value(t, shape_quads(.Cube, {}).count, 0)
	for upper in ([2]bool{false, true}) {
		orientation := Block_Orientation{upper = upper}
		quads := shape_quads(.Slab, orientation)
		testing.expect_value(t, quads.count, 6)
		expect_quads_face_outward(t, quads, shape_collision_boxes(.Slab, orientation))
		testing.expect(t, abs(shape_quads_area(quads) - 4) < 1e-5)
	}
	for rotation in u8(0) ..< 4 {
		orientation := Block_Orientation{rotation = rotation}
		quads := shape_quads(.Stairs, orientation)
		testing.expect_value(t, quads.count, 10)
		expect_quads_face_outward(t, quads, shape_collision_boxes(.Stairs, orientation))
		// The outer surface of the union: nothing missing, nothing twice.
		testing.expect(t, abs(shape_quads_area(quads) - 5.5) < 1e-5)
	}
	post := shape_quads(.Post, {})
	testing.expect_value(t, post.count, 6)
	post_boxes := [1]Box{post_box()}
	expect_quads_face_outward(t, post, post_boxes[:])
}

@(test)
test_bottom_slab_quads_border_and_inner_top :: proc(t: ^testing.T) {
	quads := shape_quads(.Slab, {})
	top_count, border_count := 0, 0
	for quad in quads.quads[:quads.count] {
		if quad.group == .Top {
			top_count += 1
			testing.expect_value(t, quad.border, nil)
			testing.expect_value(t, quad.corners[0].y, 0.5)
		}
		if quad.border != nil {
			border_count += 1
		}
	}
	testing.expect_value(t, top_count, 1)
	testing.expect_value(t, border_count, 5)
}

@(test)
test_cross_quads_are_two_diagonals_from_both_sides :: proc(t: ^testing.T) {
	quads := shape_quads(.Cross, {})
	testing.expect_value(t, quads.count, 4)
	for index in 0 ..< 2 {
		front, back := quads.quads[2 * index], quads.quads[2 * index + 1]
		testing.expect_value(t, front.group, Face_Group.Side)
		testing.expect_value(t, front.border, nil)
		testing.expect(t, linalg.dot(quad_normal(front), quad_normal(back)) < -0.99)
		testing.expect(t, abs(quad_normal(front).y) < 1e-5)
		testing.expect(t, abs(quad_area(front) - linalg.SQRT_TWO) < 1e-5)
	}
}
