package game

import "core:testing"

@(test)
test_the_nearest_point_lights_are_kept_nearest_first :: proc(t: ^testing.T) {
	lights: [12]Point_Light
	for &light, index in lights {
		light = Point_Light{position = {f32(12 - index), 0, 0}, radius = 1}
	}
	nearest, count := nearest_point_lights(lights[:], {0, 0, 0})
	testing.expect_value(t, count, MAXIMUM_POINT_LIGHTS)
	for light, index in nearest {
		testing.expect_value(t, light.position.x, f32(index + 1))
	}
	few, few_count := nearest_point_lights(lights[:3], {10, 0, 0})
	testing.expect_value(t, few_count, 3)
	testing.expect_value(t, few[0].position.x, 10)
	testing.expect_value(t, few[3].radius, 0)
}
