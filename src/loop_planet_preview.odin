package game

import "core:fmt"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// The planet preview (--planet-preview, work item 0169): a window with the
// fly camera over the terrain field of the home planet, streamed and
// meshed with the level of detail and drawn with the field shader. No
// simulation tick, no player, no UI but a line of counts. A viewing tool
// until the slice switches the session to the field world (0179); the
// field items 0170 to 0173 extend it. Escape closes it.
//
// With a screenshot path (--planet-preview-screenshot) it takes no input:
// the camera stays above the pole's ground just inside the finest level's
// distance, so the finest nodes lie under it and the horizon as far out as
// it can be, tilted by PLANET_PREVIEW_SCREENSHOT_PITCH,
// the frames run until PLANET_PREVIEW_SCREENSHOT_FRAMES have passed and the
// streaming has settled (at most PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT),
// and the last frame is saved to the path.

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

// With capture set, the frame is saved before it is shown; saved says
// whether that worked.
draw_planet_preview :: proc(preview: ^Planet_Preview, selection: []Field_Node, capture: bool) -> (saved: bool) {
	camera := fly_camera_to_raylib(preview.camera, PLANET_PREVIEW_FIELD_OF_VIEW)
	rl.BeginDrawing()
	rl.ClearBackground(FIELD_FOG_COLOR)
	rl.BeginMode3D(camera)
	draw_field(&preview.renderer, camera, selection)
	rl.EndMode3D()
	height := linalg.length(preview.camera.position) - f32(preview.planet.radius_metres)
	line := fmt.ctprintf("%d fps  height %.0f m  nodes %d of %d  vertices %d  chunks %d", rl.GetFPS(), height, preview.renderer.drawn_node_count, len(selection), preview.renderer.vertex_count, len(preview.world.chunks))
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
		if !screenshot {
			fly_planet_preview(preview, rl.GetFrameTime())
		}
		camera := metres_to_world_position(preview.camera.position)
		view := make_field_view(camera, preview.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, preview.level_distances)
		selection := select_field_nodes(view, context.temp_allocator)
		update_field_streaming(&preview.streaming, &preview.world, selection)
		upload_streamed_field_meshes(&preview.renderer, &preview.streaming)
		capture := screenshot && planet_preview_screenshot_due(frame, field_streaming_settled(&preview.streaming, selection))
		saved := draw_planet_preview(preview, selection, capture)
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
// screenshot_path empty runs the interactive preview.
run_planet_preview :: proc(config: Game_Config, planets: []Planet, bindings: []Binding, data_directory: string, seed: u64, screenshot_path: string) -> int {
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
	}
	if screenshot_path != "" {
		preview.camera = planet_preview_screenshot_camera(planet, seed, level_distances[0])
	}
	platform.log_printf("planet preview: %s, seed %d, radius %d m", planet.id, seed, planet.radius_metres)
	exit_code := run_planet_preview_frames(&preview)
	stop_field_streaming(&preview.streaming)
	destroy_field_renderer(&preview.renderer)
	destroy_field_world(&preview.world)
	return exit_code
}
