package game

import "core:log"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:time"

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
	config.arrival_start_metres = shipped.arrival_start_metres
	config.arrival_entry_angle_degrees = shipped.arrival_entry_angle_degrees
	config.arrival_entry_speed_metres_per_second = shipped.arrival_entry_speed_metres_per_second
	config.arrival_terminal_speed_metres_per_second = shipped.arrival_terminal_speed_metres_per_second
	config.arrival_heat_threshold_percent = shipped.arrival_heat_threshold_percent
	config.arrival_real_seconds = shipped.arrival_real_seconds
	config.arrival_rest_tilt_degrees = shipped.arrival_rest_tilt_degrees
	config.atmosphere = shipped.atmosphere
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

// A walk, a jump, Sneak, the tools and Interact.
ARRIVAL_TEST_RESTLESS :: Input_Frame {
	move         = {0, 1},
	pressed      = {.Move, .Jump, .Interact, .Sneak, .Mine, .Place},
	just_pressed = {.Jump, .Interact, .Mine, .Place},
}

// A turn alone, and Interact alone (0223).
ARRIVAL_TEST_LOOK :: Input_Frame{look_delta = {40, 0}}
ARRIVAL_TEST_INTERACT :: Input_Frame{pressed = {.Interact}, just_pressed = {.Interact}}

// One tick of a session with each player's frame, the set staged first.
tick_arrival_test_session :: proc(session: ^Session, content: Simulation_Content, inputs: []Input_Frame) {
	if !simulated_chunks_ready(&session.simulation) {
		stage_generated_field_set(&session.simulation)
	}
	simulation_tick(&session.simulation, content, inputs)
}

// A new world's players cannot move for the fall; the hatches stay
// closed through it and at its end (0222: the airlock opens them as a
// player comes).
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
	testing.expect(t, arrival_test_hatches_are(state, restless_content.machines, false), "closed after the last tick")
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	for hatch in arrival_test_hatches(state, restless_content.machines) {
		testing.expect_value(t, pool_get(&state.world.entities.foundations, hatch).hatch_toggle_tick, 0)
	}
	// Unbuckled (0223), both alike.
	tick_field_test_simulation(&restless.simulation, restless_content, ARRIVAL_TEST_INTERACT)
	tick_field_test_simulation(&still.simulation, still_content, ARRIVAL_TEST_INTERACT)
	walk := Input_Frame{move = {0, 1}, pressed = {.Move}}
	for _ in 0 ..< 10 {
		tick_field_test_simulation(&restless.simulation, restless_content, walk)
		tick_field_test_simulation(&still.simulation, still_content, {})
	}
	testing.expect(t, restless.simulation.players[0].field.position != still.simulation.players[0].field.position, "the walk moves the player after the landing")
}

// The fall cuts the frame to the look (0223): the walk, Sneak, the tools,
// Interact and Open_Aimed do nothing, the player stays strapped in with
// the eye on the seat's, and the look turns every tick.
@(test)
test_the_fall_ignores_the_walk_and_the_tools_and_takes_the_look :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	restless := start_field_test_session(config, content)
	defer end_session(restless)
	still := start_field_test_session(config, content)
	defer end_session(still)
	restless_content := field_test_content(restless, content)
	still_content := field_test_content(still, content)
	frame := ARRIVAL_TEST_RESTLESS
	frame.look_delta = ARRIVAL_TEST_LOOK.look_delta
	frame.pressed += {.Open_Aimed}
	frame.just_pressed += {.Open_Aimed}
	held := arrival_input(restless.simulation.field.arrival, frame)
	testing.expect_value(t, held.pressed, Action_Set{})
	testing.expect_value(t, held.just_pressed, Action_Set{})
	testing.expect_value(t, held.move, [2]f32{})
	testing.expect_value(t, held.look_delta, frame.look_delta)
	for tick in 1 ..< ARRIVAL_TEST_TICKS {
		yaw_before := restless.simulation.players[0].field.yaw
		tick_field_test_simulation(&restless.simulation, restless_content, frame)
		tick_field_test_simulation(&still.simulation, still_content, {})
		state := &restless.simulation
		body := state.players[0].field
		pod, pod_frame, found := find_pod(&state.world.entities, restless_content.machines)
		testing.expect(t, found)
		if body.seat != .Strapped || field_player_eye(body, restless_content.field.tuning) != pod_seat_eye(pod_frame, pod, restless_content.machines.machines[pod.machine]) {
			testing.expectf(t, false, "tick %d: seat %v, the eye off the seat", tick, body.seat)
			return
		}
		// The hit's rest turns the look into the forward, yaw 0 (0270).
		resting := u64(tick) == field_arrival_hit_tick(state.field.arrival, restless_content.field.pod_rest.settle_ticks)
		if body.crouching || (!resting && (body.yaw == yaw_before || body.yaw == still.simulation.players[0].field.yaw)) {
			testing.expectf(t, false, "tick %d: crouching %v, yaw %d before %d", tick, body.crouching, body.yaw, yaw_before)
			return
		}
		same_inventory := arrival_test_stacks_equal(state.players[0].inventory.slots, still.simulation.players[0].inventory.slots)
		if !same_inventory || len(state.field.edits) != len(still.simulation.field.edits) || len(state.field.placements) != len(still.simulation.field.placements) || len(state.field.torches) != len(still.simulation.field.torches) {
			testing.expectf(t, false, "tick %d: the tools acted", tick)
			return
		}
		if state.players[0].open_machine != NO_ENTITY {
			testing.expectf(t, false, "tick %d: Open_Aimed opened a panel", tick)
			return
		}
	}
}

// The two inventories hold the same stacks.
arrival_test_stacks_equal :: proc(first, second: []Item_Stack) -> bool {
	if len(first) != len(second) {
		return false
	}
	for stack, index in first {
		if stack != second[index] {
			return false
		}
	}
	return true
}

// Interact through the fall does nothing; the landing tells player 0
// Touchdown_Confirmed on its tick alone; Interact on the tick after
// stands the player in the cabin, and the walk then moves it.
@(test)
test_interact_before_touchdown_does_nothing_and_after_it_stands_the_player :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	for tick in 1 ..= ARRIVAL_TEST_TICKS + 1 {
		clear(&state.events)
		tick_field_test_simulation(state, simulation_content, ARRIVAL_TEST_INTERACT)
		touchdown := false
		for event in state.events {
			touchdown ||= event.player == 0 && event.kind == .Touchdown_Confirmed
		}
		testing.expectf(t, touchdown == (tick == ARRIVAL_TEST_TICKS), "tick %d: touchdown told %v", tick, touchdown)
		if tick <= ARRIVAL_TEST_TICKS && state.players[0].field.seat != .Strapped {
			testing.expectf(t, false, "tick %d: unbuckled before touchdown", tick)
			return
		}
	}
	body := state.players[0].field
	testing.expect_value(t, body.seat, Field_Seat.Standing)
	// In the cabin's cells: the tilted cabin's cells (the test content has
	// no collision volumes) push the upright capsule off the spawn (0270).
	pod, pod_frame, found := find_pod(&state.world.entities, simulation_content.machines)
	testing.expect(t, found)
	feet := frame_cell_of_feet(pod_frame, body)
	testing.expectf(t, slice.contains(test_pod_box_cells(simulation_content.machines.machines[pod.machine], TEST_CABIN_BOX), feet), "the feet stand in cell %v, not the cabin's", feet)
	for _ in 0 ..< 10 {
		tick_field_test_simulation(state, simulation_content, Input_Frame{move = {0, 1}, pressed = {.Move}})
	}
	testing.expect(t, state.players[0].field.position != body.position, "the walk moves the player")
}

// arrival_ticks 0 (the spawn stands): aimed at the chair's cushion
// Interact sits, the eye on the seat's; the walk and Jump leave the body
// where it is; Interact stands it at the cabin's spawn. Aimed at the
// bench, Interact leaves the player standing.
@(test)
test_interact_on_the_chair_seats_and_unseats :: proc(t: ^testing.T) {
	config := arrival_test_config()
	config.arrival_ticks = 0
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tuning := simulation_content.field.tuning
	pod, pod_frame, found := find_pod(&state.world.entities, simulation_content.machines)
	testing.expect(t, found)
	machine := simulation_content.machines.machines[pod.machine]
	cushion := model_point_in_frame(pod_frame, pod.origin, pod.size, pod.rotation, collision_point_units({-2.0, 1.0, 1.0}))
	testing.expect(t, look_field_player_at(&state.players[0].field, tuning, cushion))
	tick_field_test_simulation(state, simulation_content, {})
	testing.expect(t, field_aimed_chair(&state.world.entities, simulation_content.machines, state.players[0].field.frame_target), "the cushion is the chair")
	tick_field_test_simulation(state, simulation_content, ARRIVAL_TEST_INTERACT)
	testing.expect_value(t, state.players[0].field.seat, Field_Seat.Seated)
	testing.expect_value(t, field_player_eye(state.players[0].field, tuning), pod_seat_eye(pod_frame, pod, machine))
	seated := state.players[0].field.position
	for _ in 0 ..< 30 {
		tick_field_test_simulation(state, simulation_content, Input_Frame{move = {0, 1}, pressed = {.Move, .Jump}, just_pressed = {.Jump}})
	}
	testing.expect_value(t, state.players[0].field.position, seated)
	tick_field_test_simulation(state, simulation_content, ARRIVAL_TEST_INTERACT)
	testing.expect_value(t, state.players[0].field.seat, Field_Seat.Standing)
	spawn, _ := field_pod_spawn(&state.world.entities, simulation_content.machines)
	testing.expect(t, vector_length(cast([3]i64)(state.players[0].field.position - spawn.position)) < millimetres_to_position_units(100), "stood at the cabin's spawn")
	bench := model_point_in_frame(pod_frame, pod.origin, pod.size, pod.rotation, collision_point_units({-3.5, 1.0, -1.5}))
	testing.expect(t, look_field_player_at(&state.players[0].field, tuning, bench))
	tick_field_test_simulation(state, simulation_content, {})
	testing.expect(t, !field_aimed_chair(&state.world.entities, simulation_content.machines, state.players[0].field.frame_target), "the bench is no chair")
	tick_field_test_simulation(state, simulation_content, ARRIVAL_TEST_INTERACT)
	testing.expect_value(t, state.players[0].field.seat, Field_Seat.Standing)
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

// One frame of A: its queued commands held, one record of input stamped,
// relayed to B, and both run their ready ticks. The tick of a record
// carrying a command, 0 for none.
step_arrival_lockstep_test :: proc(first, second: ^Session, first_content, second_content: Simulation_Content, input := Input_Frame{}) -> (command_tick: u64) {
	hold_local_commands(&first.lockstep, &first.simulation)
	stamp_local_record(&first.lockstep, first.simulation.tick, input)
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
		testing.expect(t, arrival_test_hatches_are(&session.simulation, first_content.machines, false))
	}
	queue_player_command(&first.simulation.player_commands, 0, Skip_Arrival_Command{})
	for _ in 0 ..< 5 {
		step_arrival_lockstep_test(first, second, first_content, second_content)
	}
	testing.expect_value(t, first.simulation.field.arrival.landed_tick, landing)
	testing.expect_value(t, lockstep_state_hash(&first.simulation), lockstep_state_hash(&second.simulation))
}

// Two machines in lockstep (window 2), A stamping the restless frame and
// the look through the fall and Interact at the landing and every 50
// ticks after: the hashes agree at the fall's middle, its landing and
// after the stand (0223).
@(test)
test_two_machines_hash_alike_through_a_fall_with_input :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	first := start_field_test_session(config, content)
	defer end_session(first)
	second := start_field_test_session(config, content)
	defer end_session(second)
	first_content := field_test_content(first, content)
	second_content := field_test_content(second, content)
	first.lockstep.window, second.lockstep.window = 2, 2
	restless := ARRIVAL_TEST_RESTLESS
	restless.look_delta = ARRIVAL_TEST_LOOK.look_delta
	checked := 0
	placed: Frame
	before_hit: [2]u64
	for first.simulation.tick < 700 {
		tick := first.simulation.tick
		input := tick < ARRIVAL_TEST_TICKS ? restless : Input_Frame{}
		if tick >= ARRIVAL_TEST_TICKS - 2 && (tick - (ARRIVAL_TEST_TICKS - 2)) % 50 == 0 {
			input = ARRIVAL_TEST_INTERACT
		}
		step_arrival_lockstep_test(first, second, first_content, second_content, input)
		testing.expect_value(t, first.simulation.tick, second.simulation.tick)
		hit := field_arrival_hit_tick(first.simulation.field.arrival, first_content.field.pod_rest.settle_ticks)
		if first.simulation.tick == hit - 1 {
			_, placed, _ = find_pod(&first.simulation.world.entities, first_content.machines)
			before_hit = {field_state_hash(&first.simulation.field, 0), field_state_hash(&second.simulation.field, 0)}
		}
		switch first.simulation.tick {
		case 300, 540, 600, 601, 650, 700:
			checked += 1
			testing.expectf(t, lockstep_state_hash(&first.simulation) == lockstep_state_hash(&second.simulation), "the hashes part at tick %d", first.simulation.tick)
		}
		if first.simulation.tick == hit {
			for session, index in ([2]^Session{first, second}) {
				testing.expect(t, field_state_hash(&session.simulation.field, 0) != before_hit[index], "the field changes at the hit (0271)")
				pod, frame, _ := find_pod(&session.simulation.world.entities, first_content.machines)
				origin, axes := pod_rest_pose(placed, pod, first_content.machines.machines[pod.machine], first_content.field.pod_rest.tilt_degrees)
				testing.expect(t, frame.axes != placed.axes, "the pose changed at the hit")
				testing.expect(t, frame.origin == origin && frame.axes == axes, "the pod rests in its rest pose at the hit")
			}
		}
	}
	testing.expect_value(t, checked, 6)
	testing.expect_value(t, first.simulation.players[0].field.seat, Field_Seat.Standing)
	testing.expect_value(t, second.simulation.players[0].field.seat, Field_Seat.Standing)
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

// A save loaded at tick 1000 has no fall: landed, the hatches closed, the
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
	testing.expect(t, arrival_test_hatches_are(state, loaded_content.machines, false))
	// Still strapped in, never unbuckled (0223).
	testing.expect_value(t, state.players[0].field.seat, Field_Seat.Strapped)
	tick_field_test_simulation(state, loaded_content, ARRIVAL_TEST_INTERACT)
	start := state.players[0].field.position
	tick_field_test_simulation(state, loaded_content, FIELD_PREDICTION_TEST_WALK)
	testing.expect(t, state.players[0].field.position != start, "the walk moves the player")
	curve := build_arrival_curve(config)
	testing.expect_value(t, arrival_view(state.field.arrival, 1000, 0, config, &curve).phase, Arrival_Phase.None)
}

// A joiner at tick 1000 starts from the snapshot's files: the pod's frame
// is the host's rested one, a second player spawns in the cabin and walks
// on the next tick.
@(test)
test_a_joiner_after_the_fall_has_no_fall :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, 1000)
	joined, joined_content := reload_arrival_test_world(config, content, session, simulation_content)
	_, host_frame, _ := find_pod(&session.simulation.world.entities, simulation_content.machines)
	host_field := field_state_hash(&session.simulation.field, 0)
	end_session(session)
	defer end_session(joined)
	state := &joined.simulation
	_, joined_frame, _ := find_pod(&state.world.entities, joined_content.machines)
	testing.expect_value(t, joined_frame, host_frame)
	// The crater travels in the snapshot (0271).
	testing.expect_value(t, field_state_hash(&state.field, 0), host_field)
	centre, radius := arrival_test_bed(state, joined_content.machines)
	expect_field_holds_the_crater(t, state, centre, radius)
	queue_player_command(&state.player_commands, 1, Add_Player_Command{})
	tick_arrival_test_session(joined, joined_content, {})
	testing.expect_value(t, len(state.players), 2)
	if len(state.players) < 2 {
		return
	}
	_, found := field_pod_spawn(&state.world.entities, joined_content.machines)
	testing.expect(t, found)
	// The tilted cabin's cells (the test content has no collision
	// volumes) push the upright capsule off the spawn on its first tick,
	// so the feet are checked in the cabin's cells.
	pod, _, _ := find_pod(&state.world.entities, joined_content.machines)
	cabin := test_pod_box_cells(joined_content.machines.machines[pod.machine], TEST_CABIN_BOX)
	feet := frame_cell_of_feet(joined_frame, state.players[1].field)
	testing.expectf(t, slice.contains(cabin, feet), "the joiner's feet are in cell %v, not the cabin's", feet)
	testing.expect_value(t, state.players[1].field.seat, Field_Seat.Standing)
	before := state.players[1].field.position
	heading := field_player_heading(state.players[1].field)
	inputs := [2]Input_Frame{{}, Input_Frame{move = {0, 1}, pressed = {.Move}}}
	tick_arrival_test_session(joined, joined_content, inputs[:])
	step := cast([3]i64)(state.players[1].field.position - before)
	testing.expect(t, step.x * heading.x + step.y * heading.y + step.z * heading.z > 0, "the joiner walks ahead on the next tick")
	testing.expect(t, !field_arrival_falling(state.field.arrival))
	curve := build_arrival_curve(config)
	testing.expect_value(t, arrival_view(state.field.arrival, state.tick, 0, config, &curve).phase, Arrival_Phase.None)
}

// A save taken at tick 300 resumes the fall, rests at the hit to the
// unsaved run's pose and field and lands at tick 600, not before; one
// taken at tick 200 after a Skip at tick 101 loads landed.
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
	unsaved, unsaved_content := run_arrival_test_world(config, content, 300)
	defer end_session(unsaved)
	for state.tick < ARRIVAL_TEST_TICKS - 1 {
		tick_field_test_simulation(state, loaded_content, {})
		tick_field_test_simulation(&unsaved.simulation, unsaved_content, {})
	}
	_, loaded_frame, _ := find_pod(&state.world.entities, loaded_content.machines)
	_, unsaved_frame, _ := find_pod(&unsaved.simulation.world.entities, unsaved_content.machines)
	testing.expect_value(t, loaded_frame, unsaved_frame)
	testing.expect_value(t, field_state_hash(&state.field, 0), field_state_hash(&unsaved.simulation.field, 0))
	centre, radius := arrival_test_bed(state, loaded_content.machines)
	expect_field_holds_the_crater(t, state, centre, radius)
	testing.expect(t, field_arrival_falling(state.field.arrival), "still falling at tick 599")
	tick_field_test_simulation(state, loaded_content, {})
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	testing.expect(t, arrival_test_hatches_are(state, loaded_content.machines, false))
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
	testing.expect(t, arrival_test_hatches_are(&reloaded.simulation, reloaded_content.machines, false))
}

// Work items 0222, 0231: the landing leaves both doors closed and nothing
// opens them while the player stands still in the cabin; crawling to the
// inner door opens it, the outer shut on that tick.
@(test)
test_the_doors_stay_closed_at_the_landing_until_the_player_comes :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, ARRIVAL_TEST_TICKS)
	defer end_session(session)
	state := &session.simulation
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	testing.expect(t, arrival_test_hatches_are(state, simulation_content.machines, false), "closed at the landing")
	for _ in 0 ..< 120 {
		tick_field_test_simulation(state, simulation_content, {})
	}
	testing.expect(t, arrival_test_hatches_are(state, simulation_content.machines, false), "closed with the player still in the cabin")
	for hatch in arrival_test_hatches(state, simulation_content.machines) {
		testing.expect_value(t, pool_get(&state.world.entities.foundations, hatch).hatch_toggle_tick, 0)
	}
	// Unbuckled (0223), facing the seat's way; turned to the door as the
	// player would turn.
	tick_field_test_simulation(state, simulation_content, ARRIVAL_TEST_INTERACT)
	spawn, _ := field_pod_spawn(&state.world.entities, simulation_content.machines)
	state.players[0].field.forward, state.players[0].field.yaw = spawn.forward, 0
	crawl := Input_Frame{move = {0, 1}, pressed = {.Move, .Sneak}}
	opened := false
	for _ in 0 ..< 120 {
		tick_field_test_simulation(state, simulation_content, crawl)
		inner := test_session_hatch(state, simulation_content.machines, 1)
		if inner != nil && inner.hatch_open {
			opened = true
			break
		}
	}
	outer := test_session_hatch(state, simulation_content.machines, 0)
	testing.expect(t, opened, "the inner door opens as the player comes")
	testing.expect(t, outer != nil && !outer.hatch_open, "the outer door is shut when the inner opens")
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
	curve := build_arrival_curve(config)
	for tick in 1 ..= 700 {
		tick_field_test_simulation(&watched.simulation, watched_content, {})
		tick_field_test_simulation(&plain.simulation, plain_content, {})
		state := &watched.simulation
		view := arrival_view(state.field.arrival, state.tick, 0.5, config, &curve)
		pod, frame, found := find_pod(&state.world.entities, watched_content.machines)
		testing.expect(t, found)
		machine := watched_content.machines.machines[pod.machine]
		up, forward := unit_vector_to_f32(frame.axes[FRAME_UP]), unit_vector_to_f32(pod_travel_heading(frame, pod, machine))
		arrival_descent_offset(view, up, forward, &curve)
		travel := arrival_travel_direction(arrival_curve_at(&curve, view.curve_progress), up, forward)
		arrival_pod_transform(view, frame, pod, machine, config.arrival_rest_tilt_degrees, &curve)
		testing.expect(t, machine.window_count > 0)
		for index in 0 ..< machine.window_count {
			window := machine.windows[index]
			arrival_window_corners(window.centre, window.normal, travel, up, window.radius)
		}
		arrival_shake_offset(view.seconds_since_hit, salt)
		arrival_buffet_offset(view.seconds, view.heat, salt)
		atmosphere_sky_share(linalg.dot(arrival_descent_offset(view, up, forward, &curve), up), config.atmosphere)
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
		gather_machine_lights(&lights, &state.world.entities, watched_content.machines, Model_Renderer{})
		eye := world_position_to_metres(field_player_eye(state.players[0].field, watched_content.field.tuning))
		nearest_point_lights(lights[:], eye)
		if tick == 300 || tick == 540 || tick == 700 {
			testing.expectf(t, len(lights) == 2, "tick %d: %d lights gathered", tick, len(lights))
			testing.expectf(t, lockstep_state_hash(state) == lockstep_state_hash(&plain.simulation), "the hashes part at tick %d", tick)
		}
	}
}

// Work item 0225: the pod's interior light share is presentation only, a
// world drawn with it hashes as one whose pod has none.
@(test)
test_the_interior_light_share_leaves_the_hash :: proc(t: ^testing.T) {
	config := arrival_test_config()
	watched_game := make_field_test_game_content()
	watched_game.machines.machines[find_machine_of_kind(watched_game.machines, .Pod)].interior_light_share = 0.25
	plain_game := make_field_test_game_content()
	watched, watched_content := run_arrival_test_world(config, watched_game, 0)
	defer end_session(watched)
	plain, plain_content := run_arrival_test_world(config, plain_game, 0)
	defer end_session(plain)
	model_frame := Model_Frame{open_sky = true, day_factor = 1, sky_tint = {1, 1, 1}}
	for tick in 1 ..= 700 {
		tick_field_test_simulation(&watched.simulation, watched_content, {})
		tick_field_test_simulation(&plain.simulation, plain_content, {})
		state := &watched.simulation
		entities := &state.world.entities
		model_frame.interiors = gather_interior_lights(entities, watched_content.machines)
		pod_frame, _ := find_pod_frame(entities, watched_content.machines)
		pod := pool_get(&entities.foundations, pod_on_frame(entities, watched_content.machines, pod_frame.id))
		tint: [3]f32
		if pod != nil {
			tint, _ = posed_model_light(model_frame, pod.common, watched_content.machines.machines[pod.machine], {working = true})
		}
		field_player_interior_light_share(model_frame.interiors, state.players[0].field)
		if tick == 300 || tick == 540 || tick == 700 {
			testing.expectf(t, len(model_frame.interiors) == 1, "tick %d: %d interiors gathered", tick, len(model_frame.interiors))
			testing.expectf(t, abs(tint.x - 0.25) < 1e-5, "tick %d: the pod's tint is %v", tick, tint)
			testing.expectf(t, lockstep_state_hash(state) == lockstep_state_hash(&plain.simulation), "the hashes part at tick %d", tick)
		}
	}
}

// Work item 0223: a machine placement command (the placement editor's
// commit) is refused from a player strapped in during the fall and from a
// seated player after it; a standing player's is queued as before.
@(test)
test_a_placement_from_the_chair_is_refused :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	command := Machine_Placement_Command{machine = test_machine(simulation_content.machines, "stone_furnace"), new_frame = true, hit = state.players[0].field.position, heading = state.players[0].field.forward}
	testing.expect_value(t, state.players[0].field.seat, Field_Seat.Strapped)
	testing.expect(t, !queue_machine_placement(state, simulation_content, 0, command), "strapped in during the fall")
	for state.tick < ARRIVAL_TEST_TICKS {
		tick_field_test_simulation(state, simulation_content, {})
	}
	tuning := simulation_content.field.tuning
	testing.expect(t, seat_field_player(&state.world.entities, simulation_content.machines, tuning, &state.players[0].field, .Seated))
	testing.expect(t, !queue_machine_placement(state, simulation_content, 0, command), "seated after the landing")
	testing.expect_value(t, len(state.field.placements), 0)
	stand_field_player_from_seat(&state.world.entities, simulation_content.machines, &state.players[0].field)
	testing.expect(t, queue_machine_placement(state, simulation_content, 0, command), "standing")
	testing.expect_value(t, len(state.field.placements), 1)
	clear(&state.field.placements)
}

// Work item 0270: the pod's frame is the placed one up to the hit and
// pod_rest_pose's exactly after it, unchanged through the landing and
// after; the strapped player's eye is the rested seat's and its look the
// look before the hit turned with the pod.
@(test)
test_the_pod_rests_at_the_hit :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	_, placed, _ := find_pod(&state.world.entities, simulation_content.machines)
	hit := field_arrival_hit_tick(state.field.arrival, simulation_content.field.pod_rest.settle_ticks)
	for state.tick < hit - 1 {
		tick_field_test_simulation(state, simulation_content, ARRIVAL_TEST_LOOK)
	}
	pod, before, _ := find_pod(&state.world.entities, simulation_content.machines)
	testing.expect_value(t, before, placed)
	machine := simulation_content.machines.machines[pod.machine]
	body := state.players[0].field
	look := field_look_direction(body.forward, body.up, body.yaw, body.pitch)
	cosine, sine := pod_rest_turn(simulation_content.field.pod_rest.tilt_degrees)
	turned, _ := normalize_fixed(rotate_in_plane(look, placed.axes[FRAME_UP], pod_travel_heading(placed, pod, machine), cosine, sine))
	tick_field_test_simulation(state, simulation_content, {})
	origin, axes := pod_rest_pose(placed, pod, machine, simulation_content.field.pod_rest.tilt_degrees)
	_, rested, _ := find_pod(&state.world.entities, simulation_content.machines)
	testing.expect(t, rested.origin == origin && rested.axes == axes, "the frame is the rest pose after the hit")
	body = state.players[0].field
	testing.expect_value(t, body.seat, Field_Seat.Strapped)
	eye := field_player_eye(body, simulation_content.field.tuning)
	testing.expectf(t, vector_length(cast([3]i64)(eye - pod_seat_eye(rested, pod, machine))) <= millimetres_to_position_units(1), "the eye lies off the rested seat's")
	drawn := field_look_direction(body.forward, body.up, body.yaw, body.pitch)
	testing.expectf(t, vector_length(drawn - turned) <= UNIT_VECTOR_ONE / 1024, "the look %v is not the turned %v", drawn, turned)
	for state.tick < ARRIVAL_TEST_TICKS + 60 {
		tick_field_test_simulation(state, simulation_content, {})
	}
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	_, after, _ := find_pod(&state.world.entities, simulation_content.machines)
	testing.expect_value(t, after, rested)
}

// Work item 0270: a Skip at tick 100 rests the pod at that tick to the
// same pose and field as a run that rests at the hit; the landing changes
// neither.
@(test)
test_skip_before_the_hit_rests_the_pod_once :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	skipped, skipped_content := run_arrival_test_world(config, content, 99)
	defer end_session(skipped)
	_, placed, _ := find_pod(&skipped.simulation.world.entities, skipped_content.machines)
	queue_player_command(&skipped.simulation.player_commands, 0, Skip_Arrival_Command{})
	tick_field_test_simulation(&skipped.simulation, skipped_content, {})
	testing.expect_value(t, skipped.simulation.field.arrival.landed_tick, u64(100))
	pod, skip_frame, _ := find_pod(&skipped.simulation.world.entities, skipped_content.machines)
	origin, axes := pod_rest_pose(placed, pod, skipped_content.machines.machines[pod.machine], skipped_content.field.pod_rest.tilt_degrees)
	testing.expect(t, skip_frame.origin == origin && skip_frame.axes == axes, "the Skip rests the pod")
	skip_hash := field_state_hash(&skipped.simulation.field, 0)

	hit := int(field_arrival_hit_tick(skipped.simulation.field.arrival, skipped_content.field.pod_rest.settle_ticks))
	rested, rested_content := run_arrival_test_world(config, content, hit)
	defer end_session(rested)
	_, hit_frame, _ := find_pod(&rested.simulation.world.entities, rested_content.machines)
	testing.expect_value(t, hit_frame, skip_frame)
	testing.expect_value(t, field_state_hash(&rested.simulation.field, 0), skip_hash)

	for rested.simulation.tick < ARRIVAL_TEST_TICKS + 1 {
		tick_field_test_simulation(&rested.simulation, rested_content, {})
		tick_field_test_simulation(&skipped.simulation, skipped_content, {})
	}
	testing.expect_value(t, rested.simulation.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	for session in ([2]^Session{skipped, rested}) {
		_, frame, _ := find_pod(&session.simulation.world.entities, skipped_content.machines)
		testing.expect_value(t, frame, skip_frame)
		testing.expect_value(t, field_state_hash(&session.simulation.field, 0), skip_hash)
	}
}

// Work item 0270: a world landed without the rest (its arrival set
// landed directly, as a build before 0270 left it) saves and loads with
// the frame as saved, still level after 120 ticks.
@(test)
test_a_world_landed_level_loads_level :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, 100)
	session.simulation.field.arrival.landed_tick = session.simulation.tick
	_, level, _ := find_pod(&session.simulation.world.entities, simulation_content.machines)
	loaded, loaded_content := reload_arrival_test_world(config, content, session, simulation_content)
	end_session(session)
	defer end_session(loaded)
	_, frame, _ := find_pod(&loaded.simulation.world.entities, loaded_content.machines)
	testing.expect_value(t, frame, level)
	for _ in 0 ..< 120 {
		tick_field_test_simulation(&loaded.simulation, loaded_content, {})
	}
	_, frame, _ = find_pod(&loaded.simulation.world.entities, loaded_content.machines)
	testing.expect_value(t, frame, level)
}

// The impact's crater (work item 0271).

// A new world of the arrival at the spacing.
start_arrival_test_session_at :: proc(config: Game_Config, content: Game_Content, spacing_millimetres: int) -> ^Session {
	settings := default_world_file_settings(config)
	settings.sample_spacing_millimetres = spacing_millimetres
	session, problem := start_session(Session_Plan{seed = DEFAULT_WORLD_SEED, settings = settings}, config, content, make_test_generator(DEFAULT_WORLD_SEED))
	assert(problem == "", problem)
	return session
}

// The rested pod's bed: its base centre and the bed's radius plus two
// spacings (pod_bed_edits), the samples the crater's check leaves out.
arrival_test_bed :: proc(state: ^Simulation_State, machines: Machine_Registry) -> (centre: World_Position, radius: i64) {
	pod, frame, _ := find_pod(&state.world.entities, machines)
	machine := machines.machines[pod.machine]
	radius = i64(max(machine.footprint.x, machine.footprint.z)) * frame_pitch_units(frame) / 2
	return pod_base_centre(frame, pod), radius + 2 * sample_axis_to_position(1, state.field.spacing_millimetres)
}

// Every loaded sample farther than except_radius from except_centre
// holds the baked generation's density, material and tint; the first
// that does not is named.
expect_field_holds_the_crater :: proc(t: ^testing.T, state: ^Simulation_State, except_centre: World_Position, except_radius: i64, location := #caller_location) {
	world := &state.field.world
	baked := baked_planet_generation(world.water_planet.generation)
	spacing := state.field.spacing_millimetres
	testing.expect(t, len(world.chunks) > 0, "chunks are loaded", loc = location)
	for coordinate in sorted_field_chunk_coordinates(world.chunks) {
		chunk := world.chunks[coordinate]
		origin := field_chunk_origin(coordinate)
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			sample := origin + Sample_Coordinate(field_index_to_local(index))
			position := sample_to_world_position(sample, spacing)
			if except_radius >= 0 && vector_length(cast([3]i64)(position - except_centre)) <= except_radius {
				continue
			}
			if expected := planet_sample(baked, position); field_chunk_get_sample(chunk, index) != expected {
				testing.expectf(t, false, "the sample %v is %v, not the crater's %v", sample, field_chunk_get_sample(chunk, index), expected, loc = location)
				return
			}
		}
	}
}

// The terrain of every loaded chunk, for a comparison after an edit.
Arrival_Test_Terrain :: struct {
	density:  [FIELD_CHUNK_SAMPLE_COUNT]i8,
	material: [FIELD_CHUNK_SAMPLE_COUNT]Field_Material,
	tint:     [FIELD_CHUNK_SAMPLE_COUNT]u8,
}

copy_arrival_test_terrain :: proc(world: ^Field_World) -> map[Field_Chunk_Coordinate]^Arrival_Test_Terrain {
	terrain := make(map[Field_Chunk_Coordinate]^Arrival_Test_Terrain)
	for coordinate, chunk in world.chunks {
		copied := new(Arrival_Test_Terrain)
		copied^ = {chunk.density, chunk.material, chunk.tint}
		terrain[coordinate] = copied
	}
	return terrain
}

delete_arrival_test_terrain :: proc(terrain: ^map[Field_Chunk_Coordinate]^Arrival_Test_Terrain) {
	for _, copied in terrain {
		free(copied)
	}
	delete(terrain^)
}

// Work item 0271: up to the hit every loaded sample is the whole
// generation's; the dig writes the baked sample where impact_crater_sample
// marks a change and leaves every other sample, its wall time logged
// (the main agent's decision 3); a world ticked through the hit holds the
// crater outside the pod's bed, the ground at the placed frame's base
// centre.
@(test)
test_the_hit_digs_the_crater_and_nothing_else :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	for spacing in ([3]int{1000, 500, 333}) {
		session := start_arrival_test_session_at(config, content, spacing)
		defer end_session(session)
		simulation_content := field_test_content(session, content)
		state := &session.simulation
		testing.expect(t, state.world.planet.crater_at_impact, "a new world digs its crater at the hit")
		hit := field_arrival_hit_tick(state.field.arrival, simulation_content.field.pod_rest.settle_ticks)
		for state.tick < hit - 1 {
			tick_field_test_simulation(state, simulation_content, {})
		}
		world := &state.field.world
		generation := world.water_planet.generation
		expect_field_world_is_generation(t, world, generation, "before the hit")
		before := copy_arrival_test_terrain(world)
		defer delete_arrival_test_terrain(&before)
		entries := 0
		for _, chunk in world.chunks {
			entries += len(chunk.crater_overlay)
		}
		start := time.tick_now()
		chunks, applied := dig_impact_crater(state)
		log.infof("0271: the apply at %d mm over %d loaded chunks took %v: %d chunks with an overlay, %d samples applied, the overlays held %d samples (%d bytes)", spacing, len(world.chunks), time.tick_since(start), chunks, applied, entries, entries * size_of(Field_Crater_Sample))
		changed_count := 0
		mismatch: for coordinate in sorted_field_chunk_coordinates(world.chunks) {
			chunk := world.chunks[coordinate]
			copied := before[coordinate]
			origin := field_chunk_origin(coordinate)
			for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
				sample := origin + Sample_Coordinate(field_index_to_local(index))
				baked, changed := impact_crater_sample(generation, sample_to_world_position(sample, spacing))
				expected := changed ? baked : Field_Sample{copied.density[index], copied.material[index], copied.tint[index]}
				changed_count += changed ? 1 : 0
				if field_chunk_get_sample(chunk, index) != expected {
					testing.expectf(t, false, "%d mm: the sample %v (changed %v) is %v, not %v", spacing, sample, changed, field_chunk_get_sample(chunk, index), expected)
					break mismatch
				}
			}
		}
		testing.expectf(t, changed_count > 0, "%d mm: the dig changes samples", spacing)

		through := start_arrival_test_session_at(config, content, spacing)
		defer end_session(through)
		through_content := field_test_content(through, content)
		pod, placed, _ := find_pod(&through.simulation.world.entities, through_content.machines)
		for through.simulation.tick < hit {
			tick_field_test_simulation(&through.simulation, through_content, {})
		}
		centre, radius := arrival_test_bed(&through.simulation, through_content.machines)
		expect_field_holds_the_crater(t, &through.simulation, centre, radius)
		base := pod_base_centre(placed, pod)
		up := placed.axes[FRAME_UP]
		metre := i64(POSITION_UNITS_PER_METRE)
		ground := raycast_field(&through.simulation.field.world, spacing, base + World_Position(fixed_scale(up, metre)), -up, 3 * metre)
		testing.expectf(t, ground.hit && vector_length(cast([3]i64)(ground.position - base)) <= sample_axis_to_position(1, spacing), "%d mm: the ground lies %v off the base centre", spacing, ground.position - base)
	}
}

// Work item 0271: a new world saved at tick 0 whose world.sjson is set
// back to a baked crater, as a build before 0271 wrote it, generates the
// crater and holds it before the hit and after the landing.
@(test)
test_a_world_from_before_the_impact_keeps_its_baked_crater :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	session, simulation_content := run_arrival_test_world(config, content, 0)
	files := encode_save_files(&session.simulation, simulation_content, "before the impact", 0)
	end_session(session)
	text := string(files.world)
	testing.expect(t, strings.contains(text, "crater_at_impact: true"), "a new world records its impact")
	old, _ := strings.replace(text, "crater_at_impact: true", "crater_at_impact: false", 1, context.temp_allocator)
	files.world = transmute([]byte)old
	loaded := load_test_field_save(config, content, &files)
	defer end_session(loaded)
	loaded_content := field_test_content(loaded, content)
	state := &loaded.simulation
	testing.expect(t, !state.world.planet.crater_at_impact)
	hit := field_arrival_hit_tick(state.field.arrival, loaded_content.field.pod_rest.settle_ticks)
	for state.tick < hit - 1 {
		tick_field_test_simulation(state, loaded_content, {})
	}
	expect_field_holds_the_crater(t, state, {}, -1)
	for state.tick < ARRIVAL_TEST_TICKS + 1 {
		tick_field_test_simulation(state, loaded_content, {})
	}
	testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
	centre, radius := arrival_test_bed(state, loaded_content.machines)
	expect_field_holds_the_crater(t, state, centre, radius)
}

// Work item 0271: a world without a fall digs every chunk as it enters
// the set; nothing rests the pod, so no sample is left out.
@(test)
test_a_world_without_a_fall_digs_its_crater_as_it_enters :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session, _ := run_arrival_test_world(config, content, 2)
	defer end_session(session)
	testing.expect(t, !field_arrival_falling(session.simulation.field.arrival))
	testing.expect(t, session.simulation.world.planet.crater_at_impact)
	expect_field_holds_the_crater(t, &session.simulation, {}, -1)
}

// Work item 0271: a world saved after the hit's tick less one restores
// its set inside the hit's own tick (the tick is counted before the
// chunks) and still digs there: past the landing it holds the crater
// outside the bed and hashes as the run that never saved. The join case
// restores the snapshot's set before its first tick (as the joiner tests
// do) and hashes as the host's.
@(test)
test_a_save_at_the_tick_before_the_hit_digs_at_the_hit :: proc(t: ^testing.T) {
	config := arrival_test_config()
	content := make_field_test_game_content()
	host, host_content := run_arrival_test_world(config, content, 1)
	defer end_session(host)
	hit := field_arrival_hit_tick(host.simulation.field.arrival, host_content.field.pod_rest.settle_ticks)
	for host.simulation.tick < hit - 1 {
		tick_field_test_simulation(&host.simulation, host_content, {})
	}
	files := encode_save_files(&host.simulation, host_content, "before the hit", 0)
	saved := load_test_field_save(config, content, &files)
	defer end_session(saved)
	saved_content := field_test_content(saved, content)
	testing.expect(t, saved.simulation.field.chunk_set.restoring, "the saved world restores its set in its first tick")
	joined, joined_content := reload_arrival_test_world(config, content, host, host_content)
	defer end_session(joined)
	sessions := [2]^Session{saved, joined}
	contents := [2]Simulation_Content{saved_content, joined_content}
	for host.simulation.tick < ARRIVAL_TEST_TICKS + 1 {
		tick_field_test_simulation(&host.simulation, host_content, {})
		for session, index in sessions {
			tick_field_test_simulation(&session.simulation, contents[index], {})
		}
	}
	host_hash := field_state_hash(&host.simulation.field, 0)
	for session, index in sessions {
		state := &session.simulation
		testing.expect_value(t, state.tick, host.simulation.tick)
		testing.expect_value(t, state.field.arrival.landed_tick, u64(ARRIVAL_TEST_TICKS))
		centre, radius := arrival_test_bed(state, contents[index].machines)
		expect_field_holds_the_crater(t, state, centre, radius)
		testing.expectf(t, field_state_hash(&state.field, 0) == host_hash, "the %s world parts from the unsaved run", index == 0 ? "saved" : "joined")
	}
}
