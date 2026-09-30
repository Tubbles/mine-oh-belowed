package game

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"
import rl "shared:raylib"
import rlgl "shared:raylib/rlgl"

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
	// The HUD's biome banner, rendering state across frames.
	biome_banner:       Biome_Banner,
	title:              Title_State,
	input_backend:      Input_Backend,
	sdl3_input:         Sdl3_Input_State,
	input:              Input_Frame,
	// The touch overlay's fingers (touch_overlay.odin), and --touch-overlay.
	touch_overlay:        Touch_Overlay_State,
	touch_overlay_forced: bool,
	// The rumble for this frame, applied by the SDL3 backend or, on
	// Android, by the raylib backend through the phone's vibrator.
	haptic:             Haptic_Request,
	vibrator:           Vibrator_State,
	previous_input:     Input_Frame,
	frame_seconds:      f32,
	// The sprint field of view kick's progress, 0 to 1 (advance_sprint_kick).
	sprint_kick:        f32,
	// The camera the world was last drawn with: the touch overlay's aim
	// ray (touch_aim_direction) and the HUD's mining ring.
	render_camera:      rl.Camera3D,
	// The Render page's frame time average and the ticks update_session
	// ran this frame (work item 0086).
	frame_times:        Frame_Time_Ring,
	frame_tick_count:   int,
	// World actions still held since a screen closed, see update_world_action_guard.
	world_action_guard: Action_Set,
	settings:           Settings,
	// The settings as last read or written, see write_changed_settings.
	stored_settings:    Settings,
	// The settings as last applied to the window (display.odin), and the
	// monitor's size read while the window was still windowed.
	window_settings:    Settings,
	monitor_size:       [2]int,
	// The window's scale, read every frame, and the windowing platform GLFW
	// took (display.odin, work items 0084 and 0085).
	window_scale:       [2]f32,
	platform:           Window_Platform,
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
	// The item icons (render_icons.odin), rebuilt with the block atlas;
	// content.items.icon_loaded points into it.
	item_atlas:         Item_Atlas,
	// The UI icons (render_icons.odin, work item 0071), rebuilt with the
	// theme.
	ui_icon_atlas:      Item_Atlas,
	belt_renderer:      Belt_Renderer,
	model_renderer:     Model_Renderer,
	// Particles and feedback (work item 0067, render_particles.odin):
	// render state only, advanced by the frame time, reset with the
	// session.
	particles:          Particle_System,
	particle_memory:    Particle_Memory,
	particle_renderer:  Particle_Renderer,
	// The player's body and arm (work item 0066, render_player_model.odin)
	// and what its animation remembers of the last frame, reset with the
	// session.
	player_model:       Player_Model,
	player_animation:   Player_Animation_Memory,
	// Sound (work item 0068, audio.odin, sound_events.odin): the mixer
	// for the whole run, and what the sound triggers remember of the last
	// frame, reset with the session.
	audio:              Audio_Mixer,
	sound_memory:       Sound_Memory,
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
	// The texture editor's entries (work item 0100, ui_texture_editor.odin),
	// read at start and served by serve_texture_editor.
	texture_editor:       Texture_Editor,
	// The user touch layouts (0121, touch_overlay.odin), read at start and
	// written by serve_touch_layouts, and the layout editor's draft
	// (ui_touch_layout_editor.odin).
	touch_layouts:        Touch_Layouts,
	touch_layout_editor:  Touch_Layout_Editor,
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
	state.world.entities.loose_items.despawn_ticks = loose_item_despawn_ticks(config.loose_item_despawn_minutes, config.tick_rate)
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
// (recipe_runs_in_machines). A profile (tick_profile.odin) gets the wall
// time of each step.
simulation_tick :: proc(state: ^Simulation_State, content_tables: Simulation_Content, inputs: []Input_Frame, profile: ^Tick_Profile = nil) {
	clock := profile_now(profile)
	content := content_tables
	content.recipes = with_schematics_found(content.recipes, state.unlocks.schematics_found)
	clock = profile_section(profile, .Unlocks, clock)
	state.tick += 1
	advance_statistics_clock(&state.world.statistics, state.tick, state.tick_rate)
	clock = profile_section(profile, .Statistics, clock)
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
	clock = profile_section(profile, .Players, clock)
	newly_obtained := update_recipe_unlocks(&state.unlocks, content.recipes, state.players[:])
	log_discoveries(&state.quests, content.blocks, content.items, newly_obtained, state.tick)
	clock = profile_section(profile, .Unlocks, clock)
	tick_entities(&state.world, content, state.tick_rate, profile)
	clock = profile_now(profile)
	shipments_before := len(state.world.shipments)
	apply_launch_requests(&state.world, state.tick)
	clock = profile_section(profile, .Launch_Pads, clock)
	tick_venture(state, content, shipments_before)
	clock = profile_section(profile, .Venture, clock)
	apply_research_result(state, content)
	clock = profile_section(profile, .Research, clock)
	observe_player_holdings(&state.world.statistics, state.players[:], true)
	observe_full_inventories(&state.world.statistics, state.players[:])
	clock = profile_section(profile, .Statistics, clock)
	tick_quests(&state.quests, simulation_quest_context(state, content), &state.world.entities)
	clock = profile_section(profile, .Quests, clock)
	tick_world(&state.world, content.blocks, state.tick, simulation_tree_felling(content))
	profile_section(profile, .World, clock)
	if profile != nil {
		profile.ticks += 1
	}
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
	overlay := read_touch_overlay_frame(state)
	frame: Input_Frame
	switch state.input_backend {
	case .Sdl3:
		frame = read_sdl3_input_frame(&state.sdl3_input, state.input, frame_seconds, state.settings, state.input_bindings, overlay)
	case .Raylib:
		frame = read_raylib_input_frame(state.input.pressed, state.input_bindings, overlay)
	}
	return apply_touch_overlay_hotbar(apply_touch_overlay_aim(frame, overlay), overlay)
}

// The mouse steers the view while the world is shown and is free for the
// diagnostics screen and the menus. With the touch overlay on it stays
// free, since on the desktop the mouse is the overlay's touch point.
apply_cursor_mode :: proc(state: ^Frame_State) {
	wanted := state.diagnostics_page != .Off || state.ui.screens.count > 0 || touch_overlay_on(state)
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
	if .Toggle_Diagnostics in state.input.just_pressed {
		state.diagnostics_page = next_diagnostics_page(state.diagnostics_page)
	}
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
	state.frame_times = push_frame_time(state.frame_times, state.frame_seconds)
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
	switch state.input_backend {
	case .Sdl3:
		apply_sdl3_haptics(&state.sdl3_input, state.haptic)
	case .Raylib:
		apply_vibrator_haptics(&state.vibrator, state.haptic)
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
	frame_for_world := world_input(state.input, world_blocked, state.world_action_guard, state.settings, developer_mode_on(state))
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
	state.frame_tick_count = tick_count
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

render_frame :: proc(state: ^Frame_State) {
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
	upload_streamed_meshes(&state.renderer, &session.streaming)
	weather := session_weather(session, state.settings.weather)
	sky := weathered_day_sky(day_sky(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks), weather)
	apply_daylight(&state.renderer, sky)
	rl.BeginDrawing()
	defer rl.EndDrawing()
	// The horizon colour, which is the fog colour: the dome covers the
	// upper hemisphere alone, so the clear colour shows below the horizon.
	rl.ClearBackground(sky.colors.horizon)
	counts := draw_session_world(state, session, sky, weather)
	counts.uploaded_meshes = pending_before_upload - session.streaming.pending_jobs
	begin_render_pixel_drawing()
	if counts.underwater {
		draw_underwater_overlay()
	}
	play_frame_sounds(&state.audio, &state.sound_memory, session_sound_frame(state, weather))
	switch state.diagnostics_page {
	case .Off:
		if state.show_world_overlay {
			draw_world_overlay(state^)
		}
	case .Input:
		draw_diagnostics_page(state^, state.config, {}, {})
	case .Render:
		draw_diagnostics_page(state^, state.config, render_facts(state, sky, weather, counts), {})
	case .World:
		draw_diagnostics_page(state^, state.config, {}, world_facts(state))
	}
	run_ui_frame(state)
	queue_requested_screenshot(state)
	capture_pending_screenshot(state)
}

session_sound_frame :: proc(state: ^Frame_State, weather: Weather) -> Sound_Frame {
	session := state.session
	return Sound_Frame {
		world = &session.simulation.world,
		content = frame_simulation_content(state),
		generator = &session.generator,
		player = session.simulation.players[0],
		tick = session.simulation.tick,
		quests = &session.simulation.quests,
		particle_memory = state.particle_memory,
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
		window_mode = state.window_settings.window_mode,
		monitor_size = state.monitor_size,
		window_size = {int(rl.GetScreenWidth()), int(rl.GetScreenHeight())},
		render_size = {int(rl.GetRenderWidth()), int(rl.GetRenderHeight())},
		window_scale = state.window_scale,
		platform = state.platform,
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
		drawn_chunk_count = state.renderer.drawn_chunk_count,
		vertex_count = state.renderer.vertex_count,
		uploaded_mesh_count = counts.uploaded_meshes,
		pending_job_count = session.streaming.pending_jobs,
		drawn_water_mesh_count = counts.water_meshes,
		live_particle_count = live_particle_count(&state.particles),
		weather_particle_count = counts.weather_particles,
		flame_count = flame_count(state.renderer),
		block_atlas_size = texture_size(chunk_atlas_texture(state.renderer)),
		item_atlas_size = texture_size(state.item_atlas.texture),
		ui_atlas_size = texture_size(state.ui_icon_atlas.texture),
		underwater = counts.underwater,
	}
}

// The World page's facts (diagnostics.odin).
world_facts :: proc(state: ^Frame_State) -> World_Facts {
	session := state.session
	world := &session.simulation.world
	cell := camera_world_coordinate(session.simulation.players[0].position)
	biome := sample_column(&session.generator, cell.x, cell.z).biome
	biome_name := biome < len(session.generator.biomes) ? text(session.generator.biomes[biome].definition.name_key) : "?"
	return World_Facts {
		overlay_lines = world_overlay_statistics_lines(state^),
		tick = session.simulation.tick,
		player_chunk = world_to_chunk_coordinate(cell),
		biome_name = biome_name,
		entity_counts = entity_counts(&world.entities),
		loose_item_count = len(world.entities.loose_items.items),
		belt_line_count = len(world.entities.belt_network.lines),
		belt_item_count = belt_item_count(world.entities.belt_network),
		leaf_decay_count = len(world.leaf_decay.updates),
	}
}

draw_session_world :: proc(state: ^Frame_State, session: ^Session, sky: Day_Sky, weather: Weather) -> (counts: Frame_Render_Counts) {
	content := state.content
	world := &session.simulation.world
	tick_rate := session.simulation.tick_rate
	player := session.simulation.players[0]
	alpha := f32(interpolation_alpha(session.accumulator))
	seconds := rl.GetTime()
	update_player_presence(&state.player_animation, &state.particles, state.particle_memory, world, content.blocks, player, session.simulation.tick, seconds, session.simulation.cheat_speed)
	pose := interpolate_player_pose(player, alpha)
	animation := player_animation_state(state.player_animation, player, pose.pitch, seconds)
	bob := head_bob_offset(animation.walk_phase, head_bob_amplitude(animation.moving, animation.sprinting, head_bob_enabled(state.settings)))
	view := player_view_camera(world, content.blocks, player, alpha, bob, state.settings)
	state.sprint_kick = advance_sprint_kick(state.sprint_kick, animation.moving && player_sprints(player, state.input.pressed), state.frame_seconds)
	camera := fly_camera_to_raylib(view, sprint_field_of_view(state.settings.field_of_view, sprint_kick_degrees(state.settings), state.sprint_kick))
	state.render_camera = camera
	still_seconds := flicker_seconds(seconds, state.settings.reduced_motion)
	look := weather_look(weather, weather_motion_enabled(state.settings), sky.blend)
	apply_weather(&state.renderer, look, still_seconds)
	counts.underwater = camera_underwater(world, content.blocks, camera.position)
	if counts.underwater {
		apply_fog(&state.renderer, underwater_fog())
	}
	rl.BeginMode3D(camera)
	draw_sky(&state.renderer.sky, camera, sky, state.particle_memory.satellite)
	draw_chunks(&state.renderer, camera)
	frame := Model_Frame{world = world, tick = session.simulation.tick, alpha = alpha, tick_rate = tick_rate, day_factor = day_factor(sky.blend), sky_tint = color_to_vector3(sky.colors.sun_tint)}
	draw_entities(world, content.machines, state.model_renderer, content.items, frame)
	if state.settings.bottleneck_overlay {
		draw_machine_markers(world, content.machines, state.model_renderer, camera.position, bottleneck_marker_colors(ui_theme(&state.ui), state.settings.palette))
	}
	draw_fluid_entities(world, content.machines, state.model_renderer, content.fluids, frame)
	draw_power_entities(world, content.machines, state.model_renderer, frame)
	draw_belts(&state.belt_renderer, world, content.items, content.machines, state.model_renderer, frame, Item_Billboards{camera = camera, atlas = state.item_atlas})
	draw_loose_items(world, content.items, frame, Item_Billboards{camera = camera, atlas = state.item_atlas})
	draw_torch_flames(&state.renderer, camera, still_seconds)
	life := session_life_frame(session, camera, sky, weather, look, alpha, seconds)
	draw_fish_shadows(&state.renderer, life)
	draw_water_chunks(&state.renderer, camera, seconds)
	draw_bird_flocks(&session.generator, life)
	draw_insect_motes(&state.renderer, session.generator.biomes, life)
	if state.diagnostics_page == .Render {
		counts.water_meshes = water_meshes_in_view(state.renderer, camera)
	}
	update_particles(&state.particles, &state.particle_memory, world, frame_simulation_content(state), state.model_renderer, session.simulation.players[:], tick_rate, state.frame_seconds)
	update_satellite_pass(&state.particle_memory, session.simulation.quests.messages[:], state.frame_seconds)
	draw_particles(&state.particle_renderer, camera, &state.particles, state.particle_memory, world, state.model_renderer, color_to_vector3(sky.colors.sun_tint) * day_factor(sky.blend))
	if weather_motion_enabled(state.settings) {
		counts.weather_particles = draw_session_weather(session, camera, weather, sky, seconds)
	}
	body := Player_Body_Draw{renderer = state.model_renderer, model = state.player_model, animation = animation, light = player_body_light(frame, player_eye(pose.position))}
	draw_player_world_overlay(world, frame_simulation_content(state), state.model_renderer, &state.belt_renderer, session.simulation.players[:], 0, alpha, body)
	rl.EndMode3D()
	if player.camera_mode == .First_Person {
		draw_first_person_hands(view, body, Item_Billboards{camera = camera, atlas = state.item_atlas}, Held_Block_Tiles{texture = chunk_atlas_texture(state.renderer), layout = state.renderer.atlas_layout, blocks = content.blocks}, content.items, selected_hotbar_stack(player))
	}
	return counts
}

// The mined block's centre in render pixels, through the camera the world
// was drawn with this frame (the HUD draws after the world).
mining_ring_centre :: proc(state: ^Frame_State, mining: Mining_State) -> [2]f32 {
	if !mining.active {
		return {}
	}
	size := render_size()
	return rl.GetWorldToScreenEx(block_centre(mining.block), state.render_camera, i32(size.x), i32(size.y))
}

// The context every screen gets. Without a session the world fields stay
// empty; only the title screens and settings run then.
make_screen_context :: proc(state: ^Frame_State) -> Screen_Context {
	content := state.content
	screen_context := Screen_Context {
		settings        = &state.settings,
		monitor_size    = state.monitor_size,
		platform        = state.platform,
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
		notes           = content.notes,
		recipe_names    = content.recipe_names,
		recipe_order    = content.recipe_order,
		developer_mode  = content.developer_mode,
		diagnostics_page = &state.diagnostics_page,
		show_world_overlay = &state.show_world_overlay,
		developer_chapter_count = len(content.developer_kits.kits),
		texture_editor  = &state.texture_editor,
		touch_layouts   = &state.touch_layouts,
		touch_layout_editor = &state.touch_layout_editor,
		default_touch_layout = content.touch_overlay,
	}
	session := state.session
	if session == nil {
		return screen_context
	}
	screen_context.save_requested = &session.save_requested
	screen_context.touch_aims = touch_overlay_aims(state)
	screen_context.mining_ring_centre = mining_ring_centre(state, session.simulation.players[0].mining)
	screen_context.discovery_card_clearance = discovery_card_clearance(state)
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
	screen_context.generator = &session.generator
	screen_context.biome_banner = &state.biome_banner
	screen_context.developer_requests = &session.simulation.developer_requests
	screen_context.cheat_speed = session.simulation.cheat_speed
	screen_context.landing_pad = session.start.landing_pad
	screen_context.particle_memory = &state.particle_memory
	screen_context.reload_requested = &state.reload_requested
	screen_context.data_changed = state.data_watch.content_changed
	return screen_context
}

run_ui_frame :: proc(state: ^Frame_State) {
	// Render pixels (work item 0085): with the high DPI flag the UI follows
	// the panel's pixels and its text rasterises at their size.
	screen_pixels := [2]f32{f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
	input := make_ui_input(state.previous_input, state.input)
	ui_begin(&state.ui, input, screen_pixels, state.frame_seconds, state.settings.ui_scale, state.settings.pointer_speed, ui_accessibility(state.settings))
	sync_font_cache(&state.font_cache, state.settings, state.ui.pixels_per_unit)
	screen_context := make_screen_context(state)
	if state.session != nil {
		show_simulation_events(&state.ui, &state.session.simulation.events)
		show_quest_notices(&state.ui, &state.session.simulation.quests.notices, state.session.simulation.world.shipments[:], state.content.items)
		draw_hud(&state.ui, screen_context)
	}
	run_screens(&state.ui, screen_context)
	// After the screens, so Start and Back show over an open one.
	if state.session != nil && touch_overlay_on(state) && !touch_layout_editor_shown(state.ui.screens) {
		draw_touch_overlay(&state.ui, state.touch_overlay, frame_touch_layout(state), screen_pixels, !ui_blocks_world(state.ui.screens))
	}
	icon_atlas := Icon_Atlas {
		texture      = chunk_atlas_texture(state.renderer),
		layout       = state.renderer.atlas_layout,
		item_texture = state.item_atlas.texture,
		item_layout  = state.item_atlas.layout,
		ui_texture   = state.ui_icon_atlas.texture,
		ui_layout    = state.ui_icon_atlas.layout,
	}
	ui_end(&state.ui, icon_atlas, &state.ui_images)
	play_ui_sounds(&state.audio, &state.ui)
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

// Mission Control's lines to its panel, a discovery to its card, the
// rest (finished research, the capsule landing, the venture's notes) as
// toasts (work item 0069).
show_quest_notices :: proc(state: ^Ui_State, notices: ^[dynamic]Quest_Message, shipments: []Shipment, items: Item_Registry) {
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
	// The journal's Notes tab (notes.odin); presentation only, so the
	// simulation never sees it.
	notes:           Note_Registry,
	developer_kits:  Developer_Kits,
	// The touch overlay's layout (touch_overlay.odin); presentation only.
	touch_overlay:   Touch_Overlay_Layout,
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
	state.particles = {}
	state.particle_memory = {}
	state.player_animation = {}
	state.sound_memory = {}
	clear_mission_control(&state.ui.mission_control)
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
	state.diagnostics_page = .Off
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
		log_printf("error: could not open a window (is a display available?)")
		os.exit(1)
	}
	defer rl.CloseWindow()
	// Escape is bound to the Pause action, so it must not close the window.
	rl.SetExitKey(.KEY_NULL)
	monitor_size := current_monitor_size()
	platform := current_window_platform()
	log_display_diagnostics(platform)
	log_gl_info()
	update_display(&window_settings, player_configuration.settings, monitor_size, platform)

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
		touch_overlay_forced = player_configuration.touch_overlay_forced,
		title           = title,
		input_backend   = input_backend,
		renderer        = renderer,
		settings        = player_configuration.settings,
		stored_settings = player_configuration.settings,
		window_settings = window_settings,
		monitor_size    = monitor_size,
		window_scale    = window_scale(),
		platform        = platform,
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
	theme, theme_problem := load_ui_theme(data_directory)
	if theme_problem != "" {
		log_printf("error: %s", theme_problem)
		os.exit(1)
	}
	apply_ui_theme(&state.ui, theme)
	state.ui_icon_atlas = upload_ui_icon_atlas(data_directory)
	defer destroy_item_atlas(&state.ui_icon_atlas)
	defer destroy_title_state(&state.title)
	defer write_changed_settings(&state)
	defer if input_backend == .Sdl3 {
		shutdown_sdl3_input(&state.sdl3_input)
	}
	state.vibrator = start_vibrator()
	defer stop_vibrator(&state.vibrator)
	defer destroy_chunk_renderer(&state.renderer)
	state.item_atlas = upload_item_atlas(&state.content.items, data_directory)
	defer destroy_item_atlas(&state.item_atlas)
	state.belt_renderer = init_belt_renderer(content.machines)
	defer destroy_belt_renderer(&state.belt_renderer)
	state.model_renderer = init_model_renderer(content.machines, data_directory)
	defer destroy_model_renderer(&state.model_renderer)
	state.particle_renderer = init_particle_renderer()
	defer destroy_particle_renderer(&state.particle_renderer)
	state.player_model = init_player_model(data_directory)
	defer unload_player_model(&state.player_model)
	state.audio = init_audio(data_directory, content.blocks, game_data.base_generator.biomes, state.settings)
	defer shutdown_audio(&state.audio)
	start_command_frame_state(&state)
	defer destroy_command_frame_state(&state)
	load_texture_editor(&state.texture_editor, data_directory, texture_edits_path(), state.content.blocks)
	defer destroy_texture_editor(&state.texture_editor)
	touch_layouts_problem: string
	if state.touch_layouts, touch_layouts_problem = load_touch_layouts(state.environment); touch_layouts_problem != "" {
		ui_toast(&state.ui, touch_layouts_locked_text(state.touch_layouts))
	}
	defer destroy_touch_layouts(&state.touch_layouts)
	defer destroy_touch_layout_editor(&state.touch_layout_editor)
	if session != nil {
		enter_session(&state, session)
	} else {
		show_title(&state)
	}
	defer leave_session(&state)
	apply_cursor_mode(&state)
	for !rl.WindowShouldClose() && !state.quit_requested {
		update_frame(&state)
		serve_texture_editor(&state)
		serve_touch_layouts(&state)
		render_frame(&state)
		update_audio(&state.audio, state.settings, state.frame_seconds)
		apply_session_request(&state)
		update_data_watch(&state)
		apply_reload_request(&state)
		// Applied at once, like the font choice.
		update_display(&state.window_settings, state.settings, state.monitor_size, state.platform)
		state.window_scale = window_scale()
		if !screen_stack_contains(state.ui.screens, .Settings) {
			write_changed_settings(&state)
		}
		free_all(context.temp_allocator)
	}
}

// Command socket (work item 0053, command_socket.odin, command.odin).

start_command_frame_state :: proc(state: ^Frame_State) {
	state.command_server = make_command_server()
	directories := platform_directories(context.temp_allocator)
	state.command_socket_path, _ = command_socket_path_from_environment(directories.runtime_directory, directories.state_home, directories.home)
	state.screenshot_directory, _ = screenshot_directory_from_environment(directories.state_home, directories.home)
}

destroy_command_frame_state :: proc(state: ^Frame_State) {
	destroy_command_server(&state.command_server)
	delete(state.command_socket_path)
	delete(state.screenshot_directory)
	delete(state.command_control.screenshot_path)
}

// Listens while developer mode is on (--dev or the setting), and stops
// when the setting is switched off. A failure to listen is logged once.
// Does nothing where there is no command socket (Windows, 0108).
update_command_server_open :: proc(state: ^Frame_State) {
	server := &state.command_server
	wanted := state.content.developer_mode || state.settings.developer_mode
	switch {
	case COMMAND_SOCKET_SUPPORTED && wanted && server.listening == -1 && !server.open_failed:
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
		textures             = state.texture_editor.entries[:],
		screenshot_directory = state.screenshot_directory,
		now                  = time.now(),
	}
	if state.session != nil {
		command_context.simulation = &state.session.simulation
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

// The texture editor (work item 0100, ui_texture_editor.odin).

// $XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson in the temp
// allocator, "" without a state directory.
texture_edits_path :: proc() -> string {
	directories := platform_directories(context.temp_allocator)
	path, _ := texture_edits_path_from_environment(directories.state_home, directories.home, context.temp_allocator)
	return path
}

// Before the frame's screens: the files read again when the Developer
// screen asked or a content reload renumbered the blocks; while the
// editor is open every entry's tile copied into the block atlas, which
// also puts the edits back after a reload rebuilt the atlas from the
// files; a Save written.
serve_texture_editor :: proc(state: ^Frame_State) {
	editor := &state.texture_editor
	if editor.refresh_requested || !texture_editor_matches_registry(editor^, state.content.blocks) {
		editor.refresh_requested = false
		load_texture_editor(editor, state.data_directory, texture_edits_path(), state.content.blocks)
	}
	if screen_stack_contains(state.ui.screens, .Textures) {
		for entry in editor.entries {
			update_atlas_block_tile(chunk_atlas_texture(state.renderer), state.renderer.atlas_layout, entry.block, entry.tile)
		}
	}
	if editor.save_requested {
		editor.save_requested = false
		save_texture_edits(state)
	}
}

// The touch layouts (0121), between frames: the editor's request, served
// after the frame's draw list ran, since it may free the draft's arena
// the frame's text pointed into; a change of the active layout releases
// the overlay's latches, which index its elements; a change the settings
// or the editor made is written to the user file whole. A failed write is
// logged and toasted, and not retried. While a broken file from the start
// stands, nothing is written.
serve_touch_layouts :: proc(state: ^Frame_State) {
	layouts := &state.touch_layouts
	apply_touch_layout_request(&state.ui, &state.touch_layout_editor, layouts, state.content.touch_overlay)
	if layouts.changed {
		layouts.changed = false
		state.touch_overlay = release_touch_latches(state.touch_overlay)
	}
	if !layouts.write_requested {
		return
	}
	layouts.write_requested = false
	if layouts.locked_path != "" {
		ui_toast(&state.ui, touch_layouts_locked_text(layouts^))
		return
	}
	if problem := write_touch_layouts_file(state.environment, layouts^); problem != "" {
		log_printf("error: cannot save the touch layouts: %s", problem)
		ui_toast(&state.ui, text("touch_layout_save_failed"))
	}
}

// Every texture's current parameters to the overrides file, one log line
// per texture in the data file's form, and a toast naming the file.
save_texture_edits :: proc(state: ^Frame_State) {
	editor := &state.texture_editor
	path := texture_edits_path()
	problem := path == "" ? NO_STATE_DIRECTORY_PROBLEM : ""
	lines := texture_editor_lines(editor.entries[:])
	if problem == "" {
		problem = write_texture_edits_file(path, format_texture_edits_file(lines))
	}
	if problem != "" {
		log_printf("error: texture edits: %s", problem)
		ui_toast(&state.ui, fmt.tprintf("%s: %s", text("texture_editor_save_failed"), problem))
		return
	}
	log_printf("texture edits saved to %s", path)
	for line in lines {
		log_printf("texture: %s", line)
	}
	for &entry in editor.entries {
		entry.edited = false
	}
	ui_toast(&state.ui, fmt.tprintf("%s %s", text("texture_editor_saved"), path))
}
