package game

import "core:testing"

// The default day of data/game.sjson: 1200 seconds at 60 ticks.
WEATHER_TEST_DAY_LENGTH :: 72_000

@(rodata)
weather_test_seeds := [?]u64{1, 42, 20260928}

@(test)
test_weather_is_the_same_for_the_same_seed_and_tick :: proc(t: ^testing.T) {
	for tick := u64(0); tick < 3 * WEATHER_TEST_DAY_LENGTH; tick += 997 {
		testing.expect_value(t, weather_at(42, tick, WEATHER_TEST_DAY_LENGTH), weather_at(42, tick, WEATHER_TEST_DAY_LENGTH))
	}
}

// Two seeds give different kinds in some hour of the first days.
@(test)
test_weather_differs_between_seeds :: proc(t: ^testing.T) {
	hour_length := weather_hour_length(WEATHER_TEST_DAY_LENGTH)
	differing := 0
	for hour in u64(0) ..< 3 * WEATHER_HOURS_PER_DAY {
		middle := hour * hour_length + hour_length / 2
		if weather_at(1, middle, WEATHER_TEST_DAY_LENGTH).kind != weather_at(42, middle, WEATHER_TEST_DAY_LENGTH).kind {
			differing += 1
		}
	}
	testing.expect(t, differing > 0)
}

// Over the first day every kind occurs on each test seed.
@(test)
test_weather_every_kind_occurs_in_a_day :: proc(t: ^testing.T) {
	hour_length := weather_hour_length(WEATHER_TEST_DAY_LENGTH)
	for seed in weather_test_seeds {
		seen: [Weather_Kind]bool
		for hour in u64(0) ..< WEATHER_HOURS_PER_DAY {
			seen[weather_at(seed, hour * hour_length + hour_length / 2, WEATHER_TEST_DAY_LENGTH).kind] = true
		}
		for kind in Weather_Kind {
			testing.expectf(t, seen[kind], "seed %d never has %v", seed, kind)
		}
	}
}

// No jumps between ticks: at most the steepest ramp's step.
@(test)
test_weather_intensity_changes_gradually :: proc(t: ^testing.T) {
	hour_length := weather_hour_length(WEATHER_TEST_DAY_LENGTH)
	largest_step := 1 / (WEATHER_RAMP_SHARE * f32(hour_length)) + 0.0001
	previous := weather_at(42, 0, WEATHER_TEST_DAY_LENGTH)
	testing.expect_value(t, previous.intensity, 0)
	for tick in u64(1) ..< WEATHER_TEST_DAY_LENGTH {
		current := weather_at(42, tick, WEATHER_TEST_DAY_LENGTH)
		testing.expectf(t, abs(current.intensity - previous.intensity) <= largest_step, "tick %d: %v to %v", tick, previous, current)
		testing.expect(t, current.intensity >= 0 && current.intensity <= 1)
		previous = current
	}
}

@(test)
test_weather_kind_rolls_follow_the_weights :: proc(t: ^testing.T) {
	testing.expect_value(t, weather_kind_for_roll(0), Weather_Kind.Clear)
	testing.expect_value(t, weather_kind_for_roll(49), Weather_Kind.Clear)
	testing.expect_value(t, weather_kind_for_roll(50), Weather_Kind.Overcast)
	testing.expect_value(t, weather_kind_for_roll(75), Weather_Kind.Rain)
	testing.expect_value(t, weather_kind_for_roll(89), Weather_Kind.Rain)
	testing.expect_value(t, weather_kind_for_roll(90), Weather_Kind.Fog)
	testing.expect_value(t, weather_kind_for_roll(99), Weather_Kind.Fog)
	testing.expect_value(t, weather_ramp(0), 0)
	testing.expect_value(t, weather_ramp(0.5), 1)
	testing.expect_value(t, weather_ramp(1), 0)
}

// Rain over a column colder than the cold barrens' bound falls as snow.
@(test)
test_weather_cold_column_snows :: proc(t: ^testing.T) {
	rain := Weather{kind = .Rain, intensity = 0.8}
	testing.expect_value(t, weather_precipitation(rain, -0.6), Precipitation.Snow)
	testing.expect_value(t, weather_precipitation(rain, 0.2), Precipitation.Rain)
	testing.expect_value(t, weather_precipitation(Weather{kind = .Fog, intensity = 1}, -0.6), Precipitation.None)
	testing.expect_value(t, weather_precipitation(Weather{kind = .Rain, intensity = 0}, 0.2), Precipitation.None)
}

@(test)
test_weather_override_forces_full_intensity :: proc(t: ^testing.T) {
	scheduled := Weather{kind = .Clear, intensity = 0.3}
	testing.expect_value(t, forced_weather(scheduled, nil), scheduled)
	testing.expect_value(t, forced_weather(scheduled, Weather_Kind.Fog), Weather{kind = .Fog, intensity = 1})
}

// The weather command sets and clears the session's override.
@(test)
test_weather_command_forces_a_kind :: proc(t: ^testing.T) {
	override: Maybe(Weather_Kind)
	command_context := Command_Context{weather_override = &override}
	testing.expect(t, command_weather(command_context, {"rain"}).ok)
	testing.expect_value(t, override, Weather_Kind.Rain)
	testing.expect(t, !command_weather(command_context, {"hail"}).ok)
	testing.expect_value(t, override, Weather_Kind.Rain)
	testing.expect(t, command_weather(command_context, {"auto"}).ok)
	testing.expect_value(t, override, nil)
	testing.expect(t, !command_weather(Command_Context{}, {"fog"}).ok)
}
