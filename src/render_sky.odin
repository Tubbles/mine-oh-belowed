package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// The sky pass (work item 0064), drawn first inside BeginMode3D, centred
// on the camera, without depth test or depth writes, so everything else
// draws over it: a hemisphere dome coloured from the horizon to the zenith
// colour, stars at night turning with the day, then the sun and the moon
// as discs facing the camera along their own direction, so they stay
// round anywhere in the sky (work item 0092), the moon's phase a second disc in the sky colour
// overlapping it, and during a survey satellite's pass (work item 0069) a
// small bright quad crossing from west to east along the sun's path. The
// geometry, the star set and the colours are pure procedures; only the
// upload and the draw calls touch raylib. Render only, it reads nothing
// of the simulation but the day (Day_Sky) and the pass the frame passes.

// Well inside the far plane; with the depth test off the size only sets
// the scale of the discs and stars.
SKY_DOME_RADIUS :: 50.0
SKY_DOME_SEGMENTS :: 24
SKY_DOME_RINGS :: 8
SKY_DOME_VERTEX_COUNT :: SKY_DOME_SEGMENTS * SKY_DOME_RINGS + 1
SKY_DOME_TRIANGLE_COUNT :: (SKY_DOME_RINGS - 1) * SKY_DOME_SEGMENTS * 2 + SKY_DOME_SEGMENTS
// raylib's vertex buffer slot for colours
// (RL_DEFAULT_SHADER_ATTRIB_LOCATION_COLOR).
MESH_COLOR_BUFFER_INDEX :: 3
STAR_COUNT :: 500
STAR_SEED :: 0x5a17_57a2
STAR_SMALLEST_SIZE :: 0.08
STAR_LARGEST_SIZE :: 0.22
// Radius of the sun and moon discs as a share of the dome radius.
SUN_RADIUS_SHARE :: 0.04
MOON_RADIUS_SHARE :: 0.03
SUN_DISC_COLOR :: rl.Color{255, 248, 220, 255}
MOON_DISC_COLOR :: rl.Color{225, 230, 240, 255}
SATELLITE_SKY_SIZE :: 0.35
SATELLITE_SKY_COLOR :: rl.Color{255, 255, 250, 255}
DISC_TEXTURE_SIZE :: 64
// The disc's edge fades out over this many texels.
DISC_EDGE_TEXELS :: 1.5

Sky_Dome_Geometry :: struct {
	positions: [dynamic][3]f32,
	indices:   [dynamic]u16,
}

Sky_Renderer :: struct {
	dome:     rl.Mesh,
	material: rl.Material,
	disc:     rl.Texture2D,
}

// Ring 0 lies on the horizon, ring SKY_DOME_RINGS - 1 just below the apex,
// which is the last vertex.
sky_dome_vertex_direction :: proc(index: int) -> [3]f32 {
	if index == SKY_DOME_VERTEX_COUNT - 1 {
		return {0, 1, 0}
	}
	ring := index / SKY_DOME_SEGMENTS
	segment := index % SKY_DOME_SEGMENTS
	elevation := f32(ring) / SKY_DOME_RINGS * math.PI / 2
	azimuth := f32(segment) / SKY_DOME_SEGMENTS * math.TAU
	return {math.cos(azimuth) * math.cos(elevation), math.sin(elevation), math.sin(azimuth) * math.cos(elevation)}
}

// Two triangles per segment between neighbouring rings, a fan to the apex
// above the last ring, wound counter clockwise seen from inside.
append_sky_dome_triangles :: proc(indices: ^[dynamic]u16) {
	for ring in 0 ..< SKY_DOME_RINGS - 1 {
		for segment in 0 ..< SKY_DOME_SEGMENTS {
			next := (segment + 1) % SKY_DOME_SEGMENTS
			a := u16(ring * SKY_DOME_SEGMENTS + segment)
			b := u16(ring * SKY_DOME_SEGMENTS + next)
			c := u16((ring + 1) * SKY_DOME_SEGMENTS + segment)
			d := u16((ring + 1) * SKY_DOME_SEGMENTS + next)
			append(indices, a, b, c, b, d, c)
		}
	}
	top := (SKY_DOME_RINGS - 1) * SKY_DOME_SEGMENTS
	for segment in 0 ..< SKY_DOME_SEGMENTS {
		next := (segment + 1) % SKY_DOME_SEGMENTS
		append(indices, u16(top + segment), u16(top + next), u16(SKY_DOME_VERTEX_COUNT - 1))
	}
}

build_sky_dome :: proc(allocator := context.allocator) -> Sky_Dome_Geometry {
	geometry := Sky_Dome_Geometry {
		positions = make([dynamic][3]f32, 0, SKY_DOME_VERTEX_COUNT, allocator),
		indices   = make([dynamic]u16, 0, SKY_DOME_TRIANGLE_COUNT * 3, allocator),
	}
	for index in 0 ..< SKY_DOME_VERTEX_COUNT {
		append(&geometry.positions, sky_dome_vertex_direction(index) * SKY_DOME_RADIUS)
	}
	append_sky_dome_triangles(&geometry.indices)
	return geometry
}

destroy_sky_dome :: proc(geometry: Sky_Dome_Geometry) {
	delete(geometry.positions)
	delete(geometry.indices)
}

// The sky seen in a direction: the horizon colour at and below the
// horizon, the zenith colour straight up.
sky_color_towards :: proc(colors: Sky_Colors, direction: [3]f32) -> rl.Color {
	return mix_color(colors.horizon, colors.zenith, clamp(direction.y, 0, 1))
}

fill_sky_dome_colors :: proc(colors: Sky_Colors, vertex_colors: []rl.Color) {
	for &color, index in vertex_colors {
		color = sky_color_towards(colors, sky_dome_vertex_direction(index))
	}
}

// Rodrigues' rotation of a point about a unit axis.
rotate_about_axis :: proc(point, axis: [3]f32, angle: f32) -> [3]f32 {
	cosine := math.cos(angle)
	sine := math.sin(angle)
	return point * cosine + linalg.cross(axis, point) * sine + axis * linalg.dot(axis, point) * (1 - cosine)
}

hash_unit :: proc(key: u64) -> f32 {
	return f32(hash_u64(key) % 65536) / 65536
}

// A fixed direction, uniform over the sphere, per star.
star_direction :: proc(index: int) -> [3]f32 {
	key := u64(STAR_SEED) ~ (u64(index) << 8)
	height := 2 * hash_unit(key) - 1
	azimuth := hash_unit(key + 1) * math.TAU
	across := math.sqrt(1 - height * height)
	return {across * math.cos(azimuth), height, across * math.sin(azimuth)}
}

// 0.4 to 1.
star_brightness :: proc(index: int) -> f32 {
	return 0.4 + 0.6 * hash_unit(u64(STAR_SEED) ~ (u64(index) << 8) + 2)
}

// On the dome, relative to the camera, turned with the day about the sun
// path's axis like the sun.
star_position :: proc(index: int, fraction: f64) -> [3]f32 {
	return rotate_about_axis(star_direction(index), sun_path_axis(), f32(fraction * math.TAU)) * SKY_DOME_RADIUS
}

// Offset of the moon's shadow disc from the moon, in moon diameters along
// its path: 0 at new moon (covered), 2 at full moon; waxing and waning on
// opposite sides. At 1 or more the discs no longer overlap.
moon_shadow_offset :: proc(phase: f32) -> f32 {
	offset := 1 - math.cos(phase * math.TAU)
	return phase < 0.5 ? offset : -offset
}

// The direction along the moon's path, in which its shadow disc moves.
moon_path_tangent :: proc(fraction: f64) -> [3]f32 {
	return linalg.cross(sun_path_axis(), moon_direction(fraction))
}

multiply_color :: proc(color, tint: rl.Color) -> rl.Color {
	return {
		u8(u32(color.r) * u32(tint.r) / 255),
		u8(u32(color.g) * u32(tint.g) / 255),
		u8(u32(color.b) * u32(tint.b) / 255),
		u8(u32(color.a) * u32(tint.a) / 255),
	}
}

// White, opaque inside the disc, fading over edge_texels at its edge. The
// particles (render_particles.odin) take a small, softer one.
disc_pixels :: proc(size: int, edge_texels: f32 = DISC_EDGE_TEXELS, allocator := context.allocator) -> []rl.Color {
	pixels := make([]rl.Color, size * size, allocator)
	radius := f32(size) / 2
	for &pixel, index in pixels {
		offset := [2]f32{f32(index % size) + 0.5, f32(index / size) + 0.5} - radius
		coverage := clamp((radius - linalg.length(offset)) / edge_texels, 0, 1)
		pixel = {255, 255, 255, u8(coverage * 255 + 0.5)}
	}
	return pixels
}

upload_sky_dome :: proc() -> rl.Mesh {
	geometry := build_sky_dome()
	defer destroy_sky_dome(geometry)
	colors := make([]rl.Color, SKY_DOME_VERTEX_COUNT, context.temp_allocator)
	mesh := rl.Mesh {
		vertexCount   = SKY_DOME_VERTEX_COUNT,
		triangleCount = SKY_DOME_TRIANGLE_COUNT,
		vertices      = cast([^]f32)clone_for_raylib(geometry.positions[:]),
		colors        = cast([^]u8)clone_for_raylib(colors),
		indices       = clone_for_raylib(geometry.indices[:]),
	}
	rl.UploadMesh(&mesh, true)
	return mesh
}

upload_disc_texture :: proc(size: int = DISC_TEXTURE_SIZE, edge_texels: f32 = DISC_EDGE_TEXELS) -> rl.Texture2D {
	pixels := disc_pixels(size, edge_texels)
	defer delete(pixels)
	image := rl.Image {
		data    = raw_data(pixels),
		width   = i32(size),
		height  = i32(size),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := load_rgba_texture(image)
	rl.SetTextureFilter(texture, .BILINEAR)
	return texture
}

init_sky_renderer :: proc() -> Sky_Renderer {
	return Sky_Renderer{dome = upload_sky_dome(), material = rl.LoadMaterialDefault(), disc = upload_disc_texture()}
}

// UnloadMaterial keeps raylib's default shader and texture.
destroy_sky_renderer :: proc(renderer: ^Sky_Renderer) {
	rl.UnloadMesh(renderer.dome)
	rl.UnloadMaterial(renderer.material)
	rl.UnloadTexture(renderer.disc)
}

// The dome is seen from inside, so culling goes off with the depth test.
begin_sky_pass :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthTest()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
}

end_sky_pass :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthMask()
	rlgl.EnableDepthTest()
}

draw_sky_dome :: proc(renderer: ^Sky_Renderer, camera: rl.Camera3D, colors: Sky_Colors) {
	vertex_colors := (cast([^]rl.Color)renderer.dome.colors)[:SKY_DOME_VERTEX_COUNT]
	fill_sky_dome_colors(colors, vertex_colors)
	rl.UpdateMeshBuffer(renderer.dome, MESH_COLOR_BUFFER_INDEX, raw_data(vertex_colors), SKY_DOME_VERTEX_COUNT * size_of(rl.Color), 0)
	position := camera.position
	rl.DrawMesh(renderer.dome, renderer.material, rl.MatrixTranslate(position.x, position.y, position.z))
}

// One batch of quads on raylib's white default texture, the stars under
// the horizon left out.
draw_stars :: proc(camera: rl.Camera3D, sky: Day_Sky) {
	night := 1 - sky.blend
	if night <= 0 {
		return
	}
	white := rl.Texture2D {
		id      = rlgl.GetTextureIdDefault(),
		width   = 1,
		height  = 1,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	for index in 0 ..< STAR_COUNT {
		position := star_position(index, sky.fraction)
		if position.y <= 0 {
			continue
		}
		brightness := star_brightness(index)
		size := STAR_SMALLEST_SIZE + (STAR_LARGEST_SIZE - STAR_SMALLEST_SIZE) * brightness
		color := rl.Color{255, 255, 255, u8(night * brightness * 255)}
		rl.DrawBillboardRec(camera, white, {0, 0, 1, 1}, camera.position + position, {size, size}, color)
	}
}

// Unit right and up across a quad seen along direction, like a camera
// looking that way: right level with the horizon, up towards the zenith.
// Straight up or down the level reference is +x instead of +y. raylib's
// billboards take the camera's right and the world's up, which squashes a
// disc high in the sky into an ellipse.
disc_axes :: proc(direction: [3]f32) -> (right, up: [3]f32) {
	forward := linalg.normalize(direction)
	reference := abs(forward.y) < 0.99 ? [3]f32{0, 1, 0} : [3]f32{1, 0, 0}
	right = linalg.normalize(linalg.cross(forward, reference))
	up = linalg.cross(right, forward)
	return right, up
}

// A square of side size at centre, facing back along direction, with the
// whole texture on it. The sky pass has culling off, so the winding does
// not matter.
draw_sky_quad :: proc(texture: rl.Texture2D, centre, direction: [3]f32, size: f32, color: rl.Color) {
	right, up := disc_axes(direction)
	right, up = right * size / 2, up * size / 2
	corners := [4][3]f32{centre - right + up, centre - right - up, centre + right - up, centre + right + up}
	texture_coordinates := [4][2]f32{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	rlgl.SetTexture(texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for corner, index in corners {
		rlgl.TexCoord2f(texture_coordinates[index].x, texture_coordinates[index].y)
		rlgl.Vertex3f(corner.x, corner.y, corner.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// Left out once the whole disc is under the horizon.
draw_sky_disc :: proc(renderer: ^Sky_Renderer, camera: rl.Camera3D, direction: [3]f32, radius_share: f32, color: rl.Color) {
	if direction.y < -2 * radius_share {
		return
	}
	draw_sky_quad(renderer.disc, camera.position + direction * SKY_DOME_RADIUS, direction, 2 * radius_share * SKY_DOME_RADIUS, color)
}

draw_moon :: proc(renderer: ^Sky_Renderer, camera: rl.Camera3D, sky: Day_Sky) {
	direction := moon_direction(sky.fraction)
	draw_sky_disc(renderer, camera, direction, MOON_RADIUS_SHARE, MOON_DISC_COLOR)
	offset := moon_shadow_offset(moon_phase(sky.day_number))
	if abs(offset) >= 1 {
		return
	}
	diameter: f32 = 2 * MOON_RADIUS_SHARE
	shadow := linalg.normalize(direction + moon_path_tangent(sky.fraction) * offset * diameter)
	draw_sky_disc(renderer, camera, shadow, MOON_RADIUS_SHARE, sky_color_towards(sky.colors, direction))
}

// The satellite's direction: turned about the sun path's axis from the
// western horizon (the sun's setting point) back over the top to the
// eastern one (its rising point), against the sun's way.
satellite_sky_direction :: proc(pass: Satellite_Pass) -> [3]f32 {
	return sun_direction(0.5 * f64(1 - satellite_pass_fraction(pass)))
}

// One quad on raylib's white default texture, facing the camera along
// its direction like the discs.
draw_satellite :: proc(camera: rl.Camera3D, pass: Satellite_Pass) {
	if !pass.active {
		return
	}
	white := rl.Texture2D {
		id      = rlgl.GetTextureIdDefault(),
		width   = 1,
		height  = 1,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	direction := satellite_sky_direction(pass)
	draw_sky_quad(white, camera.position + direction * SKY_DOME_RADIUS, direction, SATELLITE_SKY_SIZE, SATELLITE_SKY_COLOR)
}

// Between BeginMode3D and EndMode3D, before anything else.
draw_sky :: proc(renderer: ^Sky_Renderer, camera: rl.Camera3D, sky: Day_Sky, satellite: Satellite_Pass) {
	begin_sky_pass()
	defer end_sky_pass()
	draw_sky_dome(renderer, camera, sky.colors)
	draw_stars(camera, sky)
	draw_sky_disc(renderer, camera, sun_direction(sky.fraction), SUN_RADIUS_SHARE, multiply_color(SUN_DISC_COLOR, sky.colors.sun_tint))
	draw_moon(renderer, camera, sky)
	draw_satellite(camera, satellite)
}
