package game

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

// Longest frame the accumulator accepts, so that a stall (debugger, window
// drag) does not trigger a burst of catch up ticks.
MAXIMUM_FRAME_SECONDS :: 0.25

// The simulation owns the world and the players. players[index] reads
// inputs[index] in simulation_tick; the alpha has one player.
Simulation_State :: struct {
	tick:             u64,
	tick_rate:        int,
	day_length_ticks: u64,
	world:            World,
	players:          [dynamic]Player,
}

Tick_Accumulator :: struct {
	seconds_per_tick:    f64,
	accumulated_seconds: f64,
}

Frame_State :: struct {
	simulation:         Simulation_State,
	accumulator:        Tick_Accumulator,
	input_backend:      Input_Backend,
	sdl3_input:         Sdl3_Input_State,
	input:              Input_Frame,
	previous_input:     Input_Frame,
	frame_seconds:      f32,
	tick_input:         Tick_Input_Accumulator,
	// World actions still held since a screen closed, see update_world_action_guard.
	world_action_guard: Action_Set,
	settings:           Settings,
	ui:                 Ui_State,
	cursor_enabled:     bool,
	quit_requested:     bool,
	registry:           Block_Registry,
	generator:          Generator,
	streaming:          Chunk_Streaming,
	renderer:           Chunk_Renderer,
	show_diagnostics:   bool,
	debug_edit_counter: u64,
}

// Above the middle of the debug terrain, looking down at an angle. The
// player starts here in fly mode on the debug terrain.
INITIAL_FLY_CAMERA :: Fly_Camera {
	position = {-40, 80, -40},
	yaw      = 45,
	pitch    = -30,
}

// The config's starting blocks must have passed validate_starting_blocks.
make_simulation :: proc(config: Game_Config, start: Player_Start, registry: Block_Registry) -> Simulation_State {
	state := Simulation_State {
		tick_rate        = config.tick_rate,
		day_length_ticks = u64(config.day_length_seconds) * u64(config.tick_rate),
	}
	player := make_player(start, len(registry.definitions))
	give_starting_blocks(&player, registry, config.starting_blocks)
	append(&state.players, player)
	return state
}

destroy_simulation :: proc(state: ^Simulation_State) {
	for player in state.players {
		destroy_player(player)
	}
	delete(state.players)
	destroy_world(&state.world)
}

// A player without an input entry gets an empty one.
simulation_tick :: proc(state: ^Simulation_State, registry: Block_Registry, inputs: []Input_Frame) {
	state.tick += 1
	for index in 0 ..< len(state.players) {
		input := index < len(inputs) ? inputs[index] : Input_Frame{}
		tick_player(&state.world, registry, state.players[:], index, input, state.tick_rate)
	}
	tick_world(&state.world, registry, state.tick)
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
		return read_sdl3_input_frame(&state.sdl3_input, state.input, frame_seconds, state.settings)
	case .Raylib:
		return read_raylib_input_frame(state.input.pressed)
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

apply_debug_actions :: proc(state: ^Frame_State) {
	if .Toggle_Diagnostics in state.input.just_pressed {
		state.show_diagnostics = !state.show_diagnostics
	}
	if .Debug_Remove_Block in state.input.just_pressed {
		state.debug_edit_counter += 1
		eye := player_eye(state.simulation.players[0].position)
		debug_remove_block(&state.simulation.world, state.registry, eye, state.debug_edit_counter)
	}
}

// The UI runs in render_frame, so the screen stack read here is the one the
// previous frame left: a screen opened or closed takes effect on the world
// one frame later.
update_frame :: proc(state: ^Frame_State) {
	state.frame_seconds = rl.GetFrameTime()
	state.previous_input = state.input
	state.input = read_input_frame(state, state.frame_seconds)
	apply_debug_actions(state)
	world_blocked := ui_blocks_world(state.ui.screens)
	paused := ui_pauses_simulation(state.ui.screens)
	state.world_action_guard = update_world_action_guard(state.world_action_guard, world_blocked, state.input.pressed)
	frame_for_world := world_input(state.input, world_blocked, state.world_action_guard, state.settings)
	state.tick_input = paused ? {} : accumulate_frame_input(state.tick_input, frame_for_world)
	tick_count: int
	state.accumulator, tick_count = advance_simulation_clock(state.accumulator, f64(state.frame_seconds), paused)
	for _ in 0 ..< tick_count {
		tick_input: Input_Frame
		tick_input, state.tick_input = take_tick_input(state.tick_input, frame_for_world)
		simulation_tick(&state.simulation, state.registry, {tick_input})
	}
	player_chunk := world_to_chunk_coordinate(camera_world_coordinate(state.simulation.players[0].position))
	update_chunk_streaming(&state.streaming, &state.simulation.world, player_chunk)
}

render_frame :: proc(state: ^Frame_State, config: Game_Config) {
	upload_streamed_meshes(&state.renderer, &state.streaming)
	blend := daylight_blend(state.simulation.tick, state.simulation.day_length_ticks)
	apply_daylight(&state.renderer, blend)
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(sky_color(blend))
	player := state.simulation.players[0]
	alpha := f32(interpolation_alpha(state.accumulator))
	camera := fly_camera_to_raylib(player_view_camera(&state.simulation.world, state.registry, player, alpha))
	rl.BeginMode3D(camera)
	draw_chunks(&state.renderer, camera)
	draw_player_world_overlay(player, alpha)
	rl.EndMode3D()
	if state.show_diagnostics {
		draw_diagnostics_backdrop()
		draw_diagnostics(state^, config)
	} else {
		draw_world_overlay(state^)
	}
	run_ui_frame(state)
}

run_ui_frame :: proc(state: ^Frame_State) {
	screen_pixels := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	input := make_ui_input(state.previous_input, state.input)
	ui_begin(&state.ui, input, screen_pixels, state.frame_seconds, state.settings.ui_scale, state.settings.pointer_speed)
	draw_hud(&state.ui)
	run_screens(&state.ui, Screen_Context{settings = &state.settings, quit_requested = &state.quit_requested})
	ui_end(&state.ui)
	apply_cursor_mode(state)
}

run_game :: proc(config: Game_Config, input_backend: Input_Backend, registry: Block_Registry, generator: Generator, start: World_Start, data_directory: string) {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Mine oh Belowed")
	// raylib returns from a failed InitWindow instead of reporting it, and
	// the first draw call would then crash. A missing display is the usual cause.
	if !rl.IsWindowReady() {
		fmt.eprintln("error: could not open a window (is a display available?)")
		os.exit(1)
	}
	defer rl.CloseWindow()
	// Escape is bound to the Pause action, so it must not close the window.
	rl.SetExitKey(.KEY_NULL)

	renderer, renderer_ok := init_chunk_renderer(registry, data_directory)
	if !renderer_ok {
		os.exit(1)
	}
	state := Frame_State {
		accumulator   = make_tick_accumulator(config.tick_rate),
		input_backend = input_backend,
		registry      = registry,
		generator     = generator,
		renderer      = renderer,
		simulation    = make_simulation(config, start.player, registry),
		settings      = DEFAULT_SETTINGS,
		ui            = Ui_State{measure_text = raylib_measure_text},
		// raylib starts with the cursor shown; the first apply hides it.
		cursor_enabled = true,
	}
	defer destroy_ui_state(&state.ui)
	defer if input_backend == .Sdl3 {
		shutdown_sdl3_input(&state.sdl3_input)
	}
	defer destroy_simulation(&state.simulation)
	defer destroy_chunk_renderer(&state.renderer)
	if start.debug_terrain {
		terrain_blocks, terrain_ok := resolve_debug_terrain_blocks(registry)
		if !terrain_ok {
			os.exit(1)
		}
		build_debug_terrain(&state.simulation.world, registry, terrain_blocks)
	}
	// Workers read state.generator, so they stop before state goes away.
	state.streaming = start_chunk_streaming(&state.generator, registry, !start.debug_terrain, default_worker_count())
	defer stop_chunk_streaming(&state.streaming)
	apply_cursor_mode(&state)
	for !rl.WindowShouldClose() && !state.quit_requested {
		update_frame(&state)
		render_frame(&state, config)
		free_all(context.temp_allocator)
	}
}
