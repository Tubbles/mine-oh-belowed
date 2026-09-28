package game

import "core:flags"
import "core:strings"
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
	empty, empty_error := parse_command_line({})
	testing.expect_value(t, empty_error, nil)
	default_seed, default_ok := command_line_seed(empty)
	testing.expect(t, default_ok)
	testing.expect_value(t, default_seed, DEFAULT_WORLD_SEED)
	command_line, error := parse_command_line({"--seed=7", "--debug-terrain"})
	testing.expect_value(t, error, nil)
	seed, ok := command_line_seed(command_line)
	testing.expect(t, ok)
	testing.expect_value(t, seed, 7)
	testing.expect(t, command_line.debug_terrain)
	testing.expect_value(t, command_line_value_problem(command_line), "")
	bogus, bogus_error := parse_command_line({"--seed=bogus"})
	testing.expect_value(t, bogus_error, nil)
	testing.expect(t, strings.has_prefix(command_line_value_problem(bogus), "invalid seed \"bogus\""))
}

@(test)
test_command_line_rejects_unknown_values :: proc(t: ^testing.T) {
	_, error := parse_command_line({"--bogus"})
	testing.expect(t, error != nil)
	_, is_help := error.(flags.Help_Request)
	testing.expect(t, !is_help)
	input, input_error := parse_command_line({"--input=vulkan"})
	testing.expect_value(t, input_error, nil)
	testing.expect(t, strings.has_prefix(command_line_value_problem(input), "unknown input backend"))
	subcommand, subcommand_error := parse_command_line({"play"})
	testing.expect_value(t, subcommand_error, nil)
	testing.expect(t, strings.has_prefix(command_line_value_problem(subcommand), "unknown command"))
	_, help_error := parse_command_line({"--help"})
	_, is_help = help_error.(flags.Help_Request)
	testing.expect(t, is_help)
}

@(test)
test_command_line_benchmark_size_and_conflicts :: proc(t: ^testing.T) {
	command_line, error := parse_command_line({"--benchmark=4"})
	testing.expect_value(t, error, nil)
	testing.expect_value(t, command_line.benchmark, 4)
	testing.expect_value(t, command_line_value_problem(command_line), "")
	testing.expect_value(t, command_line_conflict(command_line), "")
	testing.expect(t, !command_line_starts_world(command_line))
	for size in ([?]string{"--benchmark=-1", "--benchmark=65"}) {
		invalid, _ := parse_command_line({size})
		testing.expectf(t, strings.has_prefix(command_line_value_problem(invalid), "invalid --benchmark"), "%s accepted", size)
	}
	for other in ([?]string{"--load=a", "--seed=7", "--name=a", "--chapter=2", "--debug-terrain"}) {
		combined, _ := parse_command_line({"--benchmark=1", other})
		testing.expectf(t, strings.has_prefix(command_line_conflict(combined), "--benchmark and"), "--benchmark with %s accepted", other)
	}
}

@(test)
test_command_line_repeated_set :: proc(t: ^testing.T) {
	command_line, error := parse_command_line({"config", "--set=settings.ui_scale=1.25", "--set=paths.saves=/tmp/saves"})
	defer delete(command_line.set_assignments)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, command_line.subcommand, CONFIG_SUBCOMMAND)
	testing.expect_value(t, len(command_line.set_assignments), 2)
	if len(command_line.set_assignments) == 2 {
		testing.expect_value(t, command_line.set_assignments[0], "settings.ui_scale=1.25")
		testing.expect_value(t, command_line.set_assignments[1], "paths.saves=/tmp/saves")
	}
}

@(test)
test_command_line_usage_lists_every_flag :: proc(t: ^testing.T) {
	builder := strings.builder_make(context.temp_allocator)
	write_command_line_usage(strings.to_writer(&builder))
	usage := strings.to_string(builder)
	testing.expect(t, strings.contains(usage, PROGRAM_NAME))
	for flag in ([?]string{"subcommand", "--version", "--set", "--input", "--seed", "--load", "--name", "--debug-terrain", "--unlock-all", "--benchmark"}) {
		testing.expectf(t, strings.contains(usage, flag), "usage lacks %s:\n%s", flag, usage)
	}
}
