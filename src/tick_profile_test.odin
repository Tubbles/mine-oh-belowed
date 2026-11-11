package game

import "core:testing"
import "core:time"

// Work item 0050: the profile gets time only when one is given.

@(test)
test_profile_sections_add_only_with_a_profile :: proc(t: ^testing.T) {
	testing.expect_value(t, profile_now(nil), time.Tick{})
	testing.expect_value(t, profile_section(nil, .Belts, time.tick_now()), time.Tick{})
	profile: Tick_Profile
	start := profile_now(&profile)
	time.sleep(time.Millisecond)
	next := profile_section(&profile, .Belts, start)
	testing.expect(t, profile.seconds[.Belts] >= 0.001)
	testing.expect(t, time.tick_diff(start, next) > 0)
	for seconds, section in profile.seconds {
		if section != .Belts {
			testing.expect_value(t, seconds, 0)
		}
	}
	testing.expect_value(t, profile_total_seconds(profile), profile.seconds[.Belts])
}

@(test)
test_simulation_tick_fills_a_given_profile :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content := make_save_test_content()
	simulation := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&simulation)
	simulation_tick(&simulation, content, {})
	profile: Tick_Profile
	simulation_tick(&simulation, content, {}, &profile)
	simulation_tick(&simulation, content, {}, &profile)
	testing.expect_value(t, profile.ticks, 2)
	testing.expect(t, profile_total_seconds(profile) > 0)
	testing.expect_value(t, simulation.tick, 3)
}

// Work item 0342: a field session's tick fills the field's sections; the
// state hash is run_session_tick's, so simulation_tick leaves it 0.
@(test) // slow
test_a_field_tick_fills_the_field_sections :: proc(t: ^testing.T) {
	game := make_field_test_game_content()
	session := start_field_test_session(test_field_game_config(), game)
	defer end_session(session)
	state := &session.simulation
	content := field_test_content(session, game)
	profile: Tick_Profile
	for _ in 0 ..< 2 {
		if !simulated_chunks_ready(state) {
			stage_cached_field_set(state)
		}
		inputs := [1]Input_Frame{}
		simulation_tick(state, content, inputs[:], &profile)
	}
	testing.expect_value(t, profile.ticks, 2)
	field: f64
	for section in ([?]Tick_Section{.Field_Players, .Field_Edits, .Field_Water, .Field_Light, .Field_Rest}) {
		field += profile.seconds[section]
	}
	testing.expect(t, field > 0)
	testing.expect_value(t, profile.seconds[.State_Hash], 0)
}
