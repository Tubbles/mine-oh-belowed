package game

import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"
import "render_frustum"

// The terrain field's renderer (work item 0169, doc/presentation.md, Chunk
// meshes): one raylib mesh per selected octree node (world_field_lod.odin),
// drawn with the triplanar shader (data/shaders/field.vs and field.fs) and
// the ground atlas of the materials' and the looks' tiles
// (texture_field_materials.odin), and the globe, a sphere in the ground's
// colour (field_globe_color) drawn every frame below the lowest ground
// the relief can make, so the meshed nodes cover it where they exist and
// it fills the planet's silhouette beyond the last distance; it draws
// through the model shader's lit material (draw_field_globe), lit and
// hazed as the terrain is.
// Each node also carries the water's mesh (0172), drawn after every
// node's terrain through the same shader with water_color set:
// translucent, alpha blended and without depth writes, so the terrain
// shows through and the water never hides the water behind it. The
// field light (0173) reaches the shader per vertex, the sky light gating
// the open sky's light (0313: the sun, the sky from above and the
// ground's bounce from below) and its haze; those and the torchlight
// (0297, render_point_lights.odin) are set per draw
// (set_field_frame_lights), since each viewer's up turns the sun. The
// finest nodes also carry the ground cover's instances (0311,
// render_field_cover.odin), drawn between the terrain and the water.

FIELD_VERTEX_SHADER_PATH :: "shaders/field.vs"
FIELD_FRAGMENT_SHADER_PATH :: "shaders/field.fs"
FIELD_GLOBE_RINGS :: 64
FIELD_GLOBE_SLICES :: 128
// Below the lowest relief: a coarsest cell, which also holds the sphere's
// facets (about 2.4 m deep at 8 km) under the ground.
FIELD_GLOBE_MARGIN_METRES :: 8
// The water pass's colour and opacity (the shader's water_color); the
// terrain pass sets an opacity of 0.
FIELD_WATER_COLOR :: [4]f32{0.16, 0.36, 0.52, 0.62}

// The ground atlas's sampler, bound to the material's map 0 (DrawMesh
// binds map i to the shader location MAP_ALBEDO + i).
FIELD_GROUND_ATLAS_SAMPLER :: "ground_atlas"
// A uniform of field.fs since the open sky (0313), whose absence marks an
// older copy.
FIELD_HAZE_UNIFORM :: "haze_color"
// A uniform of field.fs since the sun's shadow (0328), likewise.
FIELD_SUN_SHADOW_UNIFORM :: "sun_shadow_strength"

#assert(FIELD_MATERIAL_TILE_COUNT == FIELD_TEXTURED_MATERIAL_COUNT, "every generated material tile is a tile of the atlas")

// origin is the node's first sample in metres. A node with no water has
// has_water false and no water mesh. cover holds a finest node's ground
// cover per kind (0311). terrain_hash is the terrain mesh's depth hash
// (field_mesh_depth_hash, the sun's kept shadow maps' fingerprint, 0348).
Field_Node_Render :: struct {
	mesh:         rl.Mesh,
	water:        rl.Mesh,
	has_mesh:     bool,
	has_water:    bool,
	origin:       [3]f32,
	vertex_count: int,
	cover:        [MAXIMUM_COVER_KINDS]Field_Cover_Node_Draw,
	terrain_hash: u64,
}

Field_Renderer :: struct {
	material:                 rl.Material,
	camera_position_location: i32,
	water_color_location:     i32,
	// The point lights' uniforms (0175, set_field_point_lights).
	point_light_locations:    [2]i32,
	// The open sky's (0313) and the torchlight's (0297,
	// set_field_frame_lights): the spot's position, direction, cos_inner,
	// cos_outer, range and colour.
	open_sky_locations:       [Open_Sky_Uniform]i32,
	spot_locations:           [6]i32,
	globe:                    rl.Mesh,
	// The globe's colour, 0 to 1 (field_globe_color): its albedo and the
	// ground's bounce (Field_Light_Inputs.ground_color).
	globe_color:              [3]f32,
	// The last level of detail's distance in metres, where the haze's end
	// fade ends. prepare_field_frame sets it every frame from the frame's
	// distances, inside the view distance setting (0343); the planet
	// preview keeps the data's value from init_field_renderer.
	last_distance_metres:     f32,
	spacing_millimetres:      int,
	meshes:                   map[Field_Node]Field_Node_Render,
	// Counts every change of meshes (apply_field_mesh, unload_field_node),
	// so the sun's kept shadow maps know when to fingerprint the terrain
	// (0348).
	mesh_revision:            u64,
	vertex_count:             int,
	drawn_node_count:         int,
	// The trees round the eyes (0197, render_field_trees.odin).
	trees:                    Field_Tree_Cache,
	// Each player's eased crouch by player index, advanced in
	// prepare_field_frame (0218).
	crouch_progress:          [dynamic]f32,
	// Each material tile's mean texel, 0 to 1 (the debris' colours, 0272).
	material_colors:          [FIELD_MATERIAL_TILE_COUNT][3]f32,
	// The grass tile's mean texel, 0 to 1 (the globe's and the cover's
	// grass, 0311).
	grass_color:              [3]f32,
	// The ground cover's shader and kinds (0311, init_field_cover_renderer).
	cover:                    Field_Cover_Renderer,
	// The sun's shadow map (0328, render_sun_shadows.odin) and the field
	// shader's uniforms that read it.
	sun_shadows:              Sun_Shadow_Renderer,
	sun_shadow_locations:     [Sun_Shadow_Uniform]i32,
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

// The ground atlas (field_ground_atlas_pixels), trilinear with mipmaps
// and clamped: the shader wraps each tile itself inside its cell and reads
// it by level (textureLod), so no read crosses a cell.
upload_field_ground_atlas :: proc(tiles: Field_Ground_Tiles) -> rl.Texture2D {
	pixels := field_ground_atlas_pixels(tiles, context.temp_allocator)
	image := rl.Image {
		data    = raw_data(pixels),
		width   = FIELD_GROUND_ATLAS_TEXELS,
		height  = FIELD_GROUND_ATLAS_TEXELS,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := load_rgba_texture(image)
	rl.GenTextureMipmaps(&texture)
	rl.SetTextureFilter(texture, .TRILINEAR)
	rl.SetTextureWrap(texture, .CLAMP)
	return texture
}

// The look's uniforms (0307): on with a climate, and the sand's and the
// snow's colours from 0 to 1; the grass colour comes per vertex.
set_field_ground_look_uniforms :: proc(shader: rl.Shader, planet: Planet) {
	set_shader_float(shader, "ground_look_on", planet.climate != {} ? 1 : 0)
	sand := field_color_float(planet.climate.sand_color) / 255
	snow := field_color_float(planet.climate.snow_color) / 255
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "sand_color"), &sand, .VEC3)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "snow_color"), &snow, .VEC3)
}

use_field_shader :: proc(renderer: ^Field_Renderer, shader: rl.Shader) {
	shader.locs[int(rl.ShaderLocationIndex.MAP_ALBEDO)] = rl.GetShaderLocation(shader, FIELD_GROUND_ATLAS_SAMPLER)
	renderer.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	renderer.water_color_location = rl.GetShaderLocation(shader, "water_color")
	renderer.point_light_locations = {rl.GetShaderLocation(shader, "point_light_positions"), rl.GetShaderLocation(shader, "point_light_colors")}
	renderer.open_sky_locations = open_sky_locations(shader)
	renderer.spot_locations = spot_light_locations(shader)
	renderer.sun_shadow_locations = use_sun_shadow_sampler(shader)
	renderer.material.shader = shader
}

field_globe_radius_metres :: proc(planet: Planet) -> f32 {
	return f32(planet.radius_metres - relief_depth_metres(planet_relief_bounds(planet)) - FIELD_GLOBE_MARGIN_METRES)
}

// With a climate the temperate moderate grass anchor as the grass tile
// shows it (its mean times the shader's tint_scale), so the far planet
// reads green; without one the palette's first colour.
field_globe_color :: proc(planet: Planet, grass_mean: [3]f32) -> rl.Color {
	if planet.climate == {} {
		color := planet.palette[0]
		return {u8(color.r), u8(color.g), u8(color.b), 255}
	}
	color := field_color_bytes(field_color_float(planet.climate.grass_colors[4]) * grass_mean * 2)
	return {color.r, color.g, color.b, 255}
}

// False with an error line when the shaders do not load or the fragment
// shader has no ground atlas, no haze or no sun's shadow: a copy older
// than the looks (0307), the open sky (0313) or the shadow (0328) links
// with today's vertex shader on desktop GL, so the load alone does not
// catch it.
// fog_end is the last level of detail distance in metres.
init_field_renderer :: proc(data_directory: string, tiles: Field_Ground_Tiles, planet: Planet, spacing_millimetres: int, fog_end: f32) -> (renderer: Field_Renderer, ok: bool) {
	shader := load_shader_pair(data_directory, FIELD_VERTEX_SHADER_PATH, FIELD_FRAGMENT_SHADER_PATH, "field") or_return
	if rl.GetShaderLocation(shader, FIELD_GROUND_ATLAS_SAMPLER) < 0 {
		platform.log_printf("error: the field shader from %s and %s has no %s, a copy older than the ground's looks", FIELD_VERTEX_SHADER_PATH, FIELD_FRAGMENT_SHADER_PATH, FIELD_GROUND_ATLAS_SAMPLER)
		rl.UnloadShader(shader)
		return {}, false
	}
	if rl.GetShaderLocation(shader, FIELD_HAZE_UNIFORM) < 0 {
		platform.log_printf("error: the field shader from %s and %s has no %s, a copy older than the open sky's light", FIELD_VERTEX_SHADER_PATH, FIELD_FRAGMENT_SHADER_PATH, FIELD_HAZE_UNIFORM)
		rl.UnloadShader(shader)
		return {}, false
	}
	if rl.GetShaderLocation(shader, FIELD_SUN_SHADOW_UNIFORM) < 0 {
		platform.log_printf("error: the field shader from %s and %s has no %s, a copy older than the sun's shadow", FIELD_VERTEX_SHADER_PATH, FIELD_FRAGMENT_SHADER_PATH, FIELD_SUN_SHADOW_UNIFORM)
		rl.UnloadShader(shader)
		return {}, false
	}
	renderer.material = rl.LoadMaterialDefault()
	use_field_shader(&renderer, shader)
	set_field_ground_look_uniforms(shader, planet)
	rl.SetMaterialTexture(&renderer.material, .ALBEDO, upload_field_ground_atlas(tiles))
	for slot in 0 ..< FIELD_MATERIAL_TILE_COUNT {
		renderer.material_colors[slot] = tile_mean_color(tiles[slot])
	}
	renderer.globe = rl.GenMeshSphere(field_globe_radius_metres(planet), FIELD_GLOBE_RINGS, FIELD_GLOBE_SLICES)
	renderer.grass_color = tile_mean_color(tiles[field_look_tile(.Grass)])
	renderer.globe_color = color_to_vector3(field_globe_color(planet, renderer.grass_color))
	renderer.last_distance_metres = fog_end
	renderer.spacing_millimetres = spacing_millimetres
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
		texcoords2    = cast([^]f32)clone_for_raylib(data.looks[:]),
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
	unload_field_cover_node(render.cover)
}

unload_field_node :: proc(renderer: ^Field_Renderer, node: Field_Node) {
	if previous, found := renderer.meshes[node]; found {
		renderer.vertex_count -= previous.vertex_count
		unload_field_node_render(previous)
		delete_key(&renderer.meshes, node)
		renderer.mesh_revision += 1
	}
}

field_node_origin_metres :: proc(node: Field_Node, spacing_millimetres: int) -> [3]f32 {
	origin := field_node_origin(node)
	metres_per_sample := f64(spacing_millimetres) / MILLIMETRES_PER_METRE
	return {f32(f64(origin.x) * metres_per_sample), f32(f64(origin.y) * metres_per_sample), f32(f64(origin.z) * metres_per_sample)}
}

// Replaces the node's meshes and its cover (0311) and moves the mesh
// revision. Two empty meshes only remove the old ones. terrain_hash is
// the terrain mesh's (field_mesh_depth_hash, 0348). The data stays the
// caller's.
apply_field_mesh :: proc(renderer: ^Field_Renderer, node: Field_Node, data, water: Field_Mesh_Data, terrain_hash: u64, cover: Field_Cover_Data = {}) {
	unload_field_node(renderer, node)
	renderer.mesh_revision += 1
	if len(data.indices) == 0 && len(water.indices) == 0 {
		return
	}
	render := Field_Node_Render {
		origin       = field_node_origin_metres(node, renderer.spacing_millimetres),
		vertex_count = len(data.positions) + len(water.positions),
		terrain_hash = terrain_hash,
	}
	if len(data.indices) > 0 {
		render.mesh, render.has_mesh = upload_field_mesh(data), true
	}
	if len(water.indices) > 0 {
		render.water, render.has_water = upload_field_mesh(water), true
	}
	render.cover = upload_field_cover(renderer.cover, cover)
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
		apply_field_mesh(renderer, result.node, result.mesh, result.water_mesh, result.terrain_hash, result.cover)
		destroy_field_mesh_data(result.mesh)
		destroy_field_mesh_data(result.water_mesh)
		destroy_field_cover_data(result.cover)
	}
}

// A node's box in metres: its cube from the origin, widened by the cells
// below the origin and the skirts, which reach three cells past it.
field_node_box_metres :: proc(render: Field_Node_Render, node: Field_Node, spacing_millimetres: int) -> (minimum, maximum: [3]f32) {
	size := f32(f64(field_node_samples(node.level)) * f64(spacing_millimetres) / MILLIMETRES_PER_METRE)
	margin := size / FIELD_GRID_CELLS * 4
	return render.origin - margin, render.origin + size + margin
}

field_node_in_frustum :: proc(frustum: render_frustum.Frustum, render: Field_Node_Render, node: Field_Node, spacing_millimetres: int) -> bool {
	minimum, maximum := field_node_box_metres(render, node, spacing_millimetres)
	return render_frustum.frustum_contains_box(frustum, minimum, maximum)
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
			count_draw_call()
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// The shaders' spot_ uniforms in Spot_Light's field order (field.fs and
// model.fs declare the same six).
spot_light_locations :: proc(shader: rl.Shader) -> [6]i32 {
	return {
		rl.GetShaderLocation(shader, "spot_position"),
		rl.GetShaderLocation(shader, "spot_direction"),
		rl.GetShaderLocation(shader, "spot_cos_inner"),
		rl.GetShaderLocation(shader, "spot_cos_outer"),
		rl.GetShaderLocation(shader, "spot_range"),
		rl.GetShaderLocation(shader, "spot_color"),
	}
}

set_spot_light_uniforms :: proc(shader: rl.Shader, locations: [6]i32, spot: Spot_Light) {
	spot := spot
	rl.SetShaderValue(shader, locations[0], &spot.position, .VEC3)
	rl.SetShaderValue(shader, locations[1], &spot.direction, .VEC3)
	rl.SetShaderValue(shader, locations[2], &spot.cos_inner, .FLOAT)
	rl.SetShaderValue(shader, locations[3], &spot.cos_outer, .FLOAT)
	rl.SetShaderValue(shader, locations[4], &spot.range, .FLOAT)
	rl.SetShaderValue(shader, locations[5], &spot.color, .VEC3)
}

// The open sky's uniforms of field.fs and model.fs (0313, the same
// declarations in both): the light's and the haze's.
Open_Sky_Uniform :: enum {
	Sun_Direction,
	Sun_Color,
	Sky_Color,
	Bounce_Color,
	Haze_Color,
	Haze_Sun_Color,
	Haze_Density,
	Haze_Scale_Height,
	Haze_End_Share,
	Globe_Color,
	Planet_Radius,
	Eye_Height,
	Fog_Start,
	Fog_End,
}

OPEN_SKY_UNIFORM_NAMES :: [Open_Sky_Uniform]cstring {
	.Sun_Direction     = "sun_direction",
	.Sun_Color         = "sun_color",
	.Sky_Color         = "sky_color",
	.Bounce_Color      = "bounce_color",
	.Haze_Color        = "haze_color",
	.Haze_Sun_Color    = "haze_sun_color",
	.Haze_Density      = "haze_density",
	.Haze_Scale_Height = "haze_scale_height",
	.Haze_End_Share    = "haze_end_share",
	.Globe_Color       = "globe_color",
	.Planet_Radius     = "planet_radius",
	.Eye_Height        = "eye_height",
	.Fog_Start         = "fog_start",
	.Fog_End           = "fog_end",
}

open_sky_locations :: proc(shader: rl.Shader) -> (locations: [Open_Sky_Uniform]i32) {
	names := OPEN_SKY_UNIFORM_NAMES
	for name, uniform in names {
		locations[uniform] = rl.GetShaderLocation(shader, name)
	}
	return locations
}

// Every frame, on both shaders, for the viewer the lights are for.
set_open_sky_uniforms :: proc(shader: rl.Shader, locations: [Open_Sky_Uniform]i32, lights: Field_Frame_Lights) {
	lights := lights
	haze := &lights.haze
	rl.SetShaderValue(shader, locations[.Sun_Direction], &lights.sun_direction, .VEC3)
	rl.SetShaderValue(shader, locations[.Sun_Color], &lights.sun_color, .VEC3)
	rl.SetShaderValue(shader, locations[.Sky_Color], &lights.sky_color, .VEC3)
	rl.SetShaderValue(shader, locations[.Bounce_Color], &lights.bounce_color, .VEC3)
	rl.SetShaderValue(shader, locations[.Haze_Color], &haze.color, .VEC3)
	rl.SetShaderValue(shader, locations[.Haze_Sun_Color], &haze.sun_color, .VEC3)
	rl.SetShaderValue(shader, locations[.Haze_Density], &haze.density, .FLOAT)
	rl.SetShaderValue(shader, locations[.Haze_Scale_Height], &haze.scale_height, .FLOAT)
	rl.SetShaderValue(shader, locations[.Haze_End_Share], &haze.end_share, .FLOAT)
	rl.SetShaderValue(shader, locations[.Globe_Color], &haze.globe_color, .VEC3)
	rl.SetShaderValue(shader, locations[.Planet_Radius], &haze.planet_radius, .FLOAT)
	rl.SetShaderValue(shader, locations[.Eye_Height], &haze.eye_height, .FLOAT)
	rl.SetShaderValue(shader, locations[.Fog_Start], &haze.fog_start, .FLOAT)
	rl.SetShaderValue(shader, locations[.Fog_End], &haze.fog_end, .FLOAT)
}

// The open sky's light and haze (0313), the torchlight (0297) and the
// sun's shadow (0328), before the terrain so the water pass and the cover
// (0311) share them.
set_field_frame_lights :: proc(renderer: ^Field_Renderer, lights: Field_Frame_Lights) {
	shader := renderer.material.shader
	set_open_sky_uniforms(shader, renderer.open_sky_locations, lights)
	set_spot_light_uniforms(shader, renderer.spot_locations, lights.spot)
	set_sun_shadow_uniforms(shader, renderer.sun_shadow_locations, lights.sun_shadow)
	set_field_cover_frame_lights(renderer.cover, lights)
}

// The globe through the model shader's lit material (0313), lit and
// hazed as an open sky model: its albedo times the flat light the CPU
// gives a model (daylight_tint), which the shader divides out again.
// GenMeshSphere has normals and no colours, which default to white. The
// model shader's open sky must be set first (set_model_open_sky).
draw_field_globe :: proc(renderer: ^Field_Renderer, models: Model_Renderer, daylight_tint: [3]f32) {
	material := model_layer_material(models, .Lit)
	material.maps[rl.MaterialMapIndex.ALBEDO].color = brightness_color(renderer.globe_color * daylight_tint)
	rl.DrawMesh(renderer.globe, material, rl.Matrix(1))
	count_draw_call()
}

// Must run between BeginMode3D and EndMode3D, after the globe. The
// selected nodes' terrain, then the cover on the visible ones (0311),
// then their water, lit by the frame's open sky and torchlight. A frame
// profile (0342) gets the Cover and Water marks and the counts.
draw_field :: proc(renderer: ^Field_Renderer, camera: rl.Camera3D, selection: []Field_Node, lights: Field_Frame_Lights, profile: ^Frame_Profile = nil) {
	renderer.drawn_node_count = 0
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := render_frustum.frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	position := camera.position
	rl.SetShaderValue(renderer.material.shader, renderer.camera_position_location, &position, .VEC3)
	set_field_frame_lights(renderer, lights)
	set_field_water_color(renderer, {})
	visible := make([dynamic]Field_Node_Render, 0, len(selection), context.temp_allocator)
	triangles, water_nodes := 0, 0
	for node in selection {
		render, found := renderer.meshes[node]
		if !found || !field_node_in_frustum(frustum, render, node, renderer.spacing_millimetres) {
			continue
		}
		append(&visible, render)
		if render.has_mesh {
			rl.DrawMesh(render.mesh, renderer.material, rl.MatrixTranslate(render.origin.x, render.origin.y, render.origin.z))
			count_draw_call()
			triangles += int(render.mesh.triangleCount)
		}
		water_nodes += render.has_water ? 1 : 0
		renderer.drawn_node_count += 1
	}
	count_frame(profile, .Terrain_Nodes, renderer.drawn_node_count)
	count_frame(profile, .Terrain_Triangles, triangles)
	count_frame(profile, .Water_Nodes, water_nodes)
	profile_mark(profile, .Cover)
	draw_field_cover(renderer, camera, visible[:], lights.sun_shadow.texture)
	count_frame(profile, .Cover_Instances, renderer.cover.drawn_count)
	profile_mark(profile, .Water)
	draw_field_water(renderer, visible[:])
}

// The selected nodes not yet drawable (0342, profile settle): a node is
// meshed once it is in the mesh revisions and either has its meshes up or
// no job of it is in flight (a node meshed empty has none).
field_view_unmeshed_nodes :: proc(streaming: ^Field_Streaming, renderer: ^Field_Renderer, selection: []Field_Node) -> int {
	count := 0
	for node in selection {
		_, rendered := renderer.meshes[node]
		meshed := node in streaming.mesh_revisions && (rendered || node not_in streaming.in_flight)
		count += meshed ? 0 : 1
	}
	return count
}

// UnloadMaterial also unloads the shader and the ground atlas; the sun's
// shadow map goes first (0328), the receivers' slots cleared, so no
// material deletes a texture the map owns. models are the receivers'
// (sun_shadow_receivers), {} without them.
destroy_field_renderer :: proc(renderer: ^Field_Renderer, models: Model_Renderer) {
	receivers := sun_shadow_receivers(renderer, models)
	release_sun_shadow_map(&renderer.sun_shadows, receivers[:])
	for _, render in renderer.meshes {
		unload_field_node_render(render)
	}
	delete(renderer.meshes)
	destroy_field_tree_cache(&renderer.trees)
	destroy_field_cover_renderer(&renderer.cover)
	delete(renderer.crouch_progress)
	rl.UnloadMesh(renderer.globe)
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
	set_field_cover_point_lights(renderer.cover, &positions, &colors)
}
