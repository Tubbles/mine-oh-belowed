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
// belt and pipe runs, the torches, the players' bodies and the viewing
// player's placement ghost. The planet preview draws the same scene
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

// One selection for every viewport's eye (Field_View.more_cameras), in
// the temp allocator; none outside a field session.
field_viewport_selection :: proc(state: ^Frame_State) -> []Field_Node {
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
	return true
}

stop_field_presentation :: proc(presentation: ^Frame_Presentation) {
	if presentation.field_renderer_ready {
		destroy_field_renderer(&presentation.field_renderer)
	}
	presentation.field_renderer_ready = false
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

// The body standing still, or a capsule without the model.
draw_field_player_body :: proc(scene: Field_Scene, player: Field_Player) {
	previous := world_position_to_metres(player.previous_position)
	feet := previous + (world_position_to_metres(player.position) - previous) * scene.frame.alpha
	if !scene.player_model.loaded {
		up := unit_vector_to_f32(player.up)
		rl.DrawCapsule(feet + up * 0.3, feet + up * 1.5, 0.3, 8, 4, FIELD_PLAYER_CAPSULE_COLOR)
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
	machine := field_placed_machine(player.field, scene.content)
	placement, wanted := field_player_placement(player.field, machine, scene.content.field)
	if !wanted {
		placement, wanted = field_bare_ground_placement(player.field, machine)
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

// Inside BeginMode3D with the field camera.
draw_field_scene :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node) {
	set_field_scene_point_lights(scene, camera)
	draw_field(scene.renderer, camera, selection)
	world := &scene.state.world
	draw_frames(&world.entities, scene.content.machines)
	draw_entities(world, scene.content.machines, scene.models, scene.content.items, scene.frame)
	draw_belt_runs(scene.belts, &world.entities, scene.content.machines, scene.content.items, scene.state.tick, scene.state.tick_rate)
	draw_field_torches(scene.state.field.torches[:], scene.state.field.spacing_millimetres)
	draw_field_players(scene)
	draw_field_ghosts(scene)
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

// One viewport of a field session, with the field camera's clip planes
// (the block world's are restored after).
draw_field_viewport_world :: proc(state: ^Frame_State, viewport: ^Viewport, content: Simulation_Content, sky: Day_Sky) {
	session := state.session
	if !state.presentation.field_renderer_ready {
		return
	}
	alpha := f32(interpolation_alpha(session.accumulator))
	player := lockstep_view_player(&session.lockstep, &session.simulation, viewport.player)
	camera := field_viewport_camera(state, viewport, player, alpha)
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
	}
	rl.BeginMode3D(camera)
	draw_field_scene(scene, camera, frame_field_selection(state))
	rl.EndMode3D()
}

// Before the viewports draw: the finished meshes up and the daylight of
// the shared clock.
prepare_field_frame :: proc(state: ^Frame_State) {
	session := state.session
	if !state.presentation.field_renderer_ready {
		return
	}
	upload_streamed_field_meshes(&state.presentation.field_renderer, &session.field_streaming)
	state.presentation.field_renderer.daylight = daylight_blend(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks)
}
