package game

import "core:time"

// Wall time per simulation system (work item 0050): simulation_tick and
// tick_entities take an optional profile and add the time of each step to
// its section. Without a profile no clock is read. The game profiles every
// tick into its frame profile (0342, render_frame_profile.odin); the
// factory benchmark (benchmark_factory.odin) keeps its own over its
// measured ticks, and the server and the tick command pass none.

Tick_Section :: enum u8 {
	// update_simulated_chunks: the simulated chunk set.
	Chunk_Set,
	// The tick hook's socket lines and apply_player_commands.
	Commands,
	// Every field player's move, look, dig and placement queueing.
	Field_Players,
	// The field's edits, placements, water edits and pumps.
	Field_Edits,
	// The water step (step_field_water_keeping_events).
	Field_Water,
	// The field light within its budget.
	Field_Light,
	// The airlocks, the refusals told, the arrival's hit and landing.
	Field_Rest,
	// The block world's players.
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
	// The lockstep's state hash on a due tick (run_session_tick).
	State_Hash,
}

// seconds per section summed over ticks; ticks counts the ticks
// simulation_tick ran with the profile. longest_seconds is the longest
// whole tick run_session_tick timed, state_hashes the ticks it hashed.
Tick_Profile :: struct {
	seconds:         [Tick_Section]f64,
	ticks:           int,
	longest_seconds: f64,
	state_hashes:    int,
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

// The whole tick since start, kept when it is the longest yet.
note_longest_tick :: proc(profile: ^Tick_Profile, start: time.Tick) {
	if profile == nil {
		return
	}
	profile.longest_seconds = max(profile.longest_seconds, time.duration_seconds(time.tick_since(start)))
}

profile_total_seconds :: proc(profile: Tick_Profile) -> f64 {
	total: f64
	for seconds in profile.seconds {
		total += seconds
	}
	return total
}
