package game

import "core:fmt"
import "core:os"
import "core:sync"
import "core:time"

// The lines the game prints to stderr ("input:", "world:", "strings:",
// "error:") also go to $XDG_STATE_HOME/mine-oh-belowed/log.txt, appended,
// with one header line per start. Before open_log_file (and when it fails)
// only stderr gets them. Chunk workers can report missing strings, hence
// the mutex.

LOG_FILE_NAME :: "log.txt"
STATE_HOME_UNDER_HOME :: ".local/state"
GAME_DIRECTORY_NAME :: "mine-oh-belowed"

Log_State :: struct {
	mutex: sync.Mutex,
	file:  ^os.File,
}

global_log: Log_State

// $XDG_STATE_HOME (only when absolute) or $HOME/.local/state, then the
// game's directory.
log_directory_from_environment :: proc(state_home, home: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	switch {
	case state_home != "" && os.is_absolute_path(state_home):
		joined, error := os.join_path({state_home, GAME_DIRECTORY_NAME}, allocator)
		return joined, error == nil
	case home != "":
		joined, error := os.join_path({home, STATE_HOME_UNDER_HOME, GAME_DIRECTORY_NAME}, allocator)
		return joined, error == nil
	}
	return "", false
}

log_session_header :: proc(now: time.Time) -> string {
	date_time, _ := time.time_to_datetime(now)
	return fmt.tprintf(
		"--- Mine oh Belowed %s started %04d-%02d-%02d %02d:%02d:%02d UTC ---",
		GAME_VERSION,
		date_time.year,
		date_time.month,
		date_time.day,
		date_time.hour,
		date_time.minute,
		date_time.second,
	)
}

// A log file that cannot be opened is reported once and the game goes on
// with stderr only.
open_log_file :: proc() {
	directory, found := log_directory_from_environment(os.get_env("XDG_STATE_HOME", context.temp_allocator), os.get_env("HOME", context.temp_allocator), context.temp_allocator)
	if !found {
		return
	}
	path, _ := os.join_path({directory, LOG_FILE_NAME}, context.temp_allocator)
	file, error := open_log_for_append(directory, path)
	if error != nil {
		fmt.eprintfln("error: cannot open the log %s: %v", path, error)
		return
	}
	global_log.file = file
	write_log_line(global_log.file, log_session_header(time.now()))
}

open_log_for_append :: proc(directory, path: string) -> (^os.File, os.Error) {
	if error := os.make_directory_all(directory); error != nil && error != .Exist {
		return nil, error
	}
	return os.open(path, {.Write, .Append, .Create})
}

close_log_file :: proc() {
	if global_log.file != nil {
		os.close(global_log.file)
		global_log.file = nil
	}
}

write_log_line :: proc(file: ^os.File, line: string) {
	os.write_strings(file, line, "\n")
}

// fmt.eprintfln plus the log file.
log_printf :: proc(format: string, arguments: ..any) {
	line := fmt.tprintf(format, ..arguments)
	sync.mutex_lock(&global_log.mutex)
	defer sync.mutex_unlock(&global_log.mutex)
	fmt.eprintln(line)
	if global_log.file != nil {
		write_log_line(global_log.file, line)
	}
}
