package game

import "core:math/linalg"
import "core:testing"

// The render side of work item 0072: the flicker of block light and the
// sun shadows' matrices, all pure.

SHADOW_TEST_TOLERANCE :: 1e-4

light_space_point :: proc(light_space: matrix[4, 4]f32, point: [3]f32) -> [3]f32 {
	clip := light_space * [4]f32{point.x, point.y, point.z, 1}
	return clip.xyz / clip.w
}

point_in_clip_box :: proc(point: [3]f32) -> bool {
	limit: f32 = 1 + SHADOW_TEST_TOLERANCE
	return abs(point.x) <= limit && abs(point.y) <= limit && abs(point.z) <= limit
}

@(test)
test_light_flicker_stays_in_range :: proc(t: ^testing.T) {
	lowest, highest: f32 = 1, 0
	for step in 0 ..< 10_000 {
		flicker := light_flicker(f64(step) * 0.0037 + 1000)
		lowest, highest = min(lowest, flicker), max(highest, flicker)
	}
	testing.expect(t, lowest >= LIGHT_FLICKER_MINIMUM - SHADOW_TEST_TOLERANCE, "the flicker goes below its minimum")
	testing.expect(t, highest <= 1, "the flicker brightens block light")
	// It does flicker, not stand still.
	testing.expect(t, highest - lowest > 0.02, "the flicker barely moves")
	testing.expect_value(t, light_flicker(0), 0.98)
}

// Every point within the range of the camera's block lies inside the
// light's clip box, whatever the sun's direction, the block's centre on
// the box's middle depth; a point beyond the range across the sun does
// not.
@(test)
test_light_space_matrix_maps_the_range_into_clip_space :: proc(t: ^testing.T) {
	camera := [3]f32{130.6, 71.2, -40.3}
	centre := shadow_centre(camera)
	for fraction in ([?]f64{0.05, 0.12, 0.25, 0.4}) {
		frame := shadow_frame(true, camera, fraction)
		middle := light_space_point(frame.light_space, centre)
		testing.expectf(t, linalg.length(middle) < SHADOW_TEST_TOLERANCE, "the centre maps to %v at fraction %v", middle, fraction)
		for axis in 0 ..< 3 {
			for sign in ([?]f32{-1, 1}) {
				offset: [3]f32
				offset[axis] = sign * SHADOW_RANGE_BLOCKS
				point := light_space_point(frame.light_space, centre + offset)
				testing.expectf(t, point_in_clip_box(point), "%v blocks from the centre maps to %v at fraction %v", offset, point, fraction)
			}
		}
		// Along the light's own x axis (the view's first row), just past
		// the range, the box ends.
		across := [3]f32{frame.view[0, 0], frame.view[0, 1], frame.view[0, 2]}
		outside := light_space_point(frame.light_space, centre + across * (SHADOW_RANGE_BLOCKS + 1))
		testing.expectf(t, !point_in_clip_box(outside), "past the range maps inside the box at fraction %v", fraction)
		// Towards the sun is nearer to the light: smaller depth.
		towards := light_space_point(frame.light_space, centre + frame.sun * 10)
		testing.expect(t, towards.z < middle.z, "a point towards the sun is not nearer")
	}
}

// The box follows the camera in whole blocks: anywhere inside one block
// the matrix is the same, in the next block it moves.
@(test)
test_shadow_box_snaps_to_whole_blocks :: proc(t: ^testing.T) {
	testing.expect_value(t, shadow_centre({10.3, 64.9, -5.2}), [3]f32{10, 64, -6})
	first := shadow_frame(true, {10.05, 64.9, -5.2}, 0.2)
	second := shadow_frame(true, {10.95, 64.1, -5.9}, 0.2)
	testing.expect(t, first.light_space == second.light_space, "the matrix moves within a block")
	next := shadow_frame(true, {11.05, 64.1, -5.9}, 0.2)
	testing.expect(t, first.light_space != next.light_space, "the matrix stays in the next block")
}

// Off, at night or with the sun on the horizon the shadows are off; by
// full day they are full.
@(test)
test_shadow_strength_follows_the_sun :: proc(t: ^testing.T) {
	testing.expect_value(t, shadow_frame(false, {}, NOON_FRACTION).strength, 0)
	testing.expect_value(t, shadow_frame(true, {}, NOON_FRACTION).strength, 1)
	testing.expect_value(t, shadow_frame(true, {}, 0.75).strength, 0)
	testing.expect_value(t, shadow_frame(true, {}, 0).strength, 0)
	dawn := shadow_strength_for_sun_height((SHADOW_FADE_START + SHADOW_FADE_END) / 2)
	testing.expect(t, dawn > 0 && dawn < 1, "no fade between the fade heights")
	testing.expect(t, shadow_depth_bias() > 0 && shadow_depth_bias() < 0.01, "the bias is outside a few texels")
}

@(test)
test_shadow_pass_takes_chunks_within_range :: proc(t: ^testing.T) {
	camera := [3]f32{16, 40, 16}
	testing.expect(t, chunk_in_shadow_range({0, 1, 0}, camera), "the camera's chunk")
	testing.expect(t, chunk_in_shadow_range({3, 1, 0}, camera), "a chunk 80 blocks away")
	testing.expect(t, !chunk_in_shadow_range({4, 1, 0}, camera), "a chunk 112 blocks away")
	testing.expect(t, !chunk_in_shadow_range({3, 1, 3}, camera), "a chunk 113 blocks away diagonally")
}
