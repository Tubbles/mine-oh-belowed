package game

import "core:slice"
import "core:time"

// The lockstep driver (work item 0177): every machine of a session runs
// the whole simulation, and a tick runs only when every connected player's
// input record for it is there. A record is one player's input for one
// tick, stamped with the tick: the Input_Frame without the raw device
// state, the player's queued commands (player_command.odin) and the
// command socket's lines. Each machine stamps its local player's records,
// sends them to the host, and the host relays every player's records to
// everyone, itself included (session_network.odin); single player is the
// same driver with one player, no network and a window of zero, so its
// records come straight back and the game ticks as before.
//
// The window: a machine stamps its local records up to window ticks
// ahead of the simulation (set at join from the measured round trip,
// about the round trip in ticks plus one), so the other players' records
// for a tick are there by the time it runs. Inside the window the local
// player's movement and camera are predicted: after the frame's ticks the
// prediction is the confirmed local player, copied, moved by every local
// input stamped and not yet run (predict_player_motion). A confirmed tick
// whose inputs the prediction already used gives the same position; one
// where the world differed (another player, a belt, a block placed)
// replaces the prediction with the confirmed player on the next rebuild,
// so the reconciliation is the rebuild itself. Only the presentation reads
// the prediction.

// Every machine hashes its state at the ticks that are a multiple of this
// and the host compares (session_network.odin): five seconds at 60 Hz.
STATE_HASH_INTERVAL_TICKS :: 300
// A member that never joined, or never left.
NEVER_TICK :: max(u64)

// The part of an Input_Frame the tick reads, without the raw device state
// (Raw_Input), so a record is plain data that crosses the network.
Record_Input :: struct {
	move:          [2]f32,
	look:          [2]f32,
	look_delta:    [2]f32,
	pressed:       Action_Set,
	just_pressed:  Action_Set,
	sneak_toggles: bool,
	sprint_holds:  bool,
	developer:     bool,
	world_blocked: bool,
	aim_direction: [3]f32,
	aim_overrides: bool,
}

// A command socket line (command.odin) to run at the start of the tick
// it was stamped for. blueprint holds the file's text for a blueprint
// line, read on the machine that sent it. client is the socket client
// that waits for the answer on that machine. Strings are owned.
Socket_Line :: struct {
	line:      string,
	blueprint: string,
	client:    u64,
}

Input_Record :: struct {
	tick:     u64,
	player:   int,
	input:    Record_Input,
	commands: [dynamic]Player_Command,
	lines:    [dynamic]Socket_Line,
}

// Whose records a tick needs: a player is connected from joined_tick up to
// before left_tick. adds_entry: the join appends the player's entry to the
// simulation's players at joined_tick (Add_Player_Command); otherwise the
// player takes over an entry the save already has.
Lockstep_Member :: struct {
	joined_tick: u64,
	left_tick:   u64,
	adds_entry:  bool,
}

// A local record stamped and not run yet: its input for the prediction,
// a copy of its commands for the screens' pending state
// (lockstep_unconfirmed_commands).
Stamped_Input :: struct {
	tick:     u64,
	input:    Input_Frame,
	commands: [dynamic]Player_Command,
}

// A socket line of the tick about to run, with the player whose record
// carried it.
Tick_Line :: struct {
	player: int,
	line:   Socket_Line,
}

Lockstep :: struct {
	// The player this machine's input drives, NO_PLAYER on the server.
	local_player:     int,
	// Ticks the local records run ahead of the simulation.
	window:           int,
	// The tick of the first local record (a joiner's join tick).
	first_local_tick: u64,
	next_local_tick:  u64,
	// Where a joining player's new entry spawns.
	spawn:            Player_Start,
	members:          [dynamic]Lockstep_Member,
	// Received records of ticks not run yet, any order.
	records:          [dynamic]Input_Record,
	// Local records for the host (or straight back when offline).
	outgoing:         [dynamic]Input_Record,
	// The local player's commands and the socket's lines waiting for the
	// next local record.
	local_commands:   [dynamic]Player_Command,
	local_lines:      [dynamic]Socket_Line,
	// The local inputs stamped and not yet run, oldest first, and the
	// predicted local player built from them.
	predicted_inputs: [dynamic]Stamped_Input,
	prediction:       Player,
	predicting:       bool,
	// The accumulator's ticks not taken yet by a tick no player paces.
	clock_ticks:      int,
}

// One local player, connected from the start, window zero.
make_single_player_lockstep :: proc(simulation_tick: u64, spawn: Player_Start) -> Lockstep {
	lockstep := Lockstep {
		local_player     = 0,
		first_local_tick = simulation_tick + 1,
		next_local_tick  = simulation_tick + 1,
		spawn            = spawn,
	}
	append(&lockstep.members, Lockstep_Member{joined_tick = 0, left_tick = NEVER_TICK})
	return lockstep
}

destroy_input_record :: proc(record: Input_Record) {
	for command in record.commands {
		destroy_player_command(command)
	}
	delete(record.commands)
	for line in record.lines {
		destroy_socket_line(line)
	}
	delete(record.lines)
}

destroy_socket_line :: proc(line: Socket_Line) {
	delete(line.line)
	delete(line.blueprint)
}

destroy_lockstep :: proc(lockstep: ^Lockstep) {
	for record in lockstep.records {
		destroy_input_record(record)
	}
	for record in lockstep.outgoing {
		destroy_input_record(record)
	}
	for command in lockstep.local_commands {
		destroy_player_command(command)
	}
	for line in lockstep.local_lines {
		destroy_socket_line(line)
	}
	delete(lockstep.members)
	delete(lockstep.records)
	delete(lockstep.outgoing)
	delete(lockstep.local_commands)
	delete(lockstep.local_lines)
	for stamped in lockstep.predicted_inputs {
		delete(stamped.commands)
	}
	delete(lockstep.predicted_inputs)
	lockstep^ = {}
}

// Input_Frame is Record_Input plus the raw device state: a field added to
// the frame and not to the record fails here instead of leaving the
// record silently.
#assert(size_of(Input_Frame) == size_of(Record_Input) + size_of(Raw_Input))

record_input_of :: proc(frame: Input_Frame) -> Record_Input {
	return Record_Input {
		move = frame.move,
		look = frame.look,
		look_delta = frame.look_delta,
		pressed = frame.pressed,
		just_pressed = frame.just_pressed,
		sneak_toggles = frame.sneak_toggles,
		sprint_holds = frame.sprint_holds,
		developer = frame.developer,
		world_blocked = frame.world_blocked,
		aim_direction = frame.aim_direction,
		aim_overrides = frame.aim_overrides,
	}
}

input_frame_of :: proc(input: Record_Input) -> Input_Frame {
	return Input_Frame {
		move = input.move,
		look = input.look,
		look_delta = input.look_delta,
		pressed = input.pressed,
		just_pressed = input.just_pressed,
		sneak_toggles = input.sneak_toggles,
		sprint_holds = input.sprint_holds,
		developer = input.developer,
		world_blocked = input.world_blocked,
		aim_direction = input.aim_direction,
		aim_overrides = input.aim_overrides,
	}
}

member_connected :: proc(member: Lockstep_Member, tick: u64) -> bool {
	return member.joined_tick <= tick && tick < member.left_tick
}

// The members connected at the tick.
connected_member_count :: proc(lockstep: Lockstep, tick: u64) -> int {
	count := 0
	for member in lockstep.members {
		count += member_connected(member, tick) ? 1 : 0
	}
	return count
}

// The local player's commands the screens queued on the simulation move
// to the lockstep until the next local record carries them, so a tick
// never applies a command no other machine has.
hold_local_commands :: proc(lockstep: ^Lockstep, simulation: ^Simulation_State) {
	kept := 0
	for queued in simulation.player_commands {
		if lockstep.local_player != NO_PLAYER && queued.player == lockstep.local_player && command_is_relayed(queued.command) {
			append(&lockstep.local_commands, queued.command)
		} else {
			simulation.player_commands[kept] = queued
			kept += 1
		}
	}
	resize(&simulation.player_commands, kept)
}

// The last tick a local record may be stamped for now: window ticks past
// the next tick to run, counted from the join while a joiner catches up.
local_stamp_limit :: proc(lockstep: Lockstep, simulation_tick: u64) -> u64 {
	return max(simulation_tick, lockstep.first_local_tick - 1) + u64(lockstep.window) + 1
}

// One local record for the next local tick, with the held commands and
// lines. False, and nothing taken, without a local player or while the
// records are window ticks ahead (the input keeps accumulating).
stamp_local_record :: proc(lockstep: ^Lockstep, simulation_tick: u64, frame: Input_Frame) -> bool {
	if lockstep.local_player == NO_PLAYER || lockstep.next_local_tick > local_stamp_limit(lockstep^, simulation_tick) {
		return false
	}
	// A tick command ran ticks without records (single player only).
	lockstep.next_local_tick = max(lockstep.next_local_tick, simulation_tick + 1)
	record := Input_Record {
		tick   = lockstep.next_local_tick,
		player = lockstep.local_player,
		input  = record_input_of(frame),
	}
	append(&record.commands, ..lockstep.local_commands[:])
	clear(&lockstep.local_commands)
	append(&record.lines, ..lockstep.local_lines[:])
	clear(&lockstep.local_lines)
	append(&lockstep.outgoing, record)
	stamped := Stamped_Input{tick = record.tick, input = input_frame_of(record.input)}
	append(&stamped.commands, ..record.commands[:])
	append(&lockstep.predicted_inputs, stamped)
	lockstep.next_local_tick += 1
	return true
}

// A record from the host (or the local machine's own when offline). Owned
// by the lockstep from here. A record of a tick that ran already is
// dropped.
receive_input_record :: proc(lockstep: ^Lockstep, record: Input_Record, simulation_tick: u64) {
	if record.tick <= simulation_tick {
		destroy_input_record(record)
		return
	}
	append(&lockstep.records, record)
}

// Offline: the local records are the relayed ones.
deliver_outgoing_locally :: proc(lockstep: ^Lockstep, simulation_tick: u64) {
	for record in lockstep.outgoing {
		receive_input_record(lockstep, record, simulation_tick)
	}
	clear(&lockstep.outgoing)
}

find_input_record :: proc(records: []Input_Record, tick: u64, player: int) -> int {
	for record, index in records {
		if record.tick == tick && record.player == player {
			return index
		}
	}
	return -1
}

// Every connected player's record for the next tick is there.
lockstep_records_ready :: proc(lockstep: Lockstep, simulation_tick: u64) -> bool {
	tick := simulation_tick + 1
	for member, player in lockstep.members {
		if member_connected(member, tick) && find_input_record(lockstep.records[:], tick, player) < 0 {
			return false
		}
	}
	return true
}

// Takes the next tick's records: a joining player's entry and every
// player's commands go onto the simulation's list in player order, the
// inputs (in the temp allocator) and the socket lines are returned for
// the caller, which runs the lines and then simulation_tick.
begin_lockstep_tick :: proc(lockstep: ^Lockstep, simulation: ^Simulation_State) -> (inputs: []Input_Frame, lines: []Tick_Line) {
	hold_local_commands(lockstep, simulation)
	tick := simulation.tick + 1
	for member, player in lockstep.members {
		if member.joined_tick == tick && member.adds_entry {
			queue_player_command(&simulation.player_commands, player, Add_Player_Command{start = lockstep.spawn})
		}
	}
	inputs = make([]Input_Frame, max(len(simulation.players), len(lockstep.members)), context.temp_allocator)
	tick_lines := make([dynamic]Tick_Line, context.temp_allocator)
	for player in 0 ..< len(lockstep.members) {
		index := find_input_record(lockstep.records[:], tick, player)
		if index < 0 {
			continue
		}
		record := lockstep.records[index]
		unordered_remove(&lockstep.records, index)
		inputs[player] = input_frame_of(record.input)
		for command in record.commands {
			queue_player_command(&simulation.player_commands, player, command)
		}
		for line in record.lines {
			append(&tick_lines, Tick_Line{player = player, line = line})
		}
		delete(record.commands)
		delete(record.lines)
	}
	return inputs, tick_lines[:]
}

// After a tick: the inputs it confirmed leave the prediction, records of
// players not connected at it are dropped.
finish_lockstep_tick :: proc(lockstep: ^Lockstep, simulation_tick: u64) {
	confirmed := 0
	for confirmed < len(lockstep.predicted_inputs) && lockstep.predicted_inputs[confirmed].tick <= simulation_tick {
		delete(lockstep.predicted_inputs[confirmed].commands)
		confirmed += 1
	}
	remove_range(&lockstep.predicted_inputs, 0, confirmed)
	for index := len(lockstep.records) - 1; index >= 0; index -= 1 {
		if lockstep.records[index].tick <= simulation_tick {
			destroy_input_record(lockstep.records[index])
			unordered_remove(&lockstep.records, index)
		}
	}
}

// The predicted local player: the confirmed one moved by the local inputs
// not confirmed yet. Off with a window of zero (nothing is ever ahead) or
// without a local player.
rebuild_prediction :: proc(lockstep: ^Lockstep, simulation: ^Simulation_State, content: Simulation_Content) {
	local := lockstep.local_player
	lockstep.predicting = lockstep.window > 0 && local != NO_PLAYER && local < len(simulation.players)
	if !lockstep.predicting {
		return
	}
	lockstep.prediction = simulation.players[local]
	for stamped in lockstep.predicted_inputs {
		if stamped.tick > simulation.tick {
			predict_player_motion(&simulation.world, content, &lockstep.prediction, stamped.input, simulation.tick_rate, simulation.cheat_speed)
		}
	}
}

// The local player's commands no tick has applied yet: the ones waiting
// for the next record and the ones in records stamped and not run. With
// the frame's queue (Simulation_State.player_commands) they are what a
// screen shows as pending. In the temp allocator.
lockstep_unconfirmed_commands :: proc(lockstep: ^Lockstep) -> []Player_Command {
	commands := make([dynamic]Player_Command, context.temp_allocator)
	for stamped in lockstep.predicted_inputs {
		append(&commands, ..stamped.commands[:])
	}
	append(&commands, ..lockstep.local_commands[:])
	return commands[:]
}

// A tick command runs ticks without records (single player only): the
// local commands waiting for a record go back onto the simulation's list,
// so the tick applies them as it did before the driver.
release_local_commands :: proc(lockstep: ^Lockstep, simulation: ^Simulation_State) {
	for command in lockstep.local_commands {
		queue_player_command(&simulation.player_commands, lockstep.local_player, command)
	}
	clear(&lockstep.local_commands)
}

// The local player as the presentation draws it: the prediction while
// one runs, else the confirmed player.
lockstep_view_player :: proc(lockstep: ^Lockstep, simulation: ^Simulation_State) -> Player {
	if lockstep.predicting {
		return lockstep.prediction
	}
	return simulation.players[max(lockstep.local_player, 0)]
}

// The window from a round trip: the round trip in ticks, rounded up, plus
// one, at least one.
latency_window_ticks :: proc(round_trip_seconds: f64, tick_rate: int) -> int {
	ticks := int(round_trip_seconds * f64(tick_rate))
	if f64(ticks) < round_trip_seconds * f64(tick_rate) {
		ticks += 1
	}
	return max(ticks + 1, 1)
}

// The state the machines compare: the loaded columns' explored surfaces
// are refreshed first, as a save does, so a save taken on one machine
// between two ticks (refresh_loaded_surfaces) changes no hash.
// Beside the save's state it covers cheat speed and the saved chunks of
// the chunks not loaded (the edited chunks outside the simulated set) in
// coordinate order. A loaded chunk's saved entry is left out: the loaded
// blocks are hashed and replace it when the chunk unloads, and only a
// machine that loaded the world from a save holds such entries.
// day_offset_ticks stays out: no tick reads it, only the sky, the weather
// and the save do.
lockstep_state_hash :: proc(simulation: ^Simulation_State) -> u64 {
	refresh_loaded_surfaces(&simulation.world, &simulation.records.explored)
	result := fingerprint_u64(simulation_state_hash(simulation), simulation.cheat_speed ? 1 : 0)
	coordinates := make([dynamic]Chunk_Coordinate, 0, len(simulation.world.saved_chunks), context.temp_allocator)
	for coordinate in simulation.world.saved_chunks {
		if coordinate not_in simulation.world.chunks {
			append(&coordinates, coordinate)
		}
	}
	slice.sort_by(coordinates[:], chunk_coordinate_before)
	for coordinate in coordinates {
		result = fingerprint_u64(result, u64(u32(coordinate.x)) | u64(u32(coordinate.z)) << 32)
		result = fingerprint_u64(result, u64(u32(coordinate.y)))
		result = fingerprint_bytes(result, simulation.world.saved_chunks[coordinate])
	}
	return result
}

state_hash_due :: proc(tick: u64) -> bool {
	return tick % STATE_HASH_INTERVAL_TICKS == 0
}

// The session's ticks.

// Wall time the ready ticks may take per frame: a joiner catching up runs
// as many as fit, the frame keeps drawing.
LOCKSTEP_TICK_WALL_BUDGET :: 100 * time.Millisecond

// A socket line's answer for the machine that sent it (send_line_answers
// in loop.odin). In the temp allocator.
Line_Answer :: struct {
	client:   u64,
	line:     string,
	response: Command_Response,
}

// The command context a socket line runs in, for the player whose record
// carried it.
session_command_context :: proc(session: ^Session, content: Simulation_Content, control: ^Command_Control, player: int, blueprint_text: string) -> Command_Context {
	return Command_Context {
		simulation       = &session.simulation,
		player           = player,
		blueprint_text   = blueprint_text,
		content          = content,
		control          = control,
		weather_override = &session.weather_override,
		now              = time.now(),
	}
}

// Runs the lines; the local machine's are answered.
run_tick_lines :: proc(session: ^Session, content: Simulation_Content, control: ^Command_Control, lines: []Tick_Line, answers: ^[dynamic]Line_Answer) {
	for tick_line in lines {
		command_context := session_command_context(session, content, control, tick_line.player, tick_line.line.blueprint)
		response, empty := execute_command_line(command_context, tick_line.line.line)
		if !empty && tick_line.player == session.lockstep.local_player && tick_line.line.client != 0 {
			append(answers, Line_Answer{client = tick_line.line.client, line = clone_text_temp(tick_line.line.line), response = response})
		}
		destroy_socket_line(tick_line.line)
	}
}

clone_text_temp :: proc(text: string) -> string {
	return string(slice.clone(transmute([]byte)text, context.temp_allocator))
}

// What the tick's hook needs to run the records' socket lines.
Tick_Lines :: struct {
	session: ^Session,
	content: Simulation_Content,
	control: ^Command_Control,
	lines:   []Tick_Line,
	answers: ^[dynamic]Line_Answer,
}

run_tick_lines_hook :: proc(data: rawptr) {
	tick_lines := (^Tick_Lines)(data)
	run_tick_lines(tick_lines.session, tick_lines.content, tick_lines.control, tick_lines.lines, tick_lines.answers)
}

// One tick of the driver: the tick, whose hook runs the records' socket
// lines where the commands apply (after the simulated chunk set is
// derived, so a teleport moves the set alike on every machine), and the
// hash when due.
run_session_tick :: proc(session: ^Session, content: Simulation_Content, control: ^Command_Control, answers: ^[dynamic]Line_Answer) {
	inputs, lines := begin_lockstep_tick(&session.lockstep, &session.simulation)
	tick_lines := Tick_Lines{session = session, content = content, control = control, lines = lines, answers = answers}
	simulation_tick(&session.simulation, content, inputs, hook = Tick_Hook{procedure = run_tick_lines_hook, data = &tick_lines})
	finish_lockstep_tick(&session.lockstep, session.simulation.tick)
	report_state_hash(&session.network, &session.simulation)
}

// Every tick whose records and chunks are there, within the wall budget.
// A tick no connected player paces (a server alone) takes one of the
// clock's ticks. Offline, a tick waiting for its chunks still takes the
// ones that arrived, so a new world fills in while it waits; with other
// machines that would make the order of the insertions differ.
run_ready_ticks :: proc(session: ^Session, content: Simulation_Content, control: ^Command_Control, answers: ^[dynamic]Line_Answer) -> int {
	lockstep, simulation := &session.lockstep, &session.simulation
	start := time.tick_now()
	count := 0
	for time.tick_since(start) < LOCKSTEP_TICK_WALL_BUDGET && lockstep_records_ready(lockstep^, simulation.tick) {
		unpaced := connected_member_count(lockstep^, simulation.tick + 1) == 0
		if unpaced && lockstep.clock_ticks == 0 {
			break
		}
		if !simulated_chunks_ready(simulation) {
			if session.network.role == .Offline {
				update_simulated_chunks(simulation, content)
			}
			session.chunk_stalled = true
			break
		}
		session.chunk_stalled = false
		if unpaced {
			lockstep.clock_ticks -= 1
		}
		run_session_tick(session, content, control, answers)
		count += 1
	}
	return count
}

// While a single player session holds its ticks (a pause, a pausing
// screen) the socket's lines run at once, as they did before the driver.
run_held_lines :: proc(session: ^Session, content: Simulation_Content, control: ^Command_Control, answers: ^[dynamic]Line_Answer) {
	lines := make([dynamic]Tick_Line, context.temp_allocator)
	for line in session.lockstep.local_lines {
		append(&lines, Tick_Line{player = session.lockstep.local_player, line = line})
	}
	clear(&session.lockstep.local_lines)
	run_tick_lines(session, content, control, lines[:], answers)
}
