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
	testing.expect_value(t, empty.planet_preview_daylight, 100)
	night, night_error := parse_command_line({"--planet-preview-daylight=0"})
	testing.expect_value(t, night_error, nil)
	testing.expect_value(t, night.planet_preview_daylight, 0)
	testing.expect_value(t, empty.planet_preview_pitch, PLANET_PREVIEW_PIT_PITCH_DEGREES)
	level, level_error := parse_command_line({"--planet-preview-pitch=-10"})
	testing.expect_value(t, level_error, nil)
	testing.expect_value(t, level.planet_preview_pitch, -10)
	testing.expect_value(t, empty.planet_preview_yaw, 0)
	turned, turned_error := parse_command_line({"--planet-preview-yaw=-40"})
	testing.expect_value(t, turned_error, nil)
	testing.expect_value(t, turned.planet_preview_yaw, -40)
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
	command_line, error := parse_command_line({"--benchmark=1"})
	testing.expect_value(t, error, nil)
	testing.expect_value(t, command_line.benchmark, 1)
	testing.expect_value(t, command_line_value_problem(command_line), "")
	testing.expect_value(t, command_line_conflict(command_line), "")
	testing.expect(t, !command_line_starts_world(command_line))
	for size in ([?]string{"--benchmark=-1", "--benchmark=17"}) {
		invalid, _ := parse_command_line({size})
		testing.expectf(t, strings.has_prefix(command_line_value_problem(invalid), "invalid --benchmark"), "%s accepted", size)
	}
	// The field world runs size 1 until M14 (0179).
	larger, _ := parse_command_line({"--benchmark=4"})
	testing.expect(t, strings.contains(command_line_value_problem(larger), "M14"), command_line_value_problem(larger))
	for other in ([?]string{"--load=a", "--seed=7", "--name=a", "--chapter=2", "--debug-terrain"}) {
		combined, _ := parse_command_line({"--benchmark=1", other})
		testing.expectf(t, strings.has_prefix(command_line_conflict(combined), "--benchmark and"), "--benchmark with %s accepted", other)
	}
}

@(test)
test_command_line_server_join_and_port :: proc(t: ^testing.T) {
	server, error := parse_command_line({"--server", "--port=4000", "--load=a"})
	testing.expect_value(t, error, nil)
	testing.expect(t, server.server)
	testing.expect_value(t, server.port, 4000)
	testing.expect_value(t, command_line_value_problem(server), "")
	testing.expect_value(t, command_line_conflict(server), "")
	joining, _ := parse_command_line({"--join=192.168.1.20:4000"})
	testing.expect_value(t, joining.join_address, "192.168.1.20:4000")
	testing.expect_value(t, command_line_conflict(joining), "")
	for port in ([?]string{"--port=-1", "--port=65536"}) {
		invalid, _ := parse_command_line({"--server", port})
		testing.expectf(t, strings.has_prefix(command_line_value_problem(invalid), "invalid --port"), "%s accepted", port)
	}
	conflicts := [?][2]string{{"--server", "--join=a"}, {"--join=a", "--seed=7"}, {"--port=4000", "--load=a"}, {"--server", "--debug-terrain"}, {"--server", "--chapter=2"}, {"--server", "--give=iron_plate:1"}}
	for pair in conflicts {
		combined, _ := parse_command_line({pair[0], pair[1]})
		defer delete(combined.give_arguments)
		testing.expectf(t, command_line_conflict(combined) != "", "%s with %s accepted", pair[0], pair[1])
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
	for flag in ([?]string{"subcommand", "--version", "--set", "--input", "--seed", "--load", "--name", "--debug-terrain", "--unlock-all", "--benchmark", "--model-check", "--model-preview", "--model-preview-directory", "--tech-demo"}) {
		testing.expectf(t, strings.contains(usage, flag), "usage lacks %s:\n%s", flag, usage)
	}
}

// --tech-demo (0291): bare it opens the menu, with words it starts the
// world; each word is checked, the radius against the data's presets.
@(test)
test_command_line_tech_demo :: proc(t: ^testing.T) {
	menu, error := parse_command_line({"--tech-demo"})
	testing.expect_value(t, error, nil)
	testing.expect_value(t, menu.tech_demo, TECH_DEMO_MENU_WORD)
	testing.expect(t, tech_demo_opens_menu(menu))
	testing.expect(t, !tech_demo_starts_world(menu))
	testing.expect_value(t, command_line_value_problem(menu), "")
	testing.expect_value(t, command_line_conflict(menu), "")
	testing.expect(t, !command_line_starts_world(menu))

	full, _ := parse_command_line({"--tech-demo=bodies,4000,home"})
	testing.expect(t, tech_demo_starts_world(full))
	testing.expect_value(t, command_line_value_problem(full), "")
	setup, problem := command_line_tech_demo_setup(full)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, setup, Tech_Demo_Setup{.Bodies, 4000, .Home})
	partial, _ := parse_command_line({"--tech-demo=,16000"})
	setup, problem = command_line_tech_demo_setup(partial)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, setup, Tech_Demo_Setup{.Teleport, 16000, .Spring})
	for invalid in ([?]string{"--tech-demo=rivers", "--tech-demo=teleport,abc", "--tech-demo=teleport,0", "--tech-demo=teleport,8000,moon", "--tech-demo=teleport,8000,spring,extra"}) {
		command_line, _ := parse_command_line({invalid})
		testing.expectf(t, strings.has_prefix(command_line_value_problem(command_line), "invalid --tech-demo"), "%s accepted: %q", invalid, command_line_value_problem(command_line))
	}

	with_load, _ := parse_command_line({"--tech-demo", "--load=x"})
	testing.expect(t, strings.has_prefix(command_line_conflict(with_load), "--tech-demo and --load"), command_line_conflict(with_load))
	with_preview, _ := parse_command_line({"--tech-demo=bodies", "--planet-preview"})
	testing.expect(t, strings.contains(command_line_conflict(with_preview), "--planet-preview"), command_line_conflict(with_preview))
	with_seed, _ := parse_command_line({"--tech-demo", "--seed=5", "--dev"})
	testing.expect_value(t, command_line_value_problem(with_seed), "")
	testing.expect_value(t, command_line_conflict(with_seed), "")
	testing.expect(t, with_seed.developer_mode)
	testing.expect_value(t, with_seed.seed, "5")

	planets := shipped_test_planets()
	items := make_test_items()
	kits := make_test_developer_kits(items)
	off_preset, _ := parse_command_line({"--tech-demo=teleport,5000"})
	_, data_problem := command_line_data_problem(off_preset, items, kits, planets)
	testing.expect(t, strings.has_prefix(data_problem, "invalid --tech-demo radius 5000"), data_problem)
	testing.expect(t, strings.contains(data_problem, "4000"), data_problem)
	for accepted in ([?]string{"--tech-demo=teleport,4000", "--tech-demo=bodies"}) {
		command_line, _ := parse_command_line({accepted})
		_, data_problem = command_line_data_problem(command_line, items, kits, planets)
		testing.expectf(t, data_problem == "", "%s refused: %s", accepted, data_problem)
	}
	_, data_problem = command_line_data_problem(full, items, kits, nil)
	testing.expect(t, strings.contains(data_problem, "no planet"), data_problem)
}

@(test)
test_command_line_model_workbench_flags :: proc(t: ^testing.T) {
	check, error := parse_command_line({"--model-check=all"})
	testing.expect_value(t, error, nil)
	testing.expect_value(t, check.model_check, "all")
	testing.expect_value(t, command_line_conflict(check), "")
	preview, _ := parse_command_line({"--model-preview=a", "--model-preview-directory=d"})
	testing.expect_value(t, command_line_conflict(preview), "")
	alone, _ := parse_command_line({"--model-preview=a"})
	testing.expect_value(t, command_line_conflict(alone), "--model-preview needs --model-preview-directory")
	directory, _ := parse_command_line({"--model-preview-directory=d"})
	testing.expect_value(t, command_line_conflict(directory), "--model-preview-directory needs --model-preview")
	both, _ := parse_command_line({"--model-check=all", "--model-preview=a", "--model-preview-directory=d"})
	testing.expect_value(t, command_line_conflict(both), "--model-check and --model-preview cannot be combined")
	for other in ([?]string{"--benchmark=1", "--seed=7", "--server", "--planet-preview", "--planet-preview-yaw=30"}) {
		combined, _ := parse_command_line({"--model-check=all", other})
		testing.expectf(t, strings.has_prefix(command_line_conflict(combined), "--model-check runs no world"), "--model-check with %s accepted", other)
	}
}

// Work item 0341: --input=none reads only the command socket, so it
// needs the socket and developer mode from the flag or the setting.
@(test)
test_input_none_is_parsed_and_needs_developer_mode_and_the_socket :: proc(t: ^testing.T) {
	request, ok := parse_input_request("none")
	testing.expect(t, ok)
	testing.expect_value(t, request, Input_Backend_Request.None)
	none, none_error := parse_command_line({"--input=none"})
	testing.expect_value(t, none_error, nil)
	testing.expect_value(t, command_line_value_problem(none), "")
	unknown, _ := parse_command_line({"--input=vulkan"})
	testing.expect(t, strings.contains(command_line_value_problem(unknown), "--input=none"), command_line_value_problem(unknown))
	testing.expect_value(t, input_none_problem(.None, false, false, true), "--input=none reads only the command socket, which needs developer mode (--dev or the Developer mode setting)")
	testing.expect_value(t, input_none_problem(.None, true, false, false), "--input=none reads only the command socket, which the Windows build lacks")
	testing.expect_value(t, input_none_problem(.None, true, false, true), "")
	testing.expect_value(t, input_none_problem(.None, false, true, true), "")
	testing.expect_value(t, input_none_problem(.Sdl3, false, false, true), "")
}
