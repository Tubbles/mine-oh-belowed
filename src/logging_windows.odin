#+build windows
package game

import "core:os"

// The Windows side of logging.odin (work item 0102): the console lines go
// to stderr as they are, stderr is never redirected and no signal handler
// is installed, so a fatal signal leaves no raw back trace. The assertion
// back trace of logging.odin still works. No posix package here: its
// import alone links the static C runtime (libucrt.lib), which clashes
// with raylib's release library, built for the dynamic one.

redirect_stderr_to_log :: proc(file: ^os.File) {}

write_console :: proc(text: string) {
	os.write_string(os.stderr, text)
}

restore_default_trap_signal :: proc() {}

install_crash_handlers :: proc() {}
