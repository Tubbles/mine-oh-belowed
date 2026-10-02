package game

import "core:testing"

// Flat ground 8000 m out along +y, at 1 m spacing (the test terrains of
// player_field_test.odin).
@(test)
test_a_field_ray_hits_flat_ground_at_its_height :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&world)
	down := [3]i64{0, -UNIT_VECTOR_ONE, 0}
	height := metres_to_position_units(3) + 1000
	origin := test_site_point(0, height, 0)
	hit := raycast_field(&world, 1000, origin, down, metres_to_position_units(5))
	testing.expect(t, hit.hit)
	testing.expectf(t, abs(hit.distance - height) <= POSITION_UNITS_PER_METRE / 64, "hit at %d, ground at %d", hit.distance, height)
	testing.expectf(t, hit.normal.y > UNIT_VECTOR_ONE - UNIT_VECTOR_ONE / 64, "normal %v", hit.normal)
	testing.expect_value(t, hit.sample, Sample_Coordinate{0, TEST_SITE_RADIUS_METRES, 0})
	short := raycast_field(&world, 1000, origin, down, metres_to_position_units(2))
	testing.expect(t, !short.hit)
}

// A ray starting in the ground hits at once; a ray into missing chunks
// reads air.
@(test)
test_a_field_ray_from_the_ground_hits_at_its_origin :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&world)
	inside := test_site_point(0, -metres_to_position_units(2), 0)
	hit := raycast_field(&world, 1000, inside, {UNIT_VECTOR_ONE, 0, 0}, metres_to_position_units(4))
	testing.expect(t, hit.hit && hit.distance == 0)
	testing.expectf(t, hit.normal == radial_up(inside), "a hit deep in the ground takes the radial up as its normal, not %v", hit.normal)
	empty: Field_World
	testing.expect(t, !raycast_field(&empty, 1000, inside, {0, -UNIT_VECTOR_ONE, 0}, metres_to_position_units(4)).hit)
}
