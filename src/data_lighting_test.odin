package game

import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_the_lighting_file_parses_and_names_the_torch_and_the_lamp :: proc(t: ^testing.T) {
	lighting := test_lighting_file()
	torch, torch_found := find_lighting_emitter(lighting, "torch")
	lamp, lamp_found := find_lighting_emitter(lighting, "lamp")
	testing.expect(t, torch_found && lamp_found && torch < lamp)
}

@(test)
test_the_lighting_file_refuses_what_would_break_the_fill :: proc(t: ^testing.T) {
	valid := "falloff = [24, 18, 12, 6]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = [{id = \"torch\", level = 192}, {id = \"lamp\", level = 255}]\n"
	_, problem := parse_lighting_file(transmute([]byte)valid, "lighting.sjson", context.temp_allocator)
	testing.expect_value(t, problem, "")
	cases := [?]struct {
		text:     string,
		expected: string,
	} {
		{"falloff = [6, 12, 18, 24]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = []\n", "falloff[1] (12) is above falloff[0]"},
		{"falloff = [24, 18, 12]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = []\n", "not a power of two"},
		{"falloff = [24, 0]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = []\n", "falloff[1] is 0"},
		{"falloff = [24]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\n", "missing key emitters"},
		{"falloff = [24]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = []\nglow = 1\n", "unknown key glow"},
		{"falloff = [24]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = [{id = \"torch\"}]\n", "emitters[0] is missing level"},
		{"falloff = [24]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = [{id = \"torch\", level = 300}]\n", "level 300"},
		{"falloff = [24]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = [{id = \"torch\", level = 9}, {id = \"torch\", level = 9}]\n", "listed twice"},
		{"falloff = [24]\ndark_level = 24\nsteps_per_tick = 0\nchunk_seeds_per_tick = 2\nemitters = []\n", "steps_per_tick 0"},
		{"falloff = [24]\ndark_level = 24\nsteps_per_tick = 100\nchunk_seeds_per_tick = 2\nemitters = [{id = \"torch\", level = 9}]\n", "emitters has no lamp"},
	}
	for entry in cases {
		_, problem = parse_lighting_file(transmute([]byte)entry.text, "lighting.sjson", context.temp_allocator)
		testing.expectf(t, strings.contains(problem, entry.expected), "%q: %q", entry.expected, problem)
	}
}

// A step loses the falloff of the level it leaves times the spacing,
// rounded: the data's multiples of 6 divide evenly at every spacing.
@(test)
test_the_falloff_scales_with_the_spacing :: proc(t: ^testing.T) {
	lighting := test_lighting_file()
	for spacing in ([3]int{333, 500, 1000}) {
		tuning := make_field_light_tuning(lighting, spacing)
		testing.expect_value(t, int(tuning.spread[255]), 255 - field_light_step_loss(6, spacing))
		testing.expect_value(t, int(tuning.spread[40]), 40 - field_light_step_loss(24, spacing))
		testing.expect_value(t, tuning.spread[1], 0)
		for level in 1 ..< FIELD_LIGHT_LEVELS {
			testing.expect(t, tuning.spread[level] >= tuning.spread[level - 1] && int(tuning.spread[level]) < level)
		}
	}
	testing.expect_value(t, field_light_step_loss(24, 333), 8)
	testing.expect_value(t, field_light_step_loss(1, 333), 1)
}

// A new world started from the title read the emitters frames after
// the tables loaded and crashed (2026-10-03): the file's lists must live
// in the caller's allocator, never in the frame's temporary memory.
@(test)
test_the_lighting_file_lives_in_the_callers_allocator :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.temp_allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	lighting, problem := parse_lighting_file(#load("../data/lighting.sjson"), LIGHTING_FILE_NAME, mem.tracking_allocator(&tracking))
	testing.expect_value(t, problem, "")
	testing.expect(t, len(lighting.emitters) > 0 && len(lighting.falloff) > 0)
	_, emitters_tracked := tracking.allocation_map[raw_data(lighting.emitters)]
	_, falloff_tracked := tracking.allocation_map[raw_data(lighting.falloff)]
	_, id_tracked := tracking.allocation_map[raw_data(lighting.emitters[0].id)]
	testing.expect(t, emitters_tracked, "the emitters are not in the caller's allocator")
	testing.expect(t, falloff_tracked, "the falloff is not in the caller's allocator")
	testing.expect(t, id_tracked, "an emitter's id is not in the caller's allocator")
}
