package game

import "core:math"
import rl "vendor:raylib"

// The cosmetic day and night cycle, a function of the simulation tick
// alone. It sets the sky colours, the fog colour, the sun and moon
// directions and how much sky light reaches the shader, and in which
// colour (work item 0064). Block light is neither scaled nor tinted, so
// torches glow the same at night.

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
