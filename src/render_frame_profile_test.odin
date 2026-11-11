package game

import "core:testing"
import "core:time"

// The frame profile (work item 0342): the marks' intervals and draws, the
// GPU's timestamps, the statistics, a sample's frames and the ring.

milliseconds_after_zero :: proc(milliseconds: int) -> time.Tick {
	return time.tick_add(time.Tick{}, time.Duration(milliseconds) * time.Millisecond)
}

expect_milliseconds :: proc(t: ^testing.T, got, wanted: f32, location := #caller_location) {
	testing.expectf(t, abs(got - wanted) < 0.001, "got %v ms, wanted %v", got, wanted, loc = location)
}

@(test)
test_marks_add_each_interval_to_the_open_section :: proc(t: ^testing.T) {
	profile: Frame_Profile
	defer release_frame_profile(&profile)
	begin_profiled_frame_at(&profile, milliseconds_after_zero(0), 0)
	mark_frame_section(&profile, .Ticks, milliseconds_after_zero(1), 0)
	mark_frame_section(&profile, .Prepare, milliseconds_after_zero(3), 0)
	mark_frame_section(&profile, .Ticks, milliseconds_after_zero(4), 0)
	begin_profiled_frame_at(&profile, milliseconds_after_zero(6), 0)
	testing.expect_value(t, profile.recent_count, 1)
	record := profile.recent[0]
	testing.expect_value(t, record.frame, 1)
	expect_milliseconds(t, record.cpu[.Input], 1)
	expect_milliseconds(t, record.cpu[.Ticks], 4)
	expect_milliseconds(t, record.cpu[.Prepare], 1)
	expect_milliseconds(t, frame_record_wall(record), 6)
	expect_milliseconds(t, frame_record_work(record), 6)
	testing.expect_value(t, profile.current.frame, 2)
	testing.expect_value(t, profile.open, Frame_Section.Input)
}

@(test)
test_draw_calls_are_counted_per_section :: proc(t: ^testing.T) {
	profile: Frame_Profile
	defer release_frame_profile(&profile)
	begin_profiled_frame_at(&profile, milliseconds_after_zero(0), 0)
	mark_frame_section(&profile, .Terrain, milliseconds_after_zero(1), 5)
	mark_frame_section(&profile, .Cover, milliseconds_after_zero(2), 12)
	testing.expect_value(t, profile.current.draws[.Input], 5)
	testing.expect_value(t, profile.current.draws[.Terrain], 7)
}

@(test)
test_gpu_timestamps_sum_into_their_sections :: proc(t: ^testing.T) {
	sections := [?]Frame_Section{.Prepare, .Terrain, .Prepare, .Present}
	timestamps := [?]u64{0, 1_000_000, 3_000_000, 4_000_000}
	record := gpu_record_from_marks(9, sections[:], timestamps[:])
	testing.expect_value(t, record.frame, 9)
	expect_milliseconds(t, record.sections[.Prepare], 2)
	expect_milliseconds(t, record.sections[.Terrain], 2)
	expect_milliseconds(t, record.total, 4)
	backwards := [?]u64{0, 2_000_000, 1_000_000, 4_000_000}
	stepped := gpu_record_from_marks(9, sections[:], backwards[:])
	expect_milliseconds(t, stepped.sections[.Terrain], 0)
	expect_milliseconds(t, stepped.sections[.Prepare], 2 + 3)
}

@(test)
test_section_statistics_take_the_nearest_rank :: proc(t: ^testing.T) {
	values: [100]f32
	for &value, index in values {
		value = f32(100 - index)
	}
	statistics := section_statistics(values[:])
	expect_milliseconds(t, statistics.mean, 50.5)
	expect_milliseconds(t, statistics.p50, 50)
	expect_milliseconds(t, statistics.p99, 99)
	expect_milliseconds(t, statistics.worst, 100)
	one := [?]f32{7}
	testing.expect_value(t, section_statistics(one[:]), Section_Statistics{7, 7, 7, 7})
	testing.expect_value(t, section_statistics(nil), Section_Statistics{})
}

@(test)
test_a_sample_takes_the_frames_after_its_start_and_completes :: proc(t: ^testing.T) {
	profile: Frame_Profile
	defer release_frame_profile(&profile)
	profile.frame = 5
	start_frame_sample(&profile, 3)
	for frame in 5 ..= 9 {
		testing.expect_value(t, frame_sample_complete(profile), frame > 8)
		file_frame_record(&profile, Frame_Record{frame = frame})
	}
	testing.expect_value(t, len(profile.sample.records), 3)
	for record, index in profile.sample.records {
		testing.expect_value(t, record.frame, 6 + index)
	}
	testing.expect(t, frame_sample_complete(profile))

	// Timed on the GPU: complete once every frame has its GPU record or
	// its drop; a record of a frame before the sample is not taken.
	profile.gpu.state = .Ready
	testing.expect(t, !frame_sample_complete(profile))
	file_gpu_record(&profile, Frame_Gpu_Record{frame = 4})
	file_gpu_record(&profile, Frame_Gpu_Record{frame = 6})
	file_gpu_drop(&profile, 7)
	testing.expect_value(t, len(profile.sample.gpu), 1)
	testing.expect_value(t, profile.sample.gpu_dropped, 1)
	testing.expect(t, !frame_sample_complete(profile))
	file_gpu_record(&profile, Frame_Gpu_Record{frame = 8})
	testing.expect(t, frame_sample_complete(profile))
	profile.gpu.state = .Off
}

@(test)
test_the_recent_report_averages_the_ring :: proc(t: ^testing.T) {
	profile: Frame_Profile
	defer release_frame_profile(&profile)
	for frame in 1 ..= 70 {
		record := Frame_Record{frame = frame}
		record.cpu[.Prepare] = f32(frame)
		file_frame_record(&profile, record)
	}
	report := recent_frame_profile_report(&profile)
	testing.expect_value(t, report.frames, FRAME_PROFILE_RECENT_FRAMES)
	expect_milliseconds(t, report.work.mean, 38.5)
	expect_milliseconds(t, report.work.worst, 70)
	testing.expect_value(t, report.worst.frame, 70)
}
