package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"

// The cosmetic day and night cycle, a function of the simulation tick
// alone. It sets the sky colours, the fog colour, the sun and moon
// directions and how much sky light reaches the shader, and in which
// colour (work item 0064). Block light is neither scaled nor tinted, so
// torches glow the same at night. On the field the sun also lights the
// slopes (0297, field_sun_world_direction): the sky is drawn about the
// viewer's up, so the sun the field shades by is the sky's turned back
// into the world's frame. The field's open sky light (0313,
// field_frame_lights) takes its colours from here: the sun's from the
// data's high and low colours by the sun's height (sun_light_color),
// the sky's from the dome's colours (sky_light_color), the ground's
// bounce from both (ground_bounce_color) and the haze's warm glow
// towards a low sun (haze_sun_glow_color).

DAY_SKY_COLOR :: rl.Color{150, 190, 230, 255}
NIGHT_SKY_COLOR :: rl.Color{12, 16, 32, 255}
DAY_HORIZON_COLOR :: rl.Color{200, 222, 240, 255}
NIGHT_HORIZON_COLOR :: rl.Color{28, 34, 58, 255}
// The horizon in the middle of dawn and dusk.
DUSK_HORIZON_COLOR :: rl.Color{240, 140, 70, 255}
// The colour sky light takes: white by day, warm at dawn and dusk, blue
// grey at night.
DAY_SUN_TINT :: rl.Color{255, 255, 255, 255}
DUSK_SUN_TINT :: rl.Color{255, 196, 140, 255}
NIGHT_SUN_TINT :: rl.Color{170, 185, 230, 255}
// Share of full sky light left at midnight, so moonlit ground stays visible.
NIGHT_DAY_FACTOR :: 0.2
// The world starts a little after sunrise.
DAY_START_FRACTION :: 0.05
NOON_FRACTION :: 0.25
// Sun heights, as the sine of the day fraction, between which dawn and
// dusk blend night into day.
TWILIGHT_START :: -0.2
TWILIGHT_END :: 0.25
// The dawn and dusk colours are full with the sun on the horizon and gone
// this far above or below it, in sun height.
TWILIGHT_GLOW_HALF_WIDTH :: 0.2
// The sun's path leans this far towards +z, so it never passes straight
// overhead.
SUN_PATH_TILT_DEGREES :: 20.0
// Days from one new moon to the next.
MOON_CYCLE_DAYS :: 8
// The field's sun light (0313, sun_light_color), by the sun's height
// (sun_direction's y): off below SUN_LIGHT_SET_HEIGHT, full above
// SUN_LIGHT_RISEN_HEIGHT, the low colour on the horizon turning to the
// high one by SUN_HIGH_HEIGHT.
SUN_LIGHT_SET_HEIGHT :: -0.05
SUN_LIGHT_RISEN_HEIGHT :: 0.05
SUN_HIGH_HEIGHT :: 0.5
// The zenith's share of the sky's light on an upward face: the cosine
// weighted mean of a dome whose colour is linear in the sine of the
// elevation, as sky_color_towards draws it.
SKY_LIGHT_ZENITH_SHARE :: 2.0 / 3.0

Sky_Colors :: struct {
	zenith:   rl.Color,
	horizon:  rl.Color,
	// The horizon colour, so chunks fade into the sky at the horizon.
	fog:      rl.Color,
	// Multiplies sky light in the chunk shader and on models.
	sun_tint: rl.Color,
}

// Everything the renderer draws of the day at one moment.
Day_Sky :: struct {
	fraction:   f64,
	day_number: u64,
	blend:      f32,
	colors:     Sky_Colors,
}

// 0 to 1 since sunrise: the sun rises at 0, peaks at 0.25, sets at 0.5
// and is lowest at 0.75.
day_fraction :: proc(tick, day_length_ticks: u64) -> f64 {
	fraction := f64(tick % day_length_ticks) / f64(day_length_ticks) + DAY_START_FRACTION
	return fraction - math.floor(fraction)
}

// The sine of the day fraction, 1 at noon and -1 at midnight.
sun_height :: proc(fraction: f64) -> f64 {
	return math.sin(fraction * math.TAU)
}

blend_for_sun_height :: proc(height: f64) -> f32 {
	return f32(smoothstep(TWILIGHT_START, TWILIGHT_END, height))
}

// 0 at night, 1 by day, smooth in between.
daylight_blend :: proc(tick, day_length_ticks: u64) -> f32 {
	return blend_for_sun_height(sun_height(day_fraction(tick, day_length_ticks)))
}

// 1 with the sun on the horizon, 0 from TWILIGHT_GLOW_HALF_WIDTH away.
twilight_share :: proc(height: f64) -> f32 {
	return f32(1 - smoothstep(0, TWILIGHT_GLOW_HALF_WIDTH, abs(height)))
}

// The factor the shader multiplies sky light by, NIGHT_DAY_FACTOR to 1.
day_factor :: proc(blend: f32) -> f32 {
	return NIGHT_DAY_FACTOR + (1 - NIGHT_DAY_FACTOR) * blend
}

mix_color :: proc(from, to: rl.Color, share: f32) -> rl.Color {
	start := [4]f32{f32(from.r), f32(from.g), f32(from.b), f32(from.a)}
	end := [4]f32{f32(to.r), f32(to.g), f32(to.b), f32(to.a)}
	mixed := start + (end - start) * share
	return rl.Color{u8(math.round(mixed.r)), u8(math.round(mixed.g)), u8(math.round(mixed.b)), u8(math.round(mixed.a))}
}

// The zenith colour.
sky_color :: proc(blend: f32) -> rl.Color {
	return mix_color(NIGHT_SKY_COLOR, DAY_SKY_COLOR, blend)
}

sky_colors :: proc(fraction: f64) -> Sky_Colors {
	height := sun_height(fraction)
	blend := blend_for_sun_height(height)
	warm := twilight_share(height)
	horizon := mix_color(mix_color(NIGHT_HORIZON_COLOR, DAY_HORIZON_COLOR, blend), DUSK_HORIZON_COLOR, warm)
	return Sky_Colors {
		zenith = sky_color(blend),
		horizon = horizon,
		fog = horizon,
		sun_tint = mix_color(mix_color(NIGHT_SUN_TINT, DAY_SUN_TINT, blend), DUSK_SUN_TINT, warm),
	}
}

day_sky_at :: proc(fraction: f64, day_number: u64) -> Day_Sky {
	return Day_Sky {
		fraction = fraction,
		day_number = day_number,
		blend = blend_for_sun_height(sun_height(fraction)),
		colors = sky_colors(fraction),
	}
}

day_sky :: proc(tick, day_length_ticks: u64) -> Day_Sky {
	return day_sky_at(day_fraction(tick, day_length_ticks), tick / day_length_ticks)
}

// Unit vector towards the sun. East is +x: it rises at fraction 0, stands
// highest at 0.25 and sets at 0.5 towards -x, its path leaning
// SUN_PATH_TILT_DEGREES towards +z.
sun_direction :: proc(fraction: f64) -> [3]f32 {
	angle := fraction * math.TAU
	tilt := f64(SUN_PATH_TILT_DEGREES) * math.RAD_PER_DEG
	return {f32(math.cos(angle)), f32(math.sin(angle) * math.cos(tilt)), f32(math.sin(angle) * math.sin(tilt))}
}

moon_direction :: proc(fraction: f64) -> [3]f32 {
	return -sun_direction(fraction)
}

// A rotation that takes the up to +y, so the sky drawn round +y stands
// about the up (field_sky_camera, loop_field_session.odin).
up_to_sky_rotation :: proc(up: [3]f32) -> quaternion128 {
	return linalg.quaternion_between_two_vector3_f32(linalg.normalize(up), [3]f32{0, 1, 0})
}

// The sun as the field shader lights by it (0297): sun_direction in the
// sky's frame turned back by the inverse of the sky's rotation, so it
// stands where the sky dome shows it for a viewer with that up. Unit.
// Noon is overhead for every longitude at once, as daylight is.
field_sun_world_direction :: proc(fraction: f64, up: [3]f32) -> [3]f32 {
	return linalg.quaternion128_mul_vector3(linalg.quaternion_inverse(up_to_sky_rotation(up)), sun_direction(fraction))
}

// The axis the sun, the moon and the stars turn about, so that turning
// sun_direction(0) by fraction times a full turn gives sun_direction.
sun_path_axis :: proc() -> [3]f32 {
	tilt := f64(SUN_PATH_TILT_DEGREES) * math.RAD_PER_DEG
	return {0, f32(-math.sin(tilt)), f32(math.cos(tilt))}
}

// 0 at new moon, 0.5 at full moon.
moon_phase :: proc(day_number: u64) -> f32 {
	return f32(day_number % MOON_CYCLE_DAYS) / MOON_CYCLE_DAYS
}

// The sun's light on a face turned to it (0313), 0 to the strength: the
// low colour on the horizon to the high one by SUN_HIGH_HEIGHT, faded
// out as the sun sets, scaled by sun_strength_percent.
sun_light_color :: proc(fraction: f64, light: Sun_And_Torchlight_Config) -> [3]f32 {
	height := f64(sun_direction(fraction).y)
	high := field_color_float(light.sun_high_color)
	low := field_color_float(light.sun_low_color)
	color := high + (low - high) * f32(1 - smoothstep(0, SUN_HIGH_HEIGHT, height))
	return color / 255 * f32(smoothstep(SUN_LIGHT_SET_HEIGHT, SUN_LIGHT_RISEN_HEIGHT, height)) * f32(light.sun_strength_percent) / 100
}

// The sky's light on an upward face (0313): the dome's horizon and
// zenith mixed by SKY_LIGHT_ZENITH_SHARE, scaled by sky_light_percent.
sky_light_color :: proc(colors: Sky_Colors, light: Sun_And_Torchlight_Config) -> [3]f32 {
	horizon, zenith := color_to_vector3(colors.horizon), color_to_vector3(colors.zenith)
	return (horizon + (zenith - horizon) * SKY_LIGHT_ZENITH_SHARE) * f32(light.sky_light_percent) / 100
}

// The ground's bounce on a downward face (0313): the ground's colour lit
// by the sun at its height and by the sky, scaled by
// ground_bounce_percent.
ground_bounce_color :: proc(ground, sun, sky: [3]f32, sun_height: f32, light: Sun_And_Torchlight_Config) -> [3]f32 {
	return ground * (sun * max(sun_height, 0) + sky) * f32(light.ground_bounce_percent) / 100
}

// The haze's and the dome's glow towards the sun (0313), 0 to 1: the
// sun's low colour while the sun is near the horizon (twilight_share),
// scaled by sun_glow_percent.
haze_sun_glow_color :: proc(fraction: f64, light: Sun_And_Torchlight_Config, haze: Haze_Config) -> [3]f32 {
	return field_color_float(light.sun_low_color) / 255 * twilight_share(sun_height(fraction)) * f32(haze.sun_glow_percent) / 100
}
