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
	// Items obtained, technologies researched and the recipes they unlock.
	unlocks:          Recipe_Unlocks,
	// Filled by ticks, emptied by the UI each frame (toasts). The
	// simulation never calls the UI itself.
	events:           [dynamic]Simulation_Event,
}

Simulation_Event :: struct {
	player: int,
	kind:   Player_Event,
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
	items:              Item_Registry,
	machines:           Machine_Registry,
	recipes:            Recipe_Registry,
	technologies:       Technology_Registry,
	// Inventory sort order, from item_sort_ranks.
	item_sort_ranks:    []u16,
	// Recipe display names and the recipe indices sorted by them.
	recipe_names:       []string,
	recipe_order:       []int,
	recipe_browser:     Recipe_Browser,
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

// The config's starting items must have passed validate_starting_items.
// unlock_all makes every recipe available (--unlock-all or the setting).
make_simulation :: proc(config: Game_Config, start: Player_Start, content: Simulation_Content, technologies: Technology_Registry, unlock_all: bool) -> Simulation_State {
	state := Simulation_State {
		tick_rate        = config.tick_rate,
		day_length_ticks = u64(config.day_length_seconds) * u64(config.tick_rate),
		unlocks          = make_recipe_unlocks(len(content.items.items), content.recipes, technologies, unlock_all),
	}
	player := make_player(start)
	give_starting_items(&player, content.items, config.starting_items)
	append(&state.players, player)
	update_recipe_unlocks(&state.unlocks, content.recipes, state.players[:])
	return state
}

destroy_simulation :: proc(state: ^Simulation_State) {
	for player in state.players {
		destroy_player(player)
	}
	delete(state.players)
	delete(state.events)
	destroy_recipe_unlocks(state.unlocks)
	destroy_world(&state.world)
}

// A player without an input entry gets an empty one. Entities tick after
// the players, so a stack dropped into a furnace this tick is seen at once.
simulation_tick :: proc(state: ^Simulation_State, content: Simulation_Content, inputs: []Input_Frame) {
	state.tick += 1
	for index in 0 ..< len(state.players) {
		input := index < len(inputs) ? inputs[index] : Input_Frame{}
		events := tick_player(&state.world, content, state.players[:], index, input, state.tick_rate)
		for kind in events {
			append(&state.events, Simulation_Event{player = index, kind = kind})
		}
	}
	update_recipe_unlocks(&state.unlocks, content.recipes, state.players[:])
	tick_entities(&state.world, content, state.tick_rate)
	tick_world(&state.world, content.blocks, state.tick)
}

frame_simulation_content :: proc(state: ^Frame_State) -> Simulation_Content {
	return Simulation_Content{blocks = state.registry, items = state.items, machines = state.machines, recipes = state.recipes}
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
	// The right stick drives an open hotbar radial instead of the camera.
	if state.ui.radial.open {
		frame_for_world = without_actions(frame_for_world, {.Look})
	}
	state.tick_input = paused ? {} : accumulate_frame_input(state.tick_input, frame_for_world)
	tick_count: int
	state.accumulator, tick_count = advance_simulation_clock(state.accumulator, f64(state.frame_seconds), paused)
	for _ in 0 ..< tick_count {
		tick_input: Input_Frame
		tick_input, state.tick_input = take_tick_input(state.tick_input, frame_for_world)
		simulation_tick(&state.simulation, frame_simulation_content(state), {tick_input})
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
	draw_entities(&state.simulation.world, state.machines)
	draw_player_world_overlay(&state.simulation.world, frame_simulation_content(state), state.simulation.players[:], 0, alpha)
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
	show_simulation_events(&state.ui, &state.simulation.events)
	player := &state.simulation.players[0]
	screen_context := Screen_Context {
		settings        = &state.settings,
		quit_requested  = &state.quit_requested,
		player          = player,
		items           = state.items,
		item_sort_ranks = state.item_sort_ranks,
		world           = &state.simulation.world,
		machines        = state.machines,
		tick_rate       = state.simulation.tick_rate,
		recipes         = state.recipes,
		technologies    = state.technologies,
		unlocks         = &state.simulation.unlocks,
		recipe_names    = state.recipe_names,
		recipe_order    = state.recipe_order,
		browser         = &state.recipe_browser,
	}
	draw_hud(&state.ui, screen_context)
	run_screens(&state.ui, screen_context)
	ui_end(&state.ui, Icon_Atlas{texture = chunk_atlas_texture(state.renderer), layout = state.renderer.atlas_layout})
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
		}
	}
	clear(events)
}

Game_Content :: struct {
	blocks:          Block_Registry,
	items:           Item_Registry,
	machines:        Machine_Registry,
	recipes:         Recipe_Registry,
	technologies:    Technology_Registry,
	item_sort_ranks: []u16,
	recipe_names:    []string,
	recipe_order:    []int,
	unlock_all:      bool,
}

game_simulation_content :: proc(content: Game_Content) -> Simulation_Content {
	return Simulation_Content{blocks = content.blocks, items = content.items, machines = content.machines, recipes = content.recipes}
}

run_game :: proc(config: Game_Config, input_backend: Input_Backend, content: Game_Content, generator: Generator, start: World_Start, data_directory: string) {
	registry := content.blocks
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
		accumulator     = make_tick_accumulator(config.tick_rate),
		input_backend   = input_backend,
		registry        = registry,
		items           = content.items,
		machines        = content.machines,
		recipes         = content.recipes,
		technologies    = content.technologies,
		item_sort_ranks = content.item_sort_ranks,
		recipe_names    = content.recipe_names,
		recipe_order    = content.recipe_order,
		recipe_browser  = make_recipe_browser(),
		generator       = generator,
		renderer        = renderer,
		simulation      = make_simulation(config, start.player, game_simulation_content(content), content.technologies, content.unlock_all),
		settings        = DEFAULT_SETTINGS,
		ui              = Ui_State{measure_text = raylib_measure_text},
		// raylib starts with the cursor shown; the first apply hides it.
		cursor_enabled  = true,
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
