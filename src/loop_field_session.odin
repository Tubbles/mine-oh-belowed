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
// first without depth), the field's terrain and water, the foundations,
// the machines on their frames (draw_entities, lit by the open sky), the
// trees (0197, draw_field_trees), the belt and pipe runs, the torches, the
// players' bodies and the viewing player's placement ghost. The planet preview draws the same scene
// (draw_field_scene).

// The clip planes of a field camera: near enough for the hands' reach,
// far enough for the globe from orbit.
FIELD_NEAR_METRES :: 0.1
FIELD_FAR_RADII :: 4
// A torch is drawn as a small glowing box at its sample.
FIELD_TORCH_SIZE_METRES :: 0.2
FIELD_TORCH_COLOR :: rl.Color{255, 196, 96, 255}
// A player whose body model did not load is drawn as a capsule.
FIELD_PLAYER_CAPSULE_COLOR :: rl.Color{70, 110, 180, 255}

// What draw_field_scene draws with. viewer is the player whose camera
// it is (its ghost is drawn, its body only in third person); NO_PLAYER for
// a free camera. lockstep, when set, gives the local players as predicted
// (lockstep_view_player); nil draws the simulation's players.
Field_Scene :: struct {
	state:        ^Simulation_State,
	content:      Simulation_Content,
	renderer:     ^Field_Renderer,
	models:       Model_Renderer,
	belts:        ^Belt_Renderer,
	player_model: Player_Model,
	frame:        Model_Frame,
	viewer:       int,
	lockstep:     ^Lockstep,
	// The arrival's descent (0200): every viewer is inside the pod, whose
	// hull would hide the window's view, so the frames, the machines, the
	// players and the ghosts are not drawn.
	hide_frames:  bool,
	// The viewer's placement editor (0215): its outline or anchored ghost
	// replaces Place's ghost; zero draws today's ghosts.
	placement_editor: Placement_Editor,
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

// One selection for every viewport's eye (Field_View.more_cameras), in
// the temp allocator; none outside a field session.
field_viewport_selection :: proc(state: ^Frame_State) -> []Field_Node {
	session := state.session
	eyes := field_viewport_eyes(state)
	if len(eyes) == 0 {
		return nil
	}
	view := make_field_view(eyes[0], session.planet, session.simulation.field.spacing_millimetres, state.config.field_view.level_distances_metres)
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
// by the streaming and every viewport's draw (render_frame clears it).
frame_field_selection :: proc(state: ^Frame_State) -> []Field_Node {
	if state.presentation.field_selection == nil {
		state.presentation.field_selection = field_viewport_selection(state)
	}
	return state.presentation.field_selection
}

// The field's part of the frame's streaming: the chunks the next ticks
// need to the workers, the generated ones back as chunk ready commands
// (NO_PLAYER, kept on this machine as the block chunks are), and the
// selection's nodes meshed. A server passes no selection and meshes
// nothing; the edited chunks are taken either way.
stream_field_session :: proc(session: ^Session, selection: []Field_Node) {
	simulation := &session.simulation
	frame := Field_Stream_Frame {
		requested = field_chunk_requests(simulation),
		held      = held_field_chunk_arrivals(simulation),
		selection = selection,
	}
	arrivals := make([dynamic]^Field_Chunk, context.temp_allocator)
	update_field_streaming(&session.field_streaming, &simulation.field.world, frame, &arrivals)
	for chunk in arrivals {
		queue_player_command(&simulation.player_commands, NO_PLAYER, Field_Chunk_Ready_Command{chunk = chunk})
	}
}

// The field renderer of a field session; false (and a log line) when its
// shader or tiles do not load, and the session then draws only its UI.
start_field_presentation :: proc(state: ^Frame_State) -> bool {
	session := state.session
	tiles, problem := load_field_material_tiles(state.data_directory)
	if problem != "" {
		platform.log_printf("error: %s", problem)
		return false
	}
	distances := state.config.field_view.level_distances_metres
	renderer, ok := init_field_renderer(state.data_directory, tiles, session.planet, session.simulation.field.spacing_millimetres, f32(distances[FIELD_COARSEST_LEVEL]))
	if !ok {
		return false
	}
	state.presentation.field_renderer = renderer
	state.presentation.field_renderer_ready = true
	state.presentation.arrival = init_arrival_presentation(state.data_directory)
	return true
}

stop_field_presentation :: proc(presentation: ^Frame_Presentation) {
	if presentation.field_renderer_ready {
		destroy_field_renderer(&presentation.field_renderer)
	}
	presentation.field_renderer_ready = false
	destroy_arrival_presentation(&presentation.arrival)
}

// A rotation that takes the up to +y, so the sky drawn round +y stands
// about the up.
up_to_sky_rotation :: proc(up: [3]f32) -> quaternion128 {
	return linalg.quaternion_between_two_vector3_f32(linalg.normalize(up), [3]f32{0, 1, 0})
}

// The camera's look and up turned into the sky's frame, at the origin.
field_sky_camera :: proc(camera: rl.Camera3D, up: [3]f32) -> rl.Camera3D {
	rotation := up_to_sky_rotation(up)
	look := linalg.quaternion128_mul_vector3(rotation, camera.target - camera.position)
	sky_up := linalg.quaternion128_mul_vector3(rotation, camera.up)
	return rl.Camera3D{position = {}, target = look, up = sky_up, fovy = camera.fovy, projection = camera.projection}
}

// The working arms' lights nearest the camera, before draw_field.
set_field_scene_point_lights :: proc(scene: Field_Scene, camera: rl.Camera3D) {
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
	nearest, _ := nearest_point_lights(lights[:], camera.position)
	set_field_point_lights(scene.renderer, nearest)
}

draw_field_torches :: proc(torches: []Field_Torch, spacing_millimetres: int) {
	for torch in torches {
		centre := world_position_to_metres(sample_to_world_position(torch.sample, spacing_millimetres))
		rl.DrawCubeV(centre, FIELD_TORCH_SIZE_METRES, FIELD_TORCH_COLOR)
	}
}

// Standing at the feet, the model's front (+x) along the heading and its
// up along the player's up.
field_player_body_transform :: proc(feet: [3]f32, player: Field_Player) -> matrix[4, 4]f32 {
	heading := unit_vector_to_f32(field_player_heading(player))
	up := unit_vector_to_f32(player.up)
	side := linalg.cross(heading, up)
	return matrix[4, 4]f32{
		heading.x, up.x, side.x, feet.x,
		heading.y, up.y, side.y, feet.y,
		heading.z, up.z, side.z, feet.z,
		0, 0, 0, 1,
	}
}

// The player without the model; the model preview (0207) draws it for
// scale.
draw_field_player_capsule :: proc(feet, up: [3]f32) {
	rl.DrawCapsule(feet + up * 0.3, feet + up * 1.5, 0.3, 8, 4, FIELD_PLAYER_CAPSULE_COLOR)
}

// The body standing still, or a capsule without the model.
draw_field_player_body :: proc(scene: Field_Scene, player: Field_Player) {
	previous := world_position_to_metres(player.previous_position)
	feet := previous + (world_position_to_metres(player.position) - previous) * scene.frame.alpha
	if !scene.player_model.loaded {
		draw_field_player_capsule(feet, unit_vector_to_f32(player.up))
		return
	}
	light := player_body_light(scene.frame, feet)
	body := field_player_body_transform(feet, player)
	for limb in Player_Limb {
		draw_player_limb(scene.models, scene.player_model, limb, body * player_model_scale(), light)
	}
}

draw_field_players :: proc(scene: Field_Scene) {
	for index in 0 ..< len(scene.state.players) {
		player := field_scene_player(scene, index)
		if index != scene.viewer || player.field.camera_mode == .Third_Person {
			draw_field_player_body(scene, player.field)
		}
	}
}

// Where the viewer's Place would put a run, a foundation's whole block
// (0193) or a machine, on a frame or on bare ground on a frame of its own
// (0201, field_bare_ground_placement), red where the drain would refuse
// it (field_placement_refusal: a drill off every vein, a taken cell, a
// buried player, too few foundations, ground too steep).
draw_field_ghosts :: proc(scene: Field_Scene) {
	if scene.viewer < 0 || scene.viewer >= len(scene.state.players) {
		return
	}
	player := field_scene_player(scene, scene.viewer)
	entities := &scene.state.world.entities
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

// Inside BeginMode3D with the field camera.
draw_field_scene :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node) {
	set_field_scene_point_lights(scene, camera)
	draw_field(scene.renderer, camera, selection)
	world := &scene.state.world
	if !scene.hide_frames {
		draw_frames(&world.entities, scene.content.machines)
		draw_entities(world, scene.content.machines, scene.models, scene.content.items, scene.frame)
	}
	draw_field_trees(scene, camera)
	draw_belt_runs(scene.belts, &world.entities, scene.content.machines, scene.content.items, scene.state.tick, scene.state.tick_rate)
	draw_field_torches(scene.state.field.torches[:], scene.state.field.spacing_millimetres)
	if !scene.hide_frames {
		draw_field_players(scene)
		draw_field_ghosts(scene)
	}
}

// The sky about the camera's up, before the scene.
draw_field_sky :: proc(renderer: ^Sky_Renderer, camera: rl.Camera3D, sky: Day_Sky, satellite: Satellite_Pass) {
	rl.BeginMode3D(field_sky_camera(camera, camera.up))
	draw_sky(renderer, field_sky_camera(camera, camera.up), sky, satellite)
	rl.EndMode3D()
}

// The viewport's field camera, kept for the HUD's projections.
field_viewport_camera :: proc(state: ^Frame_State, viewport: ^Viewport, player: Player, alpha: f32) -> rl.Camera3D {
	view := field_player_view(player.field, state.session.field_content.tuning, alpha)
	camera := field_camera(view, player.field.camera_mode, state.settings.third_person_distance, state.settings.third_person_shoulder, state.settings.field_of_view)
	viewport.presentation.camera = camera
	return camera
}

// The viewport's camera during the arrival (0200, render_arrival.odin):
// on the tilted path to the resting eye during the descent, along the
// pod's axes (the player's without a pod); shaken after the hit unless
// motion is reduced. Stored for the HUD's projections as
// field_viewport_camera stores it.
arrival_viewport_camera :: proc(state: ^Frame_State, viewport: ^Viewport, player: Player, camera: rl.Camera3D, view: Arrival_View, pod: Frame, pod_found: bool, alpha: f32) -> rl.Camera3D {
	camera := camera
	switch view.phase {
	case .None:
		return camera
	case .Descent:
		up, forward := unit_vector_to_f32(player.field.up), unit_vector_to_f32(player.field.forward)
		if pod_found {
			up, forward = unit_vector_to_f32(pod.axes[FRAME_UP]), unit_vector_to_f32(pod.axes[FRAME_FORWARD])
		}
		eye := world_position_to_metres(field_player_view(player.field, state.session.field_content.tuning, alpha).eye)
		camera = arrival_descent_camera(eye, view, up, forward, state.config, state.settings.field_of_view)
	case .Settled:
		if state.settings.reduced_motion {
			return camera
		}
		position, look := arrival_shake_offset(view.seconds_since_hit, state.session.simulation.world.settings.seed)
		camera.position += position
		camera.target += position + look
	}
	viewport.presentation.camera = camera
	return camera
}

// One viewport of a field session, with the field camera's clip planes
// (the block world's are restored after). Returns the arrival's view for
// the window overlay drawn after the 3D pass (draw_arrival_window).
draw_field_viewport_world :: proc(state: ^Frame_State, viewport: ^Viewport, content: Simulation_Content, sky: Day_Sky) -> Arrival_View {
	session := state.session
	if !state.presentation.field_renderer_ready {
		return {}
	}
	alpha := f32(interpolation_alpha(session.accumulator))
	player := lockstep_view_player(&session.lockstep, &session.simulation, viewport.player)
	view := arrival_view(session.simulation.field.arrival, session.simulation.tick, alpha, state.config)
	pod, pod_found := find_pod_frame(&session.simulation.world.entities, content.machines)
	camera := arrival_viewport_camera(state, viewport, player, field_viewport_camera(state, viewport, player, alpha), view, pod, pod_found, alpha)
	near, far := rlgl.GetCullDistanceNear(), rlgl.GetCullDistanceFar()
	defer rlgl.SetClipPlanes(near, far)
	draw_field_sky(&state.presentation.renderer.sky, camera, sky, viewport.presentation.particle_memory.satellite)
	rlgl.SetClipPlanes(FIELD_NEAR_METRES, f64(session.planet.radius_metres * FIELD_FAR_RADII))
	scene := Field_Scene {
		state        = &session.simulation,
		content      = content,
		renderer     = &state.presentation.field_renderer,
		models       = state.presentation.model_renderer,
		belts        = &state.presentation.belt_renderer,
		player_model = state.presentation.player_model,
		frame        = Model_Frame{world = &session.simulation.world, tick = session.simulation.tick, alpha = alpha, tick_rate = session.simulation.tick_rate, day_factor = day_factor(sky.blend), sky_tint = color_to_vector3(sky.colors.sun_tint), open_sky = true, reaching_arm = NO_ENTITY},
		viewer       = viewport.player,
		lockstep     = &session.lockstep,
		hide_frames  = view.phase == .Descent,
		placement_editor = viewport.interaction.placement_editor,
	}
	rl.BeginMode3D(camera)
	draw_field_scene(scene, camera, frame_field_selection(state))
	if view.phase == .Settled && pod_found {
		draw_arrival_dust(pod, view, session.simulation.world.settings.seed, rl.ColorBrightness(field_globe_color(session.planet.palette), 0.3))
	}
	rl.EndMode3D()
	return view
}

// Before the viewports draw: the finished meshes up, the trees round the
// eyes (update_field_tree_cache) and the daylight of the shared clock.
prepare_field_frame :: proc(state: ^Frame_State) {
	session := state.session
	if !state.presentation.field_renderer_ready {
		return
	}
	upload_streamed_field_meshes(&state.presentation.field_renderer, &session.field_streaming)
	update_field_tree_cache(&state.presentation.field_renderer.trees, field_tree_generation(&session.simulation.field), field_viewport_eyes(state))
	state.presentation.field_renderer.daylight = daylight_blend(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks)
}
