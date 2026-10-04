package game

import "core:math"
import "core:math/linalg"
import "core:testing"

// The planet preview's home (work item 0184): the free camera's frame,
// the start camera, the walker on the crest and the pads, at every radius
// preset of the shipped home. Pure procedures only, no window.

PLANET_PREVIEW_TEST_SPACING_MILLIMETRES :: 1000
PLANET_PREVIEW_TEST_PITCH_MILLIMETRES :: 500

Planet_Preview_Test_Home :: struct {
	planet:     Planet,
	generation: Planet_Generation,
	site:       World_Position,
	axes:       [3][3]i64,
}

planet_preview_test_home :: proc(radius_metres: int) -> Planet_Preview_Test_Home {
	planet := shipped_test_home_at(radius_metres)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, PLANET_PREVIEW_TEST_SPACING_MILLIMETRES)
	site, axes := planet_preview_home(generation, planet, PLANET_PREVIEW_TEST_PITCH_MILLIMETRES)
	return {planet = planet, generation = generation, site = site, axes = axes}
}

// The angle between two directions in degrees.
planet_preview_test_angle_degrees :: proc(first, second: [3]f32) -> f32 {
	cosine := clamp(linalg.dot(linalg.normalize(first), linalg.normalize(second)), -1, 1)
	return math.acos(cosine) * math.DEG_PER_RAD
}

planet_preview_test_near :: proc(first, second: [3]f32, tolerance: f32) -> bool {
	return linalg.length(first - second) < tolerance
}

// The offset to a point along the body's heading and its right.
planet_preview_test_bearing :: proc(body: Field_Player, point: World_Position) -> (ahead, right: i64) {
	offset := cast([3]i64)(point - body.position)
	return fixed_dot(offset, field_player_heading(body)), fixed_dot(offset, field_player_right(body))
}

@(test)
test_planet_preview_basis_follows_the_home :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		home := planet_preview_test_home(radius)
		basis := planet_preview_basis(home.axes)
		radial := linalg.normalize(world_position_to_metres(home.site))
		testing.expectf(t, planet_preview_test_near(basis.up, radial, 0.001), "at %d m the up %v is not the radial %v", radius, basis.up, radial)
		axes := [3][3]f32{basis.forward, basis.up, basis.right}
		for first in 0 ..< 3 {
			testing.expectf(t, abs(linalg.length(axes[first]) - 1) < 0.001, "at %d m axis %d is not unit length", radius, first)
			for second in first + 1 ..< 3 {
				testing.expectf(t, abs(linalg.dot(axes[first], axes[second])) < 0.001, "at %d m axes %d and %d are not orthogonal", radius, first, second)
			}
		}
		turned := planet_preview_basis_to_world(basis, fly_camera_forward(Fly_Camera{yaw = 90}))
		field_right := unit_vector_to_f32(fixed_cross(home.axes[FRAME_FORWARD], home.axes[FRAME_UP]))
		testing.expectf(t, planet_preview_test_near(turned, field_right, 0.001), "at %d m yaw 90 looks along %v, not the field player's right %v", radius, turned, field_right)
	}
}

// The pod and the first spring lie inside a cone within the 35 degree
// vertical half field of view, whatever their bearing (0260: the door
// faces the spring at every preset).
@(test)
test_planet_preview_start_camera_frames_the_pod_and_the_spring :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		home := planet_preview_test_home(radius)
		basis := planet_preview_basis(home.axes)
		camera := planet_preview_start_camera(home.site, basis, 0)
		look := planet_preview_basis_to_world(basis, fly_camera_forward(camera))
		site := world_position_to_metres(home.site)
		pod_angle := planet_preview_test_angle_degrees(look, site - camera.position)
		testing.expectf(t, pod_angle < 30, "at %d m the pod lies %v degrees off the look", radius, pod_angle)
		spring_direction := planet_spring_direction(home.planet.springs[0])
		spring_ground := home.generation.radius + surface_relief(home.generation, fixed_scale(spring_direction, home.generation.radius))
		spring := world_position_to_metres(World_Position(fixed_scale(spring_direction, spring_ground)))
		spring_angle := planet_preview_test_angle_degrees(look, spring - camera.position)
		testing.expectf(t, spring_angle < 30, "at %d m the spring lies %v degrees off the look", radius, spring_angle)
		height := linalg.dot(camera.position - site, basis.up)
		testing.expectf(t, height > 35 && height < 45, "at %d m the camera stands %v m above the site", radius, height)
	}
}

@(test)
test_planet_preview_walker_stands_on_the_crest :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		home := planet_preview_test_home(radius)
		body := planet_preview_home_walker(home.generation, home.site, home.axes, 0)
		out := vector_length(project_onto_plane(cast([3]i64)(body.position - home.site), home.axes[FRAME_UP]))
		crest := metres_to_position_units(i64(home.planet.crater.radius_metres))
		testing.expectf(t, abs(out - crest) < POSITION_UNITS_PER_METRE / 2, "at %d m the walker stands %v m out, not on the crest", radius, f64(out) / POSITION_UNITS_PER_METRE)
		ahead, right := planet_preview_test_bearing(body, home.site)
		testing.expectf(t, ahead > 0 && right > 0, "at %d m the site is not ahead and right (%d, %d)", radius, ahead, right)
		if ahead > 0 {
			ratio := right * 1000 / ahead
			testing.expectf(t, ratio > 268 && ratio < 700, "at %d m the site's bearing ratio is %d", radius, ratio)
		}
		along := fixed_dot(field_player_heading(body), home.axes[FRAME_FORWARD])
		testing.expectf(t, along > UNIT_VECTOR_ONE * 99 / 100, "at %d m the heading is off the door's direction (%d)", radius, along)
		turned := planet_preview_home_walker(home.generation, home.site, home.axes, 40)
		turned_along := f64(fixed_dot(field_player_heading(turned), home.axes[FRAME_FORWARD])) / UNIT_VECTOR_ONE
		testing.expectf(t, abs(turned_along - math.cos(f64(40) * math.RAD_PER_DEG)) < 0.01, "at %d m yaw 40 heads %v along the door", radius, turned_along)
	}
}

@(test)
test_planet_preview_pads_stand_outside_the_crater_in_view :: proc(t: ^testing.T) {
	for radius in default_planet(shipped_test_planets()).radius_presets_metres {
		home := planet_preview_test_home(radius)
		crater := home.planet.crater
		first := planet_preview_home_point(home.site, home.axes, PLANET_PREVIEW_PAD_FORWARD_MILLIMETRES, PLANET_PREVIEW_PAD_FRAME_RIGHT_MILLIMETRES)
		out := vector_length(project_onto_plane(cast([3]i64)(first - home.site), home.axes[FRAME_UP]))
		reach := metres_to_position_units(i64(crater.radius_metres + CRATER_RIM_FALL_PER_HEIGHT * crater.rim_metres))
		half_diagonal := millimetres_to_position_units((2 * PLANET_PREVIEW_PAD_HALF_WIDTH + 1) * PLANET_PREVIEW_TEST_PITCH_MILLIMETRES * 1414 / 2000)
		testing.expectf(t, out > reach + half_diagonal, "at %d m the first pad lies %v m out, inside the crater's reach", radius, f64(out) / POSITION_UNITS_PER_METRE)
		body := planet_preview_home_walker(home.generation, home.site, home.axes, 0)
		ahead, right := planet_preview_test_bearing(body, first)
		testing.expectf(t, ahead > 0 && right < 0 && -right * 1000 / ahead < 1192, "at %d m the first pad is not ahead and left within 50 degrees (%d, %d)", radius, ahead, right)
		origin, axes := free_frame_at(field_surface_under(home.generation, first, 0), home.axes[FRAME_FORWARD], PLANET_PREVIEW_TEST_PITCH_MILLIMETRES)
		frame := Frame{origin = origin, axes = axes, pitch_millimetres = PLANET_PREVIEW_TEST_PITCH_MILLIMETRES}
		second := frame_cell_bottom(frame, {}) + World_Position(fixed_scale(planet_preview_run_direction(frame), millimetres_to_position_units(PLANET_PREVIEW_SECOND_PAD_DISTANCE_MILLIMETRES)))
		second_ahead, second_right := planet_preview_test_bearing(body, second)
		testing.expectf(t, second_ahead > 0 && second_right < 0 && -second_right * 1000 / second_ahead < 1192, "at %d m the second pad is not ahead and left within 50 degrees (%d, %d)", radius, second_ahead, second_right)
	}
}
