package game

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

// Longest frame the accumulator accepts, so that a stall (debugger, window
// drag) does not trigger a burst of catch up ticks.
MAXIMUM_FRAME_SECONDS :: 0.25

Simulation_State :: struct {
	tick: u64,
}

Tick_Accumulator :: struct {
	seconds_per_tick:    f64,
	accumulated_seconds: f64,
}

// The world lives here until the simulation owns world state (work item
// 0007). The fly camera and debug edits are render side developer tools.
Frame_State :: struct {
	simulation:         Simulation_State,
	accumulator:        Tick_Accumulator,
	input_backend:      Input_Backend,
	sdl3_input:         Sdl3_Input_State,
	input:              Input_Frame,
	registry:           Block_Registry,
	world:              World,
	renderer:           Chunk_Renderer,
	camera:             Fly_Camera,
	show_diagnostics:   bool,
	debug_edit_counter: u64,
}

// Above the middle of the debug terrain, looking down at an angle.
INITIAL_FLY_CAMERA :: Fly_Camera {
	position = {-40, 80, -40},
	yaw      = 45,
	pitch    = -30,
}

simulation_tick :: proc(state: ^Simulation_State, input: Input_Frame) {
	state.tick += 1
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

// Fraction of the next tick already elapsed, for camera interpolation.
interpolation_alpha :: proc(accumulator: Tick_Accumulator) -> f64 {
	return accumulator.accumulated_seconds / accumulator.seconds_per_tick
}

read_input_frame :: proc(state: ^Frame_State, frame_seconds: f32) -> Input_Frame {
	switch state.input_backend {
	case .Sdl3:
		return read_sdl3_input_frame(&state.sdl3_input, state.input, frame_seconds)
	case .Raylib:
		return read_raylib_input_frame(state.input.pressed)
	}
	return {}
}

// The mouse steers the fly camera while the world is shown and is free
// for the diagnostics screen.
apply_cursor_mode :: proc(show_diagnostics: bool) {
	if show_diagnostics {
		rl.EnableCursor()
	} else {
		rl.DisableCursor()
	}
}

apply_debug_actions :: proc(state: ^Frame_State) {
	if .Toggle_Diagnostics in state.input.just_pressed {
		state.show_diagnostics = !state.show_diagnostics
		apply_cursor_mode(state.show_diagnostics)
	}
	if .Debug_Remove_Block in state.input.just_pressed {
		state.debug_edit_counter += 1
		debug_remove_block(&state.world, state.registry, state.camera.position, state.debug_edit_counter)
	}
}

update_frame :: proc(state: ^Frame_State) {
	frame_seconds := rl.GetFrameTime()
	state.input = read_input_frame(state, frame_seconds)
	apply_debug_actions(state)
	state.camera = update_fly_camera(state.camera, state.input, min(frame_seconds, MAXIMUM_FRAME_SECONDS))
	tick_count: int
	state.accumulator, tick_count = advance_tick_accumulator(state.accumulator, f64(frame_seconds))
	for _ in 0 ..< tick_count {
		simulation_tick(&state.simulation, state.input)
	}
}

// Dirty chunks, including those an edit in update_frame just marked, are
// remeshed before drawing.
render_frame :: proc(state: ^Frame_State, config: Game_Config) {
	remesh_dirty_chunks(&state.renderer, &state.world, state.registry)
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(SKY_COLOR)
	rl.BeginMode3D(fly_camera_to_raylib(state.camera))
	draw_chunks(&state.renderer, fly_camera_to_raylib(state.camera))
	rl.EndMode3D()
	if state.show_diagnostics {
		draw_diagnostics_backdrop()
		draw_diagnostics(state^, config)
	} else {
		draw_world_overlay(state^)
	}
}

run_game :: proc(config: Game_Config, input_backend: Input_Backend, registry: Block_Registry, data_directory: string) {
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

	terrain_blocks, terrain_ok := resolve_debug_terrain_blocks(registry)
	renderer, renderer_ok := init_chunk_renderer(registry, data_directory)
	if !terrain_ok || !renderer_ok {
		os.exit(1)
	}
	state := Frame_State {
		accumulator   = make_tick_accumulator(config.tick_rate),
		input_backend = input_backend,
		registry      = registry,
		renderer      = renderer,
		camera        = INITIAL_FLY_CAMERA,
	}
	defer if input_backend == .Sdl3 {
		shutdown_sdl3_input(&state.sdl3_input)
	}
	defer destroy_world(&state.world)
	defer destroy_chunk_renderer(&state.renderer)
	build_debug_terrain(&state.world, terrain_blocks)
	apply_cursor_mode(state.show_diagnostics)
	for !rl.WindowShouldClose() {
		update_frame(&state)
		render_frame(&state, config)
		free_all(context.temp_allocator)
	}
}
