package game

import "core:fmt"
import "core:slice"
import "core:time"
import "platform"

// The machines of a lockstep session (work item 0177): the host relays,
// the clients send and receive, over the transport of the platform
// package (platform/network.odin). The host has no authority: it runs the
// same driver (lockstep.odin) on its own records like any machine, and a
// headless server (session_server.odin) is a host without a local player.
//
// Messages, each a kind byte and its body:
// - Input_Record: a client's local record to the host; the host sends
//   every record (its own and the clients') to every joined client and
//   delivers it to its own driver.
// - Ping and Pong: a client measures the round trip before it joins, and
//   its window comes from it (latency_window_ticks).
// - Join_Request and Join_Snapshot: the host serialises its world as the
//   save does (encode_save_files), with the simulated chunk set, the
//   members and every record it holds for the ticks after its own; the
//   joiner loads it (start_joined_session). The joiner has no player yet
//   (work item 0190): the host relays every record and member change to
//   it like to any client and plays on while it restores and runs the
//   relayed ticks. Once its world is restored and no relayed tick is left
//   to run, it asks for its player with Add_Local_Player, and only from
//   that player's join tick does any machine wait for its records.
// - Member_Change: a player joined (from the join tick) or left (from the
//   tick after its last relayed record); every machine changes its
//   members alike.
// - Hash_Report and Hash_Mismatch: every STATE_HASH_INTERVAL_TICKS each
//   client sends its state hash; the host compares it with its own, and a
//   mismatch is logged with both hashes and the tick, toasted naming the
//   machine and sent to every client. Play continues.
// - Join_Refused: the joiner's build or content tables differ from the
//   host's (Join_Request carries both); the reason, then the host drops it.
// - Add_Local_Player and Local_Player_Added: a client that has the
//   snapshot asks for a local player, its own once it caught up (0190) or
//   one more for a split screen viewport (work item 0178); the host takes
//   an entry (joining_player_index) from the tick after the newest record
//   relayed (next_join), announces the member with Member_Change and
//   answers with the player and its join tick. Remove_Local_Player: the
//   client's extra local player leaves from the tick after its last
//   relayed record. One connection carries every local player of a
//   machine.
//
// Every machine pings each peer every NETWORK_KEEPALIVE_INTERVAL; a peer
// from which no byte arrived for NETWORK_TIMEOUT is dropped (a client
// leaves from the tick after its last record, a host is lost).

Network_Role :: enum u8 {
	Offline,
	Host,
	Client,
}

Lockstep_Message_Kind :: enum u8 {
	Input_Record = 1,
	Ping,
	Pong,
	Join_Request,
	Join_Snapshot,
	Member_Change,
	Hash_Report,
	Hash_Mismatch,
	Join_Refused,
	Add_Local_Player,
	Local_Player_Added,
	Remove_Local_Player,
}

// The keepalive ping, and the silence after which a peer is dropped.
NETWORK_KEEPALIVE_INTERVAL :: time.Second
NETWORK_TIMEOUT :: 10 * time.Second
// A client whose unsent bytes on the host pass this (beyond its join
// snapshot) is too far behind and is dropped, so a stalled reader cannot
// grow the host's memory without bound.
MAXIMUM_CLIENT_BACKLOG_BYTES :: 32 * 1024 * 1024
// Hash reports one machine may have waiting for the host's own hash.
MAXIMUM_PENDING_HASH_REPORTS :: 16
// The window a joiner may ask for (two seconds at 60 Hz), and how far
// past the host's tick plus its window a client's record may be stamped
// (other clients' records run ahead of the host by their windows).
MAXIMUM_JOIN_WINDOW :: 120
RECORD_TICK_MARGIN :: MAXIMUM_JOIN_WINDOW + 60

// The tags of the relayed commands; a chunk arrival and a join's entry
// never cross the network.
Player_Command_Tag :: enum u8 {
	Research = 1,
	Craft,
	Cancel_Craft,
	Assembler_Recipe,
	Power_Switch,
	Assembly,
	Launch,
	Catalogue_Order,
	Machine_Filter,
	Splitter_Priorities,
	Splitter_Side,
	Hotbar_Slot,
	Close_Machine,
	Debug_Remove_Block,
	Debug_Drop_Item,
	Developer,
	Slot_Primary,
	Slot_Split,
	Slot_Sort,
	Distribute,
	Return_Held,
	Drop_Stack,
	Quick_Move,
	Transfer_Button,
	Grid_Transfer,
	Inserter_Hand,
	Foundation_Block,
	// The pause menu's Skip arrival (0200).
	Skip_Arrival,
	// The placement editor's commit (0215).
	Machine_Placement,
}

// A player a client's machine drives, on the host: the newest tick
// relayed for it and its join tick.
Peer_Player :: struct {
	player:      int,
	last_tick:   u64,
	joined_tick: u64,
}

// A client's connection on the host, or the host's on a client.
Network_Peer :: struct {
	connection:    platform.Network_Connection,
	// The players its machine drives, none until it joined: the first
	// from its join, the others its split screen viewports' (0178).
	players:       [MAXIMUM_VIEWPORTS]Peer_Player,
	player_count:  int,
	// The joiner's window (from its join request) and the size of the
	// snapshot sent to it, which its backlog may hold besides the cap.
	window:        int,
	snapshot_size: int,
	// The last time bytes arrived from it and the last ping sent to it.
	last_heard:    time.Tick,
	last_ping:     time.Tick,
	// The connection's received_total when last_heard was set.
	received_mark: int,
	// Refused at its join: dropped once the reason is sent.
	refused:       bool,
	// The snapshot went out: from then on every record and member change
	// goes to it, with a player or (while it restores, 0190) without.
	receives_records: bool,
}

Pending_Hash_Report :: struct {
	tick:    u64,
	hash:    u64,
	machine: string,
}

Session_Network :: struct {
	role:            Network_Role,
	listener:        platform.Network_Listener,
	// Host: the LAN discovery's socket the queries reach (0188), closed
	// when it could not open (joins by address still work).
	discovery:       platform.Discovery_Socket,
	peers:           [dynamic]Network_Peer,
	// Host: the newest tick of any record relayed.
	frontier:        u64,
	// Host: its own hashes by tick, and the clients' reports waiting for
	// them.
	hashes:          map[u64]u64,
	reports:         [dynamic]Pending_Hash_Report,
	// Client: the ping's send time, the round trip measured, and whether
	// the join was asked for.
	ping_sent:       time.Tick,
	round_trip:      f64,
	join_requested:  bool,
	// Client: the host's snapshot, owned, until the loop starts the
	// session from it (take_join_snapshot).
	snapshot:        []byte,
	// Client: the host's connection closed, timed out or refused the join.
	host_lost:       bool,
	// Client: the connection being made (platform.start_dial) and when
	// the join started.
	dial:            ^platform.Network_Dial,
	join_started:    time.Tick,
	// Client: the host's records and member changes that arrived with or
	// after the snapshot, before the session existed (owned); the driver
	// takes them once it does (adopt_join_snapshot).
	held_messages:   [dynamic][]byte,
	// Client: the simulation's tick rate, for the window (join_window).
	tick_rate:       int,
	// What the frame toasts (owned), logged when added.
	notices:         [dynamic]string,
	// State hash mismatches seen (host: compared; client: told).
	mismatch_count:  int,
	// Client: split screen players asked of the host (Add_Local_Player)
	// whose viewport left before the answer came; each answer that lands
	// while one is counted leaves at once (Remove_Local_Player), since a
	// local member never exists without a viewport.
	cancelled_local_players: int,
	// Client: the joiner asked for its own player (0190), once its world
	// caught up (request_own_player).
	own_player_requested: bool,
}

// A machine joining a host (--join): the connection until the snapshot
// arrives, then the joined world while it catches up and before the
// frame takes it (update_joining in loop.odin).
Session_Join :: struct {
	network: Session_Network,
	session: ^Session,
}

join_active :: proc(join: Session_Join) -> bool {
	return join.network.role == .Client || join.session != nil
}

// The joined world is dropped unsaved: it is the host's.
destroy_session_join :: proc(join: ^Session_Join) {
	if join.session != nil {
		end_session(join.session)
	}
	destroy_session_network(&join.network)
	join^ = {}
}

destroy_session_network :: proc(network: ^Session_Network) {
	platform.close_listener(&network.listener)
	platform.close_discovery_socket(&network.discovery)
	for &peer in network.peers {
		platform.destroy_connection(&peer.connection)
	}
	delete(network.peers)
	delete(network.hashes)
	for report in network.reports {
		delete(report.machine)
	}
	delete(network.reports)
	delete(network.snapshot)
	if network.dial != nil {
		platform.abandon_dial(network.dial)
	}
	for message in network.held_messages {
		delete(message)
	}
	delete(network.held_messages)
	for notice in network.notices {
		delete(notice)
	}
	delete(network.notices)
	network^ = {}
}

network_notice :: proc(network: ^Session_Network, format: string, arguments: ..any) {
	notice := fmt.aprintf(format, ..arguments)
	platform.log_printf("network: %s", notice)
	append(&network.notices, notice)
}

// Encoding.

append_bytes :: proc(bytes: ^[dynamic]byte, value: []byte) {
	append_u32(bytes, u32(len(value)))
	append(bytes, ..value)
}

// A view into the reader's data.
read_bytes :: proc(reader: ^Byte_Reader) -> (value: []byte, ok: bool) {
	text := read_string(reader) or_return
	return transmute([]byte)text, true
}

write_tagged_command :: proc(bytes: ^[dynamic]byte, tag: Player_Command_Tag, command: $T) {
	command := command
	append_u8(bytes, u8(tag))
	write_value_of(bytes, &command)
}

encode_player_command :: proc(bytes: ^[dynamic]byte, command: Player_Command) {
	switch variant in command {
	case Research_Command:
		write_tagged_command(bytes, .Research, variant)
	case Craft_Command:
		write_tagged_command(bytes, .Craft, variant)
	case Cancel_Craft_Command:
		write_tagged_command(bytes, .Cancel_Craft, variant)
	case Assembler_Recipe_Command:
		write_tagged_command(bytes, .Assembler_Recipe, variant)
	case Power_Switch_Command:
		write_tagged_command(bytes, .Power_Switch, variant)
	case Assembly_Command:
		write_tagged_command(bytes, .Assembly, variant)
	case Launch_Command:
		write_tagged_command(bytes, .Launch, variant)
	case Catalogue_Order_Command:
		write_tagged_command(bytes, .Catalogue_Order, variant)
	case Machine_Filter_Command:
		write_tagged_command(bytes, .Machine_Filter, variant)
	case Splitter_Priorities_Command:
		write_tagged_command(bytes, .Splitter_Priorities, variant)
	case Splitter_Side_Command:
		write_tagged_command(bytes, .Splitter_Side, variant)
	case Hotbar_Slot_Command:
		write_tagged_command(bytes, .Hotbar_Slot, variant)
	case Close_Machine_Command:
		write_tagged_command(bytes, .Close_Machine, variant)
	case Debug_Remove_Block_Command:
		write_tagged_command(bytes, .Debug_Remove_Block, variant)
	case Debug_Drop_Item_Command:
		write_tagged_command(bytes, .Debug_Drop_Item, variant)
	case Developer_Request:
		write_tagged_command(bytes, .Developer, variant)
	case Slot_Primary_Command:
		write_tagged_command(bytes, .Slot_Primary, variant)
	case Slot_Split_Command:
		write_tagged_command(bytes, .Slot_Split, variant)
	case Slot_Sort_Command:
		write_tagged_command(bytes, .Slot_Sort, variant)
	case Distribute_Command:
		write_tagged_command(bytes, .Distribute, variant)
	case Return_Held_Command:
		write_tagged_command(bytes, .Return_Held, variant)
	case Drop_Stack_Command:
		write_tagged_command(bytes, .Drop_Stack, variant)
	case Quick_Move_Command:
		write_tagged_command(bytes, .Quick_Move, variant)
	case Transfer_Button_Command:
		write_tagged_command(bytes, .Transfer_Button, variant)
	case Grid_Transfer_Command:
		write_tagged_command(bytes, .Grid_Transfer, variant)
	case Inserter_Hand_Command:
		write_tagged_command(bytes, .Inserter_Hand, variant)
	case Foundation_Block_Command:
		write_tagged_command(bytes, .Foundation_Block, variant)
	case Skip_Arrival_Command:
		write_tagged_command(bytes, .Skip_Arrival, variant)
	case Machine_Placement_Command:
		write_tagged_command(bytes, .Machine_Placement, variant)
	case Add_Player_Command, Chunk_Ready_Command, Field_Chunk_Ready_Command:
		panic("a join's entry and a chunk arrival are never relayed")
	}
}

read_command_value :: proc(reader: ^Byte_Reader, $T: typeid) -> (command: Player_Command, ok: bool) {
	value: T
	read_value_of(reader, &value) or_return
	return value, true
}

decode_player_command :: proc(reader: ^Byte_Reader) -> (command: Player_Command, ok: bool) {
	switch Player_Command_Tag(read_u8(reader) or_return) {
	case .Research:
		return read_command_value(reader, Research_Command)
	case .Craft:
		return read_command_value(reader, Craft_Command)
	case .Cancel_Craft:
		return read_command_value(reader, Cancel_Craft_Command)
	case .Assembler_Recipe:
		return read_command_value(reader, Assembler_Recipe_Command)
	case .Power_Switch:
		return read_command_value(reader, Power_Switch_Command)
	case .Assembly:
		return read_command_value(reader, Assembly_Command)
	case .Launch:
		return read_command_value(reader, Launch_Command)
	case .Catalogue_Order:
		return read_command_value(reader, Catalogue_Order_Command)
	case .Machine_Filter:
		return read_command_value(reader, Machine_Filter_Command)
	case .Splitter_Priorities:
		return read_command_value(reader, Splitter_Priorities_Command)
	case .Splitter_Side:
		return read_command_value(reader, Splitter_Side_Command)
	case .Hotbar_Slot:
		return read_command_value(reader, Hotbar_Slot_Command)
	case .Close_Machine:
		return read_command_value(reader, Close_Machine_Command)
	case .Debug_Remove_Block:
		return read_command_value(reader, Debug_Remove_Block_Command)
	case .Debug_Drop_Item:
		return read_command_value(reader, Debug_Drop_Item_Command)
	case .Developer:
		return read_command_value(reader, Developer_Request)
	case .Slot_Primary:
		return read_command_value(reader, Slot_Primary_Command)
	case .Slot_Split:
		return read_command_value(reader, Slot_Split_Command)
	case .Slot_Sort:
		return read_command_value(reader, Slot_Sort_Command)
	case .Distribute:
		return read_command_value(reader, Distribute_Command)
	case .Return_Held:
		return read_command_value(reader, Return_Held_Command)
	case .Drop_Stack:
		return read_command_value(reader, Drop_Stack_Command)
	case .Quick_Move:
		return read_command_value(reader, Quick_Move_Command)
	case .Transfer_Button:
		return read_command_value(reader, Transfer_Button_Command)
	case .Grid_Transfer:
		return read_command_value(reader, Grid_Transfer_Command)
	case .Inserter_Hand:
		return read_command_value(reader, Inserter_Hand_Command)
	case .Foundation_Block:
		return read_command_value(reader, Foundation_Block_Command)
	case .Skip_Arrival:
		return read_command_value(reader, Skip_Arrival_Command)
	case .Machine_Placement:
		return read_command_value(reader, Machine_Placement_Command)
	}
	return nil, false
}

encode_input_record :: proc(bytes: ^[dynamic]byte, record: Input_Record) {
	append_u64(bytes, record.tick)
	append_u32(bytes, u32(record.player))
	input := record.input
	write_value_of(bytes, &input)
	append_u32(bytes, u32(len(record.commands)))
	for command in record.commands {
		encode_player_command(bytes, command)
	}
	append_u32(bytes, u32(len(record.lines)))
	for line in record.lines {
		append_string(bytes, line.line)
		append_string(bytes, line.blueprint)
		append_u64(bytes, line.client)
	}
}

// The record owns what it holds. Counts are checked against the bytes
// left before anything is allocated for them.
decode_input_record :: proc(reader: ^Byte_Reader) -> (record: Input_Record, ok: bool) {
	record.tick = read_u64(reader) or_return
	record.player = int(read_u32(reader) or_return)
	read_value_of(reader, &record.input) or_return
	command_count := int(read_u32(reader) or_return)
	if command_count > bytes_left(reader^) {
		return {}, false
	}
	for _ in 0 ..< command_count {
		command, command_ok := decode_player_command(reader)
		if !command_ok {
			destroy_input_record(record)
			return {}, false
		}
		append(&record.commands, command)
	}
	line_count := int(read_u32(reader) or_return)
	if line_count > bytes_left(reader^) {
		destroy_input_record(record)
		return {}, false
	}
	for _ in 0 ..< line_count {
		line, line_ok := read_string(reader)
		blueprint, blueprint_ok := read_string(reader)
		client, client_ok := read_u64(reader)
		if !line_ok || !blueprint_ok || !client_ok {
			destroy_input_record(record)
			return {}, false
		}
		append(&record.lines, Socket_Line{line = clone_text(line), blueprint = clone_text(blueprint), client = client})
	}
	return record, true
}

clone_text :: proc(text: string) -> string {
	return string(slice.clone(transmute([]byte)text))
}

message_of :: proc(kind: Lockstep_Message_Kind, allocator := context.temp_allocator) -> [dynamic]byte {
	bytes := make([dynamic]byte, allocator)
	append_u8(&bytes, u8(kind))
	return bytes
}

record_message :: proc(record: Input_Record) -> []byte {
	bytes := message_of(.Input_Record)
	encode_input_record(&bytes, record)
	return bytes[:]
}

member_change_message :: proc(player: int, member: Lockstep_Member) -> []byte {
	bytes := message_of(.Member_Change)
	append_u32(&bytes, u32(player))
	member := member
	write_value_of(&bytes, &member)
	return bytes[:]
}

hash_report_message :: proc(tick, hash: u64) -> []byte {
	bytes := message_of(.Hash_Report)
	append_u64(&bytes, tick)
	append_u64(&bytes, hash)
	return bytes[:]
}

hash_mismatch_message :: proc(tick, host_hash, machine_hash: u64, machine: string) -> []byte {
	bytes := message_of(.Hash_Mismatch)
	append_u64(&bytes, tick)
	append_u64(&bytes, host_hash)
	append_u64(&bytes, machine_hash)
	append_string(&bytes, machine)
	return bytes[:]
}

// Members.

// The peer joined: it drives a player.
peer_joined :: proc(peer: Network_Peer) -> bool {
	return peer.player_count > 0
}

// The index of the player in the peer's players, or -1.
find_peer_player :: proc(peer: Network_Peer, player: int) -> int {
	for index in 0 ..< peer.player_count {
		if peer.players[index].player == player {
			return index
		}
	}
	return -1
}

// Sets a member's entry, growing the list with members that never joined.
set_lockstep_member :: proc(lockstep: ^Lockstep, player: int, member: Lockstep_Member) {
	for len(lockstep.members) <= player {
		append(&lockstep.members, Lockstep_Member{joined_tick = NEVER_TICK, left_tick = NEVER_TICK})
	}
	lockstep.members[player] = member
}

// The entry a joining player takes: the first entry of the save no member
// holds or will hold, else a new one after every entry and pending join.
joining_player_index :: proc(lockstep: Lockstep, player_count: int, join_tick: u64) -> (player: int, adds_entry: bool) {
	for index in 0 ..< player_count {
		if index >= len(lockstep.members) {
			return index, false
		}
		member := lockstep.members[index]
		if member.joined_tick == NEVER_TICK || member.left_tick <= join_tick {
			return index, false
		}
	}
	return max(player_count, len(lockstep.members)), true
}

// Hosting.

// Listens on the plan's first free port for clients and answers the
// LAN's queries (session_discovery.odin); the local driver keeps its
// members. The caller logs the port. A discovery port that cannot open is logged and the session
// hosts without it.
start_hosting :: proc(network: ^Session_Network, plan: Hosting_Plan) -> string {
	listener, problem := platform.listen_on_free_port(plan.first_port, plan.port_count, plan.address)
	if problem != "" {
		return problem
	}
	network.role, network.listener = .Host, listener
	if plan.discovery {
		discovery_problem: string
		if network.discovery, discovery_problem = platform.open_discovery_responder(plan.discovery_port); discovery_problem != "" {
			platform.log_printf("error: network: %s; the game is joined by address only", discovery_problem)
		}
	}
	return ""
}

// No other machine plays: offline, or a host no client has joined yet.
// The frame holds and runs such a session's ticks as single player.
session_alone :: proc(network: Session_Network) -> bool {
	switch network.role {
	case .Offline:
		return true
	case .Host:
		// A joiner restoring without a player follows the records too,
		// so the host no longer runs ticks no record carries.
		for peer in network.peers {
			if peer.receives_records {
				return false
			}
		}
		return true
	case .Client:
	}
	return false
}

// The host's frame: new clients, their messages, its own records out to
// everyone. content and name are for a join's save.
update_host_network :: proc(session: ^Session, content: Simulation_Content, name: string) {
	network := &session.network
	for {
		connection, accepted := platform.accept_connection(&network.listener)
		if !accepted {
			break
		}
		platform.log_printf("network: %s connected", connection.address)
		now := time.tick_now()
		append(&network.peers, Network_Peer{connection = connection, last_heard = now, last_ping = now})
	}
	answer_discovery_queries(session, name)
	for index := 0; index < len(network.peers); index += 1 {
		peer := &network.peers[index]
		platform.poll_connection(&peer.connection)
		for {
			payload, ok := platform.take_message(&peer.connection, context.temp_allocator)
			if !ok {
				break
			}
			handle_client_message(session, content, name, index, payload)
		}
		keep_peer_alive(peer)
		if peer.refused && len(peer.connection.unsent) == 0 {
			platform.close_connection(&peer.connection, "refused at the join")
		}
		if !peer.connection.open {
			drop_client(session, index)
			index -= 1
		}
	}
	for record in session.lockstep.outgoing {
		relay_record(session, record)
	}
	clear(&session.lockstep.outgoing)
	for &peer in network.peers {
		platform.flush_connection(&peer.connection)
		if len(peer.connection.unsent) > MAXIMUM_CLIENT_BACKLOG_BYTES + peer.snapshot_size {
			platform.close_connection(&peer.connection, "too far behind (its unsent bytes passed the cap)")
		}
	}
}

// Pings the peer every keepalive interval, notes when bytes arrived, and
// closes a connection silent for NETWORK_TIMEOUT. Either side calls it
// after polling.
keep_peer_alive :: proc(peer: ^Network_Peer) {
	now := time.tick_now()
	if peer.connection.received_total != peer.received_mark {
		peer.last_heard = now
		peer.received_mark = peer.connection.received_total
	}
	if time.tick_diff(peer.last_ping, now) >= NETWORK_KEEPALIVE_INTERVAL {
		peer.last_ping = now
		ping := message_of(.Ping)
		platform.send_message(&peer.connection, ping[:])
	}
	if time.tick_diff(peer.last_heard, now) >= NETWORK_TIMEOUT {
		platform.close_connection(&peer.connection, "timed out")
	}
}

handle_client_message :: proc(session: ^Session, content: Simulation_Content, name: string, peer_index: int, payload: []byte) {
	reader := Byte_Reader{data = payload}
	kind, kind_ok := read_u8(&reader)
	peer := &session.network.peers[peer_index]
	if !kind_ok {
		return
	}
	#partial switch Lockstep_Message_Kind(kind) {
	case .Ping:
		payload := payload
		payload[0] = u8(Lockstep_Message_Kind.Pong)
		platform.send_message(&peer.connection, payload)
	case .Pong:
	case .Join_Request:
		request, request_ok := decode_join_request(&reader)
		switch {
		case peer.receives_records || peer.refused:
		case !request_ok:
			platform.close_connection(&peer.connection, "a malformed join request")
		case:
			if reason := join_refusal(request, content); reason != "" {
				refuse_join(&session.network, peer, reason)
				return
			}
			peer.window = clamp(request.window, 1, MAXIMUM_JOIN_WINDOW)
			host_join(session, content, name, peer_index)
		}
	case .Input_Record:
		record, ok := decode_input_record(&reader)
		index := ok ? find_peer_player(peer^, record.player) : -1
		if !ok || index < 0 || !record_tick_expected(peer.players[index], peer.window, record.tick, session.simulation.tick) {
			problem := ok ? fmt.tprintf("an input record for player %d tick %d out of order or out of range", record.player, record.tick) : "a malformed input record"
			if ok {
				destroy_input_record(record)
			}
			platform.close_connection(&peer.connection, problem)
			return
		}
		relay_record(session, record)
	case .Add_Local_Player:
		if peer.receives_records && peer.player_count < MAXIMUM_VIEWPORTS {
			host_add_peer_player(session, peer_index)
		}
	case .Remove_Local_Player:
		player, player_ok := read_u32(&reader)
		index := player_ok ? find_peer_player(peer^, int(player)) : -1
		// The machine's own player leaves with its connection.
		if index > 0 {
			drop_peer_player(session, peer_index, index)
		}
	case .Hash_Report:
		tick, tick_ok := read_u64(&reader)
		hash, hash_ok := read_u64(&reader)
		if tick_ok && hash_ok && state_hash_due(tick) && pending_reports_of(session.network, peer.connection.address) < MAXIMUM_PENDING_HASH_REPORTS {
			append(&session.network.reports, Pending_Hash_Report{tick = tick, hash = hash, machine = clone_text(peer.connection.address)})
			compare_hash_reports(&session.network)
		}
	case:
		platform.close_connection(&peer.connection, fmt.tprintf("an unexpected message %d", kind))
	}
}

// A client player's records come one tick after another from its join
// tick, and no further ahead of the host's tick than the client's window
// and the other clients' lead (RECORD_TICK_MARGIN) allow: one record far
// in the future would hold every machine at that tick.
record_tick_expected :: proc(peer_player: Peer_Player, window: int, tick, host_tick: u64) -> bool {
	return tick == peer_player.last_tick + 1 && tick <= max(host_tick, peer_player.joined_tick) + u64(window) + RECORD_TICK_MARGIN
}

pending_reports_of :: proc(network: Session_Network, machine: string) -> int {
	count := 0
	for report in network.reports {
		count += report.machine == machine ? 1 : 0
	}
	return count
}

// What a joiner sends: its window and what its build and content are.
Join_Request :: struct {
	window:       int,
	build:        string,
	content_hash: u64,
}

join_request_message :: proc(window: int, build: string, content_hash: u64) -> []byte {
	bytes := message_of(.Join_Request)
	append_u32(&bytes, u32(window))
	append_string(&bytes, build)
	append_u64(&bytes, content_hash)
	return bytes[:]
}

// The build is a view into the reader's data.
decode_join_request :: proc(reader: ^Byte_Reader) -> (request: Join_Request, ok: bool) {
	request.window = int(read_u32(reader) or_return)
	request.build = read_string(reader) or_return
	request.content_hash = read_u64(reader) or_return
	return request, true
}

// The content tables (every id by name) as one number: two machines with
// the same tables number items, recipes and machines alike.
content_tables_hash :: proc(content: Simulation_Content) -> u64 {
	bytes := make([dynamic]byte, context.temp_allocator)
	append_content_tables(&bytes, content_tables(content))
	return fingerprint_bytes(FINGERPRINT_START, bytes[:])
}

// Why the host refuses the join, or "".
join_refusal :: proc(request: Join_Request, content: Simulation_Content) -> string {
	switch {
	case request.build != BUILD_STAMP:
		return fmt.tprintf("the host runs build %s, this machine %s", BUILD_STAMP, request.build)
	case request.content_hash != content_tables_hash(content):
		return "the host's content tables differ from this machine's (another data directory or data edits)"
	}
	return ""
}

refuse_join :: proc(network: ^Session_Network, peer: ^Network_Peer, reason: string) {
	bytes := message_of(.Join_Refused)
	append_string(&bytes, reason)
	platform.send_message(&peer.connection, bytes[:])
	peer.refused = true
	network_notice(network, "%s was refused: %s", peer.connection.address, reason)
}

// To every joined client and to the host's own driver, which owns the
// record from here.
relay_record :: proc(session: ^Session, record: Input_Record) {
	network := &session.network
	message := record_message(record)
	for &peer in network.peers {
		if peer.receives_records {
			platform.send_message(&peer.connection, message)
		}
		if index := find_peer_player(peer, record.player); index >= 0 {
			peer.players[index].last_tick = max(peer.players[index].last_tick, record.tick)
		}
	}
	network.frontier = max(network.frontier, record.tick)
	receive_input_record(&session.lockstep, record, session.simulation.tick)
}

broadcast_member :: proc(session: ^Session, player: int, member: Lockstep_Member) {
	set_lockstep_member(&session.lockstep, player, member)
	message := member_change_message(player, member)
	for &peer in session.network.peers {
		if peer.receives_records {
			platform.send_message(&peer.connection, message)
		}
	}
}

// A client's player leaves from the tick after its last relayed record,
// which no machine can have run without it.
leave_peer_player :: proc(session: ^Session, address: string, peer_player: Peer_Player) {
	if peer_player.player >= len(session.lockstep.members) {
		return
	}
	member := session.lockstep.members[peer_player.player]
	member.left_tick = max(peer_player.last_tick + 1, member.joined_tick)
	broadcast_member(session, peer_player.player, member)
	network_notice(&session.network, "player %d (%s) left at tick %d", peer_player.player, address, member.left_tick)
}

// A joined client's players leave (leave_peer_player).
drop_client :: proc(session: ^Session, peer_index: int) {
	peer := session.network.peers[peer_index]
	platform.log_printf("network: %s disconnected: %s", peer.connection.address, peer.connection.problem)
	for index in 0 ..< peer.player_count {
		leave_peer_player(session, peer.connection.address, peer.players[index])
	}
	platform.destroy_connection(&session.network.peers[peer_index].connection)
	ordered_remove(&session.network.peers, peer_index)
	if peer_joined(peer) {
		notice_player_count(session)
	}
}

// A client's split screen player leaves; its machine's own player stays.
drop_peer_player :: proc(session: ^Session, peer_index, index: int) {
	peer := &session.network.peers[peer_index]
	leave_peer_player(session, peer.connection.address, peer.players[index])
	for after in index + 1 ..< peer.player_count {
		peer.players[after - 1] = peer.players[after]
	}
	peer.player_count -= 1
}

Join_Snapshot :: struct {
	cheat_speed: bool,
	free_crafting: bool,
	files:       Save_Files,
	// The host's simulated chunk radii: every machine derives the set
	// alike, whatever its own game.sjson says.
	chunk_radius: [2]i32,
	chunks:      []Chunk_Coordinate,
	members:     []Lockstep_Member,
	records:     [dynamic]Input_Record,
}

// The save, the simulated chunk set, the members and the records after
// the host's tick, in the temp allocator. The joiner's player comes
// later (request_own_player). The loaded columns' surfaces are refreshed
// first, as a save does (lockstep_state_hash does the same on every
// machine).
encode_join_snapshot :: proc(simulation: ^Simulation_State, lockstep: ^Lockstep, content: Simulation_Content, name: string) -> []byte {
	refresh_loaded_surfaces(&simulation.world, &simulation.records.explored)
	files := encode_save_files(simulation, content, name, 0)
	bytes := message_of(.Join_Snapshot)
	append_u8(&bytes, simulation.cheat_speed ? 1 : 0)
	append_u8(&bytes, simulation.free_crafting ? 1 : 0)
	append_bytes(&bytes, files.world)
	append_bytes(&bytes, files.entities)
	append_u32(&bytes, u32(len(files.regions)))
	for region in files.regions {
		append_string(&bytes, region.name)
		append_bytes(&bytes, region.bytes)
	}
	append_bytes(&bytes, files.field)
	chunks := make([dynamic]Chunk_Coordinate, 0, len(simulation.chunk_set.chunks), context.temp_allocator)
	for coordinate in simulation.chunk_set.chunks {
		append(&chunks, coordinate)
	}
	slice.sort_by(chunks[:], chunk_coordinate_before)
	append_u8(&bytes, simulation.chunk_set.enabled ? 1 : 0)
	append_u32(&bytes, u32(simulation.chunk_set.horizontal_radius))
	append_u32(&bytes, u32(simulation.chunk_set.vertical_radius))
	append_u32(&bytes, u32(len(chunks)))
	for coordinate in chunks {
		for axis in 0 ..< 3 {
			append_u32(&bytes, u32(coordinate[axis]))
		}
	}
	append_u32(&bytes, u32(len(lockstep.members)))
	for &member in lockstep.members {
		write_value_of(&bytes, &member)
	}
	held := 0
	for record in lockstep.records {
		held += record.tick > simulation.tick ? 1 : 0
	}
	append_u32(&bytes, u32(held))
	for record in lockstep.records {
		if record.tick > simulation.tick {
			encode_input_record(&bytes, record)
		}
	}
	return bytes[:]
}

// Views into payload, except the records, which the caller owns. False
// for malformed bytes.
decode_join_snapshot :: proc(payload: []byte) -> (snapshot: Join_Snapshot, chunk_set_enabled: bool, ok: bool) {
	reader := Byte_Reader{data = payload}
	if Lockstep_Message_Kind(read_u8(&reader) or_return) != .Join_Snapshot {
		return {}, false, false
	}
	snapshot.cheat_speed = (read_u8(&reader) or_return) == 1
	snapshot.free_crafting = (read_u8(&reader) or_return) == 1
	snapshot.files.world = read_bytes(&reader) or_return
	snapshot.files.entities = read_bytes(&reader) or_return
	region_count := int(read_u32(&reader) or_return)
	if region_count > bytes_left(reader) {
		return {}, false, false
	}
	snapshot.files.regions = make([dynamic]Region_File, 0, region_count, context.temp_allocator)
	for _ in 0 ..< region_count {
		region_name := read_string(&reader) or_return
		region_bytes := read_bytes(&reader) or_return
		append(&snapshot.files.regions, Region_File{name = region_name, bytes = region_bytes})
	}
	snapshot.files.field = read_bytes(&reader) or_return
	chunk_set_enabled = (read_u8(&reader) or_return) == 1
	snapshot.chunk_radius.x = i32(read_u32(&reader) or_return)
	snapshot.chunk_radius.y = i32(read_u32(&reader) or_return)
	if chunk_set_enabled && !(within_radius_limit(snapshot.chunk_radius.x) && within_radius_limit(snapshot.chunk_radius.y)) {
		return {}, false, false
	}
	chunk_count := int(read_u32(&reader) or_return)
	if chunk_count > bytes_left(reader) {
		return {}, false, false
	}
	chunks := make([]Chunk_Coordinate, chunk_count, context.temp_allocator)
	for &coordinate in chunks {
		for axis in 0 ..< 3 {
			coordinate[axis] = i32(read_u32(&reader) or_return)
		}
	}
	snapshot.chunks = chunks
	member_count := int(read_u32(&reader) or_return)
	if member_count > bytes_left(reader) {
		return {}, false, false
	}
	members := make([]Lockstep_Member, member_count, context.temp_allocator)
	for &member in members {
		read_value_of(&reader, &member) or_return
	}
	snapshot.members = members
	record_count := int(read_u32(&reader) or_return)
	if record_count > bytes_left(reader) {
		return {}, false, false
	}
	for _ in 0 ..< record_count {
		record, record_ok := decode_input_record(&reader)
		if !record_ok {
			destroy_join_records(&snapshot.records)
			return {}, false, false
		}
		append(&snapshot.records, record)
	}
	return snapshot, chunk_set_enabled, true
}

within_radius_limit :: proc(radius: i32) -> bool {
	return radius >= 1 && radius <= MAXIMUM_SIMULATED_CHUNK_RADIUS
}

destroy_join_records :: proc(records: ^[dynamic]Input_Record) {
	for record in records {
		destroy_input_record(record)
	}
	delete(records^)
}

// The joiner gets the world and from then on every record, but no member
// (0190): no machine waits for it while it restores, and one that drops
// before it asked for its player (Add_Local_Player) leaves nothing behind.
host_join :: proc(session: ^Session, content: Simulation_Content, name: string, peer_index: int) {
	network := &session.network
	peer := &network.peers[peer_index]
	snapshot := encode_join_snapshot(&session.simulation, &session.lockstep, content, name)
	peer.snapshot_size = len(snapshot)
	peer.receives_records = true
	platform.send_message(&peer.connection, snapshot)
	platform.log_printf("network: %s gets the world at tick %d", peer.connection.address, session.simulation.tick)
}

// The tick a player joining now takes, and the entry, as for a join: the
// tick after the newest record relayed (frontier, 0 offline), so no
// machine has run it yet.
next_join :: proc(session: ^Session) -> (player: int, member: Lockstep_Member) {
	join_tick := max(session.network.frontier, session.simulation.tick) + 1
	adds_entry: bool
	player, adds_entry = joining_player_index(session.lockstep, len(session.simulation.players), join_tick)
	return player, Lockstep_Member{joined_tick = join_tick, left_tick = NEVER_TICK, adds_entry = adds_entry}
}

// A client's machine adds a player: its own once its world caught up
// (0190), or a split screen player (0178), over the connection it already
// has, announced to every machine and answered with the player and its
// join tick. The machine's own player is counted in the host's notice.
host_add_peer_player :: proc(session: ^Session, peer_index: int) {
	player, member := next_join(session)
	broadcast_member(session, player, member)
	peer := &session.network.peers[peer_index]
	own := peer.player_count == 0
	peer.players[peer.player_count] = Peer_Player{player = player, last_tick = member.joined_tick - 1, joined_tick = member.joined_tick}
	peer.player_count += 1
	bytes := message_of(.Local_Player_Added)
	append_u32(&bytes, u32(player))
	append_u64(&bytes, member.joined_tick)
	platform.send_message(&peer.connection, bytes[:])
	network_notice(&session.network, "player %d (%s) joins at tick %d", player, peer.connection.address, member.joined_tick)
	if own {
		notice_player_count(session)
	}
}

// A local player for a split screen viewport (0178), through the add
// player path of a join (next_join): offline and on the host it is a
// local member at once, a client asks the host and the member arrives with
// Local_Player_Added (handle_host_message). Returns the player, NO_PLAYER
// while a client waits. The entry exists from the join tick on.
request_local_player :: proc(session: ^Session) -> int {
	switch session.network.role {
	case .Offline, .Host:
		player, member := next_join(session)
		if session.network.role == .Host {
			broadcast_member(session, player, member)
		} else {
			set_lockstep_member(&session.lockstep, player, member)
		}
		add_local_member(&session.lockstep, player, member.joined_tick)
		platform.log_printf("network: local player %d joins at tick %d", player, member.joined_tick)
		return player
	case .Client:
		if len(session.network.peers) > 0 {
			bytes := message_of(.Add_Local_Player)
			platform.send_message(&session.network.peers[0].connection, bytes[:])
		}
	}
	return NO_PLAYER
}

// A split screen viewport's player leaves (0178) from the tick after its
// last stamped record; its entry stays in the world for a later join. The
// machine's own player never leaves this way. A client's records already
// went to the host this frame, ahead of the message on the connection.
leave_local_player :: proc(session: ^Session, player: int) {
	index := find_local_member(session.lockstep, player)
	if index <= 0 {
		return
	}
	left_tick := local_member_left_tick(session.lockstep.locals[index])
	remove_local_member(&session.lockstep, index)
	member := session.lockstep.members[player]
	member.left_tick = max(left_tick, member.joined_tick)
	switch session.network.role {
	case .Offline:
		set_lockstep_member(&session.lockstep, player, member)
	case .Host:
		broadcast_member(session, player, member)
	case .Client:
		send_remove_local_player(&session.network, player)
	}
	platform.log_printf("network: local player %d leaves at tick %d", player, member.left_tick)
}

// A client's split screen player leaves; the host picks the tick
// (leave_peer_player).
send_remove_local_player :: proc(network: ^Session_Network, player: int) {
	if len(network.peers) > 0 {
		bytes := message_of(.Remove_Local_Player)
		append_u32(&bytes, u32(player))
		platform.send_message(&network.peers[0].connection, bytes[:])
	}
}

// A joiner without a player (0190) asks for its own once, through the
// add player path (Local_Player_Added makes it the first local member).
request_own_player :: proc(session: ^Session) {
	if session.network.role != .Client || session.network.own_player_requested || len(session.lockstep.locals) > 0 {
		return
	}
	session.network.own_player_requested = true
	request_local_player(session)
	platform.log_printf("network: caught up at tick %d, asking for a player", session.simulation.tick)
}

// A viewport that asked the host for a player and leaves before the
// answer: the answer, when it lands, leaves at once.
cancel_local_player_request :: proc(session: ^Session) {
	if session.network.role == .Client {
		session.network.cancelled_local_players += 1
	}
}

// The host's own hashes kept for late reports.
KEPT_HOST_HASHES :: 16

// Host: its own hash for the tick, then every report it can compare. A
// report older than the oldest hash kept can never be compared and goes.
record_host_hash :: proc(network: ^Session_Network, tick, hash: u64) {
	network.hashes[tick] = hash
	compare_hash_reports(network)
	stale := make([dynamic]u64, context.temp_allocator)
	for kept in network.hashes {
		if kept + KEPT_HOST_HASHES * STATE_HASH_INTERVAL_TICKS < tick {
			append(&stale, kept)
		}
	}
	for kept in stale {
		delete_key(&network.hashes, kept)
	}
	kept := 0
	for report in network.reports {
		if report.tick + KEPT_HOST_HASHES * STATE_HASH_INTERVAL_TICKS < tick {
			delete(report.machine)
			continue
		}
		network.reports[kept] = report
		kept += 1
	}
	resize(&network.reports, kept)
}

compare_hash_reports :: proc(network: ^Session_Network) {
	kept := 0
	for report in network.reports {
		host_hash, known := network.hashes[report.tick]
		if !known {
			network.reports[kept] = report
			kept += 1
			continue
		}
		if host_hash != report.hash {
			network.mismatch_count += 1
			network_notice(network, "state hash mismatch at tick %d: host %16x, %s %16x", report.tick, host_hash, report.machine, report.hash)
			message := hash_mismatch_message(report.tick, host_hash, report.hash, report.machine)
			for &peer in network.peers {
				platform.send_message(&peer.connection, message)
			}
		}
		delete(report.machine)
	}
	resize(&network.reports, kept)
}

// Clients.

// Starts connecting to the host on a thread (platform.start_dial); the
// ping, the join and the snapshot follow in update_client_network.
start_joining :: proc(network: ^Session_Network, address: string, tick_rate: int) {
	network.role = .Client
	network.tick_rate = tick_rate
	network.dial = platform.start_dial(address)
	network.join_started = time.tick_now()
	platform.log_printf("network: connecting to %s", address)
}

// The window a joiner asks for and plays with: the measured round trip in
// ticks (latency_window_ticks), at most MAXIMUM_JOIN_WINDOW.
join_window :: proc(network: Session_Network) -> int {
	return min(latency_window_ticks(network.round_trip, network.tick_rate), MAXIMUM_JOIN_WINDOW)
}

// The dial's outcome: the host's peer and the first ping once connected,
// a lost host when it failed or took longer than NETWORK_TIMEOUT.
finish_dial :: proc(network: ^Session_Network) {
	connection, problem, done := platform.take_dial(network.dial)
	switch {
	case !done && time.tick_since(network.join_started) >= NETWORK_TIMEOUT:
		platform.abandon_dial(network.dial)
		network.dial = nil
		network.host_lost = true
		network_notice(network, "the host did not answer within %v", NETWORK_TIMEOUT)
	case !done:
	case problem != "":
		network.dial = nil
		network.host_lost = true
		network_notice(network, "%s", problem)
		delete(problem)
	case:
		network.dial = nil
		now := time.tick_now()
		append(&network.peers, Network_Peer{connection = connection, last_heard = now, last_ping = now})
		network.ping_sent = now
		ping := message_of(.Ping)
		platform.send_message(&network.peers[0].connection, ping[:])
		platform.log_printf("network: connected to %s", connection.address)
	}
}

// The client's frame: the host's messages in, the local records and
// hashes out. lockstep is nil until the session exists.
update_client_network :: proc(network: ^Session_Network, lockstep: ^Lockstep, simulation_tick: u64, content: Simulation_Content) {
	if network.dial != nil {
		finish_dial(network)
	}
	if len(network.peers) == 0 {
		return
	}
	host := &network.peers[0]
	platform.poll_connection(&host.connection)
	for {
		payload, ok := platform.take_message(&host.connection, context.temp_allocator)
		if !ok {
			break
		}
		handle_host_message(network, lockstep, simulation_tick, content, payload)
	}
	keep_peer_alive(host)
	if lockstep != nil {
		for record in lockstep.outgoing {
			platform.send_message(&host.connection, record_message(record))
			destroy_input_record(record)
		}
		clear(&lockstep.outgoing)
	}
	platform.flush_connection(&host.connection)
	if !host.connection.open && !network.host_lost {
		network.host_lost = true
		network_notice(network, "the host %s left: %s", host.connection.address, host.connection.problem)
	}
}

handle_host_message :: proc(network: ^Session_Network, lockstep: ^Lockstep, simulation_tick: u64, content: Simulation_Content, payload: []byte) {
	reader := Byte_Reader{data = payload}
	kind, kind_ok := read_u8(&reader)
	if !kind_ok {
		return
	}
	message_kind := Lockstep_Message_Kind(kind)
	if lockstep == nil && network.snapshot != nil && (message_kind == .Input_Record || message_kind == .Member_Change) {
		append(&network.held_messages, slice.clone(payload))
		return
	}
	#partial switch message_kind {
	case .Ping:
		payload := payload
		payload[0] = u8(Lockstep_Message_Kind.Pong)
		platform.send_message(&network.peers[0].connection, payload)
	case .Pong:
		if !network.join_requested {
			network.round_trip = time.duration_seconds(time.tick_since(network.ping_sent))
			network.join_requested = true
			platform.send_message(&network.peers[0].connection, join_request_message(join_window(network^), BUILD_STAMP, content_tables_hash(content)))
			platform.log_printf("network: round trip %.1f ms, asking to join", network.round_trip * 1000)
		}
	case .Join_Refused:
		reason, _ := read_string(&reader)
		network.host_lost = true
		network_notice(network, "the host refused the join: %s", reason)
		platform.close_connection(&network.peers[0].connection, "refused")
	case .Join_Snapshot:
		if network.snapshot == nil && lockstep == nil {
			network.snapshot = slice.clone(payload)
		}
	case .Input_Record:
		if record, ok := decode_input_record(&reader); ok && lockstep != nil {
			receive_input_record(lockstep, record, simulation_tick)
		} else if ok {
			destroy_input_record(record)
		}
	case .Member_Change:
		player, player_ok := read_u32(&reader)
		member: Lockstep_Member
		if player_ok && read_value_of(&reader, &member) && lockstep != nil && int(player) <= len(lockstep.members) + 64 {
			set_lockstep_member(lockstep, int(player), member)
		}
	case .Local_Player_Added:
		player, player_ok := read_u32(&reader)
		join_tick, tick_ok := read_u64(&reader)
		// The host announced the member first (Member_Change), with the
		// same join tick.
		valid := player_ok && tick_ok && lockstep != nil && int(player) < len(lockstep.members) && lockstep.members[int(player)].joined_tick == join_tick
		switch {
		case !valid:
		case network.cancelled_local_players > 0:
			network.cancelled_local_players -= 1
			send_remove_local_player(network, int(player))
			platform.log_printf("network: local player %d left before its join tick %d", player, join_tick)
		case len(lockstep.locals) < MAXIMUM_VIEWPORTS && find_local_member(lockstep^, int(player)) < 0:
			add_local_member(lockstep, int(player), join_tick)
			platform.log_printf("network: local player %d joins at tick %d", player, join_tick)
		}
	case .Hash_Mismatch:
		tick, _ := read_u64(&reader)
		host_hash, _ := read_u64(&reader)
		machine_hash, _ := read_u64(&reader)
		machine, _ := read_string(&reader)
		network.mismatch_count += 1
		network_notice(network, "state hash mismatch at tick %d: host %16x, %s %16x", tick, host_hash, machine, machine_hash)
	}
}

// Client: sends its hash of a due tick to the host.
send_hash_report :: proc(network: ^Session_Network, tick, hash: u64) {
	if network.role == .Client && len(network.peers) > 0 {
		platform.send_message(&network.peers[0].connection, hash_report_message(tick, hash))
	}
}

// The machine's hash of a due tick: the host keeps its own, a client
// sends its own. Offline nothing is hashed.
report_state_hash :: proc(network: ^Session_Network, simulation: ^Simulation_State) {
	if network.role == .Offline || !state_hash_due(simulation.tick) {
		return
	}
	hash := lockstep_state_hash(simulation)
	switch network.role {
	case .Host:
		record_host_hash(network, simulation.tick, hash)
	case .Client:
		send_hash_report(network, simulation.tick, hash)
	case .Offline:
	}
}

// The joiner's session from the host's snapshot: the world loaded from
// the save's bytes, the host's simulated chunk set and members, the
// records it held and the window from the round trip; no local player
// until it asks for one (request_own_player).
// Returns nil and the problem when the snapshot does not load.
start_joined_session :: proc(network: ^Session_Network, config: Game_Config, content: Game_Content, base_generator: Generator) -> (session: ^Session, problem: string) {
	payload := network.snapshot
	network.snapshot = nil
	defer delete(payload)
	snapshot, chunk_set_enabled, ok := decode_join_snapshot(payload)
	if !ok {
		return nil, "the host's world is malformed or truncated"
	}
	file: World_File
	if file, problem = parse_world_file(snapshot.files.world, context.temp_allocator); problem != "" {
		destroy_join_records(&snapshot.records)
		return nil, problem
	}
	plan := Session_Plan {
		loading  = true,
		seed     = file.seed,
		settings = file.settings,
		file     = file,
		files    = &snapshot.files,
	}
	if session, problem = start_session(plan, config, content, base_generator); problem != "" {
		destroy_join_records(&snapshot.records)
		return nil, problem
	}
	adopt_join_snapshot(&session.simulation, &session.lockstep, snapshot, chunk_set_enabled, join_window(network^))
	session.network = network^
	network^ = {}
	take_held_messages(&session.network, &session.lockstep, session.simulation.tick, content.simulation_content)
	return session, ""
}

// The messages that arrived with the snapshot, into the driver in the
// order they came.
take_held_messages :: proc(network: ^Session_Network, lockstep: ^Lockstep, simulation_tick: u64, content: Simulation_Content) {
	if len(network.held_messages) > 0 {
		platform.log_printf("network: %d messages arrived with the snapshot", len(network.held_messages))
	}
	for message in network.held_messages {
		handle_host_message(network, lockstep, simulation_tick, content, message)
		delete(message)
	}
	clear(&network.held_messages)
}

// The parts of the snapshot the save does not hold. The records move into
// the driver. The machine drives no player yet.
adopt_join_snapshot :: proc(simulation: ^Simulation_State, lockstep: ^Lockstep, snapshot: Join_Snapshot, chunk_set_enabled: bool, window: int) {
	simulation.cheat_speed = snapshot.cheat_speed
	simulation.free_crafting = snapshot.free_crafting
	simulation.chunk_set.enabled = chunk_set_enabled
	simulation.chunk_set.horizontal_radius, simulation.chunk_set.vertical_radius = snapshot.chunk_radius.x, snapshot.chunk_radius.y
	clear(&simulation.chunk_set.chunks)
	for coordinate in snapshot.chunks {
		simulation.chunk_set.chunks[coordinate] = {}
	}
	clear(&lockstep.members)
	append(&lockstep.members, ..snapshot.members)
	for &local in lockstep.locals {
		destroy_local_member(&local)
	}
	clear(&lockstep.locals)
	lockstep.window = window
	for record in snapshot.records {
		receive_input_record(lockstep, record, simulation.tick)
	}
	delete(snapshot.records)
	platform.log_printf("network: got the world at tick %d, window %d ticks", simulation.tick, window)
}
