package game

import rl "shared:raylib"
import "platform"

// Machine models on the GPU (work items 0055 and 0056): per machine that
// names a model, the body and the moving part, each as a lit and an
// emissive mesh (model_mesh.odin builds them), uploaded when the renderer
// starts, after a content reload and when a model file changes, and drawn
// per entity with the entity's transform in place of the coloured box.
// raylib's default material multiplies the vertex colours by its diffuse
// colour, which carries the light tint for the lit meshes and the glow
// brightness for the emissive ones (model_motion.odin), so no shader of
// our own is needed.

Uploaded_Layers :: [Model_Layer]rl.Mesh

Uploaded_Machine_Model :: struct {
	body: Uploaded_Layers,
	part: Uploaded_Layers,
	top:  f32,
}

Model_Renderer :: struct {
	material: rl.Material,
	// By Machine_Id; no vertices in the body for a machine drawn as a box.
	models:   []Uploaded_Machine_Model,
}

// What every model drawn this frame shares: the world for the light, the
// render time for the motion, and the day factor and sky tint for the sky
// light.
Model_Frame :: struct {
	world:      ^World,
	tick:       u64,
	alpha:      f32,
	tick_rate:  int,
	day_factor: f32,
	sky_tint:   [3]f32,
}

// The pose of one entity's model this frame.
Model_Pose :: struct {
	phase:   f32,
	working: bool,
}

layers_have_vertices :: proc(layers: Uploaded_Layers) -> bool {
	return layers[.Lit].vertexCount > 0 || layers[.Emissive].vertexCount > 0
}

// The machine's uploaded model, or found false for the box.
machine_model :: proc(renderer: Model_Renderer, machine: Machine_Id) -> (model: Uploaded_Machine_Model, found: bool) {
	if int(machine) >= len(renderer.models) || !layers_have_vertices(renderer.models[machine].body) {
		return {}, false
	}
	return renderer.models[machine], true
}

// The height of the model's top above the entity's bottom, or the
// footprint's height for a machine drawn as a box.
machine_model_top :: proc(renderer: Model_Renderer, common: Entity_Common) -> f32 {
	if model, found := machine_model(renderer, common.machine); found {
		return model.top
	}
	return f32(common.size.y)
}

upload_model_mesh :: proc(mesh: Model_Mesh) -> rl.Mesh {
	if len(mesh.positions) == 0 {
		return {}
	}
	uploaded := rl.Mesh {
		vertexCount   = i32(len(mesh.positions)),
		triangleCount = i32(len(mesh.indices) / 3),
		vertices      = cast([^]f32)clone_for_raylib(mesh.positions[:]),
		colors        = cast([^]u8)clone_for_raylib(mesh.colors[:]),
		indices       = clone_for_raylib(mesh.indices[:]),
	}
	rl.UploadMesh(&uploaded, false)
	return uploaded
}

upload_model_layers :: proc(meshes: Model_Layers) -> (uploaded: Uploaded_Layers) {
	for mesh, layer in meshes {
		uploaded[layer] = upload_model_mesh(mesh)
	}
	return uploaded
}

unload_model_layers :: proc(layers: Uploaded_Layers) {
	for mesh in layers {
		if mesh.vertexCount > 0 {
			rl.UnloadMesh(mesh)
		}
	}
}

unload_model_meshes :: proc(renderer: ^Model_Renderer) {
	for model in renderer.models {
		unload_model_layers(model.body)
		unload_model_layers(model.part)
	}
	delete(renderer.models)
	renderer.models = nil
}

// Loads every machine's model from the files and replaces the meshes. On
// a problem the old meshes stay; they still match the machines only when
// the machine table did not change.
replace_machine_models :: proc(renderer: ^Model_Renderer, machines: Machine_Registry, data_directory: string) -> string {
	meshes, problem := load_machine_model_meshes(machines, data_directory, context.temp_allocator)
	if problem != "" {
		return problem
	}
	unload_model_meshes(renderer)
	renderer.models = make([]Uploaded_Machine_Model, len(meshes))
	for mesh, index in meshes {
		renderer.models[index] = {
			body = upload_model_layers(mesh.body),
			part = upload_model_layers(mesh.part),
			top  = mesh.top,
		}
	}
	return ""
}

// The machine table changed (start, content reload): a model that does
// not load leaves every machine a box, since old meshes would follow old
// Machine_Ids.
use_machine_models :: proc(renderer: ^Model_Renderer, machines: Machine_Registry, data_directory: string) {
	if problem := replace_machine_models(renderer, machines, data_directory); problem != "" {
		platform.log_printf("error: %s; machines are drawn as boxes", problem)
		unload_model_meshes(renderer)
	}
}

// Needs the window.
init_model_renderer :: proc(machines: Machine_Registry, data_directory: string) -> (renderer: Model_Renderer) {
	renderer.material = rl.LoadMaterialDefault()
	use_machine_models(&renderer, machines, data_directory)
	return renderer
}

// UnloadMaterial keeps raylib's default shader and texture.
destroy_model_renderer :: proc(renderer: ^Model_Renderer) {
	unload_model_meshes(renderer)
	rl.UnloadMaterial(renderer.material)
}

brightness_color :: proc(brightness: [3]f32) -> rl.Color {
	value := [3]u8{}
	for channel, index in brightness {
		value[index] = u8(clamp(channel, 0, 1) * 255 + 0.5)
	}
	return {value.r, value.g, value.b, 255}
}

// The material's diffuse colour multiplies the vertex colours.
draw_model_layers :: proc(renderer: Model_Renderer, layers: Uploaded_Layers, transform: matrix[4, 4]f32, light_tint, glow: [3]f32) {
	colors := [Model_Layer]rl.Color {
		.Lit      = brightness_color(light_tint),
		.Emissive = brightness_color(glow),
	}
	draw_model_layers_colored(renderer, layers, transform, colors)
}

// Both layers of a placement ghost take the ghost colour, alpha included,
// at full brightness, so the ghost reads in the dark.
ghost_layer_colors :: proc(tint: rl.Color) -> [Model_Layer]rl.Color {
	return {.Lit = tint, .Emissive = tint}
}

// raylib's default blend mode is alpha blending, so a colour's alpha
// makes the mesh translucent.
draw_model_layers_colored :: proc(renderer: Model_Renderer, layers: Uploaded_Layers, transform: matrix[4, 4]f32, colors: [Model_Layer]rl.Color) {
	for mesh, layer in layers {
		if mesh.vertexCount > 0 {
			renderer.material.maps[rl.MaterialMapIndex.ALBEDO].color = colors[layer]
			rl.DrawMesh(mesh, renderer.material, cast(rl.Matrix)transform)
		}
	}
}

// The machine's model at a placement, the part at rest, tinted with the
// ghost colour. False when the machine has no model, so the caller draws
// the box.
draw_ghost_model :: proc(renderer: Model_Renderer, machines: Machine_Registry, placement: Placement, tint: rl.Color) -> bool {
	model := machine_model(renderer, placement.machine) or_return
	machine := machines.machines[placement.machine]
	colors := ghost_layer_colors(tint)
	body := model_transform(placement.origin, placement.size, placement.rotation)
	draw_model_layers_colored(renderer, model.body, body, colors)
	part := body * motion_transform(machine.motion, machine.footprint, 0)
	draw_model_layers_colored(renderer, model.part, part, colors)
	return true
}

// The entity's model at the pose, lit by the cell model_light_cell names.
draw_posed_model :: proc(renderer: Model_Renderer, model: Uploaded_Machine_Model, common: Entity_Common, machine: Machine, frame: Model_Frame, pose: Model_Pose) {
	light_tint := model_light_tint(world_get_light(frame.world, model_light_cell(common)), frame.day_factor, frame.sky_tint)
	glow := emissive_brightness(machine.motion.kind, pose.phase, pose.working, light_tint)
	body := entity_frame_matrix(&frame.world.entities, common.frame) * model_transform(common.origin, common.size, common.rotation)
	draw_model_layers(renderer, model.body, body, light_tint, glow)
	part := body * motion_transform(machine.motion, machine.footprint, pose.phase)
	draw_model_layers(renderer, model.part, part, light_tint, glow)
}

// The pose of a machine whose part runs on the clock while it works, at
// its own offset into the period.
clock_pose :: proc(frame: Model_Frame, common: Entity_Common, machine: Machine, working: bool) -> Model_Pose {
	offset := motion_phase_offset(common.origin)
	return {phase = motion_phase(frame.tick, frame.alpha, frame.tick_rate, machine.motion.period_seconds, working, offset), working = working}
}

// False when the machine has no model, so the caller draws the box.
draw_machine_model :: proc(renderer: Model_Renderer, machines: Machine_Registry, common: Entity_Common, frame: Model_Frame, working: bool) -> bool {
	model := machine_model(renderer, common.machine) or_return
	machine := machines.machines[common.machine]
	draw_posed_model(renderer, model, common, machine, frame, clock_pose(frame, common, machine, working))
	return true
}
