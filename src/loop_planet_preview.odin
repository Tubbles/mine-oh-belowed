package game

import "core:fmt"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// The planet preview (--planet-preview, work item 0169): a window with the
// fly camera over the terrain field of the home planet, streamed and
// meshed with the level of detail and drawn with the field shader. No
// simulation, no UI but a line of counts. A viewing tool until the slice
// switches the session to the field world (0179); the field items 0170 to
// 0173 extend it. Escape closes it.
//
// The walk key (PLANET_PREVIEW_WALK_KEY, 0170) switches between the free
// camera and the field player standing on the surface under it: the
// player's controller ticks at the game's tick rate on the raylib input,
// the field streams round the player, and the camera follows its eye with
// its up. The walk key again returns the free camera to the eye.
//
// With a screenshot path (--planet-preview-screenshot) it takes no input:
// the camera stays above the pole's ground just inside the finest level's
// distance, so the finest nodes lie under it and the horizon as far out as
// it can be, tilted by PLANET_PREVIEW_SCREENSHOT_PITCH,
// the frames run until PLANET_PREVIEW_SCREENSHOT_FRAMES have passed and the
// streaming has settled (at most PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT),
// and the last frame is saved to the path. With --planet-preview-walk the
// frame is the field player's instead, standing on the pole's ground and
// looking along the horizon, one tick a frame, taken once it stands.

PLANET_PREVIEW_PLANET :: "home"
PLANET_PREVIEW_START_HEIGHT_METRES :: 40
PLANET_PREVIEW_START_PITCH :: -25
// Above this height the fly speed grows in proportion, so the globe is a
// short flight away.
PLANET_PREVIEW_SPEED_HEIGHT_METRES :: 32
PLANET_PREVIEW_NEAR_METRES :: 0.5
// The far plane in planet radii, so the whole globe fits.
PLANET_PREVIEW_FAR_RADII :: 4
PLANET_PREVIEW_WINDOW_WIDTH :: 1280
PLANET_PREVIEW_WINDOW_HEIGHT :: 720
PLANET_PREVIEW_FIELD_OF_VIEW :: 70
PLANET_PREVIEW_TEXT_SIZE :: 20
// The screenshot camera's height below the finest level's distance, and
// its tilt below the horizon, so the level seams lie ahead.
PLANET_PREVIEW_SCREENSHOT_CLEARANCE_METRES :: 2
PLANET_PREVIEW_SCREENSHOT_PITCH :: -8
PLANET_PREVIEW_SCREENSHOT_FRAMES :: 120
PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT :: 1200
PLANET_PREVIEW_WALK_KEY :: rl.KeyboardKey.G
// The field player starts this far above the generated surface and drops.
PLANET_PREVIEW_WALK_CLEARANCE_MILLIMETRES :: 250
// A slow frame runs at most this many ticks; the rest of the time is
// dropped.
PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME :: 5

Planet_Preview :: struct {
	planet:          Planet,
	level_distances: [FIELD_LEVEL_COUNT]int,
	camera:          Fly_Camera,
	world:           Field_World,
	streaming:       Field_Streaming,
	renderer:        Field_Renderer,
	input_bindings:  Input_Bindings,
	pressed:         Action_Set,
	// Empty for the interactive preview.
	screenshot_path: string,
	seed:            u64,
	tick_rate:       int,
	// The walk mode (0170): the field player instead of the free camera.
	walking:         bool,
	player:          Field_Player,
	tuning:          Field_Player_Tuning,
	// Frame time not yet run as ticks, the input gathered for the next
	// tick, the buttons held on the latest frame (the held buttons of a
	// tick after the first of a frame) and the turn short of a whole angle
	// unit.
	tick_seconds:    f32,
	pending:         Field_Player_Input,
	held_now:        Field_Player_Buttons,
	turn_remainder:  [2]f32,
	tick:            u64,
}

planet_preview_speed_scale :: proc(height_metres: f32) -> f32 {
	return max(1, height_metres / PLANET_PREVIEW_SPEED_HEIGHT_METRES)
}

// Metres from the planet's centre into fixed point, inside the generation's
// far limit.
metres_to_world_position :: proc(position: [3]f32) -> World_Position {
	limit := f32(FAR_LIMIT_METRES)
	world: World_Position
	for axis in 0 ..< 3 {
		world[axis] = i64(clamp(position[axis], -limit, limit) * POSITION_UNITS_PER_METRE)
	}
	return world
}

// Above the planet's pole on +y, where the fly camera's up is the planet's.
planet_preview_start_camera :: proc(planet: Planet) -> Fly_Camera {
	return Fly_Camera{position = {0, f32(planet.radius_metres + PLANET_PREVIEW_START_HEIGHT_METRES), 0}, pitch = PLANET_PREVIEW_START_PITCH}
}

// Above the pole's local ground (the generation's surface there) by the
// finest distance less the clearance: the node holding that ground is then
// nearer than the finest distance.
planet_preview_screenshot_camera :: proc(planet: Planet, seed: u64, finest_distance_metres: int) -> Fly_Camera {
	generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	pole := [3]i64{0, generation.radius, 0}
	ground := f32(generation.radius + surface_relief(generation.surface_seed, pole)) / POSITION_UNITS_PER_METRE
	return Fly_Camera{position = {0, ground + f32(finest_distance_metres - PLANET_PREVIEW_SCREENSHOT_CLEARANCE_METRES), 0}, pitch = PLANET_PREVIEW_SCREENSHOT_PITCH}
}

// Every selected node has been meshed and nothing is pending.
field_streaming_settled :: proc(streaming: ^Field_Streaming, selection: []Field_Node) -> bool {
	if streaming.pending_jobs > 0 {
		return false
	}
	for node in selection {
		if node not_in streaming.mesh_revisions {
			return false
		}
	}
	return true
}

planet_preview_screenshot_due :: proc(frame: int, settled: bool) -> bool {
	return frame >= PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT || (frame >= PLANET_PREVIEW_SCREENSHOT_FRAMES && settled)
}

// Read from the back buffer before the swap; raylib's TakeScreenshot would
// drop the path's directories and report no failure.
save_planet_preview_screenshot :: proc(path: string) -> bool {
	image := rl.LoadImageFromScreen()
	defer rl.UnloadImage(image)
	return rl.ExportImage(image, fmt.ctprintf("%s", path))
}

fly_planet_preview :: proc(preview: ^Planet_Preview, frame_seconds: f32) {
	input := read_raylib_input_frame(preview.pressed, preview.input_bindings, {})
	preview.pressed = input.pressed
	preview.camera = turn_fly_camera(preview.camera, input, frame_seconds)
	height := linalg.length(preview.camera.position) - f32(preview.planet.radius_metres)
	velocity := fly_camera_velocity(preview.camera, input, .Sprint in input.pressed)
	preview.camera.position += velocity * planet_preview_speed_scale(height) * frame_seconds
}

// One frame's turn in angle units at the fly camera's rates: x right, y
// up.
frame_turn_angle_units :: proc(frame: Input_Frame, frame_seconds: f32) -> [2]f32 {
	stick_degrees := frame.look * FLY_CAMERA_STICK_DEGREES_PER_SECOND * frame_seconds
	pointer_degrees := frame.look_delta * FLY_CAMERA_DEGREES_PER_LOOK_PIXEL
	return [2]f32{stick_degrees.x + pointer_degrees.x, stick_degrees.y - pointer_degrees.y} * ANGLE_UNITS_PER_TURN / 360
}

// The whole angle units of the turn and the remainder carried to the next
// frame, so a slow stick turn is not lost to truncation.
carry_turn :: proc(remainder, turn: [2]f32) -> (whole: [2]i32, rest: [2]f32) {
	total := remainder + turn
	whole = {i32(total.x), i32(total.y)}
	return whole, total - {f32(whole.x), f32(whole.y)}
}

// One frame's raylib input as the field player's integers, the stick in
// thousandths. Sprint sprints while held (the toggle setting is the
// session's, 0179); the preview is a developer tool, so the Jump double
// tap flies.
field_player_input_from_frame :: proc(frame: Input_Frame, turn: [2]i32) -> Field_Player_Input {
	input := Field_Player_Input {
		move      = {i32(clamp(frame.move.x, -1, 1) * FIELD_MOVE_ONE), i32(clamp(frame.move.y, -1, 1) * FIELD_MOVE_ONE)},
		turn      = turn,
		developer = true,
	}
	buttons := [?]struct {
		action: Action,
		button: Field_Player_Button,
	}{{.Jump, .Jump}, {.Sneak, .Sneak}, {.Sprint, .Sprint}, {.Sprint_Hold, .Sprint}, {.Toggle_Fly_Mode, .Toggle_Fly_Mode}, {.Toggle_No_Clip, .Toggle_No_Clip}, {.Toggle_Camera_Mode, .Toggle_Camera_Mode}}
	for entry in buttons {
		if entry.action in frame.pressed {
			input.held += {entry.button}
		}
		if entry.action in frame.just_pressed {
			input.just_pressed += {entry.button}
		}
	}
	return input
}

// Frames between ticks add their turns and their presses, and a button
// held on any of them is held for the tick, so a Jump pressed and released
// between two ticks still jumps; the latest move stands.
merge_field_player_input :: proc(pending, next: Field_Player_Input) -> Field_Player_Input {
	merged := next
	merged.turn += pending.turn
	merged.held += pending.held
	merged.just_pressed += pending.just_pressed
	return merged
}

// The field player standing on the generated surface under the free
// camera, heading where the camera looks.
start_planet_preview_walk :: proc(preview: ^Planet_Preview) {
	generation := make_planet_generation(preview.seed, preview.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	clearance := millimetres_to_position_units(PLANET_PREVIEW_WALK_CLEARANCE_MILLIMETRES)
	feet := field_surface_under(generation, metres_to_world_position(preview.camera.position), clearance)
	forward := fly_camera_forward(preview.camera)
	look := [3]i64{i64(forward.x * UNIT_VECTOR_ONE), i64(forward.y * UNIT_VECTOR_ONE), i64(forward.z * UNIT_VECTOR_ONE)}
	preview.player = make_field_player(feet, look)
	preview.walking = true
	preview.tick_seconds = 0
	preview.pending = {}
	preview.held_now = {}
	preview.turn_remainder = {}
}

// The free camera back at the player's eye, with its own yaw and pitch.
stop_planet_preview_walk :: proc(preview: ^Planet_Preview) {
	preview.camera.position = world_position_to_metres(field_player_eye(preview.player, preview.tuning))
	preview.walking = false
}

// One tick of the field player on the pending input; a fly mode change
// logs as the block player's does (log_movement_toggles).
tick_planet_preview_player :: proc(preview: ^Planet_Preview) {
	before := Movement_Toggles{preview.player.flying, preview.player.no_clip}
	tick_field_player(&preview.world, preview.tuning, &preview.player, preview.pending)
	preview.tick += 1
	after := Movement_Toggles{preview.player.flying, preview.player.no_clip}
	if before.flying != after.flying {
		platform.log_printf("player: fly mode %s at tick %d", after.flying ? "on" : "off", preview.tick)
	}
	if before.no_clip != after.no_clip {
		platform.log_printf("player: no clip %s at tick %d", after.no_clip ? "on" : "off", preview.tick)
	}
	preview.pending.turn = {}
	preview.pending.just_pressed = {}
	preview.pending.held = preview.held_now
}

// The fixed step: whole ticks of the frame time, at most
// PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME. Returns the fraction of a tick
// left over, for the camera's interpolation.
walk_planet_preview :: proc(preview: ^Planet_Preview, frame: Input_Frame, frame_seconds: f32) -> f32 {
	turn: [2]i32
	turn, preview.turn_remainder = carry_turn(preview.turn_remainder, frame_turn_angle_units(frame, frame_seconds))
	next := field_player_input_from_frame(frame, turn)
	preview.pending = merge_field_player_input(preview.pending, next)
	preview.held_now = next.held
	tick_length := 1 / f32(preview.tick_rate)
	preview.tick_seconds += frame_seconds
	for ticks := 0; preview.tick_seconds >= tick_length; ticks += 1 {
		if ticks == PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME {
			preview.tick_seconds = 0
			break
		}
		tick_planet_preview_player(preview)
		preview.tick_seconds -= tick_length
	}
	return preview.tick_seconds / tick_length
}

// The input of one interactive frame: the walk key switches modes, then
// the free camera flies or the player walks. Returns the interpolation
// fraction of the walk.
update_planet_preview_input :: proc(preview: ^Planet_Preview, frame_seconds: f32) -> f32 {
	if rl.IsKeyPressed(PLANET_PREVIEW_WALK_KEY) {
		if preview.walking {
			stop_planet_preview_walk(preview)
		} else {
			start_planet_preview_walk(preview)
		}
	}
	if !preview.walking {
		fly_planet_preview(preview, frame_seconds)
		return 1
	}
	frame := read_raylib_input_frame(preview.pressed, preview.input_bindings, {})
	preview.pressed = frame.pressed
	return walk_planet_preview(preview, frame, frame_seconds)
}

// Where the field streams from: the free camera or the player's eye.
planet_preview_viewpoint :: proc(preview: ^Planet_Preview) -> World_Position {
	if preview.walking {
		return field_player_eye(preview.player, preview.tuning)
	}
	return metres_to_world_position(preview.camera.position)
}

planet_preview_raylib_camera :: proc(preview: ^Planet_Preview, alpha: f32) -> rl.Camera3D {
	if preview.walking {
		view := field_player_view(preview.player, preview.tuning, alpha)
		return field_camera(view, preview.player.camera_mode, THIRD_PERSON_DISTANCE, 0, PLANET_PREVIEW_FIELD_OF_VIEW)
	}
	return fly_camera_to_raylib(preview.camera, PLANET_PREVIEW_FIELD_OF_VIEW)
}

planet_preview_height_metres :: proc(preview: ^Planet_Preview) -> f32 {
	viewpoint := world_position_to_metres(planet_preview_viewpoint(preview))
	return linalg.length(viewpoint) - f32(preview.planet.radius_metres)
}

planet_preview_mode_text :: proc(preview: ^Planet_Preview) -> string {
	switch {
	case !preview.walking:
		return "free camera"
	case preview.player.flying:
		return "walk mode, flying"
	case preview.player.on_ground:
		return "walk mode, on the ground"
	}
	return "walk mode, in the air"
}

// With capture set, the frame is saved before it is shown; saved says
// whether that worked.
draw_planet_preview :: proc(preview: ^Planet_Preview, selection: []Field_Node, capture: bool, alpha: f32) -> (saved: bool) {
	camera := planet_preview_raylib_camera(preview, alpha)
	rl.BeginDrawing()
	rl.ClearBackground(FIELD_FOG_COLOR)
	rl.BeginMode3D(camera)
	draw_field(&preview.renderer, camera, selection)
	rl.EndMode3D()
	height := planet_preview_height_metres(preview)
	line := fmt.ctprintf("%d fps  %s  height %.0f m  nodes %d of %d  vertices %d  chunks %d", rl.GetFPS(), planet_preview_mode_text(preview), height, preview.renderer.drawn_node_count, len(selection), preview.renderer.vertex_count, len(preview.world.chunks))
	rl.DrawText(line, PLANET_PREVIEW_TEXT_SIZE, PLANET_PREVIEW_TEXT_SIZE, PLANET_PREVIEW_TEXT_SIZE, rl.WHITE)
	if capture {
		saved = save_planet_preview_screenshot(preview.screenshot_path)
	}
	rl.EndDrawing()
	return saved
}

// Returns the exit code: 0, or 1 when the screenshot could not be saved.
run_planet_preview_frames :: proc(preview: ^Planet_Preview) -> int {
	screenshot := preview.screenshot_path != ""
	for frame := 1; !rl.WindowShouldClose(); frame += 1 {
		alpha := f32(1)
		switch {
		case !screenshot:
			alpha = update_planet_preview_input(preview, rl.GetFrameTime())
		case preview.walking:
			tick_planet_preview_player(preview)
		}
		view := make_field_view(planet_preview_viewpoint(preview), preview.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, preview.level_distances)
		selection := select_field_nodes(view, context.temp_allocator)
		update_field_streaming(&preview.streaming, &preview.world, selection)
		upload_streamed_field_meshes(&preview.renderer, &preview.streaming)
		settled := field_streaming_settled(&preview.streaming, selection) && (!preview.walking || preview.player.on_ground)
		capture := screenshot && planet_preview_screenshot_due(frame, settled)
		saved := draw_planet_preview(preview, selection, capture, alpha)
		free_all(context.temp_allocator)
		if capture {
			if !saved {
				platform.log_printf("error: could not save the planet preview screenshot to %s", preview.screenshot_path)
				return 1
			}
			platform.log_printf("planet preview: saved %s after %d frames", preview.screenshot_path, frame)
			return 0
		}
	}
	return 0
}

// Returns the process's exit code.
// screenshot_path empty runs the interactive preview; walk starts it in
// the walk mode.
run_planet_preview :: proc(config: Game_Config, planets: []Planet, bindings: []Binding, data_directory: string, seed: u64, screenshot_path: string, walk: bool) -> int {
	planet, found := find_planet(planets, PLANET_PREVIEW_PLANET)
	if !found {
		platform.log_printf("error: %s has no planet %q to preview", PLANETS_FILE_NAME, PLANET_PREVIEW_PLANET)
		return 1
	}
	tiles, tiles_problem := load_field_material_tiles(data_directory)
	if tiles_problem != "" {
		platform.log_printf("error: %s", tiles_problem)
		return 1
	}
	install_raylib_trace_log()
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(PLANET_PREVIEW_WINDOW_WIDTH, PLANET_PREVIEW_WINDOW_HEIGHT, "Mine oh Belowed planet preview")
	if !rl.IsWindowReady() {
		platform.log_printf("error: could not open a window (is a display available?)")
		return 1
	}
	defer rl.CloseWindow()
	rlgl.SetClipPlanes(PLANET_PREVIEW_NEAR_METRES, f64(planet.radius_metres * PLANET_PREVIEW_FAR_RADII))
	if screenshot_path == "" {
		rl.DisableCursor()
	}
	level_distances := config.field_view.level_distances_metres
	renderer, renderer_ok := init_field_renderer(data_directory, tiles, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, f32(level_distances[FIELD_COARSEST_LEVEL]))
	if !renderer_ok {
		return 1
	}
	preview := Planet_Preview {
		planet          = planet,
		level_distances = level_distances,
		camera          = planet_preview_start_camera(planet),
		streaming       = start_field_streaming(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, default_worker_count()),
		renderer        = renderer,
		input_bindings  = make_backend_bindings(bindings, .Raylib),
		screenshot_path = screenshot_path,
		seed            = seed,
		tick_rate       = config.tick_rate,
		tuning          = make_field_player_tuning(config.field_player, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, config.tick_rate),
	}
	if screenshot_path != "" {
		preview.camera = planet_preview_screenshot_camera(planet, seed, level_distances[0])
	}
	if walk {
		start_planet_preview_walk(&preview)
	}
	platform.log_printf("planet preview: %s, seed %d, radius %d m", planet.id, seed, planet.radius_metres)
	exit_code := run_planet_preview_frames(&preview)
	stop_field_streaming(&preview.streaming)
	destroy_field_renderer(&preview.renderer)
	destroy_field_world(&preview.world)
	return exit_code
}
