package game

import "core:testing"

// The field player against a machine's collision volumes (work item
// 0230): a body on a 500 mm frame on the flat test site, its volumes in
// the model's frame, the player walking, sliding and aiming at it at the
// shipped tuning.

TEST_BODY_FOOTPRINT :: [3]i32{12, 8, 12}
TEST_BODY_OCCUPANT :: Occupant_Handle(1 << 56 | 1)

// A frame at 500 mm on the flat test site, the footprint's cells centred
// on cell (0, 0, 0) (pod_origin's rule) held by a test occupant with
// Shaped, and the body registered with rotation 0.
place_test_body :: proc(frames: ^Frame_Table, definitions: []Collision_Volume_Definition, footprint: [3]i32) -> (frame: Frame, body: Frame_Body) {
	origin, axes := free_frame_at(test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	frame, _ = find_frame(frames, add_frame(frames, origin, axes, 500))
	corner := World_Coordinate{-(footprint.x - 1) / 2, 0, -(footprint.z - 1) / 2}
	occupant := Occupant{handle = TEST_BODY_OCCUPANT, flags = {.Solid, .Blocks_Water, .Shaped}}
	for cell in footprint_cells(corner, footprint, 0) {
		occupy_frame_cell(frames, frame.id, cell, occupant)
	}
	body = make_frame_body(frame, occupant, corner, footprint, 0, resolve_collision_volumes(definitions, context.temp_allocator))
	register_frame_body(frames, body)
	return frame, body
}

// A point of the model's frame (position units at the frame's pitch) in
// the world, and back.
test_body_world_point :: proc(body: Frame_Body, model: [3]i64) -> World_Position {
	return body.frame.origin + World_Position(frame_world_direction(body.frame, body.centre + model))
}

test_body_model_point :: proc(body: Frame_Body, position: World_Position) -> [3]i64 {
	return body_point_from_frame(body, frame_local_position(body.frame, position))
}

// From the model's y axis, across it.
test_body_radius :: proc(body: Frame_Body, position: World_Position) -> i64 {
	model := test_body_model_point(body, position)
	return vector_length({model.x, 0, model.z})
}

test_cone_definitions :: proc(radius_top_cells, height_cells: f64) -> []Collision_Volume_Definition {
	definitions := make([]Collision_Volume_Definition, 1, context.temp_allocator)
	definitions[0] = {kind = "round", axis = "y", from = {0, 0, 0}, to = {0, height_cells, 0}, radius_from = 5, radius_to = radius_top_cells}
	return definitions
}

test_box_definitions :: proc(from, to: [3]f64) -> []Collision_Volume_Definition {
	definitions := make([]Collision_Volume_Definition, 1, context.temp_allocator)
	definitions[0] = {kind = "box", from = from, to = to}
	return definitions
}

TEST_BODY_CELL :: 2048
// A quarter metre over the floor, where the walks start and settle.
TEST_BODY_DROP :: POSITION_UNITS_PER_METRE / 4

// A player at a model point looking along a model direction.
make_test_body_player :: proc(body: Frame_Body, model: [3]i64, look: [3]i64) -> Field_Player {
	return make_field_player(test_body_world_point(body, model), frame_world_direction(body.frame, look))
}

// The walk's displacement in a tick.
test_walk_per_tick :: proc(tuning: Field_Player_Tuning) -> i64 {
	return tuning.walk_speed / VELOCITY_FRACTION_ONE
}

// The deepest a capsule sphere reaches into the bodies, as a distance.
test_nearest_body :: proc(frames: ^Frame_Table, tuning: Field_Player_Tuning, player: Field_Player) -> i64 {
	nearest := max(i64)
	for index in 0 ..< field_capsule_sphere_count(tuning) {
		centre := field_capsule_centre(tuning, player.position, player.up, index)
		nearest = min(nearest, frame_body_probe(frames, centre, field_frame_probe_reach(tuning)).distance)
	}
	return nearest
}

@(test)
test_a_steep_cone_volume_stops_a_walk_and_slides_a_player_off :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		frames: Frame_Table
		defer destroy_frame_table(&frames)
		_, body := place_test_body(&frames, test_cone_definitions(2, 6), TEST_BODY_FOOTPRINT)
		tuning := test_field_tuning(spacing, shipped_field_player_config())
		base := i64(5 * TEST_BODY_CELL)
		player := make_test_body_player(body, {base + metres_to_position_units(2), TEST_BODY_DROP, 0}, {-UNIT_VECTOR_ONE, 0, 0})
		run_field_player_on_frames(&world, &frames, tuning, &player, {}, 20)
		for tick in 0 ..< 180 {
			tick_field_player(&world, &frames, tuning, &player, FIELD_WALK_FORWARD)
			nearest := test_nearest_body(&frames, tuning, player)
			testing.expectf(t, nearest >= tuning.capsule_radius - FIELD_PENETRATION_TOLERANCE, "%d mm tick %d: a sphere is %d from the cone", spacing, tick, nearest)
			testing.expectf(t, abs(site_height(player.position)) <= FIELD_GROUND_TOLERANCE, "%d mm tick %d: the feet at %d", spacing, tick, site_height(player.position))
		}
		radius := test_body_radius(body, player.position)
		testing.expectf(t, radius >= base && radius <= base + tuning.capsule_radius + test_walk_per_tick(tuning), "%d mm: the walk ended at radius %d", spacing, radius)
		slider := make_test_body_player(body, {7 * TEST_BODY_CELL / 2, metres_to_position_units(3), 0}, {-UNIT_VECTOR_ONE, 0, 0})
		run_field_player_on_frames(&world, &frames, tuning, &slider, {}, 180)
		testing.expectf(t, test_body_radius(body, slider.position) > base, "%d mm: the slide ended at radius %d", spacing, test_body_radius(body, slider.position))
		testing.expectf(t, slider.on_ground && abs(site_height(slider.position)) <= FIELD_GROUND_TOLERANCE, "%d mm: the slide ended at height %d", spacing, site_height(slider.position))
	}
}

@(test)
test_a_gentle_cone_volume_is_walked_up :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		frames: Frame_Table
		defer destroy_frame_table(&frames)
		_, body := place_test_body(&frames, test_cone_definitions(1, 2), TEST_BODY_FOOTPRINT)
		tuning := test_field_tuning(spacing, shipped_field_player_config())
		player := make_test_body_player(body, {5 * TEST_BODY_CELL + metres_to_position_units(2), TEST_BODY_DROP, 0}, {-UNIT_VECTOR_ONE, 0, 0})
		run_field_player_on_frames(&world, &frames, tuning, &player, {}, 20)
		highest := i64(0)
		for _ in 0 ..< 180 {
			tick_field_player(&world, &frames, tuning, &player, FIELD_WALK_FORWARD)
			highest = max(highest, site_height(player.position))
		}
		testing.expectf(t, highest >= 3 * TEST_BODY_CELL / 2, "%d mm: the walk rose only %d", spacing, highest)
	}
}

@(test)
test_the_empty_corner_of_a_footprint_with_a_cone_volume_is_free :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		frames: Frame_Table
		defer destroy_frame_table(&frames)
		frame, _ := place_test_body(&frames, test_cone_definitions(2, 6), TEST_BODY_FOOTPRINT)
		tuning := test_field_tuning(spacing, shipped_field_player_config())
		corner := frame_cell_centre(frame, {-5, 0, -5})
		start := corner - World_Position(fixed_scale(frame.axes[FRAME_UP], TEST_BODY_CELL / 2 - TEST_BODY_DROP))
		player := make_field_player(start, frame.axes[FRAME_RIGHT])
		testing.expect_value(t, world_to_frame_cell(frame, player.position), World_Coordinate{-5, 0, -5})
		run_field_player_on_frames(&world, &frames, tuning, &player, {}, 20)
		wanted := fixed_scale(frame.axes[FRAME_RIGHT], test_walk_per_tick(tuning))
		for tick in 0 ..< 60 {
			before := player.position
			tick_field_player(&world, &frames, tuning, &player, FIELD_WALK_FORWARD)
			testing.expectf(t, !field_walk_impeded(before, player.position, wanted), "%d mm tick %d: the walk was impeded", spacing, tick)
			testing.expectf(t, !field_capsule_overlaps(&world, &frames, tuning, player.position, player.up), "%d mm tick %d: the capsule overlaps", spacing, tick)
		}
		// The same footprint as plain solid cells holds the corner.
		cells: Frame_Table
		defer destroy_frame_table(&cells)
		plain_frame, _ := find_frame(&cells, add_frame(&cells, frame.origin, frame.axes, 500))
		for cell in footprint_cells({-5, 0, -5}, TEST_BODY_FOOTPRINT, 0) {
			occupy_frame_cell(&cells, plain_frame.id, cell, {handle = TEST_BODY_OCCUPANT, flags = {.Solid, .Blocks_Water}})
		}
		testing.expectf(t, field_capsule_overlaps(&world, &cells, tuning, start, player.up), "%d mm: the solid corner cell does not hold the capsule", spacing)
	}
}

@(test)
test_a_capsule_inside_a_shell_is_held_by_its_inner_surface :: proc(t: ^testing.T) {
	definitions := []Collision_Volume_Definition{{kind = "round", axis = "y", from = {0, 0, 0}, to = {0, 8, 0}, radius_from = 5, radius_to = 5, shell = 0.4}}
	for spacing in TEST_FIELD_SPACINGS {
		for look in ([2][3]i64{{UNIT_VECTOR_ONE, 0, 0}, {0, 0, -UNIT_VECTOR_ONE}}) {
			world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
			defer destroy_field_world(&world)
			frames: Frame_Table
			defer destroy_frame_table(&frames)
			_, body := place_test_body(&frames, definitions, TEST_BODY_FOOTPRINT)
			tuning := test_field_tuning(spacing, shipped_field_player_config())
			inner := body.volumes[0].radius_from - body.volumes[0].shell
			player := make_test_body_player(body, {0, TEST_BODY_DROP, 0}, look)
			run_field_player_on_frames(&world, &frames, tuning, &player, {}, 20)
			farthest := i64(0)
			for _ in 0 ..< 240 {
				tick_field_player(&world, &frames, tuning, &player, FIELD_WALK_FORWARD)
				farthest = max(farthest, test_body_radius(body, player.position))
			}
			radius := test_body_radius(body, player.position)
			lowest := inner - tuning.capsule_radius - test_walk_per_tick(tuning)
			highest := inner - tuning.capsule_radius + FIELD_PENETRATION_TOLERANCE
			testing.expectf(t, radius >= lowest && farthest <= highest, "%d mm towards %v: radius %d, at most %d, the band %d to %d", spacing, look, radius, farthest, lowest, highest)
			testing.expectf(t, player.on_ground, "%d mm towards %v: not on the ground", spacing, look)
		}
	}
}

@(test)
test_a_box_volume_stops_the_capsule_on_each_face_and_is_stepped_onto_when_low :: proc(t: ^testing.T) {
	sides := [4][3]i64{{UNIT_VECTOR_ONE, 0, 0}, {-UNIT_VECTOR_ONE, 0, 0}, {0, 0, UNIT_VECTOR_ONE}, {0, 0, -UNIT_VECTOR_ONE}}
	for spacing in TEST_FIELD_SPACINGS {
		tuning := test_field_tuning(spacing, shipped_field_player_config())
		for side in sides {
			world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
			defer destroy_field_world(&world)
			frames: Frame_Table
			defer destroy_frame_table(&frames)
			_, body := place_test_body(&frames, test_box_definitions({-1, 0, -1}, {1, 4, 1}), TEST_BODY_FOOTPRINT)
			out := TEST_BODY_CELL + metres_to_position_units(2)
			player := make_test_body_player(body, {side.x / UNIT_VECTOR_ONE * out, TEST_BODY_DROP, side.z / UNIT_VECTOR_ONE * out}, -side)
			run_field_player_on_frames(&world, &frames, tuning, &player, {}, 20)
			run_field_player_on_frames(&world, &frames, tuning, &player, FIELD_WALK_FORWARD, 90)
			model := test_body_model_point(body, player.position)
			along := (model.x * side.x + model.z * side.z) / UNIT_VECTOR_ONE
			testing.expectf(t, abs(along - (TEST_BODY_CELL + tuning.capsule_radius)) <= FIELD_GROUND_TOLERANCE, "%d mm from %v: the feet stop %d out", spacing, side, along)
			testing.expectf(t, abs(site_height(player.position)) <= FIELD_GROUND_TOLERANCE, "%d mm from %v: the feet at %d", spacing, side, site_height(player.position))
		}
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		frames: Frame_Table
		defer destroy_frame_table(&frames)
		// 4 by 4 cells: at 1000 mm the step onto a sharp edge is the
		// ledge's, whose stride overshoots a top only 1 m across.
		height := f64(tuning.step_height / 2) / TEST_BODY_CELL
		_, body := place_test_body(&frames, test_box_definitions({-2, 0, -2}, {2, height, 2}), TEST_BODY_FOOTPRINT)
		player := make_test_body_player(body, {2 * TEST_BODY_CELL + metres_to_position_units(2), TEST_BODY_DROP, 0}, {-UNIT_VECTOR_ONE, 0, 0})
		run_field_player_on_frames(&world, &frames, tuning, &player, {}, 20)
		// Walk until the feet pass the top's middle, then stand.
		for _ in 0 ..< 120 {
			if test_body_model_point(body, player.position).x <= 0 {
				break
			}
			tick_field_player(&world, &frames, tuning, &player, FIELD_WALK_FORWARD)
		}
		run_field_player_on_frames(&world, &frames, tuning, &player, {}, 30)
		top := body.volumes[0].to.y
		testing.expectf(t, player.on_ground && abs(site_height(player.position) - top) <= FIELD_GROUND_TOLERANCE, "%d mm: the feet at %d, the top at %d", spacing, site_height(player.position), top)
	}
}

@(test)
test_the_aiming_ray_stops_at_a_volume_and_passes_the_empty_corner :: proc(t: ^testing.T) {
	frames: Frame_Table
	defer destroy_frame_table(&frames)
	frame, body := place_test_body(&frames, test_cone_definitions(2, 6), TEST_BODY_FOOTPRINT)
	eye := i64(6553)
	out := metres_to_position_units(3)
	origin := test_body_world_point(body, {out, eye, 0})
	towards := frame_world_direction(frame, {-UNIT_VECTOR_ONE, 0, 0})
	hit, normal := raycast_frames_and_bodies(&frames, origin, towards, metres_to_position_units(6))
	// The cone's radius at the eye's height: 5 cells less half the height.
	surface := 5 * TEST_BODY_CELL - eye / 2
	testing.expectf(t, hit.hit && abs(hit.distance - (out - surface)) <= 2, "the ray hit %v at %d, the surface at %d", hit.hit, hit.distance, out - surface)
	testing.expect_value(t, hit.occupant.handle, TEST_BODY_OCCUPANT)
	testing.expectf(t, fixed_dot(normal, frame.axes[FRAME_UP]) > 0 && fixed_dot(normal, -towards) > 0, "the normal %v", normal)
	corner := frame_cell_centre(frame, {-7, 0, -5})
	along := frame.axes[FRAME_RIGHT]
	beside, _ := raycast_frames_and_bodies(&frames, corner, along, metres_to_position_units(4))
	testing.expectf(t, !beside.hit, "the ray across the corner hit %v", beside.cell)
	cells := raycast_frames(&frames, corner, along, metres_to_position_units(4))
	testing.expectf(t, cells.hit && cells.cell == World_Coordinate{-5, 0, -5}, "the cells' ray hit %v", cells.cell)
}

@(test)
test_a_machine_without_volumes_collides_by_its_cells :: proc(t: ^testing.T) {
	frames: Frame_Table
	defer destroy_frame_table(&frames)
	origin, axes := free_frame_at(test_site_point(0, 0, 0), {UNIT_VECTOR_ONE, 0, 0}, 500)
	frame, _ := find_frame(&frames, add_frame(&frames, origin, axes, 500))
	for cell in footprint_cells({0, 0, 0}, {2, 2, 2}, 0) {
		occupy_frame_cell(&frames, frame.id, cell, {handle = TEST_BODY_OCCUPANT, flags = {.Solid}})
	}
	reach := metres_to_position_units(1)
	points := [5]World_Coordinate{{-1, 0, 0}, {2, 1, 1}, {0, 2, 0}, {1, 1, -1}, {0, 0, 0}}
	for cell in points {
		position := frame_cell_centre(frame, cell)
		cells, _ := frame_solid_probe(&frames, position, reach)
		testing.expect_value(t, frame_probe(&frames, position, reach), cells)
	}
	start := frame_cell_centre(frame, {-3, 1, 1})
	direction := frame.axes[FRAME_RIGHT]
	hit, normal := raycast_frames_and_bodies(&frames, start, direction, reach * 4, {.Solid})
	expected := raycast_frames(&frames, start, direction, reach * 4, {.Solid})
	testing.expect_value(t, hit, expected)
	offset := direction_offsets[expected.face]
	testing.expect_value(t, normal, frame_world_direction(frame, {i64(offset.x) * UNIT_VECTOR_ONE, i64(offset.y) * UNIT_VECTOR_ONE, i64(offset.z) * UNIT_VECTOR_ONE}))
}

run_field_player_on_frames :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, input: Field_Player_Input, ticks: int) {
	for _ in 0 ..< ticks {
		tick_field_player(world, frames, tuning, player, input)
	}
}

// The steep contact rule of the step (0230) keeps a lip of the step
// height walkable at crouch speed, where the edge meets the bottom sphere
// steepest, at every spacing: a sharp box volume 8 cells deep whose face
// the player crouch walks into.
@(test)
test_a_lip_of_the_step_height_is_stepped_onto_at_crouch_speed :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		frames: Frame_Table
		defer destroy_frame_table(&frames)
		tuning := test_field_tuning(spacing, shipped_field_player_config())
		height := f64(tuning.step_height) / TEST_BODY_CELL
		_, body := place_test_body(&frames, test_box_definitions({-6, 0, -6}, {2, height, 6}), TEST_BODY_FOOTPRINT)
		player := make_test_body_player(body, {2 * TEST_BODY_CELL + metres_to_position_units(2), TEST_BODY_DROP, 0}, {-UNIT_VECTOR_ONE, 0, 0})
		run_field_player_on_frames(&world, &frames, tuning, &player, {}, 20)
		crouch := Field_Player_Input{move = {0, FIELD_MOVE_ONE}, held = {.Sneak}}
		// Until the feet are a cell past the face, 3 m at most.
		for _ in 0 ..< 180 {
			if test_body_model_point(body, player.position).x <= 0 {
				break
			}
			tick_field_player(&world, &frames, tuning, &player, crouch)
		}
		top := body.volumes[0].to.y
		model := test_body_model_point(body, player.position)
		testing.expectf(t, player.on_ground && abs(site_height(player.position) - top) <= FIELD_GROUND_TOLERANCE, "%d mm: the feet at %d (x %d), the lip's top at %d", spacing, site_height(player.position), model.x, top)
	}
}
