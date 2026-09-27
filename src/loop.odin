package game

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Longest frame the accumulator accepts, so that a stall (debugger, window
// drag) does not trigger a burst of catch up ticks.
MAXIMUM_FRAME_SECONDS :: 0.25
// Wall time a tick command (work item 0053) may spend per frame, so the
// window keeps drawing and answering while it runs.
COMMAND_TICK_WALL_BUDGET :: 1 * time.Second

// The simulation owns the world and the players. players[index] reads
// inputs[index] in simulation_tick; the alpha has one player.
Simulation_State :: struct {
	tick:             u64,
	tick_rate:        int,
	day_length_ticks: u64,
	// Added to the tick for the day cycle, so the developer menu can set
	// the time of day without moving the tick every counter reads. Saved
	// through world.sjson's day_time_ticks.
	day_offset_ticks: u64,
	world:            World,
	players:          [dynamic]Player,
	// Items obtained, technologies researched and the recipes they unlock.
	unlocks:          Recipe_Unlocks,
	quests:           Quest_State,
	// Filled by ticks, emptied by the UI each frame (toasts). The
	// simulation never calls the UI itself.
	events:           [dynamic]Simulation_Event,
	// Filled by the developer menu and the command line, served and
	// emptied at the start of the next tick (developer.odin).
	developer_requests: [dynamic]Developer_Request,
	// Developer cheat speed (0044): faster movement and hand mining. Not
	// saved.
	cheat_speed:        bool,
	// The pad the world was created with, written to world.sjson so a loaded
	// world keeps it whatever the spawn rules do later (0049).
	landing_pad:        Landing_Pad_Site,
}

Simulation_Event :: struct {
	player: int,
	kind:   Player_Event,
}

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
// screen shows.
Frame_State :: struct {
	config:             Game_Config,
	content:            Game_Content,
	// The generator data every session copies (session_generator).
	base_generator:     Generator,
	session:            ^Session,
	title:              Title_State,
	input_backend:      Input_Backend,
	sdl3_input:         Sdl3_Input_State,
	input:              Input_Frame,
	// The rumble for this frame, applied by the SDL3 backend.
	haptic:             Haptic_Request,
	previous_input:     Input_Frame,
	frame_seconds:      f32,
	// World actions still held since a screen closed, see update_world_action_guard.
	world_action_guard: Action_Set,
	settings:           Settings,
	// The settings as last read or written, see write_changed_settings.
	stored_settings:    Settings,
	environment:        Configuration_Environment,
	// The effective bindings, for the settings screen's Controls list.
	bindings:           []Binding,
	input_bindings:     Input_Bindings,
	ui:                 Ui_State,
	// The map's texture (ui_draw.odin).
	ui_images:          Ui_Image_Cache,
	// The font families and the fonts loaded from them (ui_font.odin, work
	// item 0077); ui.fonts points at font_cache. A fonts reload retires
	// the old families' arena until exit, settings.font may point into it.
	fonts:              Loaded_Fonts,
	font_cache:         Font_Cache,
	retired_font_arenas: [dynamic]^virtual.Arena,
	cursor_enabled:     bool,
	quit_requested:     bool,
	renderer:           Chunk_Renderer,
	belt_renderer:      Belt_Renderer,
	show_diagnostics:   bool,
	// The world statistics overlay (draw_world_overlay), off by default.
	show_world_overlay: bool,
	// The command socket (work item 0053): open while developer mode is
	// on, served between ticks (serve_command_socket). The paths are
	// owned, empty when the environment names no directory.
	command_server:       Command_Server,
	command_control:      Command_Control,
	command_socket_path:  string,
	screenshot_directory: string,
	// The Developer screen's Screenshot button.
	screenshot_requested: bool,
	// Hot reload (work item 0054, hot_reload.odin). content and
	// base_generator live in content_arena, which a content reload frees.
	data_directory:       string,
	content_arena:        ^virtual.Arena,
	data_watch:           Data_Watch,
	watch_data_flag:      Watch_Data_Mode,
	binding_overrides:    []Binding,
	// The bindings of the last bindings reload; nil for those main read.
	bindings_arena:       ^virtual.Arena,
	// String entries a strings reload replaced, freed at exit.
	retired_strings:      [dynamic]map[string]string,
	// F8, the Developer screen's Reload data button, watch_data all.
	reload_requested:     bool,
}

// Above the middle of the debug terrain, looking down at an angle. The
// player starts here in fly mode on the debug terrain.
INITIAL_FLY_CAMERA :: Fly_Camera {
	position = {-40, 80, -40},
	yaw      = 45,
	pitch    = -30,
}

// The config's starting items must have passed validate_starting_items.
// unlock_all makes every recipe available (--unlock-all or the setting).
// The capsule stands on the landing pad from the start, and the first
// quest is active at tick 0.
make_simulation :: proc(config: Game_Config, start: Player_Start, content: Simulation_Content, technologies: Technology_Registry, unlock_all: bool, landing_pad: Landing_Pad_Site) -> Simulation_State {
	state := Simulation_State {
		tick_rate        = config.tick_rate,
		day_length_ticks = u64(config.day_length_seconds) * u64(config.tick_rate),
		unlocks          = make_recipe_unlocks(len(content.items.items), content.recipes, technologies, unlock_all),
		landing_pad      = landing_pad,
	}
	state.world.statistics = make_statistics(len(content.items.items), len(content.machines.machines), len(content.blocks.definitions))
	state.world.statistics.fluids = make_fluid_statistics(len(content.fluids.fluids))
	capsule := place_capsule(&state.world.entities, content.machines, landing_pad)
	state.quests = make_quest_state(content.quests, capsule)
	player := make_player(start)
	give_starting_items(&player, content.items, config.starting_items)
	append(&state.players, player)
	update_recipe_unlocks(&state.unlocks, content.recipes, state.players[:])
	observe_player_holdings(&state.world.statistics, state.players[:], false)
	start_quests(&state.quests, content.quests, state.world.statistics, 0)
	return state
}

destroy_simulation :: proc(state: ^Simulation_State) {
	for player in state.players {
		destroy_player(player)
	}
	delete(state.players)
	delete(state.events)
	delete(state.developer_requests)
	destroy_recipe_unlocks(state.unlocks)
	destroy_quest_state(state.quests)
	destroy_world(&state.world)
}

// A player without an input entry gets an empty one. Entities tick after
// the players, so a stack dropped into a furnace this tick is seen at once.
// Machines see the found schematics through the recipe registry
// (recipe_runs_in_machines).
simulation_tick :: proc(state: ^Simulation_State, content_tables: Simulation_Content, inputs: []Input_Frame) {
	content := content_tables
	content.recipes = with_schematics_found(content.recipes, state.unlocks.schematics_found)
	state.tick += 1
	advance_statistics_clock(&state.world.statistics, state.tick, state.tick_rate)
	serve_developer_requests(state, content)
	for index in 0 ..< len(state.players) {
		input, used := resolve_use_item(&state.players[index], &state.world.entities, content.items, index < len(inputs) ? inputs[index] : Input_Frame{})
		if used != NO_ITEM {
			if event, happened := apply_item_use(state, content, index, used); happened {
				append(&state.events, Simulation_Event{player = index, kind = event})
			}
		}
		events := tick_player(&state.world, content, state.players[:], index, input, state.tick_rate, state.cheat_speed)
		update_magnetometer(&state.world, content, &state.players[index])
		for kind in events {
			append(&state.events, Simulation_Event{player = index, kind = kind})
		}
	}
	newly_obtained := update_recipe_unlocks(&state.unlocks, content.recipes, state.players[:])
	log_discoveries(&state.quests, content.blocks, content.items, newly_obtained, state.tick)
	tick_entities(&state.world, content, state.tick_rate)
	shipments_before := len(state.world.shipments)
	apply_launch_requests(&state.world, state.tick)
	tick_venture(state, content, shipments_before)
	apply_research_result(state, content)
	observe_player_holdings(&state.world.statistics, state.players[:], true)
	observe_full_inventories(&state.world.statistics, state.players[:])
	tick_quests(&state.quests, simulation_quest_context(state, content), &state.world.entities)
	tick_world(&state.world, content.blocks, state.tick)
}

// Opens the recipes of a technology the labs finished this tick and says
// so in the message log.
apply_research_result :: proc(state: ^Simulation_State, content: Simulation_Content) {
	if technology, finished := apply_finished_research(&state.world.research, &state.unlocks, content.recipes); finished {
		log_research_complete(&state.quests, state.tick, content.technologies.technologies[technology].name_key)
	}
}

simulation_quest_context :: proc(state: ^Simulation_State, content: Simulation_Content) -> Quest_Tick_Context {
	return Quest_Tick_Context {
		registry = content.quests,
		recipes = content.recipes,
		items = content.items,
		statistics = &state.world.statistics,
		unlocks = &state.unlocks,
		tick = state.tick,
		tick_rate = state.tick_rate,
	}
}

// With the session's generator, for the orbital survey.
frame_simulation_content :: proc(state: ^Frame_State) -> Simulation_Content {
	content := session_simulation_content(state.content, state.session.technologies)
	content.generator = &state.session.generator
	return content
}

// The tick the day cycle shows.
simulation_day_ticks :: proc(state: Simulation_State) -> u64 {
	return state.tick + state.day_offset_ticks
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

read_input_frame :: proc(state: ^Frame_State, frame_seconds: f32) -> Input_Frame {
	switch state.input_backend {
	case .Sdl3:
		return read_sdl3_input_frame(&state.sdl3_input, state.input, frame_seconds, state.settings, state.input_bindings)
	case .Raylib:
		return read_raylib_input_frame(state.input.pressed, state.input_bindings)
	}
	return {}
}

// The mouse steers the view while the world is shown and is free for the
// diagnostics screen and the menus.
apply_cursor_mode :: proc(state: ^Frame_State) {
	wanted := state.show_diagnostics || state.ui.screens.count > 0
	if wanted == state.cursor_enabled {
		return
	}
	state.cursor_enabled = wanted
	if wanted {
		rl.EnableCursor()
	} else {
		rl.DisableCursor()
	}
}

toggle_on_press :: proc(value: bool, just_pressed: Action_Set, action: Action) -> bool {
	return action in just_pressed ? !value : value
}

apply_debug_actions :: proc(state: ^Frame_State) {
	state.show_diagnostics = toggle_on_press(state.show_diagnostics, state.input.just_pressed, .Toggle_Diagnostics)
	state.show_world_overlay = toggle_on_press(state.show_world_overlay, state.input.just_pressed, .Toggle_World_Overlay)
	session := state.session
	if .Debug_Remove_Block in state.input.just_pressed {
		session.debug_edit_counter += 1
		eye := player_eye(session.simulation.players[0].position)
		debug_remove_block(&session.simulation.world, state.content.blocks, eye, session.debug_edit_counter)
	}
	if .Debug_Drop_Item in state.input.just_pressed {
		debug_drop_item_on_belt(&session.simulation.world, frame_simulation_content(state), session.simulation.players[0])
	}
}

// The UI runs in render_frame, so the screen stack read here is the one the
// previous frame left: a screen opened or closed takes effect on the world
// one frame later.
update_frame :: proc(state: ^Frame_State) {
	state.frame_seconds = rl.GetFrameTime()
	state.previous_input = state.input
	state.input = read_input_frame(state, state.frame_seconds)
	world_blocked := ui_blocks_world(state.ui.screens)
	state.world_action_guard = update_world_action_guard(state.world_action_guard, world_blocked, state.input.pressed)
	state.haptic = {}
	if state.session != nil {
		apply_debug_actions(state)
		apply_overlay_toggle(state, world_blocked)
		update_session(state, world_blocked)
		state.haptic = haptic_request_for(state.session.simulation.players[0], !world_blocked)
	}
	if .Reload_Data in state.input.just_pressed && developer_mode_on(state) {
		state.reload_requested = true
	}
	serve_command_socket(state)
	if state.input_backend == .Sdl3 {
		apply_sdl3_haptics(&state.sdl3_input, state.haptic)
	}
}

// Only while no screen is open, so O typed into a text field or pressed
// in a menu does nothing. The setting is written like any other changed
// setting.
apply_overlay_toggle :: proc(state: ^Frame_State, world_blocked: bool) {
	if .Toggle_Bottleneck_Overlay in state.input.just_pressed && !world_blocked {
		state.settings.bottleneck_overlay = !state.settings.bottleneck_overlay
	}
}

// A pause command holds the ticks like a pausing screen; a tick command
// replaces the frame's ticks with its own (run_command_ticks).
update_session :: proc(state: ^Frame_State, world_blocked: bool) {
	session := state.session
	paused := ui_pauses_simulation(state.ui.screens) || state.command_control.paused
	fast := state.command_control.pending_ticks > 0
	frame_for_world := world_input(state.input, world_blocked, state.world_action_guard, state.settings)
	// The right stick drives an open hotbar radial instead of the camera.
	if state.ui.radial.open {
		frame_for_world = without_actions(frame_for_world, {.Look})
	}
	session.tick_input = paused ? {} : accumulate_frame_input(session.tick_input, frame_for_world)
	tick_count: int
	session.accumulator, tick_count = advance_simulation_clock(session.accumulator, f64(state.frame_seconds), paused || fast)
	for _ in 0 ..< tick_count {
		tick_input: Input_Frame
		tick_input, session.tick_input = take_tick_input(session.tick_input, frame_for_world)
		simulation_tick(&session.simulation, frame_simulation_content(state), {tick_input})
	}
	if fast {
		tick_count = run_command_ticks(state)
	}
	session.ticks_since_save += u64(tick_count)
	save_when_due(state)
	player_chunk := world_to_chunk_coordinate(camera_world_coordinate(session.simulation.players[0].position))
	update_chunk_streaming(&session.streaming, &session.simulation.world, player_chunk)
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
		ui_toast(&state.ui, text("save_failed"))
	} else {
		ui_toast(&state.ui, text(requested ? "save_done" : "autosave_done"))
	}
}

render_frame :: proc(state: ^Frame_State) {
	if state.session == nil {
		rl.BeginDrawing()
		defer rl.EndDrawing()
		rl.ClearBackground(DAY_SKY_COLOR)
		run_ui_frame(state)
		capture_pending_screenshot(state)
		return
	}
	session := state.session
	upload_streamed_meshes(&state.renderer, &session.streaming)
	blend := daylight_blend(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks)
	apply_daylight(&state.renderer, blend)
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(sky_color(blend))
	draw_session_world(state, session)
	if state.show_diagnostics {
		draw_diagnostics_backdrop()
		draw_diagnostics(state^, state.config)
	} else if state.show_world_overlay {
		draw_world_overlay(state^)
	}
	run_ui_frame(state)
	queue_requested_screenshot(state)
	capture_pending_screenshot(state)
}

draw_session_world :: proc(state: ^Frame_State, session: ^Session) {
	content := state.content
	world := &session.simulation.world
	tick_rate := session.simulation.tick_rate
	player := session.simulation.players[0]
	alpha := f32(interpolation_alpha(session.accumulator))
	camera := fly_camera_to_raylib(player_view_camera(world, content.blocks, player, alpha))
	rl.BeginMode3D(camera)
	defer rl.EndMode3D()
	draw_chunks(&state.renderer, camera)
	draw_entities(world, content.machines, content.items, tick_rate)
	if state.settings.bottleneck_overlay {
		draw_machine_markers(world, content.machines, camera.position)
	}
	draw_fluid_entities(world, content.machines, content.fluids)
	draw_power_entities(world, content.machines)
	draw_belts(&state.belt_renderer, world, content.items, content.machines, session.simulation.tick, alpha, tick_rate)
	draw_player_world_overlay(world, frame_simulation_content(state), session.simulation.players[:], 0, alpha)
}

// The context every screen gets. Without a session the world fields stay
// empty; only the title screens and settings run then.
make_screen_context :: proc(state: ^Frame_State) -> Screen_Context {
	content := state.content
	screen_context := Screen_Context {
		settings        = &state.settings,
		font_families   = state.fonts.families,
		screenshot_requested = &state.screenshot_requested,
		bindings        = state.bindings,
		quit_requested  = &state.quit_requested,
		title           = &state.title,
		items           = content.items,
		blocks          = content.blocks,
		item_sort_ranks = content.item_sort_ranks,
		machines        = content.machines,
		fluids          = content.fluids,
		veins           = content.veins,
		tick_rate       = state.config.tick_rate,
		recipes         = content.recipes,
		technologies    = content.technologies,
		quests          = content.quests,
		contracts       = content.contracts,
		recipe_names    = content.recipe_names,
		recipe_order    = content.recipe_order,
		developer_mode  = content.developer_mode,
		show_diagnostics = &state.show_diagnostics,
		show_world_overlay = &state.show_world_overlay,
		developer_chapter_count = len(content.developer_kits.kits),
	}
	session := state.session
	if session == nil {
		return screen_context
	}
	screen_context.save_requested = &session.save_requested
	screen_context.player = &session.simulation.players[0]
	screen_context.world = &session.simulation.world
	screen_context.tick = session.simulation.tick
	screen_context.tick_rate = session.simulation.tick_rate
	screen_context.technologies = session.technologies
	screen_context.unlocks = &session.simulation.unlocks
	screen_context.recipes = with_schematics_found(content.recipes, session.simulation.unlocks.schematics_found)
	screen_context.quest_state = &session.simulation.quests
	screen_context.browser = &session.recipe_browser
	screen_context.technology_browser = &session.technology_browser
	screen_context.statistics_view = &session.statistics_view
	screen_context.map_view = &session.map_view
	screen_context.developer_requests = &session.simulation.developer_requests
	screen_context.cheat_speed = session.simulation.cheat_speed
	screen_context.landing_pad = session.start.landing_pad
	screen_context.reload_requested = &state.reload_requested
	screen_context.data_changed = state.data_watch.content_changed
	return screen_context
}

run_ui_frame :: proc(state: ^Frame_State) {
	screen_pixels := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	input := make_ui_input(state.previous_input, state.input)
	ui_begin(&state.ui, input, screen_pixels, state.frame_seconds, state.settings.ui_scale, state.settings.pointer_speed)
	sync_font_cache(&state.font_cache, state.settings, state.ui.pixels_per_unit)
	screen_context := make_screen_context(state)
	if state.session != nil {
		show_simulation_events(&state.ui, &state.session.simulation.events)
		show_quest_notices(&state.ui, &state.session.simulation.quests.notices, state.session.simulation.world.shipments[:], state.content.items)
		draw_hud(&state.ui, screen_context)
	}
	run_screens(&state.ui, screen_context)
	ui_end(&state.ui, Icon_Atlas{texture = chunk_atlas_texture(state.renderer), layout = state.renderer.atlas_layout}, &state.ui_images)
	apply_cursor_mode(state)
}

show_simulation_events :: proc(state: ^Ui_State, events: ^[dynamic]Simulation_Event) {
	for event in events {
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
		}
	}
	clear(events)
}

// Mission Control's lines, finished research and the capsule landing, as
// toasts.
show_quest_notices :: proc(state: ^Ui_State, notices: ^[dynamic]Quest_Message, shipments: []Shipment, items: Item_Registry) {
	for notice in notices {
		ui_toast(state, quest_message_text(notice, shipments, items))
	}
	clear(notices)
}

Game_Content :: struct {
	blocks:          Block_Registry,
	items:           Item_Registry,
	machines:        Machine_Registry,
	fluids:          Fluid_Registry,
	recipes:         Recipe_Registry,
	technologies:    Technology_Registry,
	quests:          Quest_Registry,
	veins:           Vein_Content,
	contracts:       Contract_Registry,
	developer_kits:  Developer_Kits,
	item_sort_ranks: []u16,
	recipe_names:    []string,
	recipe_order:    []int,
	unlock_all:      bool,
	// --dev: the pause menu shows the Developer entry.
	developer_mode:  bool,
}

game_simulation_content :: proc(content: Game_Content) -> Simulation_Content {
	return Simulation_Content {
		blocks = content.blocks,
		items = content.items,
		machines = content.machines,
		fluids = content.fluids,
		recipes = content.recipes,
		technologies = content.technologies,
		quests = content.quests,
		veins = content.veins,
		contracts = content.contracts,
		developer_kits = content.developer_kits,
	}
}

// Between frames: starts, loads or leaves a world as the menus asked. A
// world that cannot be made or loaded leaves the title showing with a
// toast.
apply_session_request :: proc(state: ^Frame_State) {
	request := state.title.request
	state.title.request = {}
	switch request.kind {
	case .None:
	case .New_World:
		setup := &state.title.setup
		seed, _ := world_setup_seed(setup)
		plan := new_world_plan(strings.trim_space(text_field_text(&setup.name)), seed, world_file_settings_from_setup(setup^), state.title.saves_directory, state.title.saves_found, false)
		enter_planned_session(state, plan)
	case .Load:
		plan, problem := saved_world_plan(state.title.saves_directory, request.directory_name)
		if problem != "" {
			report_session_problem(state, problem)
			return
		}
		enter_planned_session(state, plan)
	case .Quit_To_Title:
		leave_session(state)
		show_title(state)
	}
}

report_session_problem :: proc(state: ^Frame_State, problem: string) {
	log_printf("error: %s", problem)
	ui_toast(&state.ui, fmt.tprintf("%s: %s", text("title_world_failed"), problem))
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
	state.session = session
	state.ui.screens = {}
	state.ui.keyboard = {}
	state.ui.tooltip_open = false
}

// Saves first when the world saves.
leave_session :: proc(state: ^Frame_State) {
	session := state.session
	if session == nil {
		return
	}
	if session.save.enabled && save_session(session, state.content) == "" {
		log_printf("world: saved %q", session.save.location.display_name)
	}
	unload_all_chunk_meshes(&state.renderer)
	end_session(session)
	state.session = nil
	state.show_diagnostics = false
	state.show_world_overlay = false
	// A pause command holds only the world it was given in.
	state.command_control.paused = false
}

// Once the settings screen is closed (and on exit), changed settings go to
// config.d/90-settings.sjson. A failed write is reported once, not retried.
write_changed_settings :: proc(state: ^Frame_State) {
	if state.settings == state.stored_settings {
		return
	}
	state.stored_settings = state.settings
	if problem := write_settings_file(state.environment, state.settings); problem != "" {
		log_printf("error: cannot save the settings: %s", problem)
	}
}

show_title :: proc(state: ^Frame_State) {
	state.ui.screens = {}
	state.ui.keyboard = {}
	push_screen(&state.ui.screens, .Title)
	refresh_title_saves(&state.title)
}

// Takes ownership of the session, or shows the title when there is none.
// Saves on quit when the world saves.
run_game :: proc(config: Game_Config, input_backend: Input_Backend, game_data: Game_Data, data_directory: string, fonts: Loaded_Fonts, session: ^Session, title: Title_State, player_configuration: Player_Configuration) {
	content := game_data.content
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Mine oh Belowed")
	// raylib returns from a failed InitWindow instead of reporting it, and
	// the first draw call would then crash. A missing display is the usual cause.
	if !rl.IsWindowReady() {
		log_printf("error: could not open a window (is a display available?)")
		os.exit(1)
	}
	defer rl.CloseWindow()
	// Escape is bound to the Pause action, so it must not close the window.
	rl.SetExitKey(.KEY_NULL)

	renderer, renderer_ok := init_chunk_renderer(content.blocks, data_directory)
	if !renderer_ok {
		os.exit(1)
	}
	state := Frame_State {
		config          = config,
		content         = content,
		base_generator  = game_data.base_generator,
		content_arena   = game_data.arena,
		data_directory  = data_directory,
		watch_data_flag = player_configuration.watch_data,
		binding_overrides = player_configuration.binding_overrides,
		title           = title,
		input_backend   = input_backend,
		renderer        = renderer,
		settings        = player_configuration.settings,
		stored_settings = player_configuration.settings,
		environment     = player_configuration.environment,
		bindings        = player_configuration.bindings,
		input_bindings  = player_configuration.input_bindings,
		fonts           = fonts,
		// raylib starts with the cursor shown; the first apply hides it.
		cursor_enabled  = true,
	}
	// After the session left, which saves with the content.
	defer destroy_hot_reload_state(&state)
	defer destroy_ui_state(&state.ui)
	defer release_ui_images(&state.ui_images)
	strings_text, _ := read_strings_file(data_directory)
	init_font_cache(&state.font_cache, data_directory, state.fonts.families, string(strings_text), state.settings)
	state.ui.fonts, state.ui.measure_text = &state.font_cache, measure_font_text
	defer destroy_font_cache(&state.font_cache)
	defer destroy_title_state(&state.title)
	defer write_changed_settings(&state)
	defer if input_backend == .Sdl3 {
		shutdown_sdl3_input(&state.sdl3_input)
	}
	defer destroy_chunk_renderer(&state.renderer)
	state.belt_renderer = init_belt_renderer(content.machines)
	defer destroy_belt_renderer(&state.belt_renderer)
	start_command_frame_state(&state)
	defer destroy_command_frame_state(&state)
	if session != nil {
		enter_session(&state, session)
	} else {
		show_title(&state)
	}
	defer leave_session(&state)
	apply_cursor_mode(&state)
	for !rl.WindowShouldClose() && !state.quit_requested {
		update_frame(&state)
		render_frame(&state)
		apply_session_request(&state)
		update_data_watch(&state)
		apply_reload_request(&state)
		if !screen_stack_contains(state.ui.screens, .Settings) {
			write_changed_settings(&state)
		}
		free_all(context.temp_allocator)
	}
}

// Command socket (work item 0053, command_socket.odin, command.odin).

start_command_frame_state :: proc(state: ^Frame_State) {
	state.command_server = make_command_server()
	runtime_directory := os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
	state_home := os.get_env("XDG_STATE_HOME", context.temp_allocator)
	home := os.get_env("HOME", context.temp_allocator)
	state.command_socket_path, _ = command_socket_path_from_environment(runtime_directory, state_home, home)
	state.screenshot_directory, _ = screenshot_directory_from_environment(state_home, home)
}

destroy_command_frame_state :: proc(state: ^Frame_State) {
	destroy_command_server(&state.command_server)
	delete(state.command_socket_path)
	delete(state.screenshot_directory)
	delete(state.command_control.screenshot_path)
}

// Listens while developer mode is on (--dev or the setting), and stops
// when the setting is switched off. A failure to listen is logged once.
update_command_server_open :: proc(state: ^Frame_State) {
	server := &state.command_server
	wanted := state.content.developer_mode || state.settings.developer_mode
	switch {
	case wanted && server.listening == -1 && !server.open_failed:
		problem := state.command_socket_path == "" ? "no directory for it (set XDG_RUNTIME_DIR, XDG_STATE_HOME or HOME)" : open_command_server(server, state.command_socket_path)
		if problem != "" {
			log_printf("error: command socket: %s", problem)
			server.open_failed = true
		} else {
			log_printf("command: listening on %s", server.path)
		}
	case !wanted && server.listening != -1:
		close_command_server(server)
		log_printf("command: socket closed")
	case !wanted:
		server.open_failed = false
	}
}

// After the frame's ticks: answers a tick command whose ticks ran, then
// executes the queued lines in order until one starts a tick command.
serve_command_socket :: proc(state: ^Frame_State) {
	update_command_server_open(state)
	server := &state.command_server
	if server.listening == -1 {
		return
	}
	poll_command_server(server)
	answer_command_ticks(state)
	for !state.command_control.ticks_waiting {
		queued := take_command_line(server) or_break
		execute_queued_command(state, queued)
		delete(queued.line)
	}
	flush_command_server(server)
}

answer_command_ticks :: proc(state: ^Frame_State) {
	control := &state.command_control
	if control.ticks_waiting && state.session == nil {
		control.pending_ticks, control.ticks_waiting = 0, false
		send_logged_response(state, state.command_server.tick_client, "tick", command_error("the world was closed"))
		state.command_server.tick_client = 0
		return
	}
	if state.session == nil {
		return
	}
	if response, finished := finish_command_ticks(control, state.session.simulation.tick); finished {
		send_logged_response(state, state.command_server.tick_client, "tick", response)
		state.command_server.tick_client = 0
	}
}

send_logged_response :: proc(state: ^Frame_State, client: u64, line: string, response: Command_Response) {
	text := format_command_response(response)
	log_command_exchange(line, text)
	send_command_response(&state.command_server, client, text)
}

frame_command_context :: proc(state: ^Frame_State) -> Command_Context {
	command_context := Command_Context {
		content              = game_simulation_content(state.content),
		control              = &state.command_control,
		screenshot_directory = state.screenshot_directory,
		now                  = time.now(),
	}
	if state.session != nil {
		command_context.simulation = &state.session.simulation
		command_context.content = frame_simulation_content(state)
	}
	return command_context
}

// save and reload need the session and the game content, the rest runs
// in command.odin. A tick command answers later (answer_command_ticks).
execute_queued_command :: proc(state: ^Frame_State, queued: Queued_Command_Line) {
	words, _ := split_command_words(queued.line)
	response: Command_Response
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
		log_printf("command: %s", queued.line)
		state.command_server.tick_client = queued.client
		return
	}
	send_logged_response(state, queued.client, queued.line, response)
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
run_command_ticks :: proc(state: ^Frame_State) -> int {
	start := time.tick_now()
	content := frame_simulation_content(state)
	count := 0
	for state.command_control.pending_ticks > 0 && time.tick_since(start) < COMMAND_TICK_WALL_BUDGET {
		run_command_tick(&state.session.simulation, content, &state.command_control)
		count += 1
	}
	return count
}

// The Developer screen's button, queued like the screenshot command.
queue_requested_screenshot :: proc(state: ^Frame_State) {
	if !state.screenshot_requested {
		return
	}
	state.screenshot_requested = false
	path, problem := queue_screenshot(&state.command_control, state.screenshot_directory, "", time.now())
	if problem != "" {
		log_printf("error: screenshot: %s", problem)
		ui_toast(&state.ui, fmt.tprintf("%s: %s", text("developer_screenshot_failed"), problem))
		return
	}
	ui_toast(&state.ui, fmt.tprintf("%s %s", text("developer_screenshot_saved"), path))
}

// At the end of the frame, before EndDrawing shows it: the drawn frame
// read back and written as PNG. ExportImage takes the absolute path as
// given (TakeScreenshot would put the file in the working directory).
capture_pending_screenshot :: proc(state: ^Frame_State) {
	path := state.command_control.screenshot_path
	if path == "" {
		return
	}
	state.command_control.screenshot_path = ""
	defer delete(path)
	rlgl.DrawRenderBatchActive()
	image := rl.LoadImageFromScreen()
	defer rl.UnloadImage(image)
	if rl.ExportImage(image, strings.clone_to_cstring(path, context.temp_allocator)) {
		log_printf("command: screenshot %s", path)
	} else {
		log_printf("error: screenshot: cannot write %s", path)
	}
}
