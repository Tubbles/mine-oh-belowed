package game

import "core:testing"

// Work item 0176: runs between poles and belt ends.

TEST_RUN_METRE :: i64(POSITION_UNITS_PER_METRE)
TEST_RUN_PITCH :: 500
TEST_RUN_AXES :: [3][3]i64{{UNIT_VECTOR_ONE, 0, 0}, {0, UNIT_VECTOR_ONE, 0}, {0, 0, UNIT_VECTOR_ONE}}

data_belt_run_constraints :: proc() -> Belt_Run_Constraints {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	return make_belt_run_constraints(config.belt_runs)
}

// A frame with the world's axes whose cell (0, 0, 0) has the middle of its
// bottom at bottom.
add_test_run_frame :: proc(entities: ^Entities, bottom: World_Position) -> Frame_Id {
	half := millimetres_to_position_units(TEST_RUN_PITCH) / 2
	return add_frame(&entities.frames, bottom - {half, 0, half}, TEST_RUN_AXES, TEST_RUN_PITCH)
}

// A pole on a frame of its own, facing the rotation (0 is +x, 1 is +z).
add_test_pole :: proc(entities: ^Entities, machines: Machine_Registry, bottom: World_Position, rotation: u8) -> Entity_Handle {
	frame := add_test_run_frame(entities, bottom)
	return add_entity(entities, machines, find_machine_of_kind(machines, .Belt_Pole), {}, rotation, frame)
}

pole_bottom :: proc(entities: ^Entities, pole: Entity_Handle) -> World_Position {
	entry := pool_get(&entities.belt_poles, pole)
	frame, _ := find_frame(&entities.frames, entry.frame)
	return frame_cell_bottom(frame, entry.origin)
}

add_test_run :: proc(entities: ^Entities, machines: Machine_Registry, first, second: Entity_Handle) -> (run: Entity_Handle, refusal: Belt_Run_Refusal) {
	chord := cast([3]i64)(pole_bottom(entities, second) - pole_bottom(entities, first))
	start, _ := belt_pole_endpoint(entities, first, chord, .Belt, BELT_RUN_START)
	end, _ := belt_pole_endpoint(entities, second, chord, .Belt, BELT_RUN_END)
	return add_belt_run(entities, machines, data_belt_run_constraints(), .Belt, find_belt_machine(machines, .Flat), {start, end})
}

@(test)
test_a_run_between_poles_ten_metres_apart_is_straight :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	first := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	second := add_test_pole(&entities, machines, {10 * TEST_RUN_METRE, 0, 0}, 0)
	run, refusal := add_test_run(&entities, machines, first, second)
	testing.expect_value(t, refusal, Belt_Run_Refusal.None)
	curve := pool_get(&entities.belt_runs, run).curve
	testing.expectf(t, abs(curve.arc_length - 10 * TEST_RUN_METRE) <= TEST_RUN_METRE / 100, "arc length %d units", curve.arc_length)
	for point in curve.polyline {
		testing.expect_value(t, point.y, curve.polyline[0].y)
		testing.expect_value(t, point.z, i64(0))
	}
	testing.expect_value(t, curve.length_units, i32(10 * BELT_UNITS_PER_BLOCK * MILLIMETRES_PER_METRE / TEST_RUN_PITCH))
}

// From facing +x to facing +z five metres on and five across: a quarter
// circle of five metres, its arc the sum of the polyline's segments.
@(test)
test_a_run_with_facings_at_right_angles_is_a_quarter_turn :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	radius := 5 * TEST_RUN_METRE
	first := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	second := add_test_pole(&entities, machines, {radius, 0, radius}, 1)
	run, refusal := add_test_run(&entities, machines, first, second)
	testing.expect_value(t, refusal, Belt_Run_Refusal.None)
	curve := pool_get(&entities.belt_runs, run).curve
	segments: i64
	for step in 0 ..< BELT_RUN_SUBDIVISIONS {
		segments += vector_length(cast([3]i64)(curve.polyline[step + 1] - curve.polyline[step]))
	}
	testing.expectf(t, abs(segments - curve.arc_length) <= BELT_RUN_SUBDIVISIONS, "segments %d against arc %d", segments, curve.arc_length)
	quarter := radius * 314159 / 200000
	testing.expectf(t, abs(curve.arc_length - quarter) <= quarter / 200, "arc %d against the quarter circle's %d", curve.arc_length, quarter)
	centre := World_Position{0, curve.polyline[0].y, radius}
	for point in curve.polyline {
		distance := vector_length(cast([3]i64)(point - centre))
		testing.expectf(t, abs(distance - radius) <= radius / 100, "%v lies %d from the centre", point, distance)
	}
}

// Two metres up and a quarter turn at once is refused; two metres up
// straight on and the turn on the level are each allowed.
@(test)
test_a_run_that_inclines_and_turns_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	first := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	climbing_turn := add_test_pole(&entities, machines, {5 * TEST_RUN_METRE, 2 * TEST_RUN_METRE, 5 * TEST_RUN_METRE}, 1)
	_, refusal := add_test_run(&entities, machines, first, climbing_turn)
	testing.expect_value(t, refusal, Belt_Run_Refusal.Inclines_And_Turns)
	climbing := add_test_pole(&entities, machines, {10 * TEST_RUN_METRE, 2 * TEST_RUN_METRE, 0}, 0)
	_, climbing_refusal := add_test_run(&entities, machines, first, climbing)
	testing.expect_value(t, climbing_refusal, Belt_Run_Refusal.None)
	foot := add_test_pole(&entities, machines, {0, 0, 10 * TEST_RUN_METRE}, 0)
	steep := add_test_pole(&entities, machines, {2 * TEST_RUN_METRE, 2 * TEST_RUN_METRE, 10 * TEST_RUN_METRE}, 0)
	_, steep_refusal := add_test_run(&entities, machines, foot, steep)
	testing.expect_value(t, steep_refusal, Belt_Run_Refusal.Too_Steep)
	testing.expect_value(t, pool_alive_count(entities.belt_runs), 1)
}

@(test)
test_a_run_over_the_maximum_span_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	first := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	far := add_test_pole(&entities, machines, {31 * TEST_RUN_METRE, 0, 0}, 0)
	_, refusal := add_test_run(&entities, machines, first, far)
	testing.expect_value(t, refusal, Belt_Run_Refusal.Too_Long)
	near := add_test_pole(&entities, machines, {29 * TEST_RUN_METRE, 0, 0}, 0)
	_, near_refusal := add_test_run(&entities, machines, first, near)
	testing.expect_value(t, near_refusal, Belt_Run_Refusal.None)
	// The pole has its leaving run now.
	_, taken := add_test_run(&entities, machines, first, far)
	testing.expect_value(t, taken, Belt_Run_Refusal.Endpoint_Taken)
}

// Three belts on frame 1, a run from the last one's end over 8.5 m to the
// first of three belts on frame 2: one line, the run a segment of 8.5 m
// at the 500 mm pitch. Four items a spacing apart keep it inside the run
// and arrive at the dead end a spacing apart.
@(test)
test_items_keep_their_spacing_across_a_run :: proc(t: ^testing.T) {
	machines := make_test_machines()
	items := make_test_items()
	entities: Entities
	defer destroy_entities(&entities)
	belt := find_belt_machine(machines, .Flat)
	first_frame := add_test_run_frame(&entities, {0, 0, 0})
	second_frame := add_test_run_frame(&entities, {10 * TEST_RUN_METRE, 0, 0})
	for x in i32(0) ..< 3 {
		add_belt(&entities, machines, belt, {x, 0, 0}, 0, .Flat, first_frame)
		add_belt(&entities, machines, belt, {x, 0, 0}, 0, .Flat, second_frame)
	}
	start := Belt_Run_Endpoint{frame = first_frame, cell = {2, 0, 0}}
	end := Belt_Run_Endpoint{frame = second_frame, cell = {0, 0, 0}}
	run, refusal := add_belt_run(&entities, machines, data_belt_run_constraints(), .Belt, belt, {start, end})
	testing.expect_value(t, refusal, Belt_Run_Refusal.None)
	run_length := pool_get(&entities.belt_runs, run).curve.length_units
	testing.expect_value(t, run_length, i32(17 * BELT_UNITS_PER_BLOCK))
	testing.expect_value(t, len(entities.belt_network.lines), 1)
	line := &entities.belt_network.lines[0]
	testing.expect_value(t, len(line.belts), 7)
	testing.expect_value(t, belt_line_length(line^), 6 * BELT_UNITS_PER_BLOCK + run_length)
	plate := test_item(items, "iron_plate")
	for index in i32(0) ..< 4 {
		testing.expect(t, lane_insert(&line.lanes[.Left], plate, BELT_END_MARGIN + index * BELT_ITEM_SPACING))
	}
	run_start := i32(3 * BELT_UNITS_PER_BLOCK)
	inside := false
	for _ in 0 ..< 2000 {
		tick_belt_network(&entities.belt_network, 60)
		lane := entities.belt_network.lines[0].lanes[.Left][:]
		if lane[0].position >= run_start && lane[3].position < run_start + run_length {
			inside = true
			expect_item_gaps(t, lane, BELT_ITEM_SPACING)
		}
	}
	testing.expect(t, inside, "the items crossed the run together")
	lane := entities.belt_network.lines[0].lanes[.Left][:]
	expect_item_gaps(t, lane, BELT_ITEM_SPACING)
	testing.expect_value(t, lane[3].position, belt_line_length(entities.belt_network.lines[0]) - BELT_END_MARGIN)
}

expect_item_gaps :: proc(t: ^testing.T, lane: []Lane_Item, gap: i32) {
	for index in 1 ..< len(lane) {
		testing.expect_value(t, lane[index].position - lane[index - 1].position, gap)
	}
}

// Free poles on an 8 km planet, built twice: the same control points,
// polyline and arc length, so every machine of a session agrees.
@(test)
test_two_instances_compute_the_same_arc_length :: proc(t: ^testing.T) {
	machines := make_test_machines()
	curves: [2]Belt_Run
	for &curve in curves {
		entities: Entities
		defer destroy_entities(&entities)
		pole := find_machine_of_kind(machines, .Belt_Pole)
		start_hit := World_Position{0, 8000 * TEST_RUN_METRE, 0}
		end_hit := World_Position{3 * TEST_RUN_METRE, 32_767_960, 12 * TEST_RUN_METRE}
		chord := cast([3]i64)(end_hit - start_hit)
		first, _ := place_free_belt_pole(&entities, machines, pole, start_hit, chord, TEST_RUN_PITCH)
		second, _ := place_free_belt_pole(&entities, machines, pole, end_hit, chord, TEST_RUN_PITCH)
		run, refusal := add_test_run(&entities, machines, first, second)
		testing.expect_value(t, refusal, Belt_Run_Refusal.None)
		curve = pool_get(&entities.belt_runs, run)^
	}
	testing.expect(t, curves[0].control_points == curves[1].control_points)
	testing.expect(t, curves[0].curve == curves[1].curve)
	testing.expect(t, curves[0].curve.arc_length > 12 * TEST_RUN_METRE)
}

@(test)
test_the_assist_picks_the_endpoint_nearest_the_reticle :: proc(t: ^testing.T) {
	metre := TEST_RUN_METRE
	options := []Belt_Run_Option {
		{point = {5 * metre, metre / 2, 0}},
		{point = {3 * metre, metre / 5, 0}},
		{point = {-2 * metre, 0, 0}},
		{point = {20 * metre, 0, 0}},
		{point = {4 * metre, 2 * metre, 0}},
	}
	look := [3]i64{UNIT_VECTOR_ONE, 0, 0}
	testing.expect_value(t, nearest_belt_run_option(options, {}, look, 10 * metre, metre), 1)
	// Behind the eye, out of reach or off the ray by more than the radius:
	// none.
	testing.expect_value(t, nearest_belt_run_option(options[2:], {}, look, 10 * metre, metre), -1)
	testing.expect_value(t, nearest_belt_run_option(options, {}, look, 10 * metre, metre / 10), -1)
}

// A world without poles or runs writes no run tables.
@(test)
test_a_world_without_runs_writes_no_run_tables :: proc(t: ^testing.T) {
	entities: Entities
	defer destroy_entities(&entities)
	bytes := make([dynamic]byte, context.temp_allocator)
	write_belt_run_tables(&bytes, &entities)
	testing.expect_value(t, len(bytes), 0)
}

// The field: with the belt run tool held, Place on the ground picks a new
// pole's spot, Back forgets it, Place again picks it, and Place on a spot
// a quarter turn round lays both poles and the run through the queue,
// taking two pole items.
@(test)
test_the_field_lays_a_run_through_the_queue :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation_pitch_millimetres = TEST_RUN_PITCH
	content.field.belt_pole = find_machine_of_kind(content.machines, .Belt_Pole)
	content.field.run_belt = find_belt_machine(content.machines, .Flat)
	content.field.belt_runs = data_belt_run_constraints()
	simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"belt_pole", 2})
	player := &simulation.players[0]
	player.field.pitch = degrees_to_angle_units(-45)
	player.field.tool = .Belt_Run
	place := [1]Field_Player_Input{{held = {.Place}, just_pressed = {.Place}}}
	back := [1]Field_Player_Input{{just_pressed = {.Back}}}
	tick_field_simulation(&simulation, content, place[:])
	testing.expect(t, player.field.run_started)
	testing.expect_value(t, player.field.run_start.kind, Belt_Run_Candidate_Kind.Free_Pole)
	tick_field_simulation(&simulation, content, back[:])
	testing.expect(t, !player.field.run_started)
	tick_field_simulation(&simulation, content, place[:])
	testing.expect(t, player.field.run_started)
	player.field.yaw += ANGLE_UNITS_PER_QUARTER
	tick_field_simulation(&simulation, content, place[:])
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect(t, !player.field.run_started)
	testing.expect_value(t, pool_alive_count(simulation.world.entities.belt_poles), 2)
	testing.expect_value(t, pool_alive_count(simulation.world.entities.belt_runs), 1)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "belt_pole")), 0)
	testing.expect_value(t, len(simulation.field.placements), 0)
	// No poles left: a run needing a new pole is refused Nothing_Held.
	tick_field_simulation(&simulation, content, place[:])
	player.field.yaw += ANGLE_UNITS_PER_QUARTER
	tick_field_simulation(&simulation, content, place[:])
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Nothing_Held)
	testing.expect_value(t, pool_alive_count(simulation.world.entities.belt_runs), 1)
}

// Four metres up over eight on: the chord climbs 50 percent, under the
// 70 percent limit, but with both ends level the belt is steepest in the
// middle, over the limit there.
@(test)
test_a_run_steeper_in_the_middle_than_the_limit_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	first := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	second := add_test_pole(&entities, machines, {8 * TEST_RUN_METRE, 4 * TEST_RUN_METRE, 0}, 0)
	constraints := data_belt_run_constraints()
	chord := cast([3]i64)(pole_bottom(&entities, second) - pole_bottom(&entities, first))
	testing.expect(t, !direction_too_steep(chord, {0, UNIT_VECTOR_ONE, 0}, constraints.maximum_slope_percent))
	_, refusal := add_test_run(&entities, machines, first, second)
	testing.expect_value(t, refusal, Belt_Run_Refusal.Too_Steep)
}

TEST_RUN_TILTED_COSINE :: 16_736_348
TEST_RUN_TILTED_SINE :: 1_170_319

// A pole facing +x on a frame tilted four degrees about z.
add_tilted_test_pole :: proc(entities: ^Entities, machines: Machine_Registry, bottom: World_Position) -> Entity_Handle {
	axes := [3][3]i64{{TEST_RUN_TILTED_COSINE, TEST_RUN_TILTED_SINE, 0}, {-TEST_RUN_TILTED_SINE, TEST_RUN_TILTED_COSINE, 0}, {0, 0, UNIT_VECTOR_ONE}}
	half := millimetres_to_position_units(TEST_RUN_PITCH) / 2
	origin := bottom - World_Position(fixed_scale(axes[FRAME_RIGHT], half)) - World_Position(fixed_scale(axes[FRAME_FORWARD], half))
	frame := add_frame(&entities.frames, origin, axes, TEST_RUN_PITCH)
	return add_entity(entities, machines, find_machine_of_kind(machines, .Belt_Pole), {}, 0, frame)
}

// A level quarter turn from a frame tilted four degrees to a level one:
// across the tilted up alone the chord rises over the level tolerance and
// the turn would be refused one way and allowed the other. Across the
// mean up both ways agree.
@(test)
test_a_run_and_its_reverse_are_judged_alike :: proc(t: ^testing.T) {
	machines := make_test_machines()
	refusals: [2]Belt_Run_Refusal
	for &refusal, reverse in refusals {
		entities: Entities
		defer destroy_entities(&entities)
		tilted := add_tilted_test_pole(&entities, machines, {0, 0, 0})
		level := add_test_pole(&entities, machines, {5 * TEST_RUN_METRE, 0, 5 * TEST_RUN_METRE}, 1)
		ends := reverse == 0 ? [2]Entity_Handle{tilted, level} : [2]Entity_Handle{level, tilted}
		_, refusal = add_test_run(&entities, machines, ends[0], ends[1])
	}
	testing.expect_value(t, refusals[0], Belt_Run_Refusal.None)
	testing.expect_value(t, refusals[1], Belt_Run_Refusal.None)
}

// A to P, then P on to B back on A's side would turn the items round on
// P: refused. P on to C beyond it continues: allowed. A run arriving at P
// from beyond C is refused too, P's leaving run fixing its facing.
@(test)
test_a_chain_of_runs_never_reverses_at_a_pole :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	a := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	p := add_test_pole(&entities, machines, {10 * TEST_RUN_METRE, 0, 0}, 0)
	b := add_test_pole(&entities, machines, {2 * TEST_RUN_METRE, 0, 3 * TEST_RUN_METRE}, 0)
	c := add_test_pole(&entities, machines, {20 * TEST_RUN_METRE, 0, 0}, 0)
	_, first := add_test_run(&entities, machines, a, p)
	testing.expect_value(t, first, Belt_Run_Refusal.None)
	_, back := add_test_run(&entities, machines, p, b)
	testing.expect_value(t, back, Belt_Run_Refusal.Reverses_At_Pole)
	_, on := add_test_run(&entities, machines, p, c)
	testing.expect_value(t, on, Belt_Run_Refusal.None)
	remove_belt_runs_on_pole(&entities, machines, a)
	beyond := add_test_pole(&entities, machines, {25 * TEST_RUN_METRE, 0, 2 * TEST_RUN_METRE}, 0)
	_, arriving := add_test_run(&entities, machines, beyond, p)
	testing.expect_value(t, arriving, Belt_Run_Refusal.Reverses_At_Pole)
	testing.expect_value(t, pool_alive_count(entities.belt_runs), 1)
}

// Three belts in a row: the middle one is fed by the first and feeds the
// last, so a run may neither end nor start at it.
@(test)
test_a_run_never_takes_a_belt_end_already_linked :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	belt := find_belt_machine(machines, .Flat)
	frame := add_test_run_frame(&entities, {0, 0, 0})
	for x in i32(0) ..< 3 {
		add_belt(&entities, machines, belt, {x, 0, 0}, 0, .Flat, frame)
	}
	middle := Belt_Run_Endpoint{frame = frame, cell = {1, 0, 0}}
	before := add_test_pole(&entities, machines, {-10 * TEST_RUN_METRE, 0, 0}, 0)
	after := add_test_pole(&entities, machines, {10 * TEST_RUN_METRE, 0, 0}, 0)
	chord := [3]i64{TEST_RUN_METRE, 0, 0}
	start, _ := belt_pole_endpoint(&entities, before, chord, .Belt, BELT_RUN_START)
	end, _ := belt_pole_endpoint(&entities, after, chord, .Belt, BELT_RUN_END)
	constraints := data_belt_run_constraints()
	_, fed := add_belt_run(&entities, machines, constraints, .Belt, belt, {start, middle})
	testing.expect_value(t, fed, Belt_Run_Refusal.Belt_Already_Fed)
	_, taken := add_belt_run(&entities, machines, constraints, .Belt, belt, {middle, end})
	testing.expect_value(t, taken, Belt_Run_Refusal.Belt_Output_Taken)
	testing.expect_value(t, pool_alive_count(entities.belt_runs), 0)
}

@(test)
test_a_run_from_a_pole_to_itself_is_too_short :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	pole := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	_, refusal := add_test_run(&entities, machines, pole, pole)
	testing.expect_value(t, refusal, Belt_Run_Refusal.Too_Short)
}

// Two belt ends five metres apart on the level, the first facing +x and
// the second -x: a half turn, over the 90 degree limit.
@(test)
test_a_level_run_turning_too_far_is_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	belt := find_belt_machine(machines, .Flat)
	first_frame := add_test_run_frame(&entities, {0, 0, 0})
	second_frame := add_test_run_frame(&entities, {0, 0, 5 * TEST_RUN_METRE})
	add_belt(&entities, machines, belt, {}, 0, .Flat, first_frame)
	add_belt(&entities, machines, belt, {}, 2, .Flat, second_frame)
	start := Belt_Run_Endpoint{frame = first_frame}
	end := Belt_Run_Endpoint{frame = second_frame, facing = 2}
	_, refusal := add_belt_run(&entities, machines, data_belt_run_constraints(), .Belt, belt, {start, end})
	testing.expect_value(t, refusal, Belt_Run_Refusal.Turns_Too_Far)
}

// Removing the middle pole of a chain removes both its runs and its
// frame; the outer poles stay.
@(test)
test_removing_a_pole_removes_its_runs_and_frame :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	a := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	p := add_test_pole(&entities, machines, {10 * TEST_RUN_METRE, 0, 0}, 0)
	c := add_test_pole(&entities, machines, {20 * TEST_RUN_METRE, 0, 0}, 0)
	add_test_run(&entities, machines, a, p)
	add_test_run(&entities, machines, p, c)
	testing.expect_value(t, pool_alive_count(entities.belt_runs), 2)
	frame := pool_get(&entities.belt_poles, p).frame
	frames := len(entities.frames.frames)
	testing.expect(t, remove_entity(&entities, machines, p))
	testing.expect_value(t, pool_alive_count(entities.belt_runs), 0)
	testing.expect_value(t, pool_alive_count(entities.belt_poles), 2)
	testing.expect_value(t, len(entities.frames.frames), frames - 1)
	_, still := find_frame(&entities.frames, frame)
	testing.expect(t, !still)
	testing.expect(t, frame not_in entities.frames.extents)
}

// The drain's undo: the poles a refused run placed are taken away with
// the frames they brought, leaving no frame record behind.
@(test)
test_undoing_planned_poles_leaves_no_frame :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation_pitch_millimetres = TEST_RUN_PITCH
	content.field.belt_pole = find_machine_of_kind(content.machines, .Belt_Pole)
	content.field.belt_runs = data_belt_run_constraints()
	entities: Entities
	defer destroy_entities(&entities)
	frames := len(entities.frames.frames)
	run := Field_Run_Placement {
		kind       = .Belt,
		candidates = {{kind = .Free_Pole, hit = {0, 8000 * TEST_RUN_METRE, 0}}, {kind = .Free_Pole, hit = {10 * TEST_RUN_METRE, 8000 * TEST_RUN_METRE, 0}}},
	}
	plan, found := plan_belt_run(&entities, content, run.kind, run.candidates)
	testing.expect(t, found)
	_, placed := place_planned_poles(&entities, content, run, plan)
	testing.expect_value(t, pool_alive_count(entities.belt_poles), 2)
	testing.expect_value(t, len(entities.frames.frames), frames + 2)
	remove_planned_poles(&entities, content.machines, placed)
	testing.expect_value(t, pool_alive_count(entities.belt_poles), 0)
	testing.expect_value(t, len(entities.frames.frames), frames)
	testing.expect_value(t, len(entities.frames.extents), 0)
	testing.expect_value(t, len(entities.frames.occupants), 0)
}

// Two players confirm runs to the same pole in one tick: the first in the
// queue lays its run, the second is refused Endpoint_Taken.
@(test)
test_two_players_running_to_one_pole_in_a_tick :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation_pitch_millimetres = TEST_RUN_PITCH
	content.field.belt_pole = find_machine_of_kind(content.machines, .Belt_Pole)
	content.field.run_belt = find_belt_machine(content.machines, .Flat)
	content.field.belt_runs = data_belt_run_constraints()
	simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0))
	add_test_miner(&simulation, items, test_site_point(2, 0, 0))
	entities := &simulation.world.entities
	first := add_test_pole(entities, content.machines, {0, 0, 0}, 0)
	second := add_test_pole(entities, content.machines, {0, 0, 6 * TEST_RUN_METRE}, 0)
	shared := add_test_pole(entities, content.machines, {10 * TEST_RUN_METRE, 0, 3 * TEST_RUN_METRE}, 0)
	for start, player in ([2]Entity_Handle{first, second}) {
		candidates: [2]Belt_Run_Candidate
		for pole, role in ([2]Entity_Handle{start, shared}) {
			entry := pool_get(&entities.belt_poles, pole)
			candidates[role] = {kind = .Existing, endpoint = {pole = pole, frame = entry.frame, cell = entry.origin}}
		}
		placement := Field_Placement{kind = .Run, run = {kind = .Belt, machine = content.field.run_belt, candidates = candidates}}
		append(&simulation.field.placements, Queued_Field_Placement{player = player, placement = placement})
	}
	drain_field_placements(&simulation, content)
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, simulation.players[1].field_refusal, Field_Edit_Refusal.Run_Refused)
	testing.expect_value(t, simulation.players[1].field_run_refusal, Belt_Run_Refusal.Endpoint_Taken)
	testing.expect_value(t, pool_alive_count(entities.belt_runs), 1)
}

// A fixed quarter turn's arc length against the constant it gave when
// written: a machine whose integer path differs shows here.
TEST_RUN_QUARTER_TURN_ARC_LENGTH :: i64(32171)

@(test)
test_a_fixed_run_has_a_fixed_arc_length :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	first := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	second := add_test_pole(&entities, machines, {5 * TEST_RUN_METRE, 0, 5 * TEST_RUN_METRE}, 1)
	run, _ := add_test_run(&entities, machines, first, second)
	testing.expect_value(t, pool_get(&entities.belt_runs, run).curve.arc_length, TEST_RUN_QUARTER_TURN_ARC_LENGTH)
}
