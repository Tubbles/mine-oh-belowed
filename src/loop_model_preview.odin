package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// --model-preview (work item 0207, doc/build.md, The workbench), after
// the precedent of --planet-preview-screenshot: a window, a fixed scene,
// frames drawn, the screen exported, exit. The machine alone on a pad of
// foundation cells under the field's full sky light, the player's capsule
// beside it for scale, from four cameras at rest and at three phases of
// its motion (an arm at its grab, lift and drop fractions): 16 PNG files
// per machine named <machine>_<camera>_<phase>.png. The scene is metres,
// the frame's cells scaled by the pitch about the origin, up +y; no
// world, no session, no field.

// The Xvfb screen of tools/model_preview.sh.
MODEL_PREVIEW_WINDOW_WIDTH :: 1280
MODEL_PREVIEW_WINDOW_HEIGHT :: 720
// Vertical degrees: less distortion than the planet preview's 70.
MODEL_PREVIEW_FIELD_OF_VIEW :: 40
// The margin round the scene's bounding sphere.
MODEL_PREVIEW_FRAMING :: 1.1
// The close front camera's distance from the model's front face.
MODEL_PREVIEW_CLOSE_METRES :: 2
// The three quarter cameras' height share of their direction.
MODEL_PREVIEW_THREE_QUARTER_RISE :: 0.55
// Pad cells round the footprint; an arm's ring is its reach plus 1, so
// its pickup and drop cells lie on the pad.
MODEL_PREVIEW_PAD_RING_CELLS :: 2
// Frames drawn before the first export: a first swap under Xvfb can read
// back empty.
MODEL_PREVIEW_WARM_UP_FRAMES :: 3
// The gripper past the reach, for the framing.
MODEL_PREVIEW_ARM_SLACK_METRES :: 0.3
// The capsule of draw_field_player_capsule: its radius and height.
MODEL_PREVIEW_CAPSULE_RADIUS_METRES :: 0.3
MODEL_PREVIEW_CAPSULE_HEIGHT_METRES :: 1.8

Model_Preview_View :: enum u8 {
	Front,
	Back,
	Top,
	Close,
}

@(rodata)
model_preview_view_names := [Model_Preview_View]string {
	.Front = "front",
	.Back  = "back",
	.Top   = "top",
	.Close = "close",
}

Model_Preview_Phase :: enum u8 {
	Rest,
	Quarter,
	Half,
	Three_Quarters,
}

@(rodata)
model_preview_phase_names := [Model_Preview_Phase]string {
	.Rest           = "rest",
	.Quarter        = "0.25",
	.Half           = "0.5",
	.Three_Quarters = "0.75",
}

// phase is a cycle fraction for the arm.
Model_Preview_Pose :: struct {
	phase:   f32,
	working: bool,
}

Model_Preview_Camera :: struct {
	position, target, up: [3]f32,
}

// Metres.
Model_Preview_Bounds :: struct {
	model_minimum, model_maximum, scene_minimum, scene_maximum: [3]f32,
}

model_preview_pose :: proc(machine: Machine, phase: Model_Preview_Phase) -> Model_Preview_Pose {
	if phase == .Rest {
		return {0, false}
	}
	if machine.motion.kind == .Arm {
		fractions := [Model_Preview_Phase]f32{.Rest = 0, .Quarter = ARM_GRAB_END, .Half = ARM_SWING_MIDDLE, .Three_Quarters = ARM_DROP_FRACTION}
		return {fractions[phase], true}
	}
	phases := [Model_Preview_Phase]f32{.Rest = 0, .Quarter = 0.25, .Half = 0.5, .Three_Quarters = 0.75}
	return {phases[phase], true}
}

// In the temp allocator.
model_preview_file_name :: proc(machine_id: string, view: Model_Preview_View, phase: Model_Preview_Phase) -> string {
	return fmt.tprintf("%s_%s_%s.png", machine_id, model_preview_view_names[view], model_preview_phase_names[phase])
}

// Beside the -z side (the right seen from the front) at its back corner,
// so an arm's swing over +z never passes through it and the front three
// quarter camera, which looks from the front right, sees it beside the
// machine rather than in front of it: 0.2 m clear of the footprint at
// 500 mm.
model_preview_capsule_feet :: proc(pitch_metres: f32) -> [3]f32 {
	return [3]f32{-0.5, 0, -1} * pitch_metres
}

// The model's box (an arm's reach round its post) joined with the
// capsule's.
model_preview_bounds :: proc(machine: Machine, top_cells: f32, pitch_millimetres: int) -> (bounds: Model_Preview_Bounds) {
	pitch := f32(pitch_millimetres) / MILLIMETRES_PER_METRE
	if machine.motion.kind == .Arm {
		reach := f32(model_check_arm_reach(machine, pitch_millimetres)) * pitch + MODEL_PREVIEW_ARM_SLACK_METRES
		dimensions := arm_dimensions_on_frame(model_check_arm_reach(machine, pitch_millimetres), pitch_millimetres)
		post := [3]f32{pitch / 2, 0, pitch / 2}
		bounds.model_minimum = post - {reach, 0, reach}
		bounds.model_maximum = post + {reach, ARM_SHOULDER_HEIGHT_METRES + dimensions.upper_arm, reach}
	} else {
		bounds.model_maximum = [3]f32{f32(machine.footprint.x), top_cells, f32(machine.footprint.z)} * pitch
	}
	feet := model_preview_capsule_feet(pitch)
	capsule_minimum := feet - {MODEL_PREVIEW_CAPSULE_RADIUS_METRES, 0, MODEL_PREVIEW_CAPSULE_RADIUS_METRES}
	capsule_maximum := feet + {MODEL_PREVIEW_CAPSULE_RADIUS_METRES, MODEL_PREVIEW_CAPSULE_HEIGHT_METRES, MODEL_PREVIEW_CAPSULE_RADIUS_METRES}
	bounds.scene_minimum = linalg.min(bounds.model_minimum, capsule_minimum)
	bounds.scene_maximum = linalg.max(bounds.model_maximum, capsule_maximum)
	return bounds
}

// The three quarter cameras and the top one frame the scene's bounding
// sphere; the close one stands MODEL_PREVIEW_CLOSE_METRES in front of
// the model's front face.
model_preview_camera :: proc(view: Model_Preview_View, bounds: Model_Preview_Bounds) -> Model_Preview_Camera {
	centre := (bounds.scene_minimum + bounds.scene_maximum) / 2
	radius := linalg.length(bounds.scene_maximum - bounds.scene_minimum) / 2
	distance := MODEL_PREVIEW_FRAMING * radius / math.sin(f32(MODEL_PREVIEW_FIELD_OF_VIEW) * math.RAD_PER_DEG / 2)
	switch view {
	case .Front:
		return {centre + linalg.normalize([3]f32{1, MODEL_PREVIEW_THREE_QUARTER_RISE, -1}) * distance, centre, {0, 1, 0}}
	case .Back:
		return {centre + linalg.normalize([3]f32{-1, MODEL_PREVIEW_THREE_QUARTER_RISE, 1}) * distance, centre, {0, 1, 0}}
	case .Top:
		return {centre + {0, distance, 0}, centre, {1, 0, 0}}
	case .Close:
	}
	minimum, maximum := bounds.model_minimum, bounds.model_maximum
	target := [3]f32{maximum.x, maximum.y / 2, (minimum.z + maximum.z) / 2}
	return {target + {MODEL_PREVIEW_CLOSE_METRES, 0, 0}, target, {0, 1, 0}}
}

// The pad: foundation cells one below the machine's bottom, ring cells
// round its footprint.
draw_model_preview_pad :: proc(footprint: [3]i32, ring: i32, pitch_metres: f32) {
	flat := transmute([16]f32)uniform_scale_matrix(pitch_metres)
	rlgl.PushMatrix()
	defer rlgl.PopMatrix()
	rlgl.MultMatrixf(raw_data(flat[:]))
	for x in -ring ..= footprint.x - 1 + ring {
		for z in -ring ..= footprint.z - 1 + ring {
			draw_frame_cell({x, -1, z}, FRAME_FOUNDATION_COLOR)
		}
	}
}

// Inside BeginMode3D: the machine (the draw_posed_model sequence without
// the world) or the arm, lit by the field's open sky at full day, then
// the pad and the capsule.
draw_model_preview_scene :: proc(renderer: Model_Renderer, machine: Machine, machine_id: Machine_Id, pose: Model_Preview_Pose, pitch_millimetres: int) {
	pitch := f32(pitch_millimetres) / MILLIMETRES_PER_METRE
	light := model_light_tint(with_light_level(0, .Sky, MAXIMUM_LIGHT), 1, {1, 1, 1})
	glow := emissive_brightness(machine.motion.kind, pose.phase, pose.working, light)
	ring := i32(MODEL_PREVIEW_PAD_RING_CELLS)
	if arm, found := machine_arm_model(renderer, machine_id); found {
		reach := model_check_arm_reach(machine, pitch_millimetres)
		dimensions := arm_dimensions_on_frame(reach, pitch_millimetres)
		transform := uniform_scale_matrix(pitch) * arm_entity_transform(Entity_Common{size = {1, 1, 1}}, pitch_millimetres)
		draw_arm(renderer, arm, transform, dimensions, arm_pose_at(dimensions, pose.phase), light, glow)
		ring = reach + 1
	} else if model, model_found := machine_model(renderer, machine_id); model_found {
		body := uniform_scale_matrix(pitch) * model_transform({}, machine.footprint, 0)
		draw_model_layers(renderer, model.body, body, light, glow)
		draw_model_layers(renderer, model.part, body * motion_transform(machine.motion, machine.footprint, pose.phase), light, glow)
	}
	draw_model_preview_pad(machine.footprint, ring, pitch)
	draw_field_player_capsule(model_preview_capsule_feet(pitch), {0, 1, 0})
}

// Read from the back buffer before the swap and written through
// write_file_replacing; the problem, or "".
save_model_preview_image :: proc(path: string) -> string {
	image := rl.LoadImageFromScreen()
	defer rl.UnloadImage(image)
	size: i32
	data := rl.ExportImageToMemory(image, ".png", &size)
	if data == nil {
		return "cannot encode"
	}
	defer rl.MemFree(data)
	return platform.write_file_replacing(path, ([^]byte)(data)[:size])
}

// One frame of the shot, saved to path unless it is "".
draw_model_preview_frame :: proc(renderer: Model_Renderer, machine: Machine, machine_id: Machine_Id, view: Model_Preview_View, pose: Model_Preview_Pose, top_cells: f32, pitch_millimetres: int, path: string) -> (problem: string) {
	camera := model_preview_camera(view, model_preview_bounds(machine, top_cells, pitch_millimetres))
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(FIELD_FOG_COLOR)
	rl.BeginMode3D(rl.Camera3D{position = camera.position, target = camera.target, up = camera.up, fovy = MODEL_PREVIEW_FIELD_OF_VIEW, projection = .PERSPECTIVE})
	draw_model_preview_scene(renderer, machine, machine_id, pose, pitch_millimetres)
	rl.EndMode3D()
	if path != "" {
		problem = save_model_preview_image(path)
	}
	return problem
}

// The uploaded model's top in cells, 0 for an arm (model_preview_bounds
// ignores it); found false when neither loaded.
model_preview_top :: proc(renderer: Model_Renderer, machine: Machine_Id) -> (top: f32, found: bool) {
	if _, arm_found := machine_arm_model(renderer, machine); arm_found {
		return 0, true
	}
	model := machine_model(renderer, machine) or_return
	return model.top, true
}

// Every shot of the machine: 4 phases by 4 views.
write_model_preview_shots :: proc(renderer: Model_Renderer, machines: Machine_Registry, machine_id: Machine_Id, top: f32, pitch_millimetres: int, directory: string) -> bool {
	machine := machines.machines[machine_id]
	for phase in Model_Preview_Phase {
		for view in Model_Preview_View {
			path := platform.join_path(directory, model_preview_file_name(machine.id, view, phase))
			if problem := draw_model_preview_frame(renderer, machine, machine_id, view, model_preview_pose(machine, phase), top, pitch_millimetres, path); problem != "" {
				platform.log_printf("error: could not write %s: %s", path, problem)
				return false
			}
			platform.log_printf("model preview: wrote %s", path)
		}
	}
	return true
}

// 2 for a bad selection, 1 for a window, a model or a file that failed,
// 0 otherwise.
run_model_preview :: proc(list, directory: string, machines: Machine_Registry, pitch_millimetres: int, data_directory: string) -> int {
	selected, problem := model_workbench_selection(machines, list, false)
	if problem != "" {
		platform.log_printf("error: --model-preview=%s: %s", list, problem)
		return 2
	}
	install_raylib_trace_log()
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(MODEL_PREVIEW_WINDOW_WIDTH, MODEL_PREVIEW_WINDOW_HEIGHT, "Mine oh Belowed model preview")
	if !rl.IsWindowReady() {
		platform.log_printf("error: could not open a window (is a display available?)")
		return 1
	}
	defer rl.CloseWindow()
	renderer := init_model_renderer(machines, data_directory)
	defer destroy_model_renderer(&renderer)
	tops := make([]f32, len(selected), context.temp_allocator)
	for machine_id, index in selected {
		found: bool
		if tops[index], found = model_preview_top(renderer, machine_id); !found {
			platform.log_printf("error: machine %q: its model did not load (the log names the problem)", machines.machines[machine_id].id)
			return 1
		}
	}
	first := machines.machines[selected[0]]
	for _ in 0 ..< MODEL_PREVIEW_WARM_UP_FRAMES {
		draw_model_preview_frame(renderer, first, selected[0], .Front, model_preview_pose(first, .Rest), tops[0], pitch_millimetres, "")
	}
	for machine_id, index in selected {
		if !write_model_preview_shots(renderer, machines, machine_id, tops[index], pitch_millimetres, directory) {
			return 1
		}
	}
	return 0
}
