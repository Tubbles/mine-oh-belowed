package game

import "core:math"
import rl "vendor:raylib"

// The cosmetic day and night cycle, a function of the simulation tick
// alone. It changes only the sky colour, the fog colour and how much sky
// light reaches the shader. Block light is not scaled, so torches glow the
// same at night.

DAY_SKY_COLOR :: rl.Color{150, 190, 230, 255}
NIGHT_SKY_COLOR :: rl.Color{12, 16, 32, 255}
// Share of full sky light left at midnight, so moonlit ground stays visible.
NIGHT_DAY_FACTOR :: 0.2
// The world starts a little after sunrise.
DAY_START_FRACTION :: 0.05
// Sun heights, as the sine of the day fraction, between which dawn and
// dusk blend night into day.
TWILIGHT_START :: -0.2
TWILIGHT_END :: 0.25

// 0 at night, 1 by day, smooth in between. The sun rises at fraction 0,
// peaks at 0.25, sets at 0.5 and is lowest at 0.75.
daylight_blend :: proc(tick, day_length_ticks: u64) -> f32 {
	fraction := f64(tick % day_length_ticks) / f64(day_length_ticks) + DAY_START_FRACTION
	sun := math.sin(fraction * math.TAU)
	return f32(smoothstep(TWILIGHT_START, TWILIGHT_END, sun))
}

// The factor the shader multiplies sky light by, NIGHT_DAY_FACTOR to 1.
day_factor :: proc(blend: f32) -> f32 {
	return NIGHT_DAY_FACTOR + (1 - NIGHT_DAY_FACTOR) * blend
}

sky_color :: proc(blend: f32) -> rl.Color {
	night := [4]f32{f32(NIGHT_SKY_COLOR.r), f32(NIGHT_SKY_COLOR.g), f32(NIGHT_SKY_COLOR.b), 255}
	day := [4]f32{f32(DAY_SKY_COLOR.r), f32(DAY_SKY_COLOR.g), f32(DAY_SKY_COLOR.b), 255}
	mixed := night + (day - night) * blend
	return rl.Color{u8(math.round(mixed.r)), u8(math.round(mixed.g)), u8(math.round(mixed.b)), 255}
}
