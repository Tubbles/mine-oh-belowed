package game

import "core:math/linalg"
import "core:testing"
import rl "shared:raylib"

@(test)
test_belt_ghost_surface_sits_where_a_real_belt_does :: proc(t: ^testing.T) {
	origin := World_Coordinate{3, 5, -2}
	for shape in Belt_Shape {
		for rotation in u8(0) ..< 4 {
			placement := Placement{shown = true, valid = true, belt = true, origin = origin, rotation = rotation, size = {1, 1, 1}, belt_shape = shape}
			ghost := placement_ghost_belt(placement)
			real := make_belt(Entity_Common{origin = origin, rotation = rotation, size = {1, 1, 1}}, shape)
			testing.expect_value(t, ghost.shape, shape)
			testing.expect_value(t, belt_surface_pose(ghost), belt_surface_pose(real))
			testing.expect_value(t, belt_surface_pose(ghost), Belt_Surface_Pose{position = {3.5, 5, -1.5}, angle = -90 * f32(rotation)})
		}
	}
}

@(test)
test_ghost_tint_keeps_the_ghost_alpha :: proc(t: ^testing.T) {
	for tint in ([]rl.Color{GHOST_VALID_COLOR, GHOST_INVALID_COLOR}) {
		for color in ghost_layer_colors(tint) {
			testing.expect_value(t, color, tint)
			testing.expect(t, color.a < 255)
		}
	}
}

@(test)
test_inserter_ghost_cells_follow_rotation_and_reach :: proc(t: ^testing.T) {
	origin := World_Coordinate{10, 4, 7}
	forwards := [4]World_Coordinate{{1, 0, 0}, {0, 0, 1}, {-1, 0, 0}, {0, 0, -1}}
	for reach in i32(1) ..= 2 {
		machine := Machine{inserter_reach = reach}
		for forward, rotation in forwards {
			placement := Placement{shown = true, inserter = true, origin = origin, rotation = u8(rotation), size = {1, 1, 1}}
			pickup, drop := inserter_ghost_cells(placement, machine)
			testing.expect_value(t, pickup, origin - forward * reach)
			testing.expect_value(t, drop, origin + forward * reach)
		}
	}
}

// The head's last corner is the tip, the farthest point along the flow,
// and the head is wider than the shaft across it.
expect_chevron_points_along :: proc(t: ^testing.T, chevron: Ghost_Chevron, forward: [3]f32) {
	tip := chevron[2][2]
	centre := (chevron[0][0] + chevron[0][1]) / 2 + forward * (GHOST_CHEVRON_LENGTH / 2)
	testing.expectf(t, linalg.length(tip - centre - forward * (GHOST_CHEVRON_LENGTH / 2)) < 1e-4, "tip %v, centre %v, forward %v", tip, centre, forward)
	for triangle in chevron {
		for corner in triangle {
			testing.expectf(t, linalg.dot(corner - tip, forward) < 1e-4, "corner %v beyond the tip %v", corner, tip)
		}
	}
	head_width := linalg.length(chevron[2][1] - chevron[2][0])
	shaft_width := linalg.length(chevron[0][1] - chevron[0][0])
	testing.expect(t, head_width > shaft_width)
	testing.expect(t, abs(linalg.dot(chevron[2][1] - chevron[2][0], forward)) < 1e-4)
}

@(test)
test_ghost_chevrons_point_along_the_flow :: proc(t: ^testing.T) {
	origin := World_Coordinate{-4, 2, 9}
	for rotation in u8(0) ..< 4 {
		forward := belt_direction_vector(rotation)
		belt := make_belt(Entity_Common{origin = origin, rotation = rotation}, .Flat)
		chevron := belt_ghost_chevron(belt)
		expect_chevron_points_along(t, chevron, forward)
		surface := f32(origin.y) + BELT_SURFACE_HEIGHT
		for triangle in chevron {
			for corner in triangle {
				testing.expectf(t, corner.y > surface, "rotation %d: corner %v below the surface", rotation, corner)
			}
		}
		placement := Placement{shown = true, inserter = true, origin = origin, rotation = rotation, size = {1, 1, 1}}
		expect_chevron_points_along(t, inserter_ghost_chevron(placement, 0.8), forward)
		testing.expect(t, inserter_ghost_chevron(placement, 0.8)[0][0].y > f32(origin.y) + 0.8)
	}
	ramp := make_belt(Entity_Common{origin = origin, rotation = 0}, .Ramp_Up)
	ramp_chevron := belt_ghost_chevron(ramp)
	testing.expect(t, ramp_chevron[2][2].y > ramp_chevron[0][0].y)
}
