package game

import "core:os"
import "core:strings"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

CHUNK_VERTEX_SHADER_PATH :: "shaders/chunk.vs"
CHUNK_FRAGMENT_SHADER_PATH :: "shaders/chunk.fs"

// The fog starts at this share of its end distance (fog_distances).
FOG_START_SHARE :: 0.6
CAMERA_FIELD_OF_VIEW_DEGREES :: 70.0

// One raylib mesh per part: a chunk only needs more than one when it
// exceeds the u16 index range (MESH_PART_VERTEX_LIMIT). water_meshes are
// the water parts, drawn by the water pass (render_water.odin). flames
// holds the world cells of the chunk's torches (render_flames.odin).
Chunk_Render :: struct {
	meshes:       [dynamic]rl.Mesh,
	water_meshes: [dynamic]rl.Mesh,
	vertex_count: int,
	flames:       [dynamic]World_Coordinate,
}

Chunk_Renderer :: struct {
	atlas_layout:                   Atlas_Layout,
	material:                       rl.Material,
	camera_position_location:       i32,
	day_factor_location:            i32,
	fog_color_location:             i32,
	sky_tint_location:              i32,
	// Set every frame from the weather (apply_weather, work item 0063).
	fog_start_location:             i32,
	fog_end_location:               i32,
	wind_time_location:             i32,
	wind_strength_location:         i32,
	cloud_offset_location:          i32,
	cloud_shadow_strength_location: i32,
	// The sky pass (render_sky.odin) lives with the chunks it sits behind.
	sky:                            Sky_Renderer,
	// The water pass (render_water.odin, work item 0065).
	water:                          Water_Renderer,
	chunk_meshes:                   map[Chunk_Coordinate]Chunk_Render,
	drawn_chunk_count:              int,
	vertex_count:                   int,
}

load_chunk_shader :: proc(data_directory: string) -> (shader: rl.Shader, ok: bool) {
	return load_shader_pair(data_directory, CHUNK_VERTEX_SHADER_PATH, CHUNK_FRAGMENT_SHADER_PATH, "chunk")
}

// name says which shader failed in the log.
load_shader_pair :: proc(data_directory, vertex_file, fragment_file, name: string) -> (shader: rl.Shader, ok: bool) {
	vertex_path, vertex_error := os.join_path({data_directory, vertex_file}, context.temp_allocator)
	fragment_path, fragment_error := os.join_path({data_directory, fragment_file}, context.temp_allocator)
	if vertex_error != nil || fragment_error != nil {
		return {}, false
	}
	shader = rl.LoadShader(
		strings.clone_to_cstring(vertex_path, context.temp_allocator),
		strings.clone_to_cstring(fragment_path, context.temp_allocator),
	)
	// raylib falls back to its default shader when loading or compiling fails.
	if !rl.IsShaderValid(shader) || shader.id == rlgl.GetShaderIdDefault() {
		log_printf("error: cannot load the %s shader from %s and %s", name, vertex_path, fragment_path)
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

// The fog is complete one chunk inside the load radius and starts at
// FOG_START_SHARE of that, so the world edge never shows whatever the
// radius (work item 0064).
fog_distances :: proc(load_radius_chunks: int) -> (start, end: f32) {
	end = f32((load_radius_chunks - 1) * CHUNK_SIZE)
	return end * FOG_START_SHARE, end
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
	water_shader, water_loaded := load_water_shader(data_directory)
	if !water_loaded {
		rl.UnloadShader(shader)
		return {}, false
	}
	renderer.atlas_layout = atlas_layout_for_block_count(len(registry.definitions))
	renderer.material = rl.LoadMaterialDefault()
	use_chunk_shader(&renderer, shader)
	rl.SetMaterialTexture(&renderer.material, .ALBEDO, upload_atlas(registry, renderer.atlas_layout, data_directory))
	// The cloud shadows (render_weather.odin) in the second texture slot,
	// bound to cloud_texture by use_chunk_shader; UnloadMaterial frees it.
	rl.SetMaterialTexture(&renderer.material, .METALNESS, upload_cloud_texture())
	renderer.sky = init_sky_renderer()
	renderer.water = init_water_renderer(water_shader, chunk_atlas_texture(renderer), renderer.atlas_layout)
	apply_daylight(&renderer, day_sky_at(NOON_FRACTION, 0))
	return renderer, true
}

// The uniforms that stay for the shader's life, and the locations of those
// set every frame.
use_chunk_shader :: proc(renderer: ^Chunk_Renderer, shader: rl.Shader) {
	set_shader_vector2(shader, "tile_size", atlas_tile_uv_size(renderer.atlas_layout))
	fog_start, fog_end := fog_distances(LOAD_RADIUS_HORIZONTAL)
	set_shader_float(shader, "fog_start", fog_start)
	set_shader_float(shader, "fog_end", fog_end)
	renderer.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	renderer.day_factor_location = rl.GetShaderLocation(shader, "day_factor")
	renderer.fog_color_location = rl.GetShaderLocation(shader, "fog_color")
	renderer.sky_tint_location = rl.GetShaderLocation(shader, "sky_tint")
	renderer.fog_start_location = rl.GetShaderLocation(shader, "fog_start")
	renderer.fog_end_location = rl.GetShaderLocation(shader, "fog_end")
	renderer.wind_time_location = rl.GetShaderLocation(shader, "wind_time")
	renderer.wind_strength_location = rl.GetShaderLocation(shader, "wind_strength")
	renderer.cloud_offset_location = rl.GetShaderLocation(shader, "cloud_offset")
	renderer.cloud_shadow_strength_location = rl.GetShaderLocation(shader, "cloud_shadow_strength")
	// DrawMesh binds the material's second map to this location.
	shader.locs[rl.ShaderLocationIndex.MAP_METALNESS] = rl.GetShaderLocation(shader, "cloud_texture")
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
	set_shader_vector2(renderer.water.material.shader, "tile_size", atlas_tile_uv_size(renderer.atlas_layout))
	renderer.water.material.maps[rl.MaterialMapIndex.ALBEDO].texture = chunk_atlas_texture(renderer^)
}

// raylib frees the CPU side arrays in UnloadMesh with its own allocator,
// so they must come from it.
clone_for_raylib :: proc(values: []$T) -> [^]T {
	copied := make([]T, len(values), rl.MemAllocator())
	copy(copied, values)
	return raw_data(copied)
}

// Water parts carry a tangent per vertex (water_tangent), the others none.
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
	if len(part.tangents) > 0 {
		mesh.tangents = cast([^]f32)clone_for_raylib(part.tangents[:])
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

unload_chunk_render :: proc(chunk_render: Chunk_Render) {
	for mesh in chunk_render.meshes {
		rl.UnloadMesh(mesh)
	}
	for mesh in chunk_render.water_meshes {
		rl.UnloadMesh(mesh)
	}
	delete(chunk_render.meshes)
	delete(chunk_render.water_meshes)
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
	if len(data.parts) == 0 && len(data.water_parts) == 0 {
		return
	}
	chunk_render := Chunk_Render {
		meshes       = make([dynamic]rl.Mesh, 0, len(data.parts)),
		water_meshes = make([dynamic]rl.Mesh, 0, len(data.water_parts)),
		vertex_count = chunk_mesh_vertex_count(data),
		flames       = make([dynamic]World_Coordinate, 0, len(data.flames)),
	}
	for part in data.parts {
		append(&chunk_render.meshes, upload_mesh_part(part))
	}
	for part in data.water_parts {
		append(&chunk_render.water_meshes, upload_mesh_part(part))
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

// Sky light scale and tint and the fog colour for the time of day, once
// per frame, on the chunk and the water material.
apply_daylight :: proc(renderer: ^Chunk_Renderer, sky: Day_Sky) {
	factor := day_factor(sky.blend)
	fog := color_to_vector3(sky.colors.fog)
	tint := color_to_vector3(sky.colors.sun_tint)
	rl.SetShaderValue(renderer.material.shader, renderer.day_factor_location, &factor, .FLOAT)
	rl.SetShaderValue(renderer.material.shader, renderer.fog_color_location, &fog, .VEC3)
	rl.SetShaderValue(renderer.material.shader, renderer.sky_tint_location, &tint, .VEC3)
	water := &renderer.water
	rl.SetShaderValue(water.material.shader, water.day_factor_location, &factor, .FLOAT)
	rl.SetShaderValue(water.material.shader, water.fog_color_location, &fog, .VEC3)
	rl.SetShaderValue(water.material.shader, water.sky_tint_location, &tint, .VEC3)
}

// The weather's fog distances (on the water material too), plant sway and
// cloud shadows, once per frame; seconds is the render time.
apply_weather :: proc(renderer: ^Chunk_Renderer, look: Weather_Look, seconds: f64) {
	shader := renderer.material.shader
	fog_start, fog_end := weather_fog_distances(LOAD_RADIUS_HORIZONTAL, look.fog_scale)
	wind := wind_time(seconds)
	wind_strength := look.wind_strength
	offset := cloud_offset(seconds)
	shadow := look.cloud_shadow_strength
	rl.SetShaderValue(shader, renderer.fog_start_location, &fog_start, .FLOAT)
	rl.SetShaderValue(shader, renderer.fog_end_location, &fog_end, .FLOAT)
	rl.SetShaderValue(shader, renderer.wind_time_location, &wind, .FLOAT)
	rl.SetShaderValue(shader, renderer.wind_strength_location, &wind_strength, .FLOAT)
	rl.SetShaderValue(shader, renderer.cloud_offset_location, &offset, .VEC2)
	rl.SetShaderValue(shader, renderer.cloud_shadow_strength_location, &shadow, .FLOAT)
	water := &renderer.water
	rl.SetShaderValue(water.material.shader, water.fog_start_location, &fog_start, .FLOAT)
	rl.SetShaderValue(water.material.shader, water.fog_end_location, &fog_end, .FLOAT)
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

// UnloadMaterial also unloads the shader and the atlas texture, which the
// water material shares, so that goes first.
destroy_chunk_renderer :: proc(renderer: ^Chunk_Renderer) {
	for _, chunk_render in renderer.chunk_meshes {
		unload_chunk_render(chunk_render)
	}
	delete(renderer.chunk_meshes)
	destroy_water_renderer(&renderer.water)
	rl.UnloadMaterial(renderer.material)
	destroy_sky_renderer(&renderer.sky)
}
