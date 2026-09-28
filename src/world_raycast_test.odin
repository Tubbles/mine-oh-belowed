package game

import "core:math/linalg"
import "core:testing"

@(test)
test_raycast_axis_aligned_hits :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	set_blocks(&world, test_block(registry, "stone"), {5, 1, 0})
	sideways := raycast_blocks(&world, registry, {0.5, 1.5, 0.5}, {1, 0, 0}, PLAYER_REACH)
	testing.expect(t, sideways.hit)
	testing.expect_value(t, sideways.block, World_Coordinate{5, 1, 0})
	testing.expect_value(t, sideways.face, Direction.Negative_X)
	testing.expect_value(t, sideways.adjacent, World_Coordinate{4, 1, 0})
	testing.expect(t, abs(sideways.distance - 4.5) < 1e-4)
	down := raycast_blocks(&world, registry, {0.5, 3.5, 0.5}, {0, -1, 0}, PLAYER_REACH)
	testing.expect_value(t, down.block, World_Coordinate{0, 0, 0})
	testing.expect_value(t, down.face, Direction.Positive_Y)
	testing.expect_value(t, down.adjacent, World_Coordinate{0, 1, 0})
}

@(test)
test_raycast_diagonal_hits :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	floor := raycast_blocks(&world, registry, {0.2, 2.5, 0.5}, linalg.normalize([3]f32{1, -1, 0}), PLAYER_REACH)
	testing.expect_value(t, floor.block, World_Coordinate{1, 0, 0})
	testing.expect_value(t, floor.face, Direction.Positive_Y)
	testing.expect_value(t, floor.adjacent, World_Coordinate{1, 1, 0})
	for z in i32(-4) ..= 4 {
		set_blocks(&world, test_block(registry, "stone"), {3, 1, z})
	}
	wall := raycast_blocks(&world, registry, {0.5, 1.5, 0.5}, linalg.normalize([3]f32{1, 0, 0.5}), PLAYER_REACH)
	testing.expect_value(t, wall.block, World_Coordinate{3, 1, 1})
	testing.expect_value(t, wall.face, Direction.Negative_X)
	testing.expect_value(t, wall.adjacent, World_Coordinate{2, 1, 1})
}

@(test)
test_raycast_misses_air_and_respects_reach :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	up := raycast_blocks(&world, registry, {0.5, 1.5, 0.5}, {0, 1, 0}, PLAYER_REACH)
	testing.expect(t, !up.hit)
	water := test_block(registry, "water")
	set_blocks(&world, water, {1, 1, 0}, {2, 1, 0})
	through_water := raycast_blocks(&world, registry, {0.5, 1.5, 0.5}, {1, 0, 0}, PLAYER_REACH)
	testing.expect(t, !through_water.hit)
	set_blocks(&world, test_block(registry, "stone"), {6, 1, 0})
	testing.expect(t, !raycast_blocks(&world, registry, {0.5, 1.5, 0.5}, {1, 0, 0}, PLAYER_REACH).hit)
	testing.expect(t, raycast_blocks(&world, registry, {1.5, 1.5, 0.5}, {1, 0, 0}, PLAYER_REACH).hit)
}

// A ray through the empty upper half of a bottom slab hits the block
// behind it; one lower meets the slab's side, one from above its top.
@(test)
test_raycast_passes_over_a_slab_and_hits_its_half :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	world := make_floor_world(registry, 32)
	set_blocks(&world, SHAPE_TEST_SLAB, {2, 1, 0})
	set_blocks(&world, SHAPE_TEST_STONE, {4, 1, 0})
	over := raycast_blocks(&world, registry, {0.5, 1.75, 0.5}, {1, 0, 0}, PLAYER_REACH)
	testing.expect(t, over.hit)
	testing.expect_value(t, over.block, World_Coordinate{4, 1, 0})
	testing.expect_value(t, over.adjacent, World_Coordinate{3, 1, 0})
	side := raycast_blocks(&world, registry, {0.5, 1.25, 0.5}, {1, 0, 0}, PLAYER_REACH)
	testing.expect_value(t, side.block, World_Coordinate{2, 1, 0})
	testing.expect_value(t, side.face, Direction.Negative_X)
	testing.expect_value(t, side.adjacent, World_Coordinate{1, 1, 0})
	testing.expect(t, abs(side.distance - 1.5) < 1e-4)
	top := raycast_blocks(&world, registry, {2.5, 3.5, 0.5}, {0, -1, 0}, PLAYER_REACH)
	testing.expect_value(t, top.block, World_Coordinate{2, 1, 0})
	testing.expect_value(t, top.face, Direction.Positive_Y)
	testing.expect_value(t, top.adjacent, World_Coordinate{2, 2, 0})
	testing.expect(t, abs(top.distance - 2) < 1e-4)
}

// A torch has no collision box: the ray targets a box half a block wide
// around its post, so it can be aimed at and mined, and passes beside
// that box.
@(test)
test_raycast_hits_a_torch_post :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	world := make_floor_world(registry, 32)
	set_blocks(&world, SHAPE_TEST_TORCH, {2, 1, 0})
	hit := raycast_blocks(&world, registry, {0.5, 1.3, 0.5}, {1, 0, 0}, PLAYER_REACH)
	testing.expect(t, hit.hit)
	testing.expect_value(t, hit.block, World_Coordinate{2, 1, 0})
	testing.expect(t, abs(hit.distance - (2 - f32(POST_TARGET_HALF_WIDTH))) < 1e-4)
	testing.expect_value(t, hit.face, Direction.Negative_X)
	// Off the drawn post but inside the target box.
	near := raycast_blocks(&world, registry, {0.5, 1.3, 0.3}, {1, 0, 0}, PLAYER_REACH)
	testing.expect(t, near.hit)
	testing.expect_value(t, near.block, World_Coordinate{2, 1, 0})
	beside := raycast_blocks(&world, registry, {0.5, 1.3, 0.2}, {1, 0, 0}, PLAYER_REACH)
	testing.expect(t, !beside.hit)
	above := raycast_blocks(&world, registry, {0.5, 1.8, 0.5}, {1, 0, 0}, PLAYER_REACH)
	testing.expect(t, !above.hit)
}
