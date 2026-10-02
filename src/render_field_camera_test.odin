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
	before := field_camera(field_player_view(player, tuning, 1), .First_Person, 4, 0, 70)
	expect_f32_vector_near(t, before.up, unit_vector_to_f32(player.up), 1e-6, "camera up at the start")
	expect_f32_vector_near(t, before.up, {1, 0, 0}, 1e-3, "the start's up")
	run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, ticks_round_test_sphere(tuning, 1, 4))
	after := field_camera(field_player_view(player, tuning, 1), .First_Person, 4, 0, 70)
	expect_f32_vector_near(t, after.up, unit_vector_to_f32(player.up), 1e-6, "camera up after the quarter")
	expect_f32_vector_near(t, after.up, {0, 0, 1}, 0.02, "the quarter's up")
	look := after.target - after.position
	testing.expectf(t, abs(look.x * after.up.x + look.y * after.up.y + look.z * after.up.z) < 1e-3, "the look %v leaves the horizon", look)
	third := field_camera(field_player_view(player, tuning, 1), .Third_Person, 4, 0, 70)
	behind := third.position - after.position
	testing.expect(t, behind.x * look.x + behind.y * look.y + behind.z * look.z < -3.9, "the third person camera sits behind the eye")
}
