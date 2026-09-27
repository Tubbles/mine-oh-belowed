package game

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"

// The saved worlds the title screen and the Load screen list, read from
// each save's world.sjson. The format versions and the entities file's
// content tables say whether this build can load the save (0044, 0047).

Save_Summary :: struct {
	directory_name:           string,
	name:                     string,
	seed:                     u64,
	tick:                     u64,
	last_played_unix_seconds: i64,
	// False when the save has another format version or its entities file
	// is missing or its tables do not parse; load_problem says why.
	loadable:                 bool,
	load_problem:             string,
	// The save was made by an older generator (GENERATOR_VERSION): it
	// loads, with the new terrain wherever the player changed nothing.
	terrain_changed:          bool,
}

destroy_save_summaries :: proc(saves: ^[dynamic]Save_Summary) {
	for save in saves {
		delete(save.directory_name)
		delete(save.name)
		delete(save.load_problem)
	}
	clear(saves)
}

// Newest first, then by directory name, so equal times keep a stable order.
save_summary_before :: proc(first, second: Save_Summary) -> bool {
	if first.last_played_unix_seconds != second.last_played_unix_seconds {
		return first.last_played_unix_seconds > second.last_played_unix_seconds
	}
	return first.directory_name < second.directory_name
}

// The most recently played save, for Continue.
newest_save :: proc(saves: []Save_Summary) -> (index: int, found: bool) {
	index = -1
	for save, candidate in saves {
		if index < 0 || save.last_played_unix_seconds > saves[index].last_played_unix_seconds {
			index = candidate
		}
	}
	return index, index >= 0
}

// The world directory an entry belongs to: a staging directory belongs to
// no save yet, a previous directory to the save it backs up.
save_directory_of_entry :: proc(entry_name: string) -> (directory_name: string, ok: bool) {
	if strings.has_suffix(entry_name, STAGING_DIRECTORY_SUFFIX) {
		return "", false
	}
	return strings.trim_suffix(entry_name, PREVIOUS_DIRECTORY_SUFFIX), true
}

contains_directory_name :: proc(saves: []Save_Summary, directory_name: string) -> bool {
	for save in saves {
		if save.directory_name == directory_name {
			return true
		}
	}
	return false
}

// A save whose world.sjson cannot be read is left out; one of another
// format version is listed with that problem. expected is this build's
// header (make_save_header).
read_save_summary :: proc(saves_directory, directory_name: string, expected: Save_Header) -> (summary: Save_Summary, ok: bool) {
	directory := existing_save_directory(Save_Location{saves_directory = saves_directory, directory_name = directory_name}) or_return
	file, problem := read_world_file(directory, context.temp_allocator)
	if file.format_version == 0 || (problem != "" && file.format_version == SAVE_FORMAT_VERSION) {
		return {}, false
	}
	load_problem := problem != "" ? problem : entities_header_problem(directory, expected)
	return Save_Summary {
			directory_name = strings.clone(directory_name),
			name = strings.clone(file.name),
			seed = file.seed,
			tick = file.tick,
			last_played_unix_seconds = file.last_played_unix_seconds,
			loadable = load_problem == "",
			load_problem = strings.clone(load_problem),
			terrain_changed = file.generator_version < GENERATOR_VERSION,
		},
		true
}

// Replaces the list with the saves in the directory, newest first.
list_saves :: proc(saves: ^[dynamic]Save_Summary, saves_directory: string, expected: Save_Header) {
	destroy_save_summaries(saves)
	entries, error := os.read_all_directory_by_path(saves_directory, context.temp_allocator)
	if error != nil {
		return
	}
	for entry in entries {
		directory_name, is_save := save_directory_of_entry(entry.name)
		if entry.type != .Directory || !is_save || contains_directory_name(saves[:], directory_name) {
			continue
		}
		if summary, ok := read_save_summary(saves_directory, directory_name, expected); ok {
			append(saves, summary)
		}
	}
	slice.sort_by(saves[:], save_summary_before)
}

// Removes the save and any staging or previous directory beside it.
delete_save :: proc(saves_directory, directory_name: string) -> os.Error {
	target := join_save_path(saves_directory, directory_name)
	for path in ([?]string{target, strings.concatenate({target, PREVIOUS_DIRECTORY_SUFFIX}, context.temp_allocator), strings.concatenate({target, STAGING_DIRECTORY_SUFFIX}, context.temp_allocator)}) {
		if os.exists(path) {
			os.remove_all(path) or_return
		}
	}
	return nil
}

// Hours and minutes of simulated time.
play_time_text :: proc(tick: u64, tick_rate: int) -> string {
	minutes := tick / u64(max(tick_rate, 1)) / 60
	return fmt.tprintf("%d:%02d", minutes / 60, minutes % 60)
}

// In the zone given, UTC for nil.
date_text :: proc(unix_seconds: i64, zone: ^datetime.TZ_Region) -> string {
	utc, ok := time.time_to_datetime(time.unix(unix_seconds, 0))
	if !ok {
		return ""
	}
	local := timezone.datetime_to_tz(utc, zone) or_else utc
	return fmt.tprintf("%04d-%02d-%02d %02d:%02d", local.year, local.month, local.day, local.hour, local.minute)
}
