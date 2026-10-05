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
	state.presentation.arrival = init_arrival_presentation(state.data_directory, state.config)
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

// The working arms', machines' and portholes' lights nearest the camera,
// before draw_field, to the field shader and the model shader. They are
// moved by the pod's transform with the models they light
// (moved_point_light), so the cabin is lit through the fall.
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
	gather_machine_lights(&lights, &scene.state.world.entities, scene.content.machines, scene.models, scene.frame)
	append(&lights, ..scene.window_lights)
	if transform, moved := scene.pod_transform.?; moved {
		for &light in lights {
			light = moved_point_light(light, transform)
		}
	}
	nearest, _ := nearest_point_lights(lights[:], camera.position)
	set_field_point_lights(scene.renderer, nearest)
	set_model_point_lights(scene.models, nearest)
}

// A light moved by transform, its clip box with it. raylib's DrawMesh
// sends the model shader the mesh transform times the rlgl matrix stack's
// (rmodels.c, raylib 6.0), so a model drawn inside the pod's transform
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

// The torch's box; its flame draws after everything opaque
// (draw_field_flames, 0274).
draw_field_torches :: proc(torches: []Field_Torch, spacing_millimetres: int) {
	for torch in torches {
		centre := world_position_to_metres(sample_to_world_position(torch.sample, spacing_millimetres))
		rl.DrawCubeV(centre, FIELD_TORCH_SIZE_METRES, FIELD_TORCH_COLOR)
	}
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
	return {corners = corners, seed = flame_seed(salt), flicker = flame_flicker(seconds, salt, reduced_motion), aspect = height / width}
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
	rl.DrawCapsule(bottom, top, 0.3, 8, 4, FIELD_PLAYER_CAPSULE_COLOR)
}

// The body standing still, or a capsule without the model; both lowered
// over the crouch's progress.
draw_field_player_body :: proc(scene: Field_Scene, player: Field_Player, crouch_progress: f32) {
	previous := world_position_to_metres(player.previous_position)
	feet := previous + (world_position_to_metres(player.position) - previous) * scene.frame.alpha
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

// The player the chair shows: the viewer when it is not standing, else
// the lowest index not standing, -1 for none. The one chair holds every
// seated player (0223), so it shows one body.
first_seated_player :: proc(scene: Field_Scene) -> int {
	if scene.viewer >= 0 && scene.viewer < len(scene.state.players) && field_scene_player(scene, scene.viewer).field.seat != .Standing {
		return scene.viewer
	}
	for index in 0 ..< len(scene.state.players) {
		if field_scene_player(scene, index).field.seat != .Standing {
			return index
		}
	}
	return -1
}

// Hidden where the body is not drawn (the viewer in first person) and for
// a seated player the chair does not show, so a viewer in the chair sees
// no other seated body round its eye.
field_player_body_pose :: proc(scene: Field_Scene, index: int) -> Field_Body_Pose {
	if !field_player_body_drawn(scene, index) {
		return .Hidden
	}
	if field_scene_player(scene, index).field.seat == .Standing {
		return .Standing
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

// Every player's body in its pose (field_player_body_pose).
draw_field_players :: proc(scene: Field_Scene) {
	for index in 0 ..< len(scene.state.players) {
		player := field_scene_player(scene, index)
		switch field_player_body_pose(scene, index) {
		case .Hidden:
		case .Standing:
			draw_field_player_body(scene, player.field, field_crouch_progress_of(scene.renderer.crouch_progress[:], index))
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

// Where the viewer's Place would put a run, a foundation's whole block
// (0193) or a machine, on a frame or on bare ground on a frame of its own
// (0201, field_bare_ground_placement), red where the drain would refuse
// it (field_placement_refusal: a drill off every vein, a taken cell, a
// buried player, too few foundations, ground too steep).
draw_field_ghosts :: proc(scene: Field_Scene) {
	if !field_viewer_ghosts_drawn(scene) {
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
	scene := scene
	scene.frame.interiors = gather_interior_lights(&scene.state.world.entities, scene.content.machines)
	set_field_scene_point_lights(scene, camera)
	draw_field(scene.renderer, camera, selection)
	world := &scene.state.world
	push_pod_transform(scene.pod_transform)
	draw_frames(&world.entities, scene.content.machines)
	draw_entities(world, scene.content.machines, scene.models, scene.content.items, scene.frame)
	pop_pod_transform(scene.pod_transform)
	draw_field_trees(scene, camera)
	draw_belt_runs(scene.belts, &world.entities, scene.content.machines, scene.content.items, scene.state.tick, scene.state.tick_rate)
	draw_field_torches(scene.state.field.torches[:], scene.state.field.spacing_millimetres)
	push_pod_transform(scene.pod_transform)
	draw_field_players(scene)
	pop_pod_transform(scene.pod_transform)
	// Before the ghosts, so a ghost cube's depth does not hide them.
	draw_field_flames(scene, camera)
	push_pod_transform(scene.pod_transform)
	draw_field_ghosts(scene)
	pop_pod_transform(scene.pod_transform)
}

// The sky about the camera's up, before the scene.
draw_field_sky :: proc(renderer: ^Sky_Renderer, camera: rl.Camera3D, sky: Day_Sky, satellite: Satellite_Pass) {
	rl.BeginMode3D(field_sky_camera(camera, camera.up))
	draw_sky(renderer, field_sky_camera(camera, camera.up), sky, satellite)
	rl.EndMode3D()
}

// The camera mode a body is seen in: first person while strapped in for
// the descent (0223), the stored mode otherwise, also seated in the chair
// by choice (0268).
field_view_camera_mode :: proc(body: Field_Player) -> Camera_Mode {
	if body.seat == .Strapped {
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
// (the planet's), and the transform the scene draws the pod moved by,
// with the rotation and the travel for the windows; the camera alone
// buffeted at the heat unless motion is reduced (arrival_buffet_offset,
// 0269); the stored camera stays the resting one, so the HUD's
// projections stay on the cabin. Shaken after the hit unless motion is
// reduced, stored for the HUD as field_viewport_camera stores it.
arrival_viewport_camera :: proc(state: ^Frame_State, viewport: ^Viewport, player: Player, camera: rl.Camera3D, view: Arrival_View, pod: Arrival_Pod, rest_tilt_degrees: int) -> (moved: rl.Camera3D, pod_transform: Maybe(matrix[4, 4]f32), rotation: matrix[3, 3]f32, travel: [3]f32) {
	moved = camera
	rotation = 1
	switch view.phase {
	case .None:
	case .Descent:
		curve := &state.presentation.arrival.curve
		transform: matrix[4, 4]f32
		if pod.found {
			transform, rotation, travel = arrival_pod_transform(view, pod.frame, pod.common, pod.machine, rest_tilt_degrees, curve)
		} else {
			up, forward := unit_vector_to_f32(player.field.up), unit_vector_to_f32(player.field.forward)
			transform = linalg.matrix4_translate_f32(arrival_descent_offset(view, up, forward, curve))
			travel = arrival_travel_direction(arrival_curve_at(curve, view.curve_progress), up, forward)
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
	alpha := f32(interpolation_alpha(session.accumulator))
	player := lockstep_view_player(&session.lockstep, &session.simulation, viewport.player)
	view := arrival_view(session.simulation.field.arrival, session.simulation.tick, alpha, state.config, &state.presentation.arrival.curve)
	pod_common, pod, pod_found := find_pod(&session.simulation.world.entities, content.machines)
	pulled, body_shown := field_viewport_camera(state, viewport, player, alpha)
	machine := pod_found ? content.machines.machines[pod_common.machine] : Machine{}
	arrival_pod := Arrival_Pod{common = pod_common, frame = pod, machine = machine, found = pod_found}
	camera, pod_transform, pod_rotation, travel := arrival_viewport_camera(state, viewport, player, pulled, view, arrival_pod, content.field.pod_rest.tilt_degrees)
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
	draw_field_sky(&state.presentation.renderer.sky, camera, field_sky, viewport.presentation.particle_memory.satellite)
	rlgl.SetClipPlanes(FIELD_NEAR_METRES, f64(session.planet.radius_metres * FIELD_FAR_RADII))
	scene := Field_Scene {
		state        = &session.simulation,
		content      = content,
		renderer     = &state.presentation.field_renderer,
		models       = state.presentation.model_renderer,
		belts        = &state.presentation.belt_renderer,
		player_model = state.presentation.player_model,
		frame        = Model_Frame{world = &session.simulation.world, tick = session.simulation.tick, alpha = alpha, tick_rate = session.simulation.tick_rate, day_factor = day_factor(sky.blend), sky_tint = color_to_vector3(sky.colors.sun_tint), open_sky = true, reaching_arm = NO_ENTITY, reduced_motion = state.settings.reduced_motion},
		viewer       = viewport.player,
		viewer_body_shown = body_shown,
		lockstep     = &session.lockstep,
		pod_transform = pod_transform,
		window_lights = window_lights[:window_light_count],
		placement_editor = viewport.interaction.placement_editor,
	}
	rl.BeginMode3D(camera)
	draw_field_scene(scene, camera, frame_field_selection(state))
	if pod_found {
		// The windows draw in the frame's unmoved space, under the pod's
		// transform (nil outside the descent), so the travel goes back
		// through its rotation. The soot stays on them after the landing.
		push_pod_transform(pod_transform)
		draw_arrival_windows(&state.presentation.arrival, view, &session.simulation.world.entities, pod_common, machine, linalg.transpose(pod_rotation) * travel, state.config.arrival_plasma, flickers, seed)
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

// Before the viewports draw: the finished meshes up, the trees round the
// eyes (update_field_tree_cache), the daylight of the shared clock and
// each player's crouch progress (0218), read by value by the draws.
prepare_field_frame :: proc(state: ^Frame_State) {
	session := state.session
	if !state.presentation.field_renderer_ready {
		return
	}
	upload_streamed_field_meshes(&state.presentation.field_renderer, &session.field_streaming)
	update_field_tree_cache(&state.presentation.field_renderer.trees, field_tree_generation(&session.simulation.field), field_viewport_eyes(state))
	state.presentation.field_renderer.daylight = daylight_blend(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks)
	crouch_progress := &state.presentation.field_renderer.crouch_progress
	resize(crouch_progress, len(session.simulation.players))
	for index in 0 ..< len(crouch_progress) {
		crouching := lockstep_view_player(&session.lockstep, &session.simulation, index).field.crouching
		crouch_progress[index] = advance_field_crouch(crouch_progress[index], crouching, state.frame_seconds)
	}
}
