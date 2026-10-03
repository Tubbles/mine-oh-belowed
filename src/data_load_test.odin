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

// The arrival's values (0200): the shipped ones pass, a path past the
// coarsest level's fog fails naming the path, a fall too short for its
// hit and flames fails, and no fall passes.
@(test)
test_arrival_values_are_bounded :: proc(t: ^testing.T) {
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, arrival_problem(config), "")
	high := config
	high.arrival_start_metres = 700
	testing.expect(t, strings.contains(arrival_problem(high), "makes a path of"), "700 m at 30 degrees names the path")
	short := config
	short.arrival_ticks = 200
	testing.expect(t, strings.contains(arrival_problem(short), "arrival_ticks"), "200 ticks cannot hold the hit and the flames")
	none := config
	none.arrival_ticks = 0
	testing.expect_value(t, arrival_problem(none), "")
}
