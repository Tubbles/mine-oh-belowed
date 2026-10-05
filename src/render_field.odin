package game

import rl "shared:raylib"
import "shared:raylib/rlgl"
import "render_frustum"

// The terrain field's renderer (work item 0169, doc/presentation.md, Chunk
// meshes): one raylib mesh per selected octree node (world_field_lod.odin),
// drawn with the triplanar shader (data/shaders/field.vs and field.fs) and
// the seven material tiles (texture_field_materials.odin), and the globe, a
// sphere in the palette's first colour drawn every frame below the lowest
// ground the relief can make, so the meshed nodes cover it where they
// exist and it fills the planet's silhouette beyond the last distance.
// Each node also carries the water's mesh (0172), drawn after every
// node's terrain through the same shader with water_color set:
// translucent, alpha blended and without depth writes, so the terrain
// shows through and the water never hides the water behind it. The
// field light (0173) reaches the shader per vertex, the sky light scaled
// by the daylight uniform (Field_Renderer.daylight, 1 until the day cycle
// of 0179 sets it).

FIELD_VERTEX_SHADER_PATH :: "shaders/field.vs"
FIELD_FRAGMENT_SHADER_PATH :: "shaders/field.fs"
// The sun of the slope shading until the day reaches the field.
FIELD_SUN_DIRECTION :: [3]f32{0.35, 1, 0.2}
FIELD_FOG_COLOR :: rl.Color{150, 180, 210, 255}
FIELD_GLOBE_RINGS :: 64
FIELD_GLOBE_SLICES :: 128
// Below the lowest relief: a coarsest cell, which also holds the sphere's
// facets (about 2.4 m deep at 8 km) under the ground.
FIELD_GLOBE_MARGIN_METRES :: 8
// The water pass's colour and opacity (the shader's water_color); the
// terrain pass sets an opacity of 0.
FIELD_WATER_COLOR :: [4]f32{0.16, 0.36, 0.52, 0.62}

// The material slots' sampler names, bound to the material's first seven
// maps (DrawMesh binds map i to the shader location MAP_ALBEDO + i; maps
// 0 to 6 are two dimensional, the cube maps start at 7).
@(rodata)
field_material_sampler_names := [FIELD_TEXTURED_MATERIAL_COUNT]cstring {
	"material_texture_topsoil",
	"material_texture_stone",
	"material_texture_deep_stone",
	"material_texture_bedrock",
	"material_texture_hematite_ore",
	"material_texture_chalcopyrite_ore",
	"material_texture_coal_ore",
}

#assert(FIELD_MATERIAL_TILE_COUNT == FIELD_TEXTURED_MATERIAL_COUNT, "every generated material tile is bound and sampled")
#assert(FIELD_TEXTURED_MATERIAL_COUNT <= int(rl.MaterialMapIndex.CUBEMAP), "the material tiles take two dimensional maps only")

// origin is the node's first sample in metres. A node with no water has
// has_water false and no water mesh.
Field_Node_Render :: struct {
	mesh:         rl.Mesh,
	water:        rl.Mesh,
	has_mesh:     bool,
	has_water:    bool,
	origin:       [3]f32,
	vertex_count: int,
}

Field_Renderer :: struct {
	material:                 rl.Material,
	camera_position_location: i32,
	water_color_location:     i32,
	daylight_location:        i32,
	// The sky light's share, 0 at night to 1 at noon.
	daylight:                 f32,
	// The point lights' uniforms (0175, set_field_point_lights).
	point_light_locations:    [2]i32,
	globe:                    rl.Mesh,
	globe_material:           rl.Material,
	spacing_millimetres:      int,
	meshes:                   map[Field_Node]Field_Node_Render,
	vertex_count:             int,
	drawn_node_count:         int,
	// The trees round the eyes (0197, render_field_trees.odin).
	trees:                    Field_Tree_Cache,
	// Each player's eased crouch by player index, advanced in
	// prepare_field_frame (0218).
	crouch_progress:          [dynamic]f32,
	// Each material tile's mean texel, 0 to 1 (the debris' colours, 0272).
	material_colors:          [FIELD_MATERIAL_TILE_COUNT][3]f32,
}

// A tile's mean texel, 0 to 1.
tile_mean_color :: proc(tile: Tile_Pixels) -> [3]f32 {
	sum: [3]f64
	for texel in tile {
		sum += {f64(texel.r), f64(texel.g), f64(texel.b)}
	}
	mean := sum / (f64(len(tile)) * 255)
	return {f32(mean.r), f32(mean.g), f32(mean.b)}
}

// Bilinear with mipmaps and repeating, so the tile wraps and stays calm at
// a distance.
upload_field_material_tile :: proc(tile: Tile_Pixels) -> rl.Texture2D {
	tile := tile
	image := rl.Image {
		data    = raw_data(tile[:]),
		width   = ATLAS_TILE_SIZE,
		height  = ATLAS_TILE_SIZE,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := load_rgba_texture(image)
	rl.GenTextureMipmaps(&texture)
	rl.SetTextureFilter(texture, .TRILINEAR)
	rl.SetTextureWrap(texture, .REPEAT)
	return texture
}

// fog_end is the last level of detail distance in metres.
use_field_shader :: proc(renderer: ^Field_Renderer, shader: rl.Shader, fog_end: f32) {
	for name, slot in field_material_sampler_names {
		shader.locs[int(rl.ShaderLocationIndex.MAP_ALBEDO) + slot] = rl.GetShaderLocation(shader, name)
	}
	sun := FIELD_SUN_DIRECTION
	fog := color_to_vector3(FIELD_FOG_COLOR)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "sun_direction"), &sun, .VEC3)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "fog_color"), &fog, .VEC3)
	set_shader_float(shader, "fog_start", fog_end * FOG_START_SHARE)
	set_shader_float(shader, "fog_end", fog_end)
	renderer.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	renderer.water_color_location = rl.GetShaderLocation(shader, "water_color")
	renderer.daylight_location = rl.GetShaderLocation(shader, "daylight")
	renderer.point_light_locations = {rl.GetShaderLocation(shader, "point_light_positions"), rl.GetShaderLocation(shader, "point_light_colors")}
	renderer.material.shader = shader
}

field_globe_radius_metres :: proc(planet: Planet) -> f32 {
	return f32(i64(planet.radius_metres) - MAXIMUM_RELIEF_METRES - FIELD_GLOBE_MARGIN_METRES)
}

field_globe_color :: proc(palette: [][3]int) -> rl.Color {
	color := palette[0]
	return {u8(color.r), u8(color.g), u8(color.b), 255}
}

init_field_renderer :: proc(data_directory: string, tiles: Field_Material_Tiles, planet: Planet, spacing_millimetres: int, fog_end: f32) -> (renderer: Field_Renderer, ok: bool) {
	shader := load_shader_pair(data_directory, FIELD_VERTEX_SHADER_PATH, FIELD_FRAGMENT_SHADER_PATH, "field") or_return
	renderer.material = rl.LoadMaterialDefault()
	use_field_shader(&renderer, shader, fog_end)
	for tile, slot in tiles {
		rl.SetMaterialTexture(&renderer.material, rl.MaterialMapIndex(slot), upload_field_material_tile(tile))
		renderer.material_colors[slot] = tile_mean_color(tile)
	}
	renderer.globe = rl.GenMeshSphere(field_globe_radius_metres(planet), FIELD_GLOBE_RINGS, FIELD_GLOBE_SLICES)
	renderer.globe_material = rl.LoadMaterialDefault()
	renderer.globe_material.maps[rl.MaterialMapIndex.ALBEDO].color = field_globe_color(planet.palette)
	renderer.spacing_millimetres = spacing_millimetres
	renderer.daylight = 1
	return renderer, true
}

// Raylib frees the arrays in UnloadMesh, so they are its copies
// (clone_for_raylib); the block light and the weights travel in the
// attributes Field_Mesh_Data names.
upload_field_mesh :: proc(data: Field_Mesh_Data) -> rl.Mesh {
	mesh := rl.Mesh {
		vertexCount   = i32(len(data.positions)),
		triangleCount = i32(len(data.indices) / 3),
		vertices      = cast([^]f32)clone_for_raylib(data.positions[:]),
		normals       = cast([^]f32)clone_for_raylib(data.normals[:]),
		colors        = cast([^]u8)clone_for_raylib(data.colors[:]),
		texcoords     = cast([^]f32)clone_for_raylib(data.lights[:]),
		texcoords2    = cast([^]f32)clone_for_raylib(data.ore_weights[:]),
		tangents      = cast([^]f32)clone_for_raylib(data.weights[:]),
		indices       = clone_for_raylib(data.indices[:]),
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

unload_field_node_render :: proc(render: Field_Node_Render) {
	if render.has_mesh {
		rl.UnloadMesh(render.mesh)
	}
	if render.has_water {
		rl.UnloadMesh(render.water)
	}
}

unload_field_node :: proc(renderer: ^Field_Renderer, node: Field_Node) {
	if previous, found := renderer.meshes[node]; found {
		renderer.vertex_count -= previous.vertex_count
		unload_field_node_render(previous)
		delete_key(&renderer.meshes, node)
	}
}

field_node_origin_metres :: proc(node: Field_Node, spacing_millimetres: int) -> [3]f32 {
	origin := field_node_origin(node)
	metres_per_sample := f64(spacing_millimetres) / MILLIMETRES_PER_METRE
	return {f32(f64(origin.x) * metres_per_sample), f32(f64(origin.y) * metres_per_sample), f32(f64(origin.z) * metres_per_sample)}
}

// Replaces the node's meshes; two empty meshes only remove the old ones.
apply_field_mesh :: proc(renderer: ^Field_Renderer, node: Field_Node, data, water: Field_Mesh_Data) {
	unload_field_node(renderer, node)
	if len(data.indices) == 0 && len(water.indices) == 0 {
		return
	}
	render := Field_Node_Render {
		origin       = field_node_origin_metres(node, renderer.spacing_millimetres),
		vertex_count = len(data.positions) + len(water.positions),
	}
	if len(data.indices) > 0 {
		render.mesh, render.has_mesh = upload_field_mesh(data), true
	}
	if len(water.indices) > 0 {
		render.water, render.has_water = upload_field_mesh(water), true
	}
	renderer.meshes[node] = render
	renderer.vertex_count += render.vertex_count
}

// Drops the meshes of nodes that left the selection and uploads the
// meshes the workers finished.
upload_streamed_field_meshes :: proc(renderer: ^Field_Renderer, streaming: ^Field_Streaming) {
	for node in streaming.dropped {
		unload_field_node(renderer, node)
	}
	for result in take_current_field_meshes(streaming, context.temp_allocator) {
		apply_field_mesh(renderer, result.node, result.mesh, result.water_mesh)
		destroy_field_mesh_data(result.mesh)
		destroy_field_mesh_data(result.water_mesh)
	}
}

field_node_in_frustum :: proc(frustum: render_frustum.Frustum, render: Field_Node_Render, node: Field_Node, spacing_millimetres: int) -> bool {
	size := f32(f64(field_node_samples(node.level)) * f64(spacing_millimetres) / MILLIMETRES_PER_METRE)
	// The cells below the origin and the skirts reach three cells past
	// the box.
	margin := size / FIELD_GRID_CELLS * 4
	return render_frustum.frustum_contains_box(frustum, render.origin - margin, render.origin + size + margin)
}

set_field_water_color :: proc(renderer: ^Field_Renderer, color: [4]f32) {
	color := color
	rl.SetShaderValue(renderer.material.shader, renderer.water_color_location, &color, .VEC4)
}

// The water pass: after all terrain, alpha blended (raylib's default
// blend), without depth writes; the back faces stay culled, so the
// water's faces against the ground, which face into it, are not drawn.
draw_field_water :: proc(renderer: ^Field_Renderer, visible: []Field_Node_Render) {
	set_field_water_color(renderer, FIELD_WATER_COLOR)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	for render in visible {
		if render.has_water {
			rl.DrawMesh(render.water, renderer.material, rl.MatrixTranslate(render.origin.x, render.origin.y, render.origin.z))
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// Must run between BeginMode3D and EndMode3D. The globe, then the
// selected nodes' terrain, then their water.
draw_field :: proc(renderer: ^Field_Renderer, camera: rl.Camera3D, selection: []Field_Node) {
	renderer.drawn_node_count = 0
	rl.DrawMesh(renderer.globe, renderer.globe_material, rl.Matrix(1))
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := render_frustum.frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	position := camera.position
	rl.SetShaderValue(renderer.material.shader, renderer.camera_position_location, &position, .VEC3)
	daylight := renderer.daylight
	rl.SetShaderValue(renderer.material.shader, renderer.daylight_location, &daylight, .FLOAT)
	set_field_water_color(renderer, {})
	visible := make([dynamic]Field_Node_Render, 0, len(selection), context.temp_allocator)
	for node in selection {
		render, found := renderer.meshes[node]
		if !found || !field_node_in_frustum(frustum, render, node, renderer.spacing_millimetres) {
			continue
		}
		append(&visible, render)
		if render.has_mesh {
			rl.DrawMesh(render.mesh, renderer.material, rl.MatrixTranslate(render.origin.x, render.origin.y, render.origin.z))
		}
		renderer.drawn_node_count += 1
	}
	draw_field_water(renderer, visible[:])
}

// UnloadMaterial also unloads the shader and the material tiles.
destroy_field_renderer :: proc(renderer: ^Field_Renderer) {
	for _, render in renderer.meshes {
		unload_field_node_render(render)
	}
	delete(renderer.meshes)
	destroy_field_tree_cache(&renderer.trees)
	delete(renderer.crouch_progress)
	rl.UnloadMesh(renderer.globe)
	rl.UnloadMaterial(renderer.globe_material)
	rl.UnloadMaterial(renderer.material)
	renderer^ = {}
}

// Point lights (work item 0175, render_point_lights.odin): the lights of
// working parts nearest the camera, uploaded before draw_field each frame.
// Unused slots go up with radius 0, which the shader skips. The terrain
// takes nothing from a clipped light (colour alpha 0, 0229), so field.fs
// needs no boxes and they do not go up.
set_field_point_lights :: proc(renderer: ^Field_Renderer, lights: [MAXIMUM_POINT_LIGHTS]Point_Light) {
	positions, colors, _ := point_light_uniform_values(lights)
	shader := renderer.material.shader
	rl.SetShaderValueV(shader, renderer.point_light_locations[0], &positions, .VEC4, MAXIMUM_POINT_LIGHTS)
	rl.SetShaderValueV(shader, renderer.point_light_locations[1], &colors, .VEC4, MAXIMUM_POINT_LIGHTS)
}
