package game

import "core:fmt"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// The planet preview (--planet-preview, work item 0169): a window with the
// fly camera over the terrain field of the home planet, streamed and
// meshed with the level of detail and drawn with the field shader, and a
// line of counts. Escape closes it.
//
// Since the slice (0179) the preview runs a field session: a new world
// made by start_session (no save) on the given seed, its one player made
// through the session's spawn with the starter kit and the preview's
// extras (PLANET_PREVIEW_TOOL_ITEM, foundations and poles), ticked by
// simulation_tick on the raylib input as a session's ticks are, its chunks
// streamed by the session's field streaming (stream_field_session) and the
// scene drawn by the session's draw_field_scene. So the preview exercises
// the session's path, and the game plays as the preview shows.
//
// The walk key (PLANET_PREVIEW_WALK_KEY, 0170) switches between the free
// camera and the player standing on the surface under it: the ticks run
// at the game's tick rate while walking (the world stands still under the
// free camera), the field streams round the player, and the camera
// follows its eye with its up. The walk key again returns the free camera
// to the eye. The hotbar decides the tool as in the game (Hotbar_Next,
// the wheel): Mine digs with the brush, Place places the held material,
// a foundation, a run's end or a torch, Rotate_Building cycles the
// brushes; a second line names the brush, the tool, the target, the
// volume held per material and why the latest edit was refused.
//
// With a screenshot path (--planet-preview-screenshot) it takes no input:
// the camera stays above the pole's ground just inside the finest level's
// distance, so the finest nodes lie under it and the horizon as far out as
// it can be, tilted by PLANET_PREVIEW_SCREENSHOT_PITCH,
// the frames run until PLANET_PREVIEW_SCREENSHOT_FRAMES have passed and the
// streaming has settled (at most PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT),
// and the last frame is saved to the path. With --planet-preview-walk the
// frame is the player's instead, standing on the pole's ground, one tick
// a frame: once it stands and the field has streamed, a pit is dug ahead
// of it with a torch at its bottom (0173, dig_planet_preview_pit) and the
// camera tilts down into it, and the frame is taken once the light has
// spread. --planet-preview-daylight sets the sky light's share in percent
// (the field shader's daylight), so a torch's room shows at night (0).
//
// Once the player stands, a pad of foundations is laid 9 m ahead as well
// (0174, lay_planet_preview_foundations), past the pit, with two arms on it
// (0175, loop_planet_preview_arms.odin), and a second pad beyond it joined
// to the first by a belt run between two free poles (0176,
// loop_planet_preview_runs.odin). --planet-preview-pitch sets the walk
// screenshot's tilt once the pit is dug (default
// PLANET_PREVIEW_PIT_PITCH_DEGREES, down into the pit), so a level shot
// shows the pads, the arms and the run. The pit and the pads are written
// into the session's state directly, between ticks.

PLANET_PREVIEW_PLANET :: "home"
PLANET_PREVIEW_START_HEIGHT_METRES :: 40
PLANET_PREVIEW_START_PITCH :: -25
// The cameras look towards longitude -105 (a yaw of 255 degrees looks
// along longitude 255), where the default seed's hollows below the sea
// level (data/planets.sjson) lie 70 to 500 m from the pole, so the start
// shows the sea (0172).
PLANET_PREVIEW_START_YAW :: 255
// Above this height the fly speed grows in proportion, so the globe is a
// short flight away.
PLANET_PREVIEW_SPEED_HEIGHT_METRES :: 32
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
// A slow frame runs at most this many ticks; the rest of the time is
// dropped.
PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME :: 5
// The preview's player carries this pickaxe besides the starter kit, so
// every material with an item digs (0171), and these many foundations and
// poles.
PLANET_PREVIEW_TOOL_ITEM :: "iron_pickaxe"
PLANET_PREVIEW_FOUNDATION_COUNT :: 100
PLANET_PREVIEW_POLE_COUNT :: 50
// The screenshot's pit: a sphere dug this far ahead of the feet and this
// deep below them, open at the top, and the camera's tilt down into it.
PLANET_PREVIEW_PIT_RADIUS_MILLIMETRES :: 2500
PLANET_PREVIEW_PIT_AHEAD_MILLIMETRES :: 3300
PLANET_PREVIEW_PIT_DEPTH_MILLIMETRES :: 1500
PLANET_PREVIEW_PIT_PITCH_DEGREES :: -50
PLANET_PREVIEW_PITCH_LIMIT_DEGREES :: 89
// The walk screenshot's pad: this far ahead of the feet (past the pit), this many cells
// either side of the first foundation, and a column this high on it.
PLANET_PREVIEW_PAD_DISTANCE_MILLIMETRES :: 9000
PLANET_PREVIEW_PAD_HALF_WIDTH :: 2
PLANET_PREVIEW_PAD_COLUMN_HEIGHT :: 3

Planet_Preview :: struct {
	session:         ^Session,
	content:         Game_Content,
	level_distances: [FIELD_LEVEL_COUNT]int,
	camera:          Fly_Camera,
	renderer:        Field_Renderer,
	input_bindings:  Input_Bindings,
	pressed:         Action_Set,
	// Empty for the interactive preview.
	screenshot_path: string,
	// The walk mode (0170): the player instead of the free camera.
	walking:         bool,
	// Frame time not yet run as ticks, and the frames' events since the
	// last tick (take_tick_input), and the turn's carried fraction
	// (carry_field_turn).
	tick_seconds:    f32,
	tick_input:      Tick_Input_Accumulator,
	turn_remainder:  [2]f32,
	// The screenshot's pit is dug (0173), its pad laid (0174).
	pit_dug:         bool,
	pad_laid:        bool,
	// The arms on the pad (0175, loop_planet_preview_arms.odin): their
	// models and the one drawn at full reach.
	models:          Model_Renderer,
	player_model:    Player_Model,
	reaching_arm:    Entity_Handle,
	// The walk screenshot's tilt once the pit is dug, and the belt's
	// texture for the runs (0176).
	pitch_degrees:   int,
	belts:           Belt_Renderer,
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
	return Fly_Camera{position = {0, f32(planet.radius_metres + PLANET_PREVIEW_START_HEIGHT_METRES), 0}, yaw = PLANET_PREVIEW_START_YAW, pitch = PLANET_PREVIEW_START_PITCH}
}

// Above the pole's local ground (the generation's surface there) by the
// finest distance less the clearance: the node holding that ground is then
// nearer than the finest distance.
planet_preview_screenshot_camera :: proc(planet: Planet, seed: u64, spacing_millimetres, finest_distance_metres: int) -> Fly_Camera {
	generation := make_planet_generation(seed, planet, spacing_millimetres)
	pole := [3]i64{0, generation.radius, 0}
	ground := f32(generation.radius + surface_relief(generation, pole)) / POSITION_UNITS_PER_METRE
	return Fly_Camera{position = {0, ground + f32(finest_distance_metres - PLANET_PREVIEW_SCREENSHOT_CLEARANCE_METRES), 0}, yaw = PLANET_PREVIEW_START_YAW, pitch = PLANET_PREVIEW_SCREENSHOT_PITCH}
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

planet_preview_simulation :: proc(preview: ^Planet_Preview) -> ^Simulation_State {
	return &preview.session.simulation
}

planet_preview_player :: proc(preview: ^Planet_Preview) -> ^Player {
	return &preview.session.simulation.players[0]
}

// The session's content, as frame_simulation_content makes it.
planet_preview_content :: proc(preview: ^Planet_Preview) -> Simulation_Content {
	content := session_simulation_content(preview.content, preview.session.technologies, preview.session.field_content)
	content.generator = &preview.session.generator
	return content
}

fly_planet_preview :: proc(preview: ^Planet_Preview, frame: Input_Frame, frame_seconds: f32) {
	preview.camera = turn_fly_camera(preview.camera, frame, frame_seconds)
	height := linalg.length(preview.camera.position) - f32(preview.session.planet.radius_metres)
	velocity := fly_camera_velocity(preview.camera, frame, .Sprint in frame.pressed)
	preview.camera.position += velocity * planet_preview_speed_scale(height) * frame_seconds
}

// The player standing on the generated surface under the free camera,
// heading where the camera looks.
start_planet_preview_walk :: proc(preview: ^Planet_Preview) {
	simulation := planet_preview_simulation(preview)
	spacing := simulation.field.spacing_millimetres
	generation := make_planet_generation(simulation.world.settings.seed, preview.session.planet, spacing)
	clearance := millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES)
	feet := field_surface_under(generation, metres_to_world_position(preview.camera.position), clearance)
	forward := fly_camera_forward(preview.camera)
	look := [3]i64{i64(forward.x * UNIT_VECTOR_ONE), i64(forward.y * UNIT_VECTOR_ONE), i64(forward.z * UNIT_VECTOR_ONE)}
	planet_preview_player(preview).field = make_field_player(feet, look)
	preview.walking = true
	preview.tick_seconds = 0
	preview.tick_input = {}
	preview.turn_remainder = {}
}

// The free camera back at the player's eye, with its own yaw and pitch.
stop_planet_preview_walk :: proc(preview: ^Planet_Preview) {
	preview.camera.position = world_position_to_metres(field_player_eye(planet_preview_player(preview).field, preview.session.field_content.tuning))
	preview.walking = false
}

// One tick through the session's path: the simulated set's chunks first
// (a tick waiting for its chunks takes the arrived ones, as an offline
// run_ready_ticks does), then simulation_tick on the frame; a fly mode
// change logs. False when the tick waits for chunks.
tick_planet_preview :: proc(preview: ^Planet_Preview, frame: Input_Frame) -> bool {
	simulation := planet_preview_simulation(preview)
	content := planet_preview_content(preview)
	if !simulated_chunks_ready(simulation) {
		update_simulated_chunks(simulation, content)
		return false
	}
	body := &simulation.players[0].field
	before := Movement_Toggles{body.flying, body.no_clip}
	inputs := [1]Input_Frame{frame}
	simulation_tick(simulation, content, inputs[:])
	clear(&simulation.events)
	if before.flying != body.flying {
		platform.log_printf("player: fly mode %s at tick %d", body.flying ? "on" : "off", simulation.tick)
	}
	if before.no_clip != body.no_clip {
		platform.log_printf("player: no clip %s at tick %d", body.no_clip ? "on" : "off", simulation.tick)
	}
	return true
}

// The fixed step: whole ticks of the frame time, at most
// PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME; the first tick takes the
// frames' events (take_tick_input). Returns the fraction of a tick left
// over, for the camera's interpolation.
walk_planet_preview :: proc(preview: ^Planet_Preview, frame: Input_Frame, frame_seconds: f32) -> f32 {
	preview.tick_input = accumulate_frame_input(preview.tick_input, frame)
	tick_length := 1 / f32(preview.session.simulation.tick_rate)
	preview.tick_seconds += frame_seconds
	for ticks := 0; preview.tick_seconds >= tick_length; ticks += 1 {
		if ticks == PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME {
			preview.tick_seconds = 0
			break
		}
		tick_frame: Input_Frame
		tick_frame, preview.tick_input = take_tick_input(preview.tick_input, frame)
		tick_frame, preview.turn_remainder = carry_field_turn(tick_frame, preview.turn_remainder, preview.session.simulation.tick_rate)
		tick_planet_preview(preview, tick_frame)
		preview.tick_seconds -= tick_length
	}
	return preview.tick_seconds / tick_length
}

// The screenshot's pit, once the player stands and the field round it has
// streamed: a sphere dug ahead of the feet and below them, the shadow's
// sky marched as the edit drain does, a torch at the pit's lowest air
// sample, and the camera tilted down into it. The light spreads in the
// following ticks.
dig_planet_preview_pit :: proc(preview: ^Planet_Preview) {
	simulation := planet_preview_simulation(preview)
	player := &simulation.players[0].field
	spacing := simulation.field.spacing_millimetres
	world := &simulation.field.world
	heading := field_heading(player.forward, player.up, player.yaw)
	ahead := World_Position(fixed_scale(heading, millimetres_to_position_units(PLANET_PREVIEW_PIT_AHEAD_MILLIMETRES)))
	down := World_Position(fixed_scale(player.up, millimetres_to_position_units(PLANET_PREVIEW_PIT_DEPTH_MILLIMETRES)))
	centre := player.position + ahead - down
	radius := millimetres_to_position_units(PLANET_PREVIEW_PIT_RADIUS_MILLIMETRES)
	edit := Field_Edit {
		mode = .Dig,
		brush = Field_Brush{shape = .Sphere, radius = radius, rate = 2 * MAXIMUM_DENSITY},
		centre = centre,
		up = player.up,
		diggable = ~bit_set[Field_Material]{},
	}
	apply_field_edit(world, spacing, edit)
	update_field_sky_after_edits(world)
	floor := centre - World_Position(fixed_scale(player.up, radius - sample_axis_to_position(1, spacing)))
	torch := nearest_field_sample(floor, spacing)
	for field_world_get_sample(world, torch).density > 0 {
		floor += World_Position(fixed_scale(player.up, sample_axis_to_position(1, spacing) / 2))
		torch = nearest_field_sample(floor, spacing)
	}
	add_field_light_source(world, torch, preview.session.field_content.torch_level)
	append(&simulation.field.torches, Field_Torch{sample = torch})
	player.pitch = degrees_to_angle_units(preview.pitch_degrees)
	preview.pit_dug = true
	platform.log_printf("planet preview: pit dug, torch at %v", torch)
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
	frame := read_raylib_input_frame(preview.pressed, preview.input_bindings, {})
	preview.pressed = frame.pressed
	if !preview.walking {
		fly_planet_preview(preview, frame, frame_seconds)
		return 1
	}
	// The preview is a developer tool, so the Jump double tap flies.
	frame.developer = true
	return walk_planet_preview(preview, frame, frame_seconds)
}

// Where the field streams and draws from: the free camera or the player's
// eye.
planet_preview_viewpoint :: proc(preview: ^Planet_Preview) -> World_Position {
	if preview.walking {
		return field_player_eye(planet_preview_player(preview).field, preview.session.field_content.tuning)
	}
	return metres_to_world_position(preview.camera.position)
}

planet_preview_raylib_camera :: proc(preview: ^Planet_Preview, alpha: f32) -> rl.Camera3D {
	if preview.walking {
		body := planet_preview_player(preview).field
		view := field_player_view(body, preview.session.field_content.tuning, alpha)
		return field_camera(view, body.camera_mode, THIRD_PERSON_DISTANCE, 0, PLANET_PREVIEW_FIELD_OF_VIEW)
	}
	return fly_camera_to_raylib(preview.camera, PLANET_PREVIEW_FIELD_OF_VIEW)
}

planet_preview_height_metres :: proc(preview: ^Planet_Preview) -> f32 {
	viewpoint := world_position_to_metres(planet_preview_viewpoint(preview))
	return linalg.length(viewpoint) - f32(preview.session.planet.radius_metres)
}

planet_preview_mode_text :: proc(preview: ^Planet_Preview) -> string {
	body := planet_preview_player(preview).field
	switch {
	case !preview.walking:
		return "free camera"
	case body.flying:
		return "walk mode, flying"
	case body.on_ground:
		return "walk mode, on the ground"
	}
	return "walk mode, in the air"
}

// A material's volume held: its items and the credit, in cubic metres.
field_held_cubic_metres :: proc(player: Player, content: Simulation_Content, material: Field_Material) -> f64 {
	volume := field_place_volume_available(player.inventory, content.field.materials[material].item, player.field_credit[material])
	return f64(volume) / f64(FIELD_ITEM_VOLUME)
}

field_edit_refusal_text :: proc(refusal: Field_Edit_Refusal, material: Field_Material) -> string {
	name := field_material_name(material)
	switch refusal {
	case .None:
		return ""
	case .Tool_Tier:
		return fmt.tprintf("  %s needs a better pickaxe", name)
	case .Undiggable:
		return fmt.tprintf("  %s cannot be dug", name)
	case .Nothing_Held:
		return fmt.tprintf("  no %s to place", name)
	case .Would_Bury_Player:
		return "  the place would bury a player"
	case .Frame_Cell_Taken:
		return "  the foundation's cell is taken"
	case .Unknown_Frame:
		return "  the foundation's frame is gone"
	case .Run_Refused:
		return "  the run is refused"
	case .Torch_Blocked:
		return "  a torch does not fit there"
	case .Inventory_Full:
		return "  the inventory is full"
	case .No_Vein:
		return "  a drill needs a vein's outcrop under it"
	case .Needs_Foundation:
		return "  the machine needs a foundation under it"
	case .Too_Few_Foundations:
		return "  too few foundations for the block"
	}
	return ""
}

// What the hotbar's stack makes the tool.
field_held_name :: proc(player: Field_Player) -> string {
	switch player.tool {
	case .Material:
		return field_material_name(player.held_material)
	case .Foundation:
		return "foundation"
	case .Belt_Run:
		return player.run_started ? "belt run, start picked" : "belt run"
	case .Pipe_Run:
		return player.run_started ? "pipe run, start picked" : "pipe run"
	case .Machine:
		return fmt.tprintf("machine, %d quarter turns", player.placement_rotation)
	case .Torch:
		return "torch"
	case .Hand:
		return "hand"
	}
	return ""
}

// The walk mode's tool line: the brush, the tool, the material and tint
// under the reticle, the volume held per material and why the latest edit
// was refused.
planet_preview_tool_text :: proc(preview: ^Planet_Preview) -> string {
	simulation := planet_preview_simulation(preview)
	player := simulation.players[0]
	content := planet_preview_content(preview)
	brush := content.field.brushes[int(player.field.brush) % len(content.field.brushes)]
	target := "nothing in reach"
	if player.field.target.hit {
		sample := field_ground_sample_at(&simulation.field.world, simulation.field.spacing_millimetres, player.field.target.position)
		palette := preview.session.planet.palette
		color := palette[int(sample.tint) % len(palette)]
		target = fmt.tprintf("%s, tint %d (%d %d %d)", field_material_name(sample.material), sample.tint, color.r, color.g, color.b)
	}
	held := ""
	for material in Field_Material {
		if content.field.materials[material].item != NO_ITEM {
			held = fmt.tprintf("%s  %s %.2f m3", held, field_material_name(material), field_held_cubic_metres(player, content, material))
		}
	}
	if player.field.frame_target.hit {
		target = fmt.tprintf("frame %d cell %v", player.field.frame_target.frame, player.field.frame_target.cell)
	}
	entities := &simulation.world.entities
	held = fmt.tprintf("%s  frames %d, runs %d, torches %d", held, len(entities.frames.frames), pool_alive_count(entities.belt_runs), len(simulation.field.torches))
	refusal := field_edit_refusal_text(player.field_refusal, player.field_refused_material)
	if player.field_refusal == .Run_Refused {
		refusal = fmt.tprintf("%s: %v", refusal, player.field_run_refusal)
	}
	shapes := FIELD_BRUSH_SHAPE_NAMES
	return fmt.tprintf("brush %s %.1f m, holding %s  target %s %s%s", shapes[brush.shape], f64(brush.radius) / POSITION_UNITS_PER_METRE, field_held_name(player.field), target, held, refusal)
}

planet_preview_scene :: proc(preview: ^Planet_Preview, alpha: f32) -> Field_Scene {
	simulation := planet_preview_simulation(preview)
	return Field_Scene {
		state = simulation,
		content = planet_preview_content(preview),
		renderer = &preview.renderer,
		models = preview.models,
		belts = &preview.belts,
		player_model = preview.player_model,
		frame = Model_Frame{world = &simulation.world, tick = simulation.tick, alpha = alpha, tick_rate = simulation.tick_rate, day_factor = preview.renderer.daylight, sky_tint = {1, 1, 1}, open_sky = true, reaching_arm = preview.reaching_arm},
		viewer = preview.walking ? 0 : NO_PLAYER,
	}
}

// With capture set, the frame is saved before it is shown; saved says
// whether that worked.
draw_planet_preview :: proc(preview: ^Planet_Preview, selection: []Field_Node, capture: bool, alpha: f32) -> (saved: bool) {
	camera := planet_preview_raylib_camera(preview, alpha)
	rl.BeginDrawing()
	rl.ClearBackground(FIELD_FOG_COLOR)
	rl.BeginMode3D(camera)
	draw_field_scene(planet_preview_scene(preview, alpha), camera, selection)
	rl.EndMode3D()
	height := planet_preview_height_metres(preview)
	line := fmt.ctprintf("%d fps  %s  height %.0f m  nodes %d of %d  vertices %d  chunks %d", rl.GetFPS(), planet_preview_mode_text(preview), height, preview.renderer.drawn_node_count, len(selection), preview.renderer.vertex_count, len(preview.session.simulation.field.world.chunks))
	rl.DrawText(line, PLANET_PREVIEW_TEXT_SIZE, PLANET_PREVIEW_TEXT_SIZE, PLANET_PREVIEW_TEXT_SIZE, rl.WHITE)
	if preview.walking {
		rl.DrawText(fmt.ctprintf("%s", planet_preview_tool_text(preview)), PLANET_PREVIEW_TEXT_SIZE, 5 * PLANET_PREVIEW_TEXT_SIZE / 2, PLANET_PREVIEW_TEXT_SIZE, rl.WHITE)
	}
	if capture {
		saved = save_planet_preview_screenshot(preview.screenshot_path)
	}
	rl.EndDrawing()
	return saved
}

// The walk screenshot waits for the pit, its light and the meshes of
// the chunks they changed: no finest node's chunk dirty and no coarser
// node waiting to mesh again.
planet_preview_pit_lit :: proc(preview: ^Planet_Preview, selection: []Field_Node) -> bool {
	world := &preview.session.simulation.field.world
	if !planet_preview_player(preview).field.on_ground || !preview.pit_dug || pending_field_light_nodes(world) > 0 || len(preview.session.field_streaming.remesh) > 0 {
		return false
	}
	for node in selection {
		if chunk := world.chunks[field_node_chunk(node)] or_else nil; node.level == 0 && chunk != nil && chunk.dirty {
			return false
		}
	}
	return true
}

// The walk screenshot's pad, once the player stands: a free foundation on
// the ground ahead, the square round it snapped to its frame, and a column
// of foundations on one corner.
lay_planet_preview_foundations :: proc(preview: ^Planet_Preview) {
	simulation := planet_preview_simulation(preview)
	content := planet_preview_content(preview)
	player := simulation.players[0].field
	foundation := field_foundation(content)
	if preview.pad_laid || !player.on_ground || foundation == NO_MACHINE {
		return
	}
	preview.pad_laid = true
	heading := field_player_heading(player)
	ahead := player.position + World_Position(fixed_scale(heading, millimetres_to_position_units(PLANET_PREVIEW_PAD_DISTANCE_MILLIMETRES)))
	generation := make_planet_generation(simulation.world.settings.seed, preview.session.planet, simulation.field.spacing_millimetres)
	entities := &simulation.world.entities
	pitch := content.field.foundation_pitch_millimetres
	_, frame := place_free_foundation(entities, content.machines, foundation, field_surface_under(generation, ahead, 0), heading, pitch)
	for x in -PLANET_PREVIEW_PAD_HALF_WIDTH ..= PLANET_PREVIEW_PAD_HALF_WIDTH {
		for z in -PLANET_PREVIEW_PAD_HALF_WIDTH ..= PLANET_PREVIEW_PAD_HALF_WIDTH {
			place_on_frame(entities, content.machines, foundation, frame, {i32(x), 0, i32(z)}, 0)
		}
	}
	for y in 1 ..= PLANET_PREVIEW_PAD_COLUMN_HEIGHT {
		place_on_frame(entities, content.machines, foundation, frame, {PLANET_PREVIEW_PAD_HALF_WIDTH, i32(y), PLANET_PREVIEW_PAD_HALF_WIDTH}, 0)
	}
	platform.log_printf("planet preview: laid %d foundations on frame %d", frame_cell_count(&entities.frames, frame), frame)
	lay_planet_preview_arms(preview, frame)
	lay_planet_preview_run(preview, frame)
}

// The frame's streaming: the session's field streaming round the
// viewpoint (stream_field_session), then the finished meshes up.
stream_planet_preview :: proc(preview: ^Planet_Preview) -> []Field_Node {
	spacing := preview.session.simulation.field.spacing_millimetres
	view := make_field_view(planet_preview_viewpoint(preview), preview.session.planet, spacing, preview.level_distances)
	selection := select_field_nodes(view, context.temp_allocator)
	stream_field_session(preview.session, selection)
	upload_streamed_field_meshes(&preview.renderer, &preview.session.field_streaming)
	return selection
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
			tick_planet_preview(preview, Input_Frame{})
			lay_planet_preview_foundations(preview)
		}
		selection := stream_planet_preview(preview)
		streamed := field_streaming_settled(&preview.session.field_streaming, selection)
		// The pit waits for the chunks round it: a dig skips chunks not
		// loaded yet, which would arrive undug.
		if screenshot && preview.walking && !preview.pit_dug && streamed && planet_preview_player(preview).field.on_ground {
			dig_planet_preview_pit(preview)
		}
		settled := streamed && (!preview.walking || planet_preview_pit_lit(preview, selection))
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

// The preview's extras on top of the starter kit: the pickaxe, the
// foundations and the poles.
give_planet_preview_items :: proc(player: ^Player, items: Item_Registry, machines: Machine_Registry) {
	if tool, found := find_item_id(items, PLANET_PREVIEW_TOOL_ITEM); found {
		inventory_add(player.inventory, items, tool, 1)
	}
	if foundation := find_foundation_machine(machines); foundation != NO_MACHINE {
		inventory_add(player.inventory, items, machines.machines[foundation].item, PLANET_PREVIEW_FOUNDATION_COUNT)
	}
	if pole := find_machine_of_kind(machines, .Belt_Pole); pole != NO_MACHINE {
		inventory_add(player.inventory, items, machines.machines[pole].item, PLANET_PREVIEW_POLE_COUNT)
	}
}

// A new world of the seed on the preview's planet, without a save.
start_planet_preview_session :: proc(config: Game_Config, content: Game_Content, base_generator: Generator, seed: u64) -> (session: ^Session, problem: string) {
	settings := default_world_file_settings(config)
	settings.planet_id = PLANET_PREVIEW_PLANET
	plan := new_world_plan("planet preview", seed, settings, "", false, false)
	session, problem = start_session(plan, config, content, base_generator)
	if problem == "" && !session.simulation.field.enabled {
		end_session(session)
		return nil, "the data has no planet to preview"
	}
	return session, problem
}

// Returns the process's exit code.
// screenshot_path empty runs the interactive preview; walk starts it in
// the walk mode; daylight_percent is the sky light's share; pitch_degrees
// the walk screenshot's tilt once the pit is dug.
run_planet_preview :: proc(config: Game_Config, content: Game_Content, base_generator: Generator, bindings: []Binding, data_directory: string, seed: u64, screenshot_path: string, walk: bool, daylight_percent: int, pitch_degrees: int) -> int {
	if _, found := find_planet(content.planets, PLANET_PREVIEW_PLANET); !found {
		platform.log_printf("error: %s has no planet %q to preview", PLANETS_FILE_NAME, PLANET_PREVIEW_PLANET)
		return 1
	}
	tiles, tiles_problem := load_field_material_tiles(data_directory)
	if tiles_problem != "" {
		platform.log_printf("error: %s", tiles_problem)
		return 1
	}
	if daylight_percent < 0 || daylight_percent > 100 {
		platform.log_printf("error: --planet-preview-daylight=%d is outside 0 to 100", daylight_percent)
		return 1
	}
	if pitch_degrees < -PLANET_PREVIEW_PITCH_LIMIT_DEGREES || pitch_degrees > PLANET_PREVIEW_PITCH_LIMIT_DEGREES {
		platform.log_printf("error: --planet-preview-pitch=%d is outside %d to %d", pitch_degrees, -PLANET_PREVIEW_PITCH_LIMIT_DEGREES, PLANET_PREVIEW_PITCH_LIMIT_DEGREES)
		return 1
	}
	session, problem := start_planet_preview_session(config, content, base_generator, seed)
	if problem != "" {
		platform.log_printf("error: cannot start the preview's world: %s", problem)
		return 1
	}
	defer end_session(session)
	give_planet_preview_items(&session.simulation.players[0], content.items, content.machines)
	planet := session.planet
	spacing := session.simulation.field.spacing_millimetres
	install_raylib_trace_log()
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(PLANET_PREVIEW_WINDOW_WIDTH, PLANET_PREVIEW_WINDOW_HEIGHT, "Mine oh Belowed planet preview")
	if !rl.IsWindowReady() {
		platform.log_printf("error: could not open a window (is a display available?)")
		return 1
	}
	defer rl.CloseWindow()
	rlgl.SetClipPlanes(FIELD_NEAR_METRES, f64(planet.radius_metres * FIELD_FAR_RADII))
	if screenshot_path == "" {
		rl.DisableCursor()
	}
	level_distances := config.field_view.level_distances_metres
	renderer, renderer_ok := init_field_renderer(data_directory, tiles, planet, spacing, f32(level_distances[FIELD_COARSEST_LEVEL]))
	if !renderer_ok {
		return 1
	}
	renderer.daylight = f32(daylight_percent) / 100
	preview := Planet_Preview {
		session         = session,
		content         = content,
		level_distances = level_distances,
		camera          = planet_preview_start_camera(planet),
		renderer        = renderer,
		input_bindings  = make_backend_bindings(bindings, .Raylib),
		screenshot_path = screenshot_path,
		models          = init_model_renderer(content.machines, data_directory),
		player_model    = init_player_model(data_directory),
		pitch_degrees   = pitch_degrees,
		belts           = init_belt_renderer(content.machines),
	}
	if screenshot_path != "" {
		preview.camera = planet_preview_screenshot_camera(planet, seed, spacing, level_distances[0])
	}
	if walk {
		start_planet_preview_walk(&preview)
	}
	platform.log_printf("planet preview: %s, seed %d, radius %d m", planet.id, seed, planet.radius_metres)
	exit_code := run_planet_preview_frames(&preview)
	destroy_field_renderer(&preview.renderer)
	destroy_model_renderer(&preview.models)
	unload_player_model(&preview.player_model)
	destroy_belt_renderer(&preview.belts)
	return exit_code
}
