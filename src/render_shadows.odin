package game

import "core:math/linalg"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// Sun shadows (work item 0072), behind the shadows setting. Before the
// main pass, the chunk meshes within SHADOW_RANGE_BLOCKS of the camera are
// drawn once more, depth only, into a SHADOW_MAP_SIZE square depth texture
// from an orthographic camera looking along the sun direction
// (sun_direction, render_day.odin). The box it sees is centred on the
// camera's block, snapped to whole blocks so the map does not shimmer as
// the camera moves within a block. The chunk and the water fragment
// shaders look their fragments up in the map (chunk.fs) and keep 40
// percent of the sky light in shadow; models do not receive shadows.
//
// raylib's LoadRenderTexture gives a depth renderbuffer that cannot be
// sampled, so the framebuffer is built from rlgl with a depth texture
// and no colour attachment. It is made the first time the pass runs and
// kept. Shadows fade in after dawn and out before dusk with the sun's
// height (shadow_strength_for_sun_height); at 0 the pass is skipped.
// Only the framebuffer, the pass and the uniforms touch raylib.

SHADOW_VERTEX_SHADER_PATH :: "shaders/shadow.vs"
SHADOW_FRAGMENT_SHADER_PATH :: "shaders/shadow.fs"
SHADOW_MAP_SIZE :: 2048
SHADOW_RANGE_BLOCKS :: 96
// The light's eye sits this far from the box's centre towards the sun, and
// the box reaches as far past the centre: casters up to this far towards
// the sun still shadow the range.
SHADOW_DEPTH_BLOCKS :: 2 * SHADOW_RANGE_BLOCKS
// Sun heights (the sine of the day fraction, render_day.odin) between
// which the shadows fade in after dawn and out before dusk. Below the
// start the sun grazes the terrain and every shadow would run to the edge
// of the map.
SHADOW_FADE_START :: 0.05
SHADOW_FADE_END :: 0.2
// The depth bias at a face turned straight to the sun, in shadow map
// texels; the shaders grow it with the slope.
SHADOW_BIAS_TEXELS :: 1.5

// What the shaders need of the shadows in one frame. strength 0 turns
// them off.
Shadow_Frame :: struct {
	strength:    f32,
	sun:         [3]f32,
	view:        matrix[4, 4]f32,
	projection:  matrix[4, 4]f32,
	light_space: matrix[4, 4]f32,
}

// Uniform locations of the shadow uniforms in one shader.
Shadow_Uniforms :: struct {
	light_space:   i32,
	strength:      i32,
	bias:          i32,
	sun_direction: i32,
}

// framebuffer and depth_texture are 0 until the pass first runs.
Shadow_Renderer :: struct {
	material:      rl.Material,
	framebuffer:   u32,
	depth_texture: u32,
}

// The block the camera stands in: the box follows the camera in whole
// blocks.
shadow_centre :: proc(camera_position: [3]f32) -> [3]f32 {
	return linalg.floor(camera_position)
}

// Any up vector not along the sun works; the sun's path leans towards +z
// (SUN_PATH_TILT_DEGREES) and never points along it.
shadow_view_matrix :: proc(centre, sun: [3]f32) -> matrix[4, 4]f32 {
	return linalg.matrix4_look_at_f32(centre + sun * SHADOW_DEPTH_BLOCKS, centre, {0, 0, 1})
}

shadow_projection_matrix :: proc() -> matrix[4, 4]f32 {
	return linalg.matrix_ortho3d_f32(-SHADOW_RANGE_BLOCKS, SHADOW_RANGE_BLOCKS, -SHADOW_RANGE_BLOCKS, SHADOW_RANGE_BLOCKS, 0, 2 * SHADOW_DEPTH_BLOCKS)
}

// 0 at night and with the sun low, 1 once it stands SHADOW_FADE_END high.
shadow_strength_for_sun_height :: proc(height: f64) -> f32 {
	return f32(smoothstep(SHADOW_FADE_START, SHADOW_FADE_END, height))
}

// The depth bias in depth buffer units (0 to 1 over the box's depth).
shadow_depth_bias :: proc() -> f32 {
	texel_blocks := f32(2 * SHADOW_RANGE_BLOCKS) / SHADOW_MAP_SIZE
	return SHADOW_BIAS_TEXELS * texel_blocks / (2 * SHADOW_DEPTH_BLOCKS)
}

shadow_frame :: proc(enabled: bool, camera_position: [3]f32, day_fraction: f64) -> Shadow_Frame {
	if !enabled {
		return {}
	}
	frame := Shadow_Frame {
		strength   = shadow_strength_for_sun_height(sun_height(day_fraction)),
		sun        = sun_direction(day_fraction),
		projection = shadow_projection_matrix(),
	}
	frame.view = shadow_view_matrix(shadow_centre(camera_position), frame.sun)
	frame.light_space = frame.projection * frame.view
	return frame
}

// Whether any of the chunk lies within SHADOW_RANGE_BLOCKS of the camera.
chunk_in_shadow_range :: proc(coordinate: Chunk_Coordinate, camera_position: [3]f32) -> bool {
	origin := chunk_origin(coordinate)
	minimum := [3]f32{f32(origin.x), f32(origin.y), f32(origin.z)}
	nearest := linalg.clamp(camera_position, minimum, minimum + CHUNK_SIZE)
	return linalg.length2(nearest - camera_position) <= SHADOW_RANGE_BLOCKS * SHADOW_RANGE_BLOCKS
}

load_shadow_shader :: proc(data_directory: string) -> (shader: rl.Shader, ok: bool) {
	return load_shader_pair(data_directory, SHADOW_VERTEX_SHADER_PATH, SHADOW_FRAGMENT_SHADER_PATH, "shadow")
}

init_shadow_renderer :: proc(shader: rl.Shader) -> Shadow_Renderer {
	renderer := Shadow_Renderer{material = rl.LoadMaterialDefault()}
	renderer.material.shader = shader
	return renderer
}

reload_shadow_shader :: proc(renderer: ^Shadow_Renderer, data_directory: string) -> bool {
	shader := load_shadow_shader(data_directory) or_return
	rl.UnloadShader(renderer.material.shader)
	renderer.material.shader = shader
	return true
}

// The locations of the shadow uniforms in a chunk or water shader, whose
// shadow_map sampler DrawMesh binds from the material's normal map slot.
shadow_uniform_locations :: proc(shader: rl.Shader) -> Shadow_Uniforms {
	shader.locs[rl.ShaderLocationIndex.MAP_NORMAL] = rl.GetShaderLocation(shader, "shadow_map")
	set_shader_float(shader, "shadow_bias", shadow_depth_bias())
	return Shadow_Uniforms {
		light_space = rl.GetShaderLocation(shader, "light_space"),
		strength = rl.GetShaderLocation(shader, "shadow_strength"),
		sun_direction = rl.GetShaderLocation(shader, "sun_direction"),
	}
}

set_shadow_uniforms :: proc(shader: rl.Shader, locations: Shadow_Uniforms, frame: Shadow_Frame) {
	strength, sun := frame.strength, frame.sun
	rl.SetShaderValue(shader, locations.strength, &strength, .FLOAT)
	rl.SetShaderValue(shader, locations.sun_direction, &sun, .VEC3)
	rl.SetShaderValueMatrix(shader, locations.light_space, rl.Matrix(frame.light_space))
}

shadow_map_texture :: proc(renderer: Shadow_Renderer) -> rl.Texture2D {
	return rl.Texture2D{id = renderer.depth_texture, width = SHADOW_MAP_SIZE, height = SHADOW_MAP_SIZE, mipmaps = 1}
}

// Makes the framebuffer the first time. Returns false when the driver
// refuses it; the shadows then stay off.
ensure_shadow_map :: proc(renderer: ^Chunk_Renderer) -> bool {
	shadows := &renderer.shadows
	if shadows.framebuffer != 0 {
		return true
	}
	framebuffer := rlgl.LoadFramebuffer()
	if framebuffer == 0 {
		return false
	}
	rlgl.EnableFramebuffer(framebuffer)
	depth := rlgl.LoadTextureDepth(SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, false)
	rlgl.FramebufferAttach(framebuffer, depth, i32(rlgl.FramebufferAttachType.DEPTH), i32(rlgl.FramebufferAttachTextureType.TEXTURE2D), 0)
	complete := rlgl.FramebufferComplete(framebuffer)
	rlgl.DisableFramebuffer()
	if !complete {
		log_printf("error: the shadow map framebuffer is incomplete, shadows stay off")
		rlgl.UnloadFramebuffer(framebuffer)
		rlgl.UnloadTexture(depth)
		return false
	}
	shadows.framebuffer, shadows.depth_texture = framebuffer, depth
	texture := shadow_map_texture(shadows^)
	renderer.material.maps[rl.MaterialMapIndex.NORMAL].texture = texture
	renderer.water.material.maps[rl.MaterialMapIndex.NORMAL].texture = texture
	return true
}

// The depth pass, before BeginMode3D. EndTextureMode leaves the viewport
// and the matrices as BeginDrawing set them.
draw_shadow_map :: proc(renderer: ^Chunk_Renderer, frame: Shadow_Frame, camera_position: [3]f32) {
	shadows := renderer.shadows
	target := rl.RenderTexture2D {
		id      = shadows.framebuffer,
		texture = {width = SHADOW_MAP_SIZE, height = SHADOW_MAP_SIZE},
		depth   = shadow_map_texture(shadows),
	}
	rl.BeginTextureMode(target)
	defer rl.EndTextureMode()
	rlgl.ClearScreenBuffers()
	rlgl.SetMatrixProjection(rl.Matrix(frame.projection))
	rlgl.SetMatrixModelview(rl.Matrix(frame.view))
	rlgl.EnableDepthTest()
	defer rlgl.DisableDepthTest()
	for coordinate, chunk_render in renderer.chunk_meshes {
		if len(chunk_render.meshes) == 0 || !chunk_in_shadow_range(coordinate, camera_position) {
			continue
		}
		origin := chunk_origin(coordinate)
		transform := rl.MatrixTranslate(f32(origin.x), f32(origin.y), f32(origin.z))
		for mesh in chunk_render.meshes {
			rl.DrawMesh(mesh, shadows.material, transform)
		}
	}
	rlgl.DrawRenderBatchActive()
}

// Once per frame before BeginMode3D: the depth pass when the shadows are
// on and the sun is up, and the uniforms of both materials.
apply_shadows :: proc(renderer: ^Chunk_Renderer, frame: Shadow_Frame, camera_position: [3]f32) {
	frame := frame
	if frame.strength > 0 && ensure_shadow_map(renderer) {
		draw_shadow_map(renderer, frame, camera_position)
	} else {
		frame.strength = 0
	}
	set_shadow_uniforms(renderer.material.shader, renderer.shadow_uniforms, frame)
	set_shadow_uniforms(renderer.water.material.shader, renderer.water.shadow_uniforms, frame)
}

// Before the chunk and water materials are unloaded, which would unload
// the depth texture from their map slots.
destroy_shadow_renderer :: proc(renderer: ^Chunk_Renderer) {
	shadows := &renderer.shadows
	default_texture := rlgl.GetTextureIdDefault()
	renderer.material.maps[rl.MaterialMapIndex.NORMAL].texture.id = default_texture
	renderer.water.material.maps[rl.MaterialMapIndex.NORMAL].texture.id = default_texture
	if shadows.framebuffer != 0 {
		rlgl.UnloadFramebuffer(shadows.framebuffer)
		rlgl.UnloadTexture(shadows.depth_texture)
	}
	rl.UnloadMaterial(shadows.material)
	shadows^ = {}
}
