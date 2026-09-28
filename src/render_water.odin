package game

import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// The water pass (work item 0065): the faces of water blocks, which the
// mesher puts in parts of their own (world_mesh.odin), drawn after
// everything solid with alpha blending, depth test on and depth writes
// off, and backface culling off so a surface seen from below shows. The
// water material has its own shader pair (data/shaders/water.vs and
// water.fs) sharing the chunk atlas; the fragment shader ripples the
// surface, runs the texture along the flow and lays foam along the shore.
// Under water the fog closes in and turns blue green on both materials,
// whatever the weather, and a tint covers the view. Only the upload, the
// uniforms and the draw calls touch raylib.

WATER_VERTEX_SHADER_PATH :: "shaders/water.vs"
WATER_FRAGMENT_SHADER_PATH :: "shaders/water.fs"

// Uniforms of the water fragment shader, set once per shader.
WATER_ALPHA :: 0.6
// The ripple lightens the surface by up to this share.
WATER_RIPPLE_STRENGTH :: 0.15
// Flowing water's texture runs this many blocks per second.
WATER_FLOW_SPEED :: 1.0
// The foam's pattern scrolls this many radians per second.
WATER_FOAM_SPEED :: 3.0
// How far the foam goes towards white.
WATER_FOAM_STRENGTH :: 0.45
// The time uniform wraps after this many seconds: a whole number of the
// ripple periods in data/shaders/water.fs (2.5 and 4 seconds) and of whole
// blocks of an axis aligned flow, so neither jumps then; a diagonal flow
// jumps once per wrap.
WATER_TIME_WRAP_SECONDS :: 600.0

UNDERWATER_FOG_START :: 2
UNDERWATER_FOG_END :: 14
UNDERWATER_COLOR :: rl.Color{28, 92, 104, 255}
// The tint over the view under water.
UNDERWATER_OVERLAY_ALPHA :: 0.35

Water_Renderer :: struct {
	// Its albedo map is the chunk atlas, which the chunk material owns.
	material:                 rl.Material,
	camera_position_location: i32,
	day_factor_location:      i32,
	fog_color_location:       i32,
	sky_tint_location:        i32,
	fog_start_location:       i32,
	fog_end_location:         i32,
	time_location:            i32,
	flicker_location:         i32,
}

Fog :: struct {
	start, end: f32,
	color:      [3]f32,
}

load_water_shader :: proc(data_directory: string) -> (shader: rl.Shader, ok: bool) {
	return load_shader_pair(data_directory, WATER_VERTEX_SHADER_PATH, WATER_FRAGMENT_SHADER_PATH, "water")
}

init_water_renderer :: proc(shader: rl.Shader, atlas: rl.Texture2D, layout: Atlas_Layout) -> Water_Renderer {
	renderer := Water_Renderer{material = rl.LoadMaterialDefault()}
	use_water_shader(&renderer, shader, layout)
	renderer.material.maps[rl.MaterialMapIndex.ALBEDO].texture = atlas
	return renderer
}

// The uniforms that stay for the shader's life, and the locations of those
// set every frame.
use_water_shader :: proc(renderer: ^Water_Renderer, shader: rl.Shader, layout: Atlas_Layout) {
	set_shader_vector2(shader, "tile_size", atlas_tile_uv_size(layout))
	set_shader_float(shader, "water_alpha", WATER_ALPHA)
	set_shader_float(shader, "ripple_strength", WATER_RIPPLE_STRENGTH)
	set_shader_float(shader, "flow_speed", WATER_FLOW_SPEED)
	set_shader_float(shader, "foam_speed", WATER_FOAM_SPEED)
	set_shader_float(shader, "foam_strength", WATER_FOAM_STRENGTH)
	fog_start, fog_end := fog_distances(LOAD_RADIUS_HORIZONTAL)
	set_shader_float(shader, "fog_start", fog_start)
	set_shader_float(shader, "fog_end", fog_end)
	renderer.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	renderer.day_factor_location = rl.GetShaderLocation(shader, "day_factor")
	renderer.fog_color_location = rl.GetShaderLocation(shader, "fog_color")
	renderer.sky_tint_location = rl.GetShaderLocation(shader, "sky_tint")
	renderer.fog_start_location = rl.GetShaderLocation(shader, "fog_start")
	renderer.fog_end_location = rl.GetShaderLocation(shader, "fog_end")
	renderer.time_location = rl.GetShaderLocation(shader, "time")
	renderer.flicker_location = rl.GetShaderLocation(shader, "flicker")
	renderer.material.shader = shader
}

// A shader file changed. A shader that does not compile keeps the old
// one; load_water_shader logged why.
reload_water_shader :: proc(renderer: ^Water_Renderer, layout: Atlas_Layout, data_directory: string) -> bool {
	shader := load_water_shader(data_directory) or_return
	old_shader := renderer.material.shader
	use_water_shader(renderer, shader, layout)
	rl.UnloadShader(old_shader)
	return true
}

// The chunk material unloads the shared atlas, so the water material lets
// go of it first.
destroy_water_renderer :: proc(renderer: ^Water_Renderer) {
	renderer.material.maps[rl.MaterialMapIndex.ALBEDO].texture.id = rlgl.GetTextureIdDefault()
	rl.UnloadMaterial(renderer.material)
}

// The camera is under water when the cell of its eye holds water.
camera_underwater :: proc(world: ^World, registry: Block_Registry, eye: [3]f32) -> bool {
	return block_water_level(registry, world_get_block(world, camera_world_coordinate(eye))) > 0
}

// Under water the fog is near and blue green, whatever the weather.
underwater_fog :: proc() -> Fog {
	return Fog{start = UNDERWATER_FOG_START, end = UNDERWATER_FOG_END, color = color_to_vector3(UNDERWATER_COLOR)}
}

water_time :: proc(seconds: f64) -> f32 {
	return f32(wrap_f64(seconds, WATER_TIME_WRAP_SECONDS))
}

// Sets the fog on both materials, over what apply_daylight and
// apply_weather set this frame.
apply_fog :: proc(renderer: ^Chunk_Renderer, fog: Fog) {
	start, end, color := fog.start, fog.end, fog.color
	chunk_shader := renderer.material.shader
	rl.SetShaderValue(chunk_shader, renderer.fog_start_location, &start, .FLOAT)
	rl.SetShaderValue(chunk_shader, renderer.fog_end_location, &end, .FLOAT)
	rl.SetShaderValue(chunk_shader, renderer.fog_color_location, &color, .VEC3)
	water := &renderer.water
	water_shader := water.material.shader
	rl.SetShaderValue(water_shader, water.fog_start_location, &start, .FLOAT)
	rl.SetShaderValue(water_shader, water.fog_end_location, &end, .FLOAT)
	rl.SetShaderValue(water_shader, water.fog_color_location, &color, .VEC3)
}

begin_water_pass :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
}

end_water_pass :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthMask()
}

// Must run between BeginMode3D and EndMode3D, after everything solid.
// seconds is the render time.
draw_water_chunks :: proc(renderer: ^Chunk_Renderer, camera: rl.Camera3D, seconds: f64) {
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	water := &renderer.water
	position := camera.position
	time := water_time(seconds)
	rl.SetShaderValue(water.material.shader, water.camera_position_location, &position, .VEC3)
	rl.SetShaderValue(water.material.shader, water.time_location, &time, .FLOAT)
	begin_water_pass()
	defer end_water_pass()
	for coordinate, chunk_render in renderer.chunk_meshes {
		if len(chunk_render.water_meshes) == 0 || !chunk_in_frustum(frustum, coordinate) {
			continue
		}
		origin := chunk_origin(coordinate)
		transform := rl.MatrixTranslate(f32(origin.x), f32(origin.y), f32(origin.z))
		for mesh in chunk_render.water_meshes {
			rl.DrawMesh(mesh, water.material, transform)
		}
	}
}

// After the 3D pass.
draw_underwater_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Fade(UNDERWATER_COLOR, UNDERWATER_OVERLAY_ALPHA))
}
