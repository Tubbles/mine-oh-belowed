package game

import "core:time"
import "platform"

// The headless server (work item 0177, --server): the game without a
// window, an input backend or a local player, hosting a lockstep session
// (session_network.odin) on --port, or the first free port of the game's
// range, and answering the LAN's discovery (session_discovery.odin). It
// runs the same driver as every machine: the clients' records pace the
// ticks, and while nobody is connected the clock does (run_ready_ticks),
// except while a joiner restores without a player (0190). It saves on the autosave
// interval of the settings and when SIGINT or SIGTERM stops it
// (platform.install_stop_handlers; not on Windows).
// The command socket is not served here; the clients' socket lines in
// their records run like on every machine.

// The pause between two frames of the server's loop.
SERVER_FRAME_SLEEP :: 2 * time.Millisecond

Server_State :: struct {
	session:          ^Session,
	content:          Game_Content,
	autosave_minutes: int,
	// The socket lines in the records need a control; nothing reads it.
	control:          Command_Control,
}

// The session's driver without a local player: every entry of the save
// waits for a client to take it (joining_player_index).
make_server_lockstep :: proc(session: ^Session) -> Lockstep {
	lockstep := Lockstep {
		spawn = session.start.player,
	}
	for _ in session.simulation.players {
		append(&lockstep.members, Lockstep_Member{joined_tick = NEVER_TICK, left_tick = NEVER_TICK})
	}
	return lockstep
}

// Hosts the session as the plan says. Returns the problem, or "".
start_server :: proc(server: ^Server_State, session: ^Session, content: Game_Content, autosave_minutes: int, plan: Hosting_Plan) -> string {
	destroy_lockstep(&session.lockstep)
	session.lockstep = make_server_lockstep(session)
	session.streaming.mesh_chunks = false
	server^ = Server_State{session = session, content = content, autosave_minutes = autosave_minutes}
	if problem := start_hosting(&session.network, plan); problem != "" {
		return problem
	}
	platform.log_printf("server: hosting on port %d", session.network.listener.port)
	return ""
}

// One frame: the clock, the clients, the ready ticks, the chunks, the
// autosave. Returns the ticks run.
run_server_frame :: proc(server: ^Server_State, frame_seconds: f64) -> int {
	session := server.session
	simulation := &session.simulation
	content := session_simulation_content(server.content, session.technologies, session.field_content)
	content.generator = &session.generator
	tick_count: int
	session.accumulator, tick_count = advance_tick_accumulator(session.accumulator, frame_seconds)
	session.lockstep.clock_ticks = min(session.lockstep.clock_ticks + tick_count, simulation.tick_rate)
	if session.network.role == .Host {
		update_host_network(session, content, session.save.location.display_name)
	}
	answers := make([dynamic]Line_Answer, context.temp_allocator)
	ran := run_ready_ticks(session, content, &server.control, &answers)
	session.ticks_since_save += u64(ran)
	for notice in session.network.notices {
		delete(notice)
	}
	clear(&session.network.notices)
	// Only the UI empties these on a playing machine (logged already).
	clear(&simulation.events)
	clear(&simulation.quests.notices)
	camera_chunk := len(simulation.players) > 0 ? player_chunk(simulation.players[0]) : Chunk_Coordinate{}
	stream_session_chunks(session, camera_chunk, nil)
	if session.save.enabled && autosave_due(session.ticks_since_save, server.autosave_minutes, simulation.tick_rate) {
		save_server_world(server)
	}
	return ran
}

// A failed save is logged and waits for the next interval instead of
// retrying every frame.
save_server_world :: proc(server: ^Server_State) -> string {
	problem := save_session(server.session, server.content)
	if problem != "" {
		platform.log_printf("error: server: cannot save: %s", problem)
		server.session.ticks_since_save = 0
	}
	return problem
}

// Until SIGINT or SIGTERM, then the save. Returns the exit code.
run_server :: proc(server: ^Server_State) -> int {
	platform.install_stop_handlers()
	platform.log_printf("server: running %q at tick %d", server.session.save.location.display_name, server.session.simulation.tick)
	last := time.tick_now()
	for !platform.stop_requested() {
		frame_seconds := time.duration_seconds(time.tick_lap_time(&last))
		run_server_frame(server, frame_seconds)
		free_all(context.temp_allocator)
		time.sleep(SERVER_FRAME_SLEEP)
	}
	platform.log_printf("server: stopping at tick %d", server.session.simulation.tick)
	if server.session.save.enabled && save_server_world(server) != "" {
		return 1
	}
	return 0
}
