package game

import "core:time"

// Wall time per simulation system (work item 0050): simulation_tick and
// tick_entities take an optional profile and add the time of each step to
// its section. Without a profile (the game) no clock is read. The factory
// benchmark (benchmark_factory.odin) keeps one over its measured ticks.

Tick_Section :: enum u8 {
	Players,
	Unlocks,
	Belts,
	Loose_Items,
	Power,
	Drills,
	Inserters,
	Furnaces,
	Assemblers,
	Labs,
	Core_Sample_Drills,
	Launch_Pads,
	Fluids,
	Lamps,
	Outcrops_And_Crates,
	Venture,
	Research,
	Statistics,
	Quests,
	// tick_world: block changes, water and light queues, leaf decay.
	World,
}

// seconds per section summed over ticks; ticks counts the ticks
// simulation_tick ran with the profile.
Tick_Profile :: struct {
	seconds: [Tick_Section]f64,
	ticks:   int,
}

// The clock when profiling, the zero tick otherwise.
profile_now :: proc(profile: ^Tick_Profile) -> time.Tick {
	if profile == nil {
		return {}
	}
	return time.tick_now()
}

// Adds the time since start to the section and returns the clock, so
// the next section starts where this one ended.
profile_section :: proc(profile: ^Tick_Profile, section: Tick_Section, start: time.Tick) -> time.Tick {
	if profile == nil {
		return {}
	}
	now := time.tick_now()
	profile.seconds[section] += time.duration_seconds(time.tick_diff(start, now))
	return now
}

profile_total_seconds :: proc(profile: Tick_Profile) -> f64 {
	total: f64
	for seconds in profile.seconds {
		total += seconds
	}
	return total
}
