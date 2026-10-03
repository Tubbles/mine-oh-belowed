package game

import "core:fmt"
import "core:math"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"
import rl "shared:raylib"
import rlgl "shared:raylib/rlgl"
import "platform"
import "sjson_text"

// Longest frame the accumulator accepts, so that a stall (debugger, window
// drag) does not trigger a burst of catch up ticks.
MAXIMUM_FRAME_SECONDS :: 0.25
// Wall time a tick command (work item 0053) may spend per frame, so the
// window keeps drawing and answering while it runs.
COMMAND_TICK_WALL_BUDGET :: 1 * time.Second

Save_Setup :: struct {
	location: Save_Location,
	enabled:  bool,
}

Tick_Accumulator :: struct {
	seconds_per_tick:    f64,
	accumulated_seconds: f64,
}

// The process: window, renderer, UI and input live for the whole run, the
// session only while a world is played. Without a session the title
// screen shows. The loop's own fields are top level; the rest is in four
// groups by the cluster that reads and writes them (work item 0158), and
// in the viewports (viewport.odin, work item 0178), which hold the per
// player halves of the interaction and presentation groups.
Frame_State :: struct {
	config:             Game_Config,
	content:            Game_Content,
	// The generator data every session copies (session_generator).
	base_generator:     Generator,
	session:            ^Session,
	frame_seconds:      f32,
	// The Render page's frame time average and the ticks update_session
	// ran this frame (work item 0086).
	frame_times:        Frame_Time_Ring,
	frame_tick_count:   int,
	// What the screens and the frame asked for (F8, the data watch and a
	// data edit add Reload_Data), served between frames
	// (serve_frame_requests_before_draw). Top level: the loop serves it.
	requests:           Frame_Requests,
	data_directory:     string,
	environment:        Configuration_Environment,
	settings:           Settings,
	// The settings as last read or written, see write_changed_settings.
	stored_settings:    Settings,
	// --join or the Multiplayer screen: the connection to the host until
	// its world arrives and the session takes it (update_joining).
	joining:            Session_Join,
	// Where the game's own worlds host (session_discovery.odin, 0188);
	// zero in the tests' frames, which then stay offline.
	hosting:            Hosting_Plan,
	// The Multiplayer screen's LAN query while it shows (serve_lan_query).
	lan_query:          Lan_Query,
	// One per local player, the first always there (the title runs in
	// it); viewport_count are in use.
	viewports:          [MAXIMUM_VIEWPORTS]Viewport,
	viewport_count:     int,
	interaction:        Frame_Interaction,
	presentation:       Frame_Presentation,
	developer:          Frame_Developer_Tools,
	reload:             Frame_Reload,
}

// The input devices, the fonts, the touch overlay and the title: the
// process wide half of input and UI. Each viewport's input, Ui_State,
// session views and banner are its Viewport_Interaction.
Frame_Interaction :: struct {
	title:              Title_State,
	input_backend:      Input_Backend,
	// Every open gamepad (input_sdl3.odin); each viewport reads its own.
	sdl3_input:         Sdl3_Input_State,
	// The touch overlay's fingers (touch_overlay.odin), and --touch-overlay.
	// It drives the first viewport.
	touch_overlay:        Touch_Overlay_State,
	touch_overlay_forced: bool,
	// The phone's vibrator: on Android the raylib backend applies the
	// first viewport's rumble through it.
	vibrator:           Vibrator_State,
	// The system keyboard for text fields (work item 0133), read once at
	// start, and whether the game has shown it.
	system_keyboard_available: bool,
	system_keyboard_shown:     bool,
	// The effective bindings, for the settings screen's Controls list.
	bindings:           []Binding,
	input_bindings:     Input_Bindings,
	// The font families and the fonts loaded from them (ui_font.odin, work
	// item 0077); every viewport's ui.fonts points at font_cache. A fonts
	// reload retires the old families' arena until exit (Frame_Reload),
	// settings.font may point into it.
	fonts:              Loaded_Fonts,
	font_cache:         Font_Cache,
	cursor_enabled:     bool,
	// The user touch layouts (0121, touch_overlay.odin), read at start and
	// written by serve_touch_layouts, and the layout editor's draft
	// (ui_touch_layout_editor.odin).
	touch_layouts:        Touch_Layouts,
	touch_layout_editor:  Touch_Layout_Editor,
}

// The renderers, the atlases, the window's display state and the sound:
// the process wide half of presentation. What follows a camera (the
// camera, the cues, the particles, the body's animation) is each
// viewport's Viewport_Presentation.
Frame_Presentation :: struct {
	// The settings as last applied to the window (display.odin), and the
	// monitor's size read while the window was still windowed.
	window_settings:    Settings,
	monitor_size:       [2]int,
	// The window's scale, read every frame, and the windowing platform GLFW
	// took (display.odin, work items 0084 and 0085).
	window_scale:       [2]f32,
	platform:           Window_Platform,
	renderer:           Chunk_Renderer,
	// A field session's terrain renderer (loop_field_session.odin), made
	// when the session starts; ready false outside one or when it did not
	// load.
	field_renderer:       Field_Renderer,
	field_renderer_ready: bool,
	// The frame's field node selection over every viewport's eye, made
	// once (frame_field_selection) and cleared at the end of render_frame;
	// in the temp allocator.
	field_selection:      []Field_Node,
	// The item icons (render_icons.odin), rebuilt with the block atlas;
	// content.items.icon_loaded points into it.
	item_atlas:         Item_Atlas,
	// The UI icons (render_icons.odin, work item 0071), rebuilt with the
	// theme.
	ui_icon_atlas:      Item_Atlas,
	belt_renderer:      Belt_Renderer,
	model_renderer:     Model_Renderer,
	// Particles and feedback (work item 0067, render_particles.odin); the
	// particles themselves are each viewport's.
	particle_renderer:  Particle_Renderer,
	// The player's body and arm (work item 0066, render_player_model.odin).
	player_model:       Player_Model,
	// Sound (work item 0068, audio.odin, sound_events.odin): the mixer
	// for the whole run, and what the sounds keep between frames, reset
	// with the session. Sounds play once a frame, heard at the first
	// viewport's player (0178).
	audio:              Audio_Mixer,
	sound_memory:       Sound_Memory,
}

// The diagnostics pages, the command socket and the developer screens.
Frame_Developer_Tools :: struct {
	// F3 and the Developer screen (diagnostics.odin, work item 0086).
	diagnostics_page:   Diagnostics_Page,
	// The world statistics overlay (draw_world_overlay), off by default.
	show_world_overlay: bool,
	// The command socket (work item 0053): open while developer mode is
	// on, served between ticks (serve_command_socket). The paths are
	// owned, empty when the environment names no directory.
	command_server:       Command_Server,
	command_control:      Command_Control,
	command_socket_path:  string,
	screenshot_directory: string,
	// The texture editor's entries (work item 0100, ui_texture_editor.odin),
	// read at start and served by serve_texture_editor.
	texture_editor:       Texture_Editor,
	// The Data files screen's tree and open file (work item 0129,
	// ui_data_browser.odin), served by serve_data_browser.
	data_browser:         Data_Browser,
}

// Hot reload's own state (work item 0054, hot_reload.odin). content and
// base_generator live in content_arena, which a content reload frees.
Frame_Reload :: struct {
	content_arena:        ^virtual.Arena,
	data_watch:           Data_Watch,
	watch_data_flag:      Watch_Data_Mode,
	binding_overrides:    []Binding,
	// The bindings of the last bindings reload; nil for those main read.
	bindings_arena:       ^virtual.Arena,
	// String entries a strings reload replaced, freed at exit.
	retired_strings:      [dynamic]map[string]string,
	// The font arenas a fonts reload replaced, freed at exit.
	retired_font_arenas:  [dynamic]^virtual.Arena,
}

// Above the middle of the debug terrain, looking down at an angle. The
// player starts here in fly mode on the debug terrain.
INITIAL_FLY_CAMERA :: Fly_Camera {
	position = {-40, 80, -40},
	yaw      = 45,
	pitch    = -30,
}

// With the session's generator, for the orbital survey. Built once by
// update_frame, once by render_frame, once by make_screen_context
// inside the UI pass and once per queued command: a reload command
// between them replaces the content arena and the
// session's technologies, and a texture edit the data browser saves
// between update and render (serve_data_browser) replaces the item
// registry's icon_loaded, so a copy never outlives its phase.
frame_simulation_content :: proc(state: ^Frame_State) -> Simulation_Content {
	content := session_simulation_content(state.content, state.session.technologies, state.session.field_content)
	content.generator = &state.session.generator
	return content
}

make_tick_accumulator :: proc(tick_rate: int) -> Tick_Accumulator {
	return Tick_Accumulator{seconds_per_tick = 1.0 / f64(tick_rate)}
}

// Returns the accumulator after consuming whole ticks and the number of ticks to run.
advance_tick_accumulator :: proc(accumulator: Tick_Accumulator, frame_seconds: f64) -> (Tick_Accumulator, int) {
	result := accumulator
	result.accumulated_seconds += min(frame_seconds, MAXIMUM_FRAME_SECONDS)
	tick_count := int(result.accumulated_seconds / result.seconds_per_tick)
	result.accumulated_seconds -= f64(tick_count) * result.seconds_per_tick
	return result, tick_count
}

// While a pausing screen is open the accumulator stays frozen, so the
// frame time of the paused period never turns into catch up ticks.
advance_simulation_clock :: proc(accumulator: Tick_Accumulator, frame_seconds: f64, paused: bool) -> (Tick_Accumulator, int) {
	if paused {
		return accumulator, 0
	}
	return advance_tick_accumulator(accumulator, frame_seconds)
}

// Fraction of the next tick already elapsed, for camera interpolation.
interpolation_alpha :: proc(accumulator: Tick_Accumulator) -> f64 {
	return accumulator.accumulated_seconds / accumulator.seconds_per_tick
}

// Built at each use, so the overlay reads the fields as they are at that
// point of the frame (the render camera and tick count are the last
// frame's while the input is read). The overlay drives the first viewport,
// and only while it is the one (a phone is one player).
touch_overlay_context :: proc(state: ^Frame_State) -> Touch_Overlay_Context {
	viewport := &state.viewports[0]
	return Touch_Overlay_Context {
		interaction = &state.interaction,
		ui = &viewport.interaction.ui,
		session = state.session,
		content = &state.content,
		settings = &state.settings,
		render_camera = viewport.presentation.camera,
		frame_seconds = state.frame_seconds,
		frame_tick_count = state.frame_tick_count,
		local_player = state.session != nil ? session_local_player_index(state.session) : 0,
	}
}

// The touch overlay is on and drives the first viewport, the only one.
frame_touch_overlay_on :: proc(state: ^Frame_State) -> bool {
	return state.viewport_count == 1 && touch_overlay_on(touch_overlay_context(state))
}

// The viewport's device: the first reads the keyboard, the mouse and the
// touch overlay besides its pad.
read_input_frame :: proc(state: ^Frame_State, index: int, frame_seconds: f32) -> Input_Frame {
	viewport := &state.viewports[index]
	overlay: Touch_Overlay_Frame
	if index == 0 && state.viewport_count == 1 {
		overlay = read_touch_overlay_frame(touch_overlay_context(state))
	}
	frame: Input_Frame
	previous := viewport.interaction.input
	switch state.interaction.input_backend {
	case .Sdl3:
		frame = read_sdl3_input_frame(&state.interaction.sdl3_input, viewport.gamepad, viewport.keyboard_mouse, previous, frame_seconds, state.settings, state.interaction.input_bindings, overlay)
	case .Raylib:
		frame = read_raylib_input_frame(previous.pressed, state.interaction.input_bindings, overlay)
	}
	frame = apply_touch_overlay_jump(apply_touch_overlay_hotbar(apply_touch_overlay_aim(frame, overlay), overlay), overlay)
	// The mouse in the first viewport's own pixels.
	if state.viewport_count > 1 && viewport.keyboard_mouse {
		frame.raw.mouse.position -= [2]f32{f32(viewport.rectangle.x), f32(viewport.rectangle.y)}
	}
	return frame
}

// Lost pads leave their viewports waiting; a pad no viewport reads may
// take one or join (pad_claim). Only the SDL3 backend tells pads apart;
// the raylib backend's pad is the first viewport's.
update_viewport_pads :: proc(state: ^Frame_State) {
	if state.interaction.input_backend != .Sdl3 {
		return
	}
	sdl3 := &state.interaction.sdl3_input
	for gamepad in poll_sdl3_events(sdl3) {
		lose_viewport_pad(active_viewports(state), gamepad)
	}
	for gamepad in sdl3_pad_ids(sdl3) {
		if pad_owned(active_viewports(state), gamepad) {
			continue
		}
		pressed, just_pressed := sdl3_unowned_pad_presses(sdl3, gamepad, state.interaction.input_bindings)
		claim, index := pad_claim(active_viewports(state), just_pressed, state.session != nil)
		switch claim {
		case .None:
		case .Take:
			state.viewports[index].gamepad, state.viewports[index].pad_lost = gamepad, false
			state.viewports[index].interaction.input.pressed = pressed
		case .Add:
			add_viewport(state, gamepad, pressed)
		}
	}
}

// The mouse steers the view while the world is shown and is free for the
// diagnostics screen and the menus. With the touch overlay on it stays
// free, since on the desktop the mouse is the overlay's touch point.
apply_cursor_mode :: proc(state: ^Frame_State) {
	wanted := state.developer.diagnostics_page != .Off || primary_ui(state).screens.count > 0 || frame_touch_overlay_on(state)
	if wanted == state.interaction.cursor_enabled {
		return
	}
	state.interaction.cursor_enabled = wanted
	if wanted {
		rl.EnableCursor()
	} else {
		rl.DisableCursor()
	}
}

toggle_on_press :: proc(value: bool, just_pressed: Action_Set, action: Action) -> bool {
	return action in just_pressed ? !value : value
}

// The diagnostics switches from any viewport, the debug edits for the
// viewport's player.
apply_debug_actions :: proc(state: ^Frame_State, viewport: ^Viewport) {
	just_pressed := viewport.interaction.input.just_pressed
	if .Toggle_Diagnostics in just_pressed {
		state.developer.diagnostics_page = next_diagnostics_page(state.developer.diagnostics_page)
	}
	state.developer.show_world_overlay = toggle_on_press(state.developer.show_world_overlay, just_pressed, .Toggle_World_Overlay)
	session := state.session
	if !viewport_player_ready(session, viewport^) {
		return
	}
	if .Debug_Remove_Block in just_pressed {
		session.debug_edit_counter += 1
		queue_player_command(&session.simulation.player_commands, viewport.player, Debug_Remove_Block_Command{counter = session.debug_edit_counter})
	}
	if .Debug_Drop_Item in just_pressed {
		queue_player_command(&session.simulation.player_commands, viewport.player, Debug_Drop_Item_Command{})
	}
}

// The viewport's world is blocked by its screens.
viewport_world_blocked :: proc(viewport: Viewport) -> bool {
	return ui_blocks_world(viewport.interaction.ui.screens)
}

// The UI runs in render_frame, so the screen stack read here is the one the
// previous frame left: a screen opened or closed takes effect on the world
// one frame later. The ticks run once however many viewports there are.
update_frame :: proc(state: ^Frame_State) {
	state.frame_seconds = rl.GetFrameTime()
	state.frame_times = push_frame_time(state.frame_times, state.frame_seconds)
	update_viewport_pads(state)
	for index in 0 ..< state.viewport_count {
		viewport := &state.viewports[index]
		viewport.interaction.previous_input = viewport.interaction.input
		viewport.interaction.input = read_input_frame(state, index, state.frame_seconds)
	}
	update_frame_world(state)
	for viewport in active_viewports(state) {
		if .Reload_Data in viewport.interaction.input.just_pressed && developer_mode_on(state) {
			state.requests += {.Reload_Data}
		}
	}
	if state.session == nil && join_active(state.joining) {
		update_joining(state)
	}
	serve_command_socket(state)
	for viewport, index in active_viewports(state) {
		switch state.interaction.input_backend {
		case .Sdl3:
			apply_sdl3_haptics(&state.interaction.sdl3_input, viewport.gamepad, viewport.interaction.haptic)
		case .Raylib:
			if index == 0 {
				apply_vibrator_haptics(&state.interaction.vibrator, viewport.interaction.haptic)
			}
		}
	}
}

// The frame's input into the session, once for every viewport: the guards,
// the debug actions, the ticks and each player's rumble.
update_frame_world :: proc(state: ^Frame_State) {
	for &viewport in active_viewports(state) {
		viewport.interaction.world_action_guard = update_world_action_guard(viewport.interaction.world_action_guard, viewport_world_blocked(viewport), viewport.interaction.input.pressed)
		viewport.interaction.haptic = {}
	}
	if state.session == nil {
		return
	}
	assign_waiting_players(state)
	for &viewport in active_viewports(state) {
		apply_debug_actions(state, &viewport)
		apply_overlay_toggle(state, viewport)
	}
	update_session(state, frame_simulation_content(state))
	for &viewport in active_viewports(state) {
		if viewport_player_ready(state.session, viewport) {
			viewport.interaction.haptic = haptic_request_for(state.session.simulation.players[viewport.player], !viewport_world_blocked(viewport))
		}
	}
}

// Only while no screen is open, so O typed into a text field or pressed
// in a menu does nothing. The setting is written like any other changed
// setting.
apply_overlay_toggle :: proc(state: ^Frame_State, viewport: Viewport) {
	if .Toggle_Bottleneck_Overlay in viewport.interaction.input.just_pressed && !viewport_world_blocked(viewport) {
		state.settings.bottleneck_overlay = !state.settings.bottleneck_overlay
	}
}

// The viewport's frame input as the world takes it.
viewport_world_input :: proc(state: ^Frame_State, viewport: Viewport) -> Input_Frame {
	frame := world_input(viewport.interaction.input, viewport_world_blocked(viewport), viewport.interaction.world_action_guard, state.settings, developer_mode_on(state))
	// The right stick drives an open hotbar radial instead of the camera.
	if viewport.interaction.ui.radial.open {
		frame = without_actions(frame, {.Look})
	}
	return frame
}

// One record per viewport whose player is a local member, each from its
// own accumulated input. False when none could be stamped (every local
// player is its window ahead).
stamp_viewport_records :: proc(state: ^Frame_State, worlds: []Input_Frame) -> bool {
	session := state.session
	stamped := false
	for &viewport, index in active_viewports(state) {
		local := viewport.player == NO_PLAYER ? -1 : find_local_member(session.lockstep, viewport.player)
		if local < 0 {
			continue
		}
		tick_input, next := take_tick_input(viewport.tick_input, worlds[index])
		remainder := viewport.field_turn_remainder
		if session.simulation.field.enabled {
			tick_input, remainder = carry_field_turn(tick_input, remainder, session.simulation.tick_rate)
		}
		if stamp_local_record(&session.lockstep, session.simulation.tick, tick_input, local) {
			viewport.tick_input = next
			viewport.field_turn_remainder = remainder
			stamped = true
		}
	}
	return stamped
}

// A pause command holds the ticks like a pausing screen, and a tick
// command replaces the frame's ticks with its own (run_command_ticks),
// both only without other machines. The frame's ticks go through the
// lockstep driver (lockstep.odin): each viewport stamps a local input
// record for its player, the records go out and come back
// (session_network.odin), and every tick whose records are there runs,
// once for the frame however many viewports feed it.
update_session :: proc(state: ^Frame_State, content: Simulation_Content) {
	session := state.session
	lockstep, simulation := &session.lockstep, &session.simulation
	// A host no machine joined yet plays as single player.
	offline := session_alone(session.network)
	// Only the first viewport's pausing screen holds the world: a guest's
	// pause menu and settings run with the world going on, as online.
	holding := offline && (ui_pauses_simulation(state.viewports[0].interaction.ui.screens) || state.developer.command_control.paused)
	fast := offline && state.developer.command_control.pending_ticks > 0
	worlds: [MAXIMUM_VIEWPORTS]Input_Frame
	for &viewport, index in active_viewports(state) {
		worlds[index] = viewport_world_input(state, viewport)
		viewport.tick_input = holding ? paused_frame_input(viewport.tick_input, worlds[index]) : accumulate_frame_input(viewport.tick_input, worlds[index])
	}
	tick_count: int
	session.accumulator, tick_count = advance_simulation_clock(session.accumulator, f64(state.frame_seconds), holding || fast)
	lockstep.clock_ticks = min(lockstep.clock_ticks + tick_count, simulation.tick_rate)
	hold_local_commands(lockstep, simulation)
	answers := make([dynamic]Line_Answer, context.temp_allocator)
	if holding {
		run_held_lines(session, content, &state.developer.command_control, &answers)
	}
	ran := 0
	for _ in 0 ..< tick_count {
		if !stamp_viewport_records(state, worlds[:state.viewport_count]) {
			break
		}
		if offline {
			deliver_records_alone(session)
			ran += run_ready_ticks(session, content, &state.developer.command_control, &answers)
		}
	}
	exchange_session_records(session, content)
	ran += run_ready_ticks(session, content, &state.developer.command_control, &answers)
	send_line_answers(state, answers[:])
	// A machine that joined during the exchange runs from the join tick
	// on, so the tick command's ticks without records stop here.
	if fast && session_alone(session.network) {
		ran += run_command_ticks(state, content)
	}
	rebuild_prediction(lockstep, simulation, content)
	session.stalled_frames = stalled_frames_after(session.stalled_frames, ran, session.chunk_stalled)
	state.frame_tick_count = ran
	session.ticks_since_save += u64(ran)
	save_when_due(state)
	show_network_notices(state)
	own := session_local_player_index(session)
	stream_session_chunks(session, world_to_chunk_coordinate(camera_world_coordinate(lockstep_view_player(lockstep, simulation, own).position)), frame_field_selection(state))
}

// Alone the local records come straight back; a host relays them, which
// keeps its frontier (the next join's tick) true.
deliver_records_alone :: proc(session: ^Session) {
	if session.network.role != .Host {
		deliver_outgoing_locally(&session.lockstep, session.simulation.tick)
		return
	}
	for record in session.lockstep.outgoing {
		relay_record(session, record)
	}
	clear(&session.lockstep.outgoing)
}

// The local player's records out and everyone's in: offline straight
// back, a host relays, a client sends to the host.
exchange_session_records :: proc(session: ^Session, content: Simulation_Content) {
	switch session.network.role {
	case .Offline:
		deliver_outgoing_locally(&session.lockstep, session.simulation.tick)
	case .Host:
		update_host_network(session, content, session.save.location.display_name)
	case .Client:
		update_client_network(&session.network, &session.lockstep, session.simulation.tick, content)
	}
}

// The frames in a row the tick waited for its chunks.
stalled_frames_after :: proc(stalled_frames, ran: int, chunk_stalled: bool) -> int {
	if ran > 0 || !chunk_stalled {
		return 0
	}
	return stalled_frames + 1
}

// A tick waiting this many frames for its chunks shows the loading notice.
LOADING_NOTICE_FRAMES :: 10

// Before the frame shows a joined world: the connection, the ping, the
// join, the session from the snapshot (start_joined_session), then its
// catching up (catch_up_joined_session) until the local player's entry
// exists and no record is left to run. Only then does the session
// become the frame's, so no frame reads a player the world does not have
// yet. A host that leaves first, or a world that does not load, leaves
// the title showing with a toast.
update_joining :: proc(state: ^Frame_State) {
	join := &state.joining
	status, problem := advance_session_join(join, state.config, state.content, state.base_generator, &state.developer.command_control)
	toast_network_notices(primary_ui(state), join.session != nil ? &join.session.network : &join.network)
	switch status {
	case .Waiting:
	case .Failed:
		report_session_problem(state, problem != "" ? problem : text("join_failed"))
		destroy_session_join(join)
	case .Ready:
		session := join.session
		join.session = nil
		destroy_session_network(&join.network)
		enter_session(state, session)
	}
}

Join_Status :: enum u8 {
	Waiting,
	Ready,
	Failed,
}

// One frame of a join: the network until the snapshot, then the joined
// world catching up. Ready once joined_session_ready holds; the caller
// then takes join.session. Failed with the problem ("" for a lost host,
// whose notice says why); the caller destroys the join.
advance_session_join :: proc(join: ^Session_Join, config: Game_Config, content: Game_Content, base_generator: Generator, control: ^Command_Control) -> (status: Join_Status, problem: string) {
	if join.session == nil {
		update_client_network(&join.network, nil, 0, content.simulation_content)
		switch {
		case join.network.snapshot != nil:
			join.session, problem = start_joined_session(&join.network, config, content, base_generator)
			if problem != "" {
				return .Failed, problem
			}
		case join.network.host_lost:
			return .Failed, ""
		}
		return .Waiting, ""
	}
	session := join.session
	catch_up_joined_session(session, content, control)
	switch {
	case session.network.host_lost:
		return .Failed, ""
	case joined_session_ready(session):
		return .Ready, ""
	}
	return .Waiting, ""
}

// The joined world's ticks while the title still shows: the local
// player's records stamped empty up to its window, the records in and
// out, every ready tick, its chunks.
catch_up_joined_session :: proc(session: ^Session, game_content: Game_Content, control: ^Command_Control) {
	content := session_simulation_content(game_content, session.technologies, session.field_content)
	content.generator = &session.generator
	for local in 0 ..< len(session.lockstep.locals) {
		for stamp_local_record(&session.lockstep, session.simulation.tick, Input_Frame{}, local) {
		}
	}
	exchange_session_records(session, content)
	answers := make([dynamic]Line_Answer, context.temp_allocator)
	run_ready_ticks(session, content, control, &answers)
	stream_session_chunks(session, player_chunk(session.simulation.players[0]), nil)
}

// The local player's entry exists and the records that were there ran.
joined_session_ready :: proc(session: ^Session) -> bool {
	return lockstep_local_player(session.lockstep) < len(session.simulation.players) && !session.chunk_stalled && !lockstep_records_ready(session.lockstep, session.simulation.tick)
}

// The network's notices as toasts.
toast_network_notices :: proc(ui: ^Ui_State, network: ^Session_Network) {
	for notice in network.notices {
		ui_toast(ui, notice)
		delete(notice)
	}
	clear(&network.notices)
}

// The network's notices as toasts; a client whose host left goes back
// to the title.
show_network_notices :: proc(state: ^Frame_State) {
	network := &state.session.network
	toast_network_notices(primary_ui(state), network)
	if network.host_lost && state.interaction.title.request.kind == .None {
		state.interaction.title.request.kind = .Quit_To_Title
	}
}

// What the frame says while no tick can run: a join in progress, or a
// tick waiting for its chunks a while. "" when the world plays.
loading_notice :: proc(state: ^Frame_State) -> string {
	switch {
	case state.session == nil && state.joining.session != nil:
		return text("loading_joined_world")
	case state.session == nil && join_active(state.joining):
		return text("loading_joining")
	case state.session != nil && state.session.stalled_frames >= LOADING_NOTICE_FRAMES:
		return text("loading_world")
	}
	return ""
}

// The session's own local player: the first viewport's, the one the
// command socket and the diagnostics follow. The server has none, and
// nothing on the frame side runs there.
session_local_player_index :: proc(session: ^Session) -> int {
	return max(lockstep_local_player(session.lockstep), 0)
}

session_local_player :: proc(session: ^Session) -> ^Player {
	return &session.simulation.players[session_local_player_index(session)]
}

// The simulated chunk set's chunks to the workers, the generated ones back
// as chunk ready commands for the next tick, the tick's unloads to the
// renderer; in a field session the field's set and the viewports' nodes
// (stream_field_session).
stream_session_chunks :: proc(session: ^Session, camera_chunk: Chunk_Coordinate, field_selection: []Field_Node) {
	simulation := &session.simulation
	if simulation.field.enabled {
		stream_field_session(session, field_selection)
	}
	frame := Chunk_Stream_Frame {
		requested    = simulated_chunk_requests(simulation),
		held         = held_chunk_arrivals(simulation),
		unloaded     = simulation.unloaded_chunks[:],
		camera_chunk = camera_chunk,
	}
	arrivals := make([dynamic]Chunk_Job_Result, context.temp_allocator)
	update_chunk_streaming(&session.streaming, &simulation.world, frame, &arrivals)
	clear(&simulation.unloaded_chunks)
	for result in arrivals {
		queue_player_command(&simulation.player_commands, NO_PLAYER, Chunk_Ready_Command{result = result})
	}
}

autosave_due :: proc(ticks_since_save: u64, autosave_minutes, tick_rate: int) -> bool {
	return autosave_minutes > 0 && ticks_since_save >= u64(autosave_minutes) * 60 * u64(tick_rate)
}

// The pause menu's Save and the autosave interval, each with a toast.
save_when_due :: proc(state: ^Frame_State) {
	session := state.session
	requested := session.save_requested
	session.save_requested = false
	autosave := session.save.enabled && autosave_due(session.ticks_since_save, state.settings.autosave_minutes, session.simulation.tick_rate)
	if !requested && !autosave {
		return
	}
	if save_session(session, state.content) != "" {
		ui_toast(primary_ui(state), text("save_failed"))
	} else {
		ui_toast(primary_ui(state), text(requested ? "save_done" : "autosave_done"))
	}
}

// The 2D passes (the underwater overlay, the diagnostics pages, the UI)
// draw in render pixels (work item 0085). raylib 6.0 multiplies its DPI
// scale into the modelview in BeginDrawing and after EndMode3D, which
// would upscale them a second time under a scaled Wayland desktop; this
// flushes what is batched under that matrix and resets it. The identity at
// scale 1.
begin_render_pixel_drawing :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.LoadIdentity()
}

// One viewport, single player straight to the window: the cues of the
// viewport's player, its world, the underwater tint. Nothing before the
// player's entry exists (a local player whose join tick has not run).
draw_viewport_world :: proc(state: ^Frame_State, viewport: ^Viewport, content: Simulation_Content, sky: Day_Sky, weather: Weather) -> (counts: Frame_Render_Counts, cues: Frame_Cues) {
	session := state.session
	if !viewport_player_ready(session, viewport^) {
		begin_render_pixel_drawing()
		return
	}
	if session.simulation.field.enabled {
		draw_field_viewport_world(state, viewport, content, sky)
		begin_render_pixel_drawing()
		return
	}
	memory := &viewport.presentation.cue_memory
	cues, memory^ = detect_cues(memory^, observe_cue_counters(memory^, &session.simulation, viewport.player))
	counts = draw_session_world(state, viewport, content, sky, weather, &cues)
	begin_render_pixel_drawing()
	if counts.underwater {
		draw_underwater_overlay()
	}
	return counts, cues
}

// Split screen (0178): each viewport's world and UI into its render
// texture at its size, so every 3D pass (the world, the hands) and the
// UI's layout take the viewport's size as raylib's current framebuffer.
// Returns the first viewport's counts and cues.
draw_split_viewports :: proc(state: ^Frame_State, content: Simulation_Content, sky: Day_Sky, weather: Weather) -> (counts: Frame_Render_Counts, cues: Frame_Cues) {
	for index in 0 ..< state.viewport_count {
		viewport := &state.viewports[index]
		prepare_viewport_target(&viewport.presentation, viewport.rectangle)
		rl.BeginTextureMode(viewport.presentation.target)
		rl.ClearBackground(sky.colors.horizon)
		viewport_counts, viewport_cues := draw_viewport_world(state, viewport, content, sky, weather)
		if index == 0 {
			counts, cues = viewport_counts, viewport_cues
		}
		run_viewport_ui(state, index)
		rl.EndTextureMode()
	}
	return counts, cues
}

render_frame :: proc(state: ^Frame_State) {
	// The selection lives in the frame's temp memory.
	defer state.presentation.field_selection = nil
	place_viewports(state, render_size())
	if state.session == nil {
		rl.BeginDrawing()
		defer rl.EndDrawing()
		rl.ClearBackground(DAY_SKY_COLOR)
		begin_render_pixel_drawing()
		run_ui_frame(state)
		capture_pending_screenshot(state)
		return
	}
	session := state.session
	// Every mesh result taken lowers the pending jobs by one.
	pending_before_upload := session.streaming.pending_jobs
	upload_streamed_meshes(&state.presentation.renderer, &session.streaming)
	weather := session_weather(session, state.settings.weather)
	sky := weathered_day_sky(day_sky(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks), weather)
	apply_daylight(&state.presentation.renderer, sky)
	field := session.simulation.field.enabled
	if field {
		prepare_field_frame(state)
	}
	content := frame_simulation_content(state)
	split := state.viewport_count > 1
	counts: Frame_Render_Counts
	cues: Frame_Cues
	if split {
		counts, cues = draw_split_viewports(state, content, sky, weather)
	}
	rl.BeginDrawing()
	defer rl.EndDrawing()
	if split {
		rl.ClearBackground(rl.BLACK)
		begin_render_pixel_drawing()
		// Blending off: the targets cover the window, and a target's alpha
		// below 1 under its translucent draws (water, particles, backdrops)
		// would darken those parts against the black.
		rlgl.SetBlendFactors(rlgl.ONE, rlgl.ZERO, rlgl.FUNC_ADD)
		rl.BeginBlendMode(.CUSTOM)
		for viewport in active_viewports(state) {
			draw_viewport_target(viewport)
		}
		rl.EndBlendMode()
	} else {
		// The horizon colour, which is the fog colour: the dome covers the
		// upper hemisphere alone, so the clear colour shows below the horizon.
		rl.ClearBackground(sky.colors.horizon)
		release_viewport_target(&state.viewports[0].presentation)
		counts, cues = draw_viewport_world(state, &state.viewports[0], content, sky, weather)
	}
	counts.uploaded_meshes = pending_before_upload - session.streaming.pending_jobs
	// The sounds read the block world; a field session has none yet.
	if viewport_player_ready(session, state.viewports[0]) && !field {
		play_frame_sounds(&state.presentation.audio, &state.presentation.sound_memory, session_sound_frame(state, content, weather, cues))
	}
	switch state.developer.diagnostics_page {
	case .Off:
		if state.developer.show_world_overlay {
			draw_world_overlay(diagnostics_context(state))
		}
	case .Input:
		draw_diagnostics_page(diagnostics_context(state), state.config, {}, {})
	case .Render:
		draw_diagnostics_page(diagnostics_context(state), state.config, render_facts(state, sky, weather, counts), {})
	case .World:
		diagnostics := diagnostics_context(state)
		draw_diagnostics_page(diagnostics, state.config, {}, world_facts(state, diagnostics))
	}
	if split {
		finish_ui_frame(state)
	} else {
		run_ui_frame(state)
	}
	for index in 0 ..< state.viewport_count {
		queue_requested_screenshot(state, index)
	}
	capture_pending_screenshot(state)
}

// Sounds play once a frame, heard at the first viewport's player, with
// its cues: the world's cues (a launch, a shipment) fire alike in every
// viewport, and the other players' steps and digs stay quiet in split
// screen.
session_sound_frame :: proc(state: ^Frame_State, content: Simulation_Content, weather: Weather, cues: Frame_Cues) -> Sound_Frame {
	session := state.session
	return Sound_Frame {
		world = &session.simulation.world,
		content = content,
		generator = &session.generator,
		player = session.simulation.players[state.viewports[0].player],
		tick = session.simulation.tick,
		cues = cues,
		weather = weather,
		cheat_speed = session.simulation.cheat_speed,
		daylight = daylight_blend(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks),
	}
}

// The weather of the frame: the schedule, or the weather command's kind;
// always clear with the weather setting off (work item 0063).
session_weather :: proc(session: ^Session, enabled: bool) -> Weather {
	if !enabled {
		return {}
	}
	simulation := &session.simulation
	scheduled := weather_at(simulation.world.settings.seed, simulation_day_ticks(simulation^), simulation.day_length_ticks)
	return forced_weather(scheduled, session.weather_override)
}

// Rain, or snow over a cold column, as much as the sky is open at the
// camera. The light is the sky light of the frame. Returns the particles
// drawn.
draw_session_weather :: proc(session: ^Session, camera: rl.Camera3D, weather: Weather, sky: Day_Sky, seconds: f64) -> int {
	cell := camera_world_coordinate(camera.position)
	seeds := session.generator.seeds
	temperature := terrain_temperature(seeds, cell.x, cell.z, terrain_height(seeds, cell.x, cell.z))
	open_sky := f32(light_level(world_get_light(&session.simulation.world, cell), .Sky)) / MAXIMUM_LIGHT
	light := color_to_vector3(sky.colors.sun_tint) * day_factor(sky.blend)
	precipitation := weather_precipitation(weather, temperature)
	count := weather_particle_count(weather.intensity, open_sky)
	draw_weather(camera, precipitation, count, seconds, light)
	return precipitation == .None ? 0 : max(count, 0)
}

// Ambient life's view of the frame (render_life.odin): the tick in
// seconds for the flocks' loops, the render time for the rest.
session_life_frame :: proc(session: ^Session, camera: rl.Camera3D, sky: Day_Sky, weather: Weather, look: Weather_Look, alpha: f32, seconds: f64) -> Life_Frame {
	simulation := &session.simulation
	fog_start, fog_end := weather_fog_distances(LOAD_RADIUS_HORIZONTAL, look.fog_scale)
	return Life_Frame {
		camera = camera,
		seed = simulation.world.settings.seed,
		loop_seconds = (f64(simulation.tick) + f64(alpha)) / f64(simulation.tick_rate),
		seconds = seconds,
		presence = life_presence(sky.blend, weather.kind == .Rain ? weather.intensity : 0),
		light = day_factor(sky.blend),
		fog_start = fog_start,
		fog_end = fog_end,
	}
}

// What the frame drew besides the renderer's own counts: whether the
// camera is under water, for the tint drawn after the 3D pass (work item
// 0065), and the counts of the Render page (work item 0086). The water
// meshes are counted on the Render page only.
Frame_Render_Counts :: struct {
	underwater:        bool,
	uploaded_meshes:   int,
	water_meshes:      int,
	weather_particles: int,
}

// The Render page's facts (diagnostics.odin). The fog is the underwater
// fog while the camera is under water.
render_facts :: proc(state: ^Frame_State, sky: Day_Sky, weather: Weather, counts: Frame_Render_Counts) -> Render_Facts {
	session := state.session
	fog_start, fog_end := weather_fog_distances(LOAD_RADIUS_HORIZONTAL, weather_look(weather, weather_motion_enabled(state.settings), sky.blend).fog_scale)
	if counts.underwater {
		fog := underwater_fog()
		fog_start, fog_end = fog.start, fog.end
	}
	return Render_Facts {
		build_stamp = BUILD_STAMP,
		window_mode = state.presentation.window_settings.window_mode,
		monitor_size = state.presentation.monitor_size,
		window_size = {int(rl.GetScreenWidth()), int(rl.GetScreenHeight())},
		render_size = {int(rl.GetRenderWidth()), int(rl.GetRenderHeight())},
		window_scale = state.presentation.window_scale,
		platform = state.presentation.platform,
		vsync = state.settings.vsync,
		frame_rate_cap = state.settings.frame_rate_cap,
		frames_per_second = int(rl.GetFPS()),
		frame_milliseconds = average_frame_milliseconds(state.frame_times),
		tick_count = state.frame_tick_count,
		accumulated_seconds = session.accumulator.accumulated_seconds,
		fog_start = fog_start,
		fog_end = fog_end,
		weather = weather,
		day_fraction = sky.fraction,
		loaded_chunk_count = len(session.simulation.world.chunks),
		drawn_chunk_count = state.presentation.renderer.drawn_chunk_count,
		vertex_count = state.presentation.renderer.vertex_count,
		uploaded_mesh_count = counts.uploaded_meshes,
		pending_job_count = session.streaming.pending_jobs,
		drawn_water_mesh_count = counts.water_meshes,
		live_particle_count = live_particle_count(&state.viewports[0].presentation.particles),
		weather_particle_count = counts.weather_particles,
		flame_count = flame_count(state.presentation.renderer),
		block_atlas_size = texture_size(chunk_atlas_texture(state.presentation.renderer)),
		item_atlas_size = texture_size(state.presentation.item_atlas.texture),
		ui_atlas_size = texture_size(state.presentation.ui_icon_atlas.texture),
		underwater = counts.underwater,
	}
}

// What the diagnostics pages and the F4 overlay read (diagnostics.odin).
diagnostics_context :: proc(state: ^Frame_State) -> Diagnostics_Context {
	session := state.session
	return Diagnostics_Context {
		simulation = &session.simulation,
		player = session_local_player_index(session),
		technologies = session.technologies,
		blocks = state.content.blocks,
		items = state.content.items,
		quests = state.content.quests,
		input = state.viewports[0].interaction.input,
		fonts = primary_ui(state).fonts,
		page = state.developer.diagnostics_page,
		bottleneck_overlay = state.settings.bottleneck_overlay,
		pending_job_count = session.streaming.pending_jobs,
		seed = session.generator.seed,
		tick_interpolation = interpolation_alpha(session.accumulator),
		drawn_chunk_count = state.presentation.renderer.drawn_chunk_count,
		vertex_count = state.presentation.renderer.vertex_count,
	}
}

// The World page's facts (diagnostics.odin).
world_facts :: proc(state: ^Frame_State, diagnostics: Diagnostics_Context) -> World_Facts {
	session := state.session
	world := &session.simulation.world
	cell := camera_world_coordinate(session_local_player(session).position)
	biome := sample_column(&session.generator, cell.x, cell.z).biome
	biome_name := biome < len(session.generator.biomes) ? text(session.generator.biomes[biome].definition.name_key) : "?"
	return World_Facts {
		overlay_lines = world_overlay_statistics_lines(diagnostics),
		tick = session.simulation.tick,
		player_chunk = world_to_chunk_coordinate(cell),
		biome_name = biome_name,
		entity_counts = entity_counts(&world.entities),
		loose_item_count = len(world.entities.loose_items.items),
		belt_line_count = len(world.entities.belt_network.lines),
		belt_item_count = belt_item_count(world.entities.belt_network),
		leaf_decay_count = len(session.simulation.records.leaf_decay.updates),
	}
}

// The viewport's camera: its player's view (the prediction while the
// lockstep window runs ahead), the head bob of its animation and its
// sprint kick, which advances here.
viewport_camera :: proc(state: ^Frame_State, viewport: ^Viewport, content: Simulation_Content, player: Player, animation: Player_Animation_State, alpha: f32) -> (rl.Camera3D, Fly_Camera) {
	world := &state.session.simulation.world
	presentation := &viewport.presentation
	bob := head_bob_offset(animation.walk_phase, head_bob_amplitude(animation.moving, animation.sprinting, head_bob_enabled(state.settings)))
	view := player_view_camera(world, content.blocks, player, alpha, bob, state.settings)
	presentation.sprint_kick = advance_sprint_kick(presentation.sprint_kick, animation.moving && player_sprints(player, viewport.interaction.input.pressed), state.frame_seconds)
	camera := fly_camera_to_raylib(view, sprint_field_of_view(state.settings.field_of_view, sprint_kick_degrees(state.settings), presentation.sprint_kick))
	presentation.camera = camera
	return camera, view
}

// The particles add the Landing cue to the frame's cues. Drawn with the
// viewport's camera into whatever target is current.
draw_session_world :: proc(state: ^Frame_State, viewport: ^Viewport, content: Simulation_Content, sky: Day_Sky, weather: Weather, cues: ^Frame_Cues) -> (counts: Frame_Render_Counts) {
	session := state.session
	world := &session.simulation.world
	tick_rate := session.simulation.tick_rate
	memory := &viewport.presentation
	// The predicted local player while the lockstep window runs ahead.
	player := lockstep_view_player(&session.lockstep, &session.simulation, viewport.player)
	alpha := f32(interpolation_alpha(session.accumulator))
	seconds := rl.GetTime()
	update_player_presence(&memory.player_animation, &memory.particles, memory.particle_memory, world, content.blocks, player, cues^, seconds)
	pose := interpolate_player_pose(player, alpha)
	animation := player_animation_state(memory.player_animation, player, pose.pitch, seconds)
	camera, view := viewport_camera(state, viewport, content, player, animation, alpha)
	still_seconds := flicker_seconds(seconds, state.settings.reduced_motion)
	look := weather_look(weather, weather_motion_enabled(state.settings), sky.blend)
	apply_weather(&state.presentation.renderer, look, still_seconds)
	counts.underwater = camera_underwater(world, content.blocks, camera.position)
	if counts.underwater {
		apply_fog(&state.presentation.renderer, underwater_fog())
	}
	rl.BeginMode3D(camera)
	draw_sky(&state.presentation.renderer.sky, camera, sky, memory.particle_memory.satellite)
	draw_chunks(&state.presentation.renderer, camera)
	frame := Model_Frame{world = world, tick = session.simulation.tick, alpha = alpha, tick_rate = tick_rate, day_factor = day_factor(sky.blend), sky_tint = color_to_vector3(sky.colors.sun_tint)}
	draw_entities(world, content.machines, state.presentation.model_renderer, content.items, frame)
	if state.settings.bottleneck_overlay {
		draw_machine_markers(world, content.machines, state.presentation.model_renderer, camera.position, bottleneck_marker_colors(ui_theme(&viewport.interaction.ui), state.settings.palette))
	}
	draw_fluid_entities(world, content.machines, state.presentation.model_renderer, content.fluids, frame)
	draw_power_entities(world, content.machines, state.presentation.model_renderer, frame)
	draw_belts(&state.presentation.belt_renderer, world, content.items, content.machines, state.presentation.model_renderer, frame, Item_Billboards{camera = camera, atlas = state.presentation.item_atlas})
	draw_loose_items(world, content.items, frame, Item_Billboards{camera = camera, atlas = state.presentation.item_atlas})
	draw_torch_flames(&state.presentation.renderer, camera, still_seconds)
	life := session_life_frame(session, camera, sky, weather, look, alpha, seconds)
	draw_fish_shadows(&state.presentation.renderer, life)
	draw_water_chunks(&state.presentation.renderer, camera, seconds)
	draw_bird_flocks(&session.generator, life)
	draw_insect_motes(&state.presentation.renderer, session.generator.biomes, life)
	if state.developer.diagnostics_page == .Render {
		counts.water_meshes = water_meshes_in_view(state.presentation.renderer, camera)
	}
	if update_particles(&memory.particles, &memory.particle_memory, world, cues^, content, state.presentation.model_renderer, session.simulation.players[:], tick_rate, state.frame_seconds) {
		cues.fired += {.Landing}
	}
	update_satellite_pass(&memory.particle_memory, cues^, state.frame_seconds)
	draw_particles(&state.presentation.particle_renderer, camera, &memory.particles, memory.particle_memory, world, state.presentation.model_renderer, color_to_vector3(sky.colors.sun_tint) * day_factor(sky.blend))
	if weather_motion_enabled(state.settings) {
		counts.weather_particles = draw_session_weather(session, camera, weather, sky, seconds)
	}
	body := Player_Body_Draw{renderer = state.presentation.model_renderer, model = state.presentation.player_model, animation = animation, light = player_body_light(frame, player_eye(pose.position))}
	draw_player_world_overlay(world, content, state.presentation.model_renderer, &state.presentation.belt_renderer, session.simulation.players[:], viewport.player, alpha, body)
	rl.EndMode3D()
	if player.camera_mode == .First_Person {
		draw_first_person_hands(view, body, Item_Billboards{camera = camera, atlas = state.presentation.item_atlas}, Held_Block_Tiles{texture = chunk_atlas_texture(state.presentation.renderer), layout = state.presentation.renderer.atlas_layout, blocks = content.blocks}, content.items, selected_hotbar_stack(player))
	}
	return counts
}

// The mined block's centre in the viewport's render pixels, through the
// camera its world was drawn with this frame (the HUD draws after the
// world).
mining_ring_centre :: proc(viewport: ^Viewport, mining: Mining_State) -> [2]f32 {
	if !mining.active {
		return {}
	}
	size := [2]int{viewport.rectangle.width, viewport.rectangle.height}
	return rl.GetWorldToScreenEx(block_centre(mining.block), viewport.presentation.camera, i32(size.x), i32(size.y))
}

// The context every screen of the viewport gets. Without a session, or
// before the viewport's player has its entry, the world fields stay empty;
// only the title screens and settings run then.
make_screen_context :: proc(state: ^Frame_State, index: int) -> Screen_Context {
	content := state.content
	viewport := &state.viewports[index]
	screen_context := Screen_Context {
		settings        = &state.settings,
		monitor_size    = state.presentation.monitor_size,
		platform        = state.presentation.platform,
		font_families   = state.interaction.fonts.families,
		bindings        = state.interaction.bindings,
		requests        = &viewport.requests,
		split_screen_guest = index > 0,
		waiting_for_player = state.session != nil && !viewport_player_ready(state.session, viewport^),
		title           = &state.interaction.title,
		planets         = content.planets,
		content         = content.simulation_content,
		notes           = content.notes,
		item_sort_ranks = content.item_sort_ranks,
		recipe_names    = content.recipe_names,
		recipe_order    = content.recipe_order,
		tick_rate       = state.config.tick_rate,
		developer       = make_developer_context(state),
		touch_layouts   = &state.interaction.touch_layouts,
		touch_layout_editor = &state.interaction.touch_layout_editor,
		default_touch_layout = content.touch_overlay,
	}
	session := state.session
	if !viewport_player_ready(session, viewport^) {
		return screen_context
	}
	screen_context.save_requested = &session.save_requested
	screen_context.player = &session.simulation.players[viewport.player]
	screen_context.player_index = viewport.player
	screen_context.world = &session.simulation.world
	screen_context.records = &session.simulation.records
	screen_context.tick = session.simulation.tick
	screen_context.tick_rate = session.simulation.tick_rate
	screen_context.content = content_with_found_schematics(frame_simulation_content(state), session.simulation.unlocks)
	screen_context.unlocks = &session.simulation.unlocks
	screen_context.quest_state = &session.simulation.quests
	screen_context.views = &viewport.interaction.session_views
	screen_context.player_commands = &session.simulation.player_commands
	screen_context.unconfirmed_commands = lockstep_unconfirmed_commands(&session.lockstep, viewport.player)
	screen_context.cheat_speed = session.simulation.cheat_speed
	screen_context.landing_pad = session.start.landing_pad
	screen_context.particle_memory = &viewport.presentation.particle_memory
	return screen_context
}

// What the Developer screen and the two editors read of the frame:
// the content's developer mode and chapter count, the diagnostics page
// and overlay switches, the data watch's change flag, and the editors.
make_developer_context :: proc(state: ^Frame_State) -> Developer_Context {
	return Developer_Context {
		enabled            = state.content.developer_mode,
		chapter_count      = len(state.content.developer_kits.kits),
		diagnostics_page   = &state.developer.diagnostics_page,
		show_world_overlay = &state.developer.show_world_overlay,
		data_changed       = state.session != nil && state.reload.data_watch.content_changed,
		texture_editor     = &state.developer.texture_editor,
		data_browser       = &state.developer.data_browser,
	}
}

// The HUD's derivations for the viewport; the zero value without its
// player. The biome under the player is sampled here, once per frame. The
// touch overlay's parts only in the first viewport, alone.
make_hud_context :: proc(state: ^Frame_State, index: int) -> Hud_Context {
	session := state.session
	viewport := &state.viewports[index]
	if !viewport_player_ready(session, viewport^) {
		return {}
	}
	player := &session.simulation.players[viewport.player]
	column := sample_column(&session.generator, i32(math.floor(player.position.x)), i32(math.floor(player.position.z)))
	hud := Hud_Context {
		mining_ring_centre = mining_ring_centre(viewport, player.mining),
		biome_banner       = &viewport.interaction.biome_banner,
		biome              = column.biome,
		biomes             = session.generator.biomes,
	}
	if index == 0 && frame_touch_overlay_on(state) {
		touch := touch_overlay_context(state)
		hud.touch_aims, hud.touch_hud_buttons, hud.discovery_card_clearance = touch_overlay_aims(touch), frame_hud_touch_buttons_shown(touch), discovery_card_clearance(touch)
	}
	return hud
}

// The viewport's notice: a join in progress or a tick waiting for its
// chunks (loading_notice), a lost pad, a local player whose entry the
// join tick has not made yet. "" while it plays.
viewport_notice :: proc(state: ^Frame_State, viewport: Viewport) -> string {
	switch {
	case loading_notice(state) != "":
		return loading_notice(state)
	case viewport_waits_for_pad(viewport, state.viewport_count):
		return text("viewport_pad_lost")
	case state.session != nil && !viewport_player_ready(state.session, viewport):
		return text("viewport_joining")
	}
	return ""
}

// The viewport's UI pass up to its draw list (headless: no draw call),
// sized to its rectangle in render pixels (work item 0085: with the high
// DPI flag the UI follows the panel's pixels and its text rasterises at
// their size).
build_viewport_ui :: proc(state: ^Frame_State, index: int) {
	viewport := &state.viewports[index]
	ui := &viewport.interaction.ui
	screen_pixels := [2]f32{f32(viewport.rectangle.width), f32(viewport.rectangle.height)}
	input := make_ui_input(viewport.interaction.previous_input, viewport.interaction.input)
	// The phone's pointer is its first touch (input_raylib.odin); with the
	// overlay on, the desktop's mouse stands in for a finger (0124).
	input.pointer_is_touch = index == 0 && (ODIN_PLATFORM_SUBTARGET == .Android || frame_touch_overlay_on(state))
	ui_scale := viewport_ui_scale(state.settings.ui_scale, viewport.rectangle, state.viewport_count)
	ui_begin(ui, input, screen_pixels, state.frame_seconds, ui_scale, state.settings.pointer_speed, ui_accessibility(state.settings))
	ui.system_keyboard = index == 0 && state.interaction.system_keyboard_available && state.settings.on_screen_keyboard == .System
	ui.bindings, ui.input_backend = state.interaction.bindings, state.interaction.input_backend
	// Every viewport has the same size, so one font cache serves them.
	if index == 0 {
		sync_font_cache(&state.interaction.font_cache, state.settings, ui.pixels_per_unit)
	}
	screen_context := make_screen_context(state, index)
	if session := state.session; viewport_player_ready(session, viewport^) {
		show_simulation_events(ui, session.simulation.events[:], viewport.player)
		show_quest_notices(ui, session.simulation.quests.notices[:], session.simulation.records.shipments[:], state.content.items)
		draw_hud(ui, screen_context, make_hud_context(state, index))
	}
	run_screens(ui, screen_context)
	if notice := viewport_notice(state, viewport^); notice != "" {
		draw_loading_notice(ui, notice)
	}
	// After the screens, so Start and Back show over an open one.
	if index == 0 && state.session != nil && frame_touch_overlay_on(state) && !touch_layout_editor_shown(ui.screens) {
		draw_touch_overlay(ui, state.interaction.touch_overlay, frame_touch_layout(touch_overlay_context(state)), screen_pixels, !ui_blocks_world(ui.screens))
	}
}

frame_icon_atlas :: proc(state: ^Frame_State) -> Icon_Atlas {
	return Icon_Atlas {
		texture      = chunk_atlas_texture(state.presentation.renderer),
		layout       = state.presentation.renderer.atlas_layout,
		item_texture = state.presentation.item_atlas.texture,
		item_layout  = state.presentation.item_atlas.layout,
		ui_texture   = state.presentation.ui_icon_atlas.texture,
		ui_layout    = state.presentation.ui_icon_atlas.layout,
	}
}

// The viewport's UI drawn into the current target, in its render pixels.
run_viewport_ui :: proc(state: ^Frame_State, index: int) {
	build_viewport_ui(state, index)
	begin_render_pixel_drawing()
	ui_end(&state.viewports[index].interaction.ui, frame_icon_atlas(state), &state.viewports[index].interaction.ui_images)
}

// After every viewport's UI pass: the events and notices every viewport
// showed are taken, the game's requests collected, the system keyboard,
// the UI sounds and the cursor.
finish_ui_frame :: proc(state: ^Frame_State) {
	if state.session != nil {
		clear(&state.session.simulation.events)
		clear(&state.session.simulation.quests.notices)
	}
	collect_global_requests(state)
	sync_system_keyboard(state)
	for &viewport in active_viewports(state) {
		play_ui_sounds(&state.presentation.audio, &viewport.interaction.ui)
	}
	apply_cursor_mode(state)
}

// One viewport straight to the window: the title, and single player.
run_ui_frame :: proc(state: ^Frame_State) {
	run_viewport_ui(state, 0)
	finish_ui_frame(state)
}

// Shows the system keyboard for the field that types through it and hides
// it once the entry ended, however it ended (Done, a tap elsewhere, a
// screen change).
sync_system_keyboard :: proc(state: ^Frame_State) {
	keyboard := &primary_ui(state).keyboard
	switch system_keyboard_change(keyboard^, state.interaction.system_keyboard_shown) {
	case .Show:
		field := units_to_window_rectangle(keyboard.field_rectangle, primary_ui(state).pixels_per_unit, cursor_window_size(), render_size())
		show_system_keyboard(System_Keyboard_Field{field.x, field.y, field.width, field.height})
		state.interaction.system_keyboard_shown = true
	case .Hide:
		hide_system_keyboard()
		state.interaction.system_keyboard_shown = false
	case .None:
	}
	keyboard.show_requested = false
}

// A UI rectangle in the window's coordinates, as SDL hands Steam the text
// input rectangle: render pixels scaled per axis by the window's size over
// the framebuffer's, the inverse of pointer_to_render_pixels. The identity
// on X11, where both are pixels; a zero size (a minimised window) leaves
// the pixels alone.
units_to_window_rectangle :: proc(rectangle: Ui_Rectangle, pixels_per_unit: f32, window_size, render_size: [2]int) -> Ui_Rectangle {
	factor := [2]f32{pixels_per_unit, pixels_per_unit}
	if window_size.x > 0 && window_size.y > 0 && render_size.x > 0 && render_size.y > 0 {
		factor *= [2]f32{f32(window_size.x) / f32(render_size.x), f32(window_size.y) / f32(render_size.y)}
	}
	return {rectangle.x * factor.x, rectangle.y * factor.y, rectangle.width * factor.x, rectangle.height * factor.y}
}

// Only the viewport's player's events: another player toasts on its own
// viewport or machine. The frame takes the events after every viewport
// showed them (finish_ui_frame).
show_simulation_events :: proc(state: ^Ui_State, events: []Simulation_Event, local_player: int) {
	for event in events {
		if event.player != local_player {
			continue
		}
		switch event.kind {
		case .Inventory_Full:
			ui_toast(state, text("inventory_full"))
		case .Open_Machine:
			if state.screens.count == 0 {
				push_screen(&state.screens, .Machine)
			}
		case .Toggled_Switch:
		// The switch's colour shows the change.
		case .Launch_Requested:
			ui_toast(state, text("toast_rocket_launch"))
		case .Vein_Assayed:
			ui_toast(state, text("toast_vein_assayed"))
		case .Magnetometer_Recorded:
			ui_toast(state, text("toast_magnetometer_recorded"))
		case .Seismic_Shot_Fired:
			ui_toast(state, text("toast_seismic_shot"))
		case .Action_Refused:
			ui_toast(state, text("toast_action_refused"))
		case .Field_Refused:
			if key := field_refusal_keys[event.field_refusal]; key != "" {
				ui_toast(state, text(key))
			}
		}
	}
}

// Mission Control's lines to its panel, a discovery to its card, the
// rest (finished research, the capsule landing, the venture's notes) as
// toasts (work item 0069), on every viewport: research and the venture
// are everyone's. The frame takes them after the UI pass.
show_quest_notices :: proc(state: ^Ui_State, notices: []Quest_Message, shipments: []Shipment, items: Item_Registry) {
	for notice in notices {
		switch notice_presentation(notice.text_key) {
		case .Mission_Control:
			ui_mission_control_line(state, quest_message_text(notice, shipments, items))
		case .Discovery_Card:
			ui_discovery_card(state, notice.item, text(notice.argument_key))
		case .Toast:
			ui_toast(state, quest_message_text(notice, shipments, items))
		}
	}
}

// The registries the simulation reads (Simulation_Content, whose
// generator stays nil here: a session's content points at the session's
// generator, frame_simulation_content) and the presentation tables.
Game_Content :: struct {
	using simulation_content: Simulation_Content,
	// The journal's Notes tab (notes.odin); presentation only, so the
	// simulation never sees it.
	notes:           Note_Registry,
	// The touch overlay's layout (touch_overlay.odin); presentation only.
	touch_overlay:   Touch_Overlay_Layout,
	// The planet records (data_planet.odin); the terrain field generates
	// from them (generation_planet.odin).
	planets:         []Planet,
	// The terrain field's material table (field_mining.odin) and the
	// light's curve and emitters (data_lighting.odin), which a field
	// session's Field_Content is made from (make_field_content).
	field_materials: Field_Material_Table,
	lighting:        Lighting_File,
	item_sort_ranks: []u16,
	recipe_names:    []string,
	recipe_order:    []int,
	unlock_all:      bool,
	// --dev: the pause menu shows the Developer entry.
	developer_mode:  bool,
}

// Between frames: starts, loads or leaves a world as the menus asked. A
// world that cannot be made or loaded leaves the title showing with a
// toast.
apply_session_request :: proc(state: ^Frame_State) {
	request := state.interaction.title.request
	state.interaction.title.request = {}
	switch request.kind {
	case .None:
	case .New_World:
		setup := &state.interaction.title.setup
		seed, _ := world_setup_seed(setup)
		plan := new_world_plan(strings.trim_space(text_field_text(&setup.name)), seed, world_file_settings_from_setup(setup^, state.content.planets), state.interaction.title.saves_directory, state.interaction.title.saves_found, false)
		enter_planned_session(state, plan)
	case .Load:
		plan, problem := saved_world_plan(state.interaction.title.saves_directory, request.directory_name)
		if problem != "" {
			report_session_problem(state, problem)
			return
		}
		enter_planned_session(state, plan)
	case .Quit_To_Title:
		leave_session(state)
		show_title(state)
	case .Join:
		start_title_join(state, text_field_text(&state.interaction.title.join_address))
	}
}

// A join from the Multiplayer screen or --join, while no world plays and
// no other join runs.
start_title_join :: proc(state: ^Frame_State, address: string) {
	if state.session != nil || join_active(state.joining) {
		platform.log_printf("network: a join to %s was asked while a world or a join runs", address)
		ui_toast(primary_ui(state), text("multiplayer_already_joining"))
		return
	}
	start_joining(&state.joining.network, address, state.config.tick_rate)
}

report_session_problem :: proc(state: ^Frame_State, problem: string) {
	platform.log_printf("error: %s", problem)
	ui_toast(primary_ui(state), fmt.tprintf("%s: %s", text("title_world_failed"), problem))
}

// A new world saves at once, so it exists on disk from the start.
enter_planned_session :: proc(state: ^Frame_State, plan: Session_Plan) {
	session, problem := start_session(plan, state.config, state.content, state.base_generator)
	if problem != "" {
		report_session_problem(state, problem)
		return
	}
	if !plan.loading && session.save.enabled {
		save_session(session, state.content)
	}
	enter_session(state, session)
}

enter_session :: proc(state: ^Frame_State, session: ^Session) {
	if join_active(state.joining) {
		platform.log_printf("network: the join was cancelled by a local world")
		destroy_session_join(&state.joining)
	}
	state.session = session
	host_windowed_session(session, state.hosting)
	state.presentation.sound_memory = {}
	if session.simulation.field.enabled {
		start_field_presentation(state)
	}
	// The world starts in the first viewport alone, its player the
	// machine's own.
	viewport := &state.viewports[0]
	viewport.player = session_local_player_index(session)
	viewport.tick_input = {}
	viewport.field_turn_remainder = {}
	viewport.interaction.session_views = make_session_views()
	viewport.presentation = Viewport_Presentation {
		target = viewport.presentation.target,
	}
	ui := &viewport.interaction.ui
	clear_mission_control(&ui.mission_control)
	ui.screens = {}
	ui.keyboard = {}
	ui.tooltip_open = false
}

// Saves first when the world saves.
leave_session :: proc(state: ^Frame_State) {
	session := state.session
	if session == nil {
		return
	}
	if session.save.enabled && save_session(session, state.content) == "" {
		platform.log_printf("world: saved %q", session.save.location.display_name)
	}
	unload_all_chunk_meshes(&state.presentation.renderer)
	stop_field_presentation(&state.presentation)
	end_session(session)
	remove_extra_viewports(state)
	destroy_session_views(&state.viewports[0].interaction.session_views)
	state.viewports[0].interaction.session_views = {}
	release_viewport_target(&state.viewports[0].presentation)
	state.viewports[0].requests = {}
	state.session = nil
	state.developer.diagnostics_page = .Off
	state.developer.show_world_overlay = false
	// A pause command holds only the world it was given in.
	state.developer.command_control.paused = false
}

// Once the settings screen is closed (and on exit), changed settings go to
// config.d/90-settings.sjson. A failed write is reported once, not retried.
write_changed_settings :: proc(state: ^Frame_State) {
	if state.settings == state.stored_settings {
		return
	}
	state.stored_settings = state.settings
	if problem := write_settings_file(state.environment, state.settings); problem != "" {
		platform.log_printf("error: cannot save the settings: %s", problem)
	}
}

show_title :: proc(state: ^Frame_State) {
	ui := primary_ui(state)
	ui.screens = {}
	ui.keyboard = {}
	push_screen(&ui.screens, .Title)
	refresh_title_saves(&state.interaction.title)
}

// Takes ownership of the session, or shows the title when there is none.
// Saves on quit when the world saves.
run_game :: proc(config: Game_Config, input_backend: Input_Backend, game_data: Game_Data, data_directory: string, fonts: Loaded_Fonts, session: ^Session, title: Title_State, player_configuration: Player_Configuration) {
	content := game_data.content
	install_raylib_trace_log()
	rl.SetTraceLogLevel(.WARNING)
	// Opened windowed; the settings' mode applies below, once raylib can
	// report the monitor.
	window_settings := initial_window_settings(player_configuration.settings)
	rl.SetConfigFlags(window_config_flags(window_settings))
	when ODIN_PLATFORM_SUBTARGET == .Android {
		// raylib sizes the window to the screen (work item 0114).
		rl.InitWindow(0, 0, "Mine oh Belowed")
	} else {
		rl.InitWindow(i32(window_settings.resolution.x), i32(window_settings.resolution.y), "Mine oh Belowed")
	}
	// raylib returns from a failed InitWindow instead of reporting it, and
	// the first draw call would then crash. A missing display is the usual cause.
	if !rl.IsWindowReady() {
		platform.log_printf("error: could not open a window (is a display available?)")
		os.exit(1)
	}
	defer rl.CloseWindow()
	// Escape is bound to the Pause action, so it must not close the window.
	rl.SetExitKey(.KEY_NULL)
	monitor_size := current_monitor_size()
	window_platform := current_window_platform()
	log_display_diagnostics(window_platform)
	log_gl_info()
	update_display(&window_settings, player_configuration.settings, monitor_size, window_platform)

	renderer, renderer_ok := init_chunk_renderer_or_without_edits(content.blocks, data_directory)
	if !renderer_ok {
		os.exit(1)
	}
	// On the heap: four viewports' UI and particles make the state too
	// large for a stack frame.
	state := new(Frame_State)
	defer free(state)
	// Field by field: a whole literal would build the large value on the
	// stack first.
	state.config, state.content, state.base_generator = config, content, game_data.base_generator
	state.data_directory, state.environment = data_directory, player_configuration.environment
	state.settings, state.stored_settings = player_configuration.settings, player_configuration.settings
	// The first viewport: the keyboard, the mouse, the touch overlay and
	// the first pad (viewport.odin).
	state.viewports[0].keyboard_mouse = true
	state.viewport_count = 1
	state.interaction = {
		touch_overlay_forced = player_configuration.touch_overlay_forced,
		title           = title,
		input_backend   = input_backend,
		bindings        = player_configuration.bindings,
		input_bindings  = player_configuration.input_bindings,
		fonts           = fonts,
		// raylib starts with the cursor shown; the first apply hides it.
		cursor_enabled  = true,
	}
	state.presentation = {
		renderer        = renderer,
		window_settings = window_settings,
		monitor_size    = monitor_size,
		window_scale    = window_scale(),
		platform        = window_platform,
	}
	state.reload = {
		content_arena   = game_data.arena,
		watch_data_flag = player_configuration.watch_data,
		binding_overrides = player_configuration.binding_overrides,
	}
	// After the session left, which saves with the content.
	defer destroy_hot_reload_state(state)
	defer destroy_viewport(&state.viewports[0])
	strings_text, _, _ := read_strings_file(data_directory)
	init_font_cache(&state.interaction.font_cache, data_directory, state.interaction.fonts.families, string(strings_text), state.settings)
	primary_ui(state).fonts, primary_ui(state).measure_text = &state.interaction.font_cache, measure_font_text
	defer destroy_font_cache(&state.interaction.font_cache)
	theme, theme_problem := load_ui_theme(data_directory)
	if theme_problem != "" && turn_data_edits_off(theme_problem) {
		theme, theme_problem = load_ui_theme(data_directory)
	}
	if theme_problem != "" {
		platform.log_printf("error: %s", theme_problem)
		os.exit(1)
	}
	apply_ui_theme(primary_ui(state), theme)
	if data_edits_reading.off {
		ui_toast(primary_ui(state), text("data_files_edits_off_toast"))
	}
	if player_configuration.settings_set_aside {
		ui_toast(primary_ui(state), text("settings_file_set_aside_toast"))
	}
	if player_configuration.fonts_fell_back {
		ui_toast(primary_ui(state), text("settings_font_default_toast"))
	}
	state.presentation.ui_icon_atlas = upload_ui_icon_atlas(data_directory)
	defer destroy_item_atlas(&state.presentation.ui_icon_atlas)
	defer destroy_title_state(&state.interaction.title)
	defer write_changed_settings(state)
	defer if input_backend == .Sdl3 {
		shutdown_sdl3_input(&state.interaction.sdl3_input)
	}
	state.interaction.vibrator = start_vibrator()
	defer stop_vibrator(&state.interaction.vibrator)
	state.interaction.system_keyboard_available = system_keyboard_available()
	platform.log_printf("keyboard: system keyboard %s", state.interaction.system_keyboard_available ? "available" : "not available")
	defer destroy_chunk_renderer(&state.presentation.renderer)
	state.presentation.item_atlas = upload_item_atlas(&state.content.items, data_directory)
	defer destroy_item_atlas(&state.presentation.item_atlas)
	state.presentation.belt_renderer = init_belt_renderer(content.machines)
	defer destroy_belt_renderer(&state.presentation.belt_renderer)
	state.presentation.model_renderer = init_model_renderer(content.machines, data_directory)
	defer destroy_model_renderer(&state.presentation.model_renderer)
	state.presentation.particle_renderer = init_particle_renderer()
	defer destroy_particle_renderer(&state.presentation.particle_renderer)
	state.presentation.player_model = init_player_model(data_directory)
	defer unload_player_model(&state.presentation.player_model)
	state.presentation.audio = init_audio(data_directory, content.blocks, game_data.base_generator.biomes, state.settings)
	defer shutdown_audio(&state.presentation.audio)
	start_command_frame_state(state)
	defer destroy_command_frame_state(state)
	load_texture_editor(&state.developer.texture_editor, data_directory, texture_edits_path(), state.content.blocks)
	defer destroy_texture_editor(&state.developer.texture_editor)
	state.developer.data_browser = make_data_browser()
	defer destroy_data_browser(&state.developer.data_browser)
	touch_layouts_problem: string
	if state.interaction.touch_layouts, touch_layouts_problem = load_touch_layouts(state.environment); touch_layouts_problem != "" {
		ui_toast(primary_ui(state), touch_layouts_locked_text(state.interaction.touch_layouts))
	}
	defer destroy_touch_layouts(&state.interaction.touch_layouts)
	defer destroy_touch_layout_editor(&state.interaction.touch_layout_editor)
	if session != nil {
		enter_session(state, session)
	} else {
		show_title(state)
	}
	defer leave_session(state)
	defer destroy_session_join(&state.joining)
	state.hosting = default_hosting_plan()
	defer close_lan_query(&state.lan_query)
	if player_configuration.join_address != "" {
		request_join(&state.interaction.title, player_configuration.join_address)
	}
	apply_cursor_mode(state)
	for !rl.WindowShouldClose() && (.Quit not_in state.requests) {
		update_frame(state)
		serve_frame_requests_before_draw(state)
		render_frame(state)
		update_audio(&state.presentation.audio, state.settings, state.frame_seconds)
		serve_frame_requests_after_draw(state)
		// Applied at once, like the font choice.
		update_display(&state.presentation.window_settings, state.settings, state.presentation.monitor_size, state.presentation.platform)
		state.presentation.window_scale = window_scale()
		if !any_viewport_shows(state, .Settings) {
			write_changed_settings(state)
		}
		free_all(context.temp_allocator)
	}
}

// Some viewport has the screen on its stack.
any_viewport_shows :: proc(state: ^Frame_State, screen: Screen) -> bool {
	for viewport in active_viewports(state) {
		if screen_stack_contains(viewport.interaction.ui.screens, screen) {
			return true
		}
	}
	return false
}

// The screens' requests served before the draw, each viewport's for its
// own screens. The order is in doc/architecture.md, Frame and tick. Two
// constraints: the data browser's close comes before its discard, and
// the reload runs after the draw (serve_frame_requests_after_draw), since
// it frees memory a frame draws from.
serve_frame_requests_before_draw :: proc(state: ^Frame_State) {
	for index in 0 ..< state.viewport_count {
		serve_viewport_requests_before_draw(state, index)
	}
}

// One viewport's requests: its toasts and its screen (the texture editor,
// the data browser, the touch layout editor) are its own; the editors'
// state is the process's.
serve_viewport_requests_before_draw :: proc(state: ^Frame_State, index: int) {
	viewport := &state.viewports[index]
	ui := &viewport.interaction.ui
	serve_texture_editor(&state.developer.texture_editor, ui, state.presentation.renderer, state.data_directory, state.content.blocks, &viewport.requests)
	data_browser := Data_Browser_Context{browser = &state.developer.data_browser, ui = ui, settings = &state.settings, data_directory = state.data_directory, requests = &viewport.requests}
	apply_data_edit_change(state, serve_data_browser(data_browser))
	if serve_touch_layouts(&state.interaction.touch_layouts, &state.interaction.touch_layout_editor, ui, state.content.touch_overlay, state.environment, &viewport.requests) {
		state.interaction.touch_overlay = release_touch_latches(state.interaction.touch_overlay)
	}
}

// The requests served after the draw: a split screen guest leaving
// (which frees its viewport's UI), the session request, the data watch,
// the reload.
serve_frame_requests_after_draw :: proc(state: ^Frame_State) {
	serve_viewport_removals(state)
	apply_session_request(state)
	serve_lan_query(state)
	update_data_watch(state)
	apply_reload_request(state)
}

// The guests that left through their pause menus (the first viewport
// stays).
serve_viewport_removals :: proc(state: ^Frame_State) {
	for index := state.viewport_count - 1; index > 0; index -= 1 {
		if .Remove_Viewport in state.viewports[index].requests {
			remove_viewport(state, index)
		}
	}
	state.viewports[0].requests -= {.Remove_Viewport}
}

// Command socket (work item 0053, command_socket.odin, command.odin).

start_command_frame_state :: proc(state: ^Frame_State) {
	state.developer.command_server = make_command_server()
	directories := platform.platform_directories(context.temp_allocator)
	state.developer.command_socket_path, _ = command_socket_path_from_environment(directories.runtime_directory, directories.state_home, directories.home)
	state.developer.screenshot_directory, _ = screenshot_directory_from_environment(directories.state_home, directories.home)
}

destroy_command_frame_state :: proc(state: ^Frame_State) {
	destroy_command_server(&state.developer.command_server)
	delete(state.developer.command_socket_path)
	delete(state.developer.screenshot_directory)
	delete(state.developer.command_control.screenshot_path)
}

// Listens while developer mode is on (--dev or the setting), and stops
// when the setting is switched off. A failure to listen is logged once.
// Does nothing where there is no command socket (Windows, 0108).
update_command_server_open :: proc(state: ^Frame_State) {
	server := &state.developer.command_server
	wanted := state.content.developer_mode || state.settings.developer_mode
	switch {
	case COMMAND_SOCKET_SUPPORTED && wanted && server.listening == -1 && !server.open_failed:
		problem := state.developer.command_socket_path == "" ? "no directory for it (set XDG_RUNTIME_DIR, XDG_STATE_HOME or HOME)" : open_command_server(server, state.developer.command_socket_path)
		if problem != "" {
			platform.log_printf("error: command socket: %s", problem)
			server.open_failed = true
		} else {
			platform.log_printf("command: listening on %s", server.path)
		}
	case !wanted && server.listening != -1:
		close_command_server(server)
		platform.log_printf("command: socket closed")
	case !wanted:
		server.open_failed = false
	}
}

// After the frame's ticks: answers a tick command whose ticks ran, then
// executes the queued lines in order until one starts a tick command.
serve_command_socket :: proc(state: ^Frame_State) {
	update_command_server_open(state)
	server := &state.developer.command_server
	if server.listening == -1 {
		return
	}
	poll_command_server(server)
	answer_command_ticks(state)
	for !state.developer.command_control.ticks_waiting && !state.developer.command_control.line_waiting {
		queued := take_command_line(server) or_break
		execute_queued_command(state, queued)
		delete(queued.line)
	}
	flush_command_server(server)
}

answer_command_ticks :: proc(state: ^Frame_State) {
	control := &state.developer.command_control
	if control.line_waiting && state.session == nil {
		control.line_waiting = false
		send_logged_response(state, control.line_client, "a waiting line", command_error("the world was closed"))
	}
	if control.ticks_waiting && state.session == nil {
		control.pending_ticks, control.ticks_waiting = 0, false
		send_logged_response(state, state.developer.command_server.tick_client, "tick", command_error("the world was closed"))
		state.developer.command_server.tick_client = 0
		return
	}
	if state.session == nil {
		return
	}
	// A machine joined the host while the ticks ran: the rest would run
	// without its records.
	if control.ticks_waiting && !session_alone(state.session.network) {
		control.pending_ticks, control.ticks_waiting = 0, false
		send_logged_response(state, state.developer.command_server.tick_client, "tick", command_error("stopped: another machine joined"))
		state.developer.command_server.tick_client = 0
		return
	}
	if response, finished := finish_command_ticks(control, state.session.simulation.tick); finished {
		send_logged_response(state, state.developer.command_server.tick_client, "tick", response)
		state.developer.command_server.tick_client = 0
	}
}

send_logged_response :: proc(state: ^Frame_State, client: u64, line: string, response: Command_Response) {
	text := format_command_response(response)
	log_command_exchange(line, text)
	send_command_response(&state.developer.command_server, client, text)
}

frame_command_context :: proc(state: ^Frame_State) -> Command_Context {
	command_context := Command_Context {
		content              = state.content.simulation_content,
		control              = &state.developer.command_control,
		textures             = state.developer.texture_editor.entries[:],
		screenshot_directory = state.developer.screenshot_directory,
		now                  = time.now(),
	}
	if state.session != nil {
		command_context.simulation = &state.session.simulation
		command_context.player = session_local_player_index(state.session)
		command_context.content = frame_simulation_content(state)
		command_context.weather_override = &state.session.weather_override
	}
	return command_context
}

// save and reload need the session and the game content, the rest runs
// in command.odin. A tick command answers later (answer_command_ticks).
execute_queued_command :: proc(state: ^Frame_State, queued: Queued_Command_Line) {
	words, _ := split_command_words(queued.line)
	response: Command_Response
	switch {
	case len(words) == 0 || state.session == nil:
	case command_writes_simulation(words[0]):
		response = queue_socket_line(state, queued, words)
		if !response.deferred {
			send_logged_response(state, queued.client, queued.line, response)
		}
		return
	case (words[0] == "tick" || words[0] == "pause" || words[0] == "reload") && !session_alone(state.session.network):
		send_logged_response(state, queued.client, queued.line, command_error("%s runs only without other machines", words[0]))
		return
	}
	if len(words) > 0 && words[0] == "save" {
		response = command_save(state)
	} else if len(words) > 0 && words[0] == "reload" {
		response = command_reload(state)
	} else {
		empty: bool
		if response, empty = execute_command_line(frame_command_context(state), queued.line); empty {
			return
		}
	}
	if response.deferred {
		platform.log_printf("command: %s", queued.line)
		state.developer.command_server.tick_client = queued.client
		return
	}
	send_logged_response(state, queued.client, queued.line, response)
}

// A line that writes the simulation goes into the local player's next
// input record and is answered once its tick ran it (send_line_answers);
// a blueprint's file is read here, so every machine runs the same text.
queue_socket_line :: proc(state: ^Frame_State, queued: Queued_Command_Line, words: []string) -> Command_Response {
	blueprint: string
	if words[0] == "blueprint" && len(words) == 2 {
		data, error := os.read_entire_file(words[1], context.allocator)
		if error != nil {
			return command_error("cannot read %s: %v", words[1], error)
		}
		blueprint = string(data)
	}
	append(&state.session.lockstep.local_lines, Socket_Line{line = strings.clone(queued.line), blueprint = blueprint, client = queued.client})
	state.developer.command_control.line_waiting = true
	state.developer.command_control.line_client = queued.client
	platform.log_printf("command: %s", queued.line)
	return Command_Response{ok = true, deferred = true}
}

// The answers of the local socket lines a tick ran.
send_line_answers :: proc(state: ^Frame_State, answers: []Line_Answer) {
	for answer in answers {
		send_logged_response(state, answer.client, answer.line, answer.response)
		state.developer.command_control.line_waiting = false
	}
}

command_save :: proc(state: ^Frame_State) -> Command_Response {
	if state.session == nil {
		return command_error("no world is loaded")
	}
	if problem := save_session(state.session, state.content); problem != "" {
		return command_error("%s", problem)
	}
	return command_ok("saved %s", state.session.save.location.display_name)
}

// Ticks of a tick command with no player input, as many as fit in
// COMMAND_TICK_WALL_BUDGET. Returns how many ran.
run_command_ticks :: proc(state: ^Frame_State, content: Simulation_Content) -> int {
	start := time.tick_now()
	count := 0
	for state.developer.command_control.pending_ticks > 0 && time.tick_since(start) < COMMAND_TICK_WALL_BUDGET {
		release_local_commands(&state.session.lockstep, &state.session.simulation)
		run_command_tick(&state.session.simulation, content, &state.developer.command_control)
		count += 1
	}
	return count
}

// The Developer screen's button, queued like the screenshot command; the
// viewport that asked toasts. The screenshot holds the whole window.
queue_requested_screenshot :: proc(state: ^Frame_State, index: int) {
	viewport := &state.viewports[index]
	if .Take_Screenshot not_in viewport.requests {
		return
	}
	viewport.requests -= {.Take_Screenshot}
	path, problem := queue_screenshot(&state.developer.command_control, state.developer.screenshot_directory, "", time.now())
	if problem != "" {
		platform.log_printf("error: screenshot: %s", problem)
		ui_toast(&viewport.interaction.ui, fmt.tprintf("%s: %s", text("developer_screenshot_failed"), problem))
		return
	}
	ui_toast(&viewport.interaction.ui, fmt.tprintf("%s %s", text("developer_screenshot_saved"), path))
}

// At the end of the frame, before EndDrawing shows it: the drawn frame
// read back and written as PNG. ExportImage takes the absolute path as
// given (TakeScreenshot would put the file in the working directory).
capture_pending_screenshot :: proc(state: ^Frame_State) {
	path := state.developer.command_control.screenshot_path
	if path == "" {
		return
	}
	state.developer.command_control.screenshot_path = ""
	defer delete(path)
	rlgl.DrawRenderBatchActive()
	image := rl.LoadImageFromScreen()
	defer rl.UnloadImage(image)
	if rl.ExportImage(image, strings.clone_to_cstring(path, context.temp_allocator)) {
		platform.log_printf("command: screenshot %s", path)
	} else {
		platform.log_printf("error: screenshot: cannot write %s", path)
	}
}

// The texture editor (work item 0100, ui_texture_editor.odin).

// $XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson in the temp
// allocator, "" without a state directory.
texture_edits_path :: proc() -> string {
	directories := platform.platform_directories(context.temp_allocator)
	path, _ := texture_edits_path_from_environment(directories.state_home, directories.home, context.temp_allocator)
	return path
}

// The chunk renderer, loaded again without the data edits overlay when
// its shaders failed with it (turn_data_edits_off).
init_chunk_renderer_or_without_edits :: proc(blocks: Block_Registry, data_directory: string) -> (renderer: Chunk_Renderer, ok: bool) {
	capture: platform.Log_Capture
	platform.begin_log_capture(&capture)
	renderer, ok = init_chunk_renderer(blocks, data_directory)
	problem := platform.end_log_capture(&capture, "the chunk shaders did not load")
	if !ok && turn_data_edits_off(problem) {
		renderer, ok = init_chunk_renderer(blocks, data_directory)
	}
	return renderer, ok
}

// $XDG_STATE_HOME/mine-oh-belowed/data_edits (work item 0129,
// read_data_file) in the temp allocator, "" without a state directory.
// Under odin test the test thread's own directory
// (data_edits_reading.directory), "" unless a test gives one, so the tests
// read the shipped data whatever overlay the machine holds.
data_edits_directory :: proc() -> string {
	when ODIN_TEST {
		return data_edits_reading.directory
	} else {
		directories := platform.platform_directories(context.temp_allocator)
		directory, _ := data_edits_directory_from_environment(directories.state_home, directories.home, context.temp_allocator)
		return directory
	}
}

// Before the frame's screens: the files read again when the Developer
// screen asked or a content reload renumbered the blocks; while the
// editor is open every entry's tile copied into the block atlas, which
// also puts the edits back after a reload rebuilt the atlas from the
// files; a Save written.
serve_texture_editor :: proc(editor: ^Texture_Editor, ui: ^Ui_State, renderer: Chunk_Renderer, data_directory: string, blocks: Block_Registry, requests: ^Frame_Requests) {
	if .Refresh_Texture_Editor in requests^ || !texture_editor_matches_registry(editor^, blocks) {
		requests^ -= {.Refresh_Texture_Editor}
		load_texture_editor(editor, data_directory, texture_edits_path(), blocks)
	}
	if screen_stack_contains(ui.screens, .Textures) {
		for entry in editor.entries {
			update_atlas_block_tile(chunk_atlas_texture(renderer), renderer.atlas_layout, entry.block, entry.tile)
		}
	}
	if .Save_Texture_Edits in requests^ {
		requests^ -= {.Save_Texture_Edits}
		save_texture_edits(editor, ui)
	}
}

// The Data files screen's requests (work item 0129; the save 0130, the
// export 0131, data_export.odin), before the frame's screens in the order
// of serve_frame_requests_before_draw; a discard or a save asks for the
// tree again. Returns the categories a discard or a save changed, which
// the frame loop applies right after, still between frames
// (apply_data_edit_change).
serve_data_browser :: proc(data: Data_Browser_Context) -> (changed: Data_File_Categories) {
	browser, requests := data.browser, data.requests
	apply_data_browser_close_request(browser, requests)
	if .Discard_Data_Edit in requests^ {
		requests^ -= {.Discard_Data_Edit}
		changed |= discard_data_edit(data)
	}
	if .Save_Data_Edit in requests^ {
		requests^ -= {.Save_Data_Edit}
		changed |= save_data_edit(data, data_edits_directory())
	}
	if .Export_Data_Files in requests^ {
		requests^ -= {.Export_Data_Files}
		export_data_browser_files(data, data_edits_directory())
	}
	if .Refresh_Data_Tree in requests^ {
		requests^ -= {.Refresh_Data_Tree}
		rebuild_data_tree(browser, list_data_files(data.data_directory, data_edits_directory()))
	}
	if .Open_Data_File in requests^ {
		requests^ -= {.Open_Data_File}
		open_data_browser_file(browser, data.data_directory)
	}
	return changed
}

// Deletes the selected file's overlay copy and returns its category, for
// the frame loop to apply as the watcher would (apply_data_edit_change);
// the tree and an open file are read again. A copy that cannot be deleted
// is logged and toasted, and changes nothing. With export_on_save the
// export's copy goes too (sync_data_edit_export).
discard_data_edit :: proc(data: Data_Browser_Context) -> Data_File_Categories {
	browser := data.browser
	edits_directory := data_edits_directory()
	if browser.selected < 0 || browser.selected >= len(browser.rows) || edits_directory == "" {
		return {}
	}
	relative_path := strings.clone(browser.rows[browser.selected].path, context.temp_allocator)
	overlay := platform.join_path(edits_directory, relative_path)
	if error := os.remove(overlay); error != nil {
		platform.log_printf("error: cannot discard the data edit %s: %v", overlay, error)
		ui_toast(data.ui, fmt.tprintf("%s %s", text("data_files_discard_failed"), relative_path))
		return {}
	}
	platform.log_printf("data: discarded the data edit %s", overlay)
	if browser.open && browser.unsaved {
		ui_toast(data.ui, text("data_files_changes_dropped"))
	}
	ui_toast(data.ui, fmt.tprintf("%s %s", text("data_files_discarded"), relative_path))
	sync_data_edit_export(data, edits_directory, relative_path)
	data.requests^ += {.Refresh_Data_Tree}
	data.requests^ -= {.Open_Data_File}
	if browser.open {
		data.requests^ += {.Open_Data_File}
	}
	return {data_file_category(relative_path)}
}

// Writes the open SJSON file's tree to the edits directory (0130) and
// returns its category, for the frame loop to apply as the watcher would
// (apply_data_edit_change); the tree is read again for its edited tag. A
// failed write is logged and toasted, the file stays unsaved, and nothing
// changed. With export_on_save the copy goes to the export too
// (sync_data_edit_export). The edits directory is a parameter for the
// test (data_edits_directory is "" under odin test).
save_data_edit :: proc(data: Data_Browser_Context, edits_directory: string) -> Data_File_Categories {
	browser := data.browser
	if !browser.open || browser.file_kind != .Sjson || browser.file_problem != "" || browser.selected < 0 || browser.selected >= len(browser.rows) {
		return {}
	}
	relative_path := strings.clone(browser.rows[browser.selected].path, context.temp_allocator)
	file_text := sjson_text.sjson_text(browser.value, virtual.arena_allocator(browser.file_arena))
	if problem := write_data_edit(edits_directory, relative_path, file_text); problem != "" {
		platform.log_printf("error: cannot save the data edit %s: %s", relative_path, problem)
		ui_toast(data.ui, fmt.tprintf("%s %s", text("data_files_save_failed"), relative_path))
		return {}
	}
	browser.loaded_text, browser.unsaved, browser.shows_overlay = file_text, false, true
	data.requests^ += {.Refresh_Data_Tree}
	ui_toast(data.ui, fmt.tprintf("%s %s", text("data_files_saved"), relative_path))
	sync_data_edit_export(data, edits_directory, relative_path)
	return {data_file_category(relative_path)}
}

// The touch layouts (0121), between frames: the editor's request, served
// after the frame's draw list ran, since it may free the draft's arena
// the frame's text pointed into; a change of the active layout is
// returned, for the frame loop to release the overlay's latches, which
// index its elements; a change the settings
// or the editor made is written to the user file whole. A failed write is
// logged and toasted, and not retried. While a broken file from the start
// stands, nothing is written.
serve_touch_layouts :: proc(layouts: ^Touch_Layouts, editor: ^Touch_Layout_Editor, ui: ^Ui_State, default_layout: Touch_Overlay_Layout, environment: Configuration_Environment, requests: ^Frame_Requests) -> (changed: bool) {
	apply_touch_layout_request(ui, editor, layouts, default_layout, requests)
	changed = layouts.changed
	layouts.changed = false
	if .Write_Touch_Layouts not_in requests^ {
		return changed
	}
	requests^ -= {.Write_Touch_Layouts}
	if layouts.locked_path != "" {
		ui_toast(ui, touch_layouts_locked_text(layouts^))
		return changed
	}
	if problem := write_touch_layouts_file(environment, layouts^); problem != "" {
		platform.log_printf("error: cannot save the touch layouts: %s", problem)
		ui_toast(ui, text("touch_layout_save_failed"))
	}
	return changed
}

// Every texture's current parameters to the overrides file, one log line
// per texture in the data file's form, and a toast naming the file.
save_texture_edits :: proc(editor: ^Texture_Editor, ui: ^Ui_State) {
	path := texture_edits_path()
	problem := path == "" ? platform.NO_STATE_DIRECTORY_PROBLEM : ""
	lines := texture_editor_lines(editor.entries[:])
	if problem == "" {
		problem = write_texture_edits_file(path, format_texture_edits_file(lines))
	}
	if problem != "" {
		platform.log_printf("error: texture edits: %s", problem)
		ui_toast(ui, fmt.tprintf("%s: %s", text("texture_editor_save_failed"), problem))
		return
	}
	platform.log_printf("texture edits saved to %s", path)
	for line in lines {
		platform.log_printf("texture: %s", line)
	}
	for &entry in editor.entries {
		entry.edited = false
	}
	ui_toast(ui, fmt.tprintf("%s %s", text("texture_editor_saved"), path))
}
