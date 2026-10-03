package game

import "core:fmt"
import "core:net"
import "core:time"
import "platform"

// Every game hosts and the LAN finds it (work item 0188). A windowed
// session hosts from its first tick (host_windowed_session, from
// enter_session): the listener takes the first free port of
// HOST_PORT_COUNT from DEFAULT_NETWORK_PORT, so a second game on the
// machine hosts too, and the discovery socket answers the LAN's queries
// (answer_discovery_queries, in update_host_network, which the headless
// server shares). The title's Multiplayer screen (ui_multiplayer.odin)
// queries once a second while it shows (serve_lan_query) and lists the
// answers; its join goes through the --join path (start_joining). The
// datagrams are in platform/network_discovery.odin.

// The TCP ports a game tries, from DEFAULT_NETWORK_PORT.
HOST_PORT_COUNT :: 10
// The pause between two queries of the Multiplayer screen.
LAN_QUERY_INTERVAL :: time.Second

// Where a session hosts. A zero plan (port_count 0) does not host, so
// the tests' frames stay offline unless they ask.
Hosting_Plan :: struct {
	first_port:     int,
	port_count:     int,
	address:        platform.Listen_Address,
	// Answer the LAN's queries on discovery_port; port 0 lets the system
	// choose (the tests).
	discovery:      bool,
	discovery_port: int,
}

// A game's plan: the port range on every interface and the discovery.
default_hosting_plan :: proc() -> Hosting_Plan {
	return Hosting_Plan {
		first_port = platform.DEFAULT_NETWORK_PORT,
		port_count = HOST_PORT_COUNT,
		discovery = true,
		discovery_port = platform.DISCOVERY_PORT,
	}
}

// --server: --port alone when given, else the game's range.
server_hosting_plan :: proc(port: int) -> Hosting_Plan {
	plan := default_hosting_plan()
	if port != 0 {
		plan.first_port, plan.port_count = port, 1
	}
	return plan
}

// The windowed game hosts its own world (not a joined one) as soon as
// the frame takes it; a game that cannot host plays offline and says
// so.
host_windowed_session :: proc(session: ^Session, plan: Hosting_Plan) {
	if session.network.role != .Offline || plan.port_count == 0 {
		return
	}
	if problem := start_hosting(&session.network, plan); problem != "" {
		network_notice(&session.network, "%s: %s", text("network_cannot_host"), problem)
		return
	}
	platform.log_printf("network: hosting on port %d", session.network.listener.port)
}

// The players on the session: members that joined and have not left,
// the ones whose join tick is still ahead included.
session_player_count :: proc(lockstep: Lockstep) -> int {
	count := 0
	for member in lockstep.members {
		count += member.joined_tick != NEVER_TICK && member.left_tick == NEVER_TICK ? 1 : 0
	}
	return count
}

// The host's toast when a machine joins or leaves.
notice_player_count :: proc(session: ^Session) {
	network_notice(&session.network, "%s", format_message_text(text("network_player_count"), fmt.tprint(session_player_count(session.lockstep))))
}

// Every waiting query gets one answer at its sender: the world's name,
// the machine's, the players, the TCP port and the build. A query
// shorter than the answer gets none, so a forged sender cannot make the
// host send more than it received.
answer_discovery_queries :: proc(session: ^Session, name: string) {
	network := &session.network
	if !network.discovery.open {
		return
	}
	for datagram in platform.receive_discovery_datagrams(network.discovery) {
		message, ok := platform.parse_discovery_datagram(datagram.bytes)
		if !ok || message.kind != .Query {
			continue
		}
		answer := platform.encode_discovery_answer(name, platform.discovery_machine_name(), BUILD_STAMP, session_player_count(session.lockstep), network.listener.port)
		if len(datagram.bytes) < len(answer) {
			continue
		}
		platform.send_discovery_datagram(network.discovery, answer, datagram.source)
	}
}

// The Multiplayer screen's socket while it shows. targets is empty in
// the game, which queries the broadcast addresses on DISCOVERY_PORT, read
// once when the socket opens (broadcasts, owned); a test sets the
// loopback's own.
Lan_Query :: struct {
	socket:     platform.Discovery_Socket,
	broadcasts: [dynamic]net.Endpoint,
	last_query: time.Tick,
	queried:    bool,
	// The socket did not open: logged once, tried again when the screen
	// opens next.
	failed:     bool,
	targets:    []net.Endpoint,
}

close_lan_query :: proc(query: ^Lan_Query) {
	platform.close_discovery_socket(&query.socket)
	delete(query.broadcasts)
	query.broadcasts = nil
	query.queried, query.failed = false, false
}

// Between frames: while any viewport shows the Multiplayer screen the
// LAN is queried and the list follows the answers; otherwise the socket
// closes and the list empties.
serve_lan_query :: proc(state: ^Frame_State) {
	multiplayer := &state.interaction.title.multiplayer
	if !any_viewport_shows(state, .Multiplayer) {
		close_lan_query(&state.lan_query)
		clear_lan_games(multiplayer)
		return
	}
	update_lan_query(&state.lan_query, multiplayer, time.tick_now())
}

// The query once every LAN_QUERY_INTERVAL, the answers into the list,
// the answers older than LAN_GAME_LIFETIME out of it.
update_lan_query :: proc(query: ^Lan_Query, multiplayer: ^Multiplayer_State, now: time.Tick) {
	if !query.socket.open && !query.failed {
		problem: string
		if query.socket, problem = platform.open_discovery_query(); problem != "" {
			query.failed = true
			platform.log_printf("error: network: %s; join by address", problem)
		} else if len(query.targets) == 0 {
			append(&query.broadcasts, ..platform.discovery_broadcast_endpoints(platform.DISCOVERY_PORT))
		}
	}
	if query.socket.open && (!query.queried || time.tick_diff(query.last_query, now) >= LAN_QUERY_INTERVAL) {
		query.queried, query.last_query = true, now
		targets := len(query.targets) > 0 ? query.targets : query.broadcasts[:]
		for target in targets {
			platform.send_discovery_datagram(query.socket, platform.encode_discovery_query(), target)
		}
	}
	for datagram in platform.receive_discovery_datagrams(query.socket) {
		message, ok := platform.parse_discovery_datagram(datagram.bytes)
		if ok && message.kind == .Answer {
			add_lan_answer(multiplayer, message, net.address_to_string(datagram.source.address), message.build == BUILD_STAMP, now)
		}
	}
	prune_lan_games(multiplayer, now)
}
