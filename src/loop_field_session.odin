package game

import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// The frame side of a field session (work item 0179, doc/presentation.md,
// The field session): the field renderer of the session, the streaming
// of the simulated set's chunks and of the nodes every viewport sees, and
// the drawing of one viewport's field. The block renderer is not called
// for a field session. A viewport draws, in order: the sky dome turned
// about its player's up (a second camera that maps the up to +y, drawn
// first without depth, warmed round a low sun, 0313), the sun's shadow
// map into its own target (0328, draw_field_sun_shadows), the field's
// terrain and its cover, the globe and the water (0349), the foundations,
// the machines on their frames (draw_entities, lit by the open sky, a
// pod's box at its interior light share), the trees (0197,
// draw_field_trees), the belt and pipe runs, the torches, the
// players' bodies and the viewing player's placement ghost. The planet preview draws the same scene
// (draw_field_scene).

// The clip planes of a field camera: near enough for the hands' reach,
// far enough for the globe from orbit.
FIELD_NEAR_METRES :: 0.1
FIELD_FAR_RADII :: 4
// A torch is drawn as a small glowing box at its sample.
FIELD_TORCH_SIZE_METRES :: 0.2
FIELD_TORCH_COLOR :: rl.Color{255, 196, 96, 255}
// A field torch's flame is the block torch's scaled as its box is to the
// block torch's post (0274).
FIELD_TORCH_FLAME_SCALE :: FIELD_TORCH_SIZE_METRES / (2 * POST_HALF_WIDTH)
// A field torch's point light (0284): the firebox lamp's colour, reaching
// a room of about 10 m (data/lighting.sjson).
FIELD_TORCH_LIGHT_COLOR :: [3]f32{1.0, 0.55, 0.2}
FIELD_TORCH_LIGHT_RADIUS_METRES :: 5.0
// A player whose body model did not load is drawn as a capsule.
FIELD_PLAYER_CAPSULE_COLOR :: rl.Color{70, 110, 180, 255}

// What draw_field_scene draws with. viewer is the player whose camera
// it is (its ghost is drawn, its body only where viewer_body_shown:
// third person, the camera at least VIEWER_BODY_HIDDEN_WITHIN_METRES
// from the body's axis from the feet to the eye, 0261, 0267); NO_PLAYER
// for a free camera. lockstep, when set, gives the local players as
// predicted (lockstep_view_player); nil draws the simulation's players.
Field_Scene :: struct {
	state:        ^Simulation_State,
	content:      Simulation_Content,
	renderer:     ^Field_Renderer,
	models:       Model_Renderer,
	belts:        ^Belt_Renderer,
	player_model: Player_Model,
	frame:        Model_Frame,
	viewer:       int,
	viewer_body_shown: bool,
	lockstep:     ^Lockstep,
	// The arrival's descent (0200, 0223, 0270): the frames, the machines,
	// the players and the ghosts are drawn moved by the pod's transform
	// along the path (arrival_pod_transform), so the cabin travels and
	// turns with the seated eye; nil, unmoved, but in the descent.
	pod_transform: Maybe(matrix[4, 4]f32),
	// The portholes' lights during the descent (0273,
	// arrival_window_lights), in the frame's unmoved space like the lamps.
	window_lights: []Point_Light,
	// The viewer's placement editor (0215): its outline or anchored ghost
	// replaces Place's ghost; zero draws today's ghosts.
	placement_editor: Placement_Editor,
	// The open sky's light and haze (0313) and the viewer's torchlight
	// (0297, field_frame_lights), filled by the callers for the camera
	// they draw with.
	lights:       Field_Frame_Lights,
	// The frame profile the passes mark and count into (0342); nil in the
	// planet preview.
	profile:      ^Frame_Profile,
	// The viewport's index in the frame's viewports: the tree cache's view
	// it draws with (0346, Tree_View), the slot of its kept sun shadow map
	// (0348, draw_field_sun_shadows) and of its instance buffers (0347,
	// Field_Renderer.instance_buffers), 0 in the planet preview, which
	// keeps no map.
	view_slot:    int,
}

#assert(FIELD_VIEW_SLOTS >= MAXIMUM_VIEWPORTS)

// What field_frame_lights reads for a field drawn by the renderer: the
// clock's sky at the ground, the daylight share, the globe's colour as
// the ground's, the planet's radius, the last distance and the data's
// light, haze and atmosphere.
field_light_inputs :: proc(renderer: ^Field_Renderer, sky: Day_Sky, daylight: f32, planet_radius_metres: int, config: Game_Config) -> Field_Light_Inputs {
	return Field_Light_Inputs {
		sky = sky,
		daylight = daylight,
		ground_color = renderer.globe_color,
		planet_radius_metres = f32(planet_radius_metres),
		last_distance_metres = renderer.last_distance_metres,
		light = config.sun_and_torchlight,
		haze = config.haze,
		atmosphere = config.atmosphere,
	}
}

// A player as the scene draws it: the prediction of a local one while the
// lockstep window runs ahead.
field_scene_player :: proc(scene: Field_Scene, index: int) -> Player {
	if scene.lockstep == nil {
		return scene.state.players[index]
	}
	return lockstep_view_player(scene.lockstep, scene.state, index)
}

// The eye a viewport's field streams and draws round.
viewport_field_eye :: proc(session: ^Session, viewport: Viewport) -> World_Position {
	player := lockstep_view_player(&session.lockstep, &session.simulation, viewport.player)
	return field_player_eye(player.field, session.field_content.tuning)
}

// Every ready viewport's eye, in the temp allocator; none outside a field
// session.
field_viewport_eyes :: proc(state: ^Frame_State) -> []World_Position {
	session := state.session
	if session == nil || !session.simulation.field.enabled {
		return nil
	}
	eyes := make([dynamic]World_Position, context.temp_allocator)
	for viewport in active_viewports(state) {
		if viewport_player_ready(session, viewport) {
			append(&eyes, viewport_field_eye(session, viewport))
		}
	}
	return eyes[:]
}

// One selection for every viewport's eye (Field_View.more_cameras) at the
// given level distances, in the temp allocator; none outside a field
// session.
field_viewport_selection :: proc(state: ^Frame_State, level_distances_metres: [FIELD_LEVEL_COUNT]int) -> []Field_Node {
	session := state.session
	eyes := field_viewport_eyes(state)
	if len(eyes) == 0 {
		return nil
	}
	view := make_field_view(eyes[0], session.planet, session.simulation.field.spacing_millimetres, level_distances_metres)
	view.more_cameras = eyes[1:]
	return select_field_nodes(view, context.temp_allocator)
}

// Before a record is stamped: the fraction of an angle unit the previous
// tick's rounding dropped (remainder, field_tick_input) is added to the
// frame as pointer movement, and the fraction this frame's turn leaves is
// returned for the next, so slow turns add up instead of rounding to
// nothing. The record carries the result, so the tick stays the same on
// every machine.
carry_field_turn :: proc(frame: Input_Frame, remainder: [2]f32, tick_rate: int) -> (carried: Input_Frame, rest: [2]f32) {
	carried = frame
	pixels := remainder * 360 / ANGLE_UNITS_PER_TURN / FLY_CAMERA_DEGREES_PER_LOOK_PIXEL
	carried.look_delta += {pixels.x, -pixels.y}
	turn := field_frame_turn(carried, tick_rate)
	return carried, turn - [2]f32{f32(i32(turn.x)), f32(i32(turn.y))}
}

// The frame's selection, made on the first call of the frame and reused
// by the streaming and every viewport's draw (render_frame clears it). It
// is made at the level distances packed inside the view distance setting
// (0343), stored beside it so the frame's other uses read the same view.
frame_field_selection :: proc(state: ^Frame_State) -> []Field_Node {
	if state.presentation.field_selection == nil {
		state.presentation.field_level_distances = field_view_level_distances(state.config.field_view, state.settings.view_distance_metres)
		state.presentation.field_selection = field_viewport_selection(state, state.presentation.field_level_distances)
	}
	return state.presentation.field_selection
}

// The field's part of the frame's streaming: the chunks the next ticks
// need to the workers, the generated ones back as chunk ready commands
// (NO_PLAYER, kept on this machine as the block chunks are), and the
// selection's nodes meshed, the frames handed over for the ground cover
// (0311). A server passes no selection and meshes nothing; the edited
// chunks are taken either way. The surface waves step
// first (advance_field_waves, 0294), so this frame's gather reads this
// frame's heights; with the waves off (a server, the planet preview) the
// gather takes none (field_waves_drawn).
stream_field_session :: proc(session: ^Session, selection: []Field_Node) {
	simulation := &session.simulation
	advance_field_waves(&session.field_waves, &simulation.field.world, simulation.tick)
	frame := Field_Stream_Frame {
		requested = field_chunk_requests(simulation),
		held      = held_field_chunk_arrivals(simulation),
		selection = selection,
	}
	if len(selection) > 0 {
		frame.frames = &simulation.world.entities.frames
	}
	arrivals := make([dynamic]^Field_Chunk, context.temp_allocator)
	update_field_streaming(&session.field_streaming, &simulation.field.world, frame, &arrivals, field_waves_drawn(&session.field_waves))
	for chunk in arrivals {
		queue_player_command(&simulation.player_commands, NO_PLAYER, Field_Chunk_Ready_Command{chunk = chunk})
	}
}

// The field renderer of a field session; false (and a log line) when its
// shader or tiles do not load, and the session then draws only its UI.
// The ground cover's renderer (0311) goes off alone when its shaders do
// not load.
start_field_presentation :: proc(state: ^Frame_State) -> bool {
	session := state.session
	distances := state.config.field_view.level_distances_metres
	renderer, problem := load_field_presentation_or_without_edits(load_field_presentation, state.data_directory, session.planet, session.simulation.field.spacing_millimetres, f32(distances[FIELD_COARSEST_LEVEL]))
	if problem != "" {
		return false
	}
	init_field_cover_renderer(&renderer, state.data_directory, session.planet, field_cover_row(state.config.field_cover), f32(distances[0]))
	state.presentation.field_renderer = renderer
	state.presentation.field_renderer_ready = true
	state.presentation.arrival = init_arrival_presentation(state.data_directory, state.config)
	return true
}

// The ground tiles and the field renderer; the problem is the tiles' or
// the last error line the renderer logged, "" when both loaded.
load_field_presentation :: proc(data_directory: string, planet: Planet, spacing_millimetres: int, fog_end: f32) -> (renderer: Field_Renderer, problem: string) {
	tiles: Field_Ground_Tiles
	if tiles, problem = load_field_material_tiles(data_directory); problem != "" {
		platform.log_printf("error: %s", problem)
		return {}, problem
	}
	capture: platform.Log_Capture
	platform.begin_log_capture(&capture)
	ok: bool
	renderer, ok = init_field_renderer(data_directory, tiles, planet, spacing_millimetres, fog_end)
	problem = platform.end_log_capture(&capture, "the field shaders did not load")
	return renderer, ok ? "" : problem
}

Field_Presentation_Load :: #type proc(data_directory: string, planet: Planet, spacing_millimetres: int, fog_end: f32) -> (renderer: Field_Renderer, problem: string)

// Loaded again without the data edits overlay when it failed with it, as
// init_chunk_renderer_or_without_edits does: an overlay copy of the
// materials file or a field shader written before the looks (0307) fails.
// load is load_field_presentation, a stand-in without GL under test.
load_field_presentation_or_without_edits :: proc(load: Field_Presentation_Load, data_directory: string, planet: Planet, spacing_millimetres: int, fog_end: f32) -> (renderer: Field_Renderer, problem: string) {
	renderer, problem = load(data_directory, planet, spacing_millimetres, fog_end)
	if problem != "" && turn_data_edits_off(problem) {
		renderer, problem = load(data_directory, planet, spacing_millimetres, fog_end)
	}
	return
}

stop_field_presentation :: proc(presentation: ^Frame_Presentation) {
	if presentation.field_renderer_ready {
		destroy_field_renderer(&presentation.field_renderer, presentation.model_renderer)
	}
	presentation.field_renderer_ready = false
	destroy_arrival_presentation(&presentation.arrival)
}

// The camera's look and up turned into the sky's frame, at the origin
// (up_to_sky_rotation, render_day.odin).
field_sky_camera :: proc(camera: rl.Camera3D, up: [3]f32) -> rl.Camera3D {
	rotation := up_to_sky_rotation(up)
	look := linalg.quaternion128_mul_vector3(rotation, camera.target - camera.position)
	sky_up := linalg.quaternion128_mul_vector3(rotation, camera.up)
	return rl.Camera3D{position = {}, target = look, up = sky_up, fovy = camera.fovy, projection = camera.projection}
}

// The working arms', machines', portholes' and torches' lights nearest
// the eye. The arms', machines' and portholes' are moved by the pod's
// transform with the models they light (moved_point_light), so the cabin
// is lit through the fall; the torches stand on the field, unmoved.
gather_field_scene_point_lights :: proc(scene: Field_Scene, eye: [3]f32) -> (nearest: [MAXIMUM_POINT_LIGHTS]Point_Light, count: int) {
	lights := make([dynamic]Point_Light, context.temp_allocator)
	entities := &scene.state.world.entities
	for inserter in entities.inserters.entries {
		if !inserter.alive {
			continue
		}
		placement := model_frame_arm_placement(scene.frame, inserter, scene.content.machines.machines[inserter.machine])
		if light, found := arm_point_light(placement); found {
			append(&lights, light)
		}
	}
	gather_machine_lights(&lights, &scene.state.world.entities, scene.content.machines, scene.models, scene.frame)
	append(&lights, ..scene.window_lights)
	if transform, moved := scene.pod_transform.?; moved {
		for &light in lights {
			light = moved_point_light(light, transform)
		}
	}
	append_field_torch_lights(&lights, scene.state.field.torches[:], scene.state.field.spacing_millimetres, eye, model_frame_seconds(scene.frame), scene.frame.reduced_motion)
	return nearest_point_lights(lights[:], eye)
}

// The scene's lights (gather_field_scene_point_lights), before
// draw_field, to the field shader and the model shader.
set_field_scene_point_lights :: proc(scene: Field_Scene, camera: rl.Camera3D) {
	nearest, _ := gather_field_scene_point_lights(scene, camera.position)
	set_field_point_lights(scene.renderer, nearest)
	set_model_point_lights(scene.models, nearest)
}

// A light moved by transform, its clip box with it. raylib's DrawMesh
// sends the model shader the mesh transform times the rlgl matrix stack's
// (rmodels.c, raylib 6.2), so a model drawn inside the pod's transform
// lights its fragments in the moved place, where the light must be too.
moved_point_light :: proc(light: Point_Light, transform: matrix[4, 4]f32) -> Point_Light {
	moved := light
	moved.position = transform_point(transform, light.position)
	if box, clipped := light.clip_box.?; clipped {
		moved.clip_box = box * linalg.matrix4_inverse_f32(transform)
	}
	return moved
}

// Pushes the pod's transform onto the rlgl stack when there is one; the
// caller pops it (pop_pod_transform).
push_pod_transform :: proc(transform: Maybe(matrix[4, 4]f32)) {
	if moved, present := transform.?; present {
		flat := transmute([16]f32)moved
		rlgl.PushMatrix()
		rlgl.MultMatrixf(raw_data(flat[:]))
	}
}

pop_pod_transform :: proc(transform: Maybe(matrix[4, 4]f32)) {
	if _, present := transform.?; present {
		rlgl.PopMatrix()
	}
}

// The torch's box, through the model shader's flat batch (0360); its
// flame draws after everything opaque (draw_field_flames, 0274).
draw_field_torches :: proc(torches: []Field_Torch, spacing_millimetres: int, models: Model_Renderer) {
	begin_flat_batch(models)
	for torch in torches {
		centre := world_position_to_metres(sample_to_world_position(torch.sample, spacing_millimetres))
		rl.DrawCubeV(centre, FIELD_TORCH_SIZE_METRES, FIELD_TORCH_COLOR)
	}
	end_flat_batch(models)
}

// A field torch's flame on its box (draw_field_torches), the planet's up
// at the torch its up, square to the eye.
field_torch_flame_draw :: proc(torch: Field_Torch, spacing_millimetres: int, eye: [3]f32, seconds: f64, reduced_motion: bool) -> Flame_Draw {
	centre := world_position_to_metres(sample_to_world_position(torch.sample, spacing_millimetres))
	up := linalg.normalize(centre)
	base := centre + up * (FIELD_TORCH_SIZE_METRES / 2 - FLAME_TORCH_SINK * FIELD_TORCH_FLAME_SCALE)
	salt := flame_salt(World_Coordinate(torch.sample), BLOCK_FRAME)
	width, height := f32(FLAME_SIZE * FIELD_TORCH_FLAME_SCALE), f32(FLAME_TORCH_HEIGHT * FIELD_TORCH_FLAME_SCALE)
	corners := flame_quad_corners(base, flame_facing_across(base, eye, up), up, width, height)
	return {corners = corners, seed = flame_seed(salt), flicker = field_torch_flicker(torch, seconds, reduced_motion), aspect = height / width}
}

// A field torch's fire flicker, the same for its flame and its light.
field_torch_flicker :: proc(torch: Field_Torch, seconds: f64, reduced_motion: bool) -> f32 {
	return fire_flicker(seconds, flame_salt(World_Coordinate(torch.sample), BLOCK_FRAME), reduced_motion)
}

// A field torch's light (0284): at its flame's middle above the box,
// the colour flickering with the flame (fire_point_light_flicker),
// unclipped, so it lights the ground, the walls and the player.
field_torch_point_light :: proc(torch: Field_Torch, spacing_millimetres: int, seconds: f64, reduced_motion: bool) -> Point_Light {
	centre := world_position_to_metres(sample_to_world_position(torch.sample, spacing_millimetres))
	up := linalg.normalize(centre)
	position := centre + up * (FIELD_TORCH_SIZE_METRES / 2 + FLAME_TORCH_HEIGHT * FIELD_TORCH_FLAME_SCALE / 2)
	color := FIELD_TORCH_LIGHT_COLOR * fire_point_light_flicker(field_torch_flicker(torch, seconds, reduced_motion))
	return {position = position, color = color, radius = FIELD_TORCH_LIGHT_RADIUS_METRES}
}

// The lights of the field's torches within FLAME_DRAW_DISTANCE_METRES of
// the eye, so a torch lights where its flame draws, appended.
append_field_torch_lights :: proc(lights: ^[dynamic]Point_Light, torches: []Field_Torch, spacing_millimetres: int, eye: [3]f32, seconds: f64, reduced_motion: bool) {
	for torch in torches {
		centre := world_position_to_metres(sample_to_world_position(torch.sample, spacing_millimetres))
		if linalg.length2(centre - eye) <= FLAME_DRAW_DISTANCE_METRES * FLAME_DRAW_DISTANCE_METRES {
			append(lights, field_torch_point_light(torch, spacing_millimetres, seconds, reduced_motion))
		}
	}
}

// The flames of the field's torches within FLAME_DRAW_DISTANCE_METRES of
// the eye, appended.
append_field_torch_flames :: proc(draws: ^[dynamic]Flame_Draw, torches: []Field_Torch, spacing_millimetres: int, eye: [3]f32, seconds: f64, reduced_motion: bool) {
	for torch in torches {
		centre := world_position_to_metres(sample_to_world_position(torch.sample, spacing_millimetres))
		if linalg.length2(centre - eye) <= FLAME_DRAW_DISTANCE_METRES * FLAME_DRAW_DISTANCE_METRES {
			append(draws, field_torch_flame_draw(torch, spacing_millimetres, eye, seconds, reduced_motion))
		}
	}
}

// After the players, before the ghosts: the working furnaces' flames,
// moved by the pod's transform as their models are, and the near
// torches' flames, one list on the tick clock (nearest_flame_draws).
draw_field_flames :: proc(scene: Field_Scene, camera: rl.Camera3D) {
	seconds := model_frame_seconds(scene.frame)
	draws := make([dynamic]Flame_Draw, context.temp_allocator)
	append(&draws, ..gather_machine_flames(&scene.state.world.entities, scene.content.machines, scene.frame))
	if transform, moved := scene.pod_transform.?; moved {
		for &draw in draws {
			for &corner in draw.corners {
				corner = transform_point(transform, corner)
			}
		}
	}
	append_field_torch_flames(&draws, scene.state.field.torches[:], scene.state.field.spacing_millimetres, camera.position, seconds, scene.frame.reduced_motion)
	draw_flames(scene.models.flame, nearest_flame_draws(draws[:], camera.position), seconds, scene.frame.reduced_motion)
}

// Standing at the feet, the model's front (+x) along the heading and its
// up along the player's up, squashed along the up by up_scale while
// crouched (0218: the standing legs do not fold).
field_player_body_transform :: proc(feet: [3]f32, player: Field_Player, up_scale: f32) -> matrix[4, 4]f32 {
	heading := unit_vector_to_f32(field_player_heading(player))
	up := unit_vector_to_f32(player.up) * up_scale
	side := linalg.cross(heading, up)
	return matrix[4, 4]f32{
		heading.x, up.x, side.x, feet.x,
		heading.y, up.y, side.y, feet.y,
		heading.z, up.z, side.z, feet.z,
		0, 0, 0, 1,
	}
}

// The centres of the capsule's end spheres for a body height metres tall.
field_player_capsule_ends :: proc(feet, up: [3]f32, height: f32) -> (bottom, top: [3]f32) {
	return feet + up * 0.3, feet + up * (height - 0.3)
}

// The player without the model; the model preview (0207) draws it for
// scale.
draw_field_player_capsule :: proc(feet, up: [3]f32, height: f32) {
	bottom, top := field_player_capsule_ends(feet, up, height)
	rl.DrawCapsule(bottom, top, 0.3, 4, 8, FIELD_PLAYER_CAPSULE_COLOR)
}

// The feet between the ticks, at the frame's alpha.
field_player_feet :: proc(scene: Field_Scene, player: Field_Player) -> [3]f32 {
	previous := world_position_to_metres(player.previous_position)
	return previous + (world_position_to_metres(player.position) - previous) * scene.frame.alpha
}

// Whether the camera lies clear of a standing body (camera_clear_of_body):
// its axis from the feet between the ticks along its up to its eye at
// the crouch's progress.
field_standing_body_clear :: proc(scene: Field_Scene, player: Field_Player, crouch_progress: f32, camera: [3]f32) -> bool {
	up := unit_vector_to_f32(player.up)
	eye_height := f32(f64(field_eye_height_units(scene.content.field.tuning, crouch_progress)) / POSITION_UNITS_PER_METRE)
	return camera_clear_of_body(camera, field_player_feet(scene, player) + up * eye_height, up, eye_height)
}

// The body standing still, or a capsule without the model; both lowered
// over the crouch's progress.
draw_field_player_body :: proc(scene: Field_Scene, player: Field_Player, crouch_progress: f32) {
	feet := field_player_feet(scene, player)
	tuning := scene.content.field.tuning
	scale := field_body_up_scale(tuning, crouch_progress)
	if !scene.player_model.loaded {
		draw_field_player_capsule(feet, unit_vector_to_f32(player.up), f32(f64(tuning.capsule_height) / POSITION_UNITS_PER_METRE) * scale)
		return
	}
	light := player_body_light(scene.frame, feet, field_player_interior_light_share(scene.frame.interiors, player))
	body := field_player_body_transform(feet, player, scale)
	for limb in Player_Limb {
		draw_player_limb(scene.models, scene.player_model, limb, body * player_model_scale(), light)
	}
}

// Every player but the viewer, and the viewer where its body is shown.
field_player_body_drawn :: proc(scene: Field_Scene, index: int) -> bool {
	return index != scene.viewer || scene.viewer_body_shown
}

// How a player's body is drawn (0268): not at all, standing, or seated
// in the pod's chair.
Field_Body_Pose :: enum u8 {
	Hidden,
	Standing,
	Seated,
}

// The player the chair shows: the viewer when it is in the chair, else
// the lowest index in the chair, -1 for none. The one chair holds every
// seated player (0223), so it shows one body; a cradled one is not in the
// chair (0358).
first_seated_player :: proc(scene: Field_Scene) -> int {
	if scene.viewer >= 0 && scene.viewer < len(scene.state.players) && field_seat_in_chair(field_scene_player(scene, scene.viewer).field.seat) {
		return scene.viewer
	}
	for index in 0 ..< len(scene.state.players) {
		if field_seat_in_chair(field_scene_player(scene, index).field.seat) {
			return index
		}
	}
	return -1
}

// Hidden where the body is not drawn (the viewer in first person), for a
// seated player the chair does not show, so a viewer in the chair sees no
// other seated body round its eye, and for a cradled one (0358): the
// model has no lying pose, and the bed stands for it.
field_player_body_pose :: proc(scene: Field_Scene, index: int) -> Field_Body_Pose {
	if !field_player_body_drawn(scene, index) {
		return .Hidden
	}
	switch field_scene_player(scene, index).field.seat {
	case .Standing:
		return .Standing
	case .Cradled:
		return .Hidden
	case .Strapped, .Seated:
	}
	return index == first_seated_player(scene) ? .Seated : .Hidden
}

// The pod's chair in metres from the frame as it is (the rested one after
// the hit, so the body leans with the pod).
field_seated_chair :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> Seated_Chair {
	return Seated_Chair {
		eye = world_position_to_metres(pod_seat_eye(frame, pod, machine)),
		forward = unit_vector_to_f32(pod_seat_facing(frame, pod, machine)),
		up = unit_vector_to_f32(frame.axes[FRAME_UP]),
	}
}

field_seated_look :: proc(player: Field_Player) -> [3]f32 {
	return linalg.normalize(unit_vector_to_f32(field_look_direction(player.forward, player.up, player.yaw, player.pitch)))
}

// The body in the pod's chair, lit at the pod's interior share (the feet
// hang below the cabin's floor, where the interior lookup sees outdoors).
// Nothing without the model: the capsule would cut the floor seated.
draw_field_player_seated :: proc(scene: Field_Scene, player: Field_Player) {
	if !scene.player_model.loaded {
		return
	}
	pod, frame, found := find_pod(&scene.state.world.entities, scene.content.machines)
	if !found {
		return
	}
	machine := scene.content.machines.machines[pod.machine]
	chair := field_seated_chair(frame, pod, machine)
	eye_height := f32(f64(scene.content.field.tuning.eye_height) / POSITION_UNITS_PER_METRE)
	model := scene.player_model
	body := seated_player_transforms(chair, eye_height, model.pivots, model.leg_part_pivots, field_seated_look(player))
	light := player_body_light(scene.frame, chair.eye, machine.interior_light_share)
	for limb in ([4]Player_Limb{.Torso, .Head, .Arm_Left, .Arm_Right}) {
		draw_player_limb(scene.models, model, limb, body.limbs[limb] * player_model_scale(), light)
	}
	for part in Player_Leg_Part {
		draw_player_leg_part(scene.models, model, part, body.leg_parts[part] * player_model_scale(), light)
	}
}

// Every player's body in its pose (field_player_body_pose). With a
// camera (in the space the bodies are drawn in), a standing body it is
// not clear of is skipped (field_standing_body_clear, 0372): two players
// on one spot, the eye in the other's head saw its torso's top as a flat
// sheet. nil (the sun's shadow pass) draws every body.
draw_field_players :: proc(scene: Field_Scene, camera: Maybe([3]f32) = nil) {
	for index in 0 ..< len(scene.state.players) {
		player := field_scene_player(scene, index)
		switch field_player_body_pose(scene, index) {
		case .Hidden:
		case .Standing:
			crouch_progress := field_crouch_progress_of(scene.renderer.crouch_progress[:], index)
			if position, given := camera.?; given && !field_standing_body_clear(scene, player.field, crouch_progress, position) {
				continue
			}
			draw_field_player_body(scene, player.field, crouch_progress)
		case .Seated:
			draw_field_player_seated(scene, player.field)
		}
	}
}

// The viewer's ghosts are drawn for a viewer standing: nothing is placed
// from the pod's chair (0223).
field_viewer_ghosts_drawn :: proc(scene: Field_Scene) -> bool {
	if scene.viewer < 0 || scene.viewer >= len(scene.state.players) {
		return false
	}
	return field_scene_player(scene, scene.viewer).field.seat == .Standing
}

// Where the viewer's Place would put a vessel part (0361,
// draw_vessel_placement_ghost), a run, a foundation's whole block (0193)
// or a machine, on a frame or on bare ground on a frame of its own (0201,
// field_bare_ground_placement), red where the drain would refuse it
// (field_placement_refusal: a drill off every vein, a taken cell, a
// buried player, too few foundations, ground too steep).
draw_field_ghosts :: proc(scene: Field_Scene) {
	if !field_viewer_ghosts_drawn(scene) {
		return
	}
	player := field_scene_player(scene, scene.viewer)
	entities := &scene.state.world.entities
	if player.field.tool == .Vessel_Part {
		draw_vessel_placement_ghost(scene, player)
		return
	}
	if curve, geometry, refusal, found := field_run_ghost(player.field, entities, scene.content); found {
		draw_belt_run_ghost(curve, geometry, refusal == .None)
	}
	if ghost, shown := placement_editor_ghost(scene.placement_editor, scene.state, scene.content, player); shown {
		draw_placement_editor_ghost(scene, ghost)
		return
	}
	machine := field_placed_machine(player.field, scene.content)
	placement, wanted := field_player_placement(player.field, machine, scene.content)
	if !wanted {
		placement, wanted = field_bare_ground_placement(player.field, machine, scene.content.machines)
	}
	if !wanted {
		return
	}
	frame, cell, found := field_placement_frame(&entities.frames, placement, scene.content.field.foundation_pitch_millimetres)
	if !found {
		return
	}
	color := frame_ghost_color(field_placement_refusal(scene.state, scene.content, player, placement))
	for ghost_cell in field_placement_cells(scene.content, placement, cell) {
		draw_frame_ghost(frame, ghost_cell, color)
	}
}

// A held vessel part's place (field_vessel_placement): its model see
// through, or a box per held cell, red where the drain would refuse it
// (vessel_placement_refusal); nothing where Place would place nothing.
draw_vessel_placement_ghost :: proc(scene: Field_Scene, player: Player) {
	entities := &scene.state.world.entities
	placement, _ := field_vessel_placement(entities, scene.content, player.field)
	frame, cells, found := vessel_placement_cells(entities, scene.content, placement)
	if !found {
		return
	}
	color := frame_ghost_color(vessel_placement_refusal(scene.state, scene.content, player, placement))
	if draw_frame_ghost_model(scene.models, scene.content.machines, frame, placement.machine, placement.origin, placement.rotation, color) {
		return
	}
	for cell in cells {
		draw_frame_ghost(frame, cell, color)
	}
}

// The placement editor's ghost (0215): the flat outline with the front
// arrow (none for a foundation block), or the anchored machine's model
// see through, a box per cell for a foundation or a machine without a
// model.
draw_placement_editor_ghost :: proc(scene: Field_Scene, ghost: Placement_Editor_Ghost) {
	foundation := scene.content.machines.machines[ghost.machine].kind == .Foundation
	switch ghost.kind {
	case .Outline:
		low, high := placement_outline_box(ghost.cells)
		draw_footprint_outline(ghost.frame, low, high, ghost.rotation, !foundation, placement_outline_color(ghost.refusal))
	case .Model:
		color := frame_ghost_color(ghost.refusal)
		if !foundation && draw_frame_ghost_model(scene.models, scene.content.machines, ghost.frame, ghost.machine, ghost.origin, ghost.rotation, color) {
			return
		}
		for cell in ghost.cells {
			draw_frame_ghost(ghost.frame, cell, color)
		}
	}
}

// Inside BeginMode3D with the field camera. The lit models up to the
// players take the open sky (set_model_open_sky), the ghosts their own
// colour. The frames' matrices come from one table (0347,
// frame_matrix_table); the foundations, the machines, the runs, the poles
// and the belt items are culled by the camera's frustum and the haze's
// end (Model_View), the machines drawn instanced after draw_entities
// (draw_scene_model_instances) with the model shader's instancing, the
// pod alone. The slabs, the runs, the poles, the belt items, the torch
// boxes and the emissive layers draw flat through the model shader and
// are hazed as the machines (0360). Every machine pool is draw_entities'
// (0362); the ports and arrows follow the machines (draw_ports_and_arrows),
// and a launching rocket, translucent, is drawn after the players without
// writing depth (draw_launching_rockets).
draw_field_scene :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node) {
	profile_mark(scene.profile, .Lights)
	scene := scene
	frames := frame_matrix_table(&scene.state.world.entities.frames)
	scene.frame.frames = &frames
	scene.frame.interiors = gather_interior_lights(&scene.state.world.entities, scene.content.machines)
	set_field_scene_point_lights(scene, camera)
	set_model_spot_light(scene.models, scene.lights.spot)
	daylight_tint := model_frame_daylight_tint(scene.frame)
	set_model_open_sky(scene.models, scene.lights, daylight_tint, camera.position)
	draw_field_passes(scene, camera, selection, daylight_tint)
	world := &scene.state.world
	view := Model_View {
		frustum         = camera_frustum(camera),
		eye             = camera.position,
		distance_metres = scene.lights.haze.fog_end,
		transform       = scene.pod_transform.? or_else linalg.MATRIX4F32_IDENTITY,
	}
	machines_frame := scene.frame
	machines_frame.view = &view
	instances: [dynamic]Model_Instance
	if scene.models.instancing_ready {
		instances = make([dynamic]Model_Instance, context.temp_allocator)
		machines_frame.instances = &instances
	}
	buffers := &scene.renderer.instance_buffers[scene.view_slot]
	profile_mark(scene.profile, .Foundations)
	push_pod_transform(scene.pod_transform)
	draw_field_foundations(&scene.renderer.foundations, scene.models, machines_frame, &world.entities, nil)
	profile_mark(scene.profile, .Machines)
	draw_entities(world, scene.content.machines, scene.models, scene.content.items, machines_frame)
	draw_ports_and_arrows(world, scene.content.machines, scene.content.fluids, scene.models, machines_frame)
	draw_scene_model_instances(scene.models, instances[:], &buffers.models)
	pop_pod_transform(scene.pod_transform)
	profile_mark(scene.profile, .Trees)
	draw_field_trees(scene, camera)
	profile_mark(scene.profile, .Runs)
	// The runs draw outside the pod's transform.
	run_view := view
	run_view.transform = linalg.MATRIX4F32_IDENTITY
	runs := Belt_Run_Draw{view = &run_view, frames = &frames, models = scene.models, items = &buffers.items}
	draw_belt_runs(scene.belts, &world.entities, scene.content.machines, scene.content.items, scene.state.tick, scene.state.tick_rate, runs)
	profile_mark(scene.profile, .Effects)
	draw_field_torches(scene.state.field.torches[:], scene.state.field.spacing_millimetres, scene.models)
	push_pod_transform(scene.pod_transform)
	draw_field_players(scene, transform_point(linalg.inverse(view.transform), camera.position))
	draw_launching_rockets(world, scene.content.machines, scene.models, machines_frame)
	pop_pod_transform(scene.pod_transform)
	clear_model_open_sky(scene.models)
	// Before the ghosts, so a ghost cube's depth does not hide them.
	draw_field_flames(scene, camera)
	push_pod_transform(scene.pod_transform)
	draw_field_ghosts(scene)
	pop_pod_transform(scene.pod_transform)
}

// The frame profile's section each field pass opens (0342, 0349).
FIELD_PASS_SECTIONS :: [Field_Pass]Frame_Section {
	.Terrain = .Terrain,
	.Cover   = .Cover,
	.Globe   = .Globe,
	.Water   = .Water,
}

// The field's passes in FIELD_PASS_ORDER (0349), each opening its frame
// profile section: the terrain, which returns the nodes the frustum keeps,
// the cover and the water over those, and the globe after the opaque
// ground. The terrain and the water draw from the viewport's anchor
// (0381). The planet preview's nil profile skips the marks and counts.
draw_field_passes :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node, daylight_tint: [3]f32) {
	sections := FIELD_PASS_SECTIONS
	visible: []Field_Node_Render
	anchor := field_camera_anchor(camera, scene.renderer.spacing_millimetres)
	for pass in FIELD_PASS_ORDER {
		profile_mark(scene.profile, sections[pass])
		switch pass {
		case .Terrain:
			visible = draw_field(scene.renderer, camera, selection, scene.lights, anchor, scene.profile)
		case .Cover:
			draw_field_cover(scene.renderer, camera, visible, scene.lights.sun_shadow.texture)
			count_frame(scene.profile, .Cover_Instances, scene.renderer.cover.drawn_count)
		case .Globe:
			draw_field_globe(scene.renderer, scene.models, daylight_tint)
		case .Water:
			draw_field_water(scene.renderer, visible, anchor)
		}
	}
}

#assert(SUN_SHADOW_KEPT_MAPS == MAXIMUM_VIEWPORTS, "a kept sun shadow map per viewport")

// The sun's shadow map for the viewport (0328, render_sun_shadows.odin),
// before its 3D pass: nothing while the setting is off or the sun gives
// no light; the map made when none is (a failure leaves the field without
// shadows). With the viewport's kept map (0348, slot, the viewport's
// index): the kept map of the still casters refreshed when its step asks
// (refresh_kept_sun_shadow_map), copied into the shared map, and the
// moving casters drawn over the copy on its cascade. Without one (the
// pod's descent, the planet preview at SUN_SHADOW_NO_KEPT_MAP, a kept map
// that did not load): the whole pass into the shared map on the cascade
// round the camera, anchored at the world's origin. The casters draw
// depth only: the selected nodes' terrain and the standing trees
// (instanced) in the casters' box, the foundations, the machines in it
// (Model_Frame.casters) and every player's body, the viewer's in first
// person too, under the pod's transform as the scene draws them, the
// batch's own draws through the depth shader as well so they are pressed
// onto the near plane too. The frame the receivers read, zero for none.
draw_field_sun_shadows :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node, inputs: Sun_Shadow_Inputs, slot: int) -> Sun_Shadow_Frame {
	if !inputs.on || scene.lights.sun_color == {} {
		return {}
	}
	shadows := &scene.renderer.sun_shadows
	if shadows.state == .Unloaded {
		receivers := sun_shadow_receivers(scene.renderer, scene.models)
		load_sun_shadow_map(shadows, inputs.data_directory, inputs.row.map_texels, receivers[:])
	}
	if shadows.state != .Ready {
		return {}
	}
	profile_mark(scene.profile, .Shadow_Terrain)
	scene := scene
	frames := frame_matrix_table(&scene.state.world.entities.frames)
	scene.frame.frames = &frames
	kept := usable_sun_shadow_kept(shadows, slot, scene.pod_transform != nil)
	if kept == nil {
		cascade := sun_shadow_cascade(camera.position, scene.lights.sun_direction, field_sun_path_world_axis(camera.up), inputs.row)
		begin_sun_shadow_target(shadows.framebuffer, shadows.depth_texture, shadows.texels, cascade, true)
		nodes, _ := draw_sun_shadow_terrain(scene.renderer, cascade, selection, shadows.material)
		count_frame(scene.profile, .Shadow_Nodes, nodes)
		profile_mark(scene.profile, .Shadow_Trees)
		trees, _ := draw_sun_shadow_trees(scene, cascade, shadows^, inputs.row)
		count_frame(scene.profile, .Shadow_Trees, trees)
		profile_mark(scene.profile, .Shadow_Models)
		draw_sun_shadow_models(scene, cascade, shadows.material, .All)
		end_sun_shadow_map()
		return sun_shadow_frame(cascade, inputs.strength_percent, inputs.row.map_texels, shadows.depth_texture)
	}
	cascade := refresh_kept_sun_shadow_map(scene, camera, selection, inputs, kept)
	copy_sun_shadow_depth(kept.framebuffer, shadows.framebuffer, shadows.texels)
	begin_sun_shadow_target(shadows.framebuffer, shadows.depth_texture, shadows.texels, cascade, false)
	draw_sun_shadow_models(scene, cascade, shadows.material, .Moving)
	end_sun_shadow_map()
	return sun_shadow_frame(cascade, inputs.strength_percent, inputs.row.map_texels, shadows.depth_texture)
}

// Whether the standing trees cast this frame: the row casts some and the
// tree shader loaded.
sun_shadow_trees_cast :: proc(scene: Field_Scene, row: Sun_Shadows_Row) -> bool {
	return row.tree_limit > 0 && scene.models.trees.ready
}

// What this frame offers the viewport's kept map (0348): the camera's
// position and up, the frame's sun and the sun path's axis for that up,
// the row, whether the trees cast, and the change counters of what the
// still casters draw from.
sun_shadow_view :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node, row: Sun_Shadows_Row) -> Sun_Shadow_View {
	return Sun_Shadow_View {
		eye = camera.position,
		toward_sun = scene.lights.sun_direction,
		path_axis = field_sun_path_world_axis(camera.up),
		up = camera.up,
		row = row,
		trees_drawn = sun_shadow_trees_cast(scene, row),
		revisions = {
			meshes = scene.renderer.mesh_revision,
			selection = sun_shadow_selection_hash(selection),
			trees = scene.renderer.trees.revision,
			frames = scene.state.world.entities.frames.revision,
			models = scene.models.revision,
		},
	}
}

// Decision 2's Compare: the kept map's still casters hold when the
// terrain casting in its box fingerprints as when it was drawn, and, when
// trees cast and the tree cache changed, the viewport's casting trees
// updated on its cascade gathered nothing since (0346: on a held cascade
// the cut's other inputs are the key's, so only a gather changes what it
// draws).
kept_sun_shadow_casters_hold :: proc(scene: Field_Scene, selection: []Field_Node, row: Sun_Shadows_Row, key: Sun_Shadow_Kept_Key, revisions: Sun_Shadow_Revisions) -> bool {
	terrain_moved := revisions.meshes != key.revisions.meshes || revisions.selection != key.revisions.selection
	if terrain_moved && sun_shadow_terrain_fingerprint(scene.renderer, key.cascade, selection) != key.terrain_fingerprint {
		return false
	}
	if key.trees_drawn && revisions.trees != key.revisions.trees {
		return update_sun_shadow_trees(scene, key.cascade, row).shadow.gathers == key.tree_gathers
	}
	return true
}

// The viewport's kept map brought up to this frame (decision 2): kept, or
// drawn again with the terrain, the trees and the still machines and
// foundations (draw_sun_shadow_models, .Still) on the cascade
// sun_shadow_kept_cascade gives, and what it was drawn from stored. The
// profile's tree and model marks fall in both paths. Returns the cascade
// the map holds.
refresh_kept_sun_shadow_map :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node, inputs: Sun_Shadow_Inputs, kept: ^Sun_Shadow_Kept) -> Sun_Shadow_Cascade {
	view := sun_shadow_view(scene, camera, selection, inputs.row)
	step := sun_shadow_kept_step(kept^, view)
	if step == .Compare {
		if kept_sun_shadow_casters_hold(scene, selection, inputs.row, kept.key, view.revisions) {
			kept.key.revisions = view.revisions
			step = .Keep
		} else {
			step = .Recentre
		}
	}
	if step == .Keep {
		profile_mark(scene.profile, .Shadow_Trees)
		profile_mark(scene.profile, .Shadow_Models)
		return kept.key.cascade
	}
	cascade := sun_shadow_kept_cascade(kept^, view, step)
	shadows := &scene.renderer.sun_shadows
	begin_sun_shadow_target(kept.framebuffer, kept.depth_texture, shadows.texels, cascade, true)
	nodes, terrain_fingerprint := draw_sun_shadow_terrain(scene.renderer, cascade, selection, shadows.material)
	count_frame(scene.profile, .Shadow_Nodes, nodes)
	profile_mark(scene.profile, .Shadow_Trees)
	trees, tree_gathers := draw_sun_shadow_trees(scene, cascade, shadows^, inputs.row)
	count_frame(scene.profile, .Shadow_Trees, trees)
	profile_mark(scene.profile, .Shadow_Models)
	draw_sun_shadow_models(scene, cascade, shadows.material, .Still)
	end_sun_shadow_map()
	held := step == .Recentre
	kept.key = Sun_Shadow_Kept_Key {
		cascade             = cascade,
		toward_sun          = held ? kept.key.toward_sun : view.toward_sun,
		path_axis           = held ? kept.key.path_axis : view.path_axis,
		row                 = view.row,
		trees_drawn         = view.trees_drawn,
		revisions           = view.revisions,
		terrain_fingerprint = terrain_fingerprint,
		tree_gathers        = tree_gathers,
	}
	kept.drawn = true
	return cascade
}

// The selected nodes' terrain whose box casts (sun_shadow_node_casts),
// with the depth material, its positions in samples scaled to metres by
// the model matrix (field_node_transform, 0381). Returns how many it drew
// and their fingerprint (sun_shadow_terrain_fingerprint's sum).
draw_sun_shadow_terrain :: proc(renderer: ^Field_Renderer, cascade: Sun_Shadow_Cascade, selection: []Field_Node, material: rl.Material) -> (drawn: int, fingerprint: u64) {
	metres := field_metres_per_sample(renderer.spacing_millimetres)
	for node in selection {
		render, casts := sun_shadow_node_casts(renderer, cascade, node)
		if !casts {
			continue
		}
		rl.DrawMesh(render.mesh, material, field_node_transform(render.origin, metres))
		count_draw_call()
		drawn += 1
		fingerprint += sun_shadow_node_term(node, render)
	}
	return drawn, fingerprint
}

// The viewport's casting trees for the cascade (0346, update_shadow_trees),
// cut round the cascade's centre in place of the camera, so a map depends
// on its cascade and not on where the eye stands in its step.
update_sun_shadow_trees :: proc(scene: Field_Scene, cascade: Sun_Shadow_Cascade, row: Sun_Shadows_Row) -> ^Tree_View {
	view := &scene.renderer.trees.views[scene.view_slot]
	update_shadow_trees(&scene.renderer.trees, view, cascade, cascade.centre, field_tree_model_extent(scene), scene.state.field.felled_trees, row.tree_limit, len(scene.content.field.tree_species))
	return view
}

// The casting trees instanced with the depth material, nothing unless
// trees cast. Returns how many it drew and the gathers count of the
// view's pass they came from.
draw_sun_shadow_trees :: proc(scene: Field_Scene, cascade: Sun_Shadow_Cascade, shadows: Sun_Shadow_Renderer, row: Sun_Shadows_Row) -> (drawn, gathers: int) {
	if !sun_shadow_trees_cast(scene, row) {
		return 0, 0
	}
	view := update_sun_shadow_trees(scene, cascade, row)
	set_sun_shadow_instanced(shadows, true)
	draw_tree_pass(scene.models, scene.content.field.tree_species, &view.shadow, shadows.material)
	set_sun_shadow_instanced(shadows, false)
	return len(view.shadow.selected), view.shadow.gathers
}

// The foundations' bricks, the machines in the casters' box of the part
// (Model_Frame.casters, each also by its posed box) and every player's
// body under the depth shader and the pod's transform: the foundations
// unless only the moving casters draw, the players unless only the still
// ones do. The machines draw instanced after draw_entities (0347,
// draw_cast_model_instances) from the viewport's buffer of the part: the
// kept map's still casters from their own, so no buffer is written twice
// in a frame.
draw_sun_shadow_models :: proc(scene: Field_Scene, cascade: Sun_Shadow_Cascade, material: rl.Material, part: Sun_Shadow_Part) {
	casters := scene
	casters.models.material = material
	casters.models.emissive_material = material
	casters.viewer_body_shown = true
	cull := Sun_Shadow_Casters {
		cascade   = cascade,
		transform = scene.pod_transform.? or_else linalg.MATRIX4F32_IDENTITY,
		machines  = scene.content.machines,
		part      = part,
	}
	casters.frame.casters = &cull
	shadows := &scene.renderer.sun_shadows
	instances: [dynamic]Model_Instance
	if shadows.instanced_location != -1 {
		instances = make([dynamic]Model_Instance, context.temp_allocator)
		casters.frame.instances = &instances
	}
	buffers := &scene.renderer.instance_buffers[scene.view_slot]
	world := &scene.state.world
	rl.BeginShaderMode(material.shader)
	push_pod_transform(scene.pod_transform)
	if part != .Moving {
		draw_field_foundations(&scene.renderer.foundations, scene.models, casters.frame, &world.entities, shadows)
	}
	draw_entities(world, scene.content.machines, casters.models, scene.content.items, casters.frame)
	draw_cast_model_instances(scene.models, instances[:], part == .Still ? &buffers.kept_cast_models : &buffers.cast_models, shadows^)
	if part != .Still {
		draw_field_players(casters)
	}
	pop_pod_transform(scene.pod_transform)
	rl.EndShaderMode()
}

// The split screen viewport's target bound again after the shadow map's
// pass (rl.BeginTextureMode on the map unbinds it); a single viewport is
// back on the window after rl.EndTextureMode.
resume_viewport_target :: proc(viewport: ^Viewport) {
	if viewport.presentation.target.id != 0 {
		rl.BeginTextureMode(viewport.presentation.target)
	}
}

// The sky about the camera's up, before the scene, with the haze's glow
// round a low sun (0313).
draw_field_sky :: proc(renderer: ^Sky_Renderer, camera: rl.Camera3D, sky: Day_Sky, satellite: Satellite_Pass, glow: Sky_Glow) {
	rl.BeginMode3D(field_sky_camera(camera, camera.up))
	draw_sky(renderer, field_sky_camera(camera, camera.up), sky, satellite, glow)
	rl.EndMode3D()
}

// The camera mode a body is seen in: first person while strapped in for
// the descent (0223) and while waiting in the cradle (0358), the stored
// mode otherwise, also seated in the chair by choice (0268).
field_view_camera_mode :: proc(body: Field_Player) -> Camera_Mode {
	if body.seat == .Strapped || body.seat == .Cradled {
		return .First_Person
	}
	return body.camera_mode
}

// The viewport's field camera, kept for the HUD's projections, and
// whether it shows the viewer's body (viewer_body_shown).
field_viewport_camera :: proc(state: ^Frame_State, viewport: ^Viewport, player: Player, alpha: f32) -> (camera: rl.Camera3D, body_shown: bool) {
	crouch_progress := field_crouch_progress_of(state.presentation.field_renderer.crouch_progress[:], viewport.player)
	view := field_player_view(player.field, state.session.field_content.tuning, alpha, crouch_progress)
	mode := field_view_camera_mode(player.field)
	camera = pulled_in_field_camera(&state.session.simulation, state.session.field_content, view, mode, state.settings.third_person_distance, state.settings.third_person_shoulder, state.settings.field_of_view)
	viewport.presentation.camera = camera
	return camera, field_viewer_body_shown(mode, camera.position, view, state.session.field_content.tuning, crouch_progress)
}

// The pod as the arrival draws it (0270): its common, its frame and its
// machine; found false without a pod.
Arrival_Pod :: struct {
	common:  Entity_Common,
	frame:   Frame,
	machine: Machine,
	found:   bool,
}

// The viewport's camera during the arrival (0200, render_arrival.odin):
// during the descent the seated camera's position and target moved by
// the pod's transform (arrival_pod_transform, 0270; without a pod the
// path's offset along the player's up and forward), its up the player's
// (the planet's), and the transform the scene draws the pod moved by;
// the camera alone buffeted at the heat unless motion is reduced
// (arrival_buffet_offset, 0269); the stored camera stays the resting
// one, so the HUD's projections stay on the cabin. Shaken after the hit
// unless motion is reduced, stored for the HUD as field_viewport_camera
// stores it.
arrival_viewport_camera :: proc(state: ^Frame_State, viewport: ^Viewport, player: Player, camera: rl.Camera3D, view: Arrival_View, pod: Arrival_Pod, rest_tilt_degrees: int) -> (moved: rl.Camera3D, pod_transform: Maybe(matrix[4, 4]f32)) {
	moved = camera
	switch view.phase {
	case .None:
	case .Descent:
		curve := &state.presentation.arrival.curve
		transform: matrix[4, 4]f32
		if pod.found {
			transform, _, _ = arrival_pod_transform(view, pod.frame, pod.common, pod.machine, rest_tilt_degrees, curve)
		} else {
			up, forward := unit_vector_to_f32(player.field.up), unit_vector_to_f32(player.field.forward)
			transform = linalg.matrix4_translate_f32(arrival_descent_offset(view, up, forward, curve))
		}
		pod_transform = transform
		moved.position = transform_point(transform, camera.position)
		moved.target = transform_point(transform, camera.target)
		if !state.settings.reduced_motion {
			position, look := arrival_buffet_offset(view.seconds, view.heat, state.session.simulation.world.settings.seed)
			moved.position += position
			moved.target += position + look
		}
	case .Settled:
		if state.settings.reduced_motion {
			return
		}
		position, look := arrival_shake_offset(view.seconds_since_hit, state.session.simulation.world.settings.seed)
		moved.position += position
		moved.target += position + look
		viewport.presentation.camera = moved
	}
	return
}

// One viewport of a field session, with the field camera's clip planes
// (the block world's are restored after).
draw_field_viewport_world :: proc(state: ^Frame_State, viewport: ^Viewport, content: Simulation_Content, sky: Day_Sky) {
	session := state.session
	if !state.presentation.field_renderer_ready {
		return
	}
	profile := &state.developer.frame_profile
	profile_mark(profile, .Sky)
	alpha := f32(interpolation_alpha(session.accumulator))
	player := lockstep_view_player(&session.lockstep, &session.simulation, viewport.player)
	view := arrival_view(session.simulation.field.arrival, session.simulation.tick, alpha, state.config, &state.presentation.arrival.curve)
	pod_common, pod, pod_found := find_pod(&session.simulation.world.entities, content.machines)
	pulled, body_shown := field_viewport_camera(state, viewport, player, alpha)
	machine := pod_found ? content.machines.machines[pod_common.machine] : Machine{}
	arrival_pod := Arrival_Pod{common = pod_common, frame = pod, machine = machine, found = pod_found}
	camera, pod_transform := arrival_viewport_camera(state, viewport, player, pulled, view, arrival_pod, content.field.pod_rest.tilt_degrees)
	if point, watching := session.arrival_camera.?; watching && pod_found {
		if transform, moved := pod_transform.?; moved {
			body := entity_body_matrix(&session.simulation.world.entities, pod_common)
			camera = arrival_watch_camera(body, transform, point, {0, f32(machine.footprint.y) / 2, 0}, camera)
		}
	}
	seed := session.simulation.world.settings.seed
	flickers := arrival_window_flickers(view.seconds, machine.window_count, seed, state.settings.reduced_motion)
	window_lights: [MAXIMUM_POD_WINDOWS]Point_Light
	window_light_count := 0
	if pod_found {
		entities := &session.simulation.world.entities
		body := entity_body_matrix(entities, pod_common)
		clip_box := machine_light_clip_box(body, machine.footprint, machine_model_top(state.presentation.model_renderer, pod_common))
		window_lights, window_light_count = arrival_window_lights(view, body, entity_frame_pitch_millimetres(entities, pod_common.frame), machine, clip_box, state.config.arrival_plasma, flickers)
	}
	near, far := rlgl.GetCullDistanceNear(), rlgl.GetCullDistanceFar()
	defer rlgl.SetClipPlanes(near, far)
	altitude := linalg.length(camera.position) - f32(session.planet.radius_metres)
	sky_share := atmosphere_sky_share(altitude, state.config.atmosphere)
	field_sky := altitude_day_sky(sky, sky_share)
	if sky_share < 1 {
		rl.ClearBackground(field_sky.colors.horizon)
	}
	lights := field_frame_lights(field_light_inputs(&state.presentation.field_renderer, sky, 1, session.planet.radius_metres, state.config), camera, viewport.presentation.torchlight)
	draw_field_sky(&state.presentation.renderer.sky, camera, field_sky, viewport.presentation.particle_memory.satellite, Sky_Glow{direction = sun_direction(sky.fraction), color = lights.haze.sun_color})
	rlgl.SetClipPlanes(FIELD_NEAR_METRES, f64(session.planet.radius_metres * FIELD_FAR_RADII))
	scene := Field_Scene {
		state        = &session.simulation,
		content      = content,
		renderer     = &state.presentation.field_renderer,
		models       = state.presentation.model_renderer,
		belts        = &state.presentation.belt_renderer,
		player_model = state.presentation.player_model,
		frame        = Model_Frame{world = &session.simulation.world, tick = session.simulation.tick, alpha = alpha, tick_rate = session.simulation.tick_rate, day_factor = 1, sky_tint = lights.flat_light, open_sky = true, reaching_arm = NO_ENTITY, reduced_motion = state.settings.reduced_motion},
		viewer       = viewport.player,
		viewer_body_shown = body_shown,
		lockstep     = &session.lockstep,
		pod_transform = pod_transform,
		window_lights = window_lights[:window_light_count],
		placement_editor = viewport.interaction.placement_editor,
		lights       = lights,
		profile      = profile,
		view_slot    = viewport_index(state, viewport),
	}
	scene.lights.sun_shadow = draw_field_sun_shadows(scene, camera, frame_field_selection(state), sun_shadow_inputs(state.settings, state.config.sun_shadows, state.data_directory), scene.view_slot)
	resume_viewport_target(viewport)
	rl.BeginMode3D(camera)
	draw_field_scene(scene, camera, frame_field_selection(state))
	if pod_found {
		// The soot, the wake (0304) and the flakes (0290) draw in the
		// frame's unmoved space, under the pod's transform (nil outside
		// the descent), seen from the eye in that space. The soot stays on
		// the portholes after the landing.
		flakes, flake_count := arrival_flakes(view, arrival_flake_source(&state.presentation.arrival.curve, view, state.config, machine, seed), state.settings.reduced_motion)
		transform := pod_transform.? or_else linalg.MATRIX4F32_IDENTITY
		eye := transform_point(linalg.inverse(transform), camera.position)
		push_pod_transform(pod_transform)
		draw_arrival_entry(&state.presentation.arrival, view, &session.simulation.world.entities, pod_common, machine, state.config.arrival_plasma, seed, state.settings.reduced_motion, flakes[:flake_count], eye, transform)
		pop_pod_transform(pod_transform)
	}
	if view.phase == .Settled {
		if site, site_found := field_arrival_debris_site(&session.simulation, content, state.config); site_found {
			colors := arrival_debris_colors(&state.presentation.field_renderer, session.planet.palette, site)
			draw_arrival_debris(site, view, seed, colors, day_factor(sky.blend))
			draw_arrival_dust(site, view, seed, rl.ColorBrightness(colors[0], 0.3))
		}
	}
	rl.EndMode3D()
}

// The debris' site of a field session (0272): the field world's
// generation, the pod's base centre and reach (no pod: the crater's home
// and reach 0).
field_arrival_debris_site :: proc(simulation: ^Simulation_State, content: Simulation_Content, config: Game_Config) -> (site: Arrival_Debris_Site, found: bool) {
	generation := field_tree_generation(&simulation.field)^
	pod_base, reach := world_position_to_metres(World_Position(generation.crater.home)), f32(0)
	if pod, frame, pod_found := find_pod(&simulation.world.entities, content.machines); pod_found {
		pod_base = world_position_to_metres(pod_base_centre(frame, pod))
		reach = arrival_pod_reach_metres(content.machines.machines[pod.machine], frame)
	}
	return arrival_debris_site(generation, config, pod_base, reach)
}

// Before the viewports draw, at the frame's view distance (0343, the
// distances frame_field_selection stored): the sun's shadow map released
// when the setting turned it off or its size changed (0328,
// serve_sun_shadows) and the kept maps of the viewports removed (0348),
// the haze's end, the finished meshes up and those of
// the nodes that left the selection unloaded, the foundations' bricks
// built again when the frame table or the models changed (0347,
// update_field_foundations), the trees' tiles round the
// eyes out to the view (update_field_tree_cache, upload_field_tree_tiles)
// and each player's crouch progress (0218), read by value by the draws.
prepare_field_frame :: proc(state: ^Frame_State) {
	session := state.session
	if !state.presentation.field_renderer_ready {
		return
	}
	profile := &state.developer.frame_profile
	count_frame(profile, .Selected_Nodes, len(frame_field_selection(state)))
	last := state.presentation.field_level_distances[FIELD_COARSEST_LEVEL]
	receivers := sun_shadow_receivers(&state.presentation.field_renderer, state.presentation.model_renderer)
	row := sun_shadows_row(state.config.sun_shadows)
	serve_sun_shadows(&state.presentation.field_renderer.sun_shadows, receivers[:], sun_shadows_enabled(state.settings.sun_shadows, row.on), row.map_texels, state.viewport_count)
	state.presentation.field_renderer.last_distance_metres = f32(last)
	// Every result taken lowers the pending jobs by one.
	pending_before_upload := session.field_streaming.pending_jobs
	upload_streamed_field_meshes(&state.presentation.field_renderer, &session.field_streaming)
	count_frame(profile, .Mesh_Uploads, pending_before_upload - session.field_streaming.pending_jobs)
	update_field_foundations(&state.presentation.field_renderer.foundations, &session.simulation.world.entities, frame_simulation_content(state).machines, state.presentation.model_renderer.revision)
	trees := &state.presentation.field_renderer.trees
	update_field_tree_cache(trees, &session.field_streaming, field_tree_generation(&session.simulation.field), field_viewport_eyes(state), session.simulation.field.felled_trees, field_trees_view_row(field_trees_row(state.config.field_trees), last), session.field_content.foundation_pitch_millimetres)
	upload_field_tree_tiles(trees)
	crouch_progress := &state.presentation.field_renderer.crouch_progress
	resize(crouch_progress, len(session.simulation.players))
	for index in 0 ..< len(crouch_progress) {
		crouching := lockstep_view_player(&session.lockstep, &session.simulation, index).field.crouching
		crouch_progress[index] = advance_field_crouch(crouch_progress[index], crouching, state.frame_seconds)
	}
}
