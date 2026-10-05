package game

import "core:strings"
import "core:testing"

@(test)
test_shipped_game_config_parses_and_validates :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.name, "Mine oh Belowed")
	testing.expect_value(t, config.tick_rate, 60)
	testing.expect_value(t, config.day_length_seconds, 1200)
	testing.expect_value(t, validate_game_config(config), "")
	testing.expect_value(t, validate_starting_items(config.starting_items, make_test_items()), "")
}

@(test)
test_game_config_rejects_bad_values :: proc(t: ^testing.T) {
	testing.expect(t, validate_game_config(Game_Config{name = "x", tick_rate = 60, day_length_seconds = 0}) != "")
	unknown := [?]Starting_Item{{item = "no_such_item", count = 1}}
	testing.expect(t, validate_starting_items(unknown[:], make_test_items()) != "")
	empty := [?]Starting_Item{{item = "torch", count = 0}}
	testing.expect(t, validate_starting_items(empty[:], make_test_items()) != "")
}

@(test)
test_the_field_view_distances_rise_within_the_limit :: proc(t: ^testing.T) {
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, config.field_view.level_distances_metres, [FIELD_LEVEL_COUNT]int{64, 160, 384, 1024})
	testing.expect_value(t, field_view_problem({{64, 160, 384, 1024}}), "")
	testing.expect(t, field_view_problem({}) != "", "a missing field_view is refused")
	testing.expect(t, field_view_problem({{64, 64, 384, 1024}}) != "")
	testing.expect(t, field_view_problem({{64, 160, 384, MAXIMUM_FIELD_VIEW_DISTANCE_METRES + 1}}) != "")
	// The gaps are the diagonals of a 32, 64 and 128 m node, rounded up.
	testing.expect_value(t, [3]int{field_level_gap_metres(1), field_level_gap_metres(2), field_level_gap_metres(3)}, [3]int{56, 111, 222})
	testing.expect_value(t, field_view_problem({{64, 120, 231, 453}}), "")
	refused := [?][FIELD_LEVEL_COUNT]int{{64, 119, 384, 1024}, {64, 160, 270, 1024}, {64, 160, 384, 605}}
	for distances in refused {
		testing.expectf(t, field_view_problem({distances}) != "", "%v lets a node border one two levels coarser", distances)
	}
}

// The Android asset copy (work item 0114): the list build.sh writes and
// the stamp that skips the copy on a later start of the same build.
@(test)
test_android_asset_paths_skip_blank_lines :: proc(t: ^testing.T) {
	paths := android_asset_paths("data/game.sjson\n\ndata/strings/en.sjson\r\n  \n")
	testing.expect_value(t, len(paths), 2)
	testing.expect_value(t, paths[0], "data/game.sjson")
	testing.expect_value(t, paths[1], "data/strings/en.sjson")
	testing.expect_value(t, len(android_asset_paths("")), 0)
}

@(test)
test_android_assets_current_compares_the_build_stamp :: proc(t: ^testing.T) {
	testing.expect(t, android_assets_current("abc1234 2026-09-29T12:00Z", "abc1234 2026-09-29T12:00Z"))
	testing.expect(t, android_assets_current("abc1234 2026-09-29T12:00Z\n", "abc1234 2026-09-29T12:00Z"))
	testing.expect(t, !android_assets_current("abc1234 2026-09-29T12:00Z", "def5678 2026-09-29T13:00Z"))
	testing.expect(t, !android_assets_current("", "abc1234 2026-09-29T12:00Z"))
}

// The arrival's values (0200, 0269): the shipped ones pass; a start too
// far from the crater, a start at the atmosphere's top, a hit that
// glows, an atmosphere hazing the ground's sky, real seconds longer than
// the curve and a fall too short for its hit fail naming their key; no
// fall passes.
@(test)
test_arrival_values_are_bounded :: proc(t: ^testing.T) {
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, arrival_problem(config), "")
	far := config
	far.arrival_start_metres = 2000
	testing.expect(t, strings.contains(arrival_problem(far), "starts"), "a start 2000 m up names the start's distance")
	low := config
	low.arrival_start_metres = config.atmosphere.top_metres
	testing.expect(t, strings.contains(arrival_problem(low), "atmosphere.top_metres"), "a start at the top names the top")
	glowing := config
	glowing.arrival_heat_threshold_percent = 0
	testing.expect(t, strings.contains(arrival_problem(glowing), "heat at the hit"), "threshold 0 glows at the hit")
	thick := config
	thick.atmosphere.scale_height_metres = 400
	testing.expect(t, strings.contains(arrival_problem(thick), "two scale heights"), "a scale height of 400 m hazes the ground's sky")
	long := config
	long.arrival_real_seconds = 59
	testing.expect(t, strings.contains(arrival_problem(long), "natural seconds"), "real seconds longer than the curve")
	brief := config
	brief.arrival_ticks = 360
	testing.expect(t, strings.contains(arrival_problem(brief), "descent"), "real seconds longer than a 300 tick descent")
	short := config
	short.arrival_ticks = 60
	testing.expect(t, strings.contains(arrival_problem(short), "arrival_ticks"), "60 ticks cannot hold the hit")
	none := config
	none.arrival_ticks = 0
	testing.expect_value(t, arrival_problem(none), "")
}

// The direct placement limit (0215): the shipped one loads, each side
// outside 1 to 16 is named.
@(test)
test_direct_placement_limit_is_range_checked :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.direct_placement_limit, Placement_Limit_Config{width = 2, depth = 2, height = 3})
	testing.expect_value(t, direct_placement_limit_problem(config.direct_placement_limit), "")
	narrow := config.direct_placement_limit
	narrow.width = 0
	testing.expect(t, strings.has_prefix(direct_placement_limit_problem(narrow), "direct_placement_limit.width "))
	tall := config.direct_placement_limit
	tall.height = MAXIMUM_DIRECT_PLACEMENT_LIMIT_CELLS + 1
	testing.expect(t, strings.has_prefix(direct_placement_limit_problem(tall), "direct_placement_limit.height "))
	config.direct_placement_limit = tall
	testing.expect(t, strings.has_prefix(validate_game_config(config), "direct_placement_limit.height "))
}

// The pod's airlock (0222, 0231): the shipped reach loads, a reach
// outside its bound is named.
@(test)
test_the_pod_airlock_config_is_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.pod_airlock, Pod_Airlock_Config{reach_millimetres = 150})
	testing.expect_value(t, pod_airlock_problem(config.pod_airlock), "")
	cases := [?]struct {
		airlock: Pod_Airlock_Config,
		key:     string,
	} {
		{{40}, "pod_airlock.reach_millimetres "},
		{{301}, "pod_airlock.reach_millimetres "},
	}
	for entry in cases {
		problem := pod_airlock_problem(entry.airlock)
		testing.expectf(t, strings.has_prefix(problem, entry.key), "%v: %q", entry.airlock, problem)
	}
}

// Work item 0228: the state copy first, the edits directory's second,
// none while the overlay is off.
@(test)
test_data_edits_directories_put_the_state_copy_first :: proc(t: ^testing.T) {
	testing.expect_value(t, data_edits_directories("/s", "/r", false, false), [2]string{"/s", "/r"})
	testing.expect_value(t, data_edits_directories("/s", "/r", false, true), [2]string{"/s", ""})
	testing.expect_value(t, data_edits_directories("/s", "/r", true, false), [2]string{"", ""})
	testing.expect_value(t, data_edits_directories("", "/r", false, false), [2]string{"", "/r"})
}

@(test)
test_reachable_data_edits_refusal_cases :: proc(t: ^testing.T) {
	testing.expect_value(t, reachable_data_edits_refusal("", true, true), Reachable_Data_Edits_Refusal.Not_Set)
	testing.expect_value(t, reachable_data_edits_refusal("Download", true, true), Reachable_Data_Edits_Refusal.Not_Absolute)
	testing.expect_value(t, reachable_data_edits_refusal("~/Download", true, true), Reachable_Data_Edits_Refusal.Not_Absolute)
	testing.expect_value(t, reachable_data_edits_refusal("/storage/emulated/0/Download", false, true), Reachable_Data_Edits_Refusal.No_Access)
	testing.expect_value(t, reachable_data_edits_refusal("/storage/emulated/0/Download", true, false), Reachable_Data_Edits_Refusal.Not_A_Directory)
	testing.expect_value(t, reachable_data_edits_refusal("/storage/emulated/0/Download", true, true), Reachable_Data_Edits_Refusal.None)
}
