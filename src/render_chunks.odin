package game

import "core:os"
import "core:strings"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

CHUNK_VERTEX_SHADER_PATH :: "shaders/chunk.vs"
CHUNK_FRAGMENT_SHADER_PATH :: "shaders/chunk.fs"

// The load radius reaches at least 192 blocks from the camera, so the fog
// is complete before the load boundary.
FOG_START :: 96.0
FOG_END :: 160.0
CAMERA_FIELD_OF_VIEW_DEGREES :: 70.0

// One raylib mesh per part: a chunk only needs more than one when it
// exceeds the u16 index range (MESH_PART_VERTEX_LIMIT). flames holds the
// world cells of the chunk's torches (render_flames.odin).
Chunk_Render :: struct {
	meshes:       [dynamic]rl.Mesh,
	vertex_count: int,
	flames:       [dynamic]World_Coordinate,
}

Chunk_Renderer :: struct {
	atlas_layout:             Atlas_Layout,
	material:                 rl.Material,
	camera_position_location: i32,
	day_factor_location:      i32,
	fog_color_location:       i32,
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
		log_printf("error: cannot load the chunk shader from %s and %s", vertex_path, fragment_path)
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

// The block atlas also serves as the icon of a block placing item without
// an icon file.
chunk_atlas_texture :: proc(renderer: Chunk_Renderer) -> rl.Texture2D {
	return renderer.material.maps[rl.MaterialMapIndex.ALBEDO].texture
}

init_chunk_renderer :: proc(registry: Block_Registry, data_directory: string) -> (renderer: Chunk_Renderer, ok: bool) {
	shader := load_chunk_shader(data_directory) or_return
	renderer.atlas_layout = atlas_layout_for_block_count(len(registry.definitions))
	renderer.material = rl.LoadMaterialDefault()
	use_chunk_shader(&renderer, shader)
	rl.SetMaterialTexture(&renderer.material, .ALBEDO, upload_atlas(registry, renderer.atlas_layout, data_directory))
	apply_daylight(&renderer, 1)
	return renderer, true
}

// The uniforms that stay for the shader's life, and the locations of those
// set every frame.
use_chunk_shader :: proc(renderer: ^Chunk_Renderer, shader: rl.Shader) {
	set_shader_vector2(shader, "tile_size", atlas_tile_uv_size(renderer.atlas_layout))
	set_shader_float(shader, "fog_start", FOG_START)
	set_shader_float(shader, "fog_end", FOG_END)
	renderer.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	renderer.day_factor_location = rl.GetShaderLocation(shader, "day_factor")
	renderer.fog_color_location = rl.GetShaderLocation(shader, "fog_color")
	renderer.material.shader = shader
}

// A shader file changed (work item 0054). A shader that does not compile
// keeps the old one; load_chunk_shader logged why.
reload_chunk_shader :: proc(renderer: ^Chunk_Renderer, data_directory: string) -> bool {
	shader := load_chunk_shader(data_directory) or_return
	old_shader := renderer.material.shader
	use_chunk_shader(renderer, shader)
	rl.UnloadShader(old_shader)
	return true
}

// The block table changed (a content reload), or a texture file did: a new
// atlas. After a content reload every mesh is rebuilt by the streaming,
// since tile positions may have moved; a texture change keeps the layout,
// which depends on the block count alone, so the meshes stay.
replace_chunk_atlas :: proc(renderer: ^Chunk_Renderer, registry: Block_Registry, data_directory: string) {
	rl.UnloadTexture(chunk_atlas_texture(renderer^))
	renderer.atlas_layout = atlas_layout_for_block_count(len(registry.definitions))
	set_shader_vector2(renderer.material.shader, "tile_size", atlas_tile_uv_size(renderer.atlas_layout))
	rl.SetMaterialTexture(&renderer.material, .ALBEDO, upload_atlas(registry, renderer.atlas_layout, data_directory))
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
	delete(chunk_render.flames)
}

unload_chunk_mesh :: proc(renderer: ^Chunk_Renderer, coordinate: Chunk_Coordinate) {
	if previous, found := renderer.chunk_meshes[coordinate]; found {
		renderer.vertex_count -= previous.vertex_count
		unload_chunk_render(previous)
		delete_key(&renderer.chunk_meshes, coordinate)
	}
}

// Replaces the chunk's mesh. An empty mesh only removes the old one.
apply_chunk_mesh :: proc(renderer: ^Chunk_Renderer, coordinate: Chunk_Coordinate, data: Chunk_Mesh_Data) {
	unload_chunk_mesh(renderer, coordinate)
	if len(data.parts) == 0 {
		return
	}
	chunk_render := Chunk_Render {
		meshes       = make([dynamic]rl.Mesh, 0, len(data.parts)),
		vertex_count = chunk_mesh_vertex_count(data),
		flames       = make([dynamic]World_Coordinate, 0, len(data.flames)),
	}
	for part in data.parts {
		append(&chunk_render.meshes, upload_mesh_part(part))
	}
	for local in data.flames {
		append(&chunk_render.flames, chunk_origin(coordinate) + World_Coordinate(local))
	}
	renderer.chunk_meshes[coordinate] = chunk_render
	renderer.vertex_count += chunk_render.vertex_count
}

// Drops the meshes of chunks unloaded this frame and uploads a few of the
// meshes the workers finished.
upload_streamed_meshes :: proc(renderer: ^Chunk_Renderer, streaming: ^Chunk_Streaming) {
	for coordinate in streaming.unloaded {
		unload_chunk_mesh(renderer, coordinate)
	}
	for result in take_current_meshes(streaming, MAXIMUM_MESH_UPLOADS_PER_FRAME, context.temp_allocator) {
		apply_chunk_mesh(renderer, result.coordinate, result.mesh)
		destroy_chunk_mesh_data(result.mesh)
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

// Sky light scale and fog colour for the time of day, once per frame.
apply_daylight :: proc(renderer: ^Chunk_Renderer, blend: f32) {
	factor := day_factor(blend)
	fog := color_to_vector3(sky_color(blend))
	rl.SetShaderValue(renderer.material.shader, renderer.day_factor_location, &factor, .FLOAT)
	rl.SetShaderValue(renderer.material.shader, renderer.fog_color_location, &fog, .VEC3)
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

// When a world ends, so the next one starts without its meshes.
unload_all_chunk_meshes :: proc(renderer: ^Chunk_Renderer) {
	for _, chunk_render in renderer.chunk_meshes {
		unload_chunk_render(chunk_render)
	}
	clear(&renderer.chunk_meshes)
	renderer.vertex_count = 0
	renderer.drawn_chunk_count = 0
}

// UnloadMaterial also unloads the shader and the atlas texture.
destroy_chunk_renderer :: proc(renderer: ^Chunk_Renderer) {
	for _, chunk_render in renderer.chunk_meshes {
		unload_chunk_render(chunk_render)
	}
	delete(renderer.chunk_meshes)
	rl.UnloadMaterial(renderer.material)
}
