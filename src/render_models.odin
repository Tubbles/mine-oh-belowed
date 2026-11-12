package game

import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// Machine models on the GPU (work items 0055 and 0056): per machine that
// names a model, the body and the moving part, each as a lit and an
// emissive mesh (model_mesh.odin builds them), uploaded when the renderer
// starts, after a content reload and when a model file changes, and drawn
// per entity with the entity's transform in place of the coloured box.
// The material's diffuse colour multiplies the vertex colours; it carries
// the light tint for the lit meshes and the glow brightness for the
// emissive ones (model_motion.odin). The lit layer draws with the model
// shader (data/shaders/model.vs, model.fs, work item 0224), which adds the
// point lights (set_model_point_lights) and the torchlight (0297,
// set_model_spot_light), and on the field takes the open sky's light by
// the normal in place of the CPU's flat light, and the haze (0313,
// set_model_open_sky); the emissive layer draws with
// raylib's default material, so it never takes them. A model shader that
// fails to load leaves the lit layer on the default material too. On the
// field (0347) both layers draw instanced through the model shader, the
// emissive one in its flat mode, which is the default shader's colour
// hazed on the open sky (0360, render_model_instances.odin); the pod,
// the ghosts and the workbench still draw one by one. The field's trees
// draw with a shader of their own (0310, Tree_Draw,
// render_field_trees.odin), which takes the same lights; their far cards
// are baked from the tree models whenever the models load.

MODEL_VERTEX_SHADER_PATH :: "shaders/model.vs"
MODEL_FRAGMENT_SHADER_PATH :: "shaders/model.fs"

Uploaded_Layers :: [Model_Layer]rl.Mesh

// bounds holds each slot's mesh box from the CPU meshes, which the
// instanced draws' cull reads (0347, render_model_instances.odin).
Uploaded_Machine_Model :: struct {
	body:   Uploaded_Layers,
	part:   Uploaded_Layers,
	arm:    [Arm_Part]Uploaded_Layers,
	top:    f32,
	bounds: [Model_Mesh_Slot]Model_Bounds,
}

Model_Renderer :: struct {
	// The lit layer's: the model shader, or raylib's default when it did
	// not load.
	material:              rl.Material,
	// The emissive layer's: raylib's default.
	emissive_material:     rl.Material,
	// The model shader's point light uniforms (set_model_point_lights):
	// the positions, the colours and the clip boxes (0229).
	point_light_locations: [3]i32,
	point_lights_ready:    bool,
	// The torchlight's uniforms (0297, set_model_spot_light, the order of
	// spot_light_locations).
	spot_locations:        [6]i32,
	// The open sky's uniforms (0313, set_model_open_sky) and the switch,
	// the flat light divided out and the eye.
	open_sky_locations:       [Open_Sky_Uniform]i32,
	outdoor_on_location:      i32,
	daylight_tint_location:   i32,
	camera_position_location: i32,
	// The sun's shadow's uniforms (0328, use_sun_shadow_sampler).
	sun_shadow_locations:     [Sun_Shadow_Uniform]i32,
	// By Machine_Id; no vertices in the body for a machine drawn as a box.
	models:                []Uploaded_Machine_Model,
	// The furnaces' and the torches' flames (render_flames.odin, 0274).
	flame:                 Flame_Shader,
	// The field's trees (0310, render_field_trees.odin): their shader,
	// the cards' atlas and the cards by Machine_Id.
	trees:                 Tree_Draw,
	// Counts the unloads of the meshes (unload_model_meshes, so every
	// model and content reload), so the sun's kept shadow maps draw again
	// (0348) and the foundations' bricks are built again with the tiers'
	// colours (0347, refresh_field_foundations).
	revision:              u64,
	// The model shader's instancing switches (0347,
	// render_model_instances.odin): ready when the shader loaded with all
	// three, else every model draws one by one.
	instanced_location:     i32,
	instance_tint_location: i32,
	flat_location:          i32,
	instancing_ready:       bool,
	// rlgl's batch may draw through the flat mode (0360,
	// begin_flat_batch): the instancing uniforms and texture0 found.
	flat_batch_ready:       bool,
	// The foundations' slab and its edges as lines (0347,
	// draw_field_foundations) and the belt items' cube.
	unit_cube:              rl.Mesh,
	cube_edges:             rl.Mesh,
	// glDrawArraysInstanced, nil without it: the edges then draw one by
	// one.
	draw_lines_instanced:   Gl_Draw_Arrays_Instanced,
}

// What every model drawn this frame shares: the world for the light, the
// render time for the motion, and the day factor and sky tint for the sky
// light. open_sky lights every model with the full sky light: a field
// session's machines stand on frames the block light does not reach
// (work item 0179). reaching_arm is an arm drawn held at full reach and
// working whatever its cycle (the planet preview's screenshot), NO_ENTITY
// otherwise. interiors are the pods' boxes whose models and players take
// the pod's interior light share (0225, gather_interior_lights); nil
// outside a field scene, which leaves every share 1. reduced_motion is
// the setting: it stills the flames' flicker and the embers' pulse (0274).
// casters is set by the sun's cast pass (0328, draw_field_sun_shadows):
// draw_entities leaves out an entity whose box lies outside the casters'
// box (model_frame_draws_entity); nil draws every one. The field's passes
// set the rest (0347, render_model_instances.odin), each nil for the
// draws of before:
// view is the scene's cull by the frustum and the haze's end;
// instances collects the shown models' pieces, drawn instanced after
// draw_entities;
// frames is the pass's table of the frames' matrices.
Model_Frame :: struct {
	world:          ^World,
	tick:           u64,
	alpha:          f32,
	tick_rate:      int,
	day_factor:     f32,
	sky_tint:       [3]f32,
	open_sky:       bool,
	reaching_arm:   Entity_Handle,
	interiors:      []Interior_Light,
	reduced_motion: bool,
	casters:        ^Sun_Shadow_Casters,
	view:           ^Model_View,
	instances:      ^[dynamic]Model_Instance,
	frames:         ^Frame_Matrix_Table,
}

// The frame's time on the tick clock, so a paused game stills what reads
// it (the flames, 0274) and a screenshot reproduces.
model_frame_seconds :: proc(frame: Model_Frame) -> f64 {
	return (f64(frame.tick) + f64(frame.alpha)) / f64(max(frame.tick_rate, 1))
}

// A pod's box of cells on its frame (inclusive, the rotated size from its
// origin) and its interior_light_share (work item 0225).
Interior_Light :: struct {
	frame: Frame,
	box:   Cell_Box,
	share: f32,
}

// Every alive pod's box on its frame with its share, once per scene.
gather_interior_lights :: proc(entities: ^Entities, machines: Machine_Registry, allocator := context.temp_allocator) -> []Interior_Light {
	interiors := make([dynamic]Interior_Light, allocator)
	for entry in entities.foundations.entries {
		if !entry.alive || int(entry.machine) >= len(machines.machines) {
			continue
		}
		machine := machines.machines[entry.machine]
		frame, found := find_frame(&entities.frames, entry.frame)
		if machine.kind != .Pod || !found {
			continue
		}
		box := Cell_Box{from = cast([3]i32)entry.origin, to = cast([3]i32)entry.origin + entry.size - 1}
		append(&interiors, Interior_Light{frame = frame, box = box, share = machine.interior_light_share})
	}
	return interiors[:]
}

// The share of the first pod whose box on the frame holds the cell, else 1.
model_interior_light_share :: proc(interiors: []Interior_Light, frame: Frame_Id, cell: World_Coordinate) -> f32 {
	for interior in interiors {
		if interior.frame.id == frame && cell_box_contains(interior.box, cast([3]i32)cell) {
			return interior.share
		}
	}
	return 1
}

// The share of the first pod whose box holds the player's feet cell, else 1.
field_player_interior_light_share :: proc(interiors: []Interior_Light, player: Field_Player) -> f32 {
	for interior in interiors {
		if cell_box_contains(interior.box, cast([3]i32)frame_cell_of_feet(interior.frame, player)) {
			return interior.share
		}
	}
	return 1
}

// The light a model at the cell takes.
model_frame_light :: proc(frame: Model_Frame, cell: World_Coordinate) -> u16 {
	if frame.open_sky {
		return with_light_level(0, .Sky, MAXIMUM_LIGHT)
	}
	return world_get_light(frame.world, cell)
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
// footprint's height for a machine drawn as a box. An arm's top is its
// folded rest on the block frame (load_machine_model_mesh).
machine_model_top :: proc(renderer: Model_Renderer, common: Entity_Common) -> f32 {
	if model, found := machine_model(renderer, common.machine); found {
		return model.top
	}
	if _, found := machine_arm_model(renderer, common.machine); found {
		return renderer.models[common.machine].top
	}
	return f32(common.size.y)
}

// The counts an upload gives raylib, pure so a test reads them without a
// window.
model_mesh_upload_counts :: proc(mesh: Model_Mesh) -> (vertex_count, triangle_count: i32, indexed: bool) {
	return i32(len(mesh.positions)), i32(model_mesh_triangle_count(mesh)), len(mesh.indices) > 0
}

// A voxel layer goes up indexed, a triangle layer (no indices, 0226)
// unindexed: raylib's DrawMesh draws vertexCount vertices in order when
// indices is nil.
upload_model_mesh :: proc(mesh: Model_Mesh) -> rl.Mesh {
	if len(mesh.positions) == 0 {
		return {}
	}
	vertex_count, triangle_count, indexed := model_mesh_upload_counts(mesh)
	uploaded := rl.Mesh {
		vertexCount   = vertex_count,
		triangleCount = triangle_count,
		vertices      = cast([^]f32)clone_for_raylib(mesh.positions[:]),
		normals       = cast([^]f32)clone_for_raylib(mesh.normals[:]),
		colors        = cast([^]u8)clone_for_raylib(mesh.colors[:]),
		indices       = nil,
	}
	if indexed {
		uploaded.indices = clone_for_raylib(mesh.indices[:])
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
		for layers in model.arm {
			unload_model_layers(layers)
		}
	}
	delete(renderer.models)
	renderer.models = nil
	renderer.revision += 1
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
	replace_tree_cards(&renderer.trees, meshes, machines)
	renderer.models = make([]Uploaded_Machine_Model, len(meshes))
	for mesh, index in meshes {
		renderer.models[index] = {
			body   = upload_model_layers(mesh.body),
			part   = upload_model_layers(mesh.part),
			top    = mesh.top,
			bounds = machine_model_bounds(mesh),
		}
		for layers, part in mesh.arm {
			renderer.models[index].arm[part] = upload_model_layers(layers)
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

// The lit layer takes the model shader; when it does not load, the
// default material stays and the models draw without point lights.
use_model_shader :: proc(renderer: ^Model_Renderer, data_directory: string) {
	shader, ok := load_shader_pair(data_directory, MODEL_VERTEX_SHADER_PATH, MODEL_FRAGMENT_SHADER_PATH, "model")
	if !ok {
		platform.log_printf("models: the model shader did not load; models draw without point lights")
		return
	}
	renderer.material.shader = shader
	renderer.point_light_locations = {rl.GetShaderLocation(shader, "point_light_positions"), rl.GetShaderLocation(shader, "point_light_colors"), rl.GetShaderLocation(shader, "point_light_boxes")}
	renderer.spot_locations = spot_light_locations(shader)
	renderer.open_sky_locations = open_sky_locations(shader)
	renderer.outdoor_on_location = rl.GetShaderLocation(shader, "outdoor_on")
	renderer.daylight_tint_location = rl.GetShaderLocation(shader, "daylight_tint")
	renderer.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	renderer.sun_shadow_locations = use_sun_shadow_sampler(shader)
	renderer.point_lights_ready = true
	renderer.instanced_location = rl.GetShaderLocation(shader, "instanced_on")
	renderer.instance_tint_location = rl.GetShaderLocation(shader, "instance_tint_on")
	renderer.flat_location = rl.GetShaderLocation(shader, "flat_on")
	renderer.instancing_ready = renderer.instanced_location != -1 && renderer.instance_tint_location != -1 && renderer.flat_location != -1
	if !renderer.instancing_ready {
		platform.log_printf("models: the model shader has no instancing uniforms, machines draw one by one")
	}
	renderer.flat_batch_ready = renderer.instancing_ready && shader.locs[int(rl.ShaderLocationIndex.MAP_ALBEDO)] != -1
	if renderer.instancing_ready && !renderer.flat_batch_ready {
		platform.log_printf("models: the model shader samples no texture0, the runs and the torch boxes draw unhazed")
	}
}

// Needs the window.
init_model_renderer :: proc(machines: Machine_Registry, data_directory: string) -> (renderer: Model_Renderer) {
	renderer.material = rl.LoadMaterialDefault()
	renderer.emissive_material = rl.LoadMaterialDefault()
	use_model_shader(&renderer, data_directory)
	use_flame_shader(&renderer, data_directory)
	use_tree_shader(&renderer.trees, data_directory)
	use_machine_models(&renderer, machines, data_directory)
	renderer.unit_cube = upload_model_mesh(unit_cube_mesh())
	renderer.cube_edges = upload_model_mesh(cube_edge_mesh(FRAME_EDGE_COLOR))
	renderer.draw_lines_instanced = load_draw_arrays_instanced()
	if renderer.draw_lines_instanced == nil {
		platform.log_printf("models: no glDrawArraysInstanced, the foundations' edges draw one by one")
	}
	return renderer
}

// UnloadMaterial unloads the model shader with the lit material and keeps
// raylib's default shader and texture.
destroy_model_renderer :: proc(renderer: ^Model_Renderer) {
	unload_model_meshes(renderer)
	for mesh in ([2]rl.Mesh{renderer.unit_cube, renderer.cube_edges}) {
		if mesh.vertexCount > 0 {
			rl.UnloadMesh(mesh)
		}
	}
	renderer.unit_cube, renderer.cube_edges = {}, {}
	rl.UnloadMaterial(renderer.material)
	rl.UnloadMaterial(renderer.emissive_material)
	if renderer.flame.ready {
		rl.UnloadShader(renderer.flame.shader)
	}
	renderer.flame = {}
	destroy_tree_draw(&renderer.trees)
}

// The material a layer draws with: the emissive layer never takes the
// point lights.
model_layer_material :: proc(renderer: Model_Renderer, layer: Model_Layer) -> rl.Material {
	if layer == .Emissive {
		return renderer.emissive_material
	}
	return renderer.material
}

// Point lights (0224): the same nearest lights the field shader takes,
// uploaded before the models draw, with the clip boxes (0229). Nothing
// without the model shader.
set_model_point_lights :: proc(renderer: Model_Renderer, lights: [MAXIMUM_POINT_LIGHTS]Point_Light) {
	if !renderer.point_lights_ready {
		return
	}
	positions, colors, boxes := point_light_uniform_values(lights)
	rl.SetShaderValueV(renderer.material.shader, renderer.point_light_locations[0], &positions, .VEC4, MAXIMUM_POINT_LIGHTS)
	rl.SetShaderValueV(renderer.material.shader, renderer.point_light_locations[1], &colors, .VEC4, MAXIMUM_POINT_LIGHTS)
	rl.SetShaderValueV(renderer.material.shader, renderer.point_light_locations[2], &boxes, .VEC4, MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS)
	if renderer.trees.ready {
		shader := renderer.trees.material.shader
		locations := renderer.trees.point_light_locations
		rl.SetShaderValueV(shader, locations[0], &positions, .VEC4, MAXIMUM_POINT_LIGHTS)
		rl.SetShaderValueV(shader, locations[1], &colors, .VEC4, MAXIMUM_POINT_LIGHTS)
		rl.SetShaderValueV(shader, locations[2], &boxes, .VEC4, MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS)
	}
}

// The torchlight (0297): the field's spot, the same the field shader
// takes, uploaded before the models draw. Nothing without the model
// shader.
set_model_spot_light :: proc(renderer: Model_Renderer, spot: Spot_Light) {
	if !renderer.point_lights_ready {
		return
	}
	set_spot_light_uniforms(renderer.material.shader, renderer.spot_locations, spot)
	if renderer.trees.ready {
		set_spot_light_uniforms(renderer.trees.material.shader, renderer.trees.spot_locations, spot)
	}
}

// The flat light the CPU multiplies into an open sky model's diffuse
// colour (0313): what model_light_tint gives a full sky light, before
// its clamp; the model shader divides it out.
model_frame_daylight_tint :: proc(frame: Model_Frame) -> [3]f32 {
	return frame.day_factor * frame.sky_tint
}

// The field's open sky on the lit layer (0313): the light and the haze
// for the viewer, the sun's shadow (0328), the flat light to divide out
// and the eye; outdoor_on 1. Nothing without the model shader.
set_model_open_sky :: proc(renderer: Model_Renderer, lights: Field_Frame_Lights, daylight_tint, eye: [3]f32) {
	if !renderer.point_lights_ready {
		return
	}
	shader := renderer.material.shader
	set_open_sky_uniforms(shader, renderer.open_sky_locations, lights)
	set_sun_shadow_uniforms(shader, renderer.sun_shadow_locations, lights.sun_shadow)
	daylight_tint, eye := daylight_tint, eye
	rl.SetShaderValue(shader, renderer.daylight_tint_location, &daylight_tint, .VEC3)
	rl.SetShaderValue(shader, renderer.camera_position_location, &eye, .VEC3)
	set_model_outdoor_on(renderer, 1)
	if renderer.trees.ready {
		trees := renderer.trees
		set_open_sky_uniforms(trees.material.shader, trees.open_sky_locations, lights)
		set_sun_shadow_uniforms(trees.material.shader, trees.sun_shadow_locations, lights.sun_shadow)
		rl.SetShaderValue(trees.material.shader, trees.daylight_tint_location, &daylight_tint, .VEC3)
		rl.SetShaderValue(trees.material.shader, trees.camera_position_location, &eye, .VEC3)
	}
}

// The lit layer back to the CPU's light (0313): the ghosts and the block
// world. Nothing without the model shader.
clear_model_open_sky :: proc(renderer: Model_Renderer) {
	if !renderer.point_lights_ready {
		return
	}
	set_model_outdoor_on(renderer, 0)
}

set_model_outdoor_on :: proc(renderer: Model_Renderer, on: f32) {
	on := on
	rl.SetShaderValue(renderer.material.shader, renderer.outdoor_on_location, &on, .FLOAT)
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
			material := model_layer_material(renderer, layer)
			material.maps[rl.MaterialMapIndex.ALBEDO].color = colors[layer]
			rl.DrawMesh(mesh, material, cast(rl.Matrix)transform)
			count_draw_call()
		}
	}
}

// The machine's model at a placement, the part at rest, tinted with the
// ghost colour. False when the machine has no model, so the caller draws
// the box.
draw_ghost_model :: proc(renderer: Model_Renderer, machines: Machine_Registry, placement: Placement, tint: rl.Color) -> bool {
	machine := machines.machines[placement.machine]
	colors := ghost_layer_colors(tint)
	if arm, found := machine_arm_model(renderer, placement.machine); found {
		common := Entity_Common{origin = placement.origin, size = placement.size, rotation = placement.rotation}
		dimensions := arm_dimensions_on_frame(machine.inserter_reach, BLOCK_FRAME_PITCH_MILLIMETRES)
		draw_arm_colored(renderer, arm, arm_entity_transform(common, BLOCK_FRAME_PITCH_MILLIMETRES), dimensions, arm_rest_pose(dimensions), colors)
		return true
	}
	model := machine_model(renderer, placement.machine) or_return
	body := model_transform(placement.origin, placement.size, placement.rotation)
	draw_model_layers_colored(renderer, model.body, body, colors)
	// An iris's ghost is the shut iris, every blade (0231).
	poses := motion_part_transforms(machine.motion, machine.footprint, 0)
	for transform in poses.transforms[:poses.count] {
		draw_model_layers_colored(renderer, model.part, body * transform, colors)
	}
	return true
}

// The placement editor's anchored ghost (0215): the machine's model on
// its frame, the part at rest, tinted with the ghost colour and drawn
// without writing depth, so its far side shows through its near side.
// False for an arm machine or one without a model, so the caller draws
// the boxes.
draw_frame_ghost_model :: proc(renderer: Model_Renderer, machines: Machine_Registry, frame: Frame, machine: Machine_Id, origin: World_Coordinate, rotation: u8, tint: rl.Color) -> bool {
	if _, arm := machine_arm_model(renderer, machine); arm {
		return false
	}
	model := machine_model(renderer, machine) or_return
	definition := machines.machines[machine]
	colors := ghost_layer_colors(tint)
	body := frame_render_matrix(frame) * model_transform(origin, rotated_footprint_size(definition.footprint, rotation), rotation)
	rlgl.DisableDepthMask()
	defer rlgl.EnableDepthMask()
	draw_model_layers_colored(renderer, model.body, body, colors)
	poses := motion_part_transforms(definition.motion, definition.footprint, 0)
	for transform in poses.transforms[:poses.count] {
		draw_model_layers_colored(renderer, model.part, body * transform, colors)
	}
	return true
}

// The model's body on its frame, in the world's metres: where the model is
// drawn and where its lamps sit (append_machine_lights).
entity_body_matrix :: proc(entities: ^Entities, common: Entity_Common) -> matrix[4, 4]f32 {
	return entity_frame_matrix(entities, common.frame) * model_transform(common.origin, common.size, common.rotation)
}

// A broken machine's model (0201) is drawn this much of its light.
BROKEN_MODEL_TINT :: 0.35

// The light tint of the entity's lit layers and the brightness of its
// emissive ones: the light of the cell model_light_cell names, at its
// pod's interior light share inside a pod's box (0225), darkened while
// broken. A working model's emissive layers keep their brightness, an
// idle one's follow the tint; a working machine with flames pulses its
// whole emissive layer with the embers (flame_ember_glow, 0274).
posed_model_light :: proc(frame: Model_Frame, common: Entity_Common, machine: Machine, pose: Model_Pose) -> (light_tint, glow: [3]f32) {
	sky_light := model_light_tint(model_frame_light(frame, model_light_cell(common)), frame.day_factor, frame.sky_tint)
	light_tint = interior_light_tint(sky_light, model_interior_light_share(frame.interiors, common.frame, common.origin))
	if common.broken {
		light_tint *= BROKEN_MODEL_TINT
	}
	glow = emissive_brightness(machine.motion.kind, pose.phase, pose.working, light_tint)
	if pose.working && machine.flame_count > 0 {
		glow *= flame_ember_glow(model_frame_seconds(frame), flame_salt(common.origin, common.frame), frame.reduced_motion)
	}
	return light_tint, glow
}

// The entity's model at the pose, lit by the cell model_light_cell names,
// at its pod's interior light share inside a pod's box (0225), darkened
// while broken. The part once per pose of motion_part_transforms: an
// iris's every blade (0231). Posed first and left out when the pass does
// not show its posed box (0347, model_frame_shows_box), which shown says;
// then drawn or appended to the pass's instances (emit_posed_model).
draw_posed_model :: proc(renderer: Model_Renderer, common: Entity_Common, machine: Machine, frame: Model_Frame, pose: Model_Pose) -> (shown: bool) {
	body := model_frame_entity_matrix(frame, &frame.world.entities, common.frame) * model_transform(common.origin, common.size, common.rotation)
	posed := pose_machine_model(renderer, common.machine, body, machine, pose.phase)
	if !model_frame_shows_box(frame, posed.minimum, posed.maximum) {
		return false
	}
	light_tint, glow := posed_model_light(frame, common, machine, pose)
	emit_posed_model(renderer, frame, common.machine, machine.kind, posed, {.Lit = brightness_color(light_tint), .Emissive = brightness_color(glow)})
	return true
}

// The pose of a machine whose part runs on the clock while it works, at
// its own offset into the period.
clock_pose :: proc(frame: Model_Frame, common: Entity_Common, machine: Machine, working: bool) -> Model_Pose {
	offset := motion_phase_offset(common.origin, common.frame)
	return {phase = motion_phase(frame.tick, frame.alpha, frame.tick_rate, machine.motion.period_seconds, working, offset), working = working}
}

// A hatch's pose (0198): the door's slide, spin or iris (0231) follows the
// hatch's state, not the clock, and its strips glow while it is open.
hatch_pose :: proc(frame: Model_Frame, hatch: Foundation, machine: Machine) -> Model_Pose {
	return {phase = hatch_open_fraction(hatch.hatch_open, hatch.hatch_toggle_tick, frame.tick, frame.alpha, frame.tick_rate, machine.motion.period_seconds), working = hatch.hatch_open}
}

// False when the machine has no model, so the caller draws the box; true
// for a model the pass left out too.
draw_machine_model :: proc(renderer: Model_Renderer, machines: Machine_Registry, common: Entity_Common, frame: Model_Frame, working: bool) -> bool {
	if _, found := machine_model(renderer, common.machine); !found {
		return false
	}
	machine := machines.machines[common.machine]
	draw_posed_model(renderer, common, machine, frame, clock_pose(frame, common, machine, working))
	return true
}
