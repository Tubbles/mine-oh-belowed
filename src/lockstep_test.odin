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
	machine.lockstep.locals[0].player = local_player
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
	player := lockstep_local_player(machine.lockstep)
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
	testing.expect(t, machine.lockstep.locals[0].predicting)
	predicted := lockstep_view_player(&machine.lockstep, &machine.simulation, 0).position
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
	testing.expect_value(t, lockstep_view_player(&machine.lockstep, &machine.simulation, 0).position, predicted)

	// The remote player turns cheat speed on in tick 5, which the
	// prediction does not know: it falls behind the confirmed walk, and the
	// rebuild after the ticks replaces it.
	for _ in 0 ..< 4 {
		stamp_local_record(&machine.lockstep, machine.simulation.tick, walk)
	}
	rebuild_prediction(&machine.lockstep, &machine.simulation, content)
	predicted = lockstep_view_player(&machine.lockstep, &machine.simulation, 0).position
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
	testing.expect_value(t, lockstep_view_player(&machine.lockstep, &machine.simulation, 0).position, confirmed)
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
	testing.expect(t, !lockstep.locals[0].predicting)
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
	testing.expect_value(t, len(lockstep.locals[0].commands), 0)
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

// Three players on the save test's site, each its own input; the
// machine's local players by index (split screen, 0178).
make_split_screen_test_machine :: proc(content: Simulation_Content, generator: ^Generator, local_players: []int) -> ^Lockstep_Test_Machine {
	machine := make_lockstep_test_machine(content, generator, local_players[0], 2)
	append(&machine.simulation.players, make_player(player_start_on({8, 0, -20})))
	set_lockstep_member(&machine.lockstep, 2, Lockstep_Member{joined_tick = 0, left_tick = NEVER_TICK})
	for player in local_players[1:] {
		add_local_member(&machine.lockstep, player, machine.lockstep.locals[0].first_tick)
	}
	return machine
}

// The input of a player in a frame, whichever machine stamps it.
split_screen_test_input :: proc(simulation: ^Simulation_State, player, frame: int) -> Input_Frame {
	if frame % 40 == 11 {
		queue_player_command(&simulation.player_commands, player, Hotbar_Slot_Command{slot = (frame / 40 + player) % HOTBAR_SLOT_COUNT})
	}
	return recorded_input(frame + 97 * player)
}

// Frames of machines: every local player of every machine stamps its
// record, the records go round, the ready ticks run.
run_split_screen_test :: proc(machines: []^Lockstep_Test_Machine, content: Simulation_Content, ticks: u64) {
	for frame := 0; frame < 5000; frame += 1 {
		done := true
		for machine in machines {
			done &&= machine.simulation.tick >= ticks
		}
		if done {
			return
		}
		for machine in machines {
			for local, index in machine.lockstep.locals {
				input := split_screen_test_input(&machine.simulation, local.player, frame)
				hold_local_commands(&machine.lockstep, &machine.simulation)
				stamp_local_record(&machine.lockstep, machine.simulation.tick, input, index)
			}
		}
		relay_in_process(machines)
		for machine in machines {
			run_lockstep_test_ticks(machine, content)
		}
	}
}

// Two local players on one machine and one on another keep the state hash
// of three machines with one local player each fed the same inputs: how
// many viewports feed a machine changes nothing a tick reads.
@(test)
test_two_local_members_keep_the_hash_of_one_member_machines :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	couch := make_split_screen_test_machine(content, &generator, {0, 1})
	defer destroy_lockstep_test_machine(couch)
	remote := make_split_screen_test_machine(content, &generator, {2})
	defer destroy_lockstep_test_machine(remote)
	split := [?]^Lockstep_Test_Machine{couch, remote}
	run_split_screen_test(split[:], content, 600)
	singles: [3]^Lockstep_Test_Machine
	for &machine, player in singles {
		machine = make_split_screen_test_machine(content, &generator, {player})
	}
	defer for machine in singles {
		destroy_lockstep_test_machine(machine)
	}
	run_split_screen_test(singles[:], content, 600)
	testing.expect_value(t, couch.simulation.tick, remote.simulation.tick)
	for machine in singles {
		testing.expect_value(t, machine.simulation.tick, couch.simulation.tick)
		testing.expect_value(t, lockstep_state_hash(&machine.simulation), lockstep_state_hash(&couch.simulation))
	}
	testing.expect_value(t, lockstep_state_hash(&remote.simulation), lockstep_state_hash(&couch.simulation))
	testing.expect(t, couch.simulation.players[1].position != couch.simulation.players[0].position)
	start_player := make_player(player_start_on(LOCKSTEP_TEST_SECOND_PLAYER))
	defer destroy_player(start_player)
	testing.expect(t, couch.simulation.players[1].position != start_player.position)
}

// The test's own burner inserter far above the site, without fuel or
// neighbours, so it keeps the stone in its hand until a player takes it.
add_idle_test_inserter :: proc(simulation: ^Simulation_State, content: Simulation_Content, cell: World_Coordinate, stone: Item_Id) -> Entity_Handle {
	handle := add_entity(&simulation.world.entities, content.machines, test_machine(content.machines, "burner_inserter"), cell, 0)
	pool_get(&simulation.world.entities.inserters, handle).held = {stone, 1}
	return handle
}

// The hand and a slot as the sender's machine shows them, as a screen
// reads them.
shown_slot :: proc(simulation: ^Simulation_State, player: int, machine: Entity_Handle, slot: int) -> Held_Expectation {
	state := simulation.players[player]
	return shown_expectation(state.held, target_slots(state, &simulation.world.entities, machine)[slot])
}

// The slot commands a player queues on its own machine in a frame (0179),
// with the expectations a screen would read off the sender's state. Each
// player has its own idle inserter open. Player 0 lifts the inserter's
// hand onto the cursor and returns it; player 1 takes it into the
// inventory. Both then pick up and drag drop a stack with its return,
// drop and split on the inserter's fuel slot, spread a split over it,
// quick move into it and between the hotbar and the backpack, press
// Fill, sort, transfer a grid and drop a stack on the ground. The sort
// takes its order from the sender's own state.
slot_test_commands :: proc(simulation: ^Simulation_State, player, frame: int, inserter: Entity_Handle, stone: Item_Id, ranks: []u16) {
	list := &simulation.player_commands
	state := simulation.players[player]
	switch frame {
	case 4:
		queue_player_command(list, player, Inserter_Hand_Command{inserter = inserter, into_inventory = player == 1})
	case 10:
		queue_player_command(list, player, Return_Held_Command{})
	case 16:
		queue_player_command(list, player, Slot_Primary_Command{target = {NO_ENTITY, HOTBAR_SLOT_COUNT}, expects = shown_slot(simulation, player, NO_ENTITY, HOTBAR_SLOT_COUNT)})
	case 22:
		queue_player_command(list, player, Slot_Primary_Command{target = {NO_ENTITY, HOTBAR_SLOT_COUNT + 5}, expects = {hand = shown_item(state.held.stack), slot = ANY_ITEM}, keeps_origin = true})
		queue_player_command(list, player, Return_Held_Command{})
	case 28:
		queue_player_command(list, player, Slot_Primary_Command{target = {NO_ENTITY, HOTBAR_SLOT_COUNT + 5}, expects = shown_slot(simulation, player, NO_ENTITY, HOTBAR_SLOT_COUNT + 5)})
	case 34:
		queue_player_command(list, player, Slot_Primary_Command{target = {inserter, 0}, expects = shown_slot(simulation, player, inserter, 0)})
	case 40:
		queue_player_command(list, player, Slot_Split_Command{target = {inserter, 0}, expects = shown_slot(simulation, player, inserter, 0)})
	case 46:
		distribute := Distribute_Command{machine = inserter, hand = shown_item(state.held.stack), count = 1}
		queue_player_command(list, player, distribute)
	case 52:
		queue_player_command(list, player, Slot_Split_Command{target = {inserter, 0}, expects = shown_slot(simulation, player, inserter, 0)})
	case 58:
		queue_player_command(list, player, Return_Held_Command{})
	case 64:
		queue_player_command(list, player, Quick_Move_Command{machine = inserter, step = {kind = .All, target = {.Inventory, -1}, item = state.inventory.slots[HOTBAR_SLOT_COUNT + 5].item}})
		queue_player_command(list, player, Quick_Move_Command{machine = NO_ENTITY, step = {kind = .Stack, target = {.Hotbar, 2}}})
	case 70:
		queue_player_command(list, player, Transfer_Button_Command{machine = inserter, button = .Fill})
		queue_player_command(list, player, slot_sort_command(NO_ENTITY, inventory_grid(state.inventory), ranks))
	case 76:
		queue_player_command(list, player, Grid_Transfer_Command{machine = NO_ENTITY, transfer = {source = .Main, target = .Hotbar}})
	case 82:
		for slot, index in state.inventory.slots {
			if slot.item == stone && !stack_is_empty(slot) {
				queue_player_command(list, player, Slot_Primary_Command{target = {NO_ENTITY, index}, expects = shown_slot(simulation, player, NO_ENTITY, index)})
				break
			}
		}
	case 88:
		if drop, drops := drop_stack_command(state, -1); drops {
			queue_player_command(list, player, drop)
		}
	}
}

// Two machines whose players move stacks through every slot command keep
// the same state hash: the slot transfers are tick input like every
// other screen action.
@(test)
test_slot_commands_keep_two_machines_in_step :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	first := make_lockstep_test_machine(content, &generator, 0, 3)
	defer destroy_lockstep_test_machine(first)
	second := make_lockstep_test_machine(content, &generator, 1, 2)
	defer destroy_lockstep_test_machine(second)
	machines := [?]^Lockstep_Test_Machine{first, second}
	coal := test_item(content.items, "coal")
	stone := test_item(content.items, "stone")
	ranks := make([]u16, len(content.items.items), context.temp_allocator)
	for &rank, item in ranks {
		rank = u16(len(ranks) - item)
	}
	inserters: [2]Entity_Handle
	for machine in machines {
		for &player, index in machine.simulation.players {
			inserters[index] = add_idle_test_inserter(&machine.simulation, content, {-40 + 4 * i32(index), 90, -40}, stone)
			for &slot in player.inventory.slots {
				slot = EMPTY_STACK
			}
			player.inventory.slots[HOTBAR_SLOT_COUNT] = {coal, 9}
			player.inventory.slots[HOTBAR_SLOT_COUNT + 3] = {stone, 4}
			player.inventory.slots[2] = {stone, 2}
			player.held = EMPTY_HELD_STACK
			player.open_machine = inserters[index]
		}
	}
	loose_before := len(first.simulation.world.entities.loose_items.items)
	testing.expect_value(t, lockstep_state_hash(&first.simulation), lockstep_state_hash(&second.simulation))
	for frame := 0; first.simulation.tick < 160 || second.simulation.tick < 160; frame += 1 {
		for machine in machines {
			player := lockstep_local_player(machine.lockstep)
			slot_test_commands(&machine.simulation, player, frame, inserters[player], stone, ranks)
			hold_local_commands(&machine.lockstep, &machine.simulation)
			stamp_local_record(&machine.lockstep, machine.simulation.tick, {})
		}
		relay_in_process(machines[:])
		for machine in machines {
			run_lockstep_test_ticks(machine, content)
		}
		if first.simulation.tick == second.simulation.tick {
			testing.expectf(t, lockstep_state_hash(&first.simulation) == lockstep_state_hash(&second.simulation), "the hashes differ at tick %d", first.simulation.tick)
		}
		if frame > 1000 {
			testing.fail_now(t, "the machines stopped ticking")
		}
	}
	testing.expect_value(t, lockstep_state_hash(&first.simulation), lockstep_state_hash(&second.simulation))
	for machine in machines {
		simulation := &machine.simulation
		entities := &simulation.world.entities
		// Every command applied (none was stale), both inserters' hands
		// were taken, both dropped a stack, and no item was made or lost.
		testing.expect(t, !simulation_has_refusal(simulation, 0) && !simulation_has_refusal(simulation, 1))
		loose := entities.loose_items.items[loose_before:]
		testing.expect_value(t, len(loose), 2)
		for player in 0 ..< 2 {
			inserter := pool_get(&entities.inserters, inserters[player])
			testing.expect_value(t, inserter.held, EMPTY_STACK)
			testing.expect_value(t, simulation.players[player].held, EMPTY_HELD_STACK)
			coal_count := inventory_count({slots = inserter.slots[:]}, coal) + inventory_count(simulation.players[player].inventory, coal)
			testing.expect_value(t, coal_count, 9)
			testing.expect(t, inventory_count({slots = inserter.slots[:]}, coal) > 0)
		}
		stone_count := 0
		for item in loose {
			stone_count += item.item == stone ? int(item.count) : 0
		}
		for player in 0 ..< 2 {
			stone_count += inventory_count(simulation.players[player].inventory, stone)
		}
		testing.expect_value(t, stone_count, 14)
	}
}

// The field session's ticks whose records are there, the local records
// delivered as offline and the field set staged on the test's thread
// first (tick_field_test_simulation).
run_field_lockstep_test_ticks :: proc(session: ^Session, content: Simulation_Content, most := max(int)) {
	control: Command_Control
	answers := make([dynamic]Line_Answer, context.temp_allocator)
	deliver_outgoing_locally(&session.lockstep, session.simulation.tick)
	for count := 0; count < most && lockstep_records_ready(session.lockstep, session.simulation.tick); count += 1 {
		if !simulated_chunks_ready(&session.simulation) {
			stage_generated_field_set(&session.simulation)
		}
		run_session_tick(session, content, &control, &answers)
	}
}

// A field session whose player stood a second, its lockstep window ticks
// ahead.
start_field_lockstep_test_session :: proc(content: Game_Content, window: int) -> (session: ^Session, simulation_content: Simulation_Content) {
	session = start_field_test_session(test_field_game_config(), content)
	simulation_content = field_test_content(session, content)
	for _ in 0 ..< 60 {
		tick_field_test_simulation(&session.simulation, simulation_content, {})
	}
	session.lockstep.window = window
	return session, simulation_content
}

FIELD_PREDICTION_TEST_WALK :: Input_Frame {
	move       = {0, 1},
	look_delta = {40, 0},
	pressed    = {.Move},
}

// Field prediction (0182): with a window of three ticks the predicted
// feet and look after a walk press are where the three confirmed ticks
// put the player; the prediction leaves the simulation's hash, the walk
// counter and the field's queues alone, and a session that never
// predicts hashes alike after the same ticks.
@(test)
test_the_field_prediction_matches_the_confirmed_walk :: proc(t: ^testing.T) {
	content := make_field_test_game_content()
	session, simulation_content := start_field_lockstep_test_session(content, 3)
	defer end_session(session)
	unpredicted, unpredicted_content := start_field_lockstep_test_session(content, 0)
	defer end_session(unpredicted)
	state := &session.simulation
	start := state.players[0].field
	for _ in 0 ..< 3 {
		testing.expect(t, stamp_local_record(&session.lockstep, state.tick, FIELD_PREDICTION_TEST_WALK))
	}
	hash_before := lockstep_state_hash(state)
	walked_before := state.records.statistics.distance_walked_millimetres
	rebuild_prediction(&session.lockstep, state, simulation_content)
	testing.expect(t, session.lockstep.locals[0].predicting)
	predicted := lockstep_view_player(&session.lockstep, state, 0).field
	testing.expect(t, predicted.position != start.position, "the prediction walks")
	testing.expect(t, predicted.yaw != start.yaw, "the prediction turns")
	testing.expect_value(t, state.players[0].field.position, start.position)
	testing.expect_value(t, lockstep_state_hash(state), hash_before)
	testing.expect_value(t, state.records.statistics.distance_walked_millimetres, walked_before)
	testing.expect_value(t, len(state.field.edits), 0)
	testing.expect_value(t, len(state.field.placements), 0)

	tick_before := state.tick
	run_field_lockstep_test_ticks(session, simulation_content)
	testing.expect_value(t, state.tick, tick_before + 3)
	testing.expect_value(t, state.players[0].field.position, predicted.position)
	testing.expect_value(t, state.players[0].field.yaw, predicted.yaw)
	testing.expect_value(t, state.players[0].field.pitch, predicted.pitch)
	rebuild_prediction(&session.lockstep, state, simulation_content)
	testing.expect_value(t, lockstep_view_player(&session.lockstep, state, 0).field.position, predicted.position)

	for _ in 0 ..< 3 {
		tick_field_test_simulation(&unpredicted.simulation, unpredicted_content, FIELD_PREDICTION_TEST_WALK)
	}
	testing.expect_value(t, unpredicted.simulation.tick, state.tick)
	testing.expect_value(t, lockstep_state_hash(&unpredicted.simulation), lockstep_state_hash(state))
}

// A wall of stone raised in front of the player after the prediction
// walked (another player's place, which the prediction does not know):
// the confirmed walk stops short of the predicted feet. Mid window, with
// one input confirmed, the stale prediction still stands past the wall
// and the rebuild snaps it to where the confirmed walk ends, two inputs
// ahead of the confirmed player; after the last ticks the view is the
// confirmed feet.
@(test)
test_a_field_prediction_into_a_wall_snaps_to_the_confirmed_feet :: proc(t: ^testing.T) {
	content := make_field_test_game_content()
	session, simulation_content := start_field_lockstep_test_session(content, 3)
	defer end_session(session)
	state := &session.simulation
	// Backwards, into the cabin: the closed inner hatch stands 0.75 m
	// ahead of the spawn (0198), between the player and a wall ahead.
	walk := Input_Frame{move = {0, -1}, pressed = {.Move}}
	for _ in 0 ..< 3 {
		testing.expect(t, stamp_local_record(&session.lockstep, state.tick, walk))
	}
	rebuild_prediction(&session.lockstep, state, simulation_content)
	predicted := lockstep_view_player(&session.lockstep, state, 0).field.position

	player := state.players[0].field
	tuning := simulation_content.field.tuning
	wall_radius := metres_to_position_units(1)
	behind := -field_player_heading(player)
	wall_distance := tuning.capsule_radius + wall_radius
	wall := Field_Edit {
		mode     = .Place,
		brush    = Field_Brush{shape = .Sphere, radius = wall_radius, rate = 127},
		centre   = player.position + World_Position(fixed_scale(behind, wall_distance) + fixed_scale(player.up, tuning.capsule_height / 2)),
		up       = player.up,
		material = .Stone,
		budget   = max(i64),
	}
	apply_field_edit(&state.field.world, state.field.spacing_millimetres, wall)

	run_field_lockstep_test_ticks(session, simulation_content, 1)
	testing.expect_value(t, lockstep_view_player(&session.lockstep, state, 0).field.position, predicted)
	rebuild_prediction(&session.lockstep, state, simulation_content)
	testing.expect(t, session.lockstep.locals[0].predicting)
	mid_window := lockstep_view_player(&session.lockstep, state, 0).field.position
	testing.expect(t, mid_window != state.players[0].field.position, "two inputs are still predicted")
	testing.expect(t, mid_window != predicted, "the rebuild knows the wall")

	run_field_lockstep_test_ticks(session, simulation_content)
	confirmed := state.players[0].field.position
	testing.expect_value(t, mid_window, confirmed)
	predicted_progress := fixed_dot(cast([3]i64)(predicted - player.position), behind)
	confirmed_progress := fixed_dot(cast([3]i64)(confirmed - player.position), behind)
	testing.expectf(t, confirmed_progress < predicted_progress, "the wall stops the walk: confirmed %d, predicted %d", confirmed_progress, predicted_progress)
	rebuild_prediction(&session.lockstep, state, simulation_content)
	testing.expect_value(t, lockstep_view_player(&session.lockstep, state, 0).field.position, confirmed)
}

// One session queues the placement editor's commit (0215), the other
// applies it from the encoded record: both place the assembler at the
// same tick and hash the same.
@(test)
test_two_sessions_committing_a_placement_hash_the_same :: proc(t: ^testing.T) {
	hashes: [2]u64
	for index in 0 ..< 2 {
		simulation, content, _, frame := make_placement_editor_test(t, "assembler_1", {"assembler_1", 1})
		defer destroy_simulation(&simulation)
		command: Player_Command = Machine_Placement_Command{machine = test_machine(content.machines, "assembler_1"), frame = frame.id, cell = {2, 1, 2}}
		if index == 1 {
			// Through the input record as the host relays it (relay_in_process).
			sent := Input_Record{tick = 1, player = 0, commands = make([dynamic]Player_Command, context.temp_allocator)}
			append(&sent.commands, command)
			message := record_message(sent)
			reader := Byte_Reader{data = message[1:]}
			received, ok := decode_input_record(&reader)
			defer destroy_input_record(received)
			testing.expect(t, ok && len(received.commands) == 1)
			if len(received.commands) == 1 {
				testing.expect_value(t, received.commands[0].(Machine_Placement_Command), command.(Machine_Placement_Command))
				command = received.commands[0]
			}
		}
		queue_player_command(&simulation.player_commands, 0, command)
		apply_player_commands(&simulation, content)
		tick_field_simulation(&simulation, content, {})
		common := entity_common(&simulation.world.entities, entity_at(&simulation.world.entities, EDITOR_TEST_CENTRE, frame.id))
		testing.expect(t, common != nil && common.origin == World_Coordinate{2, 1, 2})
		hashes[index] = simulation_state_hash(&simulation)
	}
	testing.expect_value(t, hashes[0], hashes[1])
}
