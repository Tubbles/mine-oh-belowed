package game

import "core:os"
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

// The asset copy on the phone makes its directories one mkdir at a time
// (make_directories_below), never through os.make_directory_all.
@(test)
test_make_directories_below_makes_each_level_and_tolerates_existing :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-directories-test-*", context.temp_allocator)
	testing.expect(t, error == nil)
	defer os.remove_all(base)
	testing.expect(t, make_directories_below(base, "data/strings") == nil)
	nested, _ := os.join_path({base, "data", "strings"}, context.temp_allocator)
	testing.expect(t, os.is_dir(nested))
	testing.expect(t, make_directories_below(base, "data/strings") == nil)
	testing.expect(t, make_directories_below(base, "") == nil)
}
