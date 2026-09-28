package game

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// Drawing the weather (work item 0063), all from the weather of the
// frame (weather.odin), the render time and the camera, nothing of the
// simulation state: the fog distances of the day scaled per kind, the
// sky colours greyed and darkened in overcast and rain, sky light darker
// on wet ground, rain as short streaks and snow as small quads falling
// in a column around the camera, the sway strength of plants for the
// chunk vertex shader and the strength and drift of the cloud shadows
// for the chunk fragment shader. The look, the particle positions and
// the cloud noise are pure procedures; only the upload and the draw calls
// touch raylib.

// Particles at full intensity, of which those inside the cylinder are
// drawn (weather_particle_position).
WEATHER_PARTICLE_COUNT :: 600
WEATHER_PARTICLE_SEED :: 0x3a1f_0d5e
// The cylinder around the camera, in blocks: its radius, and its height,
// half of it above the camera.
WEATHER_RADIUS :: 12.0
WEATHER_HEIGHT :: 16.0
RAIN_FALL_SPEED :: 14.0
SNOW_FALL_SPEED :: 1.5
// Each particle falls at its speed times 0.8 to 1.2.
FALL_SPEED_SPREAD :: 0.4
RAIN_STREAK_LENGTH :: 0.6
SNOW_SIZE :: 0.09
// Snowflakes drift sideways by up to this many blocks.
SNOW_DRIFT :: 0.4
RAIN_COLOR :: rl.Color{175, 195, 225, 150}
SNOW_COLOR :: rl.Color{245, 248, 255, 230}
// The sky colours towards grey and darker at full gloom (rain).
WEATHER_DESATURATION :: 0.7
WEATHER_DARKENING :: 0.35
// Sky light on wet ground at full rain.
WET_GROUND_DARKENING :: 0.25
// Plants sway with this strength in clear weather, towards the kind's at
// full intensity; the vertex shader moves them up to 0.15 blocks at 1.
CLEAR_WIND_STRENGTH :: 0.3
CLEAR_CLOUD_SHADOW_STRENGTH :: 0.15
// The cloud shadow texture repeats every CLOUD_TILE_BLOCKS blocks (the
// same constant in data/shaders/chunk.fs) and drifts with the wind.
CLOUD_TEXTURE_SIZE :: 64
CLOUD_LATTICE_CELLS :: 8
CLOUD_TILE_BLOCKS :: 96.0
CLOUD_SEED :: 0x6c0d_5eed
CLOUD_DRIFT_SPEED :: 1.2
// The noise shaped into patches: clear below the first value, full shade
// above the second.
CLOUD_COVER_START :: 0.45
CLOUD_COVER_END :: 0.75
// wind_time wraps after this many seconds: a whole number of both wave
// periods in data/shaders/chunk.vs (3 and 7.5 seconds), so it never
// jumps.
WIND_TIME_WRAP_SECONDS :: 300.0

@(rodata)
weather_fog_scales := [Weather_Kind]f32 {
	.Clear    = 1,
	.Overcast = 0.8,
	.Rain     = 0.5,
	.Fog      = 0.25,
}

// How far the sky colours go towards grey and dark.
@(rodata)
weather_glooms := [Weather_Kind]f32 {
	.Clear    = 0,
	.Overcast = 0.6,
	.Rain     = 1,
	.Fog      = 0,
}

@(rodata)
weather_wind_strengths := [Weather_Kind]f32 {
	.Clear    = CLEAR_WIND_STRENGTH,
	.Overcast = 0.5,
	.Rain     = 1,
	.Fog      = 0.1,
}

@(rodata)
weather_cloud_shadow_strengths := [Weather_Kind]f32 {
	.Clear    = CLEAR_CLOUD_SHADOW_STRENGTH,
	.Overcast = 0.35,
	.Rain     = 0.35,
	.Fog      = 0,
}

// What the chunk shader gets from the weather each frame.
Weather_Look :: struct {
	fog_scale:             f32,
	wind_strength:         f32,
	cloud_shadow_strength: f32,
}

// The clear value at intensity 0, the kind's at 1.
blend_weather_value :: proc(clear_value, kind_value, intensity: f32) -> f32 {
	return clear_value + (kind_value - clear_value) * intensity
}

// enabled is the weather setting: off, nothing moves and no shadows fall.
// daylight is the day's blend: no cloud shadows at night.
weather_look :: proc(weather: Weather, enabled: bool, daylight: f32) -> Weather_Look {
	if !enabled {
		return Weather_Look{fog_scale = 1}
	}
	intensity := weather.intensity
	return Weather_Look {
		fog_scale = blend_weather_value(1, weather_fog_scales[weather.kind], intensity),
		wind_strength = blend_weather_value(CLEAR_WIND_STRENGTH, weather_wind_strengths[weather.kind], intensity),
		cloud_shadow_strength = blend_weather_value(CLEAR_CLOUD_SHADOW_STRENGTH, weather_cloud_shadow_strengths[weather.kind], intensity) * daylight,
	}
}

weather_fog_distances :: proc(load_radius_chunks: int, fog_scale: f32) -> (start, end: f32) {
	start, end = fog_distances(load_radius_chunks)
	return start * fog_scale, end * fog_scale
}

// gloom 0 keeps the colour, 1 greys it by WEATHER_DESATURATION and darkens
// it by WEATHER_DARKENING.
gloomy_color :: proc(color: rl.Color, gloom: f32) -> rl.Color {
	grey := u8(math.round(0.3 * f32(color.r) + 0.59 * f32(color.g) + 0.11 * f32(color.b)))
	greyed := mix_color(color, rl.Color{grey, grey, grey, color.a}, gloom * WEATHER_DESATURATION)
	return mix_color(greyed, rl.Color{0, 0, 0, color.a}, gloom * WEATHER_DARKENING)
}

// The day's sky under the weather: greyer and darker in overcast and
// rain, the sky light darker on wet ground in rain.
weathered_sky_colors :: proc(colors: Sky_Colors, weather: Weather) -> Sky_Colors {
	gloom := weather_glooms[weather.kind] * weather.intensity
	wet: f32 = weather.kind == .Rain ? WET_GROUND_DARKENING * weather.intensity : 0
	result := Sky_Colors {
		zenith   = gloomy_color(colors.zenith, gloom),
		horizon  = gloomy_color(colors.horizon, gloom),
		sun_tint = mix_color(colors.sun_tint, rl.Color{0, 0, 0, colors.sun_tint.a}, wet),
	}
	result.fog = result.horizon
	return result
}

weathered_day_sky :: proc(sky: Day_Sky, weather: Weather) -> Day_Sky {
	result := sky
	result.colors = weathered_sky_colors(sky.colors, weather)
	return result
}

// Wraps value into 0 to size.
wrap_f64 :: proc(value, size: f64) -> f64 {
	return value - size * math.floor(value / size)
}

// The cloud texture's offset in blocks, drifting with the wind.
cloud_offset :: proc(seconds: f64) -> [2]f32 {
	drift := seconds * CLOUD_DRIFT_SPEED
	return {f32(wrap_f64(drift, CLOUD_TILE_BLOCKS)), f32(wrap_f64(drift * 0.5, CLOUD_TILE_BLOCKS))}
}

wind_time :: proc(seconds: f64) -> f32 {
	return f32(wrap_f64(seconds, WIND_TIME_WRAP_SECONDS))
}

// Particles drawn this frame: the count scaled by the intensity and by
// how open the sky is at the camera (sky light 0 to 1), so none fall in
// a cave or under a roof.
weather_particle_count :: proc(intensity, open_sky: f32) -> int {
	return int(WEATHER_PARTICLE_COUNT * clamp(intensity, 0, 1) * clamp(open_sky, 0, 1))
}

// The particle's position, fixed in the world while it falls: its origin
// from a hash, moved down by its fall and wrapped into the square
// column of side 2 WEATHER_RADIUS and height WEATHER_HEIGHT around the
// camera, so walking does not drag the rain along. inside is false for
// the corners of the square outside the cylinder, which are not drawn.
weather_particle_position :: proc(index: int, camera: [3]f32, seconds: f64, fall_speed: f32) -> (position: [3]f32, inside: bool) {
	key := u64(WEATHER_PARTICLE_SEED) ~ (u64(index) << 8)
	side: f64 : 2 * WEATHER_RADIUS
	origin := [3]f64{f64(hash_unit(key)) * side, f64(hash_unit(key + 1)) * WEATHER_HEIGHT, f64(hash_unit(key + 2)) * side}
	speed := f64(fall_speed) * (1 - FALL_SPEED_SPREAD / 2 + FALL_SPEED_SPREAD * f64(hash_unit(key + 3)))
	low := [3]f64{f64(camera.x) - WEATHER_RADIUS, f64(camera.y) - WEATHER_HEIGHT / 2, f64(camera.z) - WEATHER_RADIUS}
	position = {
		f32(low.x + wrap_f64(origin.x - low.x, side)),
		f32(low.y + wrap_f64(origin.y - speed * seconds - low.y, WEATHER_HEIGHT)),
		f32(low.z + wrap_f64(origin.z - low.z, side)),
	}
	offset := position.xz - camera.xz
	return position, offset.x * offset.x + offset.y * offset.y <= WEATHER_RADIUS * WEATHER_RADIUS
}

// Sideways drift of a snowflake, phase shifted per particle.
snow_drift :: proc(index: int, seconds: f64) -> [3]f32 {
	phase := f64(hash_unit(u64(WEATHER_PARTICLE_SEED) ~ (u64(index) << 8) + 4)) * math.TAU
	return {f32(math.sin(seconds * 0.9 + phase)) * SNOW_DRIFT, 0, f32(math.cos(seconds * 0.7 + phase)) * SNOW_DRIFT}
}

// Value noise on a lattice of CLOUD_LATTICE_CELLS that wraps, so the
// texture tiles.
cloud_lattice_value :: proc(x, y: int) -> f32 {
	wrapped_x := (x % CLOUD_LATTICE_CELLS + CLOUD_LATTICE_CELLS) % CLOUD_LATTICE_CELLS
	wrapped_y := (y % CLOUD_LATTICE_CELLS + CLOUD_LATTICE_CELLS) % CLOUD_LATTICE_CELLS
	return hash_unit(u64(CLOUD_SEED) ~ (u64(wrapped_x) << 16) ~ (u64(wrapped_y) << 32))
}

cloud_noise :: proc(texel: [2]int, size: int) -> f32 {
	cell := [2]f32{f32(texel.x), f32(texel.y)} * CLOUD_LATTICE_CELLS / f32(size)
	corner := [2]int{int(cell.x), int(cell.y)}
	within := cell - [2]f32{f32(corner.x), f32(corner.y)}
	weight := within * within * (3 - 2 * within)
	bottom := math.lerp(cloud_lattice_value(corner.x, corner.y), cloud_lattice_value(corner.x + 1, corner.y), weight.x)
	top := math.lerp(cloud_lattice_value(corner.x, corner.y + 1), cloud_lattice_value(corner.x + 1, corner.y + 1), weight.x)
	return math.lerp(bottom, top, weight.y)
}

// The shade of each texel in red, green and blue: 0 open sky, 1 full
// cloud.
cloud_pixels :: proc(size: int, allocator := context.allocator) -> []rl.Color {
	pixels := make([]rl.Color, size * size, allocator)
	for &pixel, index in pixels {
		cover := f32(smoothstep(CLOUD_COVER_START, CLOUD_COVER_END, f64(cloud_noise({index % size, index / size}, size))))
		shade := u8(math.round(cover * 255))
		pixel = {shade, shade, shade, 255}
	}
	return pixels
}

// Repeats (raylib's default wrap), filtered so the edges are soft.
upload_cloud_texture :: proc() -> rl.Texture2D {
	pixels := cloud_pixels(CLOUD_TEXTURE_SIZE)
	defer delete(pixels)
	image := rl.Image {
		data    = raw_data(pixels),
		width   = CLOUD_TEXTURE_SIZE,
		height  = CLOUD_TEXTURE_SIZE,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(texture, .BILINEAR)
	return texture
}

// Rain as streaks falling to the particle's position, snow as small
// quads. light is the sky light colour of the frame, so the rain is not
// bright at night. Depth test on so no particle shows through a wall,
// depth writes off like the item billboards.
draw_weather :: proc(camera: rl.Camera3D, precipitation: Precipitation, count: int, seconds: f64, light: [3]f32) {
	if precipitation == .None || count <= 0 {
		return
	}
	light_color := rl.Color{u8(clamp(light.r, 0, 1) * 255), u8(clamp(light.g, 0, 1) * 255), u8(clamp(light.b, 0, 1) * 255), 255}
	begin_item_billboards()
	defer end_item_billboards()
	if precipitation == .Rain {
		draw_rain(camera, count, seconds, multiply_color(RAIN_COLOR, light_color))
	} else {
		draw_snow(camera, count, seconds, multiply_color(SNOW_COLOR, light_color))
	}
}

draw_rain :: proc(camera: rl.Camera3D, count: int, seconds: f64, color: rl.Color) {
	for index in 0 ..< count {
		bottom, inside := weather_particle_position(index, camera.position, seconds, RAIN_FALL_SPEED)
		if inside {
			rl.DrawLine3D(bottom + {0, RAIN_STREAK_LENGTH, 0}, bottom, color)
		}
	}
}

// Quads on raylib's white default texture, like the stars.
draw_snow :: proc(camera: rl.Camera3D, count: int, seconds: f64, color: rl.Color) {
	white := rl.Texture2D {
		id      = rlgl.GetTextureIdDefault(),
		width   = 1,
		height  = 1,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	for index in 0 ..< count {
		position, inside := weather_particle_position(index, camera.position, seconds, SNOW_FALL_SPEED)
		if inside {
			rl.DrawBillboardRec(camera, white, {0, 0, 1, 1}, position + snow_drift(index, seconds), {SNOW_SIZE, SNOW_SIZE}, color)
		}
	}
}
