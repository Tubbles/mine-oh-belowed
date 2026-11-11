package game

import "core:strings"
import "core:testing"

// The frame profile's commands (work item 0342): query profile's lines,
// the commands' words, as, and the commands that need the frame.

@(test)
test_the_profile_report_names_every_section :: proc(t: ^testing.T) {
	records: [2]Frame_Record
	records[0] = Frame_Record{frame = 1, ticks = 1, longest_tick = 0.5}
	records[0].cpu[.Input], records[0].cpu[.Present] = 1, 3
	records[0].tick_sections[.Field_Water] = 0.5
	records[1] = Frame_Record{frame = 2}
	records[1].cpu[.Input], records[1].cpu[.Present] = 2, 1
	display := Profile_Display{render = {1920, 1080}, window = {1920, 1080}, viewports = 1}
	text := profile_report_response(frame_profile_report(records[:], nil, 0, display)).text
	head := "profile 2 frames\nframes 2 gpu 0 dropped 0 seconds 0.007 fps 285.7\ndisplay render 1920 1080 window 1920 1080 viewports 1 vsync no cap 0\nframe work 1.500 1.000 2.000 2.000\nframe wall 3.500 3.000 4.000 4.000\nframe gpu none\nticks 1 mean 0.500 worst 0.500 hashes 0 saves 0\n"
	testing.expectf(t, strings.has_prefix(text, head), "the report starts\n%s", text)
	lines := strings.split_lines(text, context.temp_allocator)
	testing.expect_value(t, len(lines), 121)
	testing.expect(t, report_has_line(lines, "gpu none"))
	testing.expect(t, report_has_line(lines, "tick field_water 0.500"))
	for section in Frame_Section {
		name := lower_name(section)
		for prefix in ([?]string{"cpu", "draws", "worst cpu"}) {
			testing.expectf(t, report_has_prefix(lines, strings.concatenate({prefix, " ", name, " "}, context.temp_allocator)), "no %s line for %s", prefix, name)
		}
	}
	for counter in Frame_Counter {
		testing.expectf(t, report_has_prefix(lines, strings.concatenate({"count ", lower_name(counter), " "}, context.temp_allocator)), "no count line for %v", counter)
	}

	gpu := [2]Frame_Gpu_Record{{frame = 1, total = 2}, {frame = 2, total = 4}}
	timed := strings.split_lines(profile_report_response(frame_profile_report(records[:], gpu[:], 0, display)).text, context.temp_allocator)
	gpu_sections := 0
	for line in timed {
		if strings.has_prefix(line, "gpu ") {
			gpu_sections += 1
		}
	}
	testing.expect_value(t, gpu_sections, 17)
	testing.expect(t, report_has_line(timed, "frame gpu 3.000 2.000 4.000 4.000"))
}

report_has_line :: proc(lines: []string, wanted: string) -> bool {
	for line in lines {
		if line == wanted {
			return true
		}
	}
	return false
}

report_has_prefix :: proc(lines: []string, prefix: string) -> bool {
	for line in lines {
		if strings.has_prefix(line, prefix) {
			return true
		}
	}
	return false
}

@(test)
test_profile_commands_check_their_numbers :: proc(t: ^testing.T) {
	wait, frames, problem := parse_profile_command({"settle"})
	testing.expect_value(t, wait, Profile_Wait.Settle)
	testing.expect_value(t, frames, PROFILE_SETTLE_DEFAULT_FRAMES)
	testing.expect_value(t, problem, "")
	wait, frames, problem = parse_profile_command({"sample", "600"})
	testing.expect_value(t, wait, Profile_Wait.Sample)
	testing.expect_value(t, frames, 600)
	for words in ([?][]string{{"settle", "0"}, {"settle", "36001"}}) {
		_, _, problem = parse_profile_command(words)
		testing.expect_value(t, problem, "the frames must be a number from 1 to 36000")
	}
	for words in ([?][]string{{"sample"}, {"sample", "1", "2"}, {"bogus"}}) {
		_, _, problem = parse_profile_command(words)
		testing.expect_value(t, problem, PROFILE_USAGE)
	}
	add, viewport_problem := parse_viewport_command({"add"})
	testing.expect(t, add && viewport_problem == "")
	add, viewport_problem = parse_viewport_command({"remove"})
	testing.expect(t, !add && viewport_problem == "")
	_, viewport_problem = parse_viewport_command({"sideways"})
	testing.expect_value(t, viewport_problem, VIEWPORT_USAGE)
}

@(test) // slow
test_as_runs_a_command_for_another_local_player :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	add_player_entry(&test.session.simulation, test.content, 1, Player_Start{})
	players := test.session.simulation.players[:]
	first_bearing := field_player_bearing_degrees(players[0].field)
	expect_field_command_ok(t, test, "as 1 look 90 0")
	testing.expectf(t, abs(field_player_bearing_degrees(players[1].field) - 90) < 0.1, "player 1's bearing %f", field_player_bearing_degrees(players[1].field))
	testing.expect_value(t, field_player_bearing_degrees(players[0].field), first_bearing)
	expect_field_command_error(t, test, "as 2 look 0 0", "the player must be a number from 0 to 1")
	refusal :: "as takes a command that changes the world, other than as and blueprint"
	expect_field_command_error(t, test, "as 1 query player", refusal)
	expect_field_command_error(t, test, "as 1 as 0 look 0 0", refusal)
	expect_field_command_error(t, test, "as 1 blueprint x.sjson", refusal)
	expect_field_command_error(t, test, "as 1", "usage: as <player> <command> [arguments]")
}

@(test)
test_profile_and_viewport_run_only_in_the_game :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	expect_field_command_error(t, test, "profile sample 10", "profile runs only in the game")
	expect_field_command_error(t, test, "viewport add", "viewport runs only in the game")
	expect_field_command_error(t, test, "query profile", "query profile runs only in the game")
}
