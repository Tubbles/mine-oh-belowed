package game

import "core:net"
import "core:testing"
import "core:time"
import "platform"

// A host on a loopback port the system picks, answering the discovery on
// a port the system picks.
LOOPBACK_DISCOVERY_PLAN :: Hosting_Plan{port_count = 1, address = .Loopback, discovery = true}

// Queries and host frames until the list holds count games, false after
// the network test timeout.
query_until_listed :: proc(query: ^Lan_Query, multiplayer: ^Multiplayer_State, hosts: []^Server_State, count: int) -> bool {
	start := time.tick_now()
	for time.tick_since(start) < platform.NETWORK_TEST_TIMEOUT {
		update_lan_query(query, multiplayer, time.tick_now())
		for host in hosts {
			run_server_frame(host, 0)
		}
		if len(multiplayer.games) >= count {
			return true
		}
		time.sleep(time.Millisecond)
	}
	return false
}

// A hosting session answers a query over the loopback with its world's
// name, its TCP port, its players and this build.
@(test)
test_a_hosting_session_answers_a_discovery_query_over_the_loopback :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_loopback_test_server(content, LOOPBACK_DISCOVERY_PLAN)
	defer destroy_loopback_test_server(host)
	if !testing.expect(t, host.session.network.discovery.open) {
		return
	}
	multiplayer := make_multiplayer_state()
	defer destroy_multiplayer_state(&multiplayer)
	targets := [?]net.Endpoint{{address = net.IP4_Loopback, port = host.session.network.discovery.port}}
	query := Lan_Query{targets = targets[:]}
	defer close_lan_query(&query)
	if !testing.expect(t, query_until_listed(&query, &multiplayer, {host}, 1)) {
		return
	}
	testing.expect_value(t, len(multiplayer.games), 1)
	game := multiplayer.games[0]
	testing.expect_value(t, game.world, LOOPBACK_TEST_WORLD_NAME)
	testing.expect_value(t, game.port, host.session.network.listener.port)
	testing.expect_value(t, game.address, "127.0.0.1")
	testing.expect_value(t, game.build, BUILD_STAMP)
	testing.expect(t, game.same_build)
	testing.expect_value(t, game.players, session_player_count(host.session.lockstep))
}

// A query nobody answers lists nothing.
@(test)
test_a_query_with_no_host_lists_nothing :: proc(t: ^testing.T) {
	// A port that was free a moment ago, closed again, so nobody listens.
	probe, problem := platform.open_discovery_responder(0)
	if !testing.expect_value(t, problem, "") {
		return
	}
	targets := [?]net.Endpoint{{address = net.IP4_Loopback, port = probe.port}}
	platform.close_discovery_socket(&probe)
	multiplayer := make_multiplayer_state()
	defer destroy_multiplayer_state(&multiplayer)
	query := Lan_Query{targets = targets[:]}
	defer close_lan_query(&query)
	start := time.tick_now()
	for time.tick_since(start) < 300 * time.Millisecond {
		update_lan_query(&query, &multiplayer, time.tick_now())
		time.sleep(time.Millisecond)
	}
	testing.expect(t, query.socket.open)
	testing.expect_value(t, len(multiplayer.games), 0)
}

// Two games on one machine: the second takes the next free port of the
// range, both share the discovery port, and one broadcast on the loopback
// reaches both.
@(test)
test_two_sessions_on_one_machine_take_different_ports_and_both_answer :: proc(t: ^testing.T) {
	taken, problem := platform.listen_on_port(0, .Loopback)
	if !testing.expect_value(t, problem, "") {
		return
	}
	defer platform.close_listener(&taken)
	// Holds a discovery port the system picked; the games share it.
	shared: platform.Discovery_Socket
	shared, problem = platform.open_discovery_responder(0)
	if !testing.expect_value(t, problem, "") {
		return
	}
	defer platform.close_discovery_socket(&shared)
	plan := Hosting_Plan{first_port = taken.port, port_count = HOST_PORT_COUNT, address = .Loopback, discovery = true, discovery_port = shared.port}
	content := make_save_test_content()
	first := make_loopback_test_server(content, plan)
	defer destroy_loopback_test_server(first)
	second := make_loopback_test_server(content, plan)
	defer destroy_loopback_test_server(second)
	first_port, second_port := first.session.network.listener.port, second.session.network.listener.port
	testing.expect(t, first_port != second_port)
	testing.expect(t, first_port != taken.port && second_port != taken.port)
	testing.expect(t, first.session.network.discovery.open && second.session.network.discovery.open)
	multiplayer := make_multiplayer_state()
	defer destroy_multiplayer_state(&multiplayer)
	targets := [?]net.Endpoint{{address = net.IP4_Address{127, 255, 255, 255}, port = shared.port}}
	query := Lan_Query{targets = targets[:]}
	defer close_lan_query(&query)
	if !testing.expect(t, query_until_listed(&query, &multiplayer, {first, second}, 2)) {
		return
	}
	ports := [2]int{multiplayer.games[0].port, multiplayer.games[1].port}
	testing.expect(t, ports == {first_port, second_port} || ports == {second_port, first_port})
}

// A windowed game hosts its own world when the frame takes it, on the
// first free port of its range, and plays alone as single player: a
// pausing screen holds its ticks.
@(test)
test_a_windowed_game_hosts_its_world_and_pauses_while_alone :: proc(t: ^testing.T) {
	taken, problem := platform.listen_on_port(0, .Loopback)
	if !testing.expect_value(t, problem, "") {
		return
	}
	defer platform.close_listener(&taken)
	content := make_save_test_content()
	state := make_joining_test_frame(content, "")
	defer destroy_joining_test_frame(state)
	state.settings = DEFAULT_SETTINGS
	state.hosting = Hosting_Plan{first_port = taken.port, port_count = HOST_PORT_COUNT, address = .Loopback}
	enter_session(state, make_loopback_test_session(content))
	network := state.session.network
	testing.expect_value(t, network.role, Network_Role.Host)
	testing.expect(t, network.listener.port > taken.port && network.listener.port < taken.port + HOST_PORT_COUNT)
	testing.expect(t, session_alone(network))
	start_tick := state.session.simulation.tick
	push_screen(&state.viewports[0].interaction.ui.screens, .Pause)
	for _ in 0 ..< 30 {
		run_client_test_frame(state)
	}
	testing.expect_value(t, state.session.simulation.tick, start_tick)
	pop_screen(&state.viewports[0].interaction.ui.screens)
	played := false
	start := time.tick_now()
	for !played && time.tick_since(start) < time.Minute {
		run_client_test_frame(state)
		played = state.session.simulation.tick > start_tick
	}
	testing.expect(t, played)
}

// The end to end join from the Multiplayer screen's list over the
// loopback: a windowed game hosts, the client's query lists it, Confirm's
// path joins it (the .Join request, the --join path), and both machines
// keep the same hash for a thousand ticks.
@(test)
test_a_join_from_the_list_keeps_the_hosts_hash :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_hosting_test_frame(content, LOOPBACK_DISCOVERY_PLAN)
	defer destroy_joining_test_frame(host)
	client := make_joining_test_frame(content, "")
	defer destroy_joining_test_frame(client)
	title := &client.interaction.title
	title.multiplayer = make_multiplayer_state()
	defer destroy_multiplayer_state(&title.multiplayer)
	title.join_address = make_text_field("", TEXT_FIELD_CAPACITY)
	targets := [?]net.Endpoint{{address = net.IP4_Loopback, port = host.session.network.discovery.port}}
	client.lan_query.targets = targets[:]
	defer close_lan_query(&client.lan_query)
	start := time.tick_now()
	for len(title.multiplayer.games) == 0 && time.tick_since(start) < platform.NETWORK_TEST_TIMEOUT {
		update_lan_query(&client.lan_query, &title.multiplayer, time.tick_now())
		run_client_test_frame(host)
		time.sleep(time.Millisecond)
	}
	if !testing.expect_value(t, len(title.multiplayer.games), 1) {
		return
	}
	join_lan_game(&client.viewports[0].interaction.ui, title, title.multiplayer.games[0])
	testing.expect_value(t, title.request.kind, Session_Request_Kind.Join)
	apply_session_request(client)
	testing.expect(t, join_active(client.joining))
	start = time.tick_now()
	for client.session == nil && time.tick_since(start) < time.Minute {
		run_client_test_frame(host)
		run_client_test_frame(client)
		time.sleep(100 * time.Microsecond)
	}
	if !testing.expect(t, client.session != nil) {
		return
	}
	testing.expect(t, !session_alone(host.session.network))
	played_to := host.session.simulation.tick + 1000
	testing.expect(t, run_hosting_test_frames(host, {client}, played_to))
	testing.expect_value(t, host.session.network.mismatch_count, 0)
	testing.expect_value(t, client.session.network.mismatch_count, 0)
	testing.expect(t, len(host.session.network.hashes) > 0)
	testing.expect_value(t, session_player_count(host.session.lockstep), 2)
}

// A host answers only a query at least as long as its answer: a short
// query (as one with a forged sender would be) gets nothing, the padded
// one an answer.
@(test)
test_a_short_query_gets_no_answer_and_a_padded_one_does :: proc(t: ^testing.T) {
	content := make_save_test_content()
	host := make_loopback_test_server(content, LOOPBACK_DISCOVERY_PLAN)
	defer destroy_loopback_test_server(host)
	query, problem := platform.open_discovery_query()
	if !testing.expect_value(t, problem, "") {
		return
	}
	defer platform.close_discovery_socket(&query)
	responder := net.Endpoint{address = net.IP4_Loopback, port = host.session.network.discovery.port}
	testing.expect(t, answers_within(host, query, responder, platform.encode_discovery_query(64), 300 * time.Millisecond) == 0)
	testing.expect(t, answers_within(host, query, responder, platform.encode_discovery_query(), platform.NETWORK_TEST_TIMEOUT) == 1)
}

// Sends the query once and counts the answers until one arrives or the
// time is up.
answers_within :: proc(host: ^Server_State, query: platform.Discovery_Socket, responder: net.Endpoint, datagram: []byte, duration: time.Duration) -> int {
	platform.send_discovery_datagram(query, datagram, responder)
	start := time.tick_now()
	for time.tick_since(start) < duration {
		run_server_frame(host, 0)
		for answer in platform.receive_discovery_datagrams(query) {
			if message, ok := platform.parse_discovery_datagram(answer.bytes); ok && message.kind == .Answer {
				return 1
			}
		}
		time.sleep(time.Millisecond)
	}
	return 0
}
