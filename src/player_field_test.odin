package game

import "core:testing"

// Test terrains of the field player, written straight into a Field_World
// as the density of a signed distance: a small sphere planet round the
// origin, and flat ground, a slope or a ledge at a site TEST_SITE_RADIUS_METRES
// out along +y, where the up is +y within a tenth of a degree.

TEST_SITE_RADIUS_METRES :: 8000
TEST_SMALL_PLANET_RADIUS_METRES :: 64
// The ledge's face lies this far along +x from the site.
TEST_LEDGE_FACE_METRES :: 2
TEST_TICK_RATE_FIELD :: 60

Test_Terrain_Kind :: enum {
	Flat,
	Slope,
	Ledge,
	Sphere,
}

Test_Terrain :: struct {
	kind:          Test_Terrain_Kind,
	// Slope: rising along +x.
	slope_degrees: int,
	// Ledge: in position units.
	ledge_height:  i64,
}

test_field_player_config :: proc() -> Field_Player_Config {
	return Field_Player_Config {
		capsule_radius_millimetres = 300,
		capsule_height_millimetres = 1800,
		eye_height_millimetres = 1600,
		walkable_angle_degrees = 40,
		slide_speed_millimetres_per_second = 6000,
		step_height_samples = 1,
		jump_height_millimetres = 1100,
		mantle_height_millimetres = 1500,
		tool_reach_millimetres = 4000,
		walk_speed_millimetres_per_second = 4300,
		sprint_speed_millimetres_per_second = 5600,
		sneak_speed_millimetres_per_second = 1300,
		fall_speed_limit_millimetres_per_second = 50000,
		fly_speed_millimetres_per_second = 12000,
		fly_sprint_speed_millimetres_per_second = 36000,
	}
}

test_field_tuning :: proc(spacing_millimetres: int, config := Field_Player_Config{}) -> Field_Player_Tuning {
	chosen := config == {} ? test_field_player_config() : config
	return make_field_player_tuning(chosen, make_test_planet(), spacing_millimetres, TEST_TICK_RATE_FIELD)
}

// The three sample spacings of the world setting.
TEST_FIELD_SPACINGS :: SAMPLE_SPACING_CHOICES_MILLIMETRES

test_site_point :: proc(x, y, z: i64) -> World_Position {
	return {x, metres_to_position_units(TEST_SITE_RADIUS_METRES) + y, z}
}

// Inside the quadrant x >= 0, y < 0 positive, the distance to it outside.
quadrant_depth :: proc(x, y: i64) -> i64 {
	switch {
	case x >= 0 && y <= 0:
		return min(x, -y)
	case x < 0 && y > 0:
		return -i64(integer_square_root(u64(x * x + y * y)))
	case x < 0:
		return x
	}
	return -y
}

// The signed distance into the ground, in position units.
test_terrain_depth :: proc(terrain: Test_Terrain, position: World_Position) -> i64 {
	if terrain.kind == .Sphere {
		return metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES) - vector_length(cast([3]i64)(position))
	}
	x := position.x
	y := position.y - metres_to_position_units(TEST_SITE_RADIUS_METRES)
	switch terrain.kind {
	case .Slope:
		angle := degrees_to_angle_units(terrain.slope_degrees)
		return (fixed_sine(angle) * x - fixed_cosine(angle) * y) / UNIT_VECTOR_ONE
	case .Ledge:
		return max(-y, quadrant_depth(x - metres_to_position_units(TEST_LEDGE_FACE_METRES), y - terrain.ledge_height))
	case .Flat, .Sphere:
	}
	return -y
}

fill_test_chunk :: proc(world: ^Field_World, terrain: Test_Terrain, spacing_millimetres: int, coordinate: Field_Chunk_Coordinate) {
	chunk := new(Field_Chunk)
	chunk.coordinate = coordinate
	origin := field_chunk_origin(coordinate)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		position := sample_to_world_position(origin + Sample_Coordinate(field_index_to_local(index)), spacing_millimetres)
		density := depth_to_density(test_terrain_depth(terrain, position), spacing_millimetres)
		field_chunk_set_sample(chunk, index, {density, density > 0 ? .Stone : .Air, 0})
	}
	field_world_insert_chunk(world, chunk)
}

// Whether the chunk's box comes within 8 m of the small planet's surface.
chunk_near_test_sphere :: proc(coordinate: Field_Chunk_Coordinate, spacing_millimetres: int) -> bool {
	width := sample_axis_to_position(FIELD_CHUNK_SIZE, spacing_millimetres)
	nearest, farthest: i64
	for axis in 0 ..< 3 {
		low := i64(coordinate[axis]) * width
		high := low + width
		near := low <= 0 && high >= 0 ? 0 : min(abs(low), abs(high))
		far := max(abs(low), abs(high))
		nearest += near * near
		farthest += far * far
	}
	shell := metres_to_position_units(8)
	radius := metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES)
	return nearest <= (radius + shell) * (radius + shell) && farthest >= (radius - shell) * (radius - shell)
}

// The sphere fills the band of chunks round its equator (y chunks -1 and
// 0); a site terrain the 2 by 3 by 2 chunks round the site, from a chunk
// below its ground to one above.
make_test_field :: proc(terrain: Test_Terrain, spacing_millimetres: int) -> Field_World {
	world: Field_World
	if terrain.kind == .Sphere {
		reach := i32(ceiling_divide_i64(metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES + 8), sample_axis_to_position(FIELD_CHUNK_SIZE, spacing_millimetres)))
		for z in -reach ..< reach {
			for y in i32(-1) ..= 0 {
				for x in -reach ..< reach {
					if chunk_near_test_sphere({x, y, z}, spacing_millimetres) {
						fill_test_chunk(&world, terrain, spacing_millimetres, {x, y, z})
					}
				}
			}
		}
		return world
	}
	site := sample_to_field_chunk_coordinate(world_position_to_sample(test_site_point(0, 0, 0), spacing_millimetres))
	for z in i32(-1) ..= 0 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 0 {
				fill_test_chunk(&world, terrain, spacing_millimetres, {x, site.y + y, z})
			}
		}
	}
	return world
}

run_field_player :: proc(world: ^Field_World, tuning: Field_Player_Tuning, player: ^Field_Player, input: Field_Player_Input, ticks: int) {
	for _ in 0 ..< ticks {
		tick_field_player(world, nil, tuning, player, input)
	}
}

FIELD_WALK_FORWARD :: Field_Player_Input {
	move = {0, FIELD_MOVE_ONE},
}

// On the equator of the small planet, between +x and +z.
test_sphere_start :: proc(height: i64) -> World_Position {
	radius := metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES) + height
	return {radius * 3 / 5, 0, radius * 4 / 5}
}

// Height above the site's ground along +y.
site_height :: proc(position: World_Position) -> i64 {
	return position.y - metres_to_position_units(TEST_SITE_RADIUS_METRES)
}

@(test)
test_a_field_player_stands_on_the_sphere_with_a_radial_up :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Sphere}, 1000)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(1000)
	player := make_field_player(test_sphere_start(POSITION_UNITS_PER_METRE / 2), {0, UNIT_VECTOR_ONE, 0})
	run_field_player(&world, tuning, &player, {}, 60)
	testing.expect(t, player.on_ground)
	radius := vector_length(cast([3]i64)(player.position))
	surface := metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES)
	testing.expectf(t, abs(radius - surface) <= POSITION_UNITS_PER_METRE / 32, "feet %d from the centre, surface at %d", radius, surface)
	radial, _ := normalize_fixed(cast([3]i64)(player.position))
	testing.expect_value(t, player.up, radial)
	testing.expectf(t, abs(player.up.x - UNIT_VECTOR_ONE * 3 / 5) < UNIT_VECTOR_ONE / 4096 && abs(player.up.z - UNIT_VECTOR_ONE * 4 / 5) < UNIT_VECTOR_ONE / 4096, "up %v", player.up)
	testing.expect(t, fixed_dot(player.forward, player.up) == 0 || abs(fixed_dot(player.forward, player.up)) < 16)
}

// 2 pi r over the walk per tick, with pi as 355/113.
ticks_round_test_sphere :: proc(tuning: Field_Player_Tuning, fraction_numerator, fraction_denominator: i64) -> int {
	circumference := 2 * 355 * metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES) / 113
	return int(circumference * fraction_numerator * VELOCITY_FRACTION_ONE / (fraction_denominator * tuning.walk_speed))
}

@(test)
test_a_walk_round_the_small_planet_returns_to_the_start :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Sphere}, 1000)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(1000)
	start_feet := World_Position{metres_to_position_units(TEST_SMALL_PLANET_RADIUS_METRES) + POSITION_UNITS_PER_METRE / 4, 0, 0}
	player := make_field_player(start_feet, {0, 0, UNIT_VECTOR_ONE})
	run_field_player(&world, tuning, &player, {}, 30)
	start := player.position
	run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, ticks_round_test_sphere(tuning, 1, 2))
	opposite := vector_length(cast([3]i64)(player.position + start))
	testing.expectf(t, opposite <= POSITION_UNITS_PER_METRE, "half way round lies %d from the antipode", opposite)
	run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, ticks_round_test_sphere(tuning, 1, 2))
	miss := vector_length(cast([3]i64)(player.position - start))
	testing.expectf(t, miss <= sample_axis_to_position(1, 1000), "the walk round ended %d from its start", miss)
}

// A tenth of a sample, the tolerance of the spacing tests.
tenth_sample :: proc(spacing_millimetres: int) -> i64 {
	return sample_axis_to_position(1, spacing_millimetres) / 10
}

// Dropped from half a metre onto flat ground, the player stands on it
// within a tenth of a sample, on the ground and clear of the field.
@(test)
test_a_field_player_stands_on_flat_ground_at_every_spacing :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		tuning := test_field_tuning(spacing)
		player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 2, 0), {UNIT_VECTOR_ONE, 0, 0})
		run_field_player(&world, tuning, &player, {}, 60)
		testing.expectf(t, player.on_ground, "%d mm: not on the ground", spacing)
		testing.expectf(t, abs(site_height(player.position)) <= tenth_sample(spacing), "%d mm: feet at %d", spacing, site_height(player.position))
		testing.expectf(t, !field_capsule_overlaps(&world, nil, tuning, player.position, player.up), "%d mm: the capsule overlaps the ground", spacing)
	}
}

// Walking up +x for 40 ticks after landing: a 30 degree slope climbs, a
// 50 degree one slides the player below where the walk began.
@(test)
test_a_walkable_slope_is_climbed_and_a_steep_one_slides_back :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		tuning := test_field_tuning(spacing)
		for degrees in ([2]int{30, 50}) {
			world := make_test_field(Test_Terrain{kind = .Slope, slope_degrees = degrees}, spacing)
			defer destroy_field_world(&world)
			player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE, 0), {UNIT_VECTOR_ONE, 0, 0})
			run_field_player(&world, tuning, &player, {}, 20)
			before := site_height(player.position)
			run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, 40)
			climbed := site_height(player.position) - before
			if degrees == 30 {
				testing.expectf(t, climbed > POSITION_UNITS_PER_METRE, "%d mm: 30 degrees climbed only %d", spacing, climbed)
			} else {
				testing.expectf(t, climbed < 0, "%d mm: 50 degrees climbed %d", spacing, climbed)
			}
		}
	}
}

// Walks 70 ticks along +x from 2 m before a ledge of height (position
// units), holding Jump when asked, then stands for a second (a jump lasts
// about that); reports whether the player ended on the top past the face.
walk_at_test_ledge :: proc(height: i64, spacing_millimetres: int, jump: bool, config := Field_Player_Config{}) -> bool {
	world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = height}, spacing_millimetres)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(spacing_millimetres, config)
	player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), {UNIT_VECTOR_ONE, 0, 0})
	run_field_player(&world, tuning, &player, {}, 20)
	input := FIELD_WALK_FORWARD
	if jump {
		input.held = {.Jump}
	}
	run_field_player(&world, tuning, &player, input, 70)
	run_field_player(&world, tuning, &player, {}, 60)
	on_top := abs(site_height(player.position) - height) <= tenth_sample(spacing_millimetres)
	return on_top && player.position.x > metres_to_position_units(TEST_LEDGE_FACE_METRES)
}

// The test config without a mantle: only a jump climbs above the step.
config_without_mantle :: proc() -> Field_Player_Config {
	config := test_field_player_config()
	config.mantle_height_millimetres = 1
	return config
}

// At every spacing one sample is walked over and two stop a walk; a 1.5 m
// ledge is mantled and a 2 m one is not. Two samples are climbed by the
// jump itself (no mantle) where they lie below the 1.1 m jump.
@(test)
test_ledges_step_jump_and_mantle :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		sample := sample_axis_to_position(1, spacing)
		testing.expectf(t, walk_at_test_ledge(sample, spacing, false), "%d mm: a one sample ledge is walked over", spacing)
		testing.expectf(t, !walk_at_test_ledge(2 * sample, spacing, false), "%d mm: a two sample ledge stops a walk", spacing)
		testing.expectf(t, walk_at_test_ledge(millimetres_to_position_units(1500), spacing, true), "%d mm: a 1.5 m ledge is mantled", spacing)
		testing.expectf(t, !walk_at_test_ledge(millimetres_to_position_units(2000), spacing, true), "%d mm: a 2 m ledge is not mantled", spacing)
		if 2 * spacing <= 1000 {
			testing.expectf(t, !walk_at_test_ledge(2 * sample, spacing, false, config_without_mantle()), "%d mm: without the mantle a walk stays below", spacing)
			testing.expectf(t, walk_at_test_ledge(2 * sample, spacing, true, config_without_mantle()), "%d mm: a two sample ledge is jumped onto", spacing)
		}
	}
}

// At 1 m the step height (one sample) and the mantle height (1.5 m) are
// the thresholds: 1.0 m is stepped and 1.2 m not, 1.5 m is mantled and
// 1.6 m not.
@(test)
test_the_step_and_mantle_heights_are_thresholds :: proc(t: ^testing.T) {
	testing.expect(t, walk_at_test_ledge(millimetres_to_position_units(1000), 1000, false), "1.0 m is stepped")
	testing.expect(t, !walk_at_test_ledge(millimetres_to_position_units(1200), 1000, false), "1.2 m is not stepped")
	testing.expect(t, walk_at_test_ledge(millimetres_to_position_units(1500), 1000, true), "1.5 m is mantled")
	testing.expect(t, !walk_at_test_ledge(millimetres_to_position_units(1600), 1000, true), "1.6 m is not mantled")
}

// Holding forward into a 4 m wall for a second: on the ground every tick,
// the feet within a tenth of a sample of the floor and still, the capsule
// clear of the field; released, the player stands on the floor.
@(test)
test_walking_into_a_wall_stays_on_the_floor_and_clear :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = metres_to_position_units(4)}, spacing)
		defer destroy_field_world(&world)
		tuning := test_field_tuning(spacing)
		player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), {UNIT_VECTOR_ONE, 0, 0})
		run_field_player(&world, tuning, &player, {}, 20)
		run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, 40)
		for tick in 0 ..< 60 {
			before := site_height(player.position)
			tick_field_player(&world, nil, tuning, &player, FIELD_WALK_FORWARD)
			height := site_height(player.position)
			testing.expectf(t, player.on_ground, "%d mm tick %d: off the ground", spacing, tick)
			testing.expectf(t, abs(height) <= tenth_sample(spacing) && abs(height - before) <= FIELD_GROUND_TOLERANCE, "%d mm tick %d: feet at %d after %d", spacing, tick, height, before)
			testing.expectf(t, !field_capsule_overlaps(&world, nil, tuning, player.position, player.up), "%d mm tick %d: the capsule overlaps the wall", spacing, tick)
		}
		testing.expectf(t, player.position.x < metres_to_position_units(TEST_LEDGE_FACE_METRES), "%d mm: the wall was passed", spacing)
		run_field_player(&world, tuning, &player, {}, 30)
		testing.expectf(t, abs(site_height(player.position)) <= tenth_sample(spacing), "%d mm: released, the feet stand at %d", spacing, site_height(player.position))
	}
}

// A jump from flat ground rises the data's 1.1 m within a tenth of a
// sample and lands again.
@(test)
test_the_jump_rises_its_height :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(1000)
	player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), {UNIT_VECTOR_ONE, 0, 0})
	run_field_player(&world, tuning, &player, {}, 20)
	run_field_player(&world, tuning, &player, {held = {.Jump}}, 1)
	apex: i64 = 0
	for _ in 0 ..< 90 {
		tick_field_player(&world, nil, tuning, &player, {})
		apex = max(apex, site_height(player.position))
	}
	wanted := millimetres_to_position_units(test_field_player_config().jump_height_millimetres)
	testing.expectf(t, abs(apex - wanted) <= tenth_sample(1000), "the jump rose %d, wanted %d", apex, wanted)
	testing.expect(t, player.on_ground)
}

// Standing on flat ground and looking 45 degrees down, the target lies
// the eye height times the square root of two away.
@(test)
test_the_field_player_targets_the_ground_within_reach :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(1000)
	player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), {UNIT_VECTOR_ONE, 0, 0})
	run_field_player(&world, tuning, &player, {}, 20)
	run_field_player(&world, tuning, &player, {turn = {0, degrees_to_angle_units(-45)}}, 1)
	testing.expect(t, player.target.hit)
	expected := tuning.eye_height * UNIT_VECTOR_ONE / fixed_sine(degrees_to_angle_units(45))
	testing.expectf(t, abs(player.target.distance - expected) <= sample_axis_to_position(1, 1000), "target at %d, expected %d", player.target.distance, expected)
	testing.expect(t, player.target.normal.y > UNIT_VECTOR_ONE * 99 / 100)
}

// A double tap of Jump in developer mode flies; Jump then rises along the
// planet's up, not along +y.
@(test)
test_fly_mode_rises_along_the_planet_up :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Sphere}, 1000)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(1000)
	player := make_field_player(test_sphere_start(POSITION_UNITS_PER_METRE / 4), {0, UNIT_VECTOR_ONE, 0})
	run_field_player(&world, tuning, &player, {}, 30)
	tap := Field_Player_Input {
		held         = {.Jump},
		just_pressed = {.Jump},
		developer    = true,
	}
	run_field_player(&world, tuning, &player, tap, 1)
	run_field_player(&world, tuning, &player, {developer = true}, 2)
	run_field_player(&world, tuning, &player, tap, 1)
	testing.expect(t, player.flying)
	start := player.position
	up := player.up
	run_field_player(&world, tuning, &player, {held = {.Jump}, developer = true}, TEST_TICK_RATE_FIELD)
	moved := cast([3]i64)(player.position - start)
	along := fixed_dot(moved, up)
	across := vector_length(project_onto_plane(moved, up))
	testing.expectf(t, abs(along - metres_to_position_units(12)) <= POSITION_UNITS_PER_METRE / 16, "rose %d", along)
	testing.expectf(t, across <= POSITION_UNITS_PER_METRE / 64, "drifted %d across the up", across)
}

@(test)
test_the_field_player_config_is_bounded :: proc(t: ^testing.T) {
	testing.expect_value(t, field_player_problem(test_field_player_config()), "")
	testing.expect(t, field_player_problem({}) != "", "a missing field_player block is refused")
	short := test_field_player_config()
	short.capsule_height_millimetres = 2 * short.capsule_radius_millimetres
	testing.expect(t, field_player_problem(short) != "")
	steep := test_field_player_config()
	steep.walkable_angle_degrees = 90
	testing.expect(t, field_player_problem(steep) != "")
	no_jump := test_field_player_config()
	no_jump.jump_height_millimetres = 0
	testing.expect(t, field_player_problem(no_jump) != "", "a jump of nothing is refused")
	low_mantle := test_field_player_config()
	low_mantle.mantle_height_millimetres = 1000
	testing.expect(t, field_player_problem(low_mantle) != "", "a mantle not above the step at 1 m is refused")
	testing.expect_value(t, field_player_speed_problem(test_field_player_config(), 60), "")
	testing.expect(t, field_player_speed_problem(test_field_player_config(), 1) != "", "36 m/s flying is 36 m a tick at 1 Hz")
}
