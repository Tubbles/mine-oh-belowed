package game

import "core:math"
import "core:testing"

// The collision volumes' wire outlines (work item 0230).
@(test)
test_collision_wire_lines_outline_each_volume :: proc(t: ^testing.T) {
	box := test_collision_volume({kind = "box", from = {0, 0, 0}, to = {1, 1, 1}})
	solid := test_collision_volume({kind = "round", axis = "y", from = {0, 0, 0}, to = {0, 1, 0}, radius_from = 1, radius_to = 1})
	shell := test_collision_volume({kind = "round", axis = "y", from = {0, 0, 0}, to = {0, 1, 0}, radius_from = 1, radius_to = 1, shell = 0.25})
	half := test_collision_volume({kind = "round", axis = "y", from = {0, 0, 0}, to = {0, 1, 0}, radius_from = 1, radius_to = 1, shell = 0.25, sector = []f64{0, 180}})
	testing.expect_value(t, len(collision_volume_wire_lines(box)), 12)
	testing.expect_value(t, len(collision_volume_wire_lines(solid)), 52)
	testing.expect_value(t, len(collision_volume_wire_lines(shell)), 100)
	testing.expect_value(t, len(collision_volume_wire_lines(half)), 56)
	for line in collision_volume_wire_lines(shell) {
		for point in line {
			radius := math.sqrt(point.x * point.x + point.z * point.z)
			testing.expectf(t, abs(radius - 1) < 1e-4 || abs(radius - 0.75) < 1e-4, "a point at radius %f", radius)
		}
	}
}
