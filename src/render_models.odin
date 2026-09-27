package game

import rl "vendor:raylib"

// Machine models on the GPU (work item 0055): one mesh per machine that
// names a model (model_mesh.odin builds it), uploaded when the renderer
// starts, after a content reload and when a model file changes, and drawn
// per entity with the entity's transform in place of the coloured box.
// Unlit vertex colours through raylib's default material, like the boxes.

Model_Renderer :: struct {
	material: rl.Material,
	// By Machine_Id; vertexCount 0 for a machine drawn as a box.
	meshes:   []rl.Mesh,
}

// The machine's uploaded mesh, or found false for the box.
machine_model_mesh :: proc(renderer: Model_Renderer, machine: Machine_Id) -> (mesh: rl.Mesh, found: bool) {
	if int(machine) >= len(renderer.meshes) || renderer.meshes[machine].vertexCount == 0 {
		return {}, false
	}
	return renderer.meshes[machine], true
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

unload_model_meshes :: proc(renderer: ^Model_Renderer) {
	for mesh in renderer.meshes {
		if mesh.vertexCount > 0 {
			rl.UnloadMesh(mesh)
		}
	}
	delete(renderer.meshes)
	renderer.meshes = nil
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
	renderer.meshes = make([]rl.Mesh, len(meshes))
	for mesh, index in meshes {
		renderer.meshes[index] = upload_model_mesh(mesh)
	}
	return ""
}

// The machine table changed (start, content reload): a model that does
// not load leaves every machine a box, since old meshes would follow old
// Machine_Ids.
use_machine_models :: proc(renderer: ^Model_Renderer, machines: Machine_Registry, data_directory: string) {
	if problem := replace_machine_models(renderer, machines, data_directory); problem != "" {
		log_printf("error: %s; machines are drawn as boxes", problem)
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

// False when the machine has no model, so the caller draws the box.
draw_machine_model :: proc(renderer: Model_Renderer, common: Entity_Common) -> bool {
	mesh := machine_model_mesh(renderer, common.machine) or_return
	rl.DrawMesh(mesh, renderer.material, cast(rl.Matrix)model_transform(common.origin, common.size, common.rotation))
	return true
}
