package game

import "base:runtime"
import "core:debug/trace"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

// The lines the game prints to stderr ("input:", "world:", "strings:",
// "error:") also go to $XDG_STATE_HOME/mine-oh-belowed/log.txt (on
// Windows log.txt beside the executable, work item 0103: GameNative's Wine
// container is out of reach of the phone's file manager, the unzipped
// folder is not), appended, with one header line per start. Before
// open_log_file (and when it fails) only stderr gets them. Chunk workers
// can report missing strings, hence the mutex. raylib's trace log takes
// the same path (raylib_log.odin).
//
// Crash traces (work item 0043). Steam discards stderr, where Odin's
// runtime reports bounds check and type assertion failures before it
// traps. So when stderr is not a terminal, open_log_file points stderr at
// the log file (dup2) and keeps a copy of the original stderr, where the
// game's own lines still go (a pipe or a script still sees them), while
// the runtime's messages land in the log only. Every line reaches the log
// once either way. Assertions and panics of the main thread go through
// log_assertion_failure, which adds a back trace. SIGSEGV and SIGILL (the
// trap) print a raw back trace from the signal handler, then the signal
// ends the process as before. The descriptors, the redirect and the
// signal handlers live in logging_posix.odin; on Windows
// (logging_windows.odin, work item 0102) the console lines go to stderr as
// they are, with no redirect and no signal handlers. Build tags, not a
// `when` block: the posix package links the static C runtime on Windows
// by its import alone, so only a build tag keeps it out. On Android (work
// item 0114) every line also goes to logcat (platform_android.odin), where
// adb logcat -s mine-oh-belowed shows it.

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
		BUILD_STAMP,
		date_time.year,
		date_time.month,
		date_time.day,
		date_time.hour,
		date_time.minute,
		date_time.second,
	)
}

// The directory log.txt goes into: the executable's on Windows, the state
// home elsewhere.
platform_log_directory :: proc(allocator := context.allocator) -> (directory: string, ok: bool) {
	when ODIN_OS == .Windows {
		executable_directory, error := os.get_executable_directory(allocator)
		return executable_directory, error == nil
	} else {
		directories := platform_directories(context.temp_allocator)
		return log_directory_from_environment(directories.state_home, directories.home, allocator)
	}
}

// A log file that cannot be opened is reported once and the game goes on
// with stderr only.
open_log_file :: proc() {
	directory, found := platform_log_directory(context.temp_allocator)
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
	redirect_stderr_to_log(file)
}

open_log_for_append :: proc(directory, path: string) -> (^os.File, os.Error) {
	if error := os.make_directory_all(directory); error != nil && error != .Exist {
		return nil, error
	}
	return os.open(path, {.Write, .Append, .Create})
}

// After a redirect, stderr keeps the log file open until the process
// ends, so the runtime's last words still land in it.
close_log_file :: proc() {
	if global_log.file != nil {
		os.close(global_log.file)
		global_log.file = nil
	}
}

write_log_line :: proc(file: ^os.File, line: string) {
	os.write_strings(file, line, "\n")
}

// fmt.eprintfln (to the original stderr after a redirect) plus the log
// file.
// While a data reload loads the game data (data_reload.odin), the last
// "error: " line this thread logged, without the prefix, in the temp
// allocator, so the reload can name the file and the problem in a toast.
// Thread local: tests log from several threads.
@(thread_local)
captured_log_error: ^string

log_printf :: proc(format: string, arguments: ..any) {
	line := fmt.tprintf(format, ..arguments)
	if captured_log_error != nil && strings.has_prefix(line, "error: ") {
		captured_log_error^ = line[len("error: "):]
	}
	sync.mutex_lock(&global_log.mutex)
	defer sync.mutex_unlock(&global_log.mutex)
	write_console(fmt.tprintf("%s\n", line))
	when ODIN_PLATFORM_SUBTARGET == .Android {
		write_logcat(line)
	}
	if global_log.file != nil {
		write_log_line(global_log.file, line)
	}
}

// Crash traces.

// One line, like the runtime's own report, marked for grepping the log.
// In the temp allocator.
assertion_failure_text :: proc(prefix, message: string, location: runtime.Source_Code_Location) -> string {
	where_text := fmt.tprintf("%s(%d:%d) in %s", location.file_path, location.line, location.column, location.procedure)
	if message == "" {
		return fmt.tprintf("crash: %s: %s", where_text, prefix)
	}
	return fmt.tprintf("crash: %s: %s: %s", where_text, prefix, message)
}

// "\t#<n> <procedure> at <file>(<line>)" per frame, a line each. In the
// temp allocator.
back_trace_text :: proc(locations: []trace.Location) -> string {
	lines := make([dynamic]string, context.temp_allocator)
	append(&lines, "back trace:\n")
	for location, index in locations {
		line_text := location.line > 0 ? fmt.tprintf("(%d)", location.line) : ""
		append(&lines, fmt.tprintf("\t#%d %s at %s%s\n", index, location.procedure, location.file_path, line_text))
	}
	return strings.concatenate(lines[:], context.temp_allocator)
}

// Without the mutex: the failing code may hold it.
write_crash_text :: proc(crash_text: string) {
	write_console(crash_text)
	if global_log.file != nil {
		os.write_string(global_log.file, crash_text)
	}
}

// context.assertion_failure_proc of the main thread: assert, panic,
// unimplemented and unreachable report here, with a back trace, then trap.
// Threads the game starts keep the runtime's default, which still reaches
// the log through stderr.
log_assertion_failure :: proc(prefix, message: string, location: runtime.Source_Code_Location) -> ! {
	write_crash_text(fmt.tprintf("%s\n", assertion_failure_text(prefix, message, location)))
	locations, error := trace.resolve(trace.capture(skip = 1), context.temp_allocator, context.temp_allocator)
	if error == nil {
		write_crash_text(back_trace_text(locations))
	} else {
		write_crash_text(fmt.tprintf("no back trace: %s\n", trace.resolve_err_string(error)))
	}
	restore_default_trap_signal()
	runtime.trap()
}
