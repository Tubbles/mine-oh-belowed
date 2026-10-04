package game

import "core:testing"

// The arrival (work item 0200): the hold, the landing, Skip in lockstep,
// the save and the join, and the presentation's distance from the hash.

ARRIVAL_TEST_TICKS :: 600

// The shipped game config's field values with the shipped arrival.
arrival_test_config :: proc() -> Game_Config {
	shipped, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	config := test_field_game_config()
	config.arrival_ticks = ARRIVAL_TEST_TICKS
	config.arrival_settle_ticks = shipped.arrival_settle_ticks
	config.arrival_flame_ticks = shipped.arrival_flame_ticks
	config.arrival_start_metres = shipped.arrival_start_metres
	config.arrival_angle_degrees = shipped.arrival_angle_degrees
	config.arrival_window_pitch_degrees = shipped.arrival_window_pitch_degrees
	return config
}

// The alive hatches in the foundations' pool order, in the temp allocator.
arrival_test_hatches :: proc(state: ^Simulation_State, machines: Machine_Registry) -> []Entity_Handle {
	hatches := make([dynamic]Entity_Handle, context.temp_allocator)
	for entry in state.world.entities.foundations.entries {
		if entry.alive && machines.machines[entry.machine].kind == .Hatch {
			append(&hatches, entry.handle)
		}
	}
	return hatches[:]
}

// Every hatch's open state is the expected one; false without hatches.
arrival_test_hatches_are :: proc(state: ^Simulation_State, machines: Machine_Registry, open: bool) -> bool {
	hatches := arrival_test_hatches(state, machines)
	for hatch in hatches {
		if hatch_is_open(&state.world.entities, hatch) != open {
			return false
		}
	}
	return len(hatches) > 0
}

// A walk, a jump, a turn and Interact.
ARRIVAL_TEST_RESTLESS :: Input_Frame {
	move         = {0, 1},
	look_delta   = {40, 0},
	pressed      = {.Move, .Jump, .Interact},
	just_pressed = {.Jump, .Interact},
}

// One tick of a session with each player's frame, the set staged first.
tick_arrival_test_session :: proc(session: ^Session, content: Simulation_Content, inputs: []Input_Frame) {
	if !simulated_chunks_ready(&session.simulation) {
		stage_generated_field_set(&session.simulation)
	}
	simulation_tick(&session.simulation, content, inputs)
}

// A new world's players cannot move for the fall; the hatches stay
// closed until its last tick and open at its end.
@(test)
test_a_new_world_holds_its_players_through_the_fall :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	restless := start_field_test_session(config, content)
	defer end_session(restless)
	still := start_field_test_session(config, content)
	defer end_session(still)
	restless_content := field_test_content(restless, content)
	still_content := field_test_content(still, content)
	testing.expect(t, field_arrival_falling(restless.simulation.field.arrival))
	for tick in 1 ..= ARRIVAL_TEST_TICKS {
		tick_field_test_simulation(&restless.simulation, restless_content, ARRIVAL_TEST_RESTLESS)
		tick_field_test_simulation(&still.simulation, still_content, {})
		if restless.simulation.players[0].field != still.simulation.players[0].field || lockstep_state_hash(&restless.simulation) != lockstep_state_hash(&still.simulation) {
			testing.expectf(t, false, "the sessions part at tick %d", tick)
			return
		}
		if tick == ARRIVAL_TEST_TICKS - 1 {
			testing.expect(t, arrival_test_hatches_are(&restless.simulation, restless_content.machines, false), "closed before the last tick")
			testing.expect_value(t, restless.simulation.field.arrival.landed_tick, 0)
		}
	}
	state := &restless.simulation
	testing.expect(t, arrival_test_hatches_are(state, restless_content.machines, true), "open after the last tick")
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	for hatch in arrival_test_hatches(state, restless_content.machines) {
		testing.expect_value(t, pool_get(&state.world.entities.foundations, hatch).hatch_toggle_tick, u64(ARRIVAL_TEST_TICKS + 1))
	}
	walk := Input_Frame{move = {0, 1}, pressed = {.Move}}
	for _ in 0 ..< 10 {
		tick_field_test_simulation(&restless.simulation, restless_content, walk)
		tick_field_test_simulation(&still.simulation, still_content, {})
	}
	testing.expect(t, restless.simulation.players[0].field.position != still.simulation.players[0].field.position, "the walk moves the player after the landing")
}

// arrival_ticks 0: no fall, the walk moves the player on the first tick,
// the hatches stay closed (0198).
@(test)
test_arrival_ticks_zero_starts_landed :: proc(t: ^testing.T) {
	config := arrival_test_config()
	config.arrival_ticks = 0
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	testing.expect(t, !field_arrival_falling(state.field.arrival))
	start := state.players[0].field.position
	tick_field_test_simulation(state, simulation_content, FIELD_PREDICTION_TEST_WALK)
	testing.expect(t, state.players[0].field.position != start, "the walk moves the player on tick 1")
	testing.expect(t, arrival_test_hatches_are(state, simulation_content.machines, false), "the hatches stay closed")
}

// A's record carries the command to B as the network would.
relay_arrival_test_records :: proc(from, to: ^Session) {
	for record in from.lockstep.outgoing {
		message := record_message(record)
		reader := Byte_Reader{data = message[1:]}
		decoded, ok := decode_input_record(&reader)
		assert(ok)
		receive_input_record(&to.lockstep, decoded, to.simulation.tick)
	}
}

// One frame of A: its queued commands held, one record stamped, relayed
// to B, and both run their ready ticks. The tick of a record carrying a
// command, 0 for none.
step_arrival_lockstep_test :: proc(first, second: ^Session, first_content, second_content: Simulation_Content) -> (command_tick: u64) {
	hold_local_commands(&first.lockstep, &first.simulation)
	stamp_local_record(&first.lockstep, first.simulation.tick, {})
	for record in first.lockstep.outgoing {
		if len(record.commands) > 0 {
			command_tick = record.tick
		}
	}
	relay_arrival_test_records(first, second)
	run_field_lockstep_test_ticks(first, first_content)
	run_field_lockstep_test_ticks(second, second_content)
	return
}

// Skip queued on A at tick 200 lands the fall on A and B at the tick its
// record was stamped for; a second Skip changes nothing.
@(test)
test_skip_ends_the_fall_on_two_sessions_at_the_same_tick :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	first := start_field_test_session(config, content)
	defer end_session(first)
	second := start_field_test_session(config, content)
	defer end_session(second)
	first_content := field_test_content(first, content)
	second_content := field_test_content(second, content)
	first.lockstep.window, second.lockstep.window = 2, 2
	landing: u64
	for first.simulation.tick < 400 {
		if first.simulation.tick == 200 && landing == 0 {
			queue_player_command(&first.simulation.player_commands, 0, Skip_Arrival_Command{})
		}
		if command_tick := step_arrival_lockstep_test(first, second, first_content, second_content); command_tick != 0 {
			landing = command_tick
		}
		testing.expect_value(t, first.simulation.tick, second.simulation.tick)
		if landing != 0 && (first.simulation.tick == landing || first.simulation.tick == landing + 10) {
			testing.expectf(t, lockstep_state_hash(&first.simulation) == lockstep_state_hash(&second.simulation), "the hashes part at tick %d", first.simulation.tick)
		}
	}
	testing.expect(t, landing > 200, "the Skip was stamped")
	for session in ([2]^Session{first, second}) {
		testing.expect_value(t, session.simulation.field.arrival.landed_tick, landing)
		testing.expect(t, arrival_test_hatches_are(&session.simulation, first_content.machines, true))
	}
	queue_player_command(&first.simulation.player_commands, 0, Skip_Arrival_Command{})
	for _ in 0 ..< 5 {
		step_arrival_lockstep_test(first, second, first_content, second_content)
	}
	testing.expect_value(t, first.simulation.field.arrival.landed_tick, landing)
	testing.expect_value(t, lockstep_state_hash(&first.simulation), lockstep_state_hash(&second.simulation))
}

// A new world of the arrival ticked count times with no input.
run_arrival_test_world :: proc(config: Game_Config, content: Game_Content, count: int) -> (session: ^Session, simulation_content: Simulation_Content) {
	session = start_field_test_session(config, content)
	simulation_content = field_test_content(session, content)
	for _ in 0 ..< count {
		tick_field_test_simulation(&session.simulation, simulation_content, {})
	}
	return
}

// The session's save loaded, its set staged and restored.
reload_arrival_test_world :: proc(config: Game_Config, content: Game_Content, session: ^Session, simulation_content: Simulation_Content) -> (loaded: ^Session, loaded_content: Simulation_Content) {
	files := encode_save_files(&session.simulation, simulation_content, "arrival", 0)
	loaded = load_test_field_save(config, content, &files)
	stage_generated_field_set(&loaded.simulation)
	restore_arrived_field_set(&loaded.simulation.field)
	return loaded, field_test_content(loaded, content)
}

// A save loaded at tick 1000 has no fall: landed, the hatches open, the
// walk moving the player at once, nothing to present.
@(test)
test_a_save_loaded_after_the_fall_has_no_fall :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, 1000)
	loaded, loaded_content := reload_arrival_test_world(config, content, session, simulation_content)
	end_session(session)
	defer end_session(loaded)
	state := &loaded.simulation
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	testing.expect(t, !field_arrival_falling(state.field.arrival))
	testing.expect(t, arrival_test_hatches_are(state, loaded_content.machines, true))
	start := state.players[0].field.position
	tick_field_test_simulation(state, loaded_content, FIELD_PREDICTION_TEST_WALK)
	testing.expect(t, state.players[0].field.position != start, "the walk moves the player")
	testing.expect_value(t, arrival_view(state.field.arrival, 1000, 0, config).phase, Arrival_Phase.None)
}

// A joiner at tick 1000 starts from the snapshot's files: a second player
// spawns in the cabin and walks on the next tick.
@(test)
test_a_joiner_after_the_fall_has_no_fall :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, 1000)
	joined, joined_content := reload_arrival_test_world(config, content, session, simulation_content)
	end_session(session)
	defer end_session(joined)
	state := &joined.simulation
	queue_player_command(&state.player_commands, 1, Add_Player_Command{})
	tick_arrival_test_session(joined, joined_content, {})
	testing.expect_value(t, len(state.players), 2)
	if len(state.players) < 2 {
		return
	}
	spawn, found := field_pod_spawn(&state.world.entities, joined_content.machines)
	testing.expect(t, found)
	testing.expect(t, vector_length(cast([3]i64)(state.players[1].field.position - spawn.position)) < millimetres_to_position_units(100), "the joiner spawns in the cabin")
	before := state.players[1].field.position
	heading := field_player_heading(state.players[1].field)
	inputs := [2]Input_Frame{{}, Input_Frame{move = {0, 1}, pressed = {.Move}}}
	tick_arrival_test_session(joined, joined_content, inputs[:])
	step := cast([3]i64)(state.players[1].field.position - before)
	testing.expect(t, step.x * heading.x + step.y * heading.y + step.z * heading.z > 0, "the joiner walks ahead on the next tick")
	testing.expect(t, !field_arrival_falling(state.field.arrival))
	testing.expect_value(t, arrival_view(state.field.arrival, state.tick, 0, config).phase, Arrival_Phase.None)
}

// A save taken at tick 300 resumes the fall and lands at tick 600, not
// before; one taken at tick 200 after a Skip at tick 101 loads landed.
@(test)
test_a_save_taken_during_the_fall_resumes_it :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, 300)
	loaded, loaded_content := reload_arrival_test_world(config, content, session, simulation_content)
	end_session(session)
	state := &loaded.simulation
	testing.expect_value(t, state.tick, u64(300))
	testing.expect_value(t, state.field.arrival.landed_tick, 0)
	for state.tick < ARRIVAL_TEST_TICKS - 1 {
		tick_field_test_simulation(state, loaded_content, {})
	}
	testing.expect(t, field_arrival_falling(state.field.arrival), "still falling at tick 599")
	tick_field_test_simulation(state, loaded_content, {})
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	testing.expect(t, arrival_test_hatches_are(state, loaded_content.machines, true))
	end_session(loaded)

	skipped, skipped_content := run_arrival_test_world(config, content, 100)
	queue_player_command(&skipped.simulation.player_commands, 0, Skip_Arrival_Command{})
	for _ in 0 ..< 100 {
		tick_field_test_simulation(&skipped.simulation, skipped_content, {})
	}
	reloaded, reloaded_content := reload_arrival_test_world(config, content, skipped, skipped_content)
	end_session(skipped)
	defer end_session(reloaded)
	testing.expect_value(t, reloaded.simulation.field.arrival.landed_tick, u64(101))
	testing.expect(t, !field_arrival_falling(reloaded.simulation.field.arrival))
	testing.expect(t, arrival_test_hatches_are(&reloaded.simulation, reloaded_content.machines, true))
}

// A save from before 0200 ends before the arrival's table: it reads with
// a zero arrival, nothing falls.
@(test)
test_a_save_from_before_the_arrival_loads_landed :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, 2)
	queue_player_command(&session.simulation.player_commands, 0, Skip_Arrival_Command{})
	tick_field_test_simulation(&session.simulation, simulation_content, {})
	testing.expect(t, session.simulation.field.arrival.landed_tick != 0)
	files := encode_save_files(&session.simulation, simulation_content, "before the arrival", 0)
	end_session(session)
	ARRIVAL_TABLE_BYTES :: 24
	files.entities = files.entities[:len(files.entities) - ARRIVAL_TABLE_BYTES]
	loaded := load_test_field_save(config, content, &files)
	defer end_session(loaded)
	testing.expect_value(t, loaded.simulation.field.arrival, Field_Arrival{})
	testing.expect(t, !field_arrival_falling(loaded.simulation.field.arrival))

	malformed := make([dynamic]byte, context.temp_allocator)
	field: Field_Simulation
	field.arrival = {start_tick = 0, fall_ticks = MAXIMUM_ARRIVAL_TICKS + 1}
	write_field_arrival_table(&malformed, &field)
	reader := Byte_Reader{data = malformed[:]}
	testing.expect(t, !read_field_arrival_table(&reader, &field), "a fall above the bound is malformed")
	clear(&malformed)
	field.arrival = {start_tick = 50, fall_ticks = 600, landed_tick = 40}
	write_field_arrival_table(&malformed, &field)
	reader = Byte_Reader{data = malformed[:]}
	testing.expect(t, !read_field_arrival_table(&reader, &field), "a landing before the start is malformed")
}

// Every presentation procedure called on one session each tick leaves its
// hash equal to an untouched session's.
@(test)
test_the_arrivals_presentation_leaves_the_hash :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	watched, watched_content := run_arrival_test_world(config, content, 0)
	defer end_session(watched)
	plain, plain_content := run_arrival_test_world(config, content, 0)
	defer end_session(plain)
	salt := watched.simulation.world.settings.seed
	for tick in 1 ..= 700 {
		tick_field_test_simulation(&watched.simulation, watched_content, {})
		tick_field_test_simulation(&plain.simulation, plain_content, {})
		state := &watched.simulation
		view := arrival_view(state.field.arrival, state.tick, 0.5, config)
		frame, found := find_pod_frame(&state.world.entities, watched_content.machines)
		testing.expect(t, found)
		eye := world_position_to_metres(field_player_eye(state.players[0].field, watched_content.field.tuning))
		arrival_descent_camera(eye, view, unit_vector_to_f32(frame.axes[FRAME_UP]), unit_vector_to_f32(frame.axes[FRAME_FORWARD]), config, 70)
		arrival_shake_offset(view.seconds_since_hit, salt)
		for index in 0 ..< ARRIVAL_DUST_PUFFS {
			arrival_dust_puff(index, view.seconds_since_hit, salt)
		}
		if tick == 300 || tick == 540 || tick == 600 || tick == 700 {
			testing.expectf(t, lockstep_state_hash(state) == lockstep_state_hash(&plain.simulation), "the hashes part at tick %d", tick)
		}
	}
}

// Work item 0224: gathering the pod's lamps each tick (presentation only)
// leaves the hash equal to an untouched session's.
@(test)
test_the_machine_lights_leave_the_hash :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	pod_machine := find_machine_of_kind(content.machines, .Pod)
	content.machines.machines[pod_machine].lights[0] = {position = {0, 5.8, 0}, color = {1, 0.6, 0.15}, radius_cells = 6}
	content.machines.machines[pod_machine].lights[1] = {position = {3, 2, 0}, color = {0.77, 0.89, 1}, radius_cells = 2}
	content.machines.machines[pod_machine].light_count = 2
	watched, watched_content := run_arrival_test_world(config, content, 0)
	defer end_session(watched)
	plain, plain_content := run_arrival_test_world(config, content, 0)
	defer end_session(plain)
	for tick in 1 ..= 700 {
		tick_field_test_simulation(&watched.simulation, watched_content, {})
		tick_field_test_simulation(&plain.simulation, plain_content, {})
		state := &watched.simulation
		lights := make([dynamic]Point_Light, context.temp_allocator)
		gather_machine_lights(&lights, &state.world.entities, watched_content.machines)
		eye := world_position_to_metres(field_player_eye(state.players[0].field, watched_content.field.tuning))
		nearest_point_lights(lights[:], eye)
		if tick == 300 || tick == 540 || tick == 700 {
			testing.expectf(t, len(lights) == 2, "tick %d: %d lights gathered", tick, len(lights))
			testing.expectf(t, lockstep_state_hash(state) == lockstep_state_hash(&plain.simulation), "the hashes part at tick %d", tick)
		}
	}
}
