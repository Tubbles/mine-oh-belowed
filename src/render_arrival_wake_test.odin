package game

import "core:math"
import "core:math/linalg"
import "core:testing"
import rl "shared:raylib"

// The entry's wake (work item 0304), pure: its shape against the shipped
// pod, the drawing order, the light, the frame the shader reads, what
// the portholes see of it and the arrival camera.

// The larger root t of |(origin + t direction).xz| = radius: where a ray
// from inside a tube about the y axis leaves it.
wake_test_tube_exit :: proc(origin, direction: [3]f32, radius: f32) -> f32 {
	a := direction.x * direction.x + direction.z * direction.z
	b := 2 * (origin.x * direction.x + origin.z * direction.z)
	c := origin.x * origin.x + origin.z * origin.z - radius * radius
	return (-b + math.sqrt(b * b - 4 * a * c)) / (2 * a)
}

// The radius of the shipped wake's flats.
wake_test_flats :: proc(shape: Arrival_Wake_Shape) -> f32 {
	return shape.radius * math.cos(f32(math.PI) / ARRIVAL_WAKE_SIDES)
}

// The tube's flats stand 0.04 to 0.06 cells outside the rim and every
// corner of the body at least 0.04 inside them, none under the base: no
// flame touches the hull.
@(test)
test_the_wake_clears_the_pod :: proc(t: ^testing.T) {
	pod, triangles := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	flats := wake_test_flats(shape)
	clearance := flats - pod.heat_shield.radius
	testing.expectf(t, clearance >= 0.04 && clearance <= 0.06, "the flats stand %v outside the rim", clearance)
	widest, lowest: f32 = 0, 0
	for triangle in triangles {
		for corner in triangle.corners {
			widest = max(widest, linalg.length(corner.xz))
			lowest = min(lowest, corner.y)
		}
	}
	testing.expectf(t, widest <= flats - 0.04, "the body reaches %v from the axis, the flats %v", widest, flats)
	testing.expectf(t, lowest >= 0, "the body reaches y %v", lowest)
	testing.expectf(t, abs(shape.length - 21.8) < 1e-4, "the wake is %v long", shape.length)
	testing.expect_value(t, shape.shield_radius, 5.45)
}

// Every quad's corners lie on the tube from the rim to the end, each
// quad's far corners are the next one's near corners bit for bit (the
// last's the first's), the texture's x runs 0 to 1 without running back,
// and each normal is unit and square to its quad's bottom edge.
@(test)
test_the_wake_tube_closes_without_a_seam :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	for index in 0 ..< ARRIVAL_WAKE_SIDES {
		corners, coordinates := arrival_wake_quad(shape, index)
		for corner, corner_index in corners {
			testing.expectf(t, abs(linalg.length(corner.xz) - shape.radius) < 1e-4, "quad %d corner %d lies %v from the axis", index, corner_index, linalg.length(corner.xz))
			height: f32 = corner_index < 2 ? 0 : shape.length
			testing.expectf(t, corner.y == height, "quad %d corner %d lies at y %v", index, corner_index, corner.y)
		}
		next, _ := arrival_wake_quad(shape, (index + 1) % ARRIVAL_WAKE_SIDES)
		testing.expectf(t, corners[1] == next[0] && corners[2] == next[3], "quad %d does not meet quad %d", index, (index + 1) % ARRIVAL_WAKE_SIDES)
		left, right := f32(index) / ARRIVAL_WAKE_SIDES, f32(index + 1) / ARRIVAL_WAKE_SIDES
		testing.expect_value(t, coordinates, [4][2]f32{{left, 0}, {right, 0}, {right, shape.length}, {left, shape.length}})
		normal := arrival_wake_quad_normal(index)
		testing.expectf(t, abs(linalg.length(normal) - 1) < 1e-5, "normal %d is %v long", index, linalg.length(normal))
		testing.expectf(t, abs(linalg.dot(normal, corners[1] - corners[0])) < 1e-4, "normal %d leans on its quad", index)
	}
	_, last := arrival_wake_quad(shape, ARRIVAL_WAKE_SIDES - 1)
	testing.expect_value(t, last[1].x, 1)
}

// The disc's triangles fan from {0, -0.03, 0} to the rim's radius at the
// same depth, each meeting the next.
@(test)
test_the_shield_disc_lies_under_the_base :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	for index in 0 ..< ARRIVAL_WAKE_SIDES {
		corners, _ := arrival_wake_shield_triangle(shape, index)
		testing.expect_value(t, corners[0], [3]f32{0, -0.03, 0})
		for corner in corners[1:] {
			testing.expectf(t, abs(linalg.length(corner.xz) - 5.45) < 1e-4 && corner.y == -0.03, "triangle %d reaches %v", index, corner)
		}
		next, _ := arrival_wake_shield_triangle(shape, (index + 1) % ARRIVAL_WAKE_SIDES)
		testing.expectf(t, corners[2] == next[1], "triangle %d does not meet the next", index)
	}
}

// The order is a permutation of the quads, those facing away from the
// eye first: about 18 from beside the pod, all 32 from inside the tube
// and from under the base on the axis.
@(test)
test_the_far_walls_draw_first :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	eyes := [3][3]f32{{0, 3, -32}, cabin_eyes(pod)[0], {0, -12, 0}}
	for eye, eye_index in eyes {
		order, far_count := arrival_wake_quad_order(shape, eye)
		seen: [ARRIVAL_WAKE_SIDES]bool
		for index, position in order {
			testing.expectf(t, index >= 0 && index < ARRIVAL_WAKE_SIDES && !seen[index], "eye %d: quad %d twice or out of range", eye_index, index)
			if index < 0 || index >= ARRIVAL_WAKE_SIDES {
				continue
			}
			seen[index] = true
			corners, _ := arrival_wake_quad(shape, index)
			facing := linalg.dot(arrival_wake_quad_normal(index), eye - corners[0]) > 0
			testing.expectf(t, facing == (position >= far_count), "eye %d: quad %d at %d faces %v, far count %d", eye_index, index, position, facing, far_count)
		}
		if eye_index == 0 {
			testing.expectf(t, far_count >= 16 && far_count <= 20, "%d far walls from beside the pod", far_count)
		} else {
			testing.expectf(t, far_count == ARRIVAL_WAKE_SIDES, "eye %d: %d far walls", eye_index, far_count)
		}
	}
}

// Every cabin eye lies inside the tube; eyes beside it, beyond its end
// and under the base do not, and nothing lies inside no wake.
@(test)
test_the_eye_inside_the_wake :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	for eye, index in cabin_eyes(pod) {
		testing.expectf(t, arrival_eye_inside_wake(shape, eye), "cabin eye %d (%v) is outside", index, eye)
	}
	for eye in ([3][3]f32{{0, 3, -32}, {0, 30, 0}, {0, -1, 0}}) {
		testing.expectf(t, !arrival_eye_inside_wake(shape, eye), "%v is inside", eye)
	}
	testing.expect(t, !arrival_eye_inside_wake(arrival_wake_shape({}), {}))
}

// The light halves every quarter diameter at the peak and half that at
// heat 0; the opacity scale gives the percent at the reference
// intensity and rises with it.
@(test)
test_the_wake_light_and_opacity :: proc(t: ^testing.T) {
	pod, _ := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	testing.expectf(t, abs(arrival_wake_half_light_cells(shape, 1) - 2.725) < 1e-4, "the light halves every %v cells at the peak", arrival_wake_half_light_cells(shape, 1))
	testing.expectf(t, abs(arrival_wake_half_light_cells(shape, 0) - 1.3625) < 1e-4, "the light halves every %v cells at heat 0", arrival_wake_half_light_cells(shape, 0))
	scale := arrival_wake_opacity_scale(80)
	testing.expectf(t, abs(scale - -math.ln(f32(0.2)) / 0.8) < 1e-4, "the scale at 80 is %v", scale)
	previous: f32 = 0
	for percent in MINIMUM_ARRIVAL_WAKE_OPACITY_PERCENT ..= MAXIMUM_ARRIVAL_WAKE_OPACITY_PERCENT {
		scale = arrival_wake_opacity_scale(percent)
		testing.expectf(t, scale > previous, "the scale falls at %d percent", percent)
		previous = scale
	}
}

// Work item 0305: the wake's colours stay warm, KSP's red, orange, gold
// and yellow white. Every stop has red the largest, at 0.95 or more, and
// green over blue (a hue of 0 to 60, so never pink, lilac or violet,
// which need blue over green), saturated 0.35 or more (never grey or
// white), green rising against red from stop to stop. The stops suffice:
// a mix of two neighbours keeps red the largest and green over blue, its
// saturation near the lesser's.
@(test)
test_the_wake_ramp_stays_warm :: proc(t: ^testing.T) {
	stops := arrival_wake_ramp_stops(shipped_arrival_config().arrival_plasma)
	previous_green_share: f32 = -1
	for stop, index in stops {
		testing.expectf(t, stop.r >= 0.95, "stop %d's red is %v", index, stop.r)
		testing.expectf(t, stop.r >= stop.g && stop.g >= stop.b, "stop %d is %v, not red over green over blue", index, stop)
		saturation := 1 - stop.b / stop.r
		testing.expectf(t, saturation >= 0.35, "stop %d's saturation is %v", index, saturation)
		green_share := stop.g / stop.r
		testing.expectf(t, green_share > previous_green_share, "stop %d's green share %v does not rise past %v", index, green_share, previous_green_share)
		previous_green_share = green_share
	}
}

// The eye, the origin and the axis the shader reads are in the moved
// space: kept under the identity, turned and moved by a transform alike,
// the axis unit.
@(test)
test_the_wake_frame_is_in_the_moved_space :: proc(t: ^testing.T) {
	body := linalg.matrix4_translate_f32({10, -4, 2}) * linalg.matrix4_rotate_f32(0.3, linalg.normalize([3]f32{1, 0, 1})) * linalg.matrix4_scale_f32({0.5, 0.5, 0.5})
	eye := [3]f32{3, 7, -1}
	eye_position, origin, axis := arrival_wake_frame(body, 1, eye)
	testing.expect_value(t, eye_position, eye)
	testing.expectf(t, linalg.length(origin - transform_point(body, {})) < 1e-5, "the origin is %v", origin)
	up := linalg.normalize(cast(matrix[3, 3]f32)body * [3]f32{0, 1, 0})
	testing.expectf(t, linalg.length(axis - up) < 1e-5, "the axis is %v, the body's up %v", axis, up)
	transform := linalg.matrix4_translate_f32({100, 20, -7}) * linalg.matrix4_rotate_f32(0.8, linalg.normalize([3]f32{0.2, 1, -0.4}))
	moved_eye, moved_origin, moved_axis := arrival_wake_frame(body, transform, eye)
	testing.expectf(t, linalg.length(moved_eye - transform_point(transform, eye)) < 1e-4, "the eye is %v", moved_eye)
	testing.expectf(t, linalg.length(moved_origin - transform_point(transform, origin)) < 1e-4, "the origin is %v", moved_origin)
	turned := cast(matrix[3, 3]f32)transform * axis
	testing.expectf(t, linalg.length(moved_axis - turned) < 1e-5 && abs(linalg.length(moved_axis) - 1) < 1e-5, "the axis is %v, turned %v", moved_axis, turned)
}

// From the seated eye through window 2's bore (a 33 by 33 grid of rays
// 0.5 degrees apart, kept when no body triangle stands between the eye
// and the tube's flats) the porthole frames the wall about 4.2 cells aft
// of the rim nearly face on, as the sheath was: the shader's speeds
// cross the patch along the flow as 0288's crossed the glass, and the
// gain makes the porthole read 0288's intensity at the peak.
@(test)
test_the_wake_crosses_the_chairs_porthole_as_the_sheath_did :: proc(t: ^testing.T) {
	pod, triangles := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	flats := wake_test_flats(shape)
	eye := cabin_eyes(pod)[0]
	direction := linalg.normalize(pod.windows[2].centre - eye)
	right := linalg.normalize(linalg.cross(direction, [3]f32{0, 1, 0}))
	up := linalg.cross(right, direction)
	kept := 0
	sum, cosine_sum: f32 = 0, 0
	lowest, highest: f32 = math.F32_MAX, -math.F32_MAX
	for row in 0 ..< 33 {
		for column in 0 ..< 33 {
			across := math.to_radians(f32(column - 16) * 0.5)
			upward := math.to_radians(f32(row - 16) * 0.5)
			ray := linalg.normalize(direction + right * math.tan(across) + up * math.tan(upward))
			hit := eye + ray * wake_test_tube_exit(eye, ray, flats)
			if segment_crosses_any_triangle(eye, hit, triangles[:]) {
				continue
			}
			kept += 1
			sum += hit.y
			cosine_sum += abs(linalg.dot(ray, linalg.normalize([3]f32{hit.x, 0, hit.z})))
			lowest, highest = min(lowest, hit.y), max(highest, hit.y)
		}
	}
	testing.expectf(t, kept >= 60, "%d rays through the bore", kept)
	if kept == 0 {
		return
	}
	mean := sum / f32(kept)
	mean_cosine := cosine_sum / f32(kept)
	extent := highest - lowest
	testing.expectf(t, mean >= 3.9 && mean <= 4.5, "the porthole looks %v cells aft of the rim", mean)
	testing.expectf(t, extent >= 0.6 && extent <= 0.95, "the porthole frames %v cells along the flow", extent)
	source := #load("../data/shaders/arrival_wake.fs", string)
	fast, fast_found := shader_float_constant(source, "FAST_FLOW")
	testing.expect(t, fast_found, "arrival_wake.fs lacks FAST_FLOW")
	for name in ([3]string{"FAST_FLOW", "SPARK_FLOW", "SPARK_FAST_FLOW"}) {
		value, found := shader_float_constant(source, name)
		testing.expectf(t, found, "arrival_wake.fs lacks %s", name)
		crossing := extent * 60 / value
		testing.expectf(t, crossing >= 2 && crossing <= 4, "%s crosses the porthole in %v ticks", name, crossing)
	}
	slow, slow_found := shader_float_constant(source, "SLOW_FLOW")
	testing.expectf(t, slow_found && slow >= 2.3 && slow <= fast, "SLOW_FLOW is %v", slow)
	calm, calm_found := shader_float_constant(source, "CALM_FLOW")
	calm_target := 0.56 * extent / 2
	testing.expectf(t, calm_found && abs(calm - calm_target) <= 0.1 * calm_target, "CALM_FLOW is %v, 0286's pace %v", calm, calm_target)
	gain, gain_found := shader_float_constant(source, "WAKE_GAIN")
	reading := gain * math.pow(f32(2), -mean / arrival_wake_half_light_cells(shape, 1)) / mean_cosine
	testing.expectf(t, gain_found && reading >= 0.9 && reading <= 1.1, "the porthole reads %v of 0288's intensity at the peak", reading)
}

// From every cabin eye every ray through a pane's centre or through 8
// points at r 0.2 on it that reaches the tube's flats without crossing
// the body meets the wall 3 to 6 cells aft of the rim, never the root,
// the end or the disc; the seated eye sees the wake through window 2.
@(test)
test_the_wake_fills_every_porthole_from_the_cabin :: proc(t: ^testing.T) {
	pod, triangles := shipped_pod_body()
	shape := arrival_wake_shape(pod.heat_shield)
	flats := wake_test_flats(shape)
	seated_through_window_2 := 0
	for eye, eye_index in cabin_eyes(pod) {
		for index in 0 ..< pod.window_count {
			window := pod.windows[index]
			points: [9][3]f32
			points[0] = window.centre
			for step in 0 ..< 8 {
				points[step + 1] = porthole_point(window, window.centre, 0.2, f32(step) * math.TAU / 8)
			}
			for point in points {
				ray := point - eye
				hit := eye + ray * wake_test_tube_exit(eye, ray, flats)
				if segment_crosses_any_triangle(eye, hit, triangles[:]) {
					continue
				}
				testing.expectf(t, hit.y >= 3 && hit.y <= 6, "eye %d (%v) sees the wake through window %d at %v cells aft", eye_index, eye, index, hit.y)
				if eye_index == 0 && index == 2 {
					seated_through_window_2 += 1
				}
			}
		}
	}
	testing.expectf(t, seated_through_window_2 > 0, "the seated eye sees nothing through window 2")
}

// The arrival camera sits at the point and looks at the target, both
// moved by the body and the pod's transform, its up and field of view
// kept; a point at the target leaves the camera as it was, and one
// straight above it takes the pod's forward as the up.
@(test)
test_the_watch_camera_follows_the_pod :: proc(t: ^testing.T) {
	camera := rl.Camera3D{position = {1, 2, 3}, target = {4, 5, 6}, up = {0, 1, 0}, fovy = 70, projection = .PERSPECTIVE}
	point, target := [3]f32{0, 3, -32}, [3]f32{0, 5, 0}
	still := arrival_watch_camera(1, 1, point, target, camera)
	testing.expect_value(t, still.position, point)
	testing.expect_value(t, still.target, target)
	testing.expect_value(t, still.up, camera.up)
	testing.expect_value(t, still.fovy, camera.fovy)
	body := linalg.matrix4_translate_f32({10, -4, 2}) * linalg.matrix4_scale_f32({0.5, 0.5, 0.5})
	transform := linalg.matrix4_translate_f32({100, 20, -7}) * linalg.matrix4_rotate_f32(0.8, linalg.normalize([3]f32{0.2, 1, -0.4}))
	moved := arrival_watch_camera(body, transform, point, target, camera)
	testing.expectf(t, linalg.length(moved.position - transform_point(transform * body, point)) < 1e-4, "the camera sits at %v", moved.position)
	testing.expectf(t, linalg.length(moved.target - transform_point(transform * body, target)) < 1e-4, "the camera looks at %v", moved.target)
	testing.expect_value(t, moved.up, camera.up)
	testing.expect_value(t, moved.fovy, camera.fovy)
	testing.expect_value(t, arrival_watch_camera(body, transform, target, target, camera), camera)
	above := arrival_watch_camera(1, 1, {0, 30, 0}, target, camera)
	testing.expect_value(t, above.up, [3]f32{0, 0, 1})
}
