package game

import "core:testing"

// Test terrains of the field player, written straight into a Field_World
// as the density of a signed distance: a small sphere planet round the
// origin, and flat ground, a slope, a ledge, a dug hole or a ridge at a
// site TEST_SITE_RADIUS_METRES out along +y, where the up is +y within a
// tenth of a degree.

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
	Hole,
	Ridge,
}

Test_Terrain :: struct {
	kind:          Test_Terrain_Kind,
	// Slope: rising along +x.
	slope_degrees: int,
	// Ledge, Hole (its depth) and Ridge: in position units.
	ledge_height:  i64,
	// Hole: a square pit round the site, this far to each side. Ridge: a
	// wall along z centred TEST_LEDGE_FACE_METRES along x, this far to
	// each side.
	half_width:    i64,
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
	case .Hole:
		pit := min(y + terrain.ledge_height, terrain.half_width - abs(x), terrain.half_width - abs(position.z))
		return min(-y, -pit)
	case .Ridge:
		across := abs(x - metres_to_position_units(TEST_LEDGE_FACE_METRES))
		return max(-y, min(terrain.ledge_height - y, terrain.half_width - across))
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

// Along x turned towards +z by degrees.
test_heading :: proc(degrees: int) -> [3]i64 {
	angle := degrees_to_angle_units(degrees)
	return {fixed_cosine(angle), 0, fixed_sine(angle)}
}

// Walks 70 ticks along +x (or turned towards +z) from 2 m before a ledge
// of height (position units), holding Jump when asked, then stands for a
// second (a jump lasts about that); reports whether the player ended on
// the top past the face.
walk_at_test_ledge :: proc(height: i64, spacing_millimetres: int, jump: bool, config := Field_Player_Config{}, heading_degrees := 0) -> bool {
	world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = height}, spacing_millimetres)
	defer destroy_field_world(&world)
	tuning := test_field_tuning(spacing_millimetres, config)
	player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), test_heading(heading_degrees))
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

// The field player saves its foundation block indices (0193); a player
// written before them reads them as 0, the first of each list.
Field_Player_Before_Foundation_Blocks :: struct {
	yaw:                i32,
	placement_rotation: u8,
}

@(test)
test_the_field_player_saves_its_foundation_block :: proc(t: ^testing.T) {
	player := make_field_player(FAR_FEET, {UNIT_VECTOR_ONE, 0, 0})
	player.foundation_size_index, player.foundation_height_index = 3, 2
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, &player)
	read: Field_Player
	reader := Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, read.foundation_size_index, 3)
	testing.expect_value(t, read.foundation_height_index, 2)
	old := Field_Player_Before_Foundation_Blocks{yaw = 5, placement_rotation = 1}
	clear(&bytes)
	write_value_of(&bytes, &old)
	read = {}
	reader = Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, read.yaw, 5)
	testing.expect_value(t, read.foundation_size_index, 0)
	testing.expect_value(t, read.foundation_height_index, 0)
}

// The footprint's ground heights at the feet and a radius of 1229 units
// ahead, behind, right and left.
test_footprint :: proc(centre, ahead, behind, right, left: i64) -> Field_Footprint {
	radius: i64 = 1229
	return Field_Footprint {
		offsets = {{0, 0}, {radius, 0}, {-radius, 0}, {0, radius}, {0, -radius}},
		heights = {centre, ahead, behind, right, left},
	}
}

// Flat ground faces the up, a slope rising one in two along the first
// axis tilts back by its angle, and a bump under the feet only (the
// points round it flat) faces the up.
@(test)
test_the_footprint_plane_averages_a_bump_away :: proc(t: ^testing.T) {
	testing.expect_value(t, footprint_plane_normal(test_footprint(0, 0, 0, 0, 0)), [3]i64{0, UNIT_VECTOR_ONE, 0})
	half := i64(1229 / 2)
	slope := footprint_plane_normal(test_footprint(0, half, -half, 0, 0))
	expected, _ := normalize_fixed({-1 * UNIT_VECTOR_ONE, 2 * UNIT_VECTOR_ONE, 0})
	testing.expectf(t, vector_length(slope - expected) <= UNIT_VECTOR_ONE / 1000, "a one in two slope's normal %v, expected %v", slope, expected)
	sideways := footprint_plane_normal(test_footprint(0, 0, 0, half, -half))
	testing.expectf(t, sideways.x == 0 && sideways.z < 0, "a slope rising along the second axis tilts along it: %v", sideways)
	testing.expect_value(t, footprint_plane_normal(test_footprint(2000, 0, 0, 0, 0)), [3]i64{0, UNIT_VECTOR_ONE, 0})
}

// Walking 60 ticks from 2 m before a decimetre wall, head on and at 45
// degrees: no tick goes less than seven eighths of the full walk along the
// heading, and the player ends on top past the face.
@(test)
test_a_decimetre_wall_is_walked_over_without_slowing :: proc(t: ^testing.T) {
	height := millimetres_to_position_units(100)
	for spacing in TEST_FIELD_SPACINGS {
		tuning := test_field_tuning(spacing)
		full := tuning.walk_speed / VELOCITY_FRACTION_ONE
		for degrees in ([2]int{0, 45}) {
			world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = height}, spacing)
			defer destroy_field_world(&world)
			heading := test_heading(degrees)
			player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), heading)
			run_field_player(&world, tuning, &player, {}, 20)
			slowest := full
			for _ in 0 ..< 60 {
				before := player.position
				tick_field_player(&world, nil, tuning, &player, FIELD_WALK_FORWARD)
				slowest = min(slowest, fixed_dot(cast([3]i64)(player.position - before), heading))
			}
			testing.expectf(t, 8 * slowest >= 7 * full, "%d mm at %d degrees: a tick went %d of %d", spacing, degrees, slowest, full)
			testing.expectf(t, abs(site_height(player.position) - height) <= tenth_sample(spacing), "%d mm at %d degrees: the feet end at %d", spacing, degrees, site_height(player.position))
			testing.expectf(t, player.position.x > metres_to_position_units(TEST_LEDGE_FACE_METRES), "%d mm at %d degrees: the face was not passed", spacing, degrees)
		}
	}
}

// A wall a sample above the step stops a walk at 45 degrees too, and is
// mantled with Jump where it lies below the 1.5 m mantle height.
@(test)
test_a_wall_above_the_step_stops_a_slanted_walk :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		tuning := test_field_tuning(spacing)
		height := tuning.step_height + sample_axis_to_position(1, spacing)
		testing.expectf(t, !walk_at_test_ledge(height, spacing, false, heading_degrees = 45), "%d mm: the walk at 45 degrees climbed the wall", spacing)
		if height <= tuning.mantle_height {
			testing.expectf(t, walk_at_test_ledge(height, spacing, true, heading_degrees = 45), "%d mm: the wall was not mantled at 45 degrees", spacing)
		}
	}
}

// A ridge half a sample high and a sample wide, its blurred sides
// steeper than a 20 degree walkable angle, under a capsule of radius three
// quarters of a sample, so the footprint's points lie on the flat ground
// round the ridge's steep sides: the walk goes over it and on past it. By
// the feet's plane alone it held the player at the ridge's foot.
@(test)
test_a_steep_bump_narrower_than_the_footprint_is_walked_over :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		config := test_field_player_config()
		config.walkable_angle_degrees = 20
		config.capsule_radius_millimetres = 3 * spacing / 4
		tuning := test_field_tuning(spacing, config)
		sample := sample_axis_to_position(1, spacing)
		world := make_test_field(Test_Terrain{kind = .Ridge, ledge_height = sample / 2, half_width = sample / 2}, spacing)
		defer destroy_field_world(&world)
		player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), {UNIT_VECTOR_ONE, 0, 0})
		run_field_player(&world, tuning, &player, {}, 20)
		steepest := i64(UNIT_VECTOR_ONE)
		for _ in 0 ..< 80 {
			tick_field_player(&world, nil, tuning, &player, FIELD_WALK_FORWARD)
			ground := probe_field_ground(&world, nil, tuning, player.position, player.up, {}, true)
			if ground.on {
				steepest = min(steepest, ground.cosine)
			}
		}
		testing.expectf(t, steepest < tuning.walkable_cosine, "%d mm: the feet never stood on ground past the angle (cosine %d)", spacing, steepest)
		past := metres_to_position_units(TEST_LEDGE_FACE_METRES) + tuning.capsule_radius + sample
		testing.expectf(t, player.position.x > past, "%d mm: the walk ended at %d, short of %d past the ridge", spacing, player.position.x, past)
		testing.expectf(t, abs(site_height(player.position)) <= tenth_sample(spacing), "%d mm: the feet end at %d", spacing, site_height(player.position))
	}
}

// Standing in a dug pit three quarters of the step deep, the player walks
// out over its lip onto the ground round it, along x and at 45 degrees.
@(test)
test_a_player_walks_out_of_a_hole_lower_than_the_step :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		tuning := test_field_tuning(spacing)
		half_width := metres_to_position_units(3) / 2
		depth := tuning.step_height * 3 / 4
		for degrees in ([2]int{0, 45}) {
			world := make_test_field(Test_Terrain{kind = .Hole, ledge_height = depth, half_width = half_width}, spacing)
			defer destroy_field_world(&world)
			player := make_field_player(test_site_point(0, 0, 0), test_heading(degrees))
			run_field_player(&world, tuning, &player, {}, 30)
			testing.expectf(t, site_height(player.position) < -depth / 2, "%d mm at %d degrees: the player stands at %d, not in the pit", spacing, degrees, site_height(player.position))
			run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, 90)
			testing.expectf(t, player.position.x > half_width, "%d mm at %d degrees: the walk ended at %d, inside the pit", spacing, degrees, player.position.x)
			testing.expectf(t, abs(site_height(player.position)) <= tenth_sample(spacing), "%d mm at %d degrees: the feet end at %d", spacing, degrees, site_height(player.position))
		}
	}
}

// The shipped data's field player (data/game.sjson): the test tuning with
// the 60 degree walkable angle the user plays at.
shipped_field_player_config :: proc() -> Field_Player_Config {
	config := test_field_player_config()
	config.walkable_angle_degrees = 60
	return config
}

// At the shipped tuning, holding forward into a 4 m wall for a second
// keeps the feet within a tenth of a sample of the floor and short of
// the face: neither the settle nor the step lifts the player up the
// wall's blurred foot.
@(test)
test_walking_into_a_wall_stays_on_the_floor_at_the_shipped_angle :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		for degrees in ([2]int{0, 45}) {
			world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = metres_to_position_units(4)}, spacing)
			defer destroy_field_world(&world)
			tuning := test_field_tuning(spacing, shipped_field_player_config())
			player := make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0), test_heading(degrees))
			run_field_player(&world, tuning, &player, {}, 20)
			run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, 40)
			highest: i64 = 0
			for _ in 0 ..< 60 {
				tick_field_player(&world, nil, tuning, &player, FIELD_WALK_FORWARD)
				highest = max(highest, abs(site_height(player.position)))
			}
			testing.expectf(t, highest <= tenth_sample(spacing), "%d mm at %d degrees: the feet rose to %d", spacing, degrees, highest)
			testing.expectf(t, player.position.x < metres_to_position_units(TEST_LEDGE_FACE_METRES), "%d mm at %d degrees: the wall was passed", spacing, degrees)
		}
	}
}

// At the shipped tuning, on top of a 2 m cliff (above the mantle height)
// 1 m back from its edge: walking towards the edge, head on and at 45
// degrees, the player leaves it and lands below within three seconds;
// standing still at the edge of the top's walkable ground the player
// stays on top.
@(test)
test_a_walk_off_a_cliff_falls_at_the_shipped_angle :: proc(t: ^testing.T) {
	height := metres_to_position_units(2)
	face := metres_to_position_units(TEST_LEDGE_FACE_METRES)
	for spacing in ([2]int{500, 1000}) {
		tuning := test_field_tuning(spacing, shipped_field_player_config())
		for degrees in ([2]int{180, 135}) {
			world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = height}, spacing)
			defer destroy_field_world(&world)
			player := make_field_player(test_site_point(face + POSITION_UNITS_PER_METRE, height + POSITION_UNITS_PER_METRE / 4, 0), test_heading(degrees))
			run_field_player(&world, tuning, &player, {}, 20)
			testing.expectf(t, abs(site_height(player.position) - height) <= tenth_sample(spacing), "%d mm: the start stands at %d", spacing, site_height(player.position))
			run_field_player(&world, tuning, &player, FIELD_WALK_FORWARD, 180)
			testing.expectf(t, player.position.x < face, "%d mm at %d degrees: the walk stayed on the cliff at %d", spacing, degrees, player.position.x)
			testing.expectf(t, player.on_ground && abs(site_height(player.position)) <= tenth_sample(spacing), "%d mm at %d degrees: the feet end at %d, not on the ground below", spacing, degrees, site_height(player.position))
		}
		world := make_test_field(Test_Terrain{kind = .Ledge, ledge_height = height}, spacing)
		defer destroy_field_world(&world)
		player := make_field_player(test_site_point(face + POSITION_UNITS_PER_METRE, height + POSITION_UNITS_PER_METRE / 4, 0), test_heading(180))
		run_field_player(&world, tuning, &player, {}, 20)
		// Sneak to the edge: the last tick whose feet stand on the top's
		// walkable ground (past it the feet's own plane is the blurred
		// lip, and a capsule balanced there slides off).
		sneak := FIELD_WALK_FORWARD
		sneak.held = {.Sneak}
		for _ in 0 ..< 240 {
			next := player
			tick_field_player(&world, nil, tuning, &next, sneak)
			under := probe_field_ground(&world, nil, tuning, next.position, next.up, {}, true)
			if !under.walkable || site_height(next.position) < height - tenth_sample(spacing) {
				break
			}
			player = next
		}
		testing.expectf(t, player.position.x < face + tuning.capsule_radius + sample_axis_to_position(1, spacing), "%d mm: the sneak stopped at %d, short of the edge", spacing, player.position.x)
		run_field_player(&world, tuning, &player, {}, 120)
		testing.expectf(t, player.on_ground && abs(site_height(player.position) - height) <= tenth_sample(spacing), "%d mm: standing at the edge the feet end at %d", spacing, site_height(player.position))
	}
}
