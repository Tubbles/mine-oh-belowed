package game

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

Frame_State :: struct {
	simulation:  Simulation_State,
	accumulator: Tick_Accumulator,
	input:       Input_Frame,
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

update_frame :: proc(state: ^Frame_State) {
	state.input = read_raylib_input_frame(state.input.pressed)
	tick_count: int
	state.accumulator, tick_count = advance_tick_accumulator(state.accumulator, f64(rl.GetFrameTime()))
	for _ in 0 ..< tick_count {
		simulation_tick(&state.simulation, state.input)
	}
}

render_frame :: proc(state: Frame_State, config: Game_Config) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.Color{24, 24, 32, 255})
	draw_diagnostics(state, config)
}

run_game :: proc(config: Game_Config) {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Mine oh Belowed")
	defer rl.CloseWindow()
	// Escape is bound to the Pause action, so it must not close the window.
	rl.SetExitKey(.KEY_NULL)

	state := Frame_State {
		accumulator = make_tick_accumulator(config.tick_rate),
	}
	for !rl.WindowShouldClose() {
		update_frame(&state)
		render_frame(state, config)
		free_all(context.temp_allocator)
	}
}
