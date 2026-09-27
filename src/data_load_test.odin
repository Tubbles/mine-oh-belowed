package game

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
