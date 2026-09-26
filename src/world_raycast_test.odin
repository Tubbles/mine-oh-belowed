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
