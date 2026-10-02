package game

import "core:testing"

// A machine of an in-process session: a session without a window, its
// ticks through run_session_tick like the game's. generator feeds the
// simulated chunk set when it is on (feed_lockstep_test_chunks).
Lockstep_Test_Machine :: struct {
	using session: Session,
	control:       Command_Control,
	chunk_source:  ^Generator,
}

LOCKSTEP_TEST_SECOND_PLAYER :: World_Coordinate{-26, 0, -26}

// The save test's site with two players, both connected from the start,
// the local one by index, window ticks ahead.
make_lockstep_test_machine :: proc(content: Simulation_Content, generator: ^Generator, local_player, window: int, chunk_set := false) -> ^Lockstep_Test_Machine {
	machine := new(Lockstep_Test_Machine)
	machine.chunk_source = generator
	machine.simulation = make_save_test_simulation(generator, content)
	load_save_test_chunks(&machine.simulation.world, &machine.simulation.records, generator)
	build_save_test_site(&machine.simulation, content)
	if chunk_set {
		machine.simulation.chunk_set = make_simulated_chunk_set(1, 1)
	}
	append(&machine.simulation.players, make_player(player_start_on(LOCKSTEP_TEST_SECOND_PLAYER)))
	machine.lockstep = make_single_player_lockstep(machine.simulation.tick, player_start_on({}))
	set_lockstep_member(&machine.lockstep, 1, Lockstep_Member{joined_tick = 0, left_tick = NEVER_TICK})
	machine.lockstep.local_player = local_player
	machine.lockstep.window = window
	return machine
}

destroy_lockstep_test_machine :: proc(machine: ^Lockstep_Test_Machine) {
	destroy_lockstep(&machine.lockstep)
	destroy_session_network(&machine.network)
	destroy_simulation(&machine.simulation)
	free(machine)
}

// The workers' part for the test: every chunk of the next simulated set
// not loaded or arrived, generated here (from its saved blocks when it
// has some) and queued as a chunk arrival, as stream_session_chunks does.
feed_lockstep_test_chunks :: proc(machine: ^Lockstep_Test_Machine) {
	simulation := &machine.simulation
	if !simulation.chunk_set.enabled {
		return
	}
	for coordinate in next_simulated_chunks(simulation.chunk_set, player_chunk_centres(simulation.players[:])) {
		if coordinate in simulation.world.chunks || coordinate in simulation.arrived_chunks {
			continue
		}
		result := Chunk_Job_Result{kind = .Generate, coordinate = coordinate}
		generated: Generated_Chunk
		if saved, found := simulation.world.saved_chunks[coordinate]; found {
			generated, result.restored = generate_saved_chunk(machine.chunk_source, coordinate, saved)
		} else {
			generated = generate_chunk(machine.chunk_source, coordinate)
		}
		result.chunk, result.veins, result.outcrops, result.crates = generated.chunk, generated.veins, generated.outcrops, generated.crates
		queue_player_command(&simulation.player_commands, NO_PLAYER, Chunk_Ready_Command{result = result})
	}
}

// The host's relay without sockets: every machine's outgoing records,
// encoded and decoded as on the network, to every machine.
relay_in_process :: proc(machines: []^Lockstep_Test_Machine) {
	for sender in machines {
		for record in sender.lockstep.outgoing {
			message := record_message(record)
			for receiver in machines {
				reader := Byte_Reader{data = message[1:]}
				decoded, ok := decode_input_record(&reader)
				assert(ok)
				receive_input_record(&receiver.lockstep, decoded, receiver.simulation.tick)
			}
			destroy_input_record(record)
		}
		clear(&sender.lockstep.outgoing)
	}
}

// Every tick whose records and chunks are there, through the game's
// run_session_tick (the socket lines included).
run_lockstep_test_ticks :: proc(machine: ^Lockstep_Test_Machine, content: Simulation_Content) {
	answers := make([dynamic]Line_Answer, context.temp_allocator)
	for {
		feed_lockstep_test_chunks(machine)
		if !lockstep_records_ready(machine.lockstep, machine.simulation.tick) || !simulated_chunks_ready(&machine.simulation) {
			break
		}
		run_session_tick(&machine.session, content, &machine.control, &answers)
	}
}

// Each player its own input, and now and then a command.
lockstep_test_input :: proc(machine: ^Lockstep_Test_Machine, frame: int) -> Input_Frame {
	player := machine.lockstep.local_player
	if frame % 50 == 7 {
		queue_player_command(&machine.simulation.player_commands, player, Hotbar_Slot_Command{slot = (frame / 50 + player) % HOTBAR_SLOT_COUNT})
	}
	input := recorded_input(frame + 97 * player)
	input.raw.gamepad.name = "test pad"
	return input
}

// Two machines with the simulated chunk set on: the walks, the hotbar
// commands, a socket line (give), a craft and a research start of
// different players reach both alike, for a thousand ticks.
@(test)
test_two_simulations_fed_the_same_records_keep_the_same_hash :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	first := make_lockstep_test_machine(content, &generator, 0, 3, chunk_set = true)
	defer destroy_lockstep_test_machine(first)
	second := make_lockstep_test_machine(content, &generator, 1, 2, chunk_set = true)
	defer destroy_lockstep_test_machine(second)
	machines := [?]^Lockstep_Test_Machine{first, second}
	start := first.simulation.players[0].position
	plank := test_recipe(content.recipes, "plank")
	plank_item := test_item(content.items, "plank")
	// The site's queued research is taken back, so the command starts one.
	for machine in machines {
		machine.simulation.records.research.queued = false
	}
	research := NO_TECHNOLOGY
	for _, index in content.technologies.technologies {
		if technology_status(content.technologies, first.simulation.unlocks, index) == .Available {
			research = index
			break
		}
	}
	if !testing.expect(t, research != NO_TECHNOLOGY) {
		return
	}
	testing.expect_value(t, lockstep_state_hash(&first.simulation), lockstep_state_hash(&second.simulation))
	compared := 0
	for frame := 0; first.simulation.tick < 1000 || second.simulation.tick < 1000; frame += 1 {
		switch frame {
		case 10:
			append(&second.lockstep.local_lines, Socket_Line{line = clone_text("give log 4")})
		case 20:
			queue_player_command(&first.simulation.player_commands, 0, Research_Command{technology = research})
		case 40:
			queue_player_command(&second.simulation.player_commands, 1, Craft_Command{recipe = plank, count = 1})
		}
		for machine in machines {
			input := lockstep_test_input(machine, frame)
			hold_local_commands(&machine.lockstep, &machine.simulation)
			stamp_local_record(&machine.lockstep, machine.simulation.tick, input)
		}
		relay_in_process(machines[:])
		for machine in machines {
			run_lockstep_test_ticks(machine, content)
		}
		if first.simulation.tick == second.simulation.tick && state_hash_due(first.simulation.tick) && first.simulation.tick > 0 {
			testing.expectf(t, lockstep_state_hash(&first.simulation) == lockstep_state_hash(&second.simulation), "the hashes differ at tick %d", first.simulation.tick)
			compared += 1
		}
		if frame > 5000 {
			testing.fail_now(t, "the machines stopped ticking")
		}
	}
	testing.expect(t, compared >= 3)
	testing.expect_value(t, lockstep_state_hash(&first.simulation), lockstep_state_hash(&second.simulation))
	for machine in machines {
		simulation := &machine.simulation
		testing.expect(t, simulation.players[0].position != start)
		testing.expect(t, inventory_count(simulation.players[1].inventory, plank_item) > 0)
		testing.expect_value(t, simulation.players[1].crafting.count, 0)
		testing.expect(t, simulation.records.research.queued)
		testing.expect_value(t, simulation.records.research.technology, research)
		testing.expect(t, len(simulation.world.chunks) > 0)
		for coordinate in simulation.world.chunks {
			testing.expect(t, coordinate in simulation.chunk_set.chunks)
		}
	}
}

@(test)
test_a_tick_waits_for_the_last_players_record :: proc(t: ^testing.T) {
	lockstep := make_single_player_lockstep(0, {})
	defer destroy_lockstep(&lockstep)
	set_lockstep_member(&lockstep, 1, Lockstep_Member{joined_tick = 0, left_tick = NEVER_TICK})
	// Player 2 joins at tick 3, so ticks 1 and 2 need two records.
	set_lockstep_member(&lockstep, 2, Lockstep_Member{joined_tick = 3, left_tick = NEVER_TICK})
	testing.expect(t, !lockstep_records_ready(lockstep, 0))
	receive_input_record(&lockstep, Input_Record{tick = 1, player = 0}, 0)
	testing.expect(t, !lockstep_records_ready(lockstep, 0))
	receive_input_record(&lockstep, Input_Record{tick = 2, player = 1}, 0)
	testing.expect(t, !lockstep_records_ready(lockstep, 0))
	receive_input_record(&lockstep, Input_Record{tick = 1, player = 1}, 0)
	testing.expect(t, lockstep_records_ready(lockstep, 0))
	receive_input_record(&lockstep, Input_Record{tick = 2, player = 0}, 0)
	testing.expect(t, lockstep_records_ready(lockstep, 1))
	receive_input_record(&lockstep, Input_Record{tick = 3, player = 0}, 0)
	receive_input_record(&lockstep, Input_Record{tick = 3, player = 1}, 0)
	testing.expect(t, !lockstep_records_ready(lockstep, 2))
	receive_input_record(&lockstep, Input_Record{tick = 3, player = 2}, 0)
	testing.expect(t, lockstep_records_ready(lockstep, 2))
	// Player 1 left before tick 3: its record is no longer needed there.
	lockstep.members[1].left_tick = 3
	receive_input_record(&lockstep, Input_Record{tick = 4, player = 0}, 0)
	receive_input_record(&lockstep, Input_Record{tick = 4, player = 2}, 0)
	testing.expect(t, lockstep_records_ready(lockstep, 3))
}

// Walking ahead inside the window: the prediction is where the confirmed
// ticks put the player when nothing else happened, and it is replaced by
// the confirmed player when another player's command changed the outcome.
@(test)
test_the_prediction_matches_and_is_reconciled :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	machine := make_lockstep_test_machine(content, &generator, 0, 3)
	defer destroy_lockstep_test_machine(machine)
	walk := Input_Frame{move = {0, 1}}
	for _ in 0 ..< 4 {
		testing.expect(t, stamp_local_record(&machine.lockstep, machine.simulation.tick, walk))
	}
	testing.expect(t, !stamp_local_record(&machine.lockstep, machine.simulation.tick, walk))
	rebuild_prediction(&machine.lockstep, &machine.simulation, content)
	testing.expect(t, machine.lockstep.predicting)
	predicted := lockstep_view_player(&machine.lockstep, &machine.simulation).position
	start := machine.simulation.players[0].position
	testing.expect(t, predicted != start)
	// The inputs match: the remote player only stands.
	relay_in_process([]^Lockstep_Test_Machine{machine})
	for tick in u64(1) ..= 4 {
		receive_input_record(&machine.lockstep, Input_Record{tick = tick, player = 1}, machine.simulation.tick)
	}
	run_lockstep_test_ticks(machine, content)
	testing.expect_value(t, machine.simulation.tick, 4)
	testing.expect_value(t, machine.simulation.players[0].position, predicted)
	rebuild_prediction(&machine.lockstep, &machine.simulation, content)
	testing.expect_value(t, lockstep_view_player(&machine.lockstep, &machine.simulation).position, predicted)

	// The remote player turns cheat speed on in tick 5, which the
	// prediction does not know: it falls behind the confirmed walk, and the
	// rebuild after the ticks replaces it.
	for _ in 0 ..< 4 {
		stamp_local_record(&machine.lockstep, machine.simulation.tick, walk)
	}
	rebuild_prediction(&machine.lockstep, &machine.simulation, content)
	predicted = lockstep_view_player(&machine.lockstep, &machine.simulation).position
	relay_in_process([]^Lockstep_Test_Machine{machine})
	cheat := Input_Record{tick = 5, player = 1}
	append(&cheat.commands, Developer_Request{action = .Toggle_Cheat_Speed})
	receive_input_record(&machine.lockstep, cheat, machine.simulation.tick)
	for tick in u64(6) ..= 8 {
		receive_input_record(&machine.lockstep, Input_Record{tick = tick, player = 1}, machine.simulation.tick)
	}
	run_lockstep_test_ticks(machine, content)
	confirmed := machine.simulation.players[0].position
	testing.expect(t, confirmed != predicted)
	rebuild_prediction(&machine.lockstep, &machine.simulation, content)
	testing.expect_value(t, lockstep_view_player(&machine.lockstep, &machine.simulation).position, confirmed)
}

// Single player has a window of zero: no prediction, the confirmed player.
@(test)
test_a_window_of_zero_predicts_nothing :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	lockstep := make_single_player_lockstep(simulation.tick, {})
	defer destroy_lockstep(&lockstep)
	testing.expect(t, stamp_local_record(&lockstep, simulation.tick, Input_Frame{move = {0, 1}}))
	testing.expect(t, !stamp_local_record(&lockstep, simulation.tick, Input_Frame{move = {0, 1}}))
	rebuild_prediction(&lockstep, &simulation, content)
	testing.expect(t, !lockstep.predicting)
	testing.expect_value(t, latency_window_ticks(0, 60), 1)
	testing.expect_value(t, latency_window_ticks(0.05, 60), 4)
}

// The set of radius one around the player: a missing chunk stalls the
// tick, its arrival lets it run, and a chunk outside the set is unloaded
// before the tick reads anything.
@(test)
test_the_simulated_chunk_set_stalls_and_keeps_only_its_chunks :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content.generator = &generator
	simulation.chunk_set = make_simulated_chunk_set(1, 1)
	outside := Chunk_Coordinate{5, 0, 5}
	load_chunk_now(&simulation.world, &simulation.records, &generator, outside)
	wanted := simulated_chunk_requests(&simulation)
	testing.expect(t, len(wanted) > 27)
	set := next_simulated_chunks(simulation.chunk_set, player_chunk_centres(simulation.players[:]))
	testing.expect_value(t, len(set), 27)
	for coordinate in set[1:] {
		generated := generate_chunk(&generator, coordinate)
		result := Chunk_Job_Result{kind = .Generate, coordinate = coordinate, chunk = generated.chunk, veins = generated.veins, outcrops = generated.outcrops, crates = generated.crates}
		queue_player_command(&simulation.player_commands, NO_PLAYER, Chunk_Ready_Command{result = result})
	}
	testing.expect(t, !simulated_chunks_ready(&simulation))
	testing.expect_value(t, len(simulation.arrived_chunks), 26)
	generated := generate_chunk(&generator, set[0])
	queue_player_command(&simulation.player_commands, NO_PLAYER, Chunk_Ready_Command{result = Chunk_Job_Result{kind = .Generate, coordinate = set[0], chunk = generated.chunk, veins = generated.veins, outcrops = generated.outcrops, crates = generated.crates}})
	testing.expect(t, simulated_chunks_ready(&simulation))
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, len(simulation.world.chunks), 27)
	testing.expect(t, outside not_in simulation.world.chunks)
	testing.expect_value(t, len(simulation.unloaded_chunks), 1)
	for coordinate in set {
		testing.expect(t, coordinate in simulation.world.chunks)
	}
	testing.expect_value(t, len(simulation.arrived_chunks), 0)
}

// A tick command while paused runs ticks without records: the commands
// the driver held go back to the simulation and apply.
@(test)
test_a_tick_command_applies_the_held_local_commands :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	lockstep := make_single_player_lockstep(simulation.tick, {})
	defer destroy_lockstep(&lockstep)
	queue_player_command(&simulation.player_commands, 0, Hotbar_Slot_Command{slot = 6})
	hold_local_commands(&lockstep, &simulation)
	testing.expect_value(t, len(simulation.player_commands), 0)
	control := Command_Control{pending_ticks = 1}
	release_local_commands(&lockstep, &simulation)
	run_command_tick(&simulation, content, &control)
	testing.expect_value(t, simulation.players[0].selected_hotbar_slot, 6)
	testing.expect_value(t, len(lockstep.local_commands), 0)
}

// A socket line runs where the commands apply, after the simulated chunk
// set was derived: a teleport moves the set from the next tick on, on
// every machine alike.
@(test)
test_a_socket_line_runs_after_the_chunk_set_is_derived :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	machine := make_lockstep_test_machine(content, &generator, 0, 0, chunk_set = true)
	defer destroy_lockstep_test_machine(machine)
	set_lockstep_member(&machine.lockstep, 1, Lockstep_Member{joined_tick = NEVER_TICK, left_tick = NEVER_TICK})
	run_one_local_tick(machine, content)
	before := player_chunk(machine.simulation.players[0])
	append(&machine.lockstep.local_lines, Socket_Line{line = clone_text("teleport 200 40 200")})
	run_one_local_tick(machine, content)
	moved := player_chunk(machine.simulation.players[0])
	testing.expect(t, moved != before)
	// The tick that ran the line derived its set from the old position.
	testing.expect(t, before in machine.simulation.chunk_set.chunks)
	testing.expect(t, moved not_in machine.simulation.chunk_set.chunks)
	run_one_local_tick(machine, content)
	testing.expect(t, moved in machine.simulation.chunk_set.chunks)
}

// One local record stamped, delivered and run, as single player does.
run_one_local_tick :: proc(machine: ^Lockstep_Test_Machine, content: Simulation_Content) {
	stamp_local_record(&machine.lockstep, machine.simulation.tick, {})
	deliver_outgoing_locally(&machine.lockstep, machine.simulation.tick)
	run_lockstep_test_ticks(machine, content)
}
