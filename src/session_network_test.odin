package game

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:time"
import "platform"

LOOPBACK_TEST_WORLD_NAME :: "Loopback world"
// A host on a loopback port the system picks, without the discovery.
LOOPBACK_HOSTING_PLAN :: Hosting_Plan{port_count = 1, address = .Loopback}

// A third machine joins two playing ones (0190): it gets the host's
// world without a player, the two play on past the snapshot's tick while
// it restores (no record of it exists), it runs the relayed ticks, and its
// entry is added at the join tick every machine agrees on, after which
// all three keep one hash.
@(test)
test_a_joiner_restores_while_the_others_play_and_reaches_their_hash :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	host := make_lockstep_test_machine(content, &generator, 0, 0)
	defer destroy_lockstep_test_machine(host)
	guest := make_lockstep_test_machine(content, &generator, 1, 2)
	defer destroy_lockstep_test_machine(guest)
	playing := [?]^Lockstep_Test_Machine{host, guest}
	play_lockstep_test_frames(playing[:], content, 0, 120)

	snapshot_tick := host.simulation.tick
	payload := encode_join_snapshot(&host.simulation, &host.lockstep, content, "joined")
	joiner := new(Lockstep_Test_Machine)
	defer destroy_lockstep_test_machine(joiner)
	snapshot, chunk_set_enabled, ok := decode_join_snapshot(payload)
	if !testing.expect(t, ok) {
		return
	}
	file, problem := parse_world_file(snapshot.files.world, context.temp_allocator)
	if !testing.expect_value(t, problem, "") {
		destroy_join_records(&snapshot.records)
		return
	}
	joiner.simulation = make_save_test_simulation(&generator, content)
	testing.expect_value(t, load_world_from_files(&joiner.simulation, content, snapshot.files, file, "joined"), "")
	load_save_test_chunks(&joiner.simulation.world, &joiner.simulation.records, &generator)
	joiner.lockstep = make_single_player_lockstep(joiner.simulation.tick, player_start_on({}))
	adopt_join_snapshot(&joiner.simulation, &joiner.lockstep, snapshot, chunk_set_enabled, 1)
	testing.expect_value(t, len(joiner.lockstep.locals), 0)
	testing.expect_value(t, len(joiner.lockstep.members), 2)
	testing.expect_value(t, joiner.simulation.tick, snapshot_tick)
	testing.expect_value(t, lockstep_state_hash(&joiner.simulation), lockstep_state_hash(&host.simulation))

	// The joiner restores: the others play on, their records reach it.
	machines := [?]^Lockstep_Test_Machine{host, guest, joiner}
	for frame in 120 ..< 240 {
		for machine in playing {
			hold_local_commands(&machine.lockstep, &machine.simulation)
			stamp_local_record(&machine.lockstep, machine.simulation.tick, lockstep_test_input(machine, frame))
		}
		relay_in_process(machines[:])
		for machine in playing {
			run_lockstep_test_ticks(machine, content)
		}
	}
	testing.expect(t, host.simulation.tick > snapshot_tick + 100)
	testing.expect_value(t, joiner.simulation.tick, snapshot_tick)

	// Restored, it runs the relayed ticks and catches up.
	run_lockstep_test_ticks(joiner, content)
	testing.expect_value(t, joiner.simulation.tick, host.simulation.tick)
	testing.expect_value(t, lockstep_state_hash(&joiner.simulation), lockstep_state_hash(&host.simulation))

	// Its player, as the host's next_join gives it: from the tick after
	// the newest record relayed.
	frontier := host.simulation.tick
	for record in host.lockstep.records {
		frontier = max(frontier, record.tick)
	}
	join_tick := frontier + 1
	player, adds_entry := joining_player_index(host.lockstep, len(host.simulation.players), join_tick)
	testing.expect_value(t, player, 2)
	member := Lockstep_Member{joined_tick = join_tick, left_tick = NEVER_TICK, adds_entry = adds_entry}
	for machine in machines {
		set_lockstep_member(&machine.lockstep, player, member)
	}
	add_local_member(&joiner.lockstep, player, join_tick)
	play_lockstep_test_frames(machines[:], content, 240, 540)
	testing.expect(t, joiner.simulation.tick > join_tick + 200)
	for machine in machines {
		testing.expect_value(t, len(machine.simulation.players), 3)
	}
	testing.expect_value(t, host.simulation.tick, joiner.simulation.tick)
	testing.expect_value(t, lockstep_state_hash(&joiner.simulation), lockstep_state_hash(&host.simulation))
	testing.expect_value(t, lockstep_state_hash(&guest.simulation), lockstep_state_hash(&host.simulation))
}

// The frames of an in-process session: every machine stamps, the relay
// delivers, every machine runs what is ready.
play_lockstep_test_frames :: proc(machines: []^Lockstep_Test_Machine, content: Simulation_Content, first, last: int) {
	for frame in first ..< last {
		for machine in machines {
			hold_local_commands(&machine.lockstep, &machine.simulation)
			stamp_local_record(&machine.lockstep, machine.simulation.tick, lockstep_test_input(machine, frame))
		}
		relay_in_process(machines)
		for machine in machines {
			run_lockstep_test_ticks(machine, content)
		}
	}
}

// --server: no window, no local player, nobody connected; the clock
// paces the ticks and the port is listened on.
@(test)
test_a_server_ticks_without_a_window :: proc(t: ^testing.T) {
	content := make_save_test_content()
	session := new(Session)
	session.generator = make_test_generator(DEFAULT_WORLD_SEED)
	session.simulation = make_save_test_simulation(&session.generator, content)
	defer destroy_simulation(&session.simulation)
	load_save_test_chunks(&session.simulation.world, &session.simulation.records, &session.generator)
	session.technologies = content.technologies
	session.accumulator = make_tick_accumulator(session.simulation.tick_rate)
	session.streaming = start_chunk_streaming(&session.generator, make_test_registry(), false, TEST_WORKER_COUNT)
	defer stop_chunk_streaming(&session.streaming)
	defer free(session)
	defer destroy_lockstep(&session.lockstep)
	defer destroy_session_network(&session.network)
	server: Server_State
	if !testing.expect_value(t, start_server(&server, session, Game_Content{simulation_content = content}, 0, LOOPBACK_HOSTING_PLAN), "") {
		return
	}
	testing.expect_value(t, session.network.role, Network_Role.Host)
	testing.expect_value(t, lockstep_local_player(session.lockstep), NO_PLAYER)
	start_tick := session.simulation.tick
	ran := 0
	for _ in 0 ..< 30 {
		ran += run_server_frame(&server, 1.0 / 60.0)
	}
	testing.expect_value(t, ran, 30)
	testing.expect_value(t, session.simulation.tick, start_tick + 30)
}

// The end to end join over the loopback, through the real transport and
// the game's own join and frame code (update_joining, update_session): a
// server, a first client that takes the save's entry and plays, and a
// second client that joins while the first one's records flow and gets a
// new entry. No machine sees a hash mismatch, no frame of the second runs
// before its entry exists, and when the first client drops out mid
// window the others play on.
@(test)
test_two_clients_join_a_server_over_the_loopback :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_loopback_test_server(content)
	defer destroy_loopback_test_server(host)
	address := fmt.tprintf("127.0.0.1:%d", host.session.network.listener.port)
	first := make_joining_test_frame(content, address)
	defer destroy_joining_test_frame(first)
	second := make_joining_test_frame(content, "")
	defer destroy_joining_test_frame(second)
	if !testing.expect(t, run_join_test_frames(host, {first}, Join_Test_Goal{entered = 1})) {
		return
	}
	testing.expect_value(t, lockstep_local_player(first.session.lockstep), 0)
	// The first plays a second before the second asks to join.
	if !testing.expect(t, run_join_test_frames(host, {first}, Join_Test_Goal{entered = 1, tick = u64(TEST_TICK_RATE)})) {
		return
	}
	start_joining(&second.joining.network, address, TEST_TICK_RATE)
	if !testing.expect(t, run_join_test_frames(host, {first, second}, Join_Test_Goal{entered = 2})) {
		return
	}
	testing.expect_value(t, lockstep_local_player(second.session.lockstep), 1)
	testing.expect_value(t, len(second.session.simulation.players), 2)
	played_to := host.session.simulation.tick + 2 * STATE_HASH_INTERVAL_TICKS
	testing.expect(t, run_join_test_frames(host, {first, second}, Join_Test_Goal{tick = played_to}))
	// The first drops out without a word: the server lets it leave from
	// the tick after its last record and the other plays on.
	platform.close_connection(&first.session.network.peers[0].connection, "the test dropped it")
	testing.expect(t, run_join_test_frames(host, {second}, Join_Test_Goal{tick = played_to + STATE_HASH_INTERVAL_TICKS}))
	testing.expect_value(t, host.session.network.mismatch_count, 0)
	testing.expect_value(t, first.session.network.mismatch_count, 0)
	testing.expect_value(t, second.session.network.mismatch_count, 0)
	testing.expect_value(t, len(host.session.simulation.players), 2)
	testing.expect(t, host.session.lockstep.members[0].left_tick != NEVER_TICK)
}

// A server of the save test site with a new world's settings, started
// the way the game starts a saved world (start_session from the save's
// bytes, as a joiner does), its simulated chunk set radius 1 and streamed
// by real workers, on a loopback port the system chose.
make_loopback_test_server :: proc(content: Simulation_Content, plan := LOOPBACK_HOSTING_PLAN) -> ^Server_State {
	session := make_loopback_test_session(content)
	server := new(Server_State)
	problem := start_server(server, session, Game_Content{simulation_content = content}, 0, plan)
	assert(problem == "", problem)
	return server
}

// The session of make_loopback_test_server, offline.
make_loopback_test_session :: proc(content: Simulation_Content) -> ^Session {
	config := test_game_config()
	config.simulated_chunk_radius_horizontal, config.simulated_chunk_radius_vertical = 1, 1
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	source := make_save_test_simulation(&generator, content)
	load_save_test_chunks(&source.world, &source.records, &generator)
	build_save_test_site(&source, content)
	source.world.settings = world_settings_from_file(generator.seed, default_world_file_settings(config))
	files := encode_save_files(&source, content, "loopback", 0)
	destroy_simulation(&source)
	file, problem := parse_world_file(files.world, context.temp_allocator)
	assert(problem == "", problem)
	plan := Session_Plan{loading = true, seed = file.seed, settings = file.settings, file = file, files = &files}
	game_content := Game_Content{simulation_content = content}
	session: ^Session
	session, problem = start_session(plan, config, game_content, generator)
	assert(problem == "", problem)
	delete(session.save.location.display_name)
	session.save.location.display_name = strings.clone(LOOPBACK_TEST_WORLD_NAME)
	return session
}

destroy_loopback_test_server :: proc(server: ^Server_State) {
	end_session(server.session)
	free(server)
}

// A game's frame state without a window, joining address when given.
make_joining_test_frame :: proc(content: Simulation_Content, address: string) -> ^Frame_State {
	state := new(Frame_State)
	state.config = test_game_config()
	state.content = Game_Content{simulation_content = content}
	state.base_generator = make_test_generator(DEFAULT_WORLD_SEED)
	state.frame_seconds = 1.0 / f32(TEST_TICK_RATE)
	state.viewport_count = 1
	if address != "" {
		start_joining(&state.joining.network, address, TEST_TICK_RATE)
	}
	return state
}

destroy_joining_test_frame :: proc(state: ^Frame_State) {
	remove_extra_viewports(state)
	if state.session != nil {
		end_session(state.session)
		destroy_session_views(&state.viewports[0].interaction.session_views)
	}
	destroy_session_join(&state.joining)
	destroy_ui_state(&state.viewports[0].interaction.ui)
	free(state)
}

// How many clients have entered their world, or the tick every entered
// client reached.
Join_Test_Goal :: struct {
	entered: int,
	tick:    u64,
}

join_test_goal_reached :: proc(clients: []^Frame_State, goal: Join_Test_Goal) -> bool {
	entered := 0
	for client in clients {
		if client.session == nil {
			continue
		}
		entered += 1
		if client.session.simulation.tick < goal.tick {
			return false
		}
	}
	return entered >= goal.entered
}

// Server and client frames until the goal, false after a minute. The
// server also runs after every client, so a client's records reach a
// joiner right behind its snapshot, before the joiner reads either.
run_join_test_frames :: proc(server: ^Server_State, clients: []^Frame_State, goal: Join_Test_Goal) -> bool {
	start := time.tick_now()
	for time.tick_since(start) < time.Minute {
		run_server_frame(server, 1.0 / f64(TEST_TICK_RATE))
		for client in clients {
			run_client_test_frame(client)
			run_server_frame(server, 0)
		}
		if join_test_goal_reached(clients, goal) {
			return true
		}
		time.sleep(100 * time.Microsecond)
	}
	return false
}

// The game's frame minus input, UI and drawing: the join until the world
// is entered, then the session's update and the frame's read of the local
// player (which a missing entry would fail).
run_client_test_frame :: proc(state: ^Frame_State) {
	switch {
	case state.session != nil:
		assign_waiting_players(state)
		update_session(state, frame_simulation_content(state))
		player := session_local_player(state.session)
		assert(player != nil)
	case join_active(state.joining):
		update_joining(state)
	}
}

// Split screen on a joined machine (0178): a second local player asked of
// the server over the machine's one connection gets a new entry, both
// players' records flow on it, the hashes agree, and the guest's leaving
// keeps its entry while the machine plays on.
@(test)
test_a_joined_machine_adds_and_removes_a_local_player :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_loopback_test_server(content)
	defer destroy_loopback_test_server(host)
	address := fmt.tprintf("127.0.0.1:%d", host.session.network.listener.port)
	couch := make_joining_test_frame(content, address)
	defer destroy_joining_test_frame(couch)
	if !testing.expect(t, run_join_test_frames(host, {couch}, Join_Test_Goal{entered = 1, tick = u64(TEST_TICK_RATE)})) {
		return
	}
	testing.expect(t, add_viewport(couch, 9, {}))
	testing.expect_value(t, couch.viewports[1].player, NO_PLAYER)
	played_to := host.session.simulation.tick + 2 * STATE_HASH_INTERVAL_TICKS
	if !testing.expect(t, run_join_test_frames(host, {couch}, Join_Test_Goal{tick = played_to})) {
		return
	}
	testing.expect_value(t, couch.viewports[1].player, 1)
	testing.expect_value(t, len(couch.session.lockstep.locals), 2)
	testing.expect_value(t, len(host.session.simulation.players), 2)
	testing.expect_value(t, len(host.session.network.peers), 1)
	testing.expect_value(t, host.session.network.peers[0].player_count, 2)
	remove_viewport(couch, 1)
	testing.expect(t, run_join_test_frames(host, {couch}, Join_Test_Goal{tick = played_to + STATE_HASH_INTERVAL_TICKS}))
	testing.expect_value(t, host.session.network.peers[0].player_count, 1)
	testing.expect(t, host.session.lockstep.members[1].left_tick != NEVER_TICK)
	testing.expect_value(t, len(couch.session.simulation.players), 2)
	testing.expect_value(t, host.session.network.mismatch_count, 0)
	testing.expect_value(t, couch.session.network.mismatch_count, 0)
}

// A guest viewport on a joined machine that leaves before the host's
// answer: the answer's member leaves at once, so no machine waits for
// records that never come, and the session plays on.
@(test)
test_a_guest_leaving_before_the_hosts_answer_stalls_nothing :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_loopback_test_server(content)
	defer destroy_loopback_test_server(host)
	address := fmt.tprintf("127.0.0.1:%d", host.session.network.listener.port)
	couch := make_joining_test_frame(content, address)
	defer destroy_joining_test_frame(couch)
	if !testing.expect(t, run_join_test_frames(host, {couch}, Join_Test_Goal{entered = 1, tick = u64(TEST_TICK_RATE)})) {
		return
	}
	testing.expect(t, add_viewport(couch, 9, {}))
	remove_viewport(couch, 1)
	testing.expect_value(t, couch.viewport_count, 1)
	played_to := host.session.simulation.tick + 2 * STATE_HASH_INTERVAL_TICKS
	testing.expect(t, run_join_test_frames(host, {couch}, Join_Test_Goal{tick = played_to}))
	testing.expect(t, host.session.simulation.tick >= played_to)
	testing.expect_value(t, len(couch.session.lockstep.locals), 1)
	testing.expect_value(t, couch.session.network.cancelled_local_players, 0)
	testing.expect_value(t, host.session.network.peers[0].player_count, 1)
	testing.expect(t, len(host.session.lockstep.members) == 2 && host.session.lockstep.members[1].left_tick == host.session.lockstep.members[1].joined_tick)
	testing.expect_value(t, host.session.network.mismatch_count, 0)
}

// A game hosting its world (the pause menu's way, not --server), on a
// loopback port the system chose: the save test's site, its own player
// the save's entry.
make_hosting_test_frame :: proc(content: Simulation_Content, plan := LOOPBACK_HOSTING_PLAN) -> ^Frame_State {
	server := make_loopback_test_server(content, plan)
	session := server.session
	free(server)
	// The server's network keeps hosting; its driver gets the game's own
	// player.
	destroy_lockstep(&session.lockstep)
	session.lockstep = make_single_player_lockstep(session.simulation.tick, session.start.player)
	state := make_joining_test_frame(content, "")
	state.settings = DEFAULT_SETTINGS
	enter_session(state, session)
	return state
}

// Frames of a hosting game and its clients until every machine reached
// the tick, false after a minute.
run_hosting_test_frames :: proc(host: ^Frame_State, clients: []^Frame_State, tick: u64) -> bool {
	start := time.tick_now()
	for time.tick_since(start) < time.Minute {
		run_client_test_frame(host)
		reached := host.session.simulation.tick >= tick
		for client in clients {
			run_client_test_frame(client)
			reached &&= client.session != nil && client.session.simulation.tick >= tick
		}
		if reached {
			return true
		}
		time.sleep(100 * time.Microsecond)
	}
	return false
}

// The host adds a split screen guest while a client plays and removes it
// again: the client learns both member changes and both machines' hashes
// agree through them.
@(test)
test_a_host_adds_and_removes_a_local_guest_with_a_client_playing :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_hosting_test_frame(content)
	defer destroy_joining_test_frame(host)
	address := fmt.tprintf("127.0.0.1:%d", host.session.network.listener.port)
	client := make_joining_test_frame(content, address)
	defer destroy_joining_test_frame(client)
	start := time.tick_now()
	for client.session == nil && time.tick_since(start) < time.Minute {
		run_client_test_frame(host)
		run_client_test_frame(client)
		time.sleep(100 * time.Microsecond)
	}
	if !testing.expect(t, client.session != nil) {
		return
	}
	testing.expect(t, add_viewport(host, 9, {}))
	guest := host.viewports[1].player
	played_to := host.session.simulation.tick + STATE_HASH_INTERVAL_TICKS
	if !testing.expect(t, run_hosting_test_frames(host, {client}, played_to)) {
		return
	}
	testing.expect_value(t, len(client.session.simulation.players), 3)
	testing.expect(t, member_connected(client.session.lockstep.members[guest], client.session.simulation.tick))
	remove_viewport(host, 1)
	left_to := host.session.simulation.tick + 2 * STATE_HASH_INTERVAL_TICKS
	testing.expect(t, run_hosting_test_frames(host, {client}, left_to))
	testing.expect(t, client.session.lockstep.members[guest].left_tick != NEVER_TICK)
	testing.expect_value(t, client.session.lockstep.members[guest].left_tick, host.session.lockstep.members[guest].left_tick)
	testing.expect_value(t, host.session.network.mismatch_count, 0)
	testing.expect_value(t, client.session.network.mismatch_count, 0)
	testing.expect(t, len(host.session.network.hashes) > 0)
}

// Host and client frames until the host sent the client its world (the
// snapshot), false after a minute.
run_until_world_sent :: proc(host: ^Frame_State, client: ^Frame_State) -> bool {
	network := &host.session.network
	start := time.tick_now()
	for time.tick_since(start) < time.Minute {
		run_client_test_frame(host)
		if len(network.peers) > 0 && network.peers[len(network.peers) - 1].receives_records {
			return true
		}
		run_client_test_frame(client)
		time.sleep(100 * time.Microsecond)
	}
	return false
}

// Host frames alone (the joiners restoring) until it reached the tick,
// false after a minute.
run_host_alone_until :: proc(host: ^Frame_State, tick: u64) -> bool {
	start := time.tick_now()
	for host.session.simulation.tick < tick && time.tick_since(start) < time.Minute {
		run_client_test_frame(host)
		time.sleep(100 * time.Microsecond)
	}
	return host.session.simulation.tick >= tick
}

// A joiner that drops while it restores (0190): the host played on past
// the snapshot's tick without a record of it, and its leaving changes no
// member and holds no tick; the host is alone again.
@(test)
test_a_joiner_dropped_while_it_restores_leaves_nothing_behind :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_hosting_test_frame(content)
	defer destroy_joining_test_frame(host)
	address := fmt.tprintf("127.0.0.1:%d", host.session.network.listener.port)
	client := make_joining_test_frame(content, address)
	defer destroy_joining_test_frame(client)
	if !testing.expect(t, run_until_world_sent(host, client)) {
		return
	}
	members := len(host.session.lockstep.members)
	snapshot_tick := host.session.simulation.tick
	testing.expect(t, !session_alone(host.session.network))
	if !testing.expect(t, run_host_alone_until(host, snapshot_tick + 60)) {
		return
	}
	testing.expect_value(t, host.session.network.peers[0].player_count, 0)
	testing.expect_value(t, session_player_count(host.session.lockstep), 1)
	destroy_session_join(&client.joining)
	dropped_tick := host.session.simulation.tick
	testing.expect(t, run_host_alone_until(host, dropped_tick + 60))
	testing.expect_value(t, len(host.session.network.peers), 0)
	testing.expect(t, session_alone(host.session.network))
	testing.expect_value(t, len(host.session.lockstep.members), members)
	testing.expect_value(t, session_player_count(host.session.lockstep), 1)
}

// Two joiners (0190): the first gets the world and restores (its frames
// do not run) while the host plays on and the second joins and arrives;
// then the first arrives too, and all three keep one hash.
@(test)
test_a_second_joiner_arrives_while_the_first_restores :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_hosting_test_frame(content)
	defer destroy_joining_test_frame(host)
	address := fmt.tprintf("127.0.0.1:%d", host.session.network.listener.port)
	first := make_joining_test_frame(content, address)
	defer destroy_joining_test_frame(first)
	second := make_joining_test_frame(content, "")
	defer destroy_joining_test_frame(second)
	if !testing.expect(t, run_until_world_sent(host, first)) {
		return
	}
	snapshot_tick := host.session.simulation.tick
	start_joining(&second.joining.network, address, TEST_TICK_RATE)
	start := time.tick_now()
	for second.session == nil && time.tick_since(start) < time.Minute {
		run_client_test_frame(host)
		run_client_test_frame(second)
		time.sleep(100 * time.Microsecond)
	}
	if !testing.expect(t, second.session != nil) {
		return
	}
	testing.expect(t, host.session.simulation.tick > snapshot_tick)
	testing.expect_value(t, host.session.network.peers[0].player_count, 0)
	testing.expect_value(t, lockstep_local_player(second.session.lockstep), 1)
	testing.expect_value(t, session_player_count(host.session.lockstep), 2)
	played_to := host.session.simulation.tick + 2 * STATE_HASH_INTERVAL_TICKS
	if !testing.expect(t, run_hosting_test_frames(host, {first, second}, played_to)) {
		return
	}
	testing.expect_value(t, lockstep_local_player(first.session.lockstep), 2)
	for machine in ([?]^Frame_State{host, first, second}) {
		testing.expect_value(t, len(machine.session.simulation.players), 3)
		testing.expect_value(t, machine.session.network.mismatch_count, 0)
	}
	testing.expect_value(t, session_player_count(host.session.lockstep), 3)
	testing.expect(t, len(host.session.network.hashes) > 0)
}

// A client's records come one after another and not past its window and
// the margin: one far ahead would hold every machine.
@(test)
test_a_client_record_out_of_order_or_too_far_ahead_is_refused :: proc(t: ^testing.T) {
	peer := Peer_Player{last_tick = 99, joined_tick = 50}
	testing.expect(t, record_tick_expected(peer, 3, 100, 98))
	testing.expect(t, !record_tick_expected(peer, 3, 99, 98))
	testing.expect(t, !record_tick_expected(peer, 3, 101, 98))
	far := Peer_Player{last_tick = 1000, joined_tick = 5}
	testing.expect(t, !record_tick_expected(far, 3, 1001, 10))
	testing.expect(t, record_tick_expected(far, 3, 1001, 1001 - 3 - RECORD_TICK_MARGIN))
}

// Another build or other content tables are refused with the reason.
@(test)
test_a_join_from_another_build_or_content_is_refused :: proc(t: ^testing.T) {
	content := make_save_test_content()
	same := Join_Request{window = 2, build = BUILD_STAMP, content_hash = content_tables_hash(content)}
	testing.expect_value(t, join_refusal(same, content), "")
	other_build := same
	other_build.build = "0.0.0 elsewhere"
	testing.expect(t, strings.contains(join_refusal(other_build, content), "build"))
	other_content := same
	other_content.content_hash += 1
	testing.expect(t, strings.contains(join_refusal(other_content, content), "content"))
	message := join_request_message(same.window, same.build, same.content_hash)
	reader := Byte_Reader{data = message[1:]}
	decoded, ok := decode_join_request(&reader)
	testing.expect(t, ok)
	testing.expect_value(t, decoded, same)
}

// Reports the host can never compare go, and one machine cannot pile up
// more than MAXIMUM_PENDING_HASH_REPORTS.
@(test)
test_old_hash_reports_are_pruned :: proc(t: ^testing.T) {
	network: Session_Network
	defer destroy_session_network(&network)
	append(&network.reports, Pending_Hash_Report{tick = STATE_HASH_INTERVAL_TICKS, hash = 1, machine = clone_text("a")})
	append(&network.reports, Pending_Hash_Report{tick = 40 * STATE_HASH_INTERVAL_TICKS, hash = 1, machine = clone_text("a")})
	record_host_hash(&network, 20 * STATE_HASH_INTERVAL_TICKS, 7)
	testing.expect_value(t, len(network.reports), 1)
	testing.expect_value(t, network.reports[0].tick, 40 * STATE_HASH_INTERVAL_TICKS)
	testing.expect_value(t, pending_reports_of(network, "a"), 1)
	testing.expect_value(t, network.mismatch_count, 0)
}

// The server empties what only a UI would, and a failed save waits for
// the next interval.
@(test)
test_the_server_clears_its_events_and_a_failed_save_waits :: proc(t: ^testing.T) {
	content := make_save_test_content()
	session := new(Session)
	session.generator = make_test_generator(DEFAULT_WORLD_SEED)
	session.simulation = make_save_test_simulation(&session.generator, content)
	defer destroy_simulation(&session.simulation)
	session.technologies = content.technologies
	session.accumulator = make_tick_accumulator(session.simulation.tick_rate)
	session.streaming = start_chunk_streaming(&session.generator, make_test_registry(), false, TEST_WORKER_COUNT)
	defer stop_chunk_streaming(&session.streaming)
	defer free(session)
	defer destroy_lockstep(&session.lockstep)
	defer destroy_session_network(&session.network)
	server := Server_State{session = session, content = Game_Content{simulation_content = content}}
	session.lockstep = make_server_lockstep(session)
	append(&session.simulation.events, Simulation_Event{kind = .Action_Refused})
	append(&session.simulation.quests.notices, Quest_Message{tick = 1})
	run_server_frame(&server, 0)
	testing.expect_value(t, len(session.simulation.events), 0)
	testing.expect_value(t, len(session.simulation.quests.notices), 0)
	// Saving is off for this session, so the save fails.
	session.ticks_since_save = 123
	testing.expect(t, save_server_world(&server) != "")
	testing.expect_value(t, session.ticks_since_save, 0)
}

// Free crafting (0234) is not saved, so the join snapshot carries it as
// it carries cheat speed.
@(test)
test_the_join_snapshot_carries_free_crafting :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	host := make_lockstep_test_machine(content, &generator, 0, 0)
	defer destroy_lockstep_test_machine(host)
	host.simulation.free_crafting = true
	payload := encode_join_snapshot(&host.simulation, &host.lockstep, content, "joined")
	snapshot, chunk_set_enabled, ok := decode_join_snapshot(payload)
	if !testing.expect(t, ok) {
		return
	}
	testing.expect(t, snapshot.free_crafting)
	simulation := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&simulation)
	lockstep := make_single_player_lockstep(simulation.tick, player_start_on({}))
	defer destroy_lockstep(&lockstep)
	adopt_join_snapshot(&simulation, &lockstep, snapshot, chunk_set_enabled, 1)
	testing.expect(t, simulation.free_crafting)
}
