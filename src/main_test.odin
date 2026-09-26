package game

import "core:testing"

@(test)
test_parse_seed :: proc(t: ^testing.T) {
	seed, ok := parse_seed("12345")
	testing.expect(t, ok)
	testing.expect_value(t, seed, 12345)
	seed, ok = parse_seed("18446744073709551615")
	testing.expect(t, ok)
	testing.expect_value(t, seed, max(u64))
	for invalid in ([?]string{"", "bogus", "-1", "+1", "1_000", "0x10", "18446744073709551616", "99999999999999999999999"}) {
		_, ok = parse_seed(invalid)
		testing.expectf(t, !ok, "seed %q accepted", invalid)
	}
}

@(test)
test_command_line_seed_and_debug_terrain :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_command_line({}).seed, DEFAULT_WORLD_SEED)
	command_line := parse_command_line({"--seed=7", "--debug-terrain"})
	testing.expect_value(t, command_line.seed, 7)
	testing.expect(t, command_line.debug_terrain)
	testing.expect_value(t, parse_command_line({"--seed=bogus"}).invalid_seed_value, "bogus")
}
