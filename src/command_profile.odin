package game

import "core:fmt"
import "core:strings"

// The frame profile's command words and query profile's answer (work
// item 0342, doc/commands.md, Frame profile). The commands run in the
// loop (loop_profile.odin); this file parses their words and lays out
// the report (render_frame_profile.odin) as lines.

PROFILE_SETTLE_DEFAULT_FRAMES :: 3600

PROFILE_USAGE :: "usage: profile settle [frames] | profile sample <frames>"
VIEWPORT_USAGE :: "usage: viewport add|remove"

// The wait and its frames, or the problem (the usage, or the frames out
// of range).
parse_profile_command :: proc(arguments: []string) -> (wait: Profile_Wait, frames: int, problem: string) {
	switch {
	case len(arguments) == 1 && arguments[0] == "settle":
		return .Settle, PROFILE_SETTLE_DEFAULT_FRAMES, ""
	case len(arguments) == 2 && (arguments[0] == "settle" || arguments[0] == "sample"):
		frames, problem = parse_ranged_word(arguments[1], 1, MAXIMUM_PROFILE_SAMPLE_FRAMES, "the frames")
		if problem != "" {
			return .None, 0, problem
		}
		return arguments[0] == "settle" ? .Settle : .Sample, frames, ""
	}
	return .None, 0, PROFILE_USAGE
}

parse_viewport_command :: proc(arguments: []string) -> (add: bool, problem: string) {
	if len(arguments) == 1 && (arguments[0] == "add" || arguments[0] == "remove") {
		return arguments[0] == "add", ""
	}
	return false, VIEWPORT_USAGE
}

// The report as query profile's lines, every number in milliseconds with
// three decimals unless its line says otherwise. In the temp allocator.
profile_report_response :: proc(report: Profile_Report) -> Command_Response {
	builder := strings.builder_make(context.temp_allocator)
	display := report.display
	fps := report.seconds > 0 ? f64(report.frames) / report.seconds : 0
	fmt.sbprintf(&builder, "profile %d frames", report.frames)
	fmt.sbprintf(&builder, "\nframes %d gpu %d dropped %d seconds %.3f fps %.1f", report.frames, report.gpu_frames, report.gpu_dropped, report.seconds, fps)
	fmt.sbprintf(&builder, "\ndisplay render %d %d window %d %d viewports %d vsync %s cap %d", display.render.x, display.render.y, display.window.x, display.window.y, display.viewports, yes_no(display.vsync), display.frame_rate_cap)
	write_profile_statistics(&builder, "frame work", report.work)
	write_profile_statistics(&builder, "frame wall", report.wall)
	if report.gpu_frames > 0 {
		write_profile_statistics(&builder, "frame gpu", report.gpu)
	} else {
		strings.write_string(&builder, "\nframe gpu none")
	}
	fmt.sbprintf(&builder, "\nticks %d mean %.3f worst %.3f hashes %d saves %d", report.ticks, report.tick_mean, report.tick_worst, report.state_hashes, report.saves)
	for statistics, section in report.cpu {
		write_profile_statistics(&builder, fmt.tprintf("cpu %s", lower_name(section)), statistics)
	}
	write_profile_gpu_sections(&builder, report)
	for milliseconds, section in report.tick_sections {
		fmt.sbprintf(&builder, "\ntick %s %.3f", lower_name(section), milliseconds)
	}
	for mean, section in report.draws_mean {
		fmt.sbprintf(&builder, "\ndraws %s %.1f %d", lower_name(section), mean, report.draws_worst[section])
	}
	for mean, counter in report.counters_mean {
		fmt.sbprintf(&builder, "\ncount %s %.1f %d", lower_name(counter), mean, report.counters_worst[counter])
	}
	worst := report.worst
	fmt.sbprintf(&builder, "\nworst frame %d work %.3f ticks %d events %s", worst.frame, frame_record_work(worst), worst.ticks, frame_events_text(worst.events))
	for milliseconds, section in worst.cpu {
		fmt.sbprintf(&builder, "\nworst cpu %s %.3f", lower_name(section), milliseconds)
	}
	return query_response(&builder)
}

write_profile_statistics :: proc(builder: ^strings.Builder, name: string, statistics: Section_Statistics) {
	fmt.sbprintf(builder, "\n%s %.3f %.3f %.3f %.3f", name, statistics.mean, statistics.p50, statistics.p99, statistics.worst)
}

// Prepare to Composite, the sections the GPU is timed in, or gpu none.
write_profile_gpu_sections :: proc(builder: ^strings.Builder, report: Profile_Report) {
	if report.gpu_frames == 0 {
		strings.write_string(builder, "\ngpu none")
		return
	}
	for section in Frame_Section.Prepare ..= Frame_Section.Composite {
		write_profile_statistics(builder, fmt.tprintf("gpu %s", lower_name(section)), report.gpu_sections[section])
	}
}

// "none", or the events' words joined by commas.
frame_events_text :: proc(events: bit_set[Frame_Event]) -> string {
	if events == {} {
		return "none"
	}
	words := make([dynamic]string, context.temp_allocator)
	for event in events {
		append(&words, lower_name(event))
	}
	return strings.join(words[:], ",", context.temp_allocator)
}
