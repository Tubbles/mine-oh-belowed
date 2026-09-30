#+build !windows
package game

import "core:c"
import "core:os"
import "core:sys/posix"

// The POSIX side of logging.odin: the stderr redirect and the crash
// signal handlers (work item 0043). Excluded from the Windows build by the
// tag above, since core:sys/posix links the static C runtime there (work
// item 0102).

Console_State :: struct {
	// The log file's descriptor, for the signal handler, which has no
	// context.
	log_descriptor:    posix.FD,
	// stderr was pointed at the log file; original_stderr is where
	// stderr went before.
	stderr_redirected: bool,
	original_stderr:   posix.FD,
}

global_console: Console_State

// Remembers the log file's descriptor for the signal handler. Then, only
// when stderr is not a terminal (someone running the game in a terminal
// keeps seeing its output there), points stderr at the log file.
redirect_stderr_to_log :: proc(file: ^os.File) {
	global_console.log_descriptor = posix.FD(os.fd(file))
	if global_console.stderr_redirected {
		point_redirected_stderr_at_log()
		return
	}
	if posix.isatty(posix.STDERR_FILENO) {
		return
	}
	original := posix.dup(posix.STDERR_FILENO)
	if original == -1 || posix.dup2(global_console.log_descriptor, posix.STDERR_FILENO) == -1 {
		write_log_line(global_log.file, "error: cannot point stderr at the log, runtime errors will not be logged")
		if original != -1 {
			posix.close(original)
		}
		return
	}
	global_console.original_stderr = original
	global_console.stderr_redirected = true
}

// A second main in the same process (Android, work item 0116): stderr
// still holds the previous run's log (close_log_file closed only its own
// descriptor), and original_stderr is still the stderr from before the
// first redirect, so only stderr moves to the new log. When that fails,
// stderr stays on the previous run's log, the same path opened for append,
// so runtime errors still land in the log.
point_redirected_stderr_at_log :: proc() {
	if posix.dup2(global_console.log_descriptor, posix.STDERR_FILENO) == -1 {
		write_log_line(global_log.file, "error: cannot point stderr at the new log, it stays on the previous one")
	}
}

// The game's own output for a person or a script: stderr, or what stderr
// was before the redirect.
console_descriptor :: proc "contextless" () -> posix.FD {
	return global_console.stderr_redirected ? global_console.original_stderr : posix.STDERR_FILENO
}

write_console :: proc(text: string) {
	posix.write(console_descriptor(), raw_data(text), len(text))
}

// Before the trap in log_assertion_failure: the trap raises SIGILL, and
// the trace already says it all.
restore_default_trap_signal :: proc() {
	posix.signal(.SIGILL, auto_cast posix.SIG_DFL)
}

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	backtrace :: proc(buffer: [^]rawptr, size: c.int) -> c.int ---
	backtrace_symbols_fd :: proc(buffer: [^]rawptr, size: c.int, file_descriptor: c.int) ---
}

CRASH_SIGNAL_TEXT :: "crash: fatal signal (SIGSEGV or SIGILL), raw back trace:\n"
CRASH_SIGNAL_FRAMES :: 64

write_crash_signal_trace :: proc "c" (file_descriptor: posix.FD, frames: []rawptr) {
	message := CRASH_SIGNAL_TEXT
	posix.write(file_descriptor, raw_data(message), len(message))
	backtrace_symbols_fd(raw_data(frames), c.int(len(frames)), c.int(file_descriptor))
}

// Uses only calls that do not allocate: backtrace was loaded at install
// time and backtrace_symbols_fd writes straight to the descriptor.
// SA_RESETHAND has restored the default action, so the raised signal
// ends the process (with a core dump, as without the handler) once the
// handler returns.
crash_signal_handler :: proc "c" (signal: posix.Signal) {
	frames: [CRASH_SIGNAL_FRAMES]rawptr
	count := backtrace(&frames[0], CRASH_SIGNAL_FRAMES)
	write_crash_signal_trace(console_descriptor(), frames[:count])
	if global_log.file != nil {
		write_crash_signal_trace(global_console.log_descriptor, frames[:count])
	}
	posix.raise(signal)
}

// Not on Android (work item 0114): bionic's sigaction struct puts sa_flags
// first while core:sys/posix follows glibc with the handler first, so the
// call installed SIG_DFL with stray flags (logcat, 2026-09-30), and the
// back trace is a stub there anyway. Android's own crash reporter writes
// the native trace to logcat.
install_crash_handlers :: proc() {
	when ODIN_PLATFORM_SUBTARGET != .Android {
		// The first backtrace call loads libgcc, which allocates; do that
		// here rather than inside the handler.
		frames: [1]rawptr
		backtrace(&frames[0], 1)
		action := posix.sigaction_t {
			sa_handler = crash_signal_handler,
			sa_flags   = {.RESETHAND},
		}
		posix.sigemptyset(&action.sa_mask)
		posix.sigaction(.SIGSEGV, &action, nil)
		posix.sigaction(.SIGILL, &action, nil)
	}
}
