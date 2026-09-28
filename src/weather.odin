package game

// The weather (work item 0063): cosmetic, a pure function of the world
// seed and the tick, so nothing is saved and the same world always has
// the same weather at the same tick. Each game hour (a twenty fourth of
// the day) gets a kind and a peak intensity from a hash of the seed and
// the hour index; the intensity ramps up over the first and down over
// the last WEATHER_RAMP_SHARE of the hour, so changes are gradual. Snow
// is not a kind: rain over a cold column falls as snow
// (weather_precipitation). The renderer reads it (render_weather.odin);
// the simulation never does.

WEATHER_HOURS_PER_DAY :: 24
WEATHER_SEED_SALT :: 0x77ea_7e2a_5c4e_d011
// The share of the hour over which the intensity ramps up at its start
// and down at its end.
WEATHER_RAMP_SHARE :: 0.1
// An hour's peak intensity lies between this and 1.
WEATHER_MINIMUM_PEAK :: 0.5
// Rain over a column colder than this falls as snow: the upper
// temperature bound of the cold barrens (data/biomes.sjson).
SNOW_TEMPERATURE :: -0.45

Weather_Kind :: enum u8 {
	Clear,
	Overcast,
	Rain,
	Fog,
}

// intensity is 0 to 1.
Weather :: struct {
	kind:      Weather_Kind,
	intensity: f32,
}

Precipitation :: enum u8 {
	None,
	Rain,
	Snow,
}

// Percent of the hours of each kind.
@(rodata)
weather_kind_weights := [Weather_Kind]int {
	.Clear    = 50,
	.Overcast = 25,
	.Rain     = 15,
	.Fog      = 10,
}

@(rodata)
weather_kind_words := [Weather_Kind]string {
	.Clear    = "clear",
	.Overcast = "overcast",
	.Rain     = "rain",
	.Fog      = "fog",
}

weather_hour_length :: proc(day_length_ticks: u64) -> u64 {
	return max(day_length_ticks / WEATHER_HOURS_PER_DAY, 1)
}

weather_hour_hash :: proc(seed, hour: u64) -> u64 {
	return hash_u64(seed ~ WEATHER_SEED_SALT ~ (hour * 0x9e37_79b9_7f4a_7c15))
}

// roll is 0 to 99.
weather_kind_for_roll :: proc(roll: int) -> Weather_Kind {
	remaining := roll
	for weight, kind in weather_kind_weights {
		if remaining < weight {
			return kind
		}
		remaining -= weight
	}
	return .Clear
}

weather_peak_for_hash :: proc(hash: u64) -> f32 {
	share := f32((hash >> 32) % 1024) / 1023
	return WEATHER_MINIMUM_PEAK + (1 - WEATHER_MINIMUM_PEAK) * share
}

// 0 at the hour's edges, 1 from WEATHER_RAMP_SHARE inside them.
weather_ramp :: proc(share_of_hour: f32) -> f32 {
	edge := min(share_of_hour, 1 - share_of_hour)
	return clamp(edge / WEATHER_RAMP_SHARE, 0, 1)
}

weather_at :: proc(seed, tick, day_length_ticks: u64) -> Weather {
	hour_length := weather_hour_length(day_length_ticks)
	hash := weather_hour_hash(seed, tick / hour_length)
	share := f32(tick % hour_length) / f32(hour_length)
	return Weather{kind = weather_kind_for_roll(int(hash % 100)), intensity = weather_peak_for_hash(hash) * weather_ramp(share)}
}

// A forced kind (the weather command) is at full intensity.
forced_weather :: proc(scheduled: Weather, override: Maybe(Weather_Kind)) -> Weather {
	if kind, forced := override.?; forced {
		return Weather{kind = kind, intensity = 1}
	}
	return scheduled
}

// temperature is terrain_temperature at the camera's column.
weather_precipitation :: proc(weather: Weather, temperature: f32) -> Precipitation {
	if weather.kind != .Rain || weather.intensity <= 0 {
		return .None
	}
	return temperature < SNOW_TEMPERATURE ? .Snow : .Rain
}
