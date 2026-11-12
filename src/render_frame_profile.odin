package game

import "core:slice"
import "core:time"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// The frame profile (work item 0342, doc/architecture.md, Performance):
// the frame's CPU time per section, always on. A mark (profile_mark)
// reads the clock, adds the time and the draw calls since the last mark
// to the open section and opens its own; a section entered twice in a
// frame adds up, so in split screen each section sums its viewports.
// While the F3 Render page shows or a sample runs, every mark from
// Prepare to Present also writes a GPU timestamp query, read back one to
// three frames later without waiting, so the GPU's sections are the
// CPU's. The tick's sections come from the Tick_Profile run_ready_ticks
// fills, the counts from the field's draws. The last 64 frames feed the
// F3 page; a sample of up to 36000 frames feeds the command socket's
// query profile.

FRAME_PROFILE_RECENT_FRAMES :: 64
FRAME_PROFILE_GPU_SETS :: 6
FRAME_PROFILE_MAXIMUM_MARKS :: 96
// Sets dropped in a row before the GPU timing gives up.
FRAME_PROFILE_GPU_DROP_LIMIT :: 32
MAXIMUM_PROFILE_SAMPLE_FRAMES :: 36000
GL_TIMESTAMP :: 0x8E28
GL_QUERY_RESULT :: 0x8866
GL_QUERY_RESULT_AVAILABLE :: 0x8867

// In frame order, but Globe, drawn after Cover since 0349 and kept in its
// place so the tables before and after keep their columns; the mark that
// opens each is in doc/architecture.md, Performance. Prepare to Composite
// are the GPU's sections as well.
Frame_Section :: enum u8 {
	Input,
	Ticks,
	Save,
	Streaming,
	Requests,
	Prepare,
	Sky,
	Shadow_Terrain,
	Shadow_Trees,
	Shadow_Models,
	Lights,
	Globe,
	Terrain,
	Cover,
	Water,
	Foundations,
	Machines,
	Trees,
	Runs,
	Effects,
	Interface,
	Composite,
	Present,
	Between,
}

// Counted per frame, summed over the viewports.
Frame_Counter :: enum u8 {
	Selected_Nodes,
	Terrain_Nodes,
	Terrain_Triangles,
	Water_Nodes,
	Cover_Instances,
	Near_Trees,
	Far_Tiles,
	Far_Cards,
	Shadow_Nodes,
	Shadow_Trees,
	Mesh_Jobs,
	Mesh_Uploads,
}

Frame_Event :: enum u8 {
	// The frame's ticks took the hash's snapshot.
	State_Hash,
	// The frame saved (save_when_due).
	Save,
}

// One frame on the CPU, in milliseconds: the sections, the draw calls
// between their marks, the counters, and the frame's ticks with their
// sections summed over them.
Frame_Record :: struct {
	frame:         int,
	cpu:           [Frame_Section]f32,
	draws:         [Frame_Section]u32,
	counters:      [Frame_Counter]i32,
	ticks:         u16,
	tick_sections: [Tick_Section]f32,
	longest_tick:  f32,
	events:        bit_set[Frame_Event],
}

// One frame on the GPU, in milliseconds; total runs from Prepare's
// timestamp to Present's.
Frame_Gpu_Record :: struct {
	frame:    int,
	sections: [Frame_Section]f32,
	total:    f32,
}

// The display a sample ran at, taken when it completed.
Profile_Display :: struct {
	render, window: [2]int,
	viewports:      int,
	vsync:          bool,
	frame_rate_cap: int,
}

// The frames from first to first + wanted - 1, reserved at the start so
// no allocation lands inside it; gpu_dropped counts its frames whose GPU
// results never came.
Frame_Sample :: struct {
	wanted, first, gpu_dropped: int,
	records:                    [dynamic]Frame_Record,
	gpu:                        [dynamic]Frame_Gpu_Record,
	display:                    Profile_Display,
}

// Off until the first want, Unavailable without timer queries.
Frame_Gpu_State :: enum u8 {
	Off,
	Ready,
	Unavailable,
}

// The GL query procedures, through GLFW's loader (load_frame_gpu).
Frame_Gpu_Procedures :: struct {
	generate_queries:     proc "c" (count: i32, ids: [^]u32),
	delete_queries:       proc "c" (count: i32, ids: [^]u32),
	query_counter:        proc "c" (id, target: u32),
	get_query_object_int: proc "c" (id, name: u32, value: ^i32),
	get_query_object_u64: proc "c" (id, name: u32, value: ^u64),
}

// One frame's timestamps: ids[i] was written at the mark of sections[i].
// pending while its results wait to be read.
Frame_Gpu_Set :: struct {
	ids:      [FRAME_PROFILE_MAXIMUM_MARKS]u32,
	sections: [FRAME_PROFILE_MAXIMUM_MARKS]Frame_Section,
	count:    int,
	frame:    int,
	pending:  bool,
}

// timing is this frame's: the GPU is wanted and Ready.
Frame_Gpu :: struct {
	state:          Frame_Gpu_State,
	procedures:     Frame_Gpu_Procedures,
	sets:           [FRAME_PROFILE_GPU_SETS]Frame_Gpu_Set,
	timing:         bool,
	drops_in_a_row: int,
	dropped:        int,
}

// The loop's (Frame_Developer_Tools.frame_profile). current is the frame
// being measured, open its section since last_mark. recent_count and
// recent_gpu_count count every record filed; the rings hold the last
// FRAME_PROFILE_RECENT_FRAMES of each.
Frame_Profile :: struct {
	frame:              int,
	current:            Frame_Record,
	open:               Frame_Section,
	last_mark:          time.Tick,
	draws_at_last_mark: int,
	tick_profile:       Tick_Profile,
	recent:             [FRAME_PROFILE_RECENT_FRAMES]Frame_Record,
	recent_gpu:         [FRAME_PROFILE_RECENT_FRAMES]Frame_Gpu_Record,
	recent_count:       int,
	recent_gpu_count:   int,
	sample:             Frame_Sample,
	sampling:           bool,
	gpu:                Frame_Gpu,
}

// Milliseconds; the percentiles by nearest rank.
Section_Statistics :: struct {
	mean, p50, p99, worst: f32,
}

// The statistics of a run of records (frame_profile_report), in
// milliseconds: work is a frame's sections without Present, wall all of
// them. tick_sections are means per tick.
Profile_Report :: struct {
	frames, gpu_frames, gpu_dropped: int,
	seconds:                         f64,
	display:                         Profile_Display,
	work, wall, gpu:                 Section_Statistics,
	cpu, gpu_sections:               [Frame_Section]Section_Statistics,
	draws_mean:                      [Frame_Section]f32,
	draws_worst:                     [Frame_Section]u32,
	counters_mean:                   [Frame_Counter]f32,
	counters_worst:                  [Frame_Counter]i32,
	ticks:                           int,
	tick_mean, tick_worst:           f32,
	state_hashes, saves:             int,
	tick_sections:                   [Tick_Section]f32,
	// The frame of the largest work.
	worst:                           Frame_Record,
}

// The mesh draw calls so far (count_draw_call at the draw sites), which
// the marks read. Main thread only, like global_string_table.
frame_draw_calls: int

count_draw_call :: proc() {
	frame_draw_calls += 1
}

// Pure.

// The interval and the draws since the last mark go to the open section,
// then section opens at now.
mark_frame_section :: proc(profile: ^Frame_Profile, section: Frame_Section, now: time.Tick, draw_calls: int) {
	profile.current.cpu[profile.open] += f32(time.duration_milliseconds(time.tick_diff(profile.last_mark, now)))
	profile.current.draws[profile.open] += u32(max(draw_calls - profile.draws_at_last_mark, 0))
	profile.open = section
	profile.last_mark = now
	profile.draws_at_last_mark = draw_calls
}

// Files the frame before (its open section closed at now, its ticks
// taken), then starts the next with Input open.
begin_profiled_frame_at :: proc(profile: ^Frame_Profile, now: time.Tick, draw_calls: int) {
	if profile.frame > 0 {
		mark_frame_section(profile, profile.open, now, draw_calls)
		take_tick_profile(&profile.current, &profile.tick_profile)
		file_frame_record(profile, profile.current)
	}
	profile.frame += 1
	profile.current = {frame = profile.frame}
	profile.open = .Input
	profile.last_mark = now
	profile.draws_at_last_mark = draw_calls
}

// The frame's ticks into the record in milliseconds; the tick profile
// starts over.
take_tick_profile :: proc(record: ^Frame_Record, ticks: ^Tick_Profile) {
	record.ticks = u16(min(ticks.ticks, int(max(u16))))
	for seconds, section in ticks.seconds {
		record.tick_sections[section] = f32(seconds * 1000)
	}
	record.longest_tick = f32(ticks.longest_seconds * 1000)
	if ticks.state_hashes > 0 {
		record.events += {.State_Hash}
	}
	ticks^ = {}
}

frame_in_sample :: proc(profile: ^Frame_Profile, frame: int) -> bool {
	sample := profile.sample
	return profile.sampling && sample.first <= frame && frame < sample.first + sample.wanted
}

// Into the ring, and into the sample while it runs and the frame is one
// of its frames.
file_frame_record :: proc(profile: ^Frame_Profile, record: Frame_Record) {
	profile.recent[profile.recent_count % FRAME_PROFILE_RECENT_FRAMES] = record
	profile.recent_count += 1
	if frame_in_sample(profile, record.frame) {
		append(&profile.sample.records, record)
	}
}

// The interval from mark i - 1 to mark i goes to sections[i - 1]; a
// timestamp below its predecessor counts 0. In milliseconds.
gpu_record_from_marks :: proc(frame: int, sections: []Frame_Section, timestamps: []u64) -> Frame_Gpu_Record {
	record := Frame_Gpu_Record{frame = frame}
	for index in 1 ..< len(timestamps) {
		record.sections[sections[index - 1]] += nanoseconds_to_milliseconds(timestamps[index - 1], timestamps[index])
	}
	if len(timestamps) >= 2 {
		record.total = nanoseconds_to_milliseconds(timestamps[0], timestamps[len(timestamps) - 1])
	}
	return record
}

// 0 when to is before from.
nanoseconds_to_milliseconds :: proc(from, to: u64) -> f32 {
	return to > from ? f32(f64(to - from) / 1e6) : 0
}

file_gpu_record :: proc(profile: ^Frame_Profile, record: Frame_Gpu_Record) {
	profile.recent_gpu[profile.recent_gpu_count % FRAME_PROFILE_RECENT_FRAMES] = record
	profile.recent_gpu_count += 1
	if frame_in_sample(profile, record.frame) {
		append(&profile.sample.gpu, record)
	}
}

file_gpu_drop :: proc(profile: ^Frame_Profile, frame: int) {
	profile.gpu.dropped += 1
	if frame_in_sample(profile, frame) {
		profile.sample.gpu_dropped += 1
	}
}

// The next frames into a new sample; the last one is cleared.
start_frame_sample :: proc(profile: ^Frame_Profile, frames: int) {
	clear(&profile.sample.records)
	clear(&profile.sample.gpu)
	reserve(&profile.sample.records, frames)
	reserve(&profile.sample.gpu, frames)
	profile.sample.wanted = frames
	profile.sample.first = profile.frame + 1
	profile.sample.gpu_dropped = 0
	profile.sample.display = {}
	profile.sampling = true
}

// Every frame is in, and every GPU result or its drop while the GPU is
// timed.
frame_sample_complete :: proc(profile: Frame_Profile) -> bool {
	sample := profile.sample
	if len(sample.records) < sample.wanted {
		return false
	}
	return profile.gpu.state != .Ready || len(sample.gpu) + sample.gpu_dropped >= sample.wanted
}

// The values sorted in place; the percentiles by nearest rank (index
// ceil(p n / 100) - 1). All zero when empty.
section_statistics :: proc(values: []f32) -> Section_Statistics {
	if len(values) == 0 {
		return {}
	}
	slice.sort(values)
	sum: f64
	for value in values {
		sum += f64(value)
	}
	return Section_Statistics{mean = f32(sum / f64(len(values))), p50 = nearest_rank(values, 50), p99 = nearest_rank(values, 99), worst = values[len(values) - 1]}
}

nearest_rank :: proc(sorted: []f32, percent: int) -> f32 {
	return sorted[max((percent * len(sorted) + 99) / 100 - 1, 0)]
}

// The frame's sections less Present: what the CPU worked.
frame_record_work :: proc(record: Frame_Record) -> f32 {
	return frame_record_wall(record) - record.cpu[.Present]
}

frame_record_wall :: proc(record: Frame_Record) -> f32 {
	total: f32
	for milliseconds in record.cpu {
		total += milliseconds
	}
	return total
}

frame_record_tick_milliseconds :: proc(record: Frame_Record) -> f32 {
	total: f32
	for milliseconds in record.tick_sections {
		total += milliseconds
	}
	return total
}

// The statistics of the records and their GPU records. In temp memory.
frame_profile_report :: proc(records: []Frame_Record, gpu: []Frame_Gpu_Record, gpu_dropped: int, display: Profile_Display) -> Profile_Report {
	report := Profile_Report{frames = len(records), gpu_frames = len(gpu), gpu_dropped = gpu_dropped, display = display}
	values := make([]f32, len(records), context.temp_allocator)
	for record, index in records {
		values[index] = frame_record_wall(record)
		report.seconds += f64(values[index]) / 1000
	}
	report.wall = section_statistics(values)
	for record, index in records {
		values[index] = frame_record_work(record)
	}
	report.work = section_statistics(values)
	for section in Frame_Section {
		for record, index in records {
			values[index] = record.cpu[section]
		}
		report.cpu[section] = section_statistics(values)
	}
	add_gpu_statistics(&report, gpu)
	add_count_statistics(&report, records)
	add_tick_statistics(&report, records)
	worst_work := f32(-1)
	for record in records {
		if work := frame_record_work(record); work > worst_work {
			report.worst, worst_work = record, work
		}
	}
	return report
}

add_gpu_statistics :: proc(report: ^Profile_Report, gpu: []Frame_Gpu_Record) {
	values := make([]f32, len(gpu), context.temp_allocator)
	for record, index in gpu {
		values[index] = record.total
	}
	report.gpu = section_statistics(values)
	for section in Frame_Section {
		for record, index in gpu {
			values[index] = record.sections[section]
		}
		report.gpu_sections[section] = section_statistics(values)
	}
}

// The draw calls' and the counters' means and worst.
add_count_statistics :: proc(report: ^Profile_Report, records: []Frame_Record) {
	if len(records) == 0 {
		return
	}
	for record in records {
		for draws, section in record.draws {
			report.draws_mean[section] += f32(draws)
			report.draws_worst[section] = max(report.draws_worst[section], draws)
		}
		for count, counter in record.counters {
			report.counters_mean[counter] += f32(count)
			report.counters_worst[counter] = max(report.counters_worst[counter], count)
		}
	}
	for &draws in report.draws_mean {
		draws /= f32(len(records))
	}
	for &count in report.counters_mean {
		count /= f32(len(records))
	}
}

// The ticks, their mean per tick and the longest, the events.
add_tick_statistics :: proc(report: ^Profile_Report, records: []Frame_Record) {
	total: f32
	for record in records {
		report.ticks += int(record.ticks)
		total += frame_record_tick_milliseconds(record)
		report.tick_worst = max(report.tick_worst, record.longest_tick)
		for milliseconds, section in record.tick_sections {
			report.tick_sections[section] += milliseconds
		}
		report.state_hashes += .State_Hash in record.events ? 1 : 0
		report.saves += .Save in record.events ? 1 : 0
	}
	if report.ticks == 0 {
		return
	}
	report.tick_mean = total / f32(report.ticks)
	for &milliseconds in report.tick_sections {
		milliseconds /= f32(report.ticks)
	}
}

// The report over the rings' filled part, for the F3 Render page.
recent_frame_profile_report :: proc(profile: ^Frame_Profile) -> Profile_Report {
	records := profile.recent[:min(profile.recent_count, FRAME_PROFILE_RECENT_FRAMES)]
	gpu := profile.recent_gpu[:min(profile.recent_gpu_count, FRAME_PROFILE_RECENT_FRAMES)]
	return frame_profile_report(records, gpu, profile.gpu.dropped, {})
}

// Impure.

// At the top of the frame: the GPU results that are in, the last frame
// filed, the GPU timing loaded on the first want, and this frame's set of
// queries taken. A set still unread when its slot comes round is dropped.
begin_profiled_frame :: proc(profile: ^Frame_Profile, gpu_wanted: bool) {
	collect_gpu_sets(profile)
	begin_profiled_frame_at(profile, time.tick_now(), frame_draw_calls)
	gpu := &profile.gpu
	if gpu_wanted && gpu.state == .Off {
		load_frame_gpu(gpu)
	}
	gpu.timing = gpu_wanted && gpu.state == .Ready
	if !gpu.timing {
		return
	}
	set := &gpu.sets[profile.frame % FRAME_PROFILE_GPU_SETS]
	if set.pending {
		set.pending = false
		file_gpu_drop(profile, set.frame)
		gpu.drops_in_a_row += 1
		if gpu.drops_in_a_row >= FRAME_PROFILE_GPU_DROP_LIMIT {
			delete_frame_gpu_queries(gpu)
			gpu.state, gpu.timing = .Unavailable, false
			platform.log_printf("profile: GPU timer queries never became readable, the profile times the CPU only")
			return
		}
	}
	set.count, set.frame = 0, profile.frame
}

// Opens the section. While the GPU is timed the batch is drawn first, so
// the batched cubes are timed in their own section, and a mark from
// Prepare to Present writes a timestamp; past the set's last free id
// only Present does. Nil does nothing.
profile_mark :: proc(profile: ^Frame_Profile, section: Frame_Section) {
	if profile == nil {
		return
	}
	gpu := &profile.gpu
	if gpu.timing {
		rlgl.DrawRenderBatchActive()
	}
	mark_frame_section(profile, section, time.tick_now(), frame_draw_calls)
	if !gpu.timing || section < .Prepare || section > .Present {
		return
	}
	set := &gpu.sets[profile.frame % FRAME_PROFILE_GPU_SETS]
	if set.count < FRAME_PROFILE_MAXIMUM_MARKS - 1 || (section == .Present && set.count < FRAME_PROFILE_MAXIMUM_MARKS) {
		gpu.procedures.query_counter(set.ids[set.count], GL_TIMESTAMP)
		set.sections[set.count] = section
		set.count += 1
	}
	if section == .Present {
		set.pending = set.count >= 2
	}
}

// Present, the swap, then Between: in place of rl.EndDrawing.
end_profiled_drawing :: proc(profile: ^Frame_Profile) {
	profile_mark(profile, .Present)
	rl.EndDrawing()
	profile_mark(profile, .Between)
}

count_frame :: proc(profile: ^Frame_Profile, counter: Frame_Counter, amount: int) {
	if profile == nil {
		return
	}
	profile.current.counters[counter] += i32(amount)
}

note_frame_event :: proc(profile: ^Frame_Profile, event: Frame_Event) {
	if profile == nil {
		return
	}
	profile.current.events += {event}
}

// The pending sets oldest first, each once its last timestamp is
// available; the first not yet available ends the pass, since the later
// ones come after it. Never waits.
collect_gpu_sets :: proc(profile: ^Frame_Profile) {
	gpu := &profile.gpu
	if gpu.state != .Ready {
		return
	}
	for {
		oldest := -1
		for set, index in gpu.sets {
			if set.pending && (oldest < 0 || set.frame < gpu.sets[oldest].frame) {
				oldest = index
			}
		}
		if oldest < 0 {
			return
		}
		set := &gpu.sets[oldest]
		available: i32
		gpu.procedures.get_query_object_int(set.ids[set.count - 1], GL_QUERY_RESULT_AVAILABLE, &available)
		if available == 0 {
			return
		}
		timestamps: [FRAME_PROFILE_MAXIMUM_MARKS]u64
		for index in 0 ..< set.count {
			gpu.procedures.get_query_object_u64(set.ids[index], GL_QUERY_RESULT, &timestamps[index])
		}
		file_gpu_record(profile, gpu_record_from_marks(set.frame, set.sections[:set.count], timestamps[:set.count]))
		set.pending = false
		gpu.drops_in_a_row = 0
	}
}

// The query procedures through GLFW's loader and every set's ids; Ready,
// or Unavailable with a log line when a procedure is missing (a
// translation layer). Android's GLES 3.0 has no timestamp query, so it is
// Unavailable without trying.
load_frame_gpu :: proc(gpu: ^Frame_Gpu) {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		gpu.state = .Unavailable
	} else {
		names := [5]cstring{"glGenQueries", "glDeleteQueries", "glQueryCounter", "glGetQueryObjectiv", "glGetQueryObjectui64v"}
		addresses: [5]rawptr
		for name, index in names {
			addresses[index] = rl.glfwGetProcAddress(name)
			if addresses[index] == nil {
				gpu.state = .Unavailable
				platform.log_printf("profile: GPU timer queries unavailable (no %s), the profile times the CPU only", name)
				return
			}
		}
		gpu.procedures = Frame_Gpu_Procedures {
			generate_queries     = cast(proc "c" (count: i32, ids: [^]u32))addresses[0],
			delete_queries       = cast(proc "c" (count: i32, ids: [^]u32))addresses[1],
			query_counter        = cast(proc "c" (id, target: u32))addresses[2],
			get_query_object_int = cast(proc "c" (id, name: u32, value: ^i32))addresses[3],
			get_query_object_u64 = cast(proc "c" (id, name: u32, value: ^u64))addresses[4],
		}
		for &set in gpu.sets {
			gpu.procedures.generate_queries(FRAME_PROFILE_MAXIMUM_MARKS, &set.ids[0])
		}
		platform.log_printf("profile: GPU timer queries on")
		gpu.state = .Ready
	}
}

delete_frame_gpu_queries :: proc(gpu: ^Frame_Gpu) {
	for &set in gpu.sets {
		gpu.procedures.delete_queries(FRAME_PROFILE_MAXIMUM_MARKS, &set.ids[0])
		set = {}
	}
}

// Before the window closes: the query ids while Ready, and the sample.
release_frame_profile :: proc(profile: ^Frame_Profile) {
	if profile.gpu.state == .Ready {
		delete_frame_gpu_queries(&profile.gpu)
	}
	delete(profile.sample.records)
	delete(profile.sample.gpu)
	profile.sample = {}
}
