package game

import "core:math"
import "core:testing"

make_test_planet_generation :: proc() -> Planet_Generation {
	return make_planet_generation(TEST_PLANET_SEED, make_test_planet(), 1000)
}

// A unit tangent at the direction, along the projection of axis.
test_tangent_at :: proc(direction, axis: [3]i64) -> [3]i64 {
	tangent, _ := normalize_fixed(project_onto_plane(axis, direction))
	return tangent
}

// The position depth below the local surface along the direction.
position_below_surface :: proc(generation: Planet_Generation, direction: [3]i64, depth: i64) -> World_Position {
	on_sphere := fixed_scale(direction, generation.radius)
	surface := generation.radius + surface_relief(generation, on_sphere)
	return World_Position(fixed_scale(direction, surface - depth))
}

// Inside a disc a sample a metre down is the vein's ore, three metres
// down (below OUTCROP_DEPTH_METRES) stone; just outside the disc a metre
// down is topsoil again.
@(test)
test_a_sample_on_a_starter_vein_is_its_ore_down_to_the_outcrop_depth :: proc(t: ^testing.T) {
	generation := make_test_planet_generation()
	materials := PLANET_STARTER_VEIN_MATERIALS
	testing.expect_value(t, generation.veins.count, len(materials))
	for index in 0 ..< generation.veins.count {
		vein := generation.veins.veins[index]
		testing.expect_value(t, vein.material, materials[index])
		inside := planet_sample(generation, position_below_surface(generation, vein.direction, metres_to_position_units(1)))
		testing.expect_value(t, inside.material, vein.material)
		testing.expect(t, inside.density > 0)
		below := planet_sample(generation, position_below_surface(generation, vein.direction, metres_to_position_units(3)))
		testing.expect_value(t, below.material, Field_Material.Stone)
		beside, _ := normalize_fixed(vein.centre + fixed_scale(test_tangent_at(vein.direction, {UNIT_VECTOR_ONE, 0, 0}), vein.radius + metres_to_position_units(1)))
		outside := planet_sample(generation, position_below_surface(generation, beside, metres_to_position_units(1)))
		testing.expect_value(t, outside.material, Field_Material.Topsoil)
	}
}

// The bearing of a point round the home, in degrees.
test_bearing_degrees :: proc(home, point: [3]i64) -> f64 {
	north := frame_north_tangent(home)
	east := fixed_cross(north, home)
	offset := point - fixed_scale(home, vector_length(point))
	return math.atan2(f64(fixed_dot(offset, east)), f64(fixed_dot(offset, north))) * 180 / math.PI
}

// The three veins lie 30 to 80 m from the home (less the chord's
// shortening, under a decimetre at 8 km) with their discs on the sphere,
// each a sixth of a turn at least from the others round the home; one
// seed plans the same veins twice, another seed others.
@(test)
test_the_starter_veins_ring_the_home_in_distinct_sectors :: proc(t: ^testing.T) {
	generation := make_test_planet_generation()
	home := fixed_scale(FRAME_NORTH, generation.radius)
	for index in 0 ..< generation.veins.count {
		vein := generation.veins.veins[index]
		distance := vector_length(vein.centre - home)
		testing.expectf(t, distance >= metres_to_position_units(PLANET_VEIN_MINIMUM_DISTANCE_METRES) - POSITION_UNITS_PER_METRE / 10, "vein %d is %d units from the home", index, distance)
		testing.expectf(t, distance <= metres_to_position_units(PLANET_VEIN_MAXIMUM_DISTANCE_METRES), "vein %d is %d units from the home", index, distance)
		testing.expect(t, vein.radius >= metres_to_position_units(PLANET_VEIN_MINIMUM_RADIUS_METRES) && vein.radius <= metres_to_position_units(PLANET_VEIN_MAXIMUM_RADIUS_METRES))
		testing.expect(t, abs(vector_length(vein.centre) - generation.radius) <= 2)
		for other in index + 1 ..< generation.veins.count {
			turn := abs(test_bearing_degrees(FRAME_NORTH, vein.centre) - test_bearing_degrees(FRAME_NORTH, generation.veins.veins[other].centre))
			turn = min(turn, 360 - turn)
			testing.expectf(t, turn >= 59, "veins %d and %d are %f degrees apart", index, other, turn)
		}
	}
	testing.expect(t, make_test_planet_generation().veins == generation.veins)
	other := make_planet_generation(TEST_PLANET_SEED + 1, make_test_planet(), 1000)
	testing.expect(t, other.veins != generation.veins)
	moved_planet := make_test_planet()
	moved_planet.home = {latitude_degrees = 0, longitude_degrees = 90}
	moved := make_planet_generation(TEST_PLANET_SEED, moved_planet, 1000)
	moved_home := planet_home_direction(moved_planet.home)
	testing.expect(t, vector_length(moved.veins.veins[0].centre - fixed_scale(moved_home, generation.radius)) <= metres_to_position_units(PLANET_VEIN_MAXIMUM_DISTANCE_METRES))
}

// Registered veins carry the starter reservoir of their ore's spawn type
// and their disc; a position over a disc (high above it, or just inside
// its edge) finds the vein and one a metre past the edge none. A second
// registration, as after a load, keeps the reservoir and restores the
// disc the save left out.
@(test)
test_a_position_on_a_veins_disc_finds_it_and_a_metre_outside_none :: proc(t: ^testing.T) {
	generation := make_test_planet_generation()
	tables := make_test_generator(DEFAULT_WORLD_SEED).veins
	veins: [dynamic]Vein
	vein_indices: map[Vein_Id]int
	defer delete(veins)
	defer delete(vein_indices)
	testing.expect_value(t, register_planet_veins(&veins, &vein_indices, generation, tables), "")
	testing.expect_value(t, len(veins), generation.veins.count)
	for index in 0 ..< generation.veins.count {
		planned := generation.veins.veins[index]
		vein := veins[index]
		testing.expect_value(t, tables.types[vein.type].definition.outcrop_blocks[0], field_material_name(planned.material))
		testing.expect(t, vein_remaining_total(vein) >= tables.size_classes[STARTER_VEIN_SIZE_CLASS].minimum_units * 9 / 10)
		above := World_Position(fixed_scale(planned.direction, generation.radius + metres_to_position_units(40)))
		found_id, found := vein_under_world_position(veins[:], above)
		testing.expect(t, found && found_id == vein.id)
		tangent := test_tangent_at(planned.direction, {0, 0, UNIT_VECTOR_ONE})
		edge := World_Position(planned.centre + fixed_scale(tangent, planned.radius - POSITION_UNITS_PER_METRE / 10))
		found_id, found = vein_under_world_position(veins[:], edge)
		testing.expect(t, found && found_id == vein.id)
		_, found = vein_under_world_position(veins[:], World_Position(planned.centre + fixed_scale(tangent, planned.radius + metres_to_position_units(1))))
		testing.expect(t, !found)
	}
	_, found := vein_under_world_position(veins[:], World_Position(fixed_scale(FRAME_NORTH, generation.radius)))
	testing.expect(t, !found)
	veins[0].remaining[0] -= 7
	drawn := veins[0].remaining
	veins[0].sphere_centre, veins[0].sphere_radius = {}, 0
	testing.expect_value(t, register_planet_veins(&veins, &vein_indices, generation, tables), "")
	testing.expect_value(t, len(veins), generation.veins.count)
	testing.expect_value(t, veins[0].remaining, drawn)
	testing.expect_value(t, veins[0].sphere_radius, generation.veins.veins[0].radius)
}

// The home is a direction, whatever its length: a home scaled by a
// thousand (a position) plans the unit home's discs, and the zero vector
// and a planet without a home plan the north pole's.
@(test)
test_a_scaled_home_plans_the_unit_homes_veins :: proc(t: ^testing.T) {
	radius := metres_to_position_units(8000)
	for home in ([?][3]i64{FRAME_NORTH, {UNIT_VECTOR_ONE, 0, 0}, {0, 0, -UNIT_VECTOR_ONE}}) {
		testing.expect(t, plan_planet_veins(TEST_PLANET_SEED, home * 1000, radius) == plan_planet_veins(TEST_PLANET_SEED, home, radius))
	}
	diagonal, _ := normalize_fixed({1, 2, 3})
	unit := plan_planet_veins(TEST_PLANET_SEED, diagonal, radius)
	scaled := plan_planet_veins(TEST_PLANET_SEED, diagonal * 1000, radius)
	for index in 0 ..< unit.count {
		// The two normalisations may round a unit apart.
		testing.expectf(t, vector_length(unit.veins[index].centre - scaled.veins[index].centre) <= 16, "vein %d: %v against %v", index, unit.veins[index].centre, scaled.veins[index].centre)
		testing.expect_value(t, unit.veins[index].radius, scaled.veins[index].radius)
	}
	testing.expect(t, plan_planet_veins(TEST_PLANET_SEED, {}, radius) == plan_planet_veins(TEST_PLANET_SEED, FRAME_NORTH, radius))
	testing.expect_value(t, planet_home_direction({}), [3]i64{UNIT_VECTOR_ONE, 0, 0})
}

@(test)
test_a_home_of_latitude_0_longitude_0_is_a_home :: proc(t: ^testing.T) {
	planet := make_test_planet()
	planet.home = {}
	planet.crater = default_planet(shipped_test_planets()).crater
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	home := fixed_scale([3]i64{UNIT_VECTOR_ONE, 0, 0}, generation.radius)
	testing.expect_value(t, generation.crater.home, home)
	testing.expect(t, generation.veins.count > 0, "the home has starter veins")
	for vein in generation.veins.veins[:generation.veins.count] {
		testing.expectf(t, vector_length(vein.centre - home) <= metres_to_position_units(PLANET_VEIN_MAXIMUM_DISTANCE_METRES), "the vein at %v rings +x", vein.centre)
	}
	surface, _ := field_home_site(generation, planet)
	direction, _ := normalize_fixed(cast([3]i64)(surface))
	testing.expectf(t, direction.x > UNIT_VECTOR_ONE * 9999 / 10000, "the site %v lies along +x", surface)
}
