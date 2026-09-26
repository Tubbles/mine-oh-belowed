package game

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

CHUNK_VERTEX_SHADER_PATH :: "shaders/chunk.vs"
CHUNK_FRAGMENT_SHADER_PATH :: "shaders/chunk.fs"

SKY_COLOR :: rl.Color{150, 190, 230, 255}
// The debug terrain is 256 blocks across, so the fog reaches its far side
// from the middle.
FOG_START :: 96.0
FOG_END :: 160.0
CAMERA_FIELD_OF_VIEW_DEGREES :: 70.0

// One raylib mesh per part: a chunk only needs more than one when it
// exceeds the u16 index range (MESH_PART_VERTEX_LIMIT).
Chunk_Render :: struct {
	meshes:       [dynamic]rl.Mesh,
	vertex_count: int,
}

Chunk_Renderer :: struct {
	atlas_layout:             Atlas_Layout,
	material:                 rl.Material,
	camera_position_location: i32,
	chunk_meshes:             map[Chunk_Coordinate]Chunk_Render,
	drawn_chunk_count:        int,
	vertex_count:             int,
}

load_chunk_shader :: proc(data_directory: string) -> (shader: rl.Shader, ok: bool) {
	vertex_path, vertex_error := os.join_path({data_directory, CHUNK_VERTEX_SHADER_PATH}, context.temp_allocator)
	fragment_path, fragment_error := os.join_path({data_directory, CHUNK_FRAGMENT_SHADER_PATH}, context.temp_allocator)
	if vertex_error != nil || fragment_error != nil {
		return {}, false
	}
	shader = rl.LoadShader(
		strings.clone_to_cstring(vertex_path, context.temp_allocator),
		strings.clone_to_cstring(fragment_path, context.temp_allocator),
	)
	// raylib falls back to its default shader when loading or compiling fails.
	if !rl.IsShaderValid(shader) || shader.id == rlgl.GetShaderIdDefault() {
		fmt.eprintfln("error: cannot load the chunk shader from %s and %s", vertex_path, fragment_path)
		return {}, false
	}
	return shader, true
}

set_shader_float :: proc(shader: rl.Shader, name: cstring, value: f32) {
	value := value
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, name), &value, .FLOAT)
}

set_shader_vector2 :: proc(shader: rl.Shader, name: cstring, value: [2]f32) {
	value := value
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, name), &value, .VEC2)
}

set_shader_vector3 :: proc(shader: rl.Shader, name: cstring, value: [3]f32) {
	value := value
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, name), &value, .VEC3)
}

color_to_vector3 :: proc(color: rl.Color) -> [3]f32 {
	return {f32(color.r), f32(color.g), f32(color.b)} / 255
}

init_chunk_renderer :: proc(registry: Block_Registry, data_directory: string) -> (renderer: Chunk_Renderer, ok: bool) {
	shader := load_chunk_shader(data_directory) or_return
	renderer.atlas_layout = atlas_layout_for_block_count(len(registry.definitions))
	set_shader_vector2(shader, "tile_size", atlas_tile_uv_size(renderer.atlas_layout))
	set_shader_vector3(shader, "fog_color", color_to_vector3(SKY_COLOR))
	set_shader_float(shader, "fog_start", FOG_START)
	set_shader_float(shader, "fog_end", FOG_END)
	renderer.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	renderer.material = rl.LoadMaterialDefault()
	renderer.material.shader = shader
	rl.SetMaterialTexture(&renderer.material, .ALBEDO, upload_atlas(registry, renderer.atlas_layout))
	return renderer, true
}

// raylib frees the CPU side arrays in UnloadMesh with its own allocator,
// so they must come from it.
clone_for_raylib :: proc(values: []$T) -> [^]T {
	copied := make([]T, len(values), rl.MemAllocator())
	copy(copied, values)
	return raw_data(copied)
}

upload_mesh_part :: proc(part: Mesh_Part) -> rl.Mesh {
	mesh := rl.Mesh {
		vertexCount   = i32(len(part.positions)),
		triangleCount = i32(len(part.indices) / 3),
		vertices      = cast([^]f32)clone_for_raylib(part.positions[:]),
		texcoords     = cast([^]f32)clone_for_raylib(part.texcoords[:]),
		texcoords2    = cast([^]f32)clone_for_raylib(part.tile_origins[:]),
		colors        = cast([^]u8)clone_for_raylib(part.colors[:]),
		indices       = clone_for_raylib(part.indices[:]),
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

unload_chunk_render :: proc(chunk_render: Chunk_Render) {
	for mesh in chunk_render.meshes {
		rl.UnloadMesh(mesh)
	}
	delete(chunk_render.meshes)
}

remesh_chunk :: proc(renderer: ^Chunk_Renderer, world: ^World, registry: Block_Registry, chunk: ^Chunk) {
	// Mesh data only lives until the upload, so hand the scratch memory back
	// per chunk instead of holding every chunk's data until the frame ends.
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	input := Mesh_Input {
		chunk      = chunk,
		neighbours = chunk_neighbours(world, chunk.coordinate),
		registry   = registry,
		atlas      = renderer.atlas_layout,
	}
	data := mesh_chunk(input, context.temp_allocator)
	if previous, found := renderer.chunk_meshes[chunk.coordinate]; found {
		renderer.vertex_count -= previous.vertex_count
		unload_chunk_render(previous)
	}
	chunk_render := Chunk_Render {
		meshes       = make([dynamic]rl.Mesh, 0, len(data.parts)),
		vertex_count = chunk_mesh_vertex_count(data),
	}
	for part in data.parts {
		append(&chunk_render.meshes, upload_mesh_part(part))
	}
	renderer.chunk_meshes[chunk.coordinate] = chunk_render
	renderer.vertex_count += chunk_render.vertex_count
	chunk.dirty = false
}

remesh_dirty_chunks :: proc(renderer: ^Chunk_Renderer, world: ^World, registry: Block_Registry) {
	for _, chunk in world.chunks {
		if chunk.dirty {
			remesh_chunk(renderer, world, registry, chunk)
		}
	}
}

fly_camera_to_raylib :: proc(camera: Fly_Camera) -> rl.Camera3D {
	return rl.Camera3D {
		position = camera.position,
		target = fly_camera_target(camera),
		up = {0, 1, 0},
		fovy = CAMERA_FIELD_OF_VIEW_DEGREES,
		projection = .PERSPECTIVE,
	}
}

chunk_in_frustum :: proc(frustum: Frustum, coordinate: Chunk_Coordinate) -> bool {
	origin := chunk_origin(coordinate)
	minimum := [3]f32{f32(origin.x), f32(origin.y), f32(origin.z)}
	return frustum_contains_box(frustum, minimum, minimum + CHUNK_SIZE)
}

// Must run between BeginMode3D and EndMode3D, which sets the projection
// matrix read here.
draw_chunks :: proc(renderer: ^Chunk_Renderer, camera: rl.Camera3D) {
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	position := camera.position
	rl.SetShaderValue(renderer.material.shader, renderer.camera_position_location, &position, .VEC3)
	renderer.drawn_chunk_count = 0
	for coordinate, chunk_render in renderer.chunk_meshes {
		if len(chunk_render.meshes) == 0 || !chunk_in_frustum(frustum, coordinate) {
			continue
		}
		origin := chunk_origin(coordinate)
		transform := rl.MatrixTranslate(f32(origin.x), f32(origin.y), f32(origin.z))
		for mesh in chunk_render.meshes {
			rl.DrawMesh(mesh, renderer.material, transform)
		}
		renderer.drawn_chunk_count += 1
	}
}

// UnloadMaterial also unloads the shader and the atlas texture.
destroy_chunk_renderer :: proc(renderer: ^Chunk_Renderer) {
	for _, chunk_render in renderer.chunk_meshes {
		unload_chunk_render(chunk_render)
	}
	delete(renderer.chunk_meshes)
	rl.UnloadMaterial(renderer.material)
}
