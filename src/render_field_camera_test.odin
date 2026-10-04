package game

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
