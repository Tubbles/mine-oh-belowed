package game

import "core:math"
import "core:testing"

expect_f32_vector_near :: proc(t: ^testing.T, got, wanted: [3]f32, tolerance: f32, label: string) {
	for axis in 0 ..< 3 {
		testing.expectf(t, abs(got[axis] - wanted[axis]) <= tolerance, "%s: %v, wanted %v", label, got, wanted)
	}
}

// Walking a quarter round the small planet from +x towards +z: the
// camera's up is the player's up at the start (+x) and after the quarter
// (+z), and the first person look stays on the horizon.
@(test)
test_the_field_camera_takes_the_player_up_and_tilts_after_a_quarter_turn :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Sphere}, 1000)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(1000)
	start_feet := World_Position{metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES) + POSITION_UNITS_PER_METRE / 4, 0, 0}
	player := make_field_player(start_feet, {0, 0, UNIT_VECTOR_ONE})
	run_field_player(&world, tuning, &player, {}, 30)
	before := field_camera(field_player_view(player, tuning, 1, 0), .First_Person, 4, 0, 70)
	expect_f32_vector_near(t, before.up, unit_vector_to_f32(player.up), 1e-6, "camera up at the start")
	expect_f32_vector_near(t, before.up, {1, 0, 0}, 1e-3, "the start's up")
	run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, ticks_round_test_sphere(tuning, 1, 4))
	after := field_camera(field_player_view(player, tuning, 1, 0), .First_Person, 4, 0, 70)
	expect_f32_vector_near(t, after.up, unit_vector_to_f32(player.up), 1e-6, "camera up after the quarter")
	expect_f32_vector_near(t, after.up, {0, 0, 1}, 0.02, "the quarter's up")
	look := after.target - after.position
	testing.expectf(t, abs(look.x * after.up.x + look.y * after.up.y + look.z * after.up.z) < 1e-3, "the look %v leaves the horizon", look)
	third := field_camera(field_player_view(player, tuning, 1, 0), .Third_Person, 4, 0, 70)
	behind := third.position - after.position
	testing.expect(t, behind.x * look.x + behind.y * look.y + behind.z * look.z < -3.9, "the third person camera sits behind the eye")
}

@(test)
test_the_field_crouch_eases_over_its_seconds :: proc(t: ^testing.T) {
	progress: f32
	for _ in 0 ..< 10 {
		progress = advance_field_crouch(progress, true, CROUCH_EASE_SECONDS / 10)
	}
	testing.expectf(t, abs(progress - 1) <= 1e-5, "ten tenths reach %v", progress)
	testing.expect_value(t, advance_field_crouch(progress, false, 1), 0)
	half := advance_field_crouch(0, true, CROUCH_EASE_SECONDS / 2)
	testing.expectf(t, abs(half - 0.5) <= 1e-4, "half a swing gives %v", half)
	testing.expect_value(t, field_crouch_progress_of({0.5}, 1), 0)
	testing.expect_value(t, field_crouch_progress_of({0.5}, -1), 0)
	testing.expect_value(t, field_crouch_progress_of({0.5}, 0), 0.5)
}

@(test)
test_the_field_eye_follows_the_eased_crouch :: proc(t: ^testing.T) {
	tuning := test_field_tuning(500)
	player := make_field_player(test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0})
	eye_height :: proc(player: Field_Player, tuning: Field_Player_Tuning, progress: f32) -> i64 {
		return site_height(field_player_view(player, tuning, 1, progress).eye) - site_height(player.position)
	}
	testing.expect_value(t, eye_height(player, tuning, 0), tuning.eye_height)
	testing.expect_value(t, eye_height(player, tuning, 1), tuning.crouch_eye_height)
	middle := eye_height(player, tuning, 0.5)
	testing.expectf(t, middle > tuning.crouch_eye_height && middle < tuning.eye_height, "the eye at half the swing is %d", middle)
}

@(test)
test_a_crouched_field_body_is_drawn_lower :: proc(t: ^testing.T) {
	tuning := test_field_tuning(500)
	up := [3]f32{0, 1, 0}
	feet := [3]f32{0, 0, 0}
	_, standing_top := field_player_capsule_ends(feet, up, 1.8)
	_, crouched_top := field_player_capsule_ends(feet, up, field_body_up_scale(tuning, 1) * 1.8)
	testing.expectf(t, abs(standing_top.y - 1.5) <= 1e-4, "the standing top centre at %v", standing_top.y)
	testing.expectf(t, abs(crouched_top.y - 0.55) <= 1e-4, "the crouched top centre at %v", crouched_top.y)
	player := make_field_player(test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0})
	standing := transform_point(field_player_body_transform(feet, player, 1) * player_model_scale(), {0, 29, 0})
	crouched := transform_point(field_player_body_transform(feet, player, field_body_up_scale(tuning, 1)) * player_model_scale(), {0, 29, 0})
	ratio := f32(850) / 1800
	testing.expectf(t, standing.y > 1 && abs(crouched.y - standing.y * ratio) <= 1e-3, "the head at %v crouched, %v standing", crouched.y, standing.y)
}

// The pulled in third person camera (0220).

PULL_IN_TEST_TOLERANCE_METRES :: 0.02

f32_distance :: proc(first, second: [3]f32) -> f32 {
	difference := first - second
	return math.sqrt(difference.x * difference.x + difference.y * difference.y + difference.z * difference.z)
}

// A 4 m face 2 m ahead of the eye along the offset: the camera stops the
// margin short of it; an eye 0.1 m short of the face puts the camera at
// the eye.
@(test)
test_the_field_third_person_camera_stops_short_of_a_wall :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = metres_to_position_units(4)}, spacing)
		defer destroy_field_world(&world)
		eye := test_site_point(0, millimetres_to_position_units(1600), 0)
		camera := field_third_person_position(&world, nil, nil, spacing, eye, {4, 0, 0})
		distance := f32_distance(camera, world_position_to_metres(eye))
		testing.expectf(t, abs(distance - (2 - THIRD_PERSON_WALL_MARGIN)) <= PULL_IN_TEST_TOLERANCE_METRES, "%d mm: the camera %v m from the eye", spacing, distance)
		near_eye := test_site_point(millimetres_to_position_units(1900), millimetres_to_position_units(1600), 0)
		testing.expect_value(t, field_third_person_position(&world, nil, nil, spacing, near_eye, {4, 0, 0}), world_position_to_metres(near_eye))
	}
}

// Backed against the ledge's face the camera is pulled in to the eye, and
// the viewer's body is not drawn; another player's is (0261).
@(test)
test_the_field_viewers_body_is_hidden_with_the_camera_at_the_eye :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = metres_to_position_units(4)}, spacing)
		defer destroy_field_world(&world)
		near_eye := test_site_point(millimetres_to_position_units(1900), millimetres_to_position_units(1600), 0)
		position := field_third_person_position(&world, nil, nil, spacing, near_eye, {4, 0, 0})
		scene := Field_Scene{viewer = 0, viewer_body_shown = viewer_body_shown(.Third_Person, position, world_position_to_metres(near_eye))}
		testing.expectf(t, !field_player_body_drawn(scene, 0), "%d mm: the viewer's body is drawn with the camera at the eye", spacing)
		testing.expectf(t, field_player_body_drawn(scene, 1), "%d mm: the other player's body is not drawn", spacing)
	}
}

// On open ground at the settings' distance the viewer's body is drawn,
// and another player's (0261).
@(test)
test_the_field_viewers_body_is_drawn_at_the_settings_distance :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		tuning := test_field_tuning(spacing)
		player := start_crouch_test_player(&world, tuning)
		view := field_player_view(player, tuning, 1, 0)
		position := field_third_person_position(&world, nil, nil, spacing, view.eye, field_third_person_offset(view, THIRD_PERSON_DISTANCE, 0.6))
		scene := Field_Scene{viewer = 0, viewer_body_shown = viewer_body_shown(.Third_Person, position, world_position_to_metres(view.eye))}
		testing.expectf(t, field_player_body_drawn(scene, 0), "%d mm: the viewer's body is not drawn", spacing)
		testing.expectf(t, field_player_body_drawn(scene, 1), "%d mm: the other player's body is not drawn", spacing)
	}
}

// A crouched player deep in the 1 m tunnel: the ray meets the roof at a
// grazing angle, and the camera stays in the tunnel's air, the margin
// under the roof along its normal.
@(test)
test_the_field_third_person_camera_stays_inside_a_one_metre_tunnel :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(TEST_ONE_METRE_TUNNEL, spacing)
		defer destroy_field_world(&world)
		tuning := test_field_tuning(spacing)
		player := start_crouch_test_player(&world, tuning)
		run_field_player(&world, tuning, &player, FIELD_SNEAK_FORWARD, 360)
		testing.expectf(t, player.crouching && player.position.x > metres_to_position_units(5), "%d mm: crouching %v at x %d", spacing, player.crouching, player.position.x)
		view := field_player_view(player, tuning, 1, 1)
		offset := field_third_person_offset(view, THIRD_PERSON_DISTANCE, 0.6)
		camera := field_third_person_position(&world, nil, nil, spacing, view.eye, offset)
		eye := world_position_to_metres(view.eye)
		distance := f32_distance(camera, eye)
		testing.expectf(t, distance < f32_distance(offset, {}) - THIRD_PERSON_WALL_MARGIN, "%d mm: the camera %v m from the eye is not pulled in", spacing, distance)
		units := [3]i64{i64(offset.x * POSITION_UNITS_PER_METRE), i64(offset.y * POSITION_UNITS_PER_METRE), i64(offset.z * POSITION_UNITS_PER_METRE)}
		direction, _ := normalize_fixed(units)
		testing.expectf(t, !raycast_field(&world, spacing, view.eye, direction, i64(distance * POSITION_UNITS_PER_METRE)).hit, "%d mm: rock between the eye and the camera", spacing)
		testing.expectf(t, !field_position_is_ground(&world, spacing, metres_to_world_position(camera)), "%d mm: the camera %v is in the ground", spacing, camera)
		roof := f32(TEST_ONE_METRE_TUNNEL.ledge_height + sample_axis_to_position(1, spacing) / 2) / POSITION_UNITS_PER_METRE
		under := roof - (camera.y - TEST_SITE_RADIUS_METRES)
		testing.expectf(t, camera.x > TEST_LEDGE_FACE_METRES && under >= THIRD_PERSON_WALL_MARGIN - PULL_IN_TEST_TOLERANCE_METRES, "%d mm: the camera at x %v, %v m under the roof", spacing, camera.x, under)
	}
}

// Nothing in the way: the camera is field_camera's, bit for bit, at the
// settings' shortest, default and longest distances.
@(test)
test_the_field_third_person_camera_keeps_its_distance_on_open_ground :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		tuning := test_field_tuning(spacing)
		player := start_crouch_test_player(&world, tuning)
		view := field_player_view(player, tuning, 1, 0)
		for distance in ([3]f32{THIRD_PERSON_DISTANCE_RANGE.minimum, THIRD_PERSON_DISTANCE, THIRD_PERSON_DISTANCE_RANGE.maximum}) {
			camera := field_third_person_position(&world, nil, nil, spacing, view.eye, field_third_person_offset(view, distance, 0.6))
			testing.expect_value(t, camera, field_camera(view, .Third_Person, distance, 0.6, 70).position)
		}
	}
}

// Along a frame's right axis: the camera passes a belt's cell (not solid)
// and stops the margin short of cell 0's near face, 1.75 m from the eye.
@(test)
test_the_field_third_person_camera_stops_short_of_a_foundation :: proc(t: ^testing.T) {
	table, frame := make_test_frame_table(0)
	defer destroy_frame_table(&table)
	occupy_frame_cell(&table, frame.id, {-2, 0, 0}, Occupant{handle = 3, flags = {.Blocks_Water}})
	world: Field_World
	eye := frame_cell_centre(frame, {-4, 0, 0})
	camera := field_third_person_position(&world, &table, nil, 1000, eye, unit_vector_to_f32(frame.axes[FRAME_RIGHT]) * 4)
	distance := f32_distance(camera, world_position_to_metres(eye))
	testing.expectf(t, abs(distance - (1.75 - THIRD_PERSON_WALL_MARGIN)) <= PULL_IN_TEST_TOLERANCE_METRES, "the camera %v m from the eye", distance)
}

// A trunk of 0.3 m radius whose axis stands 2 m ahead: the camera stops
// the margin short of its bark, within the trunk ray's step.
@(test)
test_the_field_third_person_camera_stops_short_of_a_trunk :: proc(t: ^testing.T) {
	world: Field_World
	trunk := Field_Capsule {
		bottom = test_site_point(metres_to_position_units(2), 0, 0),
		up     = {0, UNIT_VECTOR_ONE, 0},
		length = metres_to_position_units(6),
		radius = millimetres_to_position_units(300),
	}
	eye := test_site_point(0, millimetres_to_position_units(1600), 0)
	camera := field_third_person_position(&world, nil, {trunk}, 1000, eye, {4, 0, 0})
	distance := f32_distance(camera, world_position_to_metres(eye))
	tolerance := f32(FIELD_TREE_AIM_STEP_MILLIMETRES + 2) / MILLIMETRES_PER_METRE
	testing.expectf(t, abs(distance - (2 - 0.3 - THIRD_PERSON_WALL_MARGIN)) <= tolerance, "the camera %v m from the eye", distance)
}
